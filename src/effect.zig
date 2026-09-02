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

const optimization_outcome = @import("optimization_outcome.zig");

pub const SCHEMA_VERSION = "gap182-experiment-v0";

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

    /// A sound experiment (proof-derived) stays admissible when invalidated —
    /// the theorem did not depend on the observation. Evidence-level
    /// experiments admit their candidate only while P still holds.
    pub fn admissible(self: *const Experiment, invalidated: bool) bool {
        if (self.producer.level().admitsWithoutGuard()) return true;
        return !invalidated;
    }
};

/// Guard invalidation: assumption false ⇒ realization inadmissible. There is
/// no third state; a guarded candidate either still holds or it does not.
pub const Invalidation = struct {
    experiment_proposition: []const u8,
    /// Stable identity of the next candidate selected after invalidation.
    fallback_candidate: []const u8,
};

/// Whether profile-shaped evidence is ever sufficient on its own for a
/// semantics-changing optimization. The answer is always no; this exists so
/// callers route through the fact instead of re-deriving it.
pub fn profileNeedsGuard(level: EpistemicLevel) bool {
    return !level.admitsWithoutGuard();
}

/// Bridge to the existing guard-emission taxonomy: map an emitted guard onto
/// its epistemic level. `none` is a proof, not an experiment.
pub fn levelForOutcomeEvidence(ev: optimization_outcome.Evidence) EpistemicLevel {
    return switch (ev) {
        .proven, .measured => .proven,
        .guarded => .guarded,
        .assumed => .heuristic,
        .profiled => .profiled,
        .estimated => .heuristic,
    };
}

test "effect: epistemic levels admit or require guard" {
    const std = @import("std");
    try std.testing.expect(EpistemicLevel.axiom.admitsWithoutGuard());
    try std.testing.expect(EpistemicLevel.proven.admitsWithoutGuard());
    try std.testing.expect(EpistemicLevel.inferred_sound.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.guarded.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.profiled.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.sampled.admitsWithoutGuard());
    try std.testing.expect(!EpistemicLevel.heuristic.admitsWithoutGuard());
}

test "effect: producers map to their epistemic level" {
    const std = @import("std");
    try std.testing.expectEqual(EpistemicLevel.proven, EvidenceProducer.static_proof.level());
    try std.testing.expectEqual(EpistemicLevel.inferred_sound, EvidenceProducer.invariant_inference.level());
    try std.testing.expectEqual(EpistemicLevel.guarded, EvidenceProducer.guard_observation.level());
    try std.testing.expectEqual(EpistemicLevel.profiled, EvidenceProducer.profile_counter.level());
    try std.testing.expectEqual(EpistemicLevel.profiled, EvidenceProducer.hardware_counter.level());
    try std.testing.expectEqual(EpistemicLevel.sampled, EvidenceProducer.sample.level());
    try std.testing.expectEqual(EpistemicLevel.heuristic, EvidenceProducer.heuristic_estimate.level());
}

test "effect: experiment admissibility follows invalidation and level" {
    const std = @import("std");
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

test "effect: profile evidence never admits alone" {
    const std = @import("std");
    try std.testing.expect(profileNeedsGuard(.profiled));
    try std.testing.expect(profileNeedsGuard(.sampled));
    try std.testing.expect(profileNeedsGuard(.heuristic));
    try std.testing.expect(!profileNeedsGuard(.proven));
}

test "effect: no assumption catalog lives here" {
    const std = @import("std");
    try std.testing.expect(!@hasDecl(@This(), "catalog"));
    try std.testing.expect(!@hasDecl(@This(), "experiment_catalog"));
    try std.testing.expect(!@hasDecl(@This(), "writeCatalogJson"));
}
