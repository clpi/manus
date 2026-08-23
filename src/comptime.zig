const std = @import("std");
const ast = @import("ast.zig");
const term = @import("term.zig");
const semantic_graph = @import("semantic_graph.zig");
const graph_query = @import("graph_query.zig");
const types = @import("types.zig");
const collection_relation = @import("collection_relation.zig");

pub const EvalError = error{
    OutOfMemory,
    UnsupportedExpression,
    UnsupportedOperator,
    DivisionByZero,
    StepLimitExceeded,
};

pub const CommandOutput = struct {
    ok: bool,
    stdout: []const u8,
    stderr: []const u8,
};

pub const SatisfiesHook = *const fn (ctx: ?*anyopaque, type_expr: *const ast.Expr, concept_name: []const u8) ?bool;

/// Exact graph application work admitted by the effect/authority query for one
/// native whole-body fold. Each site already carries the occurrence id its
/// graph producer published; `expr` is only the evaluator walk's provenance
/// key for selecting that carried work item.
///
/// Delete the expression key when the evaluator itself is scheduled from graph
/// value/application ids rather than from `ast.FuncBody`.
pub const ApplicationWork = struct {
    graph: *const semantic_graph.SemanticGraph,
    sites: []const graph_query.EffectFreeSite,
};

pub const Options = struct {
    step_limit: usize = 100_000,
    alloc: ?std.mem.Allocator = null,
    /// Optional cache allocator for comptime caching (separate from arena for permanent storage)
    comptime_cache_alloc: ?std.mem.Allocator = null,
    /// Optional hook for __satisfies(Type, "Concept") during @(expr) folding.
    satisfies_hook: ?SatisfiesHook = null,
    satisfies_ctx: ?*anyopaque = null,
    /// Optional hook for @comp.* metaprogramming combinators during callback
    /// evaluation. When the evaluator encounters a __comptime* call it doesn't
    /// handle internally, it delegates to this hook. This enables nested
    /// combinator calls inside callback bodies (G-059 fix).
    meta_hook: ?MetaHookFn = null,
    meta_ctx: ?*anyopaque = null,
    /// THE NATIVE WHOLE-BODY FOLD, and nothing else, turns this on. It is one
    /// switch rather than three because the three are not independently safe:
    /// admitting relation application without frames, or without the backend's
    /// integer laws, is a silent wrong answer, and each was MEASURED as one.
    ///
    /// It changes three things at once.
    ///
    /// 1. RELATION APPLICATION THROUGH THE SUBJECT-FIRST FACE. `"src":run()` is
    ///    `run(src)`; the bound relation is tried BEFORE the string faces, so a
    ///    module that declares `rev` reaches its own relation.
    ///
    /// 2. INTEGER `/`, `//` and `%` AS THE DIRECT BACKEND EVALUATES THEM.
    ///    Three divergences, each a two-line program, each a silent wrong
    ///    answer:
    ///      `if a / b == 3` at (7,2) — backend 1, interpreter 0, because
    ///          `evalNumeric` routed `.div` to the FLOAT path for two ints and
    ///          `3.5 == 3` is false;
    ///      `a // b` at (-7,2)      — backend -3, interpreter -4: AArch64
    ///          `sdiv` TRUNCATES toward zero, `@divFloor` floors;
    ///      `a % b`  at (-7,3)      — backend -1, interpreter 2: `sdiv`+`msub`
    ///          is the truncated remainder, `@mod` takes the divisor's sign.
    ///    Verified against emitted code over the full sign matrix: `//` is
    ///    3/-3/-3/3 and `%` is 1/-1/1/-1 at (7,2)(-7,2)(7,-2)(-7,-2).
    ///
    /// 3. A CALL FRAME. `locals` is one flat stack and `lookup`/`setLocal`
    ///    walked ALL of it, so a callee saw — and `setLocal` WROTE THROUGH TO —
    ///    the caller's bindings whenever the two used the same spelling. That
    ///    is dynamic scoping with cross-frame mutation. It never mattered while
    ///    the folder refused every body containing an application; it is fatal
    ///    the moment one is admitted, and `native.id`'s relations share `i`,
    ///    `n`, `k`, `q`, `d` and `b` freely. An application now opens a frame
    ///    that name resolution cannot see past.
    native_fold: bool = false,
    /// Exact applications admitted for this native whole-body fold. The graph
    /// pointer cannot recover identity: the carried site occurrence is the
    /// only input to semantic application queries.
    application_work: ?ApplicationWork = null,
};

/// Hook type for @comp.* combinator evaluation inside comptime callbacks.
/// Receives pre-evaluated Value args from the comptime evaluator.
/// Returns the computed Value (typically a .string) or null if not handled.
pub const MetaHookFn = *const fn (ctx: ?*anyopaque, name: []const u8, args: []const Value) ?Value;

/// Widest operand list any face is evaluated with, receiver included.
///
/// It was 8, with a comment saying "a face taking more than seven arguments
/// does not exist". `native.id`'s `o:rec(a,b,c,d,e,f,g,h,n)` takes NINE plus
/// the subject, and the fold declined on it with no diagnostic — an arity
/// threshold standing in for a fact, in the interpreter this time.
const max_face_operands: usize = 16;

/// Ceiling on `eval`'s NATIVE recursion, which `Options.step_limit` does not
/// bound — see the guard in `eval` for the crash this prevents.
///
/// CALIBRATED, NOT GUESSED, and it is not a source recursion depth: one
/// source-level call costs several `eval` frames plus the heavier
/// `applyFuncValue` / `evalBlock` / `evalIf` frames between them. Measured on
/// this machine with a self-recursive `deep(n)`: the compiler folded at source
/// depth 500 and SIGSEGV'd at 600. A bound of 1200 eval frames still faulted;
/// 800 refused cleanly at every source depth probed up to 100,000. 600 is that
/// safe value with margin left for shapes whose frames are heavier than this
/// one's, because the failure mode on the wrong side of this number is a
/// compiler crash and on the right side it is only a fold that did not happen.
///
/// The cost is real and is stated rather than hidden: source recursion folded
/// to depth ~500 before and folds to ~200 now. A missed fold is a slower
/// program; a fault is no program at all.
const max_eval_depth: usize = 600;

pub const Value = union(enum) {
    pub const TableEntry = struct {
        key: ?Value = null,
        name: ?[]const u8 = null,
        val: Value,
    };

    pub const CapturedBinding = struct {
        name: []const u8,
        value: Value,
    };

    pub const Func = struct {
        body: *const ast.FuncBody,
        captures: []const CapturedBinding = &.{},
    };

    unavailable,
    nil,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    table: []const TableEntry,
    func: Func,

    fn truthy(self: Value) bool {
        return switch (self) {
            .nil, .unavailable => false,
            .bool => |v| v,
            else => true,
        };
    }

    /// EQUALITY, OR AN ADMISSION THAT IT CANNOT BE DECIDED HERE.
    ///
    /// `null` means undecidable, and every caller must fail closed on it. The
    /// arm this replaces was `.table, .func => false`, which made `a == a`
    /// answer FALSE for a table — not a missed fold but a WRONG ANSWER, and
    /// one the rest of the compiler already disagreed with: the memory
    /// representation implements Lua reference identity, so the constant
    /// folder was contradicting a decision made on another path. Measured
    /// before this change, `--backend=direct`, `a = {1,2,3}`:
    ///
    ///     a == a   ->  false   (Lua: true)      WRONG
    ///     a != a   ->  true    (Lua: false)     WRONG
    ///     b = a ; a == b -> false (Lua: true)   WRONG
    ///     a == b, separately constructed -> false (Lua: false)   right
    ///
    /// Lua's rule is reference identity: two tables are equal exactly when
    /// they are the same table. `evalTable` allocates a fresh entry slice per
    /// constructor evaluation (`toOwnedSlice`), and binding or copying a table
    /// value copies the SLICE HEADER, never the entries — so `ptr` equality is
    /// exactly "same table", and a differing `ptr` is exactly "constructed
    /// separately". That is why the aliased row above is fixed by the same
    /// rule that fixes the self row.
    ///
    /// TWO EMPTY TABLES ARE THE HOLE, and they are refused rather than
    /// guessed. A zero-length slice carries no meaningful `ptr` — `{}` and
    /// `{}` may share one — so identity is unrecoverable there. Lua says
    /// `{} == {}` is false; this returns `null` and the fold declines, leaving
    /// the answer to a path that holds the reference. Answering `false` would
    /// be right by luck for two distinct empties and wrong for `a == a` with
    /// an empty `a`, which is the same defect this comment exists to describe.
    ///
    /// Functions are the same argument with a weaker handle: two closures
    /// built from one literal share a `body` pointer and differ only in their
    /// captures, so a capture-less function literal compared to itself is
    /// undecidable and is refused too.
    ///
    /// NOT TOUCHED, deliberately: `1 == 1.0` still answers false here. That is
    /// a separate divergence from Lua with a different blast radius, and
    /// widening this fix to cover it would hide it.
    fn eqlOrUnknown(self: Value, other: Value) ?bool {
        return switch (self) {
            .unavailable => other == .unavailable,
            .nil => other == .nil,
            .bool => |v| other == .bool and other.bool == v,
            .int => |v| other == .int and other.int == v,
            .float => |v| other == .float and other.float == v,
            .string => |v| other == .string and std.mem.eql(u8, other.string, v),
            .table => |v| blk: {
                if (other != .table) break :blk false;
                const w = other.table;
                if (v.len != w.len) break :blk false;
                if (v.len == 0) break :blk null;
                break :blk v.ptr == w.ptr;
            },
            .func => |v| blk: {
                if (other != .func) break :blk false;
                const w = other.func;
                if (v.body != w.body) break :blk false;
                if (v.captures.len != w.captures.len) break :blk false;
                if (v.captures.len == 0) break :blk null;
                break :blk v.captures.ptr == w.captures.ptr;
            },
        };
    }

    /// The definite-answer form, for the three KEY-LOOKUP callers (membership,
    /// pattern literal, table index). Undecidable reads as "does not match",
    /// which is what those sites already did for every aggregate and is
    /// fail-closed: a lookup that finds nothing falls through, it does not
    /// answer wrongly.
    ///
    /// `==` and `!=` must NOT use this — they have no fall-through, so for
    /// them `null` has to become a refusal to fold.
    fn eql(self: Value, other: Value) bool {
        return self.eqlOrUnknown(other) orelse false;
    }
};

pub const Bindings = struct {
    scopes: []const std.StringHashMapUnmanaged(Value) = &.{},

    pub fn get(self: Bindings, name: []const u8) ?Value {
        var i = self.scopes.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes[i].get(name)) |value| return value;
        }
        return null;
    }
};

pub const Evaluator = struct {
    const WorkItem = struct {
        expr: *const ast.Expr,
        application: ?semantic_graph.id,
    };

    const LocalBinding = struct {
        name: []const u8,
        value: Value,
        /// THE DECLARED WIDTH OF THE PLACE, or null when the binding is
        /// full-width. A write to this binding stores the EXACT projection of
        /// this descriptor — the same value `dnir_lower` hands the store and
        /// `native_backend` realizes as `sxtw`/`ubfx`, through the same
        /// function, so the folded program and the emitted program cannot
        /// answer differently.
        width: ?types.ResolvedType = null,
    };

    const BlockResult = union(enum) {
        none,
        value: Value,
    };

    bindings: Bindings = .{},
    options: Options = .{},
    locals: std.ArrayListUnmanaged(LocalBinding) = .empty,
    /// Index in `locals` below which the current frame cannot see.
    frame_base: usize = 0,
    steps: usize = 0,
    /// Native-stack depth of `eval`, which recurses. See `max_eval_depth`.
    depth: usize = 0,

    fn step(self: *Evaluator) EvalError!void {
        self.steps += 1;
        if (self.steps > self.options.step_limit) return error.StepLimitExceeded;
    }

    /// Floor of the current call frame. Name resolution must not see past it
    /// once `options.native_fold` is on; see the option's doc for the measured
    /// reason. Zero everywhere else, which is exactly today's behaviour.
    fn frameFloor(self: *const Evaluator) usize {
        return if (self.options.native_fold) self.frame_base else 0;
    }

    fn lookup(self: *const Evaluator, name: []const u8) ?Value {
        var i = self.locals.items.len;
        const floor = self.frameFloor();
        while (i > floor) {
            i -= 1;
            const binding = self.locals.items[i];
            if (std.mem.eql(u8, binding.name, name)) return binding.value;
        }
        return self.bindings.get(name);
    }

    fn pushLocal(self: *Evaluator, name: []const u8, value: Value) EvalError!usize {
        return self.pushPlace(name, value, null);
    }

    /// THE ONE WRITE PRIMITIVE. Every binding is created here and every value
    /// that enters one passes through `project`, so there is no path by which a
    /// declared width can be established and then not applied.
    fn pushPlace(
        self: *Evaluator,
        name: []const u8,
        value: Value,
        width: ?types.ResolvedType,
    ) EvalError!usize {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        const mark = self.locals.items.len;
        self.locals.append(alloc, .{
            .name = name,
            .value = project(value, width),
            .width = width,
        }) catch return error.UnsupportedExpression;
        return mark;
    }

    /// The exact projection of `value` onto `width`, or `value` unchanged when
    /// the place is full-width or does not hold an integer.
    ///
    /// A FLOAT IS NOT PROJECTED AND MUST NOT BE. `t: i32 = 1.5` is a
    /// conversion question this evaluator does not answer, and silently
    /// truncating it here would invent a semantics no other consumer shares —
    /// the binding keeps its value and any disagreement stays visible.
    fn project(value: Value, width: ?types.ResolvedType) Value {
        const w = width orelse return value;
        if (value != .int) return value;
        return .{ .int = types.narrowFitConst(value.int, w) };
    }

    fn popLocals(self: *Evaluator, mark: usize) void {
        self.locals.shrinkRetainingCapacity(mark);
    }

    fn setLocal(self: *Evaluator, name: []const u8, value: Value) EvalError!void {
        var i = self.locals.items.len;
        const floor = self.frameFloor();
        while (i > floor) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                // AT EVERY WRITE, not only at the declaration. A loop-carried
                // update is a write like any other, and it was the one this
                // evaluator got wrong: the declaration bound 0 and every
                // iteration after it stored a value the place cannot hold.
                self.locals.items[i].value = project(value, self.locals.items[i].width);
                return;
            }
        }
        // Duo mode: create new local for bare assignment
        _ = try self.pushLocal(name, value);
    }

    fn workItem(self: *const Evaluator, expr: *const ast.Expr) EvalError!WorkItem {
        const work = self.options.application_work orelse return .{
            .expr = expr,
            .application = null,
        };
        var application: ?semantic_graph.id = null;
        for (work.sites) |site| {
            if (site.expr != expr) continue;
            if (application != null and application.? != site.occurrence)
                return error.UnsupportedExpression;
            application = site.occurrence;
        }
        return .{ .expr = expr, .application = application };
    }

    pub fn eval(self: *Evaluator, expr: *const ast.Expr) EvalError!Value {
        return self.evalWork(try self.workItem(expr));
    }

    fn evalWork(self: *Evaluator, work_item: WorkItem) EvalError!Value {
        const expr = work_item.expr;
        try self.step();
        // THE STEP BUDGET DOES NOT BOUND THE NATIVE STACK. `steps` counts work
        // and `eval` recurses, so a deeply recursive source program exhausted
        // the compiler's own stack long before 100,000 steps were spent: the
        // COMPILER CRASHED at source recursion depth ~600 while depth 500
        // folded and answered. A crash is not a refusal — it produces no
        // diagnostic, no artifact, and no exit code a caller can act on.
        //
        // Reuses `StepLimitExceeded` rather than adding an error variant:
        // every caller already treats it as "fail closed, leave the body
        // lowered", which is exactly the wanted behaviour, and a new variant
        // would widen this file's error set into files this lane does not own.
        //
        // THIS DOES NOT FIX EVERY DEEP-NESTING FAULT, and it is not meant to
        // look as though it does. Two more unbounded native recursions were
        // measured over the SAME probe family and both are in routed files:
        // `src/sema.zig` faults at ~500 nested binary expressions and
        // `src/parser.zig` at ~1000, before the evaluator is ever reached.
        if (self.depth >= max_eval_depth) return error.StepLimitExceeded;
        self.depth += 1;
        defer self.depth -= 1;
        return switch (expr.*) {
            .nil => .nil,
            .true_lit => .{ .bool = true },
            .false_lit => .{ .bool = false },
            .int_lit => |lit| .{ .int = lit.val },
            .float_lit => |lit| .{ .float = lit.val },
            .quoted => |lit| .{ .string = lit.val },
            .name => |name| blk: {
                const value = self.lookup(name.ident) orelse return error.UnsupportedExpression;
                if (value == .unavailable) return error.UnsupportedExpression;
                break :blk value;
            },
            .call => |call| blk: {
                if (call.func.* == .name and std.mem.eql(u8, call.func.name.ident, "__constexpr") and call.args.len == 1) {
                    break :blk try self.eval(call.args[0]);
                }
                break :blk try self.evalCall(call.func, call.args);
            },
            .index => |index| blk: {
                if (self.options.native_fold) {
                    if (self.options.application_work) |work| {
                        if (work_item.application) |occurrence| {
                            if (work.graph.aggregateAccess(occurrence)) |access| {
                                if (access.application != occurrence)
                                    break :blk error.UnsupportedExpression;
                                const graph = work.graph;
                                const subject = graph.applicationSubject(access.application) orelse
                                    break :blk error.UnsupportedExpression;
                                if (!graph.aggregateIsSoleImmutableBinding(subject))
                                    break :blk error.UnsupportedExpression;
                                const members = graph.aggregateMembers(subject) orelse
                                    break :blk error.UnsupportedExpression;
                                const key = try self.eval(index.key);
                                if (key != .int or key.int < 1 or
                                    key.int > @as(i64, @intCast(members.len)))
                                {
                                    break :blk error.UnsupportedExpression;
                                }
                                const member = members[@intCast(key.int - 1)];
                                const node = graph.get(member) orelse
                                    break :blk error.UnsupportedExpression;
                                const descriptor = node.descriptor orelse
                                    break :blk error.UnsupportedExpression;
                                if (descriptor != .i64) break :blk error.UnsupportedExpression;
                                const content = graph.exactI64(member) orelse
                                    break :blk error.UnsupportedExpression;
                                break :blk .{ .int = content };
                            }
                        }
                    }
                }
                const obj = try self.eval(index.obj);
                const key = try self.eval(index.key);
                const value = try tableLookup(obj, key);
                // A TABLE READ THAT ANSWERS `nil` IS A READ THE RUNNING PROGRAM
                // WOULD HAVE TRAPPED ON, AND `nil` IS NOT A VALUE THIS BACKEND
                // HAS. `tableLookup` implements the Lua rule — an absent key is
                // `nil` — which is right for the metaprogramming faces and
                // WRONG whenever this evaluator is standing in for native
                // lowering, because `dnir_lower.guardedTableIndex` emits a
                // GUARD there and the guard aborts.
                //
                // MEASURED, and it is a wrong answer rather than a missed fold:
                //
                //     ys: [2]i64 = {5, 6}
                //     n = 0 · i = 1 · while i <= 3 : if ys(i) == 6 : n += 1 · n
                //
                //     compiled with the fold        2 instructions, answers 1
                //     the same program, unfolded    aborts on ys(3)
                //
                // So the fold was not making the program faster; it was making
                // a DIFFERENT program, one whose out-of-range read never
                // happened. Refusing leaves the guard in place, which is slower
                // and right.
                //
                // Confined to `native_fold`: the `@comp.*` faces use tables as
                // maps, where an absent key genuinely IS `nil` and answering
                // anything else would break them.
                if (self.options.native_fold and obj == .table and value == .nil) {
                    break :blk error.UnsupportedExpression;
                }
                break :blk value;
            },
            .field => |field| blk: {
                const obj = try self.eval(field.obj);
                break :blk try tableFieldLookup(obj, field.field);
            },
            .method_call => |mc| try self.evalMethodCall(
                mc.obj,
                mc.method,
                mc.args,
                collection_relation.shapeOf(expr),
            ),
            .unop => |unop| try self.evalUnop(unop.op, unop.operand),
            .binop => |binop| try self.evalBinop(binop.op, binop.lhs, binop.rhs),
            .table => |table| try self.evalTable(table.fields),
            .func_expr => |func| try self.makeFunc(func),
            .match_expr => |match_expr| try self.evalMatch(match_expr),
            .sequence => |seq| blk: {
                // Evaluate all expressions, return the first (multi-value semantics)
                if (seq.exprs.len == 0) break :blk .nil;
                break :blk try self.eval(seq.exprs[0]);
            },
            else => error.UnsupportedExpression,
        };
    }

    fn makeFunc(self: *Evaluator, func: *const ast.FuncBody) EvalError!Value {
        const captures = try self.snapshotCaptures();
        return .{ .func = .{ .body = func, .captures = captures } };
    }

    fn snapshotCaptures(self: *Evaluator) EvalError![]const Value.CapturedBinding {
        const alloc = self.options.alloc orelse return &.{};
        var count = self.locals.items.len;
        for (self.bindings.scopes) |*scope| count += scope.count();
        if (count == 0) return &.{};

        const captures = alloc.alloc(Value.CapturedBinding, count) catch return error.UnsupportedExpression;
        var out_i: usize = 0;
        for (self.bindings.scopes) |*scope| {
            var it = scope.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == .unavailable) continue;
                captures[out_i] = .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* };
                out_i += 1;
            }
        }
        for (self.locals.items) |local| {
            if (local.value == .unavailable) continue;
            captures[out_i] = .{ .name = local.name, .value = local.value };
            out_i += 1;
        }
        return captures[0..out_i];
    }

    fn evalCall(self: *Evaluator, func_expr: *const ast.Expr, args: []const *ast.Expr) EvalError!Value {
        // Handle math.* stdlib at compile time
        if (func_expr.* == .field) {
            const f = func_expr.field;
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                return self.evalMathBuiltin(f.field, args);
            }
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string")) {
                return self.evalStringBuiltin(f.field, args);
            }
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "table")) {
                return self.evalTableBuiltin(f.field, args);
            }
        }
        // Handle global builtins: type(), tostring(), tonumber()
        if (func_expr.* == .name) {
            const name = func_expr.name.ident;
            if (std.mem.eql(u8, name, "__constexpr") and args.len == 1) {
                return try self.eval(args[0]);
            }
            if (std.mem.eql(u8, name, "type") and args.len == 1) {
                const val = try self.eval(args[0]);
                return .{ .string = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "boolean",
                    .int, .float => "number",
                    .string => "string",
                    .table => "table",
                    .func => "function",
                } };
            }
            if (std.mem.eql(u8, name, "tonumber") and args.len == 1) {
                const val = try self.eval(args[0]);
                return switch (val) {
                    .int => val,
                    .float => val,
                    else => error.UnsupportedExpression,
                };
            }
            if (std.mem.eql(u8, name, "tostring") and args.len == 1) {
                const val = try self.eval(args[0]);
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                return switch (val) {
                    .string => val,
                    .int => blk: {
                        var buf: [20]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{val.int}) catch "??";
                        const owned = alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk .{ .string = owned };
                    },
                    .float => blk: {
                        var buf: [30]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{val.float}) catch "??";
                        const owned = alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk .{ .string = owned };
                    },
                    .bool => .{ .string = if (val.bool) "true" else "false" },
                    .nil => .{ .string = "nil" },
                    .func => .{ .string = "<function>" },
                    .table => .{ .string = "<table>" },
                    .unavailable => .{ .string = "<unavailable>" },
                };
            }
            // __has_field / __has_method — compile-time structural queries
            // At the comptime level these return bool based on table structure
            if (std.mem.eql(u8, name, "__has_field") and args.len == 2) {
                const tbl = try self.eval(args[0]);
                const field_name = try self.eval(args[1]);
                if (tbl == .table and field_name == .string) {
                    for (tbl.table) |entry| {
                        if (entry.name) |ename| {
                            if (std.mem.eql(u8, ename, field_name.string)) return .{ .bool = true };
                        }
                    }
                    return .{ .bool = false };
                }
                return error.UnsupportedExpression;
            }
            if (std.mem.eql(u8, name, "__type_name") and args.len == 1) {
                const val = try self.eval(args[0]);
                return .{ .string = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "i64",
                    .float => "f64",
                    .string => "str",
                    .table => "table",
                    .func => "function",
                } };
            }
            if (std.mem.eql(u8, name, "__type_id") and args.len == 1) {
                const val = try self.eval(args[0]);
                const type_str: []const u8 = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "int64_t",
                    .float => "double",
                    .string => "const char*",
                    .table => "lua_Value",
                    .func => "lua_Value",
                };
                // FNV-1a hash for stable type ID
                var hash: u64 = 14695981039346656037;
                for (type_str) |byte| {
                    hash ^= @as(u64, byte);
                    hash *%= 1099511628211;
                }
                return .{ .int = @bitCast(hash) };
            }
            if (std.mem.eql(u8, name, "__is_type") and args.len == 2) {
                const val = try self.eval(args[0]);
                const expected = try self.eval(args[1]);
                if (expected != .string) return error.UnsupportedExpression;
                const actual: []const u8 = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "i64",
                    .float => "f64",
                    .string => "str",
                    .table => "table",
                    .func => "function",
                };
                return .{ .bool = std.mem.eql(u8, actual, expected.string) };
            }
            // __comptimeprint — compile-time debug printing (returns nil)
            if (std.mem.eql(u8, name, "__comptimeprint") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locHint(args[0].loc(), "{s}", .{val.string});
                }
                return .nil;
            }
            // __comptimewarn — compile-time warning (returns nil)
            if (std.mem.eql(u8, name, "__comptimewarn") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locWarn(args[0].loc(), "{s}", .{val.string});
                }
                return .nil;
            }
            // __comptimeerror — abort with message
            if (std.mem.eql(u8, name, "__comptimeerror") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locErr(args[0].loc(), "{s}", .{val.string});
                }
                return error.UnsupportedExpression;
            }
            // __satisfies(TypeOrValue, "Concept") — compile-time concept membership
            if (std.mem.eql(u8, name, "__satisfies") and args.len == 2) {
                const concept_val = try self.eval(args[1]);
                if (concept_val != .string) return error.UnsupportedExpression;
                if (self.options.satisfies_hook) |hook| {
                    if (hook(self.options.satisfies_ctx, args[0], concept_val.string)) |known| {
                        return .{ .bool = known };
                    }
                }
                return error.UnsupportedExpression;
            }
            // __comptimefor — fold simple numeric templates at comptime
            if (std.mem.eql(u8, name, "__comptimefor") and args.len == 3) {
                const start_v = try self.eval(args[0]);
                const stop_v = try self.eval(args[1]);
                if (start_v != .int or stop_v != .int) return error.UnsupportedExpression;
                if (args[2].* != .quoted) return error.UnsupportedExpression;
                const tmpl = args[2].quoted.val;
                if (std.mem.eql(u8, tmpl, "%i")) {
                    var sum: i64 = 0;
                    var i = start_v.int;
                    while (i < stop_v.int) : (i += 1) sum += i;
                    return .{ .int = sum };
                }
                if (std.mem.eql(u8, tmpl, "1")) {
                    return .{ .int = @max(stop_v.int - start_v.int, 0) };
                }
                return error.UnsupportedExpression;
            }
            // G-059: Route __comptime* / __meta* metaprogramming combinators to the
            // codegen-provided meta_hook. This enables nested combinator calls
            // inside callback bodies (e.g. @comp.match callback calling @comp.interpolate).
            // Args are pre-evaluated so the hook can use them directly (with
            // callback-local variables like m.pattern already resolved).
            if (std.mem.startsWith(u8, name, "__comptime") or std.mem.startsWith(u8, name, "__meta") or std.mem.startsWith(u8, name, "__derive")) {
                if (self.options.meta_hook) |hook| {
                    // Evaluate all args to Values first (resolving callback locals)
                    const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                    const evaluated = alloc.alloc(Value, args.len) catch return error.UnsupportedExpression;
                    defer alloc.free(evaluated);
                    var ok = true;
                    for (args, 0..) |arg, i| {
                        // G-060: derive macro names are identifiers naming @comp.define.derive
                        // macros — never comptime bindings. Coerce before eval so nested
                        // @comp.match callbacks can call @comp.derive.power(..., MyDerive).
                        const is_derive_macro_arg = std.mem.startsWith(u8, name, "__derive") and arg.* == .name and blk: {
                            if (std.mem.eql(u8, name, "__derivepower") and args.len == 2 and i == 1) break :blk true;
                            if (std.mem.eql(u8, name, "__derivechoose") and args.len == 3 and i == 2) break :blk true;
                            break :blk false;
                        };
                        if (is_derive_macro_arg) {
                            const s = alloc.dupe(u8, arg.name.ident) catch {
                                ok = false;
                                break;
                            };
                            evaluated[i] = .{ .string = s };
                            continue;
                        }
                        const ev = self.eval(arg) catch {
                            if (std.mem.startsWith(u8, name, "__derive") and arg.* == .name) {
                                const s = alloc.dupe(u8, arg.name.ident) catch {
                                    ok = false;
                                    break;
                                };
                                evaluated[i] = .{ .string = s };
                                continue;
                            }
                            ok = false;
                            break;
                        };
                        evaluated[i] = ev;
                    }
                    if (ok) {
                        if (hook(self.options.meta_ctx, name, evaluated)) |result| {
                            return result;
                        }
                    }
                }
            }
        }
        const callee = try self.eval(func_expr);
        if (callee != .func) return error.UnsupportedExpression;
        return try self.applyFuncValue(callee, null, args);
    }

    /// `s:len()`, `s:byte(2)`, `s:sub(2, 3)` — the METHOD face of the standard
    /// library, which is the only face .id programs are written in.
    ///
    /// WHY THIS WAS MISSING AND WHAT IT COST. `evalStringBuiltin` below already
    /// folds `len`/`byte`/`sub`/`upper`/`lower`/`rev` with the same 1-based
    /// semantics the backend emits, and has for a long time — but `eval` had no
    /// `.method_call` arm at all, so the only route into it was the dotted face
    /// `string.len(s)`. Nothing in .id is spelled that way. Measured: a body
    /// whose whole answer is `"hello":len()` emits a 14-instruction runtime byte
    /// scan, and `"hello":byte(2)` emits 9, where the floor for a constant
    /// answer is 2. The folder was never wrong; it was never reachable.
    ///
    /// A method call is the dotted call with the receiver moved in front of the
    /// dot, so it is the same argument vector with the receiver prepended. No
    /// AST is synthesized — only the pointer vector is rebuilt — so there is one
    /// implementation of each face and the two spellings cannot drift apart.
    fn evalMethodCall(
        self: *Evaluator,
        obj: *ast.Expr,
        method: []const u8,
        args: []const *ast.Expr,
        collection: ?collection_relation.Shape,
    ) EvalError!Value {

        // Dispatch on the RECEIVER'S VALUE, not on its syntax: `s:len()` folds
        // when `s` is a literal and equally when it is a comptime binding that
        // holds a string. A receiver that is not a compile-time value at all
        // fails here, which is the decline the caller expects.
        //
        // STRINGS ONLY, AND THAT IS NOT AN OVERSIGHT. `evalTableBuiltin` is
        // deliberately not reachable from here. Its `insert`/`remove`/`sort`
        // faces are spelled functionally — they RETURN a new table — while the
        // language's `t:insert(v)` MUTATES the receiver and is written as a
        // statement whose value is discarded. Routing the method face there
        // would evaluate the call, build the updated table, throw it away, and
        // report success: the fold would swallow the mutation and the program
        // would keep the old contents. Declining leaves it to run, which is
        // slower and right. Strings are immutable, so every face below is pure
        // and has no such failure mode.
        const receiver = try self.eval(obj);

        // SUBJECT-FIRST APPLICATION OF A RELATION, TRIED FIRST WHEN THE CALLER
        // OPTED IN. `"src":run()` is `run(src)` with the subject moved in front
        // of the dot — the same rewrite the string faces use, applied to a
        // relation the caller has already proved, through the graph, is the
        // exact target of this application.
        //
        // THE BOUND RELATION WINS OVER THE STRING FACE, AND THAT ORDER IS THE
        // SOUND ONE, not a preference. `native.id` declares a relation named
        // `rev`, which is also a string face. Trying the face first would fold
        // `x:rev()` to a reversed string where the graph selected the user's
        // relation. The other direction cannot misfire: `foldRelationBody` only
        // binds names the graph resolved at every site in the closure, and a
        // site that really means the string face is an UNRESOLVED candidate,
        // which blocks the enclosing relation and so never reaches this
        // evaluator at all.
        if (self.options.native_fold) {
            if (self.lookup(method)) |callee| {
                if (callee == .func) return try self.applyFuncValue(callee, receiver, args);
            }
        }
        // COLLECTION-RELATION-ONE, ANSWERED RATHER THAN SCANNED — and asked
        // AFTER the bound relation, because a program that declares its own
        // `any` owns every call to it. That is the same order `evalMethodCall`
        // already uses against the string faces, for the same reason.
        if (collection) |shape| {
            if (self.options.native_fold) return try self.evalCollectionRelation(receiver, shape);
        }
        if (receiver == .string) {
            // Bounded on the stack rather than allocated: `options.alloc` is
            // optional. Built HERE and not before the dispatch above, because
            // an over-wide operand list is only a string face's problem — the
            // relation face passes its operands through `applyFuncValue`.
            var buf: [max_face_operands]*ast.Expr = undefined;
            if (args.len + 1 > buf.len) return error.UnsupportedExpression;
            buf[0] = obj;
            for (args, 0..) |a, i| buf[i + 1] = a;
            return self.evalStringBuiltin(method, buf[0 .. args.len + 1]);
        }
        return error.UnsupportedExpression;
    }

    /// THE QUESTION, ANSWERED — the compile-time half of `lowerAnyRelation`.
    ///
    /// The backend already answers a DETERMINED source with an immediate, so
    /// the relation's own cost there is zero. What it could not do is let the
    /// SURROUNDING relation fold, because the enclosing body contained an
    /// application and the door refused every one of those. This is the face
    /// that makes the enclosing body runnable: the question is stated, so it is
    /// answered here the same way it is answered there.
    ///
    /// AND IT IS STRICTLY STRONGER THAN `dnir_lower.foldBodyRelation`, which is
    /// a deliberately tiny recognizer over literals. This is the whole
    /// evaluator, so a predicate reading an outer binding, a module constant or
    /// a nested relation answers here — while the source itself may be any
    /// table this evaluator built, including one a loop wrote, which the
    /// backend's `const_tables` cannot represent.
    ///
    /// FAILS CLOSED AT EVERY STEP, and each refusal is load-bearing:
    ///
    ///   * a receiver that is not a compile-time TABLE — which is what a
    ///     runtime source is here, and it must stay a refusal or the 26x early
    ///     exit would be folded away into a wrong answer about a table this
    ///     evaluator never saw;
    ///   * a table with a named or non-contiguous key. A record has no element
    ///     descriptor (`docs/collection-relation.md` §5.8) and is a refusal,
    ///     not a default;
    ///   * A VERDICT THAT IS NOT A TRUTH. `Value.truthy` is LUA truthiness,
    ///     where `0` is TRUE, and this backend's branches read `0` as FALSE.
    ///     Reading an integer verdict through either convention would be a
    ///     second definition of the predicate — so an integer verdict refuses.
    ///     `sema.checkCollectionRelation` demands `bool` of the body relation
    ///     already, which is why this costs nothing that should have worked.
    ///
    /// A SHADOW, NOT A SCOPE, exactly as `dnir_lower.ResultName` is: the result
    /// name is pushed for one predicate and popped after, so an outer binding
    /// of the same spelling means what it meant before and after.
    fn evalCollectionRelation(
        self: *Evaluator,
        receiver: Value,
        shape: collection_relation.Shape,
    ) EvalError!Value {
        if (receiver != .table) return error.UnsupportedExpression;
        const entries = receiver.table;
        for (entries, 0..) |entry, i| {
            if (entry.name != null) return error.UnsupportedExpression;
            const key = entry.key orelse return error.UnsupportedExpression;
            if (key != .int) return error.UnsupportedExpression;
            if (key.int != @as(i64, @intCast(i + 1))) return error.UnsupportedExpression;
        }
        switch (shape.question) {
            .any => {
                for (entries) |entry| {
                    try self.step();
                    const mark = self.locals.items.len;
                    _ = try self.pushLocal(shape.param, entry.val);
                    const verdict = self.eval(shape.body) catch |err| {
                        self.popLocals(mark);
                        return err;
                    };
                    self.popLocals(mark);
                    if (verdict != .bool) return error.UnsupportedExpression;
                    if (verdict.bool) return .{ .bool = true };
                }
                return .{ .bool = false };
            },
        }
    }

    /// Apply a relation value to a subject already evaluated plus unevaluated
    /// operands. One implementation, shared with `evalCall`'s tail, so the
    /// dotted and subject-first faces cannot drift.
    fn applyFuncValue(
        self: *Evaluator,
        callee: Value,
        subject: ?Value,
        args: []const *ast.Expr,
    ) EvalError!Value {
        const func = callee.func.body;
        const supplied = args.len + @as(usize, if (subject != null) 1 else 0);
        if (func.vararg or supplied > func.params.len) return error.UnsupportedExpression;

        // Operands are evaluated in the CALLER's frame and the frame opens only
        // after, so `f(i)` still reads the caller's `i` while `f`'s own `i`
        // cannot be reached from inside `f`.
        var evaluated: [max_face_operands]Value = undefined;
        if (args.len > evaluated.len) return error.UnsupportedExpression;
        for (args, 0..) |argument, i| evaluated[i] = try self.eval(argument);

        const mark = self.locals.items.len;
        const outer_frame = self.frame_base;
        self.frame_base = mark;
        defer {
            self.frame_base = outer_frame;
            self.popLocals(mark);
        }
        for (callee.func.captures) |capture| {
            _ = try self.pushLocal(capture.name, capture.value);
        }
        var next: usize = 0;
        if (subject) |value| {
            _ = try self.pushPlace(func.params[0].name, value, types.narrowIntOfType(func.params[0].typ));
            next = 1;
        }
        for (func.params[next..], 0..) |param, i| {
            const value = if (i < args.len)
                evaluated[i]
            else if (param.default_val) |default_val|
                try self.eval(default_val)
            else
                Value.nil;
            // A PARAMETER IS A PLACE. `native_backend` narrows a declared
            // narrow parameter ON ENTRY precisely because the caller may not
            // have -- see its "arrives in a 64-bit register" note -- so the
            // fold binds the projection the callee would actually see.
            _ = try self.pushPlace(param.name, value, types.narrowIntOfType(param.typ));
        }
        return try self.evalBlockValue(&func.body);
    }

    /// Evaluate string.* standard library functions at compile time.
    fn evalStringBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len >= 1) {
            const a = try self.eval(args[0]);
            if (a != .string) return error.UnsupportedExpression;
            if (std.mem.eql(u8, name, "len")) return .{ .int = @intCast(a.string.len) };
            if (std.mem.eql(u8, name, "upper")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "lower")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[i] = std.ascii.toLower(c);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "rev") or std.mem.eql(u8, name, "reverse")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[a.string.len - 1 - i] = c;
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "byte") and args.len == 1) {
                if (a.string.len == 0) return .nil;
                return .{ .int = @intCast(a.string[0]) };
            }
            if (std.mem.eql(u8, name, "byte") and args.len >= 2) {
                const idx_val = try self.eval(args[1]);
                const idx = numericAsInt(idx_val) orelse return error.UnsupportedExpression;
                if (idx < 1 or idx > @as(i64, @intCast(a.string.len))) return .nil;
                return .{ .int = @intCast(a.string[@intCast(idx - 1)]) };
            }
            if (std.mem.eql(u8, name, "rep") and args.len == 2) {
                const count_val = try self.eval(args[1]);
                const count = numericAsInt(count_val) orelse return error.UnsupportedExpression;
                if (count <= 0) return .{ .string = "" };
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const n: usize = @intCast(count);
                const buf = alloc.alloc(u8, a.string.len * n) catch return error.UnsupportedExpression;
                var off: usize = 0;
                for (0..n) |_| {
                    @memcpy(buf[off .. off + a.string.len], a.string);
                    off += a.string.len;
                }
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "sub") and args.len >= 2) {
                const start_val = try self.eval(args[1]);
                const start_raw = numericAsInt(start_val) orelse return error.UnsupportedExpression;
                const len_i: i64 = @intCast(a.string.len);
                const s: i64 = if (start_raw < 0) @max(len_i + start_raw + 1, 1) else @max(start_raw, 1);
                var e: i64 = len_i;
                if (args.len >= 3) {
                    const end_val = try self.eval(args[2]);
                    const end_raw = numericAsInt(end_val) orelse return error.UnsupportedExpression;
                    e = if (end_raw < 0) len_i + end_raw + 1 else @min(end_raw, len_i);
                }
                if (s > e) return .{ .string = "" };
                const si: usize = @intCast(s - 1);
                const ei: usize = @intCast(e);
                return .{ .string = a.string[si..ei] };
            }
            if (std.mem.eql(u8, name, "find") and args.len >= 2) {
                const pattern = try self.eval(args[1]);
                if (pattern != .string) return error.UnsupportedExpression;
                const start_i: usize = if (args.len >= 3) blk: {
                    const sv = try self.eval(args[2]);
                    const s = numericAsInt(sv) orelse 1;
                    break :blk @max(1, @as(usize, @intCast(s - 1)));
                } else 0;
                if (start_i >= a.string.len) return .{ .int = 0 };
                if (pattern.string.len == 0) return .{ .int = @intCast(start_i + 1) };
                if (pattern.string.len > a.string.len - start_i) return .{ .int = 0 };
                const limit = a.string.len - pattern.string.len;
                var pos: usize = start_i;
                while (pos <= limit) : (pos += 1) {
                    if (std.mem.eql(u8, a.string[pos .. pos + pattern.string.len], pattern.string)) {
                        return .{ .int = @intCast(pos + 1) };
                    }
                }
                return .{ .int = 0 };
            }
            if (std.mem.eql(u8, name, "match") and args.len >= 2) {
                const pattern = try self.eval(args[1]);
                if (pattern != .string) return error.UnsupportedExpression;
                const start_i: usize = if (args.len >= 3) blk: {
                    const sv = try self.eval(args[2]);
                    const s = numericAsInt(sv) orelse 1;
                    break :blk @max(1, @as(usize, @intCast(s - 1)));
                } else 0;
                if (start_i >= a.string.len) return .nil;
                if (pattern.string.len == 0) return .{ .string = "" };
                if (pattern.string.len > a.string.len - start_i) return .nil;
                const limit = a.string.len - pattern.string.len;
                var pos: usize = start_i;
                while (pos <= limit) : (pos += 1) {
                    if (std.mem.eql(u8, a.string[pos .. pos + pattern.string.len], pattern.string)) {
                        return .{ .string = pattern.string };
                    }
                }
                return .nil;
            }
            if (std.mem.eql(u8, name, "split") and args.len == 2) {
                const sep_val = try self.eval(args[1]);
                if (sep_val != .string) return error.UnsupportedExpression;
                const sep = sep_val.string;
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                var entries: std.ArrayListUnmanaged(Value.TableEntry) = .empty;
                if (sep.len == 0) {
                    for (a.string, 0..) |c, idx| {
                        var buf = alloc.alloc(u8, 1) catch return error.UnsupportedExpression;
                        buf[0] = c;
                        entries.append(alloc, .{ .key = .{ .int = @intCast(idx + 1) }, .val = .{ .string = buf } }) catch return error.UnsupportedExpression;
                    }
                } else {
                    var pos: usize = 0;
                    var i: i64 = 1;
                    while (pos <= a.string.len) {
                        const rest = a.string[pos..];
                        const found = std.mem.indexOf(u8, rest, sep);
                        const end = if (found) |f| pos + f else a.string.len;
                        const part = a.string[pos..end];
                        const owned = alloc.dupe(u8, part) catch return error.UnsupportedExpression;
                        entries.append(alloc, .{ .key = .{ .int = i }, .val = .{ .string = owned } }) catch return error.UnsupportedExpression;
                        if (found == null) break;
                        pos = end + sep.len;
                        i += 1;
                    }
                }
                return .{ .table = entries.toOwnedSlice(alloc) catch return error.UnsupportedExpression };
            }
            if (std.mem.eql(u8, name, "trim") and args.len == 1) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                var start: usize = 0;
                var end: usize = a.string.len;
                while (start < end and std.ascii.isWhitespace(a.string[start])) start += 1;
                while (end > start and std.ascii.isWhitespace(a.string[end - 1])) end -= 1;
                const owned = alloc.dupe(u8, a.string[start..end]) catch return error.UnsupportedExpression;
                return .{ .string = owned };
            }
            if (std.mem.eql(u8, name, "char") and args.len >= 2) {
                const byte_val = try self.eval(args[1]);
                const byte_num = numericAsInt(byte_val) orelse return error.UnsupportedExpression;
                if (byte_num < 0 or byte_num > 255) return error.UnsupportedExpression;
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, 1) catch return error.UnsupportedExpression;
                buf[0] = @intCast(byte_num);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "format")) {
                // Fold disabled: the comptime spec parser did not handle width/precision
                // (e.g. "%.3f"), so it baked wrong literals. Let it run at runtime via
                // the C lua_str_format (codegen.zig), which now parses full printf specs.
                return error.UnsupportedExpression;
            }
        }
        return error.UnsupportedExpression;
    }

    fn evalStringFormat(self: *Evaluator, fmt: Value, extra_args: []const *ast.Expr) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        var result: std.ArrayListUnmanaged(u8) = .empty;
        defer result.deinit(alloc);
        var arg_idx: usize = 0;
        var i: usize = 0;
        while (i < fmt.string.len) : (i += 1) {
            const c = fmt.string[i];
            if (c != '%') {
                result.append(alloc, c) catch return error.UnsupportedExpression;
                continue;
            }
            i += 1;
            if (i >= fmt.string.len) break;
            const spec = fmt.string[i];
            if (spec == '%') {
                result.append(alloc, '%') catch return error.UnsupportedExpression;
                continue;
            }
            if (arg_idx >= extra_args.len) return error.UnsupportedExpression;
            const arg = try self.eval(extra_args[arg_idx]);
            arg_idx += 1;
            var buf: [30]u8 = undefined;
            switch (spec) {
                's' => {
                    const s = switch (arg) {
                        .string => arg.string,
                        .int => blk: {
                            const written = std.fmt.bufPrint(&buf, "{d}", .{arg.int}) catch "??";
                            break :blk written;
                        },
                        .float => blk: {
                            const written = std.fmt.bufPrint(&buf, "{d}", .{arg.float}) catch "??";
                            break :blk written;
                        },
                        .bool => if (arg.bool) "true" else "false",
                        .nil => "nil",
                        else => "??",
                    };
                    result.appendSlice(alloc, s) catch return error.UnsupportedExpression;
                },
                'd', 'i' => {
                    const written = switch (arg) {
                        .int => std.fmt.bufPrint(&buf, "{d}", .{arg.int}) catch "??",
                        .float => std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(arg.float))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                'f' => {
                    const written = switch (arg) {
                        .float => std.fmt.bufPrint(&buf, "{d}", .{arg.float}) catch "??",
                        .int => std.fmt.bufPrint(&buf, "{d}", .{@as(f64, @floatFromInt(arg.int))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                'x' => {
                    const written = switch (arg) {
                        .int => std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(arg.int))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                else => return error.UnsupportedExpression,
            }
        }
        return .{ .string = result.toOwnedSlice(alloc) catch return error.UnsupportedExpression };
    }

    /// Evaluate table.* standard library functions at compile time.
    fn evalTableBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len == 0) return error.UnsupportedExpression;
        const tbl = try self.eval(args[0]);
        if (tbl != .table) return error.UnsupportedExpression;
        if (std.mem.eql(u8, name, "insert") and args.len == 2) {
            const val = try self.eval(args[1]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            var new_entries = alloc.alloc(Value.TableEntry, tbl.table.len + 1) catch return error.UnsupportedExpression;
            @memcpy(new_entries[0..tbl.table.len], tbl.table);
            new_entries[tbl.table.len] = .{ .key = .{ .int = @intCast(tbl.table.len + 1) }, .val = val };
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "insert") and args.len == 3) {
            const pos_val = try self.eval(args[1]);
            const pos = numericAsInt(pos_val) orelse return error.UnsupportedExpression;
            const val = try self.eval(args[2]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            const new_len = tbl.table.len + 1;
            var new_entries = alloc.alloc(Value.TableEntry, new_len) catch return error.UnsupportedExpression;
            const insert_idx: usize = @intCast(@max(0, @min(pos - 1, @as(i64, @intCast(tbl.table.len)))));
            if (insert_idx > 0) @memcpy(new_entries[0..insert_idx], tbl.table[0..insert_idx]);
            new_entries[insert_idx] = .{ .key = .{ .int = pos }, .val = val };
            if (insert_idx < tbl.table.len) @memcpy(new_entries[insert_idx + 1 .. new_len], tbl.table[insert_idx..tbl.table.len]);
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "remove") and args.len >= 2) {
            const pos_val = try self.eval(args[1]);
            const pos = numericAsInt(pos_val) orelse return error.UnsupportedExpression;
            const idx: usize = if (pos >= 1 and pos <= @as(i64, @intCast(tbl.table.len)))
                @intCast(pos - 1)
            else
                return .nil;
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            if (tbl.table.len <= 1) return .{ .table = &.{} };
            var new_entries = alloc.alloc(Value.TableEntry, tbl.table.len - 1) catch return error.UnsupportedExpression;
            if (idx > 0) @memcpy(new_entries[0..idx], tbl.table[0..idx]);
            const rest = tbl.table.len - idx - 1;
            if (rest > 0) @memcpy(new_entries[idx .. idx + rest], tbl.table[idx + 1 .. tbl.table.len]);
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "concat")) {
            var result: std.ArrayListUnmanaged(u8) = .empty;
            const result_alloc = self.options.alloc orelse return error.UnsupportedExpression;
            defer result.deinit(result_alloc);
            var i: usize = 0;
            const sep_val: ?Value = if (args.len >= 2) try self.eval(args[1]) else null;
            const sep: []const u8 = if (sep_val) |sv| switch (sv) {
                .string => sv.string,
                else => "",
            } else "";
            while (i < tbl.table.len) : (i += 1) {
                if (i > 0 and sep.len > 0) result.appendSlice(result_alloc, sep) catch return error.UnsupportedExpression;
                const v = tbl.table[i].val;
                const s = switch (v) {
                    .string => v.string,
                    .int => blk: {
                        var buf: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{v.int}) catch return error.UnsupportedExpression;
                        const out = result_alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk out;
                    },
                    .float => blk: {
                        var buf: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{v.float}) catch return error.UnsupportedExpression;
                        const out = result_alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk out;
                    },
                    .bool => if (v.bool) "true" else "false",
                    .nil => "nil",
                    else => return error.UnsupportedExpression,
                };
                result.appendSlice(result_alloc, s) catch return error.UnsupportedExpression;
            }
            return .{ .string = result.toOwnedSlice(result_alloc) catch return error.UnsupportedExpression };
        }
        if (std.mem.eql(u8, name, "sort") and args.len == 1) {
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            var entries = alloc.alloc(Value.TableEntry, tbl.table.len) catch return error.UnsupportedExpression;
            @memcpy(entries, tbl.table);
            var j: usize = 1;
            while (j < entries.len) : (j += 1) {
                const key = entries[j];
                var k = j;
                while (k > 0) : (k -= 1) {
                    const prev = entries[k - 1];
                    const dominated = switch (prev.val) {
                        .int => |pv| switch (key.val) {
                            .int => |kv| pv > kv,
                            .float => |kvf| @as(f64, @floatFromInt(pv)) > kvf,
                            else => false,
                        },
                        .float => |pv| switch (key.val) {
                            .int => |kv| pv > @as(f64, @floatFromInt(kv)),
                            .float => |kv| pv > kv,
                            else => false,
                        },
                        .string => |ps| switch (key.val) {
                            .string => |ks| std.mem.order(u8, ps, ks) == .gt,
                            else => false,
                        },
                        .bool => |pb| switch (key.val) {
                            .bool => !pb and key.val.bool,
                            else => false,
                        },
                        else => false,
                    };
                    if (!dominated) break;
                    entries[k] = entries[k - 1];
                    entries[k - 1] = key;
                }
            }
            return .{ .table = entries };
        }
        if (std.mem.eql(u8, name, "sort") and args.len == 2) {
            _ = try self.eval(args[1]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            const entries = alloc.alloc(Value.TableEntry, tbl.table.len) catch return error.UnsupportedExpression;
            @memcpy(entries, tbl.table);
            return .{ .table = entries };
        }
        if (std.mem.eql(u8, name, "keys") and args.len == 1) {
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            var new_entries = alloc.alloc(Value.TableEntry, tbl.table.len) catch return error.UnsupportedExpression;
            for (tbl.table, 0..) |entry, i| {
                if (entry.name) |n| {
                    new_entries[i] = .{ .key = .{ .int = @intCast(i + 1) }, .val = .{ .string = n } };
                } else if (entry.key) |k| {
                    new_entries[i] = .{ .key = .{ .int = @intCast(i + 1) }, .val = k };
                }
            }
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "has") and args.len == 2) {
            const key = try self.eval(args[1]);
            for (tbl.table) |entry| {
                if (entry.name) |n| {
                    if (key == .string and std.mem.eql(u8, key.string, n)) return .{ .bool = true };
                } else if (entry.key) |k| {
                    if (k.eql(key)) return .{ .bool = true };
                }
            }
            return .{ .bool = false };
        }
        return error.UnsupportedExpression;
    }

    /// Evaluate math.* standard library functions at compile time.
    fn evalMathBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len == 1) {
            const a = try self.eval(args[0]);
            const v = numericAsFloat(a) orelse return error.UnsupportedExpression;
            if (std.mem.eql(u8, name, "abs")) return if (a == .int) .{ .int = if (a.int < 0) -a.int else a.int } else .{ .float = @abs(v) };
            if (std.mem.eql(u8, name, "floor")) return .{ .float = @floor(v) };
            if (std.mem.eql(u8, name, "ceil")) return .{ .float = @ceil(v) };
            if (std.mem.eql(u8, name, "sqrt")) return .{ .float = @sqrt(v) };
            if (std.mem.eql(u8, name, "sin")) return .{ .float = @sin(v) };
            if (std.mem.eql(u8, name, "cos")) return .{ .float = @cos(v) };
            if (std.mem.eql(u8, name, "tan")) return .{ .float = std.math.tan(v) };
            if (std.mem.eql(u8, name, "exp")) return .{ .float = @exp(v) };
            if (std.mem.eql(u8, name, "log")) return .{ .float = @log(v) };
            return error.UnsupportedExpression;
        }
        if (args.len == 2) {
            const a = try self.eval(args[0]);
            const b = try self.eval(args[1]);
            if (std.mem.eql(u8, name, "max")) {
                if (a == .int and b == .int) return .{ .int = if (a.int > b.int) a.int else b.int };
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = if (av > bv) av else bv };
            }
            if (std.mem.eql(u8, name, "min")) {
                if (a == .int and b == .int) return .{ .int = if (a.int < b.int) a.int else b.int };
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = if (av < bv) av else bv };
            }
            if (std.mem.eql(u8, name, "pow")) {
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = std.math.pow(f64, av, bv) };
            }
            return error.UnsupportedExpression;
        }
        return error.UnsupportedExpression;
    }

    fn evalTable(self: *Evaluator, fields: []const ast.TableField) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        var entries: std.ArrayList(Value.TableEntry) = .empty;
        var pos: i64 = 1;
        for (fields) |field| {
            switch (field) {
                .positional => |expr| {
                    const value = try self.eval(expr);
                    entries.append(alloc, .{ .key = .{ .int = pos }, .val = value }) catch return error.UnsupportedExpression;
                    pos += 1;
                },
                .named => |named| {
                    entries.append(alloc, .{ .name = named.key, .val = try self.eval(named.val) }) catch return error.UnsupportedExpression;
                },
                .indexed => |indexed| {
                    entries.append(alloc, .{ .key = try self.eval(indexed.key), .val = try self.eval(indexed.val) }) catch return error.UnsupportedExpression;
                },
                .spread => |expr| {
                    const spread_val = try self.eval(expr);
                    if (spread_val != .table) return error.UnsupportedExpression;
                    for (spread_val.table) |entry| {
                        entries.append(alloc, entry) catch return error.UnsupportedExpression;
                    }
                },
                .semantic => |sm| {
                    // `{ @op = impl }` — store under the `@op` key in comptime tables.
                    const key = if (sm.param) |p|
                        std.fmt.allocPrint(alloc, "@{s}({s})", .{ sm.op, p }) catch return error.UnsupportedExpression
                    else
                        std.fmt.allocPrint(alloc, "@{s}", .{sm.op}) catch return error.UnsupportedExpression;
                    entries.append(alloc, .{ .name = key, .val = try self.eval(sm.val) }) catch return error.UnsupportedExpression;
                },
            }
        }
        return .{ .table = entries.toOwnedSlice(alloc) catch return error.UnsupportedExpression };
    }

    fn evalUnop(self: *Evaluator, op: ast.UnOp, operand: *const ast.Expr) EvalError!Value {
        const value = try self.eval(operand);
        return switch (op) {
            .compile => value,
            .not => .{ .bool = !value.truthy() },
            .neg => switch (value) {
                .int => |v| .{ .int = -v },
                .float => |v| .{ .float = -v },
                else => error.UnsupportedOperator,
            },
            .bnot => switch (value) {
                .int => |v| .{ .int = ~v },
                else => error.UnsupportedOperator,
            },
            .len => switch (value) {
                .string => |v| .{ .int = @intCast(v.len) },
                .table => |v| .{ .int = @intCast(v.len) },
                else => error.UnsupportedOperator,
            },
        };
    }

    fn evalBinop(self: *Evaluator, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) EvalError!Value {
        if (op == .@"and") {
            const left = try self.eval(lhs);
            return if (left.truthy()) try self.eval(rhs) else left;
        }
        if (op == .@"or") {
            const left = try self.eval(lhs);
            return if (left.truthy()) left else try self.eval(rhs);
        }

        const left = try self.eval(lhs);
        const right = try self.eval(rhs);
        return switch (op) {
            .add, .sub, .mul, .div, .idiv, .mod, .pow => try evalNumeric(
                op,
                left,
                right,
                self.options.native_fold,
            ),
            .band, .bor, .bxor, .lshift, .rshift => try evalInteger(op, left, right),
            .concat => try self.evalConcat(left, right),
            // FAIL CLOSED ON AN UNDECIDABLE COMPARISON. Unlike the key-lookup
            // callers of `eql`, `==` has no fall-through: whatever comes back
            // here IS the program's answer, so "I cannot tell" has to stop the
            // fold rather than pick a side. The refusal leaves the body
            // lowered, exactly as an unsupported operator does.
            .eq => .{ .bool = left.eqlOrUnknown(right) orelse
                return error.UnsupportedOperator },
            .neq => .{ .bool = !(left.eqlOrUnknown(right) orelse
                return error.UnsupportedOperator) },
            .lt, .gt, .leq, .geq => try evalComparison(op, left, right),
            .contains, .@"and", .@"or" => error.UnsupportedOperator,
            .matmul => error.UnsupportedOperator,
            .pipeline => error.UnsupportedOperator,
        };
    }

    fn evalConcat(self: *Evaluator, left: Value, right: Value) EvalError!Value {
        if (left != .string or right != .string) return error.UnsupportedOperator;
        if (left.string.len == 0) return right;
        if (right.string.len == 0) return left;
        const alloc = self.options.alloc orelse return error.UnsupportedOperator;
        const joined = alloc.alloc(u8, left.string.len + right.string.len) catch return error.UnsupportedExpression;
        @memcpy(joined[0..left.string.len], left.string);
        @memcpy(joined[left.string.len..], right.string);
        return .{ .string = joined };
    }

    fn evalMatch(self: *Evaluator, match_expr: *const ast.MatchExpr) EvalError!Value {
        const scrutinee = try self.eval(match_expr.scrutinee);
        for (match_expr.arms) |arm| {
            const mark = self.locals.items.len;
            const matched = try self.matchPattern(arm.pattern, scrutinee);
            if (!matched) {
                self.popLocals(mark);
                continue;
            }
            if (arm.guard) |guard| {
                if (!(try self.eval(guard)).truthy()) {
                    self.popLocals(mark);
                    continue;
                }
            }
            const result = self.evalBlockValue(&arm.body);
            self.popLocals(mark);
            return result;
        }
        return error.UnsupportedExpression;
    }

    fn matchPattern(self: *Evaluator, pattern: ast.Pattern, value: Value) EvalError!bool {
        return switch (pattern) {
            .wildcard => true,
            .literal => |lit| (try self.eval(lit)).eql(value),
            .binding => |binding| blk: {
                _ = try self.pushLocal(binding.name, value);
                break :blk true;
            },
            .table_destr => |entries| try self.matchTablePattern(entries, value),
            .array_destr => |patterns| try self.matchArrayPattern(patterns, value),
            .rest => |name| blk: {
                _ = try self.pushLocal(name, value);
                break :blk true;
            },
            else => error.UnsupportedExpression,
        };
    }

    fn matchTablePattern(self: *Evaluator, entries: []const ast.Pattern.TableDestrEntry, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (entries) |entry| {
            const field_value = try tableFieldLookup(value, entry.key);
            if (!(try self.matchPattern(entry.pat, field_value))) return false;
        }
        return true;
    }

    fn matchArrayPattern(self: *Evaluator, patterns: []const ast.Pattern, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (patterns, 0..) |pattern, i| {
            if (pattern == .rest) {
                const rest = try self.arrayRest(value, @intCast(i + 1));
                _ = try self.pushLocal(pattern.rest, rest);
                return true;
            }
            const elem = try tableLookup(value, .{ .int = @intCast(i + 1) });
            if (!(try self.matchPattern(pattern, elem))) return false;
        }
        return true;
    }

    fn arrayRest(self: *Evaluator, value: Value, start_index: i64) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        if (value != .table) return error.UnsupportedExpression;
        var count: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) count += 1;
            }
        }
        const entries = alloc.alloc(Value.TableEntry, count) catch return error.UnsupportedExpression;
        var out_i: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) {
                    entries[out_i] = .{ .key = .{ .int = key.int - start_index + 1 }, .val = entry.val };
                    out_i += 1;
                }
            }
        }
        return .{ .table = entries };
    }

    fn evalBlockValue(self: *Evaluator, block: *const ast.Block) EvalError!Value {
        const result = try self.evalBlockScoped(block, true);
        return switch (result) {
            .value => |value| value,
            .none => error.UnsupportedExpression,
        };
    }

    /// TAIL POSITION IS A FACT THIS EVALUATOR MUST READ, NOT ASSUME.
    ///
    /// `dnir_lower` already owns the rule (`stmtIsTailSlot`, and the
    /// `while_loop` arm that passes `allow_return = false`): a loop body is
    /// NEVER an implicit-tail position, because its last expression runs once
    /// per ITERATION, not once per CALL. This evaluator asserted the opposite
    /// by construction — every `expr_stmt` produced `.value`, and every
    /// `.value` unwound the whole body — so the two producers of one fact
    /// disagreed, and the fold answered a program the backend never compiles.
    fn evalBlockScoped(self: *Evaluator, block: *const ast.Block, tail: bool) EvalError!BlockResult {
        const mark = self.locals.items.len;
        defer self.popLocals(mark);
        return self.evalBlock(block, tail);
    }

    fn evalBlock(self: *Evaluator, block: *const ast.Block, tail: bool) EvalError!BlockResult {
        for (block.stmts, 0..) |stmt, i| {
            // `stmtIsTailSlot`, verbatim: a trailing `tail_expr` takes the slot,
            // otherwise the last statement holds it.
            const slot = tail and block.tail_expr == null and i + 1 == block.stmts.len;
            const result = try self.evalStmt(stmt, slot, tail);
            if (result == .value) return result;
        }
        if (block.tail_expr) |expr| {
            const value = try self.eval(expr);
            // A non-tail block still RUNS its tail expression; it just does not
            // answer with it. Discarding the value is what a statement means.
            if (tail) return .{ .value = value };
            return .none;
        }
        return .none;
    }

    fn evalStmt(self: *Evaluator, stmt: ast.Stmt, slot: bool, tail: bool) EvalError!BlockResult {
        try self.step();
        return switch (stmt) {
            .local_decl => |decl| blk: {
                for (decl.names, 0..) |name, i| {
                    const value = if (i < decl.inits.len) try self.eval(decl.inits[i]) else Value.nil;
                    // THE INITIAL BINDING IS A WRITE. `t: u8 = a * b` stores
                    // the projection, exactly as a later `t = a * b` does.
                    _ = try self.pushPlace(name.ident, value, types.narrowIntOfType(name.typ));
                }
                break :blk .none;
            },
            .const_decl => |decl| blk: {
                _ = try self.pushPlace(decl.ident, try self.eval(decl.val), types.narrowIntOfType(decl.typ));
                break :blk .none;
            },
            .assign => |assign| blk: {
                for (assign.targets, 0..) |target, i| {
                    if (target.* != .name) return error.UnsupportedExpression;
                    const value = if (i < assign.values.len) try self.eval(assign.values[i]) else Value.nil;
                    try self.setLocal(target.name.ident, value);
                }
                break :blk .none;
            },
            .ret => |ret| blk: {
                if (ret.vals.len != 1) return error.UnsupportedExpression;
                break :blk .{ .value = try self.eval(ret.vals[0]) };
            },
            .expr_stmt => |expr_stmt| blk: {
                const value = try self.eval(expr_stmt.expr);
                break :blk if (slot) BlockResult{ .value = value } else BlockResult.none;
            },
            .call_stmt => |call_stmt| blk: {
                const value = try self.eval(call_stmt.expr);
                break :blk if (slot) BlockResult{ .value = value } else BlockResult.none;
            },
            .do_block => |do_block| try self.evalBlockScoped(&do_block.body, tail),
            .if_stmt => |if_stmt| try self.evalIf(if_stmt, tail),
            .while_loop => |while_loop| try self.evalWhile(while_loop),
            .num_for => |num_for| try self.evalNumFor(num_for),
            else => error.UnsupportedExpression,
        };
    }

    fn evalIf(self: *Evaluator, if_stmt: anytype, tail: bool) EvalError!BlockResult {
        if ((try self.eval(if_stmt.cond)).truthy()) return self.evalBlockScoped(&if_stmt.then, tail);
        for (if_stmt.elseifs) |elseif| {
            if ((try self.eval(elseif.cond)).truthy()) return self.evalBlockScoped(&elseif.body, tail);
        }
        if (if_stmt.else_body) |*else_body| return self.evalBlockScoped(else_body, tail);
        return .none;
    }

    /// A LOOP BODY IS NOT A TAIL POSITION, SO IT CANNOT ANSWER THE RELATION.
    ///
    /// `tail = false` is what makes an unbounded loop stay unbounded here: the
    /// body's fall-off value is discarded, the guard is asked again, and a
    /// `while 1 == 1` runs until the step budget refuses the fold. Divergence
    /// therefore leaves the fold as a REFUSAL — the loop is lowered and the
    /// program still hangs — instead of as an integer nobody proved.
    fn evalWhile(self: *Evaluator, while_loop: anytype) EvalError!BlockResult {
        while ((try self.eval(while_loop.cond)).truthy()) {
            try self.step();
            const result = try self.evalBlockScoped(&while_loop.body, false);
            if (result == .value) return result;
        }
        return .none;
    }

    fn evalNumFor(self: *Evaluator, num_for: anytype) EvalError!BlockResult {
        const start = numericAsInt(try self.eval(num_for.start)) orelse return error.UnsupportedOperator;
        const stop = numericAsInt(try self.eval(num_for.stop)) orelse return error.UnsupportedOperator;
        const step_value = if (num_for.step) |step_expr| numericAsInt(try self.eval(step_expr)) orelse return error.UnsupportedOperator else 1;
        if (step_value == 0) return error.UnsupportedOperator;
        const mark = self.locals.items.len;
        defer self.popLocals(mark);
        // The induction variable is a PLACE and may carry a descriptor:
        // `for k: u8 = 1, 300` counts through a `u8`, and `setLocal` below is
        // the write that has to know it.
        _ = try self.pushPlace(num_for.var_name, .{ .int = start }, types.narrowIntOfType(num_for.var_typ));
        var i = start;
        while (if (step_value > 0) i <= stop else i >= stop) : (i += step_value) {
            try self.step();
            try self.setLocal(num_for.var_name, .{ .int = i });
            const result = try self.evalBlockScoped(&num_for.body, false);
            if (result == .value) return result;
        }
        return .none;
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// LAWFUL NONEXECUTION, WITH APPLICATIONS ADMITTED.
//
// `dnir_lower.foldWholeBody` refuses ANY body containing an application. It had
// to: `ApplicationFact.effect` had no write site, so every call read `.unknown`
// and might have done anything. The fact is published now
// (`semantic_graph.publishApplicationEffects`), `graph_query` reads it, and
// this is the fold that consumes the reading.
//
// The old behaviour is kept EXACTLY for bodies that apply nothing — same two
// guards, same budget, same evaluator, empty bindings — so routing this in
// cannot move a case that folds today. The new capability is confined to the
// branch where the body does apply something.
// ─────────────────────────────────────────────────────────────────────────────

/// Spellings the evaluator itself intercepts before any binding is consulted.
/// A relation named one of these would be dispatched by the interpreter's own
/// rule instead of the relation the graph selected, so it is refused rather
/// than folded to whatever the interpreter happens to mean by it.
fn interceptedSpelling(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "__")) return true;
    const intercepted = [_][]const u8{
        // `evalCall` answers these from its own rule before it ever looks at a
        // binding, so a relation spelled one of them could never be reached.
        "type", "tonumber", "tostring",
        // namespace receivers `evalCall` routes on before any binding
        "math", "string",   "table",
    };
    // The string METHOD faces are deliberately NOT here. `evalMethodCall`
    // consults the bound relation FIRST when `native_fold` is on, so a
    // relation named `rev` or `find` is reached, not shadowed — and a site that
    // means the face instead is an unresolved candidate that blocks the fold
    // before it starts.
    for (intercepted) |word| {
        if (std.mem.eql(u8, word, name)) return true;
    }
    return false;
}

/// True when the body contains no application of any kind. Verbatim the
/// predicate `dnir_lower` used, moved here so that routing `foldRelationBody`
/// in leaves ONE copy rather than two (`law.arch.relation`).
///
/// PUBLIC because it is exactly the door `foldRelationBody` takes to the
/// `bodyHasLoop` dispatch below, and `src/loop_closure.zig` has to know whether
/// it is standing in front of that door before it deletes the loop the dispatch
/// keys on. Asking here rather than re-deriving keeps ONE predicate.
pub fn bodyHasNoApplication(b: *const ast.Block) bool {
    for (b.stmts) |st| if (!stmtHasNoApplication(&st)) return false;
    if (b.tail_expr) |te| return exprHasNoApplication(te);
    return true;
}

fn stmtHasNoApplication(st: *const ast.Stmt) bool {
    return switch (st.*) {
        .local_decl => |d| for (d.inits) |e| {
            if (!exprHasNoApplication(e)) break false;
        } else true,
        .assign => |a| blk: {
            for (a.targets) |e| if (!exprHasNoApplication(e)) break :blk false;
            for (a.values) |e| if (!exprHasNoApplication(e)) break :blk false;
            break :blk true;
        },
        .while_loop => |w| exprHasNoApplication(w.cond) and bodyHasNoApplication(&w.body),
        .num_for => |f| bodyHasNoApplication(&f.body),
        .do_block => |d| bodyHasNoApplication(&d.body),
        .if_stmt => |f| blk: {
            if (!exprHasNoApplication(f.cond)) break :blk false;
            if (!bodyHasNoApplication(&f.then)) break :blk false;
            for (f.elseifs) |ei| {
                if (!exprHasNoApplication(ei.cond)) break :blk false;
                if (!bodyHasNoApplication(&ei.body)) break :blk false;
            }
            break :blk if (f.else_body) |eb| bodyHasNoApplication(&eb) else true;
        },
        .ret => |r| for (r.vals) |e| {
            if (!exprHasNoApplication(e)) break false;
        } else true,
        .expr_stmt => |e| exprHasNoApplication(e.expr),
        .brk, .cont => true,
        else => false,
    };
}

fn exprHasNoApplication(e: *const ast.Expr) bool {
    return switch (e.*) {
        .call, .method_call, .macro_call => false,
        .binop => |b| exprHasNoApplication(b.lhs) and exprHasNoApplication(b.rhs),
        .unop => |u| exprHasNoApplication(u.operand),
        .if_expr => |ie| exprHasNoApplication(ie.cond) and
            exprHasNoApplication(ie.then_expr) and exprHasNoApplication(ie.else_expr),
        .index => |ix| exprHasNoApplication(ix.obj) and exprHasNoApplication(ix.key),
        .field => |f| exprHasNoApplication(f.obj),
        .name, .int_lit, .float_lit, .true_lit, .false_lit, .quoted, .nil => true,
        else => false,
    };
}

/// A BODY THAT IS ALREADY ITS ANSWER HAS FOLDED, AND SAYING SO IS NOT A
/// COURTESY — IT IS THE APPLICATION ACCOUNTING.
///
/// `folded_to_constant` is not a cosmetic label. `native_backend`'s
/// `unrealizedApplicationCount` reads it to learn which PUBLISHED applications
/// are realized nowhere, and every published application must be realized
/// exactly once or attributed to a fold. Returning null for a body that is a
/// bare literal was harmless while the only way to get one was to write it —
/// such a body publishes no application, so nothing was left unattributed.
///
/// It stopped being harmless the moment a body that DID publish applications
/// was replaced by its answer before lowering. `src/obseq.zig` does exactly
/// that: it closes the entry's loop to the constant its demanded observer
/// cannot distinguish, and once its grammar admits a call to a user-defined
/// relation the deleted body took the application with it. The backend then
/// counted one published application, zero realizations and zero folds, and
/// refused the program with DNB011 `application-realization-count` — a correct
/// refusal of a true inconsistency, whose real cause was this null.
///
/// So the answer is the honest one: the relation's value IS this constant, the
/// applications inside it are realized NOWHERE, and both facts travel together.
/// Nothing about ordinary lowering changes — a bare-literal body emits the same
/// `ret k` either way, and it publishes no applications for the count to
/// subtract, so a corpus with no rewritten body cannot tell the difference.
///
/// Deliberately the NARROWEST shape that carries the fact: one statement-free
/// tail integer literal, or a lone `return <int literal>`. A wider recognizer
/// here would be a second constant folder beside `runFold`.
fn constantAnswer(b: *const ast.Block) ?i64 {
    if (b.stmts.len == 0) {
        const tail = b.tail_expr orelse return null;
        return switch (tail.*) {
            .int_lit => |lit| lit.val,
            else => null,
        };
    }
    if (b.stmts.len == 1 and b.tail_expr == null) {
        switch (b.stmts[0]) {
            .ret => |r| {
                if (r.vals.len != 1) return null;
                return switch (r.vals[0].*) {
                    .int_lit => |lit| lit.val,
                    else => null,
                };
            },
            else => return null,
        }
    }
    return null;
}

/// True when the body contains a loop. This fold declines loops because it has
/// no termination budget for one; a loop body is the direct backend's job.
fn bodyHasLoop(b: *const ast.Block) bool {
    for (b.stmts) |st| {
        const has = switch (st) {
            .while_loop, .num_for, .repeat_loop, .gen_for => true,
            .do_block => |d| bodyHasLoop(&d.body),
            .if_stmt => |f| blk: {
                if (bodyHasLoop(&f.then)) break :blk true;
                for (f.elseifs) |ei| if (bodyHasLoop(&ei.body)) break :blk true;
                break :blk if (f.else_body) |eb| bodyHasLoop(&eb) else false;
            },
            else => false,
        };
        if (has) return true;
    }
    return false;
}

/// Bodies whose ONLY reader is the fold get a step budget rather than a proof
/// of termination. A loop of 1e9 iterations hits it and falls through to
/// ordinary lowering rather than folding for a minute.
///
/// THE BUDGET IS A TIME BUDGET. It is spelled in steps only because steps are
/// what this evaluator can count, so the constant is DERIVED and not chosen:
///
///     fold_step_limit = fold_target_ms * ns_per_ms / fold_ns_per_step
///
/// `fold_ns_per_step` is MEASURED, not estimated. Method: compile 20 relations
/// each holding one `while` loop, at loop counts 1 and 16,665, cold build cache,
/// minimum of seven runs; the difference is 3,999,360 evaluator steps and
/// nothing else. Measured 59.2 ns/step on `idol 6c231a95` and 60.0 on
/// `idol 48cfd928` (Apple Silicon). `gate/claim.sh` §3 re-measures it and fails
/// in BOTH directions, so this number cannot rot silently.
///
/// `fold_target_ms` is the policy half and is the only chosen number here: a
/// fold that runs to the limit and then FAILS is pure waste, and 12 ms is
/// already ~15% of the 81 ms it takes this compiler to build a seven-line file.
///
/// A PRIOR ESTIMATE PUT THIS AT ~40x, i.e. 8,000,000 steps. That is 480 ms of
/// wasted work per unfoldable relation — longer than a whole `native.id`
/// compile (412 ms). The estimate is wrong by exactly the factor it assumed the
/// evaluator was faster than it measures: 8,000,000 steps in 12 ms is
/// 1.5 ns/step, and this evaluator runs at 60.
const fold_target_ms: usize = 12;
const fold_ns_per_step: usize = 60;
/// PUBLIC because `src/loop_closure.zig` DEFERS to it: below this budget the
/// whole-relation fold answers and is strictly stronger than replacing one
/// loop, so the loop-level closure declines. Read rather than copied, so the
/// two mechanisms cannot drift into overlapping or into a gap.
pub const fold_step_limit: usize = fold_target_ms * std.time.ns_per_ms / fold_ns_per_step;

/// Run a no-operand relation body at compile time. Null when it cannot be run —
/// which is most bodies, and must stay cheap to discover.
///
/// `relation` is the graph id of the relation being lowered; `null` means the
/// caller has no graph identity for it, and with no identity there is no effect
/// fact, so an applying body is refused.
///
/// FAILS CLOSED at every step: no graph id, an unproven application, a name the
/// interpreter would intercept, an unsupported construct, the step budget — all
/// return null and leave the lowered body in place.
pub fn foldRelationBody(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    relation: ?semantic_graph.id,
    fb: *const ast.FuncBody,
) ?i64 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const scratch = arena.allocator();

    // A graph-owned projection must retain one inspectable realization until
    // the fold publishes an equivalence witness that names every eliminated
    // application. `Function.folded_to_constant` is only a presence bit and
    // cannot prove that a damaged projection still corresponds to the final
    // return value. Ordinary lowering already contracts an exact projection
    // to a constant and the backend coalesces it into the return register, so
    // refusing this broader fold preserves the two-instruction machine floor
    // while keeping Native and Wasm validation load-bearing.
    if (relation) |entity| {
        for (graph.applicationsInCaller(entity)) |application| {
            if (graph.aggregateAccess(application) != null) return null;
        }
    }

    if (bodyHasNoApplication(&fb.body)) {
        if (!bodyHasLoop(&fb.body)) return constantAnswer(&fb.body);
        return runFold(fb, .{}, .{
            .step_limit = fold_step_limit,
            .alloc = scratch,
            .native_fold = true,
        });
    }

    const entity = relation orelse return null;
    const closure = (graph_query.effectFreeClosure(graph, scratch, entity, &fb.body) catch
        return null) orelse return null;
    defer closure.deinit(scratch);

    var scope: std.StringHashMapUnmanaged(Value) = .empty;

    // MODULE-LEVEL CONSTANTS FIRST. `ring = 2147483647` at file scope is a free
    // name inside every relation that reads it, and the graph lifts no entity
    // for it — `dnir_lower` handles it separately, as an immediate, through
    // `collectModuleConsts`. Before this evaluator had call frames it resolved
    // such a name BY ACCIDENT, off whatever the caller happened to have on the
    // locals stack; with frames it is correctly unbound, and `native.id` stops
    // folding on `ring`. Binding it here is the honest version of what the
    // accident was doing.
    //
    // A binding whose initializer this evaluator cannot run is SKIPPED, not
    // refused: a relation that reads it then fails closed on the unbound name,
    // which is the same refusal by a shorter route.
    if (graph_query.moduleDeclaration(graph)) |module| {
        for (module.body.stmts) |statement| {
            const name: []const u8, const init: *const ast.Expr = switch (statement) {
                .const_decl => |d| .{ d.ident, d.val },
                .local_decl => |d| blk: {
                    if (d.names.len != 1 or d.inits.len != 1) continue;
                    break :blk .{ d.names[0].ident, d.inits[0] };
                },
                .assign => |a| blk: {
                    if (a.targets.len != 1 or a.values.len != 1) continue;
                    if (a.targets[0].* != .name) continue;
                    break :blk .{ a.targets[0].name.ident, a.values[0] };
                },
                else => continue,
            };
            if (interceptedSpelling(name)) continue;
            const so_far = [_]std.StringHashMapUnmanaged(Value){scope};
            const value = evalWithBindings(init, .{ .scopes = &so_far }, .{
                .step_limit = fold_step_limit,
                .alloc = scratch,
                .native_fold = true,
            }) catch continue;
            switch (value) {
                .int, .float, .bool, .string => {},
                else => continue,
            }
            const slot = scope.getOrPut(scratch, name) catch return null;
            if (slot.found_existing) return null;
            slot.value_ptr.* = value;
        }
    }

    for (closure.callees) |callee| {
        const node = graph.get(callee) orelse return null;
        const name = node.name orelse return null;
        if (interceptedSpelling(name)) return null;
        const declaration = graph_query.relationDeclaration(graph, callee) orelse return null;
        // A projection variant reaches its entity through a mangled path, never
        // a bare identifier, so binding one by name would bind the wrong thing.
        if (declaration.path.len != 1) return null;
        if (!std.mem.eql(u8, declaration.path[0], name)) return null;
        if (declaration.func.vararg or declaration.func.vararg_name != null) return null;
        // A local of the same spelling shadows the injected relation inside the
        // interpreter (`lookup` reads locals first) while the graph bound this
        // application to the relation. Refuse rather than let the two disagree.
        if (bindsIdent(&fb.body, name)) return null;
        for (closure.callees) |other| {
            const other_declaration = graph_query.relationDeclaration(graph, other) orelse return null;
            if (bindsIdent(&other_declaration.func.body, name)) return null;
            for (other_declaration.func.params) |param| {
                if (std.mem.eql(u8, param.name, name)) return null;
            }
        }
        const slot = scope.getOrPut(scratch, name) catch return null;
        // Two relations spelled the same is an ambiguity a by-name interpreter
        // cannot represent, whatever the graph knows about their ids.
        if (slot.found_existing) return null;
        slot.value_ptr.* = .{ .func = .{ .body = &declaration.func } };
    }

    const scopes = [_]std.StringHashMapUnmanaged(Value){scope};
    return runFold(fb, .{ .scopes = &scopes }, .{
        .step_limit = fold_step_limit,
        .alloc = scratch,
        .native_fold = true,
        .application_work = .{ .graph = graph, .sites = closure.sites },
    });
}

/// **THE VALUE OF ONE EXPRESSION, THROUGH THE SAME FOLD A WHOLE BODY GETS.**
///
/// `x = seed(1)` and `x = 12345` are the SAME FACT about the value of `x`
/// whenever `seed` is foldable, and a consumer that admits the second and
/// refuses the first is reading the SPELLING rather than the value. MEASURED,
/// `benchmarks/ftc/control/memform.id` against `regform.id` — byte-identical
/// but for that one line — 1,412,875,899 instructions retired against
/// 11,821,591, same answer 57 on both and 57 from an oracle that is not this
/// compiler, because `obseq.readMachine` required an `.int_lit` TOKEN.
///
/// This is deliberately NOT a second folder. It wraps the expression in a
/// statement-free body and hands it to `foldRelationBody`, so every fail-closed
/// guard that decides a whole body decides this too: no graph identity, an
/// application the effect fixpoint cannot prove pure, a name the interpreter
/// would intercept, a relation spelled like a local, the step budget. `os.env`
/// is refused there and must stay refused — an environment read is an INPUT,
/// not a constant, and admitting one would make the closed form answer a
/// different program.
///
/// The one thing it adds is the application-free tail: `foldRelationBody` sends
/// a body with no application and no loop to `constantAnswer`, which by design
/// recognizes only a literal. An expression has no ordinary lowering to fall
/// back to here, so `2 + 3` and `-5` are evaluated directly — with NO bindings,
/// which is what keeps it honest: a free name is unbound and the fold refuses.
pub fn foldValueExpr(
    alloc: std.mem.Allocator,
    graph: ?*const semantic_graph.SemanticGraph,
    relation: ?semantic_graph.id,
    e: *const ast.Expr,
) ?i64 {
    const loc: ast.Loc = .{ .file = "", .line = 0, .col = 0 };
    var no_params = [_]ast.FuncParam{};
    var no_stmts = [_]ast.Stmt{};
    const fb: ast.FuncBody = .{
        .loc = loc,
        .params = &no_params,
        .vararg = false,
        .ret_type = .inferred,
        .body = .{ .loc = loc, .stmts = &no_stmts, .tail_expr = @constCast(e) },
    };
    if (graph) |g| {
        if (foldRelationBody(alloc, g, relation, &fb)) |k| return k;
    }
    if (!bodyHasNoApplication(&fb.body)) return null;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const value = evalWithBindings(e, .{}, .{
        .step_limit = fold_step_limit,
        .alloc = arena.allocator(),
        .native_fold = true,
    }) catch return null;
    return switch (value) {
        .int => |n| n,
        else => null,
    };
}

fn runFold(fb: *const ast.FuncBody, bindings: Bindings, options: Options) ?i64 {
    const value = funcValue(fb, bindings, options) catch return null;
    const result = callFunctionValue(value, &.{}, bindings, options) catch return null;
    return switch (result) {
        .int => |n| n,
        else => null,
    };
}

/// True when the block binds `name` anywhere the interpreter would see it as a
/// local. Deliberately over-approximate: an assignment to an unbound name
/// creates a local in `setLocal`, so assignment targets count too.
fn bindsIdent(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |st| {
        const bound = switch (st) {
            .local_decl => |d| blk: {
                for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) break :blk true;
                break :blk false;
            },
            .const_decl => |d| std.mem.eql(u8, d.ident, name),
            .global_decl => |d| blk: {
                for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) break :blk true;
                break :blk false;
            },
            .assign => |a| blk: {
                for (a.targets) |t| {
                    if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) break :blk true;
                }
                break :blk false;
            },
            .while_loop => |w| bindsIdent(&w.body, name),
            .repeat_loop => |r| bindsIdent(&r.body, name),
            .do_block => |d| bindsIdent(&d.body, name),
            .num_for => |f| std.mem.eql(u8, f.var_name, name) or bindsIdent(&f.body, name),
            .gen_for => |g| blk: {
                for (g.vars) |v| if (std.mem.eql(u8, v, name)) break :blk true;
                break :blk bindsIdent(&g.body, name);
            },
            .if_stmt => |f| blk: {
                if (f.binding) |binding| {
                    if (std.mem.eql(u8, binding.name, name)) break :blk true;
                }
                if (bindsIdent(&f.then, name)) break :blk true;
                for (f.elseifs) |ei| if (bindsIdent(&ei.body, name)) break :blk true;
                break :blk if (f.else_body) |eb| bindsIdent(&eb, name) else false;
            },
            else => false,
        };
        if (bound) return true;
    }
    return false;
}

pub fn funcValue(func: *const ast.FuncBody, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    return evaluator.makeFunc(func);
}

pub fn callFunctionValue(func: Value, args: []const Value, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    if (func != .func) return error.UnsupportedExpression;
    const body = func.func.body;
    if (body.vararg or args.len > body.params.len) return error.UnsupportedExpression;

    const mark = evaluator.locals.items.len;
    defer evaluator.popLocals(mark);
    for (func.func.captures) |capture| {
        _ = try evaluator.pushLocal(capture.name, capture.value);
    }
    for (body.params, 0..) |param, i| {
        const value = if (i < args.len)
            args[i]
        else if (param.default_val) |default_val|
            try evaluator.eval(default_val)
        else
            Value.nil;
        _ = try evaluator.pushPlace(param.name, value, types.narrowIntOfType(param.typ));
    }
    return evaluator.evalBlockValue(&body.body);
}

fn tableFieldLookup(obj: Value, field: []const u8) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (std.mem.eql(u8, name, field)) return entry.val;
        } else if (entry.key) |key| {
            if (key == .string and std.mem.eql(u8, key.string, field)) return entry.val;
        }
    }
    return .nil;
}

fn tableLookup(obj: Value, key: Value) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (key == .string and std.mem.eql(u8, key.string, name)) return entry.val;
        } else if (entry.key) |entry_key| {
            if (entry_key.eql(key)) return entry.val;
        }
    }
    return .nil;
}

fn numericAsFloat(value: Value) ?f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        else => null,
    };
}

fn numericAsInt(value: Value) ?i64 {
    return switch (value) {
        .int => |v| v,
        else => null,
    };
}

fn evalNumeric(op: ast.BinOp, left: Value, right: Value, native_integers: bool) EvalError!Value {
    // ═══ ONE LAW FOR `//` AND `%`, AND IT IS THE LAW'S, NOT A BACKEND'S ═══
    //
    // THIS FUNCTION USED TO CONTAIN TWO INTEGER SEMANTICS. The `native_fold`
    // branch answered `@divTrunc`/`@rem` and the ordinary branch answered
    // `@divFloor`/`@mod` — truncating and floored, twelve lines apart, and
    // which one a program got depended on whether a fold happened to be running
    // under the native switch. Neither was chosen: the first was written to
    // match what AArch64 `sdiv`+`msub` happens to do, and the second to match
    // what Zig's `@mod` happens to do. **Idol's modulo law was whichever host
    // builtin someone typed**, which is HPLS §92 literally — the host defining
    // relation law — and HPLS §67, inheriting implementation-language numeric
    // assumptions accidentally.
    //
    // `docs/spec/law.md` §62 requires "modulo sign" to be "fully defined before
    // any FTCFTW claim" and it was not defined anywhere. It is now, in
    // `docs/rulings.md`: **FLOORED**, because law.md's own first line makes
    // "ordinary Lua meaning" the entry of the specialization chain, Lua's `%`
    // and `//` are floored, and an `i64` descriptor cannot be the reason —
    // Lua's `%` and `//` already answer an INTEGER for two integers, so the
    // descriptor changes nothing about this operator and cannot excuse changing
    // its answer.
    //
    // It is also the CHEAPER law, which is the part that inverts the instinct:
    // under floored law `x % 2^n -> and` and `x // 2^n -> asr` are identities
    // over the full i64 domain needing NO range fact, and no range or
    // known-bits fact exists anywhere in this compiler.
    if (left == .int and right == .int and (op == .idiv or op == .mod)) {
        const l = left.int;
        const r = right.int;
        // `@divFloor(minInt, -1)` overflows, and a trap is not a value. Refused
        // rather than folded, exactly as the divide-by-zero ruling requires.
        if (r == 0 or (r == -1 and l == std.math.minInt(i64))) return error.DivisionByZero;
        return switch (op) {
            .idiv => .{ .int = @divFloor(l, r) },
            .mod => .{ .int = @mod(l, r) },
            else => unreachable,
        };
    }
    if (native_integers and left == .int and right == .int and op != .pow) {
        const l = left.int;
        const r = right.int;
        return switch (op) {
            .add => .{ .int = l +% r },
            .sub => .{ .int = l -% r },
            .mul => .{ .int = l *% r },
            // `/` ON TWO INTEGERS IS STILL TRUNCATING, and that is an OPEN
            // ROW, not part of this ruling. Lua's `/` always produces a FLOAT
            // (`-7/10` is `-0.7`), so unlike `%` and `//` there is a real
            // descriptor question here — `a: i64 / b: i64` has no float to
            // return — and settling it is a separate ruling with a separate
            // cost. `docs/rulings.md` carries the `law:`/`today:`/`delta:` row.
            .div => if (r == 0 or (r == -1 and l == std.math.minInt(i64)))
                error.DivisionByZero
            else
                .{ .int = @divTrunc(l, r) },
            else => error.UnsupportedOperator,
        };
    }
    if (left == .int and right == .int and op != .div and op != .pow) {
        const l = left.int;
        const r = right.int;
        return switch (op) {
            .add => .{ .int = l +% r },
            .sub => .{ .int = l -% r },
            .mul => .{ .int = l *% r },
            else => error.UnsupportedOperator,
        };
    }

    const l = numericAsFloat(left) orelse return error.UnsupportedOperator;
    const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .add => .{ .float = l + r },
        .sub => .{ .float = l - r },
        .mul => .{ .float = l * r },
        .div => if (r == 0.0) error.DivisionByZero else .{ .float = l / r },
        .pow => .{ .float = std.math.pow(f64, l, r) },
        else => error.UnsupportedOperator,
    };
}

fn evalInteger(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    const l = numericAsInt(left) orelse return error.UnsupportedOperator;
    const r = numericAsInt(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .band => .{ .int = l & r },
        .bor => .{ .int = l | r },
        .bxor => .{ .int = l ^ r },
        .lshift => if (r >= 0 and r < 64) .{ .int = l << @intCast(r) } else error.UnsupportedOperator,
        .rshift => if (r >= 0 and r < 64) .{ .int = @as(i64, @bitCast(@as(u64, @bitCast(l)) >> @intCast(r))) } else error.UnsupportedOperator,
        else => error.UnsupportedOperator,
    };
}

fn evalComparison(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    if (numericAsFloat(left)) |l| {
        const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
        return .{ .bool = switch (op) {
            .lt => l < r,
            .gt => l > r,
            .leq => l <= r,
            .geq => l >= r,
            else => unreachable,
        } };
    }
    if (left == .string and right == .string) {
        const order = std.mem.order(u8, left.string, right.string);
        return .{ .bool = switch (op) {
            .lt => order == .lt,
            .gt => order == .gt,
            .leq => order != .gt,
            .geq => order != .lt,
            else => unreachable,
        } };
    }
    return error.UnsupportedOperator;
}

pub fn eval(expr: *const ast.Expr) EvalError!Value {
    var evaluator: Evaluator = .{};
    return evaluator.eval(expr);
}

pub fn evalWithBindings(expr: *const ast.Expr, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    return evaluator.eval(expr);
}

test "comptime eval: pure arithmetic" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var three = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    var four = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var mul = ast.Expr{ .binop = .{ .loc = loc, .op = .mul, .lhs = &three, .rhs = &four } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &two, .rhs = &mul } };
    try std.testing.expectEqual(Value{ .int = 14 }, try eval(&add));
}

test "comptime eval: scoped bindings and shadowing" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var outer: std.StringHashMapUnmanaged(Value) = .empty;
    defer outer.deinit(std.testing.allocator);
    var inner: std.StringHashMapUnmanaged(Value) = .empty;
    defer inner.deinit(std.testing.allocator);
    try outer.put(std.testing.allocator, "base", .{ .int = 10 });
    try inner.put(std.testing.allocator, "base", .{ .int = 20 });
    try inner.put(std.testing.allocator, "offset", .{ .int = 2 });
    const scopes = [_]std.StringHashMapUnmanaged(Value){ outer, inner };
    var base = ast.Expr{ .name = .{ .loc = loc, .ident = "base" } };
    var offset = ast.Expr{ .name = .{ .loc = loc, .ident = "offset" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &base, .rhs = &offset } };
    try std.testing.expectEqual(Value{ .int = 22 }, try evalWithBindings(&add, .{ .scopes = &scopes }, .{}));
}

test "comptime eval: runtime-only names are unsupported" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var name = ast.Expr{ .name = .{ .loc = loc, .ident = "x" } };
    try std.testing.expectError(error.UnsupportedExpression, eval(&name));
}

test "comptime eval: pure table literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var key = ast.Expr{ .quoted = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &two } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    const value = try evalWithBindings(&table, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .table);
    try std.testing.expectEqual(@as(usize, 3), value.table.len);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].key.?);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].val);
    try std.testing.expectEqualStrings("name", value.table[1].name.?);
    try std.testing.expectEqual(Value{ .int = 2 }, value.table[1].val);
    try std.testing.expectEqual(Value{ .string = "answer" }, value.table[2].key.?);
    try std.testing.expectEqual(Value{ .int = 42 }, value.table[2].val);
}

test "comptime eval: table field and index lookups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var name_value = ast.Expr{ .quoted = .{ .loc = loc, .val = "duo" } };
    var key = ast.Expr{ .quoted = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &name_value } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    var field = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "name" } };
    var index_key = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &index_key } };
    var named_index_key = ast.Expr{ .quoted = .{ .loc = loc, .val = "answer" } };
    var named_index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &named_index_key } };
    var missing = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "missing" } };

    try std.testing.expectEqual(Value{ .string = "duo" }, try evalWithBindings(&field, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 1 }, try evalWithBindings(&index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 42 }, try evalWithBindings(&named_index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value.nil, try evalWithBindings(&missing, .{}, .{ .alloc = alloc }));
}

test "comptime eval: string concat allocates deterministic literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var left = ast.Expr{ .quoted = .{ .loc = loc, .val = "du" } };
    var right = ast.Expr{ .quoted = .{ .loc = loc, .val = "o" } };
    var concat = ast.Expr{ .binop = .{ .loc = loc, .op = .concat, .lhs = &left, .rhs = &right } };
    const value = try evalWithBindings(&concat, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .string);
    try std.testing.expectEqualStrings("duo", value.string);
}

test "comptime eval: match expression with literal and guarded binding arms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };

    var scrutinee = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var one_result = ast.Expr{ .quoted = .{ .loc = loc, .val = "one" } };
    var binding_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var guard_min = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var guard = ast.Expr{ .binop = .{ .loc = loc, .op = .gt, .lhs = &binding_name, .rhs = &guard_min } };
    var forty = ast.Expr{ .int_lit = .{ .loc = loc, .val = 40 } };
    var body_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &body_name, .rhs = &forty } };

    const first_stmts = try alloc.alloc(ast.Stmt, 1);
    first_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&one_result}) } };
    const second_stmts = try alloc.alloc(ast.Stmt, 1);
    second_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&add}) } };
    const arms = try alloc.alloc(ast.MatchArm, 2);
    arms[0] = .{
        .pattern = .{ .literal = &one },
        .guard = null,
        .body = .{ .loc = loc, .stmts = first_stmts },
    };
    arms[1] = .{
        .pattern = .{ .binding = .{ .name = "n", .typ = null } },
        .guard = &guard,
        .body = .{ .loc = loc, .stmts = second_stmts },
    };
    var match_expr = ast.MatchExpr{ .loc = loc, .scrutinee = &scrutinee, .arms = arms };
    var expr = ast.Expr{ .match_expr = &match_expr };

    try std.testing.expectEqual(Value{ .int = 44 }, try evalWithBindings(&expr, .{}, .{ .alloc = alloc }));
}

test "comptime eval: match expression with table and array destructuring" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };

    var kind_key = ast.Expr{ .quoted = .{ .loc = loc, .val = "kind" } };
    var kind_val = ast.Expr{ .quoted = .{ .loc = loc, .val = "pair" } };
    var left_val = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var right_val = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    const table_fields = try alloc.alloc(ast.TableField, 3);
    table_fields[0] = .{ .indexed = .{ .key = &kind_key, .val = &kind_val } };
    table_fields[1] = .{ .named = .{ .key = "left", .val = &left_val } };
    table_fields[2] = .{ .named = .{ .key = "right", .val = &right_val } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = table_fields } };

    var literal_pair = ast.Expr{ .quoted = .{ .loc = loc, .val = "pair" } };
    const table_entries = try alloc.alloc(ast.Pattern.TableDestrEntry, 3);
    table_entries[0] = .{ .key = "kind", .pat = .{ .literal = &literal_pair } };
    table_entries[1] = .{ .key = "left", .pat = .{ .binding = .{ .name = "a", .typ = null } } };
    table_entries[2] = .{ .key = "right", .pat = .{ .binding = .{ .name = "b", .typ = null } } };
    var a_name = ast.Expr{ .name = .{ .loc = loc, .ident = "a" } };
    var b_name = ast.Expr{ .name = .{ .loc = loc, .ident = "b" } };
    var sum = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &a_name, .rhs = &b_name } };
    const table_body = try alloc.alloc(ast.Stmt, 1);
    table_body[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&sum}) } };
    const table_arms = try alloc.alloc(ast.MatchArm, 1);
    table_arms[0] = .{
        .pattern = .{ .table_destr = table_entries },
        .guard = null,
        .body = .{ .loc = loc, .stmts = table_body },
    };
    var table_match = ast.MatchExpr{ .loc = loc, .scrutinee = &table, .arms = table_arms };
    var table_expr = ast.Expr{ .match_expr = &table_match };
    try std.testing.expectEqual(Value{ .int = 5 }, try evalWithBindings(&table_expr, .{}, .{ .alloc = alloc }));

    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var three = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    const array_fields = try alloc.alloc(ast.TableField, 3);
    array_fields[0] = .{ .positional = &one };
    array_fields[1] = .{ .positional = &two };
    array_fields[2] = .{ .positional = &three };
    var array = ast.Expr{ .table = .{ .loc = loc, .fields = array_fields } };
    const array_patterns = try alloc.alloc(ast.Pattern, 2);
    array_patterns[0] = .{ .binding = .{ .name = "head", .typ = null } };
    array_patterns[1] = .{ .rest = "tail" };
    var head_name = ast.Expr{ .name = .{ .loc = loc, .ident = "head" } };
    var tail_name = ast.Expr{ .name = .{ .loc = loc, .ident = "tail" } };
    var tail_first_key = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var tail_first = ast.Expr{ .index = .{ .loc = loc, .obj = &tail_name, .key = &tail_first_key } };
    var array_sum = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &head_name, .rhs = &tail_first } };
    const array_body = try alloc.alloc(ast.Stmt, 1);
    array_body[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&array_sum}) } };
    const array_arms = try alloc.alloc(ast.MatchArm, 1);
    array_arms[0] = .{
        .pattern = .{ .array_destr = array_patterns },
        .guard = null,
        .body = .{ .loc = loc, .stmts = array_body },
    };
    var array_match = ast.MatchExpr{ .loc = loc, .scrutinee = &array, .arms = array_arms };
    var array_expr = ast.Expr{ .match_expr = &array_match };
    try std.testing.expectEqual(Value{ .int = 3 }, try evalWithBindings(&array_expr, .{}, .{ .alloc = alloc }));
}

test "comptime eval: do blocks with bounded loops and local mutation" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\local for_total = __constexpr(match true
        \\  case _ then do
        \\    local acc = 0
        \\    for i = 1, 4 do
        \\      acc += i
        \\    end
        \\    acc
        \\  end
        \\end)
        \\local while_total = __constexpr(match true
        \\  case _ then do
        \\    local n = 4
        \\    local acc = 0
        \\    while n > 0 do
        \\      acc += n
        \\      n -= 1
        \\    end
        \\    acc
        \\  end
        \\end)
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const first = module.body.stmts[0].local_decl.inits[0];
    const second = module.body.stmts[1].local_decl.inits[0];

    try std.testing.expectEqual(Value{ .int = 10 }, try evalWithBindings(first, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 10 }, try evalWithBindings(second, .{}, .{ .alloc = alloc }));
}

test "comptime eval: pure function calls and recursion" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\function fact(n: i64): i64
        \\  if n <= 1 then
        \\    return 1
        \\  end
        \\  return n * fact(n - 1)
        \\end
        \\local folded = __constexpr(fact(5))
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const func = &module.body.stmts[0].func_decl.func;
    var scope: std.StringHashMapUnmanaged(Value) = .empty;
    defer scope.deinit(alloc);
    try scope.put(alloc, "fact", try funcValue(func, .{}, .{ .alloc = alloc }));
    const scopes = [_]std.StringHashMapUnmanaged(Value){scope};
    const init = module.body.stmts[1].local_decl.inits[0];

    try std.testing.expectEqual(Value{ .int = 120 }, try evalWithBindings(init, .{ .scopes = &scopes }, .{ .alloc = alloc }));
}

test "comptime eval: function values snapshot lexical captures" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\local base = 10
        \\local add = function(n: i64): i64
        \\  return base + n
        \\end
        \\local folded = __constexpr(add(5))
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const base_init = module.body.stmts[0].local_decl.inits[0];
    const add_init = module.body.stmts[1].local_decl.inits[0];
    const folded_init = module.body.stmts[2].local_decl.inits[0];

    var scope: std.StringHashMapUnmanaged(Value) = .empty;
    defer scope.deinit(alloc);
    try scope.put(alloc, "base", try evalWithBindings(base_init, .{}, .{ .alloc = alloc }));
    const scopes = [_]std.StringHashMapUnmanaged(Value){scope};
    const add_value = try evalWithBindings(add_init, .{ .scopes = &scopes }, .{ .alloc = alloc });
    try scope.put(alloc, "add", add_value);
    try scope.put(alloc, "base", .{ .int = 20 });

    try std.testing.expectEqual(Value{ .int = 15 }, try evalWithBindings(folded_init, .{ .scopes = &scopes }, .{ .alloc = alloc }));
}

test "comptime eval: comptimefor sum template" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var zero = ast.Expr{ .int_lit = .{ .loc = loc, .val = 0 } };
    var five = ast.Expr{ .int_lit = .{ .loc = loc, .val = 5 } };
    var tmpl = ast.Expr{ .quoted = .{ .loc = loc, .val = "%i" } };
    var func = ast.Expr{ .name = .{ .loc = loc, .ident = "__comptimefor" } };
    var args = [_]*ast.Expr{ &zero, &five, &tmpl };
    var call = ast.Expr{ .call = .{ .loc = loc, .func = &func, .args = &args } };
    try std.testing.expectEqual(Value{ .int = 10 }, try eval(&call));
}

test "comptime eval: step limit" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    try std.testing.expectError(error.StepLimitExceeded, evalWithBindings(&one, .{}, .{ .step_limit = 0 }));
}

// ---------------------------------------------------------------------------
// THE METHOD FACE. `s:len()` is how .id spells it; `string.len(s)` is not a
// spelling any .id program uses. These parse REAL SOURCE rather than building
// AST by hand, because the defect being fixed was not in the fold — it was that
// the node the parser actually produces (`.method_call`) never reached it.
// ---------------------------------------------------------------------------

/// The body of the single relation in `source`, as the whole-body folder gets it.
fn methodFaceFixture(alloc: std.mem.Allocator, source: []const u8) !*const ast.FuncBody {
    var lexer = @import("lexer.zig").Lexer.init(source, "comptime-method-face.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    for (module.body.stmts) |*st| {
        if (st.* == .func_decl) return &st.func_decl.func;
    }
    return error.UnsupportedExpression;
}

/// What `dnir_lower.foldWholeBody` does, minus the two guards that keep it away
/// from these bodies. See the routed edit in the report: the fold below is the
/// whole of what the lowering would gain.
fn foldWholeBody(alloc: std.mem.Allocator, source: []const u8) !Value {
    const fb = try methodFaceFixture(alloc, source);
    const opts: Options = .{ .step_limit = 200_000, .alloc = alloc };
    const fv = try funcValue(fb, .{}, opts);
    return callFunctionValue(fv, &.{}, .{}, opts);
}

test "comptime eval: the method face reaches the string folder" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Measured before this arm existed: 14 instructions of runtime byte scan
    // for the first, 9 for the second. Both answers are these.
    try std.testing.expectEqual(Value{ .int = 5 }, try foldWholeBody(alloc,
        \\main: i64 = ()
        \\    "hello":len()
    ));
    // 1-INDEXED, and it must match what the backend emits: byte 2 of "hello"
    // is 'e' (101), not 'h' (104) and not 'l'.
    try std.testing.expectEqual(Value{ .int = 101 }, try foldWholeBody(alloc,
        \\main: i64 = ()
        \\    "hello":byte(2)
    ));
    try std.testing.expectEqual(Value{ .int = 104 }, try foldWholeBody(alloc,
        \\main: i64 = ()
        \\    "hello":byte(1)
    ));
}

test "comptime eval: the method face and the dotted face are one implementation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // If these two ever disagree, the receiver-prepending in `evalMethodCall`
    // has stopped being a pure re-spelling of the same call.
    const faces = [_][2][]const u8{
        .{ "\"hello\":len()", "string.len(\"hello\")" },
        .{ "\"hello\":byte(2)", "string.byte(\"hello\", 2)" },
        .{ "\"hello\":sub(2, 3):len()", "string.len(string.sub(\"hello\", 2, 3))" },
        .{ "\"hello\":upper():byte(1)", "string.byte(string.upper(\"hello\"), 1)" },
        .{ "\"hello\":rev():byte(1)", "string.byte(string.rev(\"hello\"), 1)" },
    };
    for (faces) |pair| {
        const method_src = try std.mem.concat(alloc, u8, &.{ "main: i64 = ()\n    ", pair[0], "\n" });
        const dotted_src = try std.mem.concat(alloc, u8, &.{ "main: i64 = ()\n    ", pair[1], "\n" });
        const m = try foldWholeBody(alloc, method_src);
        const d = try foldWholeBody(alloc, dotted_src);
        try std.testing.expect(m == .int and d == .int);
        try std.testing.expectEqual(d.int, m.int);
    }
}

test "comptime eval: a runtime receiver declines rather than inventing an answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The receiver is a PARAMETER — which, measured, is what every `:len()` and
    // `:byte(` site in `lib/native.id` actually has. There is no compile-time
    // string here and the fold must say so, not guess.
    try std.testing.expectError(error.UnsupportedExpression, foldWholeBody(alloc,
        \\n: i64 = (src: str)
        \\    src:len()
    ));
    // And an out-of-range index is `nil`, never a neighbouring byte.
    try std.testing.expectEqual(Value.nil, try foldWholeBody(alloc,
        \\main: i64 = ()
        \\    "hello":byte(6)
    ));
    try std.testing.expectEqual(Value.nil, try foldWholeBody(alloc,
        \\main: i64 = ()
        \\    "hello":byte(0)
    ));
}

test "comptime eval: a table receiver is refused, so no mutation is swallowed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `t:insert(4)` MUTATES `t`. `evalTableBuiltin` spells insert functionally
    // — it returns a new table and leaves the old one alone — so folding this
    // method call would build the answer, discard it, and report that the
    // statement succeeded, leaving `t` at three elements. The fold must decline
    // the whole body instead. If someone later routes tables through
    // `evalMethodCall`, this test is the one that fails.
    try std.testing.expectError(error.UnsupportedExpression, foldWholeBody(alloc,
        \\main: i64 = ()
        \\    t = (1, 2, 3)
        \\    t:insert(4)
        \\    t:len()
    ));
}

test "comptime eval: effect closure carries aggregate projection occurrence" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pick: i64 = (i: i64)
        \\    values = {10, 20, 30}
        \\    values[i]
        \\entry: i64 = ()
        \\    pick(2)
    ;
    var lexer = Lexer.init(source, "comptime-occurrence.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    table_apply.normalizeModule(alloc, &module, &checked.type_map);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    const home = try graph.liftModuleWithCheckedCalls(&module, &checked, "comptime-occurrence.id");
    const pick = graph.resolveInHome(home, "pick", .func) orelse
        return error.TestExpectedEqual;
    const entry = graph.resolveInHome(home, "entry", .func) orelse
        return error.TestExpectedEqual;
    const declaration = graph_query.relationDeclaration(&graph, entry) orelse
        return error.TestExpectedEqual;

    // `pick`'s dynamic projection has no exact result until its operand is
    // supplied. The fold must therefore execute that projection through the
    // closure's carried occurrence. Poisoning the initializer provenance after
    // graph publication makes the old source-table fallback refuse while the
    // exact graph occurrence still answers 20.
    var aggregate: ?semantic_graph.id = null;
    for (0..graph.aggregateCount()) |row| {
        const fact = graph.aggregateAt(row) orelse continue;
        if (fact.owner != pick or graph.aggregateProducer(fact.aggregate) != null) continue;
        const node = graph.get(fact.aggregate) orelse continue;
        if (node.scope != pick) continue;
        if (aggregate != null) return error.TestExpectedEqual;
        aggregate = fact.aggregate;
    }
    const source_initializer = @constCast(graph.valueExpression(aggregate orelse
        return error.TestExpectedEqual) orelse return error.TestExpectedEqual);
    const saved_initializer = source_initializer.*;
    source_initializer.* = .{ .nil = saved_initializer.loc() };
    defer source_initializer.* = saved_initializer;
    try std.testing.expectEqual(
        @as(?i64, 20),
        foldRelationBody(alloc, &graph, entry, &declaration.func),
    );
}

/// True for @comp.* hook callee names that take inline `fun()` callbacks folded at comptime.
pub fn isMetaCombinatorHook(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__comptime") or std.mem.startsWith(u8, name, "__meta") or
        std.mem.startsWith(u8, name, "__derive");
}

test "isMetaCombinatorHook" {
    try std.testing.expect(isMetaCombinatorHook("__comptimezip"));
    try std.testing.expect(isMetaCombinatorHook("__metatemplate"));
    try std.testing.expect(!isMetaCombinatorHook("print"));
}
