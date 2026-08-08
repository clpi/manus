//! Pass 36/40/41 — Final semantic access and projection calculus.
//!
//! Phase 0: records only. The calculus is written down in machine-readable form
//! so the gate can prove it is internally consistent *before* any parser or sema
//! change is attempted.
//!
//! Supersession history carried by this catalog (see `supersessions`):
//!   S4 — Pass 39's postfix `value@op` ruling is REVERSED. Prefix `@` only.
//!   S5 — Pass 38 §§1-3,6,13 (postfix grammar, receiver binding, `@(level)@`)
//!        superseded by Pass 40 §1. Pass 38 §§4-5,7-12,14-16 retained in full.
//!   S6 — Pass 39 R1 dissolves; the ambiguity class it arbitrated cannot arise.
//!   S7 — Pass 41: backwards compatibility removed as a design constraint. Lua
//!        is a foreign projection target, not an ecosystem invariant.
//!
//! Canonical spec: docs/plans/duo_universal_semantic_access.md
//! Operational:    docs/plans/pass36_universal_semantic_access.md
const std = @import("std");

pub const SCHEMA_VERSION = "pass40-semantic-access-catalog-v2";
pub const CANONICAL_PATH = "docs/plans/duo_universal_semantic_access.md";
pub const PLAN_PATH = "docs/plans/pass36_universal_semantic_access.md";

// ── Semantic levels ───────────────────────────────────────────────────────────

/// The layers a semantic relation may live at. Pass 41 A3 compacted the ladder
/// from ten rungs to eight by deleting the separate Lua-metamethod rung: Lua
/// values now enter at `foreign` like every other foreign value, and `dynamic`
/// is a Duo-defined semantic layer rather than a replay of Lua lookup rules.
pub const SemanticLevel = enum {
    lexical,
    instance,
    descriptor,
    descriptor_hierarchy,
    package,
    foreign,
    generated,
    dynamic,
    effective,
    failure,
};

/// Pass 40 §1 — levels addressable through `meta(level)(value)`. This is an
/// ordinary curried stdlib callable, not grammar: the level is a value, so it is
/// passable, mappable, and storable like any other.
pub const LevelSelector = struct {
    level: SemanticLevel,
    spelling: []const u8,
    assignable: bool,
};

pub const level_selectors: []const LevelSelector = &.{
    .{ .level = .lexical, .spelling = "meta(lexical)(value)", .assignable = true },
    .{ .level = .instance, .spelling = "meta(instance)(value)", .assignable = true },
    .{ .level = .descriptor, .spelling = "meta(descriptor)(value)", .assignable = true },
    .{ .level = .package, .spelling = "meta(package)(value)", .assignable = true },
    .{ .level = .foreign, .spelling = "meta(foreign)(value)", .assignable = true },
    .{ .level = .dynamic, .spelling = "meta(dynamic)(value)", .assignable = true },
    .{ .level = .effective, .spelling = "meta(value)", .assignable = false },
};

// ── Access forms (Pass 40 §1) ─────────────────────────────────────────────────

pub const AccessKind = enum {
    ordinary,
    semantic_world,
    semantic_identity,
    semantic_invocation,
    semantic_member,
    level_view,
    semantic_assignment,
    staging,
};

/// One surface form. `desugars_to` must name another form's `id`, or `CANONICAL`
/// when the form is itself the normal form. The gate proves the desugaring graph
/// is closed and acyclic.
///
/// `receiver_bound` is false for every form. That is the point: Pass 40 §0.1's
/// decisive performance argument is that `.@name` retrieval is *never*
/// receiver-bound, so the descriptor-vs-subject ambiguity class does not exist.
pub const AccessForm = struct {
    id: []const u8,
    kind: AccessKind,
    syntax: []const u8,
    desugars_to: []const u8,
    owner: SemanticLevel,
    receiver_bound: bool,
    note: []const u8,
};

pub const CANONICAL = "CANONICAL";

pub const access_forms: []const AccessForm = &.{
    .{ .id = "A-ORD", .kind = .ordinary, .syntax = "point.x", .desugars_to = CANONICAL, .owner = .effective, .receiver_bound = false, .note = "`.` is the only access operator; ordinary member/key access" },
    .{ .id = "A-WORLD", .kind = .semantic_world, .syntax = "@", .desugars_to = CANONICAL, .owner = .lexical, .receiver_bound = false, .note = "the current semantic world as a value; passable per run(world)(input)" },
    .{ .id = "A-ID", .kind = .semantic_identity, .syntax = "@eq", .desugars_to = "A-WORLD", .owner = .lexical, .receiver_bound = false, .note = "semantic identity in the current world; @.eq names the same key" },
    .{ .id = "A-CALL", .kind = .semantic_invocation, .syntax = "@eq(a, b)", .desugars_to = CANONICAL, .owner = .lexical, .receiver_bound = false, .note = "operation-first invocation; the normal form every equality spelling converges on" },
    .{ .id = "A-PARAM", .kind = .semantic_invocation, .syntax = "@to(str)", .desugars_to = "A-ID", .owner = .lexical, .receiver_bound = false, .note = "parameterized relation selection; first group only, yields a converter value" },
    .{ .id = "A-SPINE", .kind = .semantic_invocation, .syntax = "@to(str)(p)", .desugars_to = "A-PARAM", .owner = .lexical, .receiver_bound = false, .note = "two-group application spine; the group boundary is the specialization boundary" },
    .{ .id = "A-PARENLESS", .kind = .semantic_invocation, .syntax = "@to str", .desugars_to = "A-PARAM", .owner = .lexical, .receiver_bound = false, .note = "parenless FIRST group only, atomic argument; later groups always need parens" },
    .{ .id = "A-MEMBER", .kind = .semantic_member, .syntax = "point.@eq", .desugars_to = CANONICAL, .owner = .effective, .receiver_bound = false, .note = "semantic member access: RETRIEVAL, never binding; this is what removes the ambiguity class" },
    .{ .id = "A-MEMBER-PARAM", .kind = .semantic_member, .syntax = "point.@to(str)", .desugars_to = "A-MEMBER", .owner = .effective, .receiver_bound = false, .note = "parameterized slot retrieval" },
    .{ .id = "A-OP", .kind = .semantic_invocation, .syntax = "a == b", .desugars_to = "A-CALL", .owner = .effective, .receiver_bound = false, .note = "operator projection; normalizes to the same call identity as @eq(a, b)" },
    .{ .id = "A-META", .kind = .level_view, .syntax = "meta(value)", .desugars_to = CANONICAL, .owner = .effective, .receiver_bound = false, .note = "effective semantic view; an ordinary stdlib callable, not grammar" },
    .{ .id = "A-META-LEVEL", .kind = .level_view, .syntax = "meta(instance)(value)", .desugars_to = "A-META", .owner = .instance, .receiver_bound = false, .note = "exact-level view; curried, so the level is a first-class passable value" },
    .{ .id = "A-ASSIGN-LEX", .kind = .semantic_assignment, .syntax = "@eq = local_eq", .desugars_to = CANONICAL, .owner = .lexical, .receiver_bound = false, .note = "STATEMENT position: lexical world binding, statically resolvable (R2)" },
    .{ .id = "A-ASSIGN-SLOT", .kind = .semantic_assignment, .syntax = "{ @eq = point_eq }", .desugars_to = CANONICAL, .owner = .descriptor, .receiver_bound = false, .note = "TABLE literal: descriptor slot declaration; the idiomatic primary definition site" },
    .{ .id = "A-ASSIGN-VAL", .kind = .semantic_assignment, .syntax = "point.@eq = impl", .desugars_to = CANONICAL, .owner = .effective, .receiver_bound = false, .note = "assignment at the value's own level, subject to its mutability" },
    .{ .id = "A-ASSIGN-LEVEL", .kind = .semantic_assignment, .syntax = "meta(package)(geometry).@eq = geo_eq", .desugars_to = "A-META-LEVEL", .owner = .package, .receiver_bound = false, .note = "exact-level write; policy-gated" },
    .{ .id = "A-STAGE", .kind = .staging, .syntax = "@(expr)", .desugars_to = CANONICAL, .owner = .lexical, .receiver_bound = false, .note = "staging application; prefix-only, so it can never collide with a postfix form" },
    .{ .id = "A-STAGE-TABLE", .kind = .staging, .syntax = "@{ ... }", .desugars_to = "A-STAGE", .owner = .lexical, .receiver_bound = false, .note = "staged/frozen table literal; not a separate table kind" },
};

// ── Graveyard: permanently rejected syntax ────────────────────────────────────

/// Consolidated from Pass 36 §25, Pass 39, Pass 40 §1, and Pass 41 A2/A5/A8.
/// A rejected form is not "unimplemented" — it is a decision with a reason, and
/// the gate proves no access form resurrects one.
pub const RejectedForm = struct {
    syntax: []const u8,
    reason: []const u8,
};

pub const graveyard: []const RejectedForm = &.{
    .{ .syntax = "value@name", .reason = "S4: postfix gives `@` three unrelated jobs; composition buys the same power without grammar" },
    .{ .syntax = "value @ name", .reason = "infix `@` collides with semantic access and reads as an arithmetic operator" },
    .{ .syntax = "value:@name", .reason = "`:` is receiver-binding sugar for ordinary members and never touches semantic space" },
    .{ .syntax = "value@(level)@name", .reason = "S5: replaced by the ordinary curried value meta(level)(value)" },
    .{ .syntax = "duplicate @to/@from storage", .reason = "one edge, two views; declaring both ends is the duplicate-truth error" },
    .{ .syntax = "arity-inferred currying", .reason = "grouping comes from the declared schema, never from punctuation or arity" },
    .{ .syntax = "automatic parameter permutation", .reason = "argument order is part of the operation's identity" },
    .{ .syntax = "install/bind APIs", .reason = "scope and assignment already express every level" },
    .{ .syntax = "within-style helpers", .reason = "a lexical world binding names the scope directly" },
    .{ .syntax = "getmetatable / setmetatable", .reason = "A8: deleted; meta(dynamic)(v) does everything, the adapter maps them at the Lua boundary" },
    .{ .syntax = "@eq(bool)(comparable)", .reason = "static facts as curry levels; result descriptors and domain constraints are graph facts, not call ceremony" },
    .{ .syntax = "~=", .reason = "A5: `!=` wins on universal intuition; the operator inventory is chosen on merit, not inherited" },
    .{ .syntax = "__eq / __index / __tostring as canon", .reason = "A2: the `__` namespace is deleted; these survive only as @lua adapter emission targets" },
    .{ .syntax = "__index-chain inheritance", .reason = "A4: descriptor hierarchy projection is the only inheritance mechanism" },
};

// ── Grammar (Pass 40 §1) ──────────────────────────────────────────────────────

pub const GrammarStatus = enum {
    /// Recorded, not implemented — Phase 0 default.
    recorded,
    /// Recorded and implemented in the parser.
    implemented,
    /// Recorded but cannot be implemented until a supersession closes.
    blocked,
};

pub const GrammarRule = struct {
    id: []const u8,
    form: []const u8,
    meaning: []const u8,
    status: GrammarStatus,
    /// Supersession id that must reach `adopted` first, or "NONE".
    blocked_by: []const u8,
    /// Whether parentheses are mandatory.
    parens_required: bool,
};

/// One token class (`@name`) plus one spine rule. Contrast the postfix surface,
/// which needed three patch rulings, a precedence table, and a staging-collision
/// rule — the grammar-cost row of the Pass 40 scorecard.
pub const grammar_rules: []const GrammarRule = &.{
    .{ .id = "G1", .form = "@name", .meaning = "semantic identity in the current world", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G2", .form = "@", .meaning = "the current semantic world as a value", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G3", .form = "@name(args)", .meaning = "invocation through the current world", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G4", .form = "@name(param)(subject)", .meaning = "two-group application spine", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G5", .form = "@name param", .meaning = "parenless first group, atomic argument only", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    // First form of the calculus to actually exist in the compiler (2026-08-07).
    // The parser accepts `@` after `.` in the postfix chain and carries the
    // sigil in the field name; codegen lowers it to the `__name` metafield per
    // §8.5. Proven by examples/pass38_semantic_access_g6.duo (5 checks, fails
    // by exit status, negative control verified).
    .{ .id = "G6", .form = "value.@name", .meaning = "semantic member access; retrieval, never binding", .status = .implemented, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G7", .form = "@name = value", .meaning = "statement position: lexical world binding", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G8", .form = "{ @name = value }", .meaning = "table literal: descriptor slot declaration", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G9", .form = "value.@name = value", .meaning = "assignment at the value's own level", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
    .{ .id = "G10", .form = "@(expr)", .meaning = "staging application; prefix-only", .status = .recorded, .blocked_by = "NONE", .parens_required = true },
    .{ .id = "G11", .form = "@{ ... }", .meaning = "staged/frozen table literal", .status = .recorded, .blocked_by = "NONE", .parens_required = false },
};

// ── Supersessions ─────────────────────────────────────────────────────────────

pub const SupersessionStatus = enum { discovered, specified, implemented, adopted };

/// A convergence record. Pass 39's governance rule stands: any future
/// contradiction of this canon ships with a supersession record or is not canon.
pub const Supersession = struct {
    id: []const u8,
    ruling: []const u8,
    supersedes: []const u8,
    rationale: []const u8,
    status: SupersessionStatus,
};

pub const supersessions: []const Supersession = &.{
    .{
        .id = "S4",
        .ruling = "prefix `@` only; postfix, infix and `:@` forms rejected permanently",
        .supersedes = "Pass 39's ruling that postfix `value@op` superseded Pass 36's prohibition",
        .rationale = "re-scored on surface, power, performance and meaning: everything postfix bought with grammar, composition buys without it",
        .status = .adopted,
    },
    .{
        .id = "S5",
        .ruling = "Pass 38 §§1-3,6,13 superseded by Pass 40 §1; §§4-5,7-12,14-16 retained in full",
        .supersedes = "Pass 38 access grammar, receiver binding, hierarchy-selection syntax",
        .rationale = "the projection closure is graph-level and independent of spelling, so nothing in it is lost by respelling",
        .status = .adopted,
    },
    .{
        .id = "S6",
        .ruling = "Pass 39 R1 dissolves; R2 through R6 carry forward",
        .supersedes = "Pass 39 R1 (descriptor-vs-subject role inference)",
        .rationale = "retrieval is never receiver-bound, so the ambiguity class R1 arbitrated cannot arise",
        .status = .adopted,
    },
    .{
        .id = "S7",
        .ruling = "backwards compatibility removed as a design constraint; Lua is a foreign projection target",
        .supersedes = "every 'public Lua-compatible behavior never changes' clause across Passes 34-40",
        .rationale = "compat was never a decisive input to the Pass 40 scorecard; deleting it removes two ladder rungs, one inheritance mechanism, and the `__` namespace",
        .status = .adopted,
    },
};

// ── Resolution ladder (Pass 41 A3) ────────────────────────────────────────────

pub const ResolutionStep = struct {
    order: u8,
    level: SemanticLevel,
    description: []const u8,
};

/// Eight rungs, down from ten. Rungs 8 (Lua metamethod projection) and 9
/// (dynamic metatable fallback) were two rungs only because Lua's lookup rules
/// had to be replayed verbatim; A3 merges them into one Duo-defined dynamic
/// layer. Two fewer rungs to disprove means more sites reach the rung-3 proof
/// with less evidence — a performance win purchased purely by deleting
/// inherited semantics.
pub const resolution_order: []const ResolutionStep = &.{
    .{ .order = 1, .level = .lexical, .description = "lexical override (statically resolvable; costs nothing if absent)" },
    .{ .order = 2, .level = .instance, .description = "instance semantic layer (capability-gated: sealed records forbid, plain tables allow)" },
    .{ .order = 3, .level = .descriptor, .description = "exact descriptor relation" },
    .{ .order = 4, .level = .descriptor_hierarchy, .description = "descriptor hierarchy projection (the only inheritance mechanism)" },
    .{ .order = 5, .level = .package, .description = "package/namespace extension" },
    .{ .order = 6, .level = .foreign, .description = "authorized foreign relation (Lua values enter here, like all foreign values)" },
    .{ .order = 7, .level = .generated, .description = "generated/derived relation" },
    .{ .order = 8, .level = .dynamic, .description = "dynamic semantic layer (Duo-defined @get/@set/@call lookups, not Lua metatable walk rules)" },
    .{ .order = 9, .level = .failure, .description = "structured failure (nil, err — a return pack, never an exception)" },
};

/// The fields the single resolved semantic call object carries.
pub const call_object_fields: []const []const u8 = &.{
    "active operation identity",
    "receiver",
    "remaining arguments",
    "descriptor identities",
    "expected return pack",
    "scope provenance",
    "effects",
    "stage",
    "target",
    "selected implementation",
};

/// Pass 40 §2 (R5) — the conjunction that collapses the ladder to rung 3 as a
/// proof rather than a heuristic. G5 fails any compiler hot region that resolves
/// above rung 3.
pub const sealed_world_conditions: []const []const u8 = &.{
    "no lexical overrides (static)",
    "instance semantics forbidden by descriptor",
    "descriptor sealed",
    "package layer frozen (L1)",
    "world frozen-captured",
};

pub const sealed_world_guarantees: []const []const u8 = &.{
    "identity conversion = 0 instructions",
    "point.@to(str) and @to(str) = compile-time constants",
    "sealed @iter = native loop, zero iterator allocation",
    "@release tier 1 = inlined at last use",
    "derived structural ops = direct field code",
    "no closure, wrapper, metatable, registry search, or intermediate string",
};

// ── Projection families (Pass 38 §8, §10 — retained by S5) ────────────────────

pub const ProjectionFamily = struct {
    id: []const u8,
    section: []const u8,
    title: []const u8,
    /// Generated only on demand, never eagerly.
    demand_driven: bool,
    /// Whether the family can ever produce a physical artifact. Purely
    /// normalizing families never materialize.
    materializes: bool,
    note: []const u8,
};

pub const projection_families: []const ProjectionFamily = &.{
    .{ .id = "P-ENDPOINT", .section = "8.1", .title = "endpoint", .demand_driven = true, .materializes = false, .note = "one edge, several orientations: @to(str) on point IS str.@from(point)" },
    .{ .id = "P-INVOKE", .section = "8.2", .title = "invocation", .demand_driven = true, .materializes = false, .note = "normalized spellings, not generated wrappers unless reflection needs values" },
    .{ .id = "P-PARTIAL", .section = "8.3", .title = "partial application", .demand_driven = true, .materializes = true, .note = "@eq(a) derived from the declared schema, never from arity" },
    .{ .id = "P-OPERATOR", .section = "8.4", .title = "operator", .demand_driven = false, .materializes = false, .note = "closed compiler-owned set; no user-defined operators" },
    .{ .id = "P-FOREIGN-LUA", .section = "8.5", .title = "Lua adapter", .demand_driven = true, .materializes = true, .note = "A1: one row of the foreign-projection family, not an ecosystem invariant" },
    .{ .id = "P-PRODUCT", .section = "8.6", .title = "structural product", .demand_driven = true, .materializes = true, .note = "record operations project field-wise" },
    .{ .id = "P-SUM", .section = "8.7", .title = "variant/sum", .demand_driven = true, .materializes = true, .note = "tag then payload; visitors and per-variant test coverage" },
    .{ .id = "P-HIER", .section = "8.8", .title = "hierarchy", .demand_driven = true, .materializes = false, .note = "five inheritance kinds: implementation, derivation, evidence, availability, nothing" },
    .{ .id = "P-CONSTRAINT", .section = "8.9", .title = "constraint", .demand_driven = true, .materializes = false, .note = "@cmp implies @eq; @hash never from @eq alone; projects backward too" },
    .{ .id = "P-EVIDENCE", .section = "8.10", .title = "evidence", .demand_driven = true, .materializes = false, .note = "tests, proofs, fuzzing, foreign metadata, runtime observations on one edge" },
    .{ .id = "P-STAGE", .section = "8.11", .title = "stage", .demand_driven = true, .materializes = true, .note = "compile time, startup, runtime, adaptive runtime, device" },
    .{ .id = "P-REPR", .section = "8.12", .title = "representation", .demand_driven = true, .materializes = true, .note = "representation stays independent of semantic identity" },
    .{ .id = "P-RETURN", .section = "8.13", .title = "return consumption", .demand_driven = true, .materializes = true, .note = "unused result work disappears where semantically legal" },
    .{ .id = "P-EFFECT", .section = "8.14", .title = "effect", .demand_driven = true, .materializes = true, .note = "effects are graph facts, not separate protocol names" },
    .{ .id = "P-TARGET", .section = "8.15", .title = "target", .demand_driven = true, .materializes = true, .note = "scalar CPU, SIMD, GPU, Wasm, foreign, compile-time" },
    .{ .id = "P-FOREIGN", .section = "8.16", .title = "cross-language", .demand_driven = true, .materializes = true, .note = "Rust, Python, C, C++, Java, TS, SQL, OpenAPI, protobuf, Wasm components" },
    .{ .id = "P-TOOLING", .section = "8.17", .title = "tooling", .demand_driven = true, .materializes = false, .note = "tooling consumes compiler truth and stable IDs, never reimplements resolution" },
    .{ .id = "P-DOCTEST", .section = "8.18", .title = "documentation and testing", .demand_driven = true, .materializes = true, .note = "generalizes the Ward one-descriptor-many-artifacts pattern" },
    .{ .id = "P-REVERSE", .section = "8.19", .title = "reverse / N-directional", .demand_driven = true, .materializes = false, .note = "candidate updates arrive as validated transactions, never silent mutation" },
    .{ .id = "P-CAPABILITY", .section = "10.1", .title = "capability", .demand_driven = true, .materializes = true, .note = "sandbox policies, WASI rights, seccomp profiles, MCP scopes" },
    .{ .id = "P-TRUST", .section = "10.2", .title = "privacy and trust", .demand_driven = true, .materializes = true, .note = "secret, untrusted, personal, sanitized, logging-forbidden, export-restricted" },
    .{ .id = "P-MIGRATION", .section = "10.3", .title = "migration", .demand_driven = true, .materializes = true, .note = "serialized data, database, live state, foreign API, durable continuation" },
    .{ .id = "P-OBSERVE", .section = "10.4", .title = "observability", .demand_driven = true, .materializes = true, .note = "instrumentation is removable and attached to semantic identities" },
    .{ .id = "P-HARDEN", .section = "10.5", .title = "security hardening", .demand_driven = true, .materializes = true, .note = "checks, guards, sanitizers, hardened and unchecked-proven variants" },
    .{ .id = "P-BUILD", .section = "10.6", .title = "build", .demand_driven = true, .materializes = true, .note = "build edges, cache keys, invalidation, hermeticity, artifact manifests" },
    .{ .id = "P-COMPAT", .section = "10.7", .title = "package compatibility", .demand_driven = true, .materializes = false, .note = "source, ABI, behavior, effect, serialization; semantic version impact" },
    .{ .id = "P-AGENT", .section = "10.8", .title = "agent action", .demand_driven = true, .materializes = false, .note = "safe semantic transactions an agent may propose" },
};

// ── Operator inventory (Pass 41 A5) ───────────────────────────────────────────

/// A closed, compiler-owned projection set — no user-defined operators; that
/// guard is elegance, not compat. Pass 41 A5 changes the inventory's *contents*
/// from inherited to chosen: `!=` replaces `~=`, and future operator questions
/// are settled by numeric speciation (L8) rather than by precedent.
pub const OperatorProjection = struct {
    root: []const u8,
    syntax: []const u8,
    /// True when the spelling was selected on merit against inherited syntax.
    chosen_over_inherited: bool,
};

pub const operator_projections: []const OperatorProjection = &.{
    .{ .root = "@eq", .syntax = "==", .chosen_over_inherited = false },
    .{ .root = "@eq", .syntax = "!=", .chosen_over_inherited = true },
    .{ .root = "@cmp", .syntax = "< <= > >=", .chosen_over_inherited = false },
    .{ .root = "@add", .syntax = "+", .chosen_over_inherited = false },
    .{ .root = "@sub", .syntax = "-", .chosen_over_inherited = false },
    .{ .root = "@mul", .syntax = "*", .chosen_over_inherited = false },
    .{ .root = "@div", .syntax = "/", .chosen_over_inherited = false },
    .{ .root = "@mod", .syntax = "%", .chosen_over_inherited = false },
    .{ .root = "@pow", .syntax = "^", .chosen_over_inherited = false },
    .{ .root = "@concat", .syntax = "..", .chosen_over_inherited = false },
    .{ .root = "@len", .syntax = "#", .chosen_over_inherited = false },
    .{ .root = "@get", .syntax = "indexing/member access", .chosen_over_inherited = false },
    .{ .root = "@set", .syntax = "indexed/member assignment", .chosen_over_inherited = false },
    .{ .root = "@call", .syntax = "ordinary call", .chosen_over_inherited = false },
    .{ .root = "@iter", .syntax = "generic for", .chosen_over_inherited = false },
};

/// Pass 41 A2 — the `__` names are no longer canon. They survive only inside the
/// `@lua` adapter as emission targets: spelling details of one foreign ABI, no
/// more canonical than a Rust `PartialEq` impl. Emitted on demand at the
/// boundary only, with provenance.
pub const LuaAdapterTarget = struct {
    root: []const u8,
    emits: []const u8,
};

pub const lua_adapter_targets: []const LuaAdapterTarget = &.{
    .{ .root = "@eq", .emits = "__eq" },
    .{ .root = "@cmp", .emits = "__lt / __le" },
    .{ .root = "@add", .emits = "__add" },
    .{ .root = "@get", .emits = "__index" },
    .{ .root = "@set", .emits = "__newindex" },
    .{ .root = "@call", .emits = "__call" },
    .{ .root = "@len", .emits = "__len" },
    .{ .root = "@concat", .emits = "__concat" },
    .{ .root = "@format", .emits = "__tostring" },
    .{ .root = "@release", .emits = "__close / __gc" },
};

// ── Demand and erasure (Pass 38 §9 — retained by S5) ──────────────────────────

pub const DemandSource = struct {
    id: []const u8,
    trigger: []const u8,
};

pub const demand_sources: []const DemandSource = &.{
    .{ .id = "D-CALL", .trigger = "source code calls it" },
    .{ .id = "D-REFLECT", .trigger = "reflection observes it" },
    .{ .id = "D-LUA", .trigger = "a @lua boundary adapter requires it" },
    .{ .id = "D-FOREIGN", .trigger = "a foreign build requests an adapter" },
    .{ .id = "D-DOCS", .trigger = "documentation generation requests it" },
    .{ .id = "D-TESTS", .trigger = "tests request it" },
    .{ .id = "D-EXPORT", .trigger = "an export manifest requires it" },
    .{ .id = "D-TOOLING", .trigger = "an LSP/MCP query requests materialization" },
    .{ .id = "D-CONTRACT", .trigger = "a build contract requires proof" },
};

pub const ErasureObligation = struct {
    id: []const u8,
    obligation: []const u8,
    witness: []const u8,
};

pub const erasure_obligations: []const ErasureObligation = &.{
    .{ .id = "X-NOEMIT", .obligation = "an unobserved relation emits no metatable, wrapper, adapter, closure, or symbol", .witness = "L6 manifest shows zero emitted symbols for the relation" },
    .{ .id = "X-COLLAPSE", .obligation = "requested projections sharing a graph collapse into one artifact with boundary adapters", .witness = "L6 manifest artifact count < requested projection count" },
    .{ .id = "X-ADAPTER", .obligation = "ABI-, ownership-, effect- and representation-compatible projections drop the boundary", .witness = "manifest adapter count is zero for compatible pairs" },
    .{ .id = "X-SINK", .obligation = "a @format(sink) formatter called only by a sink constructs no string", .witness = "manifest allocation count is zero for the sink path" },
    .{ .id = "X-DISCARD", .obligation = "a converter whose result is discarded omits result construction", .witness = "@comp.why reports the elided return pack" },
    .{ .id = "X-ITER", .obligation = "a sealed @iter consumed by a loop becomes the loop; no iterator object", .witness = "manifest allocation count is zero for the loop" },
    .{ .id = "X-CLONE", .obligation = "a clone immediately transferred then released becomes ownership transfer", .witness = "@comp.why reports the clone-to-move rewrite" },
};

// ── Structural requirements (Pass 38 §15 — retained by S5) ────────────────────

/// Projection authority, most authoritative first. The gate proves this ordering
/// is total and that `canonical` outranks every generated form.
pub const ProjectionAuthority = enum(u8) {
    canonical = 0,
    source_owned = 1,
    local_override = 2,
    runtime_override = 3,
    target_owned = 4,
    imported_authoritative = 5,
    asserted = 6,
    generated = 7,
    observed = 8,

    pub fn rank(self: ProjectionAuthority) u8 {
        return @intFromEnum(self);
    }

    pub fn outranks(self: ProjectionAuthority, other: ProjectionAuthority) bool {
        return self.rank() < other.rank();
    }
};

pub const ConflictClass = enum {
    equivalent,
    more_specific,
    higher_authority,
    commuting,
    mergeable,
    ambiguous,
    incompatible,
    explicitly_blocked,
};

pub const Resolution = enum {
    pick_either,
    take_specific,
    take_authoritative,
    apply_both,
    merge_if_declared,
    reject_with_candidates,
    drop_projection,
};

pub const ConflictRule = struct {
    class: ConflictClass,
    resolution: Resolution,
    rationale: []const u8,
};

/// The resolution column sets how forgiving the language is when two projection
/// paths disagree. The mechanical classes have one defensible answer; the other
/// four encode a stance: silence for provably-commuting cases, explicit opt-in
/// for merges, and a hard error rather than a dynamic fallback for genuine
/// ambiguity — a dynamic fallback would silently defeat the rung-3 proof.
pub const conflict_rules: []const ConflictRule = &.{
    .{ .class = .equivalent, .resolution = .pick_either, .rationale = "same canonical edge reached by two paths; projection equality proves it" },
    .{ .class = .more_specific, .resolution = .take_specific, .rationale = "the resolution ladder already orders specificity" },
    .{ .class = .higher_authority, .resolution = .take_authoritative, .rationale = "the authority ordering is total, so this is decidable without a diagnostic" },
    .{ .class = .commuting, .resolution = .apply_both, .rationale = "proven commuting: order is unobservable, so neither choice needs a diagnostic" },
    .{ .class = .mergeable, .resolution = .merge_if_declared, .rationale = "an implicit merge invents an implementation nobody wrote; require the merge fact" },
    .{ .class = .ambiguous, .resolution = .reject_with_candidates, .rationale = "falling back to the dynamic layer would silently defeat G5 on a hot path" },
    .{ .class = .incompatible, .resolution = .reject_with_candidates, .rationale = "incompatible effects, ABI or ownership cannot be reconciled by picking a winner" },
    .{ .class = .explicitly_blocked, .resolution = .drop_projection, .rationale = "`@eq = false` is a decision, not a conflict to arbitrate" },
};

/// Three-valued slots (Pass 39 R4): implementation, `false` to forbid, `nil` to
/// yield. Choosing none is also a choice — inheritance and derivation proceed.
pub const SlotState = enum { implementation, blocked, revealed, absent };

pub const SlotRule = struct {
    state: SlotState,
    syntax: []const u8,
    effect: []const u8,
};

pub const slot_rules: []const SlotRule = &.{
    .{ .state = .implementation, .syntax = "@eq = point_eq", .effect = "explicit implementation wins over generated and inherited projections" },
    .{ .state = .blocked, .syntax = "@eq = false", .effect = "no equality: not inherited, not derived, no foreign projection; hits are manifest counters" },
    .{ .state = .revealed, .syntax = "@eq = nil", .effect = "removes the local decision, revealing lower-priority inherited or generated candidates" },
    .{ .state = .absent, .syntax = "(no declaration)", .effect = "inheritance and demand-driven derivation proceed" },
};

pub const StructuralRequirement = struct {
    id: []const u8,
    section: []const u8,
    title: []const u8,
    requirement: []const u8,
};

pub const structural_requirements: []const StructuralRequirement = &.{
    .{ .id = "R1", .section = "15.1", .title = "projection provenance identity", .requirement = "every projected form carries its own stable view identity pointing at one canonical edge" },
    .{ .id = "R2", .section = "15.2", .title = "projection conflict algebra", .requirement = "every conflict class maps to exactly one deterministic resolution" },
    .{ .id = "R3", .section = "15.3", .title = "projection invalidation", .requirement = "changing one edge invalidates only its dependents, not unrelated behavior of the same descriptor" },
    .{ .id = "R4", .section = "15.4", .title = "projection budget", .requirement = "every family has demand-driven generation, memoization, cycle detection, depth budget, cost estimate, cancellation, provenance, materialization threshold" },
    .{ .id = "R5", .section = "15.5", .title = "projection authority", .requirement = "every projection records one of the nine authority classes and the ordering is total" },
    .{ .id = "R6", .section = "15.6", .title = "semantic world capture", .requirement = "closures capture worlds frozen-by-stable-reference by default (Pass 39 R2)" },
    .{ .id = "R7", .section = "15.7", .title = "semantic-world parameters", .requirement = "run(world)(input) passes a world as data with no new language mechanism" },
    .{ .id = "R8", .section = "15.8", .title = "projection equality", .requirement = "canonical edge, semantic behavior, source implementation, generated projection, and physical realization are five distinct equalities" },
};

// ── Directives as world entries ───────────────────────────────────────────────

pub const DirectiveRoot = struct {
    root: []const u8,
    meaning: []const u8,
    shadowable_in_user_scope: bool,
};

pub const directive_roots: []const DirectiveRoot = &.{
    .{ .root = "@comp", .meaning = "scoped compiler semantic table (@comp.why, @comp.assert, @comp.target)", .shadowable_in_user_scope = true },
    .{ .root = "@target", .meaning = "current compilation target as a semantic value", .shadowable_in_user_scope = true },
    .{ .root = "@stage", .meaning = "current scope staging operation", .shadowable_in_user_scope = true },
    .{ .root = "@noalloc", .meaning = "allocation-forbidden effect fact", .shadowable_in_user_scope = true },
    .{ .root = "@export", .meaning = "export manifest entry", .shadowable_in_user_scope = true },
};

// ── Idioms and smells (Pass 40 §3) ────────────────────────────────────────────

pub const Idiom = struct {
    number: u8,
    rule: []const u8,
    example: []const u8,
};

pub const idioms: []const Idiom = &.{
    .{ .number = 1, .rule = "operators first; the operator IS the semantic call", .example = "a == b, a < b, #t, s1 .. s2" },
    .{ .number = 2, .rule = "@op(...) when the operation is the subject", .example = "sort(items, @cmp)" },
    .{ .number = 3, .rule = "value.@op to hold an implementation, never to call one", .example = "to_text = point.@to(str)" },
    .{ .number = 4, .rule = "declare at the source, in the constructor", .example = "point: { ..., @eq = ... }" },
    .{ .number = 5, .rule = "never declare both ends of an edge", .example = "@to(str) on point IS str.@from(point)" },
    .{ .number = 6, .rule = "let demand synthesize structural operations", .example = "use set[point]; let @hash derive, or block with = false" },
    .{ .number = 7, .rule = "@format(sink) is primary; @to(str) is its projection", .example = "@format(sink) = (out, p) out:write(...)" },
    .{ .number = 8, .rule = "name the scope, not a helper", .example = "compare_approximately(a, b, eps) owns its @eq binding" },
    .{ .number = 9, .rule = "meta(level) only when the level matters", .example = "meta(descriptor)(point).@cmp to bypass overrides" },
    .{ .number = 10, .rule = "false to forbid, nil to yield, silence to inherit", .example = "secret: { ..user, @eq = false }" },
};

pub const smells: []const []const u8 = &.{
    "an @ form where an operator exists (@eq(a,b) mid-expression)",
    "getmetatable or setmetatable in Duo-authored code (they do not exist)",
    "a curry level carrying a static fact (@eq(bool)(...))",
    "eager materialization: building metatables or adapters just in case",
    "manual reimplementation of a derivable operation with no semantic difference",
};

// ── Gains ledger (Pass 41 §2) ─────────────────────────────────────────────────

/// Enumerated so the price of ever reversing the native-first amendment is
/// visible rather than rediscovered.
pub const Gain = struct {
    number: u8,
    gain: []const u8,
    kind: []const u8,
};

pub const gains_ledger: []const Gain = &.{
    .{ .number = 1, .gain = "one semantic namespace (@name); __ deleted", .kind = "clarity" },
    .{ .number = 2, .gain = "dynamic layer is ordinary Duo data", .kind = "elegance, power" },
    .{ .number = 3, .gain = "ladder 10 to 8 rungs; simpler sealed-world proof", .kind = "performance, provability" },
    .{ .number = 4, .gain = "one inheritance mechanism", .kind = "clarity, provability" },
    .{ .number = 5, .gain = "operator set on merit (!=, future L8 freedom)", .kind = "intuitiveness" },
    .{ .number = 6, .gain = "error surface singular (nil, err)", .kind = "clarity, performance" },
    .{ .number = 7, .gain = "Duo-B shrinks: no compat-replay semantics to freeze", .kind = "self-hosting" },
    .{ .number = 8, .gain = "conformance shrinks: Lua parity moves to the adapter suite", .kind = "stabilization" },
    .{ .number = 9, .gain = "Ward differentials become foreign-boundary tests", .kind = "measurement honesty" },
    .{ .number = 10, .gain = "every future design question loses one veto-holder", .kind = "velocity" },
};

/// Pass 41 §4 — kept even though compat no longer demands it. Recorded so these
/// survive future zealotry: heritage is not a reason to keep anything, but
/// neither is it a reason to delete what independently wins.
pub const kept_on_merit: []const []const u8 = &.{
    "tables as the one aggregate",
    "nil",
    "1-based indexing as the default realization of sequence descriptors",
    ".. for concat",
    "the stateless iterator triple as @iter's canonical projection",
    ": receiver-binding sugar for ordinary members (A6)",
};

// ── Completion gates ──────────────────────────────────────────────────────────

pub const CompletionGate = struct {
    number: u8,
    statement: []const u8,
    evidence: []const u8,
    phase: []const u8,
};

pub const completion_gates: []const CompletionGate = &.{
    .{ .number = 1, .statement = "bare @ is the current semantic world", .evidence = "G2 parses; @.eq and @eq name the same key", .phase = "P36-PH2" },
    .{ .number = 2, .statement = "@eq accesses current-world equality", .evidence = "G1 parses; resolves via rung 1 of the ladder", .phase = "P36-PH2" },
    .{ .number = 3, .statement = "point.@to(str) accesses the relation", .evidence = "G6 parses; retrieval is never receiver-bound", .phase = "P36-PH2" },
    .{ .number = 4, .statement = "@eq(point, true) and point == true normalize to one call", .evidence = "A-CALL and A-OP produce one call object identity", .phase = "P36-PH3" },
    .{ .number = 5, .statement = "the application spine is schema-driven, not punctuation-driven", .evidence = "@to(str)(p) grouping comes from the declared schema", .phase = "P36-PH3" },
    .{ .number = 6, .statement = "@to(str) and str.@from(point) share one edge", .evidence = "both views report the same canonical edge id", .phase = "P36-PH5" },
    .{ .number = 7, .statement = "scope and assignment replace install/bind APIs", .evidence = "no getmetatable or setmetatable surface exists in the language", .phase = "P36-PH3" },
    .{ .number = 8, .statement = "exact levels are selectable via meta(level)(value)", .evidence = "meta is an ordinary curried value; every assignable level round-trips", .phase = "P36-PH4" },
    .{ .number = 9, .statement = "lexical, instance, descriptor, package, foreign and dynamic share one model", .evidence = "one ladder, one call object, no per-level API", .phase = "P36-PH3" },
    .{ .number = 10, .statement = "protocol implications and hierarchy projection are demand-driven", .evidence = "P-CONSTRAINT and P-HIER emit nothing without a demand source", .phase = "P36-PH6" },
    .{ .number = 11, .statement = "every projected artifact retains canonical provenance", .evidence = "R1 view identity present on every materialized artifact", .phase = "P36-PH7" },
    .{ .number = 12, .statement = "generated projections collapse where consumption allows", .evidence = "X-COLLAPSE and X-ADAPTER discharged in the L6 manifest", .phase = "P36-PH6" },
    .{ .number = 13, .statement = "unobserved metatables and wrappers are not emitted", .evidence = "X-NOEMIT: zero emitted symbols for unobserved relations", .phase = "P36-PH6" },
    .{ .number = 14, .statement = "return-pack and effect consumption specialize each projection", .evidence = "X-DISCARD, X-SINK, X-ITER, X-CLONE discharged", .phase = "P36-PH6" },
    .{ .number = 15, .statement = "cross-language traits and adapters map to the same edge graph", .evidence = "P-FOREIGN and P-FOREIGN-LUA carry provenance, not flattened equivalence", .phase = "P36-PH5" },
    .{ .number = 16, .statement = "reverse edits produce transactions rather than silent mutation", .evidence = "P-REVERSE candidates arrive as validated semantic transactions", .phase = "P36-PH7" },
    .{ .number = 17, .statement = "projection conflicts, invalidation, authority and budgets are formalized", .evidence = "R2, R3, R4, R5 discharged with executable rules", .phase = "P36-PH7" },
    .{ .number = 18, .statement = "@ staging and directives are entries in the world", .evidence = "G10, G11 implemented; @comp resolves as a world entry", .phase = "P36-PH8" },
    .{ .number = 19, .statement = "Lua is a foreign projection with its own adapter test suite", .evidence = "the @lua adapter emits __ targets on demand at the boundary only", .phase = "P36-PH5" },
    .{ .number = 20, .statement = "Ward and the self-hosted compiler prove rung-3 resolution on hot paths", .evidence = "G5 fails the build if the manifest shows resolution above rung 3", .phase = "P36-PH9" },
};

// ── Execution phases ──────────────────────────────────────────────────────────

pub const ExecutionPhase = struct {
    phase: u8,
    id: []const u8,
    title: []const u8,
    exit_gate: []const u8,
};

pub const execution_phases: []const ExecutionPhase = &.{
    .{ .phase = 0, .id = "P36-PH0", .title = "Record the calculus", .exit_gate = "catalog queryable every desugaring resolves zero compiler change" },
    .{ .phase = 1, .id = "P36-PH1", .title = "Reject the graveyard in the grammar corpus", .exit_gate = "every rejected form is a parse error with a named reason" },
    .{ .phase = 2, .id = "P36-PH2", .title = "Semantic access grammar", .exit_gate = "gates 1-3 formatter and tree-sitter fixtures stable" },
    .{ .phase = 3, .id = "P36-PH3", .title = "Application normalization and ladder", .exit_gate = "gates 4 5 7 9 one call identity across all spellings" },
    .{ .phase = 4, .id = "P36-PH4", .title = "meta and meta(level)", .exit_gate = "gate 8 exact-level read and write" },
    .{ .phase = 5, .id = "P36-PH5", .title = "Endpoint operator and foreign projections", .exit_gate = "gates 6 15 19 one shared edge id" },
    .{ .phase = 6, .id = "P36-PH6", .title = "Demand analysis and erasure", .exit_gate = "gates 10 12 13 14 via L6 manifest deltas" },
    .{ .phase = 7, .id = "P36-PH7", .title = "Provenance conflicts authority budgets", .exit_gate = "gates 11 16 17" },
    .{ .phase = 8, .id = "P36-PH8", .title = "Directives as world entries", .exit_gate = "gate 18 @comp @(expr) @{} unified" },
    .{ .phase = 9, .id = "P36-PH9", .title = "Prove on Ward and self-hosted compiler", .exit_gate = "gate 20 rung-3 resolution on hot paths" },
};

// ── Queries ───────────────────────────────────────────────────────────────────

pub fn findAccessForm(id: []const u8) ?AccessForm {
    for (access_forms) |f| {
        if (std.mem.eql(u8, f.id, id)) return f;
    }
    return null;
}

pub fn isValidAccessFormId(id: []const u8) bool {
    return findAccessForm(id) != null;
}

pub fn findSupersession(id: []const u8) ?Supersession {
    for (supersessions) |s| {
        if (std.mem.eql(u8, s.id, id)) return s;
    }
    return null;
}

pub fn findGrammarRule(id: []const u8) ?GrammarRule {
    for (grammar_rules) |g| {
        if (std.mem.eql(u8, g.id, id)) return g;
    }
    return null;
}

pub fn resolutionFor(class: ConflictClass) ?Resolution {
    for (conflict_rules) |r| {
        if (r.class == class) return r.resolution;
    }
    return null;
}

pub fn findCompletionGate(number: u8) ?CompletionGate {
    for (completion_gates) |g| {
        if (g.number == number) return g;
    }
    return null;
}

pub fn luaAdapterTargetFor(root: []const u8) ?LuaAdapterTarget {
    for (lua_adapter_targets) |p| {
        if (std.mem.eql(u8, p.root, root)) return p;
    }
    return null;
}

/// A form is rejected if any graveyard entry names it. The gate uses this to
/// prove no access form or grammar rule resurrects a buried spelling.
pub fn isRejected(syntax: []const u8) bool {
    for (graveyard) |g| {
        if (std.mem.eql(u8, g.syntax, syntax)) return true;
    }
    return false;
}

pub fn writePass36Json(w: *std.Io.Writer, _: std.mem.Allocator) !void {
    try w.print(
        \\  "pass36":{{
        \\    "schema_version":"{s}",
        \\    "canonical_path":"{s}",
        \\    "plan_path":"{s}",
        \\    "access_form_count":{d},
        \\    "grammar_rule_count":{d},
        \\    "graveyard_count":{d},
        \\    "level_selector_count":{d},
        \\    "resolution_step_count":{d},
        \\    "call_object_field_count":{d},
        \\    "sealed_world_condition_count":{d},
        \\    "sealed_world_guarantee_count":{d},
        \\    "projection_family_count":{d},
        \\    "operator_projection_count":{d},
        \\    "lua_adapter_target_count":{d},
        \\    "demand_source_count":{d},
        \\    "erasure_obligation_count":{d},
        \\    "conflict_rule_count":{d},
        \\    "slot_rule_count":{d},
        \\    "structural_requirement_count":{d},
        \\    "directive_root_count":{d},
        \\    "idiom_count":{d},
        \\    "smell_count":{d},
        \\    "gain_count":{d},
        \\    "kept_on_merit_count":{d},
        \\    "completion_gate_count":{d},
        \\    "execution_phase_count":{d},
        \\    "supersession_count":{d},
        \\    "implemented_grammar_forms":{d},
        \\    "phase0_status":"{s}"
        \\  }}
    ,
        .{
            SCHEMA_VERSION,
            CANONICAL_PATH,
            PLAN_PATH,
            access_forms.len,
            grammar_rules.len,
            graveyard.len,
            level_selectors.len,
            resolution_order.len,
            call_object_fields.len,
            sealed_world_conditions.len,
            sealed_world_guarantees.len,
            projection_families.len,
            operator_projections.len,
            lua_adapter_targets.len,
            demand_sources.len,
            erasure_obligations.len,
            conflict_rules.len,
            slot_rules.len,
            structural_requirements.len,
            directive_roots.len,
            idioms.len,
            smells.len,
            gains_ledger.len,
            kept_on_merit.len,
            completion_gates.len,
            execution_phases.len,
            supersessions.len,
            implementedGrammarForms(),
            phase0Status(),
        },
    );
}

/// How many of the recorded grammar forms the compiler actually accepts.
pub fn implementedGrammarForms() usize {
    var n: usize = 0;
    for (grammar_rules) |g| {
        if (g.status == .implemented) n += 1;
    }
    return n;
}

/// `phase0_status` used to be the hardcoded string "recorded_only", which meant
/// the catalog reported Phase 0 forever — including after a form was
/// implemented. It is derived now, so the number cannot drift from the table
/// above: the JSON is a projection of the records, not a parallel claim about
/// them. Same failure this repo already hit with `TOKENIZE_EXPORTS`, where a
/// hand-maintained list disagreed with the symbols that actually existed and
/// nobody noticed for as long as it stayed short.
pub fn phase0Status() []const u8 {
    const n = implementedGrammarForms();
    if (n == 0) return "recorded_only";
    if (n == grammar_rules.len) return "grammar_complete";
    return "partially_implemented";
}

test "pass36_catalog: record counts" {
    try std.testing.expect(access_forms.len == 18);
    try std.testing.expect(grammar_rules.len == 11);
    try std.testing.expect(graveyard.len == 14);
    try std.testing.expect(resolution_order.len == 9);
    try std.testing.expect(call_object_fields.len == 10);
    try std.testing.expect(projection_families.len == 27);
    try std.testing.expect(operator_projections.len == 15);
    try std.testing.expect(lua_adapter_targets.len == 10);
    try std.testing.expect(conflict_rules.len == 8);
    try std.testing.expect(structural_requirements.len == 8);
    try std.testing.expect(idioms.len == 10);
    try std.testing.expect(smells.len == 5);
    try std.testing.expect(gains_ledger.len == 10);
    try std.testing.expect(completion_gates.len == 20);
    try std.testing.expect(execution_phases.len == 10);
    try std.testing.expect(supersessions.len == 4);
}

test "pass36_catalog: every conflict class has exactly one resolution" {
    inline for (@typeInfo(ConflictClass).@"enum".field_values) |v| {
        const class: ConflictClass = @enumFromInt(v);
        try std.testing.expect(resolutionFor(class) != null);
    }
}

test "pass36_catalog: authority ordering is total and canonical wins" {
    const values = @typeInfo(ProjectionAuthority).@"enum".field_values;
    try std.testing.expect(values.len == 9);
    inline for (values) |v| {
        const a: ProjectionAuthority = @enumFromInt(v);
        if (a != .canonical) try std.testing.expect(ProjectionAuthority.canonical.outranks(a));
    }
}

test "pass36_catalog: postfix and compat forms stay buried" {
    try std.testing.expect(isRejected("value@name"));
    try std.testing.expect(isRejected("value@(level)@name"));
    try std.testing.expect(isRejected("value:@name"));
    try std.testing.expect(isRejected("getmetatable / setmetatable"));
    try std.testing.expect(isRejected("~="));
}
