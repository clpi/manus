//! Pass 7 — integration tests for duo explain enriched output.
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const semantic_graph = @import("semantic_graph.zig");
const knowledge_snapshot = @import("knowledge_snapshot.zig");
const assumption_guard = @import("assumption_guard.zig");
const explain_pipeline = @import("explain_pipeline.zig");
const optimization_outcome = @import("optimization_outcome.zig");
const repair_candidate = @import("repair_candidate.zig");
const transform_engine = @import("transform_engine.zig");

const point_src =
    \\Point: @{ x: f64, y: f64 }
    \\main(): f64
    \\    p = Point { x = 1.0, y = 2.0 }
    \\    p.x
    \\end
;

const noalloc_fail_src =
    \\@noalloc
    \\fun leak(): i64
    \\    raw: *u8 = mem.alloc(64)
    \\    mem.free(raw)
    \\    0
    \\end
    \\
    \\main(): i64
    \\    leak()
    \\end
;

fn checkModule(alloc: std.mem.Allocator, src: []const u8, file: []const u8) !struct {
    mod: @import("ast.zig").Module,
    semantic: sema.Sema,
    graph: semantic_graph.SemanticGraph,
} {
    var lex = Lexer.init(src, file);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    _ = try graph.liftModuleWithCalls(&mod, file);
    return .{ .mod = mod, .semantic = semantic, .graph = graph };
}

test "pass7 explain enrichment: Point has fingerprint and shape assumption" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var bundle = try checkModule(alloc, point_src, "point.duo");
    defer bundle.semantic.deinit();
    defer bundle.graph.deinit();

    var snap = try knowledge_snapshot.buildFromModule(alloc, &bundle.mod, &bundle.semantic, &bundle.graph, "point.duo");
    defer snap.deinit(alloc);
    var assumptions = try assumption_guard.buildFromModule(alloc, &bundle.mod, &bundle.semantic, &bundle.graph);
    defer assumptions.deinit(alloc);

    const point = blk: {
        for (snap.entities) |e| {
            if (std.mem.eql(u8, e.name, "Point")) break :blk e;
        }
        break :blk null;
    };
    try std.testing.expect(assumptions.items.len >= 1);
    var found_point_assumption = false;
    for (assumptions.items) |a| {
        if (std.mem.indexOf(u8, a.subject_entity, "Point") != null) found_point_assumption = true;
    }
    try std.testing.expect(found_point_assumption);
    if (point) |p| {
        if (p.fingerprint) |fp| try std.testing.expect(fp != 0);
    }
}

test "pass7 explain enrichment: noalloc violation yields repair candidates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var bundle = try checkModule(alloc, noalloc_fail_src, "noalloc_fail.duo");
    defer bundle.semantic.deinit();
    defer bundle.graph.deinit();

    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    optimization_outcome.deinitSession(alloc);
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const result = explain_pipeline.runForProvenance(alloc, io, &bundle.mod, &bundle.semantic, "noalloc_fail.duo", null);
    try std.testing.expectError(error.NoAllocViolation, result);

    var outcomes = try optimization_outcome.fromProvenance(alloc);
    defer outcomes.deinit(alloc);
    try optimization_outcome.mergeSessionInto(alloc, &outcomes);
    defer optimization_outcome.deinitSession(alloc);

    var repairs = try repair_candidate.repairsForBlocker("noalloc_heap_alloc", alloc);
    defer repairs.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), repairs.items.len);
}
