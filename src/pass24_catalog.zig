//! Pass 24 — unified calls, Lua superset, execution-graph concurrency catalog.
const std = @import("std");
const lua_superset_catalog = @import("lua_superset_catalog.zig");

pub const SCHEMA_VERSION = "pass24-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass24_unified_calls_concurrency_constitution.md";
pub const COMPAT_MATRIX = "docs/catalogs/lua_superset_compatibility.md";
pub const INDEX_PATH = "docs/plans/lua_superset_concurrency_supremacy.md";

pub const SyntaxClass = lua_superset_catalog.SyntaxClass;

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
    plan_section: []const u8,
};

/// Pass 24 §10 implementation ordering (P0–P9).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P24-WS0", .title = "Constitution + ambiguity fixtures registry", .status = "partial", .priority = 0, .owner = "docs/plans/pass24_unified_calls_concurrency_constitution.md", .plan_section = "§0–§2" },
    .{ .id = "P24-WS1", .title = "Lua superset P0: long brackets, classification, gates", .status = "partial", .priority = 1, .owner = "src/lua_superset_catalog.zig + lua_superset_gate.zig", .plan_section = "§3" },
    .{ .id = "P24-WS2", .title = "Lua 5.5 corpus + differential reference testing", .status = "open", .priority = 2, .owner = "src/lua_superset_corpus.zig + tests/lua55/", .plan_section = "§3.5" },
    .{ .id = "P24-WS3", .title = "Call architecture: value vs invoke, parenless, command context", .status = "partial", .priority = 3, .owner = "src/pass24_call_model.zig + src/parser.zig", .plan_section = "§2" },
    .{ .id = "P24-WS4", .title = "Call objects in semantic graph + multi-arg DNIR", .status = "partial", .priority = 4, .owner = "src/semantic_graph.zig + src/types.zig + dnir_lower.zig", .plan_section = "§2.4" },
    .{ .id = "P24-WS5", .title = "Execution graph entity + structured task scope", .status = "partial", .priority = 5, .owner = "src/pass24_execution_model.zig + src/region_graph.zig", .plan_section = "§4.1–§4.2" },
    .{ .id = "P24-WS6", .title = "@spawn @all @race on ordinary calls", .status = "open", .priority = 6, .owner = "parser + sema + transform_engine", .plan_section = "§4.3" },
    .{ .id = "P24-WS7", .title = "@parallel regions + automatic derivation + cost model", .status = "open", .priority = 7, .owner = "realization.zig + region_transform", .plan_section = "§4–§5" },
    .{ .id = "P24-WS8", .title = "Streams, channels, selection, elimination", .status = "open", .priority = 8, .owner = "stdlib + semantic_graph", .plan_section = "§4.7" },
    .{ .id = "P24-WS9", .title = "Determinism, replay, real-time policies", .status = "open", .priority = 9, .owner = "realization + runtime profiles", .plan_section = "§4.8" },
    .{ .id = "P24-WS10", .title = "Scheduler/representation elimination + zero-alloc tasks", .status = "open", .priority = 10, .owner = "native_backend + dnir", .plan_section = "§5.3" },
    .{ .id = "P24-WS11", .title = "LSP/MCP/formatter/treesitter/diagnostics integration", .status = "open", .priority = 11, .owner = "duo-lsp + duo-mcp + ext/tree-sitter-duo", .plan_section = "§7, §9" },
    .{ .id = "P24-WS12", .title = "Ward + Go benchmarks + self-host proofs", .status = "open", .priority = 12, .owner = "examples/ + bench/", .plan_section = "§5.4, §11" },
};

pub const AmbiguityFixture = struct {
    id: []const u8,
    title: []const u8,
    resolution: []const u8,
    status: []const u8,
};

/// Pass 24 §2.5 — call/long-string ambiguity registry.
pub const ambiguity_fixtures: []const AmbiguityFixture = &.{
    .{ .id = "P24-A01", .title = "bare callable is value reference, not invoke", .resolution = "a retrieves value; a() and a x invoke", .status = "proven" },
    .{ .id = "P24-A02", .title = "parenless precedence f x + y", .resolution = "(f x) + y unless parenthesized", .status = "proven" },
    .{ .id = "P24-A03", .title = "command context vs expression identifier", .resolution = "explicit command invocation context only", .status = "partial" },
    .{ .id = "P24-A04", .title = "[[ always long-string open", .resolution = "Lua delimiter matching; never shell test", .status = "proven" },
    .{ .id = "P24-A05", .title = "Type:method vs typed binding colon", .resolution = "qualified func assign disambiguation", .status = "partial" },
    .{ .id = "P24-A06", .title = "shell long string with inner Bash ]]", .resolution = "use [=[ ]=] or higher delimiter level", .status = "proven" },
};

pub const RejectedAlternative = struct {
    id: []const u8,
    proposal: []const u8,
    reason: []const u8,
};

pub const rejected_alternatives: []const RejectedAlternative = &.{
    .{ .id = "P24-R01", .proposal = "bare a means a()", .reason = "breaks first-class functions and Lua callback semantics (§2.1)" },
    .{ .id = "P24-R02", .proposal = "[[ as shell conditional", .reason = "Lua long-string syntax (§3.3)" },
    .{ .id = "P24-R03", .proposal = "deprecate then/do/local for Duo canonical", .reason = "superset threshold not met; LUA_CANONICAL permanent" },
    .{ .id = "P24-R04", .proposal = "separate async function kind", .reason = "execution policy at call site / region (§4.1)" },
    .{ .id = "P24-R05", .proposal = "fire-and-forget spawn default", .reason = "structured scope default; @detach explicit (§4.2)" },
    .{ .id = "P24-R06", .proposal = "parallel always means threads", .reason = "realization selection + break-even model (§5.2)" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    plan_section: []const u8,
};

pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P24-G01", .title = "Long-bracket family preserved and gated", .status = "partial", .plan_section = "§3.3" },
    .{ .id = "P24-G02", .title = "Syntax classification registry complete", .status = "partial", .plan_section = "§3.1" },
    .{ .id = "P24-G03", .title = "Lua 5.5 differential corpus", .status = "open", .plan_section = "§3.5" },
    .{ .id = "P24-G04", .title = "a is value; a()/a x invoke; no global auto-call", .status = "partial", .plan_section = "§2.2" },
    .{ .id = "P24-G05", .title = "Command context isolated from value references", .status = "partial", .plan_section = "§2.3" },
    .{ .id = "P24-G06", .title = "Call nodes in semantic graph with consumption", .status = "partial", .plan_section = "§2.4" },
    .{ .id = "P24-G07", .title = "Multi-arg call_direct DNIR + native ABI", .status = "partial", .plan_section = "§2.4" },
    .{ .id = "P24-G08", .title = "Execution graph region entity", .status = "partial", .plan_section = "§4.1" },
    .{ .id = "P24-G09", .title = "@spawn @all @race lowering proofs", .status = "open", .plan_section = "§4.3" },
    .{ .id = "P24-G10", .title = "@parallel legality + sequential fallback", .status = "open", .plan_section = "§4.3, §5" },
    .{ .id = "P24-G11", .title = "Channel/stream fusion elimination proof", .status = "open", .plan_section = "§4.7, §6.3" },
    .{ .id = "P24-G12", .title = "@comp.why.* concurrency explanations", .status = "open", .plan_section = "§9.3" },
    .{ .id = "P24-G13", .title = "LSP/MCP task graph exposure", .status = "open", .plan_section = "§9" },
    .{ .id = "P24-G14", .title = "Go benchmark suite with full reporting", .status = "open", .plan_section = "§5.4" },
    .{ .id = "P24-G15", .title = "Ward parallel compile without private hooks", .status = "open", .plan_section = "§11" },
};

pub fn writePass24Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass24":{{"pass":24,"mission":"Unified calls, Lua superset, execution-graph concurrency","schema":"{s}","plan":"{s}","compat_matrix":"{s}","lua_superset_schema":"{s}","workstreams":[
    , .{
        SCHEMA_VERSION,
        PLAN_PATH,
        COMPAT_MATRIX,
        lua_superset_catalog.SCHEMA_VERSION,
    });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","priority":{d},"owner":"{s}","plan_section":"{s}"}}
        , .{ ws.id, ws.title, ws.status, ws.priority, ws.owner, ws.plan_section });
    }
    try w.print("],\"completion_gates\":[", .{});
    for (completion_gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","plan_section":"{s}"}}
        , .{ g.id, g.title, g.status, g.plan_section });
    }
    try w.print(
        \\],"invariants":["maximize-lua-not-minimize","value-ref-not-auto-call","one-execution-graph","effects-drive-scheduling","canonical-not-exclusive","explain-fallback"]}}
    , .{});
}

test "pass24_catalog: schema and counts" {
    try std.testing.expectEqualStrings("pass24-catalog-v0", SCHEMA_VERSION);
    try std.testing.expectEqual(@as(usize, 13), workstreams.len);
    try std.testing.expectEqual(@as(usize, 6), ambiguity_fixtures.len);
    try std.testing.expectEqual(@as(usize, 6), rejected_alternatives.len);
    try std.testing.expectEqual(@as(usize, 15), completion_gates.len);
}
