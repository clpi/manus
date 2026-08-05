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

/// Keep in sync with `pass4_catalog.boxed_inventory` — this test fails when counts drift.
pub const expected = struct {
    pub const lua_value_refs: usize = 1871;
    pub const lua_invoke_refs: usize = 66;
    pub const emit_as_lua_value_refs: usize = 173;
    pub const module_needs_lua_runtime_refs: usize = 21;
};

test "pass4_boxed_inventory: codegen.zig boxing counts match catalog" {
    const src = @embedFile("codegen.zig");
    try std.testing.expectEqual(expected.lua_value_refs, countOccurrences(src, "lua_Value"));
    try std.testing.expectEqual(expected.lua_invoke_refs, countOccurrences(src, "lua_invoke"));
    try std.testing.expectEqual(expected.emit_as_lua_value_refs, countOccurrences(src, "emit_as_lua_value"));
    try std.testing.expectEqual(expected.module_needs_lua_runtime_refs, countOccurrences(src, "moduleNeedsLuaRuntime"));
}
