//! Pass 23 §11–§12 — canonical metaprotocol kernel + Lua compatibility aliases.
//!
//! Single source of truth for `__add` → `add` and kernel operation identity.
//! Parser, sema, codegen, LSP, and MCP must consult this registry — not ad hoc strings.
const std = @import("std");

pub const SCHEMA_VERSION = "pass23-protocol-registry-v0";

pub const Category = enum {
    call_access,
    arithmetic,
    equality_order,
    conversion,
    lifecycle,
    memory,
    construction,
    continuation,
    structural,
};

pub const KernelOp = enum {
    // Call and access
    call,
    index,
    assign,
    contains,
    length,
    iterate,
    // Arithmetic and bit
    add,
    subtract,
    multiply,
    divide,
    integer_divide,
    remainder,
    power,
    negate,
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shift_left,
    shift_right,
    rotate_left,
    rotate_right,
    concat,
    // Equality and ordering
    equal,
    hash,
    compare,
    partial_compare,
    // Conversion and representation
    to,
    from,
    format,
    debug,
    view,
    encode,
    decode,
    parse,
    // Lifecycle and ownership
    clone,
    move,
    share,
    retain,
    drop,
    // Memory access
    borrow,
    borrow_mut,
    address,
    pin,
    deref,
    deref_mut,
    // Construction
    construct,
    validate,
    normalize,
    canonicalize,
    // Continuation
    await,
    poll,
    @"resume",
    cancel,
    enter,
    exit,
    // Structural state
    freeze,
    thaw,
    seal,
    open,
    decompose,
    identity,
};

pub const LuaAlias = struct {
    lua_metamethod: []const u8,
    canonical: []const u8,
    op: KernelOp,
    category: Category,
};

/// Pass 23 §11.4 — centralized Lua metamethod → canonical protocol mapping.
pub const lua_aliases: []const LuaAlias = &.{
    .{ .lua_metamethod = "__index", .canonical = "index", .op = .index, .category = .call_access },
    .{ .lua_metamethod = "__newindex", .canonical = "assign", .op = .assign, .category = .call_access },
    .{ .lua_metamethod = "__call", .canonical = "call", .op = .call, .category = .call_access },
    .{ .lua_metamethod = "__add", .canonical = "add", .op = .add, .category = .arithmetic },
    .{ .lua_metamethod = "__sub", .canonical = "subtract", .op = .subtract, .category = .arithmetic },
    .{ .lua_metamethod = "__mul", .canonical = "multiply", .op = .multiply, .category = .arithmetic },
    .{ .lua_metamethod = "__div", .canonical = "divide", .op = .divide, .category = .arithmetic },
    .{ .lua_metamethod = "__mod", .canonical = "remainder", .op = .remainder, .category = .arithmetic },
    .{ .lua_metamethod = "__pow", .canonical = "power", .op = .power, .category = .arithmetic },
    .{ .lua_metamethod = "__unm", .canonical = "negate", .op = .negate, .category = .arithmetic },
    .{ .lua_metamethod = "__eq", .canonical = "equal", .op = .equal, .category = .equality_order },
    .{ .lua_metamethod = "__lt", .canonical = "compare", .op = .compare, .category = .equality_order },
    .{ .lua_metamethod = "__le", .canonical = "compare", .op = .compare, .category = .equality_order },
    .{ .lua_metamethod = "__len", .canonical = "length", .op = .length, .category = .call_access },
    .{ .lua_metamethod = "__concat", .canonical = "concat", .op = .concat, .category = .arithmetic },
    .{ .lua_metamethod = "__contains", .canonical = "contains", .op = .contains, .category = .call_access },
    .{ .lua_metamethod = "__tostring", .canonical = "format", .op = .format, .category = .conversion },
    .{ .lua_metamethod = "__idiv", .canonical = "integer_divide", .op = .integer_divide, .category = .arithmetic },
    .{ .lua_metamethod = "__band", .canonical = "bit_and", .op = .bit_and, .category = .arithmetic },
    .{ .lua_metamethod = "__bor", .canonical = "bit_or", .op = .bit_or, .category = .arithmetic },
    .{ .lua_metamethod = "__bxor", .canonical = "bit_xor", .op = .bit_xor, .category = .arithmetic },
    .{ .lua_metamethod = "__bnot", .canonical = "bit_not", .op = .bit_not, .category = .arithmetic },
    .{ .lua_metamethod = "__shl", .canonical = "shift_left", .op = .shift_left, .category = .arithmetic },
    .{ .lua_metamethod = "__shr", .canonical = "shift_right", .op = .shift_right, .category = .arithmetic },
};

/// @derive trait → Lua metamethod slot installed on alias metatables (codegen).
pub const DeriveMetamethodBinding = struct {
    derive_trait: []const u8,
    lua_metamethod: []const u8,
    /// C wrapper suffix: `duo_{Type}_{wrapper}__lua`
    c_wrapper_suffix: []const u8,
    op: KernelOp,
    /// Optional canonical method alias on the metatable (e.g. Display → `to_string`).
    method_alias: ?[]const u8 = null,
};

pub const derive_metamethod_bindings: []const DeriveMetamethodBinding = &.{
    .{ .derive_trait = "Display", .lua_metamethod = "__tostring", .c_wrapper_suffix = "tostring", .op = .format, .method_alias = "to_string" },
    .{ .derive_trait = "Eq", .lua_metamethod = "__eq", .c_wrapper_suffix = "eq", .op = .equal, .method_alias = "eq" },
    .{ .derive_trait = "Ord", .lua_metamethod = "__lt", .c_wrapper_suffix = "lt", .op = .compare },
    .{ .derive_trait = "Ord", .lua_metamethod = "__le", .c_wrapper_suffix = "le", .op = .compare },
    .{ .derive_trait = "Add", .lua_metamethod = "__add", .c_wrapper_suffix = "add", .op = .add },
    .{ .derive_trait = "Sub", .lua_metamethod = "__sub", .c_wrapper_suffix = "sub", .op = .subtract },
    .{ .derive_trait = "Mul", .lua_metamethod = "__mul", .c_wrapper_suffix = "mul", .op = .multiply },
    .{ .derive_trait = "Div", .lua_metamethod = "__div", .c_wrapper_suffix = "div", .op = .divide },
    .{ .derive_trait = "Rem", .lua_metamethod = "__mod", .c_wrapper_suffix = "rem", .op = .remainder },
    .{ .derive_trait = "Neg", .lua_metamethod = "__unm", .c_wrapper_suffix = "neg", .op = .negate },
    .{ .derive_trait = "Len", .lua_metamethod = "__len", .c_wrapper_suffix = "len", .op = .length },
    .{ .derive_trait = "BitAnd", .lua_metamethod = "__band", .c_wrapper_suffix = "bit_and", .op = .bit_and },
    .{ .derive_trait = "BitOr", .lua_metamethod = "__bor", .c_wrapper_suffix = "bit_or", .op = .bit_or },
    .{ .derive_trait = "BitXor", .lua_metamethod = "__bxor", .c_wrapper_suffix = "bit_xor", .op = .bit_xor },
    .{ .derive_trait = "BitNot", .lua_metamethod = "__bnot", .c_wrapper_suffix = "bit_not", .op = .bit_not },
    .{ .derive_trait = "Shl", .lua_metamethod = "__shl", .c_wrapper_suffix = "shl", .op = .shift_left },
    .{ .derive_trait = "Shr", .lua_metamethod = "__shr", .c_wrapper_suffix = "shr", .op = .shift_right },
};

/// Runtime C helpers (`lua_add`, …) that dispatch through `lua_binop_metamethod`.
pub const RuntimeBinopBinding = struct {
    op: KernelOp,
    c_func: []const u8,
};

pub const runtime_binop_bindings: []const RuntimeBinopBinding = &.{
    .{ .op = .add, .c_func = "lua_add" },
    .{ .op = .subtract, .c_func = "lua_sub" },
    .{ .op = .multiply, .c_func = "lua_mul" },
    .{ .op = .divide, .c_func = "lua_div" },
    .{ .op = .integer_divide, .c_func = "lua_idiv" },
    .{ .op = .remainder, .c_func = "lua_mod" },
    .{ .op = .power, .c_func = "lua_pow" },
    .{ .op = .bit_and, .c_func = "lua_band" },
    .{ .op = .bit_or, .c_func = "lua_bor" },
    .{ .op = .bit_xor, .c_func = "lua_bxor" },
    .{ .op = .shift_left, .c_func = "lua_lshift" },
    .{ .op = .shift_right, .c_func = "lua_rshift" },
};

/// Runtime C sites that call `lua_get_metafield_lit` with a registered Lua metamethod.
pub const RuntimeMetafieldBinding = struct {
    lua_metamethod: []const u8,
    op: KernelOp,
    c_site: []const u8,
};

pub const runtime_metafield_bindings: []const RuntimeMetafieldBinding = &.{
    .{ .lua_metamethod = "__index", .op = .index, .c_site = "lua_table_get" },
    .{ .lua_metamethod = "__newindex", .op = .assign, .c_site = "lua_table_set" },
    .{ .lua_metamethod = "__concat", .op = .concat, .c_site = "lua_concat" },
    .{ .lua_metamethod = "__unm", .op = .negate, .c_site = "lua_unm" },
    .{ .lua_metamethod = "__bnot", .op = .bit_not, .c_site = "lua_bnot" },
    .{ .lua_metamethod = "__eq", .op = .equal, .c_site = "lua_eq" },
    .{ .lua_metamethod = "__contains", .op = .contains, .c_site = "duo_contains" },
    .{ .lua_metamethod = "__lt", .op = .compare, .c_site = "lua_lt" },
    .{ .lua_metamethod = "__le", .op = .compare, .c_site = "lua_le" },
    .{ .lua_metamethod = "__tostring", .op = .format, .c_site = "lua_tostring" },
    .{ .lua_metamethod = "__len", .op = .length, .c_site = "lua_len" },
};

/// FNV-1a hash for precomputed Lua metamethod table keys (matches runtime `calc_hash`).
pub fn luaHash(lua_metamethod: []const u8) u32 {
    var h: u32 = 2166136261;
    for (lua_metamethod) |c| {
        h ^= @as(u32, c);
        h = h *% 16777619;
    }
    return h;
}

pub fn findLuaAlias(lua_metamethod: []const u8) ?LuaAlias {
    for (lua_aliases) |a| {
        if (std.mem.eql(u8, a.lua_metamethod, lua_metamethod)) return a;
    }
    return null;
}

/// Map a Lua metamethod string to canonical protocol name (e.g. `__add` → `add`).
pub fn canonicalOfLuaMetamethod(lua_metamethod: []const u8) ?[]const u8 {
    const a = findLuaAlias(lua_metamethod) orelse return null;
    return a.canonical;
}

pub fn kernelOpName(op: KernelOp) []const u8 {
    return @tagName(op);
}

pub fn isKernelOp(name: []const u8) bool {
    inline for (@typeInfo(KernelOp).@"enum".field_names) |field_name| {
        if (std.mem.eql(u8, name, field_name)) return true;
    }
    return false;
}

pub fn kernelOpCount() usize {
    return @typeInfo(KernelOp).@"enum".field_names.len;
}

/// Canonical kernel op → Lua metamethod string for runtime tables (Pass 23 §11.4).
pub fn luaMetamethodForKernel(op: KernelOp) ?[]const u8 {
    for (lua_aliases) |a| {
        if (a.op == op) return a.lua_metamethod;
    }
    return null;
}

pub fn kernelOpFromName(name: []const u8) ?KernelOp {
    inline for (@typeInfo(KernelOp).@"enum".field_names) |field_name| {
        if (std.mem.eql(u8, name, field_name)) return @field(KernelOp, field_name);
    }
    return null;
}

/// Resolve Lua metamethod or canonical kernel name to the Lua table key for emission.
pub fn resolveToLuaMetamethod(name: []const u8) []const u8 {
    if (findLuaAlias(name)) |a| return a.lua_metamethod;
    if (kernelOpFromName(name)) |op| {
        if (luaMetamethodForKernel(op)) |mm| return mm;
    }
    return name;
}

test "pass23_protocol_registry: lua alias coverage" {
    try std.testing.expect(findLuaAlias("__add") != null);
    try std.testing.expectEqualStrings("add", canonicalOfLuaMetamethod("__add").?);
    try std.testing.expectEqualStrings("format", canonicalOfLuaMetamethod("__tostring").?);
    try std.testing.expect(canonicalOfLuaMetamethod("__nope") == null);
    try std.testing.expectEqualStrings("__add", luaMetamethodForKernel(.add).?);
    try std.testing.expect(kernelOpCount() >= 40);
    try std.testing.expectEqualStrings("__add", resolveToLuaMetamethod("add"));
    try std.testing.expectEqualStrings("__tostring", resolveToLuaMetamethod("__tostring"));
    try std.testing.expect(derive_metamethod_bindings.len >= 16);
    try std.testing.expect(runtime_binop_bindings.len >= 12);
    inline for (runtime_binop_bindings) |b| {
        try std.testing.expect(luaMetamethodForKernel(b.op) != null);
    }
    try std.testing.expect(runtime_metafield_bindings.len >= 11);
    for (runtime_metafield_bindings) |b| {
        try std.testing.expect(findLuaAlias(b.lua_metamethod) != null);
        try std.testing.expectEqual(b.op, findLuaAlias(b.lua_metamethod).?.op);
        try std.testing.expect(luaHash(b.lua_metamethod) != 0);
    }
}
