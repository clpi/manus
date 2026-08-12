/// Resident semantic graph.
///
/// An `id` names one exact entity in this resident graph. Names,
/// paths, spans, and fingerprints are provenance or query projections; none of
/// them can create or recover semantic identity.
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
const sema = @import("sema.zig");
const types = @import("types.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
pub const id = u32;

pub const State = enum {
    frozen_snapshot,
    open_semantic,
    sealed,
    derived,
    mutable_builder,

    pub fn name(self: State) []const u8 {
        return @tagName(self);
    }
};

pub const Recursion = enum {
    none,
    indirect_pointer,
    inline_fixed_point,
    mutual_module,
    foreign_recursive,

    pub fn name(self: Recursion) []const u8 {
        return @tagName(self);
    }
};

pub const Completion = enum {
    placeholder,
    resolving,
    complete,
    invalid_incomplete,

    pub fn name(self: Completion) []const u8 {
        return @tagName(self);
    }
};

fn referencesDescriptorName(rt: types.ResolvedType, name: []const u8) bool {
    switch (rt) {
        .@"struct" => |s| return std.mem.eql(u8, s.name, name),
        .pointer => |p| return referencesDescriptorName(p.*, name),
        .table_type => |t| {
            for (t.fields) |f| {
                if (referencesDescriptorName(f.typ, name)) return true;
            }
            return false;
        },
        .enum_type => |e| {
            if (std.mem.eql(u8, e.name, name)) return true;
            for (e.variants) |v| {
                if (v.payload) |payload| {
                    for (payload) |p| {
                        if (referencesDescriptorName(p, name)) return true;
                    }
                }
            }
            return false;
        },
        else => return false,
    }
}

fn referencesDescriptorInline(rt: types.ResolvedType, name: []const u8) bool {
    switch (rt) {
        .@"struct" => |s| return std.mem.eql(u8, s.name, name),
        .table_type => |t| {
            for (t.fields) |f| {
                if (referencesDescriptorInline(f.typ, name)) return true;
            }
            return false;
        },
        .enum_type => |e| {
            for (e.variants) |v| {
                if (v.payload) |payload| {
                    for (payload) |p| {
                        if (referencesDescriptorInline(p, name)) return true;
                    }
                }
            }
            return false;
        },
        else => return false,
    }
}

fn classifyDescriptorRecursion(name: []const u8, rt: types.ResolvedType) Recursion {
    if (!referencesDescriptorName(rt, name)) return .none;
    if (referencesDescriptorInline(rt, name)) return .inline_fixed_point;
    return .indirect_pointer;
}

fn inferDescriptorState(sc: types.StorageClass, is_sealed: bool) State {
    if (is_sealed) return .sealed;
    return switch (sc) {
        .native, .sealed => .sealed,
        .guarded, .dynamic => .open_semantic,
    };
}

fn resolveDescriptorCompletion(
    recursion: Recursion,
    rt: types.ResolvedType,
) Completion {
    if (recursion == .none) return .complete;
    if (rt == .any) return .invalid_incomplete;
    return .complete;
}

pub const NodeKind = enum {
    module,
    source_file,
    func,
    param,
    local,
    value,
    type_node,
    call,
    relation,
    concept,
    transform_app,
    comptime_value,
    emit_artifact,
    /// Typed table/record shape node (storage class + field count).
    table_shape,
    /// Enum descriptor shape (variant count in `field_count`; names via `ast_ref`).
    enum_shape,
};

pub const EdgeKind = enum {
    contains,
    def,
    use,
    relation,
    subject,
    argument,
    result,
    type_of,
    transform_input,
    transform_output,
    provenance,
};

pub const SpanRef = struct {
    file: []const u8,
    start: u32,
    end: u32,
};

fn sameSpan(a: SpanRef, b: SpanRef) bool {
    return a.start == b.start and a.end == b.end and std.mem.eql(u8, a.file, b.file);
}

pub const Node = struct {
    kind: NodeKind,
    span: SpanRef,
    name: ?[]const u8 = null,
    /// For `.table_shape`: storage class label (dynamic/guarded/sealed/native).
    storage_class: ?types.StorageClass = null,
    field_count: u16 = 0,
    /// Shape-content fingerprint used by current realization candidates.
    /// It never selects or identifies a graph entity.
    shape_id: ?u64 = null,
    /// Derived call-shape fingerprint for specialization candidate retrieval.
    /// Exact call identity remains the graph id.
    call_shape_fingerprint: ?u64 = null,
    /// For `.call` nodes: the inferred CallShape (Phase 1 — conservative from AST).
    call_shape: ?types.CallShape = null,
    /// Resolved result descriptor attached to a function's semantic identity.
    result_descriptor: ?types.ResolvedType = null,
    /// Checked descriptor of a semantic value or application result.
    descriptor: ?types.ResolvedType = null,
    /// Demand attached to an application before realization selects control.
    demand: ?types.ReturnConsumption = null,
    /// Factual `@comp.why.shape` explanation captured at graph lift.
    why: ?[]const u8 = null,
    /// Pass 2: knowledge lattice position when known.
    knowledge: ?semantic_algebra.KnowledgeLevel = null,
    /// Pass 2: evaluation stage when known.
    stage: ?semantic_algebra.Stage = null,
    /// Pass 2.1: descriptor algebra hash for alias/type nodes (internal).
    descriptor_hash: ?u64 = null,
    /// Pass 26 M1: descriptor lifecycle state at lift.
    descriptor_state: ?State = null,
    /// Pass 26 M1: recursive layout classification.
    recursion: ?Recursion = null,
    /// Pass 26 M1: fixed-point resolution status.
    completion: ?Completion = null,
    /// Human-readable descriptor composition label (`Point+Named`).
    descriptor_label: ?[]const u8 = null,
    /// Iteration relation identity. A source face such as `|>` is provenance,
    /// not a persistent node kind.
    iteration_relation: ?semantic_algebra.IterationRelation = null,
    /// Lawful hardware realization candidates for the relation (cpu/simd/gpu).
    hardware_lowerings: semantic_algebra.HardwareSet = .{},
    /// Opaque link to AST for Phase 1 — graph mirrors, does not replace, AST yet.
    ast_ref: ?*anyopaque = null,
    /// The graph entity this one is nested inside. The `.contains` edge is a
    /// projection of this field; `addChild` writes both from one call.
    scope: ?id = null,
    /// When true, `name` was allocated on the graph allocator and must be freed in deinit.
    owns_name: bool = false,
};

pub const Edge = struct {
    from: id,
    to: id,
    kind: EdgeKind,
    position: u16 = 0,
};

pub const FactRange = struct {
    start: u32,
    len: u32,
};

/// Graph-owned facts for one checked relation application. The application
/// id is the key; packed ranges are physical projections over the graph's
/// shared value storage.
pub const ApplicationFact = struct {
    application: id,
    relation: id,
    subject: ?id,
    caller: id,
    descriptor: types.ResolvedType,
    demand: types.ReturnConsumption,
    provenance: SpanRef,
    arguments: FactRange,
    results: FactRange,
};

pub const SemanticGraph = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    edges: std.ArrayListUnmanaged(Edge) = .empty,
    application_facts: std.ArrayListUnmanaged(ApplicationFact) = .empty,
    application_values: std.ArrayListUnmanaged(id) = .empty,
    application_rows: std.ArrayListUnmanaged(u32) = .empty,
    application_presence: std.DynamicBitSetUnmanaged = .{},
    application_candidates: std.DynamicBitSetUnmanaged = .{},
    pub fn init(alloc: std.mem.Allocator) SemanticGraph {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *SemanticGraph) void {
        for (self.nodes.items) |node| {
            self.deinitNode(node);
        }
        self.nodes.deinit(self.alloc);
        self.edges.deinit(self.alloc);
        self.application_facts.deinit(self.alloc);
        self.application_values.deinit(self.alloc);
        self.application_rows.deinit(self.alloc);
        self.application_presence.deinit(self.alloc);
        self.application_candidates.deinit(self.alloc);
    }

    fn deinitNode(self: *SemanticGraph, node: Node) void {
        if (node.why) |why| self.alloc.free(why);
        if (node.descriptor_label) |descriptor| self.alloc.free(descriptor);
        if (node.owns_name) {
            if (node.name) |name| self.alloc.free(name);
        }
    }

    fn coordinateForLength(len: usize) !id {
        if (comptime @bitSizeOf(usize) > @bitSizeOf(id)) {
            if (len > std.math.maxInt(id)) return error.GraphCoordinateExhausted;
        }
        return @intCast(len);
    }

    pub fn addNode(self: *SemanticGraph, node: Node) !id {
        const entity = try coordinateForLength(self.nodes.items.len);
        try self.nodes.append(self.alloc, node);
        return entity;
    }

    /// Add `node` inside `parent`: records the scope fact and emits the
    /// `.contains` edge that projects it. Both used to be written by hand at
    /// every lift site, and the scope half was simply never written — which is
    /// how a parameter and a module function came to share one identity.
    pub fn addChild(self: *SemanticGraph, parent: id, node: Node) !id {
        var n = node;
        n.scope = parent;
        errdefer self.deinitNode(n);
        const entity = try self.addNode(n);
        errdefer {
            const removed = self.nodes.pop() orelse unreachable;
            std.debug.assert(removed.scope == parent);
        }
        try self.addEdge(.{ .from = parent, .to = entity, .kind = .contains });
        return entity;
    }

    pub fn addEdge(self: *SemanticGraph, edge: Edge) !void {
        try self.edges.append(self.alloc, edge);
    }

    pub fn get(self: *const SemanticGraph, entity: id) ?*const Node {
        if (entity >= self.nodes.items.len) return null;
        return &self.nodes.items[entity];
    }

    fn ensureApplicationRows(self: *SemanticGraph) !void {
        if (self.application_rows.items.len < self.nodes.items.len) {
            try self.application_rows.appendNTimes(
                self.alloc,
                0,
                self.nodes.items.len - self.application_rows.items.len,
            );
        }
        if (self.application_presence.bit_length < self.nodes.items.len) {
            try self.application_presence.resize(self.alloc, self.nodes.items.len, false);
        }
        if (self.application_candidates.bit_length < self.nodes.items.len) {
            try self.application_candidates.resize(self.alloc, self.nodes.items.len, false);
        }
    }

    fn factRange(start: usize, len: usize) !FactRange {
        if (start > std.math.maxInt(u32) or len > std.math.maxInt(u32)) {
            return error.ApplicationFactCapacityExceeded;
        }
        const end = std.math.add(usize, start, len) catch
            return error.ApplicationFactCapacityExceeded;
        if (end > std.math.maxInt(u32)) return error.ApplicationFactCapacityExceeded;
        return .{ .start = @intCast(start), .len = @intCast(len) };
    }

    fn valuesForRange(self: *const SemanticGraph, range: FactRange) ?[]const id {
        const start: usize = range.start;
        const end = std.math.add(usize, start, range.len) catch return null;
        if (end > self.application_values.items.len) return null;
        return self.application_values.items[start..end];
    }

    fn isApplicationCandidate(self: *const SemanticGraph, entity: id) bool {
        return entity < self.application_candidates.bit_length and
            self.application_candidates.isSet(entity);
    }

    fn markApplicationCandidate(self: *SemanticGraph, entity: id) !void {
        if (self.get(entity) == null) return error.InvalidApplicationFact;
        try self.ensureApplicationRows();
        self.application_candidates.set(entity);
    }

    fn publishApplication(
        self: *SemanticGraph,
        occurrence: id,
        relation: id,
        subject: ?id,
        caller: id,
        descriptor: types.ResolvedType,
        demand: types.ReturnConsumption,
        provenance: SpanRef,
        arguments: []const id,
        results: []const id,
    ) !void {
        const application_node = self.get(occurrence) orelse return error.InvalidApplicationFact;
        if (!self.isApplicationCandidate(occurrence) or
            application_node.descriptor == null or
            !application_node.descriptor.?.eql(descriptor) or
            application_node.demand == null or
            application_node.demand.? != demand or
            application_node.scope != caller or
            !sameSpan(application_node.span, provenance)) return error.InvalidApplicationFact;
        const relation_node = self.get(relation) orelse return error.InvalidApplicationRelation;
        if (relation_node.kind != .func and relation_node.kind != .relation) {
            return error.InvalidApplicationRelation;
        }
        const caller_node = self.get(caller) orelse return error.InvalidApplicationCaller;
        if (caller_node.kind != .func) return error.InvalidApplicationCaller;
        if (subject) |entity| {
            const node = self.get(entity) orelse return error.InvalidApplicationSubject;
            if (node.descriptor == null) return error.InvalidApplicationSubject;
        }
        for (arguments) |entity| {
            const node = self.get(entity) orelse return error.InvalidApplicationArgument;
            if (node.descriptor == null) return error.InvalidApplicationArgument;
        }
        for (results) |entity| {
            const node = self.get(entity) orelse return error.InvalidApplicationResult;
            if (node.descriptor == null or !node.descriptor.?.eql(descriptor)) {
                return error.InvalidApplicationResult;
            }
        }

        try self.ensureApplicationRows();
        if (self.application_presence.isSet(occurrence)) return error.DuplicateApplicationFact;

        const values_start = self.application_values.items.len;
        errdefer self.application_values.shrinkRetainingCapacity(values_start);
        const argument_range = try factRange(values_start, arguments.len);
        try self.application_values.appendSlice(self.alloc, arguments);
        const result_range = try factRange(self.application_values.items.len, results.len);
        try self.application_values.appendSlice(self.alloc, results);

        const row = try coordinateForLength(self.application_facts.items.len);
        try self.application_facts.append(self.alloc, .{
            .application = occurrence,
            .relation = relation,
            .subject = subject,
            .caller = caller,
            .descriptor = descriptor,
            .demand = demand,
            .provenance = provenance,
            .arguments = argument_range,
            .results = result_range,
        });
        self.application_rows.items[occurrence] = row;
        self.application_presence.set(occurrence);
    }

    pub fn applications(self: *const SemanticGraph) []const ApplicationFact {
        return self.application_facts.items;
    }

    pub fn application(self: *const SemanticGraph, occurrence: id) ?*const ApplicationFact {
        if (occurrence >= self.application_rows.items.len or
            occurrence >= self.application_presence.bit_length or
            !self.application_presence.isSet(occurrence)) return null;
        const row = self.application_rows.items[occurrence];
        if (row >= self.application_facts.items.len) return null;
        const fact = &self.application_facts.items[row];
        if (fact.application != occurrence) return null;
        const application_node = self.get(fact.application) orelse return null;
        if (!self.isApplicationCandidate(fact.application) or application_node.descriptor == null or
            !application_node.descriptor.?.eql(fact.descriptor) or
            application_node.demand == null or application_node.demand.? != fact.demand or
            application_node.scope != fact.caller or
            !sameSpan(application_node.span, fact.provenance)) return null;
        const relation_node = self.get(fact.relation) orelse return null;
        if (relation_node.kind != .func and relation_node.kind != .relation) return null;
        const caller_node = self.get(fact.caller) orelse return null;
        if (caller_node.kind != .func) return null;
        if (fact.subject) |entity| {
            const node = self.get(entity) orelse return null;
            if (node.descriptor == null) return null;
        }
        const arguments = self.valuesForRange(fact.arguments) orelse return null;
        const results = self.valuesForRange(fact.results) orelse return null;
        for (arguments) |entity| {
            const node = self.get(entity) orelse return null;
            if (node.descriptor == null) return null;
        }
        for (results) |entity| {
            const node = self.get(entity) orelse return null;
            if (node.descriptor == null or !node.descriptor.?.eql(fact.descriptor)) return null;
        }
        return fact;
    }

    pub fn applicationArguments(self: *const SemanticGraph, occurrence: id) ?[]const id {
        const fact = self.application(occurrence) orelse return null;
        return self.valuesForRange(fact.arguments);
    }

    pub fn applicationResults(self: *const SemanticGraph, occurrence: id) ?[]const id {
        const fact = self.application(occurrence) orelse return null;
        return self.valuesForRange(fact.results);
    }

    pub fn unresolvedApplicationCount(self: *const SemanticGraph, caller: ?id) usize {
        var count: usize = 0;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse {
                count += 1;
                continue;
            };
            const node = self.get(entity) orelse {
                count += 1;
                continue;
            };
            if (caller) |caller_id| {
                if (node.scope != caller_id) continue;
            }
            if (self.application(entity) == null) count += 1;
        }
        return count;
    }

    /// Bootstrap world and string descriptor faces lower through dedicated
    /// direct rules until graph vocabulary owns them (GAP-155). They remain
    /// application candidates but must not block gate transport on direct.
    pub fn unresolvedApplicationCountExcludingBootstrap(self: *const SemanticGraph, caller: ?id) usize {
        var count: usize = 0;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse {
                count += 1;
                continue;
            };
            const node = self.get(entity) orelse {
                count += 1;
                continue;
            };
            if (caller) |caller_id| {
                if (node.scope != caller_id) continue;
            }
            if (self.application(entity) != null) continue;
            if (isBootstrapApplicationNode(self, entity)) continue;
            count += 1;
        }
        return count;
    }

    pub fn isBootstrapApplicationNode(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        const raw = node.ast_ref orelse return false;
        const expr: *const ast.Expr = @ptrCast(@alignCast(raw));
        return self.bootstrapApplicationExpr(expr);
    }

    pub fn bootstrapApplicationExpr(self: *const SemanticGraph, expr: *const ast.Expr) bool {
        return isBootstrapApplicationExpr(self, expr);
    }

    fn hasFuncNamed(self: *const SemanticGraph, name: []const u8) bool {
        for (self.nodes.items) |node| {
            if (node.kind != .func) continue;
            const node_name = node.name orelse continue;
            if (std.mem.eql(u8, node_name, name)) return true;
        }
        return false;
    }

    fn astReceiverLooksStrish(obj: *const ast.Expr) bool {
        return switch (obj.*) {
            .string_lit => true,
            .method_call => true,
            .name => true,
            else => false,
        };
    }

    fn isBootstrapApplicationExpr(self: *const SemanticGraph, expr: *const ast.Expr) bool {
        _ = self;
        return expr.* == .call or expr.* == .method_call;
    }

    fn findFuncDecl(self: *const SemanticGraph, target: *const ast.FuncDecl) !?id {
        const raw: *const anyopaque = @ptrCast(target);
        var match: ?id = null;
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != .func or node.ast_ref == null) continue;
            if (@as(*const anyopaque, @ptrCast(node.ast_ref.?)) == raw) {
                if (match != null) return error.DuplicateSemanticDeclaration;
                match = @intCast(i);
            }
        }
        return match;
    }

    /// A name-facing projection is diagnostic/tooling input, never identity.
    /// Ambiguity refuses instead of selecting the first matching graph entity.
    fn findUniqueByNameOfKind(self: *const SemanticGraph, name: []const u8, kind: NodeKind) ?id {
        var match: ?id = null;
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != kind) continue;
            const node_name = node.name orelse continue;
            if (!std.mem.eql(u8, node_name, name)) continue;
            if (match != null) return null;
            match = @intCast(i);
        }
        return match;
    }

    /// Migration projection for callers that still possess only function text.
    /// Semantic consumers must retain a declaration or id instead.
    pub fn findFunc(self: *const SemanticGraph, name: []const u8) ?id {
        return self.findUniqueByNameOfKind(name, .func);
    }

    /// Relation selected for a checked application.
    pub fn applicationRelation(self: *const SemanticGraph, occurrence: id) ?id {
        return (self.application(occurrence) orelse return null).relation;
    }

    /// Result value produced by a checked application.
    pub fn applicationResult(self: *const SemanticGraph, occurrence: id) ?id {
        const results = self.applicationResults(occurrence) orelse return null;
        if (results.len != 1) return null;
        return results[0];
    }

    /// Result descriptor retained on one exact function entity.
    pub fn functionResultDescriptor(self: *const SemanticGraph, function: id) ?types.ResolvedType {
        const node = self.get(function) orelse return null;
        if (node.kind != .func) return null;
        return node.result_descriptor;
    }

    /// Migration projection for the lowering boundary that still carries only
    /// function text. Ambiguity stays unresolved.
    pub fn funcResultDescriptor(self: *const SemanticGraph, name: []const u8) ?types.ResolvedType {
        const entity = self.findFunc(name) orelse return null;
        return self.functionResultDescriptor(entity);
    }

    /// Textual projection across all kinds. Ambiguity remains unresolved.
    pub fn findByName(self: *const SemanticGraph, name: []const u8) ?id {
        var match: ?id = null;
        for (self.nodes.items, 0..) |node, i| {
            if (node.name) |n| {
                if (!std.mem.eql(u8, n, name)) continue;
                if (match != null) return null;
                match = @intCast(i);
            }
        }
        return match;
    }

    /// Textual projection for diagnostics. Ambiguity remains unresolved.
    pub fn findByNameOfKind(self: *const SemanticGraph, name: []const u8, kind: NodeKind) ?id {
        return self.findUniqueByNameOfKind(name, kind);
    }

    pub fn usersOf(self: *const SemanticGraph, target: id, buf: *std.ArrayListUnmanaged(id)) !void {
        for (self.edges.items) |e| {
            if (e.to == target and e.kind == .use) {
                try buf.append(self.alloc, e.from);
            }
        }
    }

    pub fn defsOf(self: *const SemanticGraph, name: []const u8) ?id {
        return self.findByName(name);
    }

    /// Register a shape algebra transform (`shape.lift`, `shape.seal`, …) on the graph.
    fn addShapeTransformApp(
        self: *SemanticGraph,
        parent: id,
        op: semantic_algebra.ShapeOp,
        input_knowledge: semantic_algebra.KnowledgeLevel,
        span: SpanRef,
        output_shape: id,
        input_hash: u64,
        output_hash: u64,
    ) !id {
        const transform_name = semantic_algebra.shapeTransformId(op);
        std.debug.assert(transform_engine.isShapeTransform(transform_name));
        const node_id = try self.addChild(parent, .{
            .kind = .transform_app,
            .span = span,
            .name = transform_name,
            .knowledge = semantic_algebra.ShapeOp.resultingKnowledge(op, input_knowledge),
            .stage = .transform,
        });
        try self.addEdge(.{ .from = node_id, .to = output_shape, .kind = .transform_output });
        transform_engine.logProvenance(
            self.alloc,
            transform_name,
            .top_level_assign,
            input_hash,
            output_hash,
        );
        return node_id;
    }

    fn followupShapeOps(sc: types.StorageClass, is_sealed: bool) []const semantic_algebra.ShapeOp {
        if (is_sealed or sc == .sealed) return &.{.seal};
        if (sc == .native) return &.{.specialize};
        return &.{};
    }

    fn attachTableShapeTransforms(
        self: *SemanticGraph,
        parent: id,
        span: SpanRef,
        rt: types.ResolvedType,
        sc: types.StorageClass,
        shape_id: ?u64,
        shape_node: id,
    ) !void {
        const sid = shape_id orelse 0;
        const shape_knowledge = semantic_algebra.KnowledgeLevel.fromStorageClass(sc);
        _ = try self.addShapeTransformApp(
            parent,
            .lift,
            .observed,
            span,
            shape_node,
            0,
            sid,
        );
        const is_sealed = rt == .table_type and rt.table_type.is_sealed;
        for (followupShapeOps(sc, is_sealed)) |op| {
            _ = try self.addShapeTransformApp(
                parent,
                op,
                shape_knowledge,
                span,
                shape_node,
                sid,
                sid,
            );
        }
    }

    /// Lift module-level function names from AST (Phase 1 minimal — no sema yet).
    pub fn liftModule(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.addNode(.{
            .kind = .module,
            .span = .{ .file = file, .start = 0, .end = 0 },
            .name = file,
        });
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const func_id = try self.addChild(mod_id, .{
                .kind = .func,
                .span = .{
                    .file = file,
                    .start = fd.loc.line,
                    .end = fd.loc.col,
                },
                .name = fd.path[0],
                .result_descriptor = try types.resolve(fd.func.ret_type, null, self.alloc),
                .ast_ref = @ptrCast(fd),
            });
            for (fd.func.params) |param| {
                _ = try self.addChild(func_id, .{
                    .kind = .param,
                    .span = .{ .file = file, .start = 0, .end = 0 },
                    .name = param.name,
                });
            }
        }
        return mod_id;
    }

    /// Lift alias record shapes from AST (Phase 1 — storage class inferred from fields).
    pub fn liftAliasShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .alias_def) continue;
            const ad = &stmt.alias_def;
            if (ad.type_params != null) continue;
            const field_count: u16 = blk: {
                if (ad.fields.len > 0) break :blk @intCast(ad.fields.len);
                if (ad.target) |tgt| {
                    if (tgt == .record) break :blk @intCast(tgt.record.fields.len);
                }
                break :blk 0;
            };
            var rt: types.ResolvedType = .any;
            if (ad.target) |tgt| {
                rt = try types.resolve(tgt, null, self.alloc);
            } else if (ad.fields.len > 0) {
                var fields = try self.alloc.alloc(types.FieldType, ad.fields.len);
                for (ad.fields, 0..) |field, i| {
                    fields[i] = .{
                        .name = field.name,
                        .typ = try types.resolve(field.typ, null, self.alloc),
                    };
                }
                rt = .{ .table_type = .{ .fields = fields } };
                rt.table_type.storage_class = types.inferStorageClass(fields, false, .dynamic);
            }
            types.applyTableShapeAttrs(&rt, ad.attributes);
            const sc = types.tableStorageClass(rt) orelse .dynamic;
            const why = try self.alloc.dupe(u8, types.explainStorageClass(rt));
            const shape_id = types.tableShapeIdentityHash(rt);
            const alias_span = SpanRef{
                .file = file,
                .start = ad.loc.line,
                .end = ad.loc.col,
            };
            var expr_builder = semantic_algebra.DescriptorExprBuilder.init(self.alloc);
            defer expr_builder.deinit();
            const target_name: ?[]const u8 = blk: {
                if (ad.target) |tgt| {
                    if (tgt == .named) break :blk tgt.named;
                }
                break :blk null;
            };
            const knowledge = semantic_algebra.KnowledgeLevel.fromStorageClass(sc);
            const desc_expr = try semantic_algebra.buildAliasDescriptorExprWithDerives(
                &expr_builder,
                ad.name,
                ad.parent,
                target_name,
                knowledge,
                ad.attributes,
                self.alloc,
            );
            const d_hash = semantic_algebra.descriptorStructuralHash(desc_expr);
            const state = inferDescriptorState(
                sc,
                if (rt == .table_type) rt.table_type.is_sealed else false,
            );
            const recursion = classifyDescriptorRecursion(ad.name, rt);
            const completion = resolveDescriptorCompletion(recursion, rt);
            var label_buf: [128]u8 = undefined;
            const label = try self.alloc.dupe(
                u8,
                semantic_algebra.formatDescriptorExprShort(desc_expr, &label_buf),
            );
            const shape_id_node = try self.addChild(parent, .{
                .kind = .table_shape,
                .span = alias_span,
                .name = ad.name,
                .storage_class = sc,
                .field_count = field_count,
                .shape_id = shape_id,
                .why = why,
                .knowledge = knowledge,
                .stage = .sema,
                .descriptor_hash = d_hash,
                .descriptor_state = state,
                .recursion = recursion,
                .completion = completion,
                .descriptor_label = label,
                .ast_ref = @ptrCast(ad),
            });
            try self.attachTableShapeTransforms(parent, alias_span, rt, sc, shape_id orelse 0, shape_id_node);
        }
    }

    /// Lift enum descriptor shapes from AST (Phase 2 — unified descriptor spine).
    pub fn liftEnumShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .enum_def) continue;
            const ed = &stmt.enum_def;
            if (ed.type_params != null) continue;
            const rt = types.enumShapeFromAst(ed, self.alloc) catch continue;
            const shape_id = types.enumShapeIdentityHash(rt);
            _ = try self.addChild(parent, .{
                .kind = .enum_shape,
                .span = .{
                    .file = file,
                    .start = ed.loc.line,
                    .end = ed.loc.col,
                },
                .name = ed.name,
                .field_count = @intCast(ed.variants.len),
                .shape_id = shape_id,
                .knowledge = .stable,
                .stage = .sema,
                .ast_ref = @ptrCast(ed),
            });
        }
    }

    fn liftTableShapeFromTypeExpr(
        self: *SemanticGraph,
        file: []const u8,
        func_id: id,
        binding_name: []const u8,
        te: ast.TypeExpr,
        loc: ast.Loc,
        attributes: []const ast.Attribute,
        lname: *const ast.LocalName,
    ) !void {
        var rt: types.ResolvedType = .any;
        var inline_record = false;
        switch (te) {
            .record => {
                inline_record = true;
                rt = types.resolve(te, null, self.alloc) catch return;
            },
            .named => |alias| {
                const local_id = try self.addChild(func_id, .{
                    .kind = .local,
                    .span = .{ .file = file, .start = loc.line, .end = loc.col },
                    .name = binding_name,
                    .ast_ref = @ptrCast(@constCast(lname)),
                });
                if (self.findUniqueByNameOfKind(alias, .table_shape)) |shape_id| {
                    try self.addEdge(.{ .from = local_id, .to = shape_id, .kind = .type_of });
                }
                return;
            },
            else => return,
        }
        if (rt != .table_type) return;
        types.applyTableShapeAttrs(&rt, attributes);
        const sc = types.tableStorageClass(rt) orelse .dynamic;
        const why = try self.alloc.dupe(u8, types.explainStorageClass(rt));
        const sid = types.tableShapeIdentityHash(rt);
        var shape_buf: [144]u8 = undefined;
        const shape_name = std.fmt.bufPrint(&shape_buf, "{s}@shape", .{binding_name}) catch binding_name;
        const owned_shape = try self.alloc.dupe(u8, shape_name);
        const shape_node_id = try self.addChild(func_id, .{
            .kind = .table_shape,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .name = owned_shape,
            .owns_name = true,
            .storage_class = sc,
            .field_count = @intCast(rt.table_type.fields.len),
            .shape_id = sid,
            .why = why,
            .knowledge = semantic_algebra.KnowledgeLevel.fromStorageClass(sc),
            .stage = .sema,
            .ast_ref = if (inline_record) @ptrCast(@constCast(lname)) else null,
        });
        try self.attachTableShapeTransforms(func_id, .{
            .file = file,
            .start = loc.line,
            .end = loc.col,
        }, rt, sc, sid, shape_node_id);
        const local_id = try self.addChild(func_id, .{
            .kind = .local,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .name = binding_name,
            .ast_ref = @ptrCast(@constCast(lname)),
        });
        try self.addEdge(.{ .from = local_id, .to = shape_node_id, .kind = .type_of });
    }

    fn liftBindingsInStmts(
        self: *SemanticGraph,
        file: []const u8,
        func_id: id,
        func_name: []const u8,
        stmts: []ast.Stmt,
    ) !void {
        for (stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.names) |*lname| {
                        try self.liftTableShapeFromTypeExpr(
                            file,
                            func_id,
                            lname.ident,
                            lname.typ,
                            lname.loc,
                            lname.attributes,
                            lname,
                        );
                    }
                },
                .do_block => |*d| try self.liftBindingsInStmts(file, func_id, func_name, d.body.stmts),
                .while_loop => |*w| try self.liftBindingsInStmts(file, func_id, func_name, w.body.stmts),
                .repeat_loop => |*r| try self.liftBindingsInStmts(file, func_id, func_name, r.body.stmts),
                .if_stmt => |*i| {
                    try self.liftBindingsInStmts(file, func_id, func_name, i.then.stmts);
                    for (i.elseifs) |*ei| try self.liftBindingsInStmts(file, func_id, func_name, ei.body.stmts);
                    if (i.else_body) |*eb| try self.liftBindingsInStmts(file, func_id, func_name, eb.stmts);
                },
                .num_for => |*nf| try self.liftBindingsInStmts(file, func_id, func_name, nf.body.stmts),
                .gen_for => |*g| try self.liftBindingsInStmts(file, func_id, func_name, g.body.stmts),
                .func_decl => |*fd| {
                    if (try self.findFuncDecl(fd)) |nested_id| {
                        try self.liftBindingsInStmts(file, nested_id, fd.path[0], fd.func.body.stmts);
                    }
                },
                .try_stmt => |*t| {
                    try self.liftBindingsInStmts(file, func_id, func_name, t.body.stmts);
                    for (t.catches) |*cc| try self.liftBindingsInStmts(file, func_id, func_name, cc.body.stmts);
                },
                .defer_stmt => |*d| try self.liftBindingsInStmts(file, func_id, func_name, d.body.stmts),
                else => {},
            }
        }
    }

    /// Lift typed bindings inside functions (inline records + alias type_of edges).
    pub fn liftFunctionBindings(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const func_id = (try self.findFuncDecl(fd)) orelse return error.MissingSemanticDeclaration;
            try self.liftBindingsInStmts(file, func_id, fd.path[0], fd.func.body.stmts);
        }
    }

    /// Lift module-level symbols, alias table shapes, and enum shapes.
    pub fn liftModuleFull(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModule(mod, file);
        try self.liftAliasShapes(mod, file, mod_id);
        try self.liftEnumShapes(mod, file, mod_id);
        try self.liftFunctionBindings(mod, file);
        return mod_id;
    }

    /// Lift call sites from function bodies (Phase 1 — call-shape specialization).
    /// Walks all function statements and extracts call/method_call expressions,
    /// recording their CallShape for specialization analysis.
    pub fn liftCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    const func_id = (try self.findFuncDecl(fd)) orelse continue;
                    try self.liftCallsFromBlock(&fd.func.body, file, func_id);
                },
                .expr_stmt => |es| {
                    const rc: types.ReturnConsumption = if (es.expr.* == .call or es.expr.* == .method_call)
                        .discard
                    else
                        .discard;
                    try self.liftExprsFromExpr(es.expr, file, parent, rc);
                },
                .call_stmt => |cs| {
                    try self.liftExprsFromExpr(cs.expr, file, parent, .discard);
                },
                .local_decl => |ld| {
                    for (ld.inits) |v| {
                        try self.liftExprsFromExpr(v, file, parent, .single);
                    }
                },
                .assign => |asgn| {
                    const rc = types.returnConsumptionForTargets(asgn.targets.len);
                    for (asgn.values) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                else => {},
            }
        }
        if (mod.body.tail_expr) |tail| {
            const rc: types.ReturnConsumption = switch (tail.*) {
                .call, .method_call => .discard,
                else => .single,
            };
            try self.liftExprsFromExpr(tail, file, parent, rc);
        }
    }

    fn liftCallsFromBlock(self: *SemanticGraph, block: *const ast.Block, file: []const u8, parent: id) !void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .expr_stmt => |es| {
                    const rc: types.ReturnConsumption = if (es.expr.* == .call or es.expr.* == .method_call)
                        .discard
                    else
                        .discard;
                    try self.liftExprsFromExpr(es.expr, file, parent, rc);
                },
                .call_stmt => |cs| {
                    try self.liftExprsFromExpr(cs.expr, file, parent, .discard);
                },
                .local_decl => |ld| {
                    for (ld.inits) |v| {
                        try self.liftExprsFromExpr(v, file, parent, .single);
                    }
                },
                .assign => |asgn| {
                    const rc = types.returnConsumptionForTargets(asgn.targets.len);
                    for (asgn.values) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                .ret => |r| {
                    const rc: types.ReturnConsumption = if (r.vals.len <= 1) .single else .multi;
                    for (r.vals) |v| try self.liftExprsFromExpr(v, file, parent, rc);
                },
                .if_stmt => |is| {
                    try self.liftCallsFromBlock(&is.then, file, parent);
                    for (is.elseifs) |*elif| {
                        try self.liftCallsFromBlock(&elif.body, file, parent);
                    }
                    if (is.else_body) |*eb| {
                        try self.liftCallsFromBlock(eb, file, parent);
                    }
                },
                .while_loop => |wl| {
                    try self.liftCallsFromBlock(&wl.body, file, parent);
                },
                .num_for => |nf| {
                    try self.liftCallsFromBlock(&nf.body, file, parent);
                },
                .gen_for => |gf| {
                    try self.liftCallsFromBlock(&gf.body, file, parent);
                },
                .do_block => |db| {
                    try self.liftCallsFromBlock(&db.body, file, parent);
                },
                .func_decl => |*fd| {
                    try self.liftCallsFromBlock(&fd.func.body, file, parent);
                },
                else => {},
            }
        }
        // Also check tail expression (implicit return in Duo)
        if (block.tail_expr) |tail| {
            try self.liftExprsFromExpr(tail, file, parent, .single);
        }
    }

    fn liftExprsFromExpr(
        self: *SemanticGraph,
        expr: *const Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) !void {
        switch (expr.*) {
            .binop => |b| {
                if (b.op == .pipeline) {
                    const loc = expr.loc();
                    const relation = semantic_algebra.IterationRelation.map;
                    const relation_id = try self.addChild(parent, .{
                        .kind = .relation,
                        .span = .{
                            .file = file,
                            .start = loc.line,
                            .end = loc.col,
                        },
                        .iteration_relation = relation,
                        .hardware_lowerings = semantic_algebra.HardwareSet.singleton(.cpu),
                        .knowledge = .observed,
                        .stage = .sema,
                        .ast_ref = @ptrCast(@constCast(expr)),
                    });
                    const transform_name = semantic_algebra.iterationTransformId(relation);
                    if (transform_engine.isRegisteredTransform(transform_name)) {
                        const transform_id = try self.addChild(parent, .{
                            .kind = .transform_app,
                            .span = .{ .file = file, .start = loc.line, .end = loc.col },
                            .name = transform_name,
                            .knowledge = .observed,
                            .stage = .transform,
                        });
                        try self.addEdge(.{ .from = transform_id, .to = relation_id, .kind = .transform_output });
                    }
                }
                try self.liftExprsFromExpr(b.lhs, file, parent, .single);
                try self.liftExprsFromExpr(b.rhs, file, parent, .single);
            },
            .call => |c| {
                try self.liftCallFromExpr(expr, file, parent, consumption);
                try self.liftExprsFromExpr(c.func, file, parent, .single);
                for (c.args) |arg| try self.liftExprsFromExpr(arg, file, parent, .single);
            },
            .method_call => |mc| {
                try self.liftCallFromExpr(expr, file, parent, consumption);
                try self.liftExprsFromExpr(mc.obj, file, parent, .single);
                for (mc.args) |arg| try self.liftExprsFromExpr(arg, file, parent, .single);
            },
            else => {},
        }
    }

    fn liftCallFromExpr(
        self: *SemanticGraph,
        expr: *const Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) !void {
        const base = types.inferCallShape(expr) orelse return;
        const shape = types.callShapeWithConsumption(base, consumption);
        const call_loc = expr.loc();
        const call_name = shape.callee_name orelse shape.method_name;
        const occurrence = try self.addChild(parent, .{
            .kind = .call,
            .span = .{
                .file = file,
                .start = call_loc.line,
                .end = call_loc.col,
            },
            .name = call_name,
            .call_shape = shape,
            .call_shape_fingerprint = shape.fingerprint(),
            .demand = consumption,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.markApplicationCandidate(occurrence);
    }

    /// Lift module fully including call sites (Phase 1 complete lift).
    pub fn liftModuleWithCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModuleFull(mod, file);
        try self.liftCalls(mod, file, mod_id);
        return mod_id;
    }

    fn addApplicationValue(
        self: *SemanticGraph,
        occurrence: id,
        expr: *const Expr,
        file: []const u8,
        descriptor: types.ResolvedType,
    ) !id {
        const loc = expr.loc();
        return self.addChild(occurrence, .{
            .kind = .value,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .descriptor = descriptor,
            .knowledge = semantic_algebra.knowledgeOfType(descriptor),
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
    }

    /// Publish identities and descriptors that survived semantic checking.
    /// Absence of a checked fact stays unresolved rather than falling back to
    /// name matching.
    pub fn liftModuleWithCheckedCalls(
        self: *SemanticGraph,
        mod: *const ast.Module,
        checked: *const sema.Sema,
        file: []const u8,
    ) !id {
        const module = try self.liftModuleWithCalls(mod, file);

        const candidate_limit = self.application_candidates.bit_length;
        var candidate: usize = 0;
        while (candidate < candidate_limit) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const call_id = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            if (call_id >= self.nodes.items.len) return error.InvalidApplicationFact;
            const raw = self.nodes.items[call_id].ast_ref orelse continue;
            const expr: *const Expr = @ptrCast(@alignCast(raw));
            const fact = checked.applicationFact(expr) orelse continue;
            const relation = (try self.findFuncDecl(fact.target)) orelse
                return error.MissingSemanticDeclaration;
            const caller = self.nodes.items[call_id].scope orelse return error.MissingApplicationCaller;
            const caller_node = self.get(caller) orelse return error.MissingApplicationCaller;
            if (caller_node.kind != .func) return error.MissingApplicationCaller;
            const demand = self.nodes.items[call_id].demand orelse
                return error.MissingApplicationDemand;
            const provenance = self.nodes.items[call_id].span;

            self.nodes.items[call_id].descriptor = fact.result;

            var subject_value: ?id = null;
            if (fact.subject) |subject| {
                const descriptor = checked.exprDescriptor(subject) orelse
                    return error.MissingApplicationDescriptor;
                subject_value = try self.addApplicationValue(call_id, subject, file, descriptor);
            }
            const arguments = try self.alloc.alloc(id, fact.arguments.len);
            defer self.alloc.free(arguments);
            for (fact.arguments, 0..) |argument, i| {
                const descriptor = checked.exprDescriptor(argument) orelse
                    return error.MissingApplicationDescriptor;
                arguments[i] = try self.addApplicationValue(call_id, argument, file, descriptor);
            }
            const result = try self.addApplicationValue(call_id, expr, file, fact.result);
            const results = [_]id{result};
            try self.publishApplication(
                call_id,
                relation,
                subject_value,
                caller,
                fact.result,
                demand,
                provenance,
                arguments,
                &results,
            );
        }
        return module;
    }

    /// Source-text projection for migration diagnostics. It does not answer
    /// which semantic relation an application selected.
    pub fn findCallsBySourceCallee(self: *const SemanticGraph, callee: []const u8, buf: *std.ArrayListUnmanaged(id)) !void {
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            const node = self.get(entity) orelse return error.InvalidApplicationFact;
            if (node.call_shape) |cs| {
                if (cs.callee_name) |n| {
                    if (std.mem.eql(u8, n, callee)) {
                        try buf.append(self.alloc, entity);
                    }
                }
            }
        }
    }

    const DependencyFrame = struct {
        row: usize,
        next: usize,
    };

    fn orderFunctionComponents(
        alloc: std.mem.Allocator,
        functions: []const id,
        unlocks: []const std.ArrayListUnmanaged(usize),
    ) ![]const id {
        const reverse = try alloc.alloc(std.ArrayListUnmanaged(usize), functions.len);
        defer {
            for (reverse) |*list| list.deinit(alloc);
            alloc.free(reverse);
        }
        for (reverse) |*list| list.* = .empty;
        for (unlocks, 0..) |list, row| {
            for (list.items) |dependent| try reverse[dependent].append(alloc, row);
        }

        const visited = try alloc.alloc(bool, functions.len);
        defer alloc.free(visited);
        @memset(visited, false);
        var finish: std.ArrayListUnmanaged(usize) = .empty;
        defer finish.deinit(alloc);
        var frames: std.ArrayListUnmanaged(DependencyFrame) = .empty;
        defer frames.deinit(alloc);

        for (functions, 0..) |_, root| {
            if (visited[root]) continue;
            visited[root] = true;
            try frames.append(alloc, .{ .row = root, .next = 0 });
            while (frames.items.len > 0) {
                const top = frames.items.len - 1;
                const row = frames.items[top].row;
                if (frames.items[top].next < unlocks[row].items.len) {
                    const dependent = unlocks[row].items[frames.items[top].next];
                    frames.items[top].next += 1;
                    if (!visited[dependent]) {
                        visited[dependent] = true;
                        try frames.append(alloc, .{ .row = dependent, .next = 0 });
                    }
                    continue;
                }
                _ = frames.pop().?;
                try finish.append(alloc, row);
            }
        }

        const components = try alloc.alloc(usize, functions.len);
        defer alloc.free(components);
        @memset(components, std.math.maxInt(usize));
        var component_count: usize = 0;
        var stack: std.ArrayListUnmanaged(usize) = .empty;
        defer stack.deinit(alloc);
        var finish_index = finish.items.len;
        while (finish_index > 0) {
            finish_index -= 1;
            const root = finish.items[finish_index];
            if (components[root] != std.math.maxInt(usize)) continue;
            components[root] = component_count;
            try stack.append(alloc, root);
            while (stack.items.len > 0) {
                const row = stack.pop().?;
                for (reverse[row].items) |predecessor| {
                    if (components[predecessor] != std.math.maxInt(usize)) continue;
                    components[predecessor] = component_count;
                    try stack.append(alloc, predecessor);
                }
            }
            component_count += 1;
        }

        const component_counts = try alloc.alloc(usize, component_count);
        defer alloc.free(component_counts);
        @memset(component_counts, 0);
        for (components) |component| component_counts[component] += 1;
        const component_offsets = try alloc.alloc(usize, component_count + 1);
        defer alloc.free(component_offsets);
        component_offsets[0] = 0;
        for (component_counts, 0..) |count, component| {
            component_offsets[component + 1] = component_offsets[component] + count;
        }
        const component_cursors = try alloc.dupe(usize, component_offsets[0..component_count]);
        defer alloc.free(component_cursors);
        const component_rows = try alloc.alloc(usize, functions.len);
        defer alloc.free(component_rows);
        for (components, 0..) |component, row| {
            component_rows[component_cursors[component]] = row;
            component_cursors[component] += 1;
        }

        const component_unlocks = try alloc.alloc(std.ArrayListUnmanaged(usize), component_count);
        defer {
            for (component_unlocks) |*list| list.deinit(alloc);
            alloc.free(component_unlocks);
        }
        for (component_unlocks) |*list| list.* = .empty;
        const component_degree = try alloc.alloc(usize, component_count);
        defer alloc.free(component_degree);
        @memset(component_degree, 0);
        var component_edges: std.AutoHashMapUnmanaged(u128, void) = .empty;
        defer component_edges.deinit(alloc);
        for (unlocks, 0..) |list, row| {
            const from = components[row];
            for (list.items) |dependent| {
                const to = components[dependent];
                if (from == to) continue;
                const edge = (@as(u128, from) << 64) | @as(u128, to);
                const slot = try component_edges.getOrPut(alloc, edge);
                if (slot.found_existing) continue;
                try component_unlocks[from].append(alloc, to);
                component_degree[to] += 1;
            }
        }

        var ready: std.ArrayListUnmanaged(usize) = .empty;
        defer ready.deinit(alloc);
        for (component_degree, 0..) |degree, component| {
            if (degree == 0) try ready.append(alloc, component);
        }
        var component_order: std.ArrayListUnmanaged(usize) = .empty;
        defer component_order.deinit(alloc);
        while (ready.items.len > 0) {
            const component = ready.pop().?;
            try component_order.append(alloc, component);
            for (component_unlocks[component].items) |dependent| {
                component_degree[dependent] -= 1;
                if (component_degree[dependent] == 0) try ready.append(alloc, dependent);
            }
        }
        if (component_order.items.len != component_count) return error.UnresolvedApplication;

        const ordered = try alloc.alloc(id, functions.len);
        errdefer alloc.free(ordered);
        var ordered_len: usize = 0;
        for (component_order.items) |component| {
            for (component_rows[component_offsets[component]..component_offsets[component + 1]]) |row| {
                ordered[ordered_len] = functions[row];
                ordered_len += 1;
            }
        }
        if (ordered_len != functions.len) return error.UnresolvedApplication;
        return ordered;
    }

    /// Emit order for exact module function entities: callees before callers.
    /// An unresolved application inside the requested function set refuses the
    /// projection rather than becoming an absent dependency.
    pub fn moduleFunctionEmitOrder(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        functions: []const id,
    ) ![]const id {
        if (functions.len == 0) return try alloc.dupe(id, functions);

        var rows: std.AutoHashMapUnmanaged(id, usize) = .empty;
        defer rows.deinit(alloc);
        for (functions, 0..) |function, row| {
            const node = self.get(function) orelse return error.InvalidFunctionEntity;
            if (node.kind != .func) return error.InvalidFunctionEntity;
            const slot = try rows.getOrPut(alloc, function);
            if (slot.found_existing) return error.DuplicateFunctionEntity;
            slot.value_ptr.* = row;
        }

        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const application_id = std.math.cast(id, candidate) orelse
                return error.UnresolvedApplication;
            const application_node = self.get(application_id) orelse
                return error.UnresolvedApplication;
            const caller = application_node.scope orelse return error.UnresolvedApplication;
            if (!rows.contains(caller)) continue;
            if (self.application(application_id) == null) {
                if (self.isBootstrapApplicationNode(application_id)) continue;
                return error.UnresolvedApplication;
            }
        }

        const in_degree = try alloc.alloc(usize, functions.len);
        defer alloc.free(in_degree);
        @memset(in_degree, 0);
        const unlocks = try alloc.alloc(std.ArrayListUnmanaged(usize), functions.len);
        defer {
            for (unlocks) |*list| list.deinit(alloc);
            alloc.free(unlocks);
        }
        for (unlocks) |*list| list.* = .empty;
        var dependencies: std.AutoHashMapUnmanaged(u128, void) = .empty;
        defer dependencies.deinit(alloc);

        for (self.applications()) |stored| {
            const fact = self.application(stored.application) orelse return error.UnresolvedApplication;
            const caller = rows.get(fact.caller) orelse continue;
            const relation_node = self.get(fact.relation) orelse return error.UnresolvedApplication;
            if (relation_node.kind != .func) continue;
            const relation = rows.get(fact.relation) orelse continue;
            const dependency = (@as(u128, relation) << 64) | @as(u128, caller);
            const slot = try dependencies.getOrPut(alloc, dependency);
            if (slot.found_existing) continue;
            try unlocks[relation].append(alloc, caller);
            in_degree[caller] += 1;
        }
        if (dependencies.count() == 0) return try alloc.dupe(id, functions);

        var ready: std.ArrayListUnmanaged(usize) = .empty;
        defer ready.deinit(alloc);
        for (in_degree, 0..) |degree, row| {
            if (degree == 0) try ready.append(alloc, row);
        }

        var ordered: std.ArrayListUnmanaged(id) = .empty;
        errdefer ordered.deinit(alloc);

        while (ready.items.len > 0) {
            const row = ready.pop().?;
            try ordered.append(alloc, functions[row]);
            for (unlocks[row].items) |dependent| {
                in_degree[dependent] -= 1;
                if (in_degree[dependent] == 0) try ready.append(alloc, dependent);
            }
        }

        if (ordered.items.len != functions.len) {
            ordered.clearAndFree(alloc);
            return try orderFunctionComponents(alloc, functions, unlocks);
        }

        return try ordered.toOwnedSlice(alloc);
    }

    /// Source-text method projection for migration diagnostics only.
    pub fn findCallsBySourceMethod(self: *const SemanticGraph, method: []const u8, buf: *std.ArrayListUnmanaged(id)) !void {
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            const node = self.get(entity) orelse return error.InvalidApplicationFact;
            if (node.call_shape) |cs| {
                if (cs.method_name) |m| {
                    if (std.mem.eql(u8, m, method)) {
                        try buf.append(self.alloc, entity);
                    }
                }
            }
        }
    }

    /// Get the CallShape for a specific call node.
    pub fn callShapeOf(self: *const SemanticGraph, entity: id) ?types.CallShape {
        if (!self.isApplicationCandidate(entity)) return null;
        const node = self.get(entity) orelse return null;
        return node.call_shape;
    }

    /// Count nodes of a given kind (diagnostics / MCP queries).
    pub fn countKind(self: *const SemanticGraph, kind: NodeKind) usize {
        var n: usize = 0;
        for (self.nodes.items) |node| {
            if (node.kind == kind) n += 1;
        }
        return n;
    }

    pub fn findTableShape(self: *const SemanticGraph, name: []const u8) ?*const Node {
        const entity = self.findUniqueByNameOfKind(name, .table_shape) orelse return null;
        return self.get(entity);
    }

    pub fn findEnumShape(self: *const SemanticGraph, name: []const u8) ?*const Node {
        const entity = self.findUniqueByNameOfKind(name, .enum_shape) orelse return null;
        return self.get(entity);
    }

    pub fn nodeKindLabel(kind: NodeKind) []const u8 {
        return switch (kind) {
            .module => "module",
            .source_file => "source_file",
            .func => "func",
            .param => "param",
            .local => "local",
            .value => "value",
            .type_node => "type_node",
            .call => "call",
            .relation => "relation",
            .concept => "concept",
            .transform_app => "transform_app",
            .comptime_value => "comptime_value",
            .emit_artifact => "emit_artifact",
            .table_shape => "table_shape",
            .enum_shape => "enum_shape",
        };
    }

    pub fn edgeKindLabel(kind: EdgeKind) []const u8 {
        return switch (kind) {
            .contains => "contains",
            .def => "def",
            .use => "use",
            .relation => "relation",
            .subject => "subject",
            .argument => "argument",
            .result => "result",
            .type_of => "type",
            .transform_input => "input",
            .transform_output => "output",
            .provenance => "provenance",
        };
    }

    fn jsonEscapeAppend(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, s: []const u8) !void {
        for (s) |c| switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\x08' => try buf.appendSlice(alloc, "\\b"),
            '\x0c' => try buf.appendSlice(alloc, "\\f"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            else => {
                if (c < 0x20) {
                    const hex = "0123456789abcdef";
                    try buf.appendSlice(alloc, "\\u00");
                    try buf.append(alloc, hex[c >> 4]);
                    try buf.append(alloc, hex[c & 0x0f]);
                } else {
                    try buf.append(alloc, c);
                }
            },
        };
    }

    fn appendJsonInt(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: anytype) !void {
        var tmp: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
        try buf.appendSlice(alloc, s);
    }

    fn appendIdsJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        values: []const id,
    ) !void {
        try buf.append(alloc, '[');
        for (values, 0..) |value, i| {
            if (i > 0) try buf.append(alloc, ',');
            try appendJsonInt(buf, alloc, value);
        }
        try buf.append(alloc, ']');
    }

    fn appendDemandJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        demand: types.ReturnConsumption,
    ) !void {
        try buf.append(alloc, '"');
        try buf.appendSlice(alloc, switch (demand) {
            .unknown => "unknown",
            .discard => "discard",
            .single => "single",
            .multi => "multi",
        });
        try buf.append(alloc, '"');
    }

    fn appendEnumVariantsJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        node: *const Node,
    ) !void {
        try buf.append(alloc, '[');
        if (node.ast_ref) |raw| {
            const ed: *const ast.EnumDef = @ptrCast(@alignCast(raw));
            for (ed.variants, 0..) |variant, i| {
                if (i > 0) try buf.append(alloc, ',');
                try buf.append(alloc, '"');
                try jsonEscapeAppend(buf, alloc, variant.name);
                try buf.append(alloc, '"');
            }
        }
        try buf.append(alloc, ']');
    }

    pub fn atModuleScope(self: *const SemanticGraph, node: *const Node) bool {
        const parent = self.get(node.scope orelse return false) orelse return false;
        return parent.kind == .module;
    }

    fn shapeScopeLabel(self: *const SemanticGraph, node: *const Node) ![]const u8 {
        const parent = self.get(node.scope orelse return error.InvalidTableShapeScope) orelse
            return error.InvalidTableShapeScope;
        return switch (parent.kind) {
            .module => "module",
            .func => "inline",
            else => error.InvalidTableShapeScope,
        };
    }

    fn resolveTableShapeType(
        self: *const SemanticGraph,
        node: *const Node,
        graph_alloc: std.mem.Allocator,
    ) !?types.ResolvedType {
        if (node.ast_ref) |raw| {
            const parent = self.get(node.scope orelse return null) orelse return null;
            switch (parent.kind) {
                .func => {
                    const ln: *const ast.LocalName = @ptrCast(@alignCast(raw));
                    var rt = try types.resolve(ln.typ, null, graph_alloc);
                    types.applyTableShapeAttrs(&rt, ln.attributes);
                    return rt;
                },
                .module => {
                    const ad: *const ast.AliasDef = @ptrCast(@alignCast(raw));
                    var rt: types.ResolvedType = .any;
                    if (ad.target) |tgt| {
                        rt = try types.resolve(tgt, null, graph_alloc);
                    } else if (ad.fields.len > 0) {
                        var fields = try graph_alloc.alloc(types.FieldType, ad.fields.len);
                        for (ad.fields, 0..) |field, i| {
                            fields[i] = .{
                                .name = field.name,
                                .typ = try types.resolve(field.typ, null, graph_alloc),
                            };
                        }
                        rt = .{ .table_type = .{ .fields = fields } };
                    }
                    types.applyTableShapeAttrs(&rt, ad.attributes);
                    return rt;
                },
                else => return null,
            }
        }
        return null;
    }

    fn appendTableFieldsJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        out_alloc: std.mem.Allocator,
        graph_alloc: std.mem.Allocator,
        node: *const Node,
    ) !void {
        try buf.append(out_alloc, '[');
        if (try self.resolveTableShapeType(node, graph_alloc)) |rt| {
            if (rt == .table_type) {
                for (rt.table_type.fields, 0..) |f, i| {
                    if (i > 0) try buf.append(out_alloc, ',');
                    var tb: [64]u8 = undefined;
                    const tn = f.typ.c_type(&tb);
                    try buf.appendSlice(out_alloc, "{\"name\":\"");
                    try jsonEscapeAppend(buf, out_alloc, f.name);
                    try buf.appendSlice(out_alloc, "\",\"type\":\"");
                    try jsonEscapeAppend(buf, out_alloc, tn);
                    try buf.appendSlice(out_alloc, "\"}");
                }
            }
        }
        try buf.append(out_alloc, ']');
    }

    /// Write agent-facing JSON snapshot (table_shapes + enum_shapes + full node list).
    pub fn writeJson(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        file: []const u8,
        out: *std.ArrayListUnmanaged(u8),
        source_hash: ?u64,
    ) !void {
        try out.appendSlice(alloc, "{\"schema\":\"sim-v0\",\"version\":2,\"file\":\"");
        try jsonEscapeAppend(out, alloc, file);
        try out.append(alloc, '"');
        if (source_hash) |h| {
            try out.appendSlice(alloc, ",\"source_hash\":");
            try appendJsonInt(out, alloc, h);
        }
        try out.appendSlice(alloc, ",\"nodes\":[");
        for (self.nodes.items, 0..) |node, i| {
            const entity = std.math.cast(id, i) orelse
                return error.ApplicationFactCapacityExceeded;
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, i);
            try out.appendSlice(alloc, ",\"kind\":\"");
            try out.appendSlice(alloc, nodeKindLabel(node.kind));
            try out.appendSlice(alloc, "\"");
            if (node.name) |n| {
                try out.appendSlice(alloc, ",\"name\":\"");
                try jsonEscapeAppend(out, alloc, n);
                try out.append(alloc, '"');
            }
            if (node.kind == .table_shape) {
                const sc = if (node.storage_class) |s| types.storageClassName(s) else "dynamic";
                try out.appendSlice(alloc, ",\"storage_class\":\"");
                try out.appendSlice(alloc, sc);
                try out.appendSlice(alloc, "\",\"scope\":\"");
                try out.appendSlice(alloc, try self.shapeScopeLabel(&node));
                try out.appendSlice(alloc, "\",\"field_count\":");
                try appendJsonInt(out, alloc, node.field_count);
                if (node.shape_id) |sid| {
                    try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                    try appendJsonInt(out, alloc, sid);
                }
                if (node.why) |w| {
                    try out.appendSlice(alloc, ",\"why\":\"");
                    try jsonEscapeAppend(out, alloc, w);
                    try out.append(alloc, '"');
                }
                if (node.descriptor_hash) |dh| {
                    try out.appendSlice(alloc, ",\"descriptor_hash\":");
                    try appendJsonInt(out, alloc, dh);
                }
                if (node.descriptor_state) |ds| {
                    try out.appendSlice(alloc, ",\"descriptor_state\":\"");
                    try out.appendSlice(alloc, State.name(ds));
                    try out.append(alloc, '"');
                }
                if (node.recursion) |rc| {
                    try out.appendSlice(alloc, ",\"recursion\":\"");
                    try out.appendSlice(alloc, Recursion.name(rc));
                    try out.append(alloc, '"');
                }
                if (node.completion) |cp| {
                    try out.appendSlice(alloc, ",\"completion\":\"");
                    try out.appendSlice(alloc, Completion.name(cp));
                    try out.append(alloc, '"');
                }
                if (node.descriptor_label) |dl| {
                    try out.appendSlice(alloc, ",\"descriptor\":\"");
                    try jsonEscapeAppend(out, alloc, dl);
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, ",\"fields\":");
                try self.appendTableFieldsJson(out, alloc, self.alloc, &node);
            }
            if (self.isApplicationCandidate(entity)) {
                if (node.call_shape) |cs| {
                    try out.appendSlice(alloc, ",\"callee_kind\":\"");
                    try out.appendSlice(alloc, switch (cs.callee_kind) {
                        .direct => "direct",
                        .method => "method",
                        .indirect => "indirect",
                        .comptime_known => "comptime",
                    });
                    try out.appendSlice(alloc, "\",\"arg_count\":");
                    try appendJsonInt(out, alloc, cs.arg_count);
                    if (cs.method_name) |m| {
                        try out.appendSlice(alloc, ",\"method\":\"");
                        try jsonEscapeAppend(out, alloc, m);
                        try out.append(alloc, '"');
                    }
                    try out.appendSlice(alloc, ",\"specializable\":");
                    try out.appendSlice(alloc, if (cs.isSpecializable()) "true" else "false");
                }
                if (node.call_shape_fingerprint) |fingerprint| {
                    try out.appendSlice(alloc, ",\"call_shape_fingerprint\":");
                    try appendJsonInt(out, alloc, fingerprint);
                }
                if (node.knowledge) |k| {
                    try out.appendSlice(alloc, ",\"knowledge\":\"");
                    try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                    try out.append(alloc, '"');
                }
                if (node.stage) |s| {
                    try out.appendSlice(alloc, ",\"stage\":\"");
                    try out.appendSlice(alloc, semantic_algebra.Stage.name(s));
                    try out.append(alloc, '"');
                }
            }
            if (node.kind == .transform_app) {
                if (node.name) |n| {
                    try out.appendSlice(alloc, ",\"transform\":\"");
                    try jsonEscapeAppend(out, alloc, n);
                    try out.append(alloc, '"');
                }
                if (node.knowledge) |k| {
                    try out.appendSlice(alloc, ",\"knowledge\":\"");
                    try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                    try out.append(alloc, '"');
                }
                if (node.stage) |s| {
                    try out.appendSlice(alloc, ",\"stage\":\"");
                    try out.appendSlice(alloc, semantic_algebra.Stage.name(s));
                    try out.append(alloc, '"');
                }
            }
            if (node.kind == .enum_shape) {
                try out.appendSlice(alloc, ",\"variant_count\":");
                try appendJsonInt(out, alloc, node.field_count);
                if (node.shape_id) |sid| {
                    try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                    try appendJsonInt(out, alloc, sid);
                }
                try out.appendSlice(alloc, ",\"variants\":");
                try appendEnumVariantsJson(out, alloc, &node);
            }
            if (node.kind == .relation) {
                if (node.iteration_relation) |relation| {
                    try out.appendSlice(alloc, ",\"relation\":\"");
                    try out.appendSlice(alloc, relation.name());
                    try out.append(alloc, '"');
                }
                if (node.hardware_lowerings.bits != 0) {
                    try out.appendSlice(alloc, ",\"hardware_lowerings\":");
                    try appendJsonInt(out, alloc, node.hardware_lowerings.bits);
                }
            }
            if (node.descriptor) |descriptor| {
                var namebuf: [96]u8 = undefined;
                try out.appendSlice(alloc, ",\"descriptor\":\"");
                try jsonEscapeAppend(out, alloc, descriptor.duo_name(&namebuf));
                try out.append(alloc, '"');
            }
            if (node.demand) |demand| {
                try out.appendSlice(alloc, ",\"demand\":\"");
                try out.appendSlice(alloc, switch (demand) {
                    .unknown => "unknown",
                    .discard => "discard",
                    .single => "single",
                    .multi => "multi",
                });
                try out.append(alloc, '"');
            }
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"edges\":[");
        for (self.edges.items, 0..) |edge, i| {
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"from\":");
            try appendJsonInt(out, alloc, edge.from);
            try out.appendSlice(alloc, ",\"to\":");
            try appendJsonInt(out, alloc, edge.to);
            try out.appendSlice(alloc, ",\"relation\":\"");
            try out.appendSlice(alloc, edgeKindLabel(edge.kind));
            try out.append(alloc, '"');
            if (edge.kind == .argument) {
                try out.appendSlice(alloc, ",\"position\":");
                try appendJsonInt(out, alloc, edge.position);
            }
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"applications\":[");
        for (self.applications(), 0..) |stored, i| {
            const fact = self.application(stored.application) orelse return error.InvalidApplicationFact;
            const arguments = self.applicationArguments(fact.application) orelse
                return error.InvalidApplicationFact;
            const results = self.applicationResults(fact.application) orelse
                return error.InvalidApplicationFact;
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"application\":");
            try appendJsonInt(out, alloc, fact.application);
            try out.appendSlice(alloc, ",\"relation\":");
            try appendJsonInt(out, alloc, fact.relation);
            try out.appendSlice(alloc, ",\"caller\":");
            try appendJsonInt(out, alloc, fact.caller);
            if (fact.subject) |subject| {
                try out.appendSlice(alloc, ",\"subject\":");
                try appendJsonInt(out, alloc, subject);
            }
            try out.appendSlice(alloc, ",\"arguments\":");
            try appendIdsJson(out, alloc, arguments);
            try out.appendSlice(alloc, ",\"results\":");
            try appendIdsJson(out, alloc, results);
            var descriptor_buf: [96]u8 = undefined;
            try out.appendSlice(alloc, ",\"descriptor\":\"");
            try jsonEscapeAppend(out, alloc, fact.descriptor.duo_name(&descriptor_buf));
            try out.appendSlice(alloc, "\",\"demand\":");
            try appendDemandJson(out, alloc, fact.demand);
            try out.appendSlice(alloc, ",\"provenance\":{\"file\":\"");
            try jsonEscapeAppend(out, alloc, fact.provenance.file);
            try out.appendSlice(alloc, "\",\"start\":");
            try appendJsonInt(out, alloc, fact.provenance.start);
            try out.appendSlice(alloc, ",\"end\":");
            try appendJsonInt(out, alloc, fact.provenance.end);
            try out.appendSlice(alloc, "}}");
        }
        try out.appendSlice(alloc, "],\"unresolved_applications\":[");
        var first_unresolved = true;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            if (candidate < self.application_presence.bit_length and
                self.application_presence.isSet(candidate)) continue;
            if (self.get(@intCast(candidate)) == null) return error.InvalidApplicationFact;
            if (!first_unresolved) try out.append(alloc, ',');
            first_unresolved = false;
            try appendJsonInt(out, alloc, candidate);
        }
        try out.appendSlice(alloc, "],\"table_shapes\":[");
        var first_table = true;
        for (self.nodes.items, 0..) |node, node_index| {
            if (node.kind != .table_shape) continue;
            if (!first_table) try out.append(alloc, ',');
            first_table = false;
            const sc = if (node.storage_class) |s| types.storageClassName(s) else "dynamic";
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, node_index);
            try out.appendSlice(alloc, ",\"name\":\"");
            try jsonEscapeAppend(out, alloc, node.name orelse "?");
            try out.appendSlice(alloc, "\",\"storage_class\":\"");
            try out.appendSlice(alloc, sc);
            try out.appendSlice(alloc, "\",\"scope\":\"");
            try out.appendSlice(alloc, try self.shapeScopeLabel(&node));
            try out.appendSlice(alloc, "\",\"field_count\":");
            try appendJsonInt(out, alloc, node.field_count);
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                try appendJsonInt(out, alloc, sid);
            }
            if (node.why) |w| {
                try out.appendSlice(alloc, ",\"why\":\"");
                try jsonEscapeAppend(out, alloc, w);
                try out.append(alloc, '"');
            }
            if (node.knowledge) |k| {
                try out.appendSlice(alloc, ",\"knowledge\":\"");
                try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                try out.append(alloc, '"');
            }
            if (node.descriptor_hash) |dh| {
                try out.appendSlice(alloc, ",\"descriptor_hash\":");
                try appendJsonInt(out, alloc, dh);
            }
            if (node.descriptor_label) |dl| {
                try out.appendSlice(alloc, ",\"descriptor\":\"");
                try jsonEscapeAppend(out, alloc, dl);
                try out.append(alloc, '"');
            }
            try out.appendSlice(alloc, ",\"fields\":");
            try self.appendTableFieldsJson(out, alloc, self.alloc, &node);
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"enum_shapes\":[");
        var first_enum = true;
        for (self.nodes.items, 0..) |node, node_index| {
            if (node.kind != .enum_shape) continue;
            if (!first_enum) try out.append(alloc, ',');
            first_enum = false;
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, node_index);
            try out.appendSlice(alloc, ",\"name\":\"");
            try jsonEscapeAppend(out, alloc, node.name orelse "?");
            try out.appendSlice(alloc, "\",\"variant_count\":");
            try appendJsonInt(out, alloc, node.field_count);
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                try appendJsonInt(out, alloc, sid);
            }
            try out.appendSlice(alloc, ",\"variants\":");
            try appendEnumVariantsJson(out, alloc, &node);
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"call_shapes\":[");
        var first_call = true;
        var shapes = self.application_candidates.iterator(.{});
        while (shapes.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            const node = self.get(entity) orelse return error.InvalidApplicationFact;
            if (!first_call) try out.append(alloc, ',');
            first_call = false;
            try out.appendSlice(alloc, "{\"node\":");
            try appendJsonInt(out, alloc, entity);
            try out.appendSlice(alloc, ",\"name\":\"");
            try jsonEscapeAppend(out, alloc, node.name orelse "?");
            try out.append(alloc, '"');
            if (node.call_shape) |cs| {
                try out.appendSlice(alloc, ",\"callee_kind\":\"");
                try out.appendSlice(alloc, switch (cs.callee_kind) {
                    .direct => "direct",
                    .method => "method",
                    .indirect => "indirect",
                    .comptime_known => "comptime",
                });
                try out.appendSlice(alloc, "\",\"arg_count\":");
                try appendJsonInt(out, alloc, cs.arg_count);
                if (cs.method_name) |m| {
                    try out.appendSlice(alloc, ",\"method\":\"");
                    try jsonEscapeAppend(out, alloc, m);
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, ",\"specializable\":");
                try out.appendSlice(alloc, if (cs.isSpecializable()) "true" else "false");
            }
            if (node.call_shape_fingerprint) |fingerprint| {
                try out.appendSlice(alloc, ",\"call_shape_fingerprint\":");
                try appendJsonInt(out, alloc, fingerprint);
            }
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "]}");
    }

    /// Relative sidecar path: `.duo/graph/<stem>.json`.
    pub fn sidecarRelPath(src_path: []const u8, buf: []u8) []const u8 {
        const base = std.fs.path.basename(src_path);
        const ext = std.fs.path.extension(base);
        const stem = if (ext.len > 0 and ext.len <= base.len) base[0 .. base.len - ext.len] else base;
        return std.fmt.bufPrint(buf, ".duo/graph/{s}.json", .{stem}) catch ".duo/graph/module.json";
    }

    /// Persist graph JSON sidecar invalidated by source hash (Phase 1 A1).
    pub fn writeSidecar(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        io: std.Io,
        src_path: []const u8,
        source_hash: u64,
    ) !void {
        var json: std.ArrayListUnmanaged(u8) = .empty;
        defer json.deinit(alloc);
        try self.writeJson(alloc, src_path, &json, source_hash);
        var path_buf: [512]u8 = undefined;
        const rel = sidecarRelPath(src_path, &path_buf);
        if (std.fs.path.dirname(rel)) |dir| {
            if (!std.mem.eql(u8, dir, ".")) {
                const cwd = std.Io.Dir.cwd();
                try cwd.createDirPath(io, dir);
            }
        }
        const cwd = std.Io.Dir.cwd();
        try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = rel, .data = json.items });
    }

    /// Print a one-line graph summary to stderr when `DUO_GRAPH=1`.
    pub fn dumpSummary(self: *const SemanticGraph, io: std.Io, stderr: std.Io.File, file: []const u8) void {
        var buf: [512]u8 = undefined;
        var fw: std.Io.File.Writer = .init(stderr, io, &buf);
        fw.interface.print(
            "[duo graph] {s}: {d} nodes ({d} func, {d} table_shape, {d} enum_shape, {d} call)\n",
            .{
                file,
                self.nodes.items.len,
                self.countKind(.func),
                self.countKind(.table_shape),
                self.countKind(.enum_shape),
                self.application_candidates.count(),
            },
        ) catch return;
        for (self.nodes.items) |node| {
            if (node.kind != .table_shape) continue;
            const sc = if (node.storage_class) |s| types.storageClassName(s) else "dynamic";
            fw.interface.print(
                "  shape {s}: {s} ({d} fields)",
                .{ node.name orelse "?", sc, node.field_count },
            ) catch return;
            if (node.why) |w| {
                fw.interface.print(" — {s}\n", .{w}) catch return;
            } else {
                fw.interface.print("\n", .{}) catch return;
            }
        }
        fw.interface.flush() catch {};
    }
};

fn addChildAllocationProbe(alloc: std.mem.Allocator) !void {
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const parent = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "allocation.id", .start = 0, .end = 0 },
    });
    const name = try alloc.dupe(u8, "child");
    const child = graph.addChild(parent, .{
        .kind = .value,
        .span = .{ .file = "allocation.id", .start = 1, .end = 1 },
        .name = name,
        .owns_name = true,
    }) catch |err| {
        try std.testing.expectEqual(@as(usize, 1), graph.nodes.items.len);
        try std.testing.expectEqual(@as(usize, 0), graph.edges.items.len);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 2), graph.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 1), graph.edges.items.len);
    try std.testing.expectEqual(parent, graph.edges.items[0].from);
    try std.testing.expectEqual(child, graph.edges.items[0].to);
}

fn orderFunctionComponentsAllocationProbe(alloc: std.mem.Allocator) !void {
    var unlocks = [_]std.ArrayListUnmanaged(usize){ .empty, .empty, .empty };
    defer for (&unlocks) |*list| list.deinit(alloc);
    try unlocks[0].append(alloc, 1);
    try unlocks[0].append(alloc, 2);
    try unlocks[1].append(alloc, 0);
    const functions = [_]id{ 10, 11, 12 };
    const ordered = try SemanticGraph.orderFunctionComponents(alloc, &functions, &unlocks);
    defer alloc.free(ordered);
    try std.testing.expectEqualSlices(id, &functions, ordered);
}

fn moduleFunctionEmitOrderAllocationProbe(
    alloc: std.mem.Allocator,
    graph: *const SemanticGraph,
    functions: []const id,
    expected: []const id,
) !void {
    const ordered = try graph.moduleFunctionEmitOrder(alloc, functions);
    defer alloc.free(ordered);
    try std.testing.expectEqualSlices(id, expected, ordered);
}

test "semantic_graph: child and scope relation publish transactionally" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        addChildAllocationProbe,
        .{},
    );
}

test "semantic_graph: liftModule creates func and param nodes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\function add(a, b)
        \\  return a + b
        \\end
    , "test.lua");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.liftModule(&module, "test.lua");
    try std.testing.expect(g.get(mod_id) != null);
    try std.testing.expectEqual(@as(usize, 4), g.nodes.items.len); // module + func + 2 params
    const add_id = g.findByName("add") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(.func, g.get(add_id).?.kind);
}

test "semantic_graph: function identities carry resolved result descriptors" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\measure(): f64
        \\    1.5
        \\label(): str
        \\    "ok"
        \\ready(): bool
        \\    true
    ;
    var lex = Lexer.init(src, "results.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModule(&module, "results.duo");

    try std.testing.expectEqual(types.ResolvedType.f64, g.funcResultDescriptor("measure").?);
    try std.testing.expectEqual(types.ResolvedType.str, g.funcResultDescriptor("label").?);
    try std.testing.expectEqual(types.ResolvedType.bool, g.funcResultDescriptor("ready").?);
    try std.testing.expect(g.funcResultDescriptor("missing") == null);
}

test "semantic_graph: checked subject application retains relation and value identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\document: {
        \\    value: i64
        \\}
        \\read: i64 = (subject: document)
        \\    subject.value
        \\main: i64 = ()
        \\    document{ value = 42 }:read()
    ;
    var lex = Lexer.init(src, "application.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "application.id");

    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const fact = graph.applications()[0];
    const stored = graph.application(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("read", graph.get(stored.relation).?.name.?);
    try std.testing.expectEqual(types.ResolvedType.i64, stored.descriptor);
    try std.testing.expectEqual(types.ReturnConsumption.single, stored.demand);
    try std.testing.expectEqual(@as(usize, 0), graph.applicationArguments(fact.application).?.len);
    const results = graph.applicationResults(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(results[0], graph.applicationResult(fact.application).?);
    const subject = graph.get(stored.subject orelse return error.TestExpectedEqual) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(subject.kind == .value);
    try std.testing.expect(subject.descriptor.? == .@"struct");
    try std.testing.expectEqualStrings("document", subject.descriptor.?.@"struct".name);
    try std.testing.expectEqual(types.ResolvedType.i64, graph.get(results[0]).?.descriptor.?);
    try std.testing.expectEqual(@as(u32, 7), stored.provenance.start);

    const unresolved_before = graph.unresolvedApplicationCount(null);
    const row = graph.application_rows.items[fact.application];
    graph.application_rows.items[fact.application] = std.math.maxInt(u32);
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.application_rows.items[fact.application] = row;

    graph.nodes.items[fact.application].demand = .discard;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[fact.application].demand = stored.demand;

    const subject_id = stored.subject orelse return error.TestExpectedEqual;
    graph.nodes.items[subject_id].kind = .local;
    graph.nodes.items[subject_id].scope = null;
    graph.nodes.items[results[0]].kind = .local;
    graph.nodes.items[results[0]].scope = null;
    try std.testing.expect(graph.application(fact.application) != null);
    try std.testing.expectEqual(unresolved_before, graph.unresolvedApplicationCount(null));

    const subject_descriptor = graph.nodes.items[subject_id].descriptor.?;
    graph.nodes.items[subject_id].descriptor = null;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[subject_id].descriptor = subject_descriptor;

    const result_descriptor = graph.nodes.items[results[0]].descriptor.?;
    graph.nodes.items[results[0]].descriptor = .i32;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[results[0]].descriptor = result_descriptor;

    const result_range = graph.application_facts.items[row].results;
    graph.application_facts.items[row].results.start = std.math.maxInt(u32);
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.application_facts.items[row].results = result_range;

    // Transitional kinds and containment do not own application meaning. The
    // candidate column and packed roles retain the exact semantic identities.
    graph.nodes.items[fact.application].kind = .value;
    try std.testing.expect(graph.application(fact.application) != null);
    try std.testing.expect(graph.callShapeOf(fact.application) != null);
    var method_calls: std.ArrayListUnmanaged(id) = .empty;
    defer method_calls.deinit(alloc);
    try graph.findCallsBySourceMethod("read", &method_calls);
    try std.testing.expectEqualSlices(id, &.{fact.application}, method_calls.items);

    for (graph.edges.items) |edge| {
        if (edge.from != fact.application) continue;
        try std.testing.expect(edge.kind != .relation);
        try std.testing.expect(edge.kind != .subject);
        try std.testing.expect(edge.kind != .argument);
        try std.testing.expect(edge.kind != .result);
    }

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "application.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    const projected = parsed.value.object.get("applications").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), projected.len);
    try std.testing.expectEqual(
        @as(i64, @intCast(stored.subject.?)),
        projected[0].object.get("subject").?.integer,
    );
    try std.testing.expectEqualStrings("single", projected[0].object.get("demand").?.string);
    const projected_shapes = parsed.value.object.get("call_shapes").?.array.items;
    try std.testing.expectEqual(graph.application_candidates.count(), projected_shapes.len);
    var matching_shapes: usize = 0;
    for (projected_shapes) |shape| {
        if (shape.object.get("node").?.integer != @as(i64, @intCast(fact.application))) continue;
        matching_shapes += 1;
        try std.testing.expectEqualStrings("read", shape.object.get("method").?.string);
    }
    try std.testing.expectEqual(@as(usize, 1), matching_shapes);
}

test "semantic_graph: moduleFunctionEmitOrder callees before callers" {
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
    var lex = Lexer.init(src, "order.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&module, &checked, "order.id");

    const main = g.findFunc("main") orelse return error.TestExpectedEqual;
    const helper = g.findFunc("helper") orelse return error.TestExpectedEqual;
    const functions = [_]id{ main, helper };
    const order = try g.moduleFunctionEmitOrder(alloc, &functions);
    defer alloc.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqual(helper, order[0]);
    try std.testing.expectEqual(main, order[1]);

    const idle = try g.addNode(.{
        .kind = .func,
        .span = .{ .file = "order.id", .start = 0, .end = 0 },
    });
    const independent = [_]id{ helper, idle };
    const unchanged = try g.moduleFunctionEmitOrder(alloc, &independent);
    defer alloc.free(unchanged);
    try std.testing.expectEqualSlices(id, &independent, unchanged);

    const duplicate = [_]id{ main, main };
    try std.testing.expectError(error.DuplicateFunctionEntity, g.moduleFunctionEmitOrder(alloc, &duplicate));
    const invalid = [_]id{std.math.maxInt(id)};
    try std.testing.expectError(error.InvalidFunctionEntity, g.moduleFunctionEmitOrder(alloc, &invalid));

    const unresolved = g.application_facts.items[0].application;
    g.nodes.items[unresolved].kind = .value;
    g.application_presence.unset(unresolved);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
    g.application_presence.set(unresolved);

    const application_row = g.application_rows.items[unresolved];
    g.application_rows.items[unresolved] = std.math.maxInt(u32);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
    g.application_rows.items[unresolved] = application_row;

    g.application_facts.items[0].results.len = std.math.maxInt(u32);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
}

test "semantic_graph: moduleFunctionEmitOrder condenses recursive dependencies" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\a: i64 = ()
        \\    b()
        \\b: i64 = ()
        \\    a()
        \\c: i64 = ()
        \\    a()
    ;
    var lex = Lexer.init(src, "recursive.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&module, &checked, "recursive.id");

    const a = g.findFunc("a") orelse return error.TestExpectedEqual;
    const b = g.findFunc("b") orelse return error.TestExpectedEqual;
    const c = g.findFunc("c") orelse return error.TestExpectedEqual;
    const functions = [_]id{ c, a, b };
    const order = try g.moduleFunctionEmitOrder(alloc, &functions);
    defer alloc.free(order);
    try std.testing.expectEqualSlices(id, &.{ a, b, c }, order);

    const recursive = [_]id{ b, a };
    const stable = try g.moduleFunctionEmitOrder(alloc, &recursive);
    defer alloc.free(stable);
    try std.testing.expectEqualSlices(id, &recursive, stable);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        moduleFunctionEmitOrderAllocationProbe,
        .{ &g, functions[0..], @as([]const id, &.{ a, b, c }) },
    );
}

test "semantic_graph: recursive function ordering releases temporary state" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        orderFunctionComponentsAllocationProbe,
        .{},
    );
}

test "semantic_graph: liftAliasShapes records native storage class" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Point = { x: f64, y: f64 }
        \\function main()
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const point_id = g.findByName("Point") orelse return error.TestExpectedEqual;
    const node = g.get(point_id).?;
    try std.testing.expectEqual(.table_shape, node.kind);
    try std.testing.expectEqual(types.StorageClass.native, node.storage_class.?);
    try std.testing.expectEqual(@as(u16, 2), node.field_count);
}

test "semantic_graph: findTableShape returns shape node" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const shape = try g.addNode(.{
        .kind = .table_shape,
        .span = .{ .file = "t", .start = 0, .end = 1 },
        .name = "Point",
        .storage_class = .native,
        .field_count = 2,
    });
    _ = shape;
    const node = g.findTableShape("Point") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(.native, node.storage_class.?);
    try std.testing.expect(g.findTableShape("Missing") == null);
}

test "semantic_graph: liftEnumShapes records enum variants" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\function main()
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const node = g.findEnumShape("Color") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(.enum_shape, node.kind);
    try std.testing.expectEqual(@as(u16, 3), node.field_count);
}

test "semantic_graph: writeJson includes table_shapes and enum_shapes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Point = { x: f64, y: f64 }
        \\enum Color
        \\  Red
        \\  Green
        \\end
        \\function main()
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try g.writeJson(alloc, "test.duo", &json, null);
    const s = json.items;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, s, .{});
    defer parsed.deinit();
    try std.testing.expect(std.mem.indexOf(u8, s, "\"table_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"enum_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Color\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"storage_class\":\"native\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"shape_fingerprint\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"id_scope\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"table_shapes\":[{\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"enum_shapes\":[{\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"why\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"fields\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "native C scalars") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"generation\"") == null);
}

test "semantic_graph: writeJson escapes every JSON control byte" {
    const alloc = std.testing.allocator;
    const file = "control\x00\x01\x08\x0c\x1f.id";
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);

    try graph.writeJson(alloc, file, &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(file, parsed.value.object.get("file").?.string);
}

test "semantic_graph: malformed table-shape scope refuses projection" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    _ = try graph.addNode(.{
        .kind = .table_shape,
        .span = .{ .file = "malformed.id", .start = 1, .end = 1 },
        .name = "shape",
    });
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.InvalidTableShapeScope,
        graph.writeJson(std.testing.allocator, "malformed.id", &json, null),
    );
}

test "semantic_graph: equal projection metadata does not merge graph entities" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const node = Node{
        .kind = .value,
        .span = .{ .file = "same.id", .start = 1, .end = 1 },
        .name = "same",
    };
    const first = try graph.addNode(node);
    const second = try graph.addNode(node);
    try std.testing.expect(first != second);
    try std.testing.expectEqualStrings(graph.get(first).?.name.?, graph.get(second).?.name.?);
    try std.testing.expectEqual(graph.get(first).?.span.start, graph.get(second).?.span.start);
}

test "semantic_graph: textual projections refuse same-kind ambiguity" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "ambiguous.id", .start = 0, .end = 0 },
    });
    const first = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "ambiguous.id", .start = 1, .end = 1 },
        .name = "same",
    });
    const second = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "ambiguous.id", .start = 2, .end = 1 },
        .name = "same",
    });
    try std.testing.expect(first != second);
    try std.testing.expect(graph.findFunc("same") == null);
}

test "semantic_graph: packed application facts reject duplicate and wrong roles" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "axes.id", .start = 0, .end = 0 },
    });
    const relation = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "axes.id", .start = 1, .end = 1 },
        .name = "apply",
    });
    const application = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(application);
    const subject = try graph.addChild(module, .{
        .kind = .param,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const argument = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const result = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const arguments = [_]id{argument};
    const results = [_]id{result};
    try graph.publishApplication(
        application,
        relation,
        subject,
        relation,
        .i64,
        .unknown,
        graph.get(application).?.span,
        &arguments,
        &results,
    );
    try std.testing.expectEqual(relation, graph.applicationRelation(application).?);
    try std.testing.expectEqual(subject, graph.application(application).?.subject.?);
    try std.testing.expectEqualSlices(id, &arguments, graph.applicationArguments(application).?);
    try std.testing.expectEqual(result, graph.applicationResult(application).?);
    try std.testing.expect(graph.application(@intCast(graph.nodes.items.len)) == null);

    try std.testing.expectError(
        error.InvalidApplicationFact,
        graph.publishApplication(
            application,
            relation,
            subject,
            relation,
            .i64,
            .single,
            graph.get(application).?.span,
            &arguments,
            &results,
        ),
    );

    try std.testing.expectError(
        error.DuplicateApplicationFact,
        graph.publishApplication(
            application,
            relation,
            subject,
            relation,
            .i64,
            .unknown,
            graph.get(application).?.span,
            &arguments,
            &results,
        ),
    );

    const wrong = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 3, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(wrong);
    const wrong_result = try graph.addChild(wrong, .{
        .kind = .value,
        .span = .{ .file = "axes.id", .start = 3, .end = 1 },
        .descriptor = .i64,
    });
    const wrong_results = [_]id{wrong_result};
    try std.testing.expectError(
        error.InvalidApplicationRelation,
        graph.publishApplication(
            wrong,
            result,
            null,
            relation,
            .i64,
            .unknown,
            graph.get(wrong).?.span,
            &.{},
            &wrong_results,
        ),
    );

    const incomplete = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(incomplete);
    const without_descriptor = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
    });
    const wrong_descriptor = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i32,
    });
    const complete_result = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i64,
    });
    const incomplete_arguments = [_]id{without_descriptor};
    const incomplete_results = [_]id{complete_result};
    try std.testing.expectError(
        error.InvalidApplicationSubject,
        graph.publishApplication(
            incomplete,
            relation,
            without_descriptor,
            relation,
            .i64,
            .unknown,
            graph.get(incomplete).?.span,
            &.{},
            &incomplete_results,
        ),
    );
    try std.testing.expectError(
        error.InvalidApplicationArgument,
        graph.publishApplication(
            incomplete,
            relation,
            null,
            relation,
            .i64,
            .unknown,
            graph.get(incomplete).?.span,
            &incomplete_arguments,
            &incomplete_results,
        ),
    );
    const mismatched_results = [_]id{wrong_descriptor};
    try std.testing.expectError(
        error.InvalidApplicationResult,
        graph.publishApplication(
            incomplete,
            relation,
            null,
            relation,
            .i64,
            .unknown,
            graph.get(incomplete).?.span,
            &.{},
            &mismatched_results,
        ),
    );
}

test "semantic_graph: checked occurrences keep distinct packed ranges" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\sum: i64 = (a: i64, b: i64)
        \\    a + b
        \\main: i64 = ()
        \\    sum(1, 2) + sum(3, 4)
    ;
    var lexer = Lexer.init(source, "ranges.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var probe = SemanticGraph.init(alloc);
    _ = try probe.liftModuleWithCalls(&module, "ranges.id");
    try std.testing.expect(probe.nodes.items.len < 64);
    const prefix = 64 - probe.nodes.items.len;
    probe.deinit();

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    for (0..prefix) |_| {
        _ = try graph.addNode(.{
            .kind = .value,
            .span = .{ .file = "ranges.id", .start = 0, .end = 0 },
        });
    }
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "ranges.id");

    const facts = graph.applications();
    try std.testing.expect(graph.nodes.items.len > 64);
    try std.testing.expectEqual(@as(usize, 2), facts.len);
    try std.testing.expect(facts[0].application != facts[1].application);
    try std.testing.expectEqual(facts[0].relation, facts[1].relation);
    try std.testing.expect(facts[0].arguments.start != facts[1].arguments.start);
    try std.testing.expect(facts[0].results.start != facts[1].results.start);
    for (facts) |fact| {
        try std.testing.expectEqual(@as(usize, 2), graph.applicationArguments(fact.application).?.len);
        try std.testing.expectEqual(@as(usize, 1), graph.applicationResults(fact.application).?.len);
        try std.testing.expect(graph.application(fact.application) != null);
    }

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "ranges.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    const projected = parsed.value.object.get("applications").?.array.items;
    try std.testing.expectEqual(facts.len, projected.len);
    for (projected, facts) |value, fact| {
        const object = value.object;
        try std.testing.expectEqual(@as(i64, @intCast(fact.application)), object.get("application").?.integer);
        try std.testing.expectEqual(@as(i64, @intCast(fact.relation)), object.get("relation").?.integer);
        try std.testing.expectEqual(@as(i64, @intCast(fact.caller)), object.get("caller").?.integer);
        try std.testing.expect(object.get("subject") == null);
        try std.testing.expectEqual(types.ReturnConsumption.single, fact.demand);
        try std.testing.expectEqualStrings("single", object.get("demand").?.string);
        try std.testing.expect(object.get("descriptor").?.string.len > 0);
        const provenance = object.get("provenance").?.object;
        try std.testing.expectEqualStrings("ranges.id", provenance.get("file").?.string);
        try std.testing.expectEqual(@as(i64, fact.provenance.start), provenance.get("start").?.integer);
        try std.testing.expectEqual(@as(i64, fact.provenance.end), provenance.get("end").?.integer);

        const expected_arguments = graph.applicationArguments(fact.application).?;
        const projected_arguments = object.get("arguments").?.array.items;
        try std.testing.expectEqual(expected_arguments.len, projected_arguments.len);
        for (projected_arguments, expected_arguments) |argument, expected| {
            try std.testing.expectEqual(@as(i64, @intCast(expected)), argument.integer);
        }
        const expected_results = graph.applicationResults(fact.application).?;
        const projected_results = object.get("results").?.array.items;
        try std.testing.expectEqual(expected_results.len, projected_results.len);
        for (projected_results, expected_results) |result, expected| {
            try std.testing.expectEqual(@as(i64, @intCast(expected)), result.integer);
        }
    }

    const first_application = facts[0].application;
    const first_result = graph.applicationResults(first_application).?[0];
    graph.application_facts.items[0].relation = first_result;
    try std.testing.expect(graph.application(first_application) == null);
}

test "semantic_graph: resident ids exhaust without a sentinel" {
    try std.testing.expectEqual(@as(id, 0), try SemanticGraph.coordinateForLength(0));
    try std.testing.expectEqual(
        std.math.maxInt(id),
        try SemanticGraph.coordinateForLength(std.math.maxInt(id)),
    );
    if (comptime @bitSizeOf(usize) > @bitSizeOf(id)) {
        try std.testing.expectError(
            error.GraphCoordinateExhausted,
            SemanticGraph.coordinateForLength(@as(usize, std.math.maxInt(id)) + 1),
        );
    }
}

test "semantic_graph: duplicate declaration provenance refuses" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\target: i64 = ()
        \\    0
    , "duplicate-declaration.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const parent = try graph.liftModule(&module, "duplicate-declaration.id");
    const declaration = &module.body.stmts[0].func_decl;
    _ = try graph.addChild(parent, .{
        .kind = .func,
        .span = .{ .file = "duplicate-declaration.id", .start = 1, .end = 1 },
        .name = "duplicate",
        .ast_ref = @ptrCast(@constCast(declaration)),
    });

    try std.testing.expectError(
        error.DuplicateSemanticDeclaration,
        graph.findFuncDecl(declaration),
    );
}

test "semantic_graph: liftFunctionBindings creates inline table_shape" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\point: {
        \\    x: f64
        \\    y: f64
        \\}
        \\main: i64 = ()
        \\    p: point = { x = 1.0, y = 2.0 }
        \\    other: { x: f64, y: f64 } = { x = 3.0, y = 4.0 }
        \\    0
    , "binding.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "binding.id");

    const inline_shape = g.findTableShape("other@shape") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(types.StorageClass.native, inline_shape.storage_class.?);
    try std.testing.expectEqual(@as(u16, 2), inline_shape.field_count);
    try std.testing.expect(countTransformApps(&g, "shape.lift") >= 1);
}

fn countTransformApps(g: *const SemanticGraph, transform_name: []const u8) usize {
    var n: usize = 0;
    for (g.nodes.items) |node| {
        if (node.kind != .transform_app) continue;
        if (node.name) |nm| {
            if (std.mem.eql(u8, nm, transform_name)) n += 1;
        }
    }
    return n;
}

test "semantic_graph: native alias lift attaches shape transforms" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init("alias Point = { x: f64, y: f64 }", "test.duo");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.addNode(.{ .kind = .module, .span = .{ .file = "t", .start = 0, .end = 0 }, .name = "t" });
    try g.liftAliasShapes(&module, "test.duo", mod_id);
    try std.testing.expect(countTransformApps(&g, "shape.lift") >= 1);
    try std.testing.expect(countTransformApps(&g, "shape.specialize") >= 1);
    const point = g.findTableShape("Point") orelse return error.TestExpectedEqual;
    try std.testing.expect(point.descriptor_hash != null);
    try std.testing.expect(point.descriptor_label != null);
    try std.testing.expectEqualStrings("Point", point.descriptor_label.?);
}

test "semantic_graph: alias extension builds descriptor composition" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Named = { name: str }
        \\alias Colored = Named
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const colored = g.findTableShape("Colored") orelse return error.TestExpectedEqual;
    try std.testing.expect(colored.descriptor_label != null);
    try std.testing.expectEqualStrings("Named+Colored", colored.descriptor_label.?);
}

test "semantic_graph: table shape_id stable across identical field sets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields_a = try alloc.alloc(types.FieldType, 2);
    fields_a[0] = .{ .name = "x", .typ = .f64 };
    fields_a[1] = .{ .name = "y", .typ = .f64 };
    const fields_b = try alloc.alloc(types.FieldType, 2);
    fields_b[0] = .{ .name = "x", .typ = .f64 };
    fields_b[1] = .{ .name = "y", .typ = .f64 };
    const rt_a: types.ResolvedType = .{ .table_type = .{ .fields = fields_a, .storage_class = .native } };
    const rt_b: types.ResolvedType = .{ .table_type = .{ .fields = fields_b, .storage_class = .native } };
    try std.testing.expectEqual(types.tableShapeIdentityHash(rt_a), types.tableShapeIdentityHash(rt_b));
}

test "semantic_graph: descriptor lifecycle facts need no parallel identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\PairA: { first: i32, second: str }
        \\PairB: { first: i32, second: str }
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const pair_a = g.findTableShape("PairA") orelse return error.TestExpectedEqual;
    const pair_b = g.findTableShape("PairB") orelse return error.TestExpectedEqual;
    try std.testing.expect(pair_a.descriptor_state == .sealed);
    try std.testing.expect(pair_b.descriptor_state == .sealed);
    try std.testing.expect(pair_a.recursion == .none);
    try std.testing.expect(pair_b.recursion == .none);
    try std.testing.expect(pair_a.completion == .complete);
    try std.testing.expect(pair_b.completion == .complete);
}

test "semantic_graph: recursive descriptor facts remain graph-derived" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node: types.ResolvedType = .{ .@"struct" = .{ .name = "Node" } };
    const next = try alloc.create(types.ResolvedType);
    next.* = node;
    const fields = try alloc.alloc(types.FieldType, 2);
    fields[0] = .{ .name = "value", .typ = .i64 };
    fields[1] = .{ .name = "next", .typ = .{ .pointer = next } };
    const descriptor: types.ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .native,
        .is_sealed = true,
    } };

    const recursion = classifyDescriptorRecursion("Node", descriptor);
    try std.testing.expectEqual(Recursion.indirect_pointer, recursion);
    try std.testing.expectEqual(
        Completion.complete,
        resolveDescriptorCompletion(recursion, descriptor),
    );
}

test "semantic_graph: alias with derive builds transform descriptor label" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\@derive(Display, Eq)
        \\type Vec2 = { x: f64, y: f64 }
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const vec = g.findTableShape("Vec2") orelse return error.TestExpectedEqual;
    try std.testing.expect(vec.descriptor_label != null);
    try std.testing.expectEqualStrings("Vec2~Display~Eq", vec.descriptor_label.?);
}

test "semantic_graph: pipeline face normalizes to an iteration relation" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\fun double(x: i64): i64
        \\  x * 2
        \\end
        \\fun main()
        \\  x = 21 |> double
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.liftModuleWithCalls(&module, "test.duo");
    _ = mod_id;
    try std.testing.expectEqual(@as(usize, 1), g.countKind(.relation));
    for (g.nodes.items) |node| {
        if (node.kind != .relation) continue;
        try std.testing.expectEqual(semantic_algebra.IterationRelation.map, node.iteration_relation.?);
    }
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try g.writeJson(alloc, "test.duo", &json, null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"kind\":\"relation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"relation\":\"map\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"kind\":\"pipeline\"") == null);
}

test "semantic_graph: usersOf finds use edges" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const a = try g.addNode(.{ .kind = .local, .span = .{ .file = "t", .start = 0, .end = 1 }, .name = "a" });
    const b = try g.addNode(.{ .kind = .call, .span = .{ .file = "t", .start = 2, .end = 3 } });
    try g.addEdge(.{ .from = b, .to = a, .kind = .use });
    var users: std.ArrayListUnmanaged(id) = .empty;
    defer users.deinit(g.alloc);
    try g.usersOf(a, &users);
    try std.testing.expectEqual(@as(usize, 1), users.items.len);
    try std.testing.expectEqual(b, users.items[0]);
}

test "semantic_graph: identity lookup survives a param that shadows a function name" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\scale: i64 = (n: i64)
        \\    n * 2
        \\n: i64 = ()
        \\    7
    ;
    var lex = Lexer.init(src, "shadow.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModule(&module, "shadow.id");

    try std.testing.expect(g.findByName("n") == null);

    const exact = g.findFunc("n") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(NodeKind.func, g.get(exact).?.kind);
}

test "semantic_graph: same-named params in different functions get distinct ids" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\first: i64 = (v: i64)
        \\    v + 1
        \\second: i64 = (v: i64)
        \\    v + 2
    ;
    var lex = Lexer.init(src, "params.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModule(&module, "params.id");

    var identities: [2]id = undefined;
    var count: usize = 0;
    for (g.nodes.items, 0..) |node, i| {
        if (node.kind != .param) continue;
        const name = node.name orelse continue;
        if (!std.mem.eql(u8, name, "v")) continue;
        identities[count] = @intCast(i);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expect(identities[0] != identities[1]);
    try std.testing.expect(g.get(identities[0]).?.scope.? != g.get(identities[1]).?.scope.?);
}

test "semantic_graph: four calls to one callee in one body are four identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\double: i64 = (x: i64)
        \\    x * 2
        \\run: i64 = (a: i64)
        \\    double(a) + double(a) + double(a) + double(a)
    ;
    var lex = Lexer.init(src, "calls.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&module, "calls.id");

    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(alloc);
    var calls: usize = 0;
    var candidates = g.application_candidates.iterator(.{});
    while (candidates.next()) |candidate| {
        const entity = std.math.cast(id, candidate) orelse
            return error.ApplicationFactCapacityExceeded;
        calls += 1;
        try seen.put(alloc, entity, {});
    }
    // Positive control on the count: a zero here would make the identity
    // assertion below vacuously true.
    try std.testing.expectEqual(@as(usize, 4), calls);
    try std.testing.expectEqual(@as(usize, 4), seen.count());
}

test "semantic_graph: same-named locals in sibling blocks are distinct identities" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const module = try g.addNode(.{ .kind = .module, .span = .{ .file = "locals.id", .start = 0, .end = 0 } });
    const function = try g.addChild(module, .{ .kind = .func, .span = .{ .file = "locals.id", .start = 1, .end = 1 }, .name = "pick" });
    const first = try g.addChild(function, .{ .kind = .local, .span = .{ .file = "locals.id", .start = 2, .end = 2 }, .name = "value" });
    const second = try g.addChild(function, .{ .kind = .local, .span = .{ .file = "locals.id", .start = 2, .end = 2 }, .name = "value" });
    try std.testing.expect(first != second);
    try std.testing.expectEqual(g.get(first).?.scope, g.get(second).?.scope);
}
