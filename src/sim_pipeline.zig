//! Pass 5/6 — canonical SIM export pipeline (native module → graph enrich → abi.specialize).
const std = @import("std");
const ast = @import("ast.zig");
const sim = @import("sim.zig");
const abi_specialize = @import("abi_specialize.zig");
const semantic_graph = @import("semantic_graph.zig");
const types = @import("types.zig");

fn enrichSnapshotFromGraph(alloc: std.mem.Allocator, snap: *sim.Snapshot, graph: *const semantic_graph.SemanticGraph) !void {
    for (snap.entities) |*ent| {
        switch (ent.kind) {
            .record => {
                const node = graph.findTableShape(ent.name) orelse continue;
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
            },
            .enum_type => {
                const node = graph.findEnumShape(ent.name) orelse continue;
                if (node.shape_id) |sid| ent.shape_id = sid;
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

    var snap = try exportInterchangeSnapshot(alloc, &mod, "point.duo");
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
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
    ;
    var lex = Lexer.init(src, "point.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.duo");

    var snap_plain = try exportInterchangeSnapshot(alloc, &mod, "point.duo");
    defer snap_plain.deinit(alloc);
    var snap_graph = try exportInterchangeWithGraph(alloc, &mod, "point.duo", &graph);
    defer snap_graph.deinit(alloc);

    const graph_node = graph.findTableShape("Point") orelse return error.TestExpectedEqual;
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
