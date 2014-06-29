#import <AppSupport/CPDistributedMessagingCenter.h>
#import <libactivator/libactivator.h>
#import <notify.h>

#import "CmdivatorCmd.h"
#import "CmdivatorScanner.h"
#import "Common.h"

#define ACTIVATOR_GROUP @"Cmdivator"

@interface Cmdivator: NSObject <LAListener>
@end

@implementation Cmdivator {
    NSMutableDictionary *_listeners;
    NSMutableDictionary *_icons;
    CmdivatorScanner *_scanner;
    CPDistributedMessagingCenter *_messagingCenter;
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
        _icons = [[NSMutableDictionary alloc] init];

        _scanner = [[CmdivatorScanner alloc] init];
        Cmdivator * __weak w_self = self;
        [_scanner startWithCallback:^(NSSet *urls) {
            [w_self replaceCommandsWithURLs:urls];
        }];

        _messagingCenter = [CPDistributedMessagingCenter centerNamed:MESSAGE_CENTER_NAME];
        [_messagingCenter registerForMessageName:@"listCommands" target:self selector:@selector(listCommands)];
        [_messagingCenter registerForMessageName:@"refreshCommands" target:self selector:@selector(refreshCommands)];
        [_messagingCenter runServerOnCurrentThread];

        [NSNotificationCenter.defaultCenter addObserver:self
            selector:@selector(didReceiveMemoryWarning:)
            name:UIApplicationDidReceiveMemoryWarningNotification
            object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
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
    notify_post(COMMANDS_CHANGED_NOTIFICATION);
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

- (NSData *)activator:(LAActivator *)activator requiresSmallIconDataForListenerName:(NSString *)listenerName scale:(CGFloat *)scale {
    NSData *icon = _icons[@(*scale)];
    if (!icon) {
        if (*scale == 1.0) {
            icon = [NSData dataWithContentsOfFile:@"/Library/PreferenceBundles/Cmdivator.bundle/Icon.png"];
        } else {
            *scale = 2.0;
            icon = [NSData dataWithContentsOfFile:@"/Library/PreferenceBundles/Cmdivator.bundle/Icon@2x.png"];
        }
        _icons[@(*scale)] = icon;
    }
    return icon;
}

- (NSDictionary *)listCommands {
    NSArray *sortedCommands = [_listeners.allValues sortedArrayUsingComparator:^NSComparisonResult(CmdivatorCmd *cmd1, CmdivatorCmd *cmd2) {
        return [cmd1.displayName caseInsensitiveCompare:cmd2.displayName];
    }];
    return @{ @"commands" : [sortedCommands valueForKey:@"dictionary"] };
}

- (void)refreshCommands {
    [_scanner scan];
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    [_icons removeAllObjects];
}

@end
