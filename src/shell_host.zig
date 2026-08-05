//! Pass 15 — cross-platform host shell escape hatch (`shell()` / `!` prefix).
//!
//! Raw text-reparsed execution is explicit, capability-gated, and harder to optimize.
const std = @import("std");
const builtin = @import("builtin");

pub const SCHEMA_VERSION = "shell-host-v0";

/// argv for explicit raw shell evaluation (POSIX sh or Windows cmd).
pub fn rawShellArgv(command: []const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/c", command },
        else => &.{ "sh", "-c", command },
    };
}

pub fn rawShellLabel() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "cmd.exe /c",
        else => "sh -c",
    };
}

pub fn runRawShell(io: std.Io, command: []const u8) !u8 {
    const argv = rawShellArgv(command);
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| code,
        else => 128,
    };
}

test "shell_host: rawShellArgv is non-empty" {
    const argv = rawShellArgv("echo ok");
    try std.testing.expect(argv.len >= 2);
}
