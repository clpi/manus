/// Semantic Interchange Model (SIM) v0 — versioned projection of Duo compiler facts.
///
/// SIM is not the internal semantic graph. It is a stable, serializable boundary for
/// MCP, LSP, foreign import, transformation input, and semantic diff (Layer A).
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const sema = @import("sema.zig");
const semantic_algebra = @import("semantic_algebra.zig");

pub const SCHEMA_VERSION: []const u8 = "sim-v0";

pub const Completeness = enum {
    complete,
    partial,
    opaque_region,
    unsupported,
    unknown,

    pub fn name(self: Completeness) []const u8 {
        return switch (self) {
            .opaque_region => "opaque",
            else => @tagName(self),
        };
    }
};

pub const EntityKind = enum {
    primitive,
    record,
    enum_type,
    function,
    opaque_type,
    unknown,

    pub fn name(self: EntityKind) []const u8 {
        return switch (self) {
            .enum_type => "enum",
            .opaque_type => "opaque",
            else => @tagName(self),
        };
    }
};

pub const Origin = struct {
    language: []const u8,
    artifact: []const u8,
    importer: []const u8 = "duo-compiler",
    importer_version: []const u8 = SCHEMA_VERSION,
};

pub const Contract = struct {
    origin_language: []const u8 = "duo",
    semantic_completeness: Completeness = .unknown,
    abi_completeness: Completeness = .unknown,
    layout_completeness: Completeness = .unknown,
    ownership_completeness: Completeness = .unknown,
    effect_completeness: Completeness = .unknown,
};

pub const Field = struct {
    name: []const u8,
    type_name: []const u8,
    offset: ?usize = null,
};

pub const Param = struct {
    name: []const u8,
    type_name: []const u8,
};

pub const AbiMeta = struct {
    calling_convention: []const u8 = "unknown",
    pass_by: []const u8 = "unknown",
};

pub const Entity = struct {
    id: []const u8,
    kind: EntityKind,
    name: []const u8,
    namespace: []const u8,
    completeness: Completeness,
    origin: Origin,
    storage_class: ?[]const u8 = null,
    shape_id: ?u64 = null,
    why: ?[]const u8 = null,
    fields: []Field = &.{},
    variants: []const []const u8 = &.{},
    params: []Param = &.{},
    return_type: ?[]const u8 = null,
    size_bytes: ?usize = null,
    align_bytes: ?usize = null,
    abi: ?AbiMeta = null,
    contract: Contract = .{},
};

pub const Snapshot = struct {
    schema: []const u8 = SCHEMA_VERSION,
    file: []const u8,
    target: ?[]const u8 = null,
    entities: []Entity,

    pub fn deinit(self: *Snapshot, alloc: std.mem.Allocator) void {
        for (self.entities) |*ent| {
            alloc.free(ent.id);
            alloc.free(ent.name);
            alloc.free(ent.namespace);
            if (ent.origin.artifact.ptr != self.file.ptr) {
                alloc.free(ent.origin.artifact);
            }
            if (ent.storage_class) |sc| alloc.free(sc);
            if (ent.why) |w| alloc.free(w);
            for (ent.fields) |f| {
                alloc.free(f.name);
                alloc.free(f.type_name);
            }
            alloc.free(ent.fields);
            for (ent.variants) |v| alloc.free(v);
            alloc.free(ent.variants);
            for (ent.params) |p| {
                alloc.free(p.name);
                alloc.free(p.type_name);
            }
            alloc.free(ent.params);
            if (ent.return_type) |r| alloc.free(r);
        }
        alloc.free(self.entities);
        alloc.free(self.file);
    }
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => try w.writeAll(&.{c}),
    };
}

fn typeLabel(alloc: std.mem.Allocator, te: ast.TypeExpr) ![]const u8 {
    const rt = try types.resolve(te, null, alloc);
    var buf: [128]u8 = undefined;
    return try alloc.dupe(u8, rt.c_type(&buf));
}

fn entityId(alloc: std.mem.Allocator, kind: EntityKind, name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "duo:{s}:{s}", .{ kind.name(), name });
}

fn appendRecordEntity(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(Entity),
    file: []const u8,
    name: []const u8,
    rt: types.ResolvedType,
    attributes: []const ast.Attribute,
) !void {
    if (rt != .table_type) return;
    const t = rt.table_type;
    var fields = try alloc.alloc(Field, t.fields.len);
    errdefer alloc.free(fields);
    for (t.fields, 0..) |f, i| {
        var tb: [64]u8 = undefined;
        const tn = try alloc.dupe(u8, f.typ.c_type(&tb));
        fields[i] = .{ .name = try alloc.dupe(u8, f.name), .type_name = tn, .offset = null };
    }
    var rt_mut = rt;
    types.applyTableShapeAttrs(&rt_mut, attributes);
    const sc = types.inferStorageClass(t.fields, t.is_sealed, rt_mut.table_type.storage_class);
    const completeness: Completeness = if (t.fields.len == 0)
        .partial
    else if (sc == .native and types.fieldsAreNative(t.fields))
        .complete
    else if (sc == .dynamic)
        .partial
    else
        .complete;

    const contract = Contract{
        .origin_language = "duo",
        .semantic_completeness = completeness,
        .abi_completeness = if (sc == .native) .complete else .partial,
        .layout_completeness = if (sc == .native or sc == .sealed) .complete else .partial,
        .ownership_completeness = .unknown,
        .effect_completeness = .unknown,
    };

    try list.append(alloc, .{
        .id = try entityId(alloc, .record, name),
        .kind = .record,
        .name = try alloc.dupe(u8, name),
        .namespace = try alloc.dupe(u8, "module"),
        .completeness = completeness,
        .origin = .{ .language = "duo", .artifact = file },
        .storage_class = try alloc.dupe(u8, types.storageClassName(sc)),
        .shape_id = types.tableShapeIdentityHash(rt_mut),
        .why = try alloc.dupe(u8, types.explainStorageClass(rt_mut)),
        .fields = fields,
        .size_bytes = if (types.fieldsAreNative(t.fields)) t.fields.len * 8 else null,
        .align_bytes = t.align_n orelse 8,
        .contract = contract,
    });
}

fn appendEnumEntity(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(Entity),
    file: []const u8,
    ed: *const ast.EnumDef,
) !void {
    var variants = try alloc.alloc([]const u8, ed.variants.len);
    errdefer {
        for (variants) |v| alloc.free(v);
        alloc.free(variants);
    }
    for (ed.variants, 0..) |v, i| {
        variants[i] = try alloc.dupe(u8, v.name);
    }
    try list.append(alloc, .{
        .id = try entityId(alloc, .enum_type, ed.name),
        .kind = .enum_type,
        .name = try alloc.dupe(u8, ed.name),
        .namespace = try alloc.dupe(u8, "module"),
        .completeness = .complete,
        .origin = .{ .language = "duo", .artifact = file },
        .variants = variants,
        .shape_id = types.enumShapeIdentityHash(try types.enumShapeFromAst(ed, alloc)),
        .contract = .{
            .origin_language = "duo",
            .semantic_completeness = .complete,
            .abi_completeness = .complete,
            .layout_completeness = .complete,
        },
    });
}

fn appendFunctionEntity(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(Entity),
    file: []const u8,
    fd: *const ast.FuncDecl,
) !void {
    const fb = &fd.func;
    var params = try alloc.alloc(Param, fb.params.len);
    errdefer alloc.free(params);
    for (fb.params, 0..) |p, i| {
        params[i] = .{
            .name = try alloc.dupe(u8, p.name),
            .type_name = try typeLabel(alloc, p.typ),
        };
    }
    const ret_name = try typeLabel(alloc, fb.ret_type);
    const fn_name = fd.path[fd.path.len - 1];
    const knowledge = semantic_algebra.knowledgeOfType(try types.resolve(fb.ret_type, null, alloc));

    try list.append(alloc, .{
        .id = try entityId(alloc, .function, fn_name),
        .kind = .function,
        .name = try alloc.dupe(u8, fn_name),
        .namespace = try alloc.dupe(u8, "module"),
        .completeness = if (fb.ret_type == .inferred) .partial else .complete,
        .origin = .{ .language = "duo", .artifact = file },
        .params = params,
        .return_type = ret_name,
        .abi = .{ .calling_convention = "duo-native", .pass_by = "target-default" },
        .contract = .{
            .origin_language = "duo",
            .semantic_completeness = if (fb.ret_type == .inferred) .partial else .complete,
            .abi_completeness = if (knowledge.dominates(.native)) .complete else .partial,
            .layout_completeness = .unknown,
        },
    });
}

fn cmpEntityId(_: void, a: Entity, b: Entity) bool {
    return std.mem.order(u8, a.id, b.id) == .lt;
}

/// Export a type-checked native Duo module into SIM v0 (Phase 1 / Workstream 3).
pub fn exportNativeModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    file: []const u8,
) !Snapshot {
    const owned_file = try alloc.dupe(u8, file);
    var list: std.ArrayListUnmanaged(Entity) = .empty;
    errdefer {
        var snap = Snapshot{ .file = owned_file, .entities = list.items };
        snap.deinit(alloc);
    }

    for (mod.body.stmts) |*stmt| {
        switch (stmt.*) {
            .alias_def => |*ad| {
                if (ad.type_params != null) continue;
                if (ad.target) |tgt| {
                    const rt = try types.resolve(tgt, null, alloc);
                    try appendRecordEntity(alloc, &list, owned_file, ad.name, rt, ad.attributes);
                } else if (ad.fields.len > 0) {
                    var fields = try alloc.alloc(types.FieldType, ad.fields.len);
                    defer alloc.free(fields);
                    for (ad.fields, 0..) |f, i| {
                        fields[i] = .{
                            .name = f.name,
                            .typ = try types.resolve(f.typ, null, alloc),
                        };
                    }
                    var rt: types.ResolvedType = .{ .table_type = .{ .fields = fields } };
                    types.applyTableShapeAttrs(&rt, ad.attributes);
                    rt.table_type.storage_class = types.inferStorageClass(
                        fields,
                        false,
                        rt.table_type.storage_class,
                    );
                    try appendRecordEntity(alloc, &list, owned_file, ad.name, rt, ad.attributes);
                }
            },
            .enum_def => |*ed| try appendEnumEntity(alloc, &list, owned_file, ed),
            .func_decl => |*fd| {
                if (fd.path.len != 1 or fd.method or fd.is_local) continue;
                try appendFunctionEntity(alloc, &list, owned_file, fd);
            },
            else => {},
        }
    }

    std.mem.sort(Entity, list.items, {}, cmpEntityId);
    return .{
        .file = owned_file,
        .entities = try list.toOwnedSlice(alloc),
    };
}

pub fn writeSnapshotJson(snap: *const Snapshot, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"file\":\"", .{snap.schema});
    try jsonEscape(w, snap.file);
    try w.print("\",\"entity_count\":{d},\"entities\":[", .{snap.entities.len});
    for (snap.entities, 0..) |ent, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, ent.id);
        try w.print("\",\"kind\":\"{s}\",\"name\":\"", .{ent.kind.name()});
        try jsonEscape(w, ent.name);
        try w.print("\",\"namespace\":\"", .{});
        try jsonEscape(w, ent.namespace);
        try w.print("\",\"completeness\":\"{s}\",\"origin\":{{\"language\":\"", .{ent.completeness.name()});
        try jsonEscape(w, ent.origin.language);
        try w.print("\",\"artifact\":\"", .{});
        try jsonEscape(w, ent.origin.artifact);
        try w.print(
            "\",\"importer\":\"{s}\",\"importer_version\":\"{s}\"}}",
            .{ ent.origin.importer, ent.origin.importer_version },
        );
        if (ent.storage_class) |sc| {
            try w.print(",\"storage_class\":\"", .{});
            try jsonEscape(w, sc);
            try w.print("\"", .{});
        }
        if (ent.shape_id) |sid| try w.print(",\"shape_id\":{d}", .{sid});
        if (ent.why) |why| {
            try w.print(",\"why\":\"", .{});
            try jsonEscape(w, why);
            try w.print("\"", .{});
        }
        if (ent.fields.len > 0) {
            try w.print(",\"fields\":[", .{});
            for (ent.fields, 0..) |f, fi| {
                if (fi > 0) try w.print(",", .{});
                try w.print("{{\"name\":\"", .{});
                try jsonEscape(w, f.name);
                try w.print("\",\"type\":\"", .{});
                try jsonEscape(w, f.type_name);
                try w.print("\"", .{});
                if (f.offset) |off| try w.print(",\"offset\":{d}", .{off});
                try w.print("}}", .{});
            }
            try w.print("]", .{});
        }
        if (ent.variants.len > 0) {
            try w.print(",\"variants\":[", .{});
            for (ent.variants, 0..) |v, vi| {
                if (vi > 0) try w.print(",", .{});
                try w.print("\"", .{});
                try jsonEscape(w, v);
                try w.print("\"", .{});
            }
            try w.print("]", .{});
        }
        if (ent.params.len > 0) {
            try w.print(",\"params\":[", .{});
            for (ent.params, 0..) |p, pi| {
                if (pi > 0) try w.print(",", .{});
                try w.print("{{\"name\":\"", .{});
                try jsonEscape(w, p.name);
                try w.print("\",\"type\":\"", .{});
                try jsonEscape(w, p.type_name);
                try w.print("\"}}", .{});
            }
            try w.print("]", .{});
        }
        if (ent.return_type) |rt| {
            try w.print(",\"return_type\":\"", .{});
            try jsonEscape(w, rt);
            try w.print("\"", .{});
        }
        if (ent.size_bytes) |sz| try w.print(",\"size_bytes\":{d}", .{sz});
        if (ent.align_bytes) |al| try w.print(",\"align_bytes\":{d}", .{al});
        if (ent.abi) |abi| {
            try w.print(",\"abi\":{{\"calling_convention\":\"", .{});
            try jsonEscape(w, abi.calling_convention);
            try w.print("\",\"pass_by\":\"", .{});
            try jsonEscape(w, abi.pass_by);
            try w.print("\"}}", .{});
        }
        try w.print(
            ",\"contract\":{{\"origin_language\":\"{s}\",\"semantic_completeness\":\"{s}\",\"abi_completeness\":\"{s}\",\"layout_completeness\":\"{s}\"}}",
            .{
                ent.contract.origin_language,
                ent.contract.semantic_completeness.name(),
                ent.contract.abi_completeness.name(),
                ent.contract.layout_completeness.name(),
            },
        );
        try w.print("}}", .{});
    }
    try w.print("]}}\n", .{});
}

test "sim: export pass4 Point record deterministically" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
    , "point.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.idol_mode = true;
    try semantic.check_module(&mod);

    var snap = try exportNativeModule(alloc, &mod, "point.id");
    defer snap.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), snap.entities.len);

    const point = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "duo:record:Point")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    const distance2 = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.id, "duo:function:distance2")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;

    try std.testing.expectEqual(@as(usize, 2), point.fields.len);
    try std.testing.expect(point.shape_id != null);
    try std.testing.expect(distance2.return_type != null);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeSnapshotJson(&snap, &aw.writer);
    const j1 = aw.written();
    aw = .init(alloc);
    try writeSnapshotJson(&snap, &aw.writer);
    try std.testing.expectEqualStrings(j1, aw.written());
}
