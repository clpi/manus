//! Duo-native keyword classifier projection (P12-WS6/WS7).
//!
//! Emits `lib/token/classify.id` and the compiler, LSP, and WASM keyword C
//! projections from the `.keyword` rows of `src/grammar_role_table.zig` — the
//! generated projection of the ONE grammar-fact owner, `lib/compiler/token.id`
//! (`law.grammar.one`, `law.fact.producer.one`). This generator used to read a
//! second 54-row host table (`src/token_semantic.zig`); that table is deleted
//! and the owner's rows are the only keyword-identity producer the emit reads.
//!
//! Projections emitted here: classifier (3 candidate realizations) and
//! spelling. Kind ids are lexer.TokenKind ordinals straight off the owner's
//! rows, so the Duo side is differential-equivalent to the host lexer path
//! (`src/keyword_bridge.zig` reads the same rows).
const std = @import("std");
const lexer = @import("lexer.zig");
const table = @import("grammar_role_table.zig");

pub const SCHEMA_VERSION = "grammar-role-v1";
pub const PROVENANCE = "src/token_classify_gen.zig";

const Keyword = struct { text: []const u8, kind: lexer.TokenKind };

/// The owner's keyword census in ordinal (row) order — the same rows the
/// production lookup in `src/keyword_bridge.zig` builds its map from.
pub const keywords = blk: {
    var count: usize = 0;
    for (table.rows) |row| {
        if (row.keyword) count += 1;
    }
    var kws: [count]Keyword = undefined;
    var i: usize = 0;
    for (table.rows) |row| {
        if (!row.keyword) continue;
        kws[i] = .{ .text = row.spell, .kind = row.kind.? };
        i += 1;
    }
    break :blk kws;
};

/// Lexicographic index order over the owner's keyword census.
fn sortedIndices() [keywords.len]usize {
    var idx: [keywords.len]usize = undefined;
    for (0..keywords.len) |i| idx[i] = i;
    var i: usize = 1;
    while (i < idx.len) : (i += 1) {
        const key = idx[i];
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, keywords[key].text, keywords[idx[j - 1]].text)) {
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
    const kws = keywords;
    const sorted = sortedIndices();
    try w.print(
        \\# GENERATED from src/token_classify_gen.zig — do not edit by hand.
        \\# Regenerate: idol token-tables emit
        \\# Keyword facts: src/grammar_role_table.zig `.keyword` rows — the
        \\# generated projection of the one owner, lib/compiler/token.id.
        \\
        \\# Duo-native keyword classifier (P12-WS7).
        \\# {d} reserved words; 3 candidate realizations. Kind ids are
        \\# lexer.TokenKind ordinals read off the owner's rows, so the Duo side
        \\# is differential-equivalent to the host path (src/keyword_bridge.zig).
        \\
        \\GENERATOROWNER = "src/token_classify_gen.zig"
        \\DESCRIPTORSCHEMA = "grammar-role-v1"
        \\KEYWORDCOUNT = {d}
        \\PRODUCTIONCLASSIFIER = "classifier.branchchain"
        \\
    , .{ kws.len, kws.len });

    // KIND_* constants — stable lexer.TokenKind ordinals.
    var name_buf: [32]u8 = undefined;
    for (kws) |kw| {
        const up = upperInto(&name_buf, kw.text);
        try w.print("KIND{s} = {d}\n", .{ up, @intFromEnum(kw.kind) });
    }

    // Sorted descriptor (lexicographic) — 1-indexed Lua tables.
    try w.writeAll("\n# Sorted descriptor (lexicographic) for sortedlookup + metadata.\nSORTEDTEXT = {\n");
    for (sorted, 0..) |ki, i| {
        try w.print("  {s}\"{s}\",\n", .{ if (i == 0) "" else "", kws[ki].text });
    }
    try w.writeAll("}\nSORTEDID = {\n");
    for (sorted, 0..) |ki, i| {
        try w.print("  {s}{d},\n", .{ if (i == 0) "" else "", @intFromEnum(kws[ki].kind) });
    }
    try w.writeAll("}\n");

    // Candidate 1 — branch chain (linear if-chain; no tables, no alloc).
    try w.writeAll("\n# Candidate 1: branch chain (production).\nclassifybranchchain: i64 = (w: str)\n");
    for (kws) |kw| {
        try w.print("  if w == \"{s}\"\n    return {d}\n", .{ kw.text, @intFromEnum(kw.kind) });
    }
    try w.writeAll("  0\n");

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
    try w.writeAll("\n# Candidate 2: length bucket (filter then equality chain).\nclassifylengthbucket: i64 = (w: str)\n  n = string.len(w)\n");
    for (lengths[0..len_count]) |l| {
        try w.print("  if n == {d}\n", .{l});
        for (kws) |kw| {
            if (kw.text.len != l) continue;
            try w.print("    if w == \"{s}\"\n      return {d}\n", .{ kw.text, @intFromEnum(kw.kind) });
        }
        try w.writeAll("    0\n");
    }
    try w.writeAll("  0\n");

    // Candidate 3 — sorted binary search.
    try w.print("\n# Candidate 3: sorted lookup (binary search over descriptor).\nclassifysortedlookup: i64 = (w: str)\n  lo = 1\n  hi = {d}\n  while lo <= hi\n    mid = (lo + hi) // 2\n    if w == SORTEDTEXT[mid]\n      return SORTEDID[mid]\n    if w < SORTEDTEXT[mid]\n      hi = mid - 1\n    else\n      lo = mid + 1\n  0\n", .{kws.len});

    // Production entry + metadata projections.
    try w.writeAll(
        \\
        \\# Production entry (branch chain, mirrored by src/keyword_classify.c).
        \\@c.export("duo_keyword_classify")
        \\classify: i64 = (w: str)
        \\  classifybranchchain(w)
        \\
        \\iskeyword: bool = (w: str)
        \\  classify(w) != 0
        \\
        \\spellingof: str = (id: i64)
        \\  i = 1
        \\  while i <= KEYWORDCOUNT
        \\    if SORTEDID[i] == id
        \\      return SORTEDTEXT[i]
        \\    i += 1
        \\  ""
        \\
    );
}

/// C realization of `classify.id` production entry — linked into the duo binary (P16-WS3).
pub fn emitKeywordClassifyNativeC(w: *std.Io.Writer) !void {
    const kws = keywords;
    try w.print(
        \\/* GENERATED from {s} — do not edit by hand.
        \\ * Regenerate: idol token-tables emit
        \\ * Canonical Duo projection: lib/token/classify.id (@c.export classify)
        \\ * Production consumer: src/main.zig boot() — the direct backend's link
        \\ * input for user programs importing the symbol. The compiler's own
        \\ * lexer reads the owner's rows (src/keyword_bridge.zig), not this.
        \\ */
        \\#include <stdint.h>
        \\#include <string.h>
        \\
        \\/* weak: this generated table is the PROJECTION of
        \\ * lib/token/classify.id. A program that embeds the canonical Duo
        \\ * source emits its own definition of the same symbol, and A3 ONE EDGE
        \\ * says there is one fact behind both — so the idol-emitted one must be
        \\ * allowed to win rather than colliding. Without this, anything pulling
        \\ * in SH-02's artifact AND SH-03's lexer fails to link with
        \\ * `duplicate symbol '_duo_keyword_classify'`. */
        \\__attribute__((weak)) int64_t duo_keyword_classify(const char *w) {{
        \\
    , .{PROVENANCE});
    for (kws) |kw| {
        try w.print("    if (strcmp(w, \"{s}\") == 0) return {d};\n", .{ kw.text, @intFromEnum(kw.kind) });
    }
    try w.writeAll("    return 0;\n}\n");
}

pub fn emitKeywordClassifyNativeCFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitKeywordClassifyNativeC(&aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
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

test "token_classify_gen: emitted kind ids match the owner's rows" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitTokenClassify(&aw.writer);
    const out = aw.written();
    var name_buf: [32]u8 = undefined;
    for (keywords) |kw| {
        const up = upperInto(&name_buf, kw.text);
        var want_buf: [64]u8 = undefined;
        const want = std.fmt.bufPrint(&want_buf, "KIND{s} = {d}", .{ up, @intFromEnum(kw.kind) }) catch unreachable;
        try std.testing.expect(std.mem.indexOf(u8, out, want) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, out, "classifybranchchain") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classifysortedlookup") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classifylengthbucket") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "SORTEDID") != null);
}

test "token_classify_gen: sorted descriptor is lexicographic" {
    const sorted = sortedIndices();
    for (1..sorted.len) |i| {
        const a = keywords[sorted[i - 1]].text;
        const b = keywords[sorted[i]].text;
        try std.testing.expect(std.mem.lessThan(u8, a, b));
    }
}

test "token_classify_gen: the census is the retired host table's" {
    // The deleted src/token_semantic.zig carried 54 rows; the owner's rows
    // must carry the same census or a keyword silently dropped out of the
    // generated artifacts.
    try std.testing.expectEqual(@as(usize, 54), keywords.len);
}

test "token_classify_gen: emit native C when EMIT_CLASSIFY_C set" {
    const path_z = std.c.getenv("EMIT_CLASSIFY_C") orelse return;
    const path = std.mem.span(path_z);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    try emitKeywordClassifyNativeCFile(std.testing.allocator, threaded.io(), path);
}
