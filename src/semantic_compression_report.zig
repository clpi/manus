//! Pass 16 §22.6 — semantic compression: canonical facts vs derived projections.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");

pub const SCHEMA_VERSION = "semantic-compression-v0";

pub const CompressionFact = struct {
    id: []const u8,
    canonical_owner: []const u8,
    fact_kind: []const u8,
    projection_count: u8,
    projections: []const []const u8,
    duplicated_legacy: ?[]const u8,
};

pub const facts: []const CompressionFact = &.{
    .{
        .id = "SC-01",
        .canonical_owner = "src/token_semantic.zig",
        .fact_kind = "keyword table + classifier",
        .projection_count = 6,
        .projections = &.{
            "src/lexer.zig lookupKeyword (production)",
            "lib/std/token/classify.duo (generated)",
            "duo semantic compare",
            "duo selfhost verify",
            "LSP hover (planned)",
            "MCP entity (planned)",
        },
        .duplicated_legacy = "TokenKind enum spellings parallel table; unified via entryForKind",
    },
    .{
        .id = "SC-02",
        .canonical_owner = "src/wasm_semantic.zig",
        .fact_kind = "wasm opcode decode",
        .projection_count = 3,
        .projections = &.{
            "lib/std/wasm/opcode_lookup.duo",
            "lib/std/wasm/ward_mvp_opcodes.duo",
            "duo semantic intent/compare",
        },
        .duplicated_legacy = null,
    },
    .{
        .id = "SC-03",
        .canonical_owner = "src/selfhosting_matrix.zig",
        .fact_kind = "compiler subsystem ownership",
        .projection_count = 3,
        .projections = &.{
            "duo catalog pass16",
            "duo selfhost matrix",
            "development MCP (planned)",
        },
        .duplicated_legacy = "Handwritten pass plans partially superseded by matrix",
    },
};

pub fn totalProjections() usize {
    var n: usize = 0;
    for (facts) |f| n += f.projection_count;
    return n;
}

pub fn writeReportJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"keyword_count\":{d},\"token_semantic_projections\":{d},\"facts\":[", .{
        SCHEMA_VERSION,
        token_semantic.keywords.len,
        token_semantic.projections.len,
    });
    for (facts, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"canonical_owner\":\"{s}\",\"fact_kind\":\"{s}\",\"projection_count\":{d},\"projections\":[",
            .{ f.id, f.canonical_owner, f.fact_kind, f.projection_count },
        );
        for (f.projections, 0..) |p, j| {
            if (j > 0) try w.writeAll(",");
            try w.print("\"{s}\"", .{p});
        }
        try w.writeAll("],\"duplicated_legacy\":");
        if (f.duplicated_legacy) |d| {
            try w.print("\"{s}\"", .{d});
        } else {
            try w.writeAll("null");
        }
        try w.writeAll("}");
    }
    try w.print("],\"summary\":{{\"canonical_facts\":{d},\"total_projections\":{d}}}}}", .{
        facts.len,
        totalProjections(),
    });
}

test "semantic_compression_report: facts tracked" {
    try std.testing.expect(facts.len >= 2);
    try std.testing.expect(totalProjections() >= 6);
}
