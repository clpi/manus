const std = @import("std");
const abi_resource = @import("abi_resource.zig");

pub const ForeignLiftMetadata = struct {
    boundary_id: []const u8,
    calling_conv: abi_resource.CallingConventionKind,
};

pub fn foreignLiftMetadata(pass_by: []const u8) ForeignLiftMetadata {
    _ = pass_by;
    return .{
        .boundary_id = "P26-B02",
        .calling_conv = .c_abi,
    };
}

test "foreign metadata" {
    const meta = foreignLiftMetadata("value");
    try std.testing.expectEqualStrings("P26-B02", meta.boundary_id);
    try std.testing.expect(meta.calling_conv == .c_abi);
}
