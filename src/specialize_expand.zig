/// Expand `@specialize(name, T, U)` and table `@specialize({ fn, types })` forms.
const std = @import("std");
const directives = @import("directives.zig");

pub const Request = struct {
    func_name: []const u8,
    type_args_raw: []const []const u8,
};

pub fn expand(alloc: std.mem.Allocator, raw: []const u8) ![]const Request {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '{') return try expandTable(alloc, trimmed);
    return try expandCommaForm(alloc, trimmed);
}

fn expandCommaForm(alloc: std.mem.Allocator, raw: []const u8) ![]const Request {
    const parts = try splitTopLevel(alloc, raw, ',');
    defer alloc.free(parts);
    if (parts.len == 0) return &.{};
    const name = try alloc.dupe(u8, parts[0]);
    var type_args: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (type_args.items) |t| alloc.free(t);
        type_args.deinit(alloc);
        alloc.free(name);
    }
    for (parts[1..]) |part| {
        if (part.len == 0) continue;
        try type_args.append(alloc, try alloc.dupe(u8, part));
    }
    const args = try type_args.toOwnedSlice(alloc);
    const out = try alloc.alloc(Request, 1);
    out[0] = .{ .func_name = name, .type_args_raw = args };
    return out;
}

fn expandTable(alloc: std.mem.Allocator, raw: []const u8) ![]const Request {
    var map = try directives.parseAttrArgs(alloc, raw);
    defer map.deinit(alloc);
    const func_name = map.get("fn") orelse map.get("name") orelse return error.MissingSpecializeFn;
    const types_raw = map.get("types") orelse map.get("variants") orelse return error.MissingSpecializeTypes;
    const name = try alloc.dupe(u8, func_name);

    var variants: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (variants.items) |v| alloc.free(v);
        variants.deinit(alloc);
    }
    try splitTopLevelIntoList(alloc, types_raw, '|', &variants);

    var out: std.ArrayListUnmanaged(Request) = .empty;
    errdefer {
        for (out.items) |req| {
            alloc.free(req.func_name);
            for (req.type_args_raw) |t| alloc.free(t);
            alloc.free(req.type_args_raw);
        }
        out.deinit(alloc);
    }

    for (variants.items) |variant| {
        var type_parts: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (type_parts.items) |t| alloc.free(t);
            type_parts.deinit(alloc);
        }
        try splitTopLevelIntoList(alloc, variant, ',', &type_parts);
        if (type_parts.items.len == 0) continue;
        const owned_args = try type_parts.toOwnedSlice(alloc);
        try out.append(alloc, .{
            .func_name = try alloc.dupe(u8, name),
            .type_args_raw = owned_args,
        });
    }
    alloc.free(name);
    return try out.toOwnedSlice(alloc);
}

fn splitTopLevelIntoList(alloc: std.mem.Allocator, raw: []const u8, delim: u8, out: *std.ArrayListUnmanaged([]const u8)) !void {
    const parts = try splitTopLevel(alloc, raw, delim);
    defer alloc.free(parts);
    for (parts) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        try out.append(alloc, try alloc.dupe(u8, trimmed));
    }
}

fn splitTopLevel(alloc: std.mem.Allocator, raw: []const u8, delim: u8) ![]const []const u8 {
    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer parts.deinit(alloc);
    var start: usize = 0;
    var depth: usize = 0;
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (quote) |q| {
            if (c == '\\' and i + 1 < raw.len) {
                i += 1;
                continue;
            }
            if (c == q) quote = null;
            continue;
        }
        switch (c) {
            '"', '\'' => quote = c,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            else => {
                if (c == delim and depth == 0) {
                    try parts.append(alloc, std.mem.trim(u8, raw[start..i], " \t\r\n"));
                    start = i + 1;
                }
            },
        }
    }
    try parts.append(alloc, std.mem.trim(u8, raw[start..], " \t\r\n"));
    return try parts.toOwnedSlice(alloc);
}

fn freeParts(alloc: std.mem.Allocator, parts: []const []const u8) void {
    for (parts) |p| alloc.free(p);
    alloc.free(parts);
}

test "specialize_expand: comma form" {
    const alloc = std.testing.allocator;
    const reqs = try expand(alloc, "id, i64");
    defer {
        for (reqs) |r| {
            alloc.free(r.func_name);
            for (r.type_args_raw) |t| alloc.free(t);
            alloc.free(r.type_args_raw);
        }
        alloc.free(reqs);
    }
    try std.testing.expectEqual(@as(usize, 1), reqs.len);
    try std.testing.expectEqualStrings("id", reqs[0].func_name);
    try std.testing.expectEqual(@as(usize, 1), reqs[0].type_args_raw.len);
    try std.testing.expectEqualStrings("i64", reqs[0].type_args_raw[0]);
}

test "specialize_expand: table batch with pipe" {
    const alloc = std.testing.allocator;
    const reqs = try expand(alloc, "{ fn = \"id\", types = \"i64 | f64 | str\" }");
    defer {
        for (reqs) |r| {
            alloc.free(r.func_name);
            for (r.type_args_raw) |t| alloc.free(t);
            alloc.free(r.type_args_raw);
        }
        alloc.free(reqs);
    }
    try std.testing.expectEqual(@as(usize, 3), reqs.len);
    try std.testing.expectEqual(@as(usize, 1), reqs[0].type_args_raw.len);
    try std.testing.expectEqualStrings("i64", reqs[0].type_args_raw[0]);
    try std.testing.expectEqual(@as(usize, 1), reqs[1].type_args_raw.len);
    try std.testing.expectEqualStrings("f64", reqs[1].type_args_raw[0]);
    try std.testing.expectEqual(@as(usize, 1), reqs[2].type_args_raw.len);
    try std.testing.expectEqualStrings("str", reqs[2].type_args_raw[0]);
}

test "specialize_expand: table comma list is one multi-arg request" {
    const alloc = std.testing.allocator;
    const reqs = try expand(alloc, "{ fn = \"id\", types = \"i64, f64, str\" }");
    defer {
        for (reqs) |r| {
            alloc.free(r.func_name);
            for (r.type_args_raw) |t| alloc.free(t);
            alloc.free(r.type_args_raw);
        }
        alloc.free(reqs);
    }
    try std.testing.expectEqual(@as(usize, 1), reqs.len);
    try std.testing.expectEqual(@as(usize, 3), reqs[0].type_args_raw.len);
}

test "specialize_expand: table multi-arg variants" {
    const alloc = std.testing.allocator;
    const reqs = try expand(alloc, "{ fn = \"pair\", types = \"i64, str | f64, f64\" }");
    defer {
        for (reqs) |r| {
            alloc.free(r.func_name);
            for (r.type_args_raw) |t| alloc.free(t);
            alloc.free(r.type_args_raw);
        }
        alloc.free(reqs);
    }
    try std.testing.expectEqual(@as(usize, 2), reqs.len);
    try std.testing.expectEqual(@as(usize, 2), reqs[0].type_args_raw.len);
    try std.testing.expectEqualStrings("i64", reqs[0].type_args_raw[0]);
    try std.testing.expectEqualStrings("str", reqs[0].type_args_raw[1]);
}
