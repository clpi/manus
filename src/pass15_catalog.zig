//! Pass 15 — semantic shell catalog (`duo catalog` → `pass15`).
const std = @import("std");
const command_descriptor = @import("command_descriptor.zig");
const shell_session = @import("shell_session.zig");
const shell_host = @import("shell_host.zig");
const pass15_shell_audit = @import("pass15_shell_audit.zig");

pub const SCHEMA_VERSION = "pass15-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass15_semantic_shell.md";
pub const VERTICAL_PROOF_PATH = "examples/pass15_vertical_proof.duo";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 15 §42 — twenty bounded workstreams.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P15-WS1", .title = "Shell landscape and ergonomic audit", .status = "done", .priority = 1, .owner = "src/pass15_shell_audit.zig" },
    .{ .id = "P15-WS2", .title = "Command descriptor architecture", .status = "partial", .priority = 2, .owner = "src/command_descriptor.zig" },
    .{ .id = "P15-WS3", .title = "Execution context", .status = "open", .priority = 3, .owner = "future" },
    .{ .id = "P15-WS4", .title = "Process substrate", .status = "partial", .priority = 4, .owner = "src/shell_host.zig" },
    .{ .id = "P15-WS5", .title = "Stream convergence", .status = "open", .priority = 5, .owner = "future" },
    .{ .id = "P15-WS6", .title = "Path and glob values", .status = "open", .priority = 6, .owner = "future" },
    .{ .id = "P15-WS7", .title = "Persistent semantic session", .status = "partial", .priority = 7, .owner = "src/shell_session.zig" },
    .{ .id = "P15-WS8", .title = "Progressive compilation and cache", .status = "open", .priority = 8, .owner = "future" },
    .{ .id = "P15-WS9", .title = "Pipeline fusion and realization", .status = "open", .priority = 9, .owner = "future" },
    .{ .id = "P15-WS10", .title = "Terminal renderer", .status = "partial", .priority = 10, .owner = "src/term.zig" },
    .{ .id = "P15-WS11", .title = "Completion and semantic search", .status = "open", .priority = 11, .owner = "future" },
    .{ .id = "P15-WS12", .title = "Diagnostics and repair actions", .status = "partial", .priority = 12, .owner = "src/term.zig + presentation_record.zig" },
    .{ .id = "P15-WS13", .title = "Capability security", .status = "open", .priority = 13, .owner = "future" },
    .{ .id = "P15-WS14", .title = "Cross-platform process semantics", .status = "partial", .priority = 14, .owner = "src/shell_host.zig" },
    .{ .id = "P15-WS15", .title = "LSP integration", .status = "open", .priority = 15, .owner = "~/x/duo-lsp" },
    .{ .id = "P15-WS16", .title = "MCP structured execution", .status = "open", .priority = 16, .owner = "~/x/duo-mcp" },
    .{ .id = "P15-WS17", .title = "Duo CLI migration", .status = "partial", .priority = 17, .owner = "src/command_descriptor.zig + src/main.zig" },
    .{ .id = "P15-WS18", .title = "Build and CI migration", .status = "partial", .priority = 18, .owner = "build.zig + command_descriptor" },
    .{ .id = "P15-WS19", .title = "Startup and latency performance", .status = "open", .priority = 19, .owner = "future" },
    .{ .id = "P15-WS20", .title = "Competitive benchmark and proof suite", .status = "partial", .priority = 20, .owner = "examples/pass15_vertical_proof.duo" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    owner: []const u8,
};

pub const milestones: []const Milestone = &.{
    .{ .id = "P15-M0", .title = "Plan + catalog + landscape audit + native gate", .status = "done", .owner = "docs/plans/pass15_semantic_shell.md" },
    .{ .id = "P15-M1", .title = "Command descriptor schema + duo.* built-ins", .status = "partial", .owner = "src/command_descriptor.zig" },
    .{ .id = "P15-M2", .title = "Persistent semantic session + canonical export", .status = "partial", .owner = "src/shell_session.zig" },
    .{ .id = "P15-M3", .title = "Cross-platform shell host + explicit shell()", .status = "partial", .owner = "src/shell_host.zig" },
    .{ .id = "P15-M4", .title = "First vertical proof workload", .status = "partial", .owner = VERTICAL_PROOF_PATH },
    .{ .id = "P15-M5", .title = "Pipeline fusion proof (native loop)", .status = "open", .owner = "future" },
    .{ .id = "P15-M6", .title = "Competitive ergonomics proof suite", .status = "open", .owner = "future" },
    .{ .id = "P15-M7", .title = "Agent MCP structured invocation proof", .status = "open", .owner = "future" },
};

pub const AcceptanceCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 15 §44 — acceptance criteria (subset tracked in catalog; full list in plan).
pub const acceptance_criteria: []const AcceptanceCriterion = &.{
    .{ .id = 1, .title = "Duo operates as a persistent semantic shell", .status = "partial" },
    .{ .id = 2, .title = "Interactive input is ordinary Duo or lowers canonically", .status = "partial" },
    .{ .id = 3, .title = "External arguments are structured values", .status = "open" },
    .{ .id = 4, .title = "Paths require no quoting for correctness", .status = "open" },
    .{ .id = 5, .title = "Globbing is explicit and returns path values", .status = "open" },
    .{ .id = 6, .title = "Pipelines retain structured values", .status = "open" },
    .{ .id = 7, .title = "Native stages fuse", .status = "open" },
    .{ .id = 13, .title = "Help/completion/MCP/LSP derive from descriptors", .status = "partial" },
    .{ .id = 15, .title = "Interactive sessions export canonical .duo", .status = "partial" },
    .{ .id = 25, .title = "Duo CLI uses descriptor architecture", .status = "partial" },
    .{ .id = 33, .title = "No permanent second shell semantic system", .status = "partial" },
};

pub fn writePass15Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass15":{{"pass":15,"mission":"Semantic shell — interactive realization planner for Duo","schema":"{s}","plan":"{s}","vertical_proof":"{s}","shell_session_schema":"{s}","command_descriptor_schema":"{s}","shell_host_schema":"{s}","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH, VERTICAL_PROOF_PATH, shell_session.SCHEMA_VERSION, command_descriptor.SCHEMA_VERSION, shell_host.SCHEMA_VERSION });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"priority\":{d},\"owner\":\"{s}\"}}", .{
            ws.id, ws.title, ws.status, ws.priority, ws.owner,
        });
    }
    try w.writeAll("],\"milestones\":[");
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"owner\":\"{s}\"}}", .{ m.id, m.title, m.status, m.owner });
    }
    try w.writeAll("],\"acceptance\":[");
    for (acceptance_criteria, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ c.id, c.title, c.status });
    }
    try w.writeAll("],\"command_descriptors\":");
    try command_descriptor.writeCatalogJson(w);
    try w.writeAll(",\"audits\":");
    try pass15_shell_audit.writeAuditSummaryJson(w);
    try w.writeAll("}");
}

test "pass15_catalog: writePass15Json structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass15Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass15\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P15-WS1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "duo.build") != null);
}
