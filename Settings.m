#import <AppSupport/CPDistributedMessagingCenter.h>
#import <libactivator/libactivator.h>
#import <Preferences/Preferences.h>

#import "CmdivatorCmd.h"
#import "Common.h"

@interface CmdivatorCmdCell: PSTableCell
@end

@interface PSSpecifier (Cmdivator)
@property (retain, nonatomic) CmdivatorCmd *cmd;
@end

@interface CmdivatorSettingsController: PSListController
@end

@implementation CmdivatorSettingsController {
    CPDistributedMessagingCenter *_messagingCenter;
}

static void commands_changed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CmdivatorSettingsController *controller = (__bridge CmdivatorSettingsController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadSpecifiersIfVisible];
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

- (void)viewDidLoad {
    UIImage *refreshIcon = [UIImage imageNamed:@"Refresh" inBundle:[NSBundle bundleForClass:self.class]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:refreshIcon
            style:UIBarButtonItemStylePlain target:self action:@selector(refreshCommands)];
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [self refreshCommands];
    [super viewWillAppear:animated];
}

- (void)reloadSpecifiersIfVisible {
    if (_specifiers && self.isViewLoaded && self.view.window) {
        [self reloadSpecifiers];
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [[NSMutableArray alloc] init];
        _specifiers = specifiers;

        PSSpecifier *topGroup = PSSpecifier.emptyGroupSpecifier;
        NSString *footerText = [@"Commands are executable files in\r\n" stringByAppendingString:USER_COMMANDS_DIRECTORY.stringByAbbreviatingWithTildeInPath];
        [topGroup setProperty:footerText forKey:@"footerText"];
        [specifiers addObject:topGroup];

        UIImage *iFileIcon = [LAActivator.sharedInstance smallIconForListenerName:@"eu.heinelt.ifile"];
        if (iFileIcon) {
            PSSpecifier *iFileSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Open iFile"
                    target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [iFileSpecifier setProperty:iFileIcon forKey:@"iconImage"];
            iFileSpecifier->action = @selector(open_iFile);
            [specifiers addObject:iFileSpecifier];
        }

        [specifiers addObject:PSSpecifier.emptyGroupSpecifier];

        NSArray *cmds = [_messagingCenter sendMessageAndReceiveReplyName:@"listCommands" userInfo:nil][@"commands"];
        for (NSString *path in cmds) {
            CmdivatorCmd *cmd = [[CmdivatorCmd alloc] initWithPath:path];
            PSSpecifier *cmdSpecifier = [PSSpecifier preferenceSpecifierNamed:cmd.displayName
                    target:self set:nil get:@selector(displayPathForSpecifier:) detail:nil cell:PSLinkListCell edit:nil];
            cmdSpecifier.cmd = cmd;
            [cmdSpecifier setProperty:CmdivatorCmdCell.class forKey:@"cellClass"];
            [cmdSpecifier setProperty:cmd.listenerName forKey:@"activatorListener"];
            [cmdSpecifier setProperty:cmd.displayName forKey:@"activatorTitle"];
            [cmdSpecifier setProperty:[NSBundle bundleWithIdentifier:@"com.libactivator.preferencebundle"].bundlePath forKey:@"lazy-bundle"];
            cmdSpecifier->action = @selector(lazyLoadBundle:);
            [specifiers addObject:cmdSpecifier];
        }
    }
    return _specifiers;
}

- (NSString *)displayPathForSpecifier:(PSSpecifier *)specifier {
    return specifier.cmd.displayPath;
}

- (void)refreshCommands {
    [_messagingCenter sendMessageName:@"refreshCommands" userInfo:nil];
}

- (void)open_iFile {
    NSURL *fileURL = [NSURL fileURLWithPath:USER_COMMANDS_DIRECTORY];
    NSURL *iFileURL = [NSURL URLWithString:[@"i" stringByAppendingString:fileURL.absoluteString]];
    [UIApplication.sharedApplication openURL:iFileURL];
}

- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath {
    int specifierIndex = [self indexOfGroup:indexPath.section] + indexPath.row + 1;
    return [_specifiers objectAtIndex:specifierIndex];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if (specifier.cmd.removable) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        if ([specifier.cmd delete]) {
            [self refreshCommands];
        }
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

@implementation PSSpecifier (Cmdivator)

- (CmdivatorCmd *)cmd {
    return [self propertyForKey:@"cmdivatorCmd"];
}

- (void)setCmd:(CmdivatorCmd *)cmd {
    [self setProperty:cmd forKey:@"cmdivatorCmd"];
}

@end
