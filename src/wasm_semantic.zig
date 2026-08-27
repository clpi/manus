//! — canonical Wasm instruction semantic descriptors (P9-04).
//!
//! Single source of truth for opcode facts, stack effects, immediates, and
//! provenance hooks. Decoder/validator tables are generated from this module
//! in P9-05; Ward must not maintain parallel opcode constants long-term.
const std = @import("std");

pub const SCHEMA_VERSION = "wasm-instruction-v0";
pub const MVP_FEATURE = "wasm1.0-mvp";
pub const PROVENANCE = "src/wasm_semantic.zig";

pub const ValueKind = enum(u8) {
    i32,
    i64,
    f32,
    f64,
    v128,
    funcref,
    externref,
    empty,
    /// Polymorphic / block-type dependent (control instructions).
    any,

    pub fn name(self: ValueKind) []const u8 {
        return @tagName(self);
    }
};

pub const ImmediateForm = enum(u8) {
    none,
    block_type,
    label_idx,
    br_table,
    func_idx,
    call_indirect,
    local_idx,
    global_idx,
    i32_imm,
    i64_imm,
    f32_imm,
    f64_imm,
    mem_arg,

    pub fn name(self: ImmediateForm) []const u8 {
        return @tagName(self);
    }
};

pub const Instruction = struct {
    /// Stable semantic id, e.g. `wasm.i32.add`.
    id: []const u8,
    mnemonic: []const u8,
    opcode: u8,
    prefix: ?u8 = null,
    stack_in: []const ValueKind,
    stack_out: []const ValueKind,
    immediate: ImmediateForm,
    feature: []const u8 = MVP_FEATURE,
    control_flow: bool = false,
    may_trap: bool = false,
    /// Interpreter dispatch target (Ward handler registry key).
    handler: []const u8,
    /// Compiler lowering target (native backend / JIT key).
    lowering: []const u8,

    pub fn entityId(self: Instruction) []const u8 {
        return self.id;
    }
};

fn ins(
    comptime id: []const u8,
    comptime mnemonic: []const u8,
    opcode: u8,
    stack_in: []const ValueKind,
    stack_out: []const ValueKind,
    immediate: ImmediateForm,
    handler: []const u8,
    lowering: []const u8,
) Instruction {
    return .{
        .id = id,
        .mnemonic = mnemonic,
        .opcode = opcode,
        .stack_in = stack_in,
        .stack_out = stack_out,
        .immediate = immediate,
        .handler = handler,
        .lowering = lowering,
    };
}

fn ins_ctrl(
    comptime id: []const u8,
    comptime mnemonic: []const u8,
    opcode: u8,
    immediate: ImmediateForm,
    handler: []const u8,
    lowering: []const u8,
) Instruction {
    return .{
        .id = id,
        .mnemonic = mnemonic,
        .opcode = opcode,
        .stack_in = &.{},
        .stack_out = &.{},
        .immediate = immediate,
        .control_flow = true,
        .handler = handler,
        .lowering = lowering,
    };
}

fn ins_trap(
    comptime id: []const u8,
    comptime mnemonic: []const u8,
    opcode: u8,
    stack_in: []const ValueKind,
    stack_out: []const ValueKind,
    immediate: ImmediateForm,
    handler: []const u8,
    lowering: []const u8,
) Instruction {
    var base = ins(id, mnemonic, opcode, stack_in, stack_out, immediate, handler, lowering);
    base.may_trap = true;
    return base;
}

/// Bounded MVP subset for P9-M1 kernel (control + locals + memory + core numerics).
pub const mvp_instructions: []const Instruction = &.{
    // Control
    ins_trap("wasm.unreachable", "unreachable", 0x00, &.{}, &.{}, .none, "interp.unreachable", "lower.trap"),
    ins("wasm.nop", "nop", 0x01, &.{}, &.{}, .none, "interp.nop", "lower.nop"),
    ins_ctrl("wasm.block", "block", 0x02, .block_type, "interp.block", "lower.block"),
    ins_ctrl("wasm.loop", "loop", 0x03, .block_type, "interp.loop", "lower.loop"),
    ins_ctrl("wasm.if", "if", 0x04, .block_type, "interp.if", "lower.if"),
    ins_ctrl("wasm.else", "else", 0x05, .none, "interp.else", "lower.else"),
    ins_ctrl("wasm.end", "end", 0x0B, .none, "interp.end", "lower.end"),
    ins_ctrl("wasm.br", "br", 0x0C, .label_idx, "interp.br", "lower.br"),
    ins_ctrl("wasm.br_if", "br_if", 0x0D, .label_idx, "interp.br_if", "lower.br_if"),
    ins_ctrl("wasm.br_table", "br_table", 0x0E, .br_table, "interp.br_table", "lower.br_table"),
    ins_ctrl("wasm.return", "return", 0x0F, .none, "interp.return", "lower.return"),
    ins("wasm.call", "call", 0x10, &.{}, &.{}, .func_idx, "interp.call", "lower.call"),
    ins_trap("wasm.call_indirect", "call_indirect", 0x11, &.{}, &.{}, .call_indirect, "interp.call_indirect", "lower.call_indirect"),
    ins_ctrl("wasm.return_call", "return_call", 0x12, .func_idx, "interp.return_call", "lower.return_call"),
    // Parametric
    ins("wasm.drop", "drop", 0x1A, &.{.any}, &.{}, .none, "interp.drop", "lower.drop"),
    ins("wasm.select", "select", 0x1B, &.{ .i32, .any, .any }, &.{.any}, .none, "interp.select", "lower.select"),
    // Locals / globals
    ins("wasm.local.get", "local.get", 0x20, &.{}, &.{.any}, .local_idx, "interp.local_get", "lower.local_get"),
    ins("wasm.local.set", "local.set", 0x21, &.{.any}, &.{}, .local_idx, "interp.local_set", "lower.local_set"),
    ins("wasm.local.tee", "local.tee", 0x22, &.{.any}, &.{.any}, .local_idx, "interp.local_tee", "lower.local_tee"),
    ins("wasm.global.get", "global.get", 0x23, &.{}, &.{.any}, .global_idx, "interp.global_get", "lower.global_get"),
    ins("wasm.global.set", "global.set", 0x24, &.{.any}, &.{}, .global_idx, "interp.global_set", "lower.global_set"),
    // Memory
    ins_trap("wasm.i32.load", "i32.load", 0x28, &.{.i32}, &.{.i32}, .mem_arg, "interp.i32.load", "lower.i32.load"),
    ins_trap("wasm.i64.load", "i64.load", 0x29, &.{.i32}, &.{.i64}, .mem_arg, "interp.i64.load", "lower.i64.load"),
    ins_trap("wasm.f32.load", "f32.load", 0x2A, &.{.i32}, &.{.f32}, .mem_arg, "interp.f32.load", "lower.f32.load"),
    ins_trap("wasm.f64.load", "f64.load", 0x2B, &.{.i32}, &.{.f64}, .mem_arg, "interp.f64.load", "lower.f64.load"),
    ins_trap("wasm.i32.store", "i32.store", 0x36, &.{ .i32, .i32 }, &.{}, .mem_arg, "interp.i32.store", "lower.i32.store"),
    ins_trap("wasm.i64.store", "i64.store", 0x37, &.{ .i32, .i64 }, &.{}, .mem_arg, "interp.i64.store", "lower.i64.store"),
    ins_trap("wasm.f32.store", "f32.store", 0x38, &.{ .i32, .f32 }, &.{}, .mem_arg, "interp.f32.store", "lower.f32.store"),
    ins_trap("wasm.f64.store", "f64.store", 0x39, &.{ .i32, .f64 }, &.{}, .mem_arg, "interp.f64.store", "lower.f64.store"),
    ins("wasm.memory.size", "memory.size", 0x3F, &.{}, &.{.i32}, .none, "interp.memory.size", "lower.memory.size"),
    ins_trap("wasm.memory.grow", "memory.grow", 0x40, &.{.i32}, &.{.i32}, .none, "interp.memory.grow", "lower.memory.grow"),
    // Constants
    ins("wasm.i32.const", "i32.const", 0x41, &.{}, &.{.i32}, .i32_imm, "interp.i32.const", "lower.i32.const"),
    ins("wasm.i64.const", "i64.const", 0x42, &.{}, &.{.i64}, .i64_imm, "interp.i64.const", "lower.i64.const"),
    ins("wasm.f32.const", "f32.const", 0x43, &.{}, &.{.f32}, .f32_imm, "interp.f32.const", "lower.f32.const"),
    ins("wasm.f64.const", "f64.const", 0x44, &.{}, &.{.f64}, .f64_imm, "interp.f64.const", "lower.f64.const"),
    // i32 compare + arithmetic (representative numerics)
    ins("wasm.i32.eqz", "i32.eqz", 0x45, &.{.i32}, &.{.i32}, .none, "interp.i32.eqz", "lower.i32.eqz"),
    ins("wasm.i32.eq", "i32.eq", 0x46, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.eq", "lower.i32.eq"),
    ins("wasm.i32.ne", "i32.ne", 0x47, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.ne", "lower.i32.ne"),
    ins("wasm.i32.lt_s", "i32.lt_s", 0x48, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.lt_s", "lower.i32.lt_s"),
    ins("wasm.i32.lt_u", "i32.lt_u", 0x49, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.lt_u", "lower.i32.lt_u"),
    ins("wasm.i32.gt_s", "i32.gt_s", 0x4A, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.gt_s", "lower.i32.gt_s"),
    ins("wasm.i32.gt_u", "i32.gt_u", 0x4B, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.gt_u", "lower.i32.gt_u"),
    ins("wasm.i32.le_s", "i32.le_s", 0x4C, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.le_s", "lower.i32.le_s"),
    ins("wasm.i32.le_u", "i32.le_u", 0x4D, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.le_u", "lower.i32.le_u"),
    ins("wasm.i32.ge_s", "i32.ge_s", 0x4E, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.ge_s", "lower.i32.ge_s"),
    ins("wasm.i32.ge_u", "i32.ge_u", 0x4F, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.ge_u", "lower.i32.ge_u"),
    ins("wasm.i32.add", "i32.add", 0x6A, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.add", "lower.i32.add"),
    ins("wasm.i32.sub", "i32.sub", 0x6B, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.sub", "lower.i32.sub"),
    ins("wasm.i32.mul", "i32.mul", 0x6C, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.mul", "lower.i32.mul"),
    ins_trap("wasm.i32.div_s", "i32.div_s", 0x6D, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.div_s", "lower.i32.div_s"),
    ins_trap("wasm.i32.div_u", "i32.div_u", 0x6E, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.div_u", "lower.i32.div_u"),
    ins_trap("wasm.i32.rem_s", "i32.rem_s", 0x6F, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.rem_s", "lower.i32.rem_s"),
    ins_trap("wasm.i32.rem_u", "i32.rem_u", 0x70, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.rem_u", "lower.i32.rem_u"),
    ins("wasm.i32.and", "i32.and", 0x71, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.and", "lower.i32.and"),
    ins("wasm.i32.or", "i32.or", 0x72, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.or", "lower.i32.or"),
    ins("wasm.i32.xor", "i32.xor", 0x73, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.xor", "lower.i32.xor"),
    ins("wasm.i32.shl", "i32.shl", 0x74, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.shl", "lower.i32.shl"),
    ins("wasm.i32.shr_s", "i32.shr_s", 0x75, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.shr_s", "lower.i32.shr_s"),
    ins("wasm.i32.shr_u", "i32.shr_u", 0x76, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.shr_u", "lower.i32.shr_u"),
    ins("wasm.i32.rotl", "i32.rotl", 0x77, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.rotl", "lower.i32.rotl"),
    ins("wasm.i32.rotr", "i32.rotr", 0x78, &.{ .i32, .i32 }, &.{.i32}, .none, "interp.i32.rotr", "lower.i32.rotr"),
    // i64 representative
    ins("wasm.i64.add", "i64.add", 0x7C, &.{ .i64, .i64 }, &.{.i64}, .none, "interp.i64.add", "lower.i64.add"),
    // f32 representative
    ins("wasm.f32.add", "f32.add", 0x92, &.{ .f32, .f32 }, &.{.f32}, .none, "interp.f32.add", "lower.f32.add"),
    // f64 representative
    ins("wasm.f64.add", "f64.add", 0xA0, &.{ .f64, .f64 }, &.{.f64}, .none, "interp.f64.add", "lower.f64.add"),
};

pub fn findByOpcode(opcode: u8) ?*const Instruction {
    for (mvp_instructions) |*inst| {
        if (inst.prefix == null and inst.opcode == opcode) return inst;
    }
    return null;
}

pub fn findById(id: []const u8) ?*const Instruction {
    for (mvp_instructions) |*inst| {
        if (std.mem.eql(u8, inst.id, id)) return inst;
    }
    return null;
}

pub fn mvpCount() usize {
    return mvp_instructions.len;
}

/// Comptime-generated 256-entry opcode → instruction index (-1 = unknown MVP opcode).
pub const mvp_opcode_index: [256]i16 = buildOpcodeIndexTable();

fn buildOpcodeIndexTable() [256]i16 {
    var table: [256]i16 = undefined; @memset(&table, -1);
    for (mvp_instructions, 0..) |inst, idx| {
        if (inst.prefix == null) {
            table[inst.opcode] = @intCast(idx);
        }
    }
    return table;
}

pub const DecodeStatus = enum {
    ok,
    unknown_opcode,
};

pub const DecodeResult = struct {
    status: DecodeStatus,
    instruction_index: i16 = -1,
    instruction: ?*const Instruction = null,
};

/// Resolve a single-byte MVP opcode via the generated lookup table (P9-WS5).
pub fn decodeOpcode(opcode: u8) DecodeResult {
    const idx = mvp_opcode_index[opcode];
    if (idx < 0) return .{ .status = .unknown_opcode };
    const inst = &mvp_instructions[@intCast(idx)];
    return .{
        .status = .ok,
        .instruction_index = idx,
        .instruction = inst,
    };
}

pub fn knownOpcodeCount() usize {
    var n: usize = 0;
    for (mvp_opcode_index) |idx| {
        if (idx >= 0) n += 1;
    }
    return n;
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

fn writeValueKinds(w: *std.Io.Writer, kinds: []const ValueKind) !void {
    try w.print("[", .{});
    for (kinds, 0..) |k, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{k.name()});
    }
    try w.print("]", .{});
}

pub fn writeInstructionJson(inst: *const Instruction, w: *std.Io.Writer) !void {
    try w.print("{{\"id\":\"", .{});
    try jsonEscape(w, inst.id);
    try w.print("\",\"mnemonic\":\"", .{});
    try jsonEscape(w, inst.mnemonic);
    try w.print("\",\"opcode\":{d}", .{inst.opcode});
    if (inst.prefix) |p| try w.print(",\"prefix\":{d}", .{p});
    try w.print(",\"stack_in\":", .{});
    try writeValueKinds(w, inst.stack_in);
    try w.print(",\"stack_out\":", .{});
    try writeValueKinds(w, inst.stack_out);
    try w.print(",\"immediate\":\"{s}\",\"feature\":\"", .{inst.immediate.name()});
    try jsonEscape(w, inst.feature);
    try w.print("\",\"control_flow\":", .{});
    try w.print("{s}", .{if (inst.control_flow) "true" else "false"});
    try w.print(",\"may_trap\":", .{});
    try w.print("{s}", .{if (inst.may_trap) "true" else "false"});
    try w.print(",\"handler\":\"", .{});
    try jsonEscape(w, inst.handler);
    try w.print("\",\"lowering\":\"", .{});
    try jsonEscape(w, inst.lowering);
    try w.print("\"}}", .{});
}

pub fn writeDecoderTableJson(w: *std.Io.Writer) !void {
    try w.print("{{\"table_size\":256,\"known_opcodes\":{d},\"entries\":[", .{knownOpcodeCount()});
    var first = true;
    for (mvp_opcode_index, 0..) |idx, opcode| {
        if (idx < 0) continue;
        if (!first) try w.print(",", .{});
        first = false;
        const inst = &mvp_instructions[@intCast(idx)];
        try w.print("{{\"opcode\":{d},\"index\":{d},\"id\":\"", .{ opcode, idx });
        try jsonEscape(w, inst.id);
        try w.print("\",\"handler\":\"", .{});
        try jsonEscape(w, inst.handler);
        try w.print("\",\"immediate\":\"{s}\",\"may_trap\":", .{inst.immediate.name()});
        try w.print("{s}}}", .{if (inst.may_trap) "true" else "false"});
    }
    try w.print("]}}", .{});
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"provenance\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, PROVENANCE);
    try w.print("\",\"feature\":\"", .{});
    try jsonEscape(w, MVP_FEATURE);
    try w.print("\",\"instruction_count\":{d},\"instructions\":[", .{mvp_instructions.len});
    for (mvp_instructions, 0..) |*inst, i| {
        if (i > 0) try w.print(",", .{});
        try writeInstructionJson(inst, w);
    }
    try w.print("],\"decoder_table\":", .{});
    try writeDecoderTableJson(w);
    try w.print("}}", .{});
}

test "wasm_semantic: opcodes unique in MVP set" {
    for (mvp_instructions, 0..) |a, i| {
        for (mvp_instructions[i + 1 ..]) |b| {
            if (a.prefix == null and b.prefix == null) {
                try std.testing.expect(a.opcode != b.opcode);
            }
        }
    }
}

test "wasm_semantic: i32.add stack effect" {
    const inst = findByOpcode(0x6A) orelse return error.MissingInstruction;
    try std.testing.expectEqualStrings("wasm.i32.add", inst.id);
    try std.testing.expect(inst.stack_in.len == 2);
    try std.testing.expect(inst.stack_out.len == 1);
    try std.testing.expect(inst.stack_out[0] == .i32);
}

test "wasm_semantic: unreachable traps" {
    const inst = findByOpcode(0x00) orelse return error.MissingInstruction;
    try std.testing.expect(inst.may_trap);
}

test "wasm_semantic: return_call is present with func_idx immediate" {
    const inst = findByOpcode(0x12) orelse return error.MissingInstruction;
    try std.testing.expectEqualStrings("wasm.return_call", inst.id);
    try std.testing.expect(inst.control_flow);
    try std.testing.expect(inst.immediate == .func_idx);
    try std.testing.expectEqualStrings("interp.return_call", inst.handler);
}

test "wasm_semantic: JSON export non-empty" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCatalogJson(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "wasm.i32.add") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "\"decoder_table\"") != null);
}

test "wasm_semantic: decoder table resolves i32.add" {
    const decoded = decodeOpcode(0x6A);
    try std.testing.expect(decoded.status == .ok);
    try std.testing.expect(decoded.instruction != null);
    try std.testing.expectEqualStrings("wasm.i32.add", decoded.instruction.?.id);
    try std.testing.expectEqual(@as(usize, mvpCount()), knownOpcodeCount());
}

test "wasm_semantic: unknown opcode returns unknown" {
    const decoded = decodeOpcode(0xFF);
    try std.testing.expect(decoded.status == .unknown_opcode);
    try std.testing.expect(decoded.instruction == null);
}
