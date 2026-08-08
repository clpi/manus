//! Pass 25 — semantic unification, lifetimes, bidirectional meta, descriptor reconciliation catalog.
const std = @import("std");

pub const SCHEMA_VERSION = "pass25-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass25_native_semantic_unification.md";
pub const INDEX_PATH = "docs/archive/pass25_semantic_unification_index.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
    plan_section: []const u8,
};

/// Pass 25 §28 implementation ordering.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P25-WS0", .title = "Constitution + syntax audit + rejected-syntax registry", .status = "partial", .priority = 0, .owner = "docs/archive/pass25_native_semantic_unification.md", .plan_section = "§0–§2, §24" },
    .{ .id = "P25-WS1", .title = "Descriptor construction as ordinary calls", .status = "partial", .priority = 1, .owner = "src/sema.zig + src/types.zig", .plan_section = "§3" },
    .{ .id = "P25-WS2", .title = "No type parameters; stage as call property", .status = "open", .priority = 2, .owner = "src/sema.zig + src/mono.zig", .plan_section = "§4" },
    .{ .id = "P25-WS3", .title = "Tail-assignment return + consumption realization", .status = "partial", .priority = 3, .owner = "src/dnir_lower.zig + src/semantic_graph.zig", .plan_section = "§5" },
    .{ .id = "P25-WS17", .title = "Tail-demand propagation + result lineage (supersedes P23-D01)", .status = "partial", .priority = 3, .owner = "src/pass25_tail_result_model.zig + sema + semantic_graph", .plan_section = "§5.1" },
    .{ .id = "P25-WS4", .title = "Five semantic categories (value/alias/view/owner/pointer)", .status = "partial", .priority = 4, .owner = "src/pass25_semantic_category.zig + semantic_graph", .plan_section = "§6" },
    .{ .id = "P25-WS5", .title = "Lifetime provenance analysis + violation diagnostics", .status = "open", .priority = 5, .owner = "src/pass25_lifetime_model.zig + sema", .plan_section = "§7" },
    .{ .id = "P25-WS6", .title = "Mutation as inferred effect", .status = "open", .priority = 6, .owner = "src/sema.zig + effect algebra", .plan_section = "§8" },
    .{ .id = "P25-WS7", .title = "Ownership transfer + take() operations", .status = "open", .priority = 7, .owner = "src/semantic_graph.zig", .plan_section = "§9" },
    .{ .id = "P25-WS8", .title = "Regions + pinning as realization constraints", .status = "open", .priority = 8, .owner = "src/region_graph.zig + realization", .plan_section = "§10" },
    .{ .id = "P25-WS9", .title = "Pointer provenance metadata", .status = "open", .priority = 9, .owner = "src/pass25_semantic_category.zig", .plan_section = "§11" },
    .{ .id = "P25-WS10", .title = "Descriptor relationships (Projection values)", .status = "open", .priority = 10, .owner = "src/transform_engine.zig", .plan_section = "§12" },
    .{ .id = "P25-WS11", .title = "Bidirectional metaprogramming levels 0–3", .status = "partial", .priority = 11, .owner = "src/pass25_projection_model.zig + Pass 20", .plan_section = "§13–§15" },
    .{ .id = "P25-WS12", .title = "Authority, ambiguity, provenance on projections", .status = "open", .priority = 12, .owner = "src/proof_carrying.zig + semantic_graph", .plan_section = "§16–§17" },
    .{ .id = "P25-WS13", .title = "Semantic views (PublicUser = view User, …)", .status = "open", .priority = 13, .owner = "src/sema.zig + semantic_graph", .plan_section = "§19" },
    .{ .id = "P25-WS14", .title = "LSP/MCP preview + capability security", .status = "open", .priority = 14, .owner = "~/x/duo-lsp + ~/x/duo-mcp", .plan_section = "§22" },
    .{ .id = "P25-WS15", .title = "View disjointness + Pass 24 concurrency integration", .status = "open", .priority = 15, .owner = "pass24_execution_model + sema", .plan_section = "§25" },
    .{ .id = "P25-WS16", .title = "Pass 23/22/20 reconciliation + migration", .status = "partial", .priority = 16, .owner = "pass23_catalog + pass25_catalog", .plan_section = "§29" },
};

pub const RejectedSyntax = struct {
    id: []const u8,
    pattern: []const u8,
    reason: []const u8,
};

/// Pass 25 §24 — syntax audit registry.
pub const rejected_syntax: []const RejectedSyntax = &.{
    .{ .id = "P25-S01", .pattern = "Slice[Byte] bracket generics", .reason = "use Slice(Byte) or Slice Byte ordinary calls (§3)" },
    .{ .id = "P25-S02", .pattern = "Map<Key, Value> angle/bracket generics", .reason = "descriptor values + call specialization (§4)" },
    .{ .id = "P25-S03", .pattern = "Result<T, E> type-parameter syntax", .reason = "no syntactic type parameters (§4)" },
    .{ .id = "P25-S04", .pattern = "Nim-style result / named return bindings", .reason = "tail assignment return only (§5); aligns P23-D02 rejected" },
    .{ .id = "P25-S05", .pattern = "Rust lifetime annotations ('a)", .reason = "lifetimes are provenance, not syntax (§7)" },
    .{ .id = "P25-S06", .pattern = "&mut / mutable reference types", .reason = "mutation is inferred effect (§8)" },
    .{ .id = "P25-S07", .pattern = "lens / synchronization operators", .reason = "descriptor relationships (§12)" },
    .{ .id = "P25-S08", .pattern = "separate generic / schema language", .reason = "everything is ordinary semantic data (§1)" },
    .{ .id = "P25-S09", .pattern = "silent heap promotion for invalid lifetimes", .reason = "report violation; explicit repair (§7)" },
    .{ .id = "P25-S11", .pattern = "backward last-local return search", .reason = "tail-demand propagation only (§5.1); supersedes naive live-out" },
};

pub const RejectedAlternative = struct {
    id: []const u8,
    proposal: []const u8,
    reason: []const u8,
};

pub const rejected_alternatives: []const RejectedAlternative = &.{
    .{ .id = "P25-R01", .proposal = "canonical bracket generic syntax", .reason = "§3 descriptor calls only" },
    .{ .id = "P25-R02", .proposal = "type parameter declarations", .reason = "§4 stage is call property" },
    .{ .id = "P25-R03", .proposal = "global automatic reverse sync", .reason = "§13 level 3 exceptional and per-relationship" },
    .{ .id = "P25-R04", .proposal = "reverse edits mutate compiler directly", .reason = "§15 semantic transactions only" },
    .{ .id = "P25-R05", .proposal = "syntax-first metaprogramming default", .reason = "§18 semantic objects preferred" },
    .{ .id = "P25-R07", .proposal = "arbitrary unique live-out inference (P23-D01 naive)", .reason = "superseded by tail-demand + lineage (§5.1)" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    plan_section: []const u8,
};

pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P25-G01", .title = "Descriptors remain ordinary values + calls", .status = "partial", .plan_section = "§3" },
    .{ .id = "P25-G02", .title = "No canonical type-parameter syntax", .status = "partial", .plan_section = "§4" },
    .{ .id = "P25-G03", .title = "Tail-assignment return + consumption realization", .status = "partial", .plan_section = "§5" },
    .{ .id = "P25-G04", .title = "Five semantic categories in graph schema", .status = "partial", .plan_section = "§6" },
    .{ .id = "P25-G05", .title = "Lifetime violation diagnostics (no silent promote)", .status = "open", .plan_section = "§7" },
    .{ .id = "P25-G06", .title = "Mutation inferred as effect on views/origin", .status = "open", .plan_section = "§8" },
    .{ .id = "P25-G07", .title = "Ownership transfer + take() visibility", .status = "open", .plan_section = "§9" },
    .{ .id = "P25-G08", .title = "Region-derived lifetimes + pin constraints", .status = "open", .plan_section = "§10" },
    .{ .id = "P25-G09", .title = "Pointer provenance + explicit integer cast", .status = "open", .plan_section = "§11" },
    .{ .id = "P25-G10", .title = "Descriptor relationship values (Projection)", .status = "open", .plan_section = "§12" },
    .{ .id = "P25-G11", .title = "Bidirectional levels 0–2 + transaction schema", .status = "partial", .plan_section = "§13–§15" },
    .{ .id = "P25-G12", .title = "Authority + ambiguity on reverse edits", .status = "open", .plan_section = "§16" },
    .{ .id = "P25-G13", .title = "Projection provenance reuses semantic graph", .status = "partial", .plan_section = "§17" },
    .{ .id = "P25-G14", .title = "View + @all disjointness proofs (Pass 24)", .status = "open", .plan_section = "§25" },
    .{ .id = "P25-G15", .title = "Tail-demand rules A–H in semantic graph", .status = "partial", .plan_section = "§5.1" },
    .{ .id = "P25-G16", .title = "Loop/branch carried-value phi + ambiguity diagnostics", .status = "partial", .plan_section = "§5.1" },
};

pub const GuidingRule = struct {
    id: []const u8,
    question: []const u8,
};

/// Pass 25 §2 — ten guiding rules.
pub const guiding_rules: []const GuidingRule = &.{
    .{ .id = "P25-Q01", .question = "Can this be expressed as an ordinary function?" },
    .{ .id = "P25-Q02", .question = "Can this be expressed as an ordinary descriptor?" },
    .{ .id = "P25-Q03", .question = "Can this be expressed as a protocol or metatable?" },
    .{ .id = "P25-Q04", .question = "Can the compiler infer it?" },
    .{ .id = "P25-Q05", .question = "Can this reuse @ rather than inventing new syntax?" },
    .{ .id = "P25-Q06", .question = "Does this reduce concepts?" },
    .{ .id = "P25-Q07", .question = "Does it preserve Lua familiarity?" },
    .{ .id = "P25-Q08", .question = "Does it improve optimization opportunities?" },
    .{ .id = "P25-Q09", .question = "Does it improve AI reasoning?" },
    .{ .id = "P25-Q10", .question = "Does it improve semantic density?" },
};

pub fn writePass25Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass25":{{"pass":25,"mission":"Native semantic unification, lifetimes, bidirectional meta, descriptor reconciliation","schema":"{s}","plan":"{s}","index":"{s}","workstreams":[
    , .{ SCHEMA_VERSION, PLAN_PATH, INDEX_PATH });
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
        \\],"rejected_syntax_count":{d},"guiding_rules_count":{d},"invariants":["ordinary-descriptors","no-type-parameters","provenance-not-syntax","views-not-borrows","transactions-not-direct-mutation","zero-cost-bidirectional-unused"]}}
    , .{ rejected_syntax.len, guiding_rules.len });
}

test "pass25_catalog: writePass25Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass25Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P25-WS0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P25-G16") != null);
}
