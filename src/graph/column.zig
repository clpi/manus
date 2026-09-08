const std = @import("std");
const graph = @import("../graph.zig");

pub const ColumnError = error{StaleColumn};

pub const KindColumn = struct {
    kinds: []graph.NodeKind,
    count: usize,
    check: u64,

    pub fn deinit(self: *KindColumn, alloc: std.mem.Allocator) void {
        alloc.free(self.kinds);
        self.* = undefined;
    }
};

fn checksum(kinds: []const graph.NodeKind) u64 {
    return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(kinds));
}

pub fn build(alloc: std.mem.Allocator, nodes: []const graph.Node) !KindColumn {
    const kinds = try alloc.alloc(graph.NodeKind, nodes.len);
    for (nodes, 0..) |node, i| kinds[i] = node.kind;
    return .{ .kinds = kinds, .count = nodes.len, .check = checksum(kinds) };
}

fn fresh(column: *const KindColumn, nodes: []const graph.Node) !void {
    if (column.count != nodes.len) return ColumnError.StaleColumn;
    if (column.kinds.len != nodes.len) return ColumnError.StaleColumn;
    if (column.check != checksum(column.kinds)) return ColumnError.StaleColumn;
}

pub fn countOfKind(column: *const KindColumn, nodes: []const graph.Node, kind: graph.NodeKind) !usize {
    try fresh(column, nodes);
    var total: usize = 0;
    for (column.kinds, 0..) |column_kind, i| {
        if (column_kind != kind) continue;
        if (nodes[i].kind != column_kind) return ColumnError.StaleColumn;
        total += 1;
    }
    return total;
}

pub fn findUnique(
    column: *const KindColumn,
    nodes: []const graph.Node,
    name: []const u8,
    kind: graph.NodeKind,
) !?usize {
    try fresh(column, nodes);
    var match: ?usize = null;
    for (column.kinds, 0..) |column_kind, i| {
        if (column_kind != kind) continue;
        if (nodes[i].kind != column_kind) return ColumnError.StaleColumn;
        const node_name = nodes[i].name orelse continue;
        if (!std.mem.eql(u8, node_name, name)) continue;
        if (match != null) return null;
        match = i;
    }
    return match;
}

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * 1000000000 + @as(u64, @intCast(ts.nsec));
}

fn authorityCount(nodes: []const graph.Node, kind: graph.NodeKind) usize {
    var total: usize = 0;
    for (nodes) |node| {
        if (node.kind != kind) continue;
        total += 1;
    }
    return total;
}

fn authorityFind(nodes: []const graph.Node, name: []const u8, kind: graph.NodeKind) ?usize {
    var match: ?usize = null;
    for (nodes, 0..) |node, i| {
        if (node.kind != kind) continue;
        const node_name = node.name orelse continue;
        if (!std.mem.eql(u8, node_name, name)) continue;
        if (match != null) return null;
        match = i;
    }
    return match;
}

fn makeCorpus(alloc: std.mem.Allocator, n: usize) ![]graph.Node {
    const nodes = try alloc.alloc(graph.Node, n);
    for (nodes, 0..) |*node, i| {
        node.* = std.mem.zeroes(graph.Node);
        node.kind = switch (i % 7) {
            0 => .func,
            1 => .param,
            2 => .local,
            3 => .call,
            4 => .value,
            5 => .relation,
            else => .module,
        };
    }
    nodes[17].name = "alpha";
    nodes[17].kind = .func;
    nodes[9001].name = "beta";
    nodes[9001].kind = .call;
    nodes[31000].name = "alpha";
    nodes[31000].kind = .call;
    return nodes;
}

test "kindcolumn: column agrees with authority and refuses a perturbed entry" {
    const alloc = std.testing.allocator;
    const nodes = try makeCorpus(alloc, 40000);
    defer alloc.free(nodes);
    var column = try build(alloc, nodes);
    defer column.deinit(alloc);
    try std.testing.expectEqual(authorityCount(nodes, .func), try countOfKind(&column, nodes, .func));
    try std.testing.expectEqual(authorityCount(nodes, .call), try countOfKind(&column, nodes, .call));
    try std.testing.expectEqual(authorityFind(nodes, "beta", .call), try findUnique(&column, nodes, "beta", .call));
    try std.testing.expectEqual(authorityFind(nodes, "alpha", .func), try findUnique(&column, nodes, "alpha", .func));
    try std.testing.expectEqual(authorityFind(nodes, "missing", .func), try findUnique(&column, nodes, "missing", .func));
    column.kinds[9001] = .func;
    try std.testing.expectError(ColumnError.StaleColumn, countOfKind(&column, nodes, .call));
    try std.testing.expectError(ColumnError.StaleColumn, findUnique(&column, nodes, "beta", .call));
    column.kinds[9001] = .call;
    try std.testing.expectEqual(authorityFind(nodes, "beta", .call), try findUnique(&column, nodes, "beta", .call));
    nodes[9001].kind = .func;
    try std.testing.expectError(ColumnError.StaleColumn, countOfKind(&column, nodes, .call));
    try std.testing.expectError(ColumnError.StaleColumn, findUnique(&column, nodes, "beta", .call));
    nodes[9001].kind = .call;
    try std.testing.expectEqual(authorityFind(nodes, "beta", .call), try findUnique(&column, nodes, "beta", .call));
}

test "kindcolumn: column from another node set refuses instead of answering" {
    const alloc = std.testing.allocator;
    const nodes = try makeCorpus(alloc, 40000);
    defer alloc.free(nodes);
    const other = try makeCorpus(alloc, 39999);
    defer alloc.free(other);
    var column = try build(alloc, other);
    defer column.deinit(alloc);
    try std.testing.expectError(ColumnError.StaleColumn, countOfKind(&column, nodes, .func));
    try std.testing.expectError(ColumnError.StaleColumn, findUnique(&column, nodes, "beta", .call));
    var phantom: usize = 0;
    for (column.kinds) |column_kind| {
        if (column_kind == .call) phantom += 1;
    }
    try std.testing.expect(phantom > 0);
}

test "kindcolumn: measure kind-filtered scan stride" {
    const alloc = std.testing.allocator;
    const n: usize = 80000;
    const nodes = try makeCorpus(alloc, n);
    defer alloc.free(nodes);
    var column = try build(alloc, nodes);
    defer column.deinit(alloc);
    const node_stride = @sizeOf(graph.Node);
    const kind_stride = @sizeOf(graph.NodeKind);
    var best_authority: u64 = std.math.maxInt(u64);
    var best_column: u64 = std.math.maxInt(u64);
    var sink: usize = 0;
    for (0..11) |_| {
        const start_authority = nowNs();
        sink = authorityCount(nodes, .call);
        std.mem.doNotOptimizeAway(&sink);
        const elapsed_authority = nowNs() - start_authority;
        if (elapsed_authority < best_authority) best_authority = elapsed_authority;
        const start_column = nowNs();
        sink = try countOfKind(&column, nodes, .call);
        std.mem.doNotOptimizeAway(&sink);
        const elapsed_column = nowNs() - start_column;
        if (elapsed_column < best_column) best_column = elapsed_column;
    }
    std.mem.doNotOptimizeAway(&sink);
    std.debug.print(
        "kindcolumn nodes={d} node_stride={d} kind_stride={d} authority_bytes={d} column_bytes={d} authority_ns={d} column_ns={d} per_node_authority_ps={d} per_node_column_ps={d}\n",
        .{
            n,
            node_stride,
            kind_stride,
            n * node_stride,
            n * kind_stride,
            best_authority,
            best_column,
            @divTrunc(best_authority * 1000, n),
            @divTrunc(best_column * 1000, n),
        },
    );
    try std.testing.expectEqual(authorityCount(nodes, .call), try countOfKind(&column, nodes, .call));
}
