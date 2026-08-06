//! Pass 26 extended closure — initialization, mutability, dynamic value, GC interop.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-runtime-closure-v0";

// --- Initialization (§22 / new #1) ---

pub const InitStage = enum {
    parse_time,
    expand_time,
    semantic_time,
    compile_time,
    link_time,
    load_time,
    startup,
    runtime,
    lazy_first_use,

    pub fn name(self: InitStage) []const u8 {
        return @tagName(self);
    }
};

pub const CycleClass = enum {
    acyclic,
    mutual_recursive_ok,
    illegal_cycle,
    deferred_fixed_point,

    pub fn name(self: CycleClass) []const u8 {
        return @tagName(self);
    }
};

pub const InitNode = struct {
    id: []const u8,
    stage: InitStage,
    effects: []const u8,
    cycle_class: CycleClass,
    may_fail: bool,
    thread_safe_once: bool,
};

pub const init_invariants: []const struct { id: []const u8, rule: []const u8 } = &.{
    .{ .id = "P26-IN01", .rule = "one initialization graph with dependency analysis" },
    .{ .id = "P26-IN02", .rule = "cycle classification before evaluation" },
    .{ .id = "P26-IN03", .rule = "partially initialized state not observable unless explicit" },
    .{ .id = "P26-IN04", .rule = "foreign static constructors participate in graph" },
};

// --- Mutability (§24 / new #3) ---

pub const MutationKind = enum {
    rebind_name,
    mutate_object,
    mutate_field,
    mutate_descriptor_data,
    mutate_semantic_entity,
    mutate_foreign_storage,
    atomic_mutation,
    transaction_mutation,

    pub fn name(self: MutationKind) []const u8 {
        return @tagName(self);
    }
};

pub const FreezeDepth = enum {
    shallow,
    recursive,
    semantic_only,

    pub fn name(self: FreezeDepth) []const u8 {
        return @tagName(self);
    }
};

pub const mutability_invariants: []const struct { id: []const u8, rule: []const u8 } = &.{
    .{ .id = "P26-MU01", .rule = "rebind ≠ field mutation ≠ descriptor revision" },
    .{ .id = "P26-MU02", .rule = "@{} freeze depth explicit; default shallow for M0" },
    .{ .id = "P26-MU03", .rule = "descriptor data mutation requires semantic transaction" },
    .{ .id = "P26-MU04", .rule = "mutation invalidates specialization cache keys" },
};

// --- Dynamic value model (§25 / new #4) ---

pub const DynamicComponent = enum {
    value_representation,
    table_representation,
    call_convention,
    return_pack,
    metatable_lookup,
    boxing_identity,
    gc_ownership,
    dynamic_native_transition,
    equality_hash,
    runtime_descriptor_reflection,

    pub fn name(self: DynamicComponent) []const u8 {
        return @tagName(self);
    }
};

pub const dynamic_invariants: []const struct { id: []const u8, rule: []const u8 } = &.{
    .{ .id = "P26-DY01", .rule = "dynamic representation is one explicit realization, not semantic root" },
    .{ .id = "P26-DY02", .rule = "one owner specification for Lua-compatible dynamic boundary" },
    .{ .id = "P26-DY03", .rule = "dynamic fallback remains valid (ecosystem charter)" },
};

// --- GC / native ownership interop (§26 / new #5) ---

pub const OwnershipDomain = enum {
    gc_heap,
    native_stack,
    arena,
    foreign_handle,
    static_storage,
    device,

    pub fn name(self: OwnershipDomain) []const u8 {
        return @tagName(self);
    }
};

pub const CrossDomainRefPolicy = enum {
    forbidden,
    registered_adapter,
    tracing_contract,
    pin_required,

    pub fn name(self: CrossDomainRefPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const gc_invariants: []const struct { id: []const u8, rule: []const u8 } = &.{
    .{ .id = "P26-GC01", .rule = "cross-domain refs are explicit graph edges with policy" },
    .{ .id = "P26-GC02", .rule = "view pin required when referencing moving GC object from native" },
    .{ .id = "P26-GC03", .rule = "collector profile selectable per runtime; noGC documented" },
};

test "pass26_runtime_closure: init + mutability + dynamic + gc schemas" {
    try std.testing.expect(init_invariants.len >= 4);
    try std.testing.expect(mutability_invariants.len >= 4);
    try std.testing.expect(dynamic_invariants.len >= 3);
    try std.testing.expect(gc_invariants.len >= 3);
    try std.testing.expect(@intFromEnum(MutationKind.rebind_name) != @intFromEnum(MutationKind.mutate_field));
}
