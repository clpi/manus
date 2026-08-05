//! Pass 14 §13 (shrink-first), §18 Audit 8/12, §22 Deliverable H — repository
//! compression + ergonomics metrics. This is the LIVE "before" baseline that
//! Milestone 9 (shrink proof) requires: M9's exit gate demands before-and-after
//! semantic-compression evidence, which is impossible without measurement.
//!
//! Rather than seed another classification, this module MEASURES the real
//! repository (read-only `wc`/`find` via host_run, the same pattern
//! dev_control_plane uses for git). It quantifies the §8 compression targets:
//! the codegen.zig monster, pass-shaped naming sprawl (§16.3), source volume.
const std = @import("std");
const host_run = @import("host_run.zig");

pub const SCHEMA_VERSION = "repo-metrics-v0";

pub const FileMetric = struct {
    name: []const u8,
    lines: u64,
};

pub const Metrics = struct {
    src_zig_files: usize,
    src_total_lines: u64,
    src_largest_file: []const u8,
    src_largest_lines: u64,
    /// passN_*.zig count — the §16.3 (no pass-shaped permanent names) signal.
    pass_shaped_files: usize,
    docs_md_files: usize,
    examples_duo_files: usize,
    largest_files: []const FileMetric, // top-N by lines, owned

    pub fn free(self: *Metrics, alloc: std.mem.Allocator) void {
        alloc.free(self.src_largest_file);
        for (self.largest_files) |f| alloc.free(f.name);
        alloc.free(self.largest_files);
    }
};

/// §16.3 — a production name is pass-shaped if it matches `pass<digit>...`.
pub fn isPassShaped(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "pass")) return false;
    var i: usize = 4;
    if (i >= name.len) return false;
    while (i < name.len and (name[i] >= '0' and name[i] <= '9')) : (i += 1) {}
    // must have consumed at least one digit and be followed by '_' or end
    return i > 4 and (i == name.len or name[i] == '_');
}

/// Parse `wc -l` output of the form "<lines> <name>" per line (possibly a
/// trailing "total" line). Returns owned slice of FileMetric (names duped).
pub fn parseWcLines(alloc: std.mem.Allocator, out: []const u8) ![]FileMetric {
    var list = std.ArrayList(FileMetric).empty;
    errdefer {
        for (list.items) |f| alloc.free(f.name);
        list.deinit(alloc);
    }
    var it = std.mem.splitScalar(u8, out, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        // skip a "total" line
        if (std.mem.endsWith(u8, line, "total") or std.mem.eql(u8, std.mem.trim(u8, line, " "), "total")) continue;
        // "<digits> <path>"
        const sp = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const nstr = std.mem.trim(u8, line[0..sp], " \t");
        const path = std.mem.trim(u8, line[sp + 1 ..], " \t");
        const n = std.fmt.parseInt(u64, nstr, 10) catch continue;
        // basename
        const base = std.fs.path.basename(path);
        try list.append(alloc, .{ .name = try alloc.dupe(u8, base), .lines = n });
    }
    return try list.toOwnedSlice(alloc);
}

fn sortDesc(_: void, a: FileMetric, b: FileMetric) bool {
    return a.lines > b.lines;
}

fn runText(alloc: std.mem.Allocator, command: []const u8) ?[]const u8 {
    // Shell variant so globs (src/*.zig) expand. Read-only commands only.
    const out = host_run.runHostCommand(alloc, command) orelse return null;
    defer alloc.free(out.stderr);
    if (!out.ok) {
        alloc.free(out.stdout);
        return null;
    }
    return out.stdout;
}

/// Measure the repository. Root is the repo root (cwd). Read-only. Caller frees.
pub fn measureRepository(alloc: std.mem.Allocator) !Metrics {
    // wc -l src/*.zig  -> per-file lines (+ total line)
    var src_largest_file: []const u8 = try alloc.dupe(u8, "");
    errdefer alloc.free(src_largest_file);
    var src_largest_lines: u64 = 0;
    var src_total_lines: u64 = 0;
    var pass_shaped: usize = 0;
    var largest_list = std.ArrayList(FileMetric).empty;
    errdefer {
        for (largest_list.items) |f| alloc.free(f.name);
        largest_list.deinit(alloc);
    }
    var src_files: usize = 0;

    if (runText(alloc, "wc -l src/*.zig")) |wc| {
        defer alloc.free(wc);
        const parsed = try parseWcLines(alloc, wc);
        defer {
            for (parsed) |f| alloc.free(f.name);
            alloc.free(parsed);
        }
        for (parsed) |f| {
            src_files += 1;
            src_total_lines += f.lines;
            if (isPassShaped(f.name)) pass_shaped += 1;
            if (f.lines > src_largest_lines) {
                src_largest_lines = f.lines;
                alloc.free(src_largest_file);
                src_largest_file = try alloc.dupe(u8, f.name);
            }
        }
        // top-5 largest (duped independently of parsed)
        var sorted = try alloc.dupe(FileMetric, parsed);
        defer alloc.free(sorted);
        std.mem.sort(FileMetric, sorted, {}, sortDesc);
        const top = @min(sorted.len, 5);
        for (sorted[0..top]) |f| {
            try largest_list.append(alloc, .{ .name = try alloc.dupe(u8, f.name), .lines = f.lines });
        }
    }
    const largest_owned = try largest_list.toOwnedSlice(alloc);

    var docs_md: usize = 0;
    if (runText(alloc, "find docs -name '*.md' -type f")) |d| {
        defer alloc.free(d);
        var it = std.mem.splitScalar(u8, d, '\n');
        while (it.next()) |line| if (line.len > 0) {
            docs_md += 1;
        };
    }
    var examples_duo: usize = 0;
    if (runText(alloc, "find examples -name '*.duo' -type f")) |e| {
        defer alloc.free(e);
        var it = std.mem.splitScalar(u8, e, '\n');
        while (it.next()) |line| if (line.len > 0) {
            examples_duo += 1;
        };
    }

    return .{
        .src_zig_files = src_files,
        .src_total_lines = src_total_lines,
        .src_largest_file = src_largest_file,
        .src_largest_lines = src_largest_lines,
        .pass_shaped_files = pass_shaped,
        .docs_md_files = docs_md,
        .examples_duo_files = examples_duo,
        .largest_files = largest_owned,
    };
}

pub fn writeMetricsJson(w: *std.Io.Writer, alloc: std.mem.Allocator) !void {
    var m = try measureRepository(alloc);
    defer m.free(alloc);
    try w.print("{{\"schema\":\"{s}\",\"src_zig_files\":{d},\"src_total_lines\":{d},\"src_largest_file\":\"{s}\",\"src_largest_lines\":{d},\"pass_shaped_files\":{d},\"docs_md_files\":{d},\"examples_duo_files\":{d},\"largest_files\":[", .{ SCHEMA_VERSION, m.src_zig_files, m.src_total_lines, m.src_largest_file, m.src_largest_lines, m.pass_shaped_files, m.docs_md_files, m.examples_duo_files });
    for (m.largest_files, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"name\":\"{s}\",\"lines\":{d}}}", .{ f.name, f.lines });
    }
    try w.print("],\"compression_targets\":{{\"codegen_split\":\"src_largest_file is the §6/§8 split candidate\",\"pass_shaped_naming\":\"{d} passN_*.zig files violate §16.3 enduring-name rule (current convention)\"}}}}", .{m.pass_shaped_files});
}

test "repo_metrics: isPassShaped (§16.3 signal)" {
    try std.testing.expect(isPassShaped("pass14_catalog.zig"));
    try std.testing.expect(isPassShaped("pass1_catalog.zig"));
    try std.testing.expect(isPassShaped("pass11_ward_barrier_tests.zig"));
    try std.testing.expect(!isPassShaped("codegen.zig"));
    try std.testing.expect(!isPassShaped("parser.zig"));
    try std.testing.expect(!isPassShaped("passes_audit.zig")); // plural, no digit
    try std.testing.expect(!isPassShaped("passive.zig")); // no digit after 'pass'
}

test "repo_metrics: parseWcLines handles per-file + total" {
    const alloc = std.testing.allocator;
    const sample =
        \\   42 src/lexer.zig
        \\  100 src/codegen.zig
        \\    7 src/tiny.zig
        \\  149 total
        \\
    ;
    const got = try parseWcLines(alloc, sample);
    defer {
        for (got) |f| alloc.free(f.name);
        alloc.free(got);
    }
    try std.testing.expectEqual(@as(usize, 3), got.len);
    try std.testing.expectEqualStrings("lexer.zig", got[0].name); // input order preserved
    try std.testing.expectEqual(@as(u64, 42), got[0].lines);
    try std.testing.expectEqualStrings("codegen.zig", got[1].name);
    try std.testing.expectEqual(@as(u64, 100), got[1].lines);
}

test "repo_metrics: measureRepository reads real repo and frees cleanly" {
    const alloc = std.testing.allocator;
    var m = try measureRepository(alloc);
    defer m.free(alloc);
    // This repository always has many src/*.zig files.
    try std.testing.expect(m.src_zig_files >= 20);
    try std.testing.expect(m.src_total_lines > 0);
    try std.testing.expect(m.src_largest_lines > 0);
    // codegen.zig is the known monster.
    try std.testing.expect(std.mem.indexOf(u8, m.src_largest_file, "codegen") != null or m.src_largest_lines > 1000);
    // Pass-shaped files exist (the catalog convention).
    try std.testing.expect(m.pass_shaped_files >= 5);
}

test "repo_metrics: JSON parses" {
    const alloc = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeMetricsJson(&aw.writer, alloc);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("compression_targets").? == .object);
    try std.testing.expect(parsed.value.object.get("largest_files").? == .array);
}
