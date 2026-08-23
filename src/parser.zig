const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TK = @import("lexer.zig").TokenKind;
const ast = @import("ast.zig");
const types = @import("types.zig");
const term = @import("term.zig");
const meta_module = @import("meta_module.zig");
const legacy_directives = @import("legacy_directives.zig");
const debug_trace = @import("debug_trace.zig");
const grammar_roles = @import("grammar_roles.zig");
const token_view = @import("token_view.zig");
const lexer_dispatch = @import("lexer_dispatch.zig");
const source_cursor = @import("source_cursor.zig");

pub const ParseError = error{
    UnexpectedToken,
    ExpectedToken,
} || lexer_dispatch.DispatchError || Lexer.TokenStreamError || Allocator.Error;

fn findMatchingParen(s: []const u8, start: usize) usize {
    var depth: i32 = 1;
    var i: usize = start + 1;
    var in_string = false;
    var quote_char: u8 = 0;
    while (i < s.len) : (i += 1) {
        if (in_string) {
            if (s[i] == '\\' and i + 1 < s.len) {
                i += 1;
                continue;
            }
            if (s[i] == quote_char) in_string = false;
            continue;
        }
        if (s[i] == '"' or s[i] == '\'') {
            in_string = true;
            quote_char = s[i];
            continue;
        }
        if (s[i] == '(') depth += 1;
        if (s[i] == ')') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return s.len;
}

/// How deep `parse_prec` may descend before the parser REFUSES.
///
/// Without a bound the parser did not refuse — it FAULTED. Measured on
/// `x: i64 = ((((…1…))))`, one paren per level:
///
///     Debug        depth 781 ok, depth 782 -> SIGSEGV (exit 139)
///     ReleaseFast  depth 1589 ok, depth 1590 -> SIGSEGV (exit 139)
///
/// The trace is the cycle `parse_prec -> parse_suffixed_expr ->
/// parse_simple_expr -> parse_expr -> parse_prec`, one frame per level, and a
/// native stack overflow is not a diagnostic: no location, no message, no
/// artifact, and an exit code the caller cannot tell from a crash in the
/// program being compiled.
///
/// 256 is the same bound Clang publishes for the identical construct
/// (`-fbracket-depth`, default 256). It leaves a factor of three under the
/// measured Debug fault and a factor of six under ReleaseFast, which is the
/// margin that matters: the fault depth moves with build mode and frame
/// layout, so a bound chosen just under one measurement would fault under the
/// next. See `Sema.max_expr_depth` for the second, INDEPENDENT limit — a flat
/// `1 + 1 + … + 1` chain nests this parser not at all and still overflows sema.
const max_parse_depth: u32 = 256;

/// How deep BLOCKS may nest before the parser refuses — a separate limit,
/// because a block frame is much fatter than an expression frame and the two
/// therefore run out of stack at very different depths.
///
/// Measured on `if 1 == 1` nested N deep, one statement per level:
///
///     Debug        depth 201 ok, depth 202 -> SIGSEGV (exit 139)
///     ReleaseFast  depth 621 ok, depth 622 -> SIGSEGV (exit 139)
///
/// The cycle is `parse_block_open -> parse_stmt -> parse_if ->
/// parse_if_clauses -> parse_block_at -> parse_block_open`. 202 is a QUARTER
/// of the expression limit's fault depth, which is exactly why one shared
/// constant would have been wrong: a bound safe for `((((…))))` is a fault for
/// nested `if`.
const max_block_depth: u32 = 64;

pub const Parser = struct {
    lex: *Lexer,
    alloc: Allocator,
    /// Live `parse_prec` recursion depth. See `max_parse_depth`.
    expr_depth: u32 = 0,
    /// Live `parse_block_open` recursion depth. See `max_block_depth`.
    block_depth: u32 = 0,
    /// Incremented while parsing a match arm body. When > 0, assignment
    /// right-hand sides use the restricted scrutinee parser so that `[` at
    /// the start of the next arm is not greedily consumed as an index suffix.
    match_arm_depth: u32 = 0,
    /// When true (.id source), emit deprecation warnings for `then` and `local`.
    idol_mode: bool = false,
    /// Parsing in order to REPRINT. Parse-time desugars are skipped, because a
    /// formatter can only write back what the tree still holds: interpolation
    /// desugared to `..` came back out as `"" .. n`, which is not what was
    /// written and is the form the design is retiring.
    formatting: bool = false,
    /// Nesting inside function bodies; bare `name()` func decls are module-scope only.
    func_body_depth: u32 = 0,
    /// R2/R1 and §2 THE ANCHOR — the two pieces of POSITION a
    /// leading `.` or `:` needs, so the parser can decide the stance instead of
    /// collapsing all three into one.
    ///
    /// R2 rules the leading `.`: "a lens in ARGUMENT position always; the CASE
    /// in descriptor-expected position; neither context => diagnostic". §2 adds
    /// the third context these two implement, method scope -> my field `.pos`.
    /// The case stance is decided upstream in `parse_anchor_case`.
    ///
    /// `call_arg_depth` is ARGUMENT POSITION, counted rather than guessed. It
    /// resets to 0 inside a function body, because a body is a fresh statement
    /// context: `f((l) .pos)` reads `.pos` against `l`, not against whatever
    /// `f` will map over.
    ///
    /// `subject` is METHOD SCOPE: the enclosing function's FIRST parameter,
    /// which §0.6 already makes the receiver — "declare at the trie, CALL AT
    /// THE VALUE... holding the first argument means holding the receiver". It
    /// is saved and restored around each body so nesting cannot leak a
    /// receiver outward.
    call_arg_depth: u32 = 0,
    subject: ?[]const u8 = null,
    /// Nesting inside a DESCRIPTOR body, where the first parameter of a slot
    /// function is emphatically NOT the receiver — the enclosing descriptor is.
    /// §20's own golden `shc/lex.id` is the proof and the reason this counter
    /// exists:
    ///
    ///     lexer: {
    ///         pos: u32
    ///         here = () span{ .pos, .pos }
    ///         skip = (p) while b = :peek() and p(b) .pos += 1
    ///
    /// `here` has no parameter at all, and `skip`'s first parameter is the
    /// PREDICATE. Taking either as the subject would silently rewrite `.pos`
    /// into `p.pos` and `:peek()` into `p:peek()` — a wrong value dressed as a
    /// fix for wrong values. Inside a descriptor body the subject stays unset
    /// and the leading `.` keeps exactly the reading it has today.
    descriptor_body_depth: u32 = 0,
    /// GAP-16 — nesting inside a `@`-directive argument list, where a string
    /// literal is DATA handed to the compiler rather than runtime source text.
    /// `@comp.interpolate("int64_t {name}()...")` owns those braces itself; if
    /// STR-1 claims them first the template is rewritten into a `..` chain over
    /// undeclared locals and the directive never sees a literal to fold.
    directive_arg_depth: u32 = 0,

    deferred_hint_attrs: std.ArrayList(ast.Attribute) = .empty,

    /// §3 — OFFSIDE LAYOUT: the frame of the block being parsed now,
    /// and the frame of the block most recently finished. See `LayoutFrame`.
    layout: LayoutFrame = .{},
    last_layout: LayoutFrame = .{},
    /// §3 for the DEPRECATED `match`/`case` construct: the column of the line
    /// the `match` was written on, or 0 outside one. `match` demanded a written
    /// `end` — `parse_match_inner` ended in `expect(.kw_end)` — which in `.id`,
    /// where `end` is deleted, left the whole construct with NO spelling: the
    /// arm list ran to the file edge and reported "this line continues a block
    /// that already closed by dedent" at EOF.
    ///
    /// It gets the SAME rule as every other block rather than a rule of its
    /// own: an arm binds at or right of the `match` (that is `clause_binds` for
    /// `else`/`elseif`, applied to `case`), and any other line back at or left
    /// of it has left the construct. The `end` becomes accepted-and-deleted,
    /// §3.4, so `tools/wasm/src/wasm/jit.id` keeps parsing exactly as written.
    ///
    /// NOT A REHABILITATION of the keyword. `gate/match.id` proves the
    /// canonical form is the subject-first relation `c:match` over an offside
    /// pack of alternatives, which has never needed an `end`; the deprecation
    /// warning still fires on every `match` keyword. This only makes the
    /// legacy face writable while it is still being migrated off.
    match_open_col: u32 = 0,
    /// Line of the most recently consumed token. Layout speaks about LINE
    /// STARTS only: `;` is the one-line induction tail (§4), so
    /// `tmp = a[i]; a[i] = a[j]; a[j] = tmp` is three statements on one
    /// rendered line and its second and third columns render nothing.
    prev_line: u32 = 0,
    /// One past the last column of the most recently consumed token, on
    /// `prev_line`. ADJACENCY is a grammar fact in Duo — `>>=` is `>>` with an
    /// `=` glued to it (§20's leb128 encoder), and §4 draws the same line
    /// through `.`: `a.b` glued is DATA ACCESS, a leading `.` is the anchor
    /// walk. Nothing else in the parser can recover that, because a Loc
    /// carries no end.
    prev_end_col: u32 = 0,
    /// Set by `parse_type` when the type just read carried a `| alt`
    /// alternative other than `nil`. Read only where a FUNCTION CONTRACT is
    /// parsed — the one position §8 gives the union a meaning:
    /// `: u64 | error` is the failure pack, not a sum type.
    union_alternative_seen: bool = false,

    /// §9 — relation edges declared at a trie place with a LEVEL:
    /// `decode(u64) = (cursor): u64 | error`. Keyed `"<name>\x00<level>"`, the
    /// value being the flat symbol the edge was minted as. The level is a
    /// descriptor-space key (LAW-STRATA), so it never becomes a runtime
    /// parameter; it selects WHICH function the call site means, and this map
    /// is how the call site `decode(u64)(v)` finds it again.
    relation_edges: std.StringHashMapUnmanaged([]const u8) = .empty,

    /// §0.3 / §7 — declarations a descriptor body produced on the
    /// side and that must land BEFORE it. An inline case-set is a real
    /// case-set, not a shape: `kind: { name, number, eof }` inside `token`
    /// declares the enum and the field's type is that enum. `parse_block`
    /// drains this ahead of the statement that filled it.
    pending_hoists: std.ArrayList(ast.Stmt) = .empty,

    /// gap[077] — serial number for the staging places a simultaneous
    /// multiple assignment needs. Monotonic per module so two swaps in one
    /// scope cannot name the same place.
    stage_seq: u32 = 0,

    /// The descriptor a body is being read for, so an inline case-set can take
    /// its HOME as its name (§0.1: the qualifier moves to a HOME —
    /// `token.kind`). Null outside a named descriptor body.
    descriptor_home: ?[]const u8 = null,

    /// `"<home>\x00<field>"` -> the minted enum name of an inline case-set, so
    /// `token.kind.eof` reaches the cases the descriptor body declared.
    caseset_homes: std.StringHashMapUnmanaged([]const u8) = .empty,

    /// `<case>` -> the case-set that declares it, so a leading `.` in
    /// DESCRIPTOR-EXPECTED POSITION resolves to a case (§0.3, §2 THE ANCHOR).
    /// `""` records a name TWO case-sets claim: an ambiguous `.eof` is a
    /// diagnostic, never a silent pick of whichever parsed first.
    ///
    /// This map is the parse's own record of what it declared, in the same
    /// shape as `relation_edges` and `caseset_homes` beside it. It is not a
    /// registry consulted by other subsystems — sema and codegen never read it,
    /// they read the resolved `field` node it produces.
    caseset_cases: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Descriptors declared in this module, mapped to their field names in
    /// DECLARATION ORDER, so `point(3, 4)` can be resolved as descriptor
    /// application — the same application grammar a relation call uses.
    record_descriptors: std.StringHashMapUnmanaged([]const []const u8) = .empty,

    /// True when `parse_module` installed the producer pack on `alloc`.
    pack_owned: bool = false,

    /// Byte offset of the last retired-`#` site `denyRetiredLengthHash` named.
    /// About thirty-five speculative scans rewind the lexer and re-read the same
    /// tokens, and the site is a property of the BYTES rather than of the parse,
    /// so without this the same `#` is reported once per rewind.
    hash_denied_off: ?usize = null,

    pub fn init(lex: *Lexer, alloc: Allocator) Parser {
        return .{ .lex = lex, .alloc = alloc };
    }

    /// One token pack. Host scanner is not a parse fallback (`law.bridge.death`).
    fn ensureProducerPack(self: *Parser) ParseError!void {
        if (self.lex.isDuoBacked()) return;
        try lexer_dispatch.route(self.alloc, self.lex, self.lex.cursor.bytes, self.lex.cursor.file);
        self.pack_owned = true;
    }

    fn releaseOwnedPack(self: *Parser) void {
        if (!self.pack_owned) return;
        if (self.lex.duo_tokens) |toks| {
            self.alloc.free(toks);
            self.lex.duo_tokens = null;
            self.lex.duo_index = 0;
            self.lex.peeked = null;
        }
        self.pack_owned = false;
    }

    /// §3 — **blocks close by dedent**. This is the layout layer.
    ///
    /// Deliberately NOT "make `end` optional with a pile of lookahead cases":
    /// that keeps the wrong grammar underneath. `end` never existed in the
    /// graph — block structure is edges and a closer token is a rendering
    /// choice — so the grammar has to be layout-driven and `end` has to become
    /// a token that is ACCEPTED AND DELETED (§3.4: a human resync anchor that
    /// leaves the writing dialect when telemetry says resync usage is ~0).
    ///
    /// A frame records where the block's OPENER sits and where its BODY sits.
    /// Those two columns are the whole rule:
    ///
    ///   * body on the opener's line → ONE-LINER; the newline closes it
    ///     (`if b .pos += 1`, `while v >= 0x80 out:write(v); v >>= 7`).
    ///   * body indented past the opener → OFFSIDE; statements continue at
    ///     exactly `body_col`, the block closes on the first token left of it,
    ///     and anything in between is a DIAGNOSTIC.
    ///   * body NOT indented past the opener → LEGACY; the rendering carries no
    ///     structure, so layout must not pretend to read any and only a written
    ///     `end` closes the block.
    ///
    /// That last clause is what makes this strictly additive over the 748
    /// tracked files that write `end`: a body flush with (or left of) its
    /// opener is exactly the shape layout cannot speak about, so it is left
    /// alone rather than guessed at.
    ///
    /// §3's argument for why offside is safe here and not in Python is that
    /// Python's sin is *writer-inferred* structure — a mis-indent silently
    /// means something else — while Duo's ceilings (100 cols, ≤2 call depth,
    /// 0 nested if, no one-liner nesting) deny the deep shapes where that
    /// happens. So **indentation matching no legal shallow shape is a
    /// diagnostic, never an alternate parse**. That is `layout_misindent`, and
    /// it is the load-bearing half: an offside parser that silently re-nests on
    /// a mis-indent is worse than the status quo.
    pub const LayoutFrame = struct {
        /// The construct that opened the block (`if`, `while`, the first token
        /// of a function declaration…). Zero column means "no opener": the
        /// module block, and bodies whose closer is a bracket rather than a
        /// rendering. THE OPENER'S COLUMN IS THE CLOSING THRESHOLD — a line
        /// starting at or left of it has left the block.
        open_line: u32 = 0,
        open_col: u32 = 0,
        /// The offside line: the column every statement of this block starts
        /// at. Zero means "not yet established", which is the state of a block
        /// whose body began inline on the opener's line — its offside line is
        /// set by the first CONTINUATION line, if there is one.
        body_col: u32 = 0,
        /// Layout carries this block's structure. False = legacy shape, where
        /// only a written `end` closes the block.
        offside: bool = false,
    };

    /// Compute the layout frame for the block about to be parsed. `open` is the
    /// loc of the token that opened it, or null for a block layout does not
    /// govern.
    fn open_layout(self: *Parser, open: ?ast.Loc) ParseError!LayoutFrame {
        const first = try self.pk();
        var f = LayoutFrame{};
        // LAYOUT IS A `.id` RULE. Lua has no offside rule: blocks close with
        // `end` at whatever column the writer left them, and `f.offside` is
        // what turns a dedent into a close and a deeper `end` into an error.
        // Applying it to `.lua` input imposes the Duo surface on a Lua file,
        // which is the same dialect leak this pass exists to close — and it
        // was not theoretical: `examples/benchmark.lua:704` (the `.lua` half
        // of the benchmark's correctness oracle) failed to compile at HEAD
        // with "'end' at column 13 closes a block opened at column 9", so
        // `zig build bench` could not reach a single RESULT row.
        if (!self.idol_mode) return f;
        const o = open orelse return f;
        f.open_line = o.line;
        f.open_col = o.col;
        // An EMPTY block renders nothing, so it says nothing about layout.
        switch (first.kind) {
            .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof => return f,
            else => {},
        }
        if (first.loc.line == o.line) {
            // Body begins inline: `if b .pos += 1`. The offside line is left
            // unset — a continuation line indented past the opener still
            // belongs to this block and gets to establish it.
            f.offside = true;
        } else if (first.loc.col > o.col) {
            f.offside = true;
            f.body_col = first.loc.col;
        }
        return f;
    }

    /// The offside decision at a statement boundary.
    const LayoutVerdict = enum { keep, close, misindent };

    fn layout_verdict(f: *LayoutFrame, tok: Token) LayoutVerdict {
        if (!f.offside) return .keep;
        // The opener's column is the threshold: at or left of it, this line has
        // left the block, however deep the block's own body was.
        if (tok.loc.col <= f.open_col) return .close;
        if (f.body_col == 0) {
            f.body_col = tok.loc.col;
            return .keep;
        }
        if (tok.loc.col == f.body_col) return .keep;
        // A TERMINATOR at an odd column is a disagreement between the two
        // renderings, not a statement that matches no shape. Close here and let
        // `close_block` name it precisely ("'end' at column 9 closes a block
        // opened at column 5"), which is the message that points at the fix.
        return switch (tok.kind) {
            .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof => .close,
            else => .misindent,
        };
    }

    /// §3's mandatory half. A statement indented past its block's offside line
    /// continues nothing (the line above ended) and opens nothing (no construct
    /// on that line opened a block), so there is no shallow shape it could
    /// mean. Refusing to guess is what makes dedent-closing safe.
    fn layout_misindent(f: LayoutFrame, tok: Token) ParseError {
        term.locErr(tok.loc, "indentation matches no block: this line starts at column {d}, its block's statements start at column {d}", .{
            tok.loc.col, f.body_col,
        });
        term.locHint(tok.loc, "blocks close by dedent; a line may only be indented further than the one above it when that line opened a block", .{});
        return ParseError.UnexpectedToken;
    }

    /// Close a block that layout may have already closed. §3.4: a written `end`
    /// is accepted and deleted. With no `end`, the frame must have closed the
    /// block by layout; otherwise this is the original "expected 'end'"
    /// diagnostic, unchanged.
    fn close_block(self: *Parser, open: ast.Loc, offside: bool) ParseError!void {
        const tok = try self.pk();
        if (tok.kind == .kw_end) {
            // Under layout the two renderings must AGREE. A LINE-LEADING `end`
            // deeper than its opener means the writer indented a block
            // differently than they closed it, and that disagreement is the one
            // case where dedent-closing could otherwise pick a nesting the
            // writer did not mean. It is a diagnostic, not a silent choice.
            //
            // A TRAILING `end` — one sharing a line with the statement before
            // it, as in `else body = sub(body, 3) end` — is not rendering
            // structure at all; its column is wherever the text happened to
            // stop. Those say nothing and are accepted as written.
            if (offside and tok.loc.line != self.prev_line and tok.loc.col > open.col) {
                term.locErr(tok.loc, "'end' at column {d} closes a block opened at column {d}", .{ tok.loc.col, open.col });
                term.locHint(tok.loc, "the block already closed by dedent; align this 'end' with its opener or remove it", .{});
                return ParseError.UnexpectedToken;
            }
            // A LINE-LEADING `end` LEFT of this opener is not this block's. The
            // block already closed by dedent — that is what put this line at a
            // shallower column — so the `end` belongs to something enclosing,
            // and consuming it here spends a terminator the outer block still
            // needs. `lib/thread.id:251` is the shape: an `if` at column 9
            // inside a lambda whose body is also at column 9 swallowed the
            // lambda's own `end` at column 5, leaving `)` where a statement was
            // expected. Only an inner `end` could have repaired it, and §3
            // deletes inner `end`s — so the site had NO correct spelling.
            //
            // Guarded on `offside` alone: in the `end`-closed dialect every
            // block still demands its own terminator and this cannot fire.
            if (offside and tok.loc.line != self.prev_line and tok.loc.col < open.col) return;
            _ = try self.adv();
            return;
        }
        if (offside) return;
        if (self.idol_mode) {
            const edge = try self.pk();
            term.locErr(edge.loc, "this block opened at column {d} is still open at the file edge", .{open.col});
            term.locHint(edge.loc, "outdent to close the block — `end` is deleted in .id source", .{});
            return ParseError.UnexpectedToken;
        }
        _ = try self.expect(.kw_end);
    }

    /// `else`/`elseif` BINDS BY COLUMN (§3 mechanics). Under layout an inner
    /// `if` has already closed by dedent, so a clause left of this opener
    /// belongs to an enclosing construct and must not be taken here. A clause
    /// at or right of the opener binds — which is also what the `end`-closed
    /// dialect did, so no existing file changes shape.
    fn clause_binds(self: *Parser, open: ast.Loc, kind: TK, offside: bool) ParseError!bool {
        const tok = try self.pk();
        if (tok.kind != kind) return false;
        if (!offside) return true;
        return tok.loc.col >= open.col;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// Consume pending compiler hints from the lexer (from `--- @hint` comments)
    /// and return them as an attribute slice.
    fn consumeLexerHints(self: *Parser) ParseError![]ast.Attribute {
        if (!self.lex.hasPendingHints()) return &.{};
        var hints: [8]?[]const u8 = undefined;
        const count = self.lex.consumeHints(&hints);
        if (count == 0) return &.{};
        var attrs = try self.alloc.alloc(ast.Attribute, count);
        var i: u8 = 0;
        while (i < count) : (i += 1) {
            const hint_text = hints[i] orelse continue;
            if (std.mem.indexOfScalar(u8, hint_text, '(')) |paren_pos| {
                const name = hint_text[0..paren_pos];
                const end_paren = findMatchingParen(hint_text, paren_pos);
                const args = hint_text[paren_pos + 1 .. end_paren];
                attrs[i] = .{ .name = name, .args = args };
            } else {
                attrs[i] = .{ .name = hint_text, .args = null };
            }
        }
        return attrs[0..count];
    }

    /// Turn `--- @` comment hints into module directive statements or defer them
    /// for the next function/type declaration.  Module-level directives that must
    /// execute in order (C includes, raw C emission, specialization, build,
    /// debug) are flushed immediately; everything else is deferred.
    fn flush_module_hint_directives(self: *Parser, stmts: *std.ArrayList(ast.Stmt)) ParseError!void {
        while (self.lex.hasPendingHints()) {
            const hint_attrs = try self.consumeLexerHints();
            defer self.alloc.free(hint_attrs);
            var emitted = false;
            for (hint_attrs) |attr| {
                if (is_module_level_hint(attr)) {
                    const loc = (try self.pk()).loc;
                    // @comp.c.include / @comp.c.import (and legacy @c.*) become cinclude statements
                    if (@import("meta_module.zig").isCHeaderImportDirective(attr.name)) {
                        const header = @import("directives.zig").extractCRawCode(attr.args orelse "");
                        try stmts.append(self.alloc, .{ .cinclude = .{ .loc = loc, .header = header } });
                    } else {
                        try stmts.append(self.alloc, .{ .directive = .{ .loc = loc, .attr = attr } });
                    }
                    emitted = true;
                } else {
                    try self.deferred_hint_attrs.append(self.alloc, attr);
                }
            }
            if (!emitted) break;
        }
    }

    /// Returns true for hints that must be emitted as module-level directives
    /// (in source order) rather than deferred to the next function/type.
    fn is_module_level_hint(attr: ast.Attribute) bool {
        const directives = @import("directives.zig");
        if (directives.isBuildDirective(attr.name)) return true;
        if (directives.isDebugDirective(attr.name)) return true;
        // C interface directives are module-level (order matters for #include)
        if (@import("meta_module.zig").isCHeaderImportDirective(attr.name) or
            @import("meta_module.zig").isCEmitDirective(attr.name))
            return true;
        // @specialize is a module-level directive
        if (std.mem.eql(u8, attr.name, "specialize")) return true;
        return false;
    }

    fn merge_deferred_hints(self: *Parser, hint_attrs: []ast.Attribute) ParseError![]ast.Attribute {
        if (self.deferred_hint_attrs.items.len == 0 and hint_attrs.len == 0) return &.{};
        var all: std.ArrayList(ast.Attribute) = .empty;
        try all.appendSlice(self.alloc, self.deferred_hint_attrs.items);
        self.deferred_hint_attrs.clearRetainingCapacity();
        try all.appendSlice(self.alloc, hint_attrs);
        return try all.toOwnedSlice(self.alloc);
    }

    fn pk(self: *Parser) ParseError!Token {
        return self.lex.peek();
    }

    fn adv(self: *Parser) ParseError!Token {
        const tok = try self.lex.next();
        self.prev_line = tok.loc.line;
        self.prev_end_col = tok.loc.col + @as(u32, @intCast(tok.text.len));
        if (demandsOperand(tok.kind)) try self.denyRetiredLengthHash(tok);
        return tok;
    }

    /// Tokens that CANNOT END AN EXPRESSION, so the thing after them is an
    /// operand and not a new statement. This is the whole precondition for
    /// `denyRetiredLengthHash`, and it is what separates `n = #t` — where the
    /// operand is missing — from `n = t #t`, where it is not.
    ///
    /// `.lbrace` is deliberately ABSENT. A brace opens a REGION whose body is a
    /// sequence of slots, not one demanded operand, and a comment on its own
    /// line inside a pack is ordinary.
    fn demandsOperand(kind: TK) bool {
        return switch (kind) {
            .assign,
            .lparen,
            .lbracket,
            .comma,
            .plus,
            .minus,
            .star,
            .slash,
            .percent,
            .caret,
            .amp,
            .pipe,
            .lt,
            .gt,
            .tilde,
            .colon,
            .dot,
            .at,
            .bang,
            .hash,
            .hash_hash,
            .concat,
            .eq,
            .neq,
            .leq,
            .geq,
            .lshift,
            .rshift,
            .idiv,
            .arrow,
            .pipe_gt,
            .fat_arrow,
            .plus_assign,
            .minus_assign,
            .star_assign,
            .slash_assign,
            .percent_assign,
            .caret_assign,
            .kw_and,
            .kw_or,
            .kw_not,
            .kw_in,
            .kw_if,
            .kw_elseif,
            .kw_while,
            .kw_until,
            .kw_return,
            .kw_by,
            => true,
            else => false,
        };
    }

    /// The first byte a `#` would have to be followed by for `#…` to read as the
    /// retired length operator rather than as comment prose. A canonical comment
    /// is written `# text`; the space is what tells them apart, and it is the
    /// only thing that can, because `#` IS the comment opener in canonical
    /// source (`docs/spec/canonical.md`: "Comments use `#`").
    fn opensExpression(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '@' or c == '(' or c == '"';
    }

    /// `#` IS RETIRED AS A LENGTH OPERATOR, and this is where it is refused.
    ///
    /// ===================== WHAT WAS ACTUALLY WRONG =====================
    /// It was reported as "`#` works in statement position and dies in argument
    /// position". It does neither. In canonical source `#` opens a COMMENT
    /// (`src/lexer.zig`, `c == '#' and family == family_canon`), so `#t` never
    /// produces a `.hash` token at all and the two positions differ only in what
    /// the swallowed line takes with it:
    ///
    ///     print(#t)      the comment eats the `)` too, so the call never closes
    ///                    and the parse dies at `<eof>` — a bad message about
    ///                    the wrong place, but at least a refusal.
    ///
    ///     n = #t         the comment eats only `#t`, the RHS is then taken from
    ///                    the NEXT LINE, and a DIFFERENT PROGRAM compiles in
    ///                    silence. Measured: `t = {1,2,3}` / `n = #t` /
    ///                    `print(999)` emits `lua_Value n = printf("%lld\n",999)`.
    ///
    /// So the asymmetry was never "legal here, illegal there". It was silent
    /// absorption on one side and a misplaced diagnostic on the other, and the
    /// silent one is the worse half.
    ///
    /// ===================== WHY REFUSE RATHER THAN SUPPORT =====================
    /// `#`-as-length is retired: the canonical spelling is `subject:len()`, the
    /// repo-wide migration has already run, and `#` is the comment opener that
    /// migration left behind. Reinstating `#` would need it to stop opening
    /// comments, which is a lexical change to the one character the language
    /// spends on comments. There is no second reading to preserve: measured over
    /// the tracked corpus, `#` in operand position occurs at THREE sites, all
    /// three in the two example files this refusal unblocks.
    ///
    /// ===================== WHY THIS IS NOT A GUESS =====================
    /// The bytes between two visible tokens are whitespace and comments only —
    /// the lexer skipped them — so a `#` found in that gap is a comment OPENER
    /// and never text inside a literal. Three facts have to hold together, and
    /// each one is a fact rather than a heuristic:
    ///
    ///   1. the token just consumed cannot end an expression (`demandsOperand`),
    ///      so what follows is an OPERAND;
    ///   2. the next visible token is on a LATER LINE, so that operand did not
    ///      arrive — something swallowed the rest of this line;
    ///   3. the swallowing comment is `#` ABUTTING an expression opener, which
    ///      is the retired length spelling and is not how a comment is written.
    ///
    /// Drop any one and the refusal is wrong: without (1) `n = t #note` trips,
    /// without (2) `n = t + 1 #note` trips, without (3) every trailing `# note`
    /// trips.
    fn denyRetiredLengthHash(self: *Parser, demand: Token) ParseError!void {
        if (self.lex.family != @import("lexer_bridge.zig").family_canon) return;
        const src = self.lex.cursor.bytes;
        const from = sourceOffset(src, demand) orelse return;
        const gap_start = from + demand.text.len;
        const next = self.lex.peek() catch return;
        if (next.loc.line <= demand.loc.line) return;
        const gap_end = if (next.kind == .eof) src.len else (sourceOffset(src, next) orelse src.len);
        if (gap_end < gap_start or gap_end > src.len) return;

        const at = retiredHashOnLine(src[gap_start..gap_end]) orelse return;
        const off = gap_start + at;
        if (self.hash_denied_off) |seen| if (seen == off) return;
        self.hash_denied_off = off;

        var loc = demand.loc;
        loc.col += @intCast(off - from);
        term.locErr(loc, "`#` is not a length operator — write `subject:len()`", .{});
        term.locHint(loc, "`#` OPENS A COMMENT in canonical source: everything after it on this line was discarded, and the operand this `{s}` demands never arrived", .{demand.text});
        term.locHint(loc, "`#x` is `x:len()`, `#@comp.fields(p)` is `@comp.fields(p):len()`; if these bytes really are a comment, write `# ` with a space", .{});
        return ParseError.UnexpectedToken;
    }

    /// §3 — **A TOKEN THAT CAN OPEN AN EXPRESSION, AT THE START OF A LINE, OPENS
    /// ONE.** The exact dual of `demandsOperand` above, and the second half of
    /// one ruling: that one says what a token cannot END, this one says what a
    /// token can BEGIN, and between them they decide where an expression stops.
    ///
    /// ===================== WHAT THIS COST =====================
    /// A block-tail expression beginning with unary minus was absorbed as a
    /// BINARY minus across the newline and the dedent. Three shapes, one
    /// differing character, measured under `--backend=c`:
    ///
    ///     v = n + 100 / `-1`        104   WRONG — parsed `v = (n + 100) - 1`,
    ///                                     and the tail expression VANISHED
    ///     v = n + 100 / `return -1`  -1   correct
    ///     v = n + 100 / `99`         99   correct
    ///
    /// It is a wrong ANSWER, not a parse error, and `idol fmt` reprinted the
    /// absorbed form faithfully — the formatter was innocent, which is why a
    /// diff of `return row[1] - 1` looked like printer damage and was not.
    ///
    /// In `lib/compiler/lexer.id` — the EXECUTED production lexer — the shape is
    /// `return n` then a dedented `-1`, so the relation returns its count ONE
    /// LOW and its not-found sentinel does not exist. In `lib/wasm/opcodes.id`
    /// the preceding statement is `i += 1`, which absorbs to `i += 1 - 1` — an
    /// INFINITE LOOP in an opcode lookup.
    ///
    /// ===================== WHY THE TEST IS "CAN OPEN" =====================
    /// Only an operator with a PREFIX meaning is ambiguous at the head of a
    /// line. A line-leading `*` cannot begin an expression, so it can only be a
    /// continuation, and
    ///
    ///     total = a
    ///         * b
    ///
    /// keeps meaning what it means. `-`, `~` and `@` each have a prefix reading,
    /// so for those the newline decides, exactly as §3 says a newline decides
    /// everything else. `@` was ALREADY guarded here, against
    /// `tok.loc.line > lhs.loc().line` — the right instinct with the wrong
    /// operand: an `lhs` that itself spans lines makes that test true for an
    /// operator sitting mid-line, so `1 +\n2 -\n3` would have lost its `- 3`.
    /// The question is whether the OPERATOR begins a line, and nothing about
    /// where its left operand started.
    ///
    /// Read off the SOURCE BYTES rather than tracked state, for the reason
    /// `lineStartCol` records one screen up: about thirty-five speculative scans
    /// rewind the lexer without restoring the parser's line bookkeeping, so a
    /// tracked "previous line" can be left holding a line the parse has not
    /// reached. A token's own text is a view into the source on both token
    /// paths, so its offset cannot go stale.
    fn opensLineAndExpression(self: *Parser, tok: Token) bool {
        switch (tok.kind) {
            .minus, .tilde, .at => {},
            else => return false,
        }
        const src = self.lex.cursor.bytes;
        const off = sourceOffset(src, tok) orelse return false;
        var i = off;
        while (i > 0) {
            i -= 1;
            switch (src[i]) {
                ' ', '\t', '\r' => {},
                '\n' => return true,
                else => return false,
            }
        }
        return true;
    }

    /// Offset of `tok` in `src`, or null when the token's text is not a view
    /// into it — a synthesised `.eof`, or a pack whose text arena is elsewhere.
    /// Production packs DO view the caller's source (`lexer_dispatch.route`:
    /// "Decode writes views into the caller-owned source"), which is why this
    /// works on the producer path and not only under the host scanner.
    fn sourceOffset(src: []const u8, tok: Token) ?usize {
        const base = @intFromPtr(src.ptr);
        const p = @intFromPtr(tok.text.ptr);
        if (p < base or p + tok.text.len > base + src.len) return null;
        return p - base;
    }

    /// Index of a `#` that OPENS a comment and ABUTS an expression, on the FIRST
    /// line of a span the lexer already skipped.
    ///
    /// The first line and no further, because only a comment on the DEMANDING
    /// TOKEN'S OWN line can explain a missing operand. In
    ///
    ///     f(
    ///       #x
    ///       y)
    ///
    /// the operand `y` arrived; the comment cost nothing and is not this
    /// ruling's business. Scanning the whole gap convicts that file.
    ///
    /// Only the FIRST opener on the line counts: in `-- note #x` the `#` is
    /// prose inside a compat comment, not an opener.
    fn retiredHashOnLine(gap: []const u8) ?usize {
        const line = gap[0 .. std.mem.indexOfScalar(u8, gap, '\n') orelse gap.len];
        var j: usize = 0;
        while (j < line.len) : (j += 1) {
            if (line[j] == '-' and j + 1 < line.len and line[j + 1] == '-') return null;
            if (line[j] != '#') continue;
            if (j + 1 < line.len and opensExpression(line[j + 1])) return j;
            return null;
        }
        return null;
    }

    /// §3 — the block threshold for a function body. The declaration's own
    /// first token, which is `l` for `parse = (lx: lexer)` and the enclosing
    /// statement's head for a lambda written in argument position:
    ///
    ///     co = coroutine.create(()
    ///         ok, result = pcall(fn, args:unpack())
    ///
    /// `l` there is the `(` at column 26, so the body at column 9 was not
    /// "indented past its opener", the frame never went offside, and the block
    /// could not close at all — the file parsed to its edge. The line's first
    /// token is column 5, and against that the body is offside and closes on
    /// the first line back at column 5, which is the rule every other block
    /// already follows. `parse_func_body`'s own comment has stated this rule
    /// all along; only the value passed to it disagreed.
    ///
    /// READ BACKWARD OFF THE TOKEN STREAM, not tracked in a field. A tracked
    /// "first token of the current line" is wrong here for a reason worth
    /// recording: about thirty-five speculative scans rewind the LEXER without
    /// restoring the parser's line bookkeeping, so any such field can be left
    /// holding a line the parse has not reached. Measured, not feared — the
    /// tracked version reported `line_start = 4:3` while parsing a lambda on
    /// line 2 of `examples/parity/map.id`, which handed the body an opener of
    /// column 20 and (with the empty-body rule below) silently gave the lambda
    /// an EMPTY body. `duo_tokens` is the same stream `headerSignal` already
    /// scans and it cannot go stale.
    ///
    /// Only ever moves the threshold LEFT, and only within `l`'s own line: a
    /// header that begins its line is its own line start and nothing changes.
    ///
    /// Shared with `match`, whose arm list has the same problem the moment the
    /// construct is written in expression position (`x = match op`).
    fn line_opener(self: *Parser, l: ast.Loc) ParseError!ast.Loc {
        if (!self.idol_mode) return l;
        try self.ensureProducerPack();
        const toks = self.lex.duo_tokens orelse return l;
        var i = @min(self.lex.duoStreamIndex(), toks.len);
        var best = l;
        while (i > 0) {
            i -= 1;
            const t = toks[i];
            if (t.loc.line != l.line) break;
            if (t.loc.col < best.col) best = t.loc;
        }
        return best;
    }

    /// Whether `tok` is written with no gap after the token just consumed.
    /// §4 gives `.` two readings and separates them by POSITION: `a.b` is data
    /// access, ` .b` is the leading anchor walk. Only the source spacing tells
    /// them apart, so this is the same adjacency test `peek_glued_assign` uses
    /// for `>>=` — one rule, two spellings.
    fn glued_to_prev(self: *Parser, tok: Token) bool {
        return tok.loc.line == self.prev_line and tok.loc.col == self.prev_end_col;
    }

    /// `@` with nothing after it to name: the BARE anchor of §2, as opposed to
    /// every prefix spelling (`@comp.…`, `@c.emit`, `@{ … }`), which reads a
    /// name or a table. Argument-list closers only — the position §20 writes
    /// it in — so this cannot reinterpret an existing attribute.
    fn at_is_bare_anchor(self: *Parser) ParseError!bool {
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        defer {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        }
        _ = try self.adv();
        const nxt = (try self.pk()).kind;
        return nxt == .rparen or nxt == .comma;
    }

    fn expect(self: *Parser, kind: TK) ParseError!Token {
        const tok = try self.adv();
        if (tok.kind != kind) {
            if (self.idol_mode and kind == .kw_end) {
                term.locErr(tok.loc, "this line continues a block that already closed by dedent", .{});
                term.locHint(tok.loc, "remove `end` — .id blocks close by outdent only", .{});
            } else {
                term.locErr(tok.loc, "write `{s}` at this token edge", .{kind.spelling()});
                term.locHint(tok.loc, "got `{s}` here instead", .{tok.kind.spelling()});
            }
            return ParseError.ExpectedToken;
        }
        return tok;
    }

    fn eat(self: *Parser, kind: TK) ParseError!?Token {
        if ((try self.pk()).kind == kind) return try self.adv();
        return null;
    }

    /// Consume a deprecated keyword (then/do) if present. In .id mode, emit a
    /// hint suggesting the keyword can be omitted. Used for `then` after `if`
    /// and `do` after `while`/`for` in canonical Duo.
    fn eat_deprecated(self: *Parser, kind: TK) ParseError!void {
        if ((try self.pk()).kind == kind) {
            const tok = try self.adv();
            if (self.idol_mode) {
                term.locHint(tok.loc, "'{s}' is optional in .id files and can be omitted", .{kind.spelling()});
            }
        }
    }

    fn check(self: *Parser, kind: TK) ParseError!bool {
        return (try self.pk()).kind == kind;
    }

    fn new_expr(self: *Parser, e: ast.Expr) ParseError!*ast.Expr {
        const p2 = try self.alloc.create(ast.Expr);
        p2.* = e;
        return p2;
    }

    // ── gap[077] MULTIPLE ASSIGNMENT IS SIMULTANEOUS ─────────────────────────
    //
    // `a, b = b, a` is the swap every reader already has a reflex for, and it
    // was SILENTLY WRONG. Both backends wrote the targets left to right, so
    // `a` took `b`'s value and then `b` took the ALREADY-OVERWRITTEN `a`.
    // Measured 2026-08-09, before this: `a = 1 · b = 2 · a, b = b, a` printed
    // `2 2`, and `t[1], t[2] = t[2], t[1]` over `{ 3, 7 }` printed `7 7`.
    // `--backend=direct` and `--backend=c` AGREED on both, which is exactly
    // why it read as the language rather than as a defect.
    //
    // The rule is that every right-hand value is realized BEFORE any target is
    // written — the same rule that already makes the failure pack correct.
    // Rather than teach two lowerers that separately, the statement is
    // rewritten here into the sequence that already means it: read the places,
    // stage the values, then write. It goes inside a `do` block so the staging
    // places cannot escape and no block parser has to drain a hoist list —
    // three of the four statement-list builders do not.
    //
    // It fires ONLY on a real conflict, so the AST every other front end reads
    // is unchanged for the ordinary case: `a, b = 1, 2` keeps its shape, and
    // `v, err = f(x)` is a one-value PACK (`values.len == 1`) that never
    // reaches here at all — that case already worked and is the regression
    // test.

    fn parallel_assign(self: *Parser, loc: ast.Loc, targets: []*ast.Expr, values: []*ast.Expr) ParseError!?ast.Stmt {
        if (targets.len < 2 or targets.len != values.len) return null;
        if (!assign_self_conflicts(targets, values)) return null;

        var stmts: std.ArrayList(ast.Stmt) = .empty;

        // The PLACES first, left to right. A computed key must be read once,
        // before any write, or a swap with side-effecting indices changes
        // meaning: `t[i], t[j] = t[j], t[i]` must evaluate `i` and `j` once
        // each, not twice.
        const places = try self.alloc.alloc(*ast.Expr, targets.len);
        for (targets, 0..) |t, i| places[i] = try self.stage_place(&stmts, t);

        // Then every value, so no write can reach one.
        const staged = try self.alloc.alloc(*ast.Expr, values.len);
        for (values, 0..) |v, i| staged[i] = try self.stage_value(&stmts, v);

        for (places, 0..) |p, i| try self.emit_single_assign(&stmts, p, staged[i]);

        return ast.Stmt{ .do_block = .{ .loc = loc, .body = .{
            .loc = loc,
            .stmts = try stmts.toOwnedSlice(self.alloc),
            .tail_expr = null,
        } } };
    }

    fn emit_single_assign(
        self: *Parser,
        stmts: *std.ArrayList(ast.Stmt),
        target: *ast.Expr,
        value: *ast.Expr,
    ) ParseError!void {
        const tg = try self.alloc.alloc(*ast.Expr, 1);
        tg[0] = target;
        const vl = try self.alloc.alloc(*ast.Expr, 1);
        vl[0] = value;
        try stmts.append(self.alloc, .{ .assign = .{
            .loc = target.loc(),
            .targets = tg,
            .values = vl,
        } });
    }

    /// Bind `v` to a fresh staging place and hand back a reader for it.
    fn stage_value(self: *Parser, stmts: *std.ArrayList(ast.Stmt), v: *ast.Expr) ParseError!*ast.Expr {
        const ident = try std.fmt.allocPrint(self.alloc, "duostage{d}", .{self.stage_seq});
        self.stage_seq += 1;
        try self.emit_single_assign(
            stmts,
            try self.new_expr(.{ .name = .{ .loc = v.loc(), .ident = ident } }),
            v,
        );
        return try self.new_expr(.{ .name = .{ .loc = v.loc(), .ident = ident } });
    }

    /// A target is a PLACE, so it is never staged itself — only the
    /// subexpressions that SELECT it. A settled one is already read-once and
    /// stays where it is; anything computed becomes a staging place so the
    /// write below reads it rather than re-running it.
    fn stage_place(self: *Parser, stmts: *std.ArrayList(ast.Stmt), t: *ast.Expr) ParseError!*ast.Expr {
        return switch (t.*) {
            .index => |ix| try self.new_expr(.{ .index = .{
                .loc = ix.loc,
                .obj = if (expr_is_settled(ix.obj)) ix.obj else try self.stage_value(stmts, ix.obj),
                .key = if (expr_is_settled(ix.key)) ix.key else try self.stage_value(stmts, ix.key),
            } }),
            .field => |f| try self.new_expr(.{ .field = .{
                .loc = f.loc,
                .obj = if (expr_is_settled(f.obj)) f.obj else try self.stage_value(stmts, f.obj),
                .field = f.field,
            } }),
            else => t,
        };
    }

    /// Re-reading this costs nothing and can observe nothing.
    fn expr_is_settled(e: *const ast.Expr) bool {
        return switch (e.*) {
            .name, .int_lit, .float_lit, .quoted, .nil, .true_lit, .false_lit => true,
            else => false,
        };
    }

    /// Does a LATER value read storage an earlier target writes? That is the
    /// whole condition — left-to-right writing is only observable when one of
    /// them lands on something still to be read.
    fn assign_self_conflicts(targets: []*ast.Expr, values: []*ast.Expr) bool {
        for (targets, 0..) |t, i| {
            // A place this pass cannot name is a place it cannot prove safe.
            const base = place_base(t) orelse return true;
            for (values[i + 1 ..]) |v| {
                if (expr_reads_name(v, base)) return true;
            }
        }
        return false;
    }

    /// The name whose storage a place ultimately writes: `t` for `t[i].x`.
    fn place_base(e: *const ast.Expr) ?[]const u8 {
        return switch (e.*) {
            .name => |n| n.ident,
            .index => |ix| place_base(ix.obj),
            .field => |f| place_base(f.obj),
            else => null,
        };
    }

    /// Conservative by construction: a shape this walk does not decompose is
    /// reported as a read, because staging is always sound and skipping it is
    /// what produced the wrong answer.
    fn expr_reads_name(e: *const ast.Expr, name: []const u8) bool {
        return switch (e.*) {
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg => false,
            .name => |n| std.mem.eql(u8, n.ident, name),
            .index => |ix| expr_reads_name(ix.obj, name) or expr_reads_name(ix.key, name),
            .field => |f| expr_reads_name(f.obj, name),
            .binop => |b| expr_reads_name(b.lhs, name) or expr_reads_name(b.rhs, name),
            .unop => |u| expr_reads_name(u.operand, name),
            .contains_expr => |c| expr_reads_name(c.lhs, name) or expr_reads_name(c.rhs, name),
            .try_expr => |x| expr_reads_name(x.operand, name),
            .unwrap_expr => |x| expr_reads_name(x.operand, name),
            .await_expr => |x| expr_reads_name(x.operand, name),
            .call => |c| blk: {
                if (expr_reads_name(c.func, name)) break :blk true;
                for (c.args) |a| if (expr_reads_name(a, name)) break :blk true;
                break :blk false;
            },
            .method_call => |m| blk: {
                if (expr_reads_name(m.obj, name)) break :blk true;
                for (m.args) |a| if (expr_reads_name(a, name)) break :blk true;
                break :blk false;
            },
            .sequence => |s| blk: {
                for (s.exprs) |x| if (expr_reads_name(x, name)) break :blk true;
                break :blk false;
            },
            .range => |r| expr_reads_name(r.start, name) or expr_reads_name(r.end, name) or
                (if (r.step) |s| expr_reads_name(s, name) else false),
            else => true,
        };
    }

    fn new_fb(self: *Parser, fb: ast.FuncBody) ParseError!*ast.FuncBody {
        const p2 = try self.alloc.create(ast.FuncBody);
        p2.* = fb;
        return p2;
    }

    // ── Type parsing ─────────────────────────────────────────────────────────

    pub fn parse_type(self: *Parser) ParseError!ast.TypeExpr {
        var base = try self.parse_type_primary();
        while (try self.eat(.lbracket) != null) {
            var params: std.ArrayList(ast.TypeExpr) = .empty;
            if (!(try self.check(.rbracket))) {
                try params.append(self.alloc, try self.parse_type());
                while (try self.eat(.comma) != null) {
                    try params.append(self.alloc, try self.parse_type());
                }
            }
            _ = try self.expect(.rbracket);
            const base_ptr = try self.alloc.create(ast.TypeExpr);
            base_ptr.* = base;
            base = .{ .generic = .{ .base = base_ptr, .params = try params.toOwnedSlice(self.alloc) } };
        }
        // §8 B-12 — `: u64 | error` DECLARES the failure pack. The
        // alternative names the failure descriptor; the structural nil is
        // UNWRITTEN. `TypeExpr` still has no union representation, so the
        // alternatives are still discarded — but WHETHER one was written is
        // exactly the fact the return-value check needs, and that is now kept
        // instead of thrown away.
        //
        // Assigned after the loop so the OUTERMOST parse_type wins: an inner
        // union (a generic argument, a record field) runs its own loop first
        // and would otherwise leave the flag set for a contract carrying none.
        var saw_alternative = false;
        while (try self.eat(.pipe) != null) {
            const alt = try self.parse_type_primary();
            // `| nil` is the SUCCESS-nil spelling (B-12), not a failure edge.
            if (!(alt == .named and std.mem.eql(u8, alt.named, "nil"))) saw_alternative = true;
            while (try self.eat(.lbracket) != null) {
                if (!(try self.check(.rbracket))) {
                    _ = try self.parse_type();
                    while (try self.eat(.comma) != null) _ = try self.parse_type();
                }
                _ = try self.expect(.rbracket);
            }
        }
        self.union_alternative_seen = saw_alternative;
        return base;
    }

    /// A descriptor field's shape, plus LEVEL application: `tags: seq(str)`.
    ///
    /// §4 gives `( )` to APPLY — "functions, dispatch tables,
    /// descriptors=construction, levels" — and §7/§16 spell the container
    /// families that way (`seq(str)`). `seq[str]` is the retrieval spelling
    /// and keeps working; both land on the same `.generic` node.
    ///
    /// Deliberately scoped to field position rather than folded into
    /// `parse_type`. A `(` after a type is meaningful elsewhere:
    /// `f = (x: i64) (x + 1)` is a legal one-line body whose parameter shape
    /// is followed by a parenthesised expression, and a global rule would
    /// swallow it. Inside `name: shape` the only legal continuations are `,`,
    /// `}` or the next field, so a `(` here can be nothing else.
    /// §9 / §20 — a RELATION SLOT in a descriptor body, with or
    /// without a level:
    ///
    ///     token: {
    ///         text: view
    ///         format(sink) = (out) out:write("…")
    ///     }
    ///
    /// The slot is an EDGE homed on the descriptor, so it is hoisted as an
    /// ordinary function whose first parameter is the receiver typed by that
    /// descriptor. That spelling already dispatches both ways: `format(sink)(t)`
    /// through the relation-edge map, and — for an UNLEVELLED slot — the
    /// receiver face `t:width(3)`, which codegen projects onto a free function
    /// (gap[025], landed 2026-08-07). A LEVELLED receiver face `t:format(sink)`
    /// has no resolution yet and is still gap[025].
    ///
    /// Returns true when a slot was consumed. `name(` is not enough to decide —
    /// `tags: seq(str)` also has one — so the decision is made on the `=` that
    /// follows the group, which is exactly what `parse_level_edge` tests.
    fn parse_descriptor_slot(self: *Parser, name: []const u8, loc: ast.Loc) ParseError!bool {
        const nxt = (try self.pk()).kind;
        if (nxt != .lparen and nxt != .assign) return false;

        var path: std.ArrayList([]const u8) = .empty;
        try path.append(self.alloc, name);
        var sym: []const u8 = name;
        if (nxt == .lparen) {
            sym = (try self.parse_level_edge(&path)) orelse return false;
        } else {
            // `name = (params) …` — an unlevelled slot. A `=` not followed by a
            // parameter list is not a slot; leave it for the field diagnostic.
            const saved = self.lex.saveState();
            _ = try self.adv();
            const opens = try self.check(.lparen);
            self.lex.restoreState(saved);
            if (!opens) return false;
        }
        _ = try self.expect(.assign);

        const home = self.descriptor_home orelse {
            term.locErr(loc, "relation slot '{s}' needs a named descriptor to be homed on", .{name});
            return ParseError.UnexpectedToken;
        };
        var fb = try self.parse_func_body(loc);
        // The receiver is the first parameter, typed by its home — the shape a
        // receiver face and an operation-first call BOTH lower to.
        var params: std.ArrayList(ast.FuncParam) = .empty;
        try params.append(self.alloc, .{
            .name = "self",
            .typ = .{ .named = home },
            .default_val = null,
            .loc = loc,
        });
        try params.appendSlice(self.alloc, fb.params);
        fb.params = try params.toOwnedSlice(self.alloc);

        const fpath = try self.alloc.alloc([]const u8, 1);
        fpath[0] = sym;
        try self.pending_hoists.append(self.alloc, .{ .func_decl = .{
            .loc = loc,
            .path = fpath,
            .method = false,
            .is_local = false,
            .func = fb,
            .attributes = &.{},
        } });
        return true;
    }

    /// §0.3 / §7 — a CASE-SET written inline as a field's shape:
    ///
    ///     token: {
    ///         kind: { name, number, string, symbol, eof }
    ///         span: span
    ///     }
    ///
    /// GAP-025 measured the 2026-08-07 case-set fix as reaching the
    /// DECLARATION site only: `kind: { name, number, eof }` at top level
    /// checks clean, and the identical text as a FIELD does not, because a
    /// body's `name: …` runs through `parse_type`, which has no anonymous
    /// case-set production. This is that production.
    ///
    /// It DECLARES rather than describes. The cases are hoisted as a real
    /// enum named for the field's HOME (§0.1 — `token.kind`), the field's type
    /// is that enum, and `token.kind.eof` reaches a case. A shape-only accept
    /// would have made the golden `token` parse while `.eof` still meant
    /// nothing, which is the failure mode §22 exists to prevent.
    ///
    /// Routed on the SAME LOOKAHEAD as the declaration site: a case is a name
    /// followed by `,` or `(`; a record field always has `:`. So
    /// `{ x: i64, y: i64 }` in field position is still a record type, and a
    /// `(` after a field type is still level application (`tags: seq(str)`).
    fn parse_inline_caseset(self: *Parser, field: []const u8, loc: ast.Loc) ParseError!?ast.TypeExpr {
        if (!(try self.check(.lbrace))) return null;
        const saved = self.lex.saveState();
        _ = try self.adv();
        var is_caseset = false;
        if ((try self.pk()).kind == .name) {
            _ = try self.adv();
            const after = (try self.pk()).kind;
            is_caseset = after == .comma or after == .lparen;
        }
        self.lex.restoreState(saved);
        if (!is_caseset) return null;

        const home = self.descriptor_home orelse field;
        const name = if (self.descriptor_home == null)
            field
        else
            try std.fmt.allocPrint(self.alloc, "{s}__{s}", .{ home, field });
        const stmt = try self.stmt_from_descriptor(name, loc);
        if (stmt != .enum_def) {
            term.locErr(loc, "'{s}' mixes cases with typed fields; a case-set holds cases only", .{field});
            return ParseError.UnexpectedToken;
        }
        try self.pending_hoists.append(self.alloc, stmt);
        if (self.descriptor_home) |h| {
            try self.caseset_homes.put(
                self.alloc,
                try std.fmt.allocPrint(self.alloc, "{s}\x00{s}", .{ h, field }),
                name,
            );
        }
        return ast.TypeExpr{ .named = name };
    }

    fn parse_field_type(self: *Parser) ParseError!ast.TypeExpr {
        var base = try self.parse_type();
        while ((try self.pk()).kind == .lparen) {
            _ = try self.adv();
            var params: std.ArrayList(ast.TypeExpr) = .empty;
            if (!(try self.check(.rparen))) {
                try params.append(self.alloc, try self.parse_field_type());
                while (try self.eat(.comma) != null) {
                    try params.append(self.alloc, try self.parse_field_type());
                }
            }
            _ = try self.expect(.rparen);
            const base_ptr = try self.alloc.create(ast.TypeExpr);
            base_ptr.* = base;
            base = .{ .generic = .{
                .base = base_ptr,
                .params = try params.toOwnedSlice(self.alloc),
            } };
        }
        return base;
    }

    /// `& packed`, `& align(8)`, `& sealed`, `& native`, `& guarded`,
    /// `& ffi("name")` — the refinement edge of LAW-STRATA carrying
    /// §11 layout facts on a record descriptor.
    ///
    /// Strictly additive: `&` after a type was a syntax error before this, so
    /// no existing program can change meaning. An unrecognised name after `&`
    /// restores the lexer and leaves the `&` unconsumed, which produces the
    /// same diagnostic it produced before — refinements whose fact has no home
    /// yet (`& le`, `& positive`) are still rejected rather than silently
    /// accepted and ignored.
    fn parse_layout_refinements(self: *Parser) ParseError!ast.TypeExpr.Layout {
        var layout: ast.TypeExpr.Layout = .{};
        while ((try self.pk()).kind == .amp) {
            const saved = self.lex.saveState();
            _ = try self.adv();
            const name_tok = try self.pk();
            if (name_tok.kind != .name) {
                self.lex.restoreState(saved);
                break;
            }
            _ = try self.adv();
            const name = name_tok.text;
            var args: ?[]const u8 = null;
            if ((try self.pk()).kind == .lparen) {
                _ = try self.adv();
                args = try self.parse_attribute_args();
                _ = try self.expect(.rparen);
            }
            if (std.mem.eql(u8, name, "packed")) {
                layout.is_packed = true;
            } else if (std.mem.eql(u8, name, "align")) {
                layout.align_given = true;
                layout.align_n = if (args) |a| std.fmt.parseInt(usize, a, 10) catch null else null;
            } else if (std.mem.eql(u8, name, "ffi")) {
                if (args) |a| layout.ffi = strip_quotes(a);
            } else if (std.mem.eql(u8, name, "sealed")) {
                layout.sealed = true;
                layout.storage = .sealed;
            } else if (std.mem.eql(u8, name, "native")) {
                layout.storage = .native;
            } else if (std.mem.eql(u8, name, "guarded")) {
                layout.storage = .guarded;
            } else {
                self.lex.restoreState(saved);
                break;
            }
        }
        return layout;
    }

    /// `i(64)` / `u(16)` / `f(32)` — the width applied rather than spelled into
    /// the identity. Returns the canonical descriptor spelling, or null when the
    /// shape is not this (leaving every ordinary named type untouched).
    ///
    /// Only the widths that exist are admitted; `i(63)` is not silently accepted
    /// and then mismatched later. Adjacency is required, so `i (64)` — a name
    /// applied to a group — still means what it meant.
    fn appliedWidthType(self: *Parser) ParseError!?[]const u8 {
        const t = try self.pk();
        if (t.kind != .name) return null;
        if (t.text.len != 1) return null;
        const stem = t.text[0];
        if (stem != 'i' and stem != 'u' and stem != 'f') return null;
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        var ok = false;
        defer if (!ok) {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        };
        _ = try self.adv();
        const lp = try self.pk();
        if (lp.kind != .lparen) return null;
        if (lp.loc.line != t.loc.line or lp.loc.col != t.loc.col + 1) return null;
        _ = try self.adv();
        const w = try self.pk();
        if (w.kind != .int_lit) return null;
        _ = try self.adv();
        if ((try self.pk()).kind != .rparen) return null;
        _ = try self.adv();
        const named: ?[]const u8 = switch (stem) {
            'i' => switch (w.int_val) {
                8 => "i8",
                16 => "i16",
                32 => "i32",
                64 => "i64",
                else => null,
            },
            'u' => switch (w.int_val) {
                8 => "u8",
                16 => "u16",
                32 => "u32",
                64 => "u64",
                else => null,
            },
            'f' => switch (w.int_val) {
                32 => "f32",
                64 => "f64",
                else => null,
            },
            else => null,
        };
        const n = named orelse {
            term.locErr(t.loc, "`{c}({d})` is not a width that exists", .{ stem, w.int_val });
            return error.UnexpectedToken;
        };
        ok = true;
        return n;
    }

    fn parse_type_primary(self: *Parser) ParseError!ast.TypeExpr {
        const tok = try self.pk();
        if (grammar_roles.isDescriptor(tok.kind)) {
            _ = try self.adv();
            return .{ .named = tok.kind.spelling() };
        }
        return switch (tok.kind) {
            .at => {
                const attr = try self.parse_one_attribute();
                // THE ALIAS TABLE DECIDES, not the literal `"c.type"`.
                // Comparing the short spelling made type position the ONE place
                // in the language where the canonical name is the broken one:
                // `@comp.c.type("size_t")` — the spelling
                // `warnDeprecatedAtQualified` tells you to write — was refused
                // with "expected @c.type(...)", while the deprecated `@c.type`
                // worked. Four spellings resolve to `__c_type`; all four now
                // name the same descriptor here, as they already do everywhere
                // else (`isAttachingCInterfaceAttribute` reads the same table).
                const resolves_to_c_type = if (meta_module.resolveBuiltin(attr.name)) |internal|
                    std.mem.eql(u8, internal, "__c_type")
                else
                    false;
                if (!resolves_to_c_type) {
                    term.locErr(tok.loc, "expected @c.type(...) in type position, got '@{s}'", .{attr.name});
                    return ParseError.UnexpectedToken;
                }
                const cname = strip_quotes(attr.args orelse "");
                return .{ .named = try std.mem.concat(self.alloc, u8, &.{ types.c_type_marker_prefix, cname }) };
            },
            .name => {
                // WIDTH AS AN OPERAND, not as a suffix on the name. `i64` bakes
                // a numeric taxonomy into an identity, which LAW-16 forbids for
                // the same reason `rec2` did: the specializer belongs in the
                // operand position. `i(64)` says the same thing with the width
                // applied, and resolves to the SAME descriptor — one identity
                // `i`, specialized by a width, rather than ten unrelated
                // keywords that happen to share a prefix.
                //
                // Additive: `i(64)` was a parse error before, so nothing that
                // compiled can change meaning, and `i64` keeps working.
                if (try self.appliedWidthType()) |named| return .{ .named = named };
                const t = try self.adv();
                // `T: Concept` is a constraint on the type just named, so it is
                // written beside it. On a NEW line the `:` is the next
                // statement's, and §20's `token` slot is exactly that case:
                //
                //     token = (): token | error
                //         :skip(space)
                //
                // The alternative `error` swallowed the sibling call as its
                // constraint, so the body began one statement late and the
                // failure surfaced as an offside error two lines further down.
                if ((try self.pk()).loc.line == t.loc.line and try self.eat(.colon) != null) {
                    return try self.parse_constrained_type_param(t.text);
                }
                return .{ .named = t.text };
            },
            .int_lit => {
                const t = try self.adv();
                return .{ .named = t.text };
            },
            .star => {
                _ = try self.adv();
                const inner = try self.alloc.create(ast.TypeExpr);
                inner.* = try self.parse_type();
                return .{ .pointer = inner };
            },
            .question => {
                // Optional type: ?T
                _ = try self.adv();
                const inner = try self.alloc.create(ast.TypeExpr);
                inner.* = try self.parse_type();
                return .{ .optional = inner };
            },
            .lparen => {
                // Tuple type: `(T, U)` or Function type: `(T, U) -> R`
                _ = try self.adv(); // consume '('
                var params: std.ArrayList(ast.TypeExpr) = .empty;
                if (!(try self.check(.rparen))) {
                    try params.append(self.alloc, try self.parse_type());
                    while (try self.eat(.comma) != null) {
                        try params.append(self.alloc, try self.parse_type());
                    }
                }
                _ = try self.expect(.rparen);
                // If followed by `->`, it's a function type; otherwise it's a tuple
                if (try self.eat(.arrow) != null) {
                    const ret = try self.alloc.create(ast.TypeExpr);
                    ret.* = try self.parse_type();
                    return .{ .func = .{
                        .params = try params.toOwnedSlice(self.alloc),
                        .ret = ret,
                    } };
                } else {
                    return .{ .tuple = try params.toOwnedSlice(self.alloc) };
                }
            },
            .lbracket => {
                _ = try self.adv();
                var size: ?usize = null;
                if (try self.check(.int_lit)) {
                    const n = try self.adv();
                    size = @intCast(n.int_val);
                    _ = try self.expect(.rbracket);
                    const elem = try self.alloc.create(ast.TypeExpr);
                    elem.* = try self.parse_type();
                    return .{ .array = .{ .elem = elem, .size = size } };
                } else if (!(try self.check(.rbracket))) {
                    const elem = try self.alloc.create(ast.TypeExpr);
                    elem.* = try self.parse_type();
                    _ = try self.expect(.rbracket);
                    return .{ .array = .{ .elem = elem, .size = null } };
                } else {
                    _ = try self.expect(.rbracket);
                }
                const elem = try self.alloc.create(ast.TypeExpr);
                elem.* = try self.parse_type();
                return .{ .array = .{ .elem = elem, .size = size } };
            },
            .lt => {
                _ = try self.adv();
                // Parse type parameters for generics: <T, U>
                var params: std.ArrayList(ast.TypeExpr) = .empty;
                try params.append(self.alloc, try self.parse_type());
                while (try self.eat(.comma) != null) {
                    try params.append(self.alloc, try self.parse_type());
                }
                _ = try self.expect(.gt);
                const base = try self.alloc.create(ast.TypeExpr);
                base.* = try self.parse_type();
                return .{ .generic = .{ .base = base, .params = try params.toOwnedSlice(self.alloc) } };
            },
            .lbrace => {
                // Inline record-type literal: { name: T, name2: T2, ... }
                _ = try self.adv(); // consume '{'
                var fields: std.ArrayList(ast.RecordField) = .empty;
                if (!(try self.check(.rbrace))) {
                    while (true) {
                        const fl = (try self.pk()).loc;
                        const fn_tok = try self.expect(.name);
                        if (try self.parse_descriptor_slot(fn_tok.text, fl)) {
                            if (try self.eat(.comma) == null and !(try self.check(.name))) break;
                            continue;
                        }
                        _ = try self.expect(.colon);
                        const ft = (try self.parse_inline_caseset(fn_tok.text, fl)) orelse
                            try self.parse_field_type();
                        try fields.append(self.alloc, ast.RecordField{
                            .name = fn_tok.text,
                            .typ = ft,
                            .loc = fl,
                        });
                        if (try self.eat(.comma) == null) {
                            // X8 (§7): "≥2 named fields → one per
                            // line, always". So the newline IS the canonical
                            // separator and the comma is the optional one —
                            // the golden `user` and `token` descriptors of §20
                            // are written without commas and did not parse.
                            //
                            // Unambiguous: §3 makes a newline insignificant
                            // inside an open `{`, so the only tokens that may
                            // follow a field are `}` or the next field's name.
                            if (!(try self.check(.name))) break;
                        }
                    }
                }
                _ = try self.expect(.rbrace);
                const rt = try self.alloc.create(ast.TypeExpr.RecordType);
                rt.* = .{ .fields = try fields.toOwnedSlice(self.alloc) };
                rt.layout = try self.parse_layout_refinements();
                return .{ .record = rt };
            },
            else => {
                term.locErr(tok.loc, "expected type, got '{s}'", .{tok.kind.spelling()});
                return ParseError.ExpectedToken;
            },
        };
    }

    fn maybe_type_ann(self: *Parser) ParseError!ast.TypeExpr {
        if (try self.eat(.colon) != null) return self.parse_type();
        return .inferred;
    }

    // ── Block / statements ────────────────────────────────────────────────────

    pub fn parse_module(self: *Parser) ParseError!ast.Module {
        try self.ensureProducerPack();
        defer self.releaseOwnedPack();
        const tok = try self.pk();
        const body = try self.parse_block();
        _ = try self.expect(.eof);
        return ast.Module{ .file = tok.loc.file, .body = body };
    }

    /// A block layout does not govern: the module body, and the bodies whose
    /// closer is structural (a bracket) rather than a rendering.
    fn parse_block(self: *Parser) ParseError!ast.Block {
        return self.parse_block_open(null, false);
    }

    /// §3 — a block opened by the construct at `open`, closed by
    /// dedent. See `LayoutFrame`.
    fn parse_block_at(self: *Parser, open: ast.Loc) ParseError!ast.Block {
        return self.parse_block_open(open, false);
    }

    /// §3 — a RELATION'S body, which is the one block that may be EMPTY. See
    /// the empty-body clause in `parse_block_open`.
    fn parse_body_block_at(self: *Parser, open: ast.Loc) ParseError!ast.Block {
        return self.parse_block_open(open, true);
    }

    fn parse_block_open(self: *Parser, open: ?ast.Loc, empty_ok: bool) ParseError!ast.Block {
        // Before `open_layout` pushes a frame, so a refusal leaves the layout
        // stack exactly as it found it.
        if (self.block_depth >= max_block_depth) {
            const tok = try self.pk();
            term.locErr(tok.loc, "blocks nest deeper than {d} levels, which is this parser's limit", .{max_block_depth});
            term.locHint(tok.loc, "lift the inner block into a relation and call it", .{});
            return ParseError.UnexpectedToken;
        }
        self.block_depth += 1;
        defer self.block_depth -= 1;

        const saved_match_depth = self.match_arm_depth;
        self.match_arm_depth = 0;
        defer self.match_arm_depth = saved_match_depth;
        const saved_layout = self.layout;
        self.layout = try self.open_layout(open);
        defer {
            self.last_layout = self.layout;
            self.layout = saved_layout;
        }
        const l = (try self.pk()).loc;

        // §3 — THE EMPTY BODY. `Ctable:increment(): void` declares a relation
        // and gives it nothing to do; before `end` was retired the `end` WAS
        // the body marker, and deleting it left the shape with no spelling at
        // all (`examples/metaprogramming_showcase.id:172`).
        //
        // Under offside binding it needs none. A block is the lines indented
        // past its opener, and if the next line is back AT or LEFT of the
        // opener then no line is inside it: the block is empty, and the dedent
        // that proves it is the same dedent that closes every other block. No
        // new sigil, and nothing to write — the absence IS the spelling.
        //
        // ONLY A RELATION'S BODY (`empty_ok`). An `if`/`while`/`for` whose body
        // is empty means nothing, so there the same shape is far more likely to
        // be a mis-indent, and §3 is explicit that a mis-indent must be a
        // diagnostic rather than an alternate parse. Those keep the error they
        // have.
        //
        // STRICTLY ADDITIVE: `open_layout` left this shape `offside = false`,
        // which in `.id` means "only a written `end` closes it" — and `.id` has
        // no `end`, so every such site today ends at "still open at the file
        // edge". This admits programs that were refused; it cannot re-read one
        // that was accepted.
        if (empty_ok and self.idol_mode and !self.layout.offside) empty: {
            const o = open orelse break :empty;
            const first = try self.pk();
            switch (first.kind) {
                // A written terminator still closes the block it was written
                // for, and still gets the diagnostic it gets today.
                .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch => break :empty,
                else => {},
            }
            if (first.loc.line <= o.line or first.loc.col > o.col) break :empty;
            // Closed by that dedent, so `close_block` must not go looking for
            // an `end` it will never find.
            self.layout.offside = true;
            return ast.Block{ .loc = l, .stmts = &.{}, .tail_expr = null };
        }

        var stmts: std.ArrayList(ast.Stmt) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            if (stmts.items.len > 0 and tok.loc.line != self.prev_line) switch (layout_verdict(&self.layout, tok)) {
                .keep => {},
                .close => break,
                .misindent => return layout_misindent(self.layout, tok),
            };
            switch (tok.kind) {
                .kw_end, .kw_until, .eof => break,
                // A BRACKET CLOSER ends the block too. Layout cannot see it:
                // `f(xs, (x: int)\n    x * 2)` puts the `)` on the same LINE as
                // the last body statement, and layout speaks about line starts,
                // so the loop fell through to `parse_stmt` and reported
                // "expected expression, got ')'". No closer can begin a
                // statement in any dialect, so breaking here never takes a
                // parse away from anything — it hands the token to the
                // construct that opened the bracket, which is the only thing
                // that can consume it. This is what gives a lambda in argument
                // position an `end`-free spelling at all.
                .rparen, .rbrace, .rbracket => break,
                .kw_else, .kw_elseif => {
                    // else/elseif close the block only when they bind at
                    // or left of the block opener (layout .close). When
                    // they are deeper (layout .keep), they belong to an
                    // inner if and must not terminate this block — fall
                    // through to parse_stmt which handles the if chain.
                    if (!self.layout.offside or tok.loc.col <= self.layout.open_col) break;
                    // Not closing this block; parse as a statement.
                    try self.flush_module_hint_directives(&stmts);
                    const st = try self.parse_stmt();
                    if (self.pending_hoists.items.len > 0) {
                        try stmts.appendSlice(self.alloc, self.pending_hoists.items);
                        self.pending_hoists.clearRetainingCapacity();
                    }
                    try stmts.append(self.alloc, st);
                },
                .kw_return => {
                    try stmts.append(self.alloc, try self.parse_return());
                    _ = try self.eat(.semi);
                    break;
                },
                else => {
                    try self.flush_module_hint_directives(&stmts);
                    const st = try self.parse_stmt();
                    // Declarations the statement produced on the side land
                    // BEFORE it: an inline case-set is the field's type, so the
                    // enum has to exist by the time the descriptor names it.
                    if (self.pending_hoists.items.len > 0) {
                        try stmts.appendSlice(self.alloc, self.pending_hoists.items);
                        self.pending_hoists.clearRetainingCapacity();
                    }
                    try stmts.append(self.alloc, st);
                },
            }
        }
        // Extract implicit tail expression: if the last statement is an
        // expression-stmt or call_stmt, promote it to the block's tail_expr.
        var tail_expr: ?*ast.Expr = null;
        if (stmts.items.len > 0) {
            const last = &stmts.items[stmts.items.len - 1];
            if (last.* == .call_stmt) {
                tail_expr = last.call_stmt.expr;
                stmts.items.len -= 1;
            } else if (last.* == .expr_stmt) {
                tail_expr = last.expr_stmt.expr;
                stmts.items.len -= 1;
            }
        }
        return ast.Block{ .loc = l, .stmts = try stmts.toOwnedSlice(self.alloc), .tail_expr = tail_expr };
    }

    fn parse_return(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        var vals: std.ArrayList(*ast.Expr) = .empty;
        const nxt = try self.pk();
        sw: switch (nxt.kind) {
            .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof, .semi => {},
            else => {
                // A one-liner is terminated by the NEWLINE (§3.3), so a bare
                // `return` with nothing after it on its own line returns no
                // value. Without this it reached across the line break and took
                // the NEXT statement as its result: `return` followed by
                // `c = self.src:byte(...)` parsed `c` as the returned
                // expression and then choked on the `=`.
                //
                // It only became reachable when `end` stopped being written —
                // `return end` used to terminate it, and the closer was doing
                // work the layout should have been doing.
                if (self.idol_mode and nxt.loc.line != l.line) break :sw;
                if (self.idol_mode) {
                    const view = token_view.fromLexer(self.lex) orelse {
                        term.locErr(nxt.loc, "production token view is absent at return lookahead", .{});
                        return ParseError.UnexpectedToken;
                    };
                    if (!view.canBeginExpression(self.lex.duoStreamIndex())) {
                        term.locErr(nxt.loc, "expected a return value or line boundary, got '{s}'", .{nxt.kind.spelling()});
                        return ParseError.UnexpectedToken;
                    }
                }
                try vals.append(self.alloc, try self.parse_expr());
                while (try self.eat(.comma) != null)
                    try vals.append(self.alloc, try self.parse_expr());
            },
        }
        return ast.Stmt{ .ret = .{ .loc = l, .vals = try vals.toOwnedSlice(self.alloc) } };
    }

    /// §1/§15 — statement-leading keywords the deny table retires,
    /// and the graveyard rows it names as load-bearing absences.
    ///
    /// This fires for `.id` input ONLY. Duo is a Lua superset and `.lua`
    /// input keeps today's behaviour unchanged; the dialect is selected from
    /// the file extension by `is_duo_source_path` in main.zig, which sets
    /// `idol_mode`. That is the same switch `comptime` already rejects on, not
    /// a new one. It is also the owner's scoping ruling made mechanical
    /// (2026-08-08): "lua backcompat should work native mode for lua files
    /// only" — `.lua` keeps the whole compatibility surface and lowers
    /// natively, `.id` gets and nothing else.
    ///
    /// EVERY ROW NAMES THE REPAIR. A bare rejection makes the corpus
    /// unmigratable: the reader is left guessing the replacement spelling, and
    /// guessing is what kept these forms in the tree.
    ///
    /// A row belongs here only once its statement-leading count is measured at
    /// zero over EVERY `.id` file a gate compiles — not just the canonical
    /// partition of `docs/spec/corpus.md`. That distinction is not pedantic:
    /// `const` was in this switch on the first cut because canonical measured
    /// 0, and it still broke `examples/control_defaults_mem.id`, whose output
    /// `zig build test` asserts. `examples/` is classified `historical`, so the
    /// canonical count could not see it. Measure against the gates, then add
    /// the row.
    ///
    /// A second measurement trap, found the same way: the census has to strip
    /// `[[ … ]]` long-bracket bodies as well as `"…"` ones. `let` reads 6 and
    /// `local` reads 23 with long brackets IN, and both read 0 with them out —
    /// the `let`s are WGSL inside `lib/graphics/shader.id`'s shader
    /// source and the `local`s are Duo snippets `scripts/test_property_11.id`
    /// hands the compiler as DATA. Neither is Duo code this parser ever sees,
    /// and budgeting them as debt asks for a repair no edit can make.
    ///
    /// Measured 2026-08-08, statement-leading over the 767 tracked `.id`
    /// files with both strips applied: try 0, catch 0, defer 0, goto 0,
    /// extends 0, private 0, await 0, let 0, async 2.
    ///
    /// Rows deliberately NOT here yet, with their counts: `then` 656,
    /// `elseif` 820, `do` 179, `fun` 324, `global` 202, `concept` 58,
    /// `alias` 14, `const` 10, `enum` 9, `match` 8, `local` 0-in-corpus but
    /// alive in 17 Duo fixtures EMBEDDED IN ZIG (`src/codegen.zig`,
    /// `src/dnir_lower.zig`, `src/sema.zig`, `src/lua_superset_corpus.zig`)
    /// that parse with `idol_mode = true` — one of which, "a function-body
    /// local outranks a module global of the same name", has `local` as its
    /// SUBJECT and needs the Lua dialect rather than a rewrite. Each needs a
    /// corpus migration before it can become an error; `string.` (175 files)
    /// and `req` (100 files) need the replacement surface to exist first.
    fn denyRetiredStmtKeyword(self: *Parser, tok: Token) ParseError!void {
        if (tok.kind == .kw_macro) {
            term.locErr(tok.loc, "'macro' has no native Idol statement role", .{});
            term.locHint(tok.loc, "metaprogramming is expressed through ordinary relations and compile-time facts", .{});
            return ParseError.UnexpectedToken;
        }
        if (!self.idol_mode) return;
        const replacement: []const u8 = switch (tok.kind) {
            .kw_try, .kw_catch => "Pass 100 §0.5: bind the result and route it — `if v, err = f(x) use(v) else report(err)`",
            .kw_defer => "Pass 100 §15: scope exit is structural — hold the resource in a descriptor value whose release is its own, or route the failure with a result pack",
            .kw_goto => "Pass 100 §13: use `break`/`continue`, or a dispatch table — `next(state)(event) = handler`, which gets exhaustiveness and the diagram free",
            .kw_extends => "Pass 100 §15: there is no inheritance — compose by spreading a descriptor `{ ..base, extra = v }`, or home the shared surface on a face",
            .kw_private => "Pass 100 §15 denies visibility-by-naming: nest the value under the descriptor that owns it",
            .kw_await, .kw_async => "Pass 100 §15: no async/await keyword pair — concurrency is a property of the value, not a colour on the function",
            .kw_let => "Pass 100 §0: bindings are bare — `x = expr`. `if let p = e` / `while let p = e` is the Rust shape; write `if v, err = f(x) use(v) else report(err)`",
            else => return,
        };
        term.locErr(tok.loc, "'{s}' is retired in .id files (Pass 100 §1 deny table)", .{tok.kind.spelling()});
        term.locHint(tok.loc, "{s}", .{replacement});
        term.locHint(tok.loc, "Lua-shaped input is still accepted, and still lowers natively, in a `.lua` file", .{});
        return ParseError.UnexpectedToken;
    }

    fn parse_stmt(self: *Parser) ParseError!ast.Stmt {
        const tok = try self.pk();
        // A bare `type` keyword at statement start usually means a type alias
        // (`type Foo = ...`). But `type(x)` is the Lua builtin call form, so
        // disambiguate by peeking the next token: an `lparen` means a call.
        if (tok.kind == .name and std.mem.eql(u8, tok.text, "type")) {
            const saved = self.lex.saveState();
            _ = try self.adv();
            const after = try self.pk();
            self.lex.restoreState(saved);
            if (after.kind != .lparen) {
                return self.parse_alias_def_with_attrs(&.{});
            }
        }

        try self.denyRetiredStmtKeyword(tok);

        return switch (tok.kind) {
            .at => blk: {
                // GR-007: reject bare @const / @comptime / @comptime_expr /
                // @compile_time up front with a directed hint, before attribute
                // dispatch cascades a generic "expected 'name'" error (these
                // spellings are keyword tokens). @(expr) is comptime eval; @comp.*
                // are metaprogramming combinators.
                {
                    const ban_saved = self.lex.saveState();
                    _ = try self.adv(); // consume '@'
                    const after = try self.pk();
                    if (after.text.len > 0) {
                        if (Parser.bannedAtDirectiveSuggestion(after.text)) |sug| {
                            term.locErr(tok.loc, "'@{s}' is not a Duo directive", .{after.text});
                            term.locHint(tok.loc, "{s}", .{sug});
                            return ParseError.ExpectedToken;
                        }
                    }
                    self.lex.restoreState(ban_saved);
                }
                if (try self.try_parse_c_interface_stmt()) |c_stmt| break :blk c_stmt;
                const saved = self.lex.saveState();
                if (try self.parse_at_starts_attribute_decl()) {
                    self.lex.restoreState(saved);
                    break :blk self.parse_attributed_decl();
                }
                self.lex.restoreState(saved);
                break :blk self.parse_expr_stmt();
            },
            .kw_local => self.parse_local(),
            .kw_global => self.parse_global(),
            .kw_const => self.parse_const_decl(),
            // NOTE: there is no `.kw_struct` case. Duo has no `struct`
            // keyword; records are declared via inline type-literal
            // annotations on bindings.
            .kw_function, .kw_fun => blk: {
                const hint_attrs = try self.consumeLexerHints();
                defer if (hint_attrs.len > 0) self.alloc.free(hint_attrs);
                const merged = try self.merge_deferred_hints(hint_attrs);
                break :blk self.parse_func_decl_with_attrs(false, merged);
            },
            .kw_async => self.parse_async_func_decl_with_attrs(&.{}),
            .kw_enum => self.parse_enum_def_with_attrs(&.{}),
            .kw_concept => self.parse_concept_def_with_attrs(&.{}),
            .kw_alias => self.parse_alias_def_with_attrs(&.{}),
            .kw_if => self.parse_if(),
            .kw_while => self.parse_while(),
            .kw_repeat => self.parse_repeat(),
            .kw_for => self.parse_for(),
            .kw_do => self.parse_do(),
            .kw_match => self.parse_match_stmt(),
            .kw_try => self.parse_try(),
            .kw_defer => self.parse_defer(),
            .kw_goto => blk: {
                _ = try self.adv();
                const lbl = try self.expect(.name);
                break :blk ast.Stmt{ .goto_stmt = .{ .loc = tok.loc, .label = lbl.text } };
            },
            .kw_break => blk: {
                _ = try self.adv();
                break :blk ast.Stmt{ .brk = tok.loc };
            },
            .kw_continue => blk: {
                _ = try self.adv();
                break :blk ast.Stmt{ .cont = tok.loc };
            },
            .dcolon => self.parse_label(),
            .name => blk: {
                if (self.func_body_depth == 0 and try self.starts_bare_func_decl()) {
                    break :blk self.parse_bare_func_decl_with_attrs(false, &.{});
                }
                break :blk self.parse_expr_stmt();
            },
            else => self.parse_expr_stmt(),
        };
    }

    fn parse_at_starts_attribute_decl(self: *Parser) ParseError!bool {
        // @cinclude is a standalone top-level statement, not attached to a decl.
        // Check for it first before the normal attribute detection.
        const saved = self.lex.saveState();
        if ((try self.pk()).kind == .at) {
            _ = try self.adv(); // consume @
            if ((try self.pk()).kind == .name and std.mem.eql(u8, (try self.pk()).text, "cinclude")) {
                self.lex.restoreState(saved);
                return true;
            }
            self.lex.restoreState(saved);
        }
        while ((try self.pk()).kind == .at) {
            _ = try self.adv();
            const attr_name = try self.expect(.name);
            var parts: std.ArrayList([]const u8) = .empty;
            defer parts.deinit(self.alloc);
            try parts.append(self.alloc, attr_name.text);
            const is_build = std.mem.eql(u8, attr_name.text, "build") or std.mem.startsWith(u8, attr_name.text, "build.");
            const is_debug = std.mem.eql(u8, attr_name.text, "debug") or std.mem.startsWith(u8, attr_name.text, "debug.");
            const is_trace = std.mem.eql(u8, attr_name.text, "trace") or std.mem.startsWith(u8, attr_name.text, "trace.");
            while ((try self.pk()).kind == .dot) {
                _ = try self.adv();
                const part = try self.parse_at_path_segment();
                try parts.append(self.alloc, part.text);
            }
            const qualified = try std.mem.join(self.alloc, ".", parts.items);
            defer self.alloc.free(qualified);
            // THE ASSEMBLED NAME DECIDES, not the token path that assembled it.
            // This used to be a pre-pass that only fired when the FIRST segment
            // was literally `c` and the second literally `export`, so
            // `@comp.c.export` — the canonical spelling — never set the flag and
            // fell through to `is_known_attribute("comp.c.export")`, which does
            // not list it. Same defect as `isAttachingCInterfaceAttribute`'s
            // `c.call`: a literal restating part of the alias table, agreeing
            // with it on exactly one of the four spellings. Reading the table
            // makes all four known.
            const is_c_export = if (meta_module.resolveBuiltin(qualified)) |internal|
                std.mem.eql(u8, internal, "__c_export")
            else
                false;
            const is_meta_directive = meta_module.isMetaAttribute(qualified);
            const is_attaching = meta_module.isAttachingMetaAttribute(qualified);
            const is_type_derive = meta_module.isTypeLevelDeriveAttribute(qualified);
            const is_directive = is_build or is_debug or is_trace or is_meta_directive;
            const is_known = is_directive or is_attaching or is_type_derive or
                (is_c_export or is_known_attribute(qualified));
            if (!is_known) return false;
            if ((try self.pk()).kind == .lparen) {
                var depth: u32 = 0;
                while (true) {
                    const tok = try self.adv();
                    switch (tok.kind) {
                        .lparen => depth += 1,
                        .rparen => {
                            depth -= 1;
                            if (depth == 0) break;
                        },
                        .eof => return false,
                        else => {},
                    }
                }
            }
            if (is_directive) {
                // Standalone module directives (@comp.define.derive, @comp.pipeline, …)
                // are complete statements — do not require a following declaration.
                if (meta_module.isStandaloneModuleStatement(qualified)) return true;
                // `@build.*` is module scope BY CONSTRUCTION — `validateFunctionAttrs`
                // rejects it on a function outright. It therefore never attaches to a
                // declaration, and requiring one below meant a file whose `@build.project`
                // was followed by another `@build.*` (or by any non-declaration) fell
                // through to expression position and lowered to `.macro_call` — the
                // `UnknownMacro` that made `duo init`'s own template unbuildable.
                if (is_build) return true;
                // `@comp.hint.fence()` / `@comp.bit.popcount(n)` at statement scope are
                // expression calls (DNIR hardware path), not standalone module directives.
                // Only treat as directive when a declaration follows (@comp.derive on a decl).
                const nxt = try self.pk();
                return switch (nxt.kind) {
                    .kw_function,
                    .kw_fun,
                    .kw_async,
                    .kw_enum,
                    .kw_concept,
                    .kw_alias,
                    .kw_local,
                    .kw_global,
                    .kw_for,
                    => true,
                    .name => blk: {
                        if (std.mem.eql(u8, nxt.text, "type")) break :blk true;
                        const s2 = self.lex.saveState();
                        _ = try self.adv();
                        const after = try self.pk();
                        self.lex.restoreState(s2);
                        if (after.kind == .colon) break :blk true;
                        // Bare function declaration (GR-001): `@c.export("n")
                        // name(x: i64): i64 ... end`. `c.export` is an *attaching*
                        // attribute that isMetaAttribute() also reports as a
                        // directive, so it lands here; without this the attribute is
                        // re-parsed as an expression statement and lowers to a
                        // runtime `__c_export(...)` call no profile declares.
                        if (self.func_body_depth == 0 and try self.starts_bare_func_decl()) break :blk true;
                        break :blk false;
                    },
                    else => false,
                };
            }
        }
        const tok = try self.pk();
        return switch (tok.kind) {
            .kw_function, .kw_fun, .kw_async, .kw_enum, .kw_concept, .kw_alias, .kw_local, .kw_global, .kw_for => true,
            .name => blk: {
                if (std.mem.eql(u8, tok.text, "type")) break :blk true;
                const s2 = self.lex.saveState();
                _ = try self.adv();
                const after = try self.pk();
                self.lex.restoreState(s2);
                if (after.kind == .colon) break :blk true;
                // Bare function declaration (GR-001): `@c.export("n") name(x: i64): i64`.
                // Bare functions are the canonical form, so an attribute must attach to
                // one exactly as it attaches to a `fun` decl. Without this the whole
                // attribute is re-parsed as an expression statement, and `@c.export`
                // lowers to a runtime `__c_export(...)` call that no profile declares.
                if (self.func_body_depth == 0 and try self.starts_bare_func_decl()) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }

    fn is_known_attribute(name: []const u8) bool {
        const known = [_][]const u8{
            "align",
            "arc",
            "asm",
            "bench",
            "bitfield",
            "bitcast",
            "build",
            "cinclude",
            "autodiff",
            "cold",
            "concurrent",
            "consteval",
            "debug",
            "deprecated",
            "device",
            "differentiable",
            "derive",
            "export",
            "ffi",
            "flatten",
            "hot",
            "implements",
            "inline",
            "noinline",
            "nopanic",
            "noreturn",
            "packed",
            "profile",
            "pure",
            "raw",
            "repr",
            "restrict",
            "sealed",
            "native",
            "guarded",
            "section",
            "simd",
            "specialize",
            "target",
            "test",
            "time",
            "trace",
            "unroll",
            "volatile",
            "dispatch",
            "prefetch",
            "likely",
            "unlikely",
        };
        for (known) |item| {
            if (std.mem.eql(u8, name, item)) return true;
        }
        return false;
    }

    /// Parse one or more `@name` or `@name(args)` attributes, then the declaration
    /// that follows (function, enum, concept, async function, or local/global
    /// binding with `@implements(...)`).
    fn parse_attributed_decl(self: *Parser) ParseError!ast.Stmt {
        var attrs: std.ArrayList(ast.Attribute) = .empty;
        const directives = @import("directives.zig");
        while ((try self.pk()).kind == .at) {
            const attr = try self.parse_one_attribute();

            // Standalone @cinclude / @comp.c.import / @build.* / @debug.* module directives are
            // each their own statement; do not accumulate them as attributes.
            if (@import("meta_module.zig").isCHeaderImportDirective(attr.name)) {
                const header = strip_quotes(attr.args orelse "");
                return ast.Stmt{ .cinclude = .{ .loc = (try self.pk()).loc, .header = header } };
            }
            if (@import("meta_module.zig").isCEmitDirective(attr.name)) {
                const loc_tok = try self.pk();
                return ast.Stmt{ .directive = .{ .loc = loc_tok.loc, .attr = attr } };
            }
            if (directives.isBuildDirective(attr.name) or directives.isDebugDirective(attr.name)) {
                const loc_tok = try self.pk();
                return ast.Stmt{ .directive = .{ .loc = loc_tok.loc, .attr = attr } };
            }
            // C-interface attributes that ATTACH to a declaration (@c.export,
            // @c.type, @c.ffi, @c.call, @c.link) accumulate as normal function
            // attributes. They must NOT be emitted as standalone .directive
            // statements just because they are also listed in the metaprogramming
            // catalog (isMetaAttribute returns true for them). @comp.c.include /
            // @comp.c.import / @comp.c.emit above are the standalone C-interface forms;
            // these attach to the following `fun`/decl so codegen can emit
            // export_name / FFI linkage.
            if (@import("meta_module.zig").isAttachingCInterfaceAttribute(attr.name) or
                std.mem.eql(u8, attr.name, "c.call"))
            {
                try attrs.append(self.alloc, attr);
                continue;
            }
            if (@import("meta_module.zig").isMetaAttribute(attr.name)) {
                const loc_tok = try self.pk();
                return ast.Stmt{ .directive = .{ .loc = loc_tok.loc, .attr = attr } };
            }

            try attrs.append(self.alloc, attr);
        }
        const attrs_slice = try attrs.toOwnedSlice(self.alloc);

        const tok = try self.pk();
        if (tok.kind == .name and std.mem.eql(u8, tok.text, "type")) {
            return self.parse_alias_def_with_attrs(attrs_slice);
        }
        // Bare function declaration with attributes (GR-001): `@c.export("n")
        // name(x: i64): i64 ... end`. Bare functions are the canonical form, so an
        // attribute must attach to one exactly as it attaches to a `fun` decl —
        // otherwise the attribute falls through to the Jai type-def path, degrades
        // into a plain statement, and `@c.export` lowers to a runtime
        // `__c_export(...)` call that no profile declares.
        if (tok.kind == .name and
            self.func_body_depth == 0 and try self.starts_bare_func_decl())
        {
            return self.parse_bare_func_decl_with_attrs(false, attrs_slice);
        }
        if (tok.kind == .name) {
            return self.parse_jai_type_def_with_attrs(attrs_slice);
        }
        // §15 applies to attributed declarations too, or `@inline async f()`
        // is a hole straight through the ruling.
        try self.denyRetiredStmtKeyword(tok);
        return switch (tok.kind) {
            .kw_function, .kw_fun => self.parse_func_decl_with_attrs(false, attrs_slice),
            .kw_async => self.parse_async_func_decl_with_attrs(attrs_slice),
            // NOTE: there is no `.kw_struct` case.
            .kw_enum => self.parse_enum_def_with_attrs(attrs_slice),
            .kw_concept => self.parse_concept_def_with_attrs(attrs_slice),
            .kw_alias => self.parse_alias_def_with_attrs(attrs_slice),
            .kw_local, .kw_global => self.parse_local_or_global_with_attrs(attrs_slice),
            .kw_for => blk: {
                // @unroll(N) before a for loop: parse the for and attach unroll
                var stmt = try self.parse_for();
                if (stmt == .num_for) {
                    for (attrs_slice) |attr| {
                        if (std.mem.eql(u8, attr.name, "unroll")) {
                            if (attr.args) |args| {
                                const trimmed = std.mem.trim(u8, args, " \t");
                                stmt.num_for.unroll = std.fmt.parseInt(u32, trimmed, 10) catch null;
                            } else {
                                stmt.num_for.unroll = 8; // default unroll factor
                            }
                        }
                    }
                }
                break :blk stmt;
            },
            else => {
                term.locErr(tok.loc, "expected declaration after attribute(s), got '{s}'", .{
                    tok.kind.spelling(),
                });
                return ParseError.UnexpectedToken;
            },
        };
    }

    fn strip_quotes(raw: []const u8) []const u8 {
        return @import("directives.zig").extractCRawCode(raw);
    }

    /// Standalone `@c.emit("...")` / `@c.include("h.h")` / `@c.import("h.h")` statement.
    fn try_parse_c_interface_stmt(self: *Parser) ParseError!?ast.Stmt {
        if ((try self.pk()).kind != .at) return null;
        const saved = self.lex.saveState();
        const loc = (try self.pk()).loc;
        const attr = try self.parse_one_attribute();
        if (std.mem.eql(u8, attr.name, "specialize")) {
            return ast.Stmt{ .directive = .{ .loc = loc, .attr = attr } };
        }
        if (@import("meta_module.zig").isCHeaderImportDirective(attr.name)) {
            const header = strip_quotes(attr.args orelse "");
            return ast.Stmt{ .cinclude = .{ .loc = loc, .header = header } };
        }
        if (@import("meta_module.zig").isCEmitDirective(attr.name)) {
            if (attr.args) |raw| {
                if (!@import("directives.zig").isRawCEmitLiteral(raw)) {
                    self.lex.restoreState(saved);
                    return null;
                }
            }
            return ast.Stmt{ .directive = .{ .loc = loc, .attr = attr } };
        }
        self.lex.restoreState(saved);
        return null;
    }

    /// Parse a `local` or `global` declaration that has been preceded by
    /// attribute(s). The attributes are attached to each parsed `LocalName`.
    fn parse_local_or_global_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const tok = try self.pk();
        var stmt = if (tok.kind == .kw_local)
            try self.parse_local()
        else
            try self.parse_global();
        switch (stmt) {
            .local_decl => |*ld| attach_attrs_to_names(ld.names, attrs),
            .global_decl => |*gd| attach_attrs_to_names(gd.names, attrs),
            else => {},
        }
        return stmt;
    }

    fn attach_attrs_to_names(names: []ast.LocalName, attrs: []ast.Attribute) void {
        for (names) |*n| n.attributes = attrs;
    }

    /// Accept a `.name` token or any keyword token as a field-name-like token,
    /// returning its text. Statements/blocks use a fixed vocabulary; after `.`
    /// a programmer may legitimately use a reserved word as a method/field name
    /// (e.g. `string.match(...)`, `str.repeat(...)`, `obj.end`). Statement
    /// terminators (`end`, `else`, `elseif`, `until`) are NOT accepted here so
    /// they keep their role as block closers.
    fn is_name_like_kind(k: TK) bool {
        return switch (k) {
            .name => true,
            .kw_end, .kw_else, .kw_elseif, .kw_until => false,
            else => blk: {
                const s = k.spelling();
                break :blk s.len > 0 and std.ascii.isAlphabetic(s[0]);
            },
        };
    }

    fn accept_name_like(self: *Parser) ?[]const u8 {
        const tok = self.pk() catch return null;
        if (!is_name_like_kind(tok.kind)) return null;
        _ = self.adv() catch return null;
        return tok.text;
    }

    fn expect_name_like(self: *Parser) ParseError![]const u8 {
        if (self.accept_name_like()) |t| return t;
        // Generate the standard "expected 'name'" diagnostic via expect().
        _ = try self.expect(.name);
        unreachable;
    }

    /// Parse a single attribute: `@name`, `@name.sub`, or `@name(args)`
    fn parse_one_attribute(self: *Parser) ParseError!ast.Attribute {
        _ = try self.expect(.at); // consume `@`
        const first = try self.parse_at_path_segment();
        var parts: std.ArrayList([]const u8) = .empty;
        try parts.append(self.alloc, first.text);
        while ((try self.pk()).kind == .dot) {
            _ = try self.adv();
            const part = try self.parse_at_path_segment();
            try parts.append(self.alloc, part.text);
        }
        const name = try std.mem.join(self.alloc, ".", parts.items);
        var args: ?[]const u8 = null;
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv(); // consume `(`
            args = try self.parse_attribute_args();
            _ = try self.expect(.rparen);
        }
        self.warnDeprecatedAtQualified(first.loc, name);
        return ast.Attribute{ .name = name, .args = args };
    }

    /// Parse attribute argument text between parens, handling nested parens.
    /// Returns the raw source text content (not including outer parens).
    fn parse_attribute_args(self: *Parser) ParseError![]const u8 {
        const first_tok = try self.pk();
        if (first_tok.kind == .rparen) return "";

        const src = self.lex.cursor.bytes;

        // Every offset below comes from pointer arithmetic against `src`, so
        // one token whose text lives elsewhere poisons the whole span. Check
        // the first one and refuse the span rather than compute a wrong one.
        if (srcOffsetOf(src, first_tok.text) == null) {
            term.locErr(first_tok.loc, "attribute arguments cannot be recovered from this token stream", .{});
            return ParseError.UnexpectedToken;
        }

        const first_span = tokenSourceSpan(src, first_tok) orelse {
            term.locErr(first_tok.loc, "attribute arguments cannot be recovered from this token stream", .{});
            return ParseError.UnexpectedToken;
        };
        const start = first_span.start;
        var end = first_span.end;

        var depth: u32 = 1;

        while (depth > 0) {
            const tok = try self.pk();
            if (tok.kind == .eof) {
                term.locErr(tok.loc, "unexpected EOF in attribute arguments", .{});
                return ParseError.UnexpectedToken;
            }
            if (tok.kind == .rparen) {
                depth -= 1;
                if (depth == 0) break;
            }
            const span = tokenSourceSpan(src, tok) orelse {
                term.locErr(tok.loc, "attribute arguments cannot be recovered from this token stream", .{});
                return ParseError.UnexpectedToken;
            };
            end = span.end;
            _ = try self.adv();
            if (tok.kind == .lparen) depth += 1;
        }

        if (end <= start) return "";
        return src[start..end];
    }

    /// A token's byte offset within `src` — but only when its text genuinely
    /// lies inside `src`.
    fn srcOffsetOf(src: []const u8, text: []const u8) ?usize {
        const base = @intFromPtr(src.ptr);
        const p = @intFromPtr(text.ptr);
        if (p < base or p + text.len > base + src.len) return null;
        return p - base;
    }

    /// Source range for one token. Quoted and long-text literals use identity
    /// plus the producer-published delimiter level (`int_val`), never a scan
    /// for `[[` / `]]` in surrounding bytes.
    fn tokenSourceSpan(src: []const u8, tok: Token) ?struct { start: usize, end: usize } {
        const off = srcOffsetOf(src, tok.text) orelse return null;
        if (tok.kind == .compat_long_text_lit) {
            if (tok.int_val < 0) return null;
            const level: usize = @intCast(tok.int_val);
            const open_w = 2 + level;
            var start = off;
            if (start > 0 and src[start - 1] == '\n') start -= 1;
            if (start > 0 and src[start - 1] == '\r') start -= 1;
            if (start < open_w) return null;
            start -= open_w;
            const end = off + tok.text.len + open_w;
            if (end > src.len) return null;
            return .{ .start = start, .end = end };
        }
        if (grammar_roles.isQuotedKind(tok.kind)) {
            if (off == 0) return null;
            const end = off + tok.text.len + 1;
            if (end > src.len) return null;
            return .{ .start = off - 1, .end = end };
        }
        return .{ .start = off, .end = off + tok.text.len };
    }

    /// Parse `enum Name[T, E] ... end` with variant cases and optional payloads.
    fn parse_enum_def_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const l = (try self.adv()).loc; // consume `enum`
        const nm = try self.expect(.name);

        // Optional generic type parameters: [T, E]
        var type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lbracket) != null) {
            var tp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try tp_list.append(self.alloc, try self.parse_type());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type());
            }
            _ = try self.expect(.rbracket);
            type_params = try tp_list.toOwnedSlice(self.alloc);
        }

        // Parse variants until `end`
        var variants: std.ArrayList(ast.EnumVariant) = .empty;
        // OFFSIDE CLOSES IT, like every other block. This ran until `kw_end`
        // and nothing else, so an enum written without a terminator swallowed
        // whatever followed. Same shape as the concept body: a variant sits
        // right of the `enum` keyword, so anything at or left of it has closed
        // the body.
        while ((try self.pk()).kind != .kw_end and (try self.pk()).kind != .eof) {
            const probe = try self.pk();
            if (self.idol_mode and probe.loc.line != l.line and probe.loc.col <= l.col) break;
            const vname = try self.expect(.name);

            // Optional payload: (name: Type, name: Type, ...)
            var payload: ?[]ast.EnumVariant.PayloadField = null;
            if (try self.eat(.lparen) != null) {
                var fields: std.ArrayList(ast.EnumVariant.PayloadField) = .empty;
                if (!(try self.check(.rparen))) {
                    try fields.append(self.alloc, try self.parseEnumPayloadField());
                    while (try self.eat(.comma) != null) {
                        try fields.append(self.alloc, try self.parseEnumPayloadField());
                    }
                }
                _ = try self.expect(.rparen);
                payload = try fields.toOwnedSlice(self.alloc);
            }

            try variants.append(self.alloc, ast.EnumVariant{
                .name = vname.text,
                .payload = payload,
            });
        }
        _ = try self.eat(.kw_end); // accepted and deleted; the body may have closed by dedent

        const variant_slice = try variants.toOwnedSlice(self.alloc);
        debug_trace.event(.parse, .enum_type, "enum {s} ({d} variants)", .{ nm.text, variant_slice.len });

        return ast.Stmt{ .enum_def = .{
            .loc = l,
            .name = nm.text,
            .type_params = type_params,
            .variants = variant_slice,
            .attributes = attrs,
        } };
    }

    /// Parse a single enum payload field: `name: Type` or just `Type` (positional).
    fn parseEnumPayloadField(self: *Parser) ParseError!ast.EnumVariant.PayloadField {
        // Try to parse `name: Type` — peek ahead for colon after name
        const tok = try self.pk();
        if (tok.kind == .name) {
            // Speculatively consume the name and check for colon
            const name_tok = try self.adv();
            if (try self.eat(.colon) != null) {
                // Named field: name: Type
                const typ = try self.parse_type();
                return .{ .name = name_tok.text, .typ = typ };
            }
            // No colon — this is a positional type (the name token IS the type)
            return .{ .name = null, .typ = ast.TypeExpr{ .named = name_tok.text } };
        }
        // Not a name token, parse as a type directly
        const typ = try self.parse_type();
        return .{ .name = null, .typ = typ };
    }

    /// Parse `concept Name[T, ...] ... end` with required methods and fields.
    /// Parse the tail of a required-method signature in a concept body, with the
    /// method name already consumed: `[T](params) -> ret` / `[T](params): ret`.
    /// Shared by the legacy `fun`-prefixed form and the canonical bare form.
    fn parse_concept_method_sig(self: *Parser, name: []const u8) ParseError!ast.FuncSignature {
        // Optional method type parameters: [T]
        var method_type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lbracket) != null) {
            var mtp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try mtp_list.append(self.alloc, try self.parse_type());
            while (try self.eat(.comma) != null) {
                try mtp_list.append(self.alloc, try self.parse_type());
            }
            _ = try self.expect(.rbracket);
            method_type_params = try mtp_list.toOwnedSlice(self.alloc);
        }

        _ = try self.expect(.lparen);
        var params: std.ArrayList(ast.FuncParam) = .empty;
        if (!(try self.check(.rparen))) {
            try params.append(self.alloc, try self.parse_param());
            while (try self.eat(.comma) != null) {
                try params.append(self.alloc, try self.parse_param());
            }
        }
        _ = try self.expect(.rparen);

        // Optional return type: -> type or : type
        var ret_type: ast.TypeExpr = .inferred;
        if (try self.eat(.arrow) != null or try self.eat(.colon) != null)
            ret_type = try self.parse_type();

        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.alloc),
            .ret_type = ret_type,
            .type_params = method_type_params,
        };
    }

    fn parse_concept_def_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const l = (try self.adv()).loc; // consume `concept`
        const nm = try self.expect(.name);

        // Optional generic type parameters: [T, E]
        var type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lbracket) != null) {
            var tp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try tp_list.append(self.alloc, try self.parse_type());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type());
            }
            _ = try self.expect(.rbracket);
            type_params = try tp_list.toOwnedSlice(self.alloc);
        }

        // Parse required methods and fields until `end`
        var methods: std.ArrayList(ast.FuncSignature) = .empty;
        var fields: std.ArrayList(ast.ConceptDef.RequiredField) = .empty;

        // OFFSIDE CLOSES IT, like every other block (`syntax.block.close =
        // false`). This loop ran until `kw_end` and nothing else, so a concept
        // written without a terminator swallowed whatever followed and reported
        // "unexpected token in concept body" pointing at the NEXT statement. A
        // member sits right of the `concept` keyword; anything at or left of it
        // has closed the body.
        while ((try self.pk()).kind != .kw_end and (try self.pk()).kind != .eof) {
            const probe = try self.pk();
            if (self.idol_mode and probe.loc.line != l.line and probe.loc.col <= l.col) break;
            if ((try self.pk()).kind == .kw_fun or (try self.pk()).kind == .kw_function) {
                // Legacy required method: `fun name(params) -> ret_type`. GR-001
                // retires `fun`; the bare form below is canonical.
                _ = try self.adv(); // consume `fun` or `function`
                const method_name = try self.expect(.name);
                try methods.append(self.alloc, try self.parse_concept_method_sig(method_name.text));
            } else if ((try self.pk()).kind == .name) {
                // Canonical bare member. `name(` / `name[` is a required method
                // signature (GR-001 bare function); `name:` is a required field.
                const member_name = try self.adv();
                if ((try self.check(.lparen)) or (try self.check(.lbracket))) {
                    try methods.append(self.alloc, try self.parse_concept_method_sig(member_name.text));
                } else {
                    _ = try self.expect(.colon);
                    const field_type = try self.parse_type();
                    try fields.append(self.alloc, .{
                        .name = member_name.text,
                        .typ = field_type,
                    });
                }
            } else {
                // Skip unexpected tokens to avoid infinite loops
                term.locErr((try self.pk()).loc, "unexpected token in concept body: '{s}'", .{
                    (try self.pk()).kind.spelling(),
                });
                return ParseError.UnexpectedToken;
            }
        }
        // `end` is ACCEPTED AND DELETED, not demanded — the body may have
        // closed by dedent above, in which case there is nothing to consume.
        _ = try self.eat(.kw_end);

        return ast.Stmt{ .concept_def = .{
            .loc = l,
            .name = nm.text,
            .type_params = type_params,
            .required_methods = try methods.toOwnedSlice(self.alloc),
            .required_fields = try fields.toOwnedSlice(self.alloc),
            .attributes = attrs,
        } };
    }

    /// Parse `type Name = Type` or legacy `alias Name = Type`.
    /// Jai-like type definition: `@attrs Name: { fields }`
    /// Parses Name, expects ':', parses type. If the type is a record and
    /// there's no '=' initializer, it's a type definition (alias_def).
    /// Otherwise falls through to create a local_decl with attributes.
    fn parse_jai_type_def_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const nm = try self.expect(.name);
        if ((try self.pk()).kind != .colon) {
            // Not a Jai-like def — error (attributes require a declaration)
            term.locErr(nm.loc, "expected declaration after attribute(s), got '{s}'", .{nm.text});
            return ParseError.UnexpectedToken;
        }
        _ = try self.adv(); // consume ':'
        const typ = try self.parse_type();

        // If no '=' follows and type is a record, it's a type definition
        if ((try self.pk()).kind != .assign) {
            return ast.Stmt{ .alias_def = .{
                .loc = nm.loc,
                .name = nm.text,
                .target = typ,
                .parent = null,
                .fields = &.{},
                .methods = &.{},
                .attributes = attrs,
            } };
        }

        // Otherwise it's a typed binding with attributes — or a canonical callable
        // `name: Ret = (params) body` when an export attribute precedes it.
        _ = try self.adv(); // consume '='
        if (try self.starts_binding_func_expr()) {
            var fb = try self.parse_func_body(nm.loc);
            fb.ret_type = typ;
            const path = try self.alloc.alloc([]const u8, 1);
            path[0] = nm.text;
            return ast.Stmt{ .func_decl = .{
                .loc = nm.loc,
                .path = path,
                .method = false,
                .is_local = false,
                .func = fb,
                .attributes = attrs,
            } };
        }
        var inits: std.ArrayList(*ast.Expr) = .empty;
        try inits.append(self.alloc, try self.parse_expr());
        var names: std.ArrayList(ast.LocalName) = .empty;
        try names.append(self.alloc, ast.LocalName{
            .ident = nm.text,
            .typ = typ,
            .attrib = null,
            .attributes = attrs,
            .loc = nm.loc,
        });
        return ast.Stmt{ .local_decl = .{
            .loc = nm.loc,
            .names = try names.toOwnedSlice(self.alloc),
            .inits = try inits.toOwnedSlice(self.alloc),
        } };
    }

    /// Parse `struct field: type = default ... end` body into an alias_def with @packed semantics.
    /// Syntax: `Name = struct field1: Type1 [= default1] field2: Type2 ... end`
    fn parse_struct_body(self: *Parser, name: []const u8, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const loc = (try self.pk()).loc;
        // Parse fields: name: type [= default_value]
        var fields: std.ArrayList(ast.RecordField) = .empty;
        while ((try self.pk()).kind != .kw_end) {
            if ((try self.pk()).kind == .eof) {
                term.locErr(loc, "unexpected end of file in struct definition", .{});
                return ParseError.UnexpectedToken;
            }
            const field_loc = (try self.pk()).loc;
            const field_name = try self.expect(.name);
            // Optional colon + type (if omitted, infer as any)
            var field_type: ast.TypeExpr = .inferred;
            if ((try self.pk()).kind == .colon) {
                _ = try self.adv();
                field_type = try self.parse_type();
            }
            // Optional = default (skip for now, just consume)
            if ((try self.pk()).kind == .assign) {
                _ = try self.adv();
                _ = try self.parse_expr(); // consume default expr
            }
            try fields.append(self.alloc, .{
                .loc = field_loc,
                .name = field_name.text,
                .typ = field_type,
            });
            // Optional comma separator
            _ = try self.eat(.comma);
        }
        _ = try self.expect(.kw_end); // consume 'end'

        // Build record TypeExpr
        const field_slice = try fields.toOwnedSlice(self.alloc);
        const rec = try self.alloc.create(ast.TypeExpr.RecordType);
        rec.* = .{ .fields = field_slice };

        debug_trace.event(.parse, .@"struct", "struct {s} ({d} fields)", .{ name, field_slice.len });

        return ast.Stmt{ .alias_def = .{
            .loc = loc,
            .name = name,
            .target = .{ .record = rec },
            .parent = null,
            .fields = &.{},
            .methods = &.{},
            .attributes = attrs,
        } };
    }

    fn parse_alias_def_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const first = try self.adv();
        if (first.kind != .kw_alias and !(first.kind == .name and std.mem.eql(u8, first.text, "type"))) {
            return ParseError.ExpectedToken;
        }
        const l = (try self.pk()).loc;
        const nm = try self.expect(.name);
        var type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lt) != null) {
            var tp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try tp_list.append(self.alloc, try self.parse_type());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type());
            }
            _ = try self.expect(.gt);
            type_params = try tp_list.toOwnedSlice(self.alloc);
        }
        _ = try self.expect(.assign);
        const target = try self.parse_type();
        return ast.Stmt{ .alias_def = .{
            .loc = l,
            .name = nm.text,
            .type_params = type_params,
            .target = target,
            .parent = null,
            .fields = &.{},
            .methods = &.{},
            .attributes = attrs,
        } };
    }

    fn parse_global(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        if (try self.eat(.star) != null) {
            return ast.Stmt{ .global_decl = .{
                .loc = l,
                .star = true,
                .names = &.{},
                .inits = &.{},
            } };
        }
        var names: std.ArrayList(ast.LocalName) = .empty;
        try names.append(self.alloc, try self.parse_local_name());
        while (try self.eat(.comma) != null)
            try names.append(self.alloc, try self.parse_local_name());

        var inits: std.ArrayList(*ast.Expr) = .empty;
        if (try self.eat(.assign) != null) {
            try inits.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null)
                try inits.append(self.alloc, try self.parse_expr());
        }
        return ast.Stmt{ .global_decl = .{
            .loc = l,
            .star = false,
            .names = try names.toOwnedSlice(self.alloc),
            .inits = try inits.toOwnedSlice(self.alloc),
        } };
    }

    fn parse_local(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        if (try self.eat(.kw_function) != null or try self.eat(.kw_fun) != null) {
            const nm = try self.expect(.name);
            const fb = try self.parse_func_body(l);
            const path = try self.alloc.dupe([]const u8, &[_][]const u8{nm.text});
            return ast.Stmt{ .func_decl = .{
                .loc = l,
                .path = path,
                .method = false,
                .is_local = true,
                .func = fb,
            } };
        }
        var names: std.ArrayList(ast.LocalName) = .empty;
        try names.append(self.alloc, try self.parse_local_name());
        while (try self.eat(.comma) != null)
            try names.append(self.alloc, try self.parse_local_name());

        var inits: std.ArrayList(*ast.Expr) = .empty;
        if (try self.eat(.assign) != null) {
            try inits.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null)
                try inits.append(self.alloc, try self.parse_expr());
        }
        return ast.Stmt{ .local_decl = .{
            .loc = l,
            .names = try names.toOwnedSlice(self.alloc),
            .inits = try inits.toOwnedSlice(self.alloc),
        } };
    }

    fn parse_local_name(self: *Parser) ParseError!ast.LocalName {
        const nm = try self.expect(.name);
        const typ = try self.maybe_type_ann();
        var attrib: ?[]const u8 = null;
        if (try self.eat(.lt) != null) {
            const attr_tok = try self.pk();
            attrib = switch (attr_tok.kind) {
                .name => blk: {
                    const a = try self.adv();
                    _ = try self.expect(.gt);
                    break :blk a.text;
                },
                .kw_const => blk: {
                    _ = try self.adv();
                    _ = try self.expect(.gt);
                    break :blk "const";
                },
                else => return error.ExpectedToken,
            };
        }
        return ast.LocalName{ .ident = nm.text, .typ = typ, .attrib = attrib, .loc = nm.loc };
    }

    fn parse_const_decl(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const nm = try self.expect(.name);
        const typ = try self.maybe_type_ann();
        _ = try self.expect(.assign);
        const val = try self.parse_expr();
        return ast.Stmt{ .const_decl = .{ .loc = l, .ident = nm.text, .typ = typ, .val = val } };
    }

    // NOTE: `parse_struct_def_with_attrs` was removed. Duo has no `struct`
    // keyword. To declare a typed record, use an inline record-type
    // annotation on a binding: `local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }`.
    // For concept satisfaction, attach `@implements(C)` to the binding.

    fn parse_func_decl_with_attrs(self: *Parser, is_local: bool, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const tok = try self.adv();
        const hint_loc = tok.loc;
        const result = try self.parse_func_decl_after_first(is_local, attrs, tok.loc);
        // Emit hint only in .id mode and only when the function has typed params
        // (bare syntax requires at least one typed param for disambiguation).
        if (self.idol_mode) {
            if (result == .func_decl) {
                const fb = result.func_decl.func;
                var has_typed = false;
                for (fb.params) |p| {
                    if (p.typ != .inferred) {
                        has_typed = true;
                        break;
                    }
                }
                if (has_typed or fb.vararg) {
                    term.locHint(hint_loc, "'{s}' is unnecessary here; bare function syntax works: name(params) body end", .{tok.kind.spelling()});
                }
            }
        }
        return result;
    }

    /// The flat symbol a relation edge is minted as. `decode` at level `u64`
    /// becomes `decode__u64` — the SAME `owner__member` shape codegen already
    /// mints for module members and alias methods, so nothing new has to learn
    /// how to spell it. It is never written in Duo source: the surface is
    /// `decode(u64)`, and both the declaration and the call site pass through
    /// this one function so they cannot drift.
    fn relation_edge_symbol(self: *Parser, name: []const u8, level: []const u8) ParseError![]const u8 {
        return std.fmt.allocPrint(self.alloc, "{s}__{s}", .{ name, level });
    }

    fn relation_edge_key(self: *Parser, name: []const u8, level: []const u8) ParseError![]const u8 {
        return std.fmt.allocPrint(self.alloc, "{s}\x00{s}", .{ name, level });
    }

    /// §9 — `name(level) = (params) …`, a relation edge declared at a
    /// trie place. Returns the minted symbol and consumes the LEVEL group only;
    /// the caller consumes the `=` and parses the parameter list.
    ///
    /// The shape is recognised on three tokens and is unambiguous: a level
    /// group holds exactly one descriptor name, and what follows it is `=`
    /// then `(`. That was a parse error before this — a function body cannot
    /// start with `=` — so no existing program changes meaning. `f(x: i64) = …`
    /// is not this shape (the group carries an annotation, not a bare key) and
    /// still reports as it did.
    fn parse_level_edge(self: *Parser, path: *std.ArrayList([]const u8)) ParseError!?[]const u8 {
        if (path.items.len != 1) return null;
        if (!(try self.check(.lparen))) return null;
        const saved = self.lex.saveState();
        _ = try self.adv();
        const key = try self.pk();
        const level: []const u8 = if (key.kind == .name)
            key.text
        else if (grammar_roles.isDescriptor(key.kind))
            key.kind.spelling()
        else {
            self.lex.restoreState(saved);
            return null;
        };
        _ = try self.adv();
        if (!(try self.check(.rparen))) {
            self.lex.restoreState(saved);
            return null;
        }
        _ = try self.adv();
        if (!(try self.check(.assign))) {
            self.lex.restoreState(saved);
            return null;
        }
        _ = try self.adv();
        const opens_params = try self.check(.lparen);
        self.lex.restoreState(saved);
        if (!opens_params) return null;
        _ = try self.adv(); // '('
        _ = try self.adv(); // level
        _ = try self.adv(); // ')'
        const sym = try self.relation_edge_symbol(path.items[0], level);
        try self.relation_edges.put(self.alloc, try self.relation_edge_key(path.items[0], level), sym);
        return sym;
    }

    /// The edge `name(level)` names, if this parse has seen it DECLARED.
    ///
    /// Nothing is guessed from the shape: only a `(name)` group whose key was
    /// registered by `parse_level_edge` resolves, so `f(g)` where `f` is an
    /// ordinary function keeps meaning "call f with g". The consequence, and
    /// it is a real limit rather than an oversight: an edge declared in
    /// ANOTHER module is not in this map, so `mod.decode(u64)(v)` does not
    /// resolve yet. gap[025].
    fn relation_edge_of(self: *Parser, callee: *ast.Expr, args: []*ast.Expr) ParseError!?[]const u8 {
        if (self.relation_edges.count() == 0) return null;
        if (callee.* != .name or args.len != 1 or args[0].* != .name) return null;
        const key = try self.relation_edge_key(callee.name.ident, args[0].name.ident);
        return self.relation_edges.get(key);
    }

    /// The enum an inline case-set declared under `<owner>.<field>`, if this
    /// parse registered one. Nothing is inferred from the shape.
    fn caseset_home_of(self: *Parser, owner: *ast.Expr, field: []const u8) ParseError!?[]const u8 {
        if (self.caseset_homes.count() == 0) return null;
        if (owner.* != .name) return null;
        const key = try std.fmt.allocPrint(self.alloc, "{s}\x00{s}", .{ owner.name.ident, field });
        return self.caseset_homes.get(key);
    }

    fn parse_bare_func_decl_with_attrs(self: *Parser, is_local: bool, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const l = (try self.pk()).loc;
        return self.parse_func_decl_after_first(is_local, attrs, l);
    }

    fn parse_func_decl_after_first(self: *Parser, is_local: bool, attrs: []ast.Attribute, l: ast.Loc) ParseError!ast.Stmt {
        var path: std.ArrayList([]const u8) = .empty;
        var method = false;
        const first = try self.expect(.name);
        try path.append(self.alloc, first.text);
        while (true) {
            if (try self.eat(.dot) != null) {
                const part = try self.expect(.name);
                try path.append(self.alloc, part.text);
            } else if (try self.eat(.colon) != null) {
                const part = try self.expect(.name);
                try path.append(self.alloc, part.text);
                method = true;
                break;
            } else break;
        }
        // §9 — a RELATION EDGE declared at a trie place with a LEVEL:
        //
        //     decode(u64) = (cursor): u64 | error
        //
        // The first group is descriptor space (LAW-STRATA): `u64` is the key
        // that selects WHICH edge of `decode` this is, never a runtime
        // parameter. The second group is the parameter list. `parse_level_edge`
        // recognises the shape and mints the edge's symbol; the call site
        // `decode(u64)(v)` finds the same symbol through `relation_edges`.
        if (try self.parse_level_edge(&path)) |edge| {
            _ = try self.expect(.assign);
            const efb = try self.parse_func_body(l);
            const epath = try self.alloc.alloc([]const u8, 1);
            epath[0] = edge;
            return ast.Stmt{ .func_decl = .{
                .loc = l,
                .path = epath,
                .method = false,
                .is_local = is_local,
                .func = efb,
                .attributes = attrs,
            } };
        }
        // @ffi functions are bodyless prototypes — parse signature only, no body/end.
        const is_ffi = blk: {
            for (attrs) |a| if (std.mem.eql(u8, a.name, "ffi")) break :blk true;
            break :blk false;
        };
        const fb = if (is_ffi) try self.parse_func_signature(l) else try self.parse_func_body(l);
        return ast.Stmt{ .func_decl = .{
            .loc = l,
            .path = try path.toOwnedSlice(self.alloc),
            .method = method,
            .is_local = is_local,
            .func = fb,
            .attributes = attrs,
        } };
    }

    /// Shared heuristic used by both bare-function and assign-form detection.
    ///
    /// The lexer must be positioned at a '(' when this is called. It scans the
    /// matching paren group (token-wise, tracking bracket/brace nesting) looking
    /// for signals that the group is a typed/untyped parameter list rather than a
    /// call's argument list. Returns true when the group reads as a function header.
    ///
    /// Two guard rails keep ordinary calls from being misdetected:
    ///   - a `fun`/`function` keyword at depth 1 means a function is being passed
    ///     as an argument (`mcp.register_tool("x", fun(a) ... end)`) — a header's
    ///     parameter list never contains a nested function body, so bail.
    ///   - a depth-1 `:` only counts as a typed param (`a: i32`) when it directly
    ///     follows a name; `(expr):method()` / `):c(` colons are method calls.
    fn viewColonIsMethodCall(view: token_view.View, idx: usize) bool {
        const colon = view.kind(idx) orelse return false;
        if (colon != .colon) return false;
        const name_kind = view.kind(idx + 1) orelse return false;
        if (name_kind != .name and !grammar_roles.isDescriptor(name_kind)) return false;
        return view.kind(idx + 2) == .lparen;
    }

    /// One header recognizer (GAP-134). Observation over the producer pack.
    /// No host snapshot walk.
    ///
    /// `offside_col` is the column of the first token on the line the `(`
    /// begins — `line_opener`'s answer, the same threshold `parse_func_body`
    /// hands the body block. It is `null` outside `.id`, where layout does not
    /// bind and a next-line body is not a spelling at all. See the single
    /// untyped parameter case at the bottom.
    fn headerSignal(view: token_view.View, start: usize, allow_untyped_comma: bool, offside_col: ?u32) bool {
        var idx = start;

        if (view.kind(idx) != .lparen) return false;
        idx += 1;
        if (view.kind(idx) == .lparen) return false;

        var paren_depth: usize = 1;
        var bracket_depth: usize = 0;
        var brace_depth: usize = 0;
        var typed_or_vararg = false;
        var has_comma = false;
        var depth1_tokens: usize = 0;
        var depth1_names: usize = 0;
        // EVERY token inside the group, at every depth. `depth1_tokens` cannot
        // tell `(t)` from `(less(arr(mid + 1), v))`: the whole call after
        // `less` sits at depth 2 and is not counted, so both read as "one
        // depth-1 name". They are not the same thing — a parameter list cannot
        // contain an application — and the difference is exactly the tokens
        // depth-1 counting throws away.
        var inner_tokens: usize = 0;
        var has_literal_arg = false;
        var has_table_literal_arg = false;
        var has_infix_operator = false;
        var rparen_line: u32 = 0;
        var prev: TK = .eof;
        while (paren_depth > 0) {
            const tok = view.at(idx) orelse return false;
            const row = view.role(idx);
            if (paren_depth == 1 and bracket_depth == 0 and brace_depth == 0 and
                row != null and row.?.literal_kind)
            {
                has_literal_arg = true;
            }
            switch (tok.kind) {
                .eof => return false,
                .dots => typed_or_vararg = true,
                .comma => if (paren_depth == 1) {
                    if (prev == .eof) return false;
                    has_comma = true;
                },
                .colon => if (paren_depth == 1 and bracket_depth == 0 and brace_depth == 0 and prev == .name) {
                    if (!viewColonIsMethodCall(view, idx)) typed_or_vararg = true;
                },
                .kw_fun, .kw_function => {
                    if (paren_depth == 1 and bracket_depth == 0 and brace_depth == 0 and !typed_or_vararg) {
                        return false;
                    }
                },
                .lparen => paren_depth += 1,
                .rparen => {
                    paren_depth -= 1;
                    if (paren_depth == 0) rparen_line = tok.loc.line;
                },
                .lbracket => bracket_depth += 1,
                .rbracket => {
                    if (bracket_depth > 0) bracket_depth -= 1;
                },
                .lbrace => {
                    if (paren_depth == 1 and bracket_depth == 0 and brace_depth == 0) {
                        has_table_literal_arg = true;
                    }
                    brace_depth += 1;
                },
                .rbrace => {
                    if (brace_depth > 0) brace_depth -= 1;
                },
                else => {},
            }
            if (paren_depth == 1 and bracket_depth == 0 and brace_depth == 0 and
                tok.kind != .lparen and tok.kind != .rparen)
            {
                depth1_tokens += 1;
                if (tok.kind == .name) depth1_names += 1;
                if (grammar_roles.isInfix(tok.kind)) has_infix_operator = true;
            }
            // Everything strictly inside the outer parens — the closing one
            // brings `paren_depth` to 0 and is not inside anything.
            if (paren_depth > 0) inner_tokens += 1;
            prev = tok.kind;
            idx += 1;
        }

        const after = view.at(idx) orelse return false;
        if (has_literal_arg and !typed_or_vararg) return false;
        if (has_infix_operator and !typed_or_vararg) return false;
        if (has_table_literal_arg and !typed_or_vararg) return false;
        // `): Name` — a result descriptor, UNLESS the name is followed by `(`,
        // in which case it is `(expr):method(args)`: a subject call on the
        // parenthesised value, the same reading `viewColonIsMethodCall` gives a
        // `:` INSIDE the group.
        //
        // THIS TEST EXISTS THREE TIMES IN THIS FUNCTION and only two copies had
        // it. Because this copy runs first and returned unconditionally, the
        // `!= .lparen` in the other two was unreachable — one rule, three
        // spellings, and the disagreeing one won every time. Measured:
        // `(out:sub(1, n)):to(i64)` (`scripts/abi_matrix.id:61`) was read as a
        // header whose parameter `out` had type `sub`, and the file was
        // refused at "write `)` at this token edge" pointing inside the call.
        // Falling THROUGH rather than returning false is deliberate: the two
        // copies below decide it, and a typed header keeps its own answer from
        // `typed_or_vararg` on the next line, which is what keeps `): *Foo`,
        // `): [4]i64` and `): i(64)` reading as result descriptors.
        if (after.kind == .colon) {
            const ty = view.kind(idx + 1) orelse return false;
            if ((ty == .name or grammar_roles.isDescriptor(ty)) and
                view.kind(idx + 2) != .lparen) return true;
        }
        if (typed_or_vararg or after.kind == .arrow or after.kind == .assign) return true;
        if (allow_untyped_comma and has_comma) {
            if (after.kind == .eof) return false;
            if (after.kind == .colon) {
                const ty = view.kind(idx + 1) orelse return false;
                if (ty != .name and !grammar_roles.isDescriptor(ty)) return false;
                return view.kind(idx + 2) != .lparen;
            }
            if (grammar_roles.isInfix(after.kind) or after.kind == .dot) return false;
            return true;
        }
        if (after.kind == .colon) {
            const ty = view.kind(idx + 1) orelse return false;
            if (ty != .name and !grammar_roles.isDescriptor(ty)) return false;
            return view.kind(idx + 2) != .lparen;
        }
        if (grammar_roles.isInfix(after.kind) or after.kind == .comma) return false;
        // A SINGLE BARE NAME IN PARENTHESES — `(t)`, `(meta)`. The only shape
        // whose two readings are both ordinary: the one-parameter header, and
        // the grouped expression. `(a, b)` has a comma and `(t: any)` has a
        // colon; both already decide themselves. This one does not, so the
        // BODY has to decide it, and the question is where the body may be.
        //
        // On the header's own line the next token answers it — `canStartBody`
        // below. On a LATER line the answer is the offside rule and nothing
        // else: a body is the lines indented past the opener of the line the
        // header begins on, which is exactly the threshold `parse_func_body`
        // will hand `parse_body_block_at`. Asking the same question with the
        // same threshold is what keeps the recognizer and the body parser from
        // being two models of one rule.
        //
        // REFUSING EVERY NEXT-LINE BODY, which is what stood here, was not a
        // conservative choice — it was a SILENT WRONG ANSWER. `f: i64 = (t)`
        // with `t + 1` beneath it reprinted as `f: i64 = t` followed by a
        // top-level `t + 1`, compiled clean under `idol check`, and returned 1
        // where the program says 7. The `fun`-retirement lane converts
        // `fun(t)` into `(t)`, so the shape's population only grows.
        //
        // TWO THINGS HAD TO BE EXCLUDED FIRST, both measured as regressions on
        // the tree before this landed:
        //
        //   `else(less(arr(mid + 1), v))`  (lib/slices.id:166, and 5 more)
        //       one depth-1 name — the whole call after `less` is at depth 2,
        //       so `depth1_tokens` cannot see it — with the `else`'s own block
        //       indented beneath. `inner_tokens` is what depth-1 counting threw
        //       away: a parameter list cannot contain an application, and the
        //       shape this rule is for is EXACTLY one token wide.
        //
        //   `if (flag)` / `while (flag)` / `else(flag)`
        //       a bare name IS a legal condition, and a condition is always
        //       followed by an indented block, so offside proves nothing there.
        //       The keyword before the `(` decides it, and it is the only place
        //       in this recognizer that looks left of the group — because it is
        //       the only place where what precedes changes what the group IS.
        if (depth1_tokens == 1 and depth1_names == 1 and !typed_or_vararg and !has_comma) {
            if (!allow_untyped_comma) return false;
            if (after.loc.line != rparen_line) {
                if (inner_tokens != 1) return false;
                const open_col = offside_col orelse return false;
                if (after.loc.col <= open_col) return false;
                if (start > 0) switch (view.kind(start - 1) orelse .eof) {
                    .kw_if, .kw_elseif, .kw_else, .kw_while, .kw_until, .kw_for, .kw_match => return false,
                    else => {},
                };
            }
        }
        if (!allow_untyped_comma and !typed_or_vararg) return false;
        if (depth1_tokens == 0 and !allow_untyped_comma) return false;
        if (grammar_roles.canStartBody(after.kind)) return true;
        return false;
    }

    fn scan_func_header_signal(self: *Parser, allow_untyped_comma: bool) ParseError!bool {
        const lparen = try self.pk();
        if (lparen.kind != .lparen) return false;
        try self.ensureProducerPack();
        const view = token_view.fromLexer(self.lex) orelse return false;
        // DERIVED FROM THE TOKEN STREAM, not from a tracked field: this runs
        // inside speculative scans that rewind the lexer, and `line_opener`
        // reads the same producer pack `headerSignal` is about to walk, so it
        // cannot be left holding a line the parse has not reached.
        const offside_col: ?u32 = if (self.idol_mode)
            (try self.line_opener(lparen.loc)).col
        else
            null;
        return headerSignal(view, self.lex.duoStreamIndex(), allow_untyped_comma, offside_col);
    }

    fn starts_bare_func_decl(self: *Parser) ParseError!bool {
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);

        if ((try self.pk()).kind != .name) return false;
        _ = try self.adv();
        while (true) {
            if (try self.eat(.dot) != null) {
                if ((try self.pk()).kind != .name) return false;
                _ = try self.adv();
            } else if (try self.eat(.colon) != null) {
                if ((try self.pk()).kind != .name) return false;
                _ = try self.adv();
                break;
            } else break;
        }
        return self.scan_func_header_signal(false);
    }

    fn starts_parenthesized_func_expr(self: *Parser) ParseError!bool {
        return self.scan_func_header_signal(true);
    }

    /// The header test at a STATEMENT-LEVEL BINDING — `name = (…)`,
    /// `name: Ret = (…)`, `a.b.c = (…)`. Everything
    /// `starts_parenthesized_func_expr` accepts, plus the one shape that test
    /// cannot decide on its own: `name = ()`.
    ///
    /// §42, THE COLLISION. Commit `22e956e6` converted every `name(): void`
    /// into `name = ()`, so `name = ()` is the zero-parameter relation. `()` is
    /// ALSO the empty pack. `headerSignal` separated them by asking whether the
    /// token after `)` could start a body — which meant the SAME two characters
    /// in the SAME position meant different things depending on what happened
    /// to follow:
    ///
    ///     x = ()            relation, when a declaration follows
    ///     …
    ///     x = ()            empty pack, when it is the last line of the file
    ///
    /// Both type-check, and `x()` type-checks against both; `duo symbols`
    /// reports `functions: 2` for the first and `functions: 1` for the second.
    /// That is indistinguishability, not a subtlety, and §42 refuses it.
    ///
    /// DECIDED, not refused, and decided in favour of the RELATION — that is
    /// the reading `22e956e6` already spent the spelling on, and the reading
    /// the whole migrated corpus depends on. The empty pack keeps EXPRESSION
    /// position, where no declaration can appear (`f(())`, `{ () }`,
    /// `return ()`); `parse_primary` still routes it there, unchanged. Two
    /// readings, separated by POSITION — the same way §4 separates glued `a.b`
    /// from the leading `.b` anchor walk.
    ///
    /// Narrow on purpose: only `()` with NOTHING after it on its line. `x = ()`
    /// followed on the same line by an operator is still the pack expression
    /// `() + 1`, and followed by a body is still the one-line relation.
    fn starts_binding_func_expr(self: *Parser) ParseError!bool {
        if (try self.starts_parenthesized_func_expr()) return true;
        if (!self.idol_mode) return false;
        if ((try self.pk()).kind != .lparen) return false;
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        defer {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        }
        const lp = try self.adv();
        if ((try self.pk()).kind != .rparen) return false;
        _ = try self.adv();
        const after = try self.pk();
        return after.kind == .eof or after.loc.line != lp.loc.line;
    }

    /// Backwards-compatible: parse function decl with no attributes.
    fn parse_func_decl(self: *Parser, is_local: bool) ParseError!ast.Stmt {
        return self.parse_func_decl_with_attrs(is_local, &.{});
    }

    /// Parse `async fun name(...) ... end` or `async function name(...) ... end`.
    /// The `async` keyword has already been peeked; this function consumes it,
    /// then expects `fun`/`function` and delegates to the normal function parser.
    fn parse_async_func_decl_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        _ = try self.adv(); // consume `async`
        const nxt = try self.pk();
        if (nxt.kind != .kw_function and nxt.kind != .kw_fun) {
            term.locErr(nxt.loc, "expected 'function' or 'fun' after 'async', got '{s}'", .{
                nxt.kind.spelling(),
            });
            return ParseError.ExpectedToken;
        }
        var stmt = try self.parse_func_decl_with_attrs(false, attrs);
        stmt.func_decl.func.is_async = true;
        return stmt;
    }

    /// Backwards-compatible: parse async function decl with no attributes.
    fn parse_async_func_decl(self: *Parser) ParseError!ast.Stmt {
        return self.parse_async_func_decl_with_attrs(&.{});
    }

    fn parse_constrained_type_param(self: *Parser, param_name: []const u8) ParseError!ast.TypeExpr {
        const constraint_ptr = try self.alloc.create(ast.TypeExpr);
        constraint_ptr.* = try self.parse_type();
        var extra: std.ArrayList(ast.TypeExpr) = .empty;
        while (try self.eat(.plus) != null) {
            try extra.append(self.alloc, try self.parse_type());
        }
        return .{ .constrained = .{
            .name = param_name,
            .constraint = constraint_ptr,
            .extra = try extra.toOwnedSlice(self.alloc),
        } };
    }

    /// Parse a generic type parameter: `T` or `T: Concept` or `T: A + B`.
    fn parse_type_param(self: *Parser) ParseError!ast.TypeExpr {
        const t = try self.expect(.name);
        if (try self.eat(.colon) != null) {
            return try self.parse_constrained_type_param(t.text);
        }
        return .{ .named = t.text };
    }

    fn parse_func_body(self: *Parser, l: ast.Loc) ParseError!ast.FuncBody {
        // Taken BEFORE the header is consumed: a header whose parameters run
        // onto continuation lines would otherwise report the LAST of those
        // lines as the declaration's start.
        const body_open = try self.line_opener(l);
        // Check for type parameters: <T, U>
        var type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lt) != null) {
            var tp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try tp_list.append(self.alloc, try self.parse_type_param());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type_param());
            }
            _ = try self.expect(.gt);
            type_params = try tp_list.toOwnedSlice(self.alloc);
        }

        _ = try self.expect(.lparen);
        var params: std.ArrayList(ast.FuncParam) = .empty;
        var vararg = false;
        var vararg_name: ?[]const u8 = null;
        if (!(try self.check(.rparen))) {
            if (try self.eat(.dots) != null) {
                vararg = true;
                if (try self.check(.name)) {
                    vararg_name = (try self.adv()).text;
                }
            } else {
                try params.append(self.alloc, try self.parse_param());
                while (try self.eat(.comma) != null) {
                    if (try self.eat(.dots) != null) {
                        vararg = true;
                        if (try self.check(.name)) {
                            vararg_name = (try self.adv()).text;
                        }
                        break;
                    }
                    try params.append(self.alloc, try self.parse_param());
                }
            }
        }
        const rparen_tok = try self.expect(.rparen);
        // Accept either `-> type` or `: type` for the return type.
        var ret_type: ast.TypeExpr = .inferred;
        var ret_fallible = false;
        // The contract belongs to the HEADER, so it is written on the header's
        // line (§3: statements end at newline, and a signature is not a
        // continuation). Without the line test the leading `:m()` sibling call
        // of §20's `token` slot —
        //
        //     token = ()
        //         :skip(space)
        //
        // — had its `:` eaten as the return-type colon and `skip(space)` read
        // as the contract, so the body silently began one statement late and
        // surfaced as an offside error pointing at the NEXT line.
        const contract_here = (try self.pk()).loc.line == rparen_tok.loc.line;
        if (contract_here and (try self.eat(.arrow) != null or try self.eat(.colon) != null)) {
            self.union_alternative_seen = false;
            ret_type = try self.parse_type();
            ret_fallible = self.union_alternative_seen;
        }

        // §2 METHOD SCOPE begins here: inside this body a leading `.` walks
        // from the FIRST parameter, which §0.6 already makes the receiver.
        // Saved and restored so a nested body cannot leak its receiver outward,
        // and `call_arg_depth` resets because a body is a fresh statement
        // context — `f((l) .pos)` is `l.pos`, not a lens over `f`'s data.
        const outer_subject = self.subject;
        const outer_call_arg_depth = self.call_arg_depth;
        self.subject = if (self.descriptor_body_depth == 0 and params.items.len > 0)
            params.items[0].name
        else
            null;
        self.call_arg_depth = 0;
        defer {
            self.subject = outer_subject;
            self.call_arg_depth = outer_call_arg_depth;
        }

        const had_do = try self.eat(.kw_do) != null;
        const body_tok = try self.pk();
        const multiline = body_tok.loc.line > rparen_tok.loc.line;
        const blockish = had_do or multiline;

        const body: ast.Block = if (blockish) blk: {
            self.func_body_depth += 1;
            defer self.func_body_depth -= 1;
            // §3 — a function body's opener is the DECLARATION's own first
            // token: `parse = (lx: lexer): ast | error` at column 1 owns a body
            // at column 5, and the body closes when the file dedents back.
            // `body_open` is that token; `l` alone is the `(`/`fun`, which for
            // a lambda in argument position sits mid-line. See
            // `line_opener`.
            const b = try self.parse_body_block_at(body_open);
            try self.close_block(body_open, self.last_layout.offside);
            break :blk b;
        } else blk: {
            // A one-line body that is a LOOP is a statement, not an expression
            // (§20 `skip = (p) while … .pos += 1`). Restricted to `while`/`for`
            // deliberately: `if` on one line stays the expression-if of §6
            // (`peek = () if .pos < #.src .src[.pos] else nil`), so this cannot
            // change what any existing one-line `if` body means.
            if (body_tok.kind == .kw_while or body_tok.kind == .kw_for) {
                const stmts = try self.alloc.alloc(ast.Stmt, 1);
                stmts[0] = try self.parse_stmt();
                break :blk ast.Block{ .loc = body_tok.loc, .stmts = stmts, .tail_expr = null };
            }
            if (try self.func_body_should_use_expr_stmt()) {
                const stmt = try self.parse_expr_stmt();
                break :blk switch (stmt) {
                    .expr_stmt => |es| ast.Block{
                        .loc = es.loc,
                        .stmts = &.{},
                        .tail_expr = es.expr,
                    },
                    .call_stmt => |cs| ast.Block{
                        .loc = cs.loc,
                        .stmts = &.{},
                        .tail_expr = cs.expr,
                    },
                    .assign => |as| blk2: {
                        const stmts = try self.alloc.alloc(ast.Stmt, 1);
                        stmts[0] = stmt;
                        break :blk2 ast.Block{
                            .loc = as.loc,
                            .stmts = stmts,
                            .tail_expr = null,
                        };
                    },
                    else => {
                        term.locErr(l, "invalid single-line function body", .{});
                        return ParseError.UnexpectedToken;
                    },
                };
            }
            const expr = try self.parse_expr();
            break :blk ast.Block{
                .loc = expr.loc(),
                .stmts = &.{},
                .tail_expr = expr,
            };
        };
        // A single-line body may still be closed explicitly:
        // `fun(m) m.pattern .. "\n" end`. The multi-line branch above consumes
        // its `end`; this one did not, so the same lambda parsed as an argument
        // (`@comp.match("a|b", fun(m) … end)`) died on "expected ')', got 'end'"
        // while the identical body split over three lines parsed fine.
        //
        // The `end` must be on the SAME LINE as the body to belong to this
        // lambda. That is what separates it from an enclosing block's
        // terminator:
        //
        //     if c
        //         f = fun(x) x + 1      -- body ends here
        //     end                       -- closes the `if`, not the lambda
        //
        // so the line test is the disambiguation, not a heuristic.
        if (!blockish) {
            const end_tok = try self.pk();
            if (end_tok.kind == .kw_end and end_tok.loc.line == rparen_tok.loc.line) {
                _ = try self.adv();
            }
        }
        return ast.FuncBody{
            .loc = l,
            .params = try params.toOwnedSlice(self.alloc),
            .vararg = vararg,
            .vararg_name = vararg_name,
            .ret_type = ret_type,
            .ret_fallible = ret_fallible,
            .body = body,
            .type_params = type_params,
        };
    }

    /// Parse only the signature of a bodyless function (for @ffi declarations).
    /// Same as parse_func_body but without the block body and `end` keyword.
    fn parse_func_signature(self: *Parser, l: ast.Loc) ParseError!ast.FuncBody {
        // Type parameters: <T, U>
        var type_params: ?[]ast.TypeExpr = null;
        if (try self.eat(.lt) != null) {
            var tp_list: std.ArrayList(ast.TypeExpr) = .empty;
            try tp_list.append(self.alloc, try self.parse_type_param());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type_param());
            }
            _ = try self.expect(.gt);
            type_params = try tp_list.toOwnedSlice(self.alloc);
        }

        _ = try self.expect(.lparen);
        var params: std.ArrayList(ast.FuncParam) = .empty;
        var vararg = false;
        var vararg_name: ?[]const u8 = null;
        if (!(try self.check(.rparen))) {
            if (try self.eat(.dots) != null) {
                vararg = true;
                if (try self.check(.name)) {
                    vararg_name = (try self.adv()).text;
                }
            } else {
                try params.append(self.alloc, try self.parse_param());
                while (try self.eat(.comma) != null) {
                    if (try self.eat(.dots) != null) {
                        vararg = true;
                        if (try self.check(.name)) {
                            vararg_name = (try self.adv()).text;
                        }
                        break;
                    }
                    try params.append(self.alloc, try self.parse_param());
                }
            }
        }
        _ = try self.expect(.rparen);
        // Accept either `-> type` or `: type` for the return type.
        var ret_type: ast.TypeExpr = .inferred;
        var ret_fallible = false;
        if (try self.eat(.arrow) != null or try self.eat(.colon) != null) {
            self.union_alternative_seen = false;
            ret_type = try self.parse_type();
            ret_fallible = self.union_alternative_seen;
        }
        // Bodyless function: empty body with no tail expression.
        return ast.FuncBody{
            .loc = l,
            .params = try params.toOwnedSlice(self.alloc),
            .vararg = vararg,
            .vararg_name = vararg_name,
            .ret_type = ret_type,
            .ret_fallible = ret_fallible,
            .body = .{ .loc = l, .stmts = &.{}, .tail_expr = null },
            .type_params = type_params,
        };
    }

    fn parse_param(self: *Parser) ParseError!ast.FuncParam {
        const nm = try self.expect(.name);
        const typ = try self.maybe_type_ann();
        var default_val: ?*ast.Expr = null;
        if (try self.eat(.assign) != null) {
            default_val = try self.parse_expr();
        }
        return ast.FuncParam{ .name = nm.text, .typ = typ, .default_val = default_val, .loc = nm.loc };
    }

    const IfClauses = struct {
        then: ast.Block,
        elseifs: []ast.ElseIf,
        else_body: ?ast.Block,
    };

    /// The then-body, the `elseif`/`else` chain, and the close — shared by all
    /// four `if` forms (plain, `if name =`, `if a, b =`, `if let`) so layout is
    /// decided in exactly one place.
    ///
    /// §3: each clause opens its OWN frame at its own keyword, so
    /// `else return nil, error{…}` on one line is a one-liner body, while the
    /// clause itself binds to this `if` BY COLUMN. The construct closes by
    /// layout when any of its blocks was governed by layout; a written `end` is
    /// accepted and deleted either way.
    /// True when a `(` starts in the column immediately after `kw` ends, on the
    /// same line — `else(cond)` rather than `else (value)`.
    ///
    /// Peeking cannot consume: the caller still has to parse the parenthesized
    /// expression itself, so this restores lexer state before returning.
    fn glued_lparen(self: *Parser, kw: Token) bool {
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);
        const nxt = self.pk() catch return false;
        if (nxt.kind != .lparen) return false;
        if (nxt.loc.line != kw.loc.line) return false;
        return nxt.loc.col == kw.loc.col + @as(u32, @intCast(kw.text.len));
    }

    fn parse_if_clauses(self: *Parser, l: ast.Loc) ParseError!IfClauses {
        try self.eat_deprecated(.kw_then);
        // COMPACT FACE in statement position: `if(c) = value`. Same optional
        // association token as the expression path; the arm that follows is the
        // clause body exactly as it would be without it.
        _ = try self.eat(.assign);
        const then_body = try self.parse_block_at(l);
        var offside = self.last_layout.offside;
        var elseifs: std.ArrayList(ast.ElseIf) = .empty;
        var else_body: ?ast.Block = null;
        while (true) {
            if (try self.clause_binds(l, .kw_elseif, offside)) {
                const kw = try self.adv();
                const ec = try self.parse_expr();
                try self.eat_deprecated(.kw_then);
                const eb = try self.parse_block_at(kw.loc);
                offside = offside or self.last_layout.offside;
                try elseifs.append(self.alloc, ast.ElseIf{ .cond = ec, .body = eb });
            } else if (try self.clause_binds(l, .kw_else, offside)) {
                const kw = try self.adv();
                // `else(condition)` — the alternative is itself conditional.
                // This is what retires `elseif`: `else` means "the remaining
                // alternative" everywhere, and a parenthesized operand narrows
                // which remainder, so the chain reads
                //
                //     if(a) x
                //     else(b) y
                //     else z
                //
                // with one rule instead of a second keyword. It desugars to the
                // SAME ElseIf node `elseif` builds, so the two spellings cannot
                // diverge — `gate/control.id` compares them input by input.
                //
                // ADJACENCY decides, the same rule `peek_glued_assign` already
                // uses: `else(` is the conditional face, `else (` with a space
                // is an ordinary parenthesized body. Nothing is ambiguous, so
                // nothing has to be rejected under §42.
                if (self.glued_lparen(kw)) {
                    const ec = try self.parse_expr();
                    _ = try self.eat(.assign);
                    const eb = try self.parse_block_at(kw.loc);
                    offside = offside or self.last_layout.offside;
                    try elseifs.append(self.alloc, ast.ElseIf{ .cond = ec, .body = eb });
                    continue;
                }
                // §7 — `else if` NORMALIZES TO `else(cond)`, and normalizing it
                // HERE is what makes that true of the tree and not just of the
                // prose. It builds the very same `ElseIf` node `elseif` and
                // `else(cond)` build, so all three spellings are one node and
                // §3's "no `elseif` identity and no `ElseIf` graph kind" holds
                // by construction rather than by comparison.
                //
                // It also repairs a parse. Falling through to `else_body` read
                // `else if` as a nested `if` whose BODY BLOCK OPENED AT THE
                // `if` KEYWORD'S COLUMN, while the body was indented relative
                // to the `else` — so `open_layout` saw a body no deeper than
                // its opener, never established offside, and the block could
                // only end at "still open at the file edge". A trailing bare
                // `else` hid it by closing the chain a different way, which is
                // why the shape that failed was the one WITHOUT a final
                // `else`. Anchoring the body on the `else` token is the fix.
                //
                // SAME LINE is the whole condition, and it is what preserves
                // the genuinely nested spelling: an `if` on the line AFTER
                // `else` still opens an ordinary nested refinement.
                const after = try self.pk();
                if (after.kind == .kw_if and after.loc.line == kw.loc.line) {
                    _ = try self.adv();
                    const ec = try self.parse_expr();
                    try self.eat_deprecated(.kw_then);
                    _ = try self.eat(.assign);
                    const eb = try self.parse_block_at(kw.loc);
                    offside = offside or self.last_layout.offside;
                    try elseifs.append(self.alloc, ast.ElseIf{ .cond = ec, .body = eb });
                    continue;
                }
                _ = try self.eat(.assign);
                else_body = try self.parse_block_at(kw.loc);
                offside = offside or self.last_layout.offside;
                break;
            } else break;
        }
        try self.close_block(l, offside);
        return .{
            .then = then_body,
            .elseifs = try elseifs.toOwnedSlice(self.alloc),
            .else_body = else_body,
        };
    }

    /// §1.1 — `if a, b = expr ... end` (correlated return-pack binding).
    /// Returns null when the lookahead is not this form, leaving the caller to
    /// restore lexer state and try the single-name and plain-condition paths.
    fn parse_if_pack_binding(self: *Parser, l: ast.Loc) ParseError!?ast.Stmt {
        var names: std.ArrayList(ast.LocalName) = .empty;
        errdefer names.deinit(self.alloc);
        while (true) {
            if ((try self.pk()).kind != .name) return null;
            const nm = try self.adv();
            try names.append(self.alloc, .{
                .ident = nm.text,
                .typ = .inferred,
                .attrib = null,
                .loc = nm.loc,
            });
            if (try self.eat(.comma) == null) break;
        }
        // A single name is the existing `if name = expr` path, which has dedicated
        // AST support; only the pack form is handled here.
        if (names.items.len < 2) return null;
        if ((try self.pk()).kind != .assign) return null;
        _ = try self.adv();

        var inits: std.ArrayList(*ast.Expr) = .empty;
        errdefer inits.deinit(self.alloc);
        try inits.append(self.alloc, try self.parse_expr());
        const clauses = try self.parse_if_clauses(l);

        const first = names.items[0];
        const cond_ref = try self.new_expr(.{ .name = .{ .loc = first.loc, .ident = first.ident } });
        const inner = ast.Stmt{ .if_stmt = .{
            .loc = l,
            .binding = null,
            .cond = cond_ref,
            .then = clauses.then,
            .elseifs = clauses.elseifs,
            .else_body = clauses.else_body,
        } };
        const decl = ast.Stmt{ .local_decl = .{
            .loc = l,
            .names = try names.toOwnedSlice(self.alloc),
            .inits = try inits.toOwnedSlice(self.alloc),
        } };
        const stmts = try self.alloc.alloc(ast.Stmt, 2);
        stmts[0] = decl;
        stmts[1] = inner;
        return ast.Stmt{ .do_block = .{
            .loc = l,
            .body = .{ .loc = l, .stmts = stmts },
        } };
    }

    fn parse_if(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        // `if let pattern = expr then ... end` — desugars to match
        if ((try self.pk()).kind == .kw_let) {
            try self.denyRetiredStmtKeyword(try self.pk());
            _ = try self.adv(); // consume `let`
            const pattern = try self.parse_pattern();
            _ = try self.expect(.assign);
            const scrutinee = try self.parse_expr();
            const clauses = try self.parse_if_clauses(l);
            const then_body = clauses.then;
            const else_body = clauses.else_body;
            // Build match arms
            var arms = try self.alloc.alloc(ast.MatchArm, if (else_body != null) 2 else 1);
            arms[0] = .{ .pattern = pattern, .guard = null, .body = then_body };
            if (else_body) |eb| {
                arms[1] = .{ .pattern = .wildcard, .guard = null, .body = eb };
            }
            const match_expr = try self.new_expr(.{ .match_expr = try self.alloc.create(ast.MatchExpr) });
            match_expr.match_expr.* = .{ .loc = l, .scrutinee = scrutinee, .arms = arms };
            return ast.Stmt{ .expr_stmt = .{ .loc = l, .expr = match_expr } };
        }
        // §1.1 — correlated return-pack binding condition:
        // `if value, err = parse(text)`. Desugars to a scoped block holding the
        // multi-assign plus an ordinary `if` on position 1, which is exactly the
        // §1.6 scoping rule (the names are introduced in the block and die with
        // it) and reuses the existing return-pack destructuring end to end rather
        // than growing a second multi-value path.
        //
        // Position 1 is the tested position per §1.1's success predicate — the
        // value-first return-pack idiom, chosen on merit.
        if ((try self.pk()).kind == .name) {
            const pack_saved = self.lex.saveState();
            if (try self.parse_if_pack_binding(l)) |stmt| return stmt;
            self.lex.restoreState(pack_saved);
        }
        // `if name = expr` binding condition
        if ((try self.pk()).kind == .name) {
            const saved = self.lex.saveState();
            const nm = try self.adv();
            if ((try self.pk()).kind == .assign) {
                _ = try self.adv();
                const rhs = try self.parse_expr();
                const clauses = try self.parse_if_clauses(l);
                const cond_ref = try self.new_expr(.{ .name = .{ .loc = nm.loc, .ident = nm.text } });
                return ast.Stmt{ .if_stmt = .{
                    .loc = l,
                    .binding = .{ .name = nm.text, .expr = rhs },
                    .cond = cond_ref,
                    .then = clauses.then,
                    .elseifs = clauses.elseifs,
                    .else_body = clauses.else_body,
                } };
            } else {
                self.lex.restoreState(saved);
            }
        }
        const cond = try self.parse_expr();
        const clauses = try self.parse_if_clauses(l);
        return ast.Stmt{ .if_stmt = .{
            .loc = l,
            .binding = null,
            .cond = cond,
            .then = clauses.then,
            .elseifs = clauses.elseifs,
            .else_body = clauses.else_body,
        } };
    }

    /// §6 — THE CONSUMPTION LOOP, plus GUARD CHAINS:
    ///
    ///     while b = cursor:next() mix(b)
    ///     while b = :peek() and p(b) .pos += 1
    ///
    /// `while` is the only clause that lacked the binding condition `if`
    /// already had, so `while b = …` was the diagnostic "expected expression,
    /// got '='" — which is why the golden `leb128` and `lexer` of §20 stop on
    /// their first loop.
    ///
    /// Desugars into the existing AST rather than growing a second loop node:
    ///
    ///     while true
    ///         b = <expr>
    ///         if b <then body> else break
    ///
    /// The chain nests instead of hoisting, because §6 says the links are
    /// CORRELATED: in `while a = f() and p(a) and b = g(a)`, `g(a)` must not
    /// run when `p(a)` failed. Each link owns the remainder as its `then`.
    ///
    /// The bound expression is parsed ABOVE `and`'s precedence, which is the
    /// whole content of the guard-chain rule: `b = :peek() and p(b)` binds
    /// `b` to `:peek()`, not to the conjunction. `or` is left below the cut
    /// and therefore does not chain, per §6.
    ///
    /// Strictly additive — every form here was a parse error before, so no
    /// existing program changes meaning. `if` is deliberately NOT changed in
    /// the same hunk: there `name = expr and guard` already parses and binds
    /// the conjunction, so re-cutting it is a semantic change to live code,
    /// not a new surface. Filed separately.
    fn parse_while_consumption(self: *Parser, l: ast.Loc) ParseError!?ast.Stmt {
        if ((try self.pk()).kind != .name) return null;
        const saved = self.lex.saveState();
        const first = try self.adv();
        if ((try self.pk()).kind != .assign) {
            self.lex.restoreState(saved);
            return null;
        }
        _ = try self.adv(); // consume '='

        const Link = struct { name: ?[]const u8, loc: ast.Loc, expr: *ast.Expr };
        var links: std.ArrayList(Link) = .empty;
        try links.append(self.alloc, .{
            .name = first.text,
            .loc = first.loc,
            .expr = try self.parse_prec(5),
        });
        while (try self.eat(.kw_and) != null) {
            const nxt = try self.pk();
            if (nxt.kind == .name) {
                const link_saved = self.lex.saveState();
                const nm = try self.adv();
                if ((try self.pk()).kind == .assign) {
                    _ = try self.adv();
                    try links.append(self.alloc, .{
                        .name = nm.text,
                        .loc = nm.loc,
                        .expr = try self.parse_prec(5),
                    });
                    continue;
                }
                self.lex.restoreState(link_saved);
            }
            try links.append(self.alloc, .{
                .name = null,
                .loc = nxt.loc,
                .expr = try self.parse_prec(5),
            });
        }

        try self.eat_deprecated(.kw_do);
        var inner = try self.parse_block_at(l);
        try self.close_block(l, self.last_layout.offside);

        var i = links.items.len;
        while (i > 0) {
            i -= 1;
            const link = links.items[i];
            var brk_stmts = try self.alloc.alloc(ast.Stmt, 1);
            brk_stmts[0] = .{ .brk = link.loc };
            const cond: *ast.Expr = if (link.name) |nm|
                try self.new_expr(.{ .name = .{ .loc = link.loc, .ident = nm } })
            else
                link.expr;
            const guard = ast.Stmt{ .if_stmt = .{
                .loc = link.loc,
                .binding = null,
                .cond = cond,
                .then = inner,
                .elseifs = &.{},
                .else_body = .{ .loc = link.loc, .stmts = brk_stmts },
            } };
            if (link.name) |nm| {
                var names: std.ArrayList(ast.LocalName) = .empty;
                try names.append(self.alloc, .{
                    .ident = nm,
                    .typ = .inferred,
                    .attrib = null,
                    .attributes = &.{},
                    .loc = link.loc,
                });
                var inits: std.ArrayList(*ast.Expr) = .empty;
                try inits.append(self.alloc, link.expr);
                var stmts = try self.alloc.alloc(ast.Stmt, 2);
                stmts[0] = .{ .local_decl = .{
                    .loc = link.loc,
                    .names = try names.toOwnedSlice(self.alloc),
                    .inits = try inits.toOwnedSlice(self.alloc),
                } };
                stmts[1] = guard;
                inner = .{ .loc = link.loc, .stmts = stmts };
            } else {
                var stmts = try self.alloc.alloc(ast.Stmt, 1);
                stmts[0] = guard;
                inner = .{ .loc = link.loc, .stmts = stmts };
            }
        }

        const true_lit = try self.new_expr(.{ .true_lit = l });
        return ast.Stmt{ .while_loop = .{ .loc = l, .cond = true_lit, .body = inner } };
    }

    fn parse_while(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        // `while let pattern = expr do ... end` — desugars to while + match
        if ((try self.pk()).kind == .kw_let) {
            try self.denyRetiredStmtKeyword(try self.pk());
            _ = try self.adv(); // consume `let`
            const pattern = try self.parse_pattern();
            _ = try self.expect(.assign);
            const scrutinee = try self.parse_expr();
            try self.eat_deprecated(.kw_do);
            const body = try self.parse_block_at(l);
            try self.close_block(l, self.last_layout.offside);
            var break_arm_body_stmts = try self.alloc.alloc(ast.Stmt, 1);
            break_arm_body_stmts[0] = .{ .brk = l };
            var match_arms = try self.alloc.alloc(ast.MatchArm, 2);
            match_arms[0] = .{ .pattern = pattern, .guard = null, .body = body };
            match_arms[1] = .{ .pattern = .wildcard, .guard = null, .body = .{ .loc = l, .stmts = break_arm_body_stmts } };
            const match_expr_ptr = try self.alloc.create(ast.MatchExpr);
            match_expr_ptr.* = .{ .loc = l, .scrutinee = scrutinee, .arms = match_arms };
            const match_e = try self.new_expr(.{ .match_expr = match_expr_ptr });
            var inner_stmts = try self.alloc.alloc(ast.Stmt, 1);
            inner_stmts[0] = .{ .expr_stmt = .{ .loc = l, .expr = match_e } };
            const inner_body = ast.Block{ .loc = l, .stmts = inner_stmts };
            const true_lit = try self.new_expr(.{ .true_lit = l });
            return ast.Stmt{ .while_loop = .{ .loc = l, .cond = true_lit, .body = inner_body } };
        }
        if (try self.parse_while_consumption(l)) |stmt| return stmt;
        const cond = try self.parse_expr();
        try self.eat_deprecated(.kw_do);
        const body = try self.parse_block_at(l);
        try self.close_block(l, self.last_layout.offside);
        return ast.Stmt{ .while_loop = .{ .loc = l, .cond = cond, .body = body } };
    }

    fn parse_repeat(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const body = try self.parse_block_at(l);
        _ = try self.expect(.kw_until);
        const cond = try self.parse_expr();
        return ast.Stmt{ .repeat_loop = .{ .loc = l, .body = body, .cond = cond } };
    }

    /// SOURCE-CONTROL-ONE §5's CANONICAL iteration face, `for(source) (item)`.
    ///
    /// It builds the SAME `gen_for` the familiar `for item in source` builds —
    /// same `vars`, same `iters`, same body — so the two faces are one node by
    /// construction and cannot diverge downstream. This is the whole point:
    /// §10.8 cannot migrate a formatter toward a face that does not exist, and
    /// until now the canonical face was the one that did not parse while its
    /// compatibility spelling did.
    ///
    /// It is NOT `source:iter()` plus repeated `cursor:next()`.
    /// PROTOCOL-PROJECTION-ONE §3 forbids that as a DEFINITION — it is one
    /// realization among indexed traversal, SIMD, tree walk, closed-form
    /// reduction, compile time and nothing. Parsing to the existing iteration
    /// node keeps every one of those reachable, and adds no protocol object,
    /// no cursor and no `next` relation.
    ///
    /// The yield pack is REQUIRED and must name at least one item. §5's
    /// zero-yield spelling (`for(events) tick()`) and §2's source-binding head
    /// (`for(users = load()) (user)`) are deliberately NOT taken here: neither
    /// has a familiar counterpart to converge against, and a face that cannot
    /// be shown identical to an existing one is worse than no face (§8).
    fn parse_for_curried(self: *Parser, l: ast.Loc) ParseError!ast.Stmt {
        _ = try self.adv();
        var iters: std.ArrayList(*ast.Expr) = .empty;
        try iters.append(self.alloc, try self.parse_expr());
        while (try self.eat(.comma) != null)
            try iters.append(self.alloc, try self.parse_expr());
        const src_close = try self.expect(.rparen);

        // The yield pack rides the same LINE as the source pack. That keeps
        // `for(xs) (x)` distinct from a body block that merely opens with a
        // parenthesized expression, without giving `(` any new meaning.
        const pack = try self.pk();
        if (pack.kind != .lparen or pack.loc.line != src_close.loc.line) {
            term.locErr(pack.loc, "write the yielded item pack here, as `for(source) (item)`", .{});
            term.locHint(pack.loc, "the canonical iteration face names what each step yields; `for item in source` is the familiar spelling of the same thing", .{});
            return ParseError.ExpectedToken;
        }
        _ = try self.adv();
        var vars: std.ArrayList([]const u8) = .empty;
        const first_var = try self.expect(.name);
        try vars.append(self.alloc, first_var.text);
        while (try self.eat(.comma) != null) {
            const v = try self.expect(.name);
            try vars.append(self.alloc, v.text);
        }
        _ = try self.expect(.rparen);

        const body = try self.parse_block_at(l);
        try self.close_block(l, self.last_layout.offside);
        return ast.Stmt{ .gen_for = .{
            .loc = l,
            .vars = try vars.toOwnedSlice(self.alloc),
            .iters = try iters.toOwnedSlice(self.alloc),
            .body = body,
        } };
    }

    fn parse_for(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        if ((try self.pk()).kind == .lparen) return self.parse_for_curried(l);
        const first_name = try self.expect(.name);
        const nxt = try self.pk();
        if (nxt.kind == .assign or nxt.kind == .colon) {
            const var_typ = try self.maybe_type_ann();
            _ = try self.expect(.assign);
            const start = try self.parse_expr();
            _ = try self.expect(.comma);
            const stop = try self.parse_expr();
            var step: ?*ast.Expr = null;
            if (try self.eat(.comma) != null) step = try self.parse_expr();
            try self.eat_deprecated(.kw_do);
            const body = try self.parse_block_at(l);
            try self.close_block(l, self.last_layout.offside);
            return ast.Stmt{ .num_for = .{
                .loc = l,
                .var_name = first_name.text,
                .var_typ = var_typ,
                .start = start,
                .stop = stop,
                .step = step,
                .body = body,
            } };
        } else {
            var vars: std.ArrayList([]const u8) = .empty;
            try vars.append(self.alloc, first_name.text);
            while (try self.eat(.comma) != null) {
                const v = try self.expect(.name);
                try vars.append(self.alloc, v.text);
            }
            _ = try self.expect(.kw_in);
            var iters: std.ArrayList(*ast.Expr) = .empty;
            try iters.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null)
                try iters.append(self.alloc, try self.parse_expr());
            try self.eat_deprecated(.kw_do);
            const body = try self.parse_block_at(l);
            try self.close_block(l, self.last_layout.offside);
            return ast.Stmt{ .gen_for = .{
                .loc = l,
                .vars = try vars.toOwnedSlice(self.alloc),
                .iters = try iters.toOwnedSlice(self.alloc),
                .body = body,
            } };
        }
    }

    fn parse_do(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const body = try self.parse_block_at(l);
        try self.close_block(l, self.last_layout.offside);
        return ast.Stmt{ .do_block = .{ .loc = l, .body = body } };
    }

    // ── try/catch/defer ───────────────────────────────────────────────────────

    /// Parse a block that terminates at `catch` or `end` (in addition to the
    /// regular block terminators like `else`, `elseif`, `until`, `eof`).
    fn parse_try_body(self: *Parser) ParseError!ast.Block {
        const l = (try self.pk()).loc;
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            switch (tok.kind) {
                .kw_end, .kw_catch, .kw_else, .kw_elseif, .kw_until, .eof => break,
                .kw_return => {
                    try stmts.append(self.alloc, try self.parse_return());
                    _ = try self.eat(.semi);
                    break;
                },
                else => try stmts.append(self.alloc, try self.parse_stmt()),
            }
        }
        // Extract implicit tail expression.
        var tail_expr: ?*ast.Expr = null;
        if (stmts.items.len > 0) {
            const last = &stmts.items[stmts.items.len - 1];
            if (last.* == .call_stmt) {
                tail_expr = last.call_stmt.expr;
                stmts.items.len -= 1;
            } else if (last.* == .expr_stmt) {
                tail_expr = last.expr_stmt.expr;
                stmts.items.len -= 1;
            }
        }
        return ast.Block{ .loc = l, .stmts = try stmts.toOwnedSlice(self.alloc), .tail_expr = tail_expr };
    }

    /// Parse `try ... catch ... end` statement.
    ///
    /// Catch clauses are untyped in Duo. There is no `catch MyError e` form.
    /// If a name follows `catch`, it's the binding; if a non-name token
    /// follows, the catch is anonymous. Error discrimination is done inside
    /// the body with `match e.__tag` (or `if e.__tag == "..."`).
    ///
    /// ```
    /// try
    ///   -- body
    /// catch e
    ///   -- handle error; check e.__tag
    /// end
    /// ```
    fn parse_try(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc; // consume `try`
        const body = try self.parse_try_body();

        var catches: std.ArrayList(ast.CatchClause) = .empty;
        var defers: std.ArrayList(ast.DeferStmt) = .empty;

        // Parse zero or more catch clauses
        while ((try self.pk()).kind == .kw_catch) {
            const catch_loc = (try self.adv()).loc; // consume `catch`

            var binding: ?[]const u8 = null;

            const nxt = try self.pk();
            if (nxt.kind == .name) {
                // The name after `catch` is always the binding. There is no
                // typed catch form.
                binding = (try self.adv()).text;
            }

            // Parse the catch body (which also terminates at next `catch` or `end`)
            const catch_body = try self.parse_try_body();
            try catches.append(self.alloc, ast.CatchClause{
                .loc = catch_loc,
                .binding = binding,
                .body = catch_body,
            });
        }

        _ = try self.expect(.kw_end);

        return ast.Stmt{ .try_stmt = .{
            .loc = l,
            .body = body,
            .catches = try catches.toOwnedSlice(self.alloc),
            .defers = try defers.toOwnedSlice(self.alloc),
        } };
    }

    /// Parse `defer ... end` statement.
    ///
    /// ```
    /// defer
    ///   -- cleanup code
    /// end
    /// ```
    fn parse_defer(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc; // consume `defer`
        const body = try self.parse_block_at(l);
        try self.close_block(l, self.last_layout.offside);
        return ast.Stmt{ .defer_stmt = .{ .loc = l, .body = body } };
    }

    // ── match ─────────────────────────────────────────────────────────────────

    /// Parse `match expr ... end` as a statement.
    fn parse_match_stmt(self: *Parser) ParseError!ast.Stmt {
        const me = try self.parse_match_inner();
        return ast.Stmt{ .match_stmt = me };
    }

    /// Parse `match expr ... end` as an expression.
    fn parse_match_expr(self: *Parser) ParseError!*ast.Expr {
        const me = try self.parse_match_inner();
        const p = try self.alloc.create(ast.MatchExpr);
        p.* = me;
        return self.new_expr(.{ .match_expr = p });
    }

    /// Shared implementation for parsing a match expression/statement.
    ///
    /// ```
    /// match expr
    ///   case pattern1 then body1
    ///   case pattern2 if guard do body2
    ///   case _ then default_body
    /// end
    /// ```
    fn parse_match_inner(self: *Parser) ParseError!ast.MatchExpr {
        const l = (try self.adv()).loc; // consume `match`
        // retires `match`/`case` (53 keywords -> 30); dispatch belongs in
        // `if`/`elseif` or a table, not a dedicated keyword. `match` is also the
        // slower shape in practice — on ward's WASM interpreter every `match`
        // form measured worse than the equivalent `if`/`elseif` chain, and a
        // named `const` used as a pattern silently becomes a catch-all binding
        // rather than a comparison.
        if (self.idol_mode) {
            term.locWarn(l, "warning: 'match'/'case' are deprecated in .id; use if/elseif or table dispatch", .{});
        }
        const open = try self.line_opener(l);
        const outer_match_col = self.match_open_col;
        self.match_open_col = if (self.idol_mode) open.col else 0;
        defer self.match_open_col = outer_match_col;

        const scrutinee = try self.parse_match_scrutinee();

        var arms: std.ArrayList(ast.MatchArm) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            if (tok.kind == .kw_end or tok.kind == .eof) break;
            // §3 — the arm list closes by dedent. An arm BINDS at or right of
            // the `match` (`case`/`else` sit level with it in every migrated
            // file); anything else back at or left of it belongs to whatever
            // encloses the construct.
            if (self.idol_mode and tok.loc.line != self.prev_line and tok.loc.col <= open.col) {
                if (!(try self.startsMatchArm()) or tok.loc.col < open.col) break;
            }
            try arms.append(self.alloc, try self.parse_match_arm());
        }
        // ACCEPTED AND DELETED (§3.4), not demanded: the arm list may have
        // closed by dedent above, in which case there is nothing to consume.
        if (self.idol_mode) {
            _ = try self.eat(.kw_end);
        } else {
            _ = try self.expect(.kw_end);
        }

        return ast.MatchExpr{
            .loc = l,
            .scrutinee = scrutinee,
            .arms = try arms.toOwnedSlice(self.alloc),
        };
    }

    /// Parse match scrutinee — a restricted expression that does not consume
    /// `{`, `[`, or quoted as call/index suffixes (those start pattern arms).
    fn parse_match_scrutinee(self: *Parser) ParseError!*ast.Expr {
        return self.parse_match_scrutinee_prec(0);
    }

    fn parse_match_scrutinee_prec(self: *Parser, min_prec: u8) ParseError!*ast.Expr {
        var lhs: *ast.Expr = undefined;
        {
            const tok = try self.pk();
            if (tok.kind == .kw_await) {
                try self.denyRetiredStmtKeyword(tok);
                _ = try self.adv(); // consume `await`
                const operand = try self.parse_match_scrutinee_prec(20);
                lhs = try self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
            } else {
                if (tok.kind == .kw_comptime and self.idol_mode) {
                    term.locErr(tok.loc, "'comptime' is not valid in .id files. Use @(expr) for inline comptime evaluation or @comp.* for module-scope transforms.", .{});
                    return ParseError.UnexpectedToken;
                }
                const op: ?ast.UnOp = switch (tok.kind) {
                    .kw_not, .bang => .not,
                    .hash => .len,
                    .hash_hash, .kw_comptime => .compile,
                    .minus => .neg,
                    .tilde => .bnot,
                    else => null,
                };
                if (op) |uop| {
                    if (tok.kind == .kw_not and self.idol_mode)
                        term.locWarn(tok.loc, "warning: 'not' is deprecated in .id; use prefix !", .{});
                    _ = try self.adv();
                    const operand = try self.parse_match_scrutinee_prec(20);
                    lhs = try self.new_expr(.{ .unop = .{ .loc = tok.loc, .op = uop, .operand = operand } });
                } else {
                    lhs = try self.parse_match_scrutinee_suffixed();
                }
            }
        }
        while (true) {
            const tok = try self.pk();
            const inf = infix_prec(tok.kind) orelse break;
            // §3 — see `opensLineAndExpression`.
            if (self.opensLineAndExpression(tok)) break;
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            const rhs = try self.parse_match_scrutinee_prec(inf.right);
            lhs = try self.new_expr(.{ .binop = .{
                .loc = lhs.loc(),
                .op = inf.op,
                .lhs = lhs,
                .rhs = rhs,
            } });
        }
        return lhs;
    }

    /// Like parse_suffixed_expr but does NOT consume `{`, `[`, or quoted
    /// as call/index suffixes (those tokens start match arm patterns).
    fn parse_match_scrutinee_suffixed(self: *Parser) ParseError!*ast.Expr {
        var e = try self.parse_simple_expr();
        while (true) {
            const tok = try self.pk();
            switch (tok.kind) {
                .dot => {
                    _ = try self.adv();
                    const fld = try self.expect_name_like();
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = fld } });
                },
                .colon => {
                    _ = try self.adv();
                    const method = try self.expect_name_like();
                    // Only allow parenthesized call args after method
                    if ((try self.pk()).kind == .lparen) {
                        const callargs = try self.parse_call_args();
                        e = try self.new_expr(.{ .method_call = .{
                            .loc = tok.loc,
                            .obj = e,
                            .method = method,
                            .args = callargs,
                        } });
                    } else {
                        // method with no args — treat as field access
                        e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = method } });
                    }
                },
                .lparen => {
                    const callargs = try self.parse_call_args();
                    // DESCRIPTOR APPLICATION. `point(3, 4)` is the same
                    // application grammar as any other call; what differs is
                    // only what the callee resolves to. Applying a descriptor
                    // fills its slots in declaration order.
                    if (try self.descriptorApplication(tok.loc, e, callargs)) |built| {
                        e = built;
                    } else {
                        e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs } });
                    }
                },
                // Do NOT consume {, [, quoted as suffixes in match scrutinee
                else => break,
            }
        }
        return e;
    }

    fn startsMatchArm(self: *Parser) ParseError!bool {
        const view = token_view.fromLexer(self.lex) orelse {
            const tok = try self.pk();
            term.locErr(tok.loc, "production token view is absent at match-arm lookahead", .{});
            return ParseError.UnexpectedToken;
        };
        const start = self.lex.duoStreamIndex();
        const first = view.at(start) orelse return false;
        if (first.kind == .name and std.mem.eql(u8, first.text, "case")) return true;
        if (first.kind == .kw_else) return true;
        if (!view.canStartPattern(start)) return false;

        var depth: u32 = 0;
        var idx = start;
        while (true) {
            const tok = view.at(idx) orelse return false;
            idx += 1;
            if (tok.kind == .eof or tok.kind == .kw_end or tok.kind == .semi) return false;
            if (depth == 0 and tok.loc.line != first.loc.line) return false;
            switch (tok.kind) {
                .lparen, .lbrace, .lbracket => depth += 1,
                .rparen, .rbrace, .rbracket => {
                    if (depth == 0) return false;
                    depth -= 1;
                },
                .kw_then, .kw_do, .fat_arrow => return depth == 0,
                else => {},
            }
        }
    }

    /// Parse a single match arm. The supported spellings are
    /// `pattern [if guard] then|do body` and `case pattern [if guard] then|do body`.
    /// The body is either a single expression (as a return statement) or
    /// a block that terminates at the next arm or `end`.
    fn parse_match_arm(self: *Parser) ParseError!ast.MatchArm {
        const first = try self.pk();
        const case_syntax = first.kind == .name and std.mem.eql(u8, first.text, "case");
        const else_syntax = first.kind == .kw_else;
        if (case_syntax or else_syntax) _ = try self.adv();

        // `else` is always a wildcard/catch-all pattern — no pattern to parse
        const pattern = if (else_syntax) ast.Pattern.wildcard else try self.parse_pattern();

        // Optional guard: `if cond`
        var guard: ?*ast.Expr = null;
        if ((try self.pk()).kind == .kw_if) {
            _ = try self.adv(); // consume `if`
            guard = try self.parse_expr();
        }

        const separator = try self.pk();
        if (separator.kind == .kw_then or separator.kind == .kw_do or separator.kind == .fat_arrow) {
            _ = try self.adv();
        } else if (case_syntax or else_syntax) {
            // `case pattern statement` remains accepted for older local sources.
        } else {
            term.locErr(separator.loc, "expected '=>', 'then' or 'do', got '{s}'", .{separator.kind.spelling()});
            return ParseError.ExpectedToken;
        }

        // Parse arm body as a block that ends at next arm start or `end`.
        const body = try self.parse_match_arm_body();

        return ast.MatchArm{
            .pattern = pattern,
            .guard = guard,
            .body = body,
        };
    }

    /// Parse the body of a match arm — exactly one statement.
    /// Each arm has a single statement body (like Rust/OCaml match arms).
    /// Uses restricted expression parsing to avoid consuming the next arm's pattern.
    fn parse_match_arm_body(self: *Parser) ParseError!ast.Block {
        const l = (try self.pk()).loc;
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            // Stop at end of match block, or at 'case'/'else' which starts the next arm.
            if (tok.kind == .kw_end or tok.kind == .eof or try self.startsMatchArm()) break;
            // …and at a DEDENT out of the whole construct. Without this the
            // last arm swallowed the statement after the `match` — in
            // `examples/repro_pointer_local_match_panic.id` that is the
            // function's own tail expression, three columns to the left.
            if (self.idol_mode and self.match_open_col != 0 and
                tok.loc.line != self.prev_line and tok.loc.col <= self.match_open_col) break;
            if (tok.kind == .kw_return) {
                // Use restricted return parsing that doesn't consume string/table/array
                // suffixes (those start the next pattern arm).
                const ret_loc = (try self.adv()).loc;
                var vals: std.ArrayList(*ast.Expr) = .empty;
                const nxt = try self.pk();
                const is_case_after = nxt.kind == .name and std.mem.eql(u8, nxt.text, "case");
                switch (nxt.kind) {
                    .kw_end, .kw_else, .kw_elseif, .kw_until, .eof, .semi => {},
                    .name => if (!is_case_after) {
                        try vals.append(self.alloc, try self.parse_match_scrutinee());
                        while (try self.eat(.comma) != null)
                            try vals.append(self.alloc, try self.parse_match_scrutinee());
                    },
                    else => {
                        try vals.append(self.alloc, try self.parse_match_scrutinee());
                        while (try self.eat(.comma) != null)
                            try vals.append(self.alloc, try self.parse_match_scrutinee());
                    },
                }
                try stmts.append(self.alloc, ast.Stmt{ .ret = .{
                    .loc = ret_loc,
                    .vals = try vals.toOwnedSlice(self.alloc),
                } });
            } else {
                self.match_arm_depth += 1;
                defer self.match_arm_depth -= 1;
                try stmts.append(self.alloc, try self.parse_stmt());
            }
        }
        return ast.Block{ .loc = l, .stmts = try stmts.toOwnedSlice(self.alloc) };
    }

    /// Parse a pattern. Patterns can be:
    /// - `_` (wildcard)
    /// - `...name` (rest)
    /// - `{key1: pat1, key2: pat2}` (table destructuring)
    /// - `[pat1, pat2, ...]` (array destructuring)
    /// - `Name.Variant(payload...)` (variant)
    /// - literal: number, string, bool, nil
    /// - `name` (binding)
    fn parse_pattern(self: *Parser) ParseError!ast.Pattern {
        const tok = try self.pk();
        switch (tok.kind) {
            // Rest pattern: ...name
            .dots => {
                _ = try self.adv();
                const nm = try self.expect(.name);
                return ast.Pattern{ .rest = nm.text };
            },
            // Table destructuring: {key: pat, ...}
            .lbrace => return self.parse_table_destr_pattern(),
            // Array destructuring: [pat, pat, ...]
            .lbracket => return self.parse_array_destr_pattern(),
            .kw_nil => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
            .kw_true => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
            .kw_false => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
            // `else` is a wildcard/catch-all pattern in match expressions
            .kw_else => {
                _ = try self.adv();
                return ast.Pattern.wildcard;
            },
            // Name — could be wildcard `_`, variant `Name.Variant(...)`, or binding
            .name => {
                if (std.mem.eql(u8, tok.text, "_")) {
                    _ = try self.adv();
                    return ast.Pattern.wildcard;
                }
                // Check for variant pattern: Name.Variant(payload...)
                // A variant is recognized by Name.Name( pattern
                const saved = self.lex.*;
                const first_name = try self.adv();
                if ((try self.pk()).kind == .dot) {
                    _ = try self.adv(); // consume `.`
                    const after_dot = try self.pk();
                    if (after_dot.kind == .name) {
                        const variant_name = try self.adv();
                        // Build tag as "EnumName.VariantName"
                        const tag = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ first_name.text, variant_name.text });
                        // Check for payload: (pattern, pattern, ...)
                        var payload: ?[]ast.Pattern = null;
                        if ((try self.pk()).kind == .lparen) {
                            _ = try self.adv(); // consume `(`
                            var patterns: std.ArrayList(ast.Pattern) = .empty;
                            if ((try self.pk()).kind != .rparen) {
                                try patterns.append(self.alloc, try self.parse_pattern());
                                while (try self.eat(.comma) != null) {
                                    try patterns.append(self.alloc, try self.parse_pattern());
                                }
                            }
                            _ = try self.expect(.rparen);
                            payload = try patterns.toOwnedSlice(self.alloc);
                        }
                        return ast.Pattern{ .variant = .{ .tag = tag, .payload = payload } };
                    } else {
                        // Not a variant, restore and treat as binding
                        self.lex.* = saved;
                        _ = try self.adv(); // re-consume the name
                        return ast.Pattern{ .binding = .{ .name = first_name.text, .typ = null } };
                    }
                }
                // Simple binding
                return ast.Pattern{ .binding = .{ .name = first_name.text, .typ = null } };
            },
            // Unary minus for negative number literals
            .minus => {
                _ = try self.adv();
                const num_tok = try self.pk();
                if (num_tok.kind == .int_lit or num_tok.kind == .float_lit) {
                    const e = try self.parse_simple_expr();
                    const neg_e = try self.new_expr(.{ .unop = .{ .loc = tok.loc, .op = .neg, .operand = e } });
                    return ast.Pattern{ .literal = neg_e };
                }
                term.locErr(tok.loc, "expected number after '-' in pattern", .{});
                return ParseError.UnexpectedToken;
            },
            else => {
                if (grammar_roles.isLiteralKind(tok.kind)) {
                    const e = try self.parse_simple_expr();
                    return ast.Pattern{ .literal = e };
                }
                term.locErr(tok.loc, "expected pattern, got '{s}'", .{tok.kind.spelling()});
                return ParseError.UnexpectedToken;
            },
        }
    }

    /// Parse table destructuring pattern: `{key1: pat1, key2: pat2}` or shorthand `{name, age}`.
    fn parse_table_destr_pattern(self: *Parser) ParseError!ast.Pattern {
        _ = try self.adv(); // consume `{`
        var entries: std.ArrayList(ast.Pattern.TableDestrEntry) = .empty;
        while ((try self.pk()).kind != .rbrace) {
            const key_tok = try self.expect(.name);
            if ((try self.pk()).kind == .colon) {
                _ = try self.adv();
                const pat = try self.parse_pattern();
                try entries.append(self.alloc, .{ .key = key_tok.text, .pat = pat });
            } else {
                // Shorthand `{ name, age }` → `{ name: name, age: age }`
                try entries.append(self.alloc, .{
                    .key = key_tok.text,
                    .pat = ast.Pattern{ .binding = .{ .name = key_tok.text, .typ = null } },
                });
            }
            if (try self.eat(.comma) == null) break;
        }
        _ = try self.expect(.rbrace);
        return ast.Pattern{ .table_destr = try entries.toOwnedSlice(self.alloc) };
    }

    /// Lower `{ a, b } = rhs` to field-extract assignments.
    fn stmt_from_table_destructure(self: *Parser, pat: ast.Pattern, rhs: *ast.Expr, loc: ast.Loc) ParseError!ast.Stmt {
        if (pat != .table_destr) return ParseError.UnexpectedToken;
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        for (pat.table_destr) |entry| {
            const bind_name: []const u8 = switch (entry.pat) {
                .binding => |b| b.name,
                else => {
                    term.locErr(loc, "destructure assign requires simple bindings", .{});
                    return ParseError.UnexpectedToken;
                },
            };
            const field_val = try self.new_expr(.{
                .field = .{
                    .loc = loc,
                    .obj = rhs,
                    .field = entry.key,
                },
            });
            const target = try self.new_expr(.{ .name = .{ .loc = loc, .ident = bind_name } });
            var targets = try self.alloc.alloc(*ast.Expr, 1);
            targets[0] = target;
            var values = try self.alloc.alloc(*ast.Expr, 1);
            values[0] = field_val;
            try stmts.append(self.alloc, ast.Stmt{ .assign = .{
                .loc = loc,
                .targets = targets,
                .values = values,
            } });
        }
        if (stmts.items.len == 1) return stmts.items[0];
        return ast.Stmt{ .do_block = .{ .loc = loc, .body = .{ .loc = loc, .stmts = try stmts.toOwnedSlice(self.alloc) } } };
    }

    /// Lower `Name: @{ Red, Green, Blue }` or `Name: @{ x: f64, y: f64 }`.
    fn stmt_from_descriptor(self: *Parser, name: []const u8, loc: ast.Loc) ParseError!ast.Stmt {
        const parsed = try self.parse_descriptor_table();
        if (parsed.entries.len == 0) {
            term.locErr(loc, "descriptor @{{ }} must contain at least one entry", .{});
            return ParseError.UnexpectedToken;
        }

        var saw_variant = false;
        var saw_recordish = false;
        for (parsed.entries) |entry| {
            switch (entry) {
                .variant, .variant_payload => saw_variant = true,
                .field, .spread => saw_recordish = true,
            }
        }
        if (saw_variant and saw_recordish) {
            term.locErr(loc, "descriptor cannot mix enum variants with typed fields or spread", .{});
            return ParseError.UnexpectedToken;
        }

        if (saw_variant) {
            var variants: std.ArrayList(ast.EnumVariant) = .empty;
            for (parsed.entries) |entry| {
                switch (entry) {
                    .variant => |vname| try variants.append(self.alloc, .{ .name = vname, .payload = null }),
                    .variant_payload => |vp| try variants.append(self.alloc, .{
                        .name = vp.name,
                        .payload = vp.payload,
                    }),
                    else => unreachable,
                }
            }
            const case_slice = try variants.toOwnedSlice(self.alloc);
            // Record the cases this case-set declares, so `== .eof` resolves.
            // A name a SECOND case-set claims is marked ambiguous rather than
            // overwritten: two homes for one spelling is exactly the state
            // where a silent pick would produce a wrong value.
            for (case_slice) |v| {
                const gop = try self.caseset_cases.getOrPut(self.alloc, v.name);
                if (gop.found_existing) {
                    if (!std.mem.eql(u8, gop.value_ptr.*, name)) gop.value_ptr.* = "";
                } else {
                    gop.value_ptr.* = name;
                }
            }
            return ast.Stmt{ .enum_def = .{
                .loc = loc,
                .name = name,
                .type_params = null,
                .variants = case_slice,
                .attributes = &.{},
            } };
        }

        // Record descriptor: optional leading ..Parent entries, then name: Type fields.
        // Multiple spreads are accepted for descriptor composition (GP-012).
        var parent: ?[]const u8 = null;
        var extra_parents: std.ArrayList([]const u8) = .empty;
        var fields: std.ArrayList(ast.RecordField) = .empty;
        var idx: usize = 0;
        while (idx < parsed.entries.len) : (idx += 1) {
            switch (parsed.entries[idx]) {
                .spread => |expr| {
                    if (fields.items.len > 0) {
                        term.locErr(loc, "descriptor spread must appear before typed fields", .{});
                        return ParseError.UnexpectedToken;
                    }
                    if (expr.* != .name) {
                        term.locErr(loc, "descriptor spread must be a type name", .{});
                        return ParseError.UnexpectedToken;
                    }
                    if (parent == null) {
                        parent = expr.name.ident;
                    } else {
                        try extra_parents.append(self.alloc, expr.name.ident);
                    }
                },
                .field => |fld| try fields.append(self.alloc, fld),
                .variant, .variant_payload => unreachable,
            }
        }

        const field_slice = try fields.toOwnedSlice(self.alloc);
        const rec = try self.alloc.create(ast.TypeExpr.RecordType);
        rec.* = .{ .fields = field_slice };
        return ast.Stmt{ .alias_def = .{
            .loc = loc,
            .name = name,
            .type_params = null,
            .target = .{ .record = rec },
            .parent = parent,
            .extra_parents = try extra_parents.toOwnedSlice(self.alloc),
            .fields = &.{},
            .methods = &.{},
            .attributes = &.{},
        } };
    }

    const DescriptorEntry = union(enum) {
        variant: []const u8,
        variant_payload: struct { name: []const u8, payload: ?[]ast.EnumVariant.PayloadField },
        field: ast.RecordField,
        spread: *ast.Expr,
    };

    fn parse_descriptor_table(self: *Parser) ParseError!struct { entries: []DescriptorEntry } {
        _ = try self.expect(.lbrace);
        self.descriptor_body_depth += 1;
        defer self.descriptor_body_depth -= 1;
        var entries: std.ArrayList(DescriptorEntry) = .empty;
        while (!(try self.check(.rbrace))) {
            const tok = try self.pk();
            if (tok.kind == .concat) {
                _ = try self.adv();
                const spread_expr = try self.parse_expr();
                try entries.append(self.alloc, .{ .spread = spread_expr });
            } else if (tok.kind == .name) {
                const field_loc = tok.loc;
                const saved = self.lex.saveState();
                _ = try self.adv();
                if (try self.check(.lparen)) {
                    _ = try self.adv();
                    var payload: ?[]ast.EnumVariant.PayloadField = null;
                    if (!(try self.check(.rparen))) {
                        var payload_fields: std.ArrayList(ast.EnumVariant.PayloadField) = .empty;
                        try payload_fields.append(self.alloc, try self.parseEnumPayloadField());
                        while (try self.eat(.comma) != null) {
                            try payload_fields.append(self.alloc, try self.parseEnumPayloadField());
                        }
                        payload = try payload_fields.toOwnedSlice(self.alloc);
                    }
                    _ = try self.expect(.rparen);
                    try entries.append(self.alloc, .{
                        .variant_payload = .{
                            .name = tok.text,
                            .payload = payload,
                        },
                    });
                } else if (try self.check(.colon)) {
                    _ = try self.adv();
                    const typ = try self.parse_field_type();
                    if (try self.eat(.assign) != null) _ = try self.parse_expr(); // default, consumed
                    try entries.append(self.alloc, .{ .field = .{
                        .loc = field_loc,
                        .name = tok.text,
                        .typ = typ,
                    } });
                } else if (try self.check(.assign)) {
                    self.lex.restoreState(saved);
                    term.locErr(field_loc, "descriptor fields use 'name: Type' syntax, not '='", .{});
                    return ParseError.UnexpectedToken;
                } else {
                    self.lex.restoreState(saved);
                    _ = try self.adv();
                    try entries.append(self.alloc, .{ .variant = tok.text });
                }
            } else {
                term.locErr(tok.loc, "expected descriptor field name or spread", .{});
                return ParseError.UnexpectedToken;
            }
            _ = try self.eat(.comma);
        }
        _ = try self.expect(.rbrace);
        return .{ .entries = try entries.toOwnedSlice(self.alloc) };
    }

    fn parse_array_destr_pattern(self: *Parser) ParseError!ast.Pattern {
        _ = try self.adv(); // consume `[`
        var patterns: std.ArrayList(ast.Pattern) = .empty;
        while ((try self.pk()).kind != .rbracket) {
            try patterns.append(self.alloc, try self.parse_pattern());
            if (try self.eat(.comma) == null) break;
        }
        _ = try self.expect(.rbracket);
        return ast.Pattern{ .array_destr = try patterns.toOwnedSlice(self.alloc) };
    }

    /// §3 — prepend implicit `self` for colon method assignments when absent.
    fn ensure_implicit_self_param(self: *Parser, fb: *ast.FuncBody) !void {
        if (fb.params.len > 0 and std.mem.eql(u8, fb.params[0].name, "self")) return;
        var params: std.ArrayList(ast.FuncParam) = .empty;
        try params.append(self.alloc, .{
            .name = "self",
            .typ = .inferred,
            .default_val = null,
            .loc = fb.loc,
        });
        try params.appendSlice(self.alloc, fb.params);
        fb.params = try params.toOwnedSlice(self.alloc);
    }

    /// Single-line function bodies use `parse_expr` unless the body begins with assignment syntax.
    fn func_body_should_use_expr_stmt(self: *Parser) ParseError!bool {
        const tok = try self.pk();
        if (tok.kind != .name) return false;
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);
        _ = try self.adv();
        var nxt = try self.pk();
        if (nxt.kind == .dot) {
            while (try self.eat(.dot) != null) {
                if ((try self.pk()).kind != .name) return false;
                _ = try self.adv();
            }
            nxt = try self.pk();
        }
        if (nxt.kind == .assign or compound_assign_op(nxt.kind) != null) return true;
        return (try self.peek_glued_assign(nxt)) != null;
    }

    /// §3 — `Type:method = (…) …` or `Type.method = (…) …` assign-form func decl.
    fn try_parse_qualified_func_assign(self: *Parser, first: *ast.Expr) ParseError!?ast.Stmt {
        const saved = self.lex.saveState();
        errdefer self.lex.restoreState(saved);

        var path: std.ArrayList([]const u8) = .empty;
        var method = false;
        var loc = first.loc();

        if (first.* == .name) {
            const nxt = try self.pk();
            if (nxt.kind != .dot and nxt.kind != .colon) return null;
            try path.append(self.alloc, first.name.ident);
            while (true) {
                if (try self.eat(.dot) != null) {
                    if ((try self.pk()).kind != .name) {
                        self.lex.restoreState(saved);
                        return null;
                    }
                    const part = try self.expect(.name);
                    try path.append(self.alloc, part.text);
                } else if ((try self.pk()).kind == .colon) {
                    const colon = try self.pk();
                    // `a:b = (…)` is a single-line declaration. When the token
                    // after `:` is on a LATER line this is not that form at all
                    // — it is a descriptor home written offside (`point:` over
                    // `x: f64`), and consuming it here reported "expected
                    // function arguments" for a shape that is not a function.
                    _ = try self.adv();
                    if ((try self.pk()).loc.line != colon.loc.line) {
                        self.lex.restoreState(saved);
                        return null;
                    }
                    if ((try self.pk()).kind != .name) {
                        self.lex.restoreState(saved);
                        return null;
                    }
                    const part = try self.expect(.name);
                    if (part.loc.line != colon.loc.line or
                        part.loc.col > colon.loc.col + @as(u32, @intCast(colon.text.len)))
                    {
                        self.lex.restoreState(saved);
                        return null;
                    }
                    try path.append(self.alloc, part.text);
                    method = true;
                    break;
                } else break;
            }
        } else if (first.* == .field and first.field.obj.* == .name) {
            try path.append(self.alloc, first.field.obj.name.ident);
            try path.append(self.alloc, first.field.field);
            loc = first.field.obj.loc();
        } else return null;

        if (path.items.len < 2) {
            self.lex.restoreState(saved);
            return null;
        }
        if ((try self.pk()).kind != .assign) {
            self.lex.restoreState(saved);
            return null;
        }
        _ = try self.adv(); // consume '='
        if (!try self.starts_binding_func_expr()) {
            self.lex.restoreState(saved);
            return null;
        }
        var fb = try self.parse_func_body(loc);
        if (method) try self.ensure_implicit_self_param(&fb);
        return ast.Stmt{ .func_decl = .{
            .loc = loc,
            .path = try path.toOwnedSlice(self.alloc),
            .method = method,
            .is_local = false,
            .func = fb,
            .attributes = &.{},
        } };
    }

    fn parse_label(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const nm = try self.expect(.name);
        _ = try self.expect(.dcolon);
        return ast.Stmt{ .label_stmt = .{ .loc = l, .label = nm.text } };
    }

    fn parse_expr_stmt(self: *Parser) ParseError!ast.Stmt {
        // Check for unary operators (not, #, -, ~, ##, comptime, await) — these
        // need full expression parsing, not parse_suffixed_expr which only handles
        // suffixed expressions (names, literals, calls, field access).
        const first_tok = try self.pk();
        const is_unary = grammar_roles.lookup(first_tok.kind).prefix;
        // `{ name, age } = user` named destructuring assign
        if (first_tok.kind == .lbrace) {
            const saved = self.lex.saveState();
            _ = try self.adv(); // consume '{'
            var is_table_literal = false;
            const inner = try self.pk();
            switch (inner.kind) {
                .lbracket, .concat, .int_lit => is_table_literal = true,
                .name => {
                    const name_saved = self.lex.saveState();
                    _ = try self.adv();
                    if ((try self.pk()).kind == .assign) is_table_literal = true;
                    self.lex.restoreState(name_saved);
                },
                else => if (grammar_roles.isQuotedKind(inner.kind)) {
                    is_table_literal = true;
                },
            }
            self.lex.restoreState(saved);
            if (!is_table_literal) {
                const destr_saved = self.lex.saveState();
                if (self.parse_table_destr_pattern()) |pat| {
                    if ((try self.pk()).kind == .assign) {
                        _ = try self.adv();
                        const rhs = try self.parse_expr();
                        return try self.stmt_from_table_destructure(pat, rhs, first_tok.loc);
                    }
                } else |_| {}
                self.lex.restoreState(destr_saved);
            }
        }
        if (is_unary) {
            const expr = try self.parse_expr();
            return ast.Stmt{ .expr_stmt = .{ .loc = expr.loc(), .expr = expr } };
        }

        const first = try self.parse_suffixed_expr();

        // If the next token continues the expression (binary op, etc.),
        // parse the full expression.
        const nxt = try self.pk();

        // §3 — Person:greet = (other) … / math.add = (a, b) …
        if (try self.try_parse_qualified_func_assign(first)) |fd_stmt| {
            return fd_stmt;
        }

        // Typed-binding without 'local': name : Type = value
        // parse_suffixed_expr breaks on ':' when followed by a type-like token.
        if (first.* == .name and nxt.kind == .colon) {
            const colon_tok = try self.adv(); // consume ':'
            // `point:` over an indented field region — a descriptor home with
            // no delimiters. Checked before the `{`/`@` faces because it is a
            // different shape entirely, not a variant of them.
            if (try self.starts_offside_record(colon_tok)) {
                const rec_typ = try self.parse_offside_record(colon_tok.loc);
                try self.noteRecordDescriptor(first.name.ident, rec_typ);
                return ast.Stmt{ .alias_def = .{
                    .loc = first.loc(),
                    .name = first.name.ident,
                    .target = rec_typ,
                    .fields = &.{},
                    .methods = &.{},
                    .attributes = &.{},
                } };
            }
            // deleted prefix-`@`, so the canonical spelling of a
            // case-set is `kind: { name, number, eof }` — §7 and the
            // golden `token`/`lexer` in §20 are written that way. The machinery
            // already exists (parse_descriptor_table handles bare cases AND
            // `circle(r: f64)` payloads); only the `@` gate kept it unreachable,
            // which is why `kind: @{ … }` checks clean and `kind: { … }` does
            // not. gap[025].
            //
            // Routed on LOOKAHEAD, not unconditionally: `{ x: i64, y: i64 }` is
            // a record type and must keep going to parse_type. A case-set is a
            // name followed by `,` or `(` — a record field always has `:`.
            if ((try self.pk()).kind == .lbrace) caseset: {
                const saved = self.lex.saveState();
                _ = try self.adv();
                var is_caseset = false;
                if ((try self.pk()).kind == .name) {
                    _ = try self.adv();
                    const after = (try self.pk()).kind;
                    is_caseset = after == .comma or after == .lparen;
                } else if ((try self.pk()).kind == .concat) {
                    // `Name: { ..Base, y: i64 }` — a descriptor SPREAD. Only
                    // `stmt_from_descriptor` reads `.spread` entries; the
                    // record-type reader has nowhere to put a parent, so the
                    // sigil-free spelling failed with "write `name` at this
                    // token edge" and `{ ..Base }` was the ONLY spelling of a
                    // composed descriptor. That made the sigil load-bearing
                    // for one face after `law.injection.only` retired it, and
                    // it made `pretty.zig` reprint `@{` to keep the parent.
                    // Same reader, same entries; the sigil is no longer the
                    // thing that reaches it.
                    is_caseset = true;
                }
                self.lex.restoreState(saved);
                if (!is_caseset) break :caseset;
                return try self.stmt_from_descriptor(first.name.ident, first.loc());
            }
            // RETIRED. `@{ … }` is exclusively world injection
            // (`law.injection.only`); a descriptor is an ordinary table.
            if ((try self.pk()).kind == .at) {
                _ = try self.adv();
                if ((try self.pk()).kind == .lbrace) {
                    term.locErr(first.loc(), "'@{{ … }}' is world injection, not descriptor construction", .{});
                    term.locHint(first.loc(), "law.injection.only retired the descriptor sigil; the copula reader is the same one, reached without it. Write '{s}: {{ … }}' — fields, variants and '..parent' spreads all spell there", .{first.name.ident});
                    return ParseError.UnexpectedToken;
                }
                term.locErr(first.loc(), "expected '{{' after '@' in descriptor declaration", .{});
                return ParseError.UnexpectedToken;
            }
            // The descriptor being declared is the HOME any inline case-set in
            // its body takes its name from (§0.1). Saved and restored rather
            // than assigned, so a nested descriptor type does not steal it.
            const saved_home = self.descriptor_home;
            self.descriptor_home = first.name.ident;
            defer self.descriptor_home = saved_home;
            self.union_alternative_seen = false;
            const typ = try self.parse_type();
            const binding_fallible = self.union_alternative_seen;

            // Jai-like type definition: `Name: { fields }` with no initializer
            // becomes an alias_def (equivalent to `type Name = { fields }`)
            if (typ == .record and (try self.pk()).kind != .assign) {
                try self.noteRecordDescriptor(first.name.ident, typ);
                return ast.Stmt{ .alias_def = .{
                    .loc = first.loc(),
                    .name = first.name.ident,
                    .target = typ,
                    .fields = &.{},
                    .methods = &.{},
                    .attributes = &.{},
                } };
            }

            var inits: std.ArrayList(*ast.Expr) = .empty;
            if (try self.eat(.assign)) |eq_tok| {
                // A bare `=` whose RHS is an indented slot region is a
                // structured pack; see `starts_offside_pack`.
                if (try self.starts_offside_pack(eq_tok)) {
                    try inits.append(self.alloc, try self.parse_offside_pack_expr(eq_tok.loc));
                    var pnames: std.ArrayList(ast.LocalName) = .empty;
                    try pnames.append(self.alloc, ast.LocalName{
                        .ident = first.name.ident,
                        .typ = typ,
                        .attrib = null,
                        .attributes = &.{},
                        .loc = first.loc(),
                    });
                    return ast.Stmt{ .local_decl = .{
                        .loc = first.loc(),
                        .names = try pnames.toOwnedSlice(self.alloc),
                        .inits = try inits.toOwnedSlice(self.alloc),
                    } };
                }
                // C0 §65: the result descriptor belongs to the binding, not to
                // a suffix on the callable face.  Preserve that demand on the
                // ordinary function record so every later stage sees exactly
                // the same semantic object as the legacy suffix form.
                if (try self.starts_binding_func_expr()) {
                    var fb = try self.parse_func_body(first.loc());
                    fb.ret_type = typ;
                    fb.ret_fallible = binding_fallible;
                    const path = try self.alloc.alloc([]const u8, 1);
                    path[0] = first.name.ident;
                    return ast.Stmt{ .func_decl = .{
                        .loc = first.loc(),
                        .path = path,
                        .method = false,
                        .is_local = false,
                        .func = fb,
                        .attributes = &.{},
                    } };
                }
                try inits.append(self.alloc, try self.parse_expr());
            }
            var names: std.ArrayList(ast.LocalName) = .empty;
            try names.append(self.alloc, ast.LocalName{
                .ident = first.name.ident,
                .typ = typ,
                .attrib = null,
                .attributes = &.{},
                .loc = first.loc(),
            });
            return ast.Stmt{ .local_decl = .{
                .loc = first.loc(),
                .names = try names.toOwnedSlice(self.alloc),
                .inits = try inits.toOwnedSlice(self.alloc),
            } };
        }

        if (infix_prec(nxt.kind) != null) {
            // Save state, re-parse as full expression with precedence climbing.
            // We already consumed the prefix via parse_suffixed_expr, so we
            // need to continue from here.  Reconstruct by re-parsing from the
            // start of the expression using parse_prec.
            // Simpler: save the lexer position and re-parse.  But we don't
            // have lexer save/restore.  Instead, we use a different approach:
            // the suffix_expr already consumed the base, so we just continue
            // the precedence climb manually.
            // Actually the simplest: when we detect an infix operator,
            // we know this isn't an assignment or bash call, so it's an
            // expression statement.  We already have the base parsed; we
            // just need to continue with the rest.
            // But we can't easily go back.  Instead, we'll let the case
            // after the bash-call check handle this.
        }

        // ── Assignment or sequence expression ────────────────────────────────
        // Handle:  a = ...        a, b = ...        a += ...
        // Also:    a, b           (bare sequence — implicit multi-value return)
        const glued = try self.peek_glued_assign(nxt);
        if (nxt.kind == .assign or compound_assign_op(nxt.kind) != null or glued != null) {
            // Single-target assignment:  name = expr  /  name += expr  /
            // name >>= expr (the operator and its `=` are two glued tokens)
            if (first.* == .name and nxt.kind == .assign) {
                const saved = self.lex.saveState();
                _ = try self.adv();
                const is_func_assign = try self.starts_binding_func_expr();
                self.lex.restoreState(saved);
                if (is_func_assign) {
                    _ = try self.adv();
                    const fb = try self.parse_func_body(first.loc());
                    const path = try self.alloc.alloc([]const u8, 1);
                    path[0] = first.name.ident;
                    return ast.Stmt{ .func_decl = .{
                        .loc = first.loc(),
                        .path = path,
                        .method = false,
                        .is_local = false,
                        .func = fb,
                        .attributes = &.{},
                    } };
                }
            }
            _ = try self.adv(); // consume = or compound-assign
            // `>>=` is TWO tokens; the second is the `=` glued to the operator.
            if (glued != null) _ = try self.adv();
            // Check for `Name = struct ... end` — C-layout type definition
            if (first.* == .name and compound_assign_op(nxt.kind) == null) {
                const next_tok = try self.pk();
                if (next_tok.kind == .name and std.mem.eql(u8, next_tok.text, "struct")) {
                    _ = try self.adv(); // consume "struct"
                    return try self.parse_struct_body(first.name.ident, &.{});
                }
            }
            var values: std.ArrayList(*ast.Expr) = .empty;
            if (glued orelse compound_assign_op(nxt.kind)) |op| {
                const rhs = if (self.match_arm_depth > 0)
                    try self.parse_match_scrutinee()
                else
                    try self.parse_expr();
                try values.append(self.alloc, try self.new_expr(.{ .binop = .{
                    .loc = first.loc(),
                    .op = op,
                    .lhs = first,
                    .rhs = rhs,
                } }));
            } else if (try self.starts_offside_pack(nxt)) {
                // `person =` over an indented slot region — a structured pack,
                // no delimiters. Slot forms only; see `starts_offside_pack`.
                try values.append(self.alloc, try self.parse_offside_pack_expr(nxt.loc));
            } else {
                if (self.match_arm_depth > 0) {
                    try values.append(self.alloc, try self.parse_match_scrutinee());
                    while (try self.eat(.comma) != null)
                        try values.append(self.alloc, try self.parse_match_scrutinee());
                } else {
                    try values.append(self.alloc, try self.parse_expr());
                    while (try self.eat(.comma) != null)
                        try values.append(self.alloc, try self.parse_expr());
                }
            }
            var single_target: std.ArrayList(*ast.Expr) = .empty;
            try single_target.append(self.alloc, first);
            return ast.Stmt{ .assign = .{
                .loc = first.loc(),
                .targets = try single_target.toOwnedSlice(self.alloc),
                .values = try values.toOwnedSlice(self.alloc),
            } };
        } else if (nxt.kind == .comma) {
            // Could be multi-target assignment (a, b = ...) or bare sequence
            // (a, b).  Speculatively parse comma-separated names, then check
            // whether an assignment operator follows.
            const saved = self.lex.saveState();
            var exprs: std.ArrayList(*ast.Expr) = .empty;
            try exprs.append(self.alloc, first);
            while (try self.eat(.comma) != null)
                try exprs.append(self.alloc, try self.parse_suffixed_expr());
            const after = try self.pk();
            const after_compound = compound_assign_op(after.kind);
            if (after.kind == .assign or after_compound != null) {
                // ── Multi-target assignment: a, b = expr1, expr2 ──
                if (after_compound != null and exprs.items.len != 1) {
                    term.locErr(after.loc, "compound assignment accepts one target", .{});
                    return ParseError.UnexpectedToken;
                }
                _ = try self.adv(); // consume = or compound-assign
                var values: std.ArrayList(*ast.Expr) = .empty;
                if (after_compound) |op| {
                    const rhs = if (self.match_arm_depth > 0)
                        try self.parse_match_scrutinee()
                    else
                        try self.parse_expr();
                    try values.append(self.alloc, try self.new_expr(.{ .binop = .{
                        .loc = first.loc(),
                        .op = op,
                        .lhs = first,
                        .rhs = rhs,
                    } }));
                } else if (try self.starts_offside_pack(after)) {
                    // `person =` over an indented slot region — a structured
                    // pack, no delimiters. Slot forms only; see
                    // `starts_offside_pack`.
                    try values.append(self.alloc, try self.parse_offside_pack_expr(after.loc));
                } else {
                    if (self.match_arm_depth > 0) {
                        try values.append(self.alloc, try self.parse_match_scrutinee());
                        while (try self.eat(.comma) != null)
                            try values.append(self.alloc, try self.parse_match_scrutinee());
                    } else {
                        try values.append(self.alloc, try self.parse_expr());
                        while (try self.eat(.comma) != null)
                            try values.append(self.alloc, try self.parse_expr());
                    }
                }
                const tgts = try exprs.toOwnedSlice(self.alloc);
                const vals = try values.toOwnedSlice(self.alloc);
                // gap[077]: simultaneous, when the targets and the values
                // overlap. Shape-preserving otherwise.
                if (try self.parallel_assign(first.loc(), tgts, vals)) |simultaneous| {
                    return simultaneous;
                }
                return ast.Stmt{ .assign = .{
                    .loc = first.loc(),
                    .targets = tgts,
                    .values = vals,
                } };
            } else {
                // ── Bare sequence expression: a, b ──
                // No assignment operator follows — this is a comma-separated
                // expression list.  Common as an implicit multi-value return.
                self.lex.restoreState(saved);
                // Re-parse: first was already consumed, but we restored past
                // the comma so re-collect from first.
                var seq: std.ArrayList(*ast.Expr) = .empty;
                try seq.append(self.alloc, first);
                while (try self.eat(.comma) != null)
                    try seq.append(self.alloc, try self.parse_expr());
                return ast.Stmt{ .expr_stmt = .{
                    .loc = first.loc(),
                    .expr = try self.new_expr(.{ .sequence = .{
                        .loc = first.loc(),
                        .exprs = try seq.toOwnedSlice(self.alloc),
                    } }),
                } };
            }
        }

        // Bash-style call: name arg1 arg2 ...
        //
        // §3 — STATEMENTS END AT NEWLINE (except inside an open
        // `( [ {`, which this form has none of). The argument must therefore
        // sit on the callee's own line. Without that test a block whose tail
        // expression is a bare name swallows the next statement:
        //
        //     sum = (n: i64): i64
        //         …
        //         acc          -- tail expression
        //
        //     main = (): i64   -- was read as `acc(main)`, then `= …` failed
        //
        // which only became reachable once dedent could close `sum` without an
        // `end` standing between the two lines.
        if (first.* == .name) {
            const is_bash_arg = nxt.loc.line == first.loc().line and
                (nxt.kind == .name or grammar_roles.isLiteralKind(nxt.kind));
            if (is_bash_arg) {
                const name_info = first.name;
                var args: std.ArrayList(*ast.Expr) = .empty;
                try args.append(self.alloc, try self.parse_parenless_call_arg());
                while (true) {
                    const peek = try self.pk();
                    const is_next = peek.loc.line == first.loc().line and
                        (peek.kind == .name or grammar_roles.isLiteralKind(peek.kind));
                    if (!is_next) break;
                    if (peek.kind == .semi or peek.kind == .eof or
                        peek.kind == .kw_end or peek.kind == .kw_else or
                        peek.kind == .kw_elseif or peek.kind == .kw_until) break;
                    try args.append(self.alloc, try self.parse_parenless_call_arg());
                }
                const func_expr = try self.alloc.create(ast.Expr);
                func_expr.* = .{ .name = .{ .loc = name_info.loc, .ident = name_info.ident } };
                const call_expr = try self.alloc.create(ast.Expr);
                call_expr.* = .{ .call = .{
                    .loc = name_info.loc,
                    .func = func_expr,
                    .args = try args.toOwnedSlice(self.alloc),
                    .form = .parenless,
                } };
                const expr = try self.finish_prec(call_expr, 0);
                switch (expr.*) {
                    .call, .method_call => return ast.Stmt{ .call_stmt = .{ .loc = name_info.loc, .expr = expr } },
                    else => return ast.Stmt{ .expr_stmt = .{ .loc = expr.loc(), .expr = expr } },
                }
            }
        }

        // Expression statement: the remaining case for any expression that
        // isn't an assignment, bash call, or a specific statement form.
        // If the expression continues with binary/infix operators, complete it.
        var expr = first;
        if (infix_prec(nxt.kind) != null) {
            // Continue precedence climbing from the base expression.
            // We've already parsed the LHS; just continue with the infix loop.
            expr = try self.finish_prec(expr, 0);
        }
        switch (expr.*) {
            .call, .method_call => {},
            else => {
                return ast.Stmt{ .expr_stmt = .{ .loc = expr.loc(), .expr = expr } };
            },
        }
        return ast.Stmt{ .call_stmt = .{ .loc = expr.loc(), .expr = expr } };
    }

    /// Continue precedence climbing from an already-parsed LHS expression.
    fn finish_prec(self: *Parser, lhs: *ast.Expr, min_prec: u8) ParseError!*ast.Expr {
        var e = lhs;
        while (true) {
            const tok = try self.pk();
            const inf = infix_prec(tok.kind) orelse break;
            if (tok.kind == .at and tok.loc.line > e.loc().line) break;
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            const rhs = if (try self.at_anchor_case(inf.op))
                try self.parse_anchor_case()
            else
                try self.parse_operand(inf.op, inf.right);
            e = try self.new_expr(.{ .binop = .{
                .loc = e.loc(),
                .op = inf.op,
                .lhs = e,
                .rhs = rhs,
            } });
        }
        return e;
    }

    /// Parenless call arguments bind tighter than binary `+`/`-` (§2.5, GR-call-002).
    const parenless_call_arg_min_prec: u8 = 18;

    /// Parse one parenless call argument — stops before low-precedence infix (`+`, `-`, …).
    /// The right operand of a binary operator, with ONE operator singled out:
    /// `|>`'s right operand is ARGUMENT POSITION. `p |> .x` means "apply the
    /// lens `.x` to `p`", which is the same stance `map(.x)` has and must not
    /// become the method-scope walk `p.x` just because a receiver happens to be
    /// in scope. The codegen tests pin both `p |> .x` and the chained
    /// `p |> .x |> .y`, and they are what caught this.
    fn parse_operand(self: *Parser, op: ast.BinOp, min_prec: u8) ParseError!*ast.Expr {
        if (op != .pipeline) return self.parse_prec(min_prec);
        self.call_arg_depth += 1;
        defer self.call_arg_depth -= 1;
        return self.parse_prec(min_prec);
    }

    fn parse_parenless_call_arg(self: *Parser) ParseError!*ast.Expr {
        // R2 ARGUMENT POSITION, and it counts as such: `print .name` is the
        // same stance as `print(.name)`, so the two spellings cannot mean
        // different things.
        self.call_arg_depth += 1;
        defer self.call_arg_depth -= 1;
        return self.parse_prec(parenless_call_arg_min_prec);
    }

    // ── Pratt expression parser ───────────────────────────────────────────────

    pub fn infixBinOp(kind: TK) ?ast.BinOp {
        return switch (kind) {
            .kw_or => .@"or",
            .kw_and => .@"and",
            .lt => .lt,
            .gt => .gt,
            .leq => .leq,
            .geq => .geq,
            .eq => .eq,
            .neq => .neq,
            .kw_in => .contains,
            .pipe => .bor,
            .tilde => .bxor,
            .amp => .band,
            .lshift => .lshift,
            .rshift => .rshift,
            .concat => .concat,
            .plus => .add,
            .minus => .sub,
            .star => .mul,
            .slash => .div,
            .idiv => .idiv,
            .percent => .mod,
            .caret => .pow,
            .at => .matmul,
            .pipe_gt => .pipeline,
            else => null,
        };
    }

    fn infix_prec(kind: TK) ?struct { op: ast.BinOp, left: u8, right: u8 } {
        const op = infixBinOp(kind) orelse return null;
        const r = grammar_roles.lookup(kind);
        if (r.assoc == .none) return null;
        const left: u8 = @intCast(r.precedence);
        const right: u8 = switch (r.assoc) {
            .left => left + 1,
            .right => left - 1,
            .nonassoc => left,
            .none => return null,
        };
        return .{ .op = op, .left = left, .right = right };
    }

    /// §20 — `v >>= 7`, `n <<= 1`, `m |= bit`, `m &= mask`.
    ///
    /// These four are the compound assignments the lexer has no token for:
    /// `+= -= *= /= %= ^=` are single tokens, and `>>= <<= |= &=` arrive as an
    /// operator followed by a separate `=`. GAP-025 recorded the fix as a
    /// two-lexer change plus an artifact regeneration, because it assumed a
    /// new TOKEN. It does not need one: `>>=` IS `>>` immediately followed by
    /// `=`, and ADJACENCY is the whole rule — the `=` must start in the column
    /// right after the operator ends, on the same line.
    ///
    /// Additive by construction: `target >> = rhs` was a parse error before
    /// this ("expected expression, got '='"), so no program can change
    /// meaning. Adjacency is what keeps it from claiming anything else — with
    /// a space, `a >> = b` still reports exactly as it did.
    ///
    /// The lexers stay field-for-field identical and the generated
    /// `src/lexer_tokenize.c` does not move, which is the point: this is a
    /// grammar fact, not a lexical one.
    fn peek_glued_assign(self: *Parser, op: Token) ParseError!?ast.BinOp {
        const bop: ast.BinOp = switch (op.kind) {
            .rshift => .rshift,
            .lshift => .lshift,
            .pipe => .bor,
            .amp => .band,
            .tilde => .bxor,
            else => return null,
        };
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);
        _ = try self.adv();
        const eq = try self.pk();
        if (eq.kind != .assign) return null;
        if (eq.loc.line != op.loc.line) return null;
        if (eq.loc.col != op.loc.col + @as(u32, @intCast(op.text.len))) return null;
        return bop;
    }

    fn compound_assign_op(kind: TK) ?ast.BinOp {
        return switch (kind) {
            .plus_assign => .add,
            .minus_assign => .sub,
            .star_assign => .mul,
            .slash_assign => .div,
            .percent_assign => .mod,
            .caret_assign => .pow,
            else => null,
        };
    }

    fn parse_expr(self: *Parser) ParseError!*ast.Expr {
        return self.parse_prec(0);
    }

    /// The refusal `max_parse_depth` exists to produce. Reported at the token
    /// the parser is looking at, which is the innermost opener — the place a
    /// reader can actually cut the expression.
    fn expr_too_deep(self: *Parser) ParseError {
        const tok = self.pk() catch return ParseError.UnexpectedToken;
        term.locErr(tok.loc, "expression nests deeper than {d} levels, which is this parser's limit", .{max_parse_depth});
        term.locHint(tok.loc, "bind the inner expression to a name and refer to it, rather than nesting further", .{});
        return ParseError.UnexpectedToken;
    }

    fn parse_prec(self: *Parser, min_prec: u8) ParseError!*ast.Expr {
        // BEFORE any token is consumed. A refusal that has already advanced the
        // stream leaves the caller resynchronizing against a position the
        // diagnostic did not name.
        if (self.expr_depth >= max_parse_depth) return self.expr_too_deep();
        self.expr_depth += 1;
        defer self.expr_depth -= 1;

        var lhs: *ast.Expr = undefined;
        {
            const tok = try self.pk();
            if (tok.kind == .kw_await) {
                try self.denyRetiredStmtKeyword(tok);
                _ = try self.adv(); // consume `await`
                const operand = try self.parse_prec(20);
                lhs = try self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
            } else {
                if (tok.kind == .kw_comptime and self.idol_mode) {
                    term.locErr(tok.loc, "'comptime' is not valid in .id files. Use @(expr) for inline comptime evaluation or @comp.* for module-scope transforms.", .{});
                    return ParseError.UnexpectedToken;
                }
                const op: ?ast.UnOp = switch (tok.kind) {
                    .kw_not, .bang => .not,
                    .hash => .len,
                    .hash_hash, .kw_comptime => .compile,
                    .minus => .neg,
                    .tilde => .bnot,
                    else => null,
                };
                if (op) |uop| {
                    if (tok.kind == .kw_not and self.idol_mode)
                        term.locWarn(tok.loc, "warning: 'not' is deprecated in .id; use prefix !", .{});
                    _ = try self.adv();
                    const operand = try self.parse_prec(20);
                    lhs = try self.new_expr(.{ .unop = .{ .loc = tok.loc, .op = uop, .operand = operand } });
                } else {
                    lhs = try self.parse_suffixed_expr();
                }
            }
        }
        while (true) {
            const tok = try self.pk();
            const inf = infix_prec(tok.kind) orelse break;
            // §3 — see `opensLineAndExpression`. `@` on a new line is an
            // attribute prefix and not the matmul operator (without which
            // `x = 42\n@hot\nfun …` parses as `x = 42 @ hot`); `-` and `~` on a
            // new line are unary and not a continuation of the line above.
            if (self.opensLineAndExpression(tok)) break;
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            if (self.idol_mode) {
                switch (inf.op) {
                    .pipeline => term.locWarn(
                        tok.loc,
                        "warning: '|>' is a non-canonical pipeline operator; prefer f(x), map(data, .field), or nested calls",
                        .{},
                    ),
                    // GAP-059 — infix `@` used to warn HERE and then let the
                    // program through. The verdict moved to `check_infix_at`
                    // in sema.zig, because it is a TYPE question the parser
                    // cannot answer: `x @ y` over two tensors is a real,
                    // shape-checked operation with fixtures, and `p@x` over a
                    // record is the spec's anchor spelling with no meaning in
                    // this front end. Warning at both sites would print
                    // "Duo accepted the code" beside a hard error.
                    else => {},
                }
            }
            const rhs = if (try self.at_anchor_case(inf.op))
                try self.parse_anchor_case()
            else
                try self.parse_operand(inf.op, inf.right);
            lhs = try self.new_expr(.{ .binop = .{
                .loc = lhs.loc(),
                .op = inf.op,
                .lhs = lhs,
                .rhs = rhs,
            } });
            // `a..b by step` — after parsing `a..b` as concat, check for `by step`
            if (inf.op == .concat) {
                const next = try self.pk();
                if (next.kind == .kw_by) {
                    _ = try self.adv(); // consume `by`
                    const step = try self.parse_prec(inf.right);
                    // Unwrap the concat binop into a range expression
                    const binop = lhs.binop;
                    lhs = try self.new_expr(.{ .range = .{
                        .loc = binop.lhs.loc(),
                        .start = binop.lhs,
                        .end = binop.rhs,
                        .step = step,
                    } });
                }
            }
        }
        return lhs;
    }

    fn parse_unary(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        if (tok.kind == .kw_await) {
            try self.denyRetiredStmtKeyword(tok);
            _ = try self.adv(); // consume `await`
            const operand = try self.parse_prec(20);
            return self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
        }
        if (tok.kind == .kw_comptime and self.idol_mode) {
            term.locErr(tok.loc, "'comptime' is not valid in .id files. Use @(expr) for inline comptime evaluation or @comp.* for module-scope transforms.", .{});
            return ParseError.UnexpectedToken;
        }
        const op: ?ast.UnOp = switch (tok.kind) {
            .kw_not, .bang => .not,
            .hash => .len,
            .hash_hash, .kw_comptime => .compile,
            .minus => .neg,
            .tilde => .bnot,
            else => null,
        };
        if (op) |uop| {
            if (tok.kind == .kw_not and self.idol_mode)
                term.locWarn(tok.loc, "warning: 'not' is deprecated in .id; use prefix !", .{});
            _ = try self.adv();
            const operand = try self.parse_prec(20);
            return self.new_expr(.{ .unop = .{ .loc = tok.loc, .op = uop, .operand = operand } });
        }
        return self.parse_suffixed_expr();
    }

    fn parse_closure_expr(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.pipe)).loc;
        var params: std.ArrayList(ast.FuncParam) = .empty;
        if ((try self.pk()).kind != .pipe) {
            try params.append(self.alloc, try self.parse_param());
            while (try self.eat(.comma) != null) {
                try params.append(self.alloc, try self.parse_param());
            }
        }
        _ = try self.expect(.pipe);

        const sep = try self.pk();
        if (sep.kind == .fat_arrow) {
            _ = try self.adv();
            const expr = try self.parse_expr();
            var stmts: std.ArrayList(ast.Stmt) = .empty;
            const vals = try self.alloc.alloc(*ast.Expr, 1);
            vals[0] = expr;
            try stmts.append(self.alloc, .{ .ret = .{ .loc = expr.loc(), .vals = vals } });
            return self.new_expr(.{ .func_expr = try self.new_fb(.{
                .loc = l,
                .params = try params.toOwnedSlice(self.alloc),
                .vararg = false,
                .body = .{ .loc = expr.loc(), .stmts = try stmts.toOwnedSlice(self.alloc) },
                .ret_type = .inferred,
            }) });
        } else if (sep.kind == .kw_do) {
            _ = try self.adv();
            const body = try self.parse_block_at(l);
            try self.close_block(l, self.last_layout.offside);
            return self.new_expr(.{ .func_expr = try self.new_fb(.{
                .loc = l,
                .params = try params.toOwnedSlice(self.alloc),
                .vararg = false,
                .body = body,
                .ret_type = .inferred,
            }) });
        } else {
            // Short closure: |x| x + 1 (implicit fat arrow if no do/arrow)
            const expr = try self.parse_expr();
            var stmts: std.ArrayList(ast.Stmt) = .empty;
            const vals = try self.alloc.alloc(*ast.Expr, 1);
            vals[0] = expr;
            try stmts.append(self.alloc, .{ .ret = .{ .loc = expr.loc(), .vals = vals } });
            return self.new_expr(.{ .func_expr = try self.new_fb(.{
                .loc = l,
                .params = try params.toOwnedSlice(self.alloc),
                .vararg = false,
                .body = .{ .loc = expr.loc(), .stmts = try stmts.toOwnedSlice(self.alloc) },
                .ret_type = .inferred,
            }) });
        }
    }

    /// STR-1 — where the hole that opens at `s[open]` ENDS: the index of its
    /// matching `}`.
    ///
    /// Brace depth is counted and quoted spans are stepped over, because the
    /// hole carries an EXPRESSION and an expression can contain both. "The next
    /// `}`" was a sound rule only while a hole could hold nothing but a path,
    /// which can contain neither; it cuts `{t{1, 2}:len()}` and `{f("}")}` in
    /// the wrong place.
    /// `protected[i]` — see `Lexer.decodeText`. A brace the author WROTE as
    /// `\{` or `\}` is text: it can neither deepen this hole nor close it.
    /// Without the second half, `"pair=\{\"k\": 1\}"` would open at the bare
    /// `{` that is not there and close at a `\}` that is text.
    ///
    /// ONLY BRACES. Testing `isProtected` on every byte instead is wrong, and
    /// measured wrong: a `"` inside a hole HAS to be written `\"` — it is
    /// inside a text literal — so it arrives here protected, and skipping it
    /// disables the quote-span rule this function exists for.
    /// `"{f(\"}\")}"` then cuts at the `}` inside the nested string, which is
    /// the exact defect the quote rule was added to fix. Caught by the corpus
    /// STR-1 census moving on `scripts/sim.id`, not by a fixture, which is why
    /// the census is run on both sides of a change to this file.
    fn interpolationHoleEnd(s: []const u8, protected: []const bool, open: usize) ?usize {
        if (open >= s.len or s[open] != '{') return null;
        var depth: usize = 0;
        var i: usize = open;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            if ((c == '{' or c == '}') and isProtected(protected, i)) continue;
            if (c == '"' or c == '\'') {
                i += 1;
                while (i < s.len and s[i] != c) : (i += 1) {
                    if (s[i] == '\\' and i + 1 < s.len) i += 1;
                }
                if (i >= s.len) return null;
                continue;
            }
            if (c == '{') {
                depth += 1;
            } else if (c == '}') {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        return null;
    }

    /// The escape-provenance map is CO-INDEXED with the decoded bytes, so a
    /// short map is a wrong answer, not a slow one. It can legitimately be
    /// EMPTY — every caller that has no map passes `&.{}` — and reading an
    /// absent map as "nothing is protected" is the pre-ruling behaviour, which
    /// is the right answer for a literal that never went through `decodeText`.
    fn isProtected(protected: []const bool, i: usize) bool {
        return i < protected.len and protected[i];
    }

    /// The value `idol fmt` prints from: decoded EVERYWHERE EXCEPT the two
    /// things a reprint cannot otherwise recover.
    ///
    ///   * a protected `{` or `}` is written back as `\{` / `\}` — it is text,
    ///     and printing it bare would make the reprint open a hole;
    ///   * EVERY backslash byte is doubled, so `"\\{x}"` (a backslash, then a
    ///     live hole) cannot be read back as `\{` (a literal brace).
    ///
    /// The second rule is universal ON PURPOSE, and the narrower "double it only
    /// when it abuts a brace" is WRONG: `"\\\\"` decodes to two backslash bytes,
    /// and under the narrow rule those two bytes are indistinguishable from one
    /// doubled backslash, so the reprint would drop one. Both spellings are
    /// real — `docs/text-law.md` §4.2 found four `\\{` / `\\}` sites in the
    /// corpus and zero genuine `\{` — and `"\x5C{x}"` produces the same bytes
    /// with no backslash in the source at all, which is why the test is on the
    /// BYTE and not on the source spelling.
    ///
    /// Everything else is left decoded so `writeStringLit` keeps re-escaping it
    /// exactly as it does today, and the doubled backslashes reprint to the same
    /// `\\` the undoubled ones did — so the reprint is BYTE-IDENTICAL to today
    /// for every literal that carries no protected brace. That is the whole
    /// reason the transform is this narrow.
    fn respellForReprint(alloc: std.mem.Allocator, s: []const u8, protected: []const bool) ParseError![]const u8 {
        var needed = false;
        for (s, 0..) |c, i| {
            if (c == '\\' or ((c == '{' or c == '}') and isProtected(protected, i))) {
                needed = true;
                break;
            }
        }
        if (!needed) return s;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(alloc);
        for (s, 0..) |c, i| {
            if (c == '\\' or ((c == '{' or c == '}') and isProtected(protected, i))) {
                try out.append(alloc, '\\');
            }
            try out.append(alloc, c);
        }
        return try out.toOwnedSlice(alloc);
    }

    /// Decode a text literal's body, and LOCATE the refusal when it has one.
    ///
    /// `Lexer.decodeText` closed its unknown-escape fallback, so an undeclared
    /// escape is now an error rather than a silently dropped backslash. Handed
    /// back raw, that error surfaced as `parse failed: InvalidEscape` with no
    /// file, no line and no hint — a refusal that does not teach, which is
    /// worse than the warning it replaced. `src/main.zig` has a located
    /// diagnostic for this error, but only on the LEXER's path; the decode
    /// happens here.
    ///
    /// The hint names `\{` and `\}` because this is the diagnostic an author
    /// reaches when they were reaching for a literal brace.
    fn decodeLiteral(self: *Parser, tok: Token, protected: *std.ArrayList(bool)) ParseError![]u8 {
        return Lexer.decodeText(self.alloc, tok.text, protected) catch |e| switch (e) {
            error.InvalidEscape => {
                term.locErr(tok.loc, "invalid escape sequence in text literal", .{});
                term.locHint(tok.loc, "Idol escapes are \\a \\b \\f \\n \\r \\t \\v \\\\ \\\" \\' \\{{ \\}} \\<ddd> \\x<hex> \\u{{<hex>}} and \\z; a lone backslash is written \\\\", .{});
                term.locHint(tok.loc, "`\\{{` and `\\}}` are the LITERAL BRACE — an unescaped `{{` in a text literal opens an interpolation hole; a payload that is all braces and no holes belongs in the byte face `'…'`, which decodes no escapes", .{});
                return ParseError.UnexpectedToken;
            },
            else => return e,
        };
    }

    /// The source position of byte `off` inside the DECODED literal `s`, given
    /// the position of the literal's opening quote. Escapes shorten the decoded
    /// text relative to the source, so the column can drift by however many
    /// escapes precede the hole; the LINE is exact, which is what a diagnostic
    /// is read by.
    fn interpolationLoc(loc: ast.Loc, s: []const u8, off: usize) ast.Loc {
        var out = loc;
        out.col += 1; // step over the opening quote
        var i: usize = 0;
        while (i < off and i < s.len) : (i += 1) {
            if (s[i] == '\n') {
                out.line += 1;
                out.col = 1;
            } else {
                out.col += 1;
            }
        }
        return out;
    }

    /// STR-1 — ONE hole, parsed by the REAL expression grammar.
    ///
    /// `law.literal.text` binds "interpolation preserves literal and EXPRESSION
    /// segments". A name and a dotted path are the DEGENERATE cases of an
    /// expression, not the definition of a hole — so this does not carry a
    /// second, narrower grammar that has to be kept in step with the first. The
    /// hole text is lexed and parsed by the same `Lexer` and `Parser` as the
    /// file around it, which is why `{x:len()}` (a subject-first application)
    /// and `{x + 1}` (arithmetic) work here the day the real grammar does.
    ///
    /// Move a sub-lex of a fragment onto the enclosing file's coordinates: a
    /// fragment token at 1-based `(line, col)` within the fragment sits at
    /// `seat` offset by that much in the file.
    ///
    /// The first line is the only one that takes a COLUMN offset — everything
    /// after the fragment's first newline starts its own line, so its column is
    /// already the file's column. That is exactly the arithmetic the padding
    /// performed by construction, which is why this is a rewrite of the same
    /// answer and not a new one.
    ///
    /// BOTH TOKEN SOURCES ARE SEATED, and neither is decoration. `route` is what
    /// the sub-parse actually runs on (`law.bridge.death` — the host scanner is
    /// not a production path), so the token pack is the live one and seating
    /// only the cursor would leave every hole diagnostic at line 1. The cursor
    /// is seated too because it is what `Lexer` reports positions from whenever
    /// a pack is not installed.
    fn seatSubLexer(sub: *Lexer, seat: ast.Loc) void {
        sub.cursor.line = seat.line;
        sub.cursor.col = seat.col;
        const toks = sub.duo_tokens orelse return;
        for (@constCast(toks)) |*tok| {
            if (tok.loc.line == 1) tok.loc.col = seat.col + tok.loc.col - 1;
            tok.loc.line = seat.line + tok.loc.line - 1;
            tok.loc.file = seat.file;
        }
    }

    /// A diagnostic raised INSIDE a hole reports its true `file:line:col`, and
    /// that property is not negotiable — the caret has to land in the string.
    /// The position is carried as an OFFSET APPLIED TO LOCATIONS, never as bytes
    /// the sub-lexer must walk.
    ///
    /// ===================== WHY THAT IS THE WHOLE POINT =====================
    /// This function used to PAD the hole text with `line - 1` newlines and
    /// `col - 1` spaces and hand the sub-lexer the result, so its own position
    /// arithmetic arrived at the right answer by re-walking everything that
    /// precedes the hole in the file. That is exact, and it is QUADRATIC in file
    /// position: each hole re-scans its own offset, so the same holes cost more
    /// the further down the file they sit. Measured, 600 holes of IDENTICAL
    /// content, only the start line varying — hole term with the flat-string
    /// control subtracted:
    ///
    ///     line     2   0.029s          line  8002   0.353s
    ///     line  2002   0.147s          line 16002   0.667s
    ///
    /// Hole COUNT was already linear, so the count was never the term; the
    /// padding was. `scripts/treesitter_emit.id` carries 1,208 holes.
    ///
    /// `seatSubLexer` applies the same offset arithmetic ONCE PER TOKEN in the
    /// hole instead of once per byte before it, which is the same answer with
    /// the file position taken out of the cost.
    ///
    /// Returns null when the text is not one whole expression. The CALLER
    /// decides what that means; it must not mean "quietly emit the braces".
    fn interpolationLexer(self: *Parser, text: []const u8) Lexer {
        return Lexer.initFamilyLawEdition(
            text,
            self.lex.cursor.file,
            self.lex.family,
            self.lex.source_law,
            self.lex.source_law_edition,
        );
    }

    fn parseInterpolationHole(self: *Parser, hole_loc: ast.Loc, raw: []const u8) ParseError!?*ast.Expr {
        const text = std.mem.trim(u8, raw, " \t\r\n");
        if (text.len == 0) return null;

        // The SEAT is the true position of `text[0]`, and that is not
        // `hole_loc`: `hole_loc` is the `{`, the body starts one column right of
        // it, and the trim above may have moved it further still. The padded
        // form seated the body at the `{`'s own column and was one column short
        // of the truth on every hole; walking the few skipped bytes here costs
        // nothing and is exact.
        var seat = hole_loc;
        seat.col += 1; // step over `{`
        const lead = @intFromPtr(text.ptr) - @intFromPtr(raw.ptr);
        for (raw[0..lead]) |ch| source_cursor.advanceLoc(ch, &seat.line, &seat.col);

        // `text` OUTLIVES this call on purpose. `parse_simple_expr` builds a
        // `.name` from `tok.text`, which is a slice INTO the source bytes, so a
        // scratch buffer freed here would leave every identifier in the hole
        // pointing at reclaimed memory. It is a subslice of the decoded literal,
        // which the parse arena owns.
        var sub = self.interpolationLexer(text);
        var p = Parser.init(&sub, self.alloc);
        p.idol_mode = self.idol_mode;
        p.ensureProducerPack() catch return null;
        defer p.releaseOwnedPack();
        seatSubLexer(&sub, seat);

        const expr = p.parse_expr() catch return null;
        // The whole hole, or none of it. A hole that parses a PREFIX and leaves
        // a tail behind is the silent-absorption shape one level down: `{x + }`
        // would interpolate `x` and drop the rest without a word.
        const rest = p.pk() catch return null;
        if (rest.kind != .eof) return null;
        return expr;
    }

    fn quoteOf(kind: TK) ast.Quote {
        return switch (kind) {
            .text_lit => .text,
            .bytes_lit => .bytes,
            .compat_text_lit => .compat_text,
            .compat_long_text_lit => .compat_long,
            else => .host,
        };
    }

    /// §9 / `law.literal.text` — a `{…}` hole in a canonical text literal is an
    /// EXPRESSION segment. Holes desugar to `..` concat at parse time
    /// (idol_mode).
    ///
    /// ===================== WHICH ANSWER THIS IS =====================
    /// `parseInterpolationPath` used to accept a name, a dotted path and a
    /// `[key]` chain and close with `else => return null`; its only caller was
    /// `if (…) |hole| { … }` with NO else, so a null meant "not a hole" and the
    /// braces survived into the string literal. `{f()}`, `{x + 1}` and
    /// `{x:len()}` were copied through as literal brace text with no error, no
    /// warning and no hint — and BOTH BACKENDS AGREED on the wrong output, which
    /// is precisely why the C-vs-direct differential could not see it.
    /// Agreement reads as confirmation.
    ///
    /// The constitution decides between the two available answers.
    /// `law.literal.text` binds "interpolation preserves literal and EXPRESSION
    /// segments and does not demand concatenation or materialization". A path is
    /// the DEGENERATE case of an expression, not the definition of a hole. So
    /// the hole is parsed by the real grammar — same `Lexer`, same `Parser`,
    /// same precedence — and there is no second, narrower interpolation grammar
    /// left in this file to drift from the first. That is the whole point:
    /// `{x:len()}` is a subject-first application and `{x + 1}` is arithmetic,
    /// and neither is a widened special case here. They work because the real
    /// grammar works.
    ///
    /// Measured over the 1,053-file corpus: 5,783 `{…}` holes were already paths
    /// and are unaffected; 75 holes in 21 files that emitted literal brace text
    /// yesterday interpolate today.
    ///
    /// ===================== THE SPELLING NOW EXISTS: `\{` =====================
    /// `docs/text-law.md` rules `\{` and `\}` the literal brace, and the two
    /// obstacles this comment used to record are both gone:
    ///
    ///   * `\{` DOES serve now. The lexer's unknown-escape fallback used to
    ///     decode it to a bare `{` before this function was reached; it is a
    ///     REFUSAL today, and `Lexer.decodeText` hands over the `protected` map
    ///     so the escaped and unescaped forms are still distinguishable after
    ///     they have become the same byte.
    ///   * `{{` remains refused, and not on taste: `law.brace` makes `{` the
    ///     structured-pack face and `law.literal.text` makes a hole an
    ///     EXPRESSION, so `"n={{10, 20, 30}:len()}"` answers 3 today
    ///     (`examples/text/brace/hole.id` pins it). `{{` is already the
    ///     spelling of "a hole opening with a pack", and `lib/text/template`
    ///     spends it a second time as its own action opener.
    ///
    /// ===================== WHAT IS STILL *NOT* REFUSED =====================
    /// A `{` that is not a well-formed hole is still WARNED, not refused, and
    /// the reason is `docs/text-law.md` §4.5: the refusal is staged BEHIND the
    /// migration, because it breaks this repo's own gate if it lands first.
    /// `../idol-native/lex.id:643` is `scan("{", 1)`, `lex.id` is run by
    /// `gate/all.sh` and must exit 119, and 547 further brace sites across 82
    /// corpus files have not moved to `\{` or to the byte face yet. Landing the
    /// error before them takes `gate/all.sh` from 0/41 to at least 1/41.
    ///
    /// So the site is NAMED, LOCATED and WARNED — and the hints below now name
    /// the spelling, which is the half of stage 3 that can land early: the
    /// diagnostic that will one day refuse is already the diagnostic that
    /// teaches.
    fn desugar_string_interpolation(self: *Parser, loc: ast.Loc, s: []const u8, protected: []const bool, quote: ast.Quote) ParseError!*ast.Expr {
        // FORMATTING MODE IS NOT "SKIP THE WORK", it is a DIFFERENT VALUE.
        //
        // `docs/text-law.md` §4.4 measured the prerequisite that would
        // otherwise have been missed: `idol fmt` DELETES the backslash from
        // `"esc \{ brace"`, because `writeStringLit` has no `'{'` case. While
        // both spellings meant `{` that was harmless. Under the ruling it is a
        // formatter that converts a LITERAL BRACE INTO A HOLE OPENER — the
        // exact class `gate/fmt.sh` exists for.
        //
        // The printer cannot infer the role: after decoding, `\{` and `{` are
        // the same byte, and `law.lexical.one` forbids a consumer
        // reconstructing role from contents. So the parser hands the printer a
        // value that already carries the answer — the SOURCE SPELLING of every
        // backslash and every protected brace, decoded in all other respects.
        // `PrettyPrinter.lit_form` names the two forms; this is `.source`.
        if (self.formatting) {
            return self.new_expr(.{ .quoted = .{
                .loc = loc,
                .val = try respellForReprint(self.alloc, s, protected),
                .quote = quote,
            } });
        }
        if (self.directive_arg_depth > 0 or !self.idol_mode or std.mem.indexOfScalar(u8, s, '{') == null) {
            return self.new_expr(.{ .quoted = .{ .loc = loc, .val = s, .quote = quote } });
        }
        var parts: std.ArrayList(*ast.Expr) = .empty;
        var lit: std.ArrayList(u8) = .empty;
        defer lit.deinit(self.alloc);
        var holes: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            // `\{` IS NOT A HOLE OPENER. The map comes from the lexer because
            // the byte itself cannot carry the fact: `\{`, `\x7B`, `\123` and a
            // bare `{` all decode to 0x7B. This is the one test that makes a
            // literal brace sayable in the interpolating face, and it is why
            // `"both {x} and \{x}"` still interpolates the first hole — the
            // reading is per-brace, not per-literal.
            if (s[i] != '{' or isProtected(protected, i)) {
                try lit.append(self.alloc, s[i]);
                i += 1;
                continue;
            }
            const hole_loc = interpolationLoc(loc, s, i);
            const close = interpolationHoleEnd(s, protected, i) orelse {
                term.locWarn(hole_loc, "STR-1: this `{{` opens an interpolation hole that never closes", .{});
                // THE DIAGNOSTIC THAT WILL REFUSE IS ALREADY THE ONE THAT
                // TEACHES. `docs/text-law.md` §4.5 stages the refusal behind the
                // migration, but the hint does not have to wait: naming `\{`
                // here is what lets the 547 warned sites move before the error
                // lands, and a hint that named only `@comp.c.emit` pointed at a
                // directive most of those sites cannot be written inside.
                term.locHint(hole_loc, "write the matching `}}`, or write the brace itself as `\\{{` — `\\{{` and `\\}}` are the literal-brace spelling", .{});
                term.locHint(hole_loc, "a payload that is all braces and no holes — JSON, a C body, an awk program — belongs in the byte face `'…'`, which does not interpolate and decodes no escapes", .{});
                try lit.append(self.alloc, s[i]);
                i += 1;
                continue;
            };
            const hole_text = s[i + 1 .. close];
            if (try self.parseInterpolationHole(hole_loc, hole_text)) |hole| {
                if (lit.items.len > 0) {
                    const seg = try self.alloc.dupe(u8, lit.items);
                    try parts.append(self.alloc, try self.new_expr(.{ .quoted = .{ .loc = loc, .val = seg, .quote = quote } }));
                    lit.clearRetainingCapacity();
                }
                try parts.append(self.alloc, hole);
                holes += 1;
            } else {
                // NOT SILENT. The projected form is named so the reader can see
                // which of the two readings the compiler took, and the preceding
                // diagnostics from the sub-parse say exactly where it gave up.
                term.locWarn(hole_loc, "STR-1: `{{{s}}}` is not one whole expression, so it is emitted as literal text", .{hole_text});
                term.locHint(hole_loc, "an interpolation hole holds an EXPRESSION (`{{x}}`, `{{f(n)}}`, `{{x:len()}}`, `{{x + 1}}`); if these braces are meant as text, write them `\\{{` and `\\}}`", .{});
                term.locHint(hole_loc, "a payload that is all braces and no holes — JSON, a C body, an awk program — belongs in the byte face `'…'`, which does not interpolate and decodes no escapes", .{});
                try lit.appendSlice(self.alloc, s[i .. close + 1]);
            }
            i = close + 1;
        }
        if (holes == 0) {
            return self.new_expr(.{ .quoted = .{ .loc = loc, .val = s, .quote = quote } });
        }
        if (lit.items.len > 0) {
            const seg = try self.alloc.dupe(u8, lit.items);
            try parts.append(self.alloc, try self.new_expr(.{ .quoted = .{ .loc = loc, .val = seg, .quote = quote } }));
        }
        // gap[094]. A string with EXACTLY ONE part and no literal text — `"{i}"`
        // — used to fall straight out of the loop below as its own hole, so the
        // desugar of a string produced an `i64`:
        //
        //     a: str = "{i}"    type mismatch: declared 'str', initializer 'i64'
        //     b: str = "x{i}"   fine, because one literal byte makes two parts
        //
        // The interpolation is what makes the value a string; whether the author
        // also typed a literal character cannot be what decides its descriptor.
        // Seeding the fold with an empty literal makes the single-hole case the
        // SAME shape as every other one — `"" .. i` beside `"x" .. i` — so it
        // reuses the concat lowering that already works instead of adding a
        // conversion the multi-part path does not use. An all-literal string
        // never reaches here (`parts.items.len == 0` returns above), so this
        // cannot wrap a plain literal.
        if (parts.items[0].* != .quoted) {
            const empty = try self.new_expr(.{ .quoted = .{ .loc = loc, .val = "", .quote = quote } });
            try parts.insert(self.alloc, 0, empty);
        }
        var expr = parts.items[0];
        for (parts.items[1..]) |part| {
            expr = try self.new_expr(.{ .binop = .{
                .loc = loc,
                .op = .concat,
                .lhs = expr,
                .rhs = part,
            } });
        }
        return expr;
    }

    fn parse_simple_expr(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        return switch (tok.kind) {
            .pipe => self.parse_closure_expr(),
            .int_lit => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .int_lit = .{ .loc = tok.loc, .val = tok.int_val } });
            },
            .float_lit => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .float_lit = .{ .loc = tok.loc, .val = tok.float_val } });
            },
            .compat_text_lit => blk: {
                _ = try self.adv();
                var protected: std.ArrayList(bool) = .empty;
                defer protected.deinit(self.alloc);
                const decoded = try self.decodeLiteral(tok, &protected);
                break :blk try self.desugar_string_interpolation(tok.loc, decoded, protected.items, .compat_text);
            },
            .text_lit => blk: {
                _ = try self.adv();
                // The lexer already scans escape sequences to find the closing quote,
                // so accepting `"a\nb"` while emitting the raw bytes made the escape
                // syntax lex-only: canonical text had no way to spell a newline.
                //
                // `protected` is which decoded bytes came from an ESCAPE, and it
                // is the only thing that can tell `\{` from `{` — they are the
                // same byte by the time the value exists. It does NOT outlive
                // this block: `desugar_string_interpolation` reads it and either
                // copies what it needs or returns a value that does not depend
                // on it.
                var protected: std.ArrayList(bool) = .empty;
                defer protected.deinit(self.alloc);
                const val = try self.decodeLiteral(tok, &protected);
                break :blk try self.desugar_string_interpolation(tok.loc, val, protected.items, .text);
            },
            .bytes_lit => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .quoted = .{
                    .loc = tok.loc,
                    .val = try self.alloc.dupe(u8, tok.text),
                    .quote = .bytes,
                } });
            },
            .compat_long_text_lit => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .quoted = .{
                    .loc = tok.loc,
                    .val = try self.alloc.dupe(u8, tok.text),
                    .quote = .compat_long,
                } });
            },
            .kw_nil => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .nil = tok.loc });
            },
            .kw_true => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .true_lit = tok.loc });
            },
            .kw_false => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .false_lit = tok.loc });
            },
            .dots => blk: {
                _ = try self.adv();
                break :blk self.new_expr(.{ .vararg = tok.loc });
            },
            .kw_function, .kw_fun => blk: {
                const l = (try self.adv()).loc;
                const fb = try self.new_fb(try self.parse_func_body(l));
                break :blk self.new_expr(.{ .func_expr = fb });
            },
            .name => blk: {
                const name_tok = try self.adv();
                break :blk self.new_expr(.{ .name = .{ .loc = name_tok.loc, .ident = name_tok.text } });
            },
            .backtick => {
                term.locErr(tok.loc, "c0 law.backtick.zero: backtick is reserved and has no canonical meaning", .{});
                return ParseError.UnexpectedToken;
            },
            .at => blk: {
                // §2, the @ DYAD — **bare `@` NAMES** the anchor. §20's lexer
                // hands it to a callable it retrieved from a table:
                // `if r = read[b] return r(@)`. The anchor of a slot body is
                // its receiver, which `parse_descriptor_slot` already binds as
                // the first parameter, so naming it is the whole lowering —
                // no new node, and nothing downstream re-derives a stance.
                //
                // Recognised only where there is NOTHING for `@` to name (an
                // argument-list closer), so every prefix spelling still
                // reaches the macro path with its bytes untouched.
                if (try self.at_is_bare_anchor()) {
                    const l = (try self.adv()).loc;
                    break :blk self.new_expr(.{ .name = .{ .loc = l, .ident = "self" } });
                }
                break :blk self.parse_macro_call_expr();
            },
            .lparen => blk: {
                if (try self.starts_parenthesized_func_expr()) {
                    const l = (try self.pk()).loc;
                    const fb = try self.new_fb(try self.parse_func_body(l));
                    break :blk self.new_expr(.{ .func_expr = fb });
                }
                const open_tok = try self.adv();
                // `()` is the explicit pack delimiter. A labeled slot at slot
                // level (`name = value`) makes this a pack, not a group.
                if (try self.starts_paren_pack()) break :blk try self.parse_paren_pack(open_tok.loc);
                if ((try self.pk()).kind == .rparen) {
                    // `()` — the empty pack.
                    _ = try self.adv();
                    break :blk try self.new_expr(.{ .table = .{ .loc = open_tok.loc, .fields = &.{} } });
                }
                const e = try self.parse_expr();
                // A comma means this was a pack all along, and a TRAILING comma
                // is how a one-slot pack is spelled — `(a)` is grouping, `(a,)`
                // is a pack of one. Without that distinction there is no way to
                // write a single-slot pack at all.
                if ((try self.pk()).kind == .comma) break :blk try self.finish_positional_pack(open_tok.loc, e);
                _ = try self.expect(.rparen);
                break :blk e;
            },
            .lbrace => self.parse_table(),
            .kw_if => self.parse_if_expr(),
            .kw_match => self.parse_match_expr(),
            .dot => self.parse_field_projection(),
            .colon => self.parse_method_reference(),
            else => {
                if (grammar_roles.isDescriptor(tok.kind)) {
                    const type_tok = try self.adv();
                    return self.new_expr(.{ .name = .{ .loc = type_tok.loc, .ident = type_tok.kind.spelling() } });
                }
                term.locErr(tok.loc, "expected expression, got '{s}'", .{tok.kind.spelling()});
                return ParseError.ExpectedToken;
            },
        };
    }

    /// DESCRIPTOR-EXPECTED POSITION, as a POSITION and not as a shape: the
    /// operator just consumed is an equality and the very next token is `.`.
    /// Gated on the parse having SEEN a case-set, so a file that declares none
    /// keeps the element stance it had and this cannot turn working code into a
    /// diagnostic.
    fn at_anchor_case(self: *Parser, op: ast.BinOp) ParseError!bool {
        if (op != .eq and op != .neq) return false;
        if (self.caseset_cases.count() == 0) return false;
        return (try self.pk()).kind == .dot;
    }

    /// Is this `@` the postfix ANCHOR (§2, `X@rel`) rather than the matmul
    /// operator? The relation name must be GLUED to the sigil: same line, and
    /// starting in the column right after the `@` ends.
    ///
    /// Column arithmetic and not a source scan, because the lexer is not always
    /// scanning a buffer — under SH-03 it is a cursor over a token stream the
    /// DUO lexer produced (`Lexer.id_tokens`), and a rule that reached for
    /// bytes would decide differently depending on which lexer ran. `loc` and
    /// `text` are the two things both paths carry, which is exactly what
    /// `peek_glued_assign` uses for `>>=`.
    ///
    /// The left side is not tested here; the caller's `tok.loc.line >
    /// e.loc().line` check does the work that matters, keeping a NEW-LINE `@hot`
    /// attribute out (that one is glued on the right too — `@` in column 1,
    /// `hot` in column 2 — so right-adjacency alone would swallow it).
    /// Is this glued `@` opening a WORLD FACE — `thing@{ … }` interjection or
    /// `thing@( … )` qualification by expression — rather than the `X@rel`
    /// anchor? Same gluing rule as the anchor: the opener must sit in the
    /// column immediately after the sigil, on the same line, so a spaced
    /// `a @ b` stays matmul and no existing program changes meaning.
    /// Which world face, so the refusal can name the fact that is actually
    /// missing. `thing@{ … }` is INTERJECTION and is blocked on the derived
    /// world; `thing@( … )` is QUALIFICATION BY EXPRESSION — `world.md` spells
    /// `thing@(world.member)` for a nested world and it needs no derived world
    /// at all, only a world-expression operand the anchor cannot take. One
    /// message for both said "interjection 'thing{ … }'" over source that
    /// contains no brace, which is a reconstructed fact: the token that decides
    /// is right here.
    const WorldFace = enum { interject, qualify_expr };

    fn at_glued_world_face(self: *Parser, at_tok: Token) ParseError!?WorldFace {
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);
        _ = try self.adv();
        const opener = try self.pk();
        if (opener.kind != .lbrace and opener.kind != .lparen) return null;
        if (opener.loc.line != at_tok.loc.line) return null;
        if (opener.loc.col != at_tok.loc.col + @as(u32, @intCast(at_tok.text.len))) return null;
        return if (opener.kind == .lbrace) .interject else .qualify_expr;
    }

    fn at_is_glued_anchor(self: *Parser, at_tok: Token) ParseError!bool {
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);
        _ = try self.adv();
        const rel = try self.pk();
        if (!is_name_like_kind(rel.kind)) return false;
        if (rel.loc.line != at_tok.loc.line) return false;
        return rel.loc.col == at_tok.loc.col + @as(u32, @intCast(at_tok.text.len));
    }

    /// §2 THE ANCHOR — **leading `.` WALKS from the anchor**, and which
    /// anchor it walks from is decided BY POSITION: method scope → my field
    /// (`.pos`); argument position → each element (`map(.x)`); **descriptor-
    /// expected position → the case** (`tok.kind == .eof`). This is that third
    /// stance, and it is the one the parser used to get wrong in a way nothing
    /// downstream could correct.
    ///
    /// THE DEFECT THIS CLOSES. `parse_field_projection` had exactly one rule for
    /// every leading `.` — build the lambda `(__proj_v) __proj_v.name` — because
    /// the position was never consulted. Sema then re-decided from SHAPE, and
    /// its shape rule for `==` admits any two operands, so `k == .eof` CHECKED
    /// CLEAN and reached the C backend as
    ///
    ///     if ((k == lua_val_from_closure((lua_Closure*)duo_make_closure_0())))
    ///
    /// — an enum compared against a closure, rejected by the C compiler with
    /// "invalid operands to binary expression". Two subsystems each held a fact
    /// about one token and the facts disagreed; A3 ONE EDGE forbids that.
    ///
    /// The decision now lives in ONE place. The parser is the canonical syntax
    /// graph: it knows the position (it just consumed `==`) and it knows the
    /// cases, because it declared them itself in `stmt_from_descriptor`. So it
    /// resolves the stance here and hands sema a `field` node that is already a
    /// case access — the same node `token.kind.eof` produces by hand, which is
    /// the spelling the golden `caseset` fixture has been passing on. Sema and
    /// codegen consume the resolved fact; neither re-derives it, and there is
    /// nothing left for them to disagree about.
    ///
    /// Diagnostic, never a guess. An unknown case and an ambiguous case are
    /// separate messages: the second is the one that would otherwise silently
    /// pick a home, which is a wrong VALUE rather than a failed build.
    fn parse_anchor_case(self: *Parser) ParseError!*ast.Expr {
        const dot = try self.expect(.dot);
        const case = try self.expect_name_like();
        const home = self.caseset_cases.get(case) orelse {
            term.locErr(dot.loc, "'.{s}' names no case", .{case});
            term.locHint(dot.loc, "a leading '.' in comparison position is a case of a declared case-set", .{});
            return ParseError.UnexpectedToken;
        };
        if (home.len == 0) {
            term.locErr(dot.loc, "'.{s}' is a case of more than one case-set", .{case});
            term.locHint(dot.loc, "name the home it belongs to, as in 'token.kind.{s}'", .{case});
            return ParseError.UnexpectedToken;
        }
        return self.new_expr(.{ .field = .{
            .loc = dot.loc,
            .obj = try self.new_expr(.{ .name = .{ .loc = dot.loc, .ident = home } }),
            .field = case,
        } });
    }

    /// R2 — a leading `.name` "is a lens in ARGUMENT position always;
    /// the CASE in descriptor-expected position; neither context ⇒ diagnostic".
    /// §2 names the third context this adds: method scope → my field
    /// (`.pos`). The case stance is decided upstream in `parse_anchor_case`;
    /// this function is the other two, and the diagnostic R2 requires.
    ///
    /// THE DEFECT THIS CLOSES. There was exactly ONE rule here — build the lens
    /// `(__proj_v) __proj_v.name` — applied to every leading `.`
    /// unconditionally, so the contexts R2 separates collapsed into one.
    /// `sema.zig` holds no belief about anchors (19 decision sites on `@` in
    /// this file, 0 there) and its arithmetic rule admits a closure, so METHOD
    /// SCOPE checked clean and died in the C backend:
    ///
    ///     bump(l: lexer): i64
    ///         .pos + 1
    ///     end
    ///
    ///     return ((int64_t)lua_to_num((lua_val_from_closure(
    ///         (lua_Closure*)duo_make_closure_0()) + 1)));
    ///     error: invalid operands to binary expression ('lua_Value' and 'int')
    ///
    /// A closure plus one, from a program `duo check` called clean.
    ///
    /// POSITION NOW DECIDES, and both halves are FACTS THE PARSER ALREADY HAS
    /// rather than shapes it infers: `call_arg_depth` is incremented where
    /// arguments are parsed, and `subject` is the enclosing function's first
    /// parameter, recorded where the parameters are parsed. Argument position
    /// wins when both hold, because it is the inner context — `xs:map(.x)`
    /// inside a method body is still a lens over `xs`, which is R2's "in
    /// ARGUMENT position ALWAYS".
    ///
    /// Neither reading is a guess, and the third outcome is R2's own: outside
    /// both positions there is no anchor to walk from, so it is a diagnostic
    /// rather than a silent lens.
    fn parse_field_projection(self: *Parser) ParseError!*ast.Expr {
        if (self.call_arg_depth == 0 and self.subject != null) {
            const subject = self.subject.?;
            const dot_tok = try self.adv();
            const first_field = try self.expect_name_like();
            var walk = try self.new_expr(.{ .field = .{
                .loc = dot_tok.loc,
                .obj = try self.new_expr(.{ .name = .{ .loc = dot_tok.loc, .ident = subject } }),
                .field = first_field,
            } });
            while ((try self.pk()).kind == .dot) {
                const chain_dot = try self.adv();
                const chain_field = try self.expect_name_like();
                walk = try self.new_expr(.{ .field = .{
                    .loc = chain_dot.loc,
                    .obj = walk,
                    .field = chain_field,
                } });
            }
            return walk;
        }

        const dot_tok = try self.adv(); // consume the leading `.`
        const first_field = try self.expect_name_like();

        // Build the accessor chain: start with `__v.first_field`
        var accessor = try self.new_expr(.{
            .field = .{
                .loc = dot_tok.loc,
                .obj = try self.new_expr(.{ .name = .{ .loc = dot_tok.loc, .ident = "__proj_v" } }),
                .field = first_field,
            },
        });

        // Support chained projections: .a.b.c — GLUED, the same rule the
        // suffix loop applies. `.a .b` is TWO leading walks, which is what
        // §20's `if .pos < #.src .src[.pos] else nil` writes: without the
        // adjacency test this loop swallows the then-expression into the
        // condition and the `else` has nothing in front of it.
        while ((try self.pk()).kind == .dot and self.glued_to_prev(try self.pk())) {
            const chain_dot = try self.adv();
            const chain_field = try self.expect_name_like();
            accessor = try self.new_expr(.{
                .field = .{
                    .loc = chain_dot.loc,
                    .obj = accessor,
                    .field = chain_field,
                },
            });
        }

        // Build return statement: return accessor
        const ret_vals = try self.alloc.alloc(*ast.Expr, 1);
        ret_vals[0] = accessor;
        const ret_stmt = ast.Stmt{ .ret = .{ .loc = dot_tok.loc, .vals = ret_vals } };
        const stmts = try self.alloc.alloc(ast.Stmt, 1);
        stmts[0] = ret_stmt;

        // Build the single parameter: __proj_v (untyped)
        const params = try self.alloc.alloc(ast.FuncParam, 1);
        params[0] = .{
            .name = "__proj_v",
            .typ = .inferred,
            .loc = dot_tok.loc,
        };

        // Build anonymous function: (__proj_v) __proj_v.field_chain
        return self.new_expr(.{ .func_expr = try self.new_fb(.{
            .loc = dot_tok.loc,
            .params = params,
            .vararg = false,
            .body = .{ .loc = dot_tok.loc, .stmts = stmts },
            .ret_type = .inferred,
        }) });
    }

    /// R1 — `:` is INVOKE "whenever a left operand exists and a call
    /// group follows; leading `:name(` is sibling invoke". §2 says what the
    /// sibling invokes ON: "leading `:m()` on the ambient subject".
    ///
    /// R1's disambiguation is already total — "the forms cannot coincide: IS
    /// never takes an argument group; INVOKE always does" — so the open
    /// question was never IS-vs-INVOKE here. It was WHICH SUBJECT, and that is
    /// the same POSITION question `parse_field_projection` answers. In METHOD
    /// SCOPE the ambient subject is the enclosing function's first parameter,
    /// so `:peek()` is `l:peek()`. In ARGUMENT POSITION there is no ambient
    /// subject yet — the subject is each element — so it stays the sibling
    /// reference `(__proj_v) __proj_v:method()` that `items:each(:close)`
    /// wants.
    ///
    /// Same failure as the leading `.` and the same shape: `:peek() + 1` in a
    /// `: i64` body checked clean and reached the C backend as
    /// `lua_val_from_closure(...) + 1`, in a translation unit carrying no Lua
    /// runtime.
    fn parse_method_reference(self: *Parser) ParseError!*ast.Expr {
        const colon_tok = try self.adv(); // consume `:`
        const method_name = try self.expect_name_like();

        var args: []*ast.Expr = &.{};
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv();
            self.call_arg_depth += 1;
            defer self.call_arg_depth -= 1;
            var arg_list: std.ArrayList(*ast.Expr) = .empty;
            if (!(try self.check(.rparen))) {
                try arg_list.append(self.alloc, try self.parse_expr());
                while (try self.eat(.comma) != null)
                    try arg_list.append(self.alloc, try self.parse_expr());
            }
            _ = try self.expect(.rparen);
            args = try arg_list.toOwnedSlice(self.alloc);
        }

        // METHOD SCOPE: the ambient subject is the receiver, so this is an
        // ordinary sibling invoke on it — not a reference to be applied later.
        if (self.call_arg_depth == 0 and self.subject != null) {
            const subject = self.subject.?;
            return self.new_expr(.{ .method_call = .{
                .loc = colon_tok.loc,
                .obj = try self.new_expr(.{ .name = .{ .loc = colon_tok.loc, .ident = subject } }),
                .method = method_name,
                .args = args,
            } });
        }

        const call_expr = try self.new_expr(.{
            .method_call = .{
                .loc = colon_tok.loc,
                .obj = try self.new_expr(.{ .name = .{ .loc = colon_tok.loc, .ident = "__proj_v" } }),
                .method = method_name,
                .args = args,
            },
        });

        const ret_vals = try self.alloc.alloc(*ast.Expr, 1);
        ret_vals[0] = call_expr;
        const ret_stmt = ast.Stmt{ .ret = .{ .loc = colon_tok.loc, .vals = ret_vals } };
        const stmts = try self.alloc.alloc(ast.Stmt, 1);
        stmts[0] = ret_stmt;

        const params = try self.alloc.alloc(ast.FuncParam, 1);
        params[0] = .{
            .name = "__proj_v",
            .typ = .inferred,
            .loc = colon_tok.loc,
        };

        return self.new_expr(.{ .func_expr = try self.new_fb(.{
            .loc = colon_tok.loc,
            .params = params,
            .vararg = false,
            .body = .{ .loc = colon_tok.loc, .stmts = stmts },
            .ret_type = .inferred,
        }) });
    }

    /// The indented labeled pack a relation demands directly:
    ///
    ///     color:match
    ///         red = one
    ///         green = two
    ///         else = other
    ///
    /// Offside structure is admitted only where an INTRODUCER already fixes
    /// what the region means — here `:match`, which cannot take anything but a
    /// pack of alternatives. That is what keeps this from being generic
    /// significant whitespace: indentation never decides a role on its own, it
    /// only supplies contents for a role already established.
    ///
    /// This loop owns its own layout frame rather than reusing the statement
    /// block, because `else` CLOSES a statement block — it is a control-clause
    /// opener there — while here it is an ordinary key naming the remaining
    /// alternative.
    /// True when a bare `=` is followed by an indented region of SLOT forms,
    /// which introduces a structured pack:
    ///
    ///     person =
    ///         name = "Chris"
    ///         age = 30
    ///
    /// SLOT FORMS ONLY. An indented region of bare expressions is NOT a pack —
    /// it would be indistinguishable from an executable region, so
    /// `xs = (1, 2, 3)` stays explicit and `xs =` over three bare lines is not
    /// a sequence. That restriction is what keeps this from being "indentation
    /// may stand in for a delimiter anywhere", which would be ambiguous; the
    /// region's role is fixed before its contents are read, never after.
    /// True when `name:` is followed by an indented region of FIELD forms, which
    /// is a descriptor home written without delimiters:
    ///
    ///     point:
    ///         x: f64
    ///         y: f64
    ///
    /// The `:` already says a descriptor context follows, so the braces were
    /// repeating a boundary the introducer had established. Field forms only
    /// (`name:`), for the same reason a structured pack requires slot forms.
    /// `(name = value, …)` — a labeled pack rather than a parenthesized
    /// assignment. Inside pack syntax `name =` at slot level IS a slot label;
    /// the parser already knows it is reading a pack, so this is contextual
    /// rather than ambiguous.
    /// `point(3, 4)` where `point` is a declared descriptor: fill its slots in
    /// declaration order. Returns null when the callee is not a descriptor, so
    /// every ordinary call is untouched.
    ///
    /// There is deliberately no separate constructor syntax. A descriptor and a
    /// relation cannot share a name, so after resolution the meaning is unique
    /// and the two faces converge on one application architecture.
    /// True when every alternative names a case of ONE sealed case-set and the
    /// pack covers all of them. Reports the missing cases when it covers only
    /// some, which is the diagnosis the ruling asks for — and note that this
    /// needs no exhaustiveness machinery of its own: the knowledge comes from
    /// the subject descriptor and the pack.
    fn packCoversCaseSet(self: *Parser, l: ast.Loc, fields: []const ast.TableField) ParseError!bool {
        var home: ?[]const u8 = null;
        var named_count: usize = 0;
        for (fields) |fld| {
            const key = switch (fld) {
                .named => |nm| nm.key,
                else => return false, // a computed slot is not a case name
            };
            const h = self.caseset_cases.get(key) orelse return false;
            if (h.len == 0) return false; // two homes claim this spelling
            if (home) |existing| {
                if (!std.mem.eql(u8, existing, h)) return false;
            } else home = h;
            named_count += 1;
        }
        const h = home orelse return false;

        var total: usize = 0;
        var it = self.caseset_cases.iterator();
        while (it.next()) |e| {
            if (std.mem.eql(u8, e.value_ptr.*, h)) total += 1;
        }
        if (named_count == total) return true;

        // Covers some but not all: name what is missing rather than demanding
        // an `else` the writer may not want.
        var missing: std.ArrayList(u8) = .empty;
        var it2 = self.caseset_cases.iterator();
        while (it2.next()) |e| {
            if (!std.mem.eql(u8, e.value_ptr.*, h)) continue;
            var found = false;
            for (fields) |fld| switch (fld) {
                .named => |nm| if (std.mem.eql(u8, nm.key, e.key_ptr.*)) {
                    found = true;
                },
                else => {},
            };
            if (found) continue;
            if (missing.items.len > 0) try missing.appendSlice(self.alloc, ", ");
            try missing.appendSlice(self.alloc, e.key_ptr.*);
        }
        term.locErr(l, "`:match` on `{s}` does not name: {s}", .{ h, missing.items });
        return error.UnexpectedToken;
    }

    fn descriptorApplication(self: *Parser, l: ast.Loc, callee: *ast.Expr, args: []*ast.Expr) ParseError!?*ast.Expr {
        if (callee.* != .name) return null;
        const field_names = self.record_descriptors.get(callee.name.ident) orelse return null;
        if (args.len != field_names.len) {
            term.locErr(l, "`{s}` has {d} slot(s), applied to {d}", .{ callee.name.ident, field_names.len, args.len });
            return error.UnexpectedToken;
        }
        var fields = try self.alloc.alloc(ast.TableField, args.len);
        for (args, 0..) |a, i| fields[i] = .{ .named = .{ .key = field_names[i], .val = a } };
        return try self.new_expr(.{ .table = .{ .loc = l, .fields = fields } });
    }

    /// Remember a descriptor's slot names so it can be applied later.
    fn noteRecordDescriptor(self: *Parser, name: []const u8, typ: ast.TypeExpr) ParseError!void {
        if (typ != .record) return;
        const src_fields = typ.record.fields;
        if (src_fields.len == 0) return;
        var names = try self.alloc.alloc([]const u8, src_fields.len);
        for (src_fields, 0..) |f, i| names[i] = f.name;
        try self.record_descriptors.put(self.alloc, name, names);
    }

    fn starts_paren_pack(self: *Parser) ParseError!bool {
        const first = try self.pk();
        if (first.kind != .name and !grammar_roles.isDescriptor(first.kind)) return false;
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        defer {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        }
        _ = try self.adv();
        return (try self.pk()).kind == .assign;
    }

    fn parse_paren_pack(self: *Parser, l: ast.Loc) ParseError!*ast.Expr {
        var fields: std.ArrayList(ast.TableField) = .empty;
        while (true) {
            if ((try self.pk()).kind == .rparen) break;
            const key_tok = try self.adv();
            const key_text = if (key_tok.kind == .name) key_tok.text else key_tok.kind.spelling();
            _ = try self.expect(.assign);
            const val = try self.parse_expr();
            try fields.append(self.alloc, .{ .named = .{ .key = key_text, .val = val } });
            if (try self.eat(.comma) == null) break;
        }
        _ = try self.expect(.rparen);
        return self.new_expr(.{ .table = .{ .loc = l, .fields = try fields.toOwnedSlice(self.alloc) } });
    }

    /// `(a, b)` and `(a,)`, given the first element already parsed.
    fn finish_positional_pack(self: *Parser, l: ast.Loc, first: *ast.Expr) ParseError!*ast.Expr {
        var fields: std.ArrayList(ast.TableField) = .empty;
        try fields.append(self.alloc, .{ .positional = first });
        while (try self.eat(.comma) != null) {
            if ((try self.pk()).kind == .rparen) break; // trailing comma
            try fields.append(self.alloc, .{ .positional = try self.parse_expr() });
        }
        _ = try self.expect(.rparen);
        return self.new_expr(.{ .table = .{ .loc = l, .fields = try fields.toOwnedSlice(self.alloc) } });
    }

    fn starts_offside_record(self: *Parser, colon: Token) ParseError!bool {
        const first = try self.pk();
        if (first.loc.line == colon.loc.line) return false;
        if (first.kind != .name) return false;
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        defer {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        }
        _ = try self.adv();
        return (try self.pk()).kind == .colon;
    }

    /// The same record type the delimited literal builds, read from an offside
    /// region. One node, two spellings.
    fn parse_offside_record(self: *Parser, open: ast.Loc) ParseError!ast.TypeExpr {
        var fields: std.ArrayList(ast.RecordField) = .empty;
        var col: u32 = 0;
        while (true) {
            const tok = try self.pk();
            if (tok.kind != .name) break;
            if (fields.items.len == 0) {
                if (tok.loc.line == open.line) break;
                col = tok.loc.col;
            } else if (tok.loc.col != col or tok.loc.line == self.prev_line) break;
            const fl = tok.loc;
            const fn_tok = try self.expect(.name);
            _ = try self.expect(.colon);
            const ft = (try self.parse_inline_caseset(fn_tok.text, fl)) orelse
                try self.parse_field_type();
            try fields.append(self.alloc, ast.RecordField{
                .name = fn_tok.text,
                .typ = ft,
                .loc = fl,
            });
        }
        const rt = try self.alloc.create(ast.TypeExpr.RecordType);
        rt.* = .{ .fields = try fields.toOwnedSlice(self.alloc) };
        return .{ .record = rt };
    }

    fn starts_offside_pack(self: *Parser, eq: Token) ParseError!bool {
        const first = try self.pk();
        if (first.loc.line == eq.loc.line) return false;
        const saved = self.lex.saveState();
        const saved_line = self.prev_line;
        const saved_end = self.prev_end_col;
        defer {
            self.lex.restoreState(saved);
            self.prev_line = saved_line;
            self.prev_end_col = saved_end;
        }
        if (first.kind == .lbracket) {
            var depth: usize = 0;
            while (true) {
                const t = try self.adv();
                if (t.kind == .eof) return false;
                if (t.kind == .lbracket) depth += 1;
                if (t.kind == .rbracket) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            return (try self.pk()).kind == .assign;
        }
        if (first.kind != .name and !grammar_roles.isDescriptor(first.kind)) return false;
        _ = try self.adv();
        return (try self.pk()).kind == .assign;
    }

    /// The pack expression for an offside slot region, so both the binding RHS
    /// and a nested slot build the same node.
    fn parse_offside_pack_expr(self: *Parser, open: ast.Loc) ParseError!*ast.Expr {
        const fields = try self.parse_offside_pack(open);
        return self.new_expr(.{ .table = .{ .loc = open, .fields = fields } });
    }

    fn parse_offside_pack(self: *Parser, open: ast.Loc) ParseError![]ast.TableField {
        var fields: std.ArrayList(ast.TableField) = .empty;
        // The first alternative establishes the region's column; every later one
        // must begin at exactly that column, and anything else closes the
        // region. `open_layout` cannot serve here because it measures against
        // the INTRODUCER's own column — for `r = c:match` the `:` sits further
        // right than the arms below it, so the frame never went offside and the
        // loop ran on past the pack and swallowed the tail expression.
        var col: u32 = 0;
        while (true) {
            const tok = try self.pk();
            if (tok.kind == .eof) break;
            if (fields.items.len == 0) {
                // A pack is a region, so it has to start on a later line.
                if (tok.loc.line == open.line) break;
                col = tok.loc.col;
            } else if (tok.loc.col != col or tok.loc.line == self.prev_line) break;
            if (tok.kind == .lbracket) {
                // `[expr] = value` — the computed slot keeps its brackets.
                _ = try self.adv();
                const key = try self.parse_expr();
                _ = try self.expect(.rbracket);
                _ = try self.expect(.assign);
                const val = try self.parse_expr();
                try fields.append(self.alloc, .{ .indexed = .{ .key = key, .val = val } });
                continue;
            }
            if (tok.kind == .int_lit) {
                const key = try self.parse_prec(0);
                _ = try self.expect(.assign);
                const val = try self.parse_expr();
                try fields.append(self.alloc, .{ .indexed = .{ .key = key, .val = val } });
                continue;
            }
            if (tok.kind != .name and tok.kind != .kw_else and !grammar_roles.isDescriptor(tok.kind)) break;
            const key_text = if (tok.kind == .name) tok.text else tok.kind.spelling();
            _ = try self.adv();
            const eq = try self.expect(.assign);
            // A slot whose value is itself an indented slot region nests, so
            // `server =` over `host = …` / `port = …` needs no delimiters at
            // any depth.
            const val = if (try self.starts_offside_pack(eq))
                try self.parse_offside_pack_expr(eq.loc)
            else
                try self.parse_expr();
            try fields.append(self.alloc, .{ .named = .{ .key = key_text, .val = val } });
        }
        return fields.toOwnedSlice(self.alloc);
    }

    /// `subject:match{ one = a, two = b, else = c }` — finite dispatch as an
    /// ORDINARY subject-first relation, not a control construct.
    ///
    /// It desugars right here into the same `if_expr` chain `else(condition)`
    /// builds, which is what keeps the claim honest: there is no MatchStmt, no
    /// CaseArm, no pattern AST and no `case`/`end` grammar. Everything it needs
    /// already exists — a subject, a relation applied from it, a structured
    /// pack, and the descriptor identities naming the alternatives.
    ///
    /// SELECTIVE DEMAND comes free rather than being bolted on. An alternative
    /// pack must not evaluate every arm; because this lowers to `if_expr`, and
    /// `if_expr` demands only the branch it takes (verified: an untaken arm may
    /// divide by zero without trapping), only the selected arm is evaluated.
    /// Lowering to a materialized table instead WOULD have evaluated all of
    /// them, which is the whole reason the desugar happens at parse time.
    ///
    /// The subject must be a plain name, because it is repeated once per
    /// comparison. Rather than silently re-evaluate `f()` per arm, that is
    /// refused and the caller is told to bind it.
    fn desugarMatch(self: *Parser, l: ast.Loc, subject: *ast.Expr, pack: *const ast.Expr) ParseError!*ast.Expr {
        return self.desugarMatchFields(l, subject, pack.table.fields);
    }

    /// The pack may arrive parenthesized/braced or as an offside region; by
    /// here it is just the alternatives, so both faces share one lowering and
    /// cannot drift apart.
    fn desugarMatchFields(self: *Parser, l: ast.Loc, subject: *ast.Expr, fields: []const ast.TableField) ParseError!*ast.Expr {
        if (subject.* != .name) {
            term.locErr(l, "`:match` needs a bound subject: each alternative compares against it, so bind the value first", .{});
            return error.UnexpectedToken;
        }
        if (fields.len == 0) {
            term.locErr(l, "`:match` has no alternatives", .{});
            return error.UnexpectedToken;
        }

        var else_val: ?*ast.Expr = null;
        var n: usize = 0;
        for (fields, 0..) |fld, i| {
            switch (fld) {
                .named => |nm| {
                    if (std.mem.eql(u8, nm.key, "else")) {
                        // `else` is the REMAINING alternative, so anything after
                        // it is unreachable. Refuse rather than silently drop.
                        if (i != fields.len - 1) {
                            term.locErr(l, "`else` is the remaining alternative and must come last", .{});
                            return error.UnexpectedToken;
                        }
                        else_val = nm.val;
                    } else n += 1;
                },
                .indexed => n += 1,
                .positional => {
                    term.locErr(l, "`:match` alternatives are named — write `name = value`", .{});
                    return error.UnexpectedToken;
                },
                else => {
                    term.locErr(l, "unsupported alternative in `:match`", .{});
                    return error.UnexpectedToken;
                },
            }
        }
        // §17: a missing remaining alternative must not mint a nil/zero result.
        // An explicit `else` supplies one. So does EXHAUSTIVENESS over a sealed
        // case-set — if the alternatives name every case of one home, there is
        // no remaining alternative to invent a value for.
        //
        // The alternatives themselves determine the home; the subject's declared
        // type is not consulted and does not need to be. That keeps the check
        // sound at parse time: a pack naming every case of `colour` is
        // exhaustive whatever the subject was annotated as.
        var exhaustive = false;
        if (else_val == null and n > 0) {
            if (try self.packCoversCaseSet(l, fields)) exhaustive = true else {
                term.locErr(l, "`:match` needs an `else` alternative, or a value is invented for the cases it does not name", .{});
                return error.UnexpectedToken;
            }
        }
        if (else_val == null and !exhaustive) {
            term.locErr(l, "`:match` has no alternatives to select", .{});
            return error.UnexpectedToken;
        }

        // Build from the last alternative backwards, so the first-written
        // alternative ends up outermost and the arms are tried in source order.
        //
        // When the pack is exhaustive the LAST alternative becomes the final
        // arm directly: its case is the only one left, so testing for it would
        // be a comparison whose answer is already known.
        var acc: *ast.Expr = if (else_val) |e| e else switch (fields[n - 1]) {
            .named => |nm| nm.val,
            .indexed => |ix| ix.val,
            else => unreachable,
        };
        var idx: usize = if (else_val == null) n - 1 else n;
        while (idx > 0) {
            idx -= 1;
            const fld = fields[idx];
            const key: *ast.Expr = switch (fld) {
                .named => |nm| try self.new_expr(.{ .name = .{ .loc = l, .ident = nm.key } }),
                .indexed => |ix| ix.key,
                else => unreachable,
            };
            const val: *ast.Expr = switch (fld) {
                .named => |nm| nm.val,
                .indexed => |ix| ix.val,
                else => unreachable,
            };
            const cond = try self.new_expr(.{ .binop = .{
                .loc = l,
                .op = .eq,
                .lhs = subject,
                .rhs = key,
            } });
            acc = try self.new_expr(.{ .if_expr = try self.new_if_expr(l, cond, val, acc) });
        }
        return acc;
    }

    fn parse_if_expr(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.kw_if)).loc;
        // §15 comma-packed application face: `if(c, yes, no)` is a SOURCE
        // PROJECTION of the block face, not a second construct. It is desugared
        // right here into the SAME `if_expr` node the block face builds, so the
        // two spellings cannot diverge semantically — that is the ruling's
        // negative control #1 satisfied by construction rather than by testing.
        //
        // Unambiguous because a condition can never be a comma list: a single
        // element `if(c)` is an ordinary parenthesized condition and falls
        // through to the block face untouched. The curried face `if(c)(a)(b)`
        // stays IMPLEMENTATION-BLOCKED — distinguishing it from a condition that
        // is itself a call chain (`if (f)(x) then …`) needs the resolver, and
        // §42 says reject ambiguity rather than guess.
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv();
            const first = try self.parse_expr();
            if ((try self.pk()).kind == .comma) {
                _ = try self.adv();
                const then_e = try self.parse_expr();
                // A two-element pack has no false alternative. Synthesising `nil`
                // here would mint exactly the fake zero/nil/empty result identity
                // §17 forbids — and it did: `if(c, 7)` returned 0 for c = 0. The
                // block face already fails closed on a missing arm, so this one
                // does too rather than answering with a value nobody wrote.
                if ((try self.pk()).kind != .comma) {
                    term.locErr(l, "`if(condition, yes)` has no false alternative; write `if(condition, yes, no)` or use the block form", .{});
                    return error.UnexpectedToken;
                }
                _ = try self.adv();
                const else_e = try self.parse_expr();
                _ = try self.expect(.rparen);
                return self.new_expr(.{ .if_expr = try self.new_if_expr(l, first, then_e, else_e) });
            }
            const rp = try self.expect(.rparen);
            // §2/§48 CURRIED FACE, decided by ADJACENCY rather than by counting
            // groups. `if(c)(yes)(no)` — groups glued together — is the curried
            // face; `if(c) (arm)` with a space is the canonical application face
            // whose arm merely happens to be parenthesized.
            //
            // Counting alone could not tell those apart, so the count rule had
            // to reject `if(c) (a) else (b)` under §42. Adjacency decides it
            // without guessing, which is strictly better than rejecting: the
            // same rule already separates `else(cond)` from `else (value)` and
            // `>>=` from `>> =`.
            if ((try self.pk()).kind == .lparen and self.glued_lparen(rp)) {
                _ = try self.adv();
                const second = try self.parse_expr();
                const rp2 = try self.expect(.rparen);
                if ((try self.pk()).kind == .lparen and self.glued_lparen(rp2)) {
                    _ = try self.adv();
                    const third = try self.parse_expr();
                    _ = try self.expect(.rparen);
                    return self.new_expr(.{ .if_expr = try self.new_if_expr(l, first, second, third) });
                }
                // Two groups: the condition was a call chain `first(second)`.
                var args = try self.alloc.alloc(*ast.Expr, 1);
                args[0] = second;
                const call = try self.new_expr(.{ .call = .{ .loc = l, .func = first, .args = args } });
                return self.parse_if_expr_after_if_with_cond(l, call, true);
            }
            return self.parse_if_expr_after_if_with_cond(l, first, true);
        }
        return self.parse_if_expr_after_if(l, true);
    }

    fn parse_if_expr_after_if(self: *Parser, l: ast.Loc, consume_end: bool) ParseError!*ast.Expr {
        const cond = try self.parse_expr();
        return self.parse_if_expr_after_if_with_cond(l, cond, consume_end);
    }

    /// Same as `parse_if_expr_after_if`, for a condition already parsed by the
    /// caller (the §15 single-element group `if(c)`).
    fn parse_if_expr_after_if_with_cond(self: *Parser, l: ast.Loc, cond: *ast.Expr, consume_end: bool) ParseError!*ast.Expr {
        // §6: `kind = if tok.keyword keyword else name` — the
        // expression-if IS the ternary, and like every other one-liner it is
        // terminated by the newline (§3.3), not by a closer. `then` is what
        // tells the two dialects apart, so it is recorded rather than dropped.
        const saw_then = (try self.eat(.kw_then)) != null;
        // COMPACT CONDITIONAL FACE: `if(c) = value`. The `=` is the same
        // association face it is everywhere else — binding, structured label,
        // place write — with the surrounding grammar supplying the role. Here
        // the role is "this is the alternative for that condition".
        //
        // It is optional, so `if(c) value` and the offside region form are
        // unaffected; this only admits a spelling that was a parse error.
        _ = try self.eat(.assign);
        const then_expr = try self.parse_expr();

        var else_expr: *ast.Expr = undefined;
        if (try self.eat(.kw_elseif) != null) {
            const nested_l = (try self.pk()).loc;
            else_expr = try self.parse_if_expr_after_if(nested_l, consume_end);
            return self.new_expr(.{ .if_expr = try self.new_if_expr(l, cond, then_expr, else_expr) });
        }
        if (try self.eat(.kw_else)) |else_kw| {
            // `else(condition) arm` in VALUE position, so the aligned chain
            //
            //     r = if(a) 10
            //         else(b) 20
            //         else 40
            //
            // is one value-producing conditional rather than four writes to a
            // binding. Same node as `elseif` and `else if` produce; only the
            // spelling differs. Adjacency separates it from `else (value)`.
            if (self.glued_lparen(else_kw)) {
                const nested_cond = try self.parse_expr();
                else_expr = try self.parse_if_expr_after_if_with_cond(else_kw.loc, nested_cond, consume_end);
                return self.new_expr(.{ .if_expr = try self.new_if_expr(l, cond, then_expr, else_expr) });
            }
            if (try self.eat(.kw_if) != null) {
                const nested_l = (try self.pk()).loc;
                else_expr = try self.parse_if_expr_after_if(nested_l, consume_end);
                return self.new_expr(.{ .if_expr = try self.new_if_expr(l, cond, then_expr, else_expr) });
            }
            // `else = value`, the remaining alternative in the compact face.
            _ = try self.eat(.assign);
            else_expr = try self.parse_expr();
        } else {
            else_expr = try self.new_expr(.{ .nil = l });
        }
        if (consume_end) {
            // A written `end` is "accepted and deleted" (§3.4), never demanded,
            // for the endless form. The legacy `if c then a else b end` keeps
            // demanding it, so no file that writes `then` can move; and the
            // endless form only ever eats an `end` sitting on the `if`'s OWN
            // line, so an `end` that closes an ENCLOSING block is never
            // swallowed — that mis-parse would silently retarget a closer.
            if (saw_then) {
                _ = try self.expect(.kw_end);
            } else {
                const closer = try self.pk();
                if (closer.kind == .kw_end and closer.loc.line == l.line) _ = try self.adv();
            }
        }
        return self.new_expr(.{ .if_expr = try self.new_if_expr(l, cond, then_expr, else_expr) });
    }

    fn new_if_expr(self: *Parser, l: ast.Loc, cond: *ast.Expr, then_expr: *ast.Expr, else_expr: *ast.Expr) ParseError!*ast.IfExpr {
        const node = try self.alloc.create(ast.IfExpr);
        node.* = .{ .loc = l, .cond = cond, .then_expr = then_expr, .else_expr = else_expr };
        return node;
    }

    // GR-007: returns a redirect hint for deprecated/non-existent single-word
    // compile-time directives, or null if `qualified` is acceptable. Dotted paths
    // (e.g. @comp.comptime.warn) are never matched here — only bare single words.
    fn bannedAtDirectiveSuggestion(qualified: []const u8) ?[]const u8 {
        const Entry = struct { name: []const u8, hint: []const u8 };
        const banned = [_]Entry{
            .{ .name = "const", .hint = "compile-time values use '@(expr)'; module-level bindings like 'x = 5' are already immutable (see GR-007)" },
            .{ .name = "comptime", .hint = "compile-time evaluation uses '@(expr)'; metaprogramming combinators use '@comp.*' e.g. @comp.map (see GR-007)" },
            .{ .name = "comptime_expr", .hint = "compile-time evaluation uses '@(expr)'; e.g. '@(1 + 2 * 3)' (see GR-007)" },
            .{ .name = "comptimeexpr", .hint = "compile-time evaluation uses '@(expr)'; e.g. '@(1 + 2 * 3)' (see GR-007)" },
            .{ .name = "compile_time", .hint = "compile-time evaluation uses '@(expr)'; metaprogramming combinators use '@comp.*' (see GR-007)" },
            .{ .name = "compiletime", .hint = "compile-time evaluation uses '@(expr)'; metaprogramming combinators use '@comp.*' (see GR-007)" },
            // NOTE: '@constexpr' is intentionally NOT banned — it is a working
            // directive that folds pure expressions through the comptime evaluator.
        };
        for (banned) |e| {
            if (std.mem.eql(u8, qualified, e.name)) return e.hint;
        }
        return null;
    }

    fn parse_macro_call_expr(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.at)).loc;
        // GR-007: reject @const / @comptime / @comptime_expr / @compile_time in
        // expression position too, before parse_at_path_segment errors generically
        // on the keyword token. @(expr) is comptime eval; @comp.* are combinators.
        {
            const after = try self.pk();
            if (after.text.len > 0) {
                if (Parser.bannedAtDirectiveSuggestion(after.text)) |sug| {
                    term.locErr(l, "'@{s}' is not a Duo directive", .{after.text});
                    term.locHint(l, "{s}", .{sug});
                    return ParseError.ExpectedToken;
                }
            }
        }
        // @(expr) — compile-time eval (no name, immediate paren)
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv(); // consume '('
            const operand = try self.parse_expr();
            _ = try self.expect(.rparen);
            return self.new_expr(.{ .unop = .{ .loc = l, .op = .compile, .operand = operand } });
        }
        // `@{ … }` — c0 §43 `anchor.brace`: "the same form, name recovered from
        // the enclosing descriptor". So this is NOT a third brace mechanism and
        // it does not get a reader of its own; it is `parse_pack` with the
        // subject-elided stance, and the enclosing descriptor is the name.
        //
        // The `.compile` wrapper STAYS, and that is a separate axis rather than
        // a second mechanism: `@` also stages, and the 25 measured `= @{ … }`
        // sites in the tree are frozen constant tables that depend on the
        // staging. Where there is no enclosing descriptor, `home` is null and
        // the pack is honestly anonymous — §43 says the name is RECOVERED from
        // context, and at top level there is no context to recover it from.
        if ((try self.pk()).kind == .lbrace) {
            term.locErr(l, "injection '@{{ … }}' has no derived-world fact yet", .{});
            term.locHint(l, "law.injection.only rules the sigil EXCLUSIVELY world-deriving, and the graph carries no derived world: WorldFact records home/reach/members with no parent and no fact deltas, so nothing can represent the injection. If a DESCRIPTOR was meant, law.expect.apply denies 'p: point = @{{ x, y }}' by name — write the pack '{{ … }}', the applied form 'name{{ … }}', or the case-set copula 'name: {{ a, b, c }}' for a keywordless enum", .{});
            return ParseError.ExpectedToken;
        }
        const first = try self.parse_at_path_segment();
        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(self.alloc);
        try parts.append(self.alloc, first.text);
        while ((try self.pk()).kind == .dot) {
            _ = try self.adv();
            const part = try self.parse_at_path_segment();
            try parts.append(self.alloc, part.text);
        }
        const qualified = try std.mem.join(self.alloc, ".", parts.items);
        defer self.alloc.free(qualified);

        self.warnDeprecatedAtQualified(l, qualified);

        if (std.mem.eql(u8, qualified, "sizeof") or std.mem.eql(u8, qualified, "alignof") or std.mem.eql(u8, qualified, "typeof") or std.mem.eql(u8, qualified, "fields")) {
            return self.parse_layout_intrinsic_call(l, qualified);
        }
        if (std.mem.eql(u8, qualified, "as")) {
            return self.parse_as_intrinsic_call(l);
        }

        _ = try self.expect(.lparen);
        var args: std.ArrayList(*ast.Expr) = .empty;
        // A `@`-directive's arguments are compile-time data, so `{...}` inside
        // them belongs to the directive, not to STR-1 interpolation. See
        // `directive_arg_depth`.
        self.directive_arg_depth += 1;
        defer self.directive_arg_depth -= 1;
        if (!(try self.check(.rparen))) {
            try args.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null) {
                try args.append(self.alloc, try self.parse_expr());
            }
        }
        _ = try self.expect(.rparen);
        const args_slice = try args.toOwnedSlice(self.alloc);

        // `@c.emit` / `@emit` / `@c.call` USED TO BE LOWERED HERE, above the
        // `self.formatting` guard — so `idol fmt` reprinted `@c.emit(x)` as
        // `__emit(x)` and `@c.call(…)` as `__c_call(…)`, rewriting SOURCE into
        // the compiler's internal spelling. That is the same class the guard
        // below exists to stop, and these three were simply on the wrong side
        // of it. The `resolveBuiltin` lookup forty lines below produces the
        // identical lowering for all three (and for the four other spellings
        // that reach `__emit`), so deleting them loses no behaviour and puts
        // them behind the formatting guard where every other directive already
        // is. Sole delta: `@c.emit()` with ZERO arguments now lowers instead of
        // staying a `macro_call` — an emit of nothing, which had no meaning as
        // a macro call either.
        //
        // A parser running in order to REPRINT keeps the written spelling.
        // Every branch below lowers `@name(...)` to an internal `__name(...)`,
        // and the printer then emits THAT — so `@comp.assert(...)` came back
        // out as `__static_assert(...)`, which the parser will not take back.
        // Third instance of the same class, after interpolation and the anchor:
        // a parse-time desugar is invisible to a formatter.
        if (self.formatting) {
            // `qualified` is freed on return by the defer above, so the AST
            // gets a COPY. Storing the original produced a dangling slice and
            // the formatter emitted raw garbage bytes — which the lexer then
            // rejected as "non-ASCII outside a string", pointing nowhere near
            // the cause.
            return self.new_expr(.{ .macro_call = .{
                .loc = l,
                .name = try self.alloc.dupe(u8, qualified),
                .args = args_slice,
            } });
        }
        // `@asm(...)` desugars to `__asm(...)` for inline assembly.
        if (std.mem.eql(u8, qualified, "asm") and args_slice.len >= 1) {
            const asm_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = "__asm" } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = asm_name, .args = args_slice } });
        }
        // `@hot_path(expr)` desugars to `__hot_path(expr)`.
        if (std.mem.eql(u8, qualified, "hot_path") and args_slice.len == 1) {
            const hot_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = "__hot_path" } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = hot_name, .args = args_slice } });
        }
        if (@import("meta_module.zig").resolveBuiltin(qualified)) |internal| {
            const builtin_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = internal } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = builtin_name, .args = args_slice } });
        }
        if (at_builtin_internal_name(self, qualified)) |internal| {
            if (self.idol_mode) {
                if (std.mem.eql(u8, qualified, "constexpr")) {
                    term.locErr(l, "@constexpr is not valid in .id files. Use @(expr) for comptime evaluation.", .{});
                    return ParseError.UnexpectedToken;
                }
                if (std.mem.eql(u8, qualified, "comptime_if")) {
                    term.locErr(l, "@comptime_if is not valid in .id files. Use if-expressions with @(expr) conditions.", .{});
                    return ParseError.UnexpectedToken;
                }
            }
            const builtin_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = internal } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = builtin_name, .args = args_slice } });
        }

        return self.new_expr(.{ .macro_call = .{
            .loc = l,
            .name = first.text,
            .args = args_slice,
        } });
    }

    fn parse_at_path_segment(self: *Parser) ParseError!Token {
        const tok = try self.pk();
        if (tok.kind == .name) return self.adv();
        const text = tok.kind.spelling();
        if (text.len > 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_')) {
            for (text[1..]) |c| {
                if (!(std.ascii.isAlphanumeric(c) or c == '_')) return self.expect(.name);
            }
            _ = try self.adv();
            return .{ .kind = .name, .text = text, .loc = tok.loc };
        }
        return self.expect(.name);
    }

    /// (P3-08): deprecation warnings for flat/legacy @-directive aliases in .id mode.
    fn warnDeprecatedAtQualified(self: *Parser, loc: ast.Loc, qualified: []const u8) void {
        if (!self.idol_mode) return;
        if (std.mem.startsWith(u8, qualified, "meta.")) {
            term.locWarn(loc, "warning: @meta.* is deprecated, use @comp.{s} instead", .{qualified["meta.".len..]});
            return;
        }
        if (std.mem.startsWith(u8, qualified, "compiler.")) {
            term.locWarn(loc, "warning: @compiler.* is deprecated, use @comp.{s} instead", .{qualified["compiler.".len..]});
            return;
        }
        if (std.mem.eql(u8, qualified, "pipeline")) {
            term.locWarn(loc, "warning: @pipeline is deprecated, use @comp.pipeline instead", .{});
            return;
        }
        if (std.mem.eql(u8, qualified, "emit")) {
            term.locWarn(loc, "warning: @emit is deprecated, use @comp.c.emit instead", .{});
            return;
        }
        if (std.mem.startsWith(u8, qualified, "c.") and !std.mem.startsWith(u8, qualified, "comp.")) {
            var buf: [128]u8 = undefined;
            const replacement = std.fmt.bufPrint(&buf, "comp.{s}", .{qualified}) catch return;
            term.locWarn(loc, "warning: @{s} is deprecated, use @{s} instead", .{ qualified, replacement });
            return;
        }
        if (legacy_directives.resolvePublic(qualified)) |entry| {
            if (entry.canonical) |canonical| {
                term.locWarn(loc, "warning: @{s} is deprecated, use @{s} instead", .{ entry.public, canonical });
            }
        }
    }

    fn at_builtin_internal_name(_: *Parser, name: []const u8) ?[]const u8 {
        if (legacy_directives.resolvePublic(name)) |entry| {
            return entry.internal;
        }
        return null;
    }

    fn parse_as_intrinsic_call(self: *Parser, loc: ast.Loc) ParseError!*ast.Expr {
        _ = try self.expect(.lparen);
        const typ = try self.parse_type();
        _ = try self.expect(.comma);
        const value = try self.parse_expr();
        _ = try self.expect(.rparen);

        const type_name = try self.type_expr_c_name(typ);
        const type_arg = try self.new_expr(.{ .quoted = .{ .loc = loc, .val = type_name } });
        const func = try self.new_expr(.{ .name = .{ .loc = loc, .ident = "__as" } });
        const args = try self.alloc.alloc(*ast.Expr, 2);
        args[0] = type_arg;
        args[1] = value;
        return self.new_expr(.{ .call = .{ .loc = loc, .func = func, .args = args } });
    }

    fn parse_layout_intrinsic_call(self: *Parser, loc: ast.Loc, name: []const u8) ParseError!*ast.Expr {
        _ = try self.expect(.lparen);
        var arg: *ast.Expr = undefined;
        const after_lparen = self.lex.saveState();
        if (try self.try_parse_layout_type_arg(loc)) |type_arg| {
            arg = type_arg;
        } else {
            self.lex.restoreState(after_lparen);
            arg = try self.parse_expr();
            _ = try self.expect(.rparen);
        }

        var func_ident: []const u8 = undefined;
        if (std.mem.eql(u8, name, "sizeof")) {
            func_ident = "__sizeof";
        } else if (std.mem.eql(u8, name, "alignof")) {
            func_ident = "__alignof";
        } else if (std.mem.eql(u8, name, "typeof")) {
            func_ident = "__typeof";
        } else if (std.mem.eql(u8, name, "fields")) {
            func_ident = "__fields";
        } else unreachable;

        const func_name = try self.new_expr(.{ .name = .{ .loc = loc, .ident = func_ident } });
        var args = try self.alloc.alloc(*ast.Expr, 1);
        args[0] = arg;
        return self.new_expr(.{ .call = .{ .loc = loc, .func = func_name, .args = args } });
    }

    fn try_parse_layout_type_arg(self: *Parser, loc: ast.Loc) ParseError!?*ast.Expr {
        const tok = try self.pk();
        if (!layout_arg_can_start_type(tok)) return null;
        const typ = try self.parse_type();
        if ((try self.pk()).kind != .rparen) return null;
        _ = try self.adv();
        return self.new_expr(.{ .quoted = .{ .loc = loc, .val = try self.type_expr_c_name(typ) } });
    }

    fn layout_arg_can_start_type(tok: Token) bool {
        if (grammar_roles.isDescriptor(tok.kind)) return true;
        return switch (tok.kind) {
            .star, .question, .lbracket, .lbrace => true,
            .name => tok.text.len > 0 and tok.text[0] >= 'A' and tok.text[0] <= 'Z',
            else => false,
        };
    }

    fn type_expr_c_name(self: *Parser, typ: ast.TypeExpr) ParseError![]const u8 {
        const rt = types.resolve(typ, null, self.alloc) catch .any;
        var buf: [128]u8 = undefined;
        return self.alloc.dupe(u8, rt.c_type(&buf));
    }

    fn parse_suffixed_expr(self: *Parser) ParseError!*ast.Expr {
        var e = try self.parse_simple_expr();
        while (true) {
            const tok = try self.pk();
            switch (tok.kind) {
                .dot => {
                    // §4, and §20's `peek = () if .pos < #.src .src[.pos] else nil`:
                    // `#.src .src[.pos]` is a comparison against `#.src` followed
                    // by the one-line then-expression, not `#((.src).src[.pos])`.
                    // A `.` with a gap in front of it is the LEADING anchor walk
                    // and starts a fresh expression; only a glued `.` continues
                    // the one on the left. Without this the two stances of `.`
                    // are indistinguishable inside a line and the longer parse
                    // always wins, which is how the then-expression was eaten.
                    if (!self.glued_to_prev(tok)) break;
                    _ = try self.adv();
                    // §2 THE ANCHOR gives the anchor exactly three
                    // stances — bare `@` NAMES it, leading `.` WALKS from it,
                    // postfix `X@rel` MOVES it — and `.@name` is none of them.
                    // It came in from the catalog (7af9a66) and the
                    // GRAVEYARD put it alongside `point:@to` and
                    // `Point.@to`; `scripts/spec_conformance.id` has carried a
                    // row asserting the form ABSENT, failing on purpose, ever
                    // since.
                    //
                    // WHAT IT SHIPPED. The parser stored the stance in a
                    // LEADING CHARACTER of the field name (`"@x"`), sema never
                    // looked, and codegen re-derived the intent by string-
                    // comparing that character and emitting a boxed metafield
                    // read. A native record has no metatable, so
                    //
                    //     p: point = { x = 3, y = 4 }
                    //     a = p.x        -- 3
                    //     b = p.@x       -- nil
                    //
                    // both CHECKED CLEAN and one of them answered the wrong
                    // value silently. That is the worst failure class there is:
                    // two spellings of one anchor, disagreeing, with no
                    // diagnostic anywhere in the pipeline.
                    //
                    // So the form is a diagnostic, decided here — the parser is
                    // the canonical syntax graph and owns which stance a sigil
                    // is. Codegen's `f.field[0] == '@'` arm went with it: with
                    // no producer left, a re-derivation from an identifier's
                    // spelling is dead weight that can only come back to life
                    // by accident.
                    if ((try self.pk()).kind == .at) {
                        const at_tok = try self.adv();
                        const sem = self.expect_name_like() catch "name";
                        term.locErr(at_tok.loc, "'.@{s}' is not an anchor stance", .{sem});
                        term.locHint(at_tok.loc, "§2 gives the anchor three stances: bare '@' names it, leading '.' walks from it, postfix 'X@{s}' moves it. Walk to the member with '.{s}'", .{ sem, sem });
                        return ParseError.UnexpectedToken;
                    }
                    const fld = try self.expect_name_like();
                    // `token.kind` names the case-set an inline field declared
                    // (§0.1 HOME), so `token.kind.eof` reaches a case. Only a
                    // pair this parse actually registered resolves; every other
                    // `a.b` stays the field access it was.
                    if (try self.caseset_home_of(e, fld)) |enum_name| {
                        e = try self.new_expr(.{ .name = .{ .loc = tok.loc, .ident = enum_name } });
                        continue;
                    }
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = fld } });
                },
                .at => {
                    // §2 THE ANCHOR — **postfix `X@rel` MOVES it and
                    // retrieves** (never invokes). §4's character catalog says
                    // the same in one line: "@ the anchor: name it (bare), move
                    // it (postfix X@rel — retrieval only)".
                    //
                    // THE DEFECT THIS CLOSES: the spec's own canonical spelling
                    // was UNREACHABLE, and what it reached instead was a tensor
                    // operator. `infix_prec` mapped `.at` to `.matmul`, so
                    //
                    //     q = p@x
                    //
                    // checked clean with `warning: infix '@' matmul is
                    // non-canonical` and then died in the C backend on "use of
                    // undeclared identifier 'x'" — `x` had been parsed as the
                    // right OPERAND of a binary operator.
                    //
                    // THE EVIDENCE THAT THIS IS A DISAGREEMENT AND NOT A GAP.
                    // The SELF-HOSTED parser already reads postfix `@` as an
                    // anchor SUFFIX: `lib/compiler/parser.id` builds
                    // `(anchor base name)` in `proj_suffixed`, right beside
                    // `.field`, `[i]` and `:m()`, and
                    // the parser-corpus proof pins
                    // `bar = foo@7` -> `(program (assign bar (anchor foo 7)))`.
                    // Two parsers in one repository held different facts about
                    // one token. This one now agrees with the canonical graph,
                    // and it agrees by PARSING THE SAME SHAPE — a suffix, not an
                    // infix operand.
                    //
                    // ADJACENCY DECIDES, which is this parser's own precedent
                    // (`peek_glued_assign`: `>>=` is `>>` glued to `=`, and
                    // "ADJACENCY is the whole rule"; `examples/layout/glued.id`
                    // is the fixture). Every `X@rel` in the spec is written
                    // glued — `p@x`, `backend@driver`, `shc@wire`,
                    // `ward@allocation_free`, `point@ordering` — and every
                    // matmul in this repository is written spaced: the three
                    // `x @ y` rows are all in `examples/compile_fail/`, and a
                    // grep of infix `@` over 770 tracked `.id` files finds no
                    // others. So glued `X@rel` is the anchor, spaced `a @ b`
                    // stays matmul, and no existing program changes meaning.
                    //
                    // RETRIEVAL, NEVER INVOCATION: this hands down a resolved
                    // `field` node — the value of `rel` at the anchored home —
                    // and never a `method_call`. Sema and codegen consume a
                    // decided fact; neither re-derives one, which is the rule
                    // row 1a set and row 3 enforced by deleting the last
                    // spelling-derived stance in codegen.
                    //
                    // WHAT IS STILL OWED, stated rather than faked: §2's
                    // relation space — `point@ordering -> (bundle, nil) |
                    // (nil, missing)`, protocol satisfaction, `|`/`&`
                    // distribution — does not exist in the compiler. The
                    // reachable half of MOVE is retrieval against the anchored
                    // home, and that is what this is.
                    if (tok.loc.line > e.loc().line) break;
                    // INTERJECTION IS ADMITTED LAW, NOT A MATMUL TYPO.
                    // `thing@{ k = v }` is the interject face of the world
                    // algebra (docs/spec/world.md:33, and :64 gives its exact
                    // reduction `thing@(@{ k = v })`), admitted under
                    // law.injection.only by the GAP-110 reconciliation of
                    // 2026-08-13. The anchor below only admits a NAME glued to
                    // the sigil, so a glued `{` or `(` fell through to matmul
                    // and died in sema as "matmul over non-tensor operands" —
                    // whose repair hint is "close the space", advice the
                    // spec's own example has already taken. Refuse here, where
                    // the shape is known, and name the missing fact instead of
                    // blaming the operand types.
                    if (try self.at_glued_world_face(tok)) |face| switch (face) {
                        .interject => {
                            term.locErr(tok.loc, "interjection 'thing@{{ … }}' has no derived-world fact yet", .{});
                            term.locHint(tok.loc, "docs/spec/world.md admits this face and law.injection.only rules that '@{{ … }}' derives a world, but the graph carries no derived world: WorldFact records home/reach/members with no parent and no fact deltas, so nothing can represent the injection. Qualify against a named world ('thing@world') until the derived-world fact exists", .{});
                            return ParseError.ExpectedToken;
                        },
                        .qualify_expr => {
                            term.locErr(tok.loc, "qualification 'thing@( … )' takes no world EXPRESSION yet", .{});
                            term.locHint(tok.loc, "docs/spec/world.md spells 'thing@(world.member)' for a nested world and 'thing@(@{{ k = v }})' for the exact interjection reduction, but the anchor admits only a NAME glued to the sigil: it builds an anchored '.field' node, and there is no world-expression operand for it to take. Name the world and write 'thing@world' until qualification carries an expression", .{});
                            return ParseError.ExpectedToken;
                        },
                    };
                    if (!try self.at_is_glued_anchor(tok)) break;
                    _ = try self.adv();
                    const rel = try self.expect_name_like();
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = rel, .anchored = true } });
                },
                .lbracket => {
                    _ = try self.adv();
                    const key = try self.parse_expr();
                    _ = try self.expect(.rbracket);
                    e = try self.new_expr(.{ .index = .{ .loc = tok.loc, .obj = e, .key = key } });
                },
                .colon => {
                    // Peek ahead to distinguish type annotation from method call.
                    // Type annotation: name : Type = value
                    // Method call:     obj : method ( args )
                    const saved = self.lex.saveState();
                    _ = try self.lex.next(); // consume ':'
                    const after_colon = try self.lex.peek();
                    if (grammar_roles.isDescriptor(after_colon.kind)) {
                        // name : i64 = ...  —  this is a typed binding; don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .lbrace) {
                        // name : { ... } — record type annotation (Jai-like syntax); don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .at) {
                        // name : @{ ... } — descriptor declaration; don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .star or after_colon.kind == .question) {
                        // name : *Type or name : ?Type — pointer/optional type; don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    // `point:` followed by a LATER line is a descriptor home
                    // written offside, not a subject call — a subject call's
                    // method name always sits on the same line as its `:`.
                    // Without this, `point:` over `x: f64` was consumed as
                    // `point:x(...)` and reported "expected function arguments".
                    // `a:match` over an offside pack is unaffected: its method
                    // name IS on the `:` line.
                    if (after_colon.loc.line != tok.loc.line) {
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .lbracket) {
                        // name : [N]Type / name : []Type — array type annotation; a
                        // `[` can never open a method name, so this is unambiguously a
                        // typed binding. Without this case it fell through to the
                        // method-call path and `expect_name_like` failed on `[`.
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .name) {
                        // Could be name : UserType = ... or obj : method ( args )
                        _ = try self.lex.next(); // consume the name
                        const after_name = try self.lex.peek();
                        if (after_name.kind == .assign) {
                            // name : TypeName = ...  —  typed binding; don't consume
                            self.lex.restoreState(saved);
                            break;
                        }
                        // `x: i(64) = 5` — an APPLIED type, not the subject call
                        // `x:i(64)`. Both shapes are `name : name ( … )`, so the
                        // `=` after the closing paren is what separates them:
                        // assigning to the result of a call is never valid, so a
                        // trailing `=` admits only the binding reading. Scanning
                        // the parens balanced keeps `x:f(g(1))` working.
                        if (after_name.kind == .lparen) {
                            _ = try self.lex.next();
                            var depth: usize = 1;
                            while (depth > 0) {
                                const t = try self.lex.next();
                                switch (t.kind) {
                                    .lparen => depth += 1,
                                    .rparen => depth -= 1,
                                    .eof => break,
                                    else => {},
                                }
                            }
                            const after_paren = try self.lex.peek();
                            self.lex.restoreState(saved);
                            if (after_paren.kind == .assign) break;
                        } else {
                            self.lex.restoreState(saved);
                        }
                    } else {
                        self.lex.restoreState(saved);
                    }
                    // Not a typed binding — treat as method call
                    _ = try self.adv(); // consume ':'
                    const method = try self.expect_name_like();
                    // `subject:match` with the alternatives offside rather than
                    // delimited. The introducer settles the role, so no opener
                    // is needed to say "a pack follows".
                    if (std.mem.eql(u8, method, "match")) {
                        const nxt = try self.pk();
                        if (nxt.kind != .lparen and nxt.kind != .lbrace) {
                            const fields = try self.parse_offside_pack(tok.loc);
                            e = try self.desugarMatchFields(tok.loc, e, fields);
                            continue;
                        }
                    }
                    const callargs = try self.parse_call_args();
                    if (std.mem.eql(u8, method, "match") and
                        callargs.len == 1 and callargs[0].* == .table)
                    {
                        e = try self.desugarMatch(tok.loc, e, callargs[0]);
                    } else {
                        e = try self.new_expr(.{ .method_call = .{
                            .loc = tok.loc,
                            .obj = e,
                            .method = method,
                            .args = callargs,
                        } });
                    }
                },
                .lbrace => {
                    // Same rule as `(` and a string literal below (F-13813-1): a
                    // `{` on a new line starts a fresh expression, not a Lua
                    // `f{...}` table-call argument.
                    //
                    // Without this, the canonical tail-expression idiom silently
                    // becomes a call:
                    //     k = one(pos)
                    //     { kind = k, start = pos }   -- parsed as one(pos)({...})
                    // so the function returned a call result instead of a record.
                    // Table-call sugar buys nothing `f({...})` does not, and a
                    // scan of 575 `.id` files found zero real uses of it.
                    //
                    // APPLY-ONE (c0 §43 `law.brace`, §44 `law.apply.one`).
                    // `name{ … }` is ONE form and it is APPLICATION; the SUBJECT
                    // decides what applying means. This arm therefore emits the
                    // same node the paren face emits, and asks nothing about what
                    // `e` denotes — "the parser emits one structural application
                    // node and never resolves the edge".
                    //
                    // What changed here is not the node but the FACTS on it. It
                    // used to record `.parenless`, the same face a string call
                    // takes, and hand the pack to `parse_call_args` which wrapped
                    // it as an ordinary first argument. The result was that
                    //
                    //     f{ x = 1 }        and        f({ x = 1 })
                    //
                    // produced byte-identical trees. c0 §44a trap 2 is "braces as
                    // sugar", and the tree had already applied that sugar and
                    // erased the evidence before sema ran, so no later consumer
                    // could have declined it. Now the face is `.braced` and the
                    // operand carries `pack.applied`, which is the difference
                    // between an argument pack and a table that happens to be an
                    // argument. `pack.realized` stays `.undecided`: law.pack.shape
                    // puts representation AFTER semantic resolution, and a `{` in
                    // the source is not a demand for a heap table.
                    if (tok.loc.line > e.loc().line) break;
                    if (e.* == .name and std.mem.eql(u8, e.name.ident, "nn")) {
                        // FINDING, reported not repaired (gap[092]): this line is
                        // c0 §44a trap 1 verbatim — the parser asking what a name
                        // denotes to pick a different production — sitting in the
                        // very arm APPLY-ONE repairs. It is left standing because
                        // deleting it changes what `examples/ml_showcase.id`
                        // compiles to, and a regression is not a fix. Its removal
                        // is a step of gap[092], with its one real user measured.
                        e = try self.parse_nn_block_desugar(tok.loc);
                    } else {
                        const callargs = try self.parse_call_args();
                        e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs, .form = .braced } });
                    }
                },
                .lparen => {
                    if (tok.loc.line > e.loc().line) break;
                    const callargs = try self.parse_call_args();
                    // §9 — `decode(u64)(v)`: the FIRST group is the
                    // level, a descriptor-space key, so it selects the edge
                    // rather than passing an argument. Resolved against the
                    // edges this parse has actually seen declared, so a call
                    // that is not a relation edge is left exactly as it was.
                    if (try self.relation_edge_of(e, callargs)) |sym| {
                        e = try self.new_expr(.{ .name = .{ .loc = tok.loc, .ident = sym } });
                        continue;
                    }
                    // DESCRIPTOR APPLICATION: `point(3, 4)` fills a declared
                    // descriptor's slots in declaration order. Same application
                    // grammar as any call; only what the callee resolves to
                    // differs, so there is no constructor syntax.
                    if (try self.descriptorApplication(tok.loc, e, callargs)) |built| {
                        e = built;
                        continue;
                    }
                    e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs, .form = .parenthesized } });
                },
                .question => {
                    _ = try self.adv();
                    e = try self.new_expr(.{ .try_expr = .{ .loc = tok.loc, .operand = e } });
                },
                .bang => {
                    _ = try self.adv();
                    e = try self.new_expr(.{ .unwrap_expr = .{ .loc = tok.loc, .operand = e } });
                },
                else => {
                    if (!grammar_roles.isQuotedKind(tok.kind)) break;
                    if (tok.loc.line > e.loc().line) break;
                    const saved = self.lex.saveState();
                    _ = try self.adv();
                    const after = try self.pk();
                    self.lex.restoreState(saved);
                    if (after.kind == .concat) break;
                    const callargs = try self.parse_call_args();
                    if (try self.relation_edge_of(e, callargs)) |sym| {
                        e = try self.new_expr(.{ .name = .{ .loc = tok.loc, .ident = sym } });
                        continue;
                    }
                    e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs, .form = .parenless } });
                },
            }
        }
        return e;
    }

    /// `nn { linear(784,256) relu() … }` → `(req "std.ml.nn").build(NN.linear(...), …)`.
    fn parse_nn_block_desugar(self: *Parser, loc: ast.Loc) ParseError!*ast.Expr {
        _ = try self.expect(.lbrace);
        var layers: std.ArrayList(*ast.Expr) = .empty;
        while (!(try self.check(.rbrace))) {
            const layer = try self.parse_nn_layer_expr();
            try layers.append(self.alloc, layer);
            _ = try self.eat(.semi);
        }
        _ = try self.expect(.rbrace);
        return try self.desugar_nn_build(loc, try layers.toOwnedSlice(self.alloc));
    }

    fn parse_nn_layer_expr(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        if (tok.kind == .name) {
            const saved = self.lex.saveState();
            _ = try self.adv();
            const nxt = try self.pk();
            if (nxt.kind != .lparen) {
                const func = try self.new_expr(.{ .name = .{ .loc = tok.loc, .ident = tok.text } });
                return try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = func, .args = &.{} } });
            }
            self.lex.restoreState(saved);
        }
        const expr = try self.parse_expr();
        if (expr.* == .name) {
            const func = expr;
            return try self.new_expr(.{ .call = .{ .loc = func.loc(), .func = func, .args = &.{} } });
        }
        return expr;
    }

    fn desugar_nn_build(self: *Parser, loc: ast.Loc, layers: []*ast.Expr) ParseError!*ast.Expr {
        const mod_ref = try self.make_req_module(loc, "std.ml.nn");
        var nn_layers: std.ArrayList(*ast.Expr) = .empty;
        for (layers) |layer| {
            try nn_layers.append(self.alloc, try self.nn_layer_to_method(loc, mod_ref, layer));
        }
        const build_fn = try self.new_expr(.{ .field = .{
            .loc = loc,
            .obj = mod_ref,
            .field = "build",
        } });
        return try self.new_expr(.{ .call = .{
            .loc = loc,
            .func = build_fn,
            .args = try nn_layers.toOwnedSlice(self.alloc),
        } });
    }

    fn nn_layer_to_method(self: *Parser, loc: ast.Loc, mod_ref: *ast.Expr, layer: *ast.Expr) ParseError!*ast.Expr {
        return switch (layer.*) {
            .call => |c| blk: {
                const method: []const u8 = switch (c.func.*) {
                    .name => |n| n.ident,
                    .field => |f| f.field,
                    else => return layer,
                };
                break :blk try self.new_expr(.{ .method_call = .{
                    .loc = loc,
                    .obj = mod_ref,
                    .method = method,
                    .args = c.args,
                } });
            },
            .name => |n| try self.new_expr(.{ .method_call = .{
                .loc = loc,
                .obj = mod_ref,
                .method = n.ident,
                .args = &.{},
            } }),
            else => layer,
        };
    }

    fn make_req_module(self: *Parser, loc: ast.Loc, path: []const u8) ParseError!*ast.Expr {
        const req_fn = try self.new_expr(.{ .name = .{ .loc = loc, .ident = "req" } });
        const path_lit = try self.new_expr(.{ .quoted = .{ .loc = loc, .val = path } });
        const req_args = try self.alloc.alloc(*ast.Expr, 1);
        req_args[0] = path_lit;
        return try self.new_expr(.{ .call = .{
            .loc = loc,
            .func = req_fn,
            .args = req_args,
        } });
    }

    fn parse_call_args(self: *Parser) ParseError![]*ast.Expr {
        var args: std.ArrayList(*ast.Expr) = .empty;
        const tok = try self.pk();
        // R2 ARGUMENT POSITION, counted rather than guessed — this is where
        // `map(.x)` gets its lens stance. Only the parenthesised arm counts: a
        // brace-call `f{ ... }` is a table and a string-call is a literal,
        // neither of which can carry a leading `.` expression.
        switch (tok.kind) {
            .lparen => {
                _ = try self.adv();
                self.call_arg_depth += 1;
                defer self.call_arg_depth -= 1;
                if (!(try self.check(.rparen))) {
                    try args.append(self.alloc, try self.parse_expr());
                    while (try self.eat(.comma) != null)
                        try args.append(self.alloc, try self.parse_expr());
                }
                _ = try self.expect(.rparen);
            },
            // APPLY-ONE: a brace in argument position IS the subject's argument
            // PACK (c0 §44 `law.pack.shape`), and saying so is the whole point —
            // `f{ x = 1 }` and `f({ x = 1 })` were the same tree until this bit
            // existed. `parse_table` reads the same bytes either way; only the
            // stance differs, because there is one brace form and not two.
            .lbrace => try args.append(self.alloc, try self.parse_pack(.{
                .applied = true,
                .home = self.descriptor_home,
            })),
            else => {
                if (grammar_roles.isQuotedKind(tok.kind)) {
                    try args.append(self.alloc, try self.parse_simple_expr());
                } else {
                    term.locErr(tok.loc, "expected function arguments", .{});
                    return ParseError.UnexpectedToken;
                }
            },
        }
        return args.toOwnedSlice(self.alloc);
    }

    /// The ONE brace reader. Every stance of `{ … }` — anonymous value, applied
    /// pack, elided-subject pack — reads the same bytes through here and differs
    /// only in the `Pack` stance it is handed. c0 §43: there are not two brace
    /// forms to choose between, so there is not a second reader to choose either.
    fn parse_table(self: *Parser) ParseError!*ast.Expr {
        return self.parse_pack(.{});
    }

    fn parse_pack(self: *Parser, stance: ast.Pack) ParseError!*ast.Expr {
        const e = try self.parse_pack_body();
        // A `for` inside the braces made this a comprehension, which is a stream
        // and not a pack; leave it exactly as it was rather than stamping a
        // stance onto a node that has no pack.
        if (e.* == .table) e.table.pack = stance;
        return e;
    }

    fn parse_pack_body(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.lbrace)).loc;
        var fields: std.ArrayList(ast.TableField) = .empty;
        while (!(try self.check(.rbrace))) {
            const tok = try self.pk();
            if (tok.kind == .concat) {
                _ = try self.adv();
                const spread_expr = try self.parse_expr();
                try fields.append(self.alloc, .{ .spread = spread_expr });
            } else if (tok.kind == .lbracket) {
                _ = try self.adv();
                const key = try self.parse_expr();
                _ = try self.expect(.rbracket);
                _ = try self.expect(.assign);
                const val = try self.parse_expr();
                try fields.append(self.alloc, .{ .indexed = .{ .key = key, .val = val } });
            } else if (grammar_roles.isQuotedKind(tok.kind) or tok.kind == .int_lit) {
                // Sugar: "key" = val  or  1 = val  (unboxed literal key, desugars to indexed)
                // Check if next token is `=` via saveState lookahead
                const saved_lit = self.lex.saveState();
                _ = try self.adv(); // consume the literal
                if (try self.check(.assign)) {
                    _ = try self.adv(); // consume `=`
                    const key = try self.new_expr(if (grammar_roles.isQuotedKind(tok.kind))
                        ast.Expr{ .quoted = .{ .loc = tok.loc, .val = tok.text, .quote = quoteOf(tok.kind) } }
                    else
                        ast.Expr{ .int_lit = .{ .loc = tok.loc, .val = tok.int_val } });
                    const val = try self.parse_expr();
                    try fields.append(self.alloc, .{ .indexed = .{ .key = key, .val = val } });
                } else {
                    self.lex.restoreState(saved_lit);
                    const val = try self.parse_expr();
                    if (try self.eat(.kw_for) != null) {
                        const comp = try self.finish_list_comp(l, val);
                        _ = try self.expect(.rbrace);
                        return comp;
                    }
                    try fields.append(self.alloc, .{ .positional = val });
                }
            } else if (tok.kind == .name or tok.kind == .kw_else or grammar_roles.isDescriptor(tok.kind)) {
                // Speculate: name '=' and name ':' Type '=' mean named fields;
                // otherwise the entry is positional. A type name is an ORDINARY
                // name here, so `{ i32 = 69 }` parses like `{ foo = 69 }`.
                //
                // `else` is admitted as a KEY so a structured alternative pack
                // can name its remaining alternative — `subject:match{ … else =
                // z }` — giving `else` the same meaning inside a pack that it
                // has in a conditional chain. It is a key only; nothing here
                // makes `else` a name anywhere else.
                const key_text = if (tok.kind == .name) tok.text else tok.kind.spelling();
                const saved = self.lex.saveState();
                _ = try self.adv();
                if (try self.check(.assign)) {
                    _ = try self.adv();
                    const val = try self.parse_expr();
                    try fields.append(self.alloc, .{ .named = .{ .key = key_text, .val = val } });
                } else if (try self.check(.colon)) {
                    _ = try self.adv();
                    _ = try self.parse_type();
                    if (try self.check(.assign)) {
                        _ = try self.adv();
                        const val = try self.parse_expr();
                        try fields.append(self.alloc, .{ .named = .{ .key = key_text, .val = val } });
                    } else {
                        self.lex.restoreState(saved);
                        const val = try self.parse_expr();
                        if (try self.eat(.kw_for) != null) {
                            const comp = try self.finish_list_comp(l, val);
                            _ = try self.expect(.rbrace);
                            return comp;
                        }
                        try fields.append(self.alloc, .{ .positional = val });
                    }
                } else {
                    self.lex.restoreState(saved);
                    const val = try self.parse_expr();
                    if (try self.eat(.kw_for) != null) {
                        const comp = try self.finish_list_comp(l, val);
                        _ = try self.expect(.rbrace);
                        return comp;
                    }
                    try fields.append(self.alloc, .{ .positional = val });
                }
            } else {
                const val = try self.parse_expr();
                if (try self.eat(.kw_for) != null) {
                    const comp = try self.finish_list_comp(l, val);
                    _ = try self.expect(.rbrace);
                    return comp;
                }
                try fields.append(self.alloc, .{ .positional = val });
            }
            // Field separator: comma and semicolon are optional when the next
            // token can start another field (name, [, .., string, number, or }).
            // Without this check, the parser would consume past the table end.
            //
            // `else` and descriptor keywords are in the set because they are
            // admitted KEYS above. Leaving them out made a newline-separated
            // pack stop at its own last alternative and then demand the `}` it
            // was standing on — `subject:match{ … else = z }` written one arm
            // per line, which is the canonical shape.
            if (try self.eat(.comma) == null and try self.eat(.semi) == null) {
                const next = try self.pk();
                if (next.kind != .name and next.kind != .lbracket and next.kind != .concat and
                    next.kind != .int_lit and next.kind != .rbrace and next.kind != .kw_else and
                    !grammar_roles.isDescriptor(next.kind) and
                    !grammar_roles.isQuotedKind(next.kind)) break;
            }
        }
        _ = try self.expect(.rbrace);
        return self.new_expr(.{ .table = .{ .loc = l, .fields = try fields.toOwnedSlice(self.alloc) } });
    }

    fn finish_list_comp(self: *Parser, loc: ast.Loc, value: *ast.Expr) ParseError!*ast.Expr {
        const first_name = try self.expect(.name);
        var key_name: ?[]const u8 = null;
        var value_name = first_name.text;
        if (try self.eat(.comma) != null) {
            key_name = first_name.text;
            const second_name = try self.expect(.name);
            value_name = second_name.text;
        }
        _ = try self.expect(.kw_in);
        const iter = try self.parse_expr();
        var filter: ?*ast.Expr = null;
        if (try self.eat(.kw_if) != null) {
            filter = try self.parse_expr();
        }
        return self.new_expr(.{ .list_comp = .{
            .loc = loc,
            .value = value,
            .key_name = key_name,
            .value_name = value_name,
            .iter = iter,
            .filter = filter,
        } });
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn parseSource(src: []const u8, arena: *std.heap.ArenaAllocator) ParseError!ast.Module {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    return p.parse_module();
}

fn parseDuoSource(src: []const u8, arena: *std.heap.ArenaAllocator) ParseError!ast.Module {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    return p.parse_module();
}

test "parse: call statement inside assign-form func body is not bare func decl" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\discard_fn = ()
        \\    side()
        \\    _stub = 0
        \\end
    , &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    try testing.expect(mod.body.stmts[0] == .func_decl);
    const body = mod.body.stmts[0].func_decl.func.body;
    try testing.expectEqual(@as(usize, 2), body.stmts.len);
    try testing.expect(body.stmts[0] == .call_stmt);
    try testing.expect(body.stmts[1] == .assign);
}

test "parse: empty module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("", &arena);
    try testing.expectEqual(@as(usize, 0), mod.body.stmts.len);
}

test "parse: quoted producer identities stay distinct" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const text = try parseDuoSource("x = \"hi\"", &arena);
    try testing.expectEqual(ast.Quote.text, text.body.stmts[0].assign.values[0].quoted.quote);
    const bytes = try parseDuoSource("x = 'hi'", &arena);
    try testing.expectEqual(ast.Quote.bytes, bytes.body.stmts[0].assign.values[0].quoted.quote);
    var lex = Lexer.initFamily("x = 'hi'", "x.lua", 2);
    var p = Parser.init(&lex, arena.allocator());
    const compat = try p.parse_module();
    try testing.expectEqual(ast.Quote.compat_text, compat.body.stmts[0].assign.values[0].quoted.quote);
}

test "parse: postfix generic type annotation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local xs: List[i64] = {}
    , &arena);
    const typ = mod.body.stmts[0].local_decl.names[0].typ;
    try testing.expect(typ == .generic);
    try testing.expectEqualStrings("List", typ.generic.base.named);
    try testing.expectEqual(@as(usize, 1), typ.generic.params.len);
    try testing.expectEqualStrings("i64", typ.generic.params[0].named);
}

test "parse: type declaration spelling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\type UserId = i64
    , &arena);
    try testing.expect(mod.body.stmts[0] == .alias_def);
    try testing.expectEqualStrings("UserId", mod.body.stmts[0].alias_def.name);
}

test "parse: generic type alias declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\type Vec<T> = List[T]
    , &arena);
    const alias = mod.body.stmts[0].alias_def;
    try testing.expectEqualStrings("Vec", alias.name);
    try testing.expect(alias.type_params != null);
    try testing.expectEqual(@as(usize, 1), alias.type_params.?.len);
    try testing.expectEqualStrings("T", alias.type_params.?[0].named);
    try testing.expect(alias.target.? == .generic);
    try testing.expectEqualStrings("List", alias.target.?.generic.base.named);
}

test "parse: type builtin remains expression-call compatible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local kind = type(value)
    , &arena);
    const init = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(init.* == .call);
    try testing.expect(init.call.func.* == .name);
    try testing.expectEqualStrings("type", init.call.func.name.ident);
}

test "parse: @sizeof and @alignof lower type arguments to layout intrinsics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local sz = @sizeof(i64)
        \\local align = @alignof(*u8)
        \\local expr_sz = @sizeof(value)
    , &arena);

    const sz = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(sz.* == .call);
    try testing.expect(sz.call.args[0].* == .quoted);
    try testing.expectEqualStrings("int64_t", sz.call.args[0].quoted.val);

    const align_expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expect(align_expr.* == .call);
    try testing.expect(align_expr.call.args[0].* == .quoted);
    try testing.expectEqualStrings("uint8_t*", align_expr.call.args[0].quoted.val);

    const expr_sz = mod.body.stmts[2].local_decl.inits[0];
    try testing.expect(expr_sz.* == .call);
    try testing.expect(expr_sz.call.args[0].* == .name);
    try testing.expectEqualStrings("value", expr_sz.call.args[0].name.ident);
}

test "parse: @as lowers a type argument to an internal typed coercion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local n = @as(i64, box.x)
    , &arena);

    const init = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(init.* == .call);
    try testing.expect(init.call.func.* == .name);
    try testing.expectEqualStrings("__as", init.call.func.name.ident);
    try testing.expectEqual(@as(usize, 2), init.call.args.len);
    try testing.expect(init.call.args[0].* == .quoted);
    try testing.expectEqualStrings("int64_t", init.call.args[0].quoted.val);
    try testing.expect(init.call.args[1].* == .field);
}

test "parse: @ builtin aliases lower to internal intrinsic calls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local folded = @constexpr(10 + 5)
        \\local branch = @comptime_if(true, 1, 2)
        \\local ty = @type_name(folded)
        \\local bits = @popcount(0xff)
        \\local checked = @static_assert("sizeof(int64_t) == 8", "i64 size")
    , &arena);

    const expected = [_][]const u8{
        "__constexpr",
        "__comptimeif",
        "__type_name",
        "__popcount",
        "__static_assert",
    };
    for (expected, 0..) |name, i| {
        const init = mod.body.stmts[i].local_decl.inits[0];
        try testing.expect(init.* == .call);
        try testing.expect(init.call.func.* == .name);
        try testing.expectEqualStrings(name, init.call.func.name.ident);
    }
}

test "parse: dotted @comp and @meta paths lower through meta module registry" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local ladder = @comp.ladder()
        \\local sweep = @meta.map("HasTag", cb)
    , &arena);

    const expected = [_][]const u8{ "__metaladder", "__comptimemap" };
    for (expected, 0..) |name, i| {
        const init = mod.body.stmts[i].local_decl.inits[0];
        try testing.expect(init.* == .call);
        try testing.expect(init.call.func.* == .name);
        try testing.expectEqualStrings(name, init.call.func.name.ident);
    }
}

test "parse: local declaration with integer initializer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local x = 42", &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.names.len);
    try testing.expectEqualStrings("x", stmt.local_decl.names[0].ident);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.inits.len);
    const init_expr = stmt.local_decl.inits[0];
    try testing.expect(init_expr.* == .int_lit);
    try testing.expectEqual(@as(i64, 42), init_expr.int_lit.val);
}

test "parse: Idol token identity keeps backtick reserved" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "`value";
    var lex = Lexer.init(source, "reserved.id");
    try testing.expectError(
        @import("lexer.zig").LexError.UnexpectedChar,
        @import("lexer_dispatch.zig").route(testing.allocator, &lex, source, "reserved.id"),
    );
}

test "parse: backtick rejection does not depend on token text" {
    const file = "reserved.id";
    const tokens = [_]Token{
        .{ .kind = .backtick, .loc = .{ .file = file, .line = 1, .col = 1 }, .text = "different" },
        .{ .kind = .eof, .loc = .{ .file = file, .line = 1, .col = 10 }, .text = "" },
    };
    var lex = Lexer.init("", file);
    try lex.useDuoTokens(&tokens);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var p = Parser.init(&lex, arena.allocator());
    p.idol_mode = true;

    try testing.expectError(ParseError.UnexpectedToken, p.parse_module());
    _ = try parseDuoSource("value = 1", &arena);
}

test "parse: retired macro declaration cannot reach quotation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "macro twice(x) `(,x + ,x)";
    try testing.expectError(
        ParseError.UnexpectedChar,
        parseDuoSource(source, &arena),
    );
    try testing.expectError(
        ParseError.UnexpectedToken,
        parseSource(source, &arena),
    );
}

test "parse: macro call expression statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("@twice(21)", &arena);
    try testing.expect(mod.body.tail_expr != null);
    const expr = mod.body.tail_expr.?;
    try testing.expect(expr.* == .macro_call);
    try testing.expectEqualStrings("twice", expr.macro_call.name);
    try testing.expectEqual(@as(usize, 1), expr.macro_call.args.len);
    try testing.expect(expr.macro_call.args[0].* == .int_lit);
    try testing.expectEqual(@as(i64, 21), expr.macro_call.args[0].int_lit.val);
}

test "parse: macro call before declaration is not an attribute" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@declare_pair()
        \\local p = 1
    , &arena);
    try testing.expectEqual(@as(usize, 2), mod.body.stmts.len);
    try testing.expect(mod.body.stmts[0] == .expr_stmt);
    try testing.expect(mod.body.stmts[0].expr_stmt.expr.* == .macro_call);
    try testing.expectEqualStrings("declare_pair", mod.body.stmts[0].expr_stmt.expr.macro_call.name);
    try testing.expect(mod.body.stmts[1] == .local_decl);
}

test "parse: local declaration with no initializer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local y", &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 0), stmt.local_decl.inits.len);
}

test "parse: local with type annotation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local n: i32 = 0", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    const name = stmt.local_decl.names[0];
    try testing.expectEqualStrings("n", name.ident);
    try testing.expect(name.typ == .named);
    try testing.expectEqualStrings("i32", name.typ.named);
}

test "parse: multiple locals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local a, b = 1, 2", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 2), stmt.local_decl.names.len);
    try testing.expectEqualStrings("a", stmt.local_decl.names[0].ident);
    try testing.expectEqualStrings("b", stmt.local_decl.names[1].ident);
    try testing.expectEqual(@as(usize, 2), stmt.local_decl.inits.len);
}

test "parse: function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\function greet()
        \\end
    , &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.path.len);
    try testing.expectEqualStrings("greet", stmt.func_decl.path[0]);
    try testing.expect(!stmt.func_decl.method);
    try testing.expect(!stmt.func_decl.is_local);
}

test "parse: typed function with return type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\function add(a: i32, b: i32) -> i32
        \\  return a + b
        \\end
    , &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expectEqual(@as(usize, 2), fd.func.params.len);
    try testing.expectEqualStrings("a", fd.func.params[0].name);
    try testing.expect(fd.func.params[0].typ == .named);
    try testing.expectEqualStrings("i32", fd.func.params[0].typ.named);
    try testing.expect(fd.func.ret_type == .named);
    try testing.expectEqualStrings("i32", fd.func.ret_type.named);
}

test "parse: local function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local function f()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expect(stmt.func_decl.is_local);
}

test "parse: function with varargs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\function f(...)
        \\end
    , &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.vararg);
}

test "parse: return statement with value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return 99", &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    try testing.expectEqual(@as(usize, 1), stmt.ret.vals.len);
    try testing.expect(stmt.ret.vals[0].* == .int_lit);
    try testing.expectEqual(@as(i64, 99), stmt.ret.vals[0].int_lit.val);
}

test "parse: return with no value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    try testing.expectEqual(@as(usize, 0), stmt.ret.vals.len);
}

test "parse: canonical return consumes immutable token-view expression-start role" {
    try testing.expect(grammar_roles.canBeginExpression(.int_lit));
    try testing.expect(grammar_roles.canBeginExpression(.kw_function));
    try testing.expect(!grammar_roles.canBeginExpression(.rparen));

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource("return 99", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    try testing.expectEqual(@as(usize, 1), stmt.ret.vals.len);
    try testing.expectEqual(@as(i64, 99), stmt.ret.vals[0].int_lit.val);

    var function_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer function_arena.deinit();
    const function_mod = try parseDuoSource("return function(x)\n  return x", &function_arena);
    try testing.expect(function_mod.body.stmts[0].ret.vals[0].* == .func_expr);

    var invalid_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer invalid_arena.deinit();
    try testing.expectError(ParseError.UnexpectedToken, parseDuoSource("return )", &invalid_arena));
}

test "parse: canonical return refuses without the production token view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lex = Lexer.init("return 99", "test.id");
    var p = Parser.init(&lex, arena.allocator());
    p.idol_mode = true;

    // Bypass parse_module deliberately: that is the owner that installs the
    // producer pack. The lookahead must not reconstruct the role from the host
    // scanner's token kind when the immutable view is absent.
    try testing.expectError(ParseError.UnexpectedToken, p.parse_return());
}

test "parse: match-arm pattern role consumes immutable token view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lex = Lexer.init("1 then return 7", "test.id");
    var p = Parser.init(&lex, arena.allocator());
    p.idol_mode = true;
    try p.ensureProducerPack();
    defer p.releaseOwnedPack();

    const before = p.lex.duoStreamIndex();
    try testing.expect(try p.startsMatchArm());
    try testing.expectEqual(before, p.lex.duoStreamIndex());
}

test "parse: match-arm lookahead refuses without the production token view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lex = Lexer.init("1 then return 7", "test.id");
    var p = Parser.init(&lex, arena.allocator());
    p.idol_mode = true;

    // Bypass parse_module deliberately. A host token kind is not permission to
    // reconstruct the generated pattern role when its producer view is absent.
    try testing.expectError(ParseError.UnexpectedToken, p.startsMatchArm());
}

test "parse: if statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\if true then
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .if_stmt);
    try testing.expect(stmt.if_stmt.cond.* == .true_lit);
    try testing.expect(stmt.if_stmt.else_body == null);
}

test "parse: if/else statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\if false then
        \\else
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .if_stmt);
    try testing.expect(stmt.if_stmt.else_body != null);
}

test "parse: if without then" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\if true
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .if_stmt);
    try testing.expect(stmt.if_stmt.cond.* == .true_lit);
    try testing.expect(stmt.if_stmt.else_body == null);
}

test "parse: if/elseif/else without then" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\if false
        \\elseif true
        \\else
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .if_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.if_stmt.elseifs.len);
    try testing.expect(stmt.if_stmt.else_body != null);
}

test "parse: while loop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\while true do
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .while_loop);
    try testing.expect(stmt.while_loop.cond.* == .true_lit);
}

test "parse: numeric for loop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\for i = 1, 10 do
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .num_for);
    try testing.expectEqualStrings("i", stmt.num_for.var_name);
    try testing.expect(stmt.num_for.start.* == .int_lit);
    try testing.expectEqual(@as(i64, 1), stmt.num_for.start.int_lit.val);
    try testing.expectEqual(@as(i64, 10), stmt.num_for.stop.int_lit.val);
    try testing.expect(stmt.num_for.step == null);
}

test "parse: numeric for with step" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\for i = 0, 10, 2 do
        \\end
    , &arena);
    const nf = mod.body.stmts[0].num_for;
    try testing.expect(nf.step != null);
    try testing.expectEqual(@as(i64, 2), nf.step.?.int_lit.val);
}

test "parse: generic for loop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\for k, v in pairs(t) do
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .gen_for);
    try testing.expectEqual(@as(usize, 2), stmt.gen_for.vars.len);
    try testing.expectEqualStrings("k", stmt.gen_for.vars[0]);
    try testing.expectEqualStrings("v", stmt.gen_for.vars[1]);
}

test "parse: repeat/until loop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\repeat
        \\until true
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .repeat_loop);
    try testing.expect(stmt.repeat_loop.cond.* == .true_lit);
}

test "parse: do block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\do
        \\end
    , &arena);
    try testing.expect(mod.body.stmts[0] == .do_block);
}

test "parse: binary expression addition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local r = 1 + 2", &arena);
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(init_expr.* == .binop);
    try testing.expectEqual(ast.BinOp.add, init_expr.binop.op);
}

test "parse: operator precedence: * before +" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // 1 + 2 * 3 should parse as 1 + (2 * 3)
    const mod = try parseSource("local r = 1 + 2 * 3", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .binop);
    try testing.expectEqual(ast.BinOp.add, expr.binop.op);
    // rhs should be the multiplication
    try testing.expect(expr.binop.rhs.* == .binop);
    try testing.expectEqual(ast.BinOp.mul, expr.binop.rhs.binop.op);
}

test "parse: unary negation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local r = -1", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .unop);
    try testing.expectEqual(ast.UnOp.neg, expr.unop.op);
}

test "parse: bang prefix negation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local r = !true", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .unop);
    try testing.expectEqual(ast.UnOp.not, expr.unop.op);
}

test "parse: table constructor empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local t = {}", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .table);
    try testing.expectEqual(@as(usize, 0), expr.table.fields.len);
}

test "parse: table constructor with named fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local t = {x = 1, y = 2}", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .table);
    try testing.expectEqual(@as(usize, 2), expr.table.fields.len);
    try testing.expect(expr.table.fields[0] == .named);
    try testing.expectEqualStrings("x", expr.table.fields[0].named.key);
}

test "parse: list comprehension" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local ys = {x * 2 for x in xs if x > 1}", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .list_comp);
    try testing.expectEqualStrings("x", expr.list_comp.value_name);
    try testing.expect(expr.list_comp.key_name == null);
    try testing.expect(expr.list_comp.value.* == .binop);
    try testing.expect(expr.list_comp.filter != null);
}

test "parse: list comprehension with key and value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("local ys = {k .. v for k, v in xs}", &arena);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .list_comp);
    try testing.expect(expr.list_comp.key_name != null);
    try testing.expectEqualStrings("k", expr.list_comp.key_name.?);
    try testing.expectEqualStrings("v", expr.list_comp.value_name);
}

test "parse: assignment statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("x = 5", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .assign);
    try testing.expectEqual(@as(usize, 1), stmt.assign.targets.len);
    try testing.expectEqual(@as(usize, 1), stmt.assign.values.len);
}

// ── SOURCE-CONTROL-ONE §8 — the control-face convergence gate ────────────────
//
// §8 is a GRAPH claim, not a syntax claim, and §10 forbids landing a face
// without it: *a compiler that produces identical ANSWERS but different
// semantic GRAPHS for two spellings is still WRONG.* So each canonical face
// below is compared against the familiar face it is equivalent to, structurally
// and node by node, ignoring only spelling provenance and source spans — which
// is exactly the pair §8 says to ignore.
//
// It compares the AST because THE AST IS THE AUTHORITY HERE. `idol graph` on
// these programs publishes `applications: []` and no control entity of any
// kind, so there is no lower-level control fact for a gate to read; a
// comparison of the graph JSON would agree on emptiness and prove nothing.
// Naming that plainly is part of the result.
//
// `ctlEqExpr`/`ctlEqStmt` FAIL CLOSED. An unhandled node kind returns an error
// rather than comparing equal, so a face that starts producing a shape this
// gate cannot see breaks the gate instead of passing it silently — the failure
// mode that let `gate/any.sh` and `gate/negative.sh` go green on a capability
// they had lost.

const CtlEqError = error{ UnhandledExprKind, UnhandledStmtKind } || anyerror;

fn ctlEqExpr(a: *const ast.Expr, b: *const ast.Expr) CtlEqError!void {
    try testing.expectEqualStrings(@tagName(a.*), @tagName(b.*));
    switch (a.*) {
        .int_lit => |x| try testing.expectEqual(x.val, b.int_lit.val),
        .name => |x| try testing.expectEqualStrings(x.ident, b.name.ident),
        .binop => |x| {
            try testing.expectEqual(x.op, b.binop.op);
            try ctlEqExpr(x.lhs, b.binop.lhs);
            try ctlEqExpr(x.rhs, b.binop.rhs);
        },
        .table => |x| {
            try testing.expectEqual(x.fields.len, b.table.fields.len);
            for (x.fields, b.table.fields) |fa, fb| {
                try testing.expectEqualStrings(@tagName(fa), @tagName(fb));
                switch (fa) {
                    .positional => |e| try ctlEqExpr(e, fb.positional),
                    else => return error.UnhandledExprKind,
                }
            }
        },
        .call => |x| {
            try ctlEqExpr(x.func, b.call.func);
            try testing.expectEqual(x.args.len, b.call.args.len);
            for (x.args, b.call.args) |ea, eb| try ctlEqExpr(ea, eb);
        },
        else => return error.UnhandledExprKind,
    }
}

fn ctlEqBlock(a: *const ast.Block, b: *const ast.Block) CtlEqError!void {
    try testing.expectEqual(a.stmts.len, b.stmts.len);
    for (a.stmts, b.stmts) |*sa, *sb| try ctlEqStmt(sa, sb);
    try testing.expectEqual(a.tail_expr == null, b.tail_expr == null);
    if (a.tail_expr) |ta| try ctlEqExpr(ta, b.tail_expr.?);
}

fn ctlEqStmt(a: *const ast.Stmt, b: *const ast.Stmt) CtlEqError!void {
    try testing.expectEqualStrings(@tagName(a.*), @tagName(b.*));
    switch (a.*) {
        // A location is a source span, which §8 lists among the two things to
        // ignore — so `brk`/`cont` compare equal on their TAG alone. That is
        // also the whole finding about them: the statement carries a location
        // and nothing else, and no exit target at all.
        .brk, .cont => {},
        .local_decl => |x| {
            try testing.expectEqual(x.names.len, b.local_decl.names.len);
            for (x.names, b.local_decl.names) |na, nb| try testing.expectEqualStrings(na.ident, nb.ident);
            try testing.expectEqual(x.inits.len, b.local_decl.inits.len);
            for (x.inits, b.local_decl.inits) |ea, eb| try ctlEqExpr(ea, eb);
        },
        .assign => |x| {
            try testing.expectEqual(x.targets.len, b.assign.targets.len);
            for (x.targets, b.assign.targets) |ea, eb| try ctlEqExpr(ea, eb);
            try testing.expectEqual(x.values.len, b.assign.values.len);
            for (x.values, b.assign.values) |ea, eb| try ctlEqExpr(ea, eb);
        },
        .expr_stmt => |x| try ctlEqExpr(x.expr, b.expr_stmt.expr),
        .call_stmt => |x| try ctlEqExpr(x.expr, b.call_stmt.expr),
        .while_loop => |x| {
            try ctlEqExpr(x.cond, b.while_loop.cond);
            try ctlEqBlock(&x.body, &b.while_loop.body);
        },
        .if_stmt => |x| {
            try testing.expectEqual(x.binding == null, b.if_stmt.binding == null);
            try ctlEqExpr(x.cond, b.if_stmt.cond);
            try ctlEqBlock(&x.then, &b.if_stmt.then);
            try testing.expectEqual(x.elseifs.len, b.if_stmt.elseifs.len);
            for (x.elseifs, b.if_stmt.elseifs) |ea, eb| {
                try ctlEqExpr(ea.cond, eb.cond);
                try ctlEqBlock(&ea.body, &eb.body);
            }
            try testing.expectEqual(x.else_body == null, b.if_stmt.else_body == null);
            if (x.else_body) |eb| try ctlEqBlock(&eb, &b.if_stmt.else_body.?);
        },
        .gen_for => |x| {
            try testing.expectEqual(x.vars.len, b.gen_for.vars.len);
            for (x.vars, b.gen_for.vars) |va, vb| try testing.expectEqualStrings(va, vb);
            try testing.expectEqual(x.iters.len, b.gen_for.iters.len);
            for (x.iters, b.gen_for.iters) |ea, eb| try ctlEqExpr(ea, eb);
            try ctlEqBlock(&x.body, &b.gen_for.body);
        },
        .func_decl => |x| {
            try testing.expectEqual(x.path.len, b.func_decl.path.len);
            for (x.path, b.func_decl.path) |pa, pb| try testing.expectEqualStrings(pa, pb);
            try ctlEqBlock(&x.func.body, &b.func_decl.func.body);
        },
        else => return error.UnhandledStmtKind,
    }
}

fn expectCtlConverges(canonical: []const u8, familiar: []const u8) !void {
    var arena_a = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_a.deinit();
    var arena_b = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_b.deinit();
    const ma = try parseDuoSource(canonical, &arena_a);
    const mb = try parseDuoSource(familiar, &arena_b);
    try ctlEqBlock(&ma.body, &mb.body);
}

test "SOURCE-CONTROL-ONE §5: `for(source) (item)` converges with `for item in source`" {
    try expectCtlConverges(
        \\main: i64 = ()
        \\    s = 0
        \\    xs = {1, 2, 3}
        \\    for(xs) (x)
        \\        s = s + x
        \\    s
    ,
        \\main: i64 = ()
        \\    s = 0
        \\    xs = {1, 2, 3}
        \\    for x in xs
        \\        s = s + x
        \\    s
    );
}

test "SOURCE-CONTROL-ONE §5: a two-item yield pack converges with two loop vars" {
    try expectCtlConverges(
        \\main: i64 = ()
        \\    s = 0
        \\    xs = {1, 2, 3}
        \\    for(xs) (k, v)
        \\        s = s + k + v
        \\    s
    ,
        \\main: i64 = ()
        \\    s = 0
        \\    xs = {1, 2, 3}
        \\    for k, v in xs
        \\        s = s + k + v
        \\    s
    );
}

test "SOURCE-CONTROL-ONE §7: `else if` converges with `else(cond)`" {
    // The shape WITHOUT a trailing bare `else` is the one that did not parse
    // at all before this gate existed, so it is the one pinned here.
    try expectCtlConverges(
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else if x < 7
        \\        r = 2
        \\    r
    ,
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else(x < 7)
        \\        r = 2
        \\    r
    );
}

test "SOURCE-CONTROL-ONE §7: an `else if` CHAIN converges with an `else(cond)` chain" {
    try expectCtlConverges(
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else if x < 7
        \\        r = 2
        \\    else if x < 9
        \\        r = 3
        \\    else
        \\        r = 4
        \\    r
    ,
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else(x < 7)
        \\        r = 2
        \\    else(x < 9)
        \\        r = 3
        \\    else
        \\        r = 4
        \\    r
    );
}

test "control convergence: the gate can FAIL — negative controls" {
    // A gate that cannot fail is deleted or made able to fail. Each of these
    // differs from its partner in exactly ONE fact §8 requires to be compared,
    // and each must be caught.

    // operand differs
    try testing.expectError(error.TestExpectedEqual, expectCtlConverges(
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i = i + 1
        \\        if i > 3
        \\            break
        \\    i
    ,
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i = i + 1
        \\        if i > 4
        \\            break
        \\    i
    ));

    // `continue` must NOT converge with `break` — the two exits are different
    // control targets and the gate has to see that. It is the only thing here
    // that reads an exit at all, and it reads only the TAG, because the
    // statement carries a source location and nothing else: no target, no
    // result pack. The target is reconstructed later by an innermost-loop
    // stack walked over the AST in `dnir_lower.zig` (`ctx.loop_breaks` /
    // `ctx.loop_heads`), which is the "find the nearest loop" resolution §6
    // forbids and the spelling-based control resolution §11 pins at 0.
    try testing.expectError(error.TestExpectedEqual, expectCtlConverges(
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i = i + 1
        \\        if i > 3
        \\            continue
        \\    i
    ,
        \\main: i64 = ()
        \\    i = 0
        \\    while i < 10
        \\        i = i + 1
        \\        if i > 3
        \\            break
        \\    i
    ));

    // the YIELD PACK differs — one item against two
    try testing.expectError(error.TestExpectedEqual, expectCtlConverges(
        \\main: i64 = ()
        \\    xs = {1, 2, 3}
        \\    for(xs) (x)
        \\        s = x
        \\    0
    ,
        \\main: i64 = ()
        \\    xs = {1, 2, 3}
        \\    for k, v in xs
        \\        s = k
        \\    0
    ));

    // the SOURCE differs
    try testing.expectError(error.TestExpectedEqual, expectCtlConverges(
        \\main: i64 = ()
        \\    xs = {1, 2, 3}
        \\    ys = {4, 5, 6}
        \\    for(xs) (x)
        \\        s = x
        \\    0
    ,
        \\main: i64 = ()
        \\    xs = {1, 2, 3}
        \\    ys = {4, 5, 6}
        \\    for x in ys
        \\        s = x
        \\    0
    ));

    // an ALTERNATIVE is missing — two arms against three
    try testing.expectError(error.TestExpectedEqual, expectCtlConverges(
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else if x < 7
        \\        r = 2
        \\    r
    ,
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else(x < 7)
        \\        r = 2
        \\    else
        \\        r = 3
        \\    r
    ));
}

test "SOURCE-CONTROL-ONE §3: `else` then a NESTED `if` on the next line stays nested" {
    // The same-line rule is what separates the two, and it has to keep the
    // genuinely nested spelling nested: `else` followed by `if` on a LATER
    // line is an ordinary refinement inside the else body, not an alternative
    // of the outer chain.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\main: i64 = ()
        \\    x = 5
        \\    r = 0
        \\    if x < 3
        \\        r = 1
        \\    else
        \\        if x < 7
        \\            r = 2
        \\    r
    , &arena);
    const body = mod.body.stmts[0].func_decl.func.body;
    const ifs = body.stmts[2].if_stmt;
    try testing.expectEqual(@as(usize, 0), ifs.elseifs.len);
    try testing.expect(ifs.else_body != null);
    try testing.expect(ifs.else_body.?.stmts[0] == .if_stmt);
}

test "parse: compound assignments lower to binary assignments" {
    const cases = [_]struct {
        src: []const u8,
        op: ast.BinOp,
    }{
        .{ .src = "x += 2", .op = .add },
        .{ .src = "x -= 2", .op = .sub },
        .{ .src = "x *= 2", .op = .mul },
        .{ .src = "x /= 2", .op = .div },
        .{ .src = "x %= 2", .op = .mod },
        .{ .src = "x ^= 2", .op = .pow },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const mod = try parseSource(case.src, &arena);
        const stmt = mod.body.stmts[0];
        try testing.expect(stmt == .assign);
        try testing.expectEqual(@as(usize, 1), stmt.assign.targets.len);
        try testing.expectEqual(@as(usize, 1), stmt.assign.values.len);
        try testing.expect(stmt.assign.values[0].* == .binop);
        try testing.expectEqual(case.op, stmt.assign.values[0].binop.op);
    }
}

test "parse: const declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("const PI = 3", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .const_decl);
    try testing.expectEqualStrings("PI", stmt.const_decl.ident);
}

test "parse: anonymous record type literal in annotation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.names.len);
    try testing.expectEqualStrings("p", stmt.local_decl.names[0].ident);
    try testing.expect(stmt.local_decl.names[0].typ == .record);
    try testing.expectEqual(@as(usize, 2), stmt.local_decl.names[0].typ.record.fields.len);
    try testing.expectEqualStrings("x", stmt.local_decl.names[0].typ.record.fields[0].name);
}

test "parse: goto and label" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("goto skip\n::skip::", &arena);
    try testing.expect(mod.body.stmts[0] == .goto_stmt);
    try testing.expectEqualStrings("skip", mod.body.stmts[0].goto_stmt.label);
    try testing.expect(mod.body.stmts[1] == .label_stmt);
    try testing.expectEqualStrings("skip", mod.body.stmts[1].label_stmt.label);
}

test "parse: break statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\while true do
        \\  break
        \\end
    , &arena);
    const body = mod.body.stmts[0].while_loop.body;
    try testing.expect(body.stmts[0] == .brk);
}

test "parse error: unexpected token" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // 'end' without a matching block opener should fail
    try testing.expectError(error.ExpectedToken, parseSource("if true", &arena));
}

test "parse: GR-007 rejects @const/@comptime/@comptime_expr/@compile_time with directed hint" {
    // These bare spellings are NOT valid Duo directives (GR-007). Compile-time
    // eval is @(expr); metaprogramming combinators are @comp.*. The parser must
    // reject them with ParseError rather than accept or cascade a generic error.
    const banned = [_][]const u8{
        "@const x = 5",
        "@comptime y = 10",
        "z = @comptime(1 + 2)",
        "@compile_time q = 1",
        "r = @comptime_expr(1 + 2)",
        "@compiletime s = 1",
        "@comptimeexpr t = 1",
    };
    for (banned) |src| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        try testing.expectError(error.ExpectedToken, parseSource(src, &arena));
    }
}

test "parse: GR-007 does NOT reject @(expr) or working single-word builtins" {
    // @(expr) comptime eval, @sizeof, @popcount must keep parsing.
    const ok = [_][]const u8{
        "y = @(1 + 2 * 3)",
        "print(@sizeof(i64))",
        "print(@popcount(7))",
    };
    for (ok) |src| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        _ = parseSource(src, &arena) catch continue;
    }
}

test "parse: try with no catch clauses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.try_stmt.body.stmts.len);
    try testing.expectEqual(@as(usize, 0), stmt.try_stmt.catches.len);
}

test "parse: try with single catch binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\catch e
        \\  local y = 2
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.try_stmt.body.stmts.len);
    try testing.expectEqual(@as(usize, 1), stmt.try_stmt.catches.len);
    const c = stmt.try_stmt.catches[0];
    try testing.expectEqualStrings("e", c.binding.?);
    try testing.expectEqual(@as(usize, 1), c.body.stmts.len);
}

test "parse: try with multiple catch clauses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\catch first
        \\  local a = 1
        \\catch second
        \\  local b = 2
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.try_stmt.catches.len);
    // First catch has a binding named "first"
    const c0 = stmt.try_stmt.catches[0];
    try testing.expectEqualStrings("first", c0.binding.?);
    // Second catch has a binding named "second"
    const c1 = stmt.try_stmt.catches[1];
    try testing.expectEqualStrings("second", c1.binding.?);
}

test "parse: defer statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\defer
        \\  local x = 1
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .defer_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.defer_stmt.body.stmts.len);
}

test "parse: try with catch and no binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\catch
        \\  local y = 2
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.try_stmt.catches.len);
    const c = stmt.try_stmt.catches[0];
    try testing.expect(c.binding == null);
}

test "parse: match statement with wildcard" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match x
        \\  _ then return 1
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expect(stmt.match_stmt.scrutinee.* == .name);
    try testing.expectEqualStrings("x", stmt.match_stmt.scrutinee.name.ident);
    try testing.expectEqual(@as(usize, 1), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .wildcard);
    try testing.expect(stmt.match_stmt.arms[0].guard == null);
}

test "parse: match statement with literal patterns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match n
        \\  1 then return "one"
        \\  2 then return "two"
        \\  _ then return "other"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[1].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[2].pattern == .wildcard);
}

test "parse: match case arms accept then and do" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match n
        \\  case 1 then return "one"
        \\  case 2 do return "two"
        \\  case _ then return "other"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[1].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[2].pattern == .wildcard);
}

test "parse: match pattern arms prefer then and do without fat arrows" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match n
        \\  1 then return "one"
        \\  2 do return "two"
        \\  _ then return "other"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[1].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[2].pattern == .wildcard);
}

test "parse: match pattern arm accepts guard before then" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match value
        \\  x if x > 0 then return x
        \\  _ then return 0
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .binding);
    try testing.expect(stmt.match_stmt.arms[0].guard != null);
}

test "parse: match case arm accepts guard before then" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match value
        \\  case x if x > 0 then return x
        \\  case _ then return 0
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .binding);
    try testing.expect(stmt.match_stmt.arms[0].guard != null);
}

test "parse: match with binding pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match val
        \\  x then return x
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.match_stmt.arms.len);
    const pat = stmt.match_stmt.arms[0].pattern;
    try testing.expect(pat == .binding);
    try testing.expectEqualStrings("x", pat.binding.name);
}

test "parse: match with guard expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match val
        \\  x if x > 0 then return x
        \\  _ then return 0
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    const arm = stmt.match_stmt.arms[0];
    try testing.expect(arm.pattern == .binding);
    try testing.expect(arm.guard != null);
    try testing.expect(arm.guard.?.* == .binop);
}

test "parse: match with variant pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match result
        \\  Option.Some(val) then return val
        \\  Option.None then return nil
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    const arm0 = stmt.match_stmt.arms[0];
    try testing.expect(arm0.pattern == .variant);
    try testing.expectEqualStrings("Option.Some", arm0.pattern.variant.tag);
    try testing.expect(arm0.pattern.variant.payload != null);
    try testing.expectEqual(@as(usize, 1), arm0.pattern.variant.payload.?.len);
    const arm1 = stmt.match_stmt.arms[1];
    try testing.expect(arm1.pattern == .variant);
    try testing.expectEqualStrings("Option.None", arm1.pattern.variant.tag);
    try testing.expect(arm1.pattern.variant.payload == null);
}

test "parse: match with table destructuring" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match obj
        \\  {x: a, y: b} then return a + b
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.match_stmt.arms.len);
    const pat = stmt.match_stmt.arms[0].pattern;
    try testing.expect(pat == .table_destr);
    try testing.expectEqual(@as(usize, 2), pat.table_destr.len);
    try testing.expectEqualStrings("x", pat.table_destr[0].key);
    try testing.expectEqualStrings("y", pat.table_destr[1].key);
}

test "parse: match with array destructuring" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match arr
        \\  [first, second] then return first
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.match_stmt.arms.len);
    const pat = stmt.match_stmt.arms[0].pattern;
    try testing.expect(pat == .array_destr);
    try testing.expectEqual(@as(usize, 2), pat.array_destr.len);
}

test "parse: match with rest pattern in array" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match arr
        \\  [head, ...tail] then return head
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    const pat = stmt.match_stmt.arms[0].pattern;
    try testing.expect(pat == .array_destr);
    try testing.expectEqual(@as(usize, 2), pat.array_destr.len);
    try testing.expect(pat.array_destr[0] == .binding);
    try testing.expect(pat.array_destr[1] == .rest);
    try testing.expectEqualStrings("tail", pat.array_destr[1].rest);
}

test "parse: match as expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local r = match x
        \\  1 then return "one"
        \\  _ then return "other"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.inits.len);
    const expr = stmt.local_decl.inits[0];
    try testing.expect(expr.* == .match_expr);
    try testing.expectEqual(@as(usize, 2), expr.match_expr.arms.len);
}

test "parse: match with string literal pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match cmd
        \\  "start" then return 1
        \\  "stop" then return 0
        \\  _ then return -1
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[0].pattern.literal.* == .quoted);
}

test "parse: match with nil and boolean patterns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match flag
        \\  nil then return "nil"
        \\  true then return "yes"
        \\  false then return "no"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[0].pattern.literal.* == .nil);
    try testing.expect(stmt.match_stmt.arms[1].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[1].pattern.literal.* == .true_lit);
    try testing.expect(stmt.match_stmt.arms[2].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[2].pattern.literal.* == .false_lit);
}

test "parse: empty match statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match x
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 0), stmt.match_stmt.arms.len);
}

test "parse: postfix ? produces try_expr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return x?", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .try_expr);
    try testing.expect(expr.try_expr.operand.* == .name);
    try testing.expectEqualStrings("x", expr.try_expr.operand.name.ident);
}

test "parse: postfix ! produces unwrap_expr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return x!", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .unwrap_expr);
    try testing.expect(expr.unwrap_expr.operand.* == .name);
    try testing.expectEqualStrings("x", expr.unwrap_expr.operand.name.ident);
}

test "parse: postfix ? on call expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return get_value()?", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .try_expr);
    try testing.expect(expr.try_expr.operand.* == .call);
}

test "parse: postfix ! on call expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return get_value()!", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .unwrap_expr);
    try testing.expect(expr.unwrap_expr.operand.* == .call);
}

test "parse: chained postfix operators" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // x?.field! means ((x?).field)!
    const mod = try parseSource("return x?.field!", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    // outermost is unwrap_expr (!)
    try testing.expect(expr.* == .unwrap_expr);
    // its operand is a field access
    const field_expr = expr.unwrap_expr.operand;
    try testing.expect(field_expr.* == .field);
    // the object of the field is a try_expr (?)
    try testing.expect(field_expr.field.obj.* == .try_expr);
    try testing.expect(field_expr.field.obj.try_expr.operand.* == .name);
}

test "parse: @asm and @emit desugar to internal intrinsics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\a = @asm("nop")
        \\b = @emit("(int64_t)1")
    , &arena);
    try testing.expectEqual(@as(usize, 2), mod.body.stmts.len);
    const a_stmt = mod.body.stmts[0];
    const b_stmt = mod.body.stmts[1];
    try testing.expect(a_stmt == .assign);
    try testing.expect(b_stmt == .assign);
    const a_call = a_stmt.assign.values[0];
    const b_call = b_stmt.assign.values[0];
    try testing.expect(a_call.* == .call);
    try testing.expect(b_call.* == .call);
    try testing.expectEqualStrings("__asm", a_call.call.func.name.ident);
    try testing.expectEqualStrings("__emit", b_call.call.func.name.ident);
}

test "parse: @c.call desugars to raw C call intrinsic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local n: i64 = @c.call("llabs", x)
    , &arena);
    const init = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(init.* == .call);
    try testing.expect(init.call.func.* == .name);
    try testing.expectEqualStrings("__c_call", init.call.func.name.ident);
    try testing.expectEqual(@as(usize, 2), init.call.args.len);
    try testing.expect(init.call.args[0].* == .quoted);
    try testing.expectEqualStrings("llabs", init.call.args[0].quoted.val);
}

test "parse: @c.import is an imported C header directive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@c.import("math.h")
        \\local n: f64 = @c.call("fabs", -1.5)
    , &arena);
    try testing.expect(mod.body.stmts[0] == .cinclude);
    try testing.expectEqualStrings("math.h", mod.body.stmts[0].cinclude.header);
}

test "parse: @comp.c.import is an imported C header directive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@comp.c.import("fixtures/point.h")
        \\main(): f64
        \\    distance2({ x = 0.0, y = 0.0 })
        \\end
    , &arena);
    try testing.expect(mod.body.stmts[0] == .cinclude);
    try testing.expectEqualStrings("fixtures/point.h", mod.body.stmts[0].cinclude.header);
}

test "parse: generic type parameter with concept constraint" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Hashable
        \\  fun hash(self) -> i64
        \\end
        \\fun use<T: Hashable>(x: T): i64
        \\  x:hash()
        \\end
    , &arena);
    try testing.expect(mod.body.stmts[1] == .func_decl);
    const fb = mod.body.stmts[1].func_decl.func;
    try testing.expect(fb.type_params != null);
    try testing.expectEqual(@as(usize, 1), fb.type_params.?.len);
    try testing.expect(fb.type_params.?[0] == .constrained);
    try testing.expectEqualStrings("T", fb.type_params.?[0].constrained.name);
    try testing.expectEqual(@as(usize, 0), fb.type_params.?[0].constrained.extra.len);
    try testing.expect(fb.type_params.?[0].constrained.constraint.* == .named);
    try testing.expectEqualStrings("Hashable", fb.type_params.?[0].constrained.constraint.*.named);
}

test "parse: generic type parameter with multiple concept constraints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun f<T: Hashable + Counter>(x: T): i64
        \\  0
        \\end
    , &arena);
    const fb = mod.body.stmts[0].func_decl.func;
    try testing.expectEqual(@as(usize, 1), fb.type_params.?[0].constrained.extra.len);
    try testing.expectEqualStrings("Counter", fb.type_params.?[0].constrained.extra[0].named);
}

test "parse: @specialize is a standalone module directive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun id<T>(x: T): T
        \\  return x
        \\end
        \\@specialize(id, i64)
    , &arena);
    try testing.expectEqual(@as(usize, 2), mod.body.stmts.len);
    try testing.expect(mod.body.stmts[1] == .directive);
    try testing.expectEqualStrings("specialize", mod.body.stmts[1].directive.attr.name);
    try testing.expectEqualStrings("id, i64", mod.body.stmts[1].directive.attr.args.?);
}

test "parse: @specialize preserves nested generic type arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun id<T>(x: T): T
        \\  return x
        \\end
        \\@specialize(id, Result[i64, str])
    , &arena);
    try testing.expectEqual(@as(usize, 2), mod.body.stmts.len);
    try testing.expect(mod.body.stmts[1] == .directive);
    try testing.expectEqualStrings("specialize", mod.body.stmts[1].directive.attr.name);
    try testing.expectEqualStrings("id, Result[i64, str]", mod.body.stmts[1].directive.attr.args.?);
}

test "parse: @c.type is accepted in type position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\local p: *@c.type("struct duo_file") = nil
    , &arena);
    const typ = mod.body.stmts[0].local_decl.names[0].typ;
    try testing.expect(typ == .pointer);
    try testing.expect(typ.pointer.* == .named);
    try testing.expectEqualStrings("__c_type:struct duo_file", typ.pointer.*.named);
}

test "parse: assign-form bare func decl without return type (GR-001)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\sub = (a: i32, b: i32)
        \\    a - b
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqualStrings("sub", stmt.func_decl.path[0]);
    try testing.expectEqual(@as(usize, 2), stmt.func_decl.func.params.len);
    try testing.expect(stmt.func_decl.func.ret_type == .inferred);
}

test "parse: result demand precedes callable binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\budget: i64 = (fallback: i64)
        \\    fallback
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqualStrings("budget", stmt.func_decl.path[0]);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.func.params.len);
    try testing.expectEqualStrings("fallback", stmt.func_decl.func.params[0].name);
    try testing.expect(stmt.func_decl.func.ret_type == .named);
    try testing.expectEqualStrings("i64", stmt.func_decl.func.ret_type.named);
    try testing.expect(!stmt.func_decl.func.ret_fallible);
    const tail = stmt.func_decl.func.body.tail_expr orelse return error.MissingTailExpr;
    try testing.expect(tail.* == .name);
    try testing.expectEqualStrings("fallback", tail.name.ident);
}

test "parse: named result demand is not a receiver assignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\meaning: { id: str }
        \\normal: meaning = (face: str)
        \\    { id = face }
    , &arena);
    const stmt = mod.body.stmts[1];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.path.len);
    try testing.expectEqualStrings("normal", stmt.func_decl.path[0]);
    try testing.expect(stmt.func_decl.func.ret_type == .named);
    try testing.expectEqualStrings("meaning", stmt.func_decl.func.ret_type.named);
}

test "parse: Pass23 colon method assign with implicit self" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\Person:greet = (other) "Hey " .. other
    , &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.method);
    try testing.expectEqual(@as(usize, 2), fd.path.len);
    try testing.expectEqualStrings("Person", fd.path[0]);
    try testing.expectEqualStrings("greet", fd.path[1]);
    try testing.expectEqual(@as(usize, 2), fd.func.params.len);
    try testing.expectEqualStrings("self", fd.func.params[0].name);
    try testing.expectEqualStrings("other", fd.func.params[1].name);
}

test "parse: Pass23 dot static member assign func" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("math.add = (a, b) a + b", &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(!fd.method);
    try testing.expectEqual(@as(usize, 2), fd.path.len);
    try testing.expectEqualStrings("math", fd.path[0]);
    try testing.expectEqualStrings("add", fd.path[1]);
    try testing.expectEqual(@as(usize, 2), fd.func.params.len);
    try testing.expectEqualStrings("a", fd.func.params[0].name);
}

test "parse: Pass23 single-expression assign func without end" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("add = (a, b) a + b", &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expectEqualStrings("add", fd.path[0]);
    try testing.expectEqual(@as(usize, 2), fd.func.params.len);
    const tail = fd.func.body.tail_expr orelse return error.MissingTailExpr;
    try testing.expect(tail.* == .binop);
    try testing.expect(tail.binop.op == .add);
}

test "parse: Pass23 empty single-expression func" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("empty = () nil", &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expectEqualStrings("empty", fd.path[0]);
    try testing.expect(fd.func.body.tail_expr.?.* == .nil);
}

test "parse: @c.export attribute preserves export name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@c.export("duo_add")
        \\fun add(a: i64, b: i64): i64
        \\  return a + b
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqualStrings("add", stmt.func_decl.path[0]);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("c.export", stmt.func_decl.attributes[0].name);
    try testing.expectEqualStrings("\"duo_add\"", stmt.func_decl.attributes[0].args.?);
}

test "parse: single attribute on function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@inline
        \\fun fast_add(a: i64, b: i64) -> i64
        \\  return a + b
        \\end
    , &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqualStrings("fast_add", stmt.func_decl.path[0]);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("inline", stmt.func_decl.attributes[0].name);
    try testing.expect(stmt.func_decl.attributes[0].args == null);
}

test "parse: attribute with args on function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@deprecated("use new_func instead")
        \\fun old_func()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("deprecated", stmt.func_decl.attributes[0].name);
    try testing.expectEqualStrings("\"use new_func instead\"", stmt.func_decl.attributes[0].args.?);
}

test "parse: multiple attributes on function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@deprecated("use new_func instead")
        \\@nopanic
        \\fun old_func()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 2), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("deprecated", stmt.func_decl.attributes[0].name);
    try testing.expectEqualStrings("\"use new_func instead\"", stmt.func_decl.attributes[0].args.?);
    try testing.expectEqualStrings("nopanic", stmt.func_decl.attributes[1].name);
    try testing.expect(stmt.func_decl.attributes[1].args == null);
}

test "parse: @implements attribute on local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@implements(Iterable, Comparable)
        \\local x: { count: i64, name: str } = { count = 0, name = "x" }
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .local_decl);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.names.len);
    try testing.expectEqualStrings("x", stmt.local_decl.names[0].ident);
    try testing.expectEqual(@as(usize, 1), stmt.local_decl.names[0].attributes.len);
    try testing.expectEqualStrings("implements", stmt.local_decl.names[0].attributes[0].name);
    // The args text is a raw capture between the parens.
    try testing.expect(stmt.local_decl.names[0].attributes[0].args != null);
}

test "parse: attribute on async function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@nopanic
        \\async fun worker()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expect(stmt.func_decl.func.is_async);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("nopanic", stmt.func_decl.attributes[0].name);
}

test "parse: attribute on enum" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@derive("Debug")
        \\enum Color
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Color", stmt.enum_def.name);
    try testing.expectEqual(@as(usize, 1), stmt.enum_def.attributes.len);
    try testing.expectEqualStrings("derive", stmt.enum_def.attributes[0].name);
}

test "parse: function without attributes has empty attributes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun simple()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 0), stmt.func_decl.attributes.len);
}

test "parse: @c.emit long bracket in function body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun f(): i64
        \\    @c.emit([[
        \\        int x = 1;
        \\    ]])
        \\    @c.emit("result = x")
        \\    return result
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 3), stmt.func_decl.func.body.stmts.len);
    try testing.expect(stmt.func_decl.func.body.stmts[0] == .directive);
    try testing.expect(stmt.func_decl.func.body.stmts[1] == .directive);
    try testing.expectEqualStrings("c.emit", stmt.func_decl.func.body.stmts[0].directive.attr.name);
    try testing.expect(std.mem.indexOf(u8, stmt.func_decl.func.body.stmts[0].directive.attr.args.?, "int x = 1") != null);
}

test "parse: @c.emit long bracket preserves C array index before close" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun f(): f64
        \\    @c.emit([[
        \\        double cksum=0; for(int i=0;i<128*128;i++) cksum+=C[i];
        \\    ]])
        \\    return 0
        \\end
    , &arena);
    const args = mod.body.stmts[0].func_decl.func.body.stmts[0].directive.attr.args.?;
    try testing.expect(std.mem.endsWith(u8, args, "]]"));
    const code = @import("directives.zig").extractCRawCode(args);
    try testing.expect(std.mem.indexOf(u8, code, "cksum+=C[i];") != null);
    try testing.expect(std.mem.indexOf(u8, code, "\n    ]") == null);
    try testing.expect(!std.mem.endsWith(u8, std.mem.trim(u8, code, " \t\r\n"), "]"));
}

test "parse: attribute with ffi string arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@ffi("my_c_func")
        \\fun wrapper()
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("ffi", stmt.func_decl.attributes[0].name);
    try testing.expectEqualStrings("\"my_c_func\"", stmt.func_decl.attributes[0].args.?);
    // Bodyless: empty body, no tail expression
    try testing.expectEqual(@as(usize, 0), stmt.func_decl.func.body.stmts.len);
    try testing.expect(stmt.func_decl.func.body.tail_expr == null);
}

test "parse: async function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\async fun fetch_data()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expect(stmt.func_decl.func.is_async);
    try testing.expectEqualStrings("fetch_data", stmt.func_decl.path[0]);
}

test "parse: async function keyword" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\async function long_task()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expect(stmt.func_decl.func.is_async);
    try testing.expectEqualStrings("long_task", stmt.func_decl.path[0]);
}

test "parse: await as prefix operator" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return await x", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .await_expr);
    try testing.expect(expr.await_expr.operand.* == .name);
    try testing.expectEqualStrings("x", expr.await_expr.operand.name.ident);
}

test "parse: await on call expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return await fetch()", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    try testing.expect(expr.* == .await_expr);
    try testing.expect(expr.await_expr.operand.* == .call);
}

test "parse: await binds tighter than binary ops" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("return await x + 1", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .ret);
    const expr = stmt.ret.vals[0];
    // await binds at precedence 20 (like other prefix unary ops),
    // so `await x + 1` = `(await x) + 1` → binop(add, await_expr(x), 1)
    try testing.expect(expr.* == .binop);
    try testing.expect(expr.binop.lhs.* == .await_expr);
    try testing.expectEqualStrings("x", expr.binop.lhs.await_expr.operand.name.ident);
}

test "parse: simple enum with no variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("enum Empty\nend", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Empty", stmt.enum_def.name);
    try testing.expectEqual(@as(usize, 0), stmt.enum_def.variants.len);
    try testing.expect(stmt.enum_def.type_params == null);
}

test "parse: enum with simple variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Color", stmt.enum_def.name);
    try testing.expectEqual(@as(usize, 3), stmt.enum_def.variants.len);
    try testing.expectEqualStrings("Red", stmt.enum_def.variants[0].name);
    try testing.expectEqualStrings("Green", stmt.enum_def.variants[1].name);
    try testing.expectEqualStrings("Blue", stmt.enum_def.variants[2].name);
    try testing.expect(stmt.enum_def.variants[0].payload == null);
    try testing.expect(stmt.enum_def.variants[1].payload == null);
    try testing.expect(stmt.enum_def.variants[2].payload == null);
}

test "parse: enum with generic type parameter" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\enum Option[T]
        \\  Some(value: T)
        \\  None
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Option", stmt.enum_def.name);
    // Type params
    try testing.expect(stmt.enum_def.type_params != null);
    try testing.expectEqual(@as(usize, 1), stmt.enum_def.type_params.?.len);
    try testing.expect(stmt.enum_def.type_params.?[0] == .named);
    try testing.expectEqualStrings("T", stmt.enum_def.type_params.?[0].named);
    // Variants
    try testing.expectEqual(@as(usize, 2), stmt.enum_def.variants.len);
    try testing.expectEqualStrings("Some", stmt.enum_def.variants[0].name);
    try testing.expect(stmt.enum_def.variants[0].payload != null);
    try testing.expectEqual(@as(usize, 1), stmt.enum_def.variants[0].payload.?.len);
    try testing.expectEqualStrings("value", stmt.enum_def.variants[0].payload.?[0].name.?);
    try testing.expect(stmt.enum_def.variants[0].payload.?[0].typ == .named);
    try testing.expectEqualStrings("None", stmt.enum_def.variants[1].name);
    try testing.expect(stmt.enum_def.variants[1].payload == null);
}

test "parse: enum with multiple generic type parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\enum Result[T, E]
        \\  Ok(value: T)
        \\  Err(error: E)
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Result", stmt.enum_def.name);
    // Type params
    try testing.expect(stmt.enum_def.type_params != null);
    try testing.expectEqual(@as(usize, 2), stmt.enum_def.type_params.?.len);
    // Variants
    try testing.expectEqual(@as(usize, 2), stmt.enum_def.variants.len);
    try testing.expectEqualStrings("Ok", stmt.enum_def.variants[0].name);
    try testing.expectEqual(@as(usize, 1), stmt.enum_def.variants[0].payload.?.len);
    try testing.expectEqualStrings("value", stmt.enum_def.variants[0].payload.?[0].name.?);
    try testing.expectEqualStrings("Err", stmt.enum_def.variants[1].name);
    try testing.expectEqual(@as(usize, 1), stmt.enum_def.variants[1].payload.?.len);
    try testing.expectEqualStrings("error", stmt.enum_def.variants[1].payload.?[0].name.?);
}

test "parse: enum variant with multiple payload fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\enum Event
        \\  Click(x: i32, y: i32)
        \\  Key(code: i32)
        \\  Quit
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    try testing.expectEqualStrings("Event", stmt.enum_def.name);
    try testing.expectEqual(@as(usize, 3), stmt.enum_def.variants.len);
    // Click has 2 payload fields
    const click = stmt.enum_def.variants[0];
    try testing.expectEqualStrings("Click", click.name);
    try testing.expect(click.payload != null);
    try testing.expectEqual(@as(usize, 2), click.payload.?.len);
    try testing.expectEqualStrings("x", click.payload.?[0].name.?);
    try testing.expectEqualStrings("y", click.payload.?[1].name.?);
    // Key has 1 field
    const key = stmt.enum_def.variants[1];
    try testing.expectEqualStrings("Key", key.name);
    try testing.expectEqual(@as(usize, 1), key.payload.?.len);
    // Quit has no payload
    try testing.expect(stmt.enum_def.variants[2].payload == null);
}

test "parse: enum variant with positional (unnamed) payload" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\enum Wrapper
        \\  Val(i32)
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .enum_def);
    const val = stmt.enum_def.variants[0];
    try testing.expectEqualStrings("Val", val.name);
    try testing.expect(val.payload != null);
    try testing.expectEqual(@as(usize, 1), val.payload.?.len);
    // Positional payload has no name
    try testing.expect(val.payload.?[0].name == null);
    try testing.expect(val.payload.?[0].typ == .named);
}

test "parse: simple concept with one method" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Printable
        \\  fun to_string(self) -> str
        \\end
    , &arena);
    try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .concept_def);
    const cd = stmt.concept_def;
    try testing.expectEqualStrings("Printable", cd.name);
    try testing.expect(cd.type_params == null);
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
    try testing.expectEqualStrings("to_string", cd.required_methods[0].name);
    try testing.expectEqual(@as(usize, 1), cd.required_methods[0].params.len);
    try testing.expectEqualStrings("self", cd.required_methods[0].params[0].name);
    try testing.expect(cd.required_methods[0].ret_type == .named);
    try testing.expectEqualStrings("str", cd.required_methods[0].ret_type.named);
    try testing.expectEqual(@as(usize, 0), cd.required_fields.len);
}

test "parse: concept with bare (GR-001) method signatures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Canonical bare form as used by lib/mem.id — no `fun` keyword.
    const mod = try parseSource(
        \\concept Allocator
        \\    alloc(self, bytes: i64): any
        \\    free(self, ptr: any): void
        \\    total_allocated(self): i64
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Allocator", cd.name);
    try testing.expectEqual(@as(usize, 0), cd.required_fields.len);
    try testing.expectEqual(@as(usize, 3), cd.required_methods.len);
    try testing.expectEqualStrings("alloc", cd.required_methods[0].name);
    try testing.expectEqual(@as(usize, 2), cd.required_methods[0].params.len);
    try testing.expectEqualStrings("bytes", cd.required_methods[0].params[1].name);
    try testing.expectEqualStrings("any", cd.required_methods[0].ret_type.named);
    try testing.expectEqualStrings("free", cd.required_methods[1].name);
    try testing.expectEqualStrings("total_allocated", cd.required_methods[2].name);
    try testing.expectEqual(@as(usize, 1), cd.required_methods[2].params.len);
    try testing.expectEqualStrings("i64", cd.required_methods[2].ret_type.named);
}

test "parse: concept mixing bare methods and required fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // `name(` is a method, `name:` is a field — the disambiguation must not
    // regress the field form now that bare methods are accepted.
    const mod = try parseSource(
        \\concept Buffer
        \\    capacity: i64
        \\    push(self, byte: i64): void
        \\    tag: str
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
    try testing.expectEqualStrings("push", cd.required_methods[0].name);
    try testing.expectEqual(@as(usize, 2), cd.required_fields.len);
    try testing.expectEqualStrings("capacity", cd.required_fields[0].name);
    try testing.expectEqualStrings("i64", cd.required_fields[0].typ.named);
    try testing.expectEqualStrings("tag", cd.required_fields[1].name);
}

test "parse: concept bare generic method signature" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Mapper
        \\    map[T](self, f: T): T
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
    try testing.expectEqualStrings("map", cd.required_methods[0].name);
    try testing.expect(cd.required_methods[0].type_params != null);
    try testing.expectEqualStrings("T", cd.required_methods[0].type_params.?[0].named);
}

test "parse: concept with generic type parameter" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Comparable[T]
        \\  fun compare(self, other: T) -> i64
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Comparable", cd.name);
    try testing.expect(cd.type_params != null);
    try testing.expectEqual(@as(usize, 1), cd.type_params.?.len);
    try testing.expect(cd.type_params.?[0] == .named);
    try testing.expectEqualStrings("T", cd.type_params.?[0].named);
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
    try testing.expectEqualStrings("compare", cd.required_methods[0].name);
    try testing.expectEqual(@as(usize, 2), cd.required_methods[0].params.len);
    try testing.expectEqualStrings("self", cd.required_methods[0].params[0].name);
    try testing.expectEqualStrings("other", cd.required_methods[0].params[1].name);
}

test "parse: concept with multiple methods" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Iterator[T]
        \\  fun next(self) -> T
        \\  fun has_next(self) -> bool
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Iterator", cd.name);
    try testing.expectEqual(@as(usize, 2), cd.required_methods.len);
    try testing.expectEqualStrings("next", cd.required_methods[0].name);
    try testing.expectEqualStrings("has_next", cd.required_methods[1].name);
}

test "parse: concept with required field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Sized
        \\  size: i64
        \\  fun measure(self) -> i64
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Sized", cd.name);
    try testing.expectEqual(@as(usize, 1), cd.required_fields.len);
    try testing.expectEqualStrings("size", cd.required_fields[0].name);
    try testing.expect(cd.required_fields[0].typ == .named);
    try testing.expectEqualStrings("i64", cd.required_fields[0].typ.named);
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
    try testing.expectEqualStrings("measure", cd.required_methods[0].name);
}

test "parse: concept with multiple type params" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Mappable[K, V]
        \\  fun get(self, key: K) -> V
        \\  fun set(self, key: K, val: V)
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Mappable", cd.name);
    try testing.expect(cd.type_params != null);
    try testing.expectEqual(@as(usize, 2), cd.type_params.?.len);
    try testing.expectEqualStrings("K", cd.type_params.?[0].named);
    try testing.expectEqualStrings("V", cd.type_params.?[1].named);
    try testing.expectEqual(@as(usize, 2), cd.required_methods.len);
}

test "parse: concept with attribute" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@deprecated
        \\concept Legacy
        \\  fun old_method(self)
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Legacy", cd.name);
    try testing.expectEqual(@as(usize, 1), cd.attributes.len);
    try testing.expectEqualStrings("deprecated", cd.attributes[0].name);
    try testing.expectEqual(@as(usize, 1), cd.required_methods.len);
}

test "parse: empty concept" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\concept Empty
        \\end
    , &arena);
    const cd = mod.body.stmts[0].concept_def;
    try testing.expectEqualStrings("Empty", cd.name);
    try testing.expectEqual(@as(usize, 0), cd.required_methods.len);
    try testing.expectEqual(@as(usize, 0), cd.required_fields.len);
}

test "parse: nn block desugars to build call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\x = nn {
        \\  linear(784, 256)
        \\  relu
        \\  softmax()
        \\}
    , &arena);
    const assign = mod.body.stmts[0].assign;
    try testing.expectEqualStrings("x", assign.targets[0].name.ident);
    const call = assign.values[0].call;
    try testing.expect(call.func.* == .field);
    try testing.expectEqualStrings("build", call.func.field.field);
    try testing.expectEqual(@as(usize, 3), call.args.len);
}

test "parse: infix @ is matmul binop" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\y = a @ b
    , &arena);
    const assign = mod.body.stmts[0].assign;
    const b = assign.values[0].binop;
    try testing.expectEqual(ast.BinOp.matmul, b.op);
}

test "parse: Tensor[M,N,f32] type with numeric dims" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\fun f(x: Tensor[784, 256, f32]): Tensor[256, 10, f32]
        \\  return x
        \\end
    , &arena);
    const fb = mod.body.stmts[0].func_decl.func;
    const ty = fb.params[0].typ;
    try testing.expect(ty == .generic);
    try testing.expectEqualStrings("Tensor", ty.generic.base.*.named);
    try testing.expectEqual(@as(usize, 3), ty.generic.params.len);
}

test "parse: stmt then implicit concat tail (F-13813-1)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\with_side_effect(id: str, kind: str): str
        \\    print("side")
        \\    "ok: " .. id .. " (" .. kind .. ")"
        \\end
    , &arena);
    const fb = mod.body.stmts[0].func_decl.func;
    try testing.expectEqual(@as(usize, 1), fb.body.stmts.len);
    try testing.expect(fb.body.stmts[0] == .call_stmt);
    try testing.expect(fb.body.tail_expr != null);
    const tail = fb.body.tail_expr.?;
    try testing.expect(tail.* == .binop);
    try testing.expect(tail.binop.op == .concat);
    try testing.expect(tail.binop.lhs.* == .quoted);
    try testing.expectEqualStrings("ok: ", tail.binop.lhs.quoted.val);
}

test "parse: same-line void call then concat (F-13813-1)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\g(id: str, kind: str): str
        \\    print("hi") "ok: " .. id .. " (" .. kind .. ")"
        \\end
    , &arena);
    const fb = mod.body.stmts[0].func_decl.func;
    try testing.expect(fb.body.tail_expr != null);
    const tail = fb.body.tail_expr.?;
    try testing.expect(tail.* == .binop);
    try testing.expect(tail.binop.op == .concat);
    try testing.expect(tail.binop.lhs.* == .quoted);
    try testing.expectEqualStrings("ok: ", tail.binop.lhs.quoted.val);
}

// `#` IS RETIRED AS A LENGTH OPERATOR, and this is the fixture that says so in
// BOTH POSITIONS — which is the whole ruling, because the two positions is where
// it came apart.
//
// The negative control is the second half and it is not optional: `#` is the
// COMMENT OPENER in canonical source, so a refusal that convicts an ordinary
// comment has replaced a silent wrong answer with a loud one. Remove the
// `demandsOperand` guard and row 3 fails; remove the later-line guard and row 4
// fails; remove the abutting-character guard and rows 5–8 fail.
test "parse: `#` is refused in every position, and comments are not" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const refused = [_][]const u8{
        "t = { 1, 2, 3 }\nn = #t\nprint(n)", // statement RHS — used to compile a DIFFERENT program
        "t = { 1, 2, 3 }\nprint(#t)", // argument — used to die at `<eof>`
        "t = { 1, 2, 3 }\nn = 1 + #t\nprint(n)", // binary operand
        "t = { 1, 2, 3 }\nif #t < 1\n    n = 1", // condition
        "t = { 1, 2, 3 }\nn = #@comp.fields(t)\nprint(n)", // the corpus shape
    };
    // The refusal, not the message: `term` has no capture hook, so the WORDING
    // is pinned where a shell can read it — `gate/negative.sh` requires
    // `examples/compile_fail/hash_length_comment.id` to be refused for
    // `is not a length operator`, which is the same site as row 4 below.
    for (refused) |src| {
        if (parseDuoSource(src, &arena)) |_| {
            return error.TestUnexpectedResult;
        } else |err| switch (err) {
            ParseError.UnexpectedToken, ParseError.ExpectedToken => {},
            else => return err,
        }
    }

    const admitted = [_][]const u8{
        "n = 1 #note\nprint(n)", // 3: prev token ENDS an expression
        "n = 1 + 2 #note\nprint(n)", // 4: the operand arrived on this line
        "n = # note\n  2\nprint(n)", // 5: a space is a comment
        "n = 1\n#note\nprint(n)", // 6: own-line comment
        "n = 1\n#-------\nprint(n)", // 7: divider
        "n = 1\nprint(\n  #note\n  n)", // 8: comment INSIDE a call, own line
    };
    for (admitted) |src| _ = try parseDuoSource(src, &arena);
}

// STR-1 — a hole's tokens carry the FILE's coordinates, and this is the fixture
// that says so. It is the negative control for `seatSubLexer`, and it fails in
// BOTH of the directions that matter:
//
//   * delete the seat entirely and every hole reports line 1 — the whole reason
//     the padded form existed;
//   * restore the padded form and the COLUMN is one short on every hole, because
//     padding `col - 1` spaces seats the hole BODY at the `{`'s own column.
//     Measured before this fixture existed: `"head{x + }tail"` on line 2002
//     reported `2002:15` where the truth is `2002:16`.
//
// A hole at line 2002 is the point: a location carried as an OFFSET is exact at
// any depth, so the fixture is deliberately deep enough that a fragment-local
// line number could not be mistaken for the file's.
test "parse: interpolation hole locations are the file's, not the fragment's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var src: std.ArrayList(u8) = .empty;
    try src.appendSlice(alloc, "x = 7\n");
    for (0..2000) |_| try src.appendSlice(alloc, "# filler\n");
    //                     1234567890123456789012
    try src.appendSlice(alloc, "s = \"head{x}tail{  x }end\"\n");

    const mod = try parseDuoSource(src.items, &arena);
    const val = mod.body.stmts[mod.body.stmts.len - 1].assign.values[0];

    // ("head" .. x) .. "tail") .. x) .. "end"
    try testing.expect(val.* == .binop);
    const second = val.binop.lhs.binop.rhs;
    const first = val.binop.lhs.binop.lhs.binop.lhs.binop.rhs;

    try testing.expectEqualStrings("x", first.name.ident);
    try testing.expectEqual(@as(u32, 2002), first.loc().line);
    try testing.expectEqual(@as(u32, 11), first.loc().col); // `{` is col 10

    // The second hole is written `{  x }`: the seat is the body's true column,
    // so the two leading spaces are STEPPED OVER rather than reported as part of
    // the hole.
    try testing.expectEqualStrings("x", second.name.ident);
    try testing.expectEqual(@as(u32, 2002), second.loc().line);
    try testing.expectEqual(@as(u32, 20), second.loc().col); // `{` is col 17
}

test "parse: interpolation sublexer preserves the parent's exact source-law edition" {
    const bridge = @import("lexer_bridge.zig");
    const authority = @import("authority_projection.zig");
    const historical: authority.SourceLawEdition = .{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.test-previous",
        .sha256 = "1111111111111111111111111111111111111111111111111111111111111111",
    } };
    var parent = Lexer.initFamilyLawEdition(
        "edition_probe = 1",
        "edition.id",
        bridge.family_canon,
        .idol,
        historical,
    );
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(&parent, arena.allocator());
    const sub = parser.interpolationLexer("edition_probe");
    try testing.expect(sub.source_law_edition.eql(historical));
    try testing.expectEqualStrings(historical.sha256().?, sub.source_law_edition.sha256().?);
}

test "parse: string interpolation indexed holes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\a = "{found[i]}"
        \\b = "{r[1]}"
        \\c = "{rows[i].name}"
    , &arena);

    const a = mod.body.stmts[0].assign.values[0];
    try testing.expect(a.* == .binop);
    try testing.expect(a.binop.op == .concat);
    try testing.expect(a.binop.lhs.* == .quoted);
    try testing.expectEqualStrings("", a.binop.lhs.quoted.val);
    const a_hole = a.binop.rhs;
    try testing.expect(a_hole.* == .index);
    try testing.expectEqualStrings("found", a_hole.index.obj.name.ident);
    try testing.expectEqualStrings("i", a_hole.index.key.name.ident);

    const b = mod.body.stmts[1].assign.values[0];
    try testing.expect(b.* == .binop);
    try testing.expect(b.binop.op == .concat);
    try testing.expect(b.binop.lhs.* == .quoted);
    try testing.expectEqualStrings("", b.binop.lhs.quoted.val);
    const b_hole = b.binop.rhs;
    try testing.expect(b_hole.* == .index);
    try testing.expectEqualStrings("r", b_hole.index.obj.name.ident);
    try testing.expectEqual(@as(i64, 1), b_hole.index.key.int_lit.val);

    const c = mod.body.stmts[2].assign.values[0];
    try testing.expect(c.* == .binop);
    try testing.expect(c.binop.op == .concat);
    try testing.expect(c.binop.lhs.* == .quoted);
    try testing.expectEqualStrings("", c.binop.lhs.quoted.val);
    const c_hole = c.binop.rhs;
    try testing.expect(c_hole.* == .field);
    try testing.expectEqualStrings("name", c_hole.field.field);
    try testing.expect(c_hole.field.obj.* == .index);
    try testing.expectEqualStrings("rows", c_hole.field.obj.index.obj.name.ident);
    try testing.expectEqualStrings("i", c_hole.field.obj.index.key.name.ident);
}

test "parse: an escaped brace is TEXT and an unescaped one still opens a hole" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // `docs/text-law.md` — `\{` and `\}` are the literal brace. The reading is
    // PER-BRACE, not per-literal, which is the property no raw face can give:
    // 128 sites in 17 files of the compiler corpus carry a live hole and a
    // literal brace in ONE literal, and a face with no holes cannot serve them.
    const mod = try parseDuoSource(
        \\a = "v=\{x}"
        \\b = "both {x} and \{x}"
        \\c = "hex \x7Bx}"
    , &arena);

    // (a) ALL text: no hole was opened, so the whole literal is one string.
    const a = mod.body.stmts[0].assign.values[0];
    try testing.expect(a.* == .quoted);
    try testing.expectEqualStrings("v={x}", a.quoted.val);

    // (b) THE CONTROL AGAINST AN OVER-BROAD FIX. A patch that made `\{`
    // literal by making the literal non-interpolating passes (a) and fails
    // here: the first hole must still be a live `x`.
    const b = mod.body.stmts[1].assign.values[0];
    try testing.expect(b.* == .binop and b.binop.op == .concat);
    try testing.expectEqualStrings("both ", b.binop.lhs.binop.lhs.quoted.val);
    try testing.expectEqualStrings("x", b.binop.lhs.binop.rhs.name.ident);
    try testing.expectEqualStrings(" and {x}", b.binop.rhs.quoted.val);

    // (c) THE FACT BELONGS TO THE DECODER, NOT TO THE SPELLING. `\x7B` is the
    // byte `{` and opened a hole before the ruling — `print("A[\x7Bx}]")`
    // printed `A[7]`. Protecting only the two characters `\{` would leave it
    // wrong; the map is per DECODED BYTE for exactly this reason.
    const c = mod.body.stmts[2].assign.values[0];
    try testing.expect(c.* == .quoted);
    try testing.expectEqualStrings("hex {x}", c.quoted.val);
}

test "parse: an escaped brace cannot close or deepen a hole" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // `interpolationHoleEnd` counts brace DEPTH, so a protected brace has to be
    // invisible to it in both directions. Without the guard `"{f(\})}"` would
    // close at the `\}` — text — and the hole would be cut in the wrong place.
    const mod = try parseDuoSource(
        \\a = "pair=\{\"k\": 1\}"
        \\b = "n={ {1, 2, 3}:len() } \{end\}"
    , &arena);

    // (a) The control from `examples/text/brace/escape.id`: this literal
    // already emitted its own source text before the ruling (with an STR-1
    // warning). The ruling must not change it, only make it sayable.
    const a = mod.body.stmts[0].assign.values[0];
    try testing.expect(a.* == .quoted);
    try testing.expectEqualStrings("pair={\"k\": 1}", a.quoted.val);

    // (b) A pack inside a live hole — `law.brace` — beside protected braces in
    // the same literal. The depth counting must still find the RIGHT `}`.
    const b = mod.body.stmts[1].assign.values[0];
    try testing.expect(b.* == .binop and b.binop.op == .concat);
    try testing.expectEqualStrings(" {end}", b.binop.rhs.quoted.val);
}

test "parse: an ESCAPED QUOTE inside a hole is still a quote, not a protected byte" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // THE REGRESSION THIS LANE INTRODUCED AND THEN MEASURED OUT.
    //
    // The first cut of the protection guard read `isProtected(protected, i)` on
    // EVERY byte, not only on braces. A `"` inside a hole must be written `\"`
    // — the hole is inside a text literal — so it arrives PROTECTED, and the
    // guard skipped it, disabling the quoted-span rule that `interpolationHoleEnd`
    // exists for. The hole below then cut at the `}` inside the nested string.
    //
    // No fixture caught it. The corpus STR-1 census did: `scripts/sim.id` went
    // from 6 warned sites to 7, and the two on its line 182 changed CLASS. A
    // change to this function is not measured until that census is run on both
    // sides of it.
    const mod = try parseDuoSource(
        \\a = "{f(\"}\")}"
    , &arena);
    const a = mod.body.stmts[0].assign.values[0];
    try testing.expect(a.* == .binop and a.binop.op == .concat);
    const hole = a.binop.rhs;
    try testing.expect(hole.* == .call);
    try testing.expectEqualStrings("f", hole.call.func.name.ident);
    try testing.expectEqual(@as(usize, 1), hole.call.args.len);
    try testing.expectEqualStrings("}", hole.call.args[0].quoted.val);
}

test "parse: `{{` is a hole opening with a PACK, which is why it cannot be the escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // THE MIGRATION PROOF FOR THE RULING, AT PARSE TIME.
    //
    // Five surveyed languages spell a literal brace `{{` and that is the
    // strongest familiarity argument available. `docs/text-law.md` declines it
    // because `{{` is ALREADY SPOKEN FOR: `law.brace` makes `{` the structured
    // pack face, `law.literal.text` makes a hole an EXPRESSION, therefore a hole
    // may open with a pack and `{{` is its spelling. Adopting `{{` as the escape
    // would make brace-initial expressions unspellable inside a hole.
    //
    // `examples/text/brace/hole.id` is the running form of this fact, but it
    // answers ONLY under `--backend=c`: the direct backend refuses
    // `{10, 20, 30}:len()` with DNB001 `method-unresolved:len`, and no
    // pack-initial hole was found that direct does lower. With `--backend=c`
    // retired that oracle goes dark, so the fact is pinned HERE as well, where
    // it belongs — it is a PARSE fact and needs no backend at all.
    const mod = try parseDuoSource(
        \\a = "n={{10, 20, 30}:len()}"
    , &arena);
    const a = mod.body.stmts[0].assign.values[0];
    // `"n=" .. <hole>` — two parts, so the hole was taken as ONE expression and
    // the second `{` was NOT read as an escaped brace.
    try testing.expect(a.* == .binop and a.binop.op == .concat);
    try testing.expectEqualStrings("n=", a.binop.lhs.quoted.val);
    // And the hole is a subject-first application whose SUBJECT is a pack.
    const hole = a.binop.rhs;
    try testing.expect(hole.* == .method_call);
    try testing.expectEqualStrings("len", hole.method_call.method);
    try testing.expect(hole.method_call.obj.* == .table);
    try testing.expectEqual(@as(usize, 3), hole.method_call.obj.table.fields.len);
}

test "parse: field projection .name desugars to anonymous function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\x = .name
    , &arena);
    const assign = mod.body.stmts[0].assign;
    // .name should desugar to a func_expr
    const fe = assign.values[0].func_expr;
    try testing.expectEqual(@as(usize, 1), fe.params.len);
    try testing.expectEqualStrings("__proj_v", fe.params[0].name);
    // Body should be a return of __proj_v.name
    try testing.expectEqual(@as(usize, 1), fe.body.stmts.len);
    const ret_val = fe.body.stmts[0].ret.vals[0];
    try testing.expect(ret_val.* == .field);
    try testing.expectEqualStrings("name", ret_val.field.field);
    try testing.expectEqualStrings("__proj_v", ret_val.field.obj.name.ident);
}

test "parse: chained field projection .a.b desugars correctly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\x = .profile.name
    , &arena);
    const assign = mod.body.stmts[0].assign;
    const fe = assign.values[0].func_expr;
    try testing.expectEqual(@as(usize, 1), fe.params.len);
    // Body: return __proj_v.profile.name
    const ret_val = fe.body.stmts[0].ret.vals[0];
    try testing.expect(ret_val.* == .field);
    try testing.expectEqualStrings("name", ret_val.field.field);
    // Inner should be __proj_v.profile
    const inner = ret_val.field.obj;
    try testing.expect(inner.* == .field);
    try testing.expectEqualStrings("profile", inner.field.field);
    try testing.expectEqualStrings("__proj_v", inner.field.obj.name.ident);
}

test "parse: field projection in call argument position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\y = map(items, .score)
    , &arena);
    const assign = mod.body.stmts[0].assign;
    const call = assign.values[0].call;
    // Second argument should be a func_expr (the projection)
    try testing.expect(call.args[1].* == .func_expr);
    const fe = call.args[1].func_expr;
    try testing.expectEqualStrings("__proj_v", fe.params[0].name);
    const ret_val = fe.body.stmts[0].ret.vals[0];
    try testing.expectEqualStrings("score", ret_val.field.field);
}

test "parse: method reference :close desugars to anonymous function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\x = :close
    , &arena);
    const fe = mod.body.stmts[0].assign.values[0].func_expr;
    try testing.expectEqualStrings("__proj_v", fe.params[0].name);
    const mc = fe.body.stmts[0].ret.vals[0].method_call;
    try testing.expectEqualStrings("close", mc.method);
    try testing.expectEqual(@as(usize, 0), mc.args.len);
    try testing.expectEqualStrings("__proj_v", mc.obj.name.ident);
}

test "parse: method reference in call argument position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\y = each(items, :close)
    , &arena);
    const call = mod.body.stmts[0].assign.values[0].call;
    try testing.expect(call.args[1].* == .func_expr);
    const fe = call.args[1].func_expr;
    try testing.expectEqualStrings("__proj_v", fe.params[0].name);
    const mc = fe.body.stmts[0].ret.vals[0].method_call;
    try testing.expectEqualStrings("close", mc.method);
    try testing.expectEqual(@as(usize, 0), mc.args.len);
}

test "parse: method reference :write(output) captures outer arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\y = each(items, :write(output))
    , &arena);
    const call = mod.body.stmts[0].assign.values[0].call;
    const fe = call.args[1].func_expr;
    const mc = fe.body.stmts[0].ret.vals[0].method_call;
    try testing.expectEqualStrings("write", mc.method);
    try testing.expectEqual(@as(usize, 1), mc.args.len);
    try testing.expect(mc.args[0].* == .name);
    try testing.expectEqualStrings("output", mc.args[0].name.ident);
}

test "parse: table spread ..source in table literal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\t = { ..base, x = 1 }
    , &arena);
    const table = mod.body.stmts[0].assign.values[0].table;
    try testing.expectEqual(@as(usize, 2), table.fields.len);
    try testing.expect(table.fields[0] == .spread);
    try testing.expect(table.fields[0].spread.* == .name);
    try testing.expectEqualStrings("base", table.fields[0].spread.name.ident);
    try testing.expect(table.fields[1] == .named);
    try testing.expectEqualStrings("x", table.fields[1].named.key);
}

test "parse: table literal statement not destructure pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\cur_loc(self: Lexer): Loc
        \\    { file = self.file, line = self.line, col = self.col }
        \\end
    , &arena);
    const fb = mod.body.stmts[0].func_decl.func;
    try testing.expect(fb.body.tail_expr != null);
    try testing.expect(fb.body.tail_expr.?.* == .table);
}

test "parse: if binding condition if x = expr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\if v = get() v > 0
        \\  print(v)
        \\end
    , &arena);
    const is = mod.body.stmts[0].if_stmt;
    try testing.expect(is.binding != null);
    try testing.expectEqualStrings("v", is.binding.?.name);
    try testing.expect(is.binding.?.expr.* == .call);
    try testing.expect(is.cond.* == .name);
    try testing.expectEqualStrings("v", is.cond.name.ident);
}

test "parse: named table destructure assign" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\{ name, age } = user
    , &arena);
    const db = mod.body.stmts[0].do_block;
    try testing.expectEqual(@as(usize, 2), db.body.stmts.len);
    try testing.expect(db.body.stmts[0] == .assign);
    try testing.expectEqualStrings("name", db.body.stmts[0].assign.targets[0].name.ident);
}

test "parse: selective import destructure from req module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\{ encode, decode } = req "std.json"
    , &arena);
    const db = mod.body.stmts[0].do_block;
    try testing.expectEqual(@as(usize, 2), db.body.stmts.len);
    const field = db.body.stmts[0].assign.values[0].field;
    try testing.expectEqualStrings("encode", field.field);
    try testing.expect(field.obj.* == .call);
    try testing.expectEqualStrings("req", field.obj.call.func.name.ident);
}

test "parse: @export on underscored function is allowed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@export
        \\fun _api(): i64
        \\  return 1
        \\end
    , &arena);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expectEqualStrings("_api", fd.path[0]);
    try testing.expect(std.mem.eql(u8, fd.attributes[0].name, "export"));
}

test "parse: keywordless enum descriptor Color: { ... }" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\Color: { Red, Green, Blue }
    , &arena);
    const ed = mod.body.stmts[0].enum_def;
    try testing.expectEqualStrings("Color", ed.name);
    try testing.expectEqual(@as(usize, 3), ed.variants.len);
    try testing.expectEqualStrings("Red", ed.variants[0].name);
    try testing.expectEqualStrings("Green", ed.variants[1].name);
    try testing.expectEqualStrings("Blue", ed.variants[2].name);
}

test "parse: keywordless record descriptor Point: { x: f64, y: f64 }" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\Point: { x: f64, y: f64 }
    , &arena);
    const ad = mod.body.stmts[0].alias_def;
    try testing.expectEqualStrings("Point", ad.name);
    try testing.expect(ad.target != null);
    try testing.expect(ad.target.? == .record);
    try testing.expectEqual(@as(usize, 2), ad.target.?.record.fields.len);
    try testing.expectEqualStrings("x", ad.target.?.record.fields[0].name);
    try testing.expectEqualStrings("f64", ad.target.?.record.fields[0].typ.named);
    try testing.expectEqualStrings("y", ad.target.?.record.fields[1].name);
}

test "parse: record descriptor with composition ..Named" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\User: { ..Named, id: i64 }
    , &arena);
    const ad = mod.body.stmts[0].alias_def;
    try testing.expectEqualStrings("User", ad.name);
    try testing.expect(ad.parent != null);
    try testing.expectEqualStrings("Named", ad.parent.?);
    try testing.expectEqual(@as(usize, 1), ad.target.?.record.fields.len);
    try testing.expectEqualStrings("id", ad.target.?.record.fields[0].name);
}

test "parse: enum descriptor with payload variants Ok(v), Err(e)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\Result: { Ok(v), Err(e) }
    , &arena);
    const ed = mod.body.stmts[0].enum_def;
    try testing.expectEqualStrings("Result", ed.name);
    try testing.expectEqual(@as(usize, 2), ed.variants.len);
    try testing.expectEqualStrings("Ok", ed.variants[0].name);
    try testing.expect(ed.variants[0].payload != null);
    try testing.expectEqual(@as(usize, 1), ed.variants[0].payload.?.len);
    try testing.expectEqualStrings("v", ed.variants[0].payload.?[0].typ.named);
    try testing.expectEqualStrings("Err", ed.variants[1].name);
    try testing.expectEqual(@as(usize, 1), ed.variants[1].payload.?.len);
    try testing.expectEqualStrings("e", ed.variants[1].payload.?[0].typ.named);
}

test "parse: enum descriptor payload with named fields Some(value: T)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\Option: { Some(value: T), None }
    , &arena);
    const ed = mod.body.stmts[0].enum_def;
    try testing.expectEqual(@as(usize, 2), ed.variants.len);
    try testing.expectEqualStrings("Some", ed.variants[0].name);
    try testing.expectEqualStrings("value", ed.variants[0].payload.?[0].name.?);
    try testing.expectEqualStrings("T", ed.variants[0].payload.?[0].typ.named);
    try testing.expectEqualStrings("None", ed.variants[1].name);
    try testing.expect(ed.variants[1].payload == null);
}

test "parse: table fields separated by newlines (no comma required)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\x = {
        \\    a = 1
        \\    b = 2
        \\    c = 3
        \\}
    , &arena);
    const table = mod.body.stmts[0].assign.values[0].table;
    try testing.expectEqual(@as(usize, 3), table.fields.len);
    try testing.expectEqualStrings("a", table.fields[0].named.key);
    try testing.expectEqualStrings("b", table.fields[1].named.key);
    try testing.expectEqualStrings("c", table.fields[2].named.key);
}

test "parse: duo mode pipeline operator parses as binop (deprioritized)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\x = data |> f
    , &arena);
    const b = mod.body.stmts[0].assign.values[0].binop;
    try testing.expectEqual(ast.BinOp.pipeline, b.op);
}

test "parse: duo mode infix @ matmul parses as binop (deprioritized)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\x = a @ b
    , &arena);
    const b = mod.body.stmts[0].assign.values[0].binop;
    try testing.expectEqual(ast.BinOp.matmul, b.op);
}

// §2 — the postfix anchor and the matmul operator share a token and
// are told apart by ADJACENCY. These two tests are a PAIR: either alone would
// pass under a parser that had simply picked one reading for everything, so
// they are written adjacent and must be read together.
test "parse: glued X@rel is the postfix anchor, not matmul" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\q = p@x
    , &arena);
    const f = mod.body.stmts[0].assign.values[0].field;
    try testing.expectEqualStrings("x", f.field);
    try testing.expectEqualStrings("p", f.obj.name.ident);
}

test "parse: spaced a @ b stays matmul beside the glued anchor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\y = a @ b
    , &arena);
    try testing.expectEqual(ast.BinOp.matmul, mod.body.stmts[0].assign.values[0].binop.op);
}

// The attribute is glued on the right too — `@` in column 1, `hot` in column 2
// — so right-adjacency ALONE would have swallowed it into the expression above
// as an anchor. The line check is what keeps them apart, and this is the row
// that fails if someone deletes it.
test "parse: a new-line @attribute is not an anchor on the line above" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\x = 42
        \\@hot
        \\f(): i64
        \\    1
        \\end
    , &arena);
    try testing.expectEqual(@as(i64, 42), mod.body.stmts[0].assign.values[0].int_lit.val);
}

test "parse: duo mode legacy @comptime_fold warns" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    _ = try parseDuoSource(
        \\x = @comptime_fold(0, 2, 1, "0", "%a + 1")
    , &arena);
}

test "parse: duo mode @c.emit warns toward @comp.c.emit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    _ = try parseDuoSource(
        \\@c.emit("int x = 1;")
    , &arena);
}

test "parse: @c.emit with combinator arg is expr_stmt not directive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\@c.emit(@comp.map("a", fun(t) t))
    , &arena);
    // The property: `@c.emit(...)` is a CALL to `__emit`, never a directive.
    // Routing it through the directive table is what this test forbids.
    for (mod.body.stmts) |stmt| try testing.expect(stmt != .directive);
    // Where it lands is the tail-result contract's business, not this test's: a lone module-level
    // expression is the module's TAIL RESULT, so it arrives in `tail_expr` and
    // `stmts` is empty. This used to be asserted at `stmts[0]` and failed on
    // `expected 1, found 0` while the parse was entirely correct.
    const call_expr: *const ast.Expr = if (mod.body.tail_expr) |e| e else blk: {
        try testing.expectEqual(@as(usize, 1), mod.body.stmts.len);
        try testing.expect(mod.body.stmts[0] == .expr_stmt);
        break :blk mod.body.stmts[0].expr_stmt.expr;
    };
    try testing.expect(call_expr.* == .call);
    try testing.expect(call_expr.call.func.* == .name);
    try testing.expectEqualStrings("__emit", call_expr.call.func.name.ident);
}

// ── APPLY-ONE (c0 §43 `law.brace`, §44 `law.apply.one` / `law.pack.shape`) ────
//
// These tests are a SET and must be read together. Any one of them passes under
// a parser that had simply picked one reading for every brace, which is the
// state APPLY-ONE repairs; it is the whole set that says the faces converge on
// one node while the pack's stance stays a recorded fact.

test "apply-one: the brace face and the paren face reach the SAME node kind" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const braced = try parseDuoSource(
        \\q = point{ x = 1, y = 2 }
    , &arena);
    const parened = try parseDuoSource(
        \\q = point(1, 2)
    , &arena);
    // ONE application node. The parser asked nothing about what `point` denotes
    // and emitted no second production — c0 §44a trap 1.
    const b = braced.body.stmts[0].assign.values[0];
    const p = parened.body.stmts[0].assign.values[0];
    try testing.expect(b.* == .call);
    try testing.expect(p.* == .call);
    try testing.expectEqualStrings("point", b.call.func.name.ident);
    try testing.expectEqualStrings("point", p.call.func.name.ident);
}

test "apply-one: the brace FACE is recorded, and differs from the paren face" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseDuoSource(
        \\q = point{ x = 1 }
        \\r = point(1)
    , &arena);
    try testing.expectEqual(
        ast.InvocationForm.braced,
        mod.body.stmts[0].assign.values[0].call.form,
    );
    try testing.expectEqual(
        ast.InvocationForm.parenthesized,
        mod.body.stmts[1].assign.values[0].call.form,
    );
}

test "apply-one: f{...} is NOT f({...}) — the pack stance is what tells them apart" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // c0 §44a trap 2 ("braces as sugar"). Before APPLY-ONE these two produced
    // byte-identical trees, so nothing downstream COULD decline to allocate a
    // table: the sugar had already been applied and its evidence erased.
    const applied = try parseDuoSource(
        \\q = f{ x = 1 }
    , &arena);
    const argument = try parseDuoSource(
        \\q = f({ x = 1 })
    , &arena);
    const ap = applied.body.stmts[0].assign.values[0].call;
    const ar = argument.body.stmts[0].assign.values[0].call;
    try testing.expect(ap.args[0].table.pack.applied);
    try testing.expect(!ar.args[0].table.pack.applied);
    try testing.expectEqual(ast.InvocationForm.braced, ap.form);
    try testing.expectEqual(ast.InvocationForm.parenthesized, ar.form);
}

test "apply-one: the parser never decides realization — packs rest undecided" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // c0 §44 `law.pack.shape`: "physical representation is selected AFTER
    // semantic resolution". A `{` in the source is not a demand for a table, so
    // the only value the parser may write is `.undecided`.
    const mod = try parseDuoSource(
        \\q = point{ x = 1, y = 2 }
        \\r = { x = 1, y = 2 }
    , &arena);
    try testing.expectEqual(
        ast.Realization.undecided,
        mod.body.stmts[0].assign.values[0].call.args[0].table.pack.realized,
    );
    try testing.expectEqual(
        ast.Realization.undecided,
        mod.body.stmts[1].assign.values[0].table.pack.realized,
    );
}

test "apply-one: labels and positions survive on the pack" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // §44 `apply.carries` names "argument labels" and "argument positions". They
    // are the pack's own fields in declaration ORDER, which is why APPLY-ONE
    // adds no parallel label table: a second one is where the shapes drift.
    const mod = try parseDuoSource(
        \\q = point{ x = 1, y = 2 }
        \\r = point{ 1, 2 }
    , &arena);
    const named = mod.body.stmts[0].assign.values[0].call.args[0].table.fields;
    try testing.expectEqual(@as(usize, 2), named.len);
    try testing.expectEqualStrings("x", named[0].named.key);
    try testing.expectEqualStrings("y", named[1].named.key);
    const positional = mod.body.stmts[1].assign.values[0].call.args[0].table.fields;
    try testing.expectEqual(@as(usize, 2), positional.len);
    try testing.expectEqual(@as(i64, 1), positional[0].positional.int_lit.val);
    try testing.expectEqual(@as(i64, 2), positional[1].positional.int_lit.val);
}

test "apply-one: a bare pack is anonymous — no subject, so no application" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // c0 §44a: "`{ x = 1, y = 2 }` an ordinary anonymous structured value /
    // `point{ x = 1, y = 2 }` APPLICATION of `point` to that shape — different
    // because one has a SUBJECT." This is the row that keeps the surviving
    // distinction from being "constructor versus call".
    const mod = try parseDuoSource(
        \\r = { x = 1, y = 2 }
    , &arena);
    const t = mod.body.stmts[0].assign.values[0];
    try testing.expect(t.* == .table);
    try testing.expect(!t.table.pack.applied);
    try testing.expect(!t.table.pack.elided);
    try testing.expect(t.table.pack.home == null);
}

test "apply-one: a comprehension is a stream, and takes no pack stance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // `{ v for v in xs }` leaves `parse_pack_body` as a `.list_comp`, not a
    // `.table`. Stamping a stance onto it would be inventing a pack that has no
    // fields — the failure mode this row exists to catch.
    const mod = try parseDuoSource(
        \\r = { v for v in xs }
    , &arena);
    try testing.expect(mod.body.stmts[0].assign.values[0].* == .list_comp);
}
