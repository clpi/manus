//! Pass 26 — recursive descriptors and incomplete semantic values.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-recursive-descriptor-v0";

pub const RecursionKind = enum {
    none,
    indirect_pointer,
    inline_fixed_point,
    mutual_module,
    foreign_recursive,

    pub fn name(self: RecursionKind) []const u8 {
        return @tagName(self);
    }
};

pub const DescriptorCompletion = enum {
    placeholder,
    resolving,
    complete,
    invalid_incomplete,

    pub fn name(self: DescriptorCompletion) []const u8 {
        return @tagName(self);
    }
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-RD01", .rule = "identity established first; body resolves as semantic fixed point" },
    .{ .id = "P26-RD02", .rule = "placeholder identity distinct from complete fingerprint" },
    .{ .id = "P26-RD03", .rule = "mutually recursive modules classified in init graph" },
    .{ .id = "P26-RD04", .rule = "no separate forward-declaration type subsystem" },
    .{ .id = "P26-RD05", .rule = "invalid incomplete descriptors rejected at seal time" },
};

pub const Example = struct {
    id: []const u8,
    source: []const u8,
    recursion: RecursionKind,
};

pub const examples: []const Example = &.{
    .{ .id = "P26-RX01", .source = "Node = @{ value: i64, next: Pointer Node }", .recursion = .indirect_pointer },
    .{ .id = "P26-RX02", .source = "Expr = @{ Literal(value), Binary(left: Expr, right: Expr) }", .recursion = .inline_fixed_point },
};

test "pass26_recursive_descriptor: fixed point model" {
    try std.testing.expect(invariants.len >= 5);
    try std.testing.expect(examples.len >= 2);
}
