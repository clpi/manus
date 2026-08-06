//! Pass 25 §6 — five semantic categories (design authority; partial wiring).
const std = @import("std");

pub const SCHEMA_VERSION = "pass25-semantic-category-v0";

/// Pass 25 §6 — semantic provenance categories (not surface syntax).
pub const SemanticCategory = enum {
    value,
    alias,
    view,
    owner,
    pointer,

    pub fn name(self: SemanticCategory) []const u8 {
        return @tagName(self);
    }
};

pub const AccessCapability = enum {
    read,
    write,
    read_write,

    pub fn name(self: AccessCapability) []const u8 {
        return @tagName(self);
    }
};

/// View metadata tracked in the semantic graph (schema stub).
pub const ViewProvenance = struct {
    origin_stable_id: ?u64 = null,
    extent: ?u64 = null,
    descriptor: ?[]const u8 = null,
    access: AccessCapability = .read,
    may_escape: bool = false,
};

/// Owner realization candidates (§6, §10).
pub const OwnerKind = enum {
    stack,
    arena,
    shared,
    foreign,
    device,
    static_storage,
    heap,
    compiler_selected,

    pub fn name(self: OwnerKind) []const u8 {
        return @tagName(self);
    }
};

/// Pointer provenance metadata (§11).
pub const PointerProvenance = struct {
    origin_stable_id: ?u64 = null,
    alignment: ?u32 = null,
    address_space: ?[]const u8 = null,
    extent: ?u64 = null,
    alias_class: ?[]const u8 = null,
    owner_kind: OwnerKind = .compiler_selected,
    target_descriptor: ?[]const u8 = null,
    valid: bool = true,
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P25-C01", .rule = "five categories cover all reference semantics" },
    .{ .id = "P25-C02", .rule = "views created by ordinary calls, not borrow syntax" },
    .{ .id = "P25-C03", .rule = "pointers are explicit values with provenance" },
    .{ .id = "P25-C04", .rule = "aliases require no surface syntax" },
    .{ .id = "P25-C05", .rule = "ownership is responsibility, not a source type" },
};

test "pass25_semantic_category: five categories" {
    try std.testing.expect(@intFromEnum(SemanticCategory.pointer) == 4);
    try std.testing.expect(invariants.len >= 5);
}
