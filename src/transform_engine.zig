/// Bootstrap transformation registry and provenance bridge.
///
/// Semantic law lives only in `docs/spec/constitution.md`. Graph identities and
/// facts own meaning; this host file records temporary dispatch and provenance
/// mechanics and must not become another semantic transformation authority.
/// Phase 0–1: catalog + parity metadata + provenance log.
/// Phase 2 (partial): combinator evaluation entry is `meta_dispatch.dispatchAtSite`
/// (gates via `requireMetaDispatchBeforeHook`, provenance via `dispatchMetaCombinator`).
const std = @import("std");
const meta_module = @import("meta_module.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const proof_carrying = @import("proof_carrying.zig");
const evidence = @import("evidence.zig");

pub const BudgetClass = enum {
    constant,
    linear,
    polynomial,
    exponential,
    factorial,
};

pub const OutputKind = enum {
    native_string,
    native_int,
    native_bool,
    c_fragment,
    type_set,
    side_effect,
};

pub const SiteKind = enum {
    top_level_assign,
    nested_callback,
    block_body,
    emit_call,
};

pub const Contract = struct {
    native_only: bool = true,
    max_matching_types: ?usize = null,
    requires_callback: bool = false,
    /// All evaluation sites must behave identically (G-060 lesson).
    parity_sites: []const SiteKind = &.{},
};

/// directive hardness — distinguishes preferences from requirements.
pub const Hardness = enum {
    /// Compiler may ignore (e.g. @prefer.inline, @hot).
    preference,
    /// Compiler warns when unmet (e.g. @expect.vectorized).
    expectation,
    /// Compilation fails when unmet (e.g. @require.noalloc).
    requirement,
    /// Programmer asserts a fact; compiler verifies or rejects (e.g. @assert.pure).
    assertion,
    /// Compilation fails when a measured/estimated limit is exceeded (e.g. @budget.stack(512)).
    budget,
    /// Informational — produces compiler output but doesn't constrain (e.g. @comp.why).
    query,

    pub fn name(self: Hardness) []const u8 {
        return @tagName(self);
    }

    /// True if unmet hardness should produce an error (not just a warning).
    pub fn isHard(self: Hardness) bool {
        return self == .requirement or self == .assertion or self == .budget;
    }
};

pub const Descriptor = struct {
    public_name: []const u8,
    internal_name: []const u8,
    budget: BudgetClass,
    output: OutputKind,
    contract: Contract,
    /// Minimum knowledge required on inputs (convergence).
    min_knowledge: semantic_algebra.KnowledgeLevel = .observed,
    /// Default cost hint for portfolio selection (convergence).
    cost_hint: semantic_algebra.CostVector = semantic_algebra.CostVector.neutral(),
    /// how strongly this directive constrains the compiler.
    hardness: Hardness = .preference,
};

/// classification of evidence supporting a compiler decision.
/// Every optimization decision, assumption, and realization selection should
/// record what KIND of evidence supports it.
pub const Evidence = enum(u8) {
    /// Proven from semantic facts alone (always valid).
    semantic_proof = 0,
    /// Guarded by a runtime check (valid until guard fails).
    guarded = 1,
    /// Static cost estimate from compiler model.
    static_estimate = 2,
    /// Target-specific cost model estimate.
    target_estimate = 3,
    /// Profile observation from execution.
    profile = 4,
    /// Benchmark measurement (explicit, reproducible).
    benchmark = 5,
    /// User assertion (programmer claims; compiler may verify).
    user_assertion = 6,
    /// Imported from foreign metadata.
    imported = 7,
    /// Default heuristic (no specific evidence).
    heuristic = 8,

    pub fn name(self: Evidence) []const u8 {
        return @tagName(self);
    }

    /// Evidence reliability ordering (lower = more reliable).
    pub fn reliability(self: Evidence) u8 {
        return @backingInt(self);
    }

    /// True if this evidence is deterministic and reproducible.
    pub fn isDeterministic(self: Evidence) bool {
        return self == .semantic_proof or self == .static_estimate or self == .target_estimate;
    }
};

pub const ProvenanceEntry = struct {
    public_name: []const u8,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
    /// what evidence supports this transformation outcome.
    evidence: Evidence = .heuristic,
    /// P2/GAP-137: exact graph coordinates retained through transformation
    /// provenance so a transformed application remains traceable from
    /// relation → realization → machine → bytes. Null when the caller
    /// predates graph-lineage enforcement (hash-only entry).
    graph: ?proof_carrying.GraphEntity = null,
};

var provenance_log: std.ArrayListUnmanaged(ProvenanceEntry) = .empty;
var provenance_enabled: bool = false;

/// Provenance log outlives per-compile arenas; never use the caller's arena for storage.
const provenance_allocator = std.heap.page_allocator;

pub fn deinitProvenance(_: std.mem.Allocator) void {
    provenance_log.deinit(provenance_allocator);
    provenance_log = .empty;
    provenance_snapshot.deinit(provenance_allocator);
    provenance_snapshot = .empty;
    deinitProofLog(provenance_allocator);
    provenance_enabled = false;
}

pub fn setProvenanceEnabled(enabled: bool) void {
    if (enabled) {
        provenance_log.clearRetainingCapacity();
        deinitProofLog(provenance_allocator);
    }
    provenance_enabled = enabled;
    if (!enabled) {
        provenance_log.clearRetainingCapacity();
        deinitProofLog(provenance_allocator);
    }
}

pub fn provenanceEntries() []const ProvenanceEntry {
    return provenance_log.items;
}

/// H-8: the provenance log is CLEARED by `setProvenanceEnabled(false)`,
/// which a provenance run's own `defer` fires before any caller can render it.
/// The snapshot is what survives that teardown so the state can leave the
/// process as `(transform, site, hashes)` data instead of staying invisible.
var provenance_snapshot: std.ArrayListUnmanaged(ProvenanceEntry) = .empty;

pub fn snapshotProvenance() void {
    provenance_snapshot.clearRetainingCapacity();
    provenance_snapshot.appendSlice(provenance_allocator, provenance_log.items) catch {};
}

pub fn clearProvenanceSnapshot() void {
    provenance_snapshot.clearRetainingCapacity();
}

pub fn provenanceSnapshotEntries() []const ProvenanceEntry {
    return provenance_snapshot.items;
}

/// Sites observed in the SNAPSHOT (the post-run projection of the log).
pub fn snapshotSitesObserved(public_name: []const u8) std.EnumSet(SiteKind) {
    var seen = std.EnumSet(SiteKind).empty;
    for (provenanceSnapshotEntries()) |e| {
        if (std.mem.eql(u8, e.public_name, public_name)) seen.insert(e.site);
    }
    return seen;
}

/// The observed provenance log, rendered. One object per dispatch.
pub fn writeProvenanceJson(w: *std.Io.Writer) !void {
    const entries = provenanceSnapshotEntries();
    try w.print("{{\"schema\":\"transform-provenance-v0\",\"entry_count\":{d},\"entries\":[", .{entries.len});
    for (entries, 0..) |e, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"transform\":\"{s}\",\"site\":\"{s}\",\"inputs_hash\":\"{x}\",\"output_hash\":\"{x}\",\"evidence\":\"{s}\"",
            .{ e.public_name, siteKindName(e.site), e.inputs_hash, e.output_hash, e.evidence.name() },
        );
        if (e.graph) |g| {
            try w.print(
                ",\"graph\":{{\"relation\":{?d},\"application\":{?d},\"subject\":{?d},\"input_value\":{?d},\"output_value\":{?d}}}",
                .{ g.relation, g.application, g.subject, g.input_value, g.output_value },
            );
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

/// The tier-1 registry with its contract, and — per transform — whether every
/// DECLARED parity site was OBSERVED in this run. Declared-vs-observed in one
/// read is the whole point: a registry alone cannot convict a dispatch gate.
pub fn writeRegistryJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"transform-registry-v0\",\"tier1_count\":{d},\"tier1\":[", .{parity_tier1.len});
    for (parity_tier1, 0..) |public_name, i| {
        if (i > 0) try w.print(",", .{});
        const d = descriptor(public_name);
        try w.print("{{\"transform\":\"{s}\",\"registered\":{s},\"requires_parity\":{s}", .{
            public_name,
            if (d != null) "true" else "false",
            if (requiresParityTest(public_name)) "true" else "false",
        });
        if (d) |dd| {
            try w.print(",\"native_only\":{s},\"parity_contract_satisfied\":{s},\"parse_as_expression\":{s},\"budget\":\"{s}\",\"hardness\":\"{s}\",\"parity_sites\":[", .{
                if (dd.contract.native_only) "true" else "false",
                if (parityContractSatisfied(dd)) "true" else "false",
                if (mustParseAsExpression(public_name)) "true" else "false",
                @tagName(dd.budget),
                dd.hardness.name(),
            });
            for (dd.contract.parity_sites, 0..) |site, si| {
                if (si > 0) try w.print(",", .{});
                try w.print("\"{s}\"", .{siteKindName(site)});
            }
            try w.print("],\"observed_sites\":[", .{});
            const seen = snapshotSitesObserved(public_name);
            var first = true;
            for (dd.contract.parity_sites) |site| {
                if (!seen.contains(site)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try w.print("\"{s}\"", .{siteKindName(site)});
            }
            try w.print("],\"parity_observed\":{s}", .{
                if (snapshotParityObserved(public_name)) "true" else "false",
            });
        }
        try w.print("}}", .{});
    }
    // The call algebra, enumerated FROM the enum rather than from a list: a
    // new CallTransform variant that nobody registered shows up here as
    // `registered:false` instead of going unmeasured.
    try w.print("],\"call\":[", .{});
    {
        var i: usize = 0;
        inline for (@typeInfo(semantic_algebra.CallTransform).@"enum".field_values) |value| {
            if (i > 0) try w.print(",", .{});
            i += 1;
            const op: semantic_algebra.CallTransform = @fromBackingInt(@intCast(value));
            const id = semantic_algebra.callTransformId(op);
            const d = descriptor(id);
            try w.print("{{\"transform\":\"{s}\",\"is_call\":{s},\"registered\":{s}", .{
                id,
                if (isCallTransform(id)) "true" else "false",
                if (d != null) "true" else "false",
            });
            if (d) |dd| {
                try w.print(",\"native_only\":{s},\"parity_sites\":[", .{
                    if (dd.contract.native_only) "true" else "false",
                });
                for (dd.contract.parity_sites, 0..) |site, si| {
                    if (si > 0) try w.print(",", .{});
                    try w.print("\"{s}\"", .{siteKindName(site)});
                }
                try w.print("],\"observed\":{s}", .{
                    if (snapshotSitesObserved(id).count() > 0) "true" else "false",
                });
            }
            try w.print("}}", .{});
        }
    }
    try w.print("],\"internal_gate\":[", .{});
    for (tier1_internal_hooks, 0..) |internal, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"hook\":\"{s}\",\"public\":\"{s}\",\"dispatch_allowed\":{s}}}", .{
            internal,
            publicNameForInternal(internal) orelse "",
            if (requireMetaDispatchBeforeHook(internal)) "true" else "false",
        });
    }
    try w.print("]}}", .{});
}

/// Internal codegen/comptime hook names carrying a tier-1 registry mapping.
pub const tier1_internal_hooks: []const []const u8 = &.{
    "__comptimemap",
    "__comptimematch",
    "__comptimepower",
    "__derivepower",
    "__comptimefixpoint",
    "__comptimetabulate",
    "__comptimeinterpolate",
    "__comptimeeach",
    // Mapped but NOT tier-1: it must still clear the dispatch gate under
    // `DUO_TRANSFORM_GATE=1`, which is the half of strict mode that a list of
    // parity combinators alone cannot show.
    "__metacatalog",
};

/// `tier1ParityObserved` against the snapshot rather than the live log.
pub fn snapshotParityObserved(public_name: []const u8) bool {
    if (!requiresParityTest(public_name)) return true;
    const d = descriptor(public_name) orelse return false;
    const observed = snapshotSitesObserved(public_name);
    for (d.contract.parity_sites) |site| {
        if (!observed.contains(site)) return false;
    }
    return true;
}

pub fn siteKindName(site: SiteKind) []const u8 {
    return switch (site) {
        .top_level_assign => "top_level_assign",
        .nested_callback => "nested_callback",
        .block_body => "block_body",
        .emit_call => "emit_call",
    };
}

/// Print provenance log to stderr when `DUO_PROVENANCE=1`.
pub fn dumpProvenanceSummary(io: std.Io, stderr: std.Io.File) void {
    const entries = provenanceEntries();
    if (entries.len == 0) return;
    var buf: [512]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stderr, io, &buf);
    fw.interface.print("[duo provenance] {d} transform(s)\n", .{entries.len}) catch return;
    for (entries) |e| {
        fw.interface.print(
            "  {s} @ {s} in={x} out={x}\n",
            .{ e.public_name, siteKindName(e.site), e.inputs_hash, e.output_hash },
        ) catch return;
    }
    fw.interface.flush() catch {};
}

/// Map internal codegen/comptime hook names to canonical `comp.*` registry ids.
pub fn publicNameForInternal(internal: []const u8) ?[]const u8 {
    return meta_module.publicNameForInternal(internal);
}

var meta_dispatch_strict: ?bool = null;

/// When true, mapped internal hooks without registry contract are rejected at dispatch.
pub fn setMetaDispatchStrict(enabled: bool) void {
    meta_dispatch_strict = enabled;
}

pub fn metaDispatchStrictEnabled() bool {
    if (meta_dispatch_strict) |v| return v;
    return false;
}

/// True when codegen/comptime may invoke a mapped internal meta hook (P6-07 gate).
pub fn requireMetaDispatchBeforeHook(internal: []const u8) bool {
    if (publicNameForInternal(internal) == null) return true;
    if (gateMetaDispatch(internal)) |_| return true;
    return !metaDispatchStrictEnabled();
}

/// Unified provenance dispatch for internal meta hooks — single entry from codegen (P6-07).
pub fn dispatchMetaCombinator(
    alloc: std.mem.Allocator,
    internal: []const u8,
    site: SiteKind,
    input: []const u8,
    output: []const u8,
) void {
    if (gateMetaDispatch(internal)) |_| {
        logInternalTransform(alloc, internal, site, input, output);
    }
}

/// Log provenance for a tier-1/internal meta hook when registered in the transform catalog.
pub fn logInternalTransform(
    alloc: std.mem.Allocator,
    internal: []const u8,
    site: SiteKind,
    input: []const u8,
    output: []const u8,
) void {
    const public_name = publicNameForInternal(internal) orelse return;
    if (!isRegisteredTransform(public_name)) return;
    logProvenance(
        alloc,
        public_name,
        site,
        std.hash.Wyhash.hash(0, input),
        std.hash.Wyhash.hash(0, output),
    );
}

pub const TRANSFORM_VERSION = "transform-registry-v0";

/// structured proof record for a logged transform application.
pub const TransformProofLogEntry = struct {
    record: proof_carrying.TransformProofRecord,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
    /// P2/GAP-137: exact graph input/output coordinates carried alongside
    /// the hash-based fingerprint so the lineage survives the proof log.
    graph: ?proof_carrying.GraphEntity = null,
};

var proof_log: std.ArrayListUnmanaged(TransformProofLogEntry) = .empty;
const proof_allocator = std.heap.page_allocator;

pub fn deinitProofLog(_: std.mem.Allocator) void {
    for (proof_log.items) |*e| {
        freeProofRecord(&e.record, proof_allocator);
    }
    proof_log.deinit(proof_allocator);
    proof_log = .empty;
}

pub fn proofLogEntries() []const TransformProofLogEntry {
    return proof_log.items;
}

pub fn evidenceKind(ev: Evidence) evidence.Kind {
    return switch (ev) {
        .semantic_proof => .proven_semantic_fact,
        .guarded => .guarded_fact,
        .static_estimate => .static_estimate,
        .target_estimate => .target_model_estimate,
        .profile => .profile_observation,
        .benchmark => .benchmark_measurement,
        .user_assertion => .user_assertion,
        .imported => .foreign_assertion,
        .heuristic => .static_estimate,
    };
}

/// Build a proof record for a registered transform (canonical P12-WS3 pattern).
pub fn buildTransformProofRecord(
    alloc: std.mem.Allocator,
    public_name: []const u8,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
    graph: ?proof_carrying.GraphEntity,
) !proof_carrying.TransformProofRecord {
    const d = descriptor(public_name) orelse {
        return .{
            .transform_id = try alloc.dupe(u8, public_name),
            .transform_version = TRANSFORM_VERSION,
            .subject_entity = try alloc.dupe(u8, "duo:transform:unknown"),
            .result = .unsupported,
            .obligations = &.{},
            .evidence = &.{},
            .graph = graph,
        };
    };

    const subject = try std.fmt.allocPrint(alloc, "duo:transform:{s}", .{public_name});
    errdefer alloc.free(subject);

    var result: proof_carrying.TransformResult = .validated_and_applied;
    var ev: Evidence = .semantic_proof;

    if (!d.contract.native_only) {
        result = .rejected_contract;
        ev = .heuristic;
    } else if (requiresParityTest(public_name) and !tier1ParityObserved(public_name)) {
        result = .guarded_and_applied;
        ev = .guarded;
    } else if (d.hardness.isHard()) {
        result = .proven_and_applied;
        ev = .semantic_proof;
    }

    const obligation_id = try std.fmt.allocPrint(alloc, "obl.{s}.native_only", .{public_name});
    errdefer alloc.free(obligation_id);
    const predicate = try std.fmt.allocPrint(alloc, "emit native output at {s}", .{siteKindName(site)});
    errdefer alloc.free(predicate);
    const validation = try std.fmt.allocPrint(alloc, "inputs_hash={x} output_hash={x}", .{ inputs_hash, output_hash });
    errdefer alloc.free(validation);

    const ev_slice = try alloc.alloc(evidence.Kind, 1);
    ev_slice[0] = evidenceKind(ev);

    const obligations = try alloc.alloc(proof_carrying.ProofObligation, 1);
    obligations[0] = .{
        .id = obligation_id,
        .subject_entity = subject,
        .predicate = predicate,
        .accepted_evidence = ev_slice,
        .validation_method = validation,
        .status = if (result == .rejected_contract) .failed else .discharged,
        .stage = try alloc.dupe(u8, siteKindName(site)),
        .graph = graph,
    };
    // subject owned by record.subject_entity; obligation borrows same pointer.

    return .{
        .transform_id = try alloc.dupe(u8, public_name),
        .transform_version = TRANSFORM_VERSION,
        .subject_entity = subject,
        .result = result,
        .obligations = obligations,
        .evidence = ev_slice,
        .provenance = try std.fmt.allocPrint(alloc, "transform_engine.log @ {s}", .{siteKindName(site)}),
        .graph = graph,
    };
}

fn recordProof(
    public_name: []const u8,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
    graph: ?proof_carrying.GraphEntity,
) void {
    if (!isRegisteredTransform(public_name)) return;
    const record = buildTransformProofRecord(proof_allocator, public_name, site, inputs_hash, output_hash, graph) catch return;
    proof_log.append(proof_allocator, .{
        .record = record,
        .site = site,
        .inputs_hash = inputs_hash,
        .output_hash = output_hash,
        .graph = graph,
    }) catch {
        freeProofRecord(&record, proof_allocator);
    };
}

fn freeProofRecord(record: *const proof_carrying.TransformProofRecord, alloc: std.mem.Allocator) void {
    alloc.free(record.transform_id);
    // transform_version is always the TRANSFORM_VERSION literal — never heap-allocated.
    alloc.free(record.subject_entity);
    for (record.obligations) |o| {
        alloc.free(o.id);
        alloc.free(o.predicate);
        alloc.free(o.validation_method);
        if (o.stage) |s| alloc.free(s);
        // o.subject_entity aliases record.subject_entity — freed above.
    }
    alloc.free(record.obligations);
    alloc.free(record.evidence);
    if (record.provenance) |p| alloc.free(p);
}

pub fn writeProofLogJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (proofLogEntries(), 0..) |e, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"transform_id\":\"{s}\",\"result\":\"{s}\",\"site\":\"{s}\",\"inputs_hash\":\"{x}\",\"output_hash\":\"{x}\",\"obligations_discharged\":{d}", .{
            e.record.transform_id,
            e.record.result.name(),
            siteKindName(e.site),
            e.inputs_hash,
            e.output_hash,
            blk: {
                var n: usize = 0;
                for (e.record.obligations) |o| {
                    if (o.status == .discharged) n += 1;
                }
                break :blk n;
            },
        });
        if (e.graph) |g| {
            try w.print(
                ",\"graph\":{{\"relation\":{?d},\"application\":{?d},\"subject\":{?d},\"input_value\":{?d},\"output_value\":{?d}}}",
                .{ g.relation, g.application, g.subject, g.input_value, g.output_value },
            );
        }
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

pub fn logProvenance(
    _: std.mem.Allocator,
    public_name: []const u8,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
) void {
    logProvenanceGraph(undefined, public_name, site, inputs_hash, output_hash, null);
}

/// Log provenance for a transform with exact graph entity coordinates (P2/GAP-137).
///
/// `graph` carries the semantic relation, application, subject, and input/output
/// value ids (`semantic_graph.id` = u32) so that a transformed application
/// remains queryable through graph → realization → machine → bytes without a
/// hash standing in for semantic identity. Pass `null` for transforms that
/// pre-date graph-lineage enforcement.
pub fn logProvenanceGraph(
    _: std.mem.Allocator,
    public_name: []const u8,
    site: SiteKind,
    inputs_hash: u64,
    output_hash: u64,
    graph: ?proof_carrying.GraphEntity,
) void {
    if (!provenance_enabled) return;
    provenance_log.append(provenance_allocator, .{
        .public_name = public_name,
        .site = site,
        .inputs_hash = inputs_hash,
        .output_hash = output_hash,
        .graph = graph,
    }) catch {};
    recordProof(public_name, site, inputs_hash, output_hash, graph);
}

/// Tier-1 combinators requiring 3-site parity (top-level, nested callback, block body).
pub const parity_tier1: []const []const u8 = &.{
    "comp.match",
    "comp.map",
    "comp.power",
    "comp.derive.power",
    "comp.fixpoint",
    "comp.tabulate",
    "comp.interpolate",
    "comp.each",
    "comp.zip",
    "comp.permute",
};

pub fn requiresParityTest(public_name: []const u8) bool {
    for (parity_tier1) |name| {
        if (std.mem.eql(u8, name, public_name)) return true;
    }
    return false;
}

/// Declared parity sites for a transform (harness / agent introspection).
pub fn paritySitesFor(public_name: []const u8) ?[]const SiteKind {
    const d = descriptor(public_name) orelse return null;
    return d.contract.parity_sites;
}

/// Sites observed in the current provenance log for a transform id.
pub fn provenanceSitesObserved(public_name: []const u8) std.EnumSet(SiteKind) {
    var seen = std.EnumSet(SiteKind).empty;
    for (provenanceEntries()) |e| {
        if (std.mem.eql(u8, e.public_name, public_name)) seen.insert(e.site);
    }
    return seen;
}

/// True when every declared parity site for a tier-1 combinator appears in the log.
pub fn tier1ParityObserved(public_name: []const u8) bool {
    if (!requiresParityTest(public_name)) return true;
    const d = descriptor(public_name) orelse return false;
    const observed = provenanceSitesObserved(public_name);
    for (d.contract.parity_sites) |site| {
        if (!observed.contains(site)) return false;
    }
    return true;
}

/// True when a descriptor declares all three G-061 evaluation sites.
pub fn parityContractSatisfied(d: Descriptor) bool {
    if (d.contract.parity_sites.len != 3) return false;
    var seen = std.EnumSet(SiteKind).empty;
    for (d.contract.parity_sites) |site| seen.insert(site);
    return seen.contains(.top_level_assign) and
        seen.contains(.nested_callback) and
        seen.contains(.block_body);
}

/// Gate codegen/comptime dispatch: tier-1 hooks must be registered with native contract.
pub fn gateMetaDispatch(internal: []const u8) ?Descriptor {
    const public_name = publicNameForInternal(internal) orelse return null;
    const d = descriptor(public_name) orelse return null;
    if (!d.contract.native_only) return null;
    return d;
}

/// Introspection transforms with fixed O(1) output (no parity sites required).
fn shapeIntrospectionDescriptor(public_name: []const u8, internal: []const u8) Descriptor {
    return .{
        .public_name = public_name,
        .internal_name = internal,
        .budget = .constant,
        .output = .native_string,
        .contract = .{
            .native_only = true,
            .max_matching_types = null,
            .requires_callback = false,
            .parity_sites = &[_]SiteKind{},
        },
        .min_knowledge = .observed,
        .hardness = .query,
        .cost_hint = blk: {
            var c = semantic_algebra.CostVector.neutral();
            c.set(.compile_time, 0.01);
            break :blk c;
        },
    };
}

fn abiSpecializeDescriptor() Descriptor {
    return .{
        .public_name = "abi.specialize",
        .internal_name = "abi.specialize",
        .budget = .linear,
        .output = .c_fragment,
        .contract = .{
            .native_only = true,
            .max_matching_types = null,
            .requires_callback = false,
            .parity_sites = &[_]SiteKind{.emit_call},
        },
        .min_knowledge = .stable,
        .cost_hint = blk: {
            var c = semantic_algebra.CostVector.neutral();
            c.set(.compile_time, 0.05);
            break :blk c;
        },
    };
}

/// Static catalog — grows as combinators migrate to the engine (Phase 2).
pub fn descriptor(public_name: []const u8) ?Descriptor {
    if (shapeOpFromTransformId(public_name)) |op| {
        return shapeTransformDescriptor(public_name, op);
    }
    if (callTransformFromId(public_name)) |op| {
        return callTransformDescriptor(public_name, op);
    }
    if (iterationRelationFromTransformId(public_name)) |relation| {
        return iterationRelationDescriptor(public_name, relation);
    }
    if (std.mem.eql(u8, public_name, "comp.type.shape") or
        std.mem.eql(u8, public_name, "comp.shape") or
        std.mem.eql(u8, public_name, "meta.type.shape") or
        std.mem.eql(u8, public_name, "meta.shape"))
    {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__type_shape";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.why.shape") or
        std.mem.eql(u8, public_name, "meta.why.shape"))
    {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__why_shape";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.why.boxed") or
        std.mem.eql(u8, public_name, "meta.why.boxed"))
    {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__why_boxed";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.why.not.native") or
        std.mem.eql(u8, public_name, "meta.why.not.native"))
    {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__why_not_native";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.representation") or
        std.mem.eql(u8, public_name, "meta.representation"))
    {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__representation";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.why") or std.mem.eql(u8, public_name, "meta.why")) {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__why";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.why.module") or std.mem.eql(u8, public_name, "meta.why.module")) {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__why_module";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "comp.origin") or std.mem.eql(u8, public_name, "meta.origin")) {
        const internal = meta_module.resolveBuiltin(public_name) orelse "__origin";
        return shapeIntrospectionDescriptor(public_name, internal);
    }
    if (std.mem.eql(u8, public_name, "abi.specialize")) {
        return abiSpecializeDescriptor();
    }
    const internal = meta_module.resolveBuiltin(public_name) orelse return null;
    const budget: BudgetClass = blk: {
        if (std.mem.endsWith(u8, public_name, ".permute")) break :blk .factorial;
        if (std.mem.endsWith(u8, public_name, ".power") or
            std.mem.endsWith(u8, public_name, ".powerset") or
            std.mem.endsWith(u8, public_name, ".derive.power"))
            break :blk .exponential;
        if (std.mem.endsWith(u8, public_name, ".product") or
            std.mem.endsWith(u8, public_name, ".tensor") or
            std.mem.endsWith(u8, public_name, ".nfold"))
            break :blk .polynomial;
        break :blk .linear;
    };
    const max_types: ?usize = if (budget == .exponential) 24 else null;
    const needs_cb = std.mem.endsWith(u8, public_name, ".match") or
        std.mem.endsWith(u8, public_name, ".map") or
        std.mem.endsWith(u8, public_name, ".tabulate") or
        std.mem.endsWith(u8, public_name, ".fixpoint") or
        std.mem.endsWith(u8, public_name, ".power") or
        std.mem.endsWith(u8, public_name, ".each") or
        std.mem.endsWith(u8, public_name, ".interpolate") or
        std.mem.endsWith(u8, public_name, ".zip") or
        std.mem.endsWith(u8, public_name, ".permute") or
        std.mem.endsWith(u8, public_name, ".choose");
    const parity = if (requiresParityTest(public_name))
        &[_]SiteKind{ .top_level_assign, .nested_callback, .block_body }
    else
        &[_]SiteKind{};
    return .{
        .public_name = public_name,
        .internal_name = internal,
        .budget = budget,
        .output = .native_string,
        .contract = .{
            .native_only = true,
            .max_matching_types = max_types,
            .requires_callback = needs_cb,
            .parity_sites = parity,
        },
    };
}

pub fn isRegisteredTransform(public_name: []const u8) bool {
    return descriptor(public_name) != null;
}

/// True for shape algebra transforms (`shape.seal`, `shape.lift`, …).
pub fn isShapeTransform(public_name: []const u8) bool {
    return shapeOpFromTransformId(public_name) != null;
}

/// True when a compatibility transform spelling projects an iteration relation.
pub fn isIterationTransform(public_name: []const u8) bool {
    inline for (@typeInfo(semantic_algebra.IterationRelation).@"enum".field_values) |value| {
        const relation: semantic_algebra.IterationRelation = @fromBackingInt(@intCast(value));
        if (std.mem.eql(u8, public_name, semantic_algebra.iterationTransformId(relation))) return true;
    }
    return false;
}

/// True for call algebra transforms (`call.inline`, `call.specialize`, …).
pub fn isCallTransform(public_name: []const u8) bool {
    return callTransformFromId(public_name) != null;
}

/// True for cross-language ABI transforms (`abi.specialize`, …).
pub fn isAbiTransform(public_name: []const u8) bool {
    return std.mem.eql(u8, public_name, "abi.specialize");
}

fn shapeOpFromTransformId(public_name: []const u8) ?semantic_algebra.ShapeOp {
    return semantic_algebra.shapeOpFromTransformId(public_name);
}

fn callTransformFromId(public_name: []const u8) ?semantic_algebra.CallTransform {
    return semantic_algebra.callTransformFromId(public_name);
}

fn iterationRelationFromTransformId(public_name: []const u8) ?semantic_algebra.IterationRelation {
    inline for (@typeInfo(semantic_algebra.IterationRelation).@"enum".field_values) |value| {
        const relation: semantic_algebra.IterationRelation = @fromBackingInt(@intCast(value));
        if (std.mem.eql(u8, public_name, semantic_algebra.iterationTransformId(relation))) return relation;
    }
    return null;
}

fn iterationRelationDescriptor(public_name: []const u8, relation: semantic_algebra.IterationRelation) Descriptor {
    _ = relation;
    return .{
        .public_name = public_name,
        .internal_name = public_name,
        .budget = .linear,
        .output = .c_fragment,
        .contract = .{
            .native_only = false,
            .max_matching_types = null,
            .requires_callback = false,
            .parity_sites = &[_]SiteKind{},
        },
        .min_knowledge = .observed,
        .cost_hint = blk: {
            var c = semantic_algebra.CostVector.neutral();
            c.set(.compile_time, 0.05);
            break :blk c;
        },
    };
}

fn shapeTransformDescriptor(public_name: []const u8, op: semantic_algebra.ShapeOp) Descriptor {
    return .{
        .public_name = public_name,
        .internal_name = public_name,
        .budget = .constant,
        .output = .c_fragment,
        .contract = .{
            .native_only = true,
            .max_matching_types = null,
            .requires_callback = false,
            .parity_sites = &[_]SiteKind{},
        },
        .min_knowledge = shapeTransformMinKnowledge(op),
        .cost_hint = blk: {
            var c = semantic_algebra.CostVector.neutral();
            c.set(.compile_time, 0.05);
            break :blk c;
        },
    };
}

fn shapeTransformMinKnowledge(op: semantic_algebra.ShapeOp) semantic_algebra.KnowledgeLevel {
    return switch (op) {
        .lower, .specialize => .at_comptime,
        .lift => .observed,
        else => .observed,
    };
}

fn callTransformDescriptor(public_name: []const u8, op: semantic_algebra.CallTransform) Descriptor {
    const budget: BudgetClass = switch (op) {
        .memo => .constant,
        .@"inline", .specialize, .devirtualize => .linear,
        .gpu_lower, .simd_lower => .polynomial,
    };
    const min_k: semantic_algebra.KnowledgeLevel = switch (op) {
        .memo => .at_comptime,
        .@"inline", .specialize, .devirtualize => .stable,
        .gpu_lower, .simd_lower => .native,
    };
    return .{
        .public_name = public_name,
        .internal_name = public_name,
        .budget = budget,
        .output = .c_fragment,
        .contract = .{
            .native_only = true,
            .max_matching_types = null,
            .requires_callback = false,
            .parity_sites = &[_]SiteKind{.emit_call},
        },
        .min_knowledge = min_k,
        .cost_hint = blk: {
            var c = semantic_algebra.CostVector.neutral();
            c.set(.compile_time, switch (op) {
                .memo => 0.02,
                .@"inline" => 0.05,
                .specialize => 0.1,
                .devirtualize => 0.08,
                .gpu_lower, .simd_lower => 0.2,
            });
            c.set(.latency, switch (op) {
                .memo, .@"inline", .specialize, .devirtualize => -0.1,
                .gpu_lower, .simd_lower => -0.3,
            });
            break :blk c;
        },
    };
}

/// Expression-position `@comp.*` must NOT parse as block `.directive` (G-060).
pub fn mustParseAsExpression(public_name: []const u8) bool {
    if (meta_module.resolveBuiltin(public_name) != null) {
        return !meta_module.isMetaAttribute(public_name);
    }
    return false;
}

test "transform_engine: derive.power registered with exponential budget" {
    const d = descriptor("comp.derive.power") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.exponential, d.budget);
    try std.testing.expectEqual(@as(?usize, 24), d.contract.max_matching_types);
    try std.testing.expect(requiresParityTest("comp.derive.power"));
}

test "transform_engine: derive.power must parse as expression in blocks" {
    try std.testing.expect(mustParseAsExpression("comp.derive.power"));
    try std.testing.expect(!meta_module.isMetaAttribute("comp.derive.power"));
}

test "transform_engine: define.derive remains module directive" {
    try std.testing.expect(meta_module.isMetaAttribute("comp.define.derive"));
    try std.testing.expect(!mustParseAsExpression("comp.define.derive"));
}

test "transform_engine: internal hook maps to tier-1 public name" {
    try std.testing.expectEqualStrings("comp.match", publicNameForInternal("__comptimematch").?);
    try std.testing.expectEqualStrings("comp.map", publicNameForInternal("__comptimemap").?);
    try std.testing.expect(isRegisteredTransform("comp.match"));
    try std.testing.expect(requiresParityTest("comp.match"));
}

test "transform_engine: provenance log" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    logProvenance(alloc, "comp.match", .nested_callback, 1, 2);
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
    try std.testing.expectEqualStrings("comp.match", provenanceEntries()[0].public_name);
    // Backward-compatible logProvenance passes null graph coordinates.
    try std.testing.expectEqual(null, provenanceEntries()[0].graph);
}

test "transform_engine: provenance log retains graph entity identity" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    const graph_id: proof_carrying.GraphEntity = .{
        .relation = 7,
        .application = 42,
        .subject = 3,
        .input_value = 9,
        .output_value = 14,
    };
    logProvenanceGraph(alloc, "comp.match", .nested_callback, 1, 2, graph_id);
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
    const entry = provenanceEntries()[0];
    try std.testing.expectEqualStrings("comp.match", entry.public_name);
    const g = entry.graph orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(?u32, 7), g.relation);
    try std.testing.expectEqual(@as(?u32, 42), g.application);
    try std.testing.expectEqual(@as(?u32, 3), g.subject);
    try std.testing.expectEqual(@as(?u32, 9), g.input_value);
    try std.testing.expectEqual(@as(?u32, 14), g.output_value);
    // The snapshot must also carry the graph coordinates.
    snapshotProvenance();
    const snapshot = provenanceSnapshotEntries();
    try std.testing.expectEqual(@as(usize, 1), snapshot.len);
    try std.testing.expectEqual(@as(?u32, 42), snapshot[0].graph.?.application);
}

test "transform_engine: provenance log without graph entities fails lineage gate" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    // logProvenance (the backward-compatible path) does NOT carry graph
    // identity. A proof record built from such an entry must not pass the
    // lineage gate — this is the P2 negative control: removing transform
    // lineage must fail closed rather than degrading to hash-only.
    logProvenance(alloc, "comp.match", .nested_callback, 1, 2);
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
    try std.testing.expect(provenanceEntries()[0].graph == null);
    // The proof record (if the transform is registered) has null graph.
    if (isRegisteredTransform("comp.match")) {
        var record = buildTransformProofRecord(alloc, "comp.match", .nested_callback, 1, 2, null) catch return;
        defer freeProofRecord(&record, alloc);
        try std.testing.expect(!proof_carrying.lineageGate(record));
    }
    // With graph entities present, the gate must pass.
    const graph_id: proof_carrying.GraphEntity = .{
        .relation = 7,
        .application = 42,
        .subject = 3,
        .input_value = 9,
        .output_value = 14,
    };
    var gated_record = buildTransformProofRecord(alloc, "comp.match", .nested_callback, 1, 2, graph_id) catch return;
    defer freeProofRecord(&gated_record, alloc);
    try std.testing.expect(proof_carrying.lineageGate(gated_record));
}

test "transform_engine: comp.shape registered as constant introspection" {
    const d = descriptor("comp.shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqual(OutputKind.native_string, d.output);
    try std.testing.expect(d.contract.native_only);
    try std.testing.expect(!requiresParityTest("comp.shape"));
}

test "transform_engine: comp.type.shape registered as constant introspection" {
    const d = descriptor("comp.type.shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqualStrings("__type_shape", d.internal_name);
}

test "transform_engine: comp.why.boxed registered as constant introspection" {
    const d = descriptor("comp.why.boxed") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqualStrings("__why_boxed", d.internal_name);
}

test "transform_engine: comp.representation registered as constant introspection" {
    const d = descriptor("comp.representation") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqualStrings("__representation", d.internal_name);
}

test "transform_engine: comp.why.shape registered as constant introspection" {
    const d = descriptor("comp.why.shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqualStrings("__why_shape", d.internal_name);
    try std.testing.expectEqual(semantic_algebra.KnowledgeLevel.observed, d.min_knowledge);
}

test "transform_engine: shape.seal registered as shape algebra transform" {
    const d = descriptor("shape.seal") orelse return error.TestExpectedEqual;
    try std.testing.expect(isShapeTransform("shape.seal"));
    try std.testing.expectEqual(BudgetClass.constant, d.budget);
    try std.testing.expectEqual(OutputKind.c_fragment, d.output);
    try std.testing.expectEqual(semantic_algebra.KnowledgeLevel.observed, d.min_knowledge);
}

test "transform_engine: all ShapeOp ids registered" {
    inline for (
        @typeInfo(semantic_algebra.ShapeOp).@"enum".field_names,
        @typeInfo(semantic_algebra.ShapeOp).@"enum".field_values,
    ) |_, value| {
        const op: semantic_algebra.ShapeOp = @fromBackingInt(@intCast(value));
        const id = semantic_algebra.shapeTransformId(op);
        try std.testing.expect(isRegisteredTransform(id));
    }
}

test "transform_engine: call.specialize registered as call algebra transform" {
    const d = descriptor("call.specialize") orelse return error.TestExpectedEqual;
    try std.testing.expect(isCallTransform("call.specialize"));
    try std.testing.expectEqual(BudgetClass.linear, d.budget);
    try std.testing.expectEqual(semantic_algebra.KnowledgeLevel.stable, d.min_knowledge);
    try std.testing.expectEqual(@as(usize, 1), d.contract.parity_sites.len);
    try std.testing.expectEqual(SiteKind.emit_call, d.contract.parity_sites[0]);
}

test "transform_engine: tier-1 combinators registered with 3-site parity contract" {
    for (parity_tier1) |name| {
        const d = descriptor(name) orelse return error.TestExpectedEqual;
        try std.testing.expect(requiresParityTest(name));
        try std.testing.expect(parityContractSatisfied(d));
        try std.testing.expect(mustParseAsExpression(name));
        try std.testing.expectEqualStrings(name, publicNameForInternal(d.internal_name).?);
    }
}

test "transform_engine: dispatchMetaCombinator requires registry gate" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    dispatchMetaCombinator(alloc, "__comptimemap", .block_body, "a b", "a\n");
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
    dispatchMetaCombinator(alloc, "__unknown_hook", .block_body, "x", "y");
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
}

test "transform_engine: requireMetaDispatchBeforeHook strict gate" {
    setMetaDispatchStrict(false);
    try std.testing.expect(requireMetaDispatchBeforeHook("__comptimemap"));
    setMetaDispatchStrict(true);
    try std.testing.expect(requireMetaDispatchBeforeHook("__comptimemap"));
    try std.testing.expect(requireMetaDispatchBeforeHook("__metacatalog"));
    setMetaDispatchStrict(false);
}

test "transform_engine: logInternalTransform uses registry" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    logInternalTransform(alloc, "__comptimemap", .block_body, "a b", "a\n");
    try std.testing.expectEqual(@as(usize, 1), provenanceEntries().len);
    try std.testing.expectEqualStrings("comp.map", provenanceEntries()[0].public_name);
    try std.testing.expectEqual(@as(usize, 1), proofLogEntries().len);
    try std.testing.expectEqualStrings("comp.map", proofLogEntries()[0].record.transform_id);
    try std.testing.expect(proofLogEntries()[0].record.result == .proven_and_applied or
        proofLogEntries()[0].record.result == .guarded_and_applied or
        proofLogEntries()[0].record.result == .validated_and_applied);
}

test "transform_engine: provenanceSitesObserved tracks tier-1 sites" {
    const alloc = std.testing.allocator;
    defer deinitProvenance(alloc);
    setProvenanceEnabled(true);
    logInternalTransform(alloc, "__comptimemap", .top_level_assign, "a", "a\n");
    logInternalTransform(alloc, "__comptimemap", .nested_callback, "a", "a\n");
    logInternalTransform(alloc, "__comptimemap", .block_body, "a", "a\n");
    try std.testing.expect(tier1ParityObserved("comp.map"));
    const observed = provenanceSitesObserved("comp.map");
    try std.testing.expect(observed.contains(.top_level_assign));
    try std.testing.expect(observed.contains(.nested_callback));
    try std.testing.expect(observed.contains(.block_body));
}

test "transform_engine: compatibility pipeline.map spelling is registered" {
    try std.testing.expect(isRegisteredTransform("pipeline.map"));
    const d = descriptor("pipeline.map") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(BudgetClass.linear, d.budget);
}

test "transform_engine: all iteration relation ids are registered" {
    inline for (@typeInfo(semantic_algebra.IterationRelation).@"enum".field_values) |value| {
        const relation: semantic_algebra.IterationRelation = @fromBackingInt(@intCast(value));
        const id = semantic_algebra.iterationTransformId(relation);
        try std.testing.expect(isRegisteredTransform(id));
        try std.testing.expect(isIterationTransform(id));
    }
}

test "transform_engine: abi.specialize registered as Pass 5 ABI transform" {
    const d = descriptor("abi.specialize") orelse return error.TestExpectedEqual;
    try std.testing.expect(isAbiTransform("abi.specialize"));
    try std.testing.expectEqual(BudgetClass.linear, d.budget);
    try std.testing.expectEqual(semantic_algebra.KnowledgeLevel.stable, d.min_knowledge);
    try std.testing.expectEqual(@as(usize, 1), d.contract.parity_sites.len);
    try std.testing.expectEqual(SiteKind.emit_call, d.contract.parity_sites[0]);
}

test "transform_engine: all CallTransform ids registered" {
    inline for (
        @typeInfo(semantic_algebra.CallTransform).@"enum".field_names,
        @typeInfo(semantic_algebra.CallTransform).@"enum".field_values,
    ) |_, value| {
        const op: semantic_algebra.CallTransform = @fromBackingInt(@intCast(value));
        const id = semantic_algebra.callTransformId(op);
        try std.testing.expect(isRegisteredTransform(id));
        try std.testing.expect(isCallTransform(id));
    }
}

test "transform_engine: hardness distinguishes preference from requirement" {
    try std.testing.expect(!Hardness.preference.isHard());
    try std.testing.expect(!Hardness.expectation.isHard());
    try std.testing.expect(Hardness.requirement.isHard());
    try std.testing.expect(Hardness.assertion.isHard());
    try std.testing.expect(Hardness.budget.isHard());
    try std.testing.expect(!Hardness.query.isHard());
}

test "transform_engine: introspection descriptors have query hardness" {
    const d = descriptor("comp.shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.query, d.hardness);
    const d2 = descriptor("comp.why.shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.query, d2.hardness);
}

test "transform_engine: default hardness is preference" {
    const d = descriptor("comp.map") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.preference, d.hardness);
}

test "transform_engine: evidence reliability ordering" {
    try std.testing.expect(Evidence.semantic_proof.reliability() < Evidence.heuristic.reliability());
    try std.testing.expect(Evidence.guarded.reliability() < Evidence.profile.reliability());
    try std.testing.expect(Evidence.semantic_proof.isDeterministic());
    try std.testing.expect(Evidence.static_estimate.isDeterministic());
    try std.testing.expect(!Evidence.profile.isDeterministic());
    try std.testing.expect(!Evidence.heuristic.isDeterministic());
}
