//! Lua superset gate — long-bracket preservation + compatibility contract proofs.
const std = @import("std");
const lua_superset_catalog = @import("lua_superset_catalog.zig");
const lua_superset_corpus = @import("lua_superset_corpus.zig");
const pass21_keyword_registry = @import("pass21_keyword_registry.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub const GateError = error{ GateFailed };

pub fn validateCatalog() GateError!void {
    if (!std.mem.eql(u8, lua_superset_catalog.SCHEMA_VERSION, "lua-superset-catalog-v0")) return error.GateFailed;
    if (lua_superset_catalog.constructs.len < 10) return error.GateFailed;
    if (lua_superset_catalog.deprecation_threshold.len != 6) return error.GateFailed;
    if (lua_superset_catalog.workstreams.len != 10) return error.GateFailed;
    if (lua_superset_catalog.permanentLuaConstructCount() < 8) return error.GateFailed;

    for (lua_superset_catalog.constructs) |c| {
        if (c.permanent_lua and c.classification == .actually_deprecated) return error.GateFailed;
        if (c.permanent_lua and !c.accepted) return error.GateFailed;
    }

    const ls0 = lua_superset_catalog.findConstruct("LS-0") orelse return error.GateFailed;
    if (ls0.classification != .lua_and_duo_canonical) return error.GateFailed;
}

/// Long strings must never be marked deprecated in any registry entry.
pub fn proveLongStringNotDeprecated() GateError!void {
    for (lua_superset_catalog.constructs) |c| {
        if (std.mem.indexOf(u8, c.construct, "long string") != null or std.mem.indexOf(u8, c.construct, "long comment") != null) {
            if (c.classification == .actually_deprecated) return error.GateFailed;
            if (!c.accepted or !c.same_semantics) return error.GateFailed;
        }
    }
}

/// Lua keywords then/do/local remain supported compatibility — not deprecated for shorter Duo forms.
pub fn proveLuaKeywordsNotCasuallyDeprecated() GateError!void {
    const then_kw = pass21_keyword_registry.find("then") orelse return error.GateFailed;
    if (then_kw.lifecycle == .deprecated or then_kw.lifecycle == .removed) return error.GateFailed;
    if (then_kw.classification != .lua_compatibility) return error.GateFailed;

    const do_kw = pass21_keyword_registry.find("do") orelse return error.GateFailed;
    if (do_kw.lifecycle == .deprecated or do_kw.lifecycle == .removed) return error.GateFailed;

    const local_kw = pass21_keyword_registry.find("local") orelse return error.GateFailed;
    if (local_kw.lifecycle == .deprecated or local_kw.lifecycle == .removed) return error.GateFailed;
}

fn expectLongString(src: []const u8, expected: []const u8) GateError!void {
    var lex = Lexer.init(src, "gate_long.duo");
    const tok = lex.next() catch return error.GateFailed;
    if (tok.kind != .string_lit) return error.GateFailed;
    if (!std.mem.eql(u8, tok.text, expected)) return error.GateFailed;
}

/// P0 — full long-bracket family with delimiter matching.
pub fn proveLongBracketLexing() GateError!void {
    try expectLongString("[[hello]]", "hello");
    try expectLongString("[=[content]=]", "content");
    try expectLongString("[==[text]==]", "text");
    try expectLongString("[=[contains ]] without ending]=]", "contains ]] without ending");
    try expectLongString("[==[text containing ]=]]==]", "text containing ]=]");
}

/// Long comments skip without producing tokens.
pub fn proveLongCommentLexing() GateError!void {
    var lex = Lexer.init("--[[ block comment ]]\nx = 1", "gate_lc.duo");
    const tok = lex.next() catch return error.GateFailed;
    if (tok.kind != .name or !std.mem.eql(u8, tok.text, "x")) return error.GateFailed;

    var lex2 = Lexer.init("--[=[ comment with ]] inside ]=]\ny = 2", "gate_lc1.duo");
    const tok2 = lex2.next() catch return error.GateFailed;
    if (tok2.kind != .name or !std.mem.eql(u8, tok2.text, "y")) return error.GateFailed;
}

/// Shell boundary: outer long string holds inner Bash [[ ... ]] (level-1 delimiter required).
pub fn proveShellBoundaryLongString(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\script = [=[
        \\if [[ -f "$file" ]]; then
        \\    echo "$file"
        \\fi
        \\]=]
    ;
    var lex = Lexer.init(src, "gate_shell.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1) return error.GateFailed;
    if (mod.body.stmts[0] != .assign) return error.GateFailed;
}

/// Lua if-with-then remains valid Duo.
pub fn proveLuaIfWithThen(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\if ready then
        \\    run()
        \\end
    ;
    var lex = Lexer.init(src, "gate_lua_if.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1) return error.GateFailed;
    if (mod.body.stmts[0] != .if_stmt) return error.GateFailed;
}

/// P1 — repository corpus accepts canonical Lua constructs.
pub fn proveCompatibilityCorpus(alloc: std.mem.Allocator) GateError!void {
    if (!std.mem.eql(u8, lua_superset_corpus.SCHEMA_VERSION, "lua-superset-corpus-v0")) return error.GateFailed;
    if (lua_superset_corpus.lex_cases.len < 5) return error.GateFailed;
    if (lua_superset_corpus.parse_cases.len < 6) return error.GateFailed;
    lua_superset_corpus.validateCorpus(alloc) catch return error.GateFailed;
}

pub fn validateLuaSupersetGate() GateError!void {
    try validateCatalog();
    try proveLongStringNotDeprecated();
    try proveLuaKeywordsNotCasuallyDeprecated();
    try proveLongBracketLexing();
    try proveLongCommentLexing();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try proveShellBoundaryLongString(arena.allocator());
    try proveLuaIfWithThen(arena.allocator());
    try proveCompatibilityCorpus(arena.allocator());
}

test "lua_superset_gate: full gate" {
    try validateLuaSupersetGate();
}
