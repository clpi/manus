//! Pass 26 — evidence invalidation, certainty vocabulary, proof dependency graph.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-evidence-v0";

pub const EvidenceStatus = enum {
    current,
    stale,
    invalidated,
    target_specific,
    profile_only,
    imported,
    untrusted,
    superseded,

    pub fn name(self: EvidenceStatus) []const u8 {
        return @tagName(self);
    }
};

pub const EvidenceDependency = enum {
    compiler_version,
    target,
    source_revision,
    descriptor_identity,
    transformation_version,
    runtime_profile,
    foreign_compiler_version,
    benchmark_hardware,
    environment,
    package_version,

    pub fn name(self: EvidenceDependency) []const u8 {
        return @tagName(self);
    }
};

/// Canonical certainty terms (product lattice axes — not one scalar rank).
pub const CertaintyTerm = enum {
    known,
    stable,
    sealed,
    frozen,
    proven,
    inferred,
    observed,
    guarded,
    assumed,
    trusted,

    pub fn name(self: CertaintyTerm) []const u8 {
        return @tagName(self);
    }
};

pub const ProofRecord = struct {
    id: []const u8,
    claim: []const u8,
    status: EvidenceStatus,
    dependencies: []const EvidenceDependency,
};

pub const example_proofs: []const ProofRecord = &.{
    .{
        .id = "P26-EV01",
        .claim = "bounds_check_elimination",
        .status = .current,
        .dependencies = &.{ .source_revision, .descriptor_identity, .compiler_version },
    },
    .{
        .id = "P26-EV02",
        .claim = "layout_compatible_c_abi",
        .status = .stale,
        .dependencies = &.{ .source_revision, .foreign_compiler_version },
    },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-EV01", .rule = "one evidence dependency graph with automatic staleness" },
    .{ .id = "P26-EV02", .rule = "certainty terms have machine-readable definitions" },
    .{ .id = "P26-EV03", .rule = "knowledge lattice is product; not scalar confidence" },
    .{ .id = "P26-EV04", .rule = "persistent evidence without invalidation is rejected design" },
};

pub fn certaintyTermCount() usize {
    return @typeInfo(CertaintyTerm).@"enum".field_names.len;
}

test "pass26_evidence: status + certainty terms" {
    try std.testing.expect(certaintyTermCount() == 10);
    try std.testing.expect(example_proofs.len >= 2);
    try std.testing.expect(example_proofs[1].status == .stale);
}
