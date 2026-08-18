//! Immutable observation view over a production token pack (GAP-134 prerequisite).
const std = @import("std");
const lexer = @import("lexer.zig");
const grammar_roles = @import("grammar_roles.zig");
const lexer_dispatch = @import("lexer_dispatch.zig");
const lexer_bridge = @import("lexer_bridge.zig");

pub const View = struct {
    tokens: []const lexer.Token,

    pub fn len(self: View) usize {
        return self.tokens.len;
    }

    pub fn at(self: View, index: usize) ?lexer.Token {
        if (index >= self.tokens.len) return null;
        return self.tokens[index];
    }

    pub fn peek(self: View, index: usize) ?lexer.Token {
        return self.at(index);
    }

    pub fn kind(self: View, index: usize) ?lexer.TokenKind {
        const tok = self.at(index) orelse return null;
        return tok.kind;
    }

    pub fn canBeginExpression(self: View, index: usize) bool {
        const k = self.kind(index) orelse return false;
        return grammar_roles.canBeginExpression(k);
    }

    pub fn canStartPattern(self: View, index: usize) bool {
        const k = self.kind(index) orelse return false;
        return grammar_roles.canStartPattern(k);
    }

    pub fn role(self: View, index: usize) ?grammar_roles.RoleRow {
        const k = self.kind(index) orelse return null;
        return grammar_roles.lookup(k);
    }
};

pub fn fromTokens(tokens: []const lexer.Token) View {
    return .{ .tokens = tokens };
}

pub fn fromDispatch(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    family: i64,
) !View {
    const tokens = try lexer_dispatch.tokenize(allocator, src, file, family);
    return .{ .tokens = tokens };
}

test "token view: peek is observation without cursor mutation" {
    const src = "\"a\" 1";
    var lex = lexer.Lexer.init(src, "probe.id");
    var toks: [4]lexer.Token = undefined;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        toks[i] = try lex.next();
        if (toks[i].kind == .eof) break;
    }
    const view = fromTokens(toks[0..i]);
    try std.testing.expectEqual(.text_lit, view.kind(0));
    try std.testing.expect(view.canBeginExpression(0));
    try std.testing.expect(!view.role(0).?.roles.compat_only);
}

test "token view: identity change affects role not spelling" {
    try std.testing.expect(grammar_roles.canBeginExpression(.text_lit));
    try std.testing.expect(grammar_roles.canBeginExpression(.bytes_lit));
    try std.testing.expect(!std.mem.eql(u8, @tagName(lexer.TokenKind.text_lit), @tagName(lexer.TokenKind.bytes_lit)));
}

test "token view: trivia identities are not expression starts" {
    try std.testing.expect(!grammar_roles.canBeginExpression(.shebang));
    try std.testing.expect(!grammar_roles.canBeginExpression(.comment));
    try std.testing.expect(grammar_roles.canStartBody(.text_lit));
    try std.testing.expect(grammar_roles.isLiteralKind(.compat_long_text_lit));
}

test "token view: pattern start is a generated role" {
    try std.testing.expect(grammar_roles.canStartPattern(.name));
    try std.testing.expect(grammar_roles.canStartPattern(.lbrace));
    try std.testing.expect(!grammar_roles.canStartPattern(.kw_if));
}

test "token view: fromDispatch takes family not suffix" {
    const a = std.testing.allocator;
    const src: [:0]const u8 = "x = 'a'";
    const view = try fromDispatch(a, src, "x.lua", lexer_bridge.family_canon);
    defer a.free(view.tokens);
    try std.testing.expectEqual(.bytes_lit, view.kind(2));
}
