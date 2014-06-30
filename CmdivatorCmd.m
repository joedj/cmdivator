#import <spawn.h>

#import "CmdivatorCmd.h"
#import "Common.h"

#define LISTENER_NAME_PREFIX @"net.joedj.cmdivator.listener:"

@implementation CmdivatorCmd

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = path;
    }
    return self;
}

- (NSString *)displayName {
    return _path.lastPathComponent;
}

- (NSString *)displayPath {
    return _path.stringByAbbreviatingWithTildeInPath;
}

- (NSString *)listenerName {
    return [LISTENER_NAME_PREFIX stringByAppendingString:_path];
}

- (void)runForEvent:(LAEvent *)event {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        static posix_spawn_file_actions_t cmd_spawn_file_actions;
        static posix_spawnattr_t cmd_spawnattr;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            int ret;
            if (!(ret = posix_spawnattr_init(&cmd_spawnattr))) {
                if ((ret = posix_spawnattr_setflags(&cmd_spawnattr, POSIX_SPAWN_CLOEXEC_DEFAULT))) {
                    LOG(@"posix_spawnattr_setflags: [%i] %s", ret, strerror(ret));
                }
            } else {
                LOG(@"posix_spawnattr_init: [%i] %s", ret, strerror(ret));
            }
            if (!(ret = posix_spawn_file_actions_init(&cmd_spawn_file_actions))) {
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDOUT_FILENO))) {
                    LOG(@"posix_spawn_file_actions_addinherit_np(%i): [%i] %s", STDOUT_FILENO, ret, strerror(ret));
                }
                if ((ret = posix_spawn_file_actions_addinherit_np(&cmd_spawn_file_actions, STDERR_FILENO))) {
                    LOG(@"posix_spawn_file_actions_addinherit_np(%i): [%i] %s", STDERR_FILENO, ret, strerror(ret));
                }
            } else {
                LOG(@"posix_spawn_file_actions_init: [%i] %s", ret, strerror(ret));
            }
        });

        NSString *path = _path;
        const char *const cmd = path.fileSystemRepresentation;
        const char *const cmd_argv[] = { cmd, NULL };
        const char *const cmd_envp[] = {
            [@"ACTIVATOR_LISTENER_NAME=" stringByAppendingString:self.listenerName].UTF8String,
            [@"ACTIVATOR_EVENT_NAME=" stringByAppendingString:event.name].UTF8String,
            [@"ACTIVATOR_EVENT_MODE=" stringByAppendingString:event.mode].UTF8String,
            NULL
        };
        pid_t pid;
        int ret;
        if (!(ret = posix_spawn(&pid, cmd, &cmd_spawn_file_actions, &cmd_spawnattr, (char* const*)cmd_argv, (char* const*)cmd_envp))) {
            dispatch_source_t exit_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
            dispatch_source_set_event_handler(exit_source, ^{
                int status;
                if (waitpid(pid, &status, WNOHANG) == -1) {
                    LOG(@"waitpid(%i): [%i] %s", pid, errno, strerror(errno));
                } else if (WIFEXITED(status)) {
                    int exitStatus = WEXITSTATUS(status);
                    if (exitStatus != 0) {
                        LOG(@"%@ terminated with status: %i", path, exitStatus);
                    }
                } else if (WIFSIGNALED(status)) {
                    LOG(@"%@ terminated by signal: %i", path, WTERMSIG(status));
                }
                dispatch_source_cancel(exit_source);
                dispatch_release(exit_source);
            });
            dispatch_resume(exit_source);
        } else {
            LOG(@"Unable to spawn %@ for event %@: [%i] %s", path, event, ret, strerror(ret));
        }

    });
}

- (BOOL)isRemovable {
    return [NSFileManager.defaultManager isDeletableFileAtPath:_path];
}

- (BOOL)delete {
    NSError * __autoreleasing error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:_path error:&error]) {
        LOG(@"Unable to delete command %@: %@", _path, error);
        return NO;
    }
    return YES;
}

@end
