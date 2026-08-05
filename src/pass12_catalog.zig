//! Pass 12 — semantic autonomy catalog (`duo catalog` → `pass12`).
const std = @import("std");
const proof_carrying = @import("proof_carrying.zig");
const pass11_catalog = @import("pass11_catalog.zig");
const semantic_compression = @import("semantic_compression.zig");
const semantic_transaction = @import("semantic_transaction.zig");
const token_semantic = @import("token_semantic.zig");
const wasm_decode_semantic = @import("wasm_decode_semantic.zig");
const wasm_decode_differential = @import("wasm_decode_differential.zig");
const transform_engine = @import("transform_engine.zig");

pub const SCHEMA_VERSION = "pass12-catalog-v0";

pub const Goal = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const goals: []const Goal = &.{
    .{ .id = "A", .title = "Proof-carrying semantic transformations", .status = "partial" },
    .{ .id = "B", .title = "Counterexample-guided semantic synthesis", .status = "open" },
    .{ .id = "C", .title = "Executable bidirectional specifications", .status = "partial" },
    .{ .id = "D", .title = "Semantic development loop for agents", .status = "partial" },
    .{ .id = "E", .title = "Queryable living architecture", .status = "partial" },
    .{ .id = "F", .title = "Semantic compression metrics", .status = "partial" },
    .{ .id = "G", .title = "Self-hosting through same semantic workflow", .status = "partial" },
    .{ .id = "H", .title = "Safe self-improvement via bounded transactions", .status = "open" },
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P12-WS1", .title = "Pass 11 closure + repository truth", .status = "done", .priority = 1, .owner = "pass11_catalog + pass10_repo_audit" },
    .{ .id = "P12-WS2", .title = "Intent + obligation schema", .status = "partial", .priority = 2, .owner = "src/proof_carrying.zig" },
    .{ .id = "P12-WS3", .title = "Transformation proof records", .status = "partial", .priority = 3, .owner = "src/transform_engine.zig" },
    .{ .id = "P12-WS4", .title = "Candidate comparison engine", .status = "partial", .priority = 4, .owner = "src/realization.zig" },
    .{ .id = "P12-WS5", .title = "Test + counterexample integration", .status = "done", .priority = 5, .owner = "src/token_semantic.zig" },
    .{ .id = "P12-WS6", .title = "Semantic projection generation", .status = "done", .priority = 6, .owner = "src/token_semantic.zig" },
    .{ .id = "P12-WS7", .title = "Self-hosted compiler component (M1)", .status = "done", .priority = 7, .owner = "src/token_semantic.zig" },
    .{ .id = "P12-WS8", .title = "End-user MCP transaction loop", .status = "partial", .priority = 8, .owner = "src/semantic_transaction.zig + duo-mcp/duo_bench.duo" },
    .{ .id = "P12-WS9", .title = "LSP semantic presentation", .status = "open", .priority = 9, .owner = "~/x/duo-lsp" },
    .{ .id = "P12-WS10", .title = "Release truth registry", .status = "partial", .priority = 10, .owner = "src/proof_carrying.zig + duo semantic claims + MCP" },
    .{ .id = "P12-WS11", .title = "Workflow compression harness", .status = "partial", .priority = 11, .owner = "src/semantic_compression.zig" },
    .{ .id = "P12-WS12", .title = "Ward transfer proof (M2)", .status = "partial", .priority = 12, .owner = "src/ward_readiness.zig" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    component: []const u8,
};

pub const milestones: []const Milestone = &.{
    .{
        .id = "P12-M1",
        .title = "Descriptor-driven token/lexer component in production path",
        .status = "done",
        .component = "src/token_semantic.zig → lexer + lib/std/token/classify.duo (generated)",
    },
    .{
        .id = "P12-M2",
        .title = "Ward instruction dispatch with proof-carrying selection",
        .status = "partial",
        .component = "src/wasm_decode_semantic.zig + lib/std/wasm/decode.duo + native_barrier_checks.ward_decode_profile",
    },
};

pub const SuccessCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const success_criteria: []const SuccessCriterion = &.{
    .{ .id = 1, .title = "Canonical intent-contract representation", .status = "partial" },
    .{ .id = 2, .title = "Transformations emit structured proof records", .status = "partial" },
    .{ .id = 3, .title = "Deterministic candidate comparison", .status = "partial" },
    .{ .id = 4, .title = "Counterexamples as semantic artifacts", .status = "partial" },
    .{ .id = 5, .title = "One source → multiple validated projections", .status = "done" },
    .{ .id = 6, .title = "Real Duo compiler component in production path", .status = "done" },
    .{ .id = 7, .title = "MCP bounded semantic transaction preview/validate", .status = "partial" },
    .{ .id = 8, .title = "Release claims linked to proof dependencies", .status = "done" },
    .{ .id = 9, .title = "Stale evidence invalidates claims", .status = "partial" },
    .{ .id = 10, .title = "Architecture transfers to Ward subsystem", .status = "partial" },
};

fn countDone(comptime field: []const u8, items: anytype) usize {
    _ = field;
    var n: usize = 0;
    for (items) |item| {
        const status = @field(item, "status");
        if (std.mem.eql(u8, status, "done") or std.mem.eql(u8, status, "met")) n += 1;
    }
    return n;
}

pub fn writePass12Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass12":{{"pass":12,"mission":"Semantic autonomy and proof-carrying AI development","schema":"{s}","plan":"docs/plans/pass12_semantic_autonomy.md","governing_rules":["AI proposes; Duo proves","Reuse existing foundations","Every operation bounded","Claims are semantic objects"],"pass11_prerequisite":"{s}","goals":[
    , .{ SCHEMA_VERSION, pass11_catalog.selected_release_profile.name() });
    for (goals, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{g.id});
        try jsonEscape(w, g.title);
        try w.print("\",\"status\":\"{s}\"}}", .{g.status});
    }
    try w.print("],\"workstreams\":[", .{});
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"owner\":\"", .{ ws.status, ws.priority });
        try jsonEscape(w, ws.owner);
        try w.print("\"}}", .{});
    }
    try w.print("],\"milestones\":[", .{});
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\",\"component\":\"", .{m.status});
        try jsonEscape(w, m.component);
        try w.print("\"}}", .{});
    }
    try w.print("],\"success_criteria\":[", .{});
    for (success_criteria, 0..) |s, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":{d},\"title\":\"", .{s.id});
        try jsonEscape(w, s.title);
        try w.print("\",\"status\":\"{s}\"}}", .{s.status});
    }
    try w.print("],\"proof_carrying\":", .{});
    try proof_carrying.writeSchemaJson(w);
    try w.print(",\"semantic_compression\":", .{});
    try semantic_compression.writeJson(w);
    try w.print(",\"token_semantic\":", .{});
    try token_semantic.writeCatalogJson(w);
    try w.print(",\"transform_proof_log\":", .{});
    try transform_engine.writeProofLogJson(w);
    try w.print(",\"semantic_transaction\":{{\"schema\":\"{s}\",\"max_edits\":{d},\"max_field_bytes\":{d},\"cli\":[\"duo semantic preview [classifier]\",\"duo semantic validate [classifier]\"]}}", .{
        semantic_transaction.SCHEMA_VERSION,
        semantic_transaction.MAX_EDITS,
        semantic_transaction.MAX_FIELD_BYTES,
    });
    try w.print(",\"m1_token_semantic\":", .{});
    try token_semantic.writeCatalogJson(w);
    try w.print(",\"m2_wasm_decode\":", .{});
    try wasm_decode_semantic.writeCatalogJson(w);
    try w.print(",\"wasm_decode_differential\":", .{});
    try wasm_decode_differential.writeCatalogJson(w);
    try w.print(",\"readiness_summary\":{{\"goals_done\":{d},\"workstreams_done\":{d},\"milestones_done\":{d},\"success_met\":{d},\"success_total\":{d}", .{
        countDone("status", goals),
        countDone("status", workstreams),
        countDone("status", milestones),
        countDone("status", success_criteria),
        success_criteria.len,
    });
    try w.writeAll("}}");
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '\\', '"' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "pass12_catalog: writePass12Json structure" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePass12Json(&buf.writer);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P12-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "m2_wasm_decode") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "wasm_decode_differential") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "proof_carrying") != null);
}
