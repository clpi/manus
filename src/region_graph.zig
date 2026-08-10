//! Pass 22 WS20 — executable region graph (optimization substrate).
//!
//! Projects DNIR + semantic graph identity into a bounded region graph.
//! Canonical edge vocabulary (§17.2 subset): defines, uses, calls, orders_before.
const std = @import("std");
const dnir = @import("duo_native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const graph_query = @import("graph_query.zig");
const realization = @import("realization.zig");

pub const CanonicalEdge = enum {
    defines,
    uses,
    calls,
    orders_before,
    realizes_as,
};

pub const NodeKind = enum {
    region,
    param,
    value,
    record,
    call,
    binop,
    branch,
    ret,
    realization,
    /// DNIR `hw_fence` / `hw_spin` / `hw_unary` — hardware descriptor anchor.
    hardware,
};

pub const Node = struct {
    id: u32,
    kind: NodeKind,
    label: ?[]const u8 = null,
    graph_stable_id: ?u64 = null,
    shape_id: ?u64 = null,
    dnir_temp: ?u32 = null,
    callee: ?[]const u8 = null,
};

pub const Edge = struct {
    from: u32,
    to: u32,
    kind: CanonicalEdge,
};

pub const Region = struct {
    func_name: []const u8,
    func_stable_id: ?u64,
    nodes: []Node,
    edges: []Edge,
    /// Pass 22 Gate L — unresolved realization candidates visible at region scope.
    legal_realization_candidates: u32 = 0,
    /// Highest hardware tier exercised in this region (Pass 22 WS23).
    hardware_tier: dnir.HardwareTier = .scalar,

    pub fn deinit(self: *Region, alloc: std.mem.Allocator) void {
        for (self.nodes) |n| {
            if (n.label) |l| alloc.free(l);
            if (n.callee) |c| alloc.free(c);
        }
        alloc.free(self.nodes);
        alloc.free(self.edges);
        alloc.free(self.func_name);
    }
};

pub fn buildFromDnirFunction(
    alloc: std.mem.Allocator,
    f: dnir.Function,
    graph: ?*const semantic_graph.SemanticGraph,
    records: []const dnir.RecordDesc,
) !Region {
    var nodes: std.ArrayListUnmanaged(Node) = .empty;
    errdefer nodes.deinit(alloc);
    var edges: std.ArrayListUnmanaged(Edge) = .empty;
    errdefer edges.deinit(alloc);

    var next_id: u32 = 0;
    const region_id = next_id;
    next_id += 1;
    try nodes.append(alloc, .{ .id = region_id, .kind = .region, .label = try alloc.dupe(u8, f.name) });

    // One resolver for both ends of the identity check. `validateModuleRegions`
    // re-derives this hash through `graph_query.stableIdOf` and errors when the
    // two differ; deriving them here by a second, name-first route is how that
    // check could fail on a name collision rather than on a real mismatch.
    const func_stable_id: ?u64 = if (graph) |g| graph_query.stableIdOf(g, f.name) else null;

    var temp_node: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer temp_node.deinit(alloc);

    for (f.params, 0..) |p, i| {
        const pid = next_id;
        next_id += 1;
        try nodes.append(alloc, .{
            .id = pid,
            .kind = .param,
            .label = try alloc.dupe(u8, p.name),
        });
        try edges.append(alloc, .{ .from = region_id, .to = pid, .kind = .defines });
        try temp_node.put(alloc, @intCast(i), pid);
    }

    var prev_effect: ?u32 = null;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            const nid = next_id;
            next_id += 1;
            const kind: NodeKind = switch (ins.op) {
                .call_direct, .call_extern => .call,
                .binop, .cmp => .binop,
                .br, .br_if, .br_if_not => .branch,
                .ret, .ret_record => .ret,
                .init_record => .record,
                .hw_fence, .hw_spin, .hw_unary => .hardware,
                else => .value,
            };

            var label_owned: ?[]const u8 = null;
            var record_shape_id: ?u64 = null;
            var record_stable_id: ?u64 = null;
            if (kind == .record and ins.record.len > 0) {
                label_owned = try alloc.dupe(u8, ins.record);
                for (records) |rec| {
                    if (!std.mem.eql(u8, rec.name, ins.record)) continue;
                    record_shape_id = rec.shape_id;
                    record_stable_id = rec.graph_stable_id;
                    break;
                }
            }

            if (kind == .hardware) {
                if (dnir_hardware.intrinsicOfOp(ins.op, ins.hw)) |hw| {
                    label_owned = try alloc.dupe(u8, hw.duoName());
                }
            }

            var callee_owned: ?[]const u8 = null;
            var callee_stable: ?u64 = ins.relation;
            if (kind == .call and ins.callee.len > 0) {
                callee_owned = try alloc.dupe(u8, ins.callee);
                if (callee_stable == null) if (graph) |g| {
                    if (g.findFunc(ins.callee)) |cid| {
                        if (g.get(cid)) |cn| {
                            if (cn.stable_id) |sid| callee_stable = sid.hash;
                        }
                    }
                };
            }

            try nodes.append(alloc, .{
                .id = nid,
                .kind = kind,
                .label = label_owned,
                .graph_stable_id = if (kind == .call) callee_stable else record_stable_id,
                .shape_id = if (kind == .record) record_shape_id else null,
                .callee = callee_owned,
                .dnir_temp = ins.result,
            });

            if (prev_effect) |p| {
                try edges.append(alloc, .{ .from = p, .to = nid, .kind = .orders_before });
            }
            const is_effect = kind == .branch or kind == .ret or kind == .call or kind == .binop or
                kind == .hardware or ins.op == .store_local;
            if (is_effect) prev_effect = nid;

            try wireUses(alloc, &edges, &temp_node, ins.lhs, nid);
            try wireUses(alloc, &edges, &temp_node, ins.rhs, nid);
            try wireUses(alloc, &edges, &temp_node, ins.third, nid);

            if (ins.result) |t| {
                try temp_node.put(alloc, t, nid);
                try edges.append(alloc, .{ .from = nid, .to = nid, .kind = .defines });
            }
            if (kind == .call and callee_stable != null) {
                try edges.append(alloc, .{ .from = nid, .to = region_id, .kind = .calls });
            }
        }
    }

    return .{
        .func_name = try alloc.dupe(u8, f.name),
        .func_stable_id = func_stable_id,
        .nodes = try nodes.toOwnedSlice(alloc),
        .edges = try edges.toOwnedSlice(alloc),
        .hardware_tier = dnir_hardware.functionHardwareTier(f),
    };
}

fn wireUses(
    alloc: std.mem.Allocator,
    edges: *std.ArrayListUnmanaged(Edge),
    temps: *std.AutoHashMapUnmanaged(u32, u32),
    v: dnir.Value,
    consumer: u32,
) !void {
    switch (v) {
        .temp => |t| {
            if (temps.get(t)) |src| {
                try edges.append(alloc, .{ .from = src, .to = consumer, .kind = .uses });
            }
        },
        .local => |slot| {
            if (temps.get(slot)) |src| {
                try edges.append(alloc, .{ .from = src, .to = consumer, .kind = .uses });
            }
        },
        else => {},
    }
}

pub fn buildModuleRegions(
    alloc: std.mem.Allocator,
    m: dnir.Module,
    graph: ?*const semantic_graph.SemanticGraph,
) ![]Region {
    var regions: std.ArrayListUnmanaged(Region) = .empty;
    errdefer {
        for (regions.items) |*r| r.deinit(alloc);
        regions.deinit(alloc);
    }
    for (m.functions) |f| {
        try regions.append(alloc, try buildFromDnirFunction(alloc, f, graph, m.records));
    }
    return try regions.toOwnedSlice(alloc);
}

pub fn freeModuleRegions(alloc: std.mem.Allocator, regions: []Region) void {
    for (regions) |*r| r.deinit(alloc);
    alloc.free(regions);
}

pub const RegionGraphError = error{
    EmitOrderMismatch,
    StableIdMismatch,
    CallGraphMismatch,
    OutOfMemory,
};

pub fn findRegion(regions: []const Region, func_name: []const u8) ?*const Region {
    for (regions) |*r| {
        if (std.mem.eql(u8, r.func_name, func_name)) return r;
    }
    return null;
}

/// Count direct intra-module callees with semantic graph identity.
pub fn countDirectCallees(region: *const Region) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind == .call and node.graph_stable_id != null) n += 1;
    }
    return n;
}

/// Verify DNIR emit order, stable IDs, and call edges match the semantic graph.
pub fn validateModuleRegions(
    regions: []const Region,
    graph: *const semantic_graph.SemanticGraph,
    m: dnir.Module,
    alloc: std.mem.Allocator,
) RegionGraphError!void {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(alloc);
    for (m.functions) |f| try names.append(alloc, f.name);

    const order = graph.moduleFunctionEmitOrder(alloc, names.items) catch return error.OutOfMemory;
    defer alloc.free(order);

    if (order.len != m.functions.len) return error.EmitOrderMismatch;
    for (order, 0..) |name, i| {
        if (!std.mem.eql(u8, name, m.functions[i].name)) return error.EmitOrderMismatch;
    }

    for (m.functions) |f| {
        const region = findRegion(regions, f.name) orelse return error.StableIdMismatch;
        if (region.func_stable_id != f.graph_stable_id) return error.StableIdMismatch;
        if (f.graph_stable_id) |sid| {
            const gsid = graph_query.stableIdOf(graph, f.name) orelse return error.StableIdMismatch;
            if (gsid != sid) return error.StableIdMismatch;
        }

        const callees = graph_query.calleesOf(graph, alloc, f.name) catch return error.OutOfMemory;
        defer alloc.free(callees);
        if (callees.len == 0) continue;

        if (countDirectCallees(region) != callees.len) return error.CallGraphMismatch;

        for (callees) |callee| {
            var found = false;
            for (region.nodes) |node| {
                if (node.kind != .call or node.graph_stable_id == null) continue;
                if (node.callee) |c| {
                    if (std.mem.eql(u8, c, callee)) found = true;
                }
            }
            if (!found) return error.CallGraphMismatch;
        }
    }
}

/// Attach deferred candidate counts and committed `realizes_as` edges (Gate L → IR).
pub fn attachRealizationPlan(
    alloc: std.mem.Allocator,
    regions: []Region,
    plan: *const realization.ModuleRealizations,
) !void {
    var pending: u32 = 0;
    for (plan.variables) |v| {
        if (v.selected_index == null) {
            pending += @intCast(realization.legalCandidateCount(&v));
            continue;
        }
        const sel = v.selected() orelse continue;
        const record_name = recordEntityName(v.subject_entity) orelse continue;
        for (regions) |*r| {
            try attachRealizesAsForRecord(alloc, r, record_name, sel.id);
        }
    }
    if (pending > 0) {
        for (regions) |*r| r.legal_realization_candidates = pending;
    }
}

fn recordEntityName(subject_entity: []const u8) ?[]const u8 {
    const prefix = "duo:record:";
    if (subject_entity.len <= prefix.len) return null;
    if (!std.mem.startsWith(u8, subject_entity, prefix)) return null;
    return subject_entity[prefix.len..];
}

fn attachRealizesAsForRecord(
    alloc: std.mem.Allocator,
    region: *Region,
    record_name: []const u8,
    realization_id: []const u8,
) !void {
    var next_id: u32 = 0;
    for (region.nodes) |n| {
        if (n.id >= next_id) next_id = n.id + 1;
    }

    var new_nodes: std.ArrayListUnmanaged(Node) = .empty;
    errdefer new_nodes.deinit(alloc);
    try new_nodes.appendSlice(alloc, region.nodes);

    var new_edges: std.ArrayListUnmanaged(Edge) = .empty;
    errdefer new_edges.deinit(alloc);
    try new_edges.appendSlice(alloc, region.edges);

    var attached = false;
    for (region.nodes) |node| {
        if (node.kind != .record) continue;
        if (node.label) |label| {
            if (!std.mem.eql(u8, label, record_name)) continue;
        } else continue;

        const target_id = next_id;
        next_id += 1;
        try new_nodes.append(alloc, .{
            .id = target_id,
            .kind = .realization,
            .label = try alloc.dupe(u8, realization_id),
        });
        try new_edges.append(alloc, .{ .from = node.id, .to = target_id, .kind = .realizes_as });
        attached = true;
    }
    if (!attached) {
        for (region.nodes) |node| {
            if (node.kind != .region) continue;
            const target_id = next_id;
            next_id += 1;
            try new_nodes.append(alloc, .{
                .id = target_id,
                .kind = .realization,
                .label = try alloc.dupe(u8, realization_id),
            });
            try new_edges.append(alloc, .{ .from = node.id, .to = target_id, .kind = .realizes_as });
            attached = true;
            break;
        }
    }
    if (!attached) return;

    alloc.free(region.nodes);
    alloc.free(region.edges);
    region.nodes = try new_nodes.toOwnedSlice(alloc);
    region.edges = try new_edges.toOwnedSlice(alloc);
}

/// Count hardware descriptor nodes in a region.
pub fn countHardwareNodes(region: *const Region) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind == .hardware) n += 1;
    }
    return n;
}

/// Find first hardware node id with the given intrinsic label (`fence`, `popcount`, …).
pub fn hardwareNodeId(region: *const Region, intrinsic_label: []const u8) ?u32 {
    for (region.nodes) |node| {
        if (node.kind != .hardware) continue;
        if (node.label) |label| {
            if (std.mem.eql(u8, label, intrinsic_label)) return node.id;
        }
    }
    return null;
}

/// Count hardware nodes matching an intrinsic label.
pub fn countHardwareNodesLabeled(region: *const Region, intrinsic_label: []const u8) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind != .hardware) continue;
        if (node.label) |label| {
            if (std.mem.eql(u8, label, intrinsic_label)) n += 1;
        }
    }
    return n;
}

/// Count `realizes_as` edges in a region (committed realization on IR).
pub fn countRealizesAsEdges(region: *const Region) usize {
    var n: usize = 0;
    for (region.edges) |e| {
        if (e.kind == .realizes_as) n += 1;
    }
    return n;
}

/// Deprecated alias — use `attachRealizationPlan`.
pub fn attachDeferredRealizations(regions: []Region, plan: *const realization.ModuleRealizations) void {
    var pending: u32 = 0;
    for (plan.variables) |v| {
        if (v.selected_index != null) continue;
        pending += @intCast(realization.legalCandidateCount(&v));
    }
    for (regions) |*r| r.legal_realization_candidates = pending;
}

pub fn buildValidatedModuleRegions(
    alloc: std.mem.Allocator,
    m: dnir.Module,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError![]Region {
    const regions = try buildModuleRegions(alloc, m, graph);
    errdefer freeModuleRegions(alloc, regions);
    try validateModuleRegions(regions, graph, m, alloc);
    return regions;
}

test "region_graph: preserves call edges and stable ids" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "region.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "region.duo");
    const m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);

    const regions = try buildModuleRegions(alloc, m, &g);
    defer freeModuleRegions(alloc, regions);
    try validateModuleRegions(regions, &g, m, alloc);

    var main_region: ?*const Region = null;
    for (regions) |*r| {
        if (std.mem.eql(u8, r.func_name, "main")) main_region = r;
        try std.testing.expect(r.func_stable_id != null);
    }
    const mr = main_region orelse return error.TestExpectedEqual;
    var saw_call = false;
    for (mr.edges) |e| {
        if (e.kind == .calls) saw_call = true;
    }
    try std.testing.expect(saw_call);
}

test "region_graph: hardware ops become labeled nodes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    @comp.hint.fence()
        \\    @comp.bit.popcount(47)
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "hw.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try dnir_lower.lowerModule(alloc, &mod);
    const regions = try buildModuleRegions(alloc, m, null);
    defer freeModuleRegions(alloc, regions);
    const main = findRegion(regions, "main") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(dnir.HardwareTier.scalar, main.hardware_tier);
    try std.testing.expect(countHardwareNodesLabeled(main, "fence") >= 1);
    try std.testing.expect(countHardwareNodesLabeled(main, "popcount") >= 1);
}
