/// P4-01: test-time scan of codegen.zig boxing sites (not linked into `duo` binary).
const std = @import("std");

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    while (start < haystack.len) {
        const rel = std.mem.indexOfPos(u8, haystack, start, needle) orelse break;
        count += 1;
        start = rel + needle.len;
    }
    return count;
}

/// The counts live in ONE place: `pass4_catalog.boxed_inventory`, which is what
/// `compiler_dynamic_boundary` and `compat_layer_projection` also report from.
///
/// This used to be a second copy carrying its own numbers "kept in sync" by
/// hand, and it had drifted: the copy said 1889 `lua_Value` where the catalog
/// said 1887, and neither matched the file. Because the test asserts in order
/// and stopped at the first mismatch, three further counts (`lua_invoke`,
/// `emit_as_lua_value`, `moduleNeedsLuaRuntime`) had drifted unnoticed behind
/// it — a ratchet reporting one number while three others were unmeasured.
/// Aliasing removes the class of defect rather than resetting the numbers.
pub const expected = @import("pass4_catalog.zig").boxed_inventory;

test "pass4_boxed_inventory: codegen.zig boxing counts match catalog" {
    const src = @embedFile("codegen.zig");
    // Every row is checked and the mismatches are reported TOGETHER. Asserting
    // in sequence let the first failure hide the other three for however long
    // it took someone to look at this file.
    const Row = struct { name: []const u8, needle: []const u8, want: usize };
    const rows = [_]Row{
        .{ .name = "lua_Value", .needle = "lua_Value", .want = expected.lua_value_refs },
        .{ .name = "lua_invoke", .needle = "lua_invoke", .want = expected.lua_invoke_refs },
        .{ .name = "emit_as_lua_value", .needle = "emit_as_lua_value", .want = expected.emit_as_lua_value_refs },
        .{ .name = "moduleNeedsLuaRuntime", .needle = "moduleNeedsLuaRuntime", .want = expected.module_needs_lua_runtime_refs },
    };
    var drifted = false;
    for (rows) |row| {
        const actual = countOccurrences(src, row.needle);
        if (actual != row.want) {
            drifted = true;
            std.debug.print(
                "pass4_boxed_inventory: {s} catalog={d} actual={d} — update pass4_catalog.boxed_inventory\n",
                .{ row.name, row.want, actual },
            );
        }
    }
    try std.testing.expect(!drifted);
    // Positive control: `countOccurrences` must be able to answer zero, or every
    // row above could be comparing 0 against 0 for a needle that never appears.
    try std.testing.expectEqual(@as(usize, 0), countOccurrences(src, "lua_Value_this_identifier_does_not_exist"));
}
