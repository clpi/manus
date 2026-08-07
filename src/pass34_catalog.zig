//! Pass 34 — HPLS Frontier barrier catalog (Phase 0: records only).
//!
//! Canonical spec: docs/plans/duo_hpls_frontier.md
//! Operational: docs/plans/pass34_hpls_frontier.md
//! Human index: docs/catalogs/hpls_barriers.md
const std = @import("std");
pub const SCHEMA_VERSION = "pass34-hpls-catalog-v1";
pub const PLAN_PATH = "docs/plans/duo_hpls_frontier.md";
pub const CANONICAL_PATH = "docs/plans/duo_hpls_frontier.md";
pub const INDEX_PATH = "docs/catalogs/hpls_barriers.md";
/// The incumbent T8 supersedes: a regex-over-text idiom linter. Per the
/// convergence rule, T8 closes only when this implementation is deleted.
pub const TEXT_IDIOM_GATE_PATH = "scripts/duo_idiom_gate.duo";

pub const BarrierClass = enum {
    boxing,
    allocation,
    dispatch,
    representation,
    abi,
    helper,
    fallback,
    stage,
    process,
    convergence,
};

pub const ImpactLevel = enum { low, medium, high, dominant };
pub const FrequencyLevel = enum { rare, common, pervasive };
pub const EvidenceKind = enum { measured, estimated };
pub const BarrierStatus = enum {
    discovered,
    specified,
    implemented,
    validated,
    adopted,
    wont_fix,
    superseded,
};

pub const BarrierTier = enum {
    convergence,
    elephant,
    lever,
    unicorn,
    trap,
};

pub const RankInputs = struct {
    impact: u8,
    frequency: u8,
    leverage: u8,
    ward: u8,
    selfhost: u8,
    risk: u8,
    redesign: u8,
    overlap: u8,
};

pub const ImpactProfile = struct {
    runtime: ImpactLevel,
    frequency: FrequencyLevel,
    evidence: EvidenceKind,
};

pub const PrerequisiteBridge = struct {
    id: []const u8,
    bridge: []const u8,
};

pub const BarrierRecord = struct {
    id: []const u8,
    class: BarrierClass,
    file: []const u8,
    symbol: []const u8,
    semantic_path: []const u8,
    cause: []const u8,
    semantically_required: bool,
    prerequisites: []const []const u8,
    prerequisite_bridges: []const PrerequisiteBridge,
    impact: ImpactProfile,
    backends: []const []const u8,
    tests: []const []const u8,
    bounded_fix: []const u8,
    witness: []const u8,
    status: BarrierStatus,
    rank_inputs: RankInputs,
};

pub const RankedEntry = struct { rank: u8, id: []const u8, rationale: []const u8 };
pub const CanonicalHomeMapping = struct { proposal: []const u8, home: []const u8 };

/// §13 agent idiom enforcement. Each mechanism is a projection of existing
/// barrier records, never a new subsystem: idiomatic Duo is defined as code
/// whose manifest is clean and whose facts are provable, so enforcement is
/// mechanical rather than a style guide over text.
pub const AgentIdiomProjection = struct {
    mechanism: []const u8,
    homes: []const []const u8,
    enforcement: []const u8,
};

pub const DependencyEdge = struct { from_id: []const u8, to_ids: []const []const u8, bridge: []const u8 };
pub const ExecutionPhase = struct { phase: u8, id: []const u8, title: []const u8, exit_gate: []const u8 };

const all = &[_][]const u8{"all"};
pub const convergences: []const BarrierRecord = &.{
    .{ .id = "C1", .class = .convergence, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "semantic entity to physical location", .cause = "Seven consumers grow separate location tables", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 5, .ward = 4, .selfhost = 3, .risk = 3, .redesign = 4, .overlap = 5 } }, .{ .id = "C2", .class = .convergence, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "descriptor identity", .cause = "Reflection FFI variants use separate identity systems", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 4, .selfhost = 4, .risk = 3, .redesign = 4, .overlap = 3 } }, .{ .id = "C3", .class = .convergence, .file = "semantic_graph.zig", .symbol = "SemanticGraph", .semantic_path = "program model for all tools", .cause = "Tools maintain private program models", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .dominant, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 5, .selfhost = 5, .risk = 4, .redesign = 5, .overlap = 2 } }, .{ .id = "C4", .class = .convergence, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "representation selection", .cause = "Backend decisions outside canonical representation selection", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .dominant, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 5, .selfhost = 4, .risk = 4, .redesign = 5, .overlap = 3 } }, .{ .id = "C5", .class = .convergence, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "graph + witnesses + provenance queries", .cause = "Explain history replay diff as separate systems", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "witness store accumulates from first L-tier fix" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 5, .ward = 4, .selfhost = 5, .risk = 3, .redesign = 4, .overlap = 2 } },
};

pub const elephants: []const BarrierRecord = &.{
    .{ .id = "E1", .class = .allocation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "automatic memory management", .cause = "No GC contract", .semantically_required = true, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .dominant, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 4, .selfhost = 4, .risk = 4, .redesign = 5, .overlap = 2 } }, .{ .id = "E2", .class = .stage, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "guarded specialization descent", .cause = "Deopt unspecified", .semantically_required = true, .prerequisites = &[_][]const u8{"C1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "C1", .bridge = "proofs-over-guards subset ships without frame maps" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 5, .ward = 4, .selfhost = 3, .risk = 5, .redesign = 5, .overlap = 3 } }, .{ .id = "E3", .class = .abi, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "pcall/error unwind", .cause = "Unwind undecided", .semantically_required = true, .prerequisites = &[_][]const u8{"E9"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E9", .bridge = "out-of-band error flag convention" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 4, .ward = 3, .selfhost = 3, .risk = 5, .redesign = 5, .overlap = 4 } }, .{ .id = "E4", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "compile-time cost", .cause = "Compile time unpriced", .semantically_required = false, .prerequisites = &[_][]const u8{ "U10", "E10", "L13" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "U10", .bridge = "compile budget in planner" }, .{ .id = "E10", .bridge = "invalidation as payment mechanism" }, .{ .id = "L13", .bridge = "call-shape caching as discount" } }, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 2, .selfhost = 5, .risk = 3, .redesign = 4, .overlap = 3 } }, .{ .id = "E5", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "C boundary fact loss", .cause = "No fact-loss ledger", .semantically_required = false, .prerequisites = &[_][]const u8{ "L6", "E9" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "L6", .bridge = "fact-loss ledger manifest column" }, .{ .id = "E9", .bridge = "ABI v0 enables mixed binaries" } }, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 5, .leverage = 4, .ward = 5, .selfhost = 4, .risk = 2, .redesign = 3, .overlap = 4 } }, .{ .id = "E6", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "concurrency memory model", .cause = "No memory model", .semantically_required = true, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .medium, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 2, .leverage = 4, .ward = 2, .selfhost = 2, .risk = 2, .redesign = 3, .overlap = 2 } }, .{ .id = "E7", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "debug identity at specialization", .cause = "Scalar-replaced values invisible", .semantically_required = false, .prerequisites = &[_][]const u8{"C1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "C1", .bridge = "same artifact as E2 frame maps" }}, .impact = .{ .runtime = .low, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 3, .leverage = 4, .ward = 3, .selfhost = 3, .risk = 4, .redesign = 4, .overlap = 5 } }, .{ .id = "E8", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "alias model", .cause = "No canonical alias contract", .semantically_required = true, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .dominant, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 5, .selfhost = 4, .risk = 4, .redesign = 5, .overlap = 3 } }, .{ .id = "E9", .class = .abi, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "ABI ownership", .cause = "ABI decisions smeared across subsystems", .semantically_required = true, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 5, .ward = 4, .selfhost = 4, .risk = 3, .redesign = 4, .overlap = 4 } }, .{ .id = "E10", .class = .process, .file = "semantic_graph.zig", .symbol = "SemanticGraph", .semantic_path = "incremental semantic invalidation", .cause = "Invalidation is a footnote not a subsystem", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "NONE", .witness = "NONE", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 5, .ward = 3, .selfhost = 5, .risk = 3, .redesign = 4, .overlap = 3 } },
};

pub const levers: []const BarrierRecord = &.{
    .{ .id = "L1", .class = .dispatch, .file = "sema.zig", .symbol = "module_sealed", .semantic_path = "req and cross-module calls", .cause = "Modules mutable after load", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{ "pass34_gate", "examples/l1_module_sealed_proof.duo" }, .bounded_fix = "module_sealed(m) lattice fact", .witness = "@comp.why module_sealed output", .status = .specified, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 5, .selfhost = 5, .risk = 1, .redesign = 2, .overlap = 2 } }, .{ .id = "L2", .class = .fallback, .file = "codegen.zig", .symbol = "interned_fallback_field_id / duo_fallback_get_*", .semantic_path = "fallback field access", .cause = "String hash in fallback", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .medium, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{ "pass34_gate", "examples/l2_fallback_field_manifest_proof.duo" }, .bounded_fix = "interned field IDs in generic helper", .witness = "manifest fallback field-id counts", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 5, .leverage = 3, .ward = 3, .selfhost = 3, .risk = 2, .redesign = 2, .overlap = 2 } }, .{ .id = "L3", .class = .representation, .file = "UNLOCATED", .symbol = "proven_non_nil", .semantic_path = "value,err idiom", .cause = "No proven_non_nil fact", .semantically_required = false, .prerequisites = &[_][]const u8{"E3"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E3", .bridge = "lattice fact lands before full E3" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "proven_non_nil lattice entry", .witness = "@comp.why proven_non_nil fact", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 4, .ward = 4, .selfhost = 3, .risk = 2, .redesign = 2, .overlap = 3 } }, .{ .id = "L4", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "string parsing/decoding", .cause = "Missing string ladder", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "string representation ladder", .witness = "manifest string representation tags", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 5, .leverage = 4, .ward = 5, .selfhost = 2, .risk = 3, .redesign = 3, .overlap = 3 } }, .{ .id = "L5", .class = .representation, .file = "UNLOCATED", .symbol = "dense_array", .semantic_path = "ipairs and numeric loops", .cause = "No dense_array fact", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "dense_array(t,n) shape fact", .witness = "@comp.why dense_array fact", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 3, .ward = 4, .selfhost = 2, .risk = 2, .redesign = 2, .overlap = 2 } }, .{ .id = "L6", .class = .process, .file = "pass34_representation_manifest.zig", .symbol = "RepresentationManifest", .semantic_path = "manifest verifiability", .cause = "No diffable manifest", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .medium, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{ "pass34_gate", "bench-proof-gate" }, .bounded_fix = "emit manifest from @comp.why", .witness = "pass27 manifest + fact-loss ledger columns", .status = .specified, .rank_inputs = .{ .impact = 5, .frequency = 5, .leverage = 5, .ward = 5, .selfhost = 4, .risk = 1, .redesign = 1, .overlap = 1 } }, .{ .id = "L7", .class = .dispatch, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "metamethod dispatch", .cause = "Per-field metatable lookup", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "metatable pointer identity guard", .witness = "@comp.why metatable identity guard", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 4, .ward = 3, .selfhost = 2, .risk = 2, .redesign = 2, .overlap = 3 } }, .{ .id = "L8", .class = .representation, .file = "UNLOCATED", .symbol = "proven_int", .semantic_path = "arithmetic loops", .cause = "Tag checks on unproven int", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "proven_int/proven_float facts", .witness = "@comp.why numeric speciation facts", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 5, .leverage = 4, .ward = 4, .selfhost = 2, .risk = 2, .redesign = 3, .overlap = 3 } }, .{ .id = "L9", .class = .allocation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "partial escape", .cause = "No allocation sinking", .semantically_required = false, .prerequisites = &[_][]const u8{ "E1", "E8" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "E1", .bridge = "provisional non-moving contract" }, .{ .id = "E8", .bridge = "sealed-immutable alias-free subset" } }, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "sink allocation to escaping branch", .witness = "manifest allocation site counts", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 4, .leverage = 3, .ward = 2, .selfhost = 2, .risk = 3, .redesign = 3, .overlap = 3 } }, .{ .id = "L10", .class = .dispatch, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "sealing invalidation", .cause = "Blanket write barriers", .semantically_required = false, .prerequisites = &[_][]const u8{"E1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E1", .bridge = "provisional non-moving contract" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "targeted dirty barriers", .witness = "manifest write-barrier counts", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 4, .leverage = 4, .ward = 2, .selfhost = 3, .risk = 3, .redesign = 3, .overlap = 4 } }, .{ .id = "L11", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "module closures", .cause = "Upvalues not constants after L1", .semantically_required = false, .prerequisites = &[_][]const u8{"L1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L1", .bridge = "module sealing makes upvalues constant" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "closure flattening from sealed modules", .witness = "@comp.why closure flatten witness", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 4, .ward = 3, .selfhost = 4, .risk = 2, .redesign = 2, .overlap = 5 } }, .{ .id = "L12", .class = .stage, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "effect elimination", .cause = "Effect machinery not erased when proven unnecessary", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "erase proven-unnecessary effect hooks", .witness = "@comp.why effect elimination witness", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 5, .ward = 4, .selfhost = 3, .risk = 3, .redesign = 3, .overlap = 3 } }, .{ .id = "L13", .class = .stage, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "call-shape caching", .cause = "Call shapes re-specialized per site", .semantically_required = false, .prerequisites = &[_][]const u8{"E10"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E10", .bridge = "coarse invalidation keys call-shape cache" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "compile-time call-shape dedupe", .witness = "compile budget manifest entries", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 2, .selfhost = 4, .risk = 2, .redesign = 3, .overlap = 4 } }, .{ .id = "L14", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "descriptor folding", .cause = "Descriptor comparisons at runtime", .semantically_required = false, .prerequisites = &[_][]const u8{ "L1", "C2" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "L1", .bridge = "module sealing freezes descriptors" }, .{ .id = "C2", .bridge = "one descriptor identity system" } }, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "fold frozen descriptor queries", .witness = "@comp.why descriptor fold witness", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 4, .leverage = 4, .ward = 3, .selfhost = 3, .risk = 2, .redesign = 2, .overlap = 4 } }, .{ .id = "L15", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "semantic coverage", .cause = "Tests cover lines not compiler knowledge", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "manifest extension for coverage columns" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "semantic coverage manifest columns", .witness = "manifest coverage percentages", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 3, .selfhost = 3, .risk = 2, .redesign = 2, .overlap = 3 } },
};

pub const unicorns: []const BarrierRecord = &.{
    .{ .id = "U1", .class = .stage, .file = "UNLOCATED", .symbol = "user_asserted", .semantic_path = "verified agent hints", .cause = "Not wired to verify", .semantically_required = false, .prerequisites = &[_][]const u8{"U14"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "U14", .bridge = "counterexample records on rejection" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "verify user-asserted facts", .witness = "@comp.why user-asserted verification", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 5, .ward = 3, .selfhost = 5, .risk = 3, .redesign = 2, .overlap = 2 } }, .{ .id = "U2", .class = .representation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "AoS to SoA", .cause = "Container SoA missing", .semantically_required = false, .prerequisites = &[_][]const u8{"E8"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E8", .bridge = "sealed-immutable alias-free subset" }}, .impact = .{ .runtime = .high, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "container SoA realization", .witness = "manifest SoA realization witness", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 2, .leverage = 5, .ward = 4, .selfhost = 2, .risk = 4, .redesign = 4, .overlap = 2 } }, .{ .id = "U3", .class = .stage, .file = "UNLOCATED", .symbol = "@comp.why.bailed", .semantic_path = "queryable deopt", .cause = "Deopt not exposed", .semantically_required = false, .prerequisites = &[_][]const u8{ "C1", "E2" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "C1", .bridge = "frame maps via proofs-over-guards subset" }, .{ .id = "E2", .bridge = "deopt events with provenance" } }, .impact = .{ .runtime = .low, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "@comp.why.bailed surface", .witness = "@comp.why.bailed query output", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 2, .leverage = 4, .ward = 3, .selfhost = 4, .risk = 3, .redesign = 3, .overlap = 4 } }, .{ .id = "U4", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "perf blame", .cause = "No manifest diff blame", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "manifest + fingerprint diff substrate" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "manifest + fingerprint diff", .witness = "manifest diff blame records", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 5, .ward = 3, .selfhost = 4, .risk = 2, .redesign = 2, .overlap = 4 } }, .{ .id = "U5", .class = .stage, .file = "UNLOCATED", .symbol = "@comp.world.closed", .semantic_path = "closed-world mode", .cause = "No whole-program seal flag", .semantically_required = false, .prerequisites = &[_][]const u8{ "E1", "L1" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "E1", .bridge = "provisional non-moving contract" }, .{ .id = "L1", .bridge = "module sealing at link time" } }, .impact = .{ .runtime = .dominant, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "@comp.world.closed flag", .witness = "@comp.why closed-world proof bundle", .status = .discovered, .rank_inputs = .{ .impact = 5, .frequency = 2, .leverage = 5, .ward = 5, .selfhost = 3, .risk = 4, .redesign = 4, .overlap = 3 } }, .{ .id = "U6", .class = .allocation, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "startup heap images", .cause = "No snapshot images", .semantically_required = false, .prerequisites = &[_][]const u8{"E1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E1", .bridge = "non-moving heap pointer stability" }}, .impact = .{ .runtime = .high, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "persist initialized heap image", .witness = "snapshot build manifest entry", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 2, .leverage = 4, .ward = 2, .selfhost = 3, .risk = 4, .redesign = 5, .overlap = 2 } }, .{ .id = "U7", .class = .stage, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "tests as optimization fuel", .cause = "Staged tests not mined", .semantically_required = false, .prerequisites = &[_][]const u8{"E10"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "E10", .bridge = "staging + fact classification via invalidation keys" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "staged test fact promotion", .witness = "knowledge fact promotion witnesses", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 5, .ward = 2, .selfhost = 4, .risk = 4, .redesign = 4, .overlap = 3 } }, .{ .id = "U8", .class = .abi, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "native coroutines", .cause = "Heap coroutine frames", .semantically_required = false, .prerequisites = &[_][]const u8{ "E1", "C1", "E3" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "E1", .bridge = "non-moving contract" }, .{ .id = "C1", .bridge = "frame maps" }, .{ .id = "E3", .bridge = "out-of-band error flag" } }, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "segmented side stacks", .witness = "coroutine frame map witnesses", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 4, .ward = 2, .selfhost = 2, .risk = 5, .redesign = 5, .overlap = 3 } }, .{ .id = "U9", .class = .representation, .file = "UNLOCATED", .symbol = "foreign_borrowed_view", .semantic_path = "zero-marshal FFI", .cause = "No FFI view lever", .semantically_required = false, .prerequisites = &[_][]const u8{ "C2", "E9" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "C2", .bridge = "descriptor identity for views" }, .{ .id = "E9", .bridge = "ABI v0 struct layout" } }, .impact = .{ .runtime = .high, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "C struct layout descriptor views", .witness = "FFI view descriptor witnesses", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 2, .leverage = 4, .ward = 4, .selfhost = 3, .risk = 3, .redesign = 3, .overlap = 2 } }, .{ .id = "U10", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "compile budget planner", .cause = "No compile-time cost dimension", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "compile budget in Pass 8 planner", .witness = "planner budget manifest", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 2, .selfhost = 5, .risk = 3, .redesign = 4, .overlap = 4 } }, .{ .id = "U11", .class = .stage, .file = "UNLOCATED", .symbol = "@goal", .semantic_path = "contracts/negotiation", .cause = "Hints not goals with proofs", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "witness store + manifest budgets" }}, .impact = .{ .runtime = .high, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "goal prove-or-negotiate syntax", .witness = "negotiation witness records", .status = .discovered, .rank_inputs = .{ .impact = 4, .frequency = 3, .leverage = 5, .ward = 4, .selfhost = 4, .risk = 3, .redesign = 3, .overlap = 2 } }, .{ .id = "U12", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "history/bisect", .cause = "No provenance over time", .semantically_required = false, .prerequisites = &[_][]const u8{ "C5", "L6" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "C5", .bridge = "C5 query engine projection" }, .{ .id = "L6", .bridge = "witness store over time" } }, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "semantic history + bisect queries", .witness = "provenance timeline witnesses", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 5, .ward = 3, .selfhost = 4, .risk = 3, .redesign = 3, .overlap = 3 } }, .{ .id = "U13", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "semantic replay", .cause = "No step-through entity evolution", .semantically_required = false, .prerequisites = &[_][]const u8{"C5"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "C5", .bridge = "C5 query engine replay projection" }}, .impact = .{ .runtime = .medium, .frequency = .rare, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "duo replay entity evolution", .witness = "replay step witnesses", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 2, .leverage = 4, .ward = 3, .selfhost = 4, .risk = 3, .redesign = 4, .overlap = 3 } }, .{ .id = "U14", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "proof minimization", .cause = "Failures not minimized to counterexamples", .semantically_required = false, .prerequisites = &[_][]const u8{"U1"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "U1", .bridge = "feeds rejection counterexamples" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "minimal semantic counterexample shrink", .witness = "counterexample witness records", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 2, .selfhost = 4, .risk = 3, .redesign = 3, .overlap = 3 } }, .{ .id = "U15", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "semantic diff/patch/merge", .cause = "Diff is line-based not graph-based", .semantically_required = false, .prerequisites = &[_][]const u8{ "C3", "C5" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "C3", .bridge = "semantic graph delta operations" }, .{ .id = "C5", .bridge = "C5 query projections" } }, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "graph delta diff patch merge", .witness = "semantic diff witnesses", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 5, .ward = 3, .selfhost = 4, .risk = 3, .redesign = 4, .overlap = 3 } },
};

pub const traps: []const BarrierRecord = &.{
    .{ .id = "T1", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "benchmark string concat", .cause = "Hot-loop concat measures allocator", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "manifest flags concat violations" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "harness rule + manifest flag", .witness = "manifest T1 violation flag", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 3, .leverage = 3, .ward = 4, .selfhost = 2, .risk = 1, .redesign = 1, .overlap = 2 } }, .{ .id = "T2", .class = .process, .file = "backend_identity.zig", .symbol = "BenchBackend", .semantic_path = "published benchmark identity", .cause = "Missing backend tags", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .low, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "backend tag required", .witness = "backend_identity manifest tag", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 4, .leverage = 4, .ward = 5, .selfhost = 2, .risk = 1, .redesign = 1, .overlap = 3 } }, .{ .id = "T3", .class = .helper, .file = "pass27_benchmark_evidence.zig", .symbol = "EvidenceCounters", .semantic_path = "helper-dominated microbenches", .cause = "Helpers hide specialization gaps", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "manifest helper counts" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "contaminated tag on hot helpers", .witness = "manifest helper contamination tag", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 4, .leverage = 4, .ward = 5, .selfhost = 2, .risk = 1, .redesign = 1, .overlap = 3 } }, .{ .id = "T4", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "representation-observing tests", .cause = "Tests pin representations", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .low, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "semantic assertion audit", .witness = "test audit manifest", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 3, .leverage = 3, .ward = 2, .selfhost = 3, .risk = 1, .redesign = 1, .overlap = 2 } }, .{ .id = "T5", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "cache-sized fixtures", .cause = "L2-resident fixtures hide effects", .semantically_required = false, .prerequisites = &[_][]const u8{}, .prerequisite_bridges = &[_]PrerequisiteBridge{}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "L2-exceeding benchmark tiers", .witness = "benchmark tier manifest", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 3, .ward = 4, .selfhost = 1, .risk = 1, .redesign = 1, .overlap = 1 } }, .{ .id = "T6", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "benchmark drift", .cause = "Suites optimize around compiler", .semantically_required = false, .prerequisites = &[_][]const u8{"L6"}, .prerequisite_bridges = &[_]PrerequisiteBridge{.{ .id = "L6", .bridge = "manifest tracks workload rotation" }}, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "periodic workload replacement policy", .witness = "benchmark rotation manifest", .status = .discovered, .rank_inputs = .{ .impact = 2, .frequency = 3, .leverage = 3, .ward = 4, .selfhost = 1, .risk = 1, .redesign = 1, .overlap = 2 } }, .{ .id = "T7", .class = .process, .file = "UNLOCATED", .symbol = "UNLOCATED", .semantic_path = "semantic benchmark pollution", .cause = "Suite converges on one idiom", .semantically_required = false, .prerequisites = &[_][]const u8{ "L6", "L15" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "L6", .bridge = "manifest idiom diversity" }, .{ .id = "L15", .bridge = "semantic coverage enforcement" } }, .impact = .{ .runtime = .medium, .frequency = .common, .evidence = .estimated }, .backends = all, .tests = &.{}, .bounded_fix = "idiom diversity via L15 coverage", .witness = "coverage diversity manifest", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 3, .leverage = 4, .ward = 4, .selfhost = 1, .risk = 1, .redesign = 1, .overlap = 2 } }, .{ .id = "T8", .class = .process, .file = TEXT_IDIOM_GATE_PATH, .symbol = "rules", .semantic_path = "agent idiom enforcement", .cause = "Idiom enforced by regex over source text instead of manifest cleanliness and provable facts", .semantically_required = false, .prerequisites = &[_][]const u8{ "L6", "L15", "U11" }, .prerequisite_bridges = &[_]PrerequisiteBridge{ .{ .id = "L6", .bridge = "manifest-delta gate lands before text rules are retired" }, .{ .id = "L15", .bridge = "semantic coverage replaces the hand-maintained rule list" }, .{ .id = "U11", .bridge = "per-function goal replaces the lint comment as repair instruction" } }, .impact = .{ .runtime = .medium, .frequency = .pervasive, .evidence = .estimated }, .backends = all, .tests = &.{"pass34_gate"}, .bounded_fix = "replace text rules with manifest-delta plus goal gates", .witness = "manifest delta plus goal negotiation record per agent diff", .status = .discovered, .rank_inputs = .{ .impact = 3, .frequency = 4, .leverage = 4, .ward = 2, .selfhost = 5, .risk = 1, .redesign = 2, .overlap = 3 } },
};

pub const ranked_item_ids: []const RankedEntry = &.{
    .{ .rank = 1, .id = "L6", .rationale = "without measurement every other row is opinion" },
    .{ .rank = 2, .id = "L1", .rationale = "pervasive near-zero risk feeds L11 L14 U5" },
    .{ .rank = 3, .id = "E1", .rationale = "zero code largest downstream unlock" },
    .{ .rank = 4, .id = "E8", .rationale = "peer of E1 upper ladder teeth" },
    .{ .rank = 5, .id = "L2", .rationale = "improves worst case small isolated" },
    .{ .rank = 6, .id = "C1", .rationale = "one artifact seven consumers E2+E7" },
    .{ .rank = 7, .id = "E9", .rationale = "ABI v0 prevents backend divergence" },
    .{ .rank = 8, .id = "L3", .rationale = "idiom-level win headline benchmark" },
    .{ .rank = 9, .id = "L12", .rationale = "general theorem behind several levers" },
    .{ .rank = 10, .id = "L7", .rationale = "one mechanism devirtualizes metamethods" },
    .{ .rank = 11, .id = "L4", .rationale = "Ward byte-heavy workload" },
    .{ .rank = 12, .id = "L8", .rationale = "honest C comparisons require it" },
    .{ .rank = 13, .id = "L13", .rationale = "compile-time relief pairs with E10" },
    .{ .rank = 14, .id = "U5", .rationale = "one flag whole-program proof" },
    .{ .rank = 15, .id = "L5", .rationale = "classic benchmark shape L12 instance" },
    .{ .rank = 16, .id = "U11", .rationale = "witnesses + cost model wearing syntax" },
    .{ .rank = 17, .id = "U1", .rationale = "agent-native proof point mostly wiring" },
    .{ .rank = 18, .id = "U4", .rationale = "composition of L6 + fingerprints" },
    .{ .rank = 19, .id = "L9/L10/L14", .rationale = "under E1/E8 bridges" },
    .{ .rank = 20, .id = "E10", .rationale = "coarse bridge now fine-grained later" },
    .{ .rank = 21, .id = "U10", .rationale = "answers E4 needs planner maturity" },
    .{ .rank = 22, .id = "E3", .rationale = "bridge convention co-designed with E9" },
    .{ .rank = 23, .id = "U12/U13", .rationale = "C5 projections after witness store" },
    .{ .rank = 24, .id = "L15", .rationale = "manifest extension arms T7" },
    .{ .rank = 25, .id = "U7/U14/U15", .rationale = "staging + graph maturity" },
    .{ .rank = 26, .id = "U6/U8/U9", .rationale = "after E1 C1 E3 bridges harden" },
    .{ .rank = 27, .id = "U2", .rationale = "after single-record realization under E8" },
    .{ .rank = 28, .id = "E4/E5/E6", .rationale = "strategy paragraphs zero cost" },
};

pub const canonical_home_mappings: []const CanonicalHomeMapping = &.{
    .{ .proposal = "Semantic time travel", .home = "U12" },
    .{ .proposal = "Interactive realization explorer", .home = "Pass 8 Milestone 1 via C5" },
    .{ .proposal = "Semantic diff", .home = "U15" },
    .{ .proposal = "First-class compiler queries", .home = "C5 query engine" },
    .{ .proposal = "Whole-program semantic search", .home = "C5" },
    .{ .proposal = "Semantic patching", .home = "U15" },
    .{ .proposal = "Semantic merge", .home = "U15" },
    .{ .proposal = "Optimization marketplace", .home = "Pass 8 candidate registry" },
    .{ .proposal = "Explainability score", .home = "C5 projection over witness density" },
    .{ .proposal = "Semantic coverage", .home = "L15" },
    .{ .proposal = "Optimization contracts", .home = "U11" },
    .{ .proposal = "Compiler negotiation", .home = "U11" },
    .{ .proposal = "Semantic performance budget", .home = "U11 project-level goals" },
    .{ .proposal = "Representation heat map", .home = "C5 projection of L6 data" },
    .{ .proposal = "Semantic profiles", .home = "U10 planner weight presets" },
    .{ .proposal = "Semantic replay", .home = "U13" },
    .{ .proposal = "Self-improving optimizer", .home = "Pass 8 persistent evidence" },
    .{ .proposal = "Semantic package registry", .home = "Horizon SIM-gated" },
    .{ .proposal = "Cross-language semantic refactoring", .home = "Horizon SIM-gated" },
    .{ .proposal = "Semantic operating environment", .home = "Horizon Pass 25 trajectory" },
};

/// §13 — agent idiom enforcement. Six mechanisms, zero new subsystems: each
/// routes to barrier records that already exist. Enforcement is a number
/// (manifest delta), a proof (goal), or a counterexample — never a review
/// comment. T8 records the text linter these supersede.
pub const agent_idiom_projections: []const AgentIdiomProjection = &.{
    .{ .mechanism = "manifest is the style guide", .homes = &[_][]const u8{"L6"}, .enforcement = "CI rejects a diff whose manifest grew a box allocation dynamic dispatch or hot-region helper" },
    .{ .mechanism = "goals are the agent contract not hints", .homes = &[_][]const u8{"U11"}, .enforcement = "every agent-authored function of consequence carries a goal proved or negotiated with a structured counteroffer" },
    .{ .mechanism = "assert-and-verify replaces write-and-hope", .homes = &[_][]const u8{ "U1", "U14" }, .enforcement = "agent declares monomorphic non-escaping sealed facts compiler verifies or returns the minimal semantic counterexample" },
    .{ .mechanism = "semantic edit vocabulary closes the text loophole", .homes = &[_][]const u8{ "U15", "C3" }, .enforcement = "proven-legal graph operations have no unidiomatic outcome text edits still pay the manifest gate" },
    .{ .mechanism = "golden corpus ships manifests not comments", .homes = &[_][]const u8{ "L15", "L6" }, .enforcement = "exemplars carry manifest and @comp.why output coverage spans every metaprogramming surface" },
    .{ .mechanism = "idiom served by query not source reading", .homes = &[_][]const u8{"C5"}, .enforcement = "bounded context packages over MCP with @comp.why.not counterfactuals in every response" },
};

pub const dependency_edges: []const DependencyEdge = &.{
    .{ .from_id = "E1", .to_ids = &[_][]const u8{ "L9", "L10", "U5", "U6", "U8", "E9" }, .bridge = "provisional non-moving contract" },
    .{ .from_id = "E8", .to_ids = &[_][]const u8{ "U2", "L9" }, .bridge = "sealed-immutable alias-free subset" },
    .{ .from_id = "C1", .to_ids = &[_][]const u8{ "U3", "U8", "E7", "E2" }, .bridge = "proofs-over-guards subset without frame maps" },
    .{ .from_id = "E2", .to_ids = &[_][]const u8{ "U3", "E7" }, .bridge = "proofs-over-guards subset" },
    .{ .from_id = "E7", .to_ids = &[_][]const u8{"U3"}, .bridge = "same artifact as C1" },
    .{ .from_id = "E3", .to_ids = &[_][]const u8{ "L3", "U8", "E9" }, .bridge = "out-of-band error flag per-function upgradeable" },
    .{ .from_id = "E9", .to_ids = &[_][]const u8{"E5"}, .bridge = "ABI v0 C ABI plus versioned extensions" },
    .{ .from_id = "E10", .to_ids = &[_][]const u8{ "E4", "U10" }, .bridge = "coarse module invalidation now" },
    .{ .from_id = "L1", .to_ids = &[_][]const u8{ "L11", "L14", "U5" }, .bridge = "lands early no bridge needed" },
    .{ .from_id = "L6", .to_ids = &[_][]const u8{ "U4", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "E5", "U11", "C5" }, .bridge = "lands first witness store" },
    .{ .from_id = "L15", .to_ids = &[_][]const u8{ "T7", "T8" }, .bridge = "semantic coverage replaces hand-maintained idiom rule lists" },
    .{ .from_id = "U11", .to_ids = &[_][]const u8{"T8"}, .bridge = "per-function goal is the agent-facing idiom contract" },
    .{ .from_id = "C5", .to_ids = &[_][]const u8{ "U12", "U13", "U15" }, .bridge = "witnesses accumulate from first L-tier fix" },
    .{ .from_id = "U1", .to_ids = &[_][]const u8{"U14"}, .bridge = "knowledge classes plus counterexamples" },
    .{ .from_id = "U7", .to_ids = &[_][]const u8{"E10"}, .bridge = "staging plus fact classification" },
};

pub const execution_phases: []const ExecutionPhase = &.{
    .{ .phase = 0, .id = "P34-PH0", .title = "Record everything", .exit_gate = "catalog queryable no unbridged prerequisite zero speculative code" },
    .{ .phase = 1, .id = "P34-PH1", .title = "Instrument then seal", .exit_gate = "L6 then L1 then L2 manifest dispatch drop" },
    .{ .phase = 2, .id = "P34-PH2", .title = "Decide the descent", .exit_gate = "Tier-E DISCOVERED to SPECIFIED bridges adopted" },
    .{ .phase = 3, .id = "P34-PH3", .title = "Cash the levers", .exit_gate = "Ward L4 criteria via manifest L15 baseline" },
    .{ .phase = 4, .id = "P34-PH4", .title = "Prove a unicorn", .exit_gate = "U1 or U4 or U11 end-to-end demo" },
    .{ .phase = 5, .id = "P34-PH5", .title = "Closed world", .exit_gate = "U5 Ward decoder differential benchmark" },
    .{ .phase = 6, .id = "P34-PH6", .title = "Open the substrate", .exit_gate = "C5 views heat map history replay diff bisect" },
};

pub fn barrierCount() usize {
    return convergences.len + elephants.len + levers.len + unicorns.len + traps.len;
}

pub fn barriersInTier(tier: BarrierTier) usize {
    return switch (tier) {
        .convergence => convergences.len,
        .elephant => elephants.len,
        .lever => levers.len,
        .unicorn => unicorns.len,
        .trap => traps.len,
    };
}

pub fn allBarrierTiers() [5][]const BarrierRecord {
    return .{ convergences, elephants, levers, unicorns, traps };
}

pub fn findBarrier(id: []const u8) ?BarrierRecord {
    inline for (allBarrierTiers()) |tier| {
        for (tier) |rec| {
            if (std.mem.eql(u8, rec.id, id)) return rec;
        }
    }
    return null;
}

pub fn isValidBarrierId(id: []const u8) bool {
    return findBarrier(id) != null;
}

pub fn writePass34Json(w: *std.Io.Writer, _: std.mem.Allocator) !void {
    try w.print(
        \\  "pass34":{{
        \\    "schema_version":"{s}",
        \\    "plan_path":"{s}",
        \\    "canonical_path":"{s}",
        \\    "index_path":"{s}",
        \\    "convergence_count":{d},
        \\    "elephant_count":{d},
        \\    "lever_count":{d},
        \\    "unicorn_count":{d},
        \\    "trap_count":{d},
        \\    "barrier_count":{d},
        \\    "ranked_item_count":{d},
        \\    "canonical_home_mapping_count":{d},
        \\    "dependency_edge_count":{d},
        \\    "execution_phase_count":{d},
        \\    "agent_idiom_projection_count":{d},
        \\    "text_idiom_gate_path":"{s}",
        \\    "phase0_status":"discovered_only",
        \\    "phase1_status":"L6_L1_specified"
        \\  }}
    ,
        .{ SCHEMA_VERSION, PLAN_PATH, CANONICAL_PATH, INDEX_PATH, convergences.len, elephants.len, levers.len, unicorns.len, traps.len, barrierCount(), ranked_item_ids.len, canonical_home_mappings.len, dependency_edges.len, execution_phases.len, agent_idiom_projections.len, TEXT_IDIOM_GATE_PATH },
    );
}

test "pass34_catalog: tier counts" {
    try std.testing.expect(convergences.len == 5);
    try std.testing.expect(elephants.len == 10);
    try std.testing.expect(levers.len == 15);
    try std.testing.expect(unicorns.len == 15);
    try std.testing.expect(traps.len == 8);
    try std.testing.expect(barrierCount() == 53);
    try std.testing.expect(canonical_home_mappings.len == 20);
    try std.testing.expect(execution_phases.len == 7);
}

test "pass34_catalog: §13 agent idiom projections resolve to existing records" {
    try std.testing.expect(agent_idiom_projections.len == 6);
    for (agent_idiom_projections) |proj| {
        try std.testing.expect(proj.homes.len > 0);
        for (proj.homes) |home| try std.testing.expect(isValidBarrierId(home));
    }
    const t8 = findBarrier("T8") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(TEXT_IDIOM_GATE_PATH, t8.file);
}
