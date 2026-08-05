/// Pass 7 — AI-native compilation, optimization intelligence, agent semantic API catalog.
const std = @import("std");
const pass6_catalog = @import("pass6_catalog.zig");
const contract_model = @import("contract_model.zig");
const assumption_guard = @import("assumption_guard.zig");

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass7_ai_native_compilation.md";
    pub const pass6 = pass6_catalog.CatalogPaths.plan;
    pub const semantic_universe = "docs/semantic_universe.md";
    pub const agent_alignment = "docs/AGENT_ALIGNMENT.md";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    area: []const u8,
};

/// Pass 7 bounded workstreams (one agent claims one seam).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P7-01", .title = "Repository audit + readiness maps", .status = "partial", .priority = 1, .area = "audit" },
    .{ .id = "P7-02", .title = "Contract hardness model + catalog", .status = "partial", .priority = 2, .area = "contracts" },
    .{ .id = "P7-03", .title = "Knowledge snapshot API", .status = "partial", .priority = 3, .area = "snapshots" },
    .{ .id = "P7-04", .title = "Assumption and guard objects", .status = "partial", .priority = 4, .area = "guards" },
    .{ .id = "P7-05", .title = "Optimization outcome records", .status = "partial", .priority = 5, .area = "outcomes" },
    .{ .id = "P7-06", .title = "@comp.why expansion + repair candidates", .status = "partial", .priority = 6, .area = "explain" },
    .{ .id = "P7-07", .title = "Semantic fingerprinting", .status = "partial", .priority = 7, .area = "cache" },
    .{ .id = "P7-08", .title = "Generated-code canonicalization", .status = "open", .priority = 8, .area = "normalize" },
    .{ .id = "P7-09", .title = "Duplicate semantic structure detection", .status = "open", .priority = 9, .area = "dedupe" },
    .{ .id = "P7-10", .title = "Semantic transactions + diff", .status = "open", .priority = 10, .area = "tx" },
    .{ .id = "P7-11", .title = "MCP knowledge queries", .status = "open", .priority = 11, .area = "mcp" },
    .{ .id = "P7-12", .title = "LSP optimization explanation", .status = "open", .priority = 12, .area = "lsp" },
    .{ .id = "P7-13", .title = "Tensor descriptor foundation", .status = "partial", .priority = 13, .area = "ai" },
    .{ .id = "P7-14", .title = "Model graph SIM schema", .status = "open", .priority = 14, .area = "ai" },
    .{ .id = "P7-15", .title = "Generated-code provenance", .status = "open", .priority = 15, .area = "provenance" },
};

/// Extended workstreams from Pass 7 spec (P7-16…P7-35); claim after core P7-01…P7-15 land.
pub const extended_workstreams: []const Workstream = &.{
    .{ .id = "P7-16", .title = "Optimization evidence store", .status = "open", .priority = 16, .area = "evidence" },
    .{ .id = "P7-17", .title = "Profile-guided call-shape specialization", .status = "open", .priority = 17, .area = "pgo" },
    .{ .id = "P7-18", .title = "Multi-version budget infrastructure", .status = "open", .priority = 18, .area = "pgo" },
    .{ .id = "P7-19", .title = "Tensor representation selection", .status = "open", .priority = 19, .area = "ai" },
    .{ .id = "P7-20", .title = "Static tensor-shape specialization", .status = "open", .priority = 20, .area = "ai" },
    .{ .id = "P7-21", .title = "Bounded ONNX or equivalent importer spike", .status = "open", .priority = 21, .area = "ai" },
    .{ .id = "P7-22", .title = "Operator transformation registry seam", .status = "open", .priority = 22, .area = "ai" },
    .{ .id = "P7-23", .title = "Tensor memory-lifetime analysis", .status = "open", .priority = 23, .area = "ai" },
    .{ .id = "P7-24", .title = "CPU kernel lowering", .status = "open", .priority = 24, .area = "ai" },
    .{ .id = "P7-25", .title = "SIMD tensor kernel prototype", .status = "open", .priority = 25, .area = "ai" },
    .{ .id = "P7-26", .title = "Numerical precision contracts", .status = "open", .priority = 26, .area = "ai" },
    .{ .id = "P7-27", .title = "Foreign AI runtime direct-call descriptors", .status = "open", .priority = 27, .area = "ai" },
    .{ .id = "P7-28", .title = "AI-generated transformation validation harness", .status = "open", .priority = 28, .area = "validation" },
    .{ .id = "P7-29", .title = "Agent-generated regression-test workflow", .status = "open", .priority = 29, .area = "validation" },
    .{ .id = "P7-30", .title = "Compiler-capable agent-runtime proof workload", .status = "open", .priority = 30, .area = "agent" },
    .{ .id = "P7-31", .title = "Ward semantic optimization queries", .status = "open", .priority = 31, .area = "agent" },
    .{ .id = "P7-32", .title = "Cross-language kernel specialization proof", .status = "open", .priority = 32, .area = "foreign" },
    .{ .id = "P7-33", .title = "Generated-code canonicalization", .status = "open", .priority = 33, .area = "normalize" },
    .{ .id = "P7-34", .title = "Duplicate semantic structure detection", .status = "open", .priority = 34, .area = "dedupe" },
    .{ .id = "P7-35", .title = "Semantic diff performance fields", .status = "open", .priority = 35, .area = "tx" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const milestones: []const Milestone = &.{
    .{ .id = "P7-M1", .title = "Structured optimization explanation", .status = "partial" },
    .{ .id = "P7-M2", .title = "Enforceable performance contract (noalloc)", .status = "partial" },
    .{ .id = "P7-M3", .title = "Semantic agent edit via MCP", .status = "open" },
    .{ .id = "P7-M4", .title = "Static tensor kernel", .status = "open" },
    .{ .id = "P7-M5", .title = "Imported inference operator", .status = "open" },
};

pub const Readiness = struct {
    area: []const u8,
    status: []const u8,
    owner: []const u8,
};

/// Repo-truth readiness (updated as foundations land).
pub const ai_target_readiness: []const Readiness = &.{
    .{ .area = "canonical_generation", .status = "partial", .owner = "parser + fmt --canonical" },
    .{ .area = "semantic_queries", .status = "partial", .owner = "duo sim + duo explain + MCP" },
    .{ .area = "transactions", .status = "open", .owner = "semantic_graph (planned tx)" },
    .{ .area = "provenance", .status = "partial", .owner = "transform_engine provenance log" },
    .{ .area = "contracts", .status = "partial", .owner = "contract_model.zig" },
    .{ .area = "repair_operations", .status = "partial", .owner = "repair_candidate.zig" },
    .{ .area = "validation", .status = "partial", .owner = "zig build test + pass5/6 harness" },
};

pub const optimization_intelligence: []const Readiness = &.{
    .{ .area = "snapshots", .status = "partial", .owner = "knowledge_snapshot.zig" },
    .{ .area = "assumptions", .status = "partial", .owner = "assumption_guard.zig" },
    .{ .area = "guards", .status = "partial", .owner = "assumption_guard.zig" },
    .{ .area = "outcomes", .status = "partial", .owner = "optimization_outcome.zig" },
    .{ .area = "explanations", .status = "partial", .owner = "@comp.why.* + duo explain" },
    .{ .area = "measurements", .status = "partial", .owner = "zig build bench" },
    .{ .area = "profiles", .status = "open", .owner = "PGO flags only" },
};

pub const ai_workload: []const Readiness = &.{
    .{ .area = "tensor_descriptors", .status = "partial", .owner = "types.Tensor + sema tensor ops" },
    .{ .area = "static_shapes", .status = "partial", .owner = "sema tensor matmul/add" },
    .{ .area = "dataflow_graphs", .status = "partial", .owner = "semantic_graph pipeline lift" },
    .{ .area = "kernels", .status = "open", .owner = "native_backend + @comp.device" },
    .{ .area = "memory_planning", .status = "open", .owner = "arc + escape (partial)" },
    .{ .area = "precision", .status = "open", .owner = "contract_model (planned)" },
    .{ .area = "target_lowering", .status = "partial", .owner = "codegen + native_backend" },
    .{ .area = "model_import", .status = "partial", .owner = "sim + c_sim_import (Pass 5)" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

fn writeReadinessArray(w: *std.Io.Writer, label: []const u8, rows: []const Readiness) !void {
    try w.print(",\"{s}\":[", .{label});
    for (rows, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"area\":\"", .{});
        try jsonEscape(w, row.area);
        try w.print("\",\"status\":\"{s}\",\"owner\":\"", .{row.status});
        try jsonEscape(w, row.owner);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

fn writeWorkstreamArray(w: *std.Io.Writer, label: []const u8, rows: []const Workstream) !void {
    try w.print(",\"{s}\":[", .{label});
    for (rows, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"area\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.area,
        });
    }
    try w.print("]", .{});
}

pub fn writePass7Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass7":{{"mission":"AI-native compilation + optimization intelligence + agent semantic API","schema":"pass7-catalog-v0","catalogs":{{
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

    try w.print("],\"workstream_count\":{d}", .{workstreams.len});
    try writeWorkstreamArray(w, "extended_workstreams", extended_workstreams);

    try w.print(",\"milestones\":[", .{});
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\"}}", .{m.status});
    }
    try w.print("]", .{});

    try writeReadinessArray(w, "ai_target_readiness", ai_target_readiness);
    try writeReadinessArray(w, "optimization_intelligence", optimization_intelligence);
    try writeReadinessArray(w, "ai_workload", ai_workload);

    try w.print(",\"contracts\":", .{});
    try contract_model.writeCatalogJson(w);

    try w.print(",\"assumptions\":", .{});
    try assumption_guard.writeCatalogJson(w);

    const repair_candidate = @import("repair_candidate.zig");
    try w.print(",\"repair_patterns\":", .{});
    try repair_candidate.writeCatalogJson(w);

    try w.print(
        ",\"invariants\":[\"compiler-verifies-ai-proposes\",\"one-semantic-model\",\"sim-agent-boundary\",\"no-second-graph\",\"heuristic-not-proof\",\"measured-not-estimated\"]}}",
        .{},
    );
}

test "pass7_catalog: writePass7Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass7Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P7-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "knowledge_snapshot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "contract.pure") != null);
    // Milestones array must close before readiness arrays (regression: missing ']')
    const ms = std.mem.indexOf(u8, out, "\"milestones\":[") orelse return error.TestExpectedEqual;
    const ai = std.mem.indexOf(u8, out, "\"ai_target_readiness\":[") orelse return error.TestExpectedEqual;
    try std.testing.expect(ms < ai);
    const between = out[ms..ai];
    var depth: i32 = 0;
    for (between) |c| switch (c) {
        '[' => depth += 1,
        ']' => depth -= 1,
        else => {},
    };
    try std.testing.expectEqual(@as(i32, 0), depth);
}
