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

/// Full tokenization authority for production compile driver (MP4-B02 open).
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
        "{{\"schema\":\"{s}\",\"tokenize_authority\":\"{s}\",\"keyword_authority\":\"{s}\",\"production_tokenize\":\"{s}\",\"duo_projection\":\"{s}\",\"keyword_path\":\"{s}\",\"mp4_b02\":\"partial\"}}",
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
