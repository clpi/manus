//! PLACE — observable location facts, never a synonym for value or binding.
//!
//! A place exists only where program semantics may require a location: indexed
//! or projected aggregate access, mutation, aliasing, escape, address/lifetime
//! identity, persistence, volatile/device behavior, or a real ABI boundary.
//! Scalar values, parameters and homes are not minted as places merely because
//! the host compiler stores or names them.
//!
//! This module is a bounded bootstrap producer for location facts. The graph
//! owns the published facts; names and AST pointers are provenance while exact
//! graph access/application identities replace this walk. Unknown is always
//! pessimistic. No source face is reinterpreted here: `[]` is indexed access,
//! `()` is ordinary application.

const std = @import("std");
const ast = @import("ast.zig");
const demand = @import("demand.zig");

pub const Tri = enum {
    yes,
    no,
    unknown,

    pub fn proven(self: Tri) bool {
        return self == .yes;
    }
};

/// Three-valued reference into one census's aggregate-place space. Kept as a
/// compatibility fact projection for region and graph consumers while exact
/// graph access ids replace the bounded AST census. `none` and `unknown` are
/// never represented by the same sentinel.
pub const Site = union(enum) {
    unknown,
    none,
    one: u32,

    pub fn name(self: Site) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
    }
};

pub const Determinacy = enum { exact, bounded, unknown };

pub const Extent = union(enum) {
    exact: u32,
    bounded: u32,
    unknown,

    pub fn upper(self: Extent) ?u32 {
        return switch (self) {
            .exact => |n| n,
            .bounded => |n| n,
            .unknown => null,
        };
    }
};

pub const Mult = union(enum) {
    exact: u64,
    bounded: u64,
    unknown,

    pub fn lower(self: Mult) u64 {
        return switch (self) {
            .exact => |n| n,
            .bounded, .unknown => 1,
        };
    }

    pub fn upperOrNull(self: Mult) ?u64 {
        return switch (self) {
            .exact => |n| n,
            .bounded => |n| n,
            .unknown => null,
        };
    }

    pub fn mul(a: Mult, b: Mult) Mult {
        return switch (a) {
            .unknown => .unknown,
            .exact => |x| switch (b) {
                .unknown => .unknown,
                .exact => |y| .{ .exact = x *| y },
                .bounded => |y| .{ .bounded = x *| y },
            },
            .bounded => |x| switch (b) {
                .unknown => .unknown,
                .exact => |y| .{ .bounded = x *| y },
                .bounded => |y| .{ .bounded = x *| y },
            },
        };
    }
};

pub const Lifetime = enum { region, function, module, unknown };
pub const Residency = enum { absent, register, frame, static, foreign, unknown };
pub const Origin = enum { literal, derived, parameter, world, unknown };

/// Compatibility encoding for consumers while graph facts replace host tags.
/// `collection`, `record` and `scalar` are produced. The retired members remain
/// so old exhaustive switches fail closed rather than acquiring a new meaning.
///
/// WHY `scalar` IS PRODUCED, AND ONLY AT MODULE REGION. This file's header says
/// a place exists where semantics may require a LOCATION — mutation, aliasing,
/// escape, lifetime identity, PERSISTENCE — and not merely because the host
/// compiler stores or names a value. A module-scope binding is exactly such a
/// location: it is one `__DATA` word whose lifetime is the module's and which
/// every relation in the file may read or write at a time the module's own
/// statement order does not fix. That is persistence and lifetime identity, so
/// it is a place. A FUNCTION-LOCAL scalar is not: it dies with its frame and no
/// second region can name it, so `bindPlace` still declines one.
pub const Shape = enum { unknown, scalar, collection, record, parameter, home };
pub const Region = enum { function, module };

pub const AccessKind = enum { bind, write, read };

pub const Access = struct {
    kind: AccessKind,
    point: u32,
    depth: u8,
    mult: Mult,
    const_index: bool,
};

pub const Facts = struct {
    determinacy: Determinacy = .unknown,
    extent: Extent = .unknown,
    mutation: Tri = .unknown,
    immutability: Tri = .unknown,
    alias: Tri = .unknown,
    escape: Tri = .unknown,
    lifetime: Lifetime = .unknown,
    alignment: ?u16 = null,
    residency: Residency = .unknown,
    origin: Origin = .unknown,
    contents_known: Tri = .unknown,
    ordered: Tri = .unknown,
    domain: ?u64 = null,
};

pub const Place = struct {
    id: u32,
    name: []const u8,
    binding: *const ast.Stmt,
    shape: Shape,
    region: Region,
    /// Declaration or assignment — see `BindOrigin`. `binding` carries the
    /// statement this came from, but a statement TAG is provenance: reading
    /// `.assign` off it in a consumer would make the AST spelling of the
    /// binding the authority a second time, which is the defect this fact
    /// exists to end.
    bind_origin: BindOrigin,
    init: ?*const ast.Expr,
    facts: Facts = .{},
    accesses: std.ArrayListUnmanaged(Access) = .empty,

    pub fn deinit(self: *Place, alloc: std.mem.Allocator) void {
        self.accesses.deinit(alloc);
    }

    pub fn readCount(self: *const Place) Mult {
        return self.countOf(.read);
    }

    pub fn writeCount(self: *const Place) Mult {
        return self.countOf(.write);
    }

    pub fn bindCount(self: *const Place) Mult {
        return self.countOf(.bind);
    }

    fn countOf(self: *const Place, kind: AccessKind) Mult {
        var unknown = false;
        var bounded = false;
        var total: u64 = 0;
        for (self.accesses.items) |a| {
            if (a.kind != kind) continue;
            switch (a.mult) {
                .unknown => unknown = true,
                .exact => |n| total +|= n,
                .bounded => |n| {
                    bounded = true;
                    total +|= n;
                },
            }
        }
        if (unknown) return .unknown;
        return if (bounded) .{ .bounded = total } else .{ .exact = total };
    }

    pub fn readsPerBuild(self: *const Place) ?u64 {
        const reads = self.readCount().upperOrNull() orelse return null;
        const builds = self.bindCount().upperOrNull() orelse return null;
        if (builds == 0) return null;
        return reads / builds;
    }

    pub fn anyRuntimeIndex(self: *const Place) bool {
        for (self.accesses.items) |a| {
            if ((a.kind == .read or a.kind == .write) and !a.const_index) return true;
        }
        return false;
    }
};

pub const Refusal = enum {
    none,
    not_module,
    shape,
    no_value,
    mutated,
    rebound,
    aliased,
    escaped,
    indeterminate,
    runtime_index,
};

/// A module aggregate may be physically absent only when every access is
/// statically determined and no mutation, alias or escape makes a location
/// observable. This is a realization fact, not a claim that every binding is a
/// place. Scalar values and homes never enter this function because no Place is
/// produced for them.
pub fn residencyRefusal(p: *const Place) Refusal {
    if (p.region != .module) return .not_module;
    if (p.shape != .collection and p.shape != .record) return .shape;
    if (p.init == null) return .no_value;
    if (p.facts.mutation != .no or p.facts.immutability != .yes) return .mutated;
    switch (p.bindCount()) {
        .exact => |n| if (n != 1) return .rebound,
        else => return .rebound,
    }
    if (p.facts.alias != .no) return .aliased;
    if (p.facts.escape != .no) return .escaped;
    if (p.facts.determinacy != .exact) return .indeterminate;
    return .none;
}

pub fn ruledResidency(p: *const Place) Residency {
    if (residencyRefusal(p) == .none) return .absent;
    return switch (p.region) {
        .module => .static,
        .function => .frame,
    };
}

pub const Census = struct {
    places: std.ArrayListUnmanaged(Place) = .empty,
    alloc: std.mem.Allocator,
    points: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Census {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Census) void {
        for (self.places.items) |*p| p.deinit(self.alloc);
        self.places.deinit(self.alloc);
    }

    pub fn count(self: *const Census) usize {
        return self.places.items.len;
    }

    pub fn countOfShape(self: *const Census, shape: Shape) usize {
        var n: usize = 0;
        for (self.places.items) |*p| {
            if (p.shape == shape) n += 1;
        }
        return n;
    }

    pub fn find(self: *const Census, name: []const u8) ?*const Place {
        var i = self.places.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.places.items[i].name, name)) return &self.places.items[i];
        }
        return null;
    }

    pub fn byName(self: *Census, name: []const u8) ?*Place {
        return @constCast(self.find(name) orelse return null);
    }

    pub fn get(self: *Census, id: u32) ?*Place {
        for (self.places.items) |*p| if (p.id == id) return p;
        return null;
    }
};

/// WHICH MODULE-SCOPE WORDS A RELATION BODY CAN REACH.
///
/// THIS EXISTS BECAUSE THE MAIN WALK IS ORDER-DEPENDENT AND THE FACT IS NOT.
/// `walkForeignBody` visits a relation's body at the statement where the
/// relation is DECLARED, and `bindOrRebind` drops a bare-name assignment whose
/// place does not exist yet (`if (ctx.foreign) return;`). So for
///
///     f: () = ()
///         x = 5
///     x: i64 = 0
///
/// the write is invisible and `x` would be published as never mutated — a
/// WRONG answer, not a missing one, and the only kind a consumer cannot defend
/// against. Module-scope order does not decide whether a relation reaches a
/// word, so the question is answered before the walk begins and consulted at
/// every bind.
///
/// IT OVER-APPROXIMATES, DELIBERATELY. A relation that DECLARES its own `x`
/// still counts as reaching the module's `x`, because separating the two here
/// would duplicate the shadow adjudication `BindOrigin` owns and put a second
/// answer to one question in the tree. Over-counting moves `escape`/`mutation`
/// toward `.yes`, which is the refusing direction for every consumer.
///
/// `opaque_body` is the fail-closed exit: a construct this scan does not model
/// could reach ANY word, so no `.no` may be published for any name once it is
/// set. Both switches below are EXHAUSTIVE — a new AST member breaks the build
/// rather than silently joining the modelled set.
const ForeignReach = struct {
    named: std.ArrayListUnmanaged([]const u8) = .empty,
    assigned: std.ArrayListUnmanaged([]const u8) = .empty,
    opaque_body: bool = false,

    fn deinit(self: *ForeignReach, alloc: std.mem.Allocator) void {
        self.named.deinit(alloc);
        self.assigned.deinit(alloc);
    }

    fn has(list: []const []const u8, name: []const u8) bool {
        for (list) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }

    fn mentions(self: *const ForeignReach, name: []const u8) bool {
        return has(self.named.items, name);
    }

    fn assigns(self: *const ForeignReach, name: []const u8) bool {
        return has(self.assigned.items, name);
    }

    fn note(alloc: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8), name: []const u8) !void {
        if (has(list.items, name)) return;
        try list.append(alloc, name);
    }
};

/// EVERY BODY IN THE MODULE THAT IS NOT THE MODULE'S OWN.
///
/// `.func_decl` is not the only one. `alias_def` carries `methods`, and a scan
/// that visited only relations would publish `escape:"no"` for a word an alias
/// method writes — a wrong answer with a consumer waiting for it.
///
/// Statements not named here need no arm: they are either the module's own
/// straight-line body, which the main walk records access by access, or a shape
/// the main walk already refuses through `markAllUnknown`. The two exceptions
/// are named explicitly, because the main walk treats them as NO-OPS: a C
/// header brings in code this compiler does not read, and a macro body is code
/// whose expansion this scan does not model.
fn foreignReach(alloc: std.mem.Allocator, mod: *const ast.Module) !ForeignReach {
    var out: ForeignReach = .{};
    errdefer out.deinit(alloc);
    for (mod.body.stmts) |*stmt| switch (stmt.*) {
        .func_decl => |*fd| try reachBody(alloc, &out, &fd.func),
        .alias_def => |ad| for (ad.methods) |*m| try reachBody(alloc, &out, &m.func),
        .cinclude, .macro_def => out.opaque_body = true,
        else => {},
    };
    return out;
}

fn reachBody(alloc: std.mem.Allocator, out: *ForeignReach, fb: *const ast.FuncBody) anyerror!void {
    try reachBlock(alloc, out, &fb.body);
}

fn reachBlock(alloc: std.mem.Allocator, out: *ForeignReach, b: *const ast.Block) anyerror!void {
    for (b.stmts) |*s| try reachStmt(alloc, out, s);
    if (b.tail_expr) |t| try reachExpr(alloc, out, t);
}

fn reachStmt(alloc: std.mem.Allocator, out: *ForeignReach, s: *const ast.Stmt) anyerror!void {
    switch (s.*) {
        .local_decl => |d| for (d.inits) |e| try reachExpr(alloc, out, e),
        .const_decl => |d| try reachExpr(alloc, out, d.val),
        .global_decl => |d| {
            for (d.inits) |e| try reachExpr(alloc, out, e);
            // `global x = …` inside a relation writes the module word.
            for (d.names) |n| try ForeignReach.note(alloc, &out.assigned, n.ident);
            for (d.names) |n| try ForeignReach.note(alloc, &out.named, n.ident);
        },
        .assign => |a| {
            for (a.values) |v| try reachExpr(alloc, out, v);
            for (a.targets) |t| {
                if (t.* == .name) {
                    try ForeignReach.note(alloc, &out.assigned, t.name.ident);
                    try ForeignReach.note(alloc, &out.named, t.name.ident);
                } else try reachExpr(alloc, out, t);
            }
        },
        .call_stmt => |c| try reachExpr(alloc, out, c.expr),
        .expr_stmt => |e| try reachExpr(alloc, out, e.expr),
        .do_block => |d| try reachBlock(alloc, out, &d.body),
        .while_loop => |w| {
            try reachExpr(alloc, out, w.cond);
            try reachBlock(alloc, out, &w.body);
        },
        .repeat_loop => |r| {
            try reachBlock(alloc, out, &r.body);
            try reachExpr(alloc, out, r.cond);
        },
        .if_stmt => |f| {
            if (f.binding) |binding| try reachExpr(alloc, out, binding.expr);
            try reachExpr(alloc, out, f.cond);
            try reachBlock(alloc, out, &f.then);
            for (f.elseifs) |ei| {
                try reachExpr(alloc, out, ei.cond);
                try reachBlock(alloc, out, &ei.body);
            }
            if (f.else_body) |*body| try reachBlock(alloc, out, body);
        },
        .num_for => |f| {
            try reachExpr(alloc, out, f.start);
            try reachExpr(alloc, out, f.stop);
            if (f.step) |st| try reachExpr(alloc, out, st);
            try reachBlock(alloc, out, &f.body);
        },
        .gen_for => |f| {
            for (f.iters) |iter| try reachExpr(alloc, out, iter);
            try reachBlock(alloc, out, &f.body);
        },
        .ret => |r| for (r.vals) |v| try reachExpr(alloc, out, v),
        .brk, .cont, .label_stmt, .enum_def, .concept_def, .alias_def => {},
        // NOT MODELLED. A nested relation, a macro, a `goto`, a C header, a
        // `defer`, a `match` or a `try` body can name anything; publishing
        // `.no` for a word after seeing one would be a claim this scan cannot
        // support.
        .func_decl, .macro_def, .cinclude, .directive, .goto_stmt, .match_stmt, .try_stmt, .defer_stmt => out.opaque_body = true,
    }
}

fn reachExpr(alloc: std.mem.Allocator, out: *ForeignReach, e: *const ast.Expr) anyerror!void {
    switch (e.*) {
        .name => |n| try ForeignReach.note(alloc, &out.named, n.ident),
        .index => |ix| {
            try reachExpr(alloc, out, ix.obj);
            try reachExpr(alloc, out, ix.key);
        },
        .field => |f| try reachExpr(alloc, out, f.obj),
        .call => |c| {
            try reachExpr(alloc, out, c.func);
            for (c.args) |a| try reachExpr(alloc, out, a);
        },
        .method_call => |m| {
            try reachExpr(alloc, out, m.obj);
            for (m.args) |a| try reachExpr(alloc, out, a);
        },
        .binop => |b| {
            try reachExpr(alloc, out, b.lhs);
            try reachExpr(alloc, out, b.rhs);
        },
        .unop => |u| try reachExpr(alloc, out, u.operand),
        .try_expr => |v| try reachExpr(alloc, out, v.operand),
        .unwrap_expr => |v| try reachExpr(alloc, out, v.operand),
        .await_expr => |v| try reachExpr(alloc, out, v.operand),
        .contains_expr => |v| {
            try reachExpr(alloc, out, v.lhs);
            try reachExpr(alloc, out, v.rhs);
        },
        .range => |r| {
            try reachExpr(alloc, out, r.start);
            try reachExpr(alloc, out, r.end);
            if (r.step) |st| try reachExpr(alloc, out, st);
        },
        .sequence => |sq| for (sq.exprs) |v| try reachExpr(alloc, out, v),
        .if_expr => |i| {
            try reachExpr(alloc, out, i.cond);
            try reachExpr(alloc, out, i.then_expr);
            try reachExpr(alloc, out, i.else_expr);
        },
        .table => |t| for (t.fields) |field| switch (field) {
            .indexed => |v| {
                try reachExpr(alloc, out, v.key);
                try reachExpr(alloc, out, v.val);
            },
            .named => |v| try reachExpr(alloc, out, v.val),
            .positional => |v| try reachExpr(alloc, out, v),
            .spread => |v| try reachExpr(alloc, out, v),
            .semantic => |v| try reachExpr(alloc, out, v.val),
        },
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg => {},
        // NOT MODELLED — same rule as `reachStmt`.
        .func_expr, .list_comp, .match_expr, .quote, .unquote, .macro_call, .semantic, .semantic_scope => out.opaque_body = true,
    }
}

const Ctx = struct {
    census: *Census,
    depth: u8 = 0,
    mult: Mult = .{ .exact = 1 },
    region: Region = .function,
    foreign: bool = false,
    shadow: std.ArrayListUnmanaged([]const u8) = .empty,
    reach: ForeignReach = .{},
    /// `markAllUnknown` has fired. It degrades every place the census ALREADY
    /// holds, and a place bound afterwards would otherwise be published as if
    /// the refusal had never happened — the same order-dependence
    /// `ForeignReach` exists to end, on the other axis.
    refused: bool = false,

    fn deinit(self: *Ctx) void {
        self.shadow.deinit(self.census.alloc);
        self.reach.deinit(self.census.alloc);
    }

    fn lookup(self: *Ctx, name: []const u8) ?*Place {
        for (self.shadow.items) |s| if (std.mem.eql(u8, s, name)) return null;
        return self.census.byName(name);
    }

    fn shadowName(self: *Ctx, name: []const u8) !void {
        try self.shadow.append(self.census.alloc, name);
    }
};

pub fn analyzeFunction(alloc: std.mem.Allocator, fb: *const ast.FuncBody) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census };
    defer ctx.deinit();
    try walkBlock(&ctx, &fb.body);
    return census;
}

pub fn analyzeModule(alloc: std.mem.Allocator, mod: *const ast.Module) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{
        .census = &census,
        .region = .module,
        // Answered BEFORE the walk, because which relations reach a word does
        // not depend on where in the file the word is declared.
        .reach = try foreignReach(alloc, mod),
    };
    defer ctx.deinit();
    try walkBlock(&ctx, &mod.body);
    return census;
}

fn walkBlock(ctx: *Ctx, block: *const ast.Block) anyerror!void {
    for (block.stmts) |*stmt| try walkStmt(ctx, stmt);
    if (block.tail_expr) |tail| try readExpr(ctx, tail);
}

fn walkStmt(ctx: *Ctx, stmt: *const ast.Stmt) anyerror!void {
    const point = ctx.census.points;
    ctx.census.points += 1;
    switch (stmt.*) {
        .local_decl => |d| {
            for (d.inits) |e| {
                if (try aliasInit(ctx, e)) continue;
                try readExpr(ctx, e);
            }
            for (d.names, 0..) |n, i| {
                const init: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                if (ctx.foreign) {
                    try ctx.shadowName(n.ident);
                    continue;
                }
                try bindOrRebind(ctx, n.ident, stmt, point, init, n.typ, .declaration);
            }
        },
        .const_decl => |d| {
            if (!(try aliasInit(ctx, d.val))) try readExpr(ctx, d.val);
            if (ctx.foreign) try ctx.shadowName(d.ident) else
                try bindOrRebind(ctx, d.ident, stmt, point, d.val, d.typ, .declaration);
        },
        .global_decl => |d| {
            for (d.inits) |e| {
                if (try aliasInit(ctx, e)) continue;
                try readExpr(ctx, e);
            }
            for (d.names, 0..) |n, i| {
                const init: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                try bindOrRebind(ctx, n.ident, stmt, point, init, n.typ,
                    if (ctx.foreign) .assignment else .declaration);
            }
        },
        .assign => |a| {
            for (a.values) |v| {
                if (try aliasInit(ctx, v)) continue;
                try readExpr(ctx, v);
            }
            for (a.targets, 0..) |target, i| {
                const value: ?*const ast.Expr = if (i < a.values.len) a.values[i] else null;
                if (target.* == .name) {
                    if (ctx.foreign and ctx.lookup(target.name.ident) != null) {
                        try bindOrRebind(ctx, target.name.ident, stmt, point, value, .inferred, .assignment);
                    } else if (ctx.foreign) {
                        try ctx.shadowName(target.name.ident);
                    } else {
                        try bindOrRebind(ctx, target.name.ident, stmt, point, value, .inferred, .assignment);
                    }
                    continue;
                }
                try writeTarget(ctx, target, point);
            }
        },
        .func_decl => |*fd| {
            if (ctx.region != .module or ctx.foreign) {
                try markAllUnknown(ctx);
            } else {
                try walkForeignBody(ctx, &fd.func);
            }
        },
        .enum_def, .alias_def, .concept_def, .macro_def, .cinclude, .directive,
        .label_stmt, .goto_stmt, .brk, .cont => {},
        .ret => |r| for (r.vals) |v| try readExpr(ctx, v),
        .call_stmt => |c| try readExpr(ctx, c.expr),
        .expr_stmt => |e| try readExpr(ctx, e.expr),
        .do_block => |d| try walkBlock(ctx, &d.body),
        .while_loop => |w| {
            try readExpr(ctx, w.cond);
            const trip: Mult = if (demand.provenTripCount(w)) |proof| blk: {
                const step: u64 = @intCast(if (proof.step < 0) -proof.step else proof.step);
                if (step == 0) break :blk .unknown;
                const limit: u64 = if (proof.limit < 0) 0 else @intCast(proof.limit);
                break :blk .{ .bounded = (limit + step - 1) / step };
            } else .unknown;
            try nested(ctx, &w.body, trip);
        },
        .repeat_loop => |r| {
            try nested(ctx, &r.body, .unknown);
            try readExpr(ctx, r.cond);
        },
        .if_stmt => |f| {
            if (f.binding) |binding| {
                try readExpr(ctx, binding.expr);
                if (ctx.foreign) try ctx.shadowName(binding.name);
            }
            try readExpr(ctx, f.cond);
            try nestedBound(ctx, &f.then);
            for (f.elseifs) |ei| {
                try readExpr(ctx, ei.cond);
                try nestedBound(ctx, &ei.body);
            }
            if (f.else_body) |*body| try nestedBound(ctx, body);
        },
        .num_for => |f| {
            try readExpr(ctx, f.start);
            try readExpr(ctx, f.stop);
            if (f.step) |step| try readExpr(ctx, step);
            if (ctx.foreign) try ctx.shadowName(f.var_name);
            try nested(ctx, &f.body, numForTrip(f));
        },
        .gen_for => |f| {
            for (f.iters) |iter| try readExpr(ctx, iter);
            if (ctx.foreign) for (f.vars) |name| try ctx.shadowName(name);
            try nested(ctx, &f.body, .unknown);
        },
        else => try markAllUnknown(ctx),
    }
}

fn numForTrip(f: anytype) Mult {
    const first = intLit(f.start) orelse return .unknown;
    const last = intLit(f.stop) orelse return .unknown;
    const step: i64 = if (f.step) |s| (intLit(s) orelse return .unknown) else 1;
    if (step == 0) return .unknown;
    if (step > 0) {
        if (last < first) return .{ .exact = 0 };
        return .{ .exact = @intCast(@divFloor(last - first, step) + 1) };
    }
    if (last > first) return .{ .exact = 0 };
    return .{ .exact = @intCast(@divFloor(first - last, -step) + 1) };
}

fn intLit(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |v| v.val,
        .unop => |u| if (u.op == .neg) (if (intLit(u.operand)) |v| -v else null) else null,
        else => null,
    };
}

fn nested(ctx: *Ctx, block: *const ast.Block, trip: Mult) anyerror!void {
    const depth = ctx.depth;
    const mult = ctx.mult;
    ctx.depth +|= 1;
    ctx.mult = Mult.mul(ctx.mult, trip);
    try walkBlock(ctx, block);
    ctx.depth = depth;
    ctx.mult = mult;
}

fn nestedBound(ctx: *Ctx, block: *const ast.Block) anyerror!void {
    const mult = ctx.mult;
    ctx.mult = switch (ctx.mult) {
        .exact => |n| .{ .bounded = n },
        else => ctx.mult,
    };
    try walkBlock(ctx, block);
    ctx.mult = mult;
}

fn walkForeignBody(ctx: *Ctx, fb: *const ast.FuncBody) anyerror!void {
    const foreign = ctx.foreign;
    const mult = ctx.mult;
    const depth = ctx.depth;
    const shadow_len = ctx.shadow.items.len;
    ctx.foreign = true;
    ctx.mult = .unknown;
    ctx.depth +|= 1;
    for (fb.params) |param| try ctx.shadowName(param.name);
    try walkBlock(ctx, &fb.body);
    ctx.shadow.shrinkRetainingCapacity(shadow_len);
    ctx.foreign = foreign;
    ctx.mult = mult;
    ctx.depth = depth;
}

fn markAllUnknown(ctx: *Ctx) !void {
    ctx.refused = true;
    for (ctx.census.places.items) |*p| {
        p.facts.escape = .unknown;
        p.facts.alias = .unknown;
        p.facts.mutation = .unknown;
        p.facts.immutability = .unknown;
        p.facts.determinacy = .unknown;
        // A SCALAR HAS NO SECOND STORE FOR ITS VALUE. An aggregate's
        // `contents_known` survives this sledgehammer because it is a fact
        // about the INITIALIZER's fields, which an unmodelled statement
        // elsewhere does not rewrite. A scalar's contents ARE its value, and an
        // unmodelled statement may have written it, so the same refusal reaches
        // one fact further here.
        if (p.shape == .scalar) p.facts.contents_known = .unknown;
    }
}

/// WHETHER A BINDING STATEMENT DECLARES THE NAME OR ASSIGNS TO ONE THE
/// ENCLOSING SCOPE ALREADY OWNS. The census computed this to decide which
/// access to record and then threw it away, so no consumer could ask it.
///
/// It is a DIFFERENT question from every fact already on a place. A relation
/// that writes `M.x` and a relation that DECLARES its own `M` and writes `M.x`
/// produce the same spelling, the same shape and the same accesses; only this
/// separates them, and a realization that resolves `M.x` to storage by spelling
/// alone answers the second one from the first one's word.
pub const BindOrigin = enum { declaration, assignment };
const BindMode = BindOrigin;

fn bindOrRebind(
    ctx: *Ctx,
    name: []const u8,
    stmt: *const ast.Stmt,
    point: u32,
    init: ?*const ast.Expr,
    typ: ast.TypeExpr,
    mode: BindMode,
) !void {
    if (ctx.lookup(name)) |p| {
        // A SCALAR ASSIGNMENT IS A STORE TO THE WORD, NOT A REBINDING.
        // A collection's `xs = { … }` builds a NEW value and binds the name to
        // it, which is why the census records `.bind` and
        // `residencyRefusal` counts binds. A module scalar has one word for the
        // module's lifetime; `i = i + 1` writes it. Recording that as a bind
        // would leave `writeCount()` at zero for the only kind of place whose
        // whole cost is its stores.
        if (p.shape == .scalar and mode == .assignment) {
            try appendAccess(ctx, p, .write, point, true);
            p.facts.mutation = .yes;
            p.facts.immutability = .no;
            p.facts.contents_known = .no;
            return;
        }
        if (ctx.foreign and mode == .assignment) {
            try appendAccess(ctx, p, .write, point, true);
            p.facts.mutation = .yes;
            p.facts.immutability = .no;
            p.facts.contents_known = .no;
            p.facts.ordered = .unknown;
        } else {
            try appendAccess(ctx, p, .bind, point, true);
        }
        return;
    }
    if (ctx.foreign) return;
    try bindPlace(ctx, name, stmt, point, init, typ, mode);
}

fn candidateShape(init: ?*const ast.Expr, typ: ast.TypeExpr) Shape {
    if (declaredExtent(typ) != null) return .collection;
    // A BRACE INITIALIZER OUTRANKS A SCALAR ANNOTATION, and this order is
    // measured, not stylistic. `lib/crypto.id` spells
    // `secure_random_int: i64 = {}`; reading the annotation first turned its
    // aggregate row into a scalar one and DELETED a place a consumer already
    // has. A construction of an aggregate is an aggregate whatever the
    // annotation says, and the new answer must never take a row away from the
    // old one.
    if (init) |e| if (e.* == .table) {
        for (e.table.fields) |field| switch (field) {
            .named, .indexed, .semantic => return .record,
            else => {},
        };
        return .collection;
    };
    if (typ == .named and scalarRingWord(typ.named)) return .scalar;
    const e = init orelse return .unknown;
    return switch (e.*) {
        // AN UNANNOTATED BINDING IS SCALAR ONLY WHEN ITS INITIALIZER PROVES IT.
        // `x = f()` stays `.unknown` — that is the honest answer for a value
        // this walk did not evaluate, and `.unknown` means NO ROW, not a row of
        // unknowns. Nothing here widens by guessing.
        .int_lit, .float_lit, .true_lit, .false_lit, .unop => if (typ == .inferred and scalarLiteral(e)) .scalar else .unknown,
        else => .unknown,
    };
}

/// THE SCALAR RING WORDS — the declared types that name one ring element and no
/// members. `str` is absent on purpose: a string has contents and a location
/// this walk does not model. `ptr`, `*T`, `?T`, arrays, records, tuples,
/// generics and function types are absent because they are not one element.
///
/// `int`/`integer` are here because `types.zig` resolves both to `i64`, so
/// leaving them out would make ONE type answer two ways depending on spelling —
/// the defect §8 forbids.
fn scalarRingWord(n: []const u8) bool {
    const words = [_][]const u8{
        "i8",  "i16", "i32", "i64", "u8",   "u16",     "u32", "u64",
        "f32", "f64", "bool", "int", "integer",
    };
    for (words) |w| if (std.mem.eql(u8, n, w)) return true;
    return false;
}

fn scalarLiteral(e: *const ast.Expr) bool {
    return switch (e.*) {
        .int_lit, .float_lit, .true_lit, .false_lit => true,
        .unop => |u| switch (u.op) {
            .neg, .not, .bnot => scalarLiteral(u.operand),
            // `len` and `compile` are applications, not ring arithmetic.
            .len, .compile => false,
        },
        else => false,
    };
}

/// THE SIX DECISION FACTS FOR A MODULE SCALAR, EACH WITH ITS OWN PROOF.
///
/// The same fact family collections and records publish — no scalar-specific
/// names, no second identity space for one question. What differs is the PROOF,
/// and it differs for one reason stated once here:
///
///   A SCALAR MENTION YIELDS A COPY OF THE RING ELEMENT, NOT ITS LOCATION.
///   `ys = xs` on a collection makes `ys` a second name for one location, which
///   is why `aliasInit` degrades the aggregate's `alias` to `.unknown`. `y = x`
///   on a scalar copies the word. The surface offers no operator that produces
///   the address of a binding — `ast.UnOp` is `{ neg, not, len, bnot, compile }`
///   and `TypeExpr.pointer` is TYPE position, so a value may BE a pointer while
///   no expression MAKES one out of a binding. `scalarAliasIsTwoValued` below
///   is an exhaustive switch over `ast.UnOp` so that adding an address-of
///   operator breaks this build instead of quietly invalidating the proof.
///
/// escape          `.yes`  a module relation body names the word — it is read
///                         or written at a time this module's straight-line
///                         order does not fix.
///                 `.no`   no relation body names it and nothing was refused.
///                 `.unknown` the walk refused a construct, here or in a body.
/// alias           `.no` by the copy rule above; `.unknown` once refused.
///                 `.yes` IS UNREACHABLE on this surface — see the report.
/// mutation        `.yes`  some assignment stores to the word.
/// immutability    the complement of `mutation`, published because a consumer
///                 reads them together (see `aggregateIsSoleImmutableBinding`).
/// contents_known  `.yes`  a literal initializer and no store anywhere.
///                 `.no`   a store exists, so no static value answers for it.
///                 `.unknown` the initializer is a value this walk did not
///                         evaluate, or the walk refused.
/// bind_origin     already carried by `Place`; `.declaration` for `x: i64 = 0`,
///                 `.assignment` for a bare `x = 0` the module never declared.
fn scalarFacts(ctx: *Ctx, p: *Place, name: []const u8, init: ?*const ast.Expr) void {
    // A scalar holds exactly one ring element, and there is no index to be
    // indeterminate about.
    p.facts.extent = .{ .exact = 1 };
    p.facts.determinacy = if (ctx.refused) .unknown else .exact;

    const blind = ctx.refused or ctx.reach.opaque_body;
    const written = ctx.reach.assigns(name);

    p.facts.escape = if (blind) .unknown else if (ctx.reach.mentions(name)) .yes else .no;
    // The `.no` below is licensed by the closed operator set, so the guard that
    // keeps that set closed is REFERENCED here — an unreferenced function in
    // this language is never analyzed, and an unanalyzed exhaustive switch
    // guards nothing.
    std.debug.assert(scalarAliasIsTwoValued(.neg));
    p.facts.alias = if (blind) .unknown else .no;
    p.facts.mutation = if (blind) .unknown else if (written) .yes else .no;
    p.facts.immutability = switch (p.facts.mutation) {
        .yes => .no,
        .no => .yes,
        .unknown => .unknown,
    };

    const literal = if (init) |e| scalarLiteral(e) else false;
    p.facts.origin = if (literal) .literal else .derived;
    // `.unknown` and `.no` are DIFFERENT answers and are kept apart: `.no` says
    // no static value answers for this word because something stores to it;
    // `.unknown` says this walk did not evaluate the initializer, so it has no
    // opinion either way.
    p.facts.contents_known = if (!literal or blind) .unknown else switch (p.facts.mutation) {
        .yes => .no,
        .no => .yes,
        .unknown => .unknown,
    };
}

/// A COMPILE-TIME GUARD ON THE ALIAS PROOF, not a runtime check.
///
/// `scalarFacts` publishes `alias = .no` for every module scalar because no
/// expression on this surface produces the address of a binding. That is a
/// claim about `ast.UnOp`, and a claim about a closed set should fail the BUILD
/// when the set opens, not fail a program later. Adding a member to `ast.UnOp`
/// makes this switch non-exhaustive.
fn scalarAliasIsTwoValued(op: ast.UnOp) bool {
    return switch (op) {
        .neg, .not, .bnot, .len, .compile => true,
    };
}

fn bindPlace(
    ctx: *Ctx,
    name: []const u8,
    stmt: *const ast.Stmt,
    point: u32,
    init: ?*const ast.Expr,
    typ: ast.TypeExpr,
    origin: BindOrigin,
) !void {
    const shape = candidateShape(init, typ);
    if (shape == .unknown) return;
    // See `Shape`. A frame slot that dies with its frame is not a location any
    // second region can name, so no scalar place is minted for one.
    if (shape == .scalar and ctx.region != .module) return;

    var p = Place{
        .id = @intCast(ctx.census.places.items.len),
        .name = name,
        .binding = stmt,
        .shape = shape,
        .region = ctx.region,
        .bind_origin = origin,
        .init = init,
    };
    p.facts.lifetime = if (ctx.region == .module) .module else .function;
    p.facts.alias = .no;
    p.facts.escape = .no;
    p.facts.mutation = .no;
    p.facts.immutability = .yes;
    p.facts.determinacy = .exact;

    if (shape == .scalar) {
        scalarFacts(ctx, &p, name, init);
    } else if (init) |e| switch (e.*) {
        .table => |t| {
            p.facts.origin = .literal;
            p.facts.extent = .{ .exact = @intCast(t.fields.len) };
            p.facts.contents_known = if (allFieldsConst(t.fields)) .yes else .no;
            p.facts.ordered = if (allFieldsConst(t.fields)) orderedOf(t.fields) else .unknown;
            p.facts.domain = domainOf(t.fields);
        },
        else => {
            p.facts.origin = .derived;
            p.facts.contents_known = .unknown;
        },
    };
    if (declaredExtent(typ)) |n| p.facts.extent = .{ .exact = n };

    try ctx.census.places.append(ctx.census.alloc, p);
    try appendAccess(ctx, &ctx.census.places.items[ctx.census.places.items.len - 1], .bind, point, true);
}

fn aliasInit(ctx: *Ctx, e: *const ast.Expr) !bool {
    if (e.* != .name) return false;
    const p = ctx.lookup(e.name.ident) orelse return false;
    // `y = x` ON A SCALAR IS A COPY, NOT A SECOND NAME FOR ONE WORD. Answering
    // `.unknown` here would make `alias` unknown for every scalar that is ever
    // read into another binding — a fact published everywhere and true nowhere,
    // which is worse than absent because a consumer trusts it. `false` returns
    // this initializer to `readExpr`, where the mention is recorded as the READ
    // it is.
    if (p.shape == .scalar) return false;
    p.facts.alias = .unknown;
    return true;
}

fn appendAccess(ctx: *Ctx, p: *Place, kind: AccessKind, point: u32, constant: bool) !void {
    try p.accesses.append(ctx.census.alloc, .{
        .kind = kind,
        .point = point,
        .depth = ctx.depth,
        .mult = ctx.mult,
        .const_index = constant,
    });
}

fn writeTarget(ctx: *Ctx, target: *const ast.Expr, point: u32) anyerror!void {
    switch (target.*) {
        .name => |n| if (ctx.lookup(n.ident)) |p| {
            try appendAccess(ctx, p, if (ctx.foreign) .write else .bind, point, true);
            if (ctx.foreign) {
                p.facts.mutation = .yes;
                p.facts.immutability = .no;
            }
        },
        .index => |ix| {
            if (ix.obj.* == .name) if (ctx.lookup(ix.obj.name.ident)) |p| {
                const constant = intLit(ix.key) != null;
                try appendAccess(ctx, p, .write, point, constant);
                p.facts.mutation = .yes;
                p.facts.immutability = .no;
                if (!constant) p.facts.determinacy = .bounded;
                p.facts.contents_known = .no;
                p.facts.ordered = .unknown;
            };
            try readExpr(ctx, ix.key);
        },
        else => try markAllUnknown(ctx),
    }
}

fn readExpr(ctx: *Ctx, e: *const ast.Expr) anyerror!void {
    switch (e.*) {
        .name => |n| {
            if (ctx.lookup(n.ident)) |p| {
                // THE ONE PLACE THE COPY RULE PAYS. A bare mention of an
                // AGGREGATE hands its location to code this walk cannot model,
                // so its escape drops to `.unknown`. A bare mention of a SCALAR
                // loads the ring element; the word stays where it is. Applying
                // the aggregate rule here would publish `escape:"unknown"` on
                // every scalar the program actually uses — including both
                // variables of the loop kernel this exists to serve.
                if (p.shape == .scalar) {
                    try appendAccess(ctx, @constCast(p), .read, ctx.census.points, true);
                } else {
                    @constCast(p).facts.escape = .unknown;
                }
            }
        },
        .index => |ix| {
            if (ix.obj.* == .name) if (ctx.lookup(ix.obj.name.ident)) |p| {
                const constant = intLit(ix.key) != null;
                try appendAccess(ctx, p, .read, ctx.census.points, constant);
                if (!constant) p.facts.determinacy = .bounded;
                try readExpr(ctx, ix.key);
                return;
            };
            try readExpr(ctx, ix.obj);
            try readExpr(ctx, ix.key);
        },
        .field => |f| {
            if (f.obj.* == .name) if (ctx.lookup(f.obj.name.ident)) |p| {
                if (p.shape == .record) {
                    try appendAccess(ctx, p, .read, ctx.census.points, true);
                    return;
                }
            };
            try readExpr(ctx, f.obj);
        },
        .call => |c| {
            // Ordinary application. A collection used as the callee escapes to
            // semantics this bounded walk cannot model; it is never an index.
            try readExpr(ctx, c.func);
            for (c.args) |a| try readExpr(ctx, a);
        },
        .method_call => |m| {
            try readExpr(ctx, m.obj);
            for (m.args) |a| try readExpr(ctx, a);
        },
        .binop => |b| {
            try readExpr(ctx, b.lhs);
            try readExpr(ctx, b.rhs);
        },
        .unop => |u| try readExpr(ctx, u.operand),
        .try_expr => |v| try readExpr(ctx, v.operand),
        .unwrap_expr => |v| try readExpr(ctx, v.operand),
        .await_expr => |v| try readExpr(ctx, v.operand),
        .contains_expr => |v| {
            try readExpr(ctx, v.lhs);
            try readExpr(ctx, v.rhs);
        },
        .range => |r| {
            try readExpr(ctx, r.start);
            try readExpr(ctx, r.end);
            if (r.step) |step| try readExpr(ctx, step);
        },
        .sequence => |s| for (s.exprs) |v| try readExpr(ctx, v),
        .if_expr => |i| {
            try readExpr(ctx, i.cond);
            try readExpr(ctx, i.then_expr);
            try readExpr(ctx, i.else_expr);
        },
        .table => |t| for (t.fields) |field| switch (field) {
            .indexed => |v| {
                try readExpr(ctx, v.key);
                try readExpr(ctx, v.val);
            },
            .named => |v| try readExpr(ctx, v.val),
            .positional => |v| try readExpr(ctx, v),
            .spread => |v| try readExpr(ctx, v),
            .semantic => |v| try readExpr(ctx, v.val),
        },
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg => {},
        else => try markAllUnknown(ctx),
    }
}

fn declaredExtent(typ: ast.TypeExpr) ?u32 {
    return switch (typ) {
        .array => |a| if (a.size) |n| @intCast(n) else null,
        else => null,
    };
}

fn positionalValue(field: ast.TableField) ?*const ast.Expr {
    return switch (field) {
        .positional => |v| v,
        else => null,
    };
}

fn allFieldsConst(fields: []const ast.TableField) bool {
    for (fields) |field| {
        const v = positionalValue(field) orelse return false;
        switch (v.*) {
            .int_lit => {},
            // A NESTED LITERAL OF LITERALS IS STILL A LITERAL. Requiring every
            // field to be `.int_lit` made `contents_known` `.no` for exactly the
            // shape the nested-aggregate realization needs: `immutableAggregate`
            // demands `contents_known == .yes`, while `immutableNestedAggregateRoot`
            // demands an array-OF-ARRAY descriptor. The one predicate rejected the
            // only input the other accepted, so the static nested realization was
            // unreachable by construction rather than by any fact about a program.
            .table => |t| if (!allFieldsConst(t.fields)) return false,
            else => return false,
        }
    }
    return true;
}

fn orderedOf(fields: []const ast.TableField) Tri {
    var previous: ?i64 = null;
    for (fields) |field| {
        const expr = positionalValue(field) orelse return .unknown;
        const value = intLit(expr) orelse return .unknown;
        if (previous) |p| if (value < p) return .no;
        previous = value;
    }
    return .yes;
}

fn domainOf(fields: []const ast.TableField) ?u64 {
    var maximum: i64 = 0;
    for (fields) |field| {
        const expr = positionalValue(field) orelse return null;
        const value = intLit(expr) orelse return null;
        if (value < 0) return null;
        maximum = @max(maximum, value);
    }
    var domain: u64 = 1;
    const m: u64 = @intCast(maximum);
    while (domain <= m) domain *|= 2;
    return domain;
}

const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn parseModule(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    const owned = try alloc.dupe(u8, src);
    var lexer = Lexer.init(owned, "place_test.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    return try parser.parse_module();
}

fn censusOf(arena: *std.heap.ArenaAllocator, src: []const u8) !Census {
    const alloc = arena.allocator();
    const mod = try parseModule(alloc, src);
    for (mod.body.stmts) |*stmt| if (stmt.* == .func_decl)
        return try analyzeFunction(alloc, &stmt.func_decl.func);
    return try analyzeModule(alloc, &mod);
}

test "place: brackets are the only computed projection face" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    s[2]
        \\
    );
    defer census.deinit();
    const p = census.byName("s").?;
    try testing.expectEqual(@as(?u32, 3), p.facts.extent.upper());
    try testing.expectEqual(@as(?u64, 1), p.readCount().upperOrNull());
}

test "place: an ordinary call is not an indexed read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    s(2)
        \\
    );
    defer census.deinit();
    const p = census.byName("s").?;
    try testing.expectEqual(@as(?u64, 0), p.readCount().upperOrNull());
    try testing.expectEqual(Tri.unknown, p.facts.escape);
}

test "place: parameters, homes and function-local scalars are not places" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\global C = compiler.comptime
        \\
        \\main: i64 = (n: i64)
        \\    t = 1
        \\    k + n + t
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    // `k` IS a place: a module word `main` reads. `C` is not — its initializer
    // is a value this walk did not evaluate, and `.unknown` shape means NO ROW,
    // never a row of unknowns. The parameter `n` and the frame-local `t` are
    // not places: neither is a location a second region can name.
    try testing.expectEqual(@as(usize, 1), census.count());
    const k = census.find("k").?;
    try testing.expectEqual(Shape.scalar, k.shape);
    try testing.expect(census.find("C") == null);
    try testing.expect(census.find("n") == null);
    try testing.expect(census.find("t") == null);
}

test "place: a function-local scalar gets no row even when the same walk mints module ones" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\g: i64 = 0
        \\main: i64 = ()
        \\    local w: i64 = 2
        \\    g + w
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    try testing.expect(census.find("g") != null);
    try testing.expect(census.find("w") == null);
}

test "place: a module scalar publishes every decision fact, and mutation is two-sided" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\i: i64 = 0
        \\fixed: i64 = 7
        \\while i < 3
        \\    i = i + 1
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();

    const i = census.find("i").?;
    try testing.expectEqual(Shape.scalar, i.shape);
    try testing.expectEqual(Region.module, i.region);
    try testing.expectEqual(BindOrigin.declaration, i.bind_origin);
    try testing.expectEqual(Tri.yes, i.facts.mutation);
    try testing.expectEqual(Tri.no, i.facts.immutability);
    try testing.expectEqual(Tri.no, i.facts.alias);
    try testing.expectEqual(Tri.no, i.facts.escape);
    try testing.expectEqual(Tri.no, i.facts.contents_known);
    // The store is a WRITE, not a rebinding: see `bindOrRebind`.
    try testing.expectEqual(@as(?u64, 1), i.bindCount().upperOrNull());
    try testing.expect(i.writeCount().upperOrNull().? >= 1);

    // The other direction, in the SAME module — so the answers cannot both be
    // coming from a constant.
    const fixed = census.find("fixed").?;
    try testing.expectEqual(Tri.no, fixed.facts.mutation);
    try testing.expectEqual(Tri.yes, fixed.facts.immutability);
    try testing.expectEqual(Tri.yes, fixed.facts.contents_known);
}

test "place: a relation naming a module word makes it escape; not naming it does not" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\seen: i64 = 1
        \\hidden: i64 = 2
        \\peek: i64 = ()
        \\    seen
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    try testing.expectEqual(Tri.yes, census.find("seen").?.facts.escape);
    // Reading is not writing: the word is observed from a region whose call
    // order this module does not fix, and its value is still never stored to.
    try testing.expectEqual(Tri.no, census.find("seen").?.facts.mutation);
    try testing.expectEqual(Tri.no, census.find("hidden").?.facts.escape);
}

test "place: a relation ABOVE the binding it writes is not invisible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // THE ORDER-DEPENDENCE CONTROL. `walkForeignBody` visits `poke` before `x`
    // exists, and drops the write. Without `ForeignReach` this publishes
    // `mutation:"no"` on a word a relation stores to — a wrong answer, not a
    // missing one.
    const mod = try parseModule(alloc,
        \\poke: i64 = ()
        \\    x = 5
        \\    x
        \\x: i64 = 0
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    const x = census.find("x").?;
    try testing.expectEqual(Tri.yes, x.facts.mutation);
    try testing.expectEqual(Tri.no, x.facts.immutability);
    try testing.expectEqual(Tri.yes, x.facts.escape);
}

test "place: a refused construct reaches scalars bound after it, not only before" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\before: i64 = 1
        \\z = fun(q) q
        \\after: i64 = 2
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    for ([_][]const u8{ "before", "after" }) |n| {
        const p = census.find(n).?;
        try testing.expectEqual(Tri.unknown, p.facts.escape);
        try testing.expectEqual(Tri.unknown, p.facts.alias);
        try testing.expectEqual(Tri.unknown, p.facts.mutation);
        try testing.expectEqual(Tri.unknown, p.facts.immutability);
        try testing.expectEqual(Tri.unknown, p.facts.contents_known);
    }
}

test "place: a scalar copy is not an alias, and a scalar read is not an escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\a: i64 = 4
        \\c: i64 = a
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    const a = census.find("a").?;
    try testing.expectEqual(Tri.no, a.facts.alias);
    try testing.expectEqual(Tri.no, a.facts.escape);
    // `c` copied a value this walk did not fold, so its CONTENTS are unknown
    // while its location facts are not. Two different questions, two answers.
    const c = census.find("c").?;
    try testing.expectEqual(Tri.unknown, c.facts.contents_known);
    try testing.expectEqual(Tri.no, c.facts.alias);
}

test "place: a bare module assignment is a place whose origin is assignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\q = 5
        \\r: i64 = 6
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    try testing.expectEqual(BindOrigin.assignment, census.find("q").?.bind_origin);
    try testing.expectEqual(BindOrigin.declaration, census.find("r").?.bind_origin);
}

test "place: a string is not a scalar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\s: str = "hi"
        \\n: i64 = 1
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    try testing.expect(census.find("s") == null);
    try testing.expect(census.find("n") != null);
}

test "place: indexed reads retain loop multiplicity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    i = 0
        \\    while i < 1000
        \\        h += s[1]
        \\        i += 1
        \\    h & 255
        \\
    );
    defer census.deinit();
    const p = census.byName("s").?;
    try testing.expectEqual(@as(?u64, 1000), p.readCount().upperOrNull());
}

test "place: alias and escape remain separate negative facts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var alias_census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    t = s
        \\    s[1]
        \\
    );
    defer alias_census.deinit();
    const aliased = alias_census.byName("s").?;
    try testing.expectEqual(Tri.unknown, aliased.facts.alias);
    try testing.expectEqual(Tri.no, aliased.facts.escape);

    var escape_census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    sink(s)
        \\    s[1]
        \\
    );
    defer escape_census.deinit();
    const escaped = escape_census.byName("s").?;
    try testing.expectEqual(Tri.no, escaped.facts.alias);
    try testing.expectEqual(Tri.unknown, escaped.facts.escape);
}

test "place: a module collection written by a relation requires storage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global t = (10, 20, 30)
        \\
        \\poke: i64 = ()
        \\    t[1] = 5
        \\    0
        \\
        \\main: i64 = ()
        \\    t[2]
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    const p = census.byName("t").?;
    try testing.expectEqual(Tri.yes, p.facts.mutation);
    try testing.expectEqual(Refusal.mutated, residencyRefusal(p));
}

test "place: every unmodelled shape lowers facts to unknown" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    f = (x) x
        \\    f(s)
        \\
    );
    defer census.deinit();
    const p = census.byName("s").?;
    try testing.expectEqual(Tri.unknown, p.facts.escape);
}
