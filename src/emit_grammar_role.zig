const std = @import("std");
const grammar_role_gen = @import("grammar_role_gen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    try grammar_role_gen.emitGrammarRoleFile(alloc, threaded.io(), "lib/token/grammarrole.id");
    std.debug.print("wrote lib/token/grammarrole.id\n", .{});
}
