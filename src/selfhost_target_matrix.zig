//! Pass 16 §17 — cross-architecture self-hosting target parity (honest, host-aware).
const std = @import("std");
const target_model = @import("target_model.zig");
const bootstrap_dag = @import("bootstrap_dag.zig");

pub const SCHEMA_VERSION = "selfhost-target-matrix-v0";

pub const TargetStatus = enum {
    proven,
    partial,
    open,
    planned,
    out_of_scope,

    pub fn name(self: TargetStatus) []const u8 {
        return @tagName(self);
    }
};

pub const TargetRow = struct {
    triple: []const u8,
    arch: target_model.Arch,
    os: target_model.Os,
    /// Host Zig compiler builds `duo` for this triple (via cross-compile or native).
    compiler_builds: TargetStatus,
    /// Built `duo` runs on this target.
    compiler_runs: TargetStatus,
    /// Compiler compiles its own canonical source on this target.
    compiler_self_host: TargetStatus,
    /// Native object / executable emission without hidden C fallback on declared path.
    object_emission: TargetStatus,
    /// Bootstrap stage reached for this target (S0–S3 label or `none`).
    bootstrap_stage: []const u8,
    /// Cross-compilation: host can emit artifacts for this triple without executing there.
    cross_compile_from_host: TargetStatus,
    notes: []const u8,
};

/// Honest §17 matrix — update rows when proofs land; gate enforces minimum coverage.
pub const rows: []const TargetRow = &.{
    .{
        .triple = "aarch64-macos",
        .arch = .aarch64,
        .os = .macos,
        .compiler_builds = .proven,
        .compiler_runs = .proven,
        .compiler_self_host = .open,
        .object_emission = .partial,
        .bootstrap_stage = "S0",
        .cross_compile_from_host = .partial,
        .notes = "Primary dev target; direct ARM64 Mach-O subset proven (Pass 11)",
    },
    .{
        .triple = "aarch64-linux-gnu",
        .arch = .aarch64,
        .os = .linux,
        .compiler_builds = .partial,
        .compiler_runs = .partial,
        .compiler_self_host = .open,
        .object_emission = .open,
        .bootstrap_stage = "S0",
        .cross_compile_from_host = .partial,
        .notes = "Zig cross-compile expected; direct backend not yet proven",
    },
    .{
        .triple = "x86_64-linux-gnu",
        .arch = .x86_64,
        .os = .linux,
        .compiler_builds = .proven,
        .compiler_runs = .proven,
        .compiler_self_host = .open,
        .object_emission = .open,
        .bootstrap_stage = "S0",
        .cross_compile_from_host = .partial,
        .notes = "CI ubuntu-latest: zig build + pass16 gates; C codegen path; direct x86-64 backend open (P16-WS20)",
    },
    .{
        .triple = "x86_64-macos",
        .arch = .x86_64,
        .os = .macos,
        .compiler_builds = .partial,
        .compiler_runs = .partial,
        .compiler_self_host = .open,
        .object_emission = .open,
        .bootstrap_stage = "S0",
        .cross_compile_from_host = .partial,
        .notes = "Rosetta / Intel Mac; same C path as Linux x86_64",
    },
    .{
        .triple = "wasm32-wasi",
        .arch = .wasm32,
        .os = .wasi,
        .compiler_builds = .partial,
        .compiler_runs = .partial,
        .compiler_self_host = .open,
        .object_emission = .partial,
        .bootstrap_stage = "S0",
        .cross_compile_from_host = .proven,
        .notes = "wasm32-wasi via zig build -Dtarget=wasm32-wasi; runtime bench partial",
    },
    .{
        .triple = "riscv64-linux-gnu",
        .arch = .unknown,
        .os = .linux,
        .compiler_builds = .planned,
        .compiler_runs = .planned,
        .compiler_self_host = .open,
        .object_emission = .open,
        .bootstrap_stage = "none",
        .cross_compile_from_host = .open,
        .notes = "Architecture admitted when backend matures; no release claim yet",
    },
    .{
        .triple = "x86_64-windows-msvc",
        .arch = .x86_64,
        .os = .windows,
        .compiler_builds = .planned,
        .compiler_runs = .planned,
        .compiler_self_host = .open,
        .object_emission = .open,
        .bootstrap_stage = "none",
        .cross_compile_from_host = .open,
        .notes = "Windows COFF/PE: target_model.WindowsStatus.planned",
    },
};

pub fn findRow(triple: []const u8) ?TargetRow {
    for (rows) |row| {
        if (std.mem.eql(u8, row.triple, triple)) return row;
    }
    return null;
}

pub fn hostTripleString(buf: *[64]u8) []const u8 {
    return target_model.hostTriple().formatTriple(buf);
}

/// Row whose arch+os matches the running host (best-effort; ABI may differ).
pub fn hostRow() ?TargetRow {
    const host = target_model.hostTriple();
    for (rows) |row| {
        if (row.arch == host.arch and row.os == host.os) return row;
    }
    return null;
}

pub const CiProof = struct {
    workflow: []const u8,
    runner: []const u8,
    host_triple: []const u8,
    build_steps: []const u8,
    proves: []const u8,
};

/// Shipped CI evidence for §17 (update when workflow changes).
pub const ci_proofs: []const CiProof = &.{
    .{
        .workflow = ".github/workflows/ci.yml",
        .runner = "ubuntu-latest",
        .host_triple = "x86_64-linux-gnu",
        .build_steps = "zig build; zig build pass-gates; zig build pass16-cross-platform; zig build pass16-m1-smoke",
        .proves = "compiler_builds,compiler_runs,pass16_gate,keyword_differential",
    },
    .{
        .workflow = ".github/workflows/ci.yml",
        .runner = "macos-latest",
        .host_triple = "aarch64-macos",
        .build_steps = "zig build pass16-cross-platform; zig build pass16-m1-smoke",
        .proves = "pass16_gate,keyword_differential,host_aware_target_matrix",
    },
};

pub fn writeMatrixJson(w: *std.Io.Writer) !void {
    var host_buf: [64]u8 = undefined;
    const host_str = hostTripleString(&host_buf);
    const stage = bootstrap_dag.currentStageReached().label();
    try w.print("{{\"schema\":\"{s}\",\"host_triple\":\"{s}\",\"bootstrap_stage\":\"{s}\",\"rows\":[", .{
        SCHEMA_VERSION,
        host_str,
        stage,
    });
    for (rows, 0..) |row, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"triple\":\"{s}\",\"compiler_builds\":\"{s}\",\"compiler_runs\":\"{s}\",\"compiler_self_host\":\"{s}\",\"object_emission\":\"{s}\",\"bootstrap_stage\":\"{s}\",\"cross_compile_from_host\":\"{s}\",\"notes\":\"{s}\"}}",
            .{
                row.triple,
                row.compiler_builds.name(),
                row.compiler_runs.name(),
                row.compiler_self_host.name(),
                row.object_emission.name(),
                row.bootstrap_stage,
                row.cross_compile_from_host.name(),
                row.notes,
            },
        );
    }
    try w.writeAll("],\"ci_proofs\":[");
    for (ci_proofs, 0..) |cp, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"workflow\":\"{s}\",\"runner\":\"{s}\",\"host_triple\":\"{s}\",\"build_steps\":\"{s}\",\"proves\":\"{s}\"}}",
            .{ cp.workflow, cp.runner, cp.host_triple, cp.build_steps, cp.proves },
        );
    }
    try w.writeAll("]}");
}

/// Gate invariants: matrix present, host triple matches builtin, keyword path is arch-neutral.
pub fn validateCrossPlatformGate() !void {
    if (rows.len < 6) return error.GateFailed;
    var host_buf: [64]u8 = undefined;
    const host_str = hostTripleString(&host_buf);
    const parsed = target_model.parseStructuredTarget(host_str, .exe) orelse return error.GateFailed;
    const builtin_host = target_model.hostTriple();
    if (parsed.triple.arch != builtin_host.arch) return error.GateFailed;
    if (parsed.triple.os != builtin_host.os) return error.GateFailed;
    // Every tracked row must declare bootstrap stage or explicit none.
    for (rows) |row| {
        if (row.bootstrap_stage.len == 0) return error.GateFailed;
    }
    // Primary proof target must remain in matrix.
    if (findRow("aarch64-macos") == null) return error.GateFailed;
    if (findRow("wasm32-wasi") == null) return error.GateFailed;
    if (ci_proofs.len < 2) return error.GateFailed;
}

test "selfhost_target_matrix: host triple parses" {
    var buf: [64]u8 = undefined;
    const host_str = hostTripleString(&buf);
    const parsed = target_model.parseStructuredTarget(host_str, .exe);
    try std.testing.expect(parsed != null);
}

test "selfhost_target_matrix: cross-platform gate" {
    try validateCrossPlatformGate();
}

test "selfhost_target_matrix: host row when known" {
    const host = target_model.hostTriple();
    if (host.arch == .aarch64 and host.os == .macos) {
        const row = hostRow().?;
        try std.testing.expectEqualStrings("aarch64-macos", row.triple);
    }
}
