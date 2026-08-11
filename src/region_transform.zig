//! DNIR transformations selected from physical coordinates and dependencies.
const std = @import("std");
const dnir = @import("duo_native_ir.zig");
const region_graph = @import("region_graph.zig");
const semantic_graph = @import("semantic_graph.zig");

pub const TransformRecord = struct {
    function: u32,
    coordinate: u32,
    const_value: i64,
};

pub const ModuleTransformReport = struct {
    const_binop_fusions: u32 = 0,
    dead_const_pruned: u32 = 0,
};

pub const Error = error{
    OutOfMemory,
    ResidencyMismatch,
    CoordinateOverflow,
};

fn requireResidency(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error!void {
    region_graph.validateModuleProjection(alloc, projection, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CoordinateOverflow => return error.CoordinateOverflow,
        else => return error.ResidencyMismatch,
    };
}

const ConstantOrigin = struct {
    coordinate: u32,
    value: i64,
};

fn resolveConstOperand(
    region: *const region_graph.Region,
    consumer: u32,
    value: dnir.Value,
    constants: *const std.AutoHashMapUnmanaged(u32, ConstantOrigin),
) ?i64 {
    return switch (value) {
        .i64 => |number| number,
        .temp, .local => |slot| blk: {
            const origin = constants.get(slot) orelse break :blk null;
            const producer = region_graph.dependencyProducer(region, slot, consumer) orelse
                break :blk null;
            if (producer != origin.coordinate or producer >= consumer) break :blk null;
            break :blk origin.value;
        },
        else => null,
    };
}

fn updateConstantOrigin(
    alloc: std.mem.Allocator,
    constants: *std.AutoHashMapUnmanaged(u32, ConstantOrigin),
    instruction: dnir.Instr,
    coordinate: u32,
) Error!void {
    const slot = dnir.definition(instruction) orelse return;
    const value = switch (instruction.op) {
        .@"const" => if (instruction.ty == .i64 and instruction.lhs == .i64)
            instruction.lhs.i64
        else
            null,
        .store_local => if (instruction.lhs == .i64) instruction.lhs.i64 else null,
        else => null,
    };
    if (value) |number| {
        try constants.put(alloc, slot, .{ .coordinate = coordinate, .value = number });
    } else {
        _ = constants.remove(slot);
    }
}

fn evalConstBinop(op: dnir.BinOpTag, left: i64, right: i64) ?i64 {
    return switch (op) {
        .add => left +% right,
        .sub => left -% right,
        .mul => left *% right,
        .div => if (right == 0 or (right == -1 and left == std.math.minInt(i64)))
            null
        else
            @divTrunc(left, right),
        .mod => if (right == 0 or (right == -1 and left == std.math.minInt(i64)))
            null
        else
            @rem(left, right),
        else => null,
    };
}

fn applicationFactsPresent(instruction: dnir.Instr) bool {
    return instruction.relation != null or instruction.application != null or
        instruction.value != null or instruction.subject != null or
        instruction.realization_start != null;
}

fn functionHasApplicationLineage(function: *const dnir.Function) bool {
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (applicationFactsPresent(instruction)) return true;
        }
    }
    return false;
}

fn hasControlSplit(function: dnir.Function) bool {
    if (function.blocks.len != 1) return true;
    for (function.blocks[0].instrs) |instruction| {
        if (instruction.op == .br) return true;
    }
    return false;
}

fn collectConstBinopFusions(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    var records: std.ArrayListUnmanaged(TransformRecord) = .empty;
    errdefer records.deinit(alloc);

    for (module.functions, projection.regions, 0..) |function, region, function_index| {
        if (functionHasApplicationLineage(&function) or hasControlSplit(function)) continue;
        var constants: std.AutoHashMapUnmanaged(u32, ConstantOrigin) = .empty;
        defer constants.deinit(alloc);

        var coordinate: u32 = 1;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .binop and instruction.ty != .f64 and
                !applicationFactsPresent(instruction) and instruction.result != null)
            {
                const left = resolveConstOperand(
                    &region,
                    coordinate,
                    instruction.lhs,
                    &constants,
                );
                const right = resolveConstOperand(
                    &region,
                    coordinate,
                    instruction.rhs,
                    &constants,
                );
                const fused = if (left != null and right != null)
                    evalConstBinop(instruction.binop, left.?, right.?)
                else
                    null;
                if (fused) |value| {
                    try records.append(alloc, .{
                        .function = @intCast(function_index),
                        .coordinate = coordinate,
                        .const_value = value,
                    });
                }
            }
            try updateConstantOrigin(alloc, &constants, instruction, coordinate);
            coordinate = std.math.add(u32, coordinate, 1) catch
                return error.CoordinateOverflow;
        }
    }
    return try records.toOwnedSlice(alloc);
}

pub fn findConstBinopFusions(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    try requireResidency(alloc, projection, module);
    return collectConstBinopFusions(alloc, projection, module);
}

pub fn freeTransformRecords(alloc: std.mem.Allocator, records: []TransformRecord) void {
    alloc.free(records);
}

const InstructionLocation = struct {
    block: usize,
    instruction: usize,
};

fn locateInstruction(function: dnir.Function, target: u32) ?InstructionLocation {
    var coordinate: u32 = 1;
    for (function.blocks, 0..) |block, block_index| {
        for (block.instrs, 0..) |_, instruction_index| {
            if (coordinate == target) return .{
                .block = block_index,
                .instruction = instruction_index,
            };
            coordinate = std.math.add(u32, coordinate, 1) catch return null;
        }
    }
    return null;
}

pub fn applyConstBinopFusion(
    alloc: std.mem.Allocator,
    function: *dnir.Function,
    coordinate: u32,
    value: i64,
) Error!bool {
    if (functionHasApplicationLineage(function)) return false;
    const location = locateInstruction(function.*, coordinate) orelse return false;
    const blocks: []dnir.Block = @constCast(function.blocks);
    const block = &blocks[location.block];
    const selected = block.instrs[location.instruction];
    if (selected.op != .binop or applicationFactsPresent(selected) or
        selected.ty == .f64 or selected.result == null)
    {
        return false;
    }

    const owned = try alloc.dupe(dnir.Instr, block.instrs);
    owned[location.instruction] = .{
        .op = .@"const",
        .result = selected.result,
        .lhs = .{ .i64 = value },
        .ty = .i64,
    };
    dnir.deinitInstr(alloc, selected);
    const old = block.instrs;
    block.instrs = owned;
    alloc.free(old);
    return true;
}

fn applyModuleConstBinopFusionsValidated(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    const records = try collectConstBinopFusions(alloc, projection, module.*);
    defer freeTransformRecords(alloc, records);

    const functions: []dnir.Function = @constCast(module.functions);
    var applied: u32 = 0;
    for (records) |record| {
        if (record.function >= functions.len) return error.ResidencyMismatch;
        if (try applyConstBinopFusion(
            alloc,
            &functions[record.function],
            record.coordinate,
            record.const_value,
        )) {
            applied += 1;
        }
    }
    return applied;
}

pub fn applyModuleConstBinopFusions(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    try requireResidency(alloc, projection, module.*);
    return applyModuleConstBinopFusionsValidated(alloc, module, projection);
}

fn valueUsesSlot(value: dnir.Value, slot: u32) bool {
    return switch (value) {
        .temp, .local => |candidate| candidate == slot,
        else => false,
    };
}

fn tempUseCount(function: dnir.Function, slot: u32) u32 {
    var count: u32 = 0;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .ret_record and instruction.vals.len != 0) {
                for (instruction.vals) |value| {
                    if (valueUsesSlot(value, slot)) count += 1;
                }
            } else {
                if (valueUsesSlot(instruction.lhs, slot)) count += 1;
                if (valueUsesSlot(instruction.rhs, slot)) count += 1;
                if (valueUsesSlot(instruction.third, slot)) count += 1;
            }
        }
    }
    return count;
}

pub fn pruneDeadConstProducers(
    alloc: std.mem.Allocator,
    function: *dnir.Function,
) Error!u32 {
    // Positional application lineage prevents deletion until transformations
    // have their own exact graph witness.
    if (functionHasApplicationLineage(function)) return 0;
    var pruned: u32 = 0;
    const blocks: []dnir.Block = @constCast(function.blocks);
    for (blocks) |*block| {
        var instructions: std.ArrayListUnmanaged(dnir.Instr) = .empty;
        errdefer instructions.deinit(alloc);
        var block_changed = false;

        for (block.instrs) |instruction| {
            if (instruction.op == .@"const" and instruction.ty == .i64) {
                const result = instruction.result orelse {
                    try instructions.append(alloc, instruction);
                    continue;
                };
                if (tempUseCount(function.*, result) == 0) {
                    pruned += 1;
                    block_changed = true;
                    continue;
                }
            }
            try instructions.append(alloc, instruction);
        }

        if (!block_changed) {
            instructions.deinit(alloc);
            continue;
        }
        const owned = try instructions.toOwnedSlice(alloc);
        const old = block.instrs;
        for (old) |instruction| {
            if (instruction.op != .@"const" or instruction.ty != .i64) continue;
            const result = instruction.result orelse continue;
            if (tempUseCount(function.*, result) == 0) dnir.deinitInstr(alloc, instruction);
        }
        block.instrs = owned;
        alloc.free(old);
    }
    return pruned;
}

pub fn applyModuleDeadConstPrune(alloc: std.mem.Allocator, module: *dnir.Module) Error!u32 {
    var pruned: u32 = 0;
    const functions: []dnir.Function = @constCast(module.functions);
    for (functions) |*function| pruned += try pruneDeadConstProducers(alloc, function);
    return pruned;
}

fn applyModuleRegionTransformsValidated(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!ModuleTransformReport {
    const fusions = try applyModuleConstBinopFusionsValidated(alloc, module, projection);
    const pruned = try applyModuleDeadConstPrune(alloc, module);
    return .{
        .const_binop_fusions = fusions,
        .dead_const_pruned = pruned,
    };
}

pub fn applyModuleRegionTransforms(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!ModuleTransformReport {
    try requireResidency(alloc, projection, module.*);
    return applyModuleRegionTransformsValidated(alloc, module, projection);
}

pub fn applyModuleRegionTransformsWithGraph(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
    graph: *const semantic_graph.SemanticGraph,
) Error!ModuleTransformReport {
    region_graph.validateModuleRegions(alloc, projection, graph, module.*) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CoordinateOverflow => return error.CoordinateOverflow,
        else => return error.ResidencyMismatch,
    };
    return applyModuleRegionTransformsValidated(alloc, module, projection);
}

fn functionHasBinop(function: *const dnir.Function, op: dnir.BinOpTag) bool {
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .binop and instruction.binop == op and instruction.ty != .f64) {
                return true;
            }
        }
    }
    return false;
}

test "region_transform: folds constants from physical coordinates and dependencies" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    x = 10
        \\    y = 32
        \\    x + y
    ;
    var lexer = Lexer.init(source, "region-transform.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    const ast_module = try parser.parse_module();
    var module = try dnir_lower.lowerModule(alloc, &ast_module);
    const projection = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, projection);

    const records = try findConstBinopFusions(alloc, projection, module);
    defer freeTransformRecords(alloc, records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(i64, 42), records[0].const_value);

    const report = try applyModuleRegionTransforms(alloc, &module, projection);
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);
    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expect(!functionHasBinop(&module.functions[0], .add));
}

test "region_transform: staged applications retain exact graph lineage" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const dnir_lower = @import("dnir_lower.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (subject: i64, left: i64, right: i64)
        \\    subject + left + right
        \\fold: i64 = ()
        \\    x = 10
        \\    y = 32
        \\    x + y
        \\main: i64 = ()
        \\    40:observe(1, 1)
    ;
    var lexer = Lexer.init(source, "checked-transform.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "checked-transform.id");
    var module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    const projection = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, projection);

    const Snapshot = struct {
        relation: semantic_graph.id,
        application: semantic_graph.id,
        value: semantic_graph.id,
        subject: ?semantic_graph.id,
        caller: semantic_graph.id,
        realization_start: u32,
    };
    var before: ?Snapshot = null;
    for (module.functions, projection.regions) |function, region| {
        var flattened: u32 = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application) |application| {
                    const realization_start = instruction.realization_start orelse
                        return error.TestExpectedEqual;
                    const start_coordinate = region_graph.instructionCoordinate(
                        &region,
                        realization_start,
                    ) orelse return error.TestExpectedEqual;
                    const call_coordinate = region_graph.instructionCoordinate(
                        &region,
                        flattened,
                    ) orelse return error.TestExpectedEqual;
                    try std.testing.expect(start_coordinate < call_coordinate);
                    before = .{
                        .relation = instruction.relation orelse return error.TestExpectedEqual,
                        .application = application,
                        .value = instruction.value orelse return error.TestExpectedEqual,
                        .subject = instruction.subject,
                        .caller = function.id orelse return error.TestExpectedEqual,
                        .realization_start = realization_start,
                    };
                }
                flattened += 1;
            }
        }
    }
    const expected = before orelse return error.TestExpectedEqual;

    const report = try applyModuleRegionTransformsWithGraph(alloc, &module, projection, &graph);
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);
    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);

    var retained = false;
    for (module.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application != expected.application) continue;
                try std.testing.expectEqual(expected.relation, instruction.relation.?);
                try std.testing.expectEqual(expected.value, instruction.value.?);
                try std.testing.expectEqual(expected.subject, instruction.subject);
                try std.testing.expectEqual(expected.caller, function.id.?);
                try std.testing.expectEqual(expected.realization_start, instruction.realization_start.?);
                retained = true;
            }
        }
    }
    try std.testing.expect(retained);
}

test "region_transform: rejects equal coordinates from another graph" {
    var graph_a = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph_a.deinit();
    var graph_b = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph_b.deinit();
    const functions = [_]dnir.Function{.{
        .name = "probe",
        .ret = .void,
        .blocks = &.{.{ .instrs = &.{.{ .op = .ret }} }},
    }};
    const module_a: dnir.Module = .{ .graph = &graph_a, .functions = &functions };
    var module_b: dnir.Module = .{ .graph = &graph_b, .functions = &functions };
    const projection = try region_graph.buildModuleRegions(std.testing.allocator, module_a);
    defer region_graph.freeModuleRegions(std.testing.allocator, projection);
    try std.testing.expectError(
        error.ResidencyMismatch,
        applyModuleRegionTransforms(std.testing.allocator, &module_b, projection),
    );
}

test "region_transform: stale constants across blocks and redefinitions decline" {
    const cross_blocks = [_]dnir.Block{
        .{ .instrs = &.{.{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 }} },
        .{ .instrs = &.{
            .{ .op = .call_extern, .result = 0, .callee = "value", .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .temp = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
        } },
    };
    const same_block = [_]dnir.Block{.{ .instrs = &.{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 },
        .{ .op = .call_extern, .result = 0, .callee = "value", .ty = .i64 },
        .{ .op = .binop, .result = 1, .lhs = .{ .temp = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
    } }};
    const functions = [_]dnir.Function{
        .{ .name = "cross", .ret = .i64, .blocks = &cross_blocks },
        .{ .name = "same", .ret = .i64, .blocks = &same_block },
    };
    const module: dnir.Module = .{ .functions = &functions };
    const projection = try region_graph.buildModuleRegions(std.testing.allocator, module);
    defer region_graph.freeModuleRegions(std.testing.allocator, projection);
    const records = try findConstBinopFusions(std.testing.allocator, projection, module);
    defer freeTransformRecords(std.testing.allocator, records);
    try std.testing.expectEqual(@as(usize, 0), records.len);
}

test "region_transform: exact coordinate selects one duplicate result slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "duplicate",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 },
            .{ .op = .binop, .result = 5, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .binop, .result = 5, .lhs = .{ .temp = 99 }, .rhs = .{ .i64 = 2 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 5 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const projection = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, projection);
    const records = try findConstBinopFusions(alloc, projection, module);
    defer freeTransformRecords(alloc, records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(u32, 2), records[0].coordinate);
    try std.testing.expect(try applyConstBinopFusion(
        alloc,
        &functions[0],
        records[0].coordinate,
        records[0].const_value,
    ));
    try std.testing.expectEqual(dnir.Op.@"const", functions[0].blocks[0].instrs[1].op);
    try std.testing.expectEqual(dnir.Op.binop, functions[0].blocks[0].instrs[2].op);
}

test "region_transform: prunes orphaned constant temps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var function = dnir.Function{
        .name = "dead",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 10 }, .ty = .i64 },
            .{ .op = .@"const", .result = 2, .lhs = .{ .i64 = 32 }, .ty = .i64 },
            .{ .op = .@"const", .result = 3, .lhs = .{ .i64 = 42 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 3 } },
        } }},
    };
    const pruned = try pruneDeadConstProducers(alloc, &function);
    try std.testing.expectEqual(@as(u32, 2), pruned);
    try std.testing.expectEqual(@as(usize, 2), function.blocks[0].instrs.len);
}
