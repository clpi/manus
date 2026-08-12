//! SH-03 production dispatch — the host consuming the Idol lexer's token stream.
//!
//! This is the seam `duo_lexer_bridge.tokenizeAuthority()` switches on. It binds
//! `duo_lexer_tokenize_full` from the artifact built out of
//! `lib/std/compiler/host.id` and rebuilds host `Token`s from the flat record
//! buffer, so the compiler can tokenize through Idol instead of `src/lexer.zig`.
//!
//! WHY `tokenize_full` AND NOT `tokenize_text`: `tokenize_text` writes six i64
//! per token and drops `float_val`. Dispatching on it would mis-read every float
//! literal while every kind- and text-based differential stayed green — which is
//! not hypothetical, it is exactly how GAP-021 hid for the whole life of  the Idol
//! lexer. The full entry carries all seven fields the host `Token` holds.
//!
//! WHY THE ARTIFACT IS BUILT FROM `host.id` AND NOT `lexer.id`: `--lib` never
//! initializes the primary module, so a lexer.id artifact's exports dereference
//! NULL. See gaps/GAP-020.md. `host.id` demotes the lexer to a dependency,
//! which is the path that initializes correctly.
const std = @import("std");
const lexer = @import("lexer.zig");

/// Temporary physical width of `duo_lexer_tokenize_full` records:
/// 0 kind · 1 line · 2 col · 3 int_val · 4 source_off · 5 text_len · 6 float_val.
/// GAP-107 deletes this host constant once the producer projects its schema.
pub const RECORD_SLOTS: usize = 7;

extern fn duo_lexer_tokenize_full(
    src: [*:0]const u8,
    file: [*:0]const u8,
    out: [*]i64,
    cap: i64,
    txt: i64,
    txtcap: i64,
) i64;

/// GAP-017 closed: the Idol lexer returns a REJECTION rather than aborting the
/// process. Negative returns are offset by 100 so they cannot be confused with
/// -1 (buffer too small), and the codes mirror `lexer.LexError`'s order.
extern fn duo_lexer_error_line(src: [*:0]const u8, file: [*:0]const u8) i64;

pub const DispatchError = error{
    BufferTooSmall,
    EmbeddedNul,
    InvalidBufferAddress,
    InvalidEndToken,
    InvalidRecordCount,
    InvalidRejectionCode,
    InvalidSourceSpan,
    InvalidTokenKind,
    InvalidTokenLocation,
    OutOfMemory,
    SourceTooLarge,
} || lexer.LexError;

/// Line of a source rejection. An invalid diagnostic record is an ABI failure,
/// not a fabricated source location.
pub fn errorLine(src: [:0]const u8, file: [:0]const u8) error{InvalidTokenLocation}!u32 {
    const line = duo_lexer_error_line(src.ptr, file.ptr);
    if (line <= 0) return error.InvalidTokenLocation;
    return std.math.cast(u32, line) orelse error.InvalidTokenLocation;
}

fn lexErrorFromCode(code: i64) DispatchError {
    return switch (code) {
        -101 => lexer.LexError.UnterminatedString,
        -102 => lexer.LexError.UnterminatedLongString,
        -103 => lexer.LexError.InvalidEscape,
        -104 => lexer.LexError.UnexpectedChar,
        -105 => lexer.LexError.InsufficientIndent,
        else => DispatchError.InvalidRejectionCode,
    };
}

fn tokenKindFromOrdinal(raw: i64) ?lexer.TokenKind {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    comptime {
        for (enum_info.field_values, 0..) |value, ordinal| {
            if (value != ordinal) @compileError("TokenKind ABI requires contiguous ordinals");
        }
    }
    if (raw < 0 or raw >= enum_info.field_names.len) return null;
    return @enumFromInt(@as(enum_info.tag_type, @intCast(raw)));
}

fn decodeRecords(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    records: []const i64,
    record_count: i64,
) DispatchError![]lexer.Token {
    const count = std.math.cast(usize, record_count) orelse return DispatchError.InvalidRecordCount;
    if (count == 0) return DispatchError.InvalidRecordCount;
    const used_slots = std.math.mul(usize, count, RECORD_SLOTS) catch
        return DispatchError.InvalidRecordCount;
    if (used_slots > records.len) return DispatchError.InvalidRecordCount;

    const tokens = try allocator.alloc(lexer.Token, count);
    errdefer allocator.free(tokens);

    for (tokens, 0..) |*tok, i| {
        const r = records[i * RECORD_SLOTS ..][0..RECORD_SLOTS];
        const kind = tokenKindFromOrdinal(r[0]) orelse
            return DispatchError.InvalidTokenKind;
        const line = std.math.cast(u32, r[1]) orelse
            return DispatchError.InvalidTokenLocation;
        const col = std.math.cast(u32, r[2]) orelse
            return DispatchError.InvalidTokenLocation;
        if (line == 0 or col == 0) return DispatchError.InvalidTokenLocation;
        if (r[4] < 0 or r[5] < 0) return DispatchError.InvalidSourceSpan;
        const off = std.math.cast(usize, r[4]) orelse return DispatchError.InvalidSourceSpan;
        const len = std.math.cast(usize, r[5]) orelse return DispatchError.InvalidSourceSpan;
        if (off > src.len or len > src.len - off) return DispatchError.InvalidSourceSpan;
        const final = i + 1 == count;
        if (kind == .eof) {
            if (!final or len != 0) return DispatchError.InvalidEndToken;
            // Generated C publishes end-of-content offset against strlen; dispatch
            // passes a NUL-terminated copy whose .len includes the sentinel.
            const end_ok = off == src.len or (src.len > 0 and off + 1 == src.len and src[src.len - 1] == 0);
            if (!end_ok) return DispatchError.InvalidEndToken;
        } else if (final) {
            return DispatchError.InvalidEndToken;
        }

        tok.* = .{
            .kind = kind,
            .loc = .{ .file = file, .line = line, .col = col },
            .text = src[off .. off + len],
            .int_val = r[3],
            .float_val = @bitCast(r[6]),
        };
    }
    return tokens;
}

/// Tokenize `src` through the Idol lexer, returning host `Token`s.
///
/// `text` slices point into `src`, using source offsets published by  the Idol
/// lexer. The host does not reconstruct provenance from copied token bytes.
pub fn tokenize(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
) DispatchError![]lexer.Token {
    if (std.mem.indexOfScalar(u8, src, 0) != null or
        std.mem.indexOfScalar(u8, file, 0) != null)
        return DispatchError.EmbeddedNul;

    // One record per byte is a safe upper bound: every token consumes at least
    // one source byte, plus one for the terminating EOF. Sized rather than
    // guessed, so a short read can never masquerade as a short file.
    const cap = std.math.add(usize, src.len, 2) catch return DispatchError.SourceTooLarge;
    const slot_count = std.math.mul(usize, cap, RECORD_SLOTS) catch
        return DispatchError.SourceTooLarge;
    const cap_i64 = std.math.cast(i64, cap) orelse return DispatchError.SourceTooLarge;
    const records = try allocator.alloc(i64, slot_count);
    defer allocator.free(records);

    const n = duo_lexer_tokenize_full(
        src.ptr,
        file.ptr,
        records.ptr,
        cap_i64,
        0,
        0,
    );
    if (n == -1) return DispatchError.BufferTooSmall;
    // A malformed source is a rejection the caller reports, not a truncated
    // stream — a short read that looks like a short file is the one failure a
    // parser cannot detect.
    if (n < 0) return lexErrorFromCode(n);

    // GAP-022's first repair copied every token into an arena, then searched
    // the source for that copy. That preserved parser pointer arithmetic but
    // left source provenance as host reconstruction. Slot 4 is now the exact
    // zero-based text offset decided by the Idol lexer. Reject an impossible
    // span instead of silently falling back to copied bytes.
    return decodeRecords(allocator, src, file, records, n);
}

/// Drive `lex` from the Idol lexer's token stream instead of the host scanner.
///
/// This is the ONE production routing entry. It used to live in main.zig as a
/// private helper, which is why the compile driver tokenized through Idol while
/// codegen's module-embed paths — which build their own `Lexer` + `Parser` to
/// decide native embedding and to emit required modules — still ran the host
/// scanner. Two scanners deciding one compilation is exactly the shape that
/// hides a divergence: the driver would accept a source the embed path lexed
/// differently, and nothing would report it.
///
/// Every failure is returned. The host scanner is a differential oracle, not a
/// production fallback: resource pressure must not silently restore host
/// lexical authority.
///
/// The token pack outlives `lex`. The NUL-terminated source and file copies are
/// needed only for the generated-C call; every token view is rebased to the
/// caller-owned source and file before those copies are released.
pub fn route(
    alloc: std.mem.Allocator,
    lex: *lexer.Lexer,
    src: []const u8,
    file: []const u8,
) !void {
    const bridge = @import("duo_lexer_bridge.zig");
    const zsrc = try std.mem.concatWithSentinel(alloc, u8, &.{src}, 0);
    defer alloc.free(zsrc);
    const zfile = try std.mem.concatWithSentinel(alloc, u8, &.{file}, 0);
    defer alloc.free(zfile);

    // GAP-145: tracked `duo_lexer_tokenize.c` is stale on `#` comment skip and
    // KIND_EOF ordinals for canonical `.id`. Host scanner owns `.id` admission
    // until regeneration from `lib/std/compiler/host.id`.
    const toks: []lexer.Token = if (bridge.isIdolSourcePath(file))
        try tokenizeHost(alloc, zsrc, zfile)
    else
        tokenize(alloc, zsrc, zfile) catch |e| switch (e) {
            error.UnterminatedString,
            error.UnterminatedLongString,
            error.InvalidNumber,
            error.UnexpectedChar,
            error.InvalidEscape,
            => {
                lex.last_error_loc = .{ .file = file, .line = try errorLine(zsrc, zfile), .col = 1 };
                return e;
            },
            else => return e,
        };
    errdefer alloc.free(toks);
    for (toks) |*tok| {
        tok.loc.file = file;
        if (tok.text.len == 0) continue;
        const off = @intFromPtr(tok.text.ptr) - @intFromPtr(zsrc.ptr);
        std.debug.assert(off + tok.text.len <= src.len);
        tok.text = src[off .. off + tok.text.len];
    }
    try lex.useDuoTokens(toks);
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

/// The property production dispatch rests on: for any source, the Idol lexer and
/// `src/lexer.zig` produce the SAME token stream — every field, not just kinds.
///
/// Existing SH-03 differentials compare fingerprints, which fold kinds (and,
/// separately, text). Neither reads `int_val` or `float_val`, which is how
/// GAP-021 survived — every float literal lexed to its integer part while all
/// gates stayed green. This compares the whole record.
pub fn differential(allocator: std.mem.Allocator, src: [:0]const u8, file: [:0]const u8) !void {
    const host = try tokenizeHost(allocator, src, file);
    defer allocator.free(host);

    const idol = try tokenize(allocator, src, file);
    defer allocator.free(idol);

    if (host.len != idol.len) return error.TokenCountMismatch;
    for (host, idol) |h, d| {
        if (h.kind != d.kind) return error.TokenKindMismatch;
        if (h.loc.line != d.loc.line) return error.TokenLineMismatch;
        if (h.loc.col != d.loc.col) return error.TokenColMismatch;
        if (!std.mem.eql(u8, h.text, d.text)) return error.TokenTextMismatch;
        if (h.int_val != d.int_val) return error.TokenIntMismatch;
        if (h.float_val != d.float_val) return error.TokenFloatMismatch;
    }
}

test "duo_lexer_dispatch: malformed generated records fail closed" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "";
    const file: [:0]const u8 = "record.id";
    var record = [_]i64{
        @intFromEnum(lexer.TokenKind.eof),
        1,
        1,
        0,
        0,
        0,
        0,
    };

    const valid = try decodeRecords(a, source, file, &record, 1);
    defer a.free(valid);
    try std.testing.expectEqual(lexer.TokenKind.eof, valid[0].kind);

    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, "x", file, &record, 1),
    );
    record[5] = 1;
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, "x", file, &record, 1),
    );
    record[5] = 0;
    record[0] = @intFromEnum(lexer.TokenKind.name);
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = @intFromEnum(lexer.TokenKind.eof);

    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 0),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, -1),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 2),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, std.math.maxInt(i64)),
    );

    record[0] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidTokenKind,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = -1;
    try std.testing.expectError(
        DispatchError.InvalidTokenKind,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = @intFromEnum(lexer.TokenKind.eof);

    record[1] = -1;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[1] = 0;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[1] = 1;
    record[2] = 0;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[2] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[2] = 1;

    record[4] = 1;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = 0;
    record[5] = -1;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = -1;
    record[5] = 0;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = 0;
    record[5] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );

    try std.testing.expectEqual(
        DispatchError.InvalidRejectionCode,
        lexErrorFromCode(-105),
    );

    var premature = [_]i64{
        @intFromEnum(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0,
        @intFromEnum(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0,
    };
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, source, file, &premature, 2),
    );
}

test "duo_lexer_dispatch: production route rejects embedded NUL" {
    const a = std.testing.allocator;
    const source: []const u8 = "x\x00y";
    var lex = lexer.Lexer.init(source, "nul.id");

    try std.testing.expectError(
        DispatchError.EmbeddedNul,
        route(a, &lex, source, "nul.id"),
    );
    try std.testing.expect(!lex.isDuoBacked());
    try std.testing.expectEqual(@as(?lexer.Loc, null), lex.last_error_loc);

    var file_lex = lexer.Lexer.init("", "bad\x00file.id");
    try std.testing.expectError(
        DispatchError.EmbeddedNul,
        route(a, &file_lex, "", "bad\x00file.id"),
    );
    try std.testing.expect(!file_lex.isDuoBacked());
}

test "duo_lexer_dispatch: Idol lexer drives a host token stream" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "fun add(a: i64): i64 = a + 1 end", "t.id");
    defer a.free(toks);
    try std.testing.expectEqual(@as(usize, 15), toks.len);
    try std.testing.expectEqual(lexer.TokenKind.kw_fun, toks[0].kind);
    try std.testing.expectEqualStrings("add", toks[1].text);
    try std.testing.expectEqual(@as(u32, 1), toks[0].loc.line);
}

test "duo_lexer_dispatch: production route fails closed on storage failure" {
    const src = "main: i64 = ()\n    0";
    for ([_]usize{ 0, 1, 2, 3 }) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var lex = lexer.Lexer.init(src, "lexer.id");

        try std.testing.expectError(
            error.OutOfMemory,
            route(failing.allocator(), &lex, src, "lexer.id"),
        );
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try std.testing.expect(!lex.isDuoBacked());
    }
}

test "duo_lexer_dispatch: production route releases temporary source copies" {
    const a = std.testing.allocator;
    const src: []const u8 = "main: i64 = ()\n    0";
    const file: []const u8 = "lexer.id";
    var lex = lexer.Lexer.init(src, file);

    try route(a, &lex, src, file);
    const toks = lex.duo_tokens.?;
    defer a.free(toks);

    try std.testing.expectEqual(@intFromPtr(src.ptr), @intFromPtr(toks[0].text.ptr));
    try std.testing.expectEqual(@intFromPtr(file.ptr), @intFromPtr(toks[0].loc.file.ptr));
}

test "duo_lexer_dispatch: Idol owns exact token source spans" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "a a \"a\" [[a]]";
    const toks = try tokenize(a, source, "span.id");
    defer a.free(toks);

    const base = @intFromPtr(source.ptr);
    const expected = [_]usize{ 0, 2, 5, 10, source.len };
    try std.testing.expectEqual(expected.len, toks.len);
    for (toks, expected) |tok, offset| {
        try std.testing.expectEqual(offset, @intFromPtr(tok.text.ptr) - base);
    }
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
    for (cases) |case| try differential(a, case, "t.id");
}

// The float case is the one that was silently wrong. Name it separately so a
// regression breaks a test that says WHY, rather than shifting a count.
test "duo_lexer_dispatch: float literals carry their value" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "1.5", "t.id");
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
    try std.testing.expectError(
        lexer.LexError.UnterminatedString,
        tokenize(a, "s = \"unterminated", "bad.duo"),
    );
    try std.testing.expectError(
        lexer.LexError.UnterminatedLongString,
        tokenize(a, "s = [[unterminated", "bad.id"),
    );
}

test "duo_lexer_dispatch: a rejection carries its line" {
    try std.testing.expectEqual(@as(u32, 2), try errorLine("x = 1\ns = \"bad", "bad.duo"));
}

// GAP-023: do the shapes those proofs are built from — corpus data held as
// string literals, escapes included — tokenize identically? This compiles and
// runs (the first attempt used std.fs.cwd(), which this Zig version lacks, so it
// never built and its empty failure list read as a pass).
test "duo_lexer_dispatch: corpus-data-as-literals tokenizes identically" {
    const a = std.testing.allocator;
    try differential(a, "corpus = { \"a == b ~= c\", \"-- line\\nfun\", \"\\\"hi\\\" 'there'\" }", "proof.id");
    try differential(a, "h = 0 s = \"a\\tb\\nc\\\\d\" n = #s", "proof.duo");
}

// gap[042]. GAP-024 fixed `_int_of`'s DECIMAL accumulator and left the HEX one
// as `i64`, so `v * 16` on a hex literal at or above 2^63 was signed overflow
// and the Idol lexer ABORTED THE PROCESS rather than returning a token.
//
// Nothing caught it because no differential case contained such a literal —
// lib/std does (`0xcbf29ce484222325` in heap.id, `0x8000000000000000` in
// encoding/varint.id and ml/gguf.id), but only the compile DRIVER routed
// through the Idol lexer and a driver never lexes the stdlib. It surfaced the
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
    for (cases) |case| try differential(a, case, "hex.id");
}

// The same literal, asserted by VALUE rather than by agreement, so a change
// that broke BOTH lexers identically would still fail here. 0xcbf29ce484222325
// is 14695981039346656037, which as an i64 bit pattern is -3750763034362895579.
test "duo_lexer_dispatch: gap[042] — the FNV offset basis carries its bits" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "0xcbf29ce484222325", "hex.id");
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[0].kind);
    try std.testing.expectEqual(@as(i64, -3750763034362895579), toks[0].int_val);
}

// GAP-024, found while probing GAP-023 and NOT its cause: the host lexer
// overflows on a u64 literal above i64 max, which is a value Idol's u64 can
// represent. This is a real divergence in its own right; it does NOT explain the
// two regressing proofs, whose u64 fingerprint appears only in a COMMENT.
//
// Left failing on purpose — it is the only thing that makes the divergence
// visible, and deleting it to keep a count green restores the blindness.
test "duo_lexer_dispatch: GAP-024 — u64 literal above i64 max" {
    const a = std.testing.allocator;
    try differential(a, "fingerprint = 13636438360258349679", "u64.id");
}
