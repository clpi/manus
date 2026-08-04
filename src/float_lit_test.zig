const std = @import("std");
const lexer = @import("lexer.zig");

test "lex 1e30" {
    var lex = lexer.Lexer.init("1e30", "t");
    const tok = lex.next();
    try std.testing.expect(tok == .float_lit or tok == .int_lit);
    std.debug.print("kind: {}\n", .{tok});
}
