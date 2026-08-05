sed -i '' 's/try std.testing.expect(std.mem.indexOf(u8, body, "wasm.i32.add") != null);/try std.testing.expect(std.mem.indexOf(u8, body, "return 2") != null);\n    try std.testing.expect(std.mem.indexOf(u8, body, "return 1") == null);/' src/native_barrier_checks.zig
sed -i '' '/var aw = std.ArrayList(u8).init(std.testing.allocator);/d' src/native_barrier_checks.zig
sed -i '' '/defer aw.deinit();/d' src/native_barrier_checks.zig
