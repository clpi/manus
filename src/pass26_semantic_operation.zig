//! Pass 26 §3 — canonical semantic operation identity registry.
//!
//! The compiler recognizes stable `Semantic.*` identity — not function name,
//! module path, source spelling, method name, or magic attribute.
//! Pass 23 `KernelOp` maps here as the dynamic-protocol / Lua layer.
const std = @import("std");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");

pub const SCHEMA_VERSION = "pass26-semantic-operation-v0";

/// Stable hierarchical semantic identity (compiler-facing).
pub const SemanticId = enum {
    // Memory
    memory_view,
    memory_address,
    memory_pin,
    // Ownership
    ownership_transfer,
    ownership_release,
    // Tasks
    task_spawn,
    task_join,
    // Shape / conversion
    shape_project,
    convert,
    iterate,
    // Pass 23 kernel ops extend via `kernel_bridge`
    kernel_bridge,

    pub fn dottedPath(self: SemanticId) []const u8 {
        return switch (self) {
            .memory_view => "Semantic.Memory.View",
            .memory_address => "Semantic.Memory.Address",
            .memory_pin => "Semantic.Memory.Pin",
            .ownership_transfer => "Semantic.Ownership.Transfer",
            .ownership_release => "Semantic.Release",
            .task_spawn => "Semantic.Task.Spawn",
            .task_join => "Semantic.Task.Join",
            .shape_project => "Semantic.Shape.Project",
            .convert => "Semantic.Convert",
            .iterate => "Semantic.Iterate",
            .kernel_bridge => "Semantic.Kernel.Bridge",
        };
    }
};

pub const EffectKind = enum {
    none,
    read,
    write,
    allocate,
    deallocate,
    io,
    network,
    process,
    concurrency,
    foreign,
    compile_time,
    unknown,

    pub fn name(self: EffectKind) []const u8 {
        return @tagName(self);
    }
};

pub const ArgRole = enum {
    origin,
    start,
    count,
    target,
    source,
    callee,
    descriptor,
    value,
    context,

    pub fn name(self: ArgRole) []const u8 {
        return @tagName(self);
    }
};

pub const ArgRelationship = struct {
    role: ArgRole,
    required: bool = true,
    /// Descriptor name or category constraint (optional).
    constraint: ?[]const u8 = null,
};

pub const TransformationPermission = enum {
    inline_op,
    specialize,
    fuse,
    eliminate_boundary,
    residualize,
    forbid,

    pub fn name(self: TransformationPermission) []const u8 {
        return @tagName(self);
    }
};

/// Full semantic operation record (registry entry).
pub const OperationRecord = struct {
    id: SemanticId,
    /// Example surface binding — not the identity.
    example_binding: []const u8,
    args: []const ArgRelationship,
    effects: []const EffectKind,
    /// Provenance class for results (Pass 25 categories overlap).
    result_provenance: []const u8,
    transformations: []const TransformationPermission,
    /// Optional Pass 23 kernel op for Lua / dynamic protocol mapping.
    kernel_op: ?pass23_protocol_registry.KernelOp = null,
    fallback: []const u8,
    lsp_label: []const u8,
};

pub const privileged_operations: []const OperationRecord = &.{
    .{
        .id = .memory_view,
        .example_binding = "memory.view",
        .args = &.{
            .{ .role = .origin, .constraint = "owner|pointer" },
            .{ .role = .start },
            .{ .role = .count },
        },
        .effects = &.{ .read },
        .result_provenance = "view",
        .transformations = &.{ .inline_op, .specialize, .eliminate_boundary },
        .kernel_op = .view,
        .fallback = "dynamic_view_protocol",
        .lsp_label = "Create memory view",
    },
    .{
        .id = .memory_address,
        .example_binding = "memory.address",
        .args = &.{.{ .role = .origin, .constraint = "view|owner" }},
        .effects = &.{ .read },
        .result_provenance = "pointer",
        .transformations = &.{ .inline_op, .specialize },
        .kernel_op = .address,
        .fallback = "protocol_address",
        .lsp_label = "Address of origin",
    },
    .{
        .id = .memory_pin,
        .example_binding = "memory.pin",
        .args = &.{.{ .role = .origin, .constraint = "view|owner" }},
        .effects = &.{ .read, .write },
        .result_provenance = "pinned_view",
        .transformations = &.{ .specialize, .forbid },
        .kernel_op = .pin,
        .fallback = "explicit_pin_region",
        .lsp_label = "Pin memory for escape",
    },
    .{
        .id = .ownership_transfer,
        .example_binding = "ownership.transfer",
        .args = &.{.{ .role = .value, .constraint = "owner" }, .{ .role = .target }},
        .effects = &.{ .write, .deallocate },
        .result_provenance = "owner",
        .transformations = &.{ .inline_op, .eliminate_boundary },
        .kernel_op = .move,
        .fallback = "copy_on_transfer",
        .lsp_label = "Transfer ownership",
    },
    .{
        .id = .task_spawn,
        .example_binding = "task.spawn",
        .args = &.{.{ .role = .callee }},
        .effects = &.{ .concurrency, .allocate },
        .result_provenance = "task_handle",
        .transformations = &.{ .specialize, .residualize },
        .kernel_op = null,
        .fallback = "sequential_inline",
        .lsp_label = "Spawn task",
    },
    .{
        .id = .task_join,
        .example_binding = "task.join",
        .args = &.{.{ .role = .value, .constraint = "task_handle" }},
        .effects = &.{ .concurrency, .read },
        .result_provenance = "value",
        .transformations = &.{ .inline_op, .specialize },
        .kernel_op = .await,
        .fallback = "blocking_wait",
        .lsp_label = "Join task",
    },
    .{
        .id = .shape_project,
        .example_binding = "shape.project",
        .args = &.{.{ .role = .descriptor }, .{ .role = .target, .required = false }},
        .effects = &.{ .read, .compile_time },
        .result_provenance = "descriptor",
        .transformations = &.{ .inline_op, .specialize, .fuse },
        .kernel_op = null,
        .fallback = "runtime_shape_check",
        .lsp_label = "Project descriptor shape",
    },
    .{
        .id = .convert,
        .example_binding = "convert",
        .args = &.{.{ .role = .value }, .{ .role = .target, .constraint = "descriptor" }},
        .effects = &.{ .read },
        .result_provenance = "value",
        .transformations = &.{ .inline_op, .specialize, .eliminate_boundary },
        .kernel_op = .to,
        .fallback = "adapter_insertion",
        .lsp_label = "Convert value",
    },
    .{
        .id = .iterate,
        .example_binding = "iterate",
        .args = &.{.{ .role = .value }, .{ .role = .callee, .required = false }},
        .effects = &.{ .read, .concurrency },
        .result_provenance = "iterator",
        .transformations = &.{ .inline_op, .specialize, .fuse },
        .kernel_op = .iterate,
        .fallback = "index_loop",
        .lsp_label = "Iterate collection",
    },
    .{
        .id = .ownership_release,
        .example_binding = "release",
        .args = &.{.{ .role = .value, .constraint = "owner|view" }},
        .effects = &.{ .deallocate },
        .result_provenance = "none",
        .transformations = &.{ .inline_op, .eliminate_boundary },
        .kernel_op = .drop,
        .fallback = "deferred_drop",
        .lsp_label = "Release resource",
    },
};

pub const RejectedPattern = struct {
    id: []const u8,
    pattern: []const u8,
    reason: []const u8,
};

pub const rejected_privilege_patterns: []const RejectedPattern = &.{
    .{ .id = "P26-OP-R01", .pattern = "user:set(...)", .reason = "privilege by spelling" },
    .{ .id = "P26-OP-R02", .pattern = "descriptor:with(...)", .reason = "privilege by spelling" },
    .{ .id = "P26-OP-R03", .pattern = "value:take()", .reason = "privilege by spelling" },
    .{ .id = "P26-OP-R04", .pattern = "@magic intrinsic attribute", .reason = "use Semantic.* registry" },
    .{ .id = "P26-OP-R05", .pattern = "module-path-only intrinsics", .reason = "stable semantic identity" },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-OP01", .rule = "compiler resolves Semantic.* identity, not surface spelling" },
    .{ .id = "P26-OP02", .rule = "every privileged op has effects + provenance + fallback" },
    .{ .id = "P26-OP03", .rule = "KernelOp maps to registry; KernelOp is not the identity" },
    .{ .id = "P26-OP04", .rule = "LSP/MCP present stable semantic labels from registry" },
    .{ .id = "P26-OP05", .rule = "library functions and @comp.* share one lookup table" },
};

pub fn findBySemanticId(id: SemanticId) ?OperationRecord {
    for (privileged_operations) |rec| {
        if (rec.id == id) return rec;
    }
    return null;
}

pub fn findByExampleBinding(binding: []const u8) ?OperationRecord {
    for (privileged_operations) |rec| {
        if (std.mem.eql(u8, rec.example_binding, binding)) return rec;
    }
    return null;
}

pub fn findByKernelOp(op: pass23_protocol_registry.KernelOp) ?OperationRecord {
    for (privileged_operations) |rec| {
        if (rec.kernel_op == op) return rec;
    }
    return null;
}

test "pass26_semantic_operation: privileged ops + rejected patterns" {
    const view = findBySemanticId(.memory_view).?;
    try std.testing.expectEqualStrings("Semantic.Memory.View", view.id.dottedPath());
    try std.testing.expect(view.kernel_op == .view);
    try std.testing.expect(findByExampleBinding("memory.view") != null);
    try std.testing.expect(findByKernelOp(.drop) != null);
    try std.testing.expect(rejected_privilege_patterns.len >= 5);
    try std.testing.expect(invariants.len >= 5);
    try std.testing.expect(privileged_operations.len >= 10);
}
