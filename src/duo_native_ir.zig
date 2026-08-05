//! Duo Native IR (DNIR) — canonical typed lowering between sema and backends.
//!
//! Machine code is the release target. C emission is bootstrap/debug only.
//! DNIR is SSA-ish: native scalars, records, direct calls — consumed by
//! `dnir_backend.zig` (ARM64 Mach-O) without lua_Value.
const std = @import("std");
const types = @import("types.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const RT = types.ResolvedType;

pub const HwIntrinsic = dnir_hardware.HwIntrinsic;
pub const HardwareTier = dnir_hardware.Tier;

/// Preferred lowering tier for a compiled module (release order).
pub const LoweringTier = enum {
    /// ARM64/WASM/GPU machine object — canonical.
    machine,
    /// Generated C + host compiler — bootstrap only.
    c_emit,
    /// Lua/runtime boxed path — dynamic programs only.
    dynamic,

    pub fn dominates(self: LoweringTier, other: LoweringTier) bool {
        return @intFromEnum(self) <= @intFromEnum(other);
    }
};

pub fn preferredTier(native_eligible: bool, dnir_ready: bool) LoweringTier {
    _ = dnir_ready;
    if (native_eligible) return .machine;
    return .dynamic;
}

pub const FieldKind = enum { i64, str };

pub const RecordDesc = struct {
    name: []const u8,
    fields: []const []const u8,
    kinds: []const FieldKind,
};

pub const BinOpTag = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    gt,
    leq,
    geq,
};

pub const Op = enum {
    const_i64,
    const_f64,
    const_str,
    const_req,
    load_local,
    store_local,
    load_field,
    store_field,
    init_record,
    load_index,
    store_index,
    load_global,
    binop,
    cmp,
    call_direct,
    call_extern,
    br,
    br_if,
    br_if_not,
    ret,
    ret_record,
    /// Sovereign machine barrier — `dmb` / `mfence` class (never C emit).
    hw_fence,
    /// CPU spin hint — `yield` / `pause` class.
    hw_spin,
    /// Unary hardware/bit op — see `Instr.hw`.
    hw_unary,
};

pub const Value = union(enum) {
    void,
    i64: i64,
    f64: f64,
    str: []const u8,
    local: u32,
    temp: u32,
    record: u32,
};

pub const Instr = struct {
    op: Op,
    result: ?u32 = null,
    lhs: Value = .void,
    rhs: Value = .void,
    /// Direct symbol for `call_direct` / `call_extern`.
    callee: []const u8 = "",
    /// Req alias for `const_req` (e.g. `Token`).
    req_alias: []const u8 = "",
    field: []const u8 = "",
    binop: BinOpTag = .add,
    ty: RT = .any,
    /// Record type name for init/load/store.
    record: []const u8 = "",
    /// Third ABI slot for 3-field record returns.
    third: Value = .void,
    /// Label index for branch ops (resolved by backend).
    branch_target: u32 = 0,
    /// Hardware intrinsic for `hw_unary` / metadata on fence-family ops.
    hw: HwIntrinsic = .none,
};

pub const Block = struct {
    instrs: []const Instr,
};

pub const DenseTable = struct {
    name: []const u8,
    elem_ty: RT,
    values: []const Value,
};

pub const Global = struct {
    name: []const u8,
    ty: RT,
    init: Value,
};

pub const Extern = struct {
    duo_name: []const u8,
    symbol: []const u8,
};

pub const Function = struct {
    name: []const u8,
    ret: RT,
    params: []const RT,
    ret_record: ?[]const u8 = null,
    blocks: []const Block,
};

pub const Module = struct {
    functions: []const Function,
    records: []const RecordDesc = &.{},
    globals: []const Global = &.{},
    dense_tables: []const DenseTable = &.{},
    externs: []const Extern = &.{},
    /// Highest hardware tier exercised — for catalog / capability proofs.
    hardware_tier: HardwareTier = .scalar,
};

pub fn moduleHardwareTier(m: Module) HardwareTier {
    var tier: HardwareTier = .scalar;
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |i| {
                const h: HwIntrinsic = switch (i.op) {
                    .hw_fence => .fence,
                    .hw_spin => .spin_wait,
                    .hw_unary => i.hw,
                    else => .none,
                };
                if (h == .none) continue;
                const t = h.tier();
                if (@intFromEnum(t) > @intFromEnum(tier)) tier = t;
            }
        }
    }
    return tier;
}

pub fn findRecord(m: Module, name: []const u8) ?RecordDesc {
    for (m.records) |r| {
        if (std.mem.eql(u8, r.name, name)) return r;
    }
    return null;
}

/// True when every instruction is in the direct-backend subset.
pub fn moduleIsNativeDirectReady(m: Module) bool {
    if (m.functions.len == 0) return false;
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |i| {
                switch (i.op) {
                    .call_direct, .call_extern, .load_field, .store_field,
                    .init_record, .load_index, .store_index,
                    .binop, .cmp, .ret, .ret_record,
                    .const_i64, .const_f64, .const_str, .const_req,
                    .load_local, .store_local, .load_global,
                    .br, .br_if, .br_if_not,
                    .hw_fence, .hw_spin, .hw_unary,
                    => {},
                }
            }
        }
    }
    return true;
}

test "duo_native_ir: empty module not ready" {
    const m = Module{ .functions = &.{} };
    try std.testing.expect(!moduleIsNativeDirectReady(m));
}

test "duo_native_ir: single ret function ready" {
    const blocks = [_]Block{
        .{ .instrs = &.{.{ .op = .ret, .lhs = .{ .i64 = 0 } }} },
    };
    const f = Function{
        .name = "embed_tokenize",
        .ret = .i64,
        .params = &.{},
        .blocks = &blocks,
    };
    const m = Module{ .functions = &.{f} };
    try std.testing.expect(moduleIsNativeDirectReady(m));
}
