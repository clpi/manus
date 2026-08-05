//! Pass 14 §10, §18 Audit 6, §22 Deliverable F — compatibility-layer matrix.
//!
//! This is a PROJECTION, not a parallel counter (§13.2: one source → many
//! projections). The canonical boxing counts live in `pass4_catalog.boxed_inventory`
//! and are enforced LIVE by `pass4_boxed_inventory`'s `@embedFile` test against
//! the real codegen.zig. This module reframes those counts as the §10/§22-F
//! compat-layer matrix: each boxing/dispatch boundary with its necessity,
//! allocation/copy/boxing/dispatch/generated-code cost, and removal opportunity.
//!
//! This displaces the seeded "partial" compat-layer classification with a live
//! projection (§13.1: a new mechanism that replaces a weaker one rather than
//! adding parallel truth).
const std = @import("std");
const pass4_catalog = @import("pass4_catalog.zig");

pub const SCHEMA_VERSION = "compat-layer-projection-v0";

pub const Cost = enum {
    none,
    conditional,
    always,

    pub fn name(self: Cost) []const u8 {
        return @tagName(self);
    }
};

pub const Layer = struct {
    id: []const u8,
    boundary: []const u8,
    /// Canonical live count, projected from pass4_catalog.boxed_inventory.
    live_count: usize,
    necessity: []const u8,
    allocates: Cost,
    copies: Cost,
    boxes: Cost,
    dispatches_dynamically: Cost,
    generates_code: Cost,
    removal_opportunity: []const u8,
};

/// §10/§22-F — each boxing/dispatch boundary Duo currently pays, with the live
/// count projected from the canonical inventory and the §10 cost attributes.
pub const layers: []const Layer = &.{
    .{
        .id = "lua-value-intermediary",
        .boundary = "lua_Value tagged union (the universal boxed value)",
        .live_count = pass4_catalog.boxed_inventory.lua_value_refs,
        .necessity = "Dynamic-path Lua semantics (heterogeneous tables, unknown types). §12.2: preserve Lua behavior on dynamic paths.",
        .allocates = .conditional,
        .copies = .conditional,
        .boxes = .always,
        .dispatches_dynamically = .conditional,
        .generates_code = .none,
        .removal_opportunity = "Specialize away whenever native_scalar_mode is proven — typed .duo paths already lower to C scalars/structs without lua_Value. Each removed reference is a §1.1 allocation+boxing win.",
    },
    .{
        .id = "lua-invoke-dispatcher",
        .boundary = "lua_invoke generic call dispatcher",
        .live_count = pass4_catalog.boxed_inventory.lua_invoke_refs,
        .necessity = "Dynamic call dispatch when the callee/call-shape is unknown.",
        .allocates = .conditional,
        .copies = .none,
        .boxes = .conditional,
        .dispatches_dynamically = .always,
        .generates_code = .none,
        .removal_opportunity = "Direct native calls when call-shape is known (P4-05 native call ABI; try_emit_native_abi_call for @native). Each removed lua_invoke is a §1.1 indirection+dispatch win.",
    },
    .{
        .id = "emit-as-lua-value",
        .boundary = "emit_as_lua_value representation conversion (native → boxed)",
        .live_count = pass4_catalog.boxed_inventory.emit_as_lua_value_refs,
        .necessity = "Boundary crossing from a specialized/native region back into a dynamic region.",
        .allocates = .conditional,
        .copies = .conditional,
        .boxes = .always,
        .dispatches_dynamically = .none,
        .generates_code = .none,
        .removal_opportunity = "Keep values native across the boundary when both sides are proven native (representation selection, P4-03 explicit box/unbox IR). Each removed conversion is a §1.1 conversion+copy win.",
    },
    .{
        .id = "module-needs-lua-runtime",
        .boundary = "moduleNeedsLuaRuntime embedded C preamble decision",
        .live_count = pass4_catalog.boxed_inventory.module_needs_lua_runtime_refs,
        .necessity = "Generates the Lua runtime C preamble when a module's semantics require it.",
        .allocates = .none,
        .copies = .none,
        .boxes = .none,
        .dispatches_dynamically = .none,
        .generates_code = .always,
        .removal_opportunity = "Pay-for-use linking (P4-09): native_scalar_mode already skips much of the preamble. A fully-native module should link zero runtime. Each gated site is a §1.1 binary-size + runtime-component win.",
    },
};

pub fn total_live_count() usize {
    var t: usize = 0;
    for (layers) |l| t += l.live_count;
    return t;
}

pub fn writeProjectionJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"source\":\"pass4_catalog.boxed_inventory (live, @embedFile-enforced)\",\"total_live_count\":{d},\"layers\":[", .{ SCHEMA_VERSION, total_live_count() });
    for (layers, 0..) |l, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"boundary\":\"{s}\",\"live_count\":{d},\"necessity\":\"{s}\",\"allocates\":\"{s}\",\"copies\":\"{s}\",\"boxes\":\"{s}\",\"dispatches_dynamically\":\"{s}\",\"generates_code\":\"{s}\",\"removal_opportunity\":\"{s}\"}}",
            .{ l.id, l.boundary, l.live_count, l.necessity, l.allocates.name(), l.copies.name(), l.boxes.name(), l.dispatches_dynamically.name(), l.generates_code.name(), l.removal_opportunity },
        );
    }
    try w.print("],\"displacement_note\":\"projects the canonical live inventory; adds no parallel counter (§13.2)\"}}", .{});
}

test "compat_layer_projection: reuses canonical inventory counts (§13.2)" {
    // The projected counts MUST equal the canonical source — no drift, no
    // parallel truth. If pass4_catalog.boxed_inventory changes, this projection
    // changes with it automatically.
    try std.testing.expectEqual(pass4_catalog.boxed_inventory.lua_value_refs, layers[0].live_count);
    try std.testing.expectEqual(pass4_catalog.boxed_inventory.lua_invoke_refs, layers[1].live_count);
    try std.testing.expectEqual(pass4_catalog.boxed_inventory.emit_as_lua_value_refs, layers[2].live_count);
    try std.testing.expectEqual(pass4_catalog.boxed_inventory.module_needs_lua_runtime_refs, layers[3].live_count);
}

test "compat_layer_projection: every layer has a removal opportunity (§10)" {
    for (layers) |l| {
        try std.testing.expect(l.live_count > 0 or std.mem.eql(u8, l.boxes.name(), "none"));
        try std.testing.expect(l.removal_opportunity.len > 20);
    }
}

test "compat_layer_projection: JSON parses and total matches" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeProjectionJson(&aw.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(usize, layers.len), parsed.value.object.get("layers").?.array.items.len);
    try std.testing.expectEqual(@as(i64, @intCast(total_live_count())), parsed.value.object.get("total_live_count").?.integer);
}
