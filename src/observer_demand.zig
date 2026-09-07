//! src/observer_demand.zig — RECONSTRUCT RATHER THAN RETAIN.
//!
//! HPLS §11 (observation virtualization), §59 (invertibility) and §60 (temporal
//! value policy) are one idea with three names, and none of them had a case
//! anywhere in this project before this file. This file does not implement the
//! idea. It makes the idea's PRICE measurable, states the proof obligation that
//! a reconstruction owes, and decides the one obligation that is decidable.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHY THIS FILE EXISTS: THE TAX WAS UNSPELLABLE, THEREFORE UNMEASURED
//! ════════════════════════════════════════════════════════════════════════════
//!
//! §11's target is *high-level observability at near-zero optimized-runtime
//! tax*. To measure how far this compiler is from that target you must be able
//! to ADD AN OBSERVER to a compilation and re-measure. Before this file you
//! could not:
//!
//!   `observation.WorldFact.debugger_demanded`, `.profiler_demanded`,
//!   `.reflection_demanded` and `.mcp_demanded` appear in exactly three places
//!   in the compiler — their own declaration, one `obseq` unit test, and one
//!   list in a `demand_projection` unit test. **No CLI flag, no directive and
//!   no pipeline call site could set any of them.** The single pipeline
//!   consumer of the observation model, `obseq.applyToEntry` at
//!   `src/main.zig`, passes the literal `observation.ordinary_executable`,
//!   whose roster is exactly {program, deployment, failure_recovery}.
//!
//! So §11's claim was not false here; it was UNTESTABLE here. `Observer` and
//! `Demand` below are the smallest thing that makes it testable: a `--observer`
//! spelling for the four §9 inspection observers, and one world constructor.
//!
//! MEASURED with that flag, `--backend=direct`, Apple Silicon, cache cleared,
//! whole-process cycles from `/usr/bin/time -l`, min of 7, answers checked
//! against `gate/obseq.sh`'s independent Python model (`gate/recon.sh` is the
//! authority and re-derives every row):
//!
//!     probe   observer     main insns        cycles   vs none   exit
//!     w6      none               2        4,630,978       —      125
//!     w6      debugger          22      108,363,341    23.40x    125
//!     w6      profiler          22      104,995,808    22.67x    125
//!     w6      reflection        22      104,726,646    22.61x    125
//!     w6      mcp               22      104,646,321    22.60x    125
//!     pair    none               2        4,324,678       —      169
//!     pair    debugger          27      144,796,074    33.48x    169
//!     floor   none               2        4,351,394       —        7
//!     floor   debugger           2        4,261,401     0.98x      7
//!
//! **The tax is real, it is 23.4x and 33.5x on the two rows where an
//! observation fact pays in this compiler, and it is charged for the observer's
//! EXISTENCE.** No debugger attached. No breakpoint set. No value inspected.
//! `w6` under `--observer=debugger` runs twenty million iterations of a serial
//! chain to produce a byte that FOUR iterations already fixed, because a
//! debugger might ask. That is the exact inversion §11 names: today, richer
//! tooling costs runtime, permanently.
//!
//! The `floor` row is the control and it is pinned from below as well as above:
//! a program with no loop pays 0.98x, so the instrument is measuring the
//! transform rather than the flag. The exit byte is identical on every row, so
//! nothing here is a wrong answer that got fast.
//!
//! The four observers are within 1% of each other because
//! `demand_projection.observationRefusal` refuses on the ROSTER — any observer
//! outside {program, deployment, failure_recovery} refuses the whole module.
//! **That is itself a finding**: the refusal is all-or-nothing and does not
//! consult the per-place model in `observation.zig` at all, so a profiler that
//! could not distinguish this loop's value from its constant is charged the
//! same 22.7x as a debugger that could. The per-place model disagrees: the test
//! `§11 — an observer's mere existence costs freedoms` MEASURES that
//! `profiler_demanded` and `mcp_demanded` cost ZERO freedoms on a clean place,
//! and `debugger_demanded` and `reflection_demanded` cost real ones. The gap
//! between those two authorities is the cheapest available reduction of this
//! tax and it is stated as ROUTED work, not taken here.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT §11 ASKS FOR, AND WHAT IT COSTS TO SAY YES
//! ════════════════════════════════════════════════════════════════════════════
//!
//! §11 permits: value physically absent + provenance + remaining state +
//! RECOMPUTATION RECIPE → reconstruct on observer demand. A recipe that is
//! wrong is a wrong answer with extra steps, so the obligation comes first:
//!
//!   R1 PURE       — replaying the recipe must not repeat an effect, and
//!                   skipping it must not skip one. `observation.Evidence
//!                   .has_effect` must read `.no`; `.unknown` is not `.no`.
//!   R2 TOTAL      — the recipe must be defined on every state it may be
//!                   replayed from. A partial recipe reconstructs a trap.
//!   R3 TRAP-FREE  — replay must not trap where the original did not. This
//!                   tree measured that division by zero silently yielded 0
//!                   until it was made to trap, and that `@divTrunc(minInt,-1)`
//!                   overflows: both are R3 failures wearing an arithmetic hat.
//!   R4 INPUTS LIVE— every input the recipe reads must still EXIST when the
//!                   observer asks. This is a place-lifetime question and
//!                   `place.Facts.lifetime` / `.residency` answer it. A recipe
//!                   whose input was itself discarded is not a recipe.
//!   R5 TIMING     — reconstruction moves WHEN work happens, which a timing
//!                   observer distinguishes. Refuse under a hyperproperty
//!                   demand; `demand_projection.observationRefusal` is the
//!                   authority and this file does not mint a second roster.
//!
//! R1–R4 are exactly the guards `observation.classify` already applies to
//! `recompute_vs_memoize`, and R5 is `permits`'s `blocked_hyperproperty`. So
//! the §11 recipe's legality is NOT new machinery — it is `observation.permits
//! (report, .memoization)` read for a purpose it was not yet read for. That is
//! the finding, and `admissible` below is the four lines that state it.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! §59, AND THE DUALITY THAT IS THE REAL RESULT
//! ════════════════════════════════════════════════════════════════════════════
//!
//! §59 says a predecessor may be RECOVERED FROM ITS SUCCESSOR where the
//! relation is proven invertible. On a demanded quotient the state space is
//! FINITE, and on a finite set injectivity is decidable by one sweep — the same
//! sweep that builds the inverse. **The proof and the recipe are the same
//! object**, which is `decideInverse` below.
//!
//! The decision procedure costs O(|S|) time and O(|S|) space and it is exact,
//! so §59's obligation is discharged rather than assumed. But the answer it
//! returns is not the one a reader expects, and this is the measured result:
//!
//!   MEASURED by exhaustive enumeration over the demanded quotient, on the
//!   probe bodies `gate/obseq.sh` already pins, and independently reproduced by
//!   a Python model of the same wrapping arithmetic:
//!
//!     body                        images / |S|   starts with a tail   mu, lambda
//!                                                                     from entry
//!     w6   x ^= x*C; x += K        37 / 256        255 / 256           4, 1
//!     sq   x = x*x ^ x*C; x += K  128 / 256        128 / 256           0, 4
//!     pair a ^= b*C; b += a*D     65536 / 65536      0 / 65536         0, 192
//!     x * 1103515245 (odd)         1024 / 1024       0 / 1024          0, 256
//!     x * 2                         512 / 1024    1023 / 1024         10, 1
//!
//!   `pair`'s 192 is the same 192 `gate/obseq.sh` records for its contracted
//!   orbit, arrived at from the other direction — that agreement is why these
//!   numbers are believable.
//!
//!   And the pattern is a theorem, not a coincidence: **for f : S → S on a
//!   finite S, f is injective iff NO start state has a tail.** The two columns
//!   above are the same fact read twice, and `firstStartWithTail` checks them
//!   against each other on every body. An injective step has no tail anywhere,
//!   so the fixed-point family — the cheap half of the quotient engine — can
//!   never fire on it, and `w6`'s twenty million iterations collapse only
//!   because its map is 7:1 on the demanded byte.
//!
//!   Read the `x * 2` row beside the odd one. This tree already established
//!   that 2 is not invertible mod 2^64 and that binary powering never forms the
//!   division that would need it. Here that ring fact is DECIDED rather than
//!   quoted, by the same sweep, and it lands on the non-invertible side with
//!   1023 of 1024 starts carrying a tail.
//!
//! **§59 and §11's forward recipe are in tension, and the tension is total.**
//!   - Where the step is INVERTIBLE, `derive_from_successor` is available and
//!     an observer's predecessor costs (N − i) inverse steps from the final
//!     state, with ZERO retention — but the forward orbit never contracts to a
//!     fixed point, so the value cannot be replaced by one constant.
//!   - Where the step is NON-INVERTIBLE, the predecessor is genuinely gone —
//!     `w6`'s map sends 256 low-byte states onto 37, so no recipe recovers it —
//!     but the forward orbit contracts, so the FORWARD recipe from the entry
//!     constant is O(mu) and the observer is served for free.
//!
//! Neither case needs retention. That is the useful half of the duality: on
//! this evidence the six-way menu of §60 collapses toward two, and which of the
//! two applies is decided by one O(|S|) sweep.
//!
//! The honest limit of that claim: it is measured on FIVE step functions, all
//! of them one wrapping arithmetic body over a small quotient. It is not a
//! survey and it is not a corpus. What it establishes is that the question is
//! DECIDABLE and cheap on the class this compiler's own quotient engine already
//! accepts, and that on that class the answer splits both ways.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE ANSWER FOR `w6`, END TO END — AND WHY THE 23.4x BUYS NOTHING
//! ════════════════════════════════════════════════════════════════════════════
//!
//! A debugger does not demand `x mod 2^8`. It demands `x`. So the quotient that
//! makes `obseq` close the loop is NOT the quotient the debugger asks in, and
//! that is the whole of why `observationRefusal` refuses. Take the debugger's
//! demand at face value and ask §60's question about `x` at iteration `i`:
//!
//!   RETAIN                  20,000,000 x 8 bytes = 160 MB of history, to serve
//!                           a query nobody has made.
//!   DERIVE FROM SUCCESSOR   REFUSED, and provably. `C = 1103515245` is odd, so
//!                           `x * C ≡ x (mod 2)` and `x ^ (x*C)` is EVEN for
//!                           every `x`; adding 12345 makes every successor ODD.
//!                           The image is inside the odd numbers at every width,
//!                           so the step is not injective at 8 bits (measured:
//!                           37 of 256) and not injective at 64 either (derived,
//!                           by that parity argument). §59 does not apply here.
//!   RECOMPUTE               `x0 = 12345; apply the step i times`. PURE — the
//!                           body is arithmetic and `observation.Evidence
//!                           .has_effect` reads `.no` for it. TOTAL — wrapping
//!                           arithmetic is defined everywhere. TRAP-FREE — no
//!                           division, no signed overflow, `+%` `*%` `^` only.
//!                           INPUTS LIVE — the input is the literal 12345, and a
//!                           literal outlives everything.
//!
//! **R1–R4 all discharge, so the recipe is legal, and its runtime cost when no
//! observer asks is ZERO.** The value can be physically absent. The program that
//! serves a debugger is then the SAME 2-instruction binary the unwatched build
//! already produces, plus a recipe that is data rather than code.
//!
//! That is the finding stated as a cost: **the 103.7 million cycles a debugger
//! demand costs today buy nothing, because they materialise a value in advance
//! of a query that has not been made and might never be.** §11's target —
//! observability at near-zero optimized-runtime tax — is reachable on this row,
//! and what stands between here and there is not a proof, because the proof is
//! above. It is an emission path for a recipe, which is `dnir_lower.zig`'s and
//! is not routed by this lane.
//!
//! PROJECTED, and flagged as such: the observer-query path would cost `i` steps
//! per query, up to 20,000,000. Nothing here measures that, because nothing here
//! implements it. If queries are frequent and late, RETAIN wins and `cheapest`
//! below is where that argument belongs — with a `CostModel` somebody measured.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! §60, AND WHERE THE COST MODEL IS AND IS NOT
//! ════════════════════════════════════════════════════════════════════════════
//!
//! §84 is permanent: LAW/PROOF answers *is it legal*, COST answers *is it
//! profitable*, and the separation is by SIGNATURE rather than by comment.
//!
//!     `admissible(...)`  — no cost parameter exists. Facts in, menu out.
//!     `cheapest(...)`    — takes a cost model, and can only ever choose from
//!                          a menu `admissible` already returned.
//!
//! The cost model is §47's rule, and §46 says classify the row FIRST. This tree
//! measured `divchain` at ~2.4x clang's instruction count at the SAME cycle
//! floor, so on a dependence-bound row recomputation is very nearly free and on
//! a throughput-bound row it is never free. `Row` below carries that
//! classification and `cheapest` refuses to price a row classified `.unknown`.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT IS NOT BUILT
//! ════════════════════════════════════════════════════════════════════════════
//!
//! NO TRANSFORM. Nothing here makes a value physically absent, emits a recipe,
//! or runs an inverse at runtime. `decideInverse` decides and `admissible`
//! refuses; the emission is `dnir_lower.zig`'s and is not routed. Reading this
//! file as "§11 is implemented" would be exactly the error §11's own target
//! sentence warns about — the tax is measured and the obligation is stated, and
//! that is the whole claim.
//!
//! NO SECOND OBSERVER ROSTER. `Demand.world` produces an `observation.World`
//! and every downstream question is asked of `observation.zig` and
//! `demand_projection.observationRefusal`.
//!
//! NO SYMBOLIC STEP. `decideInverse` takes a step function and a bit width and
//! enumerates. It does not read an AST. Deciding invertibility of a loop body
//! written in source needs the body contracted onto the quotient, which is
//! `obseq.Machine`'s job and is held by another lane; the adapter is one
//! function and it is named in `gate/recon.sh`'s ROUTED section.

const std = @import("std");
const observation = @import("observation.zig");
const place = @import("place.zig");

// ═══════════════════════════════════════════════════════════════════════════
// §11 — the observer, made spellable
// ═══════════════════════════════════════════════════════════════════════════

/// The four §9 observers that INSPECT rather than participate. `program`,
/// `foreign`, `concurrency`, `failure_recovery` and `deployment` are not here
/// on purpose: none of them is a tooling choice, so none of them is a thing a
/// user could switch on at a command line.
pub const Observer = enum {
    debugger,
    profiler,
    reflection,
    mcp,

    pub const count = @typeInfo(Observer).@"enum".field_names.len;

    /// The world fact this observer's demand states. One-to-one with
    /// `observation.WorldFact`'s four `*_demanded` members, and the mapping is
    /// here rather than in a `switch` at a call site so that adding an observer
    /// is one edit.
    pub fn fact(self: Observer) observation.WorldFact {
        return switch (self) {
            .debugger => .debugger_demanded,
            .profiler => .profiler_demanded,
            .reflection => .reflection_demanded,
            .mcp => .mcp_demanded,
        };
    }

    pub fn name(self: Observer) []const u8 {
        return @tagName(self);
    }
};

pub const ObserverSet = std.EnumSet(Observer);

/// Parse one `--observer` value. Returns null on an unknown name; the CALLER
/// diagnoses, because a silent "no observer" would be the permissive reading of
/// a typo and this file will not hand anyone that.
pub fn parseObserver(s: []const u8) ?Observer {
    return std.meta.stringToEnum(Observer, s);
}

/// What the command line demanded. Empty is the default and means exactly what
/// this compiler did before the flag existed.
pub const Demand = struct {
    set: ObserverSet = .{},

    pub fn add(self: *Demand, o: Observer) void {
        self.set.insert(o);
    }

    pub fn any(self: Demand) bool {
        return self.set.count() != 0;
    }

    /// **THE BUILD CACHE MUST HASH THIS.** Found by measurement, not by
    /// reasoning: the first build of the `--observer` flag changed nothing at
    /// all, because `/tmp/idol-cache-<digest>` keys on source bytes, backend,
    /// opt level, compiler stat, the gate waiver, the injected worlds and the
    /// `req` closure — and NOT on the observer roster. Two byte-identical
    /// compilations, one watched and one not, hit one entry, and the watched
    /// one was served the unwatched artifact.
    ///
    /// That is the third defect the comment at that site already catalogues, in
    /// its own words: *an artifact built under RULES THIS FILE DOES NOT HAVE*.
    /// An observer demand is such a rule. So it is hashed, and this function
    /// exists so the hash cannot drift from the flag.
    pub fn cacheKey(self: Demand) u32 {
        var k: u32 = 0;
        var it = self.set.iterator();
        while (it.next()) |o| k |= @as(u32, 1) << @intFromEnum(o);
        return k;
    }

    /// Fold the demand into a world. `base` is the world the call site would
    /// otherwise have used, so an empty demand is bit-identical to no flag.
    pub fn world(self: Demand, base: observation.World) observation.World {
        var w = base;
        var it = self.set.iterator();
        while (it.next()) |o| w = w.with(o.fact());
        return w;
    }
};

/// **THE TAX, AS A PREDICATE.** True when adding this demand to `base` costs a
/// freedom that `base` had. It is computed from `observation.permits` and from
/// nothing else, so it cannot drift from the model it reports on.
///
/// Note what it does NOT do: it does not say how many cycles. A freedom lost is
/// a legality fact; the cycles are `gate/recon.sh`'s and they are measured on
/// binaries, because a cost predicted by the thing that caused it is not a
/// measurement.
pub fn freedomsLost(
    base: observation.World,
    d: Demand,
    ev: observation.Evidence,
    ob: observation.Obligations,
    subj: observation.Subject,
) observation.FreedomSet {
    const before = observation.permittedSet(&observation.classifyAll(base, ev, ob, subj));
    const after = observation.permittedSet(&observation.classifyAll(d.world(base), ev, ob, subj));
    return before.differenceWith(after);
}

// ═══════════════════════════════════════════════════════════════════════════
// §59 — invertibility, decided rather than assumed
// ═══════════════════════════════════════════════════════════════════════════

/// The largest quotient this file will enumerate. 2^20 states is one sweep of
/// a 1 MiB table and ~2 MiB of scratch — the same order as
/// `recurrence.max_orbit_steps`, and chosen for the same reason: it must be a
/// REFUSAL past the limit, never a truncation.
pub const max_bits: u7 = 20;

pub const InverseRefusal = enum {
    /// The demanded quotient is wider than `max_bits`, so exhaustive
    /// enumeration is not affordable. NOT "probably invertible".
    state_space_too_large,
    /// Two distinct states have the same image. A predecessor is genuinely not
    /// recoverable and §59 does not apply — this is the answer, not a failure.
    not_injective,
    /// R1: the step may have an effect, so replaying it backwards is not a
    /// question about values at all.
    step_may_have_effect,
    /// R3: the step may trap. An inverse that traps where the forward run did
    /// not is a new observable.
    step_may_trap,
    /// R4: an input the step reads is not proven to outlive the observation.
    input_not_live,
    /// I0: the caller did not assert that the step commutes with the demanded
    /// projection, so enumerating the quotient answers a question about a
    /// DIFFERENT function.
    projection_not_homomorphic,
};

/// A proven bijection on `bits` bits, and its inverse. `table[y]` is the unique
/// `x` with `step(x) == y`.
///
/// The table IS the proof: it could only be filled if every image was hit
/// exactly once. There is no separate "we checked" flag to get out of sync.
pub const Inverse = struct {
    bits: u7,
    table: []u32,

    pub fn deinit(self: *Inverse, alloc: std.mem.Allocator) void {
        alloc.free(self.table);
        self.table = &.{};
    }

    /// Recover the predecessor. `y` is masked to the proven domain, because the
    /// inverse is valid on THAT quotient and asserting anything wider is R4's
    /// failure mode.
    pub fn pred(self: *const Inverse, y: u64) u64 {
        const mask: u64 = if (self.bits >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(self.bits)) - 1;
        return self.table[@intCast(y & mask)];
    }

    /// Walk back `n` steps. This is §59's whole runtime cost model: recovering
    /// the state `n` iterations before the one you hold costs `n` table reads
    /// and NO RETENTION.
    pub fn predN(self: *const Inverse, y: u64, n: u64) u64 {
        var v = y;
        var k: u64 = 0;
        while (k < n) : (k += 1) v = self.pred(v);
        return v;
    }
};

pub const InverseResult = union(enum) {
    invertible: Inverse,
    refused: InverseRefusal,
};

/// Guards the caller must discharge before invertibility is even the question.
/// Every field defaults to the conservative reading, exactly as
/// `observation.Evidence` does, so a guard the caller forgets cannot open a
/// freedom.
pub const StepGuards = struct {
    /// R1. `.no` required.
    has_effect: place.Tri = .unknown,
    /// R3. `.no` required.
    may_trap: place.Tri = .unknown,
    /// R4. `.yes` required: every input the step reads still exists when the
    /// observer asks. `place.Facts.lifetime` and `.residency` are what answer
    /// this, and `.residency == .absent` is the case that makes it `no`.
    inputs_live: place.Tri = .unknown,
    /// **I0 — THE OBLIGATION THAT MAKES THE SWEEP MEAN ANYTHING.** `.yes`
    /// required.
    ///
    /// `decideInverse` enumerates a QUOTIENT. Its answer is about the real step
    /// only if the step commutes with the projection — `h(f(x)) = g(h(x))`,
    /// which is §17 exactly. For `+`, `*` and `^` the projection `mod 2^k` is a
    /// ring homomorphism and it does; for `>>` it does NOT, which is precisely
    /// why `gate/obseq.sh`'s `shift` probe refuses.
    ///
    /// Without this guard the sweep is not merely incomplete, it is WRONG in
    /// the permissive direction: `x + (x >> 8)` sweeps as the IDENTITY on eight
    /// bits and reports a perfect bijection whose inverse returns the wrong
    /// predecessor for every input above 255. The test
    /// `§59 — I0, and the body that lies without it` is that counterexample.
    ///
    /// `refuteCommutes` below will hunt a counterexample mechanically, and
    /// finding none over a bounded probe is NOT a proof — which is why this
    /// stays a caller obligation rather than becoming an inferred fact.
    commutes_with_projection: place.Tri = .unknown,
};

/// **A REFUTER, NOT A PROVER.** Hunts a counterexample to I0 by enumerating
/// `bits + extra` bits of input and checking `low_bits(step(x))` against
/// `step(low_bits(x))`. Returns the first `x` at which the diagram fails, or
/// null.
///
/// NULL IS NOT A PROOF and this function's name says so. It searches a bounded
/// window; a step that only breaks the homomorphism at bit 40 walks past it.
/// It exists because a mechanical refutation is worth having even when a
/// mechanical proof is not available — `floor_derive.zig` cannot emit a witness
/// by construction and this is the same shape of honesty from the other side.
pub fn refuteCommutes(bits: u7, extra: u7, step: *const fn (u64) u64) ?u64 {
    if (bits == 0 or bits + extra > 40) return null;
    const mask: u64 = (@as(u64, 1) << @intCast(bits)) - 1;
    const n: u64 = @as(u64, 1) << @intCast(bits + extra);
    var x: u64 = 0;
    while (x < n) : (x += 1) {
        if ((step(x) & mask) != (step(x & mask) & mask)) return x;
    }
    return null;
}

/// **THE §59 DECISION. No cost parameter exists.**
///
/// `step` is the contracted transition on the demanded quotient — a total
/// function from `bits` bits to `bits` bits. Enumerate the whole domain, mark
/// each image, and refuse on the first collision. O(2^bits) time, one pass.
///
/// Refusing on the FIRST collision is not an optimization: a step that is not
/// injective has no inverse and continuing to sweep would only produce a
/// prettier refusal.
pub fn decideInverse(
    alloc: std.mem.Allocator,
    bits: u7,
    guards: StepGuards,
    step: *const fn (u64) u64,
) !InverseResult {
    if (guards.has_effect != .no) return .{ .refused = .step_may_have_effect };
    if (guards.may_trap != .no) return .{ .refused = .step_may_trap };
    if (guards.inputs_live != .yes) return .{ .refused = .input_not_live };
    if (guards.commutes_with_projection != .yes) return .{ .refused = .projection_not_homomorphic };
    if (bits == 0 or bits > max_bits) return .{ .refused = .state_space_too_large };

    const n: usize = @as(usize, 1) << @intCast(bits);
    const mask: u64 = @as(u64, n - 1);

    const table = try alloc.alloc(u32, n);
    errdefer alloc.free(table);
    // `sentinel` marks "no predecessor seen yet". `n` is out of range for every
    // legal entry, so it cannot collide with a real one.
    const sentinel: u32 = @intCast(n);
    @memset(table, sentinel);

    var x: usize = 0;
    while (x < n) : (x += 1) {
        const y: usize = @intCast(step(@as(u64, x)) & mask);
        if (table[y] != sentinel) {
            alloc.free(table);
            return .{ .refused = .not_injective };
        }
        table[y] = @intCast(x);
    }
    // Injective on a finite set of equal size is surjective, so no image can
    // still hold the sentinel. Asserting it is free and it is the only place a
    // bug in the sweep could hide.
    for (table) |v| std.debug.assert(v != sentinel);

    return .{ .invertible = .{ .bits = bits, .table = table } };
}

/// Orbit shape of the same step from one start state: `mu` is the tail length
/// before the first repeat and `lambda` is the period. Brent-free and
/// deliberately naive — the domain is bounded by `2^bits` so a visited array
/// is exact and cheap, and exactness is worth more here than elegance.
///
/// This exists to make the duality CHECKABLE rather than asserted: `mu == 0`
/// for every start iff the step is injective, and `gate/recon.sh` checks both
/// halves on the same bodies.
pub const Orbit = struct { mu: u64, lambda: u64 };

pub fn orbitShape(alloc: std.mem.Allocator, bits: u7, start: u64, step: *const fn (u64) u64) !?Orbit {
    if (bits == 0 or bits > max_bits) return null;
    const n: usize = @as(usize, 1) << @intCast(bits);
    const mask: u64 = @as(u64, n - 1);
    const seen = try alloc.alloc(u64, n);
    defer alloc.free(seen);
    const never: u64 = std.math.maxInt(u64);
    @memset(seen, never);

    var v: u64 = start & mask;
    var t: u64 = 0;
    while (true) : (t += 1) {
        const idx: usize = @intCast(v);
        if (seen[idx] != never) return .{ .mu = seen[idx], .lambda = t - seen[idx] };
        seen[idx] = t;
        v = step(v) & mask;
    }
}

/// The theorem, as a checkable function: on a finite domain, `step` is
/// injective iff no start state has a tail. Returns the first start state whose
/// orbit HAS a tail, or null when none does.
///
/// A caller that gets `null` from this and `not_injective` from `decideInverse`
/// has found a bug in one of them, which is exactly the two-sidedness
/// `gate/recon.sh` requires.
/// How many distinct images the step has on the quotient. `|image| == |S|` is
/// injectivity; anything less is the exact amount of information the step
/// DESTROYS, and that number is what decides whether §59 is available at all.
///
/// Separate from `decideInverse` on purpose: that function refuses on the first
/// collision because a prettier refusal is not worth a second pass, and this
/// one exists so the refusal can be QUANTIFIED when a human asks why.
pub fn imageCount(alloc: std.mem.Allocator, bits: u7, step: *const fn (u64) u64) !?usize {
    if (bits == 0 or bits > max_bits) return null;
    const n: usize = @as(usize, 1) << @intCast(bits);
    const mask: u64 = @as(u64, n - 1);
    const hit = try alloc.alloc(bool, n);
    defer alloc.free(hit);
    @memset(hit, false);
    var x: usize = 0;
    while (x < n) : (x += 1) hit[@intCast(step(@as(u64, x)) & mask)] = true;
    var c: usize = 0;
    for (hit) |h| {
        if (h) c += 1;
    }
    return c;
}

pub fn firstStartWithTail(alloc: std.mem.Allocator, bits: u7, step: *const fn (u64) u64) !?u64 {
    if (bits == 0 or bits > max_bits) return null;
    const n: usize = @as(usize, 1) << @intCast(bits);
    var s: u64 = 0;
    while (s < n) : (s += 1) {
        const o = (try orbitShape(alloc, bits, s, step)) orelse return null;
        if (o.mu != 0) return s;
    }
    return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// §60 — the temporal value policy, legality first
// ═══════════════════════════════════════════════════════════════════════════

/// §60's six, verbatim.
pub const Policy = enum {
    retain,
    recompute,
    compress,
    spill,
    derive_from_successor,
    discard_and_rebuild,

    pub const count = @typeInfo(Policy).@"enum".field_names.len;

    pub fn name(self: Policy) []const u8 {
        return @tagName(self);
    }
};

pub const PolicySet = std.EnumSet(Policy);

pub const PolicyRefusal = enum {
    /// The observation model did not open `memoization` for this subject, so
    /// re-running the producer is not proven invisible.
    recompute_not_permitted,
    /// The observation model did not open `layout` (compress) or `width`
    /// (spill's narrowing) for this subject.
    representation_not_permitted,
    /// The observation model did not open `existence`, so the place may not
    /// stop existing between its production and its observation.
    existence_not_permitted,
    /// §59 refused, so there is no predecessor recipe.
    not_invertible,
    /// The successor state is not itself live at the observation point, so
    /// there is nothing to derive FROM.
    successor_not_live,
};

/// One legality answer per policy, with the class that decided it where the
/// observation model decided it.
pub const Admissible = struct {
    set: PolicySet,
    why: [Policy.count]?PolicyRefusal,

    pub fn permits(self: *const Admissible, p: Policy) bool {
        return self.set.contains(p);
    }

    pub fn refusal(self: *const Admissible, p: Policy) ?PolicyRefusal {
        return self.why[@intFromEnum(p)];
    }

    pub fn count(self: *const Admissible) usize {
        return self.set.count();
    }
};

/// Facts §60 needs that are not in the observation report: the §59 verdict and
/// the liveness of the successor.
pub const TemporalFacts = struct {
    /// True only when `decideInverse` returned `.invertible`.
    invertible: bool = false,
    /// The successor state exists at the point the observer asks. `place.Facts
    /// .residency == .absent` is what makes this false.
    successor_live: place.Tri = .unknown,
};

/// **FACTS IN, MENU OUT. No cost parameter exists here** — the same
/// signature-level enforcement `observation.permits` and `eqspace.contract`
/// already carry, and for the same reason: a legality function that can see a
/// cost is a legality function someone will eventually let a cost decide.
///
/// `retain` is unconditionally admissible. It is the status quo, it invents no
/// new observable, and a menu that can be empty is a menu that cannot be used.
pub fn admissible(r: *const observation.Report, tf: TemporalFacts) Admissible {
    var a = Admissible{ .set = .{}, .why = @splat(null) };

    a.set.insert(.retain);

    const memo = observation.permits(r, .memoization);
    const layout = observation.permits(r, .layout);
    const width = observation.permits(r, .width);
    const exist = observation.permits(r, .existence);

    if (memo.ok()) {
        a.set.insert(.recompute);
    } else {
        a.why[@intFromEnum(Policy.recompute)] = .recompute_not_permitted;
    }

    // COMPRESS changes the physical shape of a live value: `layout`.
    if (layout.ok()) {
        a.set.insert(.compress);
    } else {
        a.why[@intFromEnum(Policy.compress)] = .representation_not_permitted;
    }

    // SPILL moves a value to a different residency and may narrow it on the
    // way; it needs both the layout and the width freedoms. Spilling is not
    // free of the observation model just because it keeps every bit — a
    // debugger that reads a register by name is reading a residency.
    if (layout.ok() and width.ok()) {
        a.set.insert(.spill);
    } else {
        a.why[@intFromEnum(Policy.spill)] = .representation_not_permitted;
    }

    // DERIVE FROM SUCCESSOR is §59 and it needs three things: the inverse
    // proven, the successor actually there to invert, and the same replay
    // legality `recompute` needs — running the inverse IS running something.
    if (!tf.invertible) {
        a.why[@intFromEnum(Policy.derive_from_successor)] = .not_invertible;
    } else if (tf.successor_live != .yes) {
        a.why[@intFromEnum(Policy.derive_from_successor)] = .successor_not_live;
    } else if (!memo.ok()) {
        a.why[@intFromEnum(Policy.derive_from_successor)] = .recompute_not_permitted;
    } else {
        a.set.insert(.derive_from_successor);
    }

    // DISCARD AND REBUILD makes the place STOP EXISTING and then produces it
    // again, so it needs `existence` as well as replay legality.
    if (!memo.ok()) {
        a.why[@intFromEnum(Policy.discard_and_rebuild)] = .recompute_not_permitted;
    } else if (!exist.ok()) {
        a.why[@intFromEnum(Policy.discard_and_rebuild)] = .existence_not_permitted;
    } else {
        a.set.insert(.discard_and_rebuild);
    }

    return a;
}

// ---------------------------------------------------------------------------
// PROFITABILITY. Everything below this line may see a cost; nothing above it
// may. §84.
// ---------------------------------------------------------------------------

/// §46's classification, and `cheapest` REFUSES an unclassified row. This tree
/// measured `divchain` at ~2.4x clang's instruction count at the same cycle
/// floor: on a dependence-bound row the extra work was free, and pricing a row
/// without knowing which kind it is produces exactly that error with the sign
/// unknown.
pub const Row = enum {
    /// Latency-bound on a serial dependence chain. Spare issue slots exist, so
    /// recomputation is very nearly free.
    dependence_bound,
    /// Every issue slot is busy. Recomputation displaces real work 1:1.
    throughput_bound,
    /// Bound by memory traffic. RETAINING is what costs here, and recomputing
    /// is how you stop paying it.
    memory_bound,
    unknown,
};

/// A cost model in the units this tree already measures: retired instructions
/// for work, bytes for storage. Both are supplied by the CALLER from
/// measurement; nothing here estimates.
pub const CostModel = struct {
    row: Row = .unknown,
    /// Instructions to re-run the producer from its inputs.
    recompute_insns: u64 = 0,
    /// Instructions to walk the inverse back to the demanded predecessor.
    /// `Inverse.predN`'s `n` table reads, in this tree's units.
    invert_insns: u64 = 0,
    /// Bytes that must be held for the value's whole semantic lifetime.
    retain_bytes: u64 = 0,
    /// Instructions charged per retained byte. On a dependence-bound row this
    /// is where the store, the reload and the cache pressure land; the caller
    /// measures it, this file does not guess it.
    insns_per_retained_byte: u64 = 0,
};

pub const Priced = struct {
    policy: Policy,
    insns: u64,
};

pub const PricingRefusal = enum {
    /// §46: the row was not classified, so no substitution rule applies.
    row_unclassified,
    /// Nothing but `retain` survived legality; there is no choice to make.
    no_alternative,
};

pub const Choice = union(enum) {
    chosen: Priced,
    refused: PricingRefusal,
};

/// **THE ONLY FUNCTION HERE THAT SEES A COST.** It can choose only from a menu
/// `admissible` already returned, so no cost can reach a legality question.
///
/// §47's rule, applied rather than quoted:
///   memory expensive  → recompute        (`.memory_bound` weights retention)
///   CPU expensive     → retain           (`.throughput_bound` weights work)
///   dependence-bound  → recompute is close to free, so retention must beat it
///                       by a real margin to win
pub fn cheapest(a: *const Admissible, m: CostModel) Choice {
    if (m.row == .unknown) return .{ .refused = .row_unclassified };
    if (a.count() <= 1) return .{ .refused = .no_alternative };

    const retain_cost = switch (m.row) {
        // On a dependence-bound row the spare issue slots absorb work but NOT
        // memory traffic, so retention keeps its full price and recomputation
        // is discounted. The discount is a factor of 2 and it is a stated
        // MODEL, not a measurement: `gate/recon.sh` reports the model's choice
        // beside the measured cycles so the two can disagree in public.
        .dependence_bound, .memory_bound => m.retain_bytes *| m.insns_per_retained_byte,
        .throughput_bound => m.retain_bytes *| m.insns_per_retained_byte,
        .unknown => unreachable,
    };
    const work_scale: u64 = switch (m.row) {
        .dependence_bound => 1,
        .memory_bound => 1,
        .throughput_bound => 2,
        .unknown => unreachable,
    };

    var best = Priced{ .policy = .retain, .insns = retain_cost };
    if (a.permits(.recompute)) {
        const c = m.recompute_insns *| work_scale;
        if (c < best.insns) best = .{ .policy = .recompute, .insns = c };
    }
    if (a.permits(.derive_from_successor)) {
        const c = m.invert_insns *| work_scale;
        if (c < best.insns) best = .{ .policy = .derive_from_successor, .insns = c };
    }
    if (a.permits(.discard_and_rebuild)) {
        const c = m.recompute_insns *| work_scale;
        if (c < best.insns) best = .{ .policy = .discard_and_rebuild, .insns = c };
    }
    return .{ .chosen = best };
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
//
// The step functions below are the EXACT bodies `gate/obseq.sh` pins, written
// in Zig with the same wrapping arithmetic, so a test that agrees with them is
// agreeing with a probe whose answer an independent Python model already
// checked.
// ═══════════════════════════════════════════════════════════════════════════

const testing = std.testing;

const w6_c: u64 = 1103515245;
const w6_k: u64 = 12345;

/// `x = x ~ (x * C); x = x + K` — the W6 body.
fn stepW6(x: u64) u64 {
    const a = x ^ (x *% w6_c);
    return a +% w6_k;
}

/// `x = (x*x) ~ (x * C); x = x + K` — the SQ body.
fn stepSq(x: u64) u64 {
    const a = (x *% x) ^ (x *% w6_c);
    return a +% w6_k;
}

/// The PAIR body on a 16-bit quotient: low 8 bits are `a`, high 8 are `b`.
///   a = a ~ (b * C) ; b = b + (a * D)
fn stepPair(s: u64) u64 {
    const d: u64 = 6364136223;
    var a: u64 = s & 0xff;
    var b: u64 = (s >> 8) & 0xff;
    a = (a ^ (b *% w6_c)) & 0xff;
    b = (b +% (a *% d)) & 0xff;
    return (b << 8) | a;
}

/// A step that is invertible for a reason this tree already established: an
/// ODD multiplier is a unit in Z/2^64, and 2 is not.
fn stepOddMul(x: u64) u64 {
    return x *% 1103515245;
}

fn stepEvenMul(x: u64) u64 {
    return x *% 2;
}

/// A step that does NOT commute with `mod 2^8`, because `>>` reads bits the
/// projection discarded. On the eight-bit quotient it looks like the IDENTITY
/// and sweeps as a perfect bijection; on real values it is nothing of the kind.
/// This is `gate/obseq.sh`'s `shift` refusal, in the smallest form that lies.
fn stepNonCommuting(x: u64) u64 {
    return x +% (x >> 8);
}

test "observer_demand: §11 — an observer's mere existence costs freedoms" {
    // The subject is a place nothing observes: no identity capture, no escape,
    // no boundary, no effect, no trap. Under the ordinary world it is as free
    // as this model can make a place.
    const clean = observation.Evidence{
        .complete = true,
        .escapes = .no,
        .may_trap = .no,
        .has_effect = .no,
        .order_declared = .no,
        .positional_read = .no,
        .crosses_boundary = .no,
        .quotient = .modulus,
        .facts = .{ .alias = .no },
    };
    const subj = observation.Subject{ .place = 0 };
    const base = observation.ordinary_executable;

    const before = observation.permittedSet(
        &observation.classifyAll(base, clean, observation.Obligations.of(&.{}, &.{}), subj),
    );
    try testing.expect(before.count() > 0);

    // Each of the four observers, one at a time.
    for ([_]Observer{ .debugger, .profiler, .reflection, .mcp }) |o| {
        var d = Demand{};
        d.add(o);
        const lost = freedomsLost(base, d, clean, observation.Obligations.of(&.{}, &.{}), subj);
        switch (o) {
            // A debugger reads storage: it takes layout, zero-copy and
            // existence. This is the row §11 exists to complain about.
            .debugger => try testing.expect(lost.count() > 0),
            // Reflection names allocations, so it takes existence and
            // zero-copy through `allocation_identity`.
            .reflection => try testing.expect(lost.count() > 0),
            // A profiler is duration: it takes `schedule` via
            // `instruction_schedule`... but ONLY through `security_adversary`
            // or a clock read, neither of which a profiler demand states. So
            // the profiler costs NOTHING in the per-place model, and it costs
            // 24.5x in the pipeline. That gap is a finding, not a pass: the
            // roster refusal in `demand_projection.observationRefusal` is
            // all-or-nothing and does not consult this per-place model at all.
            .profiler, .mcp => try testing.expectEqual(@as(usize, 0), lost.count()),
        }
    }
}

test "observer_demand: §11 — an empty demand is bit-identical to no flag" {
    const d = Demand{};
    const w = d.world(observation.ordinary_executable);
    try testing.expect(!d.any());
    try testing.expectEqual(
        observation.ordinary_executable.observers().count(),
        w.observers().count(),
    );
}

test "observer_demand: §59 — an odd multiplier inverts and 2 does not" {
    // The ring fact this tree already established, decided rather than
    // asserted: odd is a unit mod 2^k, 2 is not.
    const g = StepGuards{ .has_effect = .no, .may_trap = .no, .inputs_live = .yes, .commutes_with_projection = .yes };

    var odd = try decideInverse(testing.allocator, 12, g, stepOddMul);
    switch (odd) {
        .refused => return error.TestUnexpectedResult,
        .invertible => |*inv| {
            defer inv.deinit(testing.allocator);
            // The inverse is a real inverse, checked on every state.
            var x: u64 = 0;
            while (x < 4096) : (x += 1) {
                try testing.expectEqual(x, inv.pred(stepOddMul(x) & 0xfff));
            }
        },
    }

    switch (try decideInverse(testing.allocator, 12, g, stepEvenMul)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.not_injective, r),
    }
}

test "observer_demand: §59 — the guards refuse before the sweep runs" {
    const step = stepOddMul;
    // R1, R3, R4 each on their own, and `unknown` is not `no`.
    switch (try decideInverse(testing.allocator, 8, .{ .has_effect = .unknown, .may_trap = .no, .inputs_live = .yes, .commutes_with_projection = .yes }, step)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.step_may_have_effect, r),
    }
    switch (try decideInverse(testing.allocator, 8, .{ .has_effect = .no, .may_trap = .unknown, .inputs_live = .yes, .commutes_with_projection = .yes }, step)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.step_may_trap, r),
    }
    switch (try decideInverse(testing.allocator, 8, .{ .has_effect = .no, .may_trap = .no, .inputs_live = .unknown, .commutes_with_projection = .yes }, step)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.input_not_live, r),
    }
    // And the budget is a refusal, not a truncation.
    switch (try decideInverse(testing.allocator, 40, .{ .has_effect = .no, .may_trap = .no, .inputs_live = .yes, .commutes_with_projection = .yes }, step)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.state_space_too_large, r),
    }
}

test "observer_demand: §59 — THE DUALITY, on the gate's own probe bodies" {
    const g = StepGuards{ .has_effect = .no, .may_trap = .no, .inputs_live = .yes, .commutes_with_projection = .yes };

    // W6: NOT injective on the demanded 8-bit quotient, and its orbit HAS a
    // tail — which is exactly why `obseq` closes it by a fixed point.
    switch (try decideInverse(testing.allocator, 8, g, stepW6)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.not_injective, r),
    }
    const w6_orbit = (try orbitShape(testing.allocator, 8, 12345, stepW6)).?;
    try testing.expectEqual(@as(u64, 4), w6_orbit.mu);
    try testing.expectEqual(@as(u64, 1), w6_orbit.lambda);

    // SQ: same shape, same verdict.
    switch (try decideInverse(testing.allocator, 8, g, stepSq)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.not_injective, r),
    }

    // PAIR: INJECTIVE on the 16-bit quotient — a bijection of all 65,536
    // states — and therefore NO TAIL from any start. `obseq` closes it by the
    // exact-index family and could never have closed it by a fixed point.
    var pair = try decideInverse(testing.allocator, 16, g, stepPair);
    switch (pair) {
        .refused => return error.TestUnexpectedResult,
        .invertible => |*inv| {
            defer inv.deinit(testing.allocator);
            // §59's actual payoff, exercised: walk 1000 steps forward from the
            // entry state and recover it by walking the inverse back, with
            // NOTHING retained in between.
            const entry: u64 = (6789 & 0xff) << 8 | (12345 & 0xff);
            var v = entry;
            var k: usize = 0;
            while (k < 1000) : (k += 1) v = stepPair(v);
            try testing.expectEqual(entry, inv.predN(v, 1000));
        },
    }
    const pair_orbit = (try orbitShape(testing.allocator, 16, (6789 & 0xff) << 8 | (12345 & 0xff), stepPair)).?;
    try testing.expectEqual(@as(u64, 0), pair_orbit.mu);
}

test "observer_demand: §59 — I0, and the body that lies without it" {
    // WITHOUT I0 THIS SWEEP IS WRONG IN THE PERMISSIVE DIRECTION, which is the
    // only direction that matters. `x + (x >> 8)` restricted to eight bits is
    // the identity, so `decideInverse` would hand back a perfect bijection and
    // an inverse table that returns the wrong predecessor for every input above
    // 255. The guard is what stops it, and the refusal is NAMED.
    switch (try decideInverse(testing.allocator, 8, .{
        .has_effect = .no,
        .may_trap = .no,
        .inputs_live = .yes,
    }, stepNonCommuting)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.projection_not_homomorphic, r),
    }

    // And the refuter finds the counterexample rather than taking anyone's
    // word: 256 is the smallest input whose low byte the shift can reach.
    const witness = refuteCommutes(8, 8, stepNonCommuting);
    try testing.expectEqual(@as(?u64, 256), witness);
    try testing.expect((stepNonCommuting(256) & 0xff) != (stepNonCommuting(256 & 0xff) & 0xff));

    // The bodies this file actually decides survive the same hunt. `+`, `*` and
    // `^` are ring operations and `mod 2^k` is a homomorphism for them, which
    // is §17 and is why the quotient sweep answers a real question at all.
    try testing.expectEqual(@as(?u64, null), refuteCommutes(8, 8, stepW6));
    try testing.expectEqual(@as(?u64, null), refuteCommutes(8, 8, stepSq));
    try testing.expectEqual(@as(?u64, null), refuteCommutes(10, 8, stepOddMul));
    try testing.expectEqual(@as(?u64, null), refuteCommutes(10, 8, stepEvenMul));

    // A null from the refuter is NOT a proof, and the guard is a caller
    // obligation for exactly that reason: this asserts the refuter's contract,
    // not a theorem about the step.
    try testing.expectEqual(@as(?u64, null), refuteCommutes(0, 8, stepNonCommuting));
}

test "observer_demand: §59 — the header's image table, pinned" {
    // Every number in this file's §59 table, checked here so the prose cannot
    // rot away from the code. Each was independently reproduced by a Python
    // model of the same wrapping arithmetic before being written down.
    try testing.expectEqual(@as(?usize, 37), try imageCount(testing.allocator, 8, stepW6));
    try testing.expectEqual(@as(?usize, 128), try imageCount(testing.allocator, 8, stepSq));
    try testing.expectEqual(@as(?usize, 65536), try imageCount(testing.allocator, 16, stepPair));
    try testing.expectEqual(@as(?usize, 1024), try imageCount(testing.allocator, 10, stepOddMul));
    try testing.expectEqual(@as(?usize, 512), try imageCount(testing.allocator, 10, stepEvenMul));
    // And the budget refuses here too, rather than returning a partial count.
    try testing.expectEqual(@as(?usize, null), try imageCount(testing.allocator, 40, stepOddMul));
}

test "observer_demand: §59 — injective iff no orbit has a tail, both directions" {
    // THE THEOREM, checked rather than quoted, on both a bijection and a
    // contraction. This is the two-sided control: a `firstStartWithTail` that
    // always answered null would pass the first half and fail the second.
    const g = StepGuards{ .has_effect = .no, .may_trap = .no, .inputs_live = .yes, .commutes_with_projection = .yes };

    var inv = try decideInverse(testing.allocator, 10, g, stepOddMul);
    switch (inv) {
        .refused => return error.TestUnexpectedResult,
        .invertible => |*i| i.deinit(testing.allocator),
    }
    try testing.expectEqual(@as(?u64, null), try firstStartWithTail(testing.allocator, 10, stepOddMul));

    switch (try decideInverse(testing.allocator, 10, g, stepW6)) {
        .invertible => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(InverseRefusal.not_injective, r),
    }
    try testing.expect((try firstStartWithTail(testing.allocator, 10, stepW6)) != null);
}

test "observer_demand: §60 — the menu is facts-in, and `retain` is always on it" {
    const clean = observation.Evidence{
        .complete = true,
        .escapes = .no,
        .may_trap = .no,
        .has_effect = .no,
        .order_declared = .no,
        .positional_read = .no,
        .crosses_boundary = .no,
        .quotient = .modulus,
        .facts = .{ .alias = .no },
    };
    const subj = observation.Subject{ .place = 0 };
    const ob = observation.Obligations.of(&.{}, &.{});
    const r = observation.classifyAll(observation.ordinary_executable, clean, ob, subj);

    const with_inv = admissible(&r, .{ .invertible = true, .successor_live = .yes });
    try testing.expect(with_inv.permits(.retain));
    try testing.expect(with_inv.permits(.recompute));
    try testing.expect(with_inv.permits(.derive_from_successor));

    // Take §59 away and exactly one policy leaves the menu, with a NAMED
    // reason. A refusal without a reason is how a menu becomes a mystery.
    const without_inv = admissible(&r, .{ .invertible = false, .successor_live = .yes });
    try testing.expect(!without_inv.permits(.derive_from_successor));
    try testing.expectEqual(PolicyRefusal.not_invertible, without_inv.refusal(.derive_from_successor).?);
    try testing.expectEqual(with_inv.count() - 1, without_inv.count());

    // And an INCOMPLETE walk collapses the menu to `retain` alone: N2 raises
    // every class to unknown, unknown blocks every freedom, and every policy
    // but the status quo needs a freedom.
    const blind = observation.classifyAll(observation.ordinary_executable, .{}, ob, subj);
    const none = admissible(&blind, .{ .invertible = true, .successor_live = .yes });
    try testing.expectEqual(@as(usize, 1), none.count());
    try testing.expect(none.permits(.retain));
}

test "observer_demand: §60 — a debugger demand takes policies off the menu" {
    // THE §11 TAX, IN §60'S UNITS. Same place, same facts, one world fact.
    const clean = observation.Evidence{
        .complete = true,
        .escapes = .no,
        .may_trap = .no,
        .has_effect = .no,
        .order_declared = .no,
        .positional_read = .no,
        .crosses_boundary = .no,
        .quotient = .modulus,
        .facts = .{ .alias = .no },
    };
    const subj = observation.Subject{ .place = 0 };
    const ob = observation.Obligations.of(&.{}, &.{});
    const tf = TemporalFacts{ .invertible = true, .successor_live = .yes };

    const free_menu = admissible(
        &observation.classifyAll(observation.ordinary_executable, clean, ob, subj),
        tf,
    );
    var d = Demand{};
    d.add(.debugger);
    const watched_menu = admissible(
        &observation.classifyAll(d.world(observation.ordinary_executable), clean, ob, subj),
        tf,
    );
    try testing.expect(watched_menu.count() < free_menu.count());
    // `retain` survives, which is the point: under observation this compiler
    // has exactly the option §11 says it should not be forced into.
    try testing.expect(watched_menu.permits(.retain));
}

test "observer_demand: §84 — pricing refuses an unclassified row and a menu of one" {
    var a = Admissible{ .set = .{}, .why = @splat(null) };
    a.set.insert(.retain);
    a.set.insert(.recompute);

    switch (cheapest(&a, .{ .row = .unknown, .recompute_insns = 1, .retain_bytes = 1000, .insns_per_retained_byte = 1 })) {
        .chosen => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(PricingRefusal.row_unclassified, r),
    }

    var only_retain = Admissible{ .set = .{}, .why = @splat(null) };
    only_retain.set.insert(.retain);
    switch (cheapest(&only_retain, .{ .row = .dependence_bound })) {
        .chosen => return error.TestUnexpectedResult,
        .refused => |r| try testing.expectEqual(PricingRefusal.no_alternative, r),
    }
}

test "observer_demand: §47 — the row decides, and it decides differently" {
    var a = Admissible{ .set = .{}, .why = @splat(null) };
    a.set.insert(.retain);
    a.set.insert(.recompute);

    // 1 KiB retained at 1 instruction per byte against a 600-instruction
    // recompute. On a dependence-bound row recompute wins; make the row
    // throughput-bound and the SAME numbers flip the answer, because
    // recomputation displaces real work there.
    const m = CostModel{
        .row = .dependence_bound,
        .recompute_insns = 600,
        .retain_bytes = 1024,
        .insns_per_retained_byte = 1,
    };
    switch (cheapest(&a, m)) {
        .refused => return error.TestUnexpectedResult,
        .chosen => |p| try testing.expectEqual(Policy.recompute, p.policy),
    }

    var m2 = m;
    m2.row = .throughput_bound;
    m2.retain_bytes = 1000;
    // 600 * 2 = 1200 > 1000, so retention wins.
    switch (cheapest(&a, m2)) {
        .refused => return error.TestUnexpectedResult,
        .chosen => |p| try testing.expectEqual(Policy.retain, p.policy),
    }
}

test "observer_demand: an unknown observer name is a null, never a default" {
    try testing.expectEqual(@as(?Observer, .debugger), parseObserver("debugger"));
    try testing.expectEqual(@as(?Observer, .mcp), parseObserver("mcp"));
    try testing.expectEqual(@as(?Observer, null), parseObserver("Debugger"));
    try testing.expectEqual(@as(?Observer, null), parseObserver("gdb"));
    try testing.expectEqual(@as(?Observer, null), parseObserver(""));
}
