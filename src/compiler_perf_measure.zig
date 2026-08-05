//! Pass 16 MP-11 / §22.5 — native compiler perf measurement harness (Io.Timestamp, cross-platform).
const std = @import("std");
const token_semantic = @import("token_semantic.zig");
const lexer_differential = @import("lexer_differential.zig");
const builtin = @import("builtin");

pub const SCHEMA_VERSION = "compiler-perf-measure-v0";

pub const Sample = struct {
    id: []const u8,
    scenario: []const u8,
    status: []const u8,
    value_ns: ?u64,
    iterations: u64,
    notes: []const u8,
};

const keyword_negatives = [_][]const u8{ "foo", "bar", "identifier", "notkw", "Function", "asyncio", "matchx" };

fn measureWithIo(io: std.Io) u64 {
    const start = std.Io.Timestamp.now(io, .awake);
    const outer: u32 = 100_000;
    var ops: u64 = 0;
    var i: u32 = 0;
    while (i < outer) : (i += 1) {
        for (token_semantic.keywords) |kw| {
            _ = token_semantic.lookupKeyword(kw.text);
            ops += 1;
        }
        for (keyword_negatives) |neg| {
            _ = token_semantic.lookupKeyword(neg);
            ops += 1;
        }
    }
    const end = std.Io.Timestamp.now(io, .awake);
    const elapsed: u64 = @intCast(start.durationTo(end).nanoseconds);
    if (ops == 0 or elapsed == 0) return 0;
    return elapsed / ops;
}

pub fn measureKeywordLookupPerOpNs() u64 {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    return measureWithIo(threaded.io());
}

pub fn collectSamples() [3]Sample {
    const keyword_ns = measureKeywordLookupPerOpNs();
    const lex_kpt = lexer_differential.measureLexThroughput();
    return .{
        .{
            .id = "CP-04",
            .scenario = "keyword classify lookup (production duo_classify)",
            .status = if (keyword_ns > 0) "measured" else "failed",
            .value_ns = if (keyword_ns > 0) keyword_ns else null,
            .iterations = 100_000 * (@as(u64, token_semantic.keywords.len) + keyword_negatives.len),
            .notes = "token_semantic.lookupKeyword → duo_keyword_classify.c",
        },
        .{
            .id = "CP-07",
            .scenario = "production lexer token throughput",
            .status = if (lex_kpt > 0) "measured" else "failed",
            .value_ns = if (lex_kpt > 0) lex_kpt else null,
            .iterations = 10_000,
            .notes = "Lexer.init sample function; value = tokens*1000/ns (kilo-tokens per ms scale)",
        },
        .{
            .id = "CP-06",
            .scenario = "pass16_m1_lexer_proof compile",
            .status = "spot_check",
            .value_ns = null,
            .iterations = 0,
            .notes = "Run via `duo run examples/pass16_m1_lexer_proof.duo`; wall clock environment-dependent",
        },
    };
}

pub fn writeMeasureJson(w: *std.Io.Writer) !void {
    const arch = @tagName(builtin.cpu.arch);
    const os_tag = @tagName(builtin.os.tag);
    const samples = collectSamples();
    try w.print("{{\"schema\":\"{s}\",\"host_arch\":\"{s}\",\"host_os\":\"{s}\",\"samples\":[", .{
        SCHEMA_VERSION, arch, os_tag,
    });
    for (samples, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"scenario\":\"{s}\",\"status\":\"{s}\",\"value_ns\":",
            .{ s.id, s.scenario, s.status },
        );
        if (s.value_ns) |v| try w.print("{d}", .{v}) else try w.writeAll("null");
        try w.print(",\"iterations\":{d},\"notes\":\"{s}\"}}", .{ s.iterations, s.notes });
    }
    try w.writeAll("]}");
}

pub fn validateMeasureGate() !void {
    const ns = measureKeywordLookupPerOpNs();
    if (ns == 0) return error.GateFailed;
    if (ns > 10_000) return error.GateFailed;
    const lex = lexer_differential.measureLexThroughput();
    if (lex == 0) return error.GateFailed;
}

test "compiler_perf_measure: lexer throughput measured" {
    const kpt = lexer_differential.measureLexThroughput();
    try std.testing.expect(kpt > 0);
}

test "compiler_perf_measure: keyword lookup measured" {
    const ns = measureKeywordLookupPerOpNs();
    try std.testing.expect(ns > 0);
    try std.testing.expect(ns < 10_000);
}
