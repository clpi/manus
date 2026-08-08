//! Pass 27 — proof bundle + performance/metaprogramming evidence catalog.
const std = @import("std");

pub const SCHEMA_VERSION = "pass27-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass27_proof_bundle.md";
pub const INDEX_PATH = "docs/archive/pass27_proof_index.md";

pub const Priority = enum {
    p0,
    p1,
    p2,
    p3,
    p4,
    p5,
    p6,
    p7,
    p8,

    pub fn name(self: Priority) []const u8 {
        return switch (self) {
            .p0 => "P0",
            .p1 => "P1",
            .p2 => "P2",
            .p3 => "P3",
            .p4 => "P4",
            .p5 => "P5",
            .p6 => "P6",
            .p7 => "P7",
            .p8 => "P8",
        };
    }
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: Priority,
    owner: []const u8,
    plan_section: []const u8,
};

/// Performance gaps I.1–I.12 (P27-WS01–WS12).
pub const perf_workstreams: []const Workstream = &.{
    .{ .id = "P27-WS01", .title = "Benchmark harness profile matrix + evidence counters", .status = "partial", .priority = .p0, .owner = "scripts/run_benchmark_proof.sh + pass27_benchmark_evidence", .plan_section = "I.1" },
    .{ .id = "P27-WS02", .title = "Direct backend coverage (ARM64 cursor/LEB128)", .status = "partial", .priority = .p1, .owner = "examples/pass27_proof_matrix_direct.duo + native_barrier_checks", .plan_section = "I.2" },
    .{ .id = "P27-WS03", .title = "Native records + scalar replacement ladder", .status = "open", .priority = .p2, .owner = "realization + pass26 descriptors", .plan_section = "I.3" },
    .{ .id = "P27-WS04", .title = "Return-pack specialization + consumed-position", .status = "open", .priority = .p2, .owner = "tail_result_demand + pass25", .plan_section = "I.4" },
    .{ .id = "P27-WS05", .title = "Closure environment elimination", .status = "open", .priority = .p2, .owner = "realization + escape analysis", .plan_section = "I.5" },
    .{ .id = "P27-WS06", .title = "Metatable devirtualization ladder", .status = "open", .priority = .p2, .owner = "pass23_protocol_registry + sema", .plan_section = "I.6" },
    .{ .id = "P27-WS07", .title = "Bounds-check elimination + proof provenance", .status = "open", .priority = .p1, .owner = "proof_carrying + Ward", .plan_section = "I.7" },
    .{ .id = "P27-WS08", .title = "Pipeline/iterator fusion", .status = "open", .priority = .p8, .owner = "transform_engine", .plan_section = "I.8" },
    .{ .id = "P27-WS09", .title = "Dispatch realization (jump table / superins)", .status = "open", .priority = .p4, .owner = "Ward dispatch + pass11", .plan_section = "I.9" },
    .{ .id = "P27-WS10", .title = "Host/foreign boundary elimination", .status = "open", .priority = .p5, .owner = "pass26_semantic_boundary + foreign_adapter", .plan_section = "I.10" },
    .{ .id = "P27-WS11", .title = "Compile-time / semantic query incrementality", .status = "open", .priority = .p3, .owner = "compiler_perf_measure + semantic_graph", .plan_section = "I.11" },
    .{ .id = "P27-WS12", .title = "Task/channel/continuation elimination", .status = "open", .priority = .p8, .owner = "pass24_execution_model", .plan_section = "I.12" },
};

/// Metaprogramming gaps III.1–III.15 (P27-WS20–WS34).
pub const meta_workstreams: []const Workstream = &.{
    .{ .id = "P27-WS20", .title = "Macro/quote audit + path classification", .status = "partial", .priority = .p3, .owner = "pass27_meta_proof", .plan_section = "III.1" },
    .{ .id = "P27-WS21", .title = "Stable semantic meta-object API", .status = "open", .priority = .p3, .owner = "semantic_graph + pass27_meta_proof", .plan_section = "III.2" },
    .{ .id = "P27-WS22", .title = "Generated entity hygiene + stable IDs", .status = "open", .priority = .p3, .owner = "transform_engine + LSP", .plan_section = "III.3" },
    .{ .id = "P27-WS23", .title = "Transformation composition semantics", .status = "partial", .priority = .p3, .owner = "pass26_transform_meta", .plan_section = "III.4" },
    .{ .id = "P27-WS24", .title = "Semantic transactions (language-facing)", .status = "open", .priority = .p3, .owner = "pass25_projection_model + MCP", .plan_section = "III.5" },
    .{ .id = "P27-WS25", .title = "Bidirectional projection proof", .status = "open", .priority = .p7, .owner = "pass25_projection_model", .plan_section = "III.6" },
    .{ .id = "P27-WS26", .title = "Canonical derivation registration", .status = "open", .priority = .p4, .owner = "pass23 + transform_engine", .plan_section = "III.7" },
    .{ .id = "P27-WS27", .title = "Meta-circular convergence + cycle control", .status = "partial", .priority = .p3, .owner = "pass26_transform_meta", .plan_section = "III.8" },
    .{ .id = "P27-WS28", .title = "Staging semantics operational proof", .status = "open", .priority = .p3, .owner = "sema + pass25", .plan_section = "III.9" },
    .{ .id = "P27-WS29", .title = "Compile-time effects + hermetic mode", .status = "open", .priority = .p3, .owner = "dev_control_plane + MCP", .plan_section = "III.10" },
    .{ .id = "P27-WS30", .title = "Semantic diff breadth (LSP/MCP common output)", .status = "open", .priority = .p3, .owner = "explain_pipeline + LSP", .plan_section = "III.11" },
    .{ .id = "P27-WS31", .title = "Foreign semantic trust on transforms", .status = "partial", .priority = .p5, .owner = "pass26_semantic_boundary", .plan_section = "III.12" },
    .{ .id = "P27-WS32", .title = "Round-trip source emission", .status = "open", .priority = .p7, .owner = "git_preservation + frontends", .plan_section = "III.13" },
    .{ .id = "P27-WS33", .title = "Shared metaprogram Duo + C records", .status = "open", .priority = .p6, .owner = "pass20 + pass26 G20", .plan_section = "III.14" },
    .{ .id = "P27-WS34", .title = "Metaprogram compile-time performance metrics", .status = "open", .priority = .p4, .owner = "compiler_perf_measure", .plan_section = "III.15" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    plan_section: []const u8,
};

pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P27-G01", .title = "P0 honest benchmark profiles + evidence counters schema", .status = "partial", .plan_section = "P0" },
    .{ .id = "P27-G02", .title = "P1 Ward cursor/LEB128/direct ARM64 proof bundle", .status = "partial", .plan_section = "P1" },
    .{ .id = "P27-G03", .title = "P2 sealed record scalar replacement on direct path", .status = "open", .plan_section = "P2" },
    .{ .id = "P27-G04", .title = "P2 return-pack selective realization", .status = "open", .plan_section = "P2" },
    .{ .id = "P27-G05", .title = "P3 meta-object API + generated hygiene + transactions", .status = "open", .plan_section = "P3" },
    .{ .id = "P27-G10", .title = "P4 descriptor-generated Ward decoder flagship", .status = "open", .plan_section = "P4" },
    .{ .id = "P27-G11", .title = "P5 zero-copy C foreign boundary proof", .status = "open", .plan_section = "P5" },
    .{ .id = "P27-G12", .title = "P6 shared cross-language derivation", .status = "open", .plan_section = "P6" },
    .{ .id = "P27-G13", .title = "P7 TypeScript reverse projection (proposal-only)", .status = "open", .plan_section = "P7" },
    .{ .id = "P27-G14", .title = "P8 pipeline/closure fusion proof", .status = "open", .plan_section = "P8" },
};

pub const FlagshipProof = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const flagship_proofs: []const FlagshipProof = &.{
    .{ .id = "P27-PROOF-01", .title = "Descriptor-generated Ward decoder (north star)", .status = "open" },
    .{ .id = "P27-PROOF-02", .title = "Shape ladder (dynamic→guarded→sealed→native)", .status = "open" },
    .{ .id = "P27-PROOF-03", .title = "Selective returns (0/1/2-result call shapes)", .status = "open" },
    .{ .id = "P27-PROOF-04", .title = "Closure/pipeline fusion to single loop", .status = "open" },
    .{ .id = "P27-PROOF-05", .title = "Zero-copy C record + buffer boundary", .status = "open" },
    .{ .id = "P27-PROOF-06", .title = "Static parallel task graph (no heap tasks)", .status = "open" },
};

pub const PriorityCut = struct {
    rank: u8,
    name: []const u8,
    gate_id: []const u8,
};

pub const eight_priorities: []const PriorityCut = &.{
    .{ .rank = 0, .name = "Make evidence honest", .gate_id = "P27-G01" },
    .{ .rank = 1, .name = "Ward byte view + cursor + LEB128 + direct ARM64", .gate_id = "P27-G02" },
    .{ .rank = 2, .name = "Records + return packs on direct path", .gate_id = "P27-G03" },
    .{ .rank = 3, .name = "Semantic metaprogramming primitives", .gate_id = "P27-G05" },
    .{ .rank = 4, .name = "Descriptor-generated Ward decoder flagship", .gate_id = "P27-G10" },
    .{ .rank = 5, .name = "Zero-copy C foreign call", .gate_id = "P27-G11" },
    .{ .rank = 6, .name = "Shared cross-language derivation", .gate_id = "P27-G12" },
    .{ .rank = 7, .name = "Reverse projection proof", .gate_id = "P27-G13" },
    .{ .rank = 8, .name = "Pipeline/closure fusion proof", .gate_id = "P27-G14" },
};

pub fn workstreamCount() usize {
    return perf_workstreams.len + meta_workstreams.len;
}

pub fn writePass27Json(w: *std.Io.Writer, _: std.mem.Allocator) !void {
    try w.print(
        \\"pass27":{{
        \\  "schema_version":"{s}",
        \\  "plan_path":"{s}",
        \\  "index_path":"{s}",
        \\  "workstream_count":{d},
        \\  "perf_workstream_count":{d},
        \\  "meta_workstream_count":{d},
        \\  "completion_gate_count":{d},
        \\  "flagship_proof_count":{d},
        \\  "eight_priorities_count":{d},
        \\  "north_star_proof":"P27-PROOF-01",
        \\  "proof_bundle_stages":8,
        \\  "benchmark_matrix_cells":30
        \\}}
    ,
        .{
            SCHEMA_VERSION,
            PLAN_PATH,
            INDEX_PATH,
            workstreamCount(),
            perf_workstreams.len,
            meta_workstreams.len,
            completion_gates.len,
            flagship_proofs.len,
            eight_priorities.len,
        },
    );
}

test "pass27_catalog: workstreams + gates + priorities" {
    try std.testing.expect(perf_workstreams.len == 12);
    try std.testing.expect(meta_workstreams.len == 15);
    try std.testing.expect(workstreamCount() == 27);
    try std.testing.expect(completion_gates.len == 10);
    try std.testing.expect(flagship_proofs.len == 6);
    try std.testing.expect(eight_priorities.len == 9);
}
