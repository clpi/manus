//! Pass 26 M1 — compiler wiring hub (sema, graph, foreign integration).
const std = @import("std");
const types = @import("types.zig");
const pass26_descriptor_identity = @import("pass26_descriptor_identity.zig");
const pass26_semantic_operation = @import("pass26_semantic_operation.zig");
const pass26_semantic_boundary = @import("pass26_semantic_boundary.zig");
const pass26_semantic_domain = @import("pass26_semantic_domain.zig");
const pass26_abi_resource = @import("pass26_abi_resource.zig");
const pass26_runtime_closure = @import("pass26_runtime_closure.zig");
const pass26_descriptor_intern = @import("pass26_descriptor_intern.zig");
const pass26_recursive_descriptor = @import("pass26_recursive_descriptor.zig");
const pass26_hash_order = @import("pass26_hash_order.zig");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");

pub const SCHEMA_VERSION = "pass26-wiring-v0";

pub const ForeignLiftMetadata = struct {
    boundary_id: []const u8,
    calling_conv: pass26_abi_resource.CallingConventionKind,
    min_trust: pass26_semantic_boundary.TrustLevel,
    domains: []const pass26_semantic_domain.DomainMembership,
};

pub const foreign_lift_domains: []const pass26_semantic_domain.DomainMembership = &.{
    .{ .kind = .language, .domain_id = "c" },
    .{ .kind = .trust, .domain_id = "abi_validated" },
    .{ .kind = .target, .domain_id = "native" },
};

/// Pass 26 semantic fingerprint — canonical content hash for interning/specialization.
/// Distinct from `tableShapeIdentityHash` (physical layout) and runtime hash.
pub fn semanticFingerprint(rt: types.ResolvedType) ?u64 {
    return switch (rt) {
        .table_type, .enum_type => blk: {
            const state = descriptorStateFor(rt);
            const sc = if (rt == .table_type) rt.table_type.storage_class else types.StorageClass.sealed;
            const recursion = pass26_recursive_descriptor.RecursionKind.none;
            const completion = pass26_recursive_descriptor.DescriptorCompletion.complete;
            break :blk semanticFingerprintWithAlloc(std.heap.page_allocator, rt, state, sc, recursion, completion) catch null;
        },
        .instantiated => |inst| blk: {
            const fp = semanticFingerprint(inst.base.*);
            if (fp) |base| {
                var h = std.hash.Wyhash.init(0x26F1A90);
                h.update(std.mem.asBytes(&base));
                h.update(std.mem.asBytes(&inst.specialization_key));
                break :blk h.final();
            }
            break :blk null;
        },
        else => {
            if (types.tableShapeIdentityHash(rt)) |shape| return shape;
            if (types.enumShapeIdentityHash(rt)) |shape| return shape;
            return null;
        },
    };
}

fn semanticFingerprintWithAlloc(
    alloc: std.mem.Allocator,
    rt: types.ResolvedType,
    state: pass26_descriptor_identity.DescriptorState,
    sc: types.StorageClass,
    recursion: pass26_recursive_descriptor.RecursionKind,
    completion: pass26_recursive_descriptor.DescriptorCompletion,
) !?u64 {
    _ = sc;
    return try pass26_descriptor_intern.semanticFingerprint(rt, state, completion, recursion, alloc);
}

pub fn interningPolicyFor(rt: types.ResolvedType) pass26_descriptor_identity.InterningPolicy {
    switch (rt) {
        .table_type => |t| {
            if (t.ffi_name != null) return .foreign_fingerprint;
            if (!t.is_sealed and t.storage_class == .dynamic) return .defer_until_sealed;
            if (t.is_sealed or t.storage_class == .native or t.storage_class == .sealed) return .canonicalize_pure;
            return .defer_until_sealed;
        },
        else => return .preserve_declaration,
    }
}

pub fn descriptorStateFor(rt: types.ResolvedType) pass26_descriptor_identity.DescriptorState {
    switch (rt) {
        .table_type => |t| {
            if (t.is_sealed) return .sealed;
            if (t.storage_class == .dynamic) return .open_semantic;
            return .frozen_snapshot;
        },
        else => return .frozen_snapshot,
    }
}

/// Resolve privileged operation by example binding or Pass 23 kernel name.
pub fn resolveSemanticOperation(name: []const u8) ?pass26_semantic_operation.OperationRecord {
    if (pass26_semantic_operation.findByExampleBinding(name)) |rec| return rec;
    if (pass23_protocol_registry.kernelOpFromName(name)) |op| {
        return pass26_semantic_operation.findByKernelOp(op);
    }
    return null;
}

pub fn semanticOperationId(name: []const u8) ?pass26_semantic_operation.SemanticId {
    const rec = resolveSemanticOperation(name) orelse return null;
    return rec.id;
}

/// Metadata attached to C-import foreign functions (P26-B02 boundary).
pub fn foreignLiftMetadata(pass_by: []const u8) ForeignLiftMetadata {
    _ = pass_by;
    return .{
        .boundary_id = "P26-B02",
        .calling_conv = .c_abi,
        .min_trust = .abi_validated,
        .domains = foreign_lift_domains,
    };
}

pub fn findForeignBoundary() ?pass26_semantic_boundary.Boundary {
    return pass26_semantic_boundary.findBoundary("P26-B02");
}

/// Classify simple assignment forms for Pass 26 mutability tracking.
pub fn mutationKindForAssignTarget(target: []const u8, is_index: bool, is_field: bool) pass26_runtime_closure.MutationKind {
    _ = target;
    if (is_index or is_field) return .mutate_field;
    return .rebind_name;
}

/// Whether resolved type uses dynamic Lua representation path.
pub fn requiresDynamicRepresentation(rt: types.ResolvedType) bool {
    return switch (rt) {
        .any, .str => true,
        .table_type => |t| t.storage_class == .dynamic,
        .func => |f| !f.is_native,
        else => false,
    };
}

pub fn hashKindForFingerprint() pass26_hash_order.HashKind {
    return .semantic_fingerprint;
}

pub fn hashKindForShapeId() pass26_hash_order.HashKind {
    return .structural_hash;
}

test "pass26_wiring: semantic op lookup + foreign metadata" {
    try std.testing.expect(semanticOperationId("memory.view") == .memory_view);
    try std.testing.expect(resolveSemanticOperation("memory.view") != null);
    try std.testing.expect(resolveSemanticOperation("release") != null);
    const meta = foreignLiftMetadata("value");
    try std.testing.expectEqualStrings("P26-B02", meta.boundary_id);
    try std.testing.expect(findForeignBoundary() != null);
}
