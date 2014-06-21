#import <spawn.h>

#import "CmdivatorCmd.h"
#import "Common.h"

#define LISTENER_NAME_PREFIX @"net.joedj.cmdivator.listener:"

@implementation CmdivatorCmd {
    NSURL *_url;
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
    }
    return self;
}

- (NSString *)displayName {
    return _url.lastPathComponent;
}

- (NSString *)displayPath {
    return _url.path.stringByAbbreviatingWithTildeInPath;
}

- (NSString *)listenerName {
    return [LISTENER_NAME_PREFIX stringByAppendingString:_url.path];
}

- (void)runForEvent:(LAEvent *)event {
    NSString *path = _url.path;
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

        static const char *const cmd_argv[] = { "", NULL };
        static char *cmd_envp[] = { NULL };
        pid_t pid;
        int ret;
        if (!(ret = posix_spawn(&pid, path.fileSystemRepresentation, &cmd_spawn_file_actions, &cmd_spawnattr, (char* const*)cmd_argv, (char* const*)cmd_envp))) {
            int status;
            do {
                ret = waitpid(pid, &status, 0);
            } while (ret == -1 && errno == EINTR);
            if (ret == -1) {
                LOG(@"waitpid(%i): [%i] %s", pid, errno, strerror(errno));
            } else if (!(WIFEXITED(status) && WEXITSTATUS(status) == 0)) {
                LOG(@"%@ exited with status: %i", path, status);
            }
        } else {
            LOG(@"Unable to spawn %@ for event %@: %i: %s", path, event, ret, strerror(ret));
        }

    });
}

@end
