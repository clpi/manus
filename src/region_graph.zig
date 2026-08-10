//! Pass 22 WS20 — executable region graph (optimization substrate).
//!
//! Projects DNIR + semantic graph identity into a bounded region graph.
//! Canonical edge vocabulary (§17.2 subset): defines, uses, calls, orders_before.
const std = @import("std");
const dnir = @import("duo_native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const realization = @import("realization.zig");
const types = @import("types.zig");

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
    relation_id: ?dnir.SemanticRef = null,
    application_id: ?dnir.SemanticRef = null,
    value_id: ?dnir.SemanticRef = null,
    subject_id: ?dnir.SemanticRef = null,
    descriptor: ?types.ResolvedType = null,
    realization_start: ?u32 = null,
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
    func_identity: ?dnir.SemanticRef,
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
    _: ?*const semantic_graph.SemanticGraph,
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
                .br => .branch,
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
            if (kind == .call and ins.callee.len > 0) {
                callee_owned = try alloc.dupe(u8, ins.callee);
            }

            try nodes.append(alloc, .{
                .id = nid,
                .kind = kind,
                .label = label_owned,
                .graph_stable_id = record_stable_id,
                .relation_id = ins.relation,
                .application_id = ins.application,
                .value_id = ins.value,
                .subject_id = ins.subject,
                .descriptor = if (ins.application != null) ins.ty else null,
                .realization_start = ins.realization_start,
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
            if (kind == .call and ins.relation != null and ins.application != null and ins.value != null) {
                try edges.append(alloc, .{ .from = nid, .to = region_id, .kind = .calls });
            }
        }
    }

    return .{
        .func_name = try alloc.dupe(u8, f.name),
        .func_identity = f.semantic_identity,
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
    IncompleteApplicationIdentity,
    ApplicationGraphMismatch,
    OutOfMemory,
};

pub fn findRegion(regions: []const Region, func_name: []const u8) ?*const Region {
    for (regions) |*r| {
        if (std.mem.eql(u8, r.func_name, func_name)) return r;
    }
    return null;
}

pub fn hasAnyApplicationIdentity(node: Node) bool {
    return node.relation_id != null or node.application_id != null or node.value_id != null or
        node.subject_id != null or node.realization_start != null;
}

pub fn hasCompleteApplicationIdentity(node: Node) bool {
    return node.relation_id != null and node.application_id != null and node.value_id != null and node.realization_start != null;
}

fn optionalSemanticRefEql(a: ?dnir.SemanticRef, b: ?dnir.SemanticRef) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.?.eql(b.?);
}

pub const SemanticNameReconstructionCensus = struct {
    required_checked_applications: usize = 0,
    checked_call_nodes: usize = 0,
    checked_realization_nodes: usize = 0,
    incomplete_lineage: usize = 0,
    missing_lineage: usize = 0,
    legacy_symbol_bridges: usize = 0,
    legacy_function_name_bridges: usize = 0,
};

/// Measure the application-identity boundary represented by region nodes. A
/// partial identity fails closed; it is never completed from the symbol. A
/// call with no identity remains an explicit legacy symbol bridge.
pub fn semanticNameReconstructionCensus(
    alloc: std.mem.Allocator,
    regions: []const Region,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError!SemanticNameReconstructionCensus {
    var census: SemanticNameReconstructionCensus = .{};
    var expected = try expectedApplications(alloc, graph);
    defer expected.deinit(alloc);
    census.required_checked_applications = expected.count();

    for (regions) |region| {
        if (region.func_identity == null) census.legacy_function_name_bridges += 1;
        for (region.nodes) |node| {
            if (!hasAnyApplicationIdentity(node)) {
                if (node.kind == .call) census.legacy_symbol_bridges += 1;
                continue;
            }
            if (!hasCompleteApplicationIdentity(node)) {
                census.incomplete_lineage += 1;
                continue;
            }
            if (node.kind == .call) {
                census.checked_call_nodes += 1;
            } else {
                census.checked_realization_nodes += 1;
            }
            if (expected.getPtr(node.application_id.?.node)) |application| {
                application.uses += 1;
            }
        }
    }
    var iterator = expected.valueIterator();
    while (iterator.next()) |application| {
        if (application.uses == 0) census.missing_lineage += 1;
    }
    return census;
}

/// Count direct intra-module callees with complete semantic application identity.
pub fn countDirectCallees(region: *const Region) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind == .call and hasCompleteApplicationIdentity(node)) n += 1;
    }
    return n;
}

const ExpectedApplication = struct {
    application: dnir.SemanticRef,
    relation: dnir.SemanticRef,
    value: dnir.SemanticRef,
    subject: ?dnir.SemanticRef,
    descriptor: types.ResolvedType,
    caller: dnir.SemanticRef,
    uses: u32 = 0,
};

pub const CheckedApplicationProjection = struct {
    relation: dnir.SemanticRef,
    application: dnir.SemanticRef,
    value: dnir.SemanticRef,
    subject: ?dnir.SemanticRef,
    descriptor: types.ResolvedType,
    caller: dnir.SemanticRef,
};

const ApplicationEdges = struct {
    relation: ?semantic_graph.NodeId = null,
    result: ?semantic_graph.NodeId = null,
    subject: ?semantic_graph.NodeId = null,
};

fn containingFunctionFromScope(
    graph: *const semantic_graph.SemanticGraph,
    start: semantic_graph.NodeId,
) ?semantic_graph.NodeId {
    var current = start;
    var depth: u32 = 0;
    while (depth < 64) : (depth += 1) {
        const node = graph.get(current) orelse return null;
        if (node.kind == .func) return current;
        if (!node.scope.isValid()) return null;
        current = node.scope;
    }
    return null;
}

fn semanticReference(
    graph: *const semantic_graph.SemanticGraph,
    node_id: semantic_graph.NodeId,
) RegionGraphError!dnir.SemanticRef {
    const node = graph.get(node_id) orelse return error.ApplicationGraphMismatch;
    return .{
        .node = node_id.index,
        .fingerprint = (node.stable_id orelse return error.ApplicationGraphMismatch).hash,
    };
}

/// Collect the current checked application identity surface in O(nodes+edges).
/// These exact node references are a session-local bootstrap projection; no
/// missing pack, world, witness, provenance, or durable identity component is
/// synthesized here. Fingerprints remain non-authoritative metadata.
pub fn checkedApplicationProjections(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError![]CheckedApplicationProjection {
    const edges = alloc.alloc(ApplicationEdges, graph.nodes.items.len) catch return error.OutOfMemory;
    defer alloc.free(edges);
    for (edges) |*entry| entry.* = .{};

    for (graph.edges.items) |edge| {
        if (edge.from.index >= edges.len) return error.ApplicationGraphMismatch;
        if (graph.nodes.items[edge.from.index].kind != .call) continue;
        switch (edge.kind) {
            .relation => {
                if (edges[edge.from.index].relation != null) return error.ApplicationGraphMismatch;
                edges[edge.from.index].relation = edge.to;
            },
            .result => {
                if (edges[edge.from.index].result != null) return error.ApplicationGraphMismatch;
                edges[edge.from.index].result = edge.to;
            },
            .subject => {
                if (edges[edge.from.index].subject != null) return error.ApplicationGraphMismatch;
                edges[edge.from.index].subject = edge.to;
            },
            else => {},
        }
    }

    var projections: std.ArrayListUnmanaged(CheckedApplicationProjection) = .empty;
    errdefer projections.deinit(alloc);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(alloc);
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .call) continue;
        const relation = edges[i].relation orelse continue;
        const result = edges[i].result orelse return error.ApplicationGraphMismatch;
        const result_node = graph.get(result) orelse return error.ApplicationGraphMismatch;
        const descriptor = result_node.descriptor orelse return error.ApplicationGraphMismatch;
        const caller = containingFunctionFromScope(graph, .{ .index = @intCast(i) }) orelse
            return error.ApplicationGraphMismatch;
        const application_identity = try semanticReference(graph, .{ .index = @intCast(i) });
        const slot = seen.getOrPut(alloc, application_identity.node) catch return error.OutOfMemory;
        if (slot.found_existing) return error.ApplicationGraphMismatch;
        try projections.append(alloc, .{
            .relation = try semanticReference(graph, relation),
            .application = application_identity,
            .value = try semanticReference(graph, result),
            .subject = if (edges[i].subject) |subject|
                try semanticReference(graph, subject)
            else
                null,
            .descriptor = descriptor,
            .caller = try semanticReference(graph, caller),
        });
    }
    return projections.toOwnedSlice(alloc) catch return error.OutOfMemory;
}

fn expectedApplications(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError!std.AutoHashMapUnmanaged(u32, ExpectedApplication) {
    var expected: std.AutoHashMapUnmanaged(u32, ExpectedApplication) = .empty;
    errdefer expected.deinit(alloc);
    const projections = try checkedApplicationProjections(alloc, graph);
    defer alloc.free(projections);
    for (projections) |projection| {
        const slot = expected.getOrPut(alloc, projection.application.node) catch return error.OutOfMemory;
        if (slot.found_existing) return error.ApplicationGraphMismatch;
        slot.value_ptr.* = .{
            .application = projection.application,
            .relation = projection.relation,
            .value = projection.value,
            .subject = projection.subject,
            .descriptor = projection.descriptor,
            .caller = projection.caller,
        };
    }
    return expected;
}

/// Verify function and application identities without recovering either from
/// linker/debug names.
pub fn validateModuleRegions(
    regions: []const Region,
    graph: *const semantic_graph.SemanticGraph,
    m: dnir.Module,
    alloc: std.mem.Allocator,
) RegionGraphError!void {
    var expected = try expectedApplications(alloc, graph);
    defer expected.deinit(alloc);

    if (regions.len != m.functions.len) return error.EmitOrderMismatch;
    for (m.functions, 0..) |f, i| {
        const region = &regions[i];
        if (!optionalSemanticRefEql(region.func_identity, f.semantic_identity)) return error.StableIdMismatch;

        for (region.nodes) |node| {
            if (!hasAnyApplicationIdentity(node)) continue;
            if (!hasCompleteApplicationIdentity(node)) return error.IncompleteApplicationIdentity;
            const application = expected.getPtr(node.application_id.?.node) orelse
                return error.ApplicationGraphMismatch;
            if (!application.application.eql(node.application_id.?) or
                !application.relation.eql(node.relation_id.?) or
                !application.value.eql(node.value_id.?) or
                !optionalSemanticRefEql(application.subject, node.subject_id) or
                node.descriptor == null or
                !application.descriptor.eql(node.descriptor.?))
            {
                return error.ApplicationGraphMismatch;
            }
            if (region.func_identity == null or !application.caller.eql(region.func_identity.?)) {
                return error.ApplicationGraphMismatch;
            }
            application.uses += 1;
        }
    }

    var iterator = expected.valueIterator();
    while (iterator.next()) |application| {
        if (application.uses != 1) return error.CallGraphMismatch;
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

test "region_graph: validates checked applications by identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const dnir_lower = @import("dnir_lower.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\read: i64 = (subject: i64)
        \\    subject
        \\main: i64 = ()
        \\    42:read()
    ;
    var lex = Lexer.init(src, "region.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "region.duo");
    const m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);

    const regions = try buildModuleRegions(alloc, m, &g);
    defer freeModuleRegions(alloc, regions);
    try validateModuleRegions(regions, &g, m, alloc);

    var main_region: ?*const Region = null;
    for (regions) |*r| {
        if (std.mem.eql(u8, r.func_name, "main")) main_region = r;
        try std.testing.expect(r.func_identity != null);
    }
    const mr = main_region orelse return error.TestExpectedEqual;
    var saw_call = false;
    for (mr.nodes) |node| {
        if (node.kind != .call) continue;
        try std.testing.expect(hasCompleteApplicationIdentity(node));
        try std.testing.expect(node.subject_id != null);
        try std.testing.expect(node.descriptor.?.eql(.i64));
        saw_call = true;
    }
    try std.testing.expect(saw_call);

    const census = try semanticNameReconstructionCensus(alloc, regions, &g);
    try std.testing.expectEqual(@as(usize, 1), census.required_checked_applications);
    try std.testing.expectEqual(@as(usize, 1), census.checked_call_nodes);
    try std.testing.expectEqual(@as(usize, 0), census.incomplete_lineage);
    try std.testing.expectEqual(@as(usize, 0), census.legacy_symbol_bridges);
    try std.testing.expectEqual(@as(usize, 0), census.legacy_function_name_bridges);

    for (regions) |*region| {
        for (region.nodes) |*node| {
            if (node.kind != .call or !hasCompleteApplicationIdentity(node.*)) continue;
            const subject_id = node.subject_id;
            node.subject_id = null;
            try std.testing.expectError(
                error.ApplicationGraphMismatch,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.subject_id = subject_id;
            const descriptor = node.descriptor;
            node.descriptor = .i32;
            try std.testing.expectError(
                error.ApplicationGraphMismatch,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.descriptor = descriptor;
            const application_id = node.application_id;
            node.application_id = null;
            const invalid_census = try semanticNameReconstructionCensus(alloc, regions, &g);
            try std.testing.expectEqual(@as(usize, 1), invalid_census.incomplete_lineage);
            try std.testing.expectError(
                error.IncompleteApplicationIdentity,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.application_id = application_id;
            node.relation_id = null;
            node.application_id = null;
            node.value_id = null;
            node.subject_id = null;
            node.realization_start = null;
            const missing_census = try semanticNameReconstructionCensus(alloc, regions, &g);
            try std.testing.expectEqual(@as(usize, 1), missing_census.missing_lineage);
            try std.testing.expectError(
                error.CallGraphMismatch,
                validateModuleRegions(regions, &g, m, alloc),
            );
            return;
        }
    }
    return error.TestExpectedEqual;
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
