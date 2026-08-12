//! GAP-134 — grammar-role facts keyed by TokenKind ordinal (never by spelling).
const std = @import("std");
const lexer = @import("lexer.zig");

pub const SCHEMA_VERSION = "grammar-role-v1";

pub const Associativity = enum(u8) {
    none = 0,
    left = 1,
    right = 2,
};

pub const RoleRow = struct {
    kind: lexer.TokenKind,
    begin_expr: bool = false,
    prefix: bool = false,
    postfix: bool = false,
    parameter: bool = false,
    literal_kind: bool = false,
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
            .name => row(kind, .{ .kind = kind, .begin_expr = true }),
            .int_lit, .float_lit => row(kind, .{ .kind = kind, .begin_expr = true, .literal_kind = true }),
            .text_lit => row(kind, .{ .kind = kind, .begin_expr = true, .literal_kind = true }),
            .bytes_lit => row(kind, .{ .kind = kind, .begin_expr = true, .literal_kind = true }),
            .compat_text_lit, .compat_long_text_lit => row(kind, .{ .kind = kind, .begin_expr = true, .compat_only = true, .literal_kind = true }),
            .string_lit => row(kind, .{ .kind = kind, .begin_expr = true, .compat_only = true, .literal_kind = true }),
            .kw_true, .kw_false, .kw_nil => row(kind, .{ .kind = kind, .begin_expr = true, .compat_only = true }),
            .lparen => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true }),
            .lbrace, .lbracket => row(kind, .{ .kind = kind, .begin_expr = true }),
            .kw_not, .bang => row(kind, .{ .kind = kind, .prefix = true, .precedence = 9 }),
            .dot => row(kind, .{ .kind = kind, .postfix = true, .precedence = 10 }),
            .star, .slash, .percent, .idiv => row(kind, .{ .kind = kind, .precedence = 6, .assoc = .left }),
            .plus => row(kind, .{ .kind = kind, .precedence = 5, .assoc = .left }),
            .minus => row(kind, .{ .kind = kind, .prefix = true, .precedence = 5, .assoc = .left }),
            .concat => row(kind, .{ .kind = kind, .precedence = 4, .assoc = .left, .compat_only = true }),
            .eq, .neq, .lt, .gt, .leq, .geq => row(kind, .{ .kind = kind, .precedence = 3, .assoc = .left }),
            .assign, .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign, .caret_assign => row(kind, .{ .kind = kind, .precedence = 1, .assoc = .right }),
            .colon => row(kind, .{ .kind = kind, .parameter = true }),
            .kw_fun, .kw_function, .kw_local, .kw_const, .kw_let => row(kind, .{ .kind = kind, .compat_only = true }),
            .backtick => row(kind, .{ .kind = kind, .begin_expr = false, .compat_only = true }),
            .hash, .hash_hash => row(kind, .{ .kind = kind, .compat_only = true }),
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
}

test "grammar roles: every token identity has one ordinal row" {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    try std.testing.expectEqual(enum_info.field_names.len, rows.len);
    inline for (enum_info.field_values) |value| {
        const kind: lexer.TokenKind = @enumFromInt(value);
        try std.testing.expectEqual(kind, lookup(kind).kind);
    }
}
