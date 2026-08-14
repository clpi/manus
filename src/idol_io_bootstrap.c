// Bootstrap native io/os ingress for direct backend gate transport.
// Delete when compiler root projection owns io:read / os.args / os.cwd (GAP-155).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdint.h>
#include <errno.h>
#include <crt_externs.h>

static char* idol_io_read_fd(int fd) {
    size_t cap = 8192;
    size_t len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) return NULL;
    for (;;) {
        if (len + 4096 >= cap) {
            cap *= 2;
            char* next = (char*)realloc(buf, cap);
            if (!next) {
                free(buf);
                return NULL;
            }
            buf = next;
        }
        ssize_t got = read(fd, buf + len, cap - len - 1);
        if (got <= 0) break;
        len += (size_t)got;
    }
    if (len == 0) {
        free(buf);
        char* empty = (char*)malloc(1);
        if (!empty) return NULL;
        empty[0] = '\0';
        return empty;
    }
    buf[len] = '\0';
    return buf;
}

char* idol_io_read_stdin(void) {
    return idol_io_read_fd(0);
}

// One newline-delimited message from stdin for a persistent server loop.
// Trailing newline stripped. End of input is not modelled as a value at all:
// when the peer closes the pipe with no further bytes, the reader terminates the
// process cleanly. The Idol server loop is therefore `while true` with no
// empty-string / zero-length EOF sentinel to compare against (GAP-155).
// stdout is line-buffered here so each written response reaches the peer before
// the next line is read (a full-buffered pipe would deadlock the handshake).
__attribute__((constructor)) static void idol_io_line_buffer(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
}

char* idol_io_read_line(void) {
    size_t cap = 8192;
    size_t len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) return NULL;
    int c = getchar();
    if (c == EOF) {
        // Peer closed the stream: end the server, do not return a sentinel.
        free(buf);
        fflush(stdout);
        exit(0);
    }
    while (c != EOF) {
        if (c == '\n') break;
        if (len + 1 >= cap) {
            cap *= 2;
            char* next = (char*)realloc(buf, cap);
            if (!next) {
                free(buf);
                return NULL;
            }
            buf = next;
        }
        buf[len++] = (char)c;
        c = getchar();
    }
    buf[len] = '\0';
    return buf;
}

char* idol_io_read_path(const char* path) {
    if (path == NULL || path[0] == '\0') return idol_io_read_stdin();
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long sz = ftell(f);
    if (sz < 0) {
        fclose(f);
        return NULL;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    char* buf = (char*)malloc((size_t)sz + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    buf[sz] = '\0';
    return buf;
}

/* 1-based. Missing index is unknown (NULL), not "". GAP-118. */
char* idol_os_arg(int64_t i) {
    if (i < 1) return NULL;
    int argc = *_NSGetArgc();
    char** argv = *_NSGetArgv();
    if (i >= argc) return NULL;
    return argv[i];
}

/* Failure is unknown (NULL), not "". GAP-118. */
char* idol_os_cwd(void) {
    size_t cap = 256;
    for (;;) {
        char* buf = (char*)malloc(cap);
        if (buf == NULL) return NULL;
        if (getcwd(buf, cap) != NULL) return buf;
        free(buf);
        if (errno != ERANGE) return NULL;
        cap *= 2;
        if (cap > (size_t)1 << 20) return NULL;
    }
}

int64_t idol_os_execute(const char* cmd) {
    if (cmd == NULL) return 1;
    int rc = system(cmd);
    if (rc == -1) return 1;
    if (WIFEXITED(rc)) return WEXITSTATUS(rc) == 0 ? 0 : 1;
    return 1;
}

char* idol_process_capture(const char* cmd) {
    if (cmd == NULL) {
        char* empty = (char*)malloc(1);
        if (empty == NULL) return NULL;
        empty[0] = '\0';
        return empty;
    }
    FILE* f = popen(cmd, "r");
    if (f == NULL) {
        char* empty = (char*)malloc(1);
        if (empty == NULL) return NULL;
        empty[0] = '\0';
        return empty;
    }
    char* out = idol_io_read_fd(fileno(f));
    pclose(f);
    return out;
}
