//! Immutable grammar observation over the production token pack.
//!
//! Recognition demands token identity and source position. It does not demand
//! token text, integer/float payloads, or a copy of the host token record. Keep
//! that demand boundary explicit: widening this observation is a semantic and
//! physical cost, not a convenience accessor.
const lexer = @import("lexer.zig");

pub const View = struct {
    tokens: []const lexer.Token,

    pub inline fn kind(self: View, index: usize) ?lexer.TokenKind {
        if (index >= self.tokens.len) return null;
        return self.tokens[index].kind;
    }

    pub inline fn line(self: View, index: usize) ?u32 {
        if (index >= self.tokens.len) return null;
        return self.tokens[index].loc.line;
    }

    pub inline fn col(self: View, index: usize) ?u32 {
        if (index >= self.tokens.len) return null;
        return self.tokens[index].loc.col;
    }
};

pub fn fromTokens(tokens: []const lexer.Token) View {
    return .{ .tokens = tokens };
}
