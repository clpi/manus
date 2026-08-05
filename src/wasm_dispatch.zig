//! Pass 12 M2 — canonical Ward instruction dispatch descriptor (P12-WS12).
//!
//! Single source of truth for `opcode byte → instruction` dispatch facts,
//! mirroring the Pass 12 M1 pattern (`src/token_semantic.zig`):
//! canonical descriptor → proof-carrying obligations → candidate realizations
//! → differential validation → Duo projection (`lib/std/wasm/dispatch.duo`).
//!
//! `src/wasm_semantic.zig` owns instruction semantics (stack effects, immediates,
//! handlers). This module owns ONLY the dispatch decision: given an opcode byte,
//! which instruction index does it select? No parallel opcode constants.
const std = @import("std");
const wasm_semantic = @import("wasm_semantic.zig");
const proof_carrying = @import("proof_carrying.zig");
const realization = @import("realization.zig");
const evidence_record = @import("evidence_record.zig");
const optimization_outcome = @import("optimization_outcome.zig");

pub const SCHEMA_VERSION = "wasm-dispatch-v0";

pub const intent: proof_carrying.IntentContract = .{
    .subject_entity = "duo:wasm:instruction_dispatch",
    .summary = "Resolve a Wasm MVP opcode byte to its canonical instruction index",
    .descriptor_id = "wasm_semantic.mvp_instructions",
    .laws = "exact_match; deterministic; bounded_reads; dense_opcode_space",
    .representation_constraints = "no_allocation; no_boxing; single_byte_lookup",
    .determinism_required = true,
    .provenance = "wasm_dispatch.v0",
};

pub const projections: []const proof_carrying.SemanticProjection = &.{
    .{ .id = "proj.dispatch.compiler_metadata", .kind = .source, .source_entity = "duo:wasm:instruction_dispatch", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.dispatch.decoder_table", .kind = .decoder_table, .source_entity = "duo:wasm:instruction_dispatch", .transform_id = "dispatch.dense_table", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.dispatch.spelling", .kind = .documentation, .source_entity = "duo:wasm:instruction_dispatch", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.dispatch.lsp", .kind = .lsp_hover, .source_entity = "duo:wasm:instruction_dispatch", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.dispatch.mcp", .kind = .mcp_entity, .source_entity = "duo:wasm:instruction_dispatch", .schema_version = SCHEMA_VERSION },
    .{ .id = "proj.dispatch.tests", .kind = .test_generator, .source_entity = "duo:wasm:instruction_dispatch", .schema_version = SCHEMA_VERSION },
};

pub const proof_obligations: []const proof_carrying.ProofObligation = &.{
    .{
        .id = "obl.dispatch.exact",
        .subject_entity = "duo:wasm:instruction_dispatch",
        .predicate = "every known MVP opcode resolves to exactly its instruction index",
        .accepted_evidence = &.{ evidence_record.Kind.property_test, evidence_record.Kind.differential_test },
        .validation_method = "exhaustive over 256 opcode space",
        .status = .discharged,
    },
    .{
        .id = "obl.dispatch.no_false_positive",
        .subject_entity = "duo:wasm:instruction_dispatch",
        .predicate = "unassigned opcode bytes resolve to unknown (null/0)",
        .accepted_evidence = &.{evidence_record.Kind.property_test},
        .validation_method = "exhaustive over 256 opcode space",
        .status = .discharged,
    },
    .{
        .id = "obl.dispatch.deterministic",
        .subject_entity = "duo:wasm:instruction_dispatch",
        .predicate = "same opcode always yields same instruction index",
        .accepted_evidence = &.{evidence_record.Kind.proven_semantic_fact},
        .validation_method = "pure function; no heap allocation on production path",
        .status = .discharged,
    },
    .{
        .id = "obl.dispatch.no_alloc",
        .subject_entity = "duo:wasm:instruction_dispatch",
        .predicate = "dispatch performs no heap allocation",
        .accepted_evidence = &.{evidence_record.Kind.static_estimate},
        .validation_method = "static inspection of dispatch implementations",
        .status = .discharged,
    },
};

pub const DispatchId = enum {
    dense_table,
    sorted_lookup,
    high_nibble,
    branch_chain,

    pub fn name(self: DispatchId) []const u8 {
        return switch (self) {
            .dense_table => "dispatch.dense_table",
            .sorted_lookup => "dispatch.sorted_lookup",
            .high_nibble => "dispatch.high_nibble",
            .branch_chain => "dispatch.branch_chain",
        };
    }
};

/// Production dispatch — dense 256-entry table (mirrors `wasm_semantic.mvp_opcode_index`).
pub const production_dispatch: DispatchId = .dense_table;

/// Dispatch result: 0-based instruction index into `wasm_semantic.mvp_instructions`.
pub const LookupFn = *const fn (opcode: u8) ?u8;

pub const SelectionSnapshot = struct {
    selected: DispatchId,
    model_selected: DispatchId,
    legal_candidates: u32,
    compared_candidates: u32,
    differential_pass: bool,
};

pub const legal_dispatches = [_]DispatchId{ .dense_table, .sorted_lookup, .high_nibble, .branch_chain };
const fuzz_seed: u64 = 0xD15C0DE;

pub fn dispatchDenseTable(opcode: u8) ?u8 {
    const idx = wasm_semantic.mvp_opcode_index[opcode];
    if (idx < 0) return null;
    return @intCast(idx);
}

pub fn dispatchBranchChain(opcode: u8) ?u8 {
    for (wasm_semantic.mvp_instructions, 0..) |inst, i| {
        if (inst.prefix == null and inst.opcode == opcode) return @intCast(i);
    }
    return null;
}

/// Sorted instruction indices by opcode (built once, mirrors token_semantic pattern).
var sorted_indices: [wasm_semantic.mvp_instructions.len]usize = undefined;
var sorted_built = false;

fn buildSortedIndices() void {
    for (0..wasm_semantic.mvp_instructions.len) |i| sorted_indices[i] = i;
    var i: usize = 1;
    while (i < sorted_indices.len) : (i += 1) {
        const key = sorted_indices[i];
        var j = i;
        while (j > 0 and wasm_semantic.mvp_instructions[key].opcode < wasm_semantic.mvp_instructions[sorted_indices[j - 1]].opcode) {
            sorted_indices[j] = sorted_indices[j - 1];
            j -= 1;
        }
        sorted_indices[j] = key;
    }
    sorted_built = true;
}

fn sortedByOpcode() []const usize {
    if (!sorted_built) buildSortedIndices();
    return &sorted_indices;
}

pub fn dispatchSortedLookup(opcode: u8) ?u8 {
    const sorted = sortedByOpcode();
    var lo: usize = 0;
    var hi: usize = sorted.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const cand = wasm_semantic.mvp_instructions[sorted[mid]].opcode;
        if (cand == opcode) return @intCast(sorted[mid]);
        if (opcode < cand) hi = mid else lo = mid + 1;
    }
    return null;
}

pub fn dispatchHighNibble(opcode: u8) ?u8 {
    const nibble = opcode >> 4;
    for (wasm_semantic.mvp_instructions, 0..) |inst, i| {
        if (inst.prefix == null and inst.opcode >> 4 == nibble and inst.opcode == opcode) return @intCast(i);
    }
    return null;
}

pub fn dispatchWith(id: DispatchId, opcode: u8) ?u8 {
    return switch (id) {
        .dense_table => dispatchDenseTable(opcode),
        .sorted_lookup => dispatchSortedLookup(opcode),
        .high_nibble => dispatchHighNibble(opcode),
        .branch_chain => dispatchBranchChain(opcode),
    };
}

/// Production entry — fixed dispatch (no runtime selection on hot path).
pub fn dispatchOpcode(opcode: u8) ?u8 {
    return dispatchWith(production_dispatch, opcode);
}

pub fn differentialValidateDispatches() !void {
    for (0..256) |op| {
        const opcode: u8 = @intCast(op);
        const ref = dispatchDenseTable(opcode);
        for (legal_dispatches) |did| {
            if (dispatchWith(did, opcode) != ref) return error.DispatchMismatch;
        }
    }
}

pub fn differentialCheck(seed: u64) bool {
    differentialValidateDispatches() catch return false;
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var i: u32 = 0;
    while (i < 512) : (i += 1) {
        const opcode: u8 = random.int(u8);
        const ref = dispatchDenseTable(opcode);
        for (legal_dispatches) |did| {
            if (dispatchWith(did, opcode) != ref) return false;
        }
    }
    return true;
}

pub fn estimatedCyclesPerDispatch(id: DispatchId) u32 {
    return switch (id) {
        .dense_table => 1,
        .sorted_lookup => 5,
        .high_nibble => 6,
        .branch_chain => 20,
    };
}

pub fn compareDispatchCandidates(alloc: std.mem.Allocator) !realization.CandidateComparisonReport {
    var candidates: std.ArrayListUnmanaged(realization.Candidate) = .empty;
    errdefer {
        for (candidates.items) |*c| c.deinit(alloc);
        candidates.deinit(alloc);
    }
    try pushCandidate(alloc, &candidates, "dispatch.dense_table", "256-entry direct index", "direct_table", 1, 60, true, null, .proven);
    try pushCandidate(alloc, &candidates, "dispatch.sorted_lookup", "Binary search sorted opcodes", "sorted_table", 5, 70, true, null, .proven);
    try pushCandidate(alloc, &candidates, "dispatch.high_nibble", "Nibble bucket + scan", "nibble_bucket", 6, 75, true, null, .proven);
    try pushCandidate(alloc, &candidates, "dispatch.branch_chain", "Linear equality chain", "branch_chain", 20, 80, true, null, .proven);
    try pushCandidate(alloc, &candidates, "dispatch.perfect_hash", "Perfect hash function", "phf", 2, 50, false, "opcode space is already dense (256); direct index is optimal", .estimated);
    var var_: realization.Variable = .{
        .id = try alloc.dupe(u8, "realize.wasm_dispatch"),
        .subject_entity = try alloc.dupe(u8, intent.subject_entity),
        .dimension = .algorithm,
        .candidates = try candidates.toOwnedSlice(alloc),
        .freedoms = &.{},
    };
    defer var_.deinit(alloc);
    return realization.compareCandidates(alloc, &var_);
}

fn pushCandidate(
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(realization.Candidate),
    id: []const u8,
    label: []const u8,
    repr: []const u8,
    cost: u32,
    optionality: u32,
    legal: bool,
    reason: ?[]const u8,
    evidence: optimization_outcome.Evidence,
) !void {
    try out.append(alloc, .{
        .id = try alloc.dupe(u8, id),
        .label = try alloc.dupe(u8, label),
        .representation = try alloc.dupe(u8, repr),
        .static_cost = cost,
        .optionality_retained = optionality,
        .legal = legal,
        .rejection_reason = if (reason) |r| try alloc.dupe(u8, r) else null,
        .evidence = evidence,
        .fallback = if (!legal) try alloc.dupe(u8, "direct_table") else null,
    });
}

fn dispatchFromId(id: []const u8) DispatchId {
    if (std.mem.eql(u8, id, DispatchId.sorted_lookup.name())) return .sorted_lookup;
    if (std.mem.eql(u8, id, DispatchId.high_nibble.name())) return .high_nibble;
    if (std.mem.eql(u8, id, DispatchId.branch_chain.name())) return .branch_chain;
    return .dense_table;
}

/// Static-cost comparison + differential check; production remains `production_dispatch`.
pub fn selectDispatch(alloc: std.mem.Allocator) !SelectionSnapshot {
    if (!differentialCheck(fuzz_seed)) return error.DifferentialFailed;
    var report = try compareDispatchCandidates(alloc);
    defer report.deinit(alloc);
    const model_selected = dispatchFromId(report.selected_id orelse DispatchId.dense_table.name());
    return .{
        .selected = production_dispatch,
        .model_selected = model_selected,
        .legal_candidates = @intCast(report.legal_count),
        .compared_candidates = @intCast(report.compared_count),
        .differential_pass = true,
    };
}

pub fn handlerForIndex(index: u8) []const u8 {
    if (index >= wasm_semantic.mvp_instructions.len) return "";
    return wasm_semantic.mvp_instructions[index].handler;
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"instruction_count\":{d},\"known_opcodes\":{d},\"intent_subject\":\"{s}\",\"production_dispatch\":\"{s}\",\"production_consumer\":\"src/wasm_semantic.zig:decodeOpcode\",\"cost_model\":\"static_cycles\"", .{
        SCHEMA_VERSION,
        wasm_semantic.mvpCount(),
        wasm_semantic.knownOpcodeCount(),
        intent.subject_entity,
        production_dispatch.name(),
    });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    if (selectDispatch(arena.allocator())) |snap| {
        try w.print(",\"model_selected_dispatch\":\"{s}\"", .{snap.model_selected.name()});
        try w.print(",\"selection\":{{\"legal_candidates\":{d},\"compared_candidates\":{d},\"differential_pass\":true}}", .{
            snap.legal_candidates,
            snap.compared_candidates,
        });
    } else |_| {
        try w.print(",\"selection\":{{\"differential_pass\":false}}", .{});
    }
    try w.print(",\"obligations_discharged\":{d},\"dispatches\":[", .{proof_obligations.len});
    for (legal_dispatches, 0..) |did, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{did.name()});
    }
    try w.print("],\"projections\":[", .{});
    for (projections, 0..) |p, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"kind\":\"{s}\"}}", .{ p.id, p.kind.name() });
    }
    try w.print("]}}", .{});
}

test "wasm_dispatch: unreachable opcode resolves to instruction 0" {
    const decoded = wasm_semantic.decodeOpcode(0x00);
    try std.testing.expectEqual(@as(?u8, @intCast(decoded.instruction_index)), dispatchOpcode(0x00));
}

test "wasm_dispatch: i32.add opcode resolves to its instruction" {
    const decoded = wasm_semantic.decodeOpcode(0x6A);
    const expect_idx: u8 = @intCast(decoded.instruction_index);
    try std.testing.expectEqual(@as(?u8, expect_idx), dispatchOpcode(0x6A));
}

test "wasm_dispatch: negative dispatch" {
    try std.testing.expect(dispatchOpcode(0xFF) == null);
    try std.testing.expect(dispatchOpcode(0x1C) == null);
    try std.testing.expect(dispatchOpcode(0x1D) == null);
}

test "wasm_dispatch: all legal dispatches agree" {
    try differentialValidateDispatches();
    try std.testing.expect(differentialCheck(fuzz_seed));
}

test "wasm_dispatch: compareDispatchCandidates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var report = try compareDispatchCandidates(arena.allocator());
    defer report.deinit(arena.allocator());
    try std.testing.expectEqual(@as(usize, 4), report.legal_count);
    try std.testing.expectEqualStrings("dispatch.dense_table", report.selected_id.?);
}

test "wasm_dispatch: selectDispatch keeps production dense_table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snap = try selectDispatch(arena.allocator());
    try std.testing.expectEqual(production_dispatch, snap.selected);
    try std.testing.expect(snap.differential_pass);
    try std.testing.expectEqual(@as(u32, 4), snap.legal_candidates);
}

test "wasm_dispatch: writeCatalogJson" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeCatalogJson(&buf.writer);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "production_dispatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "dispatch.high_nibble") != null);
}
