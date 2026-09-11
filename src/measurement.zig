//! Benchmark evidence counters and compile-proof projection.
const std = @import("std");
const backend_identity = @import("backend/identity.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");
const representation_manifest = @import("representation_manifest.zig");

pub const SCHEMA_VERSION = "idol.compile.evidence.v1";

/// Representation manifest as a build artifact. The compile-proof artifact is the
/// unified diffable manifest: identity, emission counters, and transformation provenance.
pub const MANIFEST_SCHEMA_VERSION = "idol.realization.manifest.v1";

/// One transformation-provenance entry in the manifest.
pub const ManifestProvenance = struct {
    transform: []const u8,
    site: []const u8,
    inputs_hash: u64,
    output_hash: u64,
};

/// Physical emission counters beyond `native_barrier_checks.Counts`.
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
    /// Fallback `.field` accesses (current bridge marker spelling) and distinct
    /// interned field ids surfaced in the manifest emission section.
    fallback_field_accesses: usize = 0,
    interned_field_ids: usize = 0,
    fallback_entries: usize = 0,

    pub fn fromGeneratedC(source: []const u8, code_size: usize) EvidenceCounters {
        const base = native_barrier_checks.scanGeneratedC(source);
        const fallback = representation_manifest.scanFallbackFieldIds(source);
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
            .fallback_field_accesses = fallback.accesses,
            .interned_field_ids = fallback.distinct_ids,
            .fallback_entries = countOccurrences(source, "do_fallback("),
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

pub const CompileProofArtifact = struct {
    source_path: []const u8,
    generated_path: []const u8,
    bench_backend: ?backend_identity.BenchBackend,
    manifest: backend_identity.Manifest,
    counters: EvidenceCounters,
};

pub fn classifyEvidence(counters: EvidenceCounters, manifest: backend_identity.Manifest) []const u8 {
    if (manifest.backend == .direct) return "direct-native-subset";
    if (counters.isBoxedBaseline()) {
        if (manifest.representation == .specialized) return "specialized-provisional-boxed";
        if (manifest.representation == .generic) return "provisional-boxed-path";
        return "provisional-boxed-path";
    }
    if (manifest.representation == .native) return "native-scalar-generated-c";
    if (manifest.representation == .specialized) return "specialized-generated-c";
    return "dynamic-runtime";
}

pub fn writeCompileProofJson(artifact: CompileProofArtifact, provenance: []const ManifestProvenance, w: *std.Io.Writer) !void {
    const evidence_class = classifyEvidence(artifact.counters, artifact.manifest);
    try w.print("{{\"schema\":\"{s}\",\"manifest_schema\":\"{s}\",\"source_path\":\"", .{ SCHEMA_VERSION, MANIFEST_SCHEMA_VERSION });
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
    const emission_counts = representation_manifest.EmissionCounts{
        .boxes = artifact.counters.boxes,
        .allocations = artifact.counters.allocations,
        .dynamic_dispatches = artifact.counters.generic_calls + artifact.counters.generic_table_ops,
        .runtime_helpers = artifact.counters.runtime_helpers,
        .fallback_entries = artifact.counters.fallback_entries,
        .fallback_field_accesses = artifact.counters.fallback_field_accesses,
        .interned_field_ids = 0,
    };
    const contamination = representation_manifest.classifyContamination(emission_counts, 0);
    try w.print(",\"emission\":{{\"boxes\":{d},\"unboxes\":{d},\"allocations\":{d},\"generic_table_ops\":{d},\"generic_calls\":{d},\"dynamic_dispatches\":{d},\"fallback_entries\":{d},\"fallback_field_accesses\":{d},\"interned_field_ids\":{d},\"closure_envs\":{d},\"return_pack_materializations\":{d},\"runtime_helpers\":{d},\"generated_bytes\":{d},\"contamination\":\"{s}\"}}", .{
        artifact.counters.boxes,
        artifact.counters.unboxes,
        artifact.counters.allocations,
        artifact.counters.generic_table_ops,
        artifact.counters.generic_calls,
        emission_counts.dynamic_dispatches,
        emission_counts.fallback_entries,
        emission_counts.fallback_field_accesses,
        emission_counts.interned_field_ids,
        artifact.counters.closure_environments,
        artifact.counters.return_pack_materializations,
        artifact.counters.runtime_helpers,
        artifact.counters.code_size_bytes,
        contamination.name(),
    });
    try w.print(",\"transform_provenance\":[", .{});
    for (provenance, 0..) |p, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"transform\":\"", .{});
        try jsonEscape(w, p.transform);
        try w.print("\",\"site\":\"", .{});
        try jsonEscape(w, p.site);
        try w.print("\",\"inputs\":{d},\"outputs\":{d}}}", .{ p.inputs_hash, p.output_hash });
    }
    try w.print("]}}", .{});
}

pub fn writeCompileProofFile(io: std.Io, path: []const u8, artifact: CompileProofArtifact, provenance: []const ManifestProvenance, alloc: std.mem.Allocator) !void {
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    try writeCompileProofJson(artifact, provenance, &buf.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = buf.written() });
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "benchmark evidence classifies boxed specialized vs generic" {
    const counters = EvidenceCounters.fromGeneratedC("lua_Value v;", 12);
    const spec = backend_identity.Manifest{
        .backend = .c,
        .representation = .specialized,
        .runtime = .dynamic,
        .target = "native",
        .intermediate = "generated-c",
        .boxing_mode = "specialized",
    };
    const generic = backend_identity.Manifest{
        .backend = .c,
        .representation = .generic,
        .runtime = .full,
        .target = "native",
        .intermediate = "generated-c",
        .boxing_mode = "boxed",
    };
    try std.testing.expectEqualStrings("specialized-provisional-boxed", classifyEvidence(counters, spec));
    try std.testing.expectEqualStrings("provisional-boxed-path", classifyEvidence(counters, generic));
}

test "benchmark evidence counts generated C" {
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

test "benchmark evidence recognizes a zero-box direct object" {
    const obj = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x00, 0x00, 0x00 };
    const c = EvidenceCounters.fromDirectObject(&obj);
    try std.testing.expect(c.isZeroBoxNativePath());
}

test "compile proof schemas use current semantic identities" {
    try std.testing.expectEqualStrings("idol.compile.evidence.v1", SCHEMA_VERSION);
    try std.testing.expectEqualStrings("idol.realization.manifest.v1", MANIFEST_SCHEMA_VERSION);
    try std.testing.expect(std.mem.indexOf(u8, SCHEMA_VERSION, "pass") == null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFEST_SCHEMA_VERSION, "pass") == null);
}
