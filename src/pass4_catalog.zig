/// Pass 4 — native end-to-end compilation, runtime independence, self-hosting catalog.
const std = @import("std");

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass4_native_end_to_end.md";
    pub const performance = "docs/catalogs/performance_barriers.md";
    pub const bootstrap = "docs/catalogs/bootstrap_dependencies.md";
    pub const milestone = "examples/pass4_native_milestone.duo";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P4-01", .title = "Native-path audit + barrier catalog", .status = "partial", .priority = 1 },
    .{ .id = "P4-02", .title = "Semantic value model foundation", .status = "open", .priority = 2 },
    .{ .id = "P4-03", .title = "Explicit box/unbox IR boundaries", .status = "partial", .priority = 3 },
    .{ .id = "P4-04", .title = "Native table + field-offset lowering", .status = "partial", .priority = 4 },
    .{ .id = "P4-05", .title = "Native call ABI foundation", .status = "partial", .priority = 5 },
    .{ .id = "P4-06", .title = "Return-pack native dataflow", .status = "open", .priority = 6 },
    .{ .id = "P4-07", .title = "Backend-independent low-level IR", .status = "open", .priority = 7 },
    .{ .id = "P4-08", .title = "Direct scalar backend (native_backend.zig)", .status = "partial", .priority = 8 },
    .{ .id = "P4-09", .title = "Modular runtime + pay-for-use linking", .status = "partial", .priority = 9 },
    .{ .id = "P4-10", .title = "Compiler explanation (@comp.why.*)", .status = "partial", .priority = 10 },
    .{ .id = "P4-11", .title = "Dependency + bootstrap catalog", .status = "partial", .priority = 11 },
    .{ .id = "P4-12", .title = "Compiler-capable Duo profile", .status = "open", .priority = 12 },
    .{ .id = "P4-13", .title = "Bootstrappable core library", .status = "open", .priority = 13 },
    .{ .id = "P4-14", .title = "First compiler component in Duo", .status = "open", .priority = 14 },
    .{ .id = "P4-15", .title = "Multi-generation bootstrap harness", .status = "open", .priority = 15 },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    c_backend: []const u8,
    direct_backend: []const u8,
};

pub const first_milestone = Milestone{
    .id = "P4-M1",
    .title = "Sealed Point distance2 native lowering",
    .c_backend = "pass",
    .direct_backend = "pass",
};

/// Catalog counts for P4-01 — update when `pass4_boxed_inventory` test fails.
pub const boxed_inventory = struct {
    pub const lua_value_refs: usize = 1887;
    pub const lua_invoke_refs: usize = 67;
    pub const emit_as_lua_value_refs: usize = 178;
    pub const module_needs_lua_runtime_refs: usize = 21;
    pub const primary_file: []const u8 = "src/codegen.zig";
};

pub const BootstrapDep = struct {
    id: []const u8,
    name: []const u8,
    classification: []const u8,
    stage: []const u8,
};

pub const bootstrap_dependencies: []const BootstrapDep = &.{
    .{ .id = "BD-001", .name = "Zig", .classification = "bootstrap", .stage = "0" },
    .{ .id = "BD-002", .name = "clang", .classification = "bootstrap", .stage = "0" },
    .{ .id = "BD-003", .name = "generated C", .classification = "bootstrap_backend", .stage = "6" },
    .{ .id = "BD-004", .name = "duo_runtime preamble", .classification = "runtime", .stage = "7" },
    .{ .id = "BD-005", .name = "Mach-O linker", .classification = "bootstrap", .stage = "6" },
    .{ .id = "BD-006", .name = "native_backend.zig", .classification = "direct_backend", .stage = "6" },
};

pub const PipelineStage = struct {
    name: []const u8,
    file: []const u8,
    status: []const u8,
};

pub const pipeline_stages: []const PipelineStage = &.{
    .{ .name = "lexer", .file = "src/lexer.zig", .status = "done" },
    .{ .name = "parser", .file = "src/parser.zig", .status = "done" },
    .{ .name = "sema", .file = "src/sema.zig", .status = "done" },
    .{ .name = "semantic_graph", .file = "src/semantic_graph.zig", .status = "partial" },
    .{ .name = "codegen_c", .file = "src/codegen.zig", .status = "bootstrap" },
    .{ .name = "native_backend", .file = "src/native_backend.zig", .status = "partial" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        }
    }
}

/// Emit Pass 4 JSON fragment (embedded in `duo catalog` root object).
pub fn writePass4Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass4":{{"pass":4,"mission":"native end-to-end + runtime independence + self-hosting","catalogs":{{
    , .{});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"performance\":\"", .{});
    try jsonEscape(w, CatalogPaths.performance);
    try w.print("\",\"bootstrap\":\"", .{});
    try jsonEscape(w, CatalogPaths.bootstrap);
    try w.print("\",\"milestone\":\"", .{});
    try jsonEscape(w, CatalogPaths.milestone);
    try w.print("\"}},\"self_hosting_stage\":0,\"first_milestone\":{{\"id\":\"{s}\",\"title\":\"", .{first_milestone.id});
    try jsonEscape(w, first_milestone.title);
    try w.print("\",\"c_backend\":\"{s}\",\"direct_backend\":\"{s}\"}},\"pipeline_stages\":[", .{
        first_milestone.c_backend,
        first_milestone.direct_backend,
    });

    for (pipeline_stages, 0..) |ps, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"name\":\"{s}\",\"file\":\"", .{ps.name});
        try jsonEscape(w, ps.file);
        try w.print("\",\"status\":\"{s}\"}}", .{ps.status});
    }

    try w.print("],\"workstreams\":[", .{});
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d}}}", .{ ws.status, ws.priority });
    }

    try w.print("],\"bootstrap_dependencies\":[", .{});
    for (bootstrap_dependencies, 0..) |dep, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"name\":\"{s}\",\"classification\":\"{s}\",\"replacement_stage\":\"{s}\"}}",
            .{ dep.id, dep.name, dep.classification, dep.stage },
        );
    }
    try w.print("],\"boxed_inventory\":{{\"file\":\"", .{});
    try jsonEscape(w, boxed_inventory.primary_file);
    try w.print("\",\"lua_value_refs\":{d},\"lua_invoke_refs\":{d},\"emit_as_lua_value_refs\":{d},\"module_needs_lua_runtime_refs\":{d}}},\"invariants\":[\"P4-01\",\"P4-02\",\"P4-03\",\"P4-04\",\"P4-05\",\"P4-06\",\"P4-07\",\"P4-08\",\"P4-09\"]}}",
        .{
            boxed_inventory.lua_value_refs,
            boxed_inventory.lua_invoke_refs,
            boxed_inventory.emit_as_lua_value_refs,
            boxed_inventory.module_needs_lua_runtime_refs,
        },
    );
}

test "pass4_catalog: writePass4Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass4Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P4-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "native_backend.zig") != null);
}
