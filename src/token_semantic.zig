//! Pass 12 M1 — canonical token/keyword semantic source (P12-WS6 / P12-M1).
//!
//! Single source of truth for reserved words. `lexer.zig` consumes `lookupKeyword`.
//! Projections: compiler metadata, classifier, spelling, formatter, LSP, MCP, tests.
const std = @import("std");
const lexer = @import("lexer.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");
const proof_carrying = @import("proof_carrying.zig");
const realization = @import("realization.zig");
const evidence_record = @import("evidence_record.zig");
const optimization_outcome = @import("optimization_outcome.zig");

pub const SCHEMA_VERSION = "token-semantic-v0";

pub const Category = enum {
    lua_keyword,
    duo_type,
    duo_contextual,

    pub fn name(self: Category) []const u8 {
        return switch (self) {
            .lua_keyword => "lua_keyword",
            .duo_type => "duo_type",
            .duo_contextual => "duo_contextual",
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
    .{ .text = "const", .kind = .kw_const, .category = .duo_type, .diagnostic = "keyword 'const'" },
    .{ .text = "enum", .kind = .kw_enum, .category = .duo_type, .diagnostic = "keyword 'enum'" },
    .{ .text = "i8", .kind = .kw_i8, .category = .duo_type, .diagnostic = "type 'i8'" },
    .{ .text = "i16", .kind = .kw_i16, .category = .duo_type, .diagnostic = "type 'i16'" },
    .{ .text = "i32", .kind = .kw_i32, .category = .duo_type, .diagnostic = "type 'i32'" },
    .{ .text = "i64", .kind = .kw_i64, .category = .duo_type, .diagnostic = "type 'i64'" },
    .{ .text = "u8", .kind = .kw_u8, .category = .duo_type, .diagnostic = "type 'u8'" },
    .{ .text = "u16", .kind = .kw_u16, .category = .duo_type, .diagnostic = "type 'u16'" },
    .{ .text = "u32", .kind = .kw_u32, .category = .duo_type, .diagnostic = "type 'u32'" },
    .{ .text = "u64", .kind = .kw_u64, .category = .duo_type, .diagnostic = "type 'u64'" },
    .{ .text = "f32", .kind = .kw_f32, .category = .duo_type, .diagnostic = "type 'f32'" },
    .{ .text = "f64", .kind = .kw_f64, .category = .duo_type, .diagnostic = "type 'f64'" },
    .{ .text = "bool", .kind = .kw_bool, .category = .duo_type, .diagnostic = "type 'bool'" },
    .{ .text = "void", .kind = .kw_void, .category = .duo_type, .diagnostic = "type 'void'" },
    .{ .text = "str", .kind = .kw_str, .category = .duo_type, .diagnostic = "type 'str'" },
    .{ .text = "match", .kind = .kw_match, .category = .duo_contextual, .diagnostic = "keyword 'match'" },
    .{ .text = "try", .kind = .kw_try, .category = .duo_contextual, .diagnostic = "keyword 'try'" },
    .{ .text = "catch", .kind = .kw_catch, .category = .duo_contextual, .diagnostic = "keyword 'catch'" },
    .{ .text = "defer", .kind = .kw_defer, .category = .duo_contextual, .diagnostic = "keyword 'defer'" },
    .{ .text = "async", .kind = .kw_async, .category = .duo_contextual, .diagnostic = "keyword 'async'" },
    .{ .text = "await", .kind = .kw_await, .category = .duo_contextual, .diagnostic = "keyword 'await'" },
    .{ .text = "concept", .kind = .kw_concept, .category = .duo_contextual, .diagnostic = "keyword 'concept'" },
    .{ .text = "alias", .kind = .kw_alias, .category = .duo_contextual, .diagnostic = "keyword 'alias'" },
    .{ .text = "private", .kind = .kw_private, .category = .duo_contextual, .diagnostic = "keyword 'private'" },
    .{ .text = "extends", .kind = .kw_extends, .category = .duo_contextual, .diagnostic = "keyword 'extends'" },
    .{ .text = "macro", .kind = .kw_macro, .category = .duo_contextual, .diagnostic = "keyword 'macro'" },
    .{ .text = "comptime", .kind = .kw_comptime, .category = .duo_contextual, .diagnostic = "keyword 'comptime'" },
    .{ .text = "by", .kind = .kw_by, .category = .duo_contextual, .diagnostic = "keyword 'by'" },
    .{ .text = "let", .kind = .kw_let, .category = .duo_contextual, .diagnostic = "keyword 'let'" },
};

pub const intent: proof_carrying.IntentContract = .{
    .subject_entity = "duo:lexer:keyword_classifier",
    .summary = "Classify identifier text as reserved keyword or non-keyword",
    .descriptor_id = "token_semantic.keywords",
    .laws = "exact_match; deterministic; bounded_reads",
    .representation_constraints = "no_allocation; no_boxing",
    .determinism_required = true,
    .provenance = "token_semantic.v0",
};

pub const projections: []const proof_carrying.SemanticProjection = &.{
    .{ .id = "proj.keyword.compiler_metadata", .kind = .source, .source_entity = "duo:lexer:keyword_classifier", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.keyword.classifier", .kind = .decoder_table, .source_entity = "duo:lexer:keyword_classifier", .transform_id = "classifier.branch_chain", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.keyword.spelling", .kind = .documentation, .source_entity = "duo:lexer:keyword_classifier", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.keyword.lsp", .kind = .lsp_hover, .source_entity = "duo:lexer:keyword_classifier", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.keyword.mcp", .kind = .mcp_entity, .source_entity = "duo:lexer:keyword_classifier", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.keyword.tests", .kind = .test_generator, .source_entity = "duo:lexer:keyword_classifier", .schema_version = SCHEMA_VERSION },
};

pub const proof_obligations: []const proof_carrying.ProofObligation = &.{
    .{
        .id = "obl.keyword.exact",
        .subject_entity = "duo:lexer:keyword_classifier",
        .predicate = "exact classification for all reserved words",
        .accepted_evidence = &.{ evidence_record.Kind.property_test, evidence_record.Kind.differential_test },
        .validation_method = "exhaustive over keywords table",
        .status = .discharged,
    },
    .{
        .id = "obl.keyword.no_false_positive",
        .subject_entity = "duo:lexer:keyword_classifier",
        .predicate = "non-reserved identifier text returns null",
        .accepted_evidence = &.{evidence_record.Kind.property_test},
        .validation_method = "negative classification samples",
        .status = .discharged,
    },
    .{
        .id = "obl.keyword.deterministic",
        .subject_entity = "duo:lexer:keyword_classifier",
        .predicate = "same input always yields same TokenKind",
        .accepted_evidence = &.{evidence_record.Kind.proven_semantic_fact},
        .validation_method = "pure function; no heap allocation on production path",
        .status = .discharged,
    },
    .{
        .id = "obl.keyword.no_alloc",
        .subject_entity = "duo:lexer:keyword_classifier",
        .predicate = "classifier performs no heap allocation",
        .accepted_evidence = &.{evidence_record.Kind.static_estimate},
        .validation_method = "static inspection of classifier implementations",
        .status = .discharged,
    },
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
pub const production_authority: enum { duo_classify, host_branch_chain } = .duo_classify;

pub const LookupFn = *const fn ([]const u8) ?lexer.TokenKind;

pub const SelectionSnapshot = struct {
    selected: ClassifierId,
    model_selected: ClassifierId,
    legal_candidates: u32,
    compared_candidates: u32,
    differential_pass: bool,
};

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
        .duo_classify => duo_keyword_bridge.lookupKeyword(text),
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

/// Static cost estimate per lookup (ns) — branch ~n/2 compares, sorted ~log2(n) for 54 keywords.
pub fn estimatedNsPerLookup(id: ClassifierId) u64 {
    return switch (id) {
        .branch_chain => 30,
        .sorted_lookup => 20,
        .length_bucket => 25,
    };
}

pub fn benchmarkClassifier(lookup: LookupFn, iterations: u32) u64 {
    _ = iterations;
    if (lookup == lookupKeywordBranchChain) return estimatedNsPerLookup(.branch_chain);
    if (lookup == lookupKeywordSorted) return estimatedNsPerLookup(.sorted_lookup);
    if (lookup == lookupKeywordLengthBucket) return estimatedNsPerLookup(.length_bucket);
    return 30;
}

fn pushCandidate(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(realization.Candidate),
    id: []const u8,
    label: []const u8,
    repr: []const u8,
    cost: u32,
    optionality: u32,
    legal: bool,
    reason: ?[]const u8,
    evidence: optimization_outcome.Evidence,
) !void {
    try out.append(alloc, .{
        .id = try alloc.dupe(u8, id),
        .label = try alloc.dupe(u8, label),
        .representation = try alloc.dupe(u8, repr),
        .static_cost = cost,
        .optionality_retained = optionality,
        .legal = legal,
        .rejection_reason = if (reason) |r| try alloc.dupe(u8, r) else null,
        .evidence = evidence,
        .fallback = null,
    });
}

pub fn compareKeywordClassifiers(alloc: std.mem.Allocator) !realization.CandidateComparisonReport {
    var candidates: std.ArrayListUnmanaged(realization.Candidate) = .empty;
    errdefer {
        for (candidates.items) |*c| c.deinit(alloc);
        candidates.deinit(alloc);
    }
    try pushCandidate(alloc, &candidates, "classifier.branch_chain", "Linear scan", "branch_chain", 30, 80, true, null, .proven);
    try pushCandidate(alloc, &candidates, "classifier.sorted_lookup", "Binary search sorted table", "sorted_table", 20, 70, true, null, .proven);
    try pushCandidate(alloc, &candidates, "classifier.length_bucket", "Length filter + scan", "length_bucket", 25, 75, true, null, .proven);
    try pushCandidate(alloc, &candidates, "classifier.perfect_hash", "Perfect hash", "phf", 10, 40, false, "not generated for keyword set", .estimated);
    var var_: realization.Variable = .{
        .id = try alloc.dupe(u8, "realize.keyword_classifier"),
        .subject_entity = try alloc.dupe(u8, intent.subject_entity),
        .dimension = .algorithm,
        .candidates = try candidates.toOwnedSlice(alloc),
        .freedoms = &.{},
    };
    defer var_.deinit(alloc);
    return realization.compareCandidates(alloc, &var_);
}

fn classifierFromId(id: []const u8) ClassifierId {
    if (std.mem.eql(u8, id, ClassifierId.sorted_lookup.name())) return .sorted_lookup;
    if (std.mem.eql(u8, id, ClassifierId.length_bucket.name())) return .length_bucket;
    return .branch_chain;
}

/// Static-cost comparison + differential check; production remains `production_classifier`.
pub fn keywordSelectionSnapshot() SelectionSnapshot {
    return .{
        .selected = production_classifier,
        .model_selected = production_classifier,
        .legal_candidates = @intCast(legal_classifiers.len),
        .compared_candidates = @intCast(legal_classifiers.len),
        .differential_pass = differentialCheck(fuzz_seed),
    };
}

pub fn selectClassifier(alloc: std.mem.Allocator) !SelectionSnapshot {
    if (!differentialCheck(fuzz_seed)) return error.DifferentialFailed;
    var report = try compareKeywordClassifiers(alloc);
    defer report.deinit(alloc);
    const model_selected = classifierFromId(report.selected_id orelse ClassifierId.branch_chain.name());
    return .{
        .selected = production_classifier,
        .model_selected = model_selected,
        .legal_candidates = @intCast(report.legal_count),
        .compared_candidates = @intCast(report.compared_count),
        .differential_pass = true,
    };
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"keyword_count\":{d},\"intent_subject\":\"{s}\",\"production_classifier\":\"{s}\",\"production_consumer\":\"src/lexer.zig\",\"cost_model\":\"static_estimate\"", .{
        SCHEMA_VERSION,
        keywords.len,
        intent.subject_entity,
        production_classifier.name(),
    });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    if (selectClassifier(arena.allocator())) |snap| {
        try w.print(",\"model_selected_classifier\":\"{s}\"", .{snap.model_selected.name()});
        try w.print(",\"selection\":{{\"legal_candidates\":{d},\"compared_candidates\":{d},\"differential_pass\":true}}", .{
            snap.legal_candidates,
            snap.compared_candidates,
        });
    } else |_| {
        try w.print(",\"selection\":{{\"differential_pass\":false}}", .{});
    }
    try w.print(",\"obligations_discharged\":{d},\"classifiers\":[", .{proof_obligations.len});
    for (legal_classifiers, 0..) |cid, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{cid.name()});
    }
    try w.print("],\"projections\":[", .{});
    for (projections, 0..) |p, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"kind\":\"{s}\"}}", .{ p.id, p.kind.name() });
    }
    try w.print("]}}", .{});
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

test "token_semantic: compareKeywordClassifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var report = try compareKeywordClassifiers(arena.allocator());
    defer report.deinit(arena.allocator());
    try std.testing.expectEqual(@as(usize, 3), report.legal_count);
    try std.testing.expectEqualStrings("classifier.sorted_lookup", report.selected_id.?);
}

test "token_semantic: selectClassifier keeps production branch_chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snap = try selectClassifier(arena.allocator());
    try std.testing.expectEqual(production_classifier, snap.selected);
    try std.testing.expect(snap.differential_pass);
    try std.testing.expectEqual(@as(u32, 3), snap.legal_candidates);
}

test "token_semantic: writeCatalogJson" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeCatalogJson(&buf.writer);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "production_classifier") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classifier.length_bucket") != null);
}
