//! Pass 49 — Sums, Protocols, and the Demand-Return Correction (Phase 0: records only).
//!
//! Canonical spec: docs/plans/duo_sums_protocols_demand.md
//! Operational:    docs/plans/pass49_sums_protocols_demand.md
//!
//! The load-bearing claim of this pass is *zero new grammar*: sums, protocols
//! and returns are all spelled with tables, bindings, calls, spread, anchors and
//! demand — forms that already parse. The catalog therefore records, for every
//! construct, the existing production that carries it, so a gate can assert that
//! no new production was introduced.
const std = @import("std");

pub const SCHEMA_VERSION = "pass49-sums-protocols-demand-v1";
pub const CANONICAL_PATH = "docs/archive/duo_sums_protocols_demand.md";
pub const PLAN_PATH = "docs/archive/pass49_sums_protocols_demand.md";

/// Surface forms this pass is allowed to use. The whole point of Pass 49 is that
/// this list is closed: a construct carried by anything else is a new production.
pub const Carrier = enum {
    table,
    binding,
    call,
    spread,
    anchor,
    demand,

    pub fn name(self: Carrier) []const u8 {
        return @tagName(self);
    }
};

pub const Section = enum { sums, protocols, demand_return };

// ── §1 Sums ──────────────────────────────────────────────────────────────────

pub const CaseKind = enum { nullary, payload };

pub const SumForm = struct {
    id: []const u8,
    spelling: []const u8,
    case_kind: CaseKind,
    carrier: Carrier,
    /// A case is simultaneously all of these; none of them is a new kind of thing.
    is_descriptor: bool,
    is_value: bool,
    is_anchor_target: bool,
    is_dispatch_key: bool,
};

pub const sum_forms: []const SumForm = &.{
    .{
        .id = "SUM-01",
        .spelling = "token_kind: { name, number, string, symbol }",
        .case_kind = .nullary,
        .carrier = .table,
        .is_descriptor = true,
        .is_value = true,
        .is_anchor_target = true,
        .is_dispatch_key = true,
    },
    .{
        .id = "SUM-02",
        .spelling = "result: { ok(value), err(failure) }",
        .case_kind = .payload,
        .carrier = .table,
        .is_descriptor = true,
        .is_value = true,
        .is_anchor_target = true,
        .is_dispatch_key = true,
    },
    .{
        .id = "SUM-03",
        .spelling = "shape: { circle(r: f64), rect(w: f64, h: f64) }",
        .case_kind = .payload,
        .carrier = .table,
        .is_descriptor = true,
        .is_value = true,
        .is_anchor_target = true,
        .is_dispatch_key = true,
    },
    .{
        .id = "SUM-04",
        .spelling = "any_of(i64, f64)",
        .case_kind = .nullary,
        .carrier = .call,
        .is_descriptor = true,
        .is_value = true,
        .is_anchor_target = false,
        .is_dispatch_key = false,
    },
};

/// The three consumption forms. There is no fourth, and no `match` construct
/// exists or will — that is the invariant the gate defends.
pub const ConsumptionForm = struct {
    id: []const u8,
    role: []const u8,
    spelling: []const u8,
    carrier: Carrier,
    lowers_to: []const u8,
};

pub const consumption_forms: []const ConsumptionForm = &.{
    .{
        .id = "CON-01",
        .role = "exhaustive branching",
        .spelling = "@{ [shape.circle] = (c) ..., [shape.rect] = (r) ... }(s)",
        .carrier = .table,
        .lowers_to = "branch; exhaustiveness is a descriptor-driven diagnostic",
    },
    .{
        .id = "CON-02",
        .role = "narrowing",
        .spelling = "if c = to(shape.circle)(s) use(c.r) else fallback(s) end",
        .carrier = .binding,
        .lowers_to = "conversion edge consumed by a binding condition; refines the branch",
    },
    .{
        .id = "CON-03",
        .role = "testing and destructuring",
        .spelling = "if kind == token_kind.string ... end / { r } = c",
        .carrier = .binding,
        .lowers_to = "equality on cases; lenses on payloads",
    },
};

/// Relations lift over cases; every one is derived on demand and overridable per
/// case at case depth (an exact edge).
pub const LiftedRelation = struct {
    id: []const u8,
    relation: []const u8,
    lifting: []const u8,
    overridable_per_case: bool,
};

pub const lifted_relations: []const LiftedRelation = &.{
    .{ .id = "LIFT-01", .relation = "eq", .lifting = "compares case then payload", .overridable_per_case = true },
    .{ .id = "LIFT-02", .relation = "hash", .lifting = "mixes case identity", .overridable_per_case = true },
    .{ .id = "LIFT-03", .relation = "format", .lifting = "prints case + payload", .overridable_per_case = true },
};

/// Representation is demand-selected, never declared.
pub const Representation = enum {
    niche_packed,
    tag_payload,
    branch_only,
    erased,

    pub fn name(self: Representation) []const u8 {
        return @tagName(self);
    }
};

pub const representations: []const Representation = &.{
    .niche_packed,
    .tag_payload,
    .branch_only,
    .erased,
};

// ── §2 Protocols ─────────────────────────────────────────────────────────────

pub const RequirementKind = enum {
    relation_family,
    subtree,
    exact_edge,
    law,
    negative,
    protocol,
};

pub const ProtocolEntry = struct {
    id: []const u8,
    spelling: []const u8,
    kind: RequirementKind,
    carrier: Carrier,
};

pub const protocol_entries: []const ProtocolEntry = &.{
    .{ .id = "PRO-01", .spelling = "comparable = { eq, hash }", .kind = .relation_family, .carrier = .table },
    .{ .id = "PRO-02", .spelling = "ordering = { cmp, laws = { antisymmetric, transitive, total } }", .kind = .law, .carrier = .table },
    .{ .id = "PRO-03", .spelling = "wire = { encode(json), decode(json) }", .kind = .subtree, .carrier = .table },
    .{ .id = "PRO-04", .spelling = "printable = { format }", .kind = .relation_family, .carrier = .table },
    .{ .id = "PRO-05", .spelling = "opaque = { format = false }", .kind = .negative, .carrier = .table },
    .{ .id = "PRO-06", .spelling = "ordered_key = { ..ordering, ..comparable }", .kind = .protocol, .carrier = .spread },
};

/// The four operations, each reusing machinery that already existed.
pub const Operation = struct {
    id: []const u8,
    op: []const u8,
    spelling: []const u8,
    existing_machinery: []const u8,
};

pub const operations: []const Operation = &.{
    .{
        .id = "OP-01",
        .op = "test",
        .spelling = "Point@ordering",
        .existing_machinery = "the anchoring homomorphism (Pass 52): @ distributes over constraint tables, yielding (bundle, nil) | (nil, missing_set). The bundle IS the proof",
    },
    .{
        .id = "OP-02",
        .op = "select",
        .spelling = "descriptors:filter((d) d@ordering)",
        .existing_machinery = "protocols are values and anchoring is a predicate; the C5 query surface",
    },
    .{
        .id = "OP-03",
        .op = "project",
        .spelling = "ordering satisfied => eq, < <= > >=, sortability, min/max, ordered-map keys",
        .existing_machinery = "law-to-projection registry (Pass 42 §4); implication is graph algebra",
    },
    .{
        .id = "OP-04",
        .op = "inject",
        .spelling = "n = { ..number, ..numeric_meta } / eq = numeric_meta.eq / run(task, impls)",
        .existing_machinery = "spread or scope at descriptor, lexical, or argument level; demand-erased",
    },
};

/// Verification tiers — the same three as everything else in the language.
pub const VerificationTier = enum { compile_time_sealed, guard_stable, structured_failure_dynamic };

pub const verification_tiers: []const VerificationTier = &.{
    .compile_time_sealed,
    .guard_stable,
    .structured_failure_dynamic,
};

// ── §3 The demand-return correction ──────────────────────────────────────────

/// Pass 48 §2.3 made a *binding* special. Nothing is special: the body's value
/// is its final expression's value, whatever that expression is.
pub const Supersession = struct {
    id: []const u8,
    supersedes: []const u8,
    reason: []const u8,
};

pub const supersessions: []const Supersession = &.{
    .{
        .id = "SUP-01",
        .supersedes = "Pass 48 §2.3 (tail demand: final assignment IS the result)",
        .reason = "it made a binding special; the body's value is its final expression's value",
    },
    .{
        .id = "SUP-02",
        .supersedes = "Pass 44 C11",
        .reason = "amended to the demand-return rule; examples respell to bodies ending in the meaningful expression",
    },
    .{
        .id = "SUP-04",
        .supersedes = "Pass 49 §2 (satisfies as a primitive relation)",
        .reason = "Pass 52 deletes it: satisfaction is the anchoring homomorphism d@P, not a std binding with private compiler behaviour",
    },
    .{
        .id = "SUP-03",
        .supersedes = "Pass 43 §2.2-2.3",
        .reason = "amended to the demand-return rule; no named-result ceremony in canonical source",
    },
};

pub const Realization = enum {
    void_realization,
    consuming_realization,
    pack_per_position,
    pinned,

    pub fn name(self: Realization) []const u8 {
        return @tagName(self);
    }
};

pub const RealizationRule = struct {
    id: []const u8,
    site: []const u8,
    realization: Realization,
    note: []const u8,
};

pub const realization_rules: []const RealizationRule = &.{
    .{
        .id = "REAL-01",
        .site = "point:xpp(2) unconsumed",
        .realization = .void_realization,
        .note = "the update runs, no value is constructed, the ABI returns nothing",
    },
    .{
        .id = "REAL-02",
        .site = "nx = point:xpp(2)",
        .realization = .consuming_realization,
        .note = "one return: the freshly stored value read from the place, no second evaluation and no duplicated effect",
    },
    .{
        .id = "REAL-03",
        .site = "a, b = f(...) with a pack tail",
        .realization = .pack_per_position,
        .note = "unused positions' construction is deleted",
    },
    .{
        .id = "REAL-04",
        .site = "export past the closed world / foreign adapter / dynamic rung / escaping function value",
        .realization = .pinned,
        .note = "defaults to the declared return descriptor, or the full body value when undeclared; manifest records return_shape: pinned(reason)",
    },
};

/// The anti-pattern this pass names. `result = compute(a, b)` then reading it is
/// not tail demand — the whole pattern is the smell, and the canonical body is
/// `compute(a, b)`.
pub const AntiPattern = struct {
    id: []const u8,
    pattern: []const u8,
    canonical: []const u8,
};

pub const anti_patterns: []const AntiPattern = &.{
    .{
        .id = "ANTI-01",
        .pattern = "result = compute(a, b) as a final line, then reading result",
        .canonical = "compute(a, b)",
    },
    .{
        .id = "ANTI-02",
        .pattern = "a \"result\" accumulator that mirrors an existing place",
        .canonical = "the place update itself is the body's final expression",
    },
    .{
        .id = "ANTI-03",
        .pattern = "a materialized return value with no consuming site",
        .canonical = "void realization (G5 demand violation otherwise)",
    },
};

/// Canonical function spelling. Pass 49 source is written in value-binding form
/// with no named-result ceremony.
pub const CANONICAL_FUNCTION_FORM = "add = (a, b) a + b";

pub const Gate = struct {
    id: []const u8,
    statement: []const u8,
};

pub const gates: []const Gate = &.{
    .{ .id = "G5", .statement = "a materialized return value with no consuming site is a demand violation" },
    .{ .id = "G6", .statement = "hot paths show zero unconsumed constructions" },
    .{ .id = "G-IDIOM", .statement = "no function ends in a bind-then-read" },
    .{ .id = "G-CONF", .statement = "realization pairs: same source, void and consuming sites, equal effects, differing construction counts" },
};

pub const WHY_HOOK = "@comp.why.return";

// ── Emission ─────────────────────────────────────────────────────────────────

pub fn writeJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",", .{SCHEMA_VERSION});
    try w.print("\"canonical\":\"{s}\",\"plan\":\"{s}\",", .{ CANONICAL_PATH, PLAN_PATH });
    try w.print("\"canonical_function_form\":\"{s}\",", .{CANONICAL_FUNCTION_FORM});
    try w.print("\"why_hook\":\"{s}\",", .{WHY_HOOK});

    try w.writeAll("\"carriers\":[");
    inline for (@typeInfo(Carrier).@"enum".field_names, 0..) |fname, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{fname});
    }
    try w.writeAll("],");

    try w.writeAll("\"sum_forms\":[");
    for (sum_forms, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"case_kind\":\"{s}\",\"carrier\":\"{s}\",\"descriptor\":{},\"value\":{},\"anchor\":{},\"dispatch\":{}}}", .{
            f.id, @tagName(f.case_kind), f.carrier.name(), f.is_descriptor, f.is_value, f.is_anchor_target, f.is_dispatch_key,
        });
    }
    try w.writeAll("],");

    try w.writeAll("\"consumption_forms\":[");
    for (consumption_forms, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"role\":\"{s}\",\"carrier\":\"{s}\"}}", .{ f.id, f.role, f.carrier.name() });
    }
    try w.writeAll("],");

    try w.writeAll("\"protocol_entries\":[");
    for (protocol_entries, 0..) |e, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"kind\":\"{s}\",\"carrier\":\"{s}\"}}", .{ e.id, @tagName(e.kind), e.carrier.name() });
    }
    try w.writeAll("],");

    try w.writeAll("\"operations\":[");
    for (operations, 0..) |o, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"op\":\"{s}\"}}", .{ o.id, o.op });
    }
    try w.writeAll("],");

    try w.writeAll("\"realization_rules\":[");
    for (realization_rules, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"realization\":\"{s}\"}}", .{ r.id, r.realization.name() });
    }
    try w.writeAll("],");

    try w.writeAll("\"supersessions\":[");
    for (supersessions, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"supersedes\":\"{s}\"}}", .{ s.id, s.supersedes });
    }
    try w.writeAll("],");

    try w.writeAll("\"anti_patterns\":[");
    for (anti_patterns, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\"}}", .{a.id});
    }
    try w.writeAll("],");

    try w.writeAll("\"gates\":[");
    for (gates, 0..) |g, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\"}}", .{g.id});
    }
    try w.writeAll("]}");
}

test "pass49_catalog: emits structurally valid JSON" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeJson(&aw.writer);
    try aw.writer.flush();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "pass49_catalog: ids are unique within every table" {
    inline for (.{ sum_forms, consumption_forms, protocol_entries, operations, realization_rules, supersessions, anti_patterns, gates }) |tbl| {
        for (tbl, 0..) |a, i| {
            for (tbl, 0..) |b, j| {
                if (i < j) try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
            }
        }
    }
}
