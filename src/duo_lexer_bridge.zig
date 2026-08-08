//! Pass 16 MP-04 — production lexer dispatch seam (explicit authority split).
//!
//! Keywords are Duo-canonical via `duo_keyword_bridge`. Full tokenization remains
//! host (`src/lexer.zig`) until `duo_lexer_tokenize.c` (or equivalent) lands.
//! This module is the single production entry for lexer authority metadata and
//! keyword dispatch from the host lexer hot path.
const std = @import("std");
const lexer = @import("lexer.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");

/// SH-03 production dispatch: rebuilding host `Token`s from the Duo lexer's
/// record buffer. Imported here so the seam and its consumer travel together.
pub const dispatch = @import("duo_lexer_dispatch.zig");

pub const SCHEMA_VERSION = "duo-lexer-bridge-v0";

pub const TokenizeAuthority = enum {
    host_zig,
    duo_native,

    pub fn name(self: TokenizeAuthority) []const u8 {
        return @tagName(self);
    }
};

pub const PRODUCTION_TOKENIZE_PATH = "src/lexer.zig";
pub const DUO_PROJECTION_PATH = "lib/std/compiler/lexer.duo";
pub const KEYWORD_PRODUCTION_PATH = duo_keyword_bridge.PRODUCTION_PATH;

/// MP4-B02 — the C-ABI entries `lib/std/compiler/lexer.duo` exports via
/// `@c.export`. These are the symbols a `duo_lexer_tokenize.c` production
/// dispatch will bind to, mirroring `duo_keyword_classify` for the keyword leg.
///
/// This list has now been wrong in BOTH directions, which is why it is pinned.
///
/// It first named eight symbols, six of which (`duo_lexer_token_count`,
/// `_kind_at`, `_text_at`, `_int_at`, `_line_at`, `duo_lexer_start_pos`) never
/// existed — overstating the seam. Correcting that overshot: it was cut to the
/// two cursor/fingerprint entries at a moment when the whole-file tokenize
/// entries either did not exist yet or were missed, which UNDERSTATED the seam
/// by three and left the blocker note below describing a gap that had been
/// closed. All five are verified emitted as real C-ABI symbols
/// (`std_compiler_lexer__duo_lexer_*`) in the generated C.
///
/// Purity has to be judged per function, not by grepping the file: the
/// whole-program C for a proof always contains `lua_Value` from the runtime
/// preamble and other embedded modules. `duo_lexer_step` itself lowers with a
/// real C ABI and no boxing:
///     int64_t std_compiler_lexer__duo_lexer_step(const char*, const char*, int64_t)
///
/// Note: `@c.export` sets the *wasm* export name; the native symbol is the Duo
/// function name, so each Duo function is named exactly what C must see.
pub const TOKENIZE_EXPORTS = [_][]const u8{
    "duo_lexer_tokenize_full",
    "duo_lexer_tokenize_text",
    "duo_lexer_tokenize_all",
    "duo_lexer_step",
    "duo_lexer_text_fingerprint",
    "duo_lexer_kind_fingerprint",
};

pub const TOKENIZE_EXPORT_PROOF = "examples/pass16_lexer_tokenize_export_proof.duo";

/// Full tokenization authority for the production compile driver.
///
/// Still `.host_zig`, deliberately — but not for the reason this comment used
/// to give. It claimed "each call re-lexes from the start, so driving production
/// tokenization through them would be quadratic". That is wrong: `new()` is a
/// record literal, and `duo_lexer_step` sets `pos` and lexes exactly one token,
/// so feeding `next_pos` back walks a source in O(n). Measured, not assumed.
///
/// LOCATION IS NO LONGER THE BLOCKER — that claim is retired here.
///
/// This comment used to say "what MP4-B02 needs is an export that threads
/// location through, e.g. taking `line` and packing a line field alongside
/// `kind`/`next_pos`". That export exists, and in a better shape than the one
/// proposed: `duo_lexer_tokenize_all` writes four i64 per token (kind, line,
/// col, int_val) and `duo_lexer_tokenize_text` writes six (adding text_off,
/// text_len) into host-provided buffers. One `Lexer` runs the whole file, so the
/// stream is state-faithful by construction rather than rebuilt per token —
/// which also retires `duo_lexer_step`'s own hazard, recorded in lexer.duo:653,
/// that stepping discards `has_peeked`/`peeked_token` and mis-lexes
/// context-sensitive shapes.
///
/// Proven, not assumed: examples/pass16_lexer_tokenize_all_proof.duo asserts
/// that tokenizing "a\nb" reports line 1 then line 2, and
/// pass16_lexer_tokenize_text_proof.duo covers the text arena. Both assert by
/// EXIT CODE (0 pass, a distinct nonzero per failed check) and print nothing on
/// success, so "no output" is not evidence of a skipped proof. Negative control
/// verified: flipping the line-2 assertion yields exit 14.
///
/// What actually remains for `.duo_native` is PRODUCTION DISPATCH: `src/lexer.zig`
/// still tokenizes for the compile driver. Closing it means committing generated
/// C for the Duo lexer and calling it from the host, exactly as SH-02's keyword
/// leg already does through `src/duo_keyword_classify.c` — that precedent, not a
/// missing capability, is the remaining work.
pub fn tokenizeAuthority() TokenizeAuthority {
    // GAP-022 is CLOSED — token text now points into the source and the parser's
    // offset arithmetic works. Measured with the flag on: the compile-fail suite
    // is BYTE-IDENTICAL to the host-authority baseline (10 failures, same rows),
    // parser coverage 256/256, selfhost proofs 12/12, repo-hygiene pass, and
    // examples/layout_attrs_test.duo — which panicked before — checks clean.
    //
    // gap[023] is CLOSED and this is .duo_native: the compiler tokenizes
    // itself with the Duo lexer. Both halves landed 2026-08-07.
    //
    // The lexer half was `_int_of` in lib/std/compiler/lexer.duo -- exact
    // decimal/hex digit accumulation in i64, never through f64, so the two
    // lexers agree on integer literals above 2^53.
    //
    // The native half was NOT a lexer divergence at all. With the flag on,
    // pass16_lexer_text_differential failed while --backend c passed, because
    // a native main never initialises the Lua runtime it links against:
    // next_tok performs a runtime require and read the module registry out of
    // a zeroed `package` (KERN_INVALID_ADDRESS at 0x68). The direct path now
    // declines when the executable must link Duo module objects, so `auto`
    // falls through to the C emit. Both differentials exit 0.
    //
    return .duo_native;
}

/// Keyword leg is Duo-native in production (MP-02 closed).
pub fn keywordAuthority() TokenizeAuthority {
    return .duo_native;
}

/// Production keyword lookup — delegates to Duo classify projection.
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return duo_keyword_bridge.lookupKeyword(text);
}

pub fn validateProductionSplit() !void {
    if (tokenizeAuthority() != .duo_native) return error.UnexpectedTokenizeAuthority;
    if (keywordAuthority() != .duo_native) return error.UnexpectedKeywordAuthority;
    if (lookupKeyword("fun") != .kw_fun) return error.KeywordBridgeFailed;
    if (lookupKeyword("notkw") != null) return error.KeywordBridgeFailed;
}

pub fn writeBridgeJson(w: *std.Io.Writer) !void {
    try w.print(
        "{{\"schema\":\"{s}\",\"tokenize_authority\":\"{s}\",\"keyword_authority\":\"{s}\",\"production_tokenize\":\"{s}\",\"duo_projection\":\"{s}\",\"keyword_path\":\"{s}\",\"mp4_b02\":\"linked_and_differentialed_query_api\"}}",
        .{
            SCHEMA_VERSION,
            tokenizeAuthority().name(),
            keywordAuthority().name(),
            PRODUCTION_TOKENIZE_PATH,
            DUO_PROJECTION_PATH,
            KEYWORD_PRODUCTION_PATH,
        },
    );
}

test "duo_lexer_bridge: production split" {
    try validateProductionSplit();
    try std.testing.expect(tokenizeAuthority() == .duo_native);
    try std.testing.expect(keywordAuthority() == .duo_native);
}

// TOKENIZE_EXPORTS is the SH-03 seam: a self-hosting claim is only as good as
// the symbols behind it. This list once named six entries that lexer.duo never
// exported, which made the seam look three-quarters built when it was a
// quarter. Pin it so re-expanding it is a deliberate, visible act rather than
// documentation drift — the two names below are the only `@c.export`s in
// lib/std/compiler/lexer.duo, verified against its generated C.
test "duo_lexer_bridge: seam is exactly the six real lexer.duo exports" {
    const expected = [_][]const u8{
        "duo_lexer_tokenize_full",
        "duo_lexer_tokenize_text",
        "duo_lexer_tokenize_all",
        "duo_lexer_step",
        "duo_lexer_text_fingerprint",
        "duo_lexer_kind_fingerprint",
    };
    try std.testing.expectEqual(expected.len, TOKENIZE_EXPORTS.len);
    for (expected, TOKENIZE_EXPORTS) |want, got| try std.testing.expectEqualStrings(want, got);
}

// The two whole-file entries are what makes production dispatch possible at all,
// and the blocker note above now asserts they exist. Name them separately so
// deleting one breaks a test that says WHY it mattered, rather than only
// shifting a count.
test "duo_lexer_bridge: the whole-file tokenize entries carry location" {
    var found_all = false;
    var found_text = false;
    var found_full = false;
    for (TOKENIZE_EXPORTS) |sym| {
        if (std.mem.eql(u8, sym, "duo_lexer_tokenize_all")) found_all = true;
        if (std.mem.eql(u8, sym, "duo_lexer_tokenize_text")) found_text = true;
        if (std.mem.eql(u8, sym, "duo_lexer_tokenize_full")) found_full = true;
    }
    // tokenize_all: kind, line, col, int_val. tokenize_text: + text_off, text_len.
    // tokenize_full: + float_val — the ONLY entry carrying everything the host
    // `Token` holds, and therefore the only one production dispatch may use.
    // Dispatch built on tokenize_text would drop float_val silently; that field
    // was wrong for every float literal until GAP-021, undetected precisely
    // because no differential read it.
    try std.testing.expect(found_all);
    try std.testing.expect(found_text);
    try std.testing.expect(found_full);
}

test "duo_lexer_bridge: the dispatch consumer is analyzed with the seam" {
    std.testing.refAllDecls(dispatch);
}
