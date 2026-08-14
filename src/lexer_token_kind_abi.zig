//! MAGIC-CODE-ZERO debt, not closure. Host `TokenKind` still parallels
//! producer slots so live ordinals do not shift. Slot 3 is unpublished
//! (`kindname(3)==""`); `string_lit` is a hole, not an identity.
//! Deletion: token-role-id across the seam (`law.magic.zero`).
const std = @import("std");
const lexer = @import("lexer.zig");

test "lexer token kind: ABI ordinals match token.id" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(lexer.TokenKind.name));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(lexer.TokenKind.string_lit));
    try std.testing.expectEqual(@as(usize, 4), @intFromEnum(lexer.TokenKind.kw_and));
    try std.testing.expectEqual(@as(usize, 105), @intFromEnum(lexer.TokenKind.text_lit));
    try std.testing.expectEqual(@as(usize, 106), @intFromEnum(lexer.TokenKind.bytes_lit));
    try std.testing.expectEqual(@as(usize, 107), @intFromEnum(lexer.TokenKind.compat_text_lit));
    try std.testing.expectEqual(@as(usize, 108), @intFromEnum(lexer.TokenKind.compat_long_text_lit));
    try std.testing.expectEqual(@as(usize, 109), @intFromEnum(lexer.TokenKind.eof));
    try std.testing.expectEqual(@as(usize, 110), @intFromEnum(lexer.TokenKind.shebang));
    try std.testing.expectEqual(@as(usize, 111), @intFromEnum(lexer.TokenKind.comment));
    try std.testing.expectEqual(@as(usize, 112), @intFromEnum(lexer.TokenKind.compat_comment));
    try std.testing.expectEqual(@as(usize, 113), @intFromEnum(lexer.TokenKind.compat_long_comment));
}
