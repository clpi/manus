const std = @import("std");
const testing = std.testing;
test "alias target" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lex = Lexer.init(
        \\alias Named = { name: str }
        \\alias Colored = Named
    , "test.duo");
    var parser = Parser.init(&lex, arena.allocator());
    parser.duo_mode = true;
    const module = try parser.parse_module();
    for (module.body.stmts) |stmt| {
        if (stmt != .alias_def) continue;
        const ad = stmt.alias_def;
        const tgt = ad.target orelse {
            std.debug.print("alias {s} no target\n", .{ad.name});
            continue;
        };
        std.debug.print("alias {s} target={s}\n", .{ ad.name, @tagName(tgt) });
        switch (tgt) {
            .named => |n| std.debug.print("  named={s}\n", .{n}),
            else => {},
        }
    }
}
