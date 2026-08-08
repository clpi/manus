//! Pass 52 — No Magic: the anchoring homomorphism, edge hooks, the functional
//! closure (Phase 0: records only).
//!
//! Canonical spec: docs/plans/duo_no_magic.md
//! Operational:    docs/plans/pass52_no_magic.md
//!
//! The ruling: `satisfies` — and everything shaped like it — is deleted as a
//! primitive. The standing gate is the de-magicking test, and it is binary, so
//! this catalog is built to make failure representable: every standard-environment
//! name carries a `Justification`, and `side_registry` is one of the values.
const std = @import("std");

pub const SCHEMA_VERSION = "pass52-no-magic-v1";
pub const CANONICAL_PATH = "docs/archive/duo_no_magic.md";
pub const PLAN_PATH = "docs/archive/pass52_no_magic.md";

/// The de-magicking test, verbatim. G3 carries this.
pub const DEMAGICKING_TEST =
    "for every name in the standard environment, either (a) a user could define it " ++
    "with public machinery, or (b) it is a relation family on the one graph whose " ++
    "compiler-populated edges are inspectable, overridable, and blockable exactly " ++
    "like user edges. Anything failing both is a side registry (G3 violation).";

/// Exactly two justifications pass. The third exists so a violation can be
/// recorded rather than being unrepresentable — a catalog that cannot express
/// failure proves nothing.
pub const Justification = enum {
    user_definable,
    relation_family,
    side_registry,

    pub fn passes(self: Justification) bool {
        return self != .side_registry;
    }

    pub fn name(self: Justification) []const u8 {
        return @tagName(self);
    }
};

/// "Anything that answers a question about semantics is a relation family;
/// anything that merely computes is an ordinary function. No third category."
pub const Classification = enum { answers_about_semantics, merely_computes };

// ── §1 The anchoring homomorphism ────────────────────────────────────────────

/// `@` distributes over constraint tables: X@P anchors each entry at X and
/// yields (bundle, nil) or (nil, missing_set). Laws are checked as evidence
/// facts on the resolved edges; a failed law lands in missing_set with its
/// counterexample.
pub const HOMOMORPHISM_LAW = "X@(P union Q) = (X@P) union (X@Q); missing-sets union on failure";

pub const SatisfactionFace = struct {
    id: []const u8,
    face: []const u8,
    spelling: []const u8,
    mechanism: []const u8,
};

/// Three faces of one graph fact — each already in the language before Pass 52.
pub const satisfaction_faces: []const SatisfactionFace = &.{
    .{
        .id = "FACE-01",
        .face = "static",
        .spelling = "items: seq(ordering)",
        .mechanism = "the shape axis (:) — verified at compile time",
    },
    .{
        .id = "FACE-02",
        .face = "dynamic",
        .spelling = "if x = to(P)(v) ...",
        .mechanism = "narrowing — a derived conversion edge, P as target descriptor",
    },
    .{
        .id = "FACE-03",
        .face = "reflective",
        .spelling = "if b = X@P ...",
        .mechanism = "the homomorphism — proof as data; the bundle IS the proof",
    },
};

// ── §2 The former magic, respelled ───────────────────────────────────────────

pub const Respelling = struct {
    id: []const u8,
    was: []const u8,
    now: []const u8,
    justification: Justification,
    classification: Classification,
};

pub const respellings: []const Respelling = &.{
    .{
        .id = "RES-01",
        .was = "satisfies(d, P)",
        .now = "d@P",
        .justification = .relation_family,
        .classification = .answers_about_semantics,
    },
    .{
        .id = "RES-02",
        .was = "has(user, .name)",
        .now = "has(.name)(user) — a relation family, subject: container, param: lens",
        .justification = .relation_family,
        .classification = .answers_about_semantics,
    },
    .{
        .id = "RES-03",
        .was = "try_get(user, .address.city)",
        .now = "get(.address.city)(user) — correlated pack (value,nil)|(nil,missing_at)",
        .justification = .relation_family,
        .classification = .answers_about_semantics,
    },
    .{
        .id = "RES-04",
        .was = "range(0, n)",
        .now = "ordinary descriptor constructor — the exemplar of (a)",
        .justification = .user_definable,
        .classification = .merely_computes,
    },
    .{
        .id = "RES-05",
        .was = "meta, meta(level)",
        .now = "ordinary curried values",
        .justification = .user_definable,
        .classification = .merely_computes,
    },
    .{
        .id = "RES-06",
        .was = "load.module",
        .now = "ordinary effectful function returning a pack",
        .justification = .user_definable,
        .classification = .merely_computes,
    },
    .{
        .id = "RES-07",
        .was = "compare",
        .now = "projection of the cmp family",
        .justification = .relation_family,
        .classification = .answers_about_semantics,
    },
    .{
        .id = "RES-08",
        .was = "derive (the closure)",
        .now = "a trie — the hook system itself",
        .justification = .relation_family,
        .classification = .answers_about_semantics,
    },
};

// ── §3 Hooks are edge contributions ──────────────────────────────────────────

/// Every extension point is a relation family. The compiler's own behaviours are
/// pre-populated edges, inspectable and overridable like anything else.
pub const HookFamily = struct {
    id: []const u8,
    family: []const u8,
    example_edge: []const u8,
    compiler_populated: bool,
    inspectable_as: []const u8,
};

pub const hook_families: []const HookFamily = &.{
    .{ .id = "HOOK-01", .family = "derive", .example_edge = "derive(eq)(record) = structural_eq", .compiler_populated = true, .inspectable_as = "derive[eq]" },
    .{ .id = "HOOK-02", .family = "rewrite", .example_edge = "rewrite(fuse)(map_map) = fuse_maps", .compiler_populated = true, .inspectable_as = "rewrite[fuse]" },
    .{ .id = "HOOK-03", .family = "lower", .example_edge = "lower(arm64)(add_op) = lower_add_arm64", .compiler_populated = true, .inspectable_as = "lower[arm64]" },
    .{ .id = "HOOK-04", .family = "validate", .example_edge = "validate(wire)(packet) = check_packet", .compiler_populated = false, .inspectable_as = "validate[wire]" },
    .{ .id = "HOOK-05", .family = "observe", .example_edge = "observe(specialized)(on_spec) = log_spec", .compiler_populated = false, .inspectable_as = "observe[specialized]" },
    .{ .id = "HOOK-06", .family = "realize", .example_edge = "realize(simd)(dot) = dot_simd", .compiler_populated = false, .inspectable_as = "realize[simd]" },
};

/// The hook algebra is inherited from the trie, not designed.
pub const HookOperation = struct {
    id: []const u8,
    op: []const u8,
    mechanism: []const u8,
};

pub const hook_operations: []const HookOperation = &.{
    .{ .id = "HOP-01", .op = "override", .mechanism = "a more precise edge or a higher layer; lexical shadow" },
    .{ .id = "HOP-02", .op = "block", .mechanism = "= false at edge or subtree depth" },
    .{ .id = "HOP-03", .op = "remove", .mechanism = "= nil" },
    .{ .id = "HOP-04", .op = "inject", .mechanism = "spread a bundle, shadow a scope, pass a world fragment" },
    .{ .id = "HOP-05", .op = "stage", .mechanism = "the family's parameter, or a staged region" },
    .{ .id = "HOP-06", .op = "conflict", .mechanism = "the same nine classes, never last-write-wins" },
    .{ .id = "HOP-07", .op = "provenance", .mechanism = "every hook edge is witnessed" },
    .{ .id = "HOP-08", .op = "inspection", .mechanism = "trie reflection — the compiler is browsable as data" },
};

/// Graveyard shapes this replaces. A hook mechanism that is not edge
/// contribution is a side registry.
pub const graveyard: []const []const u8 = &.{
    "satisfaction as a primitive function",
    "presence as a primitive probe",
    "guarded-get as a primitive",
    "plugin APIs",
    "callback registries",
    "macro hooks",
    "magic std bindings",
};

// ── §4 The functional closure ────────────────────────────────────────────────

pub const AlgebraLaw = struct {
    id: []const u8,
    law: []const u8,
};

pub const algebra_laws: []const AlgebraLaw = &.{
    .{ .id = "ALG-01", .law = "constraint tables and bundles form a monoid under spread (right-biased, conflict-classified)" },
    .{ .id = "ALG-02", .law = HOMOMORPHISM_LAW },
    .{ .id = "ALG-03", .law = "currying gives sections everywhere: to(str), get(.name), derive(eq), meta(instance), lower(arm64)" },
    .{ .id = "ALG-04", .law = "lenses compose: .a.b = .a compose .b" },
    .{ .id = "ALG-05", .law = "packs are the product side" },
};

pub const Idiom = struct {
    id: []const u8,
    prefer: []const u8,
    over: []const u8,
};

pub const idioms: []const Idiom = &.{
    .{ .id = "IDIOM-01", .prefer = "items:map(to(str))", .over = "(x) to(str)(x)" },
    .{ .id = "IDIOM-02", .prefer = "lens composition", .over = "nested access lambdas" },
    .{ .id = "IDIOM-03", .prefer = "run(task, impls)", .over = "run(task, eq, cmp, hash)" },
    .{ .id = "IDIOM-04", .prefer = "Point@ordering", .over = "{ cmp = Point@cmp }" },
    .{ .id = "IDIOM-05", .prefer = "the clear pipeline, fused by law", .over = "the hand-fused loop" },
};

/// The point-free boundary stands: sections, lenses and named functions compose
/// freely; implicit-parameter lambdas remain rejected.
pub const IMPLICIT_PARAM_LAMBDAS_REJECTED = true;

pub const CANONICAL_FUNCTION_FORM = "add = (a, b) a + b";

// ── Emission ─────────────────────────────────────────────────────────────────

pub fn writeJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",", .{SCHEMA_VERSION});
    try w.print("\"canonical\":\"{s}\",\"plan\":\"{s}\",", .{ CANONICAL_PATH, PLAN_PATH });
    try w.print("\"homomorphism_law\":\"{s}\",", .{HOMOMORPHISM_LAW});
    try w.print("\"canonical_function_form\":\"{s}\",", .{CANONICAL_FUNCTION_FORM});
    try w.print("\"implicit_param_lambdas_rejected\":{},", .{IMPLICIT_PARAM_LAMBDAS_REJECTED});

    try w.writeAll("\"satisfaction_faces\":[");
    for (satisfaction_faces, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"face\":\"{s}\"}}", .{ f.id, f.face });
    }
    try w.writeAll("],");

    try w.writeAll("\"respellings\":[");
    for (respellings, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"justification\":\"{s}\",\"passes\":{}}}", .{
            r.id, r.justification.name(), r.justification.passes(),
        });
    }
    try w.writeAll("],");

    try w.writeAll("\"hook_families\":[");
    for (hook_families, 0..) |h, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"family\":\"{s}\",\"inspectable_as\":\"{s}\"}}", .{ h.id, h.family, h.inspectable_as });
    }
    try w.writeAll("],");

    try w.writeAll("\"hook_operations\":[");
    for (hook_operations, 0..) |o, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"op\":\"{s}\"}}", .{ o.id, o.op });
    }
    try w.writeAll("],");

    try w.writeAll("\"algebra_laws\":[");
    for (algebra_laws, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\"}}", .{a.id});
    }
    try w.writeAll("],");

    try w.writeAll("\"idioms\":[");
    for (idioms, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\"}}", .{d.id});
    }
    try w.writeAll("],");

    try w.writeAll("\"graveyard\":[");
    for (graveyard, 0..) |g, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{g});
    }
    try w.writeAll("]}");
}

test "pass52_catalog: emits structurally valid JSON" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeJson(&aw.writer);
    try aw.writer.flush();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "pass52_catalog: ids are unique within every table" {
    inline for (.{ satisfaction_faces, respellings, hook_families, hook_operations, algebra_laws, idioms }) |tbl| {
        for (tbl, 0..) |a, i| {
            for (tbl, 0..) |b, j| {
                if (i < j) try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
            }
        }
    }
}

test "pass52_catalog: the failure justification is representable" {
    // A catalog that cannot express a violation proves nothing about the gate.
    try std.testing.expect(!Justification.side_registry.passes());
    try std.testing.expect(Justification.user_definable.passes());
    try std.testing.expect(Justification.relation_family.passes());
}
