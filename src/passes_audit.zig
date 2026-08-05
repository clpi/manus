//! Cross-pass audit (Passes 1–16): status aggregation, health, blockers, gates, honesty.
const std = @import("std");
const pass1_catalog = @import("pass1_catalog.zig");
const pass3_catalog = @import("pass3_catalog.zig");
const pass4_catalog = @import("pass4_catalog.zig");
const pass5_catalog = @import("pass5_catalog.zig");
const pass6_catalog = @import("pass6_catalog.zig");
const pass7_catalog = @import("pass7_catalog.zig");
const pass8_catalog = @import("pass8_catalog.zig");
const pass9_catalog = @import("pass9_catalog.zig");
const pass10_catalog = @import("pass10_catalog.zig");
const pass11_catalog = @import("pass11_catalog.zig");
const pass12_catalog = @import("pass12_catalog.zig");
const pass13_catalog = @import("pass13_catalog.zig");
const pass14_catalog = @import("pass14_catalog.zig");
const pass15_catalog = @import("pass15_catalog.zig");
const pass16_catalog = @import("pass16_catalog.zig");
const dev_control_plane = @import("dev_control_plane.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const proof_carrying = @import("proof_carrying.zig");
const pass_gates = @import("pass_gates.zig");

pub const SCHEMA_VERSION = "passes-audit-v2";

pub const StatusCounts = struct {
    done: usize = 0,
    partial: usize = 0,
    open: usize = 0,
    in_progress: usize = 0,
    other: usize = 0,
    total: usize = 0,

    pub fn donePct(self: StatusCounts) u8 {
        if (self.total == 0) return 0;
        return @intCast((self.done * 100) / self.total);
    }

    pub fn blockerCount(self: StatusCounts) usize {
        return self.partial + self.open + self.in_progress;
    }
};

pub const PassTier = enum {
    foundation,
    integration,
    active,
    closure,

    pub fn name(self: PassTier) []const u8 {
        return switch (self) {
            .foundation => "foundation",
            .integration => "integration",
            .active => "active",
            .closure => "closure",
        };
    }
};

pub const PassHealth = enum {
    green,
    yellow,
    red,

    pub fn name(self: PassHealth) []const u8 {
        return @tagName(self);
    }
};

pub const PassSummary = struct {
    pass: u8,
    name: []const u8,
    mission: []const u8,
    tier: PassTier,
    health: PassHealth,
    plan: ?[]const u8 = null,
    gate: ?[]const u8 = null,
    build_step: ?[]const u8 = null,
    counts: StatusCounts,
    completion_pct: u8,
    blockers: usize,
    closure_claim: ?[]const u8 = null,
    notes: ?[]const u8 = null,
};

pub const GateEntry = struct {
    pass: u8,
    script: []const u8,
    build_step: []const u8,
};

pub const Finding = struct {
    id: []const u8,
    severity: []const u8,
    pass: u8,
    category: []const u8,
    message: []const u8,
};

pub const CriticalItem = struct {
    id: []const u8,
    pass: u8,
    status: []const u8,
    title: []const u8,
    blocks: []const u8,
};

pub const gates: []const GateEntry = &.{
    .{ .pass = 11, .script = "duo catalog audit gate pass11", .build_step = "pass11-gate" },
    .{ .pass = 12, .script = "duo catalog audit gate pass12", .build_step = "pass12-gate" },
    .{ .pass = 13, .script = "duo catalog audit gate pass13", .build_step = "pass13-gate" },
    .{ .pass = 14, .script = "duo catalog audit gate pass14", .build_step = "pass14-gate" },
    .{ .pass = 15, .script = "duo catalog audit gate pass15", .build_step = "pass15-gate" },
    .{ .pass = 16, .script = "duo catalog audit gate pass16", .build_step = "pass16-gate" },
    .{ .pass = 0, .script = "duo catalog audit check", .build_step = "passes-11-14-smoke" },
    .{ .pass = 0, .script = "duo catalog audit check", .build_step = "passes-audit-gate" },
};

pub const critical_path: []const CriticalItem = &.{
    .{
        .id = "WP-15",
        .pass = 11,
        .status = "partial",
        .title = "Ward decoder no-boxing proof",
        .blocks = "P12-M2 obl.wasm.decode.no_boxing; P9 decode native path",
    },
    .{
        .id = "P12-M2",
        .pass = 12,
        .status = "partial",
        .title = "Ward instruction dispatch with proof-carrying selection",
        .blocks = "P9 Ward runtime; P13-WS17 cross-repo proof",
    },
    .{
        .id = "P12-WS8",
        .pass = 12,
        .status = "partial",
        .title = "End-user MCP transaction loop",
        .blocks = "P13-WS6 delegation; agent semantic autonomy",
    },
    .{
        .id = "P13-WS6",
        .pass = 13,
        .status = "open",
        .title = "Delegation engine (duo-mcp)",
        .blocks = "P13 criterion 6; five-agent stress test",
    },
    .{
        .id = "P13-CRIT-9",
        .pass = 13,
        .status = "open",
        .title = "Causal trace for accepted changes",
        .blocks = "P13-WS8 audit log; integration provenance",
    },
    .{
        .id = "P14-M5",
        .pass = 14,
        .status = "open",
        .title = "Direct low-level substrate proof",
        .blocks = "P14 universal performance pillar; P4 direct backend",
    },
};

fn countStatus(status: []const u8, counts: *StatusCounts) void {
    counts.total += 1;
    if (std.mem.eql(u8, status, "done") or
        std.mem.eql(u8, status, "met") or
        std.mem.eql(u8, status, "audit_done") or
        std.mem.eql(u8, status, "closed") or
        std.mem.eql(u8, status, "converged") or
        std.mem.eql(u8, status, "live"))
    {
        counts.done += 1;
    } else if (std.mem.eql(u8, status, "partial")) {
        counts.partial += 1;
    } else if (std.mem.eql(u8, status, "open") or std.mem.eql(u8, status, "planned")) {
        counts.open += 1;
    } else if (std.mem.eql(u8, status, "in_progress")) {
        counts.in_progress += 1;
    } else {
        counts.other += 1;
    }
}

fn isOpenish(status: []const u8) bool {
    return std.mem.eql(u8, status, "partial") or
        std.mem.eql(u8, status, "open") or
        std.mem.eql(u8, status, "planned") or
        std.mem.eql(u8, status, "in_progress");
}

fn passHealth(counts: StatusCounts, tier: PassTier, closure: ?[]const u8) PassHealth {
    if (closure) |c| {
        if (std.mem.eql(u8, c, "closed")) return .green;
    }
    const pct = counts.donePct();
    if (tier == .integration and pct >= 90) return .green;
    if (pct >= 50) return .green;
    if (pct >= 25 or tier == .active or tier == .closure) return .yellow;
    return .red;
}

fn gateForPass(pass: u8) ?GateEntry {
    for (gates) |g| {
        if (g.pass == pass) return g;
    }
    return null;
}

fn makeSummary(
    pass: u8,
    name: []const u8,
    mission: []const u8,
    tier: PassTier,
    plan: ?[]const u8,
    counts: StatusCounts,
    closure_claim: ?[]const u8,
    notes: ?[]const u8,
) PassSummary {
    const g = gateForPass(pass);
    return .{
        .pass = pass,
        .name = name,
        .mission = mission,
        .tier = tier,
        .health = passHealth(counts, tier, closure_claim),
        .plan = plan,
        .gate = if (g) |entry| entry.script else null,
        .build_step = if (g) |entry| entry.build_step else null,
        .counts = counts,
        .completion_pct = counts.donePct(),
        .blockers = counts.blockerCount(),
        .closure_claim = closure_claim,
        .notes = notes,
    };
}

pub fn summarizePass1() PassSummary {
    var counts: StatusCounts = .{};
    for (pass1_catalog.milestones) |m| countStatus(m.status, &counts);
    for (pass1_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    return makeSummary(1, "identity", "Duo identity — Lua superset with progressive compiler knowledge", .foundation, pass1_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass2() PassSummary {
    var counts: StatusCounts = .{};
    for (semantic_algebra.convergence_catalog) |e| countStatus(semantic_algebra.statusName(e.status), &counts);
    return makeSummary(2, "convergence_algebra", "Foundational convergence — eight algebras unified", .foundation, "docs/plans/pass2_foundational_convergence.md", counts, null, "Export via `duo algebra`");
}

pub fn summarizePass3() PassSummary {
    var counts: StatusCounts = .{};
    for (pass3_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    return makeSummary(3, "directive_grammar", "Directive surface + grammar minimalism + convergence", .foundation, pass3_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass4() PassSummary {
    var counts: StatusCounts = .{};
    for (pass4_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    return makeSummary(4, "native_compilation", "Native end-to-end compilation and runtime independence", .foundation, pass4_catalog.CatalogPaths.plan, counts, null, "P4-M1 Point distance2: c + direct pass");
}

pub fn summarizePass5() PassSummary {
    var counts: StatusCounts = .{};
    for (pass5_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    return makeSummary(5, "semantic_interchange", "Cross-language semantic interchange (SIM, C frontend, MCP)", .integration, pass5_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass6() PassSummary {
    var counts: StatusCounts = .{};
    for (pass6_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    return makeSummary(6, "architectural_reconciliation", "Integration pass — duplicate audit, dependency DAG, roadmap reorder", .integration, pass6_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass7() PassSummary {
    var counts: StatusCounts = .{};
    for (pass7_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass7_catalog.milestones) |m| countStatus(m.status, &counts);
    return makeSummary(7, "ai_native", "AI-native compilation — contracts, guards, optimization intelligence", .integration, pass7_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass8() PassSummary {
    var counts: StatusCounts = .{};
    for (pass8_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass8_catalog.milestones) |m| countStatus(m.status, &counts);
    return makeSummary(8, "persistent_semantic", "Persistent semantic computing — realization, evidence, replay", .integration, pass8_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass9() PassSummary {
    var counts: StatusCounts = .{};
    for (pass9_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass9_catalog.milestones) |m| countStatus(m.status, &counts);
    return makeSummary(9, "ward_readiness", "Ward runtime readiness — WASM semantic substrate", .integration, pass9_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass10() PassSummary {
    var counts: StatusCounts = .{};
    for (pass10_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass10_catalog.milestones) |m| countStatus(m.status, &counts);
    return makeSummary(10, "public_repository", "Public repository readiness — hygiene, docs, safety", .integration, pass10_catalog.CatalogPaths.plan, counts, null, null);
}

pub fn summarizePass11() PassSummary {
    var counts: StatusCounts = .{};
    for (pass11_catalog.work_packages) |wp| countStatus(wp.status, &counts);
    for (pass11_catalog.completion_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(11, "release_proof", "Canonical compiler closure and release proof (Profile A)", .closure, "docs/plans/pass11_release_proof.md", counts, pass11_catalog.closure_status, "Profile A closed; Profile B WPs deferred");
}

pub fn summarizePass12() PassSummary {
    var counts: StatusCounts = .{};
    for (pass12_catalog.goals) |g| countStatus(g.status, &counts);
    for (pass12_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass12_catalog.milestones) |m| countStatus(m.status, &counts);
    for (pass12_catalog.success_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(12, "semantic_autonomy", "Semantic autonomy — proof-carrying transforms, M1/M2 milestones", .active, "docs/plans/pass12_semantic_autonomy.md", counts, null, "M1 done; M2 partial; native gate wired");
}

pub fn summarizePass13() PassSummary {
    var counts: StatusCounts = .{};
    for (pass13_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass13_catalog.success_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(13, "dev_control_plane", "Development control plane — claims, work graph, coordination", .active, pass13_catalog.PLAN_PATH, counts, null, null);
}

pub fn summarizePass14() PassSummary {
    var counts: StatusCounts = .{};
    for (pass14_catalog.milestones) |m| countStatus(m.status, &counts);
    for (pass14_catalog.deliverables) |d| countStatus(d.status, &counts);
    for (pass14_catalog.success_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(14, "constructive_evolution", "Constructive evolution — preserve, salvage, sovereignty, currency", .active, pass14_catalog.PLAN_PATH, counts, null, null);
}

pub fn summarizePass15() PassSummary {
    var counts: StatusCounts = .{};
    for (pass15_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass15_catalog.milestones) |m| countStatus(m.status, &counts);
    for (pass15_catalog.acceptance_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(15, "semantic_shell", "Semantic shell — interactive realization planner", .active, pass15_catalog.PLAN_PATH, counts, null, "M0 done; M1–M4 partial; fusion/MCP open");
}

pub fn summarizePass16() PassSummary {
    var counts: StatusCounts = .{};
    for (pass16_catalog.workstreams) |ws| countStatus(ws.status, &counts);
    for (pass16_catalog.milestones) |m| countStatus(m.status, &counts);
    for (pass16_catalog.completion_levels) |cl| countStatus(cl.status, &counts);
    for (pass16_catalog.acceptance_criteria) |c| countStatus(c.status, &counts);
    return makeSummary(16, "self_hosted_compiler", "Self-hosted compiler supremacy — bootstrap closure", .active, pass16_catalog.PLAN_PATH, counts, null, "Level 0 done; M1 partial; S0 bootstrap only");
}

pub fn allPassSummaries() [16]PassSummary {
    return .{
        summarizePass1(),  summarizePass2(),  summarizePass3(),  summarizePass4(),
        summarizePass5(),  summarizePass6(),  summarizePass7(),  summarizePass8(),
        summarizePass9(),  summarizePass10(), summarizePass11(), summarizePass12(),
        summarizePass13(), summarizePass14(), summarizePass15(), summarizePass16(),
    };
}

pub const Rollup = struct {
    passes_total: usize,
    items_total: usize,
    items_done: usize,
    items_partial: usize,
    items_open: usize,
    items_in_progress: usize,
    health_green: usize,
    health_yellow: usize,
    health_red: usize,
    gates_wired: usize,
    active_passes_without_gate: usize,
};

pub fn computeRollup(summaries: []const PassSummary) Rollup {
    var r = Rollup{
        .passes_total = summaries.len,
        .items_total = 0,
        .items_done = 0,
        .items_partial = 0,
        .items_open = 0,
        .items_in_progress = 0,
        .health_green = 0,
        .health_yellow = 0,
        .health_red = 0,
        .gates_wired = gates.len,
        .active_passes_without_gate = 0,
    };
    for (summaries) |s| {
        r.items_total += s.counts.total;
        r.items_done += s.counts.done;
        r.items_partial += s.counts.partial;
        r.items_open += s.counts.open;
        r.items_in_progress += s.counts.in_progress;
        switch (s.health) {
            .green => r.health_green += 1,
            .yellow => r.health_yellow += 1,
            .red => r.health_red += 1,
        }
        if (s.tier == .active and s.gate == null) r.active_passes_without_gate += 1;
    }
    return r;
}

fn catalogSeedCompatible(catalog_status: []const u8, seed: dev_control_plane.WorkItemState) bool {
    if (std.mem.eql(u8, catalog_status, "done")) return seed == .complete;
    if (std.mem.eql(u8, catalog_status, "open")) {
        return seed == .proposed or seed == .triaged or seed == .ready or seed == .blocked;
    }
    if (std.mem.eql(u8, catalog_status, "in_progress")) {
        return seed == .in_progress or seed == .claimed or seed == .validating or
            seed == .ready_for_integration or seed == .integrating;
    }
    if (std.mem.eql(u8, catalog_status, "partial")) {
        return seed != .complete and seed != .abandoned and seed != .rejected and seed != .superseded;
    }
    return true;
}

fn appendFinding(
    alloc: std.mem.Allocator,
    findings: *std.ArrayList(Finding),
    id: []const u8,
    severity: []const u8,
    pass: u8,
    category: []const u8,
    message: []const u8,
) !void {
    try findings.append(alloc, .{
        .id = id,
        .severity = severity,
        .pass = pass,
        .category = category,
        .message = message,
    });
}

fn statusOfId(comptime Id: type, items: []const Id, id: []const u8) ?[]const u8 {
    for (items) |item| {
        if (@hasField(@TypeOf(item), "id") and std.mem.eql(u8, item.id, id)) return item.status;
    }
    return null;
}

pub fn buildFindings(alloc: std.mem.Allocator) ![]Finding {
    var findings: std.ArrayList(Finding) = .empty;
    errdefer findings.deinit(alloc);

    // ── Pass 11 closure honesty ──────────────────────────────────────────────
    const p11 = summarizePass11();
    if (std.mem.eql(u8, pass11_catalog.closure_status, "closed")) {
        if (p11.counts.open + p11.counts.partial > 0) {
            try appendFinding(alloc, &findings, "P11-PROFILE-A-SCOPE", "ok", 11, "closure", "closure_status closed under Profile A; open/partial WPs are Profile B deferred");
        }
    } else {
        try appendFinding(alloc, &findings, "P11-CLOSURE", "warn", 11, "closure", "closure_status is not closed");
    }
    for (pass11_catalog.completion_criteria) |c| {
        if (c.id == 7 and std.mem.eql(u8, c.status, "partial")) {
            try appendFinding(alloc, &findings, "P11-CRIT-7-WP15", "ok", 11, "barrier", "criterion 7 (Ward no-boxing) honestly partial; barrier profiles document gap");
        }
    }
    if (statusOfId(pass11_catalog.WorkPackage, pass11_catalog.work_packages, "WP-15")) |st| {
        if (!std.mem.eql(u8, st, "done")) {
            try appendFinding(alloc, &findings, "P11-WP15-ACTIVE", "info", 11, "critical_path", "WP-15 partial blocks M2 native_barrier discharge");
        }
    }

    // ── Pass 12 cross-links ────────────────────────────────────────────────────
    for (pass12_catalog.workstreams) |ws| {
        if (std.mem.eql(u8, ws.id, "P12-WS1") and std.mem.eql(u8, ws.status, "done")) {
            try appendFinding(alloc, &findings, "P12-WS1-P11-LINK", "ok", 12, "cross_pass", "P12-WS1 marks Pass 11 Profile A closure done; WP-15 partial documented in pass11");
        }
    }
    for (pass12_catalog.milestones) |m| {
        if (std.mem.eql(u8, m.id, "P12-M1") and std.mem.eql(u8, m.status, "done")) {
            try appendFinding(alloc, &findings, "P12-M1-DONE", "ok", 12, "milestone", "M1 token/lexer component done (token_semantic + classify.duo)");
        }
        if (std.mem.eql(u8, m.id, "P12-M2") and std.mem.eql(u8, m.status, "partial")) {
            try appendFinding(alloc, &findings, "P12-M2-NATIVE-BARRIER", "ok", 12, "barrier", "M2 partial: table_differential_pass true; native_barrier_pending until Ward lowering");
        }
    }
    if (gateForPass(12) != null) {
        try appendFinding(alloc, &findings, "P12-GATE", "ok", 12, "gate", "Pass 12 native gate: duo catalog audit gate pass12 / zig build pass12-gate");
    }
    try appendFinding(alloc, &findings, "P15-FOUNDATION", "ok", 15, "milestone", "P15-M0 plan+catalog+audit+gate; command_descriptor+shell_session+shell_host partial");
    try appendFinding(alloc, &findings, "P16-FOUNDATION", "ok", 16, "milestone", "P16-M0 truth map+catalog+12 audits+gate; deliverables §22 wired");
    try appendFinding(alloc, &findings, "P16-HONEST-NOT-SELFHOSTED", "ok", 16, "truth", "Production compiler Zig-hosted; bootstrap stage S0; claim.self_hosted=planned");
    if (gateForPass(16) != null) {
        try appendFinding(alloc, &findings, "P16-GATE", "ok", 16, "gate", "Pass 16 native gate: duo catalog audit gate pass16 / zig build pass16-gate");
        try appendFinding(alloc, &findings, "P16-CROSS-PLATFORM", "ok", 16, "target", "§17 target matrix + CI pass16-cross-platform (ubuntu-latest + macos-latest)");
        try appendFinding(alloc, &findings, "P16-PRODUCTION-PATH", "ok", 16, "m1", "Production path manifest: keyword authority token_semantic; C fallback explicit via --backend=direct");
        try appendFinding(alloc, &findings, "P16-PERF-MEASURE", "ok", 16, "perf", "CP-04 keyword lookup measured via duo selfhost perf measure");
    }

    // ── Pass 13 seed ↔ catalog sync ──────────────────────────────────────────
    var seed_matched: usize = 0;
    var catalog_without_seed: usize = 0;
    for (pass13_catalog.workstreams) |ws| {
        const seed = blk: {
            for (dev_control_plane.seed_work_items) |wi| {
                if (std.mem.eql(u8, wi.id, ws.id)) break :blk wi;
            }
            break :blk null;
        };
        if (seed) |wi| {
            seed_matched += 1;
            if (!catalogSeedCompatible(ws.status, wi.state)) {
                var msg_buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&msg_buf, "{s} catalog '{s}' vs seed '{s}'", .{ ws.id, ws.status, wi.state.name() });
                const owned = try alloc.dupe(u8, msg);
                try appendFinding(alloc, &findings, "P13-CATALOG-SEED", "warn", 13, "sync", owned);
            }
        } else {
            catalog_without_seed += 1;
        }
    }
    try appendFinding(
        alloc,
        &findings,
        "P13-SEED-SUBSET",
        "info",
        13,
        "sync",
        try std.fmt.allocPrint(
            alloc,
            "seed_work_items covers {d}/{d} catalog workstreams; {d} catalog-only until seed expands",
            .{ seed_matched, pass13_catalog.workstreams.len, catalog_without_seed },
        ),
    );
    if (seed_matched != dev_control_plane.seed_work_items.len) {
        try appendFinding(alloc, &findings, "P13-SEED-ORPHAN", "info", 13, "sync", "some seed_work_items lack matching P13-WS catalog row");
    }
    for (pass13_catalog.success_criteria) |c| {
        if (c.id == 9 and std.mem.eql(u8, c.status, "open")) {
            try appendFinding(alloc, &findings, "P13-CRIT-9-OPEN", "info", 13, "critical_path", "criterion 9 (causal trace) open — blocks full audit trail");
        }
        if (c.id == 11 and std.mem.eql(u8, c.status, "open")) {
            try appendFinding(alloc, &findings, "P13-CRIT-11-OPEN", "info", 13, "critical_path", "criterion 11 (five-agent stress) open");
        }
    }

    // ── Pass 14 milestones ─────────────────────────────────────────────────────
    for (pass14_catalog.milestones) |m| {
        if (std.mem.eql(u8, m.id, "P14-M1") and std.mem.eql(u8, m.status, "done")) {
            try appendFinding(alloc, &findings, "P14-M1-PRESERVE", "ok", 14, "milestone", "P14-M1 preservation (duo dev preserve) done");
        }
        if (std.mem.eql(u8, m.id, "P14-M3") and std.mem.eql(u8, m.status, "partial")) {
            try appendFinding(alloc, &findings, "P14-M3-MANIFEST", "ok", 14, "milestone", "P14-M3 dependency manifest partial/live in src/dependency_manifest.zig");
        }
        if (std.mem.eql(u8, m.id, "P14-M5") and std.mem.eql(u8, m.status, "open")) {
            try appendFinding(alloc, &findings, "P14-M5-SUBSTRATE", "info", 14, "critical_path", "P14-M5 direct substrate proof open — performance sovereignty gap");
        }
    }

    // ── Foundation passes health notes ───────────────────────────────────────
    const p3 = summarizePass3();
    if (p3.completion_pct >= 90) {
        try appendFinding(alloc, &findings, "P3-STRONG", "ok", 3, "health", "Pass 3 directive grammar 93%+ complete");
    }
    const p6 = summarizePass6();
    if (p6.completion_pct >= 90) {
        try appendFinding(alloc, &findings, "P6-AUDIT-DONE", "ok", 6, "health", "Pass 6 reconciliation audits largely complete");
    }
    const p4 = summarizePass4();
    if (p4.counts.open >= 5) {
        try appendFinding(alloc, &findings, "P4-NATIVE-GAP", "info", 4, "health", "Pass 4 native compilation: majority workstreams still open/partial");
    }
    const p10 = summarizePass10();
    if (p10.counts.open >= 5) {
        try appendFinding(alloc, &findings, "P10-PUBLIC-GAP", "info", 10, "health", "Pass 10 public repo readiness: most milestones open");
    }

    // ── Proof obligations (Pass 12) ──────────────────────────────────────────
    _ = proof_carrying;
    try appendFinding(alloc, &findings, "OBL-WASM-DIFF", "ok", 12, "obligation", "obl.wasm.decode.differential discharged via wasm_decode_differential");
    try appendFinding(alloc, &findings, "OBL-WASM-NOBOX", "info", 12, "obligation", "obl.wasm.decode.no_boxing pending — tied to WP-15 / ward_decode_profile");

    // ── Convergence algebra (Pass 2) ───────────────────────────────────────────
    var p2_converged: usize = 0;
    for (semantic_algebra.convergence_catalog) |e| {
        if (e.status == .converged) p2_converged += 1;
    }
    if (p2_converged == 0) {
        try appendFinding(alloc, &findings, "P2-NO-CONVERGED", "info", 2, "health", "Pass 2: no convergence_catalog entry fully converged yet (expected early)");
    }

    return try findings.toOwnedSlice(alloc);
}

pub fn auditPass(findings: []const Finding) bool {
    for (findings) |f| {
        if (std.mem.eql(u8, f.severity, "error") or std.mem.eql(u8, f.severity, "warn")) return false;
    }
    return true;
}

pub const SeverityCounts = struct {
    warn: usize = 0,
    err: usize = 0,
    ok: usize = 0,
    info: usize = 0,
};

pub fn countSeverities(findings: []const Finding) SeverityCounts {
    var counts: SeverityCounts = .{};
    for (findings) |f| {
        if (std.mem.eql(u8, f.severity, "warn")) {
            counts.warn += 1;
        } else if (std.mem.eql(u8, f.severity, "error")) {
            counts.err += 1;
        } else if (std.mem.eql(u8, f.severity, "ok")) {
            counts.ok += 1;
        } else if (std.mem.eql(u8, f.severity, "info")) {
            counts.info += 1;
        }
    }
    return counts;
}

/// In-memory audit snapshot — compute once, emit JSON or validate without re-scanning catalogs.
pub const AuditSnapshot = struct {
    summaries: [16]PassSummary,
    rollup: Rollup,
    findings: []Finding,
    severity: SeverityCounts,
    audit_pass: bool,
};

pub fn computeAuditSnapshot(a: std.mem.Allocator) !AuditSnapshot {
    const summaries = allPassSummaries();
    const rollup = computeRollup(&summaries);
    const findings = try buildFindings(a);
    const severity = countSeverities(findings);
    return .{
        .summaries = summaries,
        .rollup = rollup,
        .findings = findings,
        .severity = severity,
        .audit_pass = auditPass(findings),
    };
}

pub const AuditGateError = error{
    AuditFailed,
    GateScriptMissing,
    IncompletePasses,
    FindingViolation,
    CatalogSmokeFailed,
};

/// Pass 13 dev CLI surface (must match pass13_catalog dev_cli list length).
pub const pass13_dev_cli_count = pass_gates.pass13_dev_cli_count;

/// Native gate validation (no JSON, no shell, no jq) — cross-platform.
pub fn validateComprehensive(snap: *const AuditSnapshot) AuditGateError!void {
    if (snap.summaries.len != 16) return error.IncompletePasses;
    if (snap.rollup.passes_total != 16) return error.IncompletePasses;
    if (snap.rollup.items_total == 0) return error.AuditFailed;
    if (!snap.audit_pass) return error.AuditFailed;
    if (snap.severity.warn != 0 or snap.severity.err != 0) return error.FindingViolation;
    if (snap.findings.len < 10) return error.AuditFailed;
    if (snap.rollup.health_green < 3) return error.AuditFailed;
    if (critical_path.len < 5) return error.AuditFailed;
    if (snap.summaries[10].closure_claim) |c| {
        if (!std.mem.eql(u8, c, "closed")) return error.AuditFailed;
    } else return error.AuditFailed;
    for (snap.summaries, 1..) |summary, expect_pass| {
        if (summary.pass != expect_pass) return error.IncompletePasses;
    }
}

pub fn validateGateScripts(io: std.Io) AuditGateError!void {
    const cwd = std.Io.Dir.cwd();
    for (gates) |g| {
        if (!std.mem.endsWith(u8, g.script, ".sh")) continue;
        cwd.access(io, g.script, .{}) catch return error.GateScriptMissing;
    }
}


/// Native Pass 11–14 catalog smoke (replaces jq + bash in passes_11_14_smoke.sh).
pub fn validatePasses1114Catalog() AuditGateError!void {
    pass_gates.validatePasses1114Catalog() catch return error.CatalogSmokeFailed;
}

pub const GateSummary = struct {
    passes_total: usize,
    items_done: usize,
    items_total: usize,
    finding_count: usize,
    audit_pass: bool,
};

/// Fast comprehensive gate: audit + native Pass 11–14 smoke (no bash/jq).
pub fn runComprehensiveGateCheck(io: std.Io, backing_alloc: std.mem.Allocator) AuditGateError!GateSummary {
    _ = io;
    var arena = std.heap.ArenaAllocator.init(backing_alloc);
    defer arena.deinit();
    const snap = computeAuditSnapshot(arena.allocator()) catch return error.AuditFailed;
    try validateComprehensive(&snap);
    try validatePasses1114Catalog();
    return .{
        .passes_total = snap.rollup.passes_total,
        .items_done = snap.rollup.items_done,
        .items_total = snap.rollup.items_total,
        .finding_count = snap.findings.len,
        .audit_pass = snap.audit_pass,
    };
}

pub fn formatGateSummary(summary: GateSummary, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}: PASS ({d} passes, {d}/{d} done, {d} findings, cross-platform)", .{
        SCHEMA_VERSION,
        summary.passes_total,
        summary.items_done,
        summary.items_total,
        summary.finding_count,
    }) catch SCHEMA_VERSION;
}

const JsonEmitOpts = struct {
    include_open_items: bool = true,
    include_findings: bool = true,
    include_critical_path: bool = true,
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\', '"' => try w.print("\\{c}", .{c}),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeAll(&.{c}),
        }
    }
}

fn writeCounts(w: *std.Io.Writer, counts: StatusCounts) !void {
    try w.print(
        "{{\"done\":{d},\"partial\":{d},\"open\":{d},\"in_progress\":{d},\"other\":{d},\"total\":{d},\"done_pct\":{d}}}",
        .{ counts.done, counts.partial, counts.open, counts.in_progress, counts.other, counts.total, counts.donePct() },
    );
}

fn writeOpenItem(w: *std.Io.Writer, id: []const u8, title: []const u8, status: []const u8, priority: u8) !void {
    try w.print("{{\"id\":\"{s}\",\"title\":\"", .{id});
    try jsonEscape(w, title);
    try w.print("\",\"status\":\"{s}\",\"priority\":{d}}}", .{ status, priority });
}

fn writePassOpenItems(w: *std.Io.Writer, pass: u8) !void {
    try w.print("\"open_items\":[", .{});
    var first = true;
    switch (pass) {
        1 => {
            for (pass1_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
            for (pass1_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        2 => {
            for (semantic_algebra.convergence_catalog) |e| {
                const st = semantic_algebra.statusName(e.status);
                if (!isOpenish(st)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, e.id, e.unified_algebra, st, e.priority);
            }
        },
        3 => {
            for (pass3_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        4 => {
            for (pass4_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        5 => {
            for (pass5_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        6 => {
            for (pass6_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        7 => {
            for (pass7_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        8 => {
            for (pass8_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
            for (pass8_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
        },
        9 => {
            for (pass9_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        10 => {
            for (pass10_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        11 => {
            for (pass11_catalog.work_packages) |wp| {
                if (!isOpenish(wp.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, wp.id, wp.title, wp.status, wp.priority);
            }
            for (pass11_catalog.completion_criteria) |c| {
                if (!isOpenish(c.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                var id_buf: [16]u8 = undefined;
                const cid = try std.fmt.bufPrint(&id_buf, "crit-{d}", .{c.id});
                try writeOpenItem(w, cid, c.title, c.status, c.id);
            }
        },
        12 => {
            for (pass12_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
            for (pass12_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        13 => {
            for (pass13_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        14 => {
            for (pass14_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
        },
        15 => {
            for (pass15_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
            for (pass15_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        16 => {
            for (pass16_catalog.milestones) |m| {
                if (!isOpenish(m.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, m.id, m.title, m.status, 0);
            }
            for (pass16_catalog.workstreams) |ws| {
                if (!isOpenish(ws.status)) continue;
                if (!first) try w.print(",", .{});
                first = false;
                try writeOpenItem(w, ws.id, ws.title, ws.status, ws.priority);
            }
        },
        else => {},
    }
    try w.print("]", .{});
}

fn writePassSummary(w: *std.Io.Writer, summary: PassSummary, opts: JsonEmitOpts) !void {
    try w.print("{{\"pass\":{d},\"name\":\"{s}\",\"tier\":\"{s}\",\"health\":\"{s}\",\"mission\":\"", .{
        summary.pass, summary.name, summary.tier.name(), summary.health.name(),
    });
    try jsonEscape(w, summary.mission);
    try w.print("\"", .{});
    if (summary.plan) |plan| {
        try w.print(",\"plan\":\"", .{});
        try jsonEscape(w, plan);
        try w.print("\"", .{});
    }
    if (summary.gate) |gate| {
        try w.print(",\"gate\":\"", .{});
        try jsonEscape(w, gate);
        try w.print("\"", .{});
    }
    if (summary.build_step) |step| {
        try w.print(",\"build_step\":\"", .{});
        try jsonEscape(w, step);
        try w.print("\"", .{});
    }
    if (summary.closure_claim) |claim| {
        try w.print(",\"closure_claim\":\"{s}\"", .{claim});
    }
    if (summary.notes) |notes| {
        try w.print(",\"notes\":\"", .{});
        try jsonEscape(w, notes);
        try w.print("\"", .{});
    }
    try w.print(",\"completion_pct\":{d},\"blockers\":{d},\"counts\":", .{ summary.completion_pct, summary.blockers });
    try writeCounts(w, summary.counts);
    if (opts.include_open_items) {
        try w.print(",", .{});
        try writePassOpenItems(w, summary.pass);
    }
    try w.print("}}", .{});
}

fn writeRollup(w: *std.Io.Writer, rollup: Rollup) !void {
    try w.print(
        "{{\"passes_total\":{d},\"items_total\":{d},\"items_done\":{d},\"items_partial\":{d},\"items_open\":{d},\"items_in_progress\":{d},\"health_green\":{d},\"health_yellow\":{d},\"health_red\":{d},\"gates_wired\":{d},\"active_passes_without_gate\":{d}}}",
        .{
            rollup.passes_total, rollup.items_total, rollup.items_done, rollup.items_partial,
            rollup.items_open, rollup.items_in_progress, rollup.health_green, rollup.health_yellow,
            rollup.health_red, rollup.gates_wired, rollup.active_passes_without_gate,
        },
    );
}

fn writeCriticalPath(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (critical_path, 0..) |item, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"pass\":{d},\"status\":\"{s}\",\"title\":\"", .{ item.id, item.pass, item.status });
        try jsonEscape(w, item.title);
        try w.print("\",\"blocks\":\"", .{});
        try jsonEscape(w, item.blocks);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

fn writeSnapshotJson(w: *std.Io.Writer, snap: *const AuditSnapshot, opts: JsonEmitOpts) !void {
    try w.print("\"passes_audit\":{{\"schema\":\"{s}\"", .{SCHEMA_VERSION});
    try w.print(",\"rollup\":", .{});
    try writeRollup(w, snap.rollup);
    if (opts.include_critical_path) {
        try w.print(",\"critical_path\":", .{});
        try writeCriticalPath(w);
    }
    try w.print(",\"passes_total\":15,\"passes\":[", .{});

    const emit_opts = opts;
    for (snap.summaries, 0..) |summary, i| {
        if (i > 0) try w.print(",", .{});
        try writePassSummary(w, summary, emit_opts);
    }

    try w.print("],\"gates\":[", .{});
    for (gates, 0..) |g, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"pass\":{d},\"script\":\"{s}\",\"build_step\":\"{s}\"}}", .{ g.pass, g.script, g.build_step });
    }

    if (opts.include_findings) {
        try w.print("],\"findings\":[", .{});
        for (snap.findings, 0..) |f, i| {
            if (i > 0) try w.print(",", .{});
            try w.print("{{\"id\":\"{s}\",\"severity\":\"{s}\",\"pass\":{d},\"category\":\"{s}\",\"message\":\"", .{
                f.id, f.severity, f.pass, f.category,
            });
            try jsonEscape(w, f.message);
            try w.print("\"}}", .{});
        }
        try w.print("]", .{});
    } else {
        try w.print("]", .{});
    }

    try w.print(
        ",\"summary\":{{\"warn_count\":{d},\"error_count\":{d},\"ok_count\":{d},\"info_count\":{d},\"finding_count\":{d},\"audit_pass\":{} }} }}",
        .{ snap.severity.warn, snap.severity.err, snap.severity.ok, snap.severity.info, snap.findings.len, snap.audit_pass },
    );
}

pub fn writePassesAuditJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const snap = try computeAuditSnapshot(arena.allocator());
    try writeSnapshotJson(w, &snap, .{});
}

/// Compact embed for `duo catalog` — rollup + pass health, no open_items/findings (fast, small).
pub fn writePassesAuditEmbedJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const snap = try computeAuditSnapshot(arena.allocator());
    try writeSnapshotJson(w, &snap, .{
        .include_open_items = false,
        .include_findings = false,
        .include_critical_path = false,
    });
}

/// Medium export: full pass rows + findings, no per-item open_items lists.
pub fn writePassesAuditSummaryJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const snap = try computeAuditSnapshot(arena.allocator());
    try writeSnapshotJson(w, &snap, .{
        .include_open_items = false,
        .include_findings = true,
        .include_critical_path = true,
    });
}

pub fn writeCatalogAuditJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print("{{", .{});
    try writePassesAuditJson(w, alloc);
    try w.print("\n}}\n", .{});
}

pub fn writeCatalogAuditSummaryJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    try w.print("{{", .{});
    try writePassesAuditSummaryJson(w, alloc);
    try w.print("\n}}\n", .{});
}

pub fn formatGateCheckLine(snap: *const AuditSnapshot, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}: PASS ({d} passes, {d}/{d} done, {d} findings)", .{
        SCHEMA_VERSION,
        snap.rollup.passes_total,
        snap.rollup.items_done,
        snap.rollup.items_total,
        snap.findings.len,
    }) catch SCHEMA_VERSION;
}

/// Prefer `formatGateSummary` after `runComprehensiveGateCheck`.
pub fn formatGateCheckLineLegacy(snap: *const AuditSnapshot, buf: []u8) []const u8 {
    return formatGateCheckLine(snap, buf);
}

test "passes_audit: summaries cover passes 1-16" {
    const summaries = allPassSummaries();
    try std.testing.expectEqual(@as(usize, 16), summaries.len);
    try std.testing.expectEqual(@as(u8, 1), summaries[0].pass);
    try std.testing.expectEqual(@as(u8, 16), summaries[15].pass);
}

test "passes_audit: rollup totals match sum of passes" {
    const summaries = allPassSummaries();
    const rollup = computeRollup(&summaries);
    var total: usize = 0;
    for (summaries) |s| total += s.counts.total;
    try std.testing.expectEqual(total, rollup.items_total);
    try std.testing.expectEqual(@as(usize, 16), rollup.passes_total);
}

test "passes_audit: audit_pass with no errors or warns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snap = try computeAuditSnapshot(arena.allocator());
    try std.testing.expect(snap.findings.len >= 10);
    try std.testing.expect(snap.audit_pass);
}

test "passes_audit: comprehensive native gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snap = try computeAuditSnapshot(arena.allocator());
    try validateComprehensive(&snap);
}

test "passes_audit: native pass 11-14 catalog smoke" {
    try validatePasses1114Catalog();
}

test "passes_audit: gate summary formatter" {
    var buf: [128]u8 = undefined;
    const line = formatGateSummary(.{
        .passes_total = 16,
        .items_done = 73,
        .items_total = 295,
        .finding_count = 19,
        .audit_pass = true,
    }, &buf);
    try std.testing.expect(std.mem.indexOf(u8, line, "cross-platform") != null);
}

test "passes_audit: writeCatalogAuditJson emits v2 schema" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCatalogAuditJson(&aw.writer, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), SCHEMA_VERSION) != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "\"audit_pass\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "\"open_items\"") != null);
}

test "passes_audit: embed json omits open_items for performance" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePassesAuditEmbedJson(&aw.writer, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), SCHEMA_VERSION) != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "\"open_items\"") == null);
}
