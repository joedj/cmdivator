typedef void (^CmdivatorDirectoryEnumeratorCallback)(NSURL *url);

@interface CmdivatorDirectoryEnumerator: NSObject
- (instancetype)initWithMaxDepth:(NSUInteger)maxDepth includePropertiesForKeys:(NSArray *)keys;
- (void)enumerateFilesAtURL:(NSURL *)url callback:(CmdivatorDirectoryEnumeratorCallback)callback;
@end
