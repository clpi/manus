//! Bounded ambient-world ingress normalization.
//!
//! `()` is ordinary application and `[]` is computed/indexed projection. This
//! pass must never reinterpret a general call as an index after sema. In
//! particular, `table(key)` remains a call even when the callee currently has an
//! array/table descriptor; compatibility cannot change an occurrence's semantic
//! category from application to projection.
//!
//! The only remaining rewrites are explicit migration faces of the injected OS
//! world (`arg`, `env`, `cwd`, process relations). They converge historical
//! spellings onto the already-supported anchored world projection while a local
//! or declared binding always wins. This is ingress compatibility, not permanent
//! Idol semantics; graph-owned world-member ids delete it.

const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");
const subject_home = @import("subject_home.zig");

const BoundNames = struct {
    bound: std.StringHashMap(void),

    fn init(alloc: std.mem.Allocator) BoundNames {
        return .{ .bound = std.StringHashMap(void).init(alloc) };
    }

    fn deinit(self: *BoundNames) void {
        self.bound.deinit();
    }

    fn add(self: *BoundNames, name: []const u8) void {
        self.bound.put(name, {}) catch {};
    }

    fn has(self: *const BoundNames, name: []const u8) bool {
        return self.bound.contains(name);
    }
};

fn argProjection(func: *const ast.Expr) bool {
    const is_arg = struct {
        fn f(name: []const u8) bool {
            return std.mem.eql(u8, name, "arg") or std.mem.eql(u8, name, "args");
        }
    }.f;
    return switch (func.*) {
        .field => |f| f.obj.* == .name and
            std.mem.eql(u8, f.obj.name.ident, "os") and is_arg(f.field),
        else => false,
    };
}

fn bareMember(names: *const BoundNames, func: *const ast.Expr) ?subject_home.OsMember {
    if (func.* != .name) return null;
    if (names.has(func.name.ident)) return null;
    return switch (subject_home.bareReach(func.name.ident)) {
        .one => |world| if (world == .os) subject_home.osDotMember(func.name.ident) else null,
        .none, .ambiguous => null,
    };
}

fn anchoredMember(names: *const BoundNames, func: *const ast.Expr) ?subject_home.OsMember {
    if (func.* != .field) return null;
    const f = func.field;
    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "os")) return null;
    if (names.has("os")) return null;
    return subject_home.osDotMember(f.field);
}

fn isApplicationFace(form: ast.InvocationForm) bool {
    return switch (form) {
        .parenthesized, .parenless, .braced, .command => true,
        .receiver_parenthesized, .receiver_parenless => true,
        .value_reference, .indirect => false,
    };
}

fn envAnchor(func: *const ast.Expr) bool {
    return func.* == .field and func.field.obj.* == .name and
        std.mem.eql(u8, func.field.obj.name.ident, "os") and
        std.mem.eql(u8, func.field.field, "env");
}

fn envRemovalSubject(names: *const BoundNames, obj: *const ast.Expr) bool {
    return switch (obj.*) {
        .field => |f| f.obj.* == .name and
            std.mem.eql(u8, f.obj.name.ident, "os") and
            std.mem.eql(u8, f.field, "env") and !names.has("os"),
        .name => |n| std.mem.eql(u8, n.ident, "env") and !names.has("env"),
        else => false,
    };
}

fn worldTable(alloc: std.mem.Allocator, loc: ast.Loc, member: []const u8) !*ast.Expr {
    const os_name = try alloc.create(ast.Expr);
    os_name.* = .{ .name = .{ .loc = loc, .ident = "os" } };
    const field = try alloc.create(ast.Expr);
    field.* = .{ .field = .{ .loc = loc, .obj = os_name, .field = member } };
    return field;
}

fn argTable(alloc: std.mem.Allocator, loc: ast.Loc) !*ast.Expr {
    return worldTable(alloc, loc, "args");
}

fn bindPattern(names: *BoundNames, pattern: ast.Pattern) void {
    switch (pattern) {
        .binding => |b| names.add(b.name),
        .rest => |name| names.add(name),
        .variant => |v| if (v.payload) |payload| {
            for (payload) |child| bindPattern(names, child);
        },
        .table_destr => |entries| for (entries) |entry| bindPattern(names, entry.pat),
        .array_destr => |patterns| for (patterns) |child| bindPattern(names, child),
        .literal, .wildcard => {},
    }
}

fn collectExpr(names: *BoundNames, expr: *const ast.Expr) void {
    switch (expr.*) {
        .index => |x| {
            collectExpr(names, x.obj);
            collectExpr(names, x.key);
        },
        .field => |x| collectExpr(names, x.obj),
        .call => |x| {
            collectExpr(names, x.func);
            for (x.args) |arg| collectExpr(names, arg);
        },
        .method_call => |x| {
            collectExpr(names, x.obj);
            for (x.args) |arg| collectExpr(names, arg);
        },
        .binop => |x| {
            collectExpr(names, x.lhs);
            collectExpr(names, x.rhs);
        },
        .unop => |x| collectExpr(names, x.operand),
        .try_expr => |x| collectExpr(names, x.operand),
        .unwrap_expr => |x| collectExpr(names, x.operand),
        .await_expr => |x| collectExpr(names, x.operand),
        .quote => |x| collectExpr(names, x.expr),
        .unquote => |x| collectExpr(names, x.expr),
        .contains_expr => |x| {
            collectExpr(names, x.lhs);
            collectExpr(names, x.rhs);
        },
        .if_expr => |x| {
            collectExpr(names, x.cond);
            collectExpr(names, x.then_expr);
            collectExpr(names, x.else_expr);
        },
        .sequence => |x| for (x.exprs) |child| collectExpr(names, child),
        .range => |x| {
            collectExpr(names, x.start);
            collectExpr(names, x.end);
            if (x.step) |step| collectExpr(names, step);
        },
        .macro_call => |x| for (x.args) |arg| collectExpr(names, arg),
        .table => |x| for (x.fields) |field| switch (field) {
            .positional => |value| collectExpr(names, value),
            .named => |value| collectExpr(names, value.val),
            .semantic => |value| collectExpr(names, value.val),
            .spread => |value| collectExpr(names, value),
            .indexed => |value| {
                collectExpr(names, value.key);
                collectExpr(names, value.val);
            },
        },
        .match_expr => |x| {
            collectExpr(names, x.scrutinee);
            for (x.arms) |arm| {
                bindPattern(names, arm.pattern);
                if (arm.guard) |guard| collectExpr(names, guard);
                collectBlock(names, &arm.body);
            }
        },
        .func_expr => |x| {
            for (x.params) |param| names.add(param.name);
            collectBlock(names, &x.body);
        },
        else => {},
    }
}

fn collectBlock(names: *BoundNames, block: *const ast.Block) void {
    for (block.stmts) |*statement| collectStmt(names, statement);
    if (block.tail_expr) |tail| collectExpr(names, tail);
}

fn collectLocalNames(names: *BoundNames, locals: []const ast.LocalName) void {
    for (locals) |local| names.add(local.ident);
}

fn collectStmt(names: *BoundNames, statement: *const ast.Stmt) void {
    switch (statement.*) {
        .local_decl => |decl| {
            collectLocalNames(names, decl.names);
            for (decl.inits) |init| collectExpr(names, init);
        },
        .const_decl => |decl| {
            names.add(decl.ident);
            collectExpr(names, decl.val);
        },
        .global_decl => |decl| {
            collectLocalNames(names, decl.names);
            for (decl.inits) |init| collectExpr(names, init);
        },
        .assign => |assignment| {
            for (assignment.targets) |target| {
                if (target.* == .name) names.add(target.name.ident);
                collectExpr(names, target);
            }
            for (assignment.values) |value| collectExpr(names, value);
        },
        .call_stmt => |call| collectExpr(names, call.expr),
        .expr_stmt => |expression| collectExpr(names, expression.expr),
        .do_block => |block| collectBlock(names, &block.body),
        .while_loop => |loop| {
            collectExpr(names, loop.cond);
            collectBlock(names, &loop.body);
        },
        .repeat_loop => |loop| {
            collectBlock(names, &loop.body);
            collectExpr(names, loop.cond);
        },
        .if_stmt => |branch| {
            if (branch.binding) |binding| {
                names.add(binding.name);
                collectExpr(names, binding.expr);
            }
            collectExpr(names, branch.cond);
            collectBlock(names, &branch.then);
            for (branch.elseifs) |elseif| {
                collectExpr(names, elseif.cond);
                collectBlock(names, &elseif.body);
            }
            if (branch.else_body) |body| collectBlock(names, &body);
        },
        .num_for => |loop| {
            names.add(loop.var_name);
            collectExpr(names, loop.start);
            collectExpr(names, loop.stop);
            if (loop.step) |step| collectExpr(names, step);
            collectBlock(names, &loop.body);
        },
        .gen_for => |loop| {
            for (loop.vars) |name| names.add(name);
            for (loop.iters) |iter| collectExpr(names, iter);
            collectBlock(names, &loop.body);
        },
        .func_decl => |decl| {
            if (decl.path.len > 0) names.add(decl.path[0]);
            for (decl.func.params) |param| names.add(param.name);
            collectBlock(names, &decl.func.body);
        },
        .ret => |result| for (result.vals) |value| collectExpr(names, value),
        else => {},
    }
}

fn normalizeExpr(alloc: std.mem.Allocator, expr: *ast.Expr, names: *const BoundNames) void {
    switch (expr.*) {
        .index => |x| {
            normalizeExpr(alloc, x.obj, names);
            normalizeExpr(alloc, x.key, names);
        },
        .field => |x| normalizeExpr(alloc, x.obj, names),
        .binop => |x| {
            normalizeExpr(alloc, x.lhs, names);
            normalizeExpr(alloc, x.rhs, names);
        },
        .unop => |x| normalizeExpr(alloc, x.operand, names),
        .try_expr => |x| normalizeExpr(alloc, x.operand, names),
        .unwrap_expr => |x| normalizeExpr(alloc, x.operand, names),
        .await_expr => |x| normalizeExpr(alloc, x.operand, names),
        .quote => |x| normalizeExpr(alloc, x.expr, names),
        .unquote => |x| normalizeExpr(alloc, x.expr, names),
        .contains_expr => |x| {
            normalizeExpr(alloc, x.lhs, names);
            normalizeExpr(alloc, x.rhs, names);
        },
        .range => |x| {
            normalizeExpr(alloc, x.start, names);
            normalizeExpr(alloc, x.end, names);
            if (x.step) |step| normalizeExpr(alloc, step, names);
        },
        .sequence => |x| for (x.exprs) |child| normalizeExpr(alloc, child, names),
        .if_expr => |x| {
            normalizeExpr(alloc, x.cond, names);
            normalizeExpr(alloc, x.then_expr, names);
            normalizeExpr(alloc, x.else_expr, names);
        },
        .method_call => |method| {
            normalizeExpr(alloc, method.obj, names);
            for (method.args) |arg| normalizeExpr(alloc, arg, names);
            if (method.args.len == 1 and method.obj.* == .name and
                std.mem.eql(u8, method.obj.name.ident, "os") and
                (std.mem.eql(u8, method.method, "arg") or std.mem.eql(u8, method.method, "args")))
            {
                expr.* = .{ .index = .{
                    .loc = method.loc,
                    .obj = argTable(alloc, method.loc) catch return,
                    .key = method.args[0],
                } };
            } else if (method.args.len == 1 and method.obj.* == .name and
                std.mem.eql(u8, method.obj.name.ident, "os") and
                std.mem.eql(u8, method.method, "env"))
            {
                expr.* = .{ .index = .{
                    .loc = method.loc,
                    .obj = worldTable(alloc, method.loc, "env") catch return,
                    .key = method.args[0],
                } };
            } else if (method.args.len == 1 and std.mem.eql(u8, method.method, "remove") and
                envRemovalSubject(names, method.obj))
            {
                var anchored = method;
                anchored.obj = worldTable(alloc, method.loc, "env") catch return;
                expr.* = .{ .method_call = anchored };
            }
        },
        .table => |table| for (table.fields) |field| switch (field) {
            .indexed => |value| {
                normalizeExpr(alloc, value.key, names);
                normalizeExpr(alloc, value.val, names);
            },
            .named => |value| normalizeExpr(alloc, value.val, names),
            .semantic => |value| normalizeExpr(alloc, value.val, names),
            .positional => |value| normalizeExpr(alloc, value, names),
            .spread => |value| normalizeExpr(alloc, value, names),
        },
        .func_expr => |function| normalizeBlock(alloc, &function.body, names),
        .match_expr => |match| {
            normalizeExpr(alloc, match.scrutinee, names);
            for (match.arms) |arm| {
                if (arm.guard) |guard| normalizeExpr(alloc, guard, names);
                normalizeBlock(alloc, &arm.body, names);
            }
        },
        .macro_call => |macro| for (macro.args) |arg| normalizeExpr(alloc, arg, names),
        .call => |call| {
            normalizeExpr(alloc, call.func, names);
            for (call.args) |arg| normalizeExpr(alloc, arg, names);

            if (isApplicationFace(call.form) and call.args.len == 1 and argProjection(call.func)) {
                expr.* = .{ .index = .{
                    .loc = call.loc,
                    .obj = argTable(alloc, call.loc) catch return,
                    .key = call.args[0],
                } };
                return;
            }
            if (isApplicationFace(call.form) and call.args.len == 1 and envAnchor(call.func) and !names.has("os")) {
                expr.* = .{ .index = .{ .loc = call.loc, .obj = call.func, .key = call.args[0] } };
                return;
            }
            if (isApplicationFace(call.form) and call.args.len == 0) {
                if (anchoredMember(names, call.func)) |member| {
                    if (member.face == .value) {
                        expr.* = call.func.*;
                        return;
                    }
                }
            }

            if (bareMember(names, call.func)) |member| {
                const target = subject_home.osTarget(member);
                switch (member.face) {
                    .projection => if (isApplicationFace(call.form) and call.args.len == 1) {
                        expr.* = .{ .index = .{
                            .loc = call.loc,
                            .obj = worldTable(alloc, call.loc, target) catch return,
                            .key = call.args[0],
                        } };
                    },
                    .relation => {
                        var anchored = call;
                        anchored.func = worldTable(alloc, call.loc, target) catch return;
                        expr.* = .{ .call = anchored };
                    },
                    .value => if (isApplicationFace(call.form) and call.args.len == 0) {
                        expr.* = (worldTable(alloc, call.loc, target) catch return).*;
                    },
                }
            }
        },
        else => {},
    }
}

fn normalizeBlock(alloc: std.mem.Allocator, block: *ast.Block, names: *const BoundNames) void {
    for (block.stmts) |*statement| normalizeStmt(alloc, statement, names);
    if (block.tail_expr) |tail| normalizeExpr(alloc, tail, names);
}

fn normalizeStmt(alloc: std.mem.Allocator, statement: *ast.Stmt, names: *const BoundNames) void {
    switch (statement.*) {
        .local_decl => |decl| for (decl.inits) |init| normalizeExpr(alloc, init, names),
        .const_decl => |decl| normalizeExpr(alloc, decl.val, names),
        .global_decl => |decl| for (decl.inits) |init| normalizeExpr(alloc, init, names),
        .assign => |assignment| {
            for (assignment.targets) |target| normalizeExpr(alloc, target, names);
            for (assignment.values) |value| normalizeExpr(alloc, value, names);
        },
        .call_stmt => |call| normalizeExpr(alloc, call.expr, names),
        .expr_stmt => |expression| normalizeExpr(alloc, expression.expr, names),
        .do_block => |*block| normalizeBlock(alloc, &block.body, names),
        .while_loop => |*loop| {
            normalizeExpr(alloc, loop.cond, names);
            normalizeBlock(alloc, &loop.body, names);
        },
        .repeat_loop => |*loop| {
            normalizeBlock(alloc, &loop.body, names);
            normalizeExpr(alloc, loop.cond, names);
        },
        .if_stmt => |*branch| {
            if (branch.binding) |binding| normalizeExpr(alloc, binding.expr, names);
            normalizeExpr(alloc, branch.cond, names);
            normalizeBlock(alloc, &branch.then, names);
            for (branch.elseifs) |*elseif| {
                normalizeExpr(alloc, elseif.cond, names);
                normalizeBlock(alloc, &elseif.body, names);
            }
            if (branch.else_body) |*body| normalizeBlock(alloc, body, names);
        },
        .num_for => |*loop| {
            normalizeExpr(alloc, loop.start, names);
            normalizeExpr(alloc, loop.stop, names);
            if (loop.step) |step| normalizeExpr(alloc, step, names);
            normalizeBlock(alloc, &loop.body, names);
        },
        .gen_for => |*loop| {
            for (loop.iters) |iter| normalizeExpr(alloc, iter, names);
            normalizeBlock(alloc, &loop.body, names);
        },
        .func_decl => |*decl| normalizeBlock(alloc, &decl.func.body, names),
        .ret => |result| for (result.vals) |value| normalizeExpr(alloc, value, names),
        else => {},
    }
}

fn normalizeWorldModule(alloc: std.mem.Allocator, module: *ast.Module) void {
    var names = BoundNames.init(alloc);
    defer names.deinit();
    collectBlock(&names, &module.body);
    normalizeBlock(alloc, &module.body, &names);
}

/// Compatibility-only world normalization. `type_map` remains in the public
/// signature until callers stop treating this as the old table-application
/// pass; no semantic decision in this module reads it.
pub fn normalizeModule(
    alloc: std.mem.Allocator,
    module: *ast.Module,
    type_map: *const sema.TypeMap,
) void {
    _ = type_map;
    normalizeWorldModule(alloc, module);
}

fn lastExpr(block: *const ast.Block) ?*const ast.Expr {
    if (block.tail_expr) |tail| return tail;
    if (block.stmts.len == 0) return null;
    return switch (block.stmts[block.stmts.len - 1]) {
        .expr_stmt => |expression| expression.expr,
        .call_stmt => |call| call.expr,
        else => null,
    };
}

fn parseModule(alloc: std.mem.Allocator, source: []const u8, path: []const u8) !ast.Module {
    var lexer = @import("lexer.zig").Lexer.init(source, path);
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    return parser.parse_module();
}

test "table_apply: ordinary parenthesized call remains application" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = (t: i64)
        \\    t(1)
    ;
    var module = try parseModule(alloc, source, "ordinary-call.id");
    normalizeWorldModule(alloc, &module);
    const expression = lastExpr(&module.body.stmts[0].func_decl.func.body) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(expression.* == .call);
}

test "table_apply: bracket projection remains projection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = (t: i64)
        \\    t[1]
    ;
    var module = try parseModule(alloc, source, "bracket-projection.id");
    normalizeWorldModule(alloc, &module);
    const expression = lastExpr(&module.body.stmts[0].func_decl.func.body) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(expression.* == .index);
}

test "table_apply: unbound ambient env compatibility becomes projection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: str = ()
        \\    env("HOME")
    ;
    var module = try parseModule(alloc, source, "ambient-env.id");
    normalizeWorldModule(alloc, &module);
    const expression = lastExpr(&module.body.stmts[0].func_decl.func.body) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(expression.* == .index);
}

test "table_apply: user-bound env remains application" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\env: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    env(1)
    ;
    var module = try parseModule(alloc, source, "bound-env.id");
    normalizeWorldModule(alloc, &module);
    const expression = lastExpr(&module.body.stmts[1].func_decl.func.body) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(expression.* == .call);
}
