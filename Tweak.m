#import <libactivator/libactivator.h>
#import <spawn.h>

#define LOG(fmt, ...) NSLog(@"Cmdivator: " fmt, ##__VA_ARGS__)

#define SYSTEM_COMMANDS_DIRECTORY @"/Library/Cmdivator/Cmds"
#define USER_COMMANDS_DIRECTORY  (@"~/Library/Cmdivator/Cmds".stringByExpandingTildeInPath)
#define COMMANDS_DIRECTORY_MAXDEPTH 20

@interface CmdivatorCmd: NSObject
@property (retain, nonatomic) NSURL *url;
- (NSString *)name;
- (NSString *)displayPath;
- (void)runForEvent:(LAEvent *)event;
@end

@implementation CmdivatorCmd

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
    }
    return self;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [_url isEqual:((CmdivatorCmd *)other)->_url];
}

- (NSUInteger)hash {
    return _url.hash;
}

- (NSString *)name {
    return _url.lastPathComponent;
}

- (NSString *)displayPath {
    return _url.path.stringByAbbreviatingWithTildeInPath;
}

- (NSString *)listenerName {
    return [@"net.joedj.cmdivator.listener:" stringByAppendingString:_url.path];
}

- (void)runForEvent:(LAEvent *)event {
    NSString *path = _url.path;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        static posix_spawn_file_actions_t cmd_spawn_file_actions;
        static posix_spawnattr_t cmd_spawnattr;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            int ret;
            if (!(ret = posix_spawnattr_init(&cmd_spawnattr))) {
                if ((ret = posix_spawnattr_setflags(&cmd_spawnattr, POSIX_SPAWN_CLOEXEC_DEFAULT))) {
                    LOG(@"posix_spawnattr_setflags: [%i] %s", ret, strerror(ret));
                }
            } else {
                LOG(@"posix_spawnattr_init: [%i] %s", ret, strerror(ret));
            }
            if (!(ret = posix_spawn_file_actions_init(&cmd_spawn_file_actions))) {
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDOUT_FILENO))) {
                    LOG(@"posix_spawn_file_actions_addinherit_np(%i): [%i] %s", STDOUT_FILENO, ret, strerror(ret));
                }
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDERR_FILENO))) {
                    LOG(@"posix_spawn_file_actions_addinherit_np(%i): [%i] %s", STDERR_FILENO, ret, strerror(ret));
                }
            } else {
                LOG(@"posix_spawn_file_actions_init: [%i] %s", ret, strerror(ret));
            }
        });

        static const char *const cmd_argv[] = { "", NULL };
        static char *cmd_envp[] = { NULL };
        pid_t pid;
        int ret;
        if (!(ret = posix_spawn(&pid, path.fileSystemRepresentation, &cmd_spawn_file_actions, &cmd_spawnattr, (char* const*)cmd_argv, (char* const*)cmd_envp))) {
            int status;
            do {
                ret = waitpid(pid, &status, 0);
            } while (ret == -1 && errno == EINTR);
            if (ret == -1) {
                LOG(@"waitpid(%i): [%i] %s", pid, errno, strerror(errno));
            } else if (!(WIFEXITED(status) && WEXITSTATUS(status) == 0)) {
                LOG(@"%@ exited with status: %i", path, status);
            }
        } else {
            LOG(@"Unable to spawn %@ for event %@: %i: %s", path, event, ret, strerror(ret));
        }

    });
}

@end

@interface Cmdivator: NSObject <LAListener>
@end

@implementation Cmdivator {
    NSTimer *_filesystemScanTimer;
    NSArray *_commandDirectories;
    NSMutableArray *_commandDirectorySources;
    NSMutableArray *_eventFds;
    NSMutableDictionary *_listeners;
}

+ (void)load {
    @autoreleasepool {
        static Cmdivator *cmdivator;
        cmdivator = [[Cmdivator alloc] init];
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        _commandDirectories = @[SYSTEM_COMMANDS_DIRECTORY, USER_COMMANDS_DIRECTORY];
        _commandDirectorySources = [[NSMutableArray alloc] init];
        _eventFds = [[NSMutableArray alloc] init];
        _listeners = [[NSMutableDictionary alloc] init];

        NSError * __autoreleasing error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:USER_COMMANDS_DIRECTORY withIntermediateDirectories:YES attributes:nil error:&error]) {
            LOG(@"Unable to create user commands directory %@: %@", USER_COMMANDS_DIRECTORY, error);
        }

        for (NSString *commandDirectory in _commandDirectories) {
            int eventFd = open(commandDirectory.fileSystemRepresentation, O_EVTONLY);
            if (eventFd >= 0) {
                dispatch_source_t commandDirectorySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, eventFd, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
                if (commandDirectorySource) {
                    [_commandDirectorySources addObject:[NSValue valueWithPointer:commandDirectorySource]];
                    [_eventFds addObject:@(eventFd)];
                    Cmdivator * __weak w_self = self;
                    dispatch_source_set_event_handler(commandDirectorySource, ^{
                        [w_self scheduleFilesystemScan:1];
                    });
                    dispatch_resume(commandDirectorySource);
                } else {
                    LOG(@"dispatch_source_create: %@", commandDirectory);
                    close(eventFd);
                }
            } else {
                LOG(@"Unable to watch commands directory %@: [%i] %s", commandDirectory, errno, strerror(errno));
            }
        }

        [self scanFilesystem];
    }
    return self;
}

- (void)replaceCommands:(NSSet *)commands {
    for (NSString *listenerName in _listeners) {
        [LASharedActivator unregisterListenerWithName:listenerName];
    }
    _listeners = [[NSMutableDictionary alloc] init];
    for (CmdivatorCmd *cmd in commands) {
        NSString *listenerName = cmd.listenerName;
        _listeners[listenerName] = cmd;
        [LASharedActivator registerListener:self forName:listenerName];
    }
}

- (void)dealloc {
    for (NSValue *commandDirectorySource in _commandDirectorySources) {
        dispatch_source_t source = commandDirectorySource.pointerValue;
        dispatch_source_cancel(source);
        dispatch_release(source);
    }

    for (NSNumber *eventFd in _eventFds) {
        close(eventFd.intValue);
    }

    [self replaceCommands:nil];
}

- (void)scheduleFilesystemScan:(NSUInteger)seconds {
    [_filesystemScanTimer invalidate];
    _filesystemScanTimer = [NSTimer scheduledTimerWithTimeInterval:seconds target:self selector:@selector(scanFilesystem) userInfo:nil repeats:NO];
}

- (NSArray *)scanForCommandsAtURL:(NSURL *)commandsURL depth:(NSUInteger)depth {
    if (depth == COMMANDS_DIRECTORY_MAXDEPTH) {
        LOG(@"Error while scanning filesystem: at %@: Reached max depth: %lu", commandsURL, (unsigned long)depth);
        return nil;
    }

    NSDirectoryEnumerator *dirEnumerator = [NSFileManager.defaultManager enumeratorAtURL:commandsURL
        includingPropertiesForKeys:@[NSURLNameKey, NSURLIsExecutableKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey]
        options:0
        errorHandler:^(NSURL *url, NSError *error) {
            LOG(@"Error while scanning filesystem: at %@: %@", url, error);
            return YES;
        }
    ];

    NSMutableArray *cmds = [[NSMutableArray alloc] init];
    for (NSURL * __strong url in dirEnumerator) {
        NSError * __autoreleasing error = nil;

        NSNumber *isSymlink = nil;
        if (![url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:&error]) {
            LOG(@"Error while scanning filesystem: NSURLIsSymbolicLinkKey: at %@: %@", url, error);
            continue;
        } else if (isSymlink.boolValue) {
            url = url.URLByResolvingSymlinksInPath;
            NSNumber *isDirectory = nil;
            if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
                LOG(@"Error while scanning filesystem: NSURLIsDirectoryKey: at %@: %@", url, error);
            } else if (isDirectory.boolValue) {
                [cmds addObjectsFromArray:[self scanForCommandsAtURL:url depth:depth + 1]];
            }
        }

        url = url.URLByStandardizingPath;
        NSNumber *isRegularFile = nil;
        if (![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error]) {
            LOG(@"Error while scanning filesystem: NSURLIsRegularFileKey: at %@: %@", url, error);
        } else if (isRegularFile.boolValue) {
            NSNumber *isExecutable = nil;
            if (![url getResourceValue:&isExecutable forKey:NSURLIsExecutableKey error:&error]) {
                LOG(@"Error while scanning filesystem: NSURLIsExecutableKey: at %@: %@", url, error);
            } else if (isExecutable.boolValue) {
                CmdivatorCmd *cmd = [[CmdivatorCmd alloc] initWithURL:url];
                [cmds addObject:cmd];
            }
        }
    }
    return cmds;
}

- (void)scanFilesystem {
    [_filesystemScanTimer invalidate];
    _filesystemScanTimer = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableSet *cmds = [[NSMutableSet alloc] init];
        for (NSString *commandDirectory in _commandDirectories) {
            NSURL *commandDirectoryURL = [[NSURL fileURLWithPath:commandDirectory] URLByResolvingSymlinksInPath];
            [cmds addObjectsFromArray:[self scanForCommandsAtURL:commandDirectoryURL depth:0]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self replaceCommands:cmds];
            [self scheduleFilesystemScan:43200];
        });
    });
}

- (void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event forListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    event.handled = YES;
    [cmd runForEvent:event];
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedGroupForListenerName:(NSString *)listenerName {
    return @"Cmdivator";
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    return cmd.name;
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedDescriptionForListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    return cmd.displayPath;
}

// - (NSData *)activator:(LAActivator *)activator requiresIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;
// - (NSData *)activator:(LAActivator *)activator requiresSmallIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;

@end
