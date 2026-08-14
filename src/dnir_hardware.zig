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

/// Module-level hardware descriptor — one row per intrinsic exercised (WS23).
pub const Descriptor = struct {
    intrinsic: HwIntrinsic,
    tier: Tier,
    arm64_hint: []const u8,
    use_count: u32,
};

pub fn catalogEntry(h: HwIntrinsic) ?CatalogEntry {
    for (catalog) |e| {
        if (e.intrinsic == h) return e;
    }
    return null;
}

pub fn intrinsicOfOp(op: @import("native_ir.zig").Op, hw: HwIntrinsic) ?HwIntrinsic {
    const dnir = @import("native_ir.zig");
    return switch (op) {
        dnir.Op.hw_fence => .fence,
        dnir.Op.hw_spin => .spin_wait,
        dnir.Op.hw_unary => if (hw != .none) hw else null,
        else => null,
    };
}

pub fn functionHardwareTier(f: @import("native_ir.zig").Function) Tier {
    var tier: Tier = .scalar;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            const h = intrinsicOfOp(ins.op, ins.hw) orelse continue;
            const t = h.tier();
            if (@intFromEnum(t) > @intFromEnum(tier)) tier = t;
        }
    }
    return tier;
}

/// Collect deduplicated hardware descriptors used in a DNIR module.
pub fn collectModuleDescriptors(alloc: std.mem.Allocator, m: @import("native_ir.zig").Module) ![]Descriptor {
    var counts: std.AutoHashMapUnmanaged(HwIntrinsic, u32) = .{};
    defer counts.deinit(alloc);

    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                const h = intrinsicOfOp(ins.op, ins.hw) orelse continue;
                const gop = try counts.getOrPut(alloc, h);
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
            }
        }
    }

    var out: std.ArrayListUnmanaged(Descriptor) = .empty;
    errdefer out.deinit(alloc);
    var it = counts.iterator();
    while (it.next()) |e| {
        const entry = catalogEntry(e.key_ptr.*) orelse continue;
        try out.append(alloc, .{
            .intrinsic = e.key_ptr.*,
            .tier = entry.tier,
            .arm64_hint = entry.arm64,
            .use_count = e.value_ptr.*,
        });
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeModuleDescriptors(alloc: std.mem.Allocator, descs: []Descriptor) void {
    alloc.free(descs);
}

test "dnir_hardware: parse bare intrinsics" {
    try std.testing.expect(parseIntrinsic("__popcount") == .popcount);
    try std.testing.expect(parseIntrinsic("fence") == .fence);
    try std.testing.expect(parseIntrinsic("nope") == null);
}

test "dnir_hardware: arm64 fence word" {
    try std.testing.expect(arm64FixedWord(.fence) == 0xd5033bbf);
}

test "dnir_hardware: collectModuleDescriptors" {
    const dnir = @import("native_ir.zig");
    const m = dnir.Module{
        .functions = &.{
            .{
                .name = "main",
                .ret = .i64,
                .blocks = &.{
                    .{
                        .instrs = &.{
                            .{ .op = .hw_fence },
                            .{ .op = .hw_unary, .hw = .popcount, .result = 0, .lhs = .{ .i64 = 47 } },
                            .{ .op = .hw_fence },
                        },
                    },
                },
            },
        },
    };
    const descs = try collectModuleDescriptors(std.testing.allocator, m);
    defer freeModuleDescriptors(std.testing.allocator, descs);
    try std.testing.expect(descs.len >= 2);
    var saw_fence = false;
    var saw_pop = false;
    for (descs) |d| {
        if (d.intrinsic == .fence) {
            saw_fence = true;
            try std.testing.expectEqual(@as(u32, 2), d.use_count);
        }
        if (d.intrinsic == .popcount) {
            saw_pop = true;
            try std.testing.expectEqual(@as(u32, 1), d.use_count);
        }
    }
    try std.testing.expect(saw_fence and saw_pop);
}
