//! Pass 9 P9-WS7 — differential conformance between decode tables and wasm_semantic.
//!
//! Validates opcode index, validator metadata, and immediate dispatch stay aligned.
const std = @import("std");
const wasm_semantic = @import("wasm_semantic.zig");
const wasm_semantic_gen = @import("wasm_semantic_gen.zig");

test "wasm_decode_differential: every MVP instruction decodes to its index" {
    for (wasm_semantic.mvp_instructions, 0..) |inst, idx| {
        if (inst.prefix != null) continue;
        const decoded = wasm_semantic.decodeOpcode(inst.opcode);
        try std.testing.expect(decoded.status == .ok);
        try std.testing.expect(decoded.instruction_index == @as(i16, @intCast(idx)));
        try std.testing.expectEqualStrings(inst.id, decoded.instruction.?.id);
    }
}

test "wasm_decode_differential: validator entry matches decode for all 256 opcodes" {
    for (0..256) |op| {
        const opcode: u8 = @intCast(op);
        const decoded = wasm_semantic.decodeOpcode(opcode);
        const validator = wasm_semantic_gen.validatorForOpcode(opcode);
        const form = wasm_semantic_gen.immediateFormForOpcode(opcode);
        if (decoded.status == .unknown_opcode) {
            try std.testing.expect(validator == null);
            try std.testing.expect(form == null);
            continue;
        }
        const v = validator orelse return error.MissingValidator;
        try std.testing.expect(v.instruction_index == @as(u16, @intCast(decoded.instruction_index)));
        try std.testing.expectEqualStrings(decoded.instruction.?.id, v.id);
        try std.testing.expect(v.immediate == form.?);
        try std.testing.expectEqualStrings(decoded.instruction.?.handler, v.handler);
    }
}

test "wasm_decode_differential: stack metadata matches instruction arity" {
    for (wasm_semantic.mvp_instructions, 0..) |inst, idx| {
        const v = wasm_semantic_gen.validatorForIndex(idx) orelse return error.MissingValidator;
        if (inst.control_flow and inst.stack_in.len == 0) {
            try std.testing.expect(v.stack.polymorphic);
            continue;
        }
        const expected_pop: u8 = if (v.stack.polymorphic and inst.stack_in.len == 0)
            wasm_semantic_gen.POLY_STACK
        else
            @intCast(inst.stack_in.len);
        const expected_push: u8 = if (v.stack.polymorphic and inst.stack_out.len == 0)
            wasm_semantic_gen.POLY_STACK
        else
            @intCast(inst.stack_out.len);
        try std.testing.expect(v.stack.pop == expected_pop or v.stack.polymorphic);
        try std.testing.expect(v.stack.push == expected_push or v.stack.polymorphic);
    }
}

test "wasm_decode_differential: unknown opcode 0xFF" {
    const decoded = wasm_semantic.decodeOpcode(0xFF);
    try std.testing.expect(decoded.status == .unknown_opcode);
    try std.testing.expect(wasm_semantic_gen.validatorForOpcode(0xFF) == null);
}

test "wasm_decode_differential: known opcode count is 63" {
    try std.testing.expect(wasm_semantic.knownOpcodeCount() == 63);
    try std.testing.expect(wasm_semantic.mvpCount() == 63);
}

test "wasm_decode_differential: i32.add round-trip facts" {
    const decoded = wasm_semantic.decodeOpcode(0x6A);
    try std.testing.expectEqualStrings("wasm.i32.add", decoded.instruction.?.id);
    const v = wasm_semantic_gen.validatorForOpcode(0x6A).?;
    try std.testing.expect(v.stack.pop == 2);
    try std.testing.expect(v.stack.push == 1);
    try std.testing.expect(v.immediate == .none);
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"wasm-decode-differential-v0\",\"mvp_count\":{d},\"known_opcodes\":{d},\"tests\":[\"decode_index\",\"validator_opcode\",\"stack_metadata\",\"unknown_0xFF\"]}}", .{
        wasm_semantic.mvpCount(),
        wasm_semantic.knownOpcodeCount(),
    });
}
