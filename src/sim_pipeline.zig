//! Canonical SIM export pipeline (native module → graph enrich → abi.specialize).
const std = @import("std");
const ast = @import("ast.zig");
const sim = @import("sim.zig");
const abi_specialize = @import("abi_specialize.zig");
const semantic_graph = @import("graph.zig");
const types = @import("types.zig");

const ShapeIndex = struct {
    tables: std.StringHashMapUnmanaged(semantic_graph.id),
    enums: std.StringHashMapUnmanaged(semantic_graph.id),

    fn deinit(self: *ShapeIndex, alloc: std.mem.Allocator) void {
        self.tables.deinit(alloc);
        self.enums.deinit(alloc);
    }

    fn build(
        graph: *const semantic_graph.SemanticGraph,
        alloc: std.mem.Allocator,
    ) !ShapeIndex {
        var index: ShapeIndex = .{ .tables = .empty, .enums = .empty };
        errdefer index.deinit(alloc);

        const tables = try graph.entitiesOfKind(.table_shape, alloc);
        defer alloc.free(tables);
        for (tables) |record| {
            const node = graph.tableShapeEntity(record) orelse continue;
            const name = node.name orelse continue;
            try index.tables.put(alloc, name, record);
        }

        const enums = try graph.entitiesOfKind(.enum_shape, alloc);
        defer alloc.free(enums);
        for (enums) |descriptor| {
            const node = graph.enumShapeEntity(descriptor) orelse continue;
            const name = node.name orelse continue;
            try index.enums.put(alloc, name, descriptor);
        }
        return index;
    }
};

fn enrichRecordEntity(
    alloc: std.mem.Allocator,
    ent: *sim.Entity,
    graph: *const semantic_graph.SemanticGraph,
    record: semantic_graph.id,
) !void {
    const node = graph.tableShapeEntity(record) orelse return;
    if (node.shape_id) |sid| ent.shape_id = sid;
    if (node.why) |w| {
        if (ent.why) |old| alloc.free(old);
        ent.why = try alloc.dupe(u8, w);
    }
    if (node.storage_class) |sc| {
        const label = types.storageClassName(sc);
        if (ent.storage_class) |old| alloc.free(old);
        ent.storage_class = try alloc.dupe(u8, label);
    }
}

fn enrichEnumEntity(
    ent: *sim.Entity,
    graph: *const semantic_graph.SemanticGraph,
    descriptor: semantic_graph.id,
) void {
    const node = graph.enumShapeEntity(descriptor) orelse return;
    if (node.shape_id) |sid| ent.shape_id = sid;
}

fn enrichSnapshotFromGraph(alloc: std.mem.Allocator, snap: *sim.Snapshot, graph: *const semantic_graph.SemanticGraph) !void {
    var index = try ShapeIndex.build(graph, alloc);
    defer index.deinit(alloc);

    for (snap.entities) |*ent| {
        switch (ent.kind) {
            .record => {
                const record = index.tables.get(ent.name) orelse continue;
                try enrichRecordEntity(alloc, ent, graph, record);
            },
            .enum_type => {
                const descriptor = index.enums.get(ent.name) orelse continue;
                enrichEnumEntity(ent, graph, descriptor);
            },
            else => {},
        }
    }
}

/// Export SIM v0 with optional semantic-graph enrichment (shape_id, why, storage_class).
pub fn exportInterchangeWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    file: []const u8,
    graph: ?*const semantic_graph.SemanticGraph,
) !sim.Snapshot {
    var snap = try sim.exportNativeModule(alloc, mod, file);
    errdefer snap.deinit(alloc);
    if (graph) |g| try enrichSnapshotFromGraph(alloc, &snap, g);
    try abi_specialize.specializeSnapshot(alloc, &snap);
    return snap;
}

/// Export a type-checked module to SIM v0 with shared ABI specialization applied.
/// Prefer `exportInterchangeWithGraph` when a lifted graph is available.
pub fn exportInterchangeSnapshot(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    file: []const u8,
) !sim.Snapshot {
    return exportInterchangeWithGraph(alloc, mod, file, null);
}

test "sim_pipeline: exportInterchangeSnapshot applies abi.specialize" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: { x: f64, y: f64 }
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

    var snap = try exportInterchangeSnapshot(alloc, &mod, "point.id");
    defer snap.deinit(alloc);

    for (snap.entities) |ent| {
        if (std.mem.eql(u8, ent.id, "duo:function:distance2")) {
            try std.testing.expectEqual(sim.Completeness.complete, ent.contract.abi_completeness);
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "sim_pipeline: graph enrichment attaches shape_id to Point" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: { x: f64, y: f64 }
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

    var snap_plain = try exportInterchangeSnapshot(alloc, &mod, "point.id");
    defer snap_plain.deinit(alloc);
    var snap_graph = try exportInterchangeWithGraph(alloc, &mod, "point.id", &graph);
    defer snap_graph.deinit(alloc);

    const records = try graph.entitiesOfKind(.table_shape, alloc);
    defer alloc.free(records);
    var point_record: ?semantic_graph.id = null;
    for (records) |record| {
        const node = graph.tableShapeEntity(record) orelse continue;
        if (std.mem.eql(u8, node.name.?, "Point")) {
            point_record = record;
            break;
        }
    }
    const record = point_record orelse return error.TestExpectedEqual;
    const graph_node = graph.tableShapeEntity(record) orelse return error.TestExpectedEqual;
    try std.testing.expect(graph_node.shape_id != null);

    const point_graph = blk: {
        for (snap_graph.entities) |ent| {
            if (std.mem.eql(u8, ent.name, "Point")) break :blk ent;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;

    try std.testing.expect(point_graph.shape_id != null);
    try std.testing.expectEqual(graph_node.shape_id.?, point_graph.shape_id.?);
    try std.testing.expect(point_graph.why != null);
}
