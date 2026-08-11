//! Pass 8 — unified evidence model for realization decisions and persistent facts.
//!
//! Canonical owner for evidence classification. Extends Pass 7 `optimization_outcome.Evidence`
//! without duplicating optimization outcome records.
const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");

/// Reliability class for compiler claims (Pass 8 §4.6, §6).
pub const Kind = enum(u8) {
    proven_semantic_fact,
    guarded_fact,
    static_estimate,
    target_model_estimate,
    profile_observation,
    benchmark_measurement,
    production_observation,
    user_assertion,
    foreign_assertion,
    differential_test,
    fuzz_evidence,
    property_test,
    numerical_validation,

    pub fn name(self: Kind) []const u8 {
        return switch (self) {
            .proven_semantic_fact => "proven_semantic_fact",
            .guarded_fact => "guarded_fact",
            .static_estimate => "static_estimate",
            .target_model_estimate => "target_model_estimate",
            .profile_observation => "profile_observation",
            .benchmark_measurement => "benchmark_measurement",
            .production_observation => "production_observation",
            .user_assertion => "user_assertion",
            .foreign_assertion => "foreign_assertion",
            .differential_test => "differential_test",
            .fuzz_evidence => "fuzz_evidence",
            .property_test => "property_test",
            .numerical_validation => "numerical_validation",
        };
    }

    /// Observations must not silently become semantic guarantees.
    pub fn mayAuthorizeOptimization(self: Kind) bool {
        return switch (self) {
            .proven_semantic_fact, .guarded_fact, .differential_test, .property_test, .numerical_validation => true,
            .static_estimate, .target_model_estimate => true,
            .profile_observation, .benchmark_measurement, .production_observation => false,
            .user_assertion, .foreign_assertion => false,
            .fuzz_evidence => false,
        };
    }
};

/// Map Pass 7 optimization evidence into Pass 8 evidence kinds.
pub fn fromOptimizationEvidence(ev: optimization_outcome.Evidence) Kind {
    return switch (ev) {
        .proven => .proven_semantic_fact,
        .guarded => .guarded_fact,
        .assumed => .user_assertion,
        .profiled => .profile_observation,
        .estimated => .static_estimate,
        .measured => .benchmark_measurement,
    };
}

pub const catalog: []const struct {
    id: []const u8,
    kind: Kind,
    reliability: []const u8,
    wired: bool,
} = &.{
    .{ .id = "evidence.proven_fact", .kind = .proven_semantic_fact, .reliability = "highest", .wired = true },
    .{ .id = "evidence.guarded", .kind = .guarded_fact, .reliability = "high_with_fallback", .wired = true },
    .{ .id = "evidence.static_estimate", .kind = .static_estimate, .reliability = "planning_only", .wired = true },
    .{ .id = "evidence.profile", .kind = .profile_observation, .reliability = "non_authoritative", .wired = false },
    .{ .id = "evidence.benchmark", .kind = .benchmark_measurement, .reliability = "measured_local", .wired = true },
    .{ .id = "evidence.user_assertion", .kind = .user_assertion, .reliability = "requires_validation", .wired = true },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (catalog, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"kind\":\"{s}\",\"reliability\":\"",
            .{ row.id, row.kind.name() },
        );
        try jsonEscape(w, row.reliability);
        try w.print("\",\"may_authorize_optimization\":", .{});
        try w.print("{s}", .{if (row.kind.mayAuthorizeOptimization()) "true" else "false"});
        try w.print(",\"wired\":", .{});
        try w.print("{s}", .{if (row.wired) "true" else "false"});
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

test "evidence_record: optimization evidence maps without loss" {
    try std.testing.expectEqual(Kind.proven_semantic_fact, fromOptimizationEvidence(.proven));
    try std.testing.expectEqual(Kind.profile_observation, fromOptimizationEvidence(.profiled));
    try std.testing.expect(!Kind.profile_observation.mayAuthorizeOptimization());
}
