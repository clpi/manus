//! Physical scheduling projection of DNIR.
//!
//! Semantic ids and their facts remain in the resident semantic graph and in
//! DNIR lineage. Regions retain only the contiguous instruction coordinate
//! range, value-flow dependencies, and hardware tier.
const std = @import("std");
const dnir = @import("native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");

pub const Dependency = struct {
    slot: u32,
    producer: u32,
    consumer: u32,
};

pub const Region = struct {
    dependencies: []Dependency,
    coordinate_limit: u32,
    hardware_tier: dnir.HardwareTier = .scalar,

    pub fn deinit(self: *Region, alloc: std.mem.Allocator) void {
        alloc.free(self.dependencies);
    }
};

/// Borrowed residency plus derived scheduling data. The pointers are physical
/// context only: they grant no authority and create no semantic identity.
pub const Projection = struct {
    graph: ?*const semantic_graph.SemanticGraph,
    functions: []const dnir.Function,
    regions: []Region,

    pub fn deinit(self: Projection, alloc: std.mem.Allocator) void {
        for (self.regions) |*region| region.deinit(alloc);
        alloc.free(self.regions);
    }
};

pub const Error = error{
    ResidencyMismatch,
    RegionCountMismatch,
    CoordinateOutOfBounds,
    DependencyMismatch,
    HardwareTierMismatch,
    CoordinateOverflow,
    OutOfMemory,
};

fn appendDependency(
    alloc: std.mem.Allocator,
    dependencies: *std.ArrayListUnmanaged(Dependency),
    definitions: *const std.AutoHashMapUnmanaged(u32, u32),
    value: dnir.Value,
    consumer: u32,
) !void {
    const slot = switch (value) {
        .temp, .local => |slot| slot,
        else => return,
    };
    const producer = definitions.get(slot) orelse 0;
    try dependencies.append(alloc, .{
        .slot = slot,
        .producer = producer,
        .consumer = consumer,
    });
}

fn appendInstructionDependencies(
    alloc: std.mem.Allocator,
    dependencies: *std.ArrayListUnmanaged(Dependency),
    definitions: *const std.AutoHashMapUnmanaged(u32, u32),
    instruction: dnir.Instr,
    consumer: u32,
) !void {
    if (instruction.op == .ret_record and instruction.vals.len != 0) {
        for (instruction.vals) |value| {
            try appendDependency(alloc, dependencies, definitions, value, consumer);
        }
        return;
    }
    try appendDependency(alloc, dependencies, definitions, instruction.lhs, consumer);
    try appendDependency(alloc, dependencies, definitions, instruction.rhs, consumer);
    try appendDependency(alloc, dependencies, definitions, instruction.third, consumer);
}

pub fn buildFromDnirFunction(
    alloc: std.mem.Allocator,
    function: dnir.Function,
) !Region {
    var dependencies: std.ArrayListUnmanaged(Dependency) = .empty;
    errdefer dependencies.deinit(alloc);
    var definitions: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer definitions.deinit(alloc);

    // Coordinate zero means no prior definition exists in this region. It does
    // not admit the slot as a valid parameter; native realization validates
    // incoming homes. Instructions use contiguous coordinates from one.
    var coordinate: u32 = 1;

    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            const current = coordinate;
            coordinate = std.math.add(u32, coordinate, 1) catch
                return error.CoordinateOverflow;
            try appendInstructionDependencies(
                alloc,
                &dependencies,
                &definitions,
                instruction,
                current,
            );
            if (dnir.definition(instruction)) |slot| try definitions.put(alloc, slot, current);
        }
    }

    const owned_dependencies = try dependencies.toOwnedSlice(alloc);
    errdefer alloc.free(owned_dependencies);
    return .{
        .dependencies = owned_dependencies,
        .coordinate_limit = coordinate,
        .hardware_tier = dnir_hardware.functionHardwareTier(function),
    };
}

pub fn buildModuleRegions(alloc: std.mem.Allocator, module: dnir.Module) !Projection {
    var regions: std.ArrayListUnmanaged(Region) = .empty;
    errdefer {
        for (regions.items) |*region| region.deinit(alloc);
        regions.deinit(alloc);
    }

    for (module.functions) |function| {
        var region = try buildFromDnirFunction(alloc, function);
        regions.append(alloc, region) catch |err| {
            region.deinit(alloc);
            return err;
        };
    }

    return .{
        .graph = module.graph,
        .functions = module.functions,
        .regions = try regions.toOwnedSlice(alloc),
    };
}

pub fn freeModuleRegions(alloc: std.mem.Allocator, projection: Projection) void {
    projection.deinit(alloc);
}

fn sameFunctions(left: []const dnir.Function, right: []const dnir.Function) bool {
    return left.len == right.len and left.ptr == right.ptr;
}

pub fn validateResidency(projection: Projection, module: dnir.Module) Error!void {
    if (projection.graph != module.graph or
        !sameFunctions(projection.functions, module.functions))
    {
        return error.ResidencyMismatch;
    }
}

fn validateExpectedDependency(
    region: Region,
    definitions: *const std.AutoHashMapUnmanaged(u32, u32),
    index: *usize,
    value: dnir.Value,
    consumer: u32,
) Error!void {
    const slot = switch (value) {
        .temp, .local => |slot| slot,
        else => return,
    };
    const producer = definitions.get(slot) orelse 0;
    if (index.* >= region.dependencies.len) return error.DependencyMismatch;
    const dependency = region.dependencies[index.*];
    if (dependency.slot != slot or dependency.producer != producer or
        dependency.consumer != consumer)
    {
        return error.DependencyMismatch;
    }
    index.* += 1;
}

fn validateInstructionDependencies(
    region: Region,
    definitions: *const std.AutoHashMapUnmanaged(u32, u32),
    index: *usize,
    instruction: dnir.Instr,
    consumer: u32,
) Error!void {
    if (instruction.op == .ret_record and instruction.vals.len != 0) {
        for (instruction.vals) |value| {
            try validateExpectedDependency(region, definitions, index, value, consumer);
        }
        return;
    }
    try validateExpectedDependency(region, definitions, index, instruction.lhs, consumer);
    try validateExpectedDependency(region, definitions, index, instruction.rhs, consumer);
    try validateExpectedDependency(region, definitions, index, instruction.third, consumer);
}

pub fn validateModuleProjection(
    alloc: std.mem.Allocator,
    projection: Projection,
    module: dnir.Module,
) Error!void {
    try validateResidency(projection, module);
    if (projection.regions.len != module.functions.len) return error.RegionCountMismatch;

    for (module.functions, projection.regions) |function, region| {
        if (region.hardware_tier != dnir_hardware.functionHardwareTier(function)) {
            return error.HardwareTierMismatch;
        }
        var definitions: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        defer definitions.deinit(alloc);
        var coordinate: u32 = 1;
        var dependency_index: usize = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                try validateInstructionDependencies(
                    region,
                    &definitions,
                    &dependency_index,
                    instruction,
                    coordinate,
                );
                if (dnir.definition(instruction)) |slot| {
                    try definitions.put(alloc, slot, coordinate);
                }
                coordinate = std.math.add(u32, coordinate, 1) catch
                    return error.CoordinateOverflow;
            }
        }
        if (region.coordinate_limit != coordinate) return error.CoordinateOutOfBounds;
        if (dependency_index != region.dependencies.len) return error.DependencyMismatch;
        for (region.dependencies) |dependency| {
            if (dependency.consumer < 1 or
                dependency.consumer >= region.coordinate_limit or
                dependency.producer >= dependency.consumer)
            {
                return error.CoordinateOutOfBounds;
            }
        }
    }
}

pub fn validateModuleRegions(
    alloc: std.mem.Allocator,
    projection: Projection,
    graph: *const semantic_graph.SemanticGraph,
    module: dnir.Module,
) Error!void {
    try validateModuleProjection(alloc, projection, module);
    if (projection.graph != graph) return error.ResidencyMismatch;
}

pub fn regionForFunction(projection: Projection, index: usize) ?*const Region {
    if (index >= projection.regions.len or index >= projection.functions.len) return null;
    return &projection.regions[index];
}

pub fn instructionCoordinate(region: *const Region, flattened: u32) ?u32 {
    const coordinate = std.math.add(u32, 1, flattened) catch return null;
    if (coordinate >= region.coordinate_limit) return null;
    return coordinate;
}

pub fn dependencyProducer(region: *const Region, slot: u32, consumer: u32) ?u32 {
    var low: usize = 0;
    var high: usize = region.dependencies.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (region.dependencies[middle].consumer < consumer) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    for (region.dependencies[low..]) |dependency| {
        if (dependency.consumer != consumer) break;
        if (dependency.slot == slot and dependency.consumer == consumer) {
            return dependency.producer;
        }
    }
    return null;
}

test "region_graph: contiguous coordinates retain typed dependencies" {
    const function: dnir.Function = .{
        .name = "probe",
        .ret = .i64,
        .params = &.{.{ .name = "argument", .ty = .i64 }},
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 4, .lhs = .{ .i64 = 40 }, .ty = .i64 },
            .{ .op = .binop, .result = 5, .lhs = .{ .local = 4 }, .rhs = .{ .temp = 0 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 5 }, .ty = .i64 },
        } }},
    };
    var region = try buildFromDnirFunction(std.testing.allocator, function);
    defer region.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 4), region.coordinate_limit);
    try std.testing.expectEqual(@as(usize, 3), region.dependencies.len);
    try std.testing.expectEqual(@as(?u32, 1), dependencyProducer(&region, 4, 2));
    try std.testing.expectEqual(@as(?u32, 0), dependencyProducer(&region, 0, 2));
    try std.testing.expectEqual(@as(?u32, 2), dependencyProducer(&region, 5, 3));
    try std.testing.expectEqual(@as(?u32, 1), instructionCoordinate(&region, 0));
    try std.testing.expectEqual(@as(?u32, 3), instructionCoordinate(&region, 2));
    try std.testing.expectEqual(@as(?u32, null), instructionCoordinate(&region, 3));
}

test "region_graph: ABI destinations and record mirrors do not define or duplicate slots" {
    const function: dnir.Function = .{
        .name = "probe",
        .ret = .any,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 40 }, .ty = .i64 },
            .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 2 }, .ty = .i64 },
            .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
            .{ .op = .binop, .result = 2, .lhs = .{ .temp = 0 }, .rhs = .{ .temp = 1 }, .ty = .i64 },
            .{
                .op = .ret_record,
                .result = 2,
                .lhs = .{ .temp = 0 },
                .rhs = .{ .temp = 1 },
                .vals = &.{ .{ .temp = 0 }, .{ .temp = 1 } },
            },
            .{ .op = .binop, .result = 3, .lhs = .{ .temp = 2 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
        } }},
    };
    var region = try buildFromDnirFunction(std.testing.allocator, function);
    defer region.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), region.dependencies.len);
    try std.testing.expectEqual(@as(?u32, 1), dependencyProducer(&region, 0, 3));
    try std.testing.expectEqual(@as(?u32, 1), dependencyProducer(&region, 0, 4));
    try std.testing.expectEqual(@as(?u32, 2), dependencyProducer(&region, 1, 4));
    try std.testing.expectEqual(@as(?u32, 4), dependencyProducer(&region, 2, 6));
}

test "region_graph: exploded parameter slots retain outside-region dependencies" {
    const function: dnir.Function = .{
        .name = "probe",
        .ret = .i64,
        .params = &.{.{ .name = "pair", .ty = .any, .record = "Pair" }},
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .binop, .result = 2, .lhs = .{ .local = 1 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
        } }},
    };
    var region = try buildFromDnirFunction(std.testing.allocator, function);
    defer region.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?u32, 0), dependencyProducer(&region, 1, 1));
    try std.testing.expectEqual(@as(?u32, 1), dependencyProducer(&region, 2, 2));
}

test "region_graph: projection releases all allocations under failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const function: dnir.Function = .{
                .name = "probe",
                .ret = .i64,
                .params = &.{.{ .name = "argument", .ty = .i64 }},
                .blocks = &.{.{ .instrs = &.{
                    .{ .op = .store_local, .result = 2, .lhs = .{ .temp = 0 }, .ty = .i64 },
                    .{ .op = .binop, .result = 3, .lhs = .{ .local = 2 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
                    .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
                } }},
            };
            const functions = [_]dnir.Function{function};
            var graph = semantic_graph.SemanticGraph.init(alloc);
            defer graph.deinit();
            const module: dnir.Module = .{ .graph = &graph, .functions = &functions };
            const projection = try buildModuleRegions(alloc, module);
            defer freeModuleRegions(alloc, projection);
            try validateModuleRegions(alloc, projection, &graph, module);
        }
    }.run, .{});
}

test "region_graph: rejects another resident graph with equal coordinates" {
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
    const module_b: dnir.Module = .{ .graph = &graph_b, .functions = &functions };
    const projection = try buildModuleRegions(std.testing.allocator, module_a);
    defer freeModuleRegions(std.testing.allocator, projection);

    try std.testing.expectError(
        error.ResidencyMismatch,
        validateModuleRegions(std.testing.allocator, projection, &graph_b, module_b),
    );
}

test "region_graph: malformed physical coordinates fail closed" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const functions = [_]dnir.Function{.{
        .name = "probe",
        .ret = .void,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 1, .lhs = .{ .i64 = 1 } },
            .{ .op = .ret, .lhs = .{ .local = 1 } },
        } }},
    }};
    const module: dnir.Module = .{ .graph = &graph, .functions = &functions };
    const projection = try buildModuleRegions(std.testing.allocator, module);
    defer freeModuleRegions(std.testing.allocator, projection);
    try validateModuleRegions(std.testing.allocator, projection, &graph, module);

    const dependency = projection.regions[0].dependencies[0];
    projection.regions[0].dependencies[0].producer = dependency.consumer;
    try std.testing.expectError(
        error.DependencyMismatch,
        validateModuleRegions(std.testing.allocator, projection, &graph, module),
    );
    projection.regions[0].dependencies[0] = dependency;
    projection.regions[0].coordinate_limit -= 1;
    try std.testing.expectError(
        error.CoordinateOutOfBounds,
        validateModuleRegions(std.testing.allocator, projection, &graph, module),
    );
}
