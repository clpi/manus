//! Pass 10 — public repository readiness findings and release invariants.
//!
//! Canonical owner for machine-readable pollution/audit tracking (Pass 10).
const std = @import("std");

pub const SCHEMA_VERSION = "pass10-repo-audit-v0";

pub const Severity = enum(u8) {
    critical,
    high,
    medium,

    pub fn name(self: Severity) []const u8 {
        return @tagName(self);
    }
};

pub const FindingCategory = enum(u8) {
    duplicate_doc,
    agent_internal,
    historical_plan,
    hierarchy,
    naming,
    example,
    script,
    generated_untracked,
    private_path,
    missing_canonical,

    pub fn name(self: FindingCategory) []const u8 {
        return @tagName(self);
    }
};

pub const RecommendedAction = enum(u8) {
    remove,
    archive,
    merge,
    relocate,
    rename,
    automate,
    document,

    pub fn name(self: RecommendedAction) []const u8 {
        return @tagName(self);
    }
};

pub const Finding = struct {
    id: []const u8,
    category: FindingCategory,
    severity: Severity,
    path: []const u8,
    action: RecommendedAction,
    reason: []const u8,
};

pub const ReleaseInvariant = struct {
    id: []const u8,
    section: []const u8,
    title: []const u8,
    status: []const u8,
};

pub const MandatoryAudit = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    exit_gate: []const u8,
};

pub const ReleaseBlocker = struct {
    id: []const u8,
    severity: Severity,
    title: []const u8,
    status: []const u8,
    evidence: []const u8,
};

pub const AcceptanceCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

pub const PollutionFinding = struct {
    id: []const u8,
    category: FindingCategory,
    path: []const u8,
    tracked: bool,
    action: []const u8,
    status: []const u8,
    rationale: []const u8,
};

pub const CanonicalDocTarget = struct {
    path: []const u8,
    audience: []const u8,
    purpose: []const u8,
    status: []const u8,
};

/// Initial inventory — expand via Audit 16 file enumeration.
pub const findings: []const Finding = &.{
    .{ .id = "P10-F001", .category = .duplicate_doc, .severity = .high, .path = "docs/AGENT_COORDINATION.md", .action = .merge, .reason = "Mirrors .agents/AGENT_COORDINATION.md; public readers see agent buffer" },
    .{ .id = "P10-F002", .category = .duplicate_doc, .severity = .high, .path = "docs/AGENT_INTEGRATION.md", .action = .merge, .reason = "Duplicates .agents/AGENT_INTEGRATION.md" },
    .{ .id = "P10-F003", .category = .agent_internal, .severity = .high, .path = "AGENTS.md", .action = .relocate, .reason = "Agent instructions at repo root; belongs in .agents/ or contributor-internal doc" },
    .{ .id = "P10-F004", .category = .historical_plan, .severity = .medium, .path = "docs/plans/pass2_convergence.md", .action = .archive, .reason = "Redirect stub → pass2_foundational_convergence.md" },
    .{ .id = "P10-F005", .category = .historical_plan, .severity = .medium, .path = "docs/plans/pass4_native_compilation.md", .action = .archive, .reason = "Redirect stub → pass4_native_end_to_end.md" },
    .{ .id = "P10-F006", .category = .historical_plan, .severity = .medium, .path = "docs/plans/pass6_reconciliation.md", .action = .archive, .reason = "Redirect stub → pass6_architectural_reconciliation.md" },
    .{ .id = "P10-F007", .category = .historical_plan, .severity = .medium, .path = "docs/plans/pass7_ai_native.md", .action = .archive, .reason = "Redirect stub → pass7_ai_native_compilation.md" },
    .{ .id = "P10-F008", .category = .historical_plan, .severity = .medium, .path = "docs/plans/pass8_persistent_semantic.md", .action = .archive, .reason = "Redirect stub → pass8_persistent_semantic_computing.md" },
    .{ .id = "P10-F009", .category = .missing_canonical, .severity = .high, .path = "docs/compiler.md", .action = .document, .reason = "Created canonical compiler architecture entry" },
    .{ .id = "P10-F010", .category = .missing_canonical, .severity = .high, .path = "docs/language.md", .action = .document, .reason = "Created canonical language reference entry" },
    .{ .id = "P10-F011", .category = .hierarchy, .severity = .medium, .path = "src/pass3_catalog.zig", .action = .document, .reason = "Pass-numbered catalog modules in src/; acceptable as tooling but needs public explanation" },
    .{ .id = "P10-F012", .category = .example, .severity = .medium, .path = "examples/pass3_syntax_showcase.duo", .action = .rename, .reason = "Pass-shaped example name; prefer capability-named examples" },
    .{ .id = "P10-F013", .category = .private_path, .severity = .medium, .path = "README.md", .action = .document, .reason = "Documentation table + link to docs/bootstrap.md added" },
    .{ .id = "P10-F014", .category = .duplicate_doc, .severity = .medium, .path = "docs/semantic_universe.md", .action = .merge, .reason = "Overlaps docs/plans/semantic_graph_architecture.md" },
    .{ .id = "P10-F015", .category = .generated_untracked, .severity = .medium, .path = "(working tree)", .action = .remove, .reason = "scripts/public_safety_scan.sh + expanded .gitignore" },
};

pub const release_invariants: []const ReleaseInvariant = &.{
    .{ .id = "3.14", .section = "release", .title = "Repository ready for public inspection", .status = "partial" },
    .{ .id = "3.15", .section = "release", .title = "No repository pollution", .status = "open" },
    .{ .id = "3.16", .section = "release", .title = "Every file has a permanent role", .status = "open" },
    .{ .id = "3.17", .section = "release", .title = "Information density repository-wide", .status = "partial" },
    .{ .id = "3.18", .section = "release", .title = "Markdown concise and canonical", .status = "partial" },
    .{ .id = "3.19", .section = "release", .title = "Comments explain what code cannot", .status = "partial" },
    .{ .id = "3.20", .section = "release", .title = "Code concise without cleverness", .status = "partial" },
    .{ .id = "3.21", .section = "release", .title = "Public names intentional", .status = "partial" },
};

pub const mandatory_audits: []const MandatoryAudit = &.{
    .{ .id = "A15", .title = "Public repository quality audit", .status = "open", .exit_gate = "New reader can build Duo without private guidance" },
    .{ .id = "A16", .title = "File necessity audit", .status = "partial", .exit_gate = "Every tracked file has explicit durable purpose" },
    .{ .id = "A17", .title = "Markdown compression audit", .status = "open", .exit_gate = "Canonical doc set; duplicates merged or archived" },
    .{ .id = "A18", .title = "Source density and comment audit", .status = "open", .exit_gate = "Compact readable codebase without pass/agent noise" },
    .{ .id = "A19", .title = "Public safety and licensing audit", .status = "partial", .exit_gate = "No secrets; licenses complete" },
};

pub const release_blockers: []const ReleaseBlocker = &.{
    .{ .id = "RB-C1", .severity = .critical, .title = "Credentials or secrets in publication history", .status = "partial", .evidence = "scripts/public_safety_scan.sh PASS; wired in agent-smoke + zig build test; full history scan open" },
    .{ .id = "RB-C2", .severity = .critical, .title = "Unlicensed copied code", .status = "open", .evidence = "third-party audit pending" },
    .{ .id = "RB-C3", .severity = .critical, .title = "Release instructions that do not work", .status = "partial", .evidence = "README build steps verified; full release doc missing" },
    .{ .id = "RB-H1", .severity = .high, .title = "Pass-shaped production hierarchy", .status = "open", .evidence = "src/ flat; examples/pass* and docs/plans/pass* prominent" },
    .{ .id = "RB-H2", .severity = .high, .title = "Major duplicate documentation", .status = "partial", .evidence = "pass2/4/6/7/8 duplicate plans compressed to redirects" },
    .{ .id = "RB-H3", .severity = .high, .title = "Stale or untracked public examples", .status = "partial", .evidence = "examples/pass9/* (9 smokes) pass; agent-smoke includes pass9 targets" },
    .{ .id = "RB-M1", .severity = .medium, .title = "Untracked root scratch noise", .status = "open", .evidence = "bench_*, *.log, test_*.c at repo root" },
};

pub const acceptance_criteria: []const AcceptanceCriterion = &.{
    .{ .id = 1, .title = "Repository suitable for immediate public viewing", .status = "open" },
    .{ .id = 2, .title = "Sparse, self-explanatory root directory", .status = "partial" },
    .{ .id = 3, .title = "Hierarchy reflects permanent architectural ownership", .status = "open" },
    .{ .id = 4, .title = "No production file named after pass or agent session", .status = "partial" },
    .{ .id = 5, .title = "Every tracked file has durable documented purpose", .status = "open" },
    .{ .id = 6, .title = "Obsolete, duplicate, temporary files removed", .status = "open" },
    .{ .id = 7, .title = "Markdown consolidated into small canonical set", .status = "open" },
    .{ .id = 8, .title = "Every public document concise and current", .status = "open" },
    .{ .id = 9, .title = "Every runnable command/example auto-validated", .status = "partial" },
    .{ .id = 10, .title = "Future plans separated from current functionality", .status = "partial" },
    .{ .id = 11, .title = "Comments explain non-obvious constraints", .status = "open" },
    .{ .id = 12, .title = "Source concise without cryptic cleverness", .status = "partial" },
    .{ .id = 13, .title = "Public names use one canonical glossary", .status = "partial" },
    .{ .id = 14, .title = "Tests organized by semantic responsibility", .status = "open" },
    .{ .id = 15, .title = "Generated files deterministic, necessary, owned", .status = "partial" },
    .{ .id = 16, .title = "Scripts/config free of private environment assumptions", .status = "partial" },
    .{ .id = 17, .title = "No credentials, private paths, or copied conversations", .status = "partial" },
    .{ .id = 18, .title = "Licensing and third-party attribution complete", .status = "partial" },
    .{ .id = 19, .title = "External contributor can locate core subsystems without private guidance", .status = "partial" },
    .{ .id = 20, .title = "Independent reviewers find no major noise or unexplained structure", .status = "open" },
};

pub const pollution_findings: []const PollutionFinding = &.{
    .{ .id = "P10-P001", .category = .generated_untracked, .path = "compile_err.log", .tracked = false, .action = "gitignore+delete", .status = "open", .rationale = "local debug log" },
    .{ .id = "P10-P002", .category = .generated_untracked, .path = "debug.log", .tracked = false, .action = "gitignore+delete", .status = "open", .rationale = "local debug log" },
    .{ .id = "P10-P003", .category = .generated_untracked, .path = "bench_alloc_c", .tracked = false, .action = "delete", .status = "open", .rationale = "untracked benchmark binary" },
    .{ .id = "P10-P004", .category = .historical_plan, .path = "docs/plans/pass7_ai_native.md", .tracked = true, .action = "redirect", .status = "mitigated", .rationale = "compressed to redirect stub" },
    .{ .id = "P10-P005", .category = .example, .path = "examples/pass9/", .tracked = true, .action = "track", .status = "mitigated", .rationale = "nine pass9 smokes pass; differential via wasm_decode_differential.zig" },
    .{ .id = "P10-P006", .category = .hierarchy, .path = "src/codegen.zig", .tracked = true, .action = "defer_split", .status = "open", .rationale = "monolith — split by responsibility, not pass rename" },
};

pub const canonical_doc_targets: []const CanonicalDocTarget = &.{
    .{ .path = "README.md", .audience = "all", .purpose = "project entry", .status = "exists" },
    .{ .path = "docs/language.md", .audience = "users", .purpose = "language reference entry", .status = "exists" },
    .{ .path = "docs/compiler.md", .audience = "compiler engineers", .purpose = "architecture entry", .status = "exists" },
    .{ .path = "docs/tooling.md", .audience = "tooling users", .purpose = "LSP/MCP/fmt", .status = "exists" },
    .{ .path = "docs/bootstrap.md", .audience = "contributors", .purpose = "self-hosting", .status = "exists" },
    .{ .path = "docs/contributing.md", .audience = "contributors", .purpose = "contribution process", .status = "exists" },
    .{ .path = "docs/release.md", .audience = "maintainers", .purpose = "release process", .status = "exists" },
};

pub const doc_inventory = struct {
    pub const tracked_markdown: u32 = 70;
    pub const plans_markdown: u32 = 10;
    pub const agent_facing_docs: u32 = 8;
    pub const canonical_public_targets: u32 = 6;
};

pub fn countPollutionOpen() usize {
    var n: usize = 0;
    for (pollution_findings) |f| {
        if (std.mem.eql(u8, f.status, "open")) n += 1;
    }
    return n;
}

pub fn countAcceptanceByStatus(status: []const u8) usize {
    var n: usize = 0;
    for (acceptance_criteria) |c| {
        if (std.mem.eql(u8, c.status, status)) n += 1;
    }
    return n;
}

pub fn countBlockersOpen(sev: Severity) usize {
    var n: usize = 0;
    for (release_blockers) |b| {
        if (b.severity == sev and std.mem.eql(u8, b.status, "open")) n += 1;
    }
    return n;
}

pub fn countInvariantsMet() usize {
    var n: usize = 0;
    for (release_invariants) |inv| {
        if (std.mem.eql(u8, inv.status, "met")) n += 1;
    }
    return n;
}

pub fn countCanonicalDocsMissing() usize {
    var n: usize = 0;
    for (canonical_doc_targets) |d| {
        if (std.mem.eql(u8, d.status, "missing")) n += 1;
    }
    return n;
}

pub fn countFindingsBySeverity(sev: Severity) usize {
    var n: usize = 0;
    for (findings) |f| {
        if (f.severity == sev) n += 1;
    }
    return n;
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeInvariantsJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (release_invariants, 0..) |inv, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"section\":\"{s}\",\"title\":\"", .{ inv.id, inv.section });
        try jsonEscape(w, inv.title);
        try w.print("\",\"status\":\"{s}\"}}", .{inv.status});
    }
    try w.print("]", .{});
}

pub fn writeAuditsJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (mandatory_audits, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{a.id});
        try jsonEscape(w, a.title);
        try w.print("\",\"status\":\"{s}\",\"exit_gate\":\"", .{a.status});
        try jsonEscape(w, a.exit_gate);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeBlockersJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (release_blockers, 0..) |b, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"severity\":\"{s}\",\"title\":\"", .{ b.id, b.severity.name() });
        try jsonEscape(w, b.title);
        try w.print("\",\"status\":\"{s}\",\"evidence\":\"", .{b.status});
        try jsonEscape(w, b.evidence);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeAcceptanceJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (acceptance_criteria, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":{d},\"title\":\"", .{c.id});
        try jsonEscape(w, c.title);
        try w.print("\",\"status\":\"{s}\"}}", .{c.status});
    }
    try w.print("]", .{});
}

pub fn writePollutionJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (pollution_findings, 0..) |f, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"category\":\"{s}\",\"path\":\"", .{ f.id, f.category.name() });
        try jsonEscape(w, f.path);
        try w.print("\",\"tracked\":", .{});
        try w.print("{s}", .{if (f.tracked) "true" else "false"});
        try w.print(",\"action\":\"", .{});
        try jsonEscape(w, f.action);
        try w.print("\",\"status\":\"{s}\",\"rationale\":\"", .{f.status});
        try jsonEscape(w, f.rationale);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeCanonicalDocsJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (canonical_doc_targets, 0..) |d, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"path\":\"", .{});
        try jsonEscape(w, d.path);
        try w.print("\",\"audience\":\"", .{});
        try jsonEscape(w, d.audience);
        try w.print("\",\"purpose\":\"", .{});
        try jsonEscape(w, d.purpose);
        try w.print("\",\"status\":\"{s}\"}}", .{d.status});
    }
    try w.print("]", .{});
}

pub fn writeFindingsJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (findings, 0..) |f, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, f.id);
        try w.print("\",\"category\":\"{s}\",\"severity\":\"{s}\",\"path\":\"", .{ f.category.name(), f.severity.name() });
        try jsonEscape(w, f.path);
        try w.print("\",\"action\":\"{s}\",\"reason\":\"", .{f.action.name()});
        try jsonEscape(w, f.reason);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"finding_count\":{d},\"findings\":", .{ SCHEMA_VERSION, findings.len });
    try writeFindingsJson(w);
    try w.print(",\"release_invariants\":[", .{});
    for (release_invariants, 0..) |inv, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"section\":\"{s}\",\"title\":\"", .{ inv.id, inv.section });
        try jsonEscape(w, inv.title);
        try w.print("\",\"status\":\"{s}\"}}", .{inv.status});
    }
    try w.print("],\"mandatory_audits\":[", .{});
    for (mandatory_audits, 0..) |a, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{a.id});
        try jsonEscape(w, a.title);
        try w.print("\",\"status\":\"{s}\",\"exit_gate\":\"", .{a.status});
        try jsonEscape(w, a.exit_gate);
        try w.print("\"}}", .{});
    }
    try w.print("],\"doc_inventory\":{{\"tracked_markdown\":{d},\"plans_markdown\":{d},\"agent_facing_docs\":{d},\"canonical_public_targets\":{d}}},\"severity_counts\":{{\"critical\":{d},\"high\":{d},\"medium\":{d}}}}}", .{
        doc_inventory.tracked_markdown,
        doc_inventory.plans_markdown,
        doc_inventory.agent_facing_docs,
        doc_inventory.canonical_public_targets,
        countFindingsBySeverity(.critical),
        countFindingsBySeverity(.high),
        countFindingsBySeverity(.medium),
    });
}

test "pass10_repo_audit: twenty acceptance criteria" {
    try std.testing.expect(acceptance_criteria.len == 20);
}

test "pass10_repo_audit: finding ids unique" {
    for (findings, 0..) |a, i| {
        for (findings[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
        }
    }
}

test "pass10_repo_audit: fifteen seed findings" {
    try std.testing.expect(findings.len >= 15);
}
