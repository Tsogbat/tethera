#ifndef TETHERA_PTY_H
#define TETHERA_PTY_H

#include <sys/types.h>

/// Starts `path` on a new pseudo-terminal and returns its pid (or -1, with errno set).
///
/// The child gets a fresh session with the PTY as its controlling terminal, default signal
/// dispositions and an empty signal mask (ignored signals would otherwise survive exec), and
/// no inherited descriptors beyond stdin/stdout/stderr. The master is returned non-blocking
/// and close-on-exec in `*master_fd`.
pid_t tethera_spawn_pty(const char *path, char *const argv[], char *const envp[],
                        const char *cwd, unsigned short cols, unsigned short rows,
                        int *master_fd);

/// Sets the window size on a PTY master. Returns 0 on success.
int tethera_set_winsize(int master_fd, unsigned short cols, unsigned short rows);

#endif
