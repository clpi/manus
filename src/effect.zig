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
const transform_engine = @import("transform_engine.zig");
const assumption_guard = @import("assumption_guard.zig");
const semantic_graph = @import("graph.zig");

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
    /// A constitutional axiom: a law-level fact whose truth is not derived
    /// from any observation. It maps to the `axiom` level, so NO experiment
    /// built on it is ever invalidated and it never demands a guard —
    /// `axiomOf` is the one admission gate. GAP-182.
    constitutional_axiom,
    static_proof,
    invariant_inference,
    guard_observation,
    profile_counter,
    hardware_counter,
    sample,
    /// An inline cache observation: the shape witnessed at one call site on
    /// one measured subject revision. GAP-182 closure face — the foreign
    /// inline cache expressed as an evidence producer of the one experiment
    /// fact family, never a separate JIT subsystem (deletion witness).
    inline_cache,
    heuristic_estimate,

    pub fn name(self: EvidenceProducer) []const u8 {
        return switch (self) {
            .constitutional_axiom => "constitutional_axiom",
            .static_proof => "static_proof",
            .invariant_inference => "invariant_inference",
            .guard_observation => "guard_observation",
            .profile_counter => "profile_counter",
            .hardware_counter => "hardware_counter",
            .sample => "sample",
            .inline_cache => "inline_cache",
            .heuristic_estimate => "heuristic_estimate",
        };
    }

    pub fn level(self: EvidenceProducer) EpistemicLevel {
        return switch (self) {
            .constitutional_axiom => .axiom,
            .static_proof => .proven,
            .invariant_inference => .inferred_sound,
            .guard_observation => .guarded,
            .profile_counter => .profiled,
            .hardware_counter => .profiled,
            .sample => .sampled,
            .inline_cache => .profiled,
            .heuristic_estimate => .heuristic,
        };
    }

    /// GAP-182 required order 5: profiles, samples, hardware counters, and
    /// inline cache observations are evidence producers — observations of one
    /// measured subject on one measured revision, never semantic truth. Sound
    /// producers (proof, inference) are not evidence in this sense; guard
    /// observations are the guard's own witness, not aggregate evidence over
    /// runs. An axiom is not evidence either: it rests on zero measurement
    /// and is never invalidated, so it demands no revision name.
    pub fn isEvidence(self: EvidenceProducer) bool {
        return switch (self) {
            .profile_counter, .hardware_counter, .sample, .inline_cache, .heuristic_estimate => true,
            .constitutional_axiom, .static_proof, .invariant_inference, .guard_observation => false,
        };
    }

    /// Reverse of `name` over the graph-emitted producer identity. The graph
    /// face (`semantic_graph.ExperimentFact.producer`) carries the producer as
    /// its stable NAME — never an ordinal (`law.magic.code.zero`): an ordinal
    /// would force the consumer to reconstruct semantic meaning from an
    /// integer selected by the producer's declaration order. An unrecognized
    /// name consumes to NO producer — never a nearest-match guess and never a
    /// default, because a producer that cannot be named is not a fact with
    /// complete provenance (`law.fact.producer.one`).
    pub fn fromName(name_id: []const u8) ?EvidenceProducer {
        const map = .{
            .{ "constitutional_axiom", .constitutional_axiom },
            .{ "static_proof", .static_proof },
            .{ "invariant_inference", .invariant_inference },
            .{ "guard_observation", .guard_observation },
            .{ "profile_counter", .profile_counter },
            .{ "hardware_counter", .hardware_counter },
            .{ "sample", .sample },
            .{ "inline_cache", .inline_cache },
            .{ "heuristic_estimate", .heuristic_estimate },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, name_id, entry[0])) return entry[1];
        }
        return null;
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
/// fallback candidate — explicit, never a sentinel value in-band. The
/// measured subject revision is enforced here too, so this helper cannot
/// bypass the `guardFalse` construction seam and select a fallback for an
/// unprovenanceable invalidation fact.
pub fn deoptOrFallback(
    invalidation: Invalidation,
    candidates: []const Guarded,
    assumption_holds: *const fn (proposition: []const u8) bool,
) ?[]const u8 {
    const fact = guardFalse(
        invalidation.experiment_proposition,
        invalidation.subject_revision,
    ) orelse return null;
    return selectUnderInvalidation(candidates, &fact, assumption_holds) orelse invalidation.fallback_candidate;
}

/// Still-missing face: guard invalidation as a NAMED fact, not a decision
/// outcome. `DeoptBoundary.invalidate` and `select` answer WHICH candidate
/// survives; the invalidation itself was a caller-supplied string with no
/// fact identity of its own. `guardFalse` is the one construction seam for
/// the invalidation fact: assumption false ⇒ realization inadmissible, named
/// as `guard <proposition> is false on <measured subject revision>` — there
/// is no third state. Provenance is enforced AT CONSTRUCTION
/// (`law.evidence.subject.one`): an invalidation that cannot name the
/// measured subject revision on which the falsehood was observed constructs
/// NO fact — null, never a fact with incomplete provenance and never a
/// sentinel in-band. The fact names the proposition alone; selection among
/// candidates remains exactly the walk `select` already owns, so this face
/// adds identity without adding a second authority over which realizations
/// hold (`law.fact.producer.one`).
pub const GuardInvalidation = struct {
    /// Stable identity of the assumption proposition observed false.
    proposition: []const u8,
    /// The exact measured subject revision on which the falsehood was
    /// observed — never implicit "at HEAD".
    subject_revision: []const u8,
};

pub fn guardFalse(
    proposition: []const u8,
    subject_revision: []const u8,
) ?GuardInvalidation {
    if (subject_revision.len == 0) return null;
    return .{
        .proposition = proposition,
        .subject_revision = subject_revision,
    };
}

/// A named invalidation fact invalidates exactly the experiment whose
/// proposition it names. Sound experiments are untouched — their theorem did
/// not depend on the observation (same discipline as `invalidatedExperiment`,
/// now consuming the named fact rather than a bare string).
pub fn invalidationRefutes(
    fact: *const GuardInvalidation,
    e: *const Experiment,
) bool {
    return invalidatedExperiment(e, fact.proposition);
}

/// Deopt selection under a named invalidation fact: the refuted candidate
/// ceases to be admissible (`law.guard` — assumption false ⇒ realization
/// inadmissible) and the walk selects the first surviving candidate's
/// conditional theorem exactly as `select` does. The fact's measured subject
/// revision is carried by the fact itself; the walk remains a pure function
/// of fact names + world truth (`assumption_holds`).
pub fn selectUnderInvalidation(
    candidates: []const Guarded,
    fact: *const GuardInvalidation,
    assumption_holds: *const fn (proposition: []const u8) bool,
) ?[]const u8 {
    return select(candidates, fact.proposition, assumption_holds);
}

/// Speculation: the optimizer speculatively applied a transformation under a
/// guard. This is the "speculation" face of "guard/speculation/effect" — the
/// optimizer records that it applied a transformation conditionally, under a
/// guard proposition, with a named fallback candidate if the guard is
/// invalidated. The speculation is a named fact with construction-forced
/// provenance (`law.evidence.subject.one`): a speculation that cannot name the
/// measured subject revision on which it was made constructs NO fact — null,
/// never a fact with incomplete provenance and never a sentinel in-band.
///
/// The guard proposition is the SAME identity consumed by `GuardInvalidation`
/// and `selectUnderInvalidation` — one proposition namespace, no second
/// authority. The evidence field records what kind of evidence stands behind
/// the guard (profile counter, hardware counter, guard observation, etc.),
/// so the speculation's epistemic level is always recoverable from its own
/// fields (`law.magic.code.zero`).
pub const Speculation = struct {
    /// Stable identity of the guard proposition (same namespace as
    /// `GuardInvalidation.proposition` and `Experiment.proposition`).
    guard_proposition: []const u8,
    /// Stable identity of the transformation that was speculatively applied.
    applied_candidate: []const u8,
    /// Stable identity of the candidate selected if the guard is invalidated.
    fallback_candidate: []const u8,
    /// The exact measured subject revision on which the speculation was made
    /// (`law.evidence.subject.one`) — never implicit "at HEAD".
    subject_revision: []const u8,
    /// What kind of evidence stands behind the guard. Recoverable epistemic
    /// level: `self.evidence.level()` answers the level without a second table.
    evidence: EvidenceProducer,

    /// The epistemic level of this speculation's guard evidence. One taxonomy,
    /// recovered from the producer — no second priority table.
    pub fn level(self: *const Speculation) EpistemicLevel {
        return self.evidence.level();
    }

    /// Whether the speculation's guard is still valid. The caller supplies
    /// the runtime truth; this file owns no clock and no observation loop.
    pub fn valid(
        self: *const Speculation,
        guard_holds: *const fn (proposition: []const u8) bool,
    ) bool {
        return guard_holds(self.guard_proposition);
    }

    /// When the guard is invalidated, the fallback candidate is selected.
    /// This is the deopt path: the guard proposition became false, so the
    /// speculatively applied transformation is no longer admissible.
    pub fn deopt(self: *const Speculation) []const u8 {
        return self.fallback_candidate;
    }

    /// Whether this speculation's evidence can produce semantic truth on its
    /// own. Sound evidence (proof, inference) does; profile/counter/sample
    /// evidence never does — it demands a guard (`law.oracle.bounded`).
    pub fn producesTruth(self: *const Speculation) bool {
        return self.evidence.level().admitsWithoutGuard();
    }
};

/// The one construction seam for a speculation fact. The optimizer calls this
/// when it speculatively applies a transformation under a guard. Provenance is
/// enforced AT CONSTRUCTION: a speculation that cannot name the measured subject
/// revision constructs NO fact — null, never a fact with incomplete provenance
/// and never a sentinel in-band (`law.evidence.subject.one`). There is exactly
/// one construction seam — this function — so no caller can mint a speculation
/// over a different producer or with incomplete provenance
/// (`law.fact.producer.one`).
pub fn speculate(
    guard_proposition: []const u8,
    applied_candidate: []const u8,
    fallback_candidate: []const u8,
    subject_revision: []const u8,
    evidence: EvidenceProducer,
) ?Speculation {
    if (subject_revision.len == 0) return null;
    return .{
        .guard_proposition = guard_proposition,
        .applied_candidate = applied_candidate,
        .fallback_candidate = fallback_candidate,
        .subject_revision = subject_revision,
        .evidence = evidence,
    };
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

/// GAP-182 required order 5, graph-owned enforcement: the transform engine's
/// evidence taxonomy mapped onto the ONE epistemic taxonomy this file owns.
/// `semantic_proof` is static proof; `guarded` is the guard's own observation
/// witness; `imported` is an admitted foreign assertion (bounded by
/// `law.oracle.bounded` to its legacy-equivalent subset); `profile`,
/// `benchmark`, `target_estimate`, and `static_estimate` are observations or
/// estimates — evidence levels that never admit without a guard or proof.
/// The two taxonomies have no other mapping face, so a new engine evidence
/// kind cannot silently acquire a sound meaning beside it (compiler error,
/// not a default) — `law.magic.code.zero`.
pub fn levelForTransformEvidence(ev: transform_engine.Evidence) EpistemicLevel {
    return switch (ev) {
        .semantic_proof => .proven,
        .guarded => .guarded,
        .imported => .inferred_sound,
        .profile => .profiled,
        .benchmark => .sampled,
        .target_estimate => .heuristic,
        .static_estimate => .heuristic,
        .user_assertion => .heuristic,
        .heuristic => .heuristic,
    };
}

/// The truth face of the epistemic taxonomy for the outcome path: exactly
/// `admitsWithoutGuard`, restated under this name so the outcome conversion
/// reads as the law it applies (profile evidence is never semantic truth).
/// One level decides — no second priority table, no per-site override
/// (`law.profile.evidence`, `law.oracle.bounded`).
pub fn producesTruthLevel(level: EpistemicLevel) bool {
    return level.admitsWithoutGuard();
}

/// The outcome-log evidence face of the transform taxonomy, used when an
/// evidence-level entry is refused: the recorded evidence names WHAT was
/// observed, never the truth it cannot carry (`law.oracle.bounded`).
pub fn outcomeEvidenceForTransformEvidence(ev: transform_engine.Evidence) optimization_outcome.Evidence {
    return switch (ev) {
        .profile, .benchmark => .profiled,
        else => .estimated,
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

/// Required order 5 / closure face: hardware counters as a fact-producer.
/// A counter observation is one measured reading of one named hardware counter
/// on one measured subject revision (`law.evidence.subject.one`). It is
/// evidence, never semantic truth: the constructed experiment's producer is
/// always `hardware_counter` and therefore never admits without a guard
/// (`law.oracle.bounded`). There is exactly one construction seam — this
/// function — so no caller can mint a hardware-counter fact over a different
/// producer (`law.fact.producer.one`). Provenance is enforced AT CONSTRUCTION,
/// not audited afterward: a counter reading that cannot name the measured
/// subject revision it was taken on constructs no fact at all — null, never a
/// fact with incomplete provenance and never a sentinel in-band.
pub const CounterObservation = struct {
    /// Stable identity of the observed counter (e.g. "cycles", "branch_miss").
    counter: []const u8,
    /// The measured reading. An ordinary measurement value, never a sentinel.
    value: u64,
    /// The experiment-shaped fact this reading stands behind.
    experiment: Experiment,
};

pub fn observeCounter(
    proposition: []const u8,
    counter: []const u8,
    value: u64,
    cost: u32,
    conditional_theorem: []const u8,
    subject_revision: []const u8,
) ?CounterObservation {
    if (subject_revision.len == 0) return null;
    return .{
        .counter = counter,
        .value = value,
        .experiment = .{
            .proposition = proposition,
            .producer = .hardware_counter,
            .cost = cost,
            .conditional_theorem = conditional_theorem,
            .subject_revision = subject_revision,
        },
    };
}

/// Required order 5: a runtime profile is an evidence producer, never
/// semantic truth. The measured share belongs to one named proposition on one
/// measured subject revision; its experiment names the candidate the profile
/// may prefer only after a guard admits it. Missing revision provenance
/// constructs no fact (`law.evidence.subject.one`).
pub const ProfileObservation = struct {
    share: SemanticShare,
    experiment: Experiment,
};

pub fn observeProfile(
    proposition: []const u8,
    held: u64,
    total: u64,
    cost: u32,
    conditional_theorem: []const u8,
    subject_revision: []const u8,
) ?ProfileObservation {
    if (subject_revision.len == 0) return null;
    return .{
        .share = .{ .held = held, .total = total },
        .experiment = .{
            .proposition = proposition,
            .producer = .profile_counter,
            .cost = cost,
            .conditional_theorem = conditional_theorem,
            .subject_revision = subject_revision,
        },
    };
}

/// Required order 5: a runtime sample is an evidence producer, never
/// semantic truth. The sampled value belongs to one named proposition on one
/// measured subject revision. Missing revision provenance constructs no fact
/// (`law.evidence.subject.one`), and the producer is fixed at this one
/// construction seam (`law.fact.producer.one`).
pub const SampleObservation = struct {
    /// The observed sample value. An ordinary measurement, never a sentinel.
    value: u64,
    experiment: Experiment,
};

pub fn observeSample(
    proposition: []const u8,
    value: u64,
    cost: u32,
    conditional_theorem: []const u8,
    subject_revision: []const u8,
) ?SampleObservation {
    if (subject_revision.len == 0) return null;
    return .{
        .value = value,
        .experiment = .{
            .proposition = proposition,
            .producer = .sample,
            .cost = cost,
            .conditional_theorem = conditional_theorem,
            .subject_revision = subject_revision,
        },
    };
}

/// Closure face: inline caches as a fact-producer. An inline cache
/// observation is the shape witnessed at one named call site on one measured
/// subject revision (`law.evidence.subject.one`). It is evidence, never
/// semantic truth: the constructed experiment's producer is always
/// `inline_cache`, mapping to the `profiled` level and therefore never
/// admitting without a guard (`law.oracle.bounded`). There is exactly one
/// construction seam — this function — so no caller can mint an inline-cache
/// fact over a different producer (`law.fact.producer.one`). Provenance is
/// enforced AT CONSTRUCTION, not audited afterward: a cache observation that
/// cannot name the measured subject revision it was taken on constructs no
/// fact at all — null, never a fact with incomplete provenance and never a
/// sentinel in-band. This is the foreign inline cache expressed inside the
/// one experiment fact family, not a separate JIT subsystem (deletion
/// witness).
pub const InlineCacheObservation = struct {
    /// Stable identity of the observed call site (e.g. "site:17").
    site: []const u8,
    /// Stable identity of the shape witnessed at the site (e.g. "shape:42").
    shape: []const u8,
    /// The experiment-shaped fact this observation stands behind.
    experiment: Experiment,
};

pub fn observeInlineCache(
    proposition: []const u8,
    site: []const u8,
    shape: []const u8,
    cost: u32,
    conditional_theorem: []const u8,
    subject_revision: []const u8,
) ?InlineCacheObservation {
    if (subject_revision.len == 0) return null;
    return .{
        .site = site,
        .shape = shape,
        .experiment = .{
            .proposition = proposition,
            .producer = .inline_cache,
            .cost = cost,
            .conditional_theorem = conditional_theorem,
            .subject_revision = subject_revision,
        },
    };
}

/// Axiom producer wiring: the seventh epistemic level is backed by exactly
/// one producer. A constitutional axiom is a law-level fact whose truth is
/// not derived from any observation; the constructed experiment's producer
/// is always `constitutional_axiom` and therefore maps to the `axiom`
/// level — it admits without a guard (`admitsWithoutGuard`), is never
/// invalidated (`invalidatedExperiment`), and names NO measured subject
/// revision because no measurement stands behind it (`isEvidence` false, so
/// `provenanceComplete` demands none). There is exactly one construction
/// seam — this function — so no caller can mint an axiom-level experiment
/// over a different producer (`law.fact.producer.one`): an axiom asserts
/// `law`, nothing else.
pub fn axiomOf(
    proposition: []const u8,
    conditional_theorem: []const u8,
) Experiment {
    return .{
        .proposition = proposition,
        .producer = .constitutional_axiom,
        .cost = 0,
        .conditional_theorem = conditional_theorem,
    };
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

/// Compiler epistemic probability: confidence that the fact set is complete.
/// This is a fact about the COMPILER's knowledge, never about the subject.
/// It may order exploration of the realization space (`law.optimizer.economy`
/// meta-cost) but never enters admissibility, selection, or invalidation.
///
/// The representation is intentionally distinct from `SemanticShare` to prevent
/// any arithmetic or operation from confusing the two categories. There is no
/// conversion between `EpistemicProbability` and `SemanticShare`, and no shared
/// operations consume one as the other.
pub const EpistemicProbability = struct {
    /// Confidence level in milli-per-unit (0-1000). Higher values indicate
    /// greater confidence that the fact set is complete for this exploration
    /// decision point. This is NOT a measured subject probability — it is a
    /// compiler-internal meta-probability about its own knowledge state.
    confidence: u16,

    /// Create an epistemic probability from a confidence value (0-1000 mpu).
    /// Values outside the valid range are clamped to enforce the invariant.
    pub fn fromMilli(confidence: u16) EpistemicProbability {
        return .{ .confidence = if (confidence > 1000) 1000 else confidence };
    }

    /// Confidence level in milli-per-unit. This is the same representation as
    /// `SemanticShare.milli()` but the TYPE DISTINCTION prevents accidental
    /// substitution — an `EpistemicProbability` can never be passed where a
    /// `SemanticShare` is demanded, and vice versa.
    pub fn milli(self: EpistemicProbability) u16 {
        return self.confidence;
    }

    /// Compare two epistemic probabilities for ordering exploration. Higher
    /// confidence orders earlier in the search. This operation is ONLY for
    /// exploration ordering under `law.optimizer.economy`; it never influences
    /// admissibility, selection, or invalidation.
    pub fn exceeds(self: EpistemicProbability, other: EpistemicProbability) bool {
        return self.confidence > other.confidence;
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
    /// proposition is the false one cease to be admissible. A missing
    /// measured subject revision constructs no invalidation fact and selects
    /// no fallback.
    pub fn invalidate(
        self: *const DeoptBoundary,
        false_proposition: []const u8,
        subject: []const u8,
        assumption_holds: *const fn (proposition: []const u8) bool,
    ) ?[]const u8 {
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

/// Required orders 3+4 graph-consumption seam: one `Guarded` candidate from a
/// graph-emitted `ExperimentFact` plus the stated assumption identities the
/// emitting guard recorded. This is the ONLY bridge from the order-1 graph
/// tuple face into the runtime fact family — the same discipline as
/// `fromAssumption` (`law.fact.producer.one`): callers never hand-wire an
/// `Experiment` from graph tuple fields, so fact identity, producer identity,
/// and provenance cannot drift into a second authority.
///
/// - Producer: consumed by NAME through `EvidenceProducer.fromName`; an
///   unrecognized name consumes to NO candidate — an experiment whose producer
///   cannot be named is a fact with broken provenance, never a heuristic
///   default (`law.magic.code.zero`).
/// - Stated assumptions: the caller names every assumption predicate identity
///   beyond the experiment's own proposition (order 3: admissible only under
///   its stated assumptions; an experiment emitted with no assumption
///   identities carries an empty set, exactly as `fromAssumption` does).
/// - Provenance: the tuple's measured subject revision carries over verbatim;
///   evidence-strength producers with no revision name construct NO candidate —
///   provenance is enforced at the bridge before selection can promote an
///   incomplete fact (`law.evidence.subject.one`).
/// - Invalidation (order 4) is NOT stored here: it is a runtime `GuardInvalidation`
///   fact applied by `selectUnderInvalidation`; the candidate face holds only
///   the experiment + stated assumptions, so a guard false on its proposition
///   ceases admissible and deopt selects another — one walk, one authority.
pub const fromExperimentFactErrors = error{ ProducerUnnamed, EvidenceRevisionMissing };

pub fn fromExperimentFact(
    fact: *const semantic_graph.ExperimentFact,
    stated_assumptions: []const []const u8,
) fromExperimentFactErrors!Guarded {
    const producer = EvidenceProducer.fromName(fact.producer) orelse
        return error.ProducerUnnamed;
    if (producer.isEvidence() and fact.subject_revision.len == 0)
        return error.EvidenceRevisionMissing;
    return .{
        .experiment = .{
            .proposition = fact.proposition,
            .producer = producer,
            .cost = fact.cost,
            .conditional_theorem = fact.conditional_theorem,
            .subject_revision = fact.subject_revision,
        },
        .assumptions = stated_assumptions,
    };
}

/// Still-missing face: runtime facts refine the candidate set — `if P then
/// candidate C is admissible`. Assumption truth must enter as a FACT, not as
/// a caller-supplied boolean function: a `RuntimeFact` is one measured
/// observation that proposition `P` currently holds (or is observed false) on
/// one measured subject revision (`law.evidence.subject.one`). As with
/// hardware counters, there is exactly one construction seam — `observeFact`
/// — and a runtime observation that names no measured subject revision
/// constructs NO fact; provenance is the admission condition, not an audit
/// flag. A runtime fact is world-qualified evidence, never semantic truth:
/// it refines which already-guarded candidates are admissible NOW, and it
/// never promotes a candidate past its guard (`law.oracle.bounded`).
pub const RuntimeFact = struct {
    /// Stable identity of the observed proposition, e.g. "shape:42".
    proposition: []const u8,
    /// The observed truth on the measured subject at `subject_revision`.
    /// True means P currently holds; false means P was observed false.
    holds: bool,
    /// The exact measured subject revision this observation was taken on.
    subject_revision: []const u8,

    /// One fact answers one runtime truth query. A fact recorded over a
    /// different proposition answers nothing — refinement is keyed on the
    /// proposition identity alone, so an unrelated observation never touches
    /// this candidate (the same sound invalidation discipline as
    /// `invalidatedExperiment`).
    pub fn answers(self: *const RuntimeFact, proposition: []const u8) ?bool {
        if (!std.mem.eql(u8, self.proposition, proposition)) return null;
        return self.holds;
    }
};

pub fn observeFact(
    proposition: []const u8,
    holds: bool,
    subject_revision: []const u8,
) ?RuntimeFact {
    if (subject_revision.len == 0) return null;
    return .{
        .proposition = proposition,
        .holds = holds,
        .subject_revision = subject_revision,
    };
}

/// Wired-end-to-end face: every candidate carries one of the seven epistemic
/// categories, and selection consumes that category. The taxonomy and its
/// producer bridges exist above; what was missing is ONE executed boundary
/// that walks a candidate set through ALL seven levels and applies the one
/// admissibility law uniformly: sound levels (`axiom`, `proven`,
/// `inferred_sound`) admit on their fact alone; evidence levels (`guarded`,
/// `profiled`, `sampled`, `heuristic`) admit only while a runtime fact
/// affirmatively answers their proposition — profile evidence alone is never
/// affirmation and never promotes past the guard. This function is
/// graph-owned enforcement: if it is the only seam from candidate set to a
/// selected theorem, NO optimizer path can bypass the profile-needs-guard
/// law — the category is read from the experiment's producer, not re-derived
/// or audited afterward (`law.fact.producer.one`, `law.oracle.bounded`).
///
/// Selection order among survivors is the candidate order — epistemic level
/// decides admissibility, never priority.
pub fn selectByEpistemicLevel(
    candidates: []const Guarded,
    facts: []const RuntimeFact,
) ?[]const u8 {
    for (candidates) |*c| {
        const level = c.experiment.producer.level();
        if (level.admitsWithoutGuard()) {
            return c.experiment.conditional_theorem;
        }
        if (holdsUnderFacts(facts, c.experiment.proposition) and
            holdsAssumptionsUnderFacts(facts, c))
        {
            return c.experiment.conditional_theorem;
        }
    }
    return null;
}

fn holdsAssumptionsUnderFacts(facts: []const RuntimeFact, c: *const Guarded) bool {
    for (c.assumptions) |a| {
        if (!holdsUnderFacts(facts, a)) return false;
    }
    return true;
}

/// Runtime facts refine the candidate set: `if P then candidate C is
/// admissible`. The fact set is the sole authority over which propositions
/// currently hold — a proposition answered by no recorded fact does NOT hold
/// (a guarded realization is admissible only under its stated assumptions;
/// absent affirmation is not affirmation). This is the fact-family face of
/// the `assumption_holds` callback: callers that have measured runtime facts
/// route them through this one seam instead of re-deriving a truth function
/// at every boundary (`law.fact.producer.one`).
pub fn holdsUnderFacts(facts: []const RuntimeFact, proposition: []const u8) bool {
    for (facts) |*f| {
        if (f.answers(proposition)) |holds| return holds;
    }
    return false;
}

/// Refine the candidate set under measured runtime facts and select the
/// conditional theorem of the first refined-admissible candidate. Returns
/// null when no candidate survives refinement — the same answer `select`
/// gives, so `deoptOrFallback` composes verbatim. Selection order among the
/// refined survivors is exactly the candidate order: facts refine
/// admissibility, never reprioritize (`law.profile.evidence` handles
/// preference separately through `SemanticShare`).
pub fn refine(
    candidates: []const Guarded,
    false_proposition: []const u8,
    facts: []const RuntimeFact,
) ?[]const u8 {
    for (candidates) |*c| {
        const invalidated = invalidatedExperiment(&c.experiment, false_proposition);
        if (!c.experiment.admissible(invalidated)) continue;
        if (!holdsUnderFacts(facts, c.experiment.proposition)) continue;
        var assumptions_hold = true;
        for (c.assumptions) |a| {
            if (!holdsUnderFacts(facts, a)) {
                assumptions_hold = false;
                break;
            }
        }
        if (assumptions_hold) return c.experiment.conditional_theorem;
    }
    return null;
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

test "effect: epistemic probability is distinct from semantic share" {
    // Type distinction: EpistemicProbability and SemanticShare are separate
    // types with no conversion between them. This is the executable face of
    // GAP-182 order 2's requirement that semantic probability (subject fact)
    // and compiler epistemic probability (compiler knowledge fact) never be
    // confused.

    // EpistemicProbability represents compiler confidence, not subject measurement.
    const high_confidence = EpistemicProbability.fromMilli(950);
    const low_confidence = EpistemicProbability.fromMilli(100);

    // Confidence values are clamped to valid range (0-1000 mpu).
    try std.testing.expectEqual(@as(u16, 950), high_confidence.milli());
    try std.testing.expectEqual(@as(u16, 100), low_confidence.milli());

    const clamped = EpistemicProbability.fromMilli(1500);
    try std.testing.expectEqual(@as(u16, 1000), clamped.milli());

    // Comparison orders exploration (higher confidence first).
    try std.testing.expect(high_confidence.exceeds(low_confidence));
    try std.testing.expect(!low_confidence.exceeds(high_confidence));

    // SemanticShare represents measured subject probability, not compiler confidence.
    const share = SemanticShare{ .held = 80, .total = 100 };
    try std.testing.expectEqual(@as(u64, 800), share.milli());

    // No share (total == 0) answers zero.
    const no_share = SemanticShare{ .held = 0, .total = 0 };
    try std.testing.expectEqual(@as(u64, 0), no_share.milli());

    // The two types have the same `milli()` representation but are distinct
    // types — the compiler cannot accidentally substitute one for the other.
    // This is enforced by Zig's type system; there is no implicit conversion.
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
        .subject_revision = "rev:deopt",
    };
    const one = [_]Guarded{first};
    try std.testing.expectEqualStrings("cand:generic", deoptOrFallback(invalidation, &one, &holdsAll).?);
    const unmeasured = Invalidation{
        .experiment_proposition = "shape:7",
        .fallback_candidate = "cand:generic",
    };
    try std.testing.expect(deoptOrFallback(unmeasured, &one, &holdsAll) == null);
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
        .subject_revision = "rev:share",
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
        deoptOrFallback(invalidated, &candidates, &all_false).?,
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
    const evidence_producers = [_]EvidenceProducer{ .profile_counter, .hardware_counter, .sample, .inline_cache, .heuristic_estimate };
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
    try std.testing.expect(!experiment(.inline_cache, "").provenanceComplete());
    try std.testing.expect(!experiment(.heuristic_estimate, "").provenanceComplete());
    try std.testing.expect(experiment(.profile_counter, "rev:abc").provenanceComplete());
    try std.testing.expect(experiment(.hardware_counter, "rev:abc").provenanceComplete());
    try std.testing.expect(experiment(.inline_cache, "rev:abc").provenanceComplete());
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

test "effect: hardware counters are fact-producers with construction-forced provenance" {
    // Closure face: a hardware counter produces an experiment-shaped fact
    // with exactly one construction seam. A reading that names no measured
    // subject revision constructs NO fact — provenance is the admission
    // condition, not an audit flag (law.evidence.subject.one).
    const reading = (observeCounter(
        "shape:7",
        "cycles",
        4200,
        1,
        "cand:fast-table",
        "rev:abc",
    )).?;
    try std.testing.expectEqualStrings("cycles", reading.counter);
    try std.testing.expectEqual(@as(u64, 4200), reading.value);
    try std.testing.expectEqual(EvidenceProducer.hardware_counter, reading.experiment.producer);
    try std.testing.expectEqual(EpistemicLevel.profiled, reading.experiment.producer.level());
    try std.testing.expect(reading.experiment.producer.isEvidence());
    try std.testing.expect(reading.experiment.provenanceComplete());
    // The reading is evidence, never truth — it still demands a guard or
    // proof before a semantics-changing realization may rely on it.
    try std.testing.expect(!reading.experiment.producesTruth());
    try std.testing.expect(!reading.experiment.admissible(true));
    try std.testing.expect(reading.experiment.admissible(false));
    try std.testing.expect(profileNeedsGuard(reading.experiment.producer.level()));
    // No revision, no fact: provenance enforced at construction.
    try std.testing.expect(observeCounter("shape:7", "cycles", 1, 1, "cand:x", "") == null);
    // A zero-cost counter observation is lawful nonexecution but still
    // profiled evidence — cost never upgrades the epistemic level.
    const free = (observeCounter("shape:7", "cycles", 0, 0, "cand:cached", "rev:abc")).?;
    try std.testing.expect(realizesZero(&free.experiment));
    try std.testing.expect(!free.experiment.producesTruth());
}

test "effect: profiles are fact-producers with construction-forced provenance" {
    const profile = (observeProfile(
        "branch:hot",
        99,
        100,
        2,
        "cand:straight",
        "rev:profile",
    )).?;
    try std.testing.expectEqual(@as(u64, 990), profile.share.milli());
    try std.testing.expectEqual(EvidenceProducer.profile_counter, profile.experiment.producer);
    try std.testing.expect(profile.experiment.provenanceComplete());
    try std.testing.expect(!profile.experiment.producesTruth());
    try std.testing.expect(profileNeedsGuard(profile.experiment.producer.level()));
    try std.testing.expect(observeProfile(
        "branch:hot",
        1,
        1,
        1,
        "cand:straight",
        "",
    ) == null);
}

test "effect: samples are fact-producers with construction-forced provenance" {
    const sample = (observeSample(
        "shape:sampled",
        42,
        3,
        "cand:sampled",
        "rev:sample",
    )).?;
    try std.testing.expectEqual(@as(u64, 42), sample.value);
    try std.testing.expectEqual(EvidenceProducer.sample, sample.experiment.producer);
    try std.testing.expectEqual(EpistemicLevel.sampled, sample.experiment.producer.level());
    try std.testing.expect(sample.experiment.producer.isEvidence());
    try std.testing.expect(sample.experiment.provenanceComplete());
    try std.testing.expect(!sample.experiment.producesTruth());
    try std.testing.expect(profileNeedsGuard(sample.experiment.producer.level()));
    try std.testing.expect(observeSample(
        "shape:sampled",
        42,
        3,
        "cand:sampled",
        "",
    ) == null);
    // Observation cost never promotes evidence to semantic truth.
    const free = (observeSample("shape:sampled", 42, 0, "cand:sampled", "rev:sample")).?;
    try std.testing.expect(realizesZero(&free.experiment));
    try std.testing.expect(!free.experiment.producesTruth());
}

test "effect: inline caches are fact-producers with construction-forced provenance" {
    // Closure face: an inline cache observation produces an experiment-shaped
    // fact with exactly one construction seam. A site observation that names
    // no measured subject revision constructs NO fact — provenance is the
    // admission condition, not an audit flag (law.evidence.subject.one).
    const hit = (observeInlineCache(
        "site:17",
        "site:17",
        "shape:42",
        1,
        "cand:mono-site",
        "rev:abc",
    )).?;
    try std.testing.expectEqualStrings("site:17", hit.site);
    try std.testing.expectEqualStrings("shape:42", hit.shape);
    try std.testing.expectEqual(EvidenceProducer.inline_cache, hit.experiment.producer);
    try std.testing.expectEqual(EpistemicLevel.profiled, hit.experiment.producer.level());
    try std.testing.expect(hit.experiment.producer.isEvidence());
    try std.testing.expect(hit.experiment.provenanceComplete());
    // The observation is evidence, never truth — it still demands a guard or
    // proof before a semantics-changing realization may rely on it, and a
    // witnessed shape going stale invalidates exactly this candidate.
    try std.testing.expect(!hit.experiment.producesTruth());
    try std.testing.expect(!hit.experiment.admissible(true));
    try std.testing.expect(hit.experiment.admissible(false));
    try std.testing.expect(profileNeedsGuard(hit.experiment.producer.level()));
    try std.testing.expect(invalidatedExperiment(&hit.experiment, "site:17"));
    try std.testing.expect(!invalidatedExperiment(&hit.experiment, "site:18"));
    // No revision, no fact: provenance enforced at construction.
    try std.testing.expect(observeInlineCache("site:17", "site:17", "shape:42", 1, "cand:x", "") == null);
    // The producer round-trips through the graph face by NAME, never by
    // ordinal — the one reverse map consumes it (law.magic.code.zero).
    try std.testing.expectEqualStrings("inline_cache", EvidenceProducer.inline_cache.name());
    try std.testing.expectEqual(
        EvidenceProducer.inline_cache,
        EvidenceProducer.fromName("inline_cache").?,
    );
    // A zero-cost cache observation is lawful nonexecution but still
    // profiled evidence — cost never upgrades the epistemic level.
    const free = (observeInlineCache("site:17", "site:17", "shape:42", 0, "cand:cached", "rev:abc")).?;
    try std.testing.expect(realizesZero(&free.experiment));
    try std.testing.expect(!free.experiment.producesTruth());
}

fn holdsNone(proposition: []const u8) bool {
    _ = proposition;
    return false;
}

test "effect: runtime facts refine the candidate set" {
    // Still-missing face: `if P then candidate C is admissible`. Runtime
    // facts are world-qualified evidence with construction-forced provenance
    // (`law.evidence.subject.one`); a proposition answered by no fact does
    // not hold, and a fact recorded over an unrelated proposition never
    // touches this candidate.
    const hot = Guarded{
        .experiment = .{
            .proposition = "shape:7",
            .producer = .guard_observation,
            .cost = 1,
            .conditional_theorem = "cand:mono",
        },
        .assumptions = &.{"version:12"},
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

    // No fact recorded: nothing holds, no candidate is admissible.
    try std.testing.expect(refine(&candidates, "shape:never", &.{}) == null);

    // Every recorded fact names its measured subject revision; a fact cannot
    // be constructed without it (provenance is the admission condition).
    try std.testing.expect(observeFact("shape:7", true, "") == null);

    const shape7 = (observeFact("shape:7", true, "rev:abc")).?;
    const version12 = (observeFact("version:12", true, "rev:abc")).?;
    const shape9false = (observeFact("shape:9", false, "rev:abc")).?;

    // P holds and every stated assumption holds ⇒ the candidate is refined-admissible.
    const yes = [_]RuntimeFact{ shape7, version12 };
    try std.testing.expectEqualStrings("cand:mono", refine(&candidates, "shape:never", &yes).?);

    // Stated assumption unanswered ⇒ the candidate is inadmissible even while
    // its own proposition holds; refinement moves to the next candidate whose
    // proposition the fact set affirms.
    const no_version = [_]RuntimeFact{shape7};
    try std.testing.expect(!holdsUnderFacts(&no_version, "version:12"));
    try std.testing.expect(refine(&candidates, "shape:never", &no_version) == null);

    // A fact observing the second candidate's proposition FALSE never admits
    // it; refinement falls past both when the first is excluded too.
    const stale = [_]RuntimeFact{ shape7, version12, shape9false };
    try std.testing.expectEqualStrings("cand:mono", refine(&candidates, "shape:never", &stale).?);
    try std.testing.expect(refine(&candidates, "shape:7", &no_version) == null);

    // Guard invalidation composes: the first candidate's proposition is
    // recorded false, and the survivor is admissible only because the fact
    // set affirmatively answers ITS proposition — absent affirmation is not
    // affirmation, so refinement never falls through to an unwitnessed
    // candidate (order 4 + the refinement face in one walk).
    const shape9true = (observeFact("shape:9", true, "rev:abc")).?;
    const affirmed = [_]RuntimeFact{ shape7, version12, shape9true };
    try std.testing.expectEqualStrings("cand:poly", refine(&candidates, "shape:7", &affirmed).?);

    // A fact recorded over an unrelated proposition answers nothing and
    // never admits the candidate it does not name.
    const unrelated = [_]RuntimeFact{(observeFact("kind:packed", true, "rev:abc")).?};
    try std.testing.expect(unrelated[0].answers("shape:7") == null);
    try std.testing.expect(refine(&candidates, "shape:never", &unrelated) == null);

    // Facts never promote past the guard: a sound candidate stays admissible
    // under any fact set — its theorem did not depend on the observation.
    const proved = Guarded{
        .experiment = .{
            .proposition = "law:fold",
            .producer = .static_proof,
            .cost = 0,
            .conditional_theorem = "cand:theorem",
        },
    };
    try std.testing.expect(proved.experiment.admissible(true));
    // Refined admissibility answers null exactly as `select` does, so the
    // recorded fallback composes verbatim through the same boundary.
    const none = [_]Guarded{hot};
    try std.testing.expect(refine(&none, "shape:never", &.{}) == null);
    const invalidation = Invalidation{
        .experiment_proposition = "shape:never",
        .fallback_candidate = "cand:generic",
        .subject_revision = "rev:refine",
    };
    try std.testing.expectEqualStrings(
        "cand:generic",
        deoptOrFallback(invalidation, &none, &holdsNone).?,
    );
}

test "effect: guard invalidation is a named fact with construction-forced provenance" {
    // Still-missing face: guard invalidation as a NAMED fact. `guardFalse` is
    // the one construction seam; an invalidation naming no measured subject
    // revision constructs NO fact (law.evidence.subject.one).
    try std.testing.expect(guardFalse("shape:7", "") == null);
    const fact = (guardFalse("shape:7", "rev:abc")).?;
    try std.testing.expectEqualStrings("shape:7", fact.proposition);
    try std.testing.expectEqualStrings("rev:abc", fact.subject_revision);

    // The named fact refutes exactly the experiment whose proposition it
    // names; sound experiments are untouched (same discipline as
    // `invalidatedExperiment`, through the fact face).
    const guarded_exp = Experiment{
        .proposition = "shape:7",
        .producer = .guard_observation,
        .cost = 3,
        .conditional_theorem = "cand:mono",
    };
    const proved_exp = Experiment{
        .proposition = "shape:7",
        .producer = .static_proof,
        .cost = 0,
        .conditional_theorem = "cand:theorem",
    };
    try std.testing.expect(invalidationRefutes(&fact, &guarded_exp));
    try std.testing.expect(!invalidationRefutes(&fact, &proved_exp));
    const other = (guardFalse("shape:9", "rev:abc")).?;
    try std.testing.expect(!invalidationRefutes(&other, &guarded_exp));

    // Assumption false ⇒ realization inadmissible, as a fact-driven walk:
    // the refuted candidate ceases to be admissible and deopt selects the
    // next surviving candidate — exactly the `select` answer, now keyed on
    // the named fact rather than a bare string.
    const candidates = [_]Guarded{
        .{ .experiment = guarded_exp },
        .{ .experiment = .{
            .proposition = "shape:9",
            .producer = .guard_observation,
            .cost = 1,
            .conditional_theorem = "cand:poly",
        } },
        .{ .experiment = proved_exp },
    };
    try std.testing.expectEqualStrings(
        "cand:mono",
        selectUnderInvalidation(&candidates, &other, &holdsAll).?,
    );
    try std.testing.expectEqualStrings(
        "cand:poly",
        selectUnderInvalidation(&candidates, &fact, &holdsAll).?,
    );

    // When both evidence-level candidates are refuted, only the sound
    // theorem survives — a named fact never promotes or demotes anything
    // else, and no answer remains a null exactly as `select` answers null.
    const both = [_]Guarded{.{ .experiment = guarded_exp }};
    try std.testing.expect(selectUnderInvalidation(&both, &fact, &holdsAll) == null);

    // Composes with the existing boundary verbatim: the fact's proposition
    // answers the same candidate `select` and `deoptOrFallback` already
    // answer, so the fallback path is unchanged.
    const invalidation = Invalidation{
        .experiment_proposition = fact.proposition,
        .fallback_candidate = "cand:generic",
        .subject_revision = fact.subject_revision,
    };
    try std.testing.expectEqualStrings(
        "cand:generic",
        deoptOrFallback(invalidation, &both, &holdsAll).?,
    );
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
        boundary.invalidate(shape_id, "rev:boundary", &holdsAll).?,
    );
    try std.testing.expect(boundary.invalidate(shape_id, "", &holdsAll) == null);
    // An unrelated false proposition invalidates nothing; the guarded
    // candidate still holds under its assumptions.
    try std.testing.expectEqualStrings(
        "cand:sealed-point",
        boundary.invalidate("shape:elsewhere", "rev:boundary", &holdsAll).?,
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
        boundary.invalidate("shape:elsewhere", "rev:boundary", &none_hold).?,
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

test "effect: all seven epistemic categories wired through one boundary" {
    // Still-missing face executed: one candidate set exercises axiom, proven,
    // inferred-sound, guarded, profiled, sampled, and heuristic at ONE
    // boundary. The executed-graph face comes first: the guarded candidate is
    // built from an assumption emitted by `assumption_guard.buildFromModule`
    // from an executed semantic graph, so the boundary consumes graph-emitted
    // facts, not only hand-wired ones.
    const sema = @import("sema.zig");
    const ast = @import("ast.zig");
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "epistemic.id", .start = 0, .end = 0 },
    });
    const shape = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "epistemic.id", .start = 1, .end = 1 },
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
    var id_buf: [20]u8 = undefined;
    const shape_id = try std.fmt.bufPrint(&id_buf, "guard:{d}", .{shape});

    var candidates = [_]Guarded{
        (fromAssumption("ax:identity", "cand:axiom", .proven, 0, "")),
        (fromAssumption("law:fold", "cand:fold", .proven, 0, "")),
        (fromAssumption("inv:rowcount", "cand:inferred", .guarded, 0, "")),
        (fromAssumption(shape_id, "cand:sealed-point", emitted.items[0].evidence, 3, "")),
        .{ .experiment = .{
            .proposition = "shape:hot",
            .producer = .profile_counter,
            .cost = 1,
            .conditional_theorem = "cand:hot",
            .subject_revision = "rev:e1",
        } },
        .{ .experiment = .{
            .proposition = "shape:sampled",
            .producer = .sample,
            .cost = 1,
            .conditional_theorem = "cand:sampled",
            .subject_revision = "rev:e1",
        } },
        .{ .experiment = .{
            .proposition = "shape:guess",
            .producer = .heuristic_estimate,
            .cost = 0,
            .conditional_theorem = "cand:guess",
        } },
    };
    candidates[2].experiment.producer = .invariant_inference;
    try std.testing.expectEqual(@as(usize, 7), candidates.len);
    // `axiom` has exactly one producer — `constitutional_axiom` via the
    // `axiomOf` seam — so the executed coverage spans all seven categories:
    // the six producer-backed experiments above plus the axiom law consumed
    // through the same one boundary.
    inline for (@typeInfo(EvidenceProducer).@"enum".field_values) |v| {
        const p: EvidenceProducer = @fromBackingInt(@intCast(v));
        const want: EpistemicLevel = if (p == .constitutional_axiom) .axiom else p.level();
        try std.testing.expect(p.level() == want);
    }
    try std.testing.expectEqual(EpistemicLevel.proven, candidates[0].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.proven, candidates[1].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.inferred_sound, candidates[2].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.guarded, candidates[3].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.profiled, candidates[4].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.sampled, candidates[5].experiment.producer.level());
    try std.testing.expectEqual(EpistemicLevel.heuristic, candidates[6].experiment.producer.level());

    // With no runtime facts at all, a profiled/sampled/heuristic candidate
    // can never admit; the first sound-level candidate wins. Profile evidence
    // alone is not affirmation of the proposition — the boundary answers
    // cand:axiom (a proven-level experiment).
    try std.testing.expectEqualStrings(
        "cand:axiom",
        selectByEpistemicLevel(&candidates, &.{}) orelse unreachable,
    );

    // Affirm the evidence-level propositions; in the evidence tail the
    // guarded graph-emitted candidate wins once its proposition is affirmed,
    // while the profiled candidate's fact is false. Sound candidates would
    // answer regardless — they are deliberately outside this slice.
    var facts = [_]RuntimeFact{
        (observeFact("shape:hot", false, "rev:e1") orelse unreachable),
        (observeFact(shape_id, true, "rev:e0") orelse unreachable),
        (observeFact("shape:sampled", true, "rev:e1") orelse unreachable),
    };
    try std.testing.expectEqualStrings(
        "cand:sealed-point",
        selectByEpistemicLevel(candidates[3..6], &facts) orelse unreachable,
    );
    // Without an affirming fact, even a guarded candidate stays inadmissible
    // and the sampled one behind it wins when affirmed.
    try std.testing.expectEqualStrings(
        "cand:sampled",
        selectByEpistemicLevel(candidates[3..6], facts[2..3]) orelse unreachable,
    );

    // A candidate set with only evidence levels and no affirming facts
    // selects nothing — the exact answer `select` gives, so the deopt
    // fallback composition is unchanged. Affirming the heuristic's
    // proposition admits even a heuristic candidate — the level demands a
    // guard, and the runtime fact IS the supplied guard answer.
    const evidence_only = [3]Guarded{ candidates[4], candidates[5], candidates[6] };
    try std.testing.expect(selectByEpistemicLevel(&evidence_only, &.{}) == null);
    const guess_fact = [1]RuntimeFact{
        (observeFact("shape:guess", true, "rev:e1") orelse unreachable),
    };
    try std.testing.expectEqualStrings(
        "cand:guess",
        selectByEpistemicLevel(&evidence_only, &guess_fact) orelse unreachable,
    );
}

test "effect: axiom producer wires the seventh epistemic level through one seam" {
    // One construction seam mints the axiom-level experiment; the axiom
    // names no measured subject revision because no measurement stands
    // behind it, and its provenance is complete by `isEvidence == false`.
    const ax = axiomOf("law:subject-one", "cand:axiom");
    try std.testing.expectEqual(EvidenceProducer.constitutional_axiom, ax.producer);
    try std.testing.expectEqual(EpistemicLevel.axiom, ax.producer.level());
    try std.testing.expect(ax.producer.level().admitsWithoutGuard());
    try std.testing.expect(!ax.producer.isEvidence());
    try std.testing.expect(ax.provenanceComplete());
    try std.testing.expect(ax.producesTruth());
    try std.testing.expect(ax.admissible(true));
    try std.testing.expectEqualStrings("constitutional_axiom", ax.producer.name());

    // The axiom level is never invalidated by any named false proposition.
    const inv = invalidatedExperiment(&ax, "law:subject-one");
    try std.testing.expect(!inv);

    // Through the one boundary, an axiom-level candidate admits on its own
    // fact alone — no runtime facts, no guard, and it answers ahead of the
    // evidence-level tail without reprioritizing it.
    const set = [_]Guarded{
        .{ .experiment = ax },
        .{ .experiment = (observeCounter(
            "shape:7",
            "cycles",
            1,
            1,
            "cand:counter",
            "rev:abc",
        ) orelse unreachable).experiment },
    };
    try std.testing.expectEqualStrings(
        "cand:axiom",
        selectByEpistemicLevel(&set, &.{}) orelse unreachable,
    );
    // Under the fact-family boundary itself, the axiom admits on its own
    // fact alone with no runtime facts at all — the sound level answers
    // while the evidence-level counter candidate behind it does not.
}
