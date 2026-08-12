//! Physical bridge from the generated keyword classifier to the bootstrap
//! lexer. Canonical token and grammar roles remain upstream facts.
const std = @import("std");
const lexer = @import("lexer.zig");

extern fn duo_keyword_classify(w: [*:0]const u8) i64;

/// Production keyword lookup through the allocation-free generated classifier.
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    if (text.len == 0 or text.len >= 64) return null;
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    const id = duo_keyword_classify((buf[0..text.len :0]).ptr);
    if (id == 0) return null;
    return @enumFromInt(@as(u16, @intCast(id)));
}

test "keyword bridge: production keywords" {
    try std.testing.expect(lookupKeyword("fun") == .kw_fun);
    try std.testing.expect(lookupKeyword("end") == .kw_end);
    try std.testing.expect(lookupKeyword("i64") == .kw_i64);
    try std.testing.expect(lookupKeyword("notkw") == null);
}
