//! Pass 13 P13-WS7 — impact-based validation planner (file/work-item → gates).
const std = @import("std");
const dev_control_plane = @import("dev_control_plane.zig");
const host_run = @import("host_run.zig");

pub const SCHEMA_VERSION = "dev-validation-plan-v0";

pub const ValidationGate = struct {
    id: []const u8,
    command: []const u8,
    reason: []const u8,
};

pub const GateRunResult = struct {
    id: []const u8,
    command: []const u8,
    passed: bool,
    executed: bool,
};

pub fn planForWorkItem(work_id: []const u8) []const ValidationGate {
    if (dev_control_plane.findWorkItem(work_id)) |wi| {
        _ = wi;
        if (std.mem.eql(u8, work_id, "P13-WS2") or std.mem.eql(u8, work_id, "P13-WS3") or std.mem.eql(u8, work_id, "P13-WS4"))
            return &base_dev_plane_gates;
        if (std.mem.eql(u8, work_id, "P13-WS10"))
            return &presentation_gates;
        if (std.mem.eql(u8, work_id, "P12-WS12") or std.mem.eql(u8, work_id, "P12-M2"))
            return &pass12_m2_gates;
        if (std.mem.startsWith(u8, work_id, "P12-WS"))
            return &pass12_workitem_gates;
        if (std.mem.eql(u8, work_id, "P13-WS7"))
            return &base_dev_plane_gates;
    }
    return &default_gates;
}

const default_gates = [_]ValidationGate{
    .{ .id = "build", .command = "zig build", .reason = "compiler builds after any change" },
    .{ .id = "agent-smoke", .command = "zig build agent-smoke", .reason = "tier-0 regression gate" },
};

const base_dev_plane_gates = [_]ValidationGate{
    .{ .id = "build", .command = "zig build", .reason = "compiler builds" },
    .{ .id = "dev-control-plane", .command = "zig test src/dev_control_plane.zig", .reason = "claim lease + persistence" },
    .{ .id = "catalog-json", .command = "duo catalog", .reason = "pass13 catalog export parses" },
};

const presentation_gates = [_]ValidationGate{
    .{ .id = "build", .command = "zig build", .reason = "compiler builds" },
    .{ .id = "presentation-record", .command = "zig test src/presentation_record.zig", .reason = "structured diagnostic records" },
};

const codegen_gates = [_]ValidationGate{
    .{ .id = "build", .command = "zig build", .reason = "compiler builds" },
    .{ .id = "unit-test", .command = "zig build unit-test --summary all", .reason = "codegen/runtime tests" },
    .{ .id = "fmt-check", .command = "zig fmt src --check", .reason = "Zig formatting" },
};

const perf_gates = [_]ValidationGate{
    .{ .id = "bench", .command = "zig build bench", .reason = "no benchmark regressions" },
};

const stdlib_gates = [_]ValidationGate{
    .{ .id = "agent-smoke", .command = "zig build agent-smoke", .reason = "stdlib + meta smokes" },
};

const pass12_gates = [_]ValidationGate{
    .{ .id = "m1-diff", .command = "duo run examples/pass12_m1_diff.duo", .reason = "M1 differential proof" },
    .{ .id = "token-semantic", .command = "zig test src/token_semantic.zig", .reason = "keyword semantic source" },
    .{ .id = "semantic-claims", .command = "duo semantic claims", .reason = "release claim drift (Pass 12 WS10)" },
};

const pass12_workitem_gates = [_]ValidationGate{
    .{ .id = "build", .command = "zig build", .reason = "compiler builds" },
    .{ .id = "m1-diff", .command = "duo run examples/pass12_m1_diff.duo", .reason = "P12-M1 differential proof" },
    .{ .id = "semantic-claims", .command = "duo semantic claims", .reason = "release truth registry" },
    .{ .id = "semantic-compare", .command = "duo semantic compare", .reason = "candidate comparison engine" },
};

const pass12_m2_gates = [_]ValidationGate{
    .{ .id = "decode-cursor", .command = "duo run examples/pass9/decode_cursor_smoke.duo", .reason = "P12-M2 Ward decode cursor path" },
    .{ .id = "decode-semantic", .command = "duo run examples/pass9/decode_semantic_smoke.duo", .reason = "P12-M2 semantic-id dispatch" },
    .{ .id = "barrier-ward-opcode", .command = "duo dev barrier check ward_opcode_lookup", .reason = "P12-M2 opcode lookup native dense tables" },
    .{ .id = "barrier-ward", .command = "duo dev barrier check ward_decode", .reason = "P12-M2 decode_instruction __lua wrapper (honest gap)" },
};

const pass11_gates = [_]ValidationGate{
    .{ .id = "pass11-gate", .command = "zig build pass11-gate", .reason = "Profile A closure checks" },
    .{ .id = "barrier-m1", .command = "duo dev barrier check pass12_m1", .reason = "WP-15 M1 native barrier proof" },
    .{ .id = "barrier-m1-sorted", .command = "duo dev barrier check pass12_m1_sorted", .reason = "WP-15 sorted lookup native dense tables" },
};

fn pathMatches(path: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, path, prefix);
}

var composite_plan: [24]ValidationGate = undefined;
var composite_plan_len: usize = 0;

pub fn planForFiles(files: []const []const u8) []const ValidationGate {
    var need_codegen = false;
    var need_perf = false;
    var need_stdlib = false;
    var need_pass12 = false;
    var need_pass12_m2 = false;
    var need_pass11 = false;
    var need_dev = false;

    for (files) |f| {
        if (pathMatches(f, "src/codegen.zig") or pathMatches(f, "src/sema.zig") or pathMatches(f, "src/native_backend.zig") or pathMatches(f, "src/parser.zig") or pathMatches(f, "src/lexer.zig")) {
            need_codegen = true;
            if (pathMatches(f, "src/codegen.zig") or pathMatches(f, "src/native_backend.zig")) need_perf = true;
            if (pathMatches(f, "src/native_backend.zig")) need_pass11 = true;
        }
        if (pathMatches(f, "src/proof_carrying.zig") or pathMatches(f, "src/semantic_cli.zig")) need_pass12 = true;
        if (pathMatches(f, "lib/std/")) need_stdlib = true;
        if (pathMatches(f, "src/token_semantic.zig") or pathMatches(f, "src/token_classify_gen.zig") or pathMatches(f, "lib/std/token/") or pathMatches(f, "examples/pass12"))
            need_pass12 = true;
        if (pathMatches(f, "lib/std/wasm/") or pathMatches(f, "examples/pass9/") or pathMatches(f, "src/wasm_semantic"))
            need_pass12_m2 = true;
        if (pathMatches(f, "src/pass11") or pathMatches(f, "scripts/pass11")) need_pass11 = true;
        if (pathMatches(f, "src/dev_control_plane.zig") or pathMatches(f, "src/pass13")) need_dev = true;
    }

    if (!need_codegen and !need_perf and !need_stdlib and !need_pass12 and !need_pass12_m2 and !need_pass11 and !need_dev)
        return &default_gates;

    // Static composite plan (dedupe by gate id) — CLI single-threaded.
    var static_plan: [24]ValidationGate = undefined;
    var n: usize = 0;

    const appendUnique = struct {
        fn f(gate: ValidationGate, out: *[24]ValidationGate, count: *usize) void {
            for (out[0..count.*]) |g| {
                if (std.mem.eql(u8, g.id, gate.id)) return;
            }
            if (count.* >= out.len) return;
            out[count.*] = gate;
            count.* += 1;
        }
    }.f;

    if (need_dev) for (base_dev_plane_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_codegen) for (codegen_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_perf) for (perf_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_stdlib) for (stdlib_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_pass12) for (pass12_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_pass12_m2) for (pass12_m2_gates) |g| appendUnique(g, &static_plan, &n);
    if (need_pass11) for (pass11_gates) |g| appendUnique(g, &static_plan, &n);
    for (default_gates) |g| appendUnique(g, &static_plan, &n);

    composite_plan_len = n;
    if (n > 0) @memcpy(composite_plan[0..n], static_plan[0..n]);
    return composite_plan[0..composite_plan_len];
}

pub fn writePlanJson(w: *std.Io.Writer, gates: []const ValidationGate) !void {
    try w.print("{{\"schema\":\"{s}\",\"gate_count\":{d},\"gates\":[", .{ SCHEMA_VERSION, gates.len });
    for (gates, 0..) |g, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"command\":\"{s}\",\"reason\":\"{s}\"}}", .{ g.id, g.command, g.reason });
    }
    try w.writeAll("]}");
}

var run_results: [24]GateRunResult = undefined;
var run_results_len: usize = 0;

pub fn runPlan(alloc: std.mem.Allocator, gates: []const ValidationGate, execute: bool) ![]const GateRunResult {
    run_results_len = 0;
    for (gates) |g| {
        if (run_results_len >= run_results.len) break;
        var passed = false;
        var executed = false;
        if (execute) {
            if (host_run.runHostCommand(alloc, g.command)) |out| {
                defer alloc.free(out.stdout);
                defer alloc.free(out.stderr);
                passed = out.ok;
                executed = true;
            }
        }
        run_results[run_results_len] = .{
            .id = g.id,
            .command = g.command,
            .passed = passed,
            .executed = executed,
        };
        run_results_len += 1;
    }
    return run_results[0..run_results_len];
}

pub fn writeRunJson(w: *std.Io.Writer, results: []const GateRunResult) !void {
    try w.print("{{\"schema\":\"{s}-run-v0\",\"results\":[", .{SCHEMA_VERSION});
    for (results, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"command\":\"{s}\",\"passed\":", .{ r.id, r.command });
        try w.print("{s}", .{if (r.passed) "true" else "false"});
        try w.print(",\"executed\":", .{});
        try w.print("{s}", .{if (r.executed) "true" else "false"});
        try w.writeAll("}");
    }
    var all_pass = true;
    var any_executed = false;
    for (results) |r| {
        if (r.executed and !r.passed) all_pass = false;
        if (r.executed) any_executed = true;
    }
    try w.print("],\"all_passed\":", .{});
    try w.print("{s}", .{if (all_pass and any_executed) "true" else "false"});
    try w.writeAll("}");
}

test "dev_validation_planner: codegen path selects unit-test" {
    const files = [_][]const u8{"src/codegen.zig"};
    const plan = planForFiles(&files);
    var found_ut = false;
    for (plan) |g| {
        if (std.mem.eql(u8, g.id, "unit-test")) found_ut = true;
    }
    try std.testing.expect(found_ut);
}

test "dev_validation_planner: native_backend selects pass11-gate" {
    const files = [_][]const u8{"src/native_backend.zig"};
    const plan = planForFiles(&files);
    var found = false;
    for (plan) |g| {
        if (std.mem.eql(u8, g.id, "pass11-gate")) found = true;
    }
    try std.testing.expect(found);
}

test "dev_validation_planner: P13-WS3 work item" {
    const plan = planForWorkItem("P13-WS3");
    try std.testing.expect(plan.len >= 2);
}
