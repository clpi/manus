//! GAP-134 — transitional host grammar-role table (`law.grammar.one`).
//! Keyed by TokenKind ordinal, never by spelling. This file is a bridge
//! (`law.bridge.death`): destination is one Idol grammar-fact owner that
//! generates this table, `grammar.md`, and Tree-sitter. Do not treat this
//! as the permanent grammar authority. Parser BinOp maps remain debt.
const std = @import("std");
const lexer = @import("lexer.zig");

pub const SCHEMA_VERSION = "grammar-role-v2";

pub const Associativity = enum(u8) {
    none = 0,
    left = 1,
    right = 2,
    nonassoc = 3,
};

pub const Roles = packed struct(u16) {
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
    binary: bool = false,
    compat_only: bool = false,
    _: u4 = 0,
};

const RoleSpec = struct {
    /// Semantic identity occupying this physical producer slot. `null` means
    /// the ABI slot is deliberately empty and must never acquire grammar role.
    kind: ?lexer.TokenKind = null,
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
    binary: bool = false,
    precedence: i8 = 0,
    assoc: Associativity = .none,
    compat_only: bool = false,
};

pub const RoleRow = struct {
    kind: ?lexer.TokenKind = null,
    roles: Roles = .{},
    precedence: i8 = 0,
    assoc: Associativity = .none,
};

fn row(comptime k: lexer.TokenKind, r: RoleSpec) RoleRow {
    _ = k;
    return .{
        .kind = r.kind,
        .roles = .{
            .begin_expr = r.begin_expr,
            .prefix = r.prefix,
            .postfix = r.postfix,
            .parameter = r.parameter,
            .literal_kind = r.literal_kind,
            .projection = r.projection,
            .body_start = r.body_start,
            .quoted = r.quoted,
            .descriptor = r.descriptor,
            .pattern = r.pattern,
            .binary = r.binary,
            .compat_only = r.compat_only,
        },
        .precedence = r.precedence,
        .assoc = r.assoc,
    };
}

/// Physical producer-slot span. This is intentionally not the semantic token
/// identity count: producer slot 3 is empty, while live identities retain their
/// established backing values through 113.
pub const slot_count = blk: {
    const values = @typeInfo(lexer.TokenKind).@"enum".field_values;
    var max_value: usize = 0;
    for (values) |value| {
        max_value = @max(max_value, @as(usize, @intCast(value)));
    }
    break :blk max_value + 1;
};

/// Compact generated lookup table — one row per physical producer slot.
/// Semantic identities populate rows by backing value; the empty slot remains
/// the all-false row and cannot be constructed as `TokenKind`.
pub const rows = blk: {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    var table: [slot_count]RoleRow = @splat(.{});
    for (enum_info.field_values) |value| {
        const kind: lexer.TokenKind = @fromBackingInt(@intCast(value));
        table[@intCast(value)] = switch (kind) {
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
            .tilde => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .binary = true, .precedence = 9, .assoc = .left }),
            .hash => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .compat_only = true, .body_start = true }),
            .hash_hash => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .compat_only = true }),
            .kw_comptime, .kw_await => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true }),
            .comma => row(kind, .{ .kind = kind, .begin_expr = true }),
            .at => row(kind, .{ .kind = kind, .begin_expr = true, .precedence = 19, .assoc = .left, .body_start = true }),
            .dot => row(kind, .{ .kind = kind, .postfix = true, .projection = true, .precedence = 10 }),
            .colon => row(kind, .{ .kind = kind, .parameter = true, .projection = true }),
            .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64, .kw_f32, .kw_f64, .kw_bool, .kw_void, .kw_str => row(kind, .{ .kind = kind, .descriptor = true }),
            .star, .slash, .percent, .idiv => row(kind, .{ .kind = kind, .binary = true, .precedence = 19, .assoc = .left }),
            .plus => row(kind, .{ .kind = kind, .binary = true, .precedence = 17, .assoc = .left }),
            .minus => row(kind, .{ .kind = kind, .begin_expr = true, .prefix = true, .binary = true, .precedence = 17, .assoc = .left, .body_start = true, .pattern = true }),
            .concat => row(kind, .{ .kind = kind, .binary = true, .precedence = 16, .assoc = .right, .compat_only = true }),
            .eq, .neq, .lt, .gt, .leq, .geq, .kw_in => row(kind, .{ .kind = kind, .binary = true, .precedence = 6, .assoc = .nonassoc }),
            .kw_or => row(kind, .{ .kind = kind, .binary = true, .precedence = 2, .assoc = .left, .compat_only = true }),
            .kw_and => row(kind, .{ .kind = kind, .binary = true, .precedence = 4, .assoc = .left, .compat_only = true }),
            .pipe => row(kind, .{ .kind = kind, .binary = true, .precedence = 7, .assoc = .left, .body_start = true }),
            .amp => row(kind, .{ .kind = kind, .binary = true, .precedence = 11, .assoc = .left }),
            .lshift, .rshift => row(kind, .{ .kind = kind, .binary = true, .precedence = 13, .assoc = .left }),
            .caret => row(kind, .{ .kind = kind, .binary = true, .precedence = 23, .assoc = .right }),
            .pipe_gt => row(kind, .{ .kind = kind, .binary = true, .precedence = 1, .assoc = .left }),
            .assign, .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign, .caret_assign => row(kind, .{
                .kind = kind,
                .precedence = 1,
                .assoc = .right,
            }),
            // `return`, `break`, `continue` and `do` open a body exactly as
            // `if`/`while`/`for` do. Leaving `return` out made a relation whose
            // whole body is one `return` fail to be recognised as having a body
            // at all: `main: i64 = ()` over `return 7` fell through to the
            // module-top statement path and refused with `mod-top-stmt:ret`,
            // while the same body with any statement before the `return` was
            // fine. No control word is more of a statement than another.
            .kw_if, .kw_match, .kw_while, .kw_for, .kw_return, .kw_break, .kw_continue => row(kind, .{ .kind = kind, .body_start = true }),
            // THE BLOCK-DELIMITER FAMILY IS COMPAT-ONLY, and this row is the
            // authority that says so — not the formatter's private opinion of
            // it, and not `gate/design.sh`'s regex.
            //
            // `then`, `end`, `elseif` and `do` are Lua block punctuation. The
            // canonical face is OFFSIDE: a block is delimited by indentation,
            // `elseif` is `else(condition)`, and there is no terminator. That
            // was true of `gate/design.sh` (which convicts `end`), true of
            // `pretty.zig`'s canonical face (which refuses to emit any of
            // them), and NOT recorded here — so the two enforcers each carried
            // a private copy of one fact and `compat_only` had zero consumers
            // (HPLS §7/§8 scenery). `pretty.zig` now reads this row.
            //
            // ONLY `compat_only` MOVES. `body_start` is read by the PARSER and
            // is what lets `do` open a block; taking it away would change what
            // the language accepts, which is a different question from what
            // canonical tooling may WRITE (HPLS §94).
            .kw_do => row(kind, .{ .kind = kind, .body_start = true, .compat_only = true }),
            .kw_then, .kw_end, .kw_elseif => row(kind, .{ .kind = kind, .compat_only = true }),
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

fn hashByte(hash: *u64, byte: u8) void {
    hash.* = (hash.* ^ byte) *% 1099511628211;
}

fn hashText(hash: *u64, value: []const u8) void {
    for (value) |byte| hashByte(hash, byte);
    hashByte(hash, 0);
}

/// Host-layout-independent digest of the semantic role rows. Text projections
/// carry this value; they never hash Zig struct bytes or source spelling.
pub const AUTHORITY: u64 = blk: {
    @setEvalBranchQuota(100_000);
    var hash: u64 = 14695981039346656037;
    hashText(&hash, SCHEMA_VERSION);
    for (rows, 0..) |role, slot| {
        hashByte(&hash, @truncate(slot));
        hashByte(&hash, @truncate(slot >> 8));
        if (role.kind) |kind| {
            hashText(&hash, @tagName(kind));
            hashText(&hash, kind.spelling());
        } else {
            hashText(&hash, "-");
            hashText(&hash, "-");
        }
        hashByte(&hash, @intFromBool(role.roles.begin_expr));
        hashByte(&hash, @intFromBool(role.roles.prefix));
        hashByte(&hash, @intFromBool(role.roles.postfix));
        hashByte(&hash, @intFromBool(role.roles.parameter));
        hashByte(&hash, @intFromBool(role.roles.literal_kind));
        hashByte(&hash, @intFromBool(role.roles.quoted));
        hashByte(&hash, @intFromBool(role.roles.projection));
        hashByte(&hash, @intFromBool(role.roles.body_start));
        hashByte(&hash, @intFromBool(role.roles.descriptor));
        hashByte(&hash, @intFromBool(role.roles.pattern));
        hashByte(&hash, @intFromBool(role.roles.binary));
        hashByte(&hash, @bitCast(role.precedence));
        hashByte(&hash, @backingInt(role.assoc));
        hashByte(&hash, @intFromBool(role.roles.compat_only));
    }
    break :blk hash;
};

pub fn lookup(kind: lexer.TokenKind) RoleRow {
    return rows[@backingInt(kind)];
}

pub fn canBeginExpression(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.begin_expr;
}

/// Literal tokens that may appear as call operands but never in a parameter list.
pub fn isLiteralKind(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.literal_kind;
}

/// Quoted payload identities (text/bytes/compat). Slot 3 is unpublished.
pub fn isQuotedKind(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.quoted;
}

/// Binary/assignment operators that disqualify a paren group from being a param list.
/// Infix operator identity — associativity is the fact, not token text.
pub fn isInfix(kind: lexer.TokenKind) bool {
    return lookup(kind).assoc != .none;
}

/// Ordinary binary-expression production membership. Assignment and current-
/// world qualification carry binding power but are different grammar roles.
pub fn isBinary(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.binary;
}

pub fn canStartBody(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.body_start;
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
    return !lookup(kind).roles.compat_only;
}

/// Primitive descriptor identities (`i64`, `str`, …) — not a spelling list.
pub fn isDescriptor(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.descriptor;
}

/// Match-pattern start — generated fact, not a parser kind list.
pub fn canStartPattern(kind: lexer.TokenKind) bool {
    return lookup(kind).roles.pattern;
}

test "grammar roles: identity not spelling drives prefix on dot" {
    try std.testing.expect(lookup(.dot).roles.postfix);
    try std.testing.expect(!lookup(.dot).roles.prefix);
}

test "grammar roles: backtick is compat-only and not expression-start" {
    const r = lookup(.backtick);
    try std.testing.expect(r.roles.compat_only);
    try std.testing.expect(!r.roles.begin_expr);
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
    try std.testing.expect(lookup(.compat_comment).roles.compat_only);
    try std.testing.expect(!lookup(.shebang).roles.compat_only);
}

test "grammar roles: long text is a literal body start by identity" {
    try std.testing.expect(isLiteralKind(.compat_long_text_lit));
    try std.testing.expect(canStartBody(.compat_long_text_lit));
    try std.testing.expect(canStartBody(.text_lit));
    try std.testing.expect(canStartBody(.bytes_lit));
}

test "grammar roles: prefix operators begin expressions by identity" {
    try std.testing.expect(lookup(.hash).roles.prefix);
    try std.testing.expect(lookup(.minus).roles.prefix);
    try std.testing.expect(lookup(.bang).roles.prefix);
    try std.testing.expect(!lookup(.plus).roles.prefix);
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
    try std.testing.expect(lookup(.hash).roles.prefix);
    try std.testing.expect(!canBeginExpression(.comment));
    try std.testing.expect(!canBeginExpression(.shebang));
    try std.testing.expect(!lookup(.comment).roles.prefix);
}

test "grammar roles: canonical and compatibility faces stay distinct" {
    // Shared structural role (literal, comment trivia, infix), distinct
    // canonical vs compatibility identity via the compat_only fact.
    try std.testing.expect(!lookup(.text_lit).roles.compat_only);
    try std.testing.expect(lookup(.compat_text_lit).roles.compat_only);
    try std.testing.expect(lookup(.text_lit).roles.quoted and lookup(.compat_text_lit).roles.quoted);

    try std.testing.expect(!lookup(.comment).roles.compat_only);
    try std.testing.expect(lookup(.compat_comment).roles.compat_only);

    try std.testing.expect(isInfix(.pipe) and !lookup(.pipe).roles.compat_only);
    try std.testing.expect(isInfix(.kw_or) and lookup(.kw_or).roles.compat_only);
    try std.testing.expect(isInfix(.amp) and !lookup(.amp).roles.compat_only);
    try std.testing.expect(isInfix(.kw_and) and lookup(.kw_and).roles.compat_only);
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
    try std.testing.expect(!rows[3].roles.begin_expr);
    try std.testing.expect(!rows[3].roles.literal_kind);
    try std.testing.expect(!rows[3].roles.quoted);
}

test "grammar roles: binary production is explicit and excludes other infix roles" {
    try std.testing.expect(isBinary(.plus));
    try std.testing.expect(isBinary(.neq));
    try std.testing.expect(isBinary(.pipe_gt));
    try std.testing.expect(!isBinary(.assign));
    try std.testing.expect(!isBinary(.at));
    try std.testing.expect(!isBinary(.dot));
}
