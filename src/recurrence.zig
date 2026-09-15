//! Symbolic recurrence closure — ABOLISHING A LOOP, by two lawful routes.
//!
//! The question this file asks is NOT "can I close this sum?". It is
//!
//!     WHAT IS THE MINIMUM STATE SUFFICIENT TO DISTINGUISH ALL FUTURE
//!     DEMANDED OBSERVATIONS?
//!
//! and both alternatives below are answers to it. Two states are equivalent
//! when no remaining demanded observation can tell them apart; execute over
//! S/~ rather than S.
//!
//!   A. OPERATOR POWERING (§ below, and most of this file). Quotients the state
//!      ALGEBRAICALLY: the minimal monomial basis the body closes over. Assumes
//!      nothing but O1-O8, answers all 64 bits.
//!   B. OBSERVATION ORBIT (see `closeWhileByOrbit`). Quotients the state by the
//!      observation's WIDTH: h(x) = x mod 2^k, so h(f(x)) = g(h(x)) and a
//!      finite state space is eventually periodic. Assumes O9, a demand fact
//!      the CALLER supplies, and answers only the demanded bits.
//!
//! A is tried first, always — see `closeRelationBodyObserved` for why the
//! ranking is by what an alternative ASSUMES rather than what it costs.
//!
//! THE CONSEQUENCE WORTH STATING UP FRONT: a serial dependence chain is only
//! the floor of executing that chain LITERALLY. B closes a 1e9-step
//! multiply/xor chain — unvectorizable, unrollable to no purpose, every step
//! dependent on the last — to a constant, because the observation does not
//! distinguish the states the chain passes through. And B closes a FACTORIAL,
//! which has no closed form at all.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! ALTERNATIVE A — WHY THIS IS NOT A PILE OF RECOGNIZERS
//! ════════════════════════════════════════════════════════════════════════════
//!
//! There is exactly ONE mechanism here and it is a SEARCH:
//!
//!     1. Read the body as a parallel substitution  v <- P_v(state)  where each
//!        P_v is a polynomial over the loop-carried variables.
//!     2. SEARCH for a finite monomial basis closed under that substitution, by
//!        fixpoint: start from {1, v_1 .. v_m}; for each basis monomial compute
//!        its image; every monomial the image mentions joins the basis; repeat.
//!     3. If the fixpoint converges inside the bound, the body IS a matrix M
//!        over the ring, by construction. Raise it to the trip count.
//!
//! Nothing in that pipeline asks "is this a sum?". The families a conventional
//! compiler names one at a time all fall out of step 2 as different fixpoints:
//!
//!     s += i                  basis {s, i, 1}          — "arithmetic series"
//!     s += i*i                basis {s, i², i, 1}      — "polynomial series"
//!     x = 3*x + 7             basis {x, 1}             — "affine / LCG fold"
//!     p *= r ; s += p         basis {s, p, 1}          — "geometric sum"
//!     p *= r ; s += i*p       basis {s, i·p, p, 1}     — "arithmetico-geometric"
//!     a, b = b, a+b           basis {a, b, 1}          — "order-k linear"
//!     s *= i                  basis DIVERGES           — factorial, no closed form
//!
//! The last row is the point. The engine is not TOLD that a factorial has no
//! closed form; the basis search fails to converge and the loop is refused. A
//! recognizer pile would have to be told, and would be silent about every shape
//! nobody thought to name. `docs/recurrence-closure.md` §2 works these through.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE PROOF OBLIGATION — designed before the derivation, and enforced by code
//! ════════════════════════════════════════════════════════════════════════════
//!
//! Substituting a closed form for a loop claims: for every initial state, the
//! two agree on (a) every live-out value, (b) observable effects and their
//! order, (c) termination, (d) traps. Nine obligations discharge that — O1-O8
//! for both alternatives, O9 for B alone — each with the function that enforces
//! it:
//!
//!   O1 TRIP COUNT EXACTNESS — T equals the body's execution count for every
//!      value of the guard's free names. Derived in i128 so the derivation
//!      itself cannot wrap, and `max(0, ...)` is NOT optional: `while n > 0`
//!      never enters for negative n. Five wrong answers shipped in six lines of
//!      `lib/bit.id` on exactly that. → `tripCount`
//!
//!   O2 THE INDUCTION VARIABLE MAY NOT WRAP — the guard reads the RING value of
//!      `i`. If `i` crosses 2^63 mid-loop the comparison flips and O1's formula
//!      is not the trip count; the real loop stops early. Refused, not
//!      approximated. This is a SEPARATE obligation from O3 and it is the one
//!      that looks redundant and is not. → `tripCount`, `ivStaysInRange`
//!
//!   O3 THE RING — MEASURED, not assumed. i64 arithmetic here is wrapping
//!      two's complement mod 2^64 with no trap, verified on BOTH paths at
//!      `docs/recurrence-closure.md` §3 (fold path and live-loop path both
//!      reproduce the wrapped byte exactly). Reduction mod 2^64 is a ring
//!      homomorphism from Z, so a closed form built from + and * only is exact.
//!      **Binary powering of M uses + and * only — it never divides.** That is
//!      what makes this obligation dischargeable rather than hard: the
//!      schoolbook closed forms that DO divide (n(n+1)/2, Faulhaber) are never
//!      formed. → `matPow`, and `ringGuard` refuses any body needing / % >> & | ^
//!
//!   O4 TRAP AND EFFECT FREEDOM — a body that can die on iteration j < T must
//!      not be evaluated past j. `graph_query.zig:338` says the effect fact
//!      "proves NOTHING about termination, traps, or arithmetic domain", so the
//!      effect fact CANNOT discharge this and no other fact in the compiler can
//!      either. Discharged instead by ADMITTING ONLY A TRAP-FREE GRAMMAR: int
//!      literals, loop-carried names, + - * and unary minus. A subscript is
//!      trappable — measured, `t[i]` out of range aborts (exit 134) — and is
//!      not in the grammar. A call is not in the grammar. → `polyOfExpr`
//!
//!   O5 TERMINATION — proven by construction, never assumed: a monotone IV with
//!      a constant nonzero step crossing a loop-invariant bound. A guard this
//!      cannot prove monotone is refused, so a non-terminating loop is never
//!      replaced by a value. → `analyzeGuard`
//!
//!   O6 LIVE-OUT COMPLETENESS — every name the body assigns gets its closed
//!      form, not just the accumulator, and the IV's exit value is one of them.
//!      A name assigned by a rule outside the grammar refuses the whole loop
//!      rather than being left stale. → `collectUpdates`
//!
//!   O7 CONTROL FLOW — `break`, `continue`, `return`, `goto`, a nested loop or
//!      an `if` inside the body all break the trip-count derivation. Refused.
//!      → `collectUpdates`
//!
//!   O8 GUARD INVARIANCE — a bound assigned inside the body is not a bound.
//!      → `analyzeGuard` (the bound must be a constant of the entry bindings)
//!
//! FAILS CLOSED EVERYWHERE. Every path returns null on the first thing it
//! cannot prove, and null means "leave the loop alone".
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT IS BUILT HERE AND WHAT IS NOT
//! ════════════════════════════════════════════════════════════════════════════
//!
//! BUILT: the trip count is a compile-time constant. Then M^T is computed at
//! compile time by binary powering and the live-outs are constants — Tier 0,
//! the computation is ABOLISHED rather than made faster. This removes the
//! `comptime.zig` step budget for exactly the class that closes: the budget
//! stops a 1e9-iteration loop at 16,665 steps, and a closed form takes zero
//! steps, so the cliff is an artefact of HOW the fold is computed.
//!
//! NOT BUILT: a SYMBOLIC trip count. It needs the closed form EMITTED as code,
//! which is `dnir_lower.zig`, and the O(1) form for the unitriangular case
//! needs C(T,k) mod 2^64 for a runtime T — which needs the division-free 2-adic
//! construction, because 2 is not invertible mod 2^64. That construction is
//! already written and differentially tested IN THIS PROJECT, in Idol, at
//! `native.id:binom`. `docs/recurrence-closure.md` §6 states the design and the
//! exact patch. Do not read this file as covering it: `series.id`'s bound comes
//! from the environment and is NOT closed by what is built here.

const std = @import("std");
const ast = @import("ast.zig");

// ── Bounds. Every one of these makes the search TERMINATE; none is a tuning
// knob. Exceeding any of them is a refusal, never a truncation. ──────────────

/// Loop-carried variables admitted. The matrix is (basis)² per multiply and the
/// basis grows combinatorially in this, so it is the real cost control.
pub const max_vars: usize = 6;
/// Per-variable exponent, and total monomial degree. A body whose basis needs a
/// higher degree diverges in practice (see `s *= i`), so this doubles as the
/// divergence detector.
pub const max_degree: usize = 8;
/// Monomials in the closed basis. 24 covers degree-8 polynomial sums and
/// order-8 linear recurrences with room; past it the powering cost is real.
pub const max_basis: usize = 24;
/// Terms in one intermediate polynomial.
pub const max_terms: usize = 48;

/// Exponent vector over the loop-carried variables. The all-zero monomial is
/// the constant 1 and it is what makes an AFFINE map linear.
const Mono = [max_vars]u8;

const zero_mono: Mono = @splat(0);

fn monoDegree(m: Mono) usize {
    var d: usize = 0;
    for (m) |e| d += e;
    return d;
}

fn monoMul(a: Mono, b: Mono) ?Mono {
    var out: Mono = undefined;
    var total: usize = 0;
    for (0..max_vars) |i| {
        const e = @as(usize, a[i]) + @as(usize, b[i]);
        if (e > max_degree) return null;
        out[i] = @intCast(e);
        total += e;
    }
    if (total > max_degree) return null;
    return out;
}

const Term = struct { coeff: u64, mono: Mono };

/// A polynomial over the loop-carried variables with coefficients in the RING
/// (Z/2^64). Every coefficient operation below is `%`-suffixed wrapping
/// arithmetic — O3 is discharged by there being no other kind in this file.
const Poly = struct {
    terms: [max_terms]Term = undefined,
    len: usize = 0,

    fn zero() Poly {
        return .{};
    }

    fn constant(c: u64) Poly {
        var p = Poly.zero();
        if (c != 0) {
            p.terms[0] = .{ .coeff = c, .mono = zero_mono };
            p.len = 1;
        }
        return p;
    }

    fn variable(index: usize) Poly {
        var m = zero_mono;
        m[index] = 1;
        var p = Poly.zero();
        p.terms[0] = .{ .coeff = 1, .mono = m };
        p.len = 1;
        return p;
    }

    fn addTerm(self: *Poly, coeff: u64, mono: Mono) ?void {
        if (coeff == 0) return;
        for (0..self.len) |i| {
            if (std.mem.eql(u8, &self.terms[i].mono, &mono)) {
                self.terms[i].coeff = self.terms[i].coeff +% coeff;
                if (self.terms[i].coeff == 0) {
                    // Drop a term that cancelled. Keeping a zero would inflate
                    // the basis with monomials the body does not actually reach.
                    self.terms[i] = self.terms[self.len - 1];
                    self.len -= 1;
                }
                return;
            }
        }
        if (self.len == max_terms) return null;
        self.terms[self.len] = .{ .coeff = coeff, .mono = mono };
        self.len += 1;
    }

    fn add(a: Poly, b: Poly) ?Poly {
        var out = a;
        for (0..b.len) |i| {
            out.addTerm(b.terms[i].coeff, b.terms[i].mono) orelse return null;
        }
        return out;
    }

    fn negate(a: Poly) Poly {
        var out = a;
        for (0..out.len) |i| out.terms[i].coeff = 0 -% out.terms[i].coeff;
        return out;
    }

    fn sub(a: Poly, b: Poly) ?Poly {
        return add(a, negate(b));
    }

    fn mul(a: Poly, b: Poly) ?Poly {
        var out = Poly.zero();
        for (0..a.len) |i| {
            for (0..b.len) |j| {
                const m = monoMul(a.terms[i].mono, b.terms[j].mono) orelse return null;
                out.addTerm(a.terms[i].coeff *% b.terms[j].coeff, m) orelse return null;
            }
        }
        return out;
    }

    /// Degree-0 value, or null when the polynomial is not constant. This is how
    /// O8 (guard invariance) and the entry bindings are checked: "is a constant"
    /// is a property of the polynomial, never of the source spelling.
    fn asConstant(self: Poly) ?u64 {
        if (self.len == 0) return 0;
        if (self.len != 1) return null;
        if (monoDegree(self.terms[0].mono) != 0) return null;
        return self.terms[0].coeff;
    }
};

// ── The loop-carried state ───────────────────────────────────────────────────

const State = struct {
    names: [max_vars][]const u8 = undefined,
    len: usize = 0,

    fn indexOf(self: State, name: []const u8) ?usize {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return i;
        }
        return null;
    }

    fn intern(self: *State, name: []const u8) ?usize {
        if (self.indexOf(name)) |i| return i;
        if (self.len == max_vars) return null;
        self.names[self.len] = name;
        self.len += 1;
        return self.len - 1;
    }
};

/// Names bound to ring constants on entry to the region. Loop-invariant by
/// construction: the driver only ever adds a name whose initializer it folded,
/// and `collectUpdates` refuses a loop that assigns any name it did not intern
/// as loop-carried.
pub const Bindings = struct {
    names: [32][]const u8 = undefined,
    vals: [32]u64 = undefined,
    len: usize = 0,

    pub fn get(self: Bindings, name: []const u8) ?u64 {
        // Last write wins — `s = 0` then `s = 5` must read 5.
        var i = self.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.names[i], name)) return self.vals[i];
        }
        return null;
    }

    pub fn put(self: *Bindings, name: []const u8, val: u64) bool {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) {
                self.vals[i] = val;
                return true;
            }
        }
        if (self.len == self.names.len) return false;
        self.names[self.len] = name;
        self.vals[self.len] = val;
        self.len += 1;
        return true;
    }
};

// ── O3/O4: THE ADMITTED GRAMMAR ──────────────────────────────────────────────

/// Read an expression as a polynomial over the loop-carried state.
///
/// THIS FUNCTION IS THE TRAP-FREEDOM PROOF (O4). It admits int literals, names,
/// `+ - *`, unary minus and nothing else — so a body that reaches this far
/// CANNOT subscript (measured trappable: out-of-range `t[i]` aborts), cannot
/// call, cannot divide (`/ %` are excluded because the ring makes them
/// non-homomorphic, not because they are hard), cannot touch memory and cannot
/// observe anything. There is no separate "is it trap free" query to get wrong
/// and no fact to look up that does not exist.
///
/// `state` is the loop-carried variable set; a name in `binds` is a ring
/// constant. A name in NEITHER is unbound and refuses.
fn polyOfExpr(expr: *const ast.Expr, state: *const State, binds: Bindings) ?Poly {
    switch (expr.*) {
        .int_lit => |lit| return Poly.constant(@bitCast(lit.val)),
        .name => |n| {
            if (state.indexOf(n.ident)) |i| return Poly.variable(i);
            if (binds.get(n.ident)) |v| return Poly.constant(v);
            return null;
        },
        .unop => |u| switch (u.op) {
            .neg => {
                const inner = polyOfExpr(u.operand, state, binds) orelse return null;
                return inner.negate();
            },
            // `not` / `#` / `~` / `##` are not ring operations.
            else => return null,
        },
        .binop => |b| {
            const lhs = polyOfExpr(b.lhs, state, binds) orelse return null;
            const rhs = polyOfExpr(b.rhs, state, binds) orelse return null;
            return switch (b.op) {
                .add => Poly.add(lhs, rhs),
                .sub => Poly.sub(lhs, rhs),
                .mul => Poly.mul(lhs, rhs),
                // CONSTANT division folds exactly (see divConstFold): both
                // sides already reduced to ring constants, so the division is
                // evaluated in integers, never through the ring. A division
                // that would trap (by zero, or minInt / -1) declines, keeping
                // the original trap behavior (O4).
                .div => divConstFold(lhs, rhs),
                // EXPLICITLY REFUSED, and the reason is O3 rather than effort:
                // `/` with a non-constant side, `%`, `>>` are floor operations
                // that do NOT commute with reduction mod 2^64, so no closed
                // form over the ring can reproduce them; `& | ^ <<` do commute
                // but are not ring polynomial operations, so the basis search
                // has nothing to search over. `pow` with a variable exponent
                // is not polynomial.
                else => null,
            };
        },
        else => return null,
    }
}

/// The u64 bit-pattern of the polynomial's value when it is a constant (no
/// variable mentions), null otherwise. A zero polynomial (len 0) is the
/// constant 0.
fn constantValue(p: Poly) ?u64 {
    if (p.len == 0) return 0;
    if (p.len == 1 and std.mem.eql(u8, &p.terms[0].mono, &zero_mono)) {
        return p.terms[0].coeff;
    }
    return null;
}

/// Constant-only division, evaluated with the settled language law
/// (floored integer division, law.numeric.floor): floored division, declining
/// (null) on division by zero and on minInt / -1. The decline keeps a body
/// that would trap out of the closed form, so the loop keeps its original
/// behavior (O4); a division that evaluates is trap-free by construction.
/// Non-constant division stays refused: it does not commute with reduction
/// mod 2^64 (O3).
fn divConstFold(lhs: Poly, rhs: Poly) ?Poly {
    const lc = constantValue(lhs) orelse return null;
    const rc = constantValue(rhs) orelse return null;
    const l: i64 = @bitCast(lc);
    const r: i64 = @bitCast(rc);
    if (r == 0 or (r == -1 and l == std.math.minInt(i64))) return null;
    return Poly.constant(@bitCast(@divFloor(l, r)));
}

// ── O5/O8: the guard ─────────────────────────────────────────────────────────

const Guard = struct {
    /// Loop-carried index of the induction variable.
    iv: usize,
    /// Ring-independent bound, as a signed integer.
    bound: i64,
    /// True when the loop continues while `iv <= bound` (after normalization);
    /// false when it continues while `iv >= bound`.
    ascending: bool,
    /// `<=`/`>=` (inclusive) versus `<`/`>` (exclusive).
    inclusive: bool,
};

/// O5 + O8. The guard must be a monotone comparison of ONE loop-carried name
/// against a loop-invariant constant. `i != n` is deliberately absent: it
/// terminates only when `n - i0` is a positive multiple of the step, which is a
/// divisibility side condition, and a loop that fails it must HANG. Admitting
/// it would be the one refusal whose cost is an infinite loop turned into a
/// wrong answer.
fn analyzeGuard(cond: *const ast.Expr, state: *const State, binds: Bindings) ?Guard {
    const b = switch (cond.*) {
        .binop => |x| x,
        else => return null,
    };
    const lhs = polyOfExpr(b.lhs, state, binds) orelse return null;
    const rhs = polyOfExpr(b.rhs, state, binds) orelse return null;

    // Exactly one side must be a bare loop-carried variable and the other a
    // constant. `2*i <= n` is refused: the trip count is then a division and
    // the IV-range obligation changes shape.
    const lhs_var = bareVariable(lhs);
    const rhs_var = bareVariable(rhs);
    var iv: usize = undefined;
    var bound_ring: u64 = undefined;
    var op = b.op;
    if (lhs_var != null and rhs_var == null) {
        iv = lhs_var.?;
        bound_ring = rhs.asConstant() orelse return null;
    } else if (rhs_var != null and lhs_var == null) {
        iv = rhs_var.?;
        bound_ring = lhs.asConstant() orelse return null;
        // Normalize `n >= i` to `i <= n`.
        op = switch (op) {
            .lt => .gt,
            .gt => .lt,
            .leq => .geq,
            .geq => .leq,
            else => return null,
        };
    } else return null;

    return switch (op) {
        .leq => .{ .iv = iv, .bound = @bitCast(bound_ring), .ascending = true, .inclusive = true },
        .lt => .{ .iv = iv, .bound = @bitCast(bound_ring), .ascending = true, .inclusive = false },
        .geq => .{ .iv = iv, .bound = @bitCast(bound_ring), .ascending = false, .inclusive = true },
        .gt => .{ .iv = iv, .bound = @bitCast(bound_ring), .ascending = false, .inclusive = false },
        else => null,
    };
}

fn bareVariable(p: Poly) ?usize {
    if (p.len != 1) return null;
    if (p.terms[0].coeff != 1) return null;
    if (monoDegree(p.terms[0].mono) != 1) return null;
    for (0..max_vars) |i| {
        if (p.terms[0].mono[i] == 1) return i;
    }
    return null;
}

// ── O1/O2: the trip count ────────────────────────────────────────────────────

/// Exact execution count of the body, or null when it cannot be proven.
///
/// EVERYTHING HERE IS i128 SO THE DERIVATION CANNOT ITSELF WRAP. A trip count
/// computed in i64 can overflow while deriving how far an i64 travels, which is
/// the failure that would make O2 unenforceable by the very code enforcing it.
///
/// O1's `max(0, ...)`: a guard false on entry runs the body ZERO times. This is
/// the `lib/bit.id` family — `while n > 0` over a negative n — and it is why
/// the zero-trip case is the FIRST branch and not a corner.
///
/// O2: the IV visits `start, start+step, ..., start+T*step` (the last is the
/// exit value, which is live-out). Every one must be representable in i64 or
/// the real loop's guard sees a wrapped value and stops somewhere this formula
/// does not predict. Monotonicity means checking the endpoint suffices.
fn tripCount(guard: Guard, start: i64, step: i64) ?u64 {
    if (step == 0) return null; // O5: no progress, no termination proof.
    // O5: the step must move the IV TOWARD the bound.
    if (guard.ascending and step < 0) return null;
    if (!guard.ascending and step > 0) return null;

    const s: i128 = start;
    const b: i128 = guard.bound;
    const d: i128 = step;

    // O1: zero-trip test, in the guard's own sense.
    const entered = if (guard.ascending)
        (if (guard.inclusive) s <= b else s < b)
    else
        (if (guard.inclusive) s >= b else s > b);
    if (!entered) return 0;

    // Last value of the IV that still satisfies the guard.
    const limit: i128 = if (guard.ascending)
        (if (guard.inclusive) b else b - 1)
    else
        (if (guard.inclusive) b else b + 1);

    // Number of whole steps from `s` to `limit`, inclusive of both ends.
    const span: i128 = if (guard.ascending) limit - s else s - limit;
    const stride: i128 = if (guard.ascending) d else -d;
    std.debug.assert(span >= 0 and stride > 0);
    const t: i128 = @divFloor(span, stride) + 1;
    if (t < 0) return null;

    // O2: the whole trajectory INCLUDING the exit value must stay in i64.
    const exit_value: i128 = s + t * d;
    if (!ivStaysInRange(exit_value)) return null;
    if (!ivStaysInRange(s + (t - 1) * d)) return null;

    if (t > std.math.maxInt(u64)) return null;
    return @intCast(t);
}

fn ivStaysInRange(v: i128) bool {
    return v >= std.math.minInt(i64) and v <= std.math.maxInt(i64);
}

/// THE ONE TRIP-COUNT PROOF, in the shape `src/demand.zig` needs it.
///
/// Two lanes derived a trip count independently and both landed in this tree.
/// This is the seam that makes them one derivation: `demand` recognises the
/// counter, the bound and the step out of the AST and applies its own
/// structural guards, then asks THIS function the arithmetic question. Nothing
/// about wrapping, overshoot or direction is decided twice.
///
/// `demand` proves termination in order to DELETE a loop, so it never learns
/// where the counter starts — the question it must answer is "does this halt
/// with the induction variable staying in i64, from EVERY i64 start?".
///
/// That reduces to ONE call to `tripCount`, at the worst start. The IV is
/// monotone, so the largest magnitude it ever holds is its EXIT value, and the
/// exit value is largest when the loop is entered as late as the guard allows —
/// at the last value the guard still admits, where the body runs exactly once
/// and the IV steps straight out. A start below that exits no further; a start
/// past it runs zero times. So checking that single start is not a heuristic
/// bound on the answer, it IS the answer.
///
/// This is strictly more permissive than the sufficient condition it replaces
/// (`|bound| <= maxInt - step`), and the gap is real rather than theoretical:
/// see the differential test below, which walks the boundary and finds an
/// EXCLUSIVE bound at the i64 edge that terminates cleanly and was refused.
pub fn terminatesForAnyStart(bound: i64, ascending: bool, inclusive: bool, step: i64) bool {
    // O5 FIRST AND UNCONDITIONALLY, exactly as `tripCount` applies it.
    //
    // A vacuous guard — `while i < minInt`, which no i64 satisfies — halts from
    // every start whatever the step is, so returning true here would be *true*.
    // It is still refused, because this function's contract is "the kernel's
    // answer at the worst start" and the kernel refuses a zero or wrong-way
    // step outright. A wrapper that is right where its kernel is silent is a
    // second opinion, which is the thing this seam exists to abolish.
    if (step == 0) return false;
    if (ascending and step < 0) return false;
    if (!ascending and step > 0) return false;

    // The last value of the IV the guard still admits, in i128 because an
    // exclusive bound at the i64 edge steps outside the type to name it.
    const last: i128 = if (ascending)
        (if (inclusive) @as(i128, bound) else @as(i128, bound) - 1)
    else
        (if (inclusive) @as(i128, bound) else @as(i128, bound) + 1);

    // No i64 satisfies the guard at all — `while i < minInt`. The body runs
    // zero times from every start, which terminates, whatever the step is.
    if (!ivStaysInRange(last)) return true;

    const guard = Guard{
        .iv = 0,
        .bound = bound,
        .ascending = ascending,
        .inclusive = inclusive,
    };
    return tripCount(guard, @intCast(last), step) != null;
}

// ── O6/O7: the body as a parallel substitution ───────────────────────────────

const Updates = struct {
    /// `cur[v]` is v's value after one full pass, as a polynomial in the state
    /// AT LOOP HEAD. Built by sequential substitution, so `s = s + i; i = i + 1`
    /// and `i = i + 1; s = s + i` produce different (and correct) maps.
    cur: [max_vars]Poly = undefined,
};

/// O6 + O7. Walk the body in order; every statement must be a single-target
/// assignment to a loop-carried name whose value is in the admitted grammar.
/// A `break`, a nested loop, an `if`, a call statement — anything else — is a
/// refusal of the WHOLE loop, so nothing is ever left half-closed.
fn collectUpdates(body: *const ast.Block, state: *State, binds: Bindings) ?Updates {
    // First pass: intern every assigned name as loop-carried. Doing this before
    // reading any right-hand side is what makes `a, b = b, a + b` work — `b` is
    // state on the right of `a`'s update even though its own update comes later.
    for (body.stmts) |st| {
        switch (st) {
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return null;
                const target = switch (a.targets[0].*) {
                    .name => |n| n.ident,
                    else => return null, // a field or index target is a PLACE, not a scalar
                };
                _ = state.intern(target) orelse return null;
            },
            .local_decl => |d| {
                // A fresh local declared INSIDE the body is loop-carried only if
                // the body also reads it before writing; refusing is simpler and
                // costs a shape nothing in the corpus uses.
                _ = d;
                return null;
            },
            else => return null,
        }
    }
    if (body.tail_expr != null) return null;

    var up = Updates{};
    for (0..state.len) |i| up.cur[i] = Poly.variable(i);

    for (body.stmts) |st| {
        const a = st.assign;
        const target = a.targets[0].name.ident;
        const slot = state.indexOf(target).?;
        // Substitute the CURRENT map into the right-hand side: `polyOfExpr`
        // reads names as head-state variables, then `substitute` rewrites those
        // into the values they hold at this point in the pass.
        const raw = polyOfExpr(a.values[0], state, binds) orelse return null;
        up.cur[slot] = substitute(raw, up) orelse return null;
    }
    return up;
}

/// Replace each variable in `p` by its current update polynomial.
fn substitute(p: Poly, up: Updates) ?Poly {
    var out = Poly.zero();
    for (0..p.len) |i| {
        var term = Poly.constant(p.terms[i].coeff);
        for (0..max_vars) |v| {
            var e: u8 = 0;
            while (e < p.terms[i].mono[v]) : (e += 1) {
                term = Poly.mul(term, up.cur[v]) orelse return null;
            }
        }
        out = Poly.add(out, term) orelse return null;
    }
    return out;
}

// ── THE SEARCH: a monomial basis closed under the body's substitution ────────

const Basis = struct {
    monos: [max_basis]Mono = undefined,
    len: usize = 0,

    fn indexOf(self: Basis, m: Mono) ?usize {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, &self.monos[i], &m)) return i;
        }
        return null;
    }

    fn intern(self: *Basis, m: Mono) ?usize {
        if (self.indexOf(m)) |i| return i;
        if (self.len == max_basis) return null;
        self.monos[self.len] = m;
        self.len += 1;
        return self.len - 1;
    }
};

/// Image of a basis monomial under one pass: `Π_v (update_v)^{e_v}`.
fn imageOf(m: Mono, up: Updates) ?Poly {
    var out = Poly.constant(1);
    for (0..max_vars) |v| {
        var e: u8 = 0;
        while (e < m[v]) : (e += 1) {
            out = Poly.mul(out, up.cur[v]) orelse return null;
        }
    }
    return out;
}

/// THE SEARCH ITSELF. Fixpoint over "the image of a basis monomial mentions
/// monomials that must also be in the basis". Converges exactly when the body
/// is a linear operator on SOME finite monomial basis — which is the real
/// definition of "this loop has a closed form", and is strictly larger than any
/// list of named shapes. Diverges (and refuses) on `s *= i`, correctly.
///
/// `max_basis` and `max_degree` bound the search. They are the reason it always
/// terminates, and exceeding them is a refusal.
fn closeBasis(state: *const State, up: Updates) ?Basis {
    var basis = Basis{};
    // The constant monomial FIRST: it is what turns an affine map into a linear
    // one, and every image needs it available.
    _ = basis.intern(zero_mono) orelse return null;
    for (0..state.len) |i| {
        var m = zero_mono;
        m[i] = 1;
        _ = basis.intern(m) orelse return null;
    }

    var cursor: usize = 0;
    while (cursor < basis.len) {
        const image = imageOf(basis.monos[cursor], up) orelse return null;
        for (0..image.len) |t| {
            _ = basis.intern(image.terms[t].mono) orelse return null;
        }
        cursor += 1;
    }
    return basis;
}

// ── The matrix, and the powering that never divides ──────────────────────────

const Matrix = struct {
    n: usize,
    /// Row-major, `n <= max_basis`.
    a: [max_basis * max_basis]u64 = @splat(0),

    fn at(self: *const Matrix, r: usize, c: usize) u64 {
        return self.a[r * self.n + c];
    }
    fn set(self: *Matrix, r: usize, c: usize, v: u64) void {
        self.a[r * self.n + c] = v;
    }
    fn identity(n: usize) Matrix {
        var m = Matrix{ .n = n };
        for (0..n) |i| m.set(i, i, 1);
        return m;
    }
    fn mul(x: Matrix, y: Matrix) Matrix {
        var out = Matrix{ .n = x.n };
        for (0..x.n) |i| {
            for (0..x.n) |k| {
                const xv = x.at(i, k);
                if (xv == 0) continue;
                for (0..x.n) |j| {
                    out.a[i * x.n + j] = out.a[i * x.n + j] +% xv *% y.at(k, j);
                }
            }
        }
        return out;
    }
};

/// O3 IS DISCHARGED HERE, AND BY OMISSION. Binary powering uses `+%` and `*%`
/// and NOTHING ELSE. Z/2^64 is a ring under exactly those two, reduction from Z
/// is a homomorphism, and therefore `M^T` computed in wrapped u64 is EQUAL to
/// the exact integer `M^T` reduced mod 2^64 — for every T, with no side
/// condition about overflow, because overflow is the semantics rather than an
/// error condition.
///
/// This is why the hard half of the soundness obligation evaporates: the
/// schoolbook closed forms divide (`n(n+1)/2`, Faulhaber's `1/(k+1)`) and 2 is
/// not invertible mod 2^64, but binary powering never forms them. The division
/// problem is real and it belongs to the SYMBOLIC-T realization, not to this one
/// — see the module header and `docs/recurrence-closure.md` §6.
fn matPow(m: Matrix, t: u64) Matrix {
    var result = Matrix.identity(m.n);
    var base = m;
    var e = t;
    while (e > 0) {
        if (e & 1 == 1) result = Matrix.mul(result, base);
        base = Matrix.mul(base, base);
        e >>= 1;
    }
    return result;
}

// ── The public face ──────────────────────────────────────────────────────────

pub const Closed = struct {
    /// Final ring value of each loop-carried name, indexed as in `names`.
    values: [max_vars]u64 = undefined,
    names: [max_vars][]const u8 = undefined,
    len: usize = 0,
    /// Trip count actually derived — reported so a caller (and a gate) can
    /// check it against a brute-force run at small N.
    trips: u64 = 0,
    /// Size of the closed basis. 3 for a plain sum, 4 for a square sum. Exposed
    /// because it is the honest measure of how much structure the SEARCH found.
    basis: usize = 0,

    /// Number of low bits of every value above that are PROVEN equal to the
    /// loop's. 64 when the closure is exact; `obs.bits` when the loop was closed
    /// in a quotient and only the demanded bits are claimed.
    valid_bits: u7 = 64,
    /// Which lawful alternative produced this. Reported so a gate can tell a
    /// closure that assumed an observation fact from one that assumed nothing.
    via: enum { operator_power, observation_orbit } = .operator_power,

    pub fn get(self: Closed, name: []const u8) ?u64 {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return self.values[i];
        }
        return null;
    }
};

/// WHAT AN OBSERVER OF THIS RELATION'S RESULT CAN DISTINGUISH.
///
/// THIS MODULE NEVER INFERS IT. The caller supplies it as a fact and owns O9
/// below; the default is "everything", which disables the quotient alternative
/// entirely and leaves only the unconditionally-sound operator powering.
pub const Observation = struct {
    /// Low bits any observer can distinguish. 64 = fully observed.
    bits: u7 = 64,

    /// O10 — **THE CONTRACTED STATE KEY.** Loop-carried names the caller has
    /// proven the CONTINUATION cannot distinguish (`projectionOfName` is
    /// `none`) and that no surviving slot's update reads. They are dropped
    /// from the ORBIT KEY, never from the walk: their updates still run and
    /// are still held to the trap-free grammar, so nothing about O4 moves.
    ///
    /// WHY IT IS WORTH A FIELD. The key decides when the orbit REPEATS, so a
    /// slot nobody can see is a slot that lengthens the cycle for free.
    /// MEASURED by `src/obseq.zig`, which computes this set for its own
    /// e-graph and until now could not hand it here — the two-accumulator
    /// fixture walks 768 states with the induction variable in the key and 192
    /// without, and the four-accumulator one 1792 against 896. Empty is
    /// verbatim today's behaviour: every assigned name is packed.
    ///
    /// §24 — THE FACT IS CHECKED, NOT TRUSTED. `closeWhileByOrbit` re-derives
    /// the closure condition from the body it is about to walk and refuses a
    /// drop this file cannot confirm, so a wrong set from any caller costs a
    /// closure and can never cost an answer.
    unobserved: []const []const u8 = &.{},

    /// §22-23 — **THE RELATION LAW SEAM**, opaque here for the same reason
    /// `demand_projection.zig`'s is: the producer side can be compiled, tested
    /// and deleted without this file knowing its name.
    ///
    /// The one question this file asks it: *what is the value of this call, in
    /// the ring, at these already-quotiented arguments?* A non-null answer is
    /// the caller asserting that the callee is a PURE mod-2^k ring
    /// homomorphism — which is the SAME admission `quotientEval` applies to
    /// `+ - * & | ^ ~` and nothing weaker. Null, and every call refuses
    /// exactly as it always has.
    call_ctx: ?*const anyopaque = null,
    call_value: ?*const fn (
        ctx: *const anyopaque,
        call: *const ast.Expr,
        args: []const i64,
    ) ?i64 = null,

    fn dropped(self: Observation, name: []const u8) bool {
        for (self.unobserved) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }
};

/// Arguments one admitted call may carry. Sized to `max_vars` for the same
/// reason the state is: a call in a quotiented loop body reads loop-carried
/// values, and there are no more of those than there are slots.
const max_call_args: usize = max_vars;

/// Steps of the orbit walk before the quotient alternative refuses.
///
/// DERIVED THE SAME WAY `comptime.fold_step_limit` IS, and deliberately of the
/// same order: that budget is 200,000 evaluator steps at a measured 60 ns/step
/// = 12 ms. An orbit step here is a handful of masked integer ops, far cheaper
/// than an AST evaluator step, so 1<<20 steps is well under the same 12 ms —
/// and it closes a loop of 1e9 trips where the evaluator budget stops at
/// 16,665. THE COMPARISON IS THE POINT: same compile-time cost, five orders of
/// magnitude more loop.
pub const max_orbit_steps: usize = 1 << 20;

// ════════════════════════════════════════════════════════════════════════════
// ALTERNATIVE B — TEMPORAL STATE QUOTIENTING
//
// "Two states are equivalent if no remaining demanded observation can
// distinguish them. Execute over S/~ rather than S."
//
// Operator powering (alternative A) is already a quotient — an ALGEBRAIC one.
// It replaces the state by the monomial basis the body closes over, which is
// the smallest polynomial-closed summary of the state that still determines the
// observation. That is why `closeBasis` is a fixpoint search and not a table of
// shapes: it is computing S/~ for the polynomial observation algebra.
//
// This alternative quotients on the OTHER axis — the observation's WIDTH.
//
//     h(x) = x mod 2^k     is a ring homomorphism for + - * and, being
//                          bit-local, also for & | ^ ~ and << by a constant.
//
// so `h(f(x)) = g(h(x))` with g = f computed in Z/2^k. If an observer can only
// distinguish k bits, maintaining h(x) through g is not an approximation of
// maintaining x through f — it is the SAME OBSERVATION, reached in a state
// space of 2^(k·m) elements instead of 2^(64·m).
//
// AND A FINITE STATE SPACE IS EVENTUALLY PERIODIC. The orbit of the entry state
// under g has a tail μ and a period λ with μ + λ ≤ |S|, so
//
//     g^T  =  g^(μ + (T − μ) mod λ)      for T ≥ μ
//
// which is computable by walking the orbit ONCE. No algebraic structure is
// required of the body at all — this closes bodies with xors, masks and shifts
// that alternative A refuses outright, and it closes them for ANY trip count.
//
// THIS IS THE CONCRETE FORM OF "A DEPENDENCE CHAIN IS NOT A FLOOR". A serial
// 1e9-step xor/multiply chain has a genuine 1e9-deep dependence chain and it is
// NOT the floor of the computation, because the observation does not
// distinguish the states the chain passes through.
//
// ─── O9, THE OBLIGATION THIS ALTERNATIVE ADDS AND A IS FREE OF ──────────────
//
//   O9 OBSERVATION WIDTH. The k-bit quotient is licensed ONLY by a fact that no
//      observer distinguishes results agreeing on the low k bits. `Observation`
//      carries that fact and this module never invents it. For the S0 subset
//      the fact is real and documented — "the only observable of the S0 subset
//      is the process exit code" — and measured: a `main` returning
//      500,000,500,000 exits 32, which is its low byte. But it holds for the
//      PROGRAM ENTRY, not for relations in general, so the call site owes:
//        (a) this relation is the entry, and
//        (b) nothing in the module applies it, so no caller reads the full
//            value.
//      A call site that cannot show both must leave `bits` at 64.
// ════════════════════════════════════════════════════════════════════════════

/// Evaluate one body statement list in the k-bit quotient.
///
/// A SECOND, WIDER GRAMMAR — and every operator in it is admitted BECAUSE it
/// commutes with `x mod 2^k`, never because it was convenient:
///
///     + - * unary-neg   ring homomorphism
///     & | ^ ~           bit-local: low k bits of the result depend only on the
///                       low k bits of the operands
///     << by a constant  (x << c) mod 2^k = ((x mod 2^k) << c) mod 2^k
///
/// and every operator NOT in it is excluded because it does not:
///
///     >>                reads bits ABOVE the low k, which the quotient discarded
///     / %               floor operations; no homomorphism to Z/2^k exists
///
/// Subscripts and calls stay out for O4 exactly as in alternative A: the
/// quotient changes what is OBSERVED, never whether the body can trap.
fn quotientStep(
    body: *const ast.Block,
    state: *const State,
    vals: *[max_vars]u64,
    mask: u64,
    binds: Bindings,
    obs: Observation,
) bool {
    for (body.stmts) |st| {
        const a = switch (st) {
            .assign => |x| x,
            else => return false,
        };
        if (a.targets.len != 1 or a.values.len != 1) return false;
        const target = switch (a.targets[0].*) {
            .name => |n| n.ident,
            else => return false,
        };
        // O10. A name that never entered the state is one the caller proved
        // unobserved and `internAssignedNames` proved trap-free; it has no
        // value to maintain and nothing reads it. Any OTHER unknown target is
        // still a refusal.
        const slot = state.indexOf(target) orelse {
            if (obs.dropped(target)) continue;
            return false;
        };
        const v = quotientEval(a.values[0], state, vals, mask, binds, obs) orelse return false;
        vals[slot] = v & mask;
    }
    return true;
}

fn quotientEval(
    expr: *const ast.Expr,
    state: *const State,
    vals: *const [max_vars]u64,
    mask: u64,
    binds: Bindings,
    obs: Observation,
) ?u64 {
    switch (expr.*) {
        .int_lit => |lit| return @as(u64, @bitCast(lit.val)) & mask,
        .name => |n| {
            if (state.indexOf(n.ident)) |i| return vals[i] & mask;
            if (binds.get(n.ident)) |v| return v & mask;
            return null;
        },

        // ── A CALL, AND IT IS ADMITTED BY THE SAME RULE AS `+` ─────────────
        //
        // Every other operator in this grammar is here because it commutes
        // with `x mod 2^k`. A call was absent for the same reason `>>` is
        // absent — nothing had proven anything about it — and NOT because a
        // call is categorically opaque. `Observation.call_value` is the
        // caller's proof: it answers only for a callee whose law is a PURE
        // mod-2^k ring homomorphism derived from that callee's own body, and
        // null otherwise.
        //
        // WHY QUOTIENTED ARGUMENTS ARE ENOUGH. The values handed over are
        // already `x mod 2^k`, so what comes back is `h(f(h(x)))`; the
        // homomorphism is exactly the proof that this is `h(f(x))`, which is
        // the identity every line above rests on for a builtin operator.
        //
        // O4 IS NOT WEAKENED. The seam's producer runs `demand.inert` — the
        // tree's one producer of the trap/effect fact — over the callee's
        // whole answer and refuses `/ % //` and every effect before answering,
        // so admitting the node adds no trap this grammar was excluding.
        .call => |c| {
            const ctx = obs.call_ctx orelse return null;
            const value = obs.call_value orelse return null;
            if (c.args.len > max_call_args) return null;
            var argv: [max_call_args]i64 = @splat(0);
            for (c.args, 0..) |arg, i| {
                const av = quotientEval(arg, state, vals, mask, binds, obs) orelse return null;
                argv[i] = @bitCast(av);
            }
            const v = value(ctx, expr, argv[0..c.args.len]) orelse return null;
            return @as(u64, @bitCast(v)) & mask;
        },

        .unop => |u| {
            const inner = quotientEval(u.operand, state, vals, mask, binds, obs) orelse return null;
            return switch (u.op) {
                .neg => (0 -% inner) & mask,
                .bnot => (~inner) & mask,
                else => null,
            };
        },
        .binop => |b| {
            const lhs = quotientEval(b.lhs, state, vals, mask, binds, obs) orelse return null;
            const rhs = quotientEval(b.rhs, state, vals, mask, binds, obs) orelse return null;
            return switch (b.op) {
                .add => (lhs +% rhs) & mask,
                .sub => (lhs -% rhs) & mask,
                .mul => (lhs *% rhs) & mask,
                .band => lhs & rhs & mask,
                .bor => (lhs | rhs) & mask,
                .bxor => (lhs ^ rhs) & mask,
                // A shift COUNT is not a value in the quotient — it indexes
                // bits, so it must be a literal and it must be in range.
                .lshift => {
                    const c = switch (b.rhs.*) {
                        .int_lit => |lit| lit.val,
                        else => return null,
                    };
                    if (c < 0 or c > 63) return null;
                    return (lhs << @intCast(c)) & mask;
                },
                else => null,
            };
        },
        else => return null,
    }
}

/// Close a loop by walking its orbit in the observation quotient.
fn closeWhileByOrbit(loop: anytype, binds: Bindings, obs: Observation) ?Closed {
    if (obs.bits == 0 or obs.bits >= 64) return null;
    const mask: u64 = (@as(u64, 1) << @intCast(obs.bits)) - 1;

    // The state set and the trip count come from the SAME machinery alternative
    // A uses — O1, O2, O5 and O8 are discharged identically and at full width.
    // Only the BODY is quotiented; the guard never is, because the guard reads
    // the induction variable at 64 bits.
    var state = State{};
    if (!internAssignedNames(&loop.body, &state, loop.cond, obs)) return null;
    if (state.len == 0) return null;

    // THE GUARD IS NOT QUOTIENTED — same function, same rules, full width. Only
    // the BODY runs in the quotient; the induction variable is compared at 64
    // bits and O1/O2/O5/O8 are discharged exactly as in alternative A.
    const guard = analyzeGuard(loop.cond, &state, binds) orelse return null;

    // The IV must still be a monotone affine walk AT FULL WIDTH. Re-derived
    // through the polynomial reader, which refuses anything else.
    var poly_state = State{};
    const updates = collectUpdates(&loop.body, &poly_state, binds);
    const step: i64 = if (updates) |up| blk: {
        const iv_name = state.names[guard.iv];
        const poly_iv = poly_state.indexOf(iv_name) orelse return null;
        break :blk affineSelfStep(up.cur[poly_iv], poly_iv) orelse return null;
    } else affineStepFromBody(&loop.body, state.names[guard.iv], binds) orelse return null;

    var vals: [max_vars]u64 = @splat(0);
    for (0..state.len) |i| {
        if (binds.get(state.names[i])) |v| {
            vals[i] = v & mask;
        } else if (i != guard.iv and entryValueIsDead(&loop.body, state.names[i])) {
            vals[i] = 0;
        } else return null;
    }
    const iv_start: i64 = @bitCast(binds.get(state.names[guard.iv]) orelse return null);
    const trips = tripCount(guard, iv_start, step) orelse return null;

    // ── O10 — THE CONTRACTED KEY, AND THE CHECK THAT MAKES IT THIS FILE'S ──
    //
    // A slot the continuation cannot see does not have to be part of what
    // makes a state distinct. Dropping it can only SHORTEN the orbit, and on
    // the shapes `src/obseq.zig` measures it shortens 768 -> 192 and
    // 1792 -> 896 — because the induction variable's 256-cycle multiplies
    // every other slot's period and nothing observes it.
    //
    // THE CONDITION IS RE-DERIVED HERE. The caller supplies the SET; this
    // file proves the property that makes dropping it lawful, namely that the
    // remaining key still determines its own successor. If any slot that stays
    // reads a slot that goes, the orbit is not a function of the key, a repeat
    // is not a cycle, and the whole closure is refused. That is §24 across the
    // seam: the delegating engine's answer is a candidate, not an authority.
    //
    // The GUARD may read a dropped slot and that is not a defect: it is read
    // at FULL WIDTH out of `binds`, and O1/O2/O5/O8 derive the trip count
    // analytically without ever consulting `vals`. Refusing it would delete
    // the commonest case — the induction variable itself.
    var in_key: [max_vars]bool = @splat(true);
    var key_len: usize = 0;
    for (0..state.len) |i| {
        in_key[i] = !obs.dropped(state.names[i]);
        if (in_key[i]) key_len += 1;
    }
    if (key_len == 0) return null;
    if (!keyDeterminesSuccessor(&loop.body, &state, &in_key, obs)) return null;

    // The orbit key must be injective on the quotient state, or two distinct
    // states could be read as a cycle and the answer would be wrong.
    const bits_per: usize = obs.bits;
    if (bits_per * key_len > 64) return null;

    var seen: std.AutoHashMapUnmanaged(u64, u32) = .empty;
    var history: std.ArrayListUnmanaged([max_vars]u64) = .empty;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var step_index: u32 = 0;
    while (true) {
        var key: u64 = 0;
        for (0..state.len) |i| {
            if (!in_key[i]) continue;
            key = (key << @intCast(bits_per)) | (vals[i] & mask);
        }

        const slot = seen.getOrPut(alloc, key) catch return null;
        if (slot.found_existing) {
            const mu: u64 = slot.value_ptr.*;
            const lambda: u64 = @as(u64, step_index) - mu;
            const index: u64 = if (trips < mu) trips else mu + (trips - mu) % lambda;
            return finishOrbit(&state, history.items[@intCast(index)], trips, obs.bits);
        }
        slot.value_ptr.* = step_index;
        history.append(alloc, vals) catch return null;

        if (trips == step_index) {
            return finishOrbit(&state, vals, trips, obs.bits);
        }
        if (!quotientStep(&loop.body, &state, &vals, mask, binds, obs)) return null;
        step_index += 1;
        if (step_index >= max_orbit_steps) return null;
    }
}

/// O10's proof obligation, discharged against the body this file is about to
/// walk rather than against the caller's word for it.
///
/// Every slot that STAYS in the key must have an update that reads only slots
/// that stay. Then the key is a function of itself one step later, a repeated
/// key IS a repeated state of the contracted machine, and the cycle detection
/// above means what it meant before the contraction.
///
/// FAILS CLOSED: an expression form `mentionsSlot` does not enumerate answers
/// TRUE, so an unmodelled construct keeps the slot and refuses the drop.
fn keyDeterminesSuccessor(
    body: *const ast.Block,
    state: *const State,
    in_key: *const [max_vars]bool,
    obs: Observation,
) bool {
    for (body.stmts) |st| {
        const a = switch (st) {
            .assign => |x| x,
            else => return false,
        };
        if (a.targets.len != 1 or a.values.len != 1) return false;
        const target = switch (a.targets[0].*) {
            .name => |n| n.ident,
            else => return false,
        };
        // A target that never entered the state is a dropped slot; nothing in
        // the key reads it, which is the property this function checks.
        const slot = state.indexOf(target) orelse continue;
        if (!in_key[slot]) continue;
        // Checked against the CALLER'S SET rather than against the state, so
        // a dropped name that was interned anyway — the induction variable —
        // is caught too. `a = a + i` with `i` out of the key is exactly the
        // shape that would make a repeat not a cycle.
        for (obs.unobserved) |n| {
            if (mentionsSlot(a.values[0], n)) return false;
        }
    }
    return true;
}

/// FAILS CLOSED — an expression form not enumerated answers TRUE.
fn mentionsSlot(e: *const ast.Expr, name: []const u8) bool {
    return switch (e.*) {
        .int_lit, .float_lit, .quoted, .nil, .true_lit, .false_lit => false,
        .name => |n| std.mem.eql(u8, n.ident, name),
        .unop => |u| mentionsSlot(u.operand, name),
        .binop => |b| mentionsSlot(b.lhs, name) or mentionsSlot(b.rhs, name),
        .call => |c| blk: {
            if (mentionsSlot(c.func, name)) break :blk true;
            for (c.args) |arg| if (mentionsSlot(arg, name)) break :blk true;
            break :blk false;
        },
        else => true,
    };
}

/// O10's OTHER half. `finishOrbit` reports every slot's value at the CYCLE
/// index, and for a dropped slot that is not its value at the trip index —
/// the key stopped distinguishing it, so the walk stopped tracking when it
/// came round. Nothing outside the loop may read one.
///
/// Checked over the whole relation body once, before any of it runs, rather
/// than at each of the four places a value is read: one place cannot be
/// reached around, four can.
fn readsDroppedOutsideLoop(b: *const ast.Block, obs: Observation) bool {
    for (b.stmts) |st| {
        switch (st) {
            .while_loop => {},
            .assign => |a| for (a.values) |v| {
                for (obs.unobserved) |n| if (mentionsSlot(v, n)) return true;
            },
            .local_decl => |d| for (d.inits) |v| {
                for (obs.unobserved) |n| if (mentionsSlot(v, n)) return true;
            },
            .ret => |r| for (r.vals) |v| {
                for (obs.unobserved) |n| if (mentionsSlot(v, n)) return true;
            },
            // Every other statement form refuses the whole body below anyway;
            // saying TRUE here keeps this check from being the one that lets a
            // future form through.
            else => return true,
        }
    }
    if (b.tail_expr) |t| {
        for (obs.unobserved) |n| if (mentionsSlot(t, n)) return true;
    }
    return false;
}

fn finishOrbit(state: *const State, vals: [max_vars]u64, trips: u64, bits: u7) Closed {
    var out = Closed{
        .trips = trips,
        .basis = 0,
        .valid_bits = bits,
        .via = .observation_orbit,
    };
    out.len = state.len;
    for (0..state.len) |i| {
        out.names[i] = state.names[i];
        out.values[i] = vals[i];
    }
    return out;
}

/// O6/O7 for the quotient path: the same refusals, without building polynomials.
///
/// O10 — **THE CONTRACTION REACHES THE INTERNING, NOT ONLY THE PACKING.** A
/// slot the continuation cannot see does not need a state entry at all, and
/// this is where that is worth something rather than merely tidy: `max_vars`
/// is SIX, so a loop assigning seven names is refused outright here — while
/// `obseq.max_slots` is EIGHT, so the delegating engine had already closed
/// its contracted orbit and could only watch the delegation refuse. Dropping
/// the unobserved names before interning is what makes the two agree on what
/// the state IS.
///
/// A dropped name's assignment is then NEVER EVALUATED, so O4 has to be
/// discharged another way: its right-hand side is held to the same trap-free
/// grammar `quotientEval` admits, syntactically, with no call. Skipping a
/// statement that could trap would delete a trap, and a deleted trap is a
/// changed answer.
///
/// The INDUCTION VARIABLE is interned even when it is dropped: `analyzeGuard`
/// resolves the guard's names against this state, and O1/O2/O5/O8 are derived
/// from it at full width. It is dropped from the KEY, which is the whole W6
/// contraction, and kept in the WALK, which is what the guard needs.
fn internAssignedNames(
    body: *const ast.Block,
    state: *State,
    cond: *const ast.Expr,
    obs: Observation,
) bool {
    if (body.tail_expr != null) return false;
    for (body.stmts) |st| {
        switch (st) {
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return false;
                const target = switch (a.targets[0].*) {
                    .name => |n| n.ident,
                    else => return false,
                };
                if (obs.dropped(target) and !mentionsSlot(cond, target)) continue;
                _ = state.intern(target) orelse return false;
            },
            else => return false,
        }
    }
    // Second pass, because the first cannot know which names ended up interned
    // until it has seen every statement.
    for (body.stmts) |st| {
        const a = st.assign;
        const target = a.targets[0].name.ident;
        if (state.indexOf(target) != null) continue;
        if (!droppedUpdateIsInert(a.values[0])) return false;
    }
    return state.len != 0;
}

/// O4 FOR A STATEMENT THAT WILL NOT RUN. The same node set `quotientEval`
/// admits, read syntactically because there are no values to read: a dropped
/// slot's update may mention other dropped slots, which are not in the state.
///
/// A CALL IS NOT IN IT, and deliberately: admitting one here would mean
/// asserting the callee is total without evaluating it, and the seam that
/// proves that answers about a call SITE with arguments. A dropped slot whose
/// update applies a relation refuses the drop, which costs a closure and never
/// an answer.
fn droppedUpdateIsInert(e: *const ast.Expr) bool {
    return switch (e.*) {
        .int_lit, .name => true,
        .unop => |u| switch (u.op) {
            .neg, .bnot => droppedUpdateIsInert(u.operand),
            else => false,
        },
        .binop => |b| switch (b.op) {
            .add, .sub, .mul, .band, .bor, .bxor => droppedUpdateIsInert(b.lhs) and droppedUpdateIsInert(b.rhs),
            .lshift => blk: {
                const c = switch (b.rhs.*) {
                    .int_lit => |lit| lit.val,
                    else => break :blk false,
                };
                if (c < 0 or c > 63) break :blk false;
                break :blk droppedUpdateIsInert(b.lhs);
            },
            else => false,
        },
        else => false,
    };
}

/// The IV's step when the body is outside the polynomial grammar (a body with
/// xors still has an ordinary `i += 1` in it). Reads ONLY the induction
/// variable's own assignment and requires it to be `iv + <constant>`.
fn affineStepFromBody(body: *const ast.Block, iv: []const u8, binds: Bindings) ?i64 {
    var found: ?i64 = null;
    for (body.stmts) |st| {
        const a = switch (st) {
            .assign => |x| x,
            else => return null,
        };
        if (a.targets.len != 1 or a.values.len != 1) return null;
        const target = switch (a.targets[0].*) {
            .name => |n| n.ident,
            else => return null,
        };
        if (!std.mem.eql(u8, target, iv)) continue;
        if (found != null) return null; // assigned twice: not a simple walk
        const b = switch (a.values[0].*) {
            .binop => |x| x,
            else => return null,
        };
        if (b.op != .add and b.op != .sub) return null;
        const names_iv = switch (b.lhs.*) {
            .name => |n| std.mem.eql(u8, n.ident, iv),
            else => false,
        };
        if (!names_iv) return null;
        var empty = State{};
        const rhs = polyOfExpr(b.rhs, &empty, binds) orelse return null;
        const c = rhs.asConstant() orelse return null;
        const signed: i64 = @bitCast(c);
        found = if (b.op == .add) signed else -%signed;
    }
    const c = found orelse return null;
    if (c == 0) return null;
    // The IV must not also be read into itself in a non-affine way elsewhere.
    return c;
}

/// Close one `while` loop whose entry state is entirely constant.
///
/// Returns the loop's live-out values in O(basis³ · log T) compile time,
/// INDEPENDENT of T — which is the whole point: the existing fold is O(T) and
/// gives up at 16,665 iterations.
pub fn closeWhile(
    loop: anytype,
    binds: Bindings,
) ?Closed {
    var state = State{};
    // O6: intern every assigned name BEFORE anything reads the guard, so the
    // guard's IV is recognized as loop-carried rather than as a constant.
    const updates = collectUpdates(&loop.body, &state, binds) orelse return null;
    if (state.len == 0) return null;

    const guard = analyzeGuard(loop.cond, &state, binds) orelse return null;

    // O5: the IV's own update must be exactly `iv + step` with a constant step.
    // Anything else (`i = 2*i`, `i = i + j`) is not a monotone affine walk and
    // the trip-count derivation does not apply to it.
    const iv_update = updates.cur[guard.iv];
    const step = affineSelfStep(iv_update, guard.iv) orelse return null;

    // Entry values. A loop-carried name with no entry binding is unbound and
    // refuses — nothing is silently zero.
    //
    // EXCEPT FOR A BODY TEMPORARY, whose entry value is provably never read.
    // `t = a + b ; a = b ; b = t` is how an order-k recurrence is spelled when
    // the grammar is single-target assignment, and `t` has no value before the
    // loop. Refusing it cost the whole order-2 family — `fib_order2` was the
    // one MISS in the first gate run. `entryValueIsDead` proves the temporary's
    // incoming value is overwritten before any read of it, in which case ANY
    // entry value gives the same answer and zero is as good as another.
    var entry: [max_vars]u64 = undefined;
    for (0..state.len) |i| {
        if (binds.get(state.names[i])) |v| {
            entry[i] = v;
        } else if (i != guard.iv and entryValueIsDead(&loop.body, state.names[i])) {
            entry[i] = 0;
        } else return null;
    }

    const trips = tripCount(guard, @bitCast(entry[guard.iv]), step) orelse return null;

    const basis = closeBasis(&state, updates) orelse return null;

    // Build M with `image(basis[j]) = Σ_k M[j][k] · basis[k]`.
    var m = Matrix{ .n = basis.len };
    for (0..basis.len) |j| {
        const image = imageOf(basis.monos[j], updates) orelse return null;
        for (0..image.len) |t| {
            const k = basis.indexOf(image.terms[t].mono) orelse return null;
            m.set(j, k, m.at(j, k) +% image.terms[t].coeff);
        }
    }

    const mt = matPow(m, trips);

    // Evaluate the basis at the entry state, then apply M^T once.
    var vec0: [max_basis]u64 = @splat(0);
    for (0..basis.len) |k| {
        var v: u64 = 1;
        for (0..max_vars) |x| {
            var e: u8 = 0;
            while (e < basis.monos[k][x]) : (e += 1) v = v *% entry[x];
        }
        vec0[k] = v;
    }

    var out = Closed{ .trips = trips, .basis = basis.len };
    out.len = state.len;
    for (0..state.len) |i| {
        var mono = zero_mono;
        mono[i] = 1;
        const row = basis.indexOf(mono) orelse return null;
        var acc: u64 = 0;
        for (0..basis.len) |k| acc = acc +% mt.at(row, k) *% vec0[k];
        out.names[i] = state.names[i];
        out.values[i] = acc;
    }
    return out;
}

/// True when the body WRITES `name` before it READS it, so the value `name`
/// holds on entry to the loop cannot affect anything.
///
/// SCANS IN ORDER AND STOPS AT THE FIRST MENTION. If the first mention is an
/// assignment target, the incoming value is dead. If a right-hand side mentions
/// the name first, it is live and the caller must refuse. Conservative in the
/// direction that matters: an expression form this walk does not enumerate
/// counts as a READ, so a construct nobody anticipated makes the value live
/// rather than dead.
///
/// The guard is not scanned because it cannot mention this name: `analyzeGuard`
/// admits only `iv <op> constant`, and the induction variable is excluded by
/// the caller.
fn entryValueIsDead(body: *const ast.Block, name: []const u8) bool {
    for (body.stmts) |st| {
        const a = switch (st) {
            .assign => |x| x,
            else => return false,
        };
        if (a.targets.len != 1 or a.values.len != 1) return false;
        // The right-hand side is evaluated BEFORE the target is written, so a
        // read here beats a write in the same statement.
        if (exprMentions(a.values[0], name)) return false;
        const target = switch (a.targets[0].*) {
            .name => |n| n.ident,
            else => return false,
        };
        if (std.mem.eql(u8, target, name)) return true;
    }
    return false;
}

/// Whether `name` appears anywhere in `expr`. Every form NOT enumerated answers
/// TRUE — an unknown node might mention the name, and the caller's soundness
/// depends on this erring toward "live".
fn exprMentions(expr: *const ast.Expr, name: []const u8) bool {
    return switch (expr.*) {
        .int_lit, .float_lit, .quoted, .nil, .true_lit, .false_lit => false,
        .name => |n| std.mem.eql(u8, n.ident, name),
        .unop => |u| exprMentions(u.operand, name),
        .binop => |b| exprMentions(b.lhs, name) or exprMentions(b.rhs, name),
        else => true,
    };
}

/// `iv_update` must be `iv + c`. Returns c.
fn affineSelfStep(p: Poly, iv: usize) ?i64 {
    var self_coeff: u64 = 0;
    var constant: u64 = 0;
    for (0..p.len) |i| {
        const d = monoDegree(p.terms[i].mono);
        if (d == 0) {
            constant = p.terms[i].coeff;
        } else if (d == 1 and p.terms[i].mono[iv] == 1) {
            self_coeff = p.terms[i].coeff;
        } else return null;
    }
    if (self_coeff != 1) return null;
    const c: i64 = @bitCast(constant);
    if (c == 0) return null;
    return c;
}

// ── The driver: a whole no-operand relation body ─────────────────────────────

/// Run a no-operand relation body whose only unbounded construct is a closable
/// `while` loop, and answer its integer result.
///
/// SHAPE ADMITTED, and it is deliberately narrow: a run of constant bindings, a
/// run of closable `while` loops, and a tail name or constant expression. This
/// is the shape `comptime.foldRelationBody` already handles for SMALL bounds
/// and gives up on past 16,665 iterations, so the two agree everywhere the
/// budget allows and this one keeps going.
///
/// Returns the ring value as i64 (the caller emits it as an i64 constant, and
/// the backend's `mov`/`movk` sequence carries the same 64 bits).
pub fn closeRelationBody(fb: *const ast.FuncBody) ?i64 {
    return closeRelationBodyObserved(fb, .{});
}

/// The same driver, told what an observer of the result can distinguish.
///
/// `obs.bits < 64` UNLOCKS THE QUOTIENT ALTERNATIVE AND CARRIES O9 WITH IT. The
/// caller is asserting that no observer distinguishes results agreeing on the
/// low `bits`, and it owes that proof — see `Observation`. `closeRelationBody`
/// passes the default (64, fully observed), so the quotient is off unless a
/// call site deliberately supplies the fact.
pub fn closeRelationBodyObserved(fb: *const ast.FuncBody, obs: Observation) ?i64 {
    if (fb.params.len != 0 or fb.vararg or fb.vararg_name != null) return null;
    // O10. A contracted key stops maintaining the slots it dropped, so a read
    // of one anywhere outside the loop would be reading the orbit's value at
    // the wrong index. Refused before anything runs.
    if (obs.unobserved.len != 0 and readsDroppedOutsideLoop(&fb.body, obs)) return null;

    var binds = Bindings{};
    var saw_loop = false;
    var quotiented = false;
    var valid_bits: u7 = 64;
    _ = &valid_bits;
    var state_scratch = State{};

    for (fb.body.stmts) |st| {
        switch (st) {
            .local_decl => |d| {
                if (d.names.len != d.inits.len) return null;
                for (d.names, d.inits) |n, init| {
                    const p = polyOfExpr(init, &state_scratch, binds) orelse return null;
                    const v = p.asConstant() orelse return null;
                    if (!binds.put(n.ident, v)) return null;
                }
            },
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return null;
                const name = switch (a.targets[0].*) {
                    .name => |n| n.ident,
                    else => return null,
                };
                const p = polyOfExpr(a.values[0], &state_scratch, binds) orelse return null;
                const v = p.asConstant() orelse return null;
                if (!binds.put(name, v)) return null;
            },
            .while_loop => |w| {
                // THE SEARCH OVER LAWFUL ALTERNATIVES, RANKED BY WHAT THEY
                // ASSUME rather than by what they cost.
                //
                //   A. operator powering  — assumes NOTHING beyond the eight
                //      obligations, answers all 64 bits, O(b³ log T).
                //   B. observation orbit  — assumes O9 (a demand fact the caller
                //      supplied), answers only the demanded bits, O(μ+λ).
                //
                // A first, always. A closure that needs no extra fact must never
                // lose to one that does, and running B only on A's refusals
                // means the weaker assumption can never silently take a case the
                // stronger one already had.
                //
                // ONCE QUOTIENTED, STOP. After B, the bindings hold only the low
                // `bits`; a later loop's guard compares an induction variable at
                // 64 bits, so its trip count would be derived from a value this
                // pass no longer knows. Refusing every later loop is the cheap
                // sound rule, and it is why `quotiented` exists.
                if (quotiented) return null;
                const closed = closeWhile(w, binds) orelse
                    (closeWhileByOrbit(w, binds, obs) orelse return null);
                if (closed.via == .observation_orbit) {
                    quotiented = true;
                    valid_bits = closed.valid_bits;
                }
                for (0..closed.len) |i| {
                    if (!binds.put(closed.names[i], closed.values[i])) return null;
                }
                saw_loop = true;
            },
            .ret => |r| {
                if (r.vals.len != 1) return null;
                const p = polyOfExpr(r.vals[0], &state_scratch, binds) orelse return null;
                const v = p.asConstant() orelse return null;
                // A body with no loop is the straight-line folder's business,
                // not this pass's; answering it here would make two passes claim
                // one case and mask a regression in the other.
                if (!saw_loop) return null;
                return @bitCast(v);
            },
            else => return null,
        }
    }

    const tail = fb.body.tail_expr orelse return null;
    if (!saw_loop) return null;
    const p = polyOfExpr(tail, &state_scratch, binds) orelse return null;
    const v = p.asConstant() orelse return null;
    return @bitCast(v);
}

// ════════════════════════════════════════════════════════════════════════════
// TESTS
//
// Every closure test below is DIFFERENTIAL against a brute-force loop written
// in Zig with the same wrapping arithmetic. `expectClosureMatchesLoop` is the
// only assertion form used for values, because a closed form checked against a
// hand-computed constant only proves the author's algebra agrees with itself.
// ════════════════════════════════════════════════════════════════════════════

const test_loc: ast.Loc = .{ .file = "recurrence-test", .line = 1, .col = 1 };

fn testUpdatesSum() Updates {
    // s = s + i ; i = i + 1
    var up = Updates{};
    up.cur[0] = Poly.add(Poly.variable(0), Poly.variable(1)).?; // s' = s + i
    up.cur[1] = Poly.add(Poly.variable(1), Poly.constant(1)).?; // i' = i + 1
    return up;
}

test "recurrence: poly ring is wrapping and cancellation drops terms" {
    const a = Poly.constant(std.math.maxInt(u64));
    const b = Poly.constant(1);
    const s = Poly.add(a, b).?;
    try std.testing.expectEqual(@as(?u64, 0), s.asConstant());
    try std.testing.expectEqual(@as(usize, 0), s.len);

    const v = Poly.variable(0);
    const gone = Poly.sub(v, v).?;
    try std.testing.expectEqual(@as(usize, 0), gone.len);
}

test "recurrence: basis search closes for a sum and finds three monomials" {
    var state = State{};
    _ = state.intern("s").?;
    _ = state.intern("i").?;
    const basis = closeBasis(&state, testUpdatesSum()).?;
    try std.testing.expectEqual(@as(usize, 3), basis.len);
}

test "recurrence: basis search DIVERGES on a factorial and refuses" {
    // s = s * i ; i = i + 1 — every pass raises the degree of s, so no finite
    // monomial basis exists. The engine is not told this; the search fails.
    var state = State{};
    _ = state.intern("s").?;
    _ = state.intern("i").?;
    var up = Updates{};
    up.cur[0] = Poly.mul(Poly.variable(0), Poly.variable(1)).?;
    up.cur[1] = Poly.add(Poly.variable(1), Poly.constant(1)).?;
    try std.testing.expect(closeBasis(&state, up) == null);
}

/// Brute force the SAME loop in Zig with the same wrapping ring, and require
/// the closed form to agree exactly.
fn expectSumClosure(start_s: u64, start_i: i64, bound: i64, step: i64, inclusive: bool, ascending: bool) !void {
    var state = State{};
    _ = state.intern("s").?;
    _ = state.intern("i").?;
    var up = Updates{};
    up.cur[0] = Poly.add(Poly.variable(0), Poly.variable(1)).?;
    up.cur[1] = Poly.add(Poly.variable(1), Poly.constant(@bitCast(step))).?;

    const guard = Guard{ .iv = 1, .bound = bound, .ascending = ascending, .inclusive = inclusive };
    const trips = tripCount(guard, start_i, step);

    // Brute force with the SAME wrapping ring the emitted loop runs in.
    //
    // THE WRAP FLAG IS THE POINT OF THIS HARNESS, not bookkeeping. When the IV
    // steps past i64's edge, the real loop's guard reads the WRAPPED value and
    // the loop does not exit where any affine formula says it does — it runs on
    // for ~2^64 trips. So the harness cannot brute-force such a case, and the
    // only correct answer from `tripCount` is a REFUSAL. Asserting that here is
    // what makes O2 a tested obligation instead of a paragraph.
    var bs: u64 = start_s;
    var bi: i64 = start_i;
    var count: u64 = 0;
    var wrapped = false;
    while (count < 100_000) : (count += 1) {
        const live = if (ascending)
            (if (inclusive) bi <= bound else bi < bound)
        else
            (if (inclusive) bi >= bound else bi > bound);
        if (!live) break;
        bs = bs +% @as(u64, @bitCast(bi));
        const next: i128 = @as(i128, bi) + @as(i128, step);
        if (!ivStaysInRange(next)) {
            wrapped = true;
            break;
        }
        bi = @intCast(next);
    }
    if (wrapped) {
        try std.testing.expect(trips == null);
        return;
    }
    try std.testing.expect(count < 100_000); // the brute force must have finished

    if (trips == null) return; // a refusal is always sound; nothing to compare
    try std.testing.expectEqual(count, trips.?);

    const basis = closeBasis(&state, up).?;
    var m = Matrix{ .n = basis.len };
    for (0..basis.len) |j| {
        const image = imageOf(basis.monos[j], up).?;
        for (0..image.len) |t| {
            const k = basis.indexOf(image.terms[t].mono).?;
            m.set(j, k, m.at(j, k) +% image.terms[t].coeff);
        }
    }
    const mt = matPow(m, trips.?);
    var entry: [max_vars]u64 = @splat(0);
    entry[0] = start_s;
    entry[1] = @bitCast(start_i);
    var vec0: [max_basis]u64 = @splat(0);
    for (0..basis.len) |k| {
        var v: u64 = 1;
        for (0..max_vars) |x| {
            var e: u8 = 0;
            while (e < basis.monos[k][x]) : (e += 1) v = v *% entry[x];
        }
        vec0[k] = v;
    }
    var got_s: u64 = 0;
    var got_i: u64 = 0;
    for (0..basis.len) |k| {
        got_s = got_s +% mt.at(1, k) *% vec0[k]; // row 1 == mono(s), row 0 == 1
        got_i = got_i +% mt.at(2, k) *% vec0[k];
    }
    try std.testing.expectEqual(bs, got_s);
    try std.testing.expectEqual(@as(u64, @bitCast(bi)), got_i);
}

test "recurrence: sum closure sweeps the edges the corpus got wrong" {
    // THE `lib/bit.id` FAMILY: negatives, zero, one, an odd extent, a
    // descending walk, a stride that does not divide the span.
    try expectSumClosure(0, 1, 0, 1, true, true); // zero trips
    try expectSumClosure(0, 1, 1, 1, true, true); // one trip
    try expectSumClosure(0, 1, 10, 1, true, true);
    try expectSumClosure(0, -10, 10, 1, true, true); // spans zero
    try expectSumClosure(0, -10, -1, 1, true, true); // wholly negative
    try expectSumClosure(0, 1, -5, 1, true, true); // guard false on entry
    try expectSumClosure(0, 0, 0, 1, true, true); // single zero step
    try expectSumClosure(7, 3, 3, 1, true, true); // start == bound
    try expectSumClosure(0, 1, 100, 7, true, true); // stride not dividing span
    try expectSumClosure(0, 1, 100, 7, false, true); // exclusive bound
    try expectSumClosure(0, 100, 1, -1, true, false); // descending
    try expectSumClosure(0, 100, 1, -3, false, false); // descending, exclusive
    try expectSumClosure(std.math.maxInt(u64), 1, 50, 1, true, true); // accumulator wraps
    // THE OVERFLOW BOUNDARY, both sides. The first two exit cleanly one step
    // short of the edge and must close; the last two step OVER it, where the
    // real loop's guard sees a wrapped value and never exits, and must refuse.
    try expectSumClosure(0, std.math.maxInt(i64) - 40, std.math.maxInt(i64) - 1, 1, true, true);
    try expectSumClosure(0, std.math.minInt(i64) + 40, std.math.minInt(i64) + 1, -1, true, false);
    try expectSumClosure(0, std.math.maxInt(i64) - 40, std.math.maxInt(i64), 1, true, true);
    try expectSumClosure(0, std.math.minInt(i64) + 40, std.math.minInt(i64), -1, true, false);
}

test "recurrence: O2 refuses when the induction variable would wrap" {
    // Ascending to i64 max with a step that overshoots: the real loop's guard
    // sees a wrapped negative and stops early, so no affine trip count is valid.
    const guard = Guard{
        .iv = 0,
        .bound = std.math.maxInt(i64),
        .ascending = true,
        .inclusive = true,
    };
    try std.testing.expect(tripCount(guard, std.math.maxInt(i64) - 2, 1) == null);
    // And it is not a blanket refusal near the top — a walk that exits cleanly
    // one step below the boundary is still closed.
    const ok = Guard{
        .iv = 0,
        .bound = std.math.maxInt(i64) - 8,
        .ascending = true,
        .inclusive = true,
    };
    try std.testing.expect(tripCount(ok, std.math.maxInt(i64) - 10, 1) != null);
}

// ── THE TWO PROVERS, DIFFERENCED ─────────────────────────────────────────────
//
// `src/demand.zig` shipped its own trip-count proof. These tests are the
// evidence for collapsing it onto `terminatesForAnyStart`: they sweep the
// boundary where the two derivations can disagree, against an oracle that is
// neither of them.

/// `src/demand.zig`'s ORIGINAL arithmetic condition, transcribed verbatim from
/// `provenTripCount` at f75aba55 so the difference is measured and not argued.
/// It is a SUFFICIENT condition on the bound: "the bound plus one whole step
/// fits", which ignores whether the guard is inclusive.
fn demandOldCondition(limit: i64, ascending: bool, step: i64) bool {
    if (step == 0) return false;
    if (ascending and step <= 0) return false;
    if (!ascending and step >= 0) return false;
    const magnitude = if (ascending) step else -step;
    if (ascending) {
        if (limit > std.math.maxInt(i64) - magnitude) return false;
    } else {
        if (limit < std.math.minInt(i64) + magnitude) return false;
    }
    return true;
}

fn guardHolds(i: i64, bound: i64, ascending: bool, inclusive: bool) bool {
    return if (ascending)
        (if (inclusive) i <= bound else i < bound)
    else
        (if (inclusive) i >= bound else i > bound);
}

/// THE ORACLE, and it is a third mechanism. It does not compute a trip count at
/// all: it RUNS the loop in real, wrapping i64 arithmetic from the worst-case
/// start, and asks whether the machine did what integer arithmetic in Z says.
///
/// The worst start is the last value the guard admits, so a correct loop must
/// leave after EXACTLY one trip. Two trips means the step wrapped the IV back
/// under the bound and the loop re-entered — the failure O2 exists to refuse.
fn bruteTerminatesFromWorstStart(bound: i64, ascending: bool, inclusive: bool, step: i64) bool {
    if (step == 0) return false;
    if (ascending and step < 0) return false;
    if (!ascending and step > 0) return false;

    const last: i128 = if (ascending)
        (if (inclusive) @as(i128, bound) else @as(i128, bound) - 1)
    else
        (if (inclusive) @as(i128, bound) else @as(i128, bound) + 1);
    if (!ivStaysInRange(last)) return true; // guard admits no i64: zero trips.

    var i: i64 = @intCast(last);
    var trips: u32 = 0;
    while (guardHolds(i, bound, ascending, inclusive)) {
        i +%= step;
        trips += 1;
        if (trips > 3) break; // it wrapped and came back: not a terminating walk.
    }
    if (trips != 1) return false;
    // And the value it left with must be the value arithmetic in Z predicts.
    return @as(i128, i) == last + @as(i128, step);
}

test "recurrence: terminatesForAnyStart agrees with a running loop, everywhere" {
    const max = std.math.maxInt(i64);
    const min = std.math.minInt(i64);
    const bounds = [_]i64{
        min,        min + 1,     min + 2,   min + 7,   min + 64,
        -1000,      -7,          -1,        0,         1,
        7,          1000,        max - 64,  max - 7,   max - 2,
        max - 1,    max,
    };
    const steps = [_]i64{
        1, 2, 3, 7, 64, 1000, max - 1, max,
        -1, -2, -3, -7, -64, -1000, min + 1, min + 2,
        0,
    };

    var checked: usize = 0;
    var exact_wrong: usize = 0;
    var demand_unsound: usize = 0;
    var demand_conservative: usize = 0;

    for (bounds) |bound| {
        for (steps) |step| {
            for ([_]bool{ true, false }) |ascending| {
                for ([_]bool{ true, false }) |inclusive| {
                    checked += 1;
                    const truth = bruteTerminatesFromWorstStart(bound, ascending, inclusive, step);
                    const exact = terminatesForAnyStart(bound, ascending, inclusive, step);
                    const old = demandOldCondition(bound, ascending, step);

                    // 1. The kernel this lane is converging ON must be exact.
                    if (exact != truth) exact_wrong += 1;
                    // 2. The condition it replaces must never have been WRONG —
                    //    a case demand accepted that does not actually halt is
                    //    a deleted loop that was not dead.
                    if (old and !truth) demand_unsound += 1;
                    // 3. Where it was merely tighter, count it. A zero here
                    //    would mean the convergence is pure deduplication.
                    if (truth and !old) demand_conservative += 1;
                }
            }
        }
    }

    if (exact_wrong != 0 or demand_unsound != 0) {
        std.debug.print(
            "\nconverge sweep: checked={d} exact_wrong={d} demand_unsound={d} demand_conservative={d}\n",
            .{ checked, exact_wrong, demand_unsound, demand_conservative },
        );
        for (bounds) |bound| {
            for (steps) |step| {
                for ([_]bool{ true, false }) |ascending| {
                    for ([_]bool{ true, false }) |inclusive| {
                        const truth = bruteTerminatesFromWorstStart(bound, ascending, inclusive, step);
                        const exact = terminatesForAnyStart(bound, ascending, inclusive, step);
                        const old = demandOldCondition(bound, ascending, step);
                        if (exact != truth or (old and !truth)) {
                            std.debug.print(
                                "  bound={d} step={d} asc={} incl={} truth={} exact={} old={}\n",
                                .{ bound, step, ascending, inclusive, truth, exact, old },
                            );
                        }
                    }
                }
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 1156), checked);
    try std.testing.expectEqual(bounds.len * steps.len * 4, checked);
    // The kernel is EXACT: it says yes on precisely the loops that ran and left.
    try std.testing.expectEqual(@as(usize, 0), exact_wrong);
    // `demand`'s condition was never WRONG — nothing it accepted fails to halt.
    // So this convergence licenses no transform that was previously refused for
    // a reason; it only stops refusing things for no reason.
    try std.testing.expectEqual(@as(usize, 0), demand_unsound);
    // MEASURED, not read off the source: the two provers really do differ, on
    // 7 of 1,156 shapes, all of them an exclusive bound one step from the edge.
    // A zero here would have made this a pure deduplication.
    try std.testing.expectEqual(@as(usize, 7), demand_conservative);
}

test "recurrence: the distinguishing case is an exclusive bound at the i64 edge" {
    const max = std.math.maxInt(i64);
    // `while i < maxInt` stepping by 1. The last admitted value is maxInt-1 and
    // the loop leaves holding maxInt, which is representable — it terminates,
    // and every i64 start reaches that same exit. `demand`'s condition asks
    // instead whether `maxInt + 1` fits, which it does not, so it refused.
    try std.testing.expect(bruteTerminatesFromWorstStart(max, true, false, 1));
    try std.testing.expect(terminatesForAnyStart(max, true, false, 1));
    try std.testing.expect(!demandOldCondition(max, true, 1));

    // The INCLUSIVE form of the same bound genuinely does not terminate: the
    // guard still admits maxInt, so the IV must step past it and wrap. Both
    // provers refuse, which is what makes the case above a real difference
    // rather than the exact check being loose everywhere near the edge.
    try std.testing.expect(!bruteTerminatesFromWorstStart(max, true, true, 1));
    try std.testing.expect(!terminatesForAnyStart(max, true, true, 1));
    try std.testing.expect(!demandOldCondition(max, true, 1));

    // And the mirror image at the bottom of the range.
    const min = std.math.minInt(i64);
    try std.testing.expect(bruteTerminatesFromWorstStart(min, false, false, -1));
    try std.testing.expect(terminatesForAnyStart(min, false, false, -1));
    try std.testing.expect(!demandOldCondition(min, false, -1));
}

test "recurrence: O5 refuses a zero step and a step moving away from the bound" {
    const g = Guard{ .iv = 0, .bound = 10, .ascending = true, .inclusive = true };
    try std.testing.expect(tripCount(g, 1, 0) == null);
    try std.testing.expect(tripCount(g, 1, -1) == null);
    // Descending guard with an ascending step: also no progress toward exit.
    const d = Guard{ .iv = 0, .bound = 1, .ascending = false, .inclusive = true };
    try std.testing.expect(tripCount(d, 10, 1) == null);
}

test "recurrence: O4 grammar refuses every trappable and non-ring form" {
    const state = State{};
    const binds = Bindings{};
    var lit_a = ast.Expr{ .int_lit = .{ .loc = test_loc, .val = 8 } };
    var lit_b = ast.Expr{ .int_lit = .{ .loc = test_loc, .val = 2 } };
    inline for (.{ .div, .mod, .idiv, .rshift, .lshift, .band, .bor, .bxor, .pow }) |op| {
        const e = ast.Expr{ .binop = .{ .loc = test_loc, .op = op, .lhs = &lit_a, .rhs = &lit_b } };
        try std.testing.expect(polyOfExpr(&e, &state, binds) == null);
    }
    // And the ring operations ARE admitted, so the refusals above are about the
    // operator and not about the walk failing everywhere.
    inline for (.{ .add, .sub, .mul }) |op| {
        const e = ast.Expr{ .binop = .{ .loc = test_loc, .op = op, .lhs = &lit_a, .rhs = &lit_b } };
        try std.testing.expect(polyOfExpr(&e, &state, binds) != null);
    }
    // An index expression is trappable (measured: out-of-range aborts) and has
    // no case at all in the grammar.
    const idx = ast.Expr{ .index = .{ .loc = test_loc, .obj = &lit_a, .key = &lit_b } };
    try std.testing.expect(polyOfExpr(&idx, &state, binds) == null);
}

test "recurrence: an unbound name refuses rather than reading zero" {
    const state = State{};
    const binds = Bindings{};
    const e = ast.Expr{ .name = .{ .loc = test_loc, .ident = "nowhere" } };
    try std.testing.expect(polyOfExpr(&e, &state, binds) == null);
}

test "recurrence: matrix powering is the ring, and agrees with iteration" {
    const up = testUpdatesSum();
    var state = State{};
    _ = state.intern("s").?;
    _ = state.intern("i").?;
    const basis = closeBasis(&state, up).?;
    var m = Matrix{ .n = basis.len };
    for (0..basis.len) |j| {
        const image = imageOf(basis.monos[j], up).?;
        for (0..image.len) |t| {
            const k = basis.indexOf(image.terms[t].mono).?;
            m.set(j, k, m.at(j, k) +% image.terms[t].coeff);
        }
    }
    // M^T by powering must equal M applied T times, for a T spanning bit
    // patterns that exercise both branches of the powering loop.
    for ([_]u64{ 0, 1, 2, 3, 7, 8, 63, 64, 1000, 1_048_576 }) |t| {
        const fast = matPow(m, t);
        var slow = Matrix.identity(m.n);
        var k: u64 = 0;
        while (k < t) : (k += 1) slow = Matrix.mul(slow, m);
        try std.testing.expectEqualSlices(u64, slow.a[0 .. slow.n * slow.n], fast.a[0 .. fast.n * fast.n]);
    }
}

/// Build the AST for
///
///     while i <= <bound>
///         x = x * 5 + 3
///         x = x ^ 41
///         i = i + 1
///
/// by hand. The body is deliberately OUTSIDE the polynomial grammar (`^`), so
/// alternative A refuses it and only the observation quotient can close it.
const XorLoop = struct {
    n_x: ast.Expr,
    n_i: ast.Expr,
    k5: ast.Expr,
    k3: ast.Expr,
    k41: ast.Expr,
    k1: ast.Expr,
    kbound: ast.Expr,
    mul: ast.Expr,
    add: ast.Expr,
    xor: ast.Expr,
    inc: ast.Expr,
    cond: ast.Expr,
    t_x1: *ast.Expr,
    t_x2: *ast.Expr,
    t_i: *ast.Expr,
    v_add: *ast.Expr,
    v_xor: *ast.Expr,
    v_inc: *ast.Expr,
    stmts: [3]ast.Stmt,

    fn init(self: *XorLoop, bound: i64) void {
        self.n_x = .{ .name = .{ .loc = test_loc, .ident = "x" } };
        self.n_i = .{ .name = .{ .loc = test_loc, .ident = "i" } };
        self.k5 = .{ .int_lit = .{ .loc = test_loc, .val = 5 } };
        self.k3 = .{ .int_lit = .{ .loc = test_loc, .val = 3 } };
        self.k41 = .{ .int_lit = .{ .loc = test_loc, .val = 41 } };
        self.k1 = .{ .int_lit = .{ .loc = test_loc, .val = 1 } };
        self.kbound = .{ .int_lit = .{ .loc = test_loc, .val = bound } };
        self.mul = .{ .binop = .{ .loc = test_loc, .op = .mul, .lhs = &self.n_x, .rhs = &self.k5 } };
        self.add = .{ .binop = .{ .loc = test_loc, .op = .add, .lhs = &self.mul, .rhs = &self.k3 } };
        self.xor = .{ .binop = .{ .loc = test_loc, .op = .bxor, .lhs = &self.n_x, .rhs = &self.k41 } };
        self.inc = .{ .binop = .{ .loc = test_loc, .op = .add, .lhs = &self.n_i, .rhs = &self.k1 } };
        self.cond = .{ .binop = .{ .loc = test_loc, .op = .leq, .lhs = &self.n_i, .rhs = &self.kbound } };
        self.t_x1 = &self.n_x;
        self.t_x2 = &self.n_x;
        self.t_i = &self.n_i;
        self.v_add = &self.add;
        self.v_xor = &self.xor;
        self.v_inc = &self.inc;
        self.stmts = .{
            .{ .assign = .{ .loc = test_loc, .targets = @as(*[1]*ast.Expr, &self.t_x1), .values = @as(*[1]*ast.Expr, &self.v_add) } },
            .{ .assign = .{ .loc = test_loc, .targets = @as(*[1]*ast.Expr, &self.t_x2), .values = @as(*[1]*ast.Expr, &self.v_xor) } },
            .{ .assign = .{ .loc = test_loc, .targets = @as(*[1]*ast.Expr, &self.t_i), .values = @as(*[1]*ast.Expr, &self.v_inc) } },
        };
    }

    fn loop(self: *XorLoop) struct { loc: ast.Loc, cond: *ast.Expr, body: ast.Block } {
        return .{
            .loc = test_loc,
            .cond = &self.cond,
            .body = .{ .loc = test_loc, .stmts = &self.stmts },
        };
    }
};

test "recurrence: a non-polynomial body is refused by A and closed by B" {
    var l: XorLoop = undefined;
    l.init(2000);
    var binds = Bindings{};
    _ = binds.put("x", 1);
    _ = binds.put("i", 1);

    // ALTERNATIVE A MUST REFUSE. `^` is not a ring polynomial operation, so no
    // finite monomial basis exists and the operator-powering route has nothing
    // to raise. If this ever starts succeeding, the polynomial grammar has been
    // widened past what the ring homomorphism argument covers.
    try std.testing.expect(closeWhile(l.loop(), binds) == null);

    // ALTERNATIVE B CLOSES IT — and it must agree with the loop run at FULL
    // 64-bit width on the demanded byte. That agreement IS the h∘f = g∘h claim:
    // the brute force below never reduces, the closure only ever works in 8
    // bits, and they still have to produce the same observation.
    const closed = closeWhileByOrbit(l.loop(), binds, .{ .bits = 8 }).?;
    try std.testing.expectEqual(@as(u64, 2000), closed.trips);
    try std.testing.expectEqual(@as(u7, 8), closed.valid_bits);

    var bx: u64 = 1;
    var bi: i64 = 1;
    while (bi <= 2000) : (bi += 1) {
        bx = bx *% 5 +% 3;
        bx = bx ^ 41;
    }
    try std.testing.expectEqual(bx & 0xFF, closed.get("x").? & 0xFF);
}

test "recurrence: the quotient closure agrees with the full-width loop at every trip count" {
    // SWEEP THE TRIP COUNT ACROSS THE ORBIT'S TAIL AND PERIOD. A cycle-based
    // closure that is right at large T and wrong inside the tail is the exact
    // failure this sweep exists to catch, so the low counts are not decoration.
    for ([_]i64{ 0, 1, 2, 3, 5, 8, 13, 64, 255, 256, 257, 999, 1000, 4095, 65536 }) |bound| {
        var l: XorLoop = undefined;
        l.init(bound);
        var binds = Bindings{};
        _ = binds.put("x", 1);
        _ = binds.put("i", 1);

        var bx: u64 = 1;
        var bi: i64 = 1;
        var trips: u64 = 0;
        while (bi <= bound) : (bi += 1) {
            bx = bx *% 5 +% 3;
            bx = bx ^ 41;
            trips += 1;
        }

        const closed = closeWhileByOrbit(l.loop(), binds, .{ .bits = 8 }) orelse {
            try std.testing.expect(false);
            return;
        };
        try std.testing.expectEqual(trips, closed.trips);
        try std.testing.expectEqual(bx & 0xFF, closed.get("x").? & 0xFF);
    }
}

test "recurrence: the quotient is OFF unless the caller supplies the demand fact" {
    var l: XorLoop = undefined;
    l.init(2000);
    var binds = Bindings{};
    _ = binds.put("x", 1);
    _ = binds.put("i", 1);
    // 64 bits demanded is "everything", and then the quotient cannot help: the
    // state space is 2^128 and no orbit is walkable. It must refuse rather than
    // pretend.
    try std.testing.expect(closeWhileByOrbit(l.loop(), binds, .{ .bits = 64 }) == null);
    try std.testing.expect(closeWhileByOrbit(l.loop(), binds, .{ .bits = 0 }) == null);
    // And the width must leave an injective orbit key: 2 variables at 40 bits
    // each cannot be packed into one 64-bit key, so it refuses rather than
    // collide two distinct states into a false cycle.
    try std.testing.expect(closeWhileByOrbit(l.loop(), binds, .{ .bits = 40 }) == null);
}

test "recurrence: the quotient grammar admits exactly what commutes with the projection" {
    const state = State{};
    const binds = Bindings{};
    var vals: [max_vars]u64 = @splat(0);
    var lit_a = ast.Expr{ .int_lit = .{ .loc = test_loc, .val = 200 } };
    var lit_b = ast.Expr{ .int_lit = .{ .loc = test_loc, .val = 3 } };
    // ADMITTED — each of these is a homomorphism onto Z/2^k.
    inline for (.{ .add, .sub, .mul, .band, .bor, .bxor, .lshift }) |op| {
        const e = ast.Expr{ .binop = .{ .loc = test_loc, .op = op, .lhs = &lit_a, .rhs = &lit_b } };
        try std.testing.expect(quotientEval(&e, &state, &vals, 0xFF, binds, .{ .bits = 8 }) != null);
    }
    // REFUSED — `>>` reads bits the quotient discarded; `/` and `%` are floor
    // operations with no homomorphism to Z/2^k at all. Admitting any of these
    // is the single most likely way to make this pass produce a wrong answer.
    inline for (.{ .rshift, .div, .idiv, .mod, .pow }) |op| {
        const e = ast.Expr{ .binop = .{ .loc = test_loc, .op = op, .lhs = &lit_a, .rhs = &lit_b } };
        try std.testing.expect(quotientEval(&e, &state, &vals, 0xFF, binds, .{ .bits = 8 }) == null);
    }
}

test "recurrence: a body temporary is dead on entry, a read-first name is not" {
    // `t = a + b` writes `t` before anything reads it — its entry value cannot
    // matter, which is what lets the order-2 spelling close.
    var n_a = ast.Expr{ .name = .{ .loc = test_loc, .ident = "a" } };
    var n_b = ast.Expr{ .name = .{ .loc = test_loc, .ident = "b" } };
    var n_t = ast.Expr{ .name = .{ .loc = test_loc, .ident = "t" } };
    var sum = ast.Expr{ .binop = .{ .loc = test_loc, .op = .add, .lhs = &n_a, .rhs = &n_b } };
    var with_t = ast.Expr{ .binop = .{ .loc = test_loc, .op = .add, .lhs = &n_t, .rhs = &n_b } };

    var tgt_t: *ast.Expr = &n_t;
    var val_sum: *ast.Expr = &sum;
    var val_with_t: *ast.Expr = &with_t;

    var write_first = [_]ast.Stmt{
        .{ .assign = .{ .loc = test_loc, .targets = @as(*[1]*ast.Expr, &tgt_t), .values = @as(*[1]*ast.Expr, &val_sum) } },
    };
    const wf = ast.Block{ .loc = test_loc, .stmts = &write_first };
    try std.testing.expect(entryValueIsDead(&wf, "t"));

    // `t = t + b` READS `t` first. Its entry value is live and the loop must be
    // refused rather than given a fabricated zero — this is the direction that
    // would produce a wrong answer.
    var read_first = [_]ast.Stmt{
        .{ .assign = .{ .loc = test_loc, .targets = @as(*[1]*ast.Expr, &tgt_t), .values = @as(*[1]*ast.Expr, &val_with_t) } },
    };
    const rf = ast.Block{ .loc = test_loc, .stmts = &read_first };
    try std.testing.expect(!entryValueIsDead(&rf, "t"));

    // A name never assigned at all is not dead either.
    try std.testing.expect(!entryValueIsDead(&wf, "a"));

    // AND AN UNENUMERATED EXPRESSION FORM COUNTS AS A READ. A subscript could
    // mention the name in a way this walk does not decompose, so it must make
    // the value live; erring the other way is how a fabricated entry value
    // reaches a closed form.
    var idx = ast.Expr{ .index = .{ .loc = test_loc, .obj = &n_a, .key = &n_b } };
    try std.testing.expect(exprMentions(&idx, "nothing-in-here"));
}

test "recurrence: bindings read the LAST write" {
    var b = Bindings{};
    try std.testing.expect(b.put("s", 1));
    try std.testing.expect(b.put("s", 5));
    try std.testing.expectEqual(@as(?u64, 5), b.get("s"));
    try std.testing.expectEqual(@as(?u64, null), b.get("t"));
}
