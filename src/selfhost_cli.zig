//! Pass 16 CLI — `duo selfhost` introspection (§22 deliverables, MCP parity without network).
const std = @import("std");
const selfhosting_matrix = @import("selfhosting_matrix.zig");
const bootstrap_dag = @import("bootstrap_dag.zig");
const bootstrap_subset = @import("bootstrap_subset.zig");
const pass16_selfhost_audit = @import("pass16_selfhost_audit.zig");
const compiler_dynamic_boundary = @import("compiler_dynamic_boundary.zig");
const compiler_capability_matrix = @import("compiler_capability_matrix.zig");
const removal_ledger = @import("removal_ledger.zig");
const pass16_catalog = @import("pass16_catalog.zig");
const semantic_cli = @import("semantic_cli.zig");
const selfhost_verify = @import("selfhost_verify.zig");
const semantic_compression_report = @import("semantic_compression_report.zig");
const compiler_perf_baseline = @import("compiler_perf_baseline.zig");
const compiler_perf_measure = @import("compiler_perf_measure.zig");
const bootstrap_proof = @import("bootstrap_proof.zig");
const stage_compare = @import("stage_compare.zig");
const selfhost_target_matrix = @import("selfhost_target_matrix.zig");
const selfhost_production_path = @import("selfhost_production_path.zig");
const selfhost_migration_plan = @import("selfhost_migration_plan.zig");

pub fn writeManifestJson(w: *std.Io.Writer) !void {
    const m = selfhosting_matrix.publicManifest();
    try w.print(
        "{{\"schema\":\"selfhost-manifest-v0\",\"pass\":16,\"plan\":\"{s}\",\"self_hosting_level\":{d},\"bootstrap_stage\":\"{s}\",\"canonical_compiler_in_duo\":{},\"production_duo_frontend\":{},\"silent_c_fallback\":{},\"claim_self_hosted_status\":\"{s}\",\"m1_proof\":\"{s}\"}}",
        .{
            pass16_catalog.PLAN_PATH,
            m.self_hosting_level,
            m.bootstrap_stage_reached,
            m.canonical_compiler_in_duo,
            m.production_duo_frontend,
            m.silent_c_fallback,
            m.claim_self_hosted_status,
            pass16_catalog.M1_PROOF_PATH,
        },
    );
}

pub fn dispatch(w: *std.Io.Writer, alloc: std.mem.Allocator, sub: []const u8) !void {
    if (std.mem.eql(u8, sub, "manifest")) {
        try writeManifestJson(w);
    } else if (std.mem.eql(u8, sub, "matrix")) {
        try selfhosting_matrix.writeMatrixJson(w);
    } else if (std.mem.eql(u8, sub, "bootstrap")) {
        try bootstrap_dag.writeBootstrapDagJson(w);
    } else if (std.mem.eql(u8, sub, "subset")) {
        try bootstrap_subset.writeSubsetJson(w);
    } else if (std.mem.eql(u8, sub, "audits")) {
        try pass16_selfhost_audit.writeAuditSummaryJson(w);
    } else if (std.mem.eql(u8, sub, "boundary")) {
        try compiler_dynamic_boundary.writeReportJson(w);
    } else if (std.mem.eql(u8, sub, "capabilities")) {
        try compiler_capability_matrix.writeMatrixJson(w);
    } else if (std.mem.eql(u8, sub, "ledger")) {
        try removal_ledger.writeLedgerJson(w);
    } else if (std.mem.eql(u8, sub, "catalog")) {
        try pass16_catalog.writePass16Json(w, alloc);
    } else if (std.mem.eql(u8, sub, "compare") or std.mem.eql(u8, sub, "keywords")) {
        try semantic_cli.writeCandidateCompareJson(w, alloc);
    } else if (std.mem.eql(u8, sub, "verify")) {
        try selfhost_verify.writeVerifyJson(w);
    } else if (std.mem.eql(u8, sub, "compression")) {
        try semantic_compression_report.writeReportJson(w);
    } else if (std.mem.eql(u8, sub, "perf") or std.mem.eql(u8, sub, "baseline")) {
        try compiler_perf_baseline.writeBaselineJson(w);
    } else if (std.mem.eql(u8, sub, "blockers") or std.mem.eql(u8, sub, "lexer-blockers")) {
        try @import("duo_lexer_blocker.zig").writeBlockersJson(w);
    } else if (std.mem.eql(u8, sub, "lexer-bridge")) {
        try @import("duo_lexer_bridge.zig").writeBridgeJson(w);
    } else if (std.mem.eql(u8, sub, "measure")) {
        try compiler_perf_measure.writeMeasureJson(w);
    } else if (std.mem.eql(u8, sub, "proof") or std.mem.eql(u8, sub, "bundles")) {
        try bootstrap_proof.writeBundlesJson(w, alloc);
    } else if (std.mem.eql(u8, sub, "stage") or std.mem.eql(u8, sub, "compare-stages")) {
        try stage_compare.writeCompareJson(w);
    } else if (std.mem.eql(u8, sub, "targets") or std.mem.eql(u8, sub, "target-matrix")) {
        try selfhost_target_matrix.writeMatrixJson(w);
    } else if (std.mem.eql(u8, sub, "production") or std.mem.eql(u8, sub, "path")) {
        try selfhost_production_path.writeProductionPathJson(w);
    } else if (std.mem.eql(u8, sub, "migration") or std.mem.eql(u8, sub, "plan")) {
        try selfhost_migration_plan.writePlanJson(w);
    } else if (std.mem.eql(u8, sub, "summary")) {
        try w.print(
            "{{\"schema\":\"selfhost-summary-v0\",\"level\":{d},\"stage\":\"{s}\",\"host_triple\":\"{s}\",\"matrix_subsystems\":{d},\"target_rows\":{d},\"audits\":{d},\"bootstrap_stages\":{d},\"capabilities\":{d},\"removal_entries\":{d}}}\n",
            .{
                selfhosting_matrix.publicManifest().self_hosting_level,
                bootstrap_dag.currentStageReached().label(),
                blk: {
                    var buf: [64]u8 = undefined;
                    break :blk selfhost_target_matrix.hostTripleString(&buf);
                },
                selfhosting_matrix.subsystems.len,
                selfhost_target_matrix.rows.len,
                pass16_selfhost_audit.auditEntryCount(),
                bootstrap_dag.stages.len,
                compiler_capability_matrix.requirements.len,
                removal_ledger.entries.len,
            },
        );
    } else {
        try w.print(
            "{{\"error\":\"unknown selfhost subcommand\",\"sub\":\"{s}\",\"hint\":\"manifest|matrix|bootstrap|subset|audits|boundary|capabilities|ledger|catalog|compare|verify|compression|perf|measure|blockers|lexer-bridge|proof|stage|targets|production|migration|summary\"}}",
            .{sub},
        );
    }
    try w.writeAll("\n");
}

test "selfhost_cli: manifest honest partial" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeManifestJson(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "partial") != null);
}
