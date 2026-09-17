const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");

pub fn normalizeModule(alloc: std.mem.Allocator, mod: *ast.Module, type_map: *const sema.TypeMap) std.mem.Allocator.Error!void {
    try normalizeBlock(alloc, &mod.body, type_map, &.{});
}

fn normalizeBlock(alloc: std.mem.Allocator, block: *ast.Block, type_map: *const sema.TypeMap, enclosing: []const []const u8) std.mem.Allocator.Error!void {
    for (block.stmts) |*stmt| try normalizeStmt(alloc, stmt, type_map, enclosing);
    var out: std.ArrayListUnmanaged(ast.Stmt) = .empty;
    errdefer out.deinit(alloc);
    for (block.stmts) |*stmt| {
        if (stmt.* == .num_for) {
            if (try desugarNumFor(alloc, stmt, type_map, enclosing)) |pair| {
                try out.append(alloc, pair[0]);
                try out.append(alloc, pair[1]);
                continue;
            }
        }
        try out.append(alloc, stmt.*);
    }
    if (out.items.len != block.stmts.len) {
        block.stmts = try out.toOwnedSlice(alloc);
    } else {
        out.deinit(alloc);
    }
}

fn normalizeStmt(alloc: std.mem.Allocator, stmt: *ast.Stmt, type_map: *const sema.TypeMap, enclosing: []const []const u8) std.mem.Allocator.Error!void {
    switch (stmt.*) {
        .num_for => |*nf| {
            const extended = try alloc.alloc([]const u8, enclosing.len + 1);
            @memcpy(extended[0..enclosing.len], enclosing);
            extended[enclosing.len] = nf.var_name;
            try normalizeBlock(alloc, &nf.body, type_map, extended);
        },
        .gen_for => |*gf| try normalizeBlock(alloc, &gf.body, type_map, enclosing),
        .while_loop => |*w| try normalizeBlock(alloc, &w.body, type_map, enclosing),
        .repeat_loop => |*r| try normalizeBlock(alloc, &r.body, type_map, enclosing),
        .do_block => |*d| try normalizeBlock(alloc, &d.body, type_map, enclosing),
        .if_stmt => |*s| {
            try normalizeBlock(alloc, &s.then, type_map, enclosing);
            for (s.elseifs) |*ei| try normalizeBlock(alloc, &ei.body, type_map, enclosing);
            if (s.else_body) |*eb| try normalizeBlock(alloc, eb, type_map, enclosing);
        },
        .func_decl => |*f| try normalizeBlock(alloc, &f.func.body, type_map, enclosing),
        .match_stmt => |*m| {
            for (m.arms) |*arm| try normalizeBlock(alloc, &arm.body, type_map, enclosing);
        },
        .try_stmt => |*t| {
            try normalizeBlock(alloc, &t.body, type_map, enclosing);
            for (t.catches) |*c| try normalizeBlock(alloc, &c.body, type_map, enclosing);
            for (t.defers) |*d| try normalizeBlock(alloc, &d.body, type_map, enclosing);
        },
        .defer_stmt => |*d| try normalizeBlock(alloc, &d.body, type_map, enclosing),
        else => {},
    }
}

fn desugarNumFor(alloc: std.mem.Allocator, stmt: *const ast.Stmt, type_map: *const sema.TypeMap, enclosing: []const []const u8) std.mem.Allocator.Error!?[2]ast.Stmt {
    const nf = switch (stmt.*) {
        .num_for => |*x| x,
        else => return null,
    };
    if (!eligible(nf, type_map, enclosing)) return null;
    const loc = nf.loc;
    const init = try mkAssign(alloc, loc, try mkName(alloc, loc, nf.var_name), nf.start);
    var cond_op: ast.BinOp = .leq;
    var bound: *ast.Expr = nf.stop;
    if (nf.stop.* == .int_lit) {
        const stop_val = nf.stop.int_lit.val;
        if (stop_val < std.math.maxInt(i64)) {
            bound = try mkInt(alloc, loc, stop_val + 1);
            cond_op = .lt;
        }
    }
    const cond = try mkBinop(alloc, loc, cond_op, try mkName(alloc, loc, nf.var_name), bound);
    const step = try mkAssign(
        alloc,
        loc,
        try mkName(alloc, loc, nf.var_name),
        try mkBinop(alloc, loc, .add, try mkName(alloc, loc, nf.var_name), try mkInt(alloc, loc, 1)),
    );
    const body_stmts = try alloc.alloc(ast.Stmt, nf.body.stmts.len + 1);
    @memcpy(body_stmts[0..nf.body.stmts.len], nf.body.stmts);
    body_stmts[nf.body.stmts.len] = step;
    const loop = ast.Stmt{ .while_loop = .{
        .loc = loc,
        .cond = cond,
        .body = .{ .loc = nf.body.loc, .stmts = body_stmts, .tail_expr = nf.body.tail_expr },
    } };
    return [2]ast.Stmt{ init, loop };
}

fn eligible(nf: anytype, type_map: *const sema.TypeMap, enclosing: []const []const u8) bool {
    for (enclosing) |name| if (std.mem.eql(u8, name, nf.var_name)) return false;
    if (nf.stop.* == .int_lit and nf.stop.int_lit.val == std.math.maxInt(i64)) return false;
    if (nf.unroll != null) return false;
    if (nf.var_typ != .inferred) return false;
    if (nf.step) |st| {
        if (st.* != .int_lit or st.int_lit.val != 1) return false;
    }
    if (!isI64(type_map, nf.start)) return false;
    if (!isI64(type_map, nf.stop)) return false;
    if (blockHasLoopExit(&nf.body)) return false;
    if (blockAssignsName(&nf.body, nf.var_name)) return false;
    if (blockHasForVar(&nf.body, nf.var_name)) return false;
    if (nf.stop.* == .name) {
        if (blockAssignsName(&nf.body, nf.stop.name.ident)) return false;
    }
    return true;
}

fn isI64(type_map: *const sema.TypeMap, e: *const ast.Expr) bool {
    const rt = type_map.get(e) orelse return false;
    return rt == .i64;
}

fn mkName(alloc: std.mem.Allocator, loc: ast.Loc, ident: []const u8) std.mem.Allocator.Error!*ast.Expr {
    const e = try alloc.create(ast.Expr);
    e.* = .{ .name = .{ .loc = loc, .ident = ident } };
    return e;
}

fn mkInt(alloc: std.mem.Allocator, loc: ast.Loc, val: i64) std.mem.Allocator.Error!*ast.Expr {
    const e = try alloc.create(ast.Expr);
    e.* = .{ .int_lit = .{ .loc = loc, .val = val } };
    return e;
}

fn mkBinop(alloc: std.mem.Allocator, loc: ast.Loc, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr) std.mem.Allocator.Error!*ast.Expr {
    const e = try alloc.create(ast.Expr);
    e.* = .{ .binop = .{ .loc = loc, .op = op, .lhs = lhs, .rhs = rhs } };
    return e;
}

fn mkAssign(alloc: std.mem.Allocator, loc: ast.Loc, target: *ast.Expr, value: *ast.Expr) std.mem.Allocator.Error!ast.Stmt {
    const targets = try alloc.alloc(*ast.Expr, 1);
    targets[0] = target;
    const values = try alloc.alloc(*ast.Expr, 1);
    values[0] = value;
    return .{ .assign = .{ .loc = loc, .targets = targets, .values = values } };
}

fn blockHasLoopExit(block: *const ast.Block) bool {
    for (block.stmts) |*s| if (stmtHasLoopExit(s)) return true;
    return false;
}

fn stmtHasLoopExit(stmt: *const ast.Stmt) bool {
    switch (stmt.*) {
        .brk, .cont => return true,
        .while_loop, .repeat_loop, .num_for, .gen_for, .func_decl => return false,
        .do_block => |d| return blockHasLoopExit(&d.body),
        .if_stmt => |s| {
            if (blockHasLoopExit(&s.then)) return true;
            for (s.elseifs) |*ei| if (blockHasLoopExit(&ei.body)) return true;
            if (s.else_body) |*eb| if (blockHasLoopExit(eb)) return true;
            return false;
        },
        .match_stmt => |m| {
            for (m.arms) |*arm| if (blockHasLoopExit(&arm.body)) return true;
            return false;
        },
        .try_stmt => |t| {
            if (blockHasLoopExit(&t.body)) return true;
            for (t.catches) |*c| if (blockHasLoopExit(&c.body)) return true;
            for (t.defers) |*d| if (blockHasLoopExit(&d.body)) return true;
            return false;
        },
        .defer_stmt => |d| return blockHasLoopExit(&d.body),
        else => return false,
    }
}

fn blockAssignsName(block: *const ast.Block, name: []const u8) bool {
    for (block.stmts) |*s| if (stmtAssignsName(s, name)) return true;
    return false;
}

fn stmtAssignsName(stmt: *const ast.Stmt, name: []const u8) bool {
    switch (stmt.*) {
        .assign => |a| {
            for (a.targets) |t| {
                if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) return true;
            }
            return false;
        },
        .local_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) return true;
            return false;
        },
        .const_decl => |d| return std.mem.eql(u8, d.ident, name),
        .global_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) return true;
            return false;
        },
        .num_for => |nf| {
            if (std.mem.eql(u8, nf.var_name, name)) return true;
            return blockAssignsName(&nf.body, name);
        },
        .gen_for => |gf| {
            for (gf.vars) |v| if (std.mem.eql(u8, v, name)) return true;
            return blockAssignsName(&gf.body, name);
        },
        .while_loop => |w| return blockAssignsName(&w.body, name),
        .repeat_loop => |r| return blockAssignsName(&r.body, name),
        .do_block => |d| return blockAssignsName(&d.body, name),
        .if_stmt => |s| {
            if (blockAssignsName(&s.then, name)) return true;
            for (s.elseifs) |*ei| if (blockAssignsName(&ei.body, name)) return true;
            if (s.else_body) |*eb| if (blockAssignsName(eb, name)) return true;
            return false;
        },
        .func_decl => |f| return blockAssignsName(&f.func.body, name),
        .match_stmt => |m| {
            for (m.arms) |*arm| if (blockAssignsName(&arm.body, name)) return true;
            return false;
        },
        .try_stmt => |t| {
            if (blockAssignsName(&t.body, name)) return true;
            for (t.catches) |*c| if (blockAssignsName(&c.body, name)) return true;
            for (t.defers) |*d| if (blockAssignsName(&d.body, name)) return true;
            return false;
        },
        .defer_stmt => |d| return blockAssignsName(&d.body, name),
        else => return false,
    }
}

fn blockHasForVar(block: *const ast.Block, name: []const u8) bool {
    for (block.stmts) |*s| if (stmtHasForVar(s, name)) return true;
    return false;
}

fn stmtHasForVar(stmt: *const ast.Stmt, name: []const u8) bool {
    switch (stmt.*) {
        .num_for => |nf| {
            if (std.mem.eql(u8, nf.var_name, name)) return true;
            return blockHasForVar(&nf.body, name);
        },
        .gen_for => |gf| {
            for (gf.vars) |v| if (std.mem.eql(u8, v, name)) return true;
            return blockHasForVar(&gf.body, name);
        },
        .while_loop => |w| return blockHasForVar(&w.body, name),
        .repeat_loop => |r| return blockHasForVar(&r.body, name),
        .do_block => |d| return blockHasForVar(&d.body, name),
        .if_stmt => |s| {
            if (blockHasForVar(&s.then, name)) return true;
            for (s.elseifs) |*ei| if (blockHasForVar(&ei.body, name)) return true;
            if (s.else_body) |*eb| if (blockHasForVar(eb, name)) return true;
            return false;
        },
        .func_decl => |f| return blockHasForVar(&f.func.body, name),
        .match_stmt => |m| {
            for (m.arms) |*arm| if (blockHasForVar(&arm.body, name)) return true;
            return false;
        },
        .try_stmt => |t| {
            if (blockHasForVar(&t.body, name)) return true;
            for (t.catches) |*c| if (blockHasForVar(&c.body, name)) return true;
            for (t.defers) |*d| if (blockHasForVar(&d.body, name)) return true;
            return false;
        },
        .defer_stmt => |d| return blockHasForVar(&d.body, name),
        else => return false,
    }
}
