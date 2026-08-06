//! Pass 24 §7 — execution graph entity schemas (design authority; partial wiring).
//!
//! One semantic system for tasks, coroutines, channels, parallel regions, and shell
//! pipelines. Physical realizations are selected by the compiler — not separate languages.
const std = @import("std");
const ast = @import("ast.zig");

pub const SCHEMA_VERSION = "pass24-execution-model-v0";

pub const ExecutionPolicy = enum {
    sequential,
    parallel_eligible,
    spawn,
    all_siblings,
    race,
    race_first_success,
    deterministic,
    replayable,
    detach,
    serial_override,

    pub fn name(self: ExecutionPolicy) []const u8 {
        return @tagName(self);
    }
};

pub const FailurePolicy = enum {
    cancel_siblings,
    collect_all,
    partial_ok,
    transactional,

    pub fn name(self: FailurePolicy) []const u8 {
        return @tagName(self);
    }
};

/// Pass 24 §7.1 — region node in the semantic graph (schema; not yet fully wired).
pub const ExecutionRegion = struct {
    id: u64,
    /// Enclosing function or block stable id.
    parent_stable_id: ?u64 = null,
    policies: []const ExecutionPolicy = &.{},
    failure_policy: FailurePolicy = .cancel_siblings,
    structured_scope: bool = true,
    deterministic: bool = false,
    replayable: bool = false,
};

/// Pass 24 §8.1 — task semantic value (schema).
pub const TaskEntity = struct {
    id: u64,
    region_id: u64,
    call_stable_id: ?u64 = null,
    structured_child: bool = true,
    detached: bool = false,
    cancellation_owned: bool = true,
};

/// Pass 24 §11.1 — stream / channel realization candidates.
pub const StreamEntity = struct {
    id: u64,
    element_descriptor: ?[]const u8 = null,
    buffering: enum { unbounded, bounded, zero } = .bounded,
    backpressure: bool = true,
    may_fuse: bool = false,
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P24-E01", .rule = "one execution graph for all concurrency forms" },
    .{ .id = "P24-E02", .rule = "structured scope owns child tasks by default" },
    .{ .id = "P24-E03", .rule = "effects and alias facts gate parallel overlap" },
    .{ .id = "P24-E04", .rule = "detach requires explicit capability and owner" },
    .{ .id = "P24-E05", .rule = "bare identifiers never auto-invoke (see call model)" },
};

test "pass24_execution_model: schema + call model cross-ref" {
    try std.testing.expectEqualStrings("pass24-execution-model-v0", SCHEMA_VERSION);
    try std.testing.expect(invariants.len >= 5);
    try std.testing.expect(@intFromEnum(ast.InvocationForm.value_reference) >= 0);
}
