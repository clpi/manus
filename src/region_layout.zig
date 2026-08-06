//! Pass 22 WS24 — memory / record layout planner (scaffold).
//!
//! Derives field offsets and stack frame sizes from DNIR record descriptors.
//! Feeds future stack allocation and realization materialization passes.
const std = @import("std");
const dnir = @import("duo_native_ir.zig");
const region_graph = @import("region_graph.zig");

pub const SCHEMA_VERSION = "region-layout-v0";

pub const FieldLayout = struct {
    name: []const u8,
    offset: u32,
    size: u32,
    kind: dnir.FieldKind,
};

pub const RecordLayout = struct {
    name: []const u8,
    shape_id: ?u64,
    fields: []FieldLayout,
    size: u32,
    record_align: u32,

    pub fn deinit(self: *RecordLayout, alloc: std.mem.Allocator) void {
        for (self.fields) |f| alloc.free(f.name);
        alloc.free(self.fields);
        alloc.free(self.name);
    }
};

pub const RegionFrame = struct {
    func_name: []const u8,
    stack_bytes: u32,
    record_slots: u32,

    pub fn deinit(self: *RegionFrame, alloc: std.mem.Allocator) void {
        alloc.free(self.func_name);
    }
};

fn fieldSize(kind: dnir.FieldKind) u32 {
    return switch (kind) {
        .i64, .f64 => 8,
        .str => 8,
    };
}

fn fieldAlign(kind: dnir.FieldKind) u32 {
    _ = kind;
    return 8;
}

pub fn planRecordLayout(alloc: std.mem.Allocator, rec: dnir.RecordDesc) !RecordLayout {
    var fields: std.ArrayListUnmanaged(FieldLayout) = .empty;
    errdefer fields.deinit(alloc);

    var offset: u32 = 0;
    var max_align: u32 = 8;
    for (rec.fields, rec.kinds) |fname, kind| {
        const field_alignment = fieldAlign(kind);
        if (field_alignment > max_align) max_align = field_alignment;
        offset = @intCast(std.mem.alignForward(u32, offset, field_alignment));
        const size = fieldSize(kind);
        try fields.append(alloc, .{
            .name = try alloc.dupe(u8, fname),
            .offset = offset,
            .size = size,
            .kind = kind,
        });
        offset += size;
    }
    const total: u32 = @intCast(std.mem.alignForward(u32, offset, max_align));

    return .{
        .name = try alloc.dupe(u8, rec.name),
        .shape_id = rec.shape_id,
        .fields = try fields.toOwnedSlice(alloc),
        .size = total,
        .record_align = max_align,
    };
}

pub fn planModuleRecordLayouts(alloc: std.mem.Allocator, m: dnir.Module) ![]RecordLayout {
    var out: std.ArrayListUnmanaged(RecordLayout) = .empty;
    errdefer {
        for (out.items) |*r| r.deinit(alloc);
        out.deinit(alloc);
    }
    for (m.records) |rec| {
        try out.append(alloc, try planRecordLayout(alloc, rec));
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeModuleRecordLayouts(alloc: std.mem.Allocator, layouts: []RecordLayout) void {
    for (layouts) |*r| r.deinit(alloc);
    alloc.free(layouts);
}

/// Estimate per-function stack frame from record init nodes in the region graph.
pub fn planRegionFrame(
    alloc: std.mem.Allocator,
    region: *const region_graph.Region,
    layouts: []const RecordLayout,
) !RegionFrame {
    var stack: u32 = 0;
    var slots: u32 = 0;
    for (region.nodes) |node| {
        if (node.kind != .record) continue;
        const label = node.label orelse continue;
        for (layouts) |layout| {
            if (!std.mem.eql(u8, layout.name, label)) continue;
            stack += layout.size;
            slots += 1;
            break;
        }
    }
    return .{
        .func_name = try alloc.dupe(u8, region.func_name),
        .stack_bytes = stack,
        .record_slots = slots,
    };
}

pub fn planModuleRegionFrames(
    alloc: std.mem.Allocator,
    regions: []const region_graph.Region,
    layouts: []const RecordLayout,
) ![]RegionFrame {
    var out: std.ArrayListUnmanaged(RegionFrame) = .empty;
    errdefer {
        for (out.items) |*f| f.deinit(alloc);
        out.deinit(alloc);
    }
    for (regions) |region| {
        try out.append(alloc, try planRegionFrame(alloc, &region, layouts));
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeModuleRegionFrames(alloc: std.mem.Allocator, frames: []RegionFrame) void {
    for (frames) |*f| f.deinit(alloc);
    alloc.free(frames);
}

test "region_layout: f64 Point layout is 16 bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const rec = dnir.RecordDesc{
        .name = try alloc.dupe(u8, "Point"),
        .fields = try alloc.dupe([]const u8, &.{ "x", "y" }),
        .kinds = try alloc.dupe(dnir.FieldKind, &.{ .f64, .f64 }),
    };
    const layout = try planRecordLayout(alloc, rec);
    try std.testing.expectEqual(@as(u32, 16), layout.size);
    try std.testing.expectEqual(@as(u32, 0), layout.fields[0].offset);
    try std.testing.expectEqual(@as(u32, 8), layout.fields[1].offset);
}
