/// Compiler directive registry and attribute parsing for @test.*, @build.*,
/// @time, @bench, and related debugging/benchmark annotations.
const std = @import("std");
const ast = @import("ast.zig");

pub const ParseError = error{InvalidDirective, OutOfMemory};

pub const ArgMap = struct {
    entries: std.StringHashMapUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ArgMap, alloc: std.mem.Allocator) void {
        self.entries.deinit(alloc);
    }

    pub fn get(self: *const ArgMap, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    pub fn getU32(self: *const ArgMap, key: []const u8, default: u32) u32 {
        const raw = self.entries.get(key) orelse return default;
        return std.fmt.parseInt(u32, raw, 10) catch default;
    }
};

/// Parsed options for a test/bench function annotation.
pub const TestOptions = struct {
    name: []const u8,
    skip: bool = false,
    only: bool = false,
    flaky: bool = false,
    should_panic: bool = false,
    bench: bool = false,
    time: bool = false,
    tag: ?[]const u8 = null,
    message: ?[]const u8 = null,
    timeout_ms: ?u32 = null,
    iterations: u32 = 1,
    warmup: u32 = 0,
};

pub fn attrNameEq(attr: ast.Attribute, name: []const u8) bool {
    return std.mem.eql(u8, attr.name, name);
}

pub fn attrHasPrefix(attr: ast.Attribute, prefix: []const u8) bool {
    return std.mem.startsWith(u8, attr.name, prefix);
}

pub fn isTestDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "test") or std.mem.startsWith(u8, name, "test.");
}

pub fn isBuildDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "build") or std.mem.startsWith(u8, name, "build.");
}

pub fn isTimeDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "time") or std.mem.startsWith(u8, name, "time.");
}

pub fn isBenchDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "bench") or std.mem.startsWith(u8, name, "bench.");
}

pub fn isDebugDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "trace") or
        std.mem.eql(u8, name, "debug") or
        std.mem.startsWith(u8, name, "debug.");
}

/// Whether this attribute marks a function as a test case (including @bench on tests).
pub fn attrsMarkTest(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isTestDirective(attr.name)) return true;
        if (isBenchDirective(attr.name)) return true;
    }
    return false;
}

pub fn attrsWantTiming(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isTimeDirective(attr.name)) return true;
        if (attrHasPrefix(attr, "test.time")) return true;
        if (isBenchDirective(attr.name)) return true;
        if (attrHasPrefix(attr, "test.bench")) return true;
    }
    return false;
}

pub fn attrsWantBench(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isBenchDirective(attr.name)) return true;
        if (attrHasPrefix(attr, "test.bench")) return true;
    }
    return false;
}

pub fn parseAttrArgs(alloc: std.mem.Allocator, raw: ?[]const u8) ParseError!ArgMap {
    var map: ArgMap = .{};
    errdefer map.deinit(alloc);
    const text = raw orelse return map;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return map;

    // Quoted string positional: @test("integration")
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        const s = try alloc.dupe(u8, trimmed[1 .. trimmed.len - 1]);
        try map.entries.put(alloc, "name", s);
        return map;
    }

    // Table literal: { name = "app", src = "main.duo", iterations = 1000 }
    if (std.mem.startsWith(u8, trimmed, "{") and std.mem.endsWith(u8, trimmed, "}")) {
        try parseTableArgs(alloc, trimmed[1 .. trimmed.len - 1], &map);
        return map;
    }

    // key=value pairs: iterations=1000, warmup=10
    if (std.mem.indexOfScalar(u8, trimmed, '=') != null) {
        try parseKvArgs(alloc, trimmed, &map);
        return map;
    }

    // Bare integer positional (iterations)
    if (std.fmt.parseInt(u32, trimmed, 10)) |n| {
        const key = try alloc.dupe(u8, "iterations");
        const val = try std.fmt.allocPrint(alloc, "{d}", .{n});
        try map.entries.put(alloc, key, val);
        return map;
    } else |_| {}

    // Bare identifier positional (tag/name)
    const key = try alloc.dupe(u8, "name");
    const val = try alloc.dupe(u8, trimmed);
    try map.entries.put(alloc, key, val);
    return map;
}

fn parseKvArgs(alloc: std.mem.Allocator, text: []const u8, map: *ArgMap) ParseError!void {
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const piece = std.mem.trim(u8, part, " \t\r\n");
        if (piece.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, piece, '=') orelse continue;
        const key = std.mem.trim(u8, piece[0..eq], " \t");
        const val_raw = std.mem.trim(u8, piece[eq + 1 ..], " \t");
        const val = try unquote(alloc, val_raw);
        const key_dup = try alloc.dupe(u8, key);
        try map.entries.put(alloc, key_dup, val);
    }
}

fn parseTableArgs(alloc: std.mem.Allocator, body: []const u8, map: *ArgMap) ParseError!void {
    var parts = std.mem.splitScalar(u8, body, ',');
    while (parts.next()) |part| {
        const piece = std.mem.trim(u8, part, " \t\r\n");
        if (piece.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, piece, '=') orelse continue;
        const key = std.mem.trim(u8, piece[0..eq], " \t");
        const val_raw = std.mem.trim(u8, piece[eq + 1 ..], " \t");
        const val = try unquote(alloc, val_raw);
        const key_dup = try alloc.dupe(u8, key);
        try map.entries.put(alloc, key_dup, val);
    }
}

fn unquote(alloc: std.mem.Allocator, raw: []const u8) ParseError![]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return try alloc.dupe(u8, trimmed[1 .. trimmed.len - 1]);
    }
    if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'') {
        return try alloc.dupe(u8, trimmed[1 .. trimmed.len - 1]);
    }
    return try alloc.dupe(u8, trimmed);
}

pub fn parseTestOptions(alloc: std.mem.Allocator, attrs: []const ast.Attribute) ParseError!TestOptions {
    var opts: TestOptions = .{ .name = "test" };
    var args_map: ArgMap = .{};
    defer args_map.deinit(alloc);

    for (attrs) |attr| {
        if (isTimeDirective(attr.name)) opts.time = true;
        if (isBenchDirective(attr.name)) opts.bench = true;

        if (std.mem.eql(u8, attr.name, "test")) {
            // plain @test
        } else if (std.mem.eql(u8, attr.name, "test.skip")) {
            opts.skip = true;
        } else if (std.mem.eql(u8, attr.name, "test.only")) {
            opts.only = true;
        } else if (std.mem.eql(u8, attr.name, "test.flaky")) {
            opts.flaky = true;
        } else if (std.mem.eql(u8, attr.name, "test.should_panic")) {
            opts.should_panic = true;
        } else if (std.mem.eql(u8, attr.name, "test.bench") or std.mem.eql(u8, attr.name, "test.time")) {
            if (std.mem.eql(u8, attr.name, "test.bench")) opts.bench = true;
            if (std.mem.eql(u8, attr.name, "test.time")) opts.time = true;
        } else if (std.mem.startsWith(u8, attr.name, "test.")) {
            const suffix = attr.name["test.".len..];
            if (std.mem.eql(u8, suffix, "unit") or std.mem.eql(u8, suffix, "integration") or std.mem.eql(u8, suffix, "e2e")) {
                opts.tag = try alloc.dupe(u8, suffix);
            }
        }

        if (attr.args) |raw| {
            args_map.deinit(alloc);
            args_map = .{};
            args_map = try parseAttrArgs(alloc, raw);
            if (args_map.get("name")) |n| opts.name = n;
            if (args_map.get("tag")) |t| opts.tag = t;
            if (args_map.get("message")) |m| opts.message = m;
            if (args_map.get("timeout")) |t| opts.timeout_ms = std.fmt.parseInt(u32, t, 10) catch null;
            if (args_map.get("timeout_ms")) |t| opts.timeout_ms = std.fmt.parseInt(u32, t, 10) catch null;
            opts.iterations = args_map.getU32("iterations", opts.iterations);
            opts.warmup = args_map.getU32("warmup", opts.warmup);
        }
    }

    if (opts.bench and opts.iterations == 1) opts.iterations = 1000;
    if (opts.bench) opts.time = true;
    return opts;
}

pub fn validateFuncAttrs(attrs: []const ast.Attribute) ?[]const u8 {
    for (attrs) |attr| {
        if (isTestDirective(attr.name) or isTimeDirective(attr.name) or isBenchDirective(attr.name) or isDebugDirective(attr.name)) {
            continue;
        }
        if (std.mem.eql(u8, attr.name, "inline") or
            std.mem.eql(u8, attr.name, "cold") or
            std.mem.eql(u8, attr.name, "hot") or
            std.mem.eql(u8, attr.name, "noinline") or
            std.mem.eql(u8, attr.name, "export") or
            std.mem.eql(u8, attr.name, "ffi") or
            std.mem.eql(u8, attr.name, "derive") or
            std.mem.eql(u8, attr.name, "arc") or
            std.mem.eql(u8, attr.name, "nopanic") or
            std.mem.eql(u8, attr.name, "packed") or
            std.mem.eql(u8, attr.name, "align") or
            std.mem.eql(u8, attr.name, "deprecated") or
            std.mem.startsWith(u8, attr.name, "concurrent") or
            std.mem.startsWith(u8, attr.name, "implements"))
        {
            continue;
        }
        if (isBuildDirective(attr.name)) {
            return "build directives belong at module scope (@build.project, @build.exe, …), not on functions";
        }
        return attr.name;
    }
    return null;
}

pub fn validateModuleDirective(attr: ast.Attribute) ?[]const u8 {
    if (!isBuildDirective(attr.name)) return attr.name;
    const known = std.mem.eql(u8, attr.name, "build.project") or
        std.mem.eql(u8, attr.name, "build.exe") or
        std.mem.eql(u8, attr.name, "build.lib") or
        std.mem.eql(u8, attr.name, "build.test") or
        std.mem.eql(u8, attr.name, "build.run") or
        std.mem.eql(u8, attr.name, "build.clean") or
        std.mem.eql(u8, attr.name, "build.bench") or
        std.mem.eql(u8, attr.name, "build.fmt") or
        std.mem.eql(u8, attr.name, "build.check");
    if (!known) return attr.name;
    return null;
}

/// Human-readable registry of supported directives (for docs / `--help`).
pub const registry_json =
    \\{"test":["test","test.unit","test.integration","test.e2e","test.skip","test.only","test.flaky","test.should_panic","test.bench","test.time"],
    \\ "build":["build.project","build.exe","build.lib","build.test","build.run","build.bench","build.check","build.fmt","build.clean"],
    \\ "bench":["bench","bench(iterations=N,warmup=N)"],
    \\ "time":["time","time(label=\"...\")"],
    \\ "debug":["trace","debug","debug.log"]}
;

test "directives: parse table args" {
    const alloc = std.testing.allocator;
    var map = try parseAttrArgs(alloc, "{ name = \"app\", iterations = 42 }");
    defer map.deinit(alloc);
    try std.testing.expectEqualStrings("app", map.get("name").?);
    try std.testing.expectEqualStrings("42", map.get("iterations").?);
}

test "directives: dotted test names" {
    try std.testing.expect(isTestDirective("test.unit"));
    try std.testing.expect(isBuildDirective("build.exe"));
    try std.testing.expect(attrsWantBench(&[_]ast.Attribute{.{ .name = "test.bench", .args = null }}));
}

test "directives: test options bench defaults" {
    const alloc = std.testing.allocator;
    const attrs = [_]ast.Attribute{.{ .name = "bench", .args = "{ iterations = 5 }" }};
    var opts = try parseTestOptions(alloc, &attrs);
    defer {
        if (opts.tag) |t| alloc.free(t);
        if (opts.message) |m| alloc.free(m);
    }
    try std.testing.expect(opts.bench);
    try std.testing.expectEqual(@as(u32, 5), opts.iterations);
}
