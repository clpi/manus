//! Pass 23 compatibility shim — delegates to `pass23_protocol_registry.zig`.
//!
//! Legacy import path retained for callers that predated the registry split.
//! New code should import `pass23_protocol_registry.zig` directly.
const std = @import("std");
const registry = @import("pass23_protocol_registry.zig");

pub const SCHEMA_VERSION = "protocol-kernel-v0-compat";

/// Stable canonical protocol operation identity (alias of registry `KernelOp`).
pub const Op = registry.KernelOp;

pub const Alias = struct {
    lua_name: []const u8,
    canonical: Op,
    compat_only: bool = true,
};

/// Derived view of registry aliases for legacy struct shape.
pub const lua_aliases: []const Alias = blk: {
    const reg = registry.lua_aliases;
    var out: [reg.len]Alias = undefined;
    for (reg, 0..) |a, i| {
        out[i] = .{
            .lua_name = a.lua_metamethod,
            .canonical = a.op,
            .compat_only = std.mem.eql(u8, a.lua_metamethod, "__tostring"),
        };
    }
    break :blk &out;
};

pub fn resolveLuaAlias(name: []const u8) ?Op {
    const canonical = registry.canonicalOfLuaMetamethod(name) orelse return null;
    return registry.kernelOpFromName(canonical);
}

pub fn resolveName(name: []const u8) ?Op {
    if (resolveLuaAlias(name)) |op| return op;
    return registry.kernelOpFromName(name);
}

pub const ScopedId = struct {
    package: []const u8,
    protocol: []const u8,
    member: []const u8,
    version: u32,

    pub fn hash(self: ScopedId) u64 {
        var h = std.hash.Wyhash.init(0x023A7E11);
        h.update(self.package);
        h.update(self.protocol);
        h.update(self.member);
        h.update(std.mem.asBytes(&self.version));
        return h.final();
    }
};

test "protocol_kernel: Lua __add resolves to add" {
    try std.testing.expect(resolveLuaAlias("__add") == .add);
    try std.testing.expect(resolveName("add") == .add);
}

test "protocol_kernel: __tostring maps to format compat" {
    const op = resolveLuaAlias("__tostring") orelse return error.TestExpectedEqual;
    try std.testing.expect(op == .format);
}

test "protocol_kernel: shim agrees with pass23_protocol_registry" {
    for (registry.lua_aliases) |a| {
        const via_shim = resolveLuaAlias(a.lua_metamethod) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(a.op, via_shim);
    }
    try std.testing.expectEqual(registry.kernelOpCount(), @typeInfo(Op).@"enum".field_names.len);
}
