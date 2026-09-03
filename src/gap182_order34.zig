// GAP-182 orders 3+4 focused slice: graph-emitted experiment facts consumed
// through the one effect-side bridge (`law.fact.producer.one`). Own step so
// the parser-broken unit-test mass cannot mask this seam.
// Measured at e7b3dc0b + this diff: `zig build gap182-order34`.
const std = @import("std");
const assumption_guard = @import("assumption_guard.zig");
const semantic_graph = @import("semantic_graph.zig");
const effect = @import("effect.zig");
const sema = @import("sema.zig");
const ast = @import("ast.zig");

test "gap182: order 1 graph tuple emits with producer name and provenance face" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "order34.id", .start = 0, .end = 0 },
    });
    _ = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "order34.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    try assumption_guard.emitExperimentFacts(std.testing.allocator, &graph);
    try std.testing.expectEqual(@as(usize, 1), graph.experiments.items.len);
    try std.testing.expectEqualStrings(
        "guard_observation",
        graph.experiments.items[0].producer,
    );
}

test "gap182: order 3 graph-emitted guarded realization admits only under stated assumptions" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "order3.id", .start = 0, .end = 0 },
    });
    _ = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "order3.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    try assumption_guard.emitExperimentFacts(std.testing.allocator, &graph);
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
    const stated = [1][]const u8{emitted.items[0].predicate.name()};
    const guarded = try effect.fromExperimentFact(&graph.experiments.items[0], &stated);

    const affirm = [2]effect.RuntimeFact{
        (effect.observeFact(guarded.experiment.proposition, true, "rev:3") orelse
            return error.TestUnexpectedResult),
        (effect.observeFact(stated[0], true, "rev:3") orelse
            return error.TestUnexpectedResult),
    };
    const silent = [1]effect.RuntimeFact{
        (effect.observeFact(guarded.experiment.proposition, true, "rev:3") orelse
            return error.TestUnexpectedResult),
    };
    const candidates = [1]effect.Guarded{guarded};
    // Guard and stated assumption both affirmed ⇒ theorem admitted.
    try std.testing.expectEqualStrings(
        guarded.experiment.conditional_theorem,
        effect.refine(&candidates, "shape:never", &affirm).?,
    );
    // Stated assumption unanswered ⇒ inadmissible while the guard holds.
    try std.testing.expect(effect.refine(&candidates, "shape:never", &silent) == null);
    // No facts at all ⇒ inadmissible; absent affirmation is not affirmation.
    try std.testing.expect(effect.refine(&candidates, "shape:never", &.{}) == null);
}

test "gap182: order 4 named invalidation refutes the guarded candidate and deopt selects another" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "order4.id", .start = 0, .end = 0 },
    });
    _ = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "order4.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    try assumption_guard.emitExperimentFacts(std.testing.allocator, &graph);
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
    const stated = [1][]const u8{emitted.items[0].predicate.name()};
    const guarded = try effect.fromExperimentFact(&graph.experiments.items[0], &stated);

    const holds_all = struct {
        fn f(_: []const u8) bool {
            return true;
        }
    }.f;
    const survives = effect.Guarded{
        .experiment = .{
            .proposition = "kind:packed",
            .producer = .guard_observation,
            .cost = 1,
            .conditional_theorem = "cand:poly",
            .subject_revision = "rev:4",
        },
    };
    const pair = [2]effect.Guarded{ guarded, survives };

    // Before invalidation the first candidate holds under its assumptions.
    const refusal = effect.guardFalse(guarded.experiment.proposition, "rev:4") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(effect.invalidationRefutes(&refusal, &guarded.experiment));
    try std.testing.expect(!effect.invalidationRefutes(&refusal, &survives.experiment));
    // Named fact ⇒ refuted candidate ceases admissible and deopt selects the
    // surviving one — the exact `select` walk, never a second authority.
    try std.testing.expectEqualStrings(
        "cand:poly",
        effect.selectUnderInvalidation(&pair, &refusal, holds_all).?,
    );
    // An invalidation that names an unrelated proposition refutes nothing and
    // leaves the first (graph-emitted) candidate in place.
    const unrelated = effect.guardFalse("shape:elsewhere", "rev:4") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        guarded.experiment.conditional_theorem,
        effect.selectUnderInvalidation(&pair, &unrelated, holds_all).?,
    );
    // And with no survivor left, the answer is exactly `null` — the deopt
    // fallback composes verbatim upstream (`deoptOrFallback`).
    const alone = [1]effect.Guarded{guarded};
    try std.testing.expect(
        effect.selectUnderInvalidation(&alone, &refusal, holds_all) == null,
    );
}

test "gap182: bridge rejects a graph tuple with an unnamed producer" {
    // A producer identity the effect face cannot name is broken provenance;
    // the bridge constructs NO candidate, never a heuristic default
    // (`law.magic.code.zero`, `law.fact.producer.one`).
    const tuple = semantic_graph.ExperimentFact{
        .proposition = "guard:9",
        .producer = "never_emitted",
        .cost = 1,
        .conditional_theorem = "cand:none",
        .subject_revision = "rev:bridge",
    };
    try std.testing.expectError(
        effect.fromExperimentFactErrors.ProducerUnnamed,
        effect.fromExperimentFact(&tuple, &.{}),
    );
}

test "gap182: order 5 provenance evidence cannot become an applied outcome" {
    // The production conversion seam, end to end: an entry whose evidence is
    // an observation or estimate is recorded as a `profile_insufficient`
    // rejection naming the guard-or-proof demand — never an applied outcome
    // (`law.oracle.bounded`). The status `profile_insufficient` was already
    // named by the outcome schema; this test is its executed consumer.
    const optimization_outcome = @import("optimization_outcome.zig");
    const transform_engine = @import("transform_engine.zig");
    const alloc = std.testing.allocator;
    defer optimization_outcome.deinitSession(alloc);
    transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);
    transform_engine.logProvenance(alloc, "comp.why.boxed", .emit_call, 1, 2);
    var log = try optimization_outcome.fromProvenance(alloc);
    defer log.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), log.items.len);
    const outcome = log.items[0];
    try std.testing.expectEqual(
        optimization_outcome.Status.profile_insufficient,
        outcome.status,
    );
    try std.testing.expect(outcome.reason != null);
    try std.testing.expect(
        std.mem.indexOf(u8, outcome.reason.?, "demands a guard or proof") != null,
    );
    // The recorded evidence names WHAT was observed, never the truth it
    // cannot carry; its own level still refuses truth when re-asked.
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForOutcomeEvidence(outcome.evidence),
    ));
}

test "gap182: speculation construction enforces provenance" {
    // A speculation that cannot name the measured subject revision constructs
    // NO fact — null, never a fact with incomplete provenance
    // (`law.evidence.subject.one`).
    const no_rev = effect.speculate(
        "shape:42",
        "inline_cache",
        "generic",
        "",
        .profile_counter,
    );
    try std.testing.expect(no_rev == null);
}

test "gap182: speculation records guard, candidates, and evidence" {
    // The one construction seam produces a named fact carrying the guard
    // proposition, both candidate identities, the measured subject revision,
    // and the evidence producer — all recoverable from the fact's own fields
    // (`law.magic.code.zero`).
    const s = effect.speculate(
        "shape:42",
        "inline_cache",
        "generic",
        "rev-abc",
        .hardware_counter,
    ).?;
    try std.testing.expectEqualStrings("shape:42", s.guard_proposition);
    try std.testing.expectEqualStrings("inline_cache", s.applied_candidate);
    try std.testing.expectEqualStrings("generic", s.fallback_candidate);
    try std.testing.expectEqualStrings("rev-abc", s.subject_revision);
    try std.testing.expectEqual(effect.EvidenceProducer.hardware_counter, s.evidence);
    // The epistemic level is recovered from the producer — one taxonomy,
    // no second priority table.
    try std.testing.expectEqual(effect.EpistemicLevel.profiled, s.level());
    // Hardware-counter evidence is evidence only, never semantic truth.
    try std.testing.expect(!s.producesTruth());
}

test "gap182: speculation deopt selects fallback" {
    // When the guard is invalidated, the fallback candidate is selected —
    // the speculatively applied transformation is no longer admissible.
    const s = effect.speculate(
        "shape:42",
        "inline_cache",
        "generic",
        "rev-abc",
        .profile_counter,
    ).?;
    try std.testing.expectEqualStrings("generic", s.deopt());
}

test "gap182: sound speculation produces truth" {
    // A speculation backed by static proof produces semantic truth —
    // its theorem did not depend on any measurement.
    const s = effect.speculate(
        "type:i64",
        "unbox",
        "boxed",
        "rev-abc",
        .static_proof,
    ).?;
    try std.testing.expect(s.producesTruth());
    try std.testing.expectEqual(effect.EpistemicLevel.proven, s.level());
}

fn appendExperiment(
    graph: *semantic_graph.SemanticGraph,
    proposition: []const u8,
    producer: []const u8,
    revision: []const u8,
) !void {
    const alloc = std.testing.allocator;
    try graph.experiments.append(alloc, .{
        .proposition = try alloc.dupe(u8, proposition),
        .producer = try alloc.dupe(u8, producer),
        .cost = 1,
        .conditional_theorem = try alloc.dupe(u8, "cand:narrow"),
        .subject_revision = try alloc.dupe(u8, revision),
    });
}

test "gap182: graph enforcement refuses evidence experiments without a graph guard" {
    // The graph-owned face of the evidence-only rule: an experiment fact whose
    // producer is an evidence producer (profile counter, hardware counter,
    // sample, heuristic estimate) is inadmissible unless the GRAPH carries a
    // guard over the same proposition — the effect-side law
    // (`profileNeedsGuard`) enforced over the graph's own facts, so no
    // optimizer path reading `graph.experiments` can bypass it.
    {
        // Evidence with full provenance but no graph-carried guard: refused.
        var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
        defer graph.deinit();
        try appendExperiment(&graph, "shape:7", "profile_counter", "rev:9");
        try std.testing.expectError(
            error.EvidenceUnguarded,
            assumption_guard.enforceExperimentGuards(&graph),
        );
    }
    {
        // Evidence naming no measured subject revision: refused on provenance
        // before coverage is even asked (`law.evidence.subject.one`).
        var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
        defer graph.deinit();
        try appendExperiment(&graph, "shape:7", "hardware_counter", "");
        try std.testing.expectError(
            error.EvidenceRevisionMissing,
            assumption_guard.enforceExperimentGuards(&graph),
        );
    }
    {
        // An unnamed producer constructs NO verdict — never a default
        // (`law.fact.producer.one`, `law.magic.code.zero`).
        var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
        defer graph.deinit();
        try appendExperiment(&graph, "shape:7", "never_emitted", "rev:9");
        try std.testing.expectError(
            error.ProducerUnnamed,
            assumption_guard.enforceExperimentGuards(&graph),
        );
    }
}

test "gap182: graph enforcement admits evidence only under the graph-carried guard" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "enforce.id", .start = 0, .end = 0 },
    });
    _ = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "enforce.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    // The guard's own observation witness passes on its fact alone.
    try assumption_guard.emitExperimentFacts(std.testing.allocator, &graph);
    try assumption_guard.enforceExperimentGuards(&graph);
    // Evidence over the SAME proposition the graph-carried guard names
    // ("guard:1" — the guarded node above), with measured revision: admitted.
    try appendExperiment(&graph, "guard:1", "hardware_counter", "rev:11");
    try assumption_guard.enforceExperimentGuards(&graph);
    // Sound producers (static proof) admit with no guard and no revision.
    try appendExperiment(&graph, "shape:1", "static_proof", "");
    try assumption_guard.enforceExperimentGuards(&graph);
    // Evidence over a proposition NO graph-carried guard names: refused —
    // a guard over a different proposition covers nothing.
    try appendExperiment(&graph, "guard:99", "sample", "rev:11");
    try std.testing.expectError(
        error.EvidenceUnguarded,
        assumption_guard.enforceExperimentGuards(&graph),
    );
}
