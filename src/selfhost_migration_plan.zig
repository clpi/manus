//! Pass 16 §22.7 — dependency-ordered, bounded, claimable migration work items.
const std = @import("std");

pub const SCHEMA_VERSION = "selfhost-migration-plan-v0";

pub const ItemStatus = enum {
    done,
    partial,
    open,
    blocked,

    pub fn name(self: ItemStatus) []const u8 {
        return @tagName(self);
    }
};

pub const MigrationItem = struct {
    id: []const u8,
    title: []const u8,
    workstream: []const u8,
    subsystem_id: []const u8,
    status: ItemStatus,
    depends_on: []const []const u8,
    owner: []const u8,
    validation: []const u8,
    removal_implication: ?[]const u8,
};

/// §13 migration order — bounded items agents can claim without "implement self-hosting."
pub const items: []const MigrationItem = &.{
    .{ .id = "MP-01", .title = "Production path manifest + explicit fallback disclosure", .workstream = "P16-WS30", .subsystem_id = "SH-14", .status = .done, .depends_on = &.{}, .owner = "src/selfhost_production_path.zig", .validation = "duo selfhost production; pass16-gate", .removal_implication = null },
    .{ .id = "MP-02", .title = "Keyword semantic source wired to production lexer", .workstream = "P16-WS3", .subsystem_id = "SH-02", .status = .done, .depends_on = &.{}, .owner = "src/duo_keyword_bridge.zig + src/duo_keyword_classify.c", .validation = "duo selfhost verify; pass16-gate; differential proofs", .removal_implication = "token_semantic branch_chain → oracle-only" },
    .{ .id = "MP-03", .title = "Duo-native source substrate in production lexer", .workstream = "P16-WS1", .subsystem_id = "SH-01", .status = .done, .depends_on = &.{"MP-02"}, .owner = "src/source_cursor.zig", .validation = "ProductionCursor in src/lexer.zig + differentialProductionParity + pass16_source_cursor_proof.duo", .removal_implication = "inline pos/line/col in lexer.zig" },
    .{ .id = "MP-04", .title = "Duo-native lexer kernel production dispatch", .workstream = "P16-WS4", .subsystem_id = "SH-03", .status = .partial, .depends_on = &.{"MP-03"}, .owner = "lib/std/compiler/lexer.duo + src/duo_lexer_bridge.zig", .validation = "lexer_differential + pass16_lexer_embed/tokenize + duo selfhost lexer-bridge", .removal_implication = "src/lexer.zig tokenization paths → oracle-only" },
    .{ .id = "MP-05", .title = "Grammar descriptor drives formatter + LSP projections", .workstream = "P16-WS7", .subsystem_id = "SH-05", .status = .open, .depends_on = &.{"MP-04"}, .owner = "src/token_semantic.zig", .validation = "Single canonical fact → 3+ projections", .removal_implication = "parallel fmt/LSP token tables" },
    .{ .id = "MP-06", .title = "Duo-native parser kernel (bounded subset)", .workstream = "P16-WS6", .subsystem_id = "SH-04", .status = .open, .depends_on = &.{"MP-04"}, .owner = "future syntax graph", .validation = "Positive + compile-fail corpus differential", .removal_implication = null },
    .{ .id = "MP-07", .title = "Semantic graph snapshots for compiler modules", .workstream = "P16-WS10", .subsystem_id = "SH-07", .status = .open, .depends_on = &.{"MP-06"}, .owner = "src/semantic_graph.zig", .validation = "P16-M2 stable IDs + incremental invalidation", .removal_implication = null },
    .{ .id = "MP-08", .title = "S1 compiler artifact from S0 bootstrap", .workstream = "P16-WS23", .subsystem_id = "SH-14", .status = .open, .depends_on = &.{"MP-04", "MP-06"}, .owner = "build.zig + bootstrap_dag", .validation = "S0 builds S1; stage_compare CMP-S0-S1", .removal_implication = null },
    .{ .id = "MP-09", .title = "Bootstrap closure S1→S2 behavioral equivalence", .workstream = "P16-WS24", .subsystem_id = "SH-14", .status = .open, .depends_on = &.{"MP-08"}, .owner = "src/stage_compare.zig", .validation = "Semantic fingerprints + test matrix", .removal_implication = "Zig seed optional after S2 canonical" },
    .{ .id = "MP-10", .title = "Duo-native backend loop on aarch64-macos", .workstream = "P16-WS19", .subsystem_id = "SH-11", .status = .open, .depends_on = &.{"MP-07"}, .owner = "src/native_backend.zig", .validation = "P16-M3; no hidden generated-C on declared path", .removal_implication = "codegen.zig canonical C path for proven subset" },
    .{ .id = "MP-11", .title = "Compiler phase perf instrumentation", .workstream = "P16-WS27", .subsystem_id = "SH-14", .status = .partial, .depends_on = &.{}, .owner = "src/compiler_perf_measure.zig", .validation = "duo selfhost perf measure; CP-04 measured", .removal_implication = null },
    .{ .id = "MP-12", .title = "LSP shared compiler service", .workstream = "P16-WS25", .subsystem_id = "SH-15", .status = .open, .depends_on = &.{"MP-07"}, .owner = "~/x/duo-lsp", .validation = "No separate LSP parser for Duo subset", .removal_implication = null },
    .{ .id = "MP-13", .title = "Development MCP self-hosting state", .workstream = "P16-WS26", .subsystem_id = "SH-16", .status = .open, .depends_on = &.{"MP-01"}, .owner = "~/x/duo-mcp", .validation = "Bootstrap stages + proof bundles exposed", .removal_implication = null },
};

pub fn writePlanJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"items\":[", .{SCHEMA_VERSION});
    for (items, 0..) |item, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"workstream\":\"{s}\",\"subsystem_id\":\"{s}\",\"status\":\"{s}\",\"depends_on\":[",
            .{ item.id, item.title, item.workstream, item.subsystem_id, item.status.name() },
        );
        for (item.depends_on, 0..) |dep, di| {
            if (di > 0) try w.writeAll(",");
            try w.print("\"{s}\"", .{dep});
        }
        try w.print("],\"owner\":\"{s}\",\"validation\":\"{s}\",\"removal_implication\":", .{
            item.owner, item.validation,
        });
        if (item.removal_implication) |r| try w.print("\"{s}\"", .{r}) else try w.writeAll("null");
        try w.writeAll("}");
    }
    try w.writeAll("]}");
}

test "selfhost_migration_plan: ordered items" {
    try std.testing.expect(items.len >= 10);
    try std.testing.expect(std.mem.eql(u8, items[0].id, "MP-01"));
}
