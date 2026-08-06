//! Pass 26 — transformation composition + meta-circular dependency control.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-transform-meta-v0";

pub const TransformFact = enum {
    specialization_key,
    layout_proof,
    effect_summary,
    representation_choice,
    inline_candidate,
    vectorization_candidate,

    pub fn name(self: TransformFact) []const u8 {
        return @tagName(self);
    }
};

pub const TransformCompositionRule = struct {
    id: []const u8,
    first: []const u8,
    second: []const u8,
    commutes: bool,
    note: []const u8,
};

pub const composition_rules: []const TransformCompositionRule = &.{
    .{ .id = "P26-TC01", .first = "specialize", .second = "inline_op", .commutes = false, .note = "order affects residual shape" },
    .{ .id = "P26-TC02", .first = "inline_op", .second = "vectorize", .commutes = false, .note = "vectorize prefers outlined loops" },
};

pub const TransformDeclaration = struct {
    name: []const u8,
    required_facts: []const TransformFact,
    produced_facts: []const TransformFact,
    invalidated_facts: []const TransformFact,
    preserves_identity: bool,
    budget_class: []const u8,
};

pub const MetaCyclePolicy = enum {
    dependency_track,
    cycle_detect,
    stratify,
    fixed_point_eval,
    monotonicity_check,
    iteration_budget,
    convergence_diagnostic,

    pub fn name(self: MetaCyclePolicy) []const u8 {
        return @tagName(self);
    }
};

pub const meta_invariants: []const struct { id: []const u8, rule: []const u8 } = &.{
    .{ .id = "P26-MM01", .rule = "transformations declare required/produced/invalidated facts" },
    .{ .id = "P26-MM02", .rule = "composition commutation explicit where relevant" },
    .{ .id = "P26-MM03", .rule = "meta-circular queries have budgets and cycle detection" },
    .{ .id = "P26-MM04", .rule = "reflection→transform→descriptor cycles stratified" },
};

test "pass26_transform_meta: composition + meta-circular policies" {
    try std.testing.expect(composition_rules.len >= 2);
    try std.testing.expect(meta_invariants.len >= 4);
}
