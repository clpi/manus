//! Pass 16 §22.1 — self-hosting matrix: host vs Duo ownership per compiler subsystem.
const std = @import("std");

pub const SCHEMA_VERSION = "selfhosting-matrix-v0";

/// Pass 16 §13 migration status for each subsystem.
pub const MigrationStatus = enum {
    seed_only,
    differential_oracle,
    porting,
    duo_canonical,
    retired,
    rejected,
    external_optional,

    pub fn name(self: MigrationStatus) []const u8 {
        return @tagName(self);
    }
};

pub const Subsystem = struct {
    id: []const u8,
    title: []const u8,
    host_impl: []const u8,
    duo_impl: ?[]const u8,
    production_status: MigrationStatus,
    bootstrap_required: bool,
    migration_blocker: ?[]const u8,
    removal_gate: ?[]const u8,
};

/// Honest ownership map at Pass 16 introduction. Update when a subsystem moves to `duo_canonical`.
pub const subsystems: []const Subsystem = &.{
    .{
        .id = "SH-01",
        .title = "Source bytes and cursor",
        .host_impl = "src/lexer.zig → source_cursor.ProductionCursor",
        .duo_impl = "lib/std/compiler/source.duo",
        .production_status = .differential_oracle,
        .bootstrap_required = false,
        .migration_blocker = null,
        .removal_gate = "P16-M1 full Duo ByteCursor dispatch (optional; ProductionCursor integrated)",
    },
    .{
        .id = "SH-02",
        .title = "Token definitions and keyword table",
        .host_impl = "src/token_semantic.zig (differential oracle)",
        .duo_impl = "lib/std/token/classify.duo → src/duo_keyword_classify.c",
        .production_status = .duo_canonical,
        .bootstrap_required = false,
        .migration_blocker = null,
        .removal_gate = "Host branch_chain oracle retained until S1 bootstrap closure",
    },
    .{
        .id = "SH-03",
        .title = "Lexer",
        .host_impl = "src/lexer.zig",
        .duo_impl = "lib/std/compiler/lexer.duo",
        .production_status = .differential_oracle,
        .bootstrap_required = false,
        .migration_blocker = "MP4-B02: tokenize authority host; Duo embed proven (MP4-B01); duo_lexer_bridge seam wired",
        .removal_gate = "duo_lexer_tokenize.c production dispatch + pass16-m1-smoke",
    },
    .{
        .id = "SH-04",
        .title = "Parser",
        .host_impl = "src/parser.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "No Duo-native parser kernel yet",
        .removal_gate = "P16-WS6 + syntax graph",
    },
    .{
        .id = "SH-05",
        .title = "Formatter / canonicalizer",
        .host_impl = "src/fmt.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Depends on parser + grammar descriptor convergence",
        .removal_gate = "P16-WS7",
    },
    .{
        .id = "SH-06",
        .title = "Binding and scopes",
        .host_impl = "src/sema.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Semantic graph substrate incomplete in Duo",
        .removal_gate = "P16-WS9",
    },
    .{
        .id = "SH-07",
        .title = "Semantic graph",
        .host_impl = "src/semantic_graph.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Graph is Zig-hosted partial implementation",
        .removal_gate = "P16-M2",
    },
    .{
        .id = "SH-08",
        .title = "Compile-time evaluator",
        .host_impl = "src/comptime.zig + codegen folds",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Compiler-capable Duo profile undefined (P4-12)",
        .removal_gate = "P16-WS11",
    },
    .{
        .id = "SH-09",
        .title = "Transformation registry",
        .host_impl = "src/transform_engine.zig",
        .duo_impl = null,
        .production_status = .porting,
        .bootstrap_required = false,
        .migration_blocker = "Stub + proof hooks; not full optimizer",
        .removal_gate = "P16-WS13",
    },
    .{
        .id = "SH-10",
        .title = "C code generation backend",
        .host_impl = "src/codegen.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Canonical path today; must become explicit bootstrap backend",
        .removal_gate = "P16-M3 native loop on one target",
    },
    .{
        .id = "SH-11",
        .title = "Direct native backend (ARM64 Mach-O)",
        .host_impl = "src/native_backend.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Restricted scalar subset only",
        .removal_gate = "P16-WS19 + object writers in Duo",
    },
    .{
        .id = "SH-12",
        .title = "Object writers / link substrate",
        .host_impl = "src/native_backend.zig + platform linker",
        .duo_impl = null,
        .production_status = .external_optional,
        .bootstrap_required = true,
        .migration_blocker = "Mach-O partial; ELF/COFF open",
        .removal_gate = "P16-WS21",
    },
    .{
        .id = "SH-13",
        .title = "Runtime profile",
        .host_impl = "generated duo_runtime preamble",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Full dynamic runtime linked for most builds",
        .removal_gate = "P16-WS22 freestanding compiler profile",
    },
    .{
        .id = "SH-14",
        .title = "Build orchestration",
        .host_impl = "build.zig",
        .duo_impl = null,
        .production_status = .external_optional,
        .bootstrap_required = true,
        .migration_blocker = "Zig build is bootstrap orchestrator until S2",
        .removal_gate = "P16-WS23 bootstrap DAG executor",
    },
    .{
        .id = "SH-15",
        .title = "LSP compiler service",
        .host_impl = "~/x/duo-lsp (separate repo)",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Must consume shared compiler facts, not re-parse",
        .removal_gate = "P16-WS25",
    },
    .{
        .id = "SH-16",
        .title = "MCP semantic service",
        .host_impl = "~/x/duo-mcp",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Development MCP lacks bootstrap stage state",
        .removal_gate = "P16-WS26",
    },
};

pub const Manifest = struct {
    schema: []const u8 = SCHEMA_VERSION,
    self_hosting_level: u8,
    canonical_compiler_in_duo: bool,
    bootstrap_stage_reached: []const u8,
    production_duo_frontend: bool,
    silent_c_fallback: bool,
    claim_self_hosted_status: []const u8,
};

pub fn publicManifest() Manifest {
    return .{
        .self_hosting_level = 1,
        .canonical_compiler_in_duo = false,
        .bootstrap_stage_reached = "S0",
        .production_duo_frontend = true,
        .silent_c_fallback = true,
        .claim_self_hosted_status = "partial",
    };
}

pub fn countByStatus(status: MigrationStatus) usize {
    var n: usize = 0;
    for (subsystems) |s| {
        if (s.production_status == status) n += 1;
    }
    return n;
}

pub fn writeMatrixJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"subsystems\":[", .{SCHEMA_VERSION});
    for (subsystems, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"host_impl\":\"{s}\",\"duo_impl\":",
            .{ s.id, s.title, s.host_impl },
        );
        if (s.duo_impl) |d| {
            try w.print("\"{s}\"", .{d});
        } else {
            try w.writeAll("null");
        }
        try w.print(
            ",\"production_status\":\"{s}\",\"bootstrap_required\":{},\"migration_blocker\":",
            .{ s.production_status.name(), s.bootstrap_required },
        );
        if (s.migration_blocker) |b| {
            try w.print("\"{s}\"", .{b});
        } else {
            try w.writeAll("null");
        }
        try w.print(",\"removal_gate\":", .{});
        if (s.removal_gate) |g| {
            try w.print("\"{s}\"", .{g});
        } else {
            try w.writeAll("null");
        }
        try w.writeAll("}}");
    }
    try w.writeAll("],\"manifest\":");
    const m = publicManifest();
    try w.print(
        "{{\"self_hosting_level\":{d},\"canonical_compiler_in_duo\":{},\"bootstrap_stage_reached\":\"{s}\",\"production_duo_frontend\":{},\"silent_c_fallback\":{},\"claim_self_hosted_status\":\"{s}\"}}",
        .{ m.self_hosting_level, m.canonical_compiler_in_duo, m.bootstrap_stage_reached, m.production_duo_frontend, m.silent_c_fallback, m.claim_self_hosted_status },
    );
    try w.writeAll("}");
}

test "selfhosting_matrix: honest manifest level 1 keyword component" {
    const m = publicManifest();
    try std.testing.expectEqual(@as(u8, 1), m.self_hosting_level);
    try std.testing.expect(!m.canonical_compiler_in_duo);
    try std.testing.expect(m.production_duo_frontend);
    try std.testing.expect(std.mem.eql(u8, m.claim_self_hosted_status, "partial"));
    try std.testing.expect(std.mem.eql(u8, m.bootstrap_stage_reached, "S0"));
    try std.testing.expect(subsystems.len >= 10);
}
