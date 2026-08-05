//! AST → DNIR lowering for typed native programs (no lua_Value, no C-string codegen).
//!
//! Produces `duo_native_ir.Module` for direct machine backends. C emission is bootstrap-only.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const dnir = @import("duo_native_ir.zig");
const native_req_support = @import("native_req_support.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const RT = types.ResolvedType;

pub const Error = error{
    UnsupportedConstruct,
    OutOfMemory,
};

pub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {
    var req = try native_req_support.collectFromModule(alloc, mod);
    defer req.deinit(alloc);

    var records: std.ArrayList(dnir.RecordDesc) = .empty;
    defer {
        for (records.items) |r| {
            alloc.free(r.name);
            for (r.fields) |f| alloc.free(f);
            alloc.free(r.fields);
            alloc.free(r.kinds);
        }
        records.deinit(alloc);
    }
    try collectRecords(alloc, &records, mod);

    var functions: std.ArrayList(dnir.Function) = .empty;
    errdefer functions.deinit(alloc);
    var externs: std.ArrayList(dnir.Extern) = .empty;
    errdefer externs.deinit(alloc);
    var func_record_returns: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer func_record_returns.deinit(alloc);

    var seen_main = false;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1 or fd.method or fd.is_local) continue;
        if (std.mem.eql(u8, fd.path[0], "main")) seen_main = true;
        if (!functionEligible(fd, records.items)) continue;
        const f = try lowerFunction(alloc, fd, records.items, &req, &externs, &func_record_returns);
        try functions.append(alloc, f);
    }
    if (!seen_main or functions.items.len == 0) return error.UnsupportedConstruct;

    const result = dnir.Module{
        .functions = try functions.toOwnedSlice(alloc),
        .records = try records.toOwnedSlice(alloc),
        .externs = try externs.toOwnedSlice(alloc),
    };
    return .{
        .functions = result.functions,
        .records = result.records,
        .externs = result.externs,
        .hardware_tier = dnir.moduleHardwareTier(result),
    };
}

fn functionEligible(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) bool {
    if (fd.func.vararg or fd.func.vararg_name != null) return false;
    if (std.mem.eql(u8, fd.path[0], "main")) {
        return fd.func.params.len == 0 and isIntType(fd.func.ret_type);
    }
    if (findRecordName(recs, fd.func.ret_type)) |rec| {
        if (rec.fields.len == 0 or rec.fields.len > 8) return false;
        for (fd.func.params) |p| {
            if (!isIntType(p.typ) and !isStrType(p.typ)) return false;
        }
        return true;
    }
    if (!isIntType(fd.func.ret_type) and !isStrType(fd.func.ret_type)) return false;
    if (fd.func.params.len > 8) return false;
    for (fd.func.params) |p| {
        if (!isIntType(p.typ) and !isStrType(p.typ)) return false;
    }
    return true;
}

fn collectRecords(alloc: std.mem.Allocator, out: *std.ArrayList(dnir.RecordDesc), mod: *const ast.Module) Error!void {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (ad.type_params != null) continue;
        const target = ad.target orelse continue;
        const rec = switch (target) {
            .record => |r| r,
            else => continue,
        };
        if (rec.fields.len == 0 or rec.fields.len > 8) continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        var kinds: std.ArrayListUnmanaged(dnir.FieldKind) = .empty;
        errdefer kinds.deinit(alloc);
        var ok = true;
        for (rec.fields) |field| {
            const kind: dnir.FieldKind = if (isStrType(field.typ))
                .str
            else if (isIntType(field.typ))
                .i64
            else {
                ok = false;
                break;
            };
            try names.append(alloc, field.name);
            try kinds.append(alloc, kind);
        }
        if (!ok) continue;
        try out.append(alloc, .{
            .name = try alloc.dupe(u8, ad.name),
            .fields = try names.toOwnedSlice(alloc),
            .kinds = try kinds.toOwnedSlice(alloc),
        });
    }
}

fn findRecordName(recs: []const dnir.RecordDesc, t: ast.TypeExpr) ?dnir.RecordDesc {
    if (t != .named) return null;
    for (recs) |r| {
        if (std.mem.eql(u8, r.name, t.named)) return r;
    }
    return null;
}

pub const LowerCtx = struct {
    alloc: std.mem.Allocator,
    records: []const dnir.RecordDesc,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    next_temp: u32 = 0,
    locals: std.StringHashMapUnmanaged(u32) = .empty,
    instrs: std.ArrayList(dnir.Instr) = .empty,

    pub fn deinit(self: *LowerCtx) void {
        var it = self.locals.iterator();
        while (it.next()) |e| self.alloc.free(e.key_ptr.*);
        self.locals.deinit(self.alloc);
        self.instrs.deinit(self.alloc);
    }

    fn freshTemp(self: *LowerCtx) u32 {
        const t = self.next_temp;
        self.next_temp += 1;
        return t;
    }

    fn emit(self: *LowerCtx, instr: dnir.Instr) Error!void {
        try self.instrs.append(self.alloc, instr);
    }
};

fn internInstrStrings(alloc: std.mem.Allocator, instrs: []dnir.Instr) Error!void {
    for (instrs) |*ins| {
        if (ins.callee.len > 0) ins.callee = try alloc.dupe(u8, ins.callee);
        if (ins.req_alias.len > 0) ins.req_alias = try alloc.dupe(u8, ins.req_alias);
        if (ins.field.len > 0) ins.field = try alloc.dupe(u8, ins.field);
        if (ins.record.len > 0) ins.record = try alloc.dupe(u8, ins.record);
    }
}

fn lowerFunction(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    records: []const dnir.RecordDesc,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
) Error!dnir.Function {
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .records = records,
        .req = req,
        .externs = externs,
        .func_record_returns = func_record_returns,
    };
    defer ctx.deinit();

    for (fd.func.params, 0..) |par, i| {
        const owned = try alloc.dupe(u8, par.name);
        try ctx.locals.put(alloc, owned, @intCast(i));
    }

    try lowerBlock(&ctx, &fd.func.body, true);

    const params = try alloc.alloc(RT, fd.func.params.len);
    for (fd.func.params, 0..) |par, i| params[i] = resolveType(par.typ);

    const blocks = try alloc.alloc(dnir.Block, 1);
    const owned_instrs = try ctx.instrs.toOwnedSlice(alloc);
    try internInstrStrings(alloc, owned_instrs);
    blocks[0] = .{ .instrs = owned_instrs };

    const ret_rec = findRecordName(records, fd.func.ret_type);
    const ret_record_name = if (ret_rec) |r| try alloc.dupe(u8, r.name) else null;
    if (ret_record_name) |rn| {
        const owned_fn = try alloc.dupe(u8, fd.path[0]);
        try func_record_returns.put(alloc, owned_fn, rn);
    }

    return .{
        .name = try alloc.dupe(u8, fd.path[0]),
        .ret = resolveType(fd.func.ret_type),
        .params = params,
        .ret_record = ret_record_name,
        .blocks = blocks,
    };
}

fn resolveType(t: ast.TypeExpr) RT {
    return switch (t) {
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "i64")) break :blk .i64;
            if (std.mem.eql(u8, n, "str")) break :blk .str;
            if (std.mem.eql(u8, n, "bool")) break :blk .bool;
            if (std.mem.eql(u8, n, "f64")) break :blk .f64;
            break :blk .any;
        },
        .inferred => .any,
        else => .any,
    };
}

fn isIntType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "i64");
}

fn isStrType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "str");
}

fn lowerBlock(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!void {
    for (block.stmts) |*stmt| try lowerStmt(ctx, stmt, allow_return);
    if (block.tail_expr) |expr| {
        if (allow_return) {
            const v = try lowerExpr(ctx, expr);
            try ctx.emit(.{ .op = .ret, .lhs = v });
        }
    }
}

fn lowerStmt(ctx: *LowerCtx, stmt: *const ast.Stmt, allow_return: bool) Error!void {
    switch (stmt.*) {
        .local_decl => |ld| {
            for (ld.names, 0..) |*ln, i| {
                if (i < ld.inits.len) try lowerAssignTarget(ctx, ln.ident, ld.inits[i]);
            }
        },
        .assign => |as| {
            for (as.targets, as.values) |target, value| {
                switch (target.*) {
                    .name => |n| try lowerAssignTarget(ctx, n.ident, value),
                    else => return error.UnsupportedConstruct,
                }
            }
        },
        .if_stmt => |is| {
            const cond = try lowerExpr(ctx, is.cond);
            const fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br_if_not, .lhs = cond, .branch_target = 0 });
            const then_ret = try lowerBlockReturns(ctx, &is.then, allow_return);
            if (!then_ret) try ctx.emit(.{ .op = .br, .branch_target = 0 });
            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = end_idx;
            for (ctx.instrs.items) |*ins| {
                if (ins.op == .br and ins.branch_target == 0) ins.branch_target = end_idx;
            }
            if (is.else_body) |*eb| _ = try lowerBlockReturns(ctx, eb, allow_return);
        },
        .ret => |r| {
            if (r.vals.len == 0) {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 } });
            } else if (r.vals[0].* == .table) {
                try lowerRecordReturn(ctx, r.vals[0]);
            } else {
                try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.vals[0]) });
            }
        },
        .expr_stmt => |es| {
            _ = try lowerExpr(ctx, es.expr);
        },
        .call_stmt => |cs| {
            _ = try lowerExpr(ctx, cs.expr);
        },
        else => return error.UnsupportedConstruct,
    }
}

fn lowerBlockReturns(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!bool {
    for (block.stmts) |*stmt| {
        if (stmt.* == .ret) {
            try lowerStmt(ctx, stmt, allow_return);
            return true;
        }
        try lowerStmt(ctx, stmt, allow_return);
    }
    if (block.tail_expr) |expr| {
        if (allow_return) {
            try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, expr) });
            return true;
        }
    }
    return false;
}

fn lowerAssignTarget(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!void {
    if (value.* == .call and value.call.func.* == .name) {
        if (ctx.func_record_returns.get(value.call.func.name.ident)) |rec_name| {
            try lowerRecordCallAssign(ctx, name, value.call.func.name.ident, value.call.args, rec_name);
            return;
        }
    }
    if (value.* == .table) {
        try lowerRecordLiteralAssign(ctx, name, value);
        return;
    }
    const v = try lowerExpr(ctx, value);
    if (ctx.locals.get(name)) |slot| {
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v });
}

fn lowerRecordCallAssign(ctx: *LowerCtx, name: []const u8, callee: []const u8, args: []const *ast.Expr, rec_name: []const u8) Error!void {
    const arg0 = if (args.len > 0) try lowerExpr(ctx, args[0]) else .void;
    try ctx.emit(.{ .op = .call_direct, .callee = callee, .lhs = arg0, .record = rec_name, .field = name });
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name, .field = name });
}

fn lowerRecordLiteralAssign(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!void {
    if (table.* != .table) return error.UnsupportedConstruct;
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return error.UnsupportedConstruct,
        };
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, nf.key });
        try ctx.locals.put(ctx.alloc, fk, fslot);
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v });
    }
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = "" });
}

fn lowerRecordReturn(ctx: *LowerCtx, table: *const ast.Expr) Error!void {
    if (table.* != .table) return error.UnsupportedConstruct;
    var vals: [8]dnir.Value = undefined;
    var ni: usize = 0;
    while (ni < vals.len) : (ni += 1) vals[ni] = .void;
    var count: u32 = 0;
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return error.UnsupportedConstruct,
        };
        if (count >= vals.len) return error.UnsupportedConstruct;
        vals[count] = try lowerExpr(ctx, nf.val);
        count += 1;
    }
    try ctx.emit(.{ .op = .ret_record, .lhs = vals[0], .rhs = if (count > 1) vals[1] else .void, .third = if (count > 2) vals[2] else .void, .result = count });
}

fn lowerExpr(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    return switch (expr.*) {
        .int_lit => |i| .{ .i64 = i.val },
        .true_lit => .{ .i64 = 1 },
        .false_lit => .{ .i64 = 0 },
        .string_lit => |s| .{ .str = s.val },
        .name => |n| .{ .local = ctx.locals.get(n.ident) orelse return error.UnsupportedConstruct },
        .binop => |b| try lowerBinop(ctx, b.op, b.lhs, b.rhs),
        .call => try lowerCall(ctx, expr),
        .field => try lowerField(ctx, expr),
        .macro_call => |mc| {
            if (dnir_hardware.parseIntrinsic(mc.name)) |hw| {
                return try lowerHwIntrinsic(ctx, hw, mc.args);
            }
            return error.UnsupportedConstruct;
        },
        else => error.UnsupportedConstruct,
    };
}

fn lowerBinop(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    const t = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = t,
        .binop = switch (op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div, .idiv => .div,
            .mod => .mod,
            .eq => .eq,
            .neq => .neq,
            .lt => .lt,
            .gt => .gt,
            .leq => .leq,
            .geq => .geq,
            else => return error.UnsupportedConstruct,
        },
        .lhs = try lowerExpr(ctx, lhs),
        .rhs = try lowerExpr(ctx, rhs),
    });
    return .{ .temp = t };
}

fn lowerCall(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    if (expr.* != .call) return error.UnsupportedConstruct;
    const c = expr.call;
    if (c.func.* == .field) {
        const f = c.func.field;
        if (f.obj.* == .name) {
            if (ctx.req.exportSymbol(f.obj.name.ident, f.field)) |sym| {
                try ensureExtern(ctx, f.obj.name.ident, f.field, sym);
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .call_extern,
                    .result = t,
                    .callee = sym,
                    .lhs = if (c.args.len > 0) try lowerExpr(ctx, c.args[0]) else .void,
                });
                return .{ .temp = t };
            }
        }
    }
    if (c.func.* == .name) {
        if (dnir_hardware.parseIntrinsic(c.func.name.ident)) |hw| {
            return try lowerHwIntrinsic(ctx, hw, c.args);
        }
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .call_direct,
            .result = t,
            .callee = c.func.name.ident,
            .lhs = if (c.args.len > 0) try lowerExpr(ctx, c.args[0]) else .void,
        });
        return .{ .temp = t };
    }
    return error.UnsupportedConstruct;
}

fn lowerHwIntrinsic(ctx: *LowerCtx, hw: dnir.HwIntrinsic, args: []const *const ast.Expr) Error!dnir.Value {
    return switch (hw) {
        .fence => {
            try ctx.emit(.{ .op = .hw_fence, .hw = .fence });
            return .{ .i64 = 0 };
        },
        .spin_wait => {
            try ctx.emit(.{ .op = .hw_spin, .hw = .spin_wait });
            return .{ .i64 = 0 };
        },
        .popcount, .clz, .ctz => {
            if (args.len != 1) return error.UnsupportedConstruct;
            const t = ctx.freshTemp();
            try ctx.emit(.{
                .op = .hw_unary,
                .hw = hw,
                .result = t,
                .lhs = try lowerExpr(ctx, args[0]),
            });
            return .{ .temp = t };
        },
        .none => error.UnsupportedConstruct,
    };
}

fn ensureExtern(ctx: *LowerCtx, alias: []const u8, field: []const u8, sym: []const u8) Error!void {
    for (ctx.externs.items) |e| {
        if (std.mem.eql(u8, e.symbol, sym)) return;
    }
    const duo = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ alias, field });
    try ctx.externs.append(ctx.alloc, .{ .duo_name = duo, .symbol = try ctx.alloc.dupe(u8, sym) });
}

fn lowerField(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    if (expr.* != .field) return error.UnsupportedConstruct;
    const fld = expr.field;
    if (fld.obj.* == .name) {
        if (ctx.req.constant(fld.obj.name.ident, fld.field)) |val| {
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .const_req, .result = t, .req_alias = fld.obj.name.ident, .field = fld.field, .lhs = .{ .i64 = val } });
            return .{ .temp = t };
        }
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key)) |slot| return .{ .local = slot };
    }
    const t = ctx.freshTemp();
    const base: []const u8 = if (fld.obj.* == .name) fld.obj.name.ident else "";
    try ctx.emit(.{
        .op = .load_field,
        .result = t,
        .req_alias = base,
        .field = fld.field,
    });
    return .{ .temp = t };
}

test "dnir_lower: hardware direct module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    @comp.hint.fence()
        \\    bits = @comp.bit.popcount(47)
        \\    if bits ~= 5 return 1 end
        \\    @comp.hint.fence()
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "pass16_hardware_direct.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.hardware_tier == .scalar);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var saw_fence = false;
    var saw_pop = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .hw_fence) saw_fence = true;
        if (ins.op == .hw_unary and ins.hw == .popcount) saw_pop = true;
    }
    try std.testing.expect(saw_fence and saw_pop);
}

test "dnir_lower: hardware popcount" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    return @popcount(47)
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const ins = m.functions[0].blocks[0].instrs[0];
    try std.testing.expect(ins.op == .hw_unary and ins.hw == .popcount);
    try std.testing.expect(m.hardware_tier == .scalar);
}

test "dnir_lower: ret zero" {
    const alloc = std.testing.allocator;
    const src =
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    defer alloc.free(m.functions[0].name);
    defer alloc.free(m.functions[0].params);
    defer alloc.free(m.functions[0].blocks[0].instrs);
    defer alloc.free(m.functions[0].blocks);
    defer alloc.free(m.functions);
    try std.testing.expect(m.functions[0].blocks[0].instrs[m.functions[0].blocks[0].instrs.len - 1].op == .ret);
}
