//! Pass 26 — canonical hashing, ordering, and iteration semantics.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-hash-order-v0";

pub const HashKind = enum {
    runtime_hash,
    semantic_fingerprint,
    structural_hash,
    source_hash,
    artifact_hash,
    cache_key,

    pub fn name(self: HashKind) []const u8 {
        return @tagName(self);
    }
};

pub const IterationOrder = enum {
    unspecified,
    insertion_order,
    declaration_order,
    key_sorted,
    target_dependent,
    deterministic_build,
    parallel_partition,
    semantic_set,

    pub fn name(self: IterationOrder) []const u8 {
        return @tagName(self);
    }
};

pub const FieldOrderPolicy = enum {
    significant,
    insignificant,
    declaration_significant,
    normalized_canonical,

    pub fn name(self: FieldOrderPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const TableOrderExample = struct {
    id: []const u8,
    a_fields: []const u8,
    b_fields: []const u8,
    structurally_equivalent: bool,
    fingerprint_same: bool,
    field_order_policy: FieldOrderPolicy,
};

pub const table_order_examples: []const TableOrderExample = &.{
    .{
        .id = "P26-HO01",
        .a_fields = "x=1,y=2",
        .b_fields = "y=2,x=1",
        .structurally_equivalent = true,
        .fingerprint_same = true,
        .field_order_policy = .normalized_canonical,
    },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-HO01", .rule = "six hash kinds; target runtime hash ≠ semantic fingerprint" },
    .{ .id = "P26-HO02", .rule = "iteration order is shape/descriptor fact; not silent Lua upgrade" },
    .{ .id = "P26-HO03", .rule = "field order policy explicit per descriptor kind" },
    .{ .id = "P26-HO04", .rule = "deterministic build order recorded for reproducibility" },
};

test "pass26_hash_order: hash kinds + iteration order" {
    try std.testing.expect(@typeInfo(HashKind).@"enum".field_names.len == 6);
    try std.testing.expect(@typeInfo(IterationOrder).@"enum".field_names.len >= 8);
    try std.testing.expect(table_order_examples[0].fingerprint_same);
}
