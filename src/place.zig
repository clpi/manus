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

/// Three-valued reference into one census's NAME-BINDING space, spelled
/// separately from `Site` because the two spaces are different spaces. A place
/// id and a binding id can both be 0 in the same census and mean different
/// things, so a value of one type is never assignable to the other.
pub const BindingSite = union(enum) {
    unknown,
    none,
    one: u32,

    pub fn name(self: BindingSite) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
    }
};

/// One name binding, whether or not it is a place. `bindPlace` declines every
/// scalar (SCALARS ARE NOT PLACES, established by f5857e0a); a consumer that
/// needs to name a scalar subject needs THIS row, not a place row.
pub const Binding = struct {
    id: u32,
    name: []const u8,
    stmt: *const ast.Stmt,
    point: u32,
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
/// Only `collection` and `record` are produced. The retired members remain so
/// old exhaustive switches fail closed rather than acquiring a new meaning.
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
    /// Every name bound in this relation, in binding order. A superset of
    /// `places` by construction: `bindPlace` declines scalars, `noteBinding`
    /// declines nothing.
    bindings: std.ArrayListUnmanaged(Binding) = .empty,
    alloc: std.mem.Allocator,
    points: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Census {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Census) void {
        for (self.places.items) |*p| p.deinit(self.alloc);
        self.places.deinit(self.alloc);
        self.bindings.deinit(self.alloc);
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

    pub fn bindingCount(self: *const Census) usize {
        return self.bindings.items.len;
    }

    /// Backward search, exactly as `find`: the most recent binding of a name
    /// is the one in scope.
    pub fn findBinding(self: *const Census, name: []const u8) ?*const Binding {
        var i = self.bindings.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.bindings.items[i].name, name)) return &self.bindings.items[i];
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

const Ctx = struct {
    census: *Census,
    depth: u8 = 0,
    mult: Mult = .{ .exact = 1 },
    region: Region = .function,
    foreign: bool = false,
    shadow: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Ctx) void {
        self.shadow.deinit(self.census.alloc);
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
    var ctx = Ctx{ .census = &census, .region = .module };
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
    for (ctx.census.places.items) |*p| {
        p.facts.escape = .unknown;
        p.facts.alias = .unknown;
        p.facts.mutation = .unknown;
        p.facts.immutability = .unknown;
        p.facts.determinacy = .unknown;
    }
}

const BindMode = enum { declaration, assignment };

fn bindOrRebind(
    ctx: *Ctx,
    name: []const u8,
    stmt: *const ast.Stmt,
    point: u32,
    init: ?*const ast.Expr,
    typ: ast.TypeExpr,
    mode: BindMode,
) !void {
    try noteBinding(ctx, name, stmt, point);
    if (ctx.lookup(name)) |p| {
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
    try bindPlace(ctx, name, stmt, point, init, typ);
}

/// Record a name binding once per name. A rebind of a name already bound is
/// the same binding, exactly as a rebind of a place is the same place.
fn noteBinding(ctx: *Ctx, name: []const u8, stmt: *const ast.Stmt, point: u32) !void {
    if (ctx.census.findBinding(name) != null) return;
    try ctx.census.bindings.append(ctx.census.alloc, .{
        .id = @intCast(ctx.census.bindings.items.len),
        .name = name,
        .stmt = stmt,
        .point = point,
    });
}

fn candidateShape(init: ?*const ast.Expr, typ: ast.TypeExpr) Shape {
    if (declaredExtent(typ) != null) return .collection;
    const e = init orelse return .unknown;
    return switch (e.*) {
        .table => |t| blk: {
            for (t.fields) |field| switch (field) {
                .named, .indexed, .semantic => break :blk .record,
                else => {},
            };
            break :blk .collection;
        },
        else => .unknown,
    };
}

fn bindPlace(
    ctx: *Ctx,
    name: []const u8,
    stmt: *const ast.Stmt,
    point: u32,
    init: ?*const ast.Expr,
    typ: ast.TypeExpr,
) !void {
    const shape = candidateShape(init, typ);
    if (shape == .unknown) return;

    var p = Place{
        .id = @intCast(ctx.census.places.items.len),
        .name = name,
        .binding = stmt,
        .shape = shape,
        .region = ctx.region,
        .init = init,
    };
    p.facts.lifetime = if (ctx.region == .module) .module else .function;
    p.facts.alias = .no;
    p.facts.escape = .no;
    p.facts.mutation = .no;
    p.facts.immutability = .yes;
    p.facts.determinacy = .exact;

    if (init) |e| switch (e.*) {
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
                @constCast(p).facts.escape = .unknown;
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

test "place: scalar values, parameters and homes are not places" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\global C = compiler.comptime
        \\
        \\main: i64 = (n: i64)
        \\    k + n
        \\
    );
    var census = try analyzeModule(alloc, &mod);
    defer census.deinit();
    try testing.expectEqual(@as(usize, 0), census.count());
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
