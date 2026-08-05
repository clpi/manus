const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const CodeGen = @import("codegen.zig").CodeGen;

const milestone_source =
    \\Point: @{ x: f64, y: f64 }
    \\distance2(p: Point): f64
    \\    p.x * p.x + p.y * p.y
    \\end
    \\main(): f64
    \\    distance2({ x = 3.0, y = 4.0 })
    \\end
;

fn compileMilestoneC(alloc: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(milestone_source, "pass4_native_milestone.duo");
    var parser = Parser.init(&lex, a);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(a);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    var aw: std.Io.Writer.Allocating = .init(a);
    defer aw.deinit();
    var cg = CodeGen.init(
        a,
        undefined,
        &semantic.type_map,
        &semantic.module_globals,
        &aw.writer,
        semantic.next_closure_id,
        &semantic.table_field_types,
        &semantic.concepts,
    );
    cg.duo_mode = true;
    try cg.emit_module(&module);
    const output = aw.written();
    return alloc.dupe(u8, output);
}

test "Pass 4 M1: distance2 emits native struct fields without lua_invoke" {
    const native_barrier_checks = @import("native_barrier_checks.zig");
    const output = try compileMilestoneC(testing.allocator);
    defer testing.allocator.free(output);

    const fn_start = std.mem.indexOf(u8, output, "static inline double distance2") orelse
        return error.TestUnexpectedResult;
    const fn_end_rel = std.mem.indexOf(u8, output[fn_start..], "\n}\n") orelse output.len;
    const body = output[fn_start .. fn_start + fn_end_rel];

    try testing.expect(std.mem.indexOf(u8, body, "lua_invoke") == null);
    try testing.expect(std.mem.indexOf(u8, body, "lua_Value") == null);
    try testing.expect(std.mem.indexOf(u8, body, "lua_to_") == null);
    try testing.expect(std.mem.indexOf(u8, body, "p.x") != null);
    try testing.expect(std.mem.indexOf(u8, body, "p.y") != null);
    try testing.expect(std.mem.indexOf(u8, output, "double x") != null);
    try testing.expect(std.mem.indexOf(u8, output, "double y") != null);

    var report = try native_barrier_checks.checkGeneratedC(testing.allocator, body, &.{ .no_boxing, .no_dynamic_dispatch });
    defer native_barrier_checks.freeReport(testing.allocator, report);
    try testing.expect(report.passed());
}

test "Pass 4 M1: Point table literal uses designated native initializer" {
    const output = try compileMilestoneC(testing.allocator);
    defer testing.allocator.free(output);
    try testing.expect(std.mem.indexOf(u8, output, ".x = ") != null);
    try testing.expect(std.mem.indexOf(u8, output, ".y = ") != null);
    try testing.expect(std.mem.indexOf(u8, output, "duo_rec_") != null);
}

test "Pass 4 M1: direct backend emits distance2 without lua runtime" {
    if (builtin.cpu.arch != .aarch64 or builtin.os.tag != .macos) return error.SkipZigTest;
    const native_backend = @import("native_backend.zig");

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    0
        \\end
    , "pass4_native_milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    const listing = try native_backend.emitAssembly(alloc, &module, "native-asm");
    defer alloc.free(listing);
    try testing.expect(std.mem.indexOf(u8, listing, "_distance2") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "fmul") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);
}

test "Pass 4 M1: full milestone asm has f64 main wrapper and distance2 kernel" {
    if (builtin.cpu.arch != .aarch64 or builtin.os.tag != .macos) return error.SkipZigTest;
    const native_backend = @import("native_backend.zig");

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(milestone_source, "pass4_native_milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    const listing = try native_backend.emitAssembly(alloc, &module, "native-asm");
    defer alloc.free(listing);
    try testing.expect(std.mem.indexOf(u8, listing, "_main") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "fcvtzs x0, d0") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "_distance2") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "fmul") != null);
    try testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);
}

test "Pass 4: @comp.representation and why.not.native compile in native module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\probe(p: Point): str
        \\    rep = @comp.representation(p)
        \\    why = @comp.why.not.native(p)
        \\    boxed = @comp.why.boxed(p)
        \\    rep
        \\end
        \\main(): i64
        \\    0
        \\end
    , "pass4_boundary.duo");
    var parser = Parser.init(&lex, a);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(a);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    var aw: std.Io.Writer.Allocating = .init(a);
    defer aw.deinit();
    var cg = CodeGen.init(
        a,
        undefined,
        &semantic.type_map,
        &semantic.module_globals,
        &aw.writer,
        semantic.next_closure_id,
        &semantic.table_field_types,
        &semantic.concepts,
    );
    cg.duo_mode = true;
    try cg.emit_module(&module);
    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "not boxed on this path") != null);
    try testing.expect(std.mem.indexOf(u8, output, "native lowering applies") != null);
    try testing.expect(std.mem.indexOf(u8, output, "native C scalar") != null or
        std.mem.indexOf(u8, output, "direct field access") != null);
}
