//! Pass 16 §12.3 / P16-WS24 — bootstrap stage comparison harness (scaffold).
const std = @import("std");
const bootstrap_dag = @import("bootstrap_dag.zig");

pub const SCHEMA_VERSION = "stage-compare-v0";

pub const CompareStatus = enum {
    open,
    pass,
    fail,

    pub fn name(self: CompareStatus) []const u8 {
        return @tagName(self);
    }
};

pub const CompareResult = struct {
    comparison_id: []const u8,
    title: []const u8,
    from_stage: []const u8,
    to_stage: []const u8,
    status: CompareStatus,
    notes: []const u8,
};

pub const results: []const CompareResult = &.{
    .{ .comparison_id = "CMP-S0-S1", .title = "Semantic fingerprints", .from_stage = "S0", .to_stage = "S1", .status = .open, .notes = "Awaiting S1 artifact" },
    .{ .comparison_id = "CMP-S1-S2", .title = "Behavioral equivalence", .from_stage = "S1", .to_stage = "S2", .status = .open, .notes = "Awaiting bootstrap closure" },
    .{ .comparison_id = "CMP-S2-S3", .title = "Reproducibility / binary identity", .from_stage = "S2", .to_stage = "S3", .status = .open, .notes = "Optional third generation" },
};

pub fn writeCompareJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"harness_status\":\"scaffold\",\"current_stage\":\"{s}\",\"required_comparisons\":[", .{
        SCHEMA_VERSION,
        bootstrap_dag.currentStageReached().label(),
    });
    for (bootstrap_dag.stage_comparisons, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"required\":{}}}", .{
            c.id, c.title, c.required,
        });
    }
    try w.writeAll("],\"stage_results\":[");
    for (results, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"comparison_id\":\"{s}\",\"title\":\"{s}\",\"from_stage\":\"{s}\",\"to_stage\":\"{s}\",\"status\":\"{s}\",\"notes\":\"{s}\"}}",
            .{ r.comparison_id, r.title, r.from_stage, r.to_stage, r.status.name(), r.notes },
        );
    }
    try w.writeAll("]}");
}

test "stage_compare: scaffold open" {
    for (results) |r| try std.testing.expect(r.status == .open);
}
