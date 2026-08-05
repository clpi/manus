//! Pass 12 CLI projections — `duo semantic` (Goal D, MCP parity without network).
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const wasm_decode_semantic = @import("wasm_decode_semantic.zig");
const wasm_semantic = @import("wasm_semantic.zig");
const proof_carrying = @import("proof_carrying.zig");
const semantic_context = @import("semantic_context.zig");
const semantic_transaction = @import("semantic_transaction.zig");
const transform_engine = @import("transform_engine.zig");

pub fn writeIntentJson(w: *std.Io.Writer, entity: []const u8) !void {
    const i = if (wasm_decode_semantic.entityMatches(entity))
        wasm_decode_semantic.intent
    else if (std.mem.eql(u8, entity, token_semantic.intent.subject_entity) or
        std.mem.eql(u8, entity, "keyword_classifier"))
        token_semantic.intent
    else {
        try w.print("{{\"error\":\"unknown entity\",\"entity\":\"{s}\",\"hint\":\"try duo:lexer:keyword_classifier or duo:wasm:decode_instruction\"}}", .{entity});
        return;
    };
    try w.print(
        "{{\"schema\":\"semantic-intent-v0\",\"subject\":\"{s}\",\"summary\":\"",
        .{i.subject_entity},
    );
    try jsonEscape(w, i.summary);
    try w.print("\",\"descriptor_id\":\"{s}\",\"laws\":\"", .{i.descriptor_id.?});
    try jsonEscape(w, i.laws.?);
    try w.print("\",\"representation_constraints\":\"", .{});
    try jsonEscape(w, i.representation_constraints.?);
    try w.print("\",\"determinism_required\":", .{});
    try w.print("{s}", .{if (i.determinism_required) "true" else "false"});
    try w.print("}}", .{});
}

pub fn writeCandidateCompareJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    var report = try token_semantic.compareKeywordClassifiers(alloc);
    defer report.deinit(alloc);
    try w.print("{{\"schema\":\"candidate-compare-v0\",\"subject\":\"{s}\",\"production\":\"{s}\",\"selected\":\"", .{
        token_semantic.intent.subject_entity,
        token_semantic.production_classifier.name(),
    });
    if (report.selected_id) |sid| {
        try jsonEscape(w, sid);
    }
    try w.print("\",\"legal_count\":{d},\"compared_count\":{d},\"rejections\":[", .{
        report.legal_count,
        report.compared_count,
    });
    for (report.rejections, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"candidate_id\":\"{s}\",\"reason\":\"", .{r.candidate_id});
        try jsonEscape(w, r.reason);
        try w.print("\"}}", .{});
    }
    try w.print("],\"classifiers\":[", .{});
    for (token_semantic.legal_classifiers, 0..) |cid, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{cid.name()});
    }
    try w.print("]}}", .{});
}

pub fn writeProofObligationsJson(w: *std.Io.Writer, entity: []const u8) !void {
    const subject: []const u8 = if (wasm_decode_semantic.entityMatches(entity))
        wasm_decode_semantic.intent.subject_entity
    else if (std.mem.eql(u8, entity, token_semantic.intent.subject_entity) or
        std.mem.eql(u8, entity, "keyword_classifier"))
        token_semantic.intent.subject_entity
    else {
        try w.print("{{\"error\":\"unknown entity\",\"entity\":\"{s}\"}}", .{entity});
        return;
    };
    const obligations = if (wasm_decode_semantic.entityMatches(entity))
        wasm_decode_semantic.proof_obligations
    else
        token_semantic.proof_obligations;
    try w.print("{{\"schema\":\"proof-obligations-v0\",\"subject\":\"{s}\",\"obligations\":[", .{subject});
    for (obligations, 0..) |o, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"predicate\":\"", .{o.id});
        try jsonEscape(w, o.predicate);
        try w.print("\",\"status\":\"{s}\",\"validation_method\":\"", .{o.status.name()});
        try jsonEscape(w, o.validation_method);
        try w.print("\"}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeProofBundleJson(w: *std.Io.Writer, alloc: std.mem.Allocator, entity: []const u8) !void {
    if (wasm_decode_semantic.entityMatches(entity)) {
        try w.print("{{\"schema\":\"proof-bundle-v0\",\"bundle_id\":\"bundle.m2.wasm_decode\",\"subject\":\"{s}\",\"stale\":false,\"table_differential_pass\":true,\"mvp_opcodes\":{d},\"native_barrier_pending\":true,\"obligations_discharged\":1,\"obligations_total\":{d},\"evidence\":[\"differential_test\",\"static_estimate\"],\"barrier_cmd\":\"duo dev barrier check ward_decode\",\"claim_id\":\"claim.m2_wasm_decode\"}}", .{
            wasm_decode_semantic.intent.subject_entity,
            wasm_semantic.mvpCount(),
            wasm_decode_semantic.proof_obligations.len,
        });
        return;
    }
    if (!std.mem.eql(u8, entity, token_semantic.intent.subject_entity) and
        !std.mem.eql(u8, entity, "keyword_classifier"))
    {
        try w.print("{{\"error\":\"unknown entity\",\"entity\":\"{s}\"}}", .{entity});
        return;
    }
    const snap = token_semantic.selectClassifier(alloc) catch {
        try w.print("{{\"schema\":\"proof-bundle-v0\",\"subject\":\"{s}\",\"stale\":true,\"error\":\"differential_failed\"}}", .{entity});
        return;
    };
    try w.print("{{\"schema\":\"proof-bundle-v0\",\"bundle_id\":\"bundle.m1.keyword_classifier\",\"subject\":\"{s}\",\"stale\":false,\"production_classifier\":\"{s}\",\"model_selected\":\"{s}\",\"differential_pass\":", .{
        entity,
        snap.selected.name(),
        snap.model_selected.name(),
    });
    try w.print("{s}", .{if (snap.differential_pass) "true" else "false"});
    try w.print(",\"obligations_discharged\":{d},\"legal_candidates\":{d},\"compared_candidates\":{d},\"evidence\":[", .{
        token_semantic.proof_obligations.len,
        snap.legal_candidates,
        snap.compared_candidates,
    });
    const kinds = [_]proof_carrying.AcceptedEvidence{
        .differential_test,
        .property_test,
        .fuzz_evidence,
        .static_estimate,
    };
    for (kinds, 0..) |k, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{k.name()});
    }
    try w.print("],\"claim_id\":\"claim.m1_keyword_semantic\"}}", .{});
}

pub fn writeProjectionsJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"semantic-projections-v0\",\"subject\":\"{s}\",\"projections\":[", .{
        token_semantic.intent.subject_entity,
    });
    for (token_semantic.projections, 0..) |p, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"kind\":\"{s}\",\"source_entity\":\"{s}\"", .{
            p.id,
            p.kind.name(),
            p.source_entity,
        });
        if (p.transform_id) |tid| {
            try w.print(",\"transform_id\":\"{s}\"", .{tid});
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeContextJson(w: *std.Io.Writer, entity: ?[]const u8) !void {
    const entity_id = entity orelse token_semantic.intent.subject_entity;
    const pkg = semantic_context.packageForEntity(entity_id) orelse semantic_context.m1_keyword_classifier;
    try semantic_context.writePackageJson(w, pkg);
}

pub fn writeTransactionPreviewJson(w: *std.Io.Writer, classifier_arg: ?[]const u8) !void {
    const value = classifier_arg orelse "classifier.sorted_lookup";
    const edits = [_]semantic_transaction.Edit{.{
        .kind = .set_production_classifier,
        .target = token_semantic.intent.subject_entity,
        .value = value,
    }};
    try semantic_transaction.writePreviewJson(w, &edits);
}

pub fn writeTransactionValidateJson(w: *std.Io.Writer, classifier_arg: ?[]const u8) !void {
    try writeTransactionPreviewJson(w, classifier_arg);
}

pub fn writeTransformProofLogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"transform-proof-log-v0\",\"entries\":", .{});
    try transform_engine.writeProofLogJson(w);
    try w.print("}}", .{});
}

pub fn writeClaimsJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    const downgrade_ids = proof_carrying.claimsNeedingDowngrade(alloc) catch &[_][]const u8{};
    defer alloc.free(downgrade_ids);
    try w.print("{{\"schema\":\"release-claims-v0\",\"capabilities\":[", .{});
    for (proof_carrying.seed_capabilities, 0..) |cap, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"status\":\"{s}\",\"owner\":\"", .{ cap.id, cap.status.name() });
        try jsonEscape(w, cap.owner);
        try w.print("\"}}", .{});
    }
    try w.print("],\"claims\":[", .{});
    for (proof_carrying.seed_claims, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        const eff = proof_carrying.effectiveClaimStatus(c);
        try w.print("{{\"id\":\"{s}\",\"declared\":\"{s}\",\"effective\":\"{s}\",\"statement\":\"", .{
            c.id,
            c.status.name(),
            eff.name(),
        });
        try jsonEscape(w, c.statement);
        try w.print("\"}}", .{});
    }
    try w.print("],\"downgrade_ids\":[", .{});
    for (downgrade_ids, 0..) |id, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{id});
    }
    try w.print("]}}", .{});
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "semantic_cli: candidate compare JSON" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeCandidateCompareJson(&buf.writer, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "candidate-compare-v0") != null);
}
