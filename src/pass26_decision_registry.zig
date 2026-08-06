//! Pass 26 §20 — machine-readable decision / contradiction registry.
//!
//! Extends Pass 6 rejected_ideas.md. Every agent queries before proposing syntax.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-decision-registry-v0";
pub const PASS6_REJECTED_PATH = "docs/catalogs/rejected_ideas.md";

pub const DecisionStatus = enum {
    proposed,
    under_grammar_audit,
    accepted,
    implemented,
    experimental,
    deferred,
    rejected,
    superseded,

    pub fn name(self: DecisionStatus) []const u8 {
        return @tagName(self);
    }
};

pub const DecisionCategory = enum {
    syntax,
    semantics,
    protocol,
    identity,
    boundary,
    tooling,
    foreign,
    concurrency,
    metaprogramming,

    pub fn name(self: DecisionCategory) []const u8 {
        return @tagName(self);
    }
};

pub const DecisionRecord = struct {
    id: []const u8,
    topic: []const u8,
    status: DecisionStatus,
    category: DecisionCategory,
    tension: []const u8,
    resolution: []const u8,
    /// Preferred alternative or canonical rule when resolved.
    canonical_rule: ?[]const u8 = null,
    /// Cross-pass reference (e.g. P23-D01, P25-S11, REJ-007).
    related: ?[]const u8 = null,
};

/// Open architectural tensions — query before proposing (Pass 26 §20 seed).
pub const contradictions: []const DecisionRecord = &.{
    .{
        .id = "P26-D01",
        .topic = "Call syntax: parentheses vs whitespace application",
        .status = .under_grammar_audit,
        .category = .syntax,
        .tension = "Pass 24 parenless calls vs traditional f(x) both accepted",
        .resolution = "bare a ≠ a(); both forms coexist with distinct semantics",
        .canonical_rule = "Pass 24 call model",
        .related = "P24-WS01",
    },
    .{
        .id = "P26-D02",
        .topic = "Descriptor field syntax : versus assignment",
        .status = .under_grammar_audit,
        .category = .syntax,
        .tension = "@{ x: f64 } vs @{ x = f64 }",
        .resolution = "pending grammar audit; frozen @{} uses colon form today",
        .canonical_rule = null,
        .related = "P25-WS1",
    },
    .{
        .id = "P26-D03",
        .topic = "Top-level directives vs contract descriptors",
        .status = .deferred,
        .category = .semantics,
        .tension = "@ directives at module scope vs descriptor-valued contracts",
        .resolution = "directives participate in stage model; not universal escape",
        .canonical_rule = "Pass 26 §8 stage transitions",
        .related = "REJ-008",
    },
    .{
        .id = "P26-D04",
        .topic = "Methods on descriptors vs namespace pollution",
        .status = .accepted,
        .category = .protocol,
        .tension = "Point.format vs protocol attachment",
        .resolution = "protocol attachment via graph; not magical .protocols field",
        .canonical_rule = "Pass 26 §4",
        .related = "P26-PA-R01",
    },
    .{
        .id = "P26-D05",
        .topic = "Dynamic descriptors vs compile-time assumptions",
        .status = .under_grammar_audit,
        .category = .semantics,
        .tension = "runtime descriptor values vs mono specialization",
        .resolution = "stage polymorphism + residualize; dynamic deopt boundary",
        .canonical_rule = "Pass 26 §8 + Boundary P26-B01",
        .related = "P25-WS2",
    },
    .{
        .id = "P26-D06",
        .topic = "Canonical function syntax variants",
        .status = .under_grammar_audit,
        .category = .syntax,
        .tension = "multiple func decl surface forms in corpus",
        .resolution = "decision registry gates new variants",
        .canonical_rule = null,
        .related = null,
    },
    .{
        .id = "P26-D07",
        .topic = "Lua syntax deprecated vs permanently accepted",
        .status = .accepted,
        .category = .syntax,
        .tension = "Lua superset permanence",
        .resolution = "Lua 5.x superset permanently accepted; Pass 24 constitution",
        .canonical_rule = "Pass 24 Lua superset",
        .related = "P24-WS02",
    },
    .{
        .id = "P26-D08",
        .topic = "Tail-demand inference scope",
        .status = .implemented,
        .category = .semantics,
        .tension = "how far result demand propagates past tail region",
        .resolution = "Rules A–H in tail_result_demand.zig; no backward local search",
        .canonical_rule = "Pass 25 §5.1",
        .related = "P23-D01 superseded",
    },
    .{
        .id = "P26-D09",
        .topic = "Privileged operations by spelling",
        .status = .rejected,
        .category = .semantics,
        .tension = "user:set / descriptor:with / value:take",
        .resolution = "Semantic.* operation registry",
        .canonical_rule = "Pass 26 §3",
        .related = "P26-OP-R01",
    },
    .{
        .id = "P26-D10",
        .topic = "LLVM IR as interchange",
        .status = .rejected,
        .category = .foreign,
        .tension = "IR layer vs direct native",
        .resolution = "C/asm/object + SIM; see REJ-001",
        .canonical_rule = "REJ-001",
        .related = "REJ-001",
    },
    .{
        .id = "P26-D11",
        .topic = "Table literal key forms",
        .status = .accepted,
        .category = .syntax,
        .tension = "identifier keys vs computed keys vs new operator",
        .resolution = "Lua-compatible bracket form for computed keys only; no alternate computed-key operator",
        .canonical_rule = "name = value is literal field name; [expr] = value evaluates expr as key; formatter preserves brackets when semantically necessary",
        .related = "GR-004, GR-006",
    },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-DR01", .rule = "agents query decision registry before proposing syntax" },
    .{ .id = "P26-DR02", .rule = "status transitions recorded; superseded links to replacement" },
    .{ .id = "P26-DR03", .rule = "extends Pass 6 REJ-*; does not duplicate without cross-ref" },
    .{ .id = "P26-DR04", .rule = "machine-readable via duo catalog pass26.decisions" },
};

pub fn findDecision(id: []const u8) ?DecisionRecord {
    for (contradictions) |d| {
        if (std.mem.eql(u8, d.id, id)) return d;
    }
    return null;
}

pub fn decisionsWithStatus(status: DecisionStatus) usize {
    var n: usize = 0;
    for (contradictions) |d| {
        if (d.status == status) n += 1;
    }
    return n;
}

test "pass26_decision_registry: contradictions + statuses" {
    try std.testing.expect(contradictions.len >= 11);
    try std.testing.expect(findDecision("P26-D09") != null);
    try std.testing.expect(findDecision("P26-D09").?.status == .rejected);
    try std.testing.expect(findDecision("P26-D08").?.status == .implemented);
    try std.testing.expect(findDecision("P26-D11") != null);
    try std.testing.expect(findDecision("P26-D11").?.status == .accepted);
    try std.testing.expect(decisionsWithStatus(.under_grammar_audit) >= 3);
}
