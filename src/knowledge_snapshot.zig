//! — immutable knowledge snapshots at compiler phases.
//!
//! Snapshots are projections of canonical compiler facts (not a second semantic graph).
const std = @import("std");
const sema = @import("sema.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const semantic_graph = @import("semantic_graph.zig");
const types = @import("types.zig");

pub const SCHEMA_VERSION = "knowledge-snapshot-v1";

/// Compiler phase when the snapshot was taken.
pub const Phase = enum(u8) {
    after_binding,
    after_sema,
    after_graph_lift,
    after_staging,
    after_specialization,
    after_representation,
    after_optimization,
    after_lowering,

    pub fn name(self: Phase) []const u8 {
        return switch (self) {
            .after_binding => "after_binding",
            .after_sema => "after_sema",
            .after_graph_lift => "after_graph_lift",
            .after_staging => "after_staging",
            .after_specialization => "after_specialization",
            .after_representation => "after_representation",
            .after_optimization => "after_optimization",
            .after_lowering => "after_lowering",
        };
    }
};

pub const EntityKind = enum(u8) {
    binding,
    function,
    record,
    enum_type,

    pub fn name(self: EntityKind) []const u8 {
        return switch (self) {
            .binding => "binding",
            .function => "function",
            .record => "record",
            .enum_type => "enum_type",
        };
    }
};

pub const EntitySnapshot = struct {
    /// Exact identity in the registered graph incarnation. `name` below is a
    /// human projection and cannot recover this reference.
    entity: semantic_graph.EntityRef,
    name: []const u8,
    kind: EntityKind,
    phase: Phase,
    knowledge: semantic_algebra.KnowledgeLevel,
    storage_class: ?types.StorageClass = null,
    shape_id: ?u64 = null,
    why: ?[]const u8 = null,
    representation: ?[]const u8 = null,
    effects: ?[]const u8 = null,

    pub fn deinit(self: *EntitySnapshot, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        if (self.why) |w| alloc.free(w);
        if (self.representation) |r| alloc.free(r);
        if (self.effects) |e| alloc.free(e);
    }
};

pub const ModuleSnapshots = struct {
    file: []const u8,
    incarnation: semantic_graph.incarnation,
    entities: []EntitySnapshot,

    pub fn deinit(self: *ModuleSnapshots, alloc: std.mem.Allocator) void {
        for (self.entities) |*e| e.deinit(alloc);
        alloc.free(self.entities);
        alloc.free(self.file);
    }
};

fn appendRecordFromGraph(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(EntitySnapshot),
    graph: *const semantic_graph.SemanticGraph,
    record: semantic_graph.id,
    phase: Phase,
) !void {
    const node = graph.tableShapeEntity(record) orelse return;
    const name = node.name orelse return;
    const why = if (node.why) |w| try alloc.dupe(u8, w) else null;
    errdefer if (why) |w| alloc.free(w);
    try out.append(alloc, .{
        .entity = try graph.entityRef(record),
        .name = try alloc.dupe(u8, name),
        .kind = .record,
        .phase = phase,
        .knowledge = if (node.storage_class) |sc| semantic_algebra.KnowledgeLevel.fromStorageClass(sc) else .stable,
        .storage_class = node.storage_class,
        .shape_id = node.shape_id,
        .why = why,
        .representation = if (node.storage_class) |sc| try alloc.dupe(u8, types.storageClassName(sc)) else null,
        .effects = null,
    });
}

/// Build snapshots from sema results and the semantic graph.
pub fn buildFromModule(
    alloc: std.mem.Allocator,
    semantic: *const sema.Sema,
    graph: *const semantic_graph.SemanticGraph,
    file: []const u8,
) !ModuleSnapshots {
    const incarnation = graph.incarnation_coordinate orelse return error.GraphNotRegistered;
    var entities: std.ArrayListUnmanaged(EntitySnapshot) = .empty;
    errdefer {
        for (entities.items) |*e| e.deinit(alloc);
        entities.deinit(alloc);
    }

    for (graph.nodes.items, 0..) |node, i| {
        if (!semantic_graph.SemanticGraph.atModuleScope(graph, &node)) continue;
        if (graph.callable(@intCast(i))) {
            const fname = node.name orelse continue;
            const kn = semantic.symbolKnowledge(fname);
            try entities.append(alloc, .{
                .entity = try graph.entityRef(@intCast(i)),
                .name = try alloc.dupe(u8, fname),
                .kind = .function,
                .phase = .after_sema,
                .knowledge = kn,
                .representation = if (kn == .native) try alloc.dupe(u8, "native") else try alloc.dupe(u8, "dynamic"),
                .effects = null,
            });
            continue;
        }
        if (!graph.hasTableDescriptorFacts(@intCast(i))) continue;
        if (node.name == null) continue;
        try appendRecordFromGraph(alloc, &entities, graph, @intCast(i), .after_graph_lift);
    }

    return .{
        .file = try alloc.dupe(u8, file),
        .incarnation = incarnation,
        .entities = try entities.toOwnedSlice(alloc),
    };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeJson(snap: *const ModuleSnapshots, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"incarnation\":{d},\"file\":\"", .{
        SCHEMA_VERSION,
        snap.incarnation,
    });
    try jsonEscape(w, snap.file);
    try w.print("\",\"entity_count\":{d},\"entities\":[", .{snap.entities.len});
    for (snap.entities, 0..) |ent, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"entity\":{{\"incarnation\":{d},\"coordinate\":{d}}},\"name\":\"",
            .{ ent.entity.incarnation, ent.entity.entity },
        );
        try jsonEscape(w, ent.name);
        try w.print(
            "\",\"kind\":\"{s}\",\"phase\":\"{s}\",\"knowledge\":\"{s}\"",
            .{ ent.kind.name(), ent.phase.name(), ent.knowledge.name() },
        );
        if (ent.storage_class) |sc| {
            try w.print(",\"storage_class\":\"{s}\"", .{types.storageClassName(sc)});
        }
        if (ent.shape_id) |sid| {
            try w.print(",\"shape_id\":{d}", .{sid});
        }
        if (ent.why) |why| {
            try w.print(",\"why\":\"", .{});
            try jsonEscape(w, why);
            try w.print("\"", .{});
        }
        if (ent.representation) |rep| {
            try w.print(",\"representation\":\"", .{});
            try jsonEscape(w, rep);
            try w.print("\"", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

/// Standalone CLI export (includes trailing newline).
pub fn writeJsonLine(snap: *const ModuleSnapshots, w: *std.Io.Writer) !void {
    try writeJson(snap, w);
    try w.print("\n", .{});
}

test "knowledge_snapshot: graph input is required" {
    const build_info = @typeInfo(@TypeOf(buildFromModule)).@"fn";
    try std.testing.expectEqual(@as(usize, 4), build_info.param_types.len);
    try std.testing.expect(build_info.param_types[2].? == *const semantic_graph.SemanticGraph);
}

test "knowledge_snapshot: native Point record from graph lift" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
    ;
    var lex = Lexer.init(src, "point.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.idol_mode = true;
    try semantic.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.id");
    var history = semantic_graph.History.init(alloc);
    defer history.deinit();
    const incarnation = try history.register(&graph, .{});

    var snap = try buildFromModule(alloc, &semantic, &graph, "point.id");
    defer snap.deinit(alloc);

    const point = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.name, "Point")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;

    try std.testing.expectEqual(EntityKind.record, point.kind);
    try std.testing.expectEqual(Phase.after_graph_lift, point.phase);
    try std.testing.expect(point.shape_id != null);
    try std.testing.expectEqual(incarnation, point.entity.incarnation);
    try std.testing.expectEqualStrings("Point", graph.get(point.entity.entity).?.name.?);

    const distance = blk: {
        for (snap.entities) |ent| {
            if (std.mem.eql(u8, ent.name, "distance2")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(EntityKind.function, distance.kind);
    try std.testing.expectEqual(incarnation, distance.entity.incarnation);

    var json: std.Io.Writer.Allocating = .init(alloc);
    defer json.deinit();
    try writeJson(&snap, &json.writer);
    try std.testing.expect(std.mem.indexOf(u8, json.written(), "\"entity\":{\"incarnation\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.written(), "\"entity_id\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, json.written(), "\"fingerprint\":") == null);
}

test "knowledge_snapshot: refuses unregistered graph identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try std.testing.expectError(
        error.GraphNotRegistered,
        buildFromModule(alloc, &semantic, &graph, "unregistered.id"),
    );
}
