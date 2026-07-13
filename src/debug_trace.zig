/// Debug / trace channel filtering for `@debug`, `@trace`, and CLI `--debug`.
const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");
const term = @import("term.zig");

pub const Channel = enum(u8) {
    lex,
    parse,
    sema,
    types,
    mono,
    arc,
    async,
    codegen,
    build,
    @"test",
    link,
    /// Meta-channel: when enabled, all channels may emit.
    all,
};

pub const Scope = enum(u8) {
    module,
    function,
    @"struct",
    enum_type,
    table,
    macro,
    generic,
    trait,
    impl_block,
};

pub const Filter = struct {
    channels: std.EnumSet(Channel) = .{},
    depth_max: u32 = 12,
    depth: u32 = 0,
    /// When set, only these scopes emit (empty = all scopes).
    scopes: std.EnumSet(Scope) = .{},
    scope_filter_active: bool = false,
};

var global: Filter = .{};

pub fn reset() void {
    global = .{};
}

pub fn filter() *Filter {
    return &global;
}

pub fn channelName(ch: Channel) []const u8 {
    return switch (ch) {
        .lex => "lex",
        .parse => "parse",
        .sema => "sema",
        .types => "types",
        .mono => "mono",
        .arc => "arc",
        .async => "async",
        .codegen => "codegen",
        .build => "build",
        .@"test" => "test",
        .link => "link",
        .all => "all",
    };
}

pub fn scopeName(sc: Scope) []const u8 {
    return switch (sc) {
        .module => "module",
        .function => "function",
        .@"struct" => "struct",
        .enum_type => "enum",
        .table => "table",
        .macro => "macro",
        .generic => "generic",
        .trait => "trait",
        .impl_block => "impl",
    };
}

pub fn parseChannelName(name: []const u8) ?Channel {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(trimmed, "all") or std.mem.eql(u8, trimmed, "*")) return .all;
    inline for (std.meta.tags(Channel)) |ch| {
        if (ch != .all) {
            if (std.mem.eql(u8, trimmed, channelName(ch))) return ch;
        }
    }
    return null;
}

pub fn parseScopeName(name: []const u8) ?Scope {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.eql(u8, trimmed, "enum")) return .enum_type;
    if (std.mem.eql(u8, trimmed, "impl")) return .impl_block;
    inline for (std.meta.tags(Scope)) |sc| {
        if (std.mem.eql(u8, trimmed, scopeName(sc))) return sc;
    }
    return null;
}

pub fn parseChannelList(list: []const u8, into: *std.EnumSet(Channel)) void {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= list.len) : (i += 1) {
        if (i == list.len or list[i] == ',' or list[i] == ';' or list[i] == ' ') {
            const part = std.mem.trim(u8, list[start..i], " \t\r\n");
            if (part.len > 0) {
                if (parseChannelName(part)) |ch| {
                    if (ch == .all) {
                        inline for (std.meta.tags(Channel)) |c| {
                            into.insert(c);
                        }
                    } else {
                        into.insert(ch);
                    }
                }
            }
            start = i + 1;
        }
    }
}

pub fn parseScopeList(list: []const u8, into: *std.EnumSet(Scope)) void {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= list.len) : (i += 1) {
        if (i == list.len or list[i] == ',' or list[i] == ';' or list[i] == ' ') {
            const part = std.mem.trim(u8, list[start..i], " \t\r\n");
            if (part.len > 0) {
                if (parseScopeName(part)) |sc| into.insert(sc);
            }
            start = i + 1;
        }
    }
}

pub fn channelFromDirectiveName(name: []const u8) ?Channel {
    if (std.mem.eql(u8, name, "debug") or std.mem.eql(u8, name, "trace")) return .all;
    if (std.mem.startsWith(u8, name, "debug.")) {
        const suffix = name["debug.".len..];
        return parseChannelName(suffix);
    }
    if (std.mem.startsWith(u8, name, "trace.")) {
        const suffix = name["trace.".len..];
        return parseChannelName(suffix);
    }
    return null;
}

pub fn applyCliList(list: []const u8) void {
    global.channels = .{};
    parseChannelList(list, &global.channels);
}

pub fn applyDepth(max_depth: u32) void {
    global.depth_max = max_depth;
}

pub fn enableAll() void {
    global.channels = .{};
    inline for (std.meta.tags(Channel)) |ch| {
        global.channels.insert(ch);
    }
}

pub fn isEnabled(ch: Channel) bool {
    if (global.channels.contains(.all)) return global.depth <= global.depth_max;
    if (global.channels.count() == 0) return false;
    return global.channels.contains(ch) and global.depth <= global.depth_max;
}

pub fn scopeAllowed(sc: Scope) bool {
    if (!global.scope_filter_active) return true;
    return global.scopes.contains(sc);
}

pub fn pushDepth() void {
    global.depth += 1;
}

pub fn popDepth() void {
    if (global.depth > 0) global.depth -= 1;
}

pub fn withDepth(comptime fmt: []const u8, args: anytype) void {
    if (!term.debug_enabled) return;
    term.debugEvent(fmt, args);
}

pub fn event(ch: Channel, sc: Scope, comptime fmt: []const u8, args: anytype) void {
    if (!term.debug_enabled) return;
    if (!isEnabled(ch)) return;
    if (!scopeAllowed(sc)) return;
    term.debugEventChannel(channelName(ch), scopeName(sc), fmt, args);
}

pub fn applyModuleDirective(alloc: std.mem.Allocator, attr: ast.Attribute) !void {
    var map = try directives.parseAttrArgs(alloc, attr.args);
    defer map.deinit(alloc);

    if (map.get("channels")) |raw| parseChannelList(raw, &global.channels);
    if (map.get("depth")) |raw| {
        global.depth_max = std.fmt.parseInt(u32, raw, 10) catch global.depth_max;
    }
    if (map.get("scopes")) |raw| {
        global.scope_filter_active = true;
        parseScopeList(raw, &global.scopes);
    }

    if (directives.isDebugDirective(attr.name) or directives.isTraceDirective(attr.name)) {
        if (channelFromDirectiveName(attr.name)) |ch| {
            if (ch == .all) enableAll() else global.channels.insert(ch);
        }
    }
}

pub fn applyFunctionDirective(attr: ast.Attribute) void {
    if (channelFromDirectiveName(attr.name)) |ch| {
        if (ch == .all) enableAll() else global.channels.insert(ch);
    }
}

test "parse channel list" {
    var set: std.EnumSet(Channel) = .{};
    parseChannelList("sema, codegen, types", &set);
    try std.testing.expect(set.contains(.sema));
    try std.testing.expect(set.contains(.codegen));
    try std.testing.expect(set.contains(.types));
    try std.testing.expect(!set.contains(.link));
}

test "directive name maps to channel" {
    try std.testing.expectEqual(Channel.sema, channelFromDirectiveName("debug.sema").?);
    try std.testing.expectEqual(Channel.codegen, channelFromDirectiveName("trace.codegen").?);
}
