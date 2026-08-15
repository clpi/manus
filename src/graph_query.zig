//! Bounded semantic-graph projections for compiler, LSP, and MCP consumers.
//!
//! Production queries accept exact graph ids only. Human name/path resolution
//! belongs to an outer UI locator step — never inside these projections.
const std = @import("std");
const semantic_graph = @import("semantic_graph.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const types = @import("types.zig");

pub fn requireEntity(graph: *const semantic_graph.SemanticGraph, e: semantic_graph.id) !*const semantic_graph.Node {
    return graph.get(e) orelse return error.MissingGraphEntity;
}

fn requireCallable(graph: *const semantic_graph.SemanticGraph, callable: semantic_graph.id) !void {
    if (!graph.callable(callable)) return error.InvalidFunctionEntity;
}

/// Migration alias — prefer `requireCallable`.
fn requireFunction(graph: *const semantic_graph.SemanticGraph, function: semantic_graph.id) !void {
    try requireCallable(graph, function);
}

/// Exact graph entity by id.
pub fn entity(graph: *const semantic_graph.SemanticGraph, e: semantic_graph.id) ?*const semantic_graph.Node {
    return graph.entityOf(e);
}

/// Checked application fact by application id.
pub fn application(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?*const semantic_graph.ApplicationFact {
    return graph.application(occurrence);
}

/// Relation id selected for one application occurrence.
pub fn relation(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?semantic_graph.id {
    return graph.applicationRelation(occurrence);
}

/// Subject value id for one application occurrence.
pub fn subject(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?semantic_graph.id {
    return graph.applicationSubject(occurrence);
}

/// Operand value ids — borrowed packed range (`law.fact.locality`).
pub fn operand(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?[]const semantic_graph.id {
    return graph.applicationArguments(occurrence);
}

/// Result value ids — borrowed packed range (`law.fact.locality`).
pub fn result(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?[]const semantic_graph.id {
    return graph.applicationResults(occurrence);
}

pub fn effect(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) semantic_graph.Card {
    const fact = graph.application(occurrence) orelse return .unknown;
    return fact.effect;
}

pub fn authority(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) semantic_graph.Card {
    const fact = graph.application(occurrence) orelse return .unknown;
    return fact.authority;
}

pub fn witness(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) semantic_graph.Card {
    const fact = graph.application(occurrence) orelse return .unknown;
    return fact.witness;
}

pub fn realization(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) semantic_graph.Card {
    const fact = graph.application(occurrence) orelse return .unknown;
    return fact.realization;
}

pub fn target(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) semantic_graph.Card {
    const fact = graph.application(occurrence) orelse return .unknown;
    return fact.target;
}

/// Evaluation stage when known on the application. Null is unknown.
pub fn stage(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?semantic_algebra.Stage {
    _ = graph.application(occurrence) orelse return null;
    return graph.applicationStage(occurrence);
}

/// Descriptor entity projection by exact id.
pub fn descriptor(
    graph: *const semantic_graph.SemanticGraph,
    e: semantic_graph.id,
) !*const semantic_graph.Node {
    const node = try requireEntity(graph, e);
    if (!graph.hasDescriptorFacts(e)) return error.InvalidDescriptorEntity;
    return node;
}

/// Member descriptor ids under one home descriptor entity.
pub fn member(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    home_id: semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.membersOf(home_id, alloc);
}

/// Capture binding ids for one callable entity.
pub fn capture(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    callable: semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.capturesOf(callable, alloc);
}

/// Home context id for one entity.
pub fn home(graph: *const semantic_graph.SemanticGraph, e: semantic_graph.id) ?semantic_graph.id {
    return graph.homeOf(e);
}

/// Callable/relation entities directly under one home id.
pub fn callablesInHome(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    home_id: semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.callablesInHome(home_id, alloc);
}

/// Migration alias — prefer `callablesInHome` (`law.module.zero`).
pub fn functionsInModule(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    module: semantic_graph.id,
) ![]const semantic_graph.id {
    return callablesInHome(graph, alloc, module);
}

/// Exact entities with a `.binding` edge to one binding id.
pub fn users(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    binding: semantic_graph.id,
) ![]const semantic_graph.id {
    var out: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    errdefer out.deinit(alloc);
    try graph.usersOf(binding, &out);
    return try out.toOwnedSlice(alloc);
}

/// Table/record descriptor home ids in resident graph order.
pub fn tableShapes(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
) ![]const semantic_graph.id {
    return graph.tableDescriptorHomes(alloc);
}

/// Enum descriptor home ids in resident graph order.
pub fn enumShapes(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
) ![]const semantic_graph.id {
    return graph.enumDescriptorHomes(alloc);
}

/// Projection specialization value ids for one application occurrence.
pub fn projection(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    occurrence: semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.projectionsOf(occurrence, alloc);
}

/// Published `.descriptor_ref` targets for one descriptor entity.
pub const DescriptorRef = struct {
    entity: semantic_graph.id,
    inline_ref: bool,
};

pub fn descriptorRef(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    descriptor_id: semantic_graph.id,
) ![]DescriptorRef {
    const refs = try graph.descriptorRefsOf(descriptor_id, alloc);
    defer alloc.free(refs);
    var out: std.ArrayListUnmanaged(DescriptorRef) = .empty;
    errdefer out.deinit(alloc);
    for (refs) |entry| {
        try out.append(alloc, .{ .entity = entry.target, .inline_ref = entry.inline_ref });
    }
    return try out.toOwnedSlice(alloc);
}

/// Descriptor recursion derived from published `.descriptor_ref` edges only.
pub fn descriptorRecursion(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    descriptor_id: semantic_graph.id,
) !semantic_graph.Recursion {
    return graph.descriptorRecursion(alloc, descriptor_id);
}

/// Source span provenance for one entity (display/diagnostic projection).
pub fn provenance(
    graph: *const semantic_graph.SemanticGraph,
    e: semantic_graph.id,
) ?semantic_graph.SpanRef {
    return graph.provenanceOf(e);
}

/// Exact application occurrences owned by one caller/home entity — borrowed
/// slice (`law.fact.locality`, `law.zero.copy.graph.views`).
pub fn applicationsIn(
    graph: *const semantic_graph.SemanticGraph,
    caller: semantic_graph.id,
) ![]const semantic_graph.id {
    try requireCallable(graph, caller);
    if (graph.unresolvedApplicationCount(caller) != 0) return error.UnresolvedApplication;
    const owned = graph.applicationsInCaller(caller);
    for (owned) |occurrence| {
        if (graph.application(occurrence) == null) return error.UnresolvedApplication;
    }
    return owned;
}

/// Exact relations invoked from one caller/home entity.
pub fn relationsReferencedBy(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    caller: semantic_graph.id,
) ![]const semantic_graph.id {
    var out: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    errdefer out.deinit(alloc);
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(alloc);

    const owned = try applicationsIn(graph, caller);
    for (owned) |occurrence| {
        const selected = graph.applicationRelation(occurrence) orelse
            return error.UnresolvedApplication;
        if (seen.contains(selected)) continue;
        try seen.put(alloc, selected, {});
        try out.append(alloc, selected);
    }
    return try out.toOwnedSlice(alloc);
}

/// Migration alias — prefer `relationsReferencedBy` (`law.application.consumer`).
pub fn calleesOf(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    function: semantic_graph.id,
) ![]const semantic_graph.id {
    return relationsReferencedBy(graph, alloc, function);
}

/// Migration alias — prefer `applicationsIn` (`law.application.consumer`).
pub fn callsIn(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    function: semantic_graph.id,
) ![]const semantic_graph.id {
    _ = alloc;
    return applicationsIn(graph, function);
}

/// Graph-derived function emit order (callees before callers). See `SemanticGraph.moduleFunctionEmitOrder`.
pub fn functionEmitOrder(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    functions: []const semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.moduleFunctionEmitOrder(alloc, functions);
}

test "graph_query: calls and callees from lifted graph" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\helper: i64 = ()
        \\    1
        \\entry: i64 = ()
        \\    helper()
    ;
    var lex = Lexer.init(src, "query.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    const module = try g.liftModuleWithCheckedCalls(&mod, &checked, "query.id");

    const functions = try g.functionsInModule(module, alloc);
    defer alloc.free(functions);
    try std.testing.expectEqual(@as(usize, 2), functions.len);
    const helper = g.resolveInHome(module, "helper", .func) orelse return error.TestExpectedEqual;
    const entry = g.resolveInHome(module, "entry", .func) orelse return error.TestExpectedEqual;

    const module_functions = try functionsInModule(&g, alloc, module);
    defer alloc.free(module_functions);
    try std.testing.expectEqualSlices(semantic_graph.id, functions, module_functions);

    const calls = try applicationsIn(&g, entry);
    try std.testing.expect(calls.len == 1);
    const call = application(&g, calls[0]) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(helper, g.applicationRelation(call.application).?);
    try std.testing.expectEqual(entry, g.applicationCaller(call.application).?);
    try std.testing.expectEqual(helper, relation(&g, calls[0]).?);
    const helper_users = try users(&g, alloc, helper);
    defer alloc.free(helper_users);
    try std.testing.expectEqual(@as(usize, 1), helper_users.len);
    try std.testing.expectEqual(calls[0], helper_users[0]);
    // `helper: i64 = () 1` applies nothing, captures nothing, reads no member
    // and is not foreign, so the effect pass in `semantic_graph` publishes
    // known-absent rather than not-yet-known. These two read `.unknown` for as
    // long as the two fields had no write site at all.
    try std.testing.expect(effect(&g, calls[0]) == .none);
    try std.testing.expect(authority(&g, calls[0]) == .none);
    try std.testing.expect(witness(&g, calls[0]) == .unknown);
    try std.testing.expect(realization(&g, calls[0]) == .unknown);
    try std.testing.expect(target(&g, calls[0]) == .unknown);
    try std.testing.expect(stage(&g, calls[0]) == null);
    try std.testing.expect(call.effect == .none);
    try std.testing.expect(call.authority == .none);
    try std.testing.expect(call.witness == .unknown);
    try std.testing.expect(call.target == .unknown);
    try std.testing.expect(call.realization == .unknown);

    const callees = try relationsReferencedBy(&g, alloc, entry);
    defer alloc.free(callees);
    try std.testing.expect(callees.len == 1);
    try std.testing.expectEqual(helper, callees[0]);

    try std.testing.expectError(error.MissingGraphEntity, requireEntity(&g, @intCast(g.nodes.items.len)));

    const not_function = try g.addChild(entry, .{
        .kind = .value,
        .span = .{ .file = "query.id", .start = 5, .end = 5 },
    });
    try std.testing.expectError(error.InvalidFunctionEntity, callsIn(&g, alloc, not_function));
    try std.testing.expectError(error.InvalidFunctionEntity, calleesOf(&g, alloc, not_function));

    var unresolved = semantic_graph.SemanticGraph.init(alloc);
    defer unresolved.deinit();
    const unresolved_module = try unresolved.liftModuleWithCalls(&mod, "query.id");
    const unresolved_functions = try unresolved.functionsInModule(unresolved_module, alloc);
    defer alloc.free(unresolved_functions);
    try std.testing.expectEqual(@as(usize, 2), unresolved_functions.len);
    const unresolved_entry = unresolved.resolveInHome(unresolved_module, "entry", .func) orelse
        return error.TestExpectedEqual;
    try std.testing.expectError(error.UnresolvedApplication, callsIn(&unresolved, alloc, unresolved_entry));
    try std.testing.expectError(error.UnresolvedApplication, calleesOf(&unresolved, alloc, unresolved_entry));

    const relation_entity = try g.addChild(entry, .{
        .kind = .relation,
        .span = .{ .file = "query.id", .start = 6, .end = 5 },
        .result_descriptor = .i64,
    });
    const occurrence = g.applications()[0].application;
    var binding: ?usize = null;
    for (g.edges.items, 0..) |edge, i| {
        if (edge.from == occurrence and edge.kind == .binding) {
            binding = i;
            break;
        }
    }
    g.edges.items[binding.?].to = relation_entity;
    const relation_callees = try calleesOf(&g, alloc, entry);
    defer alloc.free(relation_callees);
    try std.testing.expectEqualSlices(semantic_graph.id, &.{relation_entity}, relation_callees);

    const projections = try projection(&g, alloc, calls[0]);
    defer alloc.free(projections);
    try std.testing.expectEqual(@as(usize, 0), projections.len);

    g.edges.items[binding.?].to = not_function;
    try std.testing.expectError(error.UnresolvedApplication, callsIn(&g, alloc, entry));
    try std.testing.expectError(error.UnresolvedApplication, calleesOf(&g, alloc, entry));
}

test "graph_query: descriptor requires one exact record id" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const record = try graph.addNode(.{
        .kind = .table_shape,
        .span = .{ .file = "record.id", .start = 1, .end = 1 },
        .name = "point",
        .storage_class = .native,
        .shape_id = 42,
        .descriptor_state = .sealed,
    });
    const value = try graph.addNode(.{
        .kind = .value,
        .span = .{ .file = "record.id", .start = 2, .end = 1 },
        .name = "point",
    });

    const shape = try descriptor(&graph, record);
    try std.testing.expectEqual(graph.get(record).?, shape);
    try std.testing.expectEqualStrings("point", shape.name.?);
    try std.testing.expectEqual(@as(?u64, 42), shape.shape_id);
    try std.testing.expectError(error.InvalidDescriptorEntity, descriptor(&graph, value));
    try std.testing.expectError(
        error.MissingGraphEntity,
        descriptor(&graph, @intCast(graph.nodes.items.len)),
    );
}

test "graph_query: descriptor refs and recursion from exact ids" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    const module = try g.addNode(.{ .kind = .module, .span = .{ .file = "rec.id", .start = 0, .end = 0 } });
    const node_shape = try g.addChild(module, .{
        .kind = .table_shape,
        .span = .{ .file = "rec.id", .start = 1, .end = 1 },
        .name = "Node",
        .storage_class = .native,
        .descriptor_state = .sealed,
    });

    const node: types.ResolvedType = .{ .@"struct" = .{ .name = "Node" } };
    const next = try alloc.create(types.ResolvedType);
    next.* = node;
    const fields = try alloc.alloc(types.FieldType, 2);
    fields[0] = .{ .name = "value", .typ = .i64 };
    fields[1] = .{ .name = "next", .typ = .{ .pointer = next } };
    const table_type: types.ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .native,
        .is_sealed = true,
    } };

    try g.publishDescriptorRefEdges(node_shape, table_type);
    const refs = try descriptorRef(&g, alloc, node_shape);
    defer alloc.free(refs);
    try std.testing.expectEqual(@as(usize, 1), refs.len);
    try std.testing.expectEqual(node_shape, refs[0].entity);
    try std.testing.expect(!refs[0].inline_ref);
    try std.testing.expectEqual(semantic_graph.Recursion.indirect_pointer, try descriptorRecursion(&g, alloc, node_shape));
    try std.testing.expectError(error.InvalidDescriptorEntity, descriptorRef(&g, alloc, module));
}
