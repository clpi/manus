//! SH-03 production dispatch — the host consuming the Duo lexer's token stream.
//!
//! This is the seam `duo_lexer_bridge.tokenizeAuthority()` switches on. It binds
//! `duo_lexer_tokenize_full` from the artifact built out of
//! `lib/std/compiler/host.duo` and rebuilds host `Token`s from the flat record
//! buffer, so the compiler can tokenize through Duo instead of `src/lexer.zig`.
//!
//! WHY `tokenize_full` AND NOT `tokenize_text`: `tokenize_text` writes six i64
//! per token and drops `float_val`. Dispatching on it would mis-read every float
//! literal while every kind- and text-based differential stayed green — which is
//! not hypothetical, it is exactly how GAP-021 hid for the whole life of the Duo
//! lexer. The full entry carries all seven fields the host `Token` holds.
//!
//! WHY THE ARTIFACT IS BUILT FROM `host.duo` AND NOT `lexer.duo`: `--lib` never
//! initializes the primary module, so a lexer.duo artifact's exports dereference
//! NULL. See gaps/GAP-020.md. `host.duo` demotes the lexer to a dependency,
//! which is the path that initializes correctly.
const std = @import("std");
const lexer = @import("lexer.zig");

/// i64 slots per token in the `duo_lexer_tokenize_full` record buffer:
/// 0 kind · 1 line · 2 col · 3 int_val · 4 text_off · 5 text_len · 6 float_val.
pub const RECORD_SLOTS: usize = 7;

extern fn duo_lexer_tokenize_full(
    src: [*:0]const u8,
    file: [*:0]const u8,
    out: i64,
    cap: i64,
    txt: i64,
    txtcap: i64,
) i64;

/// Published by `lib/std/compiler/host.duo` so a consumer asserts the layout it
/// decodes rather than hard-coding it.
extern fn duo_lexer_host_stride() i64;

/// GAP-017 closed: the Duo lexer returns a REJECTION rather than aborting the
/// process. Negative returns are offset by 100 so they cannot be confused with
/// -1 (buffer too small), and the codes mirror `lexer.LexError`'s order.
extern fn duo_lexer_error_line(src: [*:0]const u8, file: [*:0]const u8) i64;

fn lexErrorFromCode(code: i64) lexer.LexError {
    return switch (code) {
        -101 => lexer.LexError.UnterminatedString,
        -102 => lexer.LexError.UnterminatedLongString,
        -103 => lexer.LexError.InvalidEscape,
        -104 => lexer.LexError.UnexpectedChar,
        else => lexer.LexError.UnexpectedChar,
    };
}

/// Line of the rejection, for a caller holding a negative code. Cold path.
pub fn errorLine(src: [:0]const u8, file: [:0]const u8) u32 {
    const line = duo_lexer_error_line(src.ptr, file.ptr);
    return if (line > 0) @intCast(line) else 1;
}

pub const DispatchError = error{
    BufferTooSmall,
    OutOfMemory,
} || lexer.LexError;

/// Tokenize `src` through the Duo lexer, returning host `Token`s.
///
/// `text` slices point into `text_arena`, which the caller owns and must keep
/// alive as long as the tokens are used — the same lifetime discipline as the
/// host lexer, whose token text points into the source buffer.
pub fn tokenize(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    text_arena: *std.ArrayList(u8),
) DispatchError![]lexer.Token {
    // One record per byte is a safe upper bound: every token consumes at least
    // one source byte, plus one for the terminating EOF. Sized rather than
    // guessed, so a short read can never masquerade as a short file.
    const cap: usize = src.len + 2;
    const records = try allocator.alloc(i64, cap * RECORD_SLOTS);
    defer allocator.free(records);

    try text_arena.resize(allocator, src.len + 1);

    const n = duo_lexer_tokenize_full(
        src.ptr,
        file.ptr,
        @intCast(@intFromPtr(records.ptr)),
        @intCast(cap),
        @intCast(@intFromPtr(text_arena.items.ptr)),
        @intCast(text_arena.items.len),
    );
    if (n == -1) return DispatchError.BufferTooSmall;
    // A malformed source is a rejection the caller reports, not a truncated
    // stream — a short read that looks like a short file is the one failure a
    // parser cannot detect.
    if (n < 0) return lexErrorFromCode(n);

    const count: usize = @intCast(n);
    const tokens = try allocator.alloc(lexer.Token, count);
    errdefer allocator.free(tokens);

    // GAP-022: token text must be a slice INTO THE SOURCE, not into the arena.
    // The parser recovers absolute offsets by pointer arithmetic against
    // `tok.text.ptr` (parse_attribute_args), so arena-backed text yields garbage
    // — index 26286 into a 188-byte file.
    //
    // No ABI change is needed to fix it. The field-for-field differential
    // against src/lexer.zig proves Duo's token text is byte-identical to the
    // host's, and the host's text IS a source slice — so every token's text is a
    // literal substring of the source and its offset is recoverable. Tokens
    // arrive in order, so one forward scan finds each in amortized O(n) without
    // the lexer publishing anything new.
    //
    // The arena is now only the transport buffer the ABI requires; nothing
    // points into it after this loop.
    var cursor: usize = 0;
    for (tokens, 0..) |*tok, i| {
        const r = records[i * RECORD_SLOTS ..][0..RECORD_SLOTS];
        const off: usize = @intCast(r[4]);
        const len: usize = @intCast(r[5]);
        const copied = text_arena.items[off .. off + len];

        // Zero-length text (EOF) has no position to find; anchor it at the
        // cursor so it still points into the source rather than nowhere.
        const src_text: []const u8 = if (len == 0)
            src[cursor..cursor]
        else if (std.mem.indexOfPos(u8, src, cursor, copied)) |at| blk: {
            cursor = at + len;
            break :blk src[at .. at + len];
        } else
            // Unreachable while the differential holds. Falling back to the
            // copy keeps the token CORRECT if it ever stops holding — a wrong
            // pointer is worse than a non-source one, and the differential is
            // what catches the latter.
            copied;

        tok.* = .{
            .kind = @enumFromInt(r[0]),
            .loc = .{ .file = file, .line = @intCast(r[1]), .col = @intCast(r[2]) },
            .text = src_text,
            .int_val = r[3],
            .float_val = @bitCast(r[6]),
        };
    }
    return tokens;
}

/// Drive `lex` from the Duo lexer's token stream instead of the host scanner.
///
/// This is the ONE production routing entry. It used to live in main.zig as a
/// private helper, which is why the compile driver tokenized through Duo while
/// codegen's module-embed paths — which build their own `Lexer` + `Parser` to
/// decide native embedding and to emit required modules — still ran the host
/// scanner. Two scanners deciding one compilation is exactly the shape that
/// hides a divergence: the driver would accept a source the embed path lexed
/// differently, and nothing would report it.
///
/// A Duo-side REJECTION is returned, not swallowed: the host scanner would
/// reject the same source, and silently falling back would hide a real
/// divergence behind a passing compile. Only an out-of-memory or buffer-sizing
/// failure falls back to the host scanner, because those are host-side and say
/// nothing about the source.
///
/// Allocations are not freed. The tokens, their NUL-terminated source copy and
/// the transport arena must outlive `lex`, and every caller's `lex` outlives
/// the function that owns the allocator — so freeing here would dangle. The
/// leak is bounded by the number of modules in one compilation, the same order
/// as the driver's own, and a compile is a process.
pub fn route(
    alloc: std.mem.Allocator,
    lex: *lexer.Lexer,
    src: []const u8,
    file: []const u8,
) !void {
    if (@import("duo_lexer_bridge.zig").tokenizeAuthority() != .duo_native) return;
    const zsrc = std.mem.concatWithSentinel(alloc, u8, &.{src}, 0) catch return;
    const zfile = std.mem.concatWithSentinel(alloc, u8, &.{file}, 0) catch return;
    const arena = alloc.create(std.ArrayList(u8)) catch return;
    arena.* = .empty;
    const toks = tokenize(alloc, zsrc, zfile, arena) catch |e| switch (e) {
        error.OutOfMemory, error.BufferTooSmall => return,
        else => {
            lex.last_error_loc = .{ .file = file, .line = errorLine(zsrc, zfile), .col = 1 };
            return e;
        },
    };
    // The scan above resolves token text against `zsrc`, the NUL-terminated
    // copy the C ABI requires. The parser holds the ORIGINAL `src`, and
    // srcOffsetOf compares pointers — so text pointing into the copy is "not in
    // the source" and attribute recovery fails. Rebase onto `src`; the copy is
    // byte-identical, so the offsets carry over exactly.
    for (toks) |*tok| {
        if (tok.text.len == 0) continue;
        const off = @intFromPtr(tok.text.ptr) - @intFromPtr(zsrc.ptr);
        if (off + tok.text.len <= src.len) tok.text = src[off .. off + tok.text.len];
    }
    lex.useDuoTokens(toks);
}

/// The ABI contract, asserted rather than assumed. A layout change in the Duo
/// lexer must fail here, at the seam, instead of silently shifting every field.
pub fn validateStride() !void {
    if (duo_lexer_host_stride() != 4) return error.UnexpectedTokenizeAllStride;
}

/// Tokenize `src` with the HOST lexer — the differential's other side.
fn tokenizeHost(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
) ![]lexer.Token {
    var lx = lexer.Lexer.init(src, file);
    var out: std.ArrayList(lexer.Token) = .empty;
    errdefer out.deinit(allocator);
    while (true) {
        const tok = try lx.next();
        try out.append(allocator, tok);
        if (tok.kind == .eof) break;
    }
    return out.toOwnedSlice(allocator);
}

/// The property production dispatch rests on: for any source, the Duo lexer and
/// `src/lexer.zig` produce the SAME token stream — every field, not just kinds.
///
/// Existing SH-03 differentials compare fingerprints, which fold kinds (and,
/// separately, text). Neither reads `int_val` or `float_val`, which is how
/// GAP-021 survived — every float literal lexed to its integer part while all
/// gates stayed green. This compares the whole record.
pub fn differential(allocator: std.mem.Allocator, src: [:0]const u8, file: [:0]const u8) !void {
    const host = try tokenizeHost(allocator, src, file);
    defer allocator.free(host);

    var arena: std.ArrayList(u8) = .empty;
    defer arena.deinit(allocator);
    const duo = try tokenize(allocator, src, file, &arena);
    defer allocator.free(duo);

    if (host.len != duo.len) return error.TokenCountMismatch;
    for (host, duo) |h, d| {
        if (h.kind != d.kind) return error.TokenKindMismatch;
        if (h.loc.line != d.loc.line) return error.TokenLineMismatch;
        if (h.loc.col != d.loc.col) return error.TokenColMismatch;
        if (!std.mem.eql(u8, h.text, d.text)) return error.TokenTextMismatch;
        if (h.int_val != d.int_val) return error.TokenIntMismatch;
        if (h.float_val != d.float_val) return error.TokenFloatMismatch;
    }
}

test "duo_lexer_dispatch: stride contract" {
    try validateStride();
}

test "duo_lexer_dispatch: Duo lexer drives a host token stream" {
    const a = std.testing.allocator;
    var arena: std.ArrayList(u8) = .empty;
    defer arena.deinit(a);
    const toks = try tokenize(a, "fun add(a: i64): i64 = a + 1 end", "t.duo", &arena);
    defer a.free(toks);
    try std.testing.expectEqual(@as(usize, 15), toks.len);
    try std.testing.expectEqual(lexer.TokenKind.kw_fun, toks[0].kind);
    try std.testing.expectEqualStrings("add", toks[1].text);
    try std.testing.expectEqual(@as(u32, 1), toks[0].loc.line);
}

test "duo_lexer_dispatch: token streams agree field for field" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "",
        "fun add(a: i64): i64 = a + 1 end",
        "x = 1.5 y = 42 z = 0xFF",
        "s = \"a\\tb\\nc\"",
        "a<=b and c>=d or e~=f",
        "-- comment\ny = 2 -- trailing\nz = 3",
        "s = [[raw \\n not an escape]]",
        "a = 1e3 b = 2.5e-2 c = 0.5",
    };
    for (cases) |case| try differential(a, case, "t.duo");
}

// The float case is the one that was silently wrong. Name it separately so a
// regression breaks a test that says WHY, rather than shifting a count.
test "duo_lexer_dispatch: float literals carry their value" {
    const a = std.testing.allocator;
    var arena: std.ArrayList(u8) = .empty;
    defer arena.deinit(a);
    const toks = try tokenize(a, "1.5", "t.duo", &arena);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.float_lit, toks[0].kind);
    try std.testing.expectEqual(@as(f64, 1.5), toks[0].float_val);
}

// GAP-017's regression test. Before the fix these aborted the process, so the
// compiler could not be routed through this lexer at all: every malformed
// source would have become a bare abort with no location instead of a
// diagnostic. Each must now be a catchable error.
test "duo_lexer_dispatch: malformed sources reject instead of aborting" {
    const a = std.testing.allocator;
    var arena: std.ArrayList(u8) = .empty;
    defer arena.deinit(a);
    try std.testing.expectError(
        lexer.LexError.UnterminatedString,
        tokenize(a, "s = \"unterminated", "bad.duo", &arena),
    );
    try std.testing.expectError(
        lexer.LexError.UnterminatedLongString,
        tokenize(a, "s = [[unterminated", "bad.duo", &arena),
    );
}

test "duo_lexer_dispatch: a rejection carries its line" {
    try std.testing.expectEqual(@as(u32, 2), errorLine("x = 1\ns = \"bad", "bad.duo"));
}

// GAP-023: do the shapes those proofs are built from — corpus data held as
// string literals, escapes included — tokenize identically? This compiles and
// runs (the first attempt used std.fs.cwd(), which this Zig version lacks, so it
// never built and its empty failure list read as a pass).
test "duo_lexer_dispatch: corpus-data-as-literals tokenizes identically" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "corpus = { \"a == b ~= c\", \"-- line\\nfun\", \"\\\"hi\\\" 'there'\" }",
        "h = 0 s = \"a\\tb\\nc\\\\d\" n = #s",
    };
    for (cases) |case| try differential(a, case, "proof.duo");
}

// gap[042]. GAP-024 fixed `_int_of`'s DECIMAL accumulator and left the HEX one
// as `i64`, so `v * 16` on a hex literal at or above 2^63 was signed overflow
// and the Duo lexer ABORTED THE PROCESS rather than returning a token.
//
// Nothing caught it because no differential case contained such a literal —
// lib/std does (`0xcbf29ce484222325` in heap.duo, `0x8000000000000000` in
// encoding/varint.duo and ml/gguf.duo), but only the compile DRIVER routed
// through the Duo lexer and a driver never lexes the stdlib. It surfaced the
// moment codegen's module-embed paths were routed through the same lexer.
//
// These three are the literals actually in the tree, plus the boundary either
// side of it. Field-for-field, so a wrong VALUE fails as loudly as an abort.
test "duo_lexer_dispatch: gap[042] — hex literals at and above 2^63" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "h = 0xcbf29ce484222325",
        "m = 0xFFFFFFFFFFFFFFFF",
        "s = 0x8000000000000000",
        "b = 0x7FFFFFFFFFFFFFFF",
        "x = 0xff y = 0x10 z = 0x0",
    };
    for (cases) |case| try differential(a, case, "hex.duo");
}

// The same literal, asserted by VALUE rather than by agreement, so a change
// that broke BOTH lexers identically would still fail here. 0xcbf29ce484222325
// is 14695981039346656037, which as an i64 bit pattern is -3750763034362895579.
test "duo_lexer_dispatch: gap[042] — the FNV offset basis carries its bits" {
    const a = std.testing.allocator;
    var arena: std.ArrayList(u8) = .empty;
    defer arena.deinit(a);
    const toks = try tokenize(a, "0xcbf29ce484222325", "hex.duo", &arena);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[0].kind);
    try std.testing.expectEqual(@as(i64, -3750763034362895579), toks[0].int_val);
}

// GAP-024, found while probing GAP-023 and NOT its cause: the host lexer
// overflows on a u64 literal above i64 max, which is a value Duo's u64 can
// represent. This is a real divergence in its own right; it does NOT explain the
// two regressing proofs, whose u64 fingerprint appears only in a COMMENT.
//
// Left failing on purpose — it is the only thing that makes the divergence
// visible, and deleting it to keep a count green restores the blindness.
test "duo_lexer_dispatch: GAP-024 — u64 literal above i64 max" {
    const a = std.testing.allocator;
    try differential(a, "fingerprint = 13636438360258349679", "u64.duo");
}
