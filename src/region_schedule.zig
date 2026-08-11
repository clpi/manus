//! Pass 22 WS25 — explicit schedule slots from region `orders_before` edges.
//!
//! Separates effect ordering (tiling/vectorization/fusion substrate) from semantics.
const std = @import("std");
const region_graph = @import("region_graph.zig");

pub const SCHEMA_VERSION = "region-schedule-v0";

pub const ScheduleSlot = struct {
    slot: u32,
    coordinate: u32,
    kind: region_graph.NodeKind,
};

pub const FunctionSchedule = struct {
    func_name: []const u8,
    slots: []ScheduleSlot,

    pub fn deinit(self: *FunctionSchedule, alloc: std.mem.Allocator) void {
        alloc.free(self.slots);
        alloc.free(self.func_name);
    }
};

pub const Error = error{
    OutOfMemory,
    ScheduleCycle,
};

/// True when `DUO_REGION_GATE` is set — region validation failures become compile errors.
pub fn regionGateStrictEnabled() bool {
    return std.c.getenv("DUO_REGION_GATE") != null;
}

/// Topological order of effect nodes linked by `orders_before` in one region.
pub fn buildRegionSchedule(
    alloc: std.mem.Allocator,
    region: *const region_graph.Region,
) Error![]ScheduleSlot {
    var participants: std.ArrayListUnmanaged(u32) = .empty;
    defer participants.deinit(alloc);

    var indegree = std.AutoHashMapUnmanaged(u32, u32){};
    defer indegree.deinit(alloc);
    var outgoing = std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(u32)){};
    defer {
        var it = outgoing.iterator();
        while (it.next()) |e| e.value_ptr.deinit(alloc);
        outgoing.deinit(alloc);
    }

    for (region.edges) |e| {
        if (e.kind != .orders_before) continue;
        try appendUnique(alloc, &participants, e.from);
        try appendUnique(alloc, &participants, e.to);

        const gop = try indegree.getOrPut(alloc, e.to);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;

        const og = try outgoing.getOrPut(alloc, e.from);
        if (!og.found_existing) og.value_ptr.* = .empty;
        try og.value_ptr.append(alloc, e.to);
    }

    if (participants.items.len == 0) return &[_]ScheduleSlot{};

    var ready: std.ArrayListUnmanaged(u32) = .empty;
    defer ready.deinit(alloc);

    for (participants.items) |id| {
        if (indegree.get(id)) |deg| {
            if (deg == 0) try ready.append(alloc, id);
        } else {
            try ready.append(alloc, id);
        }
    }

    var slots: std.ArrayListUnmanaged(ScheduleSlot) = .empty;
    errdefer slots.deinit(alloc);

    var slot_idx: u32 = 0;
    while (ready.items.len > 0) {
        const coordinate = ready.items[ready.items.len - 1];
        _ = ready.pop();

        const kind = nodeKindOf(region, coordinate);
        try slots.append(alloc, .{ .slot = slot_idx, .coordinate = coordinate, .kind = kind });
        slot_idx += 1;

        if (outgoing.get(coordinate)) |succs| {
            for (succs.items) |to| {
                const gop = indegree.getPtr(to) orelse continue;
                gop.* -= 1;
                if (gop.* == 0) try ready.append(alloc, to);
            }
        }
    }

    if (slots.items.len != participants.items.len) return error.ScheduleCycle;

    return try slots.toOwnedSlice(alloc);
}

fn appendUnique(alloc: std.mem.Allocator, list: *std.ArrayListUnmanaged(u32), id: u32) !void {
    for (list.items) |existing| {
        if (existing == id) return;
    }
    try list.append(alloc, id);
}

fn nodeKindOf(region: *const region_graph.Region, id: u32) region_graph.NodeKind {
    for (region.nodes) |n| {
        if (n.id == id) return n.kind;
    }
    return .value;
}

pub fn buildModuleSchedules(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
) Error![]FunctionSchedule {
    var out: std.ArrayListUnmanaged(FunctionSchedule) = .empty;
    errdefer {
        for (out.items) |*s| s.deinit(alloc);
        out.deinit(alloc);
    }
    for (projection.regions) |region| {
        var schedule = try buildFunctionSchedule(alloc, &region);
        out.append(alloc, schedule) catch |err| {
            schedule.deinit(alloc);
            return err;
        };
    }
    return try out.toOwnedSlice(alloc);
}

fn buildFunctionSchedule(
    alloc: std.mem.Allocator,
    region: *const region_graph.Region,
) Error!FunctionSchedule {
    const slots = try buildRegionSchedule(alloc, region);
    errdefer alloc.free(slots);
    return .{
        .func_name = try alloc.dupe(u8, region.func_name),
        .slots = slots,
    };
}

pub fn freeModuleSchedules(alloc: std.mem.Allocator, schedules: []FunctionSchedule) void {
    for (schedules) |*s| s.deinit(alloc);
    alloc.free(schedules);
}

/// Return schedule slot index for a region node, or null if not scheduled.
pub fn slotIndexOf(schedule: []const ScheduleSlot, coordinate: u32) ?u32 {
    for (schedule) |s| {
        if (s.coordinate == coordinate) return s.slot;
    }
    return null;
}

/// True when `before` is ordered before `after` in the schedule (strict <).
pub fn orderedBefore(schedule: []const ScheduleSlot, before: u32, after: u32) bool {
    const a = slotIndexOf(schedule, before) orelse return false;
    const b = slotIndexOf(schedule, after) orelse return false;
    return a < b;
}

test "region_schedule: orders_before yields call before ret" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");
    const semantic_graph = @import("semantic_graph.zig");
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\helper(): i64
        \\    1
        \\main(): i64
        \\    helper()
    ;
    var lex = Lexer.init(src, "schedule.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "schedule.id");
    const m = try dnir_lower.lowerModuleWithGraph(alloc, &mod, &g);
    const regions = try region_graph.buildModuleRegions(alloc, m);
    defer region_graph.freeModuleRegions(alloc, regions);

    const main_region = region_graph.findRegion(regions, "main") orelse return error.TestExpectedEqual;
    const schedule = try buildRegionSchedule(alloc, main_region);
    defer alloc.free(schedule);
    try std.testing.expect(schedule.len >= 2);

    var call_id: ?u32 = null;
    var ret_id: ?u32 = null;
    for (main_region.nodes) |n| {
        if (n.kind == .call) call_id = n.id;
        if (n.kind == .ret) ret_id = n.id;
    }
    const cid = call_id orelse return error.TestExpectedEqual;
    const rid = ret_id orelse return error.TestExpectedEqual;
    try std.testing.expect(orderedBefore(schedule, cid, rid));
}

test "region_schedule: module projection releases owned schedules on allocation failure" {
    const dnir = @import("duo_native_ir.zig");

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const module: dnir.Module = .{ .functions = &.{.{
                .name = "main",
                .ret = .i64,
                .blocks = &.{.{ .instrs = &.{
                    .{ .op = .call_direct, .callee = "work", .result = 0 },
                    .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i64 },
                } }},
            }} };
            const regions = try region_graph.buildModuleRegions(alloc, module);
            defer region_graph.freeModuleRegions(alloc, regions);
            const schedules = try buildModuleSchedules(alloc, regions);
            defer freeModuleSchedules(alloc, schedules);
        }
    }.run, .{});
}
