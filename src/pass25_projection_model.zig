//! Pass 25 §13–§17 — bidirectional projection + semantic transaction schema (partial wiring).
const std = @import("std");

pub const SCHEMA_VERSION = "pass25-projection-model-v0";

/// Pass 25 §13 — bidirectional metaprogramming levels.
pub const BidirectionalLevel = enum(u2) {
    observation = 0,
    forward_generation = 1,
    reverse_proposal = 2,
    automatic_sync = 3,

    pub fn name(self: BidirectionalLevel) []const u8 {
        return switch (self) {
            .observation => "observation",
            .forward_generation => "forward_generation",
            .reverse_proposal => "reverse_proposal",
            .automatic_sync => "automatic_sync",
        };
    }
};

/// Pass 25 §14 — projection reversibility class.
pub const ProjectionClass = enum {
    one_way,
    partially_reversible,
    fully_reversible,

    pub fn name(self: ProjectionClass) []const u8 {
        return @tagName(self);
    }
};

/// Pass 25 §16 — authority model for projections.
pub const AuthorityModel = enum {
    duo_authoritative,
    foreign_authoritative,
    shared_semantic,
    multi_master,

    pub fn name(self: AuthorityModel) []const u8 {
        return @tagName(self);
    }
};

/// Pass 25 §22 — capability tiers for agents and tooling.
pub const MetaCapability = enum {
    observe,
    generate,
    reverse_interpret,
    mutate_semantic_source,
    mutate_foreign_source,
    regenerate,
    patch_runtime,

    pub fn name(self: MetaCapability) []const u8 {
        return @tagName(self);
    }
};

/// Pass 25 §15 — semantic transaction (schema; reverse never mutates directly).
pub const SemanticTransaction = struct {
    id: u64,
    snapshot_id: ?u64 = null,
    proposed_ops: u32 = 0,
    ambiguity_candidates: u32 = 0,
    validated: bool = false,
    committed: bool = false,
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P25-P01", .rule = "level 0 observation always allowed" },
    .{ .id = "P25-P02", .rule = "reverse edits return transactions, never direct mutation" },
    .{ .id = "P25-P03", .rule = "level 3 automatic sync is exceptional and per-relationship" },
    .{ .id = "P25-P04", .rule = "fully reversible never assumed without validation" },
    .{ .id = "P25-P05", .rule = "bidirectional unused implies zero runtime cost" },
};

test "pass25_projection_model: four bidirectional levels" {
    try std.testing.expect(@intFromEnum(BidirectionalLevel.automatic_sync) == 3);
    try std.testing.expect(invariants.len >= 5);
}
