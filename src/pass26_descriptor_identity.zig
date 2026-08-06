//! Pass 26 §5–§7 — descriptor identity, normalization, snapshot vs mutation.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-descriptor-identity-v0";

/// Four identity layers — must never conflate (Pass 26 §6).
pub const IdentityLayer = enum {
    semantic_fingerprint,
    declaration_identity,
    instance_identity,
    physical_realization,

    pub fn name(self: IdentityLayer) []const u8 {
        return @tagName(self);
    }

    pub fn description(self: IdentityLayer) []const u8 {
        return switch (self) {
            .semantic_fingerprint => "canonical semantic content hash; drives specialization + interning",
            .declaration_identity => "source/provenance-specific ID; survives merge with same fingerprint",
            .instance_identity => "runtime descriptor value identity; per evaluation unless interned",
            .physical_realization => "layout/ABI/target facts; not part of semantic fingerprint",
        };
    }
};

/// Language-level equality/identity notions (Pass 26 §5).
pub const EqualityKind = enum {
    semantic_identity,
    runtime_object_identity,
    descriptor_identity,
    structural_equality,
    value_equality,
    representation_equality,
    foreign_identity,
    observational_equivalence,

    pub fn name(self: EqualityKind) []const u8 {
        return @tagName(self);
    }
};

pub const DescriptorState = enum {
    frozen_snapshot,
    open_semantic,
    sealed,
    derived,
    mutable_builder,

    pub fn name(self: DescriptorState) []const u8 {
        return @tagName(self);
    }
};

pub const InterningPolicy = enum {
    /// Pure closed descriptors with identical fingerprint collapse.
    canonicalize_pure,
    /// Open descriptors never intern until sealed.
    defer_until_sealed,
    /// Foreign/imported descriptors intern by foreign fingerprint + trust.
    foreign_fingerprint,
    /// User-visible distinct instances even when fingerprint matches.
    preserve_declaration,

    pub fn name(self: InterningPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const NormalizationRule = struct {
    id: []const u8,
    rule: []const u8,
};

pub const normalization_rules: []const NormalizationRule = &.{
    .{ .id = "P26-DN01", .rule = "Pair i32, str from distinct bindings share fingerprint when pure" },
    .{ .id = "P26-DN02", .rule = "normalization deterministic across builds for pure descriptors" },
    .{ .id = "P26-DN03", .rule = "provenance separate when semantic fingerprint merges" },
    .{ .id = "P26-DN04", .rule = "open descriptors prevent interning until sealed" },
    .{ .id = "P26-DN05", .rule = "target layout belongs to physical_realization, not fingerprint" },
    .{ .id = "P26-DN06", .rule = "post-construction table mutation does not mutate descriptor" },
};

pub const SnapshotRule = struct {
    id: []const u8,
    rule: []const u8,
};

pub const snapshot_rules: []const SnapshotRule = &.{
    .{ .id = "P26-DS01", .rule = "make_descriptor captures immutable semantic snapshot of builder" },
    .{ .id = "P26-DS02", .rule = "fields.z = f64 after Point = make_descriptor fields does not change Point" },
    .{ .id = "P26-DS03", .rule = "@{} frozen tables snapshot at construction" },
    .{ .id = "P26-DS04", .rule = "descriptor revision requires explicit semantic transaction" },
};

pub const ExampleScenario = struct {
    id: []const u8,
    source: []const u8,
    fingerprint_same: bool,
    declaration_same: bool,
    runtime_same: bool,
};

pub const example_scenarios: []const ExampleScenario = &.{
    .{
        .id = "P26-EX01",
        .source = "A = Slice Byte; B = Slice Byte",
        .fingerprint_same = true,
        .declaration_same = false,
        .runtime_same = false,
    },
    .{
        .id = "P26-EX02",
        .source = "a = Point{x=1,y=2}; b = Point{x=1,y=2}",
        .fingerprint_same = true,
        .declaration_same = false,
        .runtime_same = false,
    },
    .{
        .id = "P26-EX03",
        .source = "X = Pair i32, str; Y = Pair i32, str (pure)",
        .fingerprint_same = true,
        .declaration_same = false,
        .runtime_same = true,
    },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-DI01", .rule = "four identity layers never conflated in caches or ABI keys" },
    .{ .id = "P26-DI02", .rule = "eight equality kinds available for contracts and merge" },
    .{ .id = "P26-DI03", .rule = "builder mutation after snapshot is invisible to descriptor" },
    .{ .id = "P26-DI04", .rule = "interning policy explicit per descriptor state" },
    .{ .id = "P26-DI05", .rule = "text ranges are views; stable IDs live in semantic graph" },
};

pub fn layerCount() usize {
    return @typeInfo(IdentityLayer).@"enum".field_names.len;
}

pub fn equalityKindCount() usize {
    return @typeInfo(EqualityKind).@"enum".field_names.len;
}

test "pass26_descriptor_identity: four layers + eight equality kinds" {
    try std.testing.expect(layerCount() == 4);
    try std.testing.expect(equalityKindCount() == 8);
    try std.testing.expect(normalization_rules.len >= 6);
    try std.testing.expect(snapshot_rules.len >= 4);
    try std.testing.expect(example_scenarios[0].fingerprint_same);
    try std.testing.expect(!example_scenarios[1].runtime_same);
}
