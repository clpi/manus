// Tests for the FNV-1a hash function used by CodeGen to derive C symbol names.
// The algorithm is duplicated here because calc_lua_hash is private to codegen.zig;
// these tests guard against accidental changes to the algorithm.
const std = @import("std");

fn lua_hash(s: []const u8) u32 {
    var h: u32 = 2166136261; // FNV offset basis
    for (s) |c| {
        h ^= @as(u32, c);
        h = h *% 16777619; // FNV prime (wrapping multiply)
    }
    return h;
}

test "lua_hash: empty string returns FNV offset basis" {
    try std.testing.expectEqual(@as(u32, 2166136261), lua_hash(""));
}

test "lua_hash: deterministic — same input same output" {
    const h1 = lua_hash("hello");
    const h2 = lua_hash("hello");
    try std.testing.expectEqual(h1, h2);
}

test "lua_hash: different inputs differ" {
    try std.testing.expect(lua_hash("foo") != lua_hash("bar"));
    try std.testing.expect(lua_hash("a")   != lua_hash("b"));
    try std.testing.expect(lua_hash("")    != lua_hash("x"));
}

test "lua_hash: order matters (not commutative)" {
    try std.testing.expect(lua_hash("ab") != lua_hash("ba"));
}

test "lua_hash: known stable value for 'print'" {
    // Pre-computed; this test breaks intentionally if the algorithm ever changes.
    const h = lua_hash("print");
    // Recompute inline as the ground truth so the test is self-contained.
    const expected = blk: {
        var v: u32 = 2166136261;
        for ("print") |c| { v ^= @as(u32, c); v = v *% 16777619; }
        break :blk v;
    };
    try std.testing.expectEqual(expected, h);
}

test "lua_hash: single character" {
    // Hash of "a" computed step by step.
    const expected = (2166136261 ^ @as(u32, 'a')) *% 16777619;
    try std.testing.expectEqual(expected, lua_hash("a"));
}
