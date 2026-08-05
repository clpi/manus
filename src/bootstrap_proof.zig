//! Pass 16 §19.5 / §22.8 — proof bundles for bootstrap and M1 integrated components.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const proof_carrying = @import("proof_carrying.zig");
const bootstrap_dag = @import("bootstrap_dag.zig");

pub const SCHEMA_VERSION = "bootstrap-proof-v0";

pub const BundleRecord = struct {
    bundle_id: []const u8,
    subject_entity: []const u8,
    bootstrap_stage: []const u8,
    status: []const u8,
    validation: []const u8,
    proof_path: ?[]const u8,
};

pub const bundles: []const BundleRecord = &.{
    .{
        .bundle_id = "bundle.m1.keyword_classifier",
        .subject_entity = "duo:lexer:keyword_classifier",
        .bootstrap_stage = "S0",
        .status = "supported",
        .validation = "Zig differential + examples/pass12_m1_diff.duo + examples/pass16_m1_lexer_proof.duo",
        .proof_path = "examples/pass12_m1_diff.duo",
    },
    .{
        .bundle_id = "bundle.bootstrap.s0",
        .subject_entity = "duo:bootstrap:s0",
        .bootstrap_stage = "S0",
        .status = "active",
        .validation = "zig build pass-gates; pinned Zig via mise",
        .proof_path = null,
    },
    .{
        .bundle_id = "bundle.m1.lexer_embed",
        .subject_entity = "duo:lexer:embed_smoke",
        .bootstrap_stage = "S0",
        .status = "partial",
        .validation = "examples/pass16_lexer_embed_proof.duo (Lexer.new) + pass16_lexer_tokenize_proof.duo (Lexer.next)",
        .proof_path = "examples/pass16_lexer_tokenize_proof.duo",
    },
    .{
        .bundle_id = "bundle.m1.lexer_corpus",
        .subject_entity = "duo:lexer:m1_corpus",
        .bootstrap_stage = "S0",
        .status = "supported",
        .validation = "src/lexer_differential.zig + examples/pass16_lexer_corpus_proof.duo + duo selfhost verify",
        .proof_path = "examples/pass16_lexer_corpus_proof.duo",
    },
    .{
        .bundle_id = "bundle.m1.source_cursor",
        .subject_entity = "duo:compiler:source_substrate",
        .bootstrap_stage = "S0",
        .status = "supported",
        .validation = "examples/pass16_source_cursor_proof.duo + src/source_cursor.zig + lexer ProductionCursor + duo selfhost verify",
        .proof_path = "examples/pass16_source_cursor_proof.duo",
    },
    .{
        .bundle_id = "bundle.m1.production_keyword_path",
        .subject_entity = "duo:production:keyword_classifier",
        .bootstrap_stage = "S0",
        .status = "partial",
        .validation = "lexer.zig → token_semantic.lookupKeyword + duo selfhost production + verify",
        .proof_path = "src/selfhost_production_path.zig",
    },
    .{
        .bundle_id = "bundle.cross_platform.target_matrix",
        .subject_entity = "duo:selfhost:target_matrix",
        .bootstrap_stage = "S0",
        .status = "supported",
        .validation = "selfhost_target_matrix.zig + CI pass16-cross-platform (ubuntu+macos)",
        .proof_path = "src/selfhost_target_matrix.zig",
    },
    .{
        .bundle_id = "bundle.bootstrap.s1",
        .subject_entity = "duo:bootstrap:s1",
        .bootstrap_stage = "S1",
        .status = "open",
        .validation = "stage_compare harness (P16-WS24)",
        .proof_path = null,
    },
};

pub fn writeBundlesJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    const snap = token_semantic.keywordSelectionSnapshot();
    try w.print("{{\"schema\":\"{s}\",\"current_stage\":\"{s}\",\"bundles\":[", .{
        SCHEMA_VERSION,
        bootstrap_dag.currentStageReached().label(),
    });
    for (bundles, 0..) |b, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"bundle_id\":\"{s}\",\"subject_entity\":\"{s}\",\"bootstrap_stage\":\"{s}\",\"status\":\"{s}\",\"validation\":\"{s}\",\"proof_path\":",
            .{ b.bundle_id, b.subject_entity, b.bootstrap_stage, b.status, b.validation },
        );
        if (b.proof_path) |p| try w.print("\"{s}\"", .{p}) else try w.writeAll("null");
        try w.writeAll("}");
    }
    try w.writeAll("],\"m1_keyword\":");
    try w.print(
        "{{\"production_classifier\":\"{s}\",\"differential_pass\":{},\"legal_candidates\":{d},\"compared_candidates\":{d},\"obligations\":{d}}}",
        .{
            snap.selected.name(),
            snap.differential_pass,
            snap.legal_candidates,
            snap.compared_candidates,
            token_semantic.proof_obligations.len,
        },
    );
    try w.writeAll(",\"release_claims\":[");
    var first = true;
    for (proof_carrying.seed_claims) |c| {
        if (c.proof_bundle_id == null) continue;
        if (!first) try w.writeAll(",");
        first = false;
        try w.print(
            "{{\"id\":\"{s}\",\"status\":\"{s}\",\"proof_bundle_id\":\"{s}\"}}",
            .{ c.id, c.status.name(), c.proof_bundle_id.? },
        );
    }
    try w.writeAll("]}");
}

test "bootstrap_proof: m1 bundle linked" {
    var found = false;
    for (bundles) |b| {
        if (std.mem.eql(u8, b.bundle_id, "bundle.m1.keyword_classifier")) found = true;
    }
    try std.testing.expect(found);
}
