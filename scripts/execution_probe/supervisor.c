#define _GNU_SOURCE
/* Trusted guest-only supervisor; never compiled or executed on macOS. */
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int error_fd;

static void setup_failed(void) {
    int value = errno ? errno : EINVAL;
    (void)write(error_fd, &value, sizeof value);
    _exit(126);
}

static void limit(int resource, rlim_t soft, rlim_t hard) {
    struct rlimit value = {soft, hard};
    if (setrlimit(resource, &value) != 0) setup_failed();
}

int main(int argc, char **argv) {
    int compile = argc == 3 && strcmp(argv[1], "compile") == 0;
    if (getuid() != 0 || (!compile && !(argc == 2 && strcmp(argv[1], "run") == 0)))
        return 2;
    if (compile && strcmp(argv[2], "17") && strcmp(argv[2], "20")) return 2;
    int errors[2];
    if (pipe2(errors, O_CLOEXEC) != 0) return 2;
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        close(errors[0]);
        error_fd = errors[1];
        if (setsid() < 0) setup_failed();
        limit(RLIMIT_CORE, 0, 0);
        limit(RLIMIT_CPU, compile ? 8 : 1, compile ? 8 : 2);
        limit(RLIMIT_AS, (compile ? 384UL : 128UL) * 1024 * 1024,
                        (compile ? 384UL : 128UL) * 1024 * 1024);
        /* One sentinel byte lets the parent distinguish exactly-at-limit output. */
        limit(RLIMIT_FSIZE, compile ? 8 * 1024 * 1024 : 65537,
                           compile ? 8 * 1024 * 1024 : 65537);
        limit(RLIMIT_NOFILE, compile ? 64 : 32, compile ? 64 : 32);
        limit(RLIMIT_NPROC, 32, 32);
        if (setgroups(0, NULL) || setgid(65534) || setuid(65534) || chdir("/work"))
            setup_failed();
        if (compile) {
            char *args[] = {"/usr/bin/g++", strcmp(argv[2], "17") == 0 ? "-std=c++17" : "-std=c++20",
                "-O0", "-fdiagnostics-color=never", "-fdiagnostics-column-unit=byte",
                "-o", "/work/program", "/work/main.cpp", NULL};
            execv(args[0], args);
        } else {
            char *args[] = {"/work/program", NULL};
            execv(args[0], args);
        }
        setup_failed();
    }
    close(errors[1]);
    int status;
    struct rusage usage;
    while (wait4(child, &status, 0, &usage) < 0) {
        if (errno != EINTR) return 2;
    }
    /* The child called setsid(), so its PID is its process group ID. Remaining
     * group members (compiler workers or program descendants) must not outlive
     * the run; a detached grandchild that escaped the group is rejected by the
     * trusted init before any verdict is computed. */
    (void)kill(-child, SIGKILL);
    int setup_errno = 0;
    ssize_t count = read(errors[0], &setup_errno, sizeof setup_errno);
    close(errors[0]);
    if (count != 0) return 2; /* No user code can forge this close-on-exec pipe. */
    int signal = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    int code = signal ? 128 + signal : (WIFEXITED(status) ? WEXITSTATUS(status) : 255);
    int descriptor = open("/run/termination", O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
    if (descriptor < 0) return 2;
    FILE *output = fdopen(descriptor, "w");
    if (!output) { close(descriptor); return 2; }
    if (fprintf(output, "%d %d\n", code, signal) < 0 || fclose(output) != 0) return 2;
    return 0;
}
