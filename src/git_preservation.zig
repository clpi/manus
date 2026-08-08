//! Pass 14 §5, §18 Audit 1, Milestone 1 — preservation-aware Git operations.
//!
//! This is the *preservation* half of the development control plane. Where
//! `dev_control_plane.zig` (Pass 13) owns coordination *state* (snapshots,
//! claims, presentation), this module owns **what would be lost** by a
//! destructive Git operation: stashes, dirty worktrees, untracked artifacts,
//! branches carrying unique commits, and prunable worktrees.
//!
//! Philosophy (Pass 14 §5.1–5.2): destructive Git operations are exceptional.
//! `git stash` is banned as a coordination tool. Worktrees may be removed only
//! after every unique change is preserved (§5.3). This module inventories the
//! repository so an agent or CI gate can answer: *could this destroy unique
//! work?* before acting.
//!
//! CLI: `duo dev preserve` → `writePreservationReportJson`.
const std = @import("std");
const host_run = @import("host_run.zig");

pub const SCHEMA_VERSION = "git-preservation-v0";

/// Severity of a destructive-operation finding (Pass 14 §5).
pub const Severity = enum {
    safe,
    caution,
    danger,

    pub fn name(self: Severity) []const u8 {
        return @tagName(self);
    }
};

/// A detected destructive-operation risk.
pub const DestructiveFinding = struct {
    /// Operation family: "stash" | "reset" | "clean" | "force_push"
    /// | "worktree_deletion" | "branch_deletion" | "broad_restore".
    op: []const u8,
    severity: Severity,
    /// Human-readable rationale + recommended preservation action.
    detail: []const u8,
};

/// A linked working tree (Pass 14 §5.3 retirement protocol).
pub const Worktree = struct {
    path: []const u8,
    head: []const u8,
    branch: []const u8,
    prunable: bool,
};

/// The full preservation report. All slices are owned by `freeReport`.
pub const PreservationReport = struct {
    git_available: bool,
    head_revision: []const u8,
    current_branch: []const u8,
    stash_count: usize,
    dirty_count: usize,
    /// Untracked paths that look like *valuable* work (source/docs/scripts),
    /// excluding cache/build/output directories.
    untracked_valuable: []const []const u8,
    /// Branch refs carrying commits not reachable from the integration branch.
    branches_not_on_main: []const []const u8,
    worktrees: []const Worktree,
    prunable_worktrees: []const Worktree,
    destructive_findings: []const DestructiveFinding,
    overall_risk: Severity,

    pub fn freeReport(self: *PreservationReport, alloc: std.mem.Allocator) void {
        alloc.free(self.head_revision);
        alloc.free(self.current_branch);
        for (self.untracked_valuable) |p| alloc.free(p);
        alloc.free(self.untracked_valuable);
        for (self.branches_not_on_main) |b| alloc.free(b);
        alloc.free(self.branches_not_on_main);
        for (self.worktrees) |wt| {
            alloc.free(wt.path);
            alloc.free(wt.head);
            alloc.free(wt.branch);
        }
        alloc.free(self.worktrees);
        for (self.prunable_worktrees) |wt| {
            alloc.free(wt.path);
            alloc.free(wt.head);
            alloc.free(wt.branch);
        }
        alloc.free(self.prunable_worktrees);
        for (self.destructive_findings) |f| {
            alloc.free(f.op);
            alloc.free(f.detail);
        }
        alloc.free(self.destructive_findings);
    }
};

/// Prefixes that are NOT valuable work — caches, build output, IDE state.
/// Untracked files under these are reported as ignorable, not salvageable.
pub const ignore_prefixes = [_][]const u8{
    ".zig-cache/",
    "zig-out/",
    ".duo/cache/",
    ".duo/graph/",
    ".DS_Store",
    "default.profraw",
    "benchmark_c",
};

/// Extensions that mark a path as valuable source/docs/scripts.
pub const valuable_extensions = [_][]const u8{
    ".zig", ".duo", ".md", ".sh", ".txt", ".toml", ".json", ".yml", ".yaml",
    ".c", ".h", ".lua", ".patch",
};

fn isValuableUntracked(path: []const u8) bool {
    for (ignore_prefixes) |p| {
        if (std.mem.startsWith(u8, path, p)) return false;
    }
    for (valuable_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }
    // Directory entries (trailing slash) or dotfiles with no ext: report but
    // only if not in the ignore list. Keeps .claude/, CLAUDE.md-ish artifacts
    // visible without false-positiving on cache dumps.
    if (std.mem.endsWith(u8, path, "/")) return true;
    return false;
}

/// Run a git command and return its (trimmed) stdout. Returns null on any
/// failure (git missing, non-zero exit). Caller frees the returned slice.
fn gitStdout(alloc: std.mem.Allocator, argv: []const []const u8) ?[]const u8 {
    const out = host_run.runHostCommandArgs(alloc, argv) orelse return null;
    defer alloc.free(out.stderr);
    if (!out.ok) {
        alloc.free(out.stdout);
        return null;
    }
    return out.stdout;
}

fn countLines(s: []const u8) usize {
    if (s.len == 0) return 0;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |line| {
        if (line.len > 0) n += 1;
    }
    return n;
}

/// Parse `git status --porcelain` lines, counting dirty entries and collecting
/// valuable untracked paths (lines starting with `??`).
fn collectDirtyAndUntracked(alloc: std.mem.Allocator, out: *std.ArrayList([]const u8), dirty_count: *usize) !void {
    const status = gitStdout(alloc, &.{ "git", "status", "--porcelain" }) orelse return;
    defer alloc.free(status);
    var it = std.mem.splitScalar(u8, status, '\n');
    while (it.next()) |line| {
        if (line.len < 3) continue;
        dirty_count.* += 1;
        const code = line[0..2];
        const path = std.mem.trim(u8, line[3..], " \"");
        if (std.mem.eql(u8, code, "??") and isValuableUntracked(path)) {
            try out.append(alloc, try alloc.dupe(u8, path));
        }
    }
}

/// Parse `git worktree list --porcelain` into Worktree records, splitting out
/// prunable ones.
fn collectWorktrees(alloc: std.mem.Allocator, all: *std.ArrayList(Worktree), prunable: *std.ArrayList(Worktree)) !void {
    const wl = gitStdout(alloc, &.{ "git", "worktree", "list", "--porcelain" }) orelse return;
    defer alloc.free(wl);
    var path: ?[]const u8 = null;
    var head: ?[]const u8 = null;
    var branch: ?[]const u8 = null;
    var is_prunable = false;
    var it = std.mem.splitScalar(u8, wl, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) {
            // flush record
            if (path) |p| {
                const wt = Worktree{
                    .path = try alloc.dupe(u8, p),
                    .head = try alloc.dupe(u8, head orelse ""),
                    .branch = try alloc.dupe(u8, branch orelse "(detached)"),
                    .prunable = is_prunable,
                };
                if (is_prunable) {
                    try prunable.append(alloc, wt);
                } else {
                    try all.append(alloc, wt);
                }
            }
            path = null;
            head = null;
            branch = null;
            is_prunable = false;
            continue;
        }
        if (std.mem.startsWith(u8, line, "worktree ")) {
            path = line["worktree ".len..];
        } else if (std.mem.startsWith(u8, line, "HEAD ")) {
            head = line["HEAD ".len..];
        } else if (std.mem.startsWith(u8, line, "branch ")) {
            branch = line["branch ".len..];
        } else if (std.mem.startsWith(u8, line, "detached")) {
            branch = "(detached)";
        } else if (std.mem.eql(u8, line, "prunable")) {
            is_prunable = true;
        }
    }
}

/// List local branches whose tips are not reachable from `main`.
fn collectUniqueBranches(alloc: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
    const out_buf = gitStdout(alloc, &.{ "git", "branch", "--no-color", "--list" }) orelse return;
    defer alloc.free(out_buf);
    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(alloc);
    var it = std.mem.splitScalar(u8, out_buf, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r*");
        if (line.len == 0) continue;
        // strip "(HEAD detached ..." marker lines
        if (std.mem.startsWith(u8, line, "(HEAD ")) continue;
        try names.append(alloc, line);
    }
    const main_ok = gitStdout(alloc, &.{ "git", "rev-parse", "--verify", "main" });
    const main_rev = blk: {
        if (main_ok) |r| {
            defer alloc.free(r);
            break :blk try alloc.dupe(u8, std.mem.trim(u8, r, " \t\r\n"));
        }
        break :blk try alloc.dupe(u8, "");
    };
    defer alloc.free(main_rev);
    for (names.items) |name| {
        if (std.mem.eql(u8, name, "main")) continue;
        // commits on `name` not on main
        const argv = [_][]const u8{ "git", "rev-list", "--count", main_rev, "..", name };
        const cnt = gitStdout(alloc, &argv) orelse continue;
        defer alloc.free(cnt);
        const n = std.fmt.parseInt(usize, std.mem.trim(u8, cnt, " \t\r\n"), 10) catch 0;
        if (n > 0) {
            try out.append(alloc, try std.fmt.allocPrint(alloc, "{s} (+{d})", .{ name, n }));
        }
    }
}

fn computeFindings(alloc: std.mem.Allocator, stash_count: usize, dirty_count: usize, untracked_valuable: []const []const u8, branches_not_on_main: []const []const u8, prunable_worktrees: []const Worktree) ![]DestructiveFinding {
    var out = std.ArrayList(DestructiveFinding).empty;
    // §5.2 — stash is the canonical banned coordination tool.
    if (stash_count > 0) {
        const noun: []const u8 = if (stash_count == 1) "entry" else "entries";
        try out.append(alloc, .{
            .op = try alloc.dupe(u8, "stash"),
            .severity = .danger,
            .detail = try std.fmt.allocPrint(alloc, "{d} stash {s} present — restore, commit, or export to a patch before any destructive op", .{ stash_count, noun }),
        });
    }
    if (dirty_count > 0) {
        try out.append(alloc, .{
            .op = try alloc.dupe(u8, "restore"),
            .severity = .caution,
            .detail = try std.fmt.allocPrint(alloc, "{d} dirty tracked file(s); restore/clean would discard live edits — checkpoint-commit first", .{dirty_count}),
        });
    }
    if (untracked_valuable.len > 0) {
        try out.append(alloc, .{
            .op = try alloc.dupe(u8, "clean"),
            .severity = .danger,
            .detail = try std.fmt.allocPrint(alloc, "{d} valuable untracked artifact(s) (source/docs/scripts); `git clean` would delete unrecoverable work — add to salvage registry or commit first", .{untracked_valuable.len}),
        });
    }
    if (branches_not_on_main.len > 0) {
        try out.append(alloc, .{
            .op = try alloc.dupe(u8, "branch_deletion"),
            .severity = .caution,
            .detail = try std.fmt.allocPrint(alloc, "{d} branch(es) carry unique commits not on main — delete only after integration or preservation branch", .{branches_not_on_main.len}),
        });
    }
    if (prunable_worktrees.len > 0) {
        try out.append(alloc, .{
            .op = try alloc.dupe(u8, "worktree_deletion"),
            .severity = .caution,
            .detail = try std.fmt.allocPrint(alloc, "{d} prunable worktree(s); follow §5.3 retirement protocol (record revision, inspect dirty/untracked, preserve unique changes) before pruning", .{prunable_worktrees.len}),
        });
    }
    return try out.toOwnedSlice(alloc);
}

/// Build the live preservation report by inspecting Git state. Idempotent and
/// side-effect-free (read-only Git commands only). Caller owns the result.
pub fn buildPreservationReport(alloc: std.mem.Allocator) !PreservationReport {
    const head_rev = blk: {
        const r = gitStdout(alloc, &.{ "git", "rev-parse", "HEAD" }) orelse break :blk try alloc.dupe(u8, "");
        defer alloc.free(r);
        break :blk try alloc.dupe(u8, std.mem.trim(u8, r, " \t\r\n"));
    };
    errdefer alloc.free(head_rev);

    const current_branch = blk: {
        const r = gitStdout(alloc, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse break :blk try alloc.dupe(u8, "");
        defer alloc.free(r);
        break :blk try alloc.dupe(u8, std.mem.trim(u8, r, " \t\r\n"));
    };
    errdefer alloc.free(current_branch);

    const stash_count = blk: {
        const r = gitStdout(alloc, &.{ "git", "stash", "list" }) orelse break :blk 0;
        defer alloc.free(r);
        break :blk countLines(r);
    };

    var untracked_valuable = std.ArrayList([]const u8).empty;
    var dirty_count: usize = 0;
    try collectDirtyAndUntracked(alloc, &untracked_valuable, &dirty_count);
    errdefer {
        for (untracked_valuable.items) |p| alloc.free(p);
        untracked_valuable.deinit(alloc);
    }

    var branches_not_on_main = std.ArrayList([]const u8).empty;
    try collectUniqueBranches(alloc, &branches_not_on_main);
    errdefer {
        for (branches_not_on_main.items) |b| alloc.free(b);
        branches_not_on_main.deinit(alloc);
    }

    var worktrees = std.ArrayList(Worktree).empty;
    var prunable_worktrees = std.ArrayList(Worktree).empty;
    try collectWorktrees(alloc, &worktrees, &prunable_worktrees);
    errdefer {
        for (worktrees.items) |wt| {
            alloc.free(wt.path);
            alloc.free(wt.head);
            alloc.free(wt.branch);
        }
        worktrees.deinit(alloc);
        for (prunable_worktrees.items) |wt| {
            alloc.free(wt.path);
            alloc.free(wt.head);
            alloc.free(wt.branch);
        }
        prunable_worktrees.deinit(alloc);
    }

    const uv_slice = try untracked_valuable.toOwnedSlice(alloc);
    const bnm_slice = try branches_not_on_main.toOwnedSlice(alloc);
    const wt_slice = try worktrees.toOwnedSlice(alloc);
    const pr_slice = try prunable_worktrees.toOwnedSlice(alloc);

    const findings = try computeFindings(alloc, stash_count, dirty_count, uv_slice, bnm_slice, pr_slice);
    errdefer alloc.free(findings);

    var overall = Severity.safe;
    for (findings) |f| {
        if (f.severity == .danger) {
            overall = .danger;
            break;
        }
        if (f.severity == .caution) overall = .caution;
    }

    return .{
        .git_available = head_rev.len > 0,
        .head_revision = head_rev,
        .current_branch = current_branch,
        .stash_count = stash_count,
        .dirty_count = dirty_count,
        .untracked_valuable = uv_slice,
        .branches_not_on_main = bnm_slice,
        .worktrees = wt_slice,
        .prunable_worktrees = pr_slice,
        .destructive_findings = findings,
        .overall_risk = overall,
    };
}

fn writeStrList(w: *std.Io.Writer, items: []const []const u8) !void {
    try w.writeAll("[");
    for (items, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{s});
    }
    try w.writeAll("]");
}

/// Emit the report as JSON for `duo dev preserve` and `duo catalog`.
pub fn writePreservationReportJson(w: *std.Io.Writer, report: PreservationReport) !void {
    try w.print("{{\"schema\":\"{s}\",\"git_available\":{},\"head\":\"{s}\",\"branch\":\"{s}\",\"stash_count\":{d},\"dirty_count\":{d},\"untracked_valuable\":", .{ SCHEMA_VERSION, report.git_available, report.head_revision, report.current_branch, report.stash_count, report.dirty_count });
    try writeStrList(w, report.untracked_valuable);
    try w.writeAll(",\"branches_not_on_main\":");
    try writeStrList(w, report.branches_not_on_main);
    try w.writeAll(",\"worktrees\":[");
    for (report.worktrees, 0..) |wt, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"path\":\"{s}\",\"head\":\"{s}\",\"branch\":\"{s}\",\"prunable\":false}}", .{ wt.path, wt.head, wt.branch });
    }
    try w.writeAll("],\"prunable_worktrees\":[");
    for (report.prunable_worktrees, 0..) |wt, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"path\":\"{s}\",\"head\":\"{s}\",\"branch\":\"{s}\",\"prunable\":true}}", .{ wt.path, wt.head, wt.branch });
    }
    try w.writeAll("],\"destructive_findings\":[");
    for (report.destructive_findings, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"op\":\"{s}\",\"severity\":\"{s}\",\"detail\":\"{s}\"}}", .{ f.op, f.severity.name(), f.detail });
    }
    try w.print("],\"overall_risk\":\"{s}\"}}", .{report.overall_risk.name()});
}

test "git_preservation: isValuableUntracked filters caches, keeps source" {
    try std.testing.expect(isValuableUntracked("src/foo.zig"));
    try std.testing.expect(isValuableUntracked("docs/archive/pass14_constructive_evolution.md"));
    // CLAUDE.md ends in .md -> flagged valuable so it is *noticed*; its
    // disposition (agent-local isolate) is recorded in the salvage registry.
    try std.testing.expect(isValuableUntracked("CLAUDE.md"));
    try std.testing.expect(isValuableUntracked(".zig-cache/o/abc") == false);
    try std.testing.expect(isValuableUntracked("default.profraw") == false);
    try std.testing.expect(isValuableUntracked(".duo/cache/comptime/x.ducache") == false);
    try std.testing.expect(isValuableUntracked("examples/foo.duo"));
    // A no-ext binary artifact with no recognized extension is not auto-valuable.
    try std.testing.expect(isValuableUntracked("benchmark_c_fastmath") == false);
}

test "git_preservation: buildPreservationReport runs read-only git and frees cleanly" {
    const alloc = std.testing.allocator;
    var report = try buildPreservationReport(alloc);
    defer report.freeReport(alloc);
    // In this repo HEAD is always resolvable.
    try std.testing.expect(report.git_available);
    try std.testing.expect(report.head_revision.len > 0);
    // Project rule: stash list must stay empty.
    try std.testing.expect(report.stash_count == 0);
}

test "git_preservation: JSON round-trips through a parser" {
    const alloc = std.testing.allocator;
    var report = try buildPreservationReport(alloc);
    defer report.freeReport(alloc);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writePreservationReportJson(&aw.writer, report);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const root = parsed.value.object;
    try std.testing.expect(root.get("schema").?.string.len > 0);
    try std.testing.expect(root.get("overall_risk").?.string.len > 0);
    try std.testing.expect(root.get("destructive_findings").? == .array);
}
