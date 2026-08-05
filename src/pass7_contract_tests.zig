//! Pass 7 — contract enforcement tests (noalloc, explain pipeline).
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const explain_pipeline = @import("explain_pipeline.zig");
const optimization_outcome = @import("optimization_outcome.zig");
const transform_engine = @import("transform_engine.zig");

const noalloc_ok_src =
    \\@noalloc
    \\fun sum2(a: i64, b: i64): i64
    \\    a + b
    \\end
    \\
    \\main(): i64
    \\    sum2(1, 2)
    \\end
;

const noalloc_fail_src =
    \\@noalloc
    \\fun leak(): i64
    \\    raw: *u8 = mem.alloc(64)
    \\    mem.free(raw)
    \\    0
    \\end
    \\
    \\main(): i64
    \\    leak()
    \\end
;

fn parseCheck(alloc: std.mem.Allocator, src: []const u8, file: []const u8) !@import("ast.zig").Module {
    var lex = Lexer.init(src, file);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    return mod;
}

test "pass7: noalloc ok module codegen succeeds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseCheck(alloc, noalloc_ok_src, "noalloc_ok.duo");
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try explain_pipeline.runForProvenance(alloc, io, &mod, &semantic, "noalloc_ok.duo", null);
    defer optimization_outcome.deinitSession(alloc);
}

test "pass7: noalloc fail rejects mem.alloc at codegen" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseCheck(alloc, noalloc_fail_src, "noalloc_fail.duo");
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    optimization_outcome.deinitSession(alloc);
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const result = explain_pipeline.runForProvenance(alloc, io, &mod, &semantic, "noalloc_fail.duo", null);
    try std.testing.expectError(error.NoAllocViolation, result);
    var outcomes = try optimization_outcome.fromProvenance(alloc);
    defer outcomes.deinit(alloc);
    try optimization_outcome.mergeSessionInto(alloc, &outcomes);
    optimization_outcome.deinitSession(alloc);
    defer optimization_outcome.deinitSession(alloc);
    var found = false;
    for (outcomes.items) |o| {
        if (std.mem.eql(u8, o.transformation, "contract.noalloc") and o.status == .rejected) {
            found = true;
            try std.testing.expect(o.reason != null);
        }
    }
    try std.testing.expect(found);
}
