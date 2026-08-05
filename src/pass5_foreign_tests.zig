const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");
const codegen = @import("codegen.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

const smoke_src =
    \\@comp.c.import("fixtures/point.h")
    \\main(): f64
    \\    p: CPoint = { x = 3.0, y = 4.0 }
    \\    distance2(p)
    \\end
;

const smoke_path = "examples/pass5/c_point_smoke.duo";

const big_rect_src =
    \\@comp.c.import("fixtures/big_rect.h")
    \\main(): f64
    \\    r: CBigRect = { a = 1.0, b = 2.0, c = 3.0, d = 4.0 }
    \\    sum4(r)
    \\end
;

const big_rect_path = "examples/pass5/c_big_rect_smoke.duo";

const CompiledModule = struct {
    c_out: []const u8,
    semantic: sema.Sema,
    mod: ast.Module,
};

fn compileForeignModule(
    alloc: std.mem.Allocator,
    src: []const u8,
    source_path: []const u8,
) !CompiledModule {
    var lex = Lexer.init(src, source_path);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();

    var semantic = sema.Sema.init(alloc);
    semantic.duo_mode = true;
    semantic.source_path = try alloc.dupe(u8, source_path);
    try semantic.check_module(&mod);
    try std.testing.expectEqual(@as(u32, 0), semantic.errors);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    var cg = codegen.CodeGen.init(alloc, undefined, &semantic.type_map, &semantic.module_globals, &aw.writer, semantic.next_closure_id, &semantic.table_field_types, &semantic.concepts);
    cg.duo_mode = true;
    cg.foreign_records = &semantic.foreign_records;
    cg.foreign_functions = &semantic.foreign_functions;
    try cg.emit_module(&mod);
    const c_out = try aw.toOwnedSlice();
    return .{ .c_out = c_out, .semantic = semantic, .mod = mod };
}

fn compileSmokeModule(alloc: std.mem.Allocator) !CompiledModule {
    const compiled = try compileForeignModule(alloc, smoke_src, smoke_path);
    try std.testing.expect(compiled.semantic.foreign_records.get("CPoint") != null);
    try std.testing.expect(compiled.semantic.foreign_functions.get("distance2") != null);
    return compiled;
}

fn expectNativeForeignCall(c_out: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, c_out, "#include \"fixtures/point.h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "extern double distance2(CPoint") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "CPoint p = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, ".x = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "return distance2(p);") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "duo_CPoint") == null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "lua_table_new") == null);
    try std.testing.expect(std.mem.indexOf(u8, c_out, "duo_retain") == null);
}

test "pass5: foreign CPoint + distance2 type-check and codegen" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const compiled = try compileSmokeModule(alloc);
    defer alloc.free(compiled.c_out);
    try expectNativeForeignCall(compiled.c_out);
}

test "pass5: foreign distance2 links and returns 25" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const compiled = try compileSmokeModule(alloc);
    defer alloc.free(compiled.c_out);

    const tmp_base = "/tmp/duo_pass5_foreign";
    const c_path = tmp_base ++ ".c";
    const exe_path = tmp_base;

    {
        var cf = try cwd.createFile(io, c_path, .{});
        defer cf.close(io);
        try cf.writeStreamingAll(io, compiled.c_out);
    }

    const fixture_dir = "examples/pass5/fixtures";
    const pass5_dir = "examples/pass5";
    const point_c = "examples/pass5/fixtures/point.c";
    const clang_cmd = try std.fmt.allocPrint(
        alloc,
        "clang -std=c11 -O2 -I{s} -I{s} {s} {s} -lm -o {s}",
        .{ pass5_dir, fixture_dir, c_path, point_c, exe_path },
    );
    defer alloc.free(clang_cmd);

    const argv = [_][]const u8{ "/bin/sh", "-c", clang_cmd };
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    });
    const build_result = try child.wait(io);
    switch (build_result) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.LinkFailed,
    }

    var run_child = try std.process.spawn(io, .{
        .argv = &.{exe_path},
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const run_result = try run_child.wait(io);
    switch (run_result) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 25), code),
        else => return error.RunFailed,
    }

    cwd.deleteFile(io, c_path) catch {};
    cwd.deleteFile(io, exe_path) catch {};
}

test "pass5: abi.specialize pointer pass for large CBigRect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const compiled = try compileForeignModule(alloc, big_rect_src, big_rect_path);
    defer alloc.free(compiled.c_out);
    const sum4 = compiled.semantic.foreign_functions.get("sum4") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), sum4.params.len);
    try std.testing.expect(sum4.params[0] == .pointer);
    try std.testing.expectEqualStrings("pointer", sum4.pass_by);
    try std.testing.expect(std.mem.indexOf(u8, compiled.c_out, "extern double sum4") != null);
    try std.testing.expect(std.mem.indexOf(u8, compiled.c_out, "CBigRect") != null);
    try std.testing.expect(std.mem.indexOf(u8, compiled.c_out, "return sum4(&r);") != null);
}

test "pass5: foreign sum4 links and returns 10" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const compiled = try compileForeignModule(alloc, big_rect_src, big_rect_path);
    defer alloc.free(compiled.c_out);

    const tmp_base = "/tmp/duo_pass5_big_rect";
    const c_path = tmp_base ++ ".c";
    const exe_path = tmp_base;

    {
        var cf = try cwd.createFile(io, c_path, .{});
        defer cf.close(io);
        try cf.writeStreamingAll(io, compiled.c_out);
    }

    const fixture_dir = "examples/pass5/fixtures";
    const pass5_dir = "examples/pass5";
    const rect_c = "examples/pass5/fixtures/big_rect.c";
    const clang_cmd = try std.fmt.allocPrint(
        alloc,
        "clang -std=c11 -O2 -I{s} -I{s} {s} {s} -lm -o {s}",
        .{ pass5_dir, fixture_dir, c_path, rect_c, exe_path },
    );
    defer alloc.free(clang_cmd);

    const argv = [_][]const u8{ "/bin/sh", "-c", clang_cmd };
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    });
    const build_result = try child.wait(io);
    switch (build_result) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.LinkFailed,
    }

    var run_child = try std.process.spawn(io, .{
        .argv = &.{exe_path},
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const run_result = try run_child.wait(io);
    switch (run_result) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 10), code),
        else => return error.RunFailed,
    }

    cwd.deleteFile(io, c_path) catch {};
    cwd.deleteFile(io, exe_path) catch {};
}
