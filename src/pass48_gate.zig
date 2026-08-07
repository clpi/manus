//! Pass 48 gate — the consolidation checked against the passes it consolidates.
//!
//! A consolidation's risk is not being wrong in isolation; it is silently
//! disagreeing with the documents it claims authority over. Several proofs below
//! therefore import Pass 49 and Pass 52 and assert agreement, so the three
//! cannot drift apart without a test failing.
const std = @import("std");
const cat = @import("pass48_catalog.zig");
const pass49 = @import("pass49_catalog.zig");
const pass52 = @import("pass52_catalog.zig");

pub const Failure = struct {
    proof: []const u8,
    detail: []const u8,
};

fn contains(items: []const []const u8, needle: []const u8) bool {
    for (items) |i| if (std.mem.eql(u8, i, needle)) return true;
    return false;
}

// ── Authority ────────────────────────────────────────────────────────────────

/// The authority rule must state BOTH halves. A consolidation that only claimed
/// to win, without requiring the conflict be recorded, would licence silent
/// overrides — exactly the failure mode a consolidation introduces.
pub fn proveAuthorityRuleRequiresRecording() ?Failure {
    const r = cat.AUTHORITY_RULE;
    if (std.mem.indexOf(u8, r, "supersession to record") == null) {
        return .{ .proof = "authority-rule-requires-recording", .detail = "conflicts must be recorded, not just won" };
    }
    if (std.mem.indexOf(u8, r, "silent") == null and std.mem.indexOf(u8, r, "remains normative") == null) {
        return .{ .proof = "authority-rule-requires-recording", .detail = "silence must leave the source pass normative" };
    }
    return null;
}

// ── Part I: Axioms ───────────────────────────────────────────────────────────

/// Ten axioms, A1..A10, none missing. They are referenced by number throughout
/// the spec, so a gap is a dangling reference.
pub fn proveTenAxiomsPresent() ?Failure {
    if (cat.axioms.len != 10) return .{ .proof = "ten-axioms-present", .detail = "A1..A10" };
    inline for (.{ "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10" }) |id| {
        var found = false;
        for (cat.axioms) |a| if (std.mem.eql(u8, a.id, id)) {
            found = true;
        };
        if (!found) return .{ .proof = "ten-axioms-present", .detail = id };
    }
    return null;
}

/// A2 (NNS) is what every other pass leans on when it claims "zero new grammar".
pub fn proveNnsAxiomIsStated() ?Failure {
    for (cat.axioms) |a| {
        if (!std.mem.eql(u8, a.id, "A2")) continue;
        if (std.mem.indexOf(u8, a.statement, "never as new tokens") == null) {
            return .{ .proof = "nns-axiom-is-stated", .detail = "A2 must close the grammar explicitly" };
        }
        return null;
    }
    return .{ .proof = "nns-axiom-is-stated", .detail = "A2 missing" };
}

// ── Part II: Grammar ─────────────────────────────────────────────────────────

/// `~=` is graveyarded and `!=` is the operator. The repo migrated 950 sites to
/// match; if the inventory disagreed, the corpus and the spec would conflict.
pub fn proveOperatorInventoryMatchesGraveyard() ?Failure {
    if (!contains(cat.operators, "!=")) {
        return .{ .proof = "operator-inventory-matches-graveyard", .detail = "!= must be in the inventory" };
    }
    if (contains(cat.operators, "~=")) {
        return .{ .proof = "operator-inventory-matches-graveyard", .detail = "~= is graveyarded" };
    }
    if (!contains(cat.graveyard, "~=")) {
        return .{ .proof = "operator-inventory-matches-graveyard", .detail = "~= must be buried" };
    }
    return null;
}

/// Position disambiguates `@` completely: both roles must exist, or the claim
/// that prefix and postfix never collide is untested.
pub fn proveAtIsPositionDisambiguated() ?Failure {
    var saw_prefix = false;
    var saw_postfix = false;
    for (cat.at_roles) |r| {
        if (r.position == .prefix_staging) saw_prefix = true;
        if (r.position == .postfix_anchoring) saw_postfix = true;
    }
    if (!saw_prefix or !saw_postfix) {
        return .{ .proof = "at-is-position-disambiguated", .detail = "both staging and anchoring roles must be recorded" };
    }
    return null;
}

/// The SHC's own families are created by identical machinery to std's — that
/// identity is the substance of A9 and G3.
pub fn proveShcFamiliesUseIdenticalMachinery() ?Failure {
    if (cat.shc_relation_families.len == 0) {
        return .{ .proof = "shc-families-use-identical-machinery", .detail = "no SHC families recorded" };
    }
    for (cat.shc_relation_families) |f| {
        if (contains(cat.std_relation_families, f)) {
            return .{ .proof = "shc-families-use-identical-machinery", .detail = f };
        }
    }
    // Pass 52's hook families must be drawn from these, not invented separately.
    for (pass52.hook_families) |h| {
        const known = contains(cat.shc_relation_families, h.family) or
            contains(cat.std_relation_families, h.family);
        if (!known) return .{
            .proof = "shc-families-use-identical-machinery",
            .detail = h.family,
        };
    }
    return null;
}

// ── Part III: Semantic model ─────────────────────────────────────────────────

/// Eight rungs, numbered 1..8 in order. The ladder is referenced by rung number
/// (G6 says hot paths live at rung 3), so ordering is load-bearing.
pub fn proveLadderIsEightRungsInOrder() ?Failure {
    if (cat.ladder.len != 8) return .{ .proof = "ladder-is-eight-rungs-in-order", .detail = "the ladder is final at 8" };
    for (cat.ladder, 0..) |r, i| {
        if (r.rung != @as(u8, @intCast(i + 1))) {
            return .{ .proof = "ladder-is-eight-rungs-in-order", .detail = r.name };
        }
    }
    if (cat.SEALED_COLLAPSE_RUNG != 3) {
        return .{ .proof = "ladder-is-eight-rungs-in-order", .detail = "sealed-world collapse lands at rung 3" };
    }
    return null;
}

/// `false` blocks, `nil` never does. Collapsing the two would erase the
/// difference between "forbidden here" and "no local decision".
pub fn proveFalseBlocksAndNilDoesNot() ?Failure {
    if (std.mem.indexOf(u8, cat.BLOCKING_RULE, "false blocks") == null or
        std.mem.indexOf(u8, cat.BLOCKING_RULE, "nil never blocks") == null)
    {
        return .{ .proof = "false-blocks-and-nil-does-not", .detail = cat.BLOCKING_RULE };
    }
    return null;
}

/// Conflicts classify; last-write-wins is buried. Pass 52's hook algebra says
/// the same thing, and both must agree.
pub fn proveConflictsClassifyNeverLastWriteWins() ?Failure {
    if (cat.conflict_classes.len == 0) {
        return .{ .proof = "conflicts-classify", .detail = "no conflict classes recorded" };
    }
    if (!contains(cat.graveyard, "last-registration-wins")) {
        return .{ .proof = "conflicts-classify", .detail = "last-registration-wins must be buried" };
    }
    for (pass52.hook_operations) |o| {
        if (!std.mem.eql(u8, o.op, "conflict")) continue;
        if (std.mem.indexOf(u8, o.mechanism, "never last-write-wins") == null) {
            return .{ .proof = "conflicts-classify", .detail = "pass52 hook conflict rule disagrees" };
        }
    }
    return null;
}

// ── Part IV: Idioms ──────────────────────────────────────────────────────────

/// Ten idioms, numbered 1..10.
pub fn proveTenIdiomsInOrder() ?Failure {
    if (cat.idioms.len != 10) return .{ .proof = "ten-idioms-in-order", .detail = "the canon is ten" };
    for (cat.idioms, 0..) |d, i| {
        if (d.n != @as(u8, @intCast(i + 1))) return .{ .proof = "ten-idioms-in-order", .detail = d.statement };
    }
    return null;
}

/// The spec's own canonical function form must be what the repo-wide idiom gate
/// enforces at zero — otherwise the corpus and the specification disagree.
pub fn proveCanonicalFunctionFormAgreesAcrossPasses() ?Failure {
    inline for (.{ cat.CANONICAL_FUNCTION_FORM, pass49.CANONICAL_FUNCTION_FORM, pass52.CANONICAL_FUNCTION_FORM }) |f| {
        if (std.mem.indexOf(u8, f, "fun ") != null or std.mem.indexOf(u8, f, "function ") != null) {
            return .{ .proof = "canonical-function-form-agrees", .detail = f };
        }
        if (std.mem.indexOf(u8, f, "= (") == null) {
            return .{ .proof = "canonical-function-form-agrees", .detail = f };
        }
    }
    if (!std.mem.eql(u8, cat.CANONICAL_FUNCTION_FORM, pass49.CANONICAL_FUNCTION_FORM) or
        !std.mem.eql(u8, cat.CANONICAL_FUNCTION_FORM, pass52.CANONICAL_FUNCTION_FORM))
    {
        return .{ .proof = "canonical-function-form-agrees", .detail = "passes 48/49/52 must state the same form" };
    }
    return null;
}

// ── Part V: SHC gates ────────────────────────────────────────────────────────

/// Ten gates, G1..G10. G5 and G6 are also asserted by Pass 49; G3 by Pass 52.
pub fn proveTenGatesPresent() ?Failure {
    if (cat.gates.len != 10) return .{ .proof = "ten-gates-present", .detail = "G1..G10" };
    inline for (.{ "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10" }) |id| {
        var found = false;
        for (cat.gates) |g| if (std.mem.eql(u8, g.id, id)) {
            found = true;
        };
        if (!found) return .{ .proof = "ten-gates-present", .detail = id };
    }
    return null;
}

/// G3 is the de-magicking gate; Pass 52 carries its test. If G3 stopped naming
/// side registries, that test would have no home.
pub fn proveG3CarriesTheDemagickingTest() ?Failure {
    for (cat.gates) |g| {
        if (!std.mem.eql(u8, g.id, "G3")) continue;
        if (std.mem.indexOf(u8, g.statement, "side registries") == null) {
            return .{ .proof = "g3-carries-the-demagicking-test", .detail = g.statement };
        }
        if (std.mem.indexOf(u8, pass52.DEMAGICKING_TEST, "side registry") == null) {
            return .{ .proof = "g3-carries-the-demagicking-test", .detail = "pass52 test no longer names side registries" };
        }
        return null;
    }
    return .{ .proof = "g3-carries-the-demagicking-test", .detail = "G3 missing" };
}

/// G5/G6 are the demand gates Pass 49 also asserts; both catalogs must keep them.
pub fn proveDemandGatesAgreeWithPass49() ?Failure {
    inline for (.{ "G5", "G6" }) |id| {
        var here = false;
        for (cat.gates) |g| if (std.mem.eql(u8, g.id, id)) {
            here = true;
        };
        var there = false;
        for (pass49.gates) |g| if (std.mem.eql(u8, g.id, id)) {
            there = true;
        };
        if (!here or !there) return .{ .proof = "demand-gates-agree-with-pass49", .detail = id };
    }
    return null;
}

/// Registries beside the graph are forbidden architecture — the structural form
/// of the same rule G3 states as a gate.
pub fn proveRegistriesAreForbiddenArchitecture() ?Failure {
    for (cat.forbidden_architecture) |f| {
        if (std.mem.indexOf(u8, f, "registries beside the graph") != null) return null;
    }
    return .{ .proof = "registries-are-forbidden-architecture", .detail = "side registries must be architecturally forbidden" };
}

/// Bootstrap lifecycle is five states in a fixed order; the matrix uses these
/// names, so a rename here silently desynchronizes the self-hosting records.
pub fn proveBootstrapLifecycleIsFiveStates() ?Failure {
    const want = [_][]const u8{ "discovered", "specified", "implemented", "validated", "adopted" };
    if (cat.bootstrap_lifecycle.len != want.len) {
        return .{ .proof = "bootstrap-lifecycle-is-five-states", .detail = "five states, in order" };
    }
    for (want, 0..) |w, i| {
        if (!std.mem.eql(u8, cat.bootstrap_lifecycle[i], w)) {
            return .{ .proof = "bootstrap-lifecycle-is-five-states", .detail = w };
        }
    }
    return null;
}

// ── Part VI: Graveyard ───────────────────────────────────────────────────────

/// The graveyard must bury what the repo actually migrated away from. These six
/// are enforced at zero across all .duo files by `zig build idiom-gate`, so the
/// spec and the corpus would otherwise disagree.
pub fn proveGraveyardCoversEnforcedIdioms() ?Failure {
    inline for (.{ "req", "local", "~=", "__-anything", "match/pattern syntax", "implicit-parameter lambdas" }) |want| {
        if (!contains(cat.graveyard, want)) {
            return .{ .proof = "graveyard-covers-enforced-idioms", .detail = want };
        }
    }
    return null;
}

// ── Runner ───────────────────────────────────────────────────────────────────

pub const proofs = [_]*const fn () ?Failure{
    proveAuthorityRuleRequiresRecording,
    proveTenAxiomsPresent,
    proveNnsAxiomIsStated,
    proveOperatorInventoryMatchesGraveyard,
    proveAtIsPositionDisambiguated,
    proveShcFamiliesUseIdenticalMachinery,
    proveLadderIsEightRungsInOrder,
    proveFalseBlocksAndNilDoesNot,
    proveConflictsClassifyNeverLastWriteWins,
    proveTenIdiomsInOrder,
    proveCanonicalFunctionFormAgreesAcrossPasses,
    proveTenGatesPresent,
    proveG3CarriesTheDemagickingTest,
    proveDemandGatesAgreeWithPass49,
    proveRegistriesAreForbiddenArchitecture,
    proveBootstrapLifecycleIsFiveStates,
    proveGraveyardCoversEnforcedIdioms,
};

pub fn runAll() ?Failure {
    for (proofs) |p| {
        if (p()) |f| return f;
    }
    return null;
}

test "pass48_gate: every proof holds" {
    if (runAll()) |f| {
        std.debug.print("pass48 gate failed: {s} ({s})\n", .{ f.proof, f.detail });
        return error.Pass48GateFailed;
    }
}

test "pass48_gate: the runner actually runs every proof" {
    try std.testing.expectEqual(@as(usize, 17), proofs.len);
}
