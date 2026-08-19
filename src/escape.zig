//! Conservative escape facts for aggregate-place realization.
//!
//! This file has one job: decide whether a positional table binding is used only
//! through modeled projections/extent reads or whether the aggregate value can
//! escape its binding. It deliberately works in the pessimistic direction:
//! every unmodeled construct escapes until a graph-owned fact proves otherwise.
//!
//! The former Symbol-field layer (`canStackAllocate`, `shouldPruneArc`,
//! `typeNeedsArc`) was deleted. It had no production consumers, `address_taken`
//! had no producer, and its apparent "non-escape" answer omitted return/argument/
//! storage escape routes. Keeping it beside the conservative table analysis was
//! a second, weaker semantic authority with no execution value.
//!
//! Delimiter law is exact here:
//!   * `t[k]` is computed/indexed projection and does not by itself escape `t`;
//!   * `t(k)` is ordinary application, so using `t` as the callee consumes the
//!     aggregate and therefore escapes this bounded analysis;
//!   * `t:len()` and compatibility `#t` observe extent without requiring storage.
//!
//! This is still a bootstrap AST analysis. Exact graph place/access identities,
//! alias/lifetime facts and transformation lineage supersede it under GAP-201.

const std = @import("std");
const ast = @import("ast.zig");

/// Why a name was judged to escape. `.none` is the only value that licenses
/// removing the aggregate's storage in consumers that also satisfy their other
/// legality facts.
pub const Reason = enum {
    /// No mention outside a modeled projection/extent read and the single bind.
    none,
    /// The aggregate itself is consumed: call/callee/argument, return, operand,
    /// loop iterable, tail value, or another modeled whole-value use.
    aggregate_use,
    /// The whole binding was assigned more than once.
    rebound,
    /// The body contains syntax this bounded analysis does not model.
    unmodelled_construct,
};

pub const Escape = struct {
    reason: Reason = .none,

    pub fn escapes(self: Escape) bool {
        return self.reason != .none;
    }
};

const Walk = struct {
    reason: Reason = .none,
    binds: u32 = 0,

    fn raise(self: *Walk, reason: Reason) void {
        if (self.reason == .none) self.reason = reason;
    }

    fn bind(self: *Walk) void {
        self.binds += 1;
    }
};

/// Does `name`, bound in `body` to an aggregate, ever escape the narrow set of
/// modeled place operations?
///
/// Non-escaping mentions are intentionally few:
///
/// 1. the object of an `.index` node (`t[k]`);
/// 2. the receiver of `t:len()`;
/// 3. compatibility `#t`;
/// 4. the single binding site.
///
/// Everything else escapes. In particular, a `.call` whose callee is `t` is not
/// an index and is never exempted. Adding syntax therefore loses eliminations
/// until explicitly modeled, which is the safe direction for storage deletion.
pub fn positionalTableEscapes(body: *const ast.Block, name: []const u8) Escape {
    var walk: Walk = .{};
    walkBlock(body, name, &walk);
    if (walk.binds > 1) walk.raise(.rebound);
    return .{ .reason = walk.reason };
}

fn isName(expr: *const ast.Expr, name: []const u8) bool {
    return expr.* == .name and std.mem.eql(u8, expr.name.ident, name);
}

/// `t:len()` — the current extent face. Shared with `table_facts`; these
/// analyses must agree about extent reads or they can select a representation
/// the access site cannot realize.
pub fn isLengthFace(method: []const u8, arg_count: usize) bool {
    return arg_count == 0 and std.mem.eql(u8, method, "len");
}

fn walkExpr(expr: *const ast.Expr, name: []const u8, walk: *Walk) void {
    if (isName(expr, name)) {
        walk.raise(.aggregate_use);
        return;
    }
    walkInner(expr, name, walk);
}

fn walkInner(expr: *const ast.Expr, name: []const u8, walk: *Walk) void {
    switch (expr.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg => {},
        .name => {},

        // Canonical computed projection. The object may be the aggregate; the
        // key may not consume the aggregate as a whole (`t[t]` still escapes).
        .index => |index| {
            if (!isName(index.obj, name)) walkExpr(index.obj, name, walk);
            walkExpr(index.key, name, walk);
        },

        // Compatibility extent face. In canonical `.id`, `#` is a comment, but
        // compatibility law can still produce this AST node.
        .unop => |unary| {
            if (unary.op == .len and isName(unary.operand, name)) return;
            walkExpr(unary.operand, name, walk);
        },

        .field => |field| walkExpr(field.obj, name, walk),
        .binop => |binary| {
            walkExpr(binary.lhs, name, walk);
            walkExpr(binary.rhs, name, walk);
        },
        // Ordinary application. There is intentionally no table-index special
        // case here: `t(k)` consumes `t` as a callable value.
        .call => |call| {
            walkExpr(call.func, name, walk);
            for (call.args) |arg| walkExpr(arg, name, walk);
        },
        .method_call => |call| {
            if (isLengthFace(call.method, call.args.len) and isName(call.obj, name)) return;
            walkExpr(call.obj, name, walk);
            for (call.args) |arg| walkExpr(arg, name, walk);
        },
        .table => |table| for (table.fields) |field| switch (field) {
            .indexed => |value| {
                walkExpr(value.key, name, walk);
                walkExpr(value.val, name, walk);
            },
            .named => |value| walkExpr(value.val, name, walk),
            .positional => |value| walkExpr(value, name, walk),
            .spread => |value| walkExpr(value, name, walk),
            .semantic => |value| walkExpr(value.val, name, walk),
        },
        .sequence => |sequence| for (sequence.exprs) |value| walkExpr(value, name, walk),
        .range => |range| {
            walkExpr(range.start, name, walk);
            walkExpr(range.end, name, walk);
            if (range.step) |step| walkExpr(step, name, walk);
        },
        .contains_expr => |contains| {
            walkExpr(contains.lhs, name, walk);
            walkExpr(contains.rhs, name, walk);
        },
        .try_expr => |value| walkExpr(value.operand, name, walk),
        .unwrap_expr => |value| walkExpr(value.operand, name, walk),
        .await_expr => |value| walkExpr(value.operand, name, walk),
        .if_expr => |conditional| {
            walkExpr(conditional.cond, name, walk);
            walkExpr(conditional.then_expr, name, walk);
            walkExpr(conditional.else_expr, name, walk);
        },

        // Function/list/match/quotation/macro and any future syntax are unknown
        // to this bounded analysis, therefore fail closed.
        else => walk.raise(.unmodelled_construct),
    }
}

fn walkAssignTarget(target: *const ast.Expr, name: []const u8, walk: *Walk) void {
    // `t[k] = v` mutates one projected place; `t = v` binds/rebinds the whole.
    if (target.* == .index) {
        const index = target.index;
        if (!isName(index.obj, name)) walkExpr(index.obj, name, walk);
        walkExpr(index.key, name, walk);
        return;
    }
    if (isName(target, name)) {
        walk.bind();
        return;
    }
    walkExpr(target, name, walk);
}

fn walkBlock(block: *const ast.Block, name: []const u8, walk: *Walk) void {
    for (block.stmts) |*statement| walkStmt(statement, name, walk);
    if (block.tail_expr) |tail| walkExpr(tail, name, walk);
}

fn walkStmt(statement: *const ast.Stmt, name: []const u8, walk: *Walk) void {
    switch (statement.*) {
        .local_decl => |declaration| {
            for (declaration.names) |local| if (std.mem.eql(u8, local.ident, name)) walk.bind();
            for (declaration.inits) |init| walkExpr(init, name, walk);
        },
        .global_decl => |declaration| {
            for (declaration.names) |local| if (std.mem.eql(u8, local.ident, name)) walk.bind();
            for (declaration.inits) |init| walkExpr(init, name, walk);
        },
        .const_decl => |declaration| {
            if (std.mem.eql(u8, declaration.ident, name)) walk.bind();
            walkExpr(declaration.val, name, walk);
        },
        .assign => |assignment| {
            for (assignment.targets) |target| walkAssignTarget(target, name, walk);
            for (assignment.values) |value| walkExpr(value, name, walk);
        },
        .call_stmt => |call| walkExpr(call.expr, name, walk),
        .expr_stmt => |expression| walkExpr(expression.expr, name, walk),
        .do_block => |block| walkBlock(&block.body, name, walk),
        .while_loop => |loop| {
            walkExpr(loop.cond, name, walk);
            walkBlock(&loop.body, name, walk);
        },
        .repeat_loop => |loop| {
            walkBlock(&loop.body, name, walk);
            walkExpr(loop.cond, name, walk);
        },
        .if_stmt => |conditional| {
            if (conditional.binding) |binding| walkExpr(binding.expr, name, walk);
            walkExpr(conditional.cond, name, walk);
            walkBlock(&conditional.then, name, walk);
            for (conditional.elseifs) |alternative| {
                walkExpr(alternative.cond, name, walk);
                walkBlock(&alternative.body, name, walk);
            }
            if (conditional.else_body) |body| walkBlock(&body, name, walk);
        },
        .num_for => |loop| {
            if (std.mem.eql(u8, loop.var_name, name)) walk.raise(.rebound);
            walkExpr(loop.start, name, walk);
            walkExpr(loop.stop, name, walk);
            if (loop.step) |step| walkExpr(step, name, walk);
            walkBlock(&loop.body, name, walk);
        },
        .gen_for => |loop| {
            for (loop.vars) |variable| if (std.mem.eql(u8, variable, name)) walk.raise(.rebound);
            for (loop.iters) |iter| walkExpr(iter, name, walk);
            walkBlock(&loop.body, name, walk);
        },
        .ret => |result| for (result.vals) |value| walkExpr(value, name, walk),
        .brk, .cont, .goto_stmt, .label_stmt => {},
        else => walk.raise(.unmodelled_construct),
    }
}

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn parseMainBody(alloc: std.mem.Allocator, source: []const u8) !*const ast.Block {
    const owned = try alloc.dupe(u8, source);
    var lexer = Lexer.init(owned, "escape_test.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    for (module.body.stmts) |*statement| {
        if (statement.* == .func_decl and statement.func_decl.path.len == 1 and
            std.mem.eql(u8, statement.func_decl.path[0], "main"))
        {
            return &statement.func_decl.func.body;
        }
    }
    return error.TestExpectedEqual;
}

test "escape: bracket projection does not escape aggregate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const body = try parseMainBody(arena.allocator(),
        \\main: i64 = ()
        \\    t = (10, 20, 30)
        \\    t[2]
        \\
    );
    try std.testing.expectEqual(Reason.none, positionalTableEscapes(body, "t").reason);
}

test "escape: ordinary application of aggregate is not indexed access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const body = try parseMainBody(arena.allocator(),
        \\main: i64 = ()
        \\    t = (10, 20, 30)
        \\    t(2)
        \\
    );
    try std.testing.expectEqual(Reason.aggregate_use, positionalTableEscapes(body, "t").reason);
}

test "escape: passing aggregate escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const body = try parseMainBody(arena.allocator(),
        \\main: i64 = ()
        \\    t = (10, 20, 30)
        \\    sink(t)
        \\    0
        \\
    );
    try std.testing.expectEqual(Reason.aggregate_use, positionalTableEscapes(body, "t").reason);
}

test "escape: second whole binding is a rebind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const body = try parseMainBody(arena.allocator(),
        \\main: i64 = ()
        \\    t = (10, 20, 30)
        \\    t = (40, 50, 60)
        \\    t[1]
        \\
    );
    try std.testing.expectEqual(Reason.rebound, positionalTableEscapes(body, "t").reason);
}
