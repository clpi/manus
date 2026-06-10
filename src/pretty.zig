const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const TypeExpr = ast.TypeExpr;
const Pattern = ast.Pattern;
const Block = ast.Block;
const Module = ast.Module;
const BinOp = ast.BinOp;
const UnOp = ast.UnOp;

pub const Mode = enum {
    duo,
    lua,
};

const Error = error{OutOfMemory};

pub const PrettyPrinter = struct {
    alloc: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    mode: Mode,
    indent_level: usize,
    indent_str: []const u8,

    pub fn init(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), mode: Mode) PrettyPrinter {
        return .{
            .alloc = alloc,
            .buf = buf,
            .mode = mode,
            .indent_level = 0,
            .indent_str = "  ",
        };
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
        for (s) |c| {
            switch (c) {
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                else => try self.write(&[_]u8{c}),
            }
        }
        try self.write("\"");
    }

    // ── Type expressions ──────────────────────────────────────────────────────

    pub fn printTypeExpr(self: *PrettyPrinter, t: TypeExpr) !void {
        switch (t) {
            .inferred => {},
            .named => |n| try self.write(n),
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
        }
    }

    // ── Expressions ─────────────────────────────────────────────────────────────

    fn binOpPrecedence(op: BinOp) u8 {
        return switch (op) {
            .@"or" => 1,
            .@"and" => 2,
            .eq, .neq, .lt, .gt, .leq, .geq, .contains => 3,
            .concat => 4,
            .add, .sub, .bor, .bxor => 5,
            .mul, .div, .idiv, .mod, .band => 6,
            .lshift, .rshift => 7,
            .pow => 8,
        };
    }

    fn printExpr(self: *PrettyPrinter, expr: *const Expr, parent_prec: u8) Error!void {
        const needs_parens = switch (expr.*) {
            .binop => |b| binOpPrecedence(b.op) < parent_prec,
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
            .string_lit => |x| try self.writeStringLit(x.val),
            .vararg => try self.write("..."),
            .name => |x| try self.write(x.ident),
            .index => |x| {
                try self.printExpr(x.obj, 0);
                try self.write("[");
                try self.printExpr(x.key, 0);
                try self.write("]");
            },
            .field => |x| {
                try self.printExpr(x.obj, 0);
                try self.print(".{s}", .{x.field});
            },
            .call => |x| {
                try self.printExpr(x.func, 0);
                try self.write("(");
                for (x.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(arg, 0);
                }
                try self.write(")");
            },
            .method_call => |x| {
                try self.printExpr(x.obj, 0);
                try self.print(":{s}(", .{x.method});
                for (x.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(arg, 0);
                }
                try self.write(")");
            },
            .binop => |x| {
                const prec = binOpPrecedence(x.op);
                try self.printExpr(x.lhs, prec);
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
                    .neq => " ~= ",
                    .lt => " < ",
                    .gt => " > ",
                    .leq => " <= ",
                    .geq => " >= ",
                    .@"and" => " and ",
                    .@"or" => " or ",
                    .contains => " in ",
                };
                try self.write(op_str);
                try self.printExpr(x.rhs, prec);
            },
            .unop => |x| {
                const op_str = switch (x.op) {
                    .neg => "-",
                    .not => "not ",
                    .len => "#",
                    .bnot => "~",
                    .compile => "@",
                };
                try self.write(op_str);
                try self.printExpr(x.operand, 9);
            },
            .func_expr => |f| try self.printFuncBody(f),
            .table => |x| {
                try self.write("{");
                if (x.fields.len > 0) {
                    self.indent();
                    try self.nl();
                    for (x.fields, 0..) |fld, i| {
                        if (i > 0) {
                            try self.write(",");
                            try self.nl();
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
                        }
                    }
                    self.dedent();
                    try self.nl();
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
            .match_expr => |m| try self.printMatchExpr(m),
            .await_expr => |x| {
                try self.write("await ");
                try self.printExpr(x.operand, 0);
            },
            .contains_expr => |x| {
                try self.printExpr(x.lhs, 3);
                try self.write(" in ");
                try self.printExpr(x.rhs, 3);
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

    fn printMatchExpr(self: *PrettyPrinter, m: *const ast.MatchExpr) !void {
        try self.write("match ");
        try self.printExpr(m.scrutinee, 0);
        self.indent();
        for (m.arms) |arm| {
            try self.nl();
            try self.printPattern(arm.pattern);
            try self.write(" =>");
            if (arm.guard) |g| {
                try self.write(" if ");
                try self.printExpr(g, 0);
            }
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
        try self.nl();
        try self.write("end");
    }

    // ── Statements ──────────────────────────────────────────────────────────────

    fn printStmt(self: *PrettyPrinter, stmt: *const Stmt) Error!void {
        switch (stmt.*) {
            .local_decl => |ld| {
                if (self.mode == .lua or self.mode == .duo) {
                    // In Duo mode, bare assignment is preferred, but we pretty-print
                    // with 'local' for explicit clarity in both modes.
                    try self.write("local ");
                }
                for (ld.names, 0..) |name, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(name.ident);
                    if (name.typ != .inferred) {
                        try self.write(": ");
                        try self.printTypeExpr(name.typ);
                    }
                    // attributes
                    for (name.attributes) |attr| {
                        try self.print(" @{s}", .{attr.name});
                        if (attr.args) |args| try self.print("({s})", .{args});
                    }
                }
                if (ld.inits.len > 0) {
                    try self.write(" = ");
                    for (ld.inits, 0..) |inits_val, i| {
                        if (i > 0) try self.write(", ");
                        try self.printExpr(inits_val, 0);
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
                for (as.values, 0..) |v, i| {
                    if (i > 0) try self.write(", ");
                    try self.printExpr(v, 0);
                }
            },
            .call_stmt => |cs| try self.printExpr(cs.expr, 0),
            .expr_stmt => |es| try self.printExpr(es.expr, 0),
            .do_block => |db| {
                try self.write("do");
                try self.printBlock(&db.body);
                try self.nl();
                try self.write("end");
            },
            .while_loop => |wl| {
                try self.write("while ");
                try self.printExpr(wl.cond, 0);
                try self.printBlock(&wl.body);
                try self.nl();
                try self.write("end");
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
                try self.printExpr(is.cond, 0);
                if (self.mode == .lua) {
                    try self.write(" then");
                } else {
                    // Duo: optional 'then'
                    try self.write(" then");
                }
                try self.printBlock(&is.then);
                for (is.elseifs) |ei| {
                    try self.nl();
                    try self.write("elseif ");
                    try self.printExpr(ei.cond, 0);
                    try self.write(" then");
                    try self.printBlock(&ei.body);
                }
                if (is.else_body) |eb| {
                    try self.nl();
                    try self.write("else");
                    try self.printBlock(&eb);
                }
                try self.nl();
                try self.write("end");
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
                try self.nl();
                try self.write("end");
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
                try self.nl();
                try self.write("end");
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
                try self.nl();
                try self.write("end");
            },
            .defer_stmt => |d| {
                try self.write("defer");
                try self.printBlock(&d.body);
                try self.nl();
                try self.write("end");
            },
            .enum_def => |ed| try self.printEnumDef(&ed),
            .concept_def => |cd| try self.printConceptDef(&cd),
            .alias_def => {}, // skip alias defs in pretty-print
        }
    }

    fn printBlock(self: *PrettyPrinter, block: *const Block) Error!void {
        if (block.stmts.len == 0) return;
        self.indent();
        for (block.stmts) |*s| {
            try self.nl();
            try self.printStmt(s);
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
        if (self.mode == .lua) {
            try self.write("function");
        } else {
            try self.write("fun");
        }
        if (fd.path.len > 0) {
            for (fd.path) |p| try self.print(" {s}", .{p});
        }
        try self.printFuncSig(&fd.func);
        try self.printBlock(&fd.func.body);
        try self.nl();
        try self.write("end");
    }

    fn printFuncBody(self: *PrettyPrinter, fb: *const ast.FuncBody) Error!void {
        try self.printFuncSig(fb);
        try self.printBlock(&fb.body);
        try self.nl();
        try self.write("end");
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
        try self.nl();
        try self.write("end");
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
        try self.nl();
        try self.write("end");
    }

    fn printFuncSigParams(self: *PrettyPrinter, sig: *const ast.FuncSignature) !void {
        try self.write("fun ");
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

    pub fn printModule(self: *PrettyPrinter, mod: *const Module) !void {
        for (mod.body.stmts) |*stmt| {
            try self.printStmt(stmt);
            try self.nl();
        }
    }
};

// ── Convenience wrappers ────────────────────────────────────────────────────

pub fn prettyPrint(alloc: std.mem.Allocator, mod: *const Module, mode: Mode) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    var pp = PrettyPrinter.init(alloc, &buf, mode);
    try pp.printModule(mod);
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
    const out = try prettyPrint(alloc, &mod, .duo);
    defer alloc.free(out);
    if (!std.mem.eql(u8, src, out)) {
        std.debug.print("Round-trip mismatch:\n--- original ---\n{s}\n--- printed ---\n{s}\n", .{ src, out });
        return error.RoundTripMismatch;
    }
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
        \\local x: i64 = 1
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
