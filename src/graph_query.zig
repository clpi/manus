//! The effect-fact consumer: bounded semantic-graph projections that a compiler
//! decision actually reads.
//!
//! Production queries accept exact graph ids only. Human name/path resolution
//! belongs to an outer UI locator step — never inside these projections.
//!
//! THIS FILE IS DELIBERATELY SMALL. It published 37 projections and 34 of them
//! had no caller anywhere, including tests — an LSP/MCP surface nobody ever
//! wired up, re-exporting `SemanticGraph` methods one-for-one. Every fact that
//! is operative reached its consumer by going around this API, so the API was
//! scenery with an audience of nobody (`HPLS` §7-8). What remains is the three
//! entry points `comptime.zig` calls and the machinery they need.
const std = @import("std");
const ast = @import("ast.zig");
const semantic_graph = @import("semantic_graph.zig");

// ─────────────────────────────────────────────────────────────────────────────
// EFFECT CONSUMER — the query `ApplicationFact.effect` was published for.
//
// `semantic_graph.publishApplicationEffects` writes `.none` onto an application
// only when the whole transitive body behind it is provably unobservable. That
// write site had NO READER: `dnir_lower.foldWholeBody` still refuses any body
// containing an application at all (`bodyHasNoApplication`), because with the
// fact permanently `.unknown` every call might do anything.
//
// This is the reader. It answers ONE question — "is every application in this
// body one the graph proved unobservable?" — and it answers it CONSERVATIVELY:
// anything it cannot line up exactly, on BOTH sides, is a refusal.
//
// TWO SIDES, BOTH REQUIRED, AND THE REASON IS THAT EITHER ALONE IS UNSOUND.
//
//   GRAPH → AST.  Every application CANDIDATE whose enclosing callable is this
//   relation must be published, bound to a relation, and carry `effect == .none`
//   AND `authority == .none`. An unresolved candidate is a call the graph could
//   not identify — `print("hi")` is measured to be exactly that shape — and it
//   must never read as pure.
//
//   AST → GRAPH.  Every application the SOURCE contains must be one of those
//   candidates. This half is not redundant: `types.inferCallShape` recognizes
//   `.call` and `.method_call` only, so a `.macro_call` never becomes a
//   candidate at all and the graph half would walk straight past it. The same
//   argument covers any future expression form that applies something before
//   the lift learns to see it — the AST walk refuses every construct it does
//   not itself enumerate, so a new node kind fails CLOSED.
//
// WHERE THIS RULE STOPS BEING SOUND, stated rather than discovered later:
//
//   1. It inherits `publishApplicationEffects` entirely. If that pass ever
//      promotes something observable, this reads it as pure. The two conditions
//      it leans on hardest are `declarationIsForeign` (an `@ffi` target is
//      INVISIBLE to the graph — it lifts as an ordinary `func` node with an
//      ordinary body, so the fact has to come from the declaration's
//      attributes) and the unresolved-candidate rule that catches `print` and
//      every injected-world face.
//   2. It proves NOTHING about termination, traps, or arithmetic domain. A
//      caller that runs the body must impose its own budget and must treat any
//      evaluator refusal as "do not fold".
//   3. `effect == .none` is a statement about the CALLEE's body, not about the
//      operands at this site. A site whose operands are not themselves
//      compile-time values is still effect-free and still not foldable.
// ─────────────────────────────────────────────────────────────────────────────

/// One application inside a relation body, with the graph facts that prove it
/// unobservable. `expr` is provenance identity (the exact AST pointer the lift
/// recorded), never a name.
pub const EffectFreeSite = struct {
    expr: *const ast.Expr,
    occurrence: semantic_graph.id,
    /// The relation this application binds to, or null for a face the graph
    /// carries no relation id for and that
    /// `SemanticGraph.applicationIsUnobservableStringFace` proved unobservable.
    /// A null callee has nothing to bind: a consumer that runs the body relies
    /// on its own implementation of that face.
    callee: ?semantic_graph.id,
};

pub const EffectQueryError = error{OutOfMemory};

/// Nearest enclosing callable of an entity by `scope`. Null when the entity
/// hangs off a module rather than off a relation.
fn enclosingCallable(
    graph: *const semantic_graph.SemanticGraph,
    from: semantic_graph.id,
) ?semantic_graph.id {
    var cursor: ?semantic_graph.id = from;
    while (cursor) |current| {
        if (graph.callable(current)) return current;
        cursor = graph.homeOf(current);
    }
    return null;
}

/// Every application in `body`, proved effect-free — or null, meaning REFUSED.
///
/// Caller owns the returned slice. Null is the only failure signal: this query
/// never reports a partial proof, because a partial proof of purity is a wrong
/// answer with extra steps.
fn effectFreeApplications(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    caller: semantic_graph.id,
    body: *const ast.Block,
) EffectQueryError!?[]EffectFreeSite {
    if (!graph.callable(caller)) return null;

    var sites: std.ArrayListUnmanaged(EffectFreeSite) = .empty;
    errdefer sites.deinit(alloc);

    // GRAPH → AST.
    for (graph.nodes.items, 0..) |node, coordinate| {
        const occurrence: semantic_graph.id = std.math.cast(semantic_graph.id, coordinate) orelse {
            sites.deinit(alloc);
            return null;
        };
        if (!graph.isApplicationCandidate(occurrence)) continue;
        const scope = node.scope orelse {
            sites.deinit(alloc);
            return null;
        };
        const holder = enclosingCallable(graph, scope) orelse continue;
        if (holder != caller) continue;

        const fact = graph.application(occurrence) orelse {
            // The ONE unresolved shape that is still provably unobservable, and
            // the consumer must admit exactly the sites the fixpoint declined
            // to block or the two disagree about what "effect-free" means.
            if (graph.applicationIsUnobservableStringFace(occurrence)) {
                const face_raw = node.ast_ref orelse {
                    sites.deinit(alloc);
                    return null;
                };
                try sites.append(alloc, .{
                    .expr = @ptrCast(@alignCast(face_raw)),
                    .occurrence = occurrence,
                    .callee = null,
                });
                continue;
            }
            // Everything else — `print(...)`, an injected world face, any call
            // the checker could not identify. Never pure.
            sites.deinit(alloc);
            return null;
        };
        if (fact.effect != .none or fact.authority != .none) {
            sites.deinit(alloc);
            return null;
        }
        const callee = graph.applicationRelation(occurrence) orelse {
            sites.deinit(alloc);
            return null;
        };
        const raw = node.ast_ref orelse {
            sites.deinit(alloc);
            return null;
        };
        try sites.append(alloc, .{
            .expr = @ptrCast(@alignCast(raw)),
            .occurrence = occurrence,
            .callee = callee,
        });
    }

    // AST → GRAPH.
    var written: std.ArrayListUnmanaged(*const ast.Expr) = .empty;
    defer written.deinit(alloc);
    var walk: ApplicationWalk = .{ .alloc = alloc, .out = &written };
    if (!(walk.block(body) catch |err| {
        sites.deinit(alloc);
        return err;
    })) {
        sites.deinit(alloc);
        return null;
    }
    if (written.items.len != sites.items.len) {
        sites.deinit(alloc);
        return null;
    }
    for (written.items) |expression| {
        var seen = false;
        for (sites.items) |site| {
            if (site.expr != expression) continue;
            if (seen) {
                sites.deinit(alloc);
                return null;
            }
            seen = true;
        }
        if (!seen) {
            sites.deinit(alloc);
            return null;
        }
    }

    return try sites.toOwnedSlice(alloc);
}

/// Relation bodies reachable from `body` through applications the graph proved
/// effect-free, transitively — or null, meaning REFUSED. The entry relation is
/// not included; every element is a distinct callee.
///
/// The least fixpoint never promotes a recursive relation, so this closure
/// cannot cycle through published facts; the visited set is kept anyway,
/// because a query that relies on an invariant it does not check is how the
/// invariant stops holding.
pub fn effectFreeCalleeClosure(
    graph: *const semantic_graph.SemanticGraph,
    alloc: std.mem.Allocator,
    caller: semantic_graph.id,
    body: *const ast.Block,
) EffectQueryError!?[]semantic_graph.id {
    var visited: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    errdefer visited.deinit(alloc);
    var pending: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
    defer pending.deinit(alloc);

    const entry = try effectFreeApplications(graph, alloc, caller, body) orelse {
        visited.deinit(alloc);
        return null;
    };
    defer alloc.free(entry);
    for (entry) |site| if (site.callee) |callee| try pending.append(alloc, callee);

    while (pending.items.len > 0) {
        const callee = pending.pop().?;
        if (callee == caller) continue;
        var already = false;
        for (visited.items) |seen| {
            if (seen == callee) already = true;
        }
        if (already) continue;
        try visited.append(alloc, callee);

        const declaration = relationDeclaration(graph, callee) orelse {
            visited.deinit(alloc);
            return null;
        };
        const nested = try effectFreeApplications(graph, alloc, callee, &declaration.func.body) orelse {
            visited.deinit(alloc);
            return null;
        };
        defer alloc.free(nested);
        for (nested) |site| if (site.callee) |next_callee| try pending.append(alloc, next_callee);
    }
    return try visited.toOwnedSlice(alloc);
}

/// The module declaration the graph was lifted from, when it has one.
pub fn moduleDeclaration(graph: *const semantic_graph.SemanticGraph) ?*const ast.Module {
    return graph.module_ast;
}

/// The declaration a callable entity was lifted from. Provenance, not lookup:
/// the graph recorded this exact pointer at lift.
pub fn relationDeclaration(
    graph: *const semantic_graph.SemanticGraph,
    callable: semantic_graph.id,
) ?*const ast.FuncDecl {
    if (!graph.callable(callable)) return null;
    const node = graph.get(callable) orelse return null;
    const raw = node.ast_ref orelse return null;
    return @ptrCast(@alignCast(raw));
}

/// Collects every application expression in a body and REFUSES any construct
/// it does not itself enumerate. The refusal is the point: an unenumerated node
/// kind may apply something, and an application this walk does not see is an
/// application nobody checks.
const ApplicationWalk = struct {
    alloc: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(*const ast.Expr),

    fn block(self: *ApplicationWalk, b: *const ast.Block) EffectQueryError!bool {
        for (b.stmts) |*st| if (!(try self.stmt(st))) return false;
        if (b.tail_expr) |te| return try self.expr(te);
        return true;
    }

    fn stmt(self: *ApplicationWalk, st: *const ast.Stmt) EffectQueryError!bool {
        switch (st.*) {
            .local_decl => |d| {
                for (d.inits) |e| if (!(try self.expr(e))) return false;
                return true;
            },
            .assign => |a| {
                for (a.targets) |e| if (!(try self.expr(e))) return false;
                for (a.values) |e| if (!(try self.expr(e))) return false;
                return true;
            },
            .while_loop => |w| {
                if (!(try self.expr(w.cond))) return false;
                return try self.block(&w.body);
            },
            // `start`/`stop`/`step` are operands of the loop and can apply
            // something; the predicate this replaces walked only the body.
            .num_for => |f| {
                if (!(try self.expr(f.start))) return false;
                if (!(try self.expr(f.stop))) return false;
                if (f.step) |s| if (!(try self.expr(s))) return false;
                return try self.block(&f.body);
            },
            .do_block => |d| return try self.block(&d.body),
            .if_stmt => |f| {
                // `if name = expr` binds before the truth test. Nothing
                // downstream of this query models that binding, so it is a
                // refusal rather than a silently ignored operand.
                if (f.binding != null) return false;
                if (!(try self.expr(f.cond))) return false;
                if (!(try self.block(&f.then))) return false;
                for (f.elseifs) |ei| {
                    if (!(try self.expr(ei.cond))) return false;
                    if (!(try self.block(&ei.body))) return false;
                }
                if (f.else_body) |eb| return try self.block(&eb);
                return true;
            },
            .ret => |r| {
                for (r.vals) |e| if (!(try self.expr(e))) return false;
                return true;
            },
            .expr_stmt => |e| return try self.expr(e.expr),
            .call_stmt => |e| return try self.expr(e.expr),
            .brk, .cont => return true,
            else => return false,
        }
    }

    fn expr(self: *ApplicationWalk, e: *const ast.Expr) EffectQueryError!bool {
        switch (e.*) {
            .call => |c| {
                try self.out.append(self.alloc, e);
                if (!(try self.expr(c.func))) return false;
                for (c.args) |a| if (!(try self.expr(a))) return false;
                return true;
            },
            .method_call => |m| {
                try self.out.append(self.alloc, e);
                if (!(try self.expr(m.obj))) return false;
                for (m.args) |a| if (!(try self.expr(a))) return false;
                return true;
            },
            // A macro call APPLIES something and `types.inferCallShape` returns
            // null for it, so it never becomes an application candidate and the
            // graph half of this query cannot see it. Refuse.
            .macro_call => return false,
            .binop => |b| return try self.expr(b.lhs) and try self.expr(b.rhs),
            .unop => |u| return try self.expr(u.operand),
            .if_expr => |ie| {
                if (!(try self.expr(ie.cond))) return false;
                if (!(try self.expr(ie.then_expr))) return false;
                return try self.expr(ie.else_expr);
            },
            .index => |ix| return try self.expr(ix.obj) and try self.expr(ix.key),
            .field => |f| return try self.expr(f.obj),
            // A table literal is a value and every entry is an ordinary
            // expression that can itself apply something. Only the three
            // positional/named/indexed spellings are enumerated; `spread` and
            // `semantic` are refused with everything else.
            .table => |t| {
                for (t.fields) |field| {
                    const ok = switch (field) {
                        .positional => |value| try self.expr(value),
                        .named => |named| try self.expr(named.val),
                        .indexed => |indexed| (try self.expr(indexed.key)) and (try self.expr(indexed.val)),
                        else => false,
                    };
                    if (!ok) return false;
                }
                return true;
            },
            .name, .int_lit, .float_lit, .true_lit, .false_lit, .string_lit, .nil => return true,
            else => return false,
        }
    }
};

/// One lifted module, checked, with the effect fixpoint published.
const EffectFixture = struct {
    graph: semantic_graph.SemanticGraph,
    module: semantic_graph.id,

    fn init(alloc: std.mem.Allocator, source: []const u8, file: []const u8) !EffectFixture {
        const Lexer = @import("lexer.zig").Lexer;
        const Parser = @import("parser.zig").Parser;
        const lexer = try alloc.create(Lexer);
        lexer.* = Lexer.init(source, file);
        var parser = Parser.init(lexer, alloc);
        parser.idol_mode = true;
        const module = try alloc.create(@import("ast.zig").Module);
        module.* = try parser.parse_module();
        const checked = try alloc.create(@import("sema.zig").Sema);
        checked.* = @import("sema.zig").Sema.init(alloc);
        checked.idol_mode = true;
        try checked.check_module(module);
        var graph = semantic_graph.SemanticGraph.init(alloc);
        const module_id = try graph.liftModuleWithCheckedCalls(module, checked, file);
        return .{ .graph = graph, .module = module_id };
    }

    fn relationOf(self: *EffectFixture, name: []const u8) !semantic_graph.id {
        return self.graph.resolveInHome(self.module, name, .func) orelse error.TestExpectedEqual;
    }

    /// Is every application in `name`'s body provably effect-free?
    fn foldable(self: *EffectFixture, alloc: std.mem.Allocator, name: []const u8) !bool {
        const callable_id = try self.relationOf(name);
        const declaration = relationDeclaration(&self.graph, callable_id) orelse return error.TestExpectedEqual;
        const sites = try effectFreeApplications(&self.graph, alloc, callable_id, &declaration.func.body) orelse
            return false;
        alloc.free(sites);
        return true;
    }
};

// THE TWO PROBES THAT KILLED SIMPLER DESIGNS, kept as tests so they cannot be
// un-killed. Both are shapes where a rule consulting only what the graph
// RESOLVED reads an observable body as pure.
test "graph_query: print is unresolved and must never read as effect-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `print("hi")` publishes NO application: it is a `.call` candidate with no
    // checked target, so it sits in the unresolved column with no binding edge.
    // A rule that walked only `home_apps` would call this body EMPTY.
    var noisy = try EffectFixture.init(alloc,
        \\shout: i64 = ()
        \\    print("hi")
        \\    1
        \\entry: i64 = ()
        \\    shout()
    , "print.id");
    defer noisy.graph.deinit();
    try std.testing.expect(!try noisy.foldable(alloc, "entry"));

    // …and the same module with the egress removed IS effect-free, so the test
    // above is failing for the reason it names and not because nothing folds.
    var quiet = try EffectFixture.init(alloc,
        \\shout: i64 = ()
        \\    1
        \\entry: i64 = ()
        \\    shout()
    , "quiet.id");
    defer quiet.graph.deinit();
    try std.testing.expect(try quiet.foldable(alloc, "entry"));
}

test "graph_query: an @ffi target is invisible to the graph and must not read as effect-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // An `@ffi` declaration lifts as an ORDINARY `func` node with an ORDINARY
    // body, and nothing in the graph records that applying it runs foreign
    // code. The fact comes from the declaration's attributes, which is why the
    // effect pass takes the AST module it was lifted from.
    var foreign = try EffectFixture.init(alloc,
        \\@ffi("llabs")
        \\absval: i64 = (n: i64)
        \\    0
        \\entry: i64 = ()
        \\    absval(3)
    , "ffi.id");
    defer foreign.graph.deinit();
    try std.testing.expect(!try foreign.foldable(alloc, "entry"));

    // Byte-identical without the attribute: the refusal above is the attribute
    // doing the work, not the shape of the body.
    var native = try EffectFixture.init(alloc,
        \\absval: i64 = (n: i64)
        \\    0
        \\entry: i64 = ()
        \\    absval(3)
    , "native.id");
    defer native.graph.deinit();
    try std.testing.expect(try native.foldable(alloc, "entry"));
}

test "graph_query: reaching the world through a callee is not effect-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The world face is two levels down. Badness has to propagate FORWARD along
    // call edges for this to refuse.
    var world = try EffectFixture.init(alloc,
        \\reader: i64 = ()
        \\    os.env("HOME")
        \\    1
        \\middle: i64 = ()
        \\    reader()
        \\entry: i64 = ()
        \\    middle()
    , "world.id");
    defer world.graph.deinit();
    try std.testing.expect(!try world.foldable(alloc, "entry"));
    try std.testing.expect(!try world.foldable(alloc, "middle"));
}

test "graph_query: a recursive relation with no blocking evidence is effect-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The forward-on-goodness fixpoint could never promote a CYCLE, so mutual
    // recursion left every caller `.unknown` — 47 of `native.id`'s 92 relations
    // with nothing blocked at all. Badness propagation closes it.
    var cyclic = try EffectFixture.init(alloc,
        \\ping: i64 = (n: i64)
        \\    if n <= 0
        \\        return 0
        \\    pong(n - 1)
        \\pong: i64 = (n: i64)
        \\    ping(n - 1)
        \\entry: i64 = ()
        \\    ping(4)
    , "cycle.id");
    defer cyclic.graph.deinit();
    try std.testing.expect(try cyclic.foldable(alloc, "entry"));

    // The same cycle with one observable member is NOT effect-free, which is
    // the half that makes the promotion above a fact rather than optimism.
    var tainted = try EffectFixture.init(alloc,
        \\ping: i64 = (n: i64)
        \\    if n <= 0
        \\        return 0
        \\    pong(n - 1)
        \\pong: i64 = (n: i64)
        \\    print("x")
        \\    ping(n - 1)
        \\entry: i64 = ()
        \\    ping(4)
    , "tainted.id");
    defer tainted.graph.deinit();
    try std.testing.expect(!try tainted.foldable(alloc, "entry"));
}

test "graph_query: the string reader faces are admitted and only those" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `s:len()` and `s:byte(i)` lower through bootstrap rules and are forever
    // unresolved. Blocking on them cost `native.id` 60 of 92 relations.
    var reader = try EffectFixture.init(alloc,
        \\size: i64 = (s: str)
        \\    s:len() + s:byte(1)
        \\entry: i64 = ()
        \\    size("abc")
    , "face.id");
    defer reader.graph.deinit();
    try std.testing.expect(try reader.foldable(alloc, "entry"));

    // A face in the same bootstrap set that REACHES THE WORLD is not admitted.
    var egress = try EffectFixture.init(alloc,
        \\emit: i64 = (s: str)
        \\    stdout:write(s)
        \\    1
        \\entry: i64 = ()
        \\    emit("abc")
    , "egress.id");
    defer egress.graph.deinit();
    try std.testing.expect(!try egress.foldable(alloc, "entry"));
}
