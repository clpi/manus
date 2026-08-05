//! Pass 16 §22.3 — compiler capability closure matrix.
const std = @import("std");

pub const SCHEMA_VERSION = "compiler-capability-matrix-v0";

pub const Support = enum {
    proven,
    partial,
    open,
    bootstrap_only,

    pub fn name(self: Support) []const u8 {
        return @tagName(self);
    }
};

pub const Requirement = struct {
    id: []const u8,
    feature: []const u8,
    stdlib: Support,
    runtime: Support,
    backend_c: Support,
    backend_direct: Support,
    target_arm64: Support,
    proof: []const u8,
};

/// Language/runtime features the self-hosted compiler will require.
pub const requirements: []const Requirement = &.{
    .{ .id = "CC-01", .feature = "integers i64/u64", .stdlib = .proven, .runtime = .proven, .backend_c = .proven, .backend_direct = .proven, .target_arm64 = .proven, .proof = "benchmark + native_scalar_mode" },
    .{ .id = "CC-02", .feature = "native strings (str)", .stdlib = .partial, .runtime = .partial, .backend_c = .proven, .backend_direct = .partial, .target_arm64 = .partial, .proof = "strcmp lowering in codegen" },
    .{ .id = "CC-03", .feature = "sealed records / tables", .stdlib = .partial, .runtime = .partial, .backend_c = .proven, .backend_direct = .partial, .target_arm64 = .open, .proof = "pass4 milestone Point" },
    .{ .id = "CC-04", .feature = "loops and conditionals", .stdlib = .proven, .runtime = .proven, .backend_c = .proven, .backend_direct = .proven, .target_arm64 = .proven, .proof = "general codegen" },
    .{ .id = "CC-05", .feature = "native calls and closures", .stdlib = .partial, .runtime = .partial, .backend_c = .partial, .backend_direct = .open, .target_arm64 = .open, .proof = "pass11 WP-06/07 open" },
    .{ .id = "CC-06", .feature = "return packs / errors", .stdlib = .open, .runtime = .open, .backend_c = .partial, .backend_direct = .open, .target_arm64 = .open, .proof = "pass11 deferred" },
    .{ .id = "CC-07", .feature = "arenas / bump allocation", .stdlib = .open, .runtime = .open, .backend_c = .bootstrap_only, .backend_direct = .open, .target_arm64 = .open, .proof = "compiler memory model open" },
    .{ .id = "CC-08", .feature = "dense maps / interning", .stdlib = .partial, .runtime = .partial, .backend_c = .partial, .backend_direct = .open, .target_arm64 = .open, .proof = "dynamic tables today" },
    .{ .id = "CC-09", .feature = "file I/O", .stdlib = .partial, .runtime = .proven, .backend_c = .proven, .backend_direct = .open, .target_arm64 = .open, .proof = "libc + host read" },
    .{ .id = "CC-10", .feature = "object emission / executable", .stdlib = .open, .runtime = .open, .backend_c = .bootstrap_only, .backend_direct = .partial, .target_arm64 = .partial, .proof = "native_backend Mach-O subset" },
    .{ .id = "CC-11", .feature = "compile-time @comp.*", .stdlib = .partial, .runtime = .partial, .backend_c = .partial, .backend_direct = .open, .target_arm64 = .open, .proof = "meta_module + codegen hooks" },
    .{ .id = "CC-12", .feature = "byte slices / cursors", .stdlib = .partial, .runtime = .open, .backend_c = .open, .backend_direct = .open, .target_arm64 = .open, .proof = "lib/std/compiler/source.duo sketch" },
};

pub fn writeMatrixJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"requirements\":[", .{SCHEMA_VERSION});
    for (requirements, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"feature\":\"{s}\",\"stdlib\":\"{s}\",\"runtime\":\"{s}\",\"backend_c\":\"{s}\",\"backend_direct\":\"{s}\",\"target_arm64\":\"{s}\",\"proof\":\"{s}\"}}",
            .{
                r.id, r.feature, r.stdlib.name(), r.runtime.name(), r.backend_c.name(),
                r.backend_direct.name(), r.target_arm64.name(), r.proof,
            },
        );
    }
    try w.writeAll("]}");
}

test "compiler_capability_matrix: twelve requirements" {
    try std.testing.expectEqual(@as(usize, 12), requirements.len);
}
