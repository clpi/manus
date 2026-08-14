//! — bounded invalidation edges for persistent semantic evidence (P8-08 seed).
const std = @import("std");
const persistent_semantic_state = @import("persistent_semantic_state.zig");

pub const SCHEMA_VERSION = "semantic-invalidation-v0";

pub const EdgeKind = enum(u8) {
    invalidates,
    fingerprint_change,
    entity_removed,
    compiler_version_change,
    target_change,

    pub fn name(self: EdgeKind) []const u8 {
        return @tagName(self);
    }
};

pub const Edge = struct {
    subject_entity: []const u8,
    affected_entity: []const u8,
    kind: EdgeKind,
    reason: []const u8,

    pub fn deinit(self: *Edge, alloc: std.mem.Allocator) void {
        alloc.free(self.subject_entity);
        alloc.free(self.affected_entity);
        alloc.free(self.reason);
    }
};

pub const Graph = struct {
    edges: []Edge,

    pub fn deinit(self: *Graph, alloc: std.mem.Allocator) void {
        for (self.edges) |*e| e.deinit(alloc);
        alloc.free(self.edges);
    }
};

fn duplicateEdge(
    alloc: std.mem.Allocator,
    subject_entity: []const u8,
    affected_entity: []const u8,
    kind: EdgeKind,
    reason: []const u8,
) !Edge {
    const owned_subject = try alloc.dupe(u8, subject_entity);
    errdefer alloc.free(owned_subject);
    const owned_affected = try alloc.dupe(u8, affected_entity);
    errdefer alloc.free(owned_affected);
    const owned_reason = try alloc.dupe(u8, reason);
    errdefer alloc.free(owned_reason);
    return .{
        .subject_entity = owned_subject,
        .affected_entity = owned_affected,
        .kind = kind,
        .reason = owned_reason,
    };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeJson(g: *const Graph, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"edge_count\":{d},\"edges\":[", .{ SCHEMA_VERSION, g.edges.len });
    for (g.edges, 0..) |e, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"subject_entity\":\"", .{});
        try jsonEscape(w, e.subject_entity);
        try w.print("\",\"affected_entity\":\"", .{});
        try jsonEscape(w, e.affected_entity);
        try w.print("\",\"kind\":\"{s}\",\"reason\":\"", .{e.kind.name()});
        try jsonEscape(w, e.reason);
        try w.print("\"}}", .{});
    }
    try w.print("]}}", .{});
}

/// Mark cache entries absent from the current module plan as stale; record removal edges.
pub fn invalidateRemovedEntities(
    alloc: std.mem.Allocator,
    state: *persistent_semantic_state.State,
    live_entity_ids: []const []const u8,
) !Graph {
    var edges: std.ArrayListUnmanaged(Edge) = .empty;
    errdefer {
        for (edges.items) |*e| e.deinit(alloc);
        edges.deinit(alloc);
    }

    var removal_count: usize = 0;
    for (state.entries) |entry| {
        if (entry.stale) continue;
        var live = false;
        for (live_entity_ids) |id| {
            if (std.mem.eql(u8, id, entry.entity_id)) {
                live = true;
                break;
            }
        }
        if (live) continue;
        removal_count = try std.math.add(usize, removal_count, 1);
    }

    try edges.ensureTotalCapacity(alloc, removal_count);
    for (state.entries) |entry| {
        if (entry.stale) continue;
        var live = false;
        for (live_entity_ids) |entity| {
            if (std.mem.eql(u8, entity, entry.entity_id)) {
                live = true;
                break;
            }
        }
        if (live) continue;
        edges.appendAssumeCapacity(try duplicateEdge(
            alloc,
            entry.entity_id,
            entry.entity_id,
            .entity_removed,
            "entity absent from current module realization plan",
        ));
    }

    const owned_edges = try edges.toOwnedSlice(alloc);
    errdefer {
        for (owned_edges) |*edge| edge.deinit(alloc);
        alloc.free(owned_edges);
    }

    for (state.entries) |*entry| {
        if (entry.stale) continue;
        var live = false;
        for (live_entity_ids) |entity| {
            if (std.mem.eql(u8, entity, entry.entity_id)) {
                live = true;
                break;
            }
        }
        if (live) continue;
        entry.stale = true;
        entry.kind = .stale;
    }

    return .{ .edges = owned_edges };
}

/// Record invalidation edges for entities whose reuse audit reported invalidation.
pub fn edgesFromReuseAudits(
    alloc: std.mem.Allocator,
    audits: []const persistent_semantic_state.ReuseAudit,
) !Graph {
    var edges: std.ArrayListUnmanaged(Edge) = .empty;
    errdefer {
        for (edges.items) |*e| e.deinit(alloc);
        edges.deinit(alloc);
    }
    var invalidated_count: usize = 0;
    for (audits) |row| {
        if (row.action == .invalidated) {
            invalidated_count = try std.math.add(usize, invalidated_count, 1);
        }
    }
    try edges.ensureTotalCapacity(alloc, invalidated_count);
    for (audits) |row| {
        if (row.action != .invalidated) continue;
        edges.appendAssumeCapacity(try duplicateEdge(
            alloc,
            row.entity_id,
            row.entity_id,
            .fingerprint_change,
            row.reason,
        ));
    }
    return .{ .edges = try edges.toOwnedSlice(alloc) };
}

fn expectEntryOwnershipUnchanged(
    expected: persistent_semantic_state.Entry,
    actual: persistent_semantic_state.Entry,
) !void {
    try std.testing.expect(expected.entity_id.ptr == actual.entity_id.ptr);
    try std.testing.expectEqual(expected.entity_id.len, actual.entity_id.len);
    try std.testing.expectEqual(expected.fingerprint, actual.fingerprint);
    try std.testing.expectEqual(expected.kind, actual.kind);
    try std.testing.expect(expected.artifact.ptr == actual.artifact.ptr);
    try std.testing.expectEqual(expected.artifact.len, actual.artifact.len);
    try std.testing.expect(expected.compiler_version.ptr == actual.compiler_version.ptr);
    try std.testing.expectEqual(expected.compiler_version.len, actual.compiler_version.len);
    try std.testing.expect(expected.target.ptr == actual.target.ptr);
    try std.testing.expectEqual(expected.target.len, actual.target.len);
    try std.testing.expectEqual(expected.stale, actual.stale);
    try std.testing.expectEqual(expected.transform_version == null, actual.transform_version == null);
    if (expected.transform_version) |expected_version| {
        const actual_version = actual.transform_version.?;
        try std.testing.expect(expected_version.ptr == actual_version.ptr);
        try std.testing.expectEqual(expected_version.len, actual_version.len);
    }
}

fn removedEntityAllocationProbe(alloc: std.mem.Allocator) !void {
    var state: persistent_semantic_state.State = .{ .entries = &.{} };
    defer state.deinit(alloc);
    try persistent_semantic_state.appendEntry(
        alloc,
        &state,
        "duo:record:Old",
        0x1,
        .source_derived,
        "native_aggregate",
        "duo-dev",
        "native",
        "v0",
    );
    try persistent_semantic_state.appendEntry(
        alloc,
        &state,
        "duo:record:Live",
        0x2,
        .target_derived,
        "native_struct",
        "duo-dev",
        "native",
        null,
    );
    const expected_entries = state.entries.ptr;
    const expected_old = state.entries[0];
    const expected_live = state.entries[1];
    var graph = invalidateRemovedEntities(alloc, &state, &.{"duo:record:Live"}) catch |err| {
        try std.testing.expect(state.entries.ptr == expected_entries);
        try std.testing.expectEqual(@as(usize, 2), state.entries.len);
        try expectEntryOwnershipUnchanged(expected_old, state.entries[0]);
        try expectEntryOwnershipUnchanged(expected_live, state.entries[1]);
        return err;
    };
    defer graph.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), graph.edges.len);
    try std.testing.expectEqual(EdgeKind.entity_removed, graph.edges[0].kind);
    try std.testing.expectEqualStrings("duo:record:Old", graph.edges[0].subject_entity);
    try std.testing.expect(state.entries[0].stale);
    try std.testing.expectEqual(persistent_semantic_state.FactKind.stale, state.entries[0].kind);
    try expectEntryOwnershipUnchanged(expected_live, state.entries[1]);
}

fn reuseAuditAllocationProbe(alloc: std.mem.Allocator) !void {
    const audits = [_]persistent_semantic_state.ReuseAudit{
        .{
            .entity_id = "duo:record:Point",
            .action = .invalidated,
            .reason = "semantic fingerprint changed",
            .artifact = "native_aggregate",
        },
        .{
            .entity_id = "duo:record:Live",
            .action = .reused,
            .reason = "all reuse constraints match",
            .artifact = "native_struct",
        },
    };
    var graph = try edgesFromReuseAudits(alloc, &audits);
    defer graph.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), graph.edges.len);
    try std.testing.expectEqual(EdgeKind.fingerprint_change, graph.edges[0].kind);
    try std.testing.expectEqualStrings(audits[0].entity_id, graph.edges[0].subject_entity);
    try std.testing.expectEqualStrings(audits[0].reason, graph.edges[0].reason);
}

test "semantic_invalidation: removed entity marked stale" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = persistent_semantic_state.State{ .entries = &.{} };
    try persistent_semantic_state.appendEntry(
        alloc,
        &state,
        "duo:record:Old",
        0x1,
        .source_derived,
        "native_aggregate",
        "duo-dev",
        "native",
        "v0",
    );
    var g = try invalidateRemovedEntities(alloc, &state, &.{});
    defer g.deinit(alloc);
    try std.testing.expect(g.edges.len == 1);
    try std.testing.expect(state.entries[0].stale);
}

test "semantic_invalidation: removal publication is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, removedEntityAllocationProbe, .{});
}

test "semantic_invalidation: reuse audit edges release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reuseAuditAllocationProbe, .{});
}
