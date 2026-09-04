//! Canonical token/keyword semantic source.
const std = @import("std");
const lexer = @import("lexer.zig");
const keyword_bridge = @import("keyword_bridge.zig");

pub const SCHEMA_VERSION = "token-semantic-v0";

pub const Category = enum {
    lua_keyword,
    type_descriptor,
    contextual,

    pub fn name(self: Category) []const u8 {
        return switch (self) {
            .lua_keyword => "lua_keyword",
            .type_descriptor => "type_descriptor",
            .contextual => "contextual",
        };
    }
};

pub const KeywordEntry = struct {
    text: []const u8,
    kind: lexer.TokenKind,
    category: Category,
    diagnostic: []const u8,
    formatter_role: []const u8 = "keyword",
    canonical: bool = true,
};

/// Canonical keyword table — one semantic fact per reserved word.
pub const keywords: []const KeywordEntry = &.{
    .{ .text = "and", .kind = .kw_and, .category = .lua_keyword, .diagnostic = "keyword 'and'" },
    .{ .text = "break", .kind = .kw_break, .category = .lua_keyword, .diagnostic = "keyword 'break'" },
    .{ .text = "continue", .kind = .kw_continue, .category = .lua_keyword, .diagnostic = "keyword 'continue'" },
    .{ .text = "do", .kind = .kw_do, .category = .lua_keyword, .diagnostic = "keyword 'do'" },
    .{ .text = "else", .kind = .kw_else, .category = .lua_keyword, .diagnostic = "keyword 'else'" },
    .{ .text = "elseif", .kind = .kw_elseif, .category = .lua_keyword, .diagnostic = "keyword 'elseif'" },
    .{ .text = "end", .kind = .kw_end, .category = .lua_keyword, .diagnostic = "keyword 'end'" },
    .{ .text = "false", .kind = .kw_false, .category = .lua_keyword, .diagnostic = "keyword 'false'" },
    .{ .text = "for", .kind = .kw_for, .category = .lua_keyword, .diagnostic = "keyword 'for'" },
    .{ .text = "function", .kind = .kw_function, .category = .lua_keyword, .diagnostic = "keyword 'function'" },
    .{ .text = "fun", .kind = .kw_fun, .category = .lua_keyword, .diagnostic = "keyword 'fun'" },
    .{ .text = "global", .kind = .kw_global, .category = .lua_keyword, .diagnostic = "keyword 'global'" },
    .{ .text = "goto", .kind = .kw_goto, .category = .lua_keyword, .diagnostic = "keyword 'goto'" },
    .{ .text = "if", .kind = .kw_if, .category = .lua_keyword, .diagnostic = "keyword 'if'" },
    .{ .text = "in", .kind = .kw_in, .category = .lua_keyword, .diagnostic = "keyword 'in'" },
    .{ .text = "local", .kind = .kw_local, .category = .lua_keyword, .diagnostic = "keyword 'local'" },
    .{ .text = "nil", .kind = .kw_nil, .category = .lua_keyword, .diagnostic = "keyword 'nil'" },
    .{ .text = "not", .kind = .kw_not, .category = .lua_keyword, .diagnostic = "keyword 'not'" },
    .{ .text = "or", .kind = .kw_or, .category = .lua_keyword, .diagnostic = "keyword 'or'" },
    .{ .text = "repeat", .kind = .kw_repeat, .category = .lua_keyword, .diagnostic = "keyword 'repeat'" },
    .{ .text = "return", .kind = .kw_return, .category = .lua_keyword, .diagnostic = "keyword 'return'" },
    .{ .text = "then", .kind = .kw_then, .category = .lua_keyword, .diagnostic = "keyword 'then'" },
    .{ .text = "true", .kind = .kw_true, .category = .lua_keyword, .diagnostic = "keyword 'true'" },
    .{ .text = "until", .kind = .kw_until, .category = .lua_keyword, .diagnostic = "keyword 'until'" },
    .{ .text = "while", .kind = .kw_while, .category = .lua_keyword, .diagnostic = "keyword 'while'" },
    .{ .text = "const", .kind = .kw_const, .category = .type_descriptor, .diagnostic = "keyword 'const'" },
    .{ .text = "enum", .kind = .kw_enum, .category = .type_descriptor, .diagnostic = "keyword 'enum'" },
    .{ .text = "i8", .kind = .kw_i8, .category = .type_descriptor, .diagnostic = "type 'i8'" },
    .{ .text = "i16", .kind = .kw_i16, .category = .type_descriptor, .diagnostic = "type 'i16'" },
    .{ .text = "i32", .kind = .kw_i32, .category = .type_descriptor, .diagnostic = "type 'i32'" },
    .{ .text = "i64", .kind = .kw_i64, .category = .type_descriptor, .diagnostic = "type 'i64'" },
    .{ .text = "u8", .kind = .kw_u8, .category = .type_descriptor, .diagnostic = "type 'u8'" },
    .{ .text = "u16", .kind = .kw_u16, .category = .type_descriptor, .diagnostic = "type 'u16'" },
    .{ .text = "u32", .kind = .kw_u32, .category = .type_descriptor, .diagnostic = "type 'u32'" },
    .{ .text = "u64", .kind = .kw_u64, .category = .type_descriptor, .diagnostic = "type 'u64'" },
    .{ .text = "f32", .kind = .kw_f32, .category = .type_descriptor, .diagnostic = "type 'f32'" },
    .{ .text = "f64", .kind = .kw_f64, .category = .type_descriptor, .diagnostic = "type 'f64'" },
    .{ .text = "bool", .kind = .kw_bool, .category = .type_descriptor, .diagnostic = "type 'bool'" },
    .{ .text = "void", .kind = .kw_void, .category = .type_descriptor, .diagnostic = "type 'void'" },
    .{ .text = "str", .kind = .kw_str, .category = .type_descriptor, .diagnostic = "type 'str'" },
    .{ .text = "match", .kind = .kw_match, .category = .contextual, .diagnostic = "keyword 'match'" },
    .{ .text = "try", .kind = .kw_try, .category = .contextual, .diagnostic = "keyword 'try'" },
    .{ .text = "catch", .kind = .kw_catch, .category = .contextual, .diagnostic = "keyword 'catch'" },
    .{ .text = "defer", .kind = .kw_defer, .category = .contextual, .diagnostic = "keyword 'defer'" },
    .{ .text = "async", .kind = .kw_async, .category = .contextual, .diagnostic = "keyword 'async'" },
    .{ .text = "await", .kind = .kw_await, .category = .contextual, .diagnostic = "keyword 'await'" },
    .{ .text = "concept", .kind = .kw_concept, .category = .contextual, .diagnostic = "keyword 'concept'" },
    .{ .text = "alias", .kind = .kw_alias, .category = .contextual, .diagnostic = "keyword 'alias'" },
    .{ .text = "private", .kind = .kw_private, .category = .contextual, .diagnostic = "keyword 'private'" },
    .{ .text = "extends", .kind = .kw_extends, .category = .contextual, .diagnostic = "keyword 'extends'" },
    .{ .text = "macro", .kind = .kw_macro, .category = .contextual, .diagnostic = "keyword 'macro'" },
    .{ .text = "comptime", .kind = .kw_comptime, .category = .contextual, .diagnostic = "keyword 'comptime'" },
    .{ .text = "by", .kind = .kw_by, .category = .contextual, .diagnostic = "keyword 'by'" },
    .{ .text = "let", .kind = .kw_let, .category = .contextual, .diagnostic = "keyword 'let'" },
};

pub const ClassifierId = enum {
    branch_chain,
    sorted_lookup,
    length_bucket,

    pub fn name(self: ClassifierId) []const u8 {
        return switch (self) {
            .branch_chain => "classifier.branch_chain",
            .sorted_lookup => "classifier.sorted_lookup",
            .length_bucket => "classifier.length_bucket",
        };
    }
};

/// Production classifier — branch chain (smallest code; differential-equivalent peers).
pub const production_classifier: ClassifierId = .branch_chain;

/// Production authority: Duo classify projection (P16-WS3 M1 integration).
pub const production_authority: enum { bridge_classify, host_branch_chain } = .bridge_classify;

pub const legal_classifiers = [_]ClassifierId{ .branch_chain, .sorted_lookup, .length_bucket };
const bench_negatives = [_][]const u8{ "foo", "bar", "identifier", "notkw", "Function", "asyncio", "matchx" };
const fuzz_seed: u64 = 0xC12A1F00D;
pub const differential_fuzz_seed = fuzz_seed;

pub fn lookupKeywordBranchChain(text: []const u8) ?lexer.TokenKind {
    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw.text)) return kw.kind;
    }
    return null;
}

pub fn lookupKeywordLengthBucket(text: []const u8) ?lexer.TokenKind {
    const len = text.len;
    for (keywords) |kw| {
        if (kw.text.len == len and std.mem.eql(u8, text, kw.text)) return kw.kind;
    }
    return null;
}

pub fn lookupKeywordSorted(text: []const u8) ?lexer.TokenKind {
    const sorted = sortedKeywordIndices();
    var lo: usize = 0;
    var hi: usize = sorted.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const kw = keywords[sorted[mid]];
        const ord = std.mem.order(u8, text, kw.text);
        if (ord == .eq) return kw.kind;
        if (ord == .lt) hi = mid else lo = mid + 1;
    }
    return null;
}

pub fn classifyWith(id: ClassifierId, text: []const u8) ?lexer.TokenKind {
    return switch (id) {
        .branch_chain => lookupKeywordBranchChain(text),
        .sorted_lookup => lookupKeywordSorted(text),
        .length_bucket => lookupKeywordLengthBucket(text),
    };
}

/// Production entry — Duo-native classify (host branch_chain retained as differential oracle).
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return switch (production_authority) {
        .bridge_classify => keyword_bridge.lookupKeyword(text),
        .host_branch_chain => classifyWith(production_classifier, text),
    };
}

/// Host differential oracle — branch chain only (must match Duo production path).
pub fn lookupKeywordOracle(text: []const u8) ?lexer.TokenKind {
    return classifyWith(production_classifier, text);
}

var sorted_indices: [keywords.len]usize = undefined;
var sorted_built = false;

fn buildSortedIndices() void {
    for (0..keywords.len) |i| sorted_indices[i] = i;
    var i: usize = 1;
    while (i < keywords.len) : (i += 1) {
        const key = sorted_indices[i];
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, keywords[key].text, keywords[sorted_indices[j - 1]].text)) {
            sorted_indices[j] = sorted_indices[j - 1];
            j -= 1;
        }
        sorted_indices[j] = key;
    }
    sorted_built = true;
}

fn sortedKeywordIndices() []const usize {
    if (!sorted_built) buildSortedIndices();
    return &sorted_indices;
}

pub fn entryForKind(kind: lexer.TokenKind) ?KeywordEntry {
    for (keywords) |kw| {
        if (kw.kind == kind) return kw;
    }
    return null;
}

pub fn differentialValidateClassifiers() !void {
    for (keywords) |kw| {
        const ref = lookupKeywordBranchChain(kw.text) orelse return error.ClassifierMismatch;
        const prod = lookupKeyword(kw.text) orelse return error.ClassifierMismatch;
        if (prod != ref) return error.ClassifierMismatch;
        for (legal_classifiers) |cid| {
            const got = classifyWith(cid, kw.text) orelse return error.ClassifierMismatch;
            if (got != ref) return error.ClassifierMismatch;
        }
    }
    for (bench_negatives) |neg| {
        for (legal_classifiers) |cid| {
            if (classifyWith(cid, neg) != null) return error.FalsePositive;
        }
    }
}

pub fn differentialCheck(seed: u64) bool {
    differentialValidateClassifiers() catch return false;
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var buf: [32]u8 = undefined;
    var i: u32 = 0;
    while (i < 512) : (i += 1) {
        const len = random.intRangeAtMost(usize, 0, buf.len);
        random.bytes(buf[0..len]);
        const slice = buf[0..len];
        const ref = lookupKeywordBranchChain(slice);
        const prod = lookupKeyword(slice);
        if (prod != ref) return false;
        for (legal_classifiers) |cid| {
            if (classifyWith(cid, slice) != ref) return false;
        }
    }
    return true;
}

pub fn spellingForKind(kind: lexer.TokenKind) ?[]const u8 {
    if (entryForKind(kind)) |entry| return entry.text;
    return null;
}

test "token_semantic: exhaustive keyword lookup" {
    for (keywords) |kw| {
        try std.testing.expectEqual(kw.kind, lookupKeyword(kw.text));
    }
}

test "token_semantic: negative classification" {
    try std.testing.expect(lookupKeyword("foobar") == null);
    try std.testing.expect(lookupKeyword("Function") == null);
    try std.testing.expect(lookupKeyword("") == null);
}

test "token_semantic: all legal classifiers agree" {
    try differentialValidateClassifiers();
    try std.testing.expect(differentialCheck(fuzz_seed));
}
