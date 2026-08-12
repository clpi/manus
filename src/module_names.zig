//! Shared Duo module → C symbol prefix (`std.token.classify` → `std_token_classify`).
const std = @import("std");

pub fn moduleCName(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    for (path) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_')
            try out.append(alloc, c)
        else
            try out.append(alloc, '_');
    }
    return out.toOwnedSlice(alloc);
}

pub fn moduleFuncSymbol(alloc: std.mem.Allocator, mod_cname: []const u8, field: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}__{s}", .{ mod_cname, field });
}

test "module_names: path to cname" {
    const a = std.testing.allocator;
    const c = try moduleCName(a, "std.token.classify");
    defer a.free(c);
    try std.testing.expectEqualStrings("std_token_classify", c);
}
