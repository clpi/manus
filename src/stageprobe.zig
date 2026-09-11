const std = @import("std");
const semantic_graph = @import("graph.zig");
const dnir = @import("native/ir.zig");
const lower = @import("graph/lower.zig");
const subject_home = @import("subject_home.zig");

fn stageWorldMember(name: []const u8) bool {
    return switch (subject_home.bareReach(name)) {
        .one => true,
        .none, .ambiguous => false,
    };
}

fn stageProbeLower(alloc: std.mem.Allocator, source: []const u8, file: []const u8) !struct { err: ?lower.Error, note: []const u8 } {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const table_apply = @import("table_apply.zig");
    const MacroExpand = @import("macro_expand.zig");
    var lexer = Lexer.init(source, file);
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var expander = MacroExpand.Expander.init(alloc);
    defer expander.deinit();
    expander.world_member = stageWorldMember;
    try expander.expandModule(&module);
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    try std.testing.expectEqual(@as(u32, 0), checked.errors);
    table_apply.normalizeModule(alloc, &module, &checked.type_map);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, file);
    var diagnostic: lower.Diagnostic = .{};
    if (lower.lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic)) |lowered| {
        dnir.deinitModule(alloc, lowered);
        return .{ .err = null, .note = try alloc.dupe(u8, diagnostic.note() orelse "") };
    } else |e| {
        return .{ .err = e, .note = try alloc.dupe(u8, diagnostic.note() orelse "") };
    }
}

test "dnir_lower: compile-stage refusal names the drawn world" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const drawn = try stageProbeLower(alloc, "main: i64 = ()\n    os.exit(0)\n    print(@(os.cwd()))\n    0\n", "stage-drawn-world.id");
    try std.testing.expectEqual(@as(?lower.Error, error.UnsupportedConstruct), drawn.err);
    try std.testing.expectEqualStrings("compile-stage-absent:os", drawn.note);
    const solo = try stageProbeLower(alloc, "print(@(cwd()))\n", "stage-solo-world.id");
    try std.testing.expectEqual(@as(?lower.Error, error.UnsupportedConstruct), solo.err);
    try std.testing.expectEqualStrings("compile-stage-absent", solo.note);
    const folded = try stageProbeLower(alloc, "print(@(1 + 2))\n", "stage-scalar-control.id");
    try std.testing.expectEqual(@as(?lower.Error, null), folded.err);
}
