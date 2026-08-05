//! Pass 8 — bounded invalidation edges for persistent semantic evidence (P8-08 seed).
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

    for (state.entries) |*entry| {
        if (entry.stale) continue;
        var live = false;
        for (live_entity_ids) |id| {
            if (std.mem.eql(u8, id, entry.entity_id)) {
                live = true;
                break;
            }
        }
        if (live) continue;
        entry.stale = true;
        entry.kind = .stale;
        try edges.append(alloc, .{
            .subject_entity = try alloc.dupe(u8, entry.entity_id),
            .affected_entity = try alloc.dupe(u8, entry.entity_id),
            .kind = .entity_removed,
            .reason = try alloc.dupe(u8, "entity absent from current module realization plan"),
        });
    }

    return .{ .edges = try edges.toOwnedSlice(alloc) };
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
    for (audits) |row| {
        if (row.action != .invalidated) continue;
        try edges.append(alloc, .{
            .subject_entity = try alloc.dupe(u8, row.entity_id),
            .affected_entity = try alloc.dupe(u8, row.entity_id),
            .kind = .fingerprint_change,
            .reason = try alloc.dupe(u8, row.reason),
        });
    }
    return .{ .edges = try edges.toOwnedSlice(alloc) };
}

test "semantic_invalidation: removed entity marked stale" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = persistent_semantic_state.State{ .entries = &.{} };
    try persistent_semantic_state.appendEntry(
        alloc, &state, "duo:record:Old", 0x1, .source_derived, "native_aggregate", "duo-dev", "native", "v0",
    );
    var g = try invalidateRemovedEntities(alloc, &state, &.{});
    defer g.deinit(alloc);
    try std.testing.expect(g.edges.len == 1);
    try std.testing.expect(state.entries[0].stale);
}
