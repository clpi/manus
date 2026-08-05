//! Pass 13 §14 — structured semantic presentation records (terminal/MCP/LSP/CI projections).
const std = @import("std");

pub const SCHEMA_VERSION = "presentation-record-v0";

pub const Severity = enum {
    @"error",
    warning,
    note,
    hint,
    proof,
    optimization,
    validation,
    integration,
    claim,
    regression,

    pub fn name(self: Severity) []const u8 {
        return @tagName(self);
    }

    pub fn symbolAscii(self: Severity) []const u8 {
        return switch (self) {
            .@"error" => "x",
            .warning => "!",
            .note => "i",
            .hint => "?",
            .proof => "+",
            .optimization => "*",
            .validation => "v",
            .integration => "I",
            .claim => "C",
            .regression => "R",
        };
    }
};

pub const RepairOp = struct {
    kind: []const u8,
    detail: []const u8,
};

pub const DiagnosticRecord = struct {
    id: []const u8,
    severity: Severity,
    message: []const u8,
    file: ?[]const u8 = null,
    line: ?u32 = null,
    col: ?u32 = null,
    semantic_entity: ?[]const u8 = null,
    failed_invariant: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    observed: ?[]const u8 = null,
    consequence: ?[]const u8 = null,
    repairs: []const RepairOp = &.{},
    provenance: ?[]const u8 = null,
    doc_ref: ?[]const u8 = null,
};

pub fn writeDiagnosticJson(w: *std.Io.Writer, d: DiagnosticRecord) !void {
    try w.writeAll("{\"id\":\"");
    try jsonEscape(w, d.id);
    try w.writeAll("\",\"severity\":\"");
    try w.writeAll(d.severity.name());
    try w.writeAll("\",\"message\":\"");
    try jsonEscape(w, d.message);
    try w.writeAll("\"");
    if (d.semantic_entity) |e| {
        try w.writeAll(",\"semantic_entity\":\"");
        try jsonEscape(w, e);
        try w.writeAll("\"");
    }
    if (d.file) |f| {
        try w.writeAll(",\"file\":\"");
        try jsonEscape(w, f);
        try w.writeAll("\"");
    }
    if (d.line) |ln| try w.print(",\"line\":{d}", .{ln});
    if (d.col) |c| try w.print(",\"col\":{d}", .{c});
    if (d.failed_invariant) |v| {
        try w.writeAll(",\"failed_invariant\":\"");
        try jsonEscape(w, v);
        try w.writeAll("\"");
    }
    if (d.expected) |v| {
        try w.writeAll(",\"expected\":\"");
        try jsonEscape(w, v);
        try w.writeAll("\"");
    }
    if (d.observed) |v| {
        try w.writeAll(",\"observed\":\"");
        try jsonEscape(w, v);
        try w.writeAll("\"");
    }
    if (d.consequence) |v| {
        try w.writeAll(",\"consequence\":\"");
        try jsonEscape(w, v);
        try w.writeAll("\"");
    }
    try w.writeAll(",\"repairs\":[");
    for (d.repairs, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"kind\":\"");
        try jsonEscape(w, r.kind);
        try w.writeAll("\",\"detail\":\"");
        try jsonEscape(w, r.detail);
        try w.writeAll("\"}");
    }
    try w.writeAll("]}");
}

pub fn renderTerminalLine(d: DiagnosticRecord, color: bool) []const u8 {
    _ = color;
    _ = d;
    // Terminal rendering stays in term.zig; records are canonical.
    return "";
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        else => try w.writeByte(c),
    };
}

test "presentation_record: diagnostic json round-trip shape" {
    const d = DiagnosticRecord{
        .id = "DNB001",
        .severity = .@"error",
        .message = "outside direct backend subset",
        .semantic_entity = "native_backend",
        .repairs = &.{.{ .kind = "use_backend", .detail = "--backend=c" }},
    };
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeDiagnosticJson(&aw.writer, d);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"severity\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "DNB001") != null);
}
