//! Pass 11 — canonical compiler closure catalog (`duo catalog` → `pass11`).
const std = @import("std");
const backend_identity = @import("backend_identity.zig");
const semantic_ownership = @import("semantic_ownership.zig");
const pass10_repo_audit = @import("pass10_repo_audit.zig");

pub const SCHEMA_VERSION = "pass11-catalog-v0";

pub const ReleaseProfile = enum {
    profile_a_c_backend,
    profile_b_direct_backend,

    pub fn name(self: ReleaseProfile) []const u8 {
        return switch (self) {
            .profile_a_c_backend => "A-c-backend",
            .profile_b_direct_backend => "B-direct-backend",
        };
    }
};

/// Pass 11 selected release profile (honest first release).
pub const selected_release_profile: ReleaseProfile = .profile_a_c_backend;

pub const WorkPackage = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

pub const work_packages: []const WorkPackage = &.{
    .{ .id = "WP-01", .title = "Benchmark-path repair (no forced boxing)", .status = "partial", .priority = 1 },
    .{ .id = "WP-02", .title = "Explicit backend identity + silent fallback elimination", .status = "partial", .priority = 2 },
    .{ .id = "WP-03", .title = "ARM64 spills and stack frames", .status = "partial", .priority = 3 },
    .{ .id = "WP-04", .title = "Native sealed records (memory layout)", .status = "open", .priority = 4 },
    .{ .id = "WP-05", .title = "Native byte slices / Ward substrate", .status = "partial", .priority = 5 },
    .{ .id = "WP-06", .title = "Return-pack specialization", .status = "open", .priority = 6 },
    .{ .id = "WP-07", .title = "Closure specialization ladder", .status = "open", .priority = 7 },
    .{ .id = "WP-08", .title = "ELF64 object writer", .status = "open", .priority = 8 },
    .{ .id = "WP-09", .title = "Machine IR extraction", .status = "open", .priority = 9 },
    .{ .id = "WP-10", .title = "Semantic ownership audit", .status = "partial", .priority = 10 },
    .{ .id = "WP-11", .title = "Generated runtime partitioning", .status = "open", .priority = 11 },
    .{ .id = "WP-12", .title = "Repository sanitation", .status = "partial", .priority = 12 },
    .{ .id = "WP-13", .title = "Reproducible CI + pinned toolchain", .status = "open", .priority = 13 },
    .{ .id = "WP-14", .title = "Bootstrap lexer in Duo", .status = "partial", .priority = 14 },
    .{ .id = "WP-15", .title = "Ward decoder no-boxing proof", .status = "partial", .priority = 15 },
    .{ .id = "WP-16", .title = "Lua differential harness", .status = "open", .priority = 16 },
    .{ .id = "WP-17", .title = "Compiler library API boundary", .status = "open", .priority = 17 },
    .{ .id = "WP-18", .title = "Target triple + emit kind model", .status = "open", .priority = 18 },
};

pub const CompletionCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const completion_criteria: []const CompletionCriterion = &.{
    .{ .id = 1, .title = "Benchmark mode allows native_scalar path", .status = "partial" },
    .{ .id = 2, .title = "Backend selection explicit (no silent fallback)", .status = "partial" },
    .{ .id = 3, .title = "Direct backend precise diagnostics (DNB codes)", .status = "partial" },
    .{ .id = 4, .title = "ARM64 spills for >20 live values", .status = "open" },
    .{ .id = 5, .title = "ARM64 sealed record field access", .status = "open" },
    .{ .id = 6, .title = "Native byte slices for Ward", .status = "partial" },
    .{ .id = 7, .title = "Ward hot path no-boxing proof", .status = "partial" },
    .{ .id = 8, .title = "Repository root clean", .status = "partial" },
    .{ .id = 9, .title = "README claims match evidence", .status = "partial" },
    .{ .id = 10, .title = "CI pins toolchain version", .status = "open" },
};

fn countWpDone() usize {
    var n: usize = 0;
    for (work_packages) |wp| {
        if (std.mem.eql(u8, wp.status, "done")) n += 1;
    }
    return n;
}

fn countCriteriaMet() usize {
    var n: usize = 0;
    for (completion_criteria) |c| {
        if (std.mem.eql(u8, c.status, "met") or std.mem.eql(u8, c.status, "done")) n += 1;
    }
    return n;
}

pub fn writePass11Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass11":{{"pass":11,"mission":"Canonical compiler closure and release proof","schema":"{s}","release_profile":"{s}","default_backend":"c","plan":"docs/plans/pass11_release_proof.md","work_packages":[
    , .{ SCHEMA_VERSION, selected_release_profile.name() });
    for (work_packages, 0..) |wp, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{wp.id});
        try jsonEscape(w, wp.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d}}}", .{ wp.status, wp.priority });
    }
    try w.print("],\"completion_criteria\":[", .{});
    for (completion_criteria, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":{d},\"title\":\"", .{c.id});
        try jsonEscape(w, c.title);
        try w.print("\",\"status\":\"{s}\"}}", .{c.status});
    }
    try w.print("],\"bench_backends\":[", .{});
    const bench_backends = [_]backend_identity.BenchBackend{
        .c_dynamic,
        .c_specialized,
        .direct,
    };
    for (bench_backends, 0..) |bb, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"{s}\"", .{bb.name()});
    }
    try w.print("],\"semantic_ownership\":", .{});
    try semantic_ownership.writeJson(w);
    try w.print(",\"release_blockers\":[", .{});
    for (pass10_repo_audit.release_blockers, 0..) |rb, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{rb.id});
        try jsonEscape(w, rb.title);
        try w.print("\",\"status\":\"{s}\"}}", .{rb.status});
    }
    try w.print("],\"repo_hygiene\":\"partial\",\"pass12_m1\":\"partial\",\"pass12_bridge\":\"src/token_semantic.zig\",\"readiness_summary\":{{\"work_packages_done\":{d},\"completion_met\":{d},\"completion_total\":{d}}}}}",
        .{ countWpDone(), countCriteriaMet(), completion_criteria.len },
    );
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '\\', '"' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "pass11_catalog: writePass11Json structure" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writePass11Json(&buf.writer);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "WP-01") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "semantic_ownership") != null);
}
