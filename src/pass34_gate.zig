//! Pass 34 HPLS Frontier gate — Phase 0 catalog + Phase 1 L6/L1 bounded first steps.
const std = @import("std");
const pass34_catalog = @import("pass34_catalog.zig");
const pass34_representation_manifest = @import("pass34_representation_manifest.zig");
const pass27_benchmark_evidence = @import("pass27_benchmark_evidence.zig");
const backend_identity = @import("backend_identity.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");

pub const GateError = error{GateFailed};

fn ordinalValid(v: u8) bool {
    return v >= 1 and v <= 5;
}

pub fn validateCatalogSchema() GateError!void {
    if (!std.mem.eql(u8, pass34_catalog.SCHEMA_VERSION, "pass34-hpls-catalog-v1")) return error.GateFailed;
    if (pass34_catalog.barrierCount() != 53) return error.GateFailed;
    if (pass34_catalog.barriersInTier(.convergence) != 5) return error.GateFailed;
    if (pass34_catalog.barriersInTier(.elephant) != 10) return error.GateFailed;
    if (pass34_catalog.barriersInTier(.lever) != 15) return error.GateFailed;
    if (pass34_catalog.barriersInTier(.unicorn) != 15) return error.GateFailed;
    if (pass34_catalog.barriersInTier(.trap) != 8) return error.GateFailed;
    if (pass34_catalog.ranked_item_ids.len != 28) return error.GateFailed;
    if (pass34_catalog.canonical_home_mappings.len != 20) return error.GateFailed;
    if (pass34_catalog.agent_idiom_projections.len != 6) return error.GateFailed;
    if (pass34_catalog.dependency_edges.len == 0) return error.GateFailed;
    if (pass34_catalog.execution_phases.len != 7) return error.GateFailed;
}

pub fn proveRankedOrderMatches() GateError!void {
    if (!std.mem.eql(u8, pass34_catalog.ranked_item_ids[0].id, "L6")) return error.GateFailed;
    if (!std.mem.eql(u8, pass34_catalog.ranked_item_ids[1].id, "L1")) return error.GateFailed;
    if (pass34_catalog.ranked_item_ids[0].rank != 1) return error.GateFailed;
    if (pass34_catalog.ranked_item_ids[1].rank != 2) return error.GateFailed;

    var expected_rank: u8 = 1;
    for (pass34_catalog.ranked_item_ids) |entry| {
        if (entry.rank != expected_rank) return error.GateFailed;
        expected_rank += 1;
    }
}

pub fn proveEveryRecordHasRankInputs() GateError!void {
    inline for (pass34_catalog.allBarrierTiers()) |tier| {
        for (tier) |rec| {
            const ri = rec.rank_inputs;
            if (!ordinalValid(ri.impact) or !ordinalValid(ri.frequency) or !ordinalValid(ri.leverage) or
                !ordinalValid(ri.ward) or !ordinalValid(ri.selfhost) or !ordinalValid(ri.risk) or
                !ordinalValid(ri.redesign) or !ordinalValid(ri.overlap))
            {
                return error.GateFailed;
            }
            if (rec.impact.evidence != .estimated and rec.impact.evidence != .measured) return error.GateFailed;
        }
    }
}

/// Phase 0: all barriers discovered. Phase 1: only L6/L1 may advance to specified.
pub fn proveCatalogLifecycleStatus() GateError!void {
    inline for (pass34_catalog.allBarrierTiers()) |tier| {
        for (tier) |rec| {
            const expected: pass34_catalog.BarrierStatus = if (std.mem.eql(u8, rec.id, "L6") or std.mem.eql(u8, rec.id, "L1"))
                .specified
            else
                .discovered;
            if (rec.status != expected) return error.GateFailed;
        }
    }
}

pub fn provePhase1L6Specified() GateError!void {
    const l6 = pass34_catalog.findBarrier("L6") orelse return error.GateFailed;
    if (l6.status != .specified) return error.GateFailed;
    if (!std.mem.eql(u8, l6.file, "pass34_representation_manifest.zig")) return error.GateFailed;
    if (!std.mem.eql(u8, l6.symbol, "RepresentationManifest")) return error.GateFailed;
    if (!std.mem.eql(u8, l6.bounded_fix, "emit manifest from @comp.why")) return error.GateFailed;
    if (!std.mem.eql(u8, pass34_representation_manifest.SCHEMA_VERSION, pass27_benchmark_evidence.MANIFEST_SCHEMA_VERSION)) return error.GateFailed;
}

pub fn provePhase1L1Specified() GateError!void {
    const l1 = pass34_catalog.findBarrier("L1") orelse return error.GateFailed;
    if (l1.status != .specified) return error.GateFailed;
    if (!std.mem.eql(u8, l1.file, "sema.zig")) return error.GateFailed;
    if (!std.mem.eql(u8, l1.symbol, "module_sealed")) return error.GateFailed;
    if (!std.mem.eql(u8, l1.bounded_fix, "module_sealed(m) lattice fact")) return error.GateFailed;
}

pub fn proveL6ManifestSchemaValidates() GateError!void {
    const counts = pass34_representation_manifest.EmissionCounts.fromGeneratedC(
        \\void f(void) { int64_t a = 1; }
    );
    const manifest = backend_identity.Manifest{
        .backend = .direct,
        .representation = .native,
        .runtime = .freestanding,
        .target = "native-exe",
        .intermediate = "mach-o-arm64",
        .boxing_mode = "none",
    };
    const contamination = pass34_representation_manifest.classifyContamination(counts, 0);

    var buf: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer buf.deinit();
    pass34_representation_manifest.writeManifestJson(&buf.writer, manifest, counts, contamination) catch return error.GateFailed;
    const out = buf.written();
    if (std.mem.indexOf(u8, out, "\"schema\":\"pass34-l6-manifest-v0\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"dynamic_dispatches\":0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"contamination\":\"clean\"") == null) return error.GateFailed;
}

/// CI zero-dynamic-ops check for pass27_proof_matrix_direct shape (direct profile).
pub fn proveL6DirectProfileZeroDynamicOps() GateError!void {
    const direct_src =
        \\void read_u8_at(uint8_t *p) { *p = 1; }
        \\int64_t decode_leb128_bounded(const uint8_t *b, size_t n) { (void)n; return b[0]; }
        \\size_t length2(void) { return 2; }
    ;
    const counts = pass34_representation_manifest.EmissionCounts.fromGeneratedC(direct_src);
    if (!counts.isZeroDynamic()) return error.GateFailed;

    var report = native_barrier_checks.checkGeneratedC(std.heap.page_allocator, direct_src, &.{ .no_boxing, .no_dynamic_dispatch }) catch return error.GateFailed;
    defer {
        for (report.violations) |v| std.heap.page_allocator.free(v.detail);
        std.heap.page_allocator.free(report.violations);
    }
    if (!report.passed()) return error.GateFailed;

    if (pass34_catalog.findBarrier("L6")) |l6| {
        if (l6.status != .specified) return error.GateFailed;
    } else return error.GateFailed;
}

/// Pass 34 L2 — fallback `.field` accesses are emitted with interned field IDs
/// (duo_fallback_get_* markers) and counted in the manifest emission section.
pub fn proveL2FallbackFieldManifest() GateError!void {
    const fallback_src =
        \\double read_num(lua_Value t) { return duo_fallback_get_num(0, t, "x", 1u, 1); }
        \\double read_bool(lua_Value t) { return duo_fallback_get_bool(1, t, "y", 2u, 1); }
        \\double read_cstr(lua_Value t) { return duo_fallback_get_cstr(0, t, "x", 1u, 1); }
        \\double read_extra(lua_Value t) { return duo_fallback_get_num(2, t, "z", 3u, 1); }
    ;
    const fallback = pass34_representation_manifest.scanFallbackFieldIds(fallback_src);
    if (fallback.accesses != 4) return error.GateFailed;
    if (fallback.distinct_ids != 3) return error.GateFailed;

    const counts = pass34_representation_manifest.EmissionCounts.fromGeneratedC(fallback_src);
    if (counts.fallback_field_accesses != 4) return error.GateFailed;
    if (counts.interned_field_ids != 3) return error.GateFailed;

    const manifest = backend_identity.Manifest{
        .backend = .c,
        .representation = .generic,
        .runtime = .full,
        .target = "native-exe",
        .intermediate = "generated-c",
        .boxing_mode = "boxed",
    };
    const contamination = pass34_representation_manifest.classifyContamination(counts, 0);
    var buf: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer buf.deinit();
    pass34_representation_manifest.writeManifestJson(&buf.writer, manifest, counts, contamination) catch return error.GateFailed;
    const out = buf.written();
    if (std.mem.indexOf(u8, out, "\"fallback_field_accesses\":4") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"interned_field_ids\":3") == null) return error.GateFailed;
}

fn bridgeDeclaredForPrereq(rec: pass34_catalog.BarrierRecord, prereq_id: []const u8) bool {
    for (rec.prerequisite_bridges) |pb| {
        if (std.mem.eql(u8, pb.id, prereq_id) and pb.bridge.len > 0) return true;
    }
    return false;
}

pub fn proveAllPrerequisitesBridged() GateError!void {
    inline for (pass34_catalog.allBarrierTiers()) |tier| {
        for (tier) |rec| {
            for (rec.prerequisites) |pre| {
                if (!bridgeDeclaredForPrereq(rec, pre)) return error.GateFailed;
            }
        }
    }
}

pub fn proveWitnessInvariant() GateError!void {
    inline for (pass34_catalog.allBarrierTiers()) |tier| {
        for (tier) |rec| {
            const has_bounded_fix = !std.mem.eql(u8, rec.bounded_fix, "NONE");
            const has_witness = !std.mem.eql(u8, rec.witness, "NONE") and rec.witness.len > 0;
            if (has_bounded_fix and !has_witness) return error.GateFailed;
            if (!has_bounded_fix and !std.mem.eql(u8, rec.witness, "NONE")) return error.GateFailed;
        }
    }
}

pub fn proveDependencyEdgesValid() GateError!void {
    for (pass34_catalog.dependency_edges) |edge| {
        if (edge.bridge.len == 0) return error.GateFailed;
        if (edge.from_id.len == 0 or edge.to_ids.len == 0) return error.GateFailed;
        if (!pass34_catalog.isValidBarrierId(edge.from_id)) return error.GateFailed;
        for (edge.to_ids) |to_id| {
            if (!pass34_catalog.isValidBarrierId(to_id)) return error.GateFailed;
        }
    }
}

pub fn proveL6AndL1RankedFirst() GateError!void {
    if (pass34_catalog.findBarrier("L6")) |l6| {
        if (l6.rank_inputs.leverage < 4) return error.GateFailed;
    } else return error.GateFailed;

    if (pass34_catalog.findBarrier("L1")) |l1| {
        if (l1.rank_inputs.impact < 4) return error.GateFailed;
    } else return error.GateFailed;
}

pub fn proveL1ModuleSealedWitness() GateError!void {
    const l1 = pass34_catalog.findBarrier("L1") orelse return error.GateFailed;
    if (!std.mem.eql(u8, l1.bounded_fix, "module_sealed(m) lattice fact")) return error.GateFailed;
    if (std.mem.indexOf(u8, l1.witness, "module_sealed") == null) return error.GateFailed;
}

/// §13 — every agent idiom enforcement mechanism must route to barrier records
/// that already exist. A mechanism with no home is a new subsystem, which the
/// charter classifies as entropy.
pub fn proveAgentIdiomProjectionsRouteToRecords() GateError!void {
    for (pass34_catalog.agent_idiom_projections) |proj| {
        if (proj.mechanism.len == 0 or proj.enforcement.len == 0) return error.GateFailed;
        if (proj.homes.len == 0) return error.GateFailed;
        for (proj.homes) |home| {
            if (!pass34_catalog.isValidBarrierId(home)) return error.GateFailed;
        }
    }

    // The manifest (L6) and the goal contract (U11) are the two enforcement
    // surfaces §13 rests on; neither may drop out of the projection set.
    var saw_l6 = false;
    var saw_u11 = false;
    for (pass34_catalog.agent_idiom_projections) |proj| {
        for (proj.homes) |home| {
            if (std.mem.eql(u8, home, "L6")) saw_l6 = true;
            if (std.mem.eql(u8, home, "U11")) saw_u11 = true;
        }
    }
    if (!saw_l6 or !saw_u11) return error.GateFailed;
}

/// Convergence rule: a superseding record closes only when the redundant
/// implementation is deleted. While T8 is open the text linter must still be
/// present (it is the thing being superseded); once T8 reaches ADOPTED the
/// linter must be gone, or the convergence never actually closed.
pub fn proveT8ClosesOnlyOnDeletion() GateError!void {
    const t8 = pass34_catalog.findBarrier("T8") orelse return error.GateFailed;
    if (!std.mem.eql(u8, t8.file, pass34_catalog.TEXT_IDIOM_GATE_PATH)) return error.GateFailed;
    if (std.mem.eql(u8, t8.bounded_fix, "NONE")) return error.GateFailed;
    if (std.mem.eql(u8, t8.witness, "NONE")) return error.GateFailed;

    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    const linter_present = if (cwd.access(io, pass34_catalog.TEXT_IDIOM_GATE_PATH, .{})) |_| true else |_| false;

    switch (t8.status) {
        .adopted => if (linter_present) return error.GateFailed,
        .wont_fix, .superseded => {},
        else => if (!linter_present) return error.GateFailed,
    }
}

pub fn proveCanonicalDocsLinked() GateError!void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, pass34_catalog.PLAN_PATH, .{}) catch return error.GateFailed;
    cwd.access(io, pass34_catalog.INDEX_PATH, .{}) catch return error.GateFailed;
}

pub fn validatePass34Gate(_: std.mem.Allocator) GateError!void {
    try validateCatalogSchema();
    try proveRankedOrderMatches();
    try proveEveryRecordHasRankInputs();
    try proveCatalogLifecycleStatus();
    try provePhase1L6Specified();
    try provePhase1L1Specified();
    try proveL6ManifestSchemaValidates();
    try proveL6DirectProfileZeroDynamicOps();
    try proveL2FallbackFieldManifest();
    try proveAllPrerequisitesBridged();
    try proveWitnessInvariant();
    try proveDependencyEdgesValid();
    try proveL6AndL1RankedFirst();
    try proveL1ModuleSealedWitness();
    try proveAgentIdiomProjectionsRouteToRecords();
    try proveT8ClosesOnlyOnDeletion();
    try proveCanonicalDocsLinked();
}

test "pass34 gate: Phase 0+1 HPLS catalog proofs" {
    try validatePass34Gate(std.testing.allocator);
}
