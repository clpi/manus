//! GAP-134 — grammar-role ACCESSORS over the one Idol grammar-fact owner.
//! The facts live in `lib/compiler/token.id` (`law.grammar.one`); this file
//! holds no role of its own. `src/grammar_role_table.zig` is the generated
//! bridge (`law.bridge.death`) that carries them into the host parser.
//! Damaging a role in the Idol owner and regenerating changes what this
//! compiler accepts — that counterfactual is the point of the split.
//! Parser BinOp maps remain debt.
const std = @import("std");
const lexer = @import("lexer.zig");
const table = @import("grammar_role_table.zig");

pub const SCHEMA_VERSION = "grammar-role-v1";

/// Re-exported from the generated table. Every one of these is a projection
/// of the Idol owner; nothing here may be edited to change a grammar fact.
pub const Associativity = table.Associativity;
pub const RoleRow = table.RoleRow;
pub const slot_count = table.slot_count;
pub const rows = table.rows;

pub fn lookup(kind: lexer.TokenKind) RoleRow {
    return rows[@backingInt(kind)];
}

pub fn canBeginExpression(kind: lexer.TokenKind) bool {
    return lookup(kind).begin_expr;
}

/// Literal tokens that may appear as call operands but never in a parameter list.
pub fn isLiteralKind(kind: lexer.TokenKind) bool {
    return lookup(kind).literal_kind;
}

/// Quoted payload identities (text/bytes/compat). Slot 3 is unpublished.
pub fn isQuotedKind(kind: lexer.TokenKind) bool {
    return lookup(kind).quoted;
}

/// Binary/assignment operators that disqualify a paren group from being a param list.
/// Infix operator identity — associativity is the fact, not token text.
pub fn isInfix(kind: lexer.TokenKind) bool {
    return lookup(kind).assoc != .none;
}

pub fn canStartBody(kind: lexer.TokenKind) bool {
    return lookup(kind).body_start;
}

/// MAY CANONICAL TOOLING WRITE THIS SPELLING? (HPLS §94.)
///
/// The parser still ACCEPTS every compat-only spelling — acceptance and
/// emission are different questions, and collapsing them is how "the current
/// compiler cannot do X" turns into "Idol should not permit X". This answers
/// only the second: a formatter, an LSP code action, a doc generator or an MCP
/// surface that writes a token this returns `false` for is generating retired
/// syntax from canonical tooling, which §94 forbids.
///
/// It exists because `compat_only` had ZERO consumers while three separate
/// enforcers each held a private copy of the same fact.
pub fn admits(kind: lexer.TokenKind) bool {
    return !lookup(kind).compat_only;
}

/// Primitive descriptor identities (`i64`, `str`, …) — not a spelling list.
pub fn isDescriptor(kind: lexer.TokenKind) bool {
    return lookup(kind).descriptor;
}

/// Match-pattern start — generated fact, not a parser kind list.
pub fn canStartPattern(kind: lexer.TokenKind) bool {
    return lookup(kind).pattern;
}

test "grammar roles: identity not spelling drives prefix on dot" {
    try std.testing.expect(lookup(.dot).postfix);
    try std.testing.expect(!lookup(.dot).prefix);
}

test "grammar roles: backtick is compat-only and not expression-start" {
    const r = lookup(.backtick);
    try std.testing.expect(r.compat_only);
    try std.testing.expect(!r.begin_expr);
}

test "grammar roles: text and bytes both begin expressions" {
    try std.testing.expect(canBeginExpression(.text_lit));
    try std.testing.expect(canBeginExpression(.bytes_lit));
    try std.testing.expect(canBeginExpression(.compat_text_lit));
    try std.testing.expect(isQuotedKind(.text_lit));
    try std.testing.expect(isQuotedKind(.bytes_lit));
    try std.testing.expect(!isQuotedKind(.int_lit));
}

test "grammar roles: expression start and compatibility are independent facts" {
    try std.testing.expect(canBeginExpression(.kw_function));
    try std.testing.expect(lookup(.kw_function).compat_only);
    try std.testing.expect(canBeginExpression(.kw_if));
    try std.testing.expect(!lookup(.kw_if).compat_only);
    try std.testing.expect(canBeginExpression(.pipe));
    try std.testing.expect(canBeginExpression(.dot));
    try std.testing.expect(canBeginExpression(.colon));
    try std.testing.expect(canBeginExpression(.kw_i64));
    try std.testing.expect(!canBeginExpression(.lbracket));
    try std.testing.expect(!canBeginExpression(.comma));
}

test "grammar roles: shebang and comments are trivia not expression-start" {
    try std.testing.expect(!canBeginExpression(.shebang));
    try std.testing.expect(!canBeginExpression(.comment));
    try std.testing.expect(!canBeginExpression(.compat_comment));
    try std.testing.expect(!canBeginExpression(.compat_long_comment));
    try std.testing.expect(lookup(.compat_comment).compat_only);
    try std.testing.expect(!lookup(.shebang).compat_only);
}

test "grammar roles: long text is a literal body start by identity" {
    try std.testing.expect(isLiteralKind(.compat_long_text_lit));
    try std.testing.expect(canStartBody(.compat_long_text_lit));
    try std.testing.expect(canStartBody(.text_lit));
    try std.testing.expect(canStartBody(.bytes_lit));
}

test "grammar roles: prefix operators begin expressions by identity" {
    try std.testing.expect(lookup(.hash).prefix);
    try std.testing.expect(lookup(.minus).prefix);
    try std.testing.expect(lookup(.bang).prefix);
    try std.testing.expect(!lookup(.plus).prefix);
}

test "grammar roles: infix is identity not spelling" {
    try std.testing.expect(isInfix(.amp));
    try std.testing.expect(isInfix(.kw_and));
    try std.testing.expect(isInfix(.lt));
    try std.testing.expectEqual(Associativity.nonassoc, lookup(.lt).assoc);
    try std.testing.expect(!isInfix(.bang));
    try std.testing.expect(!isInfix(.dot));
    try std.testing.expectEqualStrings("&", lexer.TokenKind.amp.spelling());
}

test "grammar roles: quoted is identity not spelling" {
    try std.testing.expect(isQuotedKind(.text_lit));
    try std.testing.expect(isQuotedKind(.bytes_lit));
    try std.testing.expect(isQuotedKind(.compat_long_text_lit));
    try std.testing.expect(!isQuotedKind(.int_lit));
    try std.testing.expect(!isQuotedKind(.name));
}

test "grammar roles: descriptor is identity not spelling" {
    try std.testing.expect(isDescriptor(.kw_i64));
    try std.testing.expect(isDescriptor(.kw_str));
    try std.testing.expect(!isDescriptor(.name));
    try std.testing.expect(!isDescriptor(.kw_fun));
}

test "grammar roles: pattern start is identity not a parser list" {
    try std.testing.expect(canStartPattern(.name));
    try std.testing.expect(canStartPattern(.text_lit));
    try std.testing.expect(canStartPattern(.bytes_lit));
    try std.testing.expect(canStartPattern(.lbrace));
    try std.testing.expect(canStartPattern(.minus));
    try std.testing.expect(!canStartPattern(.kw_if));
    try std.testing.expect(!canStartPattern(.lparen));
    try std.testing.expect(!canStartPattern(.plus));
}

test "grammar roles: plus is infix not postfix" {
    try std.testing.expect(isInfix(.plus));
    try std.testing.expect(!isInfix(.dot));
    try std.testing.expect(!isInfix(.bang));
}

test "grammar roles: distinct spellings collapse to one identity and one role" {
    // `!=` is the one inequality spelling; it lexes to the identity `.neq`
    // (src/lexer.zig). Role lookup keys on that identity rather than on the
    // characters, so the role is one row: a nonassoc comparison sharing the
    // `.eq` role class. Holding identity fixed fixes the role — spelling never
    // reaches this table. (`~=` used to be a second spelling of this identity
    // and is now xor-assign, which is exactly the kind of change this
    // separation absorbs without touching the role table.)
    const r = lookup(.neq);
    try std.testing.expect(isInfix(.neq));
    try std.testing.expectEqual(Associativity.nonassoc, r.assoc);
    try std.testing.expectEqual(lookup(.eq).precedence, r.precedence);
    try std.testing.expectEqual(lookup(.eq).assoc, r.assoc);
    try std.testing.expectEqualStrings("!=", lexer.TokenKind.neq.spelling());
}

test "grammar roles: one spelling splits into identities with different roles" {
    // The single character `#` leads three distinct token identities: `.hash`
    // (compatibility length prefix), `.comment` (canonical trivia), and
    // `.shebang` (`#!` at byte zero). Same spelling, different identity,
    // different role — recognition follows identity, never the `#` text.
    try std.testing.expectEqualStrings("#", lexer.TokenKind.hash.spelling());
    try std.testing.expectEqualStrings("#", lexer.TokenKind.comment.spelling());
    try std.testing.expect(canBeginExpression(.hash));
    try std.testing.expect(lookup(.hash).prefix);
    try std.testing.expect(!canBeginExpression(.comment));
    try std.testing.expect(!canBeginExpression(.shebang));
    try std.testing.expect(!lookup(.comment).prefix);
}

test "grammar roles: canonical and compatibility faces stay distinct" {
    // Shared structural role (literal, comment trivia, infix), distinct
    // canonical vs compatibility identity via the compat_only fact.
    try std.testing.expect(!lookup(.text_lit).compat_only);
    try std.testing.expect(lookup(.compat_text_lit).compat_only);
    try std.testing.expect(lookup(.text_lit).quoted and lookup(.compat_text_lit).quoted);

    try std.testing.expect(!lookup(.comment).compat_only);
    try std.testing.expect(lookup(.compat_comment).compat_only);

    try std.testing.expect(isInfix(.pipe) and !lookup(.pipe).compat_only);
    try std.testing.expect(isInfix(.kw_or) and lookup(.kw_or).compat_only);
    try std.testing.expect(isInfix(.amp) and !lookup(.amp).compat_only);
    try std.testing.expect(isInfix(.kw_and) and lookup(.kw_and).compat_only);
}

test "grammar roles: every token identity has one ordinal row" {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    try std.testing.expectEqual(enum_info.field_names.len + 1, rows.len);
    inline for (enum_info.field_values) |value| {
        const kind: lexer.TokenKind = @fromBackingInt(@intCast(value));
        try std.testing.expectEqual(kind, lookup(kind).kind.?);
    }
}

test "grammar roles: unpublished producer slot has no token identity or role" {
    try std.testing.expect(!@hasField(lexer.TokenKind, "string_lit"));
    try std.testing.expectEqual(@as(usize, 4), @backingInt(lexer.TokenKind.kw_and));
    try std.testing.expect(rows[3].kind == null);
    try std.testing.expect(!rows[3].begin_expr);
    try std.testing.expect(!rows[3].literal_kind);
    try std.testing.expect(!rows[3].quoted);
}
