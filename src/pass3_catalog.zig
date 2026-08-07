/// Pass 3 — directive surface, grammar, and convergence catalog export.
///
/// Machine-readable JSON for agents, MCP, and `duo catalog`.
const std = @import("std");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const pass1_catalog = @import("pass1_catalog.zig");
const pass4_catalog = @import("pass4_catalog.zig");
const pass5_catalog = @import("pass5_catalog.zig");
const pass6_catalog = @import("pass6_catalog.zig");
const pass7_catalog = @import("pass7_catalog.zig");
const pass8_catalog = @import("pass8_catalog.zig");
const pass9_catalog = @import("pass9_catalog.zig");
const pass10_catalog = @import("pass10_catalog.zig");
const pass11_catalog = @import("pass11_catalog.zig");
const pass12_catalog = @import("pass12_catalog.zig");
const pass13_catalog = @import("pass13_catalog.zig");
const pass14_catalog = @import("pass14_catalog.zig");
const pass15_catalog = @import("pass15_catalog.zig");
const pass16_catalog = @import("pass16_catalog.zig");
const pass20_catalog = @import("pass20_catalog.zig");
const pass21_catalog = @import("pass21_catalog.zig");
const pass22_catalog = @import("pass22_catalog.zig");
const pass23_catalog = @import("pass23_catalog.zig");
const pass24_catalog = @import("pass24_catalog.zig");
const pass25_catalog = @import("pass25_catalog.zig");
const pass26_catalog = @import("pass26_catalog.zig");
const pass27_catalog = @import("pass27_catalog.zig");
const pass34_catalog = @import("pass34_catalog.zig");
const pass36_catalog = @import("pass36_catalog.zig");
const foundation_catalog = @import("foundation_catalog.zig");
const pass19_catalog = @import("pass19_catalog.zig");
const passes_audit = @import("passes_audit.zig");

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass3_directive_grammar_convergence.md";
    pub const keywords = "docs/catalogs/keywords.md";
    pub const directives = "docs/catalogs/directives.md";
    pub const grammar = "docs/catalogs/grammar_compactness.md";
    pub const convergence = "docs/catalogs/convergence.md";
    pub const performance = "docs/catalogs/performance_barriers.md";
    pub const pass2 = "docs/plans/pass2_foundational_convergence.md";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

/// Ranked Pass 3 workstreams (mirrors plan doc §B).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P3-01", .title = "Keyword + directive + grammar catalogs", .status = "done", .priority = 1 },
    .{ .id = "P3-02", .title = "Formatter --canonical mode", .status = "done", .priority = 2 },
    .{ .id = "P3-03", .title = "@{} descriptor grammar", .status = "done", .priority = 3 },
    .{ .id = "P3-04", .title = "Field projections .name", .status = "done", .priority = 4 },
    .{ .id = "P3-05", .title = "Table spread ..expr", .status = "done", .priority = 5 },
    .{ .id = "P3-06", .title = "Direct iteration protocol", .status = "done", .priority = 6 },
    .{ .id = "P3-07", .title = "Per-call knowledge lattice in codegen", .status = "partial", .priority = 7 },
    .{ .id = "P3-08", .title = "Deprecate flat directive aliases", .status = "done", .priority = 8 },
    .{ .id = "P3-09", .title = "Pipeline transform registration", .status = "done", .priority = 9 },
    .{ .id = "P3-10", .title = "Method references :name", .status = "done", .priority = 10 },
    .{ .id = "P3-11", .title = "Named destructuring", .status = "done", .priority = 11 },
    .{ .id = "P3-12", .title = "Binding conditions", .status = "done", .priority = 12 },
    .{ .id = "P3-13", .title = "Wire or remove unwired directives", .status = "done", .priority = 13 },
    .{ .id = "P3-14", .title = "Selective import destructuring", .status = "done", .priority = 14 },
    .{ .id = "P3-15", .title = "@export visibility", .status = "done", .priority = 15 },
};

/// Non-canonical symbolic operators: implemented for compat; parser warns in .duo mode.
pub const deprioritized_operators = [_][]const u8{
    "|>",
    "infix @ (matmul)",
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        }
    }
}

fn countRegisteredPipelineOps() usize {
    var n: usize = 0;
    inline for (@typeInfo(semantic_algebra.PipelineOp).@"enum".field_values) |value| {
        const op: semantic_algebra.PipelineOp = @enumFromInt(value);
        const id = semantic_algebra.pipelineTransformId(op);
        if (transform_engine.isRegisteredTransform(id)) n += 1;
    }
    return n;
}

fn countRegisteredCallTransforms() usize {
    var n: usize = 0;
    inline for (@typeInfo(semantic_algebra.CallTransform).@"enum".field_values) |value| {
        const op: semantic_algebra.CallTransform = @enumFromInt(value);
        const id = semantic_algebra.callTransformId(op);
        if (transform_engine.isRegisteredTransform(id)) n += 1;
    }
    return n;
}

fn countRegisteredShapeOps() usize {
    var n: usize = 0;
    inline for (@typeInfo(semantic_algebra.ShapeOp).@"enum".field_values) |value| {
        const op: semantic_algebra.ShapeOp = @enumFromInt(value);
        const id = semantic_algebra.shapeTransformId(op);
        if (transform_engine.isRegisteredTransform(id)) n += 1;
    }
    return n;
}

/// Emit Pass 3 tracking JSON (catalog paths, workstreams, transform registry summary).
pub fn writePass3Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print(
        \\{{"pass":3,"mission":"directive surface + grammar minimalism + convergence","catalogs":{{
    , .{});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"keywords\":\"", .{});
    try jsonEscape(w, CatalogPaths.keywords);
    try w.print("\",\"directives\":\"", .{});
    try jsonEscape(w, CatalogPaths.directives);
    try w.print("\",\"grammar\":\"", .{});
    try jsonEscape(w, CatalogPaths.grammar);
    try w.print("\",\"convergence\":\"", .{});
    try jsonEscape(w, CatalogPaths.convergence);
    try w.print("\",\"performance\":\"", .{});
    try jsonEscape(w, CatalogPaths.performance);
    try w.print("\"}},\"keyword_target\":{{\"current\":53,\"canonical_target\":30}},\"grammar_forms\":{{\"accepted\":14,\"proposed\":20,\"rejected\":10}},\"transform_registry\":{{", .{});

    const pipeline_total = @typeInfo(semantic_algebra.PipelineOp).@"enum".field_names.len;
    const call_total = @typeInfo(semantic_algebra.CallTransform).@"enum".field_names.len;
    const shape_total = @typeInfo(semantic_algebra.ShapeOp).@"enum".field_names.len;
    try w.print(
        "\"pipeline_ops\":{{\"registered\":{d},\"total\":{d}}},",
        .{ countRegisteredPipelineOps(), pipeline_total },
    );
    try w.print(
        "\"call_transforms\":{{\"registered\":{d},\"total\":{d}}},",
        .{ countRegisteredCallTransforms(), call_total },
    );
    try w.print(
        "\"shape_ops\":{{\"registered\":{d},\"total\":{d}}},",
        .{ countRegisteredShapeOps(), shape_total },
    );
    try w.print("\"tier1_combinators\":{d}", .{transform_engine.parity_tier1.len});
    try w.print("}},\"workstreams\":[\n", .{});

    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"",
            .{ws.id},
        );
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d}}}", .{ ws.status, ws.priority });
    }
    try w.print("\n],\"deprioritized_operators\":[", .{});
    for (deprioritized_operators, 0..) |op, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"", .{});
        try jsonEscape(w, op);
        try w.print("\"", .{});
    }
    try w.print("],\"directive_tiers\":[\"top_level\",\"short_alias\",\"namespaced\"],", .{});
    try pass1_catalog.writePass1Json(w);
    try w.print(",", .{});
    try pass4_catalog.writePass4Json(w);
    try w.print(",", .{});
    try pass5_catalog.writePass5Json(w);
    try w.print(",", .{});
    try pass6_catalog.writePass6Json(w);
    try w.print(",", .{});
    try pass7_catalog.writePass7Json(w);
    try w.print(",", .{});
    try pass8_catalog.writePass8Json(w);
    try w.print(",", .{});
    try pass9_catalog.writePass9Json(w);
    try w.print(",", .{});
    try pass10_catalog.writePass10Json(w);
    try w.print(",", .{});
    try pass11_catalog.writePass11Json(w);
    try w.print(",", .{});
    try pass12_catalog.writePass12Json(w);
    try w.print(",", .{});
    try pass13_catalog.writePass13Json(w, alloc);
    try w.print(",", .{});
    try pass14_catalog.writePass14Json(w, alloc);
    try w.print(",", .{});
    try pass15_catalog.writePass15Json(w, alloc);
    try w.print(",", .{});
    try pass16_catalog.writePass16Json(w, alloc);
    try w.print(",", .{});
    try pass20_catalog.writePass20Json(w, alloc);
    try w.print(",", .{});
    try pass21_catalog.writePass21Json(w, alloc);
    try w.print(",", .{});
    try pass22_catalog.writePass22Json(w, alloc);
    try w.print(",", .{});
    try pass19_catalog.writePass19Json(w, alloc);
    try w.print(",", .{});
    try pass23_catalog.writePass23Json(w, alloc);
    try w.print(",", .{});
    try pass24_catalog.writePass24Json(w, alloc);
    try w.print(",", .{});
    try pass25_catalog.writePass25Json(w, alloc);
    try w.print(",", .{});
    try pass26_catalog.writePass26Json(w, alloc);
    try w.print(",", .{});
    try pass27_catalog.writePass27Json(w, alloc);
    try w.print(",", .{});
    try pass34_catalog.writePass34Json(w, alloc);
    try w.print(",", .{});
    try pass36_catalog.writePass36Json(w, alloc);
    try w.print(",", .{});
    try foundation_catalog.writeFoundationJson(w, alloc);
    try w.print(",", .{});
    try passes_audit.writePassesAuditEmbedJson(w, alloc);
    try w.print("}}\n", .{});
}

/// CLI entry: `duo catalog` (Pass 3 machine-readable tracking JSON).
pub fn writeCatalogJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try writePass3Json(w, alloc);
}

test "pass3_catalog: writePass3Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass3Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"workstreams\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pipeline_ops\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"deprioritized_operators\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass5\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass6\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass9\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass10\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass11\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass12\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass13\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass14\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass15\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass16\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass20\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass21\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass22\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass23\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass24\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass26\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass27\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass36\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"foundation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass19\"") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const root = parsed.value.object;
    try std.testing.expect(root.get("pass11") != null);
    try std.testing.expect(root.get("pass12") != null);
    try std.testing.expect(root.get("pass13") != null);
    try std.testing.expect(root.get("pass14") != null);
}

test "pass3_catalog: all pipeline ops registered in transform engine" {
    inline for (@typeInfo(semantic_algebra.PipelineOp).@"enum".field_values) |value| {
        const op: semantic_algebra.PipelineOp = @enumFromInt(value);
        const id = semantic_algebra.pipelineTransformId(op);
        try std.testing.expect(transform_engine.isRegisteredTransform(id));
    }
}
