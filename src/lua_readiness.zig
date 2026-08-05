//! Pass 14 §18 Audit 10, §22 Deliverable J — Lua readiness report.
//!
//! Evaluates Duo as a Lua implementation across the §10 dimensions
//! (compatibility, interpreter startup, AOT, JIT, adaptive specialization,
//! table/closure/metatable/multi-return/coroutine performance, embedding, FFI,
//! debugging, diagnostics, memory, compilation latency). The goal (§12.2): be
//! the strongest practical Lua compiler while eliminating Lua *implementation*
//! costs from specialized regions.
const std = @import("std");

pub const SCHEMA_VERSION = "lua-readiness-v0";

pub const Status = enum {
    proven,
    partial,
    open,
    not_applicable,

    pub fn name(self: Status) []const u8 {
        return @tagName(self);
    }
};

pub const Dimension = struct {
    id: []const u8,
    dimension: []const u8,
    status: Status,
    finding: []const u8,
};

/// Pass 14 §18 Audit 10 — the Lua supremacy dimensions, evaluated against the
/// current compiler (sourced from Pass 4 §F + the codegen/runtime audit).
pub const dimensions: []const Dimension = &.{
    .{ .id = "lua-compat", .dimension = "Lua compatibility", .status = .partial, .finding = "Lua superset on dynamic paths; missing-args-nil, and/or truthiness, table-key semantics preserved. No differential Lua 5.5 suite yet, so compatibility is asserted, not proven across the corpus." },
    .{ .id = "interpreter-startup", .dimension = "Interpreter startup", .status = .open, .finding = "No standalone interpreter mode benchmark; Duo compiles to C/native, so 'startup' is binary load + runtime preamble, not bytecode load. Sub-ms startup is a target vs PyTorch-class runtimes, not yet measured vs luajit." },
    .{ .id = "aot", .dimension = "AOT compilation", .status = .proven, .finding = "Profile A (default): generated C → Clang AOT for any Clang target. Typed .duo paths lower to native C scalars/structs without lua_Value when native_scalar_mode proven (Pass 4 M1 distance2 proof)." },
    .{ .id = "jit", .dimension = "JIT / adaptive compilation", .status = .open, .finding = "No JIT or adaptive specialization tier yet. The knowledge-lattice + transform-engine + realization foundations (Pass 8) are the planned substrate, but no runtime profiler/hot-path promoter exists." },
    .{ .id = "adaptive-spec", .dimension = "Adaptive specialization", .status = .partial, .finding = "Static specialization is strong (call-shape, table-shape, closure, return-pack). Adaptive (runtime-guided) specialization is open — depends on the JIT tier + profile-guided realization (Pass 8 realization variables)." },
    .{ .id = "table-perf", .dimension = "Table performance", .status = .partial, .finding = "Known shapes specialize to native C structs/arrays (dense numeric → int64_t*, sealed records → C struct). Generic heterogeneous tables still route through lua_table_* + metatable lookup. Dense-table detection (G-054) fixed misclassification of empty {} tables." },
    .{ .id = "closure-perf", .dimension = "Closure performance", .status = .partial, .finding = "Non-escaping constant captures avoid heap closures on native paths; escaping/dynamic closures still use heap closure environments. Closure specialization is a knowledge-lattice decision, not universal." },
    .{ .id = "metatable-dispatch", .dimension = "Metatable dispatch", .status = .partial, .finding = "Dynamic paths preserve metatable dispatch (Lua semantics). Specialized paths eliminate it via direct field access / direct calls when the shape is known. No static __index resolution analysis yet." },
    .{ .id = "multi-return", .dimension = "Multiple returns", .status = .partial, .finding = "Multiple returns stay compiler dataflow until a dynamic boundary (Pass 4 invariant P4-05). Return-pack native dataflow is open (P4-06) — multi-return still materializes at dynamic boundaries." },
    .{ .id = "coroutines", .dimension = "Coroutines", .status = .partial, .finding = "Lua coroutine semantics preserved on dynamic paths via the embedded runtime. No native coroutine lowering; coroutines are a dynamic-boundary construct today." },
    .{ .id = "embedding", .dimension = "Embedding", .status = .partial, .finding = "Generated C embeds a runtime preamble when moduleNeedsLuaRuntime; pay-for-use linking is partial (native_scalar_mode skips much of it). No clean embedding API / library form yet (Pass 4 P4-09, P4-17)." },
    .{ .id = "ffi", .dimension = "FFI", .status = .partial, .finding = "@ffi / @c.import / @c.emit provide direct C ABI calls (P5-M1 proven for point.h). Foreign calls must not route through lua_Value (PB-011). Layout verification exists; full FFI ergonomics + callback support partial." },
    .{ .id = "debugging", .dimension = "Debugging", .status = .open, .finding = "No source-level debugger or DWARF/debug-info emission yet. Diagnostics + causal traces exist (Pass 15), but interactive debugging / stepping is open." },
    .{ .id = "diagnostics", .dimension = "Diagnostics", .status = .partial, .finding = "Structured diagnostics exist; Pass 14 §15 mandates beautiful, causal, dense output. Repair suggestions + causal traces are partial; presentation engine unification is Pass 13 WS10." },
    .{ .id = "memory", .dimension = "Memory / GC", .status = .partial, .finding = "Dynamic paths use the embedded GC; specialized paths avoid allocation. No GC tuning/measurements vs reference Lua runtimes; mandatory GC only on dynamic paths (§12.2 satisfied for specialized regions)." },
    .{ .id = "compile-latency", .dimension = "Compilation latency", .status = .partial, .finding = "Profile A compile latency dominated by the Clang invocation. Direct backend skips C but is ARM64-MacOS-Mach-O only. Incremental compilation via .zig-cache; no Duo-level incremental semantic cache yet (Pass 14 §14)." },
};

pub fn summary() struct { total: usize, proven: usize, partial: usize, open: usize } {
    var proven: usize = 0;
    var partial: usize = 0;
    var open: usize = 0;
    for (dimensions) |d| {
        switch (d.status) {
            .proven => proven += 1,
            .partial => partial += 1,
            .open => open += 1,
            .not_applicable => {},
        }
    }
    return .{ .total = dimensions.len, .proven = proven, .partial = partial, .open = open };
}

pub fn writeReadinessJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"goal\":\"strongest practical Lua compiler; eliminate Lua implementation costs from specialized regions\",\"dimensions\":[", .{SCHEMA_VERSION});
    for (dimensions, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"dimension\":\"{s}\",\"status\":\"{s}\",\"finding\":\"{s}\"}}", .{ d.id, d.dimension, d.status.name(), d.finding });
    }
    const s = summary();
    try w.print("],\"summary\":{{\"total\":{d},\"proven\":{d},\"partial\":{d},\"open\":{d}}}}}", .{ s.total, s.proven, s.partial, s.open });
}

test "lua_readiness: all §10 dimensions present" {
    // §18 Audit 10 lists 16 dimensions.
    try std.testing.expectEqual(@as(usize, 16), dimensions.len);
    for (dimensions) |d| {
        try std.testing.expect(d.id.len > 0);
        try std.testing.expect(d.finding.len > 0);
    }
}

test "lua_readiness: no dimension claims proven without a finding" {
    for (dimensions) |d| {
        if (d.status == .proven) try std.testing.expect(d.finding.len >= 20);
    }
}

test "lua_readiness: JSON parses" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeReadinessJson(&aw.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(usize, dimensions.len), parsed.value.object.get("dimensions").?.array.items.len);
    try std.testing.expect(parsed.value.object.get("summary").? == .object);
}
