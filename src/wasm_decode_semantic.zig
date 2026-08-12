//! Ward instruction decode semantic intent (WS12 / M2).
//!
//! Canonical subject for `std.wasm.decode` hot path; barrier proofs live in
//! `native_barrier_checks`.
const std = @import("std");
const proof_carrying = @import("proof_carrying.zig");
const evidence_record = @import("evidence_record.zig");

pub const SCHEMA_VERSION = "wasm-decode-semantic-v0";

pub const intent: proof_carrying.IntentContract = .{
    .subject_entity = "duo:wasm:decode_instruction",
    .summary = "Decode one Wasm instruction from a byte cursor into a typed semantic record",
    .descriptor_id = "wasm_semantic.instructions",
    .laws = "bounded_reads; deterministic_for_input; cursor_advance",
    .representation_constraints = "no_lua_value; no_dynamic_dispatch; native_scalar",
    .determinism_required = true,
    .provenance = "wasm_decode_semantic.v0",
};

pub const projections: []const proof_carrying.SemanticProjection = &.{
    .{ .id = "proj.wasm.decode.decoder", .kind = .decoder_table, .source_entity = "duo:wasm:decode_instruction", .transform_id = "decode.table_dispatch", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.wasm.decode.ward", .kind = .mcp_entity, .source_entity = "duo:wasm:decode_instruction", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.wasm.decode.barrier", .kind = .test_generator, .source_entity = "duo:wasm:decode_instruction", .schema_version = SCHEMA_VERSION },
};

pub const proof_obligations: []const proof_carrying.ProofObligation = &.{
    .{
        .id = "obl.wasm.decode.no_boxing",
        .subject_entity = "duo:wasm:decode_instruction",
        .predicate = "generated C for decode hot path contains no lua_Value or lua_invoke",
        .accepted_evidence = &.{evidence_record.Kind.static_estimate},
        .validation_method = "duo dev barrier check ward_decode",
        .status = .pending,
    },
    .{
        .id = "obl.wasm.decode.differential",
        .subject_entity = "duo:wasm:decode_instruction",
        .predicate = "Duo decode matches reference decoder on MVP opcode corpus",
        .accepted_evidence = &.{ evidence_record.Kind.differential_test, evidence_record.Kind.property_test },
        .validation_method = "examples/pass9/decode_semantic_smoke.id + wasm_decode_differential",
        .status = .discharged,
    },
    .{
        .id = "obl.wasm.decode.cursor",
        .subject_entity = "duo:wasm:decode_instruction",
        .predicate = "cursor advances by exact bytes consumed per instruction",
        .accepted_evidence = &.{evidence_record.Kind.property_test},
        .validation_method = "leb128_cursor_smoke + decode smoke",
        .status = .pending,
    },
};

pub fn entityMatches(entity: []const u8) bool {
    return std.mem.eql(u8, entity, intent.subject_entity) or
        std.mem.eql(u8, entity, "decode_instruction");
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"intent_subject\":\"{s}\",\"descriptor\":\"{s}\",\"obligations\":{d},\"barrier_cli\":\"duo dev barrier check ward_decode\",\"semantic_cli\":[\"duo semantic intent duo:wasm:decode_instruction\",\"duo semantic obligations duo:wasm:decode_instruction\"],\"owners\":[\"lib/std/wasm/decode.duo\",\"src/wasm_semantic_gen.zig\",\"src/wasm_decode_semantic.zig\"]}}", .{
        SCHEMA_VERSION,
        intent.subject_entity,
        intent.descriptor_id.?,
        proof_obligations.len,
    });
}

test "wasm_decode_semantic: writeCatalogJson" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeCatalogJson(&buf.writer);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "duo:wasm:decode_instruction") != null);
}
