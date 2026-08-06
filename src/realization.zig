//! Pass 8 — realization variables, candidates, degrees of freedom, deterministic planning.
//!
//! Canonical owner for "what remains free" and "what was selected" (not a second graph).
const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const semantic_graph = @import("semantic_graph.zig");
const semantic_fingerprint = @import("semantic_fingerprint.zig");
const types = @import("types.zig");

pub const SCHEMA_VERSION = "realization-v0";
pub const DEFAULT_TRANSFORM_VERSION = "transform-registry-v0";

/// Maps storage class to the canonical realization candidate id (P8-M1 alignment with codegen).
pub fn candidateIdForStorageClass(sc: types.StorageClass) []const u8 {
    return switch (sc) {
        .native => "repr.native_aggregate",
        .sealed => "repr.native_sealed",
        .guarded => "repr.guarded",
        .dynamic => "repr.dynamic_table",
    };
}

pub fn cRepresentationForStorageClass(sc: types.StorageClass) []const u8 {
    return switch (sc) {
        .native => "native_aggregate",
        .sealed => "native_struct",
        .guarded => "guarded_struct",
        .dynamic => "lua_Table",
    };
}

/// Semantic fingerprint for a record entity including shape identity (P8-M2 invalidation).
pub fn fingerprintForRecordEntity(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    record_name: []const u8,
    target: []const u8,
    transform_version: []const u8,
) !u64 {
    const entity_id = try std.fmt.allocPrint(alloc, "duo:record:{s}", .{record_name});
    defer alloc.free(entity_id);
    var shape_dep: ?[]const u8 = null;
    defer if (shape_dep) |s| alloc.free(s);
    if (graph.findTableShape(record_name)) |node| {
        if (node.shape_id) |sid| {
            shape_dep = try std.fmt.allocPrint(alloc, "shape:{x}", .{sid});
        }
    }
    return semantic_fingerprint.compute(.{
        .entity_id = entity_id,
        .target = target,
        .transform_version = transform_version,
        .descriptor_deps = shape_dep,
    });
}

/// Log structured outcome when codegen materializes a record representation (P8 codegen bridge).
pub fn logAppliedRepresentation(
    alloc: std.mem.Allocator,
    record_name: []const u8,
    sc: types.StorageClass,
    c_typedef: []const u8,
) void {
    if (sc == .dynamic) return;
    const entity = std.fmt.allocPrint(alloc, "duo:record:{s}", .{record_name}) catch return;
    defer alloc.free(entity);
    const candidate = candidateIdForStorageClass(sc);
    const reason = std.fmt.allocPrint(alloc, "codegen emitted {s} as {s}; candidate {s}", .{
        c_typedef, cRepresentationForStorageClass(sc), candidate,
    }) catch return;
    defer alloc.free(reason);
    optimization_outcome.logOutcome(
        alloc,
        "realization.representation",
        entity,
        .applied,
        if (sc == .native) .proven else .guarded,
        .emit_call,
        reason,
        "repr.dynamic_table",
        cRepresentationForStorageClass(sc),
        0,
        0,
    ) catch {};
}

pub const Dimension = enum(u8) {
    representation,
    algorithm,
    memory_placement,
    scheduling,
    precision,
    persistence,
    execution_domain,

    pub fn name(self: Dimension) []const u8 {
        return switch (self) {
            .representation => "representation",
            .algorithm => "algorithm",
            .memory_placement => "memory_placement",
            .scheduling => "scheduling",
            .precision => "precision",
            .persistence => "persistence",
            .execution_domain => "execution_domain",
        };
    }
};

pub const FreedomStatus = enum(u8) {
    fixed_semantics,
    fixed_requirement,
    constrained,
    preferred,
    selected,
    guarded,
    unknown,
    free,
    negotiable,
    invalidated,
    unavailable,

    pub fn name(self: FreedomStatus) []const u8 {
        return @tagName(self);
    }
};

pub const FreedomKind = enum(u8) {
    reorder,
    parallelize,
    fuse,
    split,
    migrate,
    cache,
    persist,
    approximate,
    change_layout,
    change_algorithm,
    change_storage,
    change_execution_domain,
    multiversion,

    pub fn name(self: FreedomKind) []const u8 {
        return @tagName(self);
    }
};

pub const DegreeOfFreedom = struct {
    kind: FreedomKind,
    status: FreedomStatus,
    scope: []const u8,
    source: []const u8,

    pub fn deinit(self: *DegreeOfFreedom, alloc: std.mem.Allocator) void {
        alloc.free(self.scope);
        alloc.free(self.source);
    }
};

pub const Candidate = struct {
    id: []const u8,
    label: []const u8,
    representation: []const u8,
    static_cost: u32,
    optionality_retained: u32,
    legal: bool,
    rejection_reason: ?[]const u8,
    evidence: optimization_outcome.Evidence,
    fallback: ?[]const u8,

    pub fn deinit(self: *Candidate, alloc: std.mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.label);
        alloc.free(self.representation);
        if (self.rejection_reason) |r| alloc.free(r);
        if (self.fallback) |f| alloc.free(f);
    }
};

pub const Variable = struct {
    id: []const u8,
    subject_entity: []const u8,
    dimension: Dimension,
    candidates: []Candidate,
    selected_index: ?usize = null,
    hard_constraints: ?[]const u8 = null,
    freedoms: []DegreeOfFreedom,
    rejections: []SelectionRejection = &.{},

    pub fn deinit(self: *Variable, alloc: std.mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.subject_entity);
        if (self.hard_constraints) |h| alloc.free(h);
        for (self.candidates) |*c| c.deinit(alloc);
        alloc.free(self.candidates);
        for (self.freedoms) |*f| f.deinit(alloc);
        alloc.free(self.freedoms);
        for (self.rejections) |*r| r.deinit(alloc);
        alloc.free(self.rejections);
    }

    pub fn selected(self: *const Variable) ?*const Candidate {
        const idx = self.selected_index orelse return null;
        if (idx >= self.candidates.len) return null;
        return &self.candidates[idx];
    }
};

pub const ModuleRealizations = struct {
    file: []const u8,
    variables: []Variable,

    pub fn deinit(self: *ModuleRealizations, alloc: std.mem.Allocator) void {
        alloc.free(self.file);
        for (self.variables) |*v| v.deinit(alloc);
        alloc.free(self.variables);
    }
};

pub const SelectionRejection = struct {
    candidate_id: []const u8,
    reason: []const u8,

    pub fn deinit(self: *SelectionRejection, alloc: std.mem.Allocator) void {
        alloc.free(self.candidate_id);
        alloc.free(self.reason);
    }
};

pub const SelectionResult = struct {
    selected_id: ?[]const u8,
    rejections: []SelectionRejection,

    pub fn deinit(self: *SelectionResult, alloc: std.mem.Allocator) void {
        if (self.selected_id) |s| alloc.free(s);
        for (self.rejections) |*r| r.deinit(alloc);
        alloc.free(self.rejections);
    }
};

/// Pass 12 — structured candidate comparison report (P12-WS4).
pub const CandidateComparisonReport = struct {
    subject_entity: []const u8,
    selected_id: ?[]const u8,
    rejections: []SelectionRejection,
    legal_count: usize,
    compared_count: usize,

    pub fn deinit(self: *CandidateComparisonReport, alloc: std.mem.Allocator) void {
        alloc.free(self.subject_entity);
        if (self.selected_id) |s| alloc.free(s);
        for (self.rejections) |*r| r.deinit(alloc);
        alloc.free(self.rejections);
    }
};

/// Deterministic comparison with explicit rejection reasons (extends selectDeterministic).
pub fn compareCandidates(alloc: std.mem.Allocator, var_: *Variable) !CandidateComparisonReport {
    var legal_count: usize = 0;
    for (var_.candidates) |c| {
        if (c.legal) legal_count += 1;
    }
    var sel = try selectDeterministic(alloc, var_);
    const subject = try alloc.dupe(u8, var_.subject_entity);
    const selected = if (sel.selected_id) |s| try alloc.dupe(u8, s) else null;
    const rejections = try alloc.alloc(SelectionRejection, sel.rejections.len);
    for (sel.rejections, 0..) |r, i| {
        rejections[i] = .{
            .candidate_id = try alloc.dupe(u8, r.candidate_id),
            .reason = try alloc.dupe(u8, r.reason),
        };
    }
    sel.deinit(alloc);
    return .{
        .subject_entity = subject,
        .selected_id = selected,
        .rejections = rejections,
        .legal_count = legal_count,
        .compared_count = var_.candidates.len,
    };
}

pub fn selectDeterministic(alloc: std.mem.Allocator, var_: *Variable) !SelectionResult {
    var rejections: std.ArrayListUnmanaged(SelectionRejection) = .empty;
    errdefer {
        for (rejections.items) |*r| r.deinit(alloc);
        rejections.deinit(alloc);
    }

    var best_idx: ?usize = null;
    var best_cost: u32 = std.math.maxInt(u32);
    var best_optionality: u32 = 0;

    for (var_.candidates, 0..) |*c, i| {
        if (!c.legal) {
            const reason = c.rejection_reason orelse "illegal";
            try rejections.append(alloc, .{
                .candidate_id = try alloc.dupe(u8, c.id),
                .reason = try alloc.dupe(u8, reason),
            });
            continue;
        }
        const better = blk: {
            if (best_idx == null) break :blk true;
            if (c.static_cost < best_cost) break :blk true;
            if (c.static_cost == best_cost and c.optionality_retained > best_optionality) break :blk true;
            break :blk false;
        };
        if (better) {
            best_idx = i;
            best_cost = c.static_cost;
            best_optionality = c.optionality_retained;
        }
    }

    if (best_idx) |bi| {
        for (var_.candidates, 0..) |c, i| {
            if (i == bi or !c.legal) continue;
            try rejections.append(alloc, .{
                .candidate_id = try alloc.dupe(u8, c.id),
                .reason = try alloc.dupe(u8, "higher static cost or lower optionality than selected candidate"),
            });
        }
    }

    var_.selected_index = best_idx;
    const selected_id = if (best_idx) |bi| try alloc.dupe(u8, var_.candidates[bi].id) else null;
    return .{
        .selected_id = selected_id,
        .rejections = try rejections.toOwnedSlice(alloc),
    };
}

/// Count candidates still legal before target-aware commitment (Pass 22 Gate L).
pub fn legalCandidateCount(var_: *const Variable) usize {
    var n: usize = 0;
    for (var_.candidates) |c| {
        if (c.legal) n += 1;
    }
    return n;
}

/// True when portable targets (Wasm) should avoid native struct realizations.
pub fn targetPrefersDynamicTable(target: []const u8) bool {
    return std.mem.indexOf(u8, target, "wasm") != null;
}

/// Apply target constraints to representation candidates (does not select).
pub fn applyTargetConstraints(alloc: std.mem.Allocator, var_: *Variable, target: []const u8) !void {
    if (var_.dimension != .representation) return;
    const portable = targetPrefersDynamicTable(target);
    for (var_.candidates) |*c| {
        if (portable and (std.mem.eql(u8, c.id, "repr.native_sealed") or
            std.mem.eql(u8, c.id, "repr.native_aggregate") or
            std.mem.eql(u8, c.id, "repr.guarded")))
        {
            c.legal = false;
            if (c.rejection_reason) |r| alloc.free(r);
            c.rejection_reason = try alloc.dupe(u8, "target requires portable dynamic representation");
            continue;
        }
        if (!portable and std.mem.eql(u8, c.id, "repr.dynamic_table")) {
            c.static_cost = 100;
        } else if (portable and std.mem.eql(u8, c.id, "repr.dynamic_table")) {
            c.static_cost = 15;
        }
    }
}

/// Target-aware deterministic selection (Pass 22 §19 — deferred commitment).
pub fn selectForTarget(alloc: std.mem.Allocator, var_: *Variable, target: []const u8) !SelectionResult {
    try applyTargetConstraints(alloc, var_, target);
    return selectDeterministic(alloc, var_);
}

/// Commit all module variables for a target (after deferred candidate build).
pub fn commitModuleForTarget(alloc: std.mem.Allocator, m: *ModuleRealizations, target: []const u8) !void {
    for (m.variables) |*v| {
        var sel = try selectForTarget(alloc, v, target);
        v.rejections = sel.rejections;
        if (sel.selected_id) |sid| alloc.free(sid);
        sel.rejections = &.{};
        sel.deinit(alloc);
    }
}

fn entityId(alloc: std.mem.Allocator, kind: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "duo:{s}:{s}", .{ kind, name });
}

fn appendCandidate(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(Candidate),
    id: []const u8,
    label: []const u8,
    repr: []const u8,
    cost: u32,
    optionality: u32,
    legal: bool,
    reason: ?[]const u8,
    evidence: optimization_outcome.Evidence,
) !void {
    try out.append(alloc, .{
        .id = try alloc.dupe(u8, id),
        .label = try alloc.dupe(u8, label),
        .representation = try alloc.dupe(u8, repr),
        .static_cost = cost,
        .optionality_retained = optionality,
        .legal = legal,
        .rejection_reason = if (reason) |r| try alloc.dupe(u8, r) else null,
        .evidence = evidence,
        .fallback = if (!legal) try alloc.dupe(u8, "dynamic_table") else null,
    });
}

pub fn representationVariableForRecord(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    record_name: []const u8,
    options: struct {
        auto_select: bool = true,
        target: []const u8 = "native",
    },
) !?Variable {
    const node = graph.findTableShape(record_name) orelse return null;
    const subject = try entityId(alloc, "record", record_name);
    errdefer alloc.free(subject);
    const var_id = try std.fmt.allocPrint(alloc, "realize.representation:{s}", .{record_name});
    errdefer alloc.free(var_id);

    const sc = node.storage_class orelse .dynamic;
    const kn = semantic_algebra.KnowledgeLevel.fromStorageClass(sc);

    var candidates: std.ArrayListUnmanaged(Candidate) = .empty;
    errdefer {
        for (candidates.items) |*c| c.deinit(alloc);
        candidates.deinit(alloc);
    }

    try appendCandidate(alloc, &candidates, "repr.dynamic_table", "Lua table (dynamic)", "lua_Table", 100, 90, true, null, .proven);
    try appendCandidate(alloc, &candidates, "repr.guarded", "Guarded native struct", "guarded_struct", 60, 70, kn.dominates(.guarded), if (kn.dominates(.guarded)) null else "knowledge below guarded", .guarded);
    try appendCandidate(alloc, &candidates, "repr.native_sealed", "Sealed native struct", "native_struct", 20, 50, kn.dominates(.stable), if (kn.dominates(.stable)) null else "shape not stable/sealed", if (sc == .native) .proven else .estimated);
    try appendCandidate(alloc, &candidates, "repr.native_aggregate", "Register/native aggregate", "native_aggregate", 10, 40, sc == .native, if (sc == .native) null else "storage_class not native", .proven);

    var freedoms: std.ArrayListUnmanaged(DegreeOfFreedom) = .empty;
    errdefer {
        for (freedoms.items) |*f| f.deinit(alloc);
        freedoms.deinit(alloc);
    }
    try freedoms.append(alloc, .{
        .kind = .change_layout,
        .status = if (sc == .native) .fixed_semantics else .free,
        .scope = try alloc.dupe(u8, record_name),
        .source = try alloc.dupe(u8, "storage_class"),
    });
    try freedoms.append(alloc, .{
        .kind = .fuse,
        .status = if (kn.dominates(.stable)) .constrained else .unknown,
        .scope = try alloc.dupe(u8, record_name),
        .source = try alloc.dupe(u8, "knowledge_lattice"),
    });

    var var_: Variable = .{
        .id = var_id,
        .subject_entity = subject,
        .dimension = .representation,
        .candidates = try candidates.toOwnedSlice(alloc),
        .hard_constraints = try std.fmt.allocPrint(alloc, "observable Lua semantics preserved; shape_id={?}", .{node.shape_id}),
        .freedoms = try freedoms.toOwnedSlice(alloc),
        .rejections = &.{},
    };
    if (options.auto_select) {
        var sel = try selectForTarget(alloc, &var_, options.target);
        var_.rejections = sel.rejections;
        if (sel.selected_id) |sid| alloc.free(sid);
        sel.rejections = &.{};
        sel.deinit(alloc);
    }
    return var_;
}

pub fn buildDeferredFromGraph(alloc: std.mem.Allocator, graph: *const semantic_graph.SemanticGraph, file: []const u8) !ModuleRealizations {
    return buildFromGraphOptions(alloc, graph, file, .{ .auto_select = false, .target = "native" });
}

pub fn buildFromGraph(alloc: std.mem.Allocator, graph: *const semantic_graph.SemanticGraph, file: []const u8) !ModuleRealizations {
    return buildFromGraphOptions(alloc, graph, file, .{ .auto_select = true, .target = "native" });
}

fn buildFromGraphOptions(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    file: []const u8,
    options: struct {
        auto_select: bool,
        target: []const u8,
    },
) !ModuleRealizations {
    var vars: std.ArrayListUnmanaged(Variable) = .empty;
    errdefer {
        for (vars.items) |*v| v.deinit(alloc);
        vars.deinit(alloc);
    }

    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(alloc);

    for (graph.nodes.items) |*node| {
        if (node.kind != .table_shape) continue;
        const name = node.name orelse continue;
        if (seen.contains(name)) continue;
        try seen.put(alloc, name, {});
        if (try representationVariableForRecord(alloc, graph, name, .{
            .auto_select = options.auto_select,
            .target = options.target,
        })) |v| {
            try vars.append(alloc, v);
        }
    }

    return .{
        .file = try alloc.dupe(u8, file),
        .variables = try vars.toOwnedSlice(alloc),
    };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeJson(m: *const ModuleRealizations, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"file\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, m.file);
    try w.print("\",\"variable_count\":{d},\"variables\":[", .{m.variables.len});
    for (m.variables, 0..) |var_, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, var_.id);
        try w.print("\",\"subject_entity\":\"", .{});
        try jsonEscape(w, var_.subject_entity);
        try w.print("\",\"dimension\":\"{s}\",\"candidates\":[", .{var_.dimension.name()});
        for (var_.candidates, 0..) |c, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("{{\"id\":\"", .{});
            try jsonEscape(w, c.id);
            try w.print("\",\"label\":\"", .{});
            try jsonEscape(w, c.label);
            try w.print("\",\"representation\":\"", .{});
            try jsonEscape(w, c.representation);
            try w.print("\",\"static_cost\":{d},\"optionality_retained\":{d},\"legal\":", .{ c.static_cost, c.optionality_retained });
            try w.print("{s}", .{if (c.legal) "true" else "false"});
            try w.print(",\"evidence\":\"{s}\"", .{c.evidence.name()});
            if (c.rejection_reason) |r| {
                try w.print(",\"rejection_reason\":\"", .{});
                try jsonEscape(w, r);
                try w.print("\"", .{});
            }
            try w.print("}}", .{});
        }
        try w.print("]", .{});
        if (var_.selected_index) |si| {
            try w.print(",\"selected_index\":{d},\"selected_id\":\"", .{si});
            try jsonEscape(w, var_.candidates[si].id);
            try w.print("\"", .{});
        }
        if (var_.hard_constraints) |hc| {
            try w.print(",\"hard_constraints\":\"", .{});
            try jsonEscape(w, hc);
            try w.print("\"", .{});
        }
        if (var_.rejections.len > 0) {
            try w.print(",\"rejections\":[", .{});
            for (var_.rejections, 0..) |r, k| {
                if (k > 0) try w.print(",", .{});
                try w.print("{{\"candidate_id\":\"", .{});
                try jsonEscape(w, r.candidate_id);
                try w.print("\",\"reason\":\"", .{});
                try jsonEscape(w, r.reason);
                try w.print("\"}}", .{});
            }
            try w.print("]", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

test "realization: native Point selects native aggregate" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
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

    var m = try buildFromGraph(alloc, &graph, "point.duo");
    defer m.deinit(alloc);
    try std.testing.expect(m.variables.len >= 1);
    const point_var = blk: {
        for (m.variables) |v| {
            if (std.mem.indexOf(u8, v.subject_entity, "Point") != null) break :blk v;
        }
        break :blk null;
    } orelse return error.TestExpectedEqual;
    const sel = point_var.selected() orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, sel.id, "repr.native_aggregate"));
}

test "realization: selectDeterministic is stable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var var_: Variable = .{
        .id = try alloc.dupe(u8, "test"),
        .subject_entity = try alloc.dupe(u8, "duo:record:T"),
        .dimension = .representation,
        .candidates = try alloc.dupe(Candidate, &.{
            .{
                .id = try alloc.dupe(u8, "a"),
                .label = try alloc.dupe(u8, "a"),
                .representation = try alloc.dupe(u8, "a"),
                .static_cost = 50,
                .optionality_retained = 10,
                .legal = true,
                .rejection_reason = null,
                .evidence = .estimated,
                .fallback = null,
            },
            .{
                .id = try alloc.dupe(u8, "b"),
                .label = try alloc.dupe(u8, "b"),
                .representation = try alloc.dupe(u8, "b"),
                .static_cost = 20,
                .optionality_retained = 5,
                .legal = true,
                .rejection_reason = null,
                .evidence = .estimated,
                .fallback = null,
            },
        }),
        .freedoms = &.{},
        .rejections = &.{},
    };
    defer var_.deinit(alloc);
    var r = try selectDeterministic(alloc, &var_);
    defer r.deinit(alloc);
    try std.testing.expectEqualStrings("b", r.selected_id.?);
}

test "realization: compareCandidates produces report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var candidates: std.ArrayListUnmanaged(Candidate) = .empty;
    defer {
        for (candidates.items) |*c| c.deinit(alloc);
        candidates.deinit(alloc);
    }
    try appendCandidate(alloc, &candidates, "classifier.branch_chain", "Linear scan", "branch_chain", 30, 80, true, null, .proven);
    try appendCandidate(alloc, &candidates, "classifier.sorted_lookup", "Binary search", "sorted_table", 20, 70, true, null, .proven);
    try appendCandidate(alloc, &candidates, "classifier.perfect_hash", "Perfect hash", "phf", 10, 40, false, "not generated for keyword set", .estimated);
    var var_: Variable = .{
        .id = try alloc.dupe(u8, "realize.keyword_classifier"),
        .subject_entity = try alloc.dupe(u8, "duo:lexer:keyword_classifier"),
        .dimension = .algorithm,
        .candidates = try candidates.toOwnedSlice(alloc),
        .freedoms = &.{},
    };
    defer var_.deinit(alloc);
    var report = try compareCandidates(alloc, &var_);
    defer report.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), report.legal_count);
    try std.testing.expectEqual(@as(usize, 3), report.compared_count);
    try std.testing.expectEqualStrings("classifier.sorted_lookup", report.selected_id.?);
}

test "realization: storage class maps to planner candidate" {
    try std.testing.expectEqualStrings("repr.native_aggregate", candidateIdForStorageClass(.native));
    try std.testing.expectEqualStrings("repr.dynamic_table", candidateIdForStorageClass(.dynamic));
}

test "realization: Gate L deferred representation until target" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@sealed
        \\alias User = { id: i64, name: str }
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "user.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "user.duo");

    var deferred = try buildDeferredFromGraph(alloc, &graph, "user.duo");
    defer deferred.deinit(alloc);
    try std.testing.expect(deferred.variables.len >= 1);
    const var0 = deferred.variables[0];
    try std.testing.expect(legalCandidateCount(&var0) >= 2);
    try std.testing.expect(var0.selected_index == null);

    var native_plan = try buildDeferredFromGraph(alloc, &graph, "user.duo");
    defer native_plan.deinit(alloc);
    try commitModuleForTarget(alloc, &native_plan, "native");
    const native_sel = native_plan.variables[0].selected() orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, native_sel.id, "repr.native_sealed"));

    var wasm_plan = try buildDeferredFromGraph(alloc, &graph, "user.duo");
    defer wasm_plan.deinit(alloc);
    try commitModuleForTarget(alloc, &wasm_plan, "wasm32-wasi");
    const wasm_sel = wasm_plan.variables[0].selected() orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, wasm_sel.id, "repr.dynamic_table"));
}

test "realization: fingerprint includes shape identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "point.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = @import("sema.zig").Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.duo");
    const fp = try fingerprintForRecordEntity(alloc, &graph, "Point", "native", DEFAULT_TRANSFORM_VERSION);
    try std.testing.expect(fp != 0);
}
