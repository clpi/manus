//! Pass 27 — metaprogramming proof bundle stages (III.1–III.15).
const std = @import("std");

pub const SCHEMA_VERSION = "pass27-meta-proof-v0";

pub const MacroPathClass = enum {
    canonical_semantic_staging,
    syntax_only_compatibility,
    shadow_system,
    dead,
    migration_required,

    pub fn name(self: MacroPathClass) []const u8 {
        return @tagName(self);
    }
};

/// Pass 23 macro/quote audit classification (III.1).
pub const macro_path_audit: []const struct {
    id: []const u8,
    path: []const u8,
    class: MacroPathClass,
} = &.{
    .{ .id = "P27-MAC-01", .path = "MacroDef AST expansion", .class = .migration_required },
    .{ .id = "P27-MAC-02", .path = "quote/unquote concrete syntax", .class = .syntax_only_compatibility },
    .{ .id = "P27-MAC-03", .path = "staged semantic function (@)", .class = .canonical_semantic_staging },
    .{ .id = "P27-MAC-04", .path = "transform_engine registered combinator", .class = .canonical_semantic_staging },
};

pub const MetaObjectKind = enum {
    descriptor,
    shape,
    function_sig,
    parameter,
    return_pack,
    call_site,
    closure,
    field,
    variant,
    effect_set,
    stage,
    region,
    transformation,
    representation,
    foreign_entity,
    diagnostic,
    evidence,
    artifact,

    pub fn name(self: MetaObjectKind) []const u8 {
        return @tagName(self);
    }
};

pub const MetaProofStage = enum {
    stable_api,
    generated_hygiene,
    transaction_lifecycle,
    transform_composition,
    bidirectional_projection,
    derivation_registry,
    meta_circular_convergence,
    staging_operational,
    compile_time_effects,
    semantic_diff,
    foreign_trust,
    round_trip_emission,
    shared_cross_language,
    metaprogram_perf,

    pub fn name(self: MetaProofStage) []const u8 {
        return @tagName(self);
    }
};

pub const MetaProofRecord = struct {
    stage: MetaProofStage,
    status: []const u8,
    gate_id: []const u8,
};

pub const meta_proof_backlog: []const MetaProofRecord = &.{
    .{ .stage = .stable_api, .status = "open", .gate_id = "P27-G05" },
    .{ .stage = .generated_hygiene, .status = "open", .gate_id = "P27-G05" },
    .{ .stage = .transaction_lifecycle, .status = "open", .gate_id = "P27-G05" },
    .{ .stage = .transform_composition, .status = "partial", .gate_id = "P27-G05" },
    .{ .stage = .bidirectional_projection, .status = "open", .gate_id = "P27-G13" },
    .{ .stage = .derivation_registry, .status = "open", .gate_id = "P27-G12" },
    .{ .stage = .shared_cross_language, .status = "open", .gate_id = "P27-G12" },
};

pub fn metaObjectKindCount() usize {
    return @typeInfo(MetaObjectKind).@"enum".field_names.len;
}

test "pass27_meta_proof: macro audit + meta object kinds" {
    try std.testing.expect(macro_path_audit.len >= 4);
    try std.testing.expect(metaObjectKindCount() >= 17);
    try std.testing.expect(meta_proof_backlog.len >= 7);
}
