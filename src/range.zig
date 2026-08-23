//! RANGE — proved bounds on the values an exact entity can hold.
//!
//! §2 lists ranges among the facts the one semantic graph carries, beside
//! effects, control dependencies and determinacy. This module is their bounded
//! producer; `SemanticGraph.ranges` is where the published answer lives and
//! `SemanticGraph.nonNegativeWidth` is how every projection reads it.
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
};

/// THE QUERY FACE — the width bounding `e`, or null when it cannot be bounded
/// below 2^63. Produces nothing and stores nothing.
pub fn widthOfExpr(lookup: Lookup, e: *const ast.Expr) ?u8 {
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
                .add => break :blk if (nonNegJoin(widthOfExpr(lookup, b.lhs), widthOfExpr(lookup, b.rhs))) |m| m + 1 else null,
                .mul => {
                    const x = widthOfExpr(lookup, b.lhs) orelse break :blk null;
                    const y = widthOfExpr(lookup, b.rhs) orelse break :blk null;
                    break :blk @as(u8, x) + @as(u8, y);
                },
                // The floored remainder takes the sign of the DIVISOR and is
                // bounded by it. The dividend is not consulted and does not
                // need to be — this is the only rule here that reads one
                // operand, and it is why the analysis reaches anything at all.
                .mod => break :blk widthOfExpr(lookup, b.rhs),
                // `a // b` and `a / b` with `a` in [0,2^w) and `b` positive
                // land in [0,2^w). `b` positive is `b` non-negative plus the
                // divisor guard, which has already refused zero on this path.
                .idiv, .div => {
                    const x = widthOfExpr(lookup, b.lhs) orelse break :blk null;
                    _ = widthOfExpr(lookup, b.rhs) orelse break :blk null;
                    break :blk x;
                },
                // A clear sign bit in EITHER operand clears it in the result,
                // and the narrower bound is the one that survives.
                .band => {
                    const x = widthOfExpr(lookup, b.lhs);
                    const y = widthOfExpr(lookup, b.rhs);
                    if (x == null) break :blk y;
                    if (y == null) break :blk x;
                    break :blk @min(x.?, y.?);
                },
                .bor, .bxor => break :blk nonNegJoin(widthOfExpr(lookup, b.lhs), widthOfExpr(lookup, b.rhs)),
                // LOGICAL shift right (`lsr`). A shift of AT LEAST ONE clears
                // the top bit whatever it held, which is the only case where
                // this rule proves anything the operand did not already have —
                // and `x >> 0` is the IDENTITY, so a negative operand stays
                // negative through it. Written without that case split first,
                // and the case split is the whole soundness of the arm.
                .rshift => {
                    const x = widthOfExpr(lookup, b.lhs);
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
                    const x = widthOfExpr(lookup, b.lhs) orelse break :blk null;
                    const k = ast.intLiteralValue(b.rhs) orelse break :blk null;
                    if (k < 0 or k > 63) break :blk null;
                    break :blk x + @as(u8, @intCast(k));
                },
                // A comparison answers 0 or 1.
                .eq, .neq, .lt, .gt, .leq, .geq => break :blk 1,
                else => break :blk null,
            }
        },
        else => null,
    };
    const width = w orelse return null;
    if (width > 63) return null;
    return width;
}

fn envLookupOf(ctx: *const anyopaque, name: []const u8) ?u8 {
    const widths: *const NonNegEnv = @ptrCast(@alignCast(ctx));
    return widths.get(name);
}

/// The producer's own face of `widthOfExpr`, over the lattice it is settling.
fn nonNegWidth(widths: *const NonNegEnv, e: *const ast.Expr) ?u8 {
    return widthOfExpr(.{ .ctx = widths, .of = envLookupOf }, e);
}

/// One pass of the transfer function over every assignment in `blk`.
/// `changed` is set when a name's width grew. `unmodeled` is set when the body
/// contains a construct this pass does not model, which discards everything.
fn nonNegScanBlock(
    alloc: std.mem.Allocator,
    widths: *NonNegEnv,
    blk: *const ast.Block,
    changed: *bool,
    unmodeled: *bool,
) std.mem.Allocator.Error!void {
    for (blk.stmts) |st| switch (st) {
        .local_decl => |d| {
            if (d.names.len != d.inits.len) {
                for (d.names) |n| try nonNegRaise(alloc, widths, n.ident, changed);
                continue;
            }
            for (d.names, d.inits) |n, init| try nonNegObserve(alloc, widths, n.ident, nonNegWidth(widths, init), changed);
        },
        .assign => |a| {
            if (a.targets.len != a.values.len) {
                for (a.targets) |t| if (t.* == .name) try nonNegRaise(alloc, widths, t.name.ident, changed);
                continue;
            }
            for (a.targets, a.values) |t, v| {
                if (t.* != .name) continue;
                try nonNegObserve(alloc, widths, t.name.ident, nonNegWidth(widths, v), changed);
            }
        },
        // A name bound by any of these takes a value this pass does not model.
        .global_decl => |d| for (d.names) |n| try nonNegRaise(alloc, widths, n.ident, changed),
        .num_for => |f| {
            try nonNegRaise(alloc, widths, f.var_name, changed);
            try nonNegScanBlock(alloc, widths, &f.body, changed, unmodeled);
        },
        .gen_for => |f| {
            for (f.vars) |v| try nonNegRaise(alloc, widths, v, changed);
            try nonNegScanBlock(alloc, widths, &f.body, changed, unmodeled);
        },
        .while_loop => |w| try nonNegScanBlock(alloc, widths, &w.body, changed, unmodeled),
        .repeat_loop => |r| try nonNegScanBlock(alloc, widths, &r.body, changed, unmodeled),
        .do_block => |d| try nonNegScanBlock(alloc, widths, &d.body, changed, unmodeled),
        .if_stmt => |f| {
            if (f.binding) |b| try nonNegRaise(alloc, widths, b.name, changed);
            try nonNegScanBlock(alloc, widths, &f.then, changed, unmodeled);
            for (f.elseifs) |ei| try nonNegScanBlock(alloc, widths, &ei.body, changed, unmodeled);
            if (f.else_body) |eb| try nonNegScanBlock(alloc, widths, &eb, changed, unmodeled);
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
        try nonNegScanBlock(alloc, &widths, body, &changed, &unmodeled);
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
pub fn widthsOf(
    alloc: std.mem.Allocator,
    fb: *const ast.FuncBody,
    outer: []const []const u8,
) !Env {
    const params = try alloc.alloc([]const u8, fb.params.len);
    defer alloc.free(params);
    for (fb.params, 0..) |par, i| params[i] = par.name;
    return nonNegativeNames(alloc, &fb.body, params, outer);
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
