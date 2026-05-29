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
            .kw_i8  => { _ = try self.adv(); return .{ .named = "i8" };  },
            .kw_i16 => { _ = try self.adv(); return .{ .named = "i16" }; },
            .kw_i32 => { _ = try self.adv(); return .{ .named = "i32" }; },
            .kw_i64 => { _ = try self.adv(); return .{ .named = "i64" }; },
            .kw_u8  => { _ = try self.adv(); return .{ .named = "u8" };  },
            .kw_u16 => { _ = try self.adv(); return .{ .named = "u16" }; },
            .kw_u32 => { _ = try self.adv(); return .{ .named = "u32" }; },
            .kw_u64 => { _ = try self.adv(); return .{ .named = "u64" }; },
            .kw_f32 => { _ = try self.adv(); return .{ .named = "f32" }; },
            .kw_f64 => { _ = try self.adv(); return .{ .named = "f64" }; },
            .kw_bool => { _ = try self.adv(); return .{ .named = "bool" }; },
            .kw_void => { _ = try self.adv(); return .{ .named = "void" }; },
            .kw_str  => { _ = try self.adv(); return .{ .named = "str" };  },
            .name    => { const t = try self.adv(); return .{ .named = t.text }; },
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
            .kw_end, .kw_else, .kw_elseif, .kw_until, .eof, .semi => {},
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
            .kw_local   => self.parse_local(),
            .kw_global  => self.parse_global(),
            .kw_const   => self.parse_const_decl(),
            .kw_struct  => self.parse_struct_def(),
            .kw_function => self.parse_func_decl(false),
            .kw_if      => self.parse_if(),
            .kw_while   => self.parse_while(),
            .kw_repeat  => self.parse_repeat(),
            .kw_for     => self.parse_for(),
            .kw_do      => self.parse_do(),
            .kw_goto    => blk: {
                _ = try self.adv();
                const lbl = try self.expect(.name);
                break :blk ast.Stmt{ .goto_stmt = .{ .loc = tok.loc, .label = lbl.text } };
            },
            .kw_break   => blk: {
                _ = try self.adv();
                break :blk ast.Stmt{ .brk = tok.loc };
            },
            .dcolon => self.parse_label(),
            else    => self.parse_expr_stmt(),
        };
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
        if (try self.eat(.kw_function) != null) {
            const nm = try self.expect(.name);
            const fb = try self.parse_func_body(l);
            const path = try self.alloc.dupe([]const u8, &[_][]const u8{nm.text});
            return ast.Stmt{ .func_decl = .{
                .loc = l, .path = path, .method = false, .is_local = true, .func = fb,
            }};
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
        }};
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

    fn parse_struct_def(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const nm = try self.expect(.name);
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
                .name = fn_tok.text, .typ = ft, .default = def, .loc = fl,
            });
            if (try self.eat(.comma) == null and !(try self.check(.rbrace))) break;
        }
        _ = try self.expect(.rbrace);
        return ast.Stmt{ .struct_def = .{
            .loc = l, .name = nm.text, .fields = try fields.toOwnedSlice(self.alloc),
        }};
    }

    fn parse_func_decl(self: *Parser, is_local: bool) ParseError!ast.Stmt {
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
        }};
    }

    fn parse_func_body(self: *Parser, l: ast.Loc) ParseError!ast.FuncBody {
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
        _ = try self.expect(.kw_then);
        const then = try self.parse_block();
        var elseifs: std.ArrayList(ast.ElseIf) = .empty;
        var else_body: ?ast.Block = null;
        while (true) {
            if (try self.eat(.kw_elseif) != null) {
                const ec = try self.parse_expr();
                _ = try self.expect(.kw_then);
                const eb = try self.parse_block();
                try elseifs.append(self.alloc, ast.ElseIf{ .cond = ec, .body = eb });
            } else if (try self.eat(.kw_else) != null) {
                else_body = try self.parse_block();
                break;
            } else break;
        }
        _ = try self.expect(.kw_end);
        return ast.Stmt{ .if_stmt = .{
            .loc = l, .cond = cond, .then = then,
            .elseifs = try elseifs.toOwnedSlice(self.alloc), .else_body = else_body,
        }};
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
                .loc = l, .var_name = first_name.text, .var_typ = var_typ,
                .start = start, .stop = stop, .step = step, .body = body,
            }};
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
                .loc = l, .vars = try vars.toOwnedSlice(self.alloc),
                .iters = try iters.toOwnedSlice(self.alloc), .body = body,
            }};
        }
    }

    fn parse_do(self: *Parser) ParseError!ast.Stmt {
        const l = (try self.adv()).loc;
        const body = try self.parse_block();
        _ = try self.expect(.kw_end);
        return ast.Stmt{ .do_block = .{ .loc = l, .body = body } };
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
            }};
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

    // ── Pratt expression parser ───────────────────────────────────────────────

    fn infix_prec(kind: TK) ?struct { op: ast.BinOp, left: u8, right: u8 } {
        return switch (kind) {
            .kw_or   => .{ .op = .@"or",  .left = 1,  .right = 2  },
            .kw_and  => .{ .op = .@"and", .left = 3,  .right = 4  },
            .lt      => .{ .op = .lt,     .left = 5,  .right = 5  },
            .gt      => .{ .op = .gt,     .left = 5,  .right = 5  },
            .leq     => .{ .op = .leq,    .left = 5,  .right = 5  },
            .geq     => .{ .op = .geq,    .left = 5,  .right = 5  },
            .eq      => .{ .op = .eq,     .left = 5,  .right = 5  },
            .neq     => .{ .op = .neq,    .left = 5,  .right = 5  },
            .pipe    => .{ .op = .bor,    .left = 6,  .right = 7  },
            .tilde   => .{ .op = .bxor,   .left = 8,  .right = 9  },
            .amp     => .{ .op = .band,   .left = 10, .right = 11 },
            .lshift  => .{ .op = .lshift, .left = 12, .right = 13 },
            .rshift  => .{ .op = .rshift, .left = 12, .right = 13 },
            .concat  => .{ .op = .concat, .left = 15, .right = 14 }, // right-assoc
            .plus    => .{ .op = .add,    .left = 16, .right = 17 },
            .minus   => .{ .op = .sub,    .left = 16, .right = 17 },
            .star    => .{ .op = .mul,    .left = 18, .right = 19 },
            .slash   => .{ .op = .div,    .left = 18, .right = 19 },
            .idiv    => .{ .op = .idiv,   .left = 18, .right = 19 },
            .percent => .{ .op = .mod,    .left = 18, .right = 19 },
            .caret   => .{ .op = .pow,    .left = 22, .right = 21 }, // right-assoc
            else     => null,
        };
    }

    fn parse_expr(self: *Parser) ParseError!*ast.Expr {
        return self.parse_prec(0);
    }

    fn parse_prec(self: *Parser, min_prec: u8) ParseError!*ast.Expr {
        var lhs = try self.parse_unary();
        while (true) {
            const tok = try self.pk();
            const inf = infix_prec(tok.kind) orelse break;
            if (inf.left <= min_prec) break;
            _ = try self.adv();
            const rhs = try self.parse_prec(inf.right);
            lhs = try self.new_expr(.{ .binop = .{
                .loc = lhs.loc(), .op = inf.op, .lhs = lhs, .rhs = rhs,
            }});
        }
        return lhs;
    }

    fn parse_unary(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        const op: ?ast.UnOp = switch (tok.kind) {
            .kw_not => .not,
            .hash   => .len,
            .minus  => .neg,
            .tilde  => .bnot,
            else    => null,
        };
        if (op) |uop| {
            _ = try self.adv();
            const operand = try self.parse_prec(20);
            return self.new_expr(.{ .unop = .{ .loc = tok.loc, .op = uop, .operand = operand } });
        }
        return self.parse_simple_expr();
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
            .kw_nil   => blk: { _ = try self.adv(); break :blk self.new_expr(.{ .nil       = tok.loc }); },
            .kw_true  => blk: { _ = try self.adv(); break :blk self.new_expr(.{ .true_lit  = tok.loc }); },
            .kw_false => blk: { _ = try self.adv(); break :blk self.new_expr(.{ .false_lit = tok.loc }); },
            .dots     => blk: { _ = try self.adv(); break :blk self.new_expr(.{ .vararg    = tok.loc }); },
            .kw_function => blk: {
                const l = (try self.adv()).loc;
                const fb = try self.new_fb(try self.parse_func_body(l));
                break :blk self.new_expr(.{ .func_expr = fb });
            },
            .lbrace => self.parse_table(),
            else    => self.parse_suffixed_expr(),
        };
    }

    fn parse_suffixed_expr(self: *Parser) ParseError!*ast.Expr {
        var e = try self.parse_primary();
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
                        .loc = tok.loc, .obj = e, .method = method.text, .args = callargs,
                    }});
                },
                .lparen, .lbrace, .string_lit => {
                    const callargs = try self.parse_call_args();
                    e = try self.new_expr(.{ .call = .{ .loc = tok.loc, .func = e, .args = callargs } });
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

    fn parse_primary(self: *Parser) ParseError!*ast.Expr {
        const tok = try self.pk();
        switch (tok.kind) {
            .name => {
                _ = try self.adv();
                return self.new_expr(.{ .name = .{ .loc = tok.loc, .ident = tok.text } });
            },
            .lparen => {
                _ = try self.adv();
                const e = try self.parse_expr();
                _ = try self.expect(.rparen);
                return e;
            },
            else => {
                std.debug.print("{}: unexpected token '{s}' in expression\n", .{ tok.loc, tok.kind.spelling() });
                return ParseError.UnexpectedToken;
            },
        }
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
