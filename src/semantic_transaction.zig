//! Pass 12 P12-WS8 — bounded semantic transaction preview/validate (MCP parity, no network).
//!
//! Agents propose edits; Duo returns deterministic preview + obligation impact before apply.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const proof_carrying = @import("proof_carrying.zig");

pub const SCHEMA_VERSION = "semantic-transaction-v0";

pub const MAX_EDITS: usize = 8;
pub const MAX_FIELD_BYTES: usize = 64;

pub const EditKind = enum {
    set_production_classifier,
    set_keyword_spelling,

    pub fn name(self: EditKind) []const u8 {
        return @tagName(self);
    }
};

pub const Edit = struct {
    kind: EditKind,
    /// Target entity (e.g. duo:lexer:keyword_classifier or keyword id).
    target: []const u8,
    /// New value (classifier id or spelling).
    value: []const u8,
};

pub const Violation = struct {
    code: []const u8,
    message: []const u8,
};

pub const PreviewResult = struct {
    accepted: bool,
    edit_count: usize,
    violations: []const Violation,
    obligations_before: usize,
    obligations_after: usize,
    obligations_broken: []const []const u8,
    production_classifier: []const u8,
    differential_would_pass: bool,
};

fn validateEditBounds(edits: []const Edit) ?Violation {
    if (edits.len == 0) {
        return .{ .code = "TXN001", .message = "transaction requires at least one edit" };
    }
    if (edits.len > MAX_EDITS) {
        return .{ .code = "TXN002", .message = "transaction exceeds MAX_EDITS budget" };
    }
    for (edits) |e| {
        if (e.target.len == 0 or e.target.len > MAX_FIELD_BYTES) {
            return .{ .code = "TXN003", .message = "edit target out of bounds" };
        }
        if (e.value.len == 0 or e.value.len > MAX_FIELD_BYTES) {
            return .{ .code = "TXN004", .message = "edit value out of bounds" };
        }
    }
    return null;
}

fn isLegalClassifier(id: []const u8) bool {
    for (token_semantic.legal_classifiers) |c| {
        if (std.mem.eql(u8, c.name(), id)) return true;
    }
    return false;
}

/// Deterministic preview — does not mutate compiler state.
pub fn previewTransaction(edits: []const Edit) PreviewResult {
    var violations_buf: [MAX_EDITS + 4]Violation = undefined;
    var violation_count: usize = 0;
    var broken_buf: [token_semantic.proof_obligations.len][]const u8 = undefined;
    var broken_count: usize = 0;

    const pushViolation = struct {
        fn f(code: []const u8, message: []const u8, buf: *[MAX_EDITS + 4]Violation, count: *usize) void {
            if (count.* >= buf.len) return;
            buf[count.*] = .{ .code = code, .message = message };
            count.* += 1;
        }
    }.f;

    if (validateEditBounds(edits)) |v| {
        pushViolation(v.code, v.message, &violations_buf, &violation_count);
        return .{
            .accepted = false,
            .edit_count = edits.len,
            .violations = violations_buf[0..violation_count],
            .obligations_before = token_semantic.proof_obligations.len,
            .obligations_after = 0,
            .obligations_broken = &.{},
            .production_classifier = token_semantic.production_classifier.name(),
            .differential_would_pass = false,
        };
    }

    var prod = token_semantic.production_classifier.name();

    for (edits) |e| {
        switch (e.kind) {
            .set_production_classifier => {
                if (!std.mem.eql(u8, e.target, token_semantic.intent.subject_entity) and
                    !std.mem.eql(u8, e.target, "keyword_classifier"))
                {
                    pushViolation("TXN010", "classifier edit target must be duo:lexer:keyword_classifier", &violations_buf, &violation_count);
                    continue;
                }
                if (!isLegalClassifier(e.value)) {
                    pushViolation("TXN011", "classifier candidate is not in legal set", &violations_buf, &violation_count);
                    broken_buf[broken_count] = "obl.keyword.exact";
                    broken_count += 1;
                    continue;
                }
                prod = e.value;
            },
            .set_keyword_spelling => {
                pushViolation("TXN020", "keyword spelling edits require descriptor reload (not in M1 preview)", &violations_buf, &violation_count);
                broken_buf[broken_count] = "obl.keyword.exact";
                broken_count += 1;
            },
        }
    }

    const diff_ok = diff: {
        token_semantic.differentialValidateClassifiers() catch break :diff false;
        break :diff true;
    };
    if (!diff_ok) {
        pushViolation("TXN030", "differential validation would fail after edits", &violations_buf, &violation_count);
        broken_buf[broken_count] = "obl.keyword.deterministic";
        broken_count += 1;
    }

    const obligations_before = token_semantic.proof_obligations.len;
    const obligations_after = if (violation_count == 0 and broken_count == 0) obligations_before else obligations_before - broken_count;

    return .{
        .accepted = violation_count == 0 and broken_count == 0,
        .edit_count = edits.len,
        .violations = violations_buf[0..violation_count],
        .obligations_before = obligations_before,
        .obligations_after = obligations_after,
        .obligations_broken = broken_buf[0..broken_count],
        .production_classifier = prod,
        .differential_would_pass = diff_ok,
    };
}

pub fn writePreviewJson(w: *std.Io.Writer, edits: []const Edit) !void {
    const r = previewTransaction(edits);
    try w.print("{{\"schema\":\"{s}\",\"accepted\":", .{SCHEMA_VERSION});
    try w.print("{s}", .{if (r.accepted) "true" else "false"});
    try w.print(",\"edit_count\":{d},\"production_classifier\":\"{s}\",\"differential_would_pass\":", .{
        r.edit_count,
        r.production_classifier,
    });
    try w.print("{s}", .{if (r.differential_would_pass) "true" else "false"});
    try w.print(",\"obligations\":{{\"before\":{d},\"after\":{d},\"broken\":[", .{
        r.obligations_before,
        r.obligations_after,
    });
    for (r.obligations_broken, 0..) |oid, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{oid});
    }
    try w.print("]}},\"violations\":[", .{});
    for (r.violations, 0..) |v, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"code\":\"{s}\",\"message\":\"", .{v.code});
        try jsonEscape(w, v.message);
        try w.print("\"}}", .{});
    }
    try w.print("],\"budget\":{{\"max_edits\":{d},\"max_field_bytes\":{d}}}}}", .{ MAX_EDITS, MAX_FIELD_BYTES });
}

/// Validate applies the same checks as preview; M1 does not mutate production state.
pub fn writeValidateJson(w: *std.Io.Writer, edits: []const Edit) !void {
    try writePreviewJson(w, edits);
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "semantic_transaction: rejects illegal classifier" {
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = "duo:lexer:keyword_classifier",
        .value = "classifier.perfect_hash",
    }};
    const r = previewTransaction(&edits);
    try std.testing.expect(!r.accepted);
    try std.testing.expect(r.violations.len > 0);
}

test "semantic_transaction: accepts legal classifier swap" {
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = "keyword_classifier",
        .value = "classifier.sorted_lookup",
    }};
    const r = previewTransaction(&edits);
    try std.testing.expect(r.accepted);
    try std.testing.expect(std.mem.eql(u8, r.production_classifier, "classifier.sorted_lookup"));
}

test "semantic_transaction: preview JSON schema" {
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = "duo:lexer:keyword_classifier",
        .value = "classifier.length_bucket",
    }};
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePreviewJson(&buf.writer, &edits);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "semantic-transaction-v0") != null);
}
