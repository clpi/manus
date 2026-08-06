//! Pass 22 native gate proofs (§37 gates J–K partial; catalog invariants).
const std = @import("std");
const pass22_catalog = @import("pass22_catalog.zig");
const graph_query = @import("graph_query.zig");
const region_graph = @import("region_graph.zig");
const region_transform = @import("region_transform.zig");
const region_schedule = @import("region_schedule.zig");
const region_layout = @import("region_layout.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const dnir_lower = @import("dnir_lower.zig");
const dnir = @import("duo_native_ir.zig");
const semantic_graph = @import("semantic_graph.zig");
const realization = @import("realization.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub const GateError = error{ GateFailed };

pub fn validatePass22Catalog() GateError!void {
    if (!std.mem.eql(u8, pass22_catalog.SCHEMA_VERSION, "pass22-catalog-v0")) return error.GateFailed;
    if (pass22_catalog.workstreams.len != 17) return error.GateFailed;
    if (pass22_catalog.completion_gates.len != 12) return error.GateFailed;
}

/// Gate J — stable semantic identity preserved graph → region → DNIR.
pub fn proveGateIdentity(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = Lexer.init(src, "gatej.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatej.duo") catch return error.GateFailed;
    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    if (m.functions[0].graph_stable_id == null) return error.GateFailed;
    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);
    if (regions[0].func_stable_id == null) return error.GateFailed;
    const sid_graph = graph_query.stableIdOf(&g, "run") orelse return error.GateFailed;
    if (sid_graph != regions[0].func_stable_id.?) return error.GateFailed;
    if (sid_graph != m.functions[0].graph_stable_id.?) return error.GateFailed;
}

/// Gate M partial — record shape identity flows graph → DNIR → region `realizes_as`.
pub fn proveGateRecordLowering(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\@sealed
        \\alias Point = { x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "gatem.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatem.duo") catch return error.GateFailed;

    const repr = graph_query.representationForRecord(&g, "Point") orelse return error.GateFailed;
    if (repr.shape_id == null or repr.stable_id == null) return error.GateFailed;

    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    var point_rec: ?dnir.RecordDesc = null;
    for (m.records) |rec| {
        if (std.mem.eql(u8, rec.name, "Point")) point_rec = rec;
    }
    const rec = point_rec orelse return error.GateFailed;
    if (rec.shape_id != repr.shape_id) return error.GateFailed;
    if (rec.graph_stable_id != repr.stable_id) return error.GateFailed;

    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);
    region_graph.validateModuleRegions(regions, &g, m, alloc) catch return error.GateFailed;

    var plan = realization.buildDeferredFromGraph(alloc, &g, "gatem.duo") catch return error.GateFailed;
    defer plan.deinit(alloc);
    realization.commitModuleForTarget(alloc, &plan, "native") catch return error.GateFailed;
    region_graph.attachRealizationPlan(alloc, regions, &plan) catch return error.GateFailed;

    var saw_realizes_as = false;
    for (regions) |r| {
        if (region_graph.countRealizesAsEdges(&r) > 0) saw_realizes_as = true;
    }
    if (!saw_realizes_as) return error.GateFailed;

    var saw_record_node = false;
    for (regions) |r| {
        for (r.nodes) |node| {
            if (node.kind == .record and node.shape_id != null) saw_record_node = true;
        }
    }
    if (!saw_record_node) return error.GateFailed;
}

/// Gate M-REC layout partial — record shapes yield stack layout plans.
pub fn proveGateRecordLayout(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\@sealed
        \\alias Point = { x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "gatelayout.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatelayout.duo") catch return error.GateFailed;
    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    const layouts = region_layout.planModuleRecordLayouts(alloc, m) catch return error.GateFailed;
    defer region_layout.freeModuleRecordLayouts(alloc, layouts);
    if (layouts.len == 0) return error.GateFailed;
    var point_layout: ?region_layout.RecordLayout = null;
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, "Point")) point_layout = layout;
    }
    const pl = point_layout orelse return error.GateFailed;
    if (pl.size != 16 or pl.fields.len != 2) return error.GateFailed;
    if (pl.shape_id == null) return error.GateFailed;

    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);
    const frames = region_layout.planModuleRegionFrames(alloc, regions, layouts) catch return error.GateFailed;
    defer region_layout.freeModuleRegionFrames(alloc, frames);
    const main_frame = blk: {
        for (frames) |f| {
            if (std.mem.eql(u8, f.func_name, "main")) break :blk f;
        }
        return error.GateFailed;
    };
    if (main_frame.record_slots == 0 or main_frame.stack_bytes < 16) return error.GateFailed;
}

/// Gate M — hardware descriptors flow DNIR → region graph → schedule.
pub fn proveGateHardwareConsumption(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\main(): i64
        \\    @comp.hint.fence()
        \\    bits = @comp.bit.popcount(47)
        \\    if bits ~= 5 return 1 end
        \\    @comp.hint.fence()
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "gatehw.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatehw.duo") catch return error.GateFailed;

    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    if (m.hardware_tier != .scalar) return error.GateFailed;
    if (!dnir.moduleIsNativeDirectReady(m)) return error.GateFailed;

    const descs = graph_query.hardwareDescriptorsOfModule(alloc, m) catch return error.GateFailed;
    defer dnir_hardware.freeModuleDescriptors(alloc, descs);
    if (descs.len < 2) return error.GateFailed;
    var saw_fence_desc = false;
    var saw_pop_desc = false;
    for (descs) |d| {
        if (d.intrinsic == .fence and d.use_count >= 2) saw_fence_desc = true;
        if (d.intrinsic == .popcount and d.use_count >= 1) saw_pop_desc = true;
    }
    if (!saw_fence_desc or !saw_pop_desc) return error.GateFailed;

    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);
    if (!graph_query.hardwareTierConsistent(m, regions)) return error.GateFailed;

    const main_region = region_graph.findRegion(regions, "main") orelse return error.GateFailed;
    if (region_graph.countHardwareNodes(main_region) < 3) return error.GateFailed;
    if (region_graph.countHardwareNodesLabeled(main_region, "fence") < 2) return error.GateFailed;
    if (region_graph.countHardwareNodesLabeled(main_region, "popcount") < 1) return error.GateFailed;
    if (main_region.hardware_tier != .scalar) return error.GateFailed;

    const schedule = region_schedule.buildRegionSchedule(alloc, main_region) catch return error.GateFailed;
    defer alloc.free(schedule);
    if (schedule.len < 3) return error.GateFailed;

    var fence_ids: [2]?u32 = .{ null, null };
    var pop_id: ?u32 = null;
    for (main_region.nodes) |n| {
        if (n.kind != .hardware) continue;
        const label = n.label orelse continue;
        if (std.mem.eql(u8, label, "fence")) {
            if (fence_ids[0] == null) fence_ids[0] = n.id else if (fence_ids[1] == null) fence_ids[1] = n.id;
        } else if (std.mem.eql(u8, label, "popcount")) {
            pop_id = n.id;
        }
    }
    const f0 = fence_ids[0] orelse return error.GateFailed;
    const f1 = fence_ids[1] orelse return error.GateFailed;
    const pid = pop_id orelse return error.GateFailed;
    if (!region_schedule.orderedBefore(schedule, f0, pid)) return error.GateFailed;
    if (!region_schedule.orderedBefore(schedule, pid, f1)) return error.GateFailed;
}

/// Gate L — multiple legal representations until target-aware selection.
pub fn proveGateDeferredRealization(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\@sealed
        \\alias User = { id: i64, name: str }
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = Lexer.init(src, "gatel.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatel.duo") catch return error.GateFailed;

    var deferred = realization.buildDeferredFromGraph(alloc, &g, "gatel.duo") catch return error.GateFailed;
    defer deferred.deinit(alloc);
    if (deferred.variables.len == 0) return error.GateFailed;
    if (realization.legalCandidateCount(&deferred.variables[0]) < 2) return error.GateFailed;
    if (deferred.variables[0].selected_index != null) return error.GateFailed;

    var native_plan = realization.buildDeferredFromGraph(alloc, &g, "gatel.duo") catch return error.GateFailed;
    defer native_plan.deinit(alloc);
    realization.commitModuleForTarget(alloc, &native_plan, "native") catch return error.GateFailed;
    const native_sel = native_plan.variables[0].selected() orelse return error.GateFailed;
    if (!std.mem.eql(u8, native_sel.id, "repr.native_sealed")) return error.GateFailed;

    var wasm_plan = realization.buildDeferredFromGraph(alloc, &g, "gatel.duo") catch return error.GateFailed;
    defer wasm_plan.deinit(alloc);
    realization.commitModuleForTarget(alloc, &wasm_plan, "wasm32-wasi") catch return error.GateFailed;
    const wasm_sel = wasm_plan.variables[0].selected() orelse return error.GateFailed;
    if (!std.mem.eql(u8, wasm_sel.id, "repr.dynamic_table")) return error.GateFailed;
}

/// Gate K — graph-driven transform (emit order) is deterministic and callee-first.
pub fn proveGateGraphTransform(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\helper(): i64
        \\    1
        \\end
        \\main(): i64
        \\    helper()
        \\end
    ;
    var lex = Lexer.init(src, "gatek.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatek.duo") catch return error.GateFailed;
    const names = graph_query.eligibleFunctionNames(alloc, &mod) catch return error.GateFailed;
    defer alloc.free(names);
    const order = graph_query.functionEmitOrder(&g, alloc, names) catch return error.GateFailed;
    defer alloc.free(order);
    if (!std.mem.eql(u8, order[0], "helper")) return error.GateFailed;
    if (!std.mem.eql(u8, order[1], "main")) return error.GateFailed;
    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    if (!std.mem.eql(u8, m.functions[0].name, "helper")) return error.GateFailed;

    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);
    region_graph.validateModuleRegions(regions, &g, m, alloc) catch return error.GateFailed;
    const main_region = region_graph.findRegion(regions, "main") orelse return error.GateFailed;
    if (region_graph.countDirectCallees(main_region) != 1) return error.GateFailed;

    var m_mut = m;
    const applied = region_transform.applyModuleConstReturnInlines(alloc, &m_mut, regions) catch return error.GateFailed;
    if (applied != 1) return error.GateFailed;
    const main_fn = blk: {
        for (m_mut.functions) |*f| {
            if (std.mem.eql(u8, f.name, "main")) break :blk f;
        }
        return error.GateFailed;
    };
    for (main_fn.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .call_direct and ins.callee.len > 0 and std.mem.eql(u8, ins.callee, "helper")) {
                return error.GateFailed;
            }
        }
    }
}

/// Gate N partial — `orders_before` region edges materialize as explicit schedule slots.
pub fn proveGateScheduleSelection(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\helper(): i64
        \\    1
        \\end
        \\main(): i64
        \\    helper()
        \\end
    ;
    var lex = Lexer.init(src, "gaten.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gaten.duo") catch return error.GateFailed;
    const m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);

    const schedules = region_schedule.buildModuleSchedules(alloc, regions) catch return error.GateFailed;
    defer region_schedule.freeModuleSchedules(alloc, schedules);
    if (schedules.len != 2) return error.GateFailed;

    const main_region = region_graph.findRegion(regions, "main") orelse return error.GateFailed;
    const main_sched = blk: {
        for (schedules) |s| {
            if (std.mem.eql(u8, s.func_name, "main")) break :blk s.slots;
        }
        return error.GateFailed;
    };
    if (main_sched.len < 2) return error.GateFailed;

    var call_id: ?u32 = null;
    var ret_id: ?u32 = null;
    for (main_region.nodes) |n| {
        if (n.kind == .call) call_id = n.id;
        if (n.kind == .ret) ret_id = n.id;
    }
    const cid = call_id orelse return error.GateFailed;
    const rid = ret_id orelse return error.GateFailed;
    if (!region_schedule.orderedBefore(main_sched, cid, rid)) return error.GateFailed;
}

/// Gate K extension — schedule-validated const binop fusion removes integer binops.
pub fn proveGateConstBinopFusion(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\main(): i64
        \\    10 + 32
        \\end
    ;
    var lex = Lexer.init(src, "gatekf.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatekf.duo") catch return error.GateFailed;
    var m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);

    const report = region_transform.applyModuleRegionTransforms(alloc, &m, regions) catch return error.GateFailed;
    if (report.const_binop_fusions != 1) return error.GateFailed;

    const main_fn = blk: {
        for (m.functions) |*f| {
            if (std.mem.eql(u8, f.name, "main")) break :blk f;
        }
        return error.GateFailed;
    };
    for (main_fn.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .binop and ins.binop == .add and ins.ty != .f64) return error.GateFailed;
        }
    }
}

/// Gate K extension — const locals fold through schedule-validated binop fusion.
pub fn proveGateLocalConstBinopFusion(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\main(): i64
        \\    x = 10
        \\    y = 32
        \\    x + y
        \\end
    ;
    var lex = Lexer.init(src, "gatekl.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = g.liftModuleWithCalls(&mod, "gatekl.duo") catch return error.GateFailed;
    var m = dnir_lower.lowerModuleWithGraph(alloc, &mod, &g) catch return error.GateFailed;
    const regions = region_graph.buildModuleRegions(alloc, m, &g) catch return error.GateFailed;
    defer region_graph.freeModuleRegions(alloc, regions);

    const report = region_transform.applyModuleRegionTransforms(alloc, &m, regions) catch return error.GateFailed;
    if (report.const_binop_fusions != 1) return error.GateFailed;

    const main_fn = blk: {
        for (m.functions) |*f| {
            if (std.mem.eql(u8, f.name, "main")) break :blk f;
        }
        return error.GateFailed;
    };
    for (main_fn.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .binop and ins.binop == .add and ins.ty != .f64) return error.GateFailed;
        }
    }
}

pub fn validatePass22Gate() GateError!void {
    try validatePass22Catalog();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try proveGateIdentity(arena.allocator());
    try proveGateGraphTransform(arena.allocator());
    try proveGateConstBinopFusion(arena.allocator());
    try proveGateLocalConstBinopFusion(arena.allocator());
    try proveGateDeferredRealization(arena.allocator());
    try proveGateRecordLowering(arena.allocator());
    try proveGateRecordLayout(arena.allocator());
    try proveGateHardwareConsumption(arena.allocator());
    try proveGateScheduleSelection(arena.allocator());
}

test "pass22_gate: catalog + gates J/K/L/M/M-LAY/M-HW/N" {
    try validatePass22Gate();
}
