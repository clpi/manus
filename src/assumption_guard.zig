//! Pass 7 — explicit specialization assumptions and runtime guards.
//!
//! Canonical owner for guarded specialization, invalidation, and agent explanations.
//! Not a second semantic graph: assumptions reference stable entity IDs from sema/graph.
const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");
const types = @import("types.zig");
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

/// Catalog of common assumption patterns (expand as wiring lands).
pub const assumption_catalog: []const struct {
    id: []const u8,
    predicate: Predicate,
    origin: Origin,
    scope: ValidityScope,
    guard: GuardImplementation,
    wired: bool,
} = &.{
    .{ .id = "assume.shape.sealed", .predicate = .shape_id_matches, .origin = .graph_lift, .scope = .module, .guard = .compare_shape_id, .wired = true },
    .{ .id = "assume.call.target", .predicate = .call_target_known, .origin = .specialization, .scope = .function, .guard = .type_tag_check, .wired = false },
    .{ .id = "assume.no.escape", .predicate = .value_non_escaping, .origin = .sema, .scope = .function, .guard = .none, .wired = true },
    .{ .id = "assume.simd.width", .predicate = .target_simd_width, .origin = .representation, .scope = .link, .guard = .runtime_trap, .wired = false },
    .{ .id = "assume.tensor.extent", .predicate = .tensor_extent_known, .origin = .specialization, .scope = .function, .guard = .range_check, .wired = false },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (assumption_catalog, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"predicate\":\"{s}\",\"origin\":\"{s}\",\"scope\":\"{s}\",\"guard\":\"{s}\",\"wired\":",
            .{ row.id, row.predicate.name(), row.origin.name(), row.scope.name(), row.guard.name() },
        );
        try w.print("{s}", .{if (row.wired) "true" else "false"});
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

fn entityId(alloc: std.mem.Allocator, kind: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "duo:{s}:{s}", .{ kind, name });
}

pub const ModuleAssumptions = struct {
    items: []Assumption,

    pub fn deinit(self: *ModuleAssumptions, alloc: std.mem.Allocator) void {
        for (self.items) |*a| a.deinit(alloc);
        alloc.free(self.items);
    }
};

fn appendShapeAssumption(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(Assumption),
    record_name: []const u8,
    sc: types.StorageClass,
    shape_id: ?u64,
) !void {
    const subject = try entityId(alloc, "record", record_name);
    errdefer alloc.free(subject);
    const id = try std.fmt.allocPrint(alloc, "assume.shape.sealed:{s}", .{record_name});
    errdefer alloc.free(id);

    const evidence: optimization_outcome.Evidence = switch (sc) {
        .native, .sealed => .proven,
        .guarded => .guarded,
        .dynamic => .assumed,
    };

    const inv_msg: []const u8 = switch (sc) {
        .dynamic => "field added or value escapes dynamic table semantics",
        else => "field added, metatable changed, or storage class widened",
    };
    const inv = try alloc.dupe(u8, inv_msg);
    errdefer alloc.free(inv);
    const fb = try alloc.dupe(u8, "dynamic table representation with runtime shape checks");
    errdefer alloc.free(fb);
    _ = shape_id;
    try out.append(alloc, .{
        .id = id,
        .subject_entity = subject,
        .predicate = .shape_id_matches,
        .origin = .graph_lift,
        .scope = .module,
        .invalidation = inv,
        .fallback = fb,
        .evidence = evidence,
    });
}

/// Infer module assumptions from sema + graph lift (Pass 7 P7-04 wiring).
pub fn buildFromModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    semantic: *const sema.Sema,
    graph: ?*const semantic_graph.SemanticGraph,
) !ModuleAssumptions {
    _ = semantic;
    var items: std.ArrayListUnmanaged(Assumption) = .empty;
    errdefer {
        for (items.items) |*a| a.deinit(alloc);
        items.deinit(alloc);
    }

    if (graph) |g| {
        for (g.nodes.items) |node| {
            if (node.kind != .table_shape) continue;
            const name = node.name orelse continue;
            if (!g.atModuleScope(&node)) continue;
            const sc = node.storage_class orelse .dynamic;
            try appendShapeAssumption(alloc, &items, name, sc, node.shape_id);
        }
    } else {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .alias_def) continue;
            const ad = stmt.alias_def;
            try appendShapeAssumption(alloc, &items, ad.name, .dynamic, null);
        }
    }

    return .{ .items = try items.toOwnedSlice(alloc) };
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

test "assumption_guard: sealed shape catalog entry wired" {
    const row = assumption_catalog[0];
    try std.testing.expectEqualStrings("assume.shape.sealed", row.id);
    try std.testing.expect(row.wired);
    try std.testing.expectEqual(Predicate.shape_id_matches, row.predicate);
}

test "assumption_guard: writeCatalogJson emits predicate names" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCatalogJson(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "shape_id_matches") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "assume.no.escape") != null);
}

test "assumption_guard: sealed Point record yields shape assumption" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): f64
        \\    p = Point { x = 1.0, y = 2.0 }
        \\    p.x
        \\end
    ;
    var lex = Lexer.init(src, "point.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.duo");

    var assumptions = try buildFromModule(alloc, &mod, &semantic, &graph);
    defer assumptions.deinit(alloc);
    try std.testing.expect(assumptions.items.len >= 1);
    try std.testing.expectEqual(Predicate.shape_id_matches, assumptions.items[0].predicate);
}
