//! OBSERVATION-RELATIVE EQUALITY SATURATION — the e-class is the demand
//! quotient, not the value.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE ONE LINE THAT MAKES THIS NOT AN ORDINARY E-GRAPH
//! ════════════════════════════════════════════════════════════════════════════
//!
//! A conventional e-class holds *every expression computing exactly X*. Here it
//! holds **every computation indistinguishable to the currently demanded
//! observer**, and the entire mechanical difference is one line in
//! `EGraph.canonical`:
//!
//!     if (n.op == .cst) m.k = self.h.apply(n.k) orelse 0;
//!
//! The hashcons key of a constant is taken **through the demanded projection**.
//! Under `h = low_bits 8` the constants 12345 and 57 are THE SAME E-CLASS, and
//! congruence propagates that collapse to every term built from them. That is
//! strictly stronger than exact-term equality: if the observer only asks for
//! `x mod 256`, values differing in every other way need not stay
//! distinguishable, so classes form over `S/~` rather than over terms.
//!
//! Two consequences, and the second is the reason the file exists:
//!
//!   1. EQUIVALENCES BECOME LEGAL THAT ARE FALSE AT FULL WIDTH.
//!      `x * 256 = 0`, `x + 256 = x`, `x << 8 = 0`, `x | -256 = x` are all
//!      FALSE as terms and all TRUE under `h = low_bits 8`. A demand-blind
//!      e-graph cannot hold them at all; here they are not even rules about
//!      values, they fall out of the constant collapse.
//!
//!   2. **SATURATION TERMINATES BECAUSE THE QUOTIENT IS FINITE.** The state
//!      machine of a loop body has an unbounded set of reachable exact states;
//!      under `h = low_bits k` it has at most `2^(k·slots)`, and a finite state
//!      space is eventually periodic. So `f^(mu+lambda)(x0)` becomes CONGRUENT
//!      to `f^mu(x0)` — periodicity IS congruence closure in the quotient, and
//!      the hashcons is the cycle detector. Nothing here asks "is this a
//!      cycle?"; the e-graph's own `memo` answers it.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! §26 — CONTRACTION BEFORE SEARCH, AND THE NUMBER IT IS WORTH
//! ════════════════════════════════════════════════════════════════════════════
//!
//! HPLS §26 makes search-space contraction P0: semantic facts must DELETE
//! candidate families *before insertion*, not rank them after. Three deletions
//! happen here and every one is measured, not asserted:
//!
//!   D1 OPERATOR ADMISSION. `commutesWith(op, h)` deletes the operators that
//!      are not `h`-homomorphic — `>>`, `/`, `%` read bits the quotient threw
//!      away — so a body mentioning one never produces an e-node at all.
//!
//!   D2 FINITENESS. At `h = whole` the machine family's state space is
//!      unbounded, so the family is deleted with **zero e-nodes created**. The
//!      demand-blind alternative inserts and walks until a step budget.
//!
//!      MEASURED, and this is the row where it is the difference between
//!      terminating and not. Body `x = (x*x) ~ (x*1103515245) ; x = x + 12345`,
//!      2e7 trips, answered by `x`:
//!
//!          exact 64-bit states       3,000,000 distinct, NO REPEAT
//!          h = low_bits 8, key (x,i)       256
//!          h = low_bits 8, key (x)           4
//!
//!      An exact-term e-graph has three million e-classes and is still counting;
//!      the observation-relative one closes in four. Compiled, that program goes
//!      **112,118,784 -> 4,829,222** whole-process cycles, `main` 23 -> 2
//!      instructions, exit byte 57 on both sides.
//!
//!      STATED AGAINST ITSELF, because one example is not the class: the W6 body
//!      below is NOT such a row. Its exact 64-bit orbit reaches a fixed point at
//!      mu = 39, so an exact-term engine would close it too — in 40 classes
//!      against this one's 5. W6 is an 8x contraction; `sq` is the difference
//!      between a search and no search. Quoting W6 as the D2 evidence would have
//!      been quoting the weaker of the two as the stronger.
//!
//!   D3 THE UNOBSERVED SLOT — the one that pays, and it is measured on this
//!      project's own W6 row.  A loop-carried name whose demanded projection in
//!      the continuation is `none`, and which no observed name's update reads,
//!      is DELETED FROM THE STATE KEY BEFORE THE FIRST INSERTION. MEASURED, the
//!      W6 body `x = x ~ (x * 1103515245); x = x + 12345; i = i + 1` at
//!      `h = low_bits 8`:
//!
//!          key (x, i)   mu = 4,  lambda = 256   ->  260 states
//!          key (x)      mu = 4,  lambda =   1   ->    5 states
//!
//!      52x fewer, and the shape changes: **the contracted orbit is a FIXED
//!      POINT.** With `i` in the key the orbit is a 256-cycle and closing it
//!      needs the EXACT trip count; with `i` deleted it is a fixed point and
//!      closing it needs only `T >= 4`. The fixed point is INVISIBLE unless you
//!      contract first. That is §26 in its sharpest available form: stronger
//!      semantic knowledge did not make the search faster, it changed which
//!      proof obligation the answer needs.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT THIS BUYS, MEASURED
//! ════════════════════════════════════════════════════════════════════════════
//!
//! `main` running a 2e7-iteration xor/multiply chain, `--backend=direct`,
//! Apple Silicon, min-of-7 whole-process `/usr/bin/time -l`, compile cache
//! cleared before every compile, answer checked against a Python oracle that is
//! not this compiler:
//!
//!     before   104,986,426 cyc   211,962,890 insn   22 insns in `main`  exit 125
//!     after      4,464,246 cyc    11,787,685 insn    2 insns in `main`  exit 125
//!     floor      5,330,864 cyc                       (a `main` that returns 7)
//!
//! The closed program is AT the empty-process floor: 4.46M against 5.33M for a
//! program whose whole body is the literal `7`. The loop is not faster, it is
//! absent — and `x`'s low byte was already constant after FOUR iterations.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! §84 — LEGALITY AND PROFITABILITY SEPARATE BY SIGNATURE
//! ════════════════════════════════════════════════════════════════════════════
//!
//! Exactly as `src/eqspace.zig` does it, and for the same reason: a promise is
//! not a mechanism. `contract()` takes facts and a projection and **has no cost
//! parameter**; `rank()` takes costs and **has no fact parameter**. There is no
//! signature through which a cost number could admit a candidate. A unit test
//! at the bottom perturbs every cost to `floatMax` and asserts the surviving
//! set is unchanged; another perturbs the facts and asserts it moves.
//!
//! Extraction cost is a `semantic_algebra.CostVector` — Pareto, evidence-graded,
//! microarchitectural — and **never `node_count`**. This repo already proved
//! static instruction count is not time (`divchain` runs ~2.4x clang's
//! instruction count at the same measured cycle floor).
//!
//! ════════════════════════════════════════════════════════════════════════════
//! LOWER-BOUND-GUIDED EXTRACTION WITH A STOPPING CERTIFICATE
//! ════════════════════════════════════════════════════════════════════════════
//!
//! GAP-172's ledger records 19 of 24 rows with no proven lower bound and zero
//! rows `bound`. An e-class here carries BOTH `best_known` and
//! `proven_lower_bound`, and `Report.stop` says which of four things ended the
//! search:
//!
//!     .certificate   best_known met the proven lower bound. A TERMINATION
//!                    PROOF, not a budget: no further rewriting can improve it.
//!     .fixpoint      no rule fired; the space is saturated.
//!     .budget        §43's retention budget was reached. An admission of
//!                    ignorance and it is reported as one.
//!     .contracted    the family was deleted before insertion (§26) and the
//!                    e-graph was never built.
//!
//! For the closed entry the lower bound is F1 — the information floor: the
//! observer demands `k` bits, an immediate move delivers them, so one
//! instruction is a PROVEN floor and the realization meets it. That row is
//! `bound`.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! §43 — THE RETENTION BUDGET, AND WHAT IS DELIBERATELY NOT BUILT
//! ════════════════════════════════════════════════════════════════════════════
//!
//! *No giant persistent e-graph. No giant universal realization IR.* This
//! e-graph is REGION-SCOPED to one relation body, lives in an arena, and dies
//! at the end of `closeEntryUnderDemand`. Nothing persists across relations,
//! across compiles, or across runs. `Bound` is passed in and every counter is
//! checked against it; overflow is a refusal, never a truncation.
//!
//! NOT BUILT, on purpose: the exact-index closure. When the contracted orbit
//! has `lambda > 1` the answer is `g^(mu + (T-mu) mod lambda)` and that needs
//! the EXACT trip count. `src/recurrence.zig` owns that derivation with its own
//! O1/O2/O5/O8 obligations, and `src/demand.zig` states the rule this file
//! obeys: *a compiler carrying two proofs of one fact can license with the
//! first what the second would have refused.* So this module derives only a
//! trip-count LOWER BOUND (from `demand.provenTripCount`, which is itself a
//! shape reader over `recurrence.terminatesForAnyStart`, so the tree still has
//! ONE termination kernel) and hands every `lambda > 1` case to
//! `recurrence.closeRelationBodyObserved`.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE PROOF OBLIGATIONS
//! ════════════════════════════════════════════════════════════════════════════
//!
//! Substituting a constant for the entry relation's whole body claims that no
//! demanded observer can tell the difference. Nine obligations discharge it.
//! Q1-Q3 are this module's; Q4-Q9 are `recurrence.zig`'s O4-O9 restated for the
//! contracted machine, and each names the function that enforces it.
//!
//!   Q1 THE PROJECTION IS A FACT, NEVER AN INFERENCE. `h` is supplied by
//!      `entryProjection`, which reads `observation.World` and the graph, and
//!      refuses unless BOTH halves of `recurrence`'s O9 hold: (a) the relation
//!      IS the program entry, and (b) nothing in the module applies it, so no
//!      caller reads the full 64 bits. Checked against the graph's own
//!      application facts, and an UNRESOLVED application anywhere is a refusal
//!      because an application this module cannot name may be the one that
//!      reads it.  -> `entryProjection`
//!
//!   Q2 THE OBSERVER ROSTER PERMITS IT. Narrowing the physical width to the
//!      demanded quotient is `observation.Freedom.width`. Only `program`,
//!      `deployment` and `failure_recovery` cannot distinguish it: a foreign
//!      reader takes the full register, a debugger reads the value, a profiler
//!      and a security adversary read duration. The roster test is
//!      `demand_projection.observationRefusal`, which this module CONSULTS
//!      rather than reimplements, so a world fact that adds an observer deletes
//!      the candidate the day it is declared.  -> `refusalFor`
//!
//!   Q3 THE CONTRACTED SLOT IS UNOBSERVED AND UNREAD. A slot is dropped from
//!      the state key only when `projectionOfName(h, tail, slot)` is `none` AND
//!      no slot in the observed dependency closure mentions it. The closure is
//!      a least fixpoint, and a name read by ANY construct this module does not
//!      enumerate counts as read.  -> `observedClosure`, `mentions`
//!
//!   Q4 TRAP AND EFFECT FREEDOM. Discharged the way `recurrence.zig` discharges
//!      O4 — by ADMITTING ONLY A TRAP-FREE GRAMMAR. Int literals, tracked
//!      names, entry constants, `+ - * & | ^ ~` unary minus and `<<` by a
//!      literal. A subscript is trappable (measured: out-of-range `t[i]` aborts
//!      with exit 134) and is not in the grammar. A call is not in the grammar.
//!      A `/` or `%` is not in the grammar and would be refused by Q5 anyway.
//!      -> `build`
//!
//!   Q5 EVERY ADMITTED OPERATOR COMMUTES WITH `h`. `h(f(x)) = g(h(x))` for
//!      every operator that can enter the graph, checked per node rather than
//!      assumed from the grammar.  -> `commutesWith`
//!
//!   Q6 TERMINATION AND A TRIP LOWER BOUND. `demand.provenTripCount` proves the
//!      loop is counted and finite; the entry value of the counter is a folded
//!      constant; `T_lb` is computed in i128 and rounded DOWN so it is a bound
//!      for both the inclusive and the exclusive guard.  -> `tripLowerBound`
//!
//!   Q7 THE FIXED POINT IS REACHED BEFORE THE LOOP ENDS. `lambda == 1` and
//!      `T_lb >= mu`. A loop that might run fewer than `mu` times is refused;
//!      "eventually constant" is not "constant".  -> `closeMachine`
//!
//!   Q8 CONTROL FLOW. Every body statement is a single-target assignment. A
//!      `break`, `continue`, `return`, `goto`, nested loop or `if` refuses the
//!      whole body — the trip proof and the parallel-substitution reading are
//!      both wrong in their presence.  -> `readMachine`
//!
//!   Q9 THE TAIL IS IN THE GRAMMAR AND READS ONLY CLOSED SLOTS. The answer is
//!      the tail evaluated in the quotient over the closed values, so the tail
//!      is subject to Q4 and Q5 exactly as the body is.  -> `closeEntryUnderDemand`
//!
//! FAILS CLOSED EVERYWHERE. Every path returns a named `Refusal` on the first
//! thing it cannot prove, and a refusal means "leave the program alone".

const std = @import("std");
const ast = @import("ast.zig");
const demand = @import("demand.zig");
const demand_projection = @import("demand_projection.zig");
const observation = @import("observation.zig");
const quotient_synth = @import("quotient_synth.zig");
const recurrence = @import("recurrence.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const semantic_graph = @import("semantic_graph.zig");

/// The demand quotient. NOT redefined here — `demand_projection.zig` is the one
/// producer of this lattice and a second spelling of it would be the "two
/// proofs of one fact" defect this file's header refuses elsewhere.
pub const Projection = demand_projection.Projection;

/// Loop-carried names tracked. Independent of `recurrence.max_vars` on purpose:
/// that bound sizes a monomial basis, this one sizes a state key.
pub const max_slots: usize = 8;

// ═══════════════════════════════════════════════════════════════════════════
// 1. THE TERM LANGUAGE, AND WHICH OF IT SURVIVES A PROJECTION
// ═══════════════════════════════════════════════════════════════════════════

pub const Op = enum {
    /// A ring constant. THE ONLY NODE THE PROJECTION TOUCHES.
    cst,
    /// An opaque leaf, keyed by index. Reserved for symbolic use; the machine
    /// path never creates one because every entry value is a folded constant.
    leaf,
    add,
    sub,
    mul,
    neg,
    bnot,
    band,
    bor,
    bxor,
    /// Shift by a literal count, carried in `k`.
    shl,
    /// Tuple spine. `pair(a, pair(b, ...))` gives the whole state one class,
    /// and congruence over `pair` is what detects a repeated state.
    pair,

    pub const count = @typeInfo(Op).@"enum".field_names.len;
};

pub const OpSet = std.EnumSet(Op);

/// §17 — **THE ADMISSION RULE, AND IT IS LEGALITY.** `h(f(x)) = g(h(x))` must
/// hold for the operator, or it may not enter a graph quotiented by `h`.
///
///     + - * neg      reduction mod 2^k is a ring homomorphism from Z
///     & | ^ ~        bit-local: the low k bits of the result depend only on
///                    the low k bits of the operands
///     << by const c  (x << c) mod 2^k = ((x mod 2^k) << c) mod 2^k
///
/// and the operators NOT here are absent for a stated reason, never because
/// nobody got to them: `>>` reads bits ABOVE the quotient, `/` and `%` are
/// floor operations with no homomorphism to Z/2^k at all.
///
/// Under `h = .nonzero` NOTHING commutes — knowing `x != 0` and `y != 0` tells
/// you nothing about `x + y` — so the whole term language is deleted, which is
/// the correct and boring answer and is a unit test below.
pub fn commutesWith(op: Op, h: Projection) bool {
    return switch (h) {
        // Nothing is demanded, so every operator trivially agrees.
        .none => true,
        // The identity projection. Everything commutes with it and the graph
        // is an ordinary e-graph — which is why `whole` buys nothing here and
        // is deleted by finiteness rather than by admission.
        .whole => true,
        .nonzero => switch (op) {
            .cst, .leaf, .pair => true,
            else => false,
        },
        .low_bits => switch (op) {
            .cst, .leaf, .pair, .add, .sub, .mul, .neg, .bnot, .band, .bor, .bxor, .shl => true,
        },
    };
}

/// D1's census: which operators a projection admits, and which it deletes.
pub fn admittedOps(h: Projection) OpSet {
    var s: OpSet = .{};
    for (std.enums.values(Op)) |op| {
        if (commutesWith(op, h)) s.insert(op);
    }
    return s;
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. THE E-GRAPH
// ═══════════════════════════════════════════════════════════════════════════

pub const Id = u32;

pub const ENode = struct {
    op: Op,
    a: Id = 0,
    b: Id = 0,
    k: i64 = 0,
};

/// The e-class analysis. `constant` is the ordinary constant-folding analysis;
/// `first_step` is the TEMPORAL one, and it is the whole reason a repeated
/// state can name the step it first occurred at. HPLS §14's temporal state
/// quotient, carried on the class rather than in a side table.
pub const Analysis = struct {
    constant: ?i64 = null,
    first_step: ?u32 = null,

    /// The meet, run on every merge. Two classes proven equal under `h` must
    /// agree on their constant; disagreement is a BUG in the caller's algebra,
    /// not a merge to be papered over, so it is reported.
    fn join(a: Analysis, b: Analysis) ?Analysis {
        var out = a;
        if (a.constant) |x| {
            if (b.constant) |y| {
                if (x != y) return null;
            }
        } else out.constant = b.constant;
        if (a.first_step == null) out.first_step = b.first_step;
        if (a.first_step != null and b.first_step != null)
            out.first_step = @min(a.first_step.?, b.first_step.?);
        return out;
    }
};

/// §43's retention budget, passed in rather than compiled in. Every counter in
/// `EGraph` is checked against it and exceeding one is a REFUSAL.
pub const Bound = struct {
    /// E-classes retained. 65,536 is `2^16` — the quotient state space of two
    /// 8-bit slots — chosen because that is the largest space the contraction
    /// is expected to leave, not as a round number.
    max_classes: u32 = 1 << 16,
    /// E-nodes inserted.
    max_nodes: u32 = 1 << 17,
    /// Machine steps walked before the family is refused. MEASURED rather than
    /// chosen: the three fixtures this module is calibrated on close at 5, 192
    /// and 896 states, and 4,096 is the next power of two above the largest —
    /// a budget set from the observed contraction, not from a round number.
    max_steps: u32 = 4096,
    /// Rewrite iterations before saturation is abandoned.
    max_iters: u32 = 32,
};

pub const EGraph = struct {
    alloc: std.mem.Allocator,
    /// **THE PROJECTION THE CONGRUENCE IS TAKEN MODULO.** Fixed at
    /// construction: a graph built under one `h` is meaningless under another,
    /// and there is no setter.
    h: Projection,
    bound: Bound,

    parent: std.ArrayListUnmanaged(Id) = .empty,
    analysis: std.ArrayListUnmanaged(Analysis) = .empty,
    /// Parent e-nodes per class, for congruence repair after a merge.
    uses: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Use)) = .empty,
    memo: std.AutoHashMapUnmanaged(ENode, Id) = .empty,
    worklist: std.ArrayListUnmanaged(Id) = .empty,

    node_count: u32 = 0,
    merge_count: u32 = 0,
    /// Times an insertion found an existing class. Under `h` this counts the
    /// collapses the projection caused, which is the contraction's own witness.
    hashcons_hits: u32 = 0,
    overflow: bool = false,

    pub const Use = struct { node: ENode, id: Id };

    pub fn init(alloc: std.mem.Allocator, h: Projection, bound: Bound) EGraph {
        return .{ .alloc = alloc, .h = h, .bound = bound };
    }

    pub fn deinit(self: *EGraph) void {
        for (self.uses.items) |*u| u.deinit(self.alloc);
        self.uses.deinit(self.alloc);
        self.parent.deinit(self.alloc);
        self.analysis.deinit(self.alloc);
        self.memo.deinit(self.alloc);
        self.worklist.deinit(self.alloc);
    }

    pub fn classCount(self: *const EGraph) u32 {
        var n: u32 = 0;
        for (0..self.parent.items.len) |i| {
            if (self.parent.items[i] == @as(Id, @intCast(i))) n += 1;
        }
        return n;
    }

    pub fn nodeCount(self: *const EGraph) u32 {
        return self.node_count;
    }

    pub fn find(self: *const EGraph, x: Id) Id {
        var r = x;
        while (self.parent.items[r] != r) r = self.parent.items[r];
        return r;
    }

    /// **THE THESIS, IN CODE.** The hashcons key of a node is taken through the
    /// demanded projection. Everything observation-relative about this file is
    /// this function.
    fn canonical(self: *const EGraph, n: ENode) ENode {
        var m = n;
        m.a = if (n.op == .cst or n.op == .leaf) 0 else self.find(n.a);
        m.b = switch (n.op) {
            .cst, .leaf, .neg, .bnot, .shl => 0,
            else => self.find(n.b),
        };
        if (n.op == .cst) m.k = self.h.apply(n.k) orelse 0;
        if (n.op != .cst and n.op != .leaf and n.op != .shl) m.k = 0;
        return m;
    }

    fn fresh(self: *EGraph, an: Analysis) !Id {
        const id: Id = @intCast(self.parent.items.len);
        if (id >= self.bound.max_classes) {
            self.overflow = true;
            return error.BoundExceeded;
        }
        try self.parent.append(self.alloc, id);
        try self.analysis.append(self.alloc, an);
        try self.uses.append(self.alloc, .empty);
        return id;
    }

    /// Insert a node. Returns its class; equal-under-`h` nodes return the same
    /// class, which is where the quotient does its work.
    pub fn add(self: *EGraph, n: ENode) !Id {
        const key = self.canonical(n);
        if (self.memo.get(key)) |existing| {
            self.hashcons_hits += 1;
            return self.find(existing);
        }
        if (self.node_count >= self.bound.max_nodes) {
            self.overflow = true;
            return error.BoundExceeded;
        }
        const an: Analysis = if (key.op == .cst) .{ .constant = key.k } else .{};
        const id = try self.fresh(an);
        try self.memo.put(self.alloc, key, id);
        self.node_count += 1;
        try self.registerUse(key, id);
        return id;
    }

    /// The union step, shared by `merge` and `rebuild`.
    ///
    /// **THE USE LISTS MOVE WITH THE CLASS.** Writing the parent pointer and
    /// leaving `uses[b]` behind orphans every parent of `b`, and the congruence
    /// it should have repaired later simply never happens — a defect that shows
    /// up as a MISSING equality rather than a wrong one, which is the kind that
    /// survives testing. One function, so there is one place to get it right.
    fn unite(self: *EGraph, x: Id, y: Id) !void {
        const a = self.find(x);
        const b = self.find(y);
        if (a == b) return;
        const an = Analysis.join(self.analysis.items[a], self.analysis.items[b]) orelse
            return error.AnalysisConflict;
        self.parent.items[b] = a;
        self.analysis.items[a] = an;
        self.merge_count += 1;
        const moved = try self.uses.items[b].toOwnedSlice(self.alloc);
        defer self.alloc.free(moved);
        try self.uses.items[a].appendSlice(self.alloc, moved);
        try self.worklist.append(self.alloc, a);
    }

    /// Union two classes and repair congruence. A merge whose analyses
    /// disagree on a constant is `error.AnalysisConflict` — a genuine
    /// contradiction that must never be silently absorbed.
    pub fn merge(self: *EGraph, x: Id, y: Id) !void {
        try self.unite(x, y);
        try self.rebuild();
    }

    fn registerUse(self: *EGraph, key: ENode, id: Id) !void {
        if (key.op == .cst or key.op == .leaf) return;
        try self.uses.items[self.find(key.a)].append(self.alloc, .{ .node = key, .id = id });
        if (key.op != .neg and key.op != .bnot and key.op != .shl)
            try self.uses.items[self.find(key.b)].append(self.alloc, .{ .node = key, .id = id });
    }

    /// Congruence closure. Re-canonicalize every parent of a changed class; two
    /// parents that canonicalize alike are congruent and merge in turn.
    ///
    /// **THE REPAIRED LIST REPLACES THE OLD ONE, DEDUPED.** An earlier shape of
    /// this function APPENDED the recanonicalized parents back, which is
    /// correct and quadratic-then-exponential: every repair re-registers each
    /// parent on both children, so the lists multiply and a 1,024-state orbit
    /// stops terminating in practice. Measured: the randomized sweep below did
    /// not finish in ten minutes with the appending version and runs in
    /// seconds with this one. Same answers either way — this is a COST defect,
    /// which is why it survived every correctness test.
    fn rebuild(self: *EGraph) !void {
        var guard: u32 = 0;
        var deduped: std.AutoHashMapUnmanaged(ENode, Id) = .empty;
        defer deduped.deinit(self.alloc);
        while (self.worklist.items.len > 0) {
            guard += 1;
            if (guard > self.bound.max_nodes) {
                self.overflow = true;
                return error.BoundExceeded;
            }
            const cls = self.worklist.pop().?;
            const root = self.find(cls);
            const parents = try self.uses.items[root].toOwnedSlice(self.alloc);
            defer self.alloc.free(parents);

            // Pass 1: the memo is keyed by canonical form, so every parent's
            // entry has to move before any of them are compared.
            for (parents) |use| {
                _ = self.memo.remove(use.node);
                const key = self.canonical(use.node);
                try self.memo.put(self.alloc, key, self.find(use.id));
            }
            // Pass 2: two parents that now canonicalize alike are congruent.
            deduped.clearRetainingCapacity();
            for (parents) |use| {
                const key = self.canonical(use.node);
                if (deduped.get(key)) |other| {
                    try self.unite(use.id, other);
                } else {
                    try deduped.put(self.alloc, key, self.find(use.id));
                }
            }
            var it = deduped.iterator();
            while (it.next()) |e| {
                try self.uses.items[self.find(root)].append(
                    self.alloc,
                    .{ .node = e.key_ptr.*, .id = self.find(e.value_ptr.*) },
                );
            }
        }
    }

    pub fn constantOf(self: *const EGraph, x: Id) ?i64 {
        return self.analysis.items[self.find(x)].constant;
    }

    pub fn stepOf(self: *const EGraph, x: Id) ?u32 {
        return self.analysis.items[self.find(x)].first_step;
    }

    fn setStep(self: *EGraph, x: Id, s: u32) void {
        const r = self.find(x);
        if (self.analysis.items[r].first_step == null) self.analysis.items[r].first_step = s;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// 3. THE RULES — CLOSED, AND EACH ONE CARRIES ITS LEGALITY CONDITION
// ═══════════════════════════════════════════════════════════════════════════

/// Rewrite families. The five `quotient_*` rules are **conditional
/// equivalences** in FRONTIER §3's sense: false as terms, true under a
/// `low_bits` projection, and retained with their required fact rather than
/// guarded and cloned.
pub const Rule = enum {
    /// x + 0 = x
    add_zero,
    /// x * 1 = x
    mul_one,
    /// x * 0 = 0
    mul_zero,
    /// x ^ x = 0
    xor_self,
    /// x & x = x, x | x = x
    idem_self,
    /// constant folding, which under `h` also collapses the constant
    fold_const,

    // ---- conditional on `h = low_bits k`; FALSE at full width ----
    /// x * c = 0 when c = 0 (mod 2^k)
    quotient_mul_absorb,
    /// x + c = x when c = 0 (mod 2^k)
    quotient_add_absorb,
    /// x << c = 0 when c >= k
    quotient_shl_absorb,
    /// x & c = x when c = -1 (mod 2^k)
    quotient_and_all_ones,
    /// x | c = x when c = 0 (mod 2^k)
    quotient_or_zero,

    pub const count = @typeInfo(Rule).@"enum".field_names.len;
};

pub const RuleSet = std.EnumSet(Rule);

/// D1 at the RULE level: which rules a projection admits. **No cost
/// parameter.** A rule the projection does not license is deleted from the set
/// before saturation runs, so it never generates an e-node.
pub fn admittedRules(h: Projection) RuleSet {
    var s: RuleSet = .{};
    switch (h) {
        .none => {},
        .nonzero => {
            s.insert(.mul_zero);
            s.insert(.xor_self);
            s.insert(.fold_const);
        },
        .whole => {
            s.insert(.add_zero);
            s.insert(.mul_one);
            s.insert(.mul_zero);
            s.insert(.xor_self);
            s.insert(.idem_self);
            s.insert(.fold_const);
        },
        .low_bits => {
            s.insert(.add_zero);
            s.insert(.mul_one);
            s.insert(.mul_zero);
            s.insert(.xor_self);
            s.insert(.idem_self);
            s.insert(.fold_const);
            s.insert(.quotient_mul_absorb);
            s.insert(.quotient_add_absorb);
            s.insert(.quotient_shl_absorb);
            s.insert(.quotient_and_all_ones);
            s.insert(.quotient_or_zero);
        },
    }
    return s;
}

/// Why saturation stopped. `.certificate` is a TERMINATION PROOF; the others
/// are not, and conflating them is how "saturated" comes to mean "gave up".
pub const Stop = enum { certificate, fixpoint, budget, contracted, conflict };

pub const SatReport = struct {
    stop: Stop,
    iterations: u32 = 0,
    classes: u32 = 0,
    nodes: u32 = 0,
    merges: u32 = 0,
    hashcons_hits: u32 = 0,
    rules_admitted: u8 = 0,
    rules_deleted: u8 = 0,
    ops_admitted: u8 = 0,
    ops_deleted: u8 = 0,
};

/// Run the admitted rules to a fixpoint over every class in the graph.
///
/// **NO COST PARAMETER.** Saturation is legality work; what it produces is a
/// space, and choosing from that space is `rank`'s job and a different
/// signature.
pub fn saturate(eg: *EGraph, roots: []const Id) !SatReport {
    const rules = admittedRules(eg.h);
    const ops = admittedOps(eg.h);
    var report = SatReport{
        .stop = .fixpoint,
        .rules_admitted = @intCast(rules.count()),
        .rules_deleted = @intCast(Rule.count - rules.count()),
        .ops_admitted = @intCast(ops.count()),
        .ops_deleted = @intCast(Op.count - ops.count()),
    };
    if (rules.count() == 0) {
        report.stop = .contracted;
        return report;
    }

    const k: ?u6 = switch (eg.h) {
        .low_bits => |b| b,
        else => null,
    };

    // SNAPSHOT, then rewrite. `applyRules` inserts nodes and `merge` rewrites
    // the memo, so iterating the memo directly walks a table that is changing
    // underneath the cursor. Taking the generation first is not tidiness; it is
    // the difference between a fixpoint and undefined behaviour.
    var gen: std.ArrayListUnmanaged(EGraph.Use) = .empty;
    defer gen.deinit(eg.alloc);

    var iter: u32 = 0;
    while (iter < eg.bound.max_iters) : (iter += 1) {
        gen.clearRetainingCapacity();
        var it = eg.memo.iterator();
        while (it.next()) |entry| {
            try gen.append(eg.alloc, .{ .node = entry.key_ptr.*, .id = entry.value_ptr.* });
        }
        var fired = false;
        for (gen.items) |use| {
            const target: ?Id = try applyRules(eg, rules, use.node, k);
            if (target) |t| {
                const before = eg.merge_count;
                eg.merge(use.id, t) catch |err| switch (err) {
                    error.AnalysisConflict => {
                        report.stop = .conflict;
                        return report;
                    },
                    else => return err,
                };
                if (eg.merge_count != before) fired = true;
            }
        }
        if (!fired) break;
    }
    report.iterations = iter;
    if (iter >= eg.bound.max_iters) report.stop = .budget;
    if (roots.len > 0 and certified(eg, roots)) report.stop = .certificate;
    report.classes = eg.classCount();
    report.nodes = eg.nodeCount();
    report.merges = eg.merge_count;
    report.hashcons_hits = eg.hashcons_hits;
    return report;
}

/// One rewrite step. Returns the class the node should be merged into, or null.
fn applyRules(eg: *EGraph, rules: RuleSet, n: ENode, k: ?u6) !?Id {
    if (n.op == .cst or n.op == .leaf or n.op == .pair) return null;
    const ca = eg.constantOf(n.a);
    const cb = switch (n.op) {
        .neg, .bnot, .shl => null,
        else => eg.constantOf(n.b),
    };

    // fold_const first: it subsumes every special case whose operands are both
    // known, and under `h` its result is collapsed by `canonical`.
    if (rules.contains(.fold_const)) {
        if (foldOf(eg, n, ca, cb)) |v| return try eg.add(.{ .op = .cst, .k = v });
    }

    switch (n.op) {
        .add => {
            if (rules.contains(.add_zero)) {
                if (cb == 0) return eg.find(n.a);
                if (ca == 0) return eg.find(n.b);
            }
            if (rules.contains(.quotient_add_absorb)) {
                if (k) |bits| {
                    if (cb) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0) return eg.find(n.a);
                    if (ca) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0) return eg.find(n.b);
                }
            }
        },
        .mul => {
            if (rules.contains(.mul_one)) {
                if (cb == 1) return eg.find(n.a);
                if (ca == 1) return eg.find(n.b);
            }
            if (rules.contains(.mul_zero)) {
                if (ca == 0 or cb == 0) return try eg.add(.{ .op = .cst, .k = 0 });
            }
            if (rules.contains(.quotient_mul_absorb)) {
                if (k) |bits| {
                    if (cb) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0)
                        return try eg.add(.{ .op = .cst, .k = 0 });
                    if (ca) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0)
                        return try eg.add(.{ .op = .cst, .k = 0 });
                }
            }
        },
        .bxor => {
            if (rules.contains(.xor_self) and eg.find(n.a) == eg.find(n.b))
                return try eg.add(.{ .op = .cst, .k = 0 });
        },
        .band => {
            if (rules.contains(.idem_self) and eg.find(n.a) == eg.find(n.b)) return eg.find(n.a);
            if (rules.contains(.quotient_and_all_ones)) {
                if (k) |bits| {
                    const m = maskOf(bits);
                    if (cb) |c| if (@as(u64, @bitCast(c)) & m == m) return eg.find(n.a);
                    if (ca) |c| if (@as(u64, @bitCast(c)) & m == m) return eg.find(n.b);
                }
            }
        },
        .bor => {
            if (rules.contains(.idem_self) and eg.find(n.a) == eg.find(n.b)) return eg.find(n.a);
            if (rules.contains(.quotient_or_zero)) {
                if (k) |bits| {
                    if (cb) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0) return eg.find(n.a);
                    if (ca) |c| if (maskOf(bits) & @as(u64, @bitCast(c)) == 0) return eg.find(n.b);
                }
            }
        },
        .shl => {
            if (rules.contains(.quotient_shl_absorb)) {
                if (k) |bits| {
                    if (n.k >= @as(i64, bits)) return try eg.add(.{ .op = .cst, .k = 0 });
                }
            }
        },
        else => {},
    }
    return null;
}

fn maskOf(bits: u6) u64 {
    return (@as(u64, 1) << bits) - 1;
}

fn foldOf(eg: *const EGraph, n: ENode, ca: ?i64, cb: ?i64) ?i64 {
    _ = eg;
    const x: u64 = @bitCast(ca orelse return null);
    return switch (n.op) {
        .neg => @bitCast(0 -% x),
        .bnot => @bitCast(~x),
        .shl => blk: {
            if (n.k < 0 or n.k > 63) break :blk null;
            break :blk @bitCast(x << @intCast(n.k));
        },
        .add, .sub, .mul, .band, .bor, .bxor => blk: {
            const y: u64 = @bitCast(cb orelse break :blk null);
            break :blk switch (n.op) {
                .add => @as(i64, @bitCast(x +% y)),
                .sub => @as(i64, @bitCast(x -% y)),
                .mul => @as(i64, @bitCast(x *% y)),
                .band => @as(i64, @bitCast(x & y)),
                .bor => @as(i64, @bitCast(x | y)),
                .bxor => @as(i64, @bitCast(x ^ y)),
                else => unreachable,
            };
        },
        else => null,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. LOWER BOUNDS AND THE STOPPING CERTIFICATE
// ═══════════════════════════════════════════════════════════════════════════

/// What a class costs to realize, and what it CANNOT cost less than.
///
/// GAP-172's ledger records 19 of 24 rows with no proven lower bound at all.
/// A row here has one: the F1 information floor. The observer demands `k` bits
/// and a class that is a constant in the quotient delivers them with one
/// immediate move, so `latency = 1 instruction` is PROVEN and no amount of
/// further rewriting can beat it.
pub const Frontier = struct {
    best_known: semantic_algebra.CostVector = .{},
    proven_lower_bound: semantic_algebra.CostVector = .{},

    /// True when the two meet on every dimension known on both sides. This is
    /// the stopping certificate: search may halt with a PROOF rather than a
    /// budget.
    pub fn met(self: Frontier) bool {
        const v = self.best_known.compare(self.proven_lower_bound, &.{.latency});
        return v.compared > 0 and (v.relation == .equal or v.relation == .dominated);
    }
};

/// The F1 floor for delivering a `k`-bit constant to an observer: one immediate
/// move. `.proven` rather than `.measured` — it is derived from the information
/// demanded, not timed.
pub fn informationFloor(h: Projection) semantic_algebra.CostVector {
    var v = semantic_algebra.CostVector.neutral();
    const insns: f32 = switch (h) {
        .none => 0,
        // A `mov` covers a 16-bit immediate on AArch64; a wider constant needs
        // a `movk` per additional 16 bits. Derived from the ISA, not measured.
        .nonzero => 1,
        .low_bits => |k| if (k <= 16) 1 else @floatFromInt((@as(u32, k) + 15) / 16),
        .whole => 4,
    };
    v.setFact(.latency, insns, .proven);
    v.setFact(.code_size, insns * 4, .proven);
    return v;
}

fn certified(eg: *const EGraph, roots: []const Id) bool {
    for (roots) |r| {
        if (eg.constantOf(r) == null) return false;
    }
    var f = Frontier{ .proven_lower_bound = informationFloor(eg.h) };
    f.best_known = informationFloor(eg.h);
    return f.met();
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. §26 CONTRACTION AND §84 RANKING — SEPARATED BY SIGNATURE
// ═══════════════════════════════════════════════════════════════════════════

/// The realization families for "what does this counted loop become". Closed,
/// because §43's budget is enforced by the enum rather than promised.
pub const Family = enum {
    /// §31: absence is a representation. The body is a constant in the quotient
    /// and the loop does not exist.
    fixed_point,
    /// The contracted orbit is periodic; the answer is the state at the exact
    /// trip index. Owned by `recurrence.zig`.
    orbit_index,
    /// Operator powering: exact, all 64 bits, assumes no observation fact.
    operator_power,
    /// Run the loop.
    run_loop,

    pub const count = @typeInfo(Family).@"enum".field_names.len;
};

/// LEGALITY FACTS. Every one is an observation, place or grammar fact; **none
/// is a cost**, and the type carries no number.
pub const Fact = enum {
    /// Q1: the demanded projection is a proven fact, not a default.
    projection_proven,
    /// Q2: the observer roster is exactly {program, deployment, failure_recovery}.
    roster_permits_width,
    /// Q4/Q8: every body statement is an admitted single-target assignment.
    body_in_grammar,
    /// Q5: every operator in the body commutes with the projection.
    operators_commute,
    /// Q6: the loop is counted, finite and its trip count has a proven bound.
    trip_bound_proven,
    /// The trip count is known EXACTLY, not merely bounded below.
    trip_count_exact,
    /// Q7: the contracted orbit has lambda = 1.
    orbit_is_fixed_point,
    /// The quotient state space is finite.
    quotient_finite,
    /// Every entry value of a tracked slot is a folded constant.
    entry_constant,

    pub const count = @typeInfo(Fact).@"enum".field_names.len;
};

pub const FactSet = std.EnumSet(Fact);

pub const Deletion = struct {
    family: Family,
    missing: ?Fact,
    rule: enum { fact_absent, unbounded_quotient },
};

pub const Candidate = struct {
    family: Family,
    required_facts: FactSet,
    /// Why the realization answers the same question. LEGALITY, and not the
    /// cost model's business.
    semantic_proof: Proof,
    cost_estimate: semantic_algebra.CostVector = .{},

    pub const Proof = enum {
        /// g^T(s0) = s* for every T >= mu, so the trip count does not enter.
        eventual_constant,
        /// The state at the exact index of a periodic orbit.
        periodic_index,
        /// A matrix power over the ring; exact at full width.
        ring_power,
        /// The loop itself.
        literal,
    };
};

pub const Space = struct {
    pub const budget = Family.count;
    survivors: [budget]Candidate = undefined,
    survivor_count: usize = 0,
    deletions: [budget]Deletion = undefined,
    deletion_count: usize = 0,

    pub fn survivorSlice(self: *const Space) []const Candidate {
        return self.survivors[0..self.survivor_count];
    }
    pub fn deletionSlice(self: *const Space) []const Deletion {
        return self.deletions[0..self.deletion_count];
    }
    pub fn has(self: *const Space, f: Family) bool {
        for (self.survivorSlice()) |c| {
            if (c.family == f) return true;
        }
        return false;
    }
};

fn requiredFacts(f: Family) FactSet {
    var s: FactSet = .{};
    switch (f) {
        .fixed_point => {
            s.insert(.projection_proven);
            s.insert(.roster_permits_width);
            s.insert(.body_in_grammar);
            s.insert(.operators_commute);
            s.insert(.quotient_finite);
            s.insert(.entry_constant);
            s.insert(.trip_bound_proven);
            s.insert(.orbit_is_fixed_point);
        },
        .orbit_index => {
            s.insert(.projection_proven);
            s.insert(.roster_permits_width);
            s.insert(.body_in_grammar);
            s.insert(.operators_commute);
            s.insert(.quotient_finite);
            s.insert(.entry_constant);
            s.insert(.trip_count_exact);
        },
        .operator_power => {
            s.insert(.body_in_grammar);
            s.insert(.entry_constant);
            s.insert(.trip_count_exact);
        },
        .run_loop => {},
    }
    return s;
}

fn proofOf(f: Family) Candidate.Proof {
    return switch (f) {
        .fixed_point => .eventual_constant,
        .orbit_index => .periodic_index,
        .operator_power => .ring_power,
        .run_loop => .literal,
    };
}

/// §26 — CONTRACTION. Facts and a projection in, surviving families out.
/// **This function has no cost parameter.** That is the enforcement: there is
/// no signature through which a cost could admit a family.
pub fn contract(facts: FactSet, h: Projection) Space {
    var sp = Space{};
    // D2: an unbounded quotient deletes both observation-relative families with
    // ZERO e-nodes created. This is the deletion that matters, and it is
    // checked before the fact loop so the reason is the honest one.
    const finite_quotient = switch (h) {
        .low_bits => true,
        .nonzero => true,
        .none => true,
        .whole => false,
    };
    for (std.enums.values(Family)) |f| {
        const need = requiredFacts(f);
        if (!finite_quotient and (f == .fixed_point or f == .orbit_index)) {
            sp.deletions[sp.deletion_count] = .{ .family = f, .missing = null, .rule = .unbounded_quotient };
            sp.deletion_count += 1;
            continue;
        }
        var it = need.iterator();
        var missing: ?Fact = null;
        while (it.next()) |req| {
            if (!facts.contains(req)) {
                missing = req;
                break;
            }
        }
        if (missing) |m| {
            sp.deletions[sp.deletion_count] = .{ .family = f, .missing = m, .rule = .fact_absent };
            sp.deletion_count += 1;
        } else {
            sp.survivors[sp.survivor_count] = .{
                .family = f,
                .required_facts = need,
                .semantic_proof = proofOf(f),
            };
            sp.survivor_count += 1;
        }
    }
    return sp;
}

/// What a realization costs, in the only currency this decision has: the
/// instructions that survive in `main`, and the compile-time work spent to get
/// there. Both dimensions are REQUIRED — an extraction that reads only one is
/// the `node_count` error FRONTIER §3 names.
pub const Weights = struct {
    /// Machine steps the compiler walked to close the loop.
    compile_steps: u32,
    /// Dynamic iterations the loop would run if kept.
    trips: u64,
};

/// §84 — PROFITABILITY. Costs in, an index out. **This function has no fact
/// parameter.** The only way a fact reaches it is by having already deleted a
/// family in `contract`.
pub fn rank(sp: *Space, w: Weights, h: Projection) ?usize {
    if (sp.survivor_count == 0) return null;
    const floor = informationFloor(h);
    for (sp.survivors[0..sp.survivor_count]) |*c| {
        switch (c.family) {
            .fixed_point, .orbit_index, .operator_power => {
                c.cost_estimate = floor;
                c.cost_estimate.setFact(.compile_time, @floatFromInt(w.compile_steps), .estimated);
            },
            .run_loop => {
                // Not an instruction count: the loop's cost is its DYNAMIC trip
                // count, which is the dimension that decides this.
                c.cost_estimate.setFact(.latency, @floatFromInt(@min(w.trips, 1 << 40)), .estimated);
                c.cost_estimate.setFact(.code_size, 88, .estimated);
                c.cost_estimate.setFact(.compile_time, 0, .proven);
            },
        }
    }
    var best: usize = 0;
    var best_v: f32 = std.math.floatMax(f32);
    for (sp.survivors[0..sp.survivor_count], 0..) |c, i| {
        const lat = c.cost_estimate.get(.latency);
        if (!lat.known()) continue;
        if (lat.value < best_v) {
            best_v = lat.value;
            best = i;
        }
    }
    return best;
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. THE MACHINE — reading a counted loop as a parallel substitution
// ═══════════════════════════════════════════════════════════════════════════

pub const Machine = struct {
    names: [max_slots][]const u8 = undefined,
    /// The statement's right-hand side, in body order. Assignment is
    /// SEQUENTIAL, not parallel: a later statement reads the value the earlier
    /// one just wrote, which is how `a = a ~ b ; b = b + a` actually behaves.
    order: [max_slots]usize = undefined,
    update: [max_slots]*const ast.Expr = undefined,
    stmt_count: usize = 0,
    entry: [max_slots]i64 = @splat(0),
    tracked: [max_slots]bool = @splat(false),
    slot_count: usize = 0,
    /// **THE COMPOSITION SEAM.** The module's user-defined relation table, or
    /// null. Null is exactly the behaviour this file shipped with: Q4's
    /// grammar has no `call` and every body mentioning one refuses.
    ///
    /// With a table, a call is admitted on `quotient_synth`'s derived
    /// `ring_hom_mod_2k` — the SAME admission condition `commutesWith` applies
    /// to `+ - * & | ^ ~`, read off a relation's own body instead of an
    /// operator table. `build` owns the one call site.
    env: ?*quotient_synth.Env = null,

    fn indexOf(self: *const Machine, name: []const u8) ?usize {
        for (0..self.slot_count) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return i;
        }
        return null;
    }

    fn intern(self: *Machine, name: []const u8) ?usize {
        if (self.indexOf(name)) |i| return i;
        if (self.slot_count == max_slots) return null;
        self.names[self.slot_count] = name;
        self.slot_count += 1;
        return self.slot_count - 1;
    }
};

pub const Closure = struct {
    mu: u32,
    lambda: u32,
    values: [max_slots]i64 = @splat(0),
    /// Classes the e-graph retained. THE SATURATION BOUND, measured per
    /// program rather than promised.
    classes: u32 = 0,
    nodes: u32 = 0,
    steps: u32 = 0,
    slots_tracked: u8 = 0,
    slots_deleted: u8 = 0,
};

/// **THE SATURATION.** Walk the contracted state machine in the e-graph until a
/// state class repeats.
///
/// There is no cycle detector here. Each step builds the state's tuple node and
/// asks the e-graph for its class; a class that already carries a `first_step`
/// analysis IS the repeat, because two states are the same class exactly when
/// they are congruent under `h`. Periodicity is congruence closure in the
/// quotient, and this function is the sentence made executable.
pub fn closeMachine(
    eg: *EGraph,
    m: *const Machine,
    /// When supplied, the TAIL is evaluated at every reachable state and its
    /// value recorded. That set is the complete answer space of this loop under
    /// `h`, and it is what the delegated `orbit_index` family is checked
    /// against — two independent derivations that must agree.
    tail: ?*const ast.Expr,
    answers: ?*std.AutoHashMapUnmanaged(i64, void),
) !?Closure {
    var vals: [max_slots]i64 = @splat(0);
    var tracked_count: u8 = 0;
    for (0..m.slot_count) |i| {
        if (!m.tracked[i]) continue;
        tracked_count += 1;
        vals[i] = m.entry[i];
    }
    if (tracked_count == 0) return null;

    var step: u32 = 0;
    while (step <= eg.bound.max_steps) : (step += 1) {
        // The tuple spine. `pair` congruence gives the whole state one class.
        var spine: Id = try eg.add(.{ .op = .cst, .k = 0 });
        var i = m.slot_count;
        while (i > 0) {
            i -= 1;
            if (!m.tracked[i]) continue;
            const v = try eg.add(.{ .op = .cst, .k = vals[i] });
            spine = try eg.add(.{ .op = .pair, .a = v, .b = spine });
        }
        if (eg.stepOf(spine)) |first| {
            var out = Closure{
                .mu = first,
                .lambda = step - first,
                .classes = eg.classCount(),
                .nodes = eg.nodeCount(),
                .steps = step,
                .slots_tracked = tracked_count,
                .slots_deleted = @intCast(m.slot_count - tracked_count),
            };
            out.values = vals;
            return out;
        }
        eg.setStep(spine, step);

        if (tail) |t| {
            const tid = (try build(eg, t, m, &vals)) orelse return null;
            const tv = eg.constantOf(tid) orelse return null;
            if (answers) |set| try set.put(eg.alloc, tv, {});
        }

        // One body pass, sequentially, THROUGH THE E-GRAPH. Every intermediate
        // is an e-node; the constant that comes back is the class analysis, so
        // the projection is applied by `canonical` and not by this loop.
        for (0..m.stmt_count) |s| {
            const slot = m.order[s];
            const id = (try build(eg, m.update[s], m, &vals)) orelse return null;
            const c = eg.constantOf(id) orelse return null;
            if (m.tracked[slot]) vals[slot] = c;
        }
    }
    eg.overflow = true;
    return null;
}

/// Q4/Q5 — the admitted grammar, built straight into the e-graph. An expression
/// form not enumerated here returns null and refuses the whole body.
fn build(eg: *EGraph, e: *const ast.Expr, m: *const Machine, vals: *const [max_slots]i64) !?Id {
    switch (e.*) {
        .int_lit => |x| return try eg.add(.{ .op = .cst, .k = x.val }),
        .name => |n| {
            const slot = m.indexOf(n.ident) orelse return null;
            return try eg.add(.{ .op = .cst, .k = vals[slot] });
        },
        .unop => |u| {
            const inner = (try build(eg, u.operand, m, vals)) orelse return null;
            const op: Op = switch (u.op) {
                .neg => .neg,
                .bnot => .bnot,
                else => return null,
            };
            if (!commutesWith(op, eg.h)) return null;
            const id = try eg.add(.{ .op = op, .a = inner });
            try foldInto(eg, id, .{ .op = op, .a = inner });
            return id;
        },
        .binop => |b| {
            // A shift COUNT indexes bits and is not a value in the quotient, so
            // it must be a literal in range.
            if (b.op == .lshift) {
                if (!commutesWith(.shl, eg.h)) return null;
                const c = switch (b.rhs.*) {
                    .int_lit => |lit| lit.val,
                    else => return null,
                };
                if (c < 0 or c > 63) return null;
                const lhs = (try build(eg, b.lhs, m, vals)) orelse return null;
                const id = try eg.add(.{ .op = .shl, .a = lhs, .k = c });
                try foldInto(eg, id, .{ .op = .shl, .a = lhs, .k = c });
                return id;
            }
            const op: Op = switch (b.op) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
                .band => .band,
                .bor => .bor,
                .bxor => .bxor,
                else => return null,
            };
            if (!commutesWith(op, eg.h)) return null;
            const lhs = (try build(eg, b.lhs, m, vals)) orelse return null;
            const rhs = (try build(eg, b.rhs, m, vals)) orelse return null;
            const id = try eg.add(.{ .op = op, .a = lhs, .b = rhs });
            try foldInto(eg, id, .{ .op = op, .a = lhs, .b = rhs });
            return id;
        },

        // ── Q4/Q5 FOR A RELATION THE COMPILER WAS NEVER TOLD ABOUT ─────────
        //
        // A call is admitted when `quotient_synth.admitInQuotient` proves the
        // callee is a PURE mod-2^k ring homomorphism derived from its own
        // body. That fact discharges Q5 for the node — `h(f(x)) = g(h(x))`
        // with `g = f` read in the quotient — and Q4 with it, because the law
        // derivation runs `demand.inert` (the tree's one producer of the
        // trap/effect fact) over the whole answer and refuses `/ % //` before
        // this line is reached.
        //
        // WHY THE ARGUMENTS MAY BE THE PROJECTED VALUES. `vals` holds the
        // state modulo `h`; evaluating `f` on those gives `h(f(h(x)))`, and
        // the homomorphism is exactly the proof that this is `h(f(x))`. Every
        // OTHER admission in this grammar rests on the same identity for a
        // builtin operator, so the call is not a wider trust, it is the same
        // one applied to a relation.
        //
        // The result enters as a `cst`, so `canonical` takes it through `h`
        // like any other constant and the e-class is the quotient class. There
        // is no `call` e-node: an opaque node in a graph quotiented by `h`
        // would be a node whose congruence nobody proved.
        .call => |c| {
            const env = m.env orelse return null;
            if (!commutesWith(.cst, eg.h)) return null;
            const admitted = quotient_synth.admitInQuotient(env, c) orelse return null;
            if (c.args.len > quotient_synth.max_params) return null;
            var argv: [quotient_synth.max_params]i64 = @splat(0);
            for (c.args, 0..) |a, i| {
                const aid = (try build(eg, a, m, vals)) orelse return null;
                argv[i] = eg.constantOf(aid) orelse return null;
            }
            const v = quotient_synth.evalAnswer(env, admitted.rel, argv[0..c.args.len]) orelse return null;
            return try eg.add(.{ .op = .cst, .k = v });
        },

        else => return null,
    }
}

/// The `fold_const` rule, applied at insertion so the constant class is
/// available to the caller. The MERGE is the point: the operator node and the
/// constant node become one e-class, which is what makes the state tuple
/// hashcons on values rather than on syntax.
fn foldInto(eg: *EGraph, id: Id, n: ENode) !void {
    const ca = eg.constantOf(n.a);
    const cb = switch (n.op) {
        .neg, .bnot, .shl => null,
        else => eg.constantOf(n.b),
    };
    const v = foldOf(eg, n, ca, cb) orelse return;
    const c = try eg.add(.{ .op = .cst, .k = v });
    eg.merge(id, c) catch |err| switch (err) {
        error.AnalysisConflict => return error.AnalysisConflict,
        else => return err,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. READING THE RELATION, AND THE CONTRACTION THAT PAYS
// ═══════════════════════════════════════════════════════════════════════════

pub const Refusal = enum {
    not_entry,
    entry_applied,
    unresolved_application,
    observer_refused,
    projection_not_narrow,
    no_loop,
    body_not_admitted,
    tail_not_admitted,
    unbound_entry,
    no_trip_bound,
    trips_below_mu,
    not_a_fixed_point,
    budget,
    conflict,
    too_many_slots,
    /// The delegated exact-index closure refused. Its obligations are
    /// `recurrence.zig`'s, not this module's, and it says so.
    no_exact_index,
    /// The delegated closure produced an answer the e-graph's own orbit never
    /// reaches. Two independent derivations disagreed; the program is left
    /// alone and the disagreement is reported rather than resolved by
    /// preference.
    disagreement,
};

pub const Census = struct {
    /// Bodies this module looked at.
    examined: u32 = 0,
    /// Bodies closed to a constant.
    closed: u32 = 0,
    refusal: ?Refusal = null,
    /// D3: slots deleted from the state key because the demanded projection of
    /// the continuation cannot see them.
    slots_deleted: u8 = 0,
    slots_tracked: u8 = 0,
    /// D1: operators and rules the projection deleted before insertion.
    ops_deleted: u8 = 0,
    rules_deleted: u8 = 0,
    /// The saturation bound, MEASURED for this program.
    classes: u32 = 0,
    nodes: u32 = 0,
    steps: u32 = 0,
    mu: u32 = 0,
    lambda: u32 = 0,
    stop: Stop = .contracted,
    demanded_bits: u7 = 64,
    /// THE COMPOSITION, COUNTED. Calls this decision handed to
    /// `quotient_synth.admitInQuotient`, and how many carried a derived
    /// mod-2^k homomorphism. `examined > 0, admitted == 0` is the honest
    /// reading of a body whose relation is outside the law's class, and it is
    /// a different fact from "no call was there".
    calls_examined: u32 = 0,
    calls_admitted: u32 = 0,
};

pub const Outcome = struct {
    value: i64,
    valid_bits: u7,
    family: Family,
    census: Census,
};

pub const Result = union(enum) {
    closed: Outcome,
    refused: struct { refusal: Refusal, census: Census },
};

/// Q1 + Q2 — **THE PROJECTION IS A FACT, AND THIS IS WHERE IT IS EARNED.**
///
/// `main: i64` in a sealed executable returns to a process, and a process exit
/// status is EIGHT BITS. MEASURED, and it is the whole license: a `main`
/// returning 500,000,500,000 exits 32, which is its low byte. So the demanded
/// projection of the entry's result is `low_bits 8` and every distinction above
/// bit 7 is unobservable.
///
/// `recurrence.zig`'s O9 says the call site owes two proofs and this function
/// discharges both:
///
///   (a) THIS RELATION IS THE ENTRY. One-segment path spelled `main`, no
///       parameters, no varargs.
///   (b) NOTHING IN THE MODULE APPLIES IT. Checked against the graph's own
///       application facts, and an UNRESOLVED application anywhere in the
///       module is a refusal — an application this function cannot name may be
///       the one that reads the full 64 bits.
///
/// plus Q2, the observer roster, which is `demand_projection.observationRefusal`
/// and is not reimplemented here.
pub fn entryProjection(
    fd: *const ast.FuncDecl,
    graph: ?*const semantic_graph.SemanticGraph,
    world: observation.World,
) union(enum) { projection: Projection, refused: Refusal } {
    if (fd.path.len != 1 or !std.mem.eql(u8, fd.path[0], "main"))
        return .{ .refused = .not_entry };
    if (fd.func.params.len != 0 or fd.func.vararg or fd.func.vararg_name != null)
        return .{ .refused = .not_entry };

    if (demand_projection.observationRefusal(world) != null)
        return .{ .refused = .observer_refused };

    if (graph) |g| {
        if (g.unresolvedApplicationCount(null) != 0)
            return .{ .refused = .unresolved_application };
        const entry = g.findFunc("main") orelse return .{ .refused = .not_entry };
        for (g.applications()) |fact| {
            const callee = g.applicationRelation(fact.application) orelse
                return .{ .refused = .unresolved_application };
            if (callee == entry) return .{ .refused = .entry_applied };
        }
    }
    return .{ .projection = .{ .low_bits = 8 } };
}

/// Read the relation body as [constant prologue] [one counted loop] [tail].
fn readMachine(fb: *const ast.FuncBody, m: *Machine) ?struct { loop: *const ast.Stmt, tail: *const ast.Expr } {
    var loop: ?*const ast.Stmt = null;
    for (fb.body.stmts) |*st| {
        switch (st.*) {
            .local_decl => |d| {
                if (loop != null) return null;
                if (d.names.len != d.inits.len) return null;
                for (d.names, d.inits) |n, init| {
                    const v = switch (init.*) {
                        .int_lit => |x| x.val,
                        else => return null,
                    };
                    const slot = m.intern(n.ident) orelse return null;
                    m.entry[slot] = v;
                }
            },
            .assign => |a| {
                if (loop != null) return null;
                if (a.targets.len != 1 or a.values.len != 1) return null;
                const name = switch (a.targets[0].*) {
                    .name => |n| n.ident,
                    else => return null,
                };
                const v = switch (a.values[0].*) {
                    .int_lit => |x| x.val,
                    else => return null,
                };
                const slot = m.intern(name) orelse return null;
                m.entry[slot] = v;
            },
            .while_loop => {
                if (loop != null) return null;
                loop = st;
            },
            // Q8: anything else in the relation body — a second loop, an `if`,
            // a `return`, a `break` — refuses.
            else => return null,
        }
    }
    const l = loop orelse return null;
    const tail = fb.body.tail_expr orelse return null;
    return .{ .loop = l, .tail = tail };
}

/// Q8 for the loop body: every statement a single-target assignment to a name
/// already bound at entry. A name assigned in the body with no entry value is
/// refused rather than assumed zero.
fn readBody(body: *const ast.Block, m: *Machine) bool {
    if (body.tail_expr != null) return false;
    for (body.stmts) |st| {
        const a = switch (st) {
            .assign => |x| x,
            else => return false,
        };
        if (a.targets.len != 1 or a.values.len != 1) return false;
        const name = switch (a.targets[0].*) {
            .name => |n| n.ident,
            else => return false,
        };
        const slot = m.indexOf(name) orelse return false;
        if (m.stmt_count == max_slots) return false;
        m.order[m.stmt_count] = slot;
        m.update[m.stmt_count] = a.values[0];
        m.stmt_count += 1;
    }
    return m.stmt_count > 0;
}

/// Q3 — **D3, THE CONTRACTION THAT PAYS.**
///
/// A slot enters the state key only if the demanded projection of the
/// continuation can see it, or if a slot that can be seen reads it. Everything
/// else is deleted BEFORE the first insertion, which on the W6 body takes the
/// saturation from 260 states to 5 and turns a 256-cycle into a fixed point.
///
/// Least fixpoint, and it errs toward KEEPING: `mentions` answers true for
/// every expression form it does not enumerate.
/// **PIECE 3 OF THE COMPOSITION LIVES ON THE FIRST LINE.**
/// `demand_projection.projectionOfName` answers `whole` for a tail that calls a
/// user-defined relation — unless `quotient_synth` is installed, in which case
/// the answer comes from the callee's own body. `closeRelation` installs it
/// around this call, so `tag(x)` demands of `x` what `tag` actually reads
/// rather than everything.
fn observedClosure(m: *Machine, tail: *const ast.Expr, h: Projection) void {
    for (0..m.slot_count) |i| {
        const p = demand_projection.projectionOfName(h, tail, m.names[i]);
        m.tracked[i] = p != .none;
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (0..m.stmt_count) |s| {
            const slot = m.order[s];
            if (!m.tracked[slot]) continue;
            for (0..m.slot_count) |j| {
                if (m.tracked[j]) continue;
                if (mentions(m.env, m.update[s], m.names[j])) {
                    m.tracked[j] = true;
                    changed = true;
                }
            }
        }
    }
}

/// FAIL-CLOSED: an expression form this does not enumerate answers TRUE, so an
/// unmodelled construct keeps the slot in the key rather than deleting it.
///
/// A CALL IS THE ONE FORM WHERE FAIL-CLOSED WAS COSTING THE WHOLE CONTRACTION.
/// `x = step(x)` made every slot answer TRUE and D3 deleted nothing, so a body
/// with a call could not contract even when the call was admitted three lines
/// later. It is answered precisely only when `admitInQuotient` proves the
/// callee — which carries `onlyParams`, so the callee reads its ARGUMENTS and
/// nothing else and cannot reach a name that is not passed to it. Without the
/// table, or for a callee the law refuses, the answer is TRUE exactly as
/// before: a relation this module cannot see into may read a place it cannot
/// bound.
fn mentions(env: ?*quotient_synth.Env, e: *const ast.Expr, name: []const u8) bool {
    return switch (e.*) {
        .int_lit, .float_lit, .string_lit, .nil, .true_lit, .false_lit => false,
        .name => |n| std.mem.eql(u8, n.ident, name),
        .unop => |u| mentions(env, u.operand, name),
        .binop => |b| mentions(env, b.lhs, name) or mentions(env, b.rhs, name),
        .call => |c| blk: {
            const table = env orelse break :blk true;
            if (quotient_synth.admitInQuotient(table, c) == null) break :blk true;
            if (mentions(env, c.func, name)) break :blk true;
            for (c.args) |a| if (mentions(env, a, name)) break :blk true;
            break :blk false;
        },
        else => true,
    };
}

/// Q6 — a trip-count LOWER BOUND, and deliberately not the trip count.
///
/// `demand.provenTripCount` proves the loop is counted, monotone, single-update
/// and finite — and it asks `recurrence.terminatesForAnyStart` for the
/// arithmetic, so the tree still has ONE termination kernel. What it returns
/// does NOT carry the guard's inclusivity, so an exact trip count cannot be
/// reconstructed from it; rounding DOWN gives a bound that is sound for `<` and
/// `<=` alike, and a bound is all the fixed-point family needs.
fn tripLowerBound(loop: anytype, m: *const Machine) ?u64 {
    const p = demand.provenTripCount(loop) orelse return null;
    const slot = m.indexOf(p.counter) orelse return null;
    const start: i128 = m.entry[slot];
    const limit: i128 = p.limit;
    const step: i128 = p.step;
    if (step <= 0) return null;
    const span: i128 = if (p.ascending) limit - start else start - limit;
    if (span <= 0) return 0;
    return @intCast(@divFloor(span, step));
}

/// The whole decision, in the order §26 mandates: derive the fact, CONTRACT,
/// then saturate, then rank.
///
/// `mod` is the module the entry lives in, or null. It carries ONE thing: the
/// user-defined relation table `quotient_synth.zig` derives law from. Null is
/// this module as it shipped — every call refuses — and the corpus differential
/// in the report is against exactly that.
pub fn closeRelation(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    mod: ?*const ast.Module,
    graph: ?*const semantic_graph.SemanticGraph,
    world: observation.World,
    bound: Bound,
) !Result {
    var census = Census{ .examined = 1 };

    // §22-23's law closure, INSTALLED FOR THE DURATION OF THIS ONE DECISION,
    // exactly as `demand.zig` installs it for the duration of one backward
    // walk. Uninstalled on the way out, so no analysis outside this call sees a
    // table it did not ask for and an uninstalled derivative is bit-identical
    // to the one that shipped.
    var qenv: ?quotient_synth.Env = if (mod) |m| quotient_synth.Env.scan(m, .{}) else null;
    if (qenv != null) quotient_synth.install(&qenv.?);
    defer if (qenv != null) quotient_synth.uninstall();

    const h: Projection = switch (entryProjection(fd, graph, world)) {
        .refused => |r| return refuse(&census, r),
        .projection => |p| p,
    };
    census.demanded_bits = switch (h) {
        .low_bits => |k| k,
        else => 64,
    };
    const bits: u6 = switch (h) {
        .low_bits => |k| k,
        else => return refuse(&census, .projection_not_narrow),
    };

    census.ops_deleted = @intCast(Op.count - admittedOps(h).count());
    census.rules_deleted = @intCast(Rule.count - admittedRules(h).count());

    var m = Machine{ .env = if (qenv != null) &qenv.? else null };
    const shape = readMachine(&fd.func, &m) orelse return refuse(&census, .no_loop);
    const loop = shape.loop.while_loop;
    if (!readBody(&loop.body, &m)) return refuse(&census, .body_not_admitted);

    // D3. Before any insertion.
    observedClosure(&m, shape.tail, h);
    var tracked: u8 = 0;
    for (0..m.slot_count) |i| {
        if (m.tracked[i]) tracked += 1;
    }
    census.slots_tracked = tracked;
    census.slots_deleted = @intCast(m.slot_count - tracked);
    if (tracked == 0) return refuse(&census, .body_not_admitted);
    // The tuple key packs `bits` per tracked slot; wider than a u64 of distinct
    // states is a family this bound cannot hold.
    if (@as(usize, bits) * tracked > 64) return refuse(&census, .too_many_slots);

    const trips = tripLowerBound(loop, &m) orelse return refuse(&census, .no_trip_bound);

    var eg = EGraph.init(alloc, h, bound);
    defer eg.deinit();
    var answers: std.AutoHashMapUnmanaged(i64, void) = .empty;
    defer answers.deinit(alloc);

    const closure = closeMachine(&eg, &m, shape.tail, &answers) catch |err| switch (err) {
        error.AnalysisConflict => return refuse(&census, .conflict),
        error.BoundExceeded => return refuse(&census, .budget),
        else => return err,
    } orelse return refuse(&census, if (eg.overflow) .budget else .body_not_admitted);

    census.classes = closure.classes;
    census.nodes = closure.nodes;
    census.steps = closure.steps;
    census.mu = closure.mu;
    census.lambda = closure.lambda;
    if (qenv) |*q| {
        census.calls_examined = q.census.calls_examined;
        census.calls_admitted = q.census.calls_admitted;
    }

    var facts: FactSet = .{};
    facts.insert(.projection_proven);
    facts.insert(.roster_permits_width);
    facts.insert(.body_in_grammar);
    facts.insert(.operators_commute);
    facts.insert(.quotient_finite);
    facts.insert(.entry_constant);
    facts.insert(.trip_bound_proven);
    if (closure.lambda == 1 and trips >= closure.mu) facts.insert(.orbit_is_fixed_point);

    var sp = contract(facts, h);

    if (sp.has(.fixed_point)) {
        const idx = rank(&sp, .{ .compile_steps = closure.steps, .trips = trips }, h) orelse
            return refuse(&census, .not_a_fixed_point);
        if (sp.survivors[idx].family == .fixed_point) {
            // Q9. The answer is the TAIL evaluated in the quotient over the
            // closed values, so the tail is subject to the same grammar as the
            // body.
            const tail_id = (try build(&eg, shape.tail, &m, &closure.values)) orelse
                return refuse(&census, .tail_not_admitted);
            const raw = eg.constantOf(tail_id) orelse return refuse(&census, .tail_not_admitted);
            const report = try saturate(&eg, &.{tail_id});
            census.stop = report.stop;
            census.classes = eg.classCount();
            census.nodes = eg.nodeCount();
            census.closed = 1;
            const value = h.apply(raw) orelse return refuse(&census, .tail_not_admitted);
            return .{ .closed = .{
                .value = value,
                .valid_bits = bits,
                .family = .fixed_point,
                .census = census,
            } };
        }
    }

    // ── THE SECOND FAMILY, AND IT IS DELEGATED ────────────────────────────
    //
    // `lambda > 1`: the answer is the orbit state at the EXACT trip index, and
    // an exact trip count is not a fact this module owns. `src/recurrence.zig`
    // owns it — O1 trip-count exactness, O2 no IV wrap, O5 termination by
    // construction, O8 guard invariance — and `src/demand.zig` states the rule
    // that keeps this from becoming a second kernel: *a compiler carrying two
    // proofs of one fact can license with the first what the second would have
    // refused.* So the fact `trip_count_exact` is discharged BY DELEGATION: it
    // is true exactly when `recurrence` answers, and false when it refuses.
    //
    // §24 — no candidate generator is semantic authority. This one is checked:
    // the answer it returns must be a state THE E-GRAPH'S OWN ORBIT REACHES.
    // Two independent quotient derivations, one contracted and one not, and a
    // disagreement leaves the program alone.
    //
    // THE CALL SITE THAT DID NOT EXIST. `closeRelationBodyObserved` has been in
    // the tree with zero non-test consumers; the only symbol anyone imported
    // from that file was `terminatesForAnyStart`. The projection this passes it
    // is the one `demand_projection.zig` produces, and this line is the edge
    // between them.
    //
    // AND IT NOW CARRIES THE CONTRACTION AS WELL AS THE PROJECTION. D3 is
    // computed above for THIS module's e-graph; handing the same set over
    // means the delegated walk quotients the state the same way instead of
    // walking the uncontracted orbit — the induction variable's 256-cycle
    // multiplied every other slot's period on the far side of a seam that had
    // the answer on this side. `recurrence` re-derives the condition that
    // makes the drop lawful and refuses one it cannot confirm, so this is a
    // fact offered, not a fact imposed.
    //
    // The relation table travels the same way, for the same reason: a body
    // whose loop applies a user-defined relation reaches the exact-index
    // family only if the far side can evaluate the call, and only
    // `quotient_synth` can say whether that is lawful.
    if (closure.lambda > 1) {
        var trial: FactSet = facts;
        trial.insert(.trip_count_exact);
        var sp2 = contract(trial, h);
        if (sp2.has(.orbit_index)) {
            var unobserved: [max_slots][]const u8 = undefined;
            var dropped: usize = 0;
            for (0..m.slot_count) |i| {
                if (m.tracked[i]) continue;
                unobserved[dropped] = m.names[i];
                dropped += 1;
            }
            const k = recurrence.closeRelationBodyObserved(&fd.func, .{
                .bits = bits,
                .unobserved = unobserved[0..dropped],
                .call_ctx = if (qenv) |*q| @as(*const anyopaque, @ptrCast(q)) else null,
                .call_value = if (qenv == null) null else &callValueInRing,
            }) orelse
                return refuse(&census, .no_exact_index);
            const value = h.apply(k) orelse return refuse(&census, .tail_not_admitted);
            if (!answers.contains(value)) return refuse(&census, .disagreement);
            const idx2 = rank(&sp2, .{ .compile_steps = closure.steps, .trips = trips }, h) orelse
                return refuse(&census, .no_exact_index);
            if (sp2.survivors[idx2].family == .run_loop) return refuse(&census, .no_exact_index);
            census.stop = .fixpoint;
            census.closed = 1;
            return .{ .closed = .{
                .value = value,
                .valid_bits = bits,
                .family = .orbit_index,
                .census = census,
            } };
        }
    }

    return refuse(&census, if (closure.lambda != 1) .not_a_fixed_point else .trips_below_mu);
}

fn refuse(census: *Census, r: Refusal) Result {
    census.refusal = r;
    return .{ .refused = .{ .refusal = r, .census = census.* } };
}

/// **THE PRODUCER BEHIND `recurrence.Observation.call_value`.**
///
/// `recurrence.zig` asks one question — *what is this call worth, in the ring,
/// at these arguments?* — and this answers it only when `quotient_synth` has
/// derived a PURE mod-2^k ring homomorphism from the callee's own body. That
/// is the same admission `build` above applies to the same node, through the
/// same two functions, so the two engines cannot come to different conclusions
/// about which calls are lawful.
///
/// No type crosses the seam: `*const anyopaque` in, `?i64` out. `recurrence`
/// compiles with or without a producer, and with none every call refuses
/// exactly as it did.
fn callValueInRing(ctx: *const anyopaque, call: *const ast.Expr, args: []const i64) ?i64 {
    const env: *quotient_synth.Env = @constCast(@ptrCast(@alignCast(ctx)));
    const c = switch (call.*) {
        .call => |x| x,
        else => return null,
    };
    if (args.len != c.args.len) return null;
    const admitted = quotient_synth.admitInQuotient(env, c) orelse return null;
    return quotient_synth.evalAnswer(env, admitted.rel, args);
}

/// **THE TRANSFORM.** Replace the entry relation's whole body with the constant
/// its demanded observer cannot distinguish from it.
///
/// Called from the ONE site that already carries the world fact — the direct
/// executable lift in `main.zig`, where `world_closed = true` is asserted with
/// its own comment saying the dylib and obj sites deliberately do not. Nothing
/// is inferred here about the artifact kind; the caller supplies it.
pub fn applyToEntry(
    alloc: std.mem.Allocator,
    mod: *ast.Module,
    graph: ?*const semantic_graph.SemanticGraph,
    world: observation.World,
) !?Outcome {
    for (mod.body.stmts) |*st| {
        if (st.* != .func_decl) continue;
        const fd = &st.func_decl;
        if (fd.path.len != 1 or !std.mem.eql(u8, fd.path[0], "main")) continue;
        const r = try closeRelation(alloc, fd, mod, graph, world, .{});
        switch (r) {
            .refused => return null,
            .closed => |out| {
                const e = try alloc.create(ast.Expr);
                e.* = .{ .int_lit = .{ .loc = fd.func.body.loc, .val = out.value } };
                fd.func.body.stmts = fd.func.body.stmts[0..0];
                fd.func.body.tail_expr = e;
                return out;
            },
        }
    }
    return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
//
// Every closure test is DIFFERENTIAL against a brute-force loop written in Zig
// with the same wrapping arithmetic. A closed form checked against a
// hand-computed constant only proves the author's algebra agrees with itself.
// ═══════════════════════════════════════════════════════════════════════════

const testing = std.testing;

// ---- the e-graph itself ----

test "obseq: the congruence key is taken through the projection" {
    // THE THESIS, as one assertion. 12345 and 57 differ in every bit above 7
    // and are the SAME E-CLASS under `low_bits 8`, and different classes at
    // full width. Nothing else in this file matters if this does not hold.
    var narrow = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer narrow.deinit();
    const a = try narrow.add(.{ .op = .cst, .k = 12345 });
    const b = try narrow.add(.{ .op = .cst, .k = 57 });
    try testing.expectEqual(narrow.find(a), narrow.find(b));

    var wide = EGraph.init(testing.allocator, .whole, .{});
    defer wide.deinit();
    const c = try wide.add(.{ .op = .cst, .k = 12345 });
    const d = try wide.add(.{ .op = .cst, .k = 57 });
    try testing.expect(wide.find(c) != wide.find(d));
}

test "obseq: congruence propagates the collapse to terms built from them" {
    // `12345 * 3` and `57 * 3` are DIFFERENT TERMS with different values, and
    // one e-class under `low_bits 8`. This is congruence, not constant folding:
    // the children are equal so the parents are.
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const three = try eg.add(.{ .op = .cst, .k = 3 });
    const x = try eg.add(.{ .op = .cst, .k = 12345 });
    const y = try eg.add(.{ .op = .cst, .k = 57 });
    const px = try eg.add(.{ .op = .mul, .a = x, .b = three });
    const py = try eg.add(.{ .op = .mul, .a = y, .b = three });
    try testing.expectEqual(eg.find(px), eg.find(py));
}

test "obseq: merge repairs congruence through a parent" {
    // Two leaves merged AFTER their parents exist. Ordinary congruence closure:
    // the parents must become equal without being rebuilt by the caller.
    var eg = EGraph.init(testing.allocator, .whole, .{});
    defer eg.deinit();
    const u = try eg.add(.{ .op = .leaf, .k = 1 });
    const v = try eg.add(.{ .op = .leaf, .k = 2 });
    const w = try eg.add(.{ .op = .leaf, .k = 3 });
    const pu = try eg.add(.{ .op = .add, .a = u, .b = w });
    const pv = try eg.add(.{ .op = .add, .a = v, .b = w });
    try testing.expect(eg.find(pu) != eg.find(pv));
    try eg.merge(u, v);
    try testing.expectEqual(eg.find(pu), eg.find(pv));
}

test "obseq: an equivalence that is FALSE at full width and TRUE in the quotient" {
    // `x * 256 = 0` and `x + 256 = x` are not true of any integer. They are
    // true of every observation that reads eight bits, and a demand-blind
    // e-graph cannot hold them at all.
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const x = try eg.add(.{ .op = .leaf, .k = 7 });
    const c = try eg.add(.{ .op = .cst, .k = 256 });
    const prod = try eg.add(.{ .op = .mul, .a = x, .b = c });
    const sum = try eg.add(.{ .op = .add, .a = x, .b = c });
    const zero = try eg.add(.{ .op = .cst, .k = 0 });
    _ = try saturate(&eg, &.{});
    try testing.expectEqual(eg.find(zero), eg.find(prod));
    try testing.expectEqual(eg.find(x), eg.find(sum));

    // The adversarial control: the SAME graph at full width proves neither.
    var wide = EGraph.init(testing.allocator, .whole, .{});
    defer wide.deinit();
    const wx = try wide.add(.{ .op = .leaf, .k = 7 });
    const wc = try wide.add(.{ .op = .cst, .k = 256 });
    const wprod = try wide.add(.{ .op = .mul, .a = wx, .b = wc });
    const wsum = try wide.add(.{ .op = .add, .a = wx, .b = wc });
    const wzero = try wide.add(.{ .op = .cst, .k = 0 });
    _ = try saturate(&wide, &.{});
    try testing.expect(wide.find(wzero) != wide.find(wprod));
    try testing.expect(wide.find(wx) != wide.find(wsum));
}

test "obseq: D1 — the projection deletes rules and operators before insertion" {
    // §26 at the rule level. Under `nonzero` almost the whole term language is
    // inadmissible, and the deletion happens in a signature that has never seen
    // a cost.
    try testing.expectEqual(@as(usize, Rule.count), admittedRules(.{ .low_bits = 8 }).count());
    try testing.expectEqual(@as(usize, 6), admittedRules(.whole).count());
    try testing.expectEqual(@as(usize, 3), admittedRules(.nonzero).count());
    try testing.expectEqual(@as(usize, 0), admittedRules(.none).count());

    try testing.expectEqual(@as(usize, Op.count), admittedOps(.{ .low_bits = 8 }).count());
    try testing.expectEqual(@as(usize, 3), admittedOps(.nonzero).count());
    try testing.expect(!commutesWith(.add, .nonzero));
}

// ---- the machine, differentially ----

const Loc = ast.Loc{ .file = "obseq-test", .line = 1, .col = 1 };

/// A tiny AST builder. The bodies below are the SHAPES the transform sees, and
/// building them by hand is what keeps the tests independent of the parser.
const Build = struct {
    arena: std.heap.ArenaAllocator,

    fn init() Build {
        return .{ .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }
    fn deinit(self: *Build) void {
        self.arena.deinit();
    }
    fn a(self: *Build) std.mem.Allocator {
        return self.arena.allocator();
    }
    fn lit(self: *Build, v: i64) *ast.Expr {
        const e = self.a().create(ast.Expr) catch unreachable;
        e.* = .{ .int_lit = .{ .loc = Loc, .val = v } };
        return e;
    }
    fn nm(self: *Build, s: []const u8) *ast.Expr {
        const e = self.a().create(ast.Expr) catch unreachable;
        e.* = .{ .name = .{ .loc = Loc, .ident = s } };
        return e;
    }
    fn bin(self: *Build, op: ast.BinOp, l: *ast.Expr, r: *ast.Expr) *ast.Expr {
        const e = self.a().create(ast.Expr) catch unreachable;
        e.* = .{ .binop = .{ .loc = Loc, .op = op, .lhs = l, .rhs = r } };
        return e;
    }
    fn assign(self: *Build, name: []const u8, v: *ast.Expr) ast.Stmt {
        const t = self.a().alloc(*ast.Expr, 1) catch unreachable;
        t[0] = self.nm(name);
        const vs = self.a().alloc(*ast.Expr, 1) catch unreachable;
        vs[0] = v;
        return .{ .assign = .{ .loc = Loc, .targets = t, .values = vs } };
    }
    fn block(self: *Build, stmts: []const ast.Stmt, tail: ?*ast.Expr) ast.Block {
        const s = self.a().alloc(ast.Stmt, stmts.len) catch unreachable;
        @memcpy(s, stmts);
        return .{ .loc = Loc, .stmts = s, .tail_expr = tail };
    }
};

/// The W6 relation: `x = x ~ (x * 1103515245); x = x + 12345; i = i + 1`, run
/// `n` times, answered by the tail `x`.
fn w6Decl(b: *Build, n: i64) ast.FuncDecl {
    const body = b.block(&.{
        b.assign("x", b.bin(.bxor, b.nm("x"), b.bin(.mul, b.nm("x"), b.lit(1103515245)))),
        b.assign("x", b.bin(.add, b.nm("x"), b.lit(12345))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("x", b.lit(12345)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(n)), .body = body } },
    }, b.nm("x"));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    return .{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
}

/// A two-accumulator relation whose CONTRACTED orbit is periodic rather than a
/// fixed point, so the fixed-point family cannot answer it and the decision
/// falls to the delegated exact-index family.
///
///     a = a ~ (b * ca) ; b = b + (a * cb) ; i = i + 1     answered by `a + b`
fn pairDecl(b: *Build, n: i64, ca: i64, cb: i64) ast.FuncDecl {
    const body = b.block(&.{
        b.assign("a", b.bin(.bxor, b.nm("a"), b.bin(.mul, b.nm("b"), b.lit(ca)))),
        b.assign("b", b.bin(.add, b.nm("b"), b.bin(.mul, b.nm("a"), b.lit(cb)))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("a", b.lit(12345)),
        b.assign("b", b.lit(6789)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(n)), .body = body } },
    }, b.bin(.add, b.nm("a"), b.nm("b")));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    return .{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
}

/// The W6 shape with the constants opened up, so the sweep can vary them.
fn soloDecl(b: *Build, n: i64, c1: i64, c2: i64) ast.FuncDecl {
    const body = b.block(&.{
        b.assign("x", b.bin(.bxor, b.nm("x"), b.bin(.mul, b.nm("x"), b.lit(c1)))),
        b.assign("x", b.bin(.add, b.nm("x"), b.lit(c2))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("x", b.lit(12345)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(n)), .body = body } },
    }, b.nm("x"));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    return .{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
}

fn soloOracle(n: u64, c1: i64, c2: i64) u64 {
    var x: u64 = 12345;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        x = x ^ (x *% @as(u64, @bitCast(c1)));
        x = x +% @as(u64, @bitCast(c2));
    }
    return x;
}

fn pairOracle(n: u64, ca: i64, cb: i64) u64 {
    var a: u64 = 12345;
    var b: u64 = 6789;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        a = a ^ (b *% @as(u64, @bitCast(ca)));
        b = b +% (a *% @as(u64, @bitCast(cb)));
    }
    return a +% b;
}

/// The oracle: the same loop, run for real in Zig, with the same wrapping
/// arithmetic. Not this module's algebra.
fn w6Oracle(n: u64) u64 {
    var x: u64 = 12345;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        x = x ^ (x *% 1103515245);
        x = x +% 12345;
    }
    return x;
}

test "obseq: W6 closes to a FIXED POINT, and the answer matches a real loop" {
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 20000000);
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    const out = switch (r) {
        .refused => |x| {
            std.debug.print("refused: {s}\n", .{@tagName(x.refusal)});
            return error.TestUnexpectedResult;
        },
        .closed => |o| o,
    };
    try testing.expectEqual(@as(i64, @intCast(w6Oracle(20000000) & 0xff)), out.value);
    try testing.expectEqual(@as(u7, 8), out.valid_bits);
    try testing.expectEqual(Family.fixed_point, out.family);

    // D3's number, as an executable expectation. `i` is deleted from the key,
    // the orbit is a FIXED POINT, and the whole saturation is five steps.
    try testing.expectEqual(@as(u8, 1), out.census.slots_deleted);
    try testing.expectEqual(@as(u8, 1), out.census.slots_tracked);
    try testing.expectEqual(@as(u32, 1), out.census.lambda);
    try testing.expectEqual(@as(u32, 4), out.census.mu);
    try testing.expectEqual(@as(u32, 5), out.census.steps);
}

test "obseq: the closed value is right at EVERY trip count past mu" {
    // The fixed-point family's whole claim is that the exact trip count does
    // not enter the answer. The differential sweeps it.
    var b = Build.init();
    defer b.deinit();
    var n: i64 = 4;
    while (n <= 4096) : (n *= 2) {
        const fd = w6Decl(&b, n);
        const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
        switch (r) {
            .refused => return error.TestUnexpectedResult,
            .closed => |o| try testing.expectEqual(
                @as(i64, @intCast(w6Oracle(@intCast(n)) & 0xff)),
                o.value,
            ),
        }
    }
}

test "obseq: Q7 — a loop that may run fewer than mu times is REFUSED" {
    // `n = 3` with `mu = 4`. The quotient is eventually constant and the loop
    // does not reach eventually. "Eventually constant" is not "constant", and
    // the refusal is the difference.
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 3);
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    switch (r) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expectEqual(Refusal.trips_below_mu, x.refusal),
    }
}

test "obseq: D3 — deleting the unobserved slot is what makes the fixed point exist" {
    // THE §26 MEASUREMENT, as a test. With the induction variable in the key
    // the orbit is a 256-cycle and needs an exact trip count; with it deleted
    // the orbit is a fixed point and needs only a bound. Same program, same
    // projection, different state key.
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 20000000);

    var m = Machine{};
    const shape = readMachine(&fd.func, &m).?;
    try testing.expect(readBody(&shape.loop.while_loop.body, &m));

    // Contracted: the tail reads only `x`.
    observedClosure(&m, shape.tail, .{ .low_bits = 8 });
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const small = (try closeMachine(&eg, &m, null, null)).?;
    try testing.expectEqual(@as(u32, 1), small.lambda);
    try testing.expectEqual(@as(u32, 5), small.steps);

    // Demand-blind: keep every slot, which is what an exact-term engine must do.
    var m2 = Machine{};
    const shape2 = readMachine(&fd.func, &m2).?;
    try testing.expect(readBody(&shape2.loop.while_loop.body, &m2));
    for (0..m2.slot_count) |i| m2.tracked[i] = true;
    var eg2 = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg2.deinit();
    const big = (try closeMachine(&eg2, &m2, null, null)).?;
    try testing.expectEqual(@as(u32, 256), big.lambda);
    try testing.expectEqual(@as(u32, 260), big.steps);

    // 52x, and the shape changed: a cycle became a fixed point.
    try testing.expect(big.steps > small.steps * 50);
}

test "obseq: D2 — at h = whole the family is deleted with ZERO e-nodes created" {
    // The contraction that FRONTIER §3 asks to be stated: an unbounded quotient
    // deletes the family before insertion rather than exhausting a budget.
    const facts = blk: {
        var s: FactSet = .{};
        for (std.enums.values(Fact)) |f| s.insert(f);
        break :blk s;
    };
    const narrow = contract(facts, .{ .low_bits = 8 });
    try testing.expect(narrow.has(.fixed_point));
    const wide = contract(facts, .whole);
    try testing.expect(!wide.has(.fixed_point));
    try testing.expect(!wide.has(.orbit_index));
    for (wide.deletionSlice()) |d| {
        if (d.family == .fixed_point) try testing.expectEqual(@as(?Fact, null), d.missing);
    }
}

// ---- §84, twice, in both directions ----

test "obseq: §84 — perturbing every cost to absurd values changes NO legality" {
    const facts = blk: {
        var s: FactSet = .{};
        for (std.enums.values(Fact)) |f| s.insert(f);
        break :blk s;
    };
    var a = contract(facts, .{ .low_bits = 8 });
    for (a.survivors[0..a.survivor_count]) |*c| {
        c.cost_estimate.setFact(.latency, std.math.floatMax(f32), .measured);
        c.cost_estimate.setFact(.code_size, std.math.floatMax(f32), .measured);
    }
    const b = contract(facts, .{ .low_bits = 8 });
    try testing.expectEqual(a.survivor_count, b.survivor_count);
    for (a.survivorSlice(), b.survivorSlice()) |x, y| {
        try testing.expectEqual(x.family, y.family);
        try testing.expectEqual(x.semantic_proof, y.semantic_proof);
    }
}

test "obseq: §19 — removing each fact moves the candidate set" {
    // A fact that changes no candidate set is not operative, and by §7 it is
    // scenery. Every fact this module retains earns its place here.
    const all = blk: {
        var s: FactSet = .{};
        for (std.enums.values(Fact)) |f| s.insert(f);
        break :blk s;
    };
    const base = contract(all, .{ .low_bits = 8 });
    var moved: usize = 0;
    for (std.enums.values(Fact)) |f| {
        var without = all;
        without.remove(f);
        const sp = contract(without, .{ .low_bits = 8 });
        if (sp.survivor_count != base.survivor_count) moved += 1;
    }
    try testing.expectEqual(@as(usize, Fact.count), moved);
    // And `run_loop` survives every deletion: `none` must always be a
    // candidate, and so must "do it the way it was written".
    try testing.expect(contract(.{}, .{ .low_bits = 8 }).has(.run_loop));
}

test "obseq: §84 — ranking never sees a fact, and the loop's cost is its TRIPS" {
    // Not an instruction count. The same survivor set ranks differently on the
    // trip count alone, which is the dimension a static count cannot see.
    const facts = blk: {
        var s: FactSet = .{};
        for (std.enums.values(Fact)) |f| s.insert(f);
        break :blk s;
    };
    var hot = contract(facts, .{ .low_bits = 8 });
    const i_hot = rank(&hot, .{ .compile_steps = 5, .trips = 20000000 }, .{ .low_bits = 8 }).?;
    try testing.expectEqual(Family.fixed_point, hot.survivors[i_hot].family);

    var cold = contract(facts, .{ .low_bits = 8 });
    const i_cold = rank(&cold, .{ .compile_steps = 5, .trips = 0 }, .{ .low_bits = 8 }).?;
    try testing.expectEqual(Family.run_loop, cold.survivors[i_cold].family);
}

// ---- the certificate ----

test "obseq: the stopping certificate is a proof, not a budget" {
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const c = try eg.add(.{ .op = .cst, .k = 125 });
    const rep = try saturate(&eg, &.{c});
    try testing.expectEqual(Stop.certificate, rep.stop);

    // A class with no constant cannot be certified, and the report says
    // `fixpoint` — saturated, but not proven optimal.
    var open = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer open.deinit();
    const leaf = try open.add(.{ .op = .leaf, .k = 1 });
    const rep2 = try saturate(&open, &.{leaf});
    try testing.expect(rep2.stop != .certificate);
}

test "obseq: the information floor is derived from the DEMANDED bits" {
    // §15: the floor is the minimum information reaching observation, not the
    // minimum instructions for the source formulation. Eight demanded bits are
    // one `mov`; sixty-four are four.
    const eight = informationFloor(.{ .low_bits = 8 });
    const wide = informationFloor(.whole);
    try testing.expectEqual(@as(f32, 1), eight.get(.latency).value);
    try testing.expectEqual(@as(f32, 4), wide.get(.latency).value);
    try testing.expectEqual(semantic_algebra.CostEvidence.proven, eight.get(.latency).evidence);
}

// ---- Q1/Q2: the fact is earned, not defaulted ----

test "obseq: Q2 — an open world refuses, and it refuses by ROSTER" {
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 20000000);
    // `World{}` has no `closed_world`, so `foreign` is in the roster and a
    // foreign caller takes the whole register.
    switch (entryProjection(&fd, null, observation.World{})) {
        .projection => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(Refusal.observer_refused, r),
    }
    // Adding a debugger demand to the CLOSED world refuses it too: a debugger
    // reads the value, not the exit byte.
    const watched = observation.ordinary_executable.with(.debugger_demanded);
    switch (entryProjection(&fd, null, watched)) {
        .projection => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(Refusal.observer_refused, r),
    }
    switch (entryProjection(&fd, null, observation.ordinary_executable)) {
        .refused => return error.TestUnexpectedResult,
        .projection => |p| try testing.expect(p.eql(.{ .low_bits = 8 })),
    }
}

test "obseq: Q1 — a relation that is not the entry gets no quotient" {
    var b = Build.init();
    defer b.deinit();
    var fd = w6Decl(&b, 20000000);
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "helper";
    fd.path = path;
    switch (entryProjection(&fd, null, observation.ordinary_executable)) {
        .projection => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(Refusal.not_entry, r),
    }
}

// ---- the second family, and the call site that did not exist ----

test "obseq: a PERIODIC contracted orbit falls to the delegated exact index" {
    // `recurrence.closeRelationBodyObserved` had ZERO non-test consumers; the
    // only symbol anyone imported from that file was `terminatesForAnyStart`.
    // This is the edge, and the projection it carries is the one
    // `demand_projection.zig` produces.
    var b = Build.init();
    defer b.deinit();
    const fd = pairDecl(&b, 20000000, 1103515245, 6364136223);
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    const out = switch (r) {
        .refused => |x| {
            std.debug.print("refused: {s}\n", .{@tagName(x.refusal)});
            return error.TestUnexpectedResult;
        },
        .closed => |o| o,
    };
    try testing.expectEqual(Family.orbit_index, out.family);
    try testing.expectEqual(@as(i64, @intCast(pairOracle(20000000, 1103515245, 6364136223) & 0xff)), out.value);
    // And the contraction still happened: `i` is out of the key even though the
    // family that used it is the one that answered.
    try testing.expectEqual(@as(u8, 1), out.census.slots_deleted);
    try testing.expect(out.census.lambda > 1);
}

test "obseq: D3 on the delegated row — 192 contracted states against 768" {
    // The §26 number for a program the fixed-point family cannot answer. The
    // contraction is worth 4x here and it is worth 52x on W6; both are measured
    // rather than promised, and both come from the same deletion.
    var b = Build.init();
    defer b.deinit();
    const fd = pairDecl(&b, 20000000, 1103515245, 6364136223);

    var m = Machine{};
    const shape = readMachine(&fd.func, &m).?;
    try testing.expect(readBody(&shape.loop.while_loop.body, &m));
    observedClosure(&m, shape.tail, .{ .low_bits = 8 });
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const small = (try closeMachine(&eg, &m, null, null)).?;
    try testing.expectEqual(@as(u32, 192), small.steps);

    var m2 = Machine{};
    const shape2 = readMachine(&fd.func, &m2).?;
    try testing.expect(readBody(&shape2.loop.while_loop.body, &m2));
    for (0..m2.slot_count) |i| m2.tracked[i] = true;
    var eg2 = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg2.deinit();
    const big = (try closeMachine(&eg2, &m2, null, null)).?;
    try testing.expectEqual(@as(u32, 768), big.steps);
}

test "obseq: §24 — the delegated answer is CHECKED against the e-graph's orbit" {
    // No candidate generator is semantic authority. The e-graph enumerates
    // every answer this loop can produce under `h`; a delegated answer outside
    // that set is a disagreement between two independent derivations, and the
    // program is left alone rather than the disagreement being resolved by
    // preference.
    var b = Build.init();
    defer b.deinit();
    const fd = pairDecl(&b, 20000000, 1103515245, 6364136223);

    var m = Machine{};
    const shape = readMachine(&fd.func, &m).?;
    try testing.expect(readBody(&shape.loop.while_loop.body, &m));
    observedClosure(&m, shape.tail, .{ .low_bits = 8 });
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    var answers: std.AutoHashMapUnmanaged(i64, void) = .empty;
    defer answers.deinit(testing.allocator);
    _ = (try closeMachine(&eg, &m, shape.tail, &answers)).?;

    const truth: i64 = @intCast(pairOracle(20000000, 1103515245, 6364136223) & 0xff);
    try testing.expect(answers.contains(truth));
    // The answer set is a strict subset of the 256 possible bytes, so the check
    // has teeth: a wrong index would usually land outside it.
    try testing.expect(answers.count() < 256);
}

/// `x = (x*x) ~ (x*1103515245) ; x = x + 12345`, answered by `x`. The row where
/// exact-term saturation does not terminate.
fn sqDecl(b: *Build, n: i64) ast.FuncDecl {
    const body = b.block(&.{
        b.assign("x", b.bin(.bxor, b.bin(.mul, b.nm("x"), b.nm("x")), b.bin(.mul, b.nm("x"), b.lit(1103515245)))),
        b.assign("x", b.bin(.add, b.nm("x"), b.lit(12345))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("x", b.lit(12345)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(n)), .body = body } },
    }, b.nm("x"));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    return .{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
}

fn sqOracle(n: u64) u64 {
    var x: u64 = 12345;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        x = (x *% x) ^ (x *% 1103515245);
        x = x +% 12345;
    }
    return x;
}

test "obseq: D2 — 65,536 exact states against FOUR in the quotient" {
    // THE §26 MEASUREMENT IN ITS STRONGEST FORM, and it is a differential
    // against the exact map rather than a claim about it. The exact 64-bit
    // orbit of this body is walked here for 65,536 steps and NEVER REPEATS —
    // so a demand-blind e-graph holds 65,536 e-classes at that point and is
    // still growing. Pushed to 3,000,000 steps offline it still never repeats.
    // The observation-relative graph closes the same body in FOUR.
    var exact: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer exact.deinit(testing.allocator);
    var x: u64 = 12345;
    for (0..65536) |_| {
        const slot = try exact.getOrPut(testing.allocator, x);
        try testing.expect(!slot.found_existing);
        x = (x *% x) ^ (x *% 1103515245);
        x = x +% 12345;
    }
    try testing.expectEqual(@as(usize, 65536), exact.count());

    var b = Build.init();
    defer b.deinit();
    const fd = sqDecl(&b, 20000000);
    var m = Machine{};
    const shape = readMachine(&fd.func, &m).?;
    try testing.expect(readBody(&shape.loop.while_loop.body, &m));
    observedClosure(&m, shape.tail, .{ .low_bits = 8 });
    var eg = EGraph.init(testing.allocator, .{ .low_bits = 8 }, .{});
    defer eg.deinit();
    const c = (try closeMachine(&eg, &m, null, null)).?;
    try testing.expectEqual(@as(u32, 4), c.steps);
    try testing.expectEqual(@as(u32, 4), c.lambda);

    // And it still answers, through the delegated exact index.
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    switch (r) {
        .refused => return error.TestUnexpectedResult,
        .closed => |o| {
            try testing.expectEqual(Family.orbit_index, o.family);
            try testing.expectEqual(@as(i64, @intCast(sqOracle(20000000) & 0xff)), o.value);
        },
    }
}

test "obseq: a randomized differential over the whole admitted grammar" {
    // 64 machines with random ring constants, each closed and checked against a
    // loop run for real. The point is coverage of BOTH families and of the
    // refusals: a sweep where nothing closes proves nothing, so the counts are
    // asserted too.
    var prng = std.Random.DefaultPrng.init(0x0b5e9);
    const rnd = prng.random();
    var closed_fixed: u32 = 0;
    var closed_orbit: u32 = 0;
    var refused: u32 = 0;
    for (0..64) |t| {
        var b = Build.init();
        defer b.deinit();
        const ca = rnd.int(i32);
        const cb = rnd.int(i32);
        const n: i64 = @intCast(1000 + t * 37);
        // Two shapes, so the sweep covers both families: one accumulator (which
        // reaches fixed points) and two (which do not).
        const solo = t % 2 == 0;
        const fd = if (solo) soloDecl(&b, n, ca, cb) else pairDecl(&b, n, ca, cb);
        const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{ .max_steps = 1024 });
        switch (r) {
            .refused => refused += 1,
            .closed => |o| {
                const truth: i64 = @intCast((if (solo)
                    soloOracle(@intCast(n), ca, cb)
                else
                    pairOracle(@intCast(n), ca, cb)) & 0xff);
                try testing.expectEqual(truth, o.value);
                switch (o.family) {
                    .fixed_point => closed_fixed += 1,
                    .orbit_index => closed_orbit += 1,
                    else => return error.TestUnexpectedResult,
                }
            },
        }
    }
    // Anti-vacuity: both families must actually fire in the sweep.
    try testing.expect(closed_fixed > 0);
    try testing.expect(closed_orbit > 0);
    try testing.expectEqual(@as(u32, 64), closed_fixed + closed_orbit + refused);
}

// ---- Q4/Q5: the grammar, and what it refuses ----

test "obseq: Q5 — a body that reads bits above the quotient is REFUSED" {
    // `x >> 7` has no homomorphism to Z/2^8 and the whole body goes with it.
    // This is the adversarial control on the operator admission: if the module
    // closed this it would be wrong, not merely optimistic.
    var b = Build.init();
    defer b.deinit();
    const body = b.block(&.{
        b.assign("x", b.bin(.bxor, b.nm("x"), b.bin(.rshift, b.nm("x"), b.lit(7)))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("x", b.lit(12345)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(1000)), .body = body } },
    }, b.nm("x"));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    const fd = ast.FuncDecl{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    switch (r) {
        .closed => return error.TestUnexpectedResult,
        .refused => {},
    }
}

test "obseq: a NON-quotientable body still closes when it is a fixed point" {
    // The anti-vacuity control on the other side: `x = x & 240` reaches a fixed
    // point in one step, so the family fires on a body with no multiply at all.
    var b = Build.init();
    defer b.deinit();
    const body = b.block(&.{
        b.assign("x", b.bin(.band, b.nm("x"), b.lit(240))),
        b.assign("i", b.bin(.add, b.nm("i"), b.lit(1))),
    }, null);
    const outer = b.block(&.{
        b.assign("x", b.lit(12345)),
        b.assign("i", b.lit(0)),
        .{ .while_loop = .{ .loc = Loc, .cond = b.bin(.lt, b.nm("i"), b.lit(999)), .body = body } },
    }, b.nm("x"));
    const path = b.a().alloc([]const u8, 1) catch unreachable;
    path[0] = "main";
    const fd = ast.FuncDecl{
        .loc = Loc,
        .path = path,
        .method = false,
        .is_local = false,
        .func = .{
            .loc = Loc,
            .params = &.{},
            .vararg = false,
            .ret_type = .{ .named = "i64" },
            .body = outer,
        },
    };
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{});
    switch (r) {
        .refused => return error.TestUnexpectedResult,
        .closed => |o| try testing.expectEqual(@as(i64, (12345 & 240) & 0xff), o.value),
    }
}

test "obseq: §43 — the retention budget is structural, and overflow REFUSES" {
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 20000000);
    // A budget of two steps cannot hold a five-step orbit. The answer is a
    // refusal, never a truncated closure.
    const r = try closeRelation(testing.allocator, &fd, null, null, observation.ordinary_executable, .{ .max_steps = 2 });
    switch (r) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expectEqual(Refusal.budget, x.refusal),
    }
}

test "obseq: the transform rewrites the entry body and nothing else" {
    var b = Build.init();
    defer b.deinit();
    const fd = w6Decl(&b, 20000000);
    const stmts = b.a().alloc(ast.Stmt, 1) catch unreachable;
    stmts[0] = .{ .func_decl = fd };
    var mod = ast.Module{ .file = "t", .body = b.block(stmts, null) };
    const out = (try applyToEntry(b.a(), &mod, null, observation.ordinary_executable)).?;
    try testing.expectEqual(@as(i64, @intCast(w6Oracle(20000000) & 0xff)), out.value);
    const after = &mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(usize, 0), after.stmts.len);
    try testing.expect(after.tail_expr != null);
    try testing.expectEqual(out.value, after.tail_expr.?.int_lit.val);
}

// ═══════════════════════════════════════════════════════════════════════════
// THE COMPOSITION — a loop whose body applies a relation nobody listed
//
// Every test below FAILS on this file without `Machine.env` and its `build`
// arm: the grammar has no `call`, so the body refuses and `applyToEntry`
// answers null. They are the executable form of the report's headline number.
// ═══════════════════════════════════════════════════════════════════════════

const CLexer = @import("lexer.zig").Lexer;
const CParser = @import("parser.zig").Parser;

const Composed = struct {
    arena: std.heap.ArenaAllocator,
    mod: ast.Module,
    fn deinit(self: *Composed) void {
        self.arena.deinit();
    }
};

fn compose(src: []const u8) !Composed {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const owned = try alloc.dupe(u8, src);
    var lex = CLexer.init(owned, "obseq_compose_test.id");
    var p = CParser.init(&lex, alloc);
    p.idol_mode = true;
    const mod = try p.parse_module();
    return .{ .arena = arena, .mod = mod };
}

fn mainOf(mod: *const ast.Module) *const ast.FuncDecl {
    for (mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        if (std.mem.eql(u8, s.func_decl.path[0], "main")) return &s.func_decl;
    }
    unreachable;
}

/// The oracle for `step(x) = (x ~ (x*1103515245)) + 12345` iterated — the SAME
/// arithmetic as `w6Oracle`, which is the point: writing the body behind a
/// relation may not change the answer.
fn stepLoopOracle(n: u64) u64 {
    var x: u64 = 12345;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        x = (x ^ (x *% 1103515245)) +% 12345;
    }
    return x;
}

const src_call_body =
    \\step: i64 = (n: i64)
    \\    (n ~ (n * 1103515245)) + 12345
    \\
    \\main: i64 = ()
    \\    x = 12345
    \\    i = 0
    \\    while i < 20000000
    \\        x = step(x)
    \\        i = i + 1
    \\    x
;

test "obseq: a loop body that APPLIES a user relation closes to a fixed point" {
    var fx = try compose(src_call_body);
    defer fx.deinit();
    const fd = mainOf(&fx.mod);

    // WITHOUT the relation table — this module exactly as it shipped.
    switch (try closeRelation(testing.allocator, fd, null, null, observation.ordinary_executable, .{})) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expectEqual(Refusal.body_not_admitted, x.refusal),
    }

    // WITH it. The answer is checked against a loop run for real in Zig, not
    // against this module's own algebra.
    const r = try closeRelation(testing.allocator, fd, &fx.mod, null, observation.ordinary_executable, .{});
    const out = switch (r) {
        .refused => return error.TestUnexpectedResult,
        .closed => |o| o,
    };
    try testing.expectEqual(@as(i64, @intCast(stepLoopOracle(20000000) & 0xff)), out.value);
    try testing.expectEqual(@as(i64, @intCast(w6Oracle(20000000) & 0xff)), out.value);
    try testing.expectEqual(Family.fixed_point, out.family);
    try testing.expect(out.census.calls_admitted > 0);
    // D3 STILL FIRES THROUGH THE CALL. `mentions` answering TRUE for every
    // call would have kept `i` in the key; the admitted callee reads its
    // arguments and nothing else, so `i` is deleted and the orbit is a fixed
    // point rather than a 256-cycle.
    try testing.expectEqual(@as(u8, 1), out.census.slots_deleted);
    try testing.expectEqual(@as(u32, 1), out.census.lambda);
}

test "obseq: the closed value is right at EVERY trip count, through the call" {
    var trips: usize = 4;
    while (trips <= 512) : (trips *= 2) {
        var buf: [512]u8 = undefined;
        const src = try std.fmt.bufPrint(&buf,
            \\step: i64 = (n: i64)
            \\    (n ~ (n * 1103515245)) + 12345
            \\
            \\main: i64 = ()
            \\    x = 12345
            \\    i = 0
            \\    while i < {d}
            \\        x = step(x)
            \\        i = i + 1
            \\    x
        , .{trips});
        var fx = try compose(src);
        defer fx.deinit();
        const r = try closeRelation(testing.allocator, mainOf(&fx.mod), &fx.mod, null, observation.ordinary_executable, .{});
        switch (r) {
            .refused => return error.TestUnexpectedResult,
            .closed => |o| try testing.expectEqual(
                @as(i64, @intCast(stepLoopOracle(trips) & 0xff)),
                o.value,
            ),
        }
    }
}

test "obseq: a callee the law refuses leaves the loop alone" {
    // ONE CHARACTER FROM THE WIN. `>>` reads bits ABOVE the quotient, so
    // `demand_projection.lawsOf` carries no `ring_hom_mod_2k` for it, the law
    // derivation refuses, and the call stays opaque. If this ever closes, the
    // admission is UNSOUND rather than merely optimistic.
    var fx = try compose(
        \\step: i64 = (n: i64)
        \\    (n ~ (n >> 7)) + 12345
        \\
        \\main: i64 = ()
        \\    x = 12345
        \\    i = 0
        \\    while i < 20000000
        \\        x = step(x)
        \\        i = i + 1
        \\    x
    );
    defer fx.deinit();
    switch (try closeRelation(testing.allocator, mainOf(&fx.mod), &fx.mod, null, observation.ordinary_executable, .{})) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expectEqual(Refusal.body_not_admitted, x.refusal),
    }
}

test "obseq: an EFFECT in the callee leaves the loop alone" {
    var fx = try compose(
        \\step: i64 = (n: i64)
        \\    print(n)
        \\    n + 1
        \\
        \\main: i64 = ()
        \\    x = 12345
        \\    i = 0
        \\    while i < 20000000
        \\        x = step(x)
        \\        i = i + 1
        \\    x
    );
    defer fx.deinit();
    switch (try closeRelation(testing.allocator, mainOf(&fx.mod), &fx.mod, null, observation.ordinary_executable, .{})) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expectEqual(Refusal.body_not_admitted, x.refusal),
    }
}

test "obseq: a REBOUND callee name is not a relation" {
    // `step` is also assigned inside `main`, so R1 refuses to resolve it and
    // the call stays opaque. A rebindable name is a place, and this module
    // cannot bound a place's writers.
    var fx = try compose(
        \\step: i64 = (n: i64)
        \\    (n ~ (n * 1103515245)) + 12345
        \\
        \\main: i64 = ()
        \\    x = 12345
        \\    i = 0
        \\    step = 3
        \\    while i < 20000000
        \\        x = step(x)
        \\        i = i + 1
        \\    x
    );
    defer fx.deinit();
    switch (try closeRelation(testing.allocator, mainOf(&fx.mod), &fx.mod, null, observation.ordinary_executable, .{})) {
        .closed => return error.TestUnexpectedResult,
        .refused => |x| try testing.expect(x.refusal != .disagreement),
    }
}

/// The `pair` shape with `b * ca` written as `mix(b)`. Its contracted orbit is
/// PERIODIC, so the fixed-point family cannot answer and the decision falls to
/// the DELEGATED exact-index closure in `recurrence.zig` — which is the other
/// half of the composition and the half that needs the routed patch.
const src_pair_call =
    \\mix: i64 = (n: i64)
    \\    n * 1103515245
    \\
    \\main: i64 = ()
    \\    a = 12345
    \\    b = 6789
    \\    i = 0
    \\    while i < 20000000
    \\        a = a ~ mix(b)
    \\        b = b + (a * 6364136223)
    \\        i = i + 1
    \\    a + b
;

test "obseq: a periodic orbit through a call reaches the delegated family" {
    var fx = try compose(src_pair_call);
    defer fx.deinit();
    const r = try closeRelation(testing.allocator, mainOf(&fx.mod), &fx.mod, null, observation.ordinary_executable, .{});
    switch (r) {
        .closed => |o| {
            // Only reachable with `patches/recurrence-contracted-key-and-call.patch`
            // applied: without it `quotientEval` refuses the call and the
            // delegation answers null.
            try testing.expectEqual(@as(i64, @intCast(pairOracle(20000000, 1103515245, 6364136223) & 0xff)), o.value);
            try testing.expectEqual(Family.orbit_index, o.family);
        },
        .refused => |x| {
            // The unrouted tree. A REFUSAL is the correct answer there, and
            // `disagreement` never is: that would mean the two engines
            // computed different values for one loop.
            try testing.expectEqual(Refusal.no_exact_index, x.refusal);
        },
    }
}
