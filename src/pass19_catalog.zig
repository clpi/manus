//! Pass 19 — unified semantic experience catalog (`duo catalog` → `pass19`).
const std = @import("std");
const command_descriptor = @import("command_descriptor.zig");
const pass15_catalog = @import("pass15_catalog.zig");

pub const SCHEMA_VERSION = "pass19-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass19_unified_semantic_experience.md";
pub const VERTICAL_PROOF_PATH = "examples/pass19_vertical_proof.duo";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 19 §89–§90 — bounded workstreams (umbrella over Pass 15 shell + platform).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P19-WS1", .title = "Unified command surface (duo)", .status = "partial", .priority = 1, .owner = "src/main.zig + src/command_descriptor.zig" },
    .{ .id = "P19-WS2", .title = "Command discoverability (help, search, explain)", .status = "open", .priority = 2, .owner = "src/command_descriptor.zig" },
    .{ .id = "P19-WS3", .title = "Semantic shell", .status = "partial", .priority = 3, .owner = "pass15: shell_session + shell_host" },
    .{ .id = "P19-WS4", .title = "Structured arguments and Path values", .status = "open", .priority = 4, .owner = "lib/std/path.duo (future)" },
    .{ .id = "P19-WS5", .title = "Command descriptor schema (full)", .status = "partial", .priority = 5, .owner = "src/command_descriptor.zig" },
    .{ .id = "P19-WS6", .title = "External tool descriptors (git, docker, …)", .status = "open", .priority = 6, .owner = "lib/std/shell.duo (future)" },
    .{ .id = "P19-WS7", .title = "Semantic shell history", .status = "open", .priority = 7, .owner = "src/shell_session.zig" },
    .{ .id = "P19-WS8", .title = "History-to-program promotion", .status = "partial", .priority = 8, .owner = "src/shell_session.zig" },
    .{ .id = "P19-WS9", .title = "Universal semantic pipelines", .status = "open", .priority = 9, .owner = "pass15 P15-WS9" },
    .{ .id = "P19-WS10", .title = "Pipeline planning and @comp.why(pipeline)", .status = "open", .priority = 10, .owner = "src/realization.zig + pass22" },
    .{ .id = "P19-WS11", .title = "Standard library semantic vocabulary", .status = "partial", .priority = 11, .owner = "lib/std/" },
    .{ .id = "P19-WS12", .title = "Collections as intent (Map/Set/Vec)", .status = "open", .priority = 12, .owner = "lib/std/maps.duo + realization" },
    .{ .id = "P19-WS13", .title = "Filesystem ergonomics", .status = "partial", .priority = 13, .owner = "lib/std/fs.duo" },
    .{ .id = "P19-WS14", .title = "Networking ergonomics", .status = "partial", .priority = 14, .owner = "lib/std/http.duo (future)" },
    .{ .id = "P19-WS15", .title = "Descriptor-driven serialization", .status = "partial", .priority = 15, .owner = "lib/std/json.duo + contracts.duo" },
    .{ .id = "P19-WS16", .title = "Module system (req)", .status = "partial", .priority = 16, .owner = "src/sema.zig + lib/" },
    .{ .id = "P19-WS17", .title = "Scope, visibility, @export", .status = "partial", .priority = 17, .owner = "src/sema.zig" },
    .{ .id = "P19-WS18", .title = "Package identity and resolution", .status = "open", .priority = 18, .owner = "future package graph" },
    .{ .id = "P19-WS19", .title = "Intent-based dependency (duo need)", .status = "open", .priority = 19, .owner = "future" },
    .{ .id = "P19-WS20", .title = "Locking and reproducibility", .status = "partial", .priority = 20, .owner = "src/dependency_manifest.zig" },
    .{ .id = "P19-WS21", .title = "Package command auto-exposure", .status = "open", .priority = 21, .owner = "future" },
    .{ .id = "P19-WS22", .title = "Semantic package registry", .status = "open", .priority = 22, .owner = "future" },
    .{ .id = "P19-WS23", .title = "Universal project model", .status = "partial", .priority = 23, .owner = "build.zig + project graph" },
    .{ .id = "P19-WS24", .title = "Universal build graph", .status = "partial", .priority = 24, .owner = "build.zig" },
    .{ .id = "P19-WS25", .title = "duo doctor diagnostics", .status = "open", .priority = 25, .owner = "future" },
    .{ .id = "P19-WS26", .title = "Universal CLI definition and projections", .status = "open", .priority = 26, .owner = "command_descriptor + codegen" },
    .{ .id = "P19-WS27", .title = "Semantic API projections (HTTP/MCP/OpenAPI)", .status = "open", .priority = 27, .owner = "future" },
    .{ .id = "P19-WS28", .title = "Universal hosting model (serve/deploy)", .status = "open", .priority = 28, .owner = "future" },
    .{ .id = "P19-WS29", .title = "Terminal renderer and data viewer", .status = "partial", .priority = 29, .owner = "lib/std/term.duo + presentation_record.zig" },
    .{ .id = "P19-WS30", .title = "Compiler as semantic oracle (@comp.why)", .status = "partial", .priority = 30, .owner = "src/semantic_graph.zig + duo explain" },
    .{ .id = "P19-WS31", .title = "Agent-native interfaces (MCP)", .status = "partial", .priority = 31, .owner = "~/x/duo-mcp" },
    .{ .id = "P19-WS32", .title = "Security and capability model", .status = "open", .priority = 32, .owner = "future" },
    .{ .id = "P19-WS33", .title = "Platform performance (startup, cache, fusion)", .status = "partial", .priority = 33, .owner = "compile_semantic_cache.zig" },
};

pub const RequiredAudit = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 19 §89 — implementation audits.
pub const required_audits: []const RequiredAudit = &.{
    .{ .id = "P19-A", .title = "Command surface inventory", .status = "partial" },
    .{ .id = "P19-B", .title = "Package resolution", .status = "open" },
    .{ .id = "P19-C", .title = "Shell integration per package command", .status = "open" },
    .{ .id = "P19-D", .title = "Module and scope", .status = "partial" },
    .{ .id = "P19-E", .title = "Semantic projections (CLI/HTTP/MCP)", .status = "open" },
    .{ .id = "P19-F", .title = "End-to-end user journeys", .status = "open" },
};

pub const SuccessCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 19 §91 — tracked success criteria (subset).
pub const success_criteria: []const SuccessCriterion = &.{
    .{ .id = 1, .title = "One-file program without project configuration", .status = "partial" },
    .{ .id = 2, .title = "Package discovery without leaving terminal", .status = "open" },
    .{ .id = 3, .title = "CLI and programmatic calls are same semantic entity", .status = "partial" },
    .{ .id = 4, .title = "Shell work promotable to canonical source", .status = "partial" },
    .{ .id = 5, .title = "Pipelines preserve structure", .status = "open" },
    .{ .id = 6, .title = "Local serve and deploy from same graph", .status = "open" },
    .{ .id = 7, .title = "Deterministic explainable package resolution", .status = "open" },
    .{ .id = 8, .title = "Semantic dependency upgrade reports", .status = "open" },
    .{ .id = 9, .title = "Compiler decisions inspectable everywhere", .status = "partial" },
    .{ .id = 10, .title = "Agents use same semantic model as humans", .status = "partial" },
    .{ .id = 11, .title = "No separate shell/package/CLI/hosting language", .status = "partial" },
};

pub fn writePass19Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass19":{{"pass":19,"mission":"Unified semantic experience — stdlib, packages, shell, CLI, developer platform","schema":"{s}","plan":"{s}","vertical_proof":"{s}","umbrella_passes":["pass15","pass8","pass14","pass22"],"command_descriptor_schema":"{s}","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH, VERTICAL_PROOF_PATH, command_descriptor.SCHEMA_VERSION });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"priority\":{d},\"owner\":\"{s}\"}}", .{
            ws.id, ws.title, ws.status, ws.priority, ws.owner,
        });
    }
    try w.writeAll("],\"required_audits\":[");
    for (required_audits, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ a.id, a.title, a.status });
    }
    try w.writeAll("],\"success_criteria\":[");
    for (success_criteria, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ c.id, c.title, c.status });
    }
    try w.writeAll("],\"command_descriptors\":");
    try command_descriptor.writeCatalogJson(w);
    try w.print(
        \\,"shell_foundation":{{"pass":15,"plan":"{s}","workstreams":{d}}},"invariants":["one-language","one-command-surface","descriptor-driven-projections","no-parallel-config-languages"]}}
    , .{ pass15_catalog.PLAN_PATH, pass15_catalog.workstreams.len });
}

test "pass19_catalog: schema and workstream count" {
    try std.testing.expectEqual(@as(usize, 33), workstreams.len);
    try std.testing.expectEqual(@as(usize, 6), required_audits.len);
    try std.testing.expect(std.mem.eql(u8, SCHEMA_VERSION, "pass19-catalog-v0"));
}

test "pass19_catalog: writePass19Json structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass19Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass19\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P19-WS1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "duo.build") != null);
}
