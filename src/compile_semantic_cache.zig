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

fn combineInvalidationGraphs(
    alloc: std.mem.Allocator,
    first: *semantic_invalidation.Graph,
    second: *semantic_invalidation.Graph,
) !semantic_invalidation.Graph {
    if (first.edges.len == 0) {
        first.deinit(alloc);
        first.edges = &.{};
        const edges = second.edges;
        second.edges = &.{};
        return .{ .edges = edges };
    }
    if (second.edges.len == 0) {
        second.deinit(alloc);
        second.edges = &.{};
        const edges = first.edges;
        first.edges = &.{};
        return .{ .edges = edges };
    }

    const first_len = first.edges.len;
    const combined_len = try std.math.add(usize, first_len, second.edges.len);
    const edges = try alloc.realloc(first.edges, combined_len);
    first.edges = &.{};
    @memcpy(edges[first_len..], second.edges);
    alloc.free(second.edges);
    second.edges = &.{};
    return .{ .edges = edges };
}

fn mergeAudit(
    alloc: std.mem.Allocator,
    state: *persistent_semantic_state.State,
    audits: *std.ArrayListUnmanaged(persistent_semantic_state.ReuseAudit),
    entity_id: []const u8,
    fingerprint: u64,
    artifact: []const u8,
    target: []const u8,
) !void {
    try audits.ensureUnusedCapacity(alloc, 1);
    const row = try persistent_semantic_state.mergeRealizationEntry(
        alloc,
        state,
        entity_id,
        fingerprint,
        artifact,
        COMPILER_VERSION,
        target,
        TRANSFORM_VERSION,
    );
    audits.appendAssumeCapacity(row);
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
    defer live_ids.deinit(alloc);

    for (realizations.variables) |var_| {
        const sel = var_.selected() orelse continue;
        const record_name = recordNameFromEntity(var_.subject_entity) orelse continue;
        try live_ids.append(alloc, var_.subject_entity);
        const fp = try realization.fingerprintForRecordEntity(alloc, graph, record_name, target, TRANSFORM_VERSION);
        try mergeAudit(
            alloc,
            &state,
            &audits,
            var_.subject_entity,
            fp,
            sel.representation,
            target,
        );
    }

    const owned_audits = try audits.toOwnedSlice(alloc);
    errdefer {
        for (owned_audits) |*audit| audit.deinit(alloc);
        alloc.free(owned_audits);
    }

    var removal = try semantic_invalidation.invalidateRemovedEntities(alloc, &state, live_ids.items);
    defer removal.deinit(alloc);
    var audit_edges = try semantic_invalidation.edgesFromReuseAudits(alloc, owned_audits);
    defer audit_edges.deinit(alloc);
    var invalidation = try combineInvalidationGraphs(alloc, &removal, &audit_edges);
    errdefer invalidation.deinit(alloc);

    try persistent_semantic_state.saveToPath(alloc, io, persistent_semantic_state.DEFAULT_CACHE_PATH, &state);

    return .{
        .realizations = realizations,
        .state = state,
        .audits = owned_audits,
        .invalidation = invalidation,
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

fn expectEdgeOwnershipUnchanged(
    expected: semantic_invalidation.Edge,
    actual: semantic_invalidation.Edge,
) !void {
    try std.testing.expect(expected.subject_entity.ptr == actual.subject_entity.ptr);
    try std.testing.expectEqual(expected.subject_entity.len, actual.subject_entity.len);
    try std.testing.expect(expected.affected_entity.ptr == actual.affected_entity.ptr);
    try std.testing.expectEqual(expected.affected_entity.len, actual.affected_entity.len);
    try std.testing.expectEqual(expected.kind, actual.kind);
    try std.testing.expect(expected.reason.ptr == actual.reason.ptr);
    try std.testing.expectEqual(expected.reason.len, actual.reason.len);
}

fn combineInvalidationAllocationProbe(alloc: std.mem.Allocator) !void {
    const first_audits = [_]persistent_semantic_state.ReuseAudit{.{
        .entity_id = "duo:record:Point",
        .action = .invalidated,
        .reason = "semantic fingerprint changed",
        .artifact = "native_aggregate",
    }};
    const second_audits = [_]persistent_semantic_state.ReuseAudit{.{
        .entity_id = "duo:record:Vector",
        .action = .invalidated,
        .reason = "target changed",
        .artifact = "native_struct",
    }};
    var first = try semantic_invalidation.edgesFromReuseAudits(alloc, &first_audits);
    defer first.deinit(alloc);
    var second = try semantic_invalidation.edgesFromReuseAudits(alloc, &second_audits);
    defer second.deinit(alloc);

    const expected_first_ptr = first.edges.ptr;
    const expected_second_ptr = second.edges.ptr;
    const expected_first = first.edges[0];
    const expected_second = second.edges[0];
    var combined = combineInvalidationGraphs(alloc, &first, &second) catch |err| {
        try std.testing.expect(first.edges.ptr == expected_first_ptr);
        try std.testing.expect(second.edges.ptr == expected_second_ptr);
        try std.testing.expectEqual(@as(usize, 1), first.edges.len);
        try std.testing.expectEqual(@as(usize, 1), second.edges.len);
        try expectEdgeOwnershipUnchanged(expected_first, first.edges[0]);
        try expectEdgeOwnershipUnchanged(expected_second, second.edges[0]);
        return err;
    };
    defer combined.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 0), first.edges.len);
    try std.testing.expectEqual(@as(usize, 0), second.edges.len);
    try std.testing.expectEqual(@as(usize, 2), combined.edges.len);
    try std.testing.expectEqualStrings(first_audits[0].entity_id, combined.edges[0].subject_entity);
    try std.testing.expectEqualStrings(second_audits[0].entity_id, combined.edges[1].subject_entity);
}

fn mergeAuditAllocationProbe(alloc: std.mem.Allocator) !void {
    var state: persistent_semantic_state.State = .{ .entries = &.{} };
    defer state.deinit(alloc);
    try persistent_semantic_state.appendEntry(
        alloc,
        &state,
        "duo:record:Point",
        0xdef,
        .source_derived,
        "native_struct",
        COMPILER_VERSION,
        "native",
        TRANSFORM_VERSION,
    );

    var audits: std.ArrayListUnmanaged(persistent_semantic_state.ReuseAudit) = .empty;
    defer {
        for (audits.items) |*audit| audit.deinit(alloc);
        audits.deinit(alloc);
    }

    const expected_entries = state.entries.ptr;
    const expected_entity = state.entries[0].entity_id.ptr;
    const expected_artifact = state.entries[0].artifact.ptr;
    mergeAudit(
        alloc,
        &state,
        &audits,
        "duo:record:Point",
        0xabc,
        "native_aggregate",
        "native",
    ) catch |err| {
        try std.testing.expect(state.entries.ptr == expected_entries);
        try std.testing.expectEqual(@as(usize, 1), state.entries.len);
        try std.testing.expect(state.entries[0].entity_id.ptr == expected_entity);
        try std.testing.expectEqual(@as(u64, 0xdef), state.entries[0].fingerprint);
        try std.testing.expect(state.entries[0].artifact.ptr == expected_artifact);
        try std.testing.expectEqualStrings("native_struct", state.entries[0].artifact);
        try std.testing.expectEqual(@as(usize, 0), audits.items.len);
        return err;
    };

    try std.testing.expectEqual(@as(usize, 1), audits.items.len);
    try std.testing.expectEqual(persistent_semantic_state.AuditAction.invalidated, audits.items[0].action);
    try std.testing.expectEqual(@as(u64, 0xabc), state.entries[0].fingerprint);
    try std.testing.expectEqualStrings("native_aggregate", state.entries[0].artifact);
}

test "compile_semantic_cache: invalidation graph ownership transfer is transactional" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, combineInvalidationAllocationProbe, .{});
}

test "compile_semantic_cache: state merge and audit publication are transactional" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mergeAuditAllocationProbe, .{});
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
