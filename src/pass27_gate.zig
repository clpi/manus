//! Pass 27 native gate — proof bundle + benchmark evidence M0 proofs.
const std = @import("std");
const pass27_catalog = @import("pass27_catalog.zig");
const pass27_proof_bundle = @import("pass27_proof_bundle.zig");
const pass27_benchmark_evidence = @import("pass27_benchmark_evidence.zig");
const pass27_meta_proof = @import("pass27_meta_proof.zig");
const backend_identity = @import("backend_identity.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");

pub const GateError = error{GateFailed};

pub fn validatePass27Catalog() GateError!void {
    if (!std.mem.eql(u8, pass27_catalog.SCHEMA_VERSION, "pass27-catalog-v0")) return error.GateFailed;
    if (pass27_catalog.perf_workstreams.len != 12) return error.GateFailed;
    if (pass27_catalog.meta_workstreams.len != 15) return error.GateFailed;
    if (pass27_catalog.workstreamCount() != 27) return error.GateFailed;
    if (pass27_catalog.completion_gates.len != 10) return error.GateFailed;
    if (pass27_catalog.flagship_proofs.len != 6) return error.GateFailed;
    if (pass27_catalog.eight_priorities.len != 9) return error.GateFailed;
}

pub fn proveProofBundlePipeline() GateError!void {
    if (!std.mem.eql(u8, pass27_proof_bundle.SCHEMA_VERSION, "pass27-proof-bundle-v0")) return error.GateFailed;
    if (pass27_proof_bundle.stageCount() != 8) return error.GateFailed;
    if (pass27_proof_bundle.default_stages.len != 8) return error.GateFailed;
    if (!std.mem.eql(u8, pass27_proof_bundle.FlagshipProof.ward_decoder.id(), "P27-PROOF-01")) return error.GateFailed;
    const bundle = pass27_proof_bundle.ProofBundle{
        .proof_id = "test",
        .source_path = "test.duo",
        .backend = .direct,
        .representation = .native,
        .runtime = .freestanding,
        .stages = pass27_proof_bundle.default_stages,
    };
    if (pass27_proof_bundle.bundleClaimsAllowed(bundle)) return error.GateFailed;
}

pub fn proveBenchmarkEvidenceSchema() GateError!void {
    if (!std.mem.eql(u8, pass27_benchmark_evidence.SCHEMA_VERSION, "pass27-benchmark-evidence-v0")) return error.GateFailed;
    if (!pass27_benchmark_evidence.validateMatrixSchema()) return error.GateFailed;
    if (pass27_benchmark_evidence.matrixCellCount() != 30) return error.GateFailed;
    if (pass27_benchmark_evidence.canonical_ten_programs.len != 10) return error.GateFailed;
    if (pass27_benchmark_evidence.required_bench_backends.len != 3) return error.GateFailed;

    const boxed_src =
        \\void f(void) { lua_Value v; lua_invoke(x,0,0); lua_to_i64(v); lua_table_new(); malloc(16); }
    ;
    const boxed = pass27_benchmark_evidence.EvidenceCounters.fromGeneratedC(boxed_src, boxed_src.len);
    if (!boxed.isBoxedBaseline()) return error.GateFailed;

    const direct = pass27_benchmark_evidence.EvidenceCounters.fromDirectObject(&[_]u8{ 0xCF, 0xFA, 0xED, 0xFE });
    if (!direct.isZeroBoxNativePath()) return error.GateFailed;

    const p = backend_identity.profileForBenchBackend(.c_specialized);
    if (p.backend != .c or p.representation != .specialized) return error.GateFailed;
}

pub fn proveBackendIdentityAxes() GateError!void {
    if (!std.mem.eql(u8, backend_identity.SCHEMA_VERSION, "backend-identity-v0")) return error.GateFailed;
    const bb = backend_identity.BenchBackend.parse("c-specialized") orelse return error.GateFailed;
    if (bb != .c_specialized) return error.GateFailed;
    const prof = backend_identity.profileForBenchBackend(bb);
    if (prof.representation != .specialized) return error.GateFailed;
}

pub fn proveNativeBarrierBridge() GateError!void {
    if (!std.mem.eql(u8, native_barrier_checks.SCHEMA_VERSION, "native-barrier-checks-v0")) return error.GateFailed;
    const src = "lua_Value x; lua_invoke(f,0,0); malloc(8);";
    const counts = native_barrier_checks.scanGeneratedC(src);
    if (counts.lua_value == 0 or counts.lua_invoke == 0 or counts.malloc == 0) return error.GateFailed;
}

pub fn proveMetaProofBacklog() GateError!void {
    if (!std.mem.eql(u8, pass27_meta_proof.SCHEMA_VERSION, "pass27-meta-proof-v0")) return error.GateFailed;
    if (pass27_meta_proof.macro_path_audit.len < 4) return error.GateFailed;
    if (pass27_meta_proof.metaObjectKindCount() < 17) return error.GateFailed;
    if (pass27_meta_proof.meta_proof_backlog.len >= 7) {} else return error.GateFailed;
    var saw_staging: bool = false;
    for (pass27_meta_proof.macro_path_audit) |entry| {
        if (entry.class == .canonical_semantic_staging and std.mem.eql(u8, entry.path, "staged semantic function (@)")) {
            saw_staging = true;
        }
    }
    if (!saw_staging) return error.GateFailed;
}

pub fn proveEightPrioritiesOrdered() GateError!void {
    if (!std.mem.eql(u8, pass27_catalog.eight_priorities[0].gate_id, "P27-G01")) return error.GateFailed;
    if (!std.mem.eql(u8, pass27_catalog.eight_priorities[0].name, "Make evidence honest")) return error.GateFailed;
    if (pass27_catalog.eight_priorities[8].rank != 8) return error.GateFailed;
    if (!std.mem.eql(u8, pass27_catalog.eight_priorities[4].gate_id, "P27-G10")) return error.GateFailed;
}

pub fn proveNorthStarProofLinked() GateError!void {
    if (!std.mem.eql(u8, pass27_catalog.flagship_proofs[0].id, "P27-PROOF-01")) return error.GateFailed;
    if (std.mem.indexOf(u8, pass27_catalog.flagship_proofs[0].title, "Ward decoder") == null) return error.GateFailed;
    const ws02 = pass27_catalog.perf_workstreams[1];
    if (!std.mem.eql(u8, ws02.id, "P27-WS02")) return error.GateFailed;
}

pub fn proveCompileProofArtifactWriter() GateError!void {
    var buf: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer buf.deinit();
    const artifact = pass27_benchmark_evidence.CompileProofArtifact{
        .source_path = "examples/benchmark.duo",
        .generated_path = "/tmp/duo_benchmark.c",
        .bench_backend = .c_specialized,
        .manifest = backend_identity.inferFromCompile(.c, "native", false, true),
        .counters = pass27_benchmark_evidence.EvidenceCounters.fromGeneratedC("lua_Value v; lua_to_num(v);", 24),
    };
    pass27_benchmark_evidence.writeCompileProofJson(artifact, &.{}, &buf.writer) catch return error.GateFailed;
    const out = buf.written();
    if (std.mem.indexOf(u8, out, "specialized-provisional-boxed") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"emission\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"manifest_schema\":\"pass34-l6-manifest-v0\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"transform_provenance\":[]") == null) return error.GateFailed;
}

/// L6 bounded first step (pass34 PH1) — one CI check: a test manifest reports
/// zero dynamic ops, and the manifest carries @comp.why transform provenance.
pub fn proveL6TestManifestZeroDynamicOps() GateError!void {
    const scalar_src =
        \\void f(void) { int64_t a = 1; double b = 2.0; if (a > 0) b += a; }
    ;
    const counters = pass27_benchmark_evidence.EvidenceCounters.fromGeneratedC(scalar_src, scalar_src.len);
    if (!counters.isZeroBoxNativePath()) return error.GateFailed;

    const provenance = [_]pass27_benchmark_evidence.ManifestProvenance{
        .{ .transform = "comp.why", .site = "emit_call", .inputs_hash = 1, .output_hash = 2 },
        .{ .transform = "comp.why.shape", .site = "emit_call", .inputs_hash = 3, .output_hash = 4 },
    };

    var buf: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer buf.deinit();
    const artifact = pass27_benchmark_evidence.CompileProofArtifact{
        .source_path = "examples/l6_manifest_proof.duo",
        .generated_path = "/tmp/duo_l6_manifest.c",
        .bench_backend = null,
        .manifest = backend_identity.inferFromCompile(.c, "native", true, true),
        .counters = counters,
    };
    pass27_benchmark_evidence.writeCompileProofJson(artifact, &provenance, &buf.writer) catch return error.GateFailed;
    const out = buf.written();
    if (std.mem.indexOf(u8, out, "\"boxes\":0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"unboxes\":0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"generic_calls\":0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "\"generic_table_ops\":0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "comp.why") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "comp.why.shape") == null) return error.GateFailed;
}

pub fn proveDirectNativeEvidenceClass() GateError!void {
    const obj = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE, 0x01, 0x00, 0x00, 0x00 };
    const counters = pass27_benchmark_evidence.EvidenceCounters.fromDirectObject(&obj);
    const manifest = backend_identity.Manifest{
        .backend = .direct,
        .representation = .native,
        .runtime = .freestanding,
        .target = "native-exe",
        .intermediate = "mach-o-arm64",
        .boxing_mode = "none",
    };
    if (!std.mem.eql(u8, pass27_benchmark_evidence.classifyEvidence(counters, manifest), "direct-native-subset")) return error.GateFailed;
    if (!counters.isZeroBoxNativePath()) return error.GateFailed;
}

pub fn validatePass27Gate(_: std.mem.Allocator) GateError!void {
    try validatePass27Catalog();
    try proveProofBundlePipeline();
    try proveBenchmarkEvidenceSchema();
    try proveBackendIdentityAxes();
    try proveNativeBarrierBridge();
    try proveMetaProofBacklog();
    try proveEightPrioritiesOrdered();
    try proveNorthStarProofLinked();
    try proveDirectNativeEvidenceClass();
    try proveCompileProofArtifactWriter();
    try proveL6TestManifestZeroDynamicOps();
}

test "pass27_gate: M0 proof bundle + evidence proofs" {
    try validatePass27Gate(std.testing.allocator);
}
