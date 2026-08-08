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

pub const FieldKind = enum { i64, str, f64 };

pub const RecordDesc = struct {
    name: []const u8,
    fields: []const []const u8,
    kinds: []const FieldKind,
    /// Semantic graph shape identity when lowered via `lowerModuleWithGraph`.
    shape_id: ?u64 = null,
    /// Semantic graph `StableId` hash for the table_shape node.
    graph_stable_id: ?u64 = null,
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
    /// Indexed element access. `ty == .i64` selects 8-byte word semantics over a
    /// memory-backed positional table (see `alloc_slots`); any other `ty` keeps
    /// the original byte semantics used by `string.byte`.
    load_index,
    store_index,
    /// Reserve `lhs` i64 slots in the current frame and put their base address in
    /// `result`. This is the memory representation a positional table needs in
    /// order to cross a function boundary: without it a table is exploded into
    /// one local per element, so there is no contiguous storage and no pointer to
    /// pass (the SH-04 blocker in `selfhosting_matrix.zig`).
    alloc_slots,
    load_global,
    binop,
    cmp,
    call_direct,
    call_extern,
    /// Move an i64 value into x{result} before `call_direct`.
    mov_arg,
    /// Move an f64 value into d{result} before `call_direct` (.ty = .f64).
    fp_mov_arg,
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
    /// `string.len(s)` — byte length of a `const char*`, emitted as an inline
    /// scan loop. Sovereign by construction: no libc `strlen`, no C helper, no
    /// runtime call, so a tokenizer built on `string.len` stays inside the
    /// direct backend subset.
    str_len,
    /// Native observable output. `native_backend.zig` already carries the full
    /// lowering for this tag (`.str` → puts, numeric → printf), but the tag
    /// itself was never declared here, so the branch tip did not compile:
    ///
    ///     native_backend.zig:1539: enum 'duo_native_ir.Op' has no member
    ///                              named 'print_value'
    ///
    /// Declared here to restore buildability — see gap[037]. Nothing emits it
    /// yet, so this is inert until a lowering site in `dnir_lower.zig` produces
    /// it; the handler is what gives the tag its meaning.
    print_value,
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

pub const Param = struct {
    name: []const u8,
    ty: RT,
    /// Named record type when `ty` is a sealed record parameter.
    record: ?[]const u8 = null,
};

pub const Function = struct {
    name: []const u8,
    ret: RT,
    params: []const Param = &.{},
    ret_record: ?[]const u8 = null,
    /// Pure f64 kernel — params/return use FP registers (Pass 4 M1).
    is_float_kernel: bool = false,
    /// Semantic graph `StableId` hash when lowered via `lowerModuleWithGraph`.
    graph_stable_id: ?u64 = null,
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
                    .call_direct,
                    .call_extern,
                    .load_field,
                    .store_field,
                    .init_record,
                    .load_index,
                    .store_index,
                    .alloc_slots,
                    .binop,
                    .cmp,
                    .ret,
                    .ret_record,
                    .const_i64,
                    .const_f64,
                    .const_str,
                    .const_req,
                    .load_local,
                    .store_local,
                    .load_global,
                    .mov_arg,
                    .fp_mov_arg,
                    .br,
                    .br_if,
                    .br_if_not,
                    .hw_fence,
                    .hw_spin,
                    .hw_unary,
                    .str_len,
                    // In the direct subset by the backend's own account: the
                    // `.print_value` handler lowers to Mach-O `_puts`/`_printf`
                    // externs precisely so "a program whose only dynamic
                    // surface is output stays sovereign machine code". Treating
                    // it as native-direct-ready is what that comment asserts.
                    .print_value,
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
        .blocks = &blocks,
    };
    const m = Module{ .functions = &.{f} };
    try std.testing.expect(moduleIsNativeDirectReady(m));
}
