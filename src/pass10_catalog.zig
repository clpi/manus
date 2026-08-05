//! Pass 10 — public repository readiness catalog export (`duo catalog` → `pass10`).
const std = @import("std");
const pass9_catalog = @import("pass9_catalog.zig");
const pass10_repo_audit = @import("pass10_repo_audit.zig");

pub const SCHEMA_VERSION = "pass10-catalog-v0";

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass10_public_repository_readiness.md";
    pub const pass9 = pass9_catalog.CatalogPaths.plan;
    pub const matrix_owner = "src/pass10_repo_audit.zig";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    area: []const u8,
};

pub const milestones: []const struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
} = &.{
    .{ .id = "P10-M0", .title = "Readiness matrix + initial pollution audit", .status = "partial" },
    .{ .id = "P10-M1", .title = "Root + canonical doc consolidation", .status = "partial" },
    .{ .id = "P10-M2", .title = "File necessity purge (tracked tree)", .status = "open" },
    .{ .id = "P10-M3", .title = "Markdown compression + archive pass plans", .status = "open" },
    .{ .id = "P10-M4", .title = "Source/comment density audit (src/)", .status = "open" },
    .{ .id = "P10-M5", .title = "Public safety + licensing gate", .status = "open" },
};

pub const workstreams: []const Workstream = &.{
    .{ .id = "P10-WS1", .title = "Public quality audit (A15)", .status = "open", .priority = 1, .area = "audit" },
    .{ .id = "P10-WS2", .title = "File necessity audit (A16)", .status = "open", .priority = 2, .area = "audit" },
    .{ .id = "P10-WS3", .title = "Markdown compression (A17)", .status = "partial", .priority = 3, .area = "docs" },
    .{ .id = "P10-WS4", .title = "Source density + comments (A18)", .status = "open", .priority = 4, .area = "source" },
    .{ .id = "P10-WS5", .title = "Safety + licensing (A19)", .status = "partial", .priority = 5, .area = "legal" },
    .{ .id = "P10-WS6", .title = "Root + README gate", .status = "partial", .priority = 6, .area = "root" },
    .{ .id = "P10-WS7", .title = "Example corpus curation", .status = "open", .priority = 7, .area = "examples" },
    .{ .id = "P10-WS8", .title = "Test hierarchy realignment", .status = "open", .priority = 8, .area = "tests" },
    .{ .id = "P10-WS9", .title = ".gitignore + untracked noise", .status = "open", .priority = 9, .area = "hygiene" },
    .{ .id = "P10-WS10", .title = "Pass-shaped naming cleanup", .status = "open", .priority = 10, .area = "hierarchy" },
};

pub const presentation_standard: []const struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
} = &.{
    .{ .id = "PRS-1", .title = "Root repository experience", .status = "partial" },
    .{ .id = "PRS-2", .title = "Documentation hierarchy", .status = "open" },
    .{ .id = "PRS-3", .title = "Current vs experimental vs historical labeling", .status = "partial" },
    .{ .id = "PRS-4", .title = "Examples as executable documentation", .status = "partial" },
    .{ .id = "PRS-5", .title = "Test hierarchy by semantic responsibility", .status = "open" },
    .{ .id = "PRS-6", .title = "Generated files policy", .status = "partial" },
    .{ .id = "PRS-7", .title = "Scripts and tooling durability", .status = "partial" },
    .{ .id = "PRS-8", .title = "Configuration minimalism", .status = "partial" },
    .{ .id = "PRS-9", .title = "Public history hygiene", .status = "open" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writePass10Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass10":{{"mission":"public repository readiness + information density + structural coherence","schema":"{s}","matrix_schema":"{s}","catalogs":{{
    , .{ SCHEMA_VERSION, pass10_repo_audit.SCHEMA_VERSION });
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"pass9\":\"", .{});
    try jsonEscape(w, CatalogPaths.pass9);
    try w.print("\",\"matrix_owner\":\"", .{});
    try jsonEscape(w, CatalogPaths.matrix_owner);
    try w.print("\"}},\"governing_rule\":\"The repository must communicate the same qualities Duo promises: compactness, semantic density, architectural convergence, and absence of unnecessary ceremony\",\"release_invariants\":", .{});
    try pass10_repo_audit.writeInvariantsJson(w);
    try w.print(",\"mandatory_audits\":", .{});
    try pass10_repo_audit.writeAuditsJson(w);
    try w.print(",\"release_blockers\":", .{});
    try pass10_repo_audit.writeBlockersJson(w);
    try w.print(",\"acceptance_criteria\":", .{});
    try pass10_repo_audit.writeAcceptanceJson(w);
    try w.print(",\"pollution_findings\":", .{});
    try pass10_repo_audit.writePollutionJson(w);
    try w.print(",\"canonical_doc_targets\":", .{});
    try pass10_repo_audit.writeCanonicalDocsJson(w);
    try w.print(",\"repo_audit_findings\":", .{});
    try pass10_repo_audit.writeFindingsJson(w);
    try w.print(",\"milestones\":[", .{});
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{m.id});
        try jsonEscape(w, m.title);
        try w.print("\",\"status\":\"{s}\"}}", .{m.status});
    }
    try w.print("],\"workstreams\":[", .{});
    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"area\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.area,
        });
    }
    try w.print("],\"presentation_standard\":[", .{});
    for (presentation_standard, 0..) |ps, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ps.id});
        try jsonEscape(w, ps.title);
        try w.print("\",\"status\":\"{s}\"}}", .{ps.status});
    }
    try w.print("],\"readiness_summary\":{{\"release_invariants_met\":{d},\"acceptance_met\":{d},\"acceptance_partial\":{d},\"pollution_open\":{d},\"blockers_critical_open\":{d},\"blockers_high_open\":{d},\"canonical_docs_missing\":{d}}},\"agent_output_required\":[\"files_added\",\"files_removed\",\"files_renamed\",\"files_merged\",\"docs_added\",\"docs_removed\",\"comments_added\",\"comments_removed\",\"duplicate_logic_removed\",\"hierarchy_impact\",\"public_readiness_impact\",\"new_permanent_concept\",\"new_file_justification\"]}}",
        .{
            pass10_repo_audit.countInvariantsMet(),
            pass10_repo_audit.countAcceptanceByStatus("met"),
            pass10_repo_audit.countAcceptanceByStatus("partial"),
            pass10_repo_audit.countPollutionOpen(),
            pass10_repo_audit.countBlockersOpen(.critical),
            pass10_repo_audit.countBlockersOpen(.high),
            pass10_repo_audit.countCanonicalDocsMissing(),
        },
    );
}

test "pass10_catalog: writePass10Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass10Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass10\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "3.14") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "A15") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "acceptance_criteria") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pollution_findings") != null);
}

test "pass10_catalog: acceptance criteria count is 20" {
    try std.testing.expect(pass10_repo_audit.acceptance_criteria.len == 20);
}
