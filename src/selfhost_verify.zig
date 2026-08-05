//! Pass 16 M1 — production-path verification (host differential + Duo proof hooks).
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");
const source_cursor = @import("source_cursor.zig");
const lexer_differential = @import("lexer_differential.zig");

pub const SCHEMA_VERSION = "selfhost-verify-v1";

pub const VerifyError = error{
    KeywordDifferentialFailed,
    KeywordFuzzFailed,
    SourceCursorDifferentialFailed,
    LexerCorpusFailed,
};

pub const KeywordVerifyResult = struct {
    exhaustive_pass: bool,
    fuzz_pass: bool,
    production_classifier: []const u8,
    keyword_count: usize,
};

pub const SourceCursorVerifyResult = struct {
    differential_pass: bool,
    corpus_cases: usize,
    indexing: []const u8,
};

pub const LexerVerifyResult = struct {
    corpus_pass: bool,
    corpus_cases: usize,
};

pub const VerifyResult = struct {
    keywords: KeywordVerifyResult,
    source_cursor: SourceCursorVerifyResult,
    lexer: LexerVerifyResult,
    all_pass: bool,
};

const cursor_corpus = [_]struct { text: []const u8, stop_line: u32, want_line: u32, want_col: u32 }{
    .{ .text = "a\nb\nc", .stop_line = 3, .want_line = 3, .want_col = 1 },
    .{ .text = "fun\nend", .stop_line = 2, .want_line = 2, .want_col = 1 },
    .{ .text = "x", .stop_line = 1, .want_line = 1, .want_col = 2 },
};

fn verifySourceCursorCorpus() bool {
    for (cursor_corpus) |case| {
        var c = source_cursor.ByteCursor.init(case.text, "corpus.duo");
        while (!c.eof()) {
            _ = c.advance();
            if (c.line == case.stop_line and c.col == 1) break;
        }
        const loc = c.loc();
        if (loc.line != case.want_line or loc.col != case.want_col) return false;
    }
    return true;
}

pub fn verifyKeywords() KeywordVerifyResult {
    const exhaustive = blk: {
        token_semantic.differentialValidateClassifiers() catch break :blk false;
        break :blk true;
    };
    const fuzz = token_semantic.differentialCheck(token_semantic.differential_fuzz_seed);
    return .{
        .exhaustive_pass = exhaustive,
        .fuzz_pass = fuzz,
        .production_classifier = token_semantic.production_classifier.name(),
        .keyword_count = token_semantic.keywords.len,
    };
}

pub fn verifySourceCursor() SourceCursorVerifyResult {
    const walk = source_cursor.walkReference("a\nb\nc", "test.duo");
    const walk_ok = walk.line == 3 and walk.col == 1;
    const corpus_ok = verifySourceCursorCorpus();
    const prod_ok = source_cursor.differentialProductionParity();
    return .{
        .differential_pass = walk_ok and corpus_ok and prod_ok,
        .corpus_cases = cursor_corpus.len,
        .indexing = "Duo 1-based ByteCursor + production ProductionCursor (0-based index)",
    };
}

pub fn verifyLexer() LexerVerifyResult {
    const pass = lexer_differential.validateCorpusOrBool();
    return .{
        .corpus_pass = pass,
        .corpus_cases = lexer_differential.kind_corpus.len,
    };
}

pub fn verifyAll() VerifyResult {
    const kw = verifyKeywords();
    const sc = verifySourceCursor();
    const lx = verifyLexer();
    return .{
        .keywords = kw,
        .source_cursor = sc,
        .lexer = lx,
        .all_pass = kw.exhaustive_pass and kw.fuzz_pass and sc.differential_pass and lx.corpus_pass,
    };
}

pub fn verifyKeywordsOrFail() VerifyError!KeywordVerifyResult {
    token_semantic.differentialValidateClassifiers() catch return error.KeywordDifferentialFailed;
    if (!token_semantic.differentialCheck(token_semantic.differential_fuzz_seed)) return error.KeywordFuzzFailed;
    return verifyKeywords();
}

pub fn verifySourceCursorOrFail() VerifyError!SourceCursorVerifyResult {
    const r = verifySourceCursor();
    if (!r.differential_pass) return error.SourceCursorDifferentialFailed;
    if (!source_cursor.differentialProductionParity()) return error.SourceCursorDifferentialFailed;
    return r;
}

pub fn verifyLexerOrFail() VerifyError!LexerVerifyResult {
    lexer_differential.validateCorpus() catch return error.LexerCorpusFailed;
    return verifyLexer();
}

pub fn verifyAllOrFail() VerifyError!VerifyResult {
    _ = try verifyKeywordsOrFail();
    _ = try verifySourceCursorOrFail();
    _ = try verifyLexerOrFail();
    return verifyAll();
}

pub fn writeVerifyJson(w: *std.Io.Writer) !void {
    const r = verifyAll();
    try w.print(
        "{{\"schema\":\"{s}\",\"all_pass\":{},\"keywords\":{{\"subsystem\":\"SH-02\",\"production_path\":\"{s}\",\"duo_projection\":\"lib/std/token/classify.duo\",\"exhaustive_pass\":{},\"fuzz_pass\":{},\"production_classifier\":\"{s}\",\"production_authority\":\"{s}\",\"keyword_count\":{d},\"duo_proofs\":[\"examples/pass12_m1_diff.duo\",\"examples/pass16_m1_lexer_proof.duo\"]}},\"source_cursor\":{{\"subsystem\":\"SH-01\",\"production_path\":\"src/lexer.zig → source_cursor.ProductionCursor\",\"duo_projection\":\"lib/std/compiler/source.duo\",\"differential_pass\":{},\"corpus_cases\":{d},\"indexing\":\"{s}\",\"duo_proofs\":[\"examples/pass16_source_cursor_proof.duo\"],\"host_note\":\"MP-03: canonical line/col substrate in production lexer\"}},\"lexer\":{{\"subsystem\":\"SH-03\",\"production_path\":\"src/lexer.zig → duo_lexer_bridge\",\"duo_projection\":\"lib/std/compiler/lexer.duo\",\"corpus_pass\":{},\"corpus_cases\":{d},\"duo_proofs\":[\"examples/pass16_lexer_corpus_proof.duo\",\"examples/pass16_lexer_embed_proof.duo\",\"examples/pass16_lexer_tokenize_proof.duo\"],\"host_note\":\"MP-04 partial: keyword leg Duo-native; tokenize host; MP4-B01 closed; MP4-B02 seam partial (duo_lexer_bridge.zig)\"}}}}",
        .{
            SCHEMA_VERSION,
            r.all_pass,
            duo_keyword_bridge.PRODUCTION_PATH,
            r.keywords.exhaustive_pass,
            r.keywords.fuzz_pass,
            r.keywords.production_classifier,
            @tagName(token_semantic.production_authority),
            r.keywords.keyword_count,
            r.source_cursor.differential_pass,
            r.source_cursor.corpus_cases,
            r.source_cursor.indexing,
            r.lexer.corpus_pass,
            r.lexer.corpus_cases,
        },
    );
}

test "selfhost_verify: production keyword path agrees" {
    const r = try verifyKeywordsOrFail();
    try std.testing.expect(r.exhaustive_pass);
    try std.testing.expect(r.fuzz_pass);
}

test "selfhost_verify: source cursor differential" {
    const r = try verifySourceCursorOrFail();
    try std.testing.expect(r.differential_pass);
    try std.testing.expect(r.corpus_cases >= 3);
}

test "selfhost_verify: combined gate" {
    const r = try verifyAllOrFail();
    try std.testing.expect(r.all_pass);
}

test "selfhost_verify: lexer corpus" {
    const r = try verifyLexerOrFail();
    try std.testing.expect(r.corpus_pass);
}
