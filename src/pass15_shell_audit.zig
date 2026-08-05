//! Pass 15 — semantic shell landscape audit (Audits 1–10 classification).
const std = @import("std");

pub const Classification = enum {
    subsumed,
    ergonomic_lesson,
    semantic_opportunity,
    compatibility,
    rejected,

    pub fn name(self: Classification) []const u8 {
        return @tagName(self);
    }
};

pub const AuditEntry = struct {
    id: []const u8,
    shell: []const u8,
    idea: []const u8,
    classification: Classification,
    duo_response: []const u8,
};

pub const audit_landscape: []const AuditEntry = &.{
    .{ .id = "A1-01", .shell = "Bash", .idea = "POSIX word splitting", .classification = .rejected, .duo_response = "Arguments are semantic values; no implicit splitting" },
    .{ .id = "A1-02", .shell = "Bash", .idea = "Glob expansion in tokens", .classification = .rejected, .duo_response = "Explicit path:glob(); returns Path values" },
    .{ .id = "A1-03", .shell = "Fish", .idea = "Autosuggestions + friendly errors", .classification = .ergonomic_lesson, .duo_response = "Semantic autocorrection + ranked repairs (Pass 15 §13)" },
    .{ .id = "A1-04", .shell = "Nushell", .idea = "Structured tables in pipeline", .classification = .semantic_opportunity, .duo_response = "Stream[Record] foundation; display is projection" },
    .{ .id = "A1-05", .shell = "PowerShell", .idea = "Named options on commands", .classification = .subsumed, .duo_response = "Command descriptors + semantic option calls" },
    .{ .id = "A1-06", .shell = "Oil", .idea = "Separate osh vs ysh", .classification = .rejected, .duo_response = "One language; interactive lowers to canonical Duo" },
    .{ .id = "A1-07", .shell = "Xonsh", .idea = "Python embedded in shell", .classification = .rejected, .duo_response = "Duo is the language; no second shell syntax" },
    .{ .id = "A1-08", .shell = "Unix", .idea = "Pipe = new process", .classification = .semantic_opportunity, .duo_response = "Pipeline graph; fusion or explicit process boundary" },
    .{ .id = "A1-09", .shell = "Task runners", .idea = "YAML-only build truth", .classification = .rejected, .duo_response = "duo.build/test/bench descriptors drive CLI+CI" },
    .{ .id = "A1-10", .shell = "REPLs", .idea = "Separate interpreter semantics", .classification = .rejected, .duo_response = "Progressive compilation ladder; same semantics compiled" },
};

pub const audit_duo_surfaces: []const AuditEntry = &.{
    .{ .id = "A2-01", .shell = "duo CLI", .idea = "Subcommand tree", .classification = .compatibility, .duo_response = "Migrating to command descriptors (command_descriptor.zig)" },
    .{ .id = "A2-02", .shell = "duo shell", .idea = "Line compile to /tmp", .classification = .semantic_opportunity, .duo_response = "shell_session.zig persistent session + export" },
    .{ .id = "A2-03", .shell = "host !cmd", .idea = "/bin/sh -c only", .classification = .compatibility, .duo_response = "shell_host.zig cross-platform explicit raw shell" },
    .{ .id = "A2-04", .shell = "MCP", .idea = "Raw shell strings", .classification = .semantic_opportunity, .duo_response = "Structured command descriptors + construct_call (WS16)" },
    .{ .id = "A2-05", .shell = "LSP", .idea = "No pipeline awareness", .classification = .semantic_opportunity, .duo_response = "Compiler facts for commands (WS15)" },
};

pub const audit_groups = [_]struct {
    id: []const u8,
    title: []const u8,
    entries: []const AuditEntry,
}{
    .{ .id = "audit-01", .title = "Shell landscape", .entries = audit_landscape },
    .{ .id = "audit-02", .title = "Current Duo surfaces", .entries = audit_duo_surfaces },
};

pub fn writeAuditSummaryJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"pass15-shell-audit-v0\",\"audit_groups\":[", .{});
    for (audit_groups, 0..) |g, gi| {
        if (gi > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"entries\":[", .{ g.id, g.title });
        for (g.entries, 0..) |e, ei| {
            if (ei > 0) try w.writeAll(",");
            try w.print("{{\"id\":\"{s}\",\"shell\":\"{s}\",\"idea\":\"{s}\",\"classification\":\"{s}\",\"duo_response\":\"", .{
                e.id, e.shell, e.idea, e.classification.name(),
            });
            try jsonEscape(w, e.duo_response);
            try w.writeAll("\"}}");
        }
        try w.writeAll("]}");
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

test "pass15_shell_audit: landscape entries present" {
    try std.testing.expect(audit_landscape.len >= 10);
    try std.testing.expect(audit_duo_surfaces.len >= 5);
}
