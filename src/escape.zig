//! Escape analysis.
//!
//! TWO LAYERS LIVE HERE, and they are not equally trustworthy. Read this before
//! wiring either one into a decision that removes storage.
//!
//! LAYER 1 — the Symbol queries (`canStackAllocate`, `shouldPruneArc`). These
//! consume escape status fields that sema is *supposed* to populate. Measured
//! against the tree rather than against the comment that used to sit here:
//!
//!   * `Symbol.escapes` and `Symbol.captured_by_closure` have exactly ONE write
//!     site in the whole compiler — `sema.zig:3900-3901`, inside closure-upvalue
//!     collection. A binding escapes, as far as this compiler is concerned, only
//!     by being captured by a nested function.
//!   * `Symbol.address_taken` has NO write site at all. `grep -rn address_taken
//!     src/` finds the declaration, this file, and nothing else. It is read here
//!     and is always `false`.
//!   * `canStackAllocate`, `shouldPruneArc` and `typeNeedsArc` have NO
//!     production call sites. Every caller is a test in this file. `main.zig`
//!     imports this module and never names a member of it; it reaches into
//!     `sem.escape_names` directly instead.
//!
//! So LAYER 1 reduces to `!is_global and !captured_by_closure`. It says nothing
//! about a value that is RETURNED, PASSED to a relation, or STORED into
//! something that outlives the frame. Do not read a `true` from it as "this
//! value does not escape" — read it as "this value is not a global and is not
//! closed over". Anything that removes storage on the strength of it is unsound
//! today, and would stay unsound until `address_taken` acquires a producer.
//!
//! LAYER 2 — `positionalTableEscapes`, below. Sound by construction, because it
//! is stated in the opposite polarity: it enumerates the ways a name can be
//! mentioned WITHOUT escaping, and treats every other mention, and every syntax
//! it does not model, as an escape. A construct added to the language later is
//! an escape until someone deliberately teaches this function otherwise. That is
//! the polarity a storage-elimination decision needs, and it is why the table
//! work in `table_facts.zig` uses this and not layer 1.

const std = @import("std");
const ast = @import("ast.zig");
const Symbol = @import("sema.zig").Symbol;
const RT = @import("types.zig").ResolvedType;

// ---------------------------------------------------------------------------
// LAYER 1 — Symbol-field queries. See the caveat at the top of this file.
// ---------------------------------------------------------------------------

/// `!is_global and !captured_by_closure and !address_taken`, and nothing more.
///
/// NOT a non-escape proof. `address_taken` has no producer, so the third clause
/// is dead, and no clause covers returning or passing the value. Kept because it
/// is the only stated form of the intended lattice; it must not be used to
/// justify deleting storage until sema populates the fields it reads.
pub fn canStackAllocate(sym: *const Symbol) bool {
    if (sym.is_global) return false;
    if (sym.escapes) return false;
    if (sym.captured_by_closure) return false;
    if (sym.address_taken) return false;
    return true;
}

/// ARC retain/release can be pruned for variables that never escape.
/// Same caveat as `canStackAllocate`: "never escapes" here means "not global and
/// not closed over".
pub fn shouldPruneArc(sym: *const Symbol) bool {
    if (sym.is_global) return false;
    if (sym.escapes) return false;
    if (sym.captured_by_closure) return false;
    return true;
}

/// Check if a type needs ARC management (ownership tracking).
/// This mirrors arc.needsArc and codegen.codegen_needs_arc.
pub fn typeNeedsArc(rt: RT) bool {
    return switch (rt) {
        .str, .array, .pointer, .func, .@"struct" => true,
        .result, .option, .channel, .instantiated, .generic_param => true,
        else => false,
    };
}

// ---------------------------------------------------------------------------
// LAYER 2 — syntactic escape of a positional-table binding.
// ---------------------------------------------------------------------------

/// Why a name was judged to escape. `.none` is the only value that licenses
/// removing the table's storage.
pub const Reason = enum {
    /// No mention of the name outside an access or a length read.
    none,
    /// The name appeared somewhere that needs the aggregate itself: a call
    /// argument, a returned value, a tail expression, an operand of an
    /// arithmetic or comparison node, a loop iterable, …
    aggregate_use,
    /// The whole binding was reassigned (`t = …`) after it was bound.
    rebound,
    /// The body contains a construct this analysis does not model. Fail-closed:
    /// the construct might mention the name in a way that escapes, so it is
    /// treated as though it does.
    unmodelled_construct,
};

pub const Escape = struct {
    reason: Reason = .none,

    pub fn escapes(self: Escape) bool {
        return self.reason != .none;
    }
};

/// Walk state. Separate from the public `Escape` because it carries one thing
/// the answer does not: how many times the body BINDS the name.
///
/// THE BINDING IS NOT A REBIND. `t = (1, 2, 3)` is the statement that brings the
/// table into existence; reading it as `.rebound` marks every table in the
/// language as escaping and eliminates nothing — which is sound, and vacuous,
/// and was the state this file was in. So binds are COUNTED and judged at the
/// end: exactly one is the binding site, two or more is a rebind. Counting
/// rather than position-matching keeps the answer independent of where in the
/// body the binding sits, and needs no second parameter naming it.
const Walk = struct {
    reason: Reason = .none,
    binds: u32 = 0,

    fn raise(self: *Walk, r: Reason) void {
        // First reason wins; `unmodelled_construct` is the least informative and
        // never displaces a concrete one.
        if (self.reason == .none) self.reason = r;
    }

    fn bind(self: *Walk) void {
        self.binds += 1;
    }
};

/// Does `name` — bound in this body to a positional table — ever get used as an
/// aggregate, rather than merely accessed?
///
/// THE POLARITY IS THE POINT. There are exactly four non-escaping mentions of a
/// table name in the modelled surface:
///
///   1. the `.obj` of an `.index` node — `t(k)` after `table_apply` has
///      canonicalized it, or `t[k]`;
///   2. the receiver of `:len()` — which folds to the literal width and never
///      touches storage;
///   3. the operand of `#` (`unop.len`), the same face in the compatibility
///      lexer family; and
///   4. the SINGLE binding of the name. A second one is `.rebound`.
///
/// Everything else escapes, including every syntax not enumerated in the
/// switches below. Adding a language construct therefore *loses* eliminations
/// until someone models it, which is the safe direction to be wrong in. The
/// inverse framing — enumerate the escape routes — silently gains unsound
/// eliminations every time the language grows, which is how a representation
/// decision starts returning wrong answers.
///
/// `table_apply.normalizeModule` MUST have run before this: it is what turns the
/// canonical application face `t(k)` into an `.index` node. Called on a raw parse
/// this function reports `aggregate_use` for every accessed table — conservative,
/// so still sound, but it eliminates nothing.
pub fn positionalTableEscapes(body: *const ast.Block, name: []const u8) Escape {
    var w: Walk = .{};
    walkBlock(body, name, &w);
    // One binding is the binding site. Two is a rebind, and the second value is
    // not knowable from the first literal. Raised last so a concrete escape
    // route found during the walk still names itself first.
    if (w.binds > 1) w.raise(.rebound);
    return .{ .reason = w.reason };
}

fn isName(expr: *const ast.Expr, name: []const u8) bool {
    return expr.* == .name and std.mem.eql(u8, expr.name.ident, name);
}

/// `t:len()` — the extent face, zero arguments. Shared with `table_facts`, which
/// must agree with this walk about which mentions are length reads: one walk
/// calling a mention exempt while the other calls it an access is the
/// disagreement class that produces a slot map the access site cannot address.
pub fn isLengthFace(method: []const u8, arg_count: usize) bool {
    return arg_count == 0 and std.mem.eql(u8, method, "len");
}

/// Visit an expression in a position that does NOT tolerate the aggregate.
fn walkExpr(expr: *const ast.Expr, name: []const u8, e: *Walk) void {
    if (isName(expr, name)) {
        e.raise(.aggregate_use);
        return;
    }
    walkInner(expr, name, e);
}

/// Visit the sub-expressions of `expr`, applying the two exemptions.
fn walkInner(expr: *const ast.Expr, name: []const u8, e: *Walk) void {
    switch (expr.*) {
        // Leaves that cannot mention a name.
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg => {},
        .name => {},

        // EXEMPTION 1 — `t(k)` / `t[k]`. The object may be the table; the key
        // may not be (an index expression that reads the table as a whole is an
        // aggregate use, e.g. `t(t)` — nonsense, but it must not be exempted).
        .index => |ix| {
            if (!isName(ix.obj, name)) walkExpr(ix.obj, name, e);
            walkExpr(ix.key, name, e);
        },

        // EXEMPTION 2 — `#t`, the compatibility-family spelling of the length.
        // Every other unary operator wants the value.
        .unop => |u| {
            if (u.op == .len and isName(u.operand, name)) return;
            walkExpr(u.operand, name, e);
        },

        .field => |f| walkExpr(f.obj, name, e),
        .binop => |b| {
            walkExpr(b.lhs, name, e);
            walkExpr(b.rhs, name, e);
        },
        .call => |c| {
            walkExpr(c.func, name, e);
            for (c.args) |a| walkExpr(a, name, e);
        },
        // EXEMPTION 3 — `t:len()`, which is how the length is spelled in .id.
        // `#` is a COMMENT in the canon lexer family (lexer.zig:828), so
        // exemption 2 above is unreachable from a .id source; without this one
        // the only length face the language actually has reads as an aggregate
        // use and every table that asks its own extent stays materialized.
        .method_call => |mc| {
            if (isLengthFace(mc.method, mc.args.len) and isName(mc.obj, name)) return;
            walkExpr(mc.obj, name, e);
            for (mc.args) |a| walkExpr(a, name, e);
        },
        .table => |t| for (t.fields) |fld| switch (fld) {
            .indexed => |x| {
                walkExpr(x.key, name, e);
                walkExpr(x.val, name, e);
            },
            .named => |x| walkExpr(x.val, name, e),
            .positional => |p| walkExpr(p, name, e),
            .spread => |s| walkExpr(s, name, e),
            .semantic => |s| walkExpr(s.val, name, e),
        },
        .sequence => |s| for (s.exprs) |x| walkExpr(x, name, e),
        .range => |r| {
            walkExpr(r.start, name, e);
            walkExpr(r.end, name, e);
            if (r.step) |s| walkExpr(s, name, e);
        },
        .contains_expr => |c| {
            walkExpr(c.lhs, name, e);
            walkExpr(c.rhs, name, e);
        },
        .try_expr => |t| walkExpr(t.operand, name, e),
        .unwrap_expr => |u| walkExpr(u.operand, name, e),
        .await_expr => |a| walkExpr(a.operand, name, e),
        .if_expr => |ie| {
            walkExpr(ie.cond, name, e);
            walkExpr(ie.then_expr, name, e);
            walkExpr(ie.else_expr, name, e);
        },

        // Everything else — `func_expr`, `list_comp`, `match_expr`, quotation,
        // macro calls, the semantic faces. Fail closed.
        else => e.raise(.unmodelled_construct),
    }
}

fn walkAssignTarget(target: *const ast.Expr, name: []const u8, e: *Walk) void {
    // `t(k) = v` writes an element; `t = v` replaces the binding.
    if (target.* == .index) {
        const ix = target.index;
        if (!isName(ix.obj, name)) walkExpr(ix.obj, name, e);
        walkExpr(ix.key, name, e);
        return;
    }
    if (isName(target, name)) {
        // `t = (…)` is how a table is BOUND in .id — the parser gives an
        // `.assign`, not a declaration. Count it; `positionalTableEscapes`
        // decides at the end whether it was the binding or a rebind.
        e.bind();
        return;
    }
    walkExpr(target, name, e);
}

fn walkBlock(block: *const ast.Block, name: []const u8, e: *Walk) void {
    for (block.stmts) |*st| walkStmt(st, name, e);
    if (block.tail_expr) |t| walkExpr(t, name, e);
}

fn walkStmt(st: *const ast.Stmt, name: []const u8, e: *Walk) void {
    switch (st.*) {
        .local_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) e.bind();
            for (d.inits) |i| walkExpr(i, name, e);
        },
        .global_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) e.bind();
            for (d.inits) |i| walkExpr(i, name, e);
        },
        .const_decl => |d| {
            if (std.mem.eql(u8, d.ident, name)) e.bind();
            walkExpr(d.val, name, e);
        },
        .assign => |a| {
            for (a.targets) |t| walkAssignTarget(t, name, e);
            for (a.values) |v| walkExpr(v, name, e);
        },
        .call_stmt => |c| walkExpr(c.expr, name, e),
        .expr_stmt => |x| walkExpr(x.expr, name, e),
        .do_block => |b| walkBlock(&b.body, name, e),
        .while_loop => |w| {
            walkExpr(w.cond, name, e);
            walkBlock(&w.body, name, e);
        },
        .repeat_loop => |r| {
            walkBlock(&r.body, name, e);
            walkExpr(r.cond, name, e);
        },
        .if_stmt => |f| {
            if (f.binding) |b| walkExpr(b.expr, name, e);
            walkExpr(f.cond, name, e);
            walkBlock(&f.then, name, e);
            for (f.elseifs) |ei| {
                walkExpr(ei.cond, name, e);
                walkBlock(&ei.body, name, e);
            }
            if (f.else_body) |eb| walkBlock(&eb, name, e);
        },
        .num_for => |f| {
            if (std.mem.eql(u8, f.var_name, name)) e.raise(.rebound);
            walkExpr(f.start, name, e);
            walkExpr(f.stop, name, e);
            if (f.step) |s| walkExpr(s, name, e);
            walkBlock(&f.body, name, e);
        },
        .gen_for => |f| {
            for (f.vars) |v| if (std.mem.eql(u8, v, name)) e.raise(.rebound);
            // The iterable wants the aggregate: `for x in t` reads the whole
            // table, so it is an escape and is NOT exempted here.
            for (f.iters) |i| walkExpr(i, name, e);
            walkBlock(&f.body, name, e);
        },
        // `return t` hands the aggregate to the caller.
        .ret => |r| for (r.vals) |v| walkExpr(v, name, e),
        .brk, .cont, .goto_stmt, .label_stmt => {},

        // Nested function declarations can capture; match/try/defer bodies and
        // the definition forms are not modelled. Fail closed.
        else => e.raise(.unmodelled_construct),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "escape: non-escaping local can be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
    };
    try std.testing.expect(canStackAllocate(&sym));
    try std.testing.expect(shouldPruneArc(&sym));
}

test "escape: global cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .is_global = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    try std.testing.expect(!shouldPruneArc(&sym));
}

test "escape: captured local cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .captured_by_closure = true,
        .escapes = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    try std.testing.expect(!shouldPruneArc(&sym));
}

test "escape: address-taken local cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .address_taken = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    // address_taken doesn't affect ARC pruning — the value might not escape
    try std.testing.expect(shouldPruneArc(&sym));
}

test "escape: typeNeedsArc for owned types" {
    try std.testing.expect(typeNeedsArc(.str));
    try std.testing.expect(!typeNeedsArc(.i32));
    try std.testing.expect(!typeNeedsArc(.f64));
    try std.testing.expect(!typeNeedsArc(.bool));
    try std.testing.expect(!typeNeedsArc(.void));
}

// LAYER 1 IS NOT A NON-ESCAPE PROOF. This test exists so that the next person
// to consider wiring `canStackAllocate` into a storage-removal decision meets
// the counterexample first: a symbol that is returned, passed to an unknown
// relation, or otherwise handed out still answers `true`, because nothing in
// the pipeline ever writes `escapes` for those routes and `address_taken` has
// no producer at all.
test "escape: canStackAllocate answers true for a symbol with no producer for its escape facts" {
    var returned = Symbol{ .typ = .void, .is_const = false };
    // Exactly what a returned or argument-passed local looks like coming out of
    // sema today: every escape field still at its default.
    try std.testing.expect(!returned.escapes);
    try std.testing.expect(!returned.address_taken);
    try std.testing.expect(!returned.captured_by_closure);
    try std.testing.expect(canStackAllocate(&returned));
}
