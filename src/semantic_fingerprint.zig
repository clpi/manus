//! Pass 7 — semantic fingerprints for caching, dedupe, and regression detection.
//!
//! Derived from canonical semantic facts, not raw source text.
const std = @import("std");

pub const SCHEMA_VERSION = "semantic-fingerprint-v0";

pub const FingerprintInputs = struct {
    entity_id: []const u8,
    descriptor_deps: ?[]const u8 = null,
    target: ?[]const u8 = null,
    stage: ?[]const u8 = null,
    effects: ?[]const u8 = null,
    constants: ?[]const u8 = null,
    transform_version: ?[]const u8 = null,
};

/// Stable 64-bit fingerprint for a semantic entity at a compiler phase.
pub fn compute(inputs: FingerprintInputs) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(inputs.entity_id);
    hasher.update("|");
    if (inputs.descriptor_deps) |d| {
        hasher.update(d);
        hasher.update("|");
    }
    if (inputs.target) |t| {
        hasher.update(t);
        hasher.update("|");
    }
    if (inputs.stage) |s| {
        hasher.update(s);
        hasher.update("|");
    }
    if (inputs.effects) |e| {
        hasher.update(e);
        hasher.update("|");
    }
    if (inputs.constants) |c| {
        hasher.update(c);
        hasher.update("|");
    }
    if (inputs.transform_version) |v| {
        hasher.update(v);
    }
    return hasher.final();
}

pub fn formatHex(hash: u64, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{x:0>16}", .{hash}) catch "0000000000000000";
}

test "semantic_fingerprint: same inputs same hash" {
    const a = compute(.{ .entity_id = "duo:function:add" });
    const b = compute(.{ .entity_id = "duo:function:add" });
    try std.testing.expectEqual(a, b);
}

test "semantic_fingerprint: target changes hash" {
    const base = compute(.{ .entity_id = "duo:function:matmul" });
    const other = compute(.{ .entity_id = "duo:function:matmul", .target = "native" });
    try std.testing.expect(base != other);
}
