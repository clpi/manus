//! Monomorphizer (Requirement 4): turns generic functions into concrete
//! specializations, one per unique tuple of type arguments.
//!
//! ## Design
//!
//! A generic function in Duo is a top-level `func_decl` whose `FuncBody` carries
//! a non-empty `type_params` list (`fun id<T>(x: T) -> T ...`). At each call site
//! the concrete type arguments are *inferred* from the static types of the
//! argument expressions, or explicitly requested with `@specialize(name, T, U)`.
//! Inferred call-site types come from the semantic pass' `type_map`
//! (`*Expr -> ResolvedType`).
//!
//! The monomorphizer:
//!   1. collects every generic function declaration in the module;
//!   2. walks the AST collecting instantiation sites (calls to those functions),
//!      inferring the type arguments by unifying each parameter's type
//!      annotation against the argument's static type;
//!   3. for each unique `(generic, type_args)` pair, records a `Specialization`
//!      carrying a substitution map (`type_param_name -> ResolvedType`) and a
//!      deterministically mangled C name;
//!   4. iterates to a fixed point: scanning a specialization's body (with its
//!      substitution environment active) may surface further instantiation
//!      sites, which are enqueued and processed in turn.
//!
//! A specialization is represented as the original (template) body paired with a
//! complete `type_param -> concrete` substitution rather than a deep AST clone.
//! Type-parameter *replacement* is therefore realized through `resolveType`,
//! which codegen calls to obtain the concrete type for any annotation inside a
//! specialized body. This keeps the pass free of a large, error-prone AST clone
//! while preserving the essential monomorphization invariant: every
//! specialization has a total mapping from type parameters to concrete types,
//! and distinct type-argument tuples produce distinct specializations.

const std = @import("std");
const debug_trace = @import("debug_trace.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");
const sema_mod = @import("sema.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

const Allocator = std.mem.Allocator;
const RT = types.ResolvedType;
const TypeMap = sema_mod.TypeMap;

/// Specialization key: identity of the generic template + a hash of the
/// concrete type arguments. Two integers, so it works directly with
/// `std.AutoHashMap`.
pub const SpecKey = struct {
    generic_id: usize,
    type_args_hash: u64,
};

/// A concrete instantiation of a generic function.
pub const Specialization = struct {
    /// Allocator used for recursively materialized resolved types.
    alloc: Allocator,
    /// Mangled C name, e.g. `duo_id_i64`.
    mangled_name: []const u8,
    /// Source name of the generic function (e.g. `id`).
    generic_name: []const u8,
    /// The generic function body this specialization derives from.
    template: *const ast.FuncBody,
    /// Concrete type arguments, in declaration order of `type_params`.
    type_args: []const RT,
    /// type-parameter name -> concrete type.
    substitutions: std.StringHashMapUnmanaged(RT),
    /// Function parameter/local name -> concrete type while scanning/emitting
    /// this specialization.
    value_types: std.StringHashMapUnmanaged(RT),
    key: SpecKey,

    /// Resolve a type annotation from within this specialization's body to its
    /// concrete type, substituting any type parameters. Codegen uses this to
    /// emit fully-typed C for a specialized body.
    pub fn resolveType(self: *const Specialization, te: ast.TypeExpr) RT {
        return self.resolveTypeRecursive(te);
    }

    fn resolveTypeRecursive(self: *const Specialization, te: ast.TypeExpr) RT {
        switch (te) {
            .named => |n| {
                if (self.substitutions.get(n)) |t| return t;
            },
            .pointer => |inner| {
                const p = self.alloc.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(inner.*);
                return .{ .pointer = p };
            },
            .optional => |inner| {
                const p = self.alloc.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(inner.*);
                return .{ .option = p };
            },
            .array => |a| {
                const p = self.alloc.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(a.elem.*);
                return .{ .array = .{ .elem = p, .size = a.size } };
            },
            .func => |f| {
                const params = self.alloc.alloc(RT, f.params.len) catch unreachable;
                var is_native = true;
                for (f.params, 0..) |param, i| {
                    params[i] = self.resolveTypeRecursive(param);
                    is_native = is_native and params[i].is_native();
                }
                const ret = self.alloc.create(RT) catch unreachable;
                ret.* = self.resolveTypeRecursive(f.ret.*);
                is_native = is_native and ret.is_native();
                return .{ .func = .{ .params = params, .ret = ret, .is_native = is_native } };
            },
            .generic => |g| return self.resolveGeneric(g),
            .record => |record| {
                const fields = self.alloc.alloc(types.FieldType, record.fields.len) catch unreachable;
                for (record.fields, 0..) |field, i| {
                    fields[i] = .{ .name = field.name, .typ = self.resolveTypeRecursive(field.typ) };
                }
                return .{ .table_type = .{ .fields = fields } };
            },
            else => {},
        }
        return types.resolve(te, null, self.alloc) catch .any;
    }

    fn resolveGeneric(self: *const Specialization, g: ast.TypeExpr.GenericType) RT {
        const base = self.alloc.create(RT) catch unreachable;
        base.* = self.resolveTypeRecursive(g.base.*);
        const args = self.alloc.alloc(RT, g.params.len) catch unreachable;
        for (g.params, 0..) |param, i| args[i] = self.resolveTypeRecursive(param);

        if (base.* == .@"struct" and
            (std.mem.eql(u8, base.@"struct".name, "List") or
                std.mem.eql(u8, base.@"struct".name, "list")) and args.len == 1)
        {
            const elem = self.alloc.create(RT) catch unreachable;
            elem.* = args[0];
            return .{ .array = .{ .elem = elem, .size = null } };
        }
        if (base.* == .@"struct" and std.mem.eql(u8, base.@"struct".name, "Option") and args.len == 1) {
            const elem = self.alloc.create(RT) catch unreachable;
            elem.* = args[0];
            return .{ .option = elem };
        }
        if (base.* == .@"struct" and std.mem.eql(u8, base.@"struct".name, "Result") and args.len == 2) {
            const ok = self.alloc.create(RT) catch unreachable;
            ok.* = args[0];
            const err = self.alloc.create(RT) catch unreachable;
            err.* = args[1];
            return .{ .result = .{ .ok = ok, .err = err } };
        }

        var key = std.hash.Wyhash.hash(0, "generic");
        if (base.* == .enum_type) key = std.hash.Wyhash.hash(0, base.enum_type.name);
        if (base.* == .@"struct") key = std.hash.Wyhash.hash(0, base.@"struct".name);
        for (args) |arg| {
            var buf: [128]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{}", .{arg}) catch "";
            key ^= std.hash.Wyhash.hash(key, rendered);
        }
        return .{ .instantiated = .{ .base = base, .args = args, .specialization_key = key } };
    }
};

const PendingReq = struct {
    template: *const ast.FuncBody,
    generic_name: []const u8,
    type_args: []const RT,
    key: SpecKey,
};

pub const Monomorphizer = struct {
    alloc: Allocator,
    type_map: *const TypeMap,

    /// name -> generic template (only functions with type_params).
    generics: std.StringHashMapUnmanaged(*const ast.FuncBody) = .empty,
    /// Specialization cache, keyed by `SpecKey`.
    specializations: std.AutoHashMapUnmanaged(SpecKey, *Specialization) = .empty,
    /// Specializations in discovery order, for deterministic emission.
    order: std.ArrayListUnmanaged(*Specialization) = .empty,
    /// Pending work queue for fixed-point expansion.
    pending: std.ArrayListUnmanaged(PendingReq) = .empty,
    /// Keys already requested (queued or done) to avoid duplicate work.
    requested: std.AutoHashMapUnmanaged(SpecKey, void) = .empty,

    const Self = @This();
    const Error = std.mem.Allocator.Error;

    pub fn init(alloc: Allocator, type_map: *const TypeMap) Self {
        return .{ .alloc = alloc, .type_map = type_map };
    }

    pub fn deinit(self: *Self) void {
        var it = self.specializations.valueIterator();
        while (it.next()) |spec_ptr| {
            spec_ptr.*.substitutions.deinit(self.alloc);
            spec_ptr.*.value_types.deinit(self.alloc);
            self.alloc.destroy(spec_ptr.*);
        }
        self.generics.deinit(self.alloc);
        self.specializations.deinit(self.alloc);
        self.order.deinit(self.alloc);
        self.pending.deinit(self.alloc);
        self.requested.deinit(self.alloc);
    }

    /// Run the full pass over a module.
    pub fn run(self: *Self, module: *const ast.Module) !void {
        try self.collectGenerics(&module.body);
        // Top-level instantiation sites (no active substitution environment).
        try self.collectSitesBlock(&module.body, null);
        // Fixed-point expansion.
        while (self.pending.items.len > 0) {
            const req = self.pending.orderedRemove(0);
            try self.specialize(req);
        }
    }

    /// Number of distinct specializations produced.
    pub fn count(self: *const Self) usize {
        return self.order.items.len;
    }

    /// Non-allocating check: does `name` have at least one specialization?
    pub fn hasSpecializations(self: *const Self, name: []const u8) bool {
        for (self.order.items) |spec| {
            if (std.mem.eql(u8, spec.generic_name, name)) return true;
        }
        return false;
    }

    /// All specializations of `name`, in discovery order (caller frees).
    pub fn getSpecializations(self: *Self, name: []const u8) ![]*Specialization {
        var out: std.ArrayListUnmanaged(*Specialization) = .empty;
        for (self.order.items) |spec| {
            if (std.mem.eql(u8, spec.generic_name, name))
                try out.append(self.alloc, spec);
        }
        return out.toOwnedSlice(self.alloc);
    }

    /// Return the specialization selected for a concrete call site, if the
    /// callee is a known generic and the pass has already produced the matching
    /// specialization.
    pub fn findSpecializationForCall(self: *Self, name: []const u8, args: []const *ast.Expr, env: Env) ?*Specialization {
        const template = self.generics.get(name) orelse return null;
        const type_args = self.inferTypeArgs(template, args, env) catch return null;
        defer self.alloc.free(type_args);
        const key = SpecKey{
            .generic_id = @intFromPtr(template),
            .type_args_hash = hashTypeArgs(type_args),
        };
        return self.specializations.get(key);
    }

    // ── Generic collection ──────────────────────────────────────────────────

    fn collectGenerics(self: *Self, block: *const ast.Block) !void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    if (fd.path.len == 1 and !fd.method) {
                        if (fd.func.type_params) |tp| {
                            if (tp.len > 0)
                                try self.generics.put(self.alloc, fd.path[0], &fd.func);
                        }
                    }
                },
                else => {},
            }
        }
    }

    // ── Instantiation-site collection ───────────────────────────────────────

    pub const Env = ?*const Specialization;

    fn collectSitesBlock(self: *Self, block: *const ast.Block, env: Env) Error!void {
        for (block.stmts) |*stmt| try self.collectSitesStmt(stmt, env);
        if (block.tail_expr) |e| try self.collectSitesExpr(e, env);
    }

    fn collectSitesStmt(self: *Self, stmt: *const ast.Stmt, env: Env) Error!void {
        switch (stmt.*) {
            .local_decl => |d| for (d.inits) |e| try self.collectSitesExpr(e, env),
            .const_decl => |d| try self.collectSitesExpr(d.val, env),
            .global_decl => |d| for (d.inits) |e| try self.collectSitesExpr(e, env),
            .assign => |a| {
                for (a.targets) |e| try self.collectSitesExpr(e, env);
                for (a.values) |e| try self.collectSitesExpr(e, env);
            },
            .call_stmt => |c| try self.collectSitesExpr(c.expr, env),
            .expr_stmt => |e| try self.collectSitesExpr(e.expr, env),
            .do_block => |d| try self.collectSitesBlock(&d.body, env),
            .while_loop => |w| {
                try self.collectSitesExpr(w.cond, env);
                try self.collectSitesBlock(&w.body, env);
            },
            .repeat_loop => |r| {
                try self.collectSitesBlock(&r.body, env);
                try self.collectSitesExpr(r.cond, env);
            },
            .if_stmt => |i| {
                try self.collectSitesExpr(i.cond, env);
                try self.collectSitesBlock(&i.then, env);
                for (i.elseifs) |ei| {
                    try self.collectSitesExpr(ei.cond, env);
                    try self.collectSitesBlock(&ei.body, env);
                }
                if (i.else_body) |eb| try self.collectSitesBlock(&eb, env);
            },
            .num_for => |f| {
                try self.collectSitesExpr(f.start, env);
                try self.collectSitesExpr(f.stop, env);
                if (f.step) |s| try self.collectSitesExpr(s, env);
                try self.collectSitesBlock(&f.body, env);
            },
            .gen_for => |f| {
                for (f.iters) |e| try self.collectSitesExpr(e, env);
                try self.collectSitesBlock(&f.body, env);
            },
            .func_decl => |fd| {
                // A generic template has no concrete value/type environment.
                // Its body is scanned only from `specialize`, after the request
                // is cached and parameter bindings are concrete.
                if (fd.func.type_params == null or fd.func.type_params.?.len == 0)
                    try self.collectSitesBlock(&fd.func.body, env);
            },
            .ret => |r| for (r.vals) |e| try self.collectSitesExpr(e, env),
            .match_stmt => |m| try self.collectSitesMatch(&m, env),
            .try_stmt => |t| {
                try self.collectSitesBlock(&t.body, env);
                for (t.catches) |c| try self.collectSitesBlock(&c.body, env);
                for (t.defers) |d| try self.collectSitesBlock(&d.body, env);
            },
            .defer_stmt => |d| try self.collectSitesBlock(&d.body, env),
            .directive => |d| {
                if (std.mem.eql(u8, d.attr.name, "specialize"))
                    try self.recordExplicitSpecialization(d.attr.args orelse "");
            },
            .brk, .cont, .goto_stmt, .label_stmt, .enum_def, .concept_def, .alias_def, .macro_def, .cinclude => {},
        }
    }

    fn collectSitesMatch(self: *Self, m: *const ast.MatchExpr, env: Env) Error!void {
        try self.collectSitesExpr(m.scrutinee, env);
        for (m.arms) |arm| {
            if (arm.guard) |g| try self.collectSitesExpr(g, env);
            try self.collectSitesBlock(&arm.body, env);
        }
    }

    fn collectSitesExpr(self: *Self, expr: *const ast.Expr, env: Env) Error!void {
        switch (expr.*) {
            .call => |c| {
                try self.collectSitesExpr(c.func, env);
                for (c.args) |a| try self.collectSitesExpr(a, env);
                if (c.func.* == .name) {
                    if (self.generics.get(c.func.name.ident)) |template|
                        try self.recordSite(c.func.name.ident, template, c.args, env);
                }
            },
            .method_call => |m| {
                try self.collectSitesExpr(m.obj, env);
                for (m.args) |a| try self.collectSitesExpr(a, env);
            },
            .index => |i| {
                try self.collectSitesExpr(i.obj, env);
                try self.collectSitesExpr(i.key, env);
            },
            .field => |f| try self.collectSitesExpr(f.obj, env),
            .binop => |b| {
                try self.collectSitesExpr(b.lhs, env);
                try self.collectSitesExpr(b.rhs, env);
            },
            .unop => |u| try self.collectSitesExpr(u.operand, env),
            .func_expr => |fb| try self.collectSitesBlock(&fb.body, env),
            .table => |t| for (t.fields) |fld| switch (fld) {
                .indexed => |kv| {
                    try self.collectSitesExpr(kv.key, env);
                    try self.collectSitesExpr(kv.val, env);
                },
                .named => |nv| try self.collectSitesExpr(nv.val, env),
                .positional => |p| try self.collectSitesExpr(p, env),
                .spread => |sp| try self.collectSitesExpr(sp, env),
                .semantic => |sm| try self.collectSitesExpr(sm.val, env),
            },
            .list_comp => |lc| {
                try self.collectSitesExpr(lc.iter, env);
                if (lc.filter) |filter| try self.collectSitesExpr(filter, env);
                try self.collectSitesExpr(lc.value, env);
            },
            .try_expr => |t| try self.collectSitesExpr(t.operand, env),
            .unwrap_expr => |u| try self.collectSitesExpr(u.operand, env),
            .if_expr => |ie| {
                try self.collectSitesExpr(ie.cond, env);
                try self.collectSitesExpr(ie.then_expr, env);
                try self.collectSitesExpr(ie.else_expr, env);
            },
            .match_expr => |m| try self.collectSitesMatch(m, env),
            .await_expr => |a| try self.collectSitesExpr(a.operand, env),
            .contains_expr => |c| {
                try self.collectSitesExpr(c.lhs, env);
                try self.collectSitesExpr(c.rhs, env);
            },
            .range => |r| {
                try self.collectSitesExpr(r.start, env);
                try self.collectSitesExpr(r.end, env);
                if (r.step) |s| try self.collectSitesExpr(s, env);
            },
            .quote, .unquote, .macro_call => unreachable,
            .semantic, .semantic_scope => {}, // semantic identity / world: no child exprs
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg, .name => {},
            .sequence => |seq| {
                for (seq.exprs) |e| try self.collectSitesExpr(e, env);
            },
        }
    }

    // ── Type-argument inference ─────────────────────────────────────────────

    /// Infer the concrete type arguments for a call to `template`, in the
    /// declaration order of its `type_params`. Unbound parameters fall back to
    /// `.any`. The result slice is owned by the monomorphizer's allocator.
    fn inferTypeArgs(self: *Self, template: *const ast.FuncBody, args: []const *ast.Expr, env: Env) ![]const RT {
        const type_params = template.type_params orelse &.{};
        var bindings: std.StringHashMapUnmanaged(RT) = .empty;
        defer bindings.deinit(self.alloc);

        const n = @min(template.params.len, args.len);
        for (template.params[0..n], args[0..n]) |p, arg| {
            const arg_rt = self.argType(arg, env, p.typ);
            try unify(self.alloc, p.typ, arg_rt, type_params, &bindings);
        }

        var out = try self.alloc.alloc(RT, type_params.len);
        for (type_params, 0..) |tp, i| {
            const name = typeParamName(tp);
            out[i] = bindings.get(name) orelse .any;
        }
        return out;
    }

    /// Static type of an argument expression, with the active substitution
    /// environment applied to any residual type-parameter type.
    fn argType(self: *Self, arg: *const ast.Expr, env: Env, param_type: ?ast.TypeExpr) RT {
        var base = self.type_map.get(arg) orelse .any;
        if (base == .any and arg.* == .name) {
            base = .{ .@"struct" = .{ .name = arg.name.ident } };
        }
        if (env) |e| {
            if (arg.* == .name) {
                if (e.value_types.get(arg.name.ident)) |t| return t;
            }
            // A nested generic call inside a specialized body: an argument that
            // is itself a type parameter shows up as `.@"struct"{name=T}` (the
            // sema fallback for an unknown named type) or `.generic_param`.
            switch (base) {
                .@"struct" => |s| if (e.substitutions.get(s.name)) |t| return t,
                .generic_param => |g| if (e.substitutions.get(g.name)) |t| return t,
                else => {},
            }
            // Also check if the param_type itself is a type parameter (e.g.
            // `v: T` where T is in the env). Sema may have typed v as .any
            // (via the single-letter heuristic), but we can recover via the
            // parameter's original type annotation.
            if (param_type) |pt| {
                if (pt == .named) {
                    if (e.substitutions.get(pt.named)) |t| return t;
                }
            }
        }
        return base;
    }

    /// Unify a parameter's type annotation against a concrete argument type,
    /// recording any type-parameter bindings. Handles the structural cases that
    /// can carry a type parameter (`T`, `*T`, `?T`, `[]T`).
    fn unify(
        alloc: Allocator,
        param: ast.TypeExpr,
        arg: RT,
        type_params: []const ast.TypeExpr,
        bindings: *std.StringHashMapUnmanaged(RT),
    ) !void {
        switch (param) {
            .named => |n| {
                if (isTypeParam(n, type_params)) {
                    // First binding wins; later occurrences must be consistent
                    // but we don't error here (sema owns diagnostics).
                    if (!bindings.contains(n)) try bindings.put(alloc, n, arg);
                }
            },
            .pointer => |inner| {
                if (arg == .pointer) try unify(alloc, inner.*, arg.pointer.*, type_params, bindings);
            },
            .optional => |inner| {
                if (arg == .option) try unify(alloc, inner.*, arg.option.*, type_params, bindings);
            },
            .array => |a| {
                if (arg == .array) try unify(alloc, a.elem.*, arg.array.elem.*, type_params, bindings);
            },
            .func => |f| {
                if (arg != .func or f.params.len != arg.func.params.len) return;
                for (f.params, arg.func.params) |param_type, concrete|
                    try unify(alloc, param_type, concrete, type_params, bindings);
                try unify(alloc, f.ret.*, arg.func.ret.*, type_params, bindings);
            },
            .record => |record| {
                if (arg != .table_type) return;
                for (record.fields) |param_field| {
                    for (arg.table_type.fields) |concrete_field| {
                        if (std.mem.eql(u8, param_field.name, concrete_field.name)) {
                            try unify(alloc, param_field.typ, concrete_field.typ, type_params, bindings);
                            break;
                        }
                    }
                }
            },
            .generic => |g| {
                const base_name = if (g.base.* == .named) g.base.named else "";
                if ((std.mem.eql(u8, base_name, "List") or std.mem.eql(u8, base_name, "list")) and
                    g.params.len == 1 and arg == .array)
                {
                    try unify(alloc, g.params[0], arg.array.elem.*, type_params, bindings);
                    return;
                }
                if (std.mem.eql(u8, base_name, "Option") and g.params.len == 1 and arg == .option) {
                    try unify(alloc, g.params[0], arg.option.*, type_params, bindings);
                    return;
                }
                if (std.mem.eql(u8, base_name, "Result") and g.params.len == 2 and arg == .result) {
                    try unify(alloc, g.params[0], arg.result.ok.*, type_params, bindings);
                    try unify(alloc, g.params[1], arg.result.err.*, type_params, bindings);
                    return;
                }
                if (arg != .instantiated or g.params.len != arg.instantiated.args.len) return;
                for (g.params, arg.instantiated.args) |param_type, concrete|
                    try unify(alloc, param_type, concrete, type_params, bindings);
            },
            else => {},
        }
    }

    // ── Specialization ──────────────────────────────────────────────────────

    fn recordSite(
        self: *Self,
        name: []const u8,
        template: *const ast.FuncBody,
        args: []const *ast.Expr,
        env: Env,
    ) !void {
        const type_args = try self.inferTypeArgs(template, args, env);
        const key = SpecKey{
            .generic_id = @intFromPtr(template),
            .type_args_hash = hashTypeArgs(type_args),
        };
        if (self.requested.contains(key)) {
            self.alloc.free(type_args);
            return;
        }
        try self.requested.put(self.alloc, key, {});
        try self.pending.append(self.alloc, .{
            .template = template,
            .generic_name = name,
            .type_args = type_args,
            .key = key,
        });
    }

    fn recordExplicitSpecialization(self: *Self, raw_args: []const u8) !void {
        const parts = try splitTopLevelArgs(self.alloc, raw_args);
        defer self.alloc.free(parts);
        if (parts.len == 0) return;
        const name = parts[0];
        if (name.len == 0) return;
        const template = self.generics.get(name) orelse return;
        const type_params = template.type_params orelse &.{};
        if (type_params.len == 0) return;

        var type_args: std.ArrayListUnmanaged(RT) = .empty;
        errdefer type_args.deinit(self.alloc);
        for (parts[1..]) |part| {
            if (part.len == 0) continue;
            try type_args.append(self.alloc, try self.directiveType(part));
        }
        if (type_args.items.len != type_params.len) {
            type_args.deinit(self.alloc);
            return;
        }

        const owned = try type_args.toOwnedSlice(self.alloc);
        const key = SpecKey{
            .generic_id = @intFromPtr(template),
            .type_args_hash = hashTypeArgs(owned),
        };
        if (self.requested.contains(key)) {
            self.alloc.free(owned);
            return;
        }
        try self.requested.put(self.alloc, key, {});
        try self.pending.append(self.alloc, .{
            .template = template,
            .generic_name = name,
            .type_args = owned,
            .key = key,
        });
    }

    fn directiveType(self: *Self, name: []const u8) !RT {
        var lex = Lexer.init(name, "specialize-type");
        var parser = Parser.init(&lex, self.alloc);
        const typ = parser.parse_type() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .any,
        };
        return types.resolve(typ, null, self.alloc) catch .any;
    }

    fn specialize(self: *Self, req: PendingReq) !void {
        if (self.specializations.contains(req.key)) return;

        var subs: std.StringHashMapUnmanaged(RT) = .empty;
        const params = req.template.type_params orelse &.{};
        for (params, 0..) |tp, i| {
            if (i < req.type_args.len)
                try subs.put(self.alloc, typeParamName(tp), req.type_args[i]);
        }

        const spec = try self.alloc.create(Specialization);
        spec.* = .{
            .alloc = self.alloc,
            .mangled_name = try self.mangleName(req.generic_name, req.type_args),
            .generic_name = req.generic_name,
            .template = req.template,
            .type_args = req.type_args,
            .substitutions = subs,
            .value_types = .empty,
            .key = req.key,
        };
        for (req.template.params) |param| {
            try spec.value_types.put(self.alloc, param.name, spec.resolveType(param.typ));
        }
        try self.collectSpecializedValueTypes(spec, &req.template.body);
        try self.specializations.put(self.alloc, req.key, spec);
        try self.order.append(self.alloc, spec);
        debug_trace.event(.mono, .generic, "specialize {s} → {s}", .{ req.generic_name, spec.mangled_name });

        // Fixed-point: scan the specialized body with this substitution active
        // to surface nested generic instantiations.
        try self.collectSitesBlock(&req.template.body, spec);
    }

    fn collectSpecializedValueTypes(self: *Self, spec: *Specialization, block: *const ast.Block) !void {
        for (block.stmts) |*stmt| switch (stmt.*) {
            .local_decl => |decl| {
                for (decl.names, 0..) |local, i| {
                    const concrete = if (local.typ != .inferred)
                        spec.resolveType(local.typ)
                    else if (i < decl.inits.len)
                        self.argType(decl.inits[i], spec, null)
                    else
                        RT.any;
                    try spec.value_types.put(self.alloc, local.ident, concrete);
                }
            },
            .do_block => |nested| try self.collectSpecializedValueTypes(spec, &nested.body),
            .while_loop => |loop| try self.collectSpecializedValueTypes(spec, &loop.body),
            .repeat_loop => |loop| try self.collectSpecializedValueTypes(spec, &loop.body),
            .if_stmt => |branch| {
                try self.collectSpecializedValueTypes(spec, &branch.then);
                for (branch.elseifs) |elseif| try self.collectSpecializedValueTypes(spec, &elseif.body);
                if (branch.else_body) |else_body| try self.collectSpecializedValueTypes(spec, &else_body);
            },
            .num_for => |loop| {
                try spec.value_types.put(self.alloc, loop.var_name, spec.resolveType(loop.var_typ));
                try self.collectSpecializedValueTypes(spec, &loop.body);
            },
            .gen_for => |loop| {
                for (loop.vars) |name| try spec.value_types.put(self.alloc, name, .any);
                try self.collectSpecializedValueTypes(spec, &loop.body);
            },
            .match_stmt => |match| for (match.arms) |arm|
                try self.collectSpecializedValueTypes(spec, &arm.body),
            .try_stmt => |try_stmt| {
                try self.collectSpecializedValueTypes(spec, &try_stmt.body);
                for (try_stmt.catches) |catch_clause| try self.collectSpecializedValueTypes(spec, &catch_clause.body);
                for (try_stmt.defers) |defer_stmt| try self.collectSpecializedValueTypes(spec, &defer_stmt.body);
            },
            .defer_stmt => |defer_stmt| try self.collectSpecializedValueTypes(spec, &defer_stmt.body),
            // Nested functions have independent type parameters and scopes.
            .func_decl => {},
            else => {},
        };
    }

    // ── Name mangling ───────────────────────────────────────────────────────

    /// Deterministic mangled name: `duo_<name>[_<typearg>]*`. Determinism means
    /// identical type-argument tuples always yield the same C symbol, which is
    /// exactly what lets distinct specializations coexist and identical ones
    /// share a definition.
    fn mangleName(self: *Self, name: []const u8, type_args: []const RT) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.alloc);
        try buf.appendSlice(self.alloc, "duo_");
        try buf.appendSlice(self.alloc, name);
        for (type_args) |t| {
            try buf.append(self.alloc, '_');
            try appendTypeName(self.alloc, &buf, t);
        }
        return buf.toOwnedSlice(self.alloc);
    }
};

// ── Free helpers ────────────────────────────────────────────────────────────

fn splitTopLevelArgs(alloc: Allocator, raw: []const u8) ![]const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer args.deinit(alloc);

    var start: usize = 0;
    var depth: usize = 0;
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (quote) |q| {
            if (c == '\\') {
                i += 1;
            } else if (c == q) {
                quote = null;
            }
            continue;
        }
        switch (c) {
            '"', '\'' => quote = c,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            ',' => if (depth == 0) {
                try args.append(alloc, std.mem.trim(u8, raw[start..i], " \t\r\n"));
                start = i + 1;
            },
            else => {},
        }
    }
    try args.append(alloc, std.mem.trim(u8, raw[start..], " \t\r\n"));
    return args.toOwnedSlice(alloc);
}

fn typeParamName(tp: ast.TypeExpr) []const u8 {
    return switch (tp) {
        .named => |n| n,
        .constrained => |cp| cp.name,
        else => "_",
    };
}

fn isTypeParam(name: []const u8, type_params: []const ast.TypeExpr) bool {
    for (type_params) |tp| {
        if (std.mem.eql(u8, typeParamName(tp), name)) return true;
    }
    return false;
}

fn hashTypeArgs(type_args: []const RT) u64 {
    var h = std.hash.Wyhash.init(0);
    for (type_args) |t| {
        var b: [96]u8 = undefined;
        const s = std.fmt.bufPrint(&b, "{}", .{t}) catch "?";
        h.update(s);
        h.update(&[_]u8{0});
    }
    return h.final();
}

fn appendTypeName(alloc: Allocator, buf: *std.ArrayListUnmanaged(u8), t: RT) !void {
    switch (t) {
        .i8 => try buf.appendSlice(alloc, "i8"),
        .i16 => try buf.appendSlice(alloc, "i16"),
        .i32 => try buf.appendSlice(alloc, "i32"),
        .i64 => try buf.appendSlice(alloc, "i64"),
        .u8 => try buf.appendSlice(alloc, "u8"),
        .u16 => try buf.appendSlice(alloc, "u16"),
        .u32 => try buf.appendSlice(alloc, "u32"),
        .u64 => try buf.appendSlice(alloc, "u64"),
        .f32 => try buf.appendSlice(alloc, "f32"),
        .f64 => try buf.appendSlice(alloc, "f64"),
        .bool => try buf.appendSlice(alloc, "bool"),
        .str => try buf.appendSlice(alloc, "str"),
        .any => try buf.appendSlice(alloc, "any"),
        .@"struct" => |s| try appendSanitized(alloc, buf, s.name),
        .enum_type => |e| try appendSanitized(alloc, buf, e.name),
        else => {
            // Fall back to the type's debug rendering, sanitized to a valid
            // C identifier fragment.
            var b: [96]u8 = undefined;
            const s = std.fmt.bufPrint(&b, "{}", .{t}) catch "T";
            try appendSanitized(alloc, buf, s);
        },
    }
}

fn appendSanitized(alloc: Allocator, buf: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    for (s) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
        try buf.append(alloc, if (ok) c else '_');
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────

const testing = std.testing;
const Sema = sema_mod.Sema;

const Harness = struct {
    arena: std.heap.ArenaAllocator,
    mod: ast.Module,
    sema: Sema,

    fn run(src: []const u8) !Harness {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        const alloc = arena.allocator();
        var lex = Lexer.init(src, "test");
        var p = Parser.init(&lex, alloc);
        const mod = try p.parse_module();
        var s = Sema.init(alloc);
        try s.check_module(@constCast(&mod));
        return .{ .arena = arena, .mod = mod, .sema = s };
    }

    fn deinit(self: *Harness) void {
        self.arena.deinit();
    }
};

test "mono: identical type args reuse a single specialization" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
        \\local b: i64 = id(2)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    // Two calls with i64 args → exactly one specialization.
    try testing.expectEqual(@as(usize, 1), mono.count());
    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 1), specs.len);
    try testing.expect(specs[0].type_args.len == 1);
    try testing.expect(specs[0].type_args[0] == .i64);
}

test "mono: distinct type args produce distinct specializations" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
        \\local b: f64 = id(2.0)
        \\local c: str = id("hi")
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    try testing.expectEqual(@as(usize, 3), mono.count());
    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 3), specs.len);
}

test "mono: mangled names are deterministic and type-tagged" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 1), specs.len);
    try testing.expectEqualStrings("duo_id_i64", specs[0].mangled_name);
}

test "mono: non-generic functions produce no specializations" {
    var h = try Harness.run(
        \\fun add(a: i64, b: i64): i64 a + b
        \\local x: i64 = add(1, 2)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    try testing.expectEqual(@as(usize, 0), mono.count());
}

test "mono: explicit @specialize directive creates specialization without call site" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\@specialize(id, i64)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    try testing.expectEqual(@as(usize, 1), mono.count());
    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 1), specs.len);
    try testing.expectEqualStrings("duo_id_i64", specs[0].mangled_name);
    try testing.expect(specs[0].type_args[0] == .i64);
}

test "mono: explicit @specialize parses nested generic type arguments" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\@specialize(id, Result[i64, str])
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    try testing.expectEqual(@as(usize, 1), mono.count());
    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 1), specs.len);
    try testing.expect(specs[0].type_args[0] == .result);
    try testing.expect(specs[0].type_args[0].result.ok.* == .i64);
    try testing.expect(specs[0].type_args[0].result.err.* == .str);
}

test "mono: substitution map resolves a type parameter to its concrete type" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    const specs = try mono.getSpecializations("id");
    try testing.expectEqual(@as(usize, 1), specs.len);
    // `T` inside this specialization resolves to i64.
    const resolved = specs[0].resolveType(.{ .named = "T" });
    try testing.expect(resolved == .i64);
    // A non-parameter annotation resolves normally.
    try testing.expect(specs[0].resolveType(.{ .named = "f64" }) == .f64);
}

test "mono: substitution resolves type parameters inside generic applications" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);
    const specs = try mono.getSpecializations("id");

    const base = try h.arena.allocator().create(ast.TypeExpr);
    base.* = .{ .named = "Container" };
    const params = try h.arena.allocator().alloc(ast.TypeExpr, 1);
    params[0] = .{ .named = "T" };

    const resolved = specs[0].resolveType(.{ .generic = .{ .base = base, .params = params } });
    try testing.expect(resolved == .instantiated);
    try testing.expectEqual(@as(usize, 1), resolved.instantiated.args.len);
    try testing.expect(resolved.instantiated.args[0] == .i64);
}

test "mono: substitution resolves type parameters inside function and record types" {
    var h = try Harness.run(
        \\fun id<T>(x: T): T x
        \\local a: i64 = id(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);
    const specs = try mono.getSpecializations("id");
    const alloc = h.arena.allocator();

    const fn_params = try alloc.alloc(ast.TypeExpr, 1);
    fn_params[0] = .{ .named = "T" };
    const opt_inner = try alloc.create(ast.TypeExpr);
    opt_inner.* = .{ .named = "T" };
    const fn_ret = try alloc.create(ast.TypeExpr);
    fn_ret.* = .{ .optional = opt_inner };
    const resolved_fn = specs[0].resolveType(.{ .func = .{ .params = fn_params, .ret = fn_ret } });
    try testing.expect(resolved_fn == .func);
    try testing.expect(resolved_fn.func.params[0] == .i64);
    try testing.expect(resolved_fn.func.ret.* == .option);
    try testing.expect(resolved_fn.func.ret.option.* == .i64);

    const fields = try alloc.alloc(ast.RecordField, 1);
    fields[0] = .{ .name = "value", .typ = .{ .named = "T" }, .loc = .{ .file = "test", .line = 1, .col = 1 } };
    const record = try alloc.create(ast.TypeExpr.RecordType);
    record.* = .{ .fields = fields };
    const resolved_record = specs[0].resolveType(.{ .record = record });
    try testing.expect(resolved_record == .table_type);
    try testing.expectEqual(@as(usize, 1), resolved_record.table_type.fields.len);
    try testing.expect(resolved_record.table_type.fields[0].typ == .i64);
}

test "mono: unification infers parameters inside generic applications" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const base_te = try alloc.create(ast.TypeExpr);
    base_te.* = .{ .named = "Container" };
    const params_te = try alloc.alloc(ast.TypeExpr, 1);
    params_te[0] = .{ .named = "T" };

    const base_rt = try alloc.create(RT);
    base_rt.* = .{ .@"struct" = .{ .name = "Container" } };
    const args_rt = try alloc.alloc(RT, 1);
    args_rt[0] = .i64;
    const arg: RT = .{ .instantiated = .{ .base = base_rt, .args = args_rt, .specialization_key = 1 } };

    var bindings: std.StringHashMapUnmanaged(RT) = .empty;
    defer bindings.deinit(alloc);
    const type_params = [_]ast.TypeExpr{.{ .named = "T" }};
    try Monomorphizer.unify(alloc, .{ .generic = .{ .base = base_te, .params = params_te } }, arg, &type_params, &bindings);
    try testing.expect(bindings.get("T") != null);
    try testing.expect(bindings.get("T").? == .i64);
}

test "mono: unification infers parameters inside function and record types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const type_params = [_]ast.TypeExpr{.{ .named = "T" }};

    const fn_params = try alloc.alloc(ast.TypeExpr, 1);
    fn_params[0] = .{ .named = "T" };
    const fn_ret = try alloc.create(ast.TypeExpr);
    fn_ret.* = .{ .named = "T" };
    const rt_params = try alloc.alloc(RT, 1);
    rt_params[0] = .str;
    const rt_ret = try alloc.create(RT);
    rt_ret.* = .str;

    var fn_bindings: std.StringHashMapUnmanaged(RT) = .empty;
    defer fn_bindings.deinit(alloc);
    try Monomorphizer.unify(alloc, .{ .func = .{ .params = fn_params, .ret = fn_ret } }, .{ .func = .{ .params = rt_params, .ret = rt_ret, .is_native = true } }, &type_params, &fn_bindings);
    try testing.expect(fn_bindings.get("T") != null);
    try testing.expect(fn_bindings.get("T").? == .str);

    const fields = try alloc.alloc(ast.RecordField, 1);
    fields[0] = .{ .name = "value", .typ = .{ .named = "T" }, .loc = .{ .file = "test", .line = 1, .col = 1 } };
    const record = try alloc.create(ast.TypeExpr.RecordType);
    record.* = .{ .fields = fields };
    const rt_fields = try alloc.alloc(types.FieldType, 1);
    rt_fields[0] = .{ .name = "value", .typ = .bool };

    var record_bindings: std.StringHashMapUnmanaged(RT) = .empty;
    defer record_bindings.deinit(alloc);
    try Monomorphizer.unify(alloc, .{ .record = record }, .{ .table_type = .{ .fields = rt_fields } }, &type_params, &record_bindings);
    try testing.expect(record_bindings.get("T") != null);
    try testing.expect(record_bindings.get("T").? == .bool);
}

test "mono: nested generic calls inherit the specialized parameter type" {
    var h = try Harness.run(
        \\fun inner<U>(x: U): U x
        \\fun outer<T>(x: T): T inner(x)
        \\local value: i64 = outer(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    const outer_specs = try mono.getSpecializations("outer");
    const inner_specs = try mono.getSpecializations("inner");
    try testing.expectEqual(@as(usize, 1), outer_specs.len);
    try testing.expectEqual(@as(usize, 1), inner_specs.len);
    try testing.expect(inner_specs[0].type_args[0] == .i64);
}

test "mono: recursive generic calls reuse the active specialization" {
    var h = try Harness.run(
        \\fun recurse<T>(x: T) -> T
        \\    if false then return recurse(x) end
        \\    return x
        \\end
        \\local value: i64 = recurse(1)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    const specs = try mono.getSpecializations("recurse");
    try testing.expectEqual(@as(usize, 1), specs.len);
    try testing.expect(specs[0].type_args[0] == .i64);
}

test "mono: nested generic calls inherit specialized local annotations" {
    var h = try Harness.run(
        \\fun inner<U>(x: U): U x
        \\fun outer<T>(x: T) -> T
        \\    local y: T = x
        \\    return inner(y)
        \\end
        \\local value: str = outer("ok")
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    const inner_specs = try mono.getSpecializations("inner");
    try testing.expectEqual(@as(usize, 1), inner_specs.len);
    try testing.expect(inner_specs[0].type_args[0] == .str);
}
