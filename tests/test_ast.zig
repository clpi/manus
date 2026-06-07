// Integration-level tests for the full lex → parse → sema pipeline.
// These complement the fine-grained unit tests in src/lexer.zig, src/parser.zig,
// and src/sema.zig by checking that complete program fragments are handled
// correctly end-to-end.
const std = @import("std");
const Lexer  = @import("src/lexer.zig").Lexer;
const Parser = @import("src/parser.zig").Parser;
const Sema   = @import("src/sema.zig").Sema;
const ast    = @import("src/ast.zig");
const RT     = @import("src/types.zig").ResolvedType;

fn parseAndCheck(src: []const u8, arena: *std.heap.ArenaAllocator) !struct {
    mod: ast.Module,
    sem: Sema,
} {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p   = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var sem = Sema.init(alloc);
    try sem.check_module(&mod);
    return .{ .mod = mod, .sem = sem };
}

test "pipeline: fibonacci function compiles without errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseAndCheck(
        \\function fib(n: i64) -> i64
        \\  if n <= 1 then
        \\    return n
        \\  end
        \\  return fib(n - 1) + fib(n - 2)
        \\end
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
    const fd = result.mod.body.stmts[0].func_decl;
    try std.testing.expect(fd.func.is_typed);
}

test "pipeline: multi-statement module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseAndCheck(
        \\local a = 1
        \\local b = 2
        \\local c = a + b
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
    try std.testing.expectEqual(@as(usize, 3), result.mod.body.stmts.len);
}

test "pipeline: nested function bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseAndCheck(
        \\function outer(x: i32) -> i32
        \\  local function inner(y: i32) -> i32
        \\    return y * 2
        \\  end
        \\  return inner(x) + 1
        \\end
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
}

test "pipeline: if/elseif/else chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseAndCheck(
        \\local x = 5
        \\if x < 0 then
        \\  local sign = -1
        \\elseif x == 0 then
        \\  local sign = 0
        \\else
        \\  local sign = 1
        \\end
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
}

test "pipeline: numeric for with typed variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseAndCheck(
        \\local sum: i64 = 0
        \\for i: i64 = 1, 100 do
        \\  sum = sum + i
        \\end
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
}

test "pipeline: inline record type annotation on a binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Duo has no `struct` keyword. Records are declared via inline type
    // literals on bindings. The annotation is parsed, the binding is
    // type-checked against the record shape, and the table literal is
    // accepted as the initializer.
    const result = try parseAndCheck(
        \\local v: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }
    , &arena);
    try std.testing.expectEqual(@as(u32, 0), result.sem.errors);
    const stmt = result.mod.body.stmts[0];
    try std.testing.expect(stmt == .local_decl);
    try std.testing.expectEqual(@as(usize, 1), stmt.local_decl.names.len);
    try std.testing.expectEqualStrings("v", stmt.local_decl.names[0].ident);
    try std.testing.expect(stmt.local_decl.names[0].typ == .record);
    try std.testing.expectEqual(@as(usize, 2), stmt.local_decl.names[0].typ.record.fields.len);
}

test "pipeline: @implements attribute on a record-typed binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Concept satisfaction is declared via `@implements(...)` on the
    // binding, not on a struct definition. Concept lookup against the
    // record-type annotation is the Type_Checker's job; the function
    // above does not define a concept so this just exercises the
    // parsing-and-resolution path with an undeclared concept tolerated.
    const result = try parseAndCheck(
        \\@implements(Iterable)
        \\local counter: { count: i64 } = { count = 0 }
    , &arena);
    const stmt = result.mod.body.stmts[0];
    try std.testing.expect(stmt == .local_decl);
    try std.testing.expectEqual(@as(usize, 1), stmt.local_decl.names[0].attributes.len);
    try std.testing.expectEqualStrings("implements", stmt.local_decl.names[0].attributes[0].name);
}

test "pipeline: type annotation on typed function affects type_map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function square(n: i64) -> i64
        \\  return n * n
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var sem = Sema.init(alloc);
    try sem.check_module(&mod);
    try std.testing.expectEqual(@as(u32, 0), sem.errors);
    // The return expression `n * n` should be recorded as i64 in the type map
    const body = mod.body.stmts[0].func_decl.func.body;
    const ret_stmt = body.stmts[0].ret;
    const mul_expr = ret_stmt.vals[0];
    const t = sem.type_map.get(mul_expr);
    try std.testing.expect(t != null);
    try std.testing.expect(t.?.is_integer());
}
