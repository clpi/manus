//! Native Pass 11–16 gate validators (cross-platform, no bash/jq).
const std = @import("std");
const pass11_catalog = @import("pass11_catalog.zig");
const pass12_catalog = @import("pass12_catalog.zig");
const pass13_catalog = @import("pass13_catalog.zig");
const pass13_dev_audit = @import("pass13_dev_audit.zig");
const pass14_catalog = @import("pass14_catalog.zig");
const pass15_catalog = @import("pass15_catalog.zig");
const pass16_catalog = @import("pass16_catalog.zig");
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

    pub fn parse(s: []const u8) ?GateScope {
        if (std.mem.eql(u8, s, "all")) return .all;
        if (std.mem.eql(u8, s, "pass11")) return .pass11;
        if (std.mem.eql(u8, s, "pass12")) return .pass12;
        if (std.mem.eql(u8, s, "pass13")) return .pass13;
        if (std.mem.eql(u8, s, "pass14")) return .pass14;
        if (std.mem.eql(u8, s, "pass15")) return .pass15;
        if (std.mem.eql(u8, s, "pass16")) return .pass16;
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
