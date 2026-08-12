//! Pass 34 L6 — representation manifest schema (build artifact from @comp.why / emission scans).
const std = @import("std");
const backend_identity = @import("backend_identity.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");

/// L6 manifest schema version (embedded in `.proof.json` as `manifest_schema` and standalone `.manifest.json`).
pub const SCHEMA_VERSION = "pass34-l6-manifest-v0";

pub const ContaminationClass = enum {
    clean,
    /// T3 — helper-dominated hot region hides specialization gaps.
    contaminated,

    pub fn name(self: ContaminationClass) []const u8 {
        return switch (self) {
            .clean => "clean",
            .contaminated => "contaminated",
        };
    }
};

/// Canonical L6 emission counters (subset surfaced in proof + manifest artifacts).
pub const EmissionCounts = struct {
    boxes: usize = 0,
    allocations: usize = 0,
    dynamic_dispatches: usize = 0,
    runtime_helpers: usize = 0,
    fallback_entries: usize = 0,
    /// Pass 34 L2 — fallback `.field` accesses emitted via `duo_fallback_get_*` markers.
    fallback_field_accesses: usize = 0,
    /// Pass 34 L2 — distinct interned field IDs among those fallback accesses.
    interned_field_ids: usize = 0,

    pub fn fromGeneratedC(source: []const u8) EmissionCounts {
        const base = native_barrier_checks.scanGeneratedC(source);
        const fallback = scanFallbackFieldIds(source);
        return .{
            .boxes = base.lua_value,
            .allocations = base.malloc,
            .dynamic_dispatches = base.lua_invoke + base.lua_table_new,
            .runtime_helpers = base.gc_refs + base.lua_invoke,
            .fallback_entries = countOccurrences(source, "fallback_") + countOccurrences(source, "lua_getfield"),
            .fallback_field_accesses = fallback.accesses,
            .interned_field_ids = fallback.distinct_ids,
        };
    }

    pub fn isZeroDynamic(self: EmissionCounts) bool {
        return self.dynamic_dispatches == 0 and self.boxes == 0;
    }
};

pub const FallbackFieldScan = struct {
    accesses: usize = 0,
    distinct_ids: usize = 0,
};

/// First-class evidence of compilation cost (AGY Workstream 2).
/// Supports optimization-priority projection by comparing expected
/// runtime benefit against measured compile-time cost.
pub const CompilerCost = struct {
    parse_sema_ms: u64 = 0,
    codegen_ms: u64 = 0,
    link_ms: u64 = 0,
    total_ms: u64 = 0,
};

/// Count fallback `.field` accesses (duo_fallback_get_* markers) and distinct interned
/// field IDs (the leading integer literal argument of each marker).
pub fn scanFallbackFieldIds(source: []const u8) FallbackFieldScan {
    var result = FallbackFieldScan{};
    var seen: std.StringArrayHashMapUnmanaged(void) = .{};
    defer seen.deinit(std.heap.page_allocator);

    var start: usize = 0;
    while (std.mem.indexOfPos(u8, source, start, "duo_fallback_get_")) |marker| {
        result.accesses += 1;
        const after = marker + "duo_fallback_get_".len;
        const after_paren = std.mem.indexOfPos(u8, source, after, "(") orelse break;
        const id_start = after_paren + 1;
        var id_end = id_start;
        while (id_end < source.len and source[id_end] >= '0' and source[id_end] <= '9') id_end += 1;
        if (id_end > id_start) {
            const id = source[id_start..id_end];
            if (!seen.contains(id)) {
                seen.put(std.heap.page_allocator, id, {}) catch {};
                result.distinct_ids += 1;
            }
        }
        start = id_end;
    }
    return result;
}

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

/// T3 trap classifier — nonzero helpers in a hot region with no dynamic dispatch still contaminates.
pub fn classifyContamination(counts: EmissionCounts, hot_region_helpers: usize) ContaminationClass {
    if (hot_region_helpers > 0 and counts.runtime_helpers > 0) return .contaminated;
    if (counts.runtime_helpers > 0 and counts.dynamic_dispatches == 0 and counts.boxes == 0) return .contaminated;
    return .clean;
}

pub fn writeManifestJson(
    w: *std.Io.Writer,
    manifest: backend_identity.Manifest,
    counts: EmissionCounts,
    contamination: ContaminationClass,
    cost: ?CompilerCost,
) !void {
    try w.print("{{\"schema\":\"{s}\",\"manifest\":", .{SCHEMA_VERSION});
    try backend_identity.writeManifestJson(manifest, w);
    try w.print(",\"emission\":{{\"boxes\":{d},\"allocations\":{d},\"dynamic_dispatches\":{d},\"runtime_helpers\":{d},\"fallback_entries\":{d},\"fallback_field_accesses\":{d},\"interned_field_ids\":{d}}}", .{
        counts.boxes,
        counts.allocations,
        counts.dynamic_dispatches,
        counts.runtime_helpers,
        counts.fallback_entries,
        counts.fallback_field_accesses,
        counts.interned_field_ids,
    });
    try w.print(",\"contamination\":\"{s}\"", .{contamination.name()});
    if (cost) |c| {
        try w.print(",\"compiler_cost\":{{\"parse_sema_ms\":{d},\"codegen_ms\":{d},\"link_ms\":{d},\"total_ms\":{d}}}", .{
            c.parse_sema_ms, c.codegen_ms, c.link_ms, c.total_ms,
        });
    }
    try w.print("}}", .{});
}

pub fn writeManifestFile(
    io: std.Io,
    path: []const u8,
    manifest: backend_identity.Manifest,
    counts: EmissionCounts,
    contamination: ContaminationClass,
    cost: ?CompilerCost,
    alloc: std.mem.Allocator,
) !void {
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    try writeManifestJson(&buf.writer, manifest, counts, contamination, cost);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = buf.written() });
}

test "pass34_representation_manifest: zero dynamic direct subset" {
    const src =
        \\void read_u8_at(uint8_t *p) { *p = 1; }
        \\int64_t decode_leb128_bounded(const uint8_t *b) { return b[0]; }
    ;
    const counts = EmissionCounts.fromGeneratedC(src);
    try std.testing.expect(counts.isZeroDynamic());
    try std.testing.expectEqual(ContaminationClass.clean, classifyContamination(counts, 0));
}

test "pass34_representation_manifest: T3 helper contamination" {
    const counts = EmissionCounts{
        .runtime_helpers = 3,
        .dynamic_dispatches = 0,
        .boxes = 0,
    };
    try std.testing.expectEqual(ContaminationClass.contaminated, classifyContamination(counts, 2));
}

test "pass34_representation_manifest: schema version" {
    try std.testing.expectEqualStrings("pass34-l6-manifest-v0", SCHEMA_VERSION);
}
