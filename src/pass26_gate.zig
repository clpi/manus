//! Pass 26 native gate — foundational semantic closure M0 proofs.
const std = @import("std");
const pass26_catalog = @import("pass26_catalog.zig");
const pass26_semantic_operation = @import("pass26_semantic_operation.zig");
const pass26_protocol_attachment = @import("pass26_protocol_attachment.zig");
const pass26_descriptor_identity = @import("pass26_descriptor_identity.zig");
const pass26_semantic_boundary = @import("pass26_semantic_boundary.zig");
const pass26_decision_registry = @import("pass26_decision_registry.zig");
const pass26_semantic_domain = @import("pass26_semantic_domain.zig");
const pass26_runtime_closure = @import("pass26_runtime_closure.zig");
const pass26_recursive_descriptor = @import("pass26_recursive_descriptor.zig");
const pass26_hash_order = @import("pass26_hash_order.zig");
const pass26_evidence = @import("pass26_evidence.zig");
const pass26_abi_resource = @import("pass26_abi_resource.zig");
const pass26_transform_meta = @import("pass26_transform_meta.zig");
const pass26_wiring = @import("pass26_wiring.zig");
const pass26_descriptor_intern = @import("pass26_descriptor_intern.zig");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");
const types = @import("types.zig");

pub const GateError = error{ GateFailed };

pub fn validatePass26Catalog() GateError!void {
    if (!std.mem.eql(u8, pass26_catalog.SCHEMA_VERSION, "pass26-catalog-v1")) return error.GateFailed;
    if (pass26_catalog.workstreams.len != 52) return error.GateFailed;
    if (pass26_catalog.completion_gates.len != 28) return error.GateFailed;
    if (pass26_catalog.five_foundations.len != 5) return error.GateFailed;
    if (pass26_catalog.ten_closure_priorities.len != 10) return error.GateFailed;
}

pub fn proveTenClosurePriorities() GateError!void {
    if (!std.mem.eql(u8, pass26_catalog.ten_closure_priorities[0].name, "Descriptor normalization, identity, and recursion")) return error.GateFailed;
    if (std.mem.indexOf(u8, pass26_catalog.ten_closure_priorities[0].workstreams, "P26-WS23") == null) return error.GateFailed;
    if (pass26_catalog.ten_closure_priorities[9].rank != 10) return error.GateFailed;
}

pub fn proveFiveFoundationsOrdered() GateError!void {
    if (!std.mem.eql(u8, pass26_catalog.five_foundations[0].workstreams, "P26-WS01")) return error.GateFailed;
    if (!std.mem.eql(u8, pass26_catalog.five_foundations[4].workstreams, "P26-WS20")) return error.GateFailed;
}

pub fn proveSemanticOperationRegistry() GateError!void {
    if (!std.mem.eql(u8, pass26_semantic_operation.SCHEMA_VERSION, "pass26-semantic-operation-v0")) return error.GateFailed;
    const view = pass26_semantic_operation.findBySemanticId(.memory_view) orelse return error.GateFailed;
    if (!std.mem.eql(u8, view.id.dottedPath(), "Semantic.Memory.View")) return error.GateFailed;
    if (pass26_semantic_operation.rejected_privilege_patterns.len < 5) return error.GateFailed;
    // Pass 23 bridge: kernel op maps but is not identity
    const via_kernel = pass26_semantic_operation.findByKernelOp(.view) orelse return error.GateFailed;
    if (via_kernel.id != .memory_view) return error.GateFailed;
}

pub fn proveProtocolAttachmentModel() GateError!void {
    if (!std.mem.eql(u8, pass26_protocol_attachment.SCHEMA_VERSION, "pass26-protocol-attachment-v0")) return error.GateFailed;
    if (pass26_protocol_attachment.example_point_attachments.len < 3) return error.GateFailed;
    const fmt = pass26_protocol_attachment.example_point_attachments[0];
    if (pass26_protocol_attachment.luaMetamethodForAttachment(fmt)) |mm| {
        if (!std.mem.eql(u8, mm, "__tostring")) return error.GateFailed;
    } else return error.GateFailed;
    if (pass26_protocol_attachment.protocolFromKernel(.add) != .add) return error.GateFailed;
}

pub fn proveDescriptorIdentityLayers() GateError!void {
    if (!std.mem.eql(u8, pass26_descriptor_identity.SCHEMA_VERSION, "pass26-descriptor-identity-v0")) return error.GateFailed;
    if (pass26_descriptor_identity.layerCount() != 4) return error.GateFailed;
    if (pass26_descriptor_identity.equalityKindCount() != 8) return error.GateFailed;
    if (pass26_descriptor_identity.snapshot_rules.len < 4) return error.GateFailed;
    // Pair i32,str pure interning scenario
    var saw_pair: bool = false;
    for (pass26_descriptor_identity.example_scenarios) |ex| {
        if (std.mem.eql(u8, ex.id, "P26-EX03") and ex.fingerprint_same and ex.runtime_same) saw_pair = true;
    }
    if (!saw_pair) return error.GateFailed;
}

pub fn proveSemanticBoundaryUnifier() GateError!void {
    if (!std.mem.eql(u8, pass26_semantic_boundary.SCHEMA_VERSION, "pass26-semantic-boundary-v0")) return error.GateFailed;
    if (pass26_semantic_boundary.canonical_boundaries.len < 5) return error.GateFailed;
    if (pass26_semantic_boundary.example_adapter_chain.len < 4) return error.GateFailed;
    if (!pass26_semantic_boundary.trustAtLeast(.abi_validated, .declared)) return error.GateFailed;
    const b = pass26_semantic_boundary.findBoundary("P26-B02") orelse return error.GateFailed;
    if (b.source != .c_abi or b.destination != .duo_native) return error.GateFailed;
}

pub fn proveDecisionRegistry() GateError!void {
    if (!std.mem.eql(u8, pass26_decision_registry.SCHEMA_VERSION, "pass26-decision-registry-v0")) return error.GateFailed;
    if (pass26_decision_registry.contradictions.len < 11) return error.GateFailed;
    const d09 = pass26_decision_registry.findDecision("P26-D09") orelse return error.GateFailed;
    if (d09.status != .rejected) return error.GateFailed;
    const d11 = pass26_decision_registry.findDecision("P26-D11") orelse return error.GateFailed;
    if (d11.status != .accepted) return error.GateFailed;
    if (pass26_decision_registry.decisionsWithStatus(.under_grammar_audit) < 3) return error.GateFailed;
}

pub fn provePass23ProtocolRegistryStillAuthority() GateError!void {
    if (pass23_protocol_registry.kernelOpCount() < 40) return error.GateFailed;
    if (pass23_protocol_registry.canonicalOfLuaMetamethod("__add")) |c| {
        if (!std.mem.eql(u8, c, "add")) return error.GateFailed;
    } else return error.GateFailed;
}

pub fn proveExtendedClosureSchemas() GateError!void {
    if (pass26_semantic_domain.domainKindCount() != 9) return error.GateFailed;
    if (!std.mem.eql(u8, pass26_runtime_closure.SCHEMA_VERSION, "pass26-runtime-closure-v0")) return error.GateFailed;
    if (pass26_recursive_descriptor.invariants.len < 5) return error.GateFailed;
    if (@typeInfo(pass26_hash_order.HashKind).@"enum".field_names.len != 6) return error.GateFailed;
    if (pass26_evidence.certaintyTermCount() != 10) return error.GateFailed;
    if (@typeInfo(pass26_abi_resource.StackKind).@"enum".field_names.len != 5) return error.GateFailed;
    if (pass26_transform_meta.meta_invariants.len >= 4) {} else return error.GateFailed;
}

pub fn proveM1WiringHub() GateError!void {
    if (!std.mem.eql(u8, pass26_wiring.SCHEMA_VERSION, "pass26-wiring-v0")) return error.GateFailed;
    if (pass26_wiring.semanticOperationId("memory.view") != .memory_view) return error.GateFailed;
    const meta = pass26_wiring.foreignLiftMetadata("value");
    if (!std.mem.eql(u8, meta.boundary_id, "P26-B02")) return error.GateFailed;
    if (pass26_wiring.findForeignBoundary() == null) return error.GateFailed;
}

pub fn proveDescriptorInternRegistry() GateError!void {
    if (!std.mem.eql(u8, pass26_descriptor_intern.SCHEMA_VERSION, "pass26-descriptor-intern-v1")) return error.GateFailed;
    var fields = [_]types.FieldType{
        .{ .name = "first", .typ = .i32 },
        .{ .name = "second", .typ = .str },
    };
    const rt: types.ResolvedType = .{ .table_type = .{ .fields = &fields, .storage_class = .native, .is_sealed = true } };
    var reg = pass26_descriptor_intern.Registry.init(std.heap.page_allocator);
    const x = reg.registerAlias("a.duo", "X", .{ .line = 1, .col = 1 }, rt, .native) catch return error.GateFailed;
    const y = reg.registerAlias("a.duo", "Y", .{ .line = 2, .col = 1 }, rt, .native) catch return error.GateFailed;
    const rx = reg.get(x) orelse return error.GateFailed;
    const ry = reg.get(y) orelse return error.GateFailed;
    if (rx.semantic_fingerprint != ry.semantic_fingerprint) return error.GateFailed;
    if (rx.declaration_identity == ry.declaration_identity) return error.GateFailed;
    if (rx.intern_slot == null or rx.intern_slot != ry.intern_slot) return error.GateFailed;
    if (!ry.runtime_interned) return error.GateFailed;
}

pub fn validatePass26Gate(_: std.mem.Allocator) GateError!void {
    try validatePass26Catalog();
    try proveFiveFoundationsOrdered();
    try proveTenClosurePriorities();
    try proveSemanticOperationRegistry();
    try proveProtocolAttachmentModel();
    try proveDescriptorIdentityLayers();
    try proveSemanticBoundaryUnifier();
    try proveDecisionRegistry();
    try proveExtendedClosureSchemas();
    try proveM1WiringHub();
    try proveDescriptorInternRegistry();
    try provePass23ProtocolRegistryStillAuthority();
}

test "pass26_gate: M0 foundational closure proofs" {
    try validatePass26Gate(std.testing.allocator);
}
