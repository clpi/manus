//! Native string helpers for the direct backend, in Zig.
//!
//! This file replaces `src/idol_str_bootstrap.c`. The direct backend used to
//! append that C source to its own clang link line, so a `--backend=direct`
//! binary that touched `s:has()`, `s:sub()`, `s:find()` or `s:to(i64)` was
//! compiled from C at link time. Retiring `--backend=c` while keeping that would
//! not make the compiler C-free; it would make the C invisible.
//!
//! WHAT IS AND IS NOT "C" HERE. Every `extern "c"` declaration below names a
//! libc entry point — `malloc`, `strstr`, `strtoll`, `write`, `abort`. Those are
//! the platform ABI: the same symbols Zig's own std calls, resolved by the
//! system dynamic linker, with no C translation unit anywhere. What is gone is
//! the hand-written C: a Lua-pattern matcher, a substring slicer and a numeric
//! parser that existed as C source files shipped beside the compiler.
//!
//! `strtoll` in particular is CALLED, not reimplemented, and that is deliberate.
//! Its accept/reject boundary is the observable behaviour of `s:to(i64)`, and it
//! has more edges than it looks: it skips `\v` and `\f` as leading whitespace
//! while the caller's own trailing-skip loop does not, so `"\v42"` parses and
//! `"42\v"` is a fatal error. Rewriting that by hand is how a port silently
//! changes an answer.
//!
//! `char` IS SIGNED on this target (arm64 Darwin — Apple deviates from AAPCS64
//! here, and it was measured, not assumed). The Lua matcher compares pattern
//! bytes held in `char` against a subject byte widened from `unsigned char`, so
//! a pattern byte >= 0x80 sign-extends to a negative `int` and can never equal a
//! subject byte in 0..255. Literal high bytes therefore NEVER match, and class
//! ranges spanning 0x80 behave as inverted. That is preserved exactly: see
//! `sChar` below, which is the only place the signedness is applied.

const NO_MATCH: usize = ~@as(usize, 0); // the C code's `(size_t)-1` sentinel
const MAXCAP: usize = 32; // DUO_LP_MAXCAP

// ── platform ABI ────────────────────────────────────────────────────────────
extern "c" fn malloc(n: usize) ?*anyopaque;
extern "c" fn free(p: ?*anyopaque) void;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strstr(hay: [*:0]const u8, needle: [*:0]const u8) ?[*:0]const u8;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn strtoll(s: [*:0]const u8, end: *?[*:0]const u8, base: c_int) c_longlong;
extern "c" fn strtod(s: [*:0]const u8, end: *?[*:0]const u8) f64;
extern "c" fn abort() noreturn;
extern "c" fn write(fd: c_int, buf: *const anyopaque, n: usize) isize;
extern "c" fn __error() *c_int; // Darwin errno location

const ERANGE: c_int = 34; // Darwin <sys/errno.h>

/// A pattern byte as the C code sees it: `char`, which is SIGNED here, widened
/// to `int`. Every comparison against a subject byte goes through this.
inline fn sChar(b: u8) c_int {
    return @as(i8, @bitCast(b));
}

// ── one-byte intern table ───────────────────────────────────────────────────
// The C file built this lazily under an `idol_one_ready` flag; a comptime table
// is the same bytes with no initialisation branch. Entry 0 is {0, 0}, so its
// address is the canonical empty string — that is what the C returned for every
// out-of-range index, and callers depend on getting a non-NULL "".
const one_table: [256][2]u8 = blk: {
    var t: [256][2]u8 = undefined;
    for (&t, 0..) |*e, c| {
        e[0] = @intCast(c);
        e[1] = 0;
    }
    break :blk t;
};

inline fn onePtr(c: u8) [*:0]const u8 {
    return @ptrCast(&one_table[c][0]);
}

// ── exported: single-byte index ─────────────────────────────────────────────
export fn idol_str_at(s: ?[*:0]const u8, i: i64) callconv(.c) [*:0]const u8 {
    const str = s orelse return onePtr(0);
    if (i < 1) return onePtr(0);
    var k: i64 = 1;
    var p: usize = 0;
    while (str[p] != 0) {
        if (k == i) return onePtr(str[p]);
        p += 1;
        k += 1;
    }
    return onePtr(0);
}

fn emptyOwned() [*:0]const u8 {
    const raw = malloc(1) orelse return onePtr(0);
    const out: [*]u8 = @ptrCast(raw);
    out[0] = 0;
    return @ptrCast(out);
}

// ── exported: substring ─────────────────────────────────────────────────────
// Lua's 1-based inclusive slice with negative indices counting from the end.
// The `start == end && start >= 1` shortcut fires BEFORE any length is taken,
// which is why `sub(s, 10, 10)` on a 3-byte string answers "" through the intern
// table rather than through the clamped path below.
export fn duo_str_sub(s: ?[*:0]const u8, i: i64, j: i64) callconv(.c) [*:0]const u8 {
    const str: [*:0]const u8 = s orelse "";
    var start = i;
    var end = j;
    if (start == end and start >= 1) return idol_str_at(str, start);
    const len: i64 = @intCast(strlen(str));
    if (start < 0) start = len + start + 1;
    if (end < 0) end = len + end + 1;
    if (start < 1) start = 1;
    if (end > len) end = len;
    if (start > end or start > len or end < 1) {
        // malloc(1) failure in the C answered NULL here; emptyOwned falls back
        // to the interned "" instead, which is the same bytes and cannot be a
        // NULL deref in a caller that never checked.
        return emptyOwned();
    }
    if (start == end) return idol_str_at(str, start);
    const sublen: usize = @intCast(end - start + 1);
    const raw = malloc(sublen + 1) orelse return str; // C returned the input
    const out: [*]u8 = @ptrCast(raw);
    _ = memcpy(raw, @ptrCast(str + @as(usize, @intCast(start - 1))), sublen);
    out[sublen] = 0;
    return @ptrCast(out);
}

// ── exported: str -> i64 ────────────────────────────────────────────────────
fn strFatal(msg: []const u8) noreturn {
    // `fprintf(stderr, "%s\n", msg)` on an unbuffered stream, as one write.
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..msg.len], msg);
    buf[msg.len] = '\n';
    _ = write(2, &buf, msg.len + 1);
    abort();
}

export fn duo_str_to_i64(s: ?[*:0]const u8) callconv(.c) i64 {
    const str = s orelse strFatal("to(i64): no string");
    var p: usize = 0;
    while (str[p] == ' ' or str[p] == '\t' or str[p] == '\n' or str[p] == '\r') p += 1;
    var endp: ?[*:0]const u8 = null;
    __error().* = 0;
    const start: [*:0]const u8 = @ptrCast(str + p);
    const v = strtoll(start, &endp, 10);
    const e = endp orelse strFatal("to(i64): not a number");
    if (@intFromPtr(e) == @intFromPtr(start)) strFatal("to(i64): not a number");
    var q: usize = 0;
    while (e[q] == ' ' or e[q] == '\t' or e[q] == '\n' or e[q] == '\r') q += 1;
    if (e[q] != 0) strFatal("to(i64): trailing text after number");
    if (__error().* == ERANGE) strFatal("to(i64): out of range");
    return @intCast(v);
}

/// `to(f64)(s)` — the other half of a conversion table that had only its
/// integer edge. Written against `duo_str_to_i64` line for line, deliberately:
/// the two are the same edge at two widths, and a caller must not have to know
/// which one it is using to know what a malformed numeral does.
///
/// `strtod` IS CALLED, NOT REIMPLEMENTED, for the reason this file's header
/// gives about `strtoll` — its accept boundary IS the observable behaviour of
/// the conversion, and hand-porting it is how a port silently changes an
/// answer. The ONE place Lua's numeral grammar is narrower is guarded here
/// instead: `strtod` reads `inf`, `infinity` and `nan`, and Lua's `tonumber`
/// does not, so a numeral must start with a digit or a decimal point after an
/// optional sign. That is the same test `codegen.zig` emits for `tonumber`, so
/// both backends refuse the same strings.
export fn duo_str_to_f64(s: ?[*:0]const u8) callconv(.c) f64 {
    const str = s orelse strFatal("to(f64): no string");
    var p: usize = 0;
    while (str[p] == ' ' or str[p] == '\t' or str[p] == '\n' or str[p] == '\r') p += 1;
    var body = p;
    if (str[body] == '+' or str[body] == '-') body += 1;
    const lead = str[body];
    if (!((lead >= '0' and lead <= '9') or lead == '.')) strFatal("to(f64): not a number");
    var endp: ?[*:0]const u8 = null;
    __error().* = 0;
    const start: [*:0]const u8 = @ptrCast(str + p);
    const v = strtod(start, &endp);
    const e = endp orelse strFatal("to(f64): not a number");
    if (@intFromPtr(e) == @intFromPtr(start)) strFatal("to(f64): not a number");
    var q: usize = 0;
    while (e[q] == ' ' or e[q] == '\t' or e[q] == '\n' or e[q] == '\r') q += 1;
    if (e[q] != 0) strFatal("to(f64): trailing text after number");
    if (__error().* == ERANGE) strFatal("to(f64): out of range");
    return v;
}

// ── exported: plain substring search ────────────────────────────────────────
export fn idol_str_has(hay: ?[*:0]const u8, needle: ?[*:0]const u8) callconv(.c) c_int {
    const h: [*:0]const u8 = hay orelse "";
    const n = needle orelse return 0;
    if (n[0] == 0) return 0;
    return if (strstr(h, n) != null) 1 else 0;
}

export fn idol_str_find(
    hay: ?[*:0]const u8,
    needle: ?[*:0]const u8,
    start_in: i64,
    plain: c_int,
) callconv(.c) i64 {
    const h: [*:0]const u8 = hay orelse "";
    const n = needle orelse return 0;
    if (n[0] == 0) return 0;
    var start = start_in;
    if (start < 1) start = 1;
    const hlen = strlen(h);
    // The C cast `(size_t)(start - 1)` on an already-clamped `start >= 1` is a
    // plain widening; no negative can reach it.
    if (@as(usize, @intCast(start - 1)) >= hlen) return 0;
    if (plain == 0) return 0; // pattern find is not implemented, and answers 0
    const from: [*:0]const u8 = @ptrCast(h + @as(usize, @intCast(start - 1)));
    const at = strstr(from, n) orelse return 0;
    return @intCast(@intFromPtr(at) - @intFromPtr(h) + 1);
}

// ── Lua pattern matcher ─────────────────────────────────────────────────────
// Ported instruction for instruction from the C. Pattern positions are `usize`
// offsets into `pat` rather than raw pointers, so every `p < end` in the C is an
// integer comparison here and the reads stay in bounds. `pat` always carries its
// own NUL, and `end` is never past it, so `pat[end]` is a legal read exactly
// where the C read `*end`.

// C-locale ctype, which is the only locale this program ever runs in (nothing
// calls setlocale). Measured against the platform's own tables for all 256
// values rather than assumed; bytes >= 0x80 are in no class at all.
inline fn isAlpha(c: c_int) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}
inline fn isCntrl(c: c_int) bool {
    return (c >= 0 and c <= 0x1F) or c == 0x7F;
}
inline fn isDigit(c: c_int) bool {
    return c >= '0' and c <= '9';
}
inline fn isLower(c: c_int) bool {
    return c >= 'a' and c <= 'z';
}
inline fn isUpper(c: c_int) bool {
    return c >= 'A' and c <= 'Z';
}
inline fn isSpace(c: c_int) bool {
    return c == ' ' or (c >= 0x09 and c <= 0x0D);
}
inline fn isAlnum(c: c_int) bool {
    return isAlpha(c) or isDigit(c);
}
inline fn isPunct(c: c_int) bool {
    return c >= 0x21 and c <= 0x7E and !isAlnum(c);
}
inline fn isXdigit(c: c_int) bool {
    return isDigit(c) or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f');
}

/// `%<spec>` against one subject byte. The default arm compares the spec as a
/// `char`, so `%<high byte>` can never match — see the signedness note above.
fn classSpec(spec: u8, c: c_int) bool {
    return switch (spec) {
        'a' => isAlpha(c),
        'c' => isCntrl(c),
        'd' => isDigit(c),
        'l' => isLower(c),
        'p' => isPunct(c),
        's' => isSpace(c),
        'u' => isUpper(c),
        'w' => isAlnum(c) or c == '_',
        'x' => isXdigit(c),
        'z' => c == 0,
        else => c == sChar(spec),
    };
}

/// `[...]` set test. Advances `pp` past the closing bracket, exactly where the C
/// left it — including the paths that run off `end` without ever seeing one.
fn classTest(c: c_int, pat: [*:0]const u8, pp: *usize, end: usize) bool {
    var p = pp.*;
    if (pat[p] != '[') return false;
    p += 1;
    var invert = false;
    if (p < end and pat[p] == '^') {
        invert = true;
        p += 1;
    }
    if (p < end and pat[p] == ']') {
        if (c == ']') {
            p += 1;
            while (p < end and pat[p] != ']') p += 1;
            if (p < end) p += 1;
            pp.* = p;
            return !invert;
        }
        p += 1;
    }
    var found = false;
    while (p < end and pat[p] != ']') {
        if (pat[p] == '%' and p + 1 < end) {
            p += 1;
            const spec = pat[p];
            p += 1;
            if (classSpec(spec, c)) found = true;
        } else if (p + 2 < end and pat[p + 1] == '-') {
            const lo = sChar(pat[p]);
            p += 2;
            const hi = sChar(pat[p]);
            p += 1;
            if (lo <= c and c <= hi) found = true;
        } else {
            if (c == sChar(pat[p])) found = true;
            p += 1;
        }
    }
    if (p < end and pat[p] == ']') p += 1;
    pp.* = p;
    return if (invert) !found else found;
}

fn itemMatch(c: c_int, pat: [*:0]const u8, pp: *usize, end: usize) bool {
    const p = pp.*;
    if (p >= end) return false;
    if (pat[p] == '.') {
        pp.* = p + 1;
        return c != 0;
    }
    if (pat[p] == '[') return classTest(c, pat, pp, end);
    if (pat[p] == '%' and p + 1 < end) {
        const spec = pat[p + 1];
        pp.* = p + 2;
        return classSpec(spec, c);
    }
    const lit = sChar(pat[p]);
    pp.* = p + 1;
    return c == lit;
}

/// Skip one pattern item, quantifier excluded. Returns the offset past it.
fn skipItem(pat: [*:0]const u8, p: usize, end: usize) usize {
    if (p >= end) return end;
    if (pat[p] == '.') return p + 1;
    if (pat[p] == '[') {
        var q = p + 1;
        if (q < end and pat[q] == '^') q += 1;
        if (q < end and pat[q] == ']') q += 1;
        while (q < end and pat[q] != ']') {
            if (pat[q] == '%' and q + 1 < end) q += 2 else q += 1;
        }
        if (q < end and pat[q] == ']') q += 1;
        return q;
    }
    if (pat[p] == '%' and p + 1 < end) {
        if (pat[p + 1] == 'b') return if (p + 4 <= end) p + 4 else end;
        return p + 2;
    }
    if (pat[p] == '(') {
        var q = p + 1;
        var depth: i32 = 1;
        while (q < end and depth > 0) {
            if (pat[q] == '(') depth += 1 else if (pat[q] == ')') depth -= 1;
            q += 1;
        }
        return q;
    }
    return p + 1;
}

/// One occurrence of item [p, item_end) at subject offset `si`. `%bXY` is the
/// only item that can consume more than one byte.
fn itemAt(
    s: [*:0]const u8,
    slen: usize,
    si: usize,
    pat: [*:0]const u8,
    p: usize,
    end: usize,
    consumed: *usize,
) bool {
    if (si >= slen) return false;
    if (p >= end) return false;
    const c: c_int = s[si];
    if (pat[p] == '.') {
        consumed.* = 1;
        return c != 0;
    }
    if (pat[p] == '[') {
        var pp = p;
        const m = classTest(c, pat, &pp, end);
        consumed.* = 1;
        return m;
    }
    if (pat[p] == '%' and p + 1 < end and pat[p + 1] == 'b') {
        if (p + 3 >= end) return false;
        const open = pat[p + 2];
        const close = pat[p + 3];
        if (c != open) return false;
        var depth: i32 = 1;
        var j = si + 1;
        while (j < slen and depth > 0) {
            if (s[j] == open) depth += 1 else if (s[j] == close) depth -= 1;
            j += 1;
        }
        if (depth != 0) return false;
        consumed.* = j - si;
        return true;
    }
    var pp = p;
    const m = itemMatch(c, pat, &pp, end);
    consumed.* = 1;
    return m;
}

const Caps = struct {
    s: [MAXCAP]usize = undefined,
    e: [MAXCAP]usize = undefined,
    n: usize = 0,
};

/// Backtracking match of pattern [p, end) at subject offset `si`. Answers the
/// final subject offset, or NO_MATCH.
///
/// THE CAPTURE INDEXING IS THE C's, defect included. A non-quantified group
/// writes `cap_s` at the CURRENT count, recurses (which may raise that count via
/// nested groups), then writes `cap_e` at the count as it stands AFTERWARDS — so
/// a nested group makes the two halves of one span land in different slots.
/// A quantified group records `poss[0]..poss[n]`, the whole run, not the last
/// iteration its comment claims. Both are preserved: this is a port, and a port
/// that fixes behaviour on the way past is a rewrite.
fn matchRec(
    s: [*:0]const u8,
    slen: usize,
    si: usize,
    pat: [*:0]const u8,
    p: usize,
    end: usize,
    caps: *Caps,
) usize {
    if (p >= end) return si;
    if (pat[p] == '$' and p + 1 == end) return if (si == slen) si else NO_MATCH;
    if (pat[p] == ')') return NO_MATCH;
    if (pat[p] == '(') {
        var close = p + 1;
        var depth: i32 = 1;
        while (close < end) {
            if (pat[close] == '(') {
                depth += 1;
            } else if (pat[close] == ')') {
                depth -= 1;
                if (depth == 0) break;
            }
            close += 1;
        }
        if (close >= end) return NO_MATCH;
        const after = close + 1;
        const op: u8 = if (after < end) pat[after] else 0;
        if (op == '*' or op == '+' or op == '-' or op == '?') {
            const rest = after + 1;
            var maxn: usize = 0;
            const raw = malloc((slen - si + 1) * @sizeOf(usize)) orelse return NO_MATCH;
            const poss: [*]usize = @ptrCast(@alignCast(raw));
            defer free(raw);
            poss[0] = si;
            var cur = si;
            while (cur < slen) {
                const save = caps.n;
                const r = matchRec(s, slen, cur, pat, p + 1, close, caps);
                if (r == NO_MATCH or r == cur) {
                    caps.n = save;
                    break;
                }
                cur = r;
                maxn += 1;
                poss[maxn] = cur;
            }
            const minn: usize = if (op == '+') 1 else 0;
            const maxc: usize = if (op == '?') (if (maxn > 0) 1 else 0) else maxn;
            if (maxc < minn) return NO_MATCH;
            const slot = caps.n;
            // The C had no bound here and would smash its 32-slot arrays. That
            // is undefined behaviour, not behaviour to preserve; refusing the
            // match is the only defined answer available.
            if (slot >= MAXCAP) return NO_MATCH;
            if (op == '-') {
                var n = minn;
                while (n <= maxc) : (n += 1) {
                    const save = caps.n;
                    caps.s[slot] = poss[0];
                    caps.e[slot] = poss[n];
                    caps.n = slot + 1;
                    const r = matchRec(s, slen, poss[n], pat, rest, end, caps);
                    if (r != NO_MATCH) return r;
                    caps.n = save;
                }
                return NO_MATCH;
            }
            var n = maxc;
            while (true) {
                const save = caps.n;
                caps.s[slot] = poss[0];
                caps.e[slot] = poss[n];
                caps.n = slot + 1;
                const r = matchRec(s, slen, poss[n], pat, rest, end, caps);
                if (r != NO_MATCH) return r;
                caps.n = save;
                if (n == minn) break;
                n -= 1;
            }
            return NO_MATCH;
        }
        if (caps.n >= MAXCAP) return NO_MATCH;
        caps.s[caps.n] = si;
        const r = matchRec(s, slen, si, pat, p + 1, close, caps);
        if (r == NO_MATCH) return NO_MATCH;
        if (caps.n >= MAXCAP) return NO_MATCH;
        caps.e[caps.n] = r;
        caps.n += 1;
        return matchRec(s, slen, r, pat, after, end, caps);
    }

    const item_end = skipItem(pat, p, end);
    if (item_end == p) return NO_MATCH;
    const op: u8 = if (item_end < end) pat[item_end] else 0;
    if (op == '*' or op == '+' or op == '-' or op == '?') {
        const rest = item_end + 1;
        var maxn: usize = 0;
        const raw = malloc((slen - si + 1) * @sizeOf(usize)) orelse return NO_MATCH;
        const poss: [*]usize = @ptrCast(@alignCast(raw));
        defer free(raw);
        poss[0] = si;
        var cur = si;
        while (cur < slen) {
            var consumed: usize = 0;
            if (!itemAt(s, slen, cur, pat, p, item_end, &consumed)) break;
            cur += consumed;
            maxn += 1;
            poss[maxn] = cur;
        }
        const minn: usize = if (op == '+') 1 else 0;
        const maxc: usize = if (op == '?') (if (maxn > 0) 1 else 0) else maxn;
        if (maxc < minn) return NO_MATCH;
        if (op == '-') {
            var n = minn;
            while (n <= maxc) : (n += 1) {
                const save = caps.n;
                const r = matchRec(s, slen, poss[n], pat, rest, end, caps);
                if (r != NO_MATCH) return r;
                caps.n = save;
            }
            return NO_MATCH;
        }
        var n = maxc;
        while (true) {
            const save = caps.n;
            const r = matchRec(s, slen, poss[n], pat, rest, end, caps);
            if (r != NO_MATCH) return r;
            caps.n = save;
            if (n == minn) break;
            n -= 1;
        }
        return NO_MATCH;
    }
    if (si >= slen) return NO_MATCH;
    var consumed: usize = 0;
    if (!itemAt(s, slen, si, pat, p, item_end, &consumed)) return NO_MATCH;
    return matchRec(s, slen, si + consumed, pat, item_end, end, caps);
}

fn matchCaps(
    s: [*:0]const u8,
    slen: usize,
    start: usize,
    pat: [*:0]const u8,
    pat_end: usize,
    ms: *usize,
    me: *usize,
    caps: *Caps,
) bool {
    var p: usize = 0;
    var anchored = false;
    if (p < pat_end and pat[p] == '^') {
        anchored = true;
        p += 1;
    }
    if (anchored) {
        if (start != 0) return false;
        caps.n = 0;
        const r = matchRec(s, slen, 0, pat, p, pat_end, caps);
        if (r == NO_MATCH) return false;
        ms.* = 0;
        me.* = r;
        return true;
    }
    var i = start;
    while (i <= slen) : (i += 1) {
        caps.n = 0;
        const r = matchRec(s, slen, i, pat, p, pat_end, caps);
        if (r != NO_MATCH) {
            ms.* = i;
            me.* = r;
            return true;
        }
    }
    return false;
}

fn strDup(s: [*:0]const u8, off: usize, len: usize) ?[*:0]u8 {
    const raw = malloc(len + 1) orelse return null;
    const out: [*]u8 = @ptrCast(raw);
    if (len != 0) _ = memcpy(raw, @ptrCast(s + off), len);
    out[len] = 0;
    return @ptrCast(out);
}

/// First match of `pat` in `s`. Answers capture 1 when the pattern has captures,
/// the whole match otherwise, and NULL when nothing matches.
export fn idol_str_match(s: ?[*:0]const u8, pat: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    const subject = s orelse return null;
    const pattern = pat orelse return null;
    const slen = strlen(subject);
    var ms: usize = 0;
    var me: usize = 0;
    var caps: Caps = .{};
    if (!matchCaps(subject, slen, 0, pattern, strlen(pattern), &ms, &me, &caps)) return null;
    if (caps.n > 0) return strDup(subject, caps.s[0], caps.e[0] - caps.s[0]);
    return strDup(subject, ms, me - ms);
}
