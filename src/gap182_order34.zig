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
