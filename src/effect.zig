//! GAP-182: runtime guards as semantic experiments — the effect-side fact family.
//!
//! One mechanism models inline caches, type/shape/version guards, branch
//! profiling, and hardware counters: observe proposition `P` at runtime, refine
//! semantic knowledge, unlock a conditional realization. This file owns the
//! fact shapes and the epistemic taxonomy only — no graph, no emission, no
//! deopt subsystem. `src/assumption_guard.zig` owns the guard emission against
//! the semantic graph; this file owns the fact identities that make a guard an
//! experiment rather than a tag.
//!
//! Law: `law.semantic.universe` … `law.algebra.absolute` epistemic levels are
//! facts with provenance, not booleans; `law.oracle.bounded` bounds profile
//! truth; `law.evidence.subject.one` requires the measured subject revision to
//! travel with the evidence. No catalog of assumptions lives here
//! (`law.catalog.zero`); an `Experiment` is one conditional theorem.

const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");
const assumption_guard = @import("assumption_guard.zig");

pub const SCHEMA_VERSION = "gap182-experiment-v1";

/// Epistemic category of a runtime-observed proposition. Profile and sample
/// evidence are evidence only — they never justify a semantics-changing
/// realization without a guard or a proof (`law.oracle.bounded`).
pub const EpistemicLevel = enum(u8) {
    axiom,
    proven,
    inferred_sound,
    guarded,
    profiled,
    sampled,
    heuristic,

    pub fn name(self: EpistemicLevel) []const u8 {
        return switch (self) {
            .axiom => "axiom",
            .proven => "proven",
            .inferred_sound => "inferred_sound",
            .guarded => "guarded",
            .profiled => "profiled",
            .sampled => "sampled",
            .heuristic => "heuristic",
        };
    }

    /// The sole authority over which levels may admit a semantics-changing
    /// realization without an accompanying guard. Sound levels do; evidence
    /// levels never do.
    pub fn admitsWithoutGuard(self: EpistemicLevel) bool {
        return switch (self) {
            .axiom, .proven, .inferred_sound => true,
            .guarded, .profiled, .sampled, .heuristic => false,
        };
    }
};

/// Who produced the evidence for the proposition. A hardware counter is a
/// fact-producer with the same standing as any other evidence producer.
pub const EvidenceProducer = enum(u8) {
    static_proof,
    invariant_inference,
    guard_observation,
    profile_counter,
    hardware_counter,
    sample,
    heuristic_estimate,

    pub fn name(self: EvidenceProducer) []const u8 {
        return switch (self) {
            .static_proof => "static_proof",
            .invariant_inference => "invariant_inference",
            .guard_observation => "guard_observation",
            .profile_counter => "profile_counter",
            .hardware_counter => "hardware_counter",
            .sample => "sample",
            .heuristic_estimate => "heuristic_estimate",
        };
    }

    pub fn level(self: EvidenceProducer) EpistemicLevel {
        return switch (self) {
            .static_proof => .proven,
            .invariant_inference => .inferred_sound,
            .guard_observation => .guarded,
            .profile_counter => .profiled,
            .hardware_counter => .profiled,
            .sample => .sampled,
            .heuristic_estimate => .heuristic,
        };
    }

    /// GAP-182 required order 5: profiles, samples, and hardware counters are
    /// evidence producers — observations of one measured subject on one
    /// revision, never semantic truth. Sound producers (proof, inference)
    /// are not evidence in this sense; guard observations are the guard's
    /// own witness, not aggregate evidence over runs.
    pub fn isEvidence(self: EvidenceProducer) bool {
        return switch (self) {
            .profile_counter, .hardware_counter, .sample, .heuristic_estimate => true,
            .static_proof, .invariant_inference, .guard_observation => false,
        };
    }
};

/// experiment(P) = { proposition, evidence kind, cost, conditional theorem }.
/// The proposition references stable fact identities, not AST text. The
/// conditional theorem is the realization candidate the experiment unlocks.
pub const Experiment = struct {
    /// Stable identity of the observed proposition, e.g. "shape:42".
    proposition: []const u8,
    producer: EvidenceProducer,
    /// Observation cost in the unit the producer measures (cycles, samples,
    /// bytes). Zero means the observation is free at the boundary — lawful
    /// nonexecution (`law.realization.contract` demands-quotient scope).
    cost: u32,
    /// Stable identity of the realization candidate admitted iff P holds.
    conditional_theorem: []const u8,
    /// The exact measured subject revision (`law.evidence.subject.one`):
    /// every evidence producer must name the revision its observations were
    /// taken on, separately from the artifact revision itself. Empty means no
    /// revision travels with the fact — lawful only for sound producers whose
    /// theorem does not depend on any measurement.
    subject_revision: []const u8 = "",

    /// A sound experiment (proof-derived) stays admissible when invalidated —
    /// the theorem did not depend on the observation. Evidence-level
    /// experiments admit their candidate only while P still holds.
    pub fn admissible(self: *const Experiment, invalidated: bool) bool {
        if (self.producer.level().admitsWithoutGuard()) return true;
        return !invalidated;
    }

    /// Required order 5: evidence is evidence only. No producer of
    /// evidence-level standing ever produces semantic truth; only sound
    /// levels make a statement about the semantics regardless of measurement.
    pub fn producesTruth(self: *const Experiment) bool {
        return self.producer.level().admitsWithoutGuard();
    }

    /// Provenance is complete iff every evidence producer names the measured
    /// subject revision. Sound producers may omit it; evidence producers
    /// (`isEvidence`) may not. This is the executable face of
    /// `law.evidence.subject.one` on the experiment fact family.
    pub fn provenanceComplete(self: *const Experiment) bool {
        if (!self.producer.isEvidence()) return true;
        return self.subject_revision.len > 0;
    }
};

/// Guard invalidation: assumption false ⇒ realization inadmissible. There is
/// no third state; a guarded candidate either still holds or it does not.
pub const Invalidation = struct {
    experiment_proposition: []const u8,
    /// Stable identity of the next candidate selected after invalidation.
    fallback_candidate: []const u8,
    /// The measured subject revision on which the invalidating observation
    /// was taken (`law.evidence.subject.one`) — separate from the artifact
    /// revision; never implicit "at HEAD" provenance.
    subject_revision: []const u8 = "",
};

/// A guarded realization candidate: one experiment plus the stated
/// assumptions under which its conditional theorem is admissible. The
/// experiment's own proposition is an implicit assumption; `assumptions`
/// carries every additional stated assumption identity. A guard is a
/// conditional witness (`law.guard`): it admisses nothing by itself.
pub const Guarded = struct {
    experiment: Experiment,
    /// Stated assumption proposition identities beyond the experiment's own
    /// proposition. Empty means the experiment proposition is the only
    /// assumption.
    assumptions: []const []const u8 = &.{},

    /// Admissible iff every stated assumption currently holds AND the
    /// experiment is admissible under invalidation state. `assumption_holds`
    /// is the current world qualification of each assumption — the caller
    /// (graph/deopt layer) supplies runtime truth; this file owns no clock
    /// and no observation loop.
    pub fn admissible(
        self: *const Guarded,
        invalidated: bool,
        assumption_holds: *const fn (proposition: []const u8) bool,
    ) bool {
        if (!self.experiment.admissible(invalidated)) return false;
        if (!assumption_holds(self.experiment.proposition)) return false;
        for (self.assumptions) |a| {
            if (!assumption_holds(a)) return false;
        }
        return true;
    }
};

/// Deopt candidate selection after an invalidation: the proposition that
/// became false names the experiment whose guarded candidates are now
/// inadmissible. Select the first remaining admissible candidate's
/// conditional theorem; deopt picks the next candidate, never a stalled one.
pub fn select(
    candidates: []const Guarded,
    false_proposition: []const u8,
    assumption_holds: *const fn (proposition: []const u8) bool,
) ?[]const u8 {
    for (candidates) |*c| {
        const invalidated = std.mem.eql(u8, c.experiment.proposition, false_proposition);
        if (c.admissible(invalidated, assumption_holds)) {
            return c.experiment.conditional_theorem;
        }
    }
    return null;
}

/// Convenience for the single-invalidation boundary: when no candidate
/// remains admissible, deopt falls back to the invalidation's recorded
/// fallback candidate — explicit, never a sentinel value in-band.
pub fn deoptOrFallback(
    invalidation: Invalidation,
    candidates: []const Guarded,
    assumption_holds: *const fn (proposition: []const u8) bool,
) []const u8 {
    return select(candidates, invalidation.experiment_proposition, assumption_holds) orelse invalidation.fallback_candidate;
}

/// Whether profile-shaped evidence is ever sufficient on its own for a
/// semantics-changing optimization. The answer is always no; this exists so
/// callers route through the fact instead of re-deriving it.
pub fn profileNeedsGuard(level: EpistemicLevel) bool {
    return !level.admitsWithoutGuard();
}

/// Bridge to the existing guard-emission taxonomy: map an emitted guard onto
/// its epistemic level. `proven` alone is sound. `measured` is an observation
/// of one subject on one revision — evidence only, never semantic truth
/// (`law.oracle.bounded`, GAP-182 required order 5); it maps to the evidence
/// level `profiled` and therefore still demands a guard or a proof before any
/// semantics-changing realization may rely on it. `assumed` / `estimated`
/// carry no witness at all and map to `heuristic`.
pub fn levelForOutcomeEvidence(ev: optimization_outcome.Evidence) EpistemicLevel {
    return switch (ev) {
        .proven => .proven,
        .measured => .profiled,
        .guarded => .guarded,
        .assumed => .heuristic,
        .profiled => .profiled,
        .estimated => .heuristic,
    };
}

/// Bridge to the existing guard-emission taxonomy: map an emitted guard's
/// evidence strength onto the producer that stands behind it. `proven` is a
/// static proof; `guarded` is the guard's own observation witness; `measured`
/// and `profiled` are profile/counter observations of one measured subject on
/// one revision (`law.evidence.subject.one`); `assumed` / `estimated` are
/// heuristic estimates with no witness. The level bridge above must be
/// exactly `producerForOutcomeEvidence(ev).level()` — one taxonomy, two
/// faces, no drift.
pub fn producerForOutcomeEvidence(ev: optimization_outcome.Evidence) EvidenceProducer {
    return switch (ev) {
        .proven => .static_proof,
        .measured => .profile_counter,
        .guarded => .guard_observation,
        .assumed => .heuristic_estimate,
        .profiled => .profile_counter,
        .estimated => .heuristic_estimate,
    };
}

/// The cost of realizing zero when an experiment's own observation cost is
/// zero: `P` answers from realized state rather than from execution. Zero-cost
/// observation is lawful nonexecution (`law.realization.contract` — cached,
/// theorem, or materialized answers are admissible candidate strategies), not
/// an optimization hint.
pub fn realizesZero(e: *const Experiment) bool {
    return e.cost == 0;
}

/// Required order 2: semantic probability and compiler epistemic probability
/// are distinct categories that must never be confused.
///
/// A SEMANTIC probability is a fact about the SUBJECT: the measured
/// distribution over runtime states at one site on one measured revision
/// (e.g. shape hit counts at a call site). It is selection evidence — it may
/// prefer one already-admissible candidate over another (`law.profile.evidence`:
/// profile data selects realization) and it never rewrites truth, so it can
/// neither promote an inadmissible candidate nor demote an admissible one.
///
/// A COMPILER EPISTEMIC probability is a fact about the compiler's own
/// knowledge — confidence that the fact set is complete — never a fact about
/// the subject. It may order exploration of the realization space
/// (`law.optimizer.economy` meta-cost); it may never enter admissibility,
/// selection, or invalidation. Keeping the two as separate variants with no
/// shared arithmetic is the executable face of the distinction: there is no
/// operation that consumes an epistemic probability as if it were observed
/// subject evidence.
pub const SemanticShare = struct {
    /// Runs in which the proposition held, of `total` measured runs on the
    /// experiment's measured subject revision. `total == 0` is no evidence.
    held: u64,
    total: u64,

    /// Measured fraction in milli-per-unit; no evidence answers zero.
    pub fn milli(self: SemanticShare) u64 {
        if (self.total == 0) return 0;
        return (self.held * 1000) / self.total;
    }
};

/// Preference among admissible candidates from measured semantic shares.
/// `shares[i]` is the measured share of `candidates[i]`'s proposition.
/// Selection law: admissibility is computed EXACTLY as in `select` — the
/// share is consulted only after, only among the survivors. An inadmissible
/// candidate with a maximal share stays inadmissible; an admissible
/// candidate with share zero stays admissible (order, not share, breaks the
/// tie at zero evidence). Returns null when no candidate is admissible —
/// the same answer `select` gives, so `deoptOrFallback` composes verbatim.
pub fn selectPreferred(
    candidates: []const Guarded,
    shares: []const SemanticShare,
    false_proposition: []const u8,
    assumption_holds: *const fn (proposition: []const u8) bool,
) ?[]const u8 {
    std.debug.assert(shares.len >= candidates.len);
    var best: ?usize = null;
    var best_milli: u64 = 0;
    for (candidates, 0..) |*c, i| {
        const invalidated = invalidatedExperiment(&c.experiment, false_proposition);
        if (!c.admissible(invalidated, assumption_holds)) continue;
        const m = shares[i].milli();
        if (best == null or m > best_milli) {
            best = i;
            best_milli = m;
        }
    }
    return if (best) |i| candidates[i].experiment.conditional_theorem else null;
}

/// Required order 4 witness: deopt selection is exactly a walk of the
/// candidate set under world qualification plus the one recorded
/// invalidation. Callers supply the current truth of each proposition; this
/// function adds no second authority over which propositions hold. It exists
/// so the deopt layer consumes the experiment family through one seam rather
/// than re-deriving admissibility at every boundary.
pub fn invalidatedExperiment(
    e: *const Experiment,
    false_proposition: []const u8,
) bool {
    // Sound experiments (axiom/proven/inferred-sound) are never invalidated by
    // any proposition: their theorem did not depend on the observation.
    if (e.producer.level().admitsWithoutGuard()) return false;
    return std.mem.eql(u8, e.proposition, false_proposition);
}

/// An `Experiment` is the experiment-shaped face of an emitted assumption
/// guard: one experiment plus the assumptions under which its conditional
/// theorem is admissible. This function is the sole bridge that constructs
/// that face — callers must route through it rather than hand-wiring an
/// `Experiment` from guard fields, so the two fact families cannot drift.
/// The assumption's evidence strength selects the producer through the
/// existing producer bridge; the guard face keeps no second epistemic table
/// (`law.catalog.zero`). The measured subject revision carries over verbatim:
/// if the guard face names none, provenance is exactly as complete as the
/// assumption's evidence demands (`law.evidence.subject.one`).
pub fn fromAssumption(
    id: []const u8,
    conditional_theorem: []const u8,
    evidence: optimization_outcome.Evidence,
    cost: u32,
    subject_revision: []const u8,
) Guarded {
    return .{
        .experiment = .{
            .proposition = id,
            .producer = producerForOutcomeEvidence(evidence),
            .cost = cost,
            .conditional_theorem = conditional_theorem,
            .subject_revision = subject_revision,
        },
    };
}

/// Required order 4 executed-graph integration: one deopt boundary from the
/// emitted assumption guard to the experiment fact family. Emitted guards that
/// name a fallback candidate (the recorded realization to select when the
/// guard's proposition becomes false) become `Guarded` candidates in the
/// order given; the deopt walk is `select` plus the first fallback as the
/// explicit no-candidate answer (`deoptOrFallback`). An emitted guard whose
/// fallback is absent contributes nothing: there is no recorded next
/// candidate to select, so no boundary fact exists — never a sentinel
/// in-band and never a second seam around the bridges.
///
/// Allocation-free: the output faces borrow proposition, theorem, and
/// fallback identity slices directly from the caller's assumptions; the
/// caller keeps them alive for the walk.
pub const DeoptBoundary = struct {
    candidates: [max_boundary_candidates]Guarded,
    count: usize,
    /// The first emitted fallback in the input order — the explicit answer
    /// when the invalidation leaves no candidate admissible.
    fallback: []const u8,

    /// One measured invalidation: the proposition that became false selects
    /// the next admissible candidate's conditional theorem, or the recorded
    /// fallback when none survives. The measured subject revision (`subject`)
    /// travels with the invalidation so the boundary satisfies
    /// `law.evidence.subject.one` — the observation was taken on exactly
    /// that revision, never "at HEAD". Sound candidates are untouched by any
    /// invalidation inside `select`; evidence-level candidates whose
    /// proposition is the false one cease to be admissible.
    pub fn invalidate(
        self: *const DeoptBoundary,
        false_proposition: []const u8,
        subject: []const u8,
        assumption_holds: *const fn (proposition: []const u8) bool,
    ) []const u8 {
        return deoptOrFallback(.{
            .experiment_proposition = false_proposition,
            .fallback_candidate = self.fallback,
            .subject_revision = subject,
        }, self.live(), assumption_holds);
    }

    fn live(self: *const DeoptBoundary) []const Guarded {
        return self.candidates[0..self.count];
    }
};

pub const max_boundary_candidates = 8;

pub fn deoptBoundary(
    assumptions: []const assumption_guard.Assumption,
    conditional_theorems: []const []const u8,
    subject_revision: []const u8,
) DeoptBoundary {
    var boundary = DeoptBoundary{
        .candidates = undefined,
        .count = 0,
        .fallback = "",
    };
    for (assumptions, 0..) |*a, i| {
        const fallback = a.fallback orelse continue;
        if (boundary.count == max_boundary_candidates) break;
        if (boundary.count == 0) boundary.fallback = fallback;
        boundary.candidates[boundary.count] = fromAssumption(
            a.id,
            conditional_theorems[i],
            a.evidence,
            0,
            subject_revision,
        );
        boundary.count += 1;
    }
    return boundary;
}

test "effect: epistemic levels admit or require guard" {
    try std.testing.expect(EpistemicLevel.axiom.admitsWithoutGuard());
    try std.testing.expect(EpistemicLevel.proven.admitsWithoutGuard());
    try std.testing.expect(EpistemicLevel.inferred_sound.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.guarded.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.profiled.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.sampled.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.heuristic.admitsWithoutGuard());
}

test "effect: producers map to their epistemic level" {
    try std.testing.expectEqual(EpistemicLevel.proven, EvidenceProducer.static_proof.level());
    try std.testing.expectEqual(EpistemicLevel.inferred_sound, EvidenceProducer.invariant_inference.level());
    try std.testing.expectEqual(EpistemicLevel.guarded, EvidenceProducer.guard_observation.level());
    try std.testing.expectEqual(EpistemicLevel.profiled, EvidenceProducer.profile_counter.level());
    try std.testing.expectEqual(EpistemicLevel.profiled, EvidenceProducer.hardware_counter.level());
    try std.testing.expectEqual(EpistemicLevel.sampled, EvidenceProducer.sample.level());
    try std.testing.expectEqual(EpistemicLevel.heuristic, EvidenceProducer.heuristic_estimate.level());
}

test "effect: experiment admissibility follows invalidation and level" {
    const guarded_exp = Experiment{
        .proposition = "shape:7",
        .producer = .guard_observation,
        .cost = 3,
        .conditional_theorem = "cand:sealed-table",
    };
    try std.testing.expect(guarded_exp.admissible(false));
    try std.testing.expect(!guarded_exp.admissible(true));
    const proved_exp = Experiment{
        .proposition = "shape:7",
        .producer = .static_proof,
        .cost = 0,
        .conditional_theorem = "cand:sealed-table",
    };
    try std.testing.expect(proved_exp.admissible(true));
}

fn holdsAll(proposition: []const u8) bool {
    _ = proposition;
    return true;
}

fn holdsOnlyShape(proposition: []const u8) bool {
    return std.mem.eql(u8, proposition, "shape:7");
}

test "effect: guarded realization admissible only under stated assumptions" {
    const guarded_candidate = Guarded{
        .experiment = .{
            .proposition = "shape:7",
            .producer = .guard_observation,
            .cost = 3,
            .conditional_theorem = "cand:sealed-table",
        },
        .assumptions = &.{"version:12"},
    };
    try std.testing.expect(guarded_candidate.admissible(false, &holdsAll));
    // Stated assumption false ⇒ inadmissible even while the guard proposition holds.
    try std.testing.expect(!guarded_candidate.admissible(false, &holdsOnlyShape));
    // Invalidated guard ⇒ inadmissible even with every assumption holding.
    try std.testing.expect(!guarded_candidate.admissible(true, &holdsAll));
}

test "effect: invalidation makes candidate inadmissible and deopt selects another" {
    const first = Guarded{
        .experiment = .{
            .proposition = "shape:7",
            .producer = .guard_observation,
            .cost = 3,
            .conditional_theorem = "cand:mono",
        },
    };
    const next = Guarded{
        .experiment = .{
            .proposition = "kind:packed",
            .producer = .guard_observation,
            .cost = 3,
            .conditional_theorem = "cand:poly",
        },
    };
    const candidates = [_]Guarded{ first, next };
    // While the first assumption holds, the first candidate wins.
    try std.testing.expectEqualStrings("cand:mono", select(&candidates, "shape:never", &holdsAll).?);
    // Assumption false ⇒ first candidate ceases to be admissible; deopt selects the next.
    try std.testing.expectEqualStrings("cand:poly", select(&candidates, "shape:7", &holdsAll).?);
    // Explicit fallback when no candidate survives.
    const invalidation = Invalidation{
        .experiment_proposition = "shape:7",
        .fallback_candidate = "cand:generic",
    };
    const one = [_]Guarded{first};
    try std.testing.expectEqualStrings("cand:generic", deoptOrFallback(invalidation, &one, &holdsAll));
}

test "effect: semantic share selects among admissible, never promotes" {
    // Required order 2 + law.profile.evidence required pattern: measured
    // subject shares select the realization among admissible candidates;
    // they never rewrite admissibility.
    const hot = Guarded{
        .experiment = .{
            .proposition = "shape:7",
            .producer = .guard_observation,
            .cost = 1,
            .conditional_theorem = "cand:mono",
        },
    };
    const cold = Guarded{
        .experiment = .{
            .proposition = "shape:9",
            .producer = .guard_observation,
            .cost = 1,
            .conditional_theorem = "cand:poly",
        },
    };
    const candidates = [_]Guarded{ hot, cold };
    // No evidence: admissibility order alone decides, exactly as `select`.
    const none = [_]SemanticShare{ .{ .held = 0, .total = 0 }, .{ .held = 0, .total = 0 } };
    try std.testing.expectEqualStrings(
        "cand:mono",
        selectPreferred(&candidates, &none, "shape:never", &holdsAll).?,
    );
    // Measured share prefers the second candidate when the first is
    // admissible too: evidence file probability high → specialize,
    // guard and fallback unchanged (semantic truth unchanged).
    const skew = [_]SemanticShare{ .{ .held = 1, .total = 100 }, .{ .held = 99, .total = 100 } };
    try std.testing.expectEqualStrings(
        "cand:poly",
        selectPreferred(&candidates, &skew, "shape:never", &holdsAll).?,
    );
    // A maximal share never promotes an invalidated candidate: the guard's
    // proposition is false, so the hot candidate is inadmissible whatever
    // the profile says; selection falls to the admissible survivor.
    try std.testing.expectEqualStrings(
        "cand:poly",
        selectPreferred(&candidates, &skew, "shape:7", &holdsAll).?,
    );
    // With every candidate inadmissible the answer is null — the same
    // answer `select` gives, so `deoptOrFallback` supplies the fallback.
    const invalidated = Invalidation{
        .experiment_proposition = "shape:never",
        .fallback_candidate = "cand:generic",
    };
    const all_false = struct {
        fn f(proposition: []const u8) bool {
            _ = proposition;
            return false;
        }
    }.f;
    try std.testing.expect(selectPreferred(&candidates, &skew, "shape:never", &all_false) == null);
    try std.testing.expectEqualStrings(
        "cand:generic",
        deoptOrFallback(invalidated, &candidates, &all_false),
    );
    // Shares are subject facts, not compiler confidence: they never touch
    // the candidate's own admissibility — admissible(true) is unchanged by
    // any share, and a measured share carries no epistemic promotion.
    try std.testing.expect(!hot.experiment.admissible(true));
    try std.testing.expect(!hot.experiment.producesTruth());
    try std.testing.expectEqual(@as(u64, 0), (SemanticShare{ .held = 7, .total = 0 }).milli());
    try std.testing.expectEqual(@as(u64, 875), (SemanticShare{ .held = 7, .total = 8 }).milli());
}

test "effect: profile evidence never admits alone" {
    try std.testing.expect(profileNeedsGuard(.profiled));
    try std.testing.expect(profileNeedsGuard(.sampled));
    try std.testing.expect(profileNeedsGuard(.heuristic));
    try std.testing.expect(!profileNeedsGuard(.proven));
}

fn experiment(producer: EvidenceProducer, revision: []const u8) Experiment {
    return .{
        .proposition = "shape:7",
        .producer = producer,
        .cost = 1,
        .conditional_theorem = "cand:x",
        .subject_revision = revision,
    };
}

test "effect: profiles, samples, and hardware counters are evidence producers" {
    // Required order 5: these producers are evidence, never semantic truth.
    const evidence_producers = [_]EvidenceProducer{ .profile_counter, .hardware_counter, .sample, .heuristic_estimate };
    for (evidence_producers) |p| {
        try std.testing.expect(p.isEvidence());
        try std.testing.expect(!experiment(p, "rev:abc").producesTruth());
    }
    const sound_producers = [_]EvidenceProducer{ .static_proof, .invariant_inference, .guard_observation };
    for (sound_producers) |p| {
        try std.testing.expect(!p.isEvidence());
    }
    // Sound experiments state semantics regardless of measurement.
    try std.testing.expect(experiment(.static_proof, "").producesTruth());
    // But a guarded experiment still cannot admit without its guard.
    try std.testing.expect(!experiment(.guard_observation, "").producesTruth());
}

test "effect: evidence provenance requires the measured subject revision" {
    // law.evidence.subject.one on the experiment fact family: an evidence
    // fact naming no measured subject revision has incomplete provenance.
    try std.testing.expect(!experiment(.profile_counter, "").provenanceComplete());
    try std.testing.expect(!experiment(.hardware_counter, "").provenanceComplete());
    try std.testing.expect(!experiment(.sample, "").provenanceComplete());
    try std.testing.expect(!experiment(.heuristic_estimate, "").provenanceComplete());
    try std.testing.expect(experiment(.profile_counter, "rev:abc").provenanceComplete());
    try std.testing.expect(experiment(.hardware_counter, "rev:abc").provenanceComplete());
    // Sound producers are complete with or without a revision naming.
    try std.testing.expect(experiment(.static_proof, "").provenanceComplete());
    try std.testing.expect(experiment(.guard_observation, "").provenanceComplete());
}

test "effect: measured outcome evidence stays evidence, never truth" {
    // Required order 5 bridge: a measured profile/counter observation on one
    // subject revision is evidence only. Only `proven` admits without a guard.
    try std.testing.expectEqual(EpistemicLevel.proven, levelForOutcomeEvidence(.proven));
    try std.testing.expectEqual(EpistemicLevel.guarded, levelForOutcomeEvidence(.guarded));
    try std.testing.expectEqual(EpistemicLevel.profiled, levelForOutcomeEvidence(.measured));
    try std.testing.expect(!levelForOutcomeEvidence(.measured).admitsWithoutGuard());
}

test "effect: outcome evidence producer bridge agrees with the level bridge" {
    // One taxonomy, two faces: mapping an emitted guard's evidence strength
    // onto its producer and taking that producer's level must equal mapping
    // the evidence strength onto its level directly (`law.catalog.zero` —
    // the bridges are faces of one fact family, not two registries).
    const all = [_]optimization_outcome.Evidence{
        .proven, .guarded, .assumed, .profiled, .estimated, .measured,
    };
    for (all) |ev| {
        try std.testing.expectEqual(
            levelForOutcomeEvidence(ev),
            producerForOutcomeEvidence(ev).level(),
        );
    }
    // Only the proof producer is sound; measured keeps no aggregate standing.
    try std.testing.expectEqual(
        EvidenceProducer.static_proof,
        producerForOutcomeEvidence(.proven),
    );
    try std.testing.expectEqual(
        EvidenceProducer.profile_counter,
        producerForOutcomeEvidence(.measured),
    );
    try std.testing.expectEqual(
        EvidenceProducer.guard_observation,
        producerForOutcomeEvidence(.guarded),
    );
    try std.testing.expect(producerForOutcomeEvidence(.measured).isEvidence());
    try std.testing.expect(!producerForOutcomeEvidence(.measured).level().admitsWithoutGuard());
}

test "effect: no assumption catalog lives here" {
    try std.testing.expect(!@hasDecl(@This(), "catalog"));
    try std.testing.expect(!@hasDecl(@This(), "experiment_catalog"));
    try std.testing.expect(!@hasDecl(@This(), "writeCatalogJson"));
}

test "effect: experiment invalidation is keyed on the proposition alone" {
    // Required order 4: an evidence-level experiment becomes inadmissible only
    // when ITS proposition is the false one; an unrelated false proposition
    // never touches it, and sound experiments are never invalidated at all —
    // their theorem did not depend on the observation.
    const guarded_exp = Experiment{
        .proposition = "shape:7",
        .producer = .guard_observation,
        .cost = 3,
        .conditional_theorem = "cand:mono",
    };
    try std.testing.expect(invalidatedExperiment(&guarded_exp, "shape:7"));
    try std.testing.expect(!invalidatedExperiment(&guarded_exp, "shape:9"));
    const proved_exp = Experiment{
        .proposition = "shape:7",
        .producer = .static_proof,
        .cost = 0,
        .conditional_theorem = "cand:mono",
    };
    try std.testing.expect(!invalidatedExperiment(&proved_exp, "shape:7"));
    // A profiled experiment invalidated by its own proposition admits nothing
    // until re-proven or re-guarded.
    const profiled_exp = Experiment{
        .proposition = "shape:7",
        .producer = .profile_counter,
        .cost = 1,
        .conditional_theorem = "cand:mono",
        .subject_revision = "rev:abc",
    };
    try std.testing.expect(invalidatedExperiment(&profiled_exp, "shape:7"));
    try std.testing.expect(!profiled_exp.admissible(true));
}

test "effect: zero-cost observation is lawful nonexecution, not truth" {
    // law.realization.contract: cost zero means the proposition answers from
    // realized state. It never upgrades the epistemic level — a zero-cost
    // profile is still profiled evidence and still demands a guard or proof.
    const free_profile = Experiment{
        .proposition = "shape:7",
        .producer = .profile_counter,
        .cost = 0,
        .conditional_theorem = "cand:cached",
        .subject_revision = "rev:abc",
    };
    try std.testing.expect(realizesZero(&free_profile));
    try std.testing.expect(!free_profile.producesTruth());
    try std.testing.expect(profileNeedsGuard(free_profile.producer.level()));
    const free_proof = Experiment{
        .proposition = "law:fold",
        .producer = .static_proof,
        .cost = 0,
        .conditional_theorem = "cand:theorem",
    };
    try std.testing.expect(realizesZero(&free_proof));
    try std.testing.expect(free_proof.producesTruth());
    const paid_guard = Experiment{
        .proposition = "shape:7",
        .producer = .guard_observation,
        .cost = 3,
        .conditional_theorem = "cand:mono",
    };
    try std.testing.expect(!realizesZero(&paid_guard));
}

test "effect: graph-emitted guards drive a measured deopt boundary" {
    // Required order 4 integration: the deopt boundary consumes assumptions
    // emitted by `assumption_guard.buildFromModule` from an executed semantic
    // graph — not hand-constructed facts. A guarded shape node emits exactly
    // one assumption whose fallback names the next realization. Measured
    // invalidation of its proposition selects the fallback; invalidating an
    // unrelated proposition keeps the guarded candidate.
    const sema = @import("sema.zig");
    const ast = @import("ast.zig");
    const semantic_graph = @import("semantic_graph.zig");
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "boundary.id", .start = 0, .end = 0 },
    });
    const shape = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "boundary.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    var dummy_mod: ast.Module = undefined;
    var dummy_sem = sema.Sema.init(std.testing.allocator);
    defer dummy_sem.deinit();
    var emitted = try assumption_guard.buildFromModule(
        std.testing.allocator,
        &dummy_mod,
        &dummy_sem,
        &graph,
    );
    defer emitted.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), emitted.items.len);

    const theorems = [1][]const u8{"cand:sealed-point"};
    var id_buf: [20]u8 = undefined;
    const shape_id = try std.fmt.bufPrint(&id_buf, "guard:{d}", .{shape});
    const boundary = deoptBoundary(emitted.items, &theorems, "rev:boundary");
    try std.testing.expectEqual(@as(usize, 1), boundary.count);
    try std.testing.expectEqualStrings("general table realization", boundary.fallback);

    // Measured invalidation: the proposition that became false is the emitted
    // guard's own; deopt selects the recorded next realization, exactly the
    // assumption's fallback edge — never a sentinel.
    try std.testing.expectEqualStrings(
        "general table realization",
        boundary.invalidate(shape_id, "rev:boundary", &holdsAll),
    );
    // An unrelated false proposition invalidates nothing; the guarded
    // candidate still holds under its assumptions.
    try std.testing.expectEqualStrings(
        "cand:sealed-point",
        boundary.invalidate("shape:elsewhere", "rev:boundary", &holdsAll),
    );
    // An assumption judged false by the world makes the candidate
    // inadmissible even without an invalidation record.
    const none_hold = struct {
        fn f(proposition: []const u8) bool {
            _ = proposition;
            return false;
        }
    }.f;
    try std.testing.expectEqualStrings(
        "general table realization",
        boundary.invalidate("shape:elsewhere", "rev:boundary", &none_hold),
    );
    // Guards that record no fallback contribute no boundary candidate.
    const no_fallback = assumption_guard.Assumption{
        .id = "guard:plain",
        .subject_entity = "0",
        .predicate = .shape_id_matches,
        .origin = .graph_lift,
        .scope = .module,
        .invalidation = null,
        .fallback = null,
        .evidence = .guarded,
    };
    const plain = [1]assumption_guard.Assumption{no_fallback};
    const one_theorem = [1][]const u8{"cand:plain"};
    const empty = deoptBoundary(&plain, &one_theorem, "rev:boundary");
    try std.testing.expectEqual(@as(usize, 0), empty.count);
}

test "effect: fromAssumption is the sole guard-to-experiment face" {
    // One taxonomy, no drift: building the guarded face from an emitted
    // assumption's evidence strength must agree with both bridges, and the
    // face itself is inadmissible once invalidated (required order 4).
    var g = fromAssumption("guard:42", "cand:sealed-table", .guarded, 3, "");
    try std.testing.expectEqualStrings("guard:42", g.experiment.proposition);
    try std.testing.expectEqual(EvidenceProducer.guard_observation, g.experiment.producer);
    try std.testing.expectEqual(levelForOutcomeEvidence(.guarded), g.experiment.producer.level());
    try std.testing.expect(g.admissible(false, &holdsAll));
    try std.testing.expect(!g.admissible(true, &holdsAll));
    // A measured-strength assumption keeps evidence standing: provenance
    // demands its subject revision, and it never produces truth (order 5).
    g = fromAssumption("guard:43", "cand:mono", .measured, 1, "");
    try std.testing.expect(!g.experiment.provenanceComplete());
    g = fromAssumption("guard:43", "cand:mono", .measured, 1, "rev:head");
    try std.testing.expect(g.experiment.provenanceComplete());
    try std.testing.expect(!g.experiment.admissible(true));
    try std.testing.expect(!g.experiment.producesTruth());
    // A proven-strength assumption is admissible regardless of invalidation.
    g = fromAssumption("guard:44", "cand:theorem", .proven, 0, "");
    try std.testing.expect(g.experiment.admissible(true));
    try std.testing.expect(g.experiment.provenanceComplete());
}
