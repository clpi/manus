//! Pass 22 §17.4 — compact semantic graph queries (deterministic, memoizable).
//!
//! Not a generic query engine: bounded facts for compiler, LSP, and MCP projections.
const std = @import("std");
const ast = @import("ast.zig");
const dnir = @import("duo_native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const region_graph = @import("region_graph.zig");
const semantic_graph = @import("semantic_graph.zig");

pub const CallSite = struct {
    callee: []const u8,
    call_shape_id: ?u64,
    caller: ?[]const u8,
};

/// Callees invoked directly from `func_name` (intra-module call nodes only).
pub fn calleesOf(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    func_name: []const u8,
) ![]const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer out.deinit(alloc);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(alloc);

    const func_id = graph.findFunc(func_name) orelse return try out.toOwnedSlice(alloc);
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .call) continue;
        const call_id = semantic_graph.NodeId{ .index = @intCast(i) };
        const caller_id = graph.containingFuncId(call_id) orelse continue;
        if (caller_id.index != func_id.index) continue;
        const callee = node.call_shape orelse continue;
        const name = callee.callee_name orelse continue;
        if (seen.contains(name)) continue;
        try seen.put(alloc, name, {});
        try out.append(alloc, name);
    }
    return try out.toOwnedSlice(alloc);
}

/// Call sites inside `func_name` (caller fixed to the query subject).
pub fn callsIn(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    func_name: []const u8,
) ![]CallSite {
    var out: std.ArrayListUnmanaged(CallSite) = .empty;
    errdefer {
        for (out.items) |cs| {
            alloc.free(cs.callee);
            if (cs.caller) |c| alloc.free(c);
        }
        out.deinit(alloc);
    }

    const func_id = graph.findFunc(func_name) orelse return try out.toOwnedSlice(alloc);
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .call) continue;
        const call_id = semantic_graph.NodeId{ .index = @intCast(i) };
        const caller_id = graph.containingFuncId(call_id) orelse continue;
        if (caller_id.index != func_id.index) continue;
        const cs = node.call_shape orelse continue;
        const callee = cs.callee_name orelse continue;
        const owned_callee = try alloc.dupe(u8, callee);
        const owned_caller = try alloc.dupe(u8, func_name);
        try out.append(alloc, .{
            .callee = owned_callee,
            .call_shape_id = node.call_shape_id,
            .caller = owned_caller,
        });
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeCallSites(alloc: std.mem.Allocator, sites: []CallSite) void {
    for (sites) |cs| {
        alloc.free(cs.callee);
        if (cs.caller) |c| alloc.free(c);
    }
    alloc.free(sites);
}

/// Record layout facts from the semantic graph (Pass 22 §17.4 `representation(value)` subset).
pub const RecordRepresentation = struct {
    name: []const u8,
    shape_id: ?u64,
    stable_id: ?u64,
    storage_class: ?[]const u8,
};

pub fn representationForRecord(graph: *const semantic_graph.SemanticGraph, name: []const u8) ?RecordRepresentation {
    const node = graph.findTableShape(name) orelse return null;
    const storage = if (node.storage_class) |sc| @import("types.zig").storageClassName(sc) else null;
    return .{
        .name = name,
        .shape_id = node.shape_id,
        .stable_id = if (node.stable_id) |sid| sid.hash else null,
        .storage_class = storage,
    };
}

/// Stable semantic identity hash for a named graph entity (func, record, …).
///
/// Resolved by IDENTITY, in declaration-kind order, not by first textual match:
/// a parameter spelled like the function it sits inside used to answer for it,
/// and every consumer of the result — DNIR provenance, region identity, the
/// gate that asserts the two agree — inherited that wrong node. The bare-name
/// scan remains only as the last rung, for kinds with no module-scope
/// declaration form.
pub fn stableIdOf(graph: *const semantic_graph.SemanticGraph, name: []const u8) ?u64 {
    const id = graph.findFunc(name) orelse
        graph.findId(.table_shape, name) orelse
        graph.findId(.enum_shape, name) orelse
        graph.findByName(name) orelse return null;
    const node = graph.get(id) orelse return null;
    return if (node.stable_id) |sid| sid.hash else null;
}

/// Graph-derived function emit order (callees before callers). See `SemanticGraph.moduleFunctionEmitOrder`.
pub fn functionEmitOrder(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    func_names: []const []const u8,
) ![]const []const u8 {
    return graph.moduleFunctionEmitOrder(alloc, func_names);
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
        \\helper(): i64
        \\    1
        \\end
        \\main(): i64
        \\    helper()
        \\end
    ;
    var lex = Lexer.init(src, "q.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "q.duo");

    const calls = try callsIn(&g, alloc, "main");
    defer freeCallSites(alloc, calls);
    try std.testing.expect(calls.len == 1);
    try std.testing.expectEqualStrings("helper", calls[0].callee);

    const callees = try calleesOf(&g, alloc, "main");
    defer alloc.free(callees);
    try std.testing.expect(callees.len == 1);
    try std.testing.expectEqualStrings("helper", callees[0]);

    try std.testing.expect(stableIdOf(&g, "main") != null);
}
