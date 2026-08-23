//! §15 — persistent semantic shell session (history, export, snapshot).
const std = @import("std");
const builtin = @import("builtin");
const scratch = @import("scratch.zig");
const shell_host = @import("shell_host.zig");

pub const SCHEMA_VERSION = "shell-session-v0";

pub const HistoryKind = enum {
    expression,
    statement,
    meta,
    raw_shell,
    @"export",

    pub fn name(self: HistoryKind) []const u8 {
        return @tagName(self);
    }
};

pub const HistoryEntry = struct {
    kind: HistoryKind,
    source: []const u8,
    canonical: []const u8,
    exit_code: ?u8 = null,
    compile_ms: ?u64 = null,
    effects: []const u8 = "",
};

pub const Session = struct {
    session_id: []const u8,
    compile_counter: usize,
    history: std.ArrayList(HistoryEntry),
    started_at_ns: i128,

    pub fn deinit(self: *Session, alloc: std.mem.Allocator) void {
        for (self.history.items) |e| {
            alloc.free(e.source);
            alloc.free(e.canonical);
            if (e.effects.len > 0) alloc.free(e.effects);
        }
        self.history.deinit(alloc);
        alloc.free(self.session_id);
    }
};

// u32, not u64: wasm32 baseline has no 64-bit atomic RMW, and a per-process
// shell session counter never approaches 2^32.
var next_shell_session_id: std.atomic.Value(u32) = .init(1);

pub fn newSession(alloc: std.mem.Allocator) !Session {
    const sid = next_shell_session_id.fetchAdd(1, .monotonic);
    const id = try std.fmt.allocPrint(alloc, "shell-{d}", .{sid});
    return .{
        .session_id = id,
        .compile_counter = 0,
        .history = .empty,
        .started_at_ns = @intCast(sid),
    };
}

pub fn tempArtifactBasename(alloc: std.mem.Allocator, counter: usize, ext: []const u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        // std.process.getEnvVarOwned no longer exists in Zig master; the
        // environment block is reached through std.process.Environ. This branch
        // is Windows-only, so it had never been compiled before the
        // cross-target matrix ran.
        const environ: std.process.Environ = .{ .block = .global };
        const temp = environ.getAlloc(alloc, "TEMP") catch try alloc.dupe(u8, ".");
        defer alloc.free(temp);
        return std.fmt.allocPrint(alloc, "{s}\\idolshell{d}.{s}", .{ temp, counter, ext });
    }
    // The counter is per-SESSION, so two shells running at once both produced
    // `/tmp/idolshell1.out`. `scratch.salt()` separates the processes and
    // `scratch.root()` honours TMPDIR.
    return scratch.path(alloc, "idolshell{x}_{d}.{s}", .{ scratch.salt(), counter, ext });
}

pub fn wrapExpression(alloc: std.mem.Allocator, line: []const u8) ![]u8 {
    return try std.fmt.allocPrint(alloc, "print({s})\n", .{line});
}

pub fn wrapStatement(alloc: std.mem.Allocator, line: []const u8) ![]u8 {
    return try std.fmt.allocPrint(alloc, "{s}\n", .{line});
}

pub fn recordHistory(
    alloc: std.mem.Allocator,
    session: *Session,
    kind: HistoryKind,
    source: []const u8,
    canonical: []const u8,
    exit_code: ?u8,
    compile_ms: ?u64,
) !void {
    const max: usize = 256;
    if (session.history.items.len >= max) {
        const old = session.history.orderedRemove(0);
        alloc.free(old.source);
        alloc.free(old.canonical);
        if (old.effects.len > 0) alloc.free(old.effects);
    }
    const effects = switch (kind) {
        .raw_shell => try alloc.dupe(u8, "process+text_reparse"),
        .expression, .statement => try alloc.dupe(u8, "compile+execute"),
        .meta => try alloc.dupe(u8, "session"),
        .@"export" => try alloc.dupe(u8, "export"),
    };
    try session.history.append(alloc, .{
        .kind = kind,
        .source = try alloc.dupe(u8, source),
        .canonical = try alloc.dupe(u8, canonical),
        .exit_code = exit_code,
        .compile_ms = compile_ms,
        .effects = effects,
    });
}

pub fn exportHistoryModule(alloc: std.mem.Allocator, session: *const Session, limit: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "-- exported from Idol semantic shell session\n");
    try out.appendSlice(alloc, "-- canonical Idol — no shell-only syntax\n\n");
    const start = if (session.history.items.len > limit) session.history.items.len - limit else 0;
    for (session.history.items[start..]) |e| {
        if (e.kind == .meta or e.kind == .raw_shell) continue;
        try out.appendSlice(alloc, e.canonical);
        if (e.canonical.len == 0 or e.canonical[e.canonical.len - 1] != '\n') {
            try out.append(alloc, '\n');
        }
        try out.append(alloc, '\n');
    }
    return try out.toOwnedSlice(alloc);
}

pub fn writeSnapshotJson(w: *std.Io.Writer, session: *const Session) !void {
    try w.print(
        "{{\"schema\":\"{s}\",\"session_id\":\"{s}\",\"compile_counter\":{d},\"history_len\":{d},\"raw_shell_label\":\"{s}\"}}",
        .{ SCHEMA_VERSION, session.session_id, session.compile_counter, session.history.items.len, shell_host.rawShellLabel() },
    );
}

test "shell_session: export skips raw shell" {
    const alloc = std.testing.allocator;
    var s = try newSession(alloc);
    defer s.deinit(alloc);
    try recordHistory(alloc, &s, .expression, "1+2", "print(1+2)\n", 0, 1);
    try recordHistory(alloc, &s, .raw_shell, "!echo hi", "shell(\"echo hi\")", 0, null);
    const mod = try exportHistoryModule(alloc, &s, 10);
    defer alloc.free(mod);
    try std.testing.expect(std.mem.indexOf(u8, mod, "print(1+2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, mod, "shell(") == null);
}
