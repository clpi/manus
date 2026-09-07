//! OBSERVATION — the classification every realization must preserve, per place.
//!
//! # Why this file exists (GAP-170, law §103/§104/§109, HPLS §9–§11, §91)
//!
//! `gaps/GAP-170.md`'s floor said **IMPLEMENTATION-BLOCKED at S0: no graph-level
//! observation facts exist**, and that stopped being true when `src/place.zig`
//! landed. Place is the entity an observation fact hangs on — a NAMED LOCATION
//! with an ACCESS HISTORY at PROGRAM POINTS — and `src/eqspace.zig` is the
//! consumer that deletes realization families from facts before any cost is
//! consulted. This module is the missing middle: it decides, per place and per
//! behaviour class, **whether any demanded observer can distinguish two
//! executions that differ only in that behaviour**, and it hands `eqspace` a
//! gate that no heuristic can open.
//!
//! `docs/observation.md` (idol-native) supplies the enumeration this module
//! presumes closed: E1–E12, every way an observation enters an Idol program,
//! derived from the compiler's own `call_extern` surface and corroborated
//! against the imported-symbol union of 84 compiled corpus artifacts. Nothing
//! here re-derives it.
//!
//! # WHAT AN OBSERVATION IS, and the one-line test used everywhere below
//!
//! > A distinction is OBSERVED iff there exists a demanded observer, in HPLS §9's
//! > list, that can distinguish two executions differing only in it.
//!
//! Three consequences the code is shaped by:
//!
//! **Observability is a WORLD FACT, not a global constant.** A security world
//! makes timing, cache access and addresses observable and an ordinary world
//! does not, so `classify` takes a `World` and there is no table of answers.
//! `World.observers()` is the only place the observer roster is computed.
//!
//! **Semantic time is not physical time.** `A` happens-before `B` requires no
//! wall-clock duration. Execution duration and scheduling are NOT observable
//! unless the program observes a clock or a deadline — and **reading a clock is
//! an effect**, so `WorldFact.clock_read` is produced by the walk finding the
//! read, never assumed.
//!
//! **Obligation is the co-equal other side** (law §109). A positive obligation
//! ADDS observations (a deadline makes duration observable); a proven negative
//! obligation DELETES WHOLE MECHANISMS (`no_allocation` deletes the allocator,
//! `no_network` deletes every remote family). Negative obligations are the
//! strongest optimization enablers in this file and `mechanismsDeleted` is
//! where that is cashed.
//!
//! # THE PROOF OBLIGATION, stated before any classification is issued
//!
//! `src/demand.zig` states five obligations and discharges each before it
//! transforms anything. The same discipline, for the opposite direction: a
//! class may be classified **not observed** — the only classification that
//! opens a realization freedom — only if ALL FIVE hold. Any one unproven yields
//! `.unknown`, and **`.unknown` is never a synonym for `no`** (`place.Tri`'s
//! rule, and the reason both are three-valued).
//!
//!   N1  ENUMERATED.   The class is one of the sixteen below, and the ways an
//!                     observation can enter the program are the closed set
//!                     E1–E12 of `docs/observation.md` §1. A class not in the
//!                     enumeration is not classifiable and reads `.unknown`.
//!
//!   N2  COMPLETE.     The evidence walk admitted every shape in the region.
//!                     ONE refused shape raises the WHOLE region to `.unknown`,
//!                     not one statement — `place.zig`'s `markAllUnknown` rule,
//!                     because a shape the walk cannot see through can capture
//!                     an address or fix an order invisibly.
//!
//!   N3  WORLD-CLOSED. The observer set was computed from the world's facts,
//!                     not assumed. Any world fact that adds an observer —
//!                     security adversary, debugger, profiler, reflection,
//!                     foreign boundary, genuine sharing, clock, deadline —
//!                     RE-OPENS the classes that observer can distinguish.
//!
//!   N4  UNOBLIGED.    No positive obligation in force makes the class
//!                     observable (`deadline` -> schedule, `ordering` ->
//!                     order and effect order, `authority_boundary` -> effect
//!                     authority), and no negative obligation constrains its
//!                     realization (`no_secret_dependent_timing` -> schedule
//!                     AND layout become observable: constant-time/oblivious).
//!
//!   N5  SINGLE-TRACE SUFFICES. Every check in this module is a SINGLE-TRACE
//!                     check. Determinism, noninterference, serializability and
//!                     linearizability are HYPERPROPERTIES over SETS of
//!                     executions, so in a world demanding one of them a
//!                     single-trace oracle is an UNSOUND acceptance criterion
//!                     and this module authorizes NOTHING. `permits` returns
//!                     `.blocked_hyperproperty` there — it does not quietly
//!                     answer as if the demand were absent.
//!
//! # WHAT THIS MODULE DOES NOT DO
//!
//! It decides no realization (§24: no candidate generator is semantic
//! authority). It produces facts with provenance; `eqspace.zig` produces
//! candidates; `admit()` below is the composition, and it takes FACTS and a
//! REPORT and **never a cost** — the same signature-level enforcement of §84
//! that `eqspace.contract` has.
//!
//! It also does not prove aliasing, effect purity, or trip counts. Those are
//! `place.zig`'s, the effect card's and `demand.zig`'s, and where this module
//! needs one it reads it and refuses when it is `unknown`.

const std = @import("std");
const ast = @import("ast.zig");
const place = @import("place.zig");
const eqspace = @import("eqspace.zig");

/// Three-valued, and the third value is the point. Shared with `place.zig`
/// rather than redeclared: two spellings of `unknown` is how one of them comes
/// to read as `no`.
pub const Tri = place.Tri;

// ===========================================================================
// §9 — the observers
// ===========================================================================

/// HPLS §9's list, in full. Every classification names WHICH observer could
/// distinguish the executions; "observable" with no observer named is the
/// hand-wave this enum exists to prevent.
pub const Observer = enum {
    program,
    foreign,
    reflection,
    debugger,
    profiler,
    mcp,
    concurrency,
    failure_recovery,
    deployment,

    pub const count = @typeInfo(Observer).@"enum".field_names.len;
};

pub const ObserverSet = std.EnumSet(Observer);

// ===========================================================================
// The world — observability is a function of THIS, not a constant
// ===========================================================================

/// Facts about the world a program is realized into. Each one either ADDS an
/// observer or makes a specific distinction reach an existing one.
///
/// None of these is a compiler flag with a default of "on". `open_world` is the
/// `--emit dylib/obj` case `demand.zig`'s W1 already had to get right, and it
/// defaults to the conservative direction there for the same reason.
pub const WorldFact = enum {
    /// A security world: an adversary observes timing, cache access and
    /// addresses. Demands constant-time / oblivious realization.
    security_adversary,
    /// The program reads a clock. THIS IS AN EFFECT, and it is produced by the
    /// walk finding the read — never assumed, never a default.
    clock_read,
    /// A deadline obligation is in force, so duration is observable.
    deadline,
    /// An irreversible boundary is inside the region: foreign ABI, file format,
    /// network protocol, shared memory, observable pointer, volatile/device.
    /// law §105 BOUNDARY-ONE: representation is free EXCEPT here, and the
    /// extent of "here" is exactly the foreign application.
    foreign_boundary,
    /// A debugger observer is demanded (not merely available — HPLS §11:
    /// debugging must not force continuous physical materialization).
    debugger_demanded,
    profiler_demanded,
    reflection_demanded,
    mcp_demanded,
    /// A genuine sharing/atomicity point exists. Not "the program has threads".
    genuine_sharing,
    /// Nothing outside the image can name a module binding. FALSE by default,
    /// like `demand.Options.world_closed`, because getting it backwards deletes
    /// a library's state.
    closed_world,
    /// A descriptor or demand permits an error bound (GAP-169 precision class).
    precision_bounded,

    // --- the hyperproperty demands. Over SETS of executions, not one. ---
    determinism_demanded,
    noninterference_demanded,
    serializability_demanded,
    linearizability_demanded,

    pub const count = @typeInfo(WorldFact).@"enum".field_names.len;
};

pub const WorldFactSet = std.EnumSet(WorldFact);

pub const World = struct {
    facts: WorldFactSet = .{},

    pub fn of(list: []const WorldFact) World {
        var s: WorldFactSet = .{};
        for (list) |f| s.insert(f);
        return .{ .facts = s };
    }

    pub fn has(self: World, f: WorldFact) bool {
        return self.facts.contains(f);
    }

    pub fn with(self: World, f: WorldFact) World {
        var w = self;
        w.facts.insert(f);
        return w;
    }

    /// THE observer roster, computed rather than tabulated. This is N3: every
    /// classification below consults this function and no other source.
    ///
    /// `program` and `deployment` are always demanded — a program's answer and
    /// its exit status are observed by construction (E1). Everything else is
    /// earned by a world fact.
    pub fn observers(self: World) ObserverSet {
        var s: ObserverSet = .{};
        s.insert(.program);
        s.insert(.deployment);
        if (self.has(.foreign_boundary)) s.insert(.foreign);
        if (!self.has(.closed_world)) s.insert(.foreign);
        if (self.has(.debugger_demanded)) s.insert(.debugger);
        if (self.has(.profiler_demanded)) s.insert(.profiler);
        if (self.has(.reflection_demanded)) s.insert(.reflection);
        if (self.has(.mcp_demanded)) s.insert(.mcp);
        if (self.has(.genuine_sharing)) s.insert(.concurrency);
        // A security adversary is not a new name in §9's list; it is the
        // PROFILER and FOREIGN observers made hostile — it reads duration and
        // it reads addresses. Saying so here keeps §9's roster closed.
        if (self.has(.security_adversary)) {
            s.insert(.profiler);
            s.insert(.foreign);
        }
        // Duration reaches the program itself once the program can read it.
        if (self.has(.clock_read) or self.has(.deadline)) s.insert(.profiler);
        // A trap that escapes is seen by whoever recovers from it. Always
        // demanded: `docs/observation.md` E8 measures that pre-trap bytes are
        // observed, and that a subset which assumed otherwise LOST OUTPUT.
        s.insert(.failure_recovery);
        return s;
    }

    /// N5. True when the demanded equivalence is a property of SETS of
    /// executions, which a single-trace oracle cannot establish.
    pub fn demandsHyperproperty(self: World) bool {
        return self.has(.determinism_demanded) or
            self.has(.noninterference_demanded) or
            self.has(.serializability_demanded) or
            self.has(.linearizability_demanded);
    }
};

/// The world an ordinary native executable is built into: closed at module
/// scope, no adversary, no debugger demand, no sharing. Everything else in this
/// file is a departure from it, and each departure must be a stated FACT.
pub const ordinary_executable = World{ .facts = blk: {
    var s: WorldFactSet = .{};
    s.insert(.closed_world);
    break :blk s;
} };

// ===========================================================================
// The behaviour classes — GAP-170's two lists, verbatim and closed
// ===========================================================================

pub const Presumption = enum { non_observable, observable };

/// Sixteen classes: nine presumptively non-observable, seven presumptively
/// observable. The enum is CLOSED, which is what makes "for each behaviour
/// class" a checkable statement rather than an aspiration.
pub const Class = enum {
    // ---- presumptively NON-observable (realization choices) ----
    /// Allocation identity, address, and existence of a place.
    allocation_identity,
    /// Table/record/array physical layout (AoS/SoA/split/scalarized/frozen).
    physical_layout,
    /// Iteration order over UNORDERED collections.
    iteration_order,
    /// Exact instruction schedule and micro-architectural timing.
    instruction_schedule,
    /// Intermediate strings and temporaries in a fused pipeline.
    intermediate_temporaries,
    /// Physical representation, width, and encoding of a value.
    representation_width,
    /// Device (CPU/GPU/NPU/core class) and storage tier.
    device_and_tier,
    /// Thread placement, memory tier, and page size.
    thread_placement,
    /// Whether a pure result is recomputed, memoized, or precomputed.
    recompute_vs_memoize,

    // ---- presumptively OBSERVABLE (must be preserved) ----
    /// Values and value relations demanded by the program.
    demanded_values,
    /// Ordering the program's semantics actually FIX (declared-ordered maps).
    fixed_ordering,
    /// Observable effects, their authority, and their externally-visible order.
    effect_order,
    /// Error/trap semantics the program can catch or that escape a boundary.
    trap_semantics,
    /// Floating-point results, except under a precision demand.
    float_result,
    /// Foreign-ABI-visible representation at a REAL boundary.
    foreign_representation,
    /// Concurrency observations at genuine sharing/atomicity points.
    concurrency_observation,

    pub const count = @typeInfo(Class).@"enum".field_names.len;

    pub fn presumption(self: Class) Presumption {
        return switch (self) {
            .allocation_identity,
            .physical_layout,
            .iteration_order,
            .instruction_schedule,
            .intermediate_temporaries,
            .representation_width,
            .device_and_tier,
            .thread_placement,
            .recompute_vs_memoize,
            => .non_observable,
            .demanded_values,
            .fixed_ordering,
            .effect_order,
            .trap_semantics,
            .float_result,
            .foreign_representation,
            .concurrency_observation,
            => .observable,
        };
    }

    pub fn name(self: Class) []const u8 {
        return @tagName(self);
    }
};

pub const ClassSet = std.EnumSet(Class);

/// N5 made mechanical. EVERY class in this module is decided by a single-trace
/// check, and saying so in code is what stops a later reader assuming
/// otherwise. The function exists so that adding a genuinely hyperproperty-
/// capable check is a CHANGE HERE, visible in a diff, rather than a silent
/// widening.
pub const CheckKind = enum { single_trace, hyperproperty };

pub fn checkKindOf(c: Class) CheckKind {
    _ = c;
    return .single_trace;
}

// ===========================================================================
// The classification, and its provenance
// ===========================================================================

/// Why. Structured rather than prose: §100 requires "why was this candidate
/// rejected" to be answerable, and a string cannot be counted or tested.
pub const Reason = enum {
    // --- reasons a class reads OBSERVED or UNKNOWN ---
    /// N1/default: presumptively observable and no proof was offered.
    presumed_observable,
    /// N2: the walk refused a shape, so the whole region is unknown.
    evidence_incomplete,
    /// The program compares or captures the place's identity.
    identity_captured,
    /// The place escapes to somewhere the walk cannot see.
    escape_unproven,
    /// An enumeration of the place reaches an effect, so its order is visible.
    order_reaches_effect,
    /// N3: a security world observes timing, cache and addresses.
    security_world,
    /// N3: a clock read or a deadline makes duration observable.
    duration_observed,
    /// N3: an irreversible boundary is inside the extent (law §105).
    boundary_in_extent,
    /// N3: a debugger/reflection/MCP observer is demanded for this subject.
    inspection_demanded,
    /// N3: a genuine sharing point.
    sharing_point,
    /// N4: a positive obligation makes this class observable.
    obligation_positive,
    /// N4: a negative obligation constrains the realization of this class.
    obligation_negative,
    /// The value is demanded and no coarser quotient was proven.
    value_demanded,
    /// The trap can be caught or can escape the region.
    trap_escapes,

    // --- reasons a class reads NOT OBSERVED ---
    /// N1–N5 all discharged and no observer in the roster can distinguish.
    no_observer_can_distinguish,
    /// The demanded quotient is coarser than the distinction (HPLS §12).
    demand_quotient_coarser,
    /// A precision/error-bound demand permits approximation (GAP-169).
    precision_demand_permits,
    /// Physical nonexistence is a first-class realization state and nothing
    /// depends on the entity existing (law §104 `none` representation).
    existence_undemanded,
};

pub const Producer = enum {
    /// `src/place.zig` — the §18 fact bundle for this place.
    place_facts,
    /// The world fact set.
    world,
    /// This module's AST evidence walk.
    observation_walk,
    /// The obligation set (law §109).
    obligation,
    /// No producer: the conservative default fired.
    default_conservative,
};

pub const Authority = enum {
    /// A semantic law decides it.
    law,
    /// A proof over the program text decides it.
    proof,
    /// Nothing decided it; the default did.
    default,
};

pub const Subject = union(enum) {
    /// A place, by `place.Place.id`.
    place: u32,
    /// An application, by the pre-order program point of its statement.
    application: u32,
    /// The whole program (E1's exit status, E9's divergence).
    program,
};

pub const Provenance = struct {
    producer: Producer,
    authority: Authority,
    subject: Subject,
};

/// One classification. `observed` is three-valued and `.unknown` BLOCKS, which
/// is the whole soundness argument in one method.
pub const Fact = struct {
    class: Class,
    observed: Tri,
    /// Which observers could distinguish. Empty exactly when `observed == .no`.
    by: ObserverSet,
    reason: Reason,
    prov: Provenance,

    /// The only question a realization gate may ask. `.unknown` answers TRUE —
    /// an unproven non-observation is not a non-observation.
    pub fn blocks(self: Fact) bool {
        return self.observed != .no;
    }
};

/// Sixteen facts, one subject, one world. Producible PER APPLICATION/PLACE,
/// which is deletion condition 1's operative word.
pub const Report = struct {
    subject: Subject,
    world: World,
    facts: [Class.count]Fact,
    /// N2, carried on the report so a consumer can see it without re-deriving.
    complete: bool,

    pub fn get(self: *const Report, c: Class) Fact {
        return self.facts[@intFromEnum(c)];
    }

    pub fn observedCount(self: *const Report) usize {
        var n: usize = 0;
        for (self.facts) |f| {
            if (f.blocks()) n += 1;
        }
        return n;
    }

    pub fn freeCount(self: *const Report) usize {
        return Class.count - self.observedCount();
    }
};

// ===========================================================================
// Obligation — law §109, the co-equal other side
// ===========================================================================

pub const Positive = enum {
    respond,
    commit_durable,
    deadline,
    ordering,
    release_resource,
    availability_under_fault,
    authority_boundary,
};

pub const Negative = enum {
    no_network,
    no_allocation,
    no_secret_dependent_timing,
    no_write_after_cancel,
    no_duplicate_external_effect,
    no_persistent_state,
    no_data_leaving_region,
};

pub const PositiveSet = std.EnumSet(Positive);
pub const NegativeSet = std.EnumSet(Negative);

/// Whole mechanisms a proven `cannot` deletes. GAP-170: *negative obligations
/// are the strongest optimization enablers — a proven `cannot` deletes whole
/// mechanisms.* This is that sentence as a function.
pub const Mechanism = enum {
    /// The allocator, and every heap realization family with it (§26).
    heap_allocator,
    /// Sockets, serialization, retry, and every remote family (§26).
    network_stack,
    /// Write-ahead log, fsync, recovery replay.
    durable_log,
    /// The idempotence key store that de-duplicates external effects.
    dedup_ledger,
    /// The barrier that makes a cancel visible before the next write.
    cancel_barrier,
    /// The dynamic check that no reference leaves a region.
    region_escape_check,
    /// Persistent state machinery: snapshots, migration, versioning.
    persistence_layer,

    pub const count = @typeInfo(Mechanism).@"enum".field_names.len;
};

pub const MechanismSet = std.EnumSet(Mechanism);

/// PROVEN negatives only. A negative obligation that is merely *expected* is
/// not in the set, and nothing is deleted for it.
pub fn mechanismsDeleted(neg: NegativeSet) MechanismSet {
    var m: MechanismSet = .{};
    if (neg.contains(.no_allocation)) m.insert(.heap_allocator);
    if (neg.contains(.no_network)) m.insert(.network_stack);
    if (neg.contains(.no_persistent_state)) {
        m.insert(.durable_log);
        m.insert(.persistence_layer);
    }
    if (neg.contains(.no_duplicate_external_effect)) {
        // The obligation is discharged BY CONSTRUCTION when the effect happens
        // once, and then the ledger that would have enforced it is dead weight.
        m.insert(.dedup_ledger);
    }
    if (neg.contains(.no_write_after_cancel)) m.insert(.cancel_barrier);
    if (neg.contains(.no_data_leaving_region)) m.insert(.region_escape_check);
    return m;
}

/// N4, first half. A positive obligation ADDS observations: it is a promise
/// about behaviour, and every promise is something a realization must preserve.
pub fn classesOpenedByPositive(pos: PositiveSet) ClassSet {
    var s: ClassSet = .{};
    if (pos.contains(.deadline)) s.insert(.instruction_schedule);
    if (pos.contains(.respond)) s.insert(.effect_order);
    if (pos.contains(.ordering)) {
        s.insert(.iteration_order);
        s.insert(.fixed_ordering);
        s.insert(.effect_order);
    }
    if (pos.contains(.commit_durable)) s.insert(.effect_order);
    if (pos.contains(.release_resource)) s.insert(.allocation_identity);
    if (pos.contains(.authority_boundary)) s.insert(.effect_order);
    if (pos.contains(.availability_under_fault)) s.insert(.trap_semantics);
    return s;
}

/// N4, second half, and the asymmetry is the interesting part: a negative
/// obligation usually DELETES mechanism, but two of them CONSTRAIN realization
/// instead — a promise not to leak timing is a promise about the schedule and
/// the memory access pattern, i.e. it makes both observable.
pub fn classesOpenedByNegative(neg: NegativeSet) ClassSet {
    var s: ClassSet = .{};
    if (neg.contains(.no_secret_dependent_timing)) {
        s.insert(.instruction_schedule);
        s.insert(.physical_layout);
    }
    if (neg.contains(.no_data_leaving_region)) s.insert(.allocation_identity);
    return s;
}

pub const Obligations = struct {
    positive: PositiveSet = .{},
    negative: NegativeSet = .{},

    pub fn of(pos: []const Positive, neg: []const Negative) Obligations {
        var o = Obligations{};
        for (pos) |p| o.positive.insert(p);
        for (neg) |n| o.negative.insert(n);
        return o;
    }

    pub fn opened(self: Obligations) ClassSet {
        var s = classesOpenedByPositive(self.positive);
        s.setUnion(classesOpenedByNegative(self.negative));
        return s;
    }
};

// ===========================================================================
// Evidence — what the walk proved about ONE place
// ===========================================================================

/// The demanded quotient of a value (HPLS §12: an observation observes
/// `value / ~`, not `value`). `.full` is the conservative reading.
pub const Quotient = enum {
    /// Every bit of the value is demanded.
    full,
    /// Only `value mod 2^k` reaches an observer. MEASURED for E1: a `main`
    /// returning 300 exits 44, so the exit status observes `mod 2^8`.
    modulus,
    /// Only "is there one" reaches an observer.
    existence,
    /// Nothing reaches any observer.
    nothing,
};

/// Program facts about one place. Every field defaults to the conservative
/// reading, so a field the walk forgets to set cannot open a freedom.
pub const Evidence = struct {
    /// N2. False until the walk finishes a region it admitted entirely.
    complete: bool = false,
    /// The place's identity is compared, hashed, printed, or otherwise made
    /// distinguishable from an equal-valued copy.
    identity_captured: bool = false,
    /// An enumeration of the place reaches an effect: its order is visible.
    /// Three-valued for N2's reason: a loop containing an applied relation the
    /// walk cannot classify has not been shown to reach an effect and has not
    /// been shown not to, and the two answers open different freedoms.
    order_reaches_effect: Tri = .no,
    /// The COLLECTION'S OWN SEMANTICS fix an enumeration order — a declared
    /// ordered map, not a sorted literal. `place.Facts.ordered` is NOT this: it
    /// says the values happen to ascend, which is a legality fact for binary
    /// search and says nothing about what any observer can see. Conflating the
    /// two was a real defect in this file's first draft and it made a sorted
    /// literal block the order freedom for no semantic reason.
    order_declared: Tri = .unknown,
    /// The place is read AT AN INDEX, so the index-to-value map is observed and
    /// no permutation of storage is lawful. On this surface every collection
    /// read is positional, so this is `.yes` for real programs and `.no` only
    /// for a place used purely as a SET — which is the identity `eqspace`
    /// models and which this surface cannot yet spell.
    positional_read: Tri = .unknown,
    /// The place is handed to something the walk cannot see through.
    escapes: Tri = .unknown,
    /// The place crosses an irreversible boundary (law §105).
    crosses_boundary: Tri = .unknown,
    /// The place's element values reach an observer at all.
    quotient: Quotient = .full,
    /// An access can trap and the trap is not proven to stay inside.
    may_trap: Tri = .unknown,
    /// A floating-point value is produced here.
    float_produced: bool = false,
    /// An observable effect occurs in this place's region. `.unknown` is the
    /// conservative reading and it BLOCKS memoization, because recomputing a
    /// region that may have an effect repeats the effect and memoizing one
    /// skips it — both are observable in a way no cost model may excuse.
    has_effect: Tri = .unknown,
    /// The place is read in a context where a temporary must materialize
    /// (handed to a foreign call, stored, or observed as a whole).
    temporary_materialized: bool = false,
    /// `place.zig`'s §18 bundle, verbatim.
    facts: place.Facts = .{},
};

// ===========================================================================
// The classification function — LEGALITY ONLY. No cost parameter exists.
// ===========================================================================

fn observedBy(set: []const Observer) ObserverSet {
    var s: ObserverSet = .{};
    for (set) |o| s.insert(o);
    return s;
}

const no_observer = ObserverSet{};

fn yes(c: Class, obs: []const Observer, r: Reason, p: Producer, a: Authority, s: Subject) Fact {
    return .{
        .class = c,
        .observed = .yes,
        .by = observedBy(obs),
        .reason = r,
        .prov = .{ .producer = p, .authority = a, .subject = s },
    };
}

fn unknown(c: Class, r: Reason, p: Producer, s: Subject) Fact {
    // An UNKNOWN names no observer, because naming one would be a claim. It
    // blocks all the same — that is `Fact.blocks`.
    return .{
        .class = c,
        .observed = .unknown,
        .by = no_observer,
        .reason = r,
        .prov = .{ .producer = p, .authority = .default, .subject = s },
    };
}

fn free(c: Class, r: Reason, p: Producer, s: Subject) Fact {
    return .{
        .class = c,
        .observed = .no,
        .by = no_observer,
        .reason = r,
        .prov = .{ .producer = p, .authority = .proof, .subject = s },
    };
}

/// Classify ONE behaviour class for ONE subject. **This function never sees a
/// cost**, exactly as `eqspace.contract` never sees one: the signature is the
/// enforcement, not a comment.
///
/// The order of the guards IS the obligation order N2, N3, N4, then the class's
/// own evidence — and it matters, because an incomplete walk must not be able
/// to reach a world-specific "not observed" answer.
pub fn classify(c: Class, w: World, ev: Evidence, ob: Obligations, s: Subject) Fact {
    // N2 — one refused shape raises the whole region.
    if (!ev.complete) return unknown(c, .evidence_incomplete, .observation_walk, s);

    // N4 — an obligation in force re-opens the class before anything else can
    // close it.
    if (ob.opened().contains(c)) {
        const from_pos = classesOpenedByPositive(ob.positive).contains(c);
        return yes(
            c,
            &.{ .program, .deployment },
            if (from_pos) .obligation_positive else .obligation_negative,
            .obligation,
            .law,
            s,
        );
    }

    return switch (c) {
        // ---------------- presumptively non-observable ----------------
        .allocation_identity => blk: {
            // The one the gap names first, and the one a positive control has
            // to be able to hit. THREE independent ways it becomes observable.
            if (ev.identity_captured)
                break :blk yes(c, &.{.program}, .identity_captured, .observation_walk, .proof, s);
            if (ev.escapes != .no)
                break :blk yes(c, &.{ .program, .foreign }, .escape_unproven, .place_facts, .proof, s);
            // §18's ALIAS fact, consumed. Two names that may denote the same
            // place make identity observable by comparison even where nothing
            // in the walk spelled a `==`, and `unknown` is not `no`.
            if (ev.facts.alias != .no)
                break :blk unknown(c, .escape_unproven, .place_facts, s);
            if (w.has(.security_adversary))
                break :blk yes(c, &.{ .foreign, .profiler }, .security_world, .world, .law, s);
            if (w.has(.debugger_demanded) or w.has(.reflection_demanded))
                break :blk yes(c, &.{ .debugger, .reflection }, .inspection_demanded, .world, .law, s);
            if (ev.crosses_boundary == .yes or w.has(.foreign_boundary))
                break :blk yes(c, &.{.foreign}, .boundary_in_extent, .world, .law, s);
            if (ev.crosses_boundary == .unknown)
                break :blk unknown(c, .boundary_in_extent, .observation_walk, s);
            break :blk free(c, .existence_undemanded, .observation_walk, s);
        },
        .physical_layout => blk: {
            if (ev.crosses_boundary == .yes or w.has(.foreign_boundary))
                break :blk yes(c, &.{.foreign}, .boundary_in_extent, .world, .law, s);
            if (ev.crosses_boundary == .unknown)
                break :blk unknown(c, .boundary_in_extent, .observation_walk, s);
            if (ev.escapes != .no)
                break :blk yes(c, &.{ .program, .foreign }, .escape_unproven, .place_facts, .proof, s);
            // An unproven alias means another name may see the bytes, so no
            // re-layout is provably invisible.
            if (ev.facts.alias != .no)
                break :blk unknown(c, .escape_unproven, .place_facts, s);
            if (w.has(.security_adversary))
                break :blk yes(c, &.{ .foreign, .profiler }, .security_world, .world, .law, s);
            if (w.has(.debugger_demanded))
                break :blk yes(c, &.{.debugger}, .inspection_demanded, .world, .law, s);
            break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
        },
        .iteration_order => blk: {
            // DECLARED order is `fixed_ordering`, a different class. This one is
            // the order in which an UNORDERED collection is walked, and it is
            // visible exactly when the walk reaches an effect or when the place
            // goes somewhere this analysis cannot follow.
            if (ev.order_reaches_effect == .yes)
                break :blk yes(c, &.{ .program, .foreign }, .order_reaches_effect, .observation_walk, .proof, s);
            if (ev.order_reaches_effect == .unknown)
                break :blk unknown(c, .order_reaches_effect, .observation_walk, s);
            if (ev.escapes == .yes)
                break :blk yes(c, &.{ .program, .foreign }, .escape_unproven, .place_facts, .proof, s);
            if (ev.escapes == .unknown)
                break :blk unknown(c, .escape_unproven, .place_facts, s);
            break :blk free(c, .no_observer_can_distinguish, .place_facts, s);
        },
        .instruction_schedule => blk: {
            // SEMANTIC TIME IS NOT PHYSICAL TIME. `A` happens-before `B` needs
            // no duration, so nothing here is observable unless the program can
            // READ a clock or a deadline is promised — and reading a clock is
            // an effect, produced by the walk.
            if (w.has(.security_adversary))
                break :blk yes(c, &.{.profiler}, .security_world, .world, .law, s);
            if (w.has(.clock_read) or w.has(.deadline))
                break :blk yes(c, &.{ .profiler, .program }, .duration_observed, .world, .law, s);
            if (w.has(.genuine_sharing))
                break :blk yes(c, &.{.concurrency}, .sharing_point, .world, .law, s);
            break :blk free(c, .no_observer_can_distinguish, .world, s);
        },
        .intermediate_temporaries => blk: {
            if (ev.temporary_materialized)
                break :blk yes(c, &.{ .program, .foreign }, .value_demanded, .observation_walk, .proof, s);
            if (w.has(.debugger_demanded))
                // HPLS §11 permits value-absent + recomputation recipe, so this
                // is a REFUSAL pending that machinery, not a law.
                break :blk unknown(c, .inspection_demanded, .world, s);
            if (ev.escapes != .no)
                break :blk yes(c, &.{.program}, .escape_unproven, .place_facts, .proof, s);
            break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
        },
        .representation_width => blk: {
            if (ev.crosses_boundary == .yes or w.has(.foreign_boundary))
                break :blk yes(c, &.{.foreign}, .boundary_in_extent, .world, .law, s);
            if (ev.crosses_boundary == .unknown)
                break :blk unknown(c, .boundary_in_extent, .observation_walk, s);
            if (ev.quotient == .full and ev.escapes != .no)
                break :blk yes(c, &.{.program}, .value_demanded, .place_facts, .proof, s);
            // MEASURED (docs/observation.md §3.3): E1 observes `n mod 2^8`, so
            // the top 56 bits of every program's answer are a width freedom.
            if (ev.quotient == .modulus or ev.quotient == .existence or ev.quotient == .nothing)
                break :blk free(c, .demand_quotient_coarser, .observation_walk, s);
            break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
        },
        .device_and_tier => blk: {
            if (w.has(.security_adversary))
                break :blk yes(c, &.{.foreign}, .security_world, .world, .law, s);
            if (ev.crosses_boundary == .yes)
                break :blk yes(c, &.{.foreign}, .boundary_in_extent, .observation_walk, .law, s);
            if (ev.crosses_boundary == .unknown)
                break :blk unknown(c, .boundary_in_extent, .observation_walk, s);
            break :blk free(c, .no_observer_can_distinguish, .world, s);
        },
        .thread_placement => blk: {
            if (w.has(.security_adversary))
                break :blk yes(c, &.{ .foreign, .profiler }, .security_world, .world, .law, s);
            if (w.has(.genuine_sharing))
                break :blk yes(c, &.{.concurrency}, .sharing_point, .world, .law, s);
            break :blk free(c, .no_observer_can_distinguish, .world, s);
        },
        .recompute_vs_memoize => blk: {
            // A pure result may be recomputed, memoized or precomputed — but
            // only if recomputing cannot trap, cannot diverge and cannot repeat
            // an effect. `may_trap = unknown` is not "probably fine", and
            // `has_effect = unknown` is not "probably pure": `demand.zig`'s O3
            // measured the corpus at 864 `none` / 414 `unknown` effect cards
            // and says treating `unknown` as fine is how a lane ships a wrong
            // answer.
            if (ev.has_effect == .yes)
                break :blk yes(c, &.{ .program, .foreign }, .presumed_observable, .observation_walk, .law, s);
            if (ev.has_effect == .unknown)
                break :blk unknown(c, .presumed_observable, .observation_walk, s);
            if (ev.may_trap != .no)
                break :blk unknown(c, .trap_escapes, .place_facts, s);
            if (w.has(.clock_read) or w.has(.deadline))
                break :blk yes(c, &.{.profiler}, .duration_observed, .world, .law, s);
            if (ev.escapes != .no)
                break :blk yes(c, &.{.program}, .escape_unproven, .place_facts, .proof, s);
            break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
        },

        // ---------------- presumptively observable ----------------
        .demanded_values => blk: {
            if (ev.quotient == .nothing)
                break :blk free(c, .demand_quotient_coarser, .observation_walk, s);
            break :blk yes(c, &.{.program}, .value_demanded, .observation_walk, .law, s);
        },
        .fixed_ordering => blk: {
            // Ordering the SEMANTICS fix, and there are exactly two ways they
            // do: the type declares one, or the program reads at an index and
            // so pins index-to-value. A permutation of storage is unlawful
            // under either.
            if (ev.order_declared == .yes or ev.positional_read == .yes)
                break :blk yes(c, &.{.program}, .value_demanded, .place_facts, .law, s);
            if (ev.order_reaches_effect == .yes)
                break :blk yes(c, &.{ .program, .foreign }, .order_reaches_effect, .observation_walk, .proof, s);
            if (ev.order_reaches_effect == .unknown or ev.order_declared == .unknown or ev.positional_read == .unknown or ev.escapes != .no)
                break :blk unknown(c, .presumed_observable, .default_conservative, s);
            break :blk free(c, .no_observer_can_distinguish, .place_facts, s);
        },
        .effect_order => blk: {
            // The externally-visible ORDER of effects is fixed by the effect
            // and world model, never by realization. A region with no effect
            // fixes nothing — which is the only route by which this class reads
            // free, and it is a proof rather than a presumption.
            if (ev.has_effect == .no)
                break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
            if (ev.has_effect == .unknown)
                break :blk unknown(c, .presumed_observable, .default_conservative, s);
            break :blk yes(c, &.{ .program, .foreign, .deployment }, .presumed_observable, .default_conservative, .law, s);
        },
        .trap_semantics => blk: {
            if (ev.may_trap == .no)
                break :blk free(c, .no_observer_can_distinguish, .place_facts, s);
            break :blk yes(c, &.{ .failure_recovery, .deployment }, .trap_escapes, .default_conservative, .law, s);
        },
        .float_result => blk: {
            if (!ev.float_produced)
                break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
            if (w.has(.precision_bounded))
                break :blk free(c, .precision_demand_permits, .world, s);
            break :blk yes(c, &.{.program}, .presumed_observable, .default_conservative, .law, s);
        },
        .foreign_representation => blk: {
            // BOUNDARY-ONE: foreign representation has FINITE EXTENT — exactly
            // the foreign application — and never infects the whole program.
            if (ev.crosses_boundary == .yes or w.has(.foreign_boundary))
                break :blk yes(c, &.{.foreign}, .boundary_in_extent, .world, .law, s);
            if (ev.crosses_boundary == .unknown)
                break :blk unknown(c, .boundary_in_extent, .observation_walk, s);
            break :blk free(c, .no_observer_can_distinguish, .observation_walk, s);
        },
        .concurrency_observation => blk: {
            if (!w.has(.genuine_sharing))
                break :blk free(c, .no_observer_can_distinguish, .world, s);
            break :blk yes(c, &.{.concurrency}, .sharing_point, .world, .law, s);
        },
    };
}

/// All sixteen, for one subject. This is deletion condition 1's deliverable:
/// an explicit classification for each behaviour class, per place, with
/// provenance on every row.
pub fn classifyAll(w: World, ev: Evidence, ob: Obligations, s: Subject) Report {
    var r = Report{ .subject = s, .world = w, .facts = undefined, .complete = ev.complete };
    for (std.enums.values(Class)) |c| {
        r.facts[@intFromEnum(c)] = classify(c, w, ev, ob, s);
    }
    return r;
}

// ===========================================================================
// Realization freedoms — deletion condition 2
// ===========================================================================

/// GAP-169's list (layout, order, device, tier, precision, memoization,
/// zero-copy) plus the three this model makes separable: existence, schedule
/// and width.
pub const Freedom = enum {
    layout,
    order,
    device,
    tier,
    precision,
    memoization,
    zero_copy,
    /// Physical nonexistence as a realization state (law §104).
    existence,
    /// Batch, defer, precompute, reorder, migrate, speculate (HPLS §63–64).
    schedule,
    /// Narrow the physical width to the demanded quotient.
    width,
    /// Thread placement, memory tier, page size.
    placement,

    pub const count = @typeInfo(Freedom).@"enum".field_names.len;

    pub fn name(self: Freedom) []const u8 {
        return @tagName(self);
    }
};

pub const FreedomSet = std.EnumSet(Freedom);

/// The classes that must ALL read `not observed` before the freedom is lawful.
/// This table is the entirety of deletion condition 2: there is no other path
/// from "we would like to" to "we may".
pub fn gatingClasses(f: Freedom) []const Class {
    return switch (f) {
        .layout => &.{ .physical_layout, .foreign_representation },
        .order => &.{ .iteration_order, .fixed_ordering },
        .device => &.{ .device_and_tier, .concurrency_observation },
        .tier => &.{.device_and_tier},
        .precision => &.{.float_result},
        // `effect_order` is NOT a gate on either of the two below, and getting
        // that wrong makes both permanently unreachable — measured, by writing
        // it wrong first. Batching writes does not reorder them, and the
        // rung-1 arrival result is exactly that: the byte sequence is observed,
        // the write-event multiplicity and the arrival schedule are not. What
        // effects DO gate is `recompute_vs_memoize`, and they gate it inside
        // the classification above where the reason can be named.
        .memoization => &.{.recompute_vs_memoize},
        .zero_copy => &.{ .allocation_identity, .intermediate_temporaries },
        // `demanded_values` is NOT a gate here either, and the distinction is
        // the gap's own: the question is whether a required observation depends
        // on the ENTITY'S PHYSICAL EXISTENCE, not on its values. A folded
        // constant still delivers every demanded value; it just has no place.
        // Existence of a place is inside `allocation_identity` by GAP-170's own
        // wording — *allocation identity, address, and existence of a place*.
        .existence => &.{.allocation_identity},
        .schedule => &.{.instruction_schedule},
        .width => &.{ .representation_width, .foreign_representation },
        .placement => &.{ .thread_placement, .concurrency_observation },
    };
}

pub const Permit = enum {
    /// Every gating class is a PROVEN non-observation.
    permitted,
    /// A gating class is observed. The realization is unlawful here.
    blocked_observed,
    /// A gating class is UNKNOWN. Not proven, therefore not permitted — the
    /// distinction from `blocked_observed` matters only for diagnostics.
    blocked_unknown,
    /// N5: the world demands a hyperproperty and every check here is
    /// single-trace, so no amount of per-trace evidence authorizes this.
    blocked_hyperproperty,
};

pub const Ruling = struct {
    freedom: Freedom,
    permit: Permit,
    /// The class that decided it. Null only when `permitted`.
    by_class: ?Class,
    reason: ?Reason,

    pub fn ok(self: Ruling) bool {
        return self.permit == .permitted;
    }
};

/// **THE GATE.** Takes a report and a freedom; returns a ruling. It takes no
/// cost, no profile, no heuristic and no override — there is no parameter
/// through which one could arrive.
pub fn permits(r: *const Report, f: Freedom) Ruling {
    // N5 first. A hyperproperty world is not a harder version of an ordinary
    // one; it is a world where this module's evidence is the WRONG KIND, and
    // answering from it at all would be the unsound step.
    if (r.world.demandsHyperproperty()) {
        var all_single = true;
        for (gatingClasses(f)) |c| {
            if (checkKindOf(c) != .single_trace) all_single = false;
        }
        if (all_single) return .{
            .freedom = f,
            .permit = .blocked_hyperproperty,
            .by_class = gatingClasses(f)[0],
            .reason = null,
        };
    }
    for (gatingClasses(f)) |c| {
        const fact = r.get(c);
        if (fact.observed == .yes) return .{
            .freedom = f,
            .permit = .blocked_observed,
            .by_class = c,
            .reason = fact.reason,
        };
        if (fact.observed == .unknown) return .{
            .freedom = f,
            .permit = .blocked_unknown,
            .by_class = c,
            .reason = fact.reason,
        };
    }
    return .{ .freedom = f, .permit = .permitted, .by_class = null, .reason = null };
}

pub fn permittedSet(r: *const Report) FreedomSet {
    var s: FreedomSet = .{};
    for (std.enums.values(Freedom)) |f| {
        if (permits(r, f).ok()) s.insert(f);
    }
    return s;
}

// ===========================================================================
// The bridge to eqspace — deletion condition 2, made concrete
// ===========================================================================

/// Which freedoms a realization family EXERCISES. A family that exercises a
/// freedom the observation model has not opened is unlawful, and this is the
/// map that says which.
///
/// Read beside `eqspace.Family`:
///   `none`           erases the place entirely -> `existence`, `zero_copy`
///   `scan`           dense vector in binding order -> exercises nothing
///   `ordered_search` requires the ascending order it already has -> nothing
///   `bitset`         a characteristic function: layout AND enumeration order
///                    both change -> `layout`, `order`
///   `hashed`         probe order is neither binding nor value order ->
///                    `layout`, `order`
pub fn familyFreedoms(f: eqspace.Family) []const Freedom {
    return switch (f) {
        .none => &.{ .existence, .zero_copy },
        .scan => &.{},
        .ordered_search => &.{},
        .bitset => &.{ .layout, .order },
        .hashed => &.{ .layout, .order },
    };
}

pub const Block = struct {
    family: eqspace.Family,
    freedom: Freedom,
    permit: Permit,
    class: ?Class,
    reason: ?Reason,
};

/// The composition. `space` is EXACTLY what `eqspace.contract` returned and is
/// never mutated — §24's "no candidate generator is semantic authority" cuts
/// both ways, and this module is not one either. `admitted` is the subset that
/// survives the observation gate, and `blocked` says why for each casualty.
pub const Admission = struct {
    space: eqspace.Space,
    admitted: std.EnumSet(eqspace.Family),
    blocked: [eqspace.Family.count]Block,
    blocked_count: usize,

    pub fn admits(self: *const Admission, f: eqspace.Family) bool {
        return self.space.has(f) and self.admitted.contains(f);
    }

    pub fn admittedCount(self: *const Admission) usize {
        var n: usize = 0;
        for (self.space.survivorSlice()) |c| {
            if (self.admitted.contains(c.family)) n += 1;
        }
        return n;
    }

    pub fn blockedSlice(self: *const Admission) []const Block {
        return self.blocked[0..self.blocked_count];
    }
};

/// **Facts in, families out. No cost parameter exists here either.** This is
/// the signature-level statement of deletion condition 2: a realization freedom
/// is reachable only through a proven non-observation fact.
pub fn admit(r: *const Report, facts: eqspace.FactSet) Admission {
    const sp = eqspace.contract(facts);
    var a = Admission{
        .space = sp,
        .admitted = .{},
        .blocked = undefined,
        .blocked_count = 0,
    };
    for (sp.survivorSlice()) |cand| {
        var ok = true;
        for (familyFreedoms(cand.family)) |fr| {
            const ruling = permits(r, fr);
            if (!ruling.ok()) {
                a.blocked[a.blocked_count] = .{
                    .family = cand.family,
                    .freedom = fr,
                    .permit = ruling.permit,
                    .class = ruling.by_class,
                    .reason = ruling.reason,
                };
                a.blocked_count += 1;
                ok = false;
                break;
            }
        }
        if (ok) a.admitted.insert(cand.family);
    }
    return a;
}

// ===========================================================================
// The evidence walk — where the classification meets real source
// ===========================================================================

/// Names whose application is an EFFECT on this surface. Derived from
/// `docs/observation.md` §1's E-table (the closed set of `call_extern` callees
/// the lowering can emit) rather than guessed, and deliberately OVER-broad: a
/// name wrongly on this list costs a freedom, a name wrongly off it costs
/// correctness.
///
/// IT IS A POSITIVE RECOGNIZER ONLY. `false` means "not recognized", never
/// "proved pure"; `markEffectUnknown` is where that difference is enforced.
fn isEffectName(n: []const u8) bool {
    const effects = [_][]const u8{
        "print",   "puts",  "printf", "write", "io",     "stdout", "stderr",
        "os",      "abort", "exit",   "error", "assert", "system", "popen",
        "require",
    };
    for (effects) |e| {
        if (std.mem.eql(u8, n, e)) return true;
    }
    return false;
}

/// Reading a clock IS AN EFFECT, and it is also the only thing that makes
/// duration observable. Both halves matter and they are the same detection.
fn isClockName(n: []const u8) bool {
    const clocks = [_][]const u8{ "clock", "time", "now", "hrtime", "deadline" };
    for (clocks) |c| {
        if (std.mem.eql(u8, n, c)) return true;
    }
    return false;
}

/// One program's observation evidence: a place census, one `Evidence` per
/// place, and the world facts the walk PRODUCED (as opposed to the ones it was
/// handed).
pub const Program = struct {
    census: place.Census,
    /// FALSE when the census was produced elsewhere and outlives this program.
    /// `law.fact.producer.one`: one census answers "which places exist", and a
    /// second one derived here would be a rival producer of that fact.
    owns_census: bool = true,
    ev: std.ArrayListUnmanaged(Evidence) = .empty,
    /// The world the caller supplied, UNION the facts the walk found — a clock
    /// read is discovered, not declared.
    world: World,
    alloc: std.mem.Allocator,
    /// Statements walked. A walk that examined zero statements has not passed.
    points: u32 = 0,

    pub fn deinit(self: *Program) void {
        self.ev.deinit(self.alloc);
        if (self.owns_census) self.census.deinit();
    }

    pub fn evidenceFor(self: *const Program, id: u32) ?Evidence {
        if (id >= self.ev.items.len) return null;
        return self.ev.items[id];
    }

    pub fn byName(self: *Program, name: []const u8) ?Evidence {
        const p = self.census.byName(name) orelse return null;
        return self.evidenceFor(p.id);
    }

    /// The per-place report. THE deliverable of deletion condition 1.
    pub fn report(self: *Program, name: []const u8, ob: Obligations) ?Report {
        const p = self.census.byName(name) orelse return null;
        const ev = self.evidenceFor(p.id) orelse return null;
        return classifyAll(self.world, ev, ob, .{ .place = p.id });
    }
};

const WalkCtx = struct {
    prog: *Program,
    /// Depth of enclosing loops. An enumeration only exists inside one.
    loop_depth: u8 = 0,
    /// Names read at the current loop nest, so that "this place is enumerated
    /// AND an effect happens in the same loop" is decidable.
    loop_reads: *std.ArrayListUnmanaged([]const u8),
    loop_effect: Tri = .no,
    /// Monotone: any observable effect ANYWHERE in the region. Separate from
    /// `loop_effect`, which is scoped to one loop nest and is restored on exit.
    any_effect: Tri = .no,
    /// Monotone: any applied relation the walk cannot prove boundary-local.
    any_boundary: Tri = .no,
};

/// `yes` dominates `unknown` dominates `no`, so a second visit can raise the
/// reading and can never lower it.
fn raise(current: Tri, found: Tri) Tri {
    if (current == .yes or found == .yes) return .yes;
    if (current == .unknown or found == .unknown) return .unknown;
    return .no;
}

/// One effect, recorded at two scopes. The loop scope decides whether an
/// ENUMERATION's order is visible; the region scope decides whether recomputing
/// is.
fn markEffect(ctx: *WalkCtx) void {
    ctx.loop_effect = .yes;
    ctx.any_effect = .yes;
}

/// AN APPLIED RELATION THE WALK CANNOT CLASSIFY, and the reason this function
/// exists rather than being left implicit.
///
/// `isEffectName` is a SPELLING LIST. A spelling list can honestly say "this
/// face is an effect"; it can never say "this face is not one", because the
/// question it answers is whether the name is on it, not whether the relation
/// observes anything. Read as a permission it was FAIL-OPEN, and measurably so
/// on the vocabulary this project's own `CLAUDE.md` teaches as canonical:
/// `stdin:read()`, `args(1)`, `env("HOME")` are none of them on the list, so a
/// program reading its input walked to `any_effect = false`, `has_effect` was
/// published `.no`, and `effect_order` read a PROVEN non-observation — issued
/// by `free(..., .observation_walk, ...)` with `authority = .proof` — for a
/// region that consumes input. `memoization` was `permitted` there, and
/// memoizing a region that reads input skips the read.
///
/// So the list keeps its one honest job and loses the other: a name ON it marks
/// `.yes`, and every applied relation NOT recognized marks `.unknown`. `.no`
/// now means "this region applied no relation at all", which is a fact the walk
/// really does establish. N2's rule, applied to the effect fact: a shape the
/// walk does not see through raises the region rather than passing it.
fn markEffectUnknown(ctx: *WalkCtx) void {
    ctx.loop_effect = raise(ctx.loop_effect, .unknown);
    ctx.any_effect = raise(ctx.any_effect, .unknown);
}

fn markBoundaryUnknown(ctx: *WalkCtx) void {
    ctx.any_boundary = raise(ctx.any_boundary, .unknown);
}

fn evOf(ctx: *WalkCtx, name: []const u8) ?*Evidence {
    const p = ctx.prog.census.byName(name) orelse return null;
    if (p.id >= ctx.prog.ev.items.len) return null;
    return &ctx.prog.ev.items[p.id];
}

/// Raise EVERY place to the pessimistic reading. N2: a shape the walk does not
/// admit is a defect in the WALK, so it refuses the whole region rather than
/// one statement.
fn refuseRegion(ctx: *WalkCtx) void {
    for (ctx.prog.ev.items) |*e| {
        e.complete = false;
        e.escapes = .unknown;
        e.may_trap = .unknown;
    }
}

/// Analyse one module for observation evidence. The place census comes from
/// `place.zig` — this module does not re-derive places, it annotates them.
pub fn analyze(alloc: std.mem.Allocator, mod: *const ast.Module, w: World) !Program {
    // The wedge's programs are one `main` relation; walk it if present,
    // otherwise the file-scope body. `place.zig` records why a pass that only
    // walks `.func_decl` inherits the file-scope hole.
    var census = blk: {
        for (mod.body.stmts) |*s| {
            if (s.* == .func_decl) break :blk try place.analyzeFunction(alloc, &s.func_decl.func);
        }
        break :blk try place.analyzeModule(alloc, mod);
    };
    errdefer census.deinit();

    var prog = Program{ .census = census, .world = w, .alloc = alloc };
    errdefer prog.ev.deinit(alloc);
    try annotate(alloc, &prog, mod);
    return prog;
}

/// The evidence walk over the census a `Program` already holds. Split out of
/// `analyze` so a caller that ALREADY OWNS a census can be annotated without a
/// second one being derived behind its back.
fn annotate(alloc: std.mem.Allocator, prog: *Program, mod: *const ast.Module) !void {
    for (prog.census.places.items) |*p| {
        // Every collection read on this surface is `s(i)` or `s[i]`, so a read
        // access IS a positional read. When a set-shaped read face exists this
        // is where it stops being unconditional, and nothing else moves.
        var any_read = false;
        for (p.accesses.items) |acc| {
            if (acc.kind == .read) any_read = true;
        }
        try prog.ev.append(alloc, .{
            .complete = true,
            .facts = p.facts,
            .escapes = p.facts.escape,
            .crosses_boundary = .no,
            .positional_read = if (any_read) .yes else .no,
            // This surface has no declared-ordered collection type: a table
            // literal fixes index-to-value and fixes no ENUMERATION order. A
            // future ordered-map type sets this `.yes` at its binding site and
            // nothing else in this file changes.
            .order_declared = if (p.facts.origin == .literal) .no else .unknown,
            // A collection access is bounds-checked and a failed check ends in
            // `brk`, so a non-constant index is trap-carrying. `demand.zig` O2
            // states the same rule and this reuses it rather than inventing a
            // second one.
            .may_trap = if (p.facts.determinacy == .exact) .no else .unknown,
        });
    }

    var reads: std.ArrayListUnmanaged([]const u8) = .empty;
    defer reads.deinit(alloc);
    var ctx = WalkCtx{ .prog = prog, .loop_reads = &reads };

    try walkBlock(&ctx, &mod.body);

    // Effect presence is a REGION fact, so it is settled after the walk rather
    // than during it: a print on the last line makes recompute-vs-memoize
    // observable for a place bound on the first.
    for (prog.ev.items) |*e| {
        if (e.complete) e.has_effect = ctx.any_effect;
    }
    for (prog.ev.items) |*e| {
        if (e.complete) e.crosses_boundary = raise(e.crosses_boundary, ctx.any_boundary);
    }

    // The walk PRODUCES world facts. A clock read is discovered here and then
    // makes `instruction_schedule` and `recompute_vs_memoize` observable — the
    // gap's "reading a clock is an effect" as a mechanism.
}

/// **THE EXISTENCE RULING, PER PLACE, OVER A BORROWED CENSUS.** Indexed by
/// `place.Place.id`, which `place.zig` assigns as the census position.
///
/// `permits(&report, .existence)` is the only question asked, because erasing a
/// place is the only freedom the caller exercises. Its gate is
/// `allocation_identity` — GAP-170's *allocation identity, address, and
/// existence of a place* — so a demanded debugger, a security adversary, a
/// foreign boundary, an unproven escape or an open world each block it.
///
/// A row this module cannot produce evidence for gets `.blocked_unknown`, never
/// `.permitted`.
pub fn existenceOverCensus(
    alloc: std.mem.Allocator,
    census: *const place.Census,
    mod: *const ast.Module,
    w: World,
    ob: Obligations,
) ![]Permit {
    var prog = Program{
        .census = census.*,
        .owns_census = false,
        .world = w,
        .alloc = alloc,
    };
    defer prog.deinit();
    try annotate(alloc, &prog, mod);

    const out = try alloc.alloc(Permit, prog.census.places.items.len);
    errdefer alloc.free(out);
    for (out, 0..) |*slot, i| {
        const ev = prog.evidenceFor(@intCast(i)) orelse {
            slot.* = .blocked_unknown;
            continue;
        };
        const r = classifyAll(prog.world, ev, ob, .{ .place = @intCast(i) });
        slot.* = permits(&r, .existence).permit;
    }
    return out;
}

fn walkBlock(ctx: *WalkCtx, b: *const ast.Block) anyerror!void {
    for (b.stmts) |*s| try walkStmt(ctx, s);
    if (b.tail_expr) |t| try walkExpr(ctx, t, .read);
}

const Position = enum { read, effect_arg, boundary_arg };

fn walkStmt(ctx: *WalkCtx, s: *const ast.Stmt) anyerror!void {
    ctx.prog.points += 1;
    switch (s.*) {
        .local_decl => |d| for (d.inits) |e| try walkExpr(ctx, e, .read),
        .global_decl => |d| {
            for (d.inits) |e| try walkExpr(ctx, e, .read);
            // A module-scope binding outlives the region and may be named from
            // outside it unless the world is closed.
            if (!ctx.prog.world.has(.closed_world)) {
                for (ctx.prog.ev.items) |*e| e.escapes = .unknown;
            }
        },
        .const_decl => |d| try walkExpr(ctx, d.val, .read),
        .assign => |a| {
            for (a.values) |v| try walkExpr(ctx, v, .read);
            for (a.targets) |t| {
                switch (t.*) {
                    .name => {},
                    .call => |c| for (c.args) |x| try walkExpr(ctx, x, .read),
                    .index => |ix| try walkExpr(ctx, ix.key, .read),
                    else => refuseRegion(ctx),
                }
            }
        },
        .call_stmt => |c| try walkExpr(ctx, c.expr, .read),
        .expr_stmt => |e| try walkExpr(ctx, e.expr, .read),
        .do_block => |d| try walkBlock(ctx, &d.body),
        .while_loop => |wl| {
            try walkExpr(ctx, wl.cond, .read);
            try walkLoop(ctx, &wl.body);
        },
        .repeat_loop => |r| {
            try walkLoop(ctx, &r.body);
            try walkExpr(ctx, r.cond, .read);
        },
        .num_for => |nf| {
            try walkExpr(ctx, nf.start, .read);
            try walkExpr(ctx, nf.stop, .read);
            if (nf.step) |st| try walkExpr(ctx, st, .read);
            try walkLoop(ctx, &nf.body);
        },
        .gen_for => |gf| {
            for (gf.iters) |it| try walkExpr(ctx, it, .read);
            try walkLoop(ctx, &gf.body);
        },
        .if_stmt => |f| {
            if (f.binding) |bd| try walkExpr(ctx, bd.expr, .read);
            try walkExpr(ctx, f.cond, .read);
            try walkBlock(ctx, &f.then);
            for (f.elseifs) |ei| {
                try walkExpr(ctx, ei.cond, .read);
                try walkBlock(ctx, &ei.body);
            }
            if (f.else_body) |*eb| try walkBlock(ctx, eb);
        },
        .ret => |r| for (r.vals) |v| try walkExpr(ctx, v, .read),
        .brk, .cont => {},
        .func_decl => |fd| try walkBlock(ctx, &fd.func.body),
        // A refusal, not a gap. The whole region goes pessimistic.
        else => refuseRegion(ctx),
    }
}

/// A loop body is the only place an ENUMERATION exists, and enumeration order
/// is only observable when the enumeration reaches an effect IN THE SAME LOOP.
/// Reading a collection in a loop that prints nothing observes no order.
fn walkLoop(ctx: *WalkCtx, b: *const ast.Block) anyerror!void {
    const saved_len = ctx.loop_reads.items.len;
    const saved_effect = ctx.loop_effect;
    ctx.loop_depth +|= 1;
    ctx.loop_effect = .no;

    try walkBlock(ctx, b);

    if (ctx.loop_effect != .no) {
        for (ctx.loop_reads.items[saved_len..]) |n| {
            if (evOf(ctx, n)) |e| e.order_reaches_effect = raise(e.order_reaches_effect, ctx.loop_effect);
        }
    }
    ctx.loop_reads.shrinkRetainingCapacity(saved_len);
    ctx.loop_depth -= 1;
    // An effect inside a nested loop is an effect in the enclosing one too.
    ctx.loop_effect = raise(saved_effect, ctx.loop_effect);
}

fn noteLoopRead(ctx: *WalkCtx, n: []const u8) !void {
    if (ctx.loop_depth == 0) return;
    try ctx.loop_reads.append(ctx.prog.alloc, n);
}

fn walkExpr(ctx: *WalkCtx, e: *const ast.Expr, pos: Position) anyerror!void {
    switch (e.*) {
        .name => |n| {
            if (evOf(ctx, n.ident)) |ev| {
                // A bare mention hands the whole place somewhere the walk
                // cannot see through.
                ev.escapes = .unknown;
                if (pos == .effect_arg or pos == .boundary_arg) {
                    ev.identity_captured = true;
                    ev.temporary_materialized = true;
                    if (pos == .boundary_arg) ev.crosses_boundary = .yes;
                }
                try noteLoopRead(ctx, n.ident);
            }
            if (isClockName(n.ident)) {
                ctx.prog.world = ctx.prog.world.with(.clock_read);
                markEffect(ctx);
            }
        },
        .binop => |b| {
            // IDENTITY CAPTURE. `a == b` on collections is a comparison of
            // WHICH ALLOCATION, not of contents, so it observes exactly the
            // fact the gap lists first as presumptively non-observable.
            if (b.op == .eq or b.op == .neq) {
                if (b.lhs.* == .name) {
                    if (evOf(ctx, b.lhs.name.ident)) |ev| ev.identity_captured = true;
                }
                if (b.rhs.* == .name) {
                    if (evOf(ctx, b.rhs.name.ident)) |ev| ev.identity_captured = true;
                }
            }
            try walkExpr(ctx, b.lhs, pos);
            try walkExpr(ctx, b.rhs, pos);
        },
        .unop => |u| try walkExpr(ctx, u.operand, pos),
        .call => |c| {
            var arg_pos = pos;
            if (c.func.* == .name) {
                const fname = c.func.name.ident;
                var recognized = false;
                if (isEffectName(fname)) {
                    markEffect(ctx);
                    arg_pos = .effect_arg;
                    recognized = true;
                }
                if (isClockName(fname)) {
                    ctx.prog.world = ctx.prog.world.with(.clock_read);
                    markEffect(ctx);
                    recognized = true;
                }
                // `s(i)` — an ELEMENT read of a place, not a call. It reads a
                // value, not the place, so it captures no identity.
                if (evOf(ctx, fname)) |_| {
                    try noteLoopRead(ctx, fname);
                    for (c.args) |a| try walkExpr(ctx, a, .read);
                    return;
                }
                if (!recognized) {
                    markEffectUnknown(ctx);
                    markBoundaryUnknown(ctx);
                }
            } else {
                // A COMPUTED CALLEE names no relation at all, so there is
                // nothing to recognize and nothing to prove pure.
                markEffectUnknown(ctx);
                markBoundaryUnknown(ctx);
                try walkExpr(ctx, c.func, .read);
            }
            for (c.args) |a| try walkExpr(ctx, a, arg_pos);
        },
        .method_call => |m| {
            var arg_pos = pos;
            if (m.obj.* == .name and isEffectName(m.obj.name.ident)) {
                markEffect(ctx);
                arg_pos = .effect_arg;
                // `io:write(...)`, `stdout:write(...)` — E2/E3. The receiver is
                // the world, not a place.
                for (m.args) |a| try walkExpr(ctx, a, arg_pos);
                return;
            }
            if (isEffectName(m.method) or isClockName(m.method)) {
                // THE SAME FACT THE `()` FACE PRODUCES. `clock()` published
                // `WorldFact.clock_read` and `t:now()` did not, so duration was
                // observable through one spelling of one relation and free
                // through the other — and `permits(.schedule)` read
                // `permitted` for a program that reads a clock subject-first.
                // A world fact is a property of the relation, never of the face
                // it was written with.
                if (isClockName(m.method)) ctx.prog.world = ctx.prog.world.with(.clock_read);
                markEffect(ctx);
                arg_pos = .effect_arg;
            } else {
                // `stdin:read()`, `path:open()`, `s:len()` — the SUBJECT-FIRST
                // face this project teaches as canonical. The receiver is not a
                // world name on the list and the relation is not on it either,
                // so the walk has recognized nothing here and says so.
                markEffectUnknown(ctx);
                markBoundaryUnknown(ctx);
            }
            try walkExpr(ctx, m.obj, arg_pos);
            for (m.args) |a| try walkExpr(ctx, a, arg_pos);
        },
        .index => |ix| {
            if (ix.obj.* == .name) {
                if (evOf(ctx, ix.obj.name.ident)) |_| {
                    try noteLoopRead(ctx, ix.obj.name.ident);
                    try walkExpr(ctx, ix.key, .read);
                    return;
                }
            }
            try walkExpr(ctx, ix.obj, pos);
            try walkExpr(ctx, ix.key, .read);
        },
        .field => |f| try walkExpr(ctx, f.obj, pos),
        .table => |t| {
            for (t.fields) |fl| {
                switch (fl) {
                    .positional => |v| try walkExpr(ctx, v, pos),
                    else => refuseRegion(ctx),
                }
            }
        },
        .float_lit => {
            for (ctx.prog.ev.items) |*ev| ev.float_produced = true;
        },
        .int_lit, .quoted, .nil, .true_lit, .false_lit, .vararg => {},
        // Anything else is a shape this walk does not see through.
        else => refuseRegion(ctx),
    }
}

// ===========================================================================
// tests
// ===========================================================================

const testing = std.testing;

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn parseModule(alloc: std.mem.Allocator, src: []const u8) !ast.Module {
    const owned = try alloc.dupe(u8, src);
    var lex = Lexer.init(owned, "observation_test.id");
    var p = Parser.init(&lex, alloc);
    p.idol_mode = true;
    return try p.parse_module();
}

fn programOf(arena: *std.heap.ArenaAllocator, src: []const u8, w: World) !Program {
    const alloc = arena.allocator();
    const mod = try parseModule(alloc, src);
    const held = try alloc.create(ast.Module);
    held.* = mod;
    return try analyze(alloc, held, w);
}

const no_obligations = Obligations{};

/// The fact set a runtime-built membership place carries, copied from
/// `eqspace.zig`'s own fixture so the two modules are talking about the same
/// program.
fn eqFacts(list: []const eqspace.Fact) eqspace.FactSet {
    var s: eqspace.FactSet = .{};
    for (list) |f| s.insert(f);
    return s;
}

const runtime_base = [_]eqspace.Fact{
    .in_bounds,
    .backend_admits_indexed_write,
    .no_escape,
    .immutable_after_build,
    .domain_bounded,
};

/// A clean place: complete walk, nothing captured, nothing escaping, constant
/// indices, no traps. Every positive control below is THIS with one field
/// changed, so the control isolates one fact.
const clean = Evidence{
    .complete = true,
    .identity_captured = false,
    .order_reaches_effect = .no,
    // A place used purely as a SET — the identity `eqspace` models. A real
    // program on this surface reads positionally and gets `.yes` here, which is
    // why the `order` freedom is CLOSED for `rt.id` in `gate/observation.sh`
    // and open for this fixture. Both answers are correct and they differ.
    .order_declared = .no,
    .positional_read = .no,
    .escapes = .no,
    .crosses_boundary = .no,
    .quotient = .modulus,
    .may_trap = .no,
    .float_produced = false,
    .has_effect = .no,
    .temporary_materialized = false,
    .facts = .{
        .ordered = .no,
        .extent = .{ .exact = 3 },
        .determinacy = .exact,
        .alias = .no,
        .escape = .no,
        .origin = .literal,
    },
};

// ---------------------------------------------------------------------------
// POSITIVE CONTROLS FIRST. GAP-170 deletion condition 3 is the one most likely
// to be faked: a model that only ever says "not observed" is worthless. Every
// test in this block asserts a BLOCK, and each is paired with the counterfactual
// that must NOT block.
// ---------------------------------------------------------------------------

test "observation: POSITIVE CONTROL — capturing allocation identity blocks existence erasure" {
    const captured = blk: {
        var e = clean;
        e.identity_captured = true;
        break :blk e;
    };
    const r_block = classifyAll(ordinary_executable, captured, no_obligations, .{ .place = 0 });
    const r_free = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });

    try testing.expectEqual(Tri.yes, r_block.get(.allocation_identity).observed);
    try testing.expectEqual(Reason.identity_captured, r_block.get(.allocation_identity).reason);
    try testing.expectEqual(Permit.blocked_observed, permits(&r_block, .existence).permit);
    try testing.expectEqual(Permit.blocked_observed, permits(&r_block, .zero_copy).permit);

    // The counterfactual, and without it the block above proves nothing.
    try testing.expectEqual(Tri.no, r_free.get(.allocation_identity).observed);
    try testing.expectEqual(Permit.permitted, permits(&r_free, .existence).permit);
    try testing.expectEqual(Permit.permitted, permits(&r_free, .zero_copy).permit);
}

test "observation: POSITIVE CONTROL — fixing iteration order blocks the order freedom" {
    const fixed = blk: {
        var e = clean;
        e.order_reaches_effect = .yes;
        break :blk e;
    };
    const r_block = classifyAll(ordinary_executable, fixed, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Tri.yes, r_block.get(.iteration_order).observed);
    try testing.expectEqual(Reason.order_reaches_effect, r_block.get(.iteration_order).reason);
    try testing.expectEqual(Permit.blocked_observed, permits(&r_block, .order).permit);

    const r_free = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Permit.permitted, permits(&r_free, .order).permit);
}

test "observation: POSITIVE CONTROL — the block reaches eqspace and deletes families" {
    // Deletion condition 3's operative half: the block must change the
    // CANDIDATE SET, not merely a boolean. `bitset` and `hashed` both permute;
    // with order observed neither is lawful, and `scan` — the family nothing
    // frees — survives.
    const facts = eqFacts(&runtime_base);
    const fixed = blk: {
        var e = clean;
        e.order_reaches_effect = .yes;
        break :blk e;
    };
    const r_block = classifyAll(ordinary_executable, fixed, no_obligations, .{ .place = 0 });
    const r_free = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });

    const blocked = admit(&r_block, facts);
    const opened = admit(&r_free, facts);

    try testing.expect(opened.admits(.bitset));
    try testing.expect(opened.admits(.hashed));
    try testing.expect(!blocked.admits(.bitset));
    try testing.expect(!blocked.admits(.hashed));
    try testing.expect(blocked.admits(.scan));
    try testing.expect(blocked.blocked_count > 0);
    // Every casualty names its freedom, its class and its reason.
    for (blocked.blockedSlice()) |b| {
        try testing.expectEqual(Freedom.order, b.freedom);
        try testing.expectEqual(Class.iteration_order, b.class.?);
        try testing.expectEqual(Reason.order_reaches_effect, b.reason.?);
    }
}

test "observation: POSITIVE CONTROL — a real program that compares two collections" {
    // Not a hand-set flag: the AST walk finds the identity comparison.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    t = (1, 2, 3)
        \\    if s == t
        \\        1
        \\    0
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expect(ev.identity_captured);
    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.yes, r.get(.allocation_identity).observed);
    try testing.expect(!permits(&r, .existence).ok());
}

test "observation: POSITIVE CONTROL — a real program that prints its elements in order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    i = 0
        \\    while i < 3
        \\        print(s(i + 1))
        \\        i += 1
        \\    0
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expectEqual(Tri.yes, ev.order_reaches_effect);
    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.yes, r.get(.iteration_order).observed);
    try testing.expectEqual(Permit.blocked_observed, permits(&r, .order).permit);
}

test "observation: POSITIVE CONTROL — a POSITIONAL read fixes order with no effect at all" {
    // The second, quieter way order becomes observable, and the one that makes
    // `gate/observation.sh`'s `rt.id` probe honest: `s(2)` must return the
    // second element, so no permutation of storage is lawful even though
    // nothing is printed and nothing escapes.
    const positional = blk: {
        var e = clean;
        e.positional_read = .yes;
        break :blk e;
    };
    const r = classifyAll(ordinary_executable, positional, no_obligations, .{ .place = 0 });
    // The ENUMERATION order is still free — nothing walks it to an observer.
    try testing.expectEqual(Tri.no, r.get(.iteration_order).observed);
    // The FIXED order is not, and that is the class that closes the freedom.
    try testing.expectEqual(Tri.yes, r.get(.fixed_ordering).observed);
    try testing.expectEqual(Permit.blocked_observed, permits(&r, .order).permit);
    try testing.expectEqual(Class.fixed_ordering, permits(&r, .order).by_class.?);
    // And it closes ONLY that one: existence, layout and width stay open.
    try testing.expect(permits(&r, .existence).ok());
    try testing.expect(permits(&r, .layout).ok());
    try testing.expect(permits(&r, .width).ok());
}

test "observation: the gate's own `rt.id` probe, classified" {
    // The program `gate/observation.sh` measures at 74 instructions against a
    // 2-instruction lawful floor. Every claim that gate's header makes about
    // which freedoms are open is asserted HERE, so the prose cannot drift from
    // the model.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (0, 0, 0)
        \\    i = 0
        \\    while i < 3
        \\        s[i + 1] = i * 7
        \\        i += 1
        \\    h = 0
        \\    j = 0
        \\    while j < 3
        \\        h += s[j + 1]
        \\        j += 1
        \\    h & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const r = prog.report("s", no_obligations).?;
    // OPEN: nothing observes the place's identity, address or existence.
    try testing.expectEqual(Tri.no, r.get(.allocation_identity).observed);
    try testing.expect(permits(&r, .existence).ok());
    try testing.expect(permits(&r, .zero_copy).ok());
    try testing.expect(permits(&r, .layout).ok());
    try testing.expect(permits(&r, .schedule).ok());
    // CLOSED, and for a NAMED semantic reason rather than an accident: the
    // program reads `s(j + 1)`, so index-to-value is fixed.
    try testing.expectEqual(Permit.blocked_observed, permits(&r, .order).permit);
    try testing.expectEqual(Class.fixed_ordering, permits(&r, .order).by_class.?);
}

test "observation: NEGATIVE CONTROL — the same loop with no effect fixes no order" {
    // The straw-man check. If the walk convicted every loop, the control above
    // would prove nothing: a rule that always says "observed" is as worthless
    // as one that always says "free", it just fails safe.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    h = 0
        \\    i = 0
        \\    while i < 3
        \\        h += s(i + 1)
        \\        i += 1
        \\    h & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expectEqual(Tri.no, ev.order_reaches_effect);
    try testing.expect(!ev.identity_captured);
}

// ---------------------------------------------------------------------------
// Observability is a WORLD FACT, not a table
// ---------------------------------------------------------------------------

test "observation: a security world observes timing, layout and addresses; an ordinary one does not" {
    const sec = ordinary_executable.with(.security_adversary);
    const r_ord = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    const r_sec = classifyAll(sec, clean, no_obligations, .{ .place = 0 });

    try testing.expectEqual(Tri.no, r_ord.get(.instruction_schedule).observed);
    try testing.expectEqual(Tri.no, r_ord.get(.physical_layout).observed);
    try testing.expectEqual(Tri.no, r_ord.get(.allocation_identity).observed);

    try testing.expectEqual(Tri.yes, r_sec.get(.instruction_schedule).observed);
    try testing.expectEqual(Tri.yes, r_sec.get(.physical_layout).observed);
    try testing.expectEqual(Tri.yes, r_sec.get(.allocation_identity).observed);
    for ([_]Class{ .instruction_schedule, .physical_layout, .allocation_identity }) |c| {
        try testing.expectEqual(Reason.security_world, r_sec.get(c).reason);
    }
    // And the freedoms follow the world rather than a constant.
    try testing.expect(permits(&r_ord, .schedule).ok());
    try testing.expect(permits(&r_ord, .layout).ok());
    try testing.expect(!permits(&r_sec, .schedule).ok());
    try testing.expect(!permits(&r_sec, .layout).ok());
}

test "observation: SEMANTIC TIME IS NOT PHYSICAL TIME — until a clock is read" {
    // Duration and schedule are free by default. Reading a clock is an EFFECT
    // and it is what makes them observable; a deadline does the same.
    const r_plain = classifyAll(ordinary_executable, clean, no_obligations, .program);
    try testing.expectEqual(Tri.no, r_plain.get(.instruction_schedule).observed);

    const r_clock = classifyAll(ordinary_executable.with(.clock_read), clean, no_obligations, .program);
    try testing.expectEqual(Tri.yes, r_clock.get(.instruction_schedule).observed);
    try testing.expectEqual(Reason.duration_observed, r_clock.get(.instruction_schedule).reason);

    const r_dead = classifyAll(ordinary_executable.with(.deadline), clean, no_obligations, .program);
    try testing.expectEqual(Tri.yes, r_dead.get(.instruction_schedule).observed);
    // Memoization goes with it: whether a result is recomputed becomes visible
    // once duration is.
    try testing.expect(!permits(&r_clock, .memoization).ok());
    try testing.expect(permits(&r_plain, .memoization).ok());
}

test "observation: the walk DISCOVERS the clock read rather than being told" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    t = clock()
        \\    s(1) + t & 255
        \\
    , ordinary_executable);
    defer prog.deinit();
    try testing.expect(prog.world.has(.clock_read));
}

test "observation: a foreign boundary has FINITE EXTENT and does not infect the program" {
    // law §105 BOUNDARY-ONE. The boundary place loses layout and width; a place
    // that does not cross it keeps both, in the same program.
    const at_boundary = blk: {
        var e = clean;
        e.crosses_boundary = .yes;
        break :blk e;
    };
    const r_b = classifyAll(ordinary_executable, at_boundary, no_obligations, .{ .place = 0 });
    const r_i = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 1 });

    try testing.expectEqual(Tri.yes, r_b.get(.foreign_representation).observed);
    try testing.expectEqual(Tri.yes, r_b.get(.physical_layout).observed);
    try testing.expect(!permits(&r_b, .layout).ok());
    try testing.expect(!permits(&r_b, .width).ok());

    try testing.expectEqual(Tri.no, r_i.get(.foreign_representation).observed);
    try testing.expect(permits(&r_i, .layout).ok());
    try testing.expect(permits(&r_i, .width).ok());
}

test "observation: an OPEN world (dylib/obj) makes the foreign observer demanded" {
    // `demand.zig`'s W1: `world_closed` defaults to FALSE and only the
    // executable site sets it. Getting that backwards deletes a library's state.
    const open = World{};
    try testing.expect(open.observers().contains(.foreign));
    try testing.expect(!ordinary_executable.observers().contains(.foreign));
}

// ---------------------------------------------------------------------------
// N2, N5 and the three-valued rule
// ---------------------------------------------------------------------------

test "observation: N2 — an incomplete walk classifies UNKNOWN and blocks EVERY freedom" {
    const incomplete = blk: {
        var e = clean;
        e.complete = false;
        break :blk e;
    };
    const r = classifyAll(ordinary_executable, incomplete, no_obligations, .{ .place = 0 });
    for (r.facts) |f| {
        try testing.expectEqual(Tri.unknown, f.observed);
        try testing.expectEqual(Reason.evidence_incomplete, f.reason);
        try testing.expect(f.blocks());
    }
    for (std.enums.values(Freedom)) |fr| {
        try testing.expectEqual(Permit.blocked_unknown, permits(&r, fr).permit);
    }
    try testing.expectEqual(@as(usize, 0), permittedSet(&r).count());
}

test "observation: UNKNOWN never reads as NO — the three-valued rule, executably" {
    // The whole soundness argument. A two-valued fact would let an unproven
    // non-observation open a freedom, which is how an escape fact becomes
    // unsound.
    const u = Fact{
        .class = .allocation_identity,
        .observed = .unknown,
        .by = no_observer,
        .reason = .presumed_observable,
        .prov = .{ .producer = .default_conservative, .authority = .default, .subject = .program },
    };
    try testing.expect(u.blocks());
    try testing.expect(!u.observed.proven());
}

test "observation: N5 — a hyperproperty world authorizes NOTHING, and says so distinctly" {
    // Determinism, noninterference, serializability and linearizability are
    // properties of SETS of executions. Every check in this module is
    // single-trace, so it is the wrong instrument and refuses rather than
    // answering.
    inline for ([_]WorldFact{
        .determinism_demanded,
        .noninterference_demanded,
        .serializability_demanded,
        .linearizability_demanded,
    }) |wf| {
        const w = ordinary_executable.with(wf);
        try testing.expect(w.demandsHyperproperty());
        const r = classifyAll(w, clean, no_obligations, .{ .place = 0 });
        for (std.enums.values(Freedom)) |fr| {
            try testing.expectEqual(Permit.blocked_hyperproperty, permits(&r, fr).permit);
        }
        // And it must be a DIFFERENT verdict from "observed", or the reason a
        // reader gets is a lie about which instrument failed.
        try testing.expect(permits(&r, .layout).permit != .blocked_observed);
    }
    // The ordinary world is unaffected — otherwise this would just be a global
    // off switch.
    const r_ord = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    try testing.expect(permits(&r_ord, .layout).ok());
}

test "observation: every classification carries provenance" {
    // Deletion condition 1 says "with provenance", and a fact without one
    // cannot be audited later.
    const r = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 7 });
    for (r.facts) |f| {
        try testing.expectEqual(Subject{ .place = 7 }, f.prov.subject);
        // A `no` is only ever issued by a PROOF, never by the default.
        if (f.observed == .no) try testing.expectEqual(Authority.proof, f.prov.authority);
        // An `unknown` never names an observer, because naming one is a claim.
        if (f.observed == .unknown) try testing.expectEqual(@as(usize, 0), f.by.count());
        // A `yes` always names at least one observer — "observable" with no
        // observer is the hand-wave the roster exists to stop.
        if (f.observed == .yes) try testing.expect(f.by.count() > 0);
    }
}

// ---------------------------------------------------------------------------
// Obligation — the co-equal other side
// ---------------------------------------------------------------------------

test "observation: a POSITIVE obligation adds an observation and closes a freedom" {
    const ob = Obligations.of(&.{.deadline}, &.{});
    const r = classifyAll(ordinary_executable, clean, ob, .{ .place = 0 });
    try testing.expectEqual(Tri.yes, r.get(.instruction_schedule).observed);
    try testing.expectEqual(Reason.obligation_positive, r.get(.instruction_schedule).reason);
    try testing.expect(!permits(&r, .schedule).ok());

    const r_none = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    try testing.expect(permits(&r_none, .schedule).ok());
}

test "observation: ORDERING as a positive obligation blocks the order freedom" {
    const ob = Obligations.of(&.{.ordering}, &.{});
    const r = classifyAll(ordinary_executable, clean, ob, .{ .place = 0 });
    try testing.expectEqual(Tri.yes, r.get(.iteration_order).observed);
    try testing.expect(!permits(&r, .order).ok());
    // And it reaches eqspace: the permuting families are deleted.
    const a = admit(&r, eqFacts(&runtime_base));
    try testing.expect(!a.admits(.bitset));
    try testing.expect(!a.admits(.hashed));
    try testing.expect(a.admits(.scan));
}

test "observation: a NEGATIVE obligation DELETES MECHANISM — the strongest enabler" {
    // GAP-170: *a proven `cannot` deletes whole mechanisms.* Four proven
    // negatives delete five mechanisms; with none proven, nothing is deleted.
    const proven = Obligations.of(&.{}, &.{ .no_allocation, .no_network, .no_persistent_state, .no_duplicate_external_effect });
    const m = mechanismsDeleted(proven.negative);
    try testing.expect(m.contains(.heap_allocator));
    try testing.expect(m.contains(.network_stack));
    try testing.expect(m.contains(.durable_log));
    try testing.expect(m.contains(.persistence_layer));
    try testing.expect(m.contains(.dedup_ledger));
    try testing.expectEqual(@as(usize, 5), m.count());

    // The control. An UNPROVEN negative deletes nothing — a mechanism deleted
    // on an expectation is a mechanism deleted wrongly.
    try testing.expectEqual(@as(usize, 0), mechanismsDeleted(NegativeSet{}).count());
}

test "observation: a NEGATIVE obligation can also CONSTRAIN rather than delete" {
    // The asymmetry worth keeping: `no_secret_dependent_timing` is a promise
    // ABOUT the schedule and the access pattern, so it makes both observable
    // and takes freedom away, where `no_network` gives freedom.
    const ob = Obligations.of(&.{}, &.{.no_secret_dependent_timing});
    const r = classifyAll(ordinary_executable, clean, ob, .{ .place = 0 });
    try testing.expectEqual(Tri.yes, r.get(.instruction_schedule).observed);
    try testing.expectEqual(Tri.yes, r.get(.physical_layout).observed);
    try testing.expectEqual(Reason.obligation_negative, r.get(.instruction_schedule).reason);
    try testing.expect(!permits(&r, .schedule).ok());
    try testing.expect(!permits(&r, .layout).ok());
    // And it deletes no mechanism, which is the half a "negatives are always
    // enablers" reading gets wrong.
    try testing.expectEqual(@as(usize, 0), mechanismsDeleted(ob.negative).count());
}

// ---------------------------------------------------------------------------
// The eqspace bridge — deletion condition 2
// ---------------------------------------------------------------------------

test "observation: EVERY freedom is gated by a class, and no freedom is ungated" {
    // Deletion condition 2 in one assertion: there is no realization freedom
    // reachable without a gating class, so there is no path from a heuristic to
    // a permission.
    for (std.enums.values(Freedom)) |f| {
        try testing.expect(gatingClasses(f).len > 0);
    }
}

test "observation: admit() takes facts and a report and NEVER a cost" {
    // §84 by signature, the same enforcement `eqspace.contract` has. Perturbing
    // every cost on the contracted space changes no admission.
    const facts = eqFacts(&runtime_base);
    const r = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    var a = admit(&r, facts);
    for (a.space.survivors[0..a.space.survivor_count]) |*c| {
        c.cost_estimate.setFact(.latency, std.math.floatMax(f32), .measured);
    }
    const b = admit(&r, facts);
    try testing.expectEqual(a.admittedCount(), b.admittedCount());
}

test "observation: the observation gate deletes families eqspace's FACTS alone would keep" {
    // The claim that makes this module load-bearing rather than decorative:
    // with identical `eqspace` facts, two different observation reports produce
    // two different candidate sets.
    const facts = eqFacts(&runtime_base);
    const sp = eqspace.contract(facts);
    const survivors = sp.survivor_count;

    const captured = blk: {
        var e = clean;
        e.identity_captured = true;
        e.order_reaches_effect = .yes;
        break :blk e;
    };
    const r_block = classifyAll(ordinary_executable, captured, no_obligations, .{ .place = 0 });
    const r_free = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });

    const a_block = admit(&r_block, facts);
    const a_free = admit(&r_free, facts);
    try testing.expectEqual(survivors, a_free.admittedCount());
    try testing.expect(a_block.admittedCount() < a_free.admittedCount());
}

test "observation: a place with NO evidence admits nothing — absence is not permission" {
    const facts = eqFacts(&runtime_base);
    const nothing_known = Evidence{};
    const r = classifyAll(ordinary_executable, nothing_known, no_obligations, .{ .place = 0 });
    const a = admit(&r, facts);
    // `scan` exercises no freedom, so it survives an empty observation model —
    // which is correct and is exactly why it is the conservative realization.
    try testing.expect(a.admits(.scan));
    try testing.expect(!a.admits(.bitset));
    try testing.expect(!a.admits(.hashed));
}

// ---------------------------------------------------------------------------
// The quotient, E1, and the width freedom
// ---------------------------------------------------------------------------

test "observation: E1 observes 8 bits, so 56 bits of every answer are a width freedom" {
    // MEASURED in `docs/observation.md` §3.3: `main` returning 300 exits 44.
    // The FACT is what this module contributes; the transform consuming it is
    // the recurrence lane's and is not claimed here.
    const modded = blk: {
        var e = clean;
        e.quotient = .modulus;
        break :blk e;
    };
    const r = classifyAll(ordinary_executable, modded, no_obligations, .program);
    try testing.expectEqual(Tri.no, r.get(.representation_width).observed);
    try testing.expectEqual(Reason.demand_quotient_coarser, r.get(.representation_width).reason);
    try testing.expect(permits(&r, .width).ok());

    const full = blk: {
        var e = clean;
        e.quotient = .full;
        e.escapes = .unknown;
        break :blk e;
    };
    const r_full = classifyAll(ordinary_executable, full, no_obligations, .program);
    try testing.expectEqual(Tri.yes, r_full.get(.representation_width).observed);
}

test "observation: a nothing-quotient frees even the DEMANDED-VALUES class" {
    // The bottom of the lattice `demand.zig` implements: `D = nothing`. It is
    // the one route by which a presumptively-observable class reads free.
    const dead = blk: {
        var e = clean;
        e.quotient = .nothing;
        break :blk e;
    };
    const r = classifyAll(ordinary_executable, dead, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Tri.no, r.get(.demanded_values).observed);
    try testing.expect(permits(&r, .existence).ok());
}

test "observation: floating point is observable unless a precision demand permits otherwise" {
    const fp = blk: {
        var e = clean;
        e.float_produced = true;
        break :blk e;
    };
    const r_strict = classifyAll(ordinary_executable, fp, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Tri.yes, r_strict.get(.float_result).observed);
    try testing.expect(!permits(&r_strict, .precision).ok());

    const r_bounded = classifyAll(ordinary_executable.with(.precision_bounded), fp, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Tri.no, r_bounded.get(.float_result).observed);
    try testing.expectEqual(Reason.precision_demand_permits, r_bounded.get(.float_result).reason);
    try testing.expect(permits(&r_bounded, .precision).ok());
}

test "observation: a possible trap blocks memoization, and `unknown` is not `no`" {
    const trappy = blk: {
        var e = clean;
        e.may_trap = .unknown;
        break :blk e;
    };
    const r = classifyAll(ordinary_executable, trappy, no_obligations, .{ .place = 0 });
    try testing.expectEqual(Tri.unknown, r.get(.recompute_vs_memoize).observed);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r, .memoization).permit);
}

// ---------------------------------------------------------------------------
// The walk, on real source
// ---------------------------------------------------------------------------

test "observation: the walk reports how many statements it examined" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    s(1)
        \\
    , ordinary_executable);
    defer prog.deinit();
    try testing.expect(prog.points > 0);
    try testing.expect(prog.census.count() > 0);
}

test "observation: a runtime index leaves may_trap UNKNOWN, so memoization stays shut" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    h = 0
        \\    i = 0
        \\    while i < 3
        \\        h += s[i + 1]
        \\        i += 1
        \\    h & 255
        \\
    , ordinary_executable);
    defer prog.deinit();
    const ev = prog.byName("s").?;
    try testing.expectEqual(Tri.unknown, ev.may_trap);
}

test "observation: handing a place to an effect captures its identity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    print(s)
        \\    0
        \\
    , ordinary_executable);
    defer prog.deinit();
    const ev = prog.byName("s").?;
    try testing.expect(ev.identity_captured);
    try testing.expect(ev.temporary_materialized);
    const r = prog.report("s", no_obligations).?;
    try testing.expect(!permits(&r, .zero_copy).ok());
}

// ---------------------------------------------------------------------------
// The effect fact, and the fail-open that used to issue it as a PROOF
// ---------------------------------------------------------------------------

test "observation: DIAGNOSTIC — a region that reads input proves no effect-freedom" {
    // The wrong answer this closes. `stdin:read()` is the canonical input face
    // (`CLAUDE.md` WORLD-ONE: prefer `stdin:read()` over `io.*`) and it is on
    // no spelling list, so the walk found no effect, `has_effect` published
    // `.no`, and `effect_order` read `free(..., .observation_walk)` with
    // `authority = .proof`. `permits(.memoization)` was `.permitted` for a
    // region that consumes input, and memoizing that region skips the read.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    x = stdin:read()
        \\    s(1) + x & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    // The unknown is the EFFECT fact, not a refused region. Without this the
    // test would also pass if the walk simply stopped seeing the program.
    try testing.expect(ev.complete);
    try testing.expectEqual(Tri.unknown, ev.has_effect);

    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.unknown, r.get(.effect_order).observed);
    try testing.expectEqual(Tri.unknown, r.get(.recompute_vs_memoize).observed);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r, .memoization).permit);
}

test "observation: CONTROL — a region that applies no relation still PROVES effect-freedom" {
    // The straw-man half. A refusal that fires on every program is not a
    // classification, so the fix has to leave the provable case provable —
    // `.no` still means "this region applied no relation at all", and it is
    // still issued with `authority = .proof`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    s(1) & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expectEqual(Tri.no, ev.has_effect);

    const r = prog.report("s", no_obligations).?;
    const eo = r.get(.effect_order);
    try testing.expectEqual(Tri.no, eo.observed);
    try testing.expectEqual(Authority.proof, eo.prov.authority);
}

test "observation: CONTROL — a recognized effect still proves `.yes`, not `unknown`" {
    // The other straw man. Raising an unrecognized face to `unknown` must not
    // cost the walk the answers it really had: `print` is recognized, so the
    // effect is OBSERVED, and a reader is never told `unknown` where a proof
    // exists.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    print(s(1))
        \\    0
        \\
    , ordinary_executable);
    defer prog.deinit();

    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.yes, r.get(.effect_order).observed);
    try testing.expectEqual(Tri.yes, r.get(.recompute_vs_memoize).observed);
}

test "observation: DIAGNOSTIC — an unclassified application proves no boundary-freedom" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    x = stdin:read()
        \\    s(1) + x & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expect(ev.complete);
    try testing.expectEqual(Tri.unknown, ev.crosses_boundary);

    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.unknown, r.get(.foreign_representation).observed);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r, .layout).permit);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r, .width).permit);
}

test "observation: CONTROL — element reads alone still PROVE boundary-freedom" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    s[1] & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expectEqual(Tri.no, ev.crosses_boundary);

    const r = prog.report("s", no_obligations).?;
    const fr = r.get(.foreign_representation);
    try testing.expectEqual(Tri.no, fr.observed);
    try testing.expectEqual(Authority.proof, fr.prov.authority);
    try testing.expect(permits(&r, .layout).ok());
    try testing.expect(permits(&r, .width).ok());
}

test "observation: an unclassified relation in a loop leaves ENUMERATION order unknown" {
    // The same fail-open in the order dimension, and it is a separate
    // consumer: `walkLoop` published `order_reaches_effect = false` for a loop
    // whose body applies a relation it cannot see through, so `iteration_order`
    // could read free while the loop was writing its enumeration out.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (10, 20, 30)
        \\    h = 0
        \\    i = 0
        \\    while i < 3
        \\        h += s(i + 1)
        \\        sink:take(h)
        \\        i += 1
        \\    h & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expect(ev.complete);
    try testing.expectEqual(Tri.unknown, ev.order_reaches_effect);
    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.unknown, r.get(.iteration_order).observed);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r, .order).permit);
}

test "observation: a clock is a clock in either face, so the SCHEDULE freedom shuts in both" {
    // `clock()` and `t:now()` are one relation written two ways, and the walk
    // produced `WorldFact.clock_read` for only one of them. `permits(.schedule)`
    // therefore read `permitted` for a program whose duration is observable.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    t = wall:now()
        \\    s(1) + t & 255
        \\
    , ordinary_executable);
    defer prog.deinit();

    try testing.expect(prog.world.has(.clock_read));
    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.yes, r.get(.instruction_schedule).observed);
    try testing.expectEqual(Reason.duration_observed, r.get(.instruction_schedule).reason);
    try testing.expectEqual(Permit.blocked_observed, permits(&r, .schedule).permit);
}

test "observation: §19 control — removing the ALIAS proof closes zero-copy and layout" {
    // `HPLS.md` §19's permanent negative controls, extended from the candidate
    // set to the observation model: a place fact that changes no classification
    // is not operative. `place.Facts.alias` is consumed HERE and nowhere else in
    // this file, so this test is the whole evidence that it has a consumer.
    var without = clean;
    without.facts.alias = .unknown;
    const r_with = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    const r_without = classifyAll(ordinary_executable, without, no_obligations, .{ .place = 0 });

    try testing.expectEqual(Tri.no, r_with.get(.allocation_identity).observed);
    try testing.expectEqual(Tri.unknown, r_without.get(.allocation_identity).observed);
    try testing.expectEqual(Tri.unknown, r_without.get(.physical_layout).observed);
    try testing.expect(permits(&r_with, .zero_copy).ok());
    try testing.expect(permits(&r_with, .layout).ok());
    try testing.expectEqual(Permit.blocked_unknown, permits(&r_without, .zero_copy).permit);
    try testing.expectEqual(Permit.blocked_unknown, permits(&r_without, .layout).permit);
    // And it changes the CANDIDATE SET, which is what makes it operative rather
    // than decorative.
    const facts = eqFacts(&runtime_base);
    try testing.expect(admit(&r_with, facts).admittedCount() > admit(&r_without, facts).admittedCount());
}

test "observation: DIAGNOSTIC — an effect in a sibling relation blocks effect-freedom" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prog = try programOf(&arena,
        \\main: i64 = ()
        \\    s = (1, 2, 3)
        \\    s(1) & 255
        \\helper: i64 = ()
        \\    print(1)
        \\    0
        \\
    , ordinary_executable);
    defer prog.deinit();

    const ev = prog.byName("s").?;
    try testing.expect(ev.complete);
    try testing.expectEqual(Tri.yes, ev.has_effect);

    const r = prog.report("s", no_obligations).?;
    try testing.expectEqual(Tri.yes, r.get(.effect_order).observed);
    try testing.expectEqual(Tri.yes, r.get(.recompute_vs_memoize).observed);
    try testing.expectEqual(Permit.blocked_observed, permits(&r, .memoization).permit);
}

test "observation: the sixteen classes are the gap's two lists, nine and seven" {
    var non_obs: usize = 0;
    var obs: usize = 0;
    for (std.enums.values(Class)) |c| {
        switch (c.presumption()) {
            .non_observable => non_obs += 1,
            .observable => obs += 1,
        }
    }
    try testing.expectEqual(@as(usize, 9), non_obs);
    try testing.expectEqual(@as(usize, 7), obs);
    try testing.expectEqual(@as(usize, 16), Class.count);
}

test "observation: the model is not trivially conservative and not trivially permissive" {
    // THE ANTI-VACUITY CHECK, and it is the one that makes the rest evidence.
    // A model that answers `observed` to everything passes every positive
    // control; a model that answers `not observed` to everything passes every
    // negative one. Neither is worth anything, so both are excluded here.
    const r = classifyAll(ordinary_executable, clean, no_obligations, .{ .place = 0 });
    try testing.expect(r.observedCount() > 0);
    try testing.expect(r.freeCount() > 0);

    // A maximally proven place is maximally free, and that is the right answer
    // — so the discrimination has to be shown ACROSS reports rather than inside
    // one. `clean` opens every freedom; one captured identity closes some and
    // not others; an empty evidence set closes all.
    const p_clean = permittedSet(&r);
    try testing.expectEqual(@as(usize, Freedom.count), p_clean.count());

    const captured = blk: {
        var e = clean;
        e.identity_captured = true;
        break :blk e;
    };
    const p_part = permittedSet(&classifyAll(ordinary_executable, captured, no_obligations, .{ .place = 0 }));
    try testing.expect(p_part.count() > 0);
    try testing.expect(p_part.count() < p_clean.count());

    const p_none = permittedSet(&classifyAll(ordinary_executable, Evidence{}, no_obligations, .{ .place = 0 }));
    try testing.expectEqual(@as(usize, 0), p_none.count());
}
