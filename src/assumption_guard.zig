//! Explicit specialization assumptions and runtime guards.
//!
//! Canonical owner for guarded specialization, invalidation, and agent explanations.
//! Not a second semantic graph: assumptions reference stable entity IDs from sema/graph.
const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");
const sema = @import("sema.zig");
const semantic_graph = @import("semantic_graph.zig");
const ast = @import("ast.zig");

pub const SCHEMA_VERSION = "assumption-guard-v0";

/// What fact the compiler assumes for a specialization.
pub const Predicate = enum(u8) {
    metatable_unchanged,
    shape_id_matches,
    field_present,
    return_count_stable,
    call_target_known,
    target_simd_width,
    value_non_escaping,
    foreign_layout_matches,
    tensor_extent_known,
    no_alias,

    pub fn name(self: Predicate) []const u8 {
        return switch (self) {
            .metatable_unchanged => "metatable_unchanged",
            .shape_id_matches => "shape_id_matches",
            .field_present => "field_present",
            .return_count_stable => "return_count_stable",
            .call_target_known => "call_target_known",
            .target_simd_width => "target_simd_width",
            .value_non_escaping => "value_non_escaping",
            .foreign_layout_matches => "foreign_layout_matches",
            .tensor_extent_known => "tensor_extent_known",
            .no_alias => "no_alias",
        };
    }
};

/// Where the assumption was introduced.
pub const Origin = enum(u8) {
    sema,
    graph_lift,
    specialization,
    representation,
    optimization,
    profile,
    import,

    pub fn name(self: Origin) []const u8 {
        return switch (self) {
            .sema => "sema",
            .graph_lift => "graph_lift",
            .specialization => "specialization",
            .representation => "representation",
            .optimization => "optimization",
            .profile => "profile",
            .import => "import",
        };
    }
};

pub const ValidityScope = enum(u8) {
    local,
    function,
    module,
    link,
    runtime,

    pub fn name(self: ValidityScope) []const u8 {
        return switch (self) {
            .local => "local",
            .function => "function",
            .module => "module",
            .link => "link",
            .runtime => "runtime",
        };
    }
};

pub const Assumption = struct {
    id: []const u8,
    subject_entity: []const u8,
    predicate: Predicate,
    origin: Origin,
    scope: ValidityScope,
    invalidation: ?[]const u8,
    fallback: ?[]const u8,
    evidence: optimization_outcome.Evidence,

    pub fn deinit(self: *Assumption, alloc: std.mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.subject_entity);
        if (self.invalidation) |s| alloc.free(s);
        if (self.fallback) |s| alloc.free(s);
    }
};

pub const GuardImplementation = enum(u8) {
    none,
    compare_shape_id,
    compare_metatable_ptr,
    range_check,
    type_tag_check,
    profile_counter,
    runtime_trap,

    pub fn name(self: GuardImplementation) []const u8 {
        return switch (self) {
            .none => "none",
            .compare_shape_id => "compare_shape_id",
            .compare_metatable_ptr => "compare_metatable_ptr",
            .range_check => "range_check",
            .type_tag_check => "type_tag_check",
            .profile_counter => "profile_counter",
            .runtime_trap => "runtime_trap",
        };
    }
};

pub const Guard = struct {
    assumption_id: []const u8,
    implementation: GuardImplementation,
    estimated_cost: u32,

    pub fn deinit(self: *Guard, alloc: std.mem.Allocator) void {
        alloc.free(self.assumption_id);
    }
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub const ModuleAssumptions = struct {
    items: []Assumption,

    pub fn deinit(self: *ModuleAssumptions, alloc: std.mem.Allocator) void {
        for (self.items) |*a| a.deinit(alloc);
        alloc.free(self.items);
    }
};

fn appendGuardedShape(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(Assumption),
    entity: semantic_graph.id,
) !void {
    const subject = try std.fmt.allocPrint(alloc, "{d}", .{entity});
    errdefer alloc.free(subject);
    const id = try std.fmt.allocPrint(alloc, "guard:{d}", .{entity});
    errdefer alloc.free(id);
    const inv = try alloc.dupe(u8, "speculated shape_id_matches fact invalidated");
    errdefer alloc.free(inv);
    const fb = try alloc.dupe(u8, "general table realization");
    errdefer alloc.free(fb);
    try out.append(alloc, .{
        .id = id,
        .subject_entity = subject,
        .predicate = .shape_id_matches,
        .origin = .graph_lift,
        .scope = .module,
        .invalidation = inv,
        .fallback = fb,
        .evidence = .guarded,
    });
}

/// Project speculated guards from the semantic graph (`law.guard.one`).
/// Known fact → guard 0. Unknown fact → general realization, no guard.
pub fn buildFromModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    semantic: *const sema.Sema,
    graph: *const semantic_graph.SemanticGraph,
) !ModuleAssumptions {
    _ = mod;
    _ = semantic;
    var items: std.ArrayListUnmanaged(Assumption) = .empty;
    errdefer {
        for (items.items) |*a| a.deinit(alloc);
        items.deinit(alloc);
    }

    for (graph.nodes.items, 0..) |node, i| {
        if (!graph.hasTableDescriptorFacts(@intCast(i))) continue;
        if (!semantic_graph.SemanticGraph.atModuleScope(graph, &node)) continue;
        const knowledge = node.knowledge orelse continue;
        if (knowledge != .guarded) continue;
        try appendGuardedShape(alloc, &items, @intCast(i));
    }

    return .{ .items = try items.toOwnedSlice(alloc) };
}

/// GAP-182 order 1: emit graph experiment facts from guarded knowledge.
/// This is the graph-emitted experiment(P) tuple face. The function emits
/// `ExperimentFact` structs into the graph for each guarded shape node.
pub fn emitExperimentFacts(
    alloc: std.mem.Allocator,
    graph: *semantic_graph.SemanticGraph,
) !void {
    for (graph.nodes.items, 0..) |node, i| {
        if (!graph.hasTableDescriptorFacts(@intCast(i))) continue;
        if (!semantic_graph.SemanticGraph.atModuleScope(graph, &node)) continue;
        const knowledge = node.knowledge orelse continue;
        if (knowledge != .guarded) continue;

        const entity_id: semantic_graph.id = @intCast(i);
        const proposition = try std.fmt.allocPrint(alloc, "guard:{d}", .{entity_id});
        errdefer alloc.free(proposition);
        const producer = try alloc.dupe(u8, "guard_observation");
        errdefer alloc.free(producer);
        const conditional_theorem = try alloc.dupe(u8, "general table realization");
        errdefer alloc.free(conditional_theorem);
        
        try graph.experiments.append(alloc, .{
            .proposition = proposition,
            .producer = producer,
            .cost = 1, // Default cost for guard observation
            .conditional_theorem = conditional_theorem,
            .subject_revision = "", // No subject revision for graph-emitted facts
        });
    }
}

pub fn writeModuleJson(m: *const ModuleAssumptions, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"assumption_count\":{d},\"assumptions\":[", .{
        SCHEMA_VERSION, m.items.len,
    });
    for (m.items, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try writeAssumptionJson(&a, w);
    }
    try w.print("]}}", .{});
}

pub fn writeAssumptionJson(a: *const Assumption, w: *std.Io.Writer) !void {
    try w.print("{{\"id\":\"", .{});
    try jsonEscape(w, a.id);
    try w.print("\",\"subject_entity\":\"", .{});
    try jsonEscape(w, a.subject_entity);
    try w.print(
        "\",\"predicate\":\"{s}\",\"origin\":\"{s}\",\"scope\":\"{s}\",\"evidence\":\"{s}\"",
        .{ a.predicate.name(), a.origin.name(), a.scope.name(), a.evidence.name() },
    );
    if (a.invalidation) |inv| {
        try w.print(",\"invalidation\":\"", .{});
        try jsonEscape(w, inv);
        try w.print("\"", .{});
    }
    if (a.fallback) |fb| {
        try w.print(",\"fallback\":\"", .{});
        try jsonEscape(w, fb);
        try w.print("\"", .{});
    }
    try w.print("}}", .{});
}

test "assumption_guard: no assumption catalog" {
    try std.testing.expect(!@hasDecl(@This(), "assumption_catalog"));
    try std.testing.expect(!@hasDecl(@This(), "writeCatalogJson"));
}

test "assumption_guard: graph input is required" {
    const build_info = @typeInfo(@TypeOf(buildFromModule)).@"fn";
    try std.testing.expect(build_info.param_types[3].? == *const semantic_graph.SemanticGraph);
}

test "assumption_guard: known and unknown shapes emit no guard" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: { x: f64, y: f64 }
        \\main(): f64
        \\    p = Point { x = 1.0, y = 2.0 }
        \\    p.x
        \\end
    ;
    var lex = Lexer.init(src, "point.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.idol_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.id");

    var assumptions = try buildFromModule(alloc, &mod, &semantic, &graph);
    defer assumptions.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 0), assumptions.items.len);
}

test "assumption_guard: speculated knowledge emits exact guard" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "guard.id", .start = 0, .end = 0 },
    });
    const shape = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "guard.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    var dummy_mod: ast.Module = undefined;
    var dummy_sem = sema.Sema.init(std.testing.allocator);
    defer dummy_sem.deinit();
    var assumptions = try buildFromModule(std.testing.allocator, &dummy_mod, &dummy_sem, &graph);
    defer assumptions.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), assumptions.items.len);
    try std.testing.expectEqual(Predicate.shape_id_matches, assumptions.items[0].predicate);
    try std.testing.expectEqual(optimization_outcome.Evidence.guarded, assumptions.items[0].evidence);
    var id_buf: [20]u8 = undefined;
    const expected = std.fmt.bufPrint(&id_buf, "{d}", .{shape}) catch unreachable;
    try std.testing.expectEqualStrings(expected, assumptions.items[0].subject_entity);
    try std.testing.expect(assumptions.items[0].fallback != null);
    try std.testing.expect(assumptions.items[0].invalidation != null);
}

test "assumption_guard: graph-emitted experiment facts (GAP-182 order 1)" {
    // GAP-182 order 1: verify that the graph emits experiment(P) tuple facts
    // for guarded knowledge nodes.
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const home = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "experiment.id", .start = 0, .end = 0 },
    });
    const shape = try graph.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "experiment.id", .start = 1, .end = 1 },
        .name = "Point",
        .knowledge = .guarded,
        .descriptor_state = .sealed,
        .shape_id = 1,
    });
    
    try emitExperimentFacts(std.testing.allocator, &graph);
    
    try std.testing.expectEqual(@as(usize, 1), graph.experiments.items.len);
    const exp = graph.experiments.items[0];
    var id_buf: [20]u8 = undefined;
    const expected_prop = std.fmt.bufPrint(&id_buf, "guard:{d}", .{shape}) catch unreachable;
    try std.testing.expectEqualStrings(expected_prop, exp.proposition);
    try std.testing.expectEqualStrings("guard_observation", exp.producer);
    try std.testing.expectEqual(@as(u32, 1), exp.cost);
    try std.testing.expectEqualStrings("general table realization", exp.conditional_theorem);
    try std.testing.expectEqualStrings("", exp.subject_revision);
}
