//! Pass 26 §4 — protocol attachment without namespace pollution.
//!
//! Relationships live in the semantic graph: descriptor + protocol identity + callable.
//! `.protocols` tables are not magical by name.
const std = @import("std");
const pass23_protocol_registry = @import("pass23_protocol_registry.zig");
const pass26_semantic_operation = @import("pass26_semantic_operation.zig");

pub const SCHEMA_VERSION = "pass26-protocol-attachment-v0";

/// Stable protocol identity (distinct from KernelOp canonical name).
pub const ProtocolId = enum {
    format,
    debug_repr,
    add,
    subtract,
    multiply,
    divide,
    equal,
    compare,
    index,
    assign,
    call,
    iterate,
    convert_to,
    convert_from,
    clone,
    drop,
    length,
    contains,

    pub fn dottedPath(self: ProtocolId) []const u8 {
        return switch (self) {
            .format => "Protocol.Format",
            .debug_repr => "Protocol.Debug",
            .add => "Protocol.Add",
            .subtract => "Protocol.Subtract",
            .multiply => "Protocol.Multiply",
            .divide => "Protocol.Divide",
            .equal => "Protocol.Equal",
            .compare => "Protocol.Compare",
            .index => "Protocol.Index",
            .assign => "Protocol.Assign",
            .call => "Protocol.Call",
            .iterate => "Protocol.Iterate",
            .convert_to => "Protocol.Convert.To",
            .convert_from => "Protocol.Convert.From",
            .clone => "Protocol.Clone",
            .drop => "Protocol.Drop",
            .length => "Protocol.Length",
            .contains => "Protocol.Contains",
        };
    }
};

pub const AttachmentKind = enum {
    /// Graph edge only — no surface field.
    semantic_graph,
    /// Explicit @comp.protocol registration.
    compiler_directive,
    /// Derived from @derive trait (Pass 23).
    derive_trait,
    /// Foreign operator mapping.
    foreign_operator,
    /// Lifecycle hook.
    lifecycle,

    pub fn name(self: AttachmentKind) []const u8 {
        return @tagName(self);
    }
};

/// One protocol implementation bound to a descriptor type.
pub const ProtocolAttachment = struct {
    protocol_id: ProtocolId,
    /// Callable binding name or stable graph node ref (not the identity).
    implementation: []const u8,
    kind: AttachmentKind,
    /// Pass 23 kernel op when Lua metamethod applies.
    kernel_op: ?pass23_protocol_registry.KernelOp = null,
    /// Optional semantic operation when attachment is privileged.
    semantic_op: ?pass26_semantic_operation.SemanticId = null,
};

/// Example attachment set for documentation / gate proofs.
pub const example_point_attachments: []const ProtocolAttachment = &.{
    .{ .protocol_id = .format, .implementation = "format_point", .kind = .compiler_directive, .kernel_op = .format, .semantic_op = null },
    .{ .protocol_id = .add, .implementation = "add_points", .kind = .semantic_graph, .kernel_op = .add, .semantic_op = null },
    .{ .protocol_id = .equal, .implementation = "eq_points", .kind = .derive_trait, .kernel_op = .equal, .semantic_op = null },
};

pub const CompilerDirectiveForm = struct {
    /// `@comp.protocol Point, Protocol.Format, format_point`
    directive: []const u8,
    descriptor: []const u8,
    protocol: ProtocolId,
    implementation: []const u8,
};

pub const example_directives: []const CompilerDirectiveForm = &.{
    .{ .directive = "@comp.protocol", .descriptor = "Point", .protocol = .format, .implementation = "format_point" },
};

pub const RejectedPattern = struct {
    id: []const u8,
    pattern: []const u8,
    reason: []const u8,
};

pub const rejected_patterns: []const RejectedPattern = &.{
    .{ .id = "P26-PA-R01", .pattern = "Point.protocols as magical field", .reason = ".protocols not magical by name; graph owns edges" },
    .{ .id = "P26-PA-R02", .pattern = "__add on descriptor table directly", .reason = "attach via protocol identity + graph" },
    .{ .id = "P26-PA-R03", .pattern = "separate Lua + Duo protocol registries", .reason = "one attachment model; Lua is projection" },
    .{ .id = "P26-PA-R04", .pattern = "method name = protocol identity", .reason = "Protocol.* stable ID" },
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-PA01", .rule = "protocol attachment is graph edge, not ordinary field" },
    .{ .id = "P26-PA02", .rule = "Lua metamethods project from attachment table" },
    .{ .id = "P26-PA03", .rule = "foreign operators map to Protocol.* identity" },
    .{ .id = "P26-PA04", .rule = "@comp.protocol is explicit; compact syntax follows architecture" },
    .{ .id = "P26-PA05", .rule = "Pass 23 lua_aliases remain compatibility projection layer" },
};

pub fn protocolFromKernel(op: pass23_protocol_registry.KernelOp) ?ProtocolId {
    return switch (op) {
        .format => .format,
        .debug => .debug_repr,
        .add => .add,
        .subtract => .subtract,
        .multiply => .multiply,
        .divide => .divide,
        .equal => .equal,
        .compare, .partial_compare => .compare,
        .index => .index,
        .assign => .assign,
        .call => .call,
        .iterate => .iterate,
        .to => .convert_to,
        .from => .convert_from,
        .clone => .clone,
        .drop => .drop,
        .length => .length,
        .contains => .contains,
        else => null,
    };
}

pub fn luaMetamethodForAttachment(att: ProtocolAttachment) ?[]const u8 {
    const op = att.kernel_op orelse return null;
    return pass23_protocol_registry.luaMetamethodForKernel(op);
}

test "pass26_protocol_attachment: point example + kernel bridge" {
    try std.testing.expectEqualStrings("Protocol.Format", ProtocolId.format.dottedPath());
    try std.testing.expect(example_point_attachments.len >= 3);
    try std.testing.expect(protocolFromKernel(.add) == .add);
    const fmt = example_point_attachments[0];
    try std.testing.expectEqualStrings("__tostring", luaMetamethodForAttachment(fmt).?);
    try std.testing.expect(rejected_patterns.len >= 4);
}
