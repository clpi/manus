//! Pass 8 — refresh persistent realization cache during compile/realize.
const std = @import("std");
const ast = @import("ast.zig");
const realization = @import("realization.zig");
const persistent_semantic_state = @import("persistent_semantic_state.zig");
const semantic_graph = @import("semantic_graph.zig");
const semantic_invalidation = @import("semantic_invalidation.zig");

pub const COMPILER_VERSION = "duo-dev";
pub const TRANSFORM_VERSION = realization.DEFAULT_TRANSFORM_VERSION;

pub const RefreshResult = struct {
    realizations: realization.ModuleRealizations,
    state: persistent_semantic_state.State,
    audits: []persistent_semantic_state.ReuseAudit,
    invalidation: semantic_invalidation.Graph,

    pub fn deinit(self: *RefreshResult, alloc: std.mem.Allocator) void {
        self.realizations.deinit(alloc);
        self.state.deinit(alloc);
        for (self.audits) |*a| a.deinit(alloc);
        alloc.free(self.audits);
        self.invalidation.deinit(alloc);
    }
};

fn recordNameFromEntity(entity_id: []const u8) ?[]const u8 {
    const prefix = "duo:record:";
    if (!std.mem.startsWith(u8, entity_id, prefix)) return null;
    return entity_id[prefix.len..];
}

pub fn refreshRealizationCache(
    alloc: std.mem.Allocator,
    io: std.Io,
    graph: *const semantic_graph.SemanticGraph,
    src_path: []const u8,
    target: []const u8,
) !RefreshResult {
    var realizations = try realization.buildFromGraph(alloc, graph, src_path);
    errdefer realizations.deinit(alloc);

    var state = try persistent_semantic_state.loadFromPath(alloc, io, persistent_semantic_state.DEFAULT_CACHE_PATH);
    errdefer state.deinit(alloc);

    var audits: std.ArrayListUnmanaged(persistent_semantic_state.ReuseAudit) = .empty;
    errdefer {
        for (audits.items) |*a| a.deinit(alloc);
        audits.deinit(alloc);
    }

    var live_ids: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer live_ids.deinit(alloc);

    for (realizations.variables) |var_| {
        const sel = var_.selected() orelse continue;
        const record_name = recordNameFromEntity(var_.subject_entity) orelse continue;
        try live_ids.append(alloc, var_.subject_entity);
        const fp = try realization.fingerprintForRecordEntity(alloc, graph, record_name, target, TRANSFORM_VERSION);
        const row = try persistent_semantic_state.mergeRealizationEntry(
            alloc,
            &state,
            var_.subject_entity,
            fp,
            sel.representation,
            COMPILER_VERSION,
            target,
            TRANSFORM_VERSION,
        );
        try audits.append(alloc, row);
    }

    const removal = try semantic_invalidation.invalidateRemovedEntities(alloc, &state, live_ids.items);
    var audit_edges = try semantic_invalidation.edgesFromReuseAudits(alloc, audits.items);
    errdefer audit_edges.deinit(alloc);

    var all_edges: std.ArrayListUnmanaged(semantic_invalidation.Edge) = .empty;
    errdefer {
        for (all_edges.items) |*e| e.deinit(alloc);
        all_edges.deinit(alloc);
    }
    try all_edges.appendSlice(alloc, removal.edges);
    alloc.free(removal.edges);
    try all_edges.appendSlice(alloc, audit_edges.edges);
    alloc.free(audit_edges.edges);

    try persistent_semantic_state.saveToPath(alloc, io, persistent_semantic_state.DEFAULT_CACHE_PATH, &state);

    return .{
        .realizations = realizations,
        .state = state,
        .audits = try audits.toOwnedSlice(alloc),
        .invalidation = .{ .edges = try all_edges.toOwnedSlice(alloc) },
    };
}

pub fn refreshFromCheckedModule(
    alloc: std.mem.Allocator,
    io: std.Io,
    mod: *const ast.Module,
    src_path: []const u8,
    target: []const u8,
) !RefreshResult {
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(mod, src_path);
    return try refreshRealizationCache(alloc, io, &graph, src_path, target);
}

test "compile_semantic_cache: second refresh reuses entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
        \\end
    ;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var lex = Lexer.init(src, "point.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);

    const cache_path = ".duo/cache/semantic/state.json";
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, cache_path) catch {};

    var r1 = try refreshFromCheckedModule(alloc, io, &mod, "point.duo", "native");
    defer r1.deinit(alloc);
    try std.testing.expect(r1.audits.len >= 1);
    try std.testing.expect(r1.audits[0].action == .fresh);

    var r2 = try refreshFromCheckedModule(alloc, io, &mod, "point.duo", "native");
    defer r2.deinit(alloc);
    try std.testing.expect(r2.audits[0].action == .reused);
}
