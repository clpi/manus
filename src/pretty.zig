const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
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

pub const SourceComment = struct { line: u32, text: []const u8 };

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
    /// When true in .id mode, omit deprecated keywords (`then`, `do`, bare `fun`).
    canonical: bool = false,
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

    fn binOpPrecedence(op: BinOp) u8 {
        return switch (op) {
            .@"or" => 1,
            .@"and" => 2,
            .eq, .neq, .lt, .gt, .leq, .geq, .contains => 3,
            .concat => 4,
            .add, .sub, .bor, .bxor => 5,
            .mul, .div, .idiv, .mod, .band => 6,
            .matmul => 6,
            .pipeline => 0,
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
                    self.dedent();
                    try self.nl();
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
                try self.printExpr(x.lhs, 3);
                try self.write(" in ");
                try self.printExpr(x.rhs, 3);
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
    fn closeBlock(self: *PrettyPrinter) !void {
        if (self.mode == .idol and self.canonical) return;
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
                if (self.mode == .lua or (self.mode == .idol and !self.canonical)) {
                    try self.write(" then");
                }
                try self.printBlock(&is.then);
                for (is.elseifs) |ei| {
                    try self.nl();
                    try self.write("elseif ");
                    try self.printExpr(ei.cond, 0);
                    if (self.mode == .lua or (self.mode == .idol and !self.canonical)) {
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
                        try self.print("{s}: ", .{ad.name});
                        try self.printTypeExpr(target);
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
        } else if (!self.canonical) {
            try self.write("fun");
        }
        if (fd.path.len > 0) {
            const needs_kw_space = self.mode == .lua or !self.canonical;
            for (fd.path, 0..) |p, i| {
                if (needs_kw_space or i > 0) try self.write(" ");
                try self.write(p);
            }
        }
        if (self.mode == .idol and self.canonical) {
            // CANONICAL BINDING FACE. A relation is `name: result = (params)`,
            // not `name(params) -> result`. The arrow form is a declaration
            // shape; the binding form is what the canon actually writes, and a
            // formatter that emits the other one cannot be used to canonicalise
            // a tree — it would rewrite every relation in the repo into a face
            // the surface does not use.
            if (fd.func.ret_type != .inferred) {
                try self.write(": ");
                try self.printTypeExpr(fd.func.ret_type);
            }
            try self.write(" = ");
            try self.printFuncParamsOnly(&fd.func);
        } else {
            try self.printFuncSig(&fd.func);
        }
        try self.printBlock(&fd.func.body);
        try self.closeBlock();
    }

    /// The parameter pack alone — the result descriptor belongs to the binding
    /// in the canonical face, so it is written before the `=`, not after `)`.
    fn printFuncParamsOnly(self: *PrettyPrinter, fb: *const ast.FuncBody) !void {
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
        if (self.mode == .idol and !self.canonical) try self.write("fun");
        try self.printFuncSig(fb);
        try self.printBlock(&fb.body);
        try self.closeBlock();
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
        if (!(self.mode == .idol and self.canonical)) try self.write("fun ");
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
            self.comment_at += 1;
            try self.write(c.text);
            try self.nl();
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
