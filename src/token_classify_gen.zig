//! Pass 12 M1 — Duo-native keyword classifier projection (P12-WS6/WS7).
//!
//! Emits `lib/std/token/classify.duo` from the canonical descriptor in
//! `src/token_semantic.zig` (mirror of `wasm_semantic_gen.zig` → opcode_lookup.duo).
//!
//! Projections emitted here: classifier (3 candidate realizations), spelling,
//! category metadata. Kind ids are lexer.TokenKind ordinals so the Duo side is
//! differential-equivalent to the Zig host path consumed by `src/lexer.zig`.
const std = @import("std");
const token_semantic = @import("token_semantic.zig");

pub const SCHEMA_VERSION = "token-semantic-v0";
pub const PROVENANCE = "src/token_classify_gen.zig";

fn categoryInt(kw: token_semantic.KeywordEntry) i64 {
    return @intFromEnum(kw.category) + 1;
}

/// Lexicographic index order over the canonical keyword table.
fn sortedIndices() [token_semantic.keywords.len]usize {
    var idx: [token_semantic.keywords.len]usize = undefined;
    for (0..token_semantic.keywords.len) |i| idx[i] = i;
    var i: usize = 1;
    while (i < idx.len) : (i += 1) {
        const key = idx[i];
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, token_semantic.keywords[key].text, token_semantic.keywords[idx[j - 1]].text)) {
            idx[j] = idx[j - 1];
            j -= 1;
        }
        idx[j] = key;
    }
    return idx;
}

fn upperInto(buf: *[32]u8, s: []const u8) []const u8 {
    std.debug.assert(s.len <= buf.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return buf[0..s.len];
}

pub fn emitTokenClassify(w: *std.Io.Writer) !void {
    const kws = token_semantic.keywords;
    const sorted = sortedIndices();
    try w.print(
        \\-- GENERATED from src/token_classify_gen.zig — do not edit by hand.
        \\-- Regenerate: duo token-tables emit
        \\-- Canonical token facts: src/token_semantic.zig
        \\
        \\-- Pass 12 M1 — Duo-native keyword classifier (P12-WS7).
        \\-- {d} reserved words across 3 categories; 3 candidate realizations.
        \\-- Proof: examples/pass12_m1_diff.duo (differential + fuzz); artifact
        \\-- inspection in src/token_classify_gen.zig (kind ids match lexer.TokenKind).
        \\
        \\GENERATOR_OWNER = "src/token_classify_gen.zig"
        \\DESCRIPTOR_SCHEMA = "token-semantic-v0"
        \\KEYWORD_COUNT = {d}
        \\PRODUCTION_CLASSIFIER = "classifier.branch_chain"
        \\
        \\-- Categories: 1 = lua_keyword, 2 = duo_type, 3 = duo_contextual
        \\CATEGORY_LUA = 1
        \\CATEGORY_DUO_TYPE = 2
        \\CATEGORY_DUO_CONTEXTUAL = 3
        \\
    , .{ kws.len, kws.len });

    // KIND_* constants — stable lexer.TokenKind ordinals.
    var name_buf: [32]u8 = undefined;
    for (kws) |kw| {
        const up = upperInto(&name_buf, kw.text);
        try w.print("KIND_{s} = {d}\n", .{ up, @intFromEnum(kw.kind) });
    }

    // Sorted descriptor (lexicographic) — 1-indexed Lua tables.
    try w.writeAll("\n-- Sorted descriptor (lexicographic) for sorted_lookup + metadata.\nSORTED_TEXT = {\n");
    for (sorted, 0..) |ki, i| {
        try w.print("    {s}\"{s}\",\n", .{ if (i == 0) "" else "", kws[ki].text });
    }
    try w.writeAll("}\nSORTED_ID = {\n");
    for (sorted, 0..) |ki, i| {
        try w.print("    {s}{d},\n", .{ if (i == 0) "" else "", @intFromEnum(kws[ki].kind) });
    }
    try w.writeAll("}\nSORTED_CATEGORY = {\n");
    for (sorted, 0..) |ki, i| {
        try w.print("    {s}{d},\n", .{ if (i == 0) "" else "", categoryInt(kws[ki]) });
    }
    try w.writeAll("}\n");

    // Candidate 1 — branch chain (linear if-chain; no tables, no alloc).
    try w.writeAll("\n-- Candidate 1: branch chain (production).\nfun classify_branch_chain(w: str): i64\n");
    for (kws) |kw| {
        try w.print("    if w == \"{s}\" then return {d} end\n", .{ kw.text, @intFromEnum(kw.kind) });
    }
    try w.writeAll("    0\nend\n");

    // Candidate 2 — length bucket (length filter then equality chain).
    var lengths: [32]usize = undefined;
    var len_count: usize = 0;
    for (kws) |kw| {
        const l = kw.text.len;
        var found = false;
        for (lengths[0..len_count]) |ex| {
            if (ex == l) found = true;
        }
        if (!found) {
            lengths[len_count] = l;
            len_count += 1;
        }
    }
    std.mem.sort(usize, lengths[0..len_count], {}, struct {
        fn lessThan(_: void, a: usize, b: usize) bool {
            return a < b;
        }
    }.lessThan);
    try w.writeAll("\n-- Candidate 2: length bucket (filter then equality chain).\nfun classify_length_bucket(w: str): i64\n    n = string.len(w)\n");
    for (lengths[0..len_count]) |l| {
        try w.print("    if n == {d} then\n", .{l});
        for (kws) |kw| {
            if (kw.text.len != l) continue;
            try w.print("        if w == \"{s}\" then return {d} end\n", .{ kw.text, @intFromEnum(kw.kind) });
        }
        try w.writeAll("        0\n    end\n");
    }
    try w.writeAll("    0\nend\n");

    // Candidate 3 — sorted binary search.
    try w.print("\n-- Candidate 3: sorted lookup (binary search over descriptor).\nfun classify_sorted_lookup(w: str): i64\n    lo = 1\n    hi = {d}\n    while lo <= hi\n        mid = (lo + hi) // 2\n        t = SORTED_TEXT[mid]\n        if w == t then return SORTED_ID[mid] end\n        if w < t then\n            hi = mid - 1\n        else\n            lo = mid + 1\n        end\n    end\n    0\nend\n", .{kws.len});

    // Production entry + metadata projections.
    try w.writeAll(
        \\
        \\-- Production entry (mirrors token_semantic.production_classifier).
        \\fun classify(w: str): i64
        \\    classify_branch_chain(w)
        \\end
        \\
        \\fun is_keyword(w: str): bool
        \\    classify(w) != 0
        \\end
        \\
        \\fun category_of(id: i64): i64
        \\    i = 1
        \\    while i <= KEYWORD_COUNT
        \\        if SORTED_ID[i] == id then return SORTED_CATEGORY[i] end
        \\        i = i + 1
        \\    end
        \\    0
        \\end
        \\
        \\fun spelling_of(id: i64): str
        \\    i = 1
        \\    while i <= KEYWORD_COUNT
        \\        if SORTED_ID[i] == id then return SORTED_TEXT[i] end
        \\        i = i + 1
        \\    end
        \\    ""
        \\end
        \\
    );
}

pub fn emitTokenClassifyFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitTokenClassify(&aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
}

test "token_classify_gen: emitted kind ids match descriptor" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitTokenClassify(&aw.writer);
    const out = aw.written();
    var name_buf: [32]u8 = undefined;
    for (token_semantic.keywords) |kw| {
        const up = upperInto(&name_buf, kw.text);
        var want_buf: [64]u8 = undefined;
        const want = std.fmt.bufPrint(&want_buf, "KIND_{s} = {d}", .{ up, @intFromEnum(kw.kind) }) catch unreachable;
        try std.testing.expect(std.mem.indexOf(u8, out, want) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, out, "classify_branch_chain") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classify_sorted_lookup") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classify_length_bucket") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "SORTED_ID") != null);
}

test "token_classify_gen: sorted descriptor is lexicographic" {
    const sorted = sortedIndices();
    for (1..sorted.len) |i| {
        const a = token_semantic.keywords[sorted[i - 1]].text;
        const b = token_semantic.keywords[sorted[i]].text;
        try std.testing.expect(std.mem.lessThan(u8, a, b));
    }
}
