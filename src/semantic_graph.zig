/// Persistent semantic graph (Phase 1 spine).
///
/// Canonical plan: `docs/semantic_universe.md`
///
/// Phase 1 goal: stable `NodeId` within a compile session, built from AST+sema,
/// with read-only query API. No behavior change to codegen until Phase 2 wiring.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const pass26_descriptor_intern = @import("pass26_descriptor_intern.zig");
const pass26_descriptor_identity = @import("pass26_descriptor_identity.zig");
const pass26_recursive_descriptor = @import("pass26_recursive_descriptor.zig");

pub const NodeId = struct {
    index: u32,

    pub const invalid: NodeId = .{ .index = std.math.maxInt(u32) };

    pub fn isValid(self: NodeId) bool {
        return self.index != invalid.index;
    }
};

/// Content-addressed durable identity (A1): hash(module_path, kind, stable_path, generation).
pub const StableId = struct {
    hash: u64,

    pub fn compute(module_path: []const u8, kind: NodeKind, stable_path: []const u8, generation: u32) StableId {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(module_path);
        hasher.update("|");
        hasher.update(&[_]u8{@intFromEnum(kind)});
        hasher.update("|");
        hasher.update(stable_path);
        hasher.update("|");
        hasher.update(std.mem.asBytes(&generation));
        return .{ .hash = hasher.final() };
    }

    pub fn formatHex(self: StableId, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{x:0>16}", .{self.hash}) catch "0000000000000000";
    }
};

pub const NodeKind = enum {
    module,
    source_file,
    func,
    param,
    local,
    type_node,
    call,
    directive,
    concept,
    transform_app,
    comptime_value,
    emit_artifact,
    /// Typed table/record shape node (storage class + field count).
    table_shape,
    /// Enum descriptor shape (variant count in `field_count`; names via `ast_ref`).
    enum_shape,
    /// Pass 2.3: `|>` pipeline step in optimization graph IR.
    pipeline,
};

pub const EdgeKind = enum {
    contains,
    def,
    use,
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

pub const Node = struct {
    kind: NodeKind,
    span: SpanRef,
    name: ?[]const u8 = null,
    /// For `.table_shape`: storage class label (dynamic/guarded/sealed/native).
    storage_class: ?types.StorageClass = null,
    field_count: u16 = 0,
    /// Stable shape identity (content hash; matches codegen struct dedup).
    shape_id: ?u64 = null,
    /// For `.call` nodes: call-shape identity hash for specialization dedup.
    call_shape_id: ?u64 = null,
    /// For `.call` nodes: the inferred CallShape (Phase 1 — conservative from AST).
    call_shape: ?types.CallShape = null,
    /// Factual `@comp.why.shape` explanation captured at graph lift.
    why: ?[]const u8 = null,
    /// Pass 2: knowledge lattice position when known.
    knowledge: ?semantic_algebra.KnowledgeLevel = null,
    /// Pass 2: evaluation stage when known.
    stage: ?semantic_algebra.Stage = null,
    /// Pass 2.1: descriptor algebra hash for alias/type nodes (internal).
    descriptor_hash: ?u64 = null,
    /// Pass 26: canonical semantic fingerprint (interning/specialization; distinct from shape_id).
    semantic_fingerprint: ?u64 = null,
    /// Pass 26 M1: declaration/provenance identity (never merged across bindings).
    declaration_identity: ?u64 = null,
    /// Pass 26 M1: intern slot when pure descriptors collapse.
    intern_slot: ?u32 = null,
    /// Pass 26 M1: descriptor lifecycle state at lift.
    descriptor_state: ?pass26_descriptor_identity.DescriptorState = null,
    /// Pass 26 M1: recursive layout classification.
    recursion: ?pass26_recursive_descriptor.RecursionKind = null,
    /// Pass 26 M1: fixed-point resolution status.
    completion: ?pass26_recursive_descriptor.DescriptorCompletion = null,
    /// Human-readable descriptor composition label (`Point+Named`).
    descriptor_label: ?[]const u8 = null,
    /// Pass 2.3: pipeline algebra op when `kind == .pipeline` (`|>` lowers to `.map`).
    pipeline_op: ?semantic_algebra.PipelineOp = null,
    /// Pass 2.4: hardware lowering targets for pipeline nodes (cpu/simd/gpu).
    hardware_lowerings: semantic_algebra.HardwareSet = .{},
    /// Opaque link to AST for Phase 1 — graph mirrors, does not replace, AST yet.
    ast_ref: ?*anyopaque = null,
    /// Content-addressed durable ID (survives benign reparses when path+span match).
    stable_id: ?StableId = null,
    /// When true, `name` was allocated on the graph allocator and must be freed in deinit.
    owns_name: bool = false,
};

pub const Edge = struct {
    from: NodeId,
    to: NodeId,
    kind: EdgeKind,
};

pub const SemanticGraph = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    edges: std.ArrayListUnmanaged(Edge) = .empty,
    /// Module path used for stable_id computation.
    module_path: []const u8 = "",
    /// Generation counter for transactional edits (default 0).
    generation: u32 = 0,
    /// Module-scope func decls indexed by name (Pass 2.2 effect inference on call lift).
    func_decls: std.StringHashMapUnmanaged(*const ast.FuncDecl) = .empty,
    /// Pass 25 §5.1 — tail-demand resolution per function (principal semantic result lineage).
    func_tail_results: std.StringHashMapUnmanaged(tail_result_demand.Resolution) = .empty,
    /// Pass 26 M1 — descriptor fingerprint interning at alias lift.
    descriptor_registry: pass26_descriptor_intern.Registry = undefined,

    pub fn init(alloc: std.mem.Allocator) SemanticGraph {
        return .{
            .alloc = alloc,
            .descriptor_registry = pass26_descriptor_intern.Registry.init(alloc),
        };
    }

    pub fn deinit(self: *SemanticGraph) void {
        for (self.nodes.items) |node| {
            if (node.why) |w| self.alloc.free(w);
            if (node.descriptor_label) |d| self.alloc.free(d);
            if (node.owns_name) {
                if (node.name) |n| self.alloc.free(n);
            }
        }
        self.nodes.deinit(self.alloc);
        self.edges.deinit(self.alloc);
        self.func_decls.deinit(self.alloc);
        self.func_tail_results.deinit(self.alloc);
        self.descriptor_registry.deinit();
    }

    fn stablePathForNode(node: *const Node, buf: []u8) []const u8 {
        if (node.name) |name| return name;
        return std.fmt.bufPrint(buf, "{s}:{d}:{d}", .{
            nodeKindLabel(node.kind),
            node.span.start,
            node.span.end,
        }) catch "anon";
    }

    fn computeStableId(self: *const SemanticGraph, node: *const Node) StableId {
        var buf: [256]u8 = undefined;
        const path = stablePathForNode(node, &buf);
        return StableId.compute(self.module_path, node.kind, path, self.generation);
    }

    pub fn addNode(self: *SemanticGraph, node: Node) !NodeId {
        const id = NodeId{ .index = @intCast(self.nodes.items.len) };
        var n = node;
        if (n.stable_id == null and self.module_path.len > 0) {
            n.stable_id = self.computeStableId(&n);
        }
        try self.nodes.append(self.alloc, n);
        return id;
    }

    pub fn addEdge(self: *SemanticGraph, edge: Edge) !void {
        try self.edges.append(self.alloc, edge);
    }

    pub fn get(self: *const SemanticGraph, id: NodeId) ?*const Node {
        if (!id.isValid() or id.index >= self.nodes.items.len) return null;
        return &self.nodes.items[id.index];
    }

    /// Find the first node with a given name. O(n) scan.
    /// NOTE: duplicate names exist (locals in different scopes). This returns
    /// the first match. For production scale, replace with a scope-qualified
    /// index (e.g. HashMap([]const u8, ArrayList(NodeId))).
    pub fn findByName(self: *const SemanticGraph, name: []const u8) ?NodeId {
        for (self.nodes.items, 0..) |node, i| {
            if (node.name) |n| {
                if (std.mem.eql(u8, n, name)) return NodeId{ .index = @intCast(i) };
            }
        }
        return null;
    }

    pub fn usersOf(self: *const SemanticGraph, target: NodeId, buf: *std.ArrayListUnmanaged(NodeId)) !void {
        for (self.edges.items) |e| {
            if (e.to.index == target.index and e.kind == .use) {
                try buf.append(self.alloc, e.from);
            }
        }
    }

    pub fn defsOf(self: *const SemanticGraph, name: []const u8) ?NodeId {
        return self.findByName(name);
    }

    /// Register a shape algebra transform (`shape.lift`, `shape.seal`, …) on the graph.
    fn addShapeTransformApp(
        self: *SemanticGraph,
        parent: NodeId,
        op: semantic_algebra.ShapeOp,
        input_knowledge: semantic_algebra.KnowledgeLevel,
        span: SpanRef,
        output_shape: NodeId,
        input_hash: u64,
        output_hash: u64,
    ) !NodeId {
        const transform_name = semantic_algebra.shapeTransformId(op);
        std.debug.assert(transform_engine.isShapeTransform(transform_name));
        const node_id = try self.addNode(.{
            .kind = .transform_app,
            .span = span,
            .name = transform_name,
            .knowledge = semantic_algebra.ShapeOp.resultingKnowledge(op, input_knowledge),
            .stage = .transform,
        });
        try self.addEdge(.{ .from = parent, .to = node_id, .kind = .contains });
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
        parent: NodeId,
        span: SpanRef,
        rt: types.ResolvedType,
        sc: types.StorageClass,
        shape_id: ?u64,
        shape_node: NodeId,
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

    /// Register eligible call algebra transforms for a lifted call node.
    fn attachCallTransforms(
        self: *SemanticGraph,
        parent: NodeId,
        call_id: NodeId,
        site: semantic_algebra.CallSite,
        shape: types.CallShape,
        span: SpanRef,
    ) !void {
        const transforms = [_]semantic_algebra.CallTransform{
            .@"inline", .specialize, .memo, .devirtualize, .gpu_lower, .simd_lower,
        };
        for (transforms) |op| {
            if (!semantic_algebra.callTransformEligible(op, site, shape)) continue;
            const transform_name = semantic_algebra.callTransformId(op);
            std.debug.assert(transform_engine.isCallTransform(transform_name));
            const node_id = try self.addNode(.{
                .kind = .transform_app,
                .span = span,
                .name = transform_name,
                .knowledge = site.knowledge,
                .stage = site.stage,
            });
            try self.addEdge(.{ .from = parent, .to = node_id, .kind = .contains });
            try self.addEdge(.{ .from = node_id, .to = call_id, .kind = .transform_input });
            const hash = shape.identityHash();
            transform_engine.logProvenance(self.alloc, transform_name, .emit_call, hash, hash);
        }
    }

    /// Lift module-level function names from AST (Phase 1 minimal — no sema yet).
    pub fn liftModule(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !NodeId {
        self.module_path = file;
        const mod_id = try self.addNode(.{
            .kind = .module,
            .span = .{ .file = file, .start = 0, .end = 0 },
            .name = file,
        });
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const func_id = try self.addNode(.{
                .kind = .func,
                .span = .{
                    .file = file,
                    .start = fd.loc.line,
                    .end = fd.loc.col,
                },
                .name = fd.path[0],
                .ast_ref = @ptrCast(fd),
            });
            try self.addEdge(.{ .from = mod_id, .to = func_id, .kind = .contains });
            try self.func_decls.put(self.alloc, fd.path[0], fd);
            if (tail_result_demand.blockTailResultWithDemand(&fd.func.body, tail_result_demand.demandFromRetType(fd.func.ret_type))) |tr| {
                try self.func_tail_results.put(self.alloc, fd.path[0], tr);
            }
            for (fd.func.params) |param| {
                const param_id = try self.addNode(.{
                    .kind = .param,
                    .span = .{ .file = file, .start = 0, .end = 0 },
                    .name = param.name,
                });
                try self.addEdge(.{ .from = func_id, .to = param_id, .kind = .contains });
            }
        }
        return mod_id;
    }

    /// Lift alias record shapes from AST (Phase 1 — storage class inferred from fields).
    pub fn liftAliasShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: NodeId) !void {
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
            const identity_index = try self.descriptor_registry.registerAlias(
                self.module_path,
                ad.name,
                .{ .line = ad.loc.line, .col = ad.loc.col },
                rt,
                sc,
            );
            const identity = self.descriptor_registry.get(identity_index).?;
            var label_buf: [128]u8 = undefined;
            const label = try self.alloc.dupe(
                u8,
                semantic_algebra.formatDescriptorExprShort(desc_expr, &label_buf),
            );
            const shape_id_node = try self.addNode(.{
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
                .semantic_fingerprint = identity.semantic_fingerprint,
                .declaration_identity = identity.declaration_identity,
                .intern_slot = identity.intern_slot,
                .descriptor_state = identity.state,
                .recursion = identity.recursion,
                .completion = identity.completion,
                .descriptor_label = label,
                .ast_ref = @ptrCast(ad),
            });
            try self.addEdge(.{ .from = parent, .to = shape_id_node, .kind = .contains });
            try self.attachTableShapeTransforms(parent, alias_span, rt, sc, shape_id orelse 0, shape_id_node);
        }
    }

    /// Lift enum descriptor shapes from AST (Phase 2 — unified descriptor spine).
    pub fn liftEnumShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: NodeId) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .enum_def) continue;
            const ed = &stmt.enum_def;
            if (ed.type_params != null) continue;
            const rt = types.enumShapeFromAst(ed, self.alloc) catch continue;
            const shape_id = types.enumShapeIdentityHash(rt);
            const shape_id_node = try self.addNode(.{
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
            try self.addEdge(.{ .from = parent, .to = shape_id_node, .kind = .contains });
        }
    }

    fn scopedBindingName(func_name: []const u8, binding: []const u8, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s}::{s}", .{ func_name, binding }) catch binding;
    }

    fn liftTableShapeFromTypeExpr(
        self: *SemanticGraph,
        file: []const u8,
        func_id: NodeId,
        func_name: []const u8,
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
                var scope_buf: [128]u8 = undefined;
                const local_name = scopedBindingName(func_name, binding_name, &scope_buf);
                const owned_local = try self.alloc.dupe(u8, local_name);
                const local_id = try self.addNode(.{
                    .kind = .local,
                    .span = .{ .file = file, .start = loc.line, .end = loc.col },
                    .name = owned_local,
                    .owns_name = true,
                    .ast_ref = @ptrCast(@constCast(lname)),
                });
                try self.addEdge(.{ .from = func_id, .to = local_id, .kind = .contains });
                if (self.findTableShape(alias) != null) {
                    const shape_id = self.findByName(alias) orelse return;
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
        var scope_buf: [128]u8 = undefined;
        const binding_scope = scopedBindingName(func_name, binding_name, &scope_buf);
        var shape_buf: [144]u8 = undefined;
        const shape_name = std.fmt.bufPrint(&shape_buf, "{s}@shape", .{binding_scope}) catch binding_scope;
        const owned_shape = try self.alloc.dupe(u8, shape_name);
        const owned_binding = try self.alloc.dupe(u8, binding_scope);
        const shape_node_id = try self.addNode(.{
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
        try self.addEdge(.{ .from = func_id, .to = shape_node_id, .kind = .contains });
        try self.attachTableShapeTransforms(func_id, .{
            .file = file,
            .start = loc.line,
            .end = loc.col,
        }, rt, sc, sid, shape_node_id);
        const local_id = try self.addNode(.{
            .kind = .local,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .name = owned_binding,
            .owns_name = true,
            .ast_ref = @ptrCast(@constCast(lname)),
        });
        try self.addEdge(.{ .from = func_id, .to = local_id, .kind = .contains });
        try self.addEdge(.{ .from = local_id, .to = shape_node_id, .kind = .type_of });
    }

    fn liftBindingsInStmts(
        self: *SemanticGraph,
        file: []const u8,
        func_id: NodeId,
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
                            func_name,
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
                    if (fd.path.len == 1) {
                        if (self.findByName(fd.path[0])) |nested_id| {
                            try self.liftBindingsInStmts(file, nested_id, fd.path[0], fd.func.body.stmts);
                        }
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
            const func_id = self.findByName(fd.path[0]) orelse continue;
            try self.liftBindingsInStmts(file, func_id, fd.path[0], fd.func.body.stmts);
        }
    }

    /// Lift module-level symbols, alias table shapes, and enum shapes.
    pub fn liftModuleFull(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !NodeId {
        const mod_id = try self.liftModule(mod, file);
        try self.liftAliasShapes(mod, file, mod_id);
        try self.liftEnumShapes(mod, file, mod_id);
        try self.liftFunctionBindings(mod, file);
        return mod_id;
    }

    /// Lift call sites from function bodies (Phase 1 — call-shape specialization).
    /// Walks all function statements and extracts call/method_call expressions,
    /// recording their CallShape for specialization analysis.
    pub fn liftCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: NodeId) !void {
        for (mod.body.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    const func_id = if (fd.path.len > 0)
                        (self.findByName(fd.path[0]) orelse parent)
                    else
                        parent;
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

    fn liftCallsFromBlock(self: *SemanticGraph, block: *const ast.Block, file: []const u8, parent: NodeId) !void {
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

    fn callSiteForShape(self: *const SemanticGraph, shape: types.CallShape) semantic_algebra.CallSite {
        if (shape.callee_name) |name| {
            if (self.func_decls.get(name)) |fd| {
                const effects = semantic_algebra.effectSetFromAttributes(fd.attributes);
                const hardware = semantic_algebra.hardwareLoweringsFromAttributes(fd.attributes);
                return semantic_algebra.callSiteFromShapeWithCalleeFacts(shape, effects, hardware);
            }
        }
        return semantic_algebra.callSiteFromShape(shape);
    }

    fn liftExprsFromExpr(
        self: *SemanticGraph,
        expr: *const ast.Expr,
        file: []const u8,
        parent: NodeId,
        consumption: types.ReturnConsumption,
    ) !void {
        switch (expr.*) {
            .binop => |b| {
                if (b.op == .pipeline) {
                    const loc = expr.loc();
                    const op = semantic_algebra.PipelineOp.map;
                    var lowerings = semantic_algebra.HardwareSet.singleton(.cpu);
                    if (b.rhs.* == .name) {
                        if (self.func_decls.get(b.rhs.name.ident)) |fd| {
                            lowerings = semantic_algebra.hardwareLoweringsFromAttributes(fd.attributes);
                        }
                    }
                    const pipe_id = try self.addNode(.{
                        .kind = .pipeline,
                        .span = .{
                            .file = file,
                            .start = loc.line,
                            .end = loc.col,
                        },
                        .pipeline_op = op,
                        .hardware_lowerings = lowerings,
                        .knowledge = .observed,
                        .stage = .sema,
                        .ast_ref = @ptrCast(@constCast(expr)),
                    });
                    try self.addEdge(.{ .from = parent, .to = pipe_id, .kind = .contains });
                    const transform_name = semantic_algebra.pipelineTransformId(op);
                    if (transform_engine.isRegisteredTransform(transform_name)) {
                        const transform_id = try self.addNode(.{
                            .kind = .transform_app,
                            .span = .{ .file = file, .start = loc.line, .end = loc.col },
                            .name = transform_name,
                            .knowledge = .observed,
                            .stage = .transform,
                        });
                        try self.addEdge(.{ .from = parent, .to = transform_id, .kind = .contains });
                        try self.addEdge(.{ .from = transform_id, .to = pipe_id, .kind = .transform_output });
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
        expr: *const ast.Expr,
        file: []const u8,
        parent: NodeId,
        consumption: types.ReturnConsumption,
    ) !void {
        const base = types.inferCallShape(expr) orelse return;
        const shape = types.callShapeWithConsumption(base, consumption);
        const call_loc = expr.loc();
        const call_name = shape.callee_name orelse shape.method_name;
        const site = self.callSiteForShape(shape);
        const call_id = try self.addNode(.{
            .kind = .call,
            .span = .{
                .file = file,
                .start = call_loc.line,
                .end = call_loc.col,
            },
            .name = call_name,
            .call_shape = shape,
            .call_shape_id = shape.identityHash(),
            .knowledge = site.knowledge,
            .stage = site.stage,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.addEdge(.{ .from = parent, .to = call_id, .kind = .contains });
        try self.attachCallTransforms(parent, call_id, site, shape, .{
            .file = file,
            .start = call_loc.line,
            .end = call_loc.col,
        });
        // If we know the callee, add a use edge to its definition (if in graph).
        if (shape.callee_name) |callee| {
            if (self.findByName(callee)) |def_id| {
                try self.addEdge(.{ .from = call_id, .to = def_id, .kind = .use });
            }
        }
    }

    /// Lift module fully including call sites (Phase 1 complete lift).
    pub fn liftModuleWithCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !NodeId {
        const mod_id = try self.liftModuleFull(mod, file);
        try self.liftCalls(mod, file, mod_id);
        return mod_id;
    }

    /// Find all call nodes targeting a specific callee name.
    pub fn findCallsByCallee(self: *const SemanticGraph, callee: []const u8, buf: *std.ArrayListUnmanaged(NodeId)) !void {
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != .call) continue;
            if (node.call_shape) |cs| {
                if (cs.callee_name) |n| {
                    if (std.mem.eql(u8, n, callee)) {
                        try buf.append(self.alloc, NodeId{ .index = @intCast(i) });
                    }
                }
            }
        }
    }

    /// Walk `contains` edges upward until a `.func` node is found.
    pub fn containingFuncId(self: *const SemanticGraph, start: NodeId) ?NodeId {
        var cur = start;
        var depth: u32 = 0;
        while (depth < 64) : (depth += 1) {
            const node = self.get(cur) orelse return null;
            if (node.kind == .func) return cur;
            var parent: ?NodeId = null;
            for (self.edges.items) |e| {
                if (e.kind != .contains or e.to.index != cur.index) continue;
                parent = e.from;
                break;
            }
            cur = parent orelse return null;
        }
        return null;
    }

    /// Emit order for module functions: callees before callers (graph call edges).
    /// Names not in `func_names` are ignored; unknown names keep AST order at the end.
    pub fn moduleFunctionEmitOrder(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        func_names: []const []const u8,
    ) ![]const []const u8 {
        if (func_names.len == 0) return try alloc.dupe([]const u8, func_names);

        var in_module: std.StringHashMapUnmanaged(void) = .empty;
        defer in_module.deinit(alloc);
        for (func_names) |name| try in_module.put(alloc, name, {});

        var in_degree: std.StringHashMapUnmanaged(usize) = .empty;
        defer in_degree.deinit(alloc);
        var unlocks: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)) = .empty;
        defer {
            var it = unlocks.iterator();
            while (it.next()) |e| e.value_ptr.deinit(alloc);
            unlocks.deinit(alloc);
        }

        for (func_names) |name| {
            try in_degree.put(alloc, name, 0);
            try unlocks.put(alloc, name, .empty);
        }

        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != .call) continue;
            const cs = node.call_shape orelse continue;
            const callee = cs.callee_name orelse continue;
            if (in_module.get(callee) == null) continue;
            const caller_id = self.containingFuncId(.{ .index = @intCast(i) }) orelse continue;
            const caller_node = self.get(caller_id) orelse continue;
            const caller = caller_node.name orelse continue;
            if (in_module.get(caller) == null) continue;

            const list = unlocks.getPtr(callee).?;
            var dup = false;
            for (list.items) |c| {
                if (std.mem.eql(u8, c, caller)) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            try list.append(alloc, caller);
            const gop = try in_degree.getOrPut(alloc, caller);
            gop.value_ptr.* += 1;
        }

        var ready: std.ArrayListUnmanaged([]const u8) = .empty;
        defer ready.deinit(alloc);
        for (func_names) |name| {
            if (in_degree.get(name).? == 0) try ready.append(alloc, name);
        }

        var ordered: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer ordered.deinit(alloc);

        while (ready.items.len > 0) {
            const name = ready.items[ready.items.len - 1];
            _ = ready.pop();
            try ordered.append(alloc, name);
            const callers = unlocks.get(name) orelse continue;
            for (callers.items) |caller| {
                const deg = in_degree.getPtr(caller) orelse continue;
                deg.* -= 1;
                if (deg.* == 0) try ready.append(alloc, caller);
            }
        }

        if (ordered.items.len != func_names.len) {
            // Cycles or unresolved deps — preserve AST order.
            return try alloc.dupe([]const u8, func_names);
        }

        return try ordered.toOwnedSlice(alloc);
    }

    /// Find all call nodes with a specific method name.
    pub fn findCallsByMethod(self: *const SemanticGraph, method: []const u8, buf: *std.ArrayListUnmanaged(NodeId)) !void {
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != .call) continue;
            if (node.call_shape) |cs| {
                if (cs.method_name) |m| {
                    if (std.mem.eql(u8, m, method)) {
                        try buf.append(self.alloc, NodeId{ .index = @intCast(i) });
                    }
                }
            }
        }
    }

    /// Get the CallShape for a specific call node.
    pub fn callShapeOf(self: *const SemanticGraph, id: NodeId) ?types.CallShape {
        const node = self.get(id) orelse return null;
        if (node.kind != .call) return null;
        return node.call_shape;
    }

    /// Count distinct call shapes (unique identity hashes) in the graph.
    pub fn countDistinctCallShapes(self: *const SemanticGraph) usize {
        var seen = std.AutoHashMapUnmanaged(u64, void){};
        defer seen.deinit(self.alloc);
        for (self.nodes.items) |node| {
            if (node.kind != .call) continue;
            if (node.call_shape_id) |id| {
                seen.put(self.alloc, id, {}) catch continue;
            }
        }
        return seen.count();
    }

    /// Count nodes of a given kind (diagnostics / MCP queries).
    pub fn countKind(self: *const SemanticGraph, kind: NodeKind) usize {
        var n: usize = 0;
        for (self.nodes.items) |node| {
            if (node.kind == kind) n += 1;
        }
        return n;
    }

    /// Lookup a table_shape node by alias name (Phase 1 query API).
    pub fn findTableShape(self: *const SemanticGraph, name: []const u8) ?*const Node {
        const id = self.findByName(name) orelse return null;
        const node = self.get(id) orelse return null;
        if (node.kind != .table_shape) return null;
        return node;
    }

    /// Lookup an enum_shape node by enum name.
    pub fn findEnumShape(self: *const SemanticGraph, name: []const u8) ?*const Node {
        const id = self.findByName(name) orelse return null;
        const node = self.get(id) orelse return null;
        if (node.kind != .enum_shape) return null;
        return node;
    }

    pub fn nodeKindLabel(kind: NodeKind) []const u8 {
        return switch (kind) {
            .module => "module",
            .source_file => "source_file",
            .func => "func",
            .param => "param",
            .local => "local",
            .type_node => "type_node",
            .call => "call",
            .directive => "directive",
            .concept => "concept",
            .transform_app => "transform_app",
            .comptime_value => "comptime_value",
            .emit_artifact => "emit_artifact",
            .table_shape => "table_shape",
            .enum_shape => "enum_shape",
            .pipeline => "pipeline",
        };
    }

    fn jsonEscapeAppend(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, s: []const u8) !void {
        for (s) |c| switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            else => try buf.append(alloc, c),
        };
    }

    fn appendJsonInt(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: anytype) !void {
        var tmp: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
        try buf.appendSlice(alloc, s);
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

    fn shapeScopeLabel(name: []const u8) []const u8 {
        if (std.mem.indexOf(u8, name, "::") != null) return "inline";
        return "module";
    }

    fn resolveTableShapeType(
        node: *const Node,
        graph_alloc: std.mem.Allocator,
    ) !?types.ResolvedType {
        if (node.ast_ref) |raw| {
            if (node.name) |n| {
                if (std.mem.endsWith(u8, n, "@shape")) {
                    const ln: *const ast.LocalName = @ptrCast(@alignCast(raw));
                    var rt = try types.resolve(ln.typ, null, graph_alloc);
                    types.applyTableShapeAttrs(&rt, ln.attributes);
                    return rt;
                }
            }
            const ad: *const ast.AliasDef = @ptrCast(@alignCast(raw));
            if (node.name) |n| {
                if (std.mem.indexOf(u8, n, "::") != null or std.mem.endsWith(u8, n, "@shape")) return null;
            }
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
        }
        return null;
    }

    fn appendTableFieldsJson(
        buf: *std.ArrayListUnmanaged(u8),
        out_alloc: std.mem.Allocator,
        graph_alloc: std.mem.Allocator,
        node: *const Node,
    ) !void {
        try buf.append(out_alloc, '[');
        if (try resolveTableShapeType(node, graph_alloc)) |rt| {
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
        try out.appendSlice(alloc, "{\"schema\":\"sim-v0\",\"version\":1,\"file\":\"");
        try jsonEscapeAppend(out, alloc, file);
        try out.appendSlice(alloc, "\",\"generation\":");
        try appendJsonInt(out, alloc, self.generation);
        if (source_hash) |h| {
            try out.appendSlice(alloc, ",\"source_hash\":");
            try appendJsonInt(out, alloc, h);
        }
        try out.appendSlice(alloc, ",\"nodes\":[");
        for (self.nodes.items, 0..) |node, i| {
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
                try out.appendSlice(alloc, if (node.name) |n| shapeScopeLabel(n) else "module");
                try out.appendSlice(alloc, "\",\"field_count\":");
                try appendJsonInt(out, alloc, node.field_count);
                if (node.shape_id) |sid| {
                    try out.appendSlice(alloc, ",\"shape_id\":");
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
                if (node.semantic_fingerprint) |sf| {
                    try out.appendSlice(alloc, ",\"semantic_fingerprint\":");
                    try appendJsonInt(out, alloc, sf);
                }
                if (node.declaration_identity) |di| {
                    try out.appendSlice(alloc, ",\"declaration_identity\":");
                    try appendJsonInt(out, alloc, di);
                }
                if (node.intern_slot) |slot| {
                    try out.appendSlice(alloc, ",\"intern_slot\":");
                    try appendJsonInt(out, alloc, slot);
                }
                if (node.descriptor_state) |ds| {
                    try out.appendSlice(alloc, ",\"descriptor_state\":\"");
                    try out.appendSlice(alloc, pass26_descriptor_identity.DescriptorState.name(ds));
                    try out.append(alloc, '"');
                }
                if (node.recursion) |rc| {
                    try out.appendSlice(alloc, ",\"recursion\":\"");
                    try out.appendSlice(alloc, pass26_recursive_descriptor.RecursionKind.name(rc));
                    try out.append(alloc, '"');
                }
                if (node.completion) |cp| {
                    try out.appendSlice(alloc, ",\"completion\":\"");
                    try out.appendSlice(alloc, pass26_recursive_descriptor.DescriptorCompletion.name(cp));
                    try out.append(alloc, '"');
                }
                if (node.descriptor_label) |dl| {
                    try out.appendSlice(alloc, ",\"descriptor\":\"");
                    try jsonEscapeAppend(out, alloc, dl);
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, ",\"fields\":");
                try appendTableFieldsJson(out, alloc, self.alloc, &node);
            }
            if (node.kind == .call) {
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
                if (node.call_shape_id) |csid| {
                    try out.appendSlice(alloc, ",\"call_shape_id\":");
                    try appendJsonInt(out, alloc, csid);
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
                    try out.appendSlice(alloc, ",\"shape_id\":");
                    try appendJsonInt(out, alloc, sid);
                }
                try out.appendSlice(alloc, ",\"variants\":");
                try appendEnumVariantsJson(out, alloc, &node);
            }
            if (node.kind == .pipeline) {
                if (node.pipeline_op) |pop| {
                    try out.appendSlice(alloc, ",\"pipeline_op\":\"");
                    try out.appendSlice(alloc, pop.name());
                    try out.append(alloc, '"');
                }
                if (node.hardware_lowerings.bits != 0) {
                    try out.appendSlice(alloc, ",\"hardware_lowerings\":");
                    try appendJsonInt(out, alloc, node.hardware_lowerings.bits);
                }
            }
            if (node.stable_id) |sid| {
                var hex: [16]u8 = undefined;
                try out.appendSlice(alloc, ",\"stable_id\":\"");
                try out.appendSlice(alloc, sid.formatHex(&hex));
                try out.append(alloc, '"');
            }
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"table_shapes\":[");
        var first_table = true;
        for (self.nodes.items) |node| {
            if (node.kind != .table_shape) continue;
            if (!first_table) try out.append(alloc, ',');
            first_table = false;
            const sc = if (node.storage_class) |s| types.storageClassName(s) else "dynamic";
            try out.appendSlice(alloc, "{\"name\":\"");
            try jsonEscapeAppend(out, alloc, node.name orelse "?");
            try out.appendSlice(alloc, "\",\"storage_class\":\"");
            try out.appendSlice(alloc, sc);
            try out.appendSlice(alloc, "\",\"scope\":\"");
            try out.appendSlice(alloc, if (node.name) |n| shapeScopeLabel(n) else "module");
            try out.appendSlice(alloc, "\",\"field_count\":");
            try appendJsonInt(out, alloc, node.field_count);
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_id\":");
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
            try appendTableFieldsJson(out, alloc, self.alloc, &node);
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"enum_shapes\":[");
        var first_enum = true;
        for (self.nodes.items) |node| {
            if (node.kind != .enum_shape) continue;
            if (!first_enum) try out.append(alloc, ',');
            first_enum = false;
            try out.appendSlice(alloc, "{\"name\":\"");
            try jsonEscapeAppend(out, alloc, node.name orelse "?");
            try out.appendSlice(alloc, "\",\"variant_count\":");
            try appendJsonInt(out, alloc, node.field_count);
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_id\":");
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
        for (self.nodes.items) |node| {
            if (node.kind != .call) continue;
            if (!first_call) try out.append(alloc, ',');
            first_call = false;
            try out.appendSlice(alloc, "{\"name\":\"");
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
            if (node.call_shape_id) |csid| {
                try out.appendSlice(alloc, ",\"call_shape_id\":");
                try appendJsonInt(out, alloc, csid);
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
                self.countKind(.call),
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
    try std.testing.expect(mod_id.isValid());
    try std.testing.expectEqual(@as(usize, 4), g.nodes.items.len); // module + func + 2 params
    const add_id = g.findByName("add") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(.func, g.get(add_id).?.kind);
}

test "semantic_graph: moduleFunctionEmitOrder callees before callers" {
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
    var lex = Lexer.init(src, "order.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&module, "order.duo");

    const names = [_][]const u8{ "helper", "main" };
    const order = try g.moduleFunctionEmitOrder(alloc, &names);
    defer alloc.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings("helper", order[0]);
    try std.testing.expectEqualStrings("main", order[1]);
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
    try std.testing.expect(std.mem.indexOf(u8, s, "\"table_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"enum_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Color\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"storage_class\":\"native\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"shape_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"why\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"fields\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "native C scalars") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"stable_id\"") != null);
}

test "semantic_graph: StableId is deterministic for same module path" {
    const a = StableId.compute("examples/foo.duo", .func, "main", 0);
    const b = StableId.compute("examples/foo.duo", .func, "main", 0);
    try std.testing.expectEqual(a.hash, b.hash);
    const c = StableId.compute("examples/foo.duo", .func, "main", 1);
    try std.testing.expect(a.hash != c.hash);
}

test "semantic_graph: liftFunctionBindings creates inline table_shape" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Point = { x: f64, y: f64 }
        \\function main()
        \\  local p: Point = { x = 1.0, y = 2.0 }
        \\  pt2: { x: f64, y: f64 } = { x = 3.0, y = 4.0 }
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.duo");
    const inline_shape = g.findTableShape("main::pt2@shape") orelse return error.TestExpectedEqual;
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

test "semantic_graph: pass26 pure alias interning shares fingerprint and slot" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\PairA = { first: i32, second: str }
        \\PairB = { first: i32, second: str }
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    g.module_path = "test.duo";
    _ = try g.liftModuleFull(&module, "test.duo");
    const pair_a = g.findTableShape("PairA") orelse return error.TestExpectedEqual;
    const pair_b = g.findTableShape("PairB") orelse return error.TestExpectedEqual;
    try std.testing.expect(pair_a.semantic_fingerprint != null);
    try std.testing.expectEqual(pair_a.semantic_fingerprint, pair_b.semantic_fingerprint);
    try std.testing.expect(pair_a.declaration_identity != null);
    try std.testing.expect(pair_b.declaration_identity != null);
    try std.testing.expect(pair_a.declaration_identity != pair_b.declaration_identity);
    try std.testing.expect(pair_a.intern_slot != null);
    try std.testing.expectEqual(pair_a.intern_slot, pair_b.intern_slot);
    try std.testing.expect(pair_a.recursion == .none);
    try std.testing.expect(pair_a.completion == .complete);
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

test "semantic_graph: pipeline operator lifts pipeline nodes" {
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
    try std.testing.expectEqual(@as(usize, 1), g.countKind(.pipeline));
}

test "semantic_graph: func_decls index supports effect inference" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\@pure
        \\fun add(a: i64, b: i64): i64
        \\  a + b
        \\end
        \\fun main()
        \\  add(1, 2)
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&module, "test.duo");
    const fd = g.func_decls.get("add") orelse return error.TestExpectedEqual;
    const effects = semantic_algebra.effectSetFromAttributes(fd.attributes);
    try std.testing.expect(effects.contains(.pure));
}

test "semantic_graph: usersOf finds use edges" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const a = try g.addNode(.{ .kind = .local, .span = .{ .file = "t", .start = 0, .end = 1 }, .name = "a" });
    const b = try g.addNode(.{ .kind = .call, .span = .{ .file = "t", .start = 2, .end = 3 } });
    try g.addEdge(.{ .from = b, .to = a, .kind = .use });
    var users: std.ArrayListUnmanaged(NodeId) = .empty;
    defer users.deinit(g.alloc);
    try g.usersOf(a, &users);
    try std.testing.expectEqual(@as(usize, 1), users.items.len);
    try std.testing.expectEqual(b.index, users.items[0].index);
}
