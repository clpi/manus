//! Canonical `table(key)` application converged onto the direct backend's
//! table-access realization (APPLICATION-ONE, C0 §67 `law.application.one`).
//!
//! Bounded bootstrap bridge (`law.bridge.death`):
//!   HOST OWNER BEFORE — the `[]` index face is the only table access the direct
//!     native path resolves; the canonical `()` application face on a table is
//!     left an unresolved application (`native_backend` reports
//!     `unresolved-application-facts` on the read, `codegen` reports
//!     `assign-target` on the place).
//!   IDOL OWNER AFTER — the semantic graph resolving `table(key)` as a
//!     table-access application in its own right (read = value demand, write =
//!     place demand), with no `.index` AST kind at all.
//!   DELETION CONDITION — delete this pass once the graph owns the `()`
//!     table-access application directly; it exists only to converge the two
//!     source faces onto one identity during S0.
//!
//! It rewrites a parenthesized single-argument `.call` whose callee resolves to
//! an `.array` — the one indexable the direct backend lowers — into the `.index`
//! node that read, place, suitability, and graph-lift already handle. A call it
//! does not convert stays exactly as before, so it can only ever ACCEPT MORE and
//! never regress a working application. It reads sema's type map and never
//! mutates semantic facts; `expr_type` derives the element type from the object,
//! so no type-map entry needs rewriting.

const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");
const types = @import("types.zig");

/// The callee value is a statically known array — `t(i)` is table access, not a
/// call. `.array` is the only indexable the direct backend lowers, and an
/// array-typed value carries no `__call`, so the conversion preserves meaning.
fn calleeIsArray(type_map: *const sema.TypeMap, func: *const ast.Expr) bool {
    const rt = type_map.get(func) orelse return false;
    return rt == .array;
}

fn normalizeExpr(expr: *ast.Expr, type_map: *const sema.TypeMap) void {
    switch (expr.*) {
        .index => |ix| {
            normalizeExpr(ix.obj, type_map);
            normalizeExpr(ix.key, type_map);
        },
        .field => |f| normalizeExpr(f.obj, type_map),
        .binop => |b| {
            normalizeExpr(b.lhs, type_map);
            normalizeExpr(b.rhs, type_map);
        },
        .unop => |u| normalizeExpr(u.operand, type_map),
        .try_expr => |t| normalizeExpr(t.operand, type_map),
        .unwrap_expr => |u| normalizeExpr(u.operand, type_map),
        .await_expr => |a| normalizeExpr(a.operand, type_map),
        .contains_expr => |c| {
            normalizeExpr(c.lhs, type_map);
            normalizeExpr(c.rhs, type_map);
        },
        .range => |r| {
            normalizeExpr(r.start, type_map);
            normalizeExpr(r.end, type_map);
            if (r.step) |s| normalizeExpr(s, type_map);
        },
        .sequence => |s| for (s.exprs) |e| normalizeExpr(e, type_map),
        .if_expr => |ie| {
            normalizeExpr(ie.cond, type_map);
            normalizeExpr(ie.then_expr, type_map);
            normalizeExpr(ie.else_expr, type_map);
        },
        .method_call => |mc| {
            normalizeExpr(mc.obj, type_map);
            for (mc.args) |a| normalizeExpr(a, type_map);
        },
        .table => |t| for (t.fields) |fld| switch (fld) {
            .indexed => |x| {
                normalizeExpr(x.key, type_map);
                normalizeExpr(x.val, type_map);
            },
            .named => |x| normalizeExpr(x.val, type_map),
            .positional => |p| normalizeExpr(p, type_map),
            else => {},
        },
        .func_expr => |fb| normalizeBlock(&fb.body, type_map),
        .call => |c| {
            // Recurse first so nested table applications convert regardless of
            // whether this node itself converts.
            normalizeExpr(c.func, type_map);
            for (c.args) |a| normalizeExpr(a, type_map);
            if (c.form == .parenthesized and c.args.len == 1 and
                calleeIsArray(type_map, c.func))
            {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = c.func, .key = c.args[0] } };
            }
        },
        else => {},
    }
}

fn normalizeBlock(block: *ast.Block, type_map: *const sema.TypeMap) void {
    for (block.stmts) |*stmt| normalizeStmt(stmt, type_map);
    if (block.tail_expr) |te| normalizeExpr(te, type_map);
}

fn normalizeStmt(stmt: *ast.Stmt, type_map: *const sema.TypeMap) void {
    switch (stmt.*) {
        .local_decl => |ld| for (ld.inits) |e| normalizeExpr(e, type_map),
        .const_decl => |cd| normalizeExpr(cd.val, type_map),
        .global_decl => |gd| for (gd.inits) |e| normalizeExpr(e, type_map),
        .assign => |as| {
            for (as.targets) |e| normalizeExpr(e, type_map);
            for (as.values) |e| normalizeExpr(e, type_map);
        },
        .call_stmt => |cs| normalizeExpr(cs.expr, type_map),
        .expr_stmt => |es| normalizeExpr(es.expr, type_map),
        .do_block => |*db| normalizeBlock(&db.body, type_map),
        .while_loop => |*wl| {
            normalizeExpr(wl.cond, type_map);
            normalizeBlock(&wl.body, type_map);
        },
        .repeat_loop => |*rl| {
            normalizeBlock(&rl.body, type_map);
            normalizeExpr(rl.cond, type_map);
        },
        .if_stmt => |*is| {
            if (is.binding) |b| normalizeExpr(b.expr, type_map);
            normalizeExpr(is.cond, type_map);
            normalizeBlock(&is.then, type_map);
            for (is.elseifs) |*ei| {
                normalizeExpr(ei.cond, type_map);
                normalizeBlock(&ei.body, type_map);
            }
            if (is.else_body) |*eb| normalizeBlock(eb, type_map);
        },
        .num_for => |*nf| {
            normalizeExpr(nf.start, type_map);
            normalizeExpr(nf.stop, type_map);
            if (nf.step) |s| normalizeExpr(s, type_map);
            normalizeBlock(&nf.body, type_map);
        },
        .gen_for => |*gf| {
            for (gf.iters) |e| normalizeExpr(e, type_map);
            normalizeBlock(&gf.body, type_map);
        },
        .func_decl => |*fd| normalizeBlock(&fd.func.body, type_map),
        .ret => |r| for (r.vals) |e| normalizeExpr(e, type_map),
        else => {},
    }
}

/// Converge canonical `table(key)` onto the `[]` realization across the module,
/// using sema's finalized type map. Runs after sema and before the native
/// suitability precheck, graph lift, and native emit so all three see one face.
pub fn normalizeModule(mod: *ast.Module, type_map: *const sema.TypeMap) void {
    normalizeBlock(&mod.body, type_map);
}
