#include "tethera_pty.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <util.h>

pid_t tethera_spawn_pty(const char *path, char *const argv[], char *const envp[],
                        const char *cwd, unsigned short cols, unsigned short rows,
                        int *master_fd) {
    struct winsize size = {0};
    size.ws_col = cols;
    size.ws_row = rows;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &size);
    if (pid < 0) {
        return -1;
    }

    if (pid == 0) {
        // Child: only async-signal-safe calls until exec.
        for (int sig = 1; sig < NSIG; sig++) {
            signal(sig, SIG_DFL);
        }
        sigset_t empty;
        sigemptyset(&empty);
        sigprocmask(SIG_SETMASK, &empty, NULL);

        int max = (int)sysconf(_SC_OPEN_MAX);
        if (max < 0 || max > 4096) max = 4096;
        for (int fd = 3; fd < max; fd++) {
            close(fd);
        }

        if (cwd == NULL || chdir(cwd) != 0) {
            const char *home = getenv("HOME");
            if (home != NULL) chdir(home);
        }
        execve(path, argv, envp);
        _exit(127);
    }

    int flags = fcntl(master, F_GETFL);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);
    fcntl(master, F_SETFD, FD_CLOEXEC);
    *master_fd = master;
    return pid;
}

int tethera_set_winsize(int master_fd, unsigned short cols, unsigned short rows) {
    struct winsize size = {0};
    size.ws_col = cols;
    size.ws_row = rows;
    return ioctl(master_fd, TIOCSWINSZ, &size);
}
