//! Pass 27 — proof bundle pipeline and evidence record schema.
const std = @import("std");
const backend_identity = @import("backend_identity.zig");

pub const SCHEMA_VERSION = "pass27-proof-bundle-v0";
pub const PLAN_PATH = "docs/archive/pass27_proof_bundle.md";

/// Mandatory pipeline stages (ecosystem charter proof bundle).
pub const PipelineStage = enum {
    accepted_source,
    canonical_semantics,
    transformation,
    native_artifact,
    correctness_comparison,
    artifact_inspection,
    benchmark,
    lsp_mcp_explanation,

    pub fn name(self: PipelineStage) []const u8 {
        return @tagName(self);
    }
};

pub const StageStatus = enum {
    pending,
    partial,
    complete,
    failed,
    not_applicable,

    pub fn name(self: StageStatus) []const u8 {
        return @tagName(self);
    }
};

pub const StageRecord = struct {
    stage: PipelineStage,
    status: StageStatus,
    artifact_ref: ?[]const u8 = null,
};

pub const FlagshipProof = enum {
    ward_decoder,
    shape_ladder,
    selective_returns,
    closure_pipeline_fusion,
    zero_copy_c_boundary,
    static_parallel_tasks,

    pub fn id(self: FlagshipProof) []const u8 {
        return switch (self) {
            .ward_decoder => "P27-PROOF-01",
            .shape_ladder => "P27-PROOF-02",
            .selective_returns => "P27-PROOF-03",
            .closure_pipeline_fusion => "P27-PROOF-04",
            .zero_copy_c_boundary => "P27-PROOF-05",
            .static_parallel_tasks => "P27-PROOF-06",
        };
    }
};

/// One complete proof bundle for a workload claim.
pub const ProofBundle = struct {
    proof_id: []const u8,
    source_path: []const u8,
    backend: backend_identity.Backend,
    representation: backend_identity.RepresentationProfile,
    runtime: backend_identity.RuntimeProfile,
    stages: []const StageRecord,
    correctness_hash: ?[]const u8 = null,
    /// FNV-style or semantic fingerprint of RESULT output.
    result_checksum: ?[]const u8 = null,
    benchmark_ns: ?u64 = null,
    code_size_bytes: ?usize = null,
    compiler_time_ns: ?u64 = null,
    claims_allowed: bool = false,
};

pub const default_stages: []const StageRecord = &.{
    .{ .stage = .accepted_source, .status = .pending },
    .{ .stage = .canonical_semantics, .status = .pending },
    .{ .stage = .transformation, .status = .pending },
    .{ .stage = .native_artifact, .status = .pending },
    .{ .stage = .correctness_comparison, .status = .pending },
    .{ .stage = .artifact_inspection, .status = .pending },
    .{ .stage = .benchmark, .status = .pending },
    .{ .stage = .lsp_mcp_explanation, .status = .pending },
};

pub fn stageCount() usize {
    return @typeInfo(PipelineStage).@"enum".field_names.len;
}

pub fn bundleClaimsAllowed(bundle: ProofBundle) bool {
    for (bundle.stages) |s| {
        if (s.status != .complete and s.status != .not_applicable) return false;
    }
    return bundle.correctness_hash != null and bundle.result_checksum != null;
}

test "pass27_proof_bundle: eight pipeline stages" {
    try std.testing.expect(stageCount() == 8);
    try std.testing.expect(default_stages.len == 8);
    try std.testing.expectEqualStrings("P27-PROOF-01", FlagshipProof.ward_decoder.id());
}
