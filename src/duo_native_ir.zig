//! DNIR — migration encoding for the current realization substrate.
//! Graph ids and facts remain authoritative; this layer adds physical facts for
//! realization and machine emission without creating another meaning space.
//!
//! Machine code is the release target. C emission is bootstrap/debug only.
//! DNIR is SSA-ish: native scalars, records, direct calls — consumed by
//! `native_backend.zig` (ARM64 Mach-O) without lua_Value.
const std = @import("std");
const semantic_graph = @import("semantic_graph.zig");
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
    band,
    bor,
    bxor,
    shl,
    shr,
};

pub const BranchCondition = enum {
    unconditional,
    when_true,
    when_false,
};

pub const Op = enum {
    @"const",
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
    /// `print(v)` — observable native output. `.ty` selects the call shape:
    /// `.str` → `puts(v)`; `.i64` → `printf("%lld\n", v)`; `.f64` →
    /// `printf("%f\n", v)`; `.void` lhs → a blank line. `puts`/`printf` are
    /// libc externs (Mach-O `_puts`/`_printf`), so a program's first output
    /// no longer forces the C-emit bootstrap fallback.
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
    /// Exact ids into the resident graph retained through realization.
    relation: ?semantic_graph.id = null,
    application: ?semantic_graph.id = null,
    value: ?semantic_graph.id = null,
    /// Semantic subject selected upstream. Null is an authoritative absence for
    /// applications whose relation has no subject role; it is never inferred
    /// here from argument position or source spelling.
    subject: ?semantic_graph.id = null,
    /// First flattened DNIR instruction whose emitted bytes belong to this
    /// application realization. Present exactly when an application id is.
    realization_start: ?u32 = null,
    result: ?u32 = null,
    lhs: Value = .void,
    rhs: Value = .void,
    /// Direct symbol for `call_direct` / `call_extern`.
    callee: []const u8 = "",
    /// Source module alias retained as provenance for a folded constant.
    req_alias: []const u8 = "",
    field: []const u8 = "",
    binop: BinOpTag = .add,
    ty: RT = .any,
    /// Record type name for init/load/store.
    record: []const u8 = "",
    /// Third ABI slot for 3-field record returns.
    third: Value = .void,
    /// Every field value of a `ret_record`, in DESCRIPTOR order, one entry per
    /// declared field. `lhs`/`rhs`/`third` mirror the first three so an older
    /// consumer reads the same values, but they cannot express a fourth: a
    /// 5-field record return wrote x0..x2 and left the caller reading whatever
    /// x3/x4 happened to hold. Fields beyond the third exist only here.
    vals: []const Value = &.{},
    /// Label index for branch ops (resolved by backend).
    branch_target: u32 = 0,
    /// Physical branch selection. The semantic condition fact remains upstream.
    branch_condition: BranchCondition = .unconditional,
    /// Hardware intrinsic for `hw_unary` / metadata on fence-family ops.
    hw: HwIntrinsic = .none,
};

/// Physical slot established by an instruction in the current DNIR projection.
/// ABI destinations and record metadata use `result` for different roles.
pub fn definition(instruction: Instr) ?u32 {
    return switch (instruction.op) {
        .@"const",
        .store_local,
        .load_field,
        .load_index,
        .alloc_slots,
        .binop,
        .call_direct,
        .call_extern,
        .hw_unary,
        .str_len,
        => instruction.result,
        else => null,
    };
}

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
    /// Exact authoritative graph id for the callable declaration.
    id: ?semantic_graph.id = null,
    blocks: []const Block,
};

pub const Module = struct {
    /// Borrowed physical coordinate domain for resident graph ids.
    /// Null means this projection carries no graph coordinates.
    graph: ?*const semantic_graph.SemanticGraph = null,
    functions: []const Function,
    records: []const RecordDesc = &.{},
    globals: []const Global = &.{},
    dense_tables: []const DenseTable = &.{},
    externs: []const Extern = &.{},
    /// Highest hardware tier exercised — for catalog / capability proofs.
    hardware_tier: HardwareTier = .scalar,
};

/// Release fields interned by DNIR lowering when an instruction is discarded.
pub fn deinitInstr(alloc: std.mem.Allocator, instruction: Instr) void {
    if (instruction.callee.len > 0) alloc.free(instruction.callee);
    if (instruction.req_alias.len > 0) alloc.free(instruction.req_alias);
    if (instruction.field.len > 0) alloc.free(instruction.field);
    if (instruction.record.len > 0) alloc.free(instruction.record);
    if (instruction.vals.len > 0) alloc.free(instruction.vals);
}

/// Release a module produced by DNIR lowering.
pub fn deinitModule(alloc: std.mem.Allocator, module: Module) void {
    for (module.records) |record| {
        alloc.free(record.name);
        for (record.fields) |field| alloc.free(field);
        alloc.free(record.fields);
        alloc.free(record.kinds);
    }
    alloc.free(module.records);
    for (module.functions) |function| {
        alloc.free(function.name);
        for (function.params) |param| {
            alloc.free(param.name);
            if (param.record) |record| alloc.free(record);
        }
        alloc.free(function.params);
        if (function.ret_record) |record| alloc.free(record);
        for (function.blocks) |block| {
            for (block.instrs) |instruction| deinitInstr(alloc, instruction);
            alloc.free(block.instrs);
        }
        alloc.free(function.blocks);
    }
    alloc.free(module.functions);
    for (module.externs) |external| {
        alloc.free(external.duo_name);
        alloc.free(external.symbol);
    }
    alloc.free(module.externs);
}

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

/// Foreign calls emitted by bootstrap lowering without graph application facts
/// (GAP-155). Must stay aligned with `dnir_lower.zig` bootstrap extern paths.
pub fn isBootstrapForeignCall(callee: []const u8) bool {
    const bootstrap = [_][]const u8{
        "abort",
        "ceil",
        "cos",
        "duo_str_sub",
        "exit",
        "fabs",
        "floor",
        "free",
        "idol_io_read_path",
        "idol_io_read_stdin",
        "idol_str_has",
        "idol_str_match",
        "malloc",
        "memset",
        "printf",
        "sin",
        "snprintf",
        "sqrt",
        "strlen",
    };
    for (bootstrap) |name| {
        if (std.mem.eql(u8, callee, name)) return true;
    }
    return false;
}

/// True when every instruction is in the direct-backend subset.
pub fn moduleIsNativeDirectReady(m: Module) bool {
    if (m.functions.len == 0) return false;
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |i| {
                const fact_count: u2 = @as(u2, @intFromBool(i.relation != null)) +
                    @as(u2, @intFromBool(i.application != null)) +
                    @as(u2, @intFromBool(i.value != null));
                if (fact_count != 0 and fact_count != 3) return false;
                if ((fact_count == 3) != (i.realization_start != null)) return false;
                if (i.op == .call_direct) {
                    if (i.application == null) continue;
                    const graph = m.graph orelse return false;
                    const application = i.application orelse return false;
                    const relation = i.relation orelse return false;
                    const value = i.value orelse return false;
                    const fact = graph.application(application) orelse return false;
                    if (fact.relation != relation or fact.subject != i.subject) return false;
                    const results = graph.applicationResults(application) orelse return false;
                    if (results.len != 1 or results[0] != value) return false;
                }
                if (i.op == .call_extern and i.application == null and !isBootstrapForeignCall(i.callee)) {
                    return false;
                }
                if (i.op == .br) {
                    switch (i.branch_condition) {
                        .unconditional => if (i.lhs != .void) return false,
                        .when_true, .when_false => if (i.lhs == .void) return false,
                    }
                } else if (i.branch_condition != .unconditional) {
                    return false;
                }
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
                    .@"const",
                    .store_local,
                    .load_global,
                    .mov_arg,
                    .fp_mov_arg,
                    .br,
                    .hw_fence,
                    .hw_spin,
                    .hw_unary,
                    .str_len,
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

test "duo_native_ir: resident graph id stays dense" {
    try std.testing.expectEqual(@sizeOf(u32), @sizeOf(semantic_graph.id));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(?semantic_graph.id));
}

test "duo_native_ir: folded module constant uses one const realization" {
    const instruction = Instr{
        .op = .@"const",
        .result = 0,
        .lhs = .{ .i64 = 14 },
        .req_alias = "token",
        .field = "kindfun",
        .ty = .i64,
    };
    try std.testing.expectEqual(Op.@"const", instruction.op);
    try std.testing.expectEqualStrings("token", instruction.req_alias);
    try std.testing.expectEqualStrings("kindfun", instruction.field);
    try std.testing.expectEqual(RT.i64, instruction.ty);
}

test "duo_native_ir: definition projects physical producers" {
    const instructions = [_]Instr{
        .{ .op = .@"const", .result = 37 },
        .{ .op = .store_local, .result = 37 },
        .{ .op = .load_field, .result = 37 },
        .{ .op = .load_index, .result = 37 },
        .{ .op = .alloc_slots, .result = 37 },
        .{ .op = .binop, .result = 37 },
        .{ .op = .call_direct, .result = 37 },
        .{ .op = .call_extern, .result = 37 },
        .{ .op = .hw_unary, .result = 37 },
        .{ .op = .str_len, .result = 37 },
    };
    for (instructions) |instruction| {
        try std.testing.expectEqual(@as(?u32, 37), definition(instruction));
    }
    try std.testing.expectEqual(@as(?u32, null), definition(.{ .op = .binop }));
}

test "duo_native_ir: definition excludes ABI metadata and nonproducers" {
    const instructions = [_]Instr{
        .{ .op = .store_field, .result = 37 },
        .{ .op = .init_record, .result = 37 },
        .{ .op = .store_index, .result = 37 },
        .{ .op = .load_global, .result = 37 },
        .{ .op = .cmp, .result = 37 },
        .{ .op = .mov_arg, .result = 37 },
        .{ .op = .fp_mov_arg, .result = 37 },
        .{ .op = .br, .result = 37 },
        .{ .op = .ret, .result = 37 },
        .{ .op = .ret_record, .result = 37 },
        .{ .op = .hw_fence, .result = 37 },
        .{ .op = .hw_spin, .result = 37 },
        .{ .op = .print_value, .result = 37 },
    };
    for (instructions) |instruction| {
        try std.testing.expectEqual(@as(?u32, null), definition(instruction));
    }
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

test "duo_native_ir: resident graph empty application census refuses direct call" {
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const blocks = [_]Block{
        .{ .instrs = &.{
            .{ .op = .call_direct, .callee = "callee" },
            .{ .op = .ret, .lhs = .{ .i64 = 0 } },
        } },
    };
    const function = Function{
        .name = "caller",
        .ret = .i64,
        .blocks = &blocks,
    };

    try std.testing.expect(!moduleIsNativeDirectReady(.{ .functions = &.{function} }));
    try std.testing.expect(!moduleIsNativeDirectReady(.{
        .graph = &graph,
        .functions = &.{function},
    }));
}

test "duo_native_ir: branch condition and operand agree" {
    const bad_unconditional = [_]Block{
        .{ .instrs = &.{.{ .op = .br, .lhs = .{ .i64 = 1 } }} },
    };
    const bad_conditional = [_]Block{
        .{ .instrs = &.{.{ .op = .br, .branch_condition = .when_false }} },
    };
    const good_conditional = [_]Block{
        .{ .instrs = &.{.{ .op = .br, .lhs = .{ .i64 = 1 }, .branch_condition = .when_false }} },
    };
    try std.testing.expect(!moduleIsNativeDirectReady(.{ .functions = &.{.{ .name = "bad", .ret = .void, .blocks = &bad_unconditional }} }));
    try std.testing.expect(!moduleIsNativeDirectReady(.{ .functions = &.{.{ .name = "bad", .ret = .void, .blocks = &bad_conditional }} }));
    try std.testing.expect(moduleIsNativeDirectReady(.{ .functions = &.{.{ .name = "good", .ret = .void, .blocks = &good_conditional }} }));
}
