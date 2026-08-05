//! Pass 16 §22.4 — dynamic boundary report for the host compiler artifact.
const std = @import("std");
const pass4_catalog = @import("pass4_catalog.zig");

pub const SCHEMA_VERSION = "compiler-dynamic-boundary-v0";

pub const BoundaryMetric = struct {
    id: []const u8,
    title: []const u8,
    count: usize,
    source: []const u8,
    notes: []const u8,
};

/// Seed metrics from codegen scan + honest host-compiler classification.
pub const metrics: []const BoundaryMetric = &.{
    .{
        .id = "DB-01",
        .title = "lua_Value references in codegen",
        .count = pass4_catalog.boxed_inventory.lua_value_refs,
        .source = "src/codegen.zig scan",
        .notes = "Dynamic/t fallback paths; typed paths must avoid boxing",
    },
    .{
        .id = "DB-02",
        .title = "lua_invoke references in codegen",
        .count = pass4_catalog.boxed_inventory.lua_invoke_refs,
        .source = "src/codegen.zig scan",
        .notes = "Dynamic dispatch; not acceptable on specialized native paths",
    },
    .{
        .id = "DB-03",
        .title = "emit_as_lua_value references",
        .count = pass4_catalog.boxed_inventory.emit_as_lua_value_refs,
        .source = "src/codegen.zig scan",
        .notes = "Explicit boxing emission sites",
    },
    .{
        .id = "DB-04",
        .title = "moduleNeedsLuaRuntime references",
        .count = pass4_catalog.boxed_inventory.module_needs_lua_runtime_refs,
        .source = "src/codegen.zig scan",
        .notes = "Modules requiring full dynamic runtime linkage",
    },
    .{
        .id = "DB-05",
        .title = "Host compiler implementation language",
        .count = 1,
        .source = "src/*.zig",
        .notes = "Production compiler is Zig-hosted until S2; not a Duo dynamic boundary",
    },
    .{
        .id = "DB-06",
        .title = "Generated C canonical path",
        .count = 1,
        .source = "default --backend=c",
        .notes = "Explicit bootstrap backend today; must not be silent after self-host",
    },
};

pub fn writeReportJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"primary_file\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, pass4_catalog.boxed_inventory.primary_file);
    try w.writeAll("\",\"metrics\":[");
    for (metrics, 0..) |m, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"count\":{d},\"source\":\"{s}\",\"notes\":\"{s}\"}}",
            .{ m.id, m.title, m.count, m.source, m.notes },
        );
    }
    try w.writeAll("]}");
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        }
    }
}

test "compiler_dynamic_boundary: metrics present" {
    try std.testing.expect(metrics.len >= 4);
}
