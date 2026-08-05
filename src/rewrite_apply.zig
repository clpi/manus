/// Apply registered `@rewrite` rules to the AST before semantic analysis.
const std = @import("std");
const ast = @import("ast.zig");
const rewrite_rules = @import("rewrite_rules.zig");

pub fn applyModule(alloc: std.mem.Allocator, mod: *ast.Module) !void {
    for (mod.body.stmts) |*stmt| {
        try applyStmt(alloc, stmt);
    }
}

fn applyStmt(alloc: std.mem.Allocator, stmt: *ast.Stmt) error{OutOfMemory}!void {
    switch (stmt.*) {
        .func_decl => |*fd| try applyBlock(alloc, &fd.func.body),
        .local_decl => |*ld| {
            for (ld.inits) |init| try applyExpr(alloc, init);
        },
        .const_decl => |*cd| try applyExpr(alloc, cd.val),
        .assign => |*as| {
            for (as.values) |val| try applyExpr(alloc, val);
        },
        .expr_stmt => |*es| try applyExpr(alloc, es.expr),
        .ret => |*r| {
            for (r.vals) |val| try applyExpr(alloc, val);
        },
        .if_stmt => |*is| {
            try applyExpr(alloc, is.cond);
            try applyBlock(alloc, &is.then);
            for (is.elseifs) |*ei| {
                try applyExpr(alloc, ei.cond);
                try applyBlock(alloc, &ei.body);
            }
            if (is.else_body) |*eb| try applyBlock(alloc, eb);
        },
        .while_loop => |*wl| {
            try applyExpr(alloc, wl.cond);
            try applyBlock(alloc, &wl.body);
        },
        .repeat_loop => |*rp| {
            try applyExpr(alloc, rp.cond);
            try applyBlock(alloc, &rp.body);
        },
        .num_for => |*nf| {
            try applyExpr(alloc, nf.start);
            try applyExpr(alloc, nf.stop);
            if (nf.step) |step| try applyExpr(alloc, step);
            try applyBlock(alloc, &nf.body);
        },
        .gen_for => |*gf| {
            for (gf.iters) |iter| try applyExpr(alloc, iter);
            try applyBlock(alloc, &gf.body);
        },
        .do_block => |*db| try applyBlock(alloc, &db.body),
        else => {},
    }
}

fn applyBlock(alloc: std.mem.Allocator, block: *ast.Block) error{OutOfMemory}!void {
    for (block.stmts) |*stmt| try applyStmt(alloc, stmt);
}

fn applyExpr(alloc: std.mem.Allocator, expr: *ast.Expr) error{OutOfMemory}!void {
    switch (expr.*) {
        .binop => |*b| {
            try applyExpr(alloc, b.lhs);
            try applyExpr(alloc, b.rhs);
            try applyBinopRewrite(alloc, expr);
        },
        .unop => |*u| {
            try applyExpr(alloc, u.operand);
            try applyUnopRewrite(alloc, expr);
        },
        .call => |*c| {
            try applyExpr(alloc, c.func);
            for (c.args) |arg| try applyExpr(alloc, arg);
        },
        .method_call => |*mc| {
            try applyExpr(alloc, mc.obj);
            for (mc.args) |arg| try applyExpr(alloc, arg);
        },
        .field => |*f| try applyExpr(alloc, f.obj),
        .index => |*idx| {
            try applyExpr(alloc, idx.obj);
            try applyExpr(alloc, idx.key);
        },
        .table => |*t| {
            for (t.fields) |*fld| {
                switch (fld.*) {
                    .indexed => |*idx| {
                        try applyExpr(alloc, idx.key);
                        try applyExpr(alloc, idx.val);
                    },
                    .named => |*nmd| try applyExpr(alloc, nmd.val),
                    .positional => |pos| try applyExpr(alloc, pos),
                }
            }
        },
        .list_comp => |*lc| {
            try applyExpr(alloc, lc.iter);
            try applyExpr(alloc, lc.value);
            if (lc.filter) |filter| try applyExpr(alloc, filter);
        },
        .func_expr => |fb| try applyBlock(alloc, &fb.body),
        .sequence => |*seq| {
            for (seq.exprs) |sub| try applyExpr(alloc, sub);
        },
        else => {},
    }
}

fn applyBinopRewrite(alloc: std.mem.Allocator, expr: *ast.Expr) error{OutOfMemory}!void {
    const b = expr.binop;
    if (tryFoldLiteralBinop(expr)) return;
    const action = rewrite_rules.matchBinop(b.op, b.lhs, b.rhs) orelse return;
    const loc = b.loc;
    switch (action) {
        .emit_capture1 => {
            expr.* = b.lhs.*;
        },
        .emit_capture_rhs => {
            expr.* = b.rhs.*;
        },
        .emit_literal_i64 => |v| {
            expr.* = .{ .int_lit = .{ .val = v, .loc = loc } };
        },
        .emit_shift_left => |n| {
            expr.* = .{ .binop = .{ .loc = loc, .op = .lshift, .lhs = b.lhs, .rhs = shiftAmount(alloc, loc, n) } };
        },
        .emit_shift_left_rhs => |n| {
            expr.* = .{ .binop = .{ .loc = loc, .op = .lshift, .lhs = b.rhs, .rhs = shiftAmount(alloc, loc, n) } };
        },
        .emit_shift_right => |n| {
            expr.* = .{ .binop = .{ .loc = loc, .op = .rshift, .lhs = b.lhs, .rhs = shiftAmount(alloc, loc, n) } };
        },
        .emit_shift_right_rhs => |n| {
            expr.* = .{ .binop = .{ .loc = loc, .op = .rshift, .lhs = b.rhs, .rhs = shiftAmount(alloc, loc, n) } };
        },
        .emit_sub_self_zero => {
            expr.* = .{ .int_lit = .{ .val = 0, .loc = loc } };
        },
    }
}

fn shiftAmount(alloc: std.mem.Allocator, loc: ast.Loc, n: u3) *ast.Expr {
    const rhs = alloc.create(ast.Expr) catch @panic("OOM");
    rhs.* = .{ .int_lit = .{ .val = @as(i64, n), .loc = loc } };
    return rhs;
}

fn tryFoldLiteralBinop(expr: *ast.Expr) bool {
    const b = expr.binop;
    if (b.lhs.* == .int_lit and b.rhs.* == .int_lit) {
        const a = b.lhs.int_lit.val;
        const c = b.rhs.int_lit.val;
        const result: ?i64 = switch (b.op) {
            .add => a + c,
            .sub => a - c,
            .mul => a * c,
            .div => if (c == 0) null else @divTrunc(a, c),
            .mod => if (c == 0) null else @mod(a, c),
            .idiv => if (c == 0) null else @divTrunc(a, c),
            .band => a & c,
            .bor => a | c,
            .bxor => a ^ c,
            .lshift => if (c < 0 or c > 63) null else @as(i64, @bitCast(@as(u64, @bitCast(a)) << @as(u6, @intCast(c)))),
            .rshift => if (c < 0 or c > 63) null else @as(i64, @bitCast(@as(u64, @bitCast(a)) >> @as(u6, @intCast(c)))),
            else => null,
        };
        if (result) |v| {
            expr.* = .{ .int_lit = .{ .val = v, .loc = b.loc } };
            return true;
        }
        const bool_result: ?bool = switch (b.op) {
            .eq => a == c,
            .neq => a != c,
            .lt => a < c,
            .leq => a <= c,
            .gt => a > c,
            .geq => a >= c,
            else => null,
        };
        if (bool_result) |v| {
            expr.* = if (v) .{ .true_lit = b.loc } else .{ .false_lit = b.loc };
            return true;
        }
    } else if (b.lhs.* == .float_lit and b.rhs.* == .float_lit) {
        const a = b.lhs.float_lit.val;
        const c = b.rhs.float_lit.val;
        const result: ?f64 = switch (b.op) {
            .add => a + c,
            .sub => a - c,
            .mul => a * c,
            .div => a / c,
            else => null,
        };
        if (result) |v| {
            expr.* = .{ .float_lit = .{ .val = v, .loc = b.loc } };
            return true;
        }
        const bool_result: ?bool = switch (b.op) {
            .eq => a == c,
            .neq => a != c,
            .lt => a < c,
            .leq => a <= c,
            .gt => a > c,
            .geq => a >= c,
            else => null,
        };
        if (bool_result) |v| {
            expr.* = if (v) .{ .true_lit = b.loc } else .{ .false_lit = b.loc };
            return true;
        }
    } else if ((b.lhs.* == .true_lit or b.lhs.* == .false_lit) and (b.rhs.* == .true_lit or b.rhs.* == .false_lit)) {
        const a = b.lhs.* == .true_lit;
        const c = b.rhs.* == .true_lit;
        const bool_result: ?bool = switch (b.op) {
            .@"and" => a and c,
            .@"or" => a or c,
            .eq => a == c,
            .neq => a != c,
            else => null,
        };
        if (bool_result) |v| {
            expr.* = if (v) .{ .true_lit = b.loc } else .{ .false_lit = b.loc };
            return true;
        }
    }
    return false;
}

fn tryFoldLiteralUnop(expr: *ast.Expr) bool {
    const u = expr.unop;
    if (u.operand.* == .int_lit) {
        if (u.op == .neg) {
            expr.* = .{ .int_lit = .{ .val = -u.operand.int_lit.val, .loc = u.loc } };
            return true;
        } else if (u.op == .bnot) {
            expr.* = .{ .int_lit = .{ .val = ~u.operand.int_lit.val, .loc = u.loc } };
            return true;
        }
    } else if (u.operand.* == .float_lit) {
        if (u.op == .neg) {
            expr.* = .{ .float_lit = .{ .val = -u.operand.float_lit.val, .loc = u.loc } };
            return true;
        }
    } else if (u.operand.* == .true_lit or u.operand.* == .false_lit) {
        if (u.op == .not) {
            const v = u.operand.* == .true_lit;
            expr.* = if (!v) .{ .true_lit = u.loc } else .{ .false_lit = u.loc };
            return true;
        }
    }
    return false;
}

fn applyUnopRewrite(alloc: std.mem.Allocator, expr: *ast.Expr) error{OutOfMemory}!void {
    const u = expr.unop;
    if (tryFoldLiteralUnop(expr)) return;
    const action = rewrite_rules.matchUnop(u.op, u.operand) orelse return;
    switch (action) {
        .emit_capture1 => expr.* = u.operand.unop.operand.*,
        else => _ = alloc,
    }
}

test "rewrite_apply: add_zero simplifies AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    rewrite_rules.clearRegistry();
    defer rewrite_rules.clearRegistry();
    try rewrite_rules.registerRule(alloc, "add_zero", "($1 + 0)", "$1", 10);

    const lhs = try alloc.create(ast.Expr);
    lhs.* = .{ .name = .{ .ident = "x", .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const rhs = try alloc.create(ast.Expr);
    rhs.* = .{ .int_lit = .{ .val = 0, .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const expr = try alloc.create(ast.Expr);
    expr.* = .{ .binop = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .op = .add, .lhs = lhs, .rhs = rhs } };

    try applyExpr(alloc, expr);
    try std.testing.expect(expr.* == .name);
    try std.testing.expectEqualStrings("x", expr.name.ident);
}

test "rewrite_apply: mul_two becomes lshift in AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    rewrite_rules.clearRegistry();
    defer rewrite_rules.clearRegistry();
    try rewrite_rules.registerRule(alloc, "mul_two", "($1 * 2)", "$1 << 1", 5);

    const lhs = try alloc.create(ast.Expr);
    lhs.* = .{ .name = .{ .ident = "x", .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const rhs = try alloc.create(ast.Expr);
    rhs.* = .{ .int_lit = .{ .val = 2, .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const expr = try alloc.create(ast.Expr);
    expr.* = .{ .binop = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .op = .mul, .lhs = lhs, .rhs = rhs } };

    try applyExpr(alloc, expr);
    try std.testing.expect(expr.* == .binop);
    try std.testing.expect(expr.binop.op == .lshift);
    try std.testing.expect(expr.binop.rhs.* == .int_lit);
    try std.testing.expectEqual(@as(i64, 1), expr.binop.rhs.int_lit.val);
}

test "rewrite_apply: folds literal addition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const lhs = try alloc.create(ast.Expr);
    lhs.* = .{ .int_lit = .{ .val = 40, .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const rhs = try alloc.create(ast.Expr);
    rhs.* = .{ .int_lit = .{ .val = 2, .loc = .{ .file = "t", .line = 1, .col = 1 } } };
    const expr = try alloc.create(ast.Expr);
    expr.* = .{ .binop = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .op = .add, .lhs = lhs, .rhs = rhs } };

    try applyExpr(alloc, expr);
    try std.testing.expect(expr.* == .int_lit);
    try std.testing.expectEqual(@as(i64, 42), expr.int_lit.val);
}
