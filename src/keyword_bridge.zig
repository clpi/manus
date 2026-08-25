//! Production keyword lookup read from the generated projection of the ONE
//! grammar-fact owner (`lib/compiler/token.id`) — the same one-producer move
//! `spelling()` made in src/lexer.zig (law.fact.producer.one).
//!
//! This used to call an extern `duo_keyword_classify` from
//! src/keyword_classify.c — a second keyword-identity table generated from the
//! host table src/token_semantic.zig and linked weak on the stale promise that
//! the lexer artifact emits a strong override; src/lexer_tokenize.c defines no
//! such symbol, so the second producer always answered. Now the answer comes
//! from the owner's `.keyword` rows at comptime: damaging one keyword row in
//! src/grammar_role_table.zig changes what this compiler RECOGNISES, and
//! `zig build grammar-projection` is the counterfactual holding that table to
//! the Idol owner.
const std = @import("std");
const lexer = @import("lexer.zig");
const table = @import("grammar_role_table.zig");

const KeywordKV = struct { []const u8, lexer.TokenKind };

const keyword_kvs = blk: {
    var count: usize = 0;
    for (table.rows) |row| {
        if (row.keyword) count += 1;
    }
    var kvs: [count]KeywordKV = undefined;
    var i: usize = 0;
    for (table.rows) |row| {
        if (!row.keyword) continue;
        kvs[i] = .{ row.spell, row.kind.? };
        i += 1;
    }
    break :blk kvs;
};

const keyword_map = std.StaticStringMap(lexer.TokenKind).initComptime(keyword_kvs);

pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return keyword_map.get(text);
}

test "keyword bridge: production keywords" {
    try std.testing.expect(lookupKeyword("fun") == .kw_fun);
    try std.testing.expect(lookupKeyword("end") == .kw_end);
    try std.testing.expect(lookupKeyword("i64") == .kw_i64);
    try std.testing.expect(lookupKeyword("notkw") == null);
}

test "keyword bridge: the owner's keyword census is the retired table's" {
    // The retired classifier carried 54 spellings (ordinals 4..57). The
    // owner-derived map must carry the same census, or a keyword row silently
    // dropped out of the generated table.
    try std.testing.expectEqual(@as(usize, 54), keyword_kvs.len);
    // Every keyword row resolves to itself through the map.
    for (table.rows) |row| {
        if (!row.keyword) continue;
        try std.testing.expectEqual(row.kind.?, lookupKeyword(row.spell).?);
    }
    // No non-keyword identity is reachable by its spelling.
    try std.testing.expect(lookupKeyword("name") == null);
    try std.testing.expect(lookupKeyword("integer") == null);
    try std.testing.expect(lookupKeyword("text") == null);
}
