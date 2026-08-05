//! Pass 11 §3.4 — executable native-barrier assertions on compiler artifacts.
//!
//! Test harness inspects generated C or object bytes; source-level intent is not trusted.
const std = @import("std");
const host_run = @import("host_run.zig");

pub const SCHEMA_VERSION = "native-barrier-checks-v0";

/// Harness directive set (may become user `@assert.*` when surfaced in language).
pub const Assert = enum {
    backend_direct,
    no_boxing,
    no_alloc,
    no_gc,
    no_generic_table,
    no_dynamic_dispatch,
    no_generated_c,
    no_external_compiler,

    pub fn name(self: Assert) []const u8 {
        return switch (self) {
            .backend_direct => "backend(direct)",
            .no_boxing => "no_boxing",
            .no_alloc => "no_alloc",
            .no_gc => "no_gc",
            .no_generic_table => "no_generic_table",
            .no_dynamic_dispatch => "no_dynamic_dispatch",
            .no_generated_c => "no_generated_c",
            .no_external_compiler => "no_external_compiler",
        };
    }
};

pub const ArtifactKind = enum {
    generated_c,
    mach_o_object,
    mach_o_executable,
    wasm_module,
};

pub const Counts = struct {
    lua_value: usize = 0,
    lua_invoke: usize = 0,
    lua_table_new: usize = 0,
    lua_to_unbox: usize = 0,
    malloc: usize = 0,
    gc_refs: usize = 0,
};

pub const Violation = struct {
    assert: Assert,
    detail: []const u8,
};

pub const Report = struct {
    kind: ArtifactKind,
    counts: Counts,
    violations: []Violation,

    pub fn passed(self: Report) bool {
        return self.violations.len == 0;
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

pub fn scanGeneratedC(source: []const u8) Counts {
    return .{
        .lua_value = countOccurrences(source, "lua_Value"),
        .lua_invoke = countOccurrences(source, "lua_invoke"),
        .lua_table_new = countOccurrences(source, "lua_table_new"),
        .lua_to_unbox = countOccurrences(source, "lua_to_"),
        .malloc = countOccurrences(source, "malloc("),
        .gc_refs = countOccurrences(source, "lua_gc") + countOccurrences(source, "lua_collect"),
    };
}

fn pushViolation(
    alloc: std.mem.Allocator,
    list: *std.ArrayList(Violation),
    assert_tag: Assert,
    detail: []const u8,
) !void {
    try list.append(alloc, .{ .assert = assert_tag, .detail = try alloc.dupe(u8, detail) });
}

pub fn checkGeneratedC(
    alloc: std.mem.Allocator,
    source: []const u8,
    asserts: []const Assert,
) !Report {
    const counts = scanGeneratedC(source);
    var violations: std.ArrayList(Violation) = .empty;
    errdefer {
        for (violations.items) |v| alloc.free(v.detail);
        violations.deinit(alloc);
    }

    for (asserts) |a| switch (a) {
        .no_boxing => {
            if (counts.lua_value > 0)
                try pushViolation(alloc, &violations, a, "lua_Value present in generated C");
            if (counts.lua_invoke > 0)
                try pushViolation(alloc, &violations, a, "lua_invoke present in generated C");
            if (counts.lua_to_unbox > 0)
                try pushViolation(alloc, &violations, a, "lua_to_* unboxing in generated C");
        },
        .no_generic_table => {
            if (counts.lua_table_new > 0)
                try pushViolation(alloc, &violations, a, "lua_table_new in generated C");
        },
        .no_alloc => {
            if (counts.malloc > 0)
                try pushViolation(alloc, &violations, a, "malloc() in generated C");
        },
        .no_gc => {
            if (counts.gc_refs > 0)
                try pushViolation(alloc, &violations, a, "GC helper references in generated C");
        },
        .no_dynamic_dispatch => {
            if (counts.lua_invoke > 0)
                try pushViolation(alloc, &violations, a, "dynamic lua_invoke dispatch");
        },
        .no_generated_c => {
            try pushViolation(alloc, &violations, a, "artifact is generated C (forbidden for this profile)");
        },
        .no_external_compiler, .backend_direct => {},
    };

    return .{
        .kind = .generated_c,
        .counts = counts,
        .violations = try violations.toOwnedSlice(alloc),
    };
}

/// Mach-O magic: 0xFEEDFACF (64-bit) or 0xCEFAEDFE (32-bit LE).
pub fn isMachOObject(bytes: []const u8) bool {
    if (bytes.len < 4) return false;
    const magic = std.mem.readInt(u32, bytes[0..4], .little);
    return magic == 0xFEEDFACF or magic == 0xCEFAEDFE;
}

pub fn checkDirectObject(
    alloc: std.mem.Allocator,
    object_bytes: []const u8,
    asserts: []const Assert,
) !Report {
    var violations: std.ArrayList(Violation) = .empty;
    errdefer {
        for (violations.items) |v| alloc.free(v.detail);
        violations.deinit(alloc);
    }

    for (asserts) |a| switch (a) {
        .backend_direct, .no_generated_c, .no_external_compiler => {},
        .no_boxing, .no_alloc, .no_gc, .no_generic_table, .no_dynamic_dispatch => {
            // Direct objects contain no Lua runtime — these asserts are vacuously satisfied
            // when the artifact is raw Mach-O. Violations would require runtime section scans.
        },
    };

    if (!isMachOObject(object_bytes)) {
        try pushViolation(alloc, &violations, .backend_direct, "artifact is not Mach-O object format");
    }

    // Direct backend must not embed generated C source.
    if (std.mem.indexOf(u8, object_bytes, "lua_Value") != null)
        try pushViolation(alloc, &violations, .no_boxing, "lua_Value string embedded in object");

    return .{
        .kind = .mach_o_object,
        .counts = .{},
        .violations = try violations.toOwnedSlice(alloc),
    };
}

pub fn freeReport(alloc: std.mem.Allocator, report: Report) void {
    for (report.violations) |v| alloc.free(v.detail);
    alloc.free(report.violations);
}

/// Extract function body for the first definition containing `symbol(`.
pub fn extractFunctionBody(source: []const u8, symbol: []const u8, require_inline: bool) ?[]const u8 {
    var pos: usize = 0;
    while (pos < source.len) {
        const rel = std.mem.indexOfPos(u8, source, pos, symbol) orelse return null;
        const after = rel + symbol.len;
        if (after >= source.len or source[after] != '(') {
            pos = rel + 1;
            continue;
        }
        if (require_inline) {
    const back_start = if (rel > 160) rel - 160 else 0;
            const prefix = source[back_start..rel];
            if (std.mem.indexOf(u8, prefix, "static inline") == null and std.mem.indexOf(u8, prefix, "__attribute__((export_name") == null) {
                pos = rel + symbol.len;
                continue;
            }
        }
        const scan_end = @min(source.len, after + 256);
        const sig = source[after..scan_end];
        const semi = std.mem.indexOfScalar(u8, sig, ';');
        const brace_in_sig = std.mem.indexOfScalar(u8, sig, '{');
        if (semi != null and (brace_in_sig == null or semi.? < brace_in_sig.?)) {
            pos = rel + symbol.len;
            continue;
        }
        const brace_rel = brace_in_sig orelse {
            pos = rel + symbol.len;
            continue;
        };
        const start = after + brace_rel;
        var depth: u32 = 0;
        var i = start;
        while (i < source.len) : (i += 1) {
            switch (source[i]) {
                '{' => depth += 1,
                '}' => {
                    if (depth == 0) return null;
                    depth -= 1;
                    if (depth == 0) return source[start .. i + 1];
                },
                else => {},
            }
        }
        return null;
    }
    return null;
}

/// Extract body of a `static inline` function containing `symbol(`.
pub fn extractInlineFunctionBody(source: []const u8, symbol: []const u8) ?[]const u8 {
    return extractFunctionBody(source, symbol, true);
}

pub fn checkFunctionSymbol(
    alloc: std.mem.Allocator,
    source: []const u8,
    symbol: []const u8,
    require_inline: bool,
    asserts: []const Assert,
) !SymbolCheck {
    const body = extractFunctionBody(source, symbol, require_inline) orelse return .{
        .symbol = symbol,
        .found = false,
        .passed = false,
        .counts = .{},
        .violations = try alloc.alloc(Violation, 0),
    };
    var report = try checkGeneratedC(alloc, body, asserts);
    return .{
        .symbol = symbol,
        .found = true,
        .passed = report.passed(),
        .counts = report.counts,
        .violations = report.violations,
    };
}

pub fn checkInlineSymbol(
    alloc: std.mem.Allocator,
    source: []const u8,
    symbol: []const u8,
    asserts: []const Assert,
) !SymbolCheck {
    return checkFunctionSymbol(alloc, source, symbol, true, asserts);
}

pub const SymbolCheck = struct {
    symbol: []const u8,
    found: bool,
    passed: bool,
    counts: Counts,
    violations: []Violation,
};

pub fn freeSymbolCheck(alloc: std.mem.Allocator, sc: SymbolCheck) void {
    for (sc.violations) |v| alloc.free(v.detail);
    alloc.free(sc.violations);
}

pub const BarrierProfile = struct {
    id: []const u8,
    source_path: []const u8,
    symbols: []const []const u8,
    /// When false, profile documents a known boxing gap (honest Ward audit).
    expect_native: bool,
    require_inline: bool,
    /// When null, defaults to `{ .no_boxing, .no_dynamic_dispatch }`.
    asserts: ?[]const Assert = null,
};

pub const pass12_m1_profile = BarrierProfile{
    .id = "pass12_m1_classifier",
    .source_path = "examples/pass12_m1_diff.duo",
    .symbols = &.{
        "std_token_classify__classify_branch_chain",
    },
    .expect_native = true,
    .require_inline = true,
};

/// Native sorted lookup: module dense tables lower to C arrays (Pass 12 M1).
pub const pass12_m1_sorted_lookup_profile = BarrierProfile{
    .id = "pass12_m1_sorted_lookup",
    .source_path = "examples/pass12_m1_diff.duo",
    .symbols = &.{"std_token_classify__classify_sorted_lookup"},
    .expect_native = true,
    .require_inline = true,
};

/// Native opcode lookup tables (Pass 12 M2 partial): dense OPCODE_TO_INDEX + typed accessors.
pub const ward_opcode_lookup_profile = BarrierProfile{
    .id = "ward_opcode_lookup",
    .source_path = "examples/pass9/decode_semantic_smoke.duo",
    .symbols = &.{
        "std_wasm_opcode_lookup__instruction_index_for_opcode",
        "std_wasm_opcode_lookup__semantic_id_for_index",
    },
    .expect_native = true,
    .require_inline = true,
};

pub const ward_decode_profile = BarrierProfile{
    .id = "ward_decode_hot",
    .source_path = "examples/pass9/decode_semantic_smoke.duo",
    .symbols = &.{"std_wasm_decode__decode_instruction"},
    .expect_native = false,
    .require_inline = false,
};

/// Req-module devirtualization: decode_instruction hot path has zero lua_invoke (Pass 12 M2).
pub const ward_decode_dispatch_profile = BarrierProfile{
    .id = "ward_decode_dispatch",
    .source_path = "examples/pass9/decode_semantic_smoke.duo",
    .symbols = &.{"std_wasm_decode__decode_instruction"},
    .expect_native = true,
    .require_inline = false,
    .asserts = &.{.no_dynamic_dispatch},
};

pub fn writeSymbolCheckJson(w: *std.Io.Writer, sc: SymbolCheck) !void {
    try w.print("{{\"symbol\":\"{s}\",\"found\":", .{sc.symbol});
    try w.print("{s},\"passed\":", .{if (sc.found) "true" else "false"});
    try w.print("{s},\"lua_value\":{d},\"lua_invoke\":{d},\"violations\":[", .{
        if (sc.passed) "true" else "false",
        sc.counts.lua_value,
        sc.counts.lua_invoke,
    });
    for (sc.violations, 0..) |v, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"assert\":\"{s}\",\"detail\":\"{s}\"}}", .{ v.assert.name(), v.detail });
    }
    try w.writeAll("]}");
}

pub fn writeProfileResultJson(w: *std.Io.Writer, profile: BarrierProfile, checks: []const SymbolCheck, profile_ok: bool) !void {
    try w.print("{{\"schema\":\"{s}\",\"profile\":\"{s}\",\"source\":\"{s}\",\"expect_native\":", .{
        SCHEMA_VERSION, profile.id, profile.source_path,
    });
    try w.print("{s},\"profile_ok\":", .{if (profile.expect_native) "true" else "false"});
    try w.print("{s},\"checks\":[", .{if (profile_ok) "true" else "false"});
    for (checks, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try writeSymbolCheckJson(w, c);
    }
    try w.writeAll("]}");
}

pub fn evaluateProfile(alloc: std.mem.Allocator, profile: BarrierProfile, duo_bin: []const u8) !struct {
    profile_ok: bool,
    checks: []SymbolCheck,
} {
    const argv = [_][]const u8{ duo_bin, "dump-c", profile.source_path };
    const out = host_run.runHostCommandArgs(alloc, &argv) orelse return error.DuoBinaryMissing;
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    if (!out.ok) return error.DuoDumpFailed;
    const source = try alloc.dupe(u8, out.stdout);

    var list: std.ArrayListUnmanaged(SymbolCheck) = .empty;
    errdefer {
        for (list.items) |c| freeSymbolCheck(alloc, c);
        list.deinit(alloc);
        alloc.free(source);
    }

    const default_asserts = [_]Assert{ .no_boxing, .no_dynamic_dispatch };
    var profile_ok = true;
    for (profile.symbols) |sym| {
        const profile_asserts = profile.asserts orelse default_asserts[0..];
        const check = try checkFunctionSymbol(alloc, source, sym, profile.require_inline, profile_asserts);
        if (!check.found) profile_ok = false;
        if (profile.expect_native) {
            if (!check.passed) profile_ok = false;
        } else if (check.passed) profile_ok = false;
        try list.append(alloc, check);
    }
    alloc.free(source);
    return .{ .profile_ok = profile_ok, .checks = try list.toOwnedSlice(alloc) };
}

pub fn formatReport(report: Report, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "kind={s} lua_Value={d} lua_invoke={d} violations={d}", .{
        @tagName(report.kind),
        report.counts.lua_value,
        report.counts.lua_invoke,
        report.violations.len,
    }) catch "native_barrier_checks report";
}

test "native_barrier_checks: native scalar C passes no_boxing" {
    const sample =
        \\static inline double distance2(double x, double y) {
        \\    return x * x + y * y;
        \\}
    ;
    var report = try checkGeneratedC(std.testing.allocator, sample, &.{.no_boxing});
    defer freeReport(std.testing.allocator, report);
    try std.testing.expect(report.passed());
}

test "native_barrier_checks: boxed C fails no_boxing" {
    const sample =
        \\static lua_Value foo(lua_Value a) {
        \\    return lua_invoke(a, 0, NULL);
        \\}
    ;
    var report = try checkGeneratedC(std.testing.allocator, sample, &.{ .no_boxing, .no_dynamic_dispatch });
    defer freeReport(std.testing.allocator, report);
    try std.testing.expect(!report.passed());
    try std.testing.expect(report.violations.len >= 2);
}

test "native_barrier_checks: scanGeneratedC counts" {
    const sample = "lua_Value v; lua_invoke(x); lua_table_new(); lua_to_num(a); malloc(1);";
    const c = scanGeneratedC(sample);
    try std.testing.expectEqual(@as(usize, 1), c.lua_value);
    try std.testing.expectEqual(@as(usize, 1), c.lua_invoke);
    try std.testing.expectEqual(@as(usize, 1), c.lua_table_new);
    try std.testing.expectEqual(@as(usize, 1), c.lua_to_unbox);
    try std.testing.expectEqual(@as(usize, 1), c.malloc);
}

test "native_barrier_checks: extract inline function body" {
    const sample =
        \\static inline int64_t std_token_classify__classify(const char* w) {
        \\    if (strcmp(w, "and") == 0) return 4;
        \\    return 0;
        \\}
    ;
    const body = extractInlineFunctionBody(sample, "std_token_classify__classify") orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, body, "strcmp") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "lua_Value") == null);
}

test "native_barrier_checks: symbol prefix does not match longer names" {
    const sample =
        \\static inline int64_t std_token_classify__classify_branch_chain(const char* w) {
        \\    return 1;
        \\}
        \\static inline int64_t std_token_classify__classify(const char* w) {
        \\    return 2;
        \\}
    ;
    const body = extractInlineFunctionBody(sample, "std_token_classify__classify") orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, body, "return 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return 1") == null);
}

test "native_barrier_checks: pass12_m1 branch_chain body passes no_boxing" {
    const alloc = std.testing.allocator;
    const argv = [_][]const u8{ "zig-out/bin/duo", "dump-c", "examples/pass12_m1_diff.duo" };
    const out = @import("host_run.zig").runHostCommandArgs(alloc, &argv) orelse return error.SkipZigTest;
    defer alloc.free(out.stdout);
    if (!out.ok) return error.SkipZigTest;
    const body = extractFunctionBody(out.stdout, "std_token_classify__classify_branch_chain", true) orelse return error.TestExpectedEqual;
    var report = try checkGeneratedC(alloc, body, &.{ .no_boxing, .no_dynamic_dispatch });
    defer freeReport(alloc, report);
    if (!report.passed()) {
        for (report.violations) |v| std.debug.print("violation: {s} — {s}\n", .{ v.assert.name(), v.detail });
    }
    try std.testing.expect(report.passed());
}

test "native_barrier_checks: pass12_m1 sorted lookup profile end-to-end" {
    const alloc = std.testing.allocator;
    const r = try evaluateProfile(alloc, pass12_m1_sorted_lookup_profile, "zig-out/bin/duo");
    defer alloc.free(r.checks);
    defer for (r.checks) |c| freeSymbolCheck(alloc, c);
    try std.testing.expect(r.profile_ok);
}

test "native_barrier_checks: pass12_m1 profile end-to-end" {
    const alloc = std.testing.allocator;
    const r = try evaluateProfile(alloc, pass12_m1_profile, "zig-out/bin/duo");
    defer alloc.free(r.checks);
    defer for (r.checks) |c| freeSymbolCheck(alloc, c);
    for (r.checks) |c| {
        if (!c.passed) {
            std.debug.print("FAIL sym={s} found={} lv={d} li={d}\n", .{ c.symbol, c.found, c.counts.lua_value, c.counts.lua_invoke });
            for (c.violations) |v| std.debug.print("  {s}: {s}\n", .{ v.assert.name(), v.detail });
        }
    }
    try std.testing.expect(r.profile_ok);
}
