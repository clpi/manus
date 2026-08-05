//! Pass 14 §18 — the fourteen required audits, machine-readable.
//!
//! Audits 1–2 (destructive Git, abandoned work) carry *live* data via
//! `git_preservation.zig` and `salvage_registry.zig`. Audits 3–14 are seeded
//! classifications of the repository's current state at Pass 14 introduction.
//! Together they form the constructive-evolution truth map: what is sovereign,
//! what is stale, what must shrink, and what may not be deleted without salvage.
const std = @import("std");
const git_preservation = @import("git_preservation.zig");
const salvage_registry = @import("salvage_registry.zig");

pub const Status = enum {
    canonical,
    partial,
    open,
    blocked,

    pub fn name(self: Status) []const u8 {
        return @tagName(self);
    }
};

pub const AuditEntry = struct {
    id: []const u8,
    title: []const u8,
    status: Status,
    owner: []const u8,
    finding: []const u8,
    /// True when the audit has a live data source (not just a seed classification).
    live: bool,
};

pub const audit_groups = [_]struct {
    group: []const u8,
    entries: []const AuditEntry,
}{
    .{ .group = "destructive_git", .entries = &.{
        .{ .id = "P14-A1", .title = "Destructive Git practices", .status = .partial, .owner = "src/git_preservation.zig", .finding = "`duo dev preserve` inventories stash, dirty files, valuable untracked artifacts, unique branches, prunable worktrees; not yet a CI pre-push hard gate.", .live = true },
    } },
    .{ .group = "abandoned_work", .entries = &.{
        .{ .id = "P14-A2", .title = "Abandoned work inventory", .status = .partial, .owner = "src/salvage_registry.zig", .finding = "Seed salvage records cover stale pass-name stubs, prunable worktrees, unmerged branch, untracked agent state; more dormancy sweeps pending.", .live = true },
    } },
    .{ .group = "dependency_sovereignty", .entries = &.{
        .{ .id = "P14-A3", .title = "Dependency sovereignty classification", .status = .partial, .owner = "src/dependency_manifest.zig", .finding = "Seed manifest classifies Zig/Clang/Lua/wasm/git/MCP/LSP; LLVM marked forbidden_architectural; exit paths recorded.", .live = true },
    } },
    .{ .group = "architecture_parity", .entries = &.{
        .{ .id = "P14-A4", .title = "Architecture parity matrix", .status = .partial, .owner = "src/target_model.zig", .finding = "`architecture_matrix` in target_model + pass14 catalog; AArch64 Mach-O subset proven; wasm decode + x86/windows rows honest partial/open.", .live = true },
    } },
    .{ .group = "target_assumptions", .entries = &.{
        .{ .id = "P14-A5", .title = "Target assumptions audit", .status = .partial, .owner = "src/native_backend.zig", .finding = "Direct backend hardcodes ARM64 (pointer width, Mach-O, bl/adrp/add relocations). Assumptions are localized to the backend, not embedded in semantic layers (Pass 14 §2.2).", .live = false },
    } },
    .{ .group = "compatibility_layers", .entries = &.{
        .{ .id = "P14-A6", .title = "Compatibility layer inventory", .status = .partial, .owner = "src/pass4_boxed_inventory.zig", .finding = "Boxing inventory tracks lua_Value intermediaries; adapter-cost records (allocates? copies? boxes? dispatches?) not yet universal.", .live = false },
    } },
    .{ .group = "lowest_level_interfaces", .entries = &.{
        .{ .id = "P14-A7", .title = "Lowest-level capability map", .status = .partial, .owner = "src/native_backend.zig + lib/std/hardware.duo", .finding = "Bytes (WP-05 blob), pointers, atomics partially exposed; direct object emission and executable-memory primitives partially sovereign; syscalls/threads/GPU continuations open.", .live = false },
    } },
    .{ .group = "compression", .entries = &.{
        .{ .id = "P14-A8", .title = "Semantic compression audit", .status = .partial, .owner = "src/semantic_compression.zig + pass14 drift findings", .finding = "Real drift found: AGENTS.md references five stale pass-name stubs (see salvage registry); duplicated pass plan names are a P10 high blocker.", .live = false },
    } },
    .{ .group = "prerelease_compatibility", .entries = &.{
        .{ .id = "P14-A9", .title = "Pre-release compatibility classification", .status = .partial, .owner = "src/pass11_catalog.zig", .finding = "Backend/representation/runtime profiles made explicit (Pass 11 WP-02); remaining provisional command surfaces and syntax not yet fully classified remove/migrate/stabilize.", .live = false },
    } },
    .{ .group = "lua_supremacy", .entries = &.{
        .{ .id = "P14-A10", .title = "Lua supremacy readiness", .status = .partial, .owner = "src/codegen.zig + runtime", .finding = "Lua superset preserved on dynamic paths; typed .duo paths eliminate lua_Value when native-scalar proven. AOT via C backend; no differential Lua suite or adaptive JIT yet.", .live = false },
    } },
    .{ .group = "cross_language_convergence", .entries = &.{
        .{ .id = "P14-A11", .title = "Cross-language importer convergence", .status = .partial, .owner = "src/sim.zig + src/c_sim_import.zig", .finding = "Single SIM v0 + descriptor + ABI architecture for C import; one shared `abi.specialize` transform. Other importers (Wasm-as-input, foreign schemas) must reuse the same SIM, not parallel frameworks.", .live = false },
    } },
    .{ .group = "development_ergonomics", .entries = &.{
        .{ .id = "P14-A12", .title = "Development ergonomics metrics", .status = .partial, .owner = "build.zig + scripts/", .finding = "Clean build is fast; incremental via .zig-cache; `duo dev` control plane + agent-smoke exist. Diagnostic latency / repair-quality metrics not yet measured.", .live = false },
    } },
    .{ .group = "architectural_currency", .entries = &.{
        .{ .id = "P14-A13", .title = "Architectural currency loop", .status = .open, .owner = "src/arch_currency.zig (future)", .finding = "No structured observe→classify→record mechanism for external language/compiler/hardware advances yet. Manual awareness only.", .live = false },
    } },
    .{ .group = "api_staleness", .entries = &.{
        .{ .id = "P14-A14", .title = "API staleness sweep", .status = .partial, .owner = "src/meta_module.zig + docs/catalogs/directives.md", .finding = "`@comp.*` canonical names tracked; internal `normalizeDirective` still maps to underscore canonicals (open AGENTS.md gap). Stale redirect-stub doc references flagged in salvage registry.", .live = false },
    } },
};

pub fn writeAuditSummaryJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print("{{\"schema\":\"pass14-audit-v0\",\"audit_groups\":[", .{});
    for (audit_groups, 0..) |g, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"group\":\"{s}\",\"entries\":[", .{g.group});
        for (g.entries, 0..) |e, j| {
            if (j > 0) try w.writeAll(",");
            try w.print(
                "{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"owner\":\"{s}\",\"finding\":\"{s}\",\"live\":{}}}",
                .{ e.id, e.title, e.status.name(), e.owner, e.finding, e.live },
            );
        }
        try w.writeAll("]}");
    }
    try w.writeAll("],\"live_preservation\":");
    var report = try git_preservation.buildPreservationReport(alloc);
    defer report.freeReport(alloc);
    try git_preservation.writePreservationReportJson(w, report);
    try w.writeAll(",\"live_salvage\":");
    try salvage_registry.writeSalvageRegistryJson(w);
    try w.writeAll("}");
}

test "pass14_audit: all fourteen audits present" {
    var count: usize = 0;
    for (audit_groups) |g| count += g.entries.len;
    try std.testing.expectEqual(@as(usize, 14), count);
}

test "pass14_audit: JSON includes live preservation + salvage" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeAuditSummaryJson(&aw.writer, std.testing.allocator);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "P14-A1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "P14-A14") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "live_preservation") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "live_salvage") != null);
}
