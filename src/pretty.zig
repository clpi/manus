const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const lexer = @import("lexer.zig");
const grammar_roles = @import("grammar_roles.zig");
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const TypeExpr = ast.TypeExpr;
const Pattern = ast.Pattern;
const Block = ast.Block;
const Module = ast.Module;
const BinOp = ast.BinOp;
const UnOp = ast.UnOp;

pub const Mode = enum {
    idol,
    lua,
};

const Error = error{OutOfMemory};

/// A table every one of whose fields carries a LABEL. Only these can be written
/// offside: an unlabelled sequence written that way is indistinguishable from an
/// executable region, so it keeps an explicit delimiter.
fn allLabelledPack(e: *const Expr) bool {
    if (e.* != .table) return false;
    if (e.table.fields.len == 0) return false;
    for (e.table.fields) |f| switch (f) {
        .named, .indexed => {},
        else => return false,
    };
    return true;
}

pub const SourceComment = struct { line: u32, text: []const u8 };

/// Which spelling of a text literal's bytes the AST being printed carries.
///
/// `docs/text-law.md` rules `\{` and `\}` the literal-brace spelling, and §4.4
/// records the consequence for this file: after `Lexer.decodeText` an escaped
/// brace and a hole brace ARE THE SAME BYTE, so `writeStringLit` cannot tell
/// them apart from contents and must be handed the answer.
pub const LitForm = enum {
    /// `Parser.formatting` was on. `desugar_string_interpolation` left the holes
    /// in place and re-spelled the two things a reprint cannot recover — a
    /// protected brace as `\{` / `\}`, and a backslash byte abutting a brace as
    /// `\\`. A BARE `{` here is therefore a HOLE OPENER and is printed bare.
    source,
    /// The value is fully decoded and holds no source spelling at all — the
    /// post-desugar AST that `formatJitClosureSource` prints from, and every
    /// literal this parser FABRICATES (`.host`: type names, C names, require
    /// paths). Printed exactly as it was before the ruling.
    ///
    /// That is deliberate and it is not "the right answer": a literal brace in
    /// a JIT chunk still reprints bare and would re-open a hole. Closing it
    /// means changing what `duo compile --load-chunk` emits, and this lane has
    /// no oracle for that path. Pinned as a known limit rather than changed
    /// blind — the corpus reprint sweep this lane DID run covers `.source`.
    decoded,
};

fn isVoidType(t: TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "void");
}

/// True when every field of a table literal began on the table's own line —
/// i.e. the source wrote it inline.
fn tableWasInline(t: anytype) bool {
    for (t.fields) |fld| {
        const v: *const Expr = switch (fld) {
            .indexed => |x| x.val,
            .named => |x| x.val,
            .positional => |x| x,
            .spread => |x| x,
            .semantic => |x| x.val,
        };
        if (v.loc().line != t.loc.line) return false;
    }
    return true;
}

/// A statement's source line, for deciding which comments precede it.
fn stmtLine(stmt: *const Stmt) u32 {
    return switch (stmt.*) {
        .brk, .cont => |l| l.line,
        inline else => |v| if (@hasField(@TypeOf(v), "loc")) v.loc.line else 0,
    };
}

pub const PrettyPrinter = struct {
    alloc: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    mode: Mode,
    /// THE SOURCE'S GRAMMAR FAMILY: true when the file this tree came from was
    /// lexed as canonical Idol. It is NOT a user preference and NOT a "style".
    ///
    /// It used to be `--canonical`, a FLAG, defaulted OFF — so `idol fmt` wrote
    /// `fun add(a: i64, b: i64) -> i64 … end` over a file whose source read
    /// `add: i64 = (a: i64, b: i64)`, and the flag that turned that off was
    /// spelled as though it were the special case. Measured over
    /// `gate/fmt.sh`'s twelve files: 145 retired declaration lines from the
    /// default printer, 0 from `--canonical`. A formatter is canonical tooling;
    /// HPLS §94 forbids canonical tooling from generating retired syntax, so
    /// there is no lawful setting of such a flag and it is gone.
    ///
    /// WHICH SPELLINGS THAT ADMITS IS NOT DECIDED HERE — see `writes`.
    canonical: bool = false,
    /// Group EVERY binary operand, so the printed form is a canonical spelling
    /// of the TREE rather than of the source: two expressions print identically
    /// here iff they parsed to the same shape. That is how the round-trip test
    /// compares trees without a structural walker, and it is why idempotence
    /// alone is not the test — a DROPPED parenthesis yields a different tree
    /// that is also a fixed point, so `fmt(fmt(x)) == fmt(x)` cannot see it.
    force_group: bool = false,
    /// Source comments, in source order, so the formatter does not DELETE them.
    ///
    /// Comments never enter the AST — the parser retains no trivia — so a
    /// formatter built only on the AST silently drops every one. That is not a
    /// cosmetic loss: `# expect: 3 10` lines are load-bearing test directives,
    /// and `idol check` cannot notice their absence, so the obvious oracle
    /// passes a file it has gutted.
    ///
    /// They do not need to be in the AST. The lexer already produces `.comment`
    /// tokens and merely SKIPS them on read, so the whole token stream still
    /// holds them with their locations. This is that stream, filtered.
    comments: []const SourceComment = &.{},
    comment_at: usize = 0,
    /// The `#!` line, so the formatter does not DELETE it.
    ///
    /// A shebang is not a comment: the lexer gives it its own token identity
    /// (`.shebang`, only ever at byte zero), so the comment channel above never
    /// carries it and a printer built on that channel drops it. The loss is
    /// silent in the worst way — the file still parses, still checks, still
    /// runs under `idol run`, and has merely stopped being executable.
    shebang: []const u8 = "",
    /// Last source line emitted, so a BLANK LINE in the source survives.
    ///
    /// Blank lines are paragraph structure, not whitespace: reflowing a file
    /// without them fuses every section into one wall.
    last_src_line: u32 = 0,
    /// The lines that are ACTUALLY blank in the source, ascending.
    ///
    /// Inferring them from a gap between statement lines is wrong, and wrongly
    /// in a way that looks right: `return x` on line 3 and `return y` on line 5
    /// are two apart because `else` sits on line 4, so a gap test invents a
    /// blank line inside an if. Only the source knows which lines are empty.
    blank_lines: []const u32 = &.{},
    /// WHICH FORM `quoted.val` IS IN. Not decoration — it decides whether a
    /// `{` in the value is a hole opener or a literal brace, and after decoding
    /// those are the same byte (`law.lexical.one`: the printer is TOLD the role,
    /// it does not reconstruct it from contents).
    ///
    /// `.source` is the default because `do_fmt` — the only production caller of
    /// this printer — always sets `Parser.formatting`, and that path now hands
    /// over a value in source form.
    lit_form: LitForm = .source,
    indent_level: usize,
    indent_str: []const u8,

    pub fn init(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), mode: Mode) PrettyPrinter {
        return .{
            .alloc = alloc,
            .buf = buf,
            .mode = mode,
            .canonical = false,
            .indent_level = 0,
            .indent_str = "  ",
        };
    }

    /// MAY THIS PRINTER WRITE THIS SPELLING? — the ONE authority, asked.
    ///
    /// This printer used to hold a private opinion of which spellings are
    /// retired, expressed as `self.canonical` at each site. That made three
    /// independent copies of one fact: `grammar_roles.compat_only` (which had
    /// ZERO consumers and was therefore scenery under HPLS §7/§8),
    /// `gate/design.sh`'s regex, and this file. Two of them disagreed —
    /// `compat_only` did not know `then`, `end`, `elseif` or `do` were retired,
    /// while this printer and the gate both did — and a fact with two owners
    /// is the demagix shape §94 exists to close.
    ///
    /// A COMPAT-FAMILY SOURCE KEEPS ITS OWN GRAMMAR. Reprinting a Lua file
    /// into the canonical face would not be formatting, it would be
    /// translation, and it is not this function's business to do it silently.
    fn writes(self: *const PrettyPrinter, kind: lexer.TokenKind) bool {
        if (!(self.mode == .idol and self.canonical)) return true;
        return grammar_roles.admits(kind);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    fn write(self: *PrettyPrinter, bytes: []const u8) !void {
        try self.buf.appendSlice(self.alloc, bytes);
    }

    fn print(self: *PrettyPrinter, comptime fmt: []const u8, args: anytype) !void {
        try self.buf.print(self.alloc, fmt, args);
    }

    fn nl(self: *PrettyPrinter) !void {
        try self.write("\n");
        for (0..self.indent_level) |_| try self.write(self.indent_str);
    }

    fn indent(self: *PrettyPrinter) void {
        self.indent_level += 1;
    }

    fn dedent(self: *PrettyPrinter) void {
        self.indent_level -= 1;
    }

    fn writeStringLit(self: *PrettyPrinter, s: []const u8) !void {
        try self.write("\"");
        var skip: usize = 0;
        for (s, 0..) |c, i| {
            if (skip > 0) {
                skip -= 1;
                continue;
            }
            // THE REPRINT MUST NOT UNSPELL THE ESCAPE. In `.source` form every
            // backslash arrives as a TWO-BYTE RUN whose second byte says what
            // it escapes: `\\` a backslash, `\{` / `\}` a LITERAL BRACE. Both
            // are written straight out. Falling through to the `'\\'` prong
            // below would print `\\{` for a literal brace, which decodes to a
            // backslash followed by A HOLE OPENER — a formatter that changes
            // what a program prints, the class `gate/fmt.sh` was built for
            // after `idol fmt` changed the answer of three programs.
            //
            // For every literal with no protected brace this emits exactly what
            // the old code emitted: a doubled `\\` in, a `\\` out.
            //
            // Guarded on `.source` because a `.decoded` value carries no source
            // spelling: there, `\` then `{` is a genuine backslash beside a
            // genuine brace and each is escaped on its own.
            if (self.lit_form == .source and c == '\\' and i + 1 < s.len and
                (s[i + 1] == '{' or s[i + 1] == '}' or s[i + 1] == '\\'))
            {
                try self.write(s[i .. i + 2]);
                skip = 1;
                continue;
            }
            switch (c) {
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                else => {
                    // A CONTROL BYTE has no printable spelling. Writing it raw
                    // put the byte itself into the source file — a literal NUL
                    // in a `.id` file, which the next reader truncates at or
                    // chokes on. `\ddd` is the escape that can say it.
                    //
                    // Padded to three digits on purpose: `\0` followed by a
                    // literal digit would re-lex as a different code point
                    // (`\0` then `5` reads as `\05`), so the width has to be
                    // fixed whenever a digit could follow.
                    if (c < 32 or c == 127) {
                        const next_is_digit = i + 1 < s.len and
                            s[i + 1] >= '0' and s[i + 1] <= '9';
                        if (next_is_digit) {
                            try self.print("\\{d:0>3}", .{c});
                        } else {
                            try self.print("\\{d}", .{c});
                        }
                    } else try self.write(&[_]u8{c});
                },
            }
        }
        try self.write("\"");
    }

    /// Print a string literal in the QUOTE IT WAS WRITTEN IN.
    ///
    /// The quote is not decoration, it selects the literal's law:
    ///
    ///   `"..."`  text  — escapes are processed AND `{name}` interpolates
    ///   `'...'`  bytes — raw; no escape processing, no interpolation
    ///   `[[..]]` long  — raw; no escape processing, no interpolation
    ///
    /// Reprinting everything as `"..."` preserves the BYTES (the printer
    /// re-escapes correctly) but not the MEANING: `'hole {y}'` prints those
    /// eight characters, while `"hole {y}"` substitutes the value of `y`. The
    /// file still checks, and prints something else.
    fn writeStringLitQuoted(self: *PrettyPrinter, x: anytype) !void {
        switch (x.quote) {
            .bytes => {
                // Raw between the quotes. The body came from between two `'`,
                // so it cannot itself contain an unescaped `'`.
                try self.write("'");
                try self.write(x.val);
                try self.write("'");
            },
            .compat_long => {
                // Pick a bracket level whose closer does not occur in the body.
                var level: usize = 0;
                while (level < 8) : (level += 1) {
                    var close: [10]u8 = undefined;
                    close[0] = ']';
                    for (0..level) |k| close[1 + k] = '=';
                    close[1 + level] = ']';
                    if (std.mem.indexOf(u8, x.val, close[0 .. level + 2]) == null) break;
                }
                try self.write("[");
                for (0..level) |_| try self.write("=");
                try self.write("[");
                try self.write(x.val);
                try self.write("]");
                for (0..level) |_| try self.write("=");
                try self.write("]");
            },
            // `.text` and `.compat_text` hold a DECODED value; `.host` is a
            // fabricated byte sequence with no source quote. Both are spelled
            // with the text quote, which is what `writeStringLit` escapes for.
            else => try self.writeStringLit(x.val),
        }
    }

    // ── Type expressions ──────────────────────────────────────────────────────

    pub fn printTypeExpr(self: *PrettyPrinter, t: TypeExpr) !void {
        switch (t) {
            .inferred => {},
            // A C type written in type position is DESUGARED AT PARSE TIME into
            // the marker name `__c_type:void` (`parse_type_primary`), and the
            // printer wrote that marker out as if it were an identifier. The
            // reprint then read `*__c_type:void` as a pointer to an unknown
            // name followed by a stray `:` and did not compile — the same
            // "a parse-time desugar is invisible to a formatter" class as the
            // anchor, interpolation and the `@`-directives, in the one position
            // nothing had checked. Recovering the written spelling is the whole
            // fix; `types.c_type_marker_prefix` is the single place the shape
            // is defined, so this asks it rather than restating it.
            .named => |n| {
                if (std.mem.startsWith(u8, n, types.c_type_marker_prefix)) {
                    try self.print("@c.type(\"{s}\")", .{n[types.c_type_marker_prefix.len..]});
                } else {
                    try self.write(n);
                }
            },
            .array => |a| {
                try self.write("[");
                if (a.size) |sz| try self.print("{d}", .{sz});
                try self.write("]");
                try self.printTypeExpr(a.elem.*);
            },
            .pointer => |p| {
                try self.write("*");
                try self.printTypeExpr(p.*);
            },
            .func => |f| {
                try self.write("(");
                for (f.params, 0..) |param, i| {
                    if (i > 0) try self.write(", ");
                    try self.printTypeExpr(param);
                }
                try self.write(") -> ");
                try self.printTypeExpr(f.ret.*);
            },
            .optional => |o| {
                try self.write("?");
                try self.printTypeExpr(o.*);
            },
            .generic => |g| {
                try self.printTypeExpr(g.base.*);
                try self.write("<");
                for (g.params, 0..) |param, i| {
                    if (i > 0) try self.write(", ");
                    try self.printTypeExpr(param);
                }
                try self.write(">");
            },
            .record => |r| {
                try self.write("{ ");
                for (r.fields, 0..) |fld, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{s}: ", .{fld.name});
                    try self.printTypeExpr(fld.typ);
                }
                try self.write(" }");
            },
            .constrained => |cp| {
                try self.write(cp.name);
                try self.write(": ");
                try self.printTypeExpr(cp.constraint.*);
                for (cp.extra) |extra| {
                    try self.write(" + ");
                    try self.printTypeExpr(extra);
                }
            },
            .tuple => |elems| {
                try self.write("(");
                for (elems, 0..) |elem, i| {
                    if (i > 0) try self.write(", ");
                    try self.printTypeExpr(elem);
                }
                try self.write(")");
            },
        }
    }

    // ── Expressions ─────────────────────────────────────────────────────────────

    // ── Grouping ──────────────────────────────────────────────────────────────
    //
    // GROUPING IS THE AUTHOR'S. A formatter normalises LAYOUT; it does not
    // relitigate what the author grouped. So the printer KEEPS the grouping of
    // every operator application it prints under another operator, and never
    // asks whether the parentheses are "needed".
    //
    // WHERE THE PARENTHESES COME FROM, and the two wrong answers that decided
    // it. The printer used to carry its OWN table of operator precedences and
    // drop parentheses it judged redundant — and that table DISAGREED with the
    // parser's (`grammar_roles`, read by `infix_prec`). It ranked `<<`/`>>`
    // above `+`/`-`; the grammar ranks them below. So `(1 << w) - 1` reprinted
    // as `1 << w - 1`, which reparses as `1 << (w - 1)`: 15 became 8, and
    // `idol check` reported no errors. Associativity was ignored on top of
    // that, so `10 - (3 - 2)` reprinted as `10 - 3 - 2`: 9 became 5.
    //
    // The first repair deleted the model and parenthesized EVERY operand. That
    // is sound and it is what shipped, but it buys soundness with syntax the
    // language does not need, and HPLS is minimum programmer-imposed syntax:
    // `idol fmt` rewrote `i % 15 != 0 and i % 3 == 0` as
    // `((i % 15) != 0) and ((i % 3) == 0)` in 128 corpus files, and
    // `gate/fmt.sh` could not see it, because that gate asks whether ANSWERS
    // moved and inert parentheses do not move an answer.
    //
    // The disease was never "a model". It was TWO models that had to agree.
    // There are three cures — delete one, keep both and test agreement, or make
    // the second CONSULT the first — and only the third gets both properties.
    // So the printer now reads binding powers out of `grammar_roles`, which is
    // the parser's own authority and not a copy of it, through `childBounds`.
    // There is still exactly one precedence model in the compiler; the printer
    // is now a reader of it rather than a rival to it.
    //
    // Two things pin this, because a derivation is what produced the original
    // wrong answers and a derivation is not evidence. `tokenFor` is pinned
    // against `Parser.infixBinOp` so the spelling map cannot drift, and the
    // round-trip test below prints every operator pair in both nestings,
    // reparses, and compares the trees — 1,300 shapes, so a bound that is
    // wrong anywhere is a failing test rather than a silently wrong program.
    //
    // What this cannot recover: parentheses that were ALREADY redundant in the
    // source, like `(a) + b` or `((x))`. Those never reach the printer — the
    // parser builds no node for a grouping that does not change the tree, so
    // by the time anything is printed the information is gone. See the report
    // accompanying this change.

    /// `parent_prec` is a BOUND, not an index. Low bits carry the largest LEFT
    /// binding power a binary operand may have here and still be read back as
    /// its own node: a binop child is grouped iff its own left binding power is
    /// `<=` the bound. Precedences run 2..23, so a bound of 0 groups nothing
    /// and `bound_always` (127) groups everything.
    const prec_mask: u8 = 0x7f;
    /// Set where a UNARY operand needs grouping regardless of the bound.
    const unary_parens_bit: u8 = 0x80;

    /// Free position: nothing above this expression binds it.
    const free_position: u8 = 0;
    /// The bound no operator can clear — the refusal path for an operator the
    /// grammar gives no associativity, where there is no binding power to
    /// reason from and grouping is the only answer that cannot be wrong.
    const bound_always: u8 = prec_mask;
    /// Under `^` or a prefix operator — the two places that bind TIGHTER than
    /// a prefix operator does, so a unary operand needs grouping there too.
    /// `(-2) ^ 2` is 4; `-2 ^ 2` is -4, because the parser reads a prefix
    /// operand with `parse_prec(20)` and `^` is 23, so `^` wins. 20 is that
    /// same `parse_prec(20)`, so a binop operand is grouped here on exactly
    /// the condition the parser would re-associate it.
    const tight_operand_position: u8 = unary_parens_bit | 20;

    /// Which token an operator is written with — INVERTED from the grammar
    /// owner, not authored beside it.
    ///
    /// This was 24 hand-written arms whose only job was to agree with
    /// `Parser.infixBinOp`'s 24 arms, and a test existed solely to check that
    /// agreement. Both maps are now one fact in `lib/compiler/token.id`:
    /// the row that gives `.plus` its binding power is the row that says
    /// `.plus` writes `add`, so the inverse is a derivation and the two
    /// cannot disagree. Totality and injectivity are enforced at COMPILE
    /// TIME below, so an operator the owner names no token for, or two
    /// identities claiming one relation, is a build failure rather than a
    /// silently wrong parenthesis.
    fn tokenFor(op: BinOp) lexer.TokenKind {
        return infix_token[@backingInt(op)];
    }

    const relation_count = @typeInfo(BinOp).@"enum".field_names.len;

    const infix_token: [relation_count]lexer.TokenKind = blk: {
        var m: [relation_count]lexer.TokenKind = undefined;
        var named: [relation_count]bool = @splat(false);
        for (grammar_roles.rows) |r| {
            const kind = r.kind orelse continue;
            if (!r.infix) continue;
            const rel = r.relation orelse continue;
            const i = @backingInt(rel);
            if (named[i]) @compileError("two token identities claim one infix relation");
            named[i] = true;
            m[i] = kind;
        }
        for (named, 0..) |ok, i| {
            if (!ok) @compileError("the grammar owner names no infix token for " ++ @typeInfo(BinOp).@"enum".field_names[i]);
        }
        break :blk m;
    };

    /// The bounds for an operator's two operands, derived from `grammar_roles`
    /// the same way `Parser.infix_prec` derives the parser's binding powers.
    ///
    /// A child is grouped iff its left binding power is `<=` its side's bound,
    /// which is the parser's own `if (inf.left <= min_prec) break;` read
    /// backwards. Equal precedence groups on the side associativity does NOT
    /// favour: `a - (b - c)` keeps its parentheses because `-` is left, and
    /// `a ^ b ^ c` drops them because `^` is right.
    fn childBounds(op: BinOp) struct { lhs: u8, rhs: u8 } {
        const r = grammar_roles.lookup(tokenFor(op));
        if (r.assoc == .none) return .{ .lhs = bound_always, .rhs = bound_always };
        const p: u8 = @intCast(r.precedence);
        return .{
            .lhs = if (r.assoc == .left) p - 1 else p,
            .rhs = if (r.assoc == .right) p - 1 else p,
        };
    }

    fn printExpr(self: *PrettyPrinter, expr: *const Expr, parent_prec: u8) Error!void {
        const needs_parens = switch (expr.*) {
            .binop => |b| blk: {
                if (self.force_group) break :blk true;
                const r = grammar_roles.lookup(tokenFor(b.op));
                if (r.assoc == .none) break :blk true;
                break :blk @as(u8, @intCast(r.precedence)) <= (parent_prec & prec_mask);
            },
            .unop => (parent_prec & unary_parens_bit) != 0,
            // AN IF-EXPRESSION IS AMBIGUOUS WITH AN IF-STATEMENT. Written bare
            // at the head of a line — which is exactly where a function's tail
            // expression goes — `if c == 1 10 else 20 end` is read as a
            // statement, and the parser then wants a block where the value is:
            // "expected expression, got 'else'".
            //
            // `gate/match.id` reached that state without any `if` in the
            // source: `c:match` desugars to an if-expression chain at PARSE
            // time, so the printer, which sees only the desugared tree, emitted
            // a face the parser cannot read back. The grouping removes the
            // ambiguity in every position, so it is written in every position.
            .if_expr => true,
            else => false,
        };

        if (needs_parens) try self.write("(");
        switch (expr.*) {
            .nil => try self.write("nil"),
            .true_lit => try self.write("true"),
            .false_lit => try self.write("false"),
            .int_lit => |x| try self.print("{d}", .{x.val}),
            .float_lit => |x| {
                if (x.val == @floor(x.val)) {
                    try self.print("{d:.1}", .{x.val});
                } else {
                    try self.print("{d}", .{x.val});
                }
            },
            .quoted => |x| try self.writeStringLitQuoted(x),
            .vararg => try self.write("..."),

            .name => |x| {
                // THE SIGIL IS THE ACCESS, so it is part of the spelling and
                // the printer owes it back. gap[223] is the standing lesson
                // here: a printer that drops half of an `@` face turns a legal
                // file into one the parser refuses. `@x` reprinted as `x` would
                // be worse than illegal — it would still compile, and resolve
                // against the lexical scope this face exists to bypass.
                if (x.world) try self.write("@");
                try self.write(x.ident);
            },
            .quote => |x| {
                try self.write("`");
                try self.printExpr(x.expr, 0);
            },
            .unquote => |x| {
                try self.write(",");
                try self.printExpr(x.expr, 0);
            },
            .macro_call => |x| {
                try self.print("@{s}(", .{x.name});
                for (x.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(arg, 0);
                }
                try self.write(")");
            },
            .sequence => |x| {
                for (x.exprs, 0..) |sub, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(sub, 0);
                }
            },
            .semantic => |x| try self.print("@{s}", .{x.op}),
            .semantic_scope => try self.write("@"),
            .index => |x| {
                // `[]` IS COMPUTED PROJECTION AND `()` IS ORDINARY APPLICATION.
                // They are DIFFERENT operators under the current law, so `a[i]`
                // prints as `a[i]` in every mode, canonical family included.
                //
                // This site used to write `(`/`)` in the canonical face, on the
                // retired ruling that `a[i]` canonicalizes to `a(i)` (762e2bff).
                // That ruling is gone: call-shaped indexing is REFUSED now —
                // `DNB001 assign-target` for a write, `DNB011
                // unresolved-application-facts` for a read — so the rewrite made
                // `idol fmt` turn a compiling program into a non-compiling one.
                // Measured on idol 05882930: `w: [4]i64 = {1,2,3,4}` /
                // `w[2] = 9` compiled, `idol fmt` reprinted it as `w(2) = 9`,
                // and the same file then refused with DNB001. A formatter that
                // breaks the build is not formatting, and HPLS §94 forbids
                // canonical tooling from generating retired syntax.
                //
                // THE REVERSE REWRITE IS NOT DONE HERE EITHER. `do_fmt` runs the
                // lexer and the parser and nothing else — no sema, no type_map —
                // so a `.call` node carries no fact about whether its callee is a
                // pack or a relation. `table_apply.normalizeModule` can converge
                // `t(key)` onto `.index` only because the COMPILE path hands it
                // `sem.type_map`. Without types, `f(x)` is a genuine application
                // and an index in the same shape, and rewriting on a guess would
                // turn a relation call into a projection. The printer leaves
                // `.call` alone; a stale `a(i)` is the compiler's diagnostic to
                // raise, not the formatter's to silently reinterpret.
                try self.printExpr(x.obj, bound_always);
                try self.write("[");
                try self.printExpr(x.key, 0);
                try self.write("]");
            },
            .field => |x| {
                try self.printExpr(x.obj, bound_always);
                // `a@b` and `a.b` are the same node; `anchored` is the only
                // record of which was written, and they are different
                // operators.
                try self.print("{s}{s}", .{ if (x.anchored) "@" else ".", x.field });
            },
            .call => |x| {
                try self.printExpr(x.func, bound_always);
                // APPLY-ONE, gap[092] — c0 §44a trap 2 is "braces as sugar",
                // and writing `(` here unconditionally made the canonical
                // FORMATTER a source-level implementation of it: every
                // `f{ … }` came back as `f({ … })`, so the brace face could not
                // survive a round trip through the repo's own tool. Until the
                // parser half this printer could not have avoided it — both
                // faces recorded `parenless` and the tree held nothing to tell
                // them apart. It now states the face, and this reads it.
                if (x.form == .braced and x.args.len == 1 and
                    x.args[0].* == .table and x.args[0].table.pack.applied)
                {
                    try self.printExpr(x.args[0], 0);
                    return;
                }
                try self.write("(");
                for (x.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(arg, 0);
                }
                try self.write(")");
            },
            // A POSTFIX RECEIVER IS DELIMITED, NOT RANKED. The parentheses in
            // `(2 * math.pi / 3):sin()` are not operator grouping — they say
            // where the receiver ENDS, and no binding power expresses that,
            // because `:sin()` binds to the primary on its left whatever the
            // precedences are. Dropping them re-reads the call as `3:sin()`.
            //
            // This was safe to leave at `free_position` only while every binop
            // operand was parenthesized anyway. `lib/math/interpolate.id` is
            // where the corpus A/B caught it: 1 file of 987 moved its tree, and
            // it was this. `bound_always` groups any operator here.
            .method_call => |x| {
                try self.printExpr(x.obj, bound_always);
                try self.print(":{s}(", .{x.method});
                for (x.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(arg, 0);
                }
                try self.write(")");
            },
            .binop => |x| {
                const bounds = childBounds(x.op);
                // `^` keeps the unary bit on BOTH sides: it is the one operator
                // that binds tighter than a prefix operator, so `-2 ^ 2` is -4.
                const tight: u8 = if (x.op == .pow) unary_parens_bit else 0;
                try self.printExpr(x.lhs, tight | bounds.lhs);
                const op_str = switch (x.op) {
                    .add => " + ",
                    .sub => " - ",
                    .mul => " * ",
                    .div => " / ",
                    .idiv => " // ",
                    .mod => " % ",
                    .pow => " ^ ",
                    .band => " & ",
                    .bor => " | ",
                    .bxor => " ~ ",
                    .lshift => " << ",
                    .rshift => " >> ",
                    .concat => " .. ",
                    .eq => " == ",
                    .neq => " != ",
                    .lt => " < ",
                    .gt => " > ",
                    .leq => " <= ",
                    .geq => " >= ",
                    .@"and" => " and ",
                    .@"or" => " or ",
                    .contains => " in ",
                    .matmul => " @ ",
                    .pipeline => " |> ",
                };
                try self.write(op_str);
                try self.printExpr(x.rhs, tight | bounds.rhs);
            },
            .unop => |x| {
                // `@` IS NOT A PREFIX OPERATOR YOU CAN JUXTAPOSE. It parses by
                // the DELIMITER, not by adjacency: `@` followed by a name reads
                // as a directive path, and `@` followed by a number does not lex
                // at all. So printing the operand bare gave `@64` for `@(64)` and
                // `@comp.for(…)` for `@(@comp.for(…))` — reprints the parser will
                // not take back. The delimiter is part of the spelling and has to
                // be reprinted with it.
                //
                // gap[223]. A table operand USED TO TAKE A SECOND ARM that wrote
                // the sigil bare, on the reasoning that "the brace IS the
                // delimiter here, and wrapping it in parens would change which
                // reader gets it (`parse_pack` with the elided stance, not a
                // table literal inside a comptime eval)". `law.injection.only`
                // retired that reader: fd85e7b8 made `parse_macro_call_expr`
                // refuse a glued `{` outright, so there is no elided stance left
                // for the bare form to preserve — and the arm went on printing it
                // anyway. `x = @({ a = 1 })` checked clean, formatted to
                // `x = @{ a = 1 }`, and then refused with "injection '@{ … }' has
                // no derived-world fact yet". The canonical formatter converted a
                // legal file into an illegal one, which is the corruption mode
                // GAP-203 named in advance when it said closing the parser half
                // alone would do exactly this.
                //
                // TWO SPELLINGS, ONE NODE, AND THE PRINTER OWES BACK THE ONE
                // THAT WAS WRITTEN. `law.stage.world` rules `@(expr)` and
                // `expr@{ stage = compile }` the same meaning — the current
                // world applied to an expression — so they build one node and
                // `world_face` carries which face spelled it. Reprinting the
                // world face as the compatibility face would still compile and
                // still mean the same thing, which is why it is a spelling
                // question and not a gap[223] corruption; but `law.md` §16 says
                // what the author wrote is kept and never relitigated by a
                // printer, and a formatter that silently migrates the canonical
                // spelling BACK to the compatibility one is migration pressure
                // pointed the wrong way.
                //
                // The compatibility arm's own history is below. `@` is not a
                // prefix operator you can juxtapose: it parses by the
                // DELIMITER, so printing the operand bare gave `@64` for
                // `@(64)` — a reprint the parser will not take back — and
                // gap[223] is the same failure with a table operand.
                if (x.op == .compile) {
                    if (x.world_face) {
                        try self.printExpr(x.operand, tight_operand_position);
                        try self.write("@{ stage = compile }");
                        return;
                    }
                    try self.write("@(");
                    try self.printExpr(x.operand, 0);
                    try self.write(")");
                    return;
                }
                const op_str = switch (x.op) {
                    .neg => "-",
                    .not => "not ",
                    .len => "#",
                    .bnot => "~",
                    .compile => unreachable,
                };
                try self.write(op_str);
                // A prefix operator's operand keeps its grouping, and a nested
                // prefix does too: `- -x` must not become `--x`.
                try self.printExpr(x.operand, tight_operand_position);
            },
            .func_expr => |f| try self.printFuncBody(f),
            .table => |x| {
                // A table the writer put on ONE line stays on one line.
                // Exploding `{ x = 3, y = 4 }` across four lines is not
                // canonicalisation, it is churn — and across a whole tree it
                // buries the changes that matter in reformatting noise.
                const inline_src = tableWasInline(&x);
                try self.write("{");
                if (x.fields.len > 0) {
                    if (inline_src) try self.write(" ") else {
                        self.indent();
                        try self.nl();
                    }
                    for (x.fields, 0..) |fld, i| {
                        if (i > 0) {
                            try self.write(",");
                            if (inline_src) try self.write(" ") else try self.nl();
                        }
                        switch (fld) {
                            .indexed => |idx| {
                                try self.write("[");
                                try self.printExpr(idx.key, 0);
                                try self.write("] = ");
                                try self.printExpr(idx.val, 0);
                            },
                            .named => |nmd| {
                                try self.print("{s} = ", .{nmd.key});
                                try self.printExpr(nmd.val, 0);
                            },
                            .positional => |pos| try self.printExpr(pos, 0),
                            .spread => |sp| {
                                try self.write("..");
                                try self.printExpr(sp, 0);
                            },
                            .semantic => |sm| {
                                try self.print("@{s}", .{sm.op});
                                if (sm.param) |p| try self.print("({s})", .{p});
                                try self.write(" = ");
                                try self.printExpr(sm.val, 0);
                            },
                        }
                    }
                    if (inline_src) try self.write(" ") else {
                        self.dedent();
                        try self.nl();
                    }
                }
                try self.write("}");
            },
            .list_comp => |x| {
                try self.write("{");
                try self.printExpr(x.value, 0);
                try self.write(" for ");
                if (x.key_name) |key_name| {
                    try self.print("{s}, ", .{key_name});
                }
                try self.print("{s} in ", .{x.value_name});
                try self.printExpr(x.iter, 0);
                if (x.filter) |filter| {
                    try self.write(" if ");
                    try self.printExpr(filter, 0);
                }
                try self.write("}");
            },
            .try_expr => |x| {
                try self.printExpr(x.operand, 0);
                try self.write("?");
            },
            .unwrap_expr => |x| {
                try self.printExpr(x.operand, 0);
                try self.write("!");
            },
            .if_expr => |x| {
                try self.write("if ");
                try self.printExpr(x.cond, 0);
                try self.write(" ");
                try self.printExpr(x.then_expr, 0);
                try self.write(" else ");
                try self.printExpr(x.else_expr, 0);
                try self.write(" end");
            },
            .match_expr => |m| try self.printMatchExpr(m),
            .await_expr => |x| {
                try self.write("await ");
                try self.printExpr(x.operand, 0);
            },
            .contains_expr => |x| {
                // `3` here was an index into the deleted precedence table.
                // Both sides are operands of an infix operator like any other.
                const bounds = childBounds(.contains);
                try self.printExpr(x.lhs, bounds.lhs);
                try self.write(" in ");
                try self.printExpr(x.rhs, bounds.rhs);
            },
            .range => |x| {
                try self.printExpr(x.start, 0);
                if (x.step) |s| {
                    try self.write(" ..<");
                    try self.printExpr(s, 0);
                }
                try self.write(" .. ");
                try self.printExpr(x.end, 0);
            },
        }
        if (needs_parens) try self.write(")");
    }

    // ── Patterns ──────────────────────────────────────────────────────────────

    fn printPattern(self: *PrettyPrinter, pat: Pattern) !void {
        switch (pat) {
            .literal => |l| try self.printExpr(l, 0),
            .binding => |b| {
                if (b.typ) |t| {
                    try self.write("(");
                    try self.write(b.name);
                    try self.write(": ");
                    try self.printTypeExpr(t);
                    try self.write(")");
                } else {
                    try self.write(b.name);
                }
            },
            .variant => |v| {
                try self.print("{s}", .{v.tag});
                if (v.payload) |payload| {
                    try self.write("(");
                    for (payload, 0..) |p, i| {
                        if (i > 0) try self.write(", ");
                        try self.printPattern(p);
                    }
                    try self.write(")");
                }
            },
            .table_destr => |entries| {
                try self.write("{ ");
                for (entries, 0..) |e, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{s}: ", .{e.key});
                    try self.printPattern(e.pat);
                }
                try self.write(" }");
            },
            .array_destr => |items| {
                try self.write("[");
                for (items, 0..) |item, i| {
                    if (i > 0) try self.write(", ");
                    try self.printPattern(item);
                }
                try self.write("]");
            },
            .rest => |name| try self.print("...{s}", .{name}),
            .wildcard => try self.write("_"),
        }
    }

    // ── Match ───────────────────────────────────────────────────────────────────

    /// Close a block.
    ///
    /// The constitution fixes `syntax.block = @{ bound = .offside, close =
    /// false }`: indentation delimits a block and there is NO closing
    /// delimiter. Canonical Idol therefore writes nothing here — the dedent is
    /// the close. The Lua face still needs `end`, and so does the JIT's Lua
    /// emitter, so the terminator survives exactly where it is someone else's
    /// grammar.
    ///
    /// One origin for every block form, so `end` cannot come back for one
    /// construct and not another.
    /// Write a labelled pack as an offside slot region — the canonical face.
    ///
    /// BRACES ARE NOT CANONICAL. Structure comes from layout; `{ … }` survives
    /// only as an explicit disambiguation escape hatch, so the formatter erases
    /// it wherever the layout form is unambiguous — which is exactly the
    /// all-labelled case. An UNLABELLED sequence is not converted: offside
    /// cannot serve there, because an unlabelled region is indistinguishable
    /// from an executable one.
    /// Whether the GRAMMAR admits an offside pack where the printer currently
    /// stands. It does inside a block and it does NOT at module top level:
    ///
    ///     main: i64 = ()              p: { x: i8, y: i64 } =
    ///         p: { x: i8 } =            x = 3
    ///           x = 3                   y = 4
    ///         0
    ///     ✓ checked — no errors       error: expected expression, got '='
    ///
    /// A FORMATTER MUST NEVER EMIT SOURCE THE PARSER REJECTS. Without this the
    /// canonical face rewrote every top-level all-labelled binding into text
    /// that no longer compiled — `fmt --canonical` destroying the program it
    /// was asked to tidy, which is the one failure mode `gate/fmt.sh` exists
    /// for. Kept beside `printOffsidePack` so the printer's admission condition
    /// and the grammar's stay in step; widen this the day the grammar takes the
    /// form at module level, not before.
    fn offsidePackParses(self: *const PrettyPrinter) bool {
        return self.indent_level > 0;
    }

    fn printOffsidePack(self: *PrettyPrinter, e: *const Expr) Error!void {
        // The caller has already written `= `, leaving a trailing space on what
        // is about to become an empty line.
        while (self.buf.items.len > 0 and self.buf.items[self.buf.items.len - 1] == ' ')
            _ = self.buf.pop();
        self.indent();
        for (e.table.fields) |f| {
            try self.nl();
            switch (f) {
                .named => |nm| {
                    try self.print("{s} = ", .{nm.key});
                    if (allLabelledPack(nm.val)) try self.printOffsidePack(nm.val)
                    else try self.printExpr(nm.val, 0);
                },
                .indexed => |ix| {
                    try self.write("[");
                    try self.printExpr(ix.key, 0);
                    try self.write("] = ");
                    try self.printExpr(ix.val, 0);
                },
                else => unreachable,
            }
        }
        self.dedent();
    }

    fn closeBlock(self: *PrettyPrinter) !void {
        if (!self.writes(.kw_end)) return;
        try self.nl();
        try self.write("end");
    }

    fn printMatchExpr(self: *PrettyPrinter, m: *const ast.MatchExpr) !void {
        try self.write("match ");
        try self.printExpr(m.scrutinee, 0);
        self.indent();
        for (m.arms) |arm| {
            try self.nl();
            try self.printPattern(arm.pattern);
            if (arm.guard) |g| {
                try self.write(" if ");
                try self.printExpr(g, 0);
            }
            try self.write(" =>");
            if (arm.body.stmts.len == 1) {
                try self.write(" ");
                try self.printStmt(&arm.body.stmts[0]);
            } else {
                try self.nl();
                self.indent();
                for (arm.body.stmts) |*s| {
                    try self.printStmt(s);
                    try self.nl();
                }
                self.dedent();
            }
        }
        self.dedent();
        try self.closeBlock();
    }

    // ── Statements ──────────────────────────────────────────────────────────────

    fn printStmt(self: *PrettyPrinter, stmt: *const Stmt) Error!void {
        switch (stmt.*) {
            .macro_def => |md| {
                try self.print("macro {s}(", .{md.name});
                for (md.params, 0..) |param, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(param);
                }
                try self.write(") ");
                switch (md.body) {
                    .expr => |expr| {
                        try self.write("`");
                        try self.printExpr(expr, 0);
                    },
                    .block => |block| {
                        try self.write("`do");
                        self.indent();
                        try self.nl();
                        try self.printBlock(&block);
                        self.dedent();
                        try self.closeBlock();
                    },
                }
            },
            .local_decl => |ld| {
                // Attributes go ABOVE the binding, on their own lines, which is
                // where they were written and the only place they re-parse.
                // Trailed after the type they produced
                // `p: { … } @packed @align(8) = …` and, worse,
                // `abs_val: i64 @c.call("printf", …) = …` — a statement-level
                // directive swallowed into the next binding's annotation.
                if (self.mode != .lua) {
                    for (ld.names) |name| {
                        for (name.attributes) |attr| {
                            try self.print("@{s}", .{attr.name});
                            if (attr.args) |args| try self.print("({s})", .{args});
                            try self.nl();
                        }
                    }
                }
                if (self.mode == .lua) {
                    try self.write("local ");
                }
                for (ld.names, 0..) |name, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(name.ident);
                    if (name.typ != .inferred) {
                        try self.write(": ");
                        try self.printTypeExpr(name.typ);
                    }
                    if (self.mode == .lua) {
                        for (name.attributes) |attr| {
                            try self.print(" @{s}", .{attr.name});
                            if (attr.args) |args| try self.print("({s})", .{args});
                        }
                    }
                }
                if (ld.inits.len > 0) {
                    try self.write(" = ");
                    if (ld.inits.len == 1 and self.mode == .idol and self.canonical and
                        self.offsidePackParses() and allLabelledPack(ld.inits[0]))
                    {
                        try self.printOffsidePack(ld.inits[0]);
                    } else {
                        for (ld.inits, 0..) |inits_val, i| {
                            if (i > 0) try self.write(", ");
                            try self.printExpr(inits_val, 0);
                        }
                    }
                }
            },
            .const_decl => |cd| {
                try self.write("const ");
                try self.write(cd.ident);
                if (cd.typ != .inferred) {
                    try self.write(": ");
                    try self.printTypeExpr(cd.typ);
                }
                try self.write(" = ");
                try self.printExpr(cd.val, 0);
            },
            .global_decl => |gd| {
                // Layout attributes are carried on the BINDING, and a global
                // binding carries them just as a local one does. Only the local
                // printer emitted them, so `@packed` / `@align(8)` written above
                // a `global` were dropped and the record silently changed
                // layout — a size and alignment change no type check can see.
                //
                // They are written on their OWN LINES, above the binding, which
                // is where they were written and the only place they re-parse:
                // trailing them after the type produced
                // `p: { … } @packed @align(8) =`, which is not the attribute
                // position.
                for (gd.names) |name| {
                    for (name.attributes) |attr| {
                        try self.print("@{s}", .{attr.name});
                        if (attr.args) |args| try self.print("({s})", .{args});
                        try self.nl();
                    }
                }
                try self.write("global ");
                if (gd.star) try self.write("* ");
                for (gd.names, 0..) |name, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(name.ident);
                    if (name.typ != .inferred) {
                        try self.write(": ");
                        try self.printTypeExpr(name.typ);
                    }
                }
                if (gd.inits.len > 0) {
                    try self.write(" = ");
                    for (gd.inits, 0..) |inits_val, i| {
                        if (i > 0) try self.write(", ");
                        try self.printExpr(inits_val, 0);
                    }
                }
            },
            .assign => |as| {
                for (as.targets, 0..) |t, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(t, 0);
                }
                try self.write(" = ");
                if (as.values.len == 1 and self.mode == .idol and self.canonical and
                    allLabelledPack(as.values[0]))
                {
                    try self.printOffsidePack(as.values[0]);
                } else {
                    for (as.values, 0..) |v, i| {
                        if (i > 0) try self.write(", ");
                        try self.printExpr(v, 0);
                    }
                }
            },
            .call_stmt => |cs| try self.printExpr(cs.expr, 0),
            .expr_stmt => |es| try self.printExpr(es.expr, 0),
            .do_block => |db| {
                if (self.mode == .idol and self.canonical) {
                    for (db.body.stmts) |*s| {
                        try self.printStmt(s);
                        try self.nl();
                    }
                    if (db.body.tail_expr) |te| {
                        try self.printExpr(te, 0);
                        try self.nl();
                    }
                    return;
                }
                try self.write("do");
                try self.printBlock(&db.body);
                try self.closeBlock();
            },
            .while_loop => |wl| {
                try self.write("while ");
                try self.printExpr(wl.cond, 0);
                try self.printBlock(&wl.body);
                try self.closeBlock();
            },
            .repeat_loop => |rl| {
                try self.write("repeat");
                try self.printBlock(&rl.body);
                try self.nl();
                try self.write("until ");
                try self.printExpr(rl.cond, 0);
            },
            .if_stmt => |is| {
                try self.write("if ");
                if (is.binding) |b| {
                    try self.write(b.name);
                    try self.write(" = ");
                    try self.printExpr(b.expr, 0);
                    try self.write(" ");
                }
                try self.printExpr(is.cond, 0);
                if (self.writes(.kw_then)) {
                    try self.write(" then");
                }
                try self.printBlock(&is.then);
                for (is.elseifs) |ei| {
                    try self.nl();
                    // `elseif` is a Lua keyword; the canonical face is
                    // `else(condition)`, proved input-by-input against the
                    // hand-nested form in idol-native/gate/control.id. The
                    // printer was re-emitting `elseif` after every conversion,
                    // so 743 of them kept coming back.
                    if (!self.writes(.kw_elseif)) {
                        try self.write("else(");
                        try self.printExpr(ei.cond, 0);
                        try self.write(")");
                        try self.printBlock(&ei.body);
                        continue;
                    }
                    try self.write("elseif ");
                    try self.printExpr(ei.cond, 0);
                    if (self.writes(.kw_then)) {
                        try self.write(" then");
                    }
                    try self.printBlock(&ei.body);
                }
                if (is.else_body) |eb| {
                    try self.nl();
                    try self.write("else");
                    try self.printBlock(&eb);
                }
                try self.closeBlock();
            },
            .num_for => |nf| {
                try self.write("for ");
                try self.write(nf.var_name);
                if (nf.var_typ != .inferred) {
                    try self.write(": ");
                    try self.printTypeExpr(nf.var_typ);
                }
                try self.write(" = ");
                try self.printExpr(nf.start, 0);
                try self.write(", ");
                try self.printExpr(nf.stop, 0);
                if (nf.step) |step| {
                    try self.write(", ");
                    try self.printExpr(step, 0);
                }
                try self.printBlock(&nf.body);
                try self.closeBlock();
            },
            .gen_for => |gf| {
                try self.write("for ");
                for (gf.vars, 0..) |v, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(v);
                }
                try self.write(" in ");
                for (gf.iters, 0..) |it, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(it, 0);
                }
                try self.printBlock(&gf.body);
                try self.closeBlock();
            },
            .func_decl => |fd| try self.printFuncDecl(&fd),
            .ret => |r| {
                try self.write("return");
                if (r.vals.len > 0) {
                    try self.write(" ");
                    for (r.vals, 0..) |v, i| {
                        if (i > 0) try self.write(", ");
                        try self.printExpr(v, 0);
                    }
                }
            },
            .brk => try self.write("break"),
            .cont => try self.write("continue"),
            .goto_stmt => |g| try self.print("goto {s}", .{g.label}),
            .label_stmt => |l| try self.print("::{s}::", .{l.label}),
            .match_stmt => |m| try self.printMatchExpr(&m),
            .try_stmt => |t| {
                try self.write("try");
                try self.printBlock(&t.body);
                for (t.catches) |catch_clause| {
                    try self.nl();
                    try self.write("catch");
                    if (catch_clause.binding) |b| {
                        try self.print(" {s}", .{b});
                    }
                    try self.printBlock(&catch_clause.body);
                }
                for (t.defers) |defer_stmt| {
                    try self.nl();
                    try self.write("defer");
                    try self.printBlock(&defer_stmt.body);
                }
                try self.closeBlock();
            },
            .defer_stmt => |d| {
                try self.write("defer");
                try self.printBlock(&d.body);
                try self.closeBlock();
            },
            .enum_def => |ed| try self.printEnumDef(&ed),
            .concept_def => |cd| try self.printConceptDef(&cd),
            .alias_def => |ad| {
                for (ad.attributes) |attr| {
                    try self.print("@{s}", .{attr.name});
                    if (attr.args) |args| try self.print("({s})", .{args});
                    try self.nl();
                }
                if (ad.target) |target| {
                    if (target == .record) {
                        // A `..parent` SPREAD has nowhere to live in a record
                        // TYPE, so printing this through `printTypeExpr` — the
                        // bare `{ … }` — silently deleted every inherited
                        // field. `derived: { ..base, y: i64 }` came back as
                        // `derived: { y: i64 }`, and `x` was simply gone.
                        //
                        // So the spread is written out HERE rather than
                        // delegated. It used to be written on the sigil face,
                        // which was then the only one that could spell a
                        // parent; `law.injection.only` retired that face and
                        // the copula reader takes `..parent` directly, so both
                        // arms below are sigil-free and differ only in whether
                        // there is a parent to write.
                        const parents = ad.parent != null or ad.extra_parents.len > 0;
                        if (!parents) {
                            try self.print("{s}: ", .{ad.name});
                            try self.printTypeExpr(target);
                        } else {
                            try self.print("{s}: {{", .{ad.name});
                            var wrote_any = false;
                            if (ad.parent) |p| {
                                try self.print(" ..{s}", .{p});
                                wrote_any = true;
                            }
                            for (ad.extra_parents) |p| {
                                try self.write(if (wrote_any) ", " else " ");
                                try self.print("..{s}", .{p});
                                wrote_any = true;
                            }
                            for (target.record.fields) |fld| {
                                try self.write(if (wrote_any) ", " else " ");
                                try self.print("{s}: ", .{fld.name});
                                try self.printTypeExpr(fld.typ);
                                wrote_any = true;
                            }
                            try self.write(" }");
                        }
                    } else {
                        try self.write("type ");
                        try self.write(ad.name);
                        if (ad.type_params) |tps| {
                            try self.write("<");
                            for (tps, 0..) |tp, i| {
                                if (i > 0) try self.write(", ");
                                try self.printTypeExpr(tp);
                            }
                            try self.write(">");
                        }
                        try self.write(" = ");
                        try self.printTypeExpr(target);
                    }
                } else {
                    try self.print("alias {s}", .{ad.name});
                    if (ad.type_params) |tps| {
                        try self.write("<");
                        for (tps, 0..) |tp, i| {
                            if (i > 0) try self.write(", ");
                            try self.printTypeExpr(tp);
                        }
                        try self.write(">");
                    }
                    if (ad.parent) |p| try self.print(" extends {s}", .{p});
                    self.indent();
                    for (ad.fields) |f| {
                        try self.nl();
                        if (f.is_private) try self.write("_");
                        try self.print("{s}: ", .{f.name});
                        try self.printTypeExpr(f.typ);
                        if (f.default_val) |dv| {
                            try self.write(" = ");
                            try self.printExpr(dv, 0);
                        }
                    }
                    for (ad.methods) |*m| {
                        try self.nl();
                        try self.printFuncDecl(m);
                    }
                    self.dedent();
                    try self.closeBlock();
                }
            },
            .cinclude => |ci| try self.print("@cinclude(\"{s}\")\n", .{ci.header}),
            .directive => |dir| {
                try self.print("@{s}", .{dir.attr.name});
                if (dir.attr.args) |args| try self.print("({s})", .{args});
                try self.nl();
            },
        }
    }

    /// AN EMPTY RELATION BODY IS WRITTEN BY WRITING NOTHING.
    ///
    /// There used to be a `printEmptyBodyAsVoid` here, which emitted the
    /// literal `void` as the body of a relation whose block was empty. Its
    /// justification was that "a block closes by dedent, and an empty block has
    /// nothing to dedent from — so it never closes". That premise is no longer
    /// true: `parse_block_open`'s `empty_ok` path makes the ABSENCE of an
    /// indented line the spelling of an empty relation body, so the dedent that
    /// closes every other block closes this one too.
    ///
    /// The premise was false and the output was worse than the shape it
    /// replaced: `noop = ()` / `  void` PASSES `idol check` and is then REFUSED
    /// by the backend — `DNB001 application: unknown missing: void`. A reprint
    /// the compiler will not take back is the same corruption class as the
    /// dropped parentheses, one step later in the pipeline. `printBlock`
    /// already returns immediately on an empty block, so falling through to it
    /// emits the one spelling the parser now accepts: nothing.
    fn printBlock(self: *PrettyPrinter, block: *const Block) Error!void {
        if (block.stmts.len == 0 and block.tail_expr == null) return;
        self.indent();
        for (block.stmts) |*s| {
            try self.nl();
            try self.flushCommentsBefore(stmtLine(s));
            try self.printStmt(s);
        }
        if (block.tail_expr) |te| {
            try self.nl();
            try self.flushCommentsBefore(te.loc().line);
            try self.printExpr(te, 0);
        }
        self.dedent();
    }

    // ── Function declarations ─────────────────────────────────────────────────

    fn printFuncDecl(self: *PrettyPrinter, fd: *const ast.FuncDecl) !void {
        for (fd.attributes) |attr| {
            try self.print("@{s}", .{attr.name});
            if (attr.args) |args| try self.print("({s})", .{args});
            try self.nl();
        }
        if (fd.func.is_async) try self.write("async ");
        if (fd.is_local and self.mode == .lua) {
            try self.write("local ");
        }
        if (self.mode == .lua) {
            try self.write("function");
        } else if (self.writes(.kw_fun)) {
            try self.write("fun");
        }
        if (fd.path.len > 0) {
            // The path is a DOTTED NAME split into segments — `mix.v2` arrives
            // as `{"mix","v2"}`. Joining the segments with a SPACE did not
            // shorten the name, it produced two tokens where the source had one
            // binding: `mix v2`. The file then failed to parse at the file
            // edge, far from the damage.
            //
            // A trailing `:` segment is a METHOD (`obj:m`), which is a
            // different edge from `obj.m` — the receiver is bound. `fd.method`
            // records which, so the last separator has to ask.
            const needs_kw_space = self.mode == .lua or self.writes(.kw_fun);
            if (needs_kw_space) try self.write(" ");
            for (fd.path, 0..) |p, i| {
                if (i > 0) {
                    const last = i == fd.path.len - 1;
                    try self.write(if (fd.method and last) ":" else ".");
                }
                try self.write(p);
            }
        }
        if (self.mode == .idol and self.canonical) {
            // Generic parameters belong to the NAME, not the operand pack:
            // `identity<T>: T = (value: T)`. Writing them after the `=` gave
            // `identity: T = <T>(value: T)`, which does not parse — the binding
            // face moves the result descriptor left, so the type parameters
            // have to travel with the name it now sits beside.
            if (fd.func.type_params) |tps| {
                try self.write("<");
                for (tps, 0..) |tp, ti| {
                    if (ti > 0) try self.write(", ");
                    try self.printTypeExpr(tp);
                }
                try self.write(">");
            }
            // CANONICAL BINDING FACE. A relation is `name: result = (params)`,
            // not `name(params) -> result`. The arrow form is a declaration
            // shape; the binding form is what the canon actually writes, and a
            // formatter that emits the other one cannot be used to canonicalise
            // a tree — it would rewrite every relation in the repo into a face
            // the surface does not use.
            // `void` is INFERRED, not written. A result descriptor is worth
            // stating when it constrains something; `void` constrains nothing —
            // it is what a relation produces when it produces nothing, and the
            // compiler already knows that from the body. Writing it everywhere
            // is noise the reader has to skip, and the canon omits what can be
            // uniquely reconstructed.
            //
            // It stays legal to write, for the case where it is directing the
            // compiler on purpose; the printer just does not add it back.
            //
            // AN EMPTY BODY IS THE EXCEPTION, because "the compiler already
            // knows that from the body" is exactly what stops being true when
            // there is no body. Measured: `noop: void = ()` with an empty body
            // compiles and the program exits 2; drop the `: void` and the same
            // program is refused — `DNB001 relation: noop missing: unspecified`.
            // The result is inferred from the body's last value and an empty
            // body has none, so here the descriptor is the only thing carrying
            // it and dropping it changes what the file means.
            //
            // A QUALIFIED name is the exception, and it is a parse fact, not a
            // taste one. `mix.v2: any = (…)` is not a declaration to the
            // parser: after a dotted path it requires `=` immediately
            // (`try_parse_qualified_func_assign`), so the binding face reads as
            // an annotated expression and the body's block never closes —
            // "this block opened at column 15 is still open at the file edge".
            // For a path the result descriptor therefore stays on the right.
            const qualified = fd.path.len > 1;
            const bodyless = fd.func.body.stmts.len == 0 and fd.func.body.tail_expr == null;
            const write_ret = fd.func.ret_type != .inferred and
                (!isVoidType(fd.func.ret_type) or bodyless);
            if (qualified) {
                try self.write(" = ");
                try self.printFuncParamsOnly(&fd.func);
                if (write_ret) {
                    try self.write(": ");
                    try self.printTypeExpr(fd.func.ret_type);
                }
            } else {
                if (write_ret) {
                    try self.write(": ");
                    try self.printTypeExpr(fd.func.ret_type);
                }
                try self.write(" = ");
                try self.printFuncParamsOnly(&fd.func);
            }
        } else {
            try self.printFuncSig(&fd.func);
        }
        // An empty body prints as no body at all — see `printBlock`.
        try self.printBlock(&fd.func.body);
        try self.closeBlock();
    }

    /// The parameter pack alone — the result descriptor belongs to the binding
    /// in the canonical face, so it is written before the `=`, not after `)`.
    fn printFuncParamsOnly(self: *PrettyPrinter, fb: *const ast.FuncBody) !void {
        // Type parameters are written beside the NAME by the caller; see there.
        try self.write("(");
        for (fb.params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            try self.write(param.name);
            if (param.typ != .inferred) {
                try self.write(": ");
                try self.printTypeExpr(param.typ);
            }
            // The DEFAULT is part of the signature: it is what a caller that
            // omits the argument gets. Dropping it changed the arity the
            // relation accepts, and every call that relied on it stopped
            // compiling — or worse, bound something else.
            if (param.default_val) |dv| {
                try self.write(" = ");
                try self.printExpr(dv, 0);
            }
        }
        if (fb.vararg) {
            if (fb.params.len > 0) try self.write(", ");
            if (fb.vararg_name) |vn| try self.print("...{s}", .{vn}) else try self.write("...");
        }
        try self.write(")");
    }

    pub fn printFuncBody(self: *PrettyPrinter, fb: *const ast.FuncBody) Error!void {
        // Reached ONLY from `.func_expr` — a lambda. A named declaration goes
        // through `printFuncDef`, so nothing here can move a `fun f() … end`.
        if (self.mode == .idol) {
            if (soleExpr(&fb.body)) |sole| {
                // RE-SUGAR THE LENS. `parser.zig` desugars a leading `.name`
                // into the lambda `(__proj_v) __proj_v.name` at PARSE time,
                // so by here the anchor is gone and the printer was faithfully
                // emitting the desugaring. Two things were wrong with that:
                // the generated binder breaks LAW-ONE twice (underscore
                // prefix, and `proj_v` is not one word), and the surface it
                // produced is not Duo grammar, so `duo fmt` output could not
                // be read back. Print the anchor the user wrote.
                if (fb.params.len == 1 and !fb.vararg and
                    std.mem.eql(u8, fb.params[0].name, "__proj_v") and
                    fb.params[0].typ == .inferred and
                    isLensChain(sole))
                {
                    try self.printLensChain(sole);
                    return;
                }
            }
        }
        // EVERY other lambda prints `fun(params) <block> end`.
        //
        // It used to print `|params| expr` for a sole-return body — a FOREIGN
        // closure spelling A2 forbids annexing, which the parser cannot read
        // back — and a bare `(params) <block> end` otherwise, which does not
        // reparse either: `f = (a)` binds a parenthesized expression and the
        // `end` is then orphaned ("expected '<eof>', got 'end'").
        //
        // The one-line `(params) expr` form is NOT the repair, and measurement
        // is why. It parses, so it looks fixed, but at STATEMENT level it
        // parses as a DIFFERENT PROGRAM:
        //
        //   f = fun(a) a + 1 end   ->  (assign f (lambda (params (param a)) (+ a 1)))
        //   f = (a) a + 1          ->  (assign f a) (+ a 1)          TWO statements
        //
        // That is the `is_bare_lambda_head` ambiguity: a single-name group is
        // undecidable without the enclosing statement's base column. Emitting
        // it would push a known-ambiguous shape out of the formatter's own
        // output and into real files — a silent misparse, which is strictly
        // worse than the rejection it replaces. Keeping `fun` keeps the head
        // unambiguous, and it projects IDENTICALLY to the source for both the
        // sole-expression and the multi-statement body.
        // CANONICAL MODE KEEPS IT TOO, and the reasoning above is why. `fun` on
        // a LAMBDA is not a block delimiter — it is the head disambiguator. The
        // canonical pass dropped it along with `then`/`end`/`fun`-on-a-
        // declaration, and the result does not reparse: a lambda passed as a
        // call argument became
        //
        //     @comp.match("…", (m)
        //       m.pattern)
        //
        // whose offside body has no way to close before the `)`. Emitting the
        // one-line form instead would be worse — at statement level it is the
        // known `is_bare_lambda_head` misparse.
        //
        // So this stays until a lambda head has an unambiguous canonical
        // spelling. Declarations are unaffected: `printFuncDef` writes the
        // binding face and never reaches here.
        if (self.mode == .idol) try self.write("fun");
        try self.printFuncSig(fb);
        try self.printBlock(&fb.body);
        // A LAMBDA closes with `end`, in canonical mode too, for the same
        // reason its head keeps `fun`: it is not delimited by layout. A lambda
        // written as a call argument is followed by the call's `)`, so its body
        // has nothing to dedent against — `fun(m)` over `m.pattern)` leaves the
        // body running into the closing paren. `closeBlock` is for blocks the
        // offside rule can close; this is not one of them.
        try self.nl();
        try self.write("end");
    }

    /// The body's SOLE expression, when it has one — the shape the lens
    /// re-sugaring must recognise.
    ///
    /// DEMAND-RETURN: a body's value is its final expression's, so `return e`
    /// and a bare tail `e` are THE SAME BODY. The AST spells that one meaning
    /// two ways, and only these two shapes qualify:
    ///
    ///     stmts = [ret e], tail = null     the explicit spelling
    ///     stmts = [],      tail = e        the offside spelling
    ///
    /// Both must answer, or the lens re-sugaring would fire on one spelling of
    /// a body and not the other. Anything with statements BESIDE the tail is a
    /// real block; `ret` with zero or several values is not a single
    /// expression.
    fn soleExpr(b: *const ast.Block) ?*const ast.Expr {
        if (b.tail_expr) |te| {
            return if (b.stmts.len == 0) te else null;
        }
        if (b.stmts.len == 1 and b.stmts[0] == .ret and b.stmts[0].ret.vals.len == 1) {
            return b.stmts[0].ret.vals[0];
        }
        return null;
    }

    /// True when `e` is exactly the field chain the lens desugaring builds:
    /// a `.field` walk (possibly nested) rooted at the generated `__proj_v`.
    /// Anything else — a call, an index, a different root — is an ORDINARY
    /// lambda a user wrote by hand and must not be re-sugared into an anchor.
    fn isLensChain(e: *const ast.Expr) bool {
        return switch (e.*) {
            .field => |f| switch (f.obj.*) {
                .name => |n| std.mem.eql(u8, n.ident, "__proj_v"),
                .field => isLensChain(f.obj),
                else => false,
            },
            else => false,
        };
    }

    /// Print `.a.b.c` for the verified chain, root first. The root `__proj_v`
    /// itself prints nothing — it IS the anchor.
    fn printLensChain(self: *PrettyPrinter, e: *const ast.Expr) Error!void {
        const f = e.field;
        if (f.obj.* == .field) try self.printLensChain(f.obj);
        try self.write(".");
        try self.write(f.field);
    }

    fn printFuncSig(self: *PrettyPrinter, fb: *const ast.FuncBody) !void {
        if (fb.type_params) |tps| {
            try self.write("<");
            for (tps, 0..) |tp, i| {
                if (i > 0) try self.write(", ");
                try self.printTypeExpr(tp);
            }
            try self.write(">");
        }
        try self.write("(");
        for (fb.params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            try self.write(param.name);
            if (param.typ != .inferred) {
                try self.write(": ");
                try self.printTypeExpr(param.typ);
            }
            // See printFuncParamsOnly: the default is part of the signature.
            if (param.default_val) |dv| {
                try self.write(" = ");
                try self.printExpr(dv, 0);
            }
        }
        if (fb.vararg) {
            if (fb.params.len > 0) try self.write(", ");
            if (fb.vararg_name) |vn| try self.print("...{s}", .{vn}) else try self.write("...");
        }
        try self.write(")");
        if (fb.ret_type != .inferred) {
            try self.write(" -> ");
            try self.printTypeExpr(fb.ret_type);
        }
    }

    // ── Enum ──────────────────────────────────────────────────────────────────

    fn printEnumDef(self: *PrettyPrinter, ed: *const ast.EnumDef) !void {
        for (ed.attributes) |attr| {
            try self.print("@{s}", .{attr.name});
            if (attr.args) |args| try self.print("({s})", .{args});
            try self.nl();
        }
        try self.print("enum {s}", .{ed.name});
        if (ed.type_params) |tps| {
            try self.write("<");
            for (tps, 0..) |tp, i| {
                if (i > 0) try self.write(", ");
                try self.printTypeExpr(tp);
            }
            try self.write(">");
        }
        self.indent();
        for (ed.variants) |variant| {
            try self.nl();
            try self.write(variant.name);
            if (variant.payload) |payload| {
                try self.write("(");
                for (payload, 0..) |pf, i| {
                    if (i > 0) try self.write(", ");
                    if (pf.name) |n| try self.print("{s}: ", .{n});
                    try self.printTypeExpr(pf.typ);
                }
                try self.write(")");
            }
        }
        self.dedent();
        try self.closeBlock();
    }

    // ── Concept ───────────────────────────────────────────────────────────────

    fn printConceptDef(self: *PrettyPrinter, cd: *const ast.ConceptDef) !void {
        for (cd.attributes) |attr| {
            try self.print("@{s}", .{attr.name});
            if (attr.args) |args| try self.print("({s})", .{args});
            try self.nl();
        }
        try self.print("concept {s}", .{cd.name});
        if (cd.type_params) |tps| {
            try self.write("<");
            for (tps, 0..) |tp, i| {
                if (i > 0) try self.write(", ");
                try self.printTypeExpr(tp);
            }
            try self.write(">");
        }
        self.indent();
        for (cd.required_methods) |sig| {
            try self.nl();
            try self.printFuncSigParams(&sig);
        }
        for (cd.required_fields) |fld| {
            try self.nl();
            try self.print("{s}: ", .{fld.name});
            try self.printTypeExpr(fld.typ);
        }
        self.dedent();
        try self.closeBlock();
    }

    fn printFuncSigParams(self: *PrettyPrinter, sig: *const ast.FuncSignature) !void {
        if (self.writes(.kw_fun)) try self.write("fun ");
        try self.write(sig.name);
        try self.write("(");
        for (sig.params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            try self.write(param.name);
            if (param.typ != .inferred) {
                try self.write(": ");
                try self.printTypeExpr(param.typ);
            }
        }
        try self.write(")");
        if (sig.ret_type != .inferred) {
            try self.write(" -> ");
            try self.printTypeExpr(sig.ret_type);
        }
    }

    // ── Module ──────────────────────────────────────────────────────────────────

    /// Emit every comment that belongs above line `line`, at the current
    /// indent. Statement granularity: a comment trailing code on its own line
    /// keeps its place, one that trailed code on a SHARED line moves onto its
    /// own line above it. That is a formatting change, not a loss.
    fn flushCommentsBefore(self: *PrettyPrinter, line: u32) Error!void {
        while (self.comment_at < self.comments.len and self.comments[self.comment_at].line <= line) {
            const c = self.comments[self.comment_at];
            try self.blankIfGap(c.line);
            self.comment_at += 1;
            try self.write(c.text);
            try self.nl();
            self.last_src_line = c.line;
        }
        try self.blankIfGap(line);
        if (line != 0) self.last_src_line = line;
    }

    /// One blank line when the source had at least one here. Collapsed to a
    /// single blank however many there were, which is a formatting decision;
    /// losing them entirely is not.
    fn blankIfGap(self: *PrettyPrinter, line: u32) Error!void {
        if (self.last_src_line == 0 or line == 0) return;
        for (self.blank_lines) |b| {
            if (b > self.last_src_line and b < line) {
                // The caller already emitted a newline AND this line's indent,
                // so the indent is now sitting on what is about to become a
                // blank line. Trim it, break the line, and put the indent back
                // — otherwise the blank keeps trailing spaces and the statement
                // after it starts at column 0. That mis-indent silently
                // reparented statements into the previous relation, and the
                // symptom was a TYPE error ("expected 'Tok', got 'bool'")
                // hundreds of lines away from the blank line that caused it.
                while (self.buf.items.len > 0 and self.buf.items[self.buf.items.len - 1] == ' ')
                    _ = self.buf.pop();
                try self.write("\n");
                for (0..self.indent_level) |_| try self.write(self.indent_str);
                return;
            }
            if (b >= line) return;
        }
    }

    fn flushRemainingComments(self: *PrettyPrinter) Error!void {
        while (self.comment_at < self.comments.len) {
            const c = self.comments[self.comment_at];
            self.comment_at += 1;
            try self.write(c.text);
            try self.nl();
        }
    }

    pub fn printModule(self: *PrettyPrinter, mod: *const Module) !void {
        // The `#!` line is only meaningful at byte zero, so it is written
        // before anything else — including any line-1 comment.
        if (self.shebang.len > 0) {
            try self.write(self.shebang);
            try self.write("\n");
        }
        for (mod.body.stmts) |*stmt| {
            try self.flushCommentsBefore(stmtLine(stmt));
            try self.printStmt(stmt);
            try self.nl();
        }
        if (mod.body.tail_expr) |te| {
            try self.flushCommentsBefore(te.loc().line);
            try self.printExpr(te, 0);
            try self.nl();
        }
        try self.flushRemainingComments();
    }
};

// ── Convenience wrappers ────────────────────────────────────────────────────

pub fn prettyPrint(alloc: std.mem.Allocator, mod: *const Module, mode: Mode) ![]u8 {
    return prettyPrintCanonical(alloc, mod, mode, false);
}

pub fn prettyPrintCanonical(alloc: std.mem.Allocator, mod: *const Module, mode: Mode, canonical: bool) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    var pp = PrettyPrinter.init(alloc, &buf, mode);
    pp.canonical = canonical and mode == .idol;
    try pp.printModule(mod);
    return try buf.toOwnedSlice(alloc);
}

/// Source for `duo compile --load-chunk`: `return function(...) ... end`
pub fn formatJitClosureSource(alloc: std.mem.Allocator, fb: *const ast.FuncBody, mode: Mode) Error![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(alloc);
    var pp = PrettyPrinter.init(alloc, &buf, mode);
    // The JIT prints the POST-DESUGAR AST — `Parser.formatting` was never set,
    // so its string values are fully decoded and carry no source spelling.
    // Printing them as `.source` would read a decoded `\` beside a decoded `{`
    // as the escape `\{` and drop a backslash. See `LitForm`.
    pp.lit_form = .decoded;
    if (fb.upvalues.len > 0) {
        try pp.write("return ");
        if (mode == .idol) try pp.write("fun") else try pp.write("function");
        try pp.write("(");
        for (fb.upvalues, 0..) |uv, i| {
            if (i > 0) try pp.write(", ");
            try pp.write(uv.name);
            if (mode == .idol) {
                if (uv.typ) |t| {
                    if (types.rt_to_type_name(t)) |nm| {
                        try pp.write(": ");
                        try pp.write(nm);
                    }
                }
            }
        }
        try pp.write(")\n");
        try pp.write("  return ");
    } else {
        try pp.write("return ");
    }
    if (mode == .idol) try pp.write("fun") else try pp.write("function");
    try pp.printFuncSig(fb);
    try pp.printBlock(&fb.body);
    try pp.nl();
    try pp.write("end");
    if (fb.upvalues.len > 0) {
        try pp.nl();
        try pp.write("end");
    }
    return try buf.toOwnedSlice(alloc);
}

// ── Tests ───────────────────────────────────────────────────────────────────

const testing = std.testing;

fn parseSource(alloc: std.mem.Allocator, src: []const u8) !Module {
    var lex = @import("lexer.zig").Lexer.init(src, "test");
    var p = @import("parser.zig").Parser.init(&lex, alloc);
    return try p.parse_module();
}

fn expectRoundTrip(alloc: std.mem.Allocator, src: []const u8) !void {
    const mod = try parseSource(alloc, src);
    const out = try prettyPrint(alloc, &mod, .idol);
    defer alloc.free(out);
    if (!std.mem.eql(u8, src, out)) {
        std.debug.print("Round-trip mismatch:\n--- original ---\n{s}\n--- printed ---\n{s}\n", .{ src, out });
        return error.RoundTripMismatch;
    }
}

test "pretty: jit closure source" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseSource(alloc, "local f = function(x)\n    return x\nend\n");
    const expr = mod.body.stmts[0].local_decl.inits[0];
    const fb = switch (expr.*) {
        .func_expr => |f| f,
        else => return error.NotFunction,
    };
    const src = try formatJitClosureSource(alloc, fb, .lua);
    try testing.expect(std.mem.startsWith(u8, src, "return function("));
}

test "pretty: jit closure source with upvalue" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseSource(alloc,
        \\local n = 1
        \\local f = function(x)
        \\    return x + n
        \\end
        \\
    );
    var semantic = @import("sema.zig").Sema.init(alloc);
    defer semantic.deinit();
    try semantic.check_module(&mod);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    const fb = switch (expr.*) {
        .func_expr => |f| f,
        else => return error.NotFunction,
    };
    try testing.expect(fb.upvalues.len > 0);
    const src = try formatJitClosureSource(alloc, fb, .lua);
    try testing.expect(std.mem.indexOf(u8, src, "return function(n)") != null);
    try testing.expect(std.mem.indexOf(u8, src, "return function(x)") != null);
}

test "pretty: simple function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectRoundTrip(arena.allocator(),
        \\fun f() -> i64
        \\  return 1
        \\end
        \\
    );
}

test "pretty: local with type annotation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectRoundTrip(arena.allocator(),
        \\x: i64 = 1
        \\
    );
}

test "pretty: enum definition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectRoundTrip(arena.allocator(),
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\
    );
}

test "pretty: match expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectRoundTrip(arena.allocator(),
        \\match x
        \\  1 => print(1)
        \\  _ => print(0)
        \\end
        \\
    );
}

test "pretty: match normalizes legacy case arms" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseSource(alloc,
        \\match x
        \\  case 1 then print(1)
        \\  case _ then print(0)
        \\end
        \\
    );
    const out = try prettyPrint(alloc, &mod, .idol);
    defer alloc.free(out);
    try testing.expectEqualStrings(
        \\match x
        \\  1 => print(1)
        \\  _ => print(0)
        \\end
        \\
    , out);
}

test "pretty: concept definition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectRoundTrip(arena.allocator(),
        \\concept Sized
        \\  fun size() -> i64
        \\end
        \\
    );
}

test "pretty: canonical mode strips fun, then, and every block terminator" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const mod = try parseSource(alloc,
        \\fun add(x: i64, y: i64): i64
        \\  if x < y then
        \\    return x
        \\  else
        \\    return y
        \\  end
        \\end
        \\
        \\do
        \\  print("hi")
        \\end
        \\
    );
    const out = try prettyPrintCanonical(alloc, &mod, .idol, true);
    defer alloc.free(out);
    // `syntax.block = @{ bound = .offside, close = false }` — indentation
    // delimits and there is no terminator, so no `end` survives canonical
    // output for ANY block form. The dedent before `print` is what closes both
    // the `if` and the relation.
    // The CANONICAL BINDING FACE: a relation is `name: result = (params)`, not
    // `name(params) -> result`. The arrow is a declaration shape; this is what
    // the surface writes, and a formatter emitting the other one could not be
    // used to canonicalise a tree.
    try testing.expectEqualStrings(
        \\add: i64 = (x: i64, y: i64)
        \\  if x < y
        \\    return x
        \\  else
        \\    return y
        \\print("hi")
        \\
        \\
    , out);
}

// ── Information-loss regressions ────────────────────────────────────────────
//
// `idol fmt --canonical` REWRITES THE FILE IN PLACE. Every one of the defects
// below produced a file that still passed `idol check`, which is why they went
// unnoticed: the obvious oracle cannot see a lost sigil, a lost parent, a lost
// default, or a NUL that decayed into the digit `0`. So each test here asserts
// on the REPRINTED BYTES, never on whether the result type-checks.

/// Parse the way `do_fmt` does: canonical family, `formatting` on (so string
/// interpolation is NOT desugared and the literal survives to the printer).
fn parseForFmt(alloc: std.mem.Allocator, src: []const u8) !Module {
    var lex = @import("lexer.zig").Lexer.init(src, "test.id");
    var p = @import("parser.zig").Parser.init(&lex, alloc);
    p.idol_mode = true;
    p.formatting = true;
    return try p.parse_module();
}

fn fmtCanonical(alloc: std.mem.Allocator, src: []const u8) ![]u8 {
    const mod = try parseForFmt(alloc, src);
    return try prettyPrintCanonical(alloc, &mod, .idol, true);
}

/// `fmt` must be a FIXED POINT: whatever it prints, printing that again must
/// give the same bytes. Used by the regressions below so a fix that merely
/// moves the damage one pass later cannot pass.
fn expectIdempotent(alloc: std.mem.Allocator, src: []const u8) !void {
    const once = try fmtCanonical(alloc, src);
    const twice = try fmtCanonical(alloc, once);
    try testing.expectEqualStrings(once, twice);
}

/// The tree's canonical spelling: every operand grouped, so equality of these
/// strings IS equality of the parsed shape.
fn fmtGrouped(alloc: std.mem.Allocator, src: []const u8) ![]u8 {
    const mod = try parseForFmt(alloc, src);
    var buf = std.ArrayList(u8).empty;
    var pp = PrettyPrinter.init(alloc, &buf, .idol);
    pp.canonical = true;
    pp.force_group = true;
    try pp.printModule(&mod);
    return try buf.toOwnedSlice(alloc);
}

test "pretty: every BinOp round-trips through the grammar" {
    // `tokenFor` is no longer a map — it is the compile-time inverse of the
    // grammar owner's `relation` fact, and the parser reads the same fact
    // forward. This is the runtime witness that the two directions compose to
    // the identity, which is the property the deleted pair of hand-written
    // switches could only be TESTED for.
    const Parser = @import("parser.zig").Parser;
    inline for (@typeInfo(BinOp).@"enum".field_names) |nm| {
        const op: BinOp = @field(BinOp, nm);
        const back = Parser.infixBinOp(PrettyPrinter.tokenFor(op));
        try testing.expect(back != null);
        try testing.expectEqual(op, back.?);
    }
}

test "pretty: minimal grouping preserves the tree on every operator pair" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE DERIVATION IS NOT THE EVIDENCE. `childBounds` is read off the
    // parser's loop condition, and reading a loop condition backwards is
    // exactly what produced `1 << w - 1` the first time. So every operator pair
    // is printed in both nestings, reparsed, and the TREES compared — not the
    // strings, and not merely that formatting is a fixed point, which a dropped
    // parenthesis also satisfies.
    const ops = [_][]const u8{
        "+",  "-",  "*",  "/",  "//", "%",  "^",  "&",
        "|",  "~",  "<<", ">>", "==", "!=", "<",  ">",
        "<=", ">=", "and", "or",
    };
    var checked: usize = 0;
    for (ops) |a| {
        for (ops) |b| {
            // Both nestings, spelled with explicit parentheses so the SOURCE is
            // unambiguous whatever the grammar says.
            const srcs = [_][]const u8{
                try std.fmt.allocPrint(alloc, "v = (x {s} y) {s} z\n", .{ a, b }),
                try std.fmt.allocPrint(alloc, "v = x {s} (y {s} z)\n", .{ a, b }),
            };
            for (srcs) |src| {
                // A pair the grammar refuses (nonassoc chains, compat-only
                // spellings) is skipped, not counted — and `checked` below
                // refuses the vacuous pass that skipping everything would be.
                const want = fmtGrouped(alloc, src) catch continue;
                const minimal = fmtCanonical(alloc, src) catch continue;
                const got = fmtGrouped(alloc, minimal) catch |e| {
                    std.debug.print("reparse failed for {s}: {s}\n", .{ minimal, @errorName(e) });
                    return e;
                };
                testing.expectEqualStrings(want, got) catch |e| {
                    std.debug.print("tree moved: {s} -> {s}\n", .{ src, minimal });
                    return e;
                };
                checked += 1;
            }
        }
    }
    // Pinned from below: skipping is allowed, skipping EVERYTHING is not.
    try testing.expect(checked >= 400);
}

test "pretty: parentheses survive when the grammar needs them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // THE ONE THAT CHANGES ANSWERS. The printer carried its own precedence
    // table, and it ranked the shifts ABOVE `+`/`-` while the grammar ranks
    // them below. `(1 << w) - 1` reprinted as `1 << w - 1`, which reparses as
    // `1 << (w - 1)`: 15 became 8, and `idol check` said "no errors".
    const src =
        \\a = (1 << w) - 1
        \\b = (x >> 4) & ((1 << 4) - 1)
        \\c = (a | b) * 2
        \\d = (a + b) << 2
        \\e = (a << 2) + b
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    // The three groupings the grammar NEEDS come back, and only those. `b` and
    // `d` lose theirs because `&` and `<<` rank below the operators inside
    // them, which is the same ranking whose absence produced the original bug —
    // read the other way. `a`, `c` and `e` keep theirs because dropping any one
    // of them re-associates the expression.
    try testing.expectEqualStrings(
        \\a = (1 << w) - 1
        \\b = x >> 4 & (1 << 4) - 1
        \\c = (a | b) * 2
        \\d = a + b << 2
        \\e = (a << 2) + b
        \\
    , out);
    // AND THE TREE DID NOT MOVE — which is the property, where the string above
    // is only its spelling. `fmtGrouped` prints the parsed shape with every
    // operand grouped, so these two agreeing means the reparse of the minimal
    // form is the same tree as the reparse of the author's fully-parenthesized
    // source. Without this line the test pins characters, not meaning.
    try testing.expectEqualStrings(
        try fmtGrouped(alloc, src),
        try fmtGrouped(alloc, out),
    );
    try expectIdempotent(alloc, src);
}

test "pretty: equal-precedence nesting keeps its grouping on either side" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Both children were handed the parent's own precedence, so an
    // equal-precedence child never got parentheses: `10 - (3 - 2)` printed
    // `10 - 3 - 2` (9 became 5) and `100 / (10 / 5)` printed `100 / 10 / 5`
    // (50 became 2). A left-associative operator may share the level only on
    // the LEFT.
    const src =
        \\a = 10 - (3 - 2)
        \\b = 100 / (10 / 5)
        \\c = 10 - (3 + 2)
        \\d = 2 ^ (3 ^ 2)
        \\e = (2 ^ 3) ^ 2
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    // Equal precedence keeps its grouping on the side associativity does NOT
    // favour, and drops it on the side that does. `a`, `b`, `c` are
    // left-associative nested on the RIGHT, so the parentheses are load-bearing
    // and stay. `d` is `^` nested on the right and `^` is RIGHT-associative, so
    // `2 ^ 3 ^ 2` already means `2 ^ (3 ^ 2)` — those parentheses are the only
    // redundant pair here, and they go. `e` is the same operator nested on the
    // left, where they are load-bearing again.
    try testing.expectEqualStrings(
        \\a = 10 - (3 - 2)
        \\b = 100 / (10 / 5)
        \\c = 10 - (3 + 2)
        \\d = 2 ^ 3 ^ 2
        \\e = (2 ^ 3) ^ 2
        \\
    , out);
    try testing.expectEqualStrings(
        try fmtGrouped(alloc, src),
        try fmtGrouped(alloc, out),
    );
    try expectIdempotent(alloc, src);
}

test "pretty: a postfix receiver keeps its grouping" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // THE SECOND ONE THAT CHANGED ANSWERS, and the shipped printer had it too:
    // parentheses around the RECEIVER of a postfix form are not grouping by
    // precedence, they say where the receiver ends. No binding power expresses
    // that, because `:sin()` takes the primary on its left whatever the
    // precedences are. The shipped printer passed `free_position` here —
    // harmless only while every operand was parenthesized anyway — and turned
    //     x / (2:log() * 2:log()):ceil()      one division
    // into
    //     (x / 2:log()) * 2:log():ceil()      a division AND a multiplication
    // in `lib/heap.id`, `lib/math/interpolate.id` and three `scripts/` files.
    const src =
        \\a = (x * y):sin()
        \\b = (x + 1).field
        \\c = (f + g)(1)
        \\d = (t * 2)(i)
        \\e = -a * b:log() / (2:log() * 2:log()):ceil()
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: a unary operand keeps its grouping under ^" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `^` is the one operator that binds tighter than a prefix operator (the
    // parser reads a prefix operand with `parse_prec(20)`, and `^` is 23). So
    // `(-2) ^ 2` is 4 while `-2 ^ 2` is -4, and the grouping has to survive.
    // Elsewhere a unary operand needs no parentheses: nothing can capture it.
    const src =
        \\a = (-2) ^ 2
        \\b = -x * y
        \\c = -(x * y)
        \\d = -(-x)
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: the printer holds no precedence model to disagree with" {
    // The defect was two precedence tables that had to agree and did not. The
    // fix is that the printer has none: grouping is printed, never inferred.
    // If a precedence table reappears here, this is the tripwire.
    // The needles are split so this test does not match its own text.
    const src = @embedFile("pretty.zig");
    try testing.expect(std.mem.indexOf(u8, src, "fn binOp" ++ "Precedence") == null);
    try testing.expect(std.mem.indexOf(u8, src, "fn child" ++ "Floor") == null);
}

test "pretty: a descriptor spread round-trips with no sigil" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `derived: { ..base, y: i64 }` was reprinted `derived: { y: i64 }`.
    // The `..base` spread vanished, so the reprinted record lost field `x`
    // entirely — and still checked clean.
    const src =
        \\Base: { x: i64 }
        \\Derived: { ..Base, y: i64 }
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    // Both faces are sigil-free. The parent-bearing one is written out by hand
    // because `printTypeExpr` has nowhere to put a `..parent`; the one with no
    // parents delegates. Neither may emit `@{` — gate/world/face.sh §4
    // holds that, because a reprint the parser refuses is the defect this whole
    // family of tests exists to catch.
    try testing.expectEqualStrings(
        \\Base: { x: i64 }
        \\Derived: { ..Base, y: i64 }
        \\
    , out);
    try expectIdempotent(alloc, src);
}

test "pretty: a descriptor under an attribute line still parses back" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `@derive(…)` above a descriptor. Reprinting the reprint is the assertion
    // that matters — it is what caught the over-application when the printer
    // still had a sigil face to over-apply.
    const src =
        \\@derive(Display, Eq)
        \\Vec2: { x: f64, y: f64 }
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: gap[223] comptime eval over a pack keeps its parens" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `x = @({ a = 1 })` — comptime eval of an ordinary pack, two live faces
    // composed. It checked clean, and `idol fmt` reprinted it `x = @{ a = 1 }`,
    // which the parser then refused: "injection '@{ … }' has no derived-world
    // fact yet". The canonical formatter turned a legal file into an illegal
    // one, exactly as GAP-203 said closing the parser half alone would.
    //
    // The assertion that matters is the ROUND TRIP, not the spelling. A
    // spelling assertion passes against any printer that happens to avoid the
    // bytes; `expectIdempotent` reprints the reprint, so it can only pass if
    // the parser takes the output back.
    const src =
        \\x = @({ a = 1 })
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try testing.expect(std.mem.indexOf(u8, out, "@{") == null);
    try expectIdempotent(alloc, src);
}

test "pretty: a world access keeps its sigil" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `@x` and `x` are DIFFERENT PROGRAMS wherever a binding of that spelling
    // exists, so dropping the sigil is worse than the gap[223] class it sits
    // next to: the reprint still compiles, and resolves to the binding instead
    // of the world member. Round trip, both in application position and bare.
    const src =
        \\x = @env("HOME")
        \\y = @cwd()
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: the two stage faces are one node and keep their own spelling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `law.stage.world`: `@(expr)` and `expr@{ stage = compile }` are one
    // meaning, so they are one node and `world_face` is the provenance the
    // printer reads. Migrating the canonical face back to the compatibility
    // one still compiles and still means the same thing — which is exactly why
    // only a round trip catches it, and why it matters: a formatter that
    // rewrites the canonical spelling into the retained one is migration
    // pressure pointed backwards.
    const compat =
        \\x = @(1 + 2)
        \\
    ;
    const canon =
        \\x = (1 + 2)@{ stage = compile }
        \\
    ;
    try testing.expectEqualStrings(compat, try fmtCanonical(alloc, compat));
    try testing.expectEqualStrings(canon, try fmtCanonical(alloc, canon));
    try expectIdempotent(alloc, compat);
    try expectIdempotent(alloc, canon);
}

test "pretty: same-fact reinjection collapses in the reprint" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `derive(derive(W, D), D) = derive(W, D)`, applied at FORMATION rather
    // than by a later pass, so the doubled spelling never becomes two worlds.
    // The reprint is where that is observable.
    const src =
        \\x = (1 + 2)@{ stage = compile }@{ stage = compile }
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings("x = (1 + 2)@{ stage = compile }\n", out);
    try expectIdempotent(alloc, out);
}

test "pretty: the empty injection is the identity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `derive(W, {}) = W`. No world is formed, so there is nothing to qualify
    // against and the subject is unchanged — including in the reprint, which
    // must not invent a stage the source did not name.
    const src =
        \\x = 5@{}
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings("x = 5\n", out);
    try testing.expect(std.mem.indexOf(u8, out, "stage") == null);
}

test "pretty: gap[223] the paren arm is still load-bearing for a non-pack" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // NEGATIVE CONTROL on the repair's direction. The two arms were merged
    // toward the PARENTHESISED one; merging them the other way is the older
    // defect, where `@(64)` printed bare gave `@64` — which does not lex — and
    // `@(@comp.for(…))` gave `@comp.for(…)`. Deleting the bare arm must not be
    // read as licence to delete the parens.
    const src =
        \\x = @(64)
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: dotted binding name keeps its dot" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `mix.v2` was reprinted `mix v2` — the path segments were joined with a
    // SPACE. The result is two tokens where there was one binding, and the
    // file then fails to parse at the file edge.
    const src =
        \\mix = {}
        \\mix.v2 = (a: any, t: f64): any
        \\    a
        \\end
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    // A qualified name keeps the result descriptor on the RIGHT: the parser
    // requires `=` straight after a dotted path, so the binding face does not
    // re-parse for this shape.
    try testing.expectEqualStrings(
        \\mix = {}
        \\mix.v2 = (a: any, t: f64): any
        \\  a
        \\
    , out);
    // The reprinted file must itself reprint unchanged. Before the fix it did
    // not even parse: `mix v2` left a block open to the file edge.
    try expectIdempotent(alloc, src);
}

test "pretty: shebang survives formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `#!/usr/bin/env duo` was deleted outright: the shebang is a distinct
    // token identity, so the formatter's comment channel never saw it and the
    // printer had nowhere to put it. An executable script silently stopped
    // being executable.
    const mod = try parseForFmt(alloc, "print(\"ok\")\n");
    var buf: std.ArrayList(u8) = .empty;
    var pp = PrettyPrinter.init(alloc, &buf, .idol);
    pp.canonical = true;
    pp.shebang = "#!/usr/bin/env duo";
    try pp.printModule(&mod);
    try testing.expectEqualStrings(
        \\#!/usr/bin/env duo
        \\print("ok")
        \\
    , buf.items);
}

test "pretty: NUL escape survives the round trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `"a\0b"` was reprinted `"a0b"`. The decoder had no decimal-escape case,
    // so the backslash was dropped and the digit kept; the printer then had no
    // way to spell a NUL back. `#s` stayed 3 either way, so the `# expect: 3`
    // directive kept passing over corrupted data.
    const src =
        \\s = "a\0b"
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: the literal-brace escape survives the round trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `docs/text-law.md` §4.4 — THE PREREQUISITE THAT WOULD HAVE BEEN MISSED.
    // `idol fmt` DELETED the backslash from `"esc \{ brace"`, because
    // `writeStringLit` had no `'{'` case. While `\{` and `{` both meant `{`
    // that was harmless; under the ruling it is a formatter that converts a
    // LITERAL BRACE INTO A HOLE OPENER, which is the `gate/fmt.sh` class.
    //
    // All four readings are in one fixture on purpose, because the three ways
    // to get this wrong each pass a fixture that omits one of them:
    //   * escape only            — an unconditional `'{' => "\\{"` also
    //                              escapes the live hole on line `b`;
    //   * hole only              — the pre-ruling printer;
    //   * both, but not `\\{`    — a printer that reads any `\` before a brace
    //                              as the escape drops line `d`'s backslash;
    //   * both, but not `\\\\`   — a printer that pairs backslashes blindly
    //                              halves line `e`.
    const src =
        \\a = "esc \{ brace"
        \\b = "hole {x} keep"
        \\c = "mixed {x} and \{x\} done"
        \\d = "bs \\{x} live"
        \\e = "two \\\\ backslashes"
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: non-interpolating literals are not requoted into interpolating ones" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `'...'` is the BYTES quote and `[[...]]` the long quote: neither
    // processes escapes and neither interpolates. Reprinting them as `"..."`
    // preserves the bytes but not the MEANING — `'hole {y}'` prints literally,
    // `"hole {y}"` substitutes the value of `y`.
    const src =
        \\a = 'hole {y} here'
        \\b = [[raw {y} here]]
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: global declarations keep their layout attributes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // `local_decl` printed binding attributes; `global_decl` did not, so
    // `@packed` / `@align(8)` on a global were dropped and the record silently
    // changed layout.
    const src =
        \\@packed
        \\@align(8)
        \\global gp: { x: i8, y: i64 } = { x = 1, y = 2 }
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
}

test "pretty: binding attributes stay above the binding, not inside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // A local binding's attributes were trailed after the TYPE:
    // `p: { x: i8 } @packed @align(8) = …`, which is not the attribute
    // position. The same path swallowed a statement-level `@c.call(…)` into
    // the following binding's annotation.
    //
    const src =
        \\@packed
        \\@align(8)
        \\p: { x: i8, y: i64 } = { x = 3, y = 4 }
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);

    // THE CLAIM, asserted directly rather than only inferred from a whole-file
    // match. Each attribute is a line of its own ABOVE the binding...
    try testing.expect(std.mem.indexOf(u8, out, "@packed\n@align(8)\np:") != null);
    // ...and neither is trailed onto the binding line after the type, which is
    // the exact shape the defect produced. These hold however the initializer
    // is spelled, so an unrelated change to the pack's rendering cannot mask a
    // real migration of the attributes back inside the binding.
    try testing.expect(std.mem.indexOf(u8, out, "} @packed") == null);
    try testing.expect(std.mem.indexOf(u8, out, "@align(8) =") == null);

    // THE ROUND TRIP IS ALSO A PARSE CLAIM, and that is why the brace spelling
    // has to come back at TOP LEVEL. Canonical Idol writes an all-labelled pack
    // offside (`printOffsidePack`: braces are a disambiguation escape hatch),
    // but the grammar only takes that form INSIDE A BLOCK — at module level
    //
    //     p: { x: i8, y: i64 } =
    //       x = 3
    //
    // is `error: expected expression, got '='`. Converting here anyway made
    // `fmt --canonical` emit source that no longer compiled. The same binding
    // one scope in is converted, and must be:
    const nested =
        \\main: i64 = ()
        \\  p: { x: i8, y: i64 } =
        \\    x = 3
        \\    y = 4
        \\  0
        \\
    ;
    const nested_out = try fmtCanonical(alloc, nested);
    try testing.expectEqualStrings(nested, nested_out);
    try expectIdempotent(alloc, nested);
    // ...from the brace spelling too, so the canon itself stays covered.
    const nested_braced =
        \\main: i64 = ()
        \\  p: { x: i8, y: i64 } = { x = 3, y = 4 }
        \\  0
        \\
    ;
    try testing.expectEqualStrings(nested, try fmtCanonical(alloc, nested_braced));

    // The other half of the note above, which had no case at all: `@c.call(…)`
    // is a STATEMENT, and it must not be absorbed as the annotation of the
    // binding that follows it.
    const stmt =
        \\@c.call("f", 1)
        \\q: i64 = 7
        \\
    ;
    const stmt_out = try fmtCanonical(alloc, stmt);
    try testing.expectEqualStrings(stmt, stmt_out);
    try expectIdempotent(alloc, stmt);
}

test "pretty: parameter default values survive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Neither parameter printer emitted `default_val`, so every default in the
    // corpus was deleted. Calls that relied on the default then bound nothing.
    const src =
        \\greet: str = (name: str = "World", greeting: str = "Hello")
        \\  greeting
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    try expectIdempotent(alloc, src);
}

test "pretty: a computed projection keeps its brackets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // THE FORMATTER ENFORCED A RETIRED LAW AND BROKE THE BUILD. This printer
    // wrote `(`/`)` for a `.index` node in the canonical face, on the ruling
    // that `a[i]` canonicalizes to `a(i)` (762e2bff). That ruling is retired:
    // `[]` is computed projection, `()` is ordinary application, and
    // call-shaped indexing is REFUSED — `DNB001 assign-target` on a write,
    // `DNB011 unresolved-application-facts` on a read.
    //
    // Measured on idol 05882930, before the fix: the source below compiled,
    // `idol fmt` rewrote both sites to `w(2)`/`w(3)`, and the SAME FILE then
    // refused with DNB001. A formatter is not permitted to turn a compiling
    // program into a non-compiling one, and HPLS §94 forbids canonical tooling
    // from generating retired syntax in those words.
    //
    // Both positions are asserted, because the read and the write reach the
    // printer by different statement paths and only the read had a witness.
    const src =
        \\main: i64 = ()
        \\  w: [4]i64 = { 1, 2, 3, 4 }
        \\  w[2] = 9
        \\  w[2] + w[3]
        \\
    ;
    const out = try fmtCanonical(alloc, src);
    try testing.expectEqualStrings(src, out);
    // The spelling assertion is not redundant with the round trip here: `w(2)`
    // still PARSES, so a printer that emits it is a fixed point too. Only the
    // byte check can see the retired face.
    try testing.expect(std.mem.indexOf(u8, out, "w(2)") == null);
    try testing.expect(std.mem.indexOf(u8, out, "w(3)") == null);
    try expectIdempotent(alloc, src);

    // A GENUINE APPLICATION IS LEFT ALONE. `do_fmt` runs the lexer and the
    // parser and nothing else, so a `.call` carries no fact saying whether its
    // callee is a pack or a relation — `table_apply` can only converge `t(key)`
    // onto `.index` because the compile path hands it `sem.type_map`. Rewriting
    // `()` into `[]` on a guess would turn a relation call into a projection,
    // so the printer does not guess in either direction.
    const app =
        \\id: i64 = (n: i64)
        \\  n
        \\main: i64 = ()
        \\  id(2)
        \\
    ;
    const app_out = try fmtCanonical(alloc, app);
    try testing.expectEqualStrings(app, app_out);
    try testing.expect(std.mem.indexOf(u8, app_out, "id[2]") == null);
    try expectIdempotent(alloc, app);
}
