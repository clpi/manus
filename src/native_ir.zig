//! DNIR — migration encoding for the current realization substrate.
//! Graph ids and facts remain authoritative; this layer adds physical facts for
//! realization and machine emission without creating another meaning space.
//!
//! Direct machine code is canonical. Explicit C99 is an orthogonal physical
//! realization of the same graph-observed DNIR; auto, self-host, and release paths
//! never select or fall back to it. DNIR is SSA-ish: native scalars, records, and
//! direct calls consumed by physical realizers without lua_Value.
const std = @import("std");
const semantic_graph = @import("semantic_graph.zig");
const types = @import("types.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const RT = types.ResolvedType;

pub const HwIntrinsic = dnir_hardware.HwIntrinsic;
pub const HardwareTier = dnir_hardware.Tier;

// `LoweringTier` AND `preferredTier` WERE HERE AND ARE DELETED. Measured across
// the whole tree: `preferredTier` had ZERO call sites, `.c_emit` had ZERO reads,
// `dominates` had ZERO callers, and the type name appeared in no file but this
// one. A three-variant policy enum that nothing produces and nothing consumes is
// not a policy — HPLS §7 scenery, §8 "a fact with consumers = 0 is P0
// architecture debt" — and this file's own `dnir_hardware.Tier` comment records
// deleting `.vector`/`.system` for exactly that reason.
//
// The middle variant made it worse than ordinary dead code: `c_emit` ranked an
// unused C policy tier between machine and dynamic. C99 now exists only as an
// explicitly selected orthogonal physical output. Keeping its selection rank in
// DNIR would make this IR own backend policy and invite an unlawful auto fallback.

pub const FieldKind = enum { i64, str, f64 };

pub const RecordDesc = struct {
    /// Exact graph descriptor-shape identity. Null is reserved for hand-built
    /// physical fixtures; production lowering always supplies it.
    semantic_shape: ?semantic_graph.id = null,
    name: []const u8,
    fields: []const []const u8,
    kinds: []const FieldKind,
    /// THE FIELD'S DECLARED WIDTH, which `kinds` DESTROYS.
    ///
    /// `FieldKind` has three members and every integer width answers `.i64`,
    /// so `R: { f: i32 }` and `R: { f: i64 }` were the same record by the time
    /// the store was chosen and `r.f = r.f + 2000000000` never projected —
    /// measured wrong at all six widths, folded AND emitted. That is this
    /// file's own §92 complaint about `BinOpTag` a second time: a three-member
    /// HOST enum deciding how many integers Idol has.
    ///
    /// `kinds` is NOT widened, because its three members are a REALIZATION
    /// question (which register file, which store form) and this is a SEMANTIC
    /// one (what value the place holds). Null means full-width — `i64`, `u64`,
    /// `str`, `f64` — so nothing on the i64 path changes.
    widths: []const ?types.ResolvedType = &.{},
};

pub const BinOpTag = enum {
    add,
    sub,
    mul,
    /// `/` — TRUNCATING integer division on integer operands, real division on
    /// float ones. Distinct from `idiv`; see it for why the distinction is not
    /// optional.
    div,
    /// `//` — FLOOR division (`law.numeric.floor`). It is a SEPARATE tag from
    /// `div` because Idol's `//` and `/` are separate relations with separate
    /// answers, and this enum used to say otherwise: `dnir_lower` mapped
    /// `.div, .idiv => .div`, so a sixteen-member HOST enum decided that Idol
    /// has one integer division. That is HPLS §92 exactly — "host structs/enums
    /// becoming semantic identity" — and it was not a rounding error:
    /// `(0-7) // 10` answered 0 where the law answers -1.
    idiv,
    /// `%` — FLOORED remainder, taking the sign of the DIVISOR
    /// (`law.numeric.floor`). Not `sdiv`+`msub`'s truncated remainder, which is
    /// what the chip happens to compute.
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
    /// Read a written module-scope binding out of its `__DATA,__bss` word.
    /// `.field` names it; `.result` receives it.
    load_global,
    /// Write one. `.field` names it, `.lhs` is the value.
    ///
    /// A file-scope binding is ONE storage location, and until this op existed
    /// the direct backend had none: every function treated the name as its own
    /// register-resident local, so the write landed nowhere the next read could
    /// see and the read folded to the initializer. See `Arm64Compiler.globals`.
    store_global,
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
    /// Return one semantic result pack through the ordinary Idol GP result
    /// convention. `vals` is ordered exactly as the graph/function pack; no
    /// tuple or aggregate is materialized.
    ret_pack,
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

/// One graph-owned application result and its selected physical realization.
/// `temp = null` means demand discarded this member; the ABI position remains
/// its index in the enclosing slice, so later demanded members never shift.
pub const PackResult = struct {
    value: semantic_graph.id,
    temp: ?u32,
    ty: RT,
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
    /// Selected callable entity id for direct realization. Distinct from
    /// relation identity once overload resolution publishes both upstream.
    target: ?semantic_graph.id = null,
    /// Semantic aggregate whose physical base this instruction realizes.
    /// Separate from application `value`: storage lineage is not a call result.
    aggregate: ?semantic_graph.id = null,
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
    /// Ordered result members for a multi-result `call_direct`. Semantic value
    /// identity and descriptor come from the resident graph; `temp` is only the
    /// selected physical destination for this realization.
    pack_results: []const PackResult = &.{},
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
    /// Exact semantic aggregate whose immutable physical realization this is.
    value: semantic_graph.id,
    elem_ty: RT,
    values: []const i64,
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
    /// Ordered internal result convention for a semantic pack. Empty is a
    /// scalar/void function. This is a physical projection of the function's
    /// tuple result descriptor, never an aggregate type.
    ret_pack: []const RT = &.{},
    params: []const Param = &.{},
    ret_record: ?[]const u8 = null,
    /// This relation DECLARED ITSELF a foreign boundary (`@comp.c.export("n")`,
    /// `@c.export`, `@export`, `@ffi`), so the symbol it exports is the name a C
    /// program writes and the convention it answers on is C's, not Idol's.
    ///
    /// It is the SAME declaration that exempts the relation from home mangling
    /// (`dnir_lower.foreignBoundaryName`), and it must be, because the two are
    /// one claim: *this name and this convention are not ours to choose*. Naming
    /// yourself to C and then answering on Idol's internal convention is the
    /// half-boundary that produced the measured defect this field exists to
    /// close — a 24-byte record returned in x0..x2 where AAPCS64 §6.9 says x8.
    ///
    /// FALSE IS THE INTERNAL ABI AND THAT IS DELIBERATE. Idol's own convention
    /// keeps a record of up to `dnir_lower.max_reg_record_fields` in registers,
    /// which is strictly cheaper than C's 16-byte cliff — no buffer, no stores,
    /// no reload. `AGENTS.md` forbids the C ABI from becoming the internal
    /// application ABI, so this is a boundary fact and never a global one.
    foreign_boundary: bool = false,
    /// Pure f64 kernel — params/return use FP registers (M1).
    is_float_kernel: bool = false,
    /// Exact authoritative graph id for the callable declaration.
    id: ?semantic_graph.id = null,
    /// LAWFUL NONEXECUTION — this body IS its compile-time answer.
    ///
    /// The relation was evaluated whole at compile time and its blocks replaced
    /// by the constant, so every application the graph publishes inside it is
    /// realized NOWHERE. That is a KNOWN-ABSENT realization, not a missing one,
    /// and the realization-count checks in `native_backend` need the two told
    /// apart or a folded relation reads as a dropped call (DNB011).
    ///
    /// THE FACT LIVES HERE AND NOT ON THE GRAPH deliberately. Realization is
    /// already a DNIR-carried fact — `Instr.realization_start` is where a
    /// PRESENT realization is published — so its absence belongs in the same
    /// representation rather than split across two stores. It is also a fact
    /// about THIS lowering, not about the source: the graph is shared with
    /// every other backend, and one that does not fold would read a realization
    /// card written by one that does.
    folded_to_constant: bool = false,
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
    if (instruction.pack_results.len > 0) alloc.free(instruction.pack_results);
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
        if (function.ret_pack.len > 0) alloc.free(function.ret_pack);
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
    // `Global.name` is borrowed from the AST identifier, which outlives the
    // compile — exactly as `Instr.field` is. Only the slice is owned.
    if (module.globals.len > 0) alloc.free(module.globals);
    for (module.dense_tables) |table| if (table.values.len > 0) alloc.free(table.values);
    if (module.dense_tables.len > 0) alloc.free(module.dense_tables);
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
        "duo_str_to_f64",
        "duo_str_to_i64",
        "exit",
        "fabs",
        "floor",
        "free",
        "getenv",
        "idol_io_read_line",
        "idol_io_read_path",
        "idol_io_read_stdin",
        "idol_os_arg",
        "idol_os_cwd",
        "idol_os_execute",
        "idol_process_capture",
        "idol_str_at",
        "idol_str_find",
        "idol_str_has",
        "idol_str_match",
        "malloc",
        "memset",
        "printf",
        "setenv",
        "sin",
        "snprintf",
        "sqrt",
        "strcmp",
        "strlen",
        "unsetenv",
    };
    for (bootstrap) |name| {
        if (std.mem.eql(u8, callee, name)) return true;
    }
    return false;
}

fn calleeIsModuleLocal(m: Module, callee: []const u8) bool {
    for (m.functions) |function| {
        if (std.mem.eql(u8, function.name, callee)) return true;
    }
    return false;
}

/// True when every instruction is in the direct-backend subset.
pub fn moduleIsNativeDirectReady(m: Module) bool {
    // NO `if (m.functions.len == 0) return false;` HERE. Readiness is a
    // UNIVERSAL predicate over the module's instructions — "every instruction
    // carries the facts the direct backend needs" — and a module with no
    // instructions satisfies it vacuously. Answering false for the empty module
    // made the base case of the module system the one shape the canonical
    // backend refused, one layer below the same conflation in
    // `dnir_lower.lowerModuleFromGraph`. Both had to go for
    // `lib/compiler/application.id` to build.
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |i| {
                const fact_count: u2 = @as(u2, @intFromBool(i.relation != null)) +
                    @as(u2, @intFromBool(i.application != null)) +
                    @as(u2, @intFromBool(i.value != null));
                if (fact_count != 0 and fact_count != 3) return false;
                if ((fact_count == 3) != (i.realization_start != null)) return false;
                if (i.op == .call_direct) {
                    if (i.application == null) {
                        if (!calleeIsModuleLocal(m, i.callee)) return false;
                        continue;
                    }
                    const graph = m.graph orelse return false;
                    const application = i.application orelse return false;
                    const relation = i.relation orelse return false;
                    const value = i.value orelse return false;
                    if (graph.application(application) == null) return false;
                    if (graph.applicationRelation(application) != relation or
                        graph.applicationSubject(application) != i.subject) return false;
                    const results = graph.applicationResults(application) orelse return false;
                    if (results.len == 0 or results[0] != value) return false;
                    if (results.len == 1) {
                        if (i.pack_results.len != 0) return false;
                    } else {
                        if (i.pack_results.len != results.len or i.result != null or i.record.len != 0) return false;
                        for (i.pack_results, results) |projected, result| {
                            if (projected.value != result) return false;
                            const node = graph.get(result) orelse return false;
                            const descriptor = node.descriptor orelse return false;
                            if (!descriptor.eql(projected.ty)) return false;
                        }
                    }
                }
                if (i.op != .call_direct and i.pack_results.len != 0) return false;
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
                    .ret_pack,
                    .ret_record,
                    .@"const",
                    .store_local,
                    .load_global,
                    .store_global,
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

// RE-RECORDED WITH THE CAPABILITY, NOT AROUND IT. This test asserted
// `!moduleIsNativeDirectReady(empty)` — the refusal that made
// `lib/compiler/application.id` unbuildable. Readiness is a UNIVERSAL predicate
// over instructions, so the empty module satisfies it vacuously and the
// assertion is inverted deliberately. The negative below is what keeps the
// predicate able to FAIL: a module whose instruction carries SOME of the three
// graph facts and not all three is still not ready, which is the property the
// old empty-module row was standing in for and never actually tested.
test "native_ir: empty module is ready — the module system's base case" {
    const m = Module{ .functions = &.{} };
    try std.testing.expect(moduleIsNativeDirectReady(m));
}

test "native_ir: partial graph facts are not ready" {
    const instrs = [_]Instr{.{ .op = .ret, .relation = 1 }};
    const blocks = [_]Block{.{ .instrs = &instrs }};
    const funcs = [_]Function{.{ .name = "f", .ret = .any, .blocks = &blocks }};
    const m = Module{ .functions = &funcs };
    try std.testing.expect(!moduleIsNativeDirectReady(m));
}
test "native_ir: resident graph id stays dense" {
    try std.testing.expectEqual(@sizeOf(u32), @sizeOf(semantic_graph.id));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(?semantic_graph.id));
}

test "native_ir: folded module constant uses one const realization" {
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

test "native_ir: definition projects physical producers" {
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

test "native_ir: definition excludes ABI metadata and nonproducers" {
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
        .{ .op = .ret_pack, .result = 37 },
        .{ .op = .ret_record, .result = 37 },
        .{ .op = .hw_fence, .result = 37 },
        .{ .op = .hw_spin, .result = 37 },
        .{ .op = .print_value, .result = 37 },
    };
    for (instructions) |instruction| {
        try std.testing.expectEqual(@as(?u32, null), definition(instruction));
    }
}

test "native_ir: single ret function ready" {
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

test "native_ir: resident graph empty application census refuses direct call" {
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

test "native_ir: branch condition and operand agree" {
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
