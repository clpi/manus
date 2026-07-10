const std = @import("std");
const ast = @import("ast.zig");

pub const Error = error{
    UnknownMacro,
    ArityMismatch,
    MacroBodyExpectedExpression,
    MacroBodyExpectedBlock,
    CaptureExpectedIdentifier,
    UnsupportedUnquote,
    ExpansionLimitExceeded,
} || std.mem.Allocator.Error;

pub const Expander = struct {
    const max_expansion_depth = 64;
    const max_expansion_nodes = 100_000;

    alloc: std.mem.Allocator,
    macros: std.StringHashMapUnmanaged(*const ast.MacroDef) = .empty,
    expansion_id: u64 = 0,
    expansion_depth: u32 = 0,
    expanded_nodes: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Expander {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Expander) void {
        self.macros.deinit(self.alloc);
    }

    pub fn expandModule(self: *Expander, module: *ast.Module) Error!void {
        self.expansion_depth = 0;
        self.expanded_nodes = 0;
        module.body = try self.expandBlock(module.body);
    }

    fn expandBlock(self: *Expander, block: ast.Block) Error!ast.Block {
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        for (block.stmts) |*stmt| {
            if (stmt.* == .macro_def) {
                try self.macros.put(self.alloc, stmt.macro_def.name, &stmt.macro_def);
                continue;
            }
            if (try self.expandStmtMacro(stmt.*, null)) |expanded| {
                try stmts.appendSlice(self.alloc, expanded);
                continue;
            }
            try stmts.append(self.alloc, try self.expandStmt(stmt.*));
        }
        const tail_expr = try self.expandTailExpr(block.tail_expr, &stmts, null);
        return .{
            .loc = block.loc,
            .stmts = try stmts.toOwnedSlice(self.alloc),
            .tail_expr = tail_expr,
        };
    }

    fn expandStmt(self: *Expander, stmt: ast.Stmt) Error!ast.Stmt {
        return switch (stmt) {
            .local_decl => |x| .{ .local_decl = .{
                .loc = x.loc,
                .names = try self.copyLocalNames(x.names, null),
                .inits = try self.expandExprSlice(x.inits),
            } },
            .const_decl => |x| .{ .const_decl = .{
                .loc = x.loc,
                .ident = x.ident,
                .typ = x.typ,
                .val = try self.expandExpr(x.val),
            } },
            .global_decl => |x| .{ .global_decl = .{
                .loc = x.loc,
                .star = x.star,
                .names = try self.copyLocalNames(x.names, null),
                .inits = try self.expandExprSlice(x.inits),
            } },
            .assign => |x| .{ .assign = .{
                .loc = x.loc,
                .targets = try self.expandExprSlice(x.targets),
                .values = try self.expandExprSlice(x.values),
            } },
            .call_stmt => |x| .{ .call_stmt = .{ .loc = x.loc, .expr = try self.expandExpr(x.expr) } },
            .expr_stmt => |x| .{ .expr_stmt = .{ .loc = x.loc, .expr = try self.expandExpr(x.expr) } },
            .do_block => |x| .{ .do_block = .{ .loc = x.loc, .body = try self.expandBlock(x.body) } },
            .while_loop => |x| .{ .while_loop = .{
                .loc = x.loc,
                .cond = try self.expandExpr(x.cond),
                .body = try self.expandBlock(x.body),
            } },
            .repeat_loop => |x| .{ .repeat_loop = .{
                .loc = x.loc,
                .body = try self.expandBlock(x.body),
                .cond = try self.expandExpr(x.cond),
            } },
            .if_stmt => |x| .{ .if_stmt = .{
                .loc = x.loc,
                .cond = try self.expandExpr(x.cond),
                .then = try self.expandBlock(x.then),
                .elseifs = try self.expandElseIfs(x.elseifs),
                .else_body = if (x.else_body) |body| try self.expandBlock(body) else null,
            } },
            .num_for => |x| .{ .num_for = .{
                .loc = x.loc,
                .var_name = x.var_name,
                .var_typ = x.var_typ,
                .start = try self.expandExpr(x.start),
                .stop = try self.expandExpr(x.stop),
                .step = if (x.step) |expr| try self.expandExpr(expr) else null,
                .body = try self.expandBlock(x.body),
            } },
            .gen_for => |x| .{ .gen_for = .{
                .loc = x.loc,
                .vars = x.vars,
                .iters = try self.expandExprSlice(x.iters),
                .body = try self.expandBlock(x.body),
            } },
            .func_decl => |x| .{ .func_decl = .{
                .loc = x.loc,
                .path = x.path,
                .method = x.method,
                .is_local = x.is_local,
                .func = try self.expandFuncBody(x.func, null),
                .attributes = x.attributes,
            } },
            .ret => |x| .{ .ret = .{ .loc = x.loc, .vals = try self.expandExprSlice(x.vals) } },
            .brk => stmt,
            .cont => stmt,
            .goto_stmt => stmt,
            .label_stmt => stmt,
            .match_stmt => |x| .{ .match_stmt = try self.expandMatch(x) },
            .try_stmt => |x| .{ .try_stmt = .{
                .loc = x.loc,
                .body = try self.expandBlock(x.body),
                .catches = try self.expandCatches(x.catches),
                .defers = try self.expandDefers(x.defers),
            } },
            .defer_stmt => |x| .{ .defer_stmt = .{ .loc = x.loc, .body = try self.expandBlock(x.body) } },
            .enum_def, .concept_def, .alias_def => stmt,
            .macro_def => stmt,
        };
    }

    fn expandExpr(self: *Expander, expr: *ast.Expr) Error!*ast.Expr {
        var ctx = HygieneContext.init(self.alloc, 0);
        defer ctx.deinit();
        return self.cloneExpr(expr, &ctx);
    }

    fn macroCallFromStmt(stmt: ast.Stmt) ?ast.MacroCall {
        return switch (stmt) {
            .expr_stmt => |x| if (x.expr.* == .macro_call) x.expr.macro_call else null,
            .call_stmt => |x| if (x.expr.* == .macro_call) x.expr.macro_call else null,
            else => null,
        };
    }

    fn expandStmtMacro(self: *Expander, stmt: ast.Stmt, parent_ctx: ?*HygieneContext) Error!?[]ast.Stmt {
        const call = macroCallFromStmt(stmt) orelse return null;
        const def = self.macros.get(call.name) orelse return null;
        if (def.body != .block) return null;
        if (parent_ctx) |ctx| return try self.expandMacroStmtCall(call, ctx);
        var top_ctx = HygieneContext.init(self.alloc, 0);
        defer top_ctx.deinit();
        return try self.expandMacroStmtCall(call, &top_ctx);
    }

    fn expandTailExpr(
        self: *Expander,
        maybe_tail: ?*ast.Expr,
        stmts: *std.ArrayList(ast.Stmt),
        parent_ctx: ?*HygieneContext,
    ) Error!?*ast.Expr {
        const tail = maybe_tail orelse return null;
        if (tail.* == .macro_call) {
            if (self.macros.get(tail.macro_call.name)) |def| {
                if (def.body == .block) {
                    const expanded = if (parent_ctx) |ctx|
                        try self.expandMacroStmtCall(tail.macro_call, ctx)
                    else blk: {
                        var top_ctx = HygieneContext.init(self.alloc, 0);
                        defer top_ctx.deinit();
                        break :blk try self.expandMacroStmtCall(tail.macro_call, &top_ctx);
                    };
                    try stmts.appendSlice(self.alloc, expanded);
                    return null;
                }
            }
        }
        if (parent_ctx) |ctx| return self.cloneExpr(tail, ctx);
        return self.expandExpr(tail);
    }

    fn expandMacroCall(self: *Expander, call: ast.MacroCall, ctx: *HygieneContext) Error!*ast.Expr {
        if (self.expansion_depth >= max_expansion_depth) return Error.ExpansionLimitExceeded;
        const def = self.macros.get(call.name) orelse return Error.UnknownMacro;
        if (def.params.len != call.args.len) return Error.ArityMismatch;
        if (def.body != .expr) return Error.MacroBodyExpectedExpression;

        self.expansion_depth += 1;
        defer self.expansion_depth -= 1;
        self.expansion_id += 1;
        var macro_ctx = HygieneContext.init(self.alloc, self.expansion_id);
        defer macro_ctx.deinit();
        for (def.params, call.args) |param, arg| {
            try macro_ctx.bindings.put(self.alloc, param, try self.cloneExpr(arg, ctx));
        }
        return self.cloneExpr(def.body.expr, &macro_ctx);
    }

    fn expandMacroStmtCall(self: *Expander, call: ast.MacroCall, ctx: *HygieneContext) Error![]ast.Stmt {
        if (self.expansion_depth >= max_expansion_depth) return Error.ExpansionLimitExceeded;
        const def = self.macros.get(call.name) orelse return Error.UnknownMacro;
        if (def.params.len != call.args.len) return Error.ArityMismatch;
        if (def.body != .block) return Error.MacroBodyExpectedBlock;

        self.expansion_depth += 1;
        defer self.expansion_depth -= 1;
        self.expansion_id += 1;
        var macro_ctx = HygieneContext.init(self.alloc, self.expansion_id);
        defer macro_ctx.deinit();
        for (def.params, call.args) |param, arg| {
            try macro_ctx.bindings.put(self.alloc, param, try self.cloneExpr(arg, ctx));
        }
        const block = try self.cloneBlockWithContext(def.body.block, &macro_ctx);
        if (block.tail_expr) |tail| {
            var out: std.ArrayList(ast.Stmt) = .empty;
            try out.appendSlice(self.alloc, block.stmts);
            try out.append(self.alloc, .{ .expr_stmt = .{ .loc = tail.loc(), .expr = tail } });
            return out.toOwnedSlice(self.alloc);
        }
        return block.stmts;
    }

    fn cloneExpr(self: *Expander, expr: *ast.Expr, ctx: *HygieneContext) Error!*ast.Expr {
        if (self.expanded_nodes >= max_expansion_nodes) return Error.ExpansionLimitExceeded;
        self.expanded_nodes += 1;
        if (expr.* == .macro_call) {
            if (try self.cloneCapture(expr.macro_call, ctx)) |captured| return captured;
            return self.expandMacroCall(expr.macro_call, ctx);
        }
        const cloned: ast.Expr = switch (expr.*) {
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg => expr.*,
            .name => |x| .{ .name = .{ .loc = x.loc, .ident = try ctx.reference(x.ident) } },
            .index => |x| .{ .index = .{
                .loc = x.loc,
                .obj = try self.cloneExpr(x.obj, ctx),
                .key = try self.cloneExpr(x.key, ctx),
            } },
            .field => |x| .{ .field = .{ .loc = x.loc, .obj = try self.cloneExpr(x.obj, ctx), .field = x.field } },
            .call => |x| .{ .call = .{
                .loc = x.loc,
                .func = try self.cloneExpr(x.func, ctx),
                .args = try self.cloneExprSlice(x.args, ctx),
            } },
            .method_call => |x| .{ .method_call = .{
                .loc = x.loc,
                .obj = try self.cloneExpr(x.obj, ctx),
                .method = x.method,
                .args = try self.cloneExprSlice(x.args, ctx),
            } },
            .binop => |x| .{ .binop = .{
                .loc = x.loc,
                .op = x.op,
                .lhs = try self.cloneExpr(x.lhs, ctx),
                .rhs = try self.cloneExpr(x.rhs, ctx),
            } },
            .unop => |x| .{ .unop = .{ .loc = x.loc, .op = x.op, .operand = try self.cloneExpr(x.operand, ctx) } },
            .func_expr => |x| blk: {
                const body = try self.alloc.create(ast.FuncBody);
                body.* = try self.expandFuncBody(x.*, ctx);
                break :blk .{ .func_expr = body };
            },
            .table => |x| .{ .table = .{ .loc = x.loc, .fields = try self.cloneTableFields(x.fields, ctx) } },
            .list_comp => |x| .{ .list_comp = .{
                .loc = x.loc,
                .value = try self.cloneExpr(x.value, ctx),
                .key_name = x.key_name,
                .value_name = x.value_name,
                .iter = try self.cloneExpr(x.iter, ctx),
                .filter = if (x.filter) |filter| try self.cloneExpr(filter, ctx) else null,
            } },
            .try_expr => |x| .{ .try_expr = .{ .loc = x.loc, .operand = try self.cloneExpr(x.operand, ctx) } },
            .unwrap_expr => |x| .{ .unwrap_expr = .{ .loc = x.loc, .operand = try self.cloneExpr(x.operand, ctx) } },
            .match_expr => |x| blk: {
                const match = try self.alloc.create(ast.MatchExpr);
                match.* = try self.expandMatchWithContext(x.*, ctx);
                break :blk .{ .match_expr = match };
            },
            .await_expr => |x| .{ .await_expr = .{ .loc = x.loc, .operand = try self.cloneExpr(x.operand, ctx) } },
            .contains_expr => |x| .{ .contains_expr = .{
                .loc = x.loc,
                .lhs = try self.cloneExpr(x.lhs, ctx),
                .rhs = try self.cloneExpr(x.rhs, ctx),
            } },
            .quote => |x| .{ .quote = .{ .loc = x.loc, .expr = try self.cloneExpr(x.expr, ctx) } },
            .unquote => |x| try self.cloneUnquote(x.expr, ctx),
            .macro_call => unreachable,
        };
        const out = try self.alloc.create(ast.Expr);
        out.* = cloned;
        return out;
    }

    fn cloneCapture(self: *Expander, call: ast.MacroCall, ctx: *HygieneContext) Error!?*ast.Expr {
        _ = ctx;
        if (!std.mem.eql(u8, call.name, "capture")) return null;
        if (call.args.len != 1) return Error.ArityMismatch;
        const arg = call.args[0];
        const ident = switch (arg.*) {
            .name => |x| x.ident,
            .string_lit => |x| x.val,
            else => return Error.CaptureExpectedIdentifier,
        };
        const out = try self.alloc.create(ast.Expr);
        out.* = .{ .name = .{ .loc = call.loc, .ident = ident } };
        return out;
    }

    fn cloneUnquote(self: *Expander, expr: *ast.Expr, ctx: *HygieneContext) Error!ast.Expr {
        if (expr.* == .name) {
            if (ctx.bindings.get(expr.name.ident)) |bound| return bound.*;
        }
        _ = self;
        return Error.UnsupportedUnquote;
    }

    fn expandFuncBody(self: *Expander, func: ast.FuncBody, parent_ctx: ?*HygieneContext) Error!ast.FuncBody {
        var local_ctx = if (parent_ctx) |ctx| try ctx.cloneShallow() else HygieneContext.init(self.alloc, 0);
        defer local_ctx.deinit();
        return .{
            .loc = func.loc,
            .params = try self.cloneParams(func.params, &local_ctx),
            .vararg = func.vararg,
            .vararg_name = if (func.vararg_name) |name| try local_ctx.introduce(name) else null,
            .ret_type = func.ret_type,
            .body = try self.cloneBlockWithContext(func.body, &local_ctx),
            .type_params = func.type_params,
            .is_async = func.is_async,
            .is_typed = func.is_typed,
            .use_iterative_fib = func.use_iterative_fib,
            .use_prime_sieve = func.use_prime_sieve,
            .use_dense_table = func.use_dense_table,
            .dense_table = func.dense_table,
            .dense_table_cap = func.dense_table_cap,
            .use_string_byte_scan = func.use_string_byte_scan,
            .use_string_hash_scan = func.use_string_hash_scan,
            .string_scan_lit = func.string_scan_lit,
            .use_grid_sum_inline = func.use_grid_sum_inline,
            .use_dense_table_max = func.use_dense_table_max,
            .use_dense_table_sum = func.use_dense_table_sum,
            .use_dense_table_identity_sum = func.use_dense_table_identity_sum,
            .use_math_floor_max = func.use_math_floor_max,
            .use_math_pow_sqrt = func.use_math_pow_sqrt,
            .use_string_len_chain = func.use_string_len_chain,
            .use_binary_search_dense = func.use_binary_search_dense,
            .use_filter_count_mod = func.use_filter_count_mod,
            .use_dot_product_identity = func.use_dot_product_identity,
            .use_dot_product_dense = func.use_dot_product_dense,
            .use_clamp_mod_sum = func.use_clamp_mod_sum,
            .use_mod_histogram_sum = func.use_mod_histogram_sum,
            .use_ema_smooth = func.use_ema_smooth,
            .use_ema_period_fold = func.use_ema_period_fold,
            .ema_alpha = func.ema_alpha,
            .ema_beta = func.ema_beta,
            .ema_period = func.ema_period,
            .use_table_lookup_sum = func.use_table_lookup_sum,
            .use_dense_table_mod997_sum = func.use_dense_table_mod997_sum,
            .use_string_token_count = func.use_string_token_count,
            .use_string_delim_byte_sum = func.use_string_delim_byte_sum,
            .use_trig_sum_recur = func.use_trig_sum_recur,
            .use_mandel_iter_native = func.use_mandel_iter_native,
            .use_nbody_native = func.use_nbody_native,
            .use_force_always_inline = func.use_force_always_inline,
            .use_fp_strict_always_inline = func.use_fp_strict_always_inline,
            .use_gcd_inline = func.use_gcd_inline,
            .use_collatz_inline = func.use_collatz_inline,
            .use_xor_fold_inline = func.use_xor_fold_inline,
            .use_bitcount_inline = func.use_bitcount_inline,
            .use_cordic_inline = func.use_cordic_inline,
            .use_ack_inline = func.use_ack_inline,
            .use_life_native = func.use_life_native,
            .use_matmul_native = func.use_matmul_native,
            .use_prefix_sum_inline = func.use_prefix_sum_inline,
            .use_ring_buf_inline = func.use_ring_buf_inline,
            .use_cond_swap_inline = func.use_cond_swap_inline,
            .use_sieve_native = func.use_sieve_native,
            .use_fenwick_native = func.use_fenwick_native,
            .use_interp_inline = func.use_interp_inline,
            .use_run_len_inline = func.use_run_len_inline,
            .use_sparse_dot_inline = func.use_sparse_dot_inline,
            .use_leven_native = func.use_leven_native,
            .closure_id = func.closure_id,
            .upvalues = func.upvalues,
        };
    }

    fn cloneBlockWithContext(self: *Expander, block: ast.Block, ctx: *HygieneContext) Error!ast.Block {
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        for (block.stmts) |stmt| {
            if (try self.expandStmtMacro(stmt, ctx)) |expanded| {
                try stmts.appendSlice(self.alloc, expanded);
            } else {
                try stmts.append(self.alloc, try self.cloneStmtWithContext(stmt, ctx));
            }
        }
        const tail_expr = try self.expandTailExpr(block.tail_expr, &stmts, ctx);
        return .{
            .loc = block.loc,
            .stmts = try stmts.toOwnedSlice(self.alloc),
            .tail_expr = tail_expr,
        };
    }

    fn cloneStmtWithContext(self: *Expander, stmt: ast.Stmt, ctx: *HygieneContext) Error!ast.Stmt {
        return switch (stmt) {
            .local_decl => |x| .{ .local_decl = .{
                .loc = x.loc,
                .names = try self.copyLocalNames(x.names, ctx),
                .inits = try self.cloneExprSlice(x.inits, ctx),
            } },
            .assign => |x| .{ .assign = .{
                .loc = x.loc,
                .targets = try self.cloneExprSlice(x.targets, ctx),
                .values = try self.cloneExprSlice(x.values, ctx),
            } },
            .call_stmt => |x| .{ .call_stmt = .{ .loc = x.loc, .expr = try self.cloneExpr(x.expr, ctx) } },
            .expr_stmt => |x| .{ .expr_stmt = .{ .loc = x.loc, .expr = try self.cloneExpr(x.expr, ctx) } },
            .ret => |x| .{ .ret = .{ .loc = x.loc, .vals = try self.cloneExprSlice(x.vals, ctx) } },
            .const_decl => |x| .{ .const_decl = .{
                .loc = x.loc,
                .ident = try ctx.introduce(x.ident),
                .typ = x.typ,
                .val = try self.cloneExpr(x.val, ctx),
            } },
            .global_decl => |x| .{ .global_decl = .{
                .loc = x.loc,
                .star = x.star,
                .names = try self.copyLocalNames(x.names, ctx),
                .inits = try self.cloneExprSlice(x.inits, ctx),
            } },
            .do_block => |x| .{ .do_block = .{ .loc = x.loc, .body = try self.cloneBlockWithContext(x.body, ctx) } },
            .while_loop => |x| .{ .while_loop = .{
                .loc = x.loc,
                .cond = try self.cloneExpr(x.cond, ctx),
                .body = try self.cloneBlockWithContext(x.body, ctx),
            } },
            .repeat_loop => |x| .{ .repeat_loop = .{
                .loc = x.loc,
                .body = try self.cloneBlockWithContext(x.body, ctx),
                .cond = try self.cloneExpr(x.cond, ctx),
            } },
            .if_stmt => |x| .{ .if_stmt = .{
                .loc = x.loc,
                .cond = try self.cloneExpr(x.cond, ctx),
                .then = try self.cloneBlockWithContext(x.then, ctx),
                .elseifs = try self.cloneElseIfsWithContext(x.elseifs, ctx),
                .else_body = if (x.else_body) |body| try self.cloneBlockWithContext(body, ctx) else null,
            } },
            .num_for => |x| .{ .num_for = .{
                .loc = x.loc,
                .var_name = try ctx.introduce(x.var_name),
                .var_typ = x.var_typ,
                .start = try self.cloneExpr(x.start, ctx),
                .stop = try self.cloneExpr(x.stop, ctx),
                .step = if (x.step) |expr| try self.cloneExpr(expr, ctx) else null,
                .body = try self.cloneBlockWithContext(x.body, ctx),
            } },
            .gen_for => |x| .{ .gen_for = .{
                .loc = x.loc,
                .vars = try self.copyNameSlice(x.vars, ctx),
                .iters = try self.cloneExprSlice(x.iters, ctx),
                .body = try self.cloneBlockWithContext(x.body, ctx),
            } },
            .func_decl => |x| .{ .func_decl = .{
                .loc = x.loc,
                .path = x.path,
                .method = x.method,
                .is_local = x.is_local,
                .func = try self.expandFuncBody(x.func, ctx),
                .attributes = x.attributes,
            } },
            .brk, .cont, .goto_stmt, .label_stmt => stmt,
            .match_stmt => |x| .{ .match_stmt = try self.expandMatchWithContext(x, ctx) },
            .try_stmt => |x| .{ .try_stmt = .{
                .loc = x.loc,
                .body = try self.cloneBlockWithContext(x.body, ctx),
                .catches = try self.cloneCatchesWithContext(x.catches, ctx),
                .defers = try self.cloneDefersWithContext(x.defers, ctx),
            } },
            .defer_stmt => |x| .{ .defer_stmt = .{ .loc = x.loc, .body = try self.cloneBlockWithContext(x.body, ctx) } },
            .enum_def, .concept_def, .alias_def, .macro_def => stmt,
        };
    }

    fn expandExprSlice(self: *Expander, exprs: []*ast.Expr) Error![]*ast.Expr {
        var out: std.ArrayList(*ast.Expr) = .empty;
        for (exprs) |expr| try out.append(self.alloc, try self.expandExpr(expr));
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneExprSlice(self: *Expander, exprs: []*ast.Expr, ctx: *HygieneContext) Error![]*ast.Expr {
        var out: std.ArrayList(*ast.Expr) = .empty;
        for (exprs) |expr| try out.append(self.alloc, try self.cloneExpr(expr, ctx));
        return out.toOwnedSlice(self.alloc);
    }

    fn copyLocalNames(self: *Expander, names: []ast.LocalName, ctx: ?*HygieneContext) Error![]ast.LocalName {
        var out: std.ArrayList(ast.LocalName) = .empty;
        for (names) |name| {
            const ident = if (ctx) |c| try c.introduce(name.ident) else name.ident;
            try out.append(self.alloc, .{
                .ident = ident,
                .typ = name.typ,
                .attrib = name.attrib,
                .attributes = name.attributes,
                .loc = name.loc,
            });
        }
        return out.toOwnedSlice(self.alloc);
    }

    fn copyNameSlice(self: *Expander, names: [][]const u8, ctx: *HygieneContext) Error![][]const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        for (names) |name| try out.append(self.alloc, try ctx.introduce(name));
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneParams(self: *Expander, params: []ast.FuncParam, ctx: *HygieneContext) Error![]ast.FuncParam {
        var out: std.ArrayList(ast.FuncParam) = .empty;
        for (params) |param| {
            try out.append(self.alloc, .{
                .name = try ctx.introduce(param.name),
                .typ = param.typ,
                .default_val = if (param.default_val) |expr| try self.cloneExpr(expr, ctx) else null,
                .loc = param.loc,
            });
        }
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneElseIfsWithContext(self: *Expander, items: []ast.ElseIf, ctx: *HygieneContext) Error![]ast.ElseIf {
        var out: std.ArrayList(ast.ElseIf) = .empty;
        for (items) |item| try out.append(self.alloc, .{
            .cond = try self.cloneExpr(item.cond, ctx),
            .body = try self.cloneBlockWithContext(item.body, ctx),
        });
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneCatchesWithContext(self: *Expander, items: []ast.CatchClause, ctx: *HygieneContext) Error![]ast.CatchClause {
        var out: std.ArrayList(ast.CatchClause) = .empty;
        for (items) |item| {
            var local_ctx = try ctx.cloneShallow();
            defer local_ctx.deinit();
            try out.append(self.alloc, .{
                .loc = item.loc,
                .binding = if (item.binding) |name| try local_ctx.introduce(name) else null,
                .body = try self.cloneBlockWithContext(item.body, &local_ctx),
            });
        }
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneDefersWithContext(self: *Expander, items: []ast.DeferStmt, ctx: *HygieneContext) Error![]ast.DeferStmt {
        var out: std.ArrayList(ast.DeferStmt) = .empty;
        for (items) |item| try out.append(self.alloc, .{
            .loc = item.loc,
            .body = try self.cloneBlockWithContext(item.body, ctx),
        });
        return out.toOwnedSlice(self.alloc);
    }

    fn cloneTableFields(self: *Expander, fields: []ast.TableField, ctx: *HygieneContext) Error![]ast.TableField {
        var out: std.ArrayList(ast.TableField) = .empty;
        for (fields) |field| {
            try out.append(self.alloc, switch (field) {
                .indexed => |x| .{ .indexed = .{ .key = try self.cloneExpr(x.key, ctx), .val = try self.cloneExpr(x.val, ctx) } },
                .named => |x| .{ .named = .{ .key = x.key, .val = try self.cloneExpr(x.val, ctx) } },
                .positional => |x| .{ .positional = try self.cloneExpr(x, ctx) },
            });
        }
        return out.toOwnedSlice(self.alloc);
    }

    fn expandElseIfs(self: *Expander, items: []ast.ElseIf) Error![]ast.ElseIf {
        var out: std.ArrayList(ast.ElseIf) = .empty;
        for (items) |item| try out.append(self.alloc, .{
            .cond = try self.expandExpr(item.cond),
            .body = try self.expandBlock(item.body),
        });
        return out.toOwnedSlice(self.alloc);
    }

    fn expandCatches(self: *Expander, items: []ast.CatchClause) Error![]ast.CatchClause {
        var out: std.ArrayList(ast.CatchClause) = .empty;
        for (items) |item| try out.append(self.alloc, .{
            .loc = item.loc,
            .binding = item.binding,
            .body = try self.expandBlock(item.body),
        });
        return out.toOwnedSlice(self.alloc);
    }

    fn expandDefers(self: *Expander, items: []ast.DeferStmt) Error![]ast.DeferStmt {
        var out: std.ArrayList(ast.DeferStmt) = .empty;
        for (items) |item| try out.append(self.alloc, .{ .loc = item.loc, .body = try self.expandBlock(item.body) });
        return out.toOwnedSlice(self.alloc);
    }

    fn expandMatch(self: *Expander, match: ast.MatchExpr) Error!ast.MatchExpr {
        var ctx = HygieneContext.init(self.alloc, 0);
        defer ctx.deinit();
        return self.expandMatchWithContext(match, &ctx);
    }

    fn expandMatchWithContext(self: *Expander, match: ast.MatchExpr, ctx: *HygieneContext) Error!ast.MatchExpr {
        var arms: std.ArrayList(ast.MatchArm) = .empty;
        for (match.arms) |arm| {
            try arms.append(self.alloc, .{
                .pattern = arm.pattern,
                .guard = if (arm.guard) |expr| try self.cloneExpr(expr, ctx) else null,
                .body = try self.cloneBlockWithContext(arm.body, ctx),
            });
        }
        return .{
            .loc = match.loc,
            .scrutinee = try self.cloneExpr(match.scrutinee, ctx),
            .arms = try arms.toOwnedSlice(self.alloc),
        };
    }
};

const HygieneContext = struct {
    alloc: std.mem.Allocator,
    id: u64,
    bindings: std.StringHashMapUnmanaged(*ast.Expr) = .empty,
    renames: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn init(alloc: std.mem.Allocator, id: u64) HygieneContext {
        return .{ .alloc = alloc, .id = id };
    }

    fn deinit(self: *HygieneContext) void {
        self.bindings.deinit(self.alloc);
        self.renames.deinit(self.alloc);
    }

    fn cloneShallow(self: *HygieneContext) Error!HygieneContext {
        var cloned = HygieneContext.init(self.alloc, self.id);
        var rename_it = self.renames.iterator();
        while (rename_it.next()) |entry| try cloned.renames.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
        var binding_it = self.bindings.iterator();
        while (binding_it.next()) |entry| try cloned.bindings.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
        return cloned;
    }

    fn introduce(self: *HygieneContext, name: []const u8) Error![]const u8 {
        if (self.id == 0) return name;
        if (self.renames.get(name)) |existing| return existing;
        const fresh = try std.fmt.allocPrint(self.alloc, "{s}__macro{}", .{ name, self.id });
        try self.renames.put(self.alloc, name, fresh);
        return fresh;
    }

    fn reference(self: *HygieneContext, name: []const u8) Error![]const u8 {
        if (self.renames.get(name)) |renamed| return renamed;
        return self.introduce(name);
    }
};

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn parseAndExpandForTest(src: []const u8, arena: *std.heap.ArenaAllocator) !ast.Module {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test.duo");
    var parser = Parser.init(&lex, alloc);
    var module = try parser.parse_module();
    var expander = Expander.init(alloc);
    defer expander.deinit();
    try expander.expandModule(&module);
    return module;
}

test "macro expansion substitutes quoted unquote arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test.duo", .line = 1, .col = 1 };
    var arg = ast.Expr{ .int_lit = .{ .loc = loc, .val = 21 } };
    var unquote_name = ast.Expr{ .name = .{ .loc = loc, .ident = "x" } };
    var unquote = ast.Expr{ .unquote = .{ .loc = loc, .expr = &unquote_name } };
    var rhs = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var body_inner = ast.Expr{ .binop = .{ .loc = loc, .op = .mul, .lhs = &unquote, .rhs = &rhs } };
    const params = [_][]const u8{"x"};
    var args = [_]*ast.Expr{&arg};
    var call = ast.Expr{ .macro_call = .{ .loc = loc, .name = "twice", .args = args[0..] } };
    var stmts = [_]ast.Stmt{
        .{ .macro_def = .{ .loc = loc, .name = "twice", .params = &params, .body = .{ .expr = &body_inner } } },
        .{ .expr_stmt = .{ .loc = loc, .expr = &call } },
    };
    var module = ast.Module{ .file = "test.duo", .body = .{ .loc = loc, .stmts = stmts[0..] } };

    var expander = Expander.init(alloc);
    defer expander.deinit();
    try expander.expandModule(&module);

    try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
    const expr = module.body.stmts[0].expr_stmt.expr;
    try std.testing.expect(expr.* == .binop);
    try std.testing.expect(expr.binop.lhs.* == .int_lit);
    try std.testing.expectEqual(@as(i64, 21), expr.binop.lhs.int_lit.val);
}

test "macro expansion reaches nested macro calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try parseAndExpandForTest(
        \\macro one() `1
        \\macro two() `(@one() + @one())
        \\local n = @two()
    , &arena);

    try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
    const init = module.body.stmts[0].local_decl.inits[0];
    try std.testing.expect(init.* == .binop);
    try std.testing.expect(init.binop.lhs.* == .int_lit);
    try std.testing.expect(init.binop.rhs.* == .int_lit);
    try std.testing.expectEqual(@as(i64, 1), init.binop.lhs.int_lit.val);
    try std.testing.expectEqual(@as(i64, 1), init.binop.rhs.int_lit.val);
}

test "macro expansion splices quoted statement blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try parseAndExpandForTest(
        \\macro bind_twice(x) `do
        \\  local tmp = ,x
        \\  local out = tmp + tmp
        \\end
        \\local tmp = 100
        \\@bind_twice(21)
    , &arena);

    try std.testing.expectEqual(@as(usize, 3), module.body.stmts.len);
    const generated_tmp = module.body.stmts[1].local_decl.names[0].ident;
    const generated_out = module.body.stmts[2].local_decl.names[0].ident;
    try std.testing.expect(!std.mem.eql(u8, "tmp", generated_tmp));
    try std.testing.expect(!std.mem.eql(u8, "out", generated_out));
    try std.testing.expect(module.body.stmts[1].local_decl.inits[0].* == .int_lit);
    try std.testing.expectEqual(@as(i64, 21), module.body.stmts[1].local_decl.inits[0].int_lit.val);
    try std.testing.expectEqualStrings(generated_tmp, module.body.stmts[2].local_decl.inits[0].binop.lhs.name.ident);
    try std.testing.expectEqualStrings(generated_tmp, module.body.stmts[2].local_decl.inits[0].binop.rhs.name.ident);
}

test "macro expansion splices type and function declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try parseAndExpandForTest(
        \\macro declare_pair() `do
        \\  alias Pair = { x: i64, y: i64 }
        \\  fun sum_pair(p: Pair): i64
        \\    return p.x + p.y
        \\  end
        \\end
        \\@declare_pair()
        \\local p: Pair = { x = 20, y = 22 }
    , &arena);

    try std.testing.expectEqual(@as(usize, 3), module.body.stmts.len);
    try std.testing.expect(module.body.stmts[0] == .alias_def);
    try std.testing.expect(module.body.stmts[1] == .func_decl);
    try std.testing.expectEqualStrings("Pair", module.body.stmts[0].alias_def.name);
    try std.testing.expectEqualStrings("sum_pair", module.body.stmts[1].func_decl.path[0]);
}

test "macro expansion freshens free identifiers unless captured" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try parseAndExpandForTest(
        \\macro accidental() `tmp
        \\macro intentional() `@capture(tmp)
        \\local tmp = 41
        \\local a = @accidental()
        \\local b = @intentional()
    , &arena);

    try std.testing.expectEqual(@as(usize, 3), module.body.stmts.len);
    const accidental = module.body.stmts[1].local_decl.inits[0];
    const intentional = module.body.stmts[2].local_decl.inits[0];
    try std.testing.expect(accidental.* == .name);
    try std.testing.expect(intentional.* == .name);
    try std.testing.expect(!std.mem.eql(u8, "tmp", accidental.name.ident));
    try std.testing.expectEqualStrings("tmp", intentional.name.ident);
}

test "macro expansion rejects recursive expansion loops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(Error.ExpansionLimitExceeded, parseAndExpandForTest(
        \\macro loop() `@loop()
        \\@loop()
    , &arena));
}

test "macro expansion hygienically renames introduced function parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test.duo", .line = 1, .col = 1 };
    var arg = ast.Expr{ .name = .{ .loc = loc, .ident = "tmp" } };
    var unquote_name = ast.Expr{ .name = .{ .loc = loc, .ident = "x" } };
    var unquote = ast.Expr{ .unquote = .{ .loc = loc, .expr = &unquote_name } };
    var param_ref = ast.Expr{ .name = .{ .loc = loc, .ident = "tmp" } };
    var body_expr = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &param_ref, .rhs = &unquote } };
    var func_params = [_]ast.FuncParam{.{ .name = "tmp", .typ = .inferred, .loc = loc }};
    var func_body = ast.FuncBody{
        .loc = loc,
        .params = func_params[0..],
        .vararg = false,
        .ret_type = .inferred,
        .body = .{ .loc = loc, .stmts = &.{}, .tail_expr = &body_expr },
    };
    var func = ast.Expr{ .func_expr = &func_body };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var quoted_call_args = [_]*ast.Expr{&one};
    var quoted_call = ast.Expr{ .call = .{ .loc = loc, .func = &func, .args = &quoted_call_args } };
    const params = [_][]const u8{"x"};
    var args = [_]*ast.Expr{&arg};
    var call_expr = ast.Expr{ .macro_call = .{ .loc = loc, .name = "wrap", .args = args[0..] } };
    var stmts = [_]ast.Stmt{
        .{ .macro_def = .{ .loc = loc, .name = "wrap", .params = &params, .body = .{ .expr = &quoted_call } } },
        .{ .expr_stmt = .{ .loc = loc, .expr = &call_expr } },
    };
    var module = ast.Module{ .file = "test.duo", .body = .{ .loc = loc, .stmts = stmts[0..] } };

    var expander = Expander.init(alloc);
    defer expander.deinit();
    try expander.expandModule(&module);

    const call = module.body.stmts[0].expr_stmt.expr;
    const expanded_func = call.call.func.func_expr;
    try std.testing.expect(!std.mem.eql(u8, "tmp", expanded_func.params[0].name));
    const lhs = expanded_func.body.tail_expr.?.binop.lhs;
    try std.testing.expectEqualStrings(expanded_func.params[0].name, lhs.name.ident);
    const rhs = expanded_func.body.tail_expr.?.binop.rhs;
    try std.testing.expectEqualStrings("tmp", rhs.name.ident);
}
