#import <libactivator/libactivator.h>

#import "CmdivatorCmd.h"
#import "CmdivatorScanner.h"
#import "Common.h"

#define ACTIVATOR_GROUP @"Cmdivator"

@interface Cmdivator: NSObject <LAListener>
@end

@implementation Cmdivator {
    NSMutableDictionary *_listeners;
    CmdivatorScanner *_scanner;
}

+ (void)load {
    @autoreleasepool {
        static Cmdivator *cmdivator;
        cmdivator = [[Cmdivator alloc] init];
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        _listeners = [[NSMutableDictionary alloc] init];
        _scanner = [[CmdivatorScanner alloc] init];
        Cmdivator * __weak w_self = self;
        [_scanner startWithCallback:^(NSSet *urls) {
            [w_self replaceCommandsWithURLs:urls];
        }];
    }
    return self;
}

- (void)dealloc {
    [_scanner stop];
    [self replaceCommandsWithURLs:nil];
}

- (void)replaceCommandsWithURLs:(NSSet *)urls {
    for (NSString *listenerName in _listeners) {
        [LASharedActivator unregisterListenerWithName:listenerName];
    }
    _listeners = [[NSMutableDictionary alloc] init];
    for (NSURL *url in urls) {
        CmdivatorCmd *cmd = [[CmdivatorCmd alloc] initWithURL:url];
        NSString *listenerName = cmd.listenerName;
        _listeners[listenerName] = cmd;
        [LASharedActivator registerListener:self forName:listenerName];
    }
}

- (void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event forListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    event.handled = YES;
    [cmd runForEvent:event];
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedGroupForListenerName:(NSString *)listenerName {
    return ACTIVATOR_GROUP;
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    return cmd.displayName;
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedDescriptionForListenerName:(NSString *)listenerName {
    CmdivatorCmd *cmd = _listeners[listenerName];
    return cmd.displayPath;
}

// - (NSData *)activator:(LAActivator *)activator requiresIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;
// - (NSData *)activator:(LAActivator *)activator requiresSmallIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale;

@end
