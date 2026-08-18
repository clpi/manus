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
const subject_home = @import("subject_home.zig");

/// The callee value is a statically known array — `t(i)` is table access, not a
/// call. `.array` is the only indexable the direct backend lowers, and an
/// array-typed value carries no `__call`, so the conversion preserves meaning.
fn calleeIsArray(type_map: *const sema.TypeMap, func: *const ast.Expr) bool {
    const rt = type_map.get(func) orelse return false;
    return rt == .array;
}

/// The ANCHORED argument projection — `os.arg(i)` and the legacy plural.
///
/// The bare spelling deliberately does NOT match here. It used to, and that was
/// a defect: a user relation named `arg` was silently captured by the injected
/// world and its calls became argument reads. Measured, a relation
/// `arg(v) = v * 7` returned 0 rather than 42, with no diagnostic anywhere.
///
/// Bare names now go through `bareMember`, which refuses any name the program
/// binds. An injected world ADDS reach; it never takes a name already in use.
fn argProjection(func: *const ast.Expr) bool {
    const isArgName = struct {
        fn f(n: []const u8) bool {
            return std.mem.eql(u8, n, "arg") or std.mem.eql(u8, n, "args");
        }
    }.f;
    return switch (func.*) {
        .field => |f| f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "os") and isArgName(f.field),
        else => false,
    };
}

/// THE OS WORLD'S MEMBER EDGES.
///
/// `os` is DEFAULT-INJECTED, so every member edge is reachable BARE from root
/// scope, and the anchored spelling is the DISAMBIGUATOR rather than the
/// canonical form — reserved for a world where the same name is also injected
/// from elsewhere and resolution is genuinely contested:
///
///     env("HOME")       canonical
///     os.env("HOME")    lawful where an anchor disambiguates
///     os.env["HOME"]    legacy, retired `[` accessor
///     os.getenv("HOME") not a lawful name at all — two words glued, a C
///                       legacy name, and LAW-16 wants one irreducible word
///
/// `arg` was admitted bare when the argument ruling landed and the rule was
/// never generalised, so five of the six members were unreachable bare. They
/// are not all the same FACE, which is why the roster is a table and not a
/// list: applying a member projection is ACCESS, applying a member relation is
/// a CALL, and a member value is neither.
///
/// ── THE ROSTER IS ASKED, NOT RESTATED ──────────────────────────────────────
///
/// This file used to carry its own `Member` struct and its own seven rows — a
/// private copy of the `os` world's membership, living in the pass that
/// rewrites it, beside `subject_home`'s two. Three authorities on one fact, and
/// the drift was already visible: `cwd` was `.value` here and its `.value` arm
/// did nothing at all, so `cwd()` and `os.cwd()` both answered DNB011 while
/// `subject_home.os_dot_members` recorded `cwd` as `.direct` — LOWERS.
/// `subject_home.OsMember` now carries the face, the result type and the
/// convergence target, and this pass reads them.
///
/// A member edge is reachable bare only where the name is NOT BOUND by the
/// program. A local, parameter or declared relation named `env` must win over
/// the injected world — capturing it would be a silent wrong answer, and the
/// whole point of deriving reach from injection is that it adds reach without
/// changing what was already there.
///
/// AND THE COUNT DECIDES, NOT A LOOKUP. `subject_home.bareReach` answers
/// `.none`, `.one` or `.ambiguous`, and only `.one` confers a bare name — §42 /
/// `law.inject.algebra`, "ambiguous injection fails rather than picking by
/// declaration import or path priority". Reaching into the `os` roster directly
/// would convert a contested name silently, which is the ordering accident the
/// count exists to remove; asking for the count means a second bare world
/// arriving with a colliding edge leaves the name unconverted and the author
/// reads sema's ambiguity diagnostic instead of getting one of two answers.
fn bareMember(func: *const ast.Expr) ?subject_home.OsMember {
    if (func.* != .name) return null;
    const names = active_names orelse return null;
    if (names.bound.contains(func.name.ident)) return null;
    return switch (subject_home.bareReach(func.name.ident)) {
        .one => |w| if (w == .os) subject_home.osDotMember(func.name.ident) else null,
        .none, .ambiguous => null,
    };
}

/// The ANCHORED face of a member edge — `os.cwd(…)`, `os.clock(…)`.
///
/// A program that binds `os` owns that word, exactly as one that binds `env`
/// owns `env`, so the anchor is refused there and the call stays an ordinary
/// receiver call on the author's own table.
fn anchoredMember(func: *const ast.Expr) ?subject_home.OsMember {
    if (func.* != .field) return null;
    const f = func.field;
    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "os")) return null;
    const names = active_names orelse return null;
    if (names.bound.contains("os")) return null;
    return subject_home.osDotMember(f.field);
}

/// APPLY-ONE (c0 §44 `law.apply.one`): "parenthesized, braced and string faces
/// project onto the SAME application relation... Nothing may switch on it to
/// pick a different object model."
///
/// This convergence was switching on `.parenthesized`, which is precisely what
/// that forbids, and the ruling's own example proved it: `env("HOME")` resolved
/// while `env "HOME"` — the same application through the string face, recorded
/// as `.parenless` — was refused with DNB011. The face is a recorded FACT about
/// how an application was written, never a reason to treat it as a different
/// application.
///
/// `value_reference` and `indirect` are excluded because they are not
/// applications at all: one names the relation without applying it, the other
/// applies something not statically known.
fn isApplicationFace(form: ast.InvocationForm) bool {
    return switch (form) {
        .parenthesized, .parenless, .braced, .command => true,
        .receiver_parenthesized, .receiver_parenless => true,
        .value_reference, .indirect => false,
    };
}

/// `os.env(k)` / `os:env(k)` — the anchored spellings, which stay lawful.
fn envAnchor(func: *const ast.Expr) bool {
    return func.* == .field and func.field.obj.* == .name and
        std.mem.eql(u8, func.field.obj.name.ident, "os") and
        std.mem.eql(u8, func.field.field, "env");
}

/// THE REMOVAL EDGE of the environment projection — `env:remove(k)`.
///
/// REMOVAL IS NOT AN ASSIGNMENT. `env(k) = v` is POSIX `setenv(k, v, 1)`;
/// removal is `unsetenv(k)`, and the two have different observable results —
/// `setenv(k, "", 1)` leaves the variable PRESENT and empty. Spelling removal
/// as `env(k) = nil` would collapse that distinction at the exact place the
/// read face already cannot express it (idol-native/docs/env-identity.md, the
/// §17 fake-nil identity), making it unrecoverable rather than merely
/// unobservable. `dnir_lower.lowerEnvStore` says this in its own header and
/// then had no edge to point at; this is that edge.
///
/// `remove` IS NOT A NEW WORD. `subject_home.sequence_relations` already
/// carries `tbl_("remove")`, and the corpus already spells removal
/// `subject:remove(...)` — `path:remove()`, `trace_spans:remove(n)`. The
/// environment table is a table; removing a key from it is that relation with
/// the world's table as the SUBJECT.
///
/// AND IT TAKES NO NAME. `remove` is reachable only THROUGH a subject, so a
/// user relation `remove(x)` — a bare application, a different node — is
/// untouched, and the subject `env` is refused whenever the program binds it,
/// by the same `bound` census every other bare member edge is refused by.
///
/// BOTH faces ask the binding question, and the anchored one asks it about the
/// ANCHOR. A program that binds `os` owns that word too, so `os.env:remove(k)`
/// on a user table named `os` is an ordinary receiver call and must stay one.
/// The rewrite there would be a no-op today — `os.env` to `os.env` — but the
/// guard belongs beside the recognizer rather than only in the lowering that
/// happens to repeat it, or the next reader has to find both to know the rule.
fn envRemovalSubject(obj: *const ast.Expr) bool {
    const names = active_names orelse return false;
    return switch (obj.*) {
        // The anchored face, already canonical: `os.env:remove(k)`.
        .field => |f| f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "os") and
            std.mem.eql(u8, f.field, "env") and !names.bound.contains("os"),
        // The bare face, admitted only where the program does not bind `env`.
        .name => |n| std.mem.eql(u8, n.ident, "env") and !names.bound.contains("env"),
        else => false,
    };
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
            } else if (mc.args.len == 1 and std.mem.eql(u8, mc.method, "remove") and
                envRemovalSubject(mc.obj))
            {
                // `env:remove(k)` / `os.env:remove(k)` — the REMOVAL edge,
                // converged onto the anchored subject so exactly one shape
                // reaches lowering, the same convergence every other face of
                // this projection gets. Only the SUBJECT is rewritten: the
                // relation stays `remove`, because it already is one.
                var call = mc;
                call.obj = worldTable(alloc, mc.loc, "env") catch return;
                expr.* = .{ .method_call = call };
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
                (calleeIsArray(type_map, c.func) or positionalResultDepth(c.func) != null))
            {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = c.func, .key = c.args[0] } };
                return;
            }
            // THE ANCHORED PROJECTIONS — `os.arg(i)`, `os.args(i)`, `os.env(k)`.
            //
            // These stay lawful: the anchor is what a contested world needs in
            // order to say WHICH `env` is meant. They converge onto the node
            // that already resolves end to end, which for arguments is the
            // PLURAL `os.args` — hence a target distinct from the name.
            //
            // Without this, demagix's `a[i]` -> `a(i)` left `os.env["PATH"]`
            // rewritten into a `.call` the graph could not resolve, because a
            // `.call` carries no application fact it recognises.
            if (isApplicationFace(c.form) and c.args.len == 1 and argProjection(c.func)) {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = argTable(alloc, c.loc) catch return, .key = c.args[0] } };
                return;
            }
            if (isApplicationFace(c.form) and c.args.len == 1 and envAnchor(c.func)) {
                expr.* = .{ .index = .{ .loc = c.loc, .obj = c.func, .key = c.args[0] } };
                return;
            }
            // THE ANCHORED FACE OF A MEMBER *VALUE* — `os.cwd()`.
            //
            // A value applied to nothing IS the value, and `os.cwd` is the node
            // that resolves end to end. Without this the anchored face reached
            // the backend as an application of a relation nothing realizes and
            // answered DNB011 `unresolved-application-facts` — measured, both
            // faces, while the roster recorded `cwd` as LOWERING. The anchor is
            // the DISAMBIGUATOR, so it must reach whatever the bare face
            // reaches; it may never reach less.
            if (isApplicationFace(c.form) and c.args.len == 0) {
                if (anchoredMember(c.func)) |m| {
                    if (m.face == .value) {
                        expr.* = c.func.*;
                        return;
                    }
                }
            }

            // THE BARE MEMBER EDGES of the injected `os` world.
            //
            // `os` is default-injected, so the edge itself is the access point
            // and the anchor is only for disambiguation. `arg` was admitted
            // this way when the argument ruling landed and the rule was never
            // generalised, leaving five of six members unreachable bare.
            //
            // The members are not one kind, and that is the whole reason this
            // dispatches on kind rather than rewriting uniformly: applying a
            // member TABLE is access, applying a member RELATION is a call.
            // Collapsing those would turn `exit(1)` into an index.
            if (bareMember(c.func)) |m| {
                const target = subject_home.osTarget(m);
                switch (m.face) {
                    .projection => if (isApplicationFace(c.form) and c.args.len == 1) {
                        expr.* = .{ .index = .{
                            .loc = c.loc,
                            .obj = worldTable(alloc, c.loc, target) catch return,
                            .key = c.args[0],
                        } };
                    },
                    .relation => {
                        var call = c;
                        call.func = worldTable(alloc, c.loc, target) catch return;
                        expr.* = .{ .call = call };
                    },
                    // A member VALUE applied to nothing IS the value. This arm
                    // was EMPTY, so `cwd()` — the canonical bare face of an edge
                    // the roster records as LOWERING — reached the backend as an
                    // unresolvable application and answered DNB011, while
                    // `d = os.cwd` compiled and ran. The bare face is the
                    // canonical one; it may not be the only one that fails.
                    .value => if (isApplicationFace(c.form) and c.args.len == 0) {
                        expr.* = (worldTable(alloc, c.loc, target) catch return).*;
                    },
                }
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
    /// Number of positional aggregate applications needed to reach a scalar.
    /// A flat `{1, 2}` has depth one; `{{1, 2}, {3, 4}}` has depth two.
    positional: std.StringHashMap(u32),
    callable: std.StringHashMap(void),
    /// EVERY name the program binds — local, global, parameter, declared
    /// relation, loop variable. Used only to REFUSE a world-member conversion:
    /// an injected edge adds reach, it never takes a name the program already
    /// uses. Deliberately over-broad, since a missed conversion is a readable
    /// diagnostic and a wrong one is a silent wrong answer.
    bound: std.StringHashMap(void),

    fn qualifies(self: *const TableNames, name: []const u8) bool {
        return self.positional.contains(name) and !self.callable.contains(name);
    }
};

fn allPositional(e: *const ast.Expr) bool {
    if (e.* != .table or e.table.fields.len == 0) return false;
    for (e.table.fields) |field| if (field != .positional) return false;
    return true;
}

/// Depth this bounded graph-owned family can realize. Returning null preserves
/// the prior one-application normalization for every other positional table;
/// it does not broaden nested projection to strings, mixed leaves, or ragged
/// shapes whose descriptor law is not owned here.
fn positionalIntDepth(e: *const ast.Expr) ?u32 {
    if (e.* != .table) return null;
    if (e.table.fields.len == 0) return null;
    var child_depth: ?u32 = null;
    for (e.table.fields) |f| {
        if (f != .positional) return null;
        const depth: u32 = switch (f.positional.*) {
            .table => positionalIntDepth(f.positional) orelse return null,
            .int_lit => 0,
            else => return null,
        };
        if (child_depth) |known| {
            if (known != depth) return null;
        } else {
            child_depth = depth;
        }
    }
    return (child_depth orelse return null) + 1;
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
            if (fd.path.len > 0) {
                names.callable.put(fd.path[0], {}) catch {};
                names.bound.put(fd.path[0], {}) catch {};
            }
            for (fd.func.params) |prm| names.bound.put(prm.name, {}) catch {};
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
    names.bound.put(name, {}) catch {};
    if (allPositional(init)) {
        names.positional.put(name, positionalIntDepth(init) orelse 1) catch {};
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
        .positional = std.StringHashMap(u32).init(alloc),
        .callable = std.StringHashMap(void).init(alloc),
        .bound = std.StringHashMap(void).init(alloc),
    };
    defer names.positional.deinit();
    defer names.callable.deinit();
    defer names.bound.deinit();
    collectNamesBlock(&names, &mod.body);
    active_names = &names;
    defer active_names = null;
    normalizeBlock(alloc, &mod.body, type_map);
}

/// Set for the duration of `normalizeModule`. The walker threads `alloc` and
/// `type_map` positionally through a dozen functions; adding a third parameter
/// to all of them to carry a read-only lookup earns nothing.
var active_names: ?*const TableNames = null;

fn positionalResultDepth(func: *const ast.Expr) ?u32 {
    const names = active_names orelse return null;
    return switch (func.*) {
        .name => |n| if (names.qualifies(n.ident)) names.positional.get(n.ident) else null,
        .index => |ix| if (positionalResultDepth(ix.obj)) |depth| (if (depth > 1) depth - 1 else null) else null,
        else => null,
    };
}
