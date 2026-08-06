//! Pass 20 native gate proofs — C harness + import strength + foreign adaptation.
const std = @import("std");
const pass20_catalog = @import("pass20_catalog.zig");
const pass20_import_strength = @import("pass20_import_strength.zig");
const sim = @import("sim.zig");
const c_sim_import = @import("c_sim_import.zig");
const foreign_adapter = @import("foreign_adapter.zig");
const abi_specialize = @import("abi_specialize.zig");

const point_h = @import("pass5_fixtures.zig").point_h;

pub const GateError = error{ GateFailed };

pub fn validatePass20Catalog() GateError!void {
    if (!std.mem.eql(u8, pass20_catalog.SCHEMA_VERSION, "pass20-catalog-v0")) return error.GateFailed;
    if (pass20_catalog.workstreams.len != 12) return error.GateFailed;
    if (pass20_catalog.adoption_ladder.len != 9) return error.GateFailed;
    if (pass20_catalog.ready_tools.len != 10) return error.GateFailed;
    if (pass20_catalog.completion_gates.len != 12) return error.GateFailed;
}

/// Gate G02 partial — C header imports as SIM with stable entity IDs.
pub fn proveForeignImportSnapshot(alloc: std.mem.Allocator) GateError!void {
    var snap = c_sim_import.importHeaderSource(alloc, "examples/pass5/fixtures/point.h", point_h) catch return error.GateFailed;
    defer snap.deinit(alloc);
    abi_specialize.specializeSnapshot(alloc, &snap) catch return error.GateFailed;

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    sim.writeSnapshotJson(&snap, &aw.writer) catch return error.GateFailed;
    const json = aw.written();
    if (std.mem.indexOf(u8, json, "\"id\":\"c:record:CPoint\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, json, "\"id\":\"c:function:distance2\"") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, json, "\"origin_language\":\"c\"") == null) return error.GateFailed;

    aw.deinit();
    aw = .init(alloc);
    sim.writeSnapshotJson(&snap, &aw.writer) catch return error.GateFailed;
    if (!std.mem.eql(u8, json, aw.written())) return error.GateFailed;
}

/// Gate G02/G05 — foreign snapshot adapts to compiler descriptors with provenance.
pub fn proveForeignAdaptation(alloc: std.mem.Allocator) GateError!void {
    var snap = c_sim_import.importHeaderSource(alloc, "examples/pass5/fixtures/point.h", point_h) catch return error.GateFailed;
    defer snap.deinit(alloc);
    abi_specialize.specializeSnapshot(alloc, &snap) catch return error.GateFailed;

    var module = foreign_adapter.adaptSnapshot(alloc, &snap) catch return error.GateFailed;
    defer module.deinit(alloc);

    const distance = module.functions.get("distance2") orelse return error.GateFailed;
    if (!std.mem.eql(u8, distance.sim_id, "c:function:distance2")) return error.GateFailed;
    if (std.mem.indexOf(u8, distance.origin_artifact, "point.h") == null) return error.GateFailed;

    const point = module.records.get("CPoint") orelse return error.GateFailed;
    if (point != .table_type) return error.GateFailed;
}

/// Import strength classification must not claim text-only for C header import.
pub fn proveImportStrength() GateError!void {
    var snap = c_sim_import.importHeaderSource(std.heap.page_allocator, "examples/pass5/fixtures/point.h", point_h) catch return error.GateFailed;
    defer snap.deinit(std.heap.page_allocator);
    const report = pass20_import_strength.classifySnapshot(&snap);
    if (@intFromEnum(report.strength) < @intFromEnum(pass20_import_strength.ImportStrength.declared_semantic)) return error.GateFailed;
    if (report.entity_count < 2) return error.GateFailed;
}

pub fn validatePass20Gate() GateError!void {
    try validatePass20Catalog();
    try proveImportStrength();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try proveForeignImportSnapshot(arena.allocator());
    try proveForeignAdaptation(arena.allocator());
}

test "pass20_gate: catalog + C harness gates" {
    try validatePass20Gate();
}
