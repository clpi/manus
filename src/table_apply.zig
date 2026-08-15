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

/// True when this callee names the process-argument projection in any lawful
/// spelling: canonical `arg`, explicit `os.arg`, subject-first `os:arg`, or the
/// legacy plural of each.
fn argProjection(func: *const ast.Expr) bool {
    const isArgName = struct {
        fn f(n: []const u8) bool {
            return std.mem.eql(u8, n, "arg") or std.mem.eql(u8, n, "args");
        }
    }.f;
    return switch (func.*) {
        .name => |n| isArgName(n.ident),
        .field => |f| f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "os") and isArgName(f.field),
        else => false,
    };
}

/// `os.env(k)` / `os:env(k)` — the environment projection. `os.env` is a root
/// TABLE, so applying it with one key is access, not a call, exactly as with
/// `os.args`. Only the ANCHORED spellings converge here: the ruling makes
/// `arg(i)` canonical for arguments, but says nothing that would make a bare
/// `env` a reserved name, and three files in this tree define their own
/// `getenv` shim. Converging a bare name would capture those.
fn envAnchor(func: *const ast.Expr) bool {
    return func.* == .field and func.field.obj.* == .name and
        std.mem.eql(u8, func.field.obj.name.ident, "os") and
        std.mem.eql(u8, func.field.field, "env");
}

/// The one node a world projection converges on — `os.args` / `os.env` — which
/// already resolves end to end.
fn worldTable(alloc: std.mem.Allocator, loc: ast.Loc, member: []const u8) !*ast.Expr {
    const os_name = try alloc.create(ast.Expr);
    os_name.* = .{ .name = .{ .loc = loc, .ident = "os" } };
    const fld = try alloc.create(ast.Expr);
    fld.* = .{ .field = .{ .loc = loc, .obj = os_name, .field = member } };
    return fld;
}

fn argTable(alloc: std.mem.Allocator, loc: ast.Loc) !*ast.Expr {
    return worldTable(alloc, loc, "args");
}

fn normalizeExpr(alloc: std.mem.Allocator, expr: *ast.Expr, type_map: *const sema.TypeMap) void {
    switch (expr.*) {
        .index => |ix| {
            normalizeExpr(alloc, ix.obj, type_map);
            normalizeExpr(alloc, ix.key, type_map);
        },
        .field => |f| normalizeExpr(alloc, f.obj, type_map),
        .binop => |b| {
            normalizeExpr(alloc, b.lhs, type_map);
            normalizeExpr(alloc, b.rhs, type_map);
        },
        .unop => |u| normalizeExpr(alloc, u.operand, type_map),
        .try_expr => |t| normalizeExpr(alloc, t.operand, type_map),
        .unwrap_expr => |u| normalizeExpr(alloc, u.operand, type_map),
        .await_expr => |a| normalizeExpr(alloc, a.operand, type_map),
        .contains_expr => |c| {
            normalizeExpr(alloc, c.lhs, type_map);
            normalizeExpr(alloc, c.rhs, type_map);
        },
        .range => |r| {
            normalizeExpr(alloc, r.start, type_map);
            normalizeExpr(alloc, r.end, type_map);
            if (r.step) |s| normalizeExpr(alloc, s, type_map);
        },
        .sequence => |s| for (s.exprs) |e| normalizeExpr(alloc, e, type_map),
        .if_expr => |ie| {
            normalizeExpr(alloc, ie.cond, type_map);
            normalizeExpr(alloc, ie.then_expr, type_map);
            normalizeExpr(alloc, ie.else_expr, type_map);
        },
        .method_call => |mc| {
            normalizeExpr(alloc, mc.obj, type_map);
            for (mc.args) |a| normalizeExpr(alloc, a, type_map);
            // `os:arg(i)` — the subject-first spelling of the same projection.
            // It arrives as a method_call rather than a call, so it needs its
            // own convergence or it type-checks and then refuses at the backend.
            if (mc.args.len == 1 and mc.obj.* == .name and
                std.mem.eql(u8, mc.obj.name.ident, "os") and
                (std.mem.eql(u8, mc.method, "arg") or std.mem.eql(u8, mc.method, "args")))
            {
                expr.* = .{ .index = .{
                    .loc = mc.loc,
                    .obj = argTable(alloc, mc.loc) catch return,
                    .key = mc.args[0],
                } };
            } else if (mc.args.len == 1 and mc.obj.* == .name and
                std.mem.eql(u8, mc.obj.name.ident, "os") and
                std.mem.eql(u8, mc.method, "env"))
            {
                // `os:env(k)` — subject-first face of the same projection.
                expr.* = .{ .index = .{
                    .loc = mc.loc,
                    .obj = worldTable(alloc, mc.loc, "env") catch return,
                    .key = mc.args[0],
                } };
            }
        },
        .table => |t| for (t.fields) |fld| switch (fld) {
            .indexed => |x| {
                normalizeExpr(alloc, x.key, type_map);
                normalizeExpr(alloc, x.val, type_map);
            },
            .named => |x| normalizeExpr(alloc, x.val, type_map),
            .positional => |p| normalizeExpr(alloc, p, type_map),
            else => {},
        },
        .func_expr => |fb| normalizeBlock(alloc, &fb.body, type_map),
        .call => |c| {
            // Recurse first so nested table applications convert regardless of
            // whether this node itself converts.
            normalizeExpr(alloc, c.func, type_map);
            for (c.args) |a| normalizeExpr(alloc, a, type_map);
            if (c.form == .parenthesized and c.args.len == 1 and
                (calleeIsArray(type_map, c.func) or nameIsPositionalTable(c.func)))
            {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = c.func, .key = c.args[0] } };
                return;
            }
            // THE ARGUMENT PROJECTION, whatever it was spelled.
            //
            // `arg(i)` at root scope is canonical — `os` is injected, so the
            // anchor adds nothing, and an identity is singular so `args` is not
            // a name this language admits. `os.arg(i)` and the legacy plural
            // remain lawful where the anchor disambiguates.
            //
            // All of them ARE the projection `os.args[i]`, which already
            // resolves end to end. Converging them here rather than teaching
            // each spelling to the graph is why there is one projection and not
            // four: without it `arg(1)` type-checked and then refused at the
            // backend with `unresolved-application-facts`, because a `.call`
            // carries no application fact the graph recognises.
            if (c.form == .parenthesized and c.args.len == 1 and argProjection(c.func)) {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = argTable(alloc, c.loc) catch return, .key = c.args[0] } };
                return;
            }
            // The ENVIRONMENT projection, for the same reason. Demagix made
            // `a[i]` canonicalize to `a(i)`, which rewrote `os.env["PATH"]` into
            // a `.call` the graph could not resolve — the projection is the
            // `.index`. `os.env` is already the node that resolves, so the
            // application face converges straight back onto it.
            if (c.form == .parenthesized and c.args.len == 1 and envAnchor(c.func)) {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = c.func, .key = c.args[0] } };
            }
        },
        else => {},
    }
}

fn normalizeBlock(alloc: std.mem.Allocator, block: *ast.Block, type_map: *const sema.TypeMap) void {
    for (block.stmts) |*stmt| normalizeStmt(alloc, stmt, type_map);
    if (block.tail_expr) |te| normalizeExpr(alloc, te, type_map);
}

fn normalizeStmt(alloc: std.mem.Allocator, stmt: *ast.Stmt, type_map: *const sema.TypeMap) void {
    switch (stmt.*) {
        .local_decl => |ld| for (ld.inits) |e| normalizeExpr(alloc, e, type_map),
        .const_decl => |cd| normalizeExpr(alloc, cd.val, type_map),
        .global_decl => |gd| for (gd.inits) |e| normalizeExpr(alloc, e, type_map),
        .assign => |as| {
            for (as.targets) |e| normalizeExpr(alloc, e, type_map);
            for (as.values) |e| normalizeExpr(alloc, e, type_map);
        },
        .call_stmt => |cs| normalizeExpr(alloc, cs.expr, type_map),
        .expr_stmt => |es| normalizeExpr(alloc, es.expr, type_map),
        .do_block => |*db| normalizeBlock(alloc, &db.body, type_map),
        .while_loop => |*wl| {
            normalizeExpr(alloc, wl.cond, type_map);
            normalizeBlock(alloc, &wl.body, type_map);
        },
        .repeat_loop => |*rl| {
            normalizeBlock(alloc, &rl.body, type_map);
            normalizeExpr(alloc, rl.cond, type_map);
        },
        .if_stmt => |*is| {
            if (is.binding) |b| normalizeExpr(alloc, b.expr, type_map);
            normalizeExpr(alloc, is.cond, type_map);
            normalizeBlock(alloc, &is.then, type_map);
            for (is.elseifs) |*ei| {
                normalizeExpr(alloc, ei.cond, type_map);
                normalizeBlock(alloc, &ei.body, type_map);
            }
            if (is.else_body) |*eb| normalizeBlock(alloc, eb, type_map);
        },
        .num_for => |*nf| {
            normalizeExpr(alloc, nf.start, type_map);
            normalizeExpr(alloc, nf.stop, type_map);
            if (nf.step) |s| normalizeExpr(alloc, s, type_map);
            normalizeBlock(alloc, &nf.body, type_map);
        },
        .gen_for => |*gf| {
            for (gf.iters) |e| normalizeExpr(alloc, e, type_map);
            normalizeBlock(alloc, &gf.body, type_map);
        },
        .func_decl => |*fd| normalizeBlock(alloc, &fd.func.body, type_map),
        .ret => |r| for (r.vals) |e| normalizeExpr(alloc, e, type_map),
        else => {},
    }
}

/// Names bound to a table literal whose fields are ALL positional — an
/// array-style table — and never bound to anything callable.
///
/// WHY THIS EXISTS. Demagix rules that `a[i]` canonicalizes to `a(i)`, so `a(i)`
/// is the spelling users are told to write. But `calleeIsArray` only converts
/// when sema resolved the callee to `.array`, and a table literal like
/// `xs = (10, 20, 30)` is typed `.any` at that point. The result was that the
/// RETIRED spelling worked and the CANONICAL one was refused:
///
///     xs = (10, 20, 30)
///     xs[2]   -> 20
///     xs(2)   -> DNB011 unresolved-application-facts
///
/// Same shape as the `os.args` / `os.env` breakage: a recognizer keyed on
/// `.index` while the ruling moved the surface to `.call`.
///
/// CONSERVATISM. A name qualifies only if it is bound to an all-positional table
/// literal somewhere and bound to nothing callable anywhere. That is stricter
/// than scope-accurate analysis and deliberately so: converting a genuine call
/// into an index would be a silent wrong answer, whereas declining to convert
/// leaves a diagnostic the user can read. Lua's `__call` is reachable only
/// through the compatibility C backend (`codegen.zig`), never the direct one,
/// so a qualifying table has no callable meaning to lose.
const TableNames = struct {
    positional: std.StringHashMap(void),
    callable: std.StringHashMap(void),

    fn qualifies(self: *const TableNames, name: []const u8) bool {
        return self.positional.contains(name) and !self.callable.contains(name);
    }
};

fn allPositional(e: *const ast.Expr) bool {
    if (e.* != .table) return false;
    if (e.table.fields.len == 0) return false;
    for (e.table.fields) |f| if (f != .positional) return false;
    return true;
}

fn collectNamesBlock(names: *TableNames, block: *const ast.Block) void {
    for (block.stmts) |*stmt| collectNamesStmt(names, stmt);
}

fn collectNamesStmt(names: *TableNames, stmt: *const ast.Stmt) void {
    switch (stmt.*) {
        .local_decl => |ld| bindNames(names, ld.names, ld.inits),
        .global_decl => |gd| bindNames(names, gd.names, gd.inits),
        .assign => |as| for (as.targets, 0..) |t, i| {
            if (t.* != .name or i >= as.values.len) continue;
            note(names, t.name.ident, as.values[i]);
        },
        // A declared relation is callable by construction.
        .func_decl => |*fd| {
            if (fd.path.len > 0) names.callable.put(fd.path[0], {}) catch {};
            collectNamesBlock(names, &fd.func.body);
        },
        .do_block => |*db| collectNamesBlock(names, &db.body),
        .while_loop => |*wl| collectNamesBlock(names, &wl.body),
        .repeat_loop => |*rl| collectNamesBlock(names, &rl.body),
        .if_stmt => |*is| {
            collectNamesBlock(names, &is.then);
            for (is.elseifs) |*ei| collectNamesBlock(names, &ei.body);
            if (is.else_body) |*eb| collectNamesBlock(names, eb);
        },
        .num_for => |*nf| collectNamesBlock(names, &nf.body),
        .gen_for => |*gf| collectNamesBlock(names, &gf.body),
        else => {},
    }
}

fn bindNames(names: *TableNames, idents: []const ast.LocalName, inits: []const *ast.Expr) void {
    for (idents, 0..) |n, i| {
        if (i >= inits.len) continue;
        note(names, n.ident, inits[i]);
    }
}

fn note(names: *TableNames, name: []const u8, init: *const ast.Expr) void {
    if (allPositional(init)) {
        names.positional.put(name, {}) catch {};
    } else {
        // Anything else this name is ever bound to disqualifies it. A lambda is
        // the case that matters; the rest is conservatism, not precision.
        names.callable.put(name, {}) catch {};
    }
    if (init.* == .func_expr) collectNamesBlock(names, &init.func_expr.body);
}

/// Converge canonical `table(key)` onto the `[]` realization across the module,
/// using sema's finalized type map. Runs after sema and before the native
/// suitability precheck, graph lift, and native emit so all three see one face.
pub fn normalizeModule(alloc: std.mem.Allocator, mod: *ast.Module, type_map: *const sema.TypeMap) void {
    var names: TableNames = .{
        .positional = std.StringHashMap(void).init(alloc),
        .callable = std.StringHashMap(void).init(alloc),
    };
    defer names.positional.deinit();
    defer names.callable.deinit();
    collectNamesBlock(&names, &mod.body);
    active_names = &names;
    defer active_names = null;
    normalizeBlock(alloc, &mod.body, type_map);
}

/// Set for the duration of `normalizeModule`. The walker threads `alloc` and
/// `type_map` positionally through a dozen functions; adding a third parameter
/// to all of them to carry a read-only lookup earns nothing.
var active_names: ?*const TableNames = null;

fn nameIsPositionalTable(func: *const ast.Expr) bool {
    const names = active_names orelse return false;
    return func.* == .name and names.qualifies(func.name.ident);
}
