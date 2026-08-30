const std = @import("std");
const builtin = @import("builtin");
const comptime_eval = @import("comptime.zig");

/// The pinned process runner returns FileNotFound for bare argv[0] on this host
/// even when the shell resolves it from PATH. POSIX `env` performs that lookup
/// while preserving every following item as argv data, never shell source.
fn pathArgv(alloc: std.mem.Allocator, argv: []const []const u8) !?[][]const u8 {
    if (builtin.os.tag == .windows or argv.len == 0 or std.mem.indexOfScalar(u8, argv[0], '/') != null) return null;
    const out = try alloc.alloc([]const u8, argv.len + 1);
    out[0] = "/usr/bin/env";
    @memcpy(out[1..], argv);
    return out;
}

fn currentEnviron() std.process.Environ {
    if (comptime builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .emscripten or builtin.os.tag == .freestanding or builtin.os.tag == .other)
        return .{ .block = .global };
    return .{ .block = .{ .slice = std.mem.span(std.c.environ) } };
}

/// Execute a shell command at compile time via `/bin/sh -c`. Used by `@run`,
/// `@c.include(@run(...))`, `@c.link(@run("pkg-config --libs"))`, etc.
pub fn runHostCommand(alloc: std.mem.Allocator, command: []const u8) ?comptime_eval.CommandOutput {
    var threaded = std.Io.Threaded.init(alloc, .{});
    var environ = std.process.Environ.createMap(currentEnviron(), alloc) catch return null;
    defer environ.deinit();
    const result = std.process.run(alloc, threaded.io(), .{
        .argv = &.{ "/bin/sh", "-c", command },
        .environ_map = &environ,
    }) catch return null;
    return .{
        .ok = result.term.success(),
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

pub fn runHostCommandArgs(alloc: std.mem.Allocator, argv: []const []const u8) ?comptime_eval.CommandOutput {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const resolved = pathArgv(alloc, argv) catch return null;
    defer if (resolved) |owned| alloc.free(owned);
    var environ = std.process.Environ.createMap(currentEnviron(), alloc) catch return null;
    defer environ.deinit();
    const result = std.process.run(alloc, threaded.io(), .{
        .argv = resolved orelse argv,
        .environ_map = &environ,
    }) catch return null;
    return .{
        .ok = result.term.success(),
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

pub const CommandLimits = struct {
    stdout_bytes: usize,
    stderr_bytes: usize,
    read_timeout_seconds: i64,
};

/// Limit captured output and apply a cooperative read deadline. This is not a
/// hard execution deadline: standard-library cleanup may wait for a child that
/// does not terminate when asked.
pub fn runHostCommandArgsLimited(
    alloc: std.mem.Allocator,
    argv: []const []const u8,
    limits: CommandLimits,
) ?comptime_eval.CommandOutput {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();
    const resolved = pathArgv(alloc, argv) catch return null;
    defer if (resolved) |owned| alloc.free(owned);
    var environ = std.process.Environ.createMap(currentEnviron(), alloc) catch return null;
    defer environ.deinit();
    const timeout: std.Io.Timeout = .{ .deadline = std.Io.Clock.Timestamp.fromNow(io, .{
        .raw = .fromSeconds(limits.read_timeout_seconds),
        .clock = .awake,
    }) };
    const result = std.process.run(alloc, io, .{
        .argv = resolved orelse argv,
        .environ_map = &environ,
        .stdout_limit = .limited(limits.stdout_bytes),
        .stderr_limit = .limited(limits.stderr_bytes),
        .timeout = timeout,
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

test "host_run: argv execution resolves PATH without shell source" {
    const alloc = std.testing.allocator;
    const out = runHostCommandArgs(alloc, &.{ "printf", "%s", "hello" }) orelse return error.TestExpectedEqual;
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    try std.testing.expect(out.ok);
    try std.testing.expectEqualStrings("hello", out.stdout);
}

test "host_run: limited argv capture refuses excess output" {
    const alloc = std.testing.allocator;
    try std.testing.expect(runHostCommandArgsLimited(
        alloc,
        &.{ "/usr/bin/printf", "12345" },
        .{ .stdout_bytes = 4, .stderr_bytes = 1024, .read_timeout_seconds = 1 },
    ) == null);
}
