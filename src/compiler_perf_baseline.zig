//! Pass 16 §22.5 — compiler performance baseline seed (continuous measurement: P16-WS27).
const std = @import("std");
const compiler_perf_measure = @import("compiler_perf_measure.zig");

pub const SCHEMA_VERSION = "compiler-perf-baseline-v0";

pub const Metric = struct {
    id: []const u8,
    scenario: []const u8,
    status: []const u8,
    notes: []const u8,
};

/// Honest seed — values recorded when harness exists; status marks measurement gap.
pub const metrics: []const Metric = &.{
    .{ .id = "CP-01", .scenario = "clean cold compile (duo binary)", .status = "unmeasured", .notes = "Use zig build + wall clock; record in docs/performance.md" },
    .{ .id = "CP-02", .scenario = "warm no-op rebuild", .status = "unmeasured", .notes = "Requires incremental compile harness" },
    .{ .id = "CP-03", .scenario = "one-function edit latency", .status = "unmeasured", .notes = "LSP/edit path not instrumented" },
    .{ .id = "CP-04", .scenario = "keyword classify lookup (duo_classify)", .status = "measured", .notes = "duo selfhost measure; production via duo_keyword_classify.c" },
    .{ .id = "CP-07", .scenario = "production lexer token throughput", .status = "measured", .notes = "lexer_differential.measureLexThroughput; CP-07 in duo selfhost measure" },
    .{ .id = "CP-05", .scenario = "self-rebuild S0→S1", .status = "unmeasured", .notes = "Blocked on S1 compiler artifact" },
    .{ .id = "CP-06", .scenario = "pass16_m1_lexer_proof compile", .status = "spot_check", .notes = "duo run examples/pass16_m1_lexer_proof.duo ~700ms debug (environment dependent)" },
};

pub fn writeBaselineJson(w: *std.Io.Writer) !void {
    const measured = compiler_perf_measure.measureKeywordLookupPerOpNs();
    try w.print("{{\"schema\":\"{s}\",\"continuous_harness\":\"partial\",\"owner\":\"P16-WS27\",\"keyword_lookup_ns_measured\":", .{SCHEMA_VERSION});
    if (measured > 0) try w.print("{d}", .{measured}) else try w.writeAll("null");
    try w.writeAll(",\"metrics\":[");
    for (metrics, 0..) |m, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"scenario\":\"{s}\",\"status\":\"{s}\",\"notes\":\"{s}\"}}",
            .{ m.id, m.scenario, m.status, m.notes },
        );
    }
    try w.writeAll("]}");
}

test "compiler_perf_baseline: metrics seeded" {
    try std.testing.expect(metrics.len >= 4);
}
