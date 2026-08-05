//! DNIR hardware surface — machine intrinsics below the C bootstrap floor.
//!
//! Typed programs lower `@fence`, `@popcount`, `@clz`, `@ctz`, and spin hints
//! into DNIR `hw_*` ops, then straight to ARM64 (or target-specific backends).
//! No `__builtin_*`, no `lua_Value`, no C-string codegen on these paths.
const std = @import("std");

pub const SCHEMA_VERSION = "dnir-hardware-v0";

/// Capability tier — ordered from portable scalar to OS/syscall class.
pub const Tier = enum {
    /// Bit ops, fences, yield — every native target.
    scalar,
    /// Vector/SIMD lanes (future DNIR `hw_simd` family).
    vector,
    /// Syscalls, MMIO, GPU dispatch (capability-gated).
    system,

    pub fn name(self: Tier) []const u8 {
        return @tagName(self);
    }
};

pub const HwIntrinsic = enum {
    none,
    fence,
    spin_wait,
    popcount,
    clz,
    ctz,

    pub fn tier(self: HwIntrinsic) Tier {
        return switch (self) {
            .none => .scalar,
            .fence, .spin_wait, .popcount, .clz, .ctz => .scalar,
        };
    }

    pub fn duoName(self: HwIntrinsic) []const u8 {
        return switch (self) {
            .none => "none",
            .fence => "fence",
            .spin_wait => "spin_wait",
            .popcount => "popcount",
            .clz => "clz",
            .ctz => "ctz",
        };
    }
};

/// Map internal / bare @-directive callee names to hardware intrinsics.
pub fn parseIntrinsic(name: []const u8) ?HwIntrinsic {
    if (std.mem.eql(u8, name, "__fence") or std.mem.eql(u8, name, "fence")) return .fence;
    if (std.mem.eql(u8, name, "__spin_wait") or std.mem.eql(u8, name, "spin_wait")) return .spin_wait;
    if (std.mem.eql(u8, name, "__popcount") or std.mem.eql(u8, name, "popcount")) return .popcount;
    if (std.mem.eql(u8, name, "__clz") or std.mem.eql(u8, name, "clz")) return .clz;
    if (std.mem.eql(u8, name, "__ctz") or std.mem.eql(u8, name, "ctz")) return .ctz;
    return null;
}

/// Fixed ARM64 A64 encodings (no assembler pass — sovereign object bytes).
pub fn arm64FixedWord(h: HwIntrinsic) ?u32 {
    return switch (h) {
        .fence => 0xd5033bbf, // dmb ish
        .spin_wait => 0xd503203f, // yield
        .none, .popcount, .clz, .ctz => null,
    };
}

pub fn arm64UnaryWord(h: HwIntrinsic, dst: u5, src: u5) ?u32 {
    const rn: u32 = src;
    const rd: u32 = dst;
    return switch (h) {
        .popcount => 0x5ac02000 | (rn << 5) | rd, // cnt xd, xn
        .clz => 0xdac01000 | (rn << 5) | rd, // clz xd, xn
        .ctz => null, // lowered as rbit + clz in backend
        else => null,
    };
}

pub const CatalogEntry = struct {
    intrinsic: HwIntrinsic,
    tier: Tier,
    arm64: []const u8,
    duo_surface: []const u8,
};

pub const catalog: []const CatalogEntry = &.{
    .{ .intrinsic = .fence, .tier = .scalar, .arm64 = "dmb ish", .duo_surface = "@fence / @comp.hint.fence" },
    .{ .intrinsic = .spin_wait, .tier = .scalar, .arm64 = "yield", .duo_surface = "std.hardware.spin_wait" },
    .{ .intrinsic = .popcount, .tier = .scalar, .arm64 = "gpr-loop", .duo_surface = "@popcount / @comp.bit.popcount" },
    .{ .intrinsic = .clz, .tier = .scalar, .arm64 = "clz", .duo_surface = "@clz / @comp.bit.clz" },
    .{ .intrinsic = .ctz, .tier = .scalar, .arm64 = "rbit+clz", .duo_surface = "@ctz / @comp.bit.ctz" },
};

test "dnir_hardware: parse bare intrinsics" {
    try std.testing.expect(parseIntrinsic("__popcount") == .popcount);
    try std.testing.expect(parseIntrinsic("fence") == .fence);
    try std.testing.expect(parseIntrinsic("nope") == null);
}

test "dnir_hardware: arm64 fence word" {
    try std.testing.expect(arm64FixedWord(.fence) == 0xd5033bbf);
}
