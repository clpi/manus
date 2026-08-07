//! Pass 16 MP-04 — production lexer dispatch seam (explicit authority split).
//!
//! Keywords are Duo-canonical via `duo_keyword_bridge`. Full tokenization remains
//! host (`src/lexer.zig`) until `duo_lexer_tokenize.c` (or equivalent) lands.
//! This module is the single production entry for lexer authority metadata and
//! keyword dispatch from the host lexer hot path.
const std = @import("std");
const lexer = @import("lexer.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");

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
/// Proven by `examples/pass16_lexer_tokenize_export_proof.duo` (11 checks), whose
/// generated C carries zero `lua_Value`, `lua_invoke`, `lua_table_get` or
/// `duo_fallback_get_*` — the tokenizer lowers fully native.
///
/// Note: `@c.export` sets the *wasm* export name; the native symbol is the Duo
/// function name, so each Duo function is named exactly what C must see.
pub const TOKENIZE_EXPORTS = [_][]const u8{
    "duo_lexer_token_count",
    "duo_lexer_token_kind_at",
    "duo_lexer_token_text_at",
    "duo_lexer_token_int_at",
    "duo_lexer_token_line_at",
    "duo_lexer_kind_fingerprint",
    "duo_lexer_step",
    "duo_lexer_start_pos",
};

pub const TOKENIZE_EXPORT_PROOF = "examples/pass16_lexer_tokenize_export_proof.duo";

/// Full tokenization authority for the production compile driver.
///
/// Still `.host_zig`, deliberately. The Duo tokenizer is linked in
/// (`TOKENIZE_PRODUCTION_C`) and is proven to agree with `src/lexer.zig`
/// token-for-token over the differential corpus, but the exported entries are a
/// *query* API: each call re-lexes from the start, so driving production
/// tokenization through them would be quadratic. Closing MP4-B02 needs a
/// streaming entry (an opaque cursor plus `next`) that the host lexer's inner
/// loop can consume — the equivalence evidence is done, the engine shape is not.
pub fn tokenizeAuthority() TokenizeAuthority {
    return .host_zig;
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
    if (tokenizeAuthority() != .host_zig) return error.UnexpectedTokenizeAuthority;
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
    try std.testing.expect(tokenizeAuthority() == .host_zig);
    try std.testing.expect(keywordAuthority() == .duo_native);
}
