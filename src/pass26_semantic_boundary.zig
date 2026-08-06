//! Pass 26 §1, §17–§18 — semantic boundary as first-class compiler value.
const std = @import("std");
const pass26_descriptor_identity = @import("pass26_descriptor_identity.zig");

pub const SCHEMA_VERSION = "pass26-semantic-boundary-v0";

pub const SemanticDomain = enum {
    duo_dynamic,
    duo_native,
    duo_compile_time,
    duo_runtime,
    c_abi,
    rust_abi,
    wasm_host,
    wasm_guest,
    gpu_device,
    process,
    network_rpc,
    agent_mcp,
    serialized,
    foreign_opaque,

    pub fn name(self: SemanticDomain) []const u8 {
        return @tagName(self);
    }
};

pub const StageTransition = enum {
    evaluate,
    lift,
    lower,
    residualize,
    persist,
    serialize,
    migrate,

    pub fn name(self: StageTransition) []const u8 {
        return @tagName(self);
    }
};

pub const TrustLevel = enum {
    parsed,
    declared,
    compiler_reported,
    abi_validated,
    differentially_tested,
    proven,
    runtime_observed,
    user_asserted,
    foreign_opaque,

    pub fn name(self: TrustLevel) []const u8 {
        return @tagName(self);
    }

    pub fn ordinal(self: TrustLevel) u8 {
        return @intFromEnum(self);
    }
};

pub const Eliminability = enum {
    unknown,
    removable,
    fusible,
    specializable,
    narrowable,
    guardable,
    migratable,
    realizable_elsewhere,
    required,

    pub fn name(self: Eliminability) []const u8 {
        return @tagName(self);
    }
};

/// First-class boundary record (Pass 26 unifier).
pub const Boundary = struct {
    id: []const u8,
    source: SemanticDomain,
    destination: SemanticDomain,
    transition: StageTransition,
    adaptation: []const u8,
    representation: []const u8,
    effects: []const u8,
    ownership_rule: []const u8,
    lifetime_rule: []const u8,
    min_trust: TrustLevel,
    failure_policy: []const u8,
    cost_hint: []const u8,
    eliminability: Eliminability,
};

pub const canonical_boundaries: []const Boundary = &.{
    .{
        .id = "P26-B01",
        .source = .duo_dynamic,
        .destination = .duo_native,
        .transition = .lower,
        .adaptation = "specialize_or_deopt",
        .representation = "native_layout",
        .effects = "none",
        .ownership_rule = "preserve_or_transfer_explicit",
        .lifetime_rule = "region_check",
        .min_trust = .compiler_reported,
        .failure_policy = "deopt_to_dynamic",
        .cost_hint = "low_when_specialized",
        .eliminability = .specializable,
    },
    .{
        .id = "P26-B02",
        .source = .c_abi,
        .destination = .duo_native,
        .transition = .lift,
        .adaptation = "foreign_descriptor_import",
        .representation = "c_layout",
        .effects = "none",
        .ownership_rule = "foreign_owned",
        .lifetime_rule = "caller_contract",
        .min_trust = .abi_validated,
        .failure_policy = "guard_or_opaque",
        .cost_hint = "medium",
        .eliminability = .fusible,
    },
    .{
        .id = "P26-B03",
        .source = .duo_compile_time,
        .destination = .duo_runtime,
        .transition = .residualize,
        .adaptation = "stage_polymorphic_eval",
        .representation = "residual_value",
        .effects = "none",
        .ownership_rule = "compile_time_owned",
        .lifetime_rule = "stage_bound",
        .min_trust = .compiler_reported,
        .failure_policy = "compile_error",
        .cost_hint = "compile_time",
        .eliminability = .specializable,
    },
    .{
        .id = "P26-B04",
        .source = .wasm_guest,
        .destination = .wasm_host,
        .transition = .serialize,
        .adaptation = "linear_memory_copy",
        .representation = "wasm_memory",
        .effects = "none",
        .ownership_rule = "guest_owned",
        .lifetime_rule = "call_boundary",
        .min_trust = .abi_validated,
        .failure_policy = "trap",
        .cost_hint = "high_copy",
        .eliminability = .removable,
    },
    .{
        .id = "P26-B05",
        .source = .process,
        .destination = .network_rpc,
        .transition = .serialize,
        .adaptation = "ipc_or_rpc",
        .representation = "serialized",
        .effects = "none",
        .ownership_rule = "process_isolated",
        .lifetime_rule = "message_scope",
        .min_trust = .differentially_tested,
        .failure_policy = "retry_or_fail",
        .cost_hint = "high_latency",
        .eliminability = .fusible,
    },
};

/// Adapter chain for elimination analysis (§18 flagship).
pub const AdapterLink = struct {
    from: SemanticDomain,
    to: SemanticDomain,
    adapter: []const u8,
};

pub const example_adapter_chain: []const AdapterLink = &.{
    .{ .from = .rust_abi, .to = .c_abi, .adapter = "rust_to_c_struct" },
    .{ .from = .c_abi, .to = .serialized, .adapter = "c_to_bytes" },
    .{ .from = .serialized, .to = .wasm_guest, .adapter = "bytes_to_wasm_mem" },
    .{ .from = .wasm_guest, .to = .duo_native, .adapter = "wasm_to_descriptor" },
};

pub const AdapterEliminationCriterion = struct {
    id: []const u8,
    criterion: []const u8,
};

pub const elimination_criteria: []const AdapterEliminationCriterion = &.{
    .{ .id = "P26-AE01", .criterion = "semantic equivalence between endpoints" },
    .{ .id = "P26-AE02", .criterion = "layout compatibility" },
    .{ .id = "P26-AE03", .criterion = "ownership compatibility" },
    .{ .id = "P26-AE04", .criterion = "lifetime compatibility" },
    .{ .id = "P26-AE05", .criterion = "effect compatibility" },
    .{ .id = "P26-AE06", .criterion = "alignment + endianness" },
    .{ .id = "P26-AE07", .criterion = "failure equivalence" },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-SB01", .rule = "all cross-domain moves are Boundary records" },
    .{ .id = "P26-SB02", .rule = "optimizer asks eliminability before inserting adapters" },
    .{ .id = "P26-SB03", .rule = "trust lattice gates transformation permissions" },
    .{ .id = "P26-SB04", .rule = "stage transitions use evaluate|lift|lower|residualize|persist|serialize|migrate only" },
    .{ .id = "P26-SB05", .rule = "physical_realization from descriptor identity is boundary metadata" },
};

pub fn trustAtLeast(have: TrustLevel, need: TrustLevel) bool {
    return have.ordinal() >= need.ordinal();
}

pub fn findBoundary(id: []const u8) ?Boundary {
    for (canonical_boundaries) |b| {
        if (std.mem.eql(u8, b.id, id)) return b;
    }
    return null;
}

test "pass26_semantic_boundary: boundaries + trust + adapter chain" {
    try std.testing.expect(canonical_boundaries.len >= 5);
    try std.testing.expect(example_adapter_chain.len >= 4);
    try std.testing.expect(trustAtLeast(.abi_validated, .declared));
    try std.testing.expect(!trustAtLeast(.parsed, .abi_validated));
    try std.testing.expect(findBoundary("P26-B02") != null);
    try std.testing.expect(pass26_descriptor_identity.layerCount() == 4);
}
