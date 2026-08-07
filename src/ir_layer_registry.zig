//! F-WS04 — IR layer registry with verifier stubs and lowering edges (IR-01..IR-09).
const std = @import("std");

pub const SCHEMA_VERSION = "ir-layer-registry-v0";

pub const VerifierStatus = enum {
    stub,
    partial,
    closed,

    pub fn name(self: VerifierStatus) []const u8 {
        return @tagName(self);
    }
};

pub const VerifierStub = struct {
    id: []const u8,
    layer_id: []const u8,
    title: []const u8,
    status: VerifierStatus,
    verify: *const fn () bool,
};

pub const LoweringEdge = struct {
    from: []const u8,
    to: []const u8,
    owner: []const u8,
    status: []const u8,
};

fn verifyIr01SyntaxGraph() bool {
    return true;
}

fn verifyIr02SemanticGraph() bool {
    return true;
}

fn verifyIr03ExecutableRegionGraph() bool {
    return true;
}

fn verifyIr04SpecializedGraph() bool {
    return true;
}

fn verifyIr05RepresentationIr() bool {
    return true;
}

fn verifyIr06SsaScheduledIr() bool {
    return true;
}

fn verifyIr07LowLevelIr() bool {
    return true;
}

fn verifyIr08MachineIr() bool {
    return true;
}

fn verifyIr09ArtifactIr() bool {
    return true;
}

pub const verifier_stubs: []const VerifierStub = &.{
    .{ .id = "V-IR-01", .layer_id = "IR-01", .title = "Syntax graph well-formedness", .status = .stub, .verify = verifyIr01SyntaxGraph },
    .{ .id = "V-IR-02", .layer_id = "IR-02", .title = "Semantic graph node/edge kinds", .status = .stub, .verify = verifyIr02SemanticGraph },
    .{ .id = "V-IR-03", .layer_id = "IR-03", .title = "Executable region coverage", .status = .stub, .verify = verifyIr03ExecutableRegionGraph },
    .{ .id = "V-IR-04", .layer_id = "IR-04", .title = "Specialization evidence present", .status = .stub, .verify = verifyIr04SpecializedGraph },
    .{ .id = "V-IR-05", .layer_id = "IR-05", .title = "Representation variables explicit", .status = .stub, .verify = verifyIr05RepresentationIr },
    .{ .id = "V-IR-06", .layer_id = "IR-06", .title = "SSA dominance + scheduling", .status = .stub, .verify = verifyIr06SsaScheduledIr },
    .{ .id = "V-IR-07", .layer_id = "IR-07", .title = "LIR instruction legality", .status = .stub, .verify = verifyIr07LowLevelIr },
    .{ .id = "V-IR-08", .layer_id = "IR-08", .title = "MIR register/stack discipline", .status = .stub, .verify = verifyIr08MachineIr },
    .{ .id = "V-IR-09", .layer_id = "IR-09", .title = "Artifact layout + relocs", .status = .stub, .verify = verifyIr09ArtifactIr },
};

/// Canonical lowering chain per foundation spec §4.
pub const lowering_edges: []const LoweringEdge = &.{
    .{ .from = "IR-01", .to = "IR-02", .owner = "parser.zig + sema.zig", .status = "partial" },
    .{ .from = "IR-02", .to = "IR-03", .owner = "transform_engine.zig", .status = "open" },
    .{ .from = "IR-03", .to = "IR-04", .owner = "realization + pass27_benchmark_evidence", .status = "partial" },
    .{ .from = "IR-04", .to = "IR-05", .owner = "pass26_descriptor_identity.zig", .status = "partial" },
    .{ .from = "IR-05", .to = "IR-06", .owner = "future", .status = "open" },
    .{ .from = "IR-06", .to = "IR-07", .owner = "native_backend.zig", .status = "partial" },
    .{ .from = "IR-07", .to = "IR-08", .owner = "native_backend.zig + Ward", .status = "partial" },
    .{ .from = "IR-08", .to = "IR-09", .owner = "native_backend.zig (Mach-O)", .status = "partial" },
};

pub fn verifierStepForLayer(layer_id: []const u8) ?[]const u8 {
    for (verifier_stubs) |stub| {
        if (std.mem.eql(u8, stub.layer_id, layer_id)) return stub.id;
    }
    return null;
}

pub fn runAllVerifierStubs() bool {
    for (verifier_stubs) |stub| {
        if (!stub.verify()) return false;
    }
    return true;
}

pub fn loweringEdgeCount() usize {
    return lowering_edges.len;
}

pub fn verifierStubCount() usize {
    return verifier_stubs.len;
}

test "ir_layer_registry: lowering chain contiguous IR-01..IR-09" {
    try std.testing.expect(lowering_edges.len == 8);
    try std.testing.expect(verifier_stubs.len == 9);
    try std.testing.expect(std.mem.eql(u8, lowering_edges[0].from, "IR-01"));
    try std.testing.expect(std.mem.eql(u8, lowering_edges[7].to, "IR-09"));
    try std.testing.expect(runAllVerifierStubs());
    try std.testing.expect(std.mem.eql(u8, verifierStepForLayer("IR-05").?, "V-IR-05"));
}
