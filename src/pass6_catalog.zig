/// Pass 6 — architectural reconciliation, dependency audit, and convergence catalog.
const std = @import("std");
const pass4_catalog = @import("pass4_catalog.zig");

pub const CatalogPaths = struct {
    pub const plan = "docs/plans/pass6_architectural_reconciliation.md";
    pub const convergence = "docs/catalogs/convergence.md";
    pub const semantic_universe = "docs/semantic_universe.md";
    pub const pass2 = "docs/plans/pass2_foundational_convergence.md";
    pub const pass5 = "docs/plans/pass5_semantic_interchange.md";
    pub const rejected = "docs/catalogs/rejected_ideas.md";
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
    audit_area: []const u8,
};

/// Pass 6 workstreams — integration pass, no new language features.
pub const workstreams: []const Workstream = &.{
    .{ .id = "P6-01", .title = "Duplicate mechanism audit + duplication matrix", .status = "audit_done", .priority = 1, .audit_area = "duplication" },
    .{ .id = "P6-02", .title = "Compiler dependency DAG + coupling map", .status = "audit_done", .priority = 2, .audit_area = "dependencies" },
    .{ .id = "P6-03", .title = "Canonical source-of-truth table", .status = "audit_done", .priority = 3, .audit_area = "ownership" },
    .{ .id = "P6-04", .title = "Terminology + canonical glossary", .status = "audit_done", .priority = 4, .audit_area = "terminology" },
    .{ .id = "P6-05", .title = "Grammar/directive convergence audit", .status = "audit_done", .priority = 5, .audit_area = "grammar" },
    .{ .id = "P6-06", .title = "Descriptor + shape + knowledge lattice audit", .status = "audit_done", .priority = 6, .audit_area = "algebra" },
    .{ .id = "P6-07", .title = "Transformation registry vs codegen dispatch convergence", .status = "partial", .priority = 7, .audit_area = "transforms" },
    .{ .id = "P6-08", .title = "IR layer catalog + redundancy removal plan", .status = "audit_done", .priority = 8, .audit_area = "ir" },
    .{ .id = "P6-09", .title = "Native performance barrier reconciliation", .status = "audit_done", .priority = 9, .audit_area = "performance" },
    .{ .id = "P6-10", .title = "Self-hosting + bootstrap dependency audit", .status = "audit_done", .priority = 10, .audit_area = "bootstrap" },
    .{ .id = "P6-11", .title = "Agent workflow audit (MCP/LSP/graph/SIM)", .status = "audit_done", .priority = 11, .audit_area = "tooling" },
    .{ .id = "P6-12", .title = "Roadmap dependency reorder", .status = "audit_done", .priority = 12, .audit_area = "roadmap" },
    .{ .id = "P6-13", .title = "Architecture risk register", .status = "audit_done", .priority = 13, .audit_area = "risk" },
    .{ .id = "P6-14", .title = "Convergence scorecard (subsystem 0–5)", .status = "audit_done", .priority = 14, .audit_area = "scorecard" },
    .{ .id = "P6-15", .title = "Rejected ideas registry maintenance", .status = "audit_done", .priority = 15, .audit_area = "rejected" },
};

pub const Duplication = struct {
    id: []const u8,
    concept: []const u8,
    implementations: []const u8,
    canonical_owner: []const u8,
    migration: []const u8,
    priority: []const u8,
    status: []const u8,
};

pub const duplications: []const Duplication = &.{
    .{
        .id = "DUP-001",
        .concept = "Semantic export JSON",
        .implementations = "semantic_graph.writeJson | sim.writeSnapshotJson | duo catalog",
        .canonical_owner = "sim.Snapshot (external); SemanticGraph (internal lift)",
        .migration = "Graph lift → SIM projection; agents use duo sim / MCP duo_semantic_snapshot",
        .priority = "P1",
        .status = "partial",
    },
    .{
        .id = "DUP-002",
        .concept = "C header parsing",
        .implementations = "c_header_parse.zig (@ffi_gen) | c_frontend.zig (Pass 5 SIM)",
        .canonical_owner = "c_frontend.zig + c_layout_verify optional clang probe",
        .migration = "Route @ffi_gen through c_frontend; retire clang-preprocess-only path when parity proven",
        .priority = "P2",
        .status = "open",
    },
    .{
        .id = "DUP-003",
        .concept = "Foreign import",
        .implementations = "@c.import sema path | foreign_transpile (@foreign) | c_sim_import",
        .canonical_owner = "c_sim_import → SIM → foreign_adapter (Pass 5); @foreign remains text transpile only",
        .migration = "Document boundary; do not merge @foreign into SIM without adapter contract",
        .priority = "P1",
        .status = "partial",
    },
    .{
        .id = "DUP-004",
        .concept = "Transform dispatch",
        .implementations = "transform_engine registry | codegen fold_meta_* | comptimeMetaHook | meta_codegen",
        .canonical_owner = "transform_engine.zig (registry + contracts); single applyTransform dispatch TBD",
        .migration = "P6-07: dispatchMetaCombinator + requireMetaDispatchBeforeHook; migrate remaining fold_meta_* to applyTransform",
        .priority = "P0",
        .status = "partial",
    },
    .{
        .id = "DUP-005",
        .concept = "Directive naming / registry",
        .implementations = "meta_module.zig | legacy_directives.zig | directives.zig | parser at_builtin table",
        .canonical_owner = "meta_module.zig + pass3_catalog + docs/catalogs/directives.md",
        .migration = "legacy_directives maps underscore → @comp.*; remove parser duplicates after G-061 parity",
        .priority = "P1",
        .status = "partial",
    },
    .{
        .id = "DUP-006",
        .concept = "Compiler knowledge / native eligibility",
        .implementations = "types.StorageClass | semantic_algebra.KnowledgeLevel | codegen native_scalar_mode | dynamic_boundary",
        .canonical_owner = "semantic_algebra.KnowledgeLevel bridges StorageClass; codegen reads lattice",
        .migration = "Replace ad-hoc native checks with knowledgeOfType + callTransformEligible",
        .priority = "P0",
        .status = "partial",
    },
    .{
        .id = "DUP-007",
        .concept = "Agent semantic queries",
        .implementations = "duo graph | duo sim | duo catalog | MCP text scrape | LSP regex symbols",
        .canonical_owner = "duo catalog + duo sim + duo graph; MCP wraps CLI; LSP consumes SIM",
        .priority = "P1",
        .migration = "P5-08/09 partial; P6-11: LSP hover via SIM; deprecate scrape-only tools",
        .status = "partial",
    },
    .{
        .id = "DUP-008",
        .concept = "Call specialization",
        .implementations = "call.specialize transform | abi.specialize | @specialize attribute | mono.zig",
        .canonical_owner = "call.specialize (Duo calls); abi.specialize (foreign ABI); mono for generics",
        .migration = "Document three lanes; avoid fourth ad-hoc specialize path in codegen",
        .priority = "P2",
        .status = "partial",
    },
};

pub const Risk = struct {
    id: []const u8,
    title: []const u8,
    severity: []const u8,
    status: []const u8,
};

pub const risks: []const Risk = &.{
    .{ .id = "AR-001", .title = "codegen.zig monolith (28k lines) — transform/native/SIM paths uncoupled", .severity = "critical", .status = "open" },
    .{ .id = "AR-002", .title = "Transform registry declared but dispatch still fragmented in codegen", .severity = "critical", .status = "open" },
    .{ .id = "AR-003", .title = "Semantic graph vs SIM dual JSON — agent confusion without projection docs", .severity = "high", .status = "partial" },
    .{ .id = "AR-004", .title = "lua_Value boxing on typed paths (1871 refs in codegen.zig)", .severity = "high", .status = "partial" },
    .{ .id = "AR-005", .title = "LSP reimplements symbol scan instead of SIM/graph", .severity = "medium", .status = "partial" },
    .{ .id = "AR-006", .title = "duo-mcp req-module dylib load aborts standalone smoke scripts", .severity = "medium", .status = "open" },
    .{ .id = "AR-007", .title = "Parser hint overflow panic blocks duo-lsp rebuild on large server.duo", .severity = "medium", .status = "partial" },
    .{ .id = "AR-008", .title = "Competing C import parsers (@ffi_gen vs Pass 5 frontend)", .severity = "medium", .status = "open" },
};

pub const Scorecard = struct {
    subsystem: []const u8,
    simplicity: u8,
    semantic_consistency: u8,
    optimization: u8,
    tooling: u8,
    agent: u8,
    extensibility: u8,
    readiness: u8,
};

pub const scorecard: []const Scorecard = &.{
    .{ .subsystem = "semantic_algebra", .simplicity = 4, .semantic_consistency = 5, .optimization = 4, .tooling = 3, .agent = 4, .extensibility = 5, .readiness = 4 },
    .{ .subsystem = "transform_engine", .simplicity = 3, .semantic_consistency = 4, .optimization = 3, .tooling = 4, .agent = 5, .extensibility = 4, .readiness = 3 },
    .{ .subsystem = "semantic_graph", .simplicity = 3, .semantic_consistency = 4, .optimization = 2, .tooling = 3, .agent = 3, .extensibility = 4, .readiness = 3 },
    .{ .subsystem = "sim_v0", .simplicity = 4, .semantic_consistency = 4, .optimization = 3, .tooling = 3, .agent = 4, .extensibility = 4, .readiness = 3 },
    .{ .subsystem = "types/sema", .simplicity = 2, .semantic_consistency = 3, .optimization = 3, .tooling = 2, .agent = 2, .extensibility = 3, .readiness = 4 },
    .{ .subsystem = "codegen", .simplicity = 1, .semantic_consistency = 2, .optimization = 4, .tooling = 2, .agent = 2, .extensibility = 2, .readiness = 5 },
    .{ .subsystem = "native_backend", .simplicity = 3, .semantic_consistency = 3, .optimization = 4, .tooling = 2, .agent = 2, .extensibility = 3, .readiness = 3 },
    .{ .subsystem = "pass5_c_import", .simplicity = 4, .semantic_consistency = 4, .optimization = 3, .tooling = 3, .agent = 4, .extensibility = 4, .readiness = 3 },
    .{ .subsystem = "mcp_tooling", .simplicity = 3, .semantic_consistency = 3, .optimization = 2, .tooling = 4, .agent = 4, .extensibility = 3, .readiness = 3 },
    .{ .subsystem = "duo_lsp", .simplicity = 2, .semantic_consistency = 2, .optimization = 2, .tooling = 3, .agent = 2, .extensibility = 2, .readiness = 3 },
};

pub const SourceOfTruth = struct {
    concept: []const u8,
    owner: []const u8,
    query: []const u8,
};

/// One owner per major compiler concept — repo truth 2026-08-04.
pub const source_of_truth: []const SourceOfTruth = &.{
    .{ .concept = "grammar_surface", .owner = "docs/GRAMMAR_SPEC.md + parser.zig", .query = "duo_grammar_spec_read MCP" },
    .{ .concept = "keywords", .owner = "docs/catalogs/keywords.md + lexer.zig", .query = "duo catalog" },
    .{ .concept = "comp_directives", .owner = "meta_module.zig + docs/catalogs/directives.md", .query = "duo_meta_catalog MCP" },
    .{ .concept = "transform_registry", .owner = "transform_engine.zig", .query = "duo catalog / duo algebra" },
    .{ .concept = "shape_call_algebra", .owner = "semantic_algebra.zig", .query = "duo algebra" },
    .{ .concept = "internal_semantic_model", .owner = "semantic_graph.zig", .query = "duo graph <file>" },
    .{ .concept = "external_interchange", .owner = "sim.zig (sim-v0)", .query = "duo sim / duo_semantic_snapshot" },
    .{ .concept = "type_checking", .owner = "sema.zig + types.zig", .query = "duo check" },
    .{ .concept = "c_declaration_import", .owner = "c_frontend.zig → c_sim_import.zig", .query = "duo sim --import-c" },
    .{ .concept = "foreign_lowering", .owner = "foreign_adapter.zig + codegen.zig", .query = "duo dump-c" },
    .{ .concept = "native_eligibility", .owner = "dynamic_boundary.zig + semantic_algebra", .query = "@comp.why.*" },
    .{ .concept = "performance_barriers", .owner = "docs/catalogs/performance_barriers.md + pass4_boxed_inventory", .query = "duo_perf_gaps MCP" },
    .{ .concept = "agent_coordination", .owner = ".agents/AGENT_COORDINATION.md", .query = "duo_coordination_* MCP" },
    .{ .concept = "pass_tracking", .owner = "pass3_catalog … pass6_catalog", .query = "duo catalog" },
    .{ .concept = "rejected_designs", .owner = "docs/catalogs/rejected_ideas.md", .query = "pass6.rejected in catalog" },
};

pub const Refactor = struct {
    id: []const u8,
    title: []const u8,
    replaces: []const u8,
    effort: []const u8,
    status: []const u8,
};

pub const required_refactors: []const Refactor = &.{
    .{ .id = "R-01", .title = "Unified applyTransform dispatch", .replaces = "fold_meta_* + comptimeMetaHook triad", .effort = "high", .status = "partial" },
    .{ .id = "R-02", .title = "SIM projection from graph lift", .replaces = "Ad-hoc dual JSON exports (DUP-001)", .effort = "medium", .status = "partial" },
    .{ .id = "R-03", .title = "Knowledge-gated codegen", .replaces = "Scattered native_scalar_mode checks (DUP-006)", .effort = "medium", .status = "partial" },
    .{ .id = "R-04", .title = "Split codegen emission layers", .replaces = "28k-line monolith (AR-001)", .effort = "high", .status = "open" },
    .{ .id = "R-05", .title = "Consolidate C frontends", .replaces = "c_header_parse + c_frontend (DUP-002)", .effort = "medium", .status = "open" },
    .{ .id = "R-06", .title = "LSP semantic provider via SIM", .replaces = "Inline regex + popen (AR-005)", .effort = "medium", .status = "partial" },
};

/// Repo-truth metrics for dispatch/boxing convergence (updated when inventory test fails).
pub const metrics = struct {
    pub const codegen_lua_value_refs: usize = pass4_catalog.boxed_inventory.lua_value_refs;
    pub const codegen_lua_invoke_refs: usize = pass4_catalog.boxed_inventory.lua_invoke_refs;
    pub const codegen_fold_meta_refs: usize = 34;
    pub const gate_meta_dispatch_enforces: bool = true;
    pub const unified_apply_hook: bool = true;
    pub const tier1_parity_combinators: usize = 8;
};

pub const DependencyNode = struct {
    id: []const u8,
    file: []const u8,
    depends_on: []const []const u8,
};

/// High-level compiler DAG (not every import edge — architectural layers only).
pub const dependency_dag: []const DependencyNode = &.{
    .{ .id = "lexer", .file = "src/lexer.zig", .depends_on = &.{} },
    .{ .id = "parser", .file = "src/parser.zig", .depends_on = &.{ "lexer", "ast", "legacy_directives" } },
    .{ .id = "ast", .file = "src/ast.zig", .depends_on = &.{} },
    .{ .id = "types", .file = "src/types.zig", .depends_on = &.{"ast"} },
    .{ .id = "semantic_algebra", .file = "src/semantic_algebra.zig", .depends_on = &.{ "types" } },
    .{ .id = "sema", .file = "src/sema.zig", .depends_on = &.{ "types", "parser", "c_sim_import", "foreign_adapter", "abi_specialize" } },
    .{ .id = "sim", .file = "src/sim.zig", .depends_on = &.{ "types", "sema", "semantic_algebra" } },
    .{ .id = "semantic_graph", .file = "src/semantic_graph.zig", .depends_on = &.{ "types", "sema", "semantic_algebra", "transform_engine" } },
    .{ .id = "transform_engine", .file = "src/transform_engine.zig", .depends_on = &.{ "semantic_algebra", "meta_module" } },
    .{ .id = "c_frontend", .file = "src/c_frontend.zig", .depends_on = &.{} },
    .{ .id = "c_sim_import", .file = "src/c_sim_import.zig", .depends_on = &.{ "c_frontend", "sim" } },
    .{ .id = "foreign_adapter", .file = "src/foreign_adapter.zig", .depends_on = &.{ "sim", "types" } },
    .{ .id = "abi_specialize", .file = "src/abi_specialize.zig", .depends_on = &.{ "sim", "transform_engine" } },
    .{ .id = "codegen", .file = "src/codegen.zig", .depends_on = &.{ "sema", "types", "comptime", "meta_codegen", "transform_engine" } },
    .{ .id = "native_backend", .file = "src/native_backend.zig", .depends_on = &.{ "types", "codegen" } },
    .{ .id = "main", .file = "src/main.zig", .depends_on = &.{ "parser", "sema", "codegen", "sim", "semantic_graph", "pass3_catalog" } },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writePass6Json(w: *std.Io.Writer) !void {
    try w.print(
        \\"pass6":{{"mission":"architectural reconciliation — no new language features","governing_principle":"reduce total conceptual complexity","catalogs":{{
    , .{});
    try w.print("\"plan\":\"", .{});
    try jsonEscape(w, CatalogPaths.plan);
    try w.print("\",\"convergence\":\"", .{});
    try jsonEscape(w, CatalogPaths.convergence);
    try w.print("\",\"rejected\":\"", .{});
    try jsonEscape(w, CatalogPaths.rejected);
    try w.print("\"}},\"workstreams\":[", .{});

    for (workstreams, 0..) |ws, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{ws.id});
        try jsonEscape(w, ws.title);
        try w.print("\",\"status\":\"{s}\",\"priority\":{d},\"audit_area\":\"{s}\"}}", .{
            ws.status, ws.priority, ws.audit_area,
        });
    }

    try w.print("],\"duplications\":[", .{});
    for (duplications, 0..) |d, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"concept\":\"", .{d.id});
        try jsonEscape(w, d.concept);
        try w.print("\",\"implementations\":\"", .{});
        try jsonEscape(w, d.implementations);
        try w.print("\",\"canonical_owner\":\"", .{});
        try jsonEscape(w, d.canonical_owner);
        try w.print("\",\"migration\":\"", .{});
        try jsonEscape(w, d.migration);
        try w.print("\",\"priority\":\"{s}\",\"status\":\"{s}\"}}", .{ d.priority, d.status });
    }

    try w.print("],\"risks\":[", .{});
    for (risks, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{r.id});
        try jsonEscape(w, r.title);
        try w.print("\",\"severity\":\"{s}\",\"status\":\"{s}\"}}", .{ r.severity, r.status });
    }

    try w.print("],\"scorecard\":[", .{});
    for (scorecard, 0..) |s, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"subsystem\":\"{s}\",\"simplicity\":{d},\"semantic_consistency\":{d},\"optimization\":{d},\"tooling\":{d},\"agent\":{d},\"extensibility\":{d},\"readiness\":{d}}}",
            .{ s.subsystem, s.simplicity, s.semantic_consistency, s.optimization, s.tooling, s.agent, s.extensibility, s.readiness },
        );
    }

    try w.print("],\"source_of_truth\":[", .{});
    for (source_of_truth, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"concept\":\"", .{});
        try jsonEscape(w, row.concept);
        try w.print("\",\"owner\":\"", .{});
        try jsonEscape(w, row.owner);
        try w.print("\",\"query\":\"", .{});
        try jsonEscape(w, row.query);
        try w.print("\"}}", .{});
    }

    try w.print("],\"required_refactors\":[", .{});
    for (required_refactors, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"title\":\"", .{r.id});
        try jsonEscape(w, r.title);
        try w.print("\",\"replaces\":\"", .{});
        try jsonEscape(w, r.replaces);
        try w.print("\",\"effort\":\"{s}\",\"status\":\"{s}\"}}", .{ r.effort, r.status });
    }

    try w.print("],\"metrics\":{{\"codegen_lua_value_refs\":{d},\"codegen_lua_invoke_refs\":{d},\"codegen_fold_meta_refs\":{d},\"gate_meta_dispatch_enforces\":", .{
        metrics.codegen_lua_value_refs,
        metrics.codegen_lua_invoke_refs,
        metrics.codegen_fold_meta_refs,
    });
    try w.print("{s}", .{if (metrics.gate_meta_dispatch_enforces) "true" else "false"});
    try w.print(",\"unified_apply_hook\":", .{});
    try w.print("{s}", .{if (metrics.unified_apply_hook) "true" else "false"});
    try w.print(",\"tier1_parity_combinators\":{d}}},\"dependency_dag\":[", .{metrics.tier1_parity_combinators});

    for (dependency_dag, 0..) |n, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"file\":\"", .{n.id});
        try jsonEscape(w, n.file);
        try w.print("\",\"depends_on\":[", .{});
        for (n.depends_on, 0..) |dep, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("\"{s}\"", .{dep});
        }
        try w.print("]}}", .{});
    }

    try w.print(
        "],\"roadmap_order\":[\"knowledge_lattice\",\"descriptors\",\"shapes\",\"semantic_graph\",\"transformations\",\"representation\",\"native_backend\",\"runtime\",\"self_hosting\",\"sim\",\"cross_language_harness\"],\"invariants\":[\"one-owner-per-concept\",\"sim-not-internal-graph\",\"registry-before-dispatch\",\"no-mcp-only-semantics\",\"repo-truth-over-docs\"]}}",
        .{},
    );
}

test "pass6_catalog: writePass6Json emits valid structure" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writePass6Json(&aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"pass6\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "DUP-001") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "AR-001") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "source_of_truth") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "required_refactors") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "gate_meta_dispatch_enforces") != null);
}
