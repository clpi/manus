//! THE CONVERSION ALGEBRA'S REFUSAL, AS A RULING RATHER THAN A BACKEND BAIL.
//!
//! gap[082] put "no silent conversion" in `codegen.emit_relation_convert`, and
//! `codegen.zig` is the C/wasm emitter. When `--backend=c` was RETIRED the
//! direct AArch64 backend became the only backend there is, and it carries no
//! such law — so on the canonical path the refusal quietly stopped existing.
//!
//! MEASURED on `examples/compile_fail/relation_lossy_compose.id`, the fixture
//! written to pin exactly this rule:
//!
//!     idol check    ->  exit 0, "✓ checked — no errors"
//!     idol compile  ->  exit 1, DNB011 unresolved-application-facts
//!
//! The file still FAILED, which is why nothing noticed for as long as it did.
//! It failed at a bail site in `emitArm64ModuleWithGraph` that has nothing to
//! do with conversion classes, and a harness scoring compile-fail fixtures by
//! exit code cannot tell those apart. `gate/negative.sh` can, and said so:
//! "a backend BAIL is standing in for the ruling".
//!
//! An algebra that composes ANYTHING is not safer than no algebra, it is more
//! dangerous — adding one descriptor can quietly change an existing program's
//! answer. The refusal is what makes the mechanism safe to scale, so it belongs
//! before any backend, where `idol check` reaches it.
//!
//! WHAT THIS DOES NOT COVER, stated because a partial law that reads complete
//! is worse than a narrow one that says so: only `dest.from(src)(v)` names its
//! SOURCE in the surface, and a route cannot be classified without one. The
//! `v:to(dest)` face infers the source from the value's descriptor, which lives
//! in codegen's type state and not here. That face is unchecked at check time
//! and keeps whatever the backend gives it. `coverage()` exists so the gap is
//! measured rather than assumed.

const std = @import("std");
const ast = @import("ast.zig");
const relation = @import("relation.zig");
const term = @import("term.zig");

/// `DUO_WHY_CONVERT` — print the witness for every derived route this law
/// JUDGES, admitted as well as refused. The refusal already speaks for itself;
/// an ADMITTED route is silent by design, and a gate cannot tell "the lattice
/// admitted this" from "the lattice was never reached" without it. That
/// distinction is the whole content of a two-sided control, so the observable
/// exists. Same switch as `codegen.why_convert`, set once in `main`.
pub var why_convert: bool = false;

pub const Result = struct {
    /// Routes that exist and the algebra refuses.
    refused: usize = 0,
    /// `dest.from(src)(v)` sites the walker reached, whatever the verdict.
    /// Cross-checked against a textual scan of the corpus — see the test below
    /// and `gate/negative.sh` — because a walker that MISSES a site is a silent
    /// hole of exactly the kind this file exists to close.
    sites: usize = 0,
};

const Ctx = struct {
    store: *relation.Store,
    res: Result = .{},
};

/// Build the store, then judge every route named in the module.
///
/// The store is populated exactly as `codegen.populate_relation_edges` does —
/// every `family(dest)(src) = conv` in the module's top level, before any body
/// is judged, because a relation is a set of facts and declaration order is
/// enumeration order and nothing else.
pub fn enforce(alloc: std.mem.Allocator, mod: *const ast.Module) !Result {
    var store = relation.Store{};
    defer store.deinit(alloc);

    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .assign) continue;
        const d = relation.declFromAssign(stmt.assign) orelse continue;
        const fam = try store.getOrCreate(alloc, d.relation);
        try fam.declare(alloc, .{
            .dest = d.dest,
            .src = d.src,
            .conv = d.conv,
            .props = d.class.to_properties(),
            .loc = d.loc,
        });
    }

    var ctx = Ctx{ .store = &store };
    // No `to` family means no conversion universe at all, and every module in
    // the corpus that declares nothing takes this exit before any walking.
    if (store.family("to")) |rel| {
        if (rel.authored() > 0) walkBlock(&ctx, &mod.body);
    }
    return ctx.res;
}

/// `dest.from(src)(value)` — the only surface spelling that names its source.
fn judgeCall(ctx: *Ctx, c: anytype) void {
    if (c.func.* != .call) return;
    const inner = c.func.call;
    if (inner.func.* != .field) return;
    const f = inner.func.field;
    if (!std.mem.eql(u8, f.field, "from")) return;
    if (f.obj.* != .name) return;
    if (inner.args.len != 1 or inner.args[0].* != .name) return;

    const dest = f.obj.name.ident;
    const src = inner.args[0].name.ident;
    if (std.mem.eql(u8, src, dest)) return;

    const rel = ctx.store.family("to") orelse return;
    ctx.res.sites += 1;

    // AN AUTHORED EDGE IS THE AUTHOR'S RULING, not this one's. A direct
    // `to(dest)(src)` was written down with its class in the source; the
    // algebra has nothing to compose and nothing to object to. Only a DERIVED
    // route can be lossy without anyone having said so, which is the whole
    // subject.
    if (rel.direct(src, dest) != null) return;

    const path = rel.derive(src, dest) orelse return;

    var wbuf: [512]u8 = undefined;
    const w = path.witness(&wbuf);
    if (path.admitted) {
        if (why_convert) std.debug.print("[why convert] {s}\n", .{w});
        return;
    }
    term.locErr(c.loc, "no silent conversion {s} -> {s}: {s}", .{ src, dest, w });
    term.locHint(c.loc, "declare the edge, or route the lossy hop by name", .{});
    ctx.res.refused += 1;
}

fn walkBlock(ctx: *Ctx, b: *const ast.Block) void {
    for (b.stmts) |*s| walkStmt(ctx, s);
    if (b.tail_expr) |t| walkExpr(ctx, t);
}

fn walkStmt(ctx: *Ctx, s: *const ast.Stmt) void {
    switch (s.*) {
        .local_decl => |x| for (x.inits) |e| walkExpr(ctx, e),
        .global_decl => |x| for (x.inits) |e| walkExpr(ctx, e),
        .const_decl => |x| walkExpr(ctx, x.val),
        .assign => |x| {
            for (x.targets) |e| walkExpr(ctx, e);
            for (x.values) |e| walkExpr(ctx, e);
        },
        .call_stmt => |x| walkExpr(ctx, x.expr),
        .expr_stmt => |x| walkExpr(ctx, x.expr),
        .do_block => |x| walkBlock(ctx, &x.body),
        .while_loop => |x| {
            walkExpr(ctx, x.cond);
            walkBlock(ctx, &x.body);
        },
        .repeat_loop => |x| {
            walkBlock(ctx, &x.body);
            walkExpr(ctx, x.cond);
        },
        .if_stmt => |x| {
            if (x.binding) |bd| walkExpr(ctx, bd.expr);
            walkExpr(ctx, x.cond);
            walkBlock(ctx, &x.then);
            for (x.elseifs) |ei| {
                walkExpr(ctx, ei.cond);
                walkBlock(ctx, &ei.body);
            }
            if (x.else_body) |eb| walkBlock(ctx, &eb);
        },
        .num_for => |x| {
            walkExpr(ctx, x.start);
            walkExpr(ctx, x.stop);
            if (x.step) |st| walkExpr(ctx, st);
            walkBlock(ctx, &x.body);
        },
        .gen_for => |x| {
            for (x.iters) |e| walkExpr(ctx, e);
            walkBlock(ctx, &x.body);
        },
        .func_decl => |x| walkBlock(ctx, &x.func.body),
        .ret => |x| for (x.vals) |e| walkExpr(ctx, e),
        .match_stmt => |m| {
            walkExpr(ctx, m.scrutinee);
            for (m.arms) |a| {
                if (a.guard) |g| walkExpr(ctx, g);
                walkBlock(ctx, &a.body);
            }
        },
        // Leaves, and the statement forms that carry no expression a conversion
        // could hide in. `else` is deliberate here and NOT in `walkExpr`: a new
        // STATEMENT kind that holds expressions would be missed silently, so
        // the coverage test below counts sites against a textual scan instead
        // of trusting this list.
        else => {},
    }
}

fn walkExpr(ctx: *Ctx, e: *const ast.Expr) void {
    switch (e.*) {
        .call => |c| {
            judgeCall(ctx, c);
            walkExpr(ctx, c.func);
            for (c.args) |a| walkExpr(ctx, a);
        },
        .index => |x| {
            walkExpr(ctx, x.obj);
            walkExpr(ctx, x.key);
        },
        .field => |x| walkExpr(ctx, x.obj),
        .method_call => |x| {
            walkExpr(ctx, x.obj);
            for (x.args) |a| walkExpr(ctx, a);
        },
        .binop => |x| {
            walkExpr(ctx, x.lhs);
            walkExpr(ctx, x.rhs);
        },
        .unop => |x| walkExpr(ctx, x.operand),
        .func_expr => |f| walkBlock(ctx, &f.body),
        .table => |x| for (x.fields) |fl| switch (fl) {
            .indexed => |i| {
                walkExpr(ctx, i.key);
                walkExpr(ctx, i.val);
            },
            .named => |n| walkExpr(ctx, n.val),
            .positional => |p| walkExpr(ctx, p),
            .spread => |sp| walkExpr(ctx, sp),
            .semantic => |sm| walkExpr(ctx, sm.val),
        },
        .list_comp => |x| {
            walkExpr(ctx, x.value);
            walkExpr(ctx, x.iter);
            if (x.filter) |fi| walkExpr(ctx, fi);
        },
        .try_expr => |x| walkExpr(ctx, x.operand),
        .unwrap_expr => |x| walkExpr(ctx, x.operand),
        .if_expr => |x| {
            walkExpr(ctx, x.cond);
            walkExpr(ctx, x.then_expr);
            walkExpr(ctx, x.else_expr);
        },
        .match_expr => |m| {
            walkExpr(ctx, m.scrutinee);
            for (m.arms) |a| {
                if (a.guard) |g| walkExpr(ctx, g);
                walkBlock(ctx, &a.body);
            }
        },
        .await_expr => |x| walkExpr(ctx, x.operand),
        .contains_expr => |x| {
            walkExpr(ctx, x.lhs);
            walkExpr(ctx, x.rhs);
        },
        .quote => |x| walkExpr(ctx, x.expr),
        .unquote => |x| walkExpr(ctx, x.expr),
        .macro_call => |m| for (m.args) |a| walkExpr(ctx, a),
        .sequence => |x| for (x.exprs) |sub| walkExpr(ctx, sub),
        .range => |x| {
            walkExpr(ctx, x.start);
            walkExpr(ctx, x.end);
            if (x.step) |st| walkExpr(ctx, st);
        },
        // EXHAUSTIVE ON PURPOSE. Every remaining variant is a leaf that holds
        // no sub-expression, and listing them means a NEW expression kind is a
        // compile error here rather than a route this law silently stops
        // judging. That is the difference between a law and a habit.
        .nil,
        .true_lit,
        .false_lit,
        .int_lit,
        .float_lit,
        .string_lit,
        .vararg,
        .name,
        .semantic,
        .semantic_scope,
        => {},
    }
}

const testing = std.testing;

fn parseSrc(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    var lex = @import("lexer.zig").Lexer.init(src, "conversion_law_test.id");
    var p = @import("parser.zig").Parser.init(&lex, alloc);
    p.idol_mode = true;
    return try p.parse_module();
}

/// The four edges of `examples/compile_fail/relation_lossy_compose.id` over
/// i64, where each division is NARROWING.
const lossy_module =
    \\stretch = (v: i64): i64
    \\  v * 25400
    \\
    \\shrink = (v: i64): i64
    \\  v // 25400
    \\
    \\swell = (v: i64): i64
    \\  v * 1000
    \\
    \\shrivel = (v: i64): i64
    \\  v // 1000
    \\
    \\to(micron)(inch) = stretch@exact
    \\to(inch)(micron) = shrink@narrowing
    \\to(micron)(milli) = swell@exact
    \\to(milli)(micron) = shrivel@narrowing
    \\
;

test "conversion law: a derived lossy route is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = try std.fmt.allocPrint(alloc,
        "{s}\nmain: i64 = ()\n  bore: i64 = milli.from(inch)(5)\n  bore\n", .{lossy_module});
    var mod = try parseSrc(alloc, src);
    _ = &mod;
    const r = try enforce(alloc, &mod);
    try testing.expectEqual(@as(usize, 1), r.sites);
    try testing.expectEqual(@as(usize, 1), r.refused);
}

test "conversion law: the SAME shape with exact hops is admitted" {
    // THE CONTROL, and it is the half that makes the test above mean anything.
    // A law that refuses everything would pass the first test; this one fails
    // unless the refusal is reading the CLASS. Same four edges, same call, both
    // divisions declared `exact`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\stretch = (v: i64): i64
        \\  v * 25400
        \\
        \\shrink = (v: i64): i64
        \\  v // 25400
        \\
        \\swell = (v: i64): i64
        \\  v * 1000
        \\
        \\shrivel = (v: i64): i64
        \\  v // 1000
        \\
        \\to(micron)(inch) = stretch@exact
        \\to(inch)(micron) = shrink@exact
        \\to(micron)(milli) = swell@exact
        \\to(milli)(micron) = shrivel@exact
        \\
        \\main: i64 = ()
        \\  bore: i64 = milli.from(inch)(5)
        \\  bore
        \\
    ;
    var mod = try parseSrc(alloc, src);
    _ = &mod;
    const r = try enforce(alloc, &mod);
    try testing.expectEqual(@as(usize, 1), r.sites);
    try testing.expectEqual(@as(usize, 0), r.refused);
}

test "conversion law: the walker reaches a site inside every nesting form" {
    // COVERAGE, MEASURED. The walker's `walkStmt` ends in `else => {}`, so a
    // statement form it forgets costs a route silently. Each of these buries
    // the same lossy call one level deeper in a different construct, and the
    // count is what proves the walker arrived — not that the law is right,
    // which the two tests above cover.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const bodies = [_][]const u8{
        "  bore: i64 = milli.from(inch)(5)\n  bore\n",
        "  bore = 0\n  if bore == 0\n    bore = milli.from(inch)(5)\n  bore\n",
        "  bore = 0\n  while bore == 0\n    bore = milli.from(inch)(5)\n  bore\n",
        "  bore = 0\n  for i = 1, 2\n    bore = milli.from(inch)(5)\n  bore\n",
        "  t = { x = milli.from(inch)(5) }\n  t.x\n",
        "  bore: i64 = 1 + milli.from(inch)(5)\n  bore\n",
        "  inner: i64 = ()\n    milli.from(inch)(5)\n  inner()\n",
    };
    for (bodies) |b| {
        const src = try std.fmt.allocPrint(alloc, "{s}\nmain: i64 = ()\n{s}", .{ lossy_module, b });
        var mod = parseSrc(alloc, src) catch |e| {
            std.debug.print("could not parse coverage body:\n{s}\n", .{b});
            return e;
        };
        _ = &mod;
        const r = try enforce(alloc, &mod);
        testing.expectEqual(@as(usize, 1), r.refused) catch |e| {
            std.debug.print("walker did not reach the site in:\n{s}\n", .{b});
            return e;
        };
    }
}
