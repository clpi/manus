//! Pass 1 — identity catalog export (`duo catalog` → `pass1`).
//!
//! Duo is Lua with progressively stronger compiler knowledge.
//! Canonical plans: `docs/semantic_universe.md`, `docs/plans/pass1_identity.md`.
const std = @import("std");
const transform_engine = @import("transform_engine.zig");

pub const SCHEMA_VERSION = "pass1-catalog-v0";

pub const CatalogPaths = struct {
    pub const plan = "docs/archive/pass1_identity.md";
    pub const semantic_universe = "docs/semantic_universe.md";
    pub const graph_architecture = "docs/archive/semantic_graph_architecture.md";
    pub const transform_engine = "src/transform_engine.zig";
    pub const meta_dispatch = "src/meta_dispatch.zig";
    pub const semantic_graph = "src/semantic_graph.zig";
    pub const parity_harness = "src/meta_transform_tests.zig";
    pub const architecture_proof = "examples/architecture_proof.duo";
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const milestones: []const Milestone = &.{
    .{ .id = "P1-M0", .title = "Canonical identity plan + catalog", .status = "done" },
    .{ .id = "P1-M1", .title = "Phase 0 alignment (registry, parity, provenance)", .status = "partial" },
    .{ .id = "P1-M2", .title = "Phase 1 graph spine (stable IDs, JSON dump)", .status = "partial" },
    .{ .id = "P1-M3", .title = "Lua semantic parity (missing args, nil, truthiness)", .status = "done" },
    .{ .id = "P1-M4", .title = "Progressive specialization ladder + smoke", .status = "partial" },
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P1-WS1", .title = "Semantic universe + agent alignment docs", .status = "done", .priority = 1 },
    .{ .id = "P1-WS2", .title = "Transform engine stub + tier-1 registry", .status = "partial", .priority = 2 },
    .{ .id = "P1-WS3", .title = "G-061 parity harness (3-site compile tests)", .status = "partial", .priority = 3 },
    .{ .id = "P1-WS4", .title = "Provenance log (DUO_PROVENANCE=1)", .status = "done", .priority = 4 },
    .{ .id = "P1-WS5", .title = "Semantic graph lift + duo graph JSON + sidecar", .status = "partial", .priority = 5 },
    .{ .id = "P1-WS6", .title = "StorageClass ladder + comp.type.shape", .status = "done", .priority = 6 },
    .{ .id = "P1-WS7", .title = "Lua call semantics (missing args, and/or truthiness)", .status = "done", .priority = 7 },
    .{ .id = "P1-WS8", .title = "Architecture proof example", .status = "done", .priority = 8 },
};

pub const AcceptanceCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const acceptance_criteria: []const AcceptanceCriterion = &.{
    .{ .id = 1, .title = "Identity statement canonical in docs and catalog", .status = "partial" },
    .{ .id = 2, .title = "Phase 0 checklist tracked with evidence", .status = "partial" },
    .{ .id = 3, .title = "Tier-1 combinators registered + parity-tested", .status = "partial" },
    .{ .id = 4, .title = "duo graph exports shapes for any .duo module", .status = "partial" },
    .{ .id = 5, .title = "Missing trailing args + bool and/or compile correctly", .status = "met" },
    .{ .id = 6, .title = "No new comp.* without registry entry (G-061)", .status = "partial" },
    .{ .id = 7, .title = "Dynamic Lua correct; typed paths avoid boxing when proven", .status = "partial" },
};

fn countMilestonesDone() usize {
    var n: usize = 0;
    for (milestones) |m| {
        if (std.mem.eql(u8, m.status, "done")) n += 1;
    }
    return n;
}

fn countWorkstreamsDone() usize {
    var n: usize = 0;
    for (workstreams) |ws| {
        if (std.mem.eql(u8, ws.status, "done")) n += 1;
    }
    return n;
}

fn countAcceptanceMet() usize {
    var n: usize = 0;
    for (acceptance_criteria) |a| {
        if (std.mem.eql(u8, a.status, "met") or std.mem.eql(u8, a.status, "done")) n += 1;
    }
    return n;
}

fn countAcceptancePartial() usize {
    var n: usize = 0;
    for (acceptance_criteria) |a| {
        if (std.mem.eql(u8, a.status, "partial")) n += 1;
    }
    return n;
}

pub fn writePass1Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass1":{{"pass":1,"mission":"Lua semantics with progressive compiler knowledge","schema":"{s}","catalogs":{{
    , .{SCHEMA_VERSION});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"semantic_universe\":\"", .{});
    try jsonEscape(w, CatalogPaths.semantic_universe);
    try w.print("\",\"graph_architecture\":\"", .{});
    try jsonEscape(w, CatalogPaths.graph_architecture);
    try w.print("\"}},\"tier1_combinators\":{d},\"parity_tier1\":{d},\"milestones\":[", .{
        transform_engine.parity_tier1.len,
        transform_engine.parity_tier1.len,
    });
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\"}}", .{m.status});
    }
    try w.print("],\"workstreams\":[", .{});
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d}}}", .{ ws.status, ws.priority });
    }
    try w.print("],\"acceptance_criteria\":[", .{});
    for (acceptance_criteria, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":{d},\"title\":\"", .{a.id});
        try jsonEscape(w, a.title);
        try w.print("\",\"status\":\"{s}\"}}", .{a.status});
    }
    try w.print("],\"readiness_summary\":{{\"milestones_done\":{d},\"workstreams_done\":{d},\"acceptance_met\":{d},\"acceptance_partial\":{d}}}}}", .{
        countMilestonesDone(),
        countWorkstreamsDone(),
        countAcceptanceMet(),
        countAcceptancePartial(),
    });
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        }
    }
}

test "pass1_catalog: milestones and workstreams non-empty" {
    try std.testing.expect(milestones.len >= 4);
    try std.testing.expect(workstreams.len >= 6);
    try std.testing.expect(acceptance_criteria.len == 7);
}

test "pass1_catalog: writePass1Json structure" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePass1Json(&buf.writer);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "readiness_summary") != null);
}
