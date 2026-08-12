//! Pass 8 — realization variables, candidates, degrees of freedom, deterministic planning.
//!
//! Canonical owner for "what remains free" and "what was selected" (not a second graph).
const std = @import("std");
const ast = @import("ast.zig");
const optimization_outcome = @import("optimization_outcome.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const semantic_graph = @import("semantic_graph.zig");
const semantic_fingerprint = @import("semantic_fingerprint.zig");
const types = @import("types.zig");

pub const SCHEMA_VERSION = "realization-v0";
pub const C_FLOOR_SCHEMA_VERSION = "c-floor-v0";

/// The ACTIVE objective for the c-floor plan (constitution §49: an ordinary
/// fact, not a compiler mode). `balanced` = every constitutional dimension is
/// relevant, which is the conservative choice and the one law.perf.floor's
/// wording implies for a compiler that has not been told otherwise.
pub const C_FLOOR_OBJECTIVE: semantic_algebra.Objective = .balanced;
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
    /// Which lowering produces the machine code for one callable. This is the
    /// dimension `law.c.floor` lives on: the C-equivalent lowering is one of
    /// its candidates, and the direct backend is another.
    lowering,

    pub fn name(self: Dimension) []const u8 {
        return switch (self) {
            .representation => "representation",
            .algorithm => "algorithm",
            .memory_placement => "memory_placement",
            .scheduling => "scheduling",
            .precision => "precision",
            .persistence => "persistence",
            .execution_domain => "execution_domain",
            .lowering => "lowering",
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
    /// §47 cost facts. Unknown on every dimension until something attaches one;
    /// an unknown dimension does not participate in dominance.
    cost: semantic_algebra.CostVector = .{},
    /// `law.perf.floor`'s "conservative baseline". A baseline candidate is
    /// RETAINED as the selection until some other candidate is proven or
    /// measured superior — it is not merely one option among equals.
    baseline: bool = false,
    /// Filled by `selectAgainstFloor`: why this candidate was realized, or why
    /// it was skipped. Structured, not prose — H-8.
    verdict: ?semantic_algebra.DominanceVerdict = null,

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
    /// The `law.c.floor` plan: one `.lowering` variable per callable, each
    /// holding the C-equivalent baseline and whatever native candidate exists.
    /// It remains separate so `variables` reports representation choices while
    /// both dimensions retain their own explicit JSON projections.
    lowering: []Variable = &.{},

    pub fn deinit(self: *ModuleRealizations, alloc: std.mem.Allocator) void {
        alloc.free(self.file);
        for (self.variables) |*v| v.deinit(alloc);
        alloc.free(self.variables);
        for (self.lowering) |*v| v.deinit(alloc);
        alloc.free(self.lowering);
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

// ── constitution §47 · C IS A CANDIDATE, NOT THE CEILING ─────────────────────
//
// Three laws land here, and each is one readable rule rather than a subsystem:
//
//   law.c.floor        `loweringVariableForFunc` always emits `lower.cequiv`,
//                      marked `baseline`. There is no path that builds a
//                      lowering variable without it.
//   law.perf.floor     `selectAgainstFloor` STARTS at the baseline and only
//                      moves off it for a candidate that DOMINATES on the
//                      §47 frontier with `proven` or `measured` evidence. An
//                      estimate cannot unseat the floor.
//   law.perf.dominance `monotoneAgainst` checks that a candidate SET never
//                      shrinks when a fact is added. Legality may flip either
//                      way — an invalid candidate is allowed to be removed —
//                      but the option may not disappear from the plan.
//
// WHAT THIS IS NOT. It is not a general cost model, and nothing here decides
// which backend actually runs. It is a plan the compiler can state and defend;
// `duo explain` renders it and `zig build c-floor` measures whether the plan
// and the measured world agree. The distance between the two is the finding.

/// `law.perf.floor`. Returns the index of the selected candidate.
///
/// Selection is BASELINE-FIRST: the retained candidate starts as the baseline
/// (the C floor), and each other legal candidate must dominate the incumbent on
/// the §47 frontier before it replaces it. Two guards make this honest rather
/// than optimistic:
///
///   - `.insufficient` (no dimension known on both sides) never replaces. A
///     candidate with no cost facts cannot win by having no facts.
///   - `.dominates` under `estimated` evidence never replaces. law.perf.floor
///     says "until another candidate is PROVEN OR MEASURED superior"; an
///     ordinal guess is neither.
///
/// With no baseline present this degrades to "first legal candidate that
/// dominates", which is the same rule with nothing retained.
pub fn selectAgainstFloor(var_: *Variable, objective: semantic_algebra.Objective) ?usize {
    const dims = objective.dimensions();
    var incumbent: ?usize = null;
    for (var_.candidates, 0..) |c, i| {
        if (c.legal and c.baseline) {
            incumbent = i;
            break;
        }
    }
    if (incumbent == null) {
        for (var_.candidates, 0..) |c, i| {
            if (c.legal) {
                incumbent = i;
                break;
            }
        }
    }
    const start = incumbent orelse {
        var_.selected_index = null;
        return null;
    };

    var cur = start;
    for (var_.candidates, 0..) |*c, i| {
        if (i == cur or !c.legal) continue;
        const v = c.cost.compare(var_.candidates[cur].cost, dims);
        c.verdict = v;
        if (v.unseats()) cur = i;
    }
    // Re-state every candidate's verdict against the FINAL incumbent, so
    // `why(skip)` answers against what was actually chosen rather than against
    // whatever happened to be incumbent when the loop reached it.
    for (var_.candidates, 0..) |*c, i| {
        if (i == cur) {
            c.verdict = null;
            continue;
        }
        if (!c.legal) continue;
        c.verdict = c.cost.compare(var_.candidates[cur].cost, dims);
    }
    var_.selected_index = cur;
    return cur;
}

/// `law.perf.dominance` — "adding semantic facts may NEVER reduce the
/// realization set". A finding names the variable and the candidate that went
/// missing; `null` means the law held.
pub const MonotonicityFinding = struct {
    variable: []const u8,
    missing_candidate: []const u8,
};

/// Does `after` (built with MORE semantic facts) still offer everything
/// `before` offered? Matching is by variable id, then by candidate id.
///
/// A variable absent from `after` entirely is NOT a finding: the fact may have
/// deleted the subject. A variable that survives with a candidate missing IS —
/// that is the compiler forgetting an option it had.
pub fn monotoneAgainst(before: *const ModuleRealizations, after: *const ModuleRealizations) ?MonotonicityFinding {
    if (monotoneOver(before.variables, after.variables)) |f| return f;
    return monotoneOver(before.lowering, after.lowering);
}

fn monotoneOver(before: []const Variable, after: []const Variable) ?MonotonicityFinding {
    for (before) |bv| {
        const av = blk: {
            for (after) |*x| {
                if (std.mem.eql(u8, x.id, bv.id)) break :blk x;
            }
            break :blk null;
        } orelse continue;
        for (bv.candidates) |bc| {
            var found = false;
            for (av.candidates) |ac| {
                if (std.mem.eql(u8, ac.id, bc.id)) {
                    found = true;
                    break;
                }
            }
            if (!found) return .{ .variable = bv.id, .missing_candidate = bc.id };
        }
    }
    return null;
}

/// Every param and the return of `fd` lowers to a native C scalar/aggregate.
///
/// This is the legality fact for the native candidate, and it is deliberately
/// STRUCTURAL: it reads declared descriptors through `types.resolve` and the
/// knowledge lattice. It never looks at the callable's NAME, at a literal, or
/// at a loop bound — §3's first rule. An `any` param disqualifies the whole
/// callable, which is the measured behaviour of the direct backend today.
fn funcLowersNative(alloc: std.mem.Allocator, fd: *const ast.FuncDecl) bool {
    if (fd.func.vararg) return false;
    for (fd.func.params) |p| {
        const rt = types.resolve(p.typ, null, alloc) catch return false;
        if (!semantic_algebra.lowersToNativeC(rt)) return false;
    }
    const ret = types.resolve(fd.func.ret_type, null, alloc) catch return false;
    if (ret == .void) return true;
    return semantic_algebra.lowersToNativeC(ret);
}

/// The `law.c.floor` variable for one callable: the C-equivalent lowering as a
/// retained baseline, plus the direct native lowering as a challenger.
///
/// COST FACTS ATTACHED HERE: **NONE, ON EITHER CANDIDATE**, and that is a
/// measured position rather than an unfinished one.
///
/// The first draft of this builder attached `compile_time` as PROVEN — the
/// C-equivalent path spawns an external C compiler process and the direct path
/// does not, so the ordering looked structural rather than estimated. Then
/// `zig build c-floor` measured it on `examples/cfloor/fact.id` and the
/// ordering was BACKWARDS: the direct backend does more work in-process than
/// the spawn costs. A process-spawn fact never entailed a wall-time ordering;
/// the label was doing the work the evidence was supposed to do.
///
/// It was DELETED rather than demoted to `estimated`, because an estimate
/// pointing the wrong way is still a wrong number, and an estimate can never
/// unseat a baseline anyway — it would have been decoration on the render with
/// no effect on the selection. §3: "a detector must verify every constant its
/// emitter assumes, and decline to the general path otherwise."
///
/// So the honest state of the slice, and the render says exactly this: the
/// compiler holds TWO candidates for every callable, knows the C-equivalent one
/// is always available, knows whether the native one is legal — and holds no
/// cost fact that would let it prefer either. `why(skip)` answers
/// `insufficient · compared 0 · missing 12`, the floor is RETAINED, and the
/// twelve empty slots are the shape of the work between here and a claim.
pub const LOWERING_COST_FACTS_ATTACHED: usize = 0;
pub fn loweringVariableForFunc(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    func_name: []const u8,
    objective: semantic_algebra.Objective,
) !Variable {
    const subject = try entityId(alloc, "func", func_name);
    errdefer alloc.free(subject);
    const var_id = try std.fmt.allocPrint(alloc, "realize.lowering:{s}", .{func_name});
    errdefer alloc.free(var_id);

    const native_ok = funcLowersNative(alloc, fd);

    var candidates: std.ArrayListUnmanaged(Candidate) = .empty;
    errdefer {
        for (candidates.items) |*c| c.deinit(alloc);
        candidates.deinit(alloc);
    }

    // law.c.floor: the baseline is unconditional. There is no `if` here on
    // purpose — "wherever a C-equivalent realization exists it is a baseline
    // candidate", and the C backend is total over the checked language.
    try appendCandidate(alloc, &candidates, "lower.cequiv", "C-equivalent lowering (baseline)", "c_translation_unit", 50, 60, true, null, .proven);
    candidates.items[0].baseline = true;

    try appendCandidate(
        alloc,
        &candidates,
        "lower.native",
        "Direct machine-code lowering",
        "arm64_object",
        40,
        50,
        native_ok,
        if (native_ok) null else "a declared descriptor on this callable does not lower to a native C scalar",
        if (native_ok) .proven else .estimated,
    );

    var freedoms: std.ArrayListUnmanaged(DegreeOfFreedom) = .empty;
    errdefer {
        for (freedoms.items) |*f| f.deinit(alloc);
        freedoms.deinit(alloc);
    }
    try freedoms.append(alloc, .{
        .kind = .multiversion,
        .status = if (native_ok) .negotiable else .fixed_requirement,
        .scope = try alloc.dupe(u8, func_name),
        .source = try alloc.dupe(u8, "law.c.floor"),
    });

    var var_: Variable = .{
        .id = var_id,
        .subject_entity = subject,
        .dimension = .lowering,
        .candidates = try candidates.toOwnedSlice(alloc),
        .hard_constraints = try alloc.dupe(u8, "observable answer identical across candidates"),
        .freedoms = try freedoms.toOwnedSlice(alloc),
        .rejections = &.{},
    };
    _ = selectAgainstFloor(&var_, objective);
    return var_;
}

/// One `.lowering` variable per module-scope callable in the graph.
pub fn buildLoweringFloor(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    objective: semantic_algebra.Objective,
) ![]Variable {
    var vars: std.ArrayListUnmanaged(Variable) = .empty;
    errdefer {
        for (vars.items) |*v| v.deinit(alloc);
        vars.deinit(alloc);
    }
    for (graph.nodes.items) |*node| {
        if (node.kind != .func) continue;
        const name = node.name orelse continue;
        const raw = node.ast_ref orelse continue;
        const fd: *const ast.FuncDecl = @ptrCast(@alignCast(raw));
        try vars.append(alloc, try loweringVariableForFunc(alloc, fd, name, objective));
    }
    return vars.toOwnedSlice(alloc);
}

/// Number of lawful candidates retained for extraction.
pub fn legalCandidateCount(var_: *const Variable) usize {
    var n: usize = 0;
    for (var_.candidates) |c| {
        if (c.legal) n += 1;
    }
    return n;
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
        var sel = try selectDeterministic(alloc, &var_);
        var_.rejections = sel.rejections;
        if (sel.selected_id) |sid| alloc.free(sid);
        sel.rejections = &.{};
        sel.deinit(alloc);
    }
    return var_;
}

pub fn buildDeferredFromGraph(alloc: std.mem.Allocator, graph: *const semantic_graph.SemanticGraph, file: []const u8) !ModuleRealizations {
    return buildFromGraphOptions(alloc, graph, file, .{ .auto_select = false, .c_floor = false });
}

pub fn buildFromGraph(alloc: std.mem.Allocator, graph: *const semantic_graph.SemanticGraph, file: []const u8) !ModuleRealizations {
    return buildFromGraphOptions(alloc, graph, file, .{ .auto_select = true, .c_floor = true });
}

fn buildFromGraphOptions(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    file: []const u8,
    options: struct {
        auto_select: bool,
        c_floor: bool = false,
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
        })) |v| {
            try vars.append(alloc, v);
        }
    }

    return .{
        .file = try alloc.dupe(u8, file),
        .variables = try vars.toOwnedSlice(alloc),
        .lowering = if (options.c_floor) try buildLoweringFloor(alloc, graph, C_FLOOR_OBJECTIVE) else &.{},
    };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

/// The cost facts that EXIST, and only those. An unknown dimension is absent
/// from the render rather than printed as zero — a rendered zero is exactly how
/// "no fact" turned into "free" in the vector this replaced.
fn writeCostJson(cost: semantic_algebra.CostVector, w: *std.Io.Writer) !void {
    try w.print("{{\"known\":{d},\"dimensions\":{{", .{cost.knownCount()});
    var first = true;
    for (semantic_algebra.CostDimension.constitutional) |dim| {
        const f = cost.get(dim);
        if (!f.known()) continue;
        if (!first) try w.print(",", .{});
        first = false;
        try w.print("\"{s}\":{{\"value\":{d:.6},\"evidence\":\"{s}\"}}", .{ dim.name(), f.value, f.evidence.name() });
    }
    try w.print("}}}}", .{});
}

/// `why(skip)` for a rejected or unselected candidate; `why(realize)` for the
/// chosen one. Both are the SAME facts read from the same verdict — H-8: the
/// answer is graph data, never a sentence assembled for a human.
fn writeVerdictJson(v: semantic_algebra.DominanceVerdict, w: *std.Io.Writer) !void {
    try w.print(
        "{{\"relation\":\"{s}\",\"compared\":{d},\"missing\":{d},\"better\":{d},\"worse\":{d},\"evidence\":\"{s}\",\"unseats\":{s}",
        .{ v.relationName(), v.compared, v.missing, v.better, v.worse, v.evidence.name(), if (v.unseats()) "true" else "false" },
    );
    if (v.decided_by) |d| try w.print(",\"decided\":\"{s}\"", .{d.name()});
    try w.print("}}", .{});
}

fn writeCandidateJson(c: Candidate, w: *std.Io.Writer) !void {
    try w.print("{{\"id\":\"", .{});
    try jsonEscape(w, c.id);
    try w.print("\",\"label\":\"", .{});
    try jsonEscape(w, c.label);
    try w.print("\",\"representation\":\"", .{});
    try jsonEscape(w, c.representation);
    try w.print("\",\"static_cost\":{d},\"optionality_retained\":{d},\"legal\":", .{ c.static_cost, c.optionality_retained });
    try w.print("{s}", .{if (c.legal) "true" else "false"});
    try w.print(",\"evidence\":\"{s}\"", .{c.evidence.name()});
    if (c.baseline) try w.print(",\"baseline\":true", .{});
    if (c.cost.knownCount() > 0) {
        try w.print(",\"cost\":", .{});
        try writeCostJson(c.cost, w);
    }
    if (c.verdict) |v| {
        try w.print(",\"why\":{{\"skip\":", .{});
        try writeVerdictJson(v, w);
        try w.print("}}", .{});
    }
    if (c.rejection_reason) |r| {
        try w.print(",\"rejection_reason\":\"", .{});
        try jsonEscape(w, r);
        try w.print("\"", .{});
    }
    try w.print("}}", .{});
}

fn writeVariableJson(var_: Variable, w: *std.Io.Writer) !void {
    try w.print("{{\"id\":\"", .{});
    try jsonEscape(w, var_.id);
    try w.print("\",\"subject_entity\":\"", .{});
    try jsonEscape(w, var_.subject_entity);
    try w.print("\",\"dimension\":\"{s}\",\"viable\":{d},\"total\":{d},\"candidates\":[", .{
        var_.dimension.name(), legalCandidateCount(&var_), var_.candidates.len,
    });
    for (var_.candidates, 0..) |c, j| {
        if (j > 0) try w.print(",", .{});
        try writeCandidateJson(c, w);
    }
    try w.print("]", .{});
    if (var_.selected_index) |si| {
        const sel = var_.candidates[si];
        try w.print(",\"selected_index\":{d},\"selected_id\":\"", .{si});
        try jsonEscape(w, sel.id);
        try w.print("\"", .{});
        // why(realize). `retained` is the load-bearing bit: it says the
        // baseline was KEPT because nothing beat it, which is a different fact
        // from the baseline having been chosen on merit.
        //
        // Every key this block introduces is ONE LOWERCASE WORD. The older keys
        // beside it (`selected_id`, `subject_entity`, `static_cost`) are not,
        // and are left alone because other gates read them — but H-8 makes an
        // emission graph data rendered through the taxonomy, and LAW-ONE governs
        // the taxonomy, so new keys obey it. `choice` exists so a duon consumer
        // can read the selection without writing `selected_id` in a literal.
        try w.print(",\"why\":{{\"realize\":{{\"law\":\"law.perf.floor\",\"retained\":{s},\"choice\":\"", .{
            if (sel.baseline) "true" else "false",
        });
        try jsonEscape(w, sel.id);
        try w.print("\"", .{});
        try w.print(",\"cost\":", .{});
        try writeCostJson(sel.cost, w);
        try w.print("}}}}", .{});
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

pub fn writeJson(m: *const ModuleRealizations, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"file\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, m.file);
    try w.print("\",\"variable_count\":{d},\"variables\":[", .{m.variables.len});
    for (m.variables, 0..) |var_, i| {
        if (i > 0) try w.print(",", .{});
        try writeVariableJson(var_, w);
    }
    try w.print("]", .{});
    try w.print(",\"c_floor\":{{\"schema\":\"{s}\",\"law\":\"law.c.floor\",\"objective\":\"{s}\",\"relevant_dimensions\":{d},\"lowerings\":{d},\"variables\":[", .{
        C_FLOOR_SCHEMA_VERSION,
        C_FLOOR_OBJECTIVE.name(),
        C_FLOOR_OBJECTIVE.dimensions().len,
        m.lowering.len,
    });
    for (m.lowering, 0..) |var_, i| {
        if (i > 0) try w.print(",", .{});
        try writeVariableJson(var_, w);
    }
    try w.print("]}}}}", .{});
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
    var lex = Lexer.init(src, "point.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.id");

    var m = try buildFromGraph(alloc, &graph, "point.id");
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

test "realization: deferred candidates remain lawful until deterministic extraction" {
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
    var lex = Lexer.init(src, "user.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "user.id");

    var deferred = try buildDeferredFromGraph(alloc, &graph, "user.id");
    defer deferred.deinit(alloc);
    try std.testing.expect(deferred.variables.len >= 1);
    const candidate_count = deferred.variables[0].candidates.len;
    const legal_count = legalCandidateCount(&deferred.variables[0]);
    try std.testing.expect(legal_count >= 2);
    try std.testing.expect(deferred.variables[0].selected_index == null);

    var selection = try selectDeterministic(alloc, &deferred.variables[0]);
    defer selection.deinit(alloc);
    const selected = deferred.variables[0].selected() orelse return error.TestExpectedEqual;
    try std.testing.expect(selected.legal);
    try std.testing.expectEqualStrings("repr.native_sealed", selected.id);
    try std.testing.expectEqual(candidate_count, deferred.variables[0].candidates.len);
    try std.testing.expectEqual(legal_count, legalCandidateCount(&deferred.variables[0]));
}

// ── §47 slice: two candidates, cost by value, floor retained ─────────────────

const CFloorFixture = struct {
    arena: *std.heap.ArenaAllocator,
    graph: semantic_graph.SemanticGraph,
    sem: @import("sema.zig").Sema,
    mod: ast.Module,

    fn init(arena: *std.heap.ArenaAllocator, src: []const u8, file: []const u8) !CFloorFixture {
        const alloc = arena.allocator();
        var lex = @import("lexer.zig").Lexer.init(src, file);
        var parser = @import("parser.zig").Parser.init(&lex, alloc);
        parser.duo_mode = true;
        const mod = try parser.parse_module();
        var semantic = @import("sema.zig").Sema.init(alloc);
        semantic.duo_mode = true;
        var m = mod;
        try semantic.check_module(&m);
        var graph = semantic_graph.SemanticGraph.init(alloc);
        _ = try graph.liftModuleWithCalls(&m, file);
        return .{ .arena = arena, .graph = graph, .sem = semantic, .mod = m };
    }

    fn deinit(self: *CFloorFixture) void {
        self.graph.deinit();
        self.sem.deinit();
    }
};

fn findVar(vars: []Variable, id: []const u8) ?*Variable {
    for (vars) |*v| {
        if (std.mem.eql(u8, v.id, id)) return v;
    }
    return null;
}

fn findCandidate(var_: *const Variable, id: []const u8) ?*const Candidate {
    for (var_.candidates) |*c| {
        if (std.mem.eql(u8, c.id, id)) return c;
    }
    return null;
}

test "cfloor: law.c.floor — a native-eligible callable still carries the C baseline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fx = try CFloorFixture.init(&arena,
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "add.id");
    defer fx.deinit();

    const vars = try buildLoweringFloor(alloc, &fx.graph, .balanced);
    const v = findVar(vars, "realize.lowering:add") orelse return error.TestExpectedEqual;
    // TWO candidates, and the C-equivalent one is present on a callable the
    // direct backend can lower perfectly well. That is the whole of law.c.floor:
    // the baseline is not conditional on the native path failing.
    try std.testing.expectEqual(@as(usize, 2), v.candidates.len);
    const c = findCandidate(v, "lower.cequiv") orelse return error.TestExpectedEqual;
    const n = findCandidate(v, "lower.native") orelse return error.TestExpectedEqual;
    try std.testing.expect(c.baseline);
    try std.testing.expect(c.legal);
    try std.testing.expect(n.legal);
    try std.testing.expect(!n.baseline);
}

test "cfloor: law.perf.floor — with no cost fact the floor is RETAINED, not guessed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fx = try CFloorFixture.init(&arena,
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "add.id");
    defer fx.deinit();

    const vars = try buildLoweringFloor(alloc, &fx.graph, .balanced);
    const v = findVar(vars, "realize.lowering:add") orelse return error.TestExpectedEqual;
    const n = findCandidate(v, "lower.native") orelse return error.TestExpectedEqual;
    const verdict = n.verdict orelse return error.TestExpectedEqual;

    // By VALUE, and this is the honest state of the slice: zero of the twelve
    // relevant dimensions carry a fact on both sides, so there is no comparison
    // to win. `insufficient` is not a tie and not a loss — it is the compiler
    // declining to prefer, which is what law.perf.floor asks of it.
    try std.testing.expectEqual(semantic_algebra.DominanceVerdict.Relation.insufficient, verdict.relation);
    try std.testing.expectEqual(@as(u8, 0), verdict.compared);
    try std.testing.expectEqual(@as(u8, 12), verdict.missing);
    try std.testing.expectEqual(semantic_algebra.CostEvidence.unknown, verdict.evidence);
    try std.testing.expect(verdict.decided_by == null);
    try std.testing.expect(!verdict.unseats());
    try std.testing.expectEqual(@as(u8, 0), n.cost.knownCount());
    try std.testing.expectEqual(@as(usize, 0), LOWERING_COST_FACTS_ATTACHED);
    const sel = v.selected() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("lower.cequiv", sel.id);
    try std.testing.expect(sel.baseline);
}

test "cfloor: measured facts covering the objective DO unseat the floor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fx = try CFloorFixture.init(&arena,
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "add.id");
    defer fx.deinit();

    // Objective `latency` is two dimensions. Supply BOTH, measured, for both
    // candidates — the shape `zig build c-floor` produces from a real run — and
    // the same selector that retained the floor above now moves off it. Without
    // this the retention above proves only that the selector never moves.
    const vars = try buildLoweringFloor(alloc, &fx.graph, .latency);
    const v = findVar(vars, "realize.lowering:add") orelse return error.TestExpectedEqual;
    for (v.candidates) |*c| {
        const native = std.mem.eql(u8, c.id, "lower.native");
        c.cost.setFact(.latency, if (native) 0.9 else 1.0, .measured);
        c.cost.setFact(.tail_latency, if (native) 0.95 else 1.0, .measured);
    }
    const idx = selectAgainstFloor(v, .latency) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("lower.native", v.candidates[idx].id);

    // And the negative half: flip the measurement and the floor is kept.
    for (v.candidates) |*c| {
        const native = std.mem.eql(u8, c.id, "lower.native");
        c.cost.setFact(.latency, if (native) 1.1 else 1.0, .measured);
        c.cost.setFact(.tail_latency, if (native) 1.2 else 1.0, .measured);
    }
    const idx2 = selectAgainstFloor(v, .latency) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("lower.cequiv", v.candidates[idx2].id);
}

test "cfloor: an `any` descriptor makes native invalid and the floor is the only option" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fx = try CFloorFixture.init(&arena,
        \\add(a: any, b: any): any
        \\    a + b
        \\end
    , "anyadd.id");
    defer fx.deinit();

    const vars = try buildLoweringFloor(alloc, &fx.graph, .balanced);
    const v = findVar(vars, "realize.lowering:add") orelse return error.TestExpectedEqual;
    // The candidate is still THERE — law.perf.dominance forbids forgetting it —
    // it is merely not legal.
    try std.testing.expectEqual(@as(usize, 2), v.candidates.len);
    const n = findCandidate(v, "lower.native") orelse return error.TestExpectedEqual;
    try std.testing.expect(!n.legal);
    try std.testing.expect(n.rejection_reason != null);
    try std.testing.expectEqual(@as(usize, 1), legalCandidateCount(v));
    try std.testing.expectEqualStrings("lower.cequiv", (v.selected() orelse return error.TestExpectedEqual).id);
}

test "cfloor: law.perf.dominance — adding a fact does not shrink the candidate set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Same program twice; the second states descriptors the first left as `any`.
    var weak = try CFloorFixture.init(&arena,
        \\add(a: any, b: any): any
        \\    a + b
        \\end
    , "m.id");
    defer weak.deinit();
    var strong = try CFloorFixture.init(&arena,
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "m.id");
    defer strong.deinit();

    var before = try buildFromGraph(alloc, &weak.graph, "m.id");
    defer before.deinit(alloc);
    var after = try buildFromGraph(alloc, &strong.graph, "m.id");
    defer after.deinit(alloc);

    try std.testing.expect(monotoneAgainst(&before, &after) == null);

    // The fact must actually DO something, or the law above is satisfied by a
    // pair of identical plans and proves nothing. Legality grows 1 -> 2.
    const b = findVar(before.lowering, "realize.lowering:add") orelse return error.TestExpectedEqual;
    const a = findVar(after.lowering, "realize.lowering:add") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), legalCandidateCount(b));
    try std.testing.expectEqual(@as(usize, 2), legalCandidateCount(a));
    try std.testing.expectEqual(b.candidates.len, a.candidates.len);
}

test "cfloor: the monotonicity checker FIRES when a candidate is deleted" {
    // The positive control for the test above. A checker that cannot report a
    // violation is a gate reporting a confident zero.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fx = try CFloorFixture.init(&arena,
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "m.id");
    defer fx.deinit();

    var before = try buildFromGraph(alloc, &fx.graph, "m.id");
    defer before.deinit(alloc);
    var after = try buildFromGraph(alloc, &fx.graph, "m.id");
    defer after.deinit(alloc);
    try std.testing.expect(monotoneAgainst(&before, &after) == null);

    // Delete the native option from the later plan — the exact shape of "a fact
    // made the compiler forget an option it had".
    const a = findVar(after.lowering, "realize.lowering:add") orelse return error.TestExpectedEqual;
    a.candidates = a.candidates[0..1];
    const finding = monotoneAgainst(&before, &after) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("realize.lowering:add", finding.variable);
    try std.testing.expectEqualStrings("lower.native", finding.missing_candidate);
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
    var lex = @import("lexer.zig").Lexer.init(src, "point.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = @import("sema.zig").Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&mod, "point.id");
    const fp = try fingerprintForRecordEntity(alloc, &graph, "Point", "native", DEFAULT_TRANSFORM_VERSION);
    try std.testing.expect(fp != 0);
}
