//! Pass 16 §21 — twelve required self-hosting audits (honest Level 0 status).
const std = @import("std");
const selfhosting_matrix = @import("selfhosting_matrix.zig");

pub const SCHEMA_VERSION = "pass16-selfhost-audit-v0";

pub const AuditStatus = enum {
    open,
    partial,
    done,

    pub fn name(self: AuditStatus) []const u8 {
        return @tagName(self);
    }
};

pub const Audit = struct {
    id: []const u8,
    title: []const u8,
    status: AuditStatus,
    finding: []const u8,
    owner: []const u8,
};

pub const audits: []const Audit = &.{
    .{
        .id = "P16-A01",
        .title = "Self-hosting truth",
        .status = .partial,
        .finding = "Production path manifest (selfhost_production_path.zig); Duo modules exist; full compiler still Zig-hosted",
        .owner = "src/selfhost_production_path.zig",
    },
    .{
        .id = "P16-A02",
        .title = "Host-shape contamination",
        .status = .open,
        .finding = "Tagged unions and visitor patterns in Zig host; classify per §4 migration sequence",
        .owner = "src/pass16_selfhost_audit.zig",
    },
    .{
        .id = "P16-A03",
        .title = "Duplicate semantic ownership",
        .status = .partial,
        .finding = "token_semantic.zig + classify.duo dual path; LSP/MCP still separate repos",
        .owner = "src/token_semantic.zig",
    },
    .{
        .id = "P16-A04",
        .title = "Compiler dynamic-boundary audit",
        .status = .partial,
        .finding = "Host compiler is Zig-native; generated C path still uses lua_Value heavily",
        .owner = "src/pass4_boxed_inventory.zig",
    },
    .{
        .id = "P16-A05",
        .title = "Compiler memory audit",
        .status = .open,
        .finding = "Phase allocation counters not yet instrumented in self-hosted path",
        .owner = "future P16-WS27",
    },
    .{
        .id = "P16-A06",
        .title = "Compiler latency audit",
        .status = .open,
        .finding = "Cold/warm/incremental baselines exist for bench suite; self-rebuild not measured",
        .owner = "docs/performance.md",
    },
    .{
        .id = "P16-A07",
        .title = "Bootstrap dependency audit",
        .status = .partial,
        .finding = "Zig+clang+platform linker classified in pass4_catalog bootstrap_dependencies",
        .owner = "src/bootstrap_dag.zig",
    },
    .{
        .id = "P16-A08",
        .title = "Backend closure audit",
        .status = .partial,
        .finding = "ARM64 Mach-O subset proven; compiler-required feature closure matrix open",
        .owner = "src/native_backend.zig",
    },
    .{
        .id = "P16-A09",
        .title = "Target parity audit",
        .status = .partial,
        .finding = "selfhost_target_matrix.zig tracks §17 rows; host-aware gate; self-host cross-target still open",
        .owner = "src/selfhost_target_matrix.zig",
    },
    .{
        .id = "P16-A10",
        .title = "Tooling duplication audit",
        .status = .open,
        .finding = "Formatter/LSP/MCP not yet driven from single Duo compiler service",
        .owner = "P16-WS25/WS26",
    },
    .{
        .id = "P16-A11",
        .title = "Bootstrap reproducibility audit",
        .status = .open,
        .finding = "S1→S2 comparison harness not implemented",
        .owner = "P16-WS24",
    },
    .{
        .id = "P16-A12",
        .title = "Self-hosting ergonomics audit",
        .status = .partial,
        .finding = "lib/std/compiler/lexer.duo: Lexer.new + Lexer.next proven via pass16_lexer_tokenize_proof; production dispatch still host (MP4-B02)",
        .owner = "lib/std/compiler",
    },
};

pub fn auditEntryCount() usize {
    return audits.len;
}

pub fn writeAuditSummaryJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"audits\":[", .{SCHEMA_VERSION});
    for (audits, 0..) |a, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"finding\":\"{s}\",\"owner\":\"{s}\"}}",
            .{ a.id, a.title, a.status.name(), a.finding, a.owner },
        );
    }
    try w.writeAll("],\"matrix_subsystems\":");
    try w.print("{d}", .{selfhosting_matrix.subsystems.len});
    try w.writeAll("}");
}

test "pass16_selfhost_audit: twelve audits" {
    try std.testing.expectEqual(@as(usize, 12), audits.len);
}
