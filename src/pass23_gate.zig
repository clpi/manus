//! Pass 23 native gate proofs — protocol registry + canonical syntax smoke (M0).
const std = @import("std");
const pass23_catalog = @import("pass23_catalog.zig");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");
const conversion_graph = @import("conversion_graph.zig");
const dnir_lower = @import("dnir_lower.zig");
const semantic_graph = @import("semantic_graph.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const ast = @import("ast.zig");

pub const GateError = error{ GateFailed };

pub fn validatePass23Catalog() GateError!void {
    if (!std.mem.eql(u8, pass23_catalog.SCHEMA_VERSION, "pass23-catalog-v0")) return error.GateFailed;
    if (pass23_catalog.workstreams.len != 16) return error.GateFailed;
    if (pass23_catalog.migration_targets.len != 8) return error.GateFailed;
    if (pass23_catalog.deferred_designs.len != 3) return error.GateFailed;
    if (pass23_catalog.completion_gates.len != 20) return error.GateFailed;
}

/// Gate G10 partial — Lua metamethod aliases map to canonical kernel names.
pub fn proveProtocolRegistry() GateError!void {
    if (!std.mem.eql(u8, pass23_protocol_registry.SCHEMA_VERSION, "pass23-protocol-registry-v0")) return error.GateFailed;
    if (pass23_protocol_registry.kernelOpCount() < 40) return error.GateFailed;
    if (pass23_protocol_registry.lua_aliases.len < 16) return error.GateFailed;

    const add = pass23_protocol_registry.canonicalOfLuaMetamethod("__add") orelse return error.GateFailed;
    if (!std.mem.eql(u8, add, "add")) return error.GateFailed;
    const fmt = pass23_protocol_registry.canonicalOfLuaMetamethod("__tostring") orelse return error.GateFailed;
    if (!std.mem.eql(u8, fmt, "format")) return error.GateFailed;
    if (pass23_protocol_registry.canonicalOfLuaMetamethod("__nope") != null) return error.GateFailed;

    for (pass23_protocol_registry.lua_aliases) |a| {
        if (!pass23_protocol_registry.isKernelOp(a.canonical)) return error.GateFailed;
    }
    if (pass23_protocol_registry.derive_metamethod_bindings.len < 16) return error.GateFailed;
    if (!std.mem.eql(u8, pass23_protocol_registry.resolveToLuaMetamethod("add"), "__add")) return error.GateFailed;
    if (!std.mem.eql(u8, pass23_protocol_registry.resolveToLuaMetamethod("format"), "__tostring")) return error.GateFailed;
    if (pass23_protocol_registry.runtime_binop_bindings.len < 12) return error.GateFailed;
    for (pass23_protocol_registry.runtime_binop_bindings) |b| {
        if (pass23_protocol_registry.luaMetamethodForKernel(b.op) == null) return error.GateFailed;
    }
    if (pass23_protocol_registry.runtime_metafield_bindings.len < 11) return error.GateFailed;
    for (pass23_protocol_registry.runtime_metafield_bindings) |b| {
        if (pass23_protocol_registry.findLuaAlias(b.lua_metamethod) == null) return error.GateFailed;
    }
}

/// Gate G19 — P23-D01 superseded by Pass 25 tail-demand propagation (not naive deferral).
pub fn proveDeferredAccumulatorRegistry() GateError!void {
    var saw_d01 = false;
    var saw_rejected_return = false;
    for (pass23_catalog.deferred_designs) |d| {
        if (std.mem.eql(u8, d.id, "P23-D01")) {
            saw_d01 = true;
            if (!std.mem.eql(u8, d.status, "superseded")) return error.GateFailed;
            if (std.mem.indexOf(u8, d.note, "Pass 25") == null) return error.GateFailed;
        }
        if (std.mem.indexOf(u8, d.title, "@return") != null or std.mem.indexOf(u8, d.note, "@return") != null) {
            if (std.mem.eql(u8, d.status, "rejected")) saw_rejected_return = true;
        }
    }
    if (!saw_d01 or !saw_rejected_return) return error.GateFailed;
}

/// Gate G02/G03 partial — trailing assignment expression is the block return value.
pub fn proveTrailingAssignReturn(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\add_named = (a, b): i64
        \\    sum = a + b
        \\end
    ;
    var lex = Lexer.init(src, "gate23_add_named.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (fd.func.body.tail_expr != null) return error.GateFailed;
    if (fd.func.body.stmts.len != 1 or fd.func.body.stmts[0] != .assign) return error.GateFailed;
    const val = fd.func.body.stmts[0].assign.values[0];
    if (val.* != .binop or val.binop.op != ast.BinOp.add) return error.GateFailed;
}

/// Gate G02 partial — compound assignment lowers to binop value returned implicitly.
pub fn proveCompoundAssignReturn(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\double = (x): i64
        \\    x *= 2
        \\end
    ;
    var lex = Lexer.init(src, "gate23_double.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (fd.func.body.stmts.len != 1 or fd.func.body.stmts[0] != .assign) return error.GateFailed;
    const as = fd.func.body.stmts[0].assign;
    if (as.targets.len != 1 or as.values.len != 1) return error.GateFailed;
    const val = as.values[0];
    if (val.* != .binop or val.binop.op != ast.BinOp.mul) return error.GateFailed;
    if (as.targets[0].* != .name or !std.mem.eql(u8, as.targets[0].name.ident, "x")) return error.GateFailed;
}

/// Gate G04 partial — colon method assignment + implicit self param.
pub fn proveColonMethodAssign(alloc: std.mem.Allocator) GateError!void {
    const src = "Person:greet = (other) \"Hey \" .. other";
    var lex = Lexer.init(src, "gate23_greet.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1 or mod.body.stmts[0] != .func_decl) return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (!fd.method) return error.GateFailed;
    if (fd.path.len != 2) return error.GateFailed;
    if (!std.mem.eql(u8, fd.path[0], "Person") or !std.mem.eql(u8, fd.path[1], "greet")) return error.GateFailed;
    if (fd.func.params.len != 2) return error.GateFailed;
    if (!std.mem.eql(u8, fd.func.params[0].name, "self")) return error.GateFailed;
    if (!std.mem.eql(u8, fd.func.params[1].name, "other")) return error.GateFailed;

    var sema = Sema.init(alloc);
    sema.check_module(&mod) catch return error.GateFailed;
    if (sema.errors != 0) return error.GateFailed;
    const fb = &mod.body.stmts[0].func_decl.func;
    if (!fb.is_typed) return error.GateFailed;
    if (fb.params[0].typ != .named or !std.mem.eql(u8, fb.params[0].typ.named, "str")) return error.GateFailed;
    if (fb.params[1].typ != .named or !std.mem.eql(u8, fb.params[1].typ.named, "str")) return error.GateFailed;
    if (fb.ret_type != .named or !std.mem.eql(u8, fb.ret_type.named, "str")) return error.GateFailed;
}

/// Gate G04 partial — colon method with single-line compound field assign body.
pub fn proveColonMethodCompoundFieldAssign(alloc: std.mem.Allocator) GateError!void {
    const src = "Vec:xplus = (amt): i32 self.x += amt";
    var lex = Lexer.init(src, "gate23_xplus.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1 or mod.body.stmts[0] != .func_decl) return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (!fd.method) return error.GateFailed;
    if (fd.path.len != 2) return error.GateFailed;
    if (!std.mem.eql(u8, fd.path[0], "Vec") or !std.mem.eql(u8, fd.path[1], "xplus")) return error.GateFailed;
    if (fd.func.params.len != 2) return error.GateFailed;
    if (!std.mem.eql(u8, fd.func.params[0].name, "self")) return error.GateFailed;
    if (!std.mem.eql(u8, fd.func.params[1].name, "amt")) return error.GateFailed;
    const body = fd.func.body;
    if (body.stmts.len != 1 or body.stmts[0] != .assign) return error.GateFailed;
    const as = body.stmts[0].assign;
    if (as.targets.len != 1 or as.values.len != 1) return error.GateFailed;
    if (as.targets[0].* != .field) return error.GateFailed;
    const val = as.values[0];
    if (val.* != .binop or val.binop.op != ast.BinOp.add) return error.GateFailed;
}

/// Gate G04 partial — colon compound field assign sema with record descriptor.
pub fn proveColonMethodCompoundFieldAssignSema(alloc: std.mem.Allocator) GateError!void {
    const src = "Vec: @{ x: i32 }\nVec:xplus = (amt): i32\n    self.x += amt\nend";
    var lex = Lexer.init(src, "gate23_xplus_sema.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 2) return error.GateFailed;
    var sema = Sema.init(alloc);
    sema.check_module(&mod) catch return error.GateFailed;
    if (sema.errors != 0) return error.GateFailed;
    const fb = &mod.body.stmts[1].func_decl.func;
    if (!fb.is_typed) return error.GateFailed;
    if (fb.params[0].typ != .named or !std.mem.eql(u8, fb.params[0].typ.named, "Vec")) return error.GateFailed;
    if (fb.params[1].typ != .named or !std.mem.eql(u8, fb.params[1].typ.named, "i32")) return error.GateFailed;
    if (fb.ret_type != .named or !std.mem.eql(u8, fb.ret_type.named, "i32")) return error.GateFailed;
}

/// Gate G04 partial — DNIR lowers colon method compound field assign as `Type.method`.
pub fn proveDnirColonMethodCompoundField(alloc: std.mem.Allocator) GateError!void {
    const src = "Vec: @{ x: i32 }\nVec:xplus = (amt): i32\n    self.x += amt\nend";
    var lex = Lexer.init(src, "gate23_xplus_dnir.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = parser.parse_module() catch return error.GateFailed;
    var sema = Sema.init(alloc);
    sema.check_module(&mod) catch return error.GateFailed;
    if (sema.errors != 0) return error.GateFailed;
    const m = dnir_lower.lowerModule(alloc, &mod) catch return error.GateFailed;
    var saw_xplus = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "Vec.xplus")) continue;
        saw_xplus = true;
        if (f.ret != .i32) return error.GateFailed;
        var ret_count: usize = 0;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .ret) ret_count += 1;
            }
        }
        if (ret_count != 1) return error.GateFailed;
    }
    if (!saw_xplus) return error.GateFailed;
}

/// Gate G04 partial — dot static member `math.add` lowers to DNIR `math.add`.
pub fn proveDnirDotStaticMemberAssign(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "gate23_math_add.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    const m = dnir_lower.lowerModule(alloc, &mod) catch return error.GateFailed;
    var saw_math_add = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "math.add")) continue;
        saw_math_add = true;
        if (f.ret != .i64) return error.GateFailed;
        if (f.params.len != 2) return error.GateFailed;
        if (!std.mem.eql(u8, f.params[0].name, "a")) return error.GateFailed;
        if (!std.mem.eql(u8, f.params[1].name, "b")) return error.GateFailed;
    }
    if (!saw_math_add) return error.GateFailed;
}

/// Gate G09 partial — `{ident}` in string literals desugar to `..` concat at parse time.
pub fn proveStringInterpolation(alloc: std.mem.Allocator) GateError!void {
    const src = "Person:greet = (other) \"Hey {other}\"";
    var lex = Lexer.init(src, "gate23_interp.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = parser.parse_module() catch return error.GateFailed;
    const tail = mod.body.stmts[0].func_decl.func.body.tail_expr orelse return error.GateFailed;
    if (tail.* != .binop or tail.binop.op != ast.BinOp.concat) return error.GateFailed;
    const lhs = tail.binop.lhs;
    const rhs = tail.binop.rhs;
    if (lhs.* != .string_lit or !std.mem.eql(u8, lhs.string_lit.val, "Hey ")) return error.GateFailed;
    if (rhs.* != .name or !std.mem.eql(u8, rhs.name.ident, "other")) return error.GateFailed;

    var sema = Sema.init(alloc);
    sema.check_module(&mod) catch return error.GateFailed;
    if (sema.errors != 0) return error.GateFailed;
    const fb = &mod.body.stmts[0].func_decl.func;
    if (!fb.is_typed) return error.GateFailed;
    if (fb.ret_type != .named or !std.mem.eql(u8, fb.ret_type.named, "str")) return error.GateFailed;
}

/// Gate G01 partial — legacy `protocol_kernel` shim delegates to the canonical registry.
pub fn proveProtocolKernelCompat() GateError!void {
    const kernel = @import("protocol_kernel.zig");
    for (pass23_protocol_registry.lua_aliases) |a| {
        const via_shim = kernel.resolveLuaAlias(a.lua_metamethod) orelse return error.GateFailed;
        if (via_shim != a.op) return error.GateFailed;
    }
    if (kernel.resolveName("multiply") != .multiply) return error.GateFailed;
    if (kernel.resolveLuaAlias("__nope") != null) return error.GateFailed;
}

/// Gate G08 partial — unified conversion graph registers directed edges.
pub fn proveConversionGraph(alloc: std.mem.Allocator) GateError!void {
    if (!std.mem.eql(u8, conversion_graph.SCHEMA_VERSION, "conversion-graph-v0")) return error.GateFailed;
    var g = conversion_graph.initGraph(alloc);
    conversion_graph.registerEdge(alloc, &g, "Person", "Employee", .checked, .target_owned) catch return error.GateFailed;
    const edge = g.find("Person", "Employee") orelse return error.GateFailed;
    if (edge.category != .checked) return error.GateFailed;
    if (g.find("Employee", "Person") != null) return error.GateFailed;
}

/// Gate G01 — canonical single-expression assign func: add = (a, b) a + b
pub fn proveSingleExprAssignFunc(alloc: std.mem.Allocator) GateError!void {
    const src = "add = (a, b) a + b";
    var lex = Lexer.init(src, "gate23_add_single.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1) return error.GateFailed;
    if (mod.body.stmts[0] != .func_decl) return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (!std.mem.eql(u8, fd.path[0], "add")) return error.GateFailed;
    if (fd.func.params.len != 2) return error.GateFailed;
    const tail = fd.func.body.tail_expr orelse return error.GateFailed;
    if (tail.* != .binop or tail.binop.op != ast.BinOp.add) return error.GateFailed;
}

/// Gate G01 partial — assign-form multiline function parses (canonical direction).
pub fn proveAssignFuncMultiline(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\add = (a: i64, b: i64): i64
        \\    a + b
        \\end
    ;
    var lex = Lexer.init(src, "gate23_add.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1) return error.GateFailed;
    if (mod.body.stmts[0] != .func_decl) return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (!std.mem.eql(u8, fd.path[0], "add")) return error.GateFailed;
    if (fd.func.params.len != 2) return error.GateFailed;
}

/// Gate G05 partial — func_expr in assignment converges on func_decl (one representation at parse).
pub fn proveFuncExprAssignConvergence(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\scale = (x: f64): f64
        \\    x * 2.0
        \\end
    ;
    var lex = Lexer.init(src, "gate23_scale.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts[0] != .func_decl) return error.GateFailed;
}

/// Gate G15 partial — call sites record return consumption from syntactic context.
pub fn proveReturnConsumption(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\discard_fn = ()
        \\    side()
        \\    _stub = 0
        \\end
        \\
        \\assign_fn = ()
        \\    x = fetch_one()
        \\end
        \\
        \\tail_fn = ()
        \\    fetch_two()
        \\end
    ;
    var lex = Lexer.init(src, "gate23_return_consumption.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = graph.liftModuleWithCalls(&mod, "gate23_return_consumption.duo") catch return error.GateFailed;

    var saw_discard = false;
    var saw_single_assign = false;
    var saw_single_tail = false;
    for (graph.nodes.items) |node| {
        if (node.kind != .call) continue;
        const cs = node.call_shape orelse continue;
        const name = cs.callee_name orelse continue;
        if (std.mem.eql(u8, name, "side") and cs.return_consumption == .discard) saw_discard = true;
        if (std.mem.eql(u8, name, "fetch_one") and cs.return_consumption == .single) saw_single_assign = true;
        if (std.mem.eql(u8, name, "fetch_two") and cs.return_consumption == .single) saw_single_tail = true;
    }
    if (!saw_discard or !saw_single_assign or !saw_single_tail) return error.GateFailed;
}

/// Gate G03 partial — `if name = expr` binding condition desugars to assign + test.
pub fn proveIfBindingAssign(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\if v = get() v > 0
        \\  noop(v)
        \\end
    ;
    var lex = Lexer.init(src, "gate23_if_bind.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    if (mod.body.stmts.len != 1 or mod.body.stmts[0] != .if_stmt) return error.GateFailed;
    const is = mod.body.stmts[0].if_stmt;
    if (is.binding == null) return error.GateFailed;
    if (!std.mem.eql(u8, is.binding.?.name, "v")) return error.GateFailed;
    if (is.binding.?.expr.* != .call) return error.GateFailed;
    if (is.cond.* != .name or !std.mem.eql(u8, is.cond.name.ident, "v")) return error.GateFailed;
}

/// Gate G15 partial — DNIR lowering discards statement-position call results.
pub fn proveDnirReturnConsumption(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\side(): i64
        \\    0
        \\end
        \\main(): i64
        \\    side();
        \\    1
        \\end
    ;
    var lex = Lexer.init(src, "gate23_dnir_discard.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    const m = dnir_lower.lowerModule(alloc, &mod) catch return error.GateFailed;
    var saw_discard = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "side") and ins.result == null) {
                    saw_discard = true;
                }
            }
        }
    }
    if (!saw_discard) return error.GateFailed;
}

/// Gate G16 partial — migration targets registered for legacy surfaces.
pub fn proveMigrationTargetsRegistered() GateError!void {
    var saw_concept = false;
    var saw_lua = false;
    for (pass23_catalog.migration_targets) |m| {
        if (std.mem.indexOf(u8, m.legacy, "ConceptDef") != null) saw_concept = true;
        if (std.mem.indexOf(u8, m.legacy, "Lua") != null) saw_lua = true;
    }
    if (!saw_concept or !saw_lua) return error.GateFailed;
}

pub fn validatePass23Gate() GateError!void {
    try validatePass23Catalog();
    try proveProtocolRegistry();
    try proveProtocolKernelCompat();
    try proveDeferredAccumulatorRegistry();
    try proveMigrationTargetsRegistered();
    try proveConversionGraph(std.heap.page_allocator);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try proveSingleExprAssignFunc(arena.allocator());
    try proveColonMethodAssign(arena.allocator());
    try proveColonMethodCompoundFieldAssign(arena.allocator());
    try proveColonMethodCompoundFieldAssignSema(arena.allocator());
    try proveDnirColonMethodCompoundField(arena.allocator());
    try proveDnirDotStaticMemberAssign(arena.allocator());
    try proveStringInterpolation(arena.allocator());
    try proveTrailingAssignReturn(arena.allocator());
    try proveCompoundAssignReturn(arena.allocator());
    try proveReturnConsumption(arena.allocator());
    try proveIfBindingAssign(arena.allocator());
    try proveDnirReturnConsumption(arena.allocator());
    try proveAssignFuncMultiline(arena.allocator());
    try proveFuncExprAssignConvergence(arena.allocator());
}

test "pass23_gate: catalog + protocol registry + syntax smoke" {
    try validatePass23Gate();
}
