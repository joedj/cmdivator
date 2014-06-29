typedef void (^CmdivatorScannerCallback)(NSSet *urls);

@interface CmdivatorScanner: NSObject
- (void)startWithCallback:(CmdivatorScannerCallback)callback;
- (void)scan;
- (void)stop;
@end
