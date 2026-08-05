//! Pass 16 §12 — bootstrap stage DAG (S0→S3) and trust boundaries.
const std = @import("std");

pub const SCHEMA_VERSION = "bootstrap-dag-v0";

pub const StageId = enum(u8) {
    s0,
    s1,
    s2,
    s3,

    pub fn label(self: StageId) []const u8 {
        return switch (self) {
            .s0 => "S0",
            .s1 => "S1",
            .s2 => "S2",
            .s3 => "S3",
        };
    }
};

pub const Stage = struct {
    id: StageId,
    title: []const u8,
    artifact: []const u8,
    role: []const u8,
    status: []const u8,
    trust_boundary: []const u8,
};

/// Honest bootstrap chain at Pass 16 introduction.
pub const stages: []const Stage = &.{
    .{
        .id = .s0,
        .title = "Trusted seed",
        .artifact = "zig build → zig-out/bin/duo",
        .role = "Pinned Zig bootstrap compiles host compiler (lexer/parser/sema/codegen/native)",
        .status = "active",
        .trust_boundary = "External; pinned via mise/scripts/ci_zig_version.sh",
    },
    .{
        .id = .s1,
        .title = "First Duo-built compiler",
        .artifact = "duo-compiler (planned)",
        .role = "S0 compiles canonical Duo compiler source",
        .status = "open",
        .trust_boundary = "Must not rely on accidental S0-only behavior",
    },
    .{
        .id = .s2,
        .title = "Bootstrap closure",
        .artifact = "duo-compiler (self-built)",
        .role = "S1 recompiles same canonical compiler source",
        .status = "open",
        .trust_boundary = "Semantic + behavioral equivalence with S1 required",
    },
    .{
        .id = .s3,
        .title = "Reproducibility analysis",
        .artifact = "duo-compiler (third generation)",
        .role = "S2 recompiles again; compare fingerprints and binary identity where declared",
        .status = "open",
        .trust_boundary = "Proof bundle records reproducibility status",
    },
};

pub const Comparison = struct {
    id: []const u8,
    title: []const u8,
    required: bool,
};

pub const stage_comparisons: []const Comparison = &.{
    .{ .id = "CMP-01", .title = "Semantic fingerprints", .required = true },
    .{ .id = "CMP-02", .title = "Public capability manifests", .required = true },
    .{ .id = "CMP-03", .title = "Optimized IR fingerprints", .required = true },
    .{ .id = "CMP-04", .title = "Object structure", .required = true },
    .{ .id = "CMP-05", .title = "Binary behavior (tests)", .required = true },
    .{ .id = "CMP-06", .title = "Diagnostics parity", .required = true },
    .{ .id = "CMP-07", .title = "Compiler performance", .required = false },
    .{ .id = "CMP-08", .title = "Binary identity (deterministic builds only)", .required = false },
};

pub fn currentStageReached() StageId {
    return .s0;
}

pub fn writeBootstrapDagJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"current_stage\":\"{s}\",\"stages\":[", .{
        SCHEMA_VERSION, currentStageReached().label(),
    });
    for (stages, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"artifact\":\"{s}\",\"role\":\"{s}\",\"status\":\"{s}\",\"trust_boundary\":\"{s}\"}}",
            .{ s.id.label(), s.title, s.artifact, s.role, s.status, s.trust_boundary },
        );
    }
    try w.writeAll("],\"comparisons\":[");
    for (stage_comparisons, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"required\":{s}}}", .{
            c.id, c.title, if (c.required) "true" else "false",
        });
    }
    try w.writeAll("]}");
}

test "bootstrap_dag: S0 active" {
    try std.testing.expectEqual(StageId.s0, currentStageReached());
    try std.testing.expect(stages.len >= 4);
}
