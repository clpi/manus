const std = @import("std");
const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const CodeGen = @import("codegen.zig").CodeGen;

test "codegen: pipeline |> .field inlines native field access" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: { x: i64, y: i64 }
        \\fun pick_x(p: Point): i64
        \\  return p |> .x
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var cg = CodeGen.init(alloc, undefined, &semantic.type_map, &semantic.module_globals, &aw.writer, semantic.next_closure_id, &semantic.table_field_types, &semantic.concepts);
    cg.duo_mode = true;
    try cg.emit_module(&module);
    const output = aw.written();
    const pick_start = std.mem.indexOf(u8, output, "static inline int64_t pick_x") orelse
        return error.TestUnexpectedResult;
    const pick_end = std.mem.indexOf(u8, output[pick_start..], "\n}\n") orelse output.len;
    const pick_body = output[pick_start .. pick_start + pick_end];
    try testing.expect(std.mem.indexOf(u8, pick_body, "lua_invoke") == null);
    try testing.expect(std.mem.indexOf(u8, pick_body, ".x") != null);
}

test "codegen: chained pipeline projection p |> .x |> .y fuses field access" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: { x: i64, y: i64 }
        \\fun pick_y(p: Point): i64
        \\  return p |> .x |> .y
        \\end
    , "test.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var cg = CodeGen.init(alloc, undefined, &semantic.type_map, &semantic.module_globals, &aw.writer, semantic.next_closure_id, &semantic.table_field_types, &semantic.concepts);
    cg.duo_mode = true;
    try cg.emit_module(&module);
    const output = aw.written();
    const pick_start = std.mem.indexOf(u8, output, "static inline int64_t pick_y") orelse
        return error.TestUnexpectedResult;
    const pick_end = std.mem.indexOf(u8, output[pick_start..], "\n}\n") orelse output.len;
    const pick_body = output[pick_start .. pick_start + pick_end];
    try testing.expect(std.mem.indexOf(u8, pick_body, "lua_invoke") == null);
    try testing.expect(std.mem.indexOf(u8, pick_body, ".x.y") != null or
        (std.mem.indexOf(u8, pick_body, ".x") != null and std.mem.indexOf(u8, pick_body, ".y") != null));
}
