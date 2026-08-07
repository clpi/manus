//! Self-hosting foundation gate — M0 schema + structural proofs for §11 F-G01..F-G10.
const std = @import("std");
const foundation_catalog = @import("foundation_catalog.zig");
const ir_layer_registry = @import("ir_layer_registry.zig");
const dependency_manifest = @import("dependency_manifest.zig");
const removal_ledger = @import("removal_ledger.zig");

pub const GateError = error{ GateFailed };

pub fn validateFoundationCatalog() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.SCHEMA_VERSION, "foundation-catalog-v0")) return error.GateFailed;
    if (foundation_catalog.bootstrapStageCount() != 4) return error.GateFailed;
    if (foundation_catalog.irLayerCount() != 9) return error.GateFailed;
    if (foundation_catalog.foundationGateCount() != 10) return error.GateFailed;
    if (foundation_catalog.foreign_classes.len != 4) return error.GateFailed;
    if (foundation_catalog.semantic_node_kinds.len != 28) return error.GateFailed;
    if (foundation_catalog.semantic_edge_kinds.len != 24) return error.GateFailed;
    if (foundation_catalog.ir_invariants.len != 8) return error.GateFailed;
    if (foundation_catalog.execution_phases.len != 10) return error.GateFailed;
    if (foundation_catalog.immediate_workstreams.len != 10) return error.GateFailed;
}

pub fn proveCanonicalDocLinked() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.CANONICAL_SPEC_PATH, "docs/plans/duo_self_hosting_foundation.md")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.PLAN_PATH, "docs/plans/self_hosting_foundation.md")) return error.GateFailed;
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, foundation_catalog.CANONICAL_SPEC_PATH, .{}) catch return error.GateFailed;
    cwd.access(io, foundation_catalog.PLAN_PATH, .{}) catch return error.GateFailed;
}

pub fn proveBootstrapLadder() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.bootstrap_stages[0].id, "S0")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.bootstrap_stages[0].status, "current")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.bootstrap_stages[3].id, "S3")) return error.GateFailed;
    if (std.mem.indexOf(u8, foundation_catalog.bootstrap_stages[1].owner, "pass16") == null) return error.GateFailed;
}

pub fn proveIrLayerRegistry() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.ir_layers[0].id, "IR-01")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.ir_layers[8].id, "IR-09")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.ir_layers[8].title, "Artifact IR")) return error.GateFailed;
    for (foundation_catalog.ir_layers) |layer| {
        if (layer.id.len == 0 or layer.title.len == 0) return error.GateFailed;
        if (layer.verifier_step == null) return error.GateFailed;
    }
    if (!ir_layer_registry.runAllVerifierStubs()) return error.GateFailed;
    if (ir_layer_registry.loweringEdgeCount() != 8) return error.GateFailed;
    if (ir_layer_registry.verifierStubCount() != 9) return error.GateFailed;
}

pub fn proveFoundationGatesOrdered() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.foundation_gates[0].id, "F-G01")) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.foundation_gates[9].id, "F-G10")) return error.GateFailed;
    if (std.mem.indexOf(u8, foundation_catalog.foundation_gates[2].title, "boxing") == null) return error.GateFailed;
    if (foundation_catalog.foundation_gates[2].build_step) |step| {
        if (!std.mem.eql(u8, step, "bench-proof-gate")) return error.GateFailed;
    } else return error.GateFailed;
}

pub fn proveIrInvariants() GateError!void {
    if (!std.mem.eql(u8, foundation_catalog.ir_invariants[3].id, "INV-04")) return error.GateFailed;
    if (std.mem.indexOf(u8, foundation_catalog.ir_invariants[3].law, "Boxing") == null) return error.GateFailed;
    if (!std.mem.eql(u8, foundation_catalog.ir_invariants[7].id, "INV-08")) return error.GateFailed;
}

pub fn proveForeignLedgerAnchors() GateError!void {
    if (!std.mem.eql(u8, dependency_manifest.SCHEMA_VERSION, "dependency-manifest-v0")) return error.GateFailed;
    if (dependency_manifest.records.len < 3) return error.GateFailed;
    if (!std.mem.eql(u8, removal_ledger.SCHEMA_VERSION, "removal-ledger-v0")) return error.GateFailed;
    if (removal_ledger.entries.len < 4) return error.GateFailed;

    var saw_bootstrap = false;
    for (dependency_manifest.records) |rec| {
        if (rec.class == .bootstrap) saw_bootstrap = true;
        if (rec.removal_gate.len == 0) return error.GateFailed;
    }
    if (!saw_bootstrap) return error.GateFailed;

    for (removal_ledger.entries) |entry| {
        if (entry.removal_gate.len == 0) return error.GateFailed;
    }
}

pub fn proveSemanticGraphAnchor() GateError!void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, "src/semantic_graph.zig", .{}) catch return error.GateFailed;
    cwd.access(io, "docs/semantic_universe.md", .{}) catch return error.GateFailed;
}

pub fn proveLedgerAnchorPaths() GateError!void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    for (foundation_catalog.ledger_anchors) |anchor| {
        cwd.access(io, anchor.path, .{}) catch return error.GateFailed;
    }
}

pub fn proveExecutionPhasesCoverSelfHosting() GateError!void {
    if (foundation_catalog.execution_phases[0].phase != 1) return error.GateFailed;
    if (foundation_catalog.execution_phases[9].phase != 10) return error.GateFailed;
    if (std.mem.indexOf(u8, foundation_catalog.execution_phases[8].title, "Native backend") == null) return error.GateFailed;
}

pub fn proveFoundationJsonExport() GateError!void {
    var buf: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer buf.deinit();
    foundation_catalog.writeFoundationJson(&buf.writer, std.heap.page_allocator) catch return error.GateFailed;
    const out = buf.written();
    if (std.mem.indexOf(u8, out, "\"foundation\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "foundation-catalog-v0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, out, "F-G01..F-G10") == null) return error.GateFailed;
}

pub fn validateFoundationGate(_: std.mem.Allocator) GateError!void {
    try validateFoundationCatalog();
    try proveCanonicalDocLinked();
    try proveBootstrapLadder();
    try proveIrLayerRegistry();
    try proveFoundationGatesOrdered();
    try proveIrInvariants();
    try proveForeignLedgerAnchors();
    try proveSemanticGraphAnchor();
    try proveLedgerAnchorPaths();
    try proveExecutionPhasesCoverSelfHosting();
    try proveFoundationJsonExport();
}

test "foundation_gate: M0 self-hosting foundation proofs" {
    try validateFoundationGate(std.testing.allocator);
}
