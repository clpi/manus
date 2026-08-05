const std = @import("std");
const testing = std.testing;
test "dbg pick" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    const mono = @import("mono.zig");
    const CodeGen = @import("codegen.zig").CodeGen;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\fun pick<T>(fallback: T, value: T): T
        \\    value
        \\end
        \\print(pick(1.5, 2))
    , "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = sema.Sema.init(alloc);
    defer s.deinit();
    try s.check_module(&mod);
    var mono_pass = mono.Monomorphizer.init(alloc, &s.type_map);
    defer mono_pass.deinit();
    try mono_pass.run(&mod);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var cg = CodeGen.init(alloc, undefined, &s.type_map, &s.module_globals, &aw.writer, s.next_closure_id, &s.table_field_types, &s.concepts);
    cg.mono = &mono_pass;
    try cg.emit_module(&mod);
    const out = aw.written();
    var it = std.mem.splitSequence(u8, out, "\n");
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, "pick") != null or std.mem.indexOf(u8, line, "printf") != null)
            std.debug.print("{s}\n", .{line});
    }
}
