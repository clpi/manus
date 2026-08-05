//! Pass 5 Layer B — map C frontend records into SIM v0 entities.
const std = @import("std");
const c_frontend = @import("c_frontend.zig");
const c_layout_verify = @import("c_layout_verify.zig");
const sim = @import("sim.zig");

fn cEntityId(alloc: std.mem.Allocator, kind: sim.EntityKind, name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "c:{s}:{s}", .{ kind.name(), name });
}

fn typeToSimLabel(alloc: std.mem.Allocator, tr: c_frontend.TypeRef) ![]const u8 {
    return switch (tr) {
        .scalar => |s| try alloc.dupe(u8, switch (s) {
            .f64 => "f64",
            .f32 => "f32",
            .i64 => "i64",
            .i32 => "i32",
            .i16 => "i16",
            .i8 => "i8",
            .u64 => "u64",
            .u32 => "u32",
            .u16 => "u16",
            .u8 => "u8",
            .bool => "bool",
            .char => "i8",
            .void => "void",
            .unknown => "unknown",
        }),
        else => try tr.display(alloc),
    };
}

fn scalarSizeAlign(sc: c_frontend.ScalarKind) struct { size: usize, alignment: usize } {
    return switch (sc) {
        .f64, .i64, .u64 => .{ .size = 8, .alignment = 8 },
        .f32, .i32, .u32 => .{ .size = 4, .alignment = 4 },
        .i16, .u16 => .{ .size = 2, .alignment = 2 },
        .i8, .u8, .bool, .char => .{ .size = 1, .alignment = 1 },
        .void => .{ .size = 0, .alignment = 1 },
        .unknown => .{ .size = 0, .alignment = 1 },
    };
}

fn recordLayout(fields: []const c_frontend.FieldDecl) struct { size: ?usize, alignment: ?usize, complete: sim.Completeness } {
    var size: usize = 0;
    var alignment: usize = 1;
    for (fields) |f| {
        switch (f.typ) {
            .scalar => |s| {
                const la = scalarSizeAlign(s);
                if (la.size == 0 and s != .void) return .{ .size = null, .alignment = null, .complete = .partial };
                if (la.alignment > alignment) alignment = la.alignment;
                const off = std.mem.alignForward(usize, size, la.alignment);
                size = off + la.size;
            },
            else => return .{ .size = null, .alignment = null, .complete = .partial },
        }
    }
    size = std.mem.alignForward(usize, size, alignment);
    return .{ .size = size, .alignment = alignment, .complete = .partial };
}

fn appendRecord(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(sim.Entity),
    artifact: []const u8,
    rec: c_frontend.RecordDecl,
) !void {
    var fields = try alloc.alloc(sim.Field, rec.fields.len);
    errdefer alloc.free(fields);
    for (rec.fields, 0..) |f, i| {
        fields[i] = .{
            .name = try alloc.dupe(u8, f.name),
            .type_name = try typeToSimLabel(alloc, f.typ),
            .offset = null,
        };
    }

    var layout = recordLayout(rec.fields);
    const layout_why: []const u8 = blk: {
        if (try c_layout_verify.verifyRecordWithClang(alloc, rec)) |v| {
            var verified = v;
            defer verified.deinit(alloc);
            layout.size = verified.size;
            layout.alignment = verified.alignment;
            layout.complete = .complete;
            for (fields, 0..) |*field, i| {
                if (i < verified.fields.len) field.offset = verified.fields[i].offset;
            }
            break :blk "imported C record; target layout verified via clang probe";
        }
        var offset: usize = 0;
        var max_align: usize = 1;
        for (rec.fields, 0..) |f, i| {
            if (f.typ == .scalar) {
                const la = scalarSizeAlign(f.typ.scalar);
                if (la.alignment > max_align) max_align = la.alignment;
                offset = std.mem.alignForward(usize, offset, la.alignment);
                fields[i].offset = offset;
                offset += la.size;
            }
        }
        break :blk "imported C record; layout heuristic until target-verified";
    };

    const completeness: sim.Completeness = if (rec.is_opaque)
        .opaque_region
    else if (rec.fields.len == 0)
        .partial
    else
        layout.complete;

    try list.append(alloc, .{
        .id = try cEntityId(alloc, .record, rec.name),
        .kind = .record,
        .name = try alloc.dupe(u8, rec.name),
        .namespace = try alloc.dupe(u8, "foreign"),
        .completeness = completeness,
        .origin = .{
            .language = "c",
            .artifact = try alloc.dupe(u8, artifact),
            .importer = "duo-c-frontend",
            .importer_version = c_frontend.FRONTEND_VERSION,
        },
        .storage_class = try alloc.dupe(u8, "foreign-record"),
        .why = try alloc.dupe(u8, layout_why),
        .fields = fields,
        .size_bytes = layout.size,
        .align_bytes = layout.alignment,
        .contract = .{
            .origin_language = "c",
            .semantic_completeness = if (rec.is_opaque) .opaque_region else .complete,
            .abi_completeness = .partial,
            .layout_completeness = layout.complete,
            .ownership_completeness = .unknown,
            .effect_completeness = .unknown,
        },
    });
}

fn appendFunction(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(sim.Entity),
    artifact: []const u8,
    fn_: c_frontend.FunctionDecl,
) !void {
    var params = try alloc.alloc(sim.Param, fn_.params.len);
    errdefer alloc.free(params);
    for (fn_.params, 0..) |p, i| {
        params[i] = .{
            .name = try alloc.dupe(u8, p.name),
            .type_name = try typeToSimLabel(alloc, p.typ),
        };
    }
    const ret_name = try typeToSimLabel(alloc, fn_.ret);

    try list.append(alloc, .{
        .id = try cEntityId(alloc, .function, fn_.name),
        .kind = .function,
        .name = try alloc.dupe(u8, fn_.name),
        .namespace = try alloc.dupe(u8, "foreign"),
        .completeness = .complete,
        .origin = .{
            .language = "c",
            .artifact = try alloc.dupe(u8, artifact),
            .importer = "duo-c-frontend",
            .importer_version = c_frontend.FRONTEND_VERSION,
        },
        .params = params,
        .return_type = ret_name,
        .abi = .{ .calling_convention = "c", .pass_by = "target-default" },
        .contract = .{
            .origin_language = "c",
            .semantic_completeness = .complete,
            .abi_completeness = .partial,
            .layout_completeness = .unknown,
            .ownership_completeness = .unknown,
            .effect_completeness = .unknown,
        },
    });
}

fn appendOpaqueUnsupported(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(sim.Entity),
    artifact: []const u8,
    u: c_frontend.UnsupportedRegion,
    index: usize,
) !void {
    const id = try std.fmt.allocPrint(alloc, "c:unsupported:{d}", .{index});
    errdefer alloc.free(id);
    try list.append(alloc, .{
        .id = id,
        .kind = .unknown,
        .name = try alloc.dupe(u8, u.kind),
        .namespace = try alloc.dupe(u8, "foreign"),
        .completeness = .unsupported,
        .origin = .{
            .language = "c",
            .artifact = artifact,
            .importer = "duo-c-frontend",
            .importer_version = c_frontend.FRONTEND_VERSION,
        },
        .why = try std.fmt.allocPrint(alloc, "{s}: {s}", .{ u.kind, u.reason }),
        .contract = .{
            .origin_language = "c",
            .semantic_completeness = .unsupported,
            .abi_completeness = .unsupported,
            .layout_completeness = .unsupported,
            .ownership_completeness = .unknown,
            .effect_completeness = .unknown,
        },
    });
}

fn cmpEntityId(_: void, a: sim.Entity, b: sim.Entity) bool {
    return std.mem.order(u8, a.id, b.id) == .lt;
}

/// Import a C header path into a SIM v0 snapshot.
pub fn importHeaderFile(alloc: std.mem.Allocator, io: std.Io, header_path: []const u8) !sim.Snapshot {
    const cwd = std.Io.Dir.cwd();
    const src = try std.Io.Dir.readFileAlloc(cwd, io, header_path, alloc, .unlimited);
    defer alloc.free(src);
    return importHeaderSource(alloc, header_path, src);
}

/// Import C header source text into a SIM v0 snapshot.
pub fn importHeaderSource(alloc: std.mem.Allocator, artifact: []const u8, src: []const u8) !sim.Snapshot {
    var frontend = try c_frontend.parseHeader(alloc, artifact, src);
    defer frontend.deinit(alloc);

    const owned_file = try alloc.dupe(u8, artifact);
    var list: std.ArrayListUnmanaged(sim.Entity) = .empty;
    errdefer {
        var snap = sim.Snapshot{ .file = owned_file, .entities = list.items };
        snap.deinit(alloc);
    }

    for (frontend.records) |rec| try appendRecord(alloc, &list, owned_file, rec);
    for (frontend.functions) |fn_| try appendFunction(alloc, &list, owned_file, fn_);
    for (frontend.unsupported, 0..) |u, i| try appendOpaqueUnsupported(alloc, &list, owned_file, u, i);

    std.mem.sort(sim.Entity, list.items, {}, cmpEntityId);
    return .{
        .file = owned_file,
        .entities = try list.toOwnedSlice(alloc),
    };
}

test "c_sim_import: point.h → SIM entities" {
    const src =
        \\typedef struct {
        \\    double x;
        \\    double y;
        \\} CPoint;
        \\double distance2(CPoint point);
    ;
    var snap = try importHeaderSource(std.testing.allocator, "examples/pass5/fixtures/point.h", src);
    defer snap.deinit(std.testing.allocator);

    try std.testing.expect(snap.entities.len >= 2);
    var found_record = false;
    var found_fn = false;
    for (snap.entities) |ent| {
        if (std.mem.eql(u8, ent.id, "c:record:CPoint")) {
            found_record = true;
            try std.testing.expectEqualStrings("c", ent.origin.language);
            try std.testing.expectEqual(@as(usize, 2), ent.fields.len);
            try std.testing.expectEqual(@as(?usize, 16), ent.size_bytes);
        }
        if (std.mem.eql(u8, ent.id, "c:function:distance2")) {
            found_fn = true;
            try std.testing.expect(ent.abi != null);
            try std.testing.expectEqualStrings("c", ent.abi.?.calling_convention);
        }
    }
    try std.testing.expect(found_record);
    try std.testing.expect(found_fn);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try sim.writeSnapshotJson(&snap, &aw.writer);
    const j1 = aw.written();
    aw = .init(std.testing.allocator);
    try sim.writeSnapshotJson(&snap, &aw.writer);
    try std.testing.expectEqualStrings(j1, aw.written());
}
