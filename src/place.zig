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

/// Three-valued reference INTO one census's place space.
///
/// `Card`'s discipline (`semantic_graph.zig`), spelled here so a place id can
/// never be read as a graph entity id: `null` may not stand in for any of the
/// three, and "no place is constrained" (`.none`) is a different answer from
/// "which place is constrained was not determined" (`.unknown`).
pub const Site = union(enum) {
    unknown,
    none,
    one: u32,

    /// The union tag, spelled ONCE, for every projection of it.
    pub fn name(self: Site) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
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

/// WHAT THE NAME NAMES. The census used to admit exactly one shape — a binding
/// whose value is a `.table` LITERAL — and five independent lanes stopped at
/// that edge on the same day. Widening it is not coverage for its own sake:
/// each member below is a JUDGMENT about whether the thing is a location at
/// all, and two of the five judgments are NEGATIVE.
///
///   `.scalar`      IS a place. It has an identity, a lifetime, a residency and
///                  a mutation history; a scalar written by a relation is the
///                  one shape `moduleFunctionsAssignName` in `dnir_lower.zig`
///                  already decides by hand, name-keyed, two-valued.
///   `.collection`  IS a place. The original census member.
///   `.record`      IS a place — and its FIELDS ARE NOT. `r.f` is a
///                  SUB-LOCATION of `r` accessed at a program point with a
///                  constant sub-location, which is what `Access.const_index`
///                  already records. Minting a place per field would make
///                  `alias` unanswerable (two fields of one record alias the
///                  same storage and nothing would say so) and would multiply
///                  the census by the arity of every record for no new fact.
///   `.parameter`   IS a place, and its `origin` says so. Its extent, alias and
///                  escape facts arrive from the CALLER, so it starts pessimal
///                  rather than at `.no`.
///   `.home`        IS a place that HOLDS NO VALUE. `global C = compiler.comptime`
///                  binds a name to a HOME, not to a datum: it has no residency,
///                  no extent and no contents, and a consumer that folds a value
///                  binding must refuse it. Recording it as a place is what lets
///                  the refusal be a RULING rather than a missing switch arm —
///                  the shadow test `lib/compiler/rewrite.id:23` blocks on.
pub const Shape = enum { unknown, scalar, collection, record, parameter, home };

/// WHERE the binding site sits. Not the same question as `Lifetime`: a place
/// bound at module scope has module lifetime, but a place bound in a relation
/// body can also outlive the body (it can escape), and the two facts are
/// established by different evidence.
pub const Region = enum { function, module };

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
    /// What the name names, and therefore which questions are askable of it.
    shape: Shape = .unknown,
    /// Which region the binding site sits in.
    region: Region = .function,
    /// The initializer expression, or null. Held rather than copied: the AST
    /// already owns the values and a second copy is a second authority. For a
    /// `.home` place this is the DOTTED PATH the name holds, which is the whole
    /// content of the binding — there is no value.
    init: ?*const ast.Expr = null,
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

    /// Every access whose sub-location is NOT a compile-time constant.
    /// `Facts.determinacy` is the whole place's aggregate; this is the
    /// per-access half, and §19 names them as two separate controls because
    /// they are: a place with one runtime index somewhere is `.bounded` for
    /// EVERY access, while one particular access can still be constant.
    pub fn anyRuntimeIndex(self: *const Place) bool {
        for (self.accesses.items) |a| {
            if (!a.const_index) return true;
        }
        return false;
    }
};

/// Why a place still needs storage. One member per §19 control, plus the shape
/// and value preconditions that are not controls at all.
///
/// NAMED RATHER THAN BOOLEAN so a regression shows up as a CHANGED REASON
/// instead of as a silently identical instruction count — the rule
/// `table_facts.Blocker` already lives by, applied to places.
pub const Refusal = enum {
    /// Nothing blocks it: the place has NO RUNTIME LOCATION.
    none,
    /// Not a module-scope binding. A function-local place's storage question is
    /// the register allocator's, not this ruling's.
    not_module,
    /// A shape this ruling does not answer for — including `.home`, which holds
    /// no value to fold and must be refused as a RULING, not by omission.
    shape,
    /// The binding has no compile-time value: no initializer, or one nobody can
    /// evaluate without running the program.
    no_value,
    /// §19 IMMUTABILITY. Something writes this place after it is bound.
    mutated,
    /// The place is bound more than once, so "the initializer" is not a
    /// function of the place — it is a function of the program point.
    rebound,
    /// §19 ALIAS. Another name may denote the same location.
    aliased,
    /// §19 ESCAPE. Something outside this walk can see or change it.
    escaped,
    /// §19 DETERMINACY. Some access reaches a sub-location decided at runtime,
    /// so the aggregate must exist even if this access is constant.
    indeterminate,
    /// §19 CONSTANT INDEX. This particular access indexes at runtime.
    runtime_index,
};

/// §18 RESIDENCY, ruled rather than guessed — and §19's five controls, in the
/// order the law lists them, as five separately-named refusals.
///
/// A module-scope binding whose value nothing can write, alias, escape or index
/// at a runtime offset has NO RUNTIME LOCATION AT ALL: every read of it IS its
/// initializer, and the word it would have occupied need not exist. That is a
/// PLACE ruling and not a constant-folding trick — the fact being established
/// is `residency = .absent`, which is one of §18's eleven and which nothing in
/// this tree could previously state.
///
/// DELETE ANY ONE CLAUSE AND A CANDIDATE THE OTHER FOUR FORBID BECOMES
/// ADMISSIBLE. That is the whole of §19, and `gate/place.sh` measures it in
/// emitted machine code rather than asserting it here.
pub fn residencyRefusal(p: *const Place) Refusal {
    if (p.region != .module) return .not_module;
    switch (p.shape) {
        .scalar, .collection => {},
        // A HOME IS NOT A VALUE BINDING. This is the ruling
        // `lib/compiler/rewrite.id:23` blocks on, stated where a consumer can
        // read it: `global C = compiler.comptime` names a home, so there is no
        // datum to put in a register and no storage to elide.
        .home, .record, .parameter, .unknown => return .shape,
    }
    if (p.init == null) return .no_value;
    // §19 (2) IMMUTABILITY.
    if (p.facts.mutation != .no) return .mutated;
    if (p.facts.immutability != .yes) return .mutated;
    // A second bind makes "the value" a property of the program point.
    switch (p.bindCount()) {
        .exact => |n| if (n != 1) return .rebound,
        else => return .rebound,
    }
    // §19 (4) ALIAS — and `unknown` deletes what `yes` deletes, never what
    // `no` deletes.
    if (p.facts.alias != .no) return .aliased;
    // §19 (5) ESCAPE.
    if (p.facts.escape != .no) return .escaped;
    // §19 (1) DETERMINACY.
    if (p.facts.determinacy != .exact) return .indeterminate;
    return .none;
}

/// The residency this ruling assigns. `.absent` is the only interesting answer;
/// the others are recorded so the fact is total rather than optional.
pub fn ruledResidency(p: *const Place) Residency {
    if (residencyRefusal(p) == .none) return .absent;
    return switch (p.region) {
        .module => .static,
        .function => switch (p.shape) {
            .collection, .record => .frame,
            else => .register,
        },
    };
}

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

    /// How many places of one shape. The unqualified `count` stopped being the
    /// interesting number when the census widened past collections.
    pub fn countOfShape(self: *const Census, s: Shape) usize {
        var n: usize = 0;
        for (self.places.items) |p| {
            if (p.shape == s) n += 1;
        }
        return n;
    }

    /// The lookup, const. ONE rule for which binding of a shadowed name wins:
    /// reverse order, so the innermost wins — which is why identity is the
    /// binding site and not the string.
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
    /// Which region the walk is CURRENTLY in — not where it started. Module
    /// scope binds places; a relation body reached from module scope only
    /// ACCESSES them.
    region: Region = .function,
    /// True while walking a relation body from module scope. A binding here is
    /// not a new module place, and an assignment here is a WRITE THROUGH the
    /// module place from outside its own region.
    foreign: bool = false,
    /// Names a relation body has taken for itself — parameters, declarations,
    /// loop variables. A module place of the same name is INVISIBLE for the
    /// rest of that body, exactly as `dnir_lower.stmtsAssignName` already
    /// rules: a write to a shadow is not a write to the global.
    shadow: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Ctx) void {
        self.shadow.deinit(self.census.alloc);
    }

    /// The place a name denotes HERE. Never `Census.byName` directly from the
    /// walk: that would read through a shadow.
    fn lookup(self: *Ctx, name: []const u8) ?*Place {
        for (self.shadow.items) |s| {
            if (std.mem.eql(u8, s, name)) return null;
        }
        return self.census.byName(name);
    }

    fn shadowName(self: *Ctx, name: []const u8) !void {
        try self.shadow.append(self.census.alloc, name);
    }
};

/// Build the place census for one function body.
pub fn analyzeFunction(alloc: std.mem.Allocator, fb: *const ast.FuncBody) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census };
    defer ctx.deinit();
    // A PARAMETER IS A PLACE, and it is the one place whose facts arrive from
    // outside: its extent, alias and escape are the caller's to state, so it
    // starts pessimal rather than at the `.no` a local binding earns.
    for (fb.params) |param| try bindParam(&ctx, param.name);
    // `walkBlock` already walks the tail. Walking it again here counted every
    // tail-position read TWICE, which inflates `q` and biases the decision
    // toward preprocessing — caught by the three-access test below.
    try walkBlock(&ctx, &fb.body);
    return census;
}

/// Build the place census for a module's file-scope body. The demand gap in
/// §96 notes the file-scope tail is the LOWER-syntax form and still measures
/// 16 → 16; a census that only walked `.func_decl` would inherit that hole.
///
/// TWO REGIONS, ONE CENSUS. Module-scope statements BIND; relation bodies are
/// then walked as FOREIGN regions that can only access what module scope bound.
/// Before this, a `.func_decl` fell to the refusal arm and marked every module
/// place unknown, so a module containing any relation at all had no usable
/// place facts — which is to say, every real module.
pub fn analyzeModule(alloc: std.mem.Allocator, mod: *const ast.Module) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census, .region = .module };
    defer ctx.deinit();
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
            for (d.inits) |e| {
                if (try aliasInit(ctx, e)) continue;
                try readExpr(ctx, e);
            }
            for (d.names, 0..) |n, i| {
                const init_expr: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                // A DECLARATION inside a relation body TAKES THE NAME. It is
                // not a write to the module place that name used to denote.
                if (ctx.foreign) {
                    try ctx.shadowName(n.ident);
                    continue;
                }
                try bindOrRebind(ctx, n.ident, s, point, init_expr, n.typ, .declaration);
            }
        },
        .const_decl => |d| {
            try readExpr(ctx, d.val);
            if (ctx.foreign) {
                try ctx.shadowName(d.ident);
            } else {
                try bindOrRebind(ctx, d.ident, s, point, d.val, d.typ, .declaration);
            }
        },
        .global_decl => |d| {
            for (d.inits) |e| {
                if (try aliasInit(ctx, e)) continue;
                try readExpr(ctx, e);
            }
            for (d.names, 0..) |n, i| {
                const init_expr: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                if (ctx.foreign) {
                    // `global x = …` INSIDE a relation writes the shared word.
                    try bindOrRebind(ctx, n.ident, s, point, init_expr, n.typ, .assignment);
                    continue;
                }
                try bindOrRebind(ctx, n.ident, s, point, init_expr, n.typ, .declaration);
                if (ctx.lookup(n.ident)) |p| p.facts.lifetime = .module;
            }
        },
        // A TYPE, A CASE-SET OR A BUILD DIRECTIVE BINDS NO LOCATION AND
        // ACCESSES NONE. These used to fall to the refusal arm and mark every
        // place in the module unknown, so one `enum` at file scope was enough
        // to make the whole census unusable. Admitting them is a judgment —
        // they declare meaning, not storage — not a widening for coverage.
        .enum_def, .alias_def, .concept_def, .macro_def, .cinclude, .directive => {},
        .label_stmt, .goto_stmt, .brk, .cont => {},
        .ret => |r| for (r.vals) |v| try readExpr(ctx, v),
        // A RELATION BODY REACHED FROM MODULE SCOPE IS A FOREIGN REGION. It
        // binds nothing here; it reads, writes and escapes what module scope
        // bound. A relation declared INSIDE another body is a closure that
        // captures, and this walk does not model capture — so it refuses.
        .func_decl => |*fd| {
            if (ctx.foreign or ctx.region != .module) {
                try markAllUnknown(ctx);
            } else {
                try walkForeignBody(ctx, &fd.func);
            }
        },
        .assign => |a| {
            // On this surface there is no `local` keyword: a bare `s = (...)`
            // IS the binding form, and it arrives as `.assign` with a `.name`
            // target. Verified against the parser rather than assumed — both
            // `(1,2,3)` and `{1,2,3}` build `.table` with positional fields.
            for (a.values) |v| {
                if (try aliasInit(ctx, v)) continue;
                try readExpr(ctx, v);
            }
            for (a.targets, 0..) |t, i| {
                const val: ?*const ast.Expr = if (i < a.values.len) a.values[i] else null;
                if (t.* == .name) {
                    // A NAME NOT YET BOUND IN THIS REGION IS A BINDING, WHATEVER
                    // IT IS BOUND TO. The census used to reach `bindOrRebind`
                    // only when the value was a `.table` literal, which is the
                    // measured reason lane 2's fixture produced zero places over
                    // seven program points. Everything else fell to
                    // `writeTarget`, which records a write against a place that
                    // was never created.
                    try bindOrRebind(ctx, t.name.ident, s, point, val, .inferred, .assignment);
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
            if (f.binding) |bd| {
                try readExpr(ctx, bd.expr);
                if (ctx.foreign) try ctx.shadowName(bd.name);
            }
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
            // The loop variable is a NAME THIS BODY HAS TAKEN.
            if (ctx.foreign) try ctx.shadowName(nf.var_name);
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
        // ALIAS BELONGS IN THIS LIST. It was the one §19 fact a refusal left
        // standing at `.no`, so an unmodelled shape could leave a place still
        // claiming nothing else denotes it. A refusal must lower every fact it
        // cannot see through, not all but one.
        p.facts.alias = .unknown;
        p.facts.immutability = .unknown;
    }
}

/// Walk a relation body reached FROM MODULE SCOPE.
///
/// THREE THINGS CHANGE AND NOTHING ELSE DOES. The region is foreign, so no
/// binding here mints a module place; the multiplicity is UNKNOWN, because
/// nothing at this level knows how often the relation is called and §84 forbids
/// inventing a number; and the parameters take their names for the whole body.
fn walkForeignBody(ctx: *Ctx, fb: *const ast.FuncBody) anyerror!void {
    const saved_foreign = ctx.foreign;
    const saved_mult = ctx.mult;
    const saved_depth = ctx.depth;
    const saved_shadow = ctx.shadow.items.len;
    ctx.foreign = true;
    ctx.mult = .unknown;
    ctx.depth +|= 1;
    for (fb.params) |param| try ctx.shadowName(param.name);
    try walkBlock(ctx, &fb.body);
    ctx.shadow.shrinkRetainingCapacity(saved_shadow);
    ctx.foreign = saved_foreign;
    ctx.mult = saved_mult;
    ctx.depth = saved_depth;
}

/// A relation parameter, as a place. Its facts are the CALLER'S to state, so
/// every one of them starts at the pessimistic reading — `unknown`, which by
/// `Tri`'s rule deletes what `yes` deletes.
fn bindParam(ctx: *Ctx, name: []const u8) !void {
    if (ctx.census.byName(name) != null) return;
    const id: u32 = @intCast(ctx.census.places.items.len);
    var p = Place{
        .id = id,
        .name = name,
        // A parameter has no binding STATEMENT. The census keys identity on the
        // binding site and a parameter's site is the signature, so this is the
        // one place whose witness is the enclosing declaration — recorded as
        // null-free only because `binding` is not optional today.
        .binding = &param_binding_sentinel,
        .shape = .parameter,
        .region = .function,
    };
    p.facts.lifetime = .function;
    p.facts.origin = .parameter;
    p.facts.residency = .register;
    try ctx.census.places.append(ctx.census.alloc, p);
}

/// A parameter's `binding` slot needs a stable non-null address and never a
/// dereference. Reading it is a defect; it exists so `Place.binding` can stay
/// non-optional for every consumer that already has one.
var param_binding_sentinel: ast.Stmt = .{ .brk = .{ .file = "<param>", .line = 0, .col = 0 } };

/// How a name arrives at `bindOrRebind`. The two are not interchangeable inside
/// a relation body: `x: i64 = 5` TAKES the name, `x = 5` WRITES the word.
const BindMode = enum { declaration, assignment };

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
    mode: BindMode,
) !void {
    if (ctx.lookup(name)) |p| {
        // A WRITE FROM A FOREIGN REGION IS NOT A BUILD EPISODE. `x = 5` inside
        // a relation stores into the module's word; counting it as a rebind
        // would leave `mutation = .no` on a place a relation demonstrably
        // writes, which is the one reading that turns a fold into a wrong
        // answer.
        if (ctx.foreign and mode == .assignment) {
            try p.accesses.append(ctx.census.alloc, .{
                .kind = .write,
                .point = point,
                .depth = ctx.depth,
                .mult = ctx.mult,
                .const_index = true,
            });
            p.facts.mutation = .yes;
            p.facts.immutability = .no;
            if (p.facts.contents_known == .yes) p.facts.contents_known = .no;
            if (p.facts.ordered == .yes) p.facts.ordered = .unknown;
            return;
        }
        try p.accesses.append(ctx.census.alloc, .{
            .kind = .bind,
            .point = point,
            .depth = ctx.depth,
            .mult = ctx.mult,
            .const_index = true,
        });
        return;
    }
    // A relation body binds nothing into the MODULE census. Its own places are
    // `analyzeFunction`'s to produce, over its own body, with its own ids.
    if (ctx.foreign) return;
    try bindPlace(ctx, name, s, point, init_expr, typ);
}

/// Which of §18's shapes this binding is — the judgment, taken once, at the
/// binding site.
fn shapeOf(ctx: *Ctx, init_expr: ?*const ast.Expr, typ: ast.TypeExpr) Shape {
    if (declaredExtent(typ) != null) return .collection;
    const e = init_expr orelse return .scalar;
    return switch (e.*) {
        .table => |t| if (t.fields.len > 0 and t.fields[0] != .positional) .record else .collection,
        // `global C = compiler.comptime` — a DOTTED CHAIN whose root names
        // nothing in this module is a HOME, not a value. The rule fails CLOSED:
        // a chain that is really `M.CONST` is classified `.home` too, and a
        // consumer that folds values then refuses it, which costs instructions
        // and never an answer.
        .field => if (dottedRoot(e)) |root|
            (if (ctx.census.byName(root) == null) Shape.home else Shape.record)
        else
            .scalar,
        // `u = t` where `t` is a collection makes `u` denote the same storage.
        .name => |n| if (ctx.census.byName(n.ident)) |src| src.shape else .scalar,
        else => .scalar,
    };
}

/// `u = t` — a SECOND NAME FOR ONE LOCATION.
///
/// That is an ALIAS and it is not an ESCAPE: nothing outside the region can
/// reach `t` merely because `u` exists. Returns true when the initializer was
/// consumed as an alias, so the caller does not ALSO route it through the
/// bare-mention arm and raise escape for it. A scalar initializer copies a
/// VALUE and aliases nothing, which is why the two shapes answer differently.
fn aliasInit(ctx: *Ctx, e: *const ast.Expr) !bool {
    if (e.* != .name) return false;
    const p = ctx.lookup(e.name.ident) orelse return false;
    return switch (p.shape) {
        .collection, .record, .home, .unknown => blk: {
            p.facts.alias = .unknown;
            break :blk true;
        },
        .scalar, .parameter => false,
    };
}

/// The head of a pure `a.b.c` chain, or null for anything else.
fn dottedRoot(e: *const ast.Expr) ?[]const u8 {
    return switch (e.*) {
        .name => |n| n.ident,
        .field => |f| dottedRoot(f.obj),
        else => null,
    };
}

fn bindPlace(
    ctx: *Ctx,
    name: []const u8,
    s: *const ast.Stmt,
    point: u32,
    init_expr: ?*const ast.Expr,
    typ: ast.TypeExpr,
) !void {
    const shape = shapeOf(ctx, init_expr, typ);

    const id: u32 = @intCast(ctx.census.places.items.len);
    var p = Place{
        .id = id,
        .name = name,
        .binding = s,
        .shape = shape,
        .region = ctx.region,
        .init = init_expr,
    };

    p.facts.lifetime = if (ctx.region == .module) .module else .function;
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
                // A SCALAR LITERAL IS CONTENT, AND THE CENSUS USED TO SAY IT
                // WAS UNKNOWN. `extent = 1` is not decoration: a scalar has one
                // sub-location, and stating it is what lets one ruling answer
                // for scalars and collections without a second code path.
                if (shape == .scalar and intLit(e) != null) {
                    p.facts.origin = .literal;
                    p.facts.contents_known = .yes;
                    p.facts.extent = .{ .exact = 1 };
                } else if (shape == .home) {
                    // A HOME HAS NO CONTENT AND NO EXTENT. Not "unknown" — there
                    // is nothing there to be known, and `residencyRefusal`
                    // refuses it on the SHAPE so that a future consumer that
                    // learns to read homes is not blocked by a fact that is
                    // merely absent.
                    p.facts.origin = .world;
                    p.facts.contents_known = .no;
                    p.facts.residency = .absent;
                } else {
                    p.facts.origin = .derived;
                    p.facts.contents_known = .unknown;
                }
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
            // Rebinding the whole place: a BUILD, not an element write — unless
            // the write comes from a foreign region, where it is a store into
            // one shared word.
            if (ctx.lookup(n.ident)) |p| {
                if (ctx.foreign) {
                    p.facts.mutation = .yes;
                    p.facts.immutability = .no;
                }
                try p.accesses.append(ctx.census.alloc, .{
                    .kind = if (ctx.foreign) .write else .bind,
                    .point = point,
                    .depth = ctx.depth,
                    .mult = ctx.mult,
                    .const_index = true,
                });
            }
        },
        .call => |c| {
            if (c.func.* == .name) {
                if (ctx.lookup(c.func.name.ident)) |p| {
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
                if (ctx.lookup(ix.obj.name.ident)) |p| {
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
            if (ctx.lookup(n.ident)) |p| switch (p.shape) {
                // A SCALAR'S IDENTITY IS NOT ITS ADDRESS. Reading `k` copies a
                // value; it hands nothing out and lets nothing else denote the
                // word. Treating this as an escape — which the census did,
                // because every place it admitted was a collection — is what
                // would make the residency ruling below unreachable for the one
                // shape it exists to answer.
                .scalar, .parameter => try p.accesses.append(ctx.census.alloc, .{
                    .kind = .read,
                    .point = ctx.census.points,
                    .depth = ctx.depth,
                    .mult = ctx.mult,
                    .const_index = true,
                }),
                // A COLLECTION'S IDENTITY IS ITS ADDRESS. A bare mention hands
                // that address to a context this walk cannot see through.
                //
                // ESCAPE ONLY — NOT ALIAS. §19 asks for the alias proof and the
                // escape proof as TWO controls, and a walk that answers both
                // with one assignment cannot run them separately. The split is
                // not a convenience: ALIAS asks whether two names IN THIS
                // REGION denote one location, ESCAPE asks whether anything
                // OUTSIDE the region can reach it. `sink(t)` is the second and
                // not the first; `u = t` is the first and not the second, and
                // `aliasInit` records that one at the binding site.
                .collection, .record, .home, .unknown => p.facts.escape = .unknown,
            };
        },
        .call => |c| {
            if (c.func.* == .name) {
                if (ctx.lookup(c.func.name.ident)) |p| {
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
                if (ctx.lookup(ix.obj.name.ident)) |p| {
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
        // A RECORD FIELD IS A SUB-LOCATION, NOT A PLACE. `r.f` is an access on
        // `r` whose sub-location is decided at compile time — which is exactly
        // what `Access.const_index` already means for `t(2)`. Minting a place
        // per field would make `alias` unanswerable between two fields of one
        // record; routing the whole object through the bare-mention arm would
        // call every field read an escape.
        .field => |f| {
            if (f.obj.* == .name) {
                if (ctx.lookup(f.obj.name.ident)) |p| {
                    if (p.shape == .record or p.shape == .home) {
                        try p.accesses.append(ctx.census.alloc, .{
                            .kind = .read,
                            .point = ctx.census.points,
                            .depth = ctx.depth,
                            .mult = ctx.mult,
                            .const_index = true,
                        });
                        return;
                    }
                }
            }
            try readExpr(ctx, f.obj);
        },
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
        // THE LEAVES, ENUMERATED. A literal mentions no place, so it lowers no
        // fact. Everything else — a comprehension, a macro call, a quote, a
        // range, a semantic operator — is a shape this walk cannot see through,
        // and `else => {}` silently called each of them harmless. It is the
        // same N2 rule the statement walk already follows: an unadmitted shape
        // is a defect in the WALK, and the walk lowers every fact rather than
        // assuming the shape was inert.
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg => {},
        else => try markAllUnknown(ctx),
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
    try testing.expectEqual(@as(usize, 1), c.countOfShape(.collection));
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
    try testing.expectEqual(@as(usize, 1), c.countOfShape(.collection));
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

test "place: a SECOND NAME is an alias and is NOT an escape" {
    // §19 asks for the alias proof and the escape proof as two controls, so the
    // walk must not answer both with one assignment. `u = s` puts a second name
    // on one location; nothing outside the region can reach it because of that.
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
    try testing.expectEqual(Tri.unknown, p.facts.alias);
    try testing.expectEqual(Tri.no, p.facts.escape);
}

test "place: handing the collection to a relation is an escape and NOT an alias" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    sink(s)
        \\    s(1)
        \\
    );
    defer c.deinit();
    const p = c.byName("s").?;
    try testing.expectEqual(Tri.unknown, p.facts.escape);
    try testing.expectEqual(Tri.no, p.facts.alias);
}

test "place: a SCALAR is a place, and reading one is not an escape" {
    // The measured hole lane 2 stopped at: seven program points, zero places,
    // because the census admitted a binding only when its value was a `.table`
    // LITERAL. A scalar has an identity, a lifetime and a mutation history, and
    // reading it copies a value rather than handing out an address.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    k = 7
        \\    k + 1
        \\
    );
    defer c.deinit();
    const p = c.byName("k").?;
    try testing.expectEqual(Shape.scalar, p.shape);
    try testing.expectEqual(Tri.no, p.facts.escape);
    try testing.expectEqual(Tri.no, p.facts.alias);
    try testing.expectEqual(Tri.yes, p.facts.contents_known);
    try testing.expectEqual(@as(?u64, 1), p.readCount().upperOrNull());
}

test "place: a MODULE-SCOPE binding no relation writes has NO RUNTIME LOCATION" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\
        \\main: i64 = ()
        \\    k + 1
        \\
    );
    var c = try analyzeModule(alloc, &mod);
    defer c.deinit();
    const p = c.byName("k").?;
    try testing.expectEqual(Shape.scalar, p.shape);
    try testing.expectEqual(Region.module, p.region);
    try testing.expectEqual(Refusal.none, residencyRefusal(p));
    try testing.expectEqual(Residency.absent, ruledResidency(p));
}

test "place: a relation that WRITES the module binding gives it back its word" {
    // §19 IMMUTABILITY, at the census. `moduleFunctionsAssignName` in
    // `dnir_lower.zig` decides this by hand, name-keyed and two-valued; here it
    // is one fact on one entity that four other modules read.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\
        \\bump: i64 = ()
        \\    k = 9
        \\    k
        \\
        \\main: i64 = ()
        \\    k + 1
        \\
    );
    var c = try analyzeModule(alloc, &mod);
    defer c.deinit();
    const p = c.byName("k").?;
    try testing.expectEqual(Tri.yes, p.facts.mutation);
    try testing.expectEqual(Refusal.mutated, residencyRefusal(p));
    try testing.expectEqual(Residency.static, ruledResidency(p));
}

test "place: a relation's own DECLARATION of the name is a shadow, not a write" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\
        \\shadowed: i64 = ()
        \\    k: i64 = 3
        \\    k = 4
        \\    k
        \\
        \\main: i64 = ()
        \\    k + 1
        \\
    );
    var c = try analyzeModule(alloc, &mod);
    defer c.deinit();
    const p = c.byName("k").?;
    try testing.expectEqual(Tri.no, p.facts.mutation);
    try testing.expectEqual(Refusal.none, residencyRefusal(p));
}

test "place: a PARAMETER of the same name shadows the module place too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global k = 7
        \\
        \\reuse: i64 = (k: i64)
        \\    k = k + 1
        \\    k
        \\
        \\main: i64 = ()
        \\    k + 1
        \\
    );
    var c = try analyzeModule(alloc, &mod);
    defer c.deinit();
    try testing.expectEqual(Tri.no, c.byName("k").?.facts.mutation);
}

test "place: a name bound to a HOME is a place that holds NO VALUE" {
    // `lib/compiler/rewrite.id:23`. The hop that needs this is blocked
    // CORRECTLY by the shadow test today: reading `global C = <home>` as a
    // value binding requires ruling that it is not one. This is that ruling,
    // and it FAILS CLOSED — a dotted chain that is really `M.CONST` is refused
    // on the shape too, which costs instructions and never an answer.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseModule(alloc,
        \\global C = compiler.comptime
        \\
        \\main: i64 = ()
        \\    1
        \\
    );
    var c = try analyzeModule(alloc, &mod);
    defer c.deinit();
    const p = c.byName("C").?;
    try testing.expectEqual(Shape.home, p.shape);
    try testing.expectEqual(Origin.world, p.facts.origin);
    try testing.expectEqual(Residency.absent, p.facts.residency);
    try testing.expectEqual(Tri.no, p.facts.contents_known);
    // NOT a value binding: the ruling refuses on the SHAPE, so a future
    // consumer that learns to read homes is not blocked by a merely-absent fact.
    try testing.expectEqual(Refusal.shape, residencyRefusal(p));
}

test "place: a RECORD FIELD is a sub-location, not a place of its own" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    r = { x = 1, y = 2 }
        \\    r.x
        \\
    );
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.count());
    const p = c.byName("r").?;
    try testing.expectEqual(Shape.record, p.shape);
    // The field read is an ACCESS on `r` with a compile-time sub-location — not
    // a second entity, and not an escape of the whole record.
    try testing.expectEqual(@as(?u64, 1), p.readCount().upperOrNull());
    try testing.expectEqual(Tri.no, p.facts.escape);
    try testing.expectEqual(@as(usize, 0), c.countOfShape(.scalar));
}

test "place: a PARAMETER is a place whose facts arrive from the caller" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = (n: i64)
        \\    n + 1
        \\
    );
    defer c.deinit();
    const p = c.byName("n").?;
    try testing.expectEqual(Shape.parameter, p.shape);
    try testing.expectEqual(Origin.parameter, p.facts.origin);
    // Pessimal, because the caller states them and this walk cannot see one.
    try testing.expectEqual(Tri.unknown, p.facts.escape);
    try testing.expectEqual(Tri.unknown, p.facts.alias);
}

test "place: §19 — each of the five removals changes the RULING, separately" {
    // The five permanent negative controls, at the fact layer. `gate/place.sh`
    // runs the same five in emitted machine code; this one pins that they are
    // FIVE and not one fact wearing five names — each fixture trips exactly the
    // refusal it is named for.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const Case = struct { src: []const u8, want: Refusal };
    const cases = [_]Case{
        .{ .src =
        \\global t = (10, 20, 30)
        \\
        \\main: i64 = ()
        \\    t(2)
        \\
        , .want = .none },
        // DETERMINACY: a runtime index anywhere makes the aggregate exist.
        .{ .src =
        \\global t = (10, 20, 30)
        \\
        \\pick: i64 = (i: i64)
        \\    t(i)
        \\
        \\main: i64 = ()
        \\    t(2)
        \\
        , .want = .indeterminate },
        // IMMUTABILITY.
        .{ .src =
        \\global t = (10, 20, 30)
        \\
        \\poke: i64 = ()
        \\    t(1) = 5
        \\    0
        \\
        \\main: i64 = ()
        \\    t(2)
        \\
        , .want = .mutated },
        // ALIAS — a second name in the region, and no escape.
        .{ .src =
        \\global t = (10, 20, 30)
        \\global u = t
        \\
        \\main: i64 = ()
        \\    t(2)
        \\
        , .want = .aliased },
        // ESCAPE — out of the region, and no second name.
        .{ .src =
        \\global t = (10, 20, 30)
        \\
        \\run: i64 = ()
        \\    sink(t)
        \\
        \\main: i64 = ()
        \\    t(2)
        \\
        , .want = .escaped },
    };
    for (cases, 0..) |c, i| {
        const mod = try parseModule(alloc, c.src);
        var census = try analyzeModule(alloc, &mod);
        defer census.deinit();
        const p = census.byName("t").?;
        testing.expectEqual(c.want, residencyRefusal(p)) catch |e| {
            std.debug.print("§19 control {d} expected {s}\n", .{ i, @tagName(c.want) });
            return e;
        };
    }
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
    // `h` and `e` are places too now — scalars — so the question is how many
    // COLLECTIONS, not how many names.
    try testing.expectEqual(@as(usize, 1), c.countOfShape(.collection));
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
