const std = @import("std");
const comptime_eval = @import("comptime.zig");

/// Execute a shell command at compile time via `/bin/sh -c`. Used by `@run`,
/// `@c.include(@run(...))`, `@c.link(@run("pkg-config --libs"))`, etc.
pub fn runHostCommand(alloc: std.mem.Allocator, command: []const u8) ?comptime_eval.CommandOutput {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const result = std.process.run(alloc, threaded.io(), .{
        .argv = &.{ "/bin/sh", "-c", command },
    }) catch return null;
    return .{
        .ok = result.term.success(),
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

pub fn runHostCommandArgs(alloc: std.mem.Allocator, argv: []const []const u8) ?comptime_eval.CommandOutput {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const result = std.process.run(alloc, threaded.io(), .{
        .argv = argv,
    }) catch return null;
    return .{
        .ok = result.term.success(),
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

/// Hook signature for `comptime_eval.Options.run_command_hook`.
pub fn runHostCommandHook(ctx: ?*anyopaque, command: []const u8, alloc: std.mem.Allocator) ?comptime_eval.CommandOutput {
    _ = ctx;
    return runHostCommand(alloc, command);
}

test "host_run: echo succeeds" {
    const alloc = std.testing.allocator;
    const out = runHostCommand(alloc, "echo hello") orelse return error.TestExpectedEqual;
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    try std.testing.expect(out.ok);
    try std.testing.expectEqualStrings("hello", std.mem.trimEnd(u8, out.stdout, "\n"));
}
