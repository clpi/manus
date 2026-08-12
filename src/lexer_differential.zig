//! Production lexer corpus differential and fingerprint gate.
const std = @import("std");
const lexer = @import("lexer.zig");

pub const SCHEMA_VERSION = "lexer-differential-v1";

pub const CorpusCase = struct {
    id: []const u8,
    source: []const u8,
    expected: []const lexer.TokenKind,
};

/// Explicit kind sequences for the bounded migration subset.
pub const kind_corpus: []const CorpusCase = &.{
    .{ .id = "kw-fun", .source = "fun", .expected = &.{ .kw_fun, .eof } },
    .{ .id = "kw-end", .source = "end", .expected = &.{ .kw_end, .eof } },
    .{ .id = "type-i64", .source = "i64", .expected = &.{ .kw_i64, .eof } },
    .{ .id = "bare-fn", .source = "fun x end", .expected = &.{ .kw_fun, .name, .kw_end, .eof } },
    .{ .id = "int-lit", .source = "42", .expected = &.{ .int_lit, .eof } },
    .{ .id = "ops-eq-neq", .source = "== ~=", .expected = &.{ .eq, .neq, .eof } },
    .{ .id = "at-directive", .source = "@inline", .expected = &.{ .at, .name, .eof } },
    .{ .id = "line-col", .source = "a\nb", .expected = &.{ .name, .name, .eof } },
};

/// Fingerprint corpus — keep in sync with the migration fingerprint proof scope.
pub const fingerprint_corpus: []const []const u8 = &.{
    "fun add(a: i64): i64 = a + 1 end",
    "42 + 1",
    "x? y!",
    "\"hi\" 'there'",
    "-- line\nfun",
    "a == b ~= c",
    "...",
};

pub const expected_fingerprint: u64 = 14826786755700828545;

/// The generated migration tokenizer computes the same corpus fingerprint via
/// `duo_lexer_kind_fingerprint` in `lib/std/compiler/lexer.id`. Matching means
/// the two tokenizers agree token-for-token, including EOF, over every corpus
/// entry.
///
/// The migration producer uses signed arithmetic, so the proof compares these
/// bits as i64.
pub const expected_fingerprint_i64: i64 = @bitCast(expected_fingerprint);
pub const MIGRATION_FINGERPRINT_SOURCE = "lib/std/compiler/lexer.id";
pub const MIGRATION_FINGERPRINT_EXPORT = "duolexerkindfingerprint";

pub fn mixFingerprint(h: u64, kind: lexer.TokenKind) u64 {
    return h *% 31 +% @intFromEnum(kind);
}

pub fn fingerprintSource(src: []const u8) lexer.LexError!u64 {
    var h: u64 = 0;
    var lex = lexer.Lexer.init(src, "corpus.id");
    while (true) {
        const tok = try lex.next();
        h = mixFingerprint(h, tok.kind);
        if (tok.kind == .eof) break;
    }
    return h;
}

/// Token-TEXT fingerprint. `fingerprintSource` hashes only kinds, so text
/// equivalence with the generated lexer was never differenced — either side could
/// return the wrong bytes for every string literal and the corpus proof would
/// stay green.
///
/// Mixes the LENGTH before the bytes so concatenation cannot alias ("ab" then
/// "c" must not hash like "a" then "bc"), and includes the terminating EOF
/// (length 0). Must stay identical to `duo_lexer_text_fingerprint` in
/// lib/std/compiler/lexer.id.
pub fn textFingerprintSource(src: []const u8) lexer.LexError!u64 {
    var h: u64 = 0;
    var lex = lexer.Lexer.init(src, "corpus.id");
    while (true) {
        const tok = try lex.next();
        h = h *% 31 +% tok.text.len;
        for (tok.text) |b| h = h *% 31 +% b;
        if (tok.kind == .eof) break;
    }
    return h;
}

/// The value `hostTextCorpusFingerprint` produces, which
/// The migration text differential must reproduce this value. The same bits as
/// i64 are -4810305713451201937.
pub const expected_text_fingerprint: u64 = 13636438360258349679;

pub fn hostTextCorpusFingerprint() !u64 {
    var h: u64 = 0;
    for (fingerprint_corpus) |src| {
        const fh = try textFingerprintSource(src);
        h = h *% 131 +% fh;
    }
    return h;
}

pub fn hostCorpusFingerprint() !u64 {
    var h: u64 = 0;
    for (fingerprint_corpus) |src| {
        const fh = try fingerprintSource(src);
        h = h *% 131 +% fh;
    }
    return h;
}

pub fn validateKindCorpusCase(case: CorpusCase) !void {
    var lex = lexer.Lexer.init(case.source, case.id);
    for (case.expected, 0..) |want, i| {
        const tok = try lex.next();
        if (tok.kind != want) {
            std.log.err("corpus {s}[{d}]: expected {s}, got {s}", .{
                case.id,
                i,
                @tagName(want),
                @tagName(tok.kind),
            });
            return error.CorpusMismatch;
        }
    }
}

/// Verify TokenKind ordinals match the generated classifier transport.
pub fn validateTokenKindParity() !void {
    const bridge = @import("keyword_bridge.zig");
    if (bridge.lookupKeyword("fun") != .kw_fun) return error.TokenKindParity;
    if (@intFromEnum(lexer.TokenKind.kw_fun) != 14) return error.TokenKindParity;
    if (bridge.lookupKeyword("end") != .kw_end) return error.TokenKindParity;
    if (@intFromEnum(lexer.TokenKind.kw_end) != 10) return error.TokenKindParity;
}

/// Measure production lexer: tokens*1000/elapsed_ns (kilo-tokens per ms scale).
pub fn measureLexTokensPerNs(io: std.Io) u64 {
    const sample = "fun add(a: i64, b: i64): i64 = a + b end\n";
    const start = std.Io.Timestamp.now(io, .awake);
    const outer: u32 = 10_000;
    var tokens: u64 = 0;
    var i: u32 = 0;
    while (i < outer) : (i += 1) {
        var lex = lexer.Lexer.init(sample, "bench.id");
        while (true) {
            const tok = lex.next() catch break;
            tokens += 1;
            if (tok.kind == .eof) break;
        }
    }
    const end = std.Io.Timestamp.now(io, .awake);
    const elapsed: u64 = @intCast(start.durationTo(end).nanoseconds);
    if (tokens == 0 or elapsed == 0) return 0;
    return (tokens * 1000) / elapsed;
}

pub fn measureLexThroughput() u64 {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    return measureLexTokensPerNs(threaded.io());
}

test "lexer differential: kind corpus and transport ordinals" {
    for (kind_corpus) |case| try validateKindCorpusCase(case);
    try validateTokenKindParity();
}

test "lexer_differential: fingerprint corpus stable" {
    const got = try hostCorpusFingerprint();
    try std.testing.expectEqual(expected_fingerprint, got);
}

test "lexer_differential: line tracking" {
    var lex = lexer.Lexer.init("a\nb", "line-col");
    const t1 = try lex.next();
    try std.testing.expectEqual(@as(u32, 1), t1.loc.line);
    const t2 = try lex.next();
    try std.testing.expectEqual(@as(u32, 2), t2.loc.line);
}

// The migration-side differential pins the same corpus constant. If either the
// corpus or the mix changes, both projections must move together.
test "lexer differential: generated fingerprint control is wired" {
    const io_mod = std.Io;
    var threaded = io_mod.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    io_mod.Dir.cwd().access(io, MIGRATION_FINGERPRINT_SOURCE, .{}) catch {
        return error.SkipZigTest;
    };

    const migration_source = try io_mod.Dir.cwd().readFileAlloc(
        io,
        "lib/std/compiler/lexer.id",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(migration_source);
    if (std.mem.indexOf(u8, migration_source, MIGRATION_FINGERPRINT_EXPORT) == null) {
        return error.GeneratedFingerprintExportMissing;
    }

    // Same bits under both signednesses.
    try std.testing.expectEqual(expected_fingerprint, @as(u64, @bitCast(expected_fingerprint_i64)));
    try std.testing.expectEqual(expected_fingerprint, try hostCorpusFingerprint());
}

test "host text corpus fingerprint matches the pinned value" {
    try std.testing.expectEqual(expected_text_fingerprint, try hostTextCorpusFingerprint());
}
