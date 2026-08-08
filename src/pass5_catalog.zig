/// Pass 5 — semantic interchange, cross-language metaprogramming, ecosystem execution catalog.
const std = @import("std");
const sim = @import("sim.zig");

pub const CatalogPaths = struct {
    pub const plan = "docs/archive/pass5_semantic_interchange.md";
    pub const pass4 = "docs/archive/pass4_native_end_to_end.md";
    pub const semantic_universe = "docs/semantic_universe.md";
    pub const milestone_c = "examples/pass5/fixtures/point.h";
    pub const milestone_duo = "examples/pass4_native_milestone.duo";
    pub const sim_module = "src/sim.zig";
    pub const c_frontend_module = "src/c_frontend.zig";
    pub const c_sim_import_module = "src/c_sim_import.zig";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    layer: []const u8,
};

/// Pass 5 workstreams (mirrors plan §11 execution phases).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P5-00", .title = "Repository truth audit (Phase 0)", .status = "done", .priority = 1, .layer = "audit" },
    .{ .id = "P5-01", .title = "SIM v0 schema + serializer", .status = "partial", .priority = 2, .layer = "A" },
    .{ .id = "P5-02", .title = "Native Duo snapshot export", .status = "partial", .priority = 3, .layer = "A" },
    .{ .id = "P5-03", .title = "C declaration frontend adapter", .status = "partial", .priority = 4, .layer = "B" },
    .{ .id = "P5-04", .title = "C-to-SIM semantic importer", .status = "partial", .priority = 5, .layer = "B" },
    .{ .id = "P5-05", .title = "Foreign descriptor adaptation", .status = "partial", .priority = 6, .layer = "C" },
    .{ .id = "P5-06", .title = "Direct native ABI call (imported fn)", .status = "done", .priority = 7, .layer = "D" },
    .{ .id = "P5-07", .title = "abi.specialize shared transformation", .status = "done", .priority = 8, .layer = "C" },
    .{ .id = "P5-08", .title = "MCP semantic snapshot tools", .status = "partial", .priority = 9, .layer = "tooling" },
    .{ .id = "P5-09", .title = "LSP foreign descriptor hover/navigation", .status = "partial", .priority = 10, .layer = "tooling" },
    .{ .id = "P5-10", .title = "End-to-end C point.h milestone", .status = "done", .priority = 11, .layer = "integration" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    sim_export: []const u8,
    c_import: []const u8,
    direct_call: []const u8,
    abi_transform: []const u8,
};

pub const first_milestone = Milestone{
    .id = "P5-M1",
    .title = "C header → SIM → foreign descriptor → direct distance2 call",
    .sim_export = "partial",
    .c_import = "partial",
    .direct_call = "done",
    .abi_transform = "done",
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

/// Emit Pass 5 JSON fragment (embedded in `duo catalog` root object).
pub fn writePass5Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass5":{{"mission":"semantic interchange + cross-language metaprogramming","schema":"{s}","catalogs":{{
    , .{sim.SCHEMA_VERSION});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"sim_module\":\"", .{});
    try jsonEscape(w, CatalogPaths.sim_module);
    try w.print("\",\"milestone_c\":\"", .{});
    try jsonEscape(w, CatalogPaths.milestone_c);
    try w.print("\",\"milestone_duo\":\"", .{});
    try jsonEscape(w, CatalogPaths.milestone_duo);
    try w.print("\"}},\"harness_components\":[\"frontend_adapter\",\"semantic_importer\",\"semantic_adapter\",\"transformation_engine\",\"validation_engine\",\"emitter_or_native_bridge\"],\"first_foreign_target\":\"c-declarations\",\"first_transform\":\"abi.specialize\",\"milestone\":{{\"id\":\"{s}\",\"title\":\"",
        .{first_milestone.id},
    );
    try jsonEscape(w, first_milestone.title);
    try w.print("\",\"sim_export\":\"{s}\",\"c_import\":\"{s}\",\"direct_call\":\"{s}\",\"abi_transform\":\"{s}\"}},\"workstreams\":[",
        .{
            first_milestone.sim_export,
            first_milestone.c_import,
            first_milestone.direct_call,
            first_milestone.abi_transform,
        },
    );

    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"",
            .{ws.id},
        );
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"layer\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.layer,
        });
    }
    try w.print(
        "],\"layers\":{{\"A\":\"semantic_interchange\",\"B\":\"foreign_interface_import\",\"C\":\"cross_language_transform\",\"D\":\"foreign_implementation_import\",\"E\":\"semantic_re_emission\"}},\"invariants\":[\"SIM-not-internal-graph\",\"dependency-direction-down\",\"explicit-uncertainty\",\"no-importer-schema-forks\"]}}",
        .{},
    );
}

test "pass5_catalog: writePass5Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass5Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass5\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P5-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "sim-v0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "abi.specialize") != null);
}
