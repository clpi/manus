//! Pass 5 Layer C — adapt SIM entities into Duo compiler foreign descriptors.
const std = @import("std");
const sim = @import("sim.zig");
const types = @import("types.zig");
const pass26_wiring = @import("pass26_wiring.zig");
const pass26_abi_resource = @import("pass26_abi_resource.zig");

pub const ForeignFunc = struct {
    name: []const u8,
    c_symbol: []const u8,
    params: []types.ResolvedType,
    ret: types.ResolvedType,
    origin_artifact: []const u8,
    sim_id: []const u8,
    /// From SIM `abi.pass_by` after `abi.specialize` (`value`, `pointer`, …).
    pass_by: []const u8 = "unknown",
    /// Pass 26 — semantic boundary on C foreign lift (default P26-B02).
    boundary_id: []const u8 = "P26-B02",
    /// Pass 26 — calling convention descriptor kind.
    calling_conv: pass26_abi_resource.CallingConventionKind = .c_abi,

    pub fn deinit(self: *ForeignFunc, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        alloc.free(self.c_symbol);
        alloc.free(self.params);
        alloc.free(self.origin_artifact);
        alloc.free(self.sim_id);
        if (!std.mem.eql(u8, self.pass_by, "unknown")) alloc.free(self.pass_by);
    }
};

pub const ForeignModule = struct {
    artifact: []const u8,
    records: std.StringHashMapUnmanaged(types.ResolvedType),
    functions: std.StringHashMapUnmanaged(ForeignFunc),

    pub fn deinit(self: *ForeignModule, alloc: std.mem.Allocator) void {
        alloc.free(self.artifact);
        var rit = self.records.iterator();
        while (rit.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            freeRecordRt(alloc, entry.value_ptr);
        }
        self.records.deinit(alloc);
        var fit = self.functions.iterator();
        while (fit.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(alloc);
        }
        self.functions.deinit(alloc);
    }
};

fn freeRecordRt(alloc: std.mem.Allocator, rt: *types.ResolvedType) void {
    if (rt.* != .table_type) return;
    for (rt.table_type.fields) |f| alloc.free(f.name);
    alloc.free(rt.table_type.fields);
    if (rt.table_type.ffi_name) |n| alloc.free(n);
}

/// Resolve a `#include`-style header path relative to the Duo source file.
pub fn resolveHeaderPath(
    alloc: std.mem.Allocator,
    io: std.Io,
    source_path: ?[]const u8,
    header: []const u8,
) ![]const u8 {
    if (std.fs.path.isAbsolute(header)) return try alloc.dupe(u8, header);
    const cwd = std.Io.Dir.cwd();
    if (pathAccessible(cwd, io, header)) {
        return try alloc.dupe(u8, header);
    }
    if (source_path) |sp| {
        if (std.fs.path.dirname(sp)) |dir| {
            const joined = try std.fs.path.join(alloc, &.{ dir, header });
            if (pathAccessible(cwd, io, joined)) return joined;
            alloc.free(joined);
        }
    }
    return try alloc.dupe(u8, header);
}

fn pathAccessible(cwd: std.Io.Dir, io: std.Io, path: []const u8) bool {
    std.Io.Dir.access(cwd, io, path, .{}) catch return false;
    return true;
}

fn scalarFromLabel(label: []const u8) ?types.ResolvedType {
    if (std.mem.eql(u8, label, "f64") or std.mem.eql(u8, label, "double")) return .f64;
    if (std.mem.eql(u8, label, "f32") or std.mem.eql(u8, label, "float")) return .f32;
    if (std.mem.eql(u8, label, "i64")) return .i64;
    if (std.mem.eql(u8, label, "i32")) return .i32;
    if (std.mem.eql(u8, label, "i16")) return .i16;
    if (std.mem.eql(u8, label, "i8")) return .i8;
    if (std.mem.eql(u8, label, "u64")) return .u64;
    if (std.mem.eql(u8, label, "u32")) return .u32;
    if (std.mem.eql(u8, label, "u16")) return .u16;
    if (std.mem.eql(u8, label, "u8")) return .u8;
    if (std.mem.eql(u8, label, "bool")) return .bool;
    if (std.mem.eql(u8, label, "void")) return .void;
    if (std.mem.eql(u8, label, "str")) return .str;
    return null;
}

fn typeFromLabel(
    alloc: std.mem.Allocator,
    label: []const u8,
    records: *const std.StringHashMapUnmanaged(types.ResolvedType),
) !types.ResolvedType {
    if (label.len > 1 and label[label.len - 1] == '*') {
        const inner = try typeFromLabel(alloc, label[0 .. label.len - 1], records);
        return wrapPassByPointer(alloc, inner);
    }
    if (scalarFromLabel(label)) |sc| return sc;
    if (records.get(label)) |existing| return existing;
    return types.ResolvedType{ .@"struct" = .{ .name = try alloc.dupe(u8, label) } };
}

fn recordFromEntity(alloc: std.mem.Allocator, ent: sim.Entity) !types.ResolvedType {
    var fields = try alloc.alloc(types.FieldType, ent.fields.len);
    errdefer alloc.free(fields);
    for (ent.fields, 0..) |f, i| {
        fields[i] = .{
            .name = try alloc.dupe(u8, f.name),
            .typ = scalarFromLabel(f.type_name) orelse .any,
        };
    }
    var rt: types.ResolvedType = .{
        .table_type = .{
            .fields = fields,
            .storage_class = if (types.fieldsAreNative(fields)) .native else .sealed,
            .is_sealed = true,
            .ffi_name = try alloc.dupe(u8, ent.name),
            .align_n = ent.align_bytes,
        },
    };
    if (ent.storage_class) |sc| {
        if (std.mem.eql(u8, sc, "native")) rt.table_type.storage_class = .native;
    }
    if (!types.fieldsAreNative(fields)) rt.table_type.storage_class = .dynamic;
    return rt;
}

fn wrapPassByPointer(alloc: std.mem.Allocator, rt: types.ResolvedType) !types.ResolvedType {
    const ptr = try alloc.create(types.ResolvedType);
    ptr.* = rt;
    return .{ .pointer = ptr };
}

fn funcFromEntity(
    alloc: std.mem.Allocator,
    ent: sim.Entity,
    records: *const std.StringHashMapUnmanaged(types.ResolvedType),
) !ForeignFunc {
    var params = try alloc.alloc(types.ResolvedType, ent.params.len);
    errdefer alloc.free(params);
    for (ent.params, 0..) |p, i| {
        params[i] = try typeFromLabel(alloc, p.type_name, records);
    }
    const pass_by = if (ent.abi) |abi| abi.pass_by else "unknown";
    // `pass_by` is a realization fact. The C parameter type remains the type
    // declared by the header.
    const ret = if (ent.return_type) |rt|
        try typeFromLabel(alloc, rt, records)
    else
        types.ResolvedType.any;
    const pass_by_owned = if (std.mem.eql(u8, pass_by, "unknown"))
        "unknown"
    else
        try alloc.dupe(u8, pass_by);
    const lift_meta = pass26_wiring.foreignLiftMetadata(pass_by);
    return .{
        .name = try alloc.dupe(u8, ent.name),
        .c_symbol = try alloc.dupe(u8, ent.name),
        .params = params,
        .ret = ret,
        .origin_artifact = try alloc.dupe(u8, ent.origin.artifact),
        .sim_id = try alloc.dupe(u8, ent.id),
        .pass_by = pass_by_owned,
        .boundary_id = lift_meta.boundary_id,
        .calling_conv = lift_meta.calling_conv,
    };
}

/// Adapt a C-imported SIM snapshot into compiler foreign descriptors.
pub fn adaptSnapshot(alloc: std.mem.Allocator, snap: *const sim.Snapshot) !ForeignModule {
    const artifact = try alloc.dupe(u8, snap.file);
    var records: std.StringHashMapUnmanaged(types.ResolvedType) = .empty;
    var functions: std.StringHashMapUnmanaged(ForeignFunc) = .empty;
    errdefer {
        var mod = ForeignModule{ .artifact = artifact, .records = records, .functions = functions };
        mod.deinit(alloc);
    }

    for (snap.entities) |ent| {
        if (ent.kind == .record and ent.origin.language.len > 0 and std.mem.eql(u8, ent.origin.language, "c")) {
            const rt = try recordFromEntity(alloc, ent);
            try records.put(alloc, try alloc.dupe(u8, ent.name), rt);
        }
    }
    for (snap.entities) |ent| {
        if (ent.kind == .function and std.mem.eql(u8, ent.origin.language, "c")) {
            const ff = try funcFromEntity(alloc, ent, &records);
            try functions.put(alloc, try alloc.dupe(u8, ent.name), ff);
        }
    }

    return .{
        .artifact = artifact,
        .records = records,
        .functions = functions,
    };
}
