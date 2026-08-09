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
    // RL-01 IS DONE. Its removal actually happened: `src/duo_keyword_classify.c`
    // was deleted 2026-08-07 in 32643ed ("its ledger gate was already met,
    // c/h 27 -> 26"), and `lib/std/token/classify.duo` (8.1 KB) is the shipping
    // classifier — a STRONG `duo_keyword_classify` in the generated
    // `src/duo_lexer_tokenize.c` overrides the weak host one (build.zig:24).
    // The row is kept rather than deleted so the ledger records a COMPLETED
    // removal, not just pending ones; `after_m1` now reads as "was gated on M1,
    // which was met", and the gate text carries the evidence.
    .{ .id = "RL-01", .host_path = "src/lexer.zig keyword switch (inline)", .subsystem_id = "SH-02", .duo_replacement = "lib/std/token/classify.duo", .eligibility = .after_m1, .removal_gate = "DONE 2026-08-07 (32643ed): differential parity met, production dispatch live, src/duo_keyword_classify.c deleted" },
    // RL-02's gate used to read "P16-M1 production integration", which has been
    // MET since 2026-08-07 and, since 2026-08-08, is met for `req`-ed modules
    // too (gap[042] — codegen's five module-embed sites were still running the
    // host scanner). A met gate on a file nobody can delete is a stale gate, so
    // it now names what actually holds the file, which is not M1 and never was:
    //
    //   1. TYPE HOME. `Token`, `TokenKind`, `Loc` and `LexError` live here, and
    //      63 files `@import("lexer.zig")` (re-measured 2026-08-08; the count
    //      read 61 when this note was written and only grows). The most-imported
    //      file in the whole ledger. The Duo lexer does not replace them
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
    // RL-04's `duo_replacement` was null, which read as "nothing exists yet".
    // `lib/std/compiler/parser.duo` does exist and reaches 257/257 on lib/std.
    // Naming it is more honest than the null, and the gate now says what that
    // number is worth — measured in gaps/GAP-046.md, not asserted:
    //
    //   * The coverage walk counts ACCEPTANCE, not fidelity, and its denominator
    //     is lib/std. Elsewhere in this repo: ward 21/24, tools 35/48.
    //   * lib/std is 100% partly because it uses NONE of match, enum, const,
    //     defer, or `: T | error` — that last one is Pass 100 §0.5.
    //   * Of 40 host-parser constructs probed, 26 accept, 14 reject, and two of
    //     the 26 project the WRONG tree (`nn { … }`, `x as i64`) while counting
    //     as passes.
    //   * The structural half: src/parser.zig builds an AST that sema and
    //     codegen consume; parser.duo builds an s-expression STRING. No grammar
    //     coverage makes a projector substitutable for `Parser.init`.
    .{ .id = "RL-04", .host_path = "src/parser.zig", .subsystem_id = "SH-04", .duo_replacement = "lib/std/compiler/parser.duo (projection only)", .eligibility = .after_m2, .removal_gate = "Duo-native parser kernel + syntax graph. Grammar half measured in gap[046]: 257/257 on lib/std but 26/40 constructs, 2 of them misprojected, and no `: T | error`. Structural half untouched: parser.duo emits sexpr TEXT, not the AST sema and codegen consume" },
    // RL-05's host_path said "(canonical path)". Pass 103 demotes C emission to
    // an interop EXPORT at the edge, so C is NOT the canonical path and that
    // parenthetical asserted the opposite of the law. Measured 2026-08-08
    // (method and controls in docs/ledger-removal.md), the file splits:
    //
    //   * 5,619 lines are C RUNTIME SOURCE held as Zig strings (`duo_runtime`
    //     5,523 + `duo_dense_runtime` 96; 286 distinct `lua_*` symbols). Inert
    //     text, no reader on the direct path.
    //   * 5,130 lines are tests (213 blocks).
    //   * 19,423 lines reach from `emit_module` but NOT from the precheck.
    //   * 2,481 lines ARE the direct backend's own admission gate:
    //     `can_emit_native_scalar_module` and its 94-function closure. That
    //     closure is a strict SUBSET of the C emitter's — the precheck-only
    //     partition is ZERO functions — and `main.zig:4074` builds a whole
    //     CodeGen with an `undefined` writer just to call it.
    //
    // So this row is not "delete when a Duo backend exists". 2,481 lines must be
    // PORTED, and two preconditions the old gate never named must hold first:
    // native attainment 119/177 must reach 177/177 (58 programs still bail to
    // the C emitter, `zig build native-census` 2026-08-08), and the
    // `emitReqModuleC` waist must close — `directLinkInputs` runs a full CodeGen
    // over every `req`'d module, so THE DIRECT PATH ITSELF INVOKES THE C EMITTER.
    //
    // There is also no interop-EXPORT partition to keep: every `.h` site in src/
    // is header INGESTION (c_frontend/c_sim_import/c_signatures). Pass 103
    // roadmap phase-1 C-header export is NOT BUILT.
    .{ .id = "RL-05", .host_path = "src/codegen.zig (C emitter + direct-path precheck)", .subsystem_id = "SH-10", .duo_replacement = null, .eligibility = .after_m3, .removal_gate = "Duo-native backend on one target AND native census 177/177 (119 today, 58 bail) AND emitReqModuleC waist closed. 2,481 lines are the direct-path precheck and must be PORTED, not dropped; 5,619 are embedded C runtime text; 5,130 are tests" },
    // build.zig is 1,238 lines and is itself one of the 237 tracked .zig files
    // the census ratchets on — removing it scores against the ceiling like any
    // src/ file. The other two non-src tracked .zig are tests/test_ast.zig and
    // tests/test_hash.zig, which no build step references at all (gap[080]).
    .{ .id = "RL-06", .host_path = "build.zig orchestration (1,238 lines; counts against CENSUS_ZIG_CEILING)", .subsystem_id = "SH-14", .duo_replacement = null, .eligibility = .after_bootstrap_closure, .removal_gate = "S2 is canonical compiler" },
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
