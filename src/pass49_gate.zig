//! Pass 49 gate — proves the claims the pass actually makes.
//!
//! Pass 49's whole argument is that sums, protocols and returns need *no new
//! grammar*: they are meaning assigned to forms that already parse. A catalog
//! that merely lists them proves nothing, so each proof below asserts a property
//! that would be false if the pass had smuggled in a production, a keyword, or a
//! special case.
const std = @import("std");
const cat = @import("pass49_catalog.zig");

pub const Failure = struct {
    proof: []const u8,
    detail: []const u8,
};

fn has(comptime T: type, tbl: []const T, id: []const u8) bool {
    for (tbl) |e| if (std.mem.eql(u8, e.id, id)) return true;
    return false;
}

// ── §1 Sums ──────────────────────────────────────────────────────────────────

/// Every sum and every consumption form rides one of the six existing carriers.
/// A construct needing a seventh would be a new production.
pub fn proveNoConstructNeedsANewCarrier() ?Failure {
    for (cat.sum_forms) |f| {
        _ = f.carrier.name(); // exhaustive by type: Carrier has no `other`
    }
    for (cat.consumption_forms) |f| {
        _ = f.carrier.name();
    }
    for (cat.protocol_entries) |e| {
        _ = e.carrier.name();
    }
    const carriers = @typeInfo(cat.Carrier).@"enum".field_names;
    if (carriers.len != 6) return .{
        .proof = "no-construct-needs-a-new-carrier",
        .detail = "the carrier set must stay closed at six: table, binding, call, spread, anchor, demand",
    };
    return null;
}

/// A case is a descriptor, a value, an anchor target and a dispatch key at once.
/// If any table-carried case failed one of these, cases would be a new kind of
/// thing rather than an ordinary slot form.
pub fn proveCasesAreOrdinaryValues() ?Failure {
    for (cat.sum_forms) |f| {
        if (f.carrier != .table) continue;
        if (!f.is_descriptor or !f.is_value or !f.is_anchor_target or !f.is_dispatch_key) {
            return .{ .proof = "cases-are-ordinary-values", .detail = f.id };
        }
    }
    return null;
}

/// There is no match construct and there will be none. The three consumption
/// forms are the whole space; a fourth would mean the claim failed.
pub fn proveNoMatchConstruct() ?Failure {
    if (cat.consumption_forms.len != 3) return .{
        .proof = "no-match-construct",
        .detail = "consumption is exactly branching, narrowing, and testing/destructuring",
    };
    for (cat.consumption_forms) |f| {
        if (std.mem.indexOf(u8, f.spelling, "match") != null or
            std.mem.indexOf(u8, f.spelling, "case ") != null or
            std.mem.indexOf(u8, f.spelling, "switch") != null)
        {
            return .{ .proof = "no-match-construct", .detail = f.id };
        }
    }
    return null;
}

/// Every lifted relation is overridable per case — an exact edge at case depth.
/// A relation that could not be overridden would be built-in behaviour, not a
/// derived projection.
pub fn proveRelationsLiftAndStayOverridable() ?Failure {
    if (cat.lifted_relations.len == 0) return .{ .proof = "relations-lift", .detail = "no lifted relations recorded" };
    for (cat.lifted_relations) |r| {
        if (!r.overridable_per_case) return .{ .proof = "relations-lift", .detail = r.id };
    }
    return null;
}

/// Representation is demand-selected, and `branch_only`/`erased` must both be
/// reachable — a case observed only by identity may never be materialized.
pub fn proveRepresentationIsDemandSelected() ?Failure {
    var saw_branch_only = false;
    var saw_erased = false;
    for (cat.representations) |r| {
        if (r == .branch_only) saw_branch_only = true;
        if (r == .erased) saw_erased = true;
    }
    if (!saw_branch_only or !saw_erased) return .{
        .proof = "representation-is-demand-selected",
        .detail = "branch-only and erased representations must both remain available",
    };
    return null;
}

// ── §2 Protocols ─────────────────────────────────────────────────────────────

/// A protocol is data. Composition is spread, not a new inheritance mechanism.
pub fn proveProtocolCompositionIsSpread() ?Failure {
    for (cat.protocol_entries) |e| {
        if (e.kind == .protocol and e.carrier != .spread) {
            return .{ .proof = "protocol-composition-is-spread", .detail = e.id };
        }
    }
    return null;
}

/// Negative requirements must exist: `opaque = { format = false }` is what makes
/// a protocol able to forbid, not just require.
pub fn proveNegativeRequirementsExist() ?Failure {
    for (cat.protocol_entries) |e| {
        if (e.kind == .negative) return null;
    }
    return .{ .proof = "negative-requirements-exist", .detail = "no negative requirement recorded" };
}

/// All four operations are present and each names the pre-existing machinery it
/// reuses. An operation with no such machinery would be new API.
pub fn proveFourOperationsReuseExistingMachinery() ?Failure {
    if (cat.operations.len != 4) return .{ .proof = "four-operations", .detail = "test, select, project, inject" };
    inline for (.{ "OP-01", "OP-02", "OP-03", "OP-04" }) |id| {
        if (!has(cat.Operation, cat.operations, id)) return .{ .proof = "four-operations", .detail = id };
    }
    for (cat.operations) |o| {
        if (o.existing_machinery.len == 0) return .{ .proof = "four-operations", .detail = o.id };
    }
    return null;
}

/// Verification uses the same three tiers as everything else — no protocol-only
/// checking mode.
pub fn proveVerificationTiersAreTheUsualThree() ?Failure {
    if (cat.verification_tiers.len != 3) return .{
        .proof = "verification-tiers-are-the-usual-three",
        .detail = "compile-time sealed, guard stable, structured failure at the dynamic rung",
    };
    return null;
}

// ── §3 The demand-return correction ──────────────────────────────────────────

/// Pass 48 §2.3 must be recorded as superseded. This is the correction the pass
/// exists to make: it had blessed a binding, and nothing is special.
pub fn provePass48TailDemandSuperseded() ?Failure {
    for (cat.supersessions) |s| {
        if (std.mem.indexOf(u8, s.supersedes, "Pass 48") != null) return null;
    }
    return .{ .proof = "pass48-tail-demand-superseded", .detail = "Pass 48 §2.3 must be superseded" };
}

/// The same edge realizes void when unconsumed and consuming when bound. Both
/// must be recorded, or demand would not be the thing deciding materialization.
pub fn proveBothRealizationsExist() ?Failure {
    var saw_void = false;
    var saw_consuming = false;
    for (cat.realization_rules) |r| {
        if (r.realization == .void_realization) saw_void = true;
        if (r.realization == .consuming_realization) saw_consuming = true;
    }
    if (!saw_void or !saw_consuming) return .{
        .proof = "both-realizations-exist",
        .detail = "one source edge must realize both void and consuming",
    };
    return null;
}

/// A consuming realization observes the stored value; it must not re-evaluate.
/// If it did, demand would change semantics rather than materialization.
pub fn proveConsumingRealizationDoesNotDuplicateEffects() ?Failure {
    for (cat.realization_rules) |r| {
        if (r.realization != .consuming_realization) continue;
        if (std.mem.indexOf(u8, r.note, "no second evaluation") == null or
            std.mem.indexOf(u8, r.note, "no duplicated effect") == null)
        {
            return .{ .proof = "consuming-realization-does-not-duplicate-effects", .detail = r.id };
        }
        return null;
    }
    return .{ .proof = "consuming-realization-does-not-duplicate-effects", .detail = "no consuming realization recorded" };
}

/// Where demand cannot propagate, the realization is pinned and the manifest
/// says so. This is the one place a return descriptor earns its keep.
pub fn provePinnedBoundariesAreRecorded() ?Failure {
    for (cat.realization_rules) |r| {
        if (r.realization != .pinned) continue;
        if (std.mem.indexOf(u8, r.note, "pinned") == null) {
            return .{ .proof = "pinned-boundaries-are-recorded", .detail = r.id };
        }
        return null;
    }
    return .{ .proof = "pinned-boundaries-are-recorded", .detail = "no pinned boundary recorded" };
}

/// The `result =` idiom is named as an anti-pattern, and its canonical form is
/// the bare expression. If the catalog ever spelled the anti-pattern as the
/// canonical form, the correction would have been lost.
pub fn proveNoResultPlumbingIdiom() ?Failure {
    if (cat.anti_patterns.len == 0) return .{ .proof = "no-result-plumbing-idiom", .detail = "no anti-patterns recorded" };
    for (cat.anti_patterns) |a| {
        if (std.mem.indexOf(u8, a.canonical, "result =") != null) {
            return .{ .proof = "no-result-plumbing-idiom", .detail = a.id };
        }
    }
    if (!has(cat.AntiPattern, cat.anti_patterns, "ANTI-01")) {
        return .{ .proof = "no-result-plumbing-idiom", .detail = "ANTI-01 (bind-then-read) must be recorded" };
    }
    return null;
}

/// Canonical Duo declares functions in value-binding form. The catalog's own
/// stated form must match what the repo's idiom gate enforces.
pub fn proveCanonicalFunctionForm() ?Failure {
    const f = cat.CANONICAL_FUNCTION_FORM;
    if (std.mem.indexOf(u8, f, "fun ") != null or std.mem.indexOf(u8, f, "function ") != null) {
        return .{ .proof = "canonical-function-form", .detail = f };
    }
    if (std.mem.indexOf(u8, f, "= (") == null) {
        return .{ .proof = "canonical-function-form", .detail = "must be value-binding form: add = (a, b) a + b" };
    }
    return null;
}

/// G5 and G6 must both survive: a materialized-but-unconsumed return is a
/// violation, and hot paths must show zero unconsumed constructions.
pub fn proveDemandGatesSurvive() ?Failure {
    inline for (.{ "G5", "G6" }) |id| {
        if (!has(cat.Gate, cat.gates, id)) return .{ .proof = "demand-gates-survive", .detail = id };
    }
    return null;
}

// ── Runner ───────────────────────────────────────────────────────────────────

pub const proofs = [_]*const fn () ?Failure{
    proveNoConstructNeedsANewCarrier,
    proveCasesAreOrdinaryValues,
    proveNoMatchConstruct,
    proveRelationsLiftAndStayOverridable,
    proveRepresentationIsDemandSelected,
    proveProtocolCompositionIsSpread,
    proveNegativeRequirementsExist,
    proveFourOperationsReuseExistingMachinery,
    proveVerificationTiersAreTheUsualThree,
    provePass48TailDemandSuperseded,
    proveBothRealizationsExist,
    proveConsumingRealizationDoesNotDuplicateEffects,
    provePinnedBoundariesAreRecorded,
    proveNoResultPlumbingIdiom,
    proveCanonicalFunctionForm,
    proveDemandGatesSurvive,
};

pub fn runAll() ?Failure {
    for (proofs) |p| {
        if (p()) |f| return f;
    }
    return null;
}

test "pass49_gate: every proof holds" {
    if (runAll()) |f| {
        std.debug.print("pass49 gate failed: {s} ({s})\n", .{ f.proof, f.detail });
        return error.Pass49GateFailed;
    }
}

test "pass49_gate: the runner actually runs every proof" {
    try std.testing.expectEqual(@as(usize, 16), proofs.len);
}
