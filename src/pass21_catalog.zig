//! Pass 21 — canonical grammar closure catalog (`duo catalog` → `pass21`).
const std = @import("std");
const pass21_keyword_registry = @import("pass21_keyword_registry.zig");

pub const SCHEMA_VERSION = "pass21-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass21_canonical_grammar_closure.md";
pub const GRAMMAR_SPEC = "docs/GRAMMAR_SPEC.md";
pub const KEYWORD_CATALOG = "docs/catalogs/keywords.md";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 21 §46 implementation phases.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P21-WS0", .title = "Repository truth map (lexer/parser/sema/fmt/treesitter/LSP)", .status = "partial", .priority = 0, .owner = "docs/GRAMMAR_SPEC.md + src/parser.zig" },
    .{ .id = "P21-WS1", .title = "Machine-readable keyword registry", .status = "partial", .priority = 1, .owner = "src/pass21_keyword_registry.zig" },
    .{ .id = "P21-WS2", .title = "Duo canonical omit then/loop do; Lua forms permanently accepted", .status = "partial", .priority = 2, .owner = "src/parser.zig + lua_superset_catalog.zig" },
    .{ .id = "P21-WS3", .title = "Canonical scope and direct iteration", .status = "partial", .priority = 3, .owner = "src/sema.zig + GR-003" },
    .{ .id = "P21-WS4", .title = "Table-native dispatch semantics", .status = "open", .priority = 4, .owner = "src/sema.zig + src/codegen.zig" },
    .{ .id = "P21-WS5", .title = "Retire match/switch/case", .status = "open", .priority = 5, .owner = "src/parser.zig + migration" },
    .{ .id = "P21-WS6", .title = "Easy grammar wins (projections/destructuring/spread)", .status = "partial", .priority = 6, .owner = "docs/GRAMMAR_SPEC.md" },
    .{ .id = "P21-WS7", .title = "Ecosystem closure (fmt/treesitter/LSP/MCP/Ward)", .status = "open", .priority = 7, .owner = "ext/tree-sitter-duo + ~/x/duo-lsp" },
    .{ .id = "P21-WS8", .title = "Remove dead grammar", .status = "open", .priority = 8, .owner = "future" },
};

pub const GrammarAudit = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 21 §44 required audits.
pub const grammar_audits: []const GrammarAudit = &.{
    .{ .id = "P21-A", .title = "Keyword inventory", .status = "partial" },
    .{ .id = "P21-B", .title = "Control-flow grammar", .status = "partial" },
    .{ .id = "P21-C", .title = "Dispatch syntax", .status = "open" },
    .{ .id = "P21-D", .title = "Grammar duplication", .status = "open" },
    .{ .id = "P21-E", .title = "Easy syntax wins", .status = "open" },
    .{ .id = "P21-F", .title = "Ambiguity fixtures", .status = "partial" },
    .{ .id = "P21-G", .title = "Compatibility burden", .status = "open" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 21 §48 success criteria (subset tracked as gates).
pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P21-G01", .title = "Duo canonical omits then; Lua if-then-end permanently valid", .status = "partial" },
    .{ .id = "P21-G02", .title = "Duo canonical omits loop do; Lua form permanently valid", .status = "partial" },
    .{ .id = "P21-G03", .title = "standalone do explicit status", .status = "open" },
    .{ .id = "P21-G04", .title = "match/switch/case noncanonical", .status = "partial" },
    .{ .id = "P21-G05", .title = "value dispatch via tables/descriptors/calls", .status = "open" },
    .{ .id = "P21-G06", .title = "exhaustiveness without match syntax", .status = "open" },
    .{ .id = "P21-G07", .title = "safe match migration detection", .status = "open" },
    .{ .id = "P21-G08", .title = "local optional in Duo canonical; Lua local permanently valid", .status = "partial" },
    .{ .id = "P21-G09", .title = "direct iteration replaces pairs/ipairs", .status = "partial" },
    .{ .id = "P21-G10", .title = "if-expressions and binding conditions specified", .status = "partial" },
    .{ .id = "P21-G11", .title = "projection/destructuring lower to ordinary semantics", .status = "partial" },
    .{ .id = "P21-G12", .title = "no parallel semantic mechanisms for shorthands", .status = "open" },
    .{ .id = "P21-G13", .title = "parser/formatter/treesitter/LSP/MCP grammar agreement", .status = "open" },
    .{ .id = "P21-G14", .title = "deterministic idempotent canonicalization", .status = "open" },
    .{ .id = "P21-G15", .title = "compatibility lifecycle records", .status = "partial" },
    .{ .id = "P21-G16", .title = "Ward descriptor/table dispatch proof", .status = "open" },
    .{ .id = "P21-G17", .title = "keyword/production count reduction", .status = "open" },
    .{ .id = "P21-G18", .title = "optimization opportunities preserved or improved", .status = "open" },
    .{ .id = "P21-G19", .title = "Lua-evolved identity preserved", .status = "partial" },
    .{ .id = "P21-G20", .title = "one compact grammar over one semantic system", .status = "open" },
};

pub fn writePass21Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass21":{{"pass":21,"mission":"Canonical grammar closure, keyword retirement, table-native dispatch","schema":"{s}","plan":"{s}","grammar_spec":"{s}","keyword_catalog":"{s}","keyword_registry":"{s}","keyword_count":{d},"canonical_target":{d},"canonical_current":{d},"workstreams":[
    , .{
        SCHEMA_VERSION,
        PLAN_PATH,
        GRAMMAR_SPEC,
        KEYWORD_CATALOG,
        pass21_keyword_registry.SCHEMA_VERSION,
        pass21_keyword_registry.keywords.len,
        pass21_keyword_registry.CANONICAL_TARGET_COUNT,
        pass21_keyword_registry.countCanonical(),
    });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}","priority":{d},"owner":"{s}"}}
        , .{ ws.id, ws.title, ws.status, ws.priority, ws.owner });
    }
    try w.print("],\"grammar_audits\":[", .{});
    for (grammar_audits, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ a.id, a.title, a.status });
    }
    try w.print("],\"completion_gates\":[", .{});
    for (completion_gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            \\{{"id":"{s}","title":"{s}","status":"{s}"}}
        , .{ g.id, g.title, g.status });
    }
    try w.print(
        \\],"invariants":["table-native-dispatch","no-second-pattern-language","compiler-owns-grammar","preserve-lua-familiarity"]}}
    , .{});
}

test "pass21_catalog: schema and counts" {
    try std.testing.expectEqualStrings("pass21-catalog-v0", SCHEMA_VERSION);
    try std.testing.expectEqual(@as(usize, 9), workstreams.len);
    try std.testing.expectEqual(@as(usize, 7), grammar_audits.len);
    try std.testing.expectEqual(@as(usize, 20), completion_gates.len);
}
