const std = @import("std");
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src =
        \\fun pick<T>(fallback: T, value: T): T
        \\    value
        \\end
        \\print(pick(1.5, 2))
    ;

    const Lexer = @import("src/lexer.zig").Lexer;
    const Parser = @import("src/parser.zig").Parser;
    const Sema = @import("src/sema.zig").Sema;
    const CodeGen = @import("src/codegen.zig").CodeGen;
    const mono = @import("src/mono.zig");

    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();

    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);

    var mono_pass = mono.Monomorphizer.init(alloc, &s.type_map);
    try mono_pass.run(&mod);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    var cg = CodeGen.init(alloc, undefined, &s.type_map, &s.module_globals, &aw.writer, s.next_closure_id, &s.table_field_types);
    cg.duo_mode = true;
    cg.mono = &mono_pass;

    // Patch Mono to trace findSpecializationForCall
    std.debug.print("Calling emit_module\n", .{});
    try cg.emit_module(&mod);
    
    std.debug.print("Did output have duo_pick_f64?\n{}\n", .{std.mem.indexOf(u8, aw.written(), "duo_pick_f64") != null});
    std.debug.print("Did output have pick(1.5, 2)?\n{}\n", .{std.mem.indexOf(u8, aw.written(), "pick(1.5, 2)") != null});
}
