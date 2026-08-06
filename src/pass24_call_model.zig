//! Pass 24 §4 — call architecture: value reference vs explicit invocation.
//!
//! Policy (permanent):
//!   `a`     → value reference (callable or not)
//!   `a()`   → zero-argument invoke
//!   `a x`   → parenless invoke (via call object; may share bash-style parse path today)
//!   `a x,y` → multi-arg parenless invoke
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const semantic_graph = @import("semantic_graph.zig");

pub const SCHEMA_VERSION = "pass24-call-model-v1";

/// Re-export for catalog consumers.
pub const InvocationForm = ast.InvocationForm;

pub const GateError = error{ GateFailed };

fn parseDuoModule(alloc: std.mem.Allocator, src: []const u8, file: []const u8) GateError!ast.Module {
    var lex = Lexer.init(src, file);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    return parser.parse_module() catch return error.GateFailed;
}

/// Module blocks promote a trailing call/expr to `tail_expr` (see `parse_block`).
fn moduleLevelExpr(mod: *const ast.Module) ?*ast.Expr {
    if (mod.body.tail_expr) |expr| return expr;
    if (mod.body.stmts.len == 1) {
        return switch (mod.body.stmts[0]) {
            .call_stmt => |cs| cs.expr,
            .expr_stmt => |es| es.expr,
            else => null,
        };
    }
    return null;
}

/// P24-G04 — storing a callable must not invoke it.
pub fn proveCallableValueReference(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "callback = print", "gate24_callback.duo");
    if (mod.body.stmts.len != 1 or mod.body.stmts[0] != .assign) return error.GateFailed;
    const as = mod.body.stmts[0].assign;
    if (as.targets.len != 1 or as.values.len != 1) return error.GateFailed;
    if (as.targets[0].* != .name) return error.GateFailed;
    if (as.values[0].* != .name or !std.mem.eql(u8, as.values[0].name.ident, "print")) return error.GateFailed;
}

/// P24-G04 — bare name in value position remains a name, not a call.
pub fn proveBareNameValueInAssign(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "handler = save", "gate24_handler.duo");
    const as = mod.body.stmts[0].assign;
    if (as.values[0].* != .name or !std.mem.eql(u8, as.values[0].name.ident, "save")) return error.GateFailed;
}

/// P24-G04 — zero-argument parenthesized invoke (RHS of assign).
pub fn proveZeroArgParenthesizedInvoke(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "x = run()", "gate24_run.duo");
    if (mod.body.stmts.len != 1 or mod.body.stmts[0] != .assign) return error.GateFailed;
    const as = mod.body.stmts[0].assign;
    if (as.values.len != 1 or as.values[0].* != .call) return error.GateFailed;
    if (as.values[0].call.args.len != 0) return error.GateFailed;
    if (as.values[0].call.func.* != .name or !std.mem.eql(u8, as.values[0].call.func.name.ident, "run")) return error.GateFailed;
    if (as.values[0].call.form != .parenthesized) return error.GateFailed;
}

/// P24-G04 — parenless invoke uses call object (bash-style path today).
pub fn proveParenlessInvoke(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "print 'hi'", "gate24_print_hi.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .call) return error.GateFailed;
    if (expr.call.args.len != 1) return error.GateFailed;
    if (expr.call.func.* != .name or !std.mem.eql(u8, expr.call.func.name.ident, "print")) return error.GateFailed;
    if (expr.call.form != .parenless) return error.GateFailed;
}

/// P24-G04 — parenthesized Lua call remains valid.
pub fn proveParenthesizedLuaCall(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "print(\"hi\", 42)", "gate24_print_paren.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .call or expr.call.args.len != 2) return error.GateFailed;
}

/// P24-G04 — higher-order: passing callable without invoking.
pub fn proveHigherOrderCallablePassing(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "map(items, transform)", "gate24_map.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .call or expr.call.args.len != 2) return error.GateFailed;
    if (expr.call.args[1].* != .name or !std.mem.eql(u8, expr.call.args[1].name.ident, "transform")) return error.GateFailed;
}

/// P24-G04 — statement-level `name()` is explicit parenthesized invoke (not bare value reference).
pub fn proveStatementLevelZeroArgInvoke(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "run()", "gate24_run_stmt.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .call or expr.call.args.len != 0) return error.GateFailed;
    if (expr.call.func.* != .name or !std.mem.eql(u8, expr.call.func.name.ident, "run")) return error.GateFailed;
    if (expr.call.form != .parenthesized) return error.GateFailed;
}

/// P24-A02 — parenless call binds tighter than binary `+`: `(f x) + y`.
pub fn proveParenlessCallPrecedence(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "f x + y", "gate24_f_x_plus_y.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .binop or expr.binop.op != .add) return error.GateFailed;
    const call = expr.binop.lhs;
    if (call.* != .call) return error.GateFailed;
    if (call.call.args.len != 1) return error.GateFailed;
    if (call.call.args[0].* != .name or !std.mem.eql(u8, call.call.args[0].name.ident, "x")) return error.GateFailed;
    if (call.call.form != .parenless) return error.GateFailed;
    const rhs = expr.binop.rhs;
    if (rhs.* != .name or !std.mem.eql(u8, rhs.name.ident, "y")) return error.GateFailed;
}

/// P24-A02 — parenthesized alternative: `f (x + y)` passes one combined argument.
pub fn proveParenlessCallExplicitGrouping(alloc: std.mem.Allocator) GateError!void {
    const mod = try parseDuoModule(alloc, "f (x + y)", "gate24_f_paren.duo");
    const expr = moduleLevelExpr(&mod) orelse return error.GateFailed;
    if (expr.* != .call or expr.call.args.len != 1) return error.GateFailed;
    const arg = expr.call.args[0];
    if (arg.* != .binop or arg.binop.op != .add) return error.GateFailed;
}

fn countCallNodesWithForm(g: *const semantic_graph.SemanticGraph, callee: []const u8, form: ast.InvocationForm) usize {
    var n: usize = 0;
    for (g.nodes.items) |node| {
        if (node.kind != .call) continue;
        const cs = node.call_shape orelse continue;
        if (cs.invocation_form != form) continue;
        if (cs.callee_name) |name| {
            if (std.mem.eql(u8, name, callee)) n += 1;
        }
    }
    return n;
}

/// P24-G06 partial — semantic graph records invocation form + return consumption; value refs are not calls.
pub fn proveSemanticGraphInvocationForms(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\callback = print
        \\worker(): i64
        \\    x = spawn()
        \\    ping 'ok'
        \\end
    ;
    const mod = try parseDuoModule(alloc, src, "gate24_graph_calls.duo");
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gate24_graph_calls.duo") catch return error.GateFailed;

    if (countCallNodesWithForm(&g, "print", .parenthesized) != 0) return error.GateFailed;
    if (countCallNodesWithForm(&g, "print", .parenless) != 0) return error.GateFailed;
    if (countCallNodesWithForm(&g, "spawn", .parenthesized) != 1) return error.GateFailed;
    if (countCallNodesWithForm(&g, "ping", .parenless) != 1) return error.GateFailed;
}

pub fn validateCallModelGate(alloc: std.mem.Allocator) GateError!void {
    try proveCallableValueReference(alloc);
    try proveBareNameValueInAssign(alloc);
    try proveStatementLevelZeroArgInvoke(alloc);
    try proveZeroArgParenthesizedInvoke(alloc);
    try proveParenlessInvoke(alloc);
    try proveParenthesizedLuaCall(alloc);
    try proveHigherOrderCallablePassing(alloc);
    try proveParenlessCallPrecedence(alloc);
    try proveParenlessCallExplicitGrouping(alloc);
    try proveSemanticGraphInvocationForms(alloc);
}

test "pass24_call_model: value vs invoke fixtures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try validateCallModelGate(arena.allocator());
}
