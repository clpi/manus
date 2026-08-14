//! P12-WS8 — bounded semantic transaction preview/validate (MCP parity, no network).
//!
//! Agents propose edits; Duo returns deterministic preview + obligation impact before apply.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");

pub const SCHEMA_VERSION = "semantic-transaction-v0";

pub const MAX_EDITS: usize = 8;
pub const MAX_FIELD_BYTES: usize = 64;

pub const EditKind = enum {
    set_production_classifier,

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

pub const DifferentialOutcome = enum {
    blocked,
    passed,
    classifier_mismatch,
    false_positive,

    pub fn name(self: DifferentialOutcome) []const u8 {
        return @tagName(self);
    }
};

pub const PreviewResult = struct {
    accepted: bool,
    edit_count: usize,
    violation_storage: [MAX_EDITS + 4]Violation = undefined,
    violation_count: usize = 0,
    obligations_before: usize,
    obligations_after: usize,
    broken_storage: [token_semantic.proof_obligations.len][]const u8 = undefined,
    broken_count: usize = 0,
    production_classifier: token_semantic.ClassifierId,
    differential: DifferentialOutcome,

    pub fn violations(self: *const PreviewResult) []const Violation {
        return self.violation_storage[0..self.violation_count];
    }

    pub fn obligationsBroken(self: *const PreviewResult) []const []const u8 {
        return self.broken_storage[0..self.broken_count];
    }

    fn addViolation(self: *PreviewResult, code: []const u8, message: []const u8) void {
        std.debug.assert(self.violation_count < self.violation_storage.len);
        self.violation_storage[self.violation_count] = .{ .code = code, .message = message };
        self.violation_count += 1;
    }

    fn breakObligation(self: *PreviewResult, id: []const u8) void {
        for (self.obligationsBroken()) |broken| {
            if (std.mem.eql(u8, broken, id)) return;
        }
        std.debug.assert(self.broken_count < self.broken_storage.len);
        self.broken_storage[self.broken_count] = id;
        self.broken_count += 1;
    }
};

const DifferentialError = error{ ClassifierMismatch, FalsePositive };
const DifferentialValidator = *const fn () DifferentialError!void;

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

fn classifier(id: []const u8) ?token_semantic.ClassifierId {
    for (token_semantic.legal_classifiers) |c| {
        if (std.mem.eql(u8, c.name(), id)) return c;
    }
    return null;
}

/// Deterministic preview — does not mutate compiler state.
pub fn previewTransaction(edits: []const Edit) PreviewResult {
    return previewTransactionWithValidation(edits, token_semantic.differentialValidateClassifiers);
}

fn previewTransactionWithValidation(edits: []const Edit, validate: DifferentialValidator) PreviewResult {
    const obligations = token_semantic.proof_obligations.len;
    var result = PreviewResult{
        .accepted = false,
        .edit_count = edits.len,
        .obligations_before = obligations,
        .obligations_after = obligations,
        .production_classifier = token_semantic.production_classifier,
        .differential = .blocked,
    };

    if (validateEditBounds(edits)) |v| {
        result.addViolation(v.code, v.message);
        return result;
    }

    for (edits) |e| {
        switch (e.kind) {
            .set_production_classifier => {
                if (!std.mem.eql(u8, e.target, token_semantic.intent.subject_entity) and
                    !std.mem.eql(u8, e.target, "keyword_classifier"))
                {
                    result.addViolation("TXN010", "classifier edit target must be duo:lexer:keyword_classifier");
                    continue;
                }
                result.production_classifier = classifier(e.value) orelse {
                    result.addViolation("TXN011", "classifier candidate is not in legal set");
                    result.breakObligation("obl.keyword.exact");
                    continue;
                };
            },
        }
    }

    const differential: DifferentialOutcome = if (result.violation_count != 0 or result.broken_count != 0)
        .blocked
    else blk: {
        validate() catch |err| break :blk switch (err) {
            error.ClassifierMismatch => .classifier_mismatch,
            error.FalsePositive => .false_positive,
        };
        break :blk .passed;
    };
    switch (differential) {
        .classifier_mismatch => {
            result.addViolation("TXN030", "differential classification mismatch after edits");
            result.breakObligation("obl.keyword.exact");
        },
        .false_positive => {
            result.addViolation("TXN030", "differential false positive after edits");
            result.breakObligation("obl.keyword.no_false_positive");
        },
        .blocked, .passed => {},
    }

    std.debug.assert(result.broken_count <= obligations);
    result.obligations_after = obligations - result.broken_count;
    result.accepted = result.violation_count == 0 and result.broken_count == 0;
    result.differential = differential;
    return result;
}

pub fn writePreviewJson(w: *std.Io.Writer, edits: []const Edit) !void {
    const r = previewTransaction(edits);
    try writeResultJson(w, &r);
}

fn writeResultJson(w: *std.Io.Writer, r: *const PreviewResult) !void {
    try w.print("{{\"schema\":\"{s}\",\"accepted\":", .{SCHEMA_VERSION});
    try w.print("{s}", .{if (r.accepted) "true" else "false"});
    try w.print(",\"edit_count\":{d},\"production_classifier\":\"{s}\",\"differential_outcome\":\"{s}\",\"differential_would_pass\":", .{
        r.edit_count,
        r.production_classifier.name(),
        r.differential.name(),
    });
    try w.print("{s}", .{if (r.differential == .passed) "true" else "false"});
    try w.print(",\"obligations\":{{\"before\":{d},\"after\":{d},\"broken\":[", .{
        r.obligations_before,
        r.obligations_after,
    });
    for (r.obligationsBroken(), 0..) |oid, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{oid});
    }
    try w.print("]}},\"violations\":[", .{});
    for (r.violations(), 0..) |v, i| {
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
    try std.testing.expectEqual(DifferentialOutcome.blocked, r.differential);
    try std.testing.expectEqual(@as(usize, 1), r.violations().len);
    try std.testing.expectEqualStrings("TXN011", r.violations()[0].code);
    try std.testing.expectEqual(@as(usize, 1), r.obligationsBroken().len);
    try std.testing.expectEqualStrings("obl.keyword.exact", r.obligationsBroken()[0]);
    try std.testing.expectEqual(token_semantic.proof_obligations.len, r.obligations_before);
    try std.testing.expectEqual(r.obligations_before - 1, r.obligations_after);
    try std.testing.expectEqual(token_semantic.production_classifier, r.production_classifier);
}

test "semantic_transaction: accepts legal classifier swap" {
    var candidate = "classifier.sorted_lookup".*;
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = "keyword_classifier",
        .value = &candidate,
    }};
    const r = previewTransaction(&edits);
    @memset(&candidate, 'x');
    try std.testing.expect(r.accepted);
    try std.testing.expectEqual(DifferentialOutcome.passed, r.differential);
    try std.testing.expectEqual(token_semantic.ClassifierId.sorted_lookup, r.production_classifier);
    try std.testing.expectEqual(r.obligations_before, r.obligations_after);
    try std.testing.expectEqual(@as(usize, 0), r.obligationsBroken().len);
}

test "semantic_transaction: repeated refusals retain one broken obligation" {
    const edit = Edit{
        .kind = .set_production_classifier,
        .target = token_semantic.intent.subject_entity,
        .value = "classifier.perfect_hash",
    };
    var edits: [MAX_EDITS]Edit = undefined;
    for (&edits) |*candidate| candidate.* = edit;
    const r = previewTransaction(&edits);
    try std.testing.expect(!r.accepted);
    try std.testing.expectEqual(DifferentialOutcome.blocked, r.differential);
    try std.testing.expectEqual(MAX_EDITS, r.violations().len);
    try std.testing.expectEqual(@as(usize, 1), r.obligationsBroken().len);
    try std.testing.expectEqualStrings("obl.keyword.exact", r.obligationsBroken()[0]);
    try std.testing.expectEqual(r.obligations_before - 1, r.obligations_after);
}

test "semantic_transaction: empty preview leaves obligations unchanged" {
    const r = previewTransaction(&.{});
    try std.testing.expect(!r.accepted);
    try std.testing.expectEqual(DifferentialOutcome.blocked, r.differential);
    try std.testing.expectEqual(@as(usize, 1), r.violations().len);
    try std.testing.expectEqualStrings("TXN001", r.violations()[0].code);
    try std.testing.expectEqual(r.obligations_before, r.obligations_after);
    try std.testing.expectEqual(@as(usize, 0), r.obligationsBroken().len);
}

test "semantic_transaction: differential failures retain their exact case and obligation" {
    const validators = struct {
        fn mismatch() DifferentialError!void {
            return error.ClassifierMismatch;
        }

        fn falsePositive() DifferentialError!void {
            return error.FalsePositive;
        }
    };
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = token_semantic.intent.subject_entity,
        .value = "classifier.sorted_lookup",
    }};

    const mismatch = previewTransactionWithValidation(&edits, validators.mismatch);
    try std.testing.expect(!mismatch.accepted);
    try std.testing.expectEqual(DifferentialOutcome.classifier_mismatch, mismatch.differential);
    try std.testing.expectEqualStrings("TXN030", mismatch.violations()[0].code);
    try std.testing.expectEqual(@as(usize, 1), mismatch.obligationsBroken().len);
    try std.testing.expectEqualStrings("obl.keyword.exact", mismatch.obligationsBroken()[0]);
    var mismatch_json: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer mismatch_json.deinit();
    try writeResultJson(&mismatch_json.writer, &mismatch);
    try std.testing.expect(std.mem.indexOf(u8, mismatch_json.written(), "\"differential_outcome\":\"classifier_mismatch\"") != null);

    const false_positive = previewTransactionWithValidation(&edits, validators.falsePositive);
    try std.testing.expect(!false_positive.accepted);
    try std.testing.expectEqual(DifferentialOutcome.false_positive, false_positive.differential);
    try std.testing.expectEqualStrings("TXN030", false_positive.violations()[0].code);
    try std.testing.expectEqual(@as(usize, 1), false_positive.obligationsBroken().len);
    try std.testing.expectEqualStrings("obl.keyword.no_false_positive", false_positive.obligationsBroken()[0]);
}

test "semantic_transaction: rejected preview JSON preserves the refusal" {
    const edits = [_]Edit{.{
        .kind = .set_production_classifier,
        .target = token_semantic.intent.subject_entity,
        .value = "classifier.perfect_hash",
    }};
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePreviewJson(&buf.writer, &edits);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "semantic-transaction-v0") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"code\":\"TXN011\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"differential_outcome\":\"blocked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"differential_would_pass\":false") != null);
}
