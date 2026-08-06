//! Pass 26 — ABI calling conventions, resources, unwind/stack semantics.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-abi-resource-v0";

pub const CallingConventionKind = enum {
    duo_native,
    c_abi,
    wasm_import,
    wasm_export,
    rust_extern,
    jit_internal,
    process_plugin,
    gpu_kernel,

    pub fn name(self: CallingConventionKind) []const u8 {
        return @tagName(self);
    }
};

pub const CallingConventionDescriptor = struct {
    kind: CallingConventionKind,
    param_classification: []const u8,
    return_pack: []const u8,
    unwind_behavior: []const u8,
    ownership_transfer: []const u8,
    symbol_naming: []const u8,
    target: []const u8,
};

pub const ResourceKind = enum {
    file,
    socket,
    memory_mapping,
    process,
    gpu_buffer,
    lock,
    task,
    foreign_handle,

    pub fn name(self: ResourceKind) []const u8 {
        return @tagName(self);
    }
};

pub const ResourceDescriptor = struct {
    kind: ResourceKind,
    owner: []const u8,
    lifecycle: []const u8,
    effects: []const u8,
    cancellable: bool,
    transfer_rules: []const u8,
};

pub const StackKind = enum {
    semantic_call_stack,
    physical_machine_frames,
    continuation_stack,
    diagnostic_trace,
    foreign_unwind_chain,

    pub fn name(self: StackKind) []const u8 {
        return @tagName(self);
    }
};

pub const UnwindPolicy = enum {
    unwind_on_failure,
    non_unwindable_trap,
    foreign_exception_boundary,
    cleanup_during_unwind,
    tail_call_preserves_trace,

    pub fn name(self: UnwindPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const abi_invariants: []const Invariant = &.{
    .{ .id = "P26-ABI01", .rule = "one calling-convention descriptor unifies native/foreign/Wasm/GPU" },
    .{ .id = "P26-ABI02", .rule = "Ward host adapters consume ABI boundary model" },
};

pub const resource_invariants: []const Invariant = &.{
    .{ .id = "P26-RES01", .rule = "files/sockets/tasks/foreign handles share resource foundation" },
    .{ .id = "P26-RES02", .rule = "resource generalizes lifetime model beyond memory" },
};

pub const unwind_invariants: []const Invariant = &.{
    .{ .id = "P26-UW01", .rule = "five stack kinds distinguished; not conflated" },
    .{ .id = "P26-UW02", .rule = "foreign exceptions stop at registered boundary" },
};

test "pass26_abi_resource: ABI + resource + unwind schemas" {
    try std.testing.expect(@typeInfo(CallingConventionKind).@"enum".field_names.len >= 8);
    try std.testing.expect(@typeInfo(ResourceKind).@"enum".field_names.len >= 8);
    try std.testing.expect(@typeInfo(StackKind).@"enum".field_names.len == 5);
}
