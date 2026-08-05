//! Pass 8 — codegen ↔ realization outcome bridge tests.
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const sema = @import("sema.zig");
const explain_pipeline = @import("explain_pipeline.zig");
const optimization_outcome = @import("optimization_outcome.zig");
const transform_engine = @import("transform_engine.zig");

const point_src =
    \\Point: @{ x: f64, y: f64 }
    \\main(): f64
    \\    p = Point { x = 1.0, y = 2.0 }
    \\    p.x
    \\end
;

test "pass8: codegen logs realization.representation for native Point" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(point_src, "point.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
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
    try explain_pipeline.runForProvenance(alloc, io, &mod, &semantic, "point.duo", null);

    var outcomes = try optimization_outcome.fromProvenance(alloc);
    defer outcomes.deinit(alloc);
    try optimization_outcome.mergeSessionInto(alloc, &outcomes);
    defer optimization_outcome.deinitSession(alloc);

    var found = false;
    for (outcomes.items) |o| {
        if (std.mem.eql(u8, o.transformation, "realization.representation") and o.status == .applied) {
            found = true;
            try std.testing.expect(o.entity != null);
            try std.testing.expect(std.mem.indexOf(u8, o.entity.?, "Point") != null);
            try std.testing.expect(o.after_repr != null);
            try std.testing.expect(std.mem.eql(u8, o.after_repr.?, "native_aggregate"));
        }
    }
    try std.testing.expect(found);
}
