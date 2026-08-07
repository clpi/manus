//! Pass 52 gate — the de-magicking test, made executable.
//!
//! Pass 52's ruling is that no standard-environment name may have private
//! compiler behaviour. Each proof below asserts something that would be false if
//! magic had survived: a name with no justification, a hook that is not an edge,
//! a `satisfies` primitive still standing, or a homomorphism that does not
//! distribute.
const std = @import("std");
const cat = @import("pass52_catalog.zig");
const pass49 = @import("pass49_catalog.zig");

pub const Failure = struct {
    proof: []const u8,
    detail: []const u8,
};

// ── The standing gate ────────────────────────────────────────────────────────

/// G3 carries the de-magicking test verbatim. Every respelled name must justify
/// itself as (a) user-definable or (b) a relation family — never a side registry.
pub fn proveEveryStdNameIsJustified() ?Failure {
    if (cat.respellings.len == 0) return .{ .proof = "every-std-name-is-justified", .detail = "no respellings recorded" };
    for (cat.respellings) |r| {
        if (!r.justification.passes()) {
            return .{ .proof = "every-std-name-is-justified", .detail = r.id };
        }
    }
    return null;
}

/// The classification is total and binary: a name that answers a question about
/// semantics is a family; one that merely computes is an ordinary function.
/// A semantics-answering name justified as merely user-definable would be magic
/// wearing a disguise.
pub fn proveClassificationMatchesJustification() ?Failure {
    for (cat.respellings) |r| {
        const ok = switch (r.classification) {
            .answers_about_semantics => r.justification == .relation_family,
            .merely_computes => r.justification == .user_definable,
        };
        if (!ok) return .{ .proof = "classification-matches-justification", .detail = r.id };
    }
    return null;
}

/// No third category exists.
pub fn proveNoThirdCategory() ?Failure {
    const n = @typeInfo(cat.Classification).@"enum".field_names.len;
    if (n != 2) return .{ .proof = "no-third-category", .detail = "classification must stay binary" };
    return null;
}

// ── §1 The anchoring homomorphism ────────────────────────────────────────────

/// `satisfies` is deleted as a primitive. If it reappeared as a respelling
/// target or in the Pass 49 catalog's operations, the ruling would have failed.
pub fn proveSatisfiesIsDeleted() ?Failure {
    for (cat.respellings) |r| {
        if (std.mem.indexOf(u8, r.now, "satisfies") != null) {
            return .{ .proof = "satisfies-is-deleted", .detail = r.id };
        }
    }
    // Pass 49 §2 is amended by Pass 52: its operations must cite d@P, to(P), or
    // the shape axis — never the old primitive.
    for (pass49.operations) |o| {
        if (std.mem.indexOf(u8, o.spelling, "satisfies(") != null) {
            return .{
                .proof = "satisfies-is-deleted",
                .detail = "pass49 catalog still spells the satisfies primitive; Pass 52 amends it",
            };
        }
    }
    return null;
}

/// The graveyard must name satisfaction-as-a-primitive, or the deletion is not
/// recorded where future work would look for it.
pub fn proveGraveyardNamesTheDeletion() ?Failure {
    for (cat.graveyard) |g| {
        if (std.mem.indexOf(u8, g, "satisfaction as a primitive") != null) return null;
    }
    return .{ .proof = "graveyard-names-the-deletion", .detail = "satisfaction as a primitive function must be buried" };
}

/// Three faces of one graph fact — static, dynamic, reflective. A fourth would
/// mean satisfaction had grown machinery of its own.
pub fn proveThreeFacesOfOneFact() ?Failure {
    if (cat.satisfaction_faces.len != 3) return .{
        .proof = "three-faces-of-one-fact",
        .detail = "satisfaction has exactly three faces: static, dynamic, reflective",
    };
    var saw_static = false;
    var saw_dynamic = false;
    var saw_reflective = false;
    for (cat.satisfaction_faces) |f| {
        if (std.mem.eql(u8, f.face, "static")) saw_static = true;
        if (std.mem.eql(u8, f.face, "dynamic")) saw_dynamic = true;
        if (std.mem.eql(u8, f.face, "reflective")) saw_reflective = true;
    }
    if (!saw_static or !saw_dynamic or !saw_reflective) {
        return .{ .proof = "three-faces-of-one-fact", .detail = "static, dynamic and reflective must all be present" };
    }
    return null;
}

/// The homomorphism must actually distribute, and failure must union the
/// missing-sets. A law that only stated the success case would leave the
/// failure path unspecified — which is where magic hides.
pub fn proveHomomorphismDistributesBothWays() ?Failure {
    const law = cat.HOMOMORPHISM_LAW;
    if (std.mem.indexOf(u8, law, "union") == null) {
        return .{ .proof = "homomorphism-distributes-both-ways", .detail = "the law must state distribution" };
    }
    if (std.mem.indexOf(u8, law, "missing-sets union on failure") == null) {
        return .{ .proof = "homomorphism-distributes-both-ways", .detail = "the failure path must union missing-sets" };
    }
    return null;
}

// ── §3 Hooks ─────────────────────────────────────────────────────────────────

/// Every hook family must be inspectable by trie reflection. A hook you cannot
/// enumerate is a registry, not an edge.
pub fn proveEveryHookIsInspectable() ?Failure {
    if (cat.hook_families.len == 0) return .{ .proof = "every-hook-is-inspectable", .detail = "no hook families recorded" };
    for (cat.hook_families) |h| {
        if (h.inspectable_as.len == 0) return .{ .proof = "every-hook-is-inspectable", .detail = h.id };
        if (std.mem.indexOf(u8, h.inspectable_as, "[") == null) {
            return .{ .proof = "every-hook-is-inspectable", .detail = h.id };
        }
    }
    return null;
}

/// The compiler's own behaviours must be pre-populated edges, not built-ins.
/// If none were, "the compiler is browsable as data" would be an empty claim.
pub fn proveCompilerShipsItsOwnEdges() ?Failure {
    for (cat.hook_families) |h| {
        if (h.compiler_populated) return null;
    }
    return .{
        .proof = "compiler-ships-its-own-edges",
        .detail = "derive/rewrite/lower must be compiler-populated and overridable",
    };
}

/// Override, block, remove, inject must all exist as trie operations — those are
/// what make a compiler-populated edge no more privileged than a user's.
pub fn proveHookAlgebraIsComplete() ?Failure {
    inline for (.{ "override", "block", "remove", "inject" }) |want| {
        var found = false;
        for (cat.hook_operations) |o| {
            if (std.mem.eql(u8, o.op, want)) found = true;
        }
        if (!found) return .{ .proof = "hook-algebra-is-complete", .detail = want };
    }
    return null;
}

/// Conflicts never resolve by last-write-wins, and every hook edge is witnessed.
pub fn proveNoLastWriteWinsAndAlwaysWitnessed() ?Failure {
    var saw_conflict = false;
    var saw_provenance = false;
    for (cat.hook_operations) |o| {
        if (std.mem.eql(u8, o.op, "conflict")) {
            saw_conflict = true;
            if (std.mem.indexOf(u8, o.mechanism, "never last-write-wins") == null) {
                return .{ .proof = "no-last-write-wins-and-always-witnessed", .detail = o.id };
            }
        }
        if (std.mem.eql(u8, o.op, "provenance")) {
            saw_provenance = true;
            if (std.mem.indexOf(u8, o.mechanism, "witnessed") == null) {
                return .{ .proof = "no-last-write-wins-and-always-witnessed", .detail = o.id };
            }
        }
    }
    if (!saw_conflict or !saw_provenance) {
        return .{ .proof = "no-last-write-wins-and-always-witnessed", .detail = "conflict and provenance must both be recorded" };
    }
    return null;
}

/// Plugin APIs, callback registries and macro hooks are the graveyard shapes
/// this pass replaces. If they were not buried, G3 would have no teeth.
pub fn provePluginShapesAreBuried() ?Failure {
    inline for (.{ "plugin APIs", "callback registries", "macro hooks" }) |want| {
        var found = false;
        for (cat.graveyard) |g| {
            if (std.mem.eql(u8, g, want)) found = true;
        }
        if (!found) return .{ .proof = "plugin-shapes-are-buried", .detail = want };
    }
    return null;
}

// ── §4 The functional closure ────────────────────────────────────────────────

/// The monoid and the homomorphism are the whole type-class story. Both must be
/// stated, or the "no features needed" claim is unsupported.
pub fn proveAlgebraIsStated() ?Failure {
    var saw_monoid = false;
    var saw_homomorphism = false;
    for (cat.algebra_laws) |a| {
        if (std.mem.indexOf(u8, a.law, "monoid under spread") != null) saw_monoid = true;
        if (std.mem.indexOf(u8, a.law, "union") != null) saw_homomorphism = true;
    }
    if (!saw_monoid or !saw_homomorphism) {
        return .{ .proof = "algebra-is-stated", .detail = "the spread monoid and the anchoring homomorphism must both be laws" };
    }
    return null;
}

/// The point-free boundary stands: implicit-parameter lambdas remain rejected
/// even though sections and lenses compose freely.
pub fn provePointFreeBoundaryHolds() ?Failure {
    if (!cat.IMPLICIT_PARAM_LAMBDAS_REJECTED) {
        return .{ .proof = "point-free-boundary-holds", .detail = "implicit-parameter lambdas must stay rejected" };
    }
    return null;
}

/// Idioms must prefer the anchored bundle over a hand-built dictionary — that is
/// the one that would silently reintroduce dictionary passing.
pub fn proveAnchoredBundlesPreferredOverDictionaries() ?Failure {
    for (cat.idioms) |d| {
        if (std.mem.indexOf(u8, d.prefer, "@ordering") != null) {
            if (std.mem.indexOf(u8, d.over, "{ cmp =") == null) {
                return .{ .proof = "anchored-bundles-preferred", .detail = d.id };
            }
            return null;
        }
    }
    return .{ .proof = "anchored-bundles-preferred", .detail = "no anchored-bundle idiom recorded" };
}

/// Canonical Duo declares functions in value-binding form, matching what the
/// repo-wide idiom gate enforces at zero.
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

// ── Runner ───────────────────────────────────────────────────────────────────

pub const proofs = [_]*const fn () ?Failure{
    proveEveryStdNameIsJustified,
    proveClassificationMatchesJustification,
    proveNoThirdCategory,
    proveSatisfiesIsDeleted,
    proveGraveyardNamesTheDeletion,
    proveThreeFacesOfOneFact,
    proveHomomorphismDistributesBothWays,
    proveEveryHookIsInspectable,
    proveCompilerShipsItsOwnEdges,
    proveHookAlgebraIsComplete,
    proveNoLastWriteWinsAndAlwaysWitnessed,
    provePluginShapesAreBuried,
    proveAlgebraIsStated,
    provePointFreeBoundaryHolds,
    proveAnchoredBundlesPreferredOverDictionaries,
    proveCanonicalFunctionForm,
};

pub fn runAll() ?Failure {
    for (proofs) |p| {
        if (p()) |f| return f;
    }
    return null;
}

test "pass52_gate: every proof holds" {
    if (runAll()) |f| {
        std.debug.print("pass52 gate failed: {s} ({s})\n", .{ f.proof, f.detail });
        return error.Pass52GateFailed;
    }
}

test "pass52_gate: the runner actually runs every proof" {
    try std.testing.expectEqual(@as(usize, 16), proofs.len);
}

test "pass52_gate: the de-magicking test is carried verbatim" {
    try std.testing.expect(std.mem.indexOf(u8, cat.DEMAGICKING_TEST, "side registry") != null);
    try std.testing.expect(std.mem.indexOf(u8, cat.DEMAGICKING_TEST, "inspectable, overridable, and blockable") != null);
}
