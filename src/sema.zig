/// Semantic analysis: type-checks the AST and annotates every expression
/// with a ResolvedType.  Also marks FuncBody.is_typed = true when all
/// parameters and the return type are statically known.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const types = @import("types.zig");
const RT = types.ResolvedType;

pub const SemaError = error{
    TypeMismatch,
    UndeclaredVariable,
    NotCallable,
    InvalidAssignment,
    UnknownBuiltin,
} || Allocator.Error;

/// A symbol in the scope chain.
const Symbol = struct {
    typ: RT,
    is_const: bool,
};

/// Lexical scope: a stack of hash maps.
pub const Scope = struct {
    alloc: Allocator,
    maps: std.ArrayList(std.StringHashMap(Symbol)),

    pub fn init(alloc: Allocator) Scope {
        return .{ .alloc = alloc, .maps = .empty };
    }

    pub fn deinit(self: *Scope) void {
        for (self.maps.items) |*m| m.deinit();
        self.maps.deinit(self.alloc);
    }

    pub fn push(self: *Scope) !void {
        try self.maps.append(self.alloc, std.StringHashMap(Symbol).init(self.alloc));
    }

    pub fn pop(self: *Scope) void {
        var m = self.maps.pop().?;
        m.deinit();
    }

    pub fn define(self: *Scope, name: []const u8, sym: Symbol) !void {
        try self.maps.items[self.maps.items.len - 1].put(name, sym);
    }

    pub fn lookup(self: *Scope, name: []const u8) ?Symbol {
        var i = self.maps.items.len;
        while (i > 0) {
            i -= 1;
            if (self.maps.items[i].get(name)) |sym| return sym;
        }
        return null;
    }
};

/// Per-expression type annotation (stored separately to avoid bloating AST).
/// The Sema pass fills this map; CodeGen reads it.
pub const TypeMap = std.AutoHashMap(*const ast.Expr, RT);

pub const Sema = struct {
    alloc: Allocator,
    scope: Scope,
    type_map: TypeMap,
    errors: u32,
    current_ret: RT,

    pub fn init(alloc: Allocator) Sema {
        return .{
            .alloc = alloc,
            .scope = Scope.init(alloc),
            .type_map = TypeMap.init(alloc),
            .errors = 0,
            .current_ret = .void,
        };
    }

    pub fn deinit(self: *Sema) void {
        self.scope.deinit();
        self.type_map.deinit();
    }

    fn err(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        self.errors += 1;
        std.debug.print("{}: error: " ++ fmt ++ "\n", .{loc} ++ args);
    }

    fn record(self: *Sema, expr: *const ast.Expr, t: RT) !RT {
        try self.type_map.put(expr, t);
        return t;
    }

    // ── Public entry ─────────────────────────────────────────────────────────

    pub fn check_module(self: *Sema, mod: *ast.Module) !void {
        try self.scope.push();
        self.seed_globals();
        try self.check_block(&mod.body);
        self.scope.pop();
    }

    fn seed_globals(self: *Sema) void {
        const names = [_][]const u8{
            "print", "math", "string", "table", "io", "os",
            "ipairs", "pairs", "tostring", "tonumber", "type",
            "error", "assert", "pcall", "require",
            "setmetatable", "getmetatable", "rawget", "rawset",
            "next", "select", "unpack", "load", "loadfile",
            "dofile", "collectgarbage",
        };
        for (names) |n| {
            self.scope.define(n, .{ .typ = .any, .is_const = true }) catch {};
        }
    }

    // ── Block / statements ────────────────────────────────────────────────────

    fn check_block(self: *Sema, blk: *ast.Block) SemaError!void {
        try self.scope.push();
        for (blk.stmts) |*stmt| try self.check_stmt(stmt);
        self.scope.pop();
    }

    fn check_stmt(self: *Sema, stmt: *ast.Stmt) SemaError!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                var init_types: std.ArrayList(RT) = .empty;
                defer init_types.deinit(self.alloc);
                for (ld.inits) |init_expr| {
                    const t = try self.check_expr(init_expr);
                    try init_types.append(self.alloc, t);
                }
                for (ld.names, 0..) |*lname, i| {
                    var t: RT = if (i < init_types.items.len)
                        init_types.items[i]
                    else
                        .nil;
                    // If annotated, use the annotation
                    if (lname.typ != .inferred) {
                        const ann = types.resolve(lname.typ, self.alloc) catch .any;
                        t = ann;
                    }
                    try self.scope.define(lname.ident, .{ .typ = t, .is_const = false });
                }
            },
            .const_decl => |*cd| {
                var t = try self.check_expr(cd.val);
                if (cd.typ != .inferred)
                    t = types.resolve(cd.typ, self.alloc) catch .any;
                try self.scope.define(cd.ident, .{ .typ = t, .is_const = true });
            },
            .assign => |*as| {
                for (as.values) |v| _ = try self.check_expr(v);
                for (as.targets) |tgt| _ = try self.check_expr(tgt);
            },
            .call_stmt => |*cs| _ = try self.check_expr(cs.expr),
            .ret => |*r| {
                for (r.vals) |v| _ = try self.check_expr(v);
            },
            .if_stmt => |*is| {
                _ = try self.check_expr(is.cond);
                try self.check_block(&is.then);
                for (is.elseifs) |*ei| {
                    _ = try self.check_expr(ei.cond);
                    try self.check_block(&ei.body);
                }
                if (is.else_body) |*eb| try self.check_block(eb);
            },
            .while_loop => |*wl| {
                _ = try self.check_expr(wl.cond);
                try self.check_block(&wl.body);
            },
            .repeat_loop => |*rl| {
                try self.check_block(&rl.body);
                _ = try self.check_expr(rl.cond);
            },
            .num_for => |*nf| {
                try self.scope.push();
                var var_t: RT = .i64;
                if (nf.var_typ != .inferred)
                    var_t = types.resolve(nf.var_typ, self.alloc) catch .i64;
                try self.scope.define(nf.var_name, .{ .typ = var_t, .is_const = false });
                _ = try self.check_expr(nf.start);
                _ = try self.check_expr(nf.stop);
                if (nf.step) |s| _ = try self.check_expr(s);
                try self.check_block(&nf.body);
                self.scope.pop();
            },
            .gen_for => |*gf| {
                for (gf.iters) |it| _ = try self.check_expr(it);
                try self.scope.push();
                for (gf.vars) |v| try self.scope.define(v, .{ .typ = .any, .is_const = false });
                try self.check_block(&gf.body);
                self.scope.pop();
            },
            .func_decl => |*fd| {
                var fb = &fd.func;
                var param_types = try self.alloc.alloc(RT, fb.params.len);
                var all_typed = true;
                for (fb.params, 0..) |*p, i| {
                    if (p.typ == .inferred) {
                        param_types[i] = .any;
                        all_typed = false;
                    } else {
                        param_types[i] = types.resolve(p.typ, self.alloc) catch .any;
                    }
                }
                var ret_t: RT = .any;
                if (fb.ret_type != .inferred) {
                    ret_t = types.resolve(fb.ret_type, self.alloc) catch .any;
                } else {
                    all_typed = false;
                }
                fb.is_typed = all_typed;

                const ret_ptr = try self.alloc.create(RT);
                ret_ptr.* = ret_t;
                const fb_t = RT{ .func = .{
                    .params = param_types,
                    .ret = ret_ptr,
                    .is_native = all_typed,
                }};

                if (fd.path.len == 1 and !fd.method) {
                    try self.scope.define(fd.path[0], .{ .typ = fb_t, .is_const = true });
                }

                // Check body
                const prev_ret = self.current_ret;
                self.current_ret = ret_t;
                try self.scope.push();
                for (fb.params, 0..) |*p, i|
                    try self.scope.define(p.name, .{ .typ = param_types[i], .is_const = false });
                try self.check_block(&fb.body);
                self.scope.pop();
                self.current_ret = prev_ret;
            },
            .do_block => |*db| try self.check_block(&db.body),
            .struct_def => |*sd| {
                try self.scope.define(sd.name, .{
                    .typ = RT{ .@"struct" = .{ .name = sd.name } },
                    .is_const = true,
                });
            },
            .brk, .goto_stmt, .label_stmt => {},
        }
    }

    fn check_func_body(self: *Sema, fb: *ast.FuncBody) SemaError!RT {
        // Determine param types and return type
        var param_types = try self.alloc.alloc(RT, fb.params.len);
        var all_typed = true;
        for (fb.params, 0..) |*p, i| {
            if (p.typ == .inferred) {
                param_types[i] = .any;
                all_typed = false;
            } else {
                param_types[i] = types.resolve(p.typ, self.alloc) catch .any;
            }
        }
        var ret_t: RT = .any;
        if (fb.ret_type != .inferred) {
            ret_t = types.resolve(fb.ret_type, self.alloc) catch .any;
        } else {
            all_typed = false;
        }
        fb.is_typed = all_typed;

        // Check body
        const prev_ret = self.current_ret;
        self.current_ret = ret_t;
        try self.scope.push();
        for (fb.params, 0..) |*p, i|
            try self.scope.define(p.name, .{ .typ = param_types[i], .is_const = false });
        try self.check_block(&fb.body);
        self.scope.pop();
        self.current_ret = prev_ret;

        const ret_ptr = try self.alloc.create(RT);
        ret_ptr.* = ret_t;
        return RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = all_typed,
        }};
    }

    // ── Expressions ───────────────────────────────────────────────────────────

    fn check_expr(self: *Sema, expr: *ast.Expr) SemaError!RT {
        const t = try self.check_expr_inner(expr);
        return self.record(expr, t);
    }

    fn check_expr_inner(self: *Sema, expr: *ast.Expr) SemaError!RT {
        return switch (expr.*) {
            .nil       => .nil,
            .true_lit, .false_lit => .bool,
            .int_lit   => .i64,
            .float_lit => .f64,
            .string_lit => .str,
            .vararg     => .any,
            .name => |n| {
                if (self.scope.lookup(n.ident)) |sym| return sym.typ;
                // Unknown identifier → treat as dynamic global
                return .any;
            },
            .field => |f| {
                _ = try self.check_expr(f.obj);
                return .any; // field access is dynamic unless struct-typed
            },
            .index => |idx| {
                _ = try self.check_expr(idx.obj);
                _ = try self.check_expr(idx.key);
                return .any;
            },
            .call => |c| {
                const ft = try self.check_expr(c.func);
                for (c.args) |arg| _ = try self.check_expr(arg);
                return switch (ft) {
                    .func => |f| f.ret.*,
                    else  => .any,
                };
            },
            .method_call => |mc| {
                _ = try self.check_expr(mc.obj);
                for (mc.args) |arg| _ = try self.check_expr(arg);
                return .any;
            },
            .binop => |b| self.check_binop(b.op, b.lhs, b.rhs),
            .unop  => |u| self.check_unop(u.op, u.operand),
            .func_expr => |fb| self.check_func_body(fb),
            .table => |t| {
                for (t.fields) |*fld| {
                    switch (fld.*) {
                        .indexed  => |*idx| { _ = try self.check_expr(idx.key); _ = try self.check_expr(idx.val); },
                        .named    => |*nmd| { _ = try self.check_expr(nmd.val); },
                        .positional => |p|  { _ = try self.check_expr(p); },
                    }
                }
                return .any;
            },
        };
    }

    fn check_binop(self: *Sema, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr) SemaError!RT {
        const lt = try self.check_expr(lhs);
        const rt = try self.check_expr(rhs);
        return switch (op) {
            .div, .pow => {
                if (lt.is_numeric() and rt.is_numeric()) return .f64;
                return .any;
            },
            .add, .sub, .mul, .idiv, .mod => {
                if (lt.is_numeric() and rt.is_numeric()) {
                    // Promote: if either is float, result is float
                    if (lt.is_float() or rt.is_float()) return .f64;
                    return lt; // both integers: use left type
                }
                return .any;
            },
            .band, .bor, .bxor, .lshift, .rshift => {
                if (lt.is_integer() and rt.is_integer()) return lt;
                return .any;
            },
            .concat => .str,
            .eq, .neq, .lt, .gt, .leq, .geq => .bool,
            .@"and" => rt, // 'and' returns rhs type
            .@"or"  => lt, // 'or'  returns lhs type
        };
    }

    fn check_unop(self: *Sema, op: ast.UnOp, operand: *ast.Expr) SemaError!RT {
        const t = try self.check_expr(operand);
        return switch (op) {
            .neg  => if (t.is_numeric()) t else .any,
            .bnot => if (t.is_integer()) t else .any,
            .not  => .bool,
            .len  => if (t == .any) .any else .i64,
        };
    }
};
