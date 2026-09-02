//! Layer C — shared ABI specialization for native Duo + imported foreign SIM entities.
const std = @import("std");
const sim = @import("sim.zig");
const transform_engine = @import("transform_engine.zig");
const types = @import("types.zig");

pub const TRANSFORM_ID: []const u8 = "abi.specialize";

fn recordEntityByName(entities: []const sim.Entity, name: []const u8) ?sim.Entity {
    for (entities) |ent| {
        if (ent.kind == .record and std.mem.eql(u8, ent.name, name)) return ent;
    }
    return null;
}

fn recordHasNativeLayout(ent: sim.Entity) bool {
    if (ent.fields.len == 0) return false;
    for (ent.fields) |f| {
        if (types.abiDescriptorNamed(f.type_name) == null) return false;
    }
    return ent.size_bytes != null and ent.align_bytes != null;
}

fn specializeRecord(alloc: std.mem.Allocator, ent: *sim.Entity) !void {
    const is_c = std.mem.eql(u8, ent.origin.language, "c");
    const is_duo = std.mem.eql(u8, ent.origin.language, "duo");
    if (!is_c and !is_duo) return;
    if (!recordHasNativeLayout(ent.*)) return;

    if (is_c) {
        if (ent.storage_class) |sc| alloc.free(sc);
        ent.storage_class = try alloc.dupe(u8, "native");
        if (ent.why) |w| alloc.free(w);
        ent.why = try alloc.dupe(u8, "abi.specialize: C record lowered to native pass-by-value layout");
    }

    ent.contract.abi_completeness = .complete;
    if (ent.fields[0].offset != null) {
        ent.contract.layout_completeness = .complete;
    }
}

fn passByForParam(entities: []const sim.Entity, param: sim.Param) []const u8 {
    if (types.abiDescriptorNamed(param.type_name) != null) return "value";
    if (param.type_name.len > 1 and param.type_name[param.type_name.len - 1] == '*') return "pointer";
    if (recordEntityByName(entities, param.type_name)) |rec| {
        if (rec.size_bytes) |sz| {
            if (sz <= 16) return "value";
            return "pointer";
        }
    }
    return "target-default";
}

fn specializeFunction(alloc: std.mem.Allocator, ent: *sim.Entity, entities: []const sim.Entity) !void {
    _ = alloc;
    const is_c = std.mem.eql(u8, ent.origin.language, "c");
    const is_duo = std.mem.eql(u8, ent.origin.language, "duo");
    if (!is_c and !is_duo) return;

    var pass_by: []const u8 = if (is_c) "c-calling-convention" else "duo-native";
    if (ent.params.len == 1) {
        pass_by = passByForParam(entities, ent.params[0]);
    } else if (ent.params.len > 1) {
        pass_by = "target-default";
    }

    ent.abi = .{
        .calling_convention = if (is_c) "c" else "duo-native",
        .pass_by = pass_by,
    };
    ent.contract.abi_completeness = .complete;
}

fn snapshotHash(snap: *const sim.Snapshot, include_abi: bool) u64 {
    var h: u64 = std.hash.Wyhash.hash(0, snap.file);
    for (snap.entities) |ent| {
        h ^= std.hash.Wyhash.hash(0, ent.id);
        if (include_abi) {
            h ^= @intFromEnum(ent.contract.abi_completeness);
            if (ent.abi) |abi| {
                h ^= std.hash.Wyhash.hash(0, abi.calling_convention);
                h ^= std.hash.Wyhash.hash(0, abi.pass_by);
            }
            if (ent.storage_class) |sc| h ^= std.hash.Wyhash.hash(0, sc);
        }
    }
    return h;
}

/// Apply shared ABI specialization to all entities in a SIM snapshot (in-place).
pub fn specializeSnapshot(alloc: std.mem.Allocator, snap: *sim.Snapshot) !void {
    const input_hash = snapshotHash(snap, false);
    for (snap.entities) |*ent| {
        switch (ent.kind) {
            .record => try specializeRecord(alloc, ent),
            .function => try specializeFunction(alloc, ent, snap.entities),
            else => {},
        }
    }
    const output_hash = snapshotHash(snap, true);
    transform_engine.logProvenance(alloc, TRANSFORM_ID, .emit_call, input_hash, output_hash);
}
