//! Pass 21 native gate proofs — keyword registry + canonical parse smoke.
const std = @import("std");
const pass21_catalog = @import("pass21_catalog.zig");
const pass21_keyword_registry = @import("pass21_keyword_registry.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub const GateError = error{ GateFailed };

pub fn validatePass21Catalog() GateError!void {
    if (!std.mem.eql(u8, pass21_catalog.SCHEMA_VERSION, "pass21-catalog-v0")) return error.GateFailed;
    if (pass21_catalog.workstreams.len != 9) return error.GateFailed;
    if (pass21_catalog.grammar_audits.len != 7) return error.GateFailed;
    if (pass21_catalog.completion_gates.len != 20) return error.GateFailed;
}

/// Gate keyword registry invariants (Phase 1 partial).
pub fn proveKeywordRegistry() GateError!void {
    if (!std.mem.eql(u8, pass21_keyword_registry.SCHEMA_VERSION, "pass21-keyword-registry-v0")) return error.GateFailed;
    if (pass21_keyword_registry.keywords.len != 54) return error.GateFailed;

    const then_kw = pass21_keyword_registry.find("then") orelse return error.GateFailed;
    if (then_kw.lifecycle != .supported_compatibility) return error.GateFailed;
    if (then_kw.classification != .lua_compatibility) return error.GateFailed;

    const do_kw = pass21_keyword_registry.find("do") orelse return error.GateFailed;
    if (do_kw.lifecycle != .supported_compatibility) return error.GateFailed;

    const match_kw = pass21_keyword_registry.find("match") orelse return error.GateFailed;
    if (match_kw.lifecycle != .deprecated) return error.GateFailed;

    const local_kw = pass21_keyword_registry.find("local") orelse return error.GateFailed;
    if (local_kw.lifecycle != .supported_compatibility) return error.GateFailed;

    // Production classify recognizes retired keywords still accepted for compatibility.
    if (duo_keyword_bridge.lookupKeyword("then") == null) return error.GateFailed;
    if (duo_keyword_bridge.lookupKeyword("match") == null) return error.GateFailed;
}

/// Gate G01 partial — canonical if parses without `then`.
pub fn proveIfWithoutThen(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\if ready
        \\    run()
        \\end
    ;
    var lex = Lexer.init(src, "gate21_if.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1) return error.GateFailed;
    if (mod.body.stmts[0] != .if_stmt) return error.GateFailed;
}

/// Gate G02 partial — while/for parse without loop `do`.
pub fn proveLoopWithoutDo(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\while active
        \\    tick()
        \\end
        \\for item in items
        \\    use(item)
        \\end
    ;
    var lex = Lexer.init(src, "gate21_loop.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 2) return error.GateFailed;
    if (mod.body.stmts[0] != .while_loop) return error.GateFailed;
    if (mod.body.stmts[1] != .gen_for) return error.GateFailed;
}

pub fn validatePass21Gate() GateError!void {
    try validatePass21Catalog();
    try proveKeywordRegistry();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try proveIfWithoutThen(arena.allocator());
    try proveLoopWithoutDo(arena.allocator());
}

test "pass21_gate: catalog + grammar gates" {
    try validatePass21Gate();
}
