//! Native io/os ingress for the direct backend, in Zig.
//!
//! This file replaces `src/idol_io_bootstrap.c`. See `idol_str_runtime.zig` for
//! why "no C" means no C TRANSLATION UNIT rather than no libc: every
//! `extern "c"` below is a platform entry point resolved by the dynamic linker.
//!
//! THE STDIO CALLS ARE CALLS, NOT REIMPLEMENTATIONS, and that is load-bearing.
//! `idol_io_read_line` reads through `getchar()` — the BUFFERED stdin stream —
//! while `idol_io_read_stdin` reads fd 0 raw. Those two share a file offset in
//! a way that a hand-rolled buffered reader would not reproduce, so the port
//! keeps calling the same libc functions the C called, in the same order.
//!
//! THE CONSTRUCTOR IS THE HARD PART. The C had
//! `__attribute__((constructor)) static void idol_io_line_buffer(void)`, which
//! sets stdout line-buffered BEFORE main. It is not decoration: the server loop
//! writes a response and then reads the next request, and a full-buffered pipe
//! deadlocks that handshake. Dropping it in favour of lazy initialisation would
//! move the flush point, so it is preserved exactly, via module-level assembly
//! that emits the `__DATA,__mod_init_func` pointer.
//!
//! `export const ptr linksection("__DATA,__mod_init_func")` — the obvious
//! spelling — produces a correct section (flags 0x09, S_MOD_INIT_FUNC_POINTERS)
//! and then CRASHES ld64 in `AliasAddressOrderer`, because Zig emits three
//! symbols at that one address where clang emits an anonymous `ltmp`. The
//! assembly below emits the pointer with no symbol attached, which is what the
//! linker expects. Verified by running a linked probe and observing the
//! constructor's output land before `main`'s.

// ── platform ABI ────────────────────────────────────────────────────────────
extern "c" fn malloc(n: usize) ?*anyopaque;
extern "c" fn realloc(p: ?*anyopaque, n: usize) ?*anyopaque;
extern "c" fn free(p: ?*anyopaque) void;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fseek(f: *anyopaque, off: c_long, whence: c_int) c_int;
extern "c" fn ftell(f: *anyopaque) c_long;
extern "c" fn fread(p: [*]u8, sz: usize, n: usize, f: *anyopaque) usize;
extern "c" fn fclose(f: *anyopaque) c_int;
extern "c" fn fileno(f: *anyopaque) c_int;
extern "c" fn getchar() c_int;
extern "c" fn setvbuf(f: *anyopaque, buf: ?[*]u8, mode: c_int, size: usize) c_int;
extern "c" fn fflush(f: ?*anyopaque) c_int;
extern "c" fn exit(code: c_int) noreturn;
extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn system(cmd: [*:0]const u8) c_int;
extern "c" fn popen(cmd: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn pclose(f: *anyopaque) c_int;
extern "c" fn _NSGetArgc() *c_int;
extern "c" fn _NSGetArgv() *[*][*:0]u8;
extern "c" fn __error() *c_int;
extern "c" var __stdoutp: *anyopaque; // Darwin's `stdout`

const EOF: c_int = -1;
const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;
const IOLBF: c_int = 1; // Darwin _IOLBF
const ERANGE: c_int = 34;

// ── the pre-main constructor ────────────────────────────────────────────────
export fn idol_io_line_buffer() callconv(.c) void {
    _ = setvbuf(__stdoutp, null, IOLBF, 0);
}

comptime {
    asm (
        \\.section __DATA,__mod_init_func,mod_init_funcs
        \\.p2align 3
        \\.quad _idol_io_line_buffer
    );
}

// ── shared reader ───────────────────────────────────────────────────────────
/// Drain a descriptor into a NUL-terminated heap buffer. The doubling rule and
/// the `cap - len - 1` read size are the C's, so the reserved terminator byte
/// and the growth points land identically.
fn readFd(fd: c_int) ?[*:0]u8 {
    var cap: usize = 8192;
    var len: usize = 0;
    var buf: [*]u8 = @ptrCast(malloc(cap) orelse return null);
    while (true) {
        if (len + 4096 >= cap) {
            cap *= 2;
            const next = realloc(buf, cap) orelse {
                free(buf);
                return null;
            };
            buf = @ptrCast(next);
        }
        const got = read(fd, buf + len, cap - len - 1);
        if (got <= 0) break;
        len += @intCast(got);
    }
    if (len == 0) {
        free(buf);
        const empty: [*]u8 = @ptrCast(malloc(1) orelse return null);
        empty[0] = 0;
        return @ptrCast(empty);
    }
    buf[len] = 0;
    return @ptrCast(buf);
}

export fn idol_io_read_stdin() callconv(.c) ?[*:0]u8 {
    return readFd(0);
}

/// One newline-delimited message, trailing newline stripped. End of input is
/// NOT modelled as a value: when the peer closes the pipe with nothing further,
/// the process ends cleanly rather than answering an empty-string sentinel, so
/// the Idol server loop is `while true` with nothing to compare against.
export fn idol_io_read_line() callconv(.c) ?[*:0]u8 {
    var cap: usize = 8192;
    var len: usize = 0;
    var buf: [*]u8 = @ptrCast(malloc(cap) orelse return null);
    var c = getchar();
    if (c == EOF) {
        free(buf);
        _ = fflush(__stdoutp);
        exit(0);
    }
    while (c != EOF) {
        if (c == '\n') break;
        if (len + 1 >= cap) {
            cap *= 2;
            const next = realloc(buf, cap) orelse {
                free(buf);
                return null;
            };
            buf = @ptrCast(next);
        }
        buf[len] = @intCast(c & 0xff);
        len += 1;
        c = getchar();
    }
    buf[len] = 0;
    return @ptrCast(buf);
}

export fn idol_io_read_path(path: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    const p = path orelse return idol_io_read_stdin();
    if (p[0] == 0) return idol_io_read_stdin();
    const f = fopen(p, "rb") orelse return null;
    if (fseek(f, 0, SEEK_END) != 0) {
        _ = fclose(f);
        return null;
    }
    const sz = ftell(f);
    if (sz < 0) {
        _ = fclose(f);
        return null;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        _ = fclose(f);
        return null;
    }
    const n: usize = @intCast(sz);
    const buf: [*]u8 = @ptrCast(malloc(n + 1) orelse {
        _ = fclose(f);
        return null;
    });
    if (fread(buf, 1, n, f) != n) {
        free(buf);
        _ = fclose(f);
        return null;
    }
    _ = fclose(f);
    buf[n] = 0;
    return @ptrCast(buf);
}

/// 1-based. A missing index is UNKNOWN (null), not "" — the two are different
/// answers and collapsing them is what GAP-118 records.
export fn idol_os_arg(i: i64) callconv(.c) ?[*:0]u8 {
    if (i < 1) return null;
    const argc: i64 = _NSGetArgc().*;
    const argv = _NSGetArgv().*;
    if (i >= argc) return null;
    return argv[@intCast(i)];
}

/// Failure is UNKNOWN (null), not "". GAP-118, same rule as `idol_os_arg`.
export fn idol_os_cwd() callconv(.c) ?[*:0]u8 {
    var cap: usize = 256;
    while (true) {
        const buf: [*]u8 = @ptrCast(malloc(cap) orelse return null);
        if (getcwd(buf, cap)) |ok| return ok;
        free(buf);
        if (__error().* != ERANGE) return null;
        cap *= 2;
        if (cap > (@as(usize, 1) << 20)) return null;
    }
}

export fn idol_os_execute(cmd: ?[*:0]const u8) callconv(.c) i64 {
    const c = cmd orelse return 1;
    const rc = system(c);
    if (rc == -1) return 1;
    // WIFEXITED / WEXITSTATUS, spelled out rather than imported.
    if ((rc & 0x7f) == 0) return if (((rc >> 8) & 0xff) == 0) 0 else 1;
    return 1;
}

export fn idol_process_capture(cmd: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    const c = cmd orelse return emptyHeap();
    const f = popen(c, "r") orelse return emptyHeap();
    const out = readFd(fileno(f));
    _ = pclose(f);
    return out;
}

fn emptyHeap() ?[*:0]u8 {
    const e: [*]u8 = @ptrCast(malloc(1) orelse return null);
    e[0] = 0;
    return @ptrCast(e);
}
