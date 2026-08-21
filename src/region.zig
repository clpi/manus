//! REGION — SOURCE-CONTROL-ONE's algebra, as EXACT FACTS.
//!
//! # Why this file exists
//!
//! `gate/control.sh` measures the hole this closes, and the measurement is the
//! reason: TEN structurally different programs — an if/else, an early return, a
//! bare tail, a three-alternative chain, that chain reordered, an effect moved
//! out of a guard, a recurrence, that recurrence carrying extra state, and a
//! binding scoped inside a body — normalised to ONE graph digest
//! (`ebede795efad`) while the backend emitted TEN distinct objects. A dump that
//! cannot separate programs the backend has already separated cannot adjudicate
//! SOURCE-CONTROL-ONE §8 on any row.
//!
//! Nothing was missing from the AST. What was missing was a fact.
//!
//! # NOT EDGES, AND THAT IS LOAD-BEARING
//!
//! `docs/spec/protocol-projection-one.md` §10 records that the eight structural
//! edge kinds being NON-OPERATIONAL is what makes CONTROL-ALGEBRA-NOT-METHODS
//! (§11.5) *enforced* rather than merely asserted. So there is no `--if-->`, no
//! `--while-->`, no `--break-->`, and this file adds no edge kind and no node
//! kind. A region is an ENTITY WITH ITS OWN DENSE ID and a packed fact row —
//! the shape `law.md` §20 prescribes for every other fact column, and the shape
//! `place.zig` already uses for the sibling entity the graph also does not have.
//!
//! # What a region is
//!
//! One of SOURCE-CONTROL-ONE's four faces plus the ordered alternative:
//!
//!     if / else(pred) / else / match   ->  ONE refinement, N ordered alternatives
//!     while / repeat                   ->  recurrence
//!     for                              ->  iteration
//!     return / break / continue        ->  exact region exit
//!
//! There is no `elseif` identity and no `ElseIf` shape (§3): `else if b` and
//! `else(b)` produce the same alternative at the same position. `break` and
//! `continue` differ by DEPARTURE, not by shape — one leaves the region, the
//! other leaves the current STEP of it and the region proceeds (§6) — and both
//! name their target EXACTLY, which is what retires the downstream
//! find-the-nearest-loop AST walk.
//!
//! # The refinement domain, and why it is an interval rather than an operator
//!
//! `n > 3` and `n >= 4` are THE SAME refinement, and a graph that recorded the
//! operator would report them as different — the precise failure §8 forbids
//! ("identical answers, different graphs is still WRONG", read in the other
//! direction). So an alternative publishes the INTERVAL its predicate leaves on
//! one exact place, normalised: `> 3` and `>= 4` both publish `lower = at 4`.
//!
//! It FAILS CLOSED. A predicate this cannot read exactly publishes
//! `subject = .unknown` and no bounds — never a guess. Today that means: one
//! comparison, one side a place, the other side an integer literal or another
//! place. Everything else is unknown, and `unknown` is not a synonym for
//! "unconstrained".

const std = @import("std");
const ast = @import("ast.zig");
const place = @import("place.zig");

/// The algebra, and only the algebra. A shape is NOT the source face that
/// established it: `if b` and `if(b)` are one `refinement`, `else if b` and
/// `else(b)` are one `alternative`, `while c` and `while(c)` are one
/// `recurrence`. Spelling does not reach here.
pub const Shape = enum {
    /// §3 — ONE ordered refinement application.
    refinement,
    /// One ordered alternative OF a refinement. `position` is its ordinal, so
    /// reordering two alternatives IS a different graph.
    alternative,
    /// §4 — `while`, `repeat`.
    recurrence,
    /// §5 — `for`. Its own shape, because iteration is not a recurrence with a
    /// cursor bolted on (PROTOCOL-PROJECTION-ONE §3).
    iteration,
    /// §6 — an exact region exit.
    exit,
};

/// §6: `break` leaves the region; `continue` leaves the current STEP of it and
/// the region proceeds; `return` leaves the RELATION, which is not a region and
/// therefore has target `.none`. Realization is free — a branch, predication, a
/// filtered iteration, a SIMD lane mask, or no instruction at all.
pub const Departure = enum { whole, step };

/// Three-valued reference into THIS census's region space.
///
/// `Card`'s discipline (`semantic_graph.zig`), spelled separately so a region
/// id can never be read as a graph entity id or a place id. `null` may not
/// stand in for any of the three.
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

/// One end of a refinement interval.
///
/// A literal bound is NORMALISED TO INCLUSIVE — `< 4` and `<= 3` both publish
/// `at 3` — because they are the same refinement and §8 requires the same
/// graph. A bound that is another PLACE cannot be normalised (the compiler does
/// not know its value here), so strictness is carried instead of guessed.
pub const Bound = union(enum) {
    /// Not narrowed at this end. NOT a synonym for "unconstrained by anything".
    unknown,
    /// Narrowed to an exact integer, INCLUSIVE.
    at: i64,
    /// Narrowed by another BINDING's value, INCLUSIVE. A `place.Binding` id,
    /// the same space as `Refinement.subject`.
    place: u32,
    /// Narrowed by another BINDING's value, EXCLUSIVE. Same space as `place`.
    under: u32,

    pub fn name(self: Bound) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .at => "at",
            .place => "place",
            .under => "under",
        };
    }
};

/// §32: "Preserve range, width, sign, overflow law, REFINEMENT ... through the
/// graph." The exact domain one alternative's predicate leaves.
pub const Refinement = struct {
    /// The BINDING the predicate constrains — a `place.Binding` id, not a
    /// `place.Place` id. Scalars are not places (`f5857e0a`), and the subject
    /// of a numeric predicate is almost always a scalar, so the place census
    /// cannot name it. `.none` on an unconditional alternative (a bare
    /// `else`); `.unknown` when the predicate is one this pass cannot read
    /// exactly.
    subject: place.BindingSite = .unknown,
    lower: Bound = .unknown,
    upper: Bound = .unknown,
    /// The single point an inequality predicate EXCLUDES (`n != 3`). Its own
    /// end because a hole is not a bound and folding it into one would make
    /// `n != 3` and `n > 3` compare equal.
    hole: Bound = .unknown,
};

pub const Range = struct { start: u32 = 0, len: u32 = 0 };

/// One region, packed. Every field is a fact SOURCE-CONTROL-ONE §8 names.
pub const Region = struct {
    /// Dense identity, assigned in pre-order within one relation.
    id: u32,
    shape: Shape,
    /// The enclosing region. `.none` at relation top level — a relation is not
    /// a region.
    parent: Site = .none,
    /// Ordinal among the siblings of one parent. THE fact that separates a
    /// three-alternative chain from the same chain reordered.
    position: u16 = 0,
    /// EXIT only — the exact region left (§6). `.none` for `return`.
    target: Site = .none,
    /// EXIT only.
    departure: Departure = .whole,
    /// EXIT only — the arity of the result pack. `return(a, b)` is 2; `break`
    /// and `continue` are 0 and §6 says so explicitly.
    results: u16 = 0,
    refinement: Refinement = .{},
    /// §8's `carried state`: the bindings this region UPDATES, by exact
    /// binding id, ascending. For a recurrence that is the carried set; for an
    /// alternative it is what the alternative does.
    carried: Range = .{},
};

pub const Census = struct {
    alloc: std.mem.Allocator,
    regions: std.ArrayListUnmanaged(Region) = .empty,
    /// Packed binding ids; every `Region.carried` is a window into this.
    carried: std.ArrayListUnmanaged(u32) = .empty,
    /// Statements walked. A census that examined zero statements has NOT
    /// passed — the rule every `gate/*.sh` lives by, applied to a producer.
    points: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Census {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Census) void {
        self.regions.deinit(self.alloc);
        self.carried.deinit(self.alloc);
    }

    pub fn count(self: *const Census) usize {
        return self.regions.items.len;
    }

    /// The places one region updates. Empty is an answer; an out-of-range
    /// window is a defect and reads as empty rather than as a crash.
    pub fn carriedOf(self: *const Census, r: Region) []const u32 {
        const end = std.math.add(u32, r.carried.start, r.carried.len) catch return &.{};
        if (end > self.carried.items.len) return &.{};
        return self.carried.items[r.carried.start..end];
    }

    /// How many regions of one shape. A shape census that is all-zero on a
    /// module full of loops is a producer that stopped producing.
    pub fn countOf(self: *const Census, shape: Shape) usize {
        var n: usize = 0;
        for (self.regions.items) |r| {
            if (r.shape == shape) n += 1;
        }
        return n;
    }
};

const Ctx = struct {
    census: *Census,
    places: *const place.Census,
    /// Nearest enclosing recurrence or iteration — the target every `break` and
    /// `continue` names EXACTLY, once, at lift.
    loop: Site = .none,

    fn add(self: *Ctx, r: Region) !u32 {
        const entity: u32 = @intCast(self.census.regions.items.len);
        var row = r;
        row.id = entity;
        try self.census.regions.append(self.census.alloc, row);
        return entity;
    }
};

/// The regions of one relation body, over that relation's own place census.
///
/// The two censuses are produced as a PAIR and their ids are only meaningful
/// together: a `Refinement.subject` is an index into that census's `bindings`,
/// not into its `places` and not into any other census. A caller that pairs
/// them wrongly gets a wrong answer, which is why nothing here accepts a bare
/// id from outside.
pub fn analyzeFunction(
    alloc: std.mem.Allocator,
    fb: *const ast.FuncBody,
    places: *const place.Census,
) !Census {
    var census = Census.init(alloc);
    errdefer census.deinit();
    var ctx = Ctx{ .census = &census, .places = places };
    try walkBlock(&ctx, &fb.body, .none);
    return census;
}

fn walkBlock(ctx: *Ctx, b: *const ast.Block, parent: Site) anyerror!void {
    var position: u16 = 0;
    for (b.stmts) |*s| try walkStmt(ctx, s, parent, &position);
}

fn walkStmt(ctx: *Ctx, s: *const ast.Stmt, parent: Site, position: *u16) anyerror!void {
    ctx.census.points += 1;
    switch (s.*) {
        .if_stmt => |f| {
            const refinement = try ctx.add(.{
                .id = 0,
                .shape = .refinement,
                .parent = parent,
                .position = position.*,
            });
            position.* +|= 1;
            var alternative: u16 = 0;
            try addAlternative(ctx, refinement, &alternative, f.cond, &f.then);
            for (f.elseifs) |ei| {
                try addAlternative(ctx, refinement, &alternative, ei.cond, &ei.body);
            }
            if (f.else_body) |*eb| {
                try addAlternative(ctx, refinement, &alternative, null, eb);
            }
        },
        .match_stmt => |m| {
            const refinement = try ctx.add(.{
                .id = 0,
                .shape = .refinement,
                .parent = parent,
                .position = position.*,
            });
            position.* +|= 1;
            var alternative: u16 = 0;
            for (m.arms) |*arm| {
                // A PATTERN IS NOT A COMPARISON, so the domain it leaves is
                // `unknown` and not `none`. §3 requires familiar `match` to
                // become the same refinement graph; it does not license
                // inventing a domain this pass cannot read.
                try addAlternative(ctx, refinement, &alternative, null, &arm.body);
            }
        },
        .while_loop => |w| {
            const recurrence = try ctx.add(.{
                .id = 0,
                .shape = .recurrence,
                .parent = parent,
                .position = position.*,
                .refinement = domainOf(ctx, w.cond),
            });
            position.* +|= 1;
            try carry(ctx, recurrence, &w.body);
            try nested(ctx, &w.body, .{ .one = recurrence }, .{ .one = recurrence });
        },
        .repeat_loop => |r| {
            const recurrence = try ctx.add(.{
                .id = 0,
                .shape = .recurrence,
                .parent = parent,
                .position = position.*,
                .refinement = domainOf(ctx, r.cond),
            });
            position.* +|= 1;
            try carry(ctx, recurrence, &r.body);
            try nested(ctx, &r.body, .{ .one = recurrence }, .{ .one = recurrence });
        },
        .num_for => |nf| {
            const iteration = try ctx.add(.{
                .id = 0,
                .shape = .iteration,
                .parent = parent,
                .position = position.*,
            });
            position.* +|= 1;
            try carry(ctx, iteration, &nf.body);
            try nested(ctx, &nf.body, .{ .one = iteration }, .{ .one = iteration });
        },
        .gen_for => |gf| {
            const iteration = try ctx.add(.{
                .id = 0,
                .shape = .iteration,
                .parent = parent,
                .position = position.*,
            });
            position.* +|= 1;
            try carry(ctx, iteration, &gf.body);
            try nested(ctx, &gf.body, .{ .one = iteration }, .{ .one = iteration });
        },
        .ret => |r| {
            _ = try ctx.add(.{
                .id = 0,
                .shape = .exit,
                .parent = parent,
                .position = position.*,
                // A RELATION IS NOT A REGION, so a `return` has no region to
                // name and `.none` is the exact answer — not `.unknown`.
                .target = .none,
                .departure = .whole,
                .results = @intCast(@min(r.vals.len, std.math.maxInt(u16))),
            });
            position.* +|= 1;
        },
        .brk => {
            _ = try ctx.add(.{
                .id = 0,
                .shape = .exit,
                .parent = parent,
                .position = position.*,
                // PUBLISHED ONCE, HERE. `break` outside every loop leaves
                // `.unknown` rather than inventing a target.
                .target = ctx.loop,
                .departure = .whole,
            });
            position.* +|= 1;
        },
        .cont => {
            _ = try ctx.add(.{
                .id = 0,
                .shape = .exit,
                .parent = parent,
                .position = position.*,
                .target = ctx.loop,
                .departure = .step,
            });
            position.* +|= 1;
        },
        // A `do` block, a `try` body and a `defer` body BIND SCOPE but are not
        // members of §0's control algebra, so they establish no region here and
        // their contents belong to the enclosing one. Stated rather than
        // silently walked past: a body-scoped binding inside a bare `do` is a
        // fact this census does not yet carry.
        .do_block => |d| try walkBlock(ctx, &d.body, parent),
        .try_stmt => |t| {
            try walkBlock(ctx, &t.body, parent);
            for (t.catches) |*cc| try walkBlock(ctx, &cc.body, parent);
            for (t.defers) |*d| try walkBlock(ctx, &d.body, parent);
        },
        .defer_stmt => |d| try walkBlock(ctx, &d.body, parent),
        // A NESTED RELATION HAS ITS OWN CENSUS, over its own body, with its own
        // ids — the same rule `place.zig` states for the same reason.
        .func_decl => {},
        else => {},
    }
}

fn nested(ctx: *Ctx, b: *const ast.Block, parent: Site, loop: Site) !void {
    const saved = ctx.loop;
    ctx.loop = loop;
    try walkBlock(ctx, b, parent);
    ctx.loop = saved;
}

fn addAlternative(
    ctx: *Ctx,
    refinement: u32,
    position: *u16,
    cond: ?*const ast.Expr,
    body: *const ast.Block,
) !void {
    const domain: Refinement = if (cond) |c|
        domainOf(ctx, c)
    else
        // A BARE `else` CONSTRAINS NOTHING, and that is a known-absent
        // predicate rather than an unreadable one. §3: `else(expr)` ALWAYS
        // means a conditional alternative, so this arm is only reached by a
        // genuine unconditional else.
        .{ .subject = .none };
    const alternative = try ctx.add(.{
        .id = 0,
        .shape = .alternative,
        .parent = .{ .one = refinement },
        .position = position.*,
        .refinement = domain,
    });
    position.* +|= 1;
    try carry(ctx, alternative, body);
    // An alternative does not change which loop a `break` inside it names.
    try walkBlock(ctx, body, .{ .one = alternative });
}

/// §8's `carried state`, for one region: the places its body UPDATES, ascending
/// and deduplicated. Only plain-name targets resolve; a write through an index
/// or a field is a write to a sub-location of a place this pass does not
/// attribute, and it is left out rather than guessed at.
fn carry(ctx: *Ctx, region: u32, body: *const ast.Block) !void {
    const start: u32 = @intCast(ctx.census.carried.items.len);
    try collectCarried(ctx, body);
    const end: u32 = @intCast(ctx.census.carried.items.len);
    std.mem.sort(u32, ctx.census.carried.items[start..end], {}, std.sort.asc(u32));
    // Deduplicate in place: one place written twice is one carried place.
    var write: u32 = start;
    var read: u32 = start;
    while (read < end) : (read += 1) {
        if (write > start and ctx.census.carried.items[write - 1] == ctx.census.carried.items[read]) continue;
        ctx.census.carried.items[write] = ctx.census.carried.items[read];
        write += 1;
    }
    ctx.census.carried.shrinkRetainingCapacity(write);
    ctx.census.regions.items[region].carried = .{ .start = start, .len = write - start };
}

fn collectCarried(ctx: *Ctx, b: *const ast.Block) anyerror!void {
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| for (a.targets) |t| {
            if (t.* != .name) continue;
            if (placeOf(ctx, t.name.ident)) |p| try ctx.census.carried.append(ctx.census.alloc, p);
        },
        .local_decl => |d| for (d.names) |n| {
            if (placeOf(ctx, n.ident)) |p| try ctx.census.carried.append(ctx.census.alloc, p);
        },
        .if_stmt => |f| {
            try collectCarried(ctx, &f.then);
            for (f.elseifs) |ei| try collectCarried(ctx, &ei.body);
            if (f.else_body) |*eb| try collectCarried(ctx, eb);
        },
        .while_loop => |w| try collectCarried(ctx, &w.body),
        .repeat_loop => |r| try collectCarried(ctx, &r.body),
        .num_for => |nf| try collectCarried(ctx, &nf.body),
        .gen_for => |gf| try collectCarried(ctx, &gf.body),
        .do_block => |d| try collectCarried(ctx, &d.body),
        .match_stmt => |m| for (m.arms) |*arm| try collectCarried(ctx, &arm.body),
        .try_stmt => |t| {
            try collectCarried(ctx, &t.body);
            for (t.catches) |*cc| try collectCarried(ctx, &cc.body);
        },
        .defer_stmt => |d| try collectCarried(ctx, &d.body),
        else => {},
    };
}

/// The BINDING a name denotes in this body, or null.
///
/// It reads the binding census, not the place census, because `bindPlace`
/// declines every scalar and the subject of a numeric predicate is a scalar.
/// Asking `places.find` for `n` in `if (n > 3)` answered null for every
/// program, which is how six region facts came to be computed off an
/// all-default `Refinement`; gap[206] measures it.
///
/// `place.Census.findBinding` scans BACKWARD, so where one body binds two
/// names of one spelling in sibling scopes this answers the LATER one. That is
/// the same lookup `dnir_lower.zig` already resolves module names through, and
/// it is the honest limit of a name-keyed locate: a shadowed spelling can
/// attribute a refinement to the wrong binding. It cannot attribute it to a
/// binding that does not exist, so a wrong answer here is a wrong SUBJECT and
/// never a wrong program — and the day bindings carry lexical extent it becomes
/// exact with no change to any consumer.
fn placeOf(ctx: *Ctx, name: []const u8) ?u32 {
    const b = ctx.places.findBinding(name) orelse return null;
    return b.id;
}

/// The interval one predicate leaves, or `.unknown` — never a guess.
fn domainOf(ctx: *Ctx, cond: *const ast.Expr) Refinement {
    if (cond.* != .binop) return .{};
    const b = cond.binop;
    // `place OP operand`, or the mirror `operand OP place` with the comparison
    // reflected. Nothing else is read: `a and b`, a call, a projection and a
    // negation all publish `.unknown`, which is the honest answer.
    if (b.lhs.* == .name) {
        if (placeOf(ctx, b.lhs.name.ident)) |subject| {
            return domainFrom(ctx, subject, b.op, b.rhs);
        }
    }
    if (b.rhs.* == .name) {
        if (placeOf(ctx, b.rhs.name.ident)) |subject| {
            return domainFrom(ctx, subject, reflect(b.op), b.lhs);
        }
    }
    return .{};
}

fn reflect(op: ast.BinOp) ast.BinOp {
    return switch (op) {
        .lt => .gt,
        .gt => .lt,
        .leq => .geq,
        .geq => .leq,
        else => op,
    };
}

fn domainFrom(ctx: *Ctx, subject: u32, op: ast.BinOp, operand: *const ast.Expr) Refinement {
    var out = Refinement{ .subject = .{ .one = subject } };
    if (intLit(operand)) |k| {
        switch (op) {
            // NORMALISED TO INCLUSIVE. `< 4` and `<= 3` are one refinement.
            .lt => out.upper = if (std.math.sub(i64, k, 1)) |v| .{ .at = v } else |_| return .{},
            .leq => out.upper = .{ .at = k },
            .gt => out.lower = if (std.math.add(i64, k, 1)) |v| .{ .at = v } else |_| return .{},
            .geq => out.lower = .{ .at = k },
            .eq => {
                out.lower = .{ .at = k };
                out.upper = .{ .at = k };
            },
            .neq => out.hole = .{ .at = k },
            else => return .{},
        }
        return out;
    }
    if (operand.* == .name) {
        if (placeOf(ctx, operand.name.ident)) |bound| {
            switch (op) {
                .lt => out.upper = .{ .under = bound },
                .leq => out.upper = .{ .place = bound },
                .gt => out.lower = .{ .under = bound },
                .geq => out.lower = .{ .place = bound },
                .eq => {
                    out.lower = .{ .place = bound };
                    out.upper = .{ .place = bound };
                },
                .neq => out.hole = .{ .place = bound },
                else => return .{},
            }
            return out;
        }
    }
    return .{};
}

fn intLit(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |l| l.val,
        .unop => |u| switch (u.op) {
            .neg => if (intLit(u.operand)) |v| (std.math.negate(v) catch null) else null,
            else => null,
        },
        else => null,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// The controls. Each one is a fact that must MOVE when the program changes, and
// every one of them is a row `gate/control.sh` pins as a defect today.
// ─────────────────────────────────────────────────────────────────────────────


const testing = std.testing;

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

/// Same fixture shape as `place.zig` and `demand.zig` — deliberately, because
/// all three analyse the same object and a second parsing convention would be
/// the duplicate semantic ownership §79-80 forbids.
fn parseModule(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    const owned = try alloc.dupe(u8, src);
    var lex = Lexer.init(owned, "region_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    return try p.parse_module();
}

/// The two censuses of the fixture's one relation, produced as a PAIR — which
/// is the only way a `Refinement.subject` means anything.
const Pair = struct {
    places: place.Census,
    regions: Census,

    fn deinit(self: *Pair) void {
        self.places.deinit();
        self.regions.deinit();
    }
};

fn censusOf(arena: *std.heap.ArenaAllocator, src: []const u8) !Pair {
    const alloc = arena.allocator();
    const mod = try parseModule(alloc, src);
    for (mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        var places = try place.analyzeFunction(alloc, &s.func_decl.func);
        errdefer places.deinit();
        const regions = try analyzeFunction(alloc, &s.func_decl.func, &places);
        return .{ .places = places, .regions = regions };
    }
    return error.NoRelation;
}

test "region: a reordered three-alternative chain is a different graph" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var low = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 9)
        \\        r = 1
        \\    else(n > 3)
        \\        r = 2
        \\    else
        \\        r = 3
        \\    r
        \\
    );
    defer low.deinit();
    var high = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 3)
        \\        r = 2
        \\    else(n > 9)
        \\        r = 1
        \\    else
        \\        r = 3
        \\    r
        \\
    );
    defer high.deinit();
    try testing.expectEqual(@as(usize, 4), low.regions.count());
    try testing.expectEqual(@as(usize, 4), high.regions.count());
    const a = low.regions.regions.items[1];
    const b = high.regions.regions.items[1];
    try testing.expectEqual(Shape.alternative, a.shape);
    try testing.expectEqual(Shape.alternative, b.shape);
    try testing.expectEqual(@as(u16, 0), a.position);
    try testing.expectEqual(@as(u16, 0), b.position);
    // Same answer for every n, DIFFERENT ordered refinement. This is the
    // `graph/alt` row `gate/control.sh` pins as a recorded defect.
    try testing.expectEqual(@as(i64, 10), a.refinement.lower.at);
    try testing.expectEqual(@as(i64, 4), b.refinement.lower.at);
}

test "region: `> 3` and `>= 4` are ONE refinement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var strict = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 3)
        \\        r = 1
        \\    r
        \\
    );
    defer strict.deinit();
    var loose = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n >= 4)
        \\        r = 1
        \\    r
        \\
    );
    defer loose.deinit();
    try testing.expectEqual(
        strict.regions.regions.items[1].refinement.lower.at,
        loose.regions.regions.items[1].refinement.lower.at,
    );
}

test "region: a different literal is a different domain" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var three = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 3)
        \\        r = 1
        \\    else
        \\        r = 2
        \\    r
        \\
    );
    defer three.deinit();
    var five = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 5)
        \\        r = 1
        \\    else
        \\        r = 2
        \\    r
        \\
    );
    defer five.deinit();
    // `graph/predicate`: both answer 1 for n = 8 and the refinement domains
    // differ, which is the whole of what §8 asks the graph to record.
    try testing.expectEqual(@as(i64, 4), three.regions.regions.items[1].refinement.lower.at);
    try testing.expectEqual(@as(i64, 6), five.regions.regions.items[1].refinement.lower.at);
}

test "region: break names its target exactly, and continue departs the step" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    i = 0
        \\    while(i < 9)
        \\        i = i + 1
        \\        if(i > 3)
        \\            break
        \\        continue
        \\    i
        \\
    );
    defer c.deinit();
    try testing.expectEqual(Shape.recurrence, c.regions.regions.items[0].shape);
    var breaks: usize = 0;
    var continues: usize = 0;
    for (c.regions.regions.items) |r| {
        if (r.shape != .exit) continue;
        switch (r.departure) {
            .whole => {
                breaks += 1;
                // PUBLISHED, not rebuilt by walking the AST for the nearest
                // loop — the recurrence is region 0 and the exit says so.
                try testing.expectEqual(@as(u32, 0), r.target.one);
            },
            .step => {
                continues += 1;
                try testing.expectEqual(@as(u32, 0), r.target.one);
            },
        }
        try testing.expectEqual(@as(u16, 0), r.results);
    }
    try testing.expectEqual(@as(usize, 1), breaks);
    try testing.expectEqual(@as(usize, 1), continues);
}

test "region: a return leaves the RELATION, which is not a region" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    if(n > 3)
        \\        return(n + 1)
        \\    return(0)
        \\
    );
    defer c.deinit();
    var exits: usize = 0;
    for (c.regions.regions.items) |r| {
        if (r.shape != .exit) continue;
        exits += 1;
        try testing.expect(r.target == .none);
        try testing.expectEqual(@as(u16, 1), r.results);
    }
    try testing.expectEqual(@as(usize, 2), exits);
}

test "region: extra carried state is a different recurrence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var one = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    i = 0
        \\    t = 0
        \\    while(i < n)
        \\        t = t + i
        \\        i = i + 1
        \\    t
        \\
    );
    defer one.deinit();
    var two = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    i = 0
        \\    t = 0
        \\    k = 0
        \\    while(i < n)
        \\        t = t + i
        \\        k = k + 2
        \\        i = i + 1
        \\    t
        \\
    );
    defer two.deinit();
    try testing.expectEqual(@as(usize, 2), one.regions.carriedOf(one.regions.regions.items[0]).len);
    try testing.expectEqual(@as(usize, 3), two.regions.carriedOf(two.regions.regions.items[0]).len);
}

test "region: a predicate this pass cannot read fails CLOSED" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 3 and n < 9)
        \\        r = 1
        \\    r
        \\
    );
    defer c.deinit();
    const alternative = c.regions.regions.items[1];
    try testing.expectEqual(Shape.alternative, alternative.shape);
    try testing.expect(alternative.refinement.subject == .unknown);
    try testing.expect(alternative.refinement.lower == .unknown);
    try testing.expect(alternative.refinement.upper == .unknown);
    try testing.expect(alternative.refinement.hole == .unknown);
}

test "region: a bare else is a KNOWN-ABSENT predicate, not an unknown one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    r = 0
        \\    if(n > 3)
        \\        r = 1
        \\    else
        \\        r = 2
        \\    r
        \\
    );
    defer c.deinit();
    try testing.expect(c.regions.regions.items[1].refinement.subject == .one);
    try testing.expect(c.regions.regions.items[2].refinement.subject == .none);
}

test "region: a bound that is another place carries its strictness" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c = try censusOf(&arena,
        \\main: i64 = ()
        \\    n = 8
        \\    i = 0
        \\    while(i < n)
        \\        i = i + 1
        \\    i
        \\
    );
    defer c.deinit();
    const recurrence = c.regions.regions.items[0];
    try testing.expectEqual(Shape.recurrence, recurrence.shape);
    try testing.expect(recurrence.refinement.subject == .one);
    // `i < n` cannot be normalised to an inclusive integer, so the exclusive
    // form is carried rather than guessed at.
    try testing.expect(recurrence.refinement.upper == .under);
}

test "region: a census that examined zero statements is visible as such" {
    var census = Census.init(testing.allocator);
    defer census.deinit();
    try testing.expectEqual(@as(u32, 0), census.points);
    try testing.expectEqual(@as(usize, 0), census.count());
    try testing.expectEqual(@as(usize, 0), census.countOf(.recurrence));
}
