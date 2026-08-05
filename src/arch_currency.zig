//! Pass 14 §3, §18 Audit 13, Milestone 8 — architectural currency loop.
//!
//! A structured record of external compiler/language/hardware developments and
//! Duo's disposition for each. This makes the `observe → classify → compare →
//! reconcile → adopt/adapt/defer/reject → record rationale` loop (§3.2)
//! machine-readable instead of folklore. Popularity is evidence of relevance,
//! not proof of quality (§3.3): every entry is judged against Duo's permanent
//! priority order.
const std = @import("std");

pub const SCHEMA_VERSION = "arch-currency-v0";

/// Pass 14 §3.3 disposition classification.
pub const Disposition = enum {
    irrelevant,
    already_subsumed,
    useful_technique,
    ergonomic_lesson,
    adaptation_candidate,
    architectural_opportunity,
    immediate_correction,
    experimental_branch,
    long_term_research,
    rejected_with_rationale,

    pub fn name(self: Disposition) []const u8 {
        return @tagName(self);
    }
};

pub const Category = enum {
    language,
    compiler,
    research,
    hardware,
    webassembly,
    ai_tooling,
    lsp,
    mcp,
    build_system,
    dev_discourse,

    pub fn name(self: Category) []const u8 {
        return @tagName(self);
    }
};

pub const Record = struct {
    id: []const u8,
    source: []const u8,
    category: Category,
    relevance: []const u8,
    architectural_fit: []const u8,
    api_impact: []const u8,
    performance_impact: []const u8,
    disposition: Disposition,
    rationale: []const u8,
};

/// Pass 14 §18 Audit 13 — seed observations of the external landscape.
/// Each is evaluated against the permanent priority order (runtime perf,
/// sovereignty, ergonomics, compression, Lua familiarity, specialization,
/// agent usability, cross-language, convergence, self-hosting).
pub const records: []const Record = &.{
    .{
        .id = "cur-mojo-ml-native",
        .source = "Modular Mojo (AI/ML-native language)",
        .category = .language,
        .relevance = "high — Duo targets AI/ML-native compilation (AGENTS.md §3).",
        .architectural_fit = "Duo already designs for this: Tensor[dims,dtype] shape checking, @comp.device(.auto) multi-target, @comp.autodiff, kernel fusion, sub-ms startup / <1MB binary vs PyTorch's 2GB.",
        .api_impact = "none — Duo's surface is already designed to exceed Mojo on startup/binary size and metaprogramming.",
        .performance_impact = "Duo must beat Mojo on startup + binary size; the metaprogramming multiplier is the differentiator.",
        .disposition = .already_subsumed,
        .rationale = "Duo's @comp.* + Tensor + device model already cover Mojo's thesis with stronger metaprogramming. Watch for Mojo's autodiff and GPU memory-space ergonomics to fold in.",
    },
    .{
        .id = "cur-zig-comptime",
        .source = "Zig comptime / Jai #run / Rust proc macros",
        .category = .language,
        .relevance = "high — metaprogramming is Duo's primary competitive advantage.",
        .architectural_fit = "Duo's @comp.* exponential combinators (map→derive→product→tensor→nfold→tower→power→permute) are designed to be strictly more capable than all three.",
        .api_impact = "none — Duo's grammar is canonical; these are the comparison baseline, not a target.",
        .performance_impact = "metaprogramming output must lower to native with zero lua_Value (already enforced on typed paths).",
        .disposition = .already_subsumed,
        .rationale = "AGENTS.md mandates MORE capability than Jai/Rust/Zig. G-060/G-061 (nested combinator folding, transform-engine parity) are the active convergence work, not new features.",
    },
    .{
        .id = "cur-llvm-free-backends",
        .source = "Cranelift, qbe, LLVM-free JITs, ispc-style target-specific lowering",
        .category = .compiler,
        .relevance = "high — directly bears on Pass 14 §1.2 sovereignty and §2 universal performance.",
        .architectural_fit = "Duo's direct backend already emits Mach-O without LLVM/Clang for an ARM64 subset. The lesson: own the smallest sufficient substrate per target (§8.1).",
        .api_impact = "informs the target-descriptor → ABI → object-format → features projection (§13.2), not new syntax.",
        .performance_impact = "target-specific lowering must beat generic C; SIMD/register/calling-convention selection is the win.",
        .disposition = .adaptation_candidate,
        .rationale = "Technique to adopt: per-target instruction selection + Duo-owned object writers (not Cranelift as a dependency — §1.2 forbids it). Feeds Milestone 5 + 7.",
    },
    .{
        .id = "cur-wasm-proposals",
        .source = "WebAssembly SIMD, GC, component-model, exception-handling proposals",
        .category = .webassembly,
        .relevance = "high — Ward (Pass 9) is a primary vertical proof and Wasm is a target.",
        .architectural_fit = "Ward must consume Duo's canonical wasm_semantic descriptors; proposals extend the descriptor space, they do not fork it.",
        .api_impact = "exposed via @comp.device / target capability constraints, not new core syntax.",
        .performance_impact = "Wasm SIMD realization is one of the §2.5 portable-semantic realizations (same source → scalar/SIMD/GPU).",
        .disposition = .architectural_opportunity,
        .rationale = "Map proposals into descriptor capability records + realization candidates. Ward L2 (wasm semantic model) is the integration point.",
    },
    .{
        .id = "cur-tree-sitter-incremental",
        .source = "Tree-sitter incremental parsing + error recovery",
        .category = .lsp,
        .relevance = "medium — bears on diagnostic latency + LSP responsiveness (§1.3, §18 Audit 12).",
        .architectural_fit = "Duo maintains a tree-sitter-duo grammar; incremental parsing is the technique for fast LSP under edits.",
        .api_impact = "none to user syntax; informs internal parser invalidation.",
        .performance_impact = "lower diagnostic/LSP latency (§1.3).",
        .disposition = .useful_technique,
        .rationale = "Keep tree-sitter-duo parity-gated against the canonical parser (Pass 13 A3-01 risk). Incremental invalidation is the technique to adopt for LSP latency.",
    },
    .{
        .id = "cur-mcp-lsp-standardization",
        .source = "MCP + LSP standardization momentum across editors/agents",
        .category = .mcp,
        .relevance = "high — Duo ships both an end-user MCP and a development MCP (Pass 13 two-role boundary).",
        .architectural_fit = "Duo already separates end-user MCP (compiler semantics) from development MCP (coordination). Standardization reinforces the split.",
        .api_impact = "schema versioning must stay explicit (Pass 13 A1-07); adopt new standard fields as projections of canonical facts.",
        .performance_impact = "none directly; structured output improves agent throughput.",
        .disposition = .adaptation_candidate,
        .rationale = "Track schema evolution; never let an external MCP/LSP schema become a semantic authority (§1.2). End-user MCP stays compiler-owned.",
    },
};

pub fn summary() struct { total: usize, by_disposition: [10]usize } {
    var by_disposition = [_]usize{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    for (records) |r| by_disposition[@intFromEnum(r.disposition)] += 1;
    return .{ .total = records.len, .by_disposition = by_disposition };
}

pub fn writeCurrencyJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"loop\":[\"observe\",\"classify\",\"compare\",\"reconcile\",\"adopt_or_adapt_or_defer_or_reject\",\"record_rationale\",\"update_architecture\"],\"records\":[", .{SCHEMA_VERSION});
    for (records, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"source\":\"{s}\",\"category\":\"{s}\",\"relevance\":\"{s}\",\"architectural_fit\":\"{s}\",\"api_impact\":\"{s}\",\"performance_impact\":\"{s}\",\"disposition\":\"{s}\",\"rationale\":\"{s}\"}}",
            .{ r.id, r.source, r.category.name(), r.relevance, r.architectural_fit, r.api_impact, r.performance_impact, r.disposition.name(), r.rationale },
        );
    }
    const s = summary();
    try w.print("],\"summary\":{{\"total\":{d},\"already_subsumed\":{d},\"adaptation_candidate\":{d},\"architectural_opportunity\":{d},\"useful_technique\":{d}}}}}", .{
        s.total, s.by_disposition[@intFromEnum(Disposition.already_subsumed)], s.by_disposition[@intFromEnum(Disposition.adaptation_candidate)], s.by_disposition[@intFromEnum(Disposition.architectural_opportunity)], s.by_disposition[@intFromEnum(Disposition.useful_technique)],
    });
}

test "arch_currency: records are well-formed with rationale" {
    try std.testing.expect(records.len >= 4);
    for (records) |r| {
        try std.testing.expect(r.id.len > 0);
        try std.testing.expect(r.source.len > 0);
        try std.testing.expect(r.rationale.len > 0);
    }
}

test "arch_currency: no trend-chasing without convergence rationale (§3.3)" {
    for (records) |r| {
        // Every record must carry rationale regardless of disposition — even
        // rejections and subsumptions need a recorded reason.
        try std.testing.expect(r.rationale.len >= 20);
    }
}

test "arch_currency: JSON parses" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCurrencyJson(&aw.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(usize, records.len), parsed.value.object.get("records").?.array.items.len);
    try std.testing.expect(parsed.value.object.get("loop").? == .array);
}
