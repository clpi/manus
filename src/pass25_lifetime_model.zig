//! Pass 25 §7 — lifetime as provenance (design authority; partial wiring).
const std = @import("std");

pub const SCHEMA_VERSION = "pass25-lifetime-model-v0";

pub const LifetimeViolationKind = enum {
    escape_of_stack_view,
    use_after_origin_end,
    conflicting_mutable_aliases,
    invalid_pointer_reconstruction,
    region_outlived,

    pub fn name(self: LifetimeViolationKind) []const u8 {
        return @tagName(self);
    }
};

pub const RepairStrategy = enum {
    copy,
    promote,
    transfer_ownership,
    change_api,

    pub fn name(self: RepairStrategy) []const u8 {
        return @tagName(self);
    }
};

/// Tracked provenance facts (semantic graph schema stub).
pub const ProvenanceFacts = struct {
    origin_stable_id: ?u64 = null,
    owner_stable_id: ?u64 = null,
    escapes: bool = false,
    destroyed_at: ?u64 = null,
    may_alias: bool = false,
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P25-L01", .rule = "lifetimes are provenance, never source syntax" },
    .{ .id = "P25-L02", .rule = "returned views derive lifetime from origin" },
    .{ .id = "P25-L03", .rule = "invalid lifetimes report violations, not silent heap promote" },
    .{ .id = "P25-L04", .rule = "arena destruction ends derived lifetimes" },
};

test "pass25_lifetime_model: repair strategies" {
    try std.testing.expect(@typeInfo(RepairStrategy).@"enum".field_names.len == 4);
    try std.testing.expect(invariants.len >= 4);
}
