const std = @import("std");
const testing = std.testing;
test "dbg math" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    const CodeGen = @import("codegen.zig").CodeGen;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\local intpart: f64 = math.modf(12.75)
    , "test");
    var parser = Parser.init(&lex, alloc);
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    try semantic.check_module(&module);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var cg = CodeGen.init(alloc, undefined, &semantic.type_map, &semantic.module_globals, &aw.writer, semantic.next_closure_id, &semantic.table_field_types, &semantic.concepts);
    try cg.emit_module(&module);
    var it = std.mem.splitSequence(u8, aw.written(), "\n");
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, "intpart") != null or std.mem.indexOf(u8, line, "modf") != null)
            std.debug.print("{s}\n", .{line});
    }
}
