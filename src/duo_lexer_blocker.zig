//! Pass 16 MP-04 — structured blockers for Duo-native lexer production dispatch.
const std = @import("std");

pub const SCHEMA_VERSION = "duo-lexer-blocker-v0";

pub const Blocker = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    evidence: []const u8,
    proof_path: ?[]const u8,
    removal_gate: []const u8,
};

pub const blockers: []const Blocker = &.{
    .{
        .id = "MP4-B01",
        .title = "Embedded req Lexer.next() — record thunk + runtime",
        .status = "proven",
        .evidence = "codegen: native record params by pointer + lua thunk write-back; pass16_lexer_tokenize_proof.duo compiles and returns 0 (fun + EOF)",
        .proof_path = "examples/pass16_lexer_tokenize_proof.duo",
        .removal_gate = "pass16_lexer_tokenize_proof exit 0; pass16-m1-smoke green",
    },
    .{
        .id = "MP4-B02",
        .title = "Production dispatch still src/lexer.zig",
        .status = "partial",
        .evidence = "duo_lexer_bridge.zig wires keyword leg + documents split; tokenize remains host until C projection",
        .proof_path = "src/duo_lexer_bridge.zig",
        .removal_gate = "duo_lexer_tokenize.c or explicit production switch; host becomes oracle-only",
    },
    .{
        .id = "MP4-B03",
        .title = "Token kind ID parity host/Duo",
        .status = "proven",
        .evidence = "duo_keyword_classify.c + lib/std/compiler/token.duo KIND_* align with TokenKind enum",
        .proof_path = "src/lexer_differential.zig",
        .removal_gate = "N/A — maintain on grammar changes",
    },
};

pub fn embedSmokeProofPath() []const u8 {
    return "examples/pass16_lexer_embed_proof.duo";
}

pub fn writeBlockersJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"blockers\":[", .{SCHEMA_VERSION});
    for (blockers, 0..) |b, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"evidence\":\"{s}\",\"proof_path\":",
            .{ b.id, b.title, b.status, b.evidence },
        );
        if (b.proof_path) |p| try w.print("\"{s}\"", .{p}) else try w.writeAll("null");
        try w.print(",\"removal_gate\":\"{s}\"}}", .{b.removal_gate});
    }
    try w.writeAll("]}");
}

test "duo_lexer_blocker: tracked" {
    try std.testing.expect(blockers.len >= 3);
}
