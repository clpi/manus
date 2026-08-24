//! AST provenance damage, for the sovereignty gate.
//!
//! `gaps/GAP-202.md` acceptance: "poisoning/removing AST provenance after graph
//! publication leaves machine bytes unchanged". `docs/spec/law.md` §1: "Once
//! known, a fact is carried forward; downstream phases never reconstruct it from
//! syntax or representation." §12: "AST pointers, names, paths, strings, and
//! opcode tags are temporary bridges only".
//!
//! Those are two statements of ONE testable proposition, and this file supplies
//! its instrument: damage the tree AFTER `liftModuleWithCheckedCalls`, realize
//! again from the SAME published graph, and compare object bytes. A byte
//! difference is a syntax read that outlived graph publication, with the exact
//! poison class naming which fact was re-derived.
//!
//! THE SPINE IS PRESERVED, ON PURPOSE. Every poison here rewrites CONTENT in
//! place — a literal's value, an identifier's bytes, a relation's tag — and
//! never frees a node, shortens a slice, or repoints a `*Expr`. The published
//! graph holds raw `Node.ast_ref` pointers into this same arena, so a poison
//! that moved the tree would be measuring use-after-free, not sovereignty.
//! Preserving the spine keeps every `ast_ref` dereferenceable and makes the
//! surviving byte difference mean exactly one thing: a consumer READ THROUGH the
//! pointer and used what it found.
//!
//! `sites` is load-bearing. A poison that damaged nothing proves nothing, so
//! every caller must refuse a zero count rather than record a pass
//! (`law.gate.protocol`, and the vacuity this repository keeps producing).
//!
//! DELETION WITNESS (`law.bridge.death`): this module has no production
//! consumer and never gains one. It is deleted when `dnir_lower` and
//! `native_backend` hold zero `ast_ref` / `valueExpression` reads after graph
//! fact closure, at which point every vertical is trivially sovereign and the
//! gate has nothing left to falsify.

const std = @import("std");
const ast = @import("ast.zig");

/// Which fact the damage attacks. One class per authoritative producer, so a
/// failing vertical names the producer that was re-derived rather than "the
/// AST".
pub const Kind = enum {
    /// Integer literal values. The graph publishes the constant; a consumer
    /// that re-reads `int_lit.val` follows the spelling instead.
    int,
    /// Quoted literal bytes. `semantic_graph.publishSourceQuote` is the one
    /// producer of text identity (GAP-145).
    text,
    /// Every identifier spelling: names, static field labels, method labels,
    /// declaration paths, parameter and binding names. Resolution owns identity;
    /// after it, a name is provenance (`law.md` §1).
    name,
    /// Relation tags on infix applications. The relation identity is a graph
    /// fact; `ast.BinOp` is a recognition tag (`law.md` §11).
    relation,

    pub fn label(self: Kind) []const u8 {
        return @tagName(self);
    }
};

/// A same-length replacement keeps slices and spans structurally identical, so
/// a byte difference cannot be blamed on a length change. Zero-length input is
/// left alone — there is nothing to damage and the site is not counted.
fn poisonBytes(alloc: std.mem.Allocator, original: []const u8) std.mem.Allocator.Error![]const u8 {
    const out = try alloc.alloc(u8, original.len);
    for (out, original) |*byte, source| {
        // Stay inside the identifier alphabet: a poisoned name must remain a
        // name-shaped byte string, otherwise a consumer could differ because
        // the bytes became unprintable rather than because it read them.
        byte.* = switch (source) {
            'a'...'y', 'A'...'Y' => source + 1,
            'z' => 'a',
            'Z' => 'A',
            '0'...'8' => source + 1,
            '9' => '0',
            else => source,
        };
    }
    return out;
}

/// The paired relation a damaged infix application becomes. Each pair stays
/// inside one arity/shape class so the poisoned tree remains well-formed.
fn poisonRelation(op: ast.BinOp) ?ast.BinOp {
    return switch (op) {
        .add => .sub,
        .sub => .add,
        .mul => .div,
        .div => .mul,
        .idiv => .mod,
        .mod => .idiv,
        .band => .bor,
        .bor => .band,
        .bxor => .band,
        .lshift => .rshift,
        .rshift => .lshift,
        .eq => .neq,
        .neq => .eq,
        .lt => .gt,
        .gt => .lt,
        .leq => .geq,
        .geq => .leq,
        .@"and" => .@"or",
        .@"or" => .@"and",
        // `concat`, `pow`, `contains`, `matmul` and `pipeline` have no
        // same-shape partner. Leaving them undamaged is honest: the site is not
        // counted, so a fixture made only of them refuses instead of passing.
        else => null,
    };
}

pub const Damage = struct {
    alloc: std.mem.Allocator,
    kind: Kind,
    sites: usize = 0,
};

/// Damage `mod` in place. Returns the number of damaged sites; a caller that
/// treats zero as anything but a refusal has built a vacuous gate.
pub fn poisonModule(alloc: std.mem.Allocator, mod: *ast.Module, kind: Kind) std.mem.Allocator.Error!usize {
    var damage: Damage = .{ .alloc = alloc, .kind = kind };
    try block(&damage, &mod.body);
    return damage.sites;
}

fn block(d: *Damage, b: *ast.Block) std.mem.Allocator.Error!void {
    for (b.stmts) |*s| try stmt(d, s);
    if (b.tail_expr) |t| try expr(d, t);
}

fn ident(d: *Damage, slot: *[]const u8) std.mem.Allocator.Error!void {
    if (d.kind != .name) return;
    if (slot.len == 0) return;
    slot.* = try poisonBytes(d.alloc, slot.*);
    d.sites += 1;
}

fn funcBody(d: *Damage, f: *ast.FuncBody) std.mem.Allocator.Error!void {
    for (f.params) |*p| {
        try ident(d, &p.name);
        if (p.default_val) |v| try expr(d, v);
    }
    try block(d, &f.body);
}

fn stmt(d: *Damage, s: *ast.Stmt) std.mem.Allocator.Error!void {
    switch (s.*) {
        .local_decl => |*x| {
            for (x.names) |*n| try ident(d, &n.ident);
            for (x.inits) |e| try expr(d, e);
        },
        .global_decl => |*x| {
            for (x.names) |*n| try ident(d, &n.ident);
            for (x.inits) |e| try expr(d, e);
        },
        .const_decl => |*x| {
            try ident(d, &x.ident);
            try expr(d, x.val);
        },
        .assign => |*x| {
            for (x.targets) |e| try expr(d, e);
            for (x.values) |e| try expr(d, e);
        },
        .call_stmt => |*x| try expr(d, x.expr),
        .expr_stmt => |*x| try expr(d, x.expr),
        .do_block => |*x| try block(d, &x.body),
        .while_loop => |*x| {
            try expr(d, x.cond);
            try block(d, &x.body);
        },
        .repeat_loop => |*x| {
            try block(d, &x.body);
            try expr(d, x.cond);
        },
        .if_stmt => |*x| {
            if (x.binding) |*bind| try expr(d, bind.expr);
            try expr(d, x.cond);
            try block(d, &x.then);
            for (x.elseifs) |*e| {
                try expr(d, e.cond);
                try block(d, &e.body);
            }
            if (x.else_body) |*e| try block(d, e);
        },
        .num_for => |*x| {
            try ident(d, &x.var_name);
            try expr(d, x.start);
            try expr(d, x.stop);
            if (x.step) |e| try expr(d, e);
            try block(d, &x.body);
        },
        .gen_for => |*x| {
            for (x.vars) |*v| try ident(d, v);
            for (x.iters) |e| try expr(d, e);
            try block(d, &x.body);
        },
        .func_decl => |*x| {
            for (x.path) |*seg| try ident(d, seg);
            try funcBody(d, &x.func);
        },
        .ret => |*x| for (x.vals) |e| try expr(d, e),
        .match_stmt => |*x| {
            try expr(d, x.scrutinee);
            for (x.arms) |*arm| {
                if (arm.guard) |g| try expr(d, g);
                try block(d, &arm.body);
            }
        },
        .alias_def => |*x| {
            try ident(d, &x.name);
            for (x.fields) |*f| {
                try ident(d, &f.name);
                if (f.default_val) |v| try expr(d, v);
            }
            for (x.methods) |*m| {
                for (m.path) |*seg| try ident(d, seg);
                try funcBody(d, &m.func);
            }
        },
        else => {},
    }
}

fn expr(d: *Damage, e: *ast.Expr) std.mem.Allocator.Error!void {
    switch (e.*) {
        .int_lit => |*x| if (d.kind == .int) {
            // `~val` is never `val`, for every i64 including zero, so the site
            // is always genuinely damaged when it is counted.
            x.val = ~x.val;
            d.sites += 1;
        },
        .float_lit => |*x| if (d.kind == .int) {
            x.val = -(x.val + 1.0);
            d.sites += 1;
        },
        .quoted => |*x| if (d.kind == .text) {
            if (x.val.len != 0) {
                x.val = try poisonBytes(d.alloc, x.val);
                d.sites += 1;
            }
        },
        .name => |*x| try ident(d, &x.ident),
        .index => |*x| {
            try expr(d, x.obj);
            try expr(d, x.key);
        },
        .field => |*x| {
            try expr(d, x.obj);
            try ident(d, &x.field);
        },
        .call => |*x| {
            try expr(d, x.func);
            for (x.args) |a| try expr(d, a);
        },
        .method_call => |*x| {
            try expr(d, x.obj);
            try ident(d, &x.method);
            for (x.args) |a| try expr(d, a);
        },
        .binop => |*x| {
            if (d.kind == .relation) {
                if (poisonRelation(x.op)) |swapped| {
                    x.op = swapped;
                    d.sites += 1;
                }
            }
            try expr(d, x.lhs);
            try expr(d, x.rhs);
        },
        .unop => |*x| try expr(d, x.operand),
        .func_expr => |f| try funcBody(d, f),
        .table => |*x| for (x.fields) |*f| switch (f.*) {
            .indexed => |*y| {
                try expr(d, y.key);
                try expr(d, y.val);
            },
            .named => |*y| {
                try ident(d, &y.key);
                try expr(d, y.val);
            },
            .positional => |v| try expr(d, v),
            .spread => |v| try expr(d, v),
            .semantic => |*y| try expr(d, y.val),
        },
        .list_comp => |*x| {
            try expr(d, x.value);
            try expr(d, x.iter);
            if (x.filter) |f| try expr(d, f);
        },
        .try_expr => |*x| try expr(d, x.operand),
        .unwrap_expr => |*x| try expr(d, x.operand),
        .if_expr => |x| {
            try expr(d, x.cond);
            try expr(d, x.then_expr);
            try expr(d, x.else_expr);
        },
        .match_expr => |x| {
            try expr(d, x.scrutinee);
            for (x.arms) |*arm| {
                if (arm.guard) |g| try expr(d, g);
                try block(d, &arm.body);
            }
        },
        .await_expr => |*x| try expr(d, x.operand),
        .contains_expr => |*x| {
            try expr(d, x.lhs);
            try expr(d, x.rhs);
        },
        .quote => |*x| try expr(d, x.expr),
        .unquote => |*x| try expr(d, x.expr),
        .macro_call => |*x| for (x.args) |a| try expr(d, a),
        .sequence => |*x| for (x.exprs) |a| try expr(d, a),
        .range => |*x| {
            try expr(d, x.start);
            try expr(d, x.end);
            if (x.step) |st| try expr(d, st);
        },
        else => {},
    }
}

const testing = std.testing;

// THE POISON'S OWN POSITIVE CONTROL. Every consumer of this module reasons
// from `sites`, so `sites` must not be able to count a site it did not change.
test "poison: every counted site is actually different afterwards" {
    for ([_][]const u8{ "a", "z", "Z", "9", "mixed42", "_-." }) |original| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const damaged = try poisonBytes(arena.allocator(), original);
        try testing.expectEqual(original.len, damaged.len);
        // `_-.` is the one input with no alphanumeric byte, and it is here to
        // show the rewrite is not a blanket scramble: punctuation survives, so
        // a name made only of it would be counted without being changed. No
        // Idol identifier can have that shape (`law.path.name`), and the
        // fixtures in `sovereign.zig` do not, but the asymmetry is real and
        // stated rather than hidden.
        if (std.mem.eql(u8, original, "_-.")) {
            try testing.expectEqualStrings(original, damaged);
        } else {
            try testing.expect(!std.mem.eql(u8, original, damaged));
        }
    }
}

test "poison: relation damage never returns the relation it was given" {
    for (std.enums.values(ast.BinOp)) |op| {
        if (poisonRelation(op)) |swapped| try testing.expect(swapped != op);
    }
}

test "poison: an integer literal is damaged in place and counted once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    6 * 7
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "poison.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    const tail = module.body.stmts[0].func_decl.func.body.tail_expr orelse
        return error.TestExpectedEqual;
    try testing.expect(tail.* == .binop);
    try testing.expectEqual(@as(i64, 6), tail.binop.lhs.int_lit.val);

    try testing.expectEqual(@as(usize, 2), try poisonModule(alloc, &module, .int));
    // The SAME node, reached through the SAME pointer the graph would hold.
    try testing.expectEqual(@as(i64, ~@as(i64, 6)), tail.binop.lhs.int_lit.val);
    try testing.expectEqual(@as(i64, ~@as(i64, 7)), tail.binop.rhs.int_lit.val);
    // Structure is untouched: `ast_ref` pointers stay dereferenceable.
    try testing.expect(tail.* == .binop and tail.binop.op == .mul);

    try testing.expectEqual(@as(usize, 1), try poisonModule(alloc, &module, .relation));
    try testing.expect(tail.binop.op == .div);
}
