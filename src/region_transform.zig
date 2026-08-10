//! Pass 22 WS21 — bounded region-graph transforms → DNIR mutation.
//!
//! Transforms: const-return call inline; schedule-validated const binop fusion.
const std = @import("std");
const dnir = @import("duo_native_ir.zig");
const region_graph = @import("region_graph.zig");
const region_schedule = @import("region_schedule.zig");

pub const TransformKind = enum {
    inline_const_return,
    fuse_const_binop,
};

pub const TransformRecord = struct {
    kind: TransformKind,
    caller: []const u8,
    callee: []const u8 = "",
    region_node_id: u32 = 0,
    const_value: i64 = 0,
    binop: dnir.BinOpTag = .add,
    result_temp: u32 = 0,
};

pub const ModuleTransformReport = struct {
    const_inlines: u32 = 0,
    const_binop_fusions: u32 = 0,
    dead_const_pruned: u32 = 0,
};

pub const Error = error{
    OutOfMemory,
    CalleeNotFound,
    CallerNotFound,
    ScheduleCycle,
};

/// If `callee` is a zero-arg function that returns a constant i64, return that value.
pub fn calleeConstI64Return(m: dnir.Module, callee: []const u8) ?i64 {
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, callee)) continue;
        if (f.params.len != 0) return null;
        if (f.blocks.len != 1) return null;
        // A SINGLE BLOCK IS NOT A SINGLE EXIT. DNIR keeps `br`/`br_if`/
        // `br_if_not` and several `ret`s inside one block, so `blocks.len == 1`
        // does not mean straight-line code. Returning the FIRST constant `ret`
        // therefore inlined the value of a branch that may never be taken:
        //
        //     f(): i64
        //         if 1 != 1 return 41 end
        //         9
        //     end
        //
        // `f` itself lowered correctly (the ARM64 for it branches and returns
        // 9), but every CALLER was folded to the literal 41 — `main` did not
        // even emit the call. Any guard clause returned its guard value
        // unconditionally, which is one of the most common shapes in the
        // language; the C backend was unaffected, so the two backends silently
        // disagreed. Found via examples/pass16_lexer_text_differential.duo.
        //
        // Fold only a function that is genuinely one straight line to one
        // constant exit: no control flow at all, exactly one `ret`, and that
        // `ret` carrying an i64 immediate.
        var found: ?i64 = null;
        for (f.blocks[0].instrs) |ins| {
            switch (ins.op) {
                .br, .br_if, .br_if_not => return null,
                .ret_record => return null,
                .ret => {
                    if (found != null) return null;
                    if (ins.lhs != .i64) return null;
                    found = ins.lhs.i64;
                },
                else => {},
            }
        }
        return found;
    }
    return null;
}

fn findFunction(m: dnir.Module, name: []const u8) ?dnir.Function {
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

fn findFunctionMut(m: *dnir.Module, name: []const u8) ?*dnir.Function {
    const funcs: []dnir.Function = @constCast(m.functions);
    for (funcs) |*f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

fn findInstrByResult(f: dnir.Function, result: u32) ?dnir.Instr {
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.result == result) return ins;
        }
    }
    return null;
}

fn findNodeByTemp(region: *const region_graph.Region, temp: u32) ?region_graph.Node {
    for (region.nodes) |n| {
        if (n.dnir_temp == temp) return n;
    }
    return null;
}

fn buildConstSlotMap(
    alloc: std.mem.Allocator,
    f: dnir.Function,
) Error!std.AutoHashMapUnmanaged(u32, i64) {
    var map: std.AutoHashMapUnmanaged(u32, i64) = .empty;
    errdefer map.deinit(alloc);

    // Constant propagation is only sound for a slot that is assigned ONCE.
    // A loop-carried variable is initialised from a literal and then reassigned
    // inside the body; recording just the literal folds the body against the
    // entry value, so `i = i + 1` becomes `i = 2` and the loop never advances.
    // Count every definition first, then keep only the single-definition slots.
    var defs: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer defs.deinit(alloc);
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            const slot = switch (ins.op) {
                .@"const", .store_local => ins.result orelse continue,
                else => continue,
            };
            const gop = try defs.getOrPut(alloc, slot);
            gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
        }
    }

    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op != .@"const" and ins.op != .store_local) continue;
            if (ins.op == .@"const" and ins.ty != .i64) continue;
            if (ins.lhs != .i64) continue;
            const slot = ins.result orelse continue;
            if ((defs.get(slot) orelse 0) != 1) continue;
            try map.put(alloc, slot, ins.lhs.i64);
        }
    }
    return map;
}

fn buildConstTempMap(
    alloc: std.mem.Allocator,
    f: dnir.Function,
) Error!std.AutoHashMapUnmanaged(u32, i64) {
    return buildConstSlotMap(alloc, f);
}

fn resolveConstOperand(v: dnir.Value, const_map: *const std.AutoHashMapUnmanaged(u32, i64)) ?i64 {
    return switch (v) {
        .i64 => |n| n,
        .temp, .local => |slot| const_map.get(slot),
        else => null,
    };
}

/// Fold two constants the way the TARGET would, or decline.
///
/// This panicked the whole compiler on `a: i64 = <i64 max>  b = a + 1`:
/// Zig's `+` traps on signed overflow, so a program whose only crime was
/// reaching the top of the range took `thread panic: integer overflow` inside
/// a fold that exists to make it faster. The run-time answer wraps — the C
/// backend prints the wrapped value and so does the ARM64 `add` this fold is
/// standing in for — so the wrapping operators are not a workaround here, they
/// are the semantics being modelled.
///
/// `@divTrunc`/`@rem` still trap on `minInt / -1`, whose true quotient is not
/// representable. That one is declined rather than wrapped: there is no
/// answer to model.
fn evalConstBinop(op: dnir.BinOpTag, a: i64, b: i64) ?i64 {
    return switch (op) {
        .add => a +% b,
        .sub => a -% b,
        .mul => a *% b,
        .div => if (b == 0 or (b == -1 and a == std.math.minInt(i64))) null else @divTrunc(a, b),
        .mod => if (b == 0 or (b == -1 and a == std.math.minInt(i64))) null else @rem(a, b),
        else => null,
    };
}

fn operandScheduleOk(
    region: *const region_graph.Region,
    schedule: []const region_schedule.ScheduleSlot,
    binop_node_id: u32,
    v: dnir.Value,
) bool {
    return switch (v) {
        .i64 => true,
        .temp, .local => |slot| blk: {
            const prod = findNodeByTemp(region, slot) orelse break :blk false;
            break :blk region_schedule.orderedBefore(schedule, prod.id, binop_node_id);
        },
        else => false,
    };
}

/// Discover const-return inline sites from region call nodes + DNIR facts.
pub fn findConstReturnInlines(
    alloc: std.mem.Allocator,
    regions: []const region_graph.Region,
    m: dnir.Module,
) Error![]TransformRecord {
    var out: std.ArrayListUnmanaged(TransformRecord) = .empty;
    errdefer out.deinit(alloc);

    for (regions) |region| {
        for (region.nodes) |node| {
            if (node.kind != .call) continue;
            if (node.graph_stable_id == null) continue;
            const callee = node.callee orelse continue;
            const value = calleeConstI64Return(m, callee) orelse continue;
            try out.append(alloc, .{
                .kind = .inline_const_return,
                .caller = region.func_name,
                .callee = callee,
                .region_node_id = node.id,
                .const_value = value,
            });
        }
    }
    return try out.toOwnedSlice(alloc);
}

/// Discover integer binops foldable to constants; schedule validates temp operands.
pub fn findConstBinopFusions(
    alloc: std.mem.Allocator,
    regions: []const region_graph.Region,
    m: dnir.Module,
) Error![]TransformRecord {
    var out: std.ArrayListUnmanaged(TransformRecord) = .empty;
    errdefer out.deinit(alloc);

    for (regions) |region| {
        const func = findFunction(m, region.func_name) orelse continue;
        var const_map = try buildConstSlotMap(alloc, func);
        defer const_map.deinit(alloc);

        const schedule = try region_schedule.buildRegionSchedule(alloc, &region);
        defer alloc.free(schedule);

        for (region.nodes) |node| {
            if (node.kind != .binop) continue;
            const rt = node.dnir_temp orelse continue;
            const ins = findInstrByResult(func, rt) orelse continue;
            if (ins.op != .binop or ins.ty == .f64) continue;
            const a = resolveConstOperand(ins.lhs, &const_map) orelse continue;
            const b = resolveConstOperand(ins.rhs, &const_map) orelse continue;
            const fused = evalConstBinop(ins.binop, a, b) orelse continue;
            if (!operandScheduleOk(&region, schedule, node.id, ins.lhs)) continue;
            if (!operandScheduleOk(&region, schedule, node.id, ins.rhs)) continue;
            try out.append(alloc, .{
                .kind = .fuse_const_binop,
                .caller = region.func_name,
                .region_node_id = node.id,
                .binop = ins.binop,
                .result_temp = rt,
                .const_value = fused,
            });
        }
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeTransformRecords(alloc: std.mem.Allocator, records: []TransformRecord) void {
    alloc.free(records);
}

fn functionHasCallTo(f: *const dnir.Function, callee: []const u8) bool {
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, callee)) return true;
        }
    }
    return false;
}

fn functionHasBinop(f: *const dnir.Function, op: dnir.BinOpTag) bool {
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .binop and ins.binop == op and ins.ty != .f64) return true;
        }
    }
    return false;
}

/// Replace a direct call with a constant realization when its result is known.
pub fn applyConstReturnInline(
    alloc: std.mem.Allocator,
    caller: *dnir.Function,
    callee: []const u8,
    value: i64,
) Error!bool {
    var changed = false;
    const blocks: []dnir.Block = @constCast(caller.blocks);
    for (blocks) |*block| {
        var new_instrs: std.ArrayListUnmanaged(dnir.Instr) = .empty;
        errdefer new_instrs.deinit(alloc);
        var block_changed = false;

        for (block.instrs) |ins| {
            if (ins.op == .call_direct and
                std.mem.eql(u8, ins.callee, callee) and
                ins.lhs == .void and
                ins.result != null)
            {
                try new_instrs.append(alloc, .{
                    .op = .@"const",
                    .relation = ins.relation,
                    .application = ins.application,
                    .value = ins.value,
                    .result = ins.result,
                    .lhs = .{ .i64 = value },
                    .ty = .i64,
                });
                block_changed = true;
                continue;
            }
            try new_instrs.append(alloc, ins);
        }

        if (block_changed) {
            const owned = try new_instrs.toOwnedSlice(alloc);
            const old = block.instrs;
            block.instrs = owned;
            alloc.free(old);
            changed = true;
        } else {
            new_instrs.deinit(alloc);
        }
    }
    return changed;
}

/// Replace a foldable integer application with a constant realization.
pub fn applyConstBinopFusion(
    alloc: std.mem.Allocator,
    caller: *dnir.Function,
    result_temp: u32,
    value: i64,
) Error!bool {
    var changed = false;
    const blocks: []dnir.Block = @constCast(caller.blocks);
    for (blocks) |*block| {
        var new_instrs: std.ArrayListUnmanaged(dnir.Instr) = .empty;
        errdefer new_instrs.deinit(alloc);
        var block_changed = false;

        for (block.instrs) |ins| {
            if (ins.op == .binop and ins.result == result_temp and ins.ty != .f64) {
                try new_instrs.append(alloc, .{
                    .op = .@"const",
                    .relation = ins.relation,
                    .application = ins.application,
                    .value = ins.value,
                    .result = result_temp,
                    .lhs = .{ .i64 = value },
                    .ty = .i64,
                });
                block_changed = true;
                continue;
            }
            try new_instrs.append(alloc, ins);
        }

        if (block_changed) {
            const owned = try new_instrs.toOwnedSlice(alloc);
            const old = block.instrs;
            block.instrs = owned;
            alloc.free(old);
            changed = true;
        } else {
            new_instrs.deinit(alloc);
        }
    }
    return changed;
}

/// Apply all const-return inlines discovered from the region graph.
pub fn applyModuleConstReturnInlines(
    alloc: std.mem.Allocator,
    m: *dnir.Module,
    regions: []const region_graph.Region,
) Error!u32 {
    const candidates = try findConstReturnInlines(alloc, regions, m.*);
    defer freeTransformRecords(alloc, candidates);

    var applied: u32 = 0;
    for (candidates) |c| {
        const caller = findFunctionMut(m, c.caller) orelse return error.CallerNotFound;
        if (try applyConstReturnInline(alloc, caller, c.callee, c.const_value)) {
            applied += 1;
        }
    }
    return applied;
}

/// Apply schedule-validated const binop fusions discovered from the region graph.
pub fn applyModuleConstBinopFusions(
    alloc: std.mem.Allocator,
    m: *dnir.Module,
    regions: []const region_graph.Region,
) Error!u32 {
    const candidates = try findConstBinopFusions(alloc, regions, m.*);
    defer freeTransformRecords(alloc, candidates);

    var applied: u32 = 0;
    for (candidates) |c| {
        const caller = findFunctionMut(m, c.caller) orelse return error.CallerNotFound;
        if (try applyConstBinopFusion(alloc, caller, c.result_temp, c.const_value)) {
            applied += 1;
        }
    }
    return applied;
}

fn valueUsesSlot(v: dnir.Value, slot: u32) bool {
    return switch (v) {
        .temp, .local => |s| s == slot,
        else => false,
    };
}

fn tempUseCount(f: dnir.Function, slot: u32) u32 {
    var n: u32 = 0;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (valueUsesSlot(ins.lhs, slot)) n += 1;
            if (valueUsesSlot(ins.rhs, slot)) n += 1;
            if (valueUsesSlot(ins.third, slot)) n += 1;
        }
    }
    return n;
}

/// Remove integer constant producers whose result temp has zero uses.
pub fn pruneDeadConstProducers(
    alloc: std.mem.Allocator,
    caller: *dnir.Function,
) Error!u32 {
    var pruned: u32 = 0;
    const blocks: []dnir.Block = @constCast(caller.blocks);
    for (blocks) |*block| {
        var new_instrs: std.ArrayListUnmanaged(dnir.Instr) = .empty;
        errdefer new_instrs.deinit(alloc);
        var block_changed = false;

        for (block.instrs) |ins| {
            if (ins.op == .@"const" and ins.ty == .i64) {
                const rt = ins.result orelse {
                    try new_instrs.append(alloc, ins);
                    continue;
                };
                if (tempUseCount(caller.*, rt) == 0) {
                    pruned += 1;
                    block_changed = true;
                    continue;
                }
            }
            try new_instrs.append(alloc, ins);
        }

        if (block_changed) {
            const owned = try new_instrs.toOwnedSlice(alloc);
            const old = block.instrs;
            block.instrs = owned;
            alloc.free(old);
        } else {
            new_instrs.deinit(alloc);
        }
    }
    return pruned;
}

pub fn applyModuleDeadConstPrune(
    alloc: std.mem.Allocator,
    m: *dnir.Module,
) Error!u32 {
    var pruned: u32 = 0;
    const funcs: []dnir.Function = @constCast(m.functions);
    for (funcs) |*func| {
        pruned += try pruneDeadConstProducers(alloc, func);
    }
    return pruned;
}

/// Run bounded region-graph transforms in dependency-safe order.
pub fn applyModuleRegionTransforms(
    alloc: std.mem.Allocator,
    m: *dnir.Module,
    regions: []const region_graph.Region,
) Error!ModuleTransformReport {
    const inlines = try applyModuleConstReturnInlines(alloc, m, regions);
    const fusions = try applyModuleConstBinopFusions(alloc, m, regions);
    const pruned = try applyModuleDeadConstPrune(alloc, m);
    return .{
        .const_inlines = inlines,
        .const_binop_fusions = fusions,
        .dead_const_pruned = pruned,
    };
}

test "region_transform: inline const-return helper at region call site" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    const semantic_graph = @import("semantic_graph.zig");

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
    var lex = Lexer.init(src, "inline.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "inline.duo");
    var m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);
    const regions = try region_graph.buildModuleRegions(alloc, m, &g);
    defer region_graph.freeModuleRegions(alloc, regions);

    const candidates = try findConstReturnInlines(alloc, regions, m);
    defer freeTransformRecords(alloc, candidates);
    try std.testing.expectEqual(@as(usize, 1), candidates.len);
    try std.testing.expectEqual(@as(i64, 1), candidates[0].const_value);

    const main_before = findFunctionMut(&m, "main") orelse return error.TestExpectedEqual;
    try std.testing.expect(functionHasCallTo(main_before, "helper"));
    const mutable_blocks: []dnir.Block = @constCast(main_before.blocks);
    const mutable_instructions: []dnir.Instr = @constCast(mutable_blocks[0].instrs);
    for (mutable_instructions) |*instruction| {
        if (instruction.op != .call_direct) continue;
        instruction.relation = 11;
        instruction.application = 22;
        instruction.value = 33;
    }

    const applied = try applyModuleConstReturnInlines(alloc, &m, regions);
    try std.testing.expectEqual(@as(u32, 1), applied);

    const main_after = findFunctionMut(&m, "main") orelse return error.TestExpectedEqual;
    try std.testing.expect(!functionHasCallTo(main_after, "helper"));
    for (main_after.blocks[0].instrs) |instruction| {
        if (instruction.op != .@"const") continue;
        try std.testing.expectEqual(@as(?u64, 11), instruction.relation);
        try std.testing.expectEqual(@as(?u64, 22), instruction.application);
        try std.testing.expectEqual(@as(?u64, 33), instruction.value);
    }
}

test "region_transform: fuse const binop via region schedule" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    const semantic_graph = @import("semantic_graph.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    10 + 32
        \\end
    ;
    var lex = Lexer.init(src, "fuse.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "fuse.duo");
    var m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);
    const regions = try region_graph.buildModuleRegions(alloc, m, &g);
    defer region_graph.freeModuleRegions(alloc, regions);

    const main_before = findFunctionMut(&m, "main") orelse return error.TestExpectedEqual;
    try std.testing.expect(functionHasBinop(main_before, .add));

    const candidates = try findConstBinopFusions(alloc, regions, m);
    defer freeTransformRecords(alloc, candidates);
    try std.testing.expectEqual(@as(usize, 1), candidates.len);
    try std.testing.expectEqual(@as(i64, 42), candidates[0].const_value);

    const report = try applyModuleRegionTransforms(alloc, &m, regions);
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);

    const main_after = findFunctionMut(&m, "main") orelse return error.TestExpectedEqual;
    try std.testing.expect(!functionHasBinop(main_after, .add));
}

test "region_transform: fuse binop over const local slots" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    const semantic_graph = @import("semantic_graph.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    x = 10
        \\    y = 32
        \\    x + y
        \\end
    ;
    var lex = Lexer.init(src, "local_fuse.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "local_fuse.duo");
    var m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);
    const regions = try region_graph.buildModuleRegions(alloc, m, &g);
    defer region_graph.freeModuleRegions(alloc, regions);

    const candidates = try findConstBinopFusions(alloc, regions, m);
    defer freeTransformRecords(alloc, candidates);
    try std.testing.expectEqual(@as(usize, 1), candidates.len);
    try std.testing.expectEqual(@as(i64, 42), candidates[0].const_value);

    const report = try applyModuleRegionTransforms(alloc, &m, regions);
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);

    const main_after = findFunctionMut(&m, "main") orelse return error.TestExpectedEqual;
    try std.testing.expect(!functionHasBinop(main_after, .add));
}

test "region_transform: prune orphaned constant temps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var f = dnir.Function{
        .name = "dead",
        .ret = .i64,
        .blocks = &.{
            .{
                .instrs = &.{
                    .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 10 }, .ty = .i64 },
                    .{ .op = .@"const", .result = 2, .lhs = .{ .i64 = 32 }, .ty = .i64 },
                    .{ .op = .@"const", .result = 3, .lhs = .{ .i64 = 42 }, .ty = .i64 },
                    .{ .op = .ret, .lhs = .{ .temp = 3 } },
                },
            },
        },
    };

    const pruned = try pruneDeadConstProducers(alloc, &f);
    try std.testing.expectEqual(@as(u32, 2), pruned);
    try std.testing.expectEqual(@as(usize, 2), f.blocks[0].instrs.len);
    try std.testing.expect(f.blocks[0].instrs[0].op == .@"const");
    try std.testing.expectEqual(@as(i64, 42), f.blocks[0].instrs[0].lhs.i64);
    try std.testing.expect(f.blocks[0].instrs[1].op == .ret);
}
