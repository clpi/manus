const std = @import("std");
pub fn main() void {
    var x = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 10);
    _ = x;
}
