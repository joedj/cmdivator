#import <libactivator/libactivator.h>
#import <spawn.h>

#define LOG(fmt, ...) NSLog(@"Cmdivator: " fmt, ##__VA_ARGS__)
#define COMMANDS_DIRECTORY (@"~/Library/Cmdivator/Cmds".stringByExpandingTildeInPath)

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

- (NSString *)name {
    return _url.lastPathComponent;
}

- (NSString *)displayPath {
    return _url.path.stringByAbbreviatingWithTildeInPath;
}

- (NSString *)listenerName {
    return [@"net.joedj.cmdivator.action.user." stringByAppendingString:_url.path];
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
                    LOG(@"Unable to set POSIX_SPAWN_CLOEXEC_DEFAULT: [%i] %s", ret, strerror(ret));
                }
            } else {
                LOG(@"Unable to posix_spawnattr_init: [%i] %s", ret, strerror(ret));
            }
            if (!(ret = posix_spawn_file_actions_init(&cmd_spawn_file_actions))) {
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDOUT_FILENO))) {
                    LOG(@"Unable to posix_spawn_file_actions_addinherit_np(STDOUT): [%i] %s", ret, strerror(ret));
                }
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDERR_FILENO))) {
                    LOG(@"Unable to posix_spawn_file_actions_addinherit_np(STDERR): [%i] %s", ret, strerror(ret));
                }
            } else {
                LOG(@"Unable to posix_spawn_file_actions_init: [%i] %s", ret, strerror(ret));
            }
        });

        LOG(@"Running %@ for event %@", path, event);
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
                LOG(@"Unable to waitpid %i: [%i] %s", pid, errno, strerror(errno));
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
    int _eventFd;
    dispatch_source_t _commandsDirectorySource;
    NSMutableDictionary *_listeners;
}

+ (void)load {
    @autoreleasepool {
        static Cmdivator *cmdivator = nil;
        cmdivator = [[Cmdivator alloc] init];
    }
}

- (instancetype)init {
    if ((self = [super init])) {

        _listeners = [[NSMutableDictionary alloc] init];

        NSError * __autoreleasing error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:COMMANDS_DIRECTORY withIntermediateDirectories:YES attributes:nil error:&error]) {
            LOG(@"Unable to create user commands directory %@: %@", COMMANDS_DIRECTORY, error);
        }
        _eventFd = open(COMMANDS_DIRECTORY.fileSystemRepresentation, O_EVTONLY);
        if (_eventFd >= 0) {
            _commandsDirectorySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, _eventFd, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
            if (_commandsDirectorySource) {
                Cmdivator * __weak w_self = self;
                dispatch_source_set_event_handler(_commandsDirectorySource, ^{
                    [w_self scheduleFilesystemScan:5];
                });
                dispatch_resume(_commandsDirectorySource);
            } else {
                LOG(@"Unable to create commands directory event source.");
                close(_eventFd);
                _eventFd = -1;
            }
        } else {
            LOG(@"Unable to watch commands directory: [%i] %s", errno, strerror(errno));
        }
        [self scheduleFilesystemScan:5];

    }
    return self;
}

- (void)registerListeners {
    for (NSString *listenerName in _listeners) {
        [LASharedActivator registerListener:self forName:listenerName];
    }
}

- (void)unregisterListeners {
    for (NSString *listenerName in _listeners) {
        [LASharedActivator unregisterListenerWithName:listenerName];
    }
    _listeners = [[NSMutableDictionary alloc] init];
}

- (void)dealloc {
    if (_commandsDirectorySource) {
        dispatch_source_cancel(_commandsDirectorySource);
    }
    if (_eventFd >= 0) {
        close(_eventFd);
    }
}

- (void)scheduleFilesystemScan:(NSUInteger)seconds {
    [_filesystemScanTimer invalidate];
    _filesystemScanTimer = [NSTimer scheduledTimerWithTimeInterval:seconds target:self selector:@selector(scanFilesystem) userInfo:nil repeats:NO];
}

- (void)scanFilesystem {
    [_filesystemScanTimer invalidate];
    _filesystemScanTimer = nil;

    [self unregisterListeners];

    NSDirectoryEnumerator *dirEnumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:COMMANDS_DIRECTORY]
        includingPropertiesForKeys:@[NSURLNameKey, NSURLIsExecutableKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey]
        options:0
        errorHandler:^(NSURL *url, NSError *error) {
            LOG(@"Error while scanning filesystem for new commands: at %@: %@", url, error);
            return YES;
        }
    ];

    for (NSURL * __strong url in dirEnumerator) {
        NSError * __autoreleasing error = nil;

        NSNumber *isSymlink = nil;
        if (![url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:&error]) {
            LOG(@"Error while scanning filesystem for new commands: NSURLIsSymbolicLinkKey: at %@: %@", url, error);
            continue;
        } else if (isSymlink.boolValue) {
            url = url.URLByResolvingSymlinksInPath;
            // TODO: could scan recursively here if we found a symlink to a directory, up to some maxdepth
        }

        url = url.URLByStandardizingPath;

        NSNumber *isRegularFile = nil;
        if (![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error]) {
            LOG(@"Error while scanning filesystem for new commands: NSURLIsRegularFileKey: at %@: %@", url, error);
            continue;
        } else if (isRegularFile.boolValue) {

            NSNumber *isExecutable = nil;
            if (![url getResourceValue:&isExecutable forKey:NSURLIsExecutableKey error:&error]) {
                LOG(@"Error while scanning filesystem for new commands: NSURLIsExecutableKey: at %@: %@", url, error);
                continue;
            } else if (isExecutable.boolValue) {

                CmdivatorCmd *cmd = [[CmdivatorCmd alloc] initWithURL:url];
                _listeners[cmd.listenerName] = cmd;

            }

        }

    }

    [self registerListeners];
    [self scheduleFilesystemScan:43200];
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
