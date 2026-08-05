//! Pass 16 P16-WS3 — production keyword dispatch via Duo classify projection.
//!
//! `duo_keyword_classify` is the C realization of `lib/std/token/classify.duo`
//! (`@c.export classify` / `classify_branch_chain`), generated from the same
//! canonical table as `src/token_semantic.zig`.
const std = @import("std");
const lexer = @import("lexer.zig");

pub const PRODUCTION_PATH = "lib/std/token/classify.duo → src/duo_keyword_classify.c";

extern fn duo_keyword_classify(w: [*:0]const u8) i64;

/// Production keyword lookup — Duo-native classify realization (no heap, no lua_Value).
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    if (text.len == 0 or text.len >= 64) return null;
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    const id = duo_keyword_classify((buf[0..text.len :0]).ptr);
    if (id == 0) return null;
    return @enumFromInt(@as(u16, @intCast(id)));
}

test "duo_keyword_bridge: production keywords" {
    try std.testing.expect(lookupKeyword("fun") == .kw_fun);
    try std.testing.expect(lookupKeyword("end") == .kw_end);
    try std.testing.expect(lookupKeyword("i64") == .kw_i64);
    try std.testing.expect(lookupKeyword("notkw") == null);
}
