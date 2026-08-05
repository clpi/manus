//! Pass 13 — live development tooling truth audit (Audits 1–15).
//!
//! Classifies what exists today vs Pass 13 requirements. Repository truth overrides prose.
const std = @import("std");

pub const Classification = enum {
    canonical,
    partial,
    experimental,
    stub,
    documentation_only,
    duplicate,
    unsafe,
    absent,

    pub fn name(self: Classification) []const u8 {
        return @tagName(self);
    }
};

pub const AuditEntry = struct {
    id: []const u8,
    title: []const u8,
    classification: Classification,
    owner: []const u8,
    finding: []const u8,
    risk: []const u8,
};

/// Audit 1 — Development MCP (`~/x/duo-mcp`).
pub const audit_dev_mcp: []const AuditEntry = &.{
    .{ .id = "A1-01", .title = "duo_coordination_read/update", .classification = .partial, .owner = "duo-mcp/duo_shared.duo", .finding = "File-append to AGENT_COORDINATION.md; no snapshot binding or lease schema", .risk = "Stale writes; semantic overlap undetected" },
    .{ .id = "A1-02", .title = "duo_agent_session_start", .classification = .partial, .owner = "duo-mcp/duo_bench.duo", .finding = "Embeds duo dev session start JSON + markdown excerpt; machine snapshot when duo built", .risk = "Fallback to prose if DUO_BIN missing" },
    .{ .id = "A1-03", .title = "Claim heartbeat/expire/transfer", .classification = .partial, .owner = "src/dev_control_plane.zig", .finding = "CLI acquire/list/release/heartbeat + .duo/dev/control_plane.json persistence; MCP wire pending", .risk = "Expired claims invisible outside duo dev" },
    .{ .id = "A1-04", .title = "Semantic overlap detection", .classification = .partial, .owner = "src/dev_control_plane.zig", .finding = "File + semantic domain overlap in acquireClaim; markdown coordination still file-only", .risk = "Parallel grammar/registry edits via markdown still collide" },
    .{ .id = "A1-05", .title = "Validation orchestration", .classification = .partial, .owner = "src/dev_validation_planner.zig", .finding = "duo dev validate plan + session start embeds gates; not auto-run yet", .risk = "Agents may skip recommended gates" },
    .{ .id = "A1-06", .title = "Integration queue", .classification = .partial, .owner = "src/dev_control_plane.zig", .finding = "duo dev integration submit/list/complete persisted in control_plane.json", .risk = "Not yet wired to CI merge gate" },
    .{ .id = "A1-07", .title = "Schema versioning", .classification = .partial, .owner = "duo catalog JSON", .finding = "Per-pass schema strings; no unified dev MCP schema", .risk = "Client drift" },
};

/// Audit 2 — End-user MCP (compiler semantics exposure).
pub const audit_enduser_mcp: []const AuditEntry = &.{
    .{ .id = "A2-01", .title = "duo_semantic_snapshot / SIM", .classification = .partial, .owner = "duo-mcp/duo_shared.duo", .finding = "Wraps duo sim; compiler-owned", .risk = "Low" },
    .{ .id = "A2-02", .title = "duo explain / proof bundles", .classification = .partial, .owner = "src/semantic_cli.zig", .finding = "CLI + partial MCP parity", .risk = "Agents may scrape terminal" },
    .{ .id = "A2-03", .title = "Project issue tracking in end-user MCP", .classification = .absent, .owner = "—", .finding = "Correctly absent", .risk = "Low" },
};

/// Audit 3 — LSP (`~/x/duo-lsp` + duo-lsp MCP).
pub const audit_lsp: []const AuditEntry = &.{
    .{ .id = "A3-01", .title = "Parser/compiler reuse", .classification = .partial, .owner = "~/x/duo-lsp", .finding = "Separate repo; parity not continuously gated", .risk = "Semantic drift" },
    .{ .id = "A3-02", .title = "Stable semantic IDs in LSP", .classification = .partial, .owner = "src/semantic_fingerprint.zig", .finding = "Compiler spine exists; LSP projection incomplete", .risk = "Range-only navigation" },
    .{ .id = "A3-03", .title = "Claim decoration / stale snapshot", .classification = .absent, .owner = "—", .finding = "LSP does not consume dev control plane", .risk = "Editors blind to conflicts" },
    .{ .id = "A3-04", .title = "Proof/representation hover", .classification = .absent, .owner = "—", .finding = "Pass 12 WS9 open", .risk = "Agents lack explainability in IDE" },
};

/// Audit 4 — Coordination buffers (markdown today).
pub const audit_coordination: []const AuditEntry = &.{
    .{ .id = "A4-01", .title = "AGENT_COORDINATION.md claims", .classification = .unsafe, .owner = ".agents/AGENT_COORDINATION.md", .finding = "Authoritative mutable markdown; duo dev coordination export provides machine-readable alternative", .risk = "Lost updates until P13-WS18 migration complete" },
    .{ .id = "A4-02", .title = "AGENT_CANONICAL.md router", .classification = .canonical, .owner = ".agents/AGENT_CANONICAL.md", .finding = "Single index; still prose", .risk = "Must migrate to generated projection" },
    .{ .id = "A4-03", .title = "scripts/duo_lock.sh", .classification = .partial, .owner = "scripts/duo_lock.sh", .finding = "Build lock only; not claim-aware", .risk = "Cache corruption under parallel bench" },
    .{ .id = "A4-04", .title = "git stash ban", .classification = .canonical, .owner = "AGENTS.md", .finding = "Documented + enforced by culture", .risk = "Low if obeyed" },
};

/// Audit 5 — Ground-truth sources.
pub const audit_ground_truth: []const AuditEntry = &.{
    .{ .id = "A5-01", .title = "duo catalog JSON", .classification = .partial, .owner = "src/pass3_catalog.zig", .finding = "Pass 1–12 machine-readable; claims still in markdown", .risk = "Split truth" },
    .{ .id = "A5-02", .title = "proof_carrying release claims", .classification = .partial, .owner = "src/proof_carrying.zig", .finding = "Capability registry + dependency recompute", .risk = "Not wired to CI gate" },
    .{ .id = "A5-03", .title = "docs/catalogs/*", .classification = .partial, .owner = "docs/catalogs", .finding = "Mix of generated and manual", .risk = "Drift" },
};

/// Audit 6 — Context comprehension (process audit; baseline expectations).
pub const audit_context: []const AuditEntry = &.{
    .{ .id = "A6-01", .title = "Context bundle generator", .classification = .partial, .owner = "src/semantic_context.zig", .finding = "M1 keyword bundle only", .risk = "Agents read full pass history" },
    .{ .id = "A6-02", .title = "12-question comprehension gate", .classification = .absent, .owner = "—", .finding = "Not enforced before edit", .risk = "Unbounded tasks" },
};

/// Audit 7–15 — summarized entries for catalog export.
pub const audit_parallel_collision: []const AuditEntry = &.{
    .{ .id = "A7-01", .title = "Semantic merge rejection", .classification = .absent, .owner = "—", .finding = "Git merge only", .risk = "Clean merge, broken semantics" },
};

pub const audit_validation: []const AuditEntry = &.{
    .{ .id = "A9-01", .title = "Impact-based validation planner", .classification = .absent, .owner = "—", .finding = "Agents choose gates ad hoc", .risk = "Missed regressions" },
    .{ .id = "A9-02", .title = "native_barrier_checks", .classification = .partial, .owner = "src/native_barrier_checks.zig", .finding = "Artifact assertions exist for proofs", .risk = "Not default in all paths" },
};

pub const audit_logging: []const AuditEntry = &.{
    .{ .id = "A10-01", .title = "Append-only dev event log", .classification = .partial, .owner = "src/dev_control_plane.zig", .finding = "JSONL at .duo/dev/events.jsonl on claim acquire/release/heartbeat", .risk = "Not yet unified with markdown session log" },
    .{ .id = "A10-02", .title = "Structured command records", .classification = .absent, .owner = "—", .finding = "Terminal transcripts not normalized", .risk = "Unreplayable" },
};

pub const audit_presentation: []const AuditEntry = &.{
    .{ .id = "A11-01", .title = "Structured diagnostic records", .classification = .partial, .owner = "src/term.zig", .finding = "Rich terminal; agents still parse prose", .risk = "Scrape fragility" },
    .{ .id = "A12-01", .title = "Single presentation engine", .classification = .absent, .owner = "—", .finding = "term/MCP/LSP emit independently", .risk = "Parity gaps" },
};

pub const audit_enforcement: []const AuditEntry = &.{
    .{ .id = "A14-01", .title = "Claim-aware commit gate", .classification = .absent, .owner = "—", .finding = "No pre-commit claim verify", .risk = "Scope expansion" },
    .{ .id = "A14-02", .title = "repo_hygiene.sh", .classification = .partial, .owner = "scripts/repo_hygiene.sh", .finding = "Artifact pollution checks", .risk = "Not full architecture enforcement" },
};

pub const audit_cross_repo: []const AuditEntry = &.{
    .{ .id = "A15-01", .title = "duo / duo-mcp / duo-lsp version contract", .classification = .partial, .owner = "docs + catalog", .finding = "DUO_ROOT coupling; no unified schema lockfile", .risk = "Cross-repo skew" },
    .{ .id = "A15-02", .title = "Ward vertical proof contract", .classification = .partial, .owner = "src/ward_readiness.zig", .finding = "Readiness matrix; Pass 13 queue not wired", .risk = "Isolated milestones" },
};

pub const AuditGroup = struct {
    id: []const u8,
    title: []const u8,
    entries: []const AuditEntry,
};

pub const audit_groups: []const AuditGroup = &.{
    .{ .id = "audit-01", .title = "Development MCP truth", .entries = audit_dev_mcp },
    .{ .id = "audit-02", .title = "End-user MCP truth", .entries = audit_enduser_mcp },
    .{ .id = "audit-03", .title = "LSP truth", .entries = audit_lsp },
    .{ .id = "audit-04", .title = "Coordination truth", .entries = audit_coordination },
    .{ .id = "audit-05", .title = "Ground-truth sources", .entries = audit_ground_truth },
    .{ .id = "audit-06", .title = "Agent context comprehension", .entries = audit_context },
    .{ .id = "audit-07", .title = "Parallel collision", .entries = audit_parallel_collision },
    .{ .id = "audit-09", .title = "Validation selection", .entries = audit_validation },
    .{ .id = "audit-10", .title = "Logging and causality", .entries = audit_logging },
    .{ .id = "audit-11", .title = "Compiler message quality", .entries = audit_presentation },
    .{ .id = "audit-12", .title = "Presentation consistency", .entries = audit_presentation },
    .{ .id = "audit-14", .title = "Enforcement bypass", .entries = audit_enforcement },
    .{ .id = "audit-15", .title = "Cross-repository contract", .entries = audit_cross_repo },
};

pub fn countByClass(entries: []const AuditEntry, class: Classification) usize {
    var n: usize = 0;
    for (entries) |e| {
        if (e.classification == class) n += 1;
    }
    return n;
}

pub fn writeAuditSummaryJson(w: *std.Io.Writer) !void {
    try w.print("{{\"audit_groups\":[", .{});
    for (audit_groups, 0..) |g, gi| {
        if (gi > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"entries\":[", .{ g.id, g.title });
        for (g.entries, 0..) |e, ei| {
            if (ei > 0) try w.writeAll(",");
            try w.print(
                "{{\"id\":\"{s}\",\"title\":\"{s}\",\"classification\":\"{s}\",\"owner\":\"{s}\",\"finding\":\"{s}\",\"risk\":\"{s}\"}}",
                .{ e.id, e.title, e.classification.name(), e.owner, e.finding, e.risk },
            );
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]}");
}

test "pass13_dev_audit: audit groups non-empty" {
    try std.testing.expect(audit_groups.len >= 10);
    try std.testing.expect(audit_dev_mcp.len >= 5);
}
