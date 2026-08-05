//! Pass 13 — development control plane catalog (`duo catalog` → `pass13`).
const std = @import("std");
const dev_control_plane = @import("dev_control_plane.zig");
const pass13_dev_audit = @import("pass13_dev_audit.zig");
const presentation_record = @import("presentation_record.zig");

pub const SCHEMA_VERSION = "pass13-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass13_development_control_plane.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P13-WS1", .title = "Repository and tooling truth map", .status = "in_progress", .priority = 1, .owner = "src/pass13_dev_audit.zig" },
    .{ .id = "P13-WS2", .title = "Development schema", .status = "in_progress", .priority = 2, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS3", .title = "Claim lease service", .status = "in_progress", .priority = 3, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS4", .title = "Context compiler", .status = "partial", .priority = 4, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS5", .title = "Dependency-aware work graph", .status = "partial", .priority = 5, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS6", .title = "Delegation engine", .status = "open", .priority = 6, .owner = "duo-mcp" },
    .{ .id = "P13-WS7", .title = "Impact and validation planner", .status = "partial", .priority = 7, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS8", .title = "Append-only audit log", .status = "in_progress", .priority = 8, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS9", .title = "Integration queue", .status = "in_progress", .priority = 9, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS10", .title = "Semantic presentation engine", .status = "in_progress", .priority = 10, .owner = "src/presentation_record.zig" },
    .{ .id = "P13-WS11", .title = "Terminal visual language", .status = "open", .priority = 11, .owner = "src/term.zig" },
    .{ .id = "P13-WS12", .title = "Structured agent output", .status = "partial", .priority = 12, .owner = "src/presentation_record.zig" },
    .{ .id = "P13-WS13", .title = "LSP development projections", .status = "open", .priority = 13, .owner = "~/x/duo-lsp" },
    .{ .id = "P13-WS14", .title = "Documentation truth generation", .status = "partial", .priority = 14, .owner = "src/proof_carrying.zig" },
    .{ .id = "P13-WS15", .title = "Enforcement (CI + commit gates)", .status = "open", .priority = 15, .owner = "scripts/repo_hygiene.sh" },
    .{ .id = "P13-WS16", .title = "Multi-agent stress test", .status = "open", .priority = 16, .owner = "—" },
    .{ .id = "P13-WS17", .title = "Ward cross-repository proof", .status = "partial", .priority = 17, .owner = "src/ward_readiness.zig" },
    .{ .id = "P13-WS18", .title = "Coordination migration", .status = "partial", .priority = 18, .owner = "src/dev_control_plane.zig" },
    .{ .id = "P13-WS19", .title = "Historical cleanup", .status = "open", .priority = 19, .owner = "docs/plans" },
    .{ .id = "P13-WS20", .title = "Final control-plane reconciliation", .status = "open", .priority = 20, .owner = "pass13_dev_audit" },
};

pub const SuccessCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const success_criteria: []const SuccessCriterion = &.{
    .{ .id = 1, .title = "Fingerprinted project snapshot at session start", .status = "partial" },
    .{ .id = 2, .title = "Dependency-aware work items (no done state)", .status = "partial" },
    .{ .id = 3, .title = "Machine-readable claim leases", .status = "partial" },
    .{ .id = 4, .title = "Semantic overlap detection", .status = "partial" },
    .{ .id = 5, .title = "Context bundles from canonical truth", .status = "partial" },
    .{ .id = 6, .title = "Development MCP owns coordination not semantics", .status = "partial" },
    .{ .id = 7, .title = "Impact-based validation selection", .status = "partial" },
    .{ .id = 8, .title = "Integration distinct from implementation", .status = "partial" },
    .{ .id = 9, .title = "Causal trace for accepted changes", .status = "open" },
    .{ .id = 10, .title = "Structured presentation records", .status = "partial" },
    .{ .id = 11, .title = "Five-agent milestone without duplicate work", .status = "open" },
    .{ .id = 12, .title = "Markdown not authoritative for active claims", .status = "partial" },
};

pub fn writePass13Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print(
        \\"pass13":{{"pass":13,"mission":"Development control plane, agent coordination, tooling reconciliation","schema":"{s}","plan":"{s}","control_plane_schema":"{s}","presentation_schema":"{s}","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH, dev_control_plane.SCHEMA_VERSION, presentation_record.SCHEMA_VERSION });

    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"priority\":{d},\"owner\":\"{s}\"}}", .{
            ws.id, ws.title, ws.status, ws.priority, ws.owner,
        });
    }
    try w.writeAll("],\"seed_work_items\":[");
    for (dev_control_plane.seed_work_items, 0..) |wi, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"state\":\"{s}\",\"owner\":\"{s}\",\"semantic_target\":\"{s}\",\"depends_on\":[", .{
            wi.id, wi.title, wi.state.name(), wi.owner, wi.semantic_target,
        });
        for (wi.depends_on, 0..) |dep, di| {
            if (di > 0) try w.writeAll(",");
            try w.print("\"{s}\"", .{dep});
        }
        try w.writeAll("]}");
    }
    try w.writeAll("],\"work_graph\":");
    try dev_control_plane.writeWorkGraphJson(w);
    try w.writeAll(",\"success_criteria\":[");
    for (success_criteria, 0..) |sc, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ sc.id, sc.title, sc.status });
    }
    try w.writeAll("],\"audits\":");
    try pass13_dev_audit.writeAuditSummaryJson(w);
    try w.writeAll(",\"authority_order\":[");
    const authority = [_][]const u8{
        "compiler_semantic_facts",
        "generated_capability_registries",
        "production_code_paths",
        "artifact_inspection",
        "tests_fuzz_bench_proof",
        "git_state",
        "canonical_documentation",
        "decision_records",
        "agent_reports",
        "historical_plans",
    };
    for (authority, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{a});
    }
    try w.writeAll("],\"dev_cli\":[");
    const dev_cli = [_][]const u8{
        "duo dev snapshot",
        "duo dev audit",
        "duo dev summary",
        "duo dev context <work-item>",
        "duo dev claim acquire|list|release|heartbeat",
        "duo dev session start",
        "duo dev validate plan|run",
        "duo dev integration submit|list|complete",
        "duo dev coordination export|status|render",
        "duo dev work graph",
        "duo dev barrier check",
        "duo dev preserve",
    };
    for (dev_cli, 0..) |cmd, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{cmd});
    }
    try w.writeAll("],\"live_snapshot\":");
    var snap_arena = std.heap.ArenaAllocator.init(alloc);
    defer snap_arena.deinit();
    const snap = try dev_control_plane.buildProjectSnapshot(snap_arena.allocator());
    try dev_control_plane.writeSnapshotJson(w, snap);
    try w.writeAll("}");
}

test "pass13_catalog: writePass13Json structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass13Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass13\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P13-WS3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "audit_groups") != null);
}
