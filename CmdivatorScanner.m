#import "CmdivatorScanner.h"
#import "Common.h"

#define SYSTEM_COMMANDS_DIRECTORY @"/Library/Cmdivator/Cmds"
#define USER_COMMANDS_DIRECTORY  (@"~/Library/Cmdivator/Cmds".stringByExpandingTildeInPath)
#define COMMANDS_DIRECTORY_MAXDEPTH 20
#define FS_EVENT_SCAN_DELAY_SECONDS 3
#define FALLBACK_SCAN_INTERVAL_SECONDS 43200

@implementation CmdivatorScanner {
    CmdivatorScannerCallback _callback;
    NSTimer *_timer;
    NSArray *_dirs;
    NSMutableArray *_sources;
    NSMutableArray *_eventFds;
}

- (void)startWithCallback:(CmdivatorScannerCallback)callback {
    [self stop];
    _callback = callback;
    _dirs = @[SYSTEM_COMMANDS_DIRECTORY, USER_COMMANDS_DIRECTORY];
    _sources = [[NSMutableArray alloc] init];
    _eventFds = [[NSMutableArray alloc] init];

    NSError * __autoreleasing error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:USER_COMMANDS_DIRECTORY withIntermediateDirectories:YES attributes:nil error:&error]) {
        LOG(@"Unable to create user commands directory %@: %@", USER_COMMANDS_DIRECTORY, error);
    }

    for (NSString *dir in _dirs) {
        int eventFd = open(dir.fileSystemRepresentation, O_EVTONLY);
        if (eventFd >= 0) {
            dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, eventFd, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
            if (source) {
                [_sources addObject:[NSValue valueWithPointer:source]];
                [_eventFds addObject:@(eventFd)];
                CmdivatorScanner * __weak w_self = self;
                dispatch_source_set_event_handler(source, ^{
                    [w_self scheduleScan:FS_EVENT_SCAN_DELAY_SECONDS];
                });
                dispatch_resume(source);
            } else {
                LOG(@"dispatch_source_create: %@", dir);
                close(eventFd);
            }
        } else {
            LOG(@"Unable to watch commands directory %@: [%i] %s", dir, errno, strerror(errno));
        }
    }

    [self scan];
}

- (void)stop {
    _callback = nil;

    [_timer invalidate];
    _timer = nil;

    for (NSValue *sourceValue in _sources) {
        dispatch_source_t source = sourceValue.pointerValue;
        dispatch_source_cancel(source);
        dispatch_release(source);
    }
    _sources = nil;

    for (NSNumber *eventFd in _eventFds) {
        close(eventFd.intValue);
    }
    _eventFds = nil;
}

- (void)dealloc {
    [self stop];
}

- (void)scan {
    [_timer invalidate];
    _timer = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableSet *urls = [[NSMutableSet alloc] init];
        for (NSString *dir in _dirs) {
            NSURL *dirURL = [[NSURL fileURLWithPath:dir] URLByResolvingSymlinksInPath];
            [urls addObjectsFromArray:[self scanForCommandsAtURL:dirURL depth:0]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_callback) {
                _callback(urls);
                [self scheduleScan:FALLBACK_SCAN_INTERVAL_SECONDS];
            }
        });
    });
}

- (void)scheduleScan:(NSUInteger)seconds {
    [_timer invalidate];
    _timer = nil;
    if (_callback) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:seconds target:self selector:@selector(scan) userInfo:nil repeats:NO];
    }
}

- (NSArray *)scanForCommandsAtURL:(NSURL *)commandsURL depth:(unsigned int)depth {
    if (depth == COMMANDS_DIRECTORY_MAXDEPTH) {
        LOG(@"Error while scanning filesystem: at %@: Reached max depth: %u", commandsURL, depth);
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

    NSMutableArray *urls = [[NSMutableArray alloc] init];
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
                [urls addObjectsFromArray:[self scanForCommandsAtURL:url depth:depth + 1]];
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
                [urls addObject:url];
            }
        }
    }
    return urls;
}

@end
