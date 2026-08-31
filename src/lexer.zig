const std = @import("std");
const source_cursor = @import("source_cursor.zig");

pub const Loc = source_cursor.Loc;

pub const DecimalIntegerClass = enum(u8) { ordinary, min_magnitude, u64_bits, wider };

/// Differential-only mirror of the Idol producer's decimal magnitude fact.
/// Production tokens receive this fact from `lib/compiler/lexer.id`; this
/// independent host scanner exists only to make producer damage observable.
fn decimalMagnitudeClass(text: []const u8) DecimalIntegerClass {
    var first: usize = 0;
    while (first < text.len and text[first] == '0') : (first += 1) {}
    const significant = text[first..];
    if (significant.len < 19) return .ordinary;
    if (significant.len > 20) return .wider;
    const lower = "9223372036854775808";
    if (significant.len == 19) {
        for (significant, lower) |source_digit, boundary_digit| {
            if (source_digit < boundary_digit) return .ordinary;
            if (source_digit > boundary_digit) return .u64_bits;
        }
        return .min_magnitude;
    }
    const upper = "18446744073709551615";
    for (significant, upper) |source_digit, boundary_digit| {
        if (source_digit < boundary_digit) return .u64_bits;
        if (source_digit > boundary_digit) return .wider;
    }
    return .u64_bits;
}

/// Physical token identity projected from the one executable owner.
/// `lib/compiler/token.id` fixes each producer slot; the generated bridge
/// carries that enum into the host until the parser consumes the owner directly.
pub const TokenKind = @import("grammar_role_table.zig").TokenKind;

pub const Token = struct {
    kind: TokenKind,
    /// Producer-owned decimal integer class. One card is carried because the
    /// four states are mutually exclusive; three booleans would admit
    /// impossible token facts. Hex bit patterns and fitted decimals are
    /// ordinary.
    int_class: DecimalIntegerClass = .ordinary,
    loc: Loc,
    text: []const u8,
    int_val: i64 = 0,
    float_val: f64 = 0.0,
};

test "lexer: decimal integer card consumes existing Token padding" {
    if (@sizeOf(usize) != 8) return;
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Token));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Token, "loc"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Token, "text"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Token, "int_val"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Token, "float_val"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(Token, "kind"));
    try std.testing.expectEqual(@as(usize, 57), @offsetOf(Token, "int_class"));
}

pub const LexError = error{
    UnterminatedString,
    UnterminatedLongString,
    InvalidNumber,
    UnexpectedChar,
    InvalidEscape,
    InsufficientIndent,
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

    /// SH-03 production dispatch. When non-null, tokens come from the DUO lexer
    /// (lib/compiler/lexer.id, via src/lexer_dispatch.zig) and this
    /// struct is a cursor over that stream rather than a scanner. The host
    /// scanner below stays intact and stays the differential oracle.
    ///
    /// The caller owns the slice and its text arena; production route installs
    /// it without copying. The compile driver owns the allocator —
    /// `init` deliberately keeps its allocator-free signature so the ~30
    /// existing call sites and every test are unaffected.
    duo_tokens: ?[]const Token = null,
    duo_index: usize = 0,

    /// Scratch for canonical multiline text normalization (GAP-145).
    text_scratch: [8192]u8 = undefined,
    text_scratch_len: usize = 0,

    /// Source-family operand (1 = canon, 2 = compat). Set once at init; later
    /// stages consume this fact and must not re-parse the path (`law.family.one`).
    family: i64 = 0,
    source_law: @import("lexer_bridge.zig").SourceLaw = .unknown,
    source_law_edition: @import("authority_projection.zig").SourceLawEdition = .unknown,
    /// Byte-zero `#!` line published by the producer. Empty when absent.
    shebang: []const u8 = "",

    /// Test convenience. Production compile, fmt, and embed call `initFacts`
    /// after one `sourceFacts` ingress (`law.family.one`).
    pub fn init(src: []const u8, file: []const u8) Lexer {
        const facts = @import("lexer_bridge.zig").sourceFacts(file);
        return initFacts(src, file, facts);
    }

    pub fn initFacts(src: []const u8, file: []const u8, facts: @import("lexer_bridge.zig").SourceFacts) Lexer {
        return initFamilyLaw(src, file, @import("lexer_bridge.zig").familyCode(facts), facts.law);
    }

    pub fn initFamily(src: []const u8, file: []const u8, family: i64) Lexer {
        const law: @import("lexer_bridge.zig").SourceLaw = if (family == @import("lexer_bridge.zig").family_canon)
            .idol
        else
            .lua;
        return initFamilyLaw(src, file, family, law);
    }

    pub fn initFamilyLaw(
        src: []const u8,
        file: []const u8,
        family: i64,
        source_law: @import("lexer_bridge.zig").SourceLaw,
    ) Lexer {
        const edition: @import("authority_projection.zig").SourceLawEdition = switch (source_law) {
            .idol => @import("authority_projection.zig").SourceLawEdition.idolCurrent(),
            .lua => .foreign_unversioned,
            .unknown => .unknown,
        };
        return initFamilyLawEdition(src, file, family, source_law, edition);
    }

    /// Preserve an already selected exact edition for nested/subsource parsing.
    /// Broad family alone cannot reconstruct a historical edition.
    pub fn initFamilyLawEdition(
        src: []const u8,
        file: []const u8,
        family: i64,
        source_law: @import("lexer_bridge.zig").SourceLaw,
        source_law_edition: @import("authority_projection.zig").SourceLawEdition,
    ) Lexer {
        return .{
            .cursor = source_cursor.ProductionCursor.init(src, file),
            .peeked = null,
            .last_error_loc = null,
            .family = family,
            .source_law = source_law,
            .source_law_edition = source_law_edition,
        };
    }

    /// Observe `--- @` facts already in the producer pack. Host-scanner
    /// harvest is not a production path (`law.bridge.death`).
    pub fn harvestCommentHints(self: *Lexer) void {
        self.pending_hint_count = 0;
        self.pending_hints = .{ null, null, null, null, null, null, null, null };
        const toks = self.duo_tokens orelse return;
        for (toks) |tok| {
            if (tok.kind != .compat_comment) continue;
            if (tok.text.len < 3) continue;
            if (tok.text[0] != '-' or tok.text[1] != '-' or tok.text[2] != '-') continue;
            const trimmed = std.mem.trim(u8, tok.text[3..], " \t");
            if (trimmed.len > 0 and trimmed[0] == '@' and self.pending_hint_count < 8) {
                self.pending_hints[self.pending_hint_count] = trimmed[1..];
                self.pending_hint_count += 1;
            }
        }
    }

    /// One token from the Duo stream. Past the end it repeats EOF, matching the
    /// host scanner, which keeps returning `.eof` rather than erroring.
    fn duo_next(self: *Lexer) Token {
        const toks = self.duo_tokens.?;
        while (self.duo_index < toks.len) {
            const tok = toks[self.duo_index];
            self.duo_index += 1;
            if (tok.kind == .shebang) {
                self.shebang = tok.text;
                continue;
            }
            if (tok.kind == .comment or tok.kind == .compat_comment or tok.kind == .compat_long_comment) continue;
            return tok;
        }
        return toks[toks.len - 1];
    }

    fn cur_loc(self: *Lexer) Loc {
        return self.cursor.loc();
    }

    /// Install the validated producer pack so the host parser can advance by
    /// token ordinal. The slice is owned by the caller (production: the
    /// parser-installed pack; tests: a stack array). The lex cursor parks
    /// at the pack's last byte so any subsequent host fallback walks nothing;
    /// shebang seating, peek reset, and hint harvest are kept here.
    pub fn installProducerPack(self: *Lexer, toks: []const Token) void {
        if (toks.len >= 2 and toks[0].kind == .shebang) {
            self.shebang = toks[0].text;
        }
        self.cursor.index = self.cursor.bytes.len;
        self.cursor.line = toks[toks.len - 1].loc.line;
        self.cursor.col = toks[toks.len - 1].loc.col + 1;
        self.peeked = null;
        self.harvestCommentHints();
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

    fn skipNewline(self: *Lexer) void {
        if (self.peek_char() == '\r') _ = self.adv();
        if (self.peek_char() == '\n') _ = self.adv();
    }

    fn readCanonicalMultiline(self: *Lexer) LexError![]const u8 {
        self.skipNewline();
        const content_start = self.cursor.index;
        var close_at: ?usize = null;
        var close_indent: u32 = 0;
        while (self.cursor.index < self.cursor.bytes.len) {
            const line_start = self.cursor.index;
            var only_ws = true;
            while (self.cursor.index < self.cursor.bytes.len) {
                const c = self.peek_char();
                if (c == '\n' or c == '\r') break;
                if (c == '"') {
                    if (only_ws) {
                        close_at = line_start;
                        close_indent = self.cursor.col - 1;
                        _ = self.adv();
                        break;
                    }
                }
                if (c != ' ' and c != '\t') only_ws = false;
                _ = self.adv();
            }
            if (close_at != null) break;
            if (self.peek_char() == '\r') _ = self.adv();
            if (self.peek_char() == '\n') _ = self.adv();
        }
        if (close_at == null) return LexError.UnterminatedString;

        var out_len: usize = 0;
        self.cursor.index = content_start;
        while (self.cursor.index < close_at.?) {
            const line_start = self.cursor.index;
            while (self.cursor.index < close_at.? and self.peek_char() != '\n' and self.peek_char() != '\r')
                _ = self.adv();
            const line_end = self.cursor.index;
            var nonblank = false;
            var check = line_start;
            while (check < line_end) : (check += 1) {
                const bc = self.cursor.bytes[check];
                if (bc != ' ' and bc != '\t') {
                    nonblank = true;
                    break;
                }
            }
            if (nonblank) {
                if (close_indent > 0) {
                    var wi: u32 = 0;
                    while (wi < close_indent) : (wi += 1) {
                        if (line_start + wi >= line_end or self.cursor.bytes[line_start + wi] != ' ')
                            return LexError.InsufficientIndent;
                    }
                }
                const chunk_start = line_start + close_indent;
                if (chunk_start <= line_end) {
                    const chunk = self.cursor.bytes[chunk_start..line_end];
                    if (out_len + chunk.len + 1 > self.text_scratch.len) return LexError.OutOfMemory;
                    if (out_len > 0) self.text_scratch[out_len] = '\n';
                    if (out_len > 0) out_len += 1;
                    @memcpy(self.text_scratch[out_len .. out_len + chunk.len], chunk);
                    out_len += chunk.len;
                }
            } else if (out_len > 0) {
                if (out_len + 1 > self.text_scratch.len) return LexError.OutOfMemory;
                self.text_scratch[out_len] = '\n';
                out_len += 1;
            }
            if (self.peek_char() == '\r') _ = self.adv();
            if (self.peek_char() == '\n') _ = self.adv();
        }
        self.text_scratch_len = out_len;
        return self.text_scratch[0..out_len];
    }

    fn read_str(self: *Lexer, quote: u8) LexError![]const u8 {
        _ = self.adv(); // opening quote
        if (quote == '"' and self.family == @import("lexer_bridge.zig").family_canon) {
            const c0 = self.peek_char();
            if (c0 == '\n' or c0 == '\r') return self.readCanonicalMultiline();
        }
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
    ///
    /// The one-argument spelling every existing caller uses. `decodeText` is the
    /// same decoder with the escape-provenance map exposed.
    pub fn decode_lua_short_string(alloc: std.mem.Allocator, raw: []const u8) LexError![]u8 {
        return decodeText(alloc, raw, null);
    }

    /// Decode a short string literal body, and — when asked — record WHICH
    /// DECODED BYTES CAME FROM AN ESCAPE.
    ///
    /// `protected`, when given, receives exactly one `bool` per byte appended to
    /// the result: `true` if that byte was produced by a backslash escape,
    /// `false` if it was copied verbatim out of the source.
    ///
    /// ===================== WHY THE MAP HAS TO EXIST =====================
    /// `docs/text-law.md` rules `\{` and `\}` the literal-brace spelling in the
    /// canonical text face, and the fact CANNOT BE RECOVERED AFTER DECODING:
    /// `\{`, `\x7B`, `\123` and a bare `{` all produce the single byte 0x7B.
    /// Measured before the ruling, `print("A[\x7Bx}]")` printed `A[7]` — the hex
    /// escape opened a hole exactly as a bare brace does. A design that
    /// protected only the two-character sequence `\{` and not the BYTE IT
    /// PRODUCES would leave that case wrong, which is why the fact belongs to
    /// the decoder and not to `desugar_string_interpolation`.
    ///
    /// `law.lexical.one`: the lexer records the role ONCE; no consumer
    /// reconstructs it from delimiter text, source substring, flags or contents.
    pub fn decodeText(
        alloc: std.mem.Allocator,
        raw: []const u8,
        protected: ?*std.ArrayList(bool),
    ) LexError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(alloc);
        var i: usize = 0;
        while (i < raw.len) {
            // Every branch below may append zero, one or several bytes (`\z`
            // appends none, `\u{1F600}` appends four). Rather than thread the
            // map through fifteen append sites — where one missed site is a
            // silent one-bit desync between two arrays that must stay the same
            // length — the flag is stamped ONCE PER SOURCE ELEMENT across
            // however many bytes that element produced.
            const mark = out.items.len;
            const from_escape = raw[i] == '\\';
            if (!from_escape) {
                try out.append(alloc, raw[i]);
                i += 1;
            } else {
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
                            cp *= 16;
                            cp += digit;
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
                    // `\ddd` — up to three DECIMAL digits, one byte. Without this
                    // case `\0` fell to the fallback below, which drops the
                    // backslash and keeps the digit, so `"a\0b"` decoded to the
                    // bytes `a`, `0`, `b`. Both are 3 bytes long, so every
                    // length-based assertion over such a string kept passing while
                    // the NUL it was checking had quietly become an ASCII zero.
                    '0'...'9' => {
                        var value: u32 = 0;
                        var digits: u8 = 0;
                        while (i < raw.len and digits < 3 and std.ascii.isDigit(raw[i])) {
                            value = value * 10 + (raw[i] - '0');
                            digits += 1;
                            i += 1;
                        }
                        if (value > 255) return LexError.InvalidEscape;
                        try out.append(alloc, @intCast(value));
                    },
                    // `\{` and `\}` — THE LITERAL BRACE, per `docs/text-law.md`.
                    //
                    // Not new vocabulary. `src/main.zig` already ships a diagnostic
                    // declaring the escape set CLOSED ("Idol escapes are \n \t \r
                    // \\ \" \' \0 and \x<hex>"); this adds a member to a closed
                    // enumeration that already has an error for non-members, which
                    // is extension within admitted vocabulary. The alternative,
                    // `{{`, would be a new LEXICAL RULE (doubling) that exists
                    // nowhere else in the language — and it is already spoken for:
                    // `law.brace` makes `{` the structured-pack face and
                    // `law.literal.text` makes a hole an EXPRESSION, so
                    // `"n={{10, 20, 30}:len()}"` answers 3 today, and
                    // `lib/text/template` uses `{{` as its own action opener.
                    //
                    // The byte is ordinary; it is the `protected` flag stamped
                    // beside it that makes it text rather than a hole opener.
                    '{', '}' => {
                        try out.append(alloc, raw[i]);
                        i += 1;
                    },
                    // FAIL-CLOSED. This prong WAS
                    //
                    //     else => { try out.append(alloc, raw[i]); i += 1; },
                    //
                    // which silently DROPPED THE BACKSLASH on every undeclared
                    // escape, so the set `src/main.zig` advertises as closed was
                    // open in fact: `print("A[\q]")` printed `A[q]`. It is the same
                    // fallback that decoded `"a\0b"` to the bytes `a`, `0`, `b` —
                    // see the `\ddd` prong above, which exists only because of it,
                    // and whose comment records that every length-based assertion
                    // kept passing while the NUL had become an ASCII zero.
                    //
                    // Closing it is what makes `\{` safe to name. `"\{x}"` decoded
                    // to a hole yesterday and is literal text today; a program can
                    // only cross that line if some OTHER undeclared escape decays
                    // silently, and after this prong none does. Either a literal
                    // holds none but declared escapes — same bytes before and after
                    // — or it stops compiling and names the site.
                    else => return LexError.InvalidEscape,
                }
            }
            if (protected) |p| try p.appendNTimes(alloc, from_escape, out.items.len - mark);
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
            var int_class: DecimalIntegerClass = .ordinary;
            const v = if (text.len > 2 and (text[1] == 'x' or text[1] == 'X')) blk: {
                // A hex literal is a bit pattern, not a signed magnitude. Parsing it
                // as i64 rejected every constant with the top bit set — e.g. the FNV
                // offset basis `0xcbf29ce484222325` (14695981039346656037) in
                // `lib/heap.id`, which failed the whole file with
                // "lexer failed with InvalidNumber". Fall back to u64 and reinterpret.
                if (std.fmt.parseInt(i64, text[2..], 16)) |signed| {
                    break :blk signed;
                } else |_| {
                    const unsigned = std.fmt.parseInt(u64, text[2..], 16) catch
                        return LexError.InvalidNumber;
                    break :blk @as(i64, @bitCast(unsigned));
                }
            } else switch (decimalMagnitudeClass(text)) {
                .ordinary => std.fmt.parseInt(i64, text, 10) catch
                    return LexError.InvalidNumber,
                .min_magnitude => blk2: {
                    int_class = .min_magnitude;
                    break :blk2 std.math.minInt(i64);
                },
                .u64_bits => blk2: {
                    const unsigned = std.fmt.parseInt(u64, text, 10) catch
                        return LexError.InvalidNumber;
                    int_class = .u64_bits;
                    break :blk2 @as(i64, @bitCast(unsigned));
                },
                .wider => blk2: {
                    int_class = .wider;
                    break :blk2 0;
                },
            };
            return Token{
                .kind = .int_lit,
                .loc = l,
                .text = text,
                .int_val = v,
                .int_class = int_class,
            };
        }
    }

    fn lookup_kw(text: []const u8) ?TokenKind {
        return @import("lexer_bridge.zig").lookupKeyword(text);
    }

    /// Producer stream, including shebang/comment identities. Parser-facing
    /// `next()` / `peek()` skip those until GAP-134 roles exist.
    pub fn next_tok(self: *Lexer) LexError!Token {
        if (self.cursor.index == 0 and self.peek_char() == '#' and self.peek_char2() == '!') {
            const loc = self.cur_loc();
            const start = self.cursor.index;
            while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '\n')
                _ = self.adv();
            return Token{ .kind = .shebang, .loc = loc, .text = self.cursor.bytes[start..self.cursor.index] };
        }
        try self.skip_ws();
        if (self.cursor.index >= self.cursor.bytes.len)
            return Token{ .kind = .eof, .loc = self.cur_loc(), .text = "" };

        const l = self.cur_loc();
        const c = self.peek_char();
        if (c == '#' and self.family == @import("lexer_bridge.zig").family_canon) {
            const start = self.cursor.index;
            while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '\n')
                _ = self.adv();
            return Token{ .kind = .comment, .loc = l, .text = self.cursor.bytes[start..self.cursor.index] };
        }
        if (c == '-' and self.peek_char2() == '-') {
            const start = self.cursor.index;
            _ = self.adv();
            _ = self.adv();
            const level = self.long_bracket_level();
            if (level >= 0) {
                try self.skip_long(@intCast(level));
                return Token{ .kind = .compat_long_comment, .loc = l, .text = self.cursor.bytes[start..self.cursor.index] };
            }
            const is_triple = self.cursor.index < self.cursor.bytes.len and self.peek_char() == '-';
            if (is_triple) _ = self.adv();
            const body = self.cursor.index;
            while (self.cursor.index < self.cursor.bytes.len and self.peek_char() != '\n')
                _ = self.adv();
            if (is_triple) {
                const comment_text = self.cursor.bytes[body..self.cursor.index];
                const trimmed = std.mem.trim(u8, comment_text, " \t");
                if (trimmed.len > 0 and trimmed[0] == '@' and self.pending_hint_count < 8) {
                    self.pending_hints[self.pending_hint_count] = trimmed[1..];
                    self.pending_hint_count += 1;
                }
            }
            return Token{ .kind = .compat_comment, .loc = l, .text = self.cursor.bytes[start..self.cursor.index] };
        }

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

        // Strings — GAP-145 identities keyed by quote and the family operand.
        if (c == '\'' or c == '"') {
            const canon = self.family == @import("lexer_bridge.zig").family_canon;
            const lit_kind: TokenKind = if (c == '"')
                .text_lit
            else if (canon)
                .bytes_lit
            else
                .compat_text_lit;
            const s = try self.read_str(c);
            return Token{ .kind = lit_kind, .loc = l, .text = s };
        }

        // Long strings — compatibility long text only.
        if (c == '[') {
            const lvl = self.long_bracket_level();
            if (lvl >= 0) {
                const s = try self.read_long_str(@intCast(lvl));
                return Token{ .kind = .compat_long_text_lit, .loc = l, .text = s, .int_val = lvl };
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
            // `~` is XOR and nothing else; inequality is `!=`. Gluing a
            // following `=` here reported inequality (Lua's spelling) and, worse,
            // turned `x ~= 1` into a discarded comparison where xor-assign was
            // meant. Left bare, the grammar's adjacency rule forms `~=` as a
            // compound assignment like `>>=`, `<<=`, `|=` and `&=`.
            '~' => Token{ .kind = .tilde, .loc = l, .text = self.cursor.bytes[p - 1 .. p] },
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

    /// Parser-facing stream. Comment/shebang identities stay on the producer
    /// (`next_tok` / Idol tokenize). GAP-145 does not admit them as parser
    /// tokens until generated roles exist (`GAP-134`).
    fn takeParserToken(self: *Lexer, tok: Token) ?Token {
        switch (tok.kind) {
            .shebang => {
                self.shebang = tok.text;
                return null;
            },
            .comment, .compat_comment, .compat_long_comment => return null,
            else => return tok,
        }
    }

    fn host_next(self: *Lexer) LexError!Token {
        while (true) {
            const tok = self.next_tok() catch |err| {
                self.last_error_loc = self.cur_loc();
                return err;
            };
            if (self.takeParserToken(tok)) |visible| {
                if (visible.kind == .backtick and self.family == @import("lexer_bridge.zig").family_canon) {
                    self.last_error_loc = visible.loc;
                    return LexError.UnexpectedChar;
                }
                return visible;
            }
        }
    }

    pub fn next(self: *Lexer) LexError!Token {
        if (self.peeked) |tok| {
            self.peeked = null;
            return tok;
        }
        if (self.duo_tokens != null) return self.duo_next();
        return self.host_next();
    }

    pub fn peek(self: *Lexer) LexError!Token {
        if (self.peeked) |tok| return tok;
        if (self.duo_tokens != null) {
            self.peeked = self.duo_next();
            return self.peeked.?;
        }
        self.peeked = try self.host_next();
        return self.peeked.?;
    }

    /// Save lexer state for speculative parsing / look-ahead.
    /// `duo_index` is part of the snapshot: on the Duo path the stream position
    /// is the index, not the cursor, so restoring only `pos` would rewind the
    /// scanner and leave the token stream where it was — a silent desync on
    /// every backtrack.
    pub const State = struct { pos: usize, line: u32, col: u32, peeked: ?Token, duo_index: usize = 0 };
    pub fn saveState(self: *const Lexer) State {
        return .{
            .pos = self.cursor.index,
            .line = self.cursor.line,
            .col = self.cursor.col,
            .peeked = self.peeked,
            .duo_index = self.duo_index,
        };
    }

    /// Restore lexer state from a saved snapshot.
    pub fn restoreState(self: *Lexer, state: State) void {
        self.cursor.index = state.pos;
        self.cursor.line = state.line;
        self.cursor.col = state.col;
        self.peeked = state.peeked;
        self.duo_index = state.duo_index;
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

test "lex: canonical multiline text strips closing indent" {
    const src =
        \\"
        \\  line1
        \\  line2
        \\  "
    ;
    var l = Lexer.init(src, "probe.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.text_lit, tok.kind);
    try testing.expectEqualStrings("line1\nline2", tok.text);
}

test "lex: double-quoted string on canonical .id is text" {
    var l = Lexer.init("\"hello\"", "probe.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.text_lit, tok.kind);
    try testing.expectEqualStrings("hello", tok.text);
}

test "lex: single-quoted string on canonical .id is bytes" {
    var l = Lexer.init("'world'", "probe.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.bytes_lit, tok.kind);
    try testing.expectEqualStrings("world", tok.text);
}

test "lex: double-quoted string" {
    var l = Lexer.init("\"hello\"", "test.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.text_lit, tok.kind);
    try testing.expectEqualStrings("hello", tok.text);
}

test "lex: single-quoted string on historical source is compat text" {
    var l = Lexer.init("'world'", "test.duo");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_text_lit, tok.kind);
    try testing.expectEqualStrings("world", tok.text);
}

test "lex: empty string" {
    var l = Lexer.init("\"\"", "test.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.text_lit, tok.kind);
    try testing.expectEqualStrings("", tok.text);
}

test "lex: long string level 0" {
    var l = Lexer.init("[[hello world]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("hello world", tok.text);
    try testing.expectEqual(@as(i64, 0), tok.int_val);
}

test "lex: long string level 1" {
    var l = Lexer.init("[=[content]=]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("content", tok.text);
    try testing.expectEqual(@as(i64, 1), tok.int_val);
}

test "lex: long string level 1 with embedded level-0 close" {
    var l = Lexer.init("[=[contains ]] without ending]=]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("contains ]] without ending", tok.text);
}

test "lex: long string level 2 with embedded level-1 close" {
    var l = Lexer.init("[==[contains ]=] and more ]==]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
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
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
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
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("text", tok.text);
}

test "lex: long string strips leading newline" {
    var l = Lexer.init("[[\nhello]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("hello", tok.text);
}

test "lex: long string with embedded newlines preserved" {
    var l = Lexer.init("[[line1\nline2]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("line1\nline2", tok.text);
}

test "lex: long string with array index before close" {
    var l = Lexer.init("[[double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];]]", "test");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expectEqualStrings("double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];", tok.text);
    try testing.expect(tok.text[tok.text.len - 1] != ']');
}

test "lex: long bracket after lparen for c.emit" {
    var l = Lexer.init("([[double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];]])", "test");
    _ = try l.next(); // lparen
    const tok = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, tok.kind);
    try testing.expect(std.mem.indexOf(u8, tok.text, "C[i];") != null);
    try testing.expect(!std.mem.endsWith(u8, tok.text, "]"));
}

test "lex: long string embedded in other tokens" {
    var l = Lexer.init("42 [[inside]] 99", "test");
    const t1 = try l.next();
    try testing.expectEqual(TokenKind.int_lit, t1.kind);
    const t2 = try l.next();
    try testing.expectEqual(TokenKind.compat_long_text_lit, t2.kind);
    try testing.expectEqualStrings("inside", t2.text);
    const t3 = try l.next();
    try testing.expectEqual(TokenKind.int_lit, t3.kind);
    try testing.expectEqual(@as(i64, 99), t3.int_val);
}

test "lex: canonical hash comment on .id is skipped" {
    var l = Lexer.init("# note\n42", "gate.id");
    const tok = try l.next();
    try testing.expectEqual(TokenKind.int_lit, tok.kind);
    try testing.expectEqual(@as(i64, 42), tok.int_val);
}

test "lex: family operand not suffix decides hash comment" {
    const bridge = @import("lexer_bridge.zig");
    var canon = Lexer.initFamily("# note\n42", "x.lua", bridge.family_canon);
    try testing.expectEqual(TokenKind.int_lit, (try canon.next()).kind);
    var compat = Lexer.initFamily("# note\n42", "x.id", bridge.family_compat);
    try testing.expectEqual(TokenKind.hash, (try compat.next()).kind);
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
    // `~=` is deliberately absent as an inequality spelling: `~` is XOR, so it
    // lexes bare and the grammar forms `~=` as a compound assignment.
    var l = Lexer.init("== != <= >= << >> // .. ... ## -> :: += -= *= /= %= ^= ~=", "test");
    const expected = [_]TokenKind{
        .eq,          .neq,          .leq,         .geq,          .lshift,         .rshift,
        .idiv,        .concat,       .dots,        .hash_hash,    .arrow,          .dcolon,
        .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign, .caret_assign,
        .tilde,       .assign,
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
    var l = Lexer.init("x", "myfile.id");
    const tok = try l.next();
    try testing.expectEqualStrings("myfile.id", tok.loc.file);
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

test "lex: backtick is a reserved identity then canon refuses it" {
    const bridge = @import("lexer_bridge.zig");
    var producer = Lexer.initFamily("`x", "t.id", bridge.family_canon);
    const bang = try producer.next_tok();
    try testing.expectEqual(TokenKind.backtick, bang.kind);
    try testing.expectEqualStrings("`", bang.text);
    var parser = Lexer.initFamily("`x", "t.id", bridge.family_canon);
    try testing.expectError(error.UnexpectedChar, parser.next());
}

test "lex: shebang is a distinct identity then the program" {
    var l = Lexer.init("#!/usr/bin/env duo\nprint(42)", "test");
    const bang = try l.next_tok();
    try testing.expectEqual(TokenKind.shebang, bang.kind);
    try testing.expectEqualStrings("#!/usr/bin/env duo", bang.text);
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("print", tok.text);
    try testing.expectEqual(@as(u32, 2), tok.loc.line);
}

test "lex: long dash comment is a distinct compat identity then the program" {
    var l = Lexer.init("--[[note]]\nprint(42)", "test");
    const note = try l.next_tok();
    try testing.expectEqual(TokenKind.compat_long_comment, note.kind);
    try testing.expectEqualStrings("--[[note]]", note.text);
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("print", tok.text);
}

test "lex: dash comment is a distinct compat identity then the program" {
    var l = Lexer.init("-- note\nprint(42)", "test");
    const note = try l.next_tok();
    try testing.expectEqual(TokenKind.compat_comment, note.kind);
    try testing.expectEqualStrings("-- note", note.text);
    const tok = try l.next();
    try testing.expectEqual(TokenKind.name, tok.kind);
    try testing.expectEqualStrings("print", tok.text);
    try testing.expectEqual(@as(u32, 2), tok.loc.line);
}

test "lex: comment is a distinct identity then the program" {
    var l = Lexer.initFamily("# note\nprint(42)", "test", @import("lexer_bridge.zig").family_canon);
    const note = try l.next_tok();
    try testing.expectEqual(TokenKind.comment, note.kind);
    try testing.expectEqualStrings("# note", note.text);
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

test "decode_lua_short_string: decimal escapes \\0 and \\65" {
    // There was no decimal-escape case at all, so `\0` fell through to the
    // "unknown escape" fallback, which DROPS the backslash and keeps the
    // digit: `"a\0b"` decoded to the three bytes `a`, `0`, `b`. The length is
    // 3 either way, so every `#s`-based assertion in the corpus kept passing
    // while the NUL it was testing had silently become an ASCII zero.
    const nul = try Lexer.decode_lua_short_string(testing.allocator, "a\\0b");
    defer testing.allocator.free(nul);
    try testing.expectEqualStrings(&[_]u8{ 'a', 0, 'b' }, nul);

    const cap_a = try Lexer.decode_lua_short_string(testing.allocator, "\\65");
    defer testing.allocator.free(cap_a);
    try testing.expectEqualStrings("A", cap_a);

    // At most three digits, and the next digit is literal text.
    const bounded = try Lexer.decode_lua_short_string(testing.allocator, "\\0653");
    defer testing.allocator.free(bounded);
    try testing.expectEqualStrings("A3", bounded);
}

test "decodeText: \\{ and \\} are the literal brace, and the map says which bytes" {
    const alloc = testing.allocator;
    // `docs/text-law.md` — the ruled spelling. The BYTES are unremarkable; the
    // whole content of the ruling is the flag stamped beside them, because
    // `desugar_string_interpolation` has nothing else to read: after decoding,
    // `\{` and `{` are both 0x7B.
    var protected: std.ArrayList(bool) = .empty;
    defer protected.deinit(alloc);
    const out = try Lexer.decodeText(alloc, "a\\{b{c\\}d}", &protected);
    defer alloc.free(out);
    try testing.expectEqualStrings("a{b{c}d}", out);
    try testing.expectEqual(out.len, protected.items.len);
    //                            a      {     b      {      c     }      d      }
    const want = [_]bool{ false, true, false, false, false, true, false, false };
    try testing.expectEqualSlices(bool, &want, protected.items);
}

test "decodeText: the map is co-indexed through multi-byte and zero-byte escapes" {
    const alloc = testing.allocator;
    // The two shapes that break a naive one-flag-per-append implementation:
    // `\u{...}` appends FOUR bytes for one escape, and `\z` appends NONE. A map
    // that drifts by one here is worse than no map — it would move the
    // protection onto the wrong brace and silently change what a literal
    // prints, which is the class this whole ruling exists to close.
    var protected: std.ArrayList(bool) = .empty;
    defer protected.deinit(alloc);
    const out = try Lexer.decodeText(alloc, "\\u{1F600}\\z   {", &protected);
    defer alloc.free(out);
    try testing.expectEqual(@as(usize, 5), out.len); // 4 bytes of emoji + `{`
    try testing.expectEqual(out.len, protected.items.len);
    try testing.expectEqualSlices(bool, &[_]bool{ true, true, true, true, false }, protected.items);
}

test "decodeText: an undeclared escape is REFUSED, not silently unwrapped" {
    // `src/main.zig` ships a diagnostic declaring the escape set CLOSED. The
    // implementation did not honour it: the trailing `else =>` dropped the
    // backslash, so `print("A[\q]")` printed `A[q]`. That fail-open fallback is
    // what made `\{` unsafe to name — a program could cross from "hole" to
    // "literal text" with no word from the compiler. Fail-closed.
    try testing.expectError(
        error.InvalidEscape,
        Lexer.decode_lua_short_string(testing.allocator, "A[\\q]"),
    );
    // And the members that ARE declared still decode, so the refusal is not a
    // blanket one.
    const ok = try Lexer.decode_lua_short_string(testing.allocator, "\\n\\t\\\\\\{\\}");
    defer testing.allocator.free(ok);
    try testing.expectEqualStrings("\n\t\\{}", ok);
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
