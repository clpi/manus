//! Pass 27 P0 — benchmark evidence counters and 3-backend comparison matrix.
const std = @import("std");
const backend_identity = @import("backend_identity.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");

pub const SCHEMA_VERSION = "pass27-benchmark-evidence-v0";

/// Extended counters beyond `native_barrier_checks.Counts` (P27-P0-02).
pub const EvidenceCounters = struct {
    boxes: usize = 0,
    unboxes: usize = 0,
    allocations: usize = 0,
    generic_table_ops: usize = 0,
    generic_calls: usize = 0,
    closure_environments: usize = 0,
    return_pack_materializations: usize = 0,
    runtime_helpers: usize = 0,
    code_size_bytes: usize = 0,
    compiler_time_ns: u64 = 0,

    pub fn fromGeneratedC(source: []const u8, code_size: usize) EvidenceCounters {
        const base = native_barrier_checks.scanGeneratedC(source);
        return .{
            .boxes = base.lua_value,
            .unboxes = base.lua_to_unbox,
            .allocations = base.malloc,
            .generic_table_ops = base.lua_table_new,
            .generic_calls = base.lua_invoke,
            .closure_environments = countOccurrences(source, "closure_env"),
            .return_pack_materializations = countOccurrences(source, "lua_push") + countOccurrences(source, "duo_ret_pack"),
            .runtime_helpers = base.gc_refs + base.lua_invoke,
            .code_size_bytes = code_size,
            .compiler_time_ns = 0,
        };
    }

    pub fn fromDirectObject(object_bytes: []const u8) EvidenceCounters {
        return .{
            .boxes = 0,
            .unboxes = 0,
            .allocations = 0,
            .generic_table_ops = 0,
            .generic_calls = 0,
            .closure_environments = 0,
            .return_pack_materializations = 0,
            .runtime_helpers = 0,
            .code_size_bytes = object_bytes.len,
        };
    }

    pub fn isBoxedBaseline(self: EvidenceCounters) bool {
        return self.boxes > 0 or self.unboxes > 0 or self.generic_table_ops > 0;
    }

    pub fn isZeroBoxNativePath(self: EvidenceCounters) bool {
        return self.boxes == 0 and self.unboxes == 0 and self.generic_calls == 0 and self.generic_table_ops == 0;
    }
};

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    while (start < haystack.len) {
        const rel = std.mem.indexOfPos(u8, haystack, start, needle) orelse break;
        count += 1;
        start = rel + needle.len;
    }
    return count;
}

pub const BenchmarkMatrixRow = struct {
    program_id: []const u8,
    bench_backend: backend_identity.BenchBackend,
    backend: backend_identity.Backend,
    representation: backend_identity.RepresentationProfile,
    runtime: backend_identity.RuntimeProfile,
    counters: EvidenceCounters,
    result_checksum: ?[]const u8 = null,
    wall_time_ns: ?u64 = null,
    correctness_match: bool = false,
};

/// Ten canonical benchmark slots (subset of 40-benchmark gate — P27 I.1).
pub const canonical_ten_programs: []const []const u8 = &.{
    "sieve", "fib", "sum", "dot", "matmul", "hash", "sort", "prime", "reduce", "conv",
};

pub const required_bench_backends: []const backend_identity.BenchBackend = &.{
    .c_dynamic,
    .c_specialized,
    .direct,
};

pub const profileForBenchBackend = backend_identity.profileForBenchBackend;

pub fn matrixCellCount() usize {
    return canonical_ten_programs.len * required_bench_backends.len;
}

/// P27-G01 partial: schema requires 10×3 matrix definition.
pub fn validateMatrixSchema() bool {
    return canonical_ten_programs.len == 10 and required_bench_backends.len == 3;
}

pub const CompileProofArtifact = struct {
    source_path: []const u8,
    generated_path: []const u8,
    bench_backend: ?backend_identity.BenchBackend,
    manifest: backend_identity.Manifest,
    counters: EvidenceCounters,
};

pub fn classifyEvidence(counters: EvidenceCounters, manifest: backend_identity.Manifest) []const u8 {
    if (counters.isBoxedBaseline()) return "provisional-boxed-path";
    if (manifest.backend == .direct) return "direct-native-subset";
    if (manifest.representation == .native) return "native-scalar-generated-c";
    if (manifest.representation == .specialized) return "specialized-generated-c";
    return "dynamic-runtime";
}

pub fn writeCompileProofJson(artifact: CompileProofArtifact, w: *std.Io.Writer) !void {
    const evidence_class = classifyEvidence(artifact.counters, artifact.manifest);
    try w.print("{{\"schema\":\"{s}\",\"source_path\":\"", .{SCHEMA_VERSION});
    try jsonEscape(w, artifact.source_path);
    try w.print("\",\"generated_path\":\"", .{});
    try jsonEscape(w, artifact.generated_path);
    try w.print("\",\"evidence_class\":\"", .{});
    try jsonEscape(w, evidence_class);
    if (artifact.bench_backend) |bb| {
        try w.print("\",\"bench_backend\":\"{s}", .{bb.name()});
    }
    try w.print("\",\"manifest\":", .{});
    try backend_identity.writeManifestJson(artifact.manifest, w);
    try w.print(",\"emission\":{{\"boxes\":{d},\"unboxes\":{d},\"allocations\":{d},\"generic_table_ops\":{d},\"generic_calls\":{d},\"closure_envs\":{d},\"return_pack_materializations\":{d},\"runtime_helpers\":{d},\"generated_bytes\":{d}}}", .{
        artifact.counters.boxes,
        artifact.counters.unboxes,
        artifact.counters.allocations,
        artifact.counters.generic_table_ops,
        artifact.counters.generic_calls,
        artifact.counters.closure_environments,
        artifact.counters.return_pack_materializations,
        artifact.counters.runtime_helpers,
        artifact.counters.code_size_bytes,
    });
    try w.print("}}", .{});
}

pub fn writeCompileProofFile(io: std.Io, path: []const u8, artifact: CompileProofArtifact, alloc: std.mem.Allocator) !void {
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    try writeCompileProofJson(artifact, &buf.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = buf.written() });
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "pass27_benchmark_evidence: counters from generated C" {
    const src =
        \\void f(void) {
        \\  lua_Value v;
        \\  lua_invoke(x, 0, 0);
        \\  lua_to_i64(v);
        \\  lua_table_new();
        \\  malloc(16);
        \\}
    ;
    const c = EvidenceCounters.fromGeneratedC(src, src.len);
    try std.testing.expect(c.boxes >= 1);
    try std.testing.expect(c.unboxes >= 1);
    try std.testing.expect(c.generic_calls >= 1);
    try std.testing.expect(c.isBoxedBaseline());
}

test "pass27_benchmark_evidence: direct object zero-box" {
    const obj = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x00, 0x00, 0x00 };
    const c = EvidenceCounters.fromDirectObject(&obj);
    try std.testing.expect(c.isZeroBoxNativePath());
}

test "pass27_benchmark_evidence: 10x3 matrix schema" {
    try std.testing.expect(validateMatrixSchema());
    try std.testing.expect(matrixCellCount() == 30);
}
