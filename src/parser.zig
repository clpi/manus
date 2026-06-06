const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TK = @import("lexer.zig").TokenKind;
const ast = @import("ast.zig");

pub const ParseError = error{
    UnexpectedToken,
    ExpectedToken,
} || @import("lexer.zig").LexError || Allocator.Error;

pub const Parser = struct {
    lex: *Lexer,
    alloc: Allocator,

    pub fn init(lex: *Lexer, alloc: Allocator) Parser {
        return .{ .lex = lex, .alloc = alloc };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    fn pk(self: *Parser) ParseError!Token {
        return self.lex.peek();
    }

    fn adv(self: *Parser) ParseError!Token {
        return self.lex.next();
    }

    fn expect(self: *Parser, kind: TK) ParseError!Token {
        const tok = try self.adv();
        if (tok.kind != kind) {
            std.debug.print("{}: expected '{s}', got '{s}'\n", .{
                tok.loc, kind.spelling(), tok.kind.spelling(),
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

    fn parse_type(self: *Parser) ParseError!ast.TypeExpr {
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
            .name => {
                const t = try self.adv();
                return .{ .named = t.text };
            },
            .star => {
                _ = try self.adv();
                const inner = try self.alloc.create(ast.TypeExpr);
                inner.* = try self.parse_type();
                return .{ .pointer = inner };
            },
            .lbracket => {
                _ = try self.adv();
                var size: ?usize = null;
                if (try self.check(.int_lit)) {
                    const n = try self.adv();
                    size = @intCast(n.int_val);
                    _ = try self.expect(.rbracket);
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
            else => {
                std.debug.print("{}: expected type, got '{s}'\n", .{ tok.loc, tok.kind.spelling() });
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
                else => try stmts.append(self.alloc, try self.parse_stmt()),
            }
        }
        return ast.Block{ .loc = l, .stmts = try stmts.toOwnedSlice(self.alloc) };
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

        return switch (tok.kind) {
            .at => self.parse_attributed_decl(),
            .kw_local => self.parse_local(),
            .kw_global => self.parse_global(),
            .kw_const => self.parse_const_decl(),
            .kw_struct => self.parse_struct_def_with_attrs(&.{}),
            .kw_function, .kw_fun => self.parse_func_decl_with_attrs(false, &.{}),
            .kw_async => self.parse_async_func_decl_with_attrs(&.{}),
            .kw_enum => self.parse_enum_def_with_attrs(&.{}),
            .kw_concept => self.parse_concept_def_with_attrs(&.{}),
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
            .dcolon => self.parse_label(),
            else => self.parse_expr_stmt(),
        };
    }

    /// Parse one or more `@name` or `@name(args)` attributes, then the declaration
    /// that follows (function, struct, enum, concept, or async function).
    fn parse_attributed_decl(self: *Parser) ParseError!ast.Stmt {
        var attrs: std.ArrayList(ast.Attribute) = .empty;
        while ((try self.pk()).kind == .at) {
            try attrs.append(self.alloc, try self.parse_one_attribute());
        }
        const attrs_slice = try attrs.toOwnedSlice(self.alloc);

        const tok = try self.pk();
        return switch (tok.kind) {
            .kw_function, .kw_fun => self.parse_func_decl_with_attrs(false, attrs_slice),
            .kw_async => self.parse_async_func_decl_with_attrs(attrs_slice),
            .kw_struct => self.parse_struct_def_with_attrs(attrs_slice),
            .kw_enum => self.parse_enum_def_with_attrs(attrs_slice),
            .kw_concept => self.parse_concept_def_with_attrs(attrs_slice),
            else => {
                std.debug.print("{}: expected declaration after attribute(s), got '{s}'\n", .{
                    tok.loc, tok.kind.spelling(),
                });
                return ParseError.UnexpectedToken;
            },
        };
    }

    /// Parse a single attribute: `@name` or `@name(args)`
    fn parse_one_attribute(self: *Parser) ParseError!ast.Attribute {
        _ = try self.expect(.at); // consume `@`
        const name_tok = try self.expect(.name);
        var args: ?[]const u8 = null;
        if ((try self.pk()).kind == .lparen) {
            _ = try self.adv(); // consume `(`
            // Capture everything inside parens as raw text
            args = try self.parse_attribute_args();
            _ = try self.expect(.rparen);
        }
        return ast.Attribute{ .name = name_tok.text, .args = args };
    }

    /// Parse attribute argument text between parens, handling nested parens.
    /// Returns the raw source text content (not including outer parens).
    fn parse_attribute_args(self: *Parser) ParseError![]const u8 {
        // At this point, the opening `(` has already been consumed.
        // The lexer's `peeked` is null and `pos` is right after `(`.
        // We need to find the source range between `(` and matching `)`.

        // Get the position in source right after `(` was consumed.
        // Since we may have a peeked token, clear it by peeking first.
        const first_tok = try self.pk();
        if (first_tok.kind == .rparen) return ""; // empty args

        // Compute start of args in source by looking at first token position.
        // For string_lit tokens, text doesn't include quotes, so we use the
        // pointer to compute where in src the token's semantic text starts.
        // We want the RAW source text including any string delimiters.
        // Use: start = position of first non-whitespace after `(`
        const src = self.lex.src;

        // Walk forward from the `(` to find raw source span.
        // The opening `(` was consumed, so we can compute its end position.
        // We'll determine start from first token's text pointer adjusted for
        // possible quote prefix (for string literals the text pointer is after the quote).
        var start: usize = undefined;
        if (first_tok.kind == .string_lit) {
            // String token text starts after the opening quote
            start = (@intFromPtr(first_tok.text.ptr) - @intFromPtr(src.ptr)) - 1;
        } else {
            start = @intFromPtr(first_tok.text.ptr) - @intFromPtr(src.ptr);
        }

        // Consume tokens until matching `)`, tracking depth
        var depth: u32 = 1;
        var end: usize = start;

        while (depth > 0) {
            const tok = try self.pk();
            if (tok.kind == .eof) {
                std.debug.print("{}: unexpected EOF in attribute arguments\n", .{tok.loc});
                return ParseError.UnexpectedToken;
            }
            if (tok.kind == .rparen) {
                depth -= 1;
                if (depth == 0) break; // don't consume the closing paren
            }
            // Update end to span this token in source
            const tok_start = @intFromPtr(tok.text.ptr) - @intFromPtr(src.ptr);
            if (tok.kind == .string_lit) {
                // Include the closing quote
                end = tok_start + tok.text.len + 1;
            } else {
                end = tok_start + tok.text.len;
            }
            _ = try self.adv();
            if (tok.kind == .lparen) depth += 1;
        }

        if (end <= start) return "";
        return src[start..end];
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

        return ast.Stmt{ .enum_def = .{
            .loc = l,
            .name = nm.text,
            .type_params = type_params,
            .variants = try variants.toOwnedSlice(self.alloc),
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
                std.debug.print("{}: unexpected token in concept body: '{s}'\n", .{
                    (try self.pk()).loc, (try self.pk()).kind.spelling(),
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

    fn parse_struct_def_with_attrs(self: *Parser, attrs: []ast.Attribute) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const nm = try self.expect(.name);

        // Parse optional `implements Concept1, Concept2, ...` clause
        var impl_list: std.ArrayList([]const u8) = .empty;
        if ((try self.pk()).kind == .name and std.mem.eql(u8, (try self.pk()).text, "implements")) {
            _ = try self.adv(); // consume 'implements'
            const first_concept = try self.expect(.name);
            try impl_list.append(self.alloc, first_concept.text);
            while ((try self.pk()).kind == .comma) {
                _ = try self.adv(); // consume ','
                const next_concept = try self.expect(.name);
                try impl_list.append(self.alloc, next_concept.text);
            }
        }

        _ = try self.expect(.lbrace);
        var fields: std.ArrayList(ast.StructField) = .empty;
        while (!(try self.check(.rbrace))) {
            const fl = (try self.pk()).loc;
            const fn_tok = try self.expect(.name);
            _ = try self.expect(.colon);
            const ft = try self.parse_type();
            var def: ?*ast.Expr = null;
            if (try self.eat(.assign) != null) def = try self.parse_expr();
            try fields.append(self.alloc, ast.StructField{
                .name = fn_tok.text,
                .typ = ft,
                .default = def,
                .loc = fl,
            });
            if (try self.eat(.comma) == null and !(try self.check(.rbrace))) break;
        }
        _ = try self.expect(.rbrace);
        return ast.Stmt{ .struct_def = .{
            .loc = l,
            .name = nm.text,
            .fields = try fields.toOwnedSlice(self.alloc),
            .attributes = attrs,
            .implements = try impl_list.toOwnedSlice(self.alloc),
        } };
    }

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
        const fb = try self.parse_func_body(l);
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
            std.debug.print("{}: expected 'function' or 'fun' after 'async', got '{s}'\n", .{
                nxt.loc, nxt.kind.spelling(),
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

    fn parse_param(self: *Parser) ParseError!ast.FuncParam {
        const nm = try self.expect(.name);
        const typ = try self.maybe_type_ann();
        return ast.FuncParam{ .name = nm.text, .typ = typ, .loc = nm.loc };
    }

    fn parse_if(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const cond = try self.parse_expr();
        _ = try self.eat(.kw_then); // `then` is optional in Duo
        const then = try self.parse_block();
        var elseifs: std.ArrayList(ast.ElseIf) = .empty;
        var else_body: ?ast.Block = null;
        while (true) {
            if (try self.eat(.kw_elseif) != null) {
                const ec = try self.parse_expr();
                _ = try self.eat(.kw_then); // `then` is optional in Duo
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
        const cond = try self.parse_expr();
        _ = try self.expect(.kw_do);
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
            _ = try self.expect(.kw_do);
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
            _ = try self.expect(.kw_do);
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
        return ast.Block{ .loc = l, .stmts = try stmts.toOwnedSlice(self.alloc) };
    }

    /// Parse `try ... catch ... end` statement.
    ///
    /// ```
    /// try
    ///   -- body
    /// catch ErrorType e
    ///   -- handle specific error
    /// catch e
    ///   -- handle any error
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

            var error_type: ?ast.TypeExpr = null;
            var binding: ?[]const u8 = null;

            const nxt = try self.pk();
            if (nxt.kind == .name) {
                // Could be either:
                //   catch ErrorType e   (type + binding)
                //   catch e             (binding only, no type)
                // Peek ahead: if we see a name followed by another name, it's type + binding.
                // Otherwise, it's just a binding.
                const saved = self.lex.*;
                const first_name = try self.adv();
                const after = try self.pk();
                if (after.kind == .name) {
                    // `catch ErrorType e` — first_name is the type, next is binding
                    error_type = .{ .named = first_name.text };
                    binding = (try self.adv()).text;
                } else {
                    // `catch e` — first_name is just the binding
                    _ = saved; // don't restore; we already consumed the name
                    binding = first_name.text;
                }
            }

            // Parse the catch body (which also terminates at next `catch` or `end`)
            const catch_body = try self.parse_try_body();
            try catches.append(self.alloc, ast.CatchClause{
                .loc = catch_loc,
                .error_type = error_type,
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
    ///   pattern1 => body1
    ///   pattern2 if guard => body2
    ///   _ => default_body
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
                    .hash_hash => .compile,
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
                    const fld = try self.expect(.name);
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = fld.text } });
                },
                .colon => {
                    _ = try self.adv();
                    const method = try self.expect(.name);
                    // Only allow parenthesized call args after method
                    if ((try self.pk()).kind == .lparen) {
                        const callargs = try self.parse_call_args();
                        e = try self.new_expr(.{ .method_call = .{
                            .loc = tok.loc,
                            .obj = e,
                            .method = method.text,
                            .args = callargs,
                        } });
                    } else {
                        // method with no args — treat as field access
                        e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = method.text } });
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

    /// Parse a single match arm: `pattern [if guard] => body`
    /// The body is either a single expression (as a return statement) or
    /// a block that terminates at the next arm or `end`.
    fn parse_match_arm(self: *Parser) ParseError!ast.MatchArm {
        const pattern = try self.parse_pattern();

        // Optional guard: `if cond`
        var guard: ?*ast.Expr = null;
        if ((try self.pk()).kind == .kw_if) {
            _ = try self.adv(); // consume `if`
            guard = try self.parse_expr();
        }

        _ = try self.expect(.fat_arrow);

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
        while (try self.eat(.semi) != null) {}
        const tok = try self.pk();
        switch (tok.kind) {
            .kw_end, .eof => {},
            .kw_return => {
                // Use restricted return parsing that doesn't consume string/table/array
                // suffixes (those start the next pattern arm).
                const ret_loc = (try self.adv()).loc;
                var vals: std.ArrayList(*ast.Expr) = .empty;
                const nxt = try self.pk();
                switch (nxt.kind) {
                    .kw_end, .kw_else, .kw_elseif, .kw_until, .eof, .semi => {},
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
            },
            else => {
                try stmts.append(self.alloc, try self.parse_stmt());
            },
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
                std.debug.print("{}: expected number after '-' in pattern\n", .{tok.loc});
                return ParseError.UnexpectedToken;
            },
            else => {
                std.debug.print("{}: expected pattern, got '{s}'\n", .{ tok.loc, tok.kind.spelling() });
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
        const first = try self.parse_suffixed_expr();
        const nxt = try self.pk();

        if (nxt.kind == .assign or nxt.kind == .comma) {
            var targets: std.ArrayList(*ast.Expr) = .empty;
            try targets.append(self.alloc, first);
            while (try self.eat(.comma) != null)
                try targets.append(self.alloc, try self.parse_suffixed_expr());
            _ = try self.expect(.assign);
            var values: std.ArrayList(*ast.Expr) = .empty;
            try values.append(self.alloc, try self.parse_expr());
            while (try self.eat(.comma) != null)
                try values.append(self.alloc, try self.parse_expr());
            return ast.Stmt{ .assign = .{
                .loc = first.loc(),
                .targets = try targets.toOwnedSlice(self.alloc),
                .values = try values.toOwnedSlice(self.alloc),
            } };
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
            std.debug.print("{}: expression is not a statement\n", .{first.loc()});
            return ParseError.UnexpectedToken;
        }

        switch (first.*) {
            .call, .method_call => {},
            else => {
                std.debug.print("{}: expression is not a statement\n", .{first.loc()});
                return ParseError.UnexpectedToken;
            },
        }
        return ast.Stmt{ .call_stmt = .{ .loc = first.loc(), .expr = first } };
    }

    fn is_expr_start(_: *Parser, kind: TK) bool {
        return switch (kind) {
            .name, .int_lit, .float_lit, .string_lit, .kw_nil, .kw_true, .kw_false, .dots, .lparen, .lbrace, .lbracket, .kw_not, .hash, .minus, .tilde, .hash_hash, .kw_await => true,
            else => false,
        };
    }

    // ── Pratt expression parser ───────────────────────────────────────────────

    fn infix_prec(kind: TK) ?struct { op: ast.BinOp, left: u8, right: u8 } {
        return switch (kind) {
            .kw_or => .{ .op = .@"or", .left = 1, .right = 2 },
            .kw_and => .{ .op = .@"and", .left = 3, .right = 4 },
            .lt => .{ .op = .lt, .left = 5, .right = 5 },
            .gt => .{ .op = .gt, .left = 5, .right = 5 },
            .leq => .{ .op = .leq, .left = 5, .right = 5 },
            .geq => .{ .op = .geq, .left = 5, .right = 5 },
            .eq => .{ .op = .eq, .left = 5, .right = 5 },
            .neq => .{ .op = .neq, .left = 5, .right = 5 },
            .kw_in => .{ .op = .contains, .left = 5, .right = 5 },
            .pipe => .{ .op = .bor, .left = 6, .right = 7 },
            .tilde => .{ .op = .bxor, .left = 8, .right = 9 },
            .amp => .{ .op = .band, .left = 10, .right = 11 },
            .lshift => .{ .op = .lshift, .left = 12, .right = 13 },
            .rshift => .{ .op = .rshift, .left = 12, .right = 13 },
            .concat => .{ .op = .concat, .left = 15, .right = 14 }, // right-assoc
            .plus => .{ .op = .add, .left = 16, .right = 17 },
            .minus => .{ .op = .sub, .left = 16, .right = 17 },
            .star => .{ .op = .mul, .left = 18, .right = 19 },
            .slash => .{ .op = .div, .left = 18, .right = 19 },
            .idiv => .{ .op = .idiv, .left = 18, .right = 19 },
            .percent => .{ .op = .mod, .left = 18, .right = 19 },
            .caret => .{ .op = .pow, .left = 22, .right = 21 }, // right-assoc
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
            if (tok.kind == .kw_await) {
                _ = try self.adv(); // consume `await`
                const operand = try self.parse_prec(20);
                lhs = try self.new_expr(.{ .await_expr = .{ .loc = tok.loc, .operand = operand } });
            } else {
                const op: ?ast.UnOp = switch (tok.kind) {
                    .kw_not => .not,
                    .hash => .len,
                    .hash_hash => .compile,
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
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            const rhs = try self.parse_prec(inf.right);
            lhs = try self.new_expr(.{ .binop = .{
                .loc = lhs.loc(),
                .op = inf.op,
                .lhs = lhs,
                .rhs = rhs,
            } });
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
            .hash_hash => .compile,
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

    fn parse_simple_expr(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        return switch (tok.kind) {
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
            .lparen => blk: {
                _ = try self.adv();
                const e = try self.parse_expr();
                _ = try self.expect(.rparen);
                break :blk e;
            },
            .lbrace => self.parse_table(),
            .kw_match => self.parse_match_expr(),
            else => {
                std.debug.print("{}: expected expression, got '{s}'\n", .{ tok.loc, tok.kind.spelling() });
                return ParseError.ExpectedToken;
            },
        };
    }

    fn parse_suffixed_expr(self: *Parser) ParseError!*ast.Expr {
        var e = try self.parse_simple_expr();
        while (true) {
            const tok = try self.pk();
            switch (tok.kind) {
                .dot => {
                    _ = try self.adv();
                    const fld = try self.expect(.name);
                    e = try self.new_expr(.{ .field = .{ .loc = tok.loc, .obj = e, .field = fld.text } });
                },
                .lbracket => {
                    _ = try self.adv();
                    const key = try self.parse_expr();
                    _ = try self.expect(.rbracket);
                    e = try self.new_expr(.{ .index = .{ .loc = tok.loc, .obj = e, .key = key } });
                },
                .colon => {
                    _ = try self.adv();
                    const method = try self.expect(.name);
                    const callargs = try self.parse_call_args();
                    e = try self.new_expr(.{ .method_call = .{
                        .loc = tok.loc,
                        .obj = e,
                        .method = method.text,
                        .args = callargs,
                    } });
                },
                .lparen, .lbrace, .string_lit => {
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
                std.debug.print("{}: expected function arguments\n", .{tok.loc});
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
                // Speculate: name '=' means named field; otherwise positional
                const saved = self.lex.*;
                _ = try self.adv();
                if (try self.check(.assign)) {
                    _ = try self.adv();
                    const val = try self.parse_expr();
                    try fields.append(self.alloc, .{ .named = .{ .key = tok.text, .val = val } });
                } else {
                    self.lex.* = saved;
                    const val = try self.parse_expr();
                    try fields.append(self.alloc, .{ .positional = val });
                }
            } else {
                const val = try self.parse_expr();
                try fields.append(self.alloc, .{ .positional = val });
            }
            if (try self.eat(.comma) == null and try self.eat(.semi) == null) break;
        }
        _ = try self.expect(.rbrace);
        return self.new_expr(.{ .table = .{ .loc = l, .fields = try fields.toOwnedSlice(self.alloc) } });
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

test "parse: assignment statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("x = 5", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .assign);
    try testing.expectEqual(@as(usize, 1), stmt.assign.targets.len);
    try testing.expectEqual(@as(usize, 1), stmt.assign.values.len);
}

test "parse: const declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource("const PI = 3", &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .const_decl);
    try testing.expectEqualStrings("PI", stmt.const_decl.ident);
}

test "parse: struct definition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\struct Point {
        \\  x: f64,
        \\  y: f64,
        \\}
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .struct_def);
    try testing.expectEqualStrings("Point", stmt.struct_def.name);
    try testing.expectEqual(@as(usize, 2), stmt.struct_def.fields.len);
    try testing.expectEqualStrings("x", stmt.struct_def.fields[0].name);
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
    try testing.expect(c.error_type == null);
    try testing.expectEqualStrings("e", c.binding.?);
    try testing.expectEqual(@as(usize, 1), c.body.stmts.len);
}

test "parse: try with typed catch clause" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\catch IOError e
        \\  local y = 2
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.try_stmt.catches.len);
    const c = stmt.try_stmt.catches[0];
    try testing.expect(c.error_type != null);
    try testing.expectEqualStrings("IOError", c.error_type.?.named);
    try testing.expectEqualStrings("e", c.binding.?);
}

test "parse: try with multiple catch clauses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\try
        \\  local x = 1
        \\catch IOError e
        \\  local a = 1
        \\catch e
        \\  local b = 2
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .try_stmt);
    try testing.expectEqual(@as(usize, 2), stmt.try_stmt.catches.len);
    // First: typed catch
    const c0 = stmt.try_stmt.catches[0];
    try testing.expect(c0.error_type != null);
    try testing.expectEqualStrings("IOError", c0.error_type.?.named);
    try testing.expectEqualStrings("e", c0.binding.?);
    // Second: untyped catch
    const c1 = stmt.try_stmt.catches[1];
    try testing.expect(c1.error_type == null);
    try testing.expectEqualStrings("e", c1.binding.?);
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
    try testing.expect(c.error_type == null);
    try testing.expect(c.binding == null);
}

test "parse: match statement with wildcard" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match x
        \\  _ => return 1
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
        \\  1 => return "one"
        \\  2 => return "two"
        \\  _ => return "other"
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .match_stmt);
    try testing.expectEqual(@as(usize, 3), stmt.match_stmt.arms.len);
    try testing.expect(stmt.match_stmt.arms[0].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[1].pattern == .literal);
    try testing.expect(stmt.match_stmt.arms[2].pattern == .wildcard);
}

test "parse: match with binding pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\match val
        \\  x => return x
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
        \\  x if x > 0 => return x
        \\  _ => return 0
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
        \\  Option.Some(val) => return val
        \\  Option.None => return nil
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
        \\  {x: a, y: b} => return a + b
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
        \\  [first, second] => return first
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
        \\  [head, ...tail] => return head
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
        \\  1 => return "one"
        \\  _ => return "other"
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
        \\  "start" => return 1
        \\  "stop" => return 0
        \\  _ => return -1
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
        \\  nil => return "nil"
        \\  true => return "yes"
        \\  false => return "no"
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

test "parse: attribute on struct" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@packed
        \\struct Data {
        \\  x: i32,
        \\  y: i32
        \\}
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .struct_def);
    try testing.expectEqualStrings("Data", stmt.struct_def.name);
    try testing.expectEqual(@as(usize, 1), stmt.struct_def.attributes.len);
    try testing.expectEqualStrings("packed", stmt.struct_def.attributes[0].name);
}

test "parse: attribute with numeric arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@align(16)
        \\struct AlignedData {
        \\  x: i64
        \\}
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .struct_def);
    try testing.expectEqual(@as(usize, 1), stmt.struct_def.attributes.len);
    try testing.expectEqualStrings("align", stmt.struct_def.attributes[0].name);
    try testing.expectEqualStrings("16", stmt.struct_def.attributes[0].args.?);
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

test "parse: attribute with ffi string arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const mod = try parseSource(
        \\@ffi("my_c_func")
        \\fun wrapper()
        \\end
    , &arena);
    const stmt = mod.body.stmts[0];
    try testing.expect(stmt == .func_decl);
    try testing.expectEqual(@as(usize, 1), stmt.func_decl.attributes.len);
    try testing.expectEqualStrings("ffi", stmt.func_decl.attributes[0].name);
    try testing.expectEqualStrings("\"my_c_func\"", stmt.func_decl.attributes[0].args.?);
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
