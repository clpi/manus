const std = @import("std");

pub const Loc = struct {
    file: []const u8,
    line: u32,
    col: u32,

    pub fn format(self: Loc, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{s}:{}:{}", .{ self.file, self.line, self.col });
    }
};

pub const TokenKind = enum {
    // Literals
    name,
    int_lit,
    float_lit,
    string_lit,

    // Lua keywords
    kw_and, kw_break, kw_do, kw_else, kw_elseif,
    kw_end, kw_false, kw_for, kw_function, kw_goto,
    kw_if, kw_in, kw_local, kw_nil, kw_not,
    kw_or, kw_repeat, kw_return, kw_then, kw_true,
    kw_until, kw_while,

    // Duo type keywords
    kw_const, kw_struct, kw_enum,
    kw_i8, kw_i16, kw_i32, kw_i64,
    kw_u8, kw_u16, kw_u32, kw_u64,
    kw_f32, kw_f64, kw_bool, kw_void, kw_str,

    // Single-char punctuation
    lparen, rparen,
    lbracket, rbracket,
    lbrace, rbrace,
    plus, minus, star, slash, percent, caret, hash,
    amp, pipe, lt, gt, assign, tilde,
    semi, colon, comma, dot,

    // Multi-char operators
    concat, // ..
    dots, // ...
    eq, // ==
    neq, // ~=
    leq, // <=
    geq, // >=
    lshift, // <<
    rshift, // >>
    idiv, // //
    dcolon, // ::
    arrow, // ->

    eof,

    pub fn spelling(self: TokenKind) []const u8 {
        return switch (self) {
            .name => "name",
            .int_lit => "integer",
            .float_lit => "float",
            .string_lit => "string",
            .kw_and => "and",
            .kw_break => "break",
            .kw_do => "do",
            .kw_else => "else",
            .kw_elseif => "elseif",
            .kw_end => "end",
            .kw_false => "false",
            .kw_for => "for",
            .kw_function => "function",
            .kw_goto => "goto",
            .kw_if => "if",
            .kw_in => "in",
            .kw_local => "local",
            .kw_nil => "nil",
            .kw_not => "not",
            .kw_or => "or",
            .kw_repeat => "repeat",
            .kw_return => "return",
            .kw_then => "then",
            .kw_true => "true",
            .kw_until => "until",
            .kw_while => "while",
            .kw_const => "const",
            .kw_struct => "struct",
            .kw_enum => "enum",
            .kw_i8 => "i8",
            .kw_i16 => "i16",
            .kw_i32 => "i32",
            .kw_i64 => "i64",
            .kw_u8 => "u8",
            .kw_u16 => "u16",
            .kw_u32 => "u32",
            .kw_u64 => "u64",
            .kw_f32 => "f32",
            .kw_f64 => "f64",
            .kw_bool => "bool",
            .kw_void => "void",
            .kw_str => "str",
            .lparen => "(",
            .rparen => ")",
            .lbracket => "[",
            .rbracket => "]",
            .lbrace => "{",
            .rbrace => "}",
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .caret => "^",
            .hash => "#",
            .amp => "&",
            .pipe => "|",
            .lt => "<",
            .gt => ">",
            .assign => "=",
            .tilde => "~",
            .semi => ";",
            .colon => ":",
            .comma => ",",
            .dot => ".",
            .concat => "..",
            .dots => "...",
            .eq => "==",
            .neq => "~=",
            .leq => "<=",
            .geq => ">=",
            .lshift => "<<",
            .rshift => ">>",
            .idiv => "//",
            .dcolon => "::",
            .arrow => "->",
            .eof => "<eof>",
        };
    }
};

pub const Token = struct {
    kind: TokenKind,
    loc: Loc,
    text: []const u8,
    int_val: i64 = 0,
    float_val: f64 = 0.0,
};

pub const LexError = error{
    UnterminatedString,
    UnterminatedLongString,
    InvalidNumber,
    UnexpectedChar,
};

pub const Lexer = struct {
    src: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    file: []const u8,
    peeked: ?Token,

    pub fn init(src: []const u8, file: []const u8) Lexer {
        return .{
            .src = src,
            .pos = 0,
            .line = 1,
            .col = 1,
            .file = file,
            .peeked = null,
        };
    }

    fn cur_loc(self: *Lexer) Loc {
        return .{ .file = self.file, .line = self.line, .col = self.col };
    }

    fn peek_char(self: *Lexer) u8 {
        if (self.pos >= self.src.len) return 0;
        return self.src[self.pos];
    }

    fn peek_char2(self: *Lexer) u8 {
        if (self.pos + 1 >= self.src.len) return 0;
        return self.src[self.pos + 1];
    }

    fn adv(self: *Lexer) u8 {
        if (self.pos >= self.src.len) return 0;
        const c = self.src[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn skip_ws(self: *Lexer) LexError!void {
        while (self.pos < self.src.len) {
            const c = self.peek_char();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                _ = self.adv();
            } else if (c == '-' and self.peek_char2() == '-') {
                self.pos += 2;
                self.col += 2;
                const level = self.long_bracket_level();
                if (level >= 0) {
                    try self.skip_long(@intCast(level));
                } else {
                    while (self.pos < self.src.len and self.peek_char() != '\n')
                        _ = self.adv();
                }
            } else break;
        }
    }

    fn long_bracket_level(self: *Lexer) i32 {
        var i = self.pos;
        if (i >= self.src.len or self.src[i] != '[') return -1;
        i += 1;
        var lvl: i32 = 0;
        while (i < self.src.len and self.src[i] == '=') {
            lvl += 1;
            i += 1;
        }
        if (i >= self.src.len or self.src[i] != '[') return -1;
        return lvl;
    }

    fn skip_long(self: *Lexer, level: u32) LexError!void {
        // consume [=..=[
        _ = self.adv();
        var i: u32 = 0;
        while (i < level) : (i += 1) _ = self.adv();
        _ = self.adv();

        while (self.pos < self.src.len) {
            if (self.adv() == ']') {
                var eq: u32 = 0;
                while (self.peek_char() == '=') {
                    _ = self.adv();
                    eq += 1;
                }
                if (eq == level and self.peek_char() == ']') {
                    _ = self.adv();
                    return;
                }
            }
        }
        return LexError.UnterminatedLongString;
    }

    fn read_long_str(self: *Lexer, level: u32) LexError![]const u8 {
        // consume [=..=[
        _ = self.adv();
        var i: u32 = 0;
        while (i < level) : (i += 1) _ = self.adv();
        _ = self.adv();
        // skip optional leading newline
        if (self.peek_char() == '\n') _ = self.adv() else if (self.peek_char() == '\r') {
            _ = self.adv();
            if (self.peek_char() == '\n') _ = self.adv();
        }
        const start = self.pos;
        while (self.pos < self.src.len) {
            if (self.adv() == ']') {
                var eq: u32 = 0;
                const eq_start = self.pos;
                while (self.peek_char() == '=') {
                    _ = self.adv();
                    eq += 1;
                }
                if (eq == level and self.peek_char() == ']') {
                    const content = self.src[start .. eq_start - 1];
                    _ = self.adv();
                    return content;
                }
            }
        }
        return LexError.UnterminatedLongString;
    }

    fn read_str(self: *Lexer, quote: u8) LexError![]const u8 {
        _ = self.adv(); // opening quote
        const start = self.pos;
        while (self.pos < self.src.len) {
            const c = self.peek_char();
            if (c == quote) {
                const s = self.src[start..self.pos];
                _ = self.adv();
                return s;
            }
            if (c == '\n' or c == '\r') return LexError.UnterminatedString;
            if (c == '\\') {
                _ = self.adv();
                if (self.pos < self.src.len) _ = self.adv();
            } else {
                _ = self.adv();
            }
        }
        return LexError.UnterminatedString;
    }

    fn read_num(self: *Lexer) LexError!Token {
        const l = self.cur_loc();
        const start = self.pos;
        var is_float = false;

        if (self.peek_char() == '0' and (self.peek_char2() == 'x' or self.peek_char2() == 'X')) {
            _ = self.adv();
            _ = self.adv();
            while (std.ascii.isHex(self.peek_char())) _ = self.adv();
            if (self.peek_char() == '.') {
                is_float = true;
                _ = self.adv();
                while (std.ascii.isHex(self.peek_char())) _ = self.adv();
            }
            if (self.peek_char() == 'p' or self.peek_char() == 'P') {
                is_float = true;
                _ = self.adv();
                if (self.peek_char() == '+' or self.peek_char() == '-') _ = self.adv();
                while (std.ascii.isDigit(self.peek_char())) _ = self.adv();
            }
        } else {
            while (std.ascii.isDigit(self.peek_char())) _ = self.adv();
            if (self.peek_char() == '.') {
                const n = self.peek_char2();
                if (std.ascii.isDigit(n)) {
                    is_float = true;
                    _ = self.adv();
                    while (std.ascii.isDigit(self.peek_char())) _ = self.adv();
                }
            }
            if (self.peek_char() == 'e' or self.peek_char() == 'E') {
                is_float = true;
                _ = self.adv();
                if (self.peek_char() == '+' or self.peek_char() == '-') _ = self.adv();
                while (std.ascii.isDigit(self.peek_char())) _ = self.adv();
            }
        }

        const text = self.src[start..self.pos];
        if (is_float) {
            const v = std.fmt.parseFloat(f64, text) catch return LexError.InvalidNumber;
            return Token{ .kind = .float_lit, .loc = l, .text = text, .float_val = v };
        } else {
            const v = if (text.len > 2 and (text[1] == 'x' or text[1] == 'X'))
                std.fmt.parseInt(i64, text[2..], 16) catch return LexError.InvalidNumber
            else
                std.fmt.parseInt(i64, text, 10) catch return LexError.InvalidNumber;
            return Token{ .kind = .int_lit, .loc = l, .text = text, .int_val = v };
        }
    }

    fn lookup_kw(text: []const u8) ?TokenKind {
        // Parallel arrays: word list and corresponding token kind.
        const words = [_][]const u8{
            "and", "break", "do", "else", "elseif", "end",
            "false", "for", "function", "goto", "if", "in",
            "local", "nil", "not", "or", "repeat", "return",
            "then", "true", "until", "while",
            "const", "struct", "enum",
            "i8", "i16", "i32", "i64",
            "u8",  "u16", "u32", "u64",
            "f32", "f64", "bool", "void", "str",
        };
        const kinds = [_]TokenKind{
            .kw_and, .kw_break, .kw_do, .kw_else, .kw_elseif, .kw_end,
            .kw_false, .kw_for, .kw_function, .kw_goto, .kw_if, .kw_in,
            .kw_local, .kw_nil, .kw_not, .kw_or, .kw_repeat, .kw_return,
            .kw_then, .kw_true, .kw_until, .kw_while,
            .kw_const, .kw_struct, .kw_enum,
            .kw_i8, .kw_i16, .kw_i32, .kw_i64,
            .kw_u8,  .kw_u16, .kw_u32, .kw_u64,
            .kw_f32, .kw_f64, .kw_bool, .kw_void, .kw_str,
        };
        for (words, kinds) |w, k| if (std.mem.eql(u8, text, w)) return k;
        return null;
    }

    fn next_tok(self: *Lexer) LexError!Token {
        try self.skip_ws();
        if (self.pos >= self.src.len)
            return Token{ .kind = .eof, .loc = self.cur_loc(), .text = "" };

        const l = self.cur_loc();
        const c = self.peek_char();

        // Numbers
        if (std.ascii.isDigit(c) or (c == '.' and std.ascii.isDigit(self.peek_char2())))
            return self.read_num();

        // Identifiers / keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = self.pos;
            while (self.pos < self.src.len and
                (std.ascii.isAlphanumeric(self.peek_char()) or self.peek_char() == '_'))
                _ = self.adv();
            const text = self.src[start..self.pos];
            const kind = lookup_kw(text) orelse .name;
            return Token{ .kind = kind, .loc = l, .text = text };
        }

        // Strings
        if (c == '\'' or c == '"') {
            const s = try self.read_str(c);
            return Token{ .kind = .string_lit, .loc = l, .text = s };
        }

        // Long strings
        if (c == '[') {
            const lvl = self.long_bracket_level();
            if (lvl >= 0) {
                const s = try self.read_long_str(@intCast(lvl));
                return Token{ .kind = .string_lit, .loc = l, .text = s };
            }
        }

        _ = self.adv();
        const p = self.pos;
        return switch (c) {
            '+' => Token{ .kind = .plus, .loc = l, .text = self.src[p - 1 .. p] },
            '*' => Token{ .kind = .star, .loc = l, .text = self.src[p - 1 .. p] },
            '%' => Token{ .kind = .percent, .loc = l, .text = self.src[p - 1 .. p] },
            '^' => Token{ .kind = .caret, .loc = l, .text = self.src[p - 1 .. p] },
            '#' => Token{ .kind = .hash, .loc = l, .text = self.src[p - 1 .. p] },
            '&' => Token{ .kind = .amp, .loc = l, .text = self.src[p - 1 .. p] },
            '|' => Token{ .kind = .pipe, .loc = l, .text = self.src[p - 1 .. p] },
            '(' => Token{ .kind = .lparen, .loc = l, .text = self.src[p - 1 .. p] },
            ')' => Token{ .kind = .rparen, .loc = l, .text = self.src[p - 1 .. p] },
            '[' => Token{ .kind = .lbracket, .loc = l, .text = self.src[p - 1 .. p] },
            ']' => Token{ .kind = .rbracket, .loc = l, .text = self.src[p - 1 .. p] },
            '{' => Token{ .kind = .lbrace, .loc = l, .text = self.src[p - 1 .. p] },
            '}' => Token{ .kind = .rbrace, .loc = l, .text = self.src[p - 1 .. p] },
            ';' => Token{ .kind = .semi, .loc = l, .text = self.src[p - 1 .. p] },
            ',' => Token{ .kind = .comma, .loc = l, .text = self.src[p - 1 .. p] },
            '-' => if (self.peek_char() == '>') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .arrow, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .minus, .loc = l, .text = self.src[p - 1 .. p] },
            '/' => if (self.peek_char() == '/') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .idiv, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .slash, .loc = l, .text = self.src[p - 1 .. p] },
            '.' => if (self.peek_char() == '.') blk: {
                _ = self.adv();
                if (self.peek_char() == '.') {
                    _ = self.adv();
                    break :blk Token{ .kind = .dots, .loc = l, .text = self.src[p - 1 .. self.pos] };
                }
                break :blk Token{ .kind = .concat, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .dot, .loc = l, .text = self.src[p - 1 .. p] },
            '=' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .eq, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .assign, .loc = l, .text = self.src[p - 1 .. p] },
            '~' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .neq, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .tilde, .loc = l, .text = self.src[p - 1 .. p] },
            '<' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .leq, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else if (self.peek_char() == '<') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .lshift, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .lt, .loc = l, .text = self.src[p - 1 .. p] },
            '>' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .geq, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else if (self.peek_char() == '>') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .rshift, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .gt, .loc = l, .text = self.src[p - 1 .. p] },
            ':' => if (self.peek_char() == ':') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .dcolon, .loc = l, .text = self.src[p - 1 .. self.pos] };
            } else Token{ .kind = .colon, .loc = l, .text = self.src[p - 1 .. p] },
            else => LexError.UnexpectedChar,
        };
    }

    pub fn next(self: *Lexer) LexError!Token {
        if (self.peeked) |tok| {
            self.peeked = null;
            return tok;
        }
        return self.next_tok();
    }

    pub fn peek(self: *Lexer) LexError!Token {
        if (self.peeked == null) self.peeked = try self.next_tok();
        return self.peeked.?;
    }
};
