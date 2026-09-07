const std = @import("std");

pub const UnitTestFilter = union(enum) {
    default,
    filter: []const u8,
    malformed: []const u8,
};

pub fn parseUnitTestFilter(raw: ?[]const u8) UnitTestFilter {
    const text = raw orelse return .default;
    if (text.len == 0) return .{ .malformed = "-Dtest-filter requires a non-empty value" };
    for (text) |c| {
        if (c < 0x20 and c != '\t') {
            return .{ .malformed = "-Dtest-filter contains a control character" };
        }
    }
    return .{ .filter = text };
}

test "parseUnitTestFilter: null is default" {
    const r = parseUnitTestFilter(null);
    try std.testing.expect(r == .default);
}

test "parseUnitTestFilter: non-empty text is filter" {
    const r = parseUnitTestFilter("lower:");
    try std.testing.expect(r == .filter);
    try std.testing.expectEqualStrings("lower:", r.filter);
}

test "parseUnitTestFilter: empty string is malformed" {
    const r = parseUnitTestFilter("");
    try std.testing.expect(r == .malformed);
    try std.testing.expect(std.mem.startsWith(u8, r.malformed, "-Dtest-filter"));
}

test "parseUnitTestFilter: control byte is malformed" {
    const r = parseUnitTestFilter("lower\x01:");
    try std.testing.expect(r == .malformed);
}

test "parseUnitTestFilter: tab is allowed" {
    const r = parseUnitTestFilter("lower\t:");
    try std.testing.expect(r == .filter);
}
