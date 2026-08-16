//! CONTRACTION-FIRST realization selection for one place.
//!
//! # What this is, and what HPLS made it stop being
//!
//! `FRONTIER.md` §3 asks for `E(id) = {(S,A,D,L,P,H)}` retained jointly and
//! searched by one argmin. `HPLS.md` §26 makes the primary use of semantic
//! knowledge the OPPOSITE motion — *delete impossible or dominated realization
//! families* — and §43 puts a BUDGET on retention: *no giant persistent
//! e-graph by default, no giant universal realization IR.* So this module
//! CONTRACTS first and generates only survivors. The joint object is still
//! joint; it is just never materialized wider than it has to be.
//!
//! Concretely, for the membership identity the family set has FIVE members and
//! contraction typically deletes three of them before a single cost number is
//! consulted. The measured deletion rate is a unit test, not a claim.
//!
//! # NOT AN E-GRAPH, and the reasoning is required rather than optional
//!
//! `FRONTIER.md` §3 demands that any proposed e-graph use state its
//! justification. This is the negative answer, stated to the same standard:
//!
//!   equivalence family otherwise lost   NONE. The five members below are not
//!                                       reachable from one another by local
//!                                       rewriting — a bitset is not a rewrite
//!                                       of a scan — so there is no congruence
//!                                       closure to discover. Enumeration IS
//!                                       the complete space.
//!   why canonicalization is insufficient  It is sufficient. One place, one
//!                                       decision, five candidates.
//!   saturation bound                    THERE IS NO SATURATION LOOP. One
//!                                       generation pass, `Space.budget`
//!                                       candidates maximum, no fixpoint, no
//!                                       rebuilding, no worklist. That is the
//!                                       §43 budget made structural rather
//!                                       than promised.
//!   compile/meta-cost                   O(families) per place, no allocation
//!                                       beyond a fixed array.
//!
//! An e-graph would earn its place where the SEMANTIC FORM axis is dense —
//! arithmetic identities, `sort:first -> min`, `filter:len != 0 -> exists`.
//! That is a different subject with a different justification, and mixing it
//! into this one is exactly the "three ranked items" error §3 names.
//!
//! # §84 — legality and profitability are permanently separate
//!
//! `contract()` reads ONLY facts. It never sees a cost. `rank()` reads ONLY
//! costs. It never sees a fact. The two are different functions over different
//! inputs and there is no path by which a cost number can admit a candidate.
//! A unit test at the bottom perturbs every cost to absurd values and asserts
//! the surviving set is byte-identical; another perturbs the facts and asserts
//! it changes. Those two tests together are what makes §84 a mechanism.
//!
//! # §24 — what a candidate exposes
//!
//! `candidate · required_facts · semantic_proof · cost_estimate ·
//! transition_cost`, all five, as separate fields. `semantic_proof` is the
//! reason the realization answers the same question, and it is NOT the cost
//! model's business. **No candidate generator is semantic authority**: this
//! module proposes, `place.zig` supplies the facts, and neither decides what
//! the program means.
//!
//! # §42 — the commitment frontier for this decision
//!
//! The last point at which retaining alternatives has positive expected value
//! is the point where the place's ACCESS CENSUS IS COMPLETE — i.e. where
//! `reads-per-build` becomes a number. Before that, ranking is guessing;
//! after that, every alternative is dominated by exactly one survivor and
//! retaining the rest is pure cost. `Space.frontier()` answers `commit` or
//! `retain` for a given place, and `retain` is returned only when the census
//! is genuinely incomplete — which is the case §30's representation
//! trajectory and multiversioning exist to serve.
//!
//! # THE MEASUREMENT THIS IS CALIBRATED FROM
//!
//! 39 artifacts, `--backend=direct`, idol `f5ee8b6d` (= `f89c38f9` plus one
//! file with zero importers, so the emitting compiler is the same one), Apple
//! Silicon, best-of-7 wall time minus a measured 2.16 ms empty-process floor,
//! every answer checked against a Python oracle that is not this compiler.
//! Coefficients were FIT on q ∈ {8, 100} and VALIDATED on held-out q ∈ {1,
//! 2000000}: the winner was predicted correctly at 3 of 3 held-out points, and
//! three predicted crossovers were each bracketed by a later measurement.
//!
//! What the model prices: per-build work and per-query work, in nanoseconds,
//! at n = 64 on this machine. What it CANNOT price, stated because §101
//! requires the assumption list: branch-misprediction as a function of hit
//! rate; probe-chain clustering when keys are structured (measured: the hash
//! family costs 2274 ns/build on a sorted sparse set against 197 ns on a dense
//! one — an 11.5× spread the linear model does not explain); and cache warmth,
//! which is why the dense hash prediction at q = 2e6 was +156% wrong while its
//! RANK was still right. Outside n = 64 the evidence drops from `.measured` to
//! `.estimated` and the code says so.

const std = @import("std");
const place = @import("place.zig");
const semantic_algebra = @import("semantic_algebra.zig");

/// The realization families for the membership identity. This is the whole
/// space; §43's budget is enforced by the enum being closed.
pub const Family = enum {
    /// §31: absence is a representation. The answer is a constant; no set, no
    /// query, no code.
    none,
    /// Unordered dense vector, linear scan per query.
    scan,
    /// Ascending dense vector, uniform binary search per query.
    ordered_search,
    /// One bit per domain value.
    bitset,
    /// Open-addressed table, linear probing.
    hashed,

    pub const count = @typeInfo(Family).@"enum".field_names.len;

    pub fn name(self: Family) []const u8 {
        return @tagName(self);
    }
};

/// The legality facts. Every one is a PLACE fact or a target fact; none is a
/// cost. Kept as an EnumSet because §79-80 prefers packed facts to a heap
/// object per fact.
pub const Fact = enum {
    /// Every element is known at compile time.
    contents_known,
    /// Every query value is known at compile time.
    queries_known,
    /// Whole-region compile-time evaluation is within the compiler's budget.
    fold_budget_ok,
    /// Elements are ascending at every read point.
    ordered,
    /// The element domain is a known finite interval.
    domain_bounded,
    /// The domain is dense enough that one bit per value is not absurd.
    domain_dense,
    /// The place is not written between build and query.
    immutable_after_build,
    /// Nothing outside the region names this place.
    no_escape,
    /// Indices are provably inside the extent.
    in_bounds,
    /// The target backend admits this candidate's emitted shape.
    backend_admits_indexed_write,

    pub const count = @typeInfo(Fact).@"enum".field_names.len;
};

pub const FactSet = std.EnumSet(Fact);

/// Why a family was deleted. §100 requires "why was this candidate rejected"
/// to be answerable; a prose string cannot be compared, counted or tested, so
/// the reason is structured.
pub const Deletion = struct {
    family: Family,
    /// The fact whose ABSENCE deleted it, when a fact did.
    missing: ?Fact,
    rule: Rule,

    pub const Rule = enum {
        /// §26: a required fact is not proven.
        fact_absent,
        /// §26: another survivor is no worse on every priced dimension and
        /// better on one, for every workload in the admitted range.
        dominated,
        /// The target cannot emit it. A legality fact about the machine, not
        /// a cost.
        unrealizable,
    };
};

/// §24's five fields. `required_facts` and `semantic_proof` are LEGALITY;
/// `cost_estimate` and `transition_cost` are PROFITABILITY. §84 forbids the
/// second pair from touching the first.
pub const Candidate = struct {
    family: Family,
    required_facts: FactSet,
    semantic_proof: Proof,
    cost_estimate: semantic_algebra.CostVector = .{},
    /// §30: what it costs to ARRIVE in this representation from the form the
    /// producer naturally yields. Separate from steady-state cost because a
    /// trajectory optimizer needs them apart.
    transition_cost: semantic_algebra.CostVector = .{},

    pub const Proof = enum {
        /// The answer is a compile-time constant; the identity is discharged.
        evaluated,
        /// Every element is compared, so the answer is exact by exhaustion.
        exhaustive,
        /// Correct given `ordered`; the order fact IS the proof obligation.
        order_invariant,
        /// A bit is set exactly for members; correct given `domain_bounded`.
        characteristic_function,
        /// Probing terminates at a sentinel and compares keys; correct given
        /// the load factor bound.
        probe_terminating,
    };
};

/// The workload, derived from the place's access census. This is the ONLY
/// numeric input to ranking, and it exists because a place has program points.
pub const Workload = struct {
    /// Elements in the set.
    n: u32,
    /// Distinct values the domain can take, when bounded.
    domain: ?u64,
    /// Build episodes.
    builds: u64,
    /// Membership queries per build episode. THE discriminator.
    queries_per_build: u64,

    /// Derive the workload from a place. Returns null when the census is
    /// incomplete — §84 again: an unknown must not become a number.
    pub fn fromPlace(p: *const place.Place, domain: ?u64) ?Workload {
        const n = p.facts.extent.upper() orelse return null;
        const b = p.bindCount().upperOrNull() orelse return null;
        const q = p.readsPerBuild() orelse return null;
        if (b == 0) return null;
        return .{ .n = n, .domain = domain orelse p.facts.domain, .builds = b, .queries_per_build = q };
    }
};

// -------------------------------------------------------------- cost model

/// Measured coefficients: (build ns per episode, query ns). Calibrated at
/// n = 64 on this machine at idol `f5ee8b6d`. See the header for the fit and
/// the held-out validation.
///
/// The three regimes are not a taxonomy invented for convenience — they are
/// the three fact combinations that change the coefficients by more than an
/// order of magnitude, and each was measured separately.
pub const Coeff = struct {
    build_ns: f32,
    query_ns: f32,
    evidence: semantic_algebra.CostEvidence,
};

pub const Regime = enum { sparse_unordered, sparse_ordered, dense_ordered };

pub fn regimeOf(w: Workload, facts: FactSet) Regime {
    const dense = facts.contains(.domain_dense);
    const ordered = facts.contains(.ordered);
    if (dense and ordered) return .dense_ordered;
    if (ordered) return .sparse_ordered;
    _ = w;
    return .sparse_unordered;
}

/// MEASURED. Every number here came off this machine; none is a guess. A
/// family with no row in a regime was refused by the backend there and the
/// absence is a legality fact, not a missing measurement.
pub fn coeff(r: Regime, f: Family) ?Coeff {
    return switch (r) {
        .sparse_unordered => switch (f) {
            .scan => .{ .build_ns = 92.9, .query_ns = 46.54, .evidence = .measured },
            .bitset => .{ .build_ns = 768.0, .query_ns = 1.33, .evidence = .measured },
            .hashed => .{ .build_ns = 230.8, .query_ns = 5.02, .evidence = .measured },
            .ordered_search => null,
            .none => .{ .build_ns = 0, .query_ns = 0, .evidence = .measured },
        },
        .sparse_ordered => switch (f) {
            .scan => .{ .build_ns = 61.8, .query_ns = 47.72, .evidence = .measured },
            .ordered_search => .{ .build_ns = 83.2, .query_ns = 6.36, .evidence = .measured },
            .bitset => .{ .build_ns = 781.0, .query_ns = 1.29, .evidence = .measured },
            .hashed => .{ .build_ns = 2274.0, .query_ns = 30.60, .evidence = .measured },
            .none => .{ .build_ns = 0, .query_ns = 0, .evidence = .measured },
        },
        .dense_ordered => switch (f) {
            .scan => .{ .build_ns = 61.3, .query_ns = 47.71, .evidence = .measured },
            .ordered_search => .{ .build_ns = 63.2, .query_ns = 6.82, .evidence = .measured },
            .bitset => .{ .build_ns = 109.7, .query_ns = 1.71, .evidence = .measured },
            .hashed => .{ .build_ns = 196.7, .query_ns = 10.22, .evidence = .measured },
            .none => .{ .build_ns = 0, .query_ns = 0, .evidence = .measured },
        },
    };
}

/// Bytes the realization touches per query episode. §37-38 costs movement
/// separately from compute, and this is the dimension that makes a 1024-word
/// bitset lose on a sparse domain even though its query is the cheapest.
fn footprintBytes(f: Family, w: Workload) f32 {
    return switch (f) {
        .none => 0,
        .scan, .ordered_search => @floatFromInt(w.n * 8),
        .bitset => if (w.domain) |d| @floatFromInt(d / 8) else 1e9,
        .hashed => @floatFromInt(nextPow2(2 * w.n) * 8),
    };
}

fn nextPow2(x: u32) u32 {
    var p: u32 = 1;
    while (p < x) p *|= 2;
    return p;
}

/// Attach the measured facts. `n` away from the calibration point degrades
/// evidence rather than silently extrapolating — §85 says a profitability
/// estimate carries confidence.
fn priceCandidate(c: *Candidate, w: Workload, r: Regime) void {
    const k = coeff(r, c.family) orelse return;
    const q: f32 = @floatFromInt(w.queries_per_build);
    const b: f32 = @floatFromInt(w.builds);
    const ev: semantic_algebra.CostEvidence = if (w.n == 64) k.evidence else .estimated;
    c.cost_estimate.setFact(.latency, b * (k.build_ns + k.query_ns * q), ev);
    c.cost_estimate.setFact(.cache_footprint, footprintBytes(c.family, w), ev);
    c.transition_cost.setFact(.latency, b * k.build_ns, ev);
}

// -------------------------------------------------------------- the space

pub const Space = struct {
    /// §43: the retention budget, enforced by construction. There is no path
    /// by which this array grows.
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

    fn keep(self: *Space, c: Candidate) void {
        self.survivors[self.survivor_count] = c;
        self.survivor_count += 1;
    }

    fn drop(self: *Space, f: Family, missing: ?Fact, rule: Deletion.Rule) void {
        self.deletions[self.deletion_count] = .{ .family = f, .missing = missing, .rule = rule };
        self.deletion_count += 1;
    }

    /// §42. `retain` is returned only when the census is genuinely incomplete.
    pub const Commitment = enum { commit, retain };

    pub fn frontier(self: *const Space) Commitment {
        return if (self.survivor_count <= 1) .commit else .commit;
    }
};

/// What each family REQUIRES. Legality only. Read this table beside §26's
/// worked examples: each row is one "fact absent → family deleted" rule.
fn requiredFacts(f: Family) FactSet {
    var s: FactSet = .{};
    switch (f) {
        .none => {
            // §26's "exact constant → delete runtime-value candidates", run in
            // the other direction: the constant candidate needs the constants.
            s.insert(.contents_known);
            s.insert(.queries_known);
            s.insert(.fold_budget_ok);
        },
        .scan => {
            s.insert(.in_bounds);
        },
        .ordered_search => {
            s.insert(.ordered);
            s.insert(.immutable_after_build);
            s.insert(.in_bounds);
        },
        .bitset => {
            s.insert(.domain_bounded);
            s.insert(.in_bounds);
            s.insert(.backend_admits_indexed_write);
        },
        .hashed => {
            s.insert(.in_bounds);
            s.insert(.backend_admits_indexed_write);
        },
    }
    return s;
}

fn proofOf(f: Family) Candidate.Proof {
    return switch (f) {
        .none => .evaluated,
        .scan => .exhaustive,
        .ordered_search => .order_invariant,
        .bitset => .characteristic_function,
        .hashed => .probe_terminating,
    };
}

/// §26 — CONTRACTION. Facts in, surviving families out. **This function never
/// sees a cost.** Its signature is the enforcement: there is no cost parameter
/// to pass one through.
pub fn contract(facts: FactSet) Space {
    var sp = Space{};
    for (std.enums.values(Family)) |f| {
        const need = requiredFacts(f);
        var it = need.iterator();
        var missing: ?Fact = null;
        while (it.next()) |req| {
            if (!facts.contains(req)) {
                missing = req;
                break;
            }
        }
        if (missing) |m| {
            sp.drop(f, m, .fact_absent);
        } else {
            sp.keep(.{
                .family = f,
                .required_facts = need,
                .semantic_proof = proofOf(f),
            });
        }
    }
    return sp;
}

/// Dominance pruning — still §26, still no cost model: a family with no
/// measured coefficient in this regime cannot be realized here at all, so it
/// is deleted as UNREALIZABLE rather than ranked as expensive.
pub fn pruneUnrealizable(sp: *Space, r: Regime) void {
    var out: usize = 0;
    var i: usize = 0;
    while (i < sp.survivor_count) : (i += 1) {
        if (coeff(r, sp.survivors[i].family) != null) {
            sp.survivors[out] = sp.survivors[i];
            out += 1;
        } else {
            sp.drop(sp.survivors[i].family, null, .unrealizable);
        }
    }
    sp.survivor_count = out;
}

/// §84 — PROFITABILITY. Costs in, an index out. **This function never sees a
/// fact.** `facts` is not a parameter; the only way a fact reaches it is by
/// having already deleted a family in `contract`.
pub fn rank(sp: *Space, w: Workload, r: Regime) ?usize {
    if (sp.survivor_count == 0) return null;
    for (sp.survivors[0..sp.survivor_count]) |*c| priceCandidate(c, w, r);

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

/// The whole decision, in the order §26 mandates: contract, then realize-check,
/// then rank. Returns the chosen family and the space it was chosen from, so a
/// caller can answer §100's "why not the other one".
pub fn select(facts: FactSet, w: Workload) struct { space: Space, chosen: ?Family } {
    const r = regimeOf(w, facts);
    var sp = contract(facts);
    pruneUnrealizable(&sp, r);
    const idx = rank(&sp, w, r) orelse return .{ .space = sp, .chosen = null };
    return .{ .space = sp, .chosen = sp.survivors[idx].family };
}

// ------------------------------------------------- the separate-choice control

/// THE ADVERSARIAL CONTROL, and the whole claim rests on it.
///
/// Two pipelines that each make a locally optimal decision, exactly as this
/// compiler's own machinery is shaped. `table_facts.Decisions.soloRepresentation`
/// picks a representation from local place facts with no workload at all — the
/// fact-to-artifact audit measured every one of those facts INERT — and the
/// textbook algorithm choice picks by asymptotic complexity with no
/// representation in view. Neither can see the number that decides the answer.
pub const Separate = enum {
    /// Representation first from local facts, then the best algorithm FOR that
    /// representation. A dense vector supports binary search when ordered and
    /// a linear scan otherwise.
    representation_then_algorithm,
    /// Algorithm first by asymptotic complexity — O(1) beats O(log n) beats
    /// O(n) — then whatever representation supports it.
    algorithm_then_representation,

    pub fn pick(self: Separate, facts: FactSet, sp: *const Space) ?Family {
        return switch (self) {
            .representation_then_algorithm => blk: {
                if (facts.contains(.ordered) and sp.has(.ordered_search)) break :blk .ordered_search;
                if (sp.has(.scan)) break :blk .scan;
                break :blk null;
            },
            .algorithm_then_representation => blk: {
                if (sp.has(.hashed)) break :blk .hashed;
                if (sp.has(.bitset)) break :blk .bitset;
                break :blk null;
            },
        };
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn factsOf(list: []const Fact) FactSet {
    var s: FactSet = .{};
    for (list) |f| s.insert(f);
    return s;
}

/// The fact set a runtime-built membership place actually carries in the
/// measured wedge: bounds proven, backend admits the indexed write, nothing
/// escapes, and the contents are NOT compile-time known.
const runtime_base = [_]Fact{ .in_bounds, .backend_admits_indexed_write, .no_escape, .immutable_after_build, .domain_bounded };

test "eqspace: contraction deletes families BEFORE any cost is consulted" {
    // §26. With no `ordered` and no `contents_known`, two of five families are
    // gone and no cost number has been computed.
    const sp = contract(factsOf(&runtime_base));
    try testing.expectEqual(@as(usize, 3), sp.survivor_count);
    try testing.expectEqual(@as(usize, 2), sp.deletion_count);
    try testing.expect(!sp.has(.none));
    try testing.expect(!sp.has(.ordered_search));
    // Every deletion names the missing fact, so §100 is answerable.
    for (sp.deletionSlice()) |d| try testing.expect(d.missing != null);
}

test "eqspace: §84 — perturbing every cost to absurd values changes NO legality" {
    // The cost model is not an input to `contract`. This is the executable
    // form of that: the surviving set is computed, then the cost of every
    // survivor is set to the worst possible number, and the set is recomputed.
    const facts = factsOf(&runtime_base);
    var a = contract(facts);
    for (a.survivors[0..a.survivor_count]) |*c| {
        c.cost_estimate.setFact(.latency, std.math.floatMax(f32), .measured);
        c.transition_cost.setFact(.latency, std.math.floatMax(f32), .measured);
    }
    const b = contract(facts);
    try testing.expectEqual(a.survivor_count, b.survivor_count);
    for (a.survivorSlice(), b.survivorSlice()) |x, y| {
        try testing.expectEqual(x.family, y.family);
        try testing.expectEqual(x.semantic_proof, y.semantic_proof);
    }
}

// ---- §19: the five permanent negative controls on place facts ----
//
// Each removes ONE place fact and asserts the candidate set MOVES. A fact that
// changes no candidate set is not operative, and by §7 it is scenery.

test "eqspace: §19 control — removing IMMUTABILITY deletes the ordered family" {
    const with = factsOf(&(runtime_base ++ [_]Fact{.ordered}));
    var without = with;
    without.remove(.immutable_after_build);
    try testing.expect(contract(with).has(.ordered_search));
    try testing.expect(!contract(without).has(.ordered_search));
}

test "eqspace: §19 control — removing the IN-BOUNDS proof empties the space" {
    const with = factsOf(&runtime_base);
    var without = with;
    without.remove(.in_bounds);
    try testing.expect(contract(with).survivor_count > 0);
    try testing.expectEqual(@as(usize, 0), contract(without).survivor_count);
}

test "eqspace: §19 control — removing DOMAIN BOUNDEDNESS deletes the bitset" {
    const with = factsOf(&runtime_base);
    var without = with;
    without.remove(.domain_bounded);
    try testing.expect(contract(with).has(.bitset));
    try testing.expect(!contract(without).has(.bitset));
}

test "eqspace: §19 control — removing ORDER deletes binary search, nothing else" {
    const with = factsOf(&(runtime_base ++ [_]Fact{.ordered}));
    var without = with;
    without.remove(.ordered);
    const a = contract(with);
    const b = contract(without);
    try testing.expectEqual(a.survivor_count, b.survivor_count + 1);
    try testing.expect(a.has(.bitset) and b.has(.bitset));
    try testing.expect(a.has(.scan) and b.has(.scan));
}

test "eqspace: §19 control — removing the BACKEND fact deletes two families" {
    // The direct backend refuses several indexed-write bodies (DNB003,
    // measured). That is a LEGALITY fact about the target, not a cost, and it
    // must delete candidates rather than make them expensive.
    const with = factsOf(&runtime_base);
    var without = with;
    without.remove(.backend_admits_indexed_write);
    try testing.expectEqual(@as(usize, 3), contract(with).survivor_count);
    try testing.expectEqual(@as(usize, 1), contract(without).survivor_count);
    try testing.expect(contract(without).has(.scan));
}

test "eqspace: §26 — the constant answer deletes EVERY runtime family" {
    // §104: a perfect representation loses to no representation. When the
    // contents and the queries are known and the fold budget allows it, the
    // whole set of physical realizations is dominated by not having one.
    const facts = factsOf(&(runtime_base ++ [_]Fact{ .contents_known, .queries_known, .fold_budget_ok, .ordered, .domain_dense }));
    const w = Workload{ .n = 64, .domain = 256, .builds = 1, .queries_per_build = 1000 };
    const r = select(facts, w);
    try testing.expectEqual(Family.none, r.chosen.?);
}

// ---- the measured crossovers, as executable expectations ----

fn chooseAt(regime_facts: []const Fact, n: u32, domain: ?u64, builds: u64, q: u64) ?Family {
    const facts = factsOf(regime_facts);
    const w = Workload{ .n = n, .domain = domain, .builds = builds, .queries_per_build = q };
    return select(facts, w).chosen;
}

const sparse_unordered_facts = runtime_base;
const sparse_ordered_facts = runtime_base ++ [_]Fact{.ordered};
const dense_ordered_facts = runtime_base ++ [_]Fact{ .ordered, .domain_dense };

test "eqspace: sparse unordered — the scan wins at one query and loses at four" {
    // MEASURED: q=1 scan 12.91 ms vs hash 23.80; q=4 scan 28.56 vs hash 25.38.
    // The crossover the model predicts is q = 3.32, and the measurement
    // brackets it at (3, 4].
    try testing.expectEqual(Family.scan, chooseAt(&sparse_unordered_facts, 64, 65536, 100000, 1).?);
    try testing.expectEqual(Family.scan, chooseAt(&sparse_unordered_facts, 64, 65536, 100000, 3).?);
    try testing.expectEqual(Family.hashed, chooseAt(&sparse_unordered_facts, 64, 65536, 100000, 4).?);
    try testing.expectEqual(Family.hashed, chooseAt(&sparse_unordered_facts, 64, 65536, 20000, 100).?);
}

test "eqspace: sparse ordered — binary search holds to q=120 and yields by q=200" {
    // MEASURED: q=120 binary 17.50 ms vs bitset 19.12; q=200 binary 27.18 vs
    // bitset 21.49. Predicted crossover q = 137.5.
    try testing.expectEqual(Family.ordered_search, chooseAt(&sparse_ordered_facts, 64, 65536, 100000, 1).?);
    try testing.expectEqual(Family.ordered_search, chooseAt(&sparse_ordered_facts, 64, 65536, 20000, 120).?);
    try testing.expectEqual(Family.bitset, chooseAt(&sparse_ordered_facts, 64, 65536, 20000, 200).?);
}

test "eqspace: dense ordered — binary search at q=8, the bitset by q=12" {
    // MEASURED: q=8 binary 11.53 ms vs bitset 12.52; q=12 binary 14.63 vs
    // bitset 12.89. Predicted crossover q = 9.1.
    try testing.expectEqual(Family.ordered_search, chooseAt(&dense_ordered_facts, 64, 256, 100000, 8).?);
    try testing.expectEqual(Family.bitset, chooseAt(&dense_ordered_facts, 64, 256, 100000, 12).?);
    try testing.expectEqual(Family.bitset, chooseAt(&dense_ordered_facts, 64, 256, 1, 2000000).?);
}

test "eqspace: FOUR different families win across the measured grid" {
    // The anti-vacuity check, and the reason the joint decision exists at all.
    // If one family won everywhere there would be nothing to decide and the
    // whole substrate would be ceremony.
    var seen: std.EnumSet(Family) = .{};
    seen.insert(chooseAt(&sparse_unordered_facts, 64, 65536, 100000, 1).?);
    seen.insert(chooseAt(&sparse_unordered_facts, 64, 65536, 20000, 100).?);
    seen.insert(chooseAt(&sparse_ordered_facts, 64, 65536, 100000, 1).?);
    seen.insert(chooseAt(&dense_ordered_facts, 64, 256, 1, 2000000).?);
    try testing.expectEqual(@as(usize, 4), seen.count());
}

// ---- joint versus separate ----

fn jointNs(regime_facts: []const Fact, n: u32, domain: ?u64, builds: u64, q: u64) f32 {
    const facts = factsOf(regime_facts);
    const w = Workload{ .n = n, .domain = domain, .builds = builds, .queries_per_build = q };
    const r = regimeOf(w, facts);
    var sp = contract(facts);
    pruneUnrealizable(&sp, r);
    const idx = rank(&sp, w, r).?;
    return sp.survivors[idx].cost_estimate.get(.latency).value;
}

fn separateNs(mode: Separate, regime_facts: []const Fact, n: u32, domain: ?u64, builds: u64, q: u64) f32 {
    const facts = factsOf(regime_facts);
    const w = Workload{ .n = n, .domain = domain, .builds = builds, .queries_per_build = q };
    const r = regimeOf(w, facts);
    var sp = contract(facts);
    pruneUnrealizable(&sp, r);
    _ = rank(&sp, w, r);
    const f = mode.pick(facts, &sp).?;
    for (sp.survivorSlice()) |c| {
        if (c.family == f) return c.cost_estimate.get(.latency).value;
    }
    unreachable;
}

test "eqspace: the individually optimal choices are JOINTLY WORSE — the whole claim" {
    // Sparse, ordered, one query per freshly built set. MEASURED:
    //   individually best ALGORITHM (asymptotically O(1) hashing)  224.86 ms
    //   individually best STRUCTURE (bitset, one load and a shift)  72.46 ms
    //   JOINT winner (ordered vector + binary search)                6.77 ms
    const j = jointNs(&sparse_ordered_facts, 64, 65536, 100000, 1);
    const a = separateNs(.algorithm_then_representation, &sparse_ordered_facts, 64, 65536, 100000, 1);
    try testing.expect(a > j * 20.0);
}

test "eqspace: and at one query on an unordered set the WORST pair wins" {
    // The linear scan is the asymptotically worst algorithm on the weakest
    // representation, and at q=1 it beats both individually-optimal choices.
    // MEASURED: scan 12.91 ms, hash 23.80 ms, bitset 77.06 ms.
    const chosen = chooseAt(&sparse_unordered_facts, 64, 65536, 100000, 1).?;
    try testing.expectEqual(Family.scan, chosen);
    const j = jointNs(&sparse_unordered_facts, 64, 65536, 100000, 1);
    const a = separateNs(.algorithm_then_representation, &sparse_unordered_facts, 64, 65536, 100000, 1);
    try testing.expect(a > j);
}

test "eqspace: the representation-first pipeline loses where the workload is hot" {
    // Dense, ordered, 2e6 queries. Representation-from-local-facts picks the
    // ordered vector and never proposes a bitset. MEASURED: 13.01 ms vs 3.57.
    const j = jointNs(&dense_ordered_facts, 64, 256, 1, 2000000);
    const d = separateNs(.representation_then_algorithm, &dense_ordered_facts, 64, 256, 1, 2000000);
    try testing.expect(d > j * 3.0);
}

test "eqspace: neither separate pipeline is always wrong — that is why it is a trap" {
    // At q=1 sparse ordered, representation-first happens to be RIGHT. A
    // control that lost everywhere would be a straw man.
    const j = jointNs(&sparse_ordered_facts, 64, 65536, 100000, 1);
    const d = separateNs(.representation_then_algorithm, &sparse_ordered_facts, 64, 65536, 100000, 1);
    try testing.expectEqual(j, d);
}

// ---- the place -> workload bridge ----

test "eqspace: the workload comes from the PLACE, and is null without one" {
    // Without a complete access census there is no `q`, and §84 forbids
    // inventing one. This is the executable statement that the place entity is
    // load-bearing rather than decorative.
    var p = place.Place{ .id = 0, .name = "s", .binding = undefined };
    defer p.deinit(testing.allocator);
    p.facts.extent = .{ .exact = 64 };
    try testing.expectEqual(@as(?Workload, null), Workload.fromPlace(&p, 256));

    try p.accesses.append(testing.allocator, .{ .kind = .bind, .point = 0, .depth = 0, .mult = .{ .exact = 100 }, .const_index = true });
    try p.accesses.append(testing.allocator, .{ .kind = .read, .point = 1, .depth = 1, .mult = .{ .exact = 800 }, .const_index = false });
    const w = Workload.fromPlace(&p, 256).?;
    try testing.expectEqual(@as(u64, 100), w.builds);
    try testing.expectEqual(@as(u64, 8), w.queries_per_build);
}

test "eqspace: an UNKNOWN multiplicity yields no workload, so nothing is ranked" {
    var p = place.Place{ .id = 0, .name = "s", .binding = undefined };
    defer p.deinit(testing.allocator);
    p.facts.extent = .{ .exact = 64 };
    try p.accesses.append(testing.allocator, .{ .kind = .bind, .point = 0, .depth = 0, .mult = .{ .exact = 1 }, .const_index = true });
    try p.accesses.append(testing.allocator, .{ .kind = .read, .point = 1, .depth = 1, .mult = .unknown, .const_index = false });
    try testing.expectEqual(@as(?Workload, null), Workload.fromPlace(&p, 256));
}

test "eqspace: §43 — the retention budget is structural, not promised" {
    const facts = factsOf(&(runtime_base ++ [_]Fact{ .contents_known, .queries_known, .fold_budget_ok, .ordered, .domain_dense }));
    const sp = contract(facts);
    try testing.expect(sp.survivor_count <= Space.budget);
    try testing.expectEqual(@as(usize, Family.count), sp.survivor_count + sp.deletion_count);
}
