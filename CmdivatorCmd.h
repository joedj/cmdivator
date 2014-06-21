#import <libactivator/libactivator.h>

@interface CmdivatorCmd: NSObject
- (instancetype)initWithURL:(NSURL *)url;
@property (readonly, nonatomic) NSString *displayName;
@property (readonly, nonatomic) NSString *displayPath;
@property (readonly, nonatomic) NSString *listenerName;
- (void)runForEvent:(LAEvent *)event;
@end
