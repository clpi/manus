//! RANGE — proved bounds on the values an exact entity can hold.
//!
//! §2 lists ranges among the facts the one semantic graph carries, beside
//! effects, control dependencies and determinacy. This module is their bounded
//! producer; `SemanticGraph.ranges` is where the published answer lives and
//! `SemanticGraph.nonNegativeWidth` is how every projection reads it.
//!
//! IT PRODUCES A SECOND FACT AND CONSUMES IT HERE. `derivationOf` is the CHECK
//! that admits one ordinary result relation's result as a `Derivation` — one
//! tail expression closed over that relation's own parameters — and the
//! application arm of the transfer is the only thing that reads one. The column
//! is `SemanticGraph.results`, keyed by callable entity, and it exists because
//! `sum(a, b)` and `a + b` are the same value and only one of them was bounded.
//! Its deletion condition is the same walk as the range lattice's: both read
//! `ast` directly, and both go when the region census carries the assignment
//! set (`law.bridge.death`).
//!
//! WHERE THIS CAME FROM AND WHY IT MOVED. The lattice below ran inside
//! `dnir_lower.zig`, once per function, into `LowerCtx.nonneg_names` — a
//! name-keyed map that died with the lowering context — and left the compiler
//! as a BOOLEAN on a DNIR instruction (`native_ir.Instr.divisor_nonneg`).
//! Three defects follow from that shape. The proof was invisible to the C,
//! Wasm, JIT, interpreter and tooling projections, which lower from the same
//! graph. It had no stated invalidation, because nothing recorded what it
//! depended on. And a boolean is not reversible: a backend reading `true` had
//! no way back to the binding that was proved or to the width that proved it.
//!
//! THIS IS NOT A NEW FOREIGN AUTHORITY, AND ITS DEATH IS WITNESSED
//! (`law.bridge.death`). No producer is created here: the lattice already ran
//! in this compiler, in `dnir_lower.zig`, in Zig. What moved is WHERE ITS
//! ANSWER LIVES — out of a lowering-local map and onto `SemanticGraph.ranges`
//! — and the whole point of the move is that the fact is now expressible to a
//! consumer that is not this host.
//!
//!     HOST OWNER BEFORE   `dnir_lower.nonNegativeNames` -> `LowerCtx`,
//!                         invisible to every projection but one backend
//!     HOST OWNER NOW      this file, publishing `SemanticGraph.ranges`
//!     IDOL OWNER AFTER    the range producer in `.id`, once relation-level
//!                         fixpoint analysis is expressible — the graph column
//!                         and its readers do not move when it lands, because
//!                         `SemanticGraph.ranges` is already the authority and
//!                         this file is already only its producer
//!     NEXT HOST BOUNDARY  `nonNegScanBlock` walks `ast.Stmt` directly. That
//!                         AST walk is the deletion condition: when the region
//!                         census carries the assignment set this pass needs,
//!                         the walk goes and the transfer function is all that
//!                         is left to transfer.
//!
//! DELETION IS OBSERVABLE, not asserted: `gate/divisor.sh` and
//! `IDOL_FLOOR_FIXUP_ALWAYS` both read the published fact rather than this
//! file, so an Idol producer that publishes the same column passes them
//! unchanged and this file's absence is the proof it was a bridge.
//!
//! IT IS NOT A PLACE FACT, WHICH WAS MEASURED AND NOT ASSUMED. `place.Facts`
//! was tried first and it loses the answer: §6 says a scalar is not minted as
//! a place, so `b: i64 = 2` has no place at all and its bound has nowhere to
//! live. Publishing there dropped the cheap floored correction on
//! `examples/native_differential/known_divergent/g065_integer_division.id`,
//! which is the whole population of one-module differences the artifact
//! control found. A range is a fact about a BINDING; a place is an observable
//! location; the graph carries both and they are not the same subject.

const std = @import("std");
const ast = @import("ast.zig");

/// THE SIGN OF A BOUND NAME, PROVED — the producer of `SemanticGraph.ranges`.
///
/// THIS LIVED IN `dnir_lower.zig` AND WAS NOT A LOWERING FACT. It was computed
/// once per function into `LowerCtx.nonneg_names`, a name-keyed map that died
/// with the lowering context, and it left the graph as a BOOLEAN on a DNIR
/// instruction (`native_ir.Instr.divisor_nonneg`). Three things follow from
/// that shape and all three are defects. The proof was invisible to the C,
/// Wasm, JIT, interpreter and tooling projections, which lower from the same
/// graph and could not see it. It could not be invalidated, because nothing
/// recorded what it depended on. And a boolean on an instruction is not
/// reversible to anything: a backend reading `true` has no way back to the
/// place that was proved or to the width that proved it.
///
/// It is a PLACE FACT. `s = 0 · s = s + step(i)` bounds `s`, and `s` is a
/// place in this census with a binding site, an access list and a region. The
/// fact now sits on that place beside `mutation`, `escape` and `domain`, is
/// published once by `analyzeFunction`, and reaches every consumer of the
/// graph rather than one backend.
///
/// THE SIGN OF A DIVISOR, PROVED — and NOT the sign of a dividend.
/// ════════════════════════════════════════════════════════════════════════════
///
/// `emitFlooredDivRem` pays eight instructions and a five-deep dependency chain
/// after `msub` to turn the chip's TRUNCATED remainder into the law's FLOORED
/// one. Both of those costs collapse if the DIVISOR is known positive: the
/// floored remainder then takes a positive sign, the correction is `r < 0 ? r+y
/// : r`, and the `r == 0` select that the general form cannot do without stops
/// being reachable at all. Five instructions, two dependent steps.
///
/// NOTHING HERE PROVES ANYTHING ABOUT THE DIVIDEND, and that is a decision, not
/// an omission. Dropping the fixup entirely needs BOTH signs, and the dividend
/// in the kernel that motivated this is `a = i` inside `while i <= n · i = i+1`
/// — an ascending counter with no static bound. §"overflow wrap realized"
/// (constitution) makes `+` on i64 WRAP, so an unbounded ascending counter is
/// not provably non-negative and any analysis that said it was would be
/// asserting a no-overflow law this language does not have. The measured
/// difference is 1.17x for the divisor-only proof against 1.34x for the
/// unsound full removal, and the 0.17x that separates them is the price of
/// staying inside the law.
///
/// ════════════════════════════════════════════════════════════════════════════
/// THE LATTICE IS A WIDTH, NOT A BIT
/// ════════════════════════════════════════════════════════════════════════════
///
/// A name maps to `w` meaning "every value this name ever holds lies in
/// [0, 2^w)". `w` is what makes `+` admissible WITHOUT a no-overflow
/// assumption: `[0,2^a) + [0,2^b) ⊆ [0,2^(max(a,b)+1))`, and the moment that
/// exponent would pass 63 the fact is DROPPED rather than assumed. So
/// `(i*7+3) % 10000 + 1` is proved (the `%` caps it at 14 bits, `+1` at 15)
/// and `i = i + 1` is NOT (the width climbs past 63 and the name goes to top),
/// which is exactly the discrimination the law requires. A plain "is it
/// non-negative" boolean cannot make it: it has to either admit `+` and be
/// wrong about the counter, or refuse `+` and be useless on the kernel.
///
/// `%` IS THE RULE THAT PAYS. Floored remainder takes the sign of the DIVISOR
/// and is bounded by it, so `x % d` is in `[0, d)` for any dividend at all —
/// the one operator here whose result width is known from one operand. That is
/// what closes the loop-carried cycle `b = a % b`: `b`'s width is a fixpoint of
/// `w -> max(entry_width, w)`, and it settles at the entry width.
///
/// FLOW-INSENSITIVE ON PURPOSE. One width per name for the whole body, joined
/// over every assignment to it, so the answer does not depend on where in the
/// body it is asked and there is no per-point state for a later reordering to
/// invalidate. That is a weaker analysis than a flow-sensitive one and it is
/// the one that composes with a single-pass lowerer.
///
/// ASCENDING ITERATION FROM BOTTOM. Every assigned name starts at `[0, 2^0)` —
/// the set `{0}` — and only ever widens. The result at the fixpoint
/// over-approximates every value the name can hold; a name that never settles
/// inside 63 bits, or that is written by a form this pass does not model, is
/// simply absent from the answer and its divisions keep the general fixup.
/// Parameters are never in the answer: their value comes from a caller.
const nonneg_top: u8 = 64;
const nonneg_rounds: usize = 96;

fn nonNegWidthOfLit(v: i64) ?u8 {
    if (v < 0) return null;
    var w: u8 = 0;
    var n: u64 = @intCast(v);
    while (n != 0) : (n >>= 1) w += 1;
    return w;
}

fn nonNegJoin(a: ?u8, b: ?u8) ?u8 {
    const x = a orelse return null;
    const y = b orelse return null;
    return @max(x, y);
}

const NonNegEnv = std.StringHashMapUnmanaged(u8);

/// The width of `e`, or null when this pass cannot bound it below 2^63.
/// HOW A CALLER RESOLVES A NAME TO A WIDTH. There is ONE derivation below and
/// two things that ask it: the producer, reading its own in-flight lattice,
/// and every consumer, reading `SemanticGraph.ranges`. A second copy of "`+`
/// widens by one, `%` takes the divisor's bound" is a rival authority for the
/// same fact, so the lookup is a parameter and the derivation is not.
pub const Lookup = struct {
    ctx: *const anyopaque,
    of: *const fn (ctx: *const anyopaque, name: []const u8) ?u8,
    /// THE RETAINED DERIVATION of the result of the relation `callee` denotes
    /// in this context, or null when nothing was retained for it.
    ///
    /// OPTIONAL, AND ABSENCE IS THE OLD ANSWER. A lookup that does not supply
    /// this reaches `null` on every application, which is exactly what the
    /// transfer answered for an application before any derivation existed. A
    /// consumer therefore never becomes WRONG by not carrying the column, only
    /// weaker — which is the direction `law.fallback.zero` permits.
    result: ?*const fn (ctx: *const anyopaque, callee: []const u8) ?Derivation = null,
};

/// A RETAINED RESULT DERIVATION — what one ordinary result relation's result
/// IS, stated over that relation's own parameters.
///
/// THE TRANSFER ABOVE BOUNDS `a + b` AND REFUSED `sum(a, b)`, and those are the
/// same value written twice. Nothing about the application was unknowable: the
/// result is one expression over the parameters and the arguments are in hand
/// at the call site. What was missing is that the relation kept no statement of
/// its own result, so a caller held a NAME where it needed a derivation — and a
/// name is a coordinate, not a fact (`law.identity.projection`). Every consumer
/// of `SemanticGraph.ranges` therefore lost its proof the moment a program
/// factored one expression into one relation, which is a penalty aimed at
/// exactly the decomposition this project's naming law demands.
///
/// THE SPELLING IS NOT WHAT CHECKS IT. `derivationOf` is the whole admission
/// and it reads the BODY. A relation spelled `sum` over `a - b` retains `a - b`;
/// the transfer refuses `-` because a difference can be negative; the
/// application answers nothing. No arm below lets a word acquire a guarantee —
/// the guarantee is the retained expression, run through the same transfer that
/// would have run had the caller written it out.
///
/// IT FAILS CLOSED IN EVERY DIRECTION. Nothing retained, an arity that
/// disagrees with the call, a free name inside the derivation, a callee a local
/// shadows, or a nest deeper than `derivation_fuel` — each answers `null`, which
/// is what every consumer already reads as "nothing proved".
pub const Derivation = struct {
    /// The relation's parameters, in application order. Borrowed from the AST,
    /// which outlives the graph lift, so nothing here is owned.
    ///
    /// A CALL WHOSE ARGUMENT COUNT DISAGREES WITH THIS IS A CORRUPT FACT
    /// AGAINST THAT CALL and answers nothing — the derivation would otherwise
    /// be evaluated with a parameter bound to no argument at all.
    params: []const ast.FuncParam,
    /// The result expression, closed over `params` — `derivationOf` is what
    /// makes that a checked claim rather than a hope.
    expr: *const ast.Expr,
};

/// HOW THE PRODUCER REACHES THE SAME COLUMN. `widthsOf` settles its lattice
/// with the derivation below, and an application inside a body it is settling
/// must answer what the same application answers to a consumer — one fact, one
/// answer, whichever end asks. Absent = no application is proved, which is what
/// the producer answered before any derivation was retained.
pub const Results = struct {
    ctx: *const anyopaque,
    of: *const fn (ctx: *const anyopaque, callee: []const u8) ?Derivation,
};

/// How deep a retained derivation may reach through further applications.
///
/// TERMINATION LIVES HERE, NOT IN THE CHECK. `derivationOf` reads one body and
/// cannot see that `f` calls `g` calls `f`, so the transfer is what must stop,
/// and it stops by running out of fuel and answering nothing. A program that
/// nests deeper than this gets the general form, never a wrong one — so the
/// number is a cost bound and no proof depends on its value.
const derivation_fuel: u8 = 3;

/// The widest parameter list a derivation is retained for. The argument widths
/// live in a fixed array on the transfer's own stack frame, so a query face
/// that allocates nothing stays a query face that allocates nothing.
const derivation_params_max: usize = 8;

/// THE QUERY FACE — the width bounding `e`, or null when it cannot be bounded
/// below 2^63. Produces nothing and stores nothing.
pub fn widthOfExpr(lookup: Lookup, e: *const ast.Expr) ?u8 {
    return widthOfExprIn(lookup, e, derivation_fuel);
}

fn widthOfExprIn(lookup: Lookup, e: *const ast.Expr, fuel: u8) ?u8 {
    const w: ?u8 = switch (e.*) {
        .int_lit => |i| nonNegWidthOfLit(i.val),
        .true_lit, .false_lit => 1,
        .name => |n| lookup.of(lookup.ctx, n.ident),
        // NO UNARY IS ADMITTED. `-x` and `~x` both MAKE a sign bit, and `not x`
        // is only 0/1 if its lowering says so — a fact this pass would be
        // guessing at rather than reading.
        .unop => null,
        .binop => |b| blk: {
            switch (b.op) {
                // Bounded growth, checked below against 63.
                .add => break :blk if (nonNegJoin(widthOfExprIn(lookup, b.lhs, fuel), widthOfExprIn(lookup, b.rhs, fuel))) |m| m + 1 else null,
                .mul => {
                    const x = widthOfExprIn(lookup, b.lhs, fuel) orelse break :blk null;
                    const y = widthOfExprIn(lookup, b.rhs, fuel) orelse break :blk null;
                    break :blk @as(u8, x) + @as(u8, y);
                },
                // The floored remainder takes the sign of the DIVISOR and is
                // bounded by it. The dividend is not consulted and does not
                // need to be — this is the only rule here that reads one
                // operand, and it is why the analysis reaches anything at all.
                .mod => break :blk widthOfExprIn(lookup, b.rhs, fuel),
                // `a // b` and `a / b` with `a` in [0,2^w) and `b` positive
                // land in [0,2^w). `b` positive is `b` non-negative plus the
                // divisor guard, which has already refused zero on this path.
                .idiv, .div => {
                    const x = widthOfExprIn(lookup, b.lhs, fuel) orelse break :blk null;
                    _ = widthOfExprIn(lookup, b.rhs, fuel) orelse break :blk null;
                    break :blk x;
                },
                // A clear sign bit in EITHER operand clears it in the result,
                // and the narrower bound is the one that survives.
                .band => {
                    const x = widthOfExprIn(lookup, b.lhs, fuel);
                    const y = widthOfExprIn(lookup, b.rhs, fuel);
                    if (x == null) break :blk y;
                    if (y == null) break :blk x;
                    break :blk @min(x.?, y.?);
                },
                .bor, .bxor => break :blk nonNegJoin(widthOfExprIn(lookup, b.lhs, fuel), widthOfExprIn(lookup, b.rhs, fuel)),
                // LOGICAL shift right (`lsr`). A shift of AT LEAST ONE clears
                // the top bit whatever it held, which is the only case where
                // this rule proves anything the operand did not already have —
                // and `x >> 0` is the IDENTITY, so a negative operand stays
                // negative through it. Written without that case split first,
                // and the case split is the whole soundness of the arm.
                .rshift => {
                    const x = widthOfExprIn(lookup, b.lhs, fuel);
                    const k = ast.intLiteralValue(b.rhs) orelse break :blk x;
                    if (k < 0 or k > 63) break :blk null;
                    const shift: u8 = @intCast(k);
                    // A known `[0,2^w)` value loses `k` width bits. An
                    // otherwise unknown 64-bit word shifted by at least one
                    // first gains the 64-bit unsigned bound, then loses those
                    // same `k` bits. The old transfer formed `64-k` and then
                    // subtracted `k` AGAIN; for `x >> 1` it published width 62
                    // instead of 63, which let a following `+ 1` falsely prove
                    // a divisor non-negative at the INT64_MIN boundary.
                    const source_width: u8 = x orelse if (shift >= 1) 64 else break :blk null;
                    break :blk if (shift >= source_width) 0 else source_width - shift;
                },
                .lshift => {
                    const x = widthOfExprIn(lookup, b.lhs, fuel) orelse break :blk null;
                    const k = ast.intLiteralValue(b.rhs) orelse break :blk null;
                    if (k < 0 or k > 63) break :blk null;
                    break :blk x + @as(u8, @intCast(k));
                },
                // A comparison answers 0 or 1.
                .eq, .neq, .lt, .gt, .leq, .geq => break :blk 1,
                else => break :blk null,
            }
        },
        // AN APPLICATION IS BOUNDED BY THE RELATION'S RETAINED DERIVATION, and
        // by nothing else. `sum(x, 1)` is bounded exactly when `a + b` is
        // bounded with `a` and `b` standing for the argument expressions — the
        // same arm above, over the same lookup, one transfer.
        //
        // BOTH FACES REACH THE SAME FACT. `sum(x, 1)` and `x:sum(1)` are one
        // relation and one application (SUBJECT-ONE, `law.md` §9), so the
        // subject-first face binds parameter 0 to the receiver and the rest in
        // order. Answering for one face and not the other would make a proved
        // bound depend on which spelling the author chose, which is the defect
        // `law.identity.projection` names.
        .call => |c| applicationWidth(
            lookup,
            if (c.func.* == .name and !c.func.name.world) c.func.name.ident else null,
            null,
            c.args,
            fuel,
        ),
        .method_call => |m| applicationWidth(lookup, m.method, m.obj, m.args, fuel),
        else => null,
    };
    const width = w orelse return null;
    if (width > 63) return null;
    return width;
}

/// The width of one application's result, through the callee's retained
/// derivation. Every refusal below is a FAIL-CLOSED arm and answers `null`,
/// which is the answer an application gave before any derivation existed.
fn applicationWidth(
    lookup: Lookup,
    callee: ?[]const u8,
    subject: ?*const ast.Expr,
    args: []const *ast.Expr,
    fuel: u8,
) ?u8 {
    // OUT OF FUEL. `derivationOf` reads one body and cannot see that `f` calls
    // `g` calls `f`, so termination is this line's and not the check's.
    if (fuel == 0) return null;
    // NO COLUMN REACHES THIS LOOKUP. Not "no derivation" — the consumer simply
    // does not carry the fact, and gets the answer it got before it existed.
    const resolve = lookup.result orelse return null;
    // A CALLEE THAT IS NOT A PLAIN RELATION NAME — a field, an index, a value
    // held in a binding — denotes a relation this fact is not keyed to.
    const name = callee orelse return null;
    const derivation = resolve(lookup.ctx, name) orelse return null;
    const arity = args.len + @intFromBool(subject != null);
    // ARITY DISAGREES: a corrupt fact against this call. Evaluating the
    // derivation anyway would bind a parameter to no argument at all and read
    // its width as unknown, which silently answers for a DIFFERENT relation.
    if (derivation.params.len != arity) return null;
    if (arity > derivation_params_max) return null;

    var env = CallEnv{ .params = derivation.params, .outer = lookup, .widths = @splat(null) };
    var at: usize = 0;
    if (subject) |s| {
        env.widths[0] = widthOfExprIn(lookup, s, fuel - 1);
        at = 1;
    }
    // THE ARGUMENTS ARE MEASURED IN THE CALLER'S LOOKUP and the body in the
    // callee's: an argument names the caller's bindings and the derivation
    // names only its own parameters.
    for (args) |arg| {
        env.widths[at] = widthOfExprIn(lookup, arg, fuel - 1);
        at += 1;
    }
    return widthOfExprIn(env.lookup(), derivation.expr, fuel - 1);
}

/// ONE DERIVATION'S VIEW while it is being evaluated: its own parameters bound
/// to the widths of the arguments at one call site, and NOTHING ELSE REACHABLE.
///
/// A name that is not a parameter answers `null` here rather than escaping to
/// the caller's bindings. `derivationOf` proved the body closed over the
/// parameter list, so a free name reaching this point is a corrupt fact, and a
/// corrupt fact must not be repaired by reading a same-spelled binding that
/// belongs to whoever happened to call it.
const CallEnv = struct {
    params: []const ast.FuncParam,
    /// Kept so a derivation may itself apply a relation: the column is reached
    /// through the lookup that had it, never re-resolved here.
    outer: Lookup,
    widths: [derivation_params_max]?u8,

    fn lookup(self: *const CallEnv) Lookup {
        return .{ .ctx = self, .of = widthOfParam, .result = derivationOfNested };
    }

    fn widthOfParam(ctx: *const anyopaque, name: []const u8) ?u8 {
        const self: *const CallEnv = @ptrCast(@alignCast(ctx));
        for (self.params, 0..) |param, i| {
            if (i >= derivation_params_max) return null;
            if (std.mem.eql(u8, param.name, name)) return self.widths[i];
        }
        return null;
    }

    fn derivationOfNested(ctx: *const anyopaque, callee: []const u8) ?Derivation {
        const self: *const CallEnv = @ptrCast(@alignCast(ctx));
        const resolve = self.outer.result orelse return null;
        return resolve(self.outer.ctx, callee);
    }
};

/// THE CHECK — the derivation one relation retains for its result, or null when
/// it retains none.
///
/// A RESULT IS RETAINED ONLY WHEN IT IS ONE EXPRESSION OVER THE PARAMETERS.
/// Every refusal here is a case where the result is not a function of the
/// arguments alone, and answering for it would be answering about a value some
/// other relation chose:
///
///   * A STATEMENT IN THE BODY. A statement can bind, assign, branch or apply
///     for effect, and the tail is then a function of that state and not of the
///     parameters. This is the strongest refusal and it is also the deletion
///     condition: when the region census carries the assignment set, a body
///     whose statements are provably pure binding can retain the substituted
///     tail and this line narrows.
///   * A VARARG. The parameter list is then not the argument list, so no
///     positional binding exists to make.
///   * A FREE NAME. A module binding is written by relations this check never
///     looks at, so `mul(a) = a * k` is a claim about a value another relation
///     chose. Same rule as `widthsOf`'s `outer`, applied to the result.
///   * A CALLEE A PARAMETER SHADOWS. `apply(f, x) = f(x)` names a relation the
///     caller supplies; the retained fact would be keyed to whatever module
///     relation shares the spelling.
///
/// WHAT IT DOES NOT CHECK IS AS DELIBERATE. It does not ask whether the tail is
/// arithmetic, non-negative, or useful to any particular consumer. The
/// derivation is what the result IS; whether that supports a bound is the
/// transfer's question, asked separately, so a second consumer with a different
/// lattice reads the same fact without this check having pre-decided for it.
pub fn derivationOf(fb: *const ast.FuncBody) ?Derivation {
    if (fb.vararg or fb.vararg_name != null) return null;
    if (fb.params.len > derivation_params_max) return null;
    if (fb.body.stmts.len != 0) return null;
    const tail = fb.body.tail_expr orelse return null;
    for (fb.params) |param| {
        if (param.name.len == 0) return null;
    }
    if (!closedOverParams(fb.params, tail)) return null;
    return .{ .params = fb.params, .expr = tail };
}

fn isParam(params: []const ast.FuncParam, name: []const u8) bool {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return true;
    }
    return false;
}

/// Is every name `e` reads a parameter of `params` — the closure test
/// `derivationOf` admits a body on.
fn closedOverParams(params: []const ast.FuncParam, e: *const ast.Expr) bool {
    return switch (e.*) {
        .int_lit, .float_lit, .true_lit, .false_lit, .nil => true,
        // `@x` READS THE WORLD, not the parameter list, whatever it is spelled.
        .name => |n| !n.world and isParam(params, n.ident),
        .binop => |b| closedOverParams(params, b.lhs) and closedOverParams(params, b.rhs),
        // `@(expr)` is the same node at a different STAGE, and a stage is not a
        // value of the parameters.
        .unop => |u| !u.world_face and closedOverParams(params, u.operand),
        .call => |c| blk: {
            if (c.func.* != .name or c.func.name.world) break :blk false;
            if (isParam(params, c.func.name.ident)) break :blk false;
            for (c.args) |arg| {
                if (!closedOverParams(params, arg)) break :blk false;
            }
            break :blk true;
        },
        .method_call => |m| blk: {
            if (isParam(params, m.method)) break :blk false;
            if (!closedOverParams(params, m.obj)) break :blk false;
            for (m.args) |arg| {
                if (!closedOverParams(params, arg)) break :blk false;
            }
            break :blk true;
        },
        else => false,
    };
}

/// The producer's own view: the lattice it is settling, beside the retained
/// derivations of the module it is settling it in.
///
/// BOTH ENDS ASK ONE DERIVATION. Without the `results` field here the producer
/// would answer `null` for `d = sum(x, 1)` while a consumer answered a width
/// for the very same application, which is one fact with two answers — the
/// shape `law.fact.producer.one` exists to refuse.
const ProducerEnv = struct {
    widths: *const NonNegEnv,
    results: ?Results,

    fn lookup(self: *const ProducerEnv) Lookup {
        return .{
            .ctx = self,
            .of = widthOfName,
            .result = if (self.results == null) null else derivationOfCallee,
        };
    }

    fn widthOfName(ctx: *const anyopaque, name: []const u8) ?u8 {
        const self: *const ProducerEnv = @ptrCast(@alignCast(ctx));
        return self.widths.get(name);
    }

    fn derivationOfCallee(ctx: *const anyopaque, callee: []const u8) ?Derivation {
        const self: *const ProducerEnv = @ptrCast(@alignCast(ctx));
        const results = self.results orelse return null;
        return results.of(results.ctx, callee);
    }
};

/// The producer's own face of `widthOfExpr`, over the lattice it is settling.
fn nonNegWidth(widths: *const NonNegEnv, results: ?Results, e: *const ast.Expr) ?u8 {
    const env = ProducerEnv{ .widths = widths, .results = results };
    return widthOfExpr(env.lookup(), e);
}

/// A loop induction variable whose bound comes from the loop's own shape
/// rather than from the fixpoint. The fixpoint cannot bound a counter:
/// `i = i + 1` widens the width every round until it passes 63 and the name
/// goes to top. But `while i < N` with `i = i + k` for a positive literal `k`
/// keeps `i` inside `[0, N + k)`, so when `N` is provably non-negative the IV
/// is provably bounded — and the increment must hold the cap instead of
/// widening past it.
const BoundedIV = struct {
    name: []const u8,
    cap: u8,
};

/// Is `v` the increment `iv + k` (either operand order) with `k` a positive
/// integer literal — the only write to a bounded IV the shape proof admits.
fn boundedIncrement(iv: []const u8, v: *const ast.Expr) bool {
    if (v.* != .binop or v.binop.op != .add) return false;
    const lhs = v.binop.lhs;
    const rhs = v.binop.rhs;
    const k_expr = if (lhs.* == .name and std.mem.eql(u8, lhs.name.ident, iv))
        rhs
    else if (rhs.* == .name and std.mem.eql(u8, rhs.name.ident, iv))
        lhs
    else
        return false;
    const k = ast.intLiteralValue(k_expr) orelse return false;
    return k > 0;
}

/// Every write to `iv` in `blk` is the positive increment, and `step_w` takes
/// the widest step seen. Any other write — or any construct this walk does
/// not look through — refuses, dropping the bound.
fn bodyIncrementsOnly(blk: *const ast.Block, iv: []const u8, step_w: *u8) bool {
    for (blk.stmts) |st| switch (st) {
        .assign => |a| {
            if (a.targets.len != a.values.len) return false;
            for (a.targets, a.values) |t, v| {
                if (t.* != .name) continue;
                if (!std.mem.eql(u8, t.name.ident, iv)) continue;
                if (!boundedIncrement(iv, v)) return false;
                const k_expr = if (v.binop.lhs.* == .name) v.binop.rhs else v.binop.lhs;
                const k = ast.intLiteralValue(k_expr) orelse return false;
                step_w.* = @max(step_w.*, nonNegWidthOfLit(k) orelse return false);
            }
        },
        .local_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, iv)) return false;
        },
        .const_decl => |d| if (std.mem.eql(u8, d.ident, iv)) return false,
        .global_decl => |d| {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, iv)) return false;
        },
        .do_block => |d| if (!bodyIncrementsOnly(&d.body, iv, step_w)) return false,
        .while_loop => |w| if (!bodyIncrementsOnly(&w.body, iv, step_w)) return false,
        .repeat_loop => |r| if (!bodyIncrementsOnly(&r.body, iv, step_w)) return false,
        .if_stmt => |f| {
            if (!bodyIncrementsOnly(&f.then, iv, step_w)) return false;
            for (f.elseifs) |ei| if (!bodyIncrementsOnly(&ei.body, iv, step_w)) return false;
            if (f.else_body) |eb| if (!bodyIncrementsOnly(&eb, iv, step_w)) return false;
        },
        .num_for => |f| {
            if (std.mem.eql(u8, f.var_name, iv)) return false;
            if (!bodyIncrementsOnly(&f.body, iv, step_w)) return false;
        },
        .gen_for => |f| {
            for (f.vars) |v| if (std.mem.eql(u8, v, iv)) return false;
            if (!bodyIncrementsOnly(&f.body, iv, step_w)) return false;
        },
        // A call cannot write a caller's local. A module-global IV written by
        // any relation is foreign, seeded at top before this walk, and
        // already refused the bound below.
        .call_stmt, .expr_stmt, .ret, .brk, .cont, .label_stmt => {},
        else => return false,
    };
    return true;
}

/// If this `while` is a bounded counter — `iv < bound` or `iv <= bound` (or
/// the mirrored `bound > iv`, `bound >= iv`) with `bound` provably
/// non-negative, `iv` already holding a provably non-negative value from its
/// initialization, and every body write to `iv` the positive increment —
/// seed `iv` at the bound-derived cap and answer the context the body scan
/// holds. Anything else answers null and the loop keeps the old behavior.
fn matchBoundedWhile(
    alloc: std.mem.Allocator,
    widths: *NonNegEnv,
    results: ?Results,
    cond: *const ast.Expr,
    body: *const ast.Block,
    changed: *bool,
) std.mem.Allocator.Error!?BoundedIV {
    if (cond.* != .binop) return null;
    const b = cond.binop;
    const iv: []const u8 = switch (b.op) {
        .lt, .leq => if (b.lhs.* == .name) b.lhs.name.ident else return null,
        .gt, .geq => if (b.rhs.* == .name) b.rhs.name.ident else return null,
        else => return null,
    };
    const bound: *const ast.Expr = switch (b.op) {
        .lt, .leq => b.rhs,
        .gt, .geq => b.lhs,
        else => return null,
    };
    const bound_w = nonNegWidth(widths, results, bound) orelse return null;
    // The initialization textually precedes the loop in any valid program,
    // so the in-order scan has observed it by now. A top value — negative,
    // unknown, or unmodeled — refuses.
    const init_w = widths.get(iv) orelse return null;
    if (init_w >= nonneg_top) return null;
    var step_w: u8 = 0;
    if (!bodyIncrementsOnly(body, iv, &step_w)) return null;
    // At the head `iv` is below `bound`; after `iv + k` below `bound + k`.
    // The initialization's own width joins separately, so the cap needs no
    // `init_w` term — and leaving it out keeps the cap stable across rounds.
    const cap: u8 = @max(bound_w, step_w) + 1;
    if (cap > 63) return null;
    try nonNegObserve(alloc, widths, iv, cap, changed);
    return BoundedIV{ .name = iv, .cap = cap };
}

/// One pass of the transfer function over every assignment in `blk`.
/// `changed` is set when a name's width grew. `unmodeled` is set when the body
/// contains a construct this pass does not model, which discards everything.
/// `biv` is the bounded induction variable of an enclosing `while`, whose
/// increment holds its cap instead of widening past it.
fn nonNegScanBlock(
    alloc: std.mem.Allocator,
    widths: *NonNegEnv,
    results: ?Results,
    blk: *const ast.Block,
    changed: *bool,
    unmodeled: *bool,
    biv: ?BoundedIV,
) std.mem.Allocator.Error!void {
    for (blk.stmts) |st| switch (st) {
        .local_decl => |d| {
            if (d.names.len != d.inits.len) {
                for (d.names) |n| try nonNegRaise(alloc, widths, n.ident, changed);
                continue;
            }
            for (d.names, d.inits) |n, init| try nonNegObserve(alloc, widths, n.ident, nonNegWidth(widths, results, init), changed);
        },
        .assign => |a| {
            if (a.targets.len != a.values.len) {
                for (a.targets) |t| if (t.* == .name) try nonNegRaise(alloc, widths, t.name.ident, changed);
                continue;
            }
            for (a.targets, a.values) |t, v| {
                if (t.* != .name) continue;
                if (biv) |b| {
                    if (std.mem.eql(u8, t.name.ident, b.name)) {
                        // The loop shape proved this IV bounded; only its
                        // increment may write it, and it keeps the cap. Any
                        // other write breaks the proof.
                        if (boundedIncrement(b.name, v)) {
                            try nonNegObserve(alloc, widths, b.name, b.cap, changed);
                        } else {
                            try nonNegRaise(alloc, widths, b.name, changed);
                        }
                        continue;
                    }
                }
                try nonNegObserve(alloc, widths, t.name.ident, nonNegWidth(widths, results, v), changed);
            }
        },
        // A name bound by any of these takes a value this pass does not model.
        .global_decl => |d| for (d.names) |n| try nonNegRaise(alloc, widths, n.ident, changed),
        .num_for => |f| {
            // The driver keeps the IV inside the closed interval between
            // `start` and `stop` (inclusive stop, either sign of step), so
            // provably non-negative bounds prove the IV. A body write only
            // widens the join, which stays sound.
            const start_w = nonNegWidth(widths, results, f.start);
            const stop_w = nonNegWidth(widths, results, f.stop);
            if (start_w != null and stop_w != null) {
                try nonNegObserve(alloc, widths, f.var_name, @max(start_w.?, stop_w.?), changed);
            } else {
                try nonNegRaise(alloc, widths, f.var_name, changed);
            }
            try nonNegScanBlock(alloc, widths, results, &f.body, changed, unmodeled, biv);
        },
        .gen_for => |f| {
            for (f.vars) |v| try nonNegRaise(alloc, widths, v, changed);
            try nonNegScanBlock(alloc, widths, results, &f.body, changed, unmodeled, biv);
        },
        .while_loop => |w| {
            const inner = try matchBoundedWhile(alloc, widths, results, w.cond, &w.body, changed);
            try nonNegScanBlock(alloc, widths, results, &w.body, changed, unmodeled, inner orelse biv);
        },
        .repeat_loop => |r| try nonNegScanBlock(alloc, widths, results, &r.body, changed, unmodeled, biv),
        .do_block => |d| try nonNegScanBlock(alloc, widths, results, &d.body, changed, unmodeled, biv),
        .if_stmt => |f| {
            if (f.binding) |b| try nonNegRaise(alloc, widths, b.name, changed);
            try nonNegScanBlock(alloc, widths, results, &f.then, changed, unmodeled, biv);
            for (f.elseifs) |ei| try nonNegScanBlock(alloc, widths, results, &ei.body, changed, unmodeled, biv);
            if (f.else_body) |eb| try nonNegScanBlock(alloc, widths, results, &eb, changed, unmodeled, biv);
        },
        // A nested function body can rebind names this one holds, and this pass
        // does not follow it. Refuse the WHOLE function rather than answer for
        // the part of it that is visible.
        .func_decl => unmodeled.* = true,
        .match_stmt, .try_stmt, .defer_stmt, .goto_stmt, .label_stmt => unmodeled.* = true,
        else => {},
    };
}

fn nonNegRaise(alloc: std.mem.Allocator, widths: *NonNegEnv, name: []const u8, changed: *bool) std.mem.Allocator.Error!void {
    const gop = try widths.getOrPut(alloc, name);
    if (gop.found_existing and gop.value_ptr.* >= nonneg_top) return;
    gop.value_ptr.* = nonneg_top;
    changed.* = true;
}

fn nonNegObserve(alloc: std.mem.Allocator, widths: *NonNegEnv, name: []const u8, w: ?u8, changed: *bool) std.mem.Allocator.Error!void {
    const width = w orelse return nonNegRaise(alloc, widths, name, changed);
    const gop = try widths.getOrPut(alloc, name);
    if (!gop.found_existing) {
        gop.value_ptr.* = width;
        changed.* = true;
        return;
    }
    if (gop.value_ptr.* >= width) return;
    gop.value_ptr.* = width;
    changed.* = true;
}

/// The names whose every value lies in [0, 2^63). Caller owns the map; keys are
/// borrowed from the AST and outlive it here.
fn nonNegativeNames(
    alloc: std.mem.Allocator,
    body: *const ast.Block,
    params: []const []const u8,
    foreign: []const []const u8,
    results: ?Results,
) std.mem.Allocator.Error!NonNegEnv {
    var widths: NonNegEnv = .empty;
    errdefer widths.deinit(alloc);
    var changed = true;
    var unmodeled = false;
    // A PARAMETER IS TOP AND STAYS TOP. Seeding it before the first scan is
    // what keeps `a = param` from entering the answer on round one and never
    // being corrected: this lattice only widens, and top is already the top.
    for (params) |p| try widths.put(alloc, p, nonneg_top);
    // ...AND SO IS EVERY NAME THIS FUNCTION DOES NOT OWN. A module global is
    // written by other relations this pass never looks at, and a module
    // constant is not in the body's assignment list at all — reading either as
    // "assigned only where I can see" would answer for a value another
    // function chose. Both are seeded at top, and the lattice only widens, so
    // neither can be talked back down.
    for (foreign) |p| try widths.put(alloc, p, nonneg_top);
    var round: usize = 0;
    while (changed and !unmodeled and round < nonneg_rounds) : (round += 1) {
        changed = false;
        try nonNegScanBlock(alloc, &widths, results, body, &changed, &unmodeled, null);
    }
    // Not converged, or a construct this pass does not model: answer nothing.
    if (unmodeled or changed) {
        widths.deinit(alloc);
        return .empty;
    }
    // Only the settled, bounded names are an answer.
    var out: NonNegEnv = .empty;
    errdefer out.deinit(alloc);
    var it = widths.iterator();
    while (it.next()) |e| if (e.value_ptr.* < nonneg_top) try out.put(alloc, e.key_ptr.*, e.value_ptr.*);
    widths.deinit(alloc);
    return out;
}


/// The name-keyed answer for one relation body. Caller owns it; keys are
/// borrowed from the AST, which outlives the graph lift.
pub const Env = NonNegEnv;

/// THE PRODUCER. `outer` is every name bound OUTSIDE this body that the body
/// may assign — module bindings and module constants.
///
/// IT FAILS CLOSED WITHOUT `outer`. A width is a claim about every value a
/// name holds, and a module binding is written by relations this walk never
/// sees: reading `g = 5` inside one body as "g is bounded by 3 bits" answers
/// for a value another relation chose.
/// The name-keyed answer for a MODULE body. `foreign` is every name the
/// module body does not own but may observe being written elsewhere — in
/// particular, names assigned inside any relation body. Those are seeded at
/// top and can never be talked down, so a module binding written by a
/// relation this walk never sees cannot enter the answer.
pub fn widthsOfModule(
    alloc: std.mem.Allocator,
    body: *const ast.Block,
    foreign: []const []const u8,
) !Env {
    return nonNegativeNames(alloc, body, &.{}, foreign, null);
}

pub fn widthsOf(
    alloc: std.mem.Allocator,
    fb: *const ast.FuncBody,
    outer: []const []const u8,
    results: ?Results,
) !Env {
    const params = try alloc.alloc([]const u8, fb.params.len);
    defer alloc.free(params);
    for (fb.params, 0..) |par, i| params[i] = par.name;
    return nonNegativeNames(alloc, &fb.body, params, outer, results);
}

/// EVERY NAME BOUND AT MODULE SCOPE — the `outer` argument, taken from the
/// module the body was lifted from.
///
/// Relation names are deliberately absent. The set exists to stop a body's
/// assignment from bounding a name another relation also writes, and a
/// declared relation is not written by an assignment; including them would
/// only drop proofs. This is the same population `dnir_lower` built from
/// `module_globals.types` and `module_consts.ints` — one source now, taken
/// from the module rather than from two lowering side tables.
pub fn outerNames(alloc: std.mem.Allocator, mod: *const ast.Module) ![]const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer out.deinit(alloc);
    for (mod.body.stmts) |*stmt| switch (stmt.*) {
        .const_decl => |d| try out.append(alloc, d.ident),
        .local_decl => |d| for (d.names) |n| try out.append(alloc, n.ident),
        .global_decl => |d| for (d.names) |n| try out.append(alloc, n.ident),
        .assign => |a| for (a.targets) |t| {
            if (t.* == .name) try out.append(alloc, t.name.ident);
        },
        else => {},
    };
    return out.toOwnedSlice(alloc);
}

// ── the retained derivation ──────────────────────────────────────────────────

fn testDerivationOf(alloc: std.mem.Allocator, source: []const u8, relation: []const u8) !?Derivation {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var lexer = Lexer.init(source, "derivation.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try alloc.create(ast.Module);
    module.* = try parser.parse_module();
    for (module.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1) continue;
        if (!std.mem.eql(u8, fd.path[0], relation)) continue;
        return derivationOf(&fd.func);
    }
    return error.TestUnexpectedResult;
}

test "range: a result derivation is retained exactly when the result is closed over the parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Case = struct { source: []const u8, retained: bool };
    // THE CHECK READS THE BODY, and the second row is the whole point of the
    // diagnostic: `sum` spelled over `a - b` RETAINS a derivation — of `a - b`.
    // It is the transfer that refuses a difference, so no relation acquires the
    // sum guarantee by being spelled `sum`.
    const cases = [_]Case{
        .{ .source = "sum: i64 = (a: i64, b: i64)\n    a + b\n", .retained = true },
        .{ .source = "sum: i64 = (a: i64, b: i64)\n    a - b\n", .retained = true },
        .{ .source = "sum: i64 = (a: i64)\n    a\n", .retained = true },
        .{ .source = "sum: i64 = (a: i64, b: i64)\n    a:add(b)\n", .retained = true },
        // A statement can bind, assign, branch or apply for effect, so the tail
        // is a function of that state and not of the parameters.
        .{ .source = "sum: i64 = (a: i64, b: i64)\n    t = a + b\n    t\n", .retained = false },
        // `k` is written by relations this check never looks at.
        .{ .source = "k: i64 = 3\nsum: i64 = (a: i64)\n    a + k\n", .retained = false },
        // The callee is a value the CALLER supplies; keying the fact to a
        // module relation of that spelling would answer for another relation.
        .{ .source = "sum: i64 = (f: i64, x: i64)\n    f(x)\n", .retained = false },
        // No result at all.
        .{ .source = "sum: i64 = (a: i64)\n    b = a\n", .retained = false },
    };
    for (cases) |case| {
        const derivation = try testDerivationOf(alloc, case.source, "sum");
        try std.testing.expectEqual(case.retained, derivation != null);
    }
}

test "range: an application is bounded by the retained derivation and by nothing else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The one fact under test, and a lookup that binds `x` to four bits.
    const Reach = struct {
        derivation: ?Derivation,
        fn widthOfName(ctx: *const anyopaque, name: []const u8) ?u8 {
            _ = ctx;
            return if (std.mem.eql(u8, name, "x")) 4 else null;
        }
        fn derivationOfCallee(ctx: *const anyopaque, callee: []const u8) ?Derivation {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            if (!std.mem.eql(u8, callee, "sum")) return null;
            return self.derivation;
        }
    };

    const parsed = (try testDerivationOf(alloc, "sum: i64 = (a: i64, b: i64)\n    a + b\n", "sum")).?;
    // `sum(x, 1)` — parsed as the divisor of a `%`, which is where a consumer
    // meets it.
    const call = blk: {
        const Lexer = @import("lexer.zig").Lexer;
        const Parser = @import("parser.zig").Parser;
        var lexer = Lexer.init("use: i64 = (n: i64)\n    n % sum(x, 1)\n", "use.id");
        var parser = Parser.init(&lexer, alloc);
        parser.idol_mode = true;
        const module = try alloc.create(ast.Module);
        module.* = try parser.parse_module();
        const tail = module.body.stmts[0].func_decl.func.body.tail_expr.?;
        try std.testing.expect(tail.* == .binop);
        break :blk tail.binop.rhs;
    };

    // RETAINED: `a + b` over widths 4 and 1 is `max(4,1)+1`.
    var reach = Reach{ .derivation = parsed };
    const with = Lookup{ .ctx = &reach, .of = Reach.widthOfName, .result = Reach.derivationOfCallee };
    try std.testing.expectEqual(@as(?u8, 5), widthOfExpr(with, call));

    // REMOVED: nothing proved.
    var gone = Reach{ .derivation = null };
    const without = Lookup{ .ctx = &gone, .of = Reach.widthOfName, .result = Reach.derivationOfCallee };
    try std.testing.expectEqual(@as(?u8, null), widthOfExpr(without, call));

    // NO COLUMN AT ALL — a consumer that does not carry the fact gets the
    // answer an application gave before the fact existed.
    const blind = Lookup{ .ctx = &reach, .of = Reach.widthOfName };
    try std.testing.expectEqual(@as(?u8, null), widthOfExpr(blind, call));

    // CORRUPT ARITY: one parameter against two arguments answers nothing
    // rather than reading the missing argument's width as unknown.
    var truncated = Reach{ .derivation = .{ .params = parsed.params[0..1], .expr = parsed.expr } };
    const corrupt = Lookup{ .ctx = &truncated, .of = Reach.widthOfName, .result = Reach.derivationOfCallee };
    try std.testing.expectEqual(@as(?u8, null), widthOfExpr(corrupt, call));

    // WRONG RELATION, RIGHT SPELLING: `sum` over `a - b` retains a derivation
    // and still proves nothing, because a difference can be negative.
    const difference = (try testDerivationOf(alloc, "sum: i64 = (a: i64, b: i64)\n    a - b\n", "sum")).?;
    var wrong = Reach{ .derivation = difference };
    const named = Lookup{ .ctx = &wrong, .of = Reach.widthOfName, .result = Reach.derivationOfCallee };
    try std.testing.expectEqual(@as(?u8, null), widthOfExpr(named, call));

    // A SELF-REFERENTIAL DERIVATION TERMINATES AND ANSWERS NOTHING. `derivationOf`
    // reads one body and cannot see a cycle, so `derivation_fuel` is what ends
    // this — and `x` proves the derivation's own view is closed while it does:
    // `x` is four bits in the CALLER's lookup and is not a parameter of `sum`,
    // so it does not escape inward to reach that width.
    const escaped = (try testDerivationOf(alloc, "sum: i64 = (a: i64, b: i64)\n    a + b\n", "sum")).?;
    var relabelled = Reach{ .derivation = .{ .params = escaped.params, .expr = call } };
    const nested = Lookup{ .ctx = &relabelled, .of = Reach.widthOfName, .result = Reach.derivationOfCallee };
    try std.testing.expectEqual(@as(?u8, null), widthOfExpr(nested, call));
}

/// Parse `source` as a module and answer the settled module-scope width of
/// `name`, or null when the analysis proves nothing.
fn testModuleWidth(alloc: std.mem.Allocator, source: []const u8, name: []const u8) !?u8 {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var lexer = Lexer.init(source, "bounded.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try alloc.create(ast.Module);
    module.* = try parser.parse_module();
    var widths = try widthsOfModule(alloc, &module.body, &.{});
    defer widths.deinit(alloc);
    return widths.get(name);
}

test "range: a canonical while counter is bounded by its loop shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `i` runs 1..99 in the body and holds 100 after the final increment:
    // width 7 covers the bound, plus one for the step.
    const w = try testModuleWidth(alloc, "i = 1\nwhile i < 100\n    i = i + 1\n", "i");
    try std.testing.expectEqual(@as(?u8, 8), w);
}

test "range: a while counter with a negative start proves nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const w = try testModuleWidth(alloc, "i = 0 - 1\nwhile i < 100\n    i = i + 1\n", "i");
    try std.testing.expectEqual(@as(?u8, null), w);
}

test "range: a while counter with an unknown bound proves nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const w = try testModuleWidth(alloc, "i = 1\nwhile i < n\n    i = i + 1\n", "i");
    try std.testing.expectEqual(@as(?u8, null), w);
}

test "range: a while counter with a non-unit step stays bounded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Step 3: the cap is max(bound, step) + 1, still 8 for bound 100.
    const w = try testModuleWidth(alloc, "i = 1\nwhile i < 100\n    i = i + 3\n", "i");
    try std.testing.expectEqual(@as(?u8, 8), w);
}

test "range: a while counter with an extra write proves nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const w = try testModuleWidth(alloc, "i = 1\nwhile i < 100\n    i = i + 1\n    i = 5\n", "i");
    try std.testing.expectEqual(@as(?u8, null), w);
}

test "range: nested while counters keep independent bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const src = "i = 1\nwhile i < 100\n    j = 1\n    while j < 1000\n        j = j + 1\n    i = i + 1\n";
    const wi = try testModuleWidth(alloc, src, "i");
    const wj = try testModuleWidth(alloc, src, "j");
    try std.testing.expectEqual(@as(?u8, 8), wi);
    try std.testing.expectEqual(@as(?u8, 11), wj);
}

test "range: a num_for IV is bounded by its start and stop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const w = try testModuleWidth(alloc, "for i = 1, 100\n    x = i\n", "i");
    try std.testing.expectEqual(@as(?u8, 7), w);
}
