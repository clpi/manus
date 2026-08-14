//! GAP-134 — transitional host grammar-role table (`law.grammar.one`).
//! Keyed by TokenKind ordinal, never by spelling. This file is a bridge
//! (`law.bridge.death`): destination is one Idol grammar-fact owner that
//! generates this table, `grammar.md`, and Tree-sitter. Do not treat this
//! as the permanent grammar authority. Parser BinOp maps remain debt.
const std = @import("std");
const lexer = @import("lexer.zig");

pub const SCHEMA_VERSION = "grammar-role-v1";

pub const Associativity = enum(u8) {
    none = 0,
    left = 1,
    right = 2,
    nonassoc = 3,
};

pub const RoleRow = struct {
    kind: lexer.TokenKind,
    begin_expr: bool = false,
    prefix: bool = false,
    postfix: bool = false,
    parameter: bool = false,
    literal_kind: bool = false,
    projection: bool = false,
    body_start: bool = false,
    quoted: bool = false,
    descriptor: bool = false,
    pattern: bool = false,
    precedence: i8 = 0,
    assoc: Associativity = .none,
    compat_only: bool = false,
};

fn row(comptime k: lexer.TokenKind, r: RoleRow) RoleRow {
    _ = k;
    return r;
}

/// Compact generated lookup table — one row per TokenKind ordinal.
pub const rows = blk: {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    var table: [enum_info.field_names.len]RoleRow = undefined;
    @memset(&table, .{ .kind = .name });
    for (enum_info.field_names, enum_info.field_values, 0..) |_, value, ordinal| {
        const kind: lexer.TokenKind = @enumFromInt(value);
        table[ordinal] = switch (kind) {
            .name => row(kind, .{ .kind = kind, .begin_expr = true, .body_start = true, .pattern = true }),
            .int_lit, .float_lit => row(kind, .{ .kind = kind, .begin_expr = true, .literal_kind = true, .body_start = true, .pattern = true }),
            .text_lit, .bytes_lit => row(kind, .{ .kind = kind, .begin_expr = true, .literal_kind = true, .quoted = true, .body_start = true, .pattern = true }),
            .compat_text_lit, .compat_long_text_lit => row(kind, .{
                .kind = kind,
                .begin_expr = true,
                .compat_only = true,
                .literal_kind = true,
                .quoted = true,
                .body_start = true,
                .pattern = true,
            }),
            .string_lit => row(kind, .{ .kind = kind }),
            .kw_true, .kw_false, .kw_nil => row(kind, .{
                .kind = kind,
                .begin_expr = true,
                .compat_only = true,
                .body_start = true,
                .pattern = true,
            }),
            .dots => row(kind, .{ .kind = kind, .begin_expr = true, .pattern = true }),
            .lparen => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .body_start = true }),
            .lbrace => row(kind, .{ .kind = kind, .begin_expr = true, .body_start = true, .pattern = true }),
            .lbracket => row(kind, .{ .kind = kind, .begin_expr = true, .projection = true, .pattern = true }),
            .kw_not => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .precedence = 9, .body_start = true }),
            .bang => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .precedence = 9 }),
            .tilde => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .precedence = 9, .assoc = .left }),
            .hash => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .compat_only = true, .body_start = true }),
            .hash_hash => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .compat_only = true }),
            .kw_comptime, .kw_await => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true }),
            .comma => row(kind, .{ .kind = kind, .begin_expr = true }),
            .at => row(kind, .{ .kind = kind, .begin_expr = true, .precedence = 19, .assoc = .left, .body_start = true }),
            .dot => row(kind, .{ .kind = kind, .postfix = true, .projection = true, .precedence = 10 }),
            .colon => row(kind, .{ .kind = kind, .parameter = true, .projection = true }),
            .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64, .kw_f32, .kw_f64, .kw_bool, .kw_void, .kw_str => row(kind, .{ .kind = kind, .descriptor = true }),
            .star, .slash, .percent, .idiv => row(kind, .{ .kind = kind, .precedence = 19, .assoc = .left }),
            .plus => row(kind, .{ .kind = kind, .precedence = 17, .assoc = .left }),
            .minus => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .precedence = 17, .assoc = .left, .body_start = true, .pattern = true }),
            .concat => row(kind, .{ .kind = kind, .precedence = 16, .assoc = .right, .compat_only = true }),
            .eq, .neq, .lt, .gt, .leq, .geq, .kw_in => row(kind, .{ .kind = kind, .precedence = 6, .assoc = .nonassoc }),
            .kw_or => row(kind, .{ .kind = kind, .precedence = 2, .assoc = .left, .compat_only = true }),
            .kw_and => row(kind, .{ .kind = kind, .precedence = 4, .assoc = .left, .compat_only = true }),
            .pipe => row(kind, .{ .kind = kind, .precedence = 7, .assoc = .left, .body_start = true }),
            .amp => row(kind, .{ .kind = kind, .precedence = 11, .assoc = .left }),
            .lshift, .rshift => row(kind, .{ .kind = kind, .precedence = 13, .assoc = .left }),
            .caret => row(kind, .{ .kind = kind, .precedence = 23, .assoc = .right }),
            .pipe_gt => row(kind, .{ .kind = kind, .precedence = 1, .assoc = .left }),
            .assign, .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign, .caret_assign => row(kind, .{
                .kind = kind,
                .precedence = 1,
                .assoc = .right,
            }),
            .kw_if, .kw_match, .kw_while, .kw_for => row(kind, .{ .kind = kind, .body_start = true }),
            .kw_fun, .kw_function => row(kind, .{ .kind = kind, .compat_only = true, .body_start = true }),
            .kw_local, .kw_const, .kw_let => row(kind, .{ .kind = kind, .compat_only = true }),
            .backtick => row(kind, .{ .kind = kind, .compat_only = true }),
            .shebang => row(kind, .{ .kind = kind }),
            .comment => row(kind, .{ .kind = kind }),
            .compat_comment, .compat_long_comment => row(kind, .{ .kind = kind, .compat_only = true }),
            else => row(kind, .{ .kind = kind }),
        };
    }
    break :blk table;
};

pub fn lookup(kind: lexer.TokenKind) RoleRow {
    return rows[@intFromEnum(kind)];
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
    // `!=` and `~=` are two source spellings that both lex to the single
    // identity `.neq` (src/lexer.zig). Role lookup keys on that identity, so
    // whichever spelling produced the token, the role is one row: a nonassoc
    // comparison sharing the `.eq` role class. Holding identity fixed fixes the
    // role — spelling never reaches this table.
    const r = lookup(.neq);
    try std.testing.expect(isInfix(.neq));
    try std.testing.expectEqual(Associativity.nonassoc, r.assoc);
    try std.testing.expectEqual(lookup(.eq).precedence, r.precedence);
    try std.testing.expectEqual(lookup(.eq).assoc, r.assoc);
    try std.testing.expectEqualStrings("~=", lexer.TokenKind.neq.spelling());
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
    try std.testing.expectEqual(enum_info.field_names.len, rows.len);
    inline for (enum_info.field_values) |value| {
        const kind: lexer.TokenKind = @enumFromInt(value);
        try std.testing.expectEqual(kind, lookup(kind).kind);
    }
}
