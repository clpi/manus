//! Pass 15 §6 — command descriptors drive parsing, help, completion, MCP, and LSP.
const std = @import("std");

pub const SCHEMA_VERSION = "command-descriptor-v0";

pub const Effect = enum {
    filesystem_read,
    filesystem_write,
    process,
    network,
    compile,
    none,

    pub fn name(self: Effect) []const u8 {
        return switch (self) {
            .filesystem_read => "filesystem.read",
            .filesystem_write => "filesystem.write",
            .process => "process",
            .network => "network",
            .compile => "compile",
            .none => "none",
        };
    }
};

pub const Descriptor = struct {
    id: []const u8,
    title: []const u8,
    /// `duo build`, `duo test`, etc.
    cli_prefix: []const u8,
    effects: []const Effect,
    /// Structured output descriptor name (Stream[Byte], Record, etc.)
    output: []const u8,
    native_alternative: ?[]const u8 = null,
    examples: []const []const u8 = &.{},
};

/// Built-in Duo project commands — single source for shell, CLI, MCP, completion.
pub const duo_commands: []const Descriptor = &.{
    .{
        .id = "duo.build",
        .title = "Build the Duo compiler and install zig-out/bin/duo",
        .cli_prefix = "zig build",
        .effects = &.{ .compile, .filesystem_read, .filesystem_write },
        .output = "BuildReport",
        .examples = &.{ "duo.build()", "build()" },
    },
    .{
        .id = "duo.test",
        .title = "Run Zig unit tests and compile-fail tests",
        .cli_prefix = "zig build test",
        .effects = &.{ .compile, .process },
        .output = "TestReport",
        .examples = &.{ "duo.test()", "test()" },
    },
    .{
        .id = "duo.bench",
        .title = "Run Duo vs C benchmark suite",
        .cli_prefix = "zig build bench",
        .effects = &.{ .compile, .process },
        .output = "BenchReport",
        .examples = &.{"duo.bench()"},
    },
    .{
        .id = "duo.fmt",
        .title = "Format Zig sources",
        .cli_prefix = "zig fmt src/",
        .effects = &.{ .filesystem_read, .filesystem_write },
        .output = "FmtReport",
        .examples = &.{"duo.fmt()"},
    },
    .{
        .id = "duo.check",
        .title = "Passes audit gate — cross-pass catalog truth",
        .cli_prefix = "duo catalog audit check",
        .effects = &.{ .compile, .process },
        .output = "AuditGateSummary",
        .examples = &.{"duo.check()"},
    },
    .{
        .id = "duo.catalog",
        .title = "Emit machine-readable pass catalog JSON",
        .cli_prefix = "duo catalog",
        .effects = &.{.process},
        .output = "CatalogJson",
        .examples = &.{"duo.catalog()"},
    },
    .{
        .id = "duo.shell",
        .title = "Start persistent semantic shell session",
        .cli_prefix = "duo shell",
        .effects = &.{ .compile, .process, .filesystem_read, .filesystem_write },
        .output = "ShellSession",
        .examples = &.{"duo.shell()"},
    },
    .{
        .id = "exec.raw",
        .title = "Explicit raw host shell (text reparsed, capability gated)",
        .cli_prefix = "shell(",
        .effects = &.{.process},
        .output = "Stream[Byte]",
        .native_alternative = null,
        .examples = &.{ "shell(\"git status\")", "!git status" },
    },
};

pub fn findById(id: []const u8) ?Descriptor {
    for (duo_commands) |d| {
        if (std.mem.eql(u8, d.id, id)) return d;
    }
    return null;
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"commands\":[", .{SCHEMA_VERSION});
    for (duo_commands, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{d.id});
        try jsonEscape(w, d.title);
        try w.print("\",\"cli_prefix\":\"{s}\",\"output\":\"{s}\",\"effects\":[", .{ d.cli_prefix, d.output });
        for (d.effects, 0..) |e, ei| {
            if (ei > 0) try w.writeAll(",");
            try w.print("\"{s}\"", .{e.name()});
        }
        try w.writeAll("]");
        if (d.native_alternative) |na| {
            try w.print(",\"native_alternative\":\"{s}\"", .{na});
        }
        // `writeAll` is raw — unlike `print`, it does not collapse `}}` to `}`.
        // One object was opened per element, so exactly one brace closes it.
        try w.writeAll("}");
    }
    try w.writeAll("]}");
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        }
    }
}

test "command_descriptor: duo.build exists" {
    const d = findById("duo.build") orelse return error.TestExpectedEqual;
    try std.testing.expect(d.effects.len >= 1);
}

test "command_descriptor: writeCatalogJson" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCatalogJson(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "duo.build") != null);
}

// A substring assertion cannot detect malformed JSON — that is how an extra
// closing brace per element survived here. Parse it structurally instead.
test "command_descriptor: writeCatalogJson emits parseable JSON" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCatalogJson(&aw.writer);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);

    const commands = parsed.value.object.get("commands") orelse return error.TestExpectedEqual;
    try std.testing.expect(commands == .array);
    try std.testing.expectEqual(duo_commands.len, commands.array.items.len);
    for (commands.array.items) |cmd| {
        try std.testing.expect(cmd == .object);
        try std.testing.expect(cmd.object.get("id") != null);
        try std.testing.expect(cmd.object.get("effects").? == .array);
    }
}
