//! Pass 26 — foundational semantic closure catalog (52 seams + flagship proof).
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-catalog-v1";
pub const PLAN_PATH = "docs/archive/pass26_foundational_semantic_closure.md";
pub const INDEX_PATH = "docs/archive/pass26_closure_index.md";

pub const Priority = enum {
    immediate,
    critical,
    high,
    medium_high,

    pub fn name(self: Priority) []const u8 {
        return switch (self) {
            .immediate => "immediate",
            .critical => "critical",
            .high => "high",
            .medium_high => "medium-high",
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

pub const workstreams: []const Workstream = &.{
    .{ .id = "P26-WS01", .title = "Semantic operation identity registry", .status = "partial", .priority = .critical, .owner = "src/pass26_semantic_operation.zig", .plan_section = "§3" },
    .{ .id = "P26-WS02", .title = "Protocol attachment without namespace pollution", .status = "partial", .priority = .critical, .owner = "src/pass26_protocol_attachment.zig", .plan_section = "§4" },
    .{ .id = "P26-WS03", .title = "Identity vs equality vs representation", .status = "partial", .priority = .critical, .owner = "src/pass26_descriptor_identity.zig", .plan_section = "§5" },
    .{ .id = "P26-WS04", .title = "Descriptor normalization + interning", .status = "partial", .priority = .critical, .owner = "src/pass26_descriptor_identity.zig", .plan_section = "§6" },
    .{ .id = "P26-WS05", .title = "Descriptors vs mutable builder tables", .status = "partial", .priority = .critical, .owner = "src/pass26_descriptor_identity.zig", .plan_section = "§7" },
    .{ .id = "P26-WS06", .title = "Stage-dependency model", .status = "open", .priority = .critical, .owner = "src/pass26_semantic_boundary.zig + sema", .plan_section = "§8" },
    .{ .id = "P26-WS07", .title = "Effect polymorphism + containment", .status = "open", .priority = .high, .owner = "effect algebra + sema", .plan_section = "§9" },
    .{ .id = "P26-WS08", .title = "Metaprogramming failure outcomes", .status = "open", .priority = .high, .owner = "pass25_projection_model + descriptors", .plan_section = "§10" },
    .{ .id = "P26-WS09", .title = "Text/bytes/code points/foreign strings", .status = "open", .priority = .high, .owner = "types + std descriptors", .plan_section = "§11" },
    .{ .id = "P26-WS10", .title = "Path/Url/Command distinct types", .status = "open", .priority = .high, .owner = "shell + command_descriptor", .plan_section = "§12" },
    .{ .id = "P26-WS11", .title = "Package/module identity rigor", .status = "open", .priority = .high, .owner = "dependency_manifest + SIM", .plan_section = "§13" },
    .{ .id = "P26-WS12", .title = "Stable source emission + preservation", .status = "open", .priority = .high, .owner = "git_preservation + frontends", .plan_section = "§14" },
    .{ .id = "P26-WS13", .title = "Cross-language trust lattice", .status = "partial", .priority = .high, .owner = "src/pass26_semantic_boundary.zig", .plan_section = "§15" },
    .{ .id = "P26-WS14", .title = "Compiler-derived semantic versioning", .status = "open", .priority = .medium_high, .owner = "dependency_manifest", .plan_section = "§16" },
    .{ .id = "P26-WS15", .title = "General migration transformation", .status = "open", .priority = .high, .owner = "transform_engine", .plan_section = "§17" },
    .{ .id = "P26-WS16", .title = "Concurrency contract algebra", .status = "open", .priority = .high, .owner = "pass24_execution_model", .plan_section = "§18" },
    .{ .id = "P26-WS17", .title = "Semantic boundary first-class object", .status = "partial", .priority = .critical, .owner = "src/pass26_semantic_boundary.zig", .plan_section = "§1, §17" },
    .{ .id = "P26-WS18", .title = "Adapter elimination framework", .status = "open", .priority = .high, .owner = "transform_engine + pass26_semantic_boundary", .plan_section = "§18" },
    .{ .id = "P26-WS19", .title = "Semantic manifest artifact", .status = "open", .priority = .high, .owner = "SIM + dependency_manifest", .plan_section = "§19" },
    .{ .id = "P26-WS20", .title = "Decision/contradiction registry", .status = "partial", .priority = .immediate, .owner = "src/pass26_decision_registry.zig", .plan_section = "§20" },
    .{ .id = "P26-WS21", .title = "Flagship vertical proof (C→Duo→Rust→zero-copy)", .status = "open", .priority = .critical, .owner = "Pass 5 + Pass 20 + transform_engine", .plan_section = "§21" },
    // Extended closure (§25–§54)
    .{ .id = "P26-WS22", .title = "Initialization graph + cycle classification", .status = "partial", .priority = .critical, .owner = "src/pass26_runtime_closure.zig", .plan_section = "§25" },
    .{ .id = "P26-WS23", .title = "Recursive descriptors + semantic fixed points", .status = "partial", .priority = .critical, .owner = "src/pass26_recursive_descriptor.zig", .plan_section = "§26" },
    .{ .id = "P26-WS24", .title = "Canonical mutability semantics", .status = "partial", .priority = .critical, .owner = "src/pass26_runtime_closure.zig", .plan_section = "§27" },
    .{ .id = "P26-WS25", .title = "Canonical dynamic value model", .status = "partial", .priority = .critical, .owner = "src/pass26_runtime_closure.zig", .plan_section = "§28" },
    .{ .id = "P26-WS26", .title = "GC/native ownership interoperability", .status = "partial", .priority = .critical, .owner = "src/pass26_runtime_closure.zig", .plan_section = "§29" },
    .{ .id = "P26-WS27", .title = "Canonical hashing model", .status = "partial", .priority = .critical, .owner = "src/pass26_hash_order.zig", .plan_section = "§30" },
    .{ .id = "P26-WS28", .title = "Deterministic iteration semantics", .status = "partial", .priority = .high, .owner = "src/pass26_hash_order.zig", .plan_section = "§31" },
    .{ .id = "P26-WS29", .title = "Reflection authority and stability", .status = "open", .priority = .high, .owner = "semantic_graph + pass26_evidence", .plan_section = "§32" },
    .{ .id = "P26-WS30", .title = "Meta-circular dependency control", .status = "partial", .priority = .critical, .owner = "src/pass26_transform_meta.zig", .plan_section = "§33" },
    .{ .id = "P26-WS31", .title = "Transformation composition semantics", .status = "partial", .priority = .high, .owner = "src/pass26_transform_meta.zig", .plan_section = "§34" },
    .{ .id = "P26-WS32", .title = "Proof invalidation + evidence expiry", .status = "partial", .priority = .critical, .owner = "src/pass26_evidence.zig", .plan_section = "§35" },
    .{ .id = "P26-WS33", .title = "Numerical semantics as descriptors", .status = "open", .priority = .high, .owner = "types + descriptors", .plan_section = "§36" },
    .{ .id = "P26-WS34", .title = "Units and dimensional semantics", .status = "open", .priority = .high, .owner = "descriptors + boundaries", .plan_section = "§37" },
    .{ .id = "P26-WS35", .title = "Calling convention descriptors", .status = "partial", .priority = .critical, .owner = "src/pass26_abi_resource.zig", .plan_section = "§38" },
    .{ .id = "P26-WS36", .title = "Unwinding and stack semantics", .status = "partial", .priority = .critical, .owner = "src/pass26_abi_resource.zig", .plan_section = "§39" },
    .{ .id = "P26-WS37", .title = "Debug semantics under optimization", .status = "open", .priority = .high, .owner = "explain_pipeline + LSP", .plan_section = "§40" },
    .{ .id = "P26-WS38", .title = "Reproducible build semantics", .status = "open", .priority = .high, .owner = "dependency_manifest + build graph", .plan_section = "§41" },
    .{ .id = "P26-WS39", .title = "Package authenticity + supply chain", .status = "open", .priority = .high, .owner = "SIM manifest + attestation", .plan_section = "§42" },
    .{ .id = "P26-WS40", .title = "Partial and degraded operation", .status = "open", .priority = .high, .owner = "semantic_graph + LSP/MCP", .plan_section = "§43" },
    .{ .id = "P26-WS41", .title = "Query complexity + DoS control", .status = "open", .priority = .high, .owner = "dev_control_plane + MCP budgets", .plan_section = "§44" },
    .{ .id = "P26-WS42", .title = "Language evolution + semantic migration", .status = "open", .priority = .high, .owner = "pass26_decision_registry + migration", .plan_section = "§45" },
    .{ .id = "P26-WS43", .title = "Capability-negotiated compiler protocol", .status = "open", .priority = .high, .owner = "SIM + MCP + LSP", .plan_section = "§46" },
    .{ .id = "P26-WS44", .title = "Multi-target semantic divergence", .status = "open", .priority = .high, .owner = "target_model + realization", .plan_section = "§47" },
    .{ .id = "P26-WS45", .title = "Canonical resource model", .status = "partial", .priority = .critical, .owner = "src/pass26_abi_resource.zig", .plan_section = "§48" },
    .{ .id = "P26-WS46", .title = "Semantic test identity + coverage", .status = "open", .priority = .high, .owner = "selfhosting_matrix + SIM", .plan_section = "§49" },
    .{ .id = "P26-WS47", .title = "Negative capability proofs", .status = "open", .priority = .high, .owner = "effect algebra + proof_carrying", .plan_section = "§50" },
    .{ .id = "P26-WS48", .title = "Semantic cost model interface", .status = "open", .priority = .high, .owner = "transform_engine + compiler_perf", .plan_section = "§51" },
    .{ .id = "P26-WS49", .title = "Optimization stability + predictability", .status = "open", .priority = .high, .owner = "realization + dev_control_plane", .plan_section = "§52" },
    .{ .id = "P26-WS50", .title = "Semantic privacy + secret propagation", .status = "open", .priority = .high, .owner = "effect + boundary model", .plan_section = "§53" },
    .{ .id = "P26-WS51", .title = "Canonical certainty terminology", .status = "partial", .priority = .high, .owner = "src/pass26_evidence.zig", .plan_section = "§54" },
    .{ .id = "P26-WS52", .title = "Semantic domains (second unifier)", .status = "partial", .priority = .critical, .owner = "src/pass26_semantic_domain.zig", .plan_section = "§55" },
};

pub const CompletionGate = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    plan_section: []const u8,
};

pub const completion_gates: []const CompletionGate = &.{
    .{ .id = "P26-G01", .title = "Semantic operation registry schema + Pass 23 bridge", .status = "partial", .plan_section = "§3" },
    .{ .id = "P26-G02", .title = "Protocol attachment model + Lua projection", .status = "partial", .plan_section = "§4" },
    .{ .id = "P26-G03", .title = "Four identity layers + eight equality kinds + snapshot rules", .status = "partial", .plan_section = "§5–§7" },
    .{ .id = "P26-G04", .title = "Boundary object + trust lattice + adapter chain schema", .status = "partial", .plan_section = "§1, §15, §18" },
    .{ .id = "P26-G05", .title = "Decision registry with 10+ seeded contradictions", .status = "partial", .plan_section = "§20" },
    .{ .id = "P26-G06", .title = "Stage transitions wired in sema/meta", .status = "open", .plan_section = "§8" },
    .{ .id = "P26-G07", .title = "Effect polymorphism on higher-order calls", .status = "open", .plan_section = "§9" },
    .{ .id = "P26-G08", .title = "ProjectionFailure descriptor-backed outcomes", .status = "open", .plan_section = "§10" },
    .{ .id = "P26-G09", .title = "Distinct Text/Path/Url/Command descriptors", .status = "open", .plan_section = "§11–§12" },
    .{ .id = "P26-G10", .title = "Package semantic fingerprint in SIM", .status = "open", .plan_section = "§13" },
    .{ .id = "P26-G11", .title = "Concrete source patch projection per frontend", .status = "open", .plan_section = "§14" },
    .{ .id = "P26-G12", .title = "Transformations declare min trust level", .status = "open", .plan_section = "§15" },
    .{ .id = "P26-G13", .title = "Evidence-based semver impact suggestion", .status = "open", .plan_section = "§16" },
    .{ .id = "P26-G14", .title = "Unified migration transformation", .status = "open", .plan_section = "§17" },
    .{ .id = "P26-G15", .title = "Concurrency law descriptors on aggregates", .status = "open", .plan_section = "§18" },
    .{ .id = "P26-G16", .title = "Adapter elimination pass in transform engine", .status = "open", .plan_section = "§18" },
    .{ .id = "P26-G17", .title = "Semantic manifest emission from builds", .status = "open", .plan_section = "§19" },
    .{ .id = "P26-G20", .title = "Flagship C struct vertical proof slice", .status = "open", .plan_section = "§21" },
    .{ .id = "P26-G21", .title = "Initialization graph schema in sema", .status = "open", .plan_section = "§25" },
    .{ .id = "P26-G22", .title = "Recursive descriptor fixed-point resolution", .status = "open", .plan_section = "§26" },
    .{ .id = "P26-G23", .title = "Mutability kinds + freeze depth wired", .status = "open", .plan_section = "§27" },
    .{ .id = "P26-G24", .title = "Single dynamic value owner specification", .status = "open", .plan_section = "§28" },
    .{ .id = "P26-G25", .title = "GC/native cross-domain ref policies", .status = "open", .plan_section = "§29" },
    .{ .id = "P26-G26", .title = "Semantic fingerprint vs runtime hash separation", .status = "partial", .plan_section = "§30" },
    .{ .id = "P26-G27", .title = "Evidence dependency graph + auto-staleness", .status = "partial", .plan_section = "§35" },
    .{ .id = "P26-G28", .title = "Calling convention descriptors on foreign calls", .status = "partial", .plan_section = "§38" },
    .{ .id = "P26-G29", .title = "Resource + unwind stack kind separation", .status = "partial", .plan_section = "§39, §48" },
    .{ .id = "P26-G30", .title = "Nine semantic domain kinds + boundary linkage", .status = "partial", .plan_section = "§55" },
};

pub const FoundationPriority = struct {
    rank: u8,
    name: []const u8,
    workstreams: []const u8,
};

/// User-prioritized five foundations + decision registry (Pass 26 executive summary).
pub const five_foundations: []const FoundationPriority = &.{
    .{ .rank = 1, .name = "Semantic operation identities", .workstreams = "P26-WS01" },
    .{ .rank = 2, .name = "Protocol attachment", .workstreams = "P26-WS02" },
    .{ .rank = 3, .name = "Descriptor identity + normalization", .workstreams = "P26-WS03,P26-WS04,P26-WS05" },
    .{ .rank = 4, .name = "Semantic boundaries + adapters", .workstreams = "P26-WS17,P26-WS18" },
    .{ .rank = 5, .name = "Decision/contradiction registry", .workstreams = "P26-WS20" },
};

/// Revised top-ten closure priorities (force before new syntax/features).
pub const ten_closure_priorities: []const FoundationPriority = &.{
    .{ .rank = 1, .name = "Descriptor normalization, identity, and recursion", .workstreams = "P26-WS03,P26-WS04,P26-WS05,P26-WS23" },
    .{ .rank = 2, .name = "Canonical dynamic representation", .workstreams = "P26-WS25" },
    .{ .rank = 3, .name = "Mutability and initialization semantics", .workstreams = "P26-WS22,P26-WS24" },
    .{ .rank = 4, .name = "GC/native ownership interoperability", .workstreams = "P26-WS26" },
    .{ .rank = 5, .name = "Semantic operation and protocol identity", .workstreams = "P26-WS01,P26-WS02" },
    .{ .rank = 6, .name = "Semantic domains and boundaries", .workstreams = "P26-WS17,P26-WS52" },
    .{ .rank = 7, .name = "Stage dependency and meta-circular convergence", .workstreams = "P26-WS06,P26-WS30" },
    .{ .rank = 8, .name = "Evidence invalidation", .workstreams = "P26-WS32,P26-WS51" },
    .{ .rank = 9, .name = "ABI/calling convention descriptors", .workstreams = "P26-WS35" },
    .{ .rank = 10, .name = "Resource and unwind semantics", .workstreams = "P26-WS36,P26-WS45" },
};

pub fn writePass26Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    _ = alloc;
    try w.print(
        \\"pass26":{{
        \\  "schema_version":"{s}",
        \\  "plan_path":"{s}",
        \\  "index_path":"{s}",
        \\  "workstream_count":{d},
        \\  "completion_gate_count":{d},
        \\  "five_foundations_count":{d},
        \\  "ten_closure_priorities_count":{d},
        \\  "flagship_proof":"P26-WS21"
        \\}}
    ,
        .{
            SCHEMA_VERSION,
            PLAN_PATH,
            INDEX_PATH,
            workstreams.len,
            completion_gates.len,
            five_foundations.len,
            ten_closure_priorities.len,
        },
    );
}

test "pass26_catalog: workstreams + gates" {
    try std.testing.expect(workstreams.len == 52);
    try std.testing.expect(completion_gates.len == 28);
    try std.testing.expect(five_foundations.len == 5);
    try std.testing.expect(ten_closure_priorities.len == 10);
}
