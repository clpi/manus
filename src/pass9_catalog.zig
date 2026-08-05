//! Pass 9 — Ward readiness catalog export (`duo catalog` → `pass9`).
//!
//! Detailed capability ↔ subsystem matrix: `src/ward_readiness.zig` (canonical owner).
const std = @import("std");
const pass8_catalog = @import("pass8_catalog.zig");
const ward_readiness = @import("ward_readiness.zig");
const wasm_semantic = @import("wasm_semantic.zig");
const wasm_semantic_gen = @import("wasm_semantic_gen.zig");

pub const SCHEMA_VERSION = "pass9-catalog-v0";

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass9_ward_readiness.md";
    pub const pass8 = pass8_catalog.CatalogPaths.plan;
    pub const ward_repo = "~/x/ward";
    pub const wart_repo = "~/x/wart";
    pub const matrix_owner = "src/ward_readiness.zig";
    pub const wasm_semantic = "src/wasm_semantic.zig";
    pub const wasm_semantic_gen = "src/wasm_semantic_gen.zig";
    pub const wasm_instruction_std = "lib/std/wasm/instruction.duo";
    pub const wasm_decode_std = "lib/std/wasm/decode.duo";
    pub const wasm_opcode_lookup = "lib/std/wasm/opcode_lookup.duo";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    area: []const u8,
};

pub const CapabilityLadder = struct {
    level: u8,
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const milestones: []const struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
} = &.{
    .{ .id = "P9-M0", .title = "Readiness matrix + repository truth (duo catalog pass9)", .status = "partial" },
    .{ .id = "P9-M1", .title = "Descriptor-generated LEB128 + instruction decoder (bounded MVP subset)", .status = "partial" },
    .{ .id = "P9-M2", .title = "Validator metadata + differential conformance harness", .status = "partial" },
    .{ .id = "P9-M3", .title = "Native byte cursor substrate (WARD_READY)", .status = "open" },
    .{ .id = "P9-M4", .title = "Dispatch realization candidates + explainable selection", .status = "open" },
    .{ .id = "P9-M5", .title = "Baseline interpreter design gate (Level 4)", .status = "open" },
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P9-WS1", .title = "Wart and Ward truth audit", .status = "partial", .priority = 1, .area = "audit" },
    .{ .id = "P9-WS2", .title = "Ward readiness registry", .status = "partial", .priority = 2, .area = "registry" },
    .{ .id = "P9-WS3", .title = "Native bytes and cursor substrate", .status = "partial", .priority = 3, .area = "substrate" },
    .{ .id = "P9-WS4", .title = "Wasm semantic descriptor", .status = "partial", .priority = 4, .area = "semantics" },
    .{ .id = "P9-WS5", .title = "Compile-time generator (decoder/validator)", .status = "partial", .priority = 5, .area = "generation" },
    .{ .id = "P9-WS6", .title = "Native decoder lowering", .status = "partial", .priority = 6, .area = "codegen" },
    .{ .id = "P9-WS7", .title = "Differential and fuzz harness", .status = "partial", .priority = 7, .area = "validation" },
    .{ .id = "P9-WS8", .title = "Performance and complexity harness", .status = "open", .priority = 8, .area = "benchmark" },
    .{ .id = "P9-WS9", .title = "Semantic tooling (LSP + end-user MCP)", .status = "open", .priority = 9, .area = "tooling" },
    .{ .id = "P9-WS10", .title = "Development MCP integration", .status = "open", .priority = 10, .area = "coordination" },
    .{ .id = "P9-WS11", .title = "Baseline interpreter design gate", .status = "open", .priority = 11, .area = "interpreter" },
};

pub const capability_ladder: []const CapabilityLadder = &.{
    .{ .level = 0, .id = "L0", .title = "Repository and benchmark truth", .status = "partial" },
    .{ .level = 1, .id = "L1", .title = "Duo-native systems substrate", .status = "open" },
    .{ .level = 2, .id = "L2", .title = "Wasm semantic model", .status = "partial" },
    .{ .level = 3, .id = "L3", .title = "Decoder and validator proof", .status = "open" },
    .{ .level = 4, .id = "L4", .title = "Baseline interpreter", .status = "open" },
    .{ .level = 5, .id = "L5", .title = "Specialization-aware interpreter", .status = "open" },
    .{ .level = 6, .id = "L6", .title = "Baseline native compiler or JIT", .status = "open" },
    .{ .level = 7, .id = "L7", .title = "Optimizing compiler", .status = "open" },
    .{ .level = 8, .id = "L8", .title = "Persistent and adaptive Ward", .status = "open" },
};

pub const AuditSnapshot = struct {
    ward_wasm_loc: u32,
    ward_hot_path_violation: []const u8,
    wart_loc_claimed: []const u8,
    wart_loc_verified: bool,
};

pub const audit_snapshot: AuditSnapshot = .{
    .ward_wasm_loc = 3554,
    .ward_hot_path_violation = "ward/src/wasm/module.duo mr_mod_read_* uses @c.emit with lua_Value",
    .wart_loc_claimed = "~1300000",
    .wart_loc_verified = false,
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writePass9Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass9":{{"mission":"Ward readiness + vertical proof + runtime supremacy","schema":"{s}","matrix_schema":"{s}","catalogs":{{
    , .{ SCHEMA_VERSION, ward_readiness.SCHEMA_VERSION });
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"pass8\":\"", .{});
    try jsonEscape(w, CatalogPaths.pass8);
    try w.print("\",\"matrix_owner\":\"", .{});
    try jsonEscape(w, CatalogPaths.matrix_owner);
    try w.print("\",\"ward_repo\":\"", .{});
    try jsonEscape(w, CatalogPaths.ward_repo);
    try w.print("\",\"wart_repo\":\"", .{});
    try jsonEscape(w, CatalogPaths.wart_repo);
    try w.print("\",\"wasm_semantic_owner\":\"", .{});
    try jsonEscape(w, CatalogPaths.wasm_semantic);
    try w.print("\",\"wasm_semantic_gen_owner\":\"", .{});
    try jsonEscape(w, CatalogPaths.wasm_semantic_gen);
    try w.print("\",\"wasm_instruction_std\":\"", .{});
    try jsonEscape(w, CatalogPaths.wasm_instruction_std);
    try w.print("\",\"wasm_decode_std\":\"", .{});
    try jsonEscape(w, CatalogPaths.wasm_decode_std);
    try w.print("\",\"wasm_opcode_lookup\":\"", .{});
    try jsonEscape(w, CatalogPaths.wasm_opcode_lookup);
    try w.print("\"}},\"governing_principles\":[\"ward-is-consumer-not-fork\",\"duo-readiness-precedes-ward\",\"beat-wart-through-leverage\",\"no-hidden-delegation\"],", .{});

    try w.print("\"milestones\":[", .{});
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\"}}", .{m.status});
    }
    try w.print("],\"workstreams\":[", .{});
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"area\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.area,
        });
    }
    try w.print("],\"capability_ladder\":[", .{});
    for (capability_ladder, 0..) |cl, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"level\":{d},\"id\":\"{s}\",\"title\":\"", .{ cl.level, cl.id });
        try jsonEscape(w, cl.title);
        try w.print("\",\"status\":\"{s}\"}}", .{cl.status});
    }
    try w.print("],\"duo_capabilities\":", .{});
    try ward_readiness.writeCapabilitiesJson(w);
    try w.print(",\"ward_subsystems\":", .{});
    try ward_readiness.writeSubsystemsJson(w);
    try w.print(",\"repository_truth\":", .{});
    try ward_readiness.writeRepositoryTruthJson(w);
    try w.print(",\"readiness_summary\":{{\"duo_capabilities\":{{\"ward_ready\":{d},\"proven_in_ward\":{d},\"partial\":{d}}},\"ward_subsystems\":{{\"ward_ready\":{d},\"proven_in_ward\":{d},\"partial\":{d}}}}},", .{
        ward_readiness.countByStatus(.capabilities, .ward_ready),
        ward_readiness.countByStatus(.capabilities, .proven_in_ward),
        ward_readiness.countByStatus(.capabilities, .partial),
        ward_readiness.countByStatus(.subsystems, .ward_ready),
        ward_readiness.countByStatus(.subsystems, .proven_in_ward),
        ward_readiness.countByStatus(.subsystems, .partial),
    });
    try w.print("\"audit_snapshot\":{{\"ward_wasm_loc\":{d},\"ward_hot_path_violation\":\"", .{audit_snapshot.ward_wasm_loc});
    try jsonEscape(w, audit_snapshot.ward_hot_path_violation);
    try w.print("\",\"wart_loc_claimed\":\"", .{});
    try jsonEscape(w, audit_snapshot.wart_loc_claimed);
    try w.print("\",\"wart_loc_verified\":", .{});
    try w.print("{s}", .{if (audit_snapshot.wart_loc_verified) "true" else "false"});
    try w.print("}},\"wasm_semantic\":", .{});
    try wasm_semantic.writeCatalogJson(w);
    try w.print(",\"wasm_semantic_gen\":", .{});
    try wasm_semantic_gen.writeCatalogJson(w);
    try w.print(",\"first_kernel\":\"descriptor-generated Wasm instruction decode + validate (P9-M1)\",\"invariants\":[\"ward-not-architectural-fork\",\"no-duplicated-instruction-facts\",\"no-hidden-wart-embedding\",\"profile-not-guarantee\",\"deterministic-realization\"]}}",
        .{},
    );
}

test "pass9_catalog: writePass9Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass9Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass9\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P9-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "duo_capabilities") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ward.sub.leb128") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "wasm.i32.add") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"wasm_semantic\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"wasm_semantic_gen\"") != null);
}

test "pass9_catalog: no subsystem ward_ready yet" {
    for (ward_readiness.ward_subsystems) |ws| {
        try std.testing.expect(ws.status != .ward_ready);
        try std.testing.expect(ws.status != .proven_in_ward);
    }
}
