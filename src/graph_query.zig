//! Bounded semantic-graph projections for compiler, LSP, and MCP consumers.
const std = @import("std");
const ast = @import("ast.zig");
const dnir = @import("native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const region_graph = @import("region_graph.zig");
const semantic_graph = @import("semantic_graph.zig");

fn requireFunction(graph: *const semantic_graph.SemanticGraph, function: semantic_graph.id) !void {
    const fact = graph.get(function) orelse return error.InvalidFunctionEntity;
    if (fact.kind != .func) return error.InvalidFunctionEntity;
}

/// Exact relations invoked directly from one function entity.
pub fn calleesOf(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    function: semantic_graph.id,
) ![]const semantic_graph.id {
    var out: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    errdefer out.deinit(alloc);
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(alloc);

    try requireFunction(graph, function);
    if (graph.unresolvedApplicationCount(function) != 0) return error.UnresolvedApplication;
    for (graph.applications()) |stored| {
        const fact = graph.application(stored.application) orelse return error.UnresolvedApplication;
        if (fact.caller != function) continue;
        if (seen.contains(fact.relation)) continue;
        try seen.put(alloc, fact.relation, {});
        try out.append(alloc, fact.relation);
    }
    return try out.toOwnedSlice(alloc);
}

/// Exact call occurrences inside one function entity.
pub fn callsIn(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    function: semantic_graph.id,
) ![]semantic_graph.id {
    var out: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    errdefer out.deinit(alloc);

    try requireFunction(graph, function);
    if (graph.unresolvedApplicationCount(function) != 0) return error.UnresolvedApplication;
    for (graph.applications()) |stored| {
        const fact = graph.application(stored.application) orelse return error.UnresolvedApplication;
        if (fact.caller != function) continue;
        try out.append(alloc, fact.application);
    }
    return try out.toOwnedSlice(alloc);
}

/// Record layout facts projected from one exact graph entity.
pub const RecordRepresentation = struct {
    id: semantic_graph.id,
    name: []const u8,
    shape_fingerprint: ?u64,
    storage_class: ?[]const u8,
};

pub fn representationForRecord(
    graph: *const semantic_graph.SemanticGraph,
    record: semantic_graph.id,
) !RecordRepresentation {
    const node = graph.get(record) orelse return error.InvalidRecordEntity;
    if (node.kind != .table_shape) return error.InvalidRecordEntity;
    const storage = if (node.storage_class) |sc| @import("types.zig").storageClassName(sc) else null;
    return .{
        .id = record,
        .name = node.name orelse return error.MissingRecordName,
        .shape_fingerprint = node.shape_id,
        .storage_class = storage,
    };
}

/// Graph-derived function emit order (callees before callers). See `SemanticGraph.moduleFunctionEmitOrder`.
pub fn functionEmitOrder(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    functions: []const semantic_graph.id,
) ![]const semantic_graph.id {
    return graph.moduleFunctionEmitOrder(alloc, functions);
}

/// Hardware descriptor rows exercised in a lowered module (Pass 22 WS23 query surface).
pub fn hardwareDescriptorsOfModule(
    alloc: std.mem.Allocator,
    m: dnir.Module,
) ![]dnir_hardware.Descriptor {
    return dnir_hardware.collectModuleDescriptors(alloc, m);
}

/// True when region hardware tier matches module tier and hardware nodes exist.
pub fn hardwareTierConsistent(m: dnir.Module, regions: []const region_graph.Region) bool {
    for (regions) |r| {
        if (@intFromEnum(r.hardware_tier) > @intFromEnum(m.hardware_tier)) return false;
    }
    return true;
}

/// Collect eligible top-level function names from a module (same surface as DNIR lowering).
pub fn eligibleFunctionNames(alloc: std.mem.Allocator, mod: *const ast.Module) ![]const []const u8 {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer names.deinit(alloc);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1 or fd.method or fd.is_local) continue;
        var ffi = false;
        for (fd.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "ffi")) ffi = true;
        }
        if (ffi) continue;
        try names.append(alloc, fd.path[0]);
    }
    return try names.toOwnedSlice(alloc);
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
        \\main: i64 = ()
        \\    helper()
    ;
    var lex = Lexer.init(src, "query.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "query.id");

    const main = g.findFunc("main") orelse return error.TestExpectedEqual;
    const helper = g.findFunc("helper") orelse return error.TestExpectedEqual;

    const calls = try callsIn(&g, alloc, main);
    defer alloc.free(calls);
    try std.testing.expect(calls.len == 1);
    const call = g.application(calls[0]) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(helper, call.relation);
    try std.testing.expectEqual(main, call.caller);

    const callees = try calleesOf(&g, alloc, main);
    defer alloc.free(callees);
    try std.testing.expect(callees.len == 1);
    try std.testing.expectEqual(helper, callees[0]);

    const not_function = try g.addChild(main, .{
        .kind = .value,
        .span = .{ .file = "query.id", .start = 5, .end = 5 },
    });
    try std.testing.expectError(error.InvalidFunctionEntity, callsIn(&g, alloc, not_function));
    try std.testing.expectError(error.InvalidFunctionEntity, calleesOf(&g, alloc, not_function));

    var unresolved = semantic_graph.SemanticGraph.init(alloc);
    defer unresolved.deinit();
    _ = try unresolved.liftModuleWithCalls(&mod, "query.id");
    const unresolved_main = unresolved.findFunc("main") orelse return error.TestExpectedEqual;
    try std.testing.expectError(error.UnresolvedApplication, callsIn(&unresolved, alloc, unresolved_main));
    try std.testing.expectError(error.UnresolvedApplication, calleesOf(&unresolved, alloc, unresolved_main));
    var unresolved_json: std.ArrayListUnmanaged(u8) = .empty;
    defer unresolved_json.deinit(alloc);
    try unresolved.writeJson(alloc, "query.id", &unresolved_json, null);
    var unresolved_parsed = try std.json.parseFromSlice(std.json.Value, alloc, unresolved_json.items, .{});
    defer unresolved_parsed.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        unresolved_parsed.value.object.get("unresolved_applications").?.array.items.len,
    );

    const relation = try g.addChild(main, .{
        .kind = .relation,
        .span = .{ .file = "query.id", .start = 6, .end = 5 },
    });
    g.application_facts.items[0].relation = relation;
    const relation_calls = try callsIn(&g, alloc, main);
    defer alloc.free(relation_calls);
    try std.testing.expectEqualSlices(semantic_graph.id, &.{calls[0]}, relation_calls);
    const relation_callees = try calleesOf(&g, alloc, main);
    defer alloc.free(relation_callees);
    try std.testing.expectEqualSlices(semantic_graph.id, &.{relation}, relation_callees);

    g.application_facts.items[0].relation = not_function;
    try std.testing.expectError(error.UnresolvedApplication, callsIn(&g, alloc, main));
    try std.testing.expectError(error.UnresolvedApplication, calleesOf(&g, alloc, main));
}

test "graph_query: record projection requires one exact record id" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const record = try graph.addNode(.{
        .kind = .table_shape,
        .span = .{ .file = "record.id", .start = 1, .end = 1 },
        .name = "point",
        .storage_class = .native,
        .shape_id = 42,
    });
    const value = try graph.addNode(.{
        .kind = .value,
        .span = .{ .file = "record.id", .start = 2, .end = 1 },
        .name = "point",
    });
    const unnamed_record = try graph.addNode(.{
        .kind = .table_shape,
        .span = .{ .file = "record.id", .start = 3, .end = 1 },
    });

    const representation = try representationForRecord(&graph, record);
    try std.testing.expectEqual(record, representation.id);
    try std.testing.expectEqualStrings("point", representation.name);
    try std.testing.expectEqual(@as(?u64, 42), representation.shape_fingerprint);
    try std.testing.expectError(error.InvalidRecordEntity, representationForRecord(&graph, value));
    try std.testing.expectError(error.MissingRecordName, representationForRecord(&graph, unnamed_record));
    try std.testing.expectError(
        error.InvalidRecordEntity,
        representationForRecord(&graph, @intCast(graph.nodes.items.len)),
    );
}
