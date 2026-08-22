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
const collection_relation = @import("collection_relation.zig");

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
/// hangs off a module rather than off a relation — which is to say, when it
/// sits at MODULE SCOPE.
///
/// Public because `obseq.entryProjection` asks the same question for a
/// different reason (which relations does the entry reach), and two walks of
/// one scope chain is how two consumers come to disagree about where an
/// application lives.
pub fn enclosingCallable(
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

/// THE SECOND UNRESOLVED SHAPE THAT IS STILL PROVABLY UNOBSERVABLE, AND IT IS
/// ADMITTED ON A DIFFERENT FACT THAN THE FIRST.
///
/// `applicationIsUnobservableStringFace` admits `s:len()` because the CALLEE is
/// known to reach nothing. A collection relation has no callee at all: its body
/// relation is written at the application site and FUSED into the iteration
/// (`collection_relation.Shape`), so there is nothing for the graph to resolve
/// and the site sits in the unresolved column forever — exactly the shape the
/// door was refusing. What makes it admissible is that all five facts the
/// enclosing fold needs are decided HERE, from the shape, with no fixpoint:
///
///     effect none        the realization emits no call and touches no world
///                        (`gate/collection.sh` row 5 reads bl=0, blr/br=0,
///                        undefined=0 off the artifact)
///     trap none          the fused body applies nothing — enforced by
///                        `ApplicationWalk` below, which refuses a body that
///                        adds a single application site
///     termination        the source's extent bounds the iteration, and the
///                        caller's step budget bounds it again
///     world closed       no operand escapes; the body relation is never built
///                        as a value, so nothing can be handed out
///     result known       only when the compile-time evaluator can actually
///                        answer it, which is the CALLER's question, not this
///                        one — a site admitted here and unanswerable there
///                        simply fails the fold closed
///
/// A CLOSED LIST, NOT A PROPERTY — the same ruling `unobservableStringFace`
/// records. `collection_relation.rostered` is the list, and a question added to
/// it without an evaluator face refuses at the fold rather than answering
/// wrongly here.
///
/// IT NEVER TAKES THE NAME. A resolved application belongs to the relation the
/// program declared and goes through the ordinary path above; a module that
/// declares the spelling at all is refused outright, because then the
/// interpreter's by-name lookup and this admission could disagree about which
/// meaning the site has.
fn collectionRelationSite(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) ?*const ast.Expr {
    if (!graph.isApplicationCandidate(occurrence)) return null;
    if (graph.application(occurrence) != null) return null;
    const node = graph.get(occurrence) orelse return null;
    const raw = node.ast_ref orelse return null;
    const expr: *const ast.Expr = @ptrCast(@alignCast(raw));
    _ = collection_relation.shapeOf(expr) orelse return null;
    for (graph.nodes.items) |declaration| {
        if (declaration.kind != .func) continue;
        const name = declaration.name orelse continue;
        if (std.mem.eql(u8, name, expr.method_call.method)) return null;
    }
    return expr;
}

/// Every application in `body`, proved effect-free — or null, meaning REFUSED.
///
/// Caller owns the returned slice. Null is the only failure signal: this query
/// never reports a partial proof, because a partial proof of purity is a wrong
/// answer with extra steps.
/// Whether the projection CHAIN this step belongs to ends in a result the
/// graph has already answered.
///
/// `xs[2][1]` publishes two projections. Only the LEAF carries an exact
/// content; the intermediate's result is a sub-aggregate and never will. Asking
/// each step in isolation therefore admits the leaf and refuses the step that
/// feeds it, which is the same chain answered twice with two verdicts. This
/// walks consumer-ward to the leaf and lets the chain answer once.
///
/// The walk is bounded by the aggregate count, so a malformed graph terminates
/// with `false` rather than looping.
fn projectionChainIsAnswered(
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) bool {
    var current = occurrence;
    var guard: usize = 0;
    while (guard <= graph.aggregateCount()) : (guard += 1) {
        const results = graph.applicationResults(current) orelse return false;
        if (results.len != 1) return false;
        if (graph.exactI64(results[0]) != null) return true;
        const consumer = projectionConsumingSubject(graph, results[0]) orelse return false;
        current = consumer;
    }
    return false;
}

/// The single projection that takes `value` as its subject, or null when there
/// is none or more than one. Ambiguity answers null; it never picks one.
fn projectionConsumingSubject(
    graph: *const semantic_graph.SemanticGraph,
    value: semantic_graph.id,
) ?semantic_graph.id {
    var found: ?semantic_graph.id = null;
    for (graph.nodes.items, 0..) |_, coordinate| {
        const candidate: semantic_graph.id = std.math.cast(semantic_graph.id, coordinate) orelse return null;
        if (graph.aggregateAccess(candidate) == null) continue;
        const subject = graph.applicationSubject(candidate) orelse continue;
        if (subject != value) continue;
        if (found != null) return null;
        found = candidate;
    }
    return found;
}

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

        // A COMPUTED PROJECTION IS NOT A CALL. `law.application.one` says it
        // outright — "computed aggregate access table[key] is projection and
        // never application" — and the two halves of this function agree with
        // that in opposite directions: the graph→AST half sees a published
        // ApplicationFact, while `ApplicationWalk` below counts only `()` and
        // `:` faces as application sites. Leaving the projection in `sites`
        // made the counts disagree by exactly one and refused the fold for
        // every body containing a `[]` read. Measured: `xs = { 3, 5, 8 } ; n =
        // xs[1] ; if n > 2 : 7` folded whole at two instructions until the
        // projection began publishing, then lowered at ten.
        //
        // Skipping is not a purity assumption. A projection binds no callee, so
        // it adds nothing to the effect-free CLOSURE this function computes;
        // its own effect facts are checked where the projection is realized.
        //
        // BOUNDED TO THE PROJECTION THE GRAPH HAS ALREADY ANSWERED, and the
        // bound is not cosmetic. `comptime`'s evaluator runs the SOURCE AST, so
        // every relation this admits into the closure becomes foldable by
        // reading the initializer expression again. `dnir_lower`'s "graph
        // aggregate facts select one immutable nested layout" test measures
        // exactly that: it poisons a root's initializer to `.nil` with the graph
        // facts intact and requires identical realization. Admitting a
        // projection whose answer is NOT already published (`pairs[i][2]`, a
        // runtime index) made the whole caller fold through the AST and the
        // poisoned relowering diverge by one instruction. A projection carrying
        // an exact published result needs no evaluation to be answered, so
        // admitting it adds no AST dependence the graph does not already
        // license. GAP: `comptime.runFold` is an AST reader, and closing that
        // is what would let this bound be lifted.
        if (graph.aggregateAccess(occurrence) != null and projectionChainIsAnswered(graph, occurrence)) {
            continue;
        }

        const fact = graph.application(occurrence) orelse {
            // The ONE unresolved shape that is still provably unobservable, and
            // the consumer must admit exactly the sites the fixpoint declined
            // to block or the two disagree about what "effect-free" means.
            if (graph.applicationIsUnobservableStringFace(occurrence)) {
                // WORLD CONSUMER. `s:len()` and `s:byte(i)` are admitted by
                // ARITY AND SPELLING, which is the whole of what
                // `unobservableStringFace` can check while the receiver's
                // descriptor is not in the graph. `applicationWorld` is the
                // exact fact underneath that guess: an occurrence the world
                // table says is supplied by an INJECTED WORLD reaches outside
                // this module however it is spelled, and `os`, `io` and `c` are
                // every one of them observable. A `len` face this rule admits
                // and the world table claims is `.one` is a disagreement
                // between two producers, and the pure answer is the unsound one.
                switch (graph.applicationWorld(occurrence)) {
                    .one => {
                        sites.deinit(alloc);
                        return null;
                    },
                    .unknown, .none => {},
                }
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
            // A COLLECTION RELATION — see `collectionRelationSite`. Null callee
            // for the same reason the string face has one: there is no relation
            // to bind, and the consumer that runs the body implements the
            // question itself. The world check is the same one the string face
            // takes, for the same reason: two producers must not disagree, and
            // the pure answer is the unsound one.
            if (collectionRelationSite(graph, occurrence)) |fused| {
                switch (graph.applicationWorld(occurrence)) {
                    .one => {
                        sites.deinit(alloc);
                        return null;
                    },
                    .unknown, .none => {},
                }
                try sites.append(alloc, .{
                    .expr = fused,
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
        // A PUBLISHED application that DRAWS A WORLD is never effect-free,
        // whatever the effect fixpoint concluded. World supplies facts,
        // authority requires them, witness proves satisfaction — three
        // questions, and `effect == .none` answers none of the first.
        switch (graph.applicationWorld(occurrence)) {
            .one => {
                sites.deinit(alloc);
                return null;
            },
            .unknown, .none => {},
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
                // A COLLECTION RELATION'S BODY IS FUSED, NOT PASSED. The
                // operand is a `.func_expr`, which the arm below refuses with
                // every other unenumerated node — correctly, because a relation
                // handed over as a VALUE can be applied anywhere. Here it is
                // not handed over: `shapeOf` guarantees one statement-free
                // expression that this walk can read in full.
                //
                // AND THE BODY MUST APPLY NOTHING. An application inside the
                // fused body is not lifted as a candidate of any callable this
                // query can name, so the graph half could not line it up; the
                // count check would then be comparing two different sets. A
                // body that adds even one site is refused, which is also the
                // whole of the "effectful predicate" refusal.
                if (collection_relation.shapeOf(e)) |fused| {
                    const before = self.out.items.len;
                    if (!(try self.expr(fused.body))) return false;
                    return self.out.items.len == before;
                }
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
            .name, .int_lit, .float_lit, .true_lit, .false_lit, .quoted, .nil => return true,
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
