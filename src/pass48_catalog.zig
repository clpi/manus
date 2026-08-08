//! Pass 48 — The Duo Canonical Specification, SHC Edition (Phase 0: records only).
//!
//! Canonical spec: docs/plans/duo_canonical_specification.md
//! Operational:    docs/plans/pass48_canonical_specification.md
//!
//! This is a *consolidation*, not another pass: Passes 34–47 folded into one
//! authoritative grammar, semantic model, idiom canon and SHC contract. Its own
//! authority rule — "where any prior pass conflicts, this document wins and the
//! conflict is a supersession to record" — is what the gate checks hardest,
//! because a consolidation that silently overrides is worse than no consolidation.
const std = @import("std");

pub const SCHEMA_VERSION = "pass48-canonical-spec-v1";
pub const CANONICAL_PATH = "docs/archive/duo_canonical_specification.md";
pub const PLAN_PATH = "docs/archive/pass48_canonical_specification.md";

/// The authority rule, verbatim. Conflicts win *and get recorded*; silence
/// leaves the source pass normative.
pub const AUTHORITY_RULE =
    "Where any prior pass conflicts with this document, this document wins and " ++
    "the conflict is a supersession to record. Where this document is silent, " ++
    "the source pass remains normative.";

// ── Part I: Axioms ───────────────────────────────────────────────────────────

pub const Axiom = struct {
    id: []const u8,
    name: []const u8,
    statement: []const u8,
};

pub const axioms: []const Axiom = &.{
    .{ .id = "A1", .name = "HPLS", .statement = "maximum leverage, power, surface, projection algebra, clarity, elegance — per token of syntax" },
    .{ .id = "A2", .name = "NNS", .statement = "the grammar is closed; capability arrives as semantics of existing forms, never as new tokens/keywords/productions" },
    .{ .id = "A3", .name = "ONE EDGE", .statement = "every semantic relationship has exactly one canonical graph fact; all spellings are projections of it" },
    .{ .id = "A4", .name = "DEMAND", .statement = "nothing is physical unless consumed (IR invariant)" },
    .{ .id = "A5", .name = "WITNESS", .statement = "no optimization without an inspectable witness: legality, enabling facts, fallback, dependents" },
    .{ .id = "A6", .name = "BRIDGES", .statement = "nothing is blocked; every open decision carries a provisional contract every final decision can honor" },
    .{ .id = "A7", .name = "NATIVE-FIRST", .statement = "Duo semantics are canonical; Lua, Rust, Python, C, schemas are foreign projections with provenance and trust" },
    .{ .id = "A8", .name = "DESCENT", .statement = "no ladder rung ships without its way back down specified" },
    .{ .id = "A9", .name = "ORDINARY", .statement = "relations, namespaces, worlds, meta-layers, ranges, lenses, subtrees are ordinary first-class values" },
    .{ .id = "A10", .name = "SELF-PROOF", .statement = "the SHC is the style guide, benchmark and truth test; a correct but conventional compiler is a failure" },
};

// ── Part II: Surface grammar ─────────────────────────────────────────────────

/// The closed, compiler-owned operator inventory. A2 makes this list the
/// grammar's boundary: an addition is an NNS violation, not a feature.
pub const operators: []const []const u8 = &.{
    "==", "!=",  "<",  "<=",  ">",  ">=",
    "+",  "-",   "*",  "/",   "%",  "^",
    "&",  "|",   "~",  "<<",  ">>", "..",
    "#",  "and", "or", "not",
};

/// `@` is position-disambiguated completely: prefix = staging, postfix = anchoring.
pub const AtPosition = enum { prefix_staging, postfix_anchoring };

pub const AtRole = struct {
    id: []const u8,
    position: AtPosition,
    role: []const u8,
    example: []const u8,
};

pub const at_roles: []const AtRole = &.{
    .{ .id = "AT-01", .position = .prefix_staging, .role = "staged evaluation", .example = "@(expr)" },
    .{ .id = "AT-02", .position = .prefix_staging, .role = "staged/frozen table", .example = "@{ ... }" },
    .{ .id = "AT-03", .position = .prefix_staging, .role = "compiler surface", .example = "@comp.why" },
    .{ .id = "AT-04", .position = .postfix_anchoring, .role = "relation resolved at an anchor", .example = "Point@to(str)" },
};

/// Std relation families — frozen bindings, plus the SHC's own families created
/// by identical machinery (that identity is the point).
pub const std_relation_families: []const []const u8 = &.{
    "to",      "from", "eq",    "cmp",   "hash",    "format", "iter",
    "release", "ref",  "deref", "clone", "default", "get",    "set",
    "call",    "len",  "copy",  "share", "encode",  "decode",
};

/// §2.6 lists these; §2.8 additionally names `derive` and `observe` as
/// extension-point families, and Pass 52 builds its hook algebra on them. Both
/// lists describe the same machinery, so they are consolidated here — the gate
/// caught the omission by cross-checking Pass 52.
pub const shc_relation_families: []const []const u8 = &.{
    "lower",  "validate", "canonicalize", "realize", "rewrite", "measure",
    "derive", "observe",
};

// ── Part III: Semantic model ─────────────────────────────────────────────────

/// The resolution ladder, final at 8 rungs. Rung 3 is where sealed-world
/// collapse lands, and where SHC hot paths must live (G6).
pub const LadderRung = struct {
    rung: u8,
    name: []const u8,
};

pub const ladder: []const LadderRung = &.{
    .{ .rung = 1, .name = "lexical shadow (static)" },
    .{ .rung = 2, .name = "instance layer (capability-gated)" },
    .{ .rung = 3, .name = "exact descriptor relation" },
    .{ .rung = 4, .name = "descriptor hierarchy" },
    .{ .rung = 5, .name = "package/namespace extension" },
    .{ .rung = 6, .name = "authorized foreign relation" },
    .{ .rung = 7, .name = "generated/derived" },
    .{ .rung = 8, .name = "dynamic layer" },
};

pub const SEALED_COLLAPSE_RUNG: u8 = 3;

/// Precision order within a rung, and the blocking rule that goes with it.
pub const PRECISION_ORDER = "exact edge > subtree > family; explicit > generated";
pub const BLOCKING_RULE = "false blocks its covered region below; nil never blocks";

/// Conflict classes. Never last-write-wins — that is the whole point of having
/// classes at all.
pub const conflict_classes: []const []const u8 = &.{
    "equivalent", "specific",     "authority", "mergeable",
    "ambiguous",  "incompatible", "blocked",
};

// ── Part IV: Idiom canon ─────────────────────────────────────────────────────

pub const Idiom = struct {
    n: u8,
    statement: []const u8,
};

pub const idioms: []const Idiom = &.{
    .{ .n = 1, .statement = "operators first (a == b, not eq(a, b) mid-expression)" },
    .{ .n = 2, .statement = "operation-first invocation; anchors for retrieval, never invocation" },
    .{ .n = 3, .statement = "relations, subtrees, lenses, namespaces are values — pass them" },
    .{ .n = 4, .statement = "declare at the source, in the descriptor; never declare both ends of an edge" },
    .{ .n = 5, .statement = "let demand synthesize structural eq/hash/clone; block with false" },
    .{ .n = 6, .statement = "format(sink) primary; to(str) is its projection" },
    .{ .n = 7, .statement = "binding conditions for every lookup/parse/consume; guards for every early exit" },
    .{ .n = 8, .statement = "lenses over trivial lambdas; bound members over wrappers" },
    .{ .n = 9, .statement = "semantic variation = lexical shadow in a well-named function" },
    .{ .n = 10, .statement = "meta layers only when the layer matters; effective resolution otherwise" },
};

pub const smells: []const []const u8 = &.{
    "sigil archaeology (__, getmetatable, req, pairs)",
    "wrapper lambdas",
    "result objects where packs suffice",
    "eager tables/metatables/adapters just in case",
    "a curry level carrying a static fact",
    "hand dispatch where a trie or dispatch-table call exists",
    "fighting the formatter (the form, not the layout, is the bug)",
};

/// Canonical function spelling — the same one the repo-wide idiom gate enforces
/// at zero across every .duo file.
pub const CANONICAL_FUNCTION_FORM = "add = (a, b) a + b";

// ── Part V: SHC contract ─────────────────────────────────────────────────────

pub const Gate = struct {
    id: []const u8,
    statement: []const u8,
};

pub const gates: []const Gate = &.{
    .{ .id = "G1", .statement = "dialect containment (source subset of Duo-B)" },
    .{ .id = "G2", .statement = "idiomatic compression (no new wrappers)" },
    .{ .id = "G3", .statement = "semantic ownership (no side registries)" },
    .{ .id = "G4", .statement = "projection reuse (no repeated switches)" },
    .{ .id = "G5", .statement = "demand discipline (no unconsumed physical artifacts)" },
    .{ .id = "G6", .statement = "hot-path staticity (sealed-world resolution only)" },
    .{ .id = "G7", .statement = "witness integrity" },
    .{ .id = "G8", .statement = "N-directional consistency" },
    .{ .id = "G9", .statement = "bootstrap fixed point (S2 equals S3: graph, closure, manifests)" },
    .{ .id = "G10", .statement = "density ratchet (tokens, duplicate facts, dynamic boundaries)" },
};

/// Architectural shapes forbidden by default in the SHC.
pub const forbidden_architecture: []const []const u8 = &.{
    "visitor hierarchies",
    "repeated enum switches",
    "parallel node universes",
    "pass-pipeline-as-meaning",
    "boxed uniform object models",
    "protocol/intrinsic/trait registries beside the graph",
};

/// Bootstrap lifecycle — five states, in order.
pub const bootstrap_lifecycle: []const []const u8 = &.{
    "discovered", "specified", "implemented", "validated", "adopted",
};

// ── Part VI: Consolidated graveyard ──────────────────────────────────────────

pub const graveyard: []const []const u8 = &.{
    "req",
    "local",
    "pairs/ipairs/enumerate",
    "getmetatable/setmetatable",
    "__-anything",
    "~=",
    "match/pattern syntax",
    "traits/interfaces/impl blocks/derive/protocol keywords",
    "lifetime & ownership syntax",
    "trait objects & dictionary passing",
    "receiver binding",
    "postfix guards",
    "? ?. or= <?= ..<",
    "implicit-parameter lambdas",
    "implicit conversions",
    "transitive cast search",
    "arity-inferred currying",
    "parameter permutation",
    "static facts as curry levels",
    "duplicate to/from storage",
    "install/bind APIs",
    "within helpers",
    "visitor ownership of truth",
    "last-registration-wins",
};

// ── Emission ─────────────────────────────────────────────────────────────────

fn writeStrArray(w: *std.Io.Writer, key: []const u8, items: []const []const u8) !void {
    try w.print("\"{s}\":[", .{key});
    for (items, 0..) |it, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{it});
    }
    try w.writeAll("],");
}

pub fn writeJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",", .{SCHEMA_VERSION});
    try w.print("\"canonical\":\"{s}\",\"plan\":\"{s}\",", .{ CANONICAL_PATH, PLAN_PATH });
    try w.print("\"sealed_collapse_rung\":{d},", .{SEALED_COLLAPSE_RUNG});
    try w.print("\"canonical_function_form\":\"{s}\",", .{CANONICAL_FUNCTION_FORM});

    try w.writeAll("\"axioms\":[");
    for (axioms, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"name\":\"{s}\"}}", .{ a.id, a.name });
    }
    try w.writeAll("],");

    try w.writeAll("\"ladder\":[");
    for (ladder, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"rung\":{d},\"name\":\"{s}\"}}", .{ r.rung, r.name });
    }
    try w.writeAll("],");

    try w.writeAll("\"gates\":[");
    for (gates, 0..) |g, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\"}}", .{g.id});
    }
    try w.writeAll("],");

    try w.writeAll("\"idioms\":[");
    for (idioms, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"n\":{d}}}", .{d.n});
    }
    try w.writeAll("],");

    try writeStrArray(w, "operators", operators);
    try writeStrArray(w, "std_relation_families", std_relation_families);
    try writeStrArray(w, "shc_relation_families", shc_relation_families);
    try writeStrArray(w, "conflict_classes", conflict_classes);
    try writeStrArray(w, "forbidden_architecture", forbidden_architecture);
    try writeStrArray(w, "bootstrap_lifecycle", bootstrap_lifecycle);
    try writeStrArray(w, "smells", smells);
    try writeStrArray(w, "graveyard", graveyard);
    try w.print("\"authority_rule\":\"{s}\"}}", .{AUTHORITY_RULE});
}

test "pass48_catalog: emits structurally valid JSON" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeJson(&aw.writer);
    try aw.writer.flush();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "pass48_catalog: axiom and gate ids are unique" {
    for (axioms, 0..) |a, i| {
        for (axioms, 0..) |b, j| {
            if (i < j) try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
        }
    }
    for (gates, 0..) |a, i| {
        for (gates, 0..) |b, j| {
            if (i < j) try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
        }
    }
}
