typedef void (^CmdivatorScannerCallback)(NSSet *paths);

@interface CmdivatorScanner: NSObject
- (void)startWithCallback:(CmdivatorScannerCallback)callback;
- (void)scan;
- (void)stop;
@end
