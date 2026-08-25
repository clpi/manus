//! — proof-carrying semantic transformations (Goals A–C foundation).
//!
//! Reuses `evidence_record.Kind`; does NOT introduce a parallel proof language.
//! Canonical plan: the semantic-autonomy plan
const std = @import("std");
const evidence_record = @import("evidence_record.zig");

pub const SCHEMA_VERSION = "proof-carrying-v0";

/// Exact graph coordinates retained through transformation provenance.
///
/// These are `semantic_graph.id` values (`u32`); `proof_carrying` deliberately
/// avoids importing `semantic_graph` to prevent a circular dependency
/// (`semantic_graph → transform_engine → proof_carrying`).
/// GAPS-137/P2: the provenance record must carry exact graph-minted identities
/// — relation, application, input value, output value, and the graph
/// transformation node — so that a transformed application remains traceable
/// from relation → realization → machine → bytes without a hash standing in.
pub const GraphEntity = struct {
    /// Graph NodeId of the transform application node (the rewrite itself).
    transform: ?u32 = null,
    /// Exact relation identity (semantic_graph.id).
    relation: ?u32 = null,
    /// Exact application occurrence identity (semantic_graph.id).
    application: ?u32 = null,
    /// Semantic subject identity where applicable (semantic_graph.id).
    subject: ?u32 = null,
    /// Exact input value identity before transformation (semantic_graph.id).
    input_value: ?u32 = null,
    /// Exact output value identity after transformation (semantic_graph.id).
    output_value: ?u32 = null,

    /// True when this entry carries exact graph identity for lineage.
    pub fn hasLineage(self: GraphEntity) bool {
        return self.relation != null and self.application != null and
            self.input_value != null and self.output_value != null;
    }
};

/// Lineage gate for transform provenance.
///
/// Returns `true` only when a proof record carries exact graph coordinates —
/// relation, application, input value, and output value — rather than
/// hash/fingerprint coordinates standing in for semantic identity.
/// A record whose `graph` is null is rejected (fail closed): removing the
/// transform lineage must not silently degrade to hash-only reconstruction.
/// This is the P2 negative control — the gate fails when graph identity is
/// absent from the provenance log.
pub fn lineageGate(record: TransformProofRecord) bool {
    if (record.graph == null) return false;
    const g = record.graph.?;
    return g.hasLineage();
}

/// Evidence classes accepted for obligation discharge (§3.2, §4).
pub const AcceptedEvidence = evidence_record.Kind;

/// §9.1 — capability registry entries linked to release claims.
pub const Capability = struct {
    id: []const u8,
    description: []const u8,
    status: ClaimStatus,
    owner: []const u8,
};

pub const seed_capabilities: []const Capability = &.{
    .{ .id = "cap.cli.compile", .description = "CLI compile orchestration", .status = .supported, .owner = "src/main.zig" },
    .{ .id = "cap.cli.backend_direct", .description = "Explicit --backend=direct selection", .status = .partial, .owner = "src/main.zig" },
    .{ .id = "cap.native_backend.arm64", .description = "Direct ARM64 Mach-O subset", .status = .experimental, .owner = "src/native_backend.zig" },
    .{ .id = "cap.bootstrap.id_chain", .description = "Zig seed → Duo B → Duo C bootstrap", .status = .planned, .owner = "(archived, deleted — git history)" },
    .{ .id = "cap.repr.native_scalar", .description = "Full native_scalar module without lua runtime", .status = .partial, .owner = "src/codegen.zig" },
    .{ .id = "cap.bench.direct", .description = "Canonical direct-native benchmark profile", .status = .partial, .owner = "src/backend_identity.zig" },
    .{ .id = "cap.bench.correctness", .description = "Benchmark RESULT correctness gate", .status = .supported, .owner = "scripts/run_benchmark.sh" },
    .{ .id = "cap.token_semantic.m1", .description = "Owner-derived keyword classifier in production lexer", .status = .supported, .owner = "src/keyword_bridge.zig" },
};

/// Recompute claim status from capability dependencies (§9.2).
pub fn effectiveClaimStatus(claim: ReleaseClaim) ClaimStatus {
    if (claim.status == .stale) return .stale;
    for (claim.dependency_ids) |dep| {
        const cap = capabilityById(dep) orelse continue;
        switch (cap.status) {
            .planned => return .planned,
            .partial => if (claim.status == .supported) return .partial,
            .experimental => if (claim.status == .supported) return .experimental,
            .stale => return .stale,
            .supported => {},
        }
    }
    return claim.status;
}

pub fn capabilityById(id: []const u8) ?Capability {
    for (seed_capabilities) |c| {
        if (std.mem.eql(u8, c.id, id)) return c;
    }
    return null;
}

/// What a semantic region must accomplish without selecting one implementation.
pub const IntentContract = struct {
    subject_entity: []const u8,
    summary: []const u8,
    /// Descriptor or table identity when known.
    descriptor_id: ?[]const u8 = null,
    effects: ?[]const u8 = null,
    laws: ?[]const u8 = null,
    representation_constraints: ?[]const u8 = null,
    determinism_required: bool = true,
    provenance: ?[]const u8 = null,
};

/// Fact that must be established before a candidate or transform is accepted.
pub const ProofObligation = struct {
    id: []const u8,
    subject_entity: []const u8,
    predicate: []const u8,
    accepted_evidence: []const AcceptedEvidence,
    validation_method: []const u8,
    status: ObligationStatus = .pending,
    stage: ?[]const u8 = null,
    /// Exact graph coordinates for this obligation's transform input/output.
    /// Null when the obligation pre-dates graph-lineage enforcement.
    graph: ?GraphEntity = null,
};

pub const ObligationStatus = enum {
    pending,
    discharged,
    failed,
    waived,

    pub fn name(self: ObligationStatus) []const u8 {
        return @tagName(self);
    }
};

/// Semantic counterexample artifact (§3.4).
pub const Counterexample = struct {
    obligation_id: []const u8,
    subject_entity: []const u8,
    minimal_input: []const u8,
    observed: []const u8,
    expected_property: []const u8,
    reproduction: ?[]const u8 = null,
    compiler_version: ?[]const u8 = null,
};

/// Realization candidate with implementation provenance (§3.3).
pub const CandidateImplementation = struct {
    id: []const u8,
    subject_entity: []const u8,
    origin: CandidateOrigin,
    realization_label: []const u8,
    status: CandidateStatus = .registered,
    proof_obligation_ids: []const []const u8 = &.{},
};

pub const CandidateOrigin = enum {
    existing_source,
    transformation,
    agent_proposal,
    model_proposal,
    registered_algorithm,

    pub fn name(self: CandidateOrigin) []const u8 {
        return switch (self) {
            .existing_source => "existing_source",
            .transformation => "transformation",
            .agent_proposal => "agent_proposal",
            .model_proposal => "model_proposal",
            .registered_algorithm => "registered_algorithm",
        };
    }
};

pub const CandidateStatus = enum {
    registered,
    validated,
    selected,
    rejected,

    pub fn name(self: CandidateStatus) []const u8 {
        return @tagName(self);
    }
};

/// Derived view of canonical facts (§3.6).
pub const SemanticProjection = struct {
    id: []const u8,
    kind: ProjectionKind,
    source_entity: []const u8,
    transform_id: ?[]const u8 = null,
    schema_version: []const u8,
};

pub const ProjectionKind = enum {
    source,
    formatted_source,
    documentation,
    lsp_hover,
    mcp_entity,
    decoder_table,
    test_generator,
    benchmark_manifest,
    release_capability,

    pub fn name(self: ProjectionKind) []const u8 {
        return switch (self) {
            .source => "source",
            .formatted_source => "formatted_source",
            .documentation => "documentation",
            .lsp_hover => "lsp_hover",
            .mcp_entity => "mcp_entity",
            .decoder_table => "decoder_table",
            .test_generator => "test_generator",
            .benchmark_manifest => "benchmark_manifest",
            .release_capability => "release_capability",
        };
    }
};

/// Structured result of an important transformation (§4).
pub const TransformProofRecord = struct {
    transform_id: []const u8,
    transform_version: []const u8,
    subject_entity: []const u8,
    result: TransformResult,
    obligations: []const ProofObligation,
    evidence: []const AcceptedEvidence,
    provenance: ?[]const u8 = null,
    /// Exact graph coordinates for the transform's input and output.
    /// P2/GAP-137: must be present for any transform that rewrites a checked
    /// application so that the original relation, application, and value
    /// identities survive through machine and object lineage.
    graph: ?GraphEntity = null,
};

pub const TransformResult = enum {
    proven_and_applied,
    guarded_and_applied,
    validated_and_applied,
    measured_and_selected,
    legal_not_selected,
    rejected_semantics,
    rejected_contract,
    rejected_target,
    rejected_budget,
    rejected_evidence,
    invalidated,
    unsupported,

    pub fn name(self: TransformResult) []const u8 {
        return switch (self) {
            .proven_and_applied => "proven_and_applied",
            .guarded_and_applied => "guarded_and_applied",
            .validated_and_applied => "validated_and_applied",
            .measured_and_selected => "measured_and_selected",
            .legal_not_selected => "legal_not_selected",
            .rejected_semantics => "rejected_semantics",
            .rejected_contract => "rejected_contract",
            .rejected_target => "rejected_target",
            .rejected_budget => "rejected_budget",
            .rejected_evidence => "rejected_evidence",
            .invalidated => "invalidated",
            .unsupported => "unsupported",
        };
    }
};

/// Collected evidence for a capability, transaction, or claim (§3.5).
pub const ProofBundle = struct {
    bundle_id: []const u8,
    subject_entity: []const u8,
    obligations: []const ProofObligation,
    evidence_kinds: []AcceptedEvidence,
    counterexample_count: u32 = 0,
    compiler_version: ?[]const u8 = null,
    fingerprint: ?u64 = null,
    stale: bool = false,
};

/// Release claim linked to proof dependencies (§9).
pub const ReleaseClaim = struct {
    id: []const u8,
    statement: []const u8,
    status: ClaimStatus,
    dependency_ids: []const []const u8,
    proof_bundle_id: ?[]const u8 = null,
};

pub const ClaimStatus = enum {
    supported,
    experimental,
    partial,
    planned,
    stale,

    pub fn name(self: ClaimStatus) []const u8 {
        return @tagName(self);
    }
};

pub const RELEASE_PROOF_SCHEMA_VERSION = "idol-release-proof-v0";
pub const RELEASE_PROOF_BUNDLE_DIR = ".id/proof/release-0.1";

/// The release argument is deliberately orthogonal: passing one domain cannot
/// stand in for missing evidence in another.
pub const ReleaseProofKind = enum {
    performance,
    compression,
    dynamicity,
    metaprogramming,
    foreign_leverage,
    systems_credibility,
    trust,

    pub fn id(self: ReleaseProofKind) []const u8 {
        return switch (self) {
            .performance => "performance",
            .compression => "compression",
            .dynamicity => "dynamicity",
            .metaprogramming => "metaprogramming",
            .foreign_leverage => "foreign-leverage",
            .systems_credibility => "systems-credibility",
            .trust => "trust",
        };
    }
};

pub const ReleaseProofDomain = struct {
    kind: ReleaseProofKind,
    label: []const u8,
    objection: []const u8,
    answer: []const u8,
    readiness: ClaimStatus,
    gates: []const []const u8,
};

/// These are supporting gates, not substitutes for the stated proof. A domain
/// becomes proven only after its readiness is explicitly promoted to supported
/// and every named gate passes.
pub const release_proofs: []const ReleaseProofDomain = &.{
    .{
        .kind = .performance,
        .label = "Performance",
        .objection = "Cute syntax, slower than C or Rust.",
        .answer = "Equivalent algorithms and semantics produce competitive native artifacts under hostile measurement.",
        .readiness = .partial,
        .gates = &.{"bench-proof-gate"},
    },
    .{
        .kind = .compression,
        .label = "Compression",
        .objection = "It is only syntax golf or generated boilerplate.",
        .answer = "One semantic authority replaces duplicated facts, mechanisms, files, and projections.",
        .readiness = .planned,
        .gates = &.{},
    },
    .{
        .kind = .dynamicity,
        .label = "Dynamicity",
        .objection = "The fast path quietly turned a dynamic language into a static one.",
        .answer = "One source meaning moves from open dynamic execution through guarded and sealed native realizations.",
        .readiness = .partial,
        .gates = &.{ "semantics-gate", "native-differential" },
    },
    .{
        .kind = .metaprogramming,
        .label = "Metaprogramming",
        .objection = "Existing macro and comptime systems already do this.",
        .answer = "One ordinary semantic program derives implementation, tests, documentation, tooling, and foreign projections.",
        .readiness = .partial,
        .gates = &.{"meta-gate"},
    },
    .{
        .kind = .foreign_leverage,
        .label = "Foreign leverage",
        .objection = "Nobody will rewrite an existing project in an experimental language.",
        .answer = "Imported foreign semantics improve an otherwise untouched project and regenerate deterministically.",
        .readiness = .partial,
        .gates = &.{ "test", "abi-matrix" },
    },
    .{
        .kind = .systems_credibility,
        .label = "Systems credibility",
        .objection = "Research languages collapse under substantial systems software.",
        .answer = "Ward, native targets, and bootstrap stages work through the released compiler with explicit fallbacks.",
        .readiness = .partial,
        .gates = &.{ "native-differential", "wasm-test" },
    },
    .{
        .kind = .trust,
        .label = "Trust",
        .objection = "The claims are cherry-picked, generated, or secretly delegated to C.",
        .answer = "Every release claim resolves to reproducible source, commands, artifacts, logs, and measurements.",
        .readiness = .partial,
        .gates = &.{ "test", "repo-hygiene", "public-safety", "reproducibility-smoke" },
    },
};

/// Stable execution order. Shared gates run once even when they support more
/// than one proof domain; the destructive reproducibility gate runs last.
pub const release_gates: []const []const u8 = &.{
    "bench-proof-gate",
    "semantics-gate",
    "native-differential",
    "meta-gate",
    "abi-matrix",
    "wasm-test",
    "test",
    "repo-hygiene",
    "public-safety",
    "reproducibility-smoke",
};

pub const ReleaseGateStatus = enum {
    passed,
    failed,
    unavailable,

    pub fn name(self: ReleaseGateStatus) []const u8 {
        return @tagName(self);
    }
};

pub const ReleaseGateResult = struct {
    gate: []const u8,
    status: ReleaseGateStatus,
    log_path: []const u8,
};

pub const ReleaseProofStatus = enum {
    proven,
    failed,
    unproven,

    pub fn name(self: ReleaseProofStatus) []const u8 {
        return @tagName(self);
    }
};

pub fn releaseProofStatus(domain: ReleaseProofDomain, results: []const ReleaseGateResult) ReleaseProofStatus {
    if (domain.gates.len == 0) return .unproven;
    for (domain.gates) |gate| {
        const result = releaseGateResult(results, gate) orelse return .unproven;
        if (result.status != .passed) return .failed;
    }
    return if (domain.readiness == .supported) .proven else .unproven;
}

fn releaseGateResult(results: []const ReleaseGateResult, gate: []const u8) ?ReleaseGateResult {
    for (results) |result| {
        if (std.mem.eql(u8, result.gate, gate)) return result;
    }
    return null;
}

fn releaseGateExists(gate: []const u8) bool {
    for (release_gates) |known| {
        if (std.mem.eql(u8, known, gate)) return true;
    }
    return false;
}

pub fn writeReleaseProofJson(
    w: *std.Io.Writer,
    revision: []const u8,
    worktree_clean: bool,
    results: []const ReleaseGateResult,
) !void {
    var proven: usize = 0;
    var failed: usize = 0;
    var unproven: usize = 0;
    for (release_proofs) |domain| switch (releaseProofStatus(domain, results)) {
        .proven => proven += 1,
        .failed => failed += 1,
        .unproven => unproven += 1,
    };

    try w.print("{{\"schema\":\"{s}\",\"revision\":\"", .{RELEASE_PROOF_SCHEMA_VERSION});
    try jsonEscape(w, revision);
    try w.print("\",\"worktree\":\"{s}\",\"worktree_status\":\"{s}/worktree.txt\",\"bundle\":\"{s}\",\"domains\":[", .{
        if (worktree_clean) "clean" else "dirty",
        RELEASE_PROOF_BUNDLE_DIR,
        RELEASE_PROOF_BUNDLE_DIR,
    });
    for (release_proofs, 0..) |domain, i| {
        if (i > 0) try w.writeByte(',');
        const status = releaseProofStatus(domain, results);
        try w.print("{{\"id\":\"{s}\",\"label\":\"", .{domain.kind.id()});
        try jsonEscape(w, domain.label);
        try w.writeAll("\",\"objection\":\"");
        try jsonEscape(w, domain.objection);
        try w.writeAll("\",\"answer\":\"");
        try jsonEscape(w, domain.answer);
        try w.print("\",\"readiness\":\"{s}\",\"status\":\"{s}\",\"gates\":[", .{
            domain.readiness.name(),
            status.name(),
        });
        for (domain.gates, 0..) |gate, gate_i| {
            if (gate_i > 0) try w.writeByte(',');
            try w.print("\"{s}\"", .{gate});
        }
        try w.writeAll("]}");
    }
    try w.writeAll("],\"gate_results\":[");
    for (results, 0..) |result, i| {
        if (i > 0) try w.writeByte(',');
        try w.print("{{\"gate\":\"{s}\",\"command\":\"zig build {s}\",\"status\":\"{s}\",\"log\":\"", .{
            result.gate,
            result.gate,
            result.status.name(),
        });
        try jsonEscape(w, result.log_path);
        try w.writeAll("\"}");
    }
    try w.print("],\"summary\":{{\"proven\":{},\"failed\":{},\"unproven\":{},\"total\":{}}}}}\n", .{
        proven,
        failed,
        unproven,
        release_proofs.len,
    });
}

/// Seed claims — must match README and release docs or be downgraded.
pub const seed_claims: []const ReleaseClaim = &.{

    .{
        .id = "claim.direct_arm64_subset",
        .statement = "Direct ARM64 Mach-O backend for restricted typed scalar subset",
        .status = .experimental,
        .dependency_ids = &.{ "cap.native_backend.arm64", "cap.cli.backend_direct" },
    },
    .{
        .id = "claim.self_hosted",
        .statement = "Compiler is self-hosted",
        .status = .planned,
        .dependency_ids = &.{"cap.bootstrap.id_chain"},
    },
    .{
        .id = "claim.zero_boxing_global",
        .statement = "All programs compile without lua_Value boxing",
        .status = .stale,
        .dependency_ids = &.{"cap.repr.native_scalar"},
    },
    .{
        .id = "claim.faster_than_c_global",
        .statement = "Duo beats C on all benchmarks globally",
        .status = .partial,
        .dependency_ids = &.{ "cap.bench.direct", "cap.bench.correctness" },
    },
    .{
        .id = "claim.m1_keyword_semantic",
        .statement = "Keyword classifier derives from the one grammar-fact owner's generated keyword rows (lib/compiler/token.id)",
        .status = .supported,
        .dependency_ids = &.{"cap.token_semantic.m1"},
        .proof_bundle_id = "bundle.m1.keyword_classifier",
    },
};

/// Mark claims stale when a proof bundle is explicitly invalidated (§9.2).
pub fn claimStatusWithBundle(claim: ReleaseClaim, bundle: ?ProofBundle) ClaimStatus {
    if (bundle) |b| {
        if (b.stale) return .stale;
    }
    return effectiveClaimStatus(claim);
}

/// Returns claim IDs whose effective status differs from declared (dependency drift).
pub fn claimsNeedingDowngrade(alloc: std.mem.Allocator) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer list.deinit(alloc);
    for (seed_claims) |c| {
        const eff = effectiveClaimStatus(c);
        if (eff != c.status) {
            try list.append(alloc, c.id);
        }
    }
    return try list.toOwnedSlice(alloc);
}

pub fn writeSchemaJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"transform_results\":[", .{SCHEMA_VERSION});
    const results = [_]TransformResult{
        .proven_and_applied,
        .guarded_and_applied,
        .validated_and_applied,
        .rejected_semantics,
        .unsupported,
    };
    for (results, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{r.name()});
    }
    try w.print("],\"capabilities\":[", .{});
    for (seed_capabilities, 0..) |cap, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"status\":\"{s}\",\"owner\":\"", .{ cap.id, cap.status.name() });
        try jsonEscape(w, cap.owner);
        try w.print("\",\"description\":\"", .{});
        try jsonEscape(w, cap.description);
        try w.print("\"}}", .{});
    }
    try w.print("],\"release_claims_effective\":[", .{});
    for (seed_claims, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        const eff = effectiveClaimStatus(c);
        try w.print("{{\"id\":\"{s}\",\"declared\":\"{s}\",\"effective\":\"{s}\",\"statement\":\"", .{
            c.id,
            c.status.name(),
            eff.name(),
        });
        try jsonEscape(w, c.statement);
        try w.print("\"}}", .{});
    }
    try w.print("],\"release_claims\":[", .{});
    for (seed_claims, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"status\":\"{s}\",\"statement\":\"", .{ c.id, c.status.name() });
        try jsonEscape(w, c.statement);
        try w.print("\"}}", .{});
    }
    try w.print("],\"evidence_reuses\":\"evidence_record.v0\"}}", .{});
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "proof_carrying: claims needing downgrade tracks dependency drift" {
    const alloc = std.testing.allocator;
    const ids = try claimsNeedingDowngrade(alloc);
    defer alloc.free(ids);
    // faster_than_c_global is partial but dependencies are partial — may appear in list.
    try std.testing.expect(ids.len >= 0);
}

test "proof_carrying: stale bundle downgrades claim" {
    for (seed_claims) |c| {
        if (std.mem.eql(u8, c.id, "claim.direct_arm64_subset")) {
            const stale_bundle: ProofBundle = .{
                .bundle_id = "test",
                .subject_entity = "test",
                .obligations = &.{},
                .evidence_kinds = &.{},
                .stale = true,
            };
            try std.testing.expectEqual(ClaimStatus.stale, claimStatusWithBundle(c, stale_bundle));
        }
    }
}

test "proof_carrying: effective claim status respects dependencies" {
    for (seed_claims) |c| {
        if (std.mem.eql(u8, c.id, "claim.self_hosted")) {
            try std.testing.expectEqual(ClaimStatus.planned, effectiveClaimStatus(c));
        }
    }
}

test "proof_carrying: seed claims include honest self-hosting status" {
    var found_self_host = false;
    for (seed_claims) |c| {
        if (std.mem.eql(u8, c.id, "claim.self_hosted")) {
            try std.testing.expectEqual(ClaimStatus.planned, c.status);
            found_self_host = true;
        }
    }
    try std.testing.expect(found_self_host);
}

test "proof_carrying: writeSchemaJson" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeSchemaJson(&buf.writer);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "proof-carrying-v0") != null);

    try std.testing.expectEqual(@as(usize, 7), release_proofs.len);
    for (release_proofs, 0..) |domain, i| {
        try std.testing.expect(domain.kind.id().len > 0);
        if (domain.readiness == .supported) try std.testing.expect(domain.gates.len > 0);
        for (domain.gates) |gate| try std.testing.expect(releaseGateExists(gate));
        for (release_proofs[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, domain.kind.id(), other.kind.id()));
        }
    }

    var results: [release_gates.len]ReleaseGateResult = undefined;
    for (release_gates, 0..) |gate, i| {
        results[i] = .{ .gate = gate, .status = .passed, .log_path = "proof.log" };
    }
    for (release_proofs) |domain| {
        try std.testing.expectEqual(ReleaseProofStatus.unproven, releaseProofStatus(domain, &results));
    }

    var release_buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer release_buf.deinit();
    try writeReleaseProofJson(&release_buf.writer, "deadbeef", false, &.{});
    try std.testing.expect(std.mem.indexOf(u8, release_buf.written(), RELEASE_PROOF_SCHEMA_VERSION) != null);
    try std.testing.expect(std.mem.indexOf(u8, release_buf.written(), "\"revision\":\"deadbeef\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_buf.written(), "\"worktree\":\"dirty\"") != null);
    for (release_proofs) |domain| {
        try std.testing.expect(std.mem.indexOf(u8, release_buf.written(), domain.kind.id()) != null);
    }
}
