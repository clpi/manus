//! Backward demand propagation — the Tier-0 question, asked for the first time.
//!
//! # What this module is for
//!
//! Every other optimiser in this tree makes the same work cheaper. This one asks
//! whether the work has to happen. Measured before it existed, with
//! `--backend=direct` on this compiler:
//!
//!     a 100,000-iteration loop whose result is NEVER read  ->  main = 16 instructions
//!     the identical loop whose result IS returned          ->  main = 19 instructions
//!     a program that just returns the answer               ->  main =  2 instructions
//!
//! The dead loop costs the same 100,000 iterations as the live one. Nothing in
//! the compiler asked whether anything observes `s`.
//!
//! # Why the graph's `demand` fact did not already do this
//!
//! `semantic_graph.Node.demand` is a `types.ReturnConsumption`
//! (`discard | single | multi | unknown`). It is FORWARD, CALL-LOCAL and
//! ARITY-ONLY: it records how many values the syntactic context of a call wants,
//! it exists only on `.call`/`.method_call` nodes, and its sole non-test reader
//! is the JSON projection in `semantic_graph.appendGraphJson`. Forcing every
//! application in a program to `.discard` — the maximal lie, "nothing observes
//! any call result" — changes the exported fact from six `single` to six
//! `discard` and leaves `__text` byte-identical. It is inert by construction.
//!
//! Backward demand is a different fact. It is a property of a PLACE at a PROGRAM
//! POINT, propagated from observation roots against the direction of control
//! flow, and the graph has no place entity to hang it on. That is why it is
//! computed here, over the AST, rather than added as another column.
//!
//! # The transform, stated as the universal contract
//!
//! The project's contract is `T: (S, F, D, W, H) -> {R1..Rn}` — semantic
//! identity, facts, demand, world, hardware target, producing lawful realization
//! candidates. Elimination is NOT a new kingdom in that contract; it is the
//! candidate generator that emits the EMPTY realization:
//!
//!     S  the statement/region's semantic identity
//!     F  effect card, authority card, trip-count proof, known-bits
//!     D  the quotient of S that is observed downstream
//!     W  whether anything outside the program observes S
//!     H  irrelevant here — the empty realization is target-independent
//!
//!     R_empty  is a LAWFUL candidate iff D = nothing and O2..O5 below hold
//!     R_keep   is always lawful
//!
//! and `R_empty` always wins on cost, so no new cost model is needed either.
//! The quotient cases are the SAME generator with a richer `D`: `D = X mod 2^k`
//! generates a narrowed-width candidate, `D = exists` generates an early-exit
//! candidate, `D = min` generates a linear scan where a sort was written. This
//! module implements the bottom of that lattice — `D = nothing` — because every
//! richer `D` is computed by the same backward walk.
//!
//! # THE PROOF OBLIGATION, stated before the transform
//!
//! A statement `S` may be deleted only if ALL FIVE hold. Any one unproven means
//! keep. There is no "probably".
//!
//!   O1  VALUE-DEAD.   Every place `S` writes is read on no path from `S` to any
//!                     observation point. Observation points are: the function's
//!                     answer, an argument to anything with an effect, any
//!                     non-local place (global, field, index, upvalue), and any
//!                     place a closure could capture.
//!
//!   O2  TRAP-FREE.    `S` cannot fault. `div`/`idiv`/`mod` are trap-carrying
//!                     unless the divisor is a non-zero literal — this backend's
//!                     `sdiv` happens not to fault on zero TODAY, which is
//!                     exactly why the exclusion must survive a future divide
//!                     check (`native_backend.zig` states the same rule for
//!                     if-conversion, and this module reuses its whitelist).
//!                     Indexing is bounds-checked and a failed check ends in
//!                     `brk`, so `a(i)` is trap-carrying.
//!
//!   O3  EFFECT-FREE.  No world interaction. A call is inert only when the
//!                     graph's `effect` card for its application reads `.none`.
//!                     `.unknown` IS AN EFFECT — corpus-wide the column is
//!                     864 `none` / 414 `unknown`, and treating `unknown` as
//!                     "probably fine" is how a lane ships a wrong answer.
//!
//!   O4  TERMINATING.  A loop is not dead merely because its value is unused. If
//!                     it may not terminate, deleting it turns a hang into a
//!                     return, which is observable. `provenTripCount` below is
//!                     the only proof accepted, and it is deliberately narrow.
//!
//!   O5  NO ESCAPE.    `S` contains no `break`, `continue`, `return`, `goto` or
//!                     label — deleting a statement that transfers control
//!                     changes where control goes.
//!
//! # What is deliberately NOT proven here
//!
//! Reads of `a(i)` / `r.f`, table constructors, string concatenation, varargs,
//! closures, `repeat`, `gen_for` and every directive are refused outright. They
//! are refusals, not gaps: the graph cannot express a place, so this module
//! cannot prove non-aliasing, and a transform that cannot prove it must not do
//! it. `num_for` bodies are analysed for liveness but the loop itself is never
//! deleted, because its induction variable is written by the lowering rather
//! than by a statement this walk can see.

const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const semantic_graph = @import("semantic_graph.zig");

/// Why a statement survived. Every non-`dead` value names an unmet obligation,
/// so a census over these says which obligation is costing the most work.
pub const Blocker = enum {
    /// O1 failed: something downstream reads a place this writes.
    observed,
    /// O2 failed: the statement can fault.
    may_trap,
    /// O3 failed: a call whose `effect` card is not `.none`, or a store to a
    /// place that is not provably local.
    has_effect,
    /// O4 failed: a loop with no accepted termination proof.
    may_not_terminate,
    /// O5 failed: `break` / `continue` / `return` / `goto` / label inside.
    control_escape,
    /// The shape is outside this module's admitted subset. Not a bug — a
    /// refusal. Widening the subset is how this number comes down.
    unsupported_shape,
};

/// One statement's verdict. `dead` means all five obligations discharged.
pub const Verdict = union(enum) {
    dead,
    kept: Blocker,
};

/// The set of statements proven deletable, keyed by statement identity.
///
/// Keyed by POINTER because a statement has no id in this tree and two textually
/// identical statements are different work. The AST outlives lowering, so the
/// pointers stay valid for exactly as long as the plan is consulted.
pub const Plan = struct {
    dead: std.AutoHashMapUnmanaged(*const ast.Stmt, void) = .empty,
    /// Statements after which a `break` is lawful — the SECOND candidate this
    /// module generates. See `earlyExitSites`.
    break_after: std.AutoHashMapUnmanaged(*const ast.Stmt, void) = .empty,
    /// Census of unmet obligations, for the gate. Index by `@intFromEnum`.
    blocked: [std.meta.fieldNames(Blocker).len]u32 = @splat(0),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Plan {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Plan) void {
        self.dead.deinit(self.alloc);
        self.break_after.deinit(self.alloc);
    }

    pub fn breaksAfter(self: *const Plan, stmt: *const ast.Stmt) bool {
        return self.break_after.contains(stmt);
    }

    pub fn earlyExitCount(self: *const Plan) u32 {
        return @intCast(self.break_after.count());
    }

    pub fn isDead(self: *const Plan, stmt: *const ast.Stmt) bool {
        return self.dead.contains(stmt);
    }

    pub fn count(self: *const Plan) u32 {
        return @intCast(self.dead.count());
    }

    fn mark(self: *Plan, stmt: *const ast.Stmt) !void {
        try self.dead.put(self.alloc, stmt, {});
    }

    fn unmark(self: *Plan, stmt: *const ast.Stmt) void {
        _ = self.dead.remove(stmt);
    }

    fn note(self: *Plan, b: Blocker) void {
        self.blocked[@intFromEnum(b)] += 1;
    }
};

pub const Options = struct {
    /// The checked graph, when there is one. Without it every call is refused,
    /// because O3 has no evidence and `unknown` is an effect.
    graph: ?*const semantic_graph.SemanticGraph = null,
    /// Names bound at MODULE scope. A write to one of these is a write to a
    /// place the whole program can see, and is never eliminable.
    ///
    /// This set is not a nicety. `s = 0` binding a function local and `g = 1`
    /// storing to a file-scope global are THE SAME AST NODE — `.assign` with a
    /// single `.name` target — so without it every global store in the corpus
    /// would have looked like a dead local.
    globals: ?*const std.StringHashMapUnmanaged(void) = null,
    /// Hard ceiling on loop-liveness fixpoint rounds. The lattice is a finite
    /// set of names and the transfer is monotone, so this can only be hit by a
    /// bug; hitting it refuses the loop rather than looping forever.
    fixpoint_rounds: u32 = 64,
};

// ---------------------------------------------------------------------------
// Live set
// ---------------------------------------------------------------------------

/// Names live at a program point. A name absent from this set is dead there.
///
/// Name-keyed rather than binding-keyed because the AST has no binding ids. That
/// is sound in the direction that matters: shadowing can only make a name look
/// live when it is not, which keeps work that could have been deleted. It can
/// never make a live name look dead.
const Live = struct {
    set: std.StringHashMapUnmanaged(void) = .empty,
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator) Live {
        return .{ .alloc = alloc };
    }

    fn deinit(self: *Live) void {
        self.set.deinit(self.alloc);
    }

    fn clone(self: *const Live) !Live {
        return .{ .set = try self.set.clone(self.alloc), .alloc = self.alloc };
    }

    fn add(self: *Live, name: []const u8) !void {
        try self.set.put(self.alloc, name, {});
    }

    fn kill(self: *Live, name: []const u8) void {
        _ = self.set.remove(name);
    }

    fn has(self: *const Live, name: []const u8) bool {
        return self.set.contains(name);
    }

    fn unionWith(self: *Live, other: *const Live) !void {
        var it = other.set.keyIterator();
        while (it.next()) |k| try self.add(k.*);
    }

    /// Take ownership of `other`'s storage, releasing `self`'s. `other` is left
    /// empty and safe to `deinit` again, so a `defer` on it stays correct.
    fn replaceWith(self: *Live, other: *Live) void {
        self.set.deinit(self.alloc);
        self.set = other.set;
        other.set = .empty;
    }

    fn eql(self: *const Live, other: *const Live) bool {
        if (self.set.count() != other.set.count()) return false;
        var it = self.set.keyIterator();
        while (it.next()) |k| if (!other.has(k.*)) return false;
        return true;
    }
};

// ---------------------------------------------------------------------------
// O2 + O3 — inertness of an expression
// ---------------------------------------------------------------------------

/// `null` when the expression is inert: it computes a value, cannot fault, and
/// touches nothing outside itself. Otherwise the obligation it fails.
///
/// The admitted operator set is the same closed whitelist `native_backend`'s
/// if-conversion uses, and for the same reason: if-conversion executes an arm
/// the branch would have skipped, this deletes work the program would have run,
/// and both are only sound over operations that cannot be observed at all.
pub fn inert(opts: Options, e: *const ast.Expr) ?Blocker {
    return switch (e.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit => null,

        // Reading a name produces no effect and cannot fault. Whether the name
        // is one this walk may KILL is a separate question, answered by O1.
        .name => null,

        .binop => |b| switch (b.op) {
            // THE trapping arithmetic. Admitted only against a literal divisor
            // that is provably non-zero; `sdiv` not faulting today is the
            // reason to exclude it, not a reason to allow it.
            .div, .idiv, .mod => blk: {
                const d = intLiteralOf(b.rhs) orelse break :blk .may_trap;
                if (d == 0) break :blk .may_trap;
                break :blk inert(opts, b.lhs);
            },
            // Wrapping ALU and comparison — no fault, no memory, no world.
            .add, .sub, .mul, .band, .bor, .bxor, .lshift, .rshift, .eq, .neq, .lt, .gt, .leq, .geq, .@"and", .@"or" => inert(opts, b.lhs) orelse inert(opts, b.rhs),
            // `concat` materialises, `matmul` and `pipeline` are applications,
            // `contains` is a search over a place, `pow` is a runtime call on
            // this backend. All refused.
            .concat, .matmul, .pipeline, .contains, .pow => .unsupported_shape,
        },

        .unop => |u| switch (u.op) {
            .neg, .not, .bnot => inert(opts, u.operand),
            // `#x` reads a length out of a place, and `##`/`comptime` is a
            // directive. Neither is a value this walk owns.
            .len, .compile => .unsupported_shape,
        },

        .if_expr => |ie| inert(opts, ie.cond) orelse inert(opts, ie.then_expr) orelse inert(opts, ie.else_expr),

        .sequence => |s| blk: {
            for (s.exprs) |x| if (inert(opts, x)) |b| break :blk b;
            break :blk null;
        },

        // O3 lives here, and it is the whole reason the graph is threaded in.
        // `.none` is the only card that discharges it. `.unknown` is an effect.
        .call, .method_call => blk: {
            const graph = opts.graph orelse break :blk .has_effect;
            const fact = applicationOf(graph, e) orelse break :blk .has_effect;
            if (fact.effect != .none) break :blk .has_effect;
            const args: []const *ast.Expr = switch (e.*) {
                .call => |c| c.args,
                .method_call => |m| m.args,
                else => unreachable,
            };
            for (args) |a| if (inert(opts, a)) |b| break :blk b;
            if (e.* == .method_call) if (inert(opts, e.method_call.obj)) |b| break :blk b;
            break :blk null;
        },

        // Reads through a place. The graph cannot express a place, so
        // non-aliasing is unprovable and indexing is bounds-checked into `brk`.
        .index, .field => .may_trap,

        else => .unsupported_shape,
    };
}

/// The checked application fact for a call expression, when the graph has one.
fn applicationOf(
    graph: *const semantic_graph.SemanticGraph,
    e: *const ast.Expr,
) ?*const semantic_graph.ApplicationFact {
    var i: usize = 0;
    while (i < graph.nodes.items.len) : (i += 1) {
        const node = graph.nodes.items[i];
        if (node.kind != .call) continue;
        const ref = node.ast_ref orelse continue;
        if (@as(*const ast.Expr, @ptrCast(@alignCast(ref))) != e) continue;
        const occurrence = std.math.cast(semantic_graph.id, i) orelse return null;
        return graph.application(occurrence);
    }
    return null;
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

/// Every name this expression reads, added to `live`.
///
/// Over-approximates on purpose: a name that appears anywhere in a shape this
/// module does not model is added, which keeps its producer alive.
fn readsOf(live: *Live, e: *const ast.Expr) std.mem.Allocator.Error!void {
    switch (e.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg, .semantic, .semantic_scope => {},
        .name => |n| try live.add(n.ident),
        .index => |x| {
            try readsOf(live, x.obj);
            try readsOf(live, x.key);
        },
        .field => |x| try readsOf(live, x.obj),
        .call => |c| {
            try readsOf(live, c.func);
            for (c.args) |a| try readsOf(live, a);
        },
        .method_call => |m| {
            try readsOf(live, m.obj);
            for (m.args) |a| try readsOf(live, a);
        },
        .binop => |b| {
            try readsOf(live, b.lhs);
            try readsOf(live, b.rhs);
        },
        .unop => |u| try readsOf(live, u.operand),
        .table => |t| for (t.fields) |f| switch (f) {
            .indexed => |x| {
                try readsOf(live, x.key);
                try readsOf(live, x.val);
            },
            .named => |x| try readsOf(live, x.val),
            .positional => |x| try readsOf(live, x),
            .spread => |x| try readsOf(live, x),
            else => {},
        },
        .list_comp => |l| {
            try readsOf(live, l.value);
            try readsOf(live, l.iter);
            if (l.filter) |f| try readsOf(live, f);
        },
        .try_expr => |x| try readsOf(live, x.operand),
        .unwrap_expr => |x| try readsOf(live, x.operand),
        .await_expr => |x| try readsOf(live, x.operand),
        .quote => |x| try readsOf(live, x.expr),
        .unquote => |x| try readsOf(live, x.expr),
        .if_expr => |ie| {
            try readsOf(live, ie.cond);
            try readsOf(live, ie.then_expr);
            try readsOf(live, ie.else_expr);
        },
        .match_expr => |m| {
            try readsOf(live, m.scrutinee);
            for (m.arms) |arm| {
                if (arm.guard) |g| try readsOf(live, g);
                try blockReads(live, &arm.body);
            }
        },
        .contains_expr => |c| {
            try readsOf(live, c.lhs);
            try readsOf(live, c.rhs);
        },
        .macro_call => |m| for (m.args) |a| try readsOf(live, a),
        .sequence => |s| for (s.exprs) |x| try readsOf(live, x),
        .range => |r| {
            try readsOf(live, r.start);
            try readsOf(live, r.end);
            if (r.step) |s| try readsOf(live, s);
        },
        // A closure can read anything its body mentions, at a time this walk
        // cannot see. Every free name in it stays live.
        .func_expr => |f| try blockReads(live, &f.body),
    }
}

/// Every name any statement in a block reads OR writes, added to `live`. The
/// escape hatch for shapes this module refuses to model: adding writes too means
/// a producer feeding an unmodelled consumer is never killed.
fn blockReads(live: *Live, b: *const ast.Block) std.mem.Allocator.Error!void {
    for (b.stmts) |*s| try stmtReads(live, s);
    if (b.tail_expr) |t| try readsOf(live, t);
}

fn stmtReads(live: *Live, s: *const ast.Stmt) std.mem.Allocator.Error!void {
    switch (s.*) {
        .local_decl => |d| {
            for (d.inits) |e| try readsOf(live, e);
            for (d.names) |n| try live.add(n.ident);
        },
        .global_decl => |d| {
            for (d.inits) |e| try readsOf(live, e);
            for (d.names) |n| try live.add(n.ident);
        },
        .const_decl => |d| {
            try readsOf(live, d.val);
            try live.add(d.ident);
        },
        .assign => |a| {
            for (a.values) |e| try readsOf(live, e);
            for (a.targets) |t| try readsOf(live, t);
        },
        .call_stmt => |x| try readsOf(live, x.expr),
        .expr_stmt => |x| try readsOf(live, x.expr),
        .do_block => |d| try blockReads(live, &d.body),
        .while_loop => |w| {
            try readsOf(live, w.cond);
            try blockReads(live, &w.body);
        },
        .repeat_loop => |r| {
            try blockReads(live, &r.body);
            try readsOf(live, r.cond);
        },
        .if_stmt => |f| {
            if (f.binding) |b| try readsOf(live, b.expr);
            try readsOf(live, f.cond);
            try blockReads(live, &f.then);
            for (f.elseifs) |ei| {
                try readsOf(live, ei.cond);
                try blockReads(live, &ei.body);
            }
            if (f.else_body) |eb| try blockReads(live, &eb);
        },
        .num_for => |n| {
            try readsOf(live, n.start);
            try readsOf(live, n.stop);
            if (n.step) |st| try readsOf(live, st);
            try blockReads(live, &n.body);
        },
        .gen_for => |g| {
            for (g.iters) |e| try readsOf(live, e);
            try blockReads(live, &g.body);
        },
        .func_decl => |f| try blockReads(live, &f.func.body),
        .ret => |r| for (r.vals) |e| try readsOf(live, e),
        .brk, .cont, .goto_stmt, .label_stmt => {},
        else => {},
    }
}

// ---------------------------------------------------------------------------
// O4 — termination
// ---------------------------------------------------------------------------

/// The integer value of a literal, INCLUDING a negated one.
///
/// `-5` parses as `unop(neg, int_lit 5)`, not as an `int_lit` of -5. Reading
/// only `.int_lit` made `while i < -5` — a loop that never enters, so the most
/// trivially terminating loop there is — fail its termination proof. Negating
/// `minInt` is refused rather than wrapped.
fn intLiteralOf(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |x| x.val,
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const inner = intLiteralOf(u.operand) orelse break :blk null;
                if (inner == std.math.minInt(i64)) break :blk null;
                break :blk -inner;
            },
            else => null,
        },
        else => null,
    };
}

/// A proof that a counted `while` runs a finite number of times, or `null`.
///
/// Accepted shape, and nothing else:
///
///     while i < N        (or <=, >, >=)   N an integer LITERAL
///         ...
///         i += c                          c a positive integer literal
///         ...
///
/// with the update at the TOP LEVEL of the body — an update nested inside an
/// `if` is not executed on every iteration and proves nothing — `i` written
/// nowhere else in the body, and no closure in the body that could capture it.
///
/// The direction must match the test: `<`/`<=` needs `+`, `>`/`>=` needs `-`.
/// A zero or negative step is REFUSED rather than assumed harmless; `while n > 0`
/// with a step that never enters is exactly how this project shipped five wrong
/// answers in six lines, and the refusal is cheaper than the incident.
///
/// Overflow is part of the proof, not an afterthought. `i` moves monotonically
/// and exits on the first value past `N`, so it overshoots by less than `c`;
/// requiring `|N| <= maxInt - c` means the overshoot cannot wrap. `N` must be a
/// literal for that inequality to be decidable at all.
pub const TripProof = struct {
    counter: []const u8,
    limit: i64,
    step: i64,
    ascending: bool,
};

pub fn provenTripCount(w: anytype) ?TripProof {
    const cond = w.cond;
    if (cond.* != .binop) return null;
    const b = cond.binop;
    const ascending = switch (b.op) {
        .lt, .leq => true,
        .gt, .geq => false,
        else => return null,
    };
    if (b.lhs.* != .name) return null;
    const counter = b.lhs.name.ident;
    const limit = intLiteralOf(b.rhs) orelse return null;

    // The counter must not be re-bound, captured, or written anywhere but the
    // one top-level update.
    if (blockDeclares(&w.body, counter)) return null;
    if (blockHasClosure(&w.body)) return null;

    var step: ?i64 = null;
    for (w.body.stmts) |*s| {
        if (nestedWrites(s, counter)) return null;
        const upd = topLevelStep(s, counter) orelse continue;
        if (step != null) return null; // two updates: no single trip count
        step = upd;
    }
    const c = step orelse return null;
    // The move must go TOWARDS the bound. A zero step never terminates, and a
    // step away from the bound is the `while n > 0` shape that never entered for
    // negatives and shipped five wrong answers in six lines. Both are refused.
    if (ascending and c <= 0) return null;
    if (!ascending and c >= 0) return null;
    const magnitude = if (ascending) c else -c;
    // The counter exits on the FIRST value past the bound, so it overshoots by
    // less than one step. Requiring the bound plus one step to fit means the
    // overshoot cannot wrap — which is decidable only because the bound is a
    // literal, and is why a symbolic bound is refused above.
    if (ascending) {
        if (limit > std.math.maxInt(i64) - magnitude) return null;
    } else {
        if (limit < std.math.minInt(i64) + magnitude) return null;
    }
    return .{ .counter = counter, .limit = limit, .step = magnitude, .ascending = ascending };
}

/// `i = i + c` / `i = i - c` written at the top level of the body, returning the
/// signed magnitude of the move in the direction the test needs.
fn topLevelStep(s: *const ast.Stmt, counter: []const u8) ?i64 {
    if (s.* != .assign) return null;
    const a = s.assign;
    if (a.targets.len != 1 or a.values.len != 1) return null;
    if (a.targets[0].* != .name) return null;
    if (!std.mem.eql(u8, a.targets[0].name.ident, counter)) return null;
    const v = a.values[0];
    if (v.* != .binop) return null;
    const bb = v.binop;
    if (bb.op != .add and bb.op != .sub) return null;
    if (bb.lhs.* != .name or !std.mem.eql(u8, bb.lhs.name.ident, counter)) return null;
    const c = intLiteralOf(bb.rhs) orelse return null;
    if (c == std.math.minInt(i64)) return null;
    return if (bb.op == .add) c else -c;
}

/// Any write to `name` that is not the single top-level update — inside an `if`,
/// an inner loop, a `do`, or as one of several assignment targets.
fn nestedWrites(s: *const ast.Stmt, name: []const u8) bool {
    return switch (s.*) {
        .assign => |a| blk: {
            if (a.targets.len == 1 and a.values.len == 1 and
                a.targets[0].* == .name and std.mem.eql(u8, a.targets[0].name.ident, name))
                break :blk false; // the top-level update, judged by topLevelStep
            for (a.targets) |t| if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) break :blk true;
            break :blk false;
        },
        .local_decl => |d| blockNamesInclude(d.names, name),
        .global_decl => |d| blockNamesInclude(d.names, name),
        .const_decl => |d| std.mem.eql(u8, d.ident, name),
        .do_block => |d| blockWrites(&d.body, name),
        .while_loop => |w| blockWrites(&w.body, name),
        .repeat_loop => |r| blockWrites(&r.body, name),
        .if_stmt => |f| blk: {
            if (blockWrites(&f.then, name)) break :blk true;
            for (f.elseifs) |ei| if (blockWrites(&ei.body, name)) break :blk true;
            if (f.else_body) |eb| if (blockWrites(&eb, name)) break :blk true;
            break :blk false;
        },
        .num_for => |n| std.mem.eql(u8, n.var_name, name) or blockWrites(&n.body, name),
        .gen_for => |g| blk: {
            for (g.vars) |v| if (std.mem.eql(u8, v, name)) break :blk true;
            break :blk blockWrites(&g.body, name);
        },
        .func_decl => true,
        else => false,
    };
}

fn blockNamesInclude(names: []const ast.LocalName, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n.ident, name)) return true;
    return false;
}

fn blockWrites(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |*s| {
        if (s.* == .assign) {
            for (s.assign.targets) |t| {
                if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) return true;
            }
            continue;
        }
        if (nestedWrites(s, name)) return true;
    }
    return false;
}

fn blockDeclares(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |*s| switch (s.*) {
        .local_decl => |d| if (blockNamesInclude(d.names, name)) return true,
        .global_decl => |d| if (blockNamesInclude(d.names, name)) return true,
        .const_decl => |d| if (std.mem.eql(u8, d.ident, name)) return true,
        else => {},
    };
    return false;
}

fn blockHasClosure(b: *const ast.Block) bool {
    for (b.stmts) |*s| switch (s.*) {
        .func_decl => return true,
        .local_decl => |d| for (d.inits) |e| if (exprHasClosure(e)) return true,
        .assign => |a| for (a.values) |e| if (exprHasClosure(e)) return true,
        .do_block => |d| if (blockHasClosure(&d.body)) return true,
        .while_loop => |w| if (blockHasClosure(&w.body)) return true,
        .repeat_loop => |r| if (blockHasClosure(&r.body)) return true,
        .if_stmt => |f| {
            if (blockHasClosure(&f.then)) return true;
            for (f.elseifs) |ei| if (blockHasClosure(&ei.body)) return true;
            if (f.else_body) |eb| if (blockHasClosure(&eb)) return true;
        },
        .num_for => |n| if (blockHasClosure(&n.body)) return true,
        .gen_for => |g| if (blockHasClosure(&g.body)) return true,
        else => {},
    };
    return false;
}

fn exprHasClosure(e: *const ast.Expr) bool {
    return switch (e.*) {
        .func_expr => true,
        .binop => |b| exprHasClosure(b.lhs) or exprHasClosure(b.rhs),
        .unop => |u| exprHasClosure(u.operand),
        .call => |c| blk: {
            for (c.args) |a| if (exprHasClosure(a)) break :blk true;
            break :blk exprHasClosure(c.func);
        },
        else => false,
    };
}

// ---------------------------------------------------------------------------
// O5 — control escape
// ---------------------------------------------------------------------------

/// `break` / `continue` / `return` / `goto` / a label anywhere under `b`.
///
/// A nested loop's own `break` still counts. Being wrong in the direction of
/// "there might be an escape" costs a kept loop; being wrong the other way
/// deletes a control transfer, which is a wrong answer.
fn blockEscapes(b: *const ast.Block) bool {
    for (b.stmts) |*s| switch (s.*) {
        .brk, .cont, .goto_stmt, .label_stmt, .ret => return true,
        .do_block => |d| if (blockEscapes(&d.body)) return true,
        .while_loop => |w| if (blockEscapes(&w.body)) return true,
        .repeat_loop => |r| if (blockEscapes(&r.body)) return true,
        .if_stmt => |f| {
            if (blockEscapes(&f.then)) return true;
            for (f.elseifs) |ei| if (blockEscapes(&ei.body)) return true;
            if (f.else_body) |eb| if (blockEscapes(&eb)) return true;
        },
        .num_for => |n| if (blockEscapes(&n.body)) return true,
        .gen_for => |g| if (blockEscapes(&g.body)) return true,
        else => {},
    };
    return false;
}

// ---------------------------------------------------------------------------
// Whole-loop judgment
// ---------------------------------------------------------------------------

/// Every plain-name place the block writes, collected into `w`. Returns false
/// the moment it finds a write this module cannot own — through an index, a
/// field, or a shape it does not model — because then the set of places written
/// is not knowable and no disjointness argument can be made.
fn loopWrites(opts: Options, b: *const ast.Block, w: *Live) std.mem.Allocator.Error!bool {
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| {
            for (a.targets) |t| {
                if (t.* != .name) return false;
                // A loop that writes a module-scope global writes a place the
                // whole program sees. Nothing downstream in THIS function
                // reading it proves nothing at all.
                if (opts.globals) |g| if (g.contains(t.name.ident)) return false;
                try w.add(t.name.ident);
            }
        },
        .local_decl => |d| for (d.names) |n| try w.add(n.ident),
        .do_block => |d| if (!try loopWrites(opts, &d.body, w)) return false,
        .while_loop => |wl| if (!try loopWrites(opts, &wl.body, w)) return false,
        .if_stmt => |f| {
            if (!try loopWrites(opts, &f.then, w)) return false;
            for (f.elseifs) |ei| if (!try loopWrites(opts, &ei.body, w)) return false;
            if (f.else_body) |eb| if (!try loopWrites(opts, &eb, w)) return false;
            if (f.binding) |bnd| try w.add(bnd.name);
        },
        .brk, .cont, .goto_stmt, .label_stmt => {},
        .call_stmt, .expr_stmt => {},
        // `global`, `const`, `func`, `for`, `repeat`, directives: the write set
        // is not this module's to describe.
        else => return false,
    };
    return true;
}

/// O2 + O3 for a loop body: every statement must be a value computation over
/// inert expressions. Returns the first unmet obligation, or `null`.
///
/// A nested loop must carry its OWN termination proof — deleting an outer loop
/// deletes the inner one with it, and an inner loop that may not terminate is
/// exactly the case where the value being unobserved proves nothing.
fn loopBodyInert(opts: Options, b: *const ast.Block) ?Blocker {
    if (b.tail_expr) |t| if (inert(opts, t)) |bl| return bl;
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| {
            for (a.targets) |t| if (t.* != .name) return .has_effect;
            for (a.values) |v| if (inert(opts, v)) |bl| return bl;
            if (a.targets.len != a.values.len) return .unsupported_shape;
        },
        .local_decl => |d| {
            for (d.inits) |e| if (inert(opts, e)) |bl| return bl;
            if (d.names.len != d.inits.len) return .unsupported_shape;
        },
        .call_stmt => |x| if (inert(opts, x.expr)) |bl| return bl,
        .expr_stmt => |x| if (inert(opts, x.expr)) |bl| return bl,
        .do_block => |d| if (loopBodyInert(opts, &d.body)) |bl| return bl,
        .if_stmt => |f| {
            if (f.binding) |bnd| if (inert(opts, bnd.expr)) |bl| return bl;
            if (inert(opts, f.cond)) |bl| return bl;
            if (loopBodyInert(opts, &f.then)) |bl| return bl;
            for (f.elseifs) |ei| {
                if (inert(opts, ei.cond)) |bl| return bl;
                if (loopBodyInert(opts, &ei.body)) |bl| return bl;
            }
            if (f.else_body) |eb| if (loopBodyInert(opts, &eb)) |bl| return bl;
        },
        .while_loop => |wl| {
            if (inert(opts, wl.cond)) |bl| return bl;
            if (loopBodyInert(opts, &wl.body)) |bl| return bl;
            if (provenTripCount(wl) == null) return .may_not_terminate;
        },
        else => return .unsupported_shape,
    };
    return null;
}

// ---------------------------------------------------------------------------
// THE SECOND CANDIDATE — the loop's answer is already final
// ---------------------------------------------------------------------------
//
// `T: (S, F, D, W, H) -> {R1..Rn}` does not become a new kingdom because a
// second candidate exists. Elimination emits the EMPTY realization when the
// demanded quotient of a region is nothing. This emits the TRUNCATED
// realization when the demanded quotient of a loop stops changing partway
// through. Same backward demand, same obligations, one more candidate.
//
// The shape, and it is `materialize all matches` -> `does one exist?`:
//
//     found = 0
//     i = 0
//     while i < 1000000
//         if <inert predicate on i>
//             found = 1        <- every write is the SAME literal
//         i += 1
//     found
//
// `found` is the only place the loop writes that anything downstream reads.
// Every write to it stores the same value, so after the first write the loop's
// observable answer CANNOT CHANGE — it has reached its fixpoint. The remaining
// iterations compute a value that is already known.
//
// UNLIKE ELIMINATION, THIS CHANGES COMPLEXITY CLASS. The loop stops being
// O(bound) and becomes O(index of the first witness). Deleting an unobserved
// computation removes a constant factor; stopping at the first witness removes
// an asymptote, which is why this candidate and not a faster inner loop is the
// interesting one.
//
// THE PROOF OBLIGATION, and it is O1..O5 plus two more:
//
//   E1  IDEMPOTENT.   Every write to the observed place stores the same integer
//                     literal, so the sequence of values is v0, v0, ..., L, L,
//                     ... — monotone in one step and constant thereafter. The
//                     value at the first write equals the value at the end.
//
//   E2  UNREAD.       The observed place is never read inside the loop, so no
//                     iteration's behaviour depends on how many writes preceded
//                     it. Without this, `found` could feed the predicate and a
//                     later iteration could do something different.
//
//   E3  SOLE.         It is the ONLY place the loop writes that survives to the
//                     exit. Every other place it writes — the induction counter
//                     included — is dead there, so truncating the iteration
//                     count cannot be observed through any of them.
//
//   E4  INERT BODY.   O2 and O3 for the whole body: the skipped iterations must
//                     perform no effect and be unable to trap. This is what
//                     makes "did not run" indistinguishable from "ran".
//
//   E5  TERMINATING.  O4 still. Truncating a loop that may not terminate turns
//                     a hang into a return, and that is observable. Early exit
//                     only ever shortens a run that was already finite.
//
//   E6  NO ESCAPE.    O5: an existing `break`/`continue`/`return` in the body
//                     means control already leaves in a way this rewrite would
//                     race with. And no NESTED loop may contain a write site,
//                     because a `break` there exits the inner loop, not this one.
//
// Then: `acc_final = L` if any iteration writes, else `acc_initial`. Breaking
// immediately after the first write yields `L`; never writing runs to
// completion and yields `acc_initial`. The two programs agree on every input.

/// Record the write sites in `wl` after which a `break` is lawful, or leave the
/// plan untouched. `live_out` is the set live at the loop's exit.
fn earlyExitSites(
    w: *Walk,
    wl: anytype,
    stmt_loop: *const ast.Stmt,
    live_out: *const Live,
    writes: *const Live,
    plain_writes: bool,
    body_blocker: ?Blocker,
    cond_blocker: ?Blocker,
    escapes: bool,
    proof: ?TripProof,
) std.mem.Allocator.Error!void {
    _ = stmt_loop;
    if (!w.recording or !w.deleting) return;
    if (!plain_writes or body_blocker != null or cond_blocker != null or escapes) return;
    if (proof == null) return; // E5
    if (blockHasLoop(&wl.body)) return; // E6 — a break would exit the wrong loop

    // E3 — exactly one written place survives to the exit.
    var acc: ?[]const u8 = null;
    var it = writes.set.keyIterator();
    while (it.next()) |k| {
        if (!live_out.has(k.*)) continue;
        if (acc != null) return;
        acc = k.*;
    }
    const name = acc orelse return;

    // E2 — the observed place must not feed the loop back.
    if (blockReadsName(&wl.body, name)) return;
    if (exprReadsName(wl.cond, name)) return;

    // E1 — every write is the same literal.
    var lit: ?i64 = null;
    var sites: std.ArrayListUnmanaged(*const ast.Stmt) = .empty;
    defer sites.deinit(w.alloc);
    if (!try constantWriteSites(w.alloc, &wl.body, name, &lit, &sites)) return;
    if (sites.items.len == 0) return;

    for (sites.items) |site| try w.plan.break_after.put(w.alloc, site, {});
}

/// True when every write to `name` under `b` is `name = <integer literal>` and
/// all of those literals are equal. Write sites are appended to `sites`.
fn constantWriteSites(
    alloc: std.mem.Allocator,
    b: *const ast.Block,
    name: []const u8,
    lit: *?i64,
    sites: *std.ArrayListUnmanaged(*const ast.Stmt),
) std.mem.Allocator.Error!bool {
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| {
            var touches = false;
            for (a.targets) |t| {
                if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) touches = true;
            }
            if (!touches) continue;
            if (a.targets.len != 1 or a.values.len != 1) return false;
            const v = intLiteralOf(a.values[0]) orelse return false;
            if (lit.*) |seen| {
                if (seen != v) return false;
            } else lit.* = v;
            try sites.append(alloc, s);
        },
        .local_decl => |d| for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) return false,
        .do_block => |d| if (!try constantWriteSites(alloc, &d.body, name, lit, sites)) return false,
        .if_stmt => |f| {
            if (f.binding) |bnd| if (std.mem.eql(u8, bnd.name, name)) return false;
            if (!try constantWriteSites(alloc, &f.then, name, lit, sites)) return false;
            for (f.elseifs) |ei| if (!try constantWriteSites(alloc, &ei.body, name, lit, sites)) return false;
            if (f.else_body) |eb| if (!try constantWriteSites(alloc, &eb, name, lit, sites)) return false;
        },
        else => {},
    };
    return true;
}

fn blockHasLoop(b: *const ast.Block) bool {
    for (b.stmts) |*s| switch (s.*) {
        .while_loop, .repeat_loop, .num_for, .gen_for => return true,
        .do_block => |d| if (blockHasLoop(&d.body)) return true,
        .if_stmt => |f| {
            if (blockHasLoop(&f.then)) return true;
            for (f.elseifs) |ei| if (blockHasLoop(&ei.body)) return true;
            if (f.else_body) |eb| if (blockHasLoop(&eb)) return true;
        },
        else => {},
    };
    return false;
}

fn exprReadsName(e: *const ast.Expr, name: []const u8) bool {
    return switch (e.*) {
        .name => |n| std.mem.eql(u8, n.ident, name),
        .binop => |b| exprReadsName(b.lhs, name) or exprReadsName(b.rhs, name),
        .unop => |u| exprReadsName(u.operand, name),
        .index => |x| exprReadsName(x.obj, name) or exprReadsName(x.key, name),
        .field => |x| exprReadsName(x.obj, name),
        .call => |c| blk: {
            for (c.args) |a| if (exprReadsName(a, name)) break :blk true;
            break :blk exprReadsName(c.func, name);
        },
        .method_call => |m| blk: {
            for (m.args) |a| if (exprReadsName(a, name)) break :blk true;
            break :blk exprReadsName(m.obj, name);
        },
        .if_expr => |ie| exprReadsName(ie.cond, name) or exprReadsName(ie.then_expr, name) or exprReadsName(ie.else_expr, name),
        .sequence => |sq| blk: {
            for (sq.exprs) |x| if (exprReadsName(x, name)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// A READ of `name` anywhere under `b`. An assignment TARGET is a write, not a
/// read, and is deliberately not counted — but `acc += 1` desugars to
/// `acc = acc + 1`, whose value side reads it, so compound updates are caught.
fn blockReadsName(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| {
            for (a.values) |v| if (exprReadsName(v, name)) return true;
            for (a.targets) |t| if (t.* != .name and exprReadsName(t, name)) return true;
        },
        .local_decl => |d| for (d.inits) |e| if (exprReadsName(e, name)) return true,
        .call_stmt => |x| if (exprReadsName(x.expr, name)) return true,
        .expr_stmt => |x| if (exprReadsName(x.expr, name)) return true,
        .ret => |r| for (r.vals) |e| if (exprReadsName(e, name)) return true,
        .do_block => |d| if (blockReadsName(&d.body, name)) return true,
        .while_loop => |wl| {
            if (exprReadsName(wl.cond, name)) return true;
            if (blockReadsName(&wl.body, name)) return true;
        },
        .repeat_loop => |r| {
            if (exprReadsName(r.cond, name)) return true;
            if (blockReadsName(&r.body, name)) return true;
        },
        .if_stmt => |f| {
            if (f.binding) |bnd| if (exprReadsName(bnd.expr, name)) return true;
            if (exprReadsName(f.cond, name)) return true;
            if (blockReadsName(&f.then, name)) return true;
            for (f.elseifs) |ei| {
                if (exprReadsName(ei.cond, name)) return true;
                if (blockReadsName(&ei.body, name)) return true;
            }
            if (f.else_body) |eb| if (blockReadsName(&eb, name)) return true;
        },
        .num_for => |n| {
            if (exprReadsName(n.start, name) or exprReadsName(n.stop, name)) return true;
            if (n.step) |st| if (exprReadsName(st, name)) return true;
            if (blockReadsName(&n.body, name)) return true;
        },
        .gen_for => |g| {
            for (g.iters) |e| if (exprReadsName(e, name)) return true;
            if (blockReadsName(&g.body, name)) return true;
        },
        else => {},
    };
    if (b.tail_expr) |t| if (exprReadsName(t, name)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// The backward walk
// ---------------------------------------------------------------------------

const Walk = struct {
    alloc: std.mem.Allocator,
    opts: Options,
    plan: *Plan,
    /// When false the walk computes liveness only and records no verdicts. Used
    /// for the loop fixpoint's throwaway rounds, so a statement is never marked
    /// dead on the strength of a live set that has not converged yet.
    recording: bool,
    /// When false a statement is never treated as deleted, so its reads still
    /// reach the live set. This is the mode a KEPT loop's body is walked in:
    /// a statement inside a loop that survives has not been removed, and
    /// pretending otherwise loses the liveness that keeps its producers.
    deleting: bool = true,

    fn isGlobal(self: *const Walk, name: []const u8) bool {
        const g = self.opts.globals orelse return false;
        return g.contains(name);
    }
};

/// Transfer a block backwards through `live`, which arrives holding the set live
/// at the block's exit and leaves holding the set live at its entry.
fn transferBlock(w: *Walk, b: *const ast.Block, live: *Live) std.mem.Allocator.Error!void {
    // A block's tail expression IS its answer, so everything it reads is
    // observed at the exit.
    if (b.tail_expr) |t| try readsOf(live, t);

    var i = b.stmts.len;
    while (i > 0) {
        i -= 1;
        try transferStmt(w, &b.stmts[i], live);
    }
}

fn transferStmt(w: *Walk, s: *const ast.Stmt, live: *Live) std.mem.Allocator.Error!void {
    switch (s.*) {
        // `return` ends every path through it, so nothing after it is live on
        // this path. The live set becomes exactly what the returned values read.
        .ret => |r| {
            var fresh = Live.init(w.alloc);
            defer fresh.deinit();
            for (r.vals) |e| try readsOf(&fresh, e);
            live.replaceWith(&fresh);
            if (w.recording) w.plan.note(.control_escape);
        },

        .local_decl => |d| {
            const all_dead = blk: {
                for (d.names) |n| if (live.has(n.ident)) break :blk false;
                break :blk true;
            };
            // A multi-value binding (`a, b = f()`) has one initializer feeding
            // several names; killing part of it is not expressible, so the whole
            // statement lives unless every name is dead.
            const shaped = d.names.len == d.inits.len;
            var blocker: ?Blocker = null;
            for (d.inits) |e| {
                if (inert(w.opts, e)) |bl| {
                    blocker = bl;
                    break;
                }
            }
            if (w.deleting and all_dead and shaped and blocker == null) {
                if (w.recording) try w.plan.mark(s);
                return;
            }
            if (w.recording) {
                w.plan.unmark(s);
                w.plan.note(if (!all_dead) .observed else blocker orelse .unsupported_shape);
            }
            for (d.names) |n| live.kill(n.ident);
            for (d.inits) |e| try readsOf(live, e);
        },

        .assign => |a| {
            // Only writes to plain names are candidates. A write through
            // `a(i)` or `r.f` reaches a place, and the graph cannot express a
            // place, so non-aliasing is unprovable.
            const plain = blk: {
                for (a.targets) |t| {
                    if (t.* != .name) break :blk false;
                    // A module-scope name is a place the whole program sees.
                    if (w.isGlobal(t.name.ident)) break :blk false;
                }
                break :blk true;
            };
            const all_dead = plain and blk: {
                for (a.targets) |t| if (live.has(t.name.ident)) break :blk false;
                break :blk true;
            };
            var blocker: ?Blocker = null;
            for (a.values) |e| {
                if (inert(w.opts, e)) |bl| {
                    blocker = bl;
                    break;
                }
            }
            const shaped = a.targets.len == a.values.len;
            if (w.deleting and plain and all_dead and shaped and blocker == null) {
                if (w.recording) try w.plan.mark(s);
                return;
            }
            if (w.recording) {
                w.plan.unmark(s);
                w.plan.note(if (!plain) .has_effect else if (!all_dead) .observed else blocker orelse .unsupported_shape);
            }
            // KILL BEFORE READ. `s = s + 1` kills `s` then reads it back, which
            // is right; `s = 0` kills it and reads nothing, which is what lets a
            // dead accumulator's initialiser die too.
            if (plain) for (a.targets) |t| live.kill(t.name.ident);
            for (a.values) |e| try readsOf(live, e);
            if (!plain) for (a.targets) |t| try readsOf(live, t);
        },

        .call_stmt, .expr_stmt => {
            const x_expr = switch (s.*) {
                .call_stmt => |c| c.expr,
                .expr_stmt => |c| c.expr,
                else => unreachable,
            };
            if (inert(w.opts, x_expr)) |bl| {
                if (w.recording) {
                    w.plan.unmark(s);
                    w.plan.note(bl);
                }
                try readsOf(live, x_expr);
                return;
            }
            // Inert AND in statement position: its value has no consumer at all.
            if (!w.deleting) {
                try readsOf(live, x_expr);
                return;
            }
            if (w.recording) try w.plan.mark(s);
        },

        .do_block => |d| try transferBlock(w, &d.body, live),

        .if_stmt => |f| {
            // Each branch is transferred from the SAME exit set, so a statement
            // inside a branch is judged against the paths that actually leave
            // that branch, and the entry set is the union over all paths.
            var acc = try live.clone();
            defer acc.deinit();

            var then_live = try live.clone();
            defer then_live.deinit();
            try transferBlock(w, &f.then, &then_live);
            try acc.unionWith(&then_live);

            for (f.elseifs) |ei| {
                var ei_live = try live.clone();
                defer ei_live.deinit();
                try transferBlock(w, &ei.body, &ei_live);
                try acc.unionWith(&ei_live);
                try readsOf(&acc, ei.cond);
            }

            if (f.else_body) |eb| {
                var else_live = try live.clone();
                defer else_live.deinit();
                try transferBlock(w, &eb, &else_live);
                try acc.unionWith(&else_live);
            }

            try readsOf(&acc, f.cond);
            if (f.binding) |bnd| try readsOf(&acc, bnd.expr);

            live.replaceWith(&acc);
        },

        // A LOOP IS JUDGED AS A UNIT, NOT STATEMENT BY STATEMENT.
        //
        // Plain liveness can never kill an induction variable: `i += 1` reads
        // `i` and `i < N` reads `i`, so `i` keeps itself alive forever and the
        // per-statement rule marks only `s += i` dead. Deleting THAT and
        // keeping the loop is worse than doing nothing — it is how a
        // terminating loop becomes a hang. So the question asked here is about
        // the whole loop: does anything downstream read any place this loop
        // writes? If not, and O2..O5 hold, the loop goes as one object.
        .while_loop => |wl| {
            var exit_live = try live.clone();
            defer exit_live.deinit();

            var writes = Live.init(w.alloc);
            defer writes.deinit();
            const plain_writes = try loopWrites(w.opts, &wl.body, &writes);

            const observed = blk: {
                var it = writes.set.keyIterator();
                while (it.next()) |k| if (exit_live.has(k.*)) break :blk true;
                break :blk false;
            };
            const body_blocker = loopBodyInert(w.opts, &wl.body);
            const cond_blocker = inert(w.opts, wl.cond);
            const escapes = blockEscapes(&wl.body);
            const proof = provenTripCount(wl);

            if (w.deleting and plain_writes and !observed and
                body_blocker == null and cond_blocker == null and !escapes and proof != null)
            {
                if (w.recording) try w.plan.mark(s);
                var out = exit_live;
                live.replaceWith(&out);
                exit_live = Live.init(w.alloc);
                return;
            }

            // The loop survives as a loop — but its ANSWER may already be
            // final partway through. Second candidate, same demand.
            try earlyExitSites(w, wl, s, &exit_live, &writes, plain_writes, body_blocker, cond_blocker, escapes, proof);

            if (w.recording) {
                w.plan.unmark(s);
                w.plan.note(if (!plain_writes)
                    .has_effect
                else if (escapes)
                    .control_escape
                else if (body_blocker) |bb|
                    bb
                else if (cond_blocker) |cb|
                    cb
                else if (proof == null)
                    .may_not_terminate
                else
                    .observed);
            }

            // The loop survives, so NOTHING inside it is deleted — removing a
            // statement from a loop whose trip count is not proven can change
            // whether it terminates. Liveness is recomputed in non-deleting
            // mode so every producer feeding the surviving body stays alive.
            var fixed = try live.clone();
            defer fixed.deinit();
            var round: u32 = 0;
            var converged = false;
            while (round < w.opts.fixpoint_rounds) : (round += 1) {
                var trial = try fixed.clone();
                defer trial.deinit();
                var sub: Walk = .{
                    .alloc = w.alloc,
                    .opts = w.opts,
                    .plan = w.plan,
                    .recording = false,
                    .deleting = false,
                };
                try transferBlock(&sub, &wl.body, &trial);
                try trial.unionWith(&exit_live);
                try readsOf(&trial, wl.cond);
                if (trial.eql(&fixed)) {
                    converged = true;
                    break;
                }
                fixed.deinit();
                fixed = try trial.clone();
            }
            if (!converged) {
                // Cannot happen for a monotone transfer over a finite name set;
                // if it does, refuse by making everything the loop touches live.
                try blockReads(live, &wl.body);
                try readsOf(live, wl.cond);
                return;
            }
            live.replaceWith(&fixed);
        },

        // Every remaining shape is refused. Liveness still has to be right, so
        // every name the statement mentions — read OR written — goes live, which
        // keeps whatever produces it.
        else => {
            try stmtReads(live, s);
            if (w.recording) {
                w.plan.unmark(s);
                w.plan.note(.unsupported_shape);
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Demand-analyse one function body. The answer of the function is the only
/// observation root; everything else must earn its life from that.
pub fn analyzeFunction(
    alloc: std.mem.Allocator,
    func: *const ast.FuncBody,
    opts: Options,
    plan: *Plan,
) !void {
    // A backward walk over a statement list assumes control reaches each
    // statement from the one after it. Two shapes break that assumption
    // outright, and neither is worth modelling for the floor case:
    //
    //   a closure — it can read or write an outer local at a time this walk
    //   cannot place, so a store that looks dead here may be the one the
    //   closure reads;
    //
    //   `goto` / a label — control can arrive from anywhere, so "the paths
    //   from this statement" is not the suffix of the block.
    //
    // Both refuse the WHOLE function rather than one statement, because the
    // unsoundness is in the walk, not in the statement.
    if (blockHasClosure(&func.body)) {
        plan.note(.unsupported_shape);
        return;
    }
    if (blockHasJump(&func.body)) {
        plan.note(.control_escape);
        return;
    }
    var live = Live.init(alloc);
    defer live.deinit();
    var w: Walk = .{ .alloc = alloc, .opts = opts, .plan = plan, .recording = true };
    try transferBlock(&w, &func.body, &live);
}

/// `goto` or a label anywhere under `b`. `break`/`continue`/`return` are
/// structured and the walk models them; these two are not.
fn blockHasJump(b: *const ast.Block) bool {
    for (b.stmts) |*s| switch (s.*) {
        .goto_stmt, .label_stmt => return true,
        .do_block => |d| if (blockHasJump(&d.body)) return true,
        .while_loop => |wl| if (blockHasJump(&wl.body)) return true,
        .repeat_loop => |r| if (blockHasJump(&r.body)) return true,
        .if_stmt => |f| {
            if (blockHasJump(&f.then)) return true;
            for (f.elseifs) |ei| if (blockHasJump(&ei.body)) return true;
            if (f.else_body) |eb| if (blockHasJump(&eb)) return true;
        },
        .num_for => |n| if (blockHasJump(&n.body)) return true,
        .gen_for => |g| if (blockHasJump(&g.body)) return true,
        else => {},
    };
    return false;
}

/// Demand-analyse every function in a module. Module-scope statements are NOT
/// analysed: a file-scope binding is reachable from outside the module and the
/// walk has no root set that can prove otherwise.
pub fn analyzeModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    opts: Options,
) !Plan {
    var plan = Plan.init(alloc);
    errdefer plan.deinit();

    var globals: std.StringHashMapUnmanaged(void) = .empty;
    defer globals.deinit(alloc);
    try collectModuleNames(alloc, mod, &globals);

    var scoped = opts;
    if (scoped.globals == null) scoped.globals = &globals;

    for (mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        try analyzeFunction(alloc, &s.func_decl.func, scoped, &plan);
    }
    return plan;
}

/// Every name bound at module scope. A function that writes one of these is
/// writing a place outside itself, and `.assign` to a global is textually
/// indistinguishable from `.assign` to a local — this set is the only thing
/// that tells them apart.
pub fn collectModuleNames(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    out: *std.StringHashMapUnmanaged(void),
) !void {
    for (mod.body.stmts) |*s| switch (s.*) {
        .assign => |a| for (a.targets) |t| {
            if (t.* == .name) try out.put(alloc, t.name.ident, {});
        },
        .local_decl => |d| for (d.names) |n| try out.put(alloc, n.ident, {}),
        .global_decl => |d| for (d.names) |n| try out.put(alloc, n.ident, {}),
        .const_decl => |d| try out.put(alloc, d.ident, {}),
        .func_decl => |f| if (f.path.len > 0) try out.put(alloc, f.path[0], {}),
        else => {},
    };
}

/// Delete every statement the plan proved dead, in place.
///
/// Blocks are pruned CHILD-FIRST. Compacting a statement list moves `Stmt`
/// values, which invalidates the pointers the plan is keyed by — but only the
/// pointers into THAT list. A child block's statements live in their own
/// allocation and travel with the moved parent, so recursing before compacting
/// keeps every key valid exactly as long as it is read.
pub fn prune(alloc: std.mem.Allocator, mod: *ast.Module, plan: *const Plan) !void {
    try pruneBlock(alloc, &mod.body, plan);
}

fn pruneBlock(alloc: std.mem.Allocator, b: *ast.Block, plan: *const Plan) std.mem.Allocator.Error!void {
    for (b.stmts) |*s| {
        if (plan.isDead(s)) continue;
        try pruneChildren(alloc, s, plan);
    }

    // A block only needs rebuilding when something is inserted; deletion alone
    // compacts in place, which keeps the common case allocation-free.
    var inserts: usize = 0;
    for (b.stmts) |*s| {
        if (!plan.isDead(s) and plan.breaksAfter(s)) inserts += 1;
    }
    if (inserts == 0) {
        var keep: usize = 0;
        for (b.stmts, 0..) |_, i| {
            if (plan.isDead(&b.stmts[i])) continue;
            if (keep != i) b.stmts[keep] = b.stmts[i];
            keep += 1;
        }
        b.stmts = b.stmts[0..keep];
        return;
    }

    var out = try alloc.alloc(ast.Stmt, b.stmts.len + inserts);
    var k: usize = 0;
    for (b.stmts, 0..) |_, i| {
        const src = &b.stmts[i];
        if (plan.isDead(src)) continue;
        const insert_here = plan.breaksAfter(src);
        const loc = stmtLoc(src);
        out[k] = b.stmts[i];
        k += 1;
        if (insert_here) {
            out[k] = .{ .brk = loc };
            k += 1;
        }
    }
    b.stmts = out[0..k];
}

fn stmtLoc(s: *const ast.Stmt) ast.Loc {
    return switch (s.*) {
        .assign => |a| a.loc,
        .local_decl => |d| d.loc,
        .call_stmt => |c| c.loc,
        .expr_stmt => |c| c.loc,
        else => .{ .file = "", .line = 0, .col = 0 },
    };
}

fn pruneChildren(alloc: std.mem.Allocator, s: *ast.Stmt, plan: *const Plan) std.mem.Allocator.Error!void {
    switch (s.*) {
        .do_block => |*d| try pruneBlock(alloc, &d.body, plan),
        .while_loop => |*w| try pruneBlock(alloc, &w.body, plan),
        .repeat_loop => |*r| try pruneBlock(alloc, &r.body, plan),
        .if_stmt => |*f| {
            try pruneBlock(alloc, &f.then, plan);
            for (f.elseifs) |*ei| try pruneBlock(alloc, &ei.body, plan);
            if (f.else_body) |*eb| try pruneBlock(alloc, eb, plan);
        },
        .num_for => |*n| try pruneBlock(alloc, &n.body, plan),
        .gen_for => |*g| try pruneBlock(alloc, &g.body, plan),
        .func_decl => |*f| try pruneBlock(alloc, &f.func.body, plan),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    mod: ast.Module,

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }
};

fn parse(src: []const u8) !Fixture {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const owned = try alloc.dupe(u8, src);
    var lex = Lexer.init(owned, "demand_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    const mod = try p.parse_module();
    return .{ .arena = arena, .mod = mod };
}

/// Number of statements proven deletable in the first function of `src`.
fn deadCount(src: []const u8) !u32 {
    var fx = try parse(src);
    defer fx.deinit();
    var plan = try analyzeModule(std.testing.allocator, &fx.mod, .{});
    defer plan.deinit();
    return plan.count();
}

/// Number of write sites after which an early exit was proven lawful.
fn earlyExits(src: []const u8) !u32 {
    var fx = try parse(src);
    defer fx.deinit();
    var plan = try analyzeModule(std.testing.allocator, &fx.mod, .{});
    defer plan.deinit();
    return plan.earlyExitCount();
}

test "demand: an unobserved accumulator loop is fully dead" {
    // The floor case. `s` is never read, `i` exists only to drive the loop, and
    // the loop is a counted loop with a literal bound and a +1 step.
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100000
        \\        s += i
        \\        i += 1
        \\    0
        \\
    );
    // s = 0, i = 0, and the whole while.
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: the same loop with its result returned is fully alive" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100000
        \\        s += i
        \\        i += 1
        \\    s & 255
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O4 — an unbounded loop is kept even though nothing reads it" {
    // No update to the counter at all: the loop may not terminate, so deleting
    // it would turn a hang into a return.
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100000
        \\        s += i
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O4 — a step in the wrong direction is refused" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100000
        \\        s += i
        \\        i -= 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O4 — an update nested in a branch proves nothing" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100000
        \\        if s < 5
        \\            i += 1
        \\        s += i
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O4 edge — a loop that never enters still terminates and still dies" {
    // `0 < -5` is false on entry: zero iterations. Termination is trivial, and
    // the elimination must still fire — this is the boundary where a
    // `while n > 0` style guard silently changes the answer.
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < -5
        \\        s += i
        \\        i += 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: O4 edge — a descending loop against a literal floor" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 10
        \\    while i > 0
        \\        s += i
        \\        i -= 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: O4 edge — a one-iteration loop" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 1
        \\        s += 7
        \\        i += 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: O2 — division by a possibly-zero divisor is kept" {
    const n = try deadCount(
        \\main: i64 = (d: i64)
        \\    q = 100 / d
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O2 — division by a non-zero literal is eliminable" {
    const n = try deadCount(
        \\main: i64 = (d: i64)
        \\    q = 100 / 7
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 1), n);
}

test "demand: O2 — division by a zero literal is kept" {
    const n = try deadCount(
        \\main: i64 = (d: i64)
        \\    q = 100 / 0
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O3 — a call with no effect evidence is kept" {
    // No graph is supplied, so the effect card is unavailable, so it reads
    // `unknown`, so it is an effect.
    const n = try deadCount(
        \\f: i64 = (k: i64)
        \\    k * 3
        \\
        \\main: i64 = ()
        \\    q = f(2)
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O5 — a break inside the dead loop keeps it" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 100
        \\        s += i
        \\        i += 1
        \\        break
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O1 — a store through a place is never eliminated" {
    const n = try deadCount(
        \\main: i64 = (t: i64)
        \\    a = { 1, 2, 3 }
        \\    a(1) = 9
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: O1 — a value read only inside a dead region dies with it" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    k = 3
        \\    s = 0
        \\    i = 0
        \\    while i < 10
        \\        s += k
        \\        i += 1
        \\    0
        \\
    );
    // k, s, i and the loop.
    try std.testing.expectEqual(@as(u32, 4), n);
}

test "demand: O1 — a loop whose accumulator IS read keeps everything" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    k = 3
        \\    s = 0
        \\    i = 0
        \\    while i < 10
        \\        s += k
        \\        i += 1
        \\    s
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: a loop writing only unobserved places dies even beside a live producer" {
    // `k` is the answer and survives; the loop writes only `s` and `i`, which
    // nothing downstream reads, so the loop and both of its seeds go.
    const n = try deadCount(
        \\main: i64 = ()
        \\    k = 3
        \\    s = 0
        \\    i = 0
        \\    while i < 10
        \\        s += k
        \\        i += 1
        \\    k
        \\
    );
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: a store to a module-scope global is never dead" {
    // `g = 1` inside `main` and `s = 0` inside `main` are the SAME AST node.
    // Only the module-scope name set separates them; without it this test
    // deletes a global store.
    const n = try deadCount(
        \\g = 7
        \\
        \\main: i64 = ()
        \\    s = 0
        \\    g = 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 1), n);
}

test "demand: a loop that writes a global is never dead" {
    const n = try deadCount(
        \\g = 7
        \\
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        g += i
        \\        i += 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: a closure anywhere in the function refuses the whole function" {
    const n = try deadCount(
        \\main: i64 = (c: i64)
        \\    f = (x: i64) x + 1
        \\    a = c + 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: a dead binding in one branch does not kill the other" {
    const n = try deadCount(
        \\main: i64 = (c: i64)
        \\    x = 0
        \\    if c < 1
        \\        x = 5
        \\    else
        \\        x = 6
        \\    x
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: only the unobserved half of a straight line dies" {
    const n = try deadCount(
        \\main: i64 = (c: i64)
        \\    a = c + 1
        \\    b = c + 2
        \\    a
        \\
    );
    try std.testing.expectEqual(@as(u32, 1), n);
}

test "demand: a chain of dead bindings dies whole" {
    const n = try deadCount(
        \\main: i64 = (c: i64)
        \\    a = c + 1
        \\    b = a + 2
        \\    d = b + 3
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 3), n);
}

test "demand: a trip proof is refused when the bound is not a literal" {
    const n = try deadCount(
        \\main: i64 = (n: i64)
        \\    s = 0
        \\    i = 0
        \\    while i < n
        \\        s += i
        \\        i += 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: a trip proof is refused at the overflow boundary" {
    var fx = try parse(
        \\main: i64 = ()
        \\    s = 0
        \\    i = 0
        \\    while i < 9223372036854775807
        \\        s += i
        \\        i += 1
        \\    0
        \\
    );
    defer fx.deinit();
    var plan = try analyzeModule(std.testing.allocator, &fx.mod, .{});
    defer plan.deinit();
    // `limit + step` would wrap, so no proof, so the loop survives — and with it
    // both of its inputs.
    try std.testing.expectEqual(@as(u32, 0), plan.count());
}

test "demand: two counter updates give no single trip count" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i += 1
        \\        i += 1
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: a zero step is refused" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i += 0
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: empty function body analyses to nothing dead" {
    const n = try deadCount(
        \\main: i64 = ()
        \\    0
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}


// --- the second candidate --------------------------------------------------

test "demand: exists — the loop stops at the first witness" {
    // `found` is written only as the literal 1, never read inside the loop, and
    // is the only place the loop writes that survives to the exit. The loop's
    // answer is final at the first write.
    const n = try earlyExits(
        \\main: i64 = ()
        \\    found = 0
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            found = 1
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 1), n);
}

test "demand: exists E1 — two different literals are not idempotent" {
    const n = try earlyExits(
        \\main: i64 = ()
        \\    found = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i == 3
        \\            found = 1
        \\        if i == 9
        \\            found = 2
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists E1 — the same literal twice is still idempotent" {
    const n = try earlyExits(
        \\main: i64 = ()
        \\    found = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i == 3
        \\            found = 1
        \\        if i == 9
        \\            found = 1
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 2), n);
}

test "demand: exists E2 — an accumulator read by the loop is not a witness flag" {
    // `n += 1` reads `n`, so the number of iterations IS observable through it.
    const n = try earlyExits(
        \\main: i64 = ()
        \\    total = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i == 3
        \\            total = 1
        \\        total += 1
        \\        i += 1
        \\    total
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists E3 — two observed places leave no single fixpoint" {
    const n = try earlyExits(
        \\main: i64 = ()
        \\    found = 0
        \\    last = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i == 3
        \\            found = 1
        \\        last = i
        \\        i += 1
        \\    found + last
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists E5 — no trip proof, no early exit" {
    const n = try earlyExits(
        \\main: i64 = (b: i64)
        \\    found = 0
        \\    i = 0
        \\    while i < b
        \\        if i == 3
        \\            found = 1
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists E6 — a write inside a nested loop would break the wrong loop" {
    const n = try earlyExits(
        \\main: i64 = ()
        \\    found = 0
        \\    i = 0
        \\    while i < 10
        \\        j = 0
        \\        while j < 10
        \\            if j == 3
        \\                found = 1
        \\            j += 1
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists E4 — a body that can trap keeps every iteration" {
    const n = try earlyExits(
        \\main: i64 = (d: i64)
        \\    found = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i / d == 3
        \\            found = 1
        \\        i += 1
        \\    found
        \\
    );
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "demand: exists — a wholly dead loop is eliminated, not truncated" {
    // The elimination candidate strictly dominates the truncation candidate,
    // so the two must not both fire on the same loop.
    var fx = try parse(
        \\main: i64 = ()
        \\    found = 0
        \\    i = 0
        \\    while i < 1000
        \\        if i == 3
        \\            found = 1
        \\        i += 1
        \\    0
        \\
    );
    defer fx.deinit();
    var plan = try analyzeModule(std.testing.allocator, &fx.mod, .{});
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 3), plan.count());
    try std.testing.expectEqual(@as(u32, 0), plan.earlyExitCount());
}
