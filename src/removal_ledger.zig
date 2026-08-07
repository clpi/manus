//! Pass 16 §22.9 — host code eligible for retirement after transfer and integration.
const std = @import("std");

pub const SCHEMA_VERSION = "removal-ledger-v0";

pub const Eligibility = enum {
    blocked,
    after_m1,
    after_m2,
    after_m3,
    after_bootstrap_closure,
    retain_oracle,

    pub fn name(self: Eligibility) []const u8 {
        return @tagName(self);
    }
};

pub const Entry = struct {
    id: []const u8,
    host_path: []const u8,
    subsystem_id: []const u8,
    duo_replacement: ?[]const u8,
    eligibility: Eligibility,
    removal_gate: []const u8,
};

pub const entries: []const Entry = &.{
    .{ .id = "RL-01", .host_path = "src/lexer.zig keyword switch (inline)", .subsystem_id = "SH-02", .duo_replacement = "lib/std/token/classify.duo", .eligibility = .after_m1, .removal_gate = "Differential parity + production dispatch" },
    .{ .id = "RL-02", .host_path = "src/lexer.zig (full)", .subsystem_id = "SH-03", .duo_replacement = "lib/std/compiler/lexer.duo", .eligibility = .after_m1, .removal_gate = "P16-M1 production integration" },
    .{ .id = "RL-03", .host_path = "src/token_semantic.zig", .subsystem_id = "SH-02", .duo_replacement = "lib/std/token/classify.duo + descriptor", .eligibility = .retain_oracle, .removal_gate = "Keep as differential oracle post-M1" },
    .{ .id = "RL-04", .host_path = "src/parser.zig", .subsystem_id = "SH-04", .duo_replacement = null, .eligibility = .after_m2, .removal_gate = "Duo-native parser kernel + syntax graph" },
    .{ .id = "RL-05", .host_path = "src/codegen.zig (canonical path)", .subsystem_id = "SH-10", .duo_replacement = null, .eligibility = .after_m3, .removal_gate = "Duo-native backend on one target" },
    .{ .id = "RL-06", .host_path = "build.zig orchestration", .subsystem_id = "SH-14", .duo_replacement = null, .eligibility = .after_bootstrap_closure, .removal_gate = "S2 is canonical compiler" },
    .{ .id = "RL-07", .host_path = "scripts/run_benchmark_proof.bash", .subsystem_id = "FC-D", .duo_replacement = "scripts/run_benchmark_proof.duo", .eligibility = .after_m1, .removal_gate = "zig build bench-proof-gate via duo run only" },
    .{ .id = "RL-08", .host_path = "scripts/duo_idiom_gate.bash", .subsystem_id = "FC-D", .duo_replacement = "scripts/duo_idiom_gate.duo", .eligibility = .after_m1, .removal_gate = "zig build duo-idiom-gate via duo run only" },
    .{ .id = "RL-09", .host_path = "scripts/verify_build.sh", .subsystem_id = "FC-D", .duo_replacement = "scripts/verify_build.duo", .eligibility = .after_m1, .removal_gate = "verify_build.duo runs zig build + test without shell logic" },
    .{ .id = "RL-10", .host_path = "scripts/run_benchmark_proof_impl.sh", .subsystem_id = "FC-D", .duo_replacement = "scripts/run_benchmark_proof.duo", .eligibility = .after_m1, .removal_gate = "Delete when bench-proof-gate uses duo run exclusively" },
    .{ .id = "RL-11", .host_path = "scripts/agent_smoke.sh", .subsystem_id = "FC-D", .duo_replacement = "scripts/agent_smoke.duo", .eligibility = .after_m1, .removal_gate = "agent-smoke tier-0 via duo run only" },
    .{ .id = "RL-12", .host_path = "scripts/repo_hygiene.sh", .subsystem_id = "FC-D", .duo_replacement = null, .eligibility = .after_m1, .removal_gate = "repo_hygiene.duo + zig build repo-hygiene" },
    .{ .id = "RL-13", .host_path = "scripts/duo_lock.sh", .subsystem_id = "FC-D", .duo_replacement = "scripts/duo_lock.duo", .eligibility = .after_m1, .removal_gate = "build mutex via std.script build_lock_* only" },
    .{ .id = "RL-14", .host_path = "scripts/run_benchmark.sh", .subsystem_id = "FC-D", .duo_replacement = "scripts/run_benchmark.duo", .eligibility = .after_m1, .removal_gate = "bench suite via duo run; bash fallback deleted" },
};

pub fn writeLedgerJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"entries\":[", .{SCHEMA_VERSION});
    for (entries, 0..) |e, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"host_path\":\"{s}\",\"subsystem_id\":\"{s}\",\"duo_replacement\":",
            .{ e.id, e.host_path, e.subsystem_id },
        );
        if (e.duo_replacement) |d| {
            try w.print("\"{s}\"", .{d});
        } else {
            try w.writeAll("null");
        }
        try w.print(
            ",\"eligibility\":\"{s}\",\"removal_gate\":\"{s}\"}}",
            .{ e.eligibility.name(), e.removal_gate },
        );
    }
    try w.writeAll("]}");
}

test "removal_ledger: entries present" {
    try std.testing.expect(entries.len >= 4);
}
