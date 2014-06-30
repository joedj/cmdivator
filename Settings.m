#import <AppSupport/CPDistributedMessagingCenter.h>
#import <Preferences/Preferences.h>

#import "Common.h"

@interface CmdivatorCmdCell: PSTableCell
@end

@interface CmdivatorSettingsController: PSListController
@end

@implementation CmdivatorSettingsController {
    CPDistributedMessagingCenter *_messagingCenter;
    BOOL _needsReload;
}

static void commands_changed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CmdivatorSettingsController *controller = (__bridge CmdivatorSettingsController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller scheduleReload];
    });
}

- (instancetype)init {
    if ((self = [super init])) {
        _messagingCenter = [CPDistributedMessagingCenter centerNamed:MESSAGE_CENTER_NAME];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, commands_changed,
            CFSTR(COMMANDS_CHANGED_NOTIFICATION), NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
        CFSTR(COMMANDS_CHANGED_NOTIFICATION), NULL);
}

- (void)scheduleReload {
    if (_specifiers) {
        if (self.isViewLoaded && self.view.window) {
            [self reloadSpecifiers];
        } else {
            _needsReload = YES;
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [self refreshCommands];
    if (_needsReload) {
        _needsReload = NO;
        if (_specifiers) {
            [self reloadSpecifiers];
        }
    }
    [super viewWillAppear:animated];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [[NSMutableArray alloc] init];
        _specifiers = specifiers;

        PSSpecifier *topGroup = PSSpecifier.emptyGroupSpecifier;
        NSString *footerText = [@"Commands are executable files in\r\n" stringByAppendingString:USER_COMMANDS_DIRECTORY.stringByAbbreviatingWithTildeInPath];
        [topGroup setProperty:footerText forKey:@"footerText"];
        [specifiers addObject:topGroup];

        PSSpecifier *refreshButton = [PSSpecifier preferenceSpecifierNamed:@"Refresh" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        refreshButton->action = @selector(refreshCommands);
        [specifiers addObject:refreshButton];

        PSSpecifier *commandsGroup = [PSSpecifier preferenceSpecifierNamed:@"Commands" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specifiers addObject:commandsGroup];

        NSArray *cmds = [_messagingCenter sendMessageAndReceiveReplyName:@"listCommands" userInfo:nil][@"commands"];
        for (NSDictionary *cmd in cmds) {
            PSSpecifier *cmdSpecifier = [PSSpecifier preferenceSpecifierNamed:cmd[@"displayName"] target:self set:nil get:@selector(displayPathForSpecifier:) detail:nil cell:PSLinkListCell edit:nil];
            [cmdSpecifier setProperty:CmdivatorCmdCell.class forKey:@"cellClass"];
            [cmdSpecifier setProperty:cmd[@"listenerName"] forKey:@"activatorListener"];
            [cmdSpecifier setProperty:cmd[@"displayName"] forKey:@"activatorTitle"];
            [cmdSpecifier setProperty:cmd[@"displayPath"] forKey:@"cmdivatorDisplayPath"];
            [cmdSpecifier setProperty:cmd[@"path"] forKey:@"cmdivatorPath"];
            [cmdSpecifier setProperty:[NSBundle bundleWithIdentifier:@"com.libactivator.preferencebundle"].bundlePath forKey:@"lazy-bundle"];
            cmdSpecifier->action = @selector(lazyLoadBundle:);
            [specifiers addObject:cmdSpecifier];
        }
    }
    return _specifiers;
}

- (void)refreshCommands {
    [_messagingCenter sendMessageName:@"refreshCommands" userInfo:nil];
}

- (NSString *)displayPathForSpecifier:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"cmdivatorDisplayPath"];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    int specifierIndex = [self indexOfGroup:indexPath.section] + indexPath.row + 1;
    PSSpecifier *specifier = [_specifiers objectAtIndex:specifierIndex];
    NSString *path = [specifier propertyForKey:@"cmdivatorPath"];
    if (path && [NSFileManager.defaultManager isDeletableFileAtPath:path]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        int specifierIndex = [self indexOfGroup:indexPath.section] + indexPath.row + 1;
        PSSpecifier *specifier = [self specifierAtIndex:specifierIndex];
        NSString *listenerName = [specifier propertyForKey:@"activatorListener"];
        [_messagingCenter sendMessageName:@"deleteCommand" userInfo:@{ @"listenerName" : listenerName }];
    }
}

@end

@implementation CmdivatorCmdCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:NSStringFromClass(self.class) specifier:specifier])) {
        self.textLabel.adjustsFontSizeToFitWidth = YES;
        self.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    }
    return self;
}
@end
