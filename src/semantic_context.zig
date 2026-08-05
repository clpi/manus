//! Pass 12 Goal D / Audit 6 — bounded semantic context packages for agents.
//!
//! Reproducible from stable IDs; not a second semantic graph.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");

pub const SCHEMA_VERSION = "semantic-context-v0";

pub const ContextPackage = struct {
    package_id: []const u8,
    task: []const u8,
    target_entities: []const []const u8,
    canonical_owners: []const []const u8,
    governing_contracts: []const []const u8,
    active_assumptions: []const []const u8,
    affected_tests: []const []const u8,
    public_claims: []const []const u8,
    accepted_operations: []const []const u8,
};

/// Bounded context for M1 keyword classifier work (P12-M1).
pub const m1_keyword_classifier: ContextPackage = .{
    .package_id = "ctx.m1.keyword_classifier",
    .task = "Inspect or modify duo:lexer:keyword_classifier without full compiler tree",
    .target_entities = &.{
        "duo:lexer:keyword_classifier",
        "token_semantic.keywords",
    },
    .canonical_owners = &.{
        "src/token_semantic.zig",
        "src/lexer.zig",
        "src/realization.zig",
    },
    .governing_contracts = &.{
        "token_semantic.intent",
        "token_semantic.proof_obligations",
    },
    .active_assumptions = &.{
        "production_classifier=classifier.branch_chain",
        "cost_model=static_estimate",
    },
    .affected_tests = &.{
        "token_semantic: exhaustive keyword lookup",
        "token_semantic: all legal classifiers agree",
        "token_semantic: compareKeywordClassifiers",
        "lex: standard keywords",
    },
    .public_claims = &.{
        "claim.m1_keyword_semantic",
    },
    .accepted_operations = &.{
        "semantic.intent",
        "candidate.compare",
        "candidate.list",
        "proof.obligations",
        "proof.bundle",
        "semantic.projections",
    },
};

pub fn packageForEntity(entity_id: []const u8) ?ContextPackage {
    if (std.mem.eql(u8, entity_id, token_semantic.intent.subject_entity) or
        std.mem.startsWith(u8, entity_id, "token_semantic."))
    {
        return m1_keyword_classifier;
    }
    return null;
}

fn writeStringArray(w: *std.Io.Writer, items: []const []const u8) !void {
    try w.print("[", .{});
    for (items, 0..) |s, i| {
        if (i > 0) try w.print(",", .{});
        try jsonEscape(w, s);
    }
    try w.print("]", .{});
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    try w.print("\"", .{});
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
    try w.print("\"", .{});
}

pub fn writePackageJson(w: *std.Io.Writer, pkg: ContextPackage) !void {
    try w.print("{{\"schema\":\"{s}\",\"package_id\":\"{s}\",\"task\":", .{ SCHEMA_VERSION, pkg.package_id });
    try jsonEscape(w, pkg.task);
    try w.print(",\"target_entities\":", .{});
    try writeStringArray(w, pkg.target_entities);
    try w.print(",\"canonical_owners\":", .{});
    try writeStringArray(w, pkg.canonical_owners);
    try w.print(",\"governing_contracts\":", .{});
    try writeStringArray(w, pkg.governing_contracts);
    try w.print(",\"active_assumptions\":", .{});
    try writeStringArray(w, pkg.active_assumptions);
    try w.print(",\"affected_tests\":", .{});
    try writeStringArray(w, pkg.affected_tests);
    try w.print(",\"public_claims\":", .{});
    try writeStringArray(w, pkg.public_claims);
    try w.print(",\"accepted_operations\":", .{});
    try writeStringArray(w, pkg.accepted_operations);
    try w.print("}}", .{});
}

test "semantic_context: m1 package references canonical owner" {
    try std.testing.expect(std.mem.eql(u8, m1_keyword_classifier.canonical_owners[0], "src/token_semantic.zig"));
}

test "semantic_context: writePackageJson" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePackageJson(&buf.writer, m1_keyword_classifier);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "ctx.m1.keyword_classifier") != null);
}
