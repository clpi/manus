//! Pass 22 — graph-native IR, metaprogramming, hardware realization catalog.
const std = @import("std");

pub const SCHEMA_VERSION = "pass22-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass22_compiler_architecture_expansion.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 22 §36 — workstreams 19–35.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P22-WS19", .title = "Canonical graph schema", .status = "partial", .priority = 19, .owner = "src/semantic_graph.zig" },
    .{ .id = "P22-WS20", .title = "Executable region graph", .status = "partial", .priority = 20, .owner = "src/region_graph.zig" },
    .{ .id = "P22-WS21", .title = "Graph-to-LIR lowering", .status = "partial", .priority = 21, .owner = "src/region_transform.zig + src/region_schedule.zig + src/native_backend.zig" },
    .{ .id = "P22-WS22", .title = "Realization-variable core", .status = "partial", .priority = 22, .owner = "src/realization.zig" },
    .{ .id = "P22-WS23", .title = "Hardware descriptor graph", .status = "partial", .priority = 23, .owner = "src/dnir_hardware.zig + src/region_graph.zig" },
    .{ .id = "P22-WS24", .title = "Memory and layout planner", .status = "partial", .priority = 24, .owner = "src/region_layout.zig" },
    .{ .id = "P22-WS25", .title = "Schedule representation", .status = "partial", .priority = 25, .owner = "src/region_schedule.zig" },
    .{ .id = "P22-WS26", .title = "Multi-stage residualization", .status = "open", .priority = 26, .owner = "src/comptime.zig" },
    .{ .id = "P22-WS27", .title = "Transformation metamodel", .status = "partial", .priority = 27, .owner = "src/transform_engine.zig" },
    .{ .id = "P22-WS28", .title = "Foreign semantic capsule", .status = "partial", .priority = 28, .owner = "src/foreign_adapter.zig" },
    .{ .id = "P22-WS29", .title = "Boundary minimization", .status = "open", .priority = 29, .owner = "future" },
    .{ .id = "P22-WS30", .title = "Cross-language native specialization", .status = "open", .priority = 30, .owner = "future" },
    .{ .id = "P22-WS31", .title = "Compiler service interface", .status = "partial", .priority = 31, .owner = "src/main.zig + ~/x/duo-lsp" },
    .{ .id = "P22-WS32", .title = "Hardware-aware proof workload", .status = "partial", .priority = 32, .owner = "examples/pass16_hardware_direct.duo" },
    .{ .id = "P22-WS33", .title = "Bounded equality exploration", .status = "open", .priority = 33, .owner = "future" },
    .{ .id = "P22-WS34", .title = "Semantic profile mapping", .status = "open", .priority = 34, .owner = "future" },
    .{ .id = "P22-WS35", .title = "Future-extension protocol", .status = "open", .priority = 35, .owner = "future" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 22 §37 — completion gates J–T.
pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P22-GJ", .title = "Graph identity through artifacts", .status = "partial" },
    .{ .id = "P22-GK", .title = "Graph-region optimization", .status = "partial" },
    .{ .id = "P22-GL", .title = "Deferred realization", .status = "partial" },
    .{ .id = "P22-GM-REC", .title = "Record shape → DNIR → realizes_as", .status = "partial" },
    .{ .id = "P22-GM", .title = "Hardware graph consumption", .status = "partial" },
    .{ .id = "P22-GN", .title = "Schedule selection", .status = "partial" },
    .{ .id = "P22-GO", .title = "Multi-stage residualization", .status = "open" },
    .{ .id = "P22-GP", .title = "Foreign executable semantics", .status = "partial" },
    .{ .id = "P22-GQ", .title = "Cross-boundary optimization", .status = "open" },
    .{ .id = "P22-GR", .title = "Shared transformation", .status = "partial" },
    .{ .id = "P22-GS", .title = "Hardware multiversioning", .status = "open" },
    .{ .id = "P22-GT", .title = "Extensibility protocol", .status = "open" },
};

pub fn writePass22Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass22":{{"pass":22,"mission":"Graph-native IR, universal metaprogramming, hardware realization","schema":"{s}","plan":"{s}","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","priority":{d},"owner":"{s}"}}
        , .{ ws.id, ws.title, ws.status, ws.priority, ws.owner });
    }
    try w.print("],\"completion_gates\":[", .{});
    for (completion_gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ g.id, g.title, g.status });
    }
    try w.print(
        \\],"pipeline":"semantic_graph→region_graph→DNIR→LIR→machine","invariants":["one-canonical-graph","no-foreign-ir-as-truth","realization-not-second-graph","deterministic-queries"]}}
    , .{});
}

test "pass22_catalog: schema and workstream count" {
    try std.testing.expectEqual(@as(usize, 17), workstreams.len);
    try std.testing.expectEqual(@as(usize, 12), completion_gates.len);
    try std.testing.expectEqualStrings("pass22-catalog-v0", SCHEMA_VERSION);
}
