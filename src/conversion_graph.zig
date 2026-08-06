//! Pass 23 §9 — unified conversion graph (to/from share one directed edge).
const std = @import("std");

pub const SCHEMA_VERSION = "conversion-graph-v0";

pub const Category = enum {
    identity,
    representation_equivalent,
    lossless,
    checked,
    potentially_failing,
    lossy,
    parsing,
    serialization,
    foreign_adaptation,
    unsafe_reinterpretation,

    pub fn permitsImplicit(self: Category) bool {
        return switch (self) {
            .identity, .representation_equivalent, .lossless => true,
            else => false,
        };
    }
};

pub const Registration = enum {
    target_owned,
    source_owned,
};

pub const Edge = struct {
    from: []const u8,
    to: []const u8,
    category: Category,
    registration: Registration,
    id_hash: u64,
};

pub const Graph = struct {
    edges: []Edge,

    pub fn deinit(self: *Graph, alloc: std.mem.Allocator) void {
        for (self.edges) |*e| {
            alloc.free(e.from);
            alloc.free(e.to);
        }
        alloc.free(self.edges);
    }

    pub fn find(self: *const Graph, from: []const u8, to: []const u8) ?*const Edge {
        for (self.edges) |*e| {
            if (std.mem.eql(u8, e.from, from) and std.mem.eql(u8, e.to, to)) return e;
        }
        return null;
    }
};

pub fn edgeId(from: []const u8, to: []const u8) u64 {
    var h = std.hash.Wyhash.init(0xC0FFE007);
    h.update(from);
    h.update("->");
    h.update(to);
    return h.final();
}

pub fn registerEdge(
    alloc: std.mem.Allocator,
    graph: *Graph,
    from: []const u8,
    to: []const u8,
    category: Category,
    registration: Registration,
) !void {
    if (graph.find(from, to) != null) return;
    const owned_from = try alloc.dupe(u8, from);
    errdefer alloc.free(owned_from);
    const owned_to = try alloc.dupe(u8, to);
    errdefer alloc.free(owned_to);
    const new_edge = Edge{
        .from = owned_from,
        .to = owned_to,
        .category = category,
        .registration = registration,
        .id_hash = edgeId(from, to),
    };
    const old = graph.edges;
    graph.edges = try alloc.realloc(old, old.len + 1);
    graph.edges[old.len] = new_edge;
}

pub fn initGraph(alloc: std.mem.Allocator) Graph {
    _ = alloc;
    return .{ .edges = &.{} };
}

test "conversion_graph: to and from share one edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var g = initGraph(alloc);
    try registerEdge(alloc, &g, "Person", "Employee", .checked, .target_owned);
    const e = g.find("Person", "Employee") orelse return error.TestExpectedEqual;
    try std.testing.expect(e.registration == .target_owned);
    try std.testing.expect(g.find("Employee", "Person") == null);
}
