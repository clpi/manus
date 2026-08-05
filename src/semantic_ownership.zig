//! Pass 11 WP-10 — semantic subsystem ownership audit.
//!
//! Classifies advanced modules by whether normal compilation depends on them.
const std = @import("std");

pub const SCHEMA_VERSION = "semantic-ownership-v0";

pub const Classification = enum {
    canonical,
    partial,
    tooling_only,
    experimental,
    shadow,
    dead,

    pub fn name(self: Classification) []const u8 {
        return switch (self) {
            .canonical => "CANONICAL",
            .partial => "PARTIAL",
            .tooling_only => "TOOLING_ONLY",
            .experimental => "EXPERIMENTAL",
            .shadow => "SHADOW",
            .dead => "DEAD",
        };
    }
};

pub const ModuleEntry = struct {
    path: []const u8,
    classification: Classification,
    role: []const u8,
    production_consumers: []const u8,
};

/// Static audit (2026-08-04 Pass 11). Update when wiring changes.
pub const modules: []const ModuleEntry = &.{
    .{ .path = "src/lexer.zig", .classification = .canonical, .role = "Tokenization", .production_consumers = "main.zig parse pipeline" },
    .{ .path = "src/parser.zig", .classification = .canonical, .role = "AST construction", .production_consumers = "main.zig" },
    .{ .path = "src/sema.zig", .classification = .canonical, .role = "Type checking + inference", .production_consumers = "main.zig, codegen.zig" },
    .{ .path = "src/codegen.zig", .classification = .canonical, .role = "C emission (primary backend)", .production_consumers = "main.zig compile" },
    .{ .path = "src/native_backend.zig", .classification = .partial, .role = "Direct ARM64 Mach-O (restricted)", .production_consumers = "main.zig when --backend=direct" },
    .{ .path = "src/mono.zig", .classification = .canonical, .role = "Generic monomorphization", .production_consumers = "main.zig compile" },
    .{ .path = "src/arc.zig", .classification = .canonical, .role = "Retain/release lowering", .production_consumers = "main.zig compile" },
    .{ .path = "src/async_lower.zig", .classification = .partial, .role = "Async state machines", .production_consumers = "main.zig when async used" },
    .{ .path = "src/comptime.zig", .classification = .canonical, .role = "Compile-time evaluation", .production_consumers = "codegen.zig, sema.zig" },
    .{ .path = "src/meta_module.zig", .classification = .canonical, .role = "@comp.* registry", .production_consumers = "parser, codegen, sema" },
    .{ .path = "src/meta_codegen.zig", .classification = .canonical, .role = "Combinator code generation", .production_consumers = "codegen.zig" },
    .{ .path = "src/meta_dispatch.zig", .classification = .partial, .role = "Unified combinator dispatch", .production_consumers = "codegen.zig (tier-1 wired)" },
    .{ .path = "src/transform_engine.zig", .classification = .partial, .role = "Transform registry + provenance", .production_consumers = "codegen provenance hooks; not sole dispatch" },
    .{ .path = "src/semantic_graph.zig", .classification = .experimental, .role = "Persistent graph lift", .production_consumers = "duo graph/sim CLI only" },
    .{ .path = "src/realization.zig", .classification = .experimental, .role = "Representation realization plan", .production_consumers = "duo realize CLI; not codegen owner" },
    .{ .path = "src/persistent_semantic_state.zig", .classification = .experimental, .role = "Semantic cache persistence", .production_consumers = "compile cache refresh (optional)" },
    .{ .path = "src/knowledge_snapshot.zig", .classification = .tooling_only, .role = "Knowledge lattice snapshots", .production_consumers = "duo explain CLI" },
    .{ .path = "src/optimization_outcome.zig", .classification = .tooling_only, .role = "Optimization outcome log", .production_consumers = "duo explain CLI" },
    .{ .path = "src/semantic_algebra.zig", .classification = .partial, .role = "Descriptor/shape algebra", .production_consumers = "semantic_graph, codegen hints" },
    .{ .path = "src/autodiff.zig", .classification = .experimental, .role = "Autodiff transform stub", .production_consumers = "none in default compile" },
    .{ .path = "src/build_framework.zig", .classification = .canonical, .role = "build.duo target model", .production_consumers = "duo build/run" },
};

pub fn countByClassification(c: Classification) usize {
    var n: usize = 0;
    for (modules) |m| {
        if (m.classification == c) n += 1;
    }
    return n;
}

pub fn writeJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"modules\":[", .{SCHEMA_VERSION});
    for (modules, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"path\":\"", .{});
        try jsonEscape(w, m.path);
        try w.print("\",\"classification\":\"{s}\",\"role\":\"", .{m.classification.name()});
        try jsonEscape(w, m.role);
        try w.print("\",\"production_consumers\":\"", .{});
        try jsonEscape(w, m.production_consumers);
        try w.print("\"}}", .{});
    }
    try w.print("],\"summary\":{{\"canonical\":{d},\"partial\":{d},\"tooling_only\":{d},\"experimental\":{d},\"shadow\":{d},\"dead\":{d}}}}}", .{
        countByClassification(.canonical),
        countByClassification(.partial),
        countByClassification(.tooling_only),
        countByClassification(.experimental),
        countByClassification(.shadow),
        countByClassification(.dead),
    });
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "semantic_ownership: canonical modules include codegen and sema" {
    var found_codegen = false;
    var found_graph = false;
    for (modules) |m| {
        if (std.mem.eql(u8, m.path, "src/codegen.zig")) {
            try std.testing.expectEqual(Classification.canonical, m.classification);
            found_codegen = true;
        }
        if (std.mem.eql(u8, m.path, "src/semantic_graph.zig")) {
            try std.testing.expectEqual(Classification.experimental, m.classification);
            found_graph = true;
        }
    }
    try std.testing.expect(found_codegen and found_graph);
}
