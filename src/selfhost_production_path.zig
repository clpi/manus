//! Pass 16 §2.2 / M1 — honest production compile-path authority (no silent fallback claims).
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const selfhost_verify = @import("selfhost_verify.zig");

pub const SCHEMA_VERSION = "selfhost-production-path-v0";

pub const Authority = enum {
    host_zig,
    host_zig_semantic,
    duo_native,
    differential_oracle,
    generated_c_fallback,
    external_tool,

    pub fn name(self: Authority) []const u8 {
        return @tagName(self);
    }
};

pub const FallbackPolicy = enum {
    none,
    explicit_flag,
    silent_default,

    pub fn name(self: FallbackPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const Phase = struct {
    id: []const u8,
    title: []const u8,
    authority: Authority,
    implementation: []const u8,
    duo_projection: ?[]const u8,
    fallback: FallbackPolicy,
    fallback_detail: ?[]const u8,
    m1_in_scope: bool,
};

/// Production path at bootstrap stage S0 — update when a phase moves to duo_native.
pub const phases: []const Phase = &.{
    .{
        .id = "PP-01",
        .title = "Source load and cursor",
        .authority = .host_zig_semantic,
        .implementation = "src/lexer.zig → source_cursor.ProductionCursor",
        .duo_projection = "lib/std/compiler/source.duo",
        .fallback = .none,
        .fallback_detail = "0-based index + Duo-parity line/col via shared advanceLoc",
        .m1_in_scope = true,
    },
    .{
        .id = "PP-02",
        .title = "Keyword classification",
        .authority = .duo_native,
        .implementation = "lib/std/token/classify.duo → src/duo_keyword_classify.c → duo_keyword_bridge",
        .duo_projection = "lib/std/token/classify.duo",
        .fallback = .none,
        .fallback_detail = "Host branch_chain oracle via token_semantic.lookupKeywordOracle for differential gate",
        .m1_in_scope = true,
    },
    .{
        .id = "PP-03",
        .title = "Lexing (non-keyword tokens)",
        .authority = .host_zig,
        .implementation = "src/lexer.zig → duo_lexer_bridge (keyword leg Duo-native via PP-02)",
        .duo_projection = "lib/std/compiler/lexer.duo",
        .fallback = .none,
        .fallback_detail = "Duo embed tokenize proven (pass16_lexer_tokenize_proof.duo); full production dispatch open MP4-B02",
        .m1_in_scope = true,
    },
    .{
        .id = "PP-04",
        .title = "Parsing",
        .authority = .host_zig,
        .implementation = "src/parser.zig",
        .duo_projection = null,
        .fallback = .none,
        .fallback_detail = null,
        .m1_in_scope = false,
    },
    .{
        .id = "PP-05",
        .title = "Semantic analysis",
        .authority = .host_zig,
        .implementation = "src/sema.zig + src/semantic_graph.zig (partial)",
        .duo_projection = null,
        .fallback = .none,
        .fallback_detail = null,
        .m1_in_scope = false,
    },
    .{
        .id = "PP-06",
        .title = "Code generation (release)",
        .authority = .duo_native,
        .implementation = "DNIR → native_backend.zig (ARM64 Mach-O); C emit bootstrap via --backend=c",
        .duo_projection = "src/duo_native_ir.zig",
        .fallback = .explicit_flag,
        .fallback_detail = "--backend=c for bootstrap C emit only; default --backend=auto prefers machine",
        .m1_in_scope = false,
    },
    .{
        .id = "PP-07",
        .title = "Native machine backend",
        .authority = .duo_native,
        .implementation = "src/native_backend.zig",
        .duo_projection = null,
        .fallback = .none,
        .fallback_detail = "Canonical path on aarch64-macos when program is in direct subset",
        .m1_in_scope = false,
    },
    .{
        .id = "PP-08",
        .title = "Duo keyword differential oracle",
        .authority = .differential_oracle,
        .implementation = "examples/pass12_m1_diff.duo + pass16_m1_lexer_proof.duo",
        .duo_projection = "lib/std/token/classify.duo",
        .fallback = .none,
        .fallback_detail = null,
        .m1_in_scope = true,
    },
    .{
        .id = "PP-09",
        .title = "Source cursor differential oracle",
        .authority = .differential_oracle,
        .implementation = "src/source_cursor.zig + examples/pass16_source_cursor_proof.duo",
        .duo_projection = "lib/std/compiler/source.duo",
        .fallback = .none,
        .fallback_detail = "1-based ByteCursor in Duo; production uses ProductionCursor (0-based index, shared advanceLoc)",
        .m1_in_scope = true,
    },
    .{
        .id = "PP-10",
        .title = "Duo lexer embed differential oracle",
        .authority = .differential_oracle,
        .implementation = "examples/pass16_lexer_embed_proof.duo + pass16_lexer_tokenize_proof.duo",
        .duo_projection = "lib/std/compiler/lexer.duo",
        .fallback = .none,
        .fallback_detail = "MP4-B01 closed; host src/lexer.zig remains tokenize authority until duo_lexer_bridge C projection",
        .m1_in_scope = true,
    },
};

pub fn m1PhaseCount() usize {
    var n: usize = 0;
    for (phases) |p| {
        if (p.m1_in_scope) n += 1;
    }
    return n;
}

pub fn validateProductionPathGate() !void {
    if (phases.len < 6) return error.GateFailed;
    // Keyword path must be explicit host semantic, not silent C.
    const kw = findPhase("PP-02") orelse return error.GateFailed;
    if (kw.authority != .duo_native) return error.GateFailed;
    if (kw.fallback != .none) return error.GateFailed;
    // Lexer bridge split must remain honest until MP4-B02 closes.
    try @import("duo_lexer_bridge.zig").validateProductionSplit();
    // Default codegen fallback must be declared explicit, not silent.
    const cg = findPhase("PP-06") orelse return error.GateFailed;
    if (cg.fallback == .silent_default) return error.GateFailed;
    // M1 differential oracles must pass at gate time.
    _ = try selfhost_verify.verifyAllOrFail();
    if (token_semantic.keywords.len < 50) return error.GateFailed;
}

pub fn findPhase(id: []const u8) ?Phase {
    for (phases) |p| {
        if (std.mem.eql(u8, p.id, id)) return p;
    }
    return null;
}

pub fn writeProductionPathJson(w: *std.Io.Writer) !void {
    const verify = selfhost_verify.verifyKeywords();
    try w.print("{{\"schema\":\"{s}\",\"bootstrap_stage\":\"S0\",\"canonical_compiler_in_duo\":false,\"default_backend\":\"auto\",\"canonical_lowering\":\"machine\",\"c_emit_flag\":\"--backend=c\",\"direct_backend_flag\":\"--backend=direct\",\"keyword_authority\":\"token_semantic.zig\",\"keyword_classifier\":\"{s}\",\"keyword_differential_pass\":{},\"m1_phases\":{d},\"phases\":[", .{
        SCHEMA_VERSION,
        token_semantic.production_classifier.name(),
        verify.exhaustive_pass and verify.fuzz_pass,
        m1PhaseCount(),
    });
    for (phases, 0..) |p, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"authority\":\"{s}\",\"implementation\":\"{s}\",\"duo_projection\":",
            .{ p.id, p.title, p.authority.name(), p.implementation },
        );
        if (p.duo_projection) |d| try w.print("\"{s}\"", .{d}) else try w.writeAll("null");
        try w.print(
            ",\"fallback\":\"{s}\",\"fallback_detail\":",
            .{p.fallback.name()},
        );
        if (p.fallback_detail) |fd| try w.print("\"{s}\"", .{fd}) else try w.writeAll("null");
        try w.print(",\"m1_in_scope\":{}}}", .{p.m1_in_scope});
    }
    try w.writeAll("]}");
}

test "selfhost_production_path: keyword phase authoritative" {
    const kw = findPhase("PP-02").?;
    try std.testing.expect(kw.authority == .duo_native);
    try std.testing.expect(kw.m1_in_scope);
}

test "selfhost_production_path: gate" {
    try validateProductionPathGate();
}
