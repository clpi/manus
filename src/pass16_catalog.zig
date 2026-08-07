//! Pass 16 — self-hosted compiler supremacy catalog (`duo catalog` → `pass16`).
const std = @import("std");
const bootstrap_dag = @import("bootstrap_dag.zig");
const selfhosting_matrix = @import("selfhosting_matrix.zig");
const pass16_selfhost_audit = @import("pass16_selfhost_audit.zig");

pub const SCHEMA_VERSION = "pass16-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass16_self_hosted_compiler.md";
pub const BOOTSTRAP_DOC = "docs/bootstrap.md";
pub const M1_PROOF_PATH = "examples/pass16_m1_lexer_proof.duo";

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    owner: []const u8,
};

/// Pass 16 §23 — thirty bounded workstreams.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P16-WS1", .title = "Source substrate and incremental source identities", .status = "partial", .priority = 1, .owner = "lib/std/compiler/source.duo" },
    .{ .id = "P16-WS2", .title = "Native byte slices and cursors", .status = "partial", .priority = 2, .owner = "lib/std/compiler/source.duo" },
    .{ .id = "P16-WS3", .title = "Token and grammar descriptor", .status = "partial", .priority = 3, .owner = "src/token_semantic.zig + lib/std/token/classify.duo" },
    .{ .id = "P16-WS4", .title = "Duo-native lexer", .status = "partial", .priority = 4, .owner = "lib/std/compiler/lexer.duo" },
    .{ .id = "P16-WS5", .title = "Syntax graph", .status = "open", .priority = 5, .owner = "future" },
    .{ .id = "P16-WS6", .title = "Duo-native parser", .status = "partial", .priority = 6, .owner = "lib/std/compiler/parser.duo" },
    .{ .id = "P16-WS7", .title = "Formatter and canonicalizer convergence", .status = "open", .priority = 7, .owner = "src/fmt.zig" },
    .{ .id = "P16-WS8", .title = "Diagnostic catalog and renderer", .status = "open", .priority = 8, .owner = "src/term.zig" },
    .{ .id = "P16-WS9", .title = "Binding and scope graph", .status = "open", .priority = 9, .owner = "src/sema.zig" },
    .{ .id = "P16-WS10", .title = "Descriptor and shape engine", .status = "open", .priority = 10, .owner = "src/semantic_graph.zig" },
    .{ .id = "P16-WS11", .title = "Compile-time evaluator", .status = "open", .priority = 11, .owner = "src/comptime.zig" },
    .{ .id = "P16-WS12", .title = "Semantic query and incremental cache", .status = "open", .priority = 12, .owner = "src/semantic_context.zig" },
    .{ .id = "P16-WS13", .title = "Transformation registry", .status = "partial", .priority = 13, .owner = "src/transform_engine.zig" },
    .{ .id = "P16-WS14", .title = "Return-pack and closure specialization", .status = "open", .priority = 14, .owner = "future" },
    .{ .id = "P16-WS15", .title = "Representation selection", .status = "open", .priority = 15, .owner = "future" },
    .{ .id = "P16-WS16", .title = "Low-level IR", .status = "open", .priority = 16, .owner = "future" },
    .{ .id = "P16-WS17", .title = "Machine IR", .status = "open", .priority = 17, .owner = "future" },
    .{ .id = "P16-WS18", .title = "Register allocation", .status = "open", .priority = 18, .owner = "future" },
    .{ .id = "P16-WS19", .title = "AArch64 lowering", .status = "partial", .priority = 19, .owner = "src/native_backend.zig" },
    .{ .id = "P16-WS20", .title = "x86-64 lowering", .status = "open", .priority = 20, .owner = "future" },
    .{ .id = "P16-WS21", .title = "Object writers", .status = "partial", .priority = 21, .owner = "src/native_backend.zig" },
    .{ .id = "P16-WS22", .title = "Runtime profile minimization", .status = "open", .priority = 22, .owner = "src/pass4_catalog.zig" },
    .{ .id = "P16-WS23", .title = "Bootstrap orchestration", .status = "partial", .priority = 23, .owner = "src/bootstrap_dag.zig + build.zig" },
    .{ .id = "P16-WS24", .title = "Stage comparison and reproducibility", .status = "open", .priority = 24, .owner = "src/bootstrap_dag.zig" },
    .{ .id = "P16-WS25", .title = "LSP compiler-service integration", .status = "open", .priority = 25, .owner = "~/x/duo-lsp" },
    .{ .id = "P16-WS26", .title = "MCP semantic-service integration", .status = "open", .priority = 26, .owner = "~/x/duo-mcp" },
    .{ .id = "P16-WS27", .title = "Compiler performance instrumentation", .status = "open", .priority = 27, .owner = "docs/performance.md" },
    .{ .id = "P16-WS28", .title = "Host-path retirement and repository cleanup", .status = "open", .priority = 28, .owner = "src/selfhosting_matrix.zig" },
    .{ .id = "P16-WS29", .title = "Ward validation of compiler foundations", .status = "partial", .priority = 29, .owner = "examples/pass9/*" },
    .{ .id = "P16-WS30", .title = "Release-proof integration", .status = "open", .priority = 30, .owner = "src/proof_carrying.zig" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    level: u8,
};

pub const milestones: []const Milestone = &.{
    .{ .id = "P16-M0", .title = "Level 0 truth map + audits + bootstrap DAG", .status = "done", .level = 0 },
    .{
        .id = "P16-M1",
        .title = "Production Duo frontend component (lexer kernel)",
        .status = "partial",
        .level = 1,
    },
    .{ .id = "P16-M2", .title = "Duo-native semantic front end + snapshots", .status = "open", .level = 2 },
    .{ .id = "P16-M3", .title = "Self-hosted native loop on one target", .status = "open", .level = 4 },
    .{ .id = "P16-M4", .title = "Bootstrap closure S0→S2", .status = "open", .level = 5 },
    .{ .id = "P16-M5", .title = "Cross-target parity matrix + host-aware gate", .status = "partial", .level = 6 },
};

pub const CompletionLevel = struct {
    level: u8,
    title: []const u8,
    status: []const u8,
};

pub const completion_levels: []const CompletionLevel = &.{
    .{ .level = 0, .title = "Truth", .status = "done" },
    .{ .level = 1, .title = "Production Duo frontend component", .status = "partial" },
    .{ .level = 2, .title = "Duo-native frontend", .status = "open" },
    .{ .level = 3, .title = "Duo-native optimizing middle end", .status = "open" },
    .{ .level = 4, .title = "Duo-native backend on one target", .status = "open" },
    .{ .level = 5, .title = "Bootstrap closure", .status = "open" },
    .{ .level = 6, .title = "Cross-target self-hosting", .status = "open" },
    .{ .level = 7, .title = "Compiler supremacy", .status = "open" },
    .{ .level = 8, .title = "Living self-improving compiler", .status = "open" },
};

pub const AcceptanceCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 16 §25 — acceptance criteria (subset tracked in catalog).
pub const acceptance_criteria: []const AcceptanceCriterion = &.{
    .{ .id = 1, .title = "Canonical compiler implemented in Duo", .status = "open" },
    .{ .id = 2, .title = "Reproducible bootstrap chain S0→S2", .status = "open" },
    .{ .id = 3, .title = "Self-hosted compiler used for normal release compilation", .status = "open" },
    .{ .id = 4, .title = "No external compiler on canonical direct path", .status = "open" },
    .{ .id = 5, .title = "No hidden generated C or Lua on canonical path", .status = "open" },
    .{ .id = 6, .title = "Semantic graph owns compiler meaning", .status = "partial" },
    .{ .id = 7, .title = "CLI/LSP/MCP consume shared compiler facts", .status = "open" },
    .{ .id = 10, .title = "Compiler self-rebuild on declared target", .status = "open" },
    .{ .id = 13, .title = "Dynamic boundaries enumerable on compiler artifact", .status = "partial" },
    .{ .id = 22, .title = "Self-hosting reduced duplication vs host architecture", .status = "partial" },
};

pub fn writePass16Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    const m = selfhosting_matrix.publicManifest();
    try w.print(
        \\"pass16":{{"pass":16,"mission":"Self-hosted compiler supremacy, bootstrap closure, compiler-as-proof","schema":"{s}","plan":"{s}","bootstrap_doc":"{s}","m1_proof":"{s}","selfhosting_matrix_schema":"{s}","bootstrap_dag_schema":"{s}","workstreams":[
    , .{
        SCHEMA_VERSION,
        PLAN_PATH,
        BOOTSTRAP_DOC,
        M1_PROOF_PATH,
        selfhosting_matrix.SCHEMA_VERSION,
        bootstrap_dag.SCHEMA_VERSION,
    });
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"priority\":{d},\"owner\":\"{s}\"}}", .{
            ws.id, ws.title, ws.status, ws.priority, ws.owner,
        });
    }
    try w.writeAll("],\"milestones\":[");
    for (milestones, 0..) |ms, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"level\":{d}}}", .{
            ms.id, ms.title, ms.status, ms.level,
        });
    }
    try w.writeAll("],\"completion_levels\":[");
    for (completion_levels, 0..) |cl, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"level\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ cl.level, cl.title, cl.status });
    }
    try w.writeAll("],\"acceptance\":[");
    for (acceptance_criteria, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ c.id, c.title, c.status });
    }
    try w.writeAll("],\"manifest\":");
    try w.print(
        "{{\"self_hosting_level\":{d},\"canonical_compiler_in_duo\":{},\"bootstrap_stage\":\"{s}\",\"production_duo_frontend\":{},\"silent_c_fallback\":{},\"claim_self_hosted_status\":\"{s}\"}}",
        .{ m.self_hosting_level, m.canonical_compiler_in_duo, m.bootstrap_stage_reached, m.production_duo_frontend, m.silent_c_fallback, m.claim_self_hosted_status },
    );
    try w.writeAll(",\"selfhosting_matrix\":");
    try selfhosting_matrix.writeMatrixJson(w);
    try w.writeAll(",\"bootstrap_dag\":");
    try bootstrap_dag.writeBootstrapDagJson(w);
    try w.writeAll(",\"bootstrap_subset\":");
    try @import("bootstrap_subset.zig").writeSubsetJson(w);
    try w.writeAll(",\"dynamic_boundary\":");
    try @import("compiler_dynamic_boundary.zig").writeReportJson(w);
    try w.writeAll(",\"capability_matrix\":");
    try @import("compiler_capability_matrix.zig").writeMatrixJson(w);
    try w.writeAll(",\"removal_ledger\":");
    try @import("removal_ledger.zig").writeLedgerJson(w);
    try w.writeAll(",\"semantic_compression\":");
    try @import("semantic_compression_report.zig").writeReportJson(w);
    try w.writeAll(",\"perf_baseline\":");
    try @import("compiler_perf_baseline.zig").writeBaselineJson(w);
    try w.writeAll(",\"proof_bundles\":");
    try @import("bootstrap_proof.zig").writeBundlesJson(w, alloc);
    try w.writeAll(",\"stage_compare\":");
    try @import("stage_compare.zig").writeCompareJson(w);
    try w.writeAll(",\"target_matrix\":");
    try @import("selfhost_target_matrix.zig").writeMatrixJson(w);
    try w.writeAll(",\"production_path\":");
    try @import("selfhost_production_path.zig").writeProductionPathJson(w);
    try w.writeAll(",\"migration_plan\":");
    try @import("selfhost_migration_plan.zig").writePlanJson(w);
    try w.writeAll(",\"audits\":");
    try pass16_selfhost_audit.writeAuditSummaryJson(w);
    try w.writeAll("}");
}

test "pass16_catalog: writePass16Json structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass16Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass16\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P16-WS4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "self_hosting_level") != null);
}
