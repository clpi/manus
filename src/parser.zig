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
        
        // Check for bash-style function call: name arg1 arg2 ...
        // Works with literals and names, but not with parentheses (to avoid breaking traditional calls)
        if (tok.kind == .name) {
            const peek = try self.pk();
            const is_bash_arg = switch (peek.kind) {
                .string_lit, .int_lit, .float_lit, .name => true,
                else => false,
            };
            
            if (is_bash_arg and peek.kind != .lparen) {
                // This is a bash-style call: print arg1 arg2
                const func_name_tok = try self.adv();
                
                var args: std.ArrayList(*ast.Expr) = .empty;
                
                // Parse the first argument
                try args.append(self.alloc, try self.parse_expr());
                
                // Continue collecting arguments while we have simple tokens
                while (true) {
                    const peek_tok = try self.pk();
                    const is_next_simple = switch (peek_tok.kind) {
                        .string_lit, .int_lit, .float_lit, .name => true,
                        else => false,
                    };
                    if (!is_next_simple) break;
                    if (peek_tok.kind == .semi or peek_tok.kind == .eof or 
                        peek_tok.kind == .kw_end or peek_tok.kind == .kw_else or 
                        peek_tok.kind == .kw_elseif or peek_tok.kind == .kw_until) break;
                    
                    try args.append(self.alloc, try self.parse_expr());
                }
                
                // Create function name expression
                const func_name_expr = try self.alloc.create(ast.Expr);
                func_name_expr.* = .{ .name = .{ .loc = func_name_tok.loc, .ident = func_name_tok.text } };
                
                // Create call expression
                const call_expr = try self.alloc.create(ast.Expr);
                call_expr.* = .{ .call = .{
                    .loc = func_name_tok.loc,
                    .func = func_name_expr,
                    .args = try args.toOwnedSlice(self.alloc),
                }};
                
                return ast.Stmt{ .call_stmt = .{ .loc = func_name_tok.loc, .expr = call_expr } };
            }
        }
        
        return switch (tok.kind) {
            .kw_local   => self.parse_local(),
            .kw_global  => self.parse_global(),
            .kw_const   => self.parse_const_decl(),
            .kw_struct  => self.parse_struct_def(),
            .kw_function, .kw_fun => self.parse_func_decl(false),
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
        if (try self.eat(.kw_function) != null or try self.eat(.kw_fun) != null) {
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
        
        // Accept both regular calls and bash-style calls (which are now parsed as .call expressions)
        switch (first.*) {
            .call, .method_call => {},
            .name => {
                // Single name without args is not a valid statement in Duo
                std.debug.print("{}: expression is not a statement\n", .{first.loc()});
                return ParseError.UnexpectedToken;
            },
            else => {
                std.debug.print("{}: expression is not a statement\n", .{first.loc()});
                return ParseError.UnexpectedToken;
            },
        }
        return ast.Stmt{ .call_stmt = .{ .loc = first.loc(), .expr = first } };
    }

    fn is_expr_start(_: *Parser, kind: TK) bool {
        return switch (kind) {
            .name, .int_lit, .float_lit, .string_lit,
            .kw_nil, .kw_true, .kw_false, .dots,
            .lparen, .lbrace, .lbracket,
            .kw_not, .hash, .minus, .tilde, .hash_hash => true,
            else => false,
        };
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
            .kw_not    => .not,
            .hash      => .len,
            .hash_hash => .compile,
            .minus     => .neg,
            .tilde     => .bnot,
            else       => null,
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
            else    => self.parse_suffixed_expr(),
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
