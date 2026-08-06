//! Pass 25 §5.1 — tail-demand propagation / result lineage (design authority).
//!
//! NOT "search backward for last variable whose type fits."
//! IS: explicit result demand + tail region + unique proven value lineage + control-flow proof.
const std = @import("std");

pub const SCHEMA_VERSION = "pass25-tail-result-model-v0";
pub const PLAN_PATH = "docs/plans/pass25_tail_result_demand.md";

/// Principal semantic return pack demand from explicit descriptor or inferred contract.
pub const ResultDemand = struct {
    /// Number of return positions demanded (`:void` → 0, `:i64` → 1, `:i64, Error` → 2).
    position_count: u8,
    /// Explicit `: Ret` descriptor written on the function (highest authority).
    explicit_descriptor: bool = false,
    /// Inferred latent tail result when no descriptor (conservative policy).
    latent_inferred: bool = false,
    /// Exported / address-taken / reflective → stable principal pack required.
    stable_principal_required: bool = false,
};

/// Value-producing forms that always have a semantic result (Pass 25 §5.1 §1).
pub const ValueProductionKind = enum {
    assign,
    compound_assign,
    field_assign,
    call,
    multi_assign,

    pub fn name(self: ValueProductionKind) []const u8 {
        return @tagName(self);
    }
};

/// Tail region being analyzed under result demand.
pub const TailRegionKind = enum {
    tail_statement,
    tail_branch,
    tail_loop,
    transparent_trailer_chain,

    pub fn name(self: TailRegionKind) []const u8 {
        return @tagName(self);
    }
};

/// How a tail region may satisfy result demand (Pass 25 §5.1 rules A–H).
pub const TailResultRule = enum {
    /// Rule A — tail assignment yields assigned value.
    tail_assignment,
    /// Rule B — tail compound assignment yields updated value.
    tail_compound_assignment,
    /// Rule C — tail call forwards return pack.
    tail_call,
    /// Rule D — tail branch yields SSA phi of compatible branch tails.
    tail_branch,
    /// Rule E — tail if with unique carried assignment merges to phi.
    tail_branch_carried,
    /// Rule F — tail loop with unique loop-carried assignment (factorial).
    tail_loop_carried,
    /// Rule G — multiple loop-carried chains for multi-position demand.
    tail_loop_multi_carried,
    /// Rule H — unconsumed tail call: effects preserved, values discarded per demand.
    tail_call_discard,

    pub fn name(self: TailResultRule) []const u8 {
        return @tagName(self);
    }
};

/// Statement may trail after result production without stealing tail (zero-result transparent).
pub const TransparentStatementKind = enum {
    debug_trace,
    assert_check,
    log_side_effect,
};

pub const ResultLineageNode = struct {
    id: u64,
    /// SSA-style name stable id in semantic graph.
    binding_stable_id: ?u64 = null,
    /// phi merge of prior nodes (loop/branch).
    phi_inputs: []const u64 = &.{},
    rule: TailResultRule,
    demand_index: u8 = 0,
    production: ValueProductionKind = .assign,
    region: TailRegionKind = .tail_statement,
};

/// Ambiguity reported when multiple lineages satisfy demand (never silent resolution).
pub const AmbiguityCandidate = struct {
    binding_name: []const u8,
    type_label: []const u8,
    stable_id: ?u64 = null,
};

pub const AmbiguityReport = struct {
    demand_position_count: u8,
    message: []const u8 = "tail region does not determine one result",
    candidates: []const AmbiguityCandidate = &.{},
};

/// Principal semantic pack vs call-site specialization (meaning vs representation).
pub const PrincipalReturnPack = struct {
    position_count: u8,
    /// Stable across exports/reflection when set.
    frozen: bool = false,
};

/// Discriminate effects, value, storage, consumption, liveness (§9).
pub const OperationAxis = enum {
    operation_effects,
    semantic_value,
    storage_effect,
    value_consumption,
    binding_liveness,

    pub fn name(self: OperationAxis) []const u8 {
        return @tagName(self);
    }
};

/// Call-site specialization axis (does not redefine semantic function meaning).
pub const CallReturnSpecialization = enum {
    full_pack,
    partial_consumed,
    discard_all,
    effect_only,

    pub fn name(self: CallReturnSpecialization) []const u8 {
        return @tagName(self);
    }
};

pub const RejectedHeuristic = struct {
    id: []const u8,
    pattern: []const u8,
    reason: []const u8,
};

/// Patterns explicitly rejected (Pass 25 §5.1 "What not to do").
pub const rejected_heuristics: []const RejectedHeuristic = &.{
    .{ .id = "P25-T01", .pattern = "last compatible local backward search", .reason = "fragile; use tail-demand graph only" },
    .{ .id = "P25-T02", .pattern = "result = magic binding name", .reason = "no special result variables" },
    .{ .id = "P25-T03", .pattern = "capitalization/name magic for returns", .reason = "lineage is structural, not nominal" },
    .{ .id = "P25-T04", .pattern = "caller redefines semantic return pack", .reason = "consumption selects realization only" },
    .{ .id = "P25-T05", .pattern = "silent ambiguity between two lineages", .reason = "report ambiguity diagnostic" },
    .{ .id = "P25-T06", .pattern = "forced unused tuple/receipt construction", .reason = "discard specialization erases dead returns" },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P25-TD01", .rule = "every value-producing op has a semantic result" },
    .{ .id = "P25-TD02", .rule = "only tail region satisfies implicit/explicit result demand" },
    .{ .id = "P25-TD03", .rule = "loop/branch satisfaction requires unique proven lineage + phi proof" },
    .{ .id = "P25-TD04", .rule = "call-site consumption specializes representation not meaning" },
    .{ .id = "P25-TD05", .rule = "transparent trailing stmts preserve same result lineage" },
    .{ .id = "P25-TD06", .rule = "void demand is zero positions symmetric with typed demand" },
    .{ .id = "P25-TD07", .rule = "supersedes Pass 23 P23-D01 arbitrary live-out deferral" },
};

test "pass25_tail_result_model: rules + rejected heuristics" {
    try std.testing.expectEqualStrings("pass25-tail-result-model-v0", SCHEMA_VERSION);
    try std.testing.expectEqual(@as(usize, 8), @typeInfo(TailResultRule).@"enum".field_names.len);
    try std.testing.expect(rejected_heuristics.len >= 6);
    try std.testing.expect(invariants.len >= 7);
    try std.testing.expectEqualStrings("docs/plans/pass25_tail_result_demand.md", PLAN_PATH);
}
