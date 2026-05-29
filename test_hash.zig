const std = @import("std");
pub fn main() !void {
    var h: u32 = 2166136261;
    for ("pi") |c| {
        h ^= @as(u32, c);
        h = h *% 16777619;
    }
    std.debug.print("hash(pi) = {d}\n", .{h});
}
