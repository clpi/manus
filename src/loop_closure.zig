//! LOOP-LEVEL CLOSURE — the consumer `src/recurrence.zig` did not have.
//!
//! `recurrence.zig` implements TWO closure families and until now exactly one
//! call site reached either of them:
//!
//!     A. OPERATOR POWERING (`closeWhile`) — assumes nothing but O1-O8,
//!        answers ALL 64 bits, needs NO demand fact.
//!     B. OBSERVATION ORBIT (`closeWhileByOrbit`) — assumes O9, a demand fact
//!        the caller supplies, answers only the demanded bits.
//!
//! The one site is `obseq.closeRelation`, which reaches B's driver
//! (`recurrence.closeRelationBodyObserved`) only when the CONTRACTED orbit is
//! periodic, and only after `obseq.readMachine` has accepted the WHOLE relation
//! body as `[int-literal prologue][one while][tail expression]`. That is a
//! SHAPE guard, and `docs/inert-projection-census.md` §7.F1 measured what it
//! costs: of 152 corpus `main`s with a loop, **46 read a loop-carried value
//! only AFTER the loop** — a full-width closed form is perfectly lawful for
//! every one of them — and all 46 are refused because `main` contains a
//! `print`. `recurrence.closeRelationBody`, the unobserved entry point, had
//! ZERO callers including tests.
//!
//! THIS FILE IS THE OTHER DOOR. It asks the closure question of a LOOP rather
//! than of a RELATION BODY, so a loop inside a relation that also does I/O can
//! be replaced while the I/O is preserved, in its original order.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHY THIS IS LAWFUL, AND WHERE EACH OBLIGATION IS DISCHARGED
//! ════════════════════════════════════════════════════════════════════════════
//!
//! Replacing a loop by its live-out values claims: for every reachable entry
//! state the two agree on (a) every live-out, (b) observable effects and their
//! order, (c) termination, (d) traps. Nothing here re-proves any of that —
//! `recurrence.closeWhile` owns O1-O8 and this file owns only the obligations
//! that are about the loop's SURROUNDINGS rather than its body, plus L6, which
//! is about the BLOCK that contains it:
//!
//!   L1 ENTRY CONSTANCY. Every name the loop reads must hold a value this pass
//!      knows exactly at the loop head. Only a literal prologue supplies one;
//!      any statement whose effect on a name this pass cannot follow makes that
//!      name UNKNOWN, and an unknown name is simply absent from `Bindings`, on
//!      which `recurrence.polyOfExpr` refuses. FAILS CLOSED BY OMISSION.
//!
//!   L2 THE RING IS THE RING. `recurrence` computes in Z/2^64. A local declared
//!      `x: u8` is stored through `dnir_lower.narrow_slots` and truncates on
//!      EVERY assignment, so the real loop runs a different machine and the
//!      closed form would be a silent wrong answer. Any name in the body's
//!      declaration set whose type is not `inferred` or `i64` — and every
//!      PARAMETER, whose entry value is not a constant anyway — poisons the
//!      loop. This obligation does not exist for `obseq`, whose answer is taken
//!      mod 2^8 either way; it exists here because this family answers all 64
//!      bits.
//!
//!   L3 NO NEW BINDING. Only a name that already held a known value BEFORE the
//!      loop is written back. A body temporary (`t = a + b ; a = b ; b = t`)
//!      that `closeWhile` admits via `entryValueIsDead` would need a binding at
//!      the OUTER scope that the source never wrote, so the whole loop is
//!      refused rather than half-closed.
//!
//!   L4 THE WRITE-BACK IS WHAT DEMAND DECIDES. `closeWhile` answers every
//!      live-out (O6); the CONTINUATION decides which of them anybody can see.
//!      `demand_projection.projectionOfName` — the one authority on
//!      `h(f(x)) = g(h(x))` in this tree — is asked, per name, over every
//!      expression that can still run, and a name whose demanded projection is
//!      `none` is not written at all. That is the demand-produced projection
//!      being causally operative at the loop level: on `s = s + i` under
//!      `print(s)` it deletes the induction variable's exit store, because
//!      nothing observes it.
//!
//!   L6 THE BLOCK'S VALUE IS NOT THE LOOP'S. A `while` carries no block value;
//!      the store written in its slot must carry none either, or the program's
//!      EXIT STATUS moves while its stdout does not. See `constantAssign` —
//!      GAP-215. The only obligation here that is about the ENCLOSING BLOCK
//!      rather than about the loop or the statements around it.
//!
//! WHAT IS DELIBERATELY NOT CLAIMED. The demand projection does NOT license the
//! closure here — family A needs no demand fact and answers exactly, so
//! `h ∘ f = g ∘ h` holds with `h` the identity. Demand only removes STORES.
//! Family B, which genuinely trades width for a closed form, stays where it is:
//! `obseq` owns the entry-level observation and this file does not reimplement
//! it. TWO PROOFS OF ONE FACT IS THE FAILURE `demand.zig` names, and a
//! narrow-observation closure derived here would be exactly that.
//!
//! FAILS CLOSED EVERYWHERE. Every path leaves the loop alone on the first thing
//! it cannot prove, and the AST it writes is ordinary assignment statements the
//! backend could have been given — the same discipline `demand.prune` states
//! for its synthesised `break`.

const std = @import("std");
const ast = @import("ast.zig");
const recurrence = @import("recurrence.zig");
const demand_projection = @import("demand_projection.zig");
const comptime_eval = @import("comptime.zig");
const demand = @import("demand.zig");

/// Names tracked in the entry environment. `recurrence.Bindings` holds 32 and
/// there is no point tracking more than it can carry.
pub const max_env = 32;
/// Loops replaced in ONE relation body. A body with more closable top-level
/// loops than this keeps the extras; nothing is refused for the wrong reason.
pub const max_plan = 8;
/// Declared names whose type takes them out of the full ring (L2), plus the
/// relation's parameters. Overflow refuses the whole body.
pub const max_poison = 64;

pub const Census = struct {
    bodies_examined: u32 = 0,
    loops_seen: u32 = 0,
    loops_closed: u32 = 0,
    /// Live-out stores actually emitted.
    writes_emitted: u32 = 0,
    /// Live-out stores DELETED because `projectionOfName` answered `none`.
    writes_deleted_by_demand: u32 = 0,
    /// A closed loop refused because a live-out had no binding before it (L3).
    refused_new_binding: u32 = 0,
    /// A closed loop refused because a live-out is not in the full ring (L2).
    refused_narrow: u32 = 0,
    /// A closed loop DECLINED because the comptime evaluator already answers
    /// the whole relation (L5).
    declined_to_fold: u32 = 0,
    /// A closed FILE-SCOPE loop refused because replacing it would need a
    /// number of stores other than one, and any other number moves a `Stmt`
    /// whose address the graph already holds (W5).
    refused_would_move: u32 = 0,
};

// ── L1: the entry environment ────────────────────────────────────────────────

/// Names and their exact values at the current point of the statement walk.
/// A name is here with `known = false` once anything this pass cannot follow
/// could have changed it, and a name that is not `known` is never handed to
/// `recurrence` — which is what makes L1 an omission rather than a check.
const Env = struct {
    names: [max_env][]const u8 = undefined,
    vals: [max_env]u64 = undefined,
    known: [max_env]bool = @splat(false),
    len: usize = 0,

    fn indexOf(self: *const Env, name: []const u8) ?usize {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return i;
        }
        return null;
    }

    fn set(self: *Env, name: []const u8, v: u64) void {
        if (self.indexOf(name)) |i| {
            self.vals[i] = v;
            self.known[i] = true;
            return;
        }
        if (self.len == max_env) return; // not recorded is not known — sound.
        self.names[self.len] = name;
        self.vals[self.len] = v;
        self.known[self.len] = true;
        self.len += 1;
    }

    fn kill(self: *Env, name: []const u8) void {
        if (self.indexOf(name)) |i| self.known[i] = false;
    }

    fn killAll(self: *Env) void {
        for (0..self.len) |i| self.known[i] = false;
    }

    fn isKnown(self: *const Env, name: []const u8) bool {
        const i = self.indexOf(name) orelse return false;
        return self.known[i];
    }

    fn bindings(self: *const Env) recurrence.Bindings {
        var b = recurrence.Bindings{};
        for (0..self.len) |i| {
            if (!self.known[i]) continue;
            if (!b.put(self.names[i], self.vals[i])) break;
        }
        return b;
    }
};

/// A prologue initializer this pass reads exactly. DELIBERATELY LITERAL ONLY.
///
/// `recurrence.polyOfExpr` already owns the ring algebra and re-deriving even
/// `12344 + 1` here would be a second implementation of it. What this reads is
/// a literal, a negated literal, or a name already proven constant — nothing
/// that could disagree with the engine, because nothing arithmetic happens.
fn literalOf(e: *const ast.Expr, env: *const Env) ?u64 {
    return switch (e.*) {
        .int_lit => |x| @bitCast(x.val),
        .name => |n| blk: {
            const i = env.indexOf(n.ident) orelse break :blk null;
            if (!env.known[i]) break :blk null;
            break :blk env.vals[i];
        },
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const inner = literalOf(u.operand, env) orelse break :blk null;
                break :blk 0 -% inner;
            },
            else => null,
        },
        else => null,
    };
}

// ── L2: the ring ─────────────────────────────────────────────────────────────

/// A binding whose stores are the ring's stores. `inferred` and `i64` only:
/// everything else either truncates (`u8`, `i32`, `u32`), is not an integer
/// (`f64`, `str`, `bool`), or is a place this pass has no business touching.
fn typeIsFullRing(t: ast.TypeExpr) bool {
    return switch (t) {
        .inferred => true,
        .named => |n| std.mem.eql(u8, n, "i64"),
        else => false,
    };
}

const Poison = struct {
    names: [max_poison][]const u8 = undefined,
    len: usize = 0,
    overflowed: bool = false,

    fn add(self: *Poison, name: []const u8) void {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return;
        }
        if (self.len == max_poison) {
            self.overflowed = true;
            return;
        }
        self.names[self.len] = name;
        self.len += 1;
    }

    fn has(self: *const Poison, name: []const u8) bool {
        if (self.overflowed) return true;
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return true;
        }
        return false;
    }
};

/// Every name in this body whose stores are NOT the ring's stores. Walks the
/// WHOLE body including nested blocks, because a declaration anywhere in the
/// relation decides how a store to that name is realized.
fn collectPoison(fb: *const ast.FuncBody, out: *Poison) void {
    for (fb.params) |p| out.add(p.name);
    if (fb.vararg_name) |v| out.add(v);
    poisonBlock(&fb.body, out);
}

fn poisonBlock(b: *const ast.Block, out: *Poison) void {
    for (b.stmts) |*st| poisonStmt(st, out);
}

fn poisonStmt(st: *const ast.Stmt, out: *Poison) void {
    switch (st.*) {
        .local_decl => |d| for (d.names) |n| {
            if (!typeIsFullRing(n.typ)) out.add(n.ident);
        },
        .global_decl => |d| for (d.names) |n| {
            if (!typeIsFullRing(n.typ)) out.add(n.ident);
        },
        .const_decl => |d| if (!typeIsFullRing(d.typ)) out.add(d.ident),
        .while_loop => |w| poisonBlock(&w.body, out),
        .repeat_loop => |r| poisonBlock(&r.body, out),
        .do_block => |d| poisonBlock(&d.body, out),
        .if_stmt => |s| {
            poisonBlock(&s.then, out);
            for (s.elseifs) |ei| poisonBlock(&ei.body, out);
            if (s.else_body) |*eb| poisonBlock(eb, out);
        },
        .num_for => |f| {
            if (!typeIsFullRing(f.var_typ)) out.add(f.var_name);
            poisonBlock(&f.body, out);
        },
        .gen_for => |f| {
            for (f.vars) |v| out.add(v);
            poisonBlock(&f.body, out);
        },
        // A nested relation may capture and rebind anything; refuse the whole
        // body rather than model capture.
        .func_decl => out.overflowed = true,
        else => {},
    }
}

// ── L4: what the continuation can still see ──────────────────────────────────
//
// `demand_projection.projectionOfName` is the ONE authority on the demand
// derivative and it answers about ONE EXPRESSION. What is written here is a
// traversal that reaches it for every expression that can still run — not a
// second derivative. Every statement form not enumerated answers `whole`, so an
// unmodelled construct keeps the store rather than deleting it.

fn demandOfNameInBlock(b: *const ast.Block, name: []const u8) demand_projection.Projection {
    var acc: demand_projection.Projection = .none;
    for (b.stmts) |*st| {
        acc = demand_projection.Projection.join(acc, demandOfNameInStmt(st, name));
        if (acc == .whole) return .whole;
    }
    if (b.tail_expr) |t| {
        acc = demand_projection.Projection.join(acc, demand_projection.projectionOfName(.whole, t, name));
    }
    return acc;
}

fn demandOfNameInStmt(st: *const ast.Stmt, name: []const u8) demand_projection.Projection {
    const P = demand_projection.Projection;
    switch (st.*) {
        .brk, .cont, .label_stmt, .goto_stmt => return .none,
        .local_decl => |d| {
            var acc: P = .none;
            for (d.inits) |e| acc = P.join(acc, demand_projection.projectionOfName(.whole, e, name));
            return acc;
        },
        .assign => |a| {
            var acc: P = .none;
            for (a.values) |e| acc = P.join(acc, demand_projection.projectionOfName(.whole, e, name));
            // A target that is NOT a bare name is a place expression and READS
            // the names inside it (`t(i) = v` reads `i`).
            for (a.targets) |t| {
                if (t.* == .name) continue;
                acc = P.join(acc, demand_projection.projectionOfName(.whole, t, name));
            }
            return acc;
        },
        .expr_stmt => |e| return demand_projection.projectionOfName(.whole, e.expr, name),
        .call_stmt => |c| return demand_projection.projectionOfName(.whole, c.expr, name),
        .ret => |r| {
            var acc: P = .none;
            for (r.vals) |e| acc = P.join(acc, demand_projection.projectionOfName(.whole, e, name));
            return acc;
        },
        .while_loop => |w| return P.join(
            demand_projection.projectionOfName(.whole, w.cond, name),
            demandOfNameInBlock(&w.body, name),
        ),
        .repeat_loop => |r| return P.join(
            demand_projection.projectionOfName(.whole, r.cond, name),
            demandOfNameInBlock(&r.body, name),
        ),
        .do_block => |d| return demandOfNameInBlock(&d.body, name),
        .if_stmt => |s| {
            var acc = demand_projection.projectionOfName(.whole, s.cond, name);
            if (s.binding) |bind| acc = P.join(acc, demand_projection.projectionOfName(.whole, bind.expr, name));
            acc = P.join(acc, demandOfNameInBlock(&s.then, name));
            for (s.elseifs) |ei| {
                acc = P.join(acc, demand_projection.projectionOfName(.whole, ei.cond, name));
                acc = P.join(acc, demandOfNameInBlock(&ei.body, name));
            }
            if (s.else_body) |*eb| acc = P.join(acc, demandOfNameInBlock(eb, name));
            return acc;
        },
        .num_for => |f| {
            var acc = demand_projection.projectionOfName(.whole, f.start, name);
            acc = P.join(acc, demand_projection.projectionOfName(.whole, f.stop, name));
            if (f.step) |s| acc = P.join(acc, demand_projection.projectionOfName(.whole, s, name));
            return P.join(acc, demandOfNameInBlock(&f.body, name));
        },
        // FAIL CLOSED. `func_decl` can capture, `gen_for` iterates a value this
        // does not model, and anything added later arrives here.
        else => return .whole,
    }
}

/// Demand of `name` over everything that can still run after statement `from`
/// in `b`, INCLUDING the block's tail expression.
fn demandAfter(b: *const ast.Block, from: usize, name: []const u8) demand_projection.Projection {
    const P = demand_projection.Projection;
    var acc: P = .none;
    var i = from + 1;
    while (i < b.stmts.len) : (i += 1) {
        acc = P.join(acc, demandOfNameInStmt(&b.stmts[i], name));
        if (acc == .whole) return .whole;
    }
    if (b.tail_expr) |t| {
        acc = P.join(acc, demand_projection.projectionOfName(.whole, t, name));
    }
    return acc;
}

// ── THE PASS ─────────────────────────────────────────────────────────────────

const Plan = struct {
    /// Index into the body's top-level statement list.
    at: usize,
    closed: recurrence.Closed,
    /// Per live-out: whether the continuation can see it.
    write: [recurrence.max_vars]bool,
};

/// W — the fifth input of `T: (S,F,D,W,H)`, and the ONE thing this pass cannot
/// infer. Supplied by the caller that knows the emit kind, exactly as
/// `demand.Options.world_closed` is, and DEFAULTING TO FALSE so a dylib or an
/// object -- artifacts that exist to be read from outside -- keep their module
/// scope untouched unless a caller deliberately says otherwise.
pub const Options = struct {
    /// W1. For a native EXECUTABLE the image is the whole world: nothing
    /// outside it can name a module-level binding, which is what makes the
    /// FILE-SCOPE TAIL analysable. `demand.zig` states the same obligation for
    /// the same region and the same caller sets both.
    world_closed: bool = false,
};

/// Replace every closable top-level `while` in every relation of `mod` with the
/// values its live-outs provably hold when it ends.
pub fn applyToModule(alloc: std.mem.Allocator, mod: *ast.Module) !Census {
    return applyToModuleObserved(alloc, mod, .{});
}

/// The same, plus the FILE-SCOPE TAIL when `W` admits it.
///
/// MODULE SCOPE USED TO BE REFUSED OUTRIGHT, and the refusal inverted the
/// project's own deliverable in the same way `demand.zig`'s header records for
/// the same region. MEASURED at b64dc075, the identical statements `s = s + i`
/// over 10^9 trips with the answer PRINTED, best of eleven:
///
///     inside a relation body   0.0037s   the loop is a constant
///     at module top level      0.3657s   the loop is a loop
///     clang -O3                0.0031s
///
/// 98.8x, from moving the same statements into a function. The engine that
/// closes the first one is this file; it simply never reached the second,
/// because `applyToModule` descended into `.func_decl` and nothing else.
///
/// THREE OBLIGATIONS ARE ADDED, and none of them is new law -- each is the one
/// `demand.analyzeModuleBody` already discharges for the same rewrite of the
/// same statement list:
///
///   W1 CLOSED WORLD. `opts.world_closed`. Not inferred here.
///
///   W2 NO DEFERRED READER. A module binding mentioned -- read OR written -- by
///      code this walk cannot place (a relation body, an alias method, a macro,
///      a `defer`, any closure) is POISONED, so no loop carrying it is closed
///      and no store to it is touched. The fact comes from
///      `demand.deferredMentionsBlock`, which is its ONE producer; a second
///      implementation of "which module bindings escape" is exactly the
///      disagreement that ships a wrong answer. An unenumerable shape makes
///      that call answer false and refuses the whole module body.
///
///   W5 NO POINTER MOVED. See `Scope.in_place`.
///
/// W3 (no export) and W4 (enumerable) are discharged structurally: a
/// `func_decl` is never rewritten by this pass, and W2's collector answers
/// false on exactly the shapes W4 refuses.
///
/// L4 IS WHAT MAKES THE MODULE REWRITE FIT, and that is not a convenience. W5
/// admits exactly one statement in the `while`'s slot; a counted loop has TWO
/// live-outs, the accumulator and the induction variable. It is
/// `demand_projection.projectionOfName` answering `none` for the induction
/// variable -- nothing after the loop reads `i` -- that takes two stores down
/// to one and lets the loop be replaced at all. Without the demand fact this
/// transform does not fit in its own slot.
///
/// AND THE DEMAND ANSWER IS EXACT HERE, WHICH IT IS NOT INSIDE A RELATION. A
/// module name a relation could read escapes the block walk, so inside a
/// relation `module_names.has` keeps the store unasked. At module scope every
/// such name is already POISONED by W2, so a loop that reaches L4 carries only
/// names whose complete reader set is the rest of the module body -- which is
/// precisely what `demandAfter` walks.
pub fn applyToModuleObserved(alloc: std.mem.Allocator, mod: *ast.Module, opts: Options) !Census {
    var census = Census{};
    var module_names: Poison = .{};
    for (mod.body.stmts) |*st| switch (st.*) {
        .local_decl => |d| for (d.names) |n| module_names.add(n.ident),
        .global_decl => |d| for (d.names) |n| module_names.add(n.ident),
        .const_decl => |d| module_names.add(d.ident),
        .assign => |a| for (a.targets) |t| {
            if (t.* == .name) module_names.add(t.name.ident);
        },
        else => {},
    };
    for (mod.body.stmts) |*st| {
        if (st.* != .func_decl) continue;
        try applyToFuncBody(alloc, &st.func_decl.func, &module_names, &census);
    }
    if (opts.world_closed) try applyToModuleBody(alloc, mod, &module_names, &census);
    return census;
}

/// The file-scope tail, under W1/W2/W5. See `applyToModuleObserved`.
fn applyToModuleBody(
    alloc: std.mem.Allocator,
    mod: *ast.Module,
    module_names: *const Poison,
    census: *Census,
) !void {
    census.bodies_examined += 1;

    // W2, from its one producer. `false` means a shape whose mentions cannot be
    // enumerated -- a `@build` directive, a `goto` -- and refuses the body.
    var escapes = demand.Live.init(alloc);
    defer escapes.deinit();
    if (!try demand.deferredMentionsBlock(&escapes, &mod.body)) return;

    var poison: Poison = .{};
    modulePoison(&mod.body, &escapes, &poison);
    if (poison.overflowed) return;

    try closeLoopsIn(alloc, &mod.body, &poison, module_names, .{
        // L5 does not apply: `comptime.foldRelationBody` answers about a
        // RELATION body and nothing in this tree dispatches it on the module
        // body. MEASURED at b64dc075 -- a three-trip file-scope loop emits the
        // loop, where the same loop inside `main: i64 = ()` emits `mov x0, #6`.
        // Declining here would defer to a mechanism that is not there.
        .fold_candidate = false,
        .in_place = true,
        .module_scope = true,
    }, census);
}

/// L2 at module scope, plus W2.
///
/// `collectPoison` refuses any body containing a `func_decl` outright, because
/// inside a RELATION a nested one can capture and rebind and nothing here
/// models capture. At MODULE scope that refusal would reject every program with
/// a helper, and it is also unnecessary: `demand.deferredMentionsBlock` has
/// already collected every module binding such code mentions, so the names that
/// would have been unsound are poisoned by name instead of by region.
fn modulePoison(b: *const ast.Block, escapes: *const demand.Live, out: *Poison) void {
    for (b.stmts) |*st| modulePoisonStmt(st, out);
    var it = escapes.set.keyIterator();
    while (it.next()) |k| out.add(k.*);
}

fn modulePoisonStmt(st: *const ast.Stmt, out: *Poison) void {
    switch (st.*) {
        // Its mentions are already in the escape set; its own locals are its
        // own scope and cannot be a module-scope loop's carried name.
        .func_decl, .alias_def, .macro_def => {},
        .while_loop => |w| modulePoison2(&w.body, out),
        .repeat_loop => |r| modulePoison2(&r.body, out),
        .do_block => |d| modulePoison2(&d.body, out),
        .if_stmt => |x| {
            modulePoison2(&x.then, out);
            for (x.elseifs) |ei| modulePoison2(&ei.body, out);
            if (x.else_body) |*eb| modulePoison2(eb, out);
        },
        else => poisonStmt(st, out),
    }
}

fn modulePoison2(b: *const ast.Block, out: *Poison) void {
    for (b.stmts) |*st| modulePoisonStmt(st, out);
}

fn applyToFuncBody(
    alloc: std.mem.Allocator,
    fb: *ast.FuncBody,
    module_names: *const Poison,
    census: *Census,
) !void {
    census.bodies_examined += 1;

    var poison: Poison = .{};
    collectPoison(fb, &poison);
    if (poison.overflowed) return;

    try closeLoopsIn(alloc, &fb.body, &poison, module_names, .{
        // L5's seam is `comptime.foldRelationBody`, which answers about a
        // RELATION. Only a zero-operand relation can reach its `bodyHasLoop`
        // dispatch, so only one can be pre-empted by it.
        .fold_candidate = fb.params.len == 0 and !fb.vararg and fb.vararg_name == null,
        .in_place = false,
        .module_scope = false,
    }, census);
}

/// What the enclosing region is, for the two obligations that are about the
/// REGION rather than about the loop. Neither is inferred here: a caller that
/// knows which region it holds supplies both, exactly as `demand.Options`
/// carries `world_closed` from the one site that knows the emit kind.
const Scope = struct {
    /// L5. True only for a body `comptime.foldRelationBody` could answer whole,
    /// which is a zero-operand RELATION and never a module body -- no folder in
    /// this tree dispatches on the module body, so deferring to one there would
    /// defer to a mechanism that does not exist.
    fold_candidate: bool,
    /// W5, AND THE FIRST FORM OF THIS PATCH GOT IT WRONG IN A WAY THAT BUILT.
    ///
    /// `semantic_graph` holds the ADDRESS of the `FuncDecl`/`AliasDef`/`EnumDef`
    /// stored BY VALUE inside three module-scope `Stmt`s, from a lift that
    /// already happened. The relation path REBUILDS the statement list into a
    /// fresh allocation, which moves EVERY statement -- not merely those after
    /// the hole -- so an index floor does not discharge this. MEASURED: with a
    /// floor and a rebuild, a module whose helper is declared BEFORE a closable
    /// file-scope loop refused with `DNB011 missing-function-id` at
    /// `dnir_lower.zig:1230`, which is that dangling `*FuncDecl` arriving.
    ///
    /// So the module path does not rebuild. It OVERWRITES the `while` slot with
    /// the one store demand leaves, one statement for one statement, and a plan
    /// that would need any other number of stores is refused. Nothing moves, so
    /// W5 is discharged by the shape of the write rather than by a check.
    in_place: bool,
    /// L4's completeness condition. Inside a RELATION a module-scope name is
    /// readable outside the body, so the body's continuation does not bound it
    /// and the store is kept. AT MODULE SCOPE the continuation is the rest of
    /// the module body, and everything else that could read the name is
    /// deferred code -- whose mentions are ALREADY POISONED by W2, so a loop
    /// that got this far carries no name any deferred reader can see. The two
    /// together are the whole program, so `demandAfter` is exact here.
    module_scope: bool,
};

fn closeLoopsIn(
    alloc: std.mem.Allocator,
    body: *ast.Block,
    poison: *const Poison,
    module_names: *const Poison,
    scope: Scope,
    census: *Census,
) !void {
    const fb_body = body;

    var env = Env{};
    var plans: [max_plan]Plan = undefined;
    var nplans: usize = 0;

    for (fb_body.stmts, 0..) |*st, idx| {
        switch (st.*) {
            .local_decl => |d| {
                if (d.names.len != d.inits.len) {
                    env.killAll();
                    continue;
                }
                for (d.names, d.inits) |n, init| {
                    if (poison.has(n.ident)) {
                        env.kill(n.ident);
                        continue;
                    }
                    if (literalOf(init, &env)) |v| env.set(n.ident, v) else env.kill(n.ident);
                }
            },
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1 or a.targets[0].* != .name) {
                    // A multi-target assignment or a place store: this pass does
                    // not follow either, so nothing it knew survives it.
                    env.killAll();
                    continue;
                }
                const nm = a.targets[0].name.ident;
                if (poison.has(nm)) {
                    env.kill(nm);
                    continue;
                }
                if (literalOf(a.values[0], &env)) |v| env.set(nm, v) else env.kill(nm);
            },
            .while_loop => |w| {
                census.loops_seen += 1;
                const closed = recurrence.closeWhile(w, env.bindings()) orelse {
                    // The loop ran and this pass cannot say what it did.
                    env.killAll();
                    continue;
                };

                // L2 FIRST, AND OVER EVERY LOOP-CARRIED NAME, written back or
                // not: a name whose stores truncate makes the whole closed
                // computation a different machine, not merely an unwritable
                // result.
                var narrow = false;
                for (0..closed.len) |i| {
                    if (poison.has(closed.names[i])) narrow = true;
                }
                if (narrow) {
                    census.refused_narrow += 1;
                    env.killAll();
                    continue;
                }

                // L4 BEFORE L3, and the order is load-bearing. `demand.prune`
                // runs ahead of this pass and DELETES a prologue binding whose
                // entry value is dead — which is exactly the `t = 0` an order-k
                // recurrence needs — so asking L3 about a name nobody writes
                // back would refuse the whole order-k family for a binding the
                // transform does not need. Only a name this pass actually
                // STORES has to have existed before the loop.
                var plan = Plan{ .at = idx, .closed = closed, .write = @splat(true) };
                for (0..closed.len) |i| {
                    // A module-scope name is readable outside this relation, so
                    // the continuation of the BODY does not bound it. AT module
                    // scope that continuation IS the bound -- see
                    // `Scope.module_scope`.
                    if (!scope.module_scope and module_names.has(closed.names[i])) continue;
                    const d = demandAfter(fb_body, idx, closed.names[i]);
                    if (d == .none) plan.write[i] = false;
                }

                // L3. A written-back name that held no known value before the
                // loop would need a binding at the OUTER scope the source never
                // wrote.
                var unbound = false;
                for (0..closed.len) |i| {
                    if (plan.write[i] and !env.isKnown(closed.names[i])) unbound = true;
                }
                if (unbound) {
                    census.refused_new_binding += 1;
                    env.killAll();
                    continue;
                }

                // The values are exact whether or not the loop is replaced, so
                // the environment learns them either way.
                for (0..closed.len) |i| env.set(closed.names[i], closed.values[i]);

                // L5 — DO NOT PRE-EMPT A STRONGER MECHANISM. MEASURED, and it
                // is the reason this clause exists rather than a precaution:
                // `examples/native_differential/i7_while.id` is a 3-trip loop
                // in a zero-operand `main`, and `comptime.foldRelationBody`
                // already answers the WHOLE relation — `_main` is `mov x0, #6 ;
                // ret`. Replacing the loop with its live-out took it to SIX
                // instructions, because `foldRelationBody` dispatches on
                // `bodyHasLoop`: a body WITH a loop gets the full evaluator, a
                // body WITHOUT one gets `constantAnswer`, which reads a bare
                // literal tail and nothing else. So DELETING THE LOOP DOWNGRADED
                // THE BODY ONTO A WEAKER FOLDER — one instruction became three.
                // That is `HPLS.md` §2 monotonicity violated by this pass, and
                // it was the only emitted-code difference in a 1,015-file
                // corpus differential.
                //
                // The partition is the one `recurrence.zig`'s own header
                // states: the evaluator's budget "stops a 1e9-iteration loop at
                // 16,665 steps, and a closed form takes zero steps". Below the
                // budget the evaluator answers the whole relation and is
                // strictly stronger; above it, it cannot run at all and this
                // pass is the only mechanism. `comptime.fold_step_limit` is the
                // seam and it is READ, not copied, so the two cannot drift.
                //
                // The bound is on TRIPS alone, which is deliberately generous:
                // an iteration costs the evaluator at least one step, so
                // `trips >= fold_step_limit` PROVES the budget was exceeded.
                // Below it the evaluator may still refuse for its own reasons
                // (an effect in the relation, an unbound name) and this pass
                // then declines a loop nobody closes — which costs at most
                // `fold_step_limit` iterations of work, well under the ~10M
                // instruction cost of the process that would run it.
                // `bodyHasNoApplication` is the exact door: `foldRelationBody`
                // only reaches the `bodyHasLoop` dispatch for a body that
                // applies nothing. A body that DOES apply something — every
                // `main` with a `print` after its loop, which is the family
                // this pass exists for — goes to the graph/effect-closure path
                // instead, where no `bodyHasLoop` gate exists and deleting the
                // loop downgrades nothing.
                if (scope.fold_candidate and
                    comptime_eval.bodyHasNoApplication(fb_body) and
                    closed.trips < comptime_eval.fold_step_limit)
                {
                    census.declined_to_fold += 1;
                    continue;
                }
                // W5. One statement for one statement, or nothing.
                if (scope.in_place) {
                    var stores: usize = 0;
                    for (0..closed.len) |i| {
                        if (plan.write[i]) stores += 1;
                    }
                    if (stores != 1) {
                        census.refused_would_move += 1;
                        continue;
                    }
                }
                if (nplans == max_plan) continue;
                plans[nplans] = plan;
                nplans += 1;
                census.loops_closed += 1;
            },
            else => env.killAll(),
        }
    }

    if (nplans == 0) return;

    if (scope.in_place) {
        // W5. Exactly one store per plan, written over the `while` it replaces.
        for (plans[0..nplans]) |p| {
            const loc = fb_body.stmts[p.at].while_loop.loc;
            for (0..p.closed.len) |j| {
                if (!p.write[j]) continue;
                fb_body.stmts[p.at] = try constantAssign(alloc, loc, p.closed.names[j], p.closed.values[j]);
                census.writes_emitted += 1;
                break;
            }
            census.writes_deleted_by_demand += @intCast(p.closed.len - 1);
        }
        return;
    }

    // THE OUTPUT LENGTH IS COMPUTED, NEVER ADJUSTED. An earlier form of this
    // accumulated `+writes` then `-1` per plan, which UNDERFLOWS a usize the
    // moment a loop's live-outs are all demand-dead — and that case is exactly
    // the one this pass exists for, a loop `demand` could not prove terminating
    // and this one can. In ReleaseFast the underflow is a silent 2^64 alloc.
    var writes_total: usize = 0;
    for (plans[0..nplans]) |p| {
        var w: usize = 0;
        for (0..p.closed.len) |i| {
            if (p.write[i]) w += 1;
        }
        writes_total += w;
        census.writes_emitted += @intCast(w);
        census.writes_deleted_by_demand += @intCast(p.closed.len - w);
    }

    const out = try alloc.alloc(ast.Stmt, fb_body.stmts.len - nplans + writes_total);
    var k: usize = 0;
    var next_plan: usize = 0;
    for (fb_body.stmts, 0..) |src, i| {
        if (next_plan < nplans and plans[next_plan].at == i) {
            const p = plans[next_plan];
            next_plan += 1;
            const loc = src.while_loop.loc;
            for (0..p.closed.len) |j| {
                if (!p.write[j]) continue;
                out[k] = try constantAssign(alloc, loc, p.closed.names[j], p.closed.values[j]);
                k += 1;
            }
            continue;
        }
        out[k] = src;
        k += 1;
    }
    fb_body.stmts = out[0..k];
}

/// `<name> = <int literal>` — ORDINARY AST, the same discipline
/// `demand.guardedBreak` states: the backend sees a program it could have been
/// given, and no second lowering path exists for a closed loop.
///
/// L6 THE BLOCK'S VALUE IS NOT THE LOOP'S, and this pass got it wrong for the
/// same reason it is easy to miss: the rewrite is CORRECT statement for
/// statement and still changes the program, because one of the block's
/// readers does not read a statement — it reads WHICH statement is last.
///
///     a: i64 = 0                  a: i64 = 0
///     i: i64 = 0                  i: i64 = 0
///     while i < 5                 while i < 5
///         a = a + 1                   t: i64 = a + 1
///         i = i + 1                   a = t
///     print(a)                        i = i + 1
///                                 print(a)
///     5, exit 5                   5, exit 0
///
/// Two spellings of one program, identical stdout, DIFFERENT EXIT STATUS —
/// GAP-215, at 300 trips exit 44 = `300 & 0xff`. The module exit rule
/// PRE-EXISTS and is not this pass's invention: `a: i64 = 0 ; a = 5 ;
/// print(a)` exits 5 with no loop anywhere, because
/// `tail_result_demand.blockTailResult` treats a void-shaped tail call as
/// transparent and walks back to the last value-carrying STATEMENT. What this
/// pass did was replace a `while` — which has no arm in that walk-back and so
/// carries nothing — with an `.assign`, which carries. The loop's trip count
/// reached the process status.
///
/// So the store is marked `closed_loop`, and `tailStatementResult` answers
/// null for it exactly as it answered null for the `while`. NOT a decline:
/// declining would refuse the whole family this pass exists for, since a
/// file-scope loop under a `print` is precisely the shape whose loop is the
/// last statement. The store still happens; only the claim "this is the
/// block's value" is withdrawn, and that claim was never the loop's to make.
fn constantAssign(
    alloc: std.mem.Allocator,
    loc: ast.Loc,
    name: []const u8,
    value: u64,
) std.mem.Allocator.Error!ast.Stmt {
    const target = try alloc.create(ast.Expr);
    target.* = .{ .name = .{ .loc = loc, .ident = name } };
    const lit = try alloc.create(ast.Expr);
    lit.* = .{ .int_lit = .{ .loc = loc, .val = @bitCast(value) } };
    const targets = try alloc.alloc(*ast.Expr, 1);
    targets[0] = target;
    const values = try alloc.alloc(*ast.Expr, 1);
    values[0] = lit;
    return .{ .assign = .{
        .loc = loc,
        .targets = targets,
        .values = values,
        .closed_loop = true,
    } };
}

// ════════════════════════════════════════════════════════════════════════════
// TESTS
//
// Every value assertion is DIFFERENTIAL against a brute-force loop written in
// Zig with the same wrapping arithmetic. A closed form checked against a
// hand-computed constant only proves the author's algebra agrees with itself.
// ════════════════════════════════════════════════════════════════════════════

const testing = std.testing;

fn parseModule(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    const owned = try alloc.dupe(u8, src);
    var lex = @import("lexer.zig").Lexer.init(owned, "loop-closure-test.id");
    var p = @import("parser.zig").Parser.init(&lex, alloc);
    p.idol_mode = true;
    return try p.parse_module();
}

// The whole point, end to end: a loop whose live-out is PRINTED after it.
// `obseq` refuses this shape outright — `readMachine` returns null on the
// `print` — and the closure engine answers it.
test "loop_closure: a loop followed by a print is closed, and the answer matches a brute-force loop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);

    // The induction variable is not read after the loop, so L4 deletes its
    // store: two live-outs, one write.
    try testing.expectEqual(@as(u32, 1), census.writes_emitted);
    try testing.expectEqual(@as(u32, 1), census.writes_deleted_by_demand);

    // DIFFERENTIAL: the same loop, in Zig, in the same ring.
    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000000) : (i += 1) s = s +% i;

    const body = &mod.body.stmts[0].func_decl.func.body;
    // `s = 0 ; i = 1 ; s = <closed> ; print(s)` — the `while` is gone.
    for (body.stmts) |st| try testing.expect(st != .while_loop);
    const written = body.stmts[2].assign;
    try testing.expectEqualStrings("s", written.targets[0].name.ident);
    try testing.expectEqual(@as(i64, @bitCast(s)), written.values[0].int_lit.val);
}

test "loop_closure: the induction variable IS written back when the continuation reads it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        s = s + i
        \\        i += 1
        \\    print(i)
        \\    s
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expectEqual(@as(u32, 2), census.writes_emitted);
    try testing.expectEqual(@as(u32, 0), census.writes_deleted_by_demand);

    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000000) : (i += 1) s = s +% i;

    const body = &mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(i64, @bitCast(s)), body.stmts[2].assign.values[0].int_lit.val);
    try testing.expectEqual(@as(i64, @bitCast(i)), body.stmts[3].assign.values[0].int_lit.val);
}

test "loop_closure: L2 refuses a narrow declaration, because its stores truncate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE CASE L2 EXISTS FOR, and it is not the obvious one. `t: u8` is written
    // before it is read, so `recurrence.entryValueIsDead` supplies an entry
    // value and `closeWhile` ANSWERS — in Z/2^64. The real loop truncates `t`
    // to eight bits on every store, so `s` accumulates something else entirely.
    // Without L2 this compiles cleanly, runs fast and prints the wrong number.
    const src =
        \\main: i64 = ()
        \\    t: u8 = 0
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        t = i * 3
        \\        s = s + t
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_seen);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
    try testing.expectEqual(@as(u32, 1), census.refused_narrow);

    // The plain accumulator case is refused one step earlier, by OMISSION: a
    // poisoned name never enters the environment, so `recurrence` has no entry
    // binding for it and refuses before this file gets an opinion.
    const plain =
        \\main: i64 = ()
        \\    s: u8 = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod2 = try parseModule(alloc, plain);
    const c2 = try applyToModule(alloc, &mod2);
    try testing.expectEqual(@as(u32, 1), c2.loops_seen);
    try testing.expectEqual(@as(u32, 0), c2.loops_closed);
}

test "loop_closure: L1 refuses when the prologue is not a value this pass knows" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\seed: i64 = (k: i64)
        \\    k + 12344
        \\
        \\main: i64 = ()
        \\    s = seed(1)
        \\    i = 1
        \\    while i <= 1000
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
}

test "loop_closure: an effect inside the loop refuses it, because the loop's order is observable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `recurrence.collectUpdates` owns this: a call statement is not a
    // single-target assignment, so the whole loop refuses. The assertion is
    // here because it is THE obligation that makes replacing a loop lawful,
    // and a regression in it would be a silent wrong program.
    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 10
        \\        print(s)
        \\        s = s + i
        \\        i += 1
        \\    s
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_seen);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
}

test "loop_closure: a runtime trip bound refuses, and the loop is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\main: i64 = ()
        \\    n = num(os.env("FTCN"))
        \\    s = 0
        \\    i = 1
        \\    while i <= n
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_seen);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
}

test "loop_closure: two loops in a row, the second reading the first's answer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        s = s + i
        \\        i += 1
        \\    j = 1
        \\    while j <= 1000000
        \\        s = s * 3
        \\        j += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 2), census.loops_closed);

    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000000) : (i += 1) s = s +% i;
    var j: u64 = 1;
    while (j <= 1000000) : (j += 1) s = s *% 3;

    const body = &mod.body.stmts[0].func_decl.func.body;
    var last: i64 = 0;
    for (body.stmts) |st| {
        if (st == .assign and std.mem.eql(u8, st.assign.targets[0].name.ident, "s")) {
            if (st.assign.values[0].* == .int_lit) last = st.assign.values[0].int_lit.val;
        }
    }
    try testing.expectEqual(@as(i64, @bitCast(s)), last);
}

test "loop_closure: a statement between the prologue and the loop that could rebind refuses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `s = other()` is not a value this pass can read, so `s` becomes UNKNOWN
    // and `recurrence` has no entry binding for it. L1 by omission.
    const src =
        \\other: i64 = ()
        \\    7
        \\
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    s = other()
        \\    while i <= 10
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_seen);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
}

test "loop_closure: a loop no continuation reads writes NOTHING back, and the block still rebuilds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE UNDERFLOW CASE. Every live-out is demand-dead, so the plan emits ZERO
    // statements where the `while` stood and the output block is SHORTER than
    // the input. Computing the length by `+writes -1` per plan wraps a usize
    // here; computing it as `len - plans + writes` cannot.
    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000000
        \\        s = s + i
        \\        i += 1
        \\    print(7)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expectEqual(@as(u32, 0), census.writes_emitted);
    try testing.expectEqual(@as(u32, 2), census.writes_deleted_by_demand);

    const body = &mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(usize, 3), body.stmts.len); // s= , i= , print
    for (body.stmts) |st| try testing.expect(st != .while_loop);
}

test "loop_closure: L5 declines a loop the comptime evaluator already answers whole" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MEASURED REGRESSION, and the only emitted-code difference in a 1,015-file
    // corpus differential before this clause existed.
    // `examples/native_differential/i7_while.id`: `comptime.foldRelationBody`
    // answers the WHOLE relation and `_main` is `mov x0, #6 ; ret`. Replacing
    // the loop with its live-out took it to SIX instructions, because that
    // folder dispatches on `bodyHasLoop` and a loopless body falls onto
    // `constantAnswer`, which reads a bare literal tail and nothing else.
    const src =
        \\main: i64 = ()
        \\    t = 0
        \\    i = 1
        \\    while i <= 3
        \\        t = t + i
        \\        i = i + 1
        \\    return t
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_seen);
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
    try testing.expectEqual(@as(u32, 1), census.declined_to_fold);
    // The loop is STILL THERE, which is the whole point: the stronger mechanism
    // gets the body it knows how to answer.
    var saw = false;
    for (mod.body.stmts[0].func_decl.func.body.stmts) |st| {
        if (st == .while_loop) saw = true;
    }
    try testing.expect(saw);
}

test "loop_closure: L5 does NOT decline a relation that takes an operand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `comptime.foldRelationBody` runs only for a relation with no operands, so
    // deferring to it here would decline for a mechanism that never runs. This
    // is also the shape `obseq` can NEVER reach: it closes the zero-parameter
    // entry and nothing else.
    const src =
        \\tot: i64 = (k: i64)
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000
        \\        s = s + i
        \\        i += 1
        \\    s * k
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expectEqual(@as(u32, 0), census.declined_to_fold);

    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000) : (i += 1) s = s +% i;
    const body = &mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(i64, @bitCast(s)), body.stmts[2].assign.values[0].int_lit.val);
}

test "loop_closure: L5 does NOT decline when the body applies something" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE FAMILY THIS PASS EXISTS FOR, at a trip count well BELOW the comptime
    // budget. `foldRelationBody` cannot answer this relation at any trip count —
    // the `print` is an application, so it takes the graph/effect-closure path
    // and refuses on the effect — and there is no `bodyHasLoop` dispatch on that
    // path for the rewrite to downgrade. Declining here would cost the whole
    // family for a mechanism that never runs.
    const src =
        \\main: i64 = ()
        \\    s = 0
        \\    i = 1
        \\    while i <= 1000
        \\        s = s + i
        \\        i += 1
        \\    print(s)
        \\    0
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expectEqual(@as(u32, 0), census.declined_to_fold);

    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000) : (i += 1) s = s +% i;
    const body = &mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(i64, @bitCast(s)), body.stmts[2].assign.values[0].int_lit.val);
}

// ── MODULE SCOPE (W1/W2/W5) ─────────────────────────────────────────────────
//
// Same discipline: every value assertion is DIFFERENTIAL against a brute-force
// Zig loop in the same ring, and every admission has a REFUSAL twin, because a
// transform with no refusal twin is one that has not been shown to fail closed.

test "loop_closure: a file-scope loop is closed only when W admits it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\s: i64 = 0
        \\i: i64 = 1
        \\while i <= 1000000
        \\    s = s + i
        \\    i = i + 1
        \\print(s)
        \\
    ;

    // W1 FALSE -- the default, and what a dylib or an object gets. The loop is
    // left exactly where it was.
    {
        var mod = try parseModule(alloc, src);
        const census = try applyToModule(alloc, &mod);
        try testing.expectEqual(@as(u32, 0), census.loops_closed);
        try testing.expect(mod.body.stmts[2] == .while_loop);
    }

    // W1 TRUE -- the executable. One store replaces the loop, and its value is
    // what a real loop in the same ring produces.
    {
        var mod = try parseModule(alloc, src);
        const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
        try testing.expectEqual(@as(u32, 1), census.loops_closed);
        // L4 deleted the induction variable's store: two live-outs, one write.
        try testing.expectEqual(@as(u32, 1), census.writes_emitted);
        try testing.expectEqual(@as(u32, 1), census.writes_deleted_by_demand);

        var s: u64 = 0;
        var i: u64 = 1;
        while (i <= 1000000) : (i += 1) s = s +% i;

        // W5: ONE statement in the slot the `while` occupied, and the list is
        // the same length -- nothing moved. `print(s)` is the block's TAIL, so
        // the statement list is `s`, `i`, and the slot the loop held.
        try testing.expectEqual(@as(usize, 3), mod.body.stmts.len);
        const written = mod.body.stmts[2].assign;
        try testing.expectEqualStrings("s", written.targets[0].name.ident);
        try testing.expectEqual(@as(i64, @bitCast(s)), written.values[0].int_lit.val);
    }
}

// THE FALSE WIN THIS GUARD EXISTS FOR, and it is not hypothetical: without W2
// the store this pass writes is a top-level integer literal, which
// `dnir_lower.collectModuleConsts` collects and every relation reading the name
// then folds to -- REGARDLESS OF WHERE THE CALL SITE SITS. So `print(peek())`
// BEFORE the loop would start answering with the loop's FINAL value. Lua says
// 1; the unguarded transform would say 11.
test "loop_closure: W2 refuses a file-scope loop whose carried name a relation reads" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\s: i64 = 0
        \\i: i64 = 1
        \\peek: i64 = ()
        \\    s + 1
        \\print(peek())
        \\while i <= 4
        \\    s = s + i
        \\    i = i + 1
        \\print(s)
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
    try testing.expect(mod.body.stmts[4] == .while_loop);
}

// W5's REFUSAL TWIN. A relation declared AFTER the loop makes `demandAfter`
// answer `whole` for every carried name -- `func_decl` is not enumerated, so it
// fails closed -- which needs TWO stores where the slot holds one.
test "loop_closure: W5 refuses a file-scope loop that would need two stores" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\s: i64 = 0
        \\i: i64 = 1
        \\while i <= 1000
        \\    s = s + i
        \\    i = i + 1
        \\later: i64 = (x: i64)
        \\    x + 1
        \\print(s)
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
    try testing.expectEqual(@as(u32, 1), census.refused_would_move);
    try testing.expect(mod.body.stmts[2] == .while_loop);
}

// A relation declared BEFORE the loop is NOT an obstacle, and this is the case
// the first form of the patch broke: it rebuilt the statement list, which moved
// the `FuncDecl` the graph already addressed, and the program refused with
// `DNB011 missing-function-id`. The in-place write leaves it where it is.
test "loop_closure: a relation declared before the loop does not block it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\help: i64 = (x: i64)
        \\    x * 3
        \\s: i64 = 0
        \\i: i64 = 1
        \\while i <= 1000
        \\    s = s + i
        \\    i = i + 1
        \\print(s)
        \\print(help(4))
        \\
    ;
    var mod = try parseModule(alloc, src);
    const before = mod.body.stmts.len;
    const decl = &mod.body.stmts[0].func_decl;
    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expectEqual(before, mod.body.stmts.len);
    // The address the graph holds is still the address of the same declaration.
    try testing.expectEqual(decl, &mod.body.stmts[0].func_decl);

    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= 1000) : (i += 1) s = s +% i;
    try testing.expectEqual(@as(i64, @bitCast(s)), mod.body.stmts[3].assign.values[0].int_lit.val);
}

// L2 AT FILE SCOPE. `u8` stores truncate, so the closed form would answer a
// different machine.
test "loop_closure: a narrow file-scope declaration refuses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\s: u8 = 0
        \\i: i64 = 1
        \\while i <= 1000
        \\    s = s + i
        \\    i = i + 1
        \\print(s)
        \\
    ;
    var mod = try parseModule(alloc, src);
    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 0), census.loops_closed);
    // NOT `refused_narrow`, and the difference is worth recording: L2 poisons
    // the name, which makes the statement walk KILL it out of the entry
    // environment, so `closeWhile` refuses on an unbound entry value before L2's
    // own counter is ever reached. The refusal is L1's, by omission -- which is
    // what this file's header says L1 is for.
    try testing.expectEqual(@as(u32, 0), census.refused_narrow);
    try testing.expect(mod.body.stmts[2] == .while_loop);
}

// ── L6: EXIT STATUS ──────────────────────────────────────────────────────────
//
// GAP-215, AND WHY THE SECTION ABOVE DID NOT CATCH IT. Every assertion above is
// about the STATEMENT LIST -- which statement stands where, and what number it
// holds. All of them stayed true through the defect, because the defect is not
// in any statement: it is in WHICH STATEMENT IS LAST. A `while` carries no
// block value; the `.assign` that replaced it carries one, so
// `tail_result_demand.blockTailResult` walked back onto it and the loop's
// answer became the process exit status. Two spellings of one program, the same
// stdout, different exit status.
//
// So these tests read the module's ANSWER rather than its statements, at both
// producers: `blockTailResult`, which decides it, and `dnir_lower.lowerModule`,
// which emits it as `main`'s `ret`. Every one is a DIFFERENTIAL between the
// transformed and untransformed program -- the transform's whole claim is that
// those two agree, so an assertion against a hand-written constant would prove
// only that the author agrees with the author.
//
// AND EVERY ZERO HAS A POSITIVE CONTROL. `exitLiteralOf` answering `0` proves
// nothing unless the same probe answers `5` for a module that really does exit
// 5, which is what the "pre-existing rule" test below is for.

const dnir_lower_probe = @import("graph/lower.zig");
const native_ir_probe = @import("native/ir.zig");
const tail_probe = @import("tail_result_demand.zig");

/// What the module's entry answers, read off the emitted `ret`.
///
/// `refused` is a REAL ANSWER, not a probe failure: some of these programs are
/// outside the direct-native subset, and a refusal that stays a refusal is
/// exactly what the differential must confirm. Folding it into an error would
/// throw away the only fact a refused program has.
const ExitProbe = union(enum) {
    /// `dnir_lower` would not lower the module at all.
    refused,
    /// A `ret` whose operand is a slot rather than a literal.
    slot,
    /// The number the process exits with, before the kernel takes its low byte.
    literal: i64,

    fn same(a: ExitProbe, b: ExitProbe) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .literal => |v| v == b.literal,
            else => true,
        };
    }
};

fn exitProbeOf(alloc: std.mem.Allocator, mod: *const ast.Module) ExitProbe {
    const m = dnir_lower_probe.lowerModule(alloc, mod) catch return .refused;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        const instrs = f.blocks[f.blocks.len - 1].instrs;
        var i = instrs.len;
        while (i > 0) {
            i -= 1;
            if (instrs[i].op != .ret) continue;
            return switch (instrs[i].lhs) {
                .i64 => |v| .{ .literal = v },
                else => .slot,
            };
        }
    }
    return .refused;
}

/// `exitProbeOf`, asserted to be a literal. Used where the program is known to
/// be inside the subset and the NUMBER is the claim.
fn exitLiteralOf(alloc: std.mem.Allocator, mod: *const ast.Module) !i64 {
    return switch (exitProbeOf(alloc, mod)) {
        .literal => |v| v,
        else => error.NotALiteralExit,
    };
}

/// The rule `blockTailResult` picks for a module body, or null when it picks
/// nothing. This is the fact the exit status is derived from, so it is asserted
/// directly rather than only through the number it produces.
fn tailRuleOf(mod: *const ast.Module) ?tail_probe.TailResultRule {
    const r = tail_probe.blockTailResult(&mod.body) orelse return null;
    return r.rule;
}

// THE DEFECT, EXACTLY AS FILED. Left spelling and right spelling of one
// program: identical stdout, and before this the left exited 5 and the right
// exited 0.
test "loop_closure: L6 -- closing a file-scope loop does not give the module an exit status" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const left =
        \\a: i64 = 0
        \\i: i64 = 0
        \\while i < 5
        \\    a = a + 1
        \\    i = i + 1
        \\print(a)
        \\
    ;

    // UNTRANSFORMED -- the program as written, and the answer both spellings
    // must keep.
    var plain = try parseModule(alloc, left);
    try testing.expect(plain.body.stmts[2] == .while_loop);
    try testing.expectEqual(tail_probe.TailResultRule.tail_call, tailRuleOf(&plain).?);
    try testing.expectEqual(@as(i64, 0), try exitLiteralOf(alloc, &plain));

    // TRANSFORMED -- the loop really is closed (the transform is not disabled
    // to fix this), and the module's answer is unchanged.
    var closed = try parseModule(alloc, left);
    const census = try applyToModuleObserved(alloc, &closed, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expect(closed.body.stmts[2] == .assign);
    try testing.expect(closed.body.stmts[2].assign.closed_loop);
    try testing.expectEqual(@as(i64, 5), closed.body.stmts[2].assign.values[0].int_lit.val);
    try testing.expectEqual(tail_probe.TailResultRule.tail_call, tailRuleOf(&closed).?);
    try testing.expectEqual(@as(i64, 0), try exitLiteralOf(alloc, &closed));

    // THE RIGHT SPELLING. A body `local_decl` -- `recurrence.collectUpdates`
    // walks only `.assign`, so the loop is REFUSED and no store is written.
    // GAP-215 forbids widening that walk until this coverage exists; the row is
    // here so the widening has something to answer to.
    const right =
        \\a: i64 = 0
        \\i: i64 = 0
        \\while i < 5
        \\    t: i64 = a + 1
        \\    a = t
        \\    i = i + 1
        \\print(a)
        \\
    ;
    var other = try parseModule(alloc, right);
    const c2 = try applyToModuleObserved(alloc, &other, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 1), c2.loops_seen);
    try testing.expectEqual(@as(u32, 0), c2.loops_closed);
    try testing.expect(other.body.stmts[2] == .while_loop);
    try testing.expectEqual(@as(i64, 0), try exitLiteralOf(alloc, &other));
}

// THE POSITIVE CONTROL FOR EVERY ZERO ABOVE, and the proof that the module exit
// rule PRE-EXISTS this transform and is not being changed by the fix. No loop
// appears anywhere: a module whose last statement is an assignment exits with
// its value, before and after the pass runs.
test "loop_closure: L6 -- a module whose last statement IS an assignment keeps its exit status" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\a: i64 = 0
        \\a = 5
        \\print(a)
        \\
    ;
    var mod = try parseModule(alloc, src);
    try testing.expectEqual(tail_probe.TailResultRule.tail_assignment, tailRuleOf(&mod).?);
    try testing.expectEqual(@as(i64, 5), try exitLiteralOf(alloc, &mod));

    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 0), census.loops_seen);
    try testing.expect(!mod.body.stmts[1].assign.closed_loop);
    try testing.expectEqual(tail_probe.TailResultRule.tail_assignment, tailRuleOf(&mod).?);
    try testing.expectEqual(@as(i64, 5), try exitLiteralOf(alloc, &mod));

    // And the OTHER half of the same control: a bare declaration is not an
    // assignment, so this one exits 0. Without this row a probe that always
    // answered 0 would pass the test above by accident.
    const decl_only =
        \\a: i64 = 5
        \\print(a)
        \\
    ;
    var d = try parseModule(alloc, decl_only);
    try testing.expectEqual(@as(i64, 0), try exitLiteralOf(alloc, &d));
}

// THE TRIP COUNT IS WHAT REACHED THE STATUS BYTE, so the count is varied and
// the answer must not move with it. 300 trips exited 44 -- `300 & 0xff`.
test "loop_closure: L6 -- the exit status does not follow the trip count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const trips = [_]u64{ 5, 300, 1000000 };
    for (trips) |n| {
        const src = try std.fmt.allocPrint(alloc,
            \\a: i64 = 0
            \\i: i64 = 0
            \\while i < {d}
            \\    a = a + 1
            \\    i = i + 1
            \\print(a)
            \\
        , .{n});
        var mod = try parseModule(alloc, src);
        const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
        try testing.expectEqual(@as(u32, 1), census.loops_closed);

        // DIFFERENTIAL: the same loop, in Zig, in the same ring. The STORE still
        // holds the loop's answer -- only the claim that it is the module's
        // answer is withdrawn.
        var a: u64 = 0;
        var i: u64 = 0;
        while (i < n) : (i += 1) a = a +% 1;
        try testing.expectEqual(@as(i64, @bitCast(a)), mod.body.stmts[2].assign.values[0].int_lit.val);

        try testing.expectEqual(@as(i64, 0), try exitLiteralOf(alloc, &mod));
    }
}

// THE SECOND DIRECTION, and the one a fix that simply refused every closable
// file-scope loop would also pass. A real assignment AFTER the closed loop is
// still the module's answer.
test "loop_closure: L6 -- a real assignment after a closed loop is still the module's answer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\a: i64 = 0
        \\i: i64 = 0
        \\b: i64 = 0
        \\while i < 5
        \\    a = a + 1
        \\    i = i + 1
        \\b = 9
        \\print(a)
        \\
    ;
    var plain = try parseModule(alloc, src);
    try testing.expectEqual(@as(i64, 9), try exitLiteralOf(alloc, &plain));

    var mod = try parseModule(alloc, src);
    const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = true });
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    try testing.expect(mod.body.stmts[3].assign.closed_loop);
    try testing.expect(!mod.body.stmts[4].assign.closed_loop);
    try testing.expectEqual(@as(i64, 9), try exitLiteralOf(alloc, &mod));
}

// A CLOSED LOOP INSIDE A RELATION HAS THE SAME HOLE, and it is not the module
// exit status -- it is the relation's return value. `main` here has no tail
// expression at all, so the body's value is nothing; the store that replaced
// the loop must not become it.
test "loop_closure: L6 -- a closed loop is not a relation body's value either" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\main: i64 = ()
        \\    a = 0
        \\    i = 0
        \\    while i < 1000000
        \\        a = a + 1
        \\        i = i + 1
        \\    print(a)
        \\
    ;
    var plain = try parseModule(alloc, src);
    const plain_body = &plain.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(tail_probe.TailResultRule.tail_call, tail_probe.blockTailResult(plain_body).?.rule);

    var mod = try parseModule(alloc, src);
    const census = try applyToModule(alloc, &mod);
    try testing.expectEqual(@as(u32, 1), census.loops_closed);
    const body = &mod.body.stmts[0].func_decl.func.body;
    try testing.expect(body.stmts[2].assign.closed_loop);
    try testing.expectEqual(tail_probe.TailResultRule.tail_call, tail_probe.blockTailResult(body).?.rule);
}

// ── THE DECLINED SHAPES, BY REASON ───────────────────────────────────────────
//
// GAP-215's other half: the 538-file corpus differential that accompanied this
// transform read as evidence of safety while exercising the changed path with
// ONE program. Of those 538, ten contain a module-scope `while` and nine refuse
// to compile on the direct backend, so `examples/boring/reverse.id` was the
// entire file-scope safety corpus -- and its loop is not even closable.
//
// One row per REASON the module path can decline, each asserting the census
// counter that names it AND that the module's answer is untouched. A refusal
// that changes the exit status is still a regression, and nothing measured that
// before.
test "loop_closure: the module path declines, by reason, and never moves the answer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Row = struct {
        why: []const u8,
        src: []const u8,
        world_closed: bool = true,
        loop_at: usize,
        refused_narrow: u32 = 0,
        refused_would_move: u32 = 0,
        refused_new_binding: u32 = 0,
    };

    const rows = [_]Row{
        // W1. Not an executable: a dylib or an object is read from outside, so
        // the file-scope tail is not analysable and the loop stands.
        .{
            .why = "W1 world not closed",
            .world_closed = false,
            .loop_at = 2,
            .src =
            \\s: i64 = 0
            \\i: i64 = 1
            \\while i <= 1000
            \\    s = s + i
            \\    i = i + 1
            \\print(s)
            \\
            ,
        },
        // W2. A relation reads the carried name, so the store would be visible
        // to a reader this walk cannot place.
        .{
            .why = "W2 deferred reader",
            .loop_at = 4,
            .src =
            \\s: i64 = 0
            \\i: i64 = 1
            \\peek: i64 = ()
            \\    s + 1
            \\print(peek())
            \\while i <= 4
            \\    s = s + i
            \\    i = i + 1
            \\print(s)
            \\
            ,
        },
        // W5. A relation declared AFTER the loop makes `demandAfter` answer
        // `whole` for every carried name, so the slot would need two stores.
        .{
            .why = "W5 would move a statement",
            .loop_at = 2,
            .refused_would_move = 1,
            .src =
            \\s: i64 = 0
            \\i: i64 = 1
            \\while i <= 1000
            \\    s = s + i
            \\    i = i + 1
            \\later: i64 = (x: i64)
            \\    x + 1
            \\print(s)
            \\
            ,
        },
        // L1, BY OMISSION. The prologue is not a value this pass knows, so the
        // name never enters the environment and `recurrence` refuses.
        .{
            .why = "L1 entry value unknown",
            .loop_at = 3,
            .src =
            \\seed: i64 = (k: i64)
            \\    k + 1
            \\s: i64 = seed(1)
            \\i: i64 = 1
            \\while i <= 1000
            \\    s = s + i
            \\    i = i + 1
            \\print(s)
            \\
            ,
        },
        // L2, ALSO BY OMISSION at file scope: the narrow name is poisoned,
        // which kills it out of the entry environment before `refused_narrow`
        // can be reached. The stores truncate, so the closed form would answer
        // a different machine.
        .{
            .why = "L2 narrow declaration",
            .loop_at = 2,
            .src =
            \\s: u8 = 0
            \\i: i64 = 1
            \\while i <= 1000
            \\    s = s + i
            \\    i = i + 1
            \\print(s)
            \\
            ,
        },
        // `recurrence.collectUpdates` refuses a body that is not all
        // single-target assignments -- an effect first.
        .{
            .why = "effect in the loop body",
            .loop_at = 2,
            .src =
            \\s: i64 = 0
            \\i: i64 = 1
            \\while i <= 10
            \\    print(s)
            \\    s = s + i
            \\    i = i + 1
            \\print(s)
            \\
            ,
        },
        // The same refusal, reached by a body `local_decl` -- the exact shape
        // GAP-215 says must not be admitted until this coverage exists.
        .{
            .why = "body local_decl",
            .loop_at = 2,
            .src =
            \\a: i64 = 0
            \\i: i64 = 0
            \\while i < 5
            \\    t: i64 = a + 1
            \\    a = t
            \\    i = i + 1
            \\print(a)
            \\
            ,
        },
    };

    var declined: u32 = 0;
    for (rows) |row| {
        var plain = try parseModule(alloc, row.src);
        const before = exitProbeOf(alloc, &plain);

        var mod = try parseModule(alloc, row.src);
        const census = try applyToModuleObserved(alloc, &mod, .{ .world_closed = row.world_closed });
        errdefer std.debug.print("row: {s}\n", .{row.why});
        try testing.expectEqual(@as(u32, 0), census.loops_closed);
        try testing.expectEqual(row.refused_narrow, census.refused_narrow);
        try testing.expectEqual(row.refused_would_move, census.refused_would_move);
        try testing.expectEqual(row.refused_new_binding, census.refused_new_binding);
        // The loop is STILL THERE, and the module's answer is what it was.
        try testing.expect(mod.body.stmts[row.loop_at] == .while_loop);
        try testing.expect(before.same(exitProbeOf(alloc, &mod)));
        declined += 1;
    }
    // The count is the coverage claim, and it is asserted so that deleting a
    // row is a failure rather than a quiet reduction.
    try testing.expectEqual(@as(u32, 7), declined);
}
