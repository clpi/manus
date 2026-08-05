//! Pass 14 §6–7, §18 Audit 2, Milestone 2 — salvage registry.
//!
//! A canonical displaced-implementation record. Before *any* code or artifact is
//! deleted, the salvage registry answers (Pass 14 §5.5): what purpose did this
//! serve, what remains valuable, where has the value moved, what proves the
//! replacement is better, and is deletion necessary? This is the constructive
//! half of Pass 14 — work is reconciled (refit/merged/extracted/generalized)
//! *before* it is removed.
//!
//! The seed records below are **real current findings** in this repository, not
//! stubs. They demonstrate the registry in operation and must be resolved
//! (integrated / migrated / preserved) rather than silently deleted.
const std = @import("std");

pub const SCHEMA_VERSION = "salvage-registry-v0";

/// Pass 14 §6 reconciliation strategies.
pub const Strategy = enum {
    refit,
    refactor,
    merge,
    extract,
    generalize,
    specialize,
    lower,
    isolate,
    translate,
    preserve_as_evidence,
    retire_through_replacement,

    pub fn name(self: Strategy) []const u8 {
        return @tagName(self);
    }
};

/// Deletion eligibility (Pass 14 §5.5). `eligible` only after salvage proof.
pub const Eligibility = enum {
    not_evaluated,
    not_eligible,
    eligible_after_salvage,
    eligible_now,
    resolved,

    pub fn name(self: Eligibility) []const u8 {
        return @tagName(self);
    }
};

pub const SalvageRecord = struct {
    /// Stable identity (semantic, not chronology-based — Pass 14 §16.3).
    id: []const u8,
    purpose: []const u8,
    retained_value: []const u8,
    invalid_assumptions: []const u8,
    replacement: []const u8,
    transferred: []const u8,
    evidence: []const u8,
    strategy: Strategy,
    eligibility: Eligibility,
    owner: []const u8,
};

/// Pass 14 §18 Audit 2 — current abandoned-work inventory in THIS repository.
/// These are real drift findings discovered at Pass 14 introduction.
pub const seed_salvage_records: []const SalvageRecord = &.{
    .{
        .id = "drift-pass-name-stubs-referenced",
        .purpose = "Short-name pass plan files (pass2_convergence.md, pass4_native_compilation.md, pass6_reconciliation.md, pass7_ai_native.md, pass8_persistent_semantic.md) were the original plan names; superseded by longer canonical names.",
        .retained_value = "Git history of each file preserves the original short drafts; the current content is a clean redirect to the canonical name.",
        .invalid_assumptions = "That short pass-numbered names are permanent (Pass 14 §16.3 forbids pass-shaped / chronology-based permanent names).",
        .replacement = "Canonical plans: pass2_foundational_convergence.md, pass4_native_end_to_end.md, pass6_architectural_reconciliation.md, pass7_ai_native_compilation.md, pass8_persistent_semantic_computing.md.",
        .transferred = "AGENTS.md + docs/AGENT_ALIGNMENT.md inbound references refitted to canonical names (Pass 14 audit 2026-08-05). Remaining inbound refs are pass10_repo_audit findings (correct-as-documentation) and the coordination buffer (redirect-functional).",
        .evidence = "Stubs now have zero canonical inbound links; `grep` for the short names finds only redirect files, pass10 findings, and historical session-log entries.",
        .strategy = .retire_through_replacement,
        .eligibility = .eligible_now,
        .owner = "docs/plans",
    },
    .{
        .id = "drift-agents-md-stale-pass-paths",
        .purpose = "AGENTS.md and docs/AGENT_ALIGNMENT.md 'Architecture passes' lists referenced redirect/stub plan paths instead of canonical names.",
        .retained_value = "The reading order and one-line descriptions remain useful navigation.",
        .invalid_assumptions = "That the short-named stub files are the substantive plans.",
        .replacement = "The five AGENTS.md links + four AGENT_ALIGNMENT.md links now point at the canonical *_foundational_convergence / *_end_to_end / *_architectural_reconciliation / *_ai_native_compilation / *_persistent_semantic_computing names.",
        .transferred = "Reading-order preserved; only the href targets changed (9 links across 2 files).",
        .evidence = "Pass 14 audit 2026-08-05: `grep` confirms AGENTS.md + AGENT_ALIGNMENT.md now reference only canonical plan paths.",
        .strategy = .refit,
        .eligibility = .resolved,
        .owner = "AGENTS.md + docs/AGENT_ALIGNMENT.md",
    },
    .{
        .id = "worktree-prunable-recovery-jul-30",
        .purpose = "/private/tmp/duo-recovery at branch recovery/jul-30, marked prunable by `git worktree list`. Created during the 2026-08-01 stash rescue.",
        .retained_value = "Possible unique commits/trees not on main from the 23-file rescue; must be inspected before pruning.",
        .invalid_assumptions = "That a prunable worktree is safe to delete — Pass 14 §5.3 requires a full retirement protocol first.",
        .replacement = "Once inspected: either integrate unique commits to a preservation branch, or confirm main supersedes them.",
        .transferred = "Nothing yet — inspection pending.",
        .evidence = "`git worktree list` reports it prunable; the 2026-08-01 session log records a 23-file rescue whose residue may live here.",
        .strategy = .extract,
        .eligibility = .not_evaluated,
        .owner = "git-preservation audit",
    },
    .{
        .id = "worktree-prunable-opencode-detached",
        .purpose = "/private/var/folders/.../opencode/duo-head2 — detached HEAD at the current main revision, marked prunable.",
        .retained_value = "A scratch build head; no unique commits expected (same rev as main) but dirty/untracked state must be confirmed.",
        .invalid_assumptions = "That detached-at-main means empty — untracked artifacts could still be present.",
        .replacement = "Confirm clean against main, then prune as pure storage cleanup.",
        .transferred = "Nothing expected.",
        .evidence = "`git worktree list` shows it at HEAD == main rev, prunable.",
        .strategy = .retire_through_replacement,
        .eligibility = .eligible_after_salvage,
        .owner = "git-preservation audit",
    },
    .{
        .id = "branch-kiro-pass2-pass3-convergence",
        .purpose = "Local branch kiro/pass2-pass3-convergence carrying unique commits not on main (merged recently per reflog).",
        .retained_value = "May contain merge artifacts or follow-up commits worth preserving as a branch or tag.",
        .invalid_assumptions = "That a recently-merged branch can be deleted without checking for post-merge commits.",
        .replacement = "If fully merged into main, delete after confirming rev-list main..branch is empty; else keep as preservation branch.",
        .transferred = "Recent reflog shows a merge into main; verify no dangling unique work.",
        .evidence = "Branch appears in `git branch` and was the HEAD@{0} merge source.",
        .strategy = .merge,
        .eligibility = .eligible_after_salvage,
        .owner = "git-preservation audit",
    },
    .{
        .id = "artifact-claude-md-and-dir",
        .purpose = "Untracked CLAUDE.md and .claude/ directory — agent session context not committed or gitignored.",
        .retained_value = "Local agent configuration; not project truth.",
        .invalid_assumptions = "That agent-local state should be tracked or left untracked indefinitely.",
        .replacement = "Either gitignore (agent-local, per-machine) or remove; do not commit machine-specific agent state to the public repo.",
        .transferred = "None needed.",
        .evidence = "`git status --porcelain` lists both as untracked (`??`).",
        .strategy = .isolate,
        .eligibility = .eligible_after_salvage,
        .owner = "repo-hygiene / .gitignore",
    },
};

/// Count records by disposition for the audit summary.
pub fn summary() struct { total: usize, eligible_now: usize, eligible_after_salvage: usize, not_evaluated: usize, resolved: usize } {
    var eligible_now: usize = 0;
    var eligible_after: usize = 0;
    var not_evaluated: usize = 0;
    var resolved: usize = 0;
    for (seed_salvage_records) |r| {
        switch (r.eligibility) {
            .eligible_now => eligible_now += 1,
            .eligible_after_salvage => eligible_after += 1,
            .not_evaluated => not_evaluated += 1,
            .resolved => resolved += 1,
            .not_eligible => {},
        }
    }
    return .{
        .total = seed_salvage_records.len,
        .eligible_now = eligible_now,
        .eligible_after_salvage = eligible_after,
        .not_evaluated = not_evaluated,
        .resolved = resolved,
    };
}

pub fn writeSalvageRegistryJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"records\":[", .{SCHEMA_VERSION});
    for (seed_salvage_records, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"purpose\":\"{s}\",\"retained_value\":\"{s}\",\"invalid_assumptions\":\"{s}\",\"replacement\":\"{s}\",\"transferred\":\"{s}\",\"evidence\":\"{s}\",\"strategy\":\"{s}\",\"eligibility\":\"{s}\",\"owner\":\"{s}\"}}",
            .{ r.id, r.purpose, r.retained_value, r.invalid_assumptions, r.replacement, r.transferred, r.evidence, r.strategy.name(), r.eligibility.name(), r.owner },
        );
    }
    const s = summary();
    try w.print("],\"summary\":{{\"total\":{d},\"eligible_now\":{d},\"eligible_after_salvage\":{d},\"not_evaluated\":{d},\"resolved\":{d}}}}}", .{ s.total, s.eligible_now, s.eligible_after_salvage, s.not_evaluated, s.resolved });
}

test "salvage_registry: seed records are non-empty and well-formed" {
    try std.testing.expect(seed_salvage_records.len >= 4);
    for (seed_salvage_records) |r| {
        try std.testing.expect(r.id.len > 0);
        try std.testing.expect(r.purpose.len > 0);
        try std.testing.expect(r.replacement.len > 0);
        try std.testing.expect(r.owner.len > 0);
    }
}

test "salvage_registry: summary counts match" {
    const s = summary();
    try std.testing.expectEqual(seed_salvage_records.len, s.total);
    try std.testing.expect(s.eligible_now + s.eligible_after_salvage + s.not_evaluated + s.resolved <= s.total);
}

test "salvage_registry: JSON parses" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeSalvageRegistryJson(&aw.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const root = parsed.value.object;
    try std.testing.expect(root.get("records").? == .array);
    try std.testing.expectEqual(@as(usize, seed_salvage_records.len), root.get("records").?.array.items.len);
    try std.testing.expect(root.get("summary").? == .object);
}
