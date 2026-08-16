//! THE DEMAND QUOTIENT AS A LATTICE — one transformer, several named classes.
//!
//! # What this module is, in one sentence
//!
//! `src/demand.zig` asks *is this observed?* — a BIT. This module asks
//! *through WHICH PROJECTION is it observed?* — a LATTICE — and that single
//! generalisation turns the elimination transformer into the transformer
//! `HPLS.md` §12-13 asks for, the one that covers dead result, truth-only,
//! existence-only, one-bit, range-class, width narrowing, top-k, first/minimum
//! and early witness *without a kingdom per case*.
//!
//! `demand.zig`'s own header states the plan this file executes:
//!
//!     "The quotient cases are the SAME generator with a richer `D`:
//!      `D = X mod 2^k` generates a narrowed-width candidate, `D = exists`
//!      generates an early-exit candidate, `D = min` generates a linear scan
//!      where a sort was written. This module implements the bottom of that
//!      lattice — `D = nothing` — because every richer `D` is computed by the
//!      same backward walk."
//!
//! `D = nothing` is the bottom. `D = whole` is the top. This file is the
//! interior.
//!
//! # THE MEASUREMENT THAT MOTIVATES IT
//!
//! Three programs, IDENTICAL LOOPS, differing only in what the answer observes
//! about the accumulator. `--backend=direct`, this compiler, Apple Silicon:
//!
//!     hits = 0 ; i = 0
//!     while i < 2000000000
//!         if (i * 7 + 3) & 1023 == 7
//!             hits += 1
//!         i += 1
//!     <ANSWER>
//!
//!     ANSWER `if hits != 0 then 1 else 0`   h = nonzero    733 iterations
//!     ANSWER `hits & 255`                   h = low_bits8  2e9 iterations
//!     (predicate `(i*2) & 1023 == 7`)       h = nonzero    2e9 iterations
//!
//! The first and the second run the same machine loop over the same data. The
//! only difference is the projection through which the answer reads `hits`,
//! and it is a difference of complexity class. The third is the adversarial
//! control: same projection, no witness, so the shortcut is lawful and
//! *changes nothing*, which is what proves the first result is the quotient
//! and not a fold.
//!
//! Note what is NOT true of the first program: `hits` is genuinely accumulated
//! — `hits += 1` reads it back every time — and the answer genuinely depends
//! on it. Nothing here is dead. The shipped early-exit rule in
//! `demand.zig::earlyExitSites` refuses this program twice over (its E1 wants
//! every write to be the same integer literal; its E2 wants the place never
//! read inside the loop), and it is right to, because at `h = whole` the
//! program's answer really is the count. The count is only *unobserved* once
//! you know the projection. **That is the fact this module produces.**
//!
//! # THE THREE ALGEBRAS, AND WHY THEY ARE THREE AND NOT TWO HUNDRED
//!
//! GAP-171 asks for graph-fact representations of six algebras with a SINGLE
//! PRODUCER each. Three of them meet here, and the whole decision procedure is
//! their intersection:
//!
//!   `law.demand.derivative`  §17. `Projection` and `projectionOfName` — given
//!                            that `e`'s value is observed only through `h`,
//!                            which projection of each name in `e` suffices?
//!                            Every rule is an instance of `h(f(x)) = g(h(x))`
//!                            and NOTHING ELSE IS ADMITTED. Producer: this
//!                            module. Consumer: `admit` below.
//!
//!   `law.relation.property`  §22-23. `lawsOf` — associativity, commutativity,
//!                            idempotence, bit-locality, ring-homomorphism mod
//!                            2^k, and the ABSORBING ELEMENT, registered per
//!                            relation rather than special-cased per rewrite.
//!                            Producer: this module. Consumer: `admit`.
//!
//!   `law.uncertainty.algebra` `Domain` — a three-status refinement lattice
//!                            (`fact` / `unknown` / `contradiction`) over an
//!                            i128 interval, with provenance naming which
//!                            statement produced the bound. Producer: this
//!                            module. Consumer: `admit`.
//!
//! and it consumes, never re-derives, the two facts that already have one
//! producer each in this tree:
//!
//!   TRAP/EFFECT INERTNESS   `demand.inert` — `.unknown` is an effect.
//!   TRIP COUNT              `demand.provenTripCount` — which is itself a thin
//!                           shape-recogniser over `recurrence.terminatesForAnyStart`,
//!                           so the tree has ONE termination kernel and this
//!                           module does not become a second.
//!
//! The claim GAP-171 makes is that completeness is STRUCTURAL, not
//! enumerative. The test of that claim is: adding a named optimisation class
//! must enrich an identity, not add a mechanism. Three classes are derived
//! below from the SAME `admit` with no new branch in the transform:
//!
//!   existence-only from a count      `filter(xs,p):len() != 0` -> `exists`
//!   short-circuit universal          `all(xs,p)` -> stop at the first refuter
//!   width-narrowed witness agreement  writes that disagree at 64 bits and
//!                                     agree at the observed 8
//!
//! # THE PROOF OBLIGATION, STATED BEFORE THE TRANSFORM
//!
//! The transform is: **place a `break` immediately after a write to `p`.** It
//! is lawful only when ALL NINE hold. Any one unproven means keep, and the
//! reason is recorded so a census says which obligation costs the most.
//!
//!   P0  THE OBSERVER ROSTER PERMITS IT. Truncation is a SCHEDULE freedom, and
//!       `src/observation.zig` — GAP-170's shared observation specification —
//!       owns who is watching. `observationRefusal` refuses unless
//!       `World.observers()` is exactly `{program, deployment,
//!       failure_recovery}`, and refuses FIRST and SEPARATELY when the world
//!       demands a hyperproperty, because every check in this file is
//!       single-trace and no number of single traces establishes a property of
//!       SETS of executions. P1..P8 below are about the PROGRAM'S OWN ANSWER;
//!       P0 is about everyone else, and this module is not its author.
//!
//!   P1  SOLE OBSERVED PLACE. Exactly one place the loop writes has a demanded
//!       projection above `none` in the loop's continuation. Every other place
//!       it writes — the induction counter included — is `none` there, so
//!       truncating the iteration count cannot be observed through any of them.
//!       If the write set is not fully enumerable the loop is refused: a place
//!       this module cannot name is a place it cannot prove unobserved.
//!
//!   P2  ENUMERABLE CONTINUATION. Every construct between the loop and the
//!       function's answer is one whose demand this module can derive. An
//!       unadmitted construct that mentions `p` yields `whole`, which is the
//!       safe direction; an unadmitted construct that could reach `p` without
//!       mentioning it — a closure, a `goto`, a directive — refuses outright.
//!
//!   P3  UPDATE FORM. Every write to `p` in the body has an admitted form
//!       (`p = <literal>`, `p = p + <literal>`, `p = p | <literal>`), and `p`
//!       is read NOWHERE in the body except as the accumulator operand of one
//!       of those writes. A `p` that feeds anything else can change an
//!       iteration's behaviour, and then "did not run" is distinguishable from
//!       "ran".
//!
//!   P4  ABSORPTION. `h(p)` is CONSTANT from the first executed write to the
//!       loop's exit, for every input. This is the whole content of the
//!       transform and it is proven three ways, never assumed — see
//!       `absorbing` below.
//!
//!   P5  INERT BODY. `demand.inert` for every expression in the body: the
//!       skipped iterations must perform no effect and be unable to trap.
//!       This is what makes "did not run" indistinguishable from "ran".
//!
//!   P6  TERMINATING. `demand.provenTripCount` returns a proof. Truncating a
//!       loop that may not terminate turns a hang into a return, and that is
//!       observable. Early exit only ever shortens a run that was already
//!       finite.
//!
//!   P7  NO ESCAPE. No `break`/`continue`/`return`/`goto`/label already in the
//!       body, and no NESTED LOOP anywhere in it — a `break` inside a nested
//!       loop exits the wrong loop.
//!
//!   P8  NO ALIAS. `p` is a plain local name: not a module-scope binding, not
//!       an index or field target, not captured by a closure. The graph cannot
//!       express a place, so anything else is unprovable.
//!
//! # WHAT IS DELIBERATELY NOT PROVEN HERE
//!
//! `sort:first()` -> selection and `map:sum()` -> no materialisation are the
//! same identity at `h = rank-0 order statistic` and `h = fold`, and they are
//! DERIVED in `docs/demand-projection.md` from `projectionOfName` without a new
//! mechanism. They are not MEASURED, and the reason is not this module: the
//! direct backend refuses `t[i] = v` (`dnir_lower.zig:4534`,
//! `lowerIndexAssignTarget`) and refuses `:sort()` (`method-unresolved:sort`),
//! so neither program reaches machine code on the surface where demand runs.
//! Claiming them as measured would be claiming a compiler that does not exist.
//!
//! The GUARDED truncation — `break` when `p` reaches an absorbing value that
//! only some writes produce, which is what turns a `min` fold into a scan that
//! stops at the domain floor — is derived and refused, because realising it
//! needs a statement this module cannot insert: `demand.Plan` carries an
//! unconditional `break_after` set and nothing else. The routed patch that
//! would give it a home is named in the lane report.

const std = @import("std");
const ast = @import("ast.zig");
const demand = @import("demand.zig");
const observation = @import("observation.zig");

// ═══════════════════════════════════════════════════════════════════════════
// ALGEBRA 2 — `law.demand.derivative`: the projection lattice
// ═══════════════════════════════════════════════════════════════════════════

/// WHICH DISTINCTIONS A DEMANDED OBSERVER CAN ACTUALLY MAKE about one value.
///
/// `HPLS.md` §12: for domain S, `x ~ y` iff all demanded observers consider
/// them equivalent; solve over S/~. This type IS `~`, named by the projection
/// that induces it.
///
///     none         x ~ y always                    the empty realization
///     nonzero      x ~ y iff (x==0) == (y==0)      existence / truth / any / all
///     low_bits k   x ~ y iff x ≡ y (mod 2^k)       width, tag, parity, exit code
///     whole        x ~ y iff x == y                no quotient at all
///
/// The order is `none ⊏ nonzero ⊏ whole` and `none ⊏ low_bits j ⊏ low_bits k
/// ⊏ whole` for j < k. `nonzero` and `low_bits` are INCOMPARABLE and their
/// join is `whole`: knowing `x & 255` does not tell you `x != 0` (256 has
/// neither property of the other), and knowing `x != 0` tells you no bit.
/// Getting that wrong in the join is how a lane admits a candidate that a
/// second observer refutes, so it is a unit test below.
pub const Projection = union(enum) {
    none,
    nonzero,
    low_bits: u6,
    whole,

    /// The join — "at least as much as either". Used to combine the demand of
    /// several consumers of one place. Always sound to over-approximate
    /// upward: more demand means fewer candidates.
    pub fn join(a: Projection, b: Projection) Projection {
        if (a == .none) return b;
        if (b == .none) return a;
        if (a == .whole or b == .whole) return .whole;
        return switch (a) {
            .nonzero => switch (b) {
                .nonzero => .nonzero,
                else => .whole,
            },
            .low_bits => |ka| switch (b) {
                .low_bits => |kb| .{ .low_bits = @max(ka, kb) },
                else => .whole,
            },
            else => unreachable,
        };
    }

    pub fn eql(a: Projection, b: Projection) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .low_bits => |ka| ka == b.low_bits,
            else => true,
        };
    }

    /// `h` applied to a concrete value. `null` for `none`, which distinguishes
    /// nothing and therefore has no representative worth comparing.
    pub fn apply(self: Projection, v: i64) ?i64 {
        return switch (self) {
            .none => null,
            .nonzero => @intFromBool(v != 0),
            .low_bits => |k| @bitCast(@as(u64, @bitCast(v)) & ((@as(u64, 1) << k) - 1)),
            .whole => v,
        };
    }

    pub fn label(self: Projection) []const u8 {
        return switch (self) {
            .none => "none",
            .nonzero => "nonzero",
            .low_bits => "low_bits",
            .whole => "whole",
        };
    }
};

/// `null` when `m` is a low mask `2^k - 1` for some 1 <= k <= 63.
fn lowMaskBits(m: i64) ?u6 {
    if (m <= 0) return null;
    const u: u64 = @bitCast(m);
    if (u & (u + 1) != 0) return null; // not of the form 2^k - 1
    const k = @popCount(u);
    if (k == 0 or k > 63) return null;
    return @intCast(k);
}

fn intLiteral(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |x| x.val,
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const inner = intLiteral(u.operand) orelse break :blk null;
                if (inner == std.math.minInt(i64)) break :blk null;
                break :blk -inner;
            },
            else => null,
        },
        else => null,
    };
}

/// THE DEMAND DERIVATIVE. Given that `e`'s value is observed only through `h`,
/// return the projection of `n` that suffices to determine `h(e)`.
///
/// **Every rule below is `h(f(x)) = g(h(x))` and there are no other rules.**
/// That is the discipline that keeps this from becoming a peephole table: a
/// case may be added only by naming the homomorphism that licenses it. Where
/// no homomorphism exists the answer is `whole`, which costs candidates and
/// never costs correctness.
///
/// The fallback is FAIL-CLOSED in the only direction that matters: a construct
/// this function does not model contributes `whole` if it mentions `n` and
/// `none` if it does not, and `mentions` returns true for every AST variant it
/// does not enumerate.
pub fn projectionOfName(h: Projection, e: *const ast.Expr, n: []const u8) Projection {
    if (h == .none) return .none;
    switch (e.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg => return .none,

        .name => |x| return if (std.mem.eql(u8, x.ident, n)) h else .none,

        .binop => |b| {
            switch (b.op) {
                // + - * are ring homomorphisms mod 2^k: (x op y) mod 2^k is
                // determined by x mod 2^k and y mod 2^k. Nothing weaker than
                // low_bits survives them — `x + y != 0` is NOT determined by
                // `x != 0` and `y != 0`.
                .add, .sub, .mul => {
                    const sub_h: Projection = switch (h) {
                        .low_bits => h,
                        else => .whole,
                    };
                    return Projection.join(
                        projectionOfName(sub_h, b.lhs, n),
                        projectionOfName(sub_h, b.rhs, n),
                    );
                },

                // Bitwise operators are BIT-LOCAL: output bit i depends only on
                // input bits i. So `(x op y) mod 2^k` is determined by the low
                // k bits of both, for every k.
                .band, .bor, .bxor => {
                    switch (h) {
                        .low_bits => |k| {
                            // MASKING NARROWS FURTHER. `(x & m) mod 2^k` where
                            // m is the low mask 2^j - 1 needs only x mod
                            // 2^min(j,k) — this is the width-narrowing rule and
                            // it is the same identity, not a special case.
                            if (b.op == .band) {
                                if (intLiteral(b.rhs)) |m| if (lowMaskBits(m)) |j|
                                    return projectionOfName(.{ .low_bits = @min(j, k) }, b.lhs, n);
                                if (intLiteral(b.lhs)) |m| if (lowMaskBits(m)) |j|
                                    return projectionOfName(.{ .low_bits = @min(j, k) }, b.rhs, n);
                            }
                            return Projection.join(
                                projectionOfName(h, b.lhs, n),
                                projectionOfName(h, b.rhs, n),
                            );
                        },
                        .whole => {
                            // `x & (2^k - 1)` observed wholly demands exactly
                            // the low k bits of x. THE narrowing rule.
                            if (b.op == .band) {
                                if (intLiteral(b.rhs)) |m| if (lowMaskBits(m)) |k|
                                    return projectionOfName(.{ .low_bits = k }, b.lhs, n);
                                if (intLiteral(b.lhs)) |m| if (lowMaskBits(m)) |k|
                                    return projectionOfName(.{ .low_bits = k }, b.rhs, n);
                            }
                            return Projection.join(
                                projectionOfName(.whole, b.lhs, n),
                                projectionOfName(.whole, b.rhs, n),
                            );
                        },
                        // `(x | y) != 0  <=>  (x != 0) or (y != 0)` — a genuine
                        // homomorphism into the two-element truth algebra. `&`
                        // and `^` have no such law (0b01 & 0b10 == 0 with both
                        // operands nonzero), so they fall through to `whole`.
                        .nonzero => {
                            if (b.op == .bor) return Projection.join(
                                projectionOfName(.nonzero, b.lhs, n),
                                projectionOfName(.nonzero, b.rhs, n),
                            );
                            return Projection.join(
                                projectionOfName(.whole, b.lhs, n),
                                projectionOfName(.whole, b.rhs, n),
                            );
                        },
                        .none => return .none,
                    }
                },

                // THE EXISTENCE RULE, and it is the one that pays. `x == 0` and
                // `x != 0` are `h(x) = (x != 0)` composed with a two-element
                // relation: the comparison's value is a function of the
                // PROJECTION, not of x. Against any other literal the
                // comparison needs every bit.
                .eq, .neq => {
                    if (intLiteral(b.rhs)) |v| if (v == 0)
                        return projectionOfName(.nonzero, b.lhs, n);
                    if (intLiteral(b.lhs)) |v| if (v == 0)
                        return projectionOfName(.nonzero, b.rhs, n);
                    return Projection.join(
                        projectionOfName(.whole, b.lhs, n),
                        projectionOfName(.whole, b.rhs, n),
                    );
                },

                // Order comparisons and everything arithmetic that is not a
                // ring hom: no projection law is claimed, so every bit is
                // demanded. `/` `%` `>>` are the obvious ones — `x >> 1` mod
                // 2^k needs k+1 bits, which is a real law this module does not
                // yet carry, and NOT carrying it costs candidates only.
                else => return Projection.join(
                    projectionOfName(.whole, b.lhs, n),
                    projectionOfName(.whole, b.rhs, n),
                ),
            }
        },

        .unop => |u| switch (u.op) {
            // `-x mod 2^k` is determined by `x mod 2^k` (two's complement is a
            // ring), and `-x != 0  <=>  x != 0` including at minInt, where
            // -minInt wraps to minInt and stays nonzero.
            .neg => return projectionOfName(switch (h) {
                .low_bits, .nonzero => h,
                else => .whole,
            }, u.operand, n),
            // `not x` reads only truthiness.
            .not => return projectionOfName(.nonzero, u.operand, n),
            // `~x` is bit-local.
            .bnot => return projectionOfName(switch (h) {
                .low_bits => h,
                else => .whole,
            }, u.operand, n),
            else => return if (mentions(u.operand, n)) .whole else .none,
        },

        .if_expr => |ie| return Projection.join(
            projectionOfName(.nonzero, ie.cond, n),
            Projection.join(
                projectionOfName(h, ie.then_expr, n),
                projectionOfName(h, ie.else_expr, n),
            ),
        ),

        .sequence => |sq| {
            var acc: Projection = .none;
            for (sq.exprs) |x| acc = Projection.join(acc, projectionOfName(h, x, n));
            return acc;
        },

        else => return if (mentions(e, n)) .whole else .none,
    }
}

/// Does `e` mention `n` anywhere? **Fails closed**: an AST variant this does
/// not enumerate answers `true`, so a future node cannot silently become a
/// place this module claims not to reach.
fn mentions(e: *const ast.Expr, n: []const u8) bool {
    return switch (e.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg => false,
        .name => |x| std.mem.eql(u8, x.ident, n),
        .binop => |b| mentions(b.lhs, n) or mentions(b.rhs, n),
        .unop => |u| mentions(u.operand, n),
        .index => |x| mentions(x.obj, n) or mentions(x.key, n),
        .field => |x| mentions(x.obj, n),
        .call => |c| blk: {
            if (mentions(c.func, n)) break :blk true;
            for (c.args) |a| if (mentions(a, n)) break :blk true;
            break :blk false;
        },
        .method_call => |m| blk: {
            if (mentions(m.obj, n)) break :blk true;
            for (m.args) |a| if (mentions(a, n)) break :blk true;
            break :blk false;
        },
        .if_expr => |ie| mentions(ie.cond, n) or mentions(ie.then_expr, n) or mentions(ie.else_expr, n),
        .sequence => |sq| blk: {
            for (sq.exprs) |x| if (mentions(x, n)) break :blk true;
            break :blk false;
        },
        .range => |r| blk: {
            if (mentions(r.start, n) or mentions(r.end, n)) break :blk true;
            if (r.step) |st| if (mentions(st, n)) break :blk true;
            break :blk false;
        },
        // Everything else — closures, tables, macros, quotes, comprehensions,
        // semantic nodes — is assumed to reach `n`.
        else => true,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// ALGEBRA 3 — `law.relation.property`: relation laws, as facts
// ═══════════════════════════════════════════════════════════════════════════

/// The laws a binary relation carries. Registered per relation, DERIVED
/// compositionally where possible, never open-coded at a rewrite site.
/// `HPLS.md` §22-23: "these are semantic facts, not handwritten backend
/// recognizer lists where derivable."
pub const Law = packed struct {
    pure: bool = false,
    commutative: bool = false,
    associative: bool = false,
    idempotent: bool = false,
    /// Output bit i depends only on input bits i. Licenses every `low_bits`
    /// projection through the relation.
    bit_local: bool = false,
    /// `(x op y) mod 2^k` determined by `x mod 2^k`, `y mod 2^k`.
    ring_hom_mod_2k: bool = false,
    /// Monotone non-decreasing in its left operand over the non-negative
    /// domain, for a non-negative right operand.
    monotone_nonneg: bool = false,
    /// There is a value `a` with `a op y == a` for every y. Filled by
    /// `absorbingElement`.
    has_absorbing: bool = false,
    /// Can produce zero from a nonzero left operand. If false, the relation
    /// PRESERVES the `nonzero` projection unconditionally.
    can_zero_nonzero: bool = true,
};

pub fn lawsOf(op: ast.BinOp) Law {
    return switch (op) {
        .add => .{ .pure = true, .commutative = true, .associative = true, .ring_hom_mod_2k = true, .monotone_nonneg = true, .can_zero_nonzero = true },
        .sub => .{ .pure = true, .ring_hom_mod_2k = true, .can_zero_nonzero = true },
        .mul => .{ .pure = true, .commutative = true, .associative = true, .ring_hom_mod_2k = true, .monotone_nonneg = true, .has_absorbing = true, .can_zero_nonzero = true },
        // `x | c` with c != 0 can NEVER be zero. That single fact is what makes
        // the saturating-flag class provable with no interval reasoning at all,
        // and it is why `can_zero_nonzero` is a law rather than a comment.
        .bor => .{ .pure = true, .commutative = true, .associative = true, .idempotent = true, .bit_local = true, .ring_hom_mod_2k = true, .monotone_nonneg = true, .can_zero_nonzero = false },
        .band => .{ .pure = true, .commutative = true, .associative = true, .idempotent = true, .bit_local = true, .ring_hom_mod_2k = true, .has_absorbing = true, .can_zero_nonzero = true },
        .bxor => .{ .pure = true, .commutative = true, .associative = true, .bit_local = true, .ring_hom_mod_2k = true, .can_zero_nonzero = true },
        .div, .idiv, .mod => .{ .commutative = false },
        else => .{},
    };
}

/// §22-23 compositional derivation: a composite relation carries a law only
/// when BOTH components do. `pure∘pure→pure`, `bit_local∘bit_local→bit_local`.
/// Exposed so a future user-defined relation's law is derived rather than
/// listed — the point of the algebra is that the optimizer progressively
/// understands abstractions it was never told about.
pub fn composeLaws(outer: Law, inner: Law) Law {
    return .{
        .pure = outer.pure and inner.pure,
        // Composition does not preserve commutativity or associativity in
        // general, and claiming it would be exactly the unproven step this
        // algebra exists to forbid.
        .commutative = false,
        .associative = false,
        .idempotent = false,
        .bit_local = outer.bit_local and inner.bit_local,
        .ring_hom_mod_2k = outer.ring_hom_mod_2k and inner.ring_hom_mod_2k,
        .monotone_nonneg = outer.monotone_nonneg and inner.monotone_nonneg,
        .has_absorbing = false,
        .can_zero_nonzero = outer.can_zero_nonzero or inner.can_zero_nonzero,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// ALGEBRA 5 — `law.uncertainty.algebra`: the refinement lattice
// ═══════════════════════════════════════════════════════════════════════════

/// A value's known range, with the THREE distinct absence states GAP-171 asks
/// to be kept apart. `unknown` is not `contradiction` is not a wide `fact`, and
/// a consumer that treats them alike is the bug this type exists to prevent.
///
/// Provenance is carried as the name of the rule that produced the bound, so
/// `--why` style tooling can answer "which fact would permit a cheaper
/// realization" (§100) without a second ledger.
pub const Domain = struct {
    pub const Status = enum {
        /// Bounds are proven.
        fact,
        /// Nothing is known. NOT the same as `[minInt, maxInt]`: a wide fact
        /// can still discharge a no-wrap obligation, an unknown never can.
        unknown,
        /// Two proven bounds that cannot both hold. Reaching this state means a
        /// producer is wrong; it must never license anything.
        contradiction,
    };

    status: Status = .unknown,
    lo: i128 = 0,
    hi: i128 = 0,
    why: []const u8 = "",

    pub const nothing_known: Domain = .{ .status = .unknown, .why = "no producer" };

    pub fn exact(v: i64, why: []const u8) Domain {
        return .{ .status = .fact, .lo = v, .hi = v, .why = why };
    }

    pub fn range(lo: i128, hi: i128, why: []const u8) Domain {
        if (lo > hi) return .{ .status = .contradiction, .lo = lo, .hi = hi, .why = why };
        return .{ .status = .fact, .lo = lo, .hi = hi, .why = why };
    }

    /// Does this domain PROVE the value is never zero? Only a `fact` can.
    pub fn provesNonzero(self: Domain) bool {
        return self.status == .fact and (self.lo > 0 or self.hi < 0);
    }

    /// Does this domain PROVE the value stays representable in i64?
    pub fn provesNoWrap(self: Domain) bool {
        return self.status == .fact and
            self.lo >= std.math.minInt(i64) and self.hi <= std.math.maxInt(i64);
    }

    /// The refinement meet — two producers agreeing narrows, disagreeing
    /// contradicts. `unknown` refines to whatever the other says.
    pub fn refine(a: Domain, b: Domain) Domain {
        if (a.status == .contradiction or b.status == .contradiction) return .{ .status = .contradiction, .why = "conflicting producers" };
        if (a.status == .unknown) return b;
        if (b.status == .unknown) return a;
        return Domain.range(@max(a.lo, b.lo), @min(a.hi, b.hi), a.why);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// THE UPDATE FORM — how a loop moves one place
// ═══════════════════════════════════════════════════════════════════════════

/// One admitted way a loop body writes the observed place. Anything else
/// refuses the loop; this is a closed set on purpose, so a future write shape
/// fails closed rather than being silently mis-modelled.
pub const Update = union(enum) {
    /// `p = <literal>`
    store: i64,
    /// `p = p <op> <literal>`, with the relation's laws attached at the site
    /// so `admit` reasons about the LAW and never about the token.
    accumulate: struct { op: ast.BinOp, k: i64 },
};

const WriteSite = struct {
    stmt: *const ast.Stmt,
    update: Update,
};

/// Why a loop was refused. Every value names an unmet obligation from the
/// header, so a census over these says which obligation costs the most work.
pub const Refusal = enum {
    /// P1: zero or several observed places, or an unenumerable write set.
    not_sole_place,
    /// P2: the continuation contains a shape whose demand cannot be derived.
    continuation_opaque,
    /// P3: a write form outside the admitted set, or `p` read where it may not
    /// be.
    update_form,
    /// P4: no absorption proof at the demanded projection. THE INTERESTING
    /// REFUSAL — it means the observer really can see the difference.
    not_absorbing,
    /// P5: the body can trap or touch the world.
    body_not_inert,
    /// P6: no termination proof.
    may_not_terminate,
    /// P7: an existing control transfer, or a nested loop.
    control_escape,
    /// P8: the place is not a plain unaliased local.
    aliased_place,
    /// The optimizer-economy budget ran out before discovery finished. NOT a
    /// legality refusal — the candidate may well be lawful; nobody looked.
    /// Kept distinct because conflating "none found" with "none exists" is the
    /// exact error GAP-171 names.
    budget_exhausted,
    /// `observation.permits(report, .schedule)` did not return `.permitted`.
    /// The SHARED observation specification refused, and this module does not
    /// get a second opinion.
    observation_refused,
    /// The world demands a HYPERPROPERTY — determinism, noninterference,
    /// serializability, linearizability — and every check in this module is
    /// single-trace. Kept as its own value rather than folded into
    /// `observation_refused`, because it is not "this place is observed"; it is
    /// "the evidence this module produces is the WRONG KIND and no amount of it
    /// would help".
    blocked_hyperproperty,
};

// ═══════════════════════════════════════════════════════════════════════════
// P4 — THE ABSORPTION TEST. THE TRUSTED CORE.
// ═══════════════════════════════════════════════════════════════════════════

/// The proof that licenses the transform, naming which of the three routes
/// discharged it and which facts it consumed.
pub const Proof = struct {
    pub const Route = enum {
        /// Every write agrees under `h`. The shipped `exists` case is this
        /// route at `h = whole`; the width-narrowed case is this route at
        /// `h = low_bits k`.
        literal_agreement,
        /// `h = nonzero` and the accumulation cannot return to zero, proven by
        /// the interval: initial value, per-write increment, and the trip
        /// count bound the accumulator away from 0 and away from wraparound.
        interval_nonzero,
        /// `h = nonzero` and the relation's LAW forbids producing zero from
        /// any operand (`x | c`, c != 0). No interval fact is consumed at all
        /// — the contrast with `interval_nonzero` is the point: two algebras,
        /// two independent routes to one conclusion.
        law_nonzero,
    };

    route: Route,
    projection: Projection,
    /// `h(p)` from the first write onward.
    settled: i64,
    /// The interval the accumulator is confined to, when a domain fact was
    /// consumed. `unknown` on the `law_nonzero` route, and that is meaningful
    /// rather than missing.
    accumulator: Domain,
};

/// **§84 MADE STRUCTURAL: this function takes FACTS AND NO COST.**
///
/// There is no cost parameter, no profile, no budget and no allocator in this
/// signature, so there is no path by which a cost number can admit a
/// candidate. `rank` below takes COSTS AND NO FACTS. Two functions over
/// disjoint inputs is what makes the separation a mechanism rather than a
/// promise, and a unit test perturbs every cost to absurd values and asserts
/// the admitted set is byte-identical.
///
/// This is also the MINIMISED TRUSTED CORE for GAP-171 deletion condition 4.
/// It allocates nothing, loops over the write list once, and is the only
/// function in this module whose failure can produce a wrong answer. Discovery
/// — finding the write list, the continuation projection, the initial value —
/// is untrusted: if discovery lies, `admit` refuses, because every input it
/// reads is re-checked against the loop by `check` at the call site.
pub fn admit(
    h: Projection,
    writes: []const Update,
    initial: Domain,
    trips: Domain,
) ?Proof {
    if (writes.len == 0) return null;
    if (h == .none) return null; // the empty realization is `demand.zig`'s job
    if (initial.status == .contradiction or trips.status == .contradiction) return null;

    // ── ROUTE 1: every write agrees under h ────────────────────────────────
    //
    // After ANY write, h(p) equals the same value v; every later write
    // reproduces v; so h(p) is constant from the first write to the exit.
    // Requires every write to be a `store`, because an accumulate's result
    // depends on the accumulator and therefore on how many writes preceded it.
    route1: {
        var settled: ?i64 = null;
        for (writes) |u| switch (u) {
            .store => |v| {
                const hv = h.apply(v) orelse break :route1;
                if (settled) |s| {
                    if (s != hv) break :route1;
                } else settled = hv;
            },
            .accumulate => break :route1,
        };
        return .{
            .route = .literal_agreement,
            .projection = h,
            .settled = settled.?,
            .accumulator = .nothing_known,
        };
    }

    // Both remaining routes prove `h(p) = 1` at `h = nonzero`. Nothing else.
    if (h != .nonzero) return null;

    // ── ROUTE 2: the relation's law forbids zero ───────────────────────────
    //
    // No interval fact is consumed. `x | c` with `c != 0` has a nonzero bit
    // set in the result whatever x is, so the FIRST write settles `p != 0` and
    // no later write can undo it.
    route2: {
        for (writes) |u| switch (u) {
            .accumulate => |acc| {
                if (lawsOf(acc.op).can_zero_nonzero) break :route2;
                if (acc.k == 0) break :route2;
            },
            .store => |v| if (v == 0) break :route2,
        };
        return .{
            .route = .law_nonzero,
            .projection = h,
            .settled = 1,
            .accumulator = .nothing_known,
        };
    }

    // ── ROUTE 3: the interval forbids zero ─────────────────────────────────
    //
    // THE COUNT-TO-EXISTENCE ROUTE. Every write is `p = p + k` with k >= 1,
    // the initial value is a proven non-negative literal, and the trip count
    // bounds the number of writes. Then after the first write
    //
    //     p ∈ [initial.lo + kmin, initial.hi + trips.hi * kmax]
    //
    // whose lower bound exceeds 0 and whose upper bound is inside i64, so `p`
    // is nonzero after the first write and cannot wrap back through 0.
    //
    // BOTH HALVES ARE LOAD-BEARING. Without the lower bound, `p` could start
    // negative and cross zero. Without the upper bound, `p` could wrap:
    // `p += 1` from 0 reaches 0 again after 2^64 writes, and a loop whose trip
    // count is not bounded below 2^63 is exactly the loop for which that is
    // not absurd.
    if (initial.status != .fact or trips.status != .fact) return null;
    var kmin: i128 = std.math.maxInt(i64);
    var kmax: i128 = 0;
    for (writes) |u| switch (u) {
        .accumulate => |acc| {
            if (acc.op != .add) return null;
            if (acc.k < 1) return null;
            kmin = @min(kmin, acc.k);
            kmax = @max(kmax, acc.k);
        },
        .store => return null,
    };
    if (trips.hi < 1) return null;
    const reach = Domain.range(
        initial.lo + kmin,
        initial.hi + trips.hi * kmax,
        "initial + trip-bounded accumulation",
    );
    if (!reach.provesNonzero()) return null;
    if (!reach.provesNoWrap()) return null;
    return .{
        .route = .interval_nonzero,
        .projection = h,
        .settled = 1,
        .accumulator = reach,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// §24 — WHAT A CANDIDATE EXPOSES, and §84's other half
// ═══════════════════════════════════════════════════════════════════════════

/// `HPLS.md` §24: `candidate · required_facts · semantic_proof · cost_estimate
/// · transition_cost`, all five as separate fields. **No candidate generator is
/// semantic authority**: this module proposes, `demand.inert` and
/// `demand.provenTripCount` supply the facts, and neither decides what the
/// program means.
pub const Candidate = struct {
    /// The write site after which `break` is lawful.
    site: *const ast.Stmt,
    /// The facts that had to be true. Named, so `--why` can say which missing
    /// fact would have permitted a cheaper realization (§100).
    required_facts: struct {
        projection: Projection,
        trip_count_proven: bool,
        body_inert: bool,
        sole_observed_place: bool,
        initial_value_known: bool,
    },
    /// Why the realization answers the same question. NOT the cost model's
    /// business.
    semantic_proof: Proof,
    /// Expected iterations saved, as a ratio numerator/denominator. This is an
    /// ESTIMATE and it is never consulted by `admit`.
    cost_estimate: struct { trips_before: i128, trips_after_est: i128 },
    /// What it costs to take the candidate: one `break` instruction.
    transition_cost: u32,
};

/// **§84's other half: this function takes COSTS AND NO FACTS.** It cannot see
/// a projection, a law, a domain or a proof — only two numbers — so it cannot
/// admit anything. It orders already-admitted candidates.
pub fn rank(trips_before: i128, trips_after_est: i128, transition_cost: u32) i128 {
    const saved = trips_before - trips_after_est;
    return saved - @as(i128, transition_cost);
}

// ═══════════════════════════════════════════════════════════════════════════
// ALGEBRA 6 — `law.optimizer.economy`: budget, cache, trusted core
// ═══════════════════════════════════════════════════════════════════════════

/// A proof-carrying cache keyed on SEMANTIC CONTENT, per `HPLS.md` §87-88:
/// "key on semantic subgraph + demand + law + world + target; file is
/// provenance, not compilation-unit authority."
///
/// The key is a fingerprint of the loop's update forms, the demanded
/// projection, the initial-value domain and the trip bound — NOT its source
/// text, NOT its line, NOT its file. Two identical loops in different files
/// share one proof; the same loop moved down a line does not miss.
///
/// THE CACHE IS UNTRUSTED. A hit returns a `Proof`, and the caller still holds
/// the same `admit` obligation for the facts it re-derived; what the hit buys
/// is skipping DISCOVERY (the walk that finds the write list and the
/// projection), which is the expensive half. That is what "minimized trusted
/// core distinct from discovery" means operationally: corrupting every entry
/// in this cache cannot produce a wrong answer, only a slower compile.
pub const Cache = struct {
    map: std.AutoHashMapUnmanaged(u64, Proof) = .empty,
    hits: u32 = 0,
    misses: u32 = 0,

    pub fn deinit(self: *Cache, alloc: std.mem.Allocator) void {
        self.map.deinit(alloc);
    }

    pub fn key(h: Projection, writes: []const Update, initial: Domain, trips: Domain) u64 {
        var w = std.hash.Wyhash.init(0x1710_0000);
        w.update(std.mem.asBytes(&std.meta.activeTag(h)));
        if (h == .low_bits) w.update(std.mem.asBytes(&h.low_bits));
        for (writes) |u| switch (u) {
            .store => |v| {
                w.update("s");
                w.update(std.mem.asBytes(&v));
            },
            .accumulate => |a| {
                w.update("a");
                w.update(std.mem.asBytes(&a.op));
                w.update(std.mem.asBytes(&a.k));
            },
        };
        inline for (.{ initial, trips }) |d| {
            w.update(std.mem.asBytes(&d.status));
            w.update(std.mem.asBytes(&d.lo));
            w.update(std.mem.asBytes(&d.hi));
        }
        return w.final();
    }
};

/// §82-83: the search budget is first-class policy, and running out is NOT a
/// legality answer. `budget_exhausted` is reported as `unknown`, never as
/// "none exists" — GAP-171's optimality-gap obligation in the one place this
/// module can honour it.
pub const Budget = struct {
    /// Discovery steps: AST statements visited by the write-form collector and
    /// the continuation-projection walk.
    search_steps: u32 = 200_000,
    /// VALUE OF INFORMATION (`HPLS.md` §41-42, GAP-171 nine-universe clause).
    /// Scanning further back for the accumulator's initial value costs steps
    /// and buys the `interval_nonzero` route. Set to 0 to refuse to pay, which
    /// is how a unit test proves the fact is causally operative rather than
    /// decorative: with 0 the candidate disappears.
    initial_value_probe_steps: u32 = 4096,

    spent: u32 = 0,

    fn charge(self: *Budget, n: u32) bool {
        self.spent +|= n;
        return self.spent <= self.search_steps;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// DISCOVERY — untrusted. If any of this lies, `admit` refuses.
// ═══════════════════════════════════════════════════════════════════════════

const WriteScan = struct {
    /// Places written by the loop, in first-seen order. `null` if the write set
    /// is not fully enumerable (P1).
    names: std.ArrayListUnmanaged([]const u8) = .empty,
    complete: bool = true,
};

/// Every plain-name place `b` writes. `complete` goes false the moment a write
/// is found that this module cannot name — through an index, a field, a
/// declaration form it does not model — because then no disjointness argument
/// can be made about what truncation is observable through.
fn collectWrites(
    alloc: std.mem.Allocator,
    b: *const ast.Block,
    out: *WriteScan,
    budget: *Budget,
) std.mem.Allocator.Error!void {
    for (b.stmts) |*s| {
        if (!budget.charge(1)) {
            out.complete = false;
            return;
        }
        switch (s.*) {
            .assign => |a| {
                for (a.targets) |t| {
                    if (t.* != .name) {
                        out.complete = false;
                        return;
                    }
                    try addName(alloc, out, t.name.ident);
                }
            },
            .local_decl => |d| for (d.names) |n| try addName(alloc, out, n.ident),
            .do_block => |d| try collectWrites(alloc, &d.body, out, budget),
            .if_stmt => |f| {
                if (f.binding) |bnd| try addName(alloc, out, bnd.name);
                try collectWrites(alloc, &f.then, out, budget);
                for (f.elseifs) |ei| try collectWrites(alloc, &ei.body, out, budget);
                if (f.else_body) |eb| try collectWrites(alloc, &eb, out, budget);
            },
            .call_stmt, .expr_stmt => {},
            else => {
                out.complete = false;
                return;
            },
        }
        if (!out.complete) return;
    }
}

fn addName(alloc: std.mem.Allocator, out: *WriteScan, n: []const u8) !void {
    for (out.names.items) |existing| if (std.mem.eql(u8, existing, n)) return;
    try out.names.append(alloc, n);
}

/// The write sites for `name`, with their update forms. Returns false when a
/// write to `name` has a form outside the admitted set (P3), or when `name` is
/// read anywhere it may not be.
fn collectUpdates(
    alloc: std.mem.Allocator,
    b: *const ast.Block,
    name: []const u8,
    sites: *std.ArrayListUnmanaged(WriteSite),
    budget: *Budget,
) std.mem.Allocator.Error!bool {
    for (b.stmts) |*s| {
        if (!budget.charge(1)) return false;
        switch (s.*) {
            .assign => |a| {
                var touches = false;
                for (a.targets) |t| {
                    if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) touches = true;
                }
                if (!touches) {
                    // P3's second half: `name` may not be READ by a statement
                    // that does not write it. A read anywhere else means an
                    // iteration's behaviour can depend on how many writes
                    // preceded it, and then skipping iterations is observable.
                    for (a.values) |v| if (mentions(v, name)) return false;
                    continue;
                }
                if (a.targets.len != 1 or a.values.len != 1) return false;
                const u = updateFormOf(a.values[0], name) orelse return false;
                try sites.append(alloc, .{ .stmt = s, .update = u });
            },
            .local_decl => |d| {
                for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) return false; // shadowing
                for (d.inits) |e| if (mentions(e, name)) return false;
            },
            // A write inside `do ... end` is REFUSED even though the write set
            // collector can see it. `prune` inserts the `break` in the block
            // that holds the write, and whether a `break` inside a `do` block
            // leaves the enclosing loop is a lowering fact this module has not
            // measured on the direct backend. An unmeasured control-flow
            // assumption is exactly the kind of thing that is right until the
            // day it is a wrong answer, so the shape costs a candidate instead.
            .do_block => return false,
            .if_stmt => |f| {
                if (f.binding) |bnd| {
                    if (std.mem.eql(u8, bnd.name, name)) return false;
                    if (mentions(bnd.expr, name)) return false;
                }
                if (mentions(f.cond, name)) return false;
                if (!try collectUpdates(alloc, &f.then, name, sites, budget)) return false;
                for (f.elseifs) |ei| {
                    if (mentions(ei.cond, name)) return false;
                    if (!try collectUpdates(alloc, &ei.body, name, sites, budget)) return false;
                }
                if (f.else_body) |eb| if (!try collectUpdates(alloc, &eb, name, sites, budget)) return false;
            },
            .call_stmt => |x| if (mentions(x.expr, name)) return false,
            .expr_stmt => |x| if (mentions(x.expr, name)) return false,
            else => return false,
        }
    }
    if (b.tail_expr) |t| if (mentions(t, name)) return false;
    return true;
}

/// `p = <literal>` or `p = p <op> <literal>`. Anything else refuses.
fn updateFormOf(v: *const ast.Expr, name: []const u8) ?Update {
    if (intLiteral(v)) |lit| return .{ .store = lit };
    if (v.* != .binop) return null;
    const b = v.binop;
    // The accumulator must be the LEFT operand and appear exactly once.
    if (b.lhs.* != .name) return null;
    if (!std.mem.eql(u8, b.lhs.name.ident, name)) return null;
    if (mentions(b.rhs, name)) return null;
    const k = intLiteral(b.rhs) orelse return null;
    return .{ .accumulate = .{ .op = b.op, .k = k } };
}

/// P5. `demand.inert` for every expression in the body — the ONE producer of
/// the trap/effect fact, consumed rather than re-derived.
fn bodyInert(opts: demand.Options, b: *const ast.Block) bool {
    if (b.tail_expr) |t| if (demand.inert(opts, t) != null) return false;
    for (b.stmts) |*s| switch (s.*) {
        .assign => |a| {
            for (a.targets) |t| if (t.* != .name) return false;
            for (a.values) |v| if (demand.inert(opts, v) != null) return false;
        },
        .local_decl => |d| for (d.inits) |e| if (demand.inert(opts, e) != null) return false,
        .call_stmt => |x| if (demand.inert(opts, x.expr) != null) return false,
        .expr_stmt => |x| if (demand.inert(opts, x.expr) != null) return false,
        .do_block => |d| if (!bodyInert(opts, &d.body)) return false,
        .if_stmt => |f| {
            if (f.binding) |bnd| if (demand.inert(opts, bnd.expr) != null) return false;
            if (demand.inert(opts, f.cond) != null) return false;
            if (!bodyInert(opts, &f.then)) return false;
            for (f.elseifs) |ei| {
                if (demand.inert(opts, ei.cond) != null) return false;
                if (!bodyInert(opts, &ei.body)) return false;
            }
            if (f.else_body) |eb| if (!bodyInert(opts, &eb)) return false;
        },
        else => return false,
    };
    return true;
}

/// P7. A control transfer already in the body, or a nested loop — a `break`
/// placed inside one would exit the wrong loop.
fn hasEscapeOrLoop(b: *const ast.Block) bool {
    for (b.stmts) |*s| switch (s.*) {
        .brk, .cont, .goto_stmt, .label_stmt, .ret => return true,
        .while_loop, .repeat_loop, .num_for, .gen_for => return true,
        .do_block => |d| if (hasEscapeOrLoop(&d.body)) return true,
        .if_stmt => |f| {
            if (hasEscapeOrLoop(&f.then)) return true;
            for (f.elseifs) |ei| if (hasEscapeOrLoop(&ei.body)) return true;
            if (f.else_body) |eb| if (hasEscapeOrLoop(&eb)) return true;
        },
        else => {},
    };
    return false;
}

// ─── The continuation projection: what the rest of the program observes ────

/// THE CONTINUATION, AS A STACK OF FRAMES.
///
/// A loop nested in an `if` is followed by the rest of that branch AND by
/// everything after the `if` — and the second half is not reachable from the
/// branch's own block. Passing only "the demand of the enclosing block" was
/// this module's first soundness bug: a loop inside a branch whose accumulator
/// is read after the branch looked unobserved, which would have truncated a
/// loop somebody reads. The frame chain is the fix, and it is why the
/// continuation is a linked list rather than one block plus a summary.
const Frame = struct {
    block: *const ast.Block,
    /// Index of the first statement AFTER the construct being analysed.
    next: usize,
    parent: ?*const Frame,
};

/// The projection of `name` demanded by everything that runs after the
/// construct `frame` points past — the rest of its block, that block's answer,
/// and, recursively, every enclosing frame.
///
/// KILLS ARE NOT MODELLED. A later `p = 0` really does make the earlier value
/// unobserved, and not saying so costs candidates. It never costs correctness,
/// which is the only direction that may be approximated.
fn frameProjection(frame: ?*const Frame, name: []const u8, budget: *Budget) Projection {
    const f = frame orelse return .none;
    const here = continuationProjection(f.block, f.next, name, .none, budget);
    if (here == .whole) return .whole;
    return Projection.join(here, frameProjection(f.parent, name, budget));
}

fn continuationProjection(
    b: *const ast.Block,
    from: usize,
    name: []const u8,
    outer: Projection,
    budget: *Budget,
) Projection {
    var acc = outer;
    var i = from;
    while (i < b.stmts.len) : (i += 1) {
        if (!budget.charge(1)) return .whole;
        acc = Projection.join(acc, stmtProjection(&b.stmts[i], name, outer, budget));
        if (acc == .whole) return .whole;
    }
    // The block's tail expression IS its answer, and an answer is observed
    // wholly: this module does not know who calls the relation. For `main` the
    // real observer is the process exit code — 8 bits — but inferring that
    // here would be inferring `W`, which `demand.zig`'s header shows is the
    // caller's fact and not the analysis's.
    if (b.tail_expr) |t| acc = Projection.join(acc, projectionOfName(.whole, t, name));
    return acc;
}

fn stmtProjection(
    s: *const ast.Stmt,
    name: []const u8,
    outer: Projection,
    budget: *Budget,
) Projection {
    if (!budget.charge(1)) return .whole;
    return switch (s.*) {
        .assign => |a| blk: {
            var acc: Projection = .none;
            for (a.values) |v| acc = Projection.join(acc, projectionOfName(.whole, v, name));
            // A write THROUGH a place (`t[i] = p`) reaches storage this module
            // cannot follow.
            for (a.targets) |t| if (t.* != .name) {
                acc = Projection.join(acc, if (mentions(t, name)) .whole else .none);
            };
            break :blk acc;
        },
        .local_decl => |d| blk: {
            var acc: Projection = .none;
            for (d.inits) |e| acc = Projection.join(acc, projectionOfName(.whole, e, name));
            break :blk acc;
        },
        .call_stmt => |x| projectionOfName(.whole, x.expr, name),
        .expr_stmt => |x| projectionOfName(.whole, x.expr, name),
        .ret => |r| blk: {
            var acc: Projection = .none;
            for (r.vals) |e| acc = Projection.join(acc, projectionOfName(.whole, e, name));
            break :blk acc;
        },
        .do_block => |d| continuationProjection(&d.body, 0, name, outer, budget),
        .while_loop => |w| Projection.join(
            projectionOfName(.nonzero, w.cond, name),
            continuationProjection(&w.body, 0, name, outer, budget),
        ),
        .repeat_loop => |r| Projection.join(
            projectionOfName(.nonzero, r.cond, name),
            continuationProjection(&r.body, 0, name, outer, budget),
        ),
        .if_stmt => |f| blk: {
            // A branch CONDITION is observed only through its truth.
            var acc = projectionOfName(.nonzero, f.cond, name);
            if (f.binding) |bnd| acc = Projection.join(acc, projectionOfName(.whole, bnd.expr, name));
            acc = Projection.join(acc, continuationProjection(&f.then, 0, name, outer, budget));
            for (f.elseifs) |ei| {
                acc = Projection.join(acc, projectionOfName(.nonzero, ei.cond, name));
                acc = Projection.join(acc, continuationProjection(&ei.body, 0, name, outer, budget));
            }
            if (f.else_body) |eb| acc = Projection.join(acc, continuationProjection(&eb, 0, name, outer, budget));
            break :blk acc;
        },
        .brk, .cont => .none,
        // Every other shape — `goto`, a label, a directive, a declaration form
        // this module does not model — is assumed to observe everything.
        else => .whole,
    };
}

// ─── VALUE OF INFORMATION: the accumulator's initial value ─────────────────

/// Scan backwards for `name`'s value on entry to the loop. THE ONE FACT the
/// `interval_nonzero` route cannot do without, and the one this module has to
/// PAY to learn: the scan costs budget and buys a complexity class.
///
/// Returns `unknown` — never a guess — when any write it cannot pin is found.
fn initialDomain(
    b: *const ast.Block,
    upto: usize,
    name: []const u8,
    budget: *Budget,
) Domain {
    var d: Domain = .nothing_known;
    var spent: u32 = 0;
    var i: usize = 0;
    while (i < upto) : (i += 1) {
        spent += 1;
        if (spent > budget.initial_value_probe_steps) return .nothing_known;
        const s = &b.stmts[i];
        switch (s.*) {
            .assign => |a| {
                var touches = false;
                for (a.targets) |t| {
                    if (t.* != .name) {
                        if (mentions(t, name)) return .nothing_known;
                        continue;
                    }
                    if (std.mem.eql(u8, t.name.ident, name)) touches = true;
                }
                if (!touches) continue;
                if (a.targets.len != 1 or a.values.len != 1) return .nothing_known;
                const v = intLiteral(a.values[0]) orelse return .nothing_known;
                d = Domain.exact(v, "literal initialiser before the loop");
            },
            .local_decl => |decl| {
                var idx: ?usize = null;
                for (decl.names, 0..) |n, j| if (std.mem.eql(u8, n.ident, name)) {
                    idx = j;
                };
                const j = idx orelse continue;
                if (decl.names.len != decl.inits.len) return .nothing_known;
                const v = intLiteral(decl.inits[j]) orelse return .nothing_known;
                d = Domain.exact(v, "literal declaration before the loop");
            },
            // A nested construct could write `name` in a way this scan cannot
            // order. Refuse rather than assume.
            .do_block, .if_stmt, .while_loop, .repeat_loop, .num_for, .gen_for => {
                var scan: WriteScan = .{};
                // Cheap syntactic containment test: if the construct mentions
                // the name at all, this scan is not authoritative.
                if (stmtMentions(s, name)) return .nothing_known;
                _ = &scan;
            },
            .call_stmt, .expr_stmt => {},
            else => return .nothing_known,
        }
    }
    return d;
}

fn stmtMentions(s: *const ast.Stmt, name: []const u8) bool {
    return switch (s.*) {
        .assign => |a| blk: {
            for (a.targets) |t| if (mentions(t, name)) break :blk true;
            for (a.values) |v| if (mentions(v, name)) break :blk true;
            break :blk false;
        },
        .local_decl => |d| blk: {
            for (d.names) |n| if (std.mem.eql(u8, n.ident, name)) break :blk true;
            for (d.inits) |e| if (mentions(e, name)) break :blk true;
            break :blk false;
        },
        .call_stmt => |x| mentions(x.expr, name),
        .expr_stmt => |x| mentions(x.expr, name),
        .ret => |r| blk: {
            for (r.vals) |e| if (mentions(e, name)) break :blk true;
            break :blk false;
        },
        .do_block => |d| blockMentions(&d.body, name),
        .while_loop => |w| mentions(w.cond, name) or blockMentions(&w.body, name),
        .repeat_loop => |r| mentions(r.cond, name) or blockMentions(&r.body, name),
        .if_stmt => |f| blk: {
            if (mentions(f.cond, name)) break :blk true;
            if (f.binding) |bnd| if (std.mem.eql(u8, bnd.name, name) or mentions(bnd.expr, name)) break :blk true;
            if (blockMentions(&f.then, name)) break :blk true;
            for (f.elseifs) |ei| if (mentions(ei.cond, name) or blockMentions(&ei.body, name)) break :blk true;
            if (f.else_body) |eb| if (blockMentions(&eb, name)) break :blk true;
            break :blk false;
        },
        .num_for => |nf| blk: {
            if (std.mem.eql(u8, nf.var_name, name)) break :blk true;
            if (mentions(nf.start, name) or mentions(nf.stop, name)) break :blk true;
            if (nf.step) |st| if (mentions(st, name)) break :blk true;
            break :blk blockMentions(&nf.body, name);
        },
        .gen_for => |g| blk: {
            for (g.iters) |e| if (mentions(e, name)) break :blk true;
            break :blk blockMentions(&g.body, name);
        },
        .brk, .cont => false,
        else => true,
    };
}

fn blockMentions(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |*s| if (stmtMentions(s, name)) return true;
    if (b.tail_expr) |t| if (mentions(t, name)) return true;
    return false;
}

/// The number of times the loop body runs, from the ONE trip-count proof plus
/// the counter's literal start. `unknown` when either is missing.
fn tripDomain(proof: demand.TripProof, start: Domain) Domain {
    if (start.status != .fact or start.lo != start.hi) return .nothing_known;
    const s: i128 = start.lo;
    const limit: i128 = proof.limit;
    const step: i128 = proof.step; // magnitude, > 0
    const distance: i128 = if (proof.ascending) limit - s else s - limit;
    if (distance <= 0) return Domain.range(0, 0, "loop never enters");
    // `<` / `>` stop one short; `provenTripCount` normalises both into an
    // exclusive bound, so ceil(distance/step) is the count.
    const t = @divTrunc(distance + step - 1, step);
    return Domain.range(0, t, "proven trip count");
}

// ═══════════════════════════════════════════════════════════════════════════
// THE PASS
// ═══════════════════════════════════════════════════════════════════════════

/// What the pass saw, for a gate that must be able to fail in BOTH directions.
/// A census of zero candidates on a corpus that contains one is a failure; a
/// census of refusals whose reasons never change is a transform that is not
/// looking.
pub const Census = struct {
    loops_examined: u32 = 0,
    candidates: u32 = 0,
    sites: u32 = 0,
    cache_hits: u32 = 0,
    refusals: [std.meta.fieldNames(Refusal).len]u32 = @splat(0),
    /// WHICH PROOF ROUTE ADMITTED EACH CANDIDATE, and WHICH FACTS IT NEEDED.
    ///
    /// This exists so `Candidate.semantic_proof` and `Candidate.required_facts`
    /// have a CONSUMER. `HPLS.md` §7-8: a fact with `consumers = 0` is P0
    /// architecture debt, and §24's five-field candidate is a licence to
    /// expose those fields, not a licence to carry them unread. Reading them
    /// here is what makes "the relation algebra and the uncertainty algebra are
    /// two algebras" a measurable statement — `by_route` separates the
    /// candidates that consumed an interval fact from the ones that consumed
    /// only a relation law, and the unit tests assert the split.
    by_route: [std.meta.fieldNames(Proof.Route).len]u32 = @splat(0),
    /// Candidates admitted while consuming a proven initial value. The
    /// difference between this and `candidates` is exactly the value of the
    /// information the probe budget paid for.
    used_initial_value: u32 = 0,

    fn refuse(self: *Census, r: Refusal) void {
        self.refusals[@intFromEnum(r)] += 1;
    }

    fn record(self: *Census, c: *const Candidate) void {
        self.candidates += 1;
        self.by_route[@intFromEnum(c.semantic_proof.route)] += 1;
        if (c.required_facts.initial_value_known) self.used_initial_value += 1;
    }

    pub fn refusalCount(self: *const Census, r: Refusal) u32 {
        return self.refusals[@intFromEnum(r)];
    }

    pub fn routeCount(self: *const Census, r: Proof.Route) u32 {
        return self.by_route[@intFromEnum(r)];
    }
};

/// Analyse every relation body in the module, and the module body itself when
/// the caller has closed the world. Break sites are added to `plan`, which
/// `demand.prune` already knows how to realize — this module adds a CANDIDATE
/// to an existing generator, it does not add a second lowering path.
pub fn analyzeModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    opts: demand.Options,
    plan: *demand.Plan,
) !Census {
    var census: Census = .{};
    var budget: Budget = .{};
    var cache: Cache = .{};
    defer cache.deinit(alloc);

    // ── THE SHARED OBSERVATION SPECIFICATION (GAP-170) ────────────────────
    //
    // `src/observation.zig` is the authority on WHO IS WATCHING. This module
    // does not carry a private observer roster and does not get a second
    // opinion; it asks `World.observers()`, which is the only place that
    // roster is computed, and rules against the answer.
    //
    // THE WORLD IS THE CALLER'S FACT, exactly as `world_closed` is. An
    // executable is closed at module scope; `--emit obj`/`dylib` exist to be
    // read from outside, so they get a world WITHOUT `closed_world`, which
    // `World.observers()` turns into a FOREIGN observer. Inferring it here
    // would be inventing the one input this module is not the producer of.
    const world = worldOf(opts);
    if (observationRefusal(world)) |r| {
        census.refuse(r);
        return census;
    }

    var ctx: Ctx = .{ .alloc = alloc, .opts = opts, .plan = plan, .census = &census, .budget = &budget, .cache = &cache };

    // Relation bodies always. `descend_functions` is false for the module walk
    // so a function body is never analysed twice — the census would double and
    // a gate reading it would be reading an artefact of the walk.
    for (mod.body.stmts) |*s| {
        if (s.* != .func_decl) continue;
        try analyzeBlock(&ctx, &s.func_decl.func.body, null, true);
    }
    // The file-scope tail is the program, but only when the caller has closed
    // the world. Note what this reaches and what it does not: every
    // module-scope binding is in `opts.globals`, and P8 refuses those outright,
    // so a file-scope loop is examined and then refused on the place. That is
    // the honest state — the module-scope place algebra is `demand.zig`'s W2
    // and this module does not have a second one.
    if (opts.world_closed) {
        ctx.opts.module_scope = true;
        try analyzeBlock(&ctx, &mod.body, null, false);
    }
    census.cache_hits = cache.hits;
    return census;
}

const Ctx = struct {
    alloc: std.mem.Allocator,
    opts: demand.Options,
    plan: *demand.Plan,
    census: *Census,
    budget: *Budget,
    cache: *Cache,
};

/// The world, from the caller's fact and nothing else.
pub fn worldOf(opts: demand.Options) observation.World {
    return if (opts.world_closed) observation.ordinary_executable else observation.World{};
}

/// **THE OBSERVER GATE, and it is the whole of GAP-171 deletion condition 2
/// that this transform can currently discharge.**
///
/// Truncation is a SCHEDULE freedom: it changes how many times the loop body
/// runs. Three observers cannot distinguish that, and every one of them is
/// unconditionally present in `World.observers()`:
///
///   `program`           the answer is PROVEN equal by `admit`.
///   `deployment`        the exit status is a function of the answer.
///   `failure_recovery`  a trap is the only thing it recovers from, and P5
///                       proves the body cannot trap, so no trap is skipped.
///
/// EVERY OTHER OBSERVER IN §9's ROSTER CAN. A foreign reader sees a
/// module-scope place at a moment this walk cannot place; a debugger steps the
/// loop and counts iterations; a profiler and a security adversary read
/// DURATION, and truncation is a duration change by construction; reflection
/// and MCP read intermediate state; a concurrency observer sees the writes.
/// So the rule is a SUBSET test against a roster this module does not own, and
/// any world fact that adds an observer deletes the candidate — which is
/// `HPLS.md` §19's negative control, made structural.
///
/// N5 IS CHECKED FIRST AND SEPARATELY. In a world demanding determinism,
/// noninterference, serializability or linearizability, every check in this
/// file is SINGLE-TRACE and therefore an unsound acceptance criterion: no
/// number of agreeing single traces establishes a property of SETS of
/// executions. The module refuses rather than answering as if the demand were
/// absent, and it says which of the two reasons applied.
///
/// WHAT IS *NOT* CONSULTED, AND WHY — MEASURED, not assumed.
/// `observation.zig` also offers a PER-PLACE report
/// (`Program.report(name, obligations)` -> `permits(&report, .schedule)`),
/// which is the finer instrument and the one deletion condition 2 really
/// names. It cannot answer here: its evidence is indexed by `place.zig`'s
/// census, and that census records a place only where a binding's value is a
/// `.table` literal (`place.zig::walkStmt`). Measured on this module's own
/// headline fixture, `observation.analyze` walked 7 program points and
/// produced **0 places**, so `report("hits", …)` returns null and there is no
/// per-place ruling to obtain. Consulting it opportunistically — taking a
/// permit when a report exists and proceeding when it does not — would be
/// treating an absent authority as a permissive one, which is the exact error
/// `place.Tri` and `observation.zig`'s N1 exist to forbid. So it is not
/// consulted at all, and the gap is reported rather than papered over.
pub fn observationRefusal(w: observation.World) ?Refusal {
    if (w.demandsHyperproperty()) return .blocked_hyperproperty;
    var permitted: observation.ObserverSet = .{};
    permitted.insert(.program);
    permitted.insert(.deployment);
    permitted.insert(.failure_recovery);
    var present = w.observers();
    present = present.differenceWith(permitted);
    if (present.count() != 0) return .observation_refused;
    return null;
}

/// Walk straight-line structure looking for loops. **Loop bodies are never
/// entered.** A loop inside a loop carries its writes into the next outer
/// iteration, so "what observes this place" is not the syntactic continuation
/// at all, and truncating on that answer would be truncating on the wrong
/// question. Refusing the inner loop costs candidates and cannot cost an
/// answer.
fn analyzeBlock(
    ctx: *Ctx,
    b: *const ast.Block,
    parent: ?*const Frame,
    descend_functions: bool,
) std.mem.Allocator.Error!void {
    for (b.stmts, 0..) |*s, i| {
        const frame: Frame = .{ .block = b, .next = i + 1, .parent = parent };
        switch (s.*) {
            .while_loop => |wl| try considerLoop(ctx, wl, &frame),
            .do_block => |d| try analyzeBlock(ctx, &d.body, &frame, descend_functions),
            .if_stmt => |f| {
                try analyzeBlock(ctx, &f.then, &frame, descend_functions);
                for (f.elseifs) |ei| try analyzeBlock(ctx, &ei.body, &frame, descend_functions);
                if (f.else_body) |eb| try analyzeBlock(ctx, &eb, &frame, descend_functions);
            },
            .func_decl => |f| if (descend_functions) try analyzeBlock(ctx, &f.func.body, null, true),
            else => {},
        }
    }
}

fn considerLoop(
    ctx: *Ctx,
    wl: anytype,
    frame: *const Frame,
) std.mem.Allocator.Error!void {
    const alloc = ctx.alloc;
    const opts = ctx.opts;
    const plan = ctx.plan;
    const census = ctx.census;
    const budget = ctx.budget;
    const cache = ctx.cache;
    const b = frame.block;
    const idx = frame.next - 1;
    census.loops_examined += 1;

    // P7 first: it is the cheapest and it refuses the most.
    if (hasEscapeOrLoop(&wl.body)) {
        census.refuse(.control_escape);
        return;
    }
    // P6 — the ONE trip-count proof.
    const trip_proof = demand.provenTripCount(wl) orelse {
        census.refuse(.may_not_terminate);
        return;
    };
    // P5 — the ONE trap/effect producer.
    if (!bodyInert(opts, &wl.body)) {
        census.refuse(.body_not_inert);
        return;
    }

    // P1 — the write set, fully enumerable.
    var scan: WriteScan = .{};
    defer scan.names.deinit(alloc);
    try collectWrites(alloc, &wl.body, &scan, budget);
    if (!scan.complete) {
        census.refuse(if (budget.spent > budget.search_steps) .budget_exhausted else .not_sole_place);
        return;
    }

    // P8 + P1 — exactly one written place is observed downstream.
    var observed_name: ?[]const u8 = null;
    var observed_h: Projection = .none;
    for (scan.names.items) |n| {
        // P8: a module-scope binding is a place the whole program can see, and
        // this module cannot bound its readers.
        if (opts.globals) |g| if (g.contains(n)) {
            census.refuse(.aliased_place);
            return;
        };
        const h = frameProjection(frame, n, budget);
        if (h == .none) continue;
        if (observed_name != null) {
            census.refuse(.not_sole_place);
            return;
        }
        observed_name = n;
        observed_h = h;
    }
    const name = observed_name orelse {
        // Nothing observed: this is `demand.zig`'s empty realization, not a
        // truncation. Not a refusal — a different candidate generator's job.
        return;
    };
    if (observed_h == .whole and !frameDerivable(frame, name)) {
        census.refuse(.continuation_opaque);
        return;
    }

    // P3 — the update forms.
    var sites: std.ArrayListUnmanaged(WriteSite) = .empty;
    defer sites.deinit(alloc);
    if (!try collectUpdates(alloc, &wl.body, name, &sites, budget)) {
        census.refuse(.update_form);
        return;
    }
    if (sites.items.len == 0) return;

    // VALUE OF INFORMATION — pay to learn the initial value and the trip bound.
    const initial = initialDomain(b, idx, name, budget);
    const counter_start = initialDomain(b, idx, trip_proof.counter, budget);
    const trips = tripDomain(trip_proof, counter_start);

    var updates: std.ArrayListUnmanaged(Update) = .empty;
    defer updates.deinit(alloc);
    for (sites.items) |site| try updates.append(alloc, site.update);

    // §87-88 — the proof-carrying cache, keyed on semantic content only.
    const k = Cache.key(observed_h, updates.items, initial, trips);
    const proof = blk: {
        if (cache.map.get(k)) |cached| {
            cache.hits += 1;
            break :blk cached;
        }
        cache.misses += 1;
        const p = admit(observed_h, updates.items, initial, trips) orelse {
            census.refuse(.not_absorbing);
            return;
        };
        try cache.map.put(alloc, k, p);
        break :blk p;
    };

    const cand: Candidate = .{
        .site = sites.items[0].stmt,
        .required_facts = .{
            .projection = observed_h,
            .trip_count_proven = true,
            .body_inert = true,
            .sole_observed_place = true,
            .initial_value_known = initial.status == .fact,
        },
        .semantic_proof = proof,
        .cost_estimate = .{ .trips_before = trips.hi, .trips_after_est = 1 },
        .transition_cost = 1,
    };
    // §84: the cost model may only ORDER what legality already admitted. A
    // negative rank means the break costs more than it saves, which for a
    // proven trip count of 0 or 1 is the honest answer.
    if (rank(cand.cost_estimate.trips_before, cand.cost_estimate.trips_after_est, cand.transition_cost) <= 0) return;

    census.record(&cand);
    for (sites.items) |site| {
        try plan.break_after.put(plan.alloc, site.stmt, {});
        census.sites += 1;
    }
}

/// P2. `continuationProjection` answers `whole` for two very different reasons
/// — "every bit is genuinely demanded" and "this module cannot tell" — and
/// admitting on the second would be admitting on ignorance. This distinguishes
/// them: true when every construct in the continuation is one whose demand the
/// derivative actually models.
fn frameDerivable(frame: ?*const Frame, name: []const u8) bool {
    const f = frame orelse return true;
    var i = f.next;
    while (i < f.block.stmts.len) : (i += 1) {
        if (!stmtDerivable(&f.block.stmts[i], name)) return false;
    }
    return frameDerivable(f.parent, name);
}

fn stmtDerivable(s: *const ast.Stmt, name: []const u8) bool {
    return switch (s.*) {
        .assign, .local_decl, .call_stmt, .expr_stmt, .ret, .brk, .cont => true,
        .do_block => |d| blockDerivable(&d.body, name),
        .while_loop => |w| blockDerivable(&w.body, name),
        .repeat_loop => |r| blockDerivable(&r.body, name),
        .if_stmt => |f| blk: {
            if (!blockDerivable(&f.then, name)) break :blk false;
            for (f.elseifs) |ei| if (!blockDerivable(&ei.body, name)) break :blk false;
            if (f.else_body) |eb| if (!blockDerivable(&eb, name)) break :blk false;
            break :blk true;
        },
        else => !stmtMentions(s, name),
    };
}

fn blockDerivable(b: *const ast.Block, name: []const u8) bool {
    for (b.stmts) |*s| if (!stmtDerivable(s, name)) return false;
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests — every obligation stated before the transform, every unproven case
// refusing. Written in `src/demand.zig`'s style, deliberately: the two modules
// answer one question at two points on one lattice and their fixtures must be
// comparable by eye.
// ═══════════════════════════════════════════════════════════════════════════

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    mod: ast.Module,

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }
};

fn parse(src: []const u8) !Fixture {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const owned = try alloc.dupe(u8, src);
    var lex = Lexer.init(owned, "demand_projection_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    const mod = try p.parse_module();
    return .{ .arena = arena, .mod = mod };
}

const Run = struct {
    fx: Fixture,
    plan: demand.Plan,
    census: Census,

    fn deinit(self: *Run) void {
        self.plan.deinit();
        self.fx.deinit();
    }
};

/// `world_closed = true` so the fixtures are analysed as the EXECUTABLES they
/// are meant to be. Without it `observation.World{}` has no `closed_world`
/// fact, a foreign observer joins the roster, and every candidate is refused
/// by the shared specification — which is the correct answer for a `.o`, and
/// the wrong fixture for testing the transform.
fn run(src: []const u8) !Run {
    var fx = try parse(src);
    errdefer fx.deinit();
    var plan = demand.Plan.init(std.testing.allocator);
    errdefer plan.deinit();
    const census = try analyzeModule(std.testing.allocator, &fx.mod, .{ .world_closed = true }, &plan);
    return .{ .fx = fx, .plan = plan, .census = census };
}

/// A `Ctx` over one fixture, for the two tests that drive the walk directly to
/// perturb a budget.
fn testCtx(plan: *demand.Plan, census: *Census, budget: *Budget, cache: *Cache) Ctx {
    return .{
        .alloc = std.testing.allocator,
        .opts = .{ .world_closed = true },
        .plan = plan,
        .census = census,
        .budget = budget,
        .cache = cache,
    };
}

// ─── the lattice itself ────────────────────────────────────────────────────

test "projection join: nonzero and low_bits are INCOMPARABLE" {
    // 256 has `nonzero` true and `low_bits 8` zero; 0 has both zero. Neither
    // projection refines the other, so the join must be `whole`. Getting this
    // wrong admits a candidate a second observer refutes.
    try std.testing.expect(Projection.join(.nonzero, .{ .low_bits = 8 }) == .whole);
    try std.testing.expect(Projection.join(.{ .low_bits = 8 }, .nonzero) == .whole);
    try std.testing.expect(Projection.join(.none, .nonzero) == .nonzero);
    try std.testing.expect(Projection.join(.nonzero, .none) == .nonzero);
    try std.testing.expect(Projection.join(.whole, .nonzero) == .whole);
    const j = Projection.join(.{ .low_bits = 8 }, .{ .low_bits = 12 });
    try std.testing.expectEqual(@as(u6, 12), j.low_bits);
}

test "projection apply: the witnesses that make the lattice non-trivial" {
    try std.testing.expectEqual(@as(?i64, 1), Projection.apply(.nonzero, 256));
    try std.testing.expectEqual(@as(?i64, 0), Projection.apply(.{ .low_bits = 8 }, 256));
    try std.testing.expectEqual(@as(?i64, 0), Projection.apply(.nonzero, 0));
    try std.testing.expectEqual(@as(?i64, 255), Projection.apply(.{ .low_bits = 8 }, -1));
    try std.testing.expectEqual(@as(?i64, null), Projection.apply(.none, 5));
}

test "demand derivative: every rule is a homomorphism, and the rest is `whole`" {
    var fx = try parse(
        \\main: i64 = ()
        \\    0
    );
    defer fx.deinit();
    const alloc = fx.arena.allocator();

    const mk = struct {
        fn e(a: std.mem.Allocator, src: []const u8) !*ast.Expr {
            // Parse `x = <src>` and lift the value side.
            const text = try std.fmt.allocPrint(a, "main: i64 = ()\n    x = {s}\n    x\n", .{src});
            var lex = Lexer.init(text, "expr.id");
            var p = Parser.init(&lex, a);
            p.idol_mode = true;
            const m = try p.parse_module();
            const body = m.body.stmts[0].func_decl.func.body;
            return body.stmts[0].assign.values[0];
        }
    };

    // `x != 0` observed at all needs only `x`'s truthiness. THE existence rule.
    try std.testing.expect(projectionOfName(.whole, try mk.e(alloc, "y != 0"), "y") == .nonzero);
    try std.testing.expect(projectionOfName(.whole, try mk.e(alloc, "0 == y"), "y") == .nonzero);
    // Against any other literal, every bit.
    try std.testing.expect(projectionOfName(.whole, try mk.e(alloc, "y != 7"), "y") == .whole);
    // Masking narrows.
    const m8 = projectionOfName(.whole, try mk.e(alloc, "y & 255"), "y");
    try std.testing.expectEqual(@as(u6, 8), m8.low_bits);
    // A non-mask constant does NOT narrow — 0b1011 is not 2^k-1.
    try std.testing.expect(projectionOfName(.whole, try mk.e(alloc, "y & 11"), "y") == .whole);
    // + is a ring hom mod 2^k: the projection passes through unchanged.
    const add = projectionOfName(.{ .low_bits = 8 }, try mk.e(alloc, "y + 3"), "y");
    try std.testing.expectEqual(@as(u6, 8), add.low_bits);
    // ...but + is NOT a hom for `nonzero`: y+3 nonzero is not a function of
    // y nonzero. Every bit.
    try std.testing.expect(projectionOfName(.nonzero, try mk.e(alloc, "y + 3"), "y") == .whole);
    // `|` IS a hom for `nonzero`.
    try std.testing.expect(projectionOfName(.nonzero, try mk.e(alloc, "y | z"), "y") == .nonzero);
    // `&` is not.
    try std.testing.expect(projectionOfName(.nonzero, try mk.e(alloc, "y & z"), "y") == .whole);
    // Division carries no projection law here.
    try std.testing.expect(projectionOfName(.{ .low_bits = 8 }, try mk.e(alloc, "y / 2"), "y") == .whole);
    // A name the expression never mentions demands nothing.
    try std.testing.expect(projectionOfName(.whole, try mk.e(alloc, "q + 1"), "y") == .none);
    // `none` in, `none` out — the bottom is absorbing on the way down.
    try std.testing.expect(projectionOfName(.none, try mk.e(alloc, "y + 1"), "y") == .none);
}

// ─── the uncertainty algebra ───────────────────────────────────────────────

test "domain: unknown, contradiction and a wide fact are three different things" {
    const unknown: Domain = .nothing_known;
    const wide = Domain.range(std.math.minInt(i64), std.math.maxInt(i64), "wide");
    const bad = Domain.range(5, 1, "impossible");
    try std.testing.expect(unknown.status == .unknown);
    try std.testing.expect(wide.status == .fact);
    try std.testing.expect(bad.status == .contradiction);
    // A wide FACT discharges no-wrap; an unknown never can, however wide the
    // caller imagines it.
    try std.testing.expect(wide.provesNoWrap());
    try std.testing.expect(!unknown.provesNoWrap());
    // A contradiction licenses nothing.
    try std.testing.expect(!bad.provesNonzero());
    try std.testing.expect(!bad.provesNoWrap());
    // Refinement: unknown yields, facts meet, conflict contradicts.
    try std.testing.expect(Domain.refine(unknown, wide).status == .fact);
    const met = Domain.refine(Domain.range(0, 10, "a"), Domain.range(5, 20, "b"));
    try std.testing.expectEqual(@as(i128, 5), met.lo);
    try std.testing.expectEqual(@as(i128, 10), met.hi);
    try std.testing.expect(Domain.refine(Domain.range(0, 1, "a"), Domain.range(5, 6, "b")).status == .contradiction);
}

// ─── the trusted core, in isolation ────────────────────────────────────────

test "admit: literal agreement is the shipped case, generalised by h" {
    const w_same = [_]Update{ .{ .store = 1 }, .{ .store = 1 } };
    const w_diff = [_]Update{ .{ .store = 256 }, .{ .store = 512 } };
    const t = Domain.range(0, 1000, "test");
    const c0 = Domain.exact(0, "test");

    // h = whole: identical literals agree, different ones do not.
    try std.testing.expect(admit(.whole, &w_same, c0, t) != null);
    try std.testing.expect(admit(.whole, &w_diff, c0, t) == null);
    // h = low_bits 8: 256 and 512 BOTH project to 0, so they agree. Same
    // `admit`, richer D, a class the shipped rule cannot express.
    const p = admit(.{ .low_bits = 8 }, &w_diff, c0, t).?;
    try std.testing.expect(p.route == .literal_agreement);
    try std.testing.expectEqual(@as(i64, 0), p.settled);
    // h = low_bits 10: 256 and 512 disagree mod 1024. The observer can see it.
    try std.testing.expect(admit(.{ .low_bits = 10 }, &w_diff, c0, t) == null);
    // h = none is not this generator's business.
    try std.testing.expect(admit(.none, &w_same, c0, t) == null);
}

test "admit: count-to-existence needs BOTH interval halves" {
    const w = [_]Update{.{ .accumulate = .{ .op = .add, .k = 1 } }};
    const t = Domain.range(0, 2_000_000_000, "test");

    // Proven start at 0, proven trip bound: admitted.
    const p = admit(.nonzero, &w, Domain.exact(0, "t"), t).?;
    try std.testing.expect(p.route == .interval_nonzero);
    try std.testing.expectEqual(@as(i64, 1), p.settled);

    // Unknown start: REFUSED. A start of -1 reaches 0 on the first write and
    // `hits != 0` would answer false where the original answered true.
    try std.testing.expect(admit(.nonzero, &w, .nothing_known, t) == null);
    // Proven NEGATIVE start: refused for the same reason, now demonstrated.
    try std.testing.expect(admit(.nonzero, &w, Domain.exact(-1, "t"), t) == null);
    // Unknown trip bound: refused — without it the accumulator may wrap
    // through zero.
    try std.testing.expect(admit(.nonzero, &w, Domain.exact(0, "t"), .nothing_known) == null);
    // A trip bound so large the accumulator could leave i64: refused.
    const huge = Domain.range(0, std.math.maxInt(i64), "huge");
    try std.testing.expect(admit(.nonzero, &w, Domain.exact(1, "t"), huge) == null);
    // A DECREMENT is not an accumulation towards nonzero.
    const dec = [_]Update{.{ .accumulate = .{ .op = .add, .k = -1 } }};
    try std.testing.expect(admit(.nonzero, &dec, Domain.exact(0, "t"), t) == null);
    // And at h = whole the count is genuinely observed: refused.
    try std.testing.expect(admit(.whole, &w, Domain.exact(0, "t"), t) == null);
    try std.testing.expect(admit(.{ .low_bits = 8 }, &w, Domain.exact(0, "t"), t) == null);
}

test "admit: the law route consumes NO interval fact" {
    // `p = p | 4`: `x | 4` is never zero, whatever x is. No initial value, no
    // trip count, and the proof still holds — which is what makes the relation
    // algebra and the uncertainty algebra genuinely two algebras.
    const w = [_]Update{.{ .accumulate = .{ .op = .bor, .k = 4 } }};
    const p = admit(.nonzero, &w, .nothing_known, .nothing_known).?;
    try std.testing.expect(p.route == .law_nonzero);
    // `p = p ^ 4` CAN be zero (4 ^ 4 == 0), and the law says so.
    const x = [_]Update{.{ .accumulate = .{ .op = .bxor, .k = 4 } }};
    try std.testing.expect(admit(.nonzero, &x, .nothing_known, .nothing_known) == null);
    // `p = p | 0` is the identity and settles nothing.
    const z = [_]Update{.{ .accumulate = .{ .op = .bor, .k = 0 } }};
    try std.testing.expect(admit(.nonzero, &z, .nothing_known, .nothing_known) == null);
}

test "admit: a contradiction licenses nothing" {
    const w = [_]Update{.{ .accumulate = .{ .op = .add, .k = 1 } }};
    const bad = Domain.range(5, 1, "impossible");
    try std.testing.expect(admit(.nonzero, &w, bad, Domain.range(0, 10, "t")) == null);
    try std.testing.expect(admit(.nonzero, &w, Domain.exact(0, "t"), bad) == null);
}

test "SS84: cost cannot admit, and facts cannot rank" {
    // Perturb the cost inputs to absurd values; the admitted set is identical
    // because `admit`'s signature has no cost in it at all. This test is what
    // makes the separation a mechanism rather than a promise.
    const w = [_]Update{.{ .accumulate = .{ .op = .add, .k = 1 } }};
    const before = admit(.nonzero, &w, Domain.exact(0, "t"), Domain.range(0, 1000, "t"));
    try std.testing.expect(before != null);
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        _ = rank(@as(i128, i) * 1_000_000, -@as(i128, i), i);
        const after = admit(.nonzero, &w, Domain.exact(0, "t"), Domain.range(0, 1000, "t"));
        try std.testing.expect(after != null);
        try std.testing.expect(after.?.route == before.?.route);
    }
    // And ranking sees only numbers: a saving of 999 against a cost of 1.
    try std.testing.expectEqual(@as(i128, 998), rank(1000, 1, 1));
    try std.testing.expectEqual(@as(i128, -1), rank(1, 1, 1));
}

// ─── end to end, over real source ──────────────────────────────────────────

const witness_scan_exists =
    \\main: i64 = ()
    \\    hits = 0
    \\    i = 0
    \\    while i < 2000000000
    \\        if (i * 7 + 3) & 1023 == 7
    \\            hits += 1
    \\        i += 1
    \\    if hits != 0
    \\        1
    \\    else
    \\        0
;

const witness_scan_counted =
    \\main: i64 = ()
    \\    hits = 0
    \\    i = 0
    \\    while i < 2000000000
    \\        if (i * 7 + 3) & 1023 == 7
    \\            hits += 1
    \\        i += 1
    \\    hits & 255
;

test "END TO END: the same loop, two observers, two complexity classes" {
    // THE RESULT THIS MODULE EXISTS FOR. Identical loops; the answer differs
    // only in the projection through which it reads the accumulator.
    var r1 = try run(witness_scan_exists);
    defer r1.deinit();
    try std.testing.expectEqual(@as(u32, 1), r1.census.candidates);
    try std.testing.expect(r1.plan.earlyExitCount() >= 1);
    // The route and the fact list are read, not merely carried: this candidate
    // is the INTERVAL one and it consumed a proven initial value.
    try std.testing.expectEqual(@as(u32, 1), r1.census.routeCount(.interval_nonzero));
    try std.testing.expectEqual(@as(u32, 0), r1.census.routeCount(.law_nonzero));
    try std.testing.expectEqual(@as(u32, 1), r1.census.used_initial_value);

    // The adversarial control. `hits & 255` demands the count mod 256, which
    // changes on every write, so absorption fails and the loop must run to
    // completion. If this ever produces a candidate, the transform is wrong
    // and the artifact answers 1 where it must answer 101.
    var r2 = try run(witness_scan_counted);
    defer r2.deinit();
    try std.testing.expectEqual(@as(u32, 0), r2.census.candidates);
    try std.testing.expectEqual(@as(u32, 0), r2.plan.earlyExitCount());
    try std.testing.expectEqual(@as(u32, 1), r2.census.refusalCount(.not_absorbing));
}

test "END TO END: value of information — refusing to pay refuses the candidate" {
    // The initial value of `hits` is the ONE fact the interval route cannot do
    // without, and it costs a backward scan to learn. `HPLS.md` §42 and
    // GAP-171's nine-universe clause both ask that fact acquisition be a
    // schedulable optimizer ACTION rather than an assumption. Here it is one:
    // with the probe budget at zero the candidate disappears, which is the
    // negative control that proves the fact is causally operative (§19).
    var fx = try parse(witness_scan_exists);
    defer fx.deinit();
    var plan = demand.Plan.init(std.testing.allocator);
    defer plan.deinit();
    var census: Census = .{};
    var budget: Budget = .{ .initial_value_probe_steps = 0 };
    var cache: Cache = .{};
    defer cache.deinit(std.testing.allocator);
    var ctx = testCtx(&plan, &census, &budget, &cache);
    const body = &fx.mod.body.stmts[0].func_decl.func.body;
    try analyzeBlock(&ctx, body, null, true);
    try std.testing.expectEqual(@as(u32, 0), census.candidates);
    try std.testing.expectEqual(@as(u32, 1), census.refusalCount(.not_absorbing));
}

test "END TO END: an effect in the body refuses truncation" {
    // Skipping iterations would delete output. `demand.inert` with no graph
    // refuses every call, which is the conservative answer and the right one.
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    i = 0
        \\    while i < 1000
        \\        print("x")
        \\        hits += 1
        \\        i += 1
        \\    if hits != 0
        \\        1
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 0), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.refusalCount(.body_not_inert));
}

test "END TO END: an unproven trip count refuses truncation" {
    // No counter update: the loop may not terminate, and truncating it turns a
    // hang into a return.
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    i = 0
        \\    while i < 1000
        \\        hits += 1
        \\    if hits != 0
        \\        1
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 0), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.refusalCount(.may_not_terminate));
}

test "END TO END: a second observed place refuses truncation" {
    // `hits` is settled after the first write but `total` is not, and `total`
    // is observed. Truncating would change `total`.
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    total = 0
        \\    i = 0
        \\    while i < 1000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            hits += 1
        \\        total += i
        \\        i += 1
        \\    if hits != 0
        \\        total & 255
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 0), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.refusalCount(.not_sole_place));
}

test "END TO END: the law route admits with NO interval fact consumed" {
    // `flag = flag | 4` cannot produce zero, so the relation's law alone
    // settles `flag != 0`. The census proves the two algebras are separate:
    // this candidate took `law_nonzero` and consumed no initial value, while
    // the count-to-existence candidate above took `interval_nonzero` and did.
    var r = try run(
        \\main: i64 = ()
        \\    flag = 0
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            flag = flag | 4
        \\        i += 1
        \\    if flag != 0
        \\        1
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 1), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.routeCount(.law_nonzero));
    try std.testing.expectEqual(@as(u32, 0), r.census.routeCount(.interval_nonzero));

    // The control the law itself supplies: `^` CAN return to zero.
    var r2 = try run(
        \\main: i64 = ()
        \\    flag = 0
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            flag = flag ~ 4
        \\        i += 1
        \\    if flag != 0
        \\        1
        \\    else
        \\        0
    );
    defer r2.deinit();
    try std.testing.expectEqual(@as(u32, 0), r2.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r2.census.refusalCount(.not_absorbing));
}

test "END TO END: the universal quantifier is the same generator" {
    // `all` — writes are the literal 0, demanded wholly. Route 1, no new
    // mechanism, no new branch. This is the structural-completeness claim
    // being cashed rather than asserted.
    var r = try run(
        \\main: i64 = ()
        \\    ok = 1
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            ok = 0
        \\        i += 1
        \\    ok
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 1), r.census.candidates);
}

test "END TO END: witnesses that disagree at 64 bits and agree at the observed 8" {
    // Two different literal witnesses. At `h = whole` the shipped rule refuses
    // (E1 wants one literal) and so does this one. At `h = low_bits 8`, 256 and
    // 512 are the same observation, so the loop's answer is settled after
    // either write.
    var r = try run(
        \\main: i64 = ()
        \\    flag = 1
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            flag = 256
        \\        if (i * 7 + 3) & 1023 == 9
        \\            flag = 512
        \\        i += 1
        \\    flag & 255
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 1), r.census.candidates);
    var r2 = try run(
        \\main: i64 = ()
        \\    flag = 1
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            flag = 256
        \\        if (i * 7 + 3) & 1023 == 9
        \\            flag = 512
        \\        i += 1
        \\    flag & 1023
    );
    defer r2.deinit();
    try std.testing.expectEqual(@as(u32, 0), r2.census.candidates);
}

test "END TO END: reading the accumulator outside its own update refuses" {
    // `hits` feeds the predicate, so an iteration's behaviour depends on how
    // many writes preceded it and "did not run" is distinguishable from "ran".
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    i = 0
        \\    while i < 1000
        \\        if hits + i > 3
        \\            hits += 1
        \\        i += 1
        \\    if hits != 0
        \\        1
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 0), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.refusalCount(.update_form));
}

test "END TO END: a nested loop refuses — a break there exits the wrong loop" {
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    i = 0
        \\    while i < 1000
        \\        j = 0
        \\        while j < 10
        \\            j += 1
        \\        hits += 1
        \\        i += 1
        \\    if hits != 0
        \\        1
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 0), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.refusalCount(.control_escape));
}

test "optimizer economy: the proof-carrying cache is keyed on semantics, not text" {
    // Two structurally identical loops with different names, different lines
    // and a different induction variable. Discovery runs twice; the PROOF is
    // derived once. §87-88: reorganization must not invalidate semantically
    // unchanged knowledge.
    var r = try run(
        \\main: i64 = ()
        \\    hits = 0
        \\    i = 0
        \\    while i < 1000000
        \\        if (i * 7 + 3) & 1023 == 7
        \\            hits += 1
        \\        i += 1
        \\    other = 0
        \\    k = 0
        \\    while k < 1000000
        \\        if (k * 7 + 3) & 1023 == 7
        \\            other += 1
        \\        k += 1
        \\    if hits != 0
        \\        if other != 0
        \\            1
        \\        else
        \\            0
        \\    else
        \\        0
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 2), r.census.candidates);
    try std.testing.expectEqual(@as(u32, 1), r.census.cache_hits);
}

test "optimizer economy: budget exhaustion is UNKNOWN, never `none exists`" {
    // GAP-171: keep "none faster found" distinct from "proven none faster
    // exists". A search that ran out of budget must not be recorded as a
    // legality refusal, because nobody looked.
    var fx = try parse(witness_scan_exists);
    defer fx.deinit();
    var plan = demand.Plan.init(std.testing.allocator);
    defer plan.deinit();
    var census: Census = .{};
    var budget: Budget = .{ .search_steps = 1 };
    var cache: Cache = .{};
    defer cache.deinit(std.testing.allocator);
    var ctx = testCtx(&plan, &census, &budget, &cache);
    const body = &fx.mod.body.stmts[0].func_decl.func.body;
    try analyzeBlock(&ctx, body, null, true);
    try std.testing.expectEqual(@as(u32, 0), census.candidates);
    try std.testing.expectEqual(@as(u32, 1), census.refusalCount(.budget_exhausted));
    try std.testing.expectEqual(@as(u32, 0), census.refusalCount(.not_absorbing));
}

test "SS19: every added observer deletes the candidate" {
    // The negative control HPLS.md §19 demands: a fact that changes no
    // candidate set is not yet operative. Here each world fact is added ALONE
    // to the ordinary executable world, and each one must be enough on its own.
    const ord = observation.ordinary_executable;
    try std.testing.expect(observationRefusal(ord) == null);

    // The default world has no `closed_world`, so `World.observers()` inserts
    // a FOREIGN observer — which is exactly why `--emit obj` and `--emit dylib`
    // must leave `world_closed` false, and why this module never infers it.
    try std.testing.expect(observationRefusal(observation.World{}) == .observation_refused);

    for ([_]observation.WorldFact{
        .foreign_boundary,
        .debugger_demanded,
        .profiler_demanded,
        .reflection_demanded,
        .mcp_demanded,
        .genuine_sharing,
        .security_adversary,
        .clock_read,
        .deadline,
    }) |f| {
        const w = ord.with(f);
        try std.testing.expectEqual(Refusal.observation_refused, observationRefusal(w).?);
    }

    // N5 is a DIFFERENT refusal, not a harder version of the same one: the
    // evidence this module produces is the wrong KIND, and no amount of it
    // would help. Conflating the two would hide the fact that a single-trace
    // oracle was being used where a hyperproperty was demanded.
    for ([_]observation.WorldFact{
        .determinism_demanded,
        .noninterference_demanded,
        .serializability_demanded,
        .linearizability_demanded,
    }) |f| {
        try std.testing.expectEqual(Refusal.blocked_hyperproperty, observationRefusal(ord.with(f)).?);
    }
}

test "SS19: the observer gate reaches the pass, not just the predicate" {
    // The gate above is only operative if the PASS consults it. Same fixture,
    // two worlds: closed executable admits, open (`--emit obj`) refuses.
    var fx = try parse(witness_scan_exists);
    defer fx.deinit();

    var plan_closed = demand.Plan.init(std.testing.allocator);
    defer plan_closed.deinit();
    const closed = try analyzeModule(std.testing.allocator, &fx.mod, .{ .world_closed = true }, &plan_closed);
    try std.testing.expectEqual(@as(u32, 1), closed.candidates);

    var plan_open = demand.Plan.init(std.testing.allocator);
    defer plan_open.deinit();
    const open = try analyzeModule(std.testing.allocator, &fx.mod, .{}, &plan_open);
    try std.testing.expectEqual(@as(u32, 0), open.candidates);
    try std.testing.expectEqual(@as(u32, 1), open.refusalCount(.observation_refused));
    try std.testing.expectEqual(@as(u32, 0), plan_open.earlyExitCount());
}

test "relation law: composition derives, it does not assume" {
    const bor = lawsOf(.bor);
    try std.testing.expect(bor.bit_local and bor.idempotent and !bor.can_zero_nonzero);
    const add = lawsOf(.add);
    try std.testing.expect(add.ring_hom_mod_2k and add.can_zero_nonzero and !add.bit_local);
    // pure∘pure→pure, bit_local∘bit_local→bit_local, and NOTHING claims
    // commutativity of a composite.
    const c = composeLaws(bor, lawsOf(.band));
    try std.testing.expect(c.pure and c.bit_local and !c.commutative and !c.associative);
    // A composite that can zero on either side can zero.
    try std.testing.expect(composeLaws(bor, add).can_zero_nonzero);
    // Division carries almost nothing, and must not acquire anything by
    // composition.
    try std.testing.expect(!composeLaws(lawsOf(.div), bor).pure);
}
