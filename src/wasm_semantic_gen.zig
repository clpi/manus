//! Pass 9 — compile-time generator artifacts from `wasm_semantic.zig` (P9-WS5).
//!
//! Produces decoder-adjacent validator metadata and immediate-reader dispatch
//! tables. Canonical opcode facts remain in wasm_semantic only.
const std = @import("std");
const wasm_semantic = @import("wasm_semantic.zig");

pub const SCHEMA_VERSION = "wasm-semantic-gen-v0";
pub const PROVENANCE = "src/wasm_semantic_gen.zig";

pub const POLY_STACK = 255;

pub const StackMeta = struct {
    pop: u8,
    push: u8,
    polymorphic: bool,

    pub fn fromInstruction(inst: wasm_semantic.Instruction) StackMeta {
        if (inst.control_flow and inst.stack_in.len == 0 and inst.stack_out.len == 0) {
            return .{ .pop = POLY_STACK, .push = POLY_STACK, .polymorphic = true };
        }
        var poly = false;
        for (inst.stack_in) |k| {
            if (k == .any) poly = true;
        }
        for (inst.stack_out) |k| {
            if (k == .any) poly = true;
        }
        if (inst.immediate == .func_idx or inst.immediate == .call_indirect) {
            poly = true;
        }
        return .{
            .pop = if (poly and inst.stack_in.len == 0) POLY_STACK else @intCast(inst.stack_in.len),
            .push = if (poly and inst.stack_out.len == 0) POLY_STACK else @intCast(inst.stack_out.len),
            .polymorphic = poly,
        };
    }
};

pub const ValidatorEntry = struct {
    instruction_index: u16,
    id: []const u8,
    stack: StackMeta,
    immediate: wasm_semantic.ImmediateForm,
    may_trap: bool,
    handler: []const u8,
};

pub const mvp_validator: [wasm_semantic.mvp_instructions.len]ValidatorEntry = buildValidatorTable();

fn buildValidatorTable() [wasm_semantic.mvp_instructions.len]ValidatorEntry {
    var out: [wasm_semantic.mvp_instructions.len]ValidatorEntry = undefined;
    for (wasm_semantic.mvp_instructions, 0..) |inst, i| {
        out[i] = .{
            .instruction_index = @intCast(i),
            .id = inst.id,
            .stack = StackMeta.fromInstruction(inst),
            .immediate = inst.immediate,
            .may_trap = inst.may_trap,
            .handler = inst.handler,
        };
    }
    return out;
}

/// Per-instruction-index immediate reader dispatch (mirrors ImmediateForm).
pub const mvp_immediate_form: [wasm_semantic.mvp_instructions.len]wasm_semantic.ImmediateForm = buildImmediateFormTable();

fn buildImmediateFormTable() [wasm_semantic.mvp_instructions.len]wasm_semantic.ImmediateForm {
    var out: [wasm_semantic.mvp_instructions.len]wasm_semantic.ImmediateForm = undefined;
    for (wasm_semantic.mvp_instructions, 0..) |inst, i| {
        out[i] = inst.immediate;
    }
    return out;
}

pub fn validatorForIndex(index: usize) ?*const ValidatorEntry {
    if (index >= mvp_validator.len) return null;
    return &mvp_validator[index];
}

pub fn validatorForOpcode(opcode: u8) ?*const ValidatorEntry {
    const decoded = wasm_semantic.decodeOpcode(opcode);
    if (decoded.instruction_index < 0) return null;
    return validatorForIndex(@intCast(decoded.instruction_index));
}

pub fn immediateFormForOpcode(opcode: u8) ?wasm_semantic.ImmediateForm {
    const decoded = wasm_semantic.decodeOpcode(opcode);
    if (decoded.instruction_index < 0) return null;
    return mvp_immediate_form[@intCast(decoded.instruction_index)];
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeValidatorTableJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"entry_count\":{d},\"entries\":[", .{
        SCHEMA_VERSION, mvp_validator.len,
    });
    for (mvp_validator, 0..) |entry, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"index\":{d},\"id\":\"", .{entry.instruction_index});
        try jsonEscape(w, entry.id);
        try w.print("\",\"stack_pop\":{d},\"stack_push\":{d},\"polymorphic\":", .{
            entry.stack.pop, entry.stack.push,
        });
        try w.print("{s}", .{if (entry.stack.polymorphic) "true" else "false"});
        try w.print(",\"immediate\":\"{s}\",\"may_trap\":", .{entry.immediate.name()});
        try w.print("{s},\"handler\":\"", .{if (entry.may_trap) "true" else "false"});
        try jsonEscape(w, entry.handler);
        try w.print("\"}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeImmediateDispatchJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"entry_count\":{d},\"forms\":[", .{
        SCHEMA_VERSION, mvp_immediate_form.len,
    });
    for (mvp_immediate_form, 0..) |form, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"index\":{d},\"form\":\"{s}\"}}", .{ i, form.name() });
    }
    try w.print("]}}", .{});
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"provenance\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, PROVENANCE);
    try w.print("\",\"validator_table\":", .{});
    try writeValidatorTableJson(w);
    try w.print(",\"immediate_dispatch\":", .{});
    try writeImmediateDispatchJson(w);
    try w.print("}}", .{});
}

/// Emit `lib/std/wasm/opcode_lookup.id` — generated opcode → semantic id dispatch (P9-M1).
pub fn emitDuoOpcodeLookup(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\-- GENERATED from src/wasm_semantic_gen.zig — do not edit by hand.
        \\-- Regenerate: duo wasm-tables emit
        \\-- Canonical opcode facts: src/wasm_semantic.zig
        \\
        \\GENERATOR_OWNER = "src/wasm_semantic_gen.zig"
        \\INSTRUCTION_COUNT = 
    );
    try w.print("{d}\n\n", .{wasm_semantic.mvpCount()});
    try w.writeAll("INSTRUCTION_IDS = {\n");
    for (wasm_semantic.mvp_instructions) |inst| {
        try w.print("    \"{s}\",\n", .{inst.id});
    }
    try w.writeAll("}\n\nIMMEDIATE_FORMS = {\n");
    for (mvp_immediate_form) |form| {
        try w.print("    \"{s}\",\n", .{form.name()});
    }
    try w.writeAll("}\n\nSTACK_POP = {\n");
    for (mvp_validator) |entry| {
        try w.print("    {d},\n", .{entry.stack.pop});
    }
    try w.writeAll("}\n\nSTACK_PUSH = {\n");
    for (mvp_validator) |entry| {
        try w.print("    {d},\n", .{entry.stack.push});
    }
    try w.writeAll("}\n\nINSTRUCTION_OPCODES = {\n");
    for (wasm_semantic.mvp_instructions) |inst| {
        try w.print("    {d},\n", .{inst.opcode});
    }
    try w.writeAll("}\n\nOPCODE_TO_INDEX = {\n");
    for (wasm_semantic.mvp_opcode_index) |idx| {
        try w.print("    {d},\n", .{idx});
    }
    try w.writeAll(
        \\}
        \\
        \\opcode_for_index(idx: i64): i64
        \\    if idx < 0 or idx >= INSTRUCTION_COUNT return -1 end
        \\    INSTRUCTION_OPCODES[idx + 1]
        \\end
        \\
        \\generator_owner(): str
        \\    GENERATOR_OWNER
        \\end
        \\
        \\instruction_count(): i64
        \\    INSTRUCTION_COUNT
        \\end
        \\
        \\instruction_index_for_opcode(op: i64): i64
        \\    if op < 0 or op > 255 return -1 end
        \\    idx = OPCODE_TO_INDEX[op + 1]
        \\    if idx < 0 return -1 end
        \\    idx
        \\end
        \\
        \\semantic_id_for_index(idx: i64): str
        \\    if idx < 0 or idx >= INSTRUCTION_COUNT return "" end
        \\    INSTRUCTION_IDS[idx + 1]
        \\end
        \\
        \\semantic_id_for_opcode(op: i64): str
        \\    idx = instruction_index_for_opcode(op)
        \\    if idx < 0 return "" end
        \\    INSTRUCTION_IDS[idx + 1]
        \\end
        \\
        \\immediate_form_for_index(idx: i64): str
        \\    if idx < 0 or idx >= INSTRUCTION_COUNT return "none" end
        \\    IMMEDIATE_FORMS[idx + 1]
        \\end
        \\
        \\stack_pop_for_index(idx: i64): i64
        \\    if idx < 0 or idx >= INSTRUCTION_COUNT return 0 end
        \\    STACK_POP[idx + 1]
        \\end
        \\
        \\stack_push_for_index(idx: i64): i64
        \\    if idx < 0 or idx >= INSTRUCTION_COUNT return 0 end
        \\    STACK_PUSH[idx + 1]
        \\end
        \\
        \\
    );
}

fn wardOpcodeFieldName(id: []const u8) []const u8 {
    const local = if (std.mem.startsWith(u8, id, "wasm.")) id["wasm.".len..] else id;
    if (std.mem.eql(u8, local, "if")) return "OP_if_";
    if (std.mem.eql(u8, local, "else")) return "OP_else_";
    if (std.mem.eql(u8, local, "end")) return "OP_end_";
    if (std.mem.eql(u8, local, "return")) return "OP_return_";
    return local;
}

/// Emit `lib/std/wasm/ward_mvp_opcodes.id` — Ward-compatible OP_* for MVP subset only.
pub fn emitWardMvpOpcodes(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\-- GENERATED from src/wasm_semantic_gen.zig — do not edit by hand.
        \\-- Regenerate: duo wasm-tables emit
        \\-- MVP subset (63 ops). Ward extended opcodes remain in ward/src/wasm/op.id until migrated.
        \\
        \\GENERATOR_OWNER = "src/wasm_semantic_gen.zig"
        \\CANONICAL_OWNER = "src/wasm_semantic.zig"
        \\
    );
    for (wasm_semantic.mvp_instructions) |inst| {
        const local = wardOpcodeFieldName(inst.id);
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        if (std.mem.startsWith(u8, local, "OP_")) {
            len = local.len;
            @memcpy(buf[0..len], local);
        } else {
            buf[0..3].* = "OP_".*;
            len = 3;
            for (local) |c| {
                buf[len] = if (c == '.') '_' else c;
                len += 1;
            }
        }
        const field = buf[0..len];
        try w.print("{s} = {d}\n", .{ field, inst.opcode });
    }
    // File-as-module-scope (Pass 48 canonical): the file's top-level bindings
    // ARE the module. No `M = {}` wrapper and no trailing bare `M` — both are
    // graveyard idiom. With no tail expression duo already exports an implicit
    // table of every module-level binding, which is exactly the right shape.
    try w.writeAll("\ncanonical_owner(): str\n    CANONICAL_OWNER\nend\n");
}

pub fn emitWardMvpOpcodesFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitWardMvpOpcodes(&aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
}

pub fn emitDuoOpcodeLookupFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitDuoOpcodeLookup(&aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
}

test "wasm_semantic_gen: emit duo lookup includes i32.add" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitDuoOpcodeLookup(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "wasm.i32.add") != null);
}

test "wasm_semantic_gen: i32.add stack pop 2 push 1" {
    const v = validatorForOpcode(0x6A) orelse return error.MissingValidator;
    try std.testing.expect(v.stack.pop == 2);
    try std.testing.expect(v.stack.push == 1);
    try std.testing.expect(!v.stack.polymorphic);
}

test "wasm_semantic_gen: select is polymorphic" {
    const v = validatorForOpcode(0x1B) orelse return error.MissingValidator;
    try std.testing.expect(v.stack.polymorphic);
    try std.testing.expect(v.stack.pop == 3);
    try std.testing.expect(v.stack.push == 1);
}

test "wasm_semantic_gen: call immediate is func_idx" {
    const form = immediateFormForOpcode(0x10) orelse return error.MissingForm;
    try std.testing.expect(form == .func_idx);
}

test "wasm_semantic_gen: validator table matches instruction count" {
    try std.testing.expect(mvp_validator.len == wasm_semantic.mvpCount());
}
