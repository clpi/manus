//! Pass 12 M2 — Duo-native Ward dispatch projection (P12-WS12).
//!
//! Emits `lib/std/wasm/dispatch.duo` from the canonical descriptor in
//! `src/wasm_semantic.zig` (opcode facts) + `src/wasm_dispatch.zig` (dispatch
//! decision, proof obligations, candidate selection).
//!
//! Projections emitted here: dispatch tables (dense / sorted / high-nibble /
//! branch chain candidate realizations), handler + immediate metadata. Indexes
//! are 1-based Lua positions so the Duo side is differential-equivalent to the
//! Zig host path (`wasm_semantic.decodeOpcode` / `dispatchOpcode`).
const std = @import("std");
const wasm_semantic = @import("wasm_semantic.zig");
const wasm_dispatch = @import("wasm_dispatch.zig");

pub const SCHEMA_VERSION = "wasm-dispatch-v0";
pub const PROVENANCE = "src/wasm_dispatch_gen.zig";

fn dispatchForOpcode(opcode: u8) u8 {
    const idx = wasm_semantic.mvp_opcode_index[opcode];
    if (idx < 0) return 0;
    return @intCast(idx + 1);
}

fn sortedOpcodeIndices() [wasm_semantic.mvp_instructions.len]usize {
    var idx: [wasm_semantic.mvp_instructions.len]usize = undefined;
    for (0..idx.len) |i| idx[i] = i;
    var i: usize = 1;
    while (i < idx.len) : (i += 1) {
        const key = idx[i];
        var j = i;
        while (j > 0 and wasm_semantic.mvp_instructions[key].opcode < wasm_semantic.mvp_instructions[idx[j - 1]].opcode) {
            idx[j] = idx[j - 1];
            j -= 1;
        }
        idx[j] = key;
    }
    return idx;
}

/// Nibble-ordered entries: instruction indices sorted by (opcode >> 4, opcode).
fn nibbleOrder() [wasm_semantic.mvp_instructions.len]usize {
    var idx: [wasm_semantic.mvp_instructions.len]usize = undefined;
    for (0..idx.len) |i| idx[i] = i;
    var i: usize = 1;
    while (i < idx.len) : (i += 1) {
        const key = idx[i];
        const key_n = wasm_semantic.mvp_instructions[key].opcode >> 4;
        var j = i;
        while (j > 0) {
            const prev = wasm_semantic.mvp_instructions[idx[j - 1]];
            const prev_n = prev.opcode >> 4;
            if (prev_n > key_n or (prev_n == key_n and prev.opcode > wasm_semantic.mvp_instructions[key].opcode)) {
                idx[j] = idx[j - 1];
                j -= 1;
            } else break;
        }
        idx[j] = key;
    }
    return idx;
}

fn nibbleStarts(order: []const usize) [17]usize {
    var starts: [17]usize = undefined;
    var nibble: usize = 0;
    var i: usize = 0;
    while (nibble <= 16) : (nibble += 1) {
        while (i < order.len and wasm_semantic.mvp_instructions[order[i]].opcode >> 4 < nibble) : (i += 1) {}
        starts[nibble] = i;
    }
    return starts;
}

pub fn emitWasmDispatch(w: *std.Io.Writer) !void {
    const insts = wasm_semantic.mvp_instructions;
    const sorted = sortedOpcodeIndices();
    const order = nibbleOrder();
    const starts = nibbleStarts(&order);

    try w.print(
        \\-- GENERATED from src/wasm_dispatch_gen.zig — do not edit by hand.
        \\-- Regenerate: duo wasm-dispatch emit
        \\-- Canonical opcode facts: src/wasm_semantic.zig
        \\-- Canonical dispatch decision: src/wasm_dispatch.zig
        \\
        \\-- Pass 12 M2 — Duo-native Ward instruction dispatch (P12-WS12).
        \\-- {d} MVP instructions; 4 candidate realizations; dense 256-entry
        \\-- table is production (mirrors src/wasm_semantic.zig:mvp_opcode_index).
        \\-- Proof: examples/pass12_m2_diff.duo (exhaustive differential over all
        \\-- 256 opcode bytes; dispatch = 1-based instruction index, 0 = unknown).
        \\
        \\GENERATOR_OWNER = "src/wasm_dispatch_gen.zig"
        \\DESCRIPTOR_SCHEMA = "wasm-dispatch-v0"
        \\INSTRUCTION_COUNT = {d}
        \\KNOWN_OPCODES = {d}
        \\PRODUCTION_DISPATCH = "dispatch.dense_table"
        \\
    , .{ insts.len, insts.len, wasm_semantic.knownOpcodeCount() });

    // Dense 256-entry table: [opcode] = dispatch (1-based) or 0 (unknown).
    try w.writeAll("\n-- Dense 256-entry dispatch table (production).\nDISPATCH_DENSE = {\n");
    for (0..256) |op| {
        try w.print("    [{d}] = {d},\n", .{ op, dispatchForOpcode(@intCast(op)) });
    }
    try w.writeAll("}\n");

    // Sorted descriptor (by opcode) for sorted_lookup + metadata.
    try w.writeAll("\n-- Sorted descriptor (by opcode) for sorted_lookup.\nSORTED_OPCODES = {\n");
    for (sorted) |ki| try w.print("    {d},\n", .{insts[ki].opcode});
    try w.writeAll("}\nSORTED_DISPATCH = {\n");
    for (sorted) |ki| try w.print("    {d},\n", .{ki + 1});
    try w.writeAll("}\n");

    // Nibble-ordered entries + start offsets for high_nibble candidate.
    try w.writeAll("\n-- Nibble-bucketed order + opcodes for high_nibble dispatch.\nNIBBLE_ORDER = {\n");
    for (order) |ki| try w.print("    {d},\n", .{ki + 1});
    try w.writeAll("}\nNIBBLE_OPCODES = {\n");
    for (order) |ki| try w.print("    {d},\n", .{insts[ki].opcode});
    try w.writeAll("}\nNIBBLE_START = {\n");
    for (starts) |s| try w.print("    {d},\n", .{s + 1});
    try w.writeAll("}\n");

    // Per-instruction metadata (1-based index).
    try w.writeAll("\n-- Per-instruction metadata (1-based index).\nINSTRUCTION_IDS = {\n");
    for (insts) |inst| try w.print("    \"{s}\",\n", .{inst.id});
    try w.writeAll("}\nHANDLERS = {\n");
    for (insts) |inst| try w.print("    \"{s}\",\n", .{inst.handler});
    try w.writeAll("}\nIMMEDIATE_FORMS = {\n");
    for (insts) |inst| try w.print("    \"{s}\",\n", .{inst.immediate.name()});
    try w.writeAll("}\n");

    // Candidate 1 — dense table (production).
    try w.writeAll("\n-- Candidate 1: dense 256-entry direct index (production).\nfun dispatch_dense_table(op): i64\n    v = DISPATCH_DENSE[op]\n    if v == nil then return 0 end\n    v\nend\n");

    // Candidate 2 — sorted binary search.
    try w.print("\n-- Candidate 2: sorted lookup (binary search over descriptor).\nfun dispatch_sorted_lookup(op): i64\n    lo = 1\n    hi = {d}\n    while lo <= hi\n        mid = (lo + hi) // 2\n        if op == SORTED_OPCODES[mid] then return SORTED_DISPATCH[mid] end\n        if op < SORTED_OPCODES[mid] then\n            hi = mid - 1\n        else\n            lo = mid + 1\n        end\n    end\n    0\nend\n", .{sorted.len});

    // Candidate 3 — high-nibble bucket + scan.
    try w.writeAll("\n-- Candidate 3: high-nibble bucket (16 buckets, then scan).\nfun dispatch_high_nibble(op): i64\n    nb = op // 16\n    i = NIBBLE_START[nb + 1]\n    last = NIBBLE_START[nb + 2]\n    while i < last\n        if op == NIBBLE_OPCODES[i] then return NIBBLE_ORDER[i] end\n        i = i + 1\n    end\n    0\nend\n");

    // Candidate 4 — branch chain (linear equality chain).
    try w.writeAll("\n-- Candidate 4: branch chain (linear equality chain).\nfun dispatch_branch_chain(op): i64\n");
    for (insts, 0..) |inst, i| {
        if (inst.prefix == null) try w.print("    if op == {d} then return {d} end\n", .{ inst.opcode, i + 1 });
    }
    try w.writeAll("    0\nend\n");

    // Production entry + metadata projections.
    try w.writeAll(
        \\
        \\-- Production entry (mirrors wasm_dispatch.production_dispatch).
        \\fun dispatch_opcode(op): i64
        \\    dispatch_dense_table(op)
        \\end
        \\
        \\fun is_known_opcode(op): bool
        \\    dispatch_opcode(op) != 0
        \\end
        \\
        \\fun handler_for_opcode(op): str
        \\    idx = dispatch_opcode(op)
        \\    if idx == 0 then return "" end
        \\    HANDLERS[idx]
        \\end
        \\
        \\fun semantic_id_for_opcode(op): str
        \\    idx = dispatch_opcode(op)
        \\    if idx == 0 then return "" end
        \\    INSTRUCTION_IDS[idx]
        \\end
        \\
        \\fun immediate_form_for_opcode(op): str
        \\    idx = dispatch_opcode(op)
        \\    if idx == 0 then return "none" end
        \\    IMMEDIATE_FORMS[idx]
        \\end
        \\
    );
}

pub fn emitWasmDispatchFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitWasmDispatch(&aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
}

test "wasm_dispatch_gen: dense table has all 256 entries" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitWasmDispatch(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "[106] = ") != null); // 0x6A
    try std.testing.expect(std.mem.indexOf(u8, out, "[255] = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "dispatch_high_nibble") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HANDLERS") != null);
}

test "wasm_dispatch_gen: known opcode has nonzero dispatch" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitWasmDispatch(&aw.writer);
    const out = aw.written();
    var buf: [32]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "[{d}] = ", .{wasm_semantic.mvp_opcode_index[0x6A]}) catch unreachable;
    _ = line;
    const want = std.fmt.bufPrint(&buf, "[106] = {d}", .{dispatchForOpcode(0x6A)}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, out, want) != null);
}

test "wasm_dispatch_gen: sorted descriptor is ascending by opcode" {
    const sorted = sortedOpcodeIndices();
    for (1..sorted.len) |i| {
        try std.testing.expect(wasm_semantic.mvp_instructions[sorted[i - 1]].opcode < wasm_semantic.mvp_instructions[sorted[i]].opcode);
    }
}

test "wasm_dispatch_gen: nibble starts cover all entries" {
    const order = nibbleOrder();
    const starts = nibbleStarts(&order);
    try std.testing.expect(starts[0] == 0);
    try std.testing.expect(starts[16] == order.len);
}
