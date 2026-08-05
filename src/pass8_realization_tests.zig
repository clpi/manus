//! Pass 8 — integration tests for realization planning and persistent evidence.
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const semantic_graph = @import("semantic_graph.zig");
const realization = @import("realization.zig");
const persistent_semantic_state = @import("persistent_semantic_state.zig");
const semantic_fingerprint = @import("semantic_fingerprint.zig");
const compile_semantic_cache = @import("compile_semantic_cache.zig");
const semantic_invalidation = @import("semantic_invalidation.zig");

test "pass8: module plan selects native aggregate for sealed Point" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
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

    var m = try realization.buildFromGraph(alloc, &graph, "point.duo");
    defer m.deinit(alloc);
    try std.testing.expect(m.variables.len >= 1);
    const var_ = m.variables[0];
    const sel = var_.selected() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("repr.native_aggregate", sel.id);
    try std.testing.expect(var_.candidates.len >= 2);
    try std.testing.expect(var_.selected_index != null);
}

test "pass8: persistent reuse rejects fingerprint drift" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var entry = persistent_semantic_state.Entry{
        .entity_id = try alloc.dupe(u8, "duo:record:Point"),
        .fingerprint = 0x1111,
        .kind = .source_derived,
        .artifact = try alloc.dupe(u8, "native_aggregate"),
        .compiler_version = try alloc.dupe(u8, "duo-dev"),
        .target = try alloc.dupe(u8, "native"),
        .transform_version = try alloc.dupe(u8, "transform-registry-v0"),
        .stale = false,
    };
    defer entry.deinit(alloc);
    var d = try persistent_semantic_state.canReuse(alloc, &entry, 0x2222, "duo-dev", "native", "transform-registry-v0");
    defer d.deinit(alloc);
    try std.testing.expect(!d.allowed);
    try std.testing.expect(std.mem.indexOf(u8, d.reason, "fingerprint") != null);
}

test "pass8: fingerprint changes when shape identity changes" {
    const fp_a = semantic_fingerprint.compute(.{
        .entity_id = "duo:record:Point",
        .target = "native",
        .transform_version = "transform-registry-v0",
        .descriptor_deps = "shape:aaa",
    });
    const fp_b = semantic_fingerprint.compute(.{
        .entity_id = "duo:record:Point",
        .target = "native",
        .transform_version = "transform-registry-v0",
        .descriptor_deps = "shape:bbb",
    });
    try std.testing.expect(fp_a != fp_b);
}

test "pass8: merge reports invalidated on fingerprint drift" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = persistent_semantic_state.State{ .entries = &.{} };
    var a1 = try persistent_semantic_state.mergeRealizationEntry(
        alloc, &state, "duo:record:Point", 0xabc, "native_aggregate", "duo-dev", "native", "transform-registry-v0",
    );
    defer a1.deinit(alloc);
    try std.testing.expect(a1.action == .fresh);
    var a2 = try persistent_semantic_state.mergeRealizationEntry(
        alloc, &state, "duo:record:Point", 0xdef, "native_aggregate", "duo-dev", "native", "transform-registry-v0",
    );
    defer a2.deinit(alloc);
    try std.testing.expect(a2.action == .invalidated);
    try std.testing.expect(std.mem.indexOf(u8, a2.reason, "fingerprint") != null);
}

test "pass8: compile cache refresh reuses then invalidates on shape drift" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    const cache_path = persistent_semantic_state.DEFAULT_CACHE_PATH;
    cwd.deleteFile(io, cache_path) catch {};

    const src_v1 =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
        \\end
    ;
    const src_v2 =
        \\Point: @{ x: f64, y: f64, z: f64 }
        \\main(): i64
        \\    0
        \\end
    ;

    const files = [_][]const u8{ "point_v1.duo", "point_v2.duo" };
    const sources = [_][]const u8{ src_v1, src_v2 };
    for (files, sources, 0..) |file_name, src, i| {
        var lex = Lexer.init(src, file_name);
        var parser = Parser.init(&lex, alloc);
        parser.duo_mode = true;
        var mod = try parser.parse_module();
        var semantic = sema.Sema.init(alloc);
        defer semantic.deinit();
        semantic.duo_mode = true;
        try semantic.check_module(&mod);
        var refresh = try compile_semantic_cache.refreshFromCheckedModule(alloc, io, &mod, file_name, "native");
        defer refresh.deinit(alloc);
        if (i == 0) {
            try std.testing.expect(refresh.audits[0].action == .fresh);
        } else {
            try std.testing.expect(refresh.audits[0].action == .invalidated);
            try std.testing.expect(refresh.invalidation.edges.len >= 1);
        }
    }
}

test "pass8: entity removal marks stale cache entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = persistent_semantic_state.State{ .entries = &.{} };
    try persistent_semantic_state.appendEntry(
        alloc, &state, "duo:record:Removed", 0x1, .source_derived, "native_aggregate", "duo-dev", "native", "transform-registry-v0",
    );
    var g = try semantic_invalidation.invalidateRemovedEntities(alloc, &state, &.{});
    defer g.deinit(alloc);
    try std.testing.expect(g.edges.len == 1);
    try std.testing.expect(state.entries[0].stale);
}
