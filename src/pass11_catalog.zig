//! Pass 11 — canonical compiler closure catalog (`duo catalog` → `pass11`).
const std = @import("std");
const backend_identity = @import("backend_identity.zig");
const semantic_ownership = @import("semantic_ownership.zig");
const pass10_repo_audit = @import("pass10_repo_audit.zig");
const target_model = @import("target_model.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");

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

/// Pass 11 Profile A closure: release proof complete; Profile B items remain partial/open.
pub const closure_status: []const u8 = "closed";
pub const closure_profile: []const u8 = "A-c-backend";
pub const closure_date: []const u8 = "2026-08-04";

pub const WorkPackage = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

pub const work_packages: []const WorkPackage = &.{
    .{ .id = "WP-01", .title = "Benchmark-path repair (no forced boxing)", .status = "done", .priority = 1 },
    .{ .id = "WP-02", .title = "Explicit backend identity + silent fallback elimination", .status = "done", .priority = 2 },
    .{ .id = "WP-03", .title = "ARM64 spills and stack frames", .status = "done", .priority = 3 },
    .{ .id = "WP-04", .title = "Native sealed records (memory layout)", .status = "done", .priority = 4 },
    .{ .id = "WP-05", .title = "Native byte slices / Ward substrate", .status = "done", .priority = 5 },
    .{ .id = "WP-06", .title = "Return-pack specialization", .status = "open", .priority = 6 },
    .{ .id = "WP-07", .title = "Closure specialization ladder", .status = "open", .priority = 7 },
    .{ .id = "WP-08", .title = "ELF64 object writer", .status = "open", .priority = 8 },
    .{ .id = "WP-09", .title = "Machine IR extraction", .status = "open", .priority = 9 },
    .{ .id = "WP-10", .title = "Semantic ownership audit", .status = "done", .priority = 10 },
    .{ .id = "WP-11", .title = "Generated runtime partitioning", .status = "open", .priority = 11 },
    .{ .id = "WP-12", .title = "Repository sanitation", .status = "done", .priority = 12 },
    .{ .id = "WP-13", .title = "Reproducible CI + pinned toolchain", .status = "done", .priority = 13 },
    .{ .id = "WP-14", .title = "Bootstrap lexer in Duo", .status = "done", .priority = 14 },
    .{ .id = "WP-15", .title = "Ward decoder no-boxing proof", .status = "partial", .priority = 15 },
    .{ .id = "WP-16", .title = "Lua differential harness", .status = "open", .priority = 16 },
    .{ .id = "WP-17", .title = "Compiler library API boundary", .status = "open", .priority = 17 },
    .{ .id = "WP-18", .title = "Target triple + emit kind model", .status = "done", .priority = 18 },
};

pub const CompletionCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const completion_criteria: []const CompletionCriterion = &.{
    .{ .id = 1, .title = "Benchmark mode allows native_scalar path", .status = "met" },
    .{ .id = 2, .title = "Backend selection explicit (no silent fallback)", .status = "met" },
    .{ .id = 3, .title = "Direct backend precise diagnostics (DNB codes)", .status = "met" },
    .{ .id = 4, .title = "ARM64 spills for >20 live values", .status = "met" },
    .{ .id = 5, .title = "ARM64 sealed record field access", .status = "met" },
    .{ .id = 6, .title = "Native byte slices for Ward", .status = "met" },
    .{ .id = 7, .title = "Ward hot path no-boxing proof", .status = "partial" },
    .{ .id = 8, .title = "Repository root clean", .status = "met" },
    .{ .id = 9, .title = "README claims match evidence", .status = "met" },
    .{ .id = 10, .title = "CI pins toolchain version", .status = "met" },
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
        \\"pass11":{{"pass":11,"mission":"Canonical compiler closure and release proof","schema":"{s}","release_profile":"{s}","closure_status":"{s}","closure_profile":"{s}","closure_date":"{s}","default_backend":"auto","plan":"docs/plans/pass11_release_proof.md","gate":"scripts/pass11_gate.sh","work_packages":[
    , .{ SCHEMA_VERSION, selected_release_profile.name(), closure_status, closure_profile, closure_date });
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
    try w.print("],\"target_model\":", .{});
    try target_model.writeJson(w);
    try w.print(",\"barrier_checks_schema\":\"{s}\",\"barrier_profiles\":[\"pass12_m1_classifier\",\"pass12_m1_sorted_lookup\",\"ward_decode_hot\"],\"barrier_cli\":\"duo dev barrier check\",\"wp15_barrier\":{{\"smoke\":\"scripts/pass11_ward_no_boxing_smoke.sh\",\"profiles\":[\"pass12_m1\",\"pass12_m1_sorted\",\"ward_decode\"],\"m1_proven\":true,\"m1_sorted_proven\":true,\"ward_native\":false}},\"semantic_ownership\":", .{native_barrier_checks.SCHEMA_VERSION});
    try semantic_ownership.writeJson(w);
    try w.print(",\"release_blockers\":[", .{});
    for (pass10_repo_audit.release_blockers, 0..) |rb, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{rb.id});
        try jsonEscape(w, rb.title);
        try w.print("\",\"status\":\"{s}\"}}", .{rb.status});
    }
    try w.print(
        "],\"repo_hygiene\":\"done\",\"pass12_m1\":\"done\",\"pass12_bridge\":\"src/token_semantic.zig\",\"readiness_summary\":{{\"work_packages_done\":{d},\"completion_met\":{d},\"completion_total\":{d},\"closure_status\":\"{s}\"}}}}",
        .{ countWpDone(), countCriteriaMet(), completion_criteria.len, closure_status },
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
