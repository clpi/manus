//! Pass 16 §22.9 — host code eligible for retirement after transfer and integration.
const std = @import("std");

pub const SCHEMA_VERSION = "removal-ledger-v0";

pub const Eligibility = enum {
    blocked,
    after_m1,
    after_m2,
    after_m3,
    after_bootstrap_closure,
    retain_oracle,

    pub fn name(self: Eligibility) []const u8 {
        return @tagName(self);
    }
};

pub const Entry = struct {
    id: []const u8,
    host_path: []const u8,
    subsystem_id: []const u8,
    duo_replacement: ?[]const u8,
    eligibility: Eligibility,
    removal_gate: []const u8,
};

pub const entries: []const Entry = &.{
    .{ .id = "RL-01", .host_path = "src/lexer.zig keyword switch (inline)", .subsystem_id = "SH-02", .duo_replacement = "lib/std/token/classify.duo", .eligibility = .after_m1, .removal_gate = "Differential parity + production dispatch" },
    // RL-02's gate used to read "P16-M1 production integration", which has been
    // MET since 2026-08-07 and, since 2026-08-08, is met for `req`-ed modules
    // too (gap[042] — codegen's five module-embed sites were still running the
    // host scanner). A met gate on a file nobody can delete is a stale gate, so
    // it now names what actually holds the file, which is not M1 and never was:
    //
    //   1. TYPE HOME. `Token`, `TokenKind`, `Loc` and `LexError` live here, and
    //      61 files `@import("lexer.zig")`. The Duo lexer does not replace them
    //      — `duo_lexer_dispatch` REBUILDS host `Token`s from its record buffer.
    //   2. DRIVER OBJECT. `Lexer` is what `Parser.init` takes; Duo tokenization
    //      is installed onto one via `useDuoTokens`. The scanner can be dead and
    //      the struct still be required.
    //   3. ORACLE. `duo_lexer_dispatch.differential` and `lexer_differential.zig`
    //      compare the two field for field. Same deliberate retention as RL-03.
    //   4. FRAGMENT SCANNER. `derive_eval.zig` and `mono.zig` lex synthetic
    //      strings (a derived source, a type name) rather than user files.
    //
    // 1 and 2 fall with `src/parser.zig`, so the honest eligibility is after_m2,
    // not after_m1. 3 outlives even that.
    .{ .id = "RL-02", .host_path = "src/lexer.zig (full)", .subsystem_id = "SH-03", .duo_replacement = "lib/std/compiler/lexer.duo", .eligibility = .after_m2, .removal_gate = "Scanner already retired from production (M1 met, incl. req-ed modules). Held by the token type home + Parser's driver object, so it falls with RL-04; then retained as the field-for-field oracle" },
    .{ .id = "RL-03", .host_path = "src/token_semantic.zig", .subsystem_id = "SH-02", .duo_replacement = "lib/std/token/classify.duo + descriptor", .eligibility = .retain_oracle, .removal_gate = "Keep as differential oracle post-M1" },
    .{ .id = "RL-04", .host_path = "src/parser.zig", .subsystem_id = "SH-04", .duo_replacement = null, .eligibility = .after_m2, .removal_gate = "Duo-native parser kernel + syntax graph" },
    .{ .id = "RL-05", .host_path = "src/codegen.zig (canonical path)", .subsystem_id = "SH-10", .duo_replacement = null, .eligibility = .after_m3, .removal_gate = "Duo-native backend on one target" },
    .{ .id = "RL-06", .host_path = "build.zig orchestration", .subsystem_id = "SH-14", .duo_replacement = null, .eligibility = .after_bootstrap_closure, .removal_gate = "S2 is canonical compiler" },
};

pub fn writeLedgerJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"entries\":[", .{SCHEMA_VERSION});
    for (entries, 0..) |e, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"host_path\":\"{s}\",\"subsystem_id\":\"{s}\",\"duo_replacement\":",
            .{ e.id, e.host_path, e.subsystem_id },
        );
        if (e.duo_replacement) |d| {
            try w.print("\"{s}\"", .{d});
        } else {
            try w.writeAll("null");
        }
        try w.print(
            ",\"eligibility\":\"{s}\",\"removal_gate\":\"{s}\"}}",
            .{ e.eligibility.name(), e.removal_gate },
        );
    }
    try w.writeAll("]}");
}

test "removal_ledger: entries present" {
    try std.testing.expect(entries.len >= 4);
}
