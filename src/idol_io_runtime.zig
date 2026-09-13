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
//! THE HANDLER INSTALL IS THE HARD PART. The C had
//! `__attribute__((constructor)) static void idol_io_line_buffer(void)`, which
//! installed the SIGABRT flush handler BEFORE main. It is not decoration: the
//! B5 obligation (bytes written before a trap must be observed) needs the
//! handler in place before any trap. Dropping it in favour of lazy
//! initialisation would move the install point, so the install is preserved
//! exactly — but LAZILY, on first entry to any exported function below, which
//! is the earliest point the handler can matter. No `__mod_init_func`, no
//! pre-main work.
//!
//! # RUNG 1 — THE ARRIVAL GRANULARITY IS AN OBSERVATION NOTHING REQUIRED
//!
//! `setvbuf(stdout, _IOLBF)` does not say "the bytes arrive". It says **"the
//! bytes arrive ONE LINE AT A TIME, FOREVER"**, and that second half is an
//! observation no Idol program asked for. MEASURED on this compiler, four
//! binaries emitting a BYTE-IDENTICAL 62,000-byte / 2,000-line stream, min of
//! seven runs of `instructions retired`:
//!
//!     2,000 print calls, no constructor linked   13,246,155
//!     2,000 print calls, constructor linked      19,993,459
//!     1 print call,      no constructor linked   12,133,658
//!     1 print call,      constructor linked      19,210,695
//!
//! Merging 1,999 write CALLS saves 556 instructions each. Removing the
//! per-newline FLUSH saves **~3,200 instructions per newline** — six times more,
//! and it is bought by changing nothing a consumer of the byte stream can see.
//! `docs/surviving-runtime.md` §7 measures the same effect at 6,099 per newline
//! on `cat`, where the writes go to a pipe rather than to `/dev/null`.
//!
//! THE REQUIRED OBSERVATION IS NOT PER-NEWLINE ARRIVAL. It is: **the bytes have
//! arrived before any other party can look at the channel.** There are exactly
//! three such moments in this file, and this is now the complete list:
//!
//!   1. before blocking on stdin  — `idol_io_read_stdin`, `idol_io_read_line`,
//!      and `idol_io_read_path` when it falls through to stdin. This is the
//!      handshake the original constructor was written for, and flushing HERE
//!      satisfies it strictly: the writer cannot block on a response it has not
//!      yet asked for.
//!   2. before a child inherits fd 1 — `idol_os_execute`, `idol_process_capture`.
//!      Parent bytes buffered past the spawn would appear AFTER the child's.
//!   3. before an abnormal end — see the obligation below.
//!
//! # THE PROOF OBLIGATION, stated before the transform
//!
//! Line buffering may be dropped only if all five hold. Any one unproven means
//! keep it; there is no "probably".
//!
//!   B1  CONTENT.    The byte sequence written to fd 1 is unchanged. Neither
//!                   buffering mode can insert, drop or reorder bytes within one
//!                   stream — stdio is a queue either way. Discharged by
//!                   construction, and pinned by `gate/arrival.sh` comparing the
//!                   full output of both regimes with `cmp`.
//!
//!   B2  ARRIVAL-BY-EXIT. Every byte arrives before the process ends normally.
//!                   Returning from `main` runs `exit()`, which flushes every
//!                   stdio stream. Discharged by libc, unchanged by this file.
//!
//!   B3  HANDSHAKE.  A program that writes and then BLOCKS ON INPUT must have
//!                   flushed first, or it waits for a reply to a request still
//!                   sitting in its own buffer. Discharged by moment 1 above.
//!                   `gate/arrival.sh` runs the real bidirectional-pipe rig; a
//!                   regression here HANGS, so the gate bounds it and reports
//!                   the timeout as a failure rather than waiting.
//!
//!   B4  FD SHARING. A child process writing to the inherited fd 1 must not
//!                   overtake buffered parent bytes. Discharged by moment 2.
//!
//!   B5  FAILURE.    Bytes written before a TRAP must still be observed. THIS
//!                   ONE WAS NOT DISCHARGED BEFORE AND IS NOT FREE.
//!                   `native_backend.emitTrapAbort` open-codes
//!                   `kill(getpid(), SIGABRT)` as six words with no call and no
//!                   import, on the reasoning that "the exit code is this
//!                   subset's ONLY observable". MEASURED, that reasoning is
//!                   false — the C oracle separates the two cases exactly:
//!
//!                       clang, puts() then abort()                12 bytes, 134
//!                       clang, puts() then kill(getpid,SIGABRT)    0 bytes, 134
//!
//!                   libc's `abort()` flushes stdio; a raw `kill` does not. So
//!                   the substitution kept the exit code and silently dropped a
//!                   DIFFERENT observation. MEASURED on this compiler, before
//!                   this change, two Idol programs of identical shape:
//!
//!                       print then trap, links `os.args`   12 bytes  (survives)
//!                       print then trap, links no io       0 bytes  (LOST)
//!
//!                   The 12 bytes survived only because `os.args` happened to
//!                   drag this constructor in. Whether a program's dying words
//!                   are heard is decided by an unrelated linkage accident.
//!                   Dropping line buffering without discharging B5 would turn
//!                   the first row into the second — so B5 is discharged HERE,
//!                   by a SIGABRT handler that flushes and re-raises with the
//!                   default disposition, reproducing `abort()`'s behaviour in
//!                   full rather than only its exit code.
//!
//!                   THE HANDLER ONLY COVERS PROGRAMS THAT LINK THIS OBJECT.
//!                   The second row above — a trapping program with no io — was
//!                   already losing its output before this change and still is.
//!                   That is `native_backend.emitTrapAbort`'s to fix and it is
//!                   ROUTED, not touched here. This file must not make it worse,
//!                   and it does not: every program that observed pre-trap bytes
//!                   before observes them after.
//!

// ── platform ABI ────────────────────────────────────────────────────────────
extern "c" fn malloc(n: usize) ?*anyopaque;
extern "c" fn realloc(p: ?*anyopaque, n: usize) ?*anyopaque;
extern "c" fn free(p: ?*anyopaque) void;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fseek(f: *anyopaque, off: c_long, whence: c_int) c_int;
extern "c" fn ftell(f: *anyopaque) c_long;
extern "c" fn fread(p: [*]u8, sz: usize, n: usize, f: *anyopaque) usize;
extern "c" fn fclose(f: *anyopaque) c_int;
extern "c" fn fileno(f: *anyopaque) c_int;
extern "c" fn getchar() c_int;
extern "c" fn fflush(f: ?*anyopaque) c_int;
extern "c" fn exit(code: c_int) noreturn;
extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn system(cmd: [*:0]const u8) c_int;
extern "c" fn popen(cmd: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn pclose(f: *anyopaque) c_int;
extern "c" fn fputs(s: [*:0]const u8, stream: *anyopaque) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn _NSGetArgc() *c_int;
extern "c" fn _NSGetArgv() *[*][*:0]u8;
extern "c" fn __error() *c_int;
extern "c" var __stdoutp: *anyopaque; // Darwin's `stdout`
extern "c" var __stderrp: *anyopaque; // Darwin's `stderr`

const Handler = *const fn (c_int) callconv(.c) void;
extern "c" fn signal(sig: c_int, handler: ?Handler) ?Handler;
extern "c" fn raise(sig: c_int) c_int;
extern "c" fn fork() c_int;
extern "c" fn pipe(fds: *[2]c_int) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn execvp(path: [*:0]const u8, argv: [*][*:0]u8) c_int;
extern "c" fn waitpid(pid: c_int, status: *c_int, options: c_int) c_int;
extern "c" fn _exit(code: c_int) noreturn;
extern "c" fn getentropy(buf: *anyopaque, len: usize) c_int;
extern "c" fn clock() c_long;

const EOF: c_int = -1;
const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;
const ERANGE: c_int = 34;
const SIGABRT: c_int = 6;

/// The one place stdout arrival is forced. Every call site names the obligation
/// (B3, B4 or B5) it is discharging, so the set stays auditable: if a flush has
/// no obligation beside it, it is an observation nobody asked for and it goes.
fn arrive() void {
    _ = fflush(__stdoutp);
}

/// B5. `abort()` flushes stdio before dying; the backend's open-coded
/// `kill(getpid(), SIGABRT)` does not, which is why pre-trap output is lost
/// today for any program that does not link this object. Restoring the flush and
/// re-raising under the DEFAULT disposition reproduces `abort()` exactly: same
/// bytes, same signal, same exit code 134. `signal` rather than `sigaction`
/// because the disposition reset must happen before the re-raise and the
/// one-shot semantics here are the simpler proof.
fn abortFlush(sig: c_int) callconv(.c) void {
    arrive();
    _ = signal(sig, null); // SIG_DFL
    _ = raise(sig);
}

// ── the pre-main constructor ────────────────────────────────────────────────
/// Was: `setvbuf(stdout, _IOLBF)` — a per-newline arrival observation for the
/// life of the process, costing ~3,200 instructions per newline forever. Then:
/// a pre-main constructor installing the B5 handler and nothing else. Now: the
/// constructor is gone and the handler installs LAZILY, on first entry to any
/// exported function below.
///
/// WHY LAZY. Installing a signal handler for a process that never traps is
/// initialization `main` doesn't touch: dyld ran the initializer, touched its
/// page, and paid a `signal` call before the first user instruction, for every
/// io-linked program whether it traps or not. The handler's only job is B5 —
/// flush stdout before dying from SIGABRT — and B5 can only matter once the
/// program has touched this runtime, so installing on first touch preserves
/// every obligation B1-B5 with no pre-main work at all.
///
/// WHY UNGUARDED. A "did I install yet" flag is a writable global: a new
/// `__DATA` word, a new loader segment, a new page touched — the very costs
/// this removes. `signal` is idempotent, so every entry point installs
/// unconditionally; one cheap libc call beside the syscalls these functions
/// already make, and nothing for the loader to do before `main`.
inline fn ensureAbortFlush() void {
    _ = signal(SIGABRT, abortFlush);
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
    ensureAbortFlush();
    arrive(); // B3: about to block on input; the request must already be out.
    return readFd(0);
}

/// One newline-delimited message, trailing newline stripped. End of input is
/// NOT modelled as a value: when the peer closes the pipe with nothing further,
/// the process ends cleanly rather than answering an empty-string sentinel, so
/// the Idol server loop is `while true` with nothing to compare against.
export fn idol_io_read_line() callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    var cap: usize = 8192;
    var len: usize = 0;
    var buf: [*]u8 = @ptrCast(malloc(cap) orelse return null);
    arrive(); // B3: about to block on input; the request must already be out.
    var c = getchar();
    if (c == EOF) {
        free(buf);
        arrive(); // B2 on the early exit path, which does not return to `main`.
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

/// `path:read()` refusal. AN ABSENT FILE IS NOT A VALUE: every failure leg
/// here used to answer NULL, which flowed into Idol `str` and became
/// `strlen(NULL)` — measured UB recorded in `gaps/GAP-145.md` ("Ordered-work
/// item 1"), where a program observing the missing-file result printed NOTHING
/// AT ALL at exit 0. Failing closed is `law.id.one`: downstream semantic use
/// fails closed when the required facts are absent. The stdin precedent is
/// `idol_io_read_line`: end of input is not modelled as a value either.
///
/// The diagnostic is identity-first — `read-refused:<cause>:<path>` — on fd 2
/// raw, the `strFatal` convention from `idol_str_runtime.zig`. Sequential
/// writes rather than one assembled buffer because the path is unbounded and
/// the `oom` leg cannot malloc a message. `arrive()` first so bytes the
/// program wrote before the refusal are observable ahead of it, the same
/// flush-before-dying obligation B5 discharges for traps. `exit(1)`, not
/// `abort()`: a refusal is an answered outcome, not a trap.
///
/// A structured absent|present outcome family (letting source observe absence
/// as a value) remains OPEN under GAP-154/GAP-118; this function does not
/// admit it.
fn readRefused(cause: [*:0]const u8, path: [*:0]const u8) noreturn {
    arrive();
    _ = write(2, "read-refused:", "read-refused:".len);
    _ = write(2, cause, strlen(cause));
    _ = write(2, ":", 1);
    _ = write(2, path, strlen(path));
    _ = write(2, "\n", 1);
    exit(1);
}

export fn idol_io_read_path(path: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    const p = path orelse return idol_io_read_stdin();
    if (p[0] == 0) return idol_io_read_stdin();
    const f = fopen(p, "rb") orelse readRefused("absent", p);
    if (fseek(f, 0, SEEK_END) != 0) {
        _ = fclose(f);
        readRefused("io", p);
    }
    const sz = ftell(f);
    if (sz < 0) {
        _ = fclose(f);
        readRefused("io", p);
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        _ = fclose(f);
        readRefused("io", p);
    }
    const n: usize = @intCast(sz);
    const buf: [*]u8 = @ptrCast(malloc(n + 1) orelse {
        _ = fclose(f);
        readRefused("oom", p);
    });
    if (fread(buf, 1, n, f) != n) {
        free(buf);
        _ = fclose(f);
        readRefused("io", p);
    }
    _ = fclose(f);
    buf[n] = 0;
    return @ptrCast(buf);
}

/// 1-based. A missing index is UNKNOWN (null), not "" — the two are different
/// answers and collapsing them is what GAP-118 records.
export fn idol_os_arg(i: i64) callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    if (i < 1) return null;
    const argc: i64 = _NSGetArgc().*;
    const argv = _NSGetArgv().*;
    if (i >= argc) return null;
    return argv[@intCast(i)];
}

/// Failure is UNKNOWN (null), not "". GAP-118, same rule as `idol_os_arg`.
export fn idol_os_cwd() callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
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


export fn idol_io_open(path: ?[*:0]const u8, mode: ?[*:0]const u8) callconv(.c) i64 {
    ensureAbortFlush();
    const p = path orelse return 0;
    const m = mode orelse return 0;
    const f = fopen(p, m) orelse return 0;
    return @intCast(@intFromPtr(f));
}

export fn idol_io_write_handle(handle: i64, text: ?[*:0]const u8) callconv(.c) i64 {
    ensureAbortFlush();
    if (handle == 0) return 1;
    const f: *anyopaque = @ptrFromInt(@as(usize, @intCast(handle)));
    const s = text orelse return 1;
    return if (fputs(s, f) == -1) 1 else 0;
}

export fn idol_io_stdout_handle() callconv(.c) i64 {
    ensureAbortFlush();
    return @intCast(@intFromPtr(__stdoutp));
}

export fn idol_io_stderr_handle() callconv(.c) i64 {
    ensureAbortFlush();
    return @intCast(@intFromPtr(__stderrp));
}

export fn idol_io_close_handle(handle: i64) callconv(.c) i64 {
    ensureAbortFlush();
    if (handle == 0) return 1;
    const f: *anyopaque = @ptrFromInt(@as(usize, @intCast(handle)));
    return if (fclose(f) != 0) 1 else 0;
}

export fn idol_os_remove(path: ?[*:0]const u8) callconv(.c) i64 {
    ensureAbortFlush();
    const p = path orelse return 0;
    return if (unlink(p) == 0) 1 else 0;
}

export fn idol_os_execute(cmd: ?[*:0]const u8) callconv(.c) i64 {
    ensureAbortFlush();
    const c = cmd orelse return 1;
    arrive(); // B4: the child inherits fd 1 and must not overtake our bytes.
    const rc = system(c);
    if (rc == -1) return 1;
    // WIFEXITED / WEXITSTATUS, spelled out rather than imported.
    if ((rc & 0x7f) == 0) return if (((rc >> 8) & 0xff) == 0) 0 else 1;
    return 1;
}

export fn idol_process_capture(cmd: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    const c = cmd orelse return emptyHeap();
    arrive(); // B4: the child inherits fd 1 and must not overtake our bytes.
    const f = popen(c, "r") orelse return emptyHeap();
    const out = readFd(fileno(f));
    _ = pclose(f);
    return out;
}

/// True per-process incarnation: 32 hex chars from 16 bytes of kernel entropy,
/// generated ONCE per process and returned from static storage. Two server
/// processes never share a token; one process never changes it. This replaces
/// the `date +%s%N` boot marker the MCP tools previously shelled out for.
var incarnation_token: [33]u8 = undefined;
var incarnation_done: bool = false;

export fn idol_incarnation() callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    if (!incarnation_done) {
        var raw: [16]u8 = undefined;
        if (getentropy(&raw, 16) != 0) {
            var mixed: usize = @intFromPtr(&raw) ^ @as(usize, @bitCast(@as(isize, @intCast(clock()))));
            var k: usize = 0;
            while (k < 16) : (k += 1) {
                raw[k] = @truncate((mixed >> @intCast((k % 8) * 8)) ^ (k *% 0x9e3779b9));
                mixed = mixed *% 0x100000001b3 ^ @as(usize, raw[k]);
            }
        }
        const hex = "0123456789abcdef";
        var k: usize = 0;
        while (k < 16) : (k += 1) {
            incarnation_token[2 * k] = hex[raw[k] >> 4];
            incarnation_token[2 * k + 1] = hex[raw[k] & 15];
        }
        incarnation_token[32] = 0;
        incarnation_done = true;
    }
    return @ptrCast(&incarnation_token);
}

/// argv-exec: run `prog` with arguments, feed `input` on stdin, capture stdout.
/// `args` carries the argument vector as elements separated by 0x1F (ASCII unit
/// separator); the runtime splits on that byte and calls execvp with a real
/// argv array. NO SHELL IS INVOLVED at any point: unlike gatecap, no command
/// string is ever assembled or reinterpreted, so argument bytes cannot inject.
/// Returns captured stdout, or "" when the spawn itself fails.
export fn idol_process_execap(prog: ?[*:0]const u8, args: ?[*:0]const u8, input: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    ensureAbortFlush();
    const p = prog orelse return emptyHeap();
    const a = args orelse return emptyHeap();
    const inp = input orelse "";
    arrive(); // B4: the child inherits fd 1 and must not overtake our bytes.
    var nargs: usize = 0;
    if (a[0] != 0) {
        nargs = 1;
        var ci: usize = 0;
        while (a[ci] != 0) : (ci += 1) {
            if (a[ci] == 0x1f) nargs += 1;
        }
    }
    var argv_buf: [34]?[*:0]u8 = undefined;
    if (nargs + 2 > argv_buf.len) return emptyHeap();
    const argv: [*]?[*:0]u8 = &argv_buf;
    argv[0] = @ptrCast(@constCast(p));
    var slot: usize = 1;
    if (nargs > 0) {
        var start: usize = 0;
        var ai: usize = 0;
        const amut: [*]u8 = @ptrCast(@constCast(a));
        while (true) {
            const b: u8 = a[ai];
            if (b == 0x1f or b == 0) {
                amut[ai] = 0;
                argv[slot] = @ptrCast(amut + start);
                slot += 1;
                if (b == 0) break;
                start = ai + 1;
            }
            ai += 1;
        }
    }
    argv[nargs + 1] = null;
    var in_pipe: [2]c_int = undefined;
    var out_pipe: [2]c_int = undefined;
    if (pipe(&in_pipe) != 0 or pipe(&out_pipe) != 0) {
        return emptyHeap();
    }
    const pid = fork();
    if (pid < 0) {
        _ = close(in_pipe[0]);
        _ = close(in_pipe[1]);
        _ = close(out_pipe[0]);
        _ = close(out_pipe[1]);
        return emptyHeap();
    }
    if (pid == 0) {
        _ = dup2(in_pipe[0], 0);
        _ = dup2(out_pipe[1], 1);
        _ = close(in_pipe[0]);
        _ = close(in_pipe[1]);
        _ = close(out_pipe[0]);
        _ = close(out_pipe[1]);
        _ = execvp(p, @ptrCast(argv));
        _exit(127);
    }
    _ = close(in_pipe[0]);
    _ = close(out_pipe[1]);
    const inlen = strlen(inp);
    var written: usize = 0;
    while (written < inlen) {
        const n = write(in_pipe[1], inp + written, inlen - written);
        if (n <= 0) break;
        written += @intCast(n);
    }
    _ = close(in_pipe[1]);
    const out = readFd(out_pipe[0]);
    _ = close(out_pipe[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    return out orelse emptyHeap();
}

fn emptyHeap() ?[*:0]u8 {
    const e: [*]u8 = @ptrCast(malloc(1) orelse return null);
    e[0] = 0;
    return @ptrCast(e);
}
