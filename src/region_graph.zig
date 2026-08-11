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
    relation: ?semantic_graph.id = null,
    application: ?semantic_graph.id = null,
    value: ?semantic_graph.id = null,
    subject: ?semantic_graph.id = null,
    descriptor: ?types.ResolvedType = null,
    realization_start: ?u32 = null,
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
    function: ?semantic_graph.id,
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

/// Derived region scheduling data plus the borrowed graph whose dense ids it
/// references. The pointer is physical residency context only: it grants no
/// authority and creates no identity.
pub const Projection = struct {
    graph: ?*const semantic_graph.SemanticGraph,
    regions: []Region,

    pub fn deinit(self: Projection, alloc: std.mem.Allocator) void {
        for (self.regions) |*region| region.deinit(alloc);
        alloc.free(self.regions);
    }
};

fn deinitNodeFields(alloc: std.mem.Allocator, node: Node) void {
    if (node.label) |label| alloc.free(label);
    if (node.callee) |callee| alloc.free(callee);
}

fn deinitNodeFieldsSlice(alloc: std.mem.Allocator, nodes: []const Node) void {
    for (nodes) |node| deinitNodeFields(alloc, node);
}

fn appendOwnedNode(
    alloc: std.mem.Allocator,
    nodes: *std.ArrayListUnmanaged(Node),
    node: Node,
) !void {
    nodes.append(alloc, node) catch |err| {
        deinitNodeFields(alloc, node);
        return err;
    };
}

pub fn buildFromDnirFunction(
    alloc: std.mem.Allocator,
    f: dnir.Function,
) !Region {
    var nodes: std.ArrayListUnmanaged(Node) = .empty;
    errdefer {
        deinitNodeFieldsSlice(alloc, nodes.items);
        nodes.deinit(alloc);
    }
    var edges: std.ArrayListUnmanaged(Edge) = .empty;
    errdefer edges.deinit(alloc);

    var next_id: u32 = 0;
    const region_id = next_id;
    next_id += 1;
    try appendOwnedNode(alloc, &nodes, .{
        .id = region_id,
        .kind = .region,
        .label = try alloc.dupe(u8, f.name),
    });

    var temp_node: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer temp_node.deinit(alloc);

    for (f.params, 0..) |p, i| {
        const pid = next_id;
        next_id += 1;
        try appendOwnedNode(alloc, &nodes, .{
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

            const projected = blk: {
                var node: Node = .{
                    .id = nid,
                    .kind = kind,
                    .relation = ins.relation,
                    .application = ins.application,
                    .value = ins.value,
                    .subject = ins.subject,
                    .descriptor = if (ins.application != null) ins.ty else null,
                    .realization_start = ins.realization_start,
                    .dnir_temp = ins.result,
                };
                errdefer deinitNodeFields(alloc, node);
                if (kind == .record and ins.record.len > 0) {
                    node.label = try alloc.dupe(u8, ins.record);
                }
                if (kind == .hardware) {
                    if (dnir_hardware.intrinsicOfOp(ins.op, ins.hw)) |hw| {
                        node.label = try alloc.dupe(u8, hw.duoName());
                    }
                }
                if (kind == .call and ins.callee.len > 0) {
                    node.callee = try alloc.dupe(u8, ins.callee);
                }
                break :blk node;
            };
            try appendOwnedNode(alloc, &nodes, projected);

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

    const func_name = try alloc.dupe(u8, f.name);
    errdefer alloc.free(func_name);
    const owned_nodes = try nodes.toOwnedSlice(alloc);
    errdefer {
        deinitNodeFieldsSlice(alloc, owned_nodes);
        alloc.free(owned_nodes);
    }
    const owned_edges = try edges.toOwnedSlice(alloc);
    errdefer alloc.free(owned_edges);

    return .{
        .func_name = func_name,
        .function = f.id,
        .nodes = owned_nodes,
        .edges = owned_edges,
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
) !Projection {
    var regions: std.ArrayListUnmanaged(Region) = .empty;
    errdefer {
        for (regions.items) |*r| r.deinit(alloc);
        regions.deinit(alloc);
    }
    for (m.functions) |f| {
        var region = try buildFromDnirFunction(alloc, f);
        regions.append(alloc, region) catch |err| {
            region.deinit(alloc);
            return err;
        };
    }
    return .{
        .graph = m.graph,
        .regions = try regions.toOwnedSlice(alloc),
    };
}

pub fn freeModuleRegions(alloc: std.mem.Allocator, projection: Projection) void {
    projection.deinit(alloc);
}

pub const RegionGraphError = error{
    EmitOrderMismatch,
    FunctionFactMismatch,
    ResidencyMismatch,
    CallGraphMismatch,
    IncompleteApplicationFacts,
    ApplicationGraphMismatch,
    OutOfMemory,
};

pub fn findRegion(projection: Projection, func_name: []const u8) ?*const Region {
    for (projection.regions) |*r| {
        if (std.mem.eql(u8, r.func_name, func_name)) return r;
    }
    return null;
}

pub fn applicationFactsPresent(node: Node) bool {
    return node.relation != null or node.application != null or node.value != null or
        node.subject != null or node.realization_start != null;
}

pub fn applicationFactsComplete(node: Node) bool {
    return node.relation != null and node.application != null and node.value != null and node.realization_start != null;
}

fn optionalEql(a: ?semantic_graph.id, b: ?semantic_graph.id) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.meta.eql(a.?, b.?);
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

/// Measure the application-fact boundary represented by region nodes. Partial
/// facts fail closed; they are never completed from the symbol. A call without
/// graph facts remains an explicit legacy symbol bridge.
pub fn semanticNameReconstructionCensus(
    alloc: std.mem.Allocator,
    projection: Projection,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError!SemanticNameReconstructionCensus {
    if (projection.graph != graph) return error.ResidencyMismatch;
    var census: SemanticNameReconstructionCensus = .{};
    const uses = alloc.alloc(u32, graph.nodes.items.len) catch return error.OutOfMemory;
    defer alloc.free(uses);
    @memset(uses, 0);
    census.required_checked_applications = graph.applications().len;

    for (projection.regions) |region| {
        if (region.function == null) census.legacy_function_name_bridges += 1;
        for (region.nodes) |node| {
            if (!applicationFactsPresent(node)) {
                if (node.kind == .call) census.legacy_symbol_bridges += 1;
                continue;
            }
            if (!applicationFactsComplete(node)) {
                census.incomplete_lineage += 1;
                continue;
            }
            if (node.kind == .call) {
                census.checked_call_nodes += 1;
            } else {
                census.checked_realization_nodes += 1;
            }
            if (graph.application(node.application.?)) |application| {
                if (application.application >= uses.len) return error.ApplicationGraphMismatch;
                uses[application.application] += 1;
            }
        }
    }
    for (graph.applications()) |stored| {
        const application = graph.application(stored.application) orelse
            return error.ApplicationGraphMismatch;
        if (application.application >= uses.len) return error.ApplicationGraphMismatch;
        if (uses[application.application] == 0) census.missing_lineage += 1;
    }
    return census;
}

/// Count direct intra-module callees with complete graph application facts.
pub fn countDirectCallees(region: *const Region) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind == .call and applicationFactsComplete(node)) n += 1;
    }
    return n;
}

/// Verify graph ids and application facts without recovering either from
/// linker/debug names.
pub fn validateModuleRegions(
    projection: Projection,
    graph: *const semantic_graph.SemanticGraph,
    m: dnir.Module,
    alloc: std.mem.Allocator,
) RegionGraphError!void {
    if (projection.graph != graph or m.graph != graph) return error.ResidencyMismatch;
    const uses = alloc.alloc(u32, graph.nodes.items.len) catch return error.OutOfMemory;
    defer alloc.free(uses);
    @memset(uses, 0);

    if (projection.regions.len != m.functions.len) return error.EmitOrderMismatch;
    for (m.functions, 0..) |f, i| {
        const region = &projection.regions[i];
        if (!optionalEql(region.function, f.id)) return error.FunctionFactMismatch;

        for (region.nodes) |node| {
            if (!applicationFactsPresent(node)) continue;
            if (!applicationFactsComplete(node)) return error.IncompleteApplicationFacts;
            const application = graph.application(node.application.?) orelse
                return error.ApplicationGraphMismatch;
            const results = graph.applicationResults(application.application) orelse
                return error.ApplicationGraphMismatch;
            if (results.len != 1) return error.ApplicationGraphMismatch;
            if (!std.meta.eql(application.application, node.application.?) or
                !std.meta.eql(application.relation, node.relation.?) or
                !std.meta.eql(results[0], node.value.?) or
                !optionalEql(application.subject, node.subject) or
                node.descriptor == null or
                !application.descriptor.eql(node.descriptor.?))
            {
                return error.ApplicationGraphMismatch;
            }
            if (region.function == null or !std.meta.eql(application.caller, region.function.?)) {
                return error.ApplicationGraphMismatch;
            }
            if (application.application >= uses.len) return error.ApplicationGraphMismatch;
            uses[application.application] += 1;
        }
    }

    for (graph.applications()) |stored| {
        const application = graph.application(stored.application) orelse
            return error.ApplicationGraphMismatch;
        if (application.application >= uses.len) return error.ApplicationGraphMismatch;
        if (uses[application.application] != 1) return error.CallGraphMismatch;
    }
}

/// Attach deferred candidate counts and committed `realizes_as` edges (Gate L → IR).
pub fn attachRealizationPlan(
    alloc: std.mem.Allocator,
    projection: Projection,
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
        for (projection.regions) |*r| {
            try attachRealizesAsForRecord(alloc, r, record_name, sel.id);
        }
    }
    if (pending > 0) {
        for (projection.regions) |*r| r.legal_realization_candidates = pending;
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

    const borrowed_nodes = region.nodes.len;
    var new_nodes: std.ArrayListUnmanaged(Node) = .empty;
    errdefer {
        if (new_nodes.items.len > borrowed_nodes) {
            deinitNodeFieldsSlice(alloc, new_nodes.items[borrowed_nodes..]);
        }
        new_nodes.deinit(alloc);
    }
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
        try appendOwnedNode(alloc, &new_nodes, .{
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
            try appendOwnedNode(alloc, &new_nodes, .{
                .id = target_id,
                .kind = .realization,
                .label = try alloc.dupe(u8, realization_id),
            });
            try new_edges.append(alloc, .{ .from = node.id, .to = target_id, .kind = .realizes_as });
            attached = true;
            break;
        }
    }
    if (!attached) {
        new_nodes.deinit(alloc);
        new_edges.deinit(alloc);
        return;
    }

    const owned_nodes = try new_nodes.toOwnedSlice(alloc);
    errdefer {
        deinitNodeFieldsSlice(alloc, owned_nodes[borrowed_nodes..]);
        alloc.free(owned_nodes);
    }
    const owned_edges = try new_edges.toOwnedSlice(alloc);
    errdefer alloc.free(owned_edges);

    const old_nodes = region.nodes;
    const old_edges = region.edges;
    region.nodes = owned_nodes;
    region.edges = owned_edges;
    alloc.free(old_nodes);
    alloc.free(old_edges);
}

/// Count hardware descriptor nodes in a region.
pub fn countHardwareNodes(region: *const Region) usize {
    var n: usize = 0;
    for (region.nodes) |node| {
        if (node.kind == .hardware) n += 1;
    }
    return n;
}

/// Find the private region coordinate for the first matching hardware label.
fn hardwareCoordinate(region: *const Region, intrinsic_label: []const u8) ?u32 {
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
pub fn attachDeferredRealizations(projection: Projection, plan: *const realization.ModuleRealizations) void {
    var pending: u32 = 0;
    for (plan.variables) |v| {
        if (v.selected_index != null) continue;
        pending += @intCast(realization.legalCandidateCount(&v));
    }
    for (projection.regions) |*r| r.legal_realization_candidates = pending;
}

pub fn buildValidatedModuleRegions(
    alloc: std.mem.Allocator,
    m: dnir.Module,
    graph: *const semantic_graph.SemanticGraph,
) RegionGraphError!Projection {
    const projection = try buildModuleRegions(alloc, m);
    errdefer freeModuleRegions(alloc, projection);
    try validateModuleRegions(projection, graph, m, alloc);
    return projection;
}

test "region_graph: validates checked application facts" {
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
    defer dnir.deinitModule(alloc, m);

    const regions = try buildModuleRegions(alloc, m);
    defer freeModuleRegions(alloc, regions);
    try validateModuleRegions(regions, &g, m, alloc);

    var main_region: ?*const Region = null;
    for (regions.regions) |*r| {
        if (std.mem.eql(u8, r.func_name, "main")) main_region = r;
        try std.testing.expect(r.function != null);
    }
    const mr = main_region orelse return error.TestExpectedEqual;
    var saw_call = false;
    for (mr.nodes) |node| {
        if (node.kind != .call) continue;
        try std.testing.expect(applicationFactsComplete(node));
        try std.testing.expect(node.subject != null);
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

    const stored_application = g.application_facts.items[0].application;
    g.application_facts.items[0].application = std.math.maxInt(semantic_graph.id);
    try std.testing.expectError(
        error.ApplicationGraphMismatch,
        semanticNameReconstructionCensus(alloc, regions, &g),
    );
    try std.testing.expectError(
        error.ApplicationGraphMismatch,
        validateModuleRegions(regions, &g, m, alloc),
    );
    g.application_facts.items[0].application = stored_application;

    for (regions.regions) |*region| {
        for (region.nodes) |*node| {
            if (node.kind != .call or !applicationFactsComplete(node.*)) continue;
            const subject = node.subject;
            node.subject = null;
            try std.testing.expectError(
                error.ApplicationGraphMismatch,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.subject = subject;
            const descriptor = node.descriptor;
            node.descriptor = .i32;
            try std.testing.expectError(
                error.ApplicationGraphMismatch,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.descriptor = descriptor;
            const application = node.application;
            node.application = null;
            const invalid_census = try semanticNameReconstructionCensus(alloc, regions, &g);
            try std.testing.expectEqual(@as(usize, 1), invalid_census.incomplete_lineage);
            try std.testing.expectError(
                error.IncompleteApplicationFacts,
                validateModuleRegions(regions, &g, m, alloc),
            );
            node.application = application;
            node.relation = null;
            node.application = null;
            node.value = null;
            node.subject = null;
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

test "region_graph: function projection releases every owned field on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const function: dnir.Function = .{
                .name = "probe",
                .ret = .i64,
                .params = &.{.{ .name = "argument", .ty = .i64 }},
                .blocks = &.{.{ .instrs = &.{
                    .{ .op = .init_record, .record = "Record", .result = 1 },
                    .{ .op = .hw_unary, .hw = .popcount, .lhs = .{ .temp = 0 }, .result = 2 },
                    .{ .op = .call_direct, .callee = "callee", .lhs = .{ .temp = 2 }, .result = 3 },
                    .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
                } }},
            };
            var region = try buildFromDnirFunction(alloc, function);
            defer region.deinit(alloc);
        }
    }.run, .{});
}

test "region_graph: realization attachment is transactional on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const function: dnir.Function = .{
                .name = "probe",
                .ret = .any,
                .blocks = &.{.{ .instrs = &.{
                    .{ .op = .init_record, .record = "Record", .result = 0 },
                    .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .any },
                } }},
            };
            var region = try buildFromDnirFunction(alloc, function);
            defer region.deinit(alloc);

            const nodes = region.nodes;
            const edges = region.edges;
            attachRealizesAsForRecord(alloc, &region, "Record", "dense") catch |err| {
                try std.testing.expectEqual(nodes.ptr, region.nodes.ptr);
                try std.testing.expectEqual(nodes.len, region.nodes.len);
                try std.testing.expectEqual(edges.ptr, region.edges.ptr);
                try std.testing.expectEqual(edges.len, region.edges.len);
                try std.testing.expectEqualStrings("Record", region.nodes[1].label.?);
                return err;
            };

            try std.testing.expectEqual(nodes.len + 1, region.nodes.len);
            try std.testing.expectEqual(edges.len + 1, region.edges.len);
            try std.testing.expectEqualStrings("dense", region.nodes[region.nodes.len - 1].label.?);
        }
    }.run, .{});
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
    const regions = try buildModuleRegions(alloc, m);
    defer freeModuleRegions(alloc, regions);
    const main = findRegion(regions, "main") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(dnir.HardwareTier.scalar, main.hardware_tier);
    try std.testing.expect(countHardwareNodesLabeled(main, "fence") >= 1);
    try std.testing.expect(countHardwareNodesLabeled(main, "popcount") >= 1);
}
