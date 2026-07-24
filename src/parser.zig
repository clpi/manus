const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TK = @import("lexer.zig").TokenKind;
const ast = @import("ast.zig");
const types = @import("types.zig");
const term = @import("term.zig");
const debug_trace = @import("debug_trace.zig");

pub const ParseError = error{
    UnexpectedToken,
    ExpectedToken,
} || @import("lexer.zig").LexError || Allocator.Error;

pub const Parser = struct {
    lex: *Lexer,
    alloc: Allocator,
    /// Incremented while parsing a match arm body. When > 0, assignment
    /// right-hand sides use the restricted scrutinee parser so that `[` at
    /// the start of the next arm is not greedily consumed as an index suffix.
    match_arm_depth: u32 = 0,
    quote_depth: u32 = 0,
    /// When true (.duo source), emit deprecation warnings for `then` and `local`.
    duo_mode: bool = false,

    deferred_hint_attrs: std.ArrayList(ast.Attribute) = .empty,

    pub fn init(lex: *Lexer, alloc: Allocator) Parser {
        return .{ .lex = lex, .alloc = alloc };
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
            // Parse "inline", "cold", "hot", "noinline", "unroll(N)", etc.
            // Split at '(' for args
            if (std.mem.indexOfScalar(u8, hint_text, '(')) |paren_pos| {
                const name = hint_text[0..paren_pos];
                const end_paren = std.mem.indexOfScalar(u8, hint_text, ')') orelse hint_text.len;
                const args = hint_text[paren_pos + 1 .. end_paren];
                attrs[i] = .{ .name = name, .args = args };
            } else {
                attrs[i] = .{ .name = hint_text, .args = null };
            }
        }
        return attrs[0..count];
    }

    /// Turn `--- @build.*` / `--- @debug.*` comment hints into module directive statements.
    fn flush_module_hint_directives(self: *Parser, stmts: *std.ArrayList(ast.Stmt)) ParseError!void {
        const directives_mod = @import("directives.zig");
        while (self.lex.hasPendingHints()) {
            const hint_attrs = try self.consumeLexerHints();
            defer self.alloc.free(hint_attrs);
            var emitted = false;
            for (hint_attrs) |attr| {
                if (directives_mod.isBuildDirective(attr.name) or directives_mod.isDebugDirective(attr.name)) {
                    const loc = (try self.pk()).loc;
                    try stmts.append(self.alloc, .{ .directive = .{ .loc = loc, .attr = attr } });
                    emitted = true;
                } else {
                    try self.deferred_hint_attrs.append(self.alloc, attr);
                }
            }
            if (!emitted) break;
        }
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
        return self.lex.next();
    }

    fn expect(self: *Parser, kind: TK) ParseError!Token {
        const tok = try self.adv();
        if (tok.kind != kind) {
            term.locErr(tok.loc, "expected '{s}', got '{s}'", .{
                kind.spelling(), tok.kind.spelling(),
            });
            return ParseError.ExpectedToken;
        }
        return tok;
    }

    fn eat(self: *Parser, kind: TK) ParseError!?Token {
        if ((try self.pk()).kind == kind) return try self.adv();
        return null;
    }

    fn check(self: *Parser, kind: TK) ParseError!bool {
        return (try self.pk()).kind == kind;
    }

    fn new_expr(self: *Parser, e: ast.Expr) ParseError!*ast.Expr {
        const p2 = try self.alloc.create(ast.Expr);
        p2.* = e;
        return p2;
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
        while (try self.eat(.pipe) != null) {
            _ = try self.parse_type_primary();
            while (try self.eat(.lbracket) != null) {
                if (!(try self.check(.rbracket))) {
                    _ = try self.parse_type();
                    while (try self.eat(.comma) != null) _ = try self.parse_type();
                }
                _ = try self.expect(.rbracket);
            }
        }
        return base;
    }

    fn parse_type_primary(self: *Parser) ParseError!ast.TypeExpr {
        const tok = try self.pk();
        return switch (tok.kind) {
            .kw_i8 => {
                _ = try self.adv();
                return .{ .named = "i8" };
            },
            .kw_i16 => {
                _ = try self.adv();
                return .{ .named = "i16" };
            },
            .kw_i32 => {
                _ = try self.adv();
                return .{ .named = "i32" };
            },
            .kw_i64 => {
                _ = try self.adv();
                return .{ .named = "i64" };
            },
            .kw_u8 => {
                _ = try self.adv();
                return .{ .named = "u8" };
            },
            .kw_u16 => {
                _ = try self.adv();
                return .{ .named = "u16" };
            },
            .kw_u32 => {
                _ = try self.adv();
                return .{ .named = "u32" };
            },
            .kw_u64 => {
                _ = try self.adv();
                return .{ .named = "u64" };
            },
            .kw_f32 => {
                _ = try self.adv();
                return .{ .named = "f32" };
            },
            .kw_f64 => {
                _ = try self.adv();
                return .{ .named = "f64" };
            },
            .kw_bool => {
                _ = try self.adv();
                return .{ .named = "bool" };
            },
            .kw_void => {
                _ = try self.adv();
                return .{ .named = "void" };
            },
            .kw_str => {
                _ = try self.adv();
                return .{ .named = "str" };
            },
            .at => {
                const attr = try self.parse_one_attribute();
                if (!std.mem.eql(u8, attr.name, "c.type")) {
                    term.locErr(tok.loc, "expected @c.type(...) in type position, got '@{s}'", .{attr.name});
                    return ParseError.UnexpectedToken;
                }
                const cname = strip_quotes(attr.args orelse "");
                return .{ .named = try std.mem.concat(self.alloc, u8, &.{ types.c_type_marker_prefix, cname }) };
            },
            .name => {
                const t = try self.adv();
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
                        _ = try self.expect(.colon);
                        const ft = try self.parse_type();
                        try fields.append(self.alloc, ast.RecordField{
                            .name = fn_tok.text,
                            .typ = ft,
                            .loc = fl,
                        });
                        if (try self.eat(.comma) == null) break;
                    }
                }
                _ = try self.expect(.rbrace);
                const rt = try self.alloc.create(ast.TypeExpr.RecordType);
                rt.* = .{ .fields = try fields.toOwnedSlice(self.alloc) };
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
        const tok = try self.pk();
        const body = try self.parse_block();
        _ = try self.expect(.eof);
        return ast.Module{ .file = tok.loc.file, .body = body };
    }

    fn parse_block(self: *Parser) ParseError!ast.Block {
        const saved_match_depth = self.match_arm_depth;
        self.match_arm_depth = 0;
        defer self.match_arm_depth = saved_match_depth;
        const l = (try self.pk()).loc;
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            switch (tok.kind) {
                .kw_end, .kw_else, .kw_elseif, .kw_until, .eof => break,
                .kw_return => {
                    try stmts.append(self.alloc, try self.parse_return());
                    _ = try self.eat(.semi);
                    break;
                },
                else => {
                    try self.flush_module_hint_directives(&stmts);
                    try stmts.append(self.alloc, try self.parse_stmt());
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
        switch (nxt.kind) {
            .kw_end, .kw_else, .kw_elseif, .kw_until, .kw_catch, .eof, .semi => {},
            else => {
                try vals.append(self.alloc, try self.parse_expr());
                while (try self.eat(.comma) != null)
                    try vals.append(self.alloc, try self.parse_expr());
            },
        }
        return ast.Stmt{ .ret = .{ .loc = l, .vals = try vals.toOwnedSlice(self.alloc) } };
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

        return switch (tok.kind) {
            .at => blk: {
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
            .kw_macro => self.parse_macro_def(),
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
            var is_c_export = false;
            if (std.mem.eql(u8, attr_name.text, "c") and (try self.pk()).kind == .dot) {
                const c_saved = self.lex.saveState();
                _ = try self.adv();
                const c_part = try self.expect(.name);
                is_c_export = std.mem.eql(u8, c_part.text, "export");
                if (!is_c_export) {
                    self.lex.restoreState(c_saved);
                }
            }
            const is_build = std.mem.eql(u8, attr_name.text, "build") or std.mem.startsWith(u8, attr_name.text, "build.");
            const is_debug = std.mem.eql(u8, attr_name.text, "debug") or std.mem.startsWith(u8, attr_name.text, "debug.");
            const is_trace = std.mem.eql(u8, attr_name.text, "trace") or std.mem.startsWith(u8, attr_name.text, "trace.");
            const is_directive = is_build or is_debug or is_trace;
            const is_known = is_directive or
                (is_c_export or is_known_attribute(attr_name.text));
            if (!is_known) return false;
            // Consume any dotted continuation (e.g. `@test.unit`, `@build.exe`,
            // `@trace.parse`) and any balanced `(...)` argument block. The
            // caller restores the cursor before the real parse, so this is
            // strictly lookahead.
            while ((try self.pk()).kind == .dot) {
                _ = try self.adv();
                _ = try self.expect(.name);
            }
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
            if (is_directive) return true;
        }
        const tok = try self.pk();
        return switch (tok.kind) {
            .kw_function, .kw_fun, .kw_async, .kw_enum, .kw_concept, .kw_alias, .kw_local, .kw_global, .kw_for => true,
            .name => blk: {
                if (std.mem.eql(u8, tok.text, "type")) break :blk true;
                // Jai-like syntax: @attr Name: { ... } — name followed by ':' is a type def
                if (!is_keyword_token(tok.text)) {
                    const s2 = self.lex.saveState();
                    _ = try self.adv(); // consume name
                    const after = try self.pk();
                    self.lex.restoreState(s2);
                    if (after.kind == .colon) break :blk true;
                }
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

    fn parse_macro_def(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.expect(.kw_macro)).loc;
        const name = try self.expect(.name);
        _ = try self.expect(.lparen);
        var params: std.ArrayList([]const u8) = .empty;
        if (!(try self.check(.rparen))) {
            const first = try self.expect(.name);
            try params.append(self.alloc, first.text);
            while (try self.eat(.comma) != null) {
                const param = try self.expect(.name);
                try params.append(self.alloc, param.text);
            }
        }
        _ = try self.expect(.rparen);
        const quote_tok = try self.expect(.backtick);
        self.quote_depth += 1;
        defer self.quote_depth -= 1;
        const body: ast.MacroBody = if (try self.eat(.kw_do) != null) blk: {
            const block = try self.parse_block();
            _ = try self.expect(.kw_end);
            break :blk .{ .block = block };
        } else .{ .expr = try self.parse_expr() };
        _ = quote_tok;
        return .{ .macro_def = .{
            .loc = l,
            .name = name.text,
            .params = try params.toOwnedSlice(self.alloc),
            .body = body,
        } };
    }

    /// Parse one or more `@name` or `@name(args)` attributes, then the declaration
    /// that follows (function, enum, concept, async function, or local/global
    /// binding with `@implements(...)`).
    fn parse_attributed_decl(self: *Parser) ParseError!ast.Stmt {
        var attrs: std.ArrayList(ast.Attribute) = .empty;
        const directives = @import("directives.zig");
        while ((try self.pk()).kind == .at) {
            const attr = try self.parse_one_attribute();

            // Standalone @cinclude / @c.import / @build.* / @debug.* module directives are
            // each their own statement; do not accumulate them as attributes.
            if (std.mem.eql(u8, attr.name, "cinclude") or
                std.mem.eql(u8, attr.name, "c.include") or
                std.mem.eql(u8, attr.name, "c.import"))
            {
                const header = strip_quotes(attr.args orelse "");
                return ast.Stmt{ .cinclude = .{ .loc = (try self.pk()).loc, .header = header } };
            }
            if (std.mem.eql(u8, attr.name, "c.emit")) {
                const loc_tok = try self.pk();
                return ast.Stmt{ .directive = .{ .loc = loc_tok.loc, .attr = attr } };
            }
            if (directives.isBuildDirective(attr.name) or directives.isDebugDirective(attr.name)) {
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
        // Jai-like type definition with attributes: @derive(Display) Vec: { x: f64, y: f64 }
        // When we see a bare name that isn't a keyword after attributes, check if it's
        // followed by `:` (indicating a type definition).
        if (tok.kind == .name and !is_keyword_token(tok.text)) {
            return self.parse_jai_type_def_with_attrs(attrs_slice);
        }
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
        if (std.mem.eql(u8, attr.name, "c.include") or std.mem.eql(u8, attr.name, "c.import")) {
            const header = strip_quotes(attr.args orelse "");
            return ast.Stmt{ .cinclude = .{ .loc = loc, .header = header } };
        }
        if (std.mem.eql(u8, attr.name, "c.emit")) {
            return ast.Stmt{ .directive = .{ .loc = loc, .attr = attr } };
        }
        self.lex.restoreState(saved);
        return null;
    }

    /// Check if a name token text is a language keyword (should not be treated as
    /// a Jai-like type definition target).
    fn is_keyword_token(text: []const u8) bool {
        return std.mem.eql(u8, text, "type") or
            std.mem.eql(u8, text, "function") or
            std.mem.eql(u8, text, "fun") or
            std.mem.eql(u8, text, "local") or
            std.mem.eql(u8, text, "global") or
            std.mem.eql(u8, text, "enum") or
            std.mem.eql(u8, text, "concept") or
            std.mem.eql(u8, text, "alias") or
            std.mem.eql(u8, text, "async") or
            std.mem.eql(u8, text, "return") or
            std.mem.eql(u8, text, "if") or
            std.mem.eql(u8, text, "while") or
            std.mem.eql(u8, text, "for") or
            std.mem.eql(u8, text, "end");
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
        const first = try self.expect(.name);
        var parts: std.ArrayList([]const u8) = .empty;
        try parts.append(self.alloc, first.text);
        while ((try self.pk()).kind == .dot) {
            _ = try self.adv();
            const part = try self.expect(.name);
            try parts.append(self.alloc, part.text);
        }
        const name = try std.mem.join(self.alloc, ".", parts.items);
        var args: ?[]const u8 = null;
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv(); // consume `(`
            args = try self.parse_attribute_args();
            _ = try self.expect(.rparen);
        }
        return ast.Attribute{ .name = name, .args = args };
    }

    /// Parse attribute argument text between parens, handling nested parens.
    /// Returns the raw source text content (not including outer parens).
    fn parse_attribute_args(self: *Parser) ParseError![]const u8 {
        const first_tok = try self.pk();
        if (first_tok.kind == .rparen) return "";

        const src = self.lex.src;

        var start: usize = undefined;
        if (first_tok.kind == .string_lit) {
            const tok_start = @intFromPtr(first_tok.text.ptr) - @intFromPtr(src.ptr);
            if (longBracketSpan(src, tok_start, first_tok.text.len)) |span| {
                start = span.start;
            } else if (longBracketDelimiterWidth(src, tok_start)) |delim| {
                start = tok_start - delim;
            } else {
                start = tok_start - 1;
            }
        } else {
            start = @intFromPtr(first_tok.text.ptr) - @intFromPtr(src.ptr);
        }

        var depth: u32 = 1;
        var end: usize = start;

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
            const tok_start = @intFromPtr(tok.text.ptr) - @intFromPtr(src.ptr);
            if (tok.kind == .string_lit) {
                if (longBracketSpan(src, tok_start, tok.text.len)) |span| {
                    end = span.end;
                } else if (longBracketDelimiterWidth(src, tok_start)) |delim| {
                    end = tok_start + tok.text.len + delim;
                } else {
                    end = tok_start + tok.text.len + 1;
                }
            } else {
                end = tok_start + tok.text.len;
            }
            _ = try self.adv();
            if (tok.kind == .lparen) depth += 1;
        }

        if (end <= start) return "";
        return src[start..end];
    }

    /// Width of `[=*[` / `]=*]` delimiter before long-string content (0 if not long bracket).
    fn longBracketDelimiterWidth(src: []const u8, content_start: usize) ?usize {
        if (content_start < 2) return null;
        if (src[content_start - 2] == '[' and src[content_start - 1] == '[') return 2;
        if (content_start < 3 or src[content_start - 1] != '[') return null;
        var eq: usize = 0;
        var i = content_start - 2;
        while (i > 0 and src[i] == '=') : (i -= 1) eq += 1;
        if (src[i] != '[') return null;
        return eq + 2;
    }

    fn skipLongBracketWsBack(src: []const u8, i: usize) usize {
        var p = i;
        while (p > 0 and (src[p - 1] == ' ' or src[p - 1] == '\t' or src[p - 1] == '\r' or src[p - 1] == '\n')) p -= 1;
        return p;
    }

    fn skipLongBracketWsForward(src: []const u8, i: usize) usize {
        var p = i;
        while (p < src.len and (src[p] == ' ' or src[p] == '\t' or src[p] == '\r' or src[p] == '\n')) p += 1;
        return p;
    }

    /// Map long-string content slice to full `[[...]]` / `[=[...]=]` span in source.
    fn longBracketSpan(src: []const u8, content_start: usize, content_len: usize) ?struct { start: usize, end: usize } {
        const after_open = skipLongBracketWsBack(src, content_start);
        const open_width = longBracketDelimiterWidth(src, after_open) orelse return null;
        const start = after_open - open_width;
        const close_pos = skipLongBracketWsForward(src, content_start + content_len);
        if (close_pos >= src.len or src[close_pos] != ']') return null;
        var eq: usize = 0;
        var i = close_pos + 1;
        while (i < src.len and src[i] == '=') : (i += 1) eq += 1;
        const level: usize = if (open_width >= 2) open_width - 2 else 0;
        if (eq != level or i >= src.len or src[i] != ']') return null;
        return .{ .start = start, .end = i + 1 };
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
        while ((try self.pk()).kind != .kw_end and (try self.pk()).kind != .eof) {
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
        _ = try self.expect(.kw_end);

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

        while ((try self.pk()).kind != .kw_end and (try self.pk()).kind != .eof) {
            if ((try self.pk()).kind == .kw_fun or (try self.pk()).kind == .kw_function) {
                // Required method: fun name(params) -> ret_type
                _ = try self.adv(); // consume `fun` or `function`
                const method_name = try self.expect(.name);

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

                // Parse parameter list
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

                try methods.append(self.alloc, .{
                    .name = method_name.text,
                    .params = try params.toOwnedSlice(self.alloc),
                    .ret_type = ret_type,
                    .type_params = method_type_params,
                });
            } else if ((try self.pk()).kind == .name) {
                // Required field: name: type
                const field_name = try self.adv();
                _ = try self.expect(.colon);
                const field_type = try self.parse_type();
                try fields.append(self.alloc, .{
                    .name = field_name.text,
                    .typ = field_type,
                });
            } else {
                // Skip unexpected tokens to avoid infinite loops
                term.locErr((try self.pk()).loc, "unexpected token in concept body: '{s}'", .{
                    (try self.pk()).kind.spelling(),
                });
                return ParseError.UnexpectedToken;
            }
        }
        _ = try self.expect(.kw_end);

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

        // Otherwise it's a typed local binding with attributes
        _ = try self.adv(); // consume '='
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
        const l = (try self.adv()).loc;
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

    fn parse_func_body(self: *Parser, l: ast.Loc) ParseError!ast.FuncBody {
        // Check for type parameters: <T, U>
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
        if (try self.eat(.arrow) != null or try self.eat(.colon) != null)
            ret_type = try self.parse_type();
        const body = try self.parse_block();
        _ = try self.expect(.kw_end);
        return ast.FuncBody{
            .loc = l,
            .params = try params.toOwnedSlice(self.alloc),
            .vararg = vararg,
            .vararg_name = vararg_name,
            .ret_type = ret_type,
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
            try tp_list.append(self.alloc, try self.parse_type());
            while (try self.eat(.comma) != null) {
                try tp_list.append(self.alloc, try self.parse_type());
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
        if (try self.eat(.arrow) != null or try self.eat(.colon) != null)
            ret_type = try self.parse_type();
        // Bodyless function: empty body with no tail expression.
        return ast.FuncBody{
            .loc = l,
            .params = try params.toOwnedSlice(self.alloc),
            .vararg = vararg,
            .vararg_name = vararg_name,
            .ret_type = ret_type,
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

    fn parse_if(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        // `if let pattern = expr then ... end` — desugars to match
        if ((try self.pk()).kind == .kw_let) {
            _ = try self.adv(); // consume `let`
            const pattern = try self.parse_pattern();
            _ = try self.expect(.assign);
            const scrutinee = try self.parse_expr();
            _ = try self.eat(.kw_then);
            const then_body = try self.parse_block();
            // Parse optional else
            var else_body: ?ast.Block = null;
            if (try self.eat(.kw_else) != null) {
                else_body = try self.parse_block();
            }
            _ = try self.expect(.kw_end);
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
        const cond = try self.parse_expr();
        _ = try self.eat(.kw_then); // `then` is optional in .duo files
        const then = try self.parse_block();
        var elseifs: std.ArrayList(ast.ElseIf) = .empty;
        var else_body: ?ast.Block = null;
        while (true) {
            if (try self.eat(.kw_elseif) != null) {
                const ec = try self.parse_expr();
                _ = try self.eat(.kw_then); // `then` is optional in .duo files
                const eb = try self.parse_block();
                try elseifs.append(self.alloc, ast.ElseIf{ .cond = ec, .body = eb });
            } else if (try self.eat(.kw_else) != null) {
                else_body = try self.parse_block();
                break;
            } else break;
        }
        _ = try self.expect(.kw_end);
        return ast.Stmt{ .if_stmt = .{
            .loc = l,
            .cond = cond,
            .then = then,
            .elseifs = try elseifs.toOwnedSlice(self.alloc),
            .else_body = else_body,
        } };
    }

    fn parse_while(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        // `while let pattern = expr do ... end` — desugars to while + match
        if ((try self.pk()).kind == .kw_let) {
            _ = try self.adv(); // consume `let`
            const pattern = try self.parse_pattern();
            _ = try self.expect(.assign);
            const scrutinee = try self.parse_expr();
            _ = try self.eat(.kw_do);
            const body = try self.parse_block();
            _ = try self.expect(.kw_end);
            // Build: while true do match scrutinee case pattern then body case _ then break end end
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
            // while true do inner_body end
            const true_lit = try self.new_expr(.{ .true_lit = l });
            return ast.Stmt{ .while_loop = .{ .loc = l, .cond = true_lit, .body = inner_body } };
        }
        const cond = try self.parse_expr();
        _ = try self.eat(.kw_do); // do is optional in Duo
        const body = try self.parse_block();
        _ = try self.expect(.kw_end);
        return ast.Stmt{ .while_loop = .{ .loc = l, .cond = cond, .body = body } };
    }

    fn parse_repeat(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const body = try self.parse_block();
        _ = try self.expect(.kw_until);
        const cond = try self.parse_expr();
        return ast.Stmt{ .repeat_loop = .{ .loc = l, .body = body, .cond = cond } };
    }

    fn parse_for(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
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
            _ = try self.eat(.kw_do);
            const body = try self.parse_block();
            _ = try self.expect(.kw_end);
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
            _ = try self.eat(.kw_do);
            const body = try self.parse_block();
            _ = try self.expect(.kw_end);
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
        const body = try self.parse_block();
        _ = try self.expect(.kw_end);
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
        const body = try self.parse_block();
        _ = try self.expect(.kw_end);
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
        const scrutinee = try self.parse_match_scrutinee();

        var arms: std.ArrayList(ast.MatchArm) = .empty;
        while (true) {
            while (try self.eat(.semi) != null) {}
            const tok = try self.pk();
            if (tok.kind == .kw_end or tok.kind == .eof) break;
            try arms.append(self.alloc, try self.parse_match_arm());
        }
        _ = try self.expect(.kw_end);

        return ast.MatchExpr{
            .loc = l,
            .scrutinee = scrutinee,
            .arms = try arms.toOwnedSlice(self.alloc),
        };
    }

    /// Parse match scrutinee — a restricted expression that does not consume
    /// `{`, `[`, or string_lit as call/index suffixes (those start pattern arms).
    fn parse_match_scrutinee(self: *Parser) ParseError!*ast.Expr {
        return self.parse_match_scrutinee_prec(0);
    }

    fn parse_match_scrutinee_prec(self: *Parser, min_prec: u8) ParseError!*ast.Expr {
        var lhs: *ast.Expr = undefined;
        {
            const tok = try self.pk();
            if (tok.kind == .kw_await) {
                _ = try self.adv(); // consume `await`
                const operand = try self.parse_match_scrutinee_prec(20);
                lhs = try self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
            } else {
                const op: ?ast.UnOp = switch (tok.kind) {
                    .kw_not => .not,
                    .hash => .len,
                    .hash_hash, .kw_comptime => .compile,
                    .minus => .neg,
                    .tilde => .bnot,
                    else => null,
                };
                if (op) |uop| {
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
            if (tok.kind == .at and tok.loc.line > lhs.loc().line) break;
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

    /// Like parse_suffixed_expr but does NOT consume `{`, `[`, or string_lit
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
                    e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs } });
                },
                // Do NOT consume {, [, string_lit as suffixes in match scrutinee
                else => break,
            }
        }
        return e;
    }

    fn tokenStartsMatchPattern(kind: TK) bool {
        return switch (kind) {
            .name,
            .dots,
            .lbrace,
            .lbracket,
            .int_lit,
            .float_lit,
            .string_lit,
            .kw_nil,
            .kw_true,
            .kw_false,
            .minus,
            => true,
            else => false,
        };
    }

    fn startsMatchArm(self: *Parser) ParseError!bool {
        const saved = self.lex.saveState();
        defer self.lex.restoreState(saved);

        const first = try self.lex.peek();
        if (first.kind == .name and std.mem.eql(u8, first.text, "case")) return true;
        if (first.kind == .kw_else) return true;
        if (!tokenStartsMatchPattern(first.kind)) return false;

        var depth: u32 = 0;
        while (true) {
            const tok = try self.lex.next();
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
            // Literals
            .int_lit => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
            .float_lit => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
            .string_lit => {
                const e = try self.parse_simple_expr();
                return ast.Pattern{ .literal = e };
            },
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
                term.locErr(tok.loc, "expected pattern, got '{s}'", .{tok.kind.spelling()});
                return ParseError.UnexpectedToken;
            },
        }
    }

    /// Parse table destructuring pattern: `{key1: pat1, key2: pat2}`
    fn parse_table_destr_pattern(self: *Parser) ParseError!ast.Pattern {
        _ = try self.adv(); // consume `{`
        var entries: std.ArrayList(ast.Pattern.TableDestrEntry) = .empty;
        while ((try self.pk()).kind != .rbrace) {
            const key_tok = try self.expect(.name);
            _ = try self.expect(.colon);
            const pat = try self.parse_pattern();
            try entries.append(self.alloc, .{ .key = key_tok.text, .pat = pat });
            if (try self.eat(.comma) == null) break;
        }
        _ = try self.expect(.rbrace);
        return ast.Pattern{ .table_destr = try entries.toOwnedSlice(self.alloc) };
    }

    /// Parse array destructuring pattern: `[pat1, pat2, ...name]`
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
        const is_unary = switch (first_tok.kind) {
            .kw_not, .hash, .hash_hash, .kw_comptime, .minus, .tilde, .kw_await, .backtick => true,
            else => false,
        };
        if (is_unary) {
            const expr = try self.parse_expr();
            return ast.Stmt{ .expr_stmt = .{ .loc = expr.loc(), .expr = expr } };
        }

        const first = try self.parse_suffixed_expr();

        // If the next token continues the expression (binary op, etc.),
        // parse the full expression.
        const nxt = try self.pk();

        // Typed-binding without 'local': name : Type = value
        // parse_suffixed_expr breaks on ':' when followed by a type-like token.
        if (first.* == .name and nxt.kind == .colon) {
            _ = try self.adv(); // consume ':'
            const typ = try self.parse_type();

            // Jai-like type definition: `Name: { fields }` with no initializer
            // becomes an alias_def (equivalent to `type Name = { fields }`)
            if (typ == .record and (try self.pk()).kind != .assign) {
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
            if (try self.eat(.assign) != null) {
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
        if (nxt.kind == .assign or compound_assign_op(nxt.kind) != null) {
            // Single-target assignment:  name = expr  /  name += expr
            _ = try self.adv(); // consume = or compound-assign
            // Check for `Name = struct ... end` — C-layout type definition
            if (first.* == .name and compound_assign_op(nxt.kind) == null) {
                const next_tok = try self.pk();
                if (next_tok.kind == .name and std.mem.eql(u8, next_tok.text, "struct")) {
                    _ = try self.adv(); // consume "struct"
                    return try self.parse_struct_body(first.name.ident, &.{});
                }
            }
            var values: std.ArrayList(*ast.Expr) = .empty;
            if (compound_assign_op(nxt.kind)) |op| {
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
                return ast.Stmt{ .assign = .{
                    .loc = first.loc(),
                    .targets = try exprs.toOwnedSlice(self.alloc),
                    .values = try values.toOwnedSlice(self.alloc),
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
        if (first.* == .name) {
            const is_bash_arg = switch (nxt.kind) {
                .string_lit, .int_lit, .float_lit, .name => true,
                else => false,
            };
            if (is_bash_arg) {
                const name_info = first.name;
                var args: std.ArrayList(*ast.Expr) = .empty;
                try args.append(self.alloc, try self.parse_expr());
                while (true) {
                    const peek = try self.pk();
                    const is_next = switch (peek.kind) {
                        .string_lit, .int_lit, .float_lit, .name => true,
                        else => false,
                    };
                    if (!is_next) break;
                    if (peek.kind == .semi or peek.kind == .eof or
                        peek.kind == .kw_end or peek.kind == .kw_else or
                        peek.kind == .kw_elseif or peek.kind == .kw_until) break;
                    try args.append(self.alloc, try self.parse_expr());
                }
                const func_expr = try self.alloc.create(ast.Expr);
                func_expr.* = .{ .name = .{ .loc = name_info.loc, .ident = name_info.ident } };
                const call_expr = try self.alloc.create(ast.Expr);
                call_expr.* = .{ .call = .{
                    .loc = name_info.loc,
                    .func = func_expr,
                    .args = try args.toOwnedSlice(self.alloc),
                } };
                return ast.Stmt{ .call_stmt = .{ .loc = name_info.loc, .expr = call_expr } };
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
            const rhs = try self.parse_prec(inf.right);
            e = try self.new_expr(.{ .binop = .{
                .loc = e.loc(),
                .op = inf.op,
                .lhs = e,
                .rhs = rhs,
            } });
        }
        return e;
    }

    fn is_expr_start(_: *Parser, kind: TK) bool {
        return switch (kind) {
            .name, .int_lit, .float_lit, .string_lit, .kw_nil, .kw_true, .kw_false, .dots, .lparen, .lbrace, .lbracket, .kw_not, .hash, .minus, .tilde, .hash_hash, .kw_comptime, .kw_await, .backtick, .comma, .at => true,
            else => false,
        };
    }

    // ── Pratt expression parser ───────────────────────────────────────────────

    fn infix_prec(kind: TK) ?struct { op: ast.BinOp, left: u8, right: u8 } {
        return switch (kind) {
            .kw_or => .{ .op = .@"or", .left = 2, .right = 3 },
            .kw_and => .{ .op = .@"and", .left = 4, .right = 5 },
            .lt => .{ .op = .lt, .left = 6, .right = 6 },
            .gt => .{ .op = .gt, .left = 6, .right = 6 },
            .leq => .{ .op = .leq, .left = 6, .right = 6 },
            .geq => .{ .op = .geq, .left = 6, .right = 6 },
            .eq => .{ .op = .eq, .left = 6, .right = 6 },
            .neq => .{ .op = .neq, .left = 6, .right = 6 },
            .kw_in => .{ .op = .contains, .left = 6, .right = 6 },
            .pipe => .{ .op = .bor, .left = 7, .right = 8 },
            .tilde => .{ .op = .bxor, .left = 9, .right = 10 },
            .amp => .{ .op = .band, .left = 11, .right = 12 },
            .lshift => .{ .op = .lshift, .left = 13, .right = 14 },
            .rshift => .{ .op = .rshift, .left = 13, .right = 14 },
            .concat => .{ .op = .concat, .left = 16, .right = 15 }, // right-assoc
            .plus => .{ .op = .add, .left = 17, .right = 18 },
            .minus => .{ .op = .sub, .left = 17, .right = 18 },
            .star => .{ .op = .mul, .left = 19, .right = 20 },
            .slash => .{ .op = .div, .left = 19, .right = 20 },
            .idiv => .{ .op = .idiv, .left = 19, .right = 20 },
            .percent => .{ .op = .mod, .left = 19, .right = 20 },
            .caret => .{ .op = .pow, .left = 23, .right = 22 }, // right-assoc
            .at => .{ .op = .matmul, .left = 19, .right = 20 }, // a @ b (same band as *)
            .pipe_gt => .{ .op = .pipeline, .left = 1, .right = 2 }, // a |> f (lowest prec, left-assoc)
            else => null,
        };
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

    fn parse_prec(self: *Parser, min_prec: u8) ParseError!*ast.Expr {
        var lhs: *ast.Expr = undefined;
        {
            const tok = try self.pk();
            if (tok.kind == .backtick) {
                _ = try self.adv();
                self.quote_depth += 1;
                defer self.quote_depth -= 1;
                const inner = try self.parse_prec(20);
                lhs = try self.new_expr(.{ .quote = .{ .loc = tok.loc, .expr = inner } });
            } else if (tok.kind == .comma and self.quote_depth > 0) {
                _ = try self.adv();
                const inner = try self.parse_prec(20);
                lhs = try self.new_expr(.{ .unquote = .{ .loc = tok.loc, .expr = inner } });
            } else if (tok.kind == .kw_await) {
                _ = try self.adv(); // consume `await`
                const operand = try self.parse_prec(20);
                lhs = try self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
            } else {
                const op: ?ast.UnOp = switch (tok.kind) {
                    .kw_not => .not,
                    .hash => .len,
                    .hash_hash, .kw_comptime => .compile,
                    .minus => .neg,
                    .tilde => .bnot,
                    else => null,
                };
                if (op) |uop| {
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
            // @ on a new line is an attribute prefix, not the matmul operator.
            // Without this check, `x = 42\n@hot\nfun ...` parses as `x = 42 @ hot`.
            if (tok.kind == .at and tok.loc.line > lhs.loc().line) break;
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            const rhs = try self.parse_prec(inf.right);
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
            _ = try self.adv(); // consume `await`
            const operand = try self.parse_prec(20);
            return self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
        }
        const op: ?ast.UnOp = switch (tok.kind) {
            .kw_not => .not,
            .hash => .len,
            .hash_hash, .kw_comptime => .compile,
            .minus => .neg,
            .tilde => .bnot,
            else => null,
        };
        if (op) |uop| {
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
            const body = try self.parse_block();
            _ = try self.expect(.kw_end);
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
            .string_lit => blk: {
                _ = try self.adv();
                const decoded = try Lexer.decode_lua_short_string(self.alloc, tok.text);
                break :blk self.new_expr(.{ .string_lit = .{ .loc = tok.loc, .val = decoded } });
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
            .at => self.parse_macro_call_expr(),
            .lparen => blk: {
                _ = try self.adv();
                const e = try self.parse_expr();
                _ = try self.expect(.rparen);
                break :blk e;
            },
            .lbrace => self.parse_table(),
            .kw_match => self.parse_match_expr(),
            else => {
                term.locErr(tok.loc, "expected expression, got '{s}'", .{tok.kind.spelling()});
                return ParseError.ExpectedToken;
            },
        };
    }

    fn parse_macro_call_expr(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.at)).loc;
        // @(expr) — compile-time eval (no name, immediate paren)
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv(); // consume '('
            const operand = try self.parse_expr();
            _ = try self.expect(.rparen);
            return self.new_expr(.{ .unop = .{ .loc = l, .op = .compile, .operand = operand } });
        }
        const first = try self.expect(.name);
        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(self.alloc);
        try parts.append(self.alloc, first.text);
        while ((try self.pk()).kind == .dot) {
            _ = try self.adv();
            const part = try self.expect(.name);
            try parts.append(self.alloc, part.text);
        }
        const qualified = try std.mem.join(self.alloc, ".", parts.items);
        defer self.alloc.free(qualified);

        if (std.mem.eql(u8, qualified, "sizeof") or std.mem.eql(u8, qualified, "alignof") or std.mem.eql(u8, qualified, "typeof") or std.mem.eql(u8, qualified, "fields")) {
            return self.parse_layout_intrinsic_call(l, qualified);
        }
        if (std.mem.eql(u8, qualified, "as")) {
            return self.parse_as_intrinsic_call(l);
        }

        _ = try self.expect(.lparen);
        var args: std.ArrayList(*ast.Expr) = .empty;
        if (!(try self.check(.rparen))) {
            try args.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null) {
                try args.append(self.alloc, try self.parse_expr());
            }
        }
        _ = try self.expect(.rparen);
        const args_slice = try args.toOwnedSlice(self.alloc);

        // `@c.emit(expr)` / `@emit(expr)` desugar to `__emit(expr)` — canonical C injection under `@`.
        if ((std.mem.eql(u8, qualified, "c.emit") or std.mem.eql(u8, qualified, "emit")) and args_slice.len >= 1) {
            const emit_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = "__emit" } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = emit_name, .args = args_slice } });
        }
        // `@c.call("name", args...)` lowers to a direct raw C call expression.
        if (std.mem.eql(u8, qualified, "c.call") and args_slice.len >= 1) {
            const call_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = "__c_call" } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = call_name, .args = args_slice } });
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
        if (at_builtin_internal_name(qualified)) |internal| {
            const builtin_name = try self.new_expr(.{ .name = .{ .loc = l, .ident = internal } });
            return self.new_expr(.{ .call = .{ .loc = l, .func = builtin_name, .args = args_slice } });
        }

        return self.new_expr(.{ .macro_call = .{
            .loc = l,
            .name = first.text,
            .args = args_slice,
        } });
    }

    fn at_builtin_internal_name(name: []const u8) ?[]const u8 {
        const pairs = [_]struct { public: []const u8, internal: []const u8 }{
            .{ .public = "constexpr", .internal = "__constexpr" },
            .{ .public = "comptime_if", .internal = "__comptimeif" },
            .{ .public = "comptimeif", .internal = "__comptimeif" },
            .{ .public = "comptime_fold", .internal = "__comptimefold" },
            .{ .public = "comptimefold", .internal = "__comptimefold" },
            .{ .public = "comptime_for", .internal = "__comptimefor" },
            .{ .public = "comptimefor", .internal = "__comptimefor" },
            .{ .public = "comptime_print", .internal = "__comptimeprint" },
            .{ .public = "comptimeprint", .internal = "__comptimeprint" },
            .{ .public = "comptime_warn", .internal = "__comptimewarn" },
            .{ .public = "comptimewarn", .internal = "__comptimewarn" },
            .{ .public = "compile_log", .internal = "__comptimeprint" },
            .{ .public = "compile_error", .internal = "__comptimeerror" },
            .{ .public = "comptime_error", .internal = "__comptimeerror" },
            .{ .public = "comptimeerror", .internal = "__comptimeerror" },
            .{ .public = "static_assert", .internal = "__static_assert" },
            .{ .public = "typeinfo", .internal = "__typeinfo" },
            .{ .public = "typeof", .internal = "__typeof" },
            .{ .public = "type_name", .internal = "__type_name" },
            .{ .public = "type_id", .internal = "__type_id" },
            .{ .public = "is_type", .internal = "__is_type" },
            .{ .public = "fields", .internal = "__fields" },
            .{ .public = "methods", .internal = "__methods" },
            .{ .public = "variants", .internal = "__variants" },
            .{ .public = "has_field", .internal = "__has_field" },
            .{ .public = "has_method", .internal = "__has_method" },
            .{ .public = "has_metamethod", .internal = "__has_metamethod" },
            .{ .public = "field_type", .internal = "__field_type" },
            .{ .public = "field_offset", .internal = "__field_offset" },
            .{ .public = "field_size", .internal = "__field_size" },
            .{ .public = "embed_str", .internal = "__embed_str" },
            .{ .public = "embed_file", .internal = "__embed_file" },
            .{ .public = "make_type", .internal = "__make_type" },
            .{ .public = "as_type", .internal = "__as_type" },
            .{ .public = "bitfield", .internal = "__bitfield" },
            .{ .public = "union", .internal = "__union" },
            .{ .public = "select", .internal = "__select" },
            .{ .public = "likely", .internal = "__likely" },
            .{ .public = "unlikely", .internal = "__unlikely" },
            .{ .public = "prefetch", .internal = "__prefetch" },
            .{ .public = "assume", .internal = "__assume" },
            .{ .public = "unreachable", .internal = "__unreachable" },
            .{ .public = "trap", .internal = "__trap" },
            .{ .public = "fence", .internal = "__fence" },
            .{ .public = "ctz", .internal = "__ctz" },
            .{ .public = "clz", .internal = "__clz" },
            .{ .public = "popcount", .internal = "__popcount" },
            .{ .public = "bswap", .internal = "__bswap" },
            .{ .public = "rotl", .internal = "__rotl" },
            .{ .public = "rotr", .internal = "__rotr" },
            .{ .public = "bitcast", .internal = "__bitcast" },
            .{ .public = "volatile", .internal = "__volatile" },
        };
        for (pairs) |pair| {
            if (std.mem.eql(u8, name, pair.public)) return pair.internal;
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
        const type_arg = try self.new_expr(.{ .string_lit = .{ .loc = loc, .val = type_name } });
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
        return self.new_expr(.{ .string_lit = .{ .loc = loc, .val = try self.type_expr_c_name(typ) } });
    }

    fn layout_arg_can_start_type(tok: Token) bool {
        if (Lexer.isTypeKeyword(tok.kind)) return true;
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
                    _ = try self.adv();
                    const fld = try self.expect_name_like();
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = fld } });
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
                    if (Lexer.isTypeKeyword(after_colon.kind)) {
                        // name : i64 = ...  —  this is a typed binding; don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .lbrace) {
                        // name : { ... } — record type annotation (Jai-like syntax); don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .star or after_colon.kind == .question) {
                        // name : *Type or name : ?Type — pointer/optional type; don't consume
                        self.lex.restoreState(saved);
                        break;
                    }
                    if (after_colon.kind == .name) {
                        // Could be name : UserType = ... or obj : method ( args )
                        _ = try self.lex.next(); // consume the name
                        const after_name = try self.lex.peek();
                        self.lex.restoreState(saved);
                        if (after_name.kind == .assign) {
                            // name : TypeName = ...  —  typed binding; don't consume
                            break;
                        }
                    } else {
                        self.lex.restoreState(saved);
                    }
                    // Not a typed binding — treat as method call
                    _ = try self.adv(); // consume ':'
                    const method = try self.expect_name_like();
                    const callargs = try self.parse_call_args();
                    e = try self.new_expr(.{ .method_call = .{
                        .loc = tok.loc,
                        .obj = e,
                        .method = method,
                        .args = callargs,
                    } });
                },
                .lbrace => {
                    if (e.* == .name and std.mem.eql(u8, e.name.ident, "nn")) {
                        e = try self.parse_nn_block_desugar(tok.loc);
                    } else {
                        const callargs = try self.parse_call_args();
                        e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs } });
                    }
                },
                .lparen, .string_lit => {
                    const callargs = try self.parse_call_args();
                    e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs } });
                },
                .question => {
                    _ = try self.adv();
                    e = try self.new_expr(.{ .try_expr = .{ .loc = tok.loc, .operand = e } });
                },
                .bang => {
                    _ = try self.adv();
                    e = try self.new_expr(.{ .unwrap_expr = .{ .loc = tok.loc, .operand = e } });
                },
                else => break,
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
        const path_lit = try self.new_expr(.{ .string_lit = .{ .loc = loc, .val = path } });
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
        switch (tok.kind) {
            .lparen => {
                _ = try self.adv();
                if (!(try self.check(.rparen))) {
                    try args.append(self.alloc, try self.parse_expr());
                    while (try self.eat(.comma) != null)
                        try args.append(self.alloc, try self.parse_expr());
                }
                _ = try self.expect(.rparen);
            },
            .lbrace => try args.append(self.alloc, try self.parse_table()),
            .string_lit => {
                const t = try self.adv();
                const decoded = try Lexer.decode_lua_short_string(self.alloc, t.text);
                try args.append(self.alloc, try self.new_expr(
                    .{ .string_lit = .{ .loc = t.loc, .val = decoded } },
                ));
            },
            else => {
                term.locErr(tok.loc, "expected function arguments", .{});
                return ParseError.UnexpectedToken;
            },
        }
        return args.toOwnedSlice(self.alloc);
    }

    fn parse_table(self: *Parser) ParseError!*ast.Expr {
        const l = (try self.expect(.lbrace)).loc;
        var fields: std.ArrayList(ast.TableField) = .empty;
        while (!(try self.check(.rbrace))) {
            const tok = try self.pk();
            if (tok.kind == .lbracket) {
                _ = try self.adv();
                const key = try self.parse_expr();
                _ = try self.expect(.rbracket);
                _ = try self.expect(.assign);
                const val = try self.parse_expr();
                try fields.append(self.alloc, .{ .indexed = .{ .key = key, .val = val } });
            } else if (tok.kind == .name) {
                // Speculate: name '=' and name ':' Type '=' mean named fields;
                // otherwise the entry is positional.
                const saved = self.lex.saveState();
                _ = try self.adv();
                if (try self.check(.assign)) {
                    _ = try self.adv();
                    const val = try self.parse_expr();
                    try fields.append(self.alloc, .{ .named = .{ .key = tok.text, .val = val } });
                } else if (try self.check(.colon)) {
                    _ = try self.adv();
                    _ = try self.parse_type();
                    if (try self.check(.assign)) {
                        _ = try self.adv();
                        const val = try self.parse_expr();
                        try fields.append(self.alloc, .{ .named = .{ .key = tok.text, .val = val } });
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
            if (try self.eat(.comma) == null and try self.eat(.semi) == null) break;
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

test "parse: empty module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("", &arena);
    try testing.expectEqual(@as(usize, 0), mod.body.stmts.len);
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
    try testing.expect(sz.call.args[0].* == .string_lit);
    try testing.expectEqualStrings("int64_t", sz.call.args[0].string_lit.val);

    const align_expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expect(align_expr.* == .call);
    try testing.expect(align_expr.call.args[0].* == .string_lit);
    try testing.expectEqualStrings("uint8_t*", align_expr.call.args[0].string_lit.val);

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
    try testing.expect(init.call.args[0].* == .string_lit);
    try testing.expectEqualStrings("int64_t", init.call.args[0].string_lit.val);
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

test "parse: macro definition with quote and unquote" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("macro twice(x) `(,x + ,x)", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .macro_def);
    try testing.expectEqualStrings("twice", stmt.macro_def.name);
    try testing.expectEqual(@as(usize, 1), stmt.macro_def.params.len);
    try testing.expectEqualStrings("x", stmt.macro_def.params[0]);
    try testing.expect(stmt.macro_def.body == .expr);
    const body = stmt.macro_def.body.expr;
    try testing.expect(body.* == .binop);
    try testing.expect(body.binop.lhs.* == .unquote);
    try testing.expect(body.binop.rhs.* == .unquote);
}

test "parse: macro definition with quoted statement block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\macro init(x) `do
        \\  local tmp = ,x
        \\  print(tmp)
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .macro_def);
    try testing.expectEqualStrings("init", stmt.macro_def.name);
    try testing.expect(stmt.macro_def.body == .block);
    try testing.expectEqual(@as(usize, 1), stmt.macro_def.body.block.stmts.len);
    try testing.expect(stmt.macro_def.body.block.tail_expr != null);
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
    try testing.expect(stmt.match_stmt.arms[0].pattern.literal.* == .string_lit);
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
    try testing.expect(init.call.args[0].* == .string_lit);
    try testing.expectEqualStrings("llabs", init.call.args[0].string_lit.val);
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
