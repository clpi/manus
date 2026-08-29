// idol_c_runtime_shim.c — host-agnostic C99 shim for the extern symbols the
// grammar-projection owner needs. Compiled alongside the C99 source the
// C backend emits for `lib/compiler/token.id`. The shim is deliberately
// minimal: only the symbols `_project` (via `spill`) reaches are
// implemented, plus the libc wrappers that the dnir's `call_extern` sites
// emit under their `idol_`-prefixed shim names.
//
// ABI: every parameter arrives as `int64_t` (the dnir's call-site
// convention). Pointer-typed parameters carry their bit pattern in the
// register / stack slot the same way `const char *` would; the shim
// reinterprets them via a tagged union that preserves the original
// representation exactly. The shim is not a strict C99 file — the
// generated program is.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <unistd.h>

/* ── host-bound externs that `_project` reaches ─────────────────────────── */

int64_t idol_io_open(int64_t path, int64_t mode) {
    union { int64_t i; const char *p; } u_path, u_mode;
    u_path.i = path;
    u_mode.i = mode;
    FILE *fp = fopen(u_path.p, u_mode.p);
    if (!fp) return 0;
    union { FILE *fp; int64_t i; } u;
    u.fp = fp;
    return u.i;
}

int64_t idol_io_write_handle(int64_t handle, int64_t text) {
    union { int64_t i; FILE *fp; } u;
    union { int64_t i; const char *p; } t;
    u.i = handle;
    t.i = text;
    if (!u.fp) return 0;
    if (!t.p) return 0;
    return (int64_t)fwrite(t.p, 1, strlen(t.p), u.fp);
}

int64_t idol_io_close_handle(int64_t handle) {
    union { int64_t i; FILE *fp; } u;
    u.i = handle;
    if (!u.fp) return 0;
    return (int64_t)fclose(u.fp);
}

int64_t idol_io_read_path(int64_t path) {
    union { int64_t i; const char *p; } u;
    u.i = path;
    if (!u.p) return 0;
    FILE *fp = fopen(u.p, "rb");
    if (!fp) return 0;
    fseek(fp, 0, SEEK_END);
    long sz = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    char *buf = (char *)malloc(sz + 1);
    fread(buf, 1, sz, fp);
    buf[sz] = 0;
    fclose(fp);
    union { char *p; int64_t i; } r;
    r.p = buf;
    return r.i;
}

int64_t idol_io_read_stdin(void) {
    /* The grammar-projection owner never reaches this. Returning 0 is
     * fail-closed; the program that does reach it never compiles. */
    return 0;
}

int64_t idol_io_read_line(void) { return idol_io_read_stdin(); }

int64_t idol_os_env(int64_t name) {
    union { int64_t i; const char *p; } u;
    u.i = name;
    const char *v = getenv(u.p);
    if (!v) return 0;
    union { const char *p; int64_t i; } r;
    r.p = v;
    return r.i;
}

int64_t idol_os_arg(int64_t i) {
    extern int *argc_address(void);
    extern char **argv_address(void);
    if (i < 1) return 0;
    int argc = *argc_address();
    if (i >= argc) return 0;
    char **argv = argv_address();
    union { char *p; int64_t i; } r;
    r.p = argv[i];
    return r.i;
}

int64_t idol_os_cwd(void) {
    char buf[4096];
    if (!getcwd(buf, sizeof buf)) return 0;
    union { char *p; int64_t i; } r;
    r.p = buf;
    return r.i;
}

int64_t idol_os_remove(int64_t path) {
    union { int64_t i; const char *p; } u;
    u.i = path;
    return (int64_t)remove(u.p);
}

int64_t idol_os_execute(int64_t cmd) {
    union { int64_t i; const char *p; } u;
    u.i = cmd;
    return (int64_t)system(u.p);
}

int64_t idol_process_capture(int64_t cmd) {
    union { int64_t i; const char *p; } u;
    u.i = cmd;
    FILE *fp = popen(u.p, "r");
    if (!fp) return 0;
    char *buf = (char *)malloc(8192);
    size_t n = fread(buf, 1, 8191, fp);
    buf[n] = 0;
    pclose(fp);
    union { char *p; int64_t i; } r;
    r.p = buf;
    return r.i;
}

int64_t idol_str_at(int64_t s, int64_t i) {
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (i < 1) return 0;
    if (!u.p) return 0;
    int64_t len = (int64_t)strlen(u.p);
    if (i > len) return 0;
    union { const char *p; int64_t i; } r;
    r.p = u.p + (i - 1);
    return r.i;
}

int64_t idol_str_has(int64_t hay, int64_t needle) {
    union { int64_t i; const char *p; } h, n;
    h.i = hay;
    n.i = needle;
    if (!h.p || !n.p) return 0;
    return strstr(h.p, n.p) != NULL;
}

int64_t idol_str_find(int64_t hay, int64_t needle, int64_t start) {
    union { int64_t i; const char *p; } h, n;
    h.i = hay;
    n.i = needle;
    if (!h.p || !n.p) return 0;
    if (start < 1) start = 1;
    if ((size_t)start > strlen(h.p)) return 0;
    const char *hit = strstr(h.p + (start - 1), n.p);
    if (!hit) return 0;
    union { const char *p; int64_t i; } r;
    r.p = hit;
    return r.i;
}

int64_t idol_str_match(int64_t s, int64_t pat) {
    union { int64_t i; const char *p; } u, p;
    u.i = s;
    p.i = pat;
    if (!u.p || !p.p) return 0;
    /* Stub: the owner never matches patterns. Real implementation lives
     * in src/idol_str_runtime.zig via the aarch64-macos prebuilt object;
     * here we return NULL so a caller would fail at the type test that
     * follows the match. */
    return 0;
}

int64_t duo_str_sub(int64_t s, int64_t i, int64_t j) {
    /* `sub(str, i, j)` reads the dnir's `[i..j]` slice, both
     * 1-INDEXED and INCLUSIVE on both ends. The slice byte count is
     * therefore `j - i + 1`, not `j - i`. A 1-character slice is
     * `sub(s, n, n)`; an empty slice (when the dnir's `start > i - 1`)
     * is `sub(s, start, start - 1)`, which this function clamps to
     * `j = i - 1` and reports `n = 0` (one NUL byte, the terminator).
     *
     * Both endpoints are clamped to `[1, len + 1]`: `len + 1` is the
     * last legal position (the position OF the NUL terminator),
     * because the dnir's `sub(start, i - 1)` writes the word it just
     * closed, where `i` is the 1-indexed space that ends the word
     * and `i - 1` is the last character of it. */
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (!u.p) return 0;
    int64_t len = (int64_t)strlen(u.p);
    if (i < 1) i = 1;
    if (j < i - 1) return 0;
    if (i > len + 1) i = len + 1;
    if (j > len + 1) j = len + 1;
    int64_t n = j - i + 1;
    char *out = (char *)malloc(n + 1);
    memcpy(out, u.p + (i - 1), n);
    out[n] = 0;
    union { char *p; int64_t i; } r;
    r.p = out;
    return r.i;
}

int64_t duo_str_to_i64(int64_t s) {
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (!u.p) return 0;
    return (int64_t)atoll(u.p);
}

double duo_str_to_f64(int64_t s) {
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (!u.p) return 0.0;
    return atof(u.p);
}

/* ── libc wrappers re-prefixed for the dnir's int64-t convention ────────── */

int64_t idol_malloc(int64_t size) {
    void *p = malloc((size_t)size);
    union { void *p; int64_t i; } r;
    r.p = p;
    return r.i;
}

int64_t idol_printf(int64_t fmt,
                   int64_t a3, int64_t a4, int64_t a5, int64_t a6,
                   int64_t a7, int64_t a8, int64_t a9, int64_t a10,
                   int64_t a11, int64_t a12, int64_t a13, int64_t a14,
                   int64_t a15, int64_t a16) {
    union { int64_t i; const char *p; } u;
    u.i = fmt;
    if (!u.p) return 0;
    /* `snprintf` is the C-printf-family variadic entry point that
     * takes individual args; `vsnprintf` would need a `va_list`,
     * which is more machinery than this single-call shim needs. */
    int n = snprintf(NULL, 0, "%s", u.p);
    return (int64_t)n;
}

int64_t idol_memcpy(int64_t dst, int64_t src, int64_t n) {
    union { int64_t i; void *p; } d, s;
    d.i = dst;
    s.i = src;
    memcpy(d.p, s.p, (size_t)n);
    return 0;
}

int64_t idol_strcmp(int64_t a, int64_t b) {
    union { int64_t i; const char *p; } x, y;
    x.i = a;
    y.i = b;
    if (!x.p || !y.p) return 0;
    return (int64_t)strcmp(x.p, y.p);
}

/* The dnir's variadic concat emits the args after `fmt` into the
 * caller's `a3..a16` slots (the C backend remaps its `mov_arg
 * result=0..13` to slot indices 3..16 so they land after the fixed
 * `buf`/`size`/`fmt` args the same call site already wrote). We name
 * every slot explicitly so the C calling convention places each
 * trailing arg in the register / stack slot the C backend emitted;
 * the format string in `fmt` is what the dnir already prepared, and
 * the callee-side interpretation of each trailing arg follows the
 * format specifier the dnir chose (`%s` for the interned address
 * the owner passes, `%lld` for the count the concat plan
 * computed). The 14 explicit trailing args cover `a3..a16` —
 * `max_concat_holes` is 13, so the C backend never needs more
 * than this. */
int64_t idol_snprintf(int64_t buf, int64_t size, int64_t fmt,
                   int64_t a3, int64_t a4, int64_t a5, int64_t a6,
                   int64_t a7, int64_t a8, int64_t a9, int64_t a10,
                   int64_t a11, int64_t a12, int64_t a13, int64_t a14,
                   int64_t a15, int64_t a16) {
    union { int64_t i; char *p; } b;
    union { int64_t i; const char *p; } f;
    b.i = buf;
    f.i = fmt;
    /* `snprintf(NULL, 0, fmt, …)` and `snprintf(b, 0, fmt, …)` are
     * both the C-idiomatic way to MEASURE the required buffer size;
     * the buffer pointer is allowed to be NULL when the size is
     * zero, and with size zero the buffer is never read or written.
     * The dnir's concat emitter uses this pattern to discover the
     * size of a concatenated literal before allocating. Honour both
     * shapes: NULL buffer, or any buffer with size 0. */
    if (!b.p || size <= 0) {
        /* The format string in `fmt` is the dnir's literal; the
         * variadic args `a3..a16` are i64 scalar values that
         * `stageConcatHoles` populated. To honour the dnir's
         * measure — which is the size of the answer, not the format
         * — we run `snprintf(NULL, 0, …)` with the same args and
         * return its result. `snprintf` returns the number of bytes
         * that WOULD HAVE been written had the buffer been large
         * enough, which is exactly the size the dnir then rounds up
         * by one to count the NUL. The trailing args are forward
         * to snprintf as the typed pointers the format string
         * would read: `const char *` for `%s` slots, `long long`
         * for `%lld` slots. The dnir's plan chooses the format,
         * and the variadic ABI carries each arg in the same
         * 64-bit register / stack slot regardless of the type the
         * callee chooses to read it as. */
        int n = snprintf(NULL, 0, f.p ? f.p : "",
                         (const char *)(intptr_t)a3,
                         (const char *)(intptr_t)a4,
                         (const char *)(intptr_t)a5,
                         (const char *)(intptr_t)a6,
                         (const char *)(intptr_t)a7,
                         (const char *)(intptr_t)a8,
                         (const char *)(intptr_t)a9,
                         (const char *)(intptr_t)a10,
                         (const char *)(intptr_t)a11,
                         (const char *)(intptr_t)a12,
                         (const char *)(intptr_t)a13,
                         (const char *)(intptr_t)a14,
                         (const char *)(intptr_t)a15,
                         (const char *)(intptr_t)a16);
        return (int64_t)n;
    }
    /* Thread the trailing i64 args through snprintf as `const char *`
     * values. The dnir's variadic plan passes i64 scalars whose
     * high-bit interpretation is the callee's responsibility: for the
     * owner, every variadic slot is either an interned string
     * address (read with `%s`) or a count (read with `%lld`).
     * Reading the i64 value as a `long long` is bit-identical to
     * reading it as a pointer for the values the dnir writes, and
     * the format string in `fmt` decides which cast snprintf
     * applies. The C calling convention carries each arg in the
     * same 64-bit register / stack slot regardless of the
     * declared type. */
    int n = snprintf(b.p, (size_t)size, f.p ? f.p : "",
                     (const char *)(intptr_t)a3,
                     (const char *)(intptr_t)a4,
                     (const char *)(intptr_t)a5,
                     (const char *)(intptr_t)a6,
                     (const char *)(intptr_t)a7,
                     (const char *)(intptr_t)a8,
                     (const char *)(intptr_t)a9,
                     (const char *)(intptr_t)a10,
                     (const char *)(intptr_t)a11,
                     (const char *)(intptr_t)a12,
                     (const char *)(intptr_t)a13,
                     (const char *)(intptr_t)a14,
                     (const char *)(intptr_t)a15,
                     (const char *)(intptr_t)a16);
    return (int64_t)n;
}

int64_t idol_strlen(int64_t s) {
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (!u.p) return 0;
    return (int64_t)strlen(u.p);
}

/* ── print_value realization ──────────────────────────────────────────────── */

int64_t idol_puts(int64_t s) {
    union { int64_t i; const char *p; } u;
    u.i = s;
    if (!u.p) return (int64_t)puts("(null)");
    return (int64_t)puts(u.p);
}

int64_t idol_vprintf(int64_t fmt, ...) {
    union { int64_t i; const char *p; } u;
    u.i = fmt;
    va_list ap;
    va_start(ap, fmt);
    int n = vprintf(u.p ? u.p : "", ap);
    va_end(ap);
    return (int64_t)n;
}

/* ── shim-side helpers called by `idol_os_arg` ──────────────────────────── */

static int _argc_storage = 0;
static char **_argv_storage = NULL;

void _idol_set_argv(int argc, char **argv) {
    _argc_storage = argc;
    _argv_storage = argv;
}

int *argc_address(void) { return &_argc_storage; }
char **argv_address(void) { return _argv_storage; }