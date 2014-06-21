#import <libactivator/libactivator.h>

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
    NSLog(@"Running %@ for event %@", _url, event);
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
            NSLog(@"Cmdivator: Unable to create user commands directory %@: %@", COMMANDS_DIRECTORY, error);
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
                NSLog(@"Cmdivator: Unable to create commands directory event source.");
                close(_eventFd);
                _eventFd = -1;
            }
        } else {
            NSLog(@"Cmdivator: Unable to watch commands directory: [%i] %s", errno, strerror(errno));
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
            NSLog(@"Cmdivator: Error while scanning filesystem for new commands: at %@: %@", url, error);
            return YES;
        }
    ];

    for (NSURL * __strong url in dirEnumerator) {
        NSError * __autoreleasing error = nil;

        NSNumber *isSymlink = nil;
        if (![url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:&error]) {
            NSLog(@"Cmdivator: Error while scanning filesystem for new commands: NSURLIsSymbolicLinkKey: at %@: %@", url, error);
            continue;
        } else if (isSymlink.boolValue) {
            url = url.URLByResolvingSymlinksInPath;
            // TODO: could scan recursively here if we found a symlink to a directory, up to some maxdepth
        }

        url = url.URLByStandardizingPath;

        NSNumber *isRegularFile = nil;
        if (![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error]) {
            NSLog(@"Cmdivator: Error while scanning filesystem for new commands: NSURLIsRegularFileKey: at %@: %@", url, error);
            continue;
        } else if (isRegularFile.boolValue) {

            NSNumber *isExecutable = nil;
            if (![url getResourceValue:&isExecutable forKey:NSURLIsExecutableKey error:&error]) {
                NSLog(@"Cmdivator: Error while scanning filesystem for new commands: NSURLIsExecutableKey: at %@: %@", url, error);
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
