#import <libactivator/libactivator.h>

@interface Cmdivator: NSObject <LAListener>
@end

@implementation Cmdivator

+ (void)load {
    @autoreleasepool {
        static Cmdivator *cmdivator = nil;
        cmdivator = [[Cmdivator alloc] init];
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        [LASharedActivator registerListener:self forName:@"net.joedj.cmdivator.action.test"];
    }
    return self;
}

- (void)dealloc {
    [LASharedActivator unregisterListenerWithName:@"net.joedj.cmdivator.action.test"];
}

- (void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event forListenerName:(NSString *)listenerName {
    NSLog(@"Cmdivator: EVENT: %@", event);
    event.handled = YES;
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedGroupForListenerName:(NSString *)listenerName {
    return @"Cmdivator";
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName {
    return @"Test Action";
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedDescriptionForListenerName:(NSString *)listenerName {
    return @"Testing!";
}

// - (NSData *)activator:(LAActivator *)activator requiresIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;
// - (NSData *)activator:(LAActivator *)activator requiresSmallIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;

@end
