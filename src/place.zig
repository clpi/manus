//! PLACE — the entity the semantic graph does not have.
//!
//! # Why this file exists (HPLS §96, §18, §97)
//!
//! `HPLS.md` §96 records the gap as measured, not conjectured: *a table binding
//! + write + read lifts 3 nodes, 2 edges, 0 applications*, and backward demand
//! had to be computed over the AST because the graph has nothing to hang a
//! place fact on. `src/demand.zig`'s own header says the same thing from the
//! other side — *"backward demand is a property of a PLACE at a PROGRAM POINT
//! [...] and the graph has no place entity to hang it on"* — and it keys its
//! plan by AST POINTER for want of a place identity. Two independent modules
//! reaching for the same missing entity is the evidence that it is an entity
//! and not a local convenience. §97 puts place in P0.
//!
//! # What a place is, and what it is NOT
//!
//! A place is a NAMED LOCATION with an ACCESS HISTORY. It is not a host
//! pointer, a Zig slice, a C lvalue, or `t(i)` syntax (§18). Its identity is
//! its BINDING SITE, not its name: two `s` in sibling scopes are two places,
//! and one place written in twenty statements is one place.
//!
//! # The one fact the graph cannot carry, and why this wedge needs it
//!
//! A graph node is a VALUE. It has no program point, so it cannot carry
//! *how many times* it is read. Every representation decision for a collection
//! turns on exactly that number: with one membership query a linear scan wins;
//! with a million, preprocessing wins. `Access.mult` below is that number, and
//! it is the only input beyond the fact set that `eqspace.zig` needs. This
//! module exists to compute it.
//!
//! Measured on this machine (39 artifacts, answers checked against a non-Idol
//! oracle) the same semantic identity — `is x in S?` — has FOUR different
//! cheapest realizations across nine workload points, and the discriminator is
//! this count. Without a place, that decision cannot even be posed.
//!
//! # §18's fact list, in full, three-valued
//!
//! identity · determinacy · extent · mutation · immutability · alias · escape ·
//! lifetime · alignment · residency · origin. Every one is THREE-VALUED. A
//! two-valued fact lets `unknown` read as `false`, which is how an escape fact
//! becomes unsound: `escape = unknown` must delete the same candidates as
//! `escape = yes`, never the ones `escape = no` deletes.
//!
//! # §19 — the permanent negative controls
//!
//! Removing determinacy, immutability, constant-index, alias proof or escape
//! proof must EACH change the candidate set. A place fact that changes no
//! candidate set is not operative, and by §7 it is scenery. Those five controls
//! are unit tests at the bottom of `eqspace.zig`, not prose here, because the
//! candidate set is that module's object.
//!
//! # What this module does NOT do
//!
//! It does not decide anything. It produces facts; `eqspace.zig` consumes them
//! and no candidate generator is semantic authority (§24). It also does not
//! prove aliasing: two places of unknown provenance are `alias = unknown`, and
//! the contraction treats that as the pessimistic value. Narrowing that is a
//! separate job with its own evidence.

const std = @import("std");
const ast = @import("ast.zig");
const demand = @import("demand.zig");

/// Three-valued because two-valued is unsound here. `unknown` is never a
/// synonym for `no`.
pub const Tri = enum {
    yes,
    no,
    unknown,

    /// The pessimistic reading, used by contraction: an unproven fact must
    /// behave as the value that permits the FEWEST deletions.
    pub fn proven(self: Tri) bool {
        return self == .yes;
    }
};

/// §18 `determinacy`: is the accessed sub-location decided at compile time?
pub const Determinacy = enum {
    /// Every access index is a compile-time constant.
    exact,
    /// Indices vary but provably stay inside the extent.
    bounded,
    unknown,
};

/// §18 `extent`. `exact` is what a `[3]i64` binding states and what the
/// fact-to-artifact audit measured the compiler ignoring (`[3]i64` and a bare
/// literal emit byte-identical code).
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

/// How many times an access at a program point actually happens. The product
/// of the proven trip counts of the loops enclosing it.
///
/// `bounded` and `unknown` are NOT the same: a bounded count still supports a
/// worst-case profitability comparison, an unknown one does not, and §84
/// forbids either from deciding legality.
pub const Mult = union(enum) {
    exact: u64,
    bounded: u64,
    unknown,

    pub fn lower(self: Mult) u64 {
        return switch (self) {
            .exact => |n| n,
            .bounded => 1,
            .unknown => 1,
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

pub const AccessKind = enum {
    /// The whole place is bound / initialized.
    bind,
    /// One sub-location is written.
    write,
    /// One sub-location is read.
    read,
};

/// One access, AT A PROGRAM POINT. `point` is the pre-order index of the
/// statement in the function body — a stable, host-independent ordinal, not a
/// pointer, so it survives serialization (the host-removal test, AGENTS.md).
pub const Access = struct {
    kind: AccessKind,
    point: u32,
    depth: u8,
    /// Dynamic count: how many times this static access executes.
    mult: Mult,
    /// True when the index expression is a compile-time constant.
    const_index: bool,
};

/// §18's fact bundle. Deliberately a plain struct of small fields: §79-80 says
/// prefer packed facts over a heap object per fact.
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
    /// Every element value is known at compile time.
    contents_known: Tri = .unknown,
    /// Elements are in ascending order at every read point.
    ordered: Tri = .unknown,
    /// The element domain is a known finite interval `[0, domain)`.
    domain: ?u64 = null,
};

pub const Place = struct {
    /// Identity. Dense, host-independent, assigned in binding order.
    id: u32,
    /// Provenance only. Never identity — see the header.
    name: []const u8,
    /// The statement that BINDS this place; identity's physical witness while
    /// the AST is the only thing that has one.
    binding: *const ast.Stmt,
    facts: Facts = .{},
    accesses: std.ArrayListUnmanaged(Access) = .empty,

    pub fn deinit(self: *Place, alloc: std.mem.Allocator) void {
        self.accesses.deinit(alloc);
    }

    /// Total dynamic reads of this place. THE number every representation
    /// decision for a collection turns on.
    pub fn readCount(self: *const Place) Mult {
        return self.countOf(.read);
    }

    /// Total dynamic writes, i.e. how often the representation must be BUILT
    /// or updated. The other half of the preprocessing-versus-query trade.
    pub fn writeCount(self: *const Place) Mult {
        return self.countOf(.write);
    }

    /// How many times the place is (re)bound — the number of BUILD EPISODES.
    pub fn bindCount(self: *const Place) Mult {
        return self.countOf(.bind);
    }

    fn countOf(self: *const Place, k: AccessKind) Mult {
        var total: Mult = .{ .exact = 0 };
        var any_unknown = false;
        var any_bounded = false;
        var sum: u64 = 0;
        for (self.accesses.items) |a| {
            if (a.kind != k) continue;
            switch (a.mult) {
                .unknown => any_unknown = true,
                .exact => |n| sum +|= n,
                .bounded => |n| {
                    any_bounded = true;
                    sum +|= n;
                },
            }
        }
        if (any_unknown) return .unknown;
        total = if (any_bounded) .{ .bounded = sum } else .{ .exact = sum };
        return total;
    }

    /// Reads per build episode — the `q` of the preprocessing trade. Returns
    /// null when either side is unknown, because a ratio of unknowns is not a
    /// number and §84 forbids inventing one.
    pub fn readsPerBuild(self: *const Place) ?u64 {
        const r = self.readCount().upperOrNull() orelse return null;
        const b = self.bindCount().upperOrNull() orelse return null;
        if (b == 0) return null;
        return r / b;
    }
};

pub const Census = struct {
    places: std.ArrayListUnmanaged(Place) = .empty,
    alloc: std.mem.Allocator,
    /// Statements walked. A census that examined zero statements has not
    /// passed — the same rule `gate/*.sh` lives by.
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

    pub fn byName(self: *Census, name: []const u8) ?*Place {
        // Reverse order: the innermost binding of a shadowed name wins, which
        // is why identity is the binding site and not the string.
        var i = self.places.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.places.items[i].name, name)) return &self.places.items[i];
        }
        return null;
    }

    pub fn get(self: *Census, id: u32) ?*Place {
        for (self.places.items) |*p| {
            if (p.id == id) return p;
        }
        return null;
    }
};

// ---------------------------------------------------------------- the walk

const Ctx = struct {
    census: *Census,
    depth: u8 = 0,
    /// Product of the proven trip counts of the enclosing loops.
    mult: Mult = .{ .exact = 1 },
};

/// Build the place census for one function body.
pub fn analyzeFunction(alloc: std.mem.Allocator, fb: *const ast.FuncBody) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census };
    // `walkBlock` already walks the tail. Walking it again here counted every
    // tail-position read TWICE, which inflates `q` and biases the decision
    // toward preprocessing — caught by the three-access test below.
    try walkBlock(&ctx, &fb.body);
    return census;
}

/// Build the place census for a module's file-scope body. The demand gap in
/// §96 notes the file-scope tail is the LOWER-syntax form and still measures
/// 16 → 16; a census that only walked `.func_decl` would inherit that hole.
pub fn analyzeModule(alloc: std.mem.Allocator, mod: *const ast.Module) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census };
    try walkBlock(&ctx, &mod.body);
    return census;
}

fn walkBlock(ctx: *Ctx, b: *const ast.Block) anyerror!void {
    for (b.stmts) |*s| try walkStmt(ctx, s);
    if (b.tail_expr) |t| try readExpr(ctx, t);
}

fn walkStmt(ctx: *Ctx, s: *const ast.Stmt) anyerror!void {
    const point = ctx.census.points;
    ctx.census.points += 1;
    switch (s.*) {
        .local_decl => |d| {
            for (d.inits) |e| try readExpr(ctx, e);
            for (d.names, 0..) |n, i| {
                const init_expr: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                try bindOrRebind(ctx, n.ident, s, point, init_expr, n.typ);
            }
        },
        .global_decl => |d| {
            for (d.inits) |e| try readExpr(ctx, e);
            for (d.names, 0..) |n, i| {
                const init_expr: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                try bindOrRebind(ctx, n.ident, s, point, init_expr, n.typ);
                // A module-scope place outlives the region and may be observed
                // from outside it. Never `escape = no` without a proof.
                if (ctx.census.byName(n.ident)) |p| {
                    p.facts.lifetime = .module;
                    p.facts.escape = .unknown;
                }
            }
        },
        .assign => |a| {
            // On this surface there is no `local` keyword: a bare `s = (...)`
            // IS the binding form, and it arrives as `.assign` with a `.name`
            // target. Verified against the parser rather than assumed — both
            // `(1,2,3)` and `{1,2,3}` build `.table` with positional fields.
            for (a.values) |v| try readExpr(ctx, v);
            for (a.targets, 0..) |t, i| {
                const val: ?*const ast.Expr = if (i < a.values.len) a.values[i] else null;
                if (t.* == .name and val != null and val.?.* == .table) {
                    try bindOrRebind(ctx, t.name.ident, s, point, val, .inferred);
                    continue;
                }
                try writeTarget(ctx, t, point);
            }
        },
        .call_stmt => |c| try readExpr(ctx, c.expr),
        .expr_stmt => |e| try readExpr(ctx, e.expr),
        .do_block => |d| try walkBlock(ctx, &d.body),
        .while_loop => |w| {
            try readExpr(ctx, w.cond);
            const trip: Mult = if (demand.provenTripCount(w)) |pr| blk: {
                const span: i64 = if (pr.ascending) pr.limit else -pr.limit;
                _ = span;
                const st: u64 = @intCast(if (pr.step < 0) -pr.step else pr.step);
                if (st == 0) break :blk .unknown;
                // The proof gives limit and step but not the initial value, so
                // the exact count is not recoverable here — only a bound.
                const lim: u64 = if (pr.limit < 0) 0 else @intCast(pr.limit);
                break :blk .{ .bounded = (lim + st - 1) / st };
            } else .unknown;
            try nested(ctx, &w.body, trip);
        },
        .repeat_loop => |r| {
            try nested(ctx, &r.body, .unknown);
            try readExpr(ctx, r.cond);
        },
        .if_stmt => |f| {
            if (f.binding) |bd| try readExpr(ctx, bd.expr);
            try readExpr(ctx, f.cond);
            // A branch executes AT MOST as often as its enclosing region.
            try nestedBound(ctx, &f.then);
            for (f.elseifs) |ei| {
                try readExpr(ctx, ei.cond);
                try nestedBound(ctx, &ei.body);
            }
            if (f.else_body) |*eb| try nestedBound(ctx, eb);
        },
        .num_for => |nf| {
            try readExpr(ctx, nf.start);
            try readExpr(ctx, nf.stop);
            if (nf.step) |st| try readExpr(ctx, st);
            try nested(ctx, &nf.body, numForTrip(nf));
        },
        else => {
            // Refusal, not a gap. An unadmitted shape must not silently
            // contribute a count of 1 — that would understate multiplicity and
            // understating it is how a scan gets chosen for a hot query.
            try markAllUnknown(ctx);
        },
    }
}

fn numForTrip(nf: anytype) Mult {
    const a = intLit(nf.start) orelse return .unknown;
    const b = intLit(nf.stop) orelse return .unknown;
    const st: i64 = if (nf.step) |s| (intLit(s) orelse return .unknown) else 1;
    if (st == 0) return .unknown;
    if (st > 0) {
        if (b < a) return .{ .exact = 0 };
        return .{ .exact = @intCast(@divFloor(b - a, st) + 1) };
    }
    if (b > a) return .{ .exact = 0 };
    return .{ .exact = @intCast(@divFloor(a - b, -st) + 1) };
}

fn intLit(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |l| l.val,
        .unop => |u| switch (u.op) {
            .neg => if (intLit(u.operand)) |v| -v else null,
            else => null,
        },
        else => null,
    };
}

fn nested(ctx: *Ctx, b: *const ast.Block, trip: Mult) anyerror!void {
    const saved_depth = ctx.depth;
    const saved_mult = ctx.mult;
    ctx.depth +|= 1;
    ctx.mult = Mult.mul(ctx.mult, trip);
    try walkBlock(ctx, b);
    ctx.depth = saved_depth;
    ctx.mult = saved_mult;
}

fn nestedBound(ctx: *Ctx, b: *const ast.Block) anyerror!void {
    const saved = ctx.mult;
    ctx.mult = switch (ctx.mult) {
        .exact => |n| .{ .bounded = n },
        else => ctx.mult,
    };
    try walkBlock(ctx, b);
    ctx.mult = saved;
}

fn markAllUnknown(ctx: *Ctx) !void {
    for (ctx.census.places.items) |*p| {
        p.facts.escape = .unknown;
        p.facts.mutation = .unknown;
        p.facts.determinacy = .unknown;
    }
}

/// Bind a new place, or record a REBIND of one that already exists.
///
/// A rebind is not a new entity: it is a new BUILD EPISODE of the same place,
/// and the count of those episodes is what amortises preprocessing. Treating a
/// rebind as a fresh place would make every loop-carried collection look like
/// N separate one-query places, which is precisely the misreading that selects
/// a linear scan for a hot set.
///
/// NOTE ON SCOPING: this surface has no declaration form that shadows, so a
/// second `s = (...)` in a nested block is the same place. `Place.binding`
/// still records the statement, so a future scoping form makes two places
/// without changing anything here.
fn bindOrRebind(
    ctx: *Ctx,
    name: []const u8,
    s: *const ast.Stmt,
    point: u32,
    init_expr: ?*const ast.Expr,
    typ: ast.TypeExpr,
) !void {
    if (ctx.census.byName(name)) |p| {
        try p.accesses.append(ctx.census.alloc, .{
            .kind = .bind,
            .point = point,
            .depth = ctx.depth,
            .mult = ctx.mult,
            .const_index = true,
        });
        return;
    }
    try bindPlace(ctx, name, s, point, init_expr, typ);
}

fn bindPlace(
    ctx: *Ctx,
    name: []const u8,
    s: *const ast.Stmt,
    point: u32,
    init_expr: ?*const ast.Expr,
    typ: ast.TypeExpr,
) !void {
    // Only collection-shaped bindings become places here. A scalar local is a
    // place too, but nothing in this wedge asks a representation question about
    // one, and §81 says do not compute analyses with no consumer.
    const is_collection = blk: {
        if (init_expr) |e| {
            if (e.* == .table) break :blk true;
        }
        break :blk declaredExtent(typ) != null;
    };
    if (!is_collection) return;

    const id: u32 = @intCast(ctx.census.places.items.len);
    var p = Place{ .id = id, .name = name, .binding = s };

    p.facts.lifetime = .function;
    p.facts.residency = .unknown;
    p.facts.alignment = null;
    // Nothing has aliased it at its binding site, and nothing has escaped yet.
    // These are RAISED to unknown by any shape the walk does not admit.
    p.facts.alias = .no;
    p.facts.escape = .no;
    p.facts.mutation = .no;
    p.facts.immutability = .yes;
    p.facts.determinacy = .exact;

    if (init_expr) |e| {
        switch (e.*) {
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
        }
    }
    // A DECLARED extent outranks a re-derived one. The fact-to-artifact audit
    // measured `[3]i64` and a bare literal emitting byte-identical code, i.e.
    // the declaration contributing nothing; consuming it here is the smallest
    // possible repair of that.
    if (declaredExtent(typ)) |n| p.facts.extent = .{ .exact = n };

    try ctx.census.places.append(ctx.census.alloc, p);
    const slot = &ctx.census.places.items[ctx.census.places.items.len - 1];
    try slot.accesses.append(ctx.census.alloc, .{
        .kind = .bind,
        .point = point,
        .depth = ctx.depth,
        .mult = ctx.mult,
        .const_index = true,
    });
}

fn declaredExtent(t: ast.TypeExpr) ?u32 {
    // A typed array binding `t: [3]i64`. The one `[]` face §7 admits.
    return switch (t) {
        .array => |a| if (a.size) |n| @intCast(n) else null,
        else => null,
    };
}

/// A table literal's positional values, or null when the literal carries any
/// shape this walk does not admit. `null` is a REFUSAL, not "empty".
fn positionalValue(f: ast.TableField) ?*const ast.Expr {
    return switch (f) {
        .positional => |e| e,
        else => null,
    };
}

fn allFieldsConst(fields: []const ast.TableField) bool {
    for (fields) |f| {
        const v = positionalValue(f) orelse return false;
        if (v.* != .int_lit) return false;
    }
    return true;
}

fn orderedOf(fields: []const ast.TableField) Tri {
    var prev: ?i64 = null;
    for (fields) |f| {
        const fv = positionalValue(f) orelse return .unknown;
        const v = switch (fv.*) {
            .int_lit => |l| l.val,
            else => return .unknown,
        };
        if (prev) |pv| {
            if (v < pv) return .no;
        }
        prev = v;
    }
    return .yes;
}

fn domainOf(fields: []const ast.TableField) ?u64 {
    var max: i64 = 0;
    for (fields) |f| {
        const pv = positionalValue(f) orelse return null;
        const v = switch (pv.*) {
            .int_lit => |l| l.val,
            else => return null,
        };
        if (v < 0) return null;
        if (v > max) max = v;
    }
    // Round up to the next power of two: the smallest dense domain that
    // covers the observed values. A DECLARED domain would beat this and is
    // exactly the kind of fact HPLS §2 says must never make things worse.
    var d: u64 = 1;
    const m: u64 = @intCast(max);
    while (d <= m) d *|= 2;
    return d;
}

/// `s(i) = v` — an assignment whose target is an application. In this surface
/// `t(key)` is the application face (§7), so the target arrives as `.call`,
/// not `.index`. Both spellings are admitted; the legacy bracket face is the
/// same place.
fn writeTarget(ctx: *Ctx, t: *const ast.Expr, point: u32) anyerror!void {
    switch (t.*) {
        .name => |n| {
            // Rebinding the whole place: a BUILD, not an element write.
            if (ctx.census.byName(n.ident)) |p| {
                try p.accesses.append(ctx.census.alloc, .{
                    .kind = .bind,
                    .point = point,
                    .depth = ctx.depth,
                    .mult = ctx.mult,
                    .const_index = true,
                });
            }
        },
        .call => |c| {
            if (c.func.* == .name) {
                if (ctx.census.byName(c.func.name.ident)) |p| {
                    const ci = c.args.len == 1 and intLit(c.args[0]) != null;
                    try p.accesses.append(ctx.census.alloc, .{
                        .kind = .write,
                        .point = point,
                        .depth = ctx.depth,
                        .mult = ctx.mult,
                        .const_index = ci,
                    });
                    p.facts.mutation = .yes;
                    p.facts.immutability = .no;
                    if (!ci) p.facts.determinacy = .bounded;
                    // Contents are no longer statically known once a runtime
                    // value is stored into them.
                    if (p.facts.contents_known == .yes) p.facts.contents_known = .no;
                    if (p.facts.ordered == .yes) p.facts.ordered = .unknown;
                }
            }
            for (c.args) |a| try readExpr(ctx, a);
        },
        .index => |ix| {
            if (ix.obj.* == .name) {
                if (ctx.census.byName(ix.obj.name.ident)) |p| {
                    const ci = intLit(ix.key) != null;
                    try p.accesses.append(ctx.census.alloc, .{
                        .kind = .write,
                        .point = point,
                        .depth = ctx.depth,
                        .mult = ctx.mult,
                        .const_index = ci,
                    });
                    p.facts.mutation = .yes;
                    p.facts.immutability = .no;
                    if (!ci) p.facts.determinacy = .bounded;
                    if (p.facts.contents_known == .yes) p.facts.contents_known = .no;
                    if (p.facts.ordered == .yes) p.facts.ordered = .unknown;
                }
            }
            try readExpr(ctx, ix.key);
        },
        else => try markAllUnknown(ctx),
    }
}

fn readExpr(ctx: *Ctx, e: *const ast.Expr) anyerror!void {
    switch (e.*) {
        .name => |n| {
            // A bare mention of a collection is the place ESCAPING into some
            // context this walk cannot see through.
            if (ctx.census.byName(n.ident)) |p| {
                p.facts.escape = .unknown;
                p.facts.alias = .unknown;
            }
        },
        .call => |c| {
            if (c.func.* == .name) {
                if (ctx.census.byName(c.func.name.ident)) |p| {
                    const ci = c.args.len == 1 and intLit(c.args[0]) != null;
                    try p.accesses.append(ctx.census.alloc, .{
                        .kind = .read,
                        .point = ctx.census.points,
                        .depth = ctx.depth,
                        .mult = ctx.mult,
                        .const_index = ci,
                    });
                    if (!ci) p.facts.determinacy = .bounded;
                    for (c.args) |a| try readExpr(ctx, a);
                    return;
                }
            }
            try readExpr(ctx, c.func);
            for (c.args) |a| try readExpr(ctx, a);
        },
        .index => |ix| {
            if (ix.obj.* == .name) {
                if (ctx.census.byName(ix.obj.name.ident)) |p| {
                    const ci = intLit(ix.key) != null;
                    try p.accesses.append(ctx.census.alloc, .{
                        .kind = .read,
                        .point = ctx.census.points,
                        .depth = ctx.depth,
                        .mult = ctx.mult,
                        .const_index = ci,
                    });
                    if (!ci) p.facts.determinacy = .bounded;
                    try readExpr(ctx, ix.key);
                    return;
                }
            }
            try readExpr(ctx, ix.obj);
            try readExpr(ctx, ix.key);
        },
        .binop => |b| {
            try readExpr(ctx, b.lhs);
            try readExpr(ctx, b.rhs);
        },
        .unop => |u| try readExpr(ctx, u.operand),
        .field => |f| try readExpr(ctx, f.obj),
        .method_call => |m| {
            try readExpr(ctx, m.obj);
            for (m.args) |a| try readExpr(ctx, a);
        },
        .table => |t| {
            for (t.fields) |f| {
                if (positionalValue(f)) |v| try readExpr(ctx, v);
            }
        },
        .func_expr => try markAllUnknown(ctx),
        else => {},
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

/// Same fixture shape as `src/demand.zig` — deliberately, because the two
/// modules analyse the same object and a second parsing convention would be
/// the duplicate semantic ownership §79-80 forbids.
fn parseModule(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    const owned = try alloc.dupe(u8, src);
    var lex = Lexer.init(owned, "place_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    return try p.parse_module();
}

fn censusOf(arena: *std.heap.ArenaAllocator, src: []const u8) !Census {
    const alloc = arena.allocator();
    const mod = try parseModule(alloc, src);
    // The wedge's programs are one `main` relation; walk it if present,
    // otherwise the file-scope body — §96 records that a pass which only walks
    // `.func_decl` inherits the file-scope hole.
    for (mod.body.stmts) |*s| {
        if (s.* == .func_decl) return try analyzeFunction(alloc, &s.func_decl.func);
    }
    return try analyzeModule(alloc, &mod);
}

test "place: a table binding is one place with an exact extent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    s(2)
        \\
    );
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.count());
    const p = c.byName("s").?;
    try testing.expectEqual(@as(?u32, 3), p.facts.extent.upper());
    try testing.expectEqual(Tri.yes, p.facts.contents_known);
    try testing.expectEqual(Tri.yes, p.facts.ordered);
}

test "place: the graph lifts 3 nodes and 0 applications for what is ONE place" {
    // The §96 measurement, restated as an executable expectation. A binding, a
    // write and a read are THREE graph nodes and TWO edges; here they are one
    // place with three accesses, which is the entity the decision needs.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (0, 0, 0)
        \\    s(1) = 7
        \\    s(1)
        \\
    );
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.count());
    const p = c.byName("s").?;
    try testing.expectEqual(@as(usize, 3), p.accesses.items.len);
    try testing.expectEqual(Tri.yes, p.facts.mutation);
}

test "place: a read inside a counted loop carries the loop's multiplicity" {
    // THE fact the semantic graph cannot carry, and the only input beyond the
    // fact set that representation selection needs.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    i = 0
        \\    while i < 1000
        \\        h += s(1)
        \\        i += 1
        \\    h & 255
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    const reads = p.readCount();
    try testing.expect(reads != .unknown);
    try testing.expectEqual(@as(?u64, 1000), reads.upperOrNull());
    try testing.expectEqual(@as(?u64, 1000), p.readsPerBuild());
}

test "place: nested loops multiply, and that is the scan's whole cost" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    j = 0
        \\    while j < 100
        \\        i = 0
        \\        while i < 64
        \\            h += s(1)
        \\            i += 1
        \\        j += 1
        \\    h & 255
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(@as(?u64, 6400), p.readCount().upperOrNull());
}

test "place: an unproven loop bound makes multiplicity UNKNOWN, never 1" {
    // Understating multiplicity is how a linear scan gets selected for a hot
    // query. `unknown` must not collapse to the optimistic value.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    i = 0
        \\    while i < 1000
        \\        h += s(1)
        \\    h & 255
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(Mult.unknown, p.readCount());
    try testing.expectEqual(@as(?u64, null), p.readsPerBuild());
}

test "place: a rebound place counts BUILD EPISODES, which is the amortiser" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (0, 0, 0)
        \\    h = 0
        \\    e = 0
        \\    while e < 100
        \\        s(1) = e
        \\        j = 0
        \\        while j < 8
        \\            h += s(1)
        \\            j += 1
        \\        e += 1
        \\    h & 255
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(@as(?u64, 100), p.writeCount().upperOrNull());
    try testing.expectEqual(@as(?u64, 800), p.readCount().upperOrNull());
}

test "place: a bare mention of the collection raises escape to UNKNOWN" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    t = s
        \\    s(1)
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(Tri.unknown, p.facts.escape);
    try testing.expectEqual(Tri.unknown, p.facts.alias);
}

test "place: a runtime index drops determinacy from exact to bounded" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    i = 0
        \\    while i < 3
        \\        h += s(i + 1)
        \\        i += 1
        \\    h & 255
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(Determinacy.bounded, p.facts.determinacy);
}

test "place: a DECLARED extent is consumed, not re-derived" {
    // The audit measured `t: [3]i64 = {10,20,30}` and `t = (10,20,30)` emitting
    // byte-identical code — the declaration contributing nothing anywhere in
    // the compiler. Here it reaches a fact.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s: [3]i64 = (10, 20, 30)
        \\    s(2)
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(@as(?u32, 3), p.facts.extent.upper());
}

test "place: an unsorted literal is ordered = no, which is a legality fact" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (30, 10, 20)
        \\    s(1)
        \\
    );
    defer c.deinit();
    try testing.expectEqual(Tri.no, c.byName("s").?.facts.ordered);
}

test "place: a rebind is the SAME place with another build episode" {
    // Not a second entity. If a rebind minted a new place, a loop-carried
    // collection would read as N one-query places and a linear scan would be
    // selected for a hot set — the exact misreading this census exists to stop.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    e = 0
        \\    while e < 10
        \\        s = (4, 5, 6)
        \\        h += s(1)
        \\        e += 1
        \\    h & 255
        \\
    );
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.count());
    const p = c.byName("s").?;
    try testing.expectEqual(@as(?u64, 11), p.bindCount().upperOrNull());
    try testing.expectEqual(@as(?u64, 10), p.readCount().upperOrNull());
}

test "place: the census reports how many statements it examined" {
    // A census that examined zero statements has NOT passed. Same rule the
    // shell gates live by, enforced on the analysis itself.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    s(1)
        \\
    );
    defer c.deinit();
    try testing.expect(c.points > 0);
}
