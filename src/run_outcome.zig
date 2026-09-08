//! Execution outcome of a compiled program: `run -> completion -> outcome`.
//!
//! A compile that succeeded and an artifact that exists are two facts; neither
//! is an outcome. The guest supplies the outcome, and it is read from the
//! completion of the process that carried it — directly for a machine artifact,
//! through a runner for a wasm one.
const std = @import("std");
const builtin = @import("builtin");
const scratch = @import("scratch.zig");

const Io = std.Io;

/// The guest never ran, so no exit code of its is being reported.
pub const Fault = enum {
    runner,
    artifact,
    unattributed,
};

pub const Outcome = union(enum) {
    exit: u8,
    trap: std.posix.SIG,
    cancel: std.posix.SIG,
    unrun: Fault,

    pub fn status(self: Outcome) u8 {
        return switch (self) {
            .exit => |code| code,
            .trap, .cancel => |sig| signalStatus(sig),
            .unrun => |fault| switch (fault) {
                .runner => 127,
                .artifact, .unattributed => 126,
            },
        };
    }

    pub fn identity(self: Outcome) ?[]const u8 {
        return switch (self) {
            .exit => null,
            .trap => "RUN110",
            .cancel => "RUN111",
            .unrun => |fault| switch (fault) {
                .runner => "RUN101",
                .artifact => "RUN102",
                .unattributed => "RUN103",
            },
        };
    }
};

pub const Completion = union(enum) {
    exited: u8,
    signalled: std.posix.SIG,
    lost,
};

/// What the runner was asked about the artifact, and answered. `unquestioned`
/// is not "fine": an outcome that needs the answer refuses without it.
pub const Artifact = enum {
    unquestioned,
    accepted,
    rejected,
};

/// WASI `proc_exit` carries [0, 126); a runner status above that band is the
/// runner's own report and not a code the guest could have asked for.
pub const wasi_exit_max: u8 = 125;

/// The runner's status for a guest trap: 128 + SIGABRT, the shell convention
/// the machine path reaches by dying of the signal itself.
pub const runner_trap_status: u8 = 128 + @intFromEnum(std.posix.SIG.ABRT);

/// The one status a guest exit and a runner failure share.
pub const runner_report_status: u8 = 1;

fn signalStatus(sig: std.posix.SIG) u8 {
    const n = @intFromEnum(sig);
    if (n > 127) return 128;
    return @as(u8, 128) +| @as(u8, @intCast(n));
}

fn trapping(sig: std.posix.SIG) bool {
    return switch (sig) {
        .ILL, .TRAP, .ABRT, .BUS, .FPE, .SEGV, .SYS => true,
        else => false,
    };
}

pub fn completionOf(t: std.process.Child.Term) Completion {
    return switch (t) {
        .exited => |code| .{ .exited = code },
        .signal => |sig| .{ .signalled = sig },
        else => .lost,
    };
}

/// The process that completed WAS the guest.
pub fn direct(completion: Completion) Outcome {
    return switch (completion) {
        .exited => |code| .{ .exit = code },
        .signalled => |sig| if (trapping(sig)) .{ .trap = sig } else .{ .cancel = sig },
        .lost => .{ .unrun = .unattributed },
    };
}

/// The process that completed CARRIED the guest, so its status is the runner's
/// report about the guest and is attributed band by band. The one overlapping
/// status is answered by asking the runner whether the artifact was ever
/// accepted; an unasked overlap is refused rather than credited to the guest.
pub fn hosted(completion: Completion, artifact: Artifact) Outcome {
    return switch (completion) {
        .exited => |code| switch (code) {
            runner_report_status => switch (artifact) {
                .accepted => .{ .exit = code },
                .rejected => .{ .unrun = .artifact },
                .unquestioned => .{ .unrun = .unattributed },
            },
            runner_trap_status => .{ .trap = .ABRT },
            else => if (code <= wasi_exit_max)
                .{ .exit = code }
            else
                .{ .unrun = .unattributed },
        },
        .signalled => |sig| if (trapping(sig))
            .{ .unrun = .unattributed }
        else
            .{ .cancel = sig },
        .lost => .{ .unrun = .unattributed },
    };
}

pub fn attributionNeeded(completion: Completion) bool {
    return switch (completion) {
        .exited => |code| code == runner_report_status,
        else => false,
    };
}

fn reachable(io: Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        Io.Dir.accessAbsolute(io, path, .{}) catch return false;
        return true;
    }
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn environValue(name: [:0]const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    const raw = std.c.getenv(name) orelse return null;
    const value = std.mem.span(raw);
    return if (value.len == 0) null else value;
}

/// The runner named by `WASMTIME_BIN`, else the first `wasmtime` on PATH.
/// `std.process.spawn` treats argv[0] as a path, so PATH is walked here.
pub fn runnerPath(alloc: std.mem.Allocator, io: Io) ?[]const u8 {
    const wanted = environValue("WASMTIME_BIN") orelse "wasmtime";
    if (std.mem.indexOfScalar(u8, wanted, '/') != null) {
        return if (reachable(io, wanted)) wanted else null;
    }
    const path = environValue("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(alloc, &.{ dir, wanted }) catch return null;
        if (reachable(io, candidate)) return candidate;
        alloc.free(candidate);
    }
    return null;
}

/// Ask the runner whether it accepts the artifact at all. A runner that cannot
/// be asked leaves the question unquestioned rather than answering it.
pub fn askArtifact(
    alloc: std.mem.Allocator,
    io: Io,
    runner: []const u8,
    artifact: []const u8,
) Artifact {
    const probe = scratch.path(alloc, "idolrun{x}.cwasm", .{scratch.salt()}) catch return .unquestioned;
    defer {
        Io.Dir.deleteFileAbsolute(io, probe) catch {};
        alloc.free(probe);
    }
    var child = std.process.spawn(io, .{
        .argv = &.{ runner, "compile", artifact, "-o", probe },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return .unquestioned;
    const t = child.wait(io) catch return .unquestioned;
    return switch (t) {
        .exited => |code| if (code == 0) .accepted else .rejected,
        else => .unquestioned,
    };
}

test "a machine completion is the guest's own" {
    try std.testing.expectEqual(Outcome{ .exit = 7 }, direct(.{ .exited = 7 }));
    try std.testing.expectEqual(Outcome{ .trap = .FPE }, direct(.{ .signalled = .FPE }));
    try std.testing.expectEqual(Outcome{ .cancel = .TERM }, direct(.{ .signalled = .TERM }));
    try std.testing.expectEqual(Outcome{ .unrun = .unattributed }, direct(.lost));
}

test "a runner status is attributed band by band" {
    try std.testing.expectEqual(Outcome{ .exit = 0 }, hosted(.{ .exited = 0 }, .unquestioned));
    try std.testing.expectEqual(Outcome{ .exit = 7 }, hosted(.{ .exited = 7 }, .unquestioned));
    try std.testing.expectEqual(
        Outcome{ .exit = wasi_exit_max },
        hosted(.{ .exited = wasi_exit_max }, .unquestioned),
    );
    try std.testing.expectEqual(Outcome{ .trap = .ABRT }, hosted(.{ .exited = runner_trap_status }, .unquestioned));
    try std.testing.expectEqual(Outcome{ .cancel = .INT }, hosted(.{ .signalled = .INT }, .unquestioned));
    try std.testing.expectEqual(
        Outcome{ .unrun = .unattributed },
        hosted(.{ .exited = wasi_exit_max + 1 }, .unquestioned),
    );
}

test "the overlapping status is the artifact's question, and refuses unasked" {
    const overlap: Completion = .{ .exited = runner_report_status };
    try std.testing.expect(attributionNeeded(overlap));
    try std.testing.expect(!attributionNeeded(.{ .exited = 7 }));
    try std.testing.expectEqual(Outcome{ .exit = 1 }, hosted(overlap, .accepted));
    try std.testing.expectEqual(Outcome{ .unrun = .artifact }, hosted(overlap, .rejected));
    try std.testing.expectEqual(Outcome{ .unrun = .unattributed }, hosted(overlap, .unquestioned));
}

test "no unrun outcome can be mistaken for a guest that exited 0" {
    const unrun = [_]Outcome{
        .{ .unrun = .runner },
        .{ .unrun = .artifact },
        .{ .unrun = .unattributed },
    };
    for (unrun) |o| {
        try std.testing.expect(o.status() != 0);
        try std.testing.expect(o.status() > wasi_exit_max);
        try std.testing.expect(o.identity() != null);
    }
    try std.testing.expectEqual(@as(?[]const u8, null), (Outcome{ .exit = 0 }).identity());
}

test "trap and cancel report distinct statuses from every lawful exit" {
    const trap = Outcome{ .trap = .ABRT };
    const cancel = Outcome{ .cancel = .TERM };
    try std.testing.expectEqual(runner_trap_status, trap.status());
    try std.testing.expectEqual(@as(u8, 143), cancel.status());
    try std.testing.expect(trap.status() != cancel.status());
    try std.testing.expect(trap.status() > wasi_exit_max);
    try std.testing.expect(cancel.status() > wasi_exit_max);
}
