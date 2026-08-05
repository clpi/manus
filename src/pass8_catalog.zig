/// Pass 8 — persistent semantic computing, realization planning, living program architecture.
const std = @import("std");
const pass7_catalog = @import("pass7_catalog.zig");
const realization = @import("realization.zig");
const persistent_semantic_state = @import("persistent_semantic_state.zig");
const assumption_guard = @import("assumption_guard.zig");
const evidence_record = @import("evidence_record.zig");

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass8_persistent_semantic_computing.md";
    pub const pass7 = pass7_catalog.CatalogPaths.plan;
    pub const semantic_universe = "docs/semantic_universe.md";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    area: []const u8,
};

pub const milestones: []const struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
} = &.{
    .{ .id = "P8-M1", .title = "Explicit realization decision", .status = "partial" },
    .{ .id = "P8-M2", .title = "Persistent semantic evidence reuse", .status = "partial" },
    .{ .id = "P8-M3", .title = "Derived execution plan", .status = "open" },
    .{ .id = "P8-M4", .title = "Semantic replay", .status = "open" },
    .{ .id = "P8-M5", .title = "Semantic evolution report", .status = "open" },
    .{ .id = "P8-M6", .title = "Bidirectional descriptor proof", .status = "open" },
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P8-01", .title = "Repository audit + readiness maps", .status = "partial", .priority = 1, .area = "audit" },
    .{ .id = "P8-02", .title = "Realization variable semantic record", .status = "partial", .priority = 2, .area = "realization" },
    .{ .id = "P8-03", .title = "Degree-of-freedom representation", .status = "partial", .priority = 3, .area = "realization" },
    .{ .id = "P8-04", .title = "Realization candidate registry seam", .status = "partial", .priority = 4, .area = "realization" },
    .{ .id = "P8-05", .title = "Deterministic candidate comparison", .status = "partial", .priority = 5, .area = "realization" },
    .{ .id = "P8-06", .title = "Evidence record unification", .status = "partial", .priority = 6, .area = "evidence" },
    .{ .id = "P8-07", .title = "Persistent semantic fingerprint store", .status = "partial", .priority = 7, .area = "persistence" },
    .{ .id = "P8-08", .title = "Assumption and invalidation graph", .status = "partial", .priority = 8, .area = "invalidation" },
    .{ .id = "P8-09", .title = "Unified dependency/conflict edge model", .status = "open", .priority = 9, .area = "dependencies" },
    .{ .id = "P8-10", .title = "Semantic version lineage record", .status = "open", .priority = 10, .area = "evolution" },
};

pub const Readiness = struct {
    area: []const u8,
    status: []const u8,
    owner: []const u8,
};

pub const realization_readiness: []const Readiness = &.{
    .{ .area = "realization_variables", .status = "partial", .owner = "realization.zig" },
    .{ .area = "degrees_of_freedom", .status = "partial", .owner = "realization.zig" },
    .{ .area = "deterministic_planner", .status = "partial", .owner = "realization.selectDeterministic" },
    .{ .area = "persistent_evidence", .status = "partial", .owner = "persistent_semantic_state.zig" },
    .{ .area = "invalidation_reuse", .status = "partial", .owner = "compile_semantic_cache.zig + semantic_invalidation.zig" },
    .{ .area = "codegen_realization_bridge", .status = "partial", .owner = "codegen.ensure_record_decl + realization.logAppliedRepresentation" },
    .{ .area = "dependency_graph", .status = "partial", .owner = "semantic_graph.zig (lift only)" },
    .{ .area = "continuation_model", .status = "open", .owner = "async_lower + closures" },
    .{ .area = "semantic_replay", .status = "open", .owner = "planned" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writePass8Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass8":{{"mission":"persistent semantic computing + negotiated realization","schema":"pass8-catalog-v0","catalogs":{{
    , .{});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\"}},\"workstreams\":[", .{});

    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"area\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.area,
        });
    }

    try w.print("],\"milestones\":[", .{});
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\"}}", .{m.status});
    }

    try w.print("],\"realization_readiness\":[", .{});
    for (realization_readiness, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"area\":\"", .{});
        try jsonEscape(w, row.area);
        try w.print("\",\"status\":\"{s}\",\"owner\":\"", .{row.status});
        try jsonEscape(w, row.owner);
        try w.print("\"}}", .{});
    }

    try w.print("],\"modules\":{{\"realization\":\"", .{});
    try jsonEscape(w, "src/realization.zig");
    try w.print("\",\"persistent_state\":\"", .{});
    try jsonEscape(w, "src/persistent_semantic_state.zig");
    try w.print("\",\"fingerprints\":\"", .{});
    try jsonEscape(w, "src/semantic_fingerprint.zig");
    try w.print("\",\"assumptions\":\"", .{});
    try jsonEscape(w, "src/assumption_guard.zig");
    try w.print("\",\"evidence\":\"", .{});
    try jsonEscape(w, "src/evidence_record.zig");
    try w.print("\"}},\"schemas\":{{\"realization\":\"{s}\",\"persistent_state\":\"{s}\",\"fingerprints\":\"", .{
        realization.SCHEMA_VERSION,
        persistent_semantic_state.SCHEMA_VERSION,
    });
    try jsonEscape(w, @import("semantic_fingerprint.zig").SCHEMA_VERSION);
    try w.print("\",\"assumptions\":\"", .{});
    try jsonEscape(w, assumption_guard.SCHEMA_VERSION);
    try w.print("\",\"evidence\":\"", .{});
    try jsonEscape(w, evidence_record.SCHEMA_VERSION);
    try w.print("\"}},\"invariants\":[\"realization-not-second-graph\",\"profile-not-guarantee\",\"deterministic-planner\",\"explicit-invalidation\",\"sim-agent-boundary\"]}}",
        .{},
    );
}

test "pass8_catalog: writePass8Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass8Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P8-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "realization.zig") != null);
}
