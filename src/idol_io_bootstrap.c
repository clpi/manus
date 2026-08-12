// Bootstrap native io world read helpers for direct backend gate transport.
// Delete when compiler root projection owns io:read() realization (GAP-155).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdint.h>

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
