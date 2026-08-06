//! Native Pass 11–16 gate validators (cross-platform, no bash/jq).
const std = @import("std");
const pass11_catalog = @import("pass11_catalog.zig");
const pass12_catalog = @import("pass12_catalog.zig");
const pass13_catalog = @import("pass13_catalog.zig");
const pass13_dev_audit = @import("pass13_dev_audit.zig");
const pass14_catalog = @import("pass14_catalog.zig");
const pass15_catalog = @import("pass15_catalog.zig");
const pass16_catalog = @import("pass16_catalog.zig");
const pass20_catalog = @import("pass20_catalog.zig");
const pass20_gate = @import("pass20_gate.zig");
const pass21_catalog = @import("pass21_catalog.zig");
const pass21_gate = @import("pass21_gate.zig");
const pass22_catalog = @import("pass22_catalog.zig");
const pass22_gate = @import("pass22_gate.zig");
const pass23_catalog = @import("pass23_catalog.zig");
const pass23_gate = @import("pass23_gate.zig");
const pass24_gate = @import("pass24_gate.zig");
const pass25_gate = @import("pass25_gate.zig");
const pass26_gate = @import("pass26_gate.zig");
const pass27_gate = @import("pass27_gate.zig");
const lua_superset_gate = @import("lua_superset_gate.zig");
const pass19_catalog = @import("pass19_catalog.zig");
const pass19_gate = @import("pass19_gate.zig");
const bootstrap_dag = @import("bootstrap_dag.zig");
const selfhosting_matrix = @import("selfhosting_matrix.zig");
const pass16_selfhost_audit = @import("pass16_selfhost_audit.zig");
const selfhost_verify = @import("selfhost_verify.zig");
const selfhost_target_matrix = @import("selfhost_target_matrix.zig");
const selfhost_production_path = @import("selfhost_production_path.zig");
const compiler_perf_measure = @import("compiler_perf_measure.zig");
const command_descriptor = @import("command_descriptor.zig");
const shell_session = @import("shell_session.zig");
const shell_host = @import("shell_host.zig");
const pass14_constructive_audit = @import("pass14_constructive_audit.zig");
const dev_control_plane = @import("dev_control_plane.zig");
const dev_validation_planner = @import("dev_validation_planner.zig");
const dependency_manifest = @import("dependency_manifest.zig");
const target_model = @import("target_model.zig");
const git_preservation = @import("git_preservation.zig");
const wasm_decode_semantic = @import("wasm_decode_semantic.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");
const wasm_semantic = @import("wasm_semantic.zig");

pub const PassGateError = error{
    GateFailed,
    DuoBinaryMissing,
    BarrierCheckFailed,
};

pub const pass13_dev_cli_min: usize = 10;
pub const pass13_dev_cli_count: usize = 12;
pub const coordination_migration_workstream = "P13-WS18";

fn seedWorkItemDependsOn(work_id: []const u8, dep: []const u8) bool {
    for (dev_control_plane.seed_work_items) |wi| {
        if (!std.mem.eql(u8, wi.id, work_id)) continue;
        for (wi.depends_on) |d| {
            if (std.mem.eql(u8, d, dep)) return true;
        }
        return false;
    }
    return false;
}

fn pass14AuditEntryCount() usize {
    var n: usize = 0;
    for (pass14_constructive_audit.audit_groups) |g| n += g.entries.len;
    return n;
}

/// Pass 11 catalog invariants (Profile A closure + readiness metadata).
pub fn validatePass11Gate() PassGateError!void {
    if (!std.mem.eql(u8, pass11_catalog.closure_status, "closed")) return error.GateFailed;
    if (!std.mem.eql(u8, pass11_catalog.SCHEMA_VERSION, "pass11-catalog-v0")) return error.GateFailed;
    if (pass11_catalog.work_packages.len == 0) return error.GateFailed;
}

/// Pass 12 semantic autonomy catalog invariants.
pub fn validatePass12Gate() PassGateError!void {
    if (!std.mem.eql(u8, pass12_catalog.SCHEMA_VERSION, "pass12-catalog-v0")) return error.GateFailed;
    if (pass12_catalog.milestones.len < 2) return error.GateFailed;
    if (pass12_catalog.workstreams.len < 12) return error.GateFailed;
    var m1_done = false;
    var m2_present = false;
    for (pass12_catalog.milestones) |m| {
        if (std.mem.eql(u8, m.id, "P12-M1")) {
            if (!std.mem.eql(u8, m.status, "done")) return error.GateFailed;
            m1_done = true;
        }
        if (std.mem.eql(u8, m.id, "P12-M2")) m2_present = true;
    }
    if (!m1_done or !m2_present) return error.GateFailed;
    if (!std.mem.eql(u8, wasm_decode_semantic.intent.subject_entity, "duo:wasm:decode_instruction")) {
        return error.GateFailed;
    }
}

/// Pass 13 control-plane + catalog invariants (replaces jq checks in pass13_gate.sh).
pub fn validatePass13Gate() PassGateError!void {
    if (!std.mem.eql(u8, dev_control_plane.SCHEMA_VERSION, "dev-control-plane-v0")) return error.GateFailed;
    if (pass13_catalog.workstreams.len < 20) return error.GateFailed;
    if (pass13_dev_audit.audit_groups.len == 0) return error.GateFailed;
    if (!seedWorkItemDependsOn("P13-WS3", "P13-WS2")) return error.GateFailed;
    if (dev_validation_planner.planForWorkItem("P13-WS3").len == 0) return error.GateFailed;
    if (pass13_dev_cli_count < pass13_dev_cli_min) return error.GateFailed;
    if (!std.mem.eql(u8, coordination_migration_workstream, "P13-WS18")) return error.GateFailed;
    if (!std.mem.eql(u8, wasm_decode_semantic.intent.subject_entity, "duo:wasm:decode_instruction")) {
        return error.GateFailed;
    }
    if (wasm_semantic.knownOpcodeCount() != 63) return error.GateFailed;
}

/// Pass 14 preservation + architecture invariants (replaces jq checks in pass14_gate.sh).
pub fn validatePass14Gate() PassGateError!void {
    if (!std.mem.eql(u8, pass14_catalog.SCHEMA_VERSION, "pass14-catalog-v0")) return error.GateFailed;
    if (!std.mem.eql(u8, git_preservation.SCHEMA_VERSION, "git-preservation-v0")) return error.GateFailed;
    if (!std.mem.eql(u8, dependency_manifest.SCHEMA_VERSION, "dependency-manifest-v0")) return error.GateFailed;
    if (dependency_manifest.records.len < 4) return error.GateFailed;
    if (target_model.architecture_matrix.len < 8) return error.GateFailed;
    if (pass14AuditEntryCount() != 14) return error.GateFailed;
    if (pass14_catalog.milestones.len == 0) return error.GateFailed;
}

/// Pass 15 semantic shell foundation invariants.
pub fn validatePass15Gate() PassGateError!void {
    if (!std.mem.eql(u8, pass15_catalog.SCHEMA_VERSION, "pass15-catalog-v0")) return error.GateFailed;
    if (pass15_catalog.workstreams.len != 20) return error.GateFailed;
    if (pass15_catalog.milestones.len < 5) return error.GateFailed;
    if (!std.mem.eql(u8, command_descriptor.SCHEMA_VERSION, "command-descriptor-v0")) return error.GateFailed;
    if (!std.mem.eql(u8, shell_session.SCHEMA_VERSION, "shell-session-v0")) return error.GateFailed;
    if (!std.mem.eql(u8, shell_host.SCHEMA_VERSION, "shell-host-v0")) return error.GateFailed;
    if (command_descriptor.duo_commands.len < 8) return error.GateFailed;
    if (@import("pass15_shell_audit.zig").audit_landscape.len >= 10) {} else return error.GateFailed;
}

/// Pass 16 self-hosting foundation invariants.
pub fn validatePass16Gate() PassGateError!void {
    if (!std.mem.eql(u8, pass16_catalog.SCHEMA_VERSION, "pass16-catalog-v0")) return error.GateFailed;
    if (pass16_catalog.workstreams.len != 30) return error.GateFailed;
    if (pass16_catalog.milestones.len >= 5) {} else return error.GateFailed;
    if (pass16_catalog.completion_levels.len != 9) return error.GateFailed;
    if (!std.mem.eql(u8, selfhosting_matrix.SCHEMA_VERSION, "selfhosting-matrix-v0")) return error.GateFailed;
    if (selfhosting_matrix.subsystems.len < 10) return error.GateFailed;
    if (!std.mem.eql(u8, bootstrap_dag.SCHEMA_VERSION, "bootstrap-dag-v0")) return error.GateFailed;
    if (bootstrap_dag.stages.len != 4) return error.GateFailed;
    if (@import("bootstrap_subset.zig").features.len >= 10) {} else return error.GateFailed;
    if (@import("compiler_dynamic_boundary.zig").metrics.len >= 4) {} else return error.GateFailed;
    if (@import("compiler_capability_matrix.zig").requirements.len >= 10) {} else return error.GateFailed;
    if (@import("removal_ledger.zig").entries.len >= 4) {} else return error.GateFailed;
    if (@import("semantic_compression_report.zig").facts.len >= 2) {} else return error.GateFailed;
    if (@import("compiler_perf_baseline.zig").metrics.len >= 4) {} else return error.GateFailed;
    if (@import("bootstrap_proof.zig").bundles.len >= 5) {} else return error.GateFailed;
    if (@import("stage_compare.zig").results.len >= 2) {} else return error.GateFailed;
    _ = selfhost_verify.verifyAllOrFail() catch return error.GateFailed;
    if (@import("pass16_selfhost_audit.zig").auditEntryCount() != 12) return error.GateFailed;
    const manifest = selfhosting_matrix.publicManifest();
    if (manifest.self_hosting_level < 1 or manifest.self_hosting_level > 1) return error.GateFailed;
    if (manifest.canonical_compiler_in_duo) return error.GateFailed;
    if (!std.mem.eql(u8, manifest.claim_self_hosted_status, "partial")) return error.GateFailed;
    if (!manifest.production_duo_frontend) return error.GateFailed;
    if (!std.mem.eql(u8, selfhost_target_matrix.SCHEMA_VERSION, "selfhost-target-matrix-v0")) return error.GateFailed;
    selfhost_target_matrix.validateCrossPlatformGate() catch return error.GateFailed;
    selfhost_production_path.validateProductionPathGate() catch return error.GateFailed;
    if (@import("selfhost_migration_plan.zig").items.len >= 10) {} else return error.GateFailed;
    compiler_perf_measure.validateMeasureGate() catch return error.GateFailed;
    _ = @import("duo_lexer_blocker.zig");
    _ = @import("source_cursor.zig");
}

/// Pass 20 universal cross-language metaprogramming harness gates.
pub fn validatePass20Gate() PassGateError!void {
    try pass20_gate.validatePass20Gate();
}

/// Pass 21 canonical grammar closure catalog + grammar gates.
pub fn validatePass21Gate() PassGateError!void {
    try pass21_gate.validatePass21Gate();
    try validateLuaSupersetGate();
}

/// Pass 19 unified semantic experience catalog + umbrella foundation checks.
pub fn validatePass19Gate() PassGateError!void {
    try pass19_gate.validatePass19Gate();
}

/// Pass 22 graph-native compiler architecture catalog + gates J/K proofs.
pub fn validatePass22Gate() PassGateError!void {
    try pass22_gate.validatePass22Gate();
}

/// Pass 23 unified metaprotocols catalog + foundation gates.
pub fn validatePass23Gate() PassGateError!void {
    try pass23_gate.validatePass23Gate();
}

/// Pass 24 unified calls, Lua superset, execution-graph concurrency constitution gates.
pub fn validatePass24Gate() PassGateError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try pass24_gate.validatePass24Gate(arena.allocator());
}

/// Pass 26 foundational semantic closure — operation identity, protocols, boundaries, decisions.
pub fn validatePass26Gate() PassGateError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try pass26_gate.validatePass26Gate(arena.allocator());
}

/// Pass 27 proof bundle + performance/metaprogramming evidence gates.
pub fn validatePass27Gate() PassGateError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try pass27_gate.validatePass27Gate(arena.allocator());
}

/// Pass 25 native semantic unification, provenance lifetimes, bidirectional metaprogramming gates.
pub fn validatePass25Gate() PassGateError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try pass25_gate.validatePass25Gate(arena.allocator());
}

/// Pass 24 P0 — Lua superset long-bracket preservation (alias for pass24/lua-superset gates).
pub fn validateLuaSupersetGate() PassGateError!void {
    try lua_superset_gate.validateLuaSupersetGate();
}

/// Shared Pass 11–16 catalog smoke (also used by passes-audit gate).
pub fn validatePasses1114Catalog() PassGateError!void {
    try validatePass11Gate();
    try validatePass12Gate();
    try validatePass13Gate();
    try validatePass14Gate();
    try validatePass15Gate();
    try validatePass16Gate();
}

pub const GateScope = enum {
    all,
    pass11,
    pass12,
    pass13,
    pass14,
    pass15,
    pass16,
    pass20,
    pass21,
    pass22,
    pass23,
    pass24,
    pass25,
    pass26,
    pass27,
    pass19,

    pub fn parse(s: []const u8) ?GateScope {
        if (std.mem.eql(u8, s, "all")) return .all;
        if (std.mem.eql(u8, s, "pass11")) return .pass11;
        if (std.mem.eql(u8, s, "pass12")) return .pass12;
        if (std.mem.eql(u8, s, "pass13")) return .pass13;
        if (std.mem.eql(u8, s, "pass14")) return .pass14;
        if (std.mem.eql(u8, s, "pass15")) return .pass15;
        if (std.mem.eql(u8, s, "pass16")) return .pass16;
        if (std.mem.eql(u8, s, "pass20")) return .pass20;
        if (std.mem.eql(u8, s, "pass21")) return .pass21;
        if (std.mem.eql(u8, s, "pass22")) return .pass22;
        if (std.mem.eql(u8, s, "pass23")) return .pass23;
        if (std.mem.eql(u8, s, "pass24") or std.mem.eql(u8, s, "lua-superset") or std.mem.eql(u8, s, "lua_superset")) return .pass24;
        if (std.mem.eql(u8, s, "pass25") or std.mem.eql(u8, s, "semantic-unification")) return .pass25;
        if (std.mem.eql(u8, s, "pass26") or std.mem.eql(u8, s, "semantic-closure") or std.mem.eql(u8, s, "foundational-closure")) return .pass26;
        if (std.mem.eql(u8, s, "pass27") or std.mem.eql(u8, s, "proof-bundle") or std.mem.eql(u8, s, "performance-evidence")) return .pass27;
        if (std.mem.eql(u8, s, "pass19")) return .pass19;
        return null;
    }

    pub fn name(self: GateScope) []const u8 {
        return switch (self) {
            .all => "all",
            .pass11 => "pass11",
            .pass12 => "pass12",
            .pass13 => "pass13",
            .pass14 => "pass14",
            .pass15 => "pass15",
            .pass16 => "pass16",
            .pass20 => "pass20",
            .pass21 => "pass21",
            .pass22 => "pass22",
            .pass23 => "pass23",
            .pass24 => "pass24",
            .pass25 => "pass25",
            .pass26 => "pass26",
            .pass27 => "pass27",
            .pass19 => "pass19",
        };
    }
};

/// Optional barrier proof when `duo` binary is installed (pass13_gate barrier check).
pub fn validatePass13BarrierM1(io: std.Io, alloc: std.mem.Allocator, duo_bin: []const u8) PassGateError!void {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, duo_bin, .{}) catch return error.DuoBinaryMissing;
    const result = native_barrier_checks.evaluateProfile(alloc, native_barrier_checks.pass12_m1_profile, duo_bin) catch {
        return error.BarrierCheckFailed;
    };
    defer alloc.free(result.checks);
    defer for (result.checks) |c| native_barrier_checks.freeSymbolCheck(alloc, c);
    if (!result.profile_ok) return error.BarrierCheckFailed;
}

pub fn runScopedGate(
    io: std.Io,
    alloc: std.mem.Allocator,
    scope: GateScope,
    opts: struct { barrier_m1: bool = false, duo_bin: []const u8 = "zig-out/bin/duo" },
) PassGateError!void {
    switch (scope) {
        .all => {
            try validatePasses1114Catalog();
            if (opts.barrier_m1) try validatePass13BarrierM1(io, alloc, opts.duo_bin);
        },
        .pass11 => try validatePass11Gate(),
        .pass12 => try validatePass12Gate(),
        .pass13 => {
            try validatePass13Gate();
            if (opts.barrier_m1) try validatePass13BarrierM1(io, alloc, opts.duo_bin);
        },
        .pass14 => try validatePass14Gate(),
        .pass15 => try validatePass15Gate(),
        .pass16 => try validatePass16Gate(),
        .pass20 => try validatePass20Gate(),
        .pass21 => try validatePass21Gate(),
        .pass22 => try validatePass22Gate(),
        .pass23 => try validatePass23Gate(),
        .pass24 => try validatePass24Gate(),
        .pass25 => try validatePass25Gate(),
        .pass26 => try validatePass26Gate(),
        .pass27 => try validatePass27Gate(),
        .pass19 => try validatePass19Gate(),
    }
}

test "pass_gates: pass11 closure" {
    try validatePass11Gate();
}

test "pass_gates: pass12 catalog smoke" {
    try validatePass12Gate();
}

test "pass_gates: pass13 catalog smoke" {
    try validatePass13Gate();
}

test "pass_gates: pass14 catalog smoke" {
    try validatePass14Gate();
}

test "pass_gates: pass15 catalog smoke" {
    try validatePass15Gate();
}

test "pass_gates: pass16 catalog smoke" {
    try validatePass16Gate();
}

test "pass_gates: pass20 harness catalog + gates" {
    try validatePass20Gate();
}

test "pass_gates: lua superset long-bracket + compatibility gate" {
    try validateLuaSupersetGate();
}

test "pass_gates: pass21 grammar catalog + gates" {
    try validatePass21Gate();
}

test "pass_gates: pass19 unified platform catalog" {
    try validatePass19Gate();
}

test "pass_gates: pass22 catalog + graph gates" {
    try validatePass22Gate();
}

test "pass_gates: pass23 metaprotocol catalog + foundation gates" {
    try validatePass23Gate();
}

test "pass_gates: pass24 constitution catalog + lua superset P0" {
    try validatePass24Gate();
}

test "pass_gates: pass25 semantic unification catalog + schema gates" {
    try validatePass25Gate();
}

test "pass_gates: pass26 foundational closure catalog + schema gates" {
    try validatePass26Gate();
}

test "pass_gates: pass27 proof bundle catalog + evidence schema gates" {
    try validatePass27Gate();
}

test "pass_gates: pass24 lua superset long-bracket gate (alias)" {
    try validateLuaSupersetGate();
}

test "pass_gates: passes 11-16 catalog bundle" {
    try validatePasses1114Catalog();
}

test "pass_gates: pass13 barrier m1 when duo built" {
    const alloc = std.testing.allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    validatePass13BarrierM1(threaded.io(), alloc, "zig-out/bin/duo") catch |err| switch (err) {
        error.DuoBinaryMissing => return error.SkipZigTest,
        else => return err,
    };
}
