//! Pass 14 — constructive evolution catalog (`duo catalog` → `pass14`).
//!
//! Machine-readable projection of the permanent development philosophy:
//! permanent priority order, milestones, deliverables, success criteria,
//! reconciliation strategies, dependency classes, prohibited outcomes, and the
//! live preservation + salvage + audit summaries. This is the *process* catalog
//! layered over Pass 13's coordination control plane.
const std = @import("std");
const pass14_constructive_audit = @import("pass14_constructive_audit.zig");
const git_preservation = @import("git_preservation.zig");
const salvage_registry = @import("salvage_registry.zig");

pub const SCHEMA_VERSION = "pass14-catalog-v0";
pub const PLAN_PATH = "docs/plans/pass14_constructive_evolution.md";

pub const Pillar = struct {
    id: []const u8,
    title: []const u8,
};

/// Pass 14 title — the four permanent development-philosophy pillars.
pub const pillars: []const Pillar = &.{
    .{ .id = "constructive_evolution", .title = "Constructive evolution — reconcile before replacing, preserve before deleting" },
    .{ .id = "architectural_sovereignty", .title = "Architectural sovereignty — own essential capabilities; no hidden semantic authorities" },
    .{ .id = "universal_performance", .title = "Universal performance — best practical performance across all major architectures" },
    .{ .id = "living_compiler", .title = "Living compiler development — stay current; shrink over time; never freeze provisional APIs" },
};

/// Pass 14 §1 — permanent priority order (strictly ranked).
pub const priority_order: []const Pillar = &.{
    .{ .id = "1_runtime_performance", .title = "Maximum runtime performance (fastest valid realization)" },
    .{ .id = "2_sovereignty", .title = "Architectural sovereignty and no required dependencies" },
    .{ .id = "3_ergonomics", .title = "Development ergonomics" },
    .{ .id = "4_compression", .title = "Maximum semantic power per permanent concept (compression)" },
};

pub const Milestone = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    owner: []const u8,
};

/// Pass 14 §20 — nine initial milestones. M1 + M2 are delivered in this pass.
pub const milestones: []const Milestone = &.{
    .{ .id = "P14-M1", .title = "Preservation-aware repository operations", .status = "done", .owner = "src/git_preservation.zig (duo dev preserve)" },
    .{ .id = "P14-M2", .title = "Salvage registry (seeded with real findings)", .status = "done", .owner = "src/salvage_registry.zig" },
    .{ .id = "P14-M3", .title = "Classified dependency manifest", .status = "open", .owner = "src/dependency_manifest.zig (future)" },
    .{ .id = "P14-M4", .title = "Cross-architecture target matrix", .status = "open", .owner = "src/target_model.zig extension" },
    .{ .id = "P14-M5", .title = "Direct low-level substrate proof", .status = "open", .owner = "future" },
    .{ .id = "P14-M6", .title = "Cross-language semantic proof", .status = "partial", .owner = "src/sim.zig + abi.specialize" },
    .{ .id = "P14-M7", .title = "Architecture-specific realization proof", .status = "partial", .owner = "src/native_backend.zig" },
    .{ .id = "P14-M8", .title = "Architectural currency loop", .status = "open", .owner = "src/arch_currency.zig (future)" },
    .{ .id = "P14-M9", .title = "Shrink proof (semantic compression)", .status = "partial", .owner = "src/semantic_compression.zig" },
};

pub const Deliverable = struct {
    letter: []const u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 14 §22 — required deliverables per execution (live ones marked).
pub const deliverables: []const Deliverable = &.{
    .{ .letter = "A", .title = "Executive summary", .status = "partial" },
    .{ .letter = "B", .title = "Git preservation report", .status = "live" },
    .{ .letter = "C", .title = "Salvage matrix", .status = "live" },
    .{ .letter = "D", .title = "Dependency matrix", .status = "open" },
    .{ .letter = "E", .title = "Architecture performance matrix", .status = "open" },
    .{ .letter = "F", .title = "Compatibility-layer matrix", .status = "partial" },
    .{ .letter = "G", .title = "Lowest-level capability map", .status = "partial" },
    .{ .letter = "H", .title = "Compression report", .status = "partial" },
    .{ .letter = "I", .title = "Compatibility table", .status = "partial" },
    .{ .letter = "J", .title = "Lua readiness report", .status = "partial" },
    .{ .letter = "K", .title = "Cross-language report", .status = "partial" },
    .{ .letter = "L", .title = "Architectural currency report", .status = "open" },
    .{ .letter = "M", .title = "Enforcement report", .status = "partial" },
    .{ .letter = "N", .title = "Integration proof", .status = "live" },
};

pub const SuccessCriterion = struct {
    id: u8,
    title: []const u8,
    status: []const u8,
};

/// Pass 14 §23 — thirty success criteria. M1+M2 close #1–#3, #5.
pub const success_criteria: []const SuccessCriterion = &.{
    .{ .id = 1, .title = "Destructive Git operations are exceptional and audited", .status = "partial" },
    .{ .id = 2, .title = "Dirty work cannot be silently discarded", .status = "partial" },
    .{ .id = 3, .title = "Worktrees cannot be removed without preservation", .status = "partial" },
    .{ .id = 4, .title = "New findings cause reconciliation before deletion", .status = "partial" },
    .{ .id = 5, .title = "Removed implementations have salvage records", .status = "partial" },
    .{ .id = 6, .title = "Useful tests/algorithms/diagnostics/evidence survive supersession", .status = "open" },
    .{ .id = 7, .title = "Essential semantics independent of external frameworks", .status = "partial" },
    .{ .id = 8, .title = "Temporary dependencies have explicit exit paths", .status = "open" },
    .{ .id = 9, .title = "Duo exposes the lowest useful systems interfaces", .status = "partial" },
    .{ .id = 10, .title = "High-level ergonomics derive from low-level power", .status = "partial" },
    .{ .id = 11, .title = "Compatibility layers exist only where semantically justified", .status = "partial" },
    .{ .id = 12, .title = "Unreleased Duo mistakes are not permanent compatibility burdens", .status = "partial" },
    .{ .id = 13, .title = "Lua compatibility remains a first-class product", .status = "partial" },
    .{ .id = 14, .title = "Lua semantics do not force Lua implementation costs into specialized code", .status = "partial" },
    .{ .id = 15, .title = "Cross-language work uses canonical semantic foundations", .status = "partial" },
    .{ .id = 16, .title = "Major features have explicit architecture coverage", .status = "open" },
    .{ .id = 17, .title = "Target-specific strengths are exploited", .status = "partial" },
    .{ .id = 18, .title = "Portable semantics do not imply mediocre generic realization", .status = "partial" },
    .{ .id = 19, .title = "Compiler APIs remain current with meaningful external advances", .status = "open" },
    .{ .id = 20, .title = "Architectural discoveries adopted/adapted/rejected quickly", .status = "open" },
    .{ .id = 21, .title = "New permanent mechanisms reduce existing complexity", .status = "partial" },
    .{ .id = 22, .title = "Source, architecture, dependencies, workflow shrink over time", .status = "partial" },
    .{ .id = 23, .title = "Runtime performance remains the first priority", .status = "canonical" },
    .{ .id = 24, .title = "Compile time remains excellent", .status = "partial" },
    .{ .id = 25, .title = "Diagnostics remain beautiful, causal, and dense", .status = "partial" },
    .{ .id = 26, .title = "Agents coordinate without erasing one another's work", .status = "partial" },
    .{ .id = 27, .title = "Self-hosting becomes easier", .status = "open" },
    .{ .id = 28, .title = "Ward consumes general low-level capabilities rather than hacks", .status = "partial" },
    .{ .id = 29, .title = "The repository accumulates knowledge rather than resetting", .status = "partial" },
    .{ .id = 30, .title = "Duo never becomes stale through passive compatibility with its own past", .status = "open" },
};

pub const Strategy = struct {
    name: []const u8,
    summary: []const u8,
};

/// Pass 14 §6 — reconciliation strategies.
pub const reconciliation_strategies: []const Strategy = &.{
    .{ .name = "refit", .summary = "Adapt implementation to the canonical system" },
    .{ .name = "strategic_refactor", .summary = "Change ownership/representation while preserving behavior" },
    .{ .name = "merge", .summary = "Combine complementary implementations" },
    .{ .name = "extract", .summary = "Move reusable algorithms/descriptors/tests/diagnostics/fixtures" },
    .{ .name = "generalize", .summary = "Project-specific machinery → reusable Duo foundation" },
    .{ .name = "specialize", .summary = "Retain general path + optimized target realizations" },
    .{ .name = "lower", .summary = "Replace compat infra with a lower-level primitive" },
    .{ .name = "isolate", .summary = "Keep an experiment explicit and bounded" },
    .{ .name = "translate", .summary = "Port valuable host-language logic into Duo" },
    .{ .name = "preserve_as_evidence", .summary = "Convert a failed approach into a regression/negative test/rejected-decision record" },
    .{ .name = "retire_through_replacement", .summary = "Delete only after behavior, tests, provenance, and knowledge have moved" },
};

pub const DependencyClass = struct {
    name: []const u8,
    summary: []const u8,
};

/// Pass 14 §8 — dependency classification (each dependency must record these).
pub const dependency_classes: []const DependencyClass = &.{
    .{ .name = "bootstrap", .summary = "Temporary build/compile host (exit path required)" },
    .{ .name = "optional_backend", .summary = "Optional portability backend (never canonical)" },
    .{ .name = "optional_integration", .summary = "Optional foreign integration" },
    .{ .name = "development_tool", .summary = "Dev/profiling tool, not on the compile path" },
    .{ .name = "platform_interface", .summary = "Platform-provided interface (libc, kernel)" },
    .{ .name = "imported_source", .summary = "Explicit user-selected imported software" },
    .{ .name = "forbidden_architectural", .summary = "Must never become a hidden semantic authority" },
};

pub const prohibited_outcomes: []const []const u8 = &.{
    "destroys unreviewed work",
    "uses stash as routine coordination",
    "deletes worktrees to avoid integration",
    "reverts mixed-value work without salvage",
    "deletes code because a new design exists",
    "introduces permanent dependencies for owned capabilities",
    "makes an external compiler canonical",
    "optimizes only one architecture",
    "hardcodes ISA assumptions into semantic layers",
    "creates wrappers without semantic value",
    "preserves unpublished mistakes",
    "forces Lua representation costs into specialized code",
    "creates importer-specific semantic frameworks",
    "introduces narrow syntax without concept reduction",
    "remains stale because an API already exists",
    "reports completion without integration and proof",
};

fn writePillars(w: *std.Io.Writer, key: []const u8, items: []const Pillar) !void {
    try w.print("\"{s}\":[", .{key});
    for (items, 0..) |p, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\"}}", .{ p.id, p.title });
    }
    try w.writeAll("]");
}

pub fn writePass14Json(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print(
        \\"pass14":{{"pass":14,"mission":"Constructive evolution, architectural sovereignty, universal performance, living compiler development","schema":"{s}","plan":"{s}"
    , .{ SCHEMA_VERSION, PLAN_PATH });
    try w.writeAll(",");
    try writePillars(w, "pillars", pillars);
    try w.writeAll(",");
    try writePillars(w, "priority_order", priority_order);

    try w.writeAll(",\"milestones\":[");
    for (milestones, 0..) |m, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"owner\":\"{s}\"}}", .{ m.id, m.title, m.status, m.owner });
    }
    try w.writeAll("],\"deliverables\":[");
    for (deliverables, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"letter\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ d.letter, d.title, d.status });
    }
    try w.writeAll("],\"success_criteria\":[");
    for (success_criteria, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":{d},\"title\":\"{s}\",\"status\":\"{s}\"}}", .{ s.id, s.title, s.status });
    }
    try w.writeAll("],\"reconciliation_strategies\":[");
    for (reconciliation_strategies, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"name\":\"{s}\",\"summary\":\"{s}\"}}", .{ s.name, s.summary });
    }
    try w.writeAll("],\"dependency_classes\":[");
    for (dependency_classes, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"name\":\"{s}\",\"summary\":\"{s}\"}}", .{ c.name, c.summary });
    }
    try w.writeAll("],\"prohibited_outcomes\":[");
    for (prohibited_outcomes, 0..) |o, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{o});
    }
    try w.writeAll("],\"audits\":");
    try pass14_constructive_audit.writeAuditSummaryJson(w, alloc);
    try w.writeAll(",\"preservation\":");
    var report = try git_preservation.buildPreservationReport(alloc);
    defer report.freeReport(alloc);
    try git_preservation.writePreservationReportJson(w, report);
    try w.writeAll(",\"salvage\":");
    try salvage_registry.writeSalvageRegistryJson(w);
    try w.writeAll("}");
}

test "pass14_catalog: writePass14Json structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass14Json(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass14\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P14-M1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P14-A14") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "retire_through_replacement") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "forbidden_architectural") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "overall_risk") != null);
    // writePass14Json emits a bare "pass14":{...} member (convention: embedded in
    // the root object by pass3_catalog). Wrap it before parsing as a document.
    const wrapped = try std.fmt.allocPrint(std.testing.allocator, "{{{s}}}", .{out});
    defer std.testing.allocator.free(wrapped);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, wrapped, .{});
    defer parsed.deinit();
    const root = parsed.value.object.get("pass14").?.object;
    try std.testing.expectEqual(@as(usize, 30), root.get("success_criteria").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 4), root.get("pillars").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 4), root.get("priority_order").?.array.items.len);
}
