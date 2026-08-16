//! §17 × §22-23 — THE INDUCED RELATION, SYNTHESIZED FOR A RELATION THE
//! COMPILER WAS NEVER TOLD ABOUT.
//!
//! # The one sentence
//!
//! `src/demand_projection.zig` asks *through which projection is this value
//! observed?* and answers it for a fixed alphabet of BUILTIN operators. Ask it
//! about `seen(hits)` where `seen` is a relation the user wrote this morning
//! and it answers `whole`, because `projectionOfName`'s fallback is
//! `mentions(e, n) -> .whole`. **This module makes the answer come from `seen`'s
//! own body**, by deriving the relation's law rather than looking its name up.
//!
//! `HPLS.md` §106 states the test that decides whether the optimizer is real:
//!
//! > Can the loop run for an ARBITRARY USER-DEFINED RELATION? Not for `+`, not
//! > for a builtin `sort`, not for a hand-listed rewrite table.
//!
//! and §17 states the interface:
//!
//!     given  a producer relation f (USER-DEFINED, not builtin)
//!     and    a demanded projection h from the consumer
//!     find   g such that h(f(x)) = g(h(x))
//!     prove  it
//!     then   maintain h(x) instead of x, and propagate h BACKWARD to f's inputs
//!
//! `inducedInputProjection` below IS that interface. `g` is `f`'s own answer
//! read in the quotient — it is never SEARCHED FOR among candidate terms,
//! because the search that matters is the search for the INPUT PROJECTIONS that
//! make `g` well defined, and that search is a least fixpoint over a finite
//! lattice.
//!
//! # THE MEASUREMENT THAT MOTIVATES IT
//!
//! Three programs with the SAME 2e9-iteration loop, differing only in how the
//! answer reads the accumulator. `--backend=direct`, Apple Silicon, cache
//! cleared, `/usr/bin/time -l`:
//!
//!     tail `if hits != 0 then 1 else 0`     11,867,976 insn   exit 1
//!     tail `seen(hits, 4)`, seen recursive  22,021,920,835    exit 1
//!     tail `seen(hits, 4)`, base case `n`   22,019,935,914    exit 101
//!
//! Row 1 is the shipped win: `demand_projection.zig` reads `h = nonzero`,
//! proves `nonzero(hits)` absorbing after the first write, and truncates —
//! 2e9 iterations become 733. Row 2 is the SAME QUOTIENT written behind a
//! relation, and the shipped compiler pays 1,856x for the wrapper. Row 3 is
//! the adversarial control and it must NEVER be truncated: its answer is 101,
//! so a synthesizer that admits it produces an artifact that exits 1.
//!
//! # WHY THIS IS NOT AN INLINER
//!
//! Inlining `seen` would give row 1's answer for row 2 — so if that were all
//! this module did, §106's test would still be unanswered and "just inline it"
//! would be the honest verdict. Two things separate them, and the second is
//! the one that is measured:
//!
//!   1. A LAW IS A SUMMARY, NOT A COPY. `inducedInputProjection(h, f)` is a
//!      fact ABOUT `f` — one vector of projections per (relation, h) — derived
//!      once, memoized, and composable. It is available where the body is not
//!      substitutable: at a call site the inliner declined, behind a size
//!      budget, and (once cross-home resolution carries it) across a module
//!      boundary.
//!
//!   2. **THE FIXPOINT TERMINATES WHERE SUBSTITUTION DIVERGES.** The projection
//!      lattice is finite, so the input demand of a RECURSIVE relation is a
//!      least fixpoint computed by Kleene iteration from `none` upward. An
//!      inliner has nothing to iterate: substituting `seen` into itself does
//!      not terminate, and every inliner in existence therefore gives up and
//!      leaves the call opaque. **The measured win below is on a recursive
//!      relation for exactly this reason** — it is a case ordinary optimization
//!      cannot match, which is the verification bar this lane was set.
//!
//! # THE PROOF OBLIGATIONS, STATED BEFORE THE TRANSFORM
//!
//! The claim made when `inducedInputProjection(h, f)` returns `p` is:
//!
//!     for all x, y:  p(x) = p(y)  =>  h(f(x)) = h(f(y))
//!
//! i.e. `h ∘ f` factors through `p`, which is exactly `h(f(x)) = g(p(x))` for
//! the `g` that reads `f`'s answer over the projected inputs. Seven obligations
//! discharge it. Any one unproven means the call stays opaque and the caller
//! gets today's answer (`whole` if the call mentions the name), so a refusal
//! costs candidates and can never cost an answer.
//!
//!   R1 THE CALLEE IS STATICALLY THIS RELATION. The callee expression is a bare
//!      name; exactly one module-scope `func_decl` with a one-segment path
//!      carries it; and NOTHING in the module rebinds that name — no
//!      `local_decl`, `assign`, `global_decl` or second declaration anywhere.
//!      A rebindable name is not a relation, it is a place, and this module
//!      cannot bound a place's writers.  -> `Env.scan`, `resolve`
//!
//!   R2 THE ANSWER IS AN ANSWER. The body is a pure answer form: a tail
//!      expression, a lone `return`, or an `if` whose branches are answer forms.
//!      A statement outside that set — a loop, a local binding, an effect, a
//!      second `return` — refuses. This is deliberately the NARROWEST form that
//!      carries the fixpoint, because widening it widens the trusted core.
//!      -> `answerProjection`
//!
//!   R3 NO CAPTURE. Every name the answer reads is a parameter of the relation.
//!      A module-scope read would make `f`'s result depend on a place the
//!      caller's loop may write, and the projection would be a lie about a
//!      different value. Fails closed: an AST variant not enumerated counts as
//!      a capture.  -> `onlyParams`
//!
//!   R4 TOTAL AND EFFECT-FREE. Every node of the answer that is not itself an
//!      admitted call is handed to `demand.inert` — the tree's ONE producer of
//!      the trap/effect fact — and a blocker refuses. `/ % //` against a
//!      non-literal divisor are refused there and this module does not get a
//!      second opinion. Without this, `f` could PRINT its argument, and a
//!      printed argument is a whole-value observation no projection may hide.
//!      -> `answerInert`
//!
//!   R5 ARITY IS EXACT. `args.len == params.len`, no vararg, no defaults. A
//!      defaulted parameter is a value this module cannot see.  -> `resolve`
//!
//!   R6 THE FIXPOINT IS LEAST AND IT CONVERGED. Recursive and mutually
//!      recursive relations are solved by ascending Kleene iteration from the
//!      bottom of the projection lattice. The transfer function is monotone in
//!      `h` (every rule in `demand_projection.projectionOfName` maps a larger
//!      `h` to a larger answer) and the lattice has finite height, so the
//!      iteration converges. **Running out of rounds or table space is reported
//!      as `unknown` and refuses — never as "no better projection exists".**
//!      -> `solve`
//!
//!   R7 THE DERIVATIVE IS THE ONE PRODUCER'S. Every call-free subexpression is
//!      handed VERBATIM to `demand_projection.projectionOfName`. This module
//!      adds exactly one rule — the call rule — and re-derives the operator
//!      rules only for subtrees that contain a call, from
//!      `demand_projection.lawsOf` rather than from a second operator list. A
//!      unit test asserts the two agree on every call-free expression it can
//!      build, so the second evaluator cannot drift into a second semantics.
//!      -> `exprProjection`, and the test `agrees with the one producer`
//!
//! # WHAT IS DELIBERATELY NOT PROVEN HERE, AND WHERE IT IS UNSOUND
//!
//! HYPERPROPERTIES. Every check in this file is SINGLE-TRACE. The transform it
//! enables changes the iteration count, and a timing observer distinguishes
//! that. This module does not consult the observer roster at all — it produces
//! a PROJECTION, and `demand_projection.observationRefusal` is the authority
//! that decides whether any projection may be acted on. A world demanding
//! determinism, noninterference, serializability or linearizability refuses the
//! whole module there, before this file's answer is used. Putting a second
//! roster test here would be a second authority, which §7 calls debt.
//!
//! EFFECT ORDER ACROSS THE CALL. R4 refuses effects outright rather than
//! reasoning about their order, so nothing here is sound for a relation that
//! writes. That is the whole reason `demand.inert` is consulted rather than
//! re-implemented.
//!
//! FLOATS. The lattice is over integers. A float parameter is refused by R4's
//! grammar walk, because `x mod 2^k` and `x != 0` are not the observations a
//! float carries and pretending otherwise is how a fast wrong answer is built.

const std = @import("std");
const ast = @import("ast.zig");
const demand = @import("demand.zig");
const dp = @import("demand_projection.zig");

/// The demand quotient. NOT redefined — `demand_projection.zig` is the one
/// producer of this lattice, and a second spelling of it is the defect this
/// tree names "two proofs of one fact".
pub const Projection = dp.Projection;
/// The relation law fact. Same rule: one producer, consumed here.
pub const Law = dp.Law;

// ── Bounds. Every one makes the search TERMINATE; none is a tuning knob.
// Exceeding any is a REFUSAL, never a truncation. ───────────────────────────

/// Module-scope relations tracked. A module with more is analysed for the
/// first `max_relations`; the rest resolve to nothing and stay opaque.
pub const max_relations: usize = 64;
/// Parameters of an admitted relation.
pub const max_params: usize = 8;
/// Distinct `(relation, h)` queries in one fixpoint. The lattice is finite so
/// this bounds the whole solve.
pub const max_queries: usize = 64;
/// Kleene rounds. The lattice `none ⊏ {nonzero, low_bits 1..63} ⊏ whole` has
/// height 3 along any chain, so a single query settles in ≤ 3 rounds; the
/// budget covers a chain of mutually recursive queries and is a refusal when
/// it runs out.
pub const max_rounds: u32 = 256;
/// Nesting of the answer walk.
pub const max_depth: u8 = 24;

/// Why a call stayed opaque. Every value names an unmet obligation above, so a
/// census over these says which obligation costs the most candidates.
pub const Refusal = enum {
    /// R1 — callee is not a bare name (a field, a method, a computed callee).
    callee_not_a_name,
    /// R1 — the name is not a module-scope relation.
    callee_not_a_relation,
    /// R1 — the name is also bound by an assignment or declaration.
    callee_rebound,
    /// R5 — arity, vararg or a defaulted parameter.
    arity,
    /// R2 — the body is not an answer form.
    answer_form,
    /// R3 — the answer reads a name that is not a parameter.
    captures_outer_name,
    /// R4 — `demand.inert` reported a blocker.
    not_inert,
    /// R6 — rounds or table space exhausted. UNKNOWN, not "none exists".
    budget,
    /// R7 — an expression form the extended derivative does not model.
    grammar,
    /// The derived projection is `whole`: correct, and worth nothing.
    no_gain,
};

pub const refusal_count = @typeInfo(Refusal).@"enum".field_names.len;

/// What the synthesizer saw. A gate that cannot fail in both directions is not
/// a gate: zero admitted calls on a corpus containing one is a failure, and a
/// refusal histogram that never changes is a search that is not looking.
pub const Census = struct {
    relations_scanned: u32 = 0,
    relations_rebound: u32 = 0,
    calls_examined: u32 = 0,
    calls_admitted: u32 = 0,
    /// Admitted by the §22-23 law shortcut (a proven mod-2^k homomorphism
    /// answers every `low_bits` query at once, with no fixpoint at all).
    admitted_by_law: u32 = 0,
    /// Admitted by the Kleene fixpoint over the answer.
    admitted_by_fixpoint: u32 = 0,
    /// Queries that needed more than one round — i.e. recursion was actually
    /// present and actually solved. This is the number that separates this
    /// mechanism from an inliner.
    recursive_queries: u32 = 0,
    rounds_spent: u32 = 0,
    refusals: [refusal_count]u32 = @splat(0),

    pub fn refuse(self: *Census, r: Refusal) void {
        self.refusals[@intFromEnum(r)] += 1;
    }
    pub fn refusalCount(self: *const Census, r: Refusal) u32 {
        return self.refusals[@intFromEnum(r)];
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// THE RELATION TABLE — R1
// ═══════════════════════════════════════════════════════════════════════════

const Rel = struct {
    name: []const u8,
    decl: *const ast.FuncDecl,
    /// R1. True when the name is bound by anything other than this one
    /// declaration, anywhere in the module.
    rebound: bool = false,
    /// §22-23 law closure state, memoized.
    law_state: enum { unknown, computing, derived, refused } = .unknown,
    law: Law = .{},
    /// R4 memo. `computing` closes a recursive answer co-inductively — see
    /// `answerInertGuarded` for why that is sound in this grammar.
    inert_state: enum { unknown, computing, yes, no } = .unknown,
};

/// The module's user-defined relations, plus the fixpoint solver's state.
///
/// Deliberately allocator-free and fixed-capacity, per §79-80: a fact table
/// this small has no business owning a heap.
pub const Env = struct {
    rels: [max_relations]Rel = undefined,
    len: usize = 0,
    opts: demand.Options = .{},
    census: Census = .{},
    tbl: Table = .{},
    /// True while `solve` is iterating. See `inducedInputProjection`.
    solving: bool = false,

    /// Build the table from a module. R1's rebinding check is done in the same
    /// pass: a name that is ever a target, a local, a global or a second
    /// declaration is marked and never resolves.
    pub fn scan(mod: *const ast.Module, opts: demand.Options) Env {
        var env = Env{ .opts = opts };
        for (mod.body.stmts) |*s| {
            if (s.* != .func_decl) continue;
            const fd = &s.func_decl;
            if (fd.method or fd.path.len != 1) continue;
            const nm = fd.path[0];
            if (env.indexOf(nm)) |i| {
                // Two declarations of one name: neither is "the" relation.
                env.rels[i].rebound = true;
                continue;
            }
            if (env.len == max_relations) break;
            env.rels[env.len] = .{ .name = nm, .decl = fd };
            env.len += 1;
        }
        env.census.relations_scanned = @intCast(env.len);
        // R1's other half — any other binder of the name kills it.
        for (mod.body.stmts) |*s| env.markRebindings(s);
        for (0..env.len) |i| {
            if (env.rels[i].rebound) env.census.relations_rebound += 1;
        }
        return env;
    }

    fn indexOf(self: *const Env, n: []const u8) ?usize {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.rels[i].name, n)) return i;
        }
        return null;
    }

    fn markName(self: *Env, n: []const u8) void {
        if (self.indexOf(n)) |i| self.rels[i].rebound = true;
    }

    fn markTarget(self: *Env, e: *const ast.Expr) void {
        switch (e.*) {
            .name => |x| self.markName(x.ident),
            else => {},
        }
    }

    /// Walks every statement form looking for a binder of a relation's name.
    /// FAILS CLOSED: a statement variant this does not enumerate marks EVERY
    /// relation rebound, so a future binder cannot silently make a name look
    /// stable.
    fn markRebindings(self: *Env, s: *const ast.Stmt) void {
        switch (s.*) {
            // A relation's own body is scanned too: a `seen = 3` inside
            // `main` is a rebinding of the module's `seen`, and a table that
            // did not walk function bodies would call the name stable while an
            // assignment two lines away made it a place.
            .func_decl => |fd| self.markBlock(&fd.func.body),
            .local_decl => |d| for (d.names) |n| self.markName(n.ident),
            .global_decl => |d| for (d.names) |n| self.markName(n.ident),
            .const_decl => |d| self.markName(d.ident),
            .assign => |a| for (a.targets) |t| self.markTarget(t),
            .do_block => |d| self.markBlock(&d.body),
            .while_loop => |w| self.markBlock(&w.body),
            .repeat_loop => |r| self.markBlock(&r.body),
            .if_stmt => |f| {
                self.markBlock(&f.then);
                for (f.elseifs) |ei| self.markBlock(&ei.body);
                if (f.else_body) |eb| self.markBlock(&eb);
            },
            .ret, .brk, .cont, .call_stmt, .expr_stmt => {},
            else => {
                // An unmodelled statement form may bind anything.
                for (0..self.len) |i| self.rels[i].rebound = true;
            },
        }
    }

    fn markBlock(self: *Env, b: *const ast.Block) void {
        for (b.stmts) |*s| self.markRebindings(s);
    }

    /// R1 + R5. Resolve a call expression to a relation index.
    pub fn resolve(self: *Env, c: anytype) ?usize {
        const callee = switch (c.func.*) {
            .name => |x| x.ident,
            else => {
                self.census.refuse(.callee_not_a_name);
                return null;
            },
        };
        const i = self.indexOf(callee) orelse {
            self.census.refuse(.callee_not_a_relation);
            return null;
        };
        if (self.rels[i].rebound) {
            self.census.refuse(.callee_rebound);
            return null;
        }
        const fb = &self.rels[i].decl.func;
        if (fb.vararg or fb.vararg_name != null or fb.params.len != c.args.len or fb.params.len > max_params) {
            self.census.refuse(.arity);
            return null;
        }
        for (fb.params) |p| if (p.default_val != null) {
            self.census.refuse(.arity);
            return null;
        };
        return i;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// R6 — THE LEAST FIXPOINT OVER A FINITE LATTICE
//
// This is the part an inliner has no counterpart for. A recursive relation's
// input demand is not a substitution, it is the least solution of
//
//     P(f, h)  =  F_f,h( P )
//
// where F reads the answer's derivative and every recursive call reads P
// itself. F is monotone (a larger projection in never yields a smaller
// projection out, because every rule in `projectionOfName` maps h upward) and
// the lattice is finite, so ascending iteration from ⊥ converges to the LEAST
// fixpoint — the strongest sound answer. Starting from ⊤ would also converge,
// to a greatest fixpoint that is sound but says nothing.
// ═══════════════════════════════════════════════════════════════════════════

const Query = struct {
    rel: u8,
    h: Projection,
    params: [max_params]Projection = @splat(.none),
    /// Set when any obligation failed for this query. A refused query answers
    /// `whole` for every parameter, which is exactly today's behaviour and is
    /// therefore always sound.
    refused: ?Refusal = null,
    /// Rounds in which this query's value changed. > 1 means recursion.
    updates: u32 = 0,
};

const Table = struct {
    qs: [max_queries]Query = undefined,
    len: usize = 0,
    changed: bool = false,
    overflow: bool = false,

    fn find(self: *const Table, rel: u8, h: Projection) ?usize {
        for (0..self.len) |i| {
            if (self.qs[i].rel == rel and self.qs[i].h.eql(h)) return i;
        }
        return null;
    }

    /// The bottom element for a new query. A query first seen mid-round reads
    /// ⊥, which is what makes the iteration ASCENDING.
    fn getOrAdd(self: *Table, rel: u8, h: Projection) ?usize {
        if (self.find(rel, h)) |i| return i;
        if (self.len == max_queries) {
            self.overflow = true;
            return null;
        }
        self.qs[self.len] = .{ .rel = rel, .h = h };
        self.len += 1;
        self.changed = true;
        return self.len - 1;
    }

    fn set(self: *Table, qi: usize, params: [max_params]Projection, refused: ?Refusal) void {
        var moved = false;
        const q = &self.qs[qi];
        for (0..max_params) |i| {
            const joined = Projection.join(q.params[i], params[i]);
            if (!joined.eql(q.params[i])) {
                q.params[i] = joined;
                moved = true;
            }
        }
        if (refused != null and q.refused == null) {
            q.refused = refused;
            for (0..max_params) |i| q.params[i] = .whole;
            moved = true;
        }
        if (moved) {
            q.updates += 1;
            self.changed = true;
        }
    }
};

/// **THE §17 INTERFACE.** Given that an observer distinguishes only `h` of the
/// result of user-defined relation `rel`, return the projection of each
/// parameter that suffices — i.e. the `p` in `h(f(x)) = g(p(x))`.
///
/// Returns null when any obligation is unproven; `whole` for every parameter
/// is the sound fallback the caller must then use.
pub fn inducedInputProjection(env: *Env, rel: usize, h: Projection) ?[max_params]Projection {
    if (h == .none) return @splat(.none);
    // R5 AT THE PUBLIC DOOR, AND IT IS A MEMORY-SAFETY BOUND, NOT A POLICY.
    //
    // The answer is `[max_params]Projection` and the loops below index it by
    // PARAMETER NUMBER. R5 was enforced only in the private `Env.resolve`, so
    // every path that arrives through a CALL was bounded and this entry point
    // — reachable with a bare relation index — was not. MEASURED on the
    // corpus: 15 module-scope relations carry more than `max_params`
    // parameters, and this function on any of them wrote past the end of a
    // stack array.
    //
    // Latent while the only callers were internal; not latent the moment a
    // second module composes through it. Refusing here is the same refusal
    // `resolve` already makes, moved to where the array is sized.
    if (rel >= env.len) {
        env.census.refuse(.callee_not_a_relation);
        return null;
    }
    const fb = &env.rels[rel].decl.func;
    if (fb.params.len > max_params or fb.vararg or fb.vararg_name != null) {
        env.census.refuse(.arity);
        return null;
    }
    // RE-ENTRANCY IS THE WHOLE DIFFICULTY OF A FIXPOINT. A call encountered
    // WHILE solving must READ the table, never start a second solve: reading ⊥
    // for a query not yet settled is what makes the iteration ascending, and
    // solving inside a solve is what makes it diverge. `solving` is the one bit
    // that distinguishes the two, and the recursive fixture below is the test
    // that it is set.

    // ── §22-23 FAST PATH: a proven mod-2^k homomorphism answers the whole
    // `low_bits` FAMILY at once. This is the law closure doing work no
    // per-query walk needs to repeat: if every operator in `f`'s answer
    // commutes with `x mod 2^k`, then `h(f(x)) = g(h(x))` for EVERY k with
    // g = f read in Z/2^k, so the input demand is `h` itself. ───────────────
    if (h == .low_bits) {
        const law = deriveRelationLaw(env, rel);
        if (law != null and law.?.ring_hom_mod_2k and law.?.pure) {
            env.census.admitted_by_law += 1;
            var out: [max_params]Projection = @splat(.none);
            for (0..fb.params.len) |i| out[i] = h;
            return out;
        }
    }

    const qi = env.tbl.getOrAdd(@intCast(rel), h) orelse {
        env.census.refuse(.budget);
        return null;
    };
    if (!env.solving) {
        env.solving = true;
        const settled = solve(env);
        env.solving = false;
        if (!settled) {
            env.census.refuse(.budget);
            return null;
        }
    }
    const q = &env.tbl.qs[qi];
    if (q.refused) |r| {
        env.census.refuse(r);
        return null;
    }
    if (q.updates > 1) env.census.recursive_queries += 1;
    env.census.admitted_by_fixpoint += 1;
    return q.params;
}

/// Ascending Kleene iteration to stability. Every query in the table is
/// recomputed each round; new queries discovered mid-round enter at ⊥ and are
/// picked up by the next round. Returns false on budget exhaustion, which the
/// caller reports as `unknown`.
fn solve(env: *Env) bool {
    var round: u32 = 0;
    while (true) {
        env.tbl.changed = false;
        var i: usize = 0;
        while (i < env.tbl.len) : (i += 1) {
            const rel = env.tbl.qs[i].rel;
            const h = env.tbl.qs[i].h;
            const fb = &env.rels[rel].decl.func;
            var params: [max_params]Projection = @splat(.none);
            var refused: ?Refusal = null;
            for (fb.params, 0..) |p, pi| {
                const r = answerProjection(env, h, &fb.body, p.name, 0);
                switch (r) {
                    .ok => |v| params[pi] = v,
                    .refuse => |x| {
                        refused = x;
                        break;
                    },
                }
            }
            // R3/R4 are properties of the ANSWER, not of one parameter, so they
            // are checked once per query rather than once per parameter.
            if (refused == null) {
                if (!onlyParams(&fb.body, fb.params)) refused = .captures_outer_name;
            }
            if (refused == null) {
                if (!answerInert(env, &fb.body)) refused = .not_inert;
            }
            env.tbl.set(i, params, refused);
        }
        round += 1;
        env.census.rounds_spent += 1;
        if (env.tbl.overflow) return false;
        if (!env.tbl.changed) return true;
        if (round >= max_rounds) return false;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// R2 — THE ANSWER FORM, AND R7 — THE EXTENDED DERIVATIVE
// ═══════════════════════════════════════════════════════════════════════════

const Answer = union(enum) {
    ok: Projection,
    refuse: Refusal,
};

fn refuseIf(cond: bool, r: Refusal, v: Projection) Answer {
    return if (cond) .{ .refuse = r } else .{ .ok = v };
}

/// R2. The projection of `name` demanded by a relation body whose value is
/// observed through `h`.
///
/// The admitted forms are exactly three, and the narrowness is the point: this
/// is the trusted core, and every form added to it is a form whose soundness
/// must be argued.
///
///   `<expr>`                     a block that is just its answer
///   `return <expr>`              the same, spelled with a keyword
///   `if c then A else B`         join of `nonzero` on c with `h` on both arms
fn answerProjection(
    env: *Env,
    h: Projection,
    b: *const ast.Block,
    name: []const u8,
    depth: u8,
) Answer {
    if (depth > max_depth) return .{ .refuse = .budget };
    if (b.stmts.len == 0) {
        const t = b.tail_expr orelse return .{ .refuse = .answer_form };
        return exprProjection(env, h, t, name, depth + 1);
    }
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| {
                if (r.vals.len != 1) return .{ .refuse = .answer_form };
                return exprProjection(env, h, r.vals[0], name, depth + 1);
            },
            .if_stmt => |f| {
                if (f.binding != null) return .{ .refuse = .answer_form };
                const eb = f.else_body orelse return .{ .refuse = .answer_form };
                // A branch CONDITION is observed only through its truth — the
                // same identity `demand_projection.zig` uses for `if_expr`.
                var acc = switch (exprProjection(env, .nonzero, f.cond, name, depth + 1)) {
                    .ok => |v| v,
                    .refuse => |x| return .{ .refuse = x },
                };
                for (f.elseifs) |ei| {
                    acc = Projection.join(acc, switch (exprProjection(env, .nonzero, ei.cond, name, depth + 1)) {
                        .ok => |v| v,
                        .refuse => |x| return .{ .refuse = x },
                    });
                    acc = Projection.join(acc, switch (answerProjection(env, h, &ei.body, name, depth + 1)) {
                        .ok => |v| v,
                        .refuse => |x| return .{ .refuse = x },
                    });
                }
                acc = Projection.join(acc, switch (answerProjection(env, h, &f.then, name, depth + 1)) {
                    .ok => |v| v,
                    .refuse => |x| return .{ .refuse = x },
                });
                acc = Projection.join(acc, switch (answerProjection(env, h, &eb, name, depth + 1)) {
                    .ok => |v| v,
                    .refuse => |x| return .{ .refuse = x },
                });
                return .{ .ok = acc };
            },
            else => return .{ .refuse = .answer_form },
        }
    }
    return .{ .refuse = .answer_form };
}

/// R7. The demand derivative, extended at ONE node.
///
/// **A call-free expression is handed to `demand_projection.projectionOfName`
/// verbatim.** That is not an optimisation, it is the anti-duplication rule:
/// there is one producer of `law.demand.derivative` and this module is not a
/// second one. Only subtrees that actually contain a call are walked here, and
/// their operator rules are taken from `demand_projection.lawsOf` — the one
/// producer of `law.relation.property` — rather than from a second list of
/// operator names.
fn exprProjection(
    env: *Env,
    h: Projection,
    e: *const ast.Expr,
    name: []const u8,
    depth: u8,
) Answer {
    if (depth > max_depth) return .{ .refuse = .budget };
    if (h == .none) return .{ .ok = .none };
    if (!containsCall(e)) return .{ .ok = dp.projectionOfName(h, e, name) };

    switch (e.*) {
        .call => |c| return callProjection(env, h, c, name, depth),

        .binop => |b| {
            // THE COMPARISON-WITH-THE-ABSORBING-ELEMENT IDENTITY. `x == 0` and
            // `x != 0` are `(x != 0)` composed with a two-element relation, so
            // the comparison's value is a function of the PROJECTION and not of
            // x. Against any other literal every bit is demanded.
            if (b.op == .eq or b.op == .neq) {
                if (isZeroLit(b.rhs)) return exprProjection(env, .nonzero, b.lhs, name, depth + 1);
                if (isZeroLit(b.lhs)) return exprProjection(env, .nonzero, b.rhs, name, depth + 1);
                return joinTwo(env, .whole, b.lhs, b.rhs, name, depth);
            }
            // THE MASK-NARROWING IDENTITY, and it is the same one, not a case:
            // `(x & (2^j - 1)) mod 2^k` is determined by `x mod 2^min(j,k)`.
            if (b.op == .band) {
                const k: ?u6 = switch (h) {
                    .whole => 63,
                    .low_bits => |kk| kk,
                    else => null,
                };
                if (k) |kk| {
                    if (intLit(b.rhs)) |m| if (lowMaskBits(m)) |j|
                        return exprProjection(env, .{ .low_bits = @min(j, kk) }, b.lhs, name, depth + 1);
                    if (intLit(b.lhs)) |m| if (lowMaskBits(m)) |j|
                        return exprProjection(env, .{ .low_bits = @min(j, kk) }, b.rhs, name, depth + 1);
                }
            }
            const sub = operandProjection(h, b.op);
            return joinTwo(env, sub, b.lhs, b.rhs, name, depth);
        },

        .unop => |u| switch (u.op) {
            .neg => return exprProjection(env, switch (h) {
                // Two's complement is a ring, and `-x != 0 <=> x != 0`
                // including at minInt, where `-minInt` wraps to minInt and
                // stays nonzero.
                .low_bits, .nonzero => h,
                else => .whole,
            }, u.operand, name, depth + 1),
            .not => return exprProjection(env, .nonzero, u.operand, name, depth + 1),
            .bnot => return exprProjection(env, switch (h) {
                .low_bits => h,
                else => .whole,
            }, u.operand, name, depth + 1),
            else => return .{ .refuse = .grammar },
        },

        .if_expr => |ie| {
            const c = switch (exprProjection(env, .nonzero, ie.cond, name, depth + 1)) {
                .ok => |v| v,
                .refuse => |x| return .{ .refuse = x },
            };
            const t = switch (exprProjection(env, h, ie.then_expr, name, depth + 1)) {
                .ok => |v| v,
                .refuse => |x| return .{ .refuse = x },
            };
            const f = switch (exprProjection(env, h, ie.else_expr, name, depth + 1)) {
                .ok => |v| v,
                .refuse => |x| return .{ .refuse = x },
            };
            return .{ .ok = Projection.join(c, Projection.join(t, f)) };
        },

        .sequence => |sq| {
            var acc: Projection = .none;
            for (sq.exprs) |x| {
                acc = Projection.join(acc, switch (exprProjection(env, h, x, name, depth + 1)) {
                    .ok => |v| v,
                    .refuse => |r| return .{ .refuse = r },
                });
            }
            return .{ .ok = acc };
        },

        // A form containing a call that this walk does not model. Refuse
        // rather than answer `whole`: the caller's fallback IS `whole`, and
        // routing through the refusal makes the census name the reason.
        else => return .{ .refuse = .grammar },
    }
}

fn joinTwo(
    env: *Env,
    sub: Projection,
    l: *const ast.Expr,
    r: *const ast.Expr,
    name: []const u8,
    depth: u8,
) Answer {
    const a = switch (exprProjection(env, sub, l, name, depth + 1)) {
        .ok => |v| v,
        .refuse => |x| return .{ .refuse = x },
    };
    const b = switch (exprProjection(env, sub, r, name, depth + 1)) {
        .ok => |v| v,
        .refuse => |x| return .{ .refuse = x },
    };
    return .{ .ok = Projection.join(a, b) };
}

/// The projection of an OPERAND sufficient to determine `h` of `x op y`,
/// **derived from `demand_projection.lawsOf`** — the tree's one producer of
/// relation law — instead of from a second table keyed on operator names.
///
///   `ring_hom_mod_2k`     `(x op y) mod 2^k` is determined by the operands
///                         mod 2^k, so `low_bits` passes through unchanged.
///   `bit_local`           output bit i depends on input bit i only — the same
///                         conclusion for every k, and it is why `&` and `^`
///                         are here without a separate rule.
///   `!can_zero_nonzero`   the relation cannot produce zero from a nonzero
///                         operand, so `nonzero` passes through. `|` is the
///                         only builtin with the fact, which is why `x | 4` is
///                         admitted where `x ~ 4` is refused.
///
/// Everything else demands every bit, which costs candidates and never costs
/// correctness.
pub fn operandProjection(h: Projection, op: ast.BinOp) Projection {
    const law = dp.lawsOf(op);
    return switch (h) {
        .none => .none,
        .low_bits => if (law.bit_local or law.ring_hom_mod_2k) h else .whole,
        .nonzero => if (!law.can_zero_nonzero) .nonzero else .whole,
        .whole => .whole,
    };
}

/// **THE CALL RULE — the one node this module adds to the derivative.**
///
///     h(f(a_1..a_n))  is determined by  p_1(a_1) .. p_n(a_n)
///     where  p = inducedInputProjection(h, f)
///
/// and the projection of `name` demanded through the call is the join of what
/// each argument demands of it at its own `p_i`. A refusal anywhere gives the
/// caller today's answer.
fn callProjection(env: *Env, h: Projection, c: anytype, name: []const u8, depth: u8) Answer {
    env.census.calls_examined += 1;
    // The callee position must not mention the name: a name used AS a callable
    // is read wholly and this module cannot say otherwise.
    if (mentionsShallow(c.func, name)) return .{ .refuse = .grammar };
    const rel = env.resolve(c) orelse return .{ .refuse = .callee_not_a_relation };
    const p = inducedInputProjection(env, rel, h) orelse return .{ .refuse = .no_gain };
    var acc: Projection = .none;
    for (c.args, 0..) |a, i| {
        acc = Projection.join(acc, switch (exprProjection(env, p[i], a, name, depth + 1)) {
            .ok => |v| v,
            .refuse => |x| return .{ .refuse = x },
        });
    }
    env.census.calls_admitted += 1;
    return .{ .ok = acc };
}

// ═══════════════════════════════════════════════════════════════════════════
// §22-23 — LAW CLOSURE FOR A USER-DEFINED RELATION
//
// `demand_projection.lawsOf` gives the law of a BUILTIN operator and
// `demand_projection.composeLaws` gives the rule for composing two — and until
// now `composeLaws` had no consumer outside its own unit test, because nothing
// in the tree ever composed anything. This is its consumer: a user relation's
// law is the fold of `composeLaws` over its answer, with nested user calls
// resolved recursively and a cycle refused.
// ═══════════════════════════════════════════════════════════════════════════

/// The law of a user-defined relation, DERIVED from its body. Null when any
/// node of the answer is outside the admitted algebra, when the relation
/// captures, or when the derivation is cyclic.
///
/// Memoized per relation. `computing` is a cycle marker: a recursive relation
/// has no law derived this way (its law is the fixpoint of the composition,
/// which this module does not solve — the PROJECTION fixpoint above is the one
/// it does solve, and it needs no law).
pub fn deriveRelationLaw(env: *Env, rel: usize) ?Law {
    // Public, index-taking, and it reads `env.rels[rel]` — the same door
    // `inducedInputProjection` had open. `blockLaw` below is bounded by the
    // params check inside it, so this one only has to bound the index.
    if (rel >= env.len) return null;
    switch (env.rels[rel].law_state) {
        .derived => return env.rels[rel].law,
        .refused, .computing => return null,
        .unknown => {},
    }
    env.rels[rel].law_state = .computing;
    const fb = &env.rels[rel].decl.func;
    const l = blk: {
        if (fb.vararg or fb.vararg_name != null or fb.params.len > max_params) break :blk null;
        if (!onlyParams(&fb.body, fb.params)) break :blk null;
        if (!answerInert(env, &fb.body)) break :blk null;
        break :blk blockLaw(env, &fb.body, 0);
    };
    if (l) |v| {
        env.rels[rel].law = v;
        env.rels[rel].law_state = .derived;
        return v;
    }
    env.rels[rel].law_state = .refused;
    return null;
}

/// The identity of the fold: a bare parameter or literal carries every law a
/// value can carry, because `x mod 2^k` of it is determined by `x mod 2^k`.
const leaf_law: Law = .{
    .pure = true,
    .commutative = true,
    .associative = true,
    .idempotent = true,
    .bit_local = true,
    .ring_hom_mod_2k = true,
    .monotone_nonneg = true,
    .has_absorbing = false,
    .can_zero_nonzero = true,
};

fn blockLaw(env: *Env, b: *const ast.Block, depth: u8) ?Law {
    if (depth > max_depth) return null;
    if (b.stmts.len == 0) return exprLaw(env, b.tail_expr orelse return null, depth + 1);
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| {
                if (r.vals.len != 1) return null;
                return exprLaw(env, r.vals[0], depth + 1);
            },
            // A branch is a SELECTION, and selection is not a mod-2^k
            // homomorphism: the branch taken depends on the whole condition.
            // Refusing it here is what keeps the fast path honest — the
            // fixpoint route below still handles such a relation, it just does
            // not get the whole-family shortcut.
            else => return null,
        }
    }
    return null;
}

fn exprLaw(env: *Env, e: *const ast.Expr, depth: u8) ?Law {
    if (depth > max_depth) return null;
    return switch (e.*) {
        .int_lit, .name => leaf_law,
        .unop => |u| switch (u.op) {
            .neg, .bnot => dp.composeLaws(
                if (u.op == .neg) dp.lawsOf(.sub) else .{ .pure = true, .bit_local = true, .ring_hom_mod_2k = true, .can_zero_nonzero = true },
                exprLaw(env, u.operand, depth + 1) orelse return null,
            ),
            else => null,
        },
        .binop => |b| {
            const own = dp.lawsOf(b.op);
            if (!own.ring_hom_mod_2k) return null;
            const l = exprLaw(env, b.lhs, depth + 1) orelse return null;
            const r = exprLaw(env, b.rhs, depth + 1) orelse return null;
            // §22-23 compositional derivation, both operands: the composite
            // carries a law only when the operator and BOTH arguments do.
            return dp.composeLaws(dp.composeLaws(own, l), r);
        },
        // **A NESTED USER CALL IS THE POINT.** `mix(scramble(x))` gets its law
        // from both, by the same composition rule as `a + b` gets its from
        // both. Nothing here knows either name.
        .call => |c| {
            const rel = env.resolve(c) orelse return null;
            const callee = deriveRelationLaw(env, rel) orelse return null;
            var acc = callee;
            for (c.args) |a| {
                acc = dp.composeLaws(acc, exprLaw(env, a, depth + 1) orelse return null);
            }
            return acc;
        },
        else => null,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// §17 × §26 — **THE CALL ADMISSION FOR A MACHINE THAT RUNS IN THE QUOTIENT.**
//
// `src/obseq.zig` and `src/recurrence.zig` both walk a loop's state machine in
// `Z/2^k` and both REFUSE a call outright, for the same stated reason: a call
// is opaque to a grammar built out of operators, and an opaque node in a
// quotiented machine is a node that may not commute with the quotient.
//
// `deriveRelationLaw` is exactly the fact that answers them. When it reports
// `ring_hom_mod_2k` for a USER-DEFINED relation the compiler was never told
// about, it has PROVEN
//
//     f(x) mod 2^k  =  f(x mod 2^k) mod 2^k
//
// compositionally, from the callee's own body — which IS the admission
// condition those two files spell for `+ - * & | ^ ~` and nothing else. So the
// call joins their grammar not as a special case but as the same rule applied
// to a relation instead of an operator, and §106's test ("can the loop run for
// an ARBITRARY USER-DEFINED RELATION?") is answered by the SAME mechanism that
// answers it for `+`.
//
// WHAT THE ADMISSION DOES NOT COVER, stated because a narrow class honestly
// named is worth more than a wide one asserted:
//
//   * `blockLaw` refuses a branch — selection is not a mod-2^k homomorphism —
//     so an admitted answer is ONE straight-line expression. A relation with
//     an `if` is refused here and still goes through the PROJECTION fixpoint,
//     which is the other half of this file and needs no law.
//   * A recursive relation is refused: `deriveRelationLaw` marks `computing`
//     and a cycle answers null. **This is what makes `evalAnswer` terminate by
//     STRUCTURE rather than by budget** — an admitted call graph is a finite
//     DAG, so there is no step limit to tune and none is offered.
//   * `/ % // **` carry no `ring_hom_mod_2k` in `demand_projection.lawsOf`, so
//     they are refused by the law derivation before this code is reached.
//
// §84 BY SIGNATURE: `admitInQuotient` takes an environment and an expression
// and NO cost parameter. There is no argument through which a measurement
// could admit a call the law refuses.
// ═══════════════════════════════════════════════════════════════════════════

/// The fact a quotiented machine needs about one call site: which relation it
/// resolves to, and the law that lets its value be computed over PROJECTED
/// arguments instead of exact ones.
pub const QuotientCall = struct {
    rel: usize,
    law: Law,
};

/// Admit — or refuse — a call inside a machine quotiented by `x mod 2^k`.
///
/// Null means "leave the call opaque", which is every caller's existing
/// behaviour, so a refusal costs candidates and can never cost an answer.
pub fn admitInQuotient(env: *Env, c: anytype) ?QuotientCall {
    env.census.calls_examined += 1;
    const rel = env.resolve(c) orelse return null;
    const law = deriveRelationLaw(env, rel) orelse {
        env.census.refuse(.answer_form);
        return null;
    };
    // PURE is not implied by the homomorphism and is not folded into it: a
    // relation could carry the arithmetic law and still write. `answerInert`
    // already refused effects, and this is the second reading of the same
    // fact through the law rather than a second authority for it.
    if (!law.pure or !law.ring_hom_mod_2k) {
        env.census.refuse(.no_gain);
        return null;
    }
    env.census.calls_admitted += 1;
    env.census.admitted_by_law += 1;
    return .{ .rel = rel, .law = law };
}

/// The admitted relation's answer at CONCRETE arguments, in the ring.
///
/// i64 here is wrapping two's complement mod 2^64 — the same ring
/// `recurrence.zig`'s O3 measures on both of its paths — so the value returned
/// is `f(args)` exactly, and the caller applies `h` to it. Because the caller
/// hands PROJECTED arguments, what it obtains is `h(f(h(x)))`, and
/// `ring_hom_mod_2k` is precisely the proof that this equals `h(f(x))`.
///
/// Terminates by structure: `admitInQuotient` refused recursion, so the walk
/// is over a finite DAG. `max_depth` is a table-space guard, not a budget that
/// could silently truncate a real answer — exceeding it is a refusal.
pub fn evalAnswer(env: *Env, rel: usize, args: []const i64) ?i64 {
    // The same bound `inducedInputProjection` states, for the same reason: a
    // public entry taking a bare relation index cannot inherit R5 from
    // `Env.resolve`, and `args` is indexed by parameter number.
    if (rel >= env.len) return null;
    const fb = &env.rels[rel].decl.func;
    if (fb.params.len != args.len or args.len > max_params) return null;
    if (fb.vararg or fb.vararg_name != null) return null;
    return evalBlock(env, &fb.body, fb.params, args, 0);
}

fn evalBlock(
    env: *Env,
    b: *const ast.Block,
    params: []const ast.FuncParam,
    args: []const i64,
    depth: u8,
) ?i64 {
    if (depth > max_depth) return null;
    if (b.stmts.len == 0) return evalExpr(env, b.tail_expr orelse return null, params, args, depth + 1);
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| {
                if (r.vals.len != 1) return null;
                return evalExpr(env, r.vals[0], params, args, depth + 1);
            },
            // The same refusal `blockLaw` makes, and it must be the same one:
            // a shape this evaluates but the law derivation refuses would be a
            // second, wider admitted class with no proof behind it.
            else => return null,
        }
    }
    return null;
}

fn evalExpr(
    env: *Env,
    e: *const ast.Expr,
    params: []const ast.FuncParam,
    args: []const i64,
    depth: u8,
) ?i64 {
    if (depth > max_depth) return null;
    return switch (e.*) {
        .int_lit => |x| x.val,
        .name => |x| blk: {
            for (params, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, x.ident)) break :blk args[i];
            }
            // R3 already refused a capture; reaching here would mean the law
            // was derived for a body this cannot read, so it refuses.
            break :blk null;
        },
        .unop => |u| switch (u.op) {
            .neg => 0 -% (evalExpr(env, u.operand, params, args, depth + 1) orelse return null),
            .bnot => ~(evalExpr(env, u.operand, params, args, depth + 1) orelse return null),
            else => null,
        },
        .binop => |b| blk: {
            // THE OPERATOR SET IS NOT LISTED TWICE. It is read off the one
            // producer of relation law, exactly as `exprLaw` reads it, so the
            // evaluator cannot admit an operator the derivation refused.
            if (!dp.lawsOf(b.op).ring_hom_mod_2k) break :blk null;
            const l = evalExpr(env, b.lhs, params, args, depth + 1) orelse break :blk null;
            const r = evalExpr(env, b.rhs, params, args, depth + 1) orelse break :blk null;
            break :blk switch (b.op) {
                .add => l +% r,
                .sub => l -% r,
                .mul => l *% r,
                .band => l & r,
                .bor => l | r,
                .bxor => l ^ r,
                else => null,
            };
        },
        .call => |c| blk: {
            const inner = admitInQuotient(env, c) orelse break :blk null;
            var sub: [max_params]i64 = @splat(0);
            for (c.args, 0..) |a, i| {
                sub[i] = evalExpr(env, a, params, args, depth + 1) orelse break :blk null;
            }
            break :blk evalAnswer(env, inner.rel, sub[0..c.args.len]);
        },
        else => null,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// R3 and R4 — capture and inertness
// ═══════════════════════════════════════════════════════════════════════════

/// R3. Every name the answer reads is a parameter. FAILS CLOSED: an AST
/// variant not enumerated counts as a capture.
fn onlyParams(b: *const ast.Block, params: []const ast.FuncParam) bool {
    if (b.stmts.len == 0) {
        const t = b.tail_expr orelse return false;
        return exprOnlyParams(t, params);
    }
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| {
                if (r.vals.len != 1) return false;
                return exprOnlyParams(r.vals[0], params);
            },
            .if_stmt => |f| {
                if (f.binding != null) return false;
                const eb = f.else_body orelse return false;
                if (!exprOnlyParams(f.cond, params)) return false;
                for (f.elseifs) |ei| {
                    if (!exprOnlyParams(ei.cond, params)) return false;
                    if (!onlyParams(&ei.body, params)) return false;
                }
                return onlyParams(&f.then, params) and onlyParams(&eb, params);
            },
            else => return false,
        }
    }
    return false;
}

fn isParam(n: []const u8, params: []const ast.FuncParam) bool {
    for (params) |p| if (std.mem.eql(u8, p.name, n)) return true;
    return false;
}

fn exprOnlyParams(e: *const ast.Expr, params: []const ast.FuncParam) bool {
    return switch (e.*) {
        .int_lit, .true_lit, .false_lit, .nil => true,
        .name => |x| isParam(x.ident, params),
        .unop => |u| exprOnlyParams(u.operand, params),
        .binop => |b| exprOnlyParams(b.lhs, params) and exprOnlyParams(b.rhs, params),
        .if_expr => |ie| exprOnlyParams(ie.cond, params) and
            exprOnlyParams(ie.then_expr, params) and
            exprOnlyParams(ie.else_expr, params),
        // A CALLEE NAME IS NOT A CAPTURE — it is a relation, and R1 already
        // proved nothing rebinds it. Its ARGUMENTS still are.
        .call => |c| blk: {
            if (c.func.* != .name) break :blk false;
            for (c.args) |a| if (!exprOnlyParams(a, params)) break :blk false;
            break :blk true;
        },
        else => false,
    };
}

/// R4. `demand.inert` — the ONE producer of the trap/effect fact — for every
/// node of the answer that is not itself a call. A call is decomposed rather
/// than asked, because `inert` refuses every call it cannot see through and
/// the whole point here is to see through exactly the ones R1 resolved.
fn answerInert(env: *Env, b: *const ast.Block) bool {
    if (b.stmts.len == 0) return exprInert(env, b.tail_expr orelse return false);
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| return r.vals.len == 1 and exprInert(env, r.vals[0]),
            .if_stmt => |f| {
                if (f.binding != null) return false;
                const eb = f.else_body orelse return false;
                if (!exprInert(env, f.cond)) return false;
                for (f.elseifs) |ei| {
                    if (!exprInert(env, ei.cond)) return false;
                    if (!answerInert(env, &ei.body)) return false;
                }
                return answerInert(env, &f.then) and answerInert(env, &eb);
            },
            else => return false,
        }
    }
    return false;
}

fn exprInert(env: *Env, e: *const ast.Expr) bool {
    if (!containsCall(e)) return demand.inert(env.opts, e) == null;
    return switch (e.*) {
        .unop => |u| exprInert(env, u.operand),
        .binop => |b| switch (b.op) {
            // The trapping arithmetic, refused in the presence of a call
            // because the divisor is then not a literal this walk can pin.
            .div, .idiv, .mod, .pow => false,
            else => exprInert(env, b.lhs) and exprInert(env, b.rhs),
        },
        .if_expr => |ie| exprInert(env, ie.cond) and exprInert(env, ie.then_expr) and exprInert(env, ie.else_expr),
        .call => |c| blk: {
            const rel = env.resolve(c) orelse break :blk false;
            for (c.args) |a| if (!exprInert(env, a)) break :blk false;
            // Recursion terminates because a relation whose inertness is being
            // decided is marked `computing` by the law derivation, and because
            // the answer grammar has no loops. A self-call reaches this line
            // once per nesting level of the ANSWER, which `max_depth` bounds.
            break :blk answerInertGuarded(env, rel, 0);
        },
        else => false,
    };
}

fn answerInertGuarded(env: *Env, rel: usize, depth: u8) bool {
    if (depth > max_depth) return false;
    // A relation whose own answer is currently being checked is assumed inert
    // for the purpose of closing the recursion — the co-inductive reading, and
    // it is sound here because the grammar admits no effect and no trap: the
    // ONLY thing a cycle can add is non-termination, and a recursive answer
    // that does not terminate returns no value at all, so the caller's
    // observation is never reached. `demand_projection.zig`'s P6 owns
    // termination for the LOOP; this is the relation's own.
    if (env.rels[rel].inert_state == .computing) return true;
    if (env.rels[rel].inert_state == .yes) return true;
    if (env.rels[rel].inert_state == .no) return false;
    env.rels[rel].inert_state = .computing;
    const ok = answerInert(env, &env.rels[rel].decl.func.body);
    env.rels[rel].inert_state = if (ok) .yes else .no;
    return ok;
}

// ═══════════════════════════════════════════════════════════════════════════
// Small shared readers
// ═══════════════════════════════════════════════════════════════════════════

/// True when `e` contains a `call` or `method_call` node anywhere.
///
/// FALSE for an AST variant this does not enumerate, which routes it to
/// `demand_projection.projectionOfName` — the one producer — whose own
/// fallback is `mentions(e, n) -> .whole`, itself fail-closed. So an
/// unmodelled node is answered by one conservative rule rather than two.
pub fn containsCall(e: *const ast.Expr) bool {
    return switch (e.*) {
        .call, .method_call => true,
        .unop => |u| containsCall(u.operand),
        .binop => |b| containsCall(b.lhs) or containsCall(b.rhs),
        .index => |x| containsCall(x.obj) or containsCall(x.key),
        .field => |x| containsCall(x.obj),
        .if_expr => |ie| containsCall(ie.cond) or containsCall(ie.then_expr) or containsCall(ie.else_expr),
        .sequence => |sq| blk: {
            for (sq.exprs) |x| if (containsCall(x)) break :blk true;
            break :blk false;
        },
        .range => |r| blk: {
            if (containsCall(r.start) or containsCall(r.end)) break :blk true;
            if (r.step) |st| if (containsCall(st)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn mentionsShallow(e: *const ast.Expr, n: []const u8) bool {
    return switch (e.*) {
        .name => |x| std.mem.eql(u8, x.ident, n),
        else => true,
    };
}

fn intLit(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |l| l.val,
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const v = intLit(u.operand) orelse break :blk null;
                break :blk -%v;
            },
            else => null,
        },
        else => null,
    };
}

fn isZeroLit(e: *const ast.Expr) bool {
    const v = intLit(e) orelse return false;
    return v == 0;
}

fn lowMaskBits(m: i64) ?u6 {
    if (m <= 0) return null;
    const u: u64 = @bitCast(m);
    if (u & (u + 1) != 0) return null;
    const k = @popCount(u);
    if (k == 0 or k > 63) return null;
    return @intCast(k);
}

// ═══════════════════════════════════════════════════════════════════════════
// THE SEAM — how a held file consults this one
//
// `demand_projection.projectionOfName` takes `(h, e, n)` and has no place to
// carry a relation table, and threading one through its twenty recursive call
// sites is a change to a file this lane does not own. The routed patch
// `patches/demand_projection-call-law.patch` adds a two-line seam there
// instead: a nullable context pointer and a nullable function pointer, both
// defaulting to null so an unpatched tree behaves EXACTLY as it does today.
//
// The signature below is written so that no type is shared across the seam —
// `*const anyopaque` in, `dp.Projection` out — which is what lets this file
// compile with or without the patch. `@hasDecl` decides.
// ═══════════════════════════════════════════════════════════════════════════

/// The function the seam installs. Never call it directly; `install` does.
pub fn deriveCallProjection(
    ctx: *const anyopaque,
    h: Projection,
    e: *const ast.Expr,
    n: []const u8,
) Projection {
    const env: *Env = @constCast(@ptrCast(@alignCast(ctx)));
    return switch (exprProjection(env, h, e, n, 0)) {
        .ok => |v| v,
        // TODAY'S ANSWER ON EVERY REFUSAL: `whole` if the expression could
        // reach the name at all, `none` if it provably cannot. A refusal costs
        // candidates and can never cost an answer.
        .refuse => if (dpMentions(e, n)) .whole else .none,
    };
}

/// `demand_projection.mentions` is private; this asks the same question through
/// its public face — `projectionOfName(.whole, e, n) != .none` IS `mentions`
/// for a call-free expression — and mirrors its recursion for the forms that
/// carry a call.
///
/// THE PRECISION HERE IS NOT COSMETIC. Answering `whole` for every call would
/// make `seen(other)` observe `hits`, and a loop whose accumulator is untouched
/// by the continuation would stop being a candidate. A seam that costs
/// candidates the unpatched compiler already had is a regression, so the
/// fallback has to be exactly as sharp as the thing it falls back to.
fn dpMentions(e: *const ast.Expr, n: []const u8) bool {
    return switch (e.*) {
        .call => |c| blk: {
            if (dpMentions(c.func, n)) break :blk true;
            for (c.args) |a| if (dpMentions(a, n)) break :blk true;
            break :blk false;
        },
        .method_call => |m| blk: {
            if (dpMentions(m.obj, n)) break :blk true;
            for (m.args) |a| if (dpMentions(a, n)) break :blk true;
            break :blk false;
        },
        .unop => |u| dpMentions(u.operand, n),
        .binop => |b| dpMentions(b.lhs, n) or dpMentions(b.rhs, n),
        .index => |x| dpMentions(x.obj, n) or dpMentions(x.key, n),
        .field => |x| dpMentions(x.obj, n),
        .if_expr => |ie| dpMentions(ie.cond, n) or dpMentions(ie.then_expr, n) or dpMentions(ie.else_expr, n),
        .sequence => |sq| blk: {
            for (sq.exprs) |x| if (dpMentions(x, n)) break :blk true;
            break :blk false;
        },
        .range => |r| blk: {
            if (dpMentions(r.start, n) or dpMentions(r.end, n)) break :blk true;
            if (r.step) |st| if (dpMentions(st, n)) break :blk true;
            break :blk false;
        },
        else => dp.projectionOfName(.whole, e, n) != .none,
    };
}

pub fn install(env: *Env) void {
    if (!@hasDecl(dp, "call_law_derive")) return;
    dp.call_law_ctx = env;
    dp.call_law_derive = &deriveCallProjection;
}

pub fn uninstall() void {
    if (!@hasDecl(dp, "call_law_derive")) return;
    dp.call_law_ctx = null;
    dp.call_law_derive = null;
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
//
// Every claim in the header is a test below, and every REFUSAL is a test too:
// a synthesizer whose refusals are untested is a synthesizer whose soundness
// is a comment.
// ═══════════════════════════════════════════════════════════════════════════

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
    var lex = Lexer.init(owned, "quotient_synth_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    const mod = try p.parse_module();
    return .{ .arena = arena, .mod = mod };
}

/// The projection the analysis would compute for the module's `main` tail,
/// which is the number the whole mechanism exists to move.
fn tailProjection(env: *Env, mod: *const ast.Module, name: []const u8) Projection {
    for (mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        if (!std.mem.eql(u8, s.func_decl.path[0], "main")) continue;
        const t = s.func_decl.func.body.tail_expr orelse return .whole;
        return deriveCallProjection(env, .whole, t, name);
    }
    return .whole;
}

const src_direct =
    \\seen: i64 = (n: i64)
    \\    if n != 0
    \\        1
    \\    else
    \\        0
    \\
    \\main: i64 = ()
    \\    hits = 0
    \\    seen(hits)
;

const src_recursive =
    \\seen: i64 = (n: i64, k: i64)
    \\    if k == 0
    \\        if n != 0
    \\            1
    \\        else
    \\            0
    \\    else
    \\        seen(n, k - 1)
    \\
    \\main: i64 = ()
    \\    hits = 0
    \\    seen(hits, 4)
;

const src_recursive_identity =
    \\seen: i64 = (n: i64, k: i64)
    \\    if k == 0
    \\        n
    \\    else
    \\        seen(n, k - 1)
    \\
    \\main: i64 = ()
    \\    hits = 0
    \\    seen(hits, 4)
;

const src_recursive_shifted =
    \\seen: i64 = (n: i64, k: i64)
    \\    if k == 0
    \\        if n != 0
    \\            1
    \\        else
    \\            0
    \\    else
    \\        seen(n + 1, k - 1)
    \\
    \\main: i64 = ()
    \\    hits = 0
    \\    seen(hits, 4)
;

test "the loop runs for a relation nobody listed" {
    var fx = try parse(src_direct);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.nonzero));
    try std.testing.expectEqual(@as(u32, 1), env.census.calls_admitted);
}

test "R6 — a RECURSIVE relation, where substitution has nothing to iterate" {
    var fx = try parse(src_recursive);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    // The whole claim of this lane in one assertion: `hits` is demanded only
    // through `!= 0`, and the fact came out of a fixpoint over a relation the
    // compiler was never told about and cannot inline.
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.nonzero));
    try std.testing.expect(env.census.rounds_spent >= 2);
}

test "ADVERSARIAL CONTROL — the identity base case must NOT admit" {
    // `seen(n, k) = n` after k steps. Truncating the caller's loop would make
    // the program answer 1 where it must answer 101, so `whole` is the only
    // sound answer and anything else is a wrong answer with a fast clock.
    var fx = try parse(src_recursive_identity);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.whole));
}

test "ADVERSARIAL CONTROL — one added character breaks the fixpoint" {
    // `seen(n + 1, k - 1)`: the recursive call SHIFTS the argument, so
    // `(hits + 4) != 0` is not determined by `hits != 0`. The fixpoint ascends
    // to `whole` on its own — nothing here recognises the shape.
    var fx = try parse(src_recursive_shifted);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.whole));
}

test "R1 — a rebound relation name is not a relation" {
    var fx = try parse(
        \\seen: i64 = (n: i64)
        \\    if n != 0
        \\        1
        \\    else
        \\        0
        \\
        \\main: i64 = ()
        \\    hits = 0
        \\    seen = 3
        \\    seen(hits)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.whole));
    try std.testing.expect(env.census.relations_rebound >= 1);
}

test "R3 — a captured module-scope name refuses" {
    var fx = try parse(
        \\global bias = 7
        \\
        \\seen: i64 = (n: i64)
        \\    if n != bias
        \\        1
        \\    else
        \\        0
        \\
        \\main: i64 = ()
        \\    hits = 0
        \\    seen(hits)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.whole));
}

test "R4 — an effect in the answer refuses" {
    var fx = try parse(
        \\seen: i64 = (n: i64)
        \\    print(n)
        \\
        \\main: i64 = ()
        \\    hits = 0
        \\    seen(hits)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    // `print` is not a module relation, so the inner call refuses and the
    // outer one inherits it. The answer is `whole`, which is what keeps a
    // printed argument observable.
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.whole));
}

test "the width family — a mod-2^k homomorphism carries low_bits through" {
    var fx = try parse(
        \\mix: i64 = (n: i64)
        \\    n * 1103515245 + 12345
        \\
        \\main: i64 = ()
        \\    s = 0
        \\    mix(s) & 255
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    for (fx.mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        if (!std.mem.eql(u8, s.func_decl.path[0], "main")) continue;
        const t = s.func_decl.func.body.tail_expr.?;
        // `x & 255` observed wholly demands `low_bits 8` of x, and `mix` is a
        // proven ring homomorphism mod 2^k, so `low_bits 8` of `s` suffices.
        const p = deriveCallProjection(&env, .whole, t, "s");
        try std.testing.expect(p.eql(.{ .low_bits = 8 }));
    }
    // And it came from the LAW, not from a walk per k.
    try std.testing.expect(env.census.admitted_by_law >= 1);
}

test "§22-23 — the law is composed through a nested user call, not looked up" {
    var fx = try parse(
        \\inner: i64 = (n: i64)
        \\    n * 6364136223 + 1
        \\
        \\outer: i64 = (n: i64)
        \\    inner(n) ~ 12345
        \\
        \\main: i64 = ()
        \\    s = 0
        \\    outer(s) & 255
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const outer = env.indexOf("outer").?;
    const law = deriveRelationLaw(&env, outer) orelse return error.TestUnexpectedResult;
    try std.testing.expect(law.ring_hom_mod_2k);
    try std.testing.expect(law.pure);
}

test "§22-23 — a relation that divides carries no mod-2^k law" {
    var fx = try parse(
        \\bad: i64 = (n: i64)
        \\    n // 3
        \\
        \\main: i64 = ()
        \\    s = 0
        \\    bad(s) & 255
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const bad = env.indexOf("bad").?;
    try std.testing.expect(deriveRelationLaw(&env, bad) == null);
}

test "the width family, end to end — one mask literal apart" {
    // The measured pair in `gate/quotsyn.sh`, pinned at the analysis level so a
    // regression is caught without a two-second loop. `tag(n) = n & 15` makes
    // the writers 16 and 32 indistinguishable and the loop closes; `n & 255`
    // makes them distinguishable and it must not.
    const win =
        \\tag: i64 = (n: i64)
        \\    n & 15
        \\
        \\main: i64 = ()
        \\    flag = 1
        \\    tag(flag)
    ;
    const ctl =
        \\tag: i64 = (n: i64)
        \\    n & 255
        \\
        \\main: i64 = ()
        \\    flag = 1
        \\    tag(flag)
    ;
    var a = try parse(win);
    defer a.deinit();
    var ea = Env.scan(&a.mod, .{});
    try std.testing.expect(tailProjection(&ea, &a.mod, "flag").eql(.{ .low_bits = 4 }));

    var b = try parse(ctl);
    defer b.deinit();
    var eb = Env.scan(&b.mod, .{});
    try std.testing.expect(tailProjection(&eb, &b.mod, "flag").eql(.{ .low_bits = 8 }));
}

test "a call that cannot reach the name observes nothing of it" {
    // The seam must be exactly as sharp as the fallback it replaces. If a call
    // mentioning some OTHER name answered `whole`, every loop whose accumulator
    // is untouched by the continuation would stop being a candidate — a seam
    // that costs candidates the unpatched compiler already had.
    var fx = try parse(
        \\opaque_one: i64 = (n: i64)
        \\    n // 3
        \\
        \\main: i64 = ()
        \\    hits = 0
        \\    other = 5
        \\    opaque_one(other)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    try std.testing.expect(tailProjection(&env, &fx.mod, "hits").eql(.none));
    try std.testing.expect(tailProjection(&env, &fx.mod, "other").eql(.whole));
}

test "R7 — the extended derivative AGREES with the one producer on call-free terms" {
    // The anti-duplication control. If these two ever disagree the tree has
    // two semantics for one algebra, which is the defect this file's header
    // promises not to introduce.
    var fx = try parse(
        \\main: i64 = ()
        \\    p = 0
        \\    q = 0
        \\    (p * 7 + 3) & 1023
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const t = fx.mod.body.stmts[0].func_decl.func.body.tail_expr.?;
    const hs = [_]Projection{ .none, .nonzero, .{ .low_bits = 1 }, .{ .low_bits = 8 }, .{ .low_bits = 32 }, .whole };
    for (hs) |h| {
        for ([_][]const u8{ "p", "q" }) |n| {
            const mine = switch (exprProjection(&env, h, t, n, 0)) {
                .ok => |v| v,
                .refuse => return error.TestUnexpectedResult,
            };
            try std.testing.expect(mine.eql(dp.projectionOfName(h, t, n)));
        }
    }
}

test "the derived operand rule matches the one producer for every builtin op" {
    // `operandProjection` is derived from `lawsOf`. This asserts the derivation
    // reproduces `projectionOfName`'s hand-written operator switch everywhere
    // it applies, so the law table is the authority and the switch is its
    // consequence rather than a second opinion.
    const ops = [_]ast.BinOp{ .add, .sub, .mul, .band, .bor, .bxor };
    for (ops) |op| {
        try std.testing.expect(operandProjection(.none, op) == .none);
        // low_bits passes through every ring homomorphism and every bit-local
        // relation, which is every operator in the list.
        try std.testing.expect(operandProjection(.{ .low_bits = 8 }, op).eql(.{ .low_bits = 8 }));
        // nonzero passes through `|` alone.
        const expected: Projection = if (op == .bor) .nonzero else .whole;
        try std.testing.expect(operandProjection(.nonzero, op).eql(expected));
    }
    // And an operator with no law demands everything.
    try std.testing.expect(operandProjection(.{ .low_bits = 8 }, .idiv).eql(.whole));
    try std.testing.expect(operandProjection(.nonzero, .idiv).eql(.whole));
}

test "VALIDATION — h(f(x)) = g(h(x)) on the admitted relations, differentially" {
    // The proof is structural; this is the validation obligation on top of it.
    // For every admitted relation and every x, the claim is that two inputs
    // agreeing under the DERIVED input projection agree under `h` of the
    // result. Checked by evaluating the relation twice over inputs chosen to
    // agree on the projection and differ everywhere else.
    var fx = try parse(src_recursive);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const rel = env.indexOf("seen").?;
    const p = inducedInputProjection(&env, rel, .whole) orelse return error.TestUnexpectedResult;
    try std.testing.expect(p[0].eql(.nonzero));

    var rng = std.Random.DefaultPrng.init(0x5eed);
    const r = rng.random();
    var trial: usize = 0;
    while (trial < 4096) : (trial += 1) {
        const x = r.int(i64);
        const y = r.int(i64);
        // Two inputs that agree under `p[0]` — both zero or both nonzero.
        const xa: i64 = if (trial % 2 == 0) 0 else (if (x == 0) 1 else x);
        const ya: i64 = if (trial % 2 == 0) 0 else (if (y == 0) 1 else y);
        try std.testing.expectEqual(seenOracle(xa, 4), seenOracle(ya, 4));
    }
    // And the control: inputs that DISAGREE under the projection must be
    // allowed to differ, or the projection is not the coarsest one.
    try std.testing.expect(seenOracle(0, 4) != seenOracle(7, 4));
}

/// A hand-written model of `src_recursive`'s `seen`, deliberately NOT this
/// module's evaluator: a differential test against your own interpreter proves
/// only that it agrees with itself.
fn seenOracle(n: i64, k: i64) i64 {
    if (k == 0) return if (n != 0) 1 else 0;
    return seenOracle(n, k - 1);
}

// ═══════════════════════════════════════════════════════════════════════════
// THE CALL ADMISSION FOR A QUOTIENTED MACHINE — every claim, and every refusal
// ═══════════════════════════════════════════════════════════════════════════

const src_ringhom =
    \\step: i64 = (n: i64)
    \\    (n ~ (n * 1103515245)) + 12345
    \\
    \\main: i64 = ()
    \\    step(7)
;

fn stepOracle(n: i64) i64 {
    return (n ^ (n *% 1103515245)) +% 12345;
}

test "quotient synth: a straight-line user relation is admitted into the quotient" {
    var fx = try parse(src_ringhom);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const rel = env.indexOf("step").?;
    const law = deriveRelationLaw(&env, rel) orelse return error.TestUnexpectedResult;
    try std.testing.expect(law.ring_hom_mod_2k and law.pure);

    // DIFFERENTIAL against a hand-written model with the same wrapping
    // arithmetic, over the whole i64 range. `evalAnswer` agreeing with itself
    // would prove nothing.
    var rng = std.Random.DefaultPrng.init(0xC0FFEE);
    const r = rng.random();
    var trial: usize = 0;
    while (trial < 4096) : (trial += 1) {
        const x = r.int(i64);
        const got = evalAnswer(&env, rel, &.{x}) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(stepOracle(x), got);
    }
}

test "quotient synth: THE HOMOMORPHISM ITSELF, checked rather than asserted" {
    // The admission's whole claim is `f(x) mod 2^k = f(x mod 2^k) mod 2^k`.
    // A quotiented machine hands PROJECTED arguments over, so if this identity
    // is false the answer is wrong, not merely imprecise.
    var fx = try parse(src_ringhom);
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const rel = env.indexOf("step").?;

    var rng = std.Random.DefaultPrng.init(0xBEEF);
    const r = rng.random();
    var k: u6 = 1;
    while (k < 32) : (k += 1) {
        const mask: i64 = @bitCast((@as(u64, 1) << k) - 1);
        var trial: usize = 0;
        while (trial < 256) : (trial += 1) {
            const x = r.int(i64);
            const exact = evalAnswer(&env, rel, &.{x}) orelse return error.TestUnexpectedResult;
            const projected = evalAnswer(&env, rel, &.{x & mask}) orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(exact & mask, projected & mask);
        }
    }
}

test "quotient synth: a nested user call composes, and nothing knows either name" {
    var fx = try parse(
        \\inner: i64 = (n: i64)
        \\    n * 1103515245
        \\
        \\outer: i64 = (n: i64)
        \\    (n ~ inner(n)) + 12345
        \\
        \\main: i64 = ()
        \\    outer(3)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const rel = env.indexOf("outer").?;
    const law = deriveRelationLaw(&env, rel) orelse return error.TestUnexpectedResult;
    try std.testing.expect(law.ring_hom_mod_2k and law.pure);
    // Identical to `step` above, written through a second relation.
    try std.testing.expectEqual(stepOracle(99), evalAnswer(&env, rel, &.{99}).?);
}

test "quotient synth: the refusals a quotiented machine depends on" {
    // A BRANCH. Selection is not a mod-2^k homomorphism — the branch taken
    // reads the WHOLE condition — so `seen` must not be admitted here even
    // though the projection fixpoint handles it perfectly well.
    {
        var fx = try parse(
            \\seen: i64 = (n: i64)
            \\    if n != 0
            \\        1
            \\    else
            \\        0
            \\
            \\main: i64 = ()
            \\    seen(3)
        );
        defer fx.deinit();
        var env = Env.scan(&fx.mod, .{});
        try std.testing.expect(deriveRelationLaw(&env, env.indexOf("seen").?) == null);
    }
    // RECURSION. Admitting it would make `evalAnswer` non-terminating, so the
    // cycle marker refusing is what makes termination structural.
    {
        var fx = try parse(
            \\down: i64 = (n: i64)
            \\    down(n - 1)
            \\
            \\main: i64 = ()
            \\    down(3)
        );
        defer fx.deinit();
        var env = Env.scan(&fx.mod, .{});
        try std.testing.expect(deriveRelationLaw(&env, env.indexOf("down").?) == null);
    }
    // DIVISION. No homomorphism to Z/2^k exists, and `demand_projection.lawsOf`
    // is the one place that says so — this module does not get a second
    // opinion.
    {
        var fx = try parse(
            \\half: i64 = (n: i64)
            \\    n / 2
            \\
            \\main: i64 = ()
            \\    half(8)
        );
        defer fx.deinit();
        var env = Env.scan(&fx.mod, .{});
        try std.testing.expect(deriveRelationLaw(&env, env.indexOf("half").?) == null);
    }
    // AN EFFECT. A printed argument is a whole-value observation and no
    // projection may hide it.
    {
        var fx = try parse(
            \\shout: i64 = (n: i64)
            \\    print(n)
            \\    1
            \\
            \\main: i64 = ()
            \\    shout(3)
        );
        defer fx.deinit();
        var env = Env.scan(&fx.mod, .{});
        try std.testing.expect(deriveRelationLaw(&env, env.indexOf("shout").?) == null);
    }
}

test "quotient synth: admission takes no cost parameter — §84 by signature" {
    // The type system carries the separation. `evalAnswer` is the value the
    // quotiented machine acts on and `deriveRelationLaw` is the legality it
    // acts on; neither has an argument through which a measurement could
    // travel, so no perturbation of any cost can move the admitted set.
    const Eval = @typeInfo(@TypeOf(evalAnswer)).@"fn";
    try std.testing.expectEqual(@as(usize, 3), Eval.param_types.len);
    const Derive = @typeInfo(@TypeOf(deriveRelationLaw)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), Derive.param_types.len);
    inline for (Derive.param_types) |p| {
        try std.testing.expect(p.? != f32 and p.? != f64);
    }
    inline for (Eval.param_types) |p| {
        try std.testing.expect(p.? != f32 and p.? != f64);
    }
}

test "quotient synth: R5 IS ENFORCED AT THE PUBLIC DOOR, not only behind a call" {
    // THE BUG THIS PINS. `inducedInputProjection` writes `[max_params]Projection`
    // indexed by parameter number, and R5 lived only in the private
    // `Env.resolve` — so every path arriving through a CALL was bounded and
    // this entry point, reachable with a bare relation index, was not. A
    // relation with more than `max_params` parameters wrote past the end of a
    // stack array. MEASURED on the corpus: 15 module-scope relations qualify.
    //
    // Nine parameters against a bound of eight. Under `-Doptimize=Debug` the
    // unguarded version trips Zig's bounds check on this call; under
    // ReleaseFast it silently corrupted the frame, which is why this is a test
    // and not a comment.
    var fx = try parse(
        \\wide: i64 = (a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, k: i64)
        \\    a + b + c + d + e + f + g + h + k
        \\
        \\main: i64 = ()
        \\    wide(1, 2, 3, 4, 5, 6, 7, 8, 9)
    );
    defer fx.deinit();
    var env = Env.scan(&fx.mod, .{});
    const rel = env.indexOf("wide").?;
    try std.testing.expect(env.rels[rel].decl.func.params.len > max_params);
    try std.testing.expect(inducedInputProjection(&env, rel, .{ .low_bits = 8 }) == null);
    try std.testing.expect(inducedInputProjection(&env, rel, .whole) == null);
    try std.testing.expect(evalAnswer(&env, rel, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }) == null);
    try std.testing.expect(env.census.refusalCount(.arity) > 0);

    // AND AN INDEX THAT NAMES NO RELATION. Every one of these is `pub` and
    // takes a `usize`; a caller that has one wrong reads uninitialised table
    // memory, so the bound is checked rather than assumed.
    try std.testing.expect(inducedInputProjection(&env, env.len, .whole) == null);
    try std.testing.expect(evalAnswer(&env, env.len, &.{}) == null);
    try std.testing.expect(deriveRelationLaw(&env, env.len) == null);
}
