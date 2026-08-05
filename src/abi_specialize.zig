//! Pass 5 Layer C — shared ABI specialization for native Duo + imported foreign SIM entities.
const std = @import("std");
const sim = @import("sim.zig");
const transform_engine = @import("transform_engine.zig");

pub const TRANSFORM_ID: []const u8 = "abi.specialize";

fn isNativeScalarLabel(label: []const u8) bool {
    return std.mem.eql(u8, label, "f64") or
        std.mem.eql(u8, label, "f32") or
        std.mem.eql(u8, label, "i64") or
        std.mem.eql(u8, label, "i32") or
        std.mem.eql(u8, label, "i16") or
        std.mem.eql(u8, label, "i8") or
        std.mem.eql(u8, label, "u64") or
        std.mem.eql(u8, label, "u32") or
        std.mem.eql(u8, label, "u16") or
        std.mem.eql(u8, label, "u8") or
        std.mem.eql(u8, label, "bool") or
        std.mem.eql(u8, label, "double") or
        std.mem.eql(u8, label, "float");
}

fn recordEntityByName(entities: []const sim.Entity, name: []const u8) ?sim.Entity {
    for (entities) |ent| {
        if (ent.kind == .record and std.mem.eql(u8, ent.name, name)) return ent;
    }
    return null;
}

fn recordHasNativeLayout(ent: sim.Entity) bool {
    if (ent.fields.len == 0) return false;
    for (ent.fields) |f| {
        if (!isNativeScalarLabel(f.type_name)) return false;
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
    if (isNativeScalarLabel(param.type_name)) return "value";
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

test "abi_specialize: C point.h snapshot gets native ABI" {
    const c_sim_import = @import("c_sim_import.zig");
    const src = @import("pass5_fixtures.zig").point_h;
    var snap = try c_sim_import.importHeaderSource(std.testing.allocator, "point.h", src);
    defer snap.deinit(std.testing.allocator);

    try specializeSnapshot(std.testing.allocator, &snap);

    const cpoint = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "c:record:CPoint")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    try std.testing.expect(cpoint.storage_class != null);
    try std.testing.expectEqualStrings("native", cpoint.storage_class.?);
    try std.testing.expectEqual(sim.Completeness.complete, cpoint.contract.abi_completeness);

    const distance2 = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "c:function:distance2")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    try std.testing.expect(distance2.abi != null);
    try std.testing.expectEqualStrings("c", distance2.abi.?.calling_convention);
    try std.testing.expectEqualStrings("value", distance2.abi.?.pass_by);
    try std.testing.expectEqual(sim.Completeness.complete, distance2.contract.abi_completeness);
}

test "abi_specialize: native Duo Point + distance2" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
    , "point.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);

    var snap = try sim.exportNativeModule(alloc, &mod, "point.duo");
    defer snap.deinit(alloc);
    try specializeSnapshot(alloc, &snap);

    const distance2 = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "duo:function:distance2")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(sim.Completeness.complete, distance2.contract.abi_completeness);
    try std.testing.expect(distance2.abi != null);
    try std.testing.expectEqualStrings("duo-native", distance2.abi.?.calling_convention);
}

test "abi_specialize: large C struct param gets pointer pass_by" {
    const c_sim_import = @import("c_sim_import.zig");
    const src =
        \\typedef struct {
        \\    double a;
        \\    double b;
        \\    double c;
        \\    double d;
        \\} CBigRect;
        \\double sum4(CBigRect rect);
    ;
    var snap = try c_sim_import.importHeaderSource(std.testing.allocator, "big_rect_byval.h", src);
    defer snap.deinit(std.testing.allocator);
    try specializeSnapshot(std.testing.allocator, &snap);

    const sum4 = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "c:function:sum4")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    try std.testing.expect(sum4.abi != null);
    try std.testing.expectEqualStrings("pointer", sum4.abi.?.pass_by);
}
