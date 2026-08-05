//! Pass 5 golden SIM snapshot fixtures — stable entity ids and formatting invariance.
const std = @import("std");
const sim = @import("sim.zig");
const c_sim_import = @import("c_sim_import.zig");
const abi_specialize = @import("abi_specialize.zig");

const point_h = @import("pass5_fixtures.zig").point_h;

test "pass5 golden: C point.h SIM entity ids" {
    var snap = try c_sim_import.importHeaderSource(std.testing.allocator, "examples/pass5/fixtures/point.h", point_h);
    defer snap.deinit(std.testing.allocator);
    try abi_specialize.specializeSnapshot(std.testing.allocator, &snap);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try sim.writeSnapshotJson(&snap, &aw.writer);
    const json = aw.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"c:record:CPoint\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"c:function:distance2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"origin_language\":\"c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"abi_completeness\":\"complete\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"calling_convention\":\"c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pass_by\":\"value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"storage_class\":\"native\"") != null);

    aw.deinit();
    aw = .init(std.testing.allocator);
    try sim.writeSnapshotJson(&snap, &aw.writer);
    try std.testing.expectEqualStrings(json, aw.written());
}

test "pass5 golden: native Duo Point SIM export" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const sema = @import("sema.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
    , "examples/pass4_native_milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);

    var snap = try sim.exportNativeModule(alloc, &mod, "examples/pass4_native_milestone.duo");
    defer snap.deinit(alloc);
    try abi_specialize.specializeSnapshot(alloc, &snap);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try sim.writeSnapshotJson(&snap, &aw.writer);
    const json = aw.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"duo:record:Point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"duo:function:distance2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"origin_language\":\"duo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"storage_class\":\"native\"") != null);
}
