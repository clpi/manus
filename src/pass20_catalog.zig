//! Pass 20 — universal cross-language metaprogramming harness catalog.
const std = @import("std");
const pass20_import_strength = @import("pass20_import_strength.zig");

pub const SCHEMA_VERSION = "pass20-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass20_universal_metaprogramming_harness.md";
pub const FOUNDATION_PASS = "docs/archive/pass5_semantic_interchange.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 20 harness workstreams (builds on Pass 5 SIM + foreign import).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P20-WS0", .title = "Repository truth + adoption ladder mapping", .status = "partial", .priority = 0, .owner = "src/pass20_catalog.zig + Pass 5 audit" },
    .{ .id = "P20-WS1", .title = "Universal meta object model (SIM extension)", .status = "partial", .priority = 1, .owner = "src/sim.zig" },
    .{ .id = "P20-WS2", .title = "C/C++ harness (header import → staged values)", .status = "partial", .priority = 2, .owner = "src/c_sim_import.zig + src/foreign_adapter.zig" },
    .{ .id = "P20-WS3", .title = "Rust/Zig/Go frontends", .status = "open", .priority = 3, .owner = "future" },
    .{ .id = "P20-WS4", .title = "TypeScript/Python/JS frontends", .status = "open", .priority = 4, .owner = "future" },
    .{ .id = "P20-WS5", .title = "Semantic patches + multi-target emit", .status = "open", .priority = 5, .owner = "future" },
    .{ .id = "P20-WS6", .title = "Portable metaprograms (capability-gated)", .status = "open", .priority = 6, .owner = "lib/std/meta/*" },
    .{ .id = "P20-WS7", .title = "Ready-to-use tools (§12 binding/ABI/schema/test/doc)", .status = "open", .priority = 7, .owner = "future CLI meta/*" },
    .{ .id = "P20-WS8", .title = "CLI + shell meta commands", .status = "open", .priority = 8, .owner = "src/main.zig" },
    .{ .id = "P20-WS9", .title = "LSP + MCP harness parity", .status = "partial", .priority = 9, .owner = "~/x/duo-lsp + ~/x/duo-mcp" },
    .{ .id = "P20-WS10", .title = "First release demo (non-Duo project leverage)", .status = "partial", .priority = 10, .owner = "examples/pass5/*" },
    .{ .id = "P20-WS11", .title = "Cross-language realization selection", .status = "open", .priority = 11, .owner = "src/realization.zig" },
};

pub const AdoptionLevel = struct {
    level: u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 20 §18 adoption ladder.
pub const adoption_ladder: []const AdoptionLevel = &.{
    .{ .level = 0, .title = "Inspect — query foreign project semantics", .status = "partial" },
    .{ .level = 1, .title = "Generate — tests, docs, bindings, schemas", .status = "partial" },
    .{ .level = 2, .title = "Validate — ABI, compatibility, differential tests", .status = "partial" },
    .{ .level = 3, .title = "Transform — semantic patches to native projects", .status = "open" },
    .{ .level = 4, .title = "Specialize — optimized native implementations", .status = "open" },
    .{ .level = 5, .title = "Integrate — generated artifacts in native build", .status = "partial" },
    .{ .level = 6, .title = "Share semantics — multi-language descriptors", .status = "open" },
    .{ .level = 7, .title = "Mixed-language optimization", .status = "open" },
    .{ .level = 8, .title = "Selective Duo adoption", .status = "open" },
};

pub const ReadyTool = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 20 §12 high-leverage ready-to-use tools.
pub const ready_tools: []const ReadyTool = &.{
    .{ .id = "P20-T01", .title = "Binding generator", .status = "partial" },
    .{ .id = "P20-T02", .title = "ABI auditor", .status = "partial" },
    .{ .id = "P20-T03", .title = "Schema synthesizer", .status = "open" },
    .{ .id = "P20-T04", .title = "Test synthesizer", .status = "open" },
    .{ .id = "P20-T05", .title = "Documentation synthesizer", .status = "open" },
    .{ .id = "P20-T06", .title = "Migration generator", .status = "open" },
    .{ .id = "P20-T07", .title = "Repetition compressor", .status = "open" },
    .{ .id = "P20-T08", .title = "Performance transformation harness", .status = "open" },
    .{ .id = "P20-T09", .title = "Package semantic indexer", .status = "partial" },
    .{ .id = "P20-T10", .title = "MCP generator", .status = "open" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 20 §20 success criteria.
pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P20-G01", .title = "Useful without Duo implementation code", .status = "partial" },
    .{ .id = "P20-G02", .title = "Foreign project as staged semantic values", .status = "partial" },
    .{ .id = "P20-G03", .title = "One metaprogram across two frontends", .status = "open" },
    .{ .id = "P20-G04", .title = "One source → several native artifacts", .status = "partial" },
    .{ .id = "P20-G05", .title = "Deterministic validated provenance-linked output", .status = "partial" },
    .{ .id = "P20-G06", .title = "Semantic patch preview before emit", .status = "open" },
    .{ .id = "P20-G07", .title = "Incremental adoption without primary-language change", .status = "partial" },
    .{ .id = "P20-G08", .title = "Material reduction of handwritten duplicated facts", .status = "open" },
    .{ .id = "P20-G09", .title = "CLI/shell/LSP/MCP same semantic model", .status = "partial" },
    .{ .id = "P20-G10", .title = "Agents query semantics not text scrape", .status = "partial" },
    .{ .id = "P20-G11", .title = "Measurable foreign project improvement", .status = "partial" },
    .{ .id = "P20-G12", .title = "Credible universal macro language", .status = "open" },
};

pub fn writePass20Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass20":{{"pass":20,"mission":"Universal cross-language metaprogramming harness","schema":"{s}","plan":"{s}","foundation":"{s}","import_strength":"{s}","pipeline":"foreign project→SIM→Duo values→metaprogram→emit","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH, FOUNDATION_PASS, pass20_import_strength.SCHEMA_VERSION });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","priority":{d},"owner":"{s}"}}
        , .{ ws.id, ws.title, ws.status, ws.priority, ws.owner });
    }
    try w.print("],\"adoption_ladder\":[", .{});
    for (adoption_ladder, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"level":{d},"title":"{s}","status":"{s}"}}
        , .{ a.level, a.title, a.status });
    }
    try w.print("],\"ready_tools\":[", .{});
    for (ready_tools, 0..) |t, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ t.id, t.title, t.status });
    }
    try w.print("],\"completion_gates\":[", .{});
    for (completion_gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ g.id, g.title, g.status });
    }
    try w.print(
        \\],"invariants":["semantic-not-text","pass5-foundation","incremental-adoption","provenance-required"]}}
    , .{});
}

test "pass20_catalog: schema and counts" {
    try std.testing.expectEqualStrings("pass20-catalog-v0", SCHEMA_VERSION);
    try std.testing.expectEqual(@as(usize, 12), workstreams.len);
    try std.testing.expectEqual(@as(usize, 9), adoption_ladder.len);
    try std.testing.expectEqual(@as(usize, 10), ready_tools.len);
    try std.testing.expectEqual(@as(usize, 12), completion_gates.len);
}
