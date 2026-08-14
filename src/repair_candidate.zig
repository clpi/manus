//! — structured diagnostic repair candidates for agents and LSP code actions.
//!
//! Diagnostics describe failure; repairs propose semantically safe next steps.
const std = @import("std");

pub const SCHEMA_VERSION = "repair-candidate-v0";

pub const RepairKind = enum(u8) {
    seal_shape,
    declare_optional_field,
    preserve_dynamic,
    add_non_overlap_contract,
    allocate_output_separately,
    retain_scalar_impl,
    move_field_outside_hot_path,
    specialize_parameter,
    add_guard,

    pub fn name(self: RepairKind) []const u8 {
        return switch (self) {
            .seal_shape => "seal_shape",
            .declare_optional_field => "declare_optional_field",
            .preserve_dynamic => "preserve_dynamic",
            .add_non_overlap_contract => "add_non_overlap_contract",
            .allocate_output_separately => "allocate_output_separately",
            .retain_scalar_impl => "retain_scalar_impl",
            .move_field_outside_hot_path => "move_field_outside_hot_path",
            .specialize_parameter => "specialize_parameter",
            .add_guard => "add_guard",
        };
    }
};

pub const Safety = enum(u8) {
    /// Compiler verified this repair preserves observable behavior under stated assumptions.
    verified,
    /// Requires human or agent review; compiler does not auto-apply.
    advisory,
    /// May change performance only.
    performance_only,

    pub fn name(self: Safety) []const u8 {
        return switch (self) {
            .verified => "verified",
            .advisory => "advisory",
            .performance_only => "performance_only",
        };
    }
};

pub const RepairCandidate = struct {
    kind: RepairKind,
    summary: []const u8,
    safety: Safety,
    entity_id: ?[]const u8 = null,

    pub fn deinit(self: *RepairCandidate, alloc: std.mem.Allocator) void {
        alloc.free(self.summary);
        if (self.entity_id) |e| alloc.free(e);
    }
};

pub const RepairSet = struct {
    diagnostic_id: []const u8,
    reason: []const u8,
    items: []RepairCandidate,

    pub fn deinit(self: *RepairSet, alloc: std.mem.Allocator) void {
        alloc.free(self.diagnostic_id);
        alloc.free(self.reason);
        for (self.items) |*r| r.deinit(alloc);
        alloc.free(self.items);
    }
};

/// Known repair patterns for common optimization blockers (catalog only until MCP wiring).
pub const catalog: []const struct {
    blocker: []const u8,
    kind: RepairKind,
    summary: []const u8,
} = &.{
    .{ .blocker = "open_shape_field_write", .kind = .seal_shape, .summary = "Seal shape or declare optional field in descriptor" },
    .{ .blocker = "unknown_alias", .kind = .add_non_overlap_contract, .summary = "Declare non-overlap contract between input and output buffers" },
    .{ .blocker = "unknown_alias", .kind = .allocate_output_separately, .summary = "Allocate output in a separate buffer from input" },
    .{ .blocker = "vectorize_blocked", .kind = .retain_scalar_impl, .summary = "Retain scalar implementation when vectorization preconditions fail" },
    .{ .blocker = "native_repr_unavailable", .kind = .preserve_dynamic, .summary = "Preserve dynamic representation when native path is unavailable" },
    .{ .blocker = "noalloc_heap_alloc", .kind = .preserve_dynamic, .summary = "Remove @noalloc from the function if heap allocation is required" },
    .{ .blocker = "noalloc_heap_alloc", .kind = .allocate_output_separately, .summary = "Use stack storage or a caller-provided buffer instead of mem.alloc" },
    // GAP-091. `@pure` lowers to `__attribute__((const))`, which promises the C
    // compiler the body reads nothing but its arguments. Touching mutable module
    // state breaks that promise and the compiler cashes it: measured, a `@pure`
    // reader of a module counter answered its FIRST call twice.
    .{ .blocker = "pure_module_state", .kind = .preserve_dynamic, .summary = "Remove @pure from the function if it reads or writes module state" },
    .{ .blocker = "pure_module_state", .kind = .specialize_parameter, .summary = "Pass the module state in as a parameter so the result depends only on arguments" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (catalog, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"blocker\":\"", .{});
        try jsonEscape(w, row.blocker);
        try w.print("\",\"kind\":\"{s}\",\"summary\":\"", .{row.kind.name()});
        try jsonEscape(w, row.summary);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeRepairSetJson(set: *const RepairSet, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"diagnostic_id\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, set.diagnostic_id);
    try w.print("\",\"reason\":\"", .{});
    try jsonEscape(w, set.reason);
    try w.print("\",\"repair_count\":{d},\"repairs\":[", .{set.items.len});
    for (set.items, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"kind\":\"{s}\",\"safety\":\"{s}\",\"summary\":\"", .{ r.kind.name(), r.safety.name() });
        try jsonEscape(w, r.summary);
        try w.print("\"}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn repairsForBlocker(blocker: []const u8, alloc: std.mem.Allocator) !RepairSet {
    var items: std.ArrayListUnmanaged(RepairCandidate) = .empty;
    errdefer {
        for (items.items) |*r| r.deinit(alloc);
        items.deinit(alloc);
    }
    for (catalog) |row| {
        if (!std.mem.eql(u8, row.blocker, blocker)) continue;
        try items.append(alloc, .{
            .kind = row.kind,
            .summary = try alloc.dupe(u8, row.summary),
            .safety = .advisory,
            .entity_id = null,
        });
    }
    const reason = try std.fmt.allocPrint(alloc, "optimization blocked: {s}", .{blocker});
    errdefer alloc.free(reason);
    return .{
        .diagnostic_id = try alloc.dupe(u8, blocker),
        .reason = reason,
        .items = try items.toOwnedSlice(alloc),
    };
}

test "repair_candidate: unknown_alias yields two repairs" {
    const alloc = std.testing.allocator;
    var set = try repairsForBlocker("unknown_alias", alloc);
    defer set.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), set.items.len);
    try std.testing.expectEqual(RepairKind.add_non_overlap_contract, set.items[0].kind);
}
