#import "CmdivatorDirectoryEnumerator.h"
#import "Common.h"

@implementation CmdivatorDirectoryEnumerator {
    NSUInteger _maxDepth;
    NSArray *_keys;
}

- (instancetype)initWithMaxDepth:(NSUInteger)maxDepth includePropertiesForKeys:(NSArray *)keys {
    if ((self = [super init])) {
        _maxDepth = maxDepth;
        NSMutableArray *allKeys = [NSMutableArray arrayWithObjects:NSURLNameKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, nil];
        [allKeys addObjectsFromArray:keys];
        _keys = allKeys;
    }
    return self;
}

- (void)enumerateFilesAtURL:(NSURL *)url callback:(CmdivatorDirectoryEnumeratorCallback)callback {
    [self enumerateFilesAtURL:url callback:callback depth:0];
}

- (void)enumerateFilesAtURL:(NSURL *)url callback:(CmdivatorDirectoryEnumeratorCallback)callback depth:(NSUInteger)depth {
    if (depth >= _maxDepth) {
        LOG(@"Error while scanning filesystem: at %@: Reached max depth: %lu", url, (unsigned long)depth);
        return;
    }

    NSDirectoryEnumerator *dirEnumerator = [NSFileManager.defaultManager enumeratorAtURL:url
        includingPropertiesForKeys:_keys
        options:0
        errorHandler:^(NSURL *url, NSError *error) {
            LOG(@"Error while scanning filesystem: at %@: %@", url, error);
            return YES;
        }
    ];

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
                [self enumerateFilesAtURL:url callback:callback depth:depth + 1];
            }
        }

        url = url.URLByStandardizingPath;
        NSNumber *isRegularFile = nil;
        if (![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error]) {
            LOG(@"Error while scanning filesystem: NSURLIsRegularFileKey: at %@: %@", url, error);
        } else if (isRegularFile.boolValue) {
            callback(url);
        }
    }
}

@end
