const std = @import("std");

/// A launcher's interpretation of source provenance. This is not a world grant:
/// the launcher decides which semantic witnesses a role supplies.
pub const Role = enum {
    ordinary,
    testing,
};

fn hasComponent(path: []const u8, component: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, path, at, component)) |hit| : (at = hit + 1) {
        const opens = hit == 0 or path[hit - 1] == '/';
        const end = hit + component.len;
        const closes = end < path.len and path[end] == '/';
        if (opens and closes) return true;
    }
    return false;
}

/// Filesystem structure may select a launch role. Nothing below grants a world
/// or becomes semantic identity after launch.
pub fn forSource(path: []const u8) Role {
    if (hasComponent(path, "test")) return .testing;
    const stem = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, stem, "_test.id")) return .testing;
    if (std.mem.startsWith(u8, stem, "test_")) return .testing;
    return .ordinary;
}

test "source structure selects a launch role, not a world" {
    try std.testing.expectEqual(Role.testing, forSource("foo_test.id"));
    try std.testing.expectEqual(Role.testing, forSource("test_foo.id"));
    try std.testing.expectEqual(Role.testing, forSource("test/foo.id"));
    try std.testing.expectEqual(Role.testing, forSource("sub/test/foo.id"));
    try std.testing.expectEqual(Role.testing, forSource("test/deep/foo.id"));
    try std.testing.expectEqual(Role.testing, forSource("test/foo_test.id"));

    try std.testing.expectEqual(Role.ordinary, forSource("plain.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("other/injection.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("mytest.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("testing/foo.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("mytest/foo.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("atest.id"));
    try std.testing.expectEqual(Role.ordinary, forSource("a/test"));
}
