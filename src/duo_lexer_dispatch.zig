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

// GAP-023's first isolation step. The two proofs that regress under
// .duo_native carry lexer corpus data as string literals, so the hypothesis was
// that the compiler lexing ITSELF with Duo changes how that data is read. This
// feeds those exact files through the differential: if the streams agree, the
// divergence is NOT in tokenization and the hypothesis is dead.
test "duo_lexer_dispatch: GAP-023 — the regressing proofs tokenize identically" {
    const a = std.testing.allocator;
    const files = [_][]const u8{
        "examples/pass16_lexer_fingerprint_differential.duo",
        "examples/pass16_lexer_text_differential.duo",
    };
    var checked: usize = 0;
    for (files) |path| {
        const f = std.fs.cwd().openFile(path, .{}) catch continue;
        defer f.close();
        const text = f.readToEndAllocOptions(a, 1 << 22, null, .of(u8), 0) catch continue;
        defer a.free(text);
        try differential(a, text, "proof.duo");
        checked += 1;
    }
    // Without this the test passes by skipping both files — the silent pass this
    // whole seam keeps producing.
    try std.testing.expectEqual(files.len, checked);
}
