#define LOG(fmt, ...) NSLog(@"Cmdivator: " fmt, ##__VA_ARGS__)

#define MESSAGE_CENTER_NAME @"net.joedj.cmdivator"
#define COMMANDS_CHANGED_NOTIFICATION "net.joedj.cmdivator/CommandsChanged"

#define SYSTEM_COMMANDS_DIRECTORY @"/Library/Cmdivator/Cmds"
#define USER_COMMANDS_DIRECTORY (@"~/Library/Cmdivator/Cmds".stringByExpandingTildeInPath)
