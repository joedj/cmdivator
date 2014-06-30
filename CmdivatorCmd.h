#import <libactivator/libactivator.h>

@interface CmdivatorCmd: NSObject
- (instancetype)initWithPath:(NSString *)path;
@property (readonly, nonatomic) NSString *path;
@property (readonly, nonatomic) NSString *displayName;
@property (readonly, nonatomic) NSString *displayPath;
@property (readonly, nonatomic) NSString *listenerName;
@property (readonly, nonatomic, getter=isRemovable) BOOL removable;
- (void)runForEvent:(LAEvent *)event;
- (BOOL)delete;
@end
