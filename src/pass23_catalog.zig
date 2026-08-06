//! Pass 23 — unified metaprotocols, native metaprogramming, semantic closure catalog.
const std = @import("std");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");

pub const SCHEMA_VERSION = "pass23-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass23_unified_metaprotocols.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 23 implementation workstreams (repository-grounded).
pub const workstreams: []const Workstream = &.{
    .{ .id = "P23-WS0", .title = "Repository truth map + migration inventory", .status = "partial", .priority = 0, .owner = "docs/plans/pass23_unified_metaprotocols.md" },
    .{ .id = "P23-WS1", .title = "Protocol identity registry (Lua aliases + kernel)", .status = "partial", .priority = 1, .owner = "src/pass23_protocol_registry.zig + src/protocol_kernel.zig + src/codegen.zig" },
    .{ .id = "P23-WS2", .title = "Canonical function syntax (assign + func_expr)", .status = "partial", .priority = 2, .owner = "src/parser.zig" },
    .{ .id = "P23-WS3", .title = "Methods/receiver policy (: vs . assignment)", .status = "partial", .priority = 3, .owner = "src/parser.zig + src/sema.zig" },
    .{ .id = "P23-WS4", .title = "Assignment expression + tail-return semantics", .status = "partial", .priority = 4, .owner = "src/sema.zig + src/codegen.zig + src/dnir_lower.zig" },
    .{ .id = "P23-WS5", .title = "Return consumption specialization", .status = "partial", .priority = 5, .owner = "src/semantic_graph.zig + src/dnir_lower.zig" },
    .{ .id = "P23-WS6", .title = "Descriptor-first types (no bracket generics)", .status = "open", .priority = 6, .owner = "src/sema.zig + src/semantic_graph.zig" },
    .{ .id = "P23-WS7", .title = "Concept/trait → descriptor migration", .status = "open", .priority = 7, .owner = "src/sema.zig + migration" },
    .{ .id = "P23-WS8", .title = "Unified conversion graph (to/from)", .status = "partial", .priority = 8, .owner = "src/conversion_graph.zig" },
    .{ .id = "P23-WS9", .title = "Formatting + interpolation sink lowering", .status = "partial", .priority = 9, .owner = "src/parser.zig + src/codegen.zig + lib/std" },
    .{ .id = "P23-WS10", .title = "Metaprotocol laws + resolution order", .status = "open", .priority = 10, .owner = "src/pass23_protocol_registry.zig + src/transform_engine.zig" },
    .{ .id = "P23-WS11", .title = "Lifecycle (drop) + borrow/view semantics", .status = "open", .priority = 11, .owner = "src/semantic_graph.zig + src/sema.zig" },
    .{ .id = "P23-WS12", .title = "Native metaprogramming + derivation", .status = "partial", .priority = 12, .owner = "src/comptime.zig + @comp.derive" },
    .{ .id = "P23-WS13", .title = "Legacy migration (macro/quote/concept/method flags)", .status = "open", .priority = 13, .owner = "migration fixtures" },
    .{ .id = "P23-WS14", .title = "LSP/MCP semantic model exposure", .status = "open", .priority = 14, .owner = "~/x/duo-lsp + ~/x/duo-mcp" },
    .{ .id = "P23-WS15", .title = "Ward metaprotocol proof workload", .status = "open", .priority = 15, .owner = "examples/ + Ward" },
};

pub const MigrationTarget = struct {
    legacy: []const u8,
    canonical: []const u8,
    status: []const u8,
};

/// Pass 23 §21 — required migration mappings.
pub const migration_targets: []const MigrationTarget = &.{
    .{ .legacy = "protocol_kernel.zig duplicate Op table", .canonical = "pass23_protocol_registry shim re-export", .status = "partial" },
    .{ .legacy = "FuncDecl (bare fun)", .canonical = "assignment + func_expr", .status = "partial" },
    .{ .legacy = "ConceptDef", .canonical = "descriptor of required semantic members", .status = "open" },
    .{ .legacy = "generic type parameters", .canonical = "descriptor values + call specialization", .status = "open" },
    .{ .legacy = "Lua __* magic names", .canonical = "pass23_protocol_registry lua_aliases", .status = "partial" },
    .{ .legacy = "__tostring / tostring", .canonical = "format + to(str) conversion graph", .status = "open" },
    .{ .legacy = "MacroDef / quote / unquote", .canonical = "staged semantic functions", .status = "partial" },
    .{ .legacy = "FuncDecl.method flag", .canonical = "callable member + receiver policy", .status = "partial" },
};

pub const DeferredDesign = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    note: []const u8,
};

/// Pass 23 §5 — explicitly deferred; must not be implemented without general mechanism.
pub const deferred_designs: []const DeferredDesign = &.{
    .{ .id = "P23-D01", .title = "Implicit accumulator return / live-out inference", .status = "superseded", .note = "Pass 25 §5.1 tail-demand propagation + result lineage (not backward local search)" },
    .{ .id = "P23-D02", .title = "@return / named return bindings", .status = "rejected", .note = "prohibited by Pass 23 §26" },
    .{ .id = "P23-D03", .title = "Whitespace-adjacent string concatenation", .status = "deferred", .note = "use interpolation instead; §10.6" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 23 §27 exit gates (subset tracked; full list in plan doc).
pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P23-G01", .title = "add = (a, b) a + b canonical", .status = "partial" },
    .{ .id = "P23-G02", .title = "Compound assignment yields updated value", .status = "partial" },
    .{ .id = "P23-G03", .title = "Assignment expression exact semantics", .status = "partial" },
    .{ .id = "P23-G04", .title = "Colon/dot method assignment", .status = "partial" },
    .{ .id = "P23-G05", .title = "One function representation", .status = "partial" },
    .{ .id = "P23-G06", .title = "Descriptors first-class (no bracket generics)", .status = "open" },
    .{ .id = "P23-G07", .title = "Natural compile-time without ceremonial @", .status = "partial" },
    .{ .id = "P23-G08", .title = "Unified conversion graph", .status = "partial" },
    .{ .id = "P23-G09", .title = "Interpolation + sink formatting", .status = "partial" },
    .{ .id = "P23-G10", .title = "Lua aliases → stable protocol identities", .status = "partial" },
    .{ .id = "P23-G11", .title = "Custom protocols same dispatch architecture", .status = "open" },
    .{ .id = "P23-G12", .title = "concept/trait compatibility-only", .status = "open" },
    .{ .id = "P23-G13", .title = "drop deterministic resource semantics", .status = "open" },
    .{ .id = "P23-G14", .title = "Distinct borrow/view/address/pin/retain", .status = "open" },
    .{ .id = "P23-G15", .title = "Return consumption without semantic fork", .status = "partial" },
    .{ .id = "P23-G16", .title = "Legacy migration paths with parity", .status = "open" },
    .{ .id = "P23-G17", .title = "LSP/MCP one canonical model", .status = "open" },
    .{ .id = "P23-G18", .title = "Ward proves architecture", .status = "open" },
    .{ .id = "P23-G19", .title = "Tail-demand supersedes P23-D01 (factorial without trailing read)", .status = "partial" },
    .{ .id = "P23-G20", .title = "No prohibited outcomes (§26)", .status = "partial" },
};

pub fn writePass23Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass23":{{"pass":23,"mission":"Unified metaprotocols, native metaprogramming, semantic closure","schema":"{s}","plan":"{s}","protocol_registry":"{s}","kernel_ops":{d},"lua_aliases":{d},"workstreams":[
    , .{
        SCHEMA_VERSION,
        PLAN_PATH,
        pass23_protocol_registry.SCHEMA_VERSION,
        pass23_protocol_registry.kernelOpCount(),
        pass23_protocol_registry.lua_aliases.len,
    });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","priority":{d},"owner":"{s}"}}
        , .{ ws.id, ws.title, ws.status, ws.priority, ws.owner });
    }
    try w.print("],\"migration_targets\":[", .{});
    for (migration_targets, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"legacy":"{s}","canonical":"{s}","status":"{s}"}}
        , .{ m.legacy, m.canonical, m.status });
    }
    try w.print("],\"deferred_designs\":[", .{});
    for (deferred_designs, 0..) |d, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","note":"{s}"}}
        , .{ d.id, d.title, d.status, d.note });
    }
    try w.print("],\"completion_gates\":[", .{});
    for (completion_gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ g.id, g.title, g.status });
    }
    try w.print(
        \\],"invariants":["one-function-representation","descriptor-not-ast","no-shadow-protocol-ast","assignment-yields-value","@-is-explicit-authority","progressive-erasure"]}}
    , .{});
}

test "pass23_catalog: schema and counts" {
    try std.testing.expectEqualStrings("pass23-catalog-v0", SCHEMA_VERSION);
    try std.testing.expectEqual(@as(usize, 16), workstreams.len);
    try std.testing.expectEqual(@as(usize, 8), migration_targets.len);
    try std.testing.expectEqual(@as(usize, 3), deferred_designs.len);
    try std.testing.expectEqual(@as(usize, 20), completion_gates.len);
}
