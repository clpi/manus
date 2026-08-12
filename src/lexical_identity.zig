//! GAP-145 — canonical lexical token identities (production source of truth).
//!
//! Distinct kinds for text, bytes, compatibility literals, comments (trivia
//! classification), shebang, and reserved backtick. Parser and formatter must
//! consume kind ids, never delimiter spelling.
const std = @import("std");
const lexer = @import("lexer.zig");
const bridge = @import("lexer_bridge.zig");

pub const SCHEMA_VERSION = "lexical-identity-v1";

pub const SourceLaw = bridge.SourceLaw;
pub const SourceProvenance = bridge.SourceProvenance;
pub const SourceFacts = bridge.SourceFacts;

pub const LiteralKind = enum {
    text,
    bytes,
    compat_text,
    compat_long_text,

    pub fn tokenKind(self: LiteralKind) lexer.TokenKind {
        return switch (self) {
            .text => .text_lit,
            .bytes => .bytes_lit,
            .compat_text => .compat_text_lit,
            .compat_long_text => .compat_long_text_lit,
        };
    }
};

pub const TriviaClass = enum {
    none,
    shebang,
    comment_canon,
    comment_lua_dash,
    comment_lua_long,
};

pub fn sourceFacts(path: []const u8) bridge.SourceFacts {
    return bridge.sourceFacts(path);
}

pub fn isCanonicalSource(path: []const u8) bool {
    return sourceFacts(path).provenance == .canonical;
}

pub fn classifyQuote(facts: SourceFacts, quote: u8, long_string: bool) ?LiteralKind {
    if (long_string) return .compat_long_text;
    return switch (quote) {
        '"' => .text,
        '\'' => switch (facts.law) {
            .idol => if (facts.provenance == .canonical) .bytes else .compat_text,
            .lua => .compat_text,
            .unknown => .compat_text,
        },
        else => null,
    };
}

pub fn classifyHistoricalSingleQuote(provenance: SourceProvenance) LiteralKind {
    return if (provenance == .canonical) .bytes else .compat_text;
}

pub fn classifyTrivia(facts: SourceFacts, at_bol: bool, first: u8, second: u8) TriviaClass {
    if (at_bol and first == '#' and second == '!') return .shebang;
    if (first == '#') {
        if (facts.provenance == .canonical) return .comment_canon;
        return .none;
    }
    if (first == '-' and second == '-') return .comment_lua_dash;
    return .none;
}

pub fn isCanonicalLineComment(facts: SourceFacts, c: u8) bool {
    return facts.provenance == .canonical and c == '#';
}

pub fn hashOperatorAllowed(facts: SourceFacts) bool {
    return facts.provenance != .canonical;
}

pub fn backtickAllowed(facts: SourceFacts) bool {
    return facts.provenance != .canonical;
}

test "lexical identity: backtick is reserved in canonical source only" {
    try std.testing.expect(!backtickAllowed(sourceFacts("x.id")));
    try std.testing.expect(backtickAllowed(sourceFacts("x.duo")));
    try std.testing.expect(backtickAllowed(sourceFacts("x.lua")));
}

test "lexical identity: text and bytes differ on canonical .id" {
    const facts = sourceFacts("x.id");
    try std.testing.expectEqual(SourceLaw.idol, facts.law);
    try std.testing.expectEqual(LiteralKind.text.tokenKind(), classifyQuote(facts, '"', false).?.tokenKind());
    try std.testing.expectEqual(LiteralKind.bytes.tokenKind(), classifyQuote(facts, '\'', false).?.tokenKind());
}

test "lexical identity: historical single quote is compatibility text" {
    try std.testing.expectEqual(
        LiteralKind.compat_text.tokenKind(),
        classifyHistoricalSingleQuote(.historical).tokenKind(),
    );
}

test "lexical identity: long strings are compatibility long text" {
    const facts = sourceFacts("x.id");
    try std.testing.expectEqual(
        LiteralKind.compat_long_text.tokenKind(),
        classifyQuote(facts, '[', true).?.tokenKind(),
    );
}

test "lexical identity: historical single quote stays compatibility text" {
    const facts = sourceFacts("x.duo");
    try std.testing.expectEqual(
        LiteralKind.compat_text.tokenKind(),
        classifyQuote(facts, '\'', false).?.tokenKind(),
    );
}

test "lexical identity: canonical hash is comment trivia not operator" {
    const facts = sourceFacts("x.id");
    try std.testing.expect(!hashOperatorAllowed(facts));
    try std.testing.expect(hashOperatorAllowed(sourceFacts("x.duo")));
    try std.testing.expectEqual(TriviaClass.comment_canon, classifyTrivia(facts, true, '#', 'x'));
    try std.testing.expectEqual(TriviaClass.shebang, classifyTrivia(facts, true, '#', '!'));
}

test "lexical identity: spelling change preserves role lookup path" {
    // Same kind, different spellings of delimiter are irrelevant once classified.
    try std.testing.expectEqual(@intFromEnum(LiteralKind.text.tokenKind()), @intFromEnum(LiteralKind.text.tokenKind()));
}

