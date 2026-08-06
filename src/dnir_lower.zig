//! AST → DNIR lowering for typed native programs (no lua_Value, no C-string codegen).
//!
//! Produces `duo_native_ir.Module` for direct machine backends. C emission is bootstrap-only.
//!
//! Entry points: Duo modules export functions at file scope (file-as-M). There is no
//! Python/Lua-style mandatory `main()` or special entry typing — any eligible function
//! lowers the same way; linker entry is `@export` / CLI target, not a magic name.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const dnir = @import("duo_native_ir.zig");
const native_req_support = @import("native_req_support.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const RT = types.ResolvedType;

pub const Error = error{
    UnsupportedConstruct,
    OutOfMemory,
};

pub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {
    var req = try native_req_support.collectFromModule(alloc, mod);
    defer req.deinit(alloc);

    var records: std.ArrayList(dnir.RecordDesc) = .empty;
    errdefer {
        for (records.items) |r| {
            alloc.free(r.name);
            for (r.fields) |f| alloc.free(f);
            alloc.free(r.fields);
            alloc.free(r.kinds);
        }
        records.deinit(alloc);
    }
    try collectRecords(alloc, &records, mod);

    var f64_kernels: std.StringHashMapUnmanaged(void) = .empty;
    defer f64_kernels.deinit(alloc);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd) or fd.path.len != 1 or fd.method) continue;
        if (funcFfiName(fd.attributes) != null) continue;
        if (isFloatType(fd.func.ret_type) and functionEligible(fd, records.items)) {
            if (f64AbiParamSlots(fd, records.items)) |slots| {
                if (slots > 0) try f64_kernels.put(alloc, fd.path[0], {});
            }
        }
    }

    var functions: std.ArrayList(dnir.Function) = .empty;
    errdefer functions.deinit(alloc);
    var externs: std.ArrayList(dnir.Extern) = .empty;
    errdefer externs.deinit(alloc);
    var func_record_returns: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer func_record_returns.deinit(alloc);

    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd)) continue;
        if (!functionEligible(fd, records.items)) continue;
        const f = try lowerFunction(alloc, fd, records.items, &req, &externs, &func_record_returns, &f64_kernels);
        try functions.append(alloc, f);
    }
    if (functions.items.len == 0) return error.UnsupportedConstruct;
    if (functions.items.len != countModuleFunctions(mod)) return error.UnsupportedConstruct;

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

/// Pass 16 hook: optional semantic graph for provenance/transform ordering.
/// Reorders functions callees-before-callers and attaches graph stable IDs.
pub fn lowerModuleWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: ?*const semantic_graph.SemanticGraph,
) Error!dnir.Module {
    var m = try lowerModule(alloc, mod);
    if (graph) |g| {
        try applyGraphToModule(alloc, g, &m);
    }
    return m;
}

fn applyGraphToModule(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    m: *dnir.Module,
) Error!void {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(alloc);
    for (m.functions) |f| try names.append(alloc, f.name);

    const order = try graph.moduleFunctionEmitOrder(alloc, names.items);
    defer alloc.free(order);

    try reorderFunctions(alloc, m, order);

    const funcs: []dnir.Function = @constCast(m.functions);
    for (funcs) |*f| {
        const id = graph.findByName(f.name) orelse continue;
        const node = graph.get(id) orelse continue;
        if (node.stable_id) |sid| f.graph_stable_id = sid.hash;
    }

    const recs: []dnir.RecordDesc = @constCast(m.records);
    for (recs) |*rec| {
        if (graph.findTableShape(rec.name)) |shape| {
            rec.shape_id = shape.shape_id;
            if (shape.stable_id) |sid| rec.graph_stable_id = sid.hash;
        }
    }
}

fn reorderFunctions(alloc: std.mem.Allocator, m: *dnir.Module, order: []const []const u8) Error!void {
    if (m.functions.len <= 1 or order.len != m.functions.len) return;

    var rank: std.StringHashMapUnmanaged(usize) = .empty;
    defer rank.deinit(alloc);
    for (order, 0..) |name, i| {
        try rank.put(alloc, name, i);
    }

    const funcs: []dnir.Function = @constCast(m.functions);
    const Func = dnir.Function;
    std.mem.sort(Func, funcs, rank, struct {
        fn lessThan(ctx: std.StringHashMapUnmanaged(usize), a: Func, b: Func) bool {
            const ra = ctx.get(a.name) orelse return false;
            const rb = ctx.get(b.name) orelse return true;
            return ra < rb;
        }
    }.lessThan);
}

fn funcFfiName(attrs: []const ast.Attribute) ?[]const u8 {
    for (attrs) |attr| {
        if (!std.mem.eql(u8, attr.name, "ffi")) continue;
        const raw = attr.args orelse return null;
        if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return null;
}

/// Export symbol for DNIR/backends — `add` or qualified `Vec.xplus`.
fn funcExportName(alloc: std.mem.Allocator, fd: *const ast.FuncDecl) Error![]const u8 {
    if (fd.path.len == 1) return try alloc.dupe(u8, fd.path[0]);
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ fd.path[0], fd.path[fd.path.len - 1] });
}

fn shouldIncludeFuncDecl(fd: *const ast.FuncDecl) bool {
    if (fd.is_local) return false;
    if (funcFfiName(fd.attributes) != null) return false;
    if (fd.path.len == 1 and !fd.method) return true;
    if (fd.method and fd.path.len >= 2) return true;
    // Pass 23 §3 — math.add = (a, b) … static module members (dot, not colon).
    if (fd.path.len >= 2 and !fd.method) return true;
    return false;
}

fn countModuleFunctions(mod: *const ast.Module) usize {
    var n: usize = 0;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (shouldIncludeFuncDecl(&stmt.func_decl)) n += 1;
    }
    return n;
}

fn isFloatType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "f64");
}

fn isF64Record(recs: []const dnir.RecordDesc, t: ast.TypeExpr) ?dnir.RecordDesc {
    const r = findRecordName(recs, t) orelse return null;
    if (r.fields.len == 0) return null;
    for (r.kinds) |k| {
        if (k != .f64) return null;
    }
    return r;
}

fn f64AbiParamSlots(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) ?usize {
    var slots: usize = 0;
    for (fd.func.params) |p| {
        if (isFloatType(p.typ)) {
            slots += 1;
        } else if (isF64Record(recs, p.typ)) |r| {
            slots += r.fields.len;
        } else return null;
    }
    return slots;
}

fn functionEligible(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) bool {
    if (fd.func.vararg or fd.func.vararg_name != null) return false;
    if (findRecordName(recs, fd.func.ret_type)) |rec| {
        if (rec.fields.len == 0 or rec.fields.len > 8) return false;
        for (fd.func.params) |p| {
            if (isF64Record(recs, p.typ)) |_| continue;
            if (findRecordName(recs, p.typ)) |_| continue;
            if (!isIntType(p.typ) and !isStrType(p.typ)) return false;
        }
        return true;
    }
    if (isFloatType(fd.func.ret_type)) {
        const slots = f64AbiParamSlots(fd, recs) orelse return false;
        return slots <= 8;
    }
    if (!isIntType(fd.func.ret_type) and !isStrType(fd.func.ret_type)) return false;
    if (fd.func.params.len > 8) return false;
    for (fd.func.params) |p| {
        if (findRecordName(recs, p.typ)) |_| continue;
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
            else if (isFloatType(field.typ))
                .f64
            else {
                ok = false;
                break;
            };
            try names.append(alloc, try alloc.dupe(u8, field.name));
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
    f64_kernels: *const std.StringHashMapUnmanaged(void),
    /// When set, tail/table returns lower to `ret_record` for this record name.
    ret_record: ?[]const u8 = null,
    /// Local slots that hold f64 values inside integer kernels.
    f64_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Names bound to compile-time-known i64 literals (for numeric for step, etc.).
    const_ints: std.StringHashMapUnmanaged(i64) = .empty,
    next_temp: u32 = 0,
    locals: std.StringHashMapUnmanaged(u32) = .empty,
    instrs: std.ArrayList(dnir.Instr) = .empty,

    pub fn deinit(self: *LowerCtx) void {
        var it = self.locals.iterator();
        while (it.next()) |e| self.alloc.free(e.key_ptr.*);
        self.locals.deinit(self.alloc);
        self.f64_slots.deinit(self.alloc);
        var ci = self.const_ints.iterator();
        while (ci.next()) |e| self.alloc.free(e.key_ptr.*);
        self.const_ints.deinit(self.alloc);
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
    f64_kernels: *const std.StringHashMapUnmanaged(void),
) Error!dnir.Function {
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .records = records,
        .req = req,
        .externs = externs,
        .func_record_returns = func_record_returns,
        .f64_kernels = f64_kernels,
        .ret_record = if (findRecordName(records, fd.func.ret_type)) |r| r.name else null,
    };
    defer ctx.deinit();

    for (fd.func.params, 0..) |par, i| {
        const owned = try alloc.dupe(u8, par.name);
        try ctx.locals.put(alloc, owned, @intCast(i));
    }

    try lowerBlock(&ctx, &fd.func.body, true);

    var params: std.ArrayList(dnir.Param) = .empty;
    defer params.deinit(alloc);
    for (fd.func.params) |par| {
        const rec_name = if (findRecordName(records, par.typ)) |r| try alloc.dupe(u8, r.name) else null;
        try params.append(alloc, .{
            .name = try alloc.dupe(u8, par.name),
            .ty = resolveType(par.typ),
            .record = rec_name,
        });
    }

    const blocks = try alloc.alloc(dnir.Block, 1);
    const owned_instrs = try ctx.instrs.toOwnedSlice(alloc);
    try internInstrStrings(alloc, owned_instrs);
    blocks[0] = .{ .instrs = owned_instrs };

    const ret_rec = findRecordName(records, fd.func.ret_type);
    const ret_record_name = if (ret_rec) |r| try alloc.dupe(u8, r.name) else null;
    const export_name = try funcExportName(alloc, fd);
    if (ret_record_name) |rn| {
        try func_record_returns.put(alloc, try alloc.dupe(u8, export_name), rn);
    }

    return .{
        .name = export_name,
        .ret = resolveType(fd.func.ret_type),
        .params = try params.toOwnedSlice(alloc),
        .ret_record = ret_record_name,
        .is_float_kernel = blk: {
            const slots = f64AbiParamSlots(fd, records) orelse break :blk false;
            break :blk slots > 0 and slots <= 8;
        },
        .blocks = blocks,
    };
}

fn resolveType(t: ast.TypeExpr) RT {
    return switch (t) {
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "i64")) break :blk .i64;
            if (std.mem.eql(u8, n, "i32")) break :blk .i32;
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
    return t == .named and (std.mem.eql(u8, t.named, "i64") or std.mem.eql(u8, t.named, "i32"));
}

fn isStrType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "str");
}

fn tryEmitTailDemandReturn(ctx: *LowerCtx, block: *const ast.Block) Error!bool {
    const r = tail_result_demand.blockTailResult(block) orelse return false;
    const ret_ty: RT = if (exprIsF64(ctx, r.expr)) .f64 else .any;
    if (r.expr.* == .table and ctx.ret_record != null) {
        try lowerRecordReturn(ctx, r.expr);
        return true;
    }
    try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.expr), .ty = ret_ty });
    return true;
}

fn lowerBlock(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!void {
    for (block.stmts) |*stmt| try lowerStmt(ctx, stmt, allow_return);
    if (allow_return) _ = try tryEmitTailDemandReturn(ctx, block);
}

fn lowerFieldAssignTarget(ctx: *LowerCtx, obj: *const ast.Expr, field_name: []const u8, value: *const ast.Expr) Error!void {
    if (obj.* != .name) return error.UnsupportedConstruct;
    const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ obj.name.ident, field_name });
    defer ctx.alloc.free(fk);
    const v = try lowerExprCons(ctx, value, .single);
    const store_ty: RT = if (exprIsF64(ctx, value)) .f64 else .any;
    if (ctx.locals.get(fk)) |slot| {
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, fk), slot);
    if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
}

fn exprCallConsumption(expr: *const ast.Expr) types.ReturnConsumption {
    return switch (expr.*) {
        .call, .method_call => .discard,
        else => .single,
    };
}

fn exprReturnsF64(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (expr.* != .call or expr.call.func.* != .name) return false;
    return ctx.f64_kernels.contains(expr.call.func.name.ident);
}

fn lowerStmt(ctx: *LowerCtx, stmt: *const ast.Stmt, allow_return: bool) Error!void {
    switch (stmt.*) {
        .local_decl => |ld| {
            for (ld.names, 0..) |*ln, i| {
                if (i < ld.inits.len) {
                    try lowerAssignTarget(ctx, ln.ident, ld.inits[i]);
                }
                if (ln.typ != .inferred and isFloatType(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.f64_slots.put(ctx.alloc, slot, {});
                }
            }
        },
        .assign => |as| {
            for (as.targets, as.values) |target, value| {
                switch (target.*) {
                    .name => |n| try lowerAssignTarget(ctx, n.ident, value),
                    .field => |f| try lowerFieldAssignTarget(ctx, f.obj, f.field, value),
                    else => return error.UnsupportedConstruct,
                }
            }
        },
        .if_stmt => |is| {
            if (is.binding) |b| {
                try lowerAssignTarget(ctx, b.name, b.expr);
            }
            var end_branches: std.ArrayListUnmanaged(u32) = .empty;
            defer end_branches.deinit(ctx.alloc);

            const cond = try lowerExpr(ctx, is.cond);
            var fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br_if_not, .lhs = cond, .branch_target = 0 });

            const then_ret = try lowerBlockReturns(ctx, &is.then, allow_return);
            if (!then_ret) {
                try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                try ctx.emit(.{ .op = .br, .branch_target = 0 });
            }

            for (is.elseifs) |elseif| {
                const next_idx: u32 = @intCast(ctx.instrs.items.len);
                ctx.instrs.items[fail_idx].branch_target = next_idx;
                const econd = try lowerExpr(ctx, elseif.cond);
                fail_idx = ctx.instrs.items.len;
                try ctx.emit(.{ .op = .br_if_not, .lhs = econd, .branch_target = 0 });
                const branch_ret = try lowerBlockReturns(ctx, &elseif.body, allow_return);
                if (!branch_ret) {
                    try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                    try ctx.emit(.{ .op = .br, .branch_target = 0 });
                }
            }

            const else_start: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = else_start;
            if (is.else_body) |*eb| _ = try lowerBlockReturns(ctx, eb, allow_return);

            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            for (end_branches.items) |*br_off| {
                ctx.instrs.items[br_off.*].branch_target = end_idx;
            }
        },
        .while_loop => |ws| {
            const head_idx: u32 = @intCast(ctx.instrs.items.len);
            const cond = try lowerExpr(ctx, ws.cond);
            const fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br_if_not, .lhs = cond, .branch_target = 0 });
            _ = try lowerBlockReturns(ctx, &ws.body, allow_return);
            try ctx.emit(.{ .op = .br, .branch_target = head_idx });
            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = end_idx;
        },
        .num_for => |nf| try lowerNumFor(ctx, nf, allow_return),
        .ret => |r| {
            if (r.vals.len == 0) {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 } });
            } else if (r.vals[0].* == .table) {
                try lowerRecordReturn(ctx, r.vals[0]);
            } else {
                const ret_ty: RT = if (exprIsF64(ctx, r.vals[0])) .f64 else .any;
                try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.vals[0]), .ty = ret_ty });
            }
        },
        .expr_stmt => |es| {
            _ = try lowerExprCons(ctx, es.expr, exprCallConsumption(es.expr));
        },
        .call_stmt => |cs| {
            _ = try lowerExprCons(ctx, cs.expr, .discard);
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
    if (allow_return) return try tryEmitTailDemandReturn(ctx, block);
    return false;
}

fn intLiteralStep(expr: *const ast.Expr) ?i64 {
    return switch (expr.*) {
        .int_lit => |i| i.val,
        .unop => |u| blk: {
            if (u.op != .neg or u.operand.* != .int_lit) break :blk null;
            break :blk -u.operand.int_lit.val;
        },
        else => null,
    };
}

fn resolveIntStep(ctx: *LowerCtx, step: *const ast.Expr) Error!i64 {
    if (intLiteralStep(step)) |v| return v;
    if (step.* == .name) {
        if (ctx.const_ints.get(step.name.ident)) |v| return v;
    }
    return error.UnsupportedConstruct;
}

fn lowerNumFor(ctx: *LowerCtx, loop: anytype, allow_return: bool) Error!void {
    if (loop.var_typ != .inferred and !isIntType(loop.var_typ)) return error.UnsupportedConstruct;
    const step_lit: ?i64 = if (loop.step) |step| resolveIntStep(ctx, step) catch null else 1;
    if (step_lit == null) {
        try lowerRuntimeNumFor(ctx, loop, allow_return);
        return;
    }
    const step = step_lit.?;
    if (step == 0) return error.UnsupportedConstruct;
    try lowerConstNumFor(ctx, loop, allow_return, step);
}

fn lowerConstNumFor(ctx: *LowerCtx, loop: anytype, allow_return: bool, step_lit: i64) Error!void {
    try lowerAssignTarget(ctx, loop.var_name, loop.start);
    const i_slot = ctx.locals.get(loop.var_name) orelse return error.UnsupportedConstruct;
    const head_idx: u32 = @intCast(ctx.instrs.items.len);
    const cond_temp = ctx.freshTemp();
    const cmp_op: dnir.BinOpTag = if (step_lit > 0) .leq else .geq;
    try ctx.emit(.{
        .op = .binop,
        .result = cond_temp,
        .binop = cmp_op,
        .lhs = .{ .local = i_slot },
        .rhs = try lowerExpr(ctx, loop.stop),
    });
    const fail_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = cond_temp }, .branch_target = 0 });
    _ = try lowerBlockReturns(ctx, &loop.body, allow_return);
    const next_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = next_temp,
        .binop = .add,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .i64 = step_lit },
    });
    try ctx.emit(.{ .op = .store_local, .result = i_slot, .lhs = .{ .temp = next_temp } });
    try ctx.emit(.{ .op = .br, .branch_target = head_idx });
    const end_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[fail_idx].branch_target = end_idx;
}

fn lowerRuntimeNumFor(ctx: *LowerCtx, loop: anytype, allow_return: bool) Error!void {
    try lowerAssignTarget(ctx, loop.var_name, loop.start);
    const i_slot = ctx.locals.get(loop.var_name) orelse return error.UnsupportedConstruct;

    const stop_key = try ctx.alloc.dupe(u8, "__dnir_stop");
    const stop_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, stop_key, stop_slot);
    const stop_v = try lowerExpr(ctx, loop.stop);
    try ctx.emit(.{ .op = .store_local, .result = stop_slot, .lhs = stop_v });

    const step_key = try ctx.alloc.dupe(u8, "__dnir_step");
    const step_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, step_key, step_slot);
    const step_v = if (loop.step) |step| try lowerExpr(ctx, step) else @as(dnir.Value, .{ .i64 = 1 });
    try ctx.emit(.{ .op = .store_local, .result = step_slot, .lhs = step_v });

    const head_idx: u32 = @intCast(ctx.instrs.items.len);

    const sign_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = sign_temp,
        .binop = .lt,
        .lhs = .{ .local = step_slot },
        .rhs = .{ .i64 = 0 },
    });
    const to_pos_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = sign_temp }, .branch_target = 0 });

    const neg_cond = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = neg_cond,
        .binop = .geq,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = stop_slot },
    });
    const neg_fail = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = neg_cond }, .branch_target = 0 });
    const to_body_from_neg = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });

    const pos_check_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[to_pos_idx].branch_target = pos_check_idx;

    const pos_cond = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = pos_cond,
        .binop = .leq,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = stop_slot },
    });
    const pos_fail = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = pos_cond }, .branch_target = 0 });

    const body_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[to_body_from_neg].branch_target = body_idx;

    _ = try lowerBlockReturns(ctx, &loop.body, allow_return);

    const next_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = next_temp,
        .binop = .add,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = step_slot },
    });
    try ctx.emit(.{ .op = .store_local, .result = i_slot, .lhs = .{ .temp = next_temp } });
    try ctx.emit(.{ .op = .br, .branch_target = head_idx });

    const exit_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[neg_fail].branch_target = exit_idx;
    ctx.instrs.items[pos_fail].branch_target = exit_idx;
}

fn exprIsF64(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .float_lit => true,
        .call => exprReturnsF64(ctx, expr),
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.f64_slots.contains(slot);
        },
        else => false,
    };
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
    const v = try lowerExprCons(ctx, value, .single);
    const store_ty: RT = if (exprIsF64(ctx, value)) .f64 else .any;
    if (ctx.locals.get(name)) |slot| {
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        if (intLiteralStep(value)) |n| {
            const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
            if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
            gop.value_ptr.* = n;
        }
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
    if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    if (intLiteralStep(value)) |n| {
        const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
        if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
        gop.value_ptr.* = n;
    }
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
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
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
    const rec_name = inferRecordNameFromTable(ctx.records, table) orelse "";
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name });
}

/// Match a table literal's named fields to a module record descriptor.
fn inferRecordNameFromTable(records: []const dnir.RecordDesc, table: *const ast.Expr) ?[]const u8 {
    if (table.* != .table) return null;
    for (records) |rec| {
        if (tableMatchesRecord(table, rec)) return rec.name;
    }
    return null;
}

fn tableMatchesRecord(table: *const ast.Expr, rec: dnir.RecordDesc) bool {
    if (table.* != .table) return false;
    if (table.table.fields.len != rec.fields.len) return false;
    for (rec.fields) |fname| {
        var found = false;
        for (table.table.fields) |fld| {
            const nf = switch (fld) {
                .named => |n| n,
                else => return false,
            };
            if (std.mem.eql(u8, nf.key, fname)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

/// Lower inline table literal as a temp record value for call arguments.
fn lowerInlineRecordArg(ctx: *LowerCtx, table: *const ast.Expr, rec_name: []const u8) Error!dnir.Value {
    if (table.* != .table) return error.UnsupportedConstruct;
    const rec_slot = ctx.freshTemp();
    const anon = try std.fmt.allocPrint(ctx.alloc, "__rec{d}", .{rec_slot});
    defer ctx.alloc.free(anon);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return error.UnsupportedConstruct,
        };
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ anon, nf.key });
        try ctx.locals.put(ctx.alloc, fk, fslot);
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name });
    return .{ .temp = rec_slot };
}

fn recordFieldsPresent(ctx: *LowerCtx, name: []const u8, rec: dnir.RecordDesc) bool {
    for (rec.fields) |fname| {
        const key = std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, fname }) catch return false;
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key) == null) return false;
    }
    return true;
}

fn emitF64RecordFieldsFromName(ctx: *LowerCtx, name: []const u8, slot: *u32) Error!bool {
    for (ctx.records) |rec| {
        var all_f64 = rec.fields.len > 0;
        for (rec.kinds) |k| {
            if (k != .f64) all_f64 = false;
        }
        if (!all_f64 or !recordFieldsPresent(ctx, name, rec)) continue;
        for (rec.fields) |fname| {
            const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, fname });
            const field_slot = ctx.locals.get(key) orelse return error.UnsupportedConstruct;
            ctx.alloc.free(key);
            const t = ctx.freshTemp();
            try ctx.emit(.{
                .op = .load_local,
                .result = t,
                .lhs = .{ .local = field_slot },
                .ty = .f64,
            });
            try ctx.emit(.{ .op = .fp_mov_arg, .result = slot.*, .lhs = .{ .temp = t } });
            slot.* += 1;
            if (slot.* > 8) return error.UnsupportedConstruct;
        }
        return true;
    }
    return false;
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
    try ctx.emit(.{
        .op = .ret_record,
        .record = ctx.ret_record orelse "",
        .lhs = vals[0],
        .rhs = if (count > 1) vals[1] else .void,
        .third = if (count > 2) vals[2] else .void,
        .result = count,
    });
}

fn lowerExpr(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    return lowerExprCons(ctx, expr, .single);
}

fn lowerExprCons(
    ctx: *LowerCtx,
    expr: *const ast.Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    return switch (expr.*) {
        .int_lit => |i| .{ .i64 = i.val },
        .float_lit => |fl| .{ .f64 = fl.val },
        .true_lit => .{ .i64 = 1 },
        .false_lit => .{ .i64 = 0 },
        .string_lit => |s| .{ .str = s.val },
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse return error.UnsupportedConstruct;
            if (ctx.f64_slots.contains(slot)) {
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_local, .result = t, .lhs = .{ .local = slot }, .ty = .f64 });
                break :blk dnir.Value{ .temp = t };
            }
            break :blk dnir.Value{ .local = slot };
        },
        .binop => |b| try lowerBinop(ctx, b.op, b.lhs, b.rhs),
        .unop => |u| blk: {
            if (u.op == .neg and u.operand.* == .int_lit) {
                break :blk dnir.Value{ .i64 = -u.operand.int_lit.val };
            }
            return error.UnsupportedConstruct;
        },
        .call => try lowerCall(ctx, expr, consumption),
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
    const f64_op = exprIsF64(ctx, lhs) or exprIsF64(ctx, rhs);
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
        .ty = if (f64_op) .f64 else .any,
    });
    return .{ .temp = t };
}

fn emitScalarCallArgs(ctx: *LowerCtx, args: []const *ast.Expr) Error!void {
    if (args.len <= 1) return;
    for (args, 0..) |arg, i| {
        if (i >= 8) return error.UnsupportedConstruct;
        try ctx.emit(.{ .op = .mov_arg, .result = @intCast(i), .lhs = try lowerExpr(ctx, arg) });
    }
}

fn scalarCallLhs(ctx: *LowerCtx, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len == 0) return .void;
    if (args.len == 1) {
        const arg = args[0];
        if (arg.* == .table) {
            if (inferRecordNameFromTable(ctx.records, arg)) |rec_name| {
                return try lowerInlineRecordArg(ctx, arg, rec_name);
            }
        }
        return try lowerExpr(ctx, arg);
    }
    try emitScalarCallArgs(ctx, args);
    return .void;
}

fn lowerCall(ctx: *LowerCtx, expr: *const ast.Expr, consumption: types.ReturnConsumption) Error!dnir.Value {
    if (expr.* != .call) return error.UnsupportedConstruct;
    const c = expr.call;
    const discard = consumption == .discard;
    if (c.func.* == .field) {
        const f = c.func.field;
        if (f.obj.* == .name) {
            if (ctx.req.exportSymbol(f.obj.name.ident, f.field)) |sym| {
                try ensureExtern(ctx, f.obj.name.ident, f.field, sym);
                if (discard) {
                    try ctx.emit(.{
                        .op = .call_extern,
                        .callee = sym,
                        .lhs = if (c.args.len > 0) try lowerExpr(ctx, c.args[0]) else .void,
                    });
                    return .void;
                }
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .call_extern,
                    .result = t,
                    .callee = sym,
                    .lhs = if (c.args.len > 0) try lowerExpr(ctx, c.args[0]) else .void,
                });
                return .{ .temp = t };
            }
            // Static module member: math.add(a, b) → call_direct math.add
            const qualified = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
            const arg0 = try scalarCallLhs(ctx, c.args);
            if (discard) {
                try ctx.emit(.{ .op = .call_direct, .callee = qualified, .lhs = arg0 });
                return .void;
            }
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .call_direct, .result = t, .callee = qualified, .lhs = arg0 });
            return .{ .temp = t };
        }
    }
    if (c.func.* == .name) {
        if (dnir_hardware.parseIntrinsic(c.func.name.ident)) |hw| {
            return try lowerHwIntrinsic(ctx, hw, c.args);
        }
        const callee = c.func.name.ident;
        if (ctx.f64_kernels.contains(callee)) {
            return try lowerF64KernelCall(ctx, callee, c.args);
        }
        const arg0 = try scalarCallLhs(ctx, c.args);
        if (discard) {
            try ctx.emit(.{
                .op = .call_direct,
                .callee = callee,
                .lhs = arg0,
            });
            return .void;
        }
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .call_direct,
            .result = t,
            .callee = callee,
            .lhs = arg0,
        });
        return .{ .temp = t };
    }
    return error.UnsupportedConstruct;
}

fn lowerF64KernelCall(ctx: *LowerCtx, callee: []const u8, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len == 0) return error.UnsupportedConstruct;
    var slot: u32 = 0;
    for (args) |arg| {
        switch (arg.*) {
            .table => {
                if (inferRecordNameFromTable(ctx.records, arg)) |rec_name| {
                    _ = try lowerInlineRecordArg(ctx, arg, rec_name);
                }
                for (arg.table.fields) |fld| {
                    const val = switch (fld) {
                        .named => |nf| nf.val,
                        .positional => |v| v,
                        else => return error.UnsupportedConstruct,
                    };
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, val) });
                    slot += 1;
                    if (slot > 8) return error.UnsupportedConstruct;
                }
            },
            .name => |n| {
                if (try emitF64RecordFieldsFromName(ctx, n.ident, &slot)) {} else {
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                    slot += 1;
                    if (slot > 8) return error.UnsupportedConstruct;
                }
            },
            else => {
                try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                slot += 1;
                if (slot > 8) return error.UnsupportedConstruct;
            },
        }
    }
    if (slot == 0) return error.UnsupportedConstruct;
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_direct, .result = t, .callee = callee, .ty = .f64 });
    return .{ .temp = t };
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

test "dnir_lower: f64 record kernel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "pass4_dnir.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    try std.testing.expect(m.functions[0].is_float_kernel or m.functions[1].is_float_kernel);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var saw_fmul = false;
    for (m.functions) |f| {
        if (!f.is_float_kernel) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .binop and ins.binop == .mul) saw_fmul = true;
            if (ins.op == .load_field) try std.testing.expect(ins.field.len > 0);
        }
    }
    try std.testing.expect(saw_fmul);
}

test "dnir_lower: f64 kernel call with table literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "pass4_call.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    var saw_fp_mov = false;
    var saw_f64_call = false;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) {
            for (f.blocks[0].instrs) |ins| {
                if (ins.op == .fp_mov_arg) saw_fp_mov = true;
                if (ins.op == .call_direct and ins.ty == .f64) saw_f64_call = true;
            }
        }
    }
    try std.testing.expect(saw_fp_mov and saw_f64_call);
}

test "dnir_lower: while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    i = 0
        \\    while i < 3
        \\        i = i + 1
        \\    end
        \\    i
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "while.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_back_branch = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .br and ins.branch_target < m.functions[0].blocks[0].instrs.len) saw_back_branch = true;
    }
    try std.testing.expect(saw_back_branch);
}

test "dnir_lower: numeric for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    sum = 0
        \\    for i = 0, 2
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "num_for.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_inc = false;
    var saw_back = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .add) saw_inc = true;
        if (ins.op == .br and ins.branch_target < m.functions[0].blocks[0].instrs.len) saw_back = true;
    }
    try std.testing.expect(saw_inc and saw_back);
}

test "dnir_lower: f64 local in integer main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    r: f64 = distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64_local.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var saw_f64_store = false;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .store_local and ins.ty == .f64) saw_f64_store = true;
    }
    try std.testing.expect(saw_f64_store);
}

test "dnir_lower: multi-arg f64 kernel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\add2(a: f64, b: f64): f64
        \\    a + b
        \\end
        \\main(): i64
        \\    add2(1.0, 2.0)
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "add2.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var fp_movs: u32 = 0;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .fp_mov_arg) fp_movs += 1;
        }
    }
    try std.testing.expect(fp_movs == 2);
}

test "dnir_lower: multi-arg i64 call_direct uses mov_arg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    math.add(10, 20)
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "math_add_call.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var mov_args: u32 = 0;
    var saw_call: bool = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .mov_arg) mov_args += 1;
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "math.add")) {
                saw_call = true;
                try std.testing.expect(ins.lhs == .void);
            }
        }
    }
    try std.testing.expect(saw_call);
    try std.testing.expect(mov_args == 2);
}

test "dnir_lower: f64 kernel call with record variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    p = { x = 3.0, y = 4.0 }
        \\    r: f64 = distance2(p)
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "record_var.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var fp_movs: u32 = 0;
    var load_f64_fields: u32 = 0;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .fp_mov_arg) fp_movs += 1;
        if (ins.op == .load_local and ins.ty == .f64) load_f64_fields += 1;
    }
    try std.testing.expect(fp_movs == 2);
    try std.testing.expect(load_f64_fields == 2);
}

test "dnir_lower: main returns f64 kernel tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): f64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "main_f64.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    try std.testing.expect(main.ret == .f64);
    try std.testing.expect(!main.is_float_kernel);
    const last = main.blocks[0].instrs[main.blocks[0].instrs.len - 1];
    try std.testing.expect(last.op == .ret and last.ty == .f64);
}

test "dnir_lower: no mandatory main — entry function lowers uniformly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "run.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 1);
    try std.testing.expect(std.mem.eql(u8, m.functions[0].name, "run"));
}

test "dnir_lower: implicit f64 assign" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    r = distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "implicit_f64.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var saw_f64_store = false;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .store_local and ins.ty == .f64) saw_f64_store = true;
    }
    try std.testing.expect(saw_f64_store);
}

test "dnir_lower: numeric for negative step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    sum = 0
        \\    for i = 3, 1, -1
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "neg_for.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_geq = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .geq) saw_geq = true;
    }
    try std.testing.expect(saw_geq);
}

test "dnir_lower: numeric for const step binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    step = -1
        \\    sum = 0
        \\    for i = 3, 1, step
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "const_step.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_geq = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .geq) saw_geq = true;
    }
    try std.testing.expect(saw_geq);
}

test "dnir_lower: ret zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions[0].blocks[0].instrs[m.functions[0].blocks[0].instrs.len - 1].op == .ret);
}

test "dnir_lower: f64 compare in integer main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\length2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    if length2({ x = 3.0, y = 4.0 }) == 25.0
        \\        return 0
        \\    else
        \\        return 1
        \\    end
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64_cmp.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_f64_eq = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .binop and ins.binop == .eq and ins.ty == .f64) saw_f64_eq = true;
            }
        }
    }
    try std.testing.expect(saw_f64_eq);
}

test "dnir_lower: if elseif else chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\pick(n: i64): i64
        \\    out = 0
        \\    if n < 0
        \\        out = 11
        \\    elseif n == 0
        \\        out = 13
        \\    elseif n > 10
        \\        out = 17
        \\    else
        \\        out = 19
        \\    end
        \\    out
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "elseif.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var br_if_not: u32 = 0;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .br_if_not) br_if_not += 1;
    }
    try std.testing.expect(br_if_not >= 3);
}

test "dnir_lower: numeric for runtime step parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\sum_to(n: i64, step: i64): i64
        \\    s = 0
        \\    for i = 1, n, step
        \\        s = s + i
        \\    end
        \\    s
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "runtime_step.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_step_local = false;
    var saw_dynamic_add = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "sum_to")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .store_local and ins.lhs == .local and ins.lhs.local > 0) saw_step_local = true;
            if (ins.op == .binop and ins.binop == .add and ins.rhs == .local) saw_dynamic_add = true;
        }
    }
    try std.testing.expect(saw_step_local);
    try std.testing.expect(saw_dynamic_add);
}

test "dnir_lower: lowerModuleWithGraph matches lowerModule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m_direct = try lowerModule(alloc, &mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "test.duo");
    const m_graph = try lowerModuleWithGraph(alloc, &mod, &g);
    try std.testing.expect(m_direct.functions.len == m_graph.functions.len);
    try std.testing.expect(m_direct.hardware_tier == m_graph.hardware_tier);
    try std.testing.expect(m_direct.functions[0].blocks[0].instrs.len == m_graph.functions[0].blocks[0].instrs.len);
    try std.testing.expect(m_graph.functions[0].graph_stable_id != null);
}

test "dnir_lower: graph orders callees before callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "graph_order.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "graph_order.duo");
    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    var idx_distance: ?usize = null;
    var idx_main: ?usize = null;
    for (m.functions, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "distance2")) idx_distance = i;
        if (std.mem.eql(u8, f.name, "main")) idx_main = i;
        try std.testing.expect(f.graph_stable_id != null);
    }
    try std.testing.expect(idx_distance != null and idx_main != null);
    try std.testing.expect(idx_distance.? < idx_main.?);
}

test "dnir_lower: graph attaches shape_id to native records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "shape.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "shape.duo");
    const shape_node = g.findTableShape("Point") orelse return error.TestExpectedEqual;
    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    try std.testing.expect(m.records.len >= 1);
    var found = false;
    for (m.records) |rec| {
        if (!std.mem.eql(u8, rec.name, "Point")) continue;
        found = true;
        try std.testing.expect(rec.shape_id != null);
        try std.testing.expectEqual(shape_node.shape_id.?, rec.shape_id.?);
        try std.testing.expect(rec.graph_stable_id != null);
    }
    try std.testing.expect(found);
}

test "dnir_lower: record-return tail and call assign emit init_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: i64, y: i64 }
        \\make(): Point
        \\    { x = 1, y = 2 }
        \\end
        \\main(): i64
        \\    local p = make()
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "rec.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_init_record = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .init_record and std.mem.eql(u8, ins.record, "Point")) {
                    saw_init_record = true;
                }
            }
        }
    }
    try std.testing.expect(saw_init_record);
}

test "dnir_lower: f64 record-return tail lowers ret_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\make(): Point
        \\    { x = 1.0, y = 2.0 }
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64ret.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    var saw_ret_record = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "make")) continue;
        try std.testing.expect(f.ret_record != null);
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .ret_record and std.mem.eql(u8, ins.record, "Point")) saw_ret_record = true;
            }
        }
    }
    try std.testing.expect(saw_ret_record);
}

test "dnir_lower: f64 kernel inline table emits init_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64tbl.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_init = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .init_record and std.mem.eql(u8, ins.record, "Point")) saw_init = true;
            }
        }
    }
    try std.testing.expect(saw_init);
}

test "dnir_lower: discard call_stmt omits call result temp" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\side(): i64
        \\    0
        \\end
        \\main(): i64
        \\    side();
        \\    1
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "discard.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_discard_call = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "side") and ins.result == null) {
                    saw_discard_call = true;
                }
            }
        }
    }
    try std.testing.expect(saw_discard_call);
}

test "dnir_lower: trailing compound assign returns assigned local" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\double(x: i64): i64
        \\    x *= 2
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "trail.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const f = m.functions[0];
    var ret_count: usize = 0;
    var ret_from_param = false;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op != .ret) continue;
            ret_count += 1;
            if (ins.lhs == .local and ins.lhs.local == 0) ret_from_param = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ret_count);
    try std.testing.expect(ret_from_param);
}

test "dnir_lower: dot static member exports module.method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "static.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expectEqual(@as(usize, 2), m.functions.len);
    var saw = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "math.add")) continue;
        saw = true;
        try std.testing.expectEqual(@as(usize, 2), f.params.len);
        try std.testing.expect(f.ret == .i64);
    }
    try std.testing.expect(saw);
}

test "dnir_lower: colon method compound field assign exports Type.method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "Vec: @{ x: i32 }\nVec:xplus = (amt): i32\n    self.x += amt\nend";
    var lex = @import("lexer.zig").Lexer.init(src, "method.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sema = @import("sema.zig").Sema.init(alloc);
    try sema.check_module(&mod);
    try std.testing.expectEqual(@as(u32, 0), sema.errors);
    const m = try lowerModule(alloc, &mod);
    try std.testing.expectEqual(@as(usize, 1), m.functions.len);
    try std.testing.expectEqualStrings("Vec.xplus", m.functions[0].name);
    try std.testing.expect(m.functions[0].ret == .i32);
}

test "dnir_lower: trailing compound field assign returns updated field slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Vec: @{ x: i32 }
        \\bump = (v: Vec, amt: i32): i32
        \\    v.x += amt
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "field.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const f = m.functions[0];
    var ret_count: usize = 0;
    var ret_from_field = false;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op != .ret) continue;
            ret_count += 1;
            if (ins.lhs == .local and ins.lhs.local != 0 and ins.lhs.local != 1) ret_from_field = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ret_count);
    try std.testing.expect(ret_from_field);
}

test "dnir_lower: if binding assigns before branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\get(): i64
        \\    5
        \\end
        \\main(): i64
        \\    if v = get() v > 0
        \\        v
        \\    else
        \\        0
        \\    end
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "ifbind.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_get_call = false;
    var saw_v_store = false;
    var br_after_store = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            var i: usize = 0;
            while (i < b.instrs.len) : (i += 1) {
                const ins = b.instrs[i];
                if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "get")) saw_get_call = true;
                if (ins.op == .store_local and ins.result != null) saw_v_store = true;
                if (saw_v_store and (ins.op == .br_if_not or ins.op == .br_if)) br_after_store = true;
            }
        }
    }
    try std.testing.expect(saw_get_call);
    try std.testing.expect(saw_v_store);
    try std.testing.expect(br_after_store);
}
