const std = @import("std");
const source_cursor = @import("source_cursor.zig");

pub const Loc = source_cursor.Loc;

pub const TokenKind = enum {
    // Literals
    name,
    int_lit,
    float_lit,
    string_lit,

    // Lua keywords
    kw_and,
    kw_break,
    kw_continue,
    kw_do,
    kw_else,
    kw_elseif,
    kw_end,
    kw_false,
    kw_for,
    kw_function,
    kw_fun,
    kw_global,
    kw_goto,
    kw_if,
    kw_in,
    kw_local,
    kw_nil,
    kw_not,
    kw_or,
    kw_repeat,
    kw_return,
    kw_then,
    kw_true,
    kw_until,
    kw_while,

    // Duo type keywords
    kw_const,
    kw_enum,
    kw_i8,
    kw_i16,
    kw_i32,
    kw_i64,
    kw_u8,
    kw_u16,
    kw_u32,
    kw_u64,
    kw_f32,
    kw_f64,
    kw_bool,
    kw_void,
    kw_str,

    // Duo contextual keywords
    kw_match,
    kw_try,
    kw_catch,
    kw_defer,
    kw_async,
    kw_await,
    kw_concept,
    kw_alias,
    kw_private,
    kw_extends,
    kw_macro,
    kw_comptime,
    kw_by,
    kw_let,

    // Single-char punctuation
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    plus,
    minus,
    star,
    slash,
    percent,
    caret,
    hash,
    amp,
    pipe,
    lt,
    gt,
    assign,
    tilde,
    semi,
    colon,
    comma,
    dot,
    at, // @
    question, // ?
    bang, // !
    backtick, // `

    // Multi-char operators
    concat, // ..
    dots, // ...
    hash_hash, // ##
    eq, // ==
    neq, // ~=
    leq, // <=
    geq, // >=
    lshift, // <<
    rshift, // >>
    idiv, // //
    dcolon, // ::
    arrow, // ->
    pipe_gt, // |>
    fat_arrow, // =>
    plus_assign, // +=
    minus_assign, // -=
    star_assign, // *=
    slash_assign, // /=
    percent_assign, // %=
    caret_assign, // ^=

    eof,

    pub fn spelling(self: TokenKind) []const u8 {
        return switch (self) {
            .name => "name",
            .int_lit => "integer",
            .float_lit => "float",
            .string_lit => "string",
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
            .at => "@",
            .question => "?",
            .bang => "!",
            .backtick => "`",
            .concat => "..",
            .dots => "...",
            .hash_hash => "##",
            .eq => "==",
            .neq => "~=",
            .leq => "<=",
            .geq => ">=",
            .lshift => "<<",
            .rshift => ">>",
            .idiv => "//",
            .dcolon => "::",
            .arrow => "->",
            .pipe_gt => "|>",
            .fat_arrow => "=>",
            .plus_assign => "+=",
            .minus_assign => "-=",
            .star_assign => "*=",
            .slash_assign => "/=",
            .percent_assign => "%=",
            .caret_assign => "^=",
            .eof => "<eof>",
            else => blk: {
                const entry = @import("token_semantic.zig").entryForKind(self) orelse unreachable;
                break :blk entry.text;
            },
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
    InvalidEscape,
    OutOfMemory,
};

pub const Lexer = struct {
    cursor: source_cursor.ProductionCursor,
    peeked: ?Token,
    last_error_loc: ?Loc,
    /// Compiler hint directives accumulated from `--- @hint` comments.
    /// Consumed by the parser when it encounters the next function declaration.
    pending_hints: [8]?[]const u8 = .{ null, null, null, null, null, null, null, null },
    pending_hint_count: u8 = 0,

    pub fn init(src: []const u8, file: []const u8) Lexer {
        return .{
            .cursor = source_cursor.ProductionCursor.init(src, file),
            .peeked = null,
            .last_error_loc = null,
        };
    }

    fn cur_loc(self: *Lexer) Loc {
        return self.cursor.loc();
    }

    /// Consume pending compiler hints (from `--- @hint` comments).
    /// Returns the count of consumed hints and fills the output slice.
    pub fn consumeHints(self: *Lexer, out: []?[]const u8) u8 {
        const count = self.pending_hint_count;
        var i: u8 = 0;
        while (i < count and i < out.len) : (i += 1) {
            out[i] = self.pending_hints[i];
        }
        self.pending_hint_count = 0;
        self.pending_hints = .{ null, null, null, null, null, null, null, null };
        return count;
    }

    /// Check if there are pending compiler hints.
    pub fn hasPendingHints(self: *const Lexer) bool {
        return self.pending_hint_count > 0;
    }

    fn peek_char(self: *Lexer) u8 {
        return self.cursor.peek();
    }

    fn peek_char2(self: *Lexer) u8 {
        return self.cursor.peek2();
    }

    fn adv(self: *Lexer) u8 {
        return self.cursor.advance();
    }

    fn skip_ws(self: *Lexer) LexError!void {
        while (self.cursor.index < self.cursor.bytes.len) {
            const c = self.peek_char();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                _ = self.adv();
            } else if (c == '#' and self.peek_char2() == '!' and self.cursor.index == 0) {
                while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '\n')
                    _ = self.adv();
            } else if (c == '-' and self.peek_char2() == '-') {
                self.cursor.bumpCol(2);
                const level = self.long_bracket_level();
                if (level >= 0) {
                    try self.skip_long(@intCast(level));
                } else {
                    // Check for triple-dash hint comment: --- @directive
                    const is_triple_dash = self.cursor.index < self.cursor.bytes.len and self.peek_char() == '-';
                    if (is_triple_dash) {
                        _ = self.adv(); // consume third '-'
                    }
                    const comment_start = self.cursor.index;
                    while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '\n')
                        _ = self.adv();
                    // If triple-dash, check for @hint pattern
                    if (is_triple_dash) {
                        const comment_text = self.cursor.bytes[comment_start..self.cursor.index];
                        const trimmed = std.mem.trim(u8, comment_text, " \t");
                        if (trimmed.len > 0 and trimmed[0] == '@' and self.pending_hint_count < 8) {
                            self.pending_hints[self.pending_hint_count] = trimmed[1..]; // strip '@'
                            self.pending_hint_count += 1;
                        }
                    }
                }
            } else break;
        }
    }

    fn long_bracket_level(self: *Lexer) i32 {
        var i = self.cursor.index;
        if (i >= self.cursor.bytes.len or self.cursor.bytes[i] != '[') return -1;
        i += 1;
        var lvl: i32 = 0;
        while (i < self.cursor.bytes.len and self.cursor.bytes[i] == '=') {
            lvl += 1;
            i += 1;
        }
        if (i >= self.cursor.bytes.len or self.cursor.bytes[i] != '[') return -1;
        return lvl;
    }

    fn skip_long(self: *Lexer, level: u32) LexError!void {
        // consume [=..=[
        _ = self.adv();
        var i: u32 = 0;
        while (i < level) : (i += 1) _ = self.adv();
        _ = self.adv();

        while (self.cursor.index < self.cursor.bytes.len) {
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
        const start = self.cursor.index;
        while (self.cursor.index < self.cursor.bytes.len) {
            if (self.peek_char() == ']') {
                const close_start = self.cursor.index;
                _ = self.adv();
                var eq: u32 = 0;
                while (self.peek_char() == '=') {
                    _ = self.adv();
                    eq += 1;
                }
                if (eq == level and self.peek_char() == ']') {
                    const content = self.cursor.bytes[start..close_start];
                    _ = self.adv();
                    return content;
                }
            } else {
                _ = self.adv();
            }
        }
        return LexError.UnterminatedLongString;
    }

    fn read_str(self: *Lexer, quote: u8) LexError![]const u8 {
        _ = self.adv(); // opening quote
        const start = self.cursor.index;
        while (self.cursor.index < self.cursor.bytes.len) {
            const c = self.peek_char();
            if (c == quote) {
                const s = self.cursor.bytes[start..self.cursor.index];
                _ = self.adv();
                return s;
            }
            if (c == '\n' or c == '\r') return LexError.UnterminatedString;
            if (c == '\\') {
                _ = self.adv();
                if (self.cursor.index >= self.cursor.bytes.len) return LexError.UnterminatedString;
                const esc = self.peek_char();
                if (esc == 'x') {
                    _ = self.adv();
                    if (self.cursor.index >= self.cursor.bytes.len or !std.ascii.isHex(self.peek_char()))
                        return LexError.InvalidEscape;
                    _ = self.adv();
                    if (self.cursor.index < self.cursor.bytes.len and std.ascii.isHex(self.peek_char())) _ = self.adv();
                } else if (esc == 'u') {
                    _ = self.adv();
                    if (self.peek_char() != '{') return LexError.InvalidEscape;
                    _ = self.adv();
                    var has_digit = false;
                    while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '}') {
                        if (!std.ascii.isHex(self.peek_char())) return LexError.InvalidEscape;
                        has_digit = true;
                        _ = self.adv();
                    }
                    if (!has_digit or self.cursor.index >= self.cursor.bytes.len or self.peek_char() != '}')
                        return LexError.InvalidEscape;
                    _ = self.adv();
                } else if (esc == 'z') {
                    _ = self.adv();
                    while (self.cursor.index < self.cursor.bytes.len) {
                        const ws = self.peek_char();
                        if (ws == ' ' or ws == '\t' or ws == '\r' or ws == '\n') {
                            _ = self.adv();
                        } else break;
                    }
                } else if (esc == '\r') {
                    _ = self.adv();
                    if (self.cursor.index < self.cursor.bytes.len and self.peek_char() == '\n') _ = self.adv();
                } else {
                    _ = self.adv();
                }
            } else {
                _ = self.adv();
            }
        }
        return LexError.UnterminatedString;
    }

    /// Decode a short Lua string literal body (between quotes, escapes intact).
    pub fn decode_lua_short_string(alloc: std.mem.Allocator, raw: []const u8) LexError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(alloc);
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] != '\\') {
                try out.append(alloc, raw[i]);
                i += 1;
                continue;
            }
            i += 1;
            if (i >= raw.len) return LexError.InvalidEscape;
            switch (raw[i]) {
                'a' => {
                    try out.append(alloc, 7);
                    i += 1;
                },
                'b' => {
                    try out.append(alloc, 8);
                    i += 1;
                },
                'f' => {
                    try out.append(alloc, 12);
                    i += 1;
                },
                'n' => {
                    try out.append(alloc, '\n');
                    i += 1;
                },
                'r' => {
                    try out.append(alloc, '\r');
                    i += 1;
                },
                't' => {
                    try out.append(alloc, '\t');
                    i += 1;
                },
                'v' => {
                    try out.append(alloc, 11);
                    i += 1;
                },
                '\\', '"', '\'' => {
                    try out.append(alloc, raw[i]);
                    i += 1;
                },
                'z' => {
                    i += 1;
                    while (i < raw.len) {
                        const ws = raw[i];
                        if (ws == ' ' or ws == '\t' or ws == '\r' or ws == '\n') {
                            i += 1;
                        } else break;
                    }
                },
                'x' => {
                    i += 1;
                    if (i >= raw.len or !std.ascii.isHex(raw[i])) return LexError.InvalidEscape;
                    var byte: u8 = std.fmt.parseInt(u8, raw[i .. i + 1], 16) catch return LexError.InvalidEscape;
                    i += 1;
                    if (i < raw.len and std.ascii.isHex(raw[i])) {
                        byte = (byte << 4) | (std.fmt.parseInt(u8, raw[i .. i + 1], 16) catch return LexError.InvalidEscape);
                        i += 1;
                    }
                    try out.append(alloc, byte);
                },
                'u' => {
                    i += 1;
                    if (i >= raw.len or raw[i] != '{') return LexError.InvalidEscape;
                    i += 1;
                    var cp: u21 = 0;
                    var digits: u32 = 0;
                    while (i < raw.len and raw[i] != '}') {
                        if (!std.ascii.isHex(raw[i])) return LexError.InvalidEscape;
                        const digit = std.fmt.parseInt(u21, raw[i .. i + 1], 16) catch return LexError.InvalidEscape;
                        cp = cp * 16 + digit;
                        digits += 1;
                        i += 1;
                    }
                    if (digits == 0 or i >= raw.len or raw[i] != '}') return LexError.InvalidEscape;
                    i += 1;
                    var enc: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &enc) catch return LexError.InvalidEscape;
                    try out.appendSlice(alloc, enc[0..n]);
                },
                '\r' => {
                    i += 1;
                    if (i < raw.len and raw[i] == '\n') i += 1;
                },
                '\n' => i += 1,
                else => {
                    try out.append(alloc, raw[i]);
                    i += 1;
                },
            }
        }
        return try out.toOwnedSlice(alloc);
    }

    fn read_num(self: *Lexer) LexError!Token {
        const l = self.cur_loc();
        const start = self.cursor.index;
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

        const text = self.cursor.bytes[start..self.cursor.index];
        if (is_float) {
            const v = std.fmt.parseFloat(f64, text) catch return LexError.InvalidNumber;
            return Token{ .kind = .float_lit, .loc = l, .text = text, .float_val = v };
        } else {
            const v = if (text.len > 2 and (text[1] == 'x' or text[1] == 'X')) blk: {
                // A hex literal is a bit pattern, not a signed magnitude. Parsing it
                // as i64 rejected every constant with the top bit set — e.g. the FNV
                // offset basis `0xcbf29ce484222325` (14695981039346656037) in
                // `lib/std/heap.duo`, which failed the whole file with
                // "lexer failed with InvalidNumber". Fall back to u64 and reinterpret.
                if (std.fmt.parseInt(i64, text[2..], 16)) |signed| {
                    break :blk signed;
                } else |_| {
                    const unsigned = std.fmt.parseInt(u64, text[2..], 16) catch
                        return LexError.InvalidNumber;
                    break :blk @as(i64, @bitCast(unsigned));
                }
            } else std.fmt.parseInt(i64, text, 10) catch return LexError.InvalidNumber;
            return Token{ .kind = .int_lit, .loc = l, .text = text, .int_val = v };
        }
    }

    fn lookup_kw(text: []const u8) ?TokenKind {
        return @import("duo_lexer_bridge.zig").lookupKeyword(text);
    }

    fn next_tok(self: *Lexer) LexError!Token {
        try self.skip_ws();
        if (self.cursor.index >= self.cursor.bytes.len)
            return Token{ .kind = .eof, .loc = self.cur_loc(), .text = "" };

        const l = self.cur_loc();
        const c = self.peek_char();

        // Numbers
        if (std.ascii.isDigit(c) or (c == '.' and std.ascii.isDigit(self.peek_char2())))
            return self.read_num();

        // Identifiers / keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = self.cursor.index;
            while (self.cursor.index < self.cursor.bytes.len and
                (std.ascii.isAlphanumeric(self.peek_char()) or self.peek_char() == '_'))
                _ = self.adv();
            const text = self.cursor.bytes[start..self.cursor.index];
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
        const p = self.cursor.index;
        return switch (c) {
            '+' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .plus_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .plus, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '*' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .star_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .star, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '%' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .percent_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .percent, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '^' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .caret_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .caret, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '#' => if (self.peek_char() == '#') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .hash_hash, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .hash, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '&' => Token{ .kind = .amp, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '|' => if (self.cursor.index < self.cursor.bytes.len and self.cursor.bytes[self.cursor.index] == '>') blk2: {
                self.cursor.index += 1;
                break :blk2 Token{ .kind = .pipe_gt, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .pipe, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '(' => Token{ .kind = .lparen, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            ')' => Token{ .kind = .rparen, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '[' => Token{ .kind = .lbracket, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            ']' => Token{ .kind = .rbracket, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '{' => Token{ .kind = .lbrace, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '}' => Token{ .kind = .rbrace, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            ';' => Token{ .kind = .semi, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            ',' => Token{ .kind = .comma, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '-' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .minus_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else if (self.peek_char() == '>') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .arrow, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .minus, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '/' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .slash_assign, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else if (self.peek_char() == '/') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .idiv, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .slash, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '.' => if (self.peek_char() == '.') blk: {
                _ = self.adv();
                if (self.peek_char() == '.') {
                    _ = self.adv();
                    break :blk Token{ .kind = .dots, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
                }
                break :blk Token{ .kind = .concat, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .dot, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '=' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .eq, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else if (self.peek_char() == '>') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .fat_arrow, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .assign, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '~' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .neq, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .tilde, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '<' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .leq, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else if (self.peek_char() == '<') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .lshift, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .lt, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '>' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .geq, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else if (self.peek_char() == '>') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .rshift, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .gt, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            ':' => if (self.peek_char() == ':') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .dcolon, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .colon, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '@' => Token{ .kind = .at, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '?' => Token{ .kind = .question, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '!' => if (self.peek_char() == '=') blk: {
                _ = self.adv();
                break :blk Token{ .kind = .neq, .loc = l, .text = self.cursor.bytes[p - 1 .. self.cursor.index] };
            } else Token{ .kind = .bang, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            '`' => Token{ .kind = .backtick, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
            else => LexError.UnexpectedChar,
        };
    }

    pub fn next(self: *Lexer) LexError!Token {
        if (self.peeked) |tok| {
            self.peeked = null;
            return tok;
        }
        return self.next_tok() catch |err| {
            self.last_error_loc = self.cur_loc();
            return err;
        };
    }

    pub fn peek(self: *Lexer) LexError!Token {
        if (self.peeked == null) {
            self.peeked = self.next_tok() catch |err| {
                self.last_error_loc = self.cur_loc();
                return err;
            };
        }
        return self.peeked.?;
    }

    /// Save lexer state for speculative parsing / look-ahead.
    pub const State = struct { pos: usize, line: u32, col: u32, peeked: ?Token };
    pub fn saveState(self: *const Lexer) State {
        return .{
            .pos = self.cursor.index,
            .line = self.cursor.line,
            .col = self.cursor.col,
            .peeked = self.peeked,
        };
    }

    /// Restore lexer state from a saved snapshot.
    pub fn restoreState(self: *Lexer, state: State) void {
        self.cursor.index = state.pos;
        self.cursor.line = state.line;
        self.cursor.col = state.col;
        self.peeked = state.peeked;
    }

    /// Check whether a token kind is a primitive type keyword (i8..f64, bool, void, str).
    pub fn isTypeKeyword(kind: TokenKind) bool {
        return switch (kind) {
            .kw_i8,
            .kw_i16,
            .kw_i32,
            .kw_i64,
            .kw_u8,
            .kw_u16,
            .kw_u32,
            .kw_u64,
            .kw_f32,
            .kw_f64,
            .kw_bool,
            .kw_void,
            .kw_str,
            => true,
            else => false,
        };
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "lex: identifiers" {
    var l = Lexer.init("foo bar _x hello123", "test");
    const names = [_][]const u8{ "foo", "bar", "_x", "hello123" };
    for (names) |expected| {
        const tok = try l.next();
        try testing.expectEqual(TokenKind.name, tok.kind);
        try testing.expectEqualStrings(expected, tok.text);
    }
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: standard keywords" {
    var l = Lexer.init("and break continue do else elseif end false for function goto if in local nil not or repeat return then true until while", "test");
    const expected = [_]TokenKind{
        .kw_and,   .kw_break, .kw_continue, .kw_do,     .kw_else,   .kw_elseif, .kw_end,
        .kw_false, .kw_for,   .kw_function, .kw_goto,   .kw_if,     .kw_in,     .kw_local,
        .kw_nil,   .kw_not,   .kw_or,       .kw_repeat, .kw_return, .kw_then,   .kw_true,
        .kw_until, .kw_while,
    };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: duo extension keywords" {
    var l = Lexer.init("const enum fun global", "test");
    const expected = [_]TokenKind{ .kw_const, .kw_enum, .kw_fun, .kw_global };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: type keywords" {
    var l = Lexer.init("i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool void str", "test");
    const expected = [_]TokenKind{
        .kw_i8,  .kw_i16, .kw_i32,  .kw_i64,
        .kw_u8,  .kw_u16, .kw_u32,  .kw_u64,
        .kw_f32, .kw_f64, .kw_bool, .kw_void,
        .kw_str,
    };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: decimal integers" {
    var l = Lexer.init("0 1 42 255 1000", "test");
    const vals = [_]i64{ 0, 1, 42, 255, 1000 };
    for (vals) |expected| {
        const tok = try l.next();
        try testing.expectEqual(TokenKind.int_lit, tok.kind);
        try testing.expectEqual(expected, tok.int_val);
    }
}

test "lex: hex integers" {
    var l = Lexer.init("0xff 0xFF 0x0 0x10", "test");
    const vals = [_]i64{ 255, 255, 0, 16 };
    for (vals) |expected| {
        const tok = try l.next();
        try testing.expectEqual(TokenKind.int_lit, tok.kind);
        try testing.expectEqual(expected, tok.int_val);
    }
}

test "lex: float literals" {
    var l = Lexer.init("3.14 1.0 0.5", "test");
    const expected_vals = [_]f64{ 3.14, 1.0, 0.5 };
    for (expected_vals) |expected| {
        const tok = try l.next();
        try testing.expectEqual(TokenKind.float_lit, tok.kind);
        try testing.expectApproxEqAbs(expected, tok.float_val, 1e-9);
    }
}

test "lex: float with exponent" {
    var l = Lexer.init("1.5e2 2.0e-1", "test");
    const tok1 = try l.next();
    try testing.expectEqual(TokenKind.float_lit, tok1.kind);
    try testing.expectApproxEqAbs(@as(f64, 150.0), tok1.float_val, 1e-9);
    const tok2 = try l.next();
    try testing.expectEqual(TokenKind.float_lit, tok2.kind);
    try testing.expectApproxEqAbs(@as(f64, 0.2), tok2.float_val, 1e-9);
}

test "lex: double-quoted string" {
    var l = Lexer.init("\"hello\"", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("hello", tok.text);
}

test "lex: single-quoted string" {
    var l = Lexer.init("'world'", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("world", tok.text);
}

test "lex: empty string" {
    var l = Lexer.init("\"\"", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("", tok.text);
}

test "lex: long string level 0" {
    var l = Lexer.init("[[hello world]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("hello world", tok.text);
}

test "lex: long string level 1" {
    var l = Lexer.init("[=[content]=]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("content", tok.text);
}

test "lex: long string level 1 with embedded level-0 close" {
    var l = Lexer.init("[=[contains ]] without ending]=]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("contains ]] without ending", tok.text);
}

test "lex: long string level 2 with embedded level-1 close" {
    var l = Lexer.init("[==[contains ]=] and more ]==]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("contains ]=] and more ", tok.text);
}

test "lex: long string preserves bash conditional text at shell boundary" {
    const src =
        "shell [=[\nif [[ -f \"$file\" ]]; then\n    echo \"$file\"\nfi\n]=]\n";
    var l = Lexer.init(src, "test");
    const name = try l.next();
    try testing.expectEqual(TokenKind.name, name.kind);
    try testing.expectEqualStrings("shell", name.text);
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expect(std.mem.indexOf(u8, tok.text, "if [[ -f") != null);
    try testing.expect(std.mem.indexOf(u8, tok.text, "echo \"$file\"") != null);
    try testing.expect(std.mem.indexOf(u8, tok.text, "fi") != null);
}

test "lex: long comment level 0 skipped" {
    var l = Lexer.init("--[[ block ]]\na = 1", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("a", tok.text);
}

test "lex: long comment level 1 with ]] inside" {
    var l = Lexer.init("--[=[ has ]] inside ]=]\nb = 2", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("b", tok.text);
}

test "lex: long string level 2" {
    var l = Lexer.init("[==[text]==]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("text", tok.text);
}

test "lex: long string strips leading newline" {
    var l = Lexer.init("[[\nhello]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("hello", tok.text);
}

test "lex: long string with embedded newlines preserved" {
    var l = Lexer.init("[[line1\nline2]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("line1\nline2", tok.text);
}

test "lex: long string with array index before close" {
    var l = Lexer.init("[[double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expectEqualStrings("double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];", tok.text);
    try testing.expect(tok.text[tok.text.len - 1] != ']');
}

test "lex: long bracket after lparen for c.emit" {
    var l = Lexer.init("([[double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];]])", "test");
    _ = try l.next(); // lparen
    const tok = try l.next();
    try testing.expectEqual(TokenKind.string_lit, tok.kind);
    try testing.expect(std.mem.indexOf(u8, tok.text, "C[i];") != null);
    try testing.expect(!std.mem.endsWith(u8, tok.text, "]"));
}

test "lex: long string embedded in other tokens" {
    var l = Lexer.init("42 [[inside]] 99", "test");
    const t1 = try l.next();
    try testing.expectEqual(TokenKind.int_lit, t1.kind);
    const t2 = try l.next();
    try testing.expectEqual(TokenKind.string_lit, t2.kind);
    try testing.expectEqualStrings("inside", t2.text);
    const t3 = try l.next();
    try testing.expectEqual(TokenKind.int_lit, t3.kind);
    try testing.expectEqual(@as(i64, 99), t3.int_val);
}

test "lex: line comment is skipped" {
    var l = Lexer.init("-- ignored\n42", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 42), tok.int_val);
}

test "lex: block comment is skipped" {
    var l = Lexer.init("--[[block comment]]99", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 99), tok.int_val);
}

test "lex: block comment with level skipped" {
    var l = Lexer.init("--[==[comment]==]77", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 77), tok.int_val);
}

test "lex: block comment level 1 with embedded level-0 close" {
    var l = Lexer.init("--[=[comment containing ]]]=]55", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 55), tok.int_val);
}

test "lex: single-char operators" {
    var l = Lexer.init("+ - * / % ^ # & | < > = ~ ; : , . @ ? ! `", "test");
    const expected = [_]TokenKind{
        .plus,  .minus, .star, .slash, .percent,  .caret, .hash,
        .amp,   .pipe,  .lt,   .gt,    .assign,   .tilde, .semi,
        .colon, .comma, .dot,  .at,    .question, .bang,  .backtick,
    };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: multi-char operators" {
    var l = Lexer.init("== ~= != <= >= << >> // .. ... ## -> :: += -= *= /= %= ^=", "test");
    const expected = [_]TokenKind{
        .eq,          .neq,          .neq,          .leq,            .geq,          .lshift, .rshift,
        .idiv,        .concat,       .dots,         .hash_hash,      .arrow,        .dcolon, .plus_assign,
        .minus_assign, .star_assign, .slash_assign, .percent_assign, .caret_assign,
    };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: brackets and braces" {
    var l = Lexer.init("( ) { } [ ]", "test");
    const expected = [_]TokenKind{ .lparen, .rparen, .lbrace, .rbrace, .lbracket, .rbracket };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
}

test "lex: line and column tracking" {
    var l = Lexer.init("a\nb", "test");
    const t1 = try l.next();
    try testing.expectEqual(@as(u32, 1), t1.loc.line);
    try testing.expectEqual(@as(u32, 1), t1.loc.col);
    const t2 = try l.next();
    try testing.expectEqual(@as(u32, 2), t2.loc.line);
    try testing.expectEqual(@as(u32, 1), t2.loc.col);
}

test "lex: column advances within a line" {
    var l = Lexer.init("ab", "test");
    const tok = try l.next();
    try testing.expectEqual(@as(u32, 1), tok.loc.col);
}

test "lex: file name preserved in loc" {
    var l = Lexer.init("x", "myfile.duo");
    const tok = try l.next();
    try testing.expectEqualStrings("myfile.duo", tok.loc.file);
}

test "lex: peek does not consume" {
    var l = Lexer.init("42", "test");
    const p1 = try l.peek();
    const p2 = try l.peek();
    const n1 = try l.next();
    try testing.expectEqual(p1.kind, p2.kind);
    try testing.expectEqual(p1.kind, n1.kind);
    try testing.expectEqual(p1.int_val, n1.int_val);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: whitespace skipped" {
    var l = Lexer.init("   \t\r\n  42", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 42), tok.int_val);
}

test "lex: shebang line is skipped" {
    var l = Lexer.init("#!/usr/bin/env duo\nprint(42)", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("print", tok.text);
    try testing.expectEqual(@as(u32, 2), tok.loc.line);
}

test "lex error: unterminated double-quoted string" {
    var l = Lexer.init("\"oops", "test");
    try testing.expectError(error.UnterminatedString, l.next());
}

test "lex error: unterminated single-quoted string" {
    var l = Lexer.init("'oops", "test");
    try testing.expectError(error.UnterminatedString, l.next());
}

test "lex error: unterminated long string" {
    var l = Lexer.init("[[oops", "test");
    try testing.expectError(error.UnterminatedLongString, l.next());
}

test "lex error: long string wrong closing level" {
    // [==[...]=] — closing has one fewer '=' than opening
    var l = Lexer.init("[==[oops]=]", "test");
    try testing.expectError(error.UnterminatedLongString, l.next());
}

test "lex error: unexpected character" {
    var l = Lexer.init("$", "test");
    try testing.expectError(error.UnexpectedChar, l.next());
}

test "decode_lua_short_string: no escapes" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "hello");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("hello", result);
}

test "decode_lua_short_string: newline escape" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "a\\nb");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a\nb", result);
}

test "decode_lua_short_string: all single-char escapes" {
    const alloc = testing.allocator;
    const cases = [_]struct { in: []const u8, out: []const u8 }{
        .{ .in = "\\a", .out = "\x07" },
        .{ .in = "\\b", .out = "\x08" },
        .{ .in = "\\f", .out = "\x0C" },
        .{ .in = "\\n", .out = "\n" },
        .{ .in = "\\r", .out = "\r" },
        .{ .in = "\\t", .out = "\t" },
        .{ .in = "\\v", .out = "\x0B" },
        .{ .in = "\\\\", .out = "\\" },
        .{ .in = "\\\"", .out = "\"" },
        .{ .in = "\\'", .out = "'" },
    };
    for (cases) |c| {
        const result = try Lexer.decode_lua_short_string(alloc, c.in);
        defer alloc.free(result);
        try testing.expectEqualStrings(c.out, result);
    }
}

test "decode_lua_short_string: hex escape \\x41 = 'A'" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "\\x41");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("A", result);
}

test "decode_lua_short_string: hex escape \\xFF" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "\\xFF");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 0xFF), result[0]);
}

test "decode_lua_short_string: unicode escape \\u{0041} = 'A'" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "\\u{0041}");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("A", result);
}

test "decode_lua_short_string: \\z skips whitespace" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "a\\z   b");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("ab", result);
}

test "decode_lua_short_string: empty string" {
    const result = try Lexer.decode_lua_short_string(testing.allocator, "");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("", result);
}

test "decode_lua_short_string error: invalid hex escape" {
    try testing.expectError(
        error.InvalidEscape,
        Lexer.decode_lua_short_string(testing.allocator, "\\xGG"),
    );
}

test "decode_lua_short_string error: incomplete unicode escape" {
    try testing.expectError(
        error.InvalidEscape,
        Lexer.decode_lua_short_string(testing.allocator, "\\u{"),
    );
}

test "lex: contextual keywords" {
    var l = Lexer.init("match try catch defer async await concept alias", "test");
    const expected = [_]TokenKind{
        .kw_match, .kw_try, .kw_catch, .kw_defer, .kw_async, .kw_await, .kw_concept, .kw_alias,
    };
    for (expected) |kind| try testing.expectEqual(kind, (try l.next()).kind);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: at operator" {
    var l = Lexer.init("@", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.at, tok.kind);
    try testing.expectEqualStrings("@", tok.text);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: question operator" {
    var l = Lexer.init("?", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.question, tok.kind);
    try testing.expectEqualStrings("?", tok.text);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: bang operator" {
    var l = Lexer.init("!", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.bang, tok.kind);
    try testing.expectEqualStrings("!", tok.text);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: at question bang in sequence" {
    var l = Lexer.init("@ ? !", "test");
    try testing.expectEqual(TokenKind.at, (try l.next()).kind);
    try testing.expectEqual(TokenKind.question, (try l.next()).kind);
    try testing.expectEqual(TokenKind.bang, (try l.next()).kind);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: contextual keywords in expression context" {
    // Contextual keywords used as identifiers should still lex as keywords
    // (the parser determines contextual usage, not the lexer)
    var l = Lexer.init("match(x)", "test");
    try testing.expectEqual(TokenKind.kw_match, (try l.next()).kind);
    try testing.expectEqual(TokenKind.lparen, (try l.next()).kind);
    try testing.expectEqual(TokenKind.name, (try l.next()).kind);
    try testing.expectEqual(TokenKind.rparen, (try l.next()).kind);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: attribute usage pattern" {
    // Common pattern: @inline fun foo() end
    var l = Lexer.init("@inline", "test");
    const t1 = try l.next();
    try testing.expectEqual(TokenKind.at, t1.kind);
    const t2 = try l.next();
    try testing.expectEqual(TokenKind.name, t2.kind);
    try testing.expectEqualStrings("inline", t2.text);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: postfix operators after name" {
    // Pattern: value? and value!
    var l = Lexer.init("x? y!", "test");
    try testing.expectEqual(TokenKind.name, (try l.next()).kind);
    try testing.expectEqual(TokenKind.question, (try l.next()).kind);
    try testing.expectEqual(TokenKind.name, (try l.next()).kind);
    try testing.expectEqual(TokenKind.bang, (try l.next()).kind);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}

test "lex: match arm with then separator" {
    var l = Lexer.init("| x then 42", "test");
    try testing.expectEqual(TokenKind.pipe, (try l.next()).kind);
    try testing.expectEqual(TokenKind.name, (try l.next()).kind);
    try testing.expectEqual(TokenKind.kw_then, (try l.next()).kind);
    try testing.expectEqual(TokenKind.int_lit, (try l.next()).kind);
    try testing.expectEqual(TokenKind.eof, (try l.next()).kind);
}
