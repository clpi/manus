//! Monomorphizer (Requirement 4): turns generic functions into concrete
//! specializations, one per unique tuple of type arguments.
//!
//! ## Design
//!
//! A generic function in Duo is a top-level `func_decl` whose `FuncBody` carries
//! a non-empty `type_params` list (`fun id<T>(x: T) -> T ...`). At each call site
//! the concrete type arguments are *inferred* from the static types of the
//! argument expressions (Duo has no turbofish syntax), which the semantic pass
//! has already recorded in its `type_map` (`*Expr -> ResolvedType`).
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
const ast = @import("ast.zig");
const types = @import("types.zig");
const sema_mod = @import("sema.zig");

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
                const p = std.heap.page_allocator.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(inner.*);
                return .{ .pointer = p };
            },
            .optional => |inner| {
                const p = std.heap.page_allocator.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(inner.*);
                return .{ .option = p };
            },
            .array => |a| {
                const p = std.heap.page_allocator.create(RT) catch unreachable;
                p.* = self.resolveTypeRecursive(a.elem.*);
                return .{ .array = .{ .elem = p, .size = a.size } };
            },
            else => {},
        }
        return types.resolve(te, null, std.heap.page_allocator) catch .any;
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
    pub fn findSpecializationForCall(self: *Self, name: []const u8, args: []const *ast.Expr) ?*Specialization {
        const template = self.generics.get(name) orelse return null;
        const type_args = self.inferTypeArgs(template, args, null) catch return null;
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

    const Env = ?*const std.StringHashMapUnmanaged(RT);

    fn collectSitesBlock(self: *Self, block: *const ast.Block, env: Env) Error!void {
        for (block.stmts) |*stmt| try self.collectSitesStmt(stmt, env);
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
            .func_decl => |fd| try self.collectSitesBlock(&fd.func.body, env),
            .ret => |r| for (r.vals) |e| try self.collectSitesExpr(e, env),
            .match_stmt => |m| try self.collectSitesMatch(&m, env),
            .try_stmt => |t| {
                try self.collectSitesBlock(&t.body, env);
                for (t.catches) |c| try self.collectSitesBlock(&c.body, env);
                for (t.defers) |d| try self.collectSitesBlock(&d.body, env);
            },
            .defer_stmt => |d| try self.collectSitesBlock(&d.body, env),
            .brk, .goto_stmt, .label_stmt, .enum_def, .concept_def => {},
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
            },
            .try_expr => |t| try self.collectSitesExpr(t.operand, env),
            .unwrap_expr => |u| try self.collectSitesExpr(u.operand, env),
            .match_expr => |m| try self.collectSitesMatch(m, env),
            .await_expr => |a| try self.collectSitesExpr(a.operand, env),
            .contains_expr => |c| {
                try self.collectSitesExpr(c.lhs, env);
                try self.collectSitesExpr(c.rhs, env);
            },
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg, .name => {},
        }
    }

    // ── Type-argument inference ─────────────────────────────────────────────

    /// Infer the concrete type arguments for a call to `template`, in the
    /// declaration order of its `type_params`. Unbound parameters fall back to
    /// `.any`. The result slice is owned by the monomorphizer's allocator.
    fn inferTypeArgs(self: *Self, template: *const ast.FuncBody, args: []const *ast.Expr, env: Env) ![]const RT {
        const params = template.type_params orelse &.{};
        var bindings: std.StringHashMapUnmanaged(RT) = .empty;
        defer bindings.deinit(self.alloc);

        const n = @min(template.params.len, args.len);
        for (template.params[0..n], args[0..n]) |p, arg| {
            const arg_rt = self.argType(arg, env);
            try unify(self.alloc, p.typ, arg_rt, params, &bindings);
        }

        var out = try self.alloc.alloc(RT, params.len);
        for (params, 0..) |tp, i| {
            const name = typeParamName(tp);
            out[i] = bindings.get(name) orelse .any;
        }
        return out;
    }

    /// Static type of an argument expression, with the active substitution
    /// environment applied to any residual type-parameter type.
    fn argType(self: *Self, arg: *const ast.Expr, env: Env) RT {
        const base = self.type_map.get(arg) orelse .any;
        if (env) |e| {
            // A nested generic call inside a specialized body: an argument that
            // is itself a type parameter shows up as `.@"struct"{name=T}` (the
            // sema fallback for an unknown named type) or `.generic_param`.
            switch (base) {
                .@"struct" => |s| if (e.get(s.name)) |t| return t,
                .generic_param => |g| if (e.get(g.name)) |t| return t,
                else => {},
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
            .mangled_name = try self.mangleName(req.generic_name, req.type_args),
            .generic_name = req.generic_name,
            .template = req.template,
            .type_args = req.type_args,
            .substitutions = subs,
            .key = req.key,
        };
        try self.specializations.put(self.alloc, req.key, spec);
        try self.order.append(self.alloc, spec);

        // Fixed-point: scan the specialized body with this substitution active
        // to surface nested generic instantiations.
        try self.collectSitesBlock(&req.template.body, &spec.substitutions);
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

fn typeParamName(tp: ast.TypeExpr) []const u8 {
    return switch (tp) {
        .named => |n| n,
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
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
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
        \\fun id<T>(x: T) -> T return x end
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
        \\fun id<T>(x: T) -> T return x end
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
        \\fun id<T>(x: T) -> T return x end
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
        \\fun add(a: i64, b: i64) -> i64 return a + b end
        \\local x: i64 = add(1, 2)
    );
    defer h.deinit();

    var mono = Monomorphizer.init(h.arena.allocator(), &h.sema.type_map);
    try mono.run(&h.mod);

    try testing.expectEqual(@as(usize, 0), mono.count());
}

test "mono: substitution map resolves a type parameter to its concrete type" {
    var h = try Harness.run(
        \\fun id<T>(x: T) -> T return x end
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
