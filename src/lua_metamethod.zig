//! Exact foreign Lua metamethod projection used by generated-C emission.
//!
//! Native relations are graph-owned. This file carries only Lua spellings and
//! their physical generated-C bindings; it does not define native operations.
const std = @import("std");

pub const Metamethod = enum {
    __index,
    __newindex,
    __call,
    __add,
    __sub,
    __mul,
    __div,
    __mod,
    __pow,
    __unm,
    __eq,
    __lt,
    __le,
    __len,
    __concat,
    __contains,
    __tostring,
    __idiv,
    __band,
    __bor,
    __bxor,
    __bnot,
    __shl,
    __shr,

    pub fn text(self: Metamethod) []const u8 {
        return @tagName(self);
    }
};

pub fn parse(text: []const u8) ?Metamethod {
    return std.meta.stringToEnum(Metamethod, text);
}

/// A derive-generated wrapper installed in a Lua metatable.
pub const DeriveBinding = struct {
    derive_trait: []const u8,
    metamethod: Metamethod,
    c_wrapper_suffix: []const u8,
    method_alias: ?[]const u8 = null,
};

pub const derive_bindings: []const DeriveBinding = &.{
    .{ .derive_trait = "Display", .metamethod = .__tostring, .c_wrapper_suffix = "tostring", .method_alias = "to_string" },
    .{ .derive_trait = "Eq", .metamethod = .__eq, .c_wrapper_suffix = "eq", .method_alias = "eq" },
    .{ .derive_trait = "Ord", .metamethod = .__lt, .c_wrapper_suffix = "lt" },
    .{ .derive_trait = "Ord", .metamethod = .__le, .c_wrapper_suffix = "le" },
    .{ .derive_trait = "Add", .metamethod = .__add, .c_wrapper_suffix = "add" },
    .{ .derive_trait = "Sub", .metamethod = .__sub, .c_wrapper_suffix = "sub" },
    .{ .derive_trait = "Mul", .metamethod = .__mul, .c_wrapper_suffix = "mul" },
    .{ .derive_trait = "Div", .metamethod = .__div, .c_wrapper_suffix = "div" },
    .{ .derive_trait = "Rem", .metamethod = .__mod, .c_wrapper_suffix = "rem" },
    .{ .derive_trait = "Neg", .metamethod = .__unm, .c_wrapper_suffix = "neg" },
    .{ .derive_trait = "Len", .metamethod = .__len, .c_wrapper_suffix = "len" },
    .{ .derive_trait = "BitAnd", .metamethod = .__band, .c_wrapper_suffix = "bit_and" },
    .{ .derive_trait = "BitOr", .metamethod = .__bor, .c_wrapper_suffix = "bit_or" },
    .{ .derive_trait = "BitXor", .metamethod = .__bxor, .c_wrapper_suffix = "bit_xor" },
    .{ .derive_trait = "BitNot", .metamethod = .__bnot, .c_wrapper_suffix = "bit_not" },
    .{ .derive_trait = "Shl", .metamethod = .__shl, .c_wrapper_suffix = "shl" },
    .{ .derive_trait = "Shr", .metamethod = .__shr, .c_wrapper_suffix = "shr" },
};

pub const runtime_binop_metamethods: []const Metamethod = &.{
    .__add,
    .__sub,
    .__mul,
    .__div,
    .__idiv,
    .__mod,
    .__pow,
    .__band,
    .__bor,
    .__bxor,
    .__shl,
    .__shr,
};

pub const runtime_metafield_metamethods: []const Metamethod = &.{
    .__index,
    .__newindex,
    .__concat,
    .__unm,
    .__bnot,
    .__eq,
    .__contains,
    .__lt,
    .__le,
    .__tostring,
    .__len,
};

/// FNV-1a for Lua table keys, matching the foreign runtime's `calc_hash`.
pub fn hash(comptime metamethod: Metamethod) u32 {
    var result: u32 = 2166136261;
    for (metamethod.text()) |byte| {
        result ^= @as(u32, byte);
        result = result *% 16777619;
    }
    return result;
}

test "exact Lua metamethod projection" {
    try std.testing.expectEqual(Metamethod.__add, parse("__add").?);
    try std.testing.expect(parse("add") == null);
    try std.testing.expect(parse("__nope") == null);
    try std.testing.expectEqualStrings("__tostring", Metamethod.__tostring.text());
    try std.testing.expect(derive_bindings.len >= 16);
    try std.testing.expect(runtime_binop_metamethods.len >= 12);
    try std.testing.expect(runtime_metafield_metamethods.len >= 11);
    inline for (runtime_binop_metamethods) |metamethod| {
        try std.testing.expect(hash(metamethod) != 0);
    }
    inline for (runtime_metafield_metamethods) |metamethod| {
        try std.testing.expect(hash(metamethod) != 0);
    }
}
