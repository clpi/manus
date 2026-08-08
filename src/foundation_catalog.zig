//! Self-hosting foundation — canonical catalog (umbrella over Pass 4/14/16/22/26/27).
//!
//! Canonical spec: `docs/plans/duo_self_hosting_foundation.md`
//! Operational projection: `docs/plans/self_hosting_foundation.md`
//! Gate: `zig build foundation-gate`
const std = @import("std");
const ir_layer_registry = @import("ir_layer_registry.zig");

pub const SCHEMA_VERSION = "foundation-catalog-v0";
pub const CANONICAL_SPEC_PATH = "docs/archive/duo_self_hosting_foundation.md";
pub const PLAN_PATH = "docs/archive/self_hosting_foundation.md";

pub const BootstrapStage = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    owner: []const u8,
    spec_section: []const u8,
};

pub const bootstrap_stages: []const BootstrapStage = &.{
    .{ .id = "S0", .title = "Trusted bootstrap (Zig host)", .status = "current", .owner = "src/*.zig + build.zig", .spec_section = "§2 S0" },
    .{ .id = "S1", .title = "First Duo compiler", .status = "partial", .owner = "pass16_catalog + lib/std/compiler/*", .spec_section = "§2 S1" },
    .{ .id = "S2", .title = "Self-hosted compiler (S1 compiles itself)", .status = "open", .owner = "bootstrap_dag.zig", .spec_section = "§2 S2" },
    .{ .id = "S3", .title = "Reproducibility closure (S2 recompiles itself)", .status = "open", .owner = "bootstrap_dag.zig", .spec_section = "§2 S3" },
};

pub const ForeignClass = struct {
    id: []const u8,
    title: []const u8,
    spec_section: []const u8,
    repo_anchor: []const u8,
};

pub const foreign_classes: []const ForeignClass = &.{
    .{ .id = "FC-A", .title = "Bootstrap (temporary authority)", .spec_section = "§1.1 A", .repo_anchor = "dependency_manifest.Class.bootstrap" },
    .{ .id = "FC-B", .title = "Foreign boundary (ABI/OS/ecosystem)", .spec_section = "§1.1 B", .repo_anchor = "dependency_manifest.Class.platform_interface" },
    .{ .id = "FC-C", .title = "Differential reference (non-authoritative)", .spec_section = "§1.1 C", .repo_anchor = "removal_ledger retain_oracle entries" },
    .{ .id = "FC-D", .title = "Disposable utilities", .spec_section = "§1.1 D", .repo_anchor = "removal_ledger + scripts/*" },
};

pub const SemanticNodeKind = struct {
    name: []const u8,
};

/// §3.1 unified node types (registry; graph lift expands over time).
pub const semantic_node_kinds: []const SemanticNodeKind = &.{
    .{ .name = "source_unit" },
    .{ .name = "syntax_entity" },
    .{ .name = "declaration" },
    .{ .name = "binding" },
    .{ .name = "descriptor" },
    .{ .name = "shape" },
    .{ .name = "field" },
    .{ .name = "function" },
    .{ .name = "closure" },
    .{ .name = "capture" },
    .{ .name = "call" },
    .{ .name = "parameter" },
    .{ .name = "return_pack" },
    .{ .name = "value" },
    .{ .name = "variant" },
    .{ .name = "stage" },
    .{ .name = "effect" },
    .{ .name = "contract" },
    .{ .name = "assumption" },
    .{ .name = "guard" },
    .{ .name = "transformation" },
    .{ .name = "representation_variable" },
    .{ .name = "realization_candidate" },
    .{ .name = "target_capability" },
    .{ .name = "foreign_entity" },
    .{ .name = "generated_entity" },
    .{ .name = "evidence" },
    .{ .name = "machine_artifact" },
};

pub const SemanticEdgeKind = struct {
    name: []const u8,
};

/// §3.2 unified edge types.
pub const semantic_edge_kinds: []const SemanticEdgeKind = &.{
    .{ .name = "defines" },
    .{ .name = "binds" },
    .{ .name = "references" },
    .{ .name = "contains" },
    .{ .name = "calls" },
    .{ .name = "captures" },
    .{ .name = "returns" },
    .{ .name = "consumes" },
    .{ .name = "refines" },
    .{ .name = "specializes" },
    .{ .name = "transforms" },
    .{ .name = "guards" },
    .{ .name = "assumes" },
    .{ .name = "invalidates" },
    .{ .name = "depends_on" },
    .{ .name = "aliases" },
    .{ .name = "mutates" },
    .{ .name = "realizes_as" },
    .{ .name = "represented_by" },
    .{ .name = "executes_on" },
    .{ .name = "generated_from" },
    .{ .name = "validates" },
    .{ .name = "proves" },
    .{ .name = "falls_back_to" },
};

pub const IrLayer = struct {
    id: []const u8,
    title: []const u8,
    spec_section: []const u8,
    status: []const u8,
    owner: []const u8,
    verifier_step: ?[]const u8,
};

/// §4.1–4.9 IR layer registry (verifier steps wired via `ir_layer_registry.zig`).
pub const ir_layers: []const IrLayer = &.{
    .{ .id = "IR-01", .title = "Syntax graph", .spec_section = "§4.1", .status = "partial", .owner = "parser.zig + ast.zig", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-01") },
    .{ .id = "IR-02", .title = "Semantic graph", .spec_section = "§4.2", .status = "partial", .owner = "semantic_graph.zig + sema.zig", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-02") },
    .{ .id = "IR-03", .title = "Executable region graph", .spec_section = "§4.3", .status = "open", .owner = "transform_engine.zig", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-03") },
    .{ .id = "IR-04", .title = "Specialized graph", .spec_section = "§4.4", .status = "partial", .owner = "realization + pass27_benchmark_evidence", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-04") },
    .{ .id = "IR-05", .title = "Representation IR", .spec_section = "§4.5", .status = "partial", .owner = "pass26_descriptor_identity.zig", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-05") },
    .{ .id = "IR-06", .title = "SSA / scheduled IR", .spec_section = "§4.6", .status = "open", .owner = "future", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-06") },
    .{ .id = "IR-07", .title = "Low-level IR", .spec_section = "§4.7", .status = "partial", .owner = "native_backend.zig", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-07") },
    .{ .id = "IR-08", .title = "Machine IR", .spec_section = "§4.8", .status = "partial", .owner = "native_backend.zig + Ward", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-08") },
    .{ .id = "IR-09", .title = "Artifact IR", .spec_section = "§4.9", .status = "partial", .owner = "native_backend.zig (Mach-O)", .verifier_step = ir_layer_registry.verifierStepForLayer("IR-09") },
};

pub const IrInvariant = struct {
    id: []const u8,
    law: []const u8,
};

/// §5 global IR laws.
pub const ir_invariants: []const IrInvariant = &.{
    .{ .id = "INV-01", .law = "Identity preserved across all lowering" },
    .{ .id = "INV-02", .law = "Knowledge is monotonic (no silent loss)" },
    .{ .id = "INV-03", .law = "All loss must be explicit" },
    .{ .id = "INV-04", .law = "Boxing/allocation is explicit IR" },
    .{ .id = "INV-05", .law = "Return packs are first-class" },
    .{ .id = "INV-06", .law = "Calls retain full metadata" },
    .{ .id = "INV-07", .law = "Every transformation produces evidence" },
    .{ .id = "INV-08", .law = "Machine code is a projection, not truth" },
};

pub const FoundationGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    spec_section: []const u8,
    owner: []const u8,
    build_step: ?[]const u8,
};

/// §11 foundation completion gates (staged).
pub const foundation_gates: []const FoundationGate = &.{
    .{ .id = "F-G01", .title = "Semantic graph + stable IDs exist", .status = "partial", .spec_section = "§11", .owner = "semantic_graph.zig", .build_step = null },
    .{ .id = "F-G02", .title = "Syntax→semantic lowering with provenance", .status = "partial", .spec_section = "§11", .owner = "parser.zig + sema.zig", .build_step = null },
    .{ .id = "F-G03", .title = "Explicit specialization (no silent boxing)", .status = "partial", .spec_section = "§11", .owner = "pass27_benchmark_evidence + native_barrier_checks", .build_step = "bench-proof-gate" },
    .{ .id = "F-G04", .title = "SSA→LIR→MIR one native target", .status = "partial", .spec_section = "§11", .owner = "native_backend.zig", .build_step = "pass27-gate" },
    .{ .id = "F-G05", .title = "Artifact IR (Mach-O emission + proof)", .status = "partial", .spec_section = "§11", .owner = "native_backend.zig", .build_step = null },
    .{ .id = "F-G06", .title = "S1 compiler subset implemented in Duo", .status = "open", .spec_section = "§11", .owner = "pass16_catalog P16-M1", .build_step = "pass16-gate" },
    .{ .id = "F-G07", .title = "S2 self-host cycle", .status = "open", .spec_section = "§11", .owner = "bootstrap_dag.zig", .build_step = null },
    .{ .id = "F-G08", .title = "Foreign elimination ledger complete", .status = "partial", .spec_section = "§9", .owner = "removal_ledger.zig + dependency_manifest.zig", .build_step = null },
    .{ .id = "F-G09", .title = "MCP/LSP/Ward share graph view", .status = "open", .spec_section = "§11", .owner = "duo-lsp + duo-mcp + Ward", .build_step = null },
    .{ .id = "F-G10", .title = "No permanent foreign code without deletion gate", .status = "partial", .spec_section = "§9", .owner = "dependency_manifest.zig", .build_step = null },
};

pub const ExecutionPhase = struct {
    phase: u8,
    title: []const u8,
    status: []const u8,
    owner: []const u8,
};

/// §7 self-hosting execution plan (phases 1–10).
pub const execution_phases: []const ExecutionPhase = &.{
    .{ .phase = 1, .title = "Substrate (Byte/Slice/Cursor/IDs/arenas)", .status = "partial", .owner = "lib/std/compiler/source.duo + pass16_source_cursor_proof.duo" },
    .{ .phase = 2, .title = "Lexer", .status = "partial", .owner = "lib/std/compiler/lexer.duo + pass12 M1" },
    .{ .phase = 3, .title = "Parser + syntax graph", .status = "open", .owner = "pass16 P16-WS5/WS6" },
    .{ .phase = 4, .title = "Semantic graph", .status = "partial", .owner = "semantic_graph.zig" },
    .{ .phase = 5, .title = "HIR", .status = "open", .owner = "pass16 P16-WS9+" },
    .{ .phase = 6, .title = "Compile-time system", .status = "partial", .owner = "comptime + descriptors" },
    .{ .phase = 7, .title = "Representation + SSA", .status = "open", .owner = "pass16 P16-WS15/WS16" },
    .{ .phase = 8, .title = "Bootstrap backend (S0 boundary or C)", .status = "partial", .owner = "codegen.zig + main.zig" },
    .{ .phase = 9, .title = "Native backend (AArch64 + Mach-O)", .status = "partial", .owner = "native_backend.zig + pass27 direct proofs" },
    .{ .phase = 10, .title = "Object + linker", .status = "partial", .owner = "native_backend.zig Mach-O" },
};

pub const FreezeDomain = struct {
    domain: []const u8,
    owner: []const u8,
};

/// §6 minimal stable core domains.
pub const foundation_freeze_domains: []const FreezeDomain = &.{
    .{ .domain = "syntax_core", .owner = "parser.zig + GRAMMAR_SPEC.md" },
    .{ .domain = "semantic_core", .owner = "semantic_graph.zig + pass26" },
    .{ .domain = "memory_substrate", .owner = "lib/std/compiler/source.duo" },
    .{ .domain = "compiler_services", .owner = "term.zig + explain_pipeline + sim" },
};

pub const ImmediateWorkstream = struct {
    id: []const u8,
    title: []const u8,
    track: []const u8,
    owner: []const u8,
};

/// §10 immediate work program (ordered).
pub const immediate_workstreams: []const ImmediateWorkstream = &.{
    .{ .id = "F-WS01", .title = "Semantic ID durability + graph storage API", .track = "foundation", .owner = "semantic_graph.zig" },
    .{ .id = "F-WS02", .title = "Syntax↔semantic mapping with provenance", .track = "foundation", .owner = "parser.zig + sema.zig" },
    .{ .id = "F-WS03", .title = "Return-pack + effect nodes as graph entities", .track = "foundation", .owner = "tail_result_demand + sema" },
    .{ .id = "F-WS04", .title = "IR schema registry + verifier stubs (IR-01..IR-09)", .track = "ir", .owner = "ir_layer_registry.zig" },
    .{ .id = "F-WS05", .title = "Lowering chain traces + evidence nodes", .track = "ir", .owner = "proof_carrying.zig + pass27" },
    .{ .id = "F-WS06", .title = "Phase 1 substrate in Duo", .track = "self_hosting", .owner = "lib/std/compiler/*" },
    .{ .id = "F-WS07", .title = "Phase 2 lexer differential vs S0", .track = "self_hosting", .owner = "pass12_m1_diff.duo" },
    .{ .id = "F-WS08", .title = "S1 build via S0 backend boundary", .track = "self_hosting", .owner = "bootstrap_dag.zig" },
    .{ .id = "F-WS09", .title = "Extend removal_ledger to full src/ inventory", .track = "migration", .owner = "removal_ledger.zig" },
    .{ .id = "F-WS10", .title = "Freeze S0 architecture policy + CI enforcement", .track = "migration", .owner = "dependency_manifest.zig" },
};

pub const LedgerAnchor = struct {
    path: []const u8,
    role: []const u8,
};

pub const ledger_anchors: []const LedgerAnchor = &.{
    .{ .path = "src/dependency_manifest.zig", .role = "foreign dependency classification + removal gates" },
    .{ .path = "src/removal_ledger.zig", .role = "host code retirement eligibility" },
    .{ .path = "src/bootstrap_dag.zig", .role = "S0→S3 bootstrap orchestration" },
    .{ .path = "src/selfhosting_matrix.zig", .role = "self-hosting parity matrix" },
};

pub fn bootstrapStageCount() usize {
    return bootstrap_stages.len;
}

pub fn irLayerCount() usize {
    return ir_layers.len;
}

pub fn foundationGateCount() usize {
    return foundation_gates.len;
}

pub fn writeFoundationJson(w: *std.Io.Writer, _: std.mem.Allocator) !void {
    try w.print(
        \\"foundation":{{
        \\  "schema_version":"{s}",
        \\  "plan_path":"{s}",
        \\  "bootstrap_stage_count":{d},
        \\  "foreign_class_count":{d},
        \\  "semantic_node_kind_count":{d},
        \\  "semantic_edge_kind_count":{d},
        \\  "ir_layer_count":{d},
        \\  "ir_invariant_count":{d},
        \\  "foundation_gate_count":{d},
        \\  "execution_phase_count":{d},
        \\  "immediate_workstream_count":{d},
        \\  "current_bootstrap_stage":"S0",
        \\  "foundation_completion_requires":"F-G01..F-G10"
        \\}}
    ,
        .{
            SCHEMA_VERSION,
            PLAN_PATH,
            bootstrap_stages.len,
            foreign_classes.len,
            semantic_node_kinds.len,
            semantic_edge_kinds.len,
            ir_layers.len,
            ir_invariants.len,
            foundation_gates.len,
            execution_phases.len,
            immediate_workstreams.len,
        },
    );
}

test "foundation_catalog: registries sized" {
    try std.testing.expect(bootstrap_stages.len == 4);
    try std.testing.expect(foreign_classes.len == 4);
    try std.testing.expect(semantic_node_kinds.len == 28);
    try std.testing.expect(semantic_edge_kinds.len == 24);
    try std.testing.expect(ir_layers.len == 9);
    try std.testing.expect(ir_invariants.len == 8);
    try std.testing.expect(foundation_gates.len == 10);
    try std.testing.expect(execution_phases.len == 10);
    try std.testing.expect(immediate_workstreams.len == 10);
    try std.testing.expect(std.mem.eql(u8, bootstrap_stages[0].id, "S0"));
    try std.testing.expect(std.mem.eql(u8, foundation_gates[9].id, "F-G10"));
    try std.testing.expect(std.mem.eql(u8, ir_layers[8].id, "IR-09"));
}
