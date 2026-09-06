//! LOWER — authority → enforcement realization selection (GAP-185).
//!
//! `world.zig` owns the facts; this module owns the DECISION: given the
//! semantic authority over a subject, the observation/attack model of the
//! world, and the mechanisms the target world admits, select the cheapest
//! enforcement that preserves every demanded property — or refuse. Three
//! rungs, in the order GAP-185 states them:
//!
//! 1. STATIC — `Authority.fixedAgainst` proves no dynamic enforcement can
//!    ever observe a violation, so the plan carries the witnessing authority
//!    facts and zero cost (the "zero overhead when authority is statically
//!    fixed" rung). The proof quantifies over the program's OWN accesses, so
//!    the rung stands only in a world without the `foreign_boundary` fact:
//!    foreign code in-image can forge pointers, and a proof over this
//!    program's accesses covers none of its (`world.enforces`' ruling).
//! 2. DYNAMIC — the cheapest admitted mechanism whose `world.enforces`
//!    superset covers the demand, costed under an explicit access/crossing
//!    profile (`law.cost.explain`: the answer carries why).
//! 3. REFUSED — no admitted mechanism preserves every demanded property.
//!    Fail closed; a gap in the target world is recorded, never silently
//!    weakened.
//!
//! CHERI construction is DERIVED from the authority facts (`capabilityOf`),
//! never hand-written: extent from the subject's extent fact, permissions
//! from `readonly`, sealing from `unique`, the global bit from `nonescape`.
//! A capability that cannot be constructed statically is not a realization,
//! so derivability is an admissibility condition for `.cheri`.
//!
//! DELETION WITNESS (`law.bridge.death`): host owner before — this module;
//! Idol owner after — realization selection as a witnessed graph transform
//! over world facts; the BACKEND lowering consumer LANDED — `selectModule`
//! below is called per census place during realization by the graph-backed
//! C99 realization arm in `main.zig` (`selectPlace` remains the graph-facing
//! selection over one census row: authority facts reach `select` through the
//! census the graph carries, not through a host projection). The per-place
//! PLANS constraining lowering LANDED — `collectStaticPlaces` populates
//! `graph.static_places` so `dnir_lower` elides the enforcement it would
//! emit per place when the authority is statically fixed. The measured-cost
//! face LANDED — a `MeasuredCost` fact names one mechanism, one target
//! triple, one unit and the exact measured subject revision, and
//! `selectMeasured` lets measured costs decide ONLY a uniform comparison
//! (every admissible candidate measured on the named target in one unit);
//! anything less leaves `costOf`'s stated orders to decide.
//! `gate/lower/cost.sh` measures the software check's per-access cost on the
//! host. Measured facts now REACH the realization walk — `selectPlace`,
//! `selectModule` and `collectStaticPlaces` delegate to their `*Measured`
//! variants, which thread a measured slice through `selectMeasured`; the
//! existing names remain the empty-measurement face. The PROVENANCE seam LANDED —
//! `parseMeasured` reconstructs one `MeasuredCost` fact from one
//! `idol.world.cost.v1` row (exactly what `gate/lower/cost.sh` emits), the
//! single producer of a measured fact from the measured world
//! (`law.fact.producer.one`): it fails closed on a foreign schema, an unknown
//! mechanism/triple/unit name, a missing cost field, an unrepresentable cost
//! magnitude, or an empty subject revision (`law.evidence.subject.one`). A
//! negative float cost is the producer's documented noise floor and
//! reconstructs as zero, so a genuine row always constructs its fact.
//! `parseMeasurements` owns the facts
//! from one complete newline-delimited evidence stream, and the graph-backed
//! C99 arm hands that exact slice to both measured walk consumers. A malformed
//! stream refuses rather than letting partial evidence decide. Next host
//! boundary — measured costs for hardware mechanisms such as MPK on x86_64.

const std = @import("std");
const observation = @import("observation.zig");
const place = @import("place.zig");
const target_model = @import("target_model.zig");
const world = @import("world.zig");

const Mechanism = world.Mechanism;
const PropertySet = world.PropertySet;

/// The demand profile a selection is costed under: how many enforced
/// accesses and how many domain crossings the realized program performs.
/// Both are facts of the workload, supplied by the caller; the model never
/// assumes one dominates the other.
pub const Profile = struct {
    accesses: u64,
    crossings: u64,
};

/// Per-mechanism cost, as two cycle-scale ORDER facts. The ORDERING is the
/// law — `none` beats software beats hardware-domain beats boundary — and
/// each magnitude is the current estimate of that order's scale, replaced by
/// measurement when a target exists to measure (`law` §14: unmeasured is
/// stated, never dressed up).
pub const Cost = struct {
    /// Cost per enforced access.
    access: u64,
    /// Cost per authority-domain crossing.
    crossing: u64,

    pub fn total(self: Cost, profile: Profile) u64 {
        return self.access *| profile.accesses +| self.crossing *| profile.crossings;
    }
};

/// The cost relation — one arm per mechanism, stated beside the mechanism's
/// `world.enforces` arm so the two facts about one mechanism are reviewed
/// together.
pub fn costOf(m: Mechanism) Cost {
    return switch (m) {
        .none => .{ .access = 0, .crossing = 0 },
        // A compare and a predictable branch per access.
        .software_check => .{ .access = 2, .crossing = 0 },
        // The bounds compare is folded into the access by hardware.
        .bounds => .{ .access = 1, .crossing = 0 },
        // In-domain access is unchecked; the domain switch is a
        // permission-register write (~tens of cycles).
        .mpk => .{ .access = 0, .crossing = 32 },
        // Tag, bounds and permissions are checked in hardware per access;
        // construction is a handful of instructions per crossing.
        .cheri => .{ .access = 0, .crossing = 4 },
        // In-domain access is free; the crossing is syscall + context
        // switch + marshalling (~thousands of cycles).
        .process => .{ .access = 0, .crossing = 2048 },
        // A bounds check (or guard-page fault path) per access and a
        // trampoline per crossing.
        .wasm_sandbox => .{ .access = 1, .crossing = 8 },
        // The crossing is a transport round trip (~tens of thousands of
        // cycles and up).
        .network_isolation => .{ .access = 0, .crossing = 65536 },
    };
}

/// The physical unit a cost is stated in. The stated relation (`costOf`)
/// speaks in cycle-scale ORDERS; a measurement names its own unit, and two
/// costs are comparable only within one unit — a measured nanosecond never
/// settles a comparison against a stated cycle estimate.
pub const CostUnit = enum {
    /// The stated relation's own scale: cycle-scale orders.
    cycle_order,
    /// Measured wall-clock nanoseconds per event on the named target.
    nanoseconds,

    pub fn name(self: CostUnit) []const u8 {
        return switch (self) {
            .cycle_order => "cycle_order",
            .nanoseconds => "nanoseconds",
        };
    }
};

/// A MEASURED per-mechanism cost — the replacement for `costOf`'s stated
/// order once a target exists to measure the mechanism on. The fact names
/// the mechanism, the target triple it was measured on, the unit the numbers
/// are in, and the exact measured subject revision
/// (`law.evidence.subject.one`): a measurement that cannot name what was
/// measured constructs NO fact.
pub const MeasuredCost = struct {
    mechanism: Mechanism,
    triple: target_model.TargetTriple,
    unit: CostUnit,
    cost: Cost,
    /// The subject revision the measurement ran against (a git commit id).
    /// Empty means the measurement names no subject — no fact.
    subject_revision: []const u8,
};

/// The unique measured fact naming one mechanism on one target triple, or
/// none. Two matching rows construct no fact: accepting the first would make
/// transport order a shadow authority over cost (`law.fact.producer.one`).
/// A measurement with no subject revision constructs no fact
/// (`law.evidence.subject.one`), and a measurement on another triple is a
/// fact about THAT target, not this one.
pub fn measurementOf(m: Mechanism, triple: target_model.TargetTriple, measured: []const MeasuredCost) ?MeasuredCost {
    var found: ?MeasuredCost = null;
    for (measured) |fact| {
        if (fact.subject_revision.len == 0) continue;
        if (fact.mechanism != m or !std.meta.eql(fact.triple, triple)) continue;
        if (found != null) return null;
        found = fact;
    }
    return found;
}

/// The uniform-measurement rule: measured costs decide a comparison ONLY
/// when every candidate was measured on the target in one shared unit and at
/// one shared subject revision. A partial measurement, a foreign-triple
/// measurement, mixed units, or mixed subjects leave the stated orders to
/// decide — the rule returns the shared unit when the whole comparison is one
/// measurement subject, null otherwise.
fn uniformMeasurement(triple: target_model.TargetTriple, candidates: []const Dynamic, measured: []const MeasuredCost) ?CostUnit {
    if (candidates.len == 0) return null;
    var unit: ?CostUnit = null;
    var subject_revision: ?[]const u8 = null;
    for (candidates) |c| {
        const fact = measurementOf(c.mechanism, triple, measured) orelse return null;
        if (unit) |u| {
            if (fact.unit != u) return null;
        } else {
            unit = fact.unit;
        }
        if (subject_revision) |revision| {
            if (!std.mem.eql(u8, fact.subject_revision, revision)) return null;
        } else {
            subject_revision = fact.subject_revision;
        }
    }
    return unit;
}

/// The provenance seam: one `idol.world.cost.v1` row — exactly what
/// `gate/lower/cost.sh` emits on stdout — parsed into the `MeasuredCost`
/// fact `selectMeasured` consumes. This is the ONLY producer of a measured
/// fact from the measured world (`law.fact.producer.one`): the runner
/// measures, the row carries the measurement across the seam, and this
/// parser reconstructs the typed fact — no host projection reads the numbers
/// a second time.
///
/// It FAILS CLOSED. A row constructs a fact only when every field the fact
/// names is present and identifies a known value: the schema is
/// `idol.world.cost.v1`, the mechanism/arch/os/abi/unit each parse to a
/// known identity, the cost carries both `access` and `crossing`, and the
/// subject revision is NON-EMPTY (`law.evidence.subject.one`: a measurement
/// that cannot name what was measured is not a fact). Anything else returns
/// null — a malformed or unowned row leaves the stated orders to decide,
/// exactly as an absent measurement does. A negative float cost is the
/// producer's documented noise floor and reconstructs as zero (`u64Field`),
/// while an unrepresentable magnitude is no fact. A `network_isolation` mechanism is
/// read from the row's own spelling, never reconstructed from an ordinal
/// (`law.magic.code.zero`).
///
/// The measured subject revision is COPIED into `revision` so the fact does
/// not borrow the transient row buffer; the caller owns `revision` for the
/// fact's lifetime. A revision that does not fit the buffer is no fact.
pub fn parseMeasured(text: []const u8, revision: []u8) ?MeasuredCost {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, text, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    const schema = stringField(obj, "schema") orelse return null;
    if (!std.mem.eql(u8, schema, "idol.world.cost.v1")) return null;

    const mechanism = mechanismByName(stringField(obj, "mechanism") orelse return null) orelse return null;

    const triple_text = stringField(obj, "triple") orelse return null;
    const triple = parseTriple(triple_text) orelse return null;

    const unit = unitByName(stringField(obj, "unit") orelse return null) orelse return null;

    const cost_value = obj.get("cost") orelse return null;
    if (cost_value != .object) return null;
    const cost_obj = cost_value.object;
    const access = u64Field(cost_obj, "access") orelse return null;
    const crossing = u64Field(cost_obj, "crossing") orelse return null;

    // `law.evidence.subject.one`: no subject, no fact.
    const rev = stringField(obj, "subject_revision") orelse return null;
    if (rev.len == 0) return null;
    if (rev.len > revision.len) return null;
    @memcpy(revision[0..rev.len], rev);

    return .{
        .mechanism = mechanism,
        .triple = triple,
        .unit = unit,
        .cost = .{ .access = access, .crossing = crossing },
        .subject_revision = revision[0..rev.len],
    };
}

/// An owned set of measured cost facts reconstructed from the newline-delimited
/// evidence emitted by `gate/lower/cost.sh`. Each revision remains separately
/// owned because it is part of the measured subject identity, not row transport.
pub const ParsedMeasurements = struct {
    facts: std.ArrayListUnmanaged(MeasuredCost) = .empty,

    pub fn deinit(self: *ParsedMeasurements, alloc: std.mem.Allocator) void {
        for (self.facts.items) |fact| alloc.free(fact.subject_revision);
        self.facts.deinit(alloc);
        self.* = .{};
    }
};

/// Parse the complete cost-evidence stream through `parseMeasured`, the single
/// row-to-fact producer. Blank lines carry no fact; any nonblank invalid row
/// refuses the stream so a partially transported measurement cannot decide a
/// realization comparison.
pub fn parseMeasurements(alloc: std.mem.Allocator, text: []const u8) !?ParsedMeasurements {
    var parsed: ParsedMeasurements = .{};
    errdefer parsed.deinit(alloc);

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;

        var revision: [128]u8 = undefined;
        var fact = parseMeasured(line, &revision) orelse {
            parsed.deinit(alloc);
            return null;
        };
        fact.subject_revision = try alloc.dupe(u8, fact.subject_revision);
        errdefer alloc.free(fact.subject_revision);
        try parsed.facts.append(alloc, fact);
    }
    return parsed;
}

fn stringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

/// A cost quantity from a row field. The producer emits computed costs as
/// `%.4f` floats, so whole measured nanoseconds arrive as floats and truncate
/// toward zero. A NEGATIVE float is the producer's documented timer noise
/// around no measurable cost (`gate/lower/cost.sh` reports the software-check
/// enforcement delta even when noise makes it negative): a cost is a physical
/// quantity, so the noise floor reconstructs as zero — refusing a genuine row
/// would make the producer's own output intermittently unconsumable, and a
/// negative quantity must never settle a comparison. An unrepresentable
/// magnitude is no fact: fail closed, never a trapping conversion.
fn u64Field(obj: std.json.ObjectMap, key: []const u8) ?u64 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .integer => |n| if (n < 0) null else @as(u64, @intCast(n)),
        .float => |f| if (f < 0)
            0
        else if (f >= @as(f64, @floatFromInt(std.math.maxInt(u64))))
            null
        else
            @as(u64, @intFromFloat(f)),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}

/// The mechanism identity from its own name — the same spelling `Mechanism.name`
/// emits, read back. Never an ordinal (`law.magic.code.zero`).
fn mechanismByName(text: []const u8) ?Mechanism {
    for (std.meta.tags(Mechanism)) |m| {
        if (std.mem.eql(u8, m.name(), text)) return m;
    }
    return null;
}

fn unitByName(text: []const u8) ?CostUnit {
    for (std.meta.tags(CostUnit)) |u| {
        if (std.mem.eql(u8, u.name(), text)) return u;
    }
    return null;
}

/// The target triple from `arch-os-abi` (the runner's own `formatTriple`
/// spelling). Two components mean an unknown abi; the fact then names a triple
/// with no abi, which `formatTriple` and `TargetWorld` already model.
fn parseTriple(text: []const u8) ?target_model.TargetTriple {
    var it = std.mem.splitScalar(u8, text, '-');
    const arch = target_model.Arch.parse(it.next() orelse return null) orelse return null;
    const os = target_model.Os.parse(it.next() orelse return null) orelse return null;
    const abi_text = it.next() orelse return .{ .arch = arch, .os = os, .abi = .unknown };
    const abi = target_model.Abi.parse(abi_text) orelse return null;
    if (it.next() != null) return null;
    return .{ .arch = arch, .os = os, .abi = abi };
}

// ===========================================================================
// CHERI construction, derived from semantic authority facts
// ===========================================================================

pub const Permission = enum {
    load,
    store,
};

/// A capability construction — the physical counterpart of one authority
/// bundle, derived, never hand-written. This is a physical fact record, not
/// a semantic kind: no `CapabilityObject` enters the graph (GAP-185's
/// semantic invariant).
pub const Capability = struct {
    /// Bounds, from the subject's extent fact. A bounded extent constructs
    /// to its upper bound; an unknown extent refuses construction entirely.
    extent: u32,
    permissions: std.EnumSet(Permission),
    /// A unique subject has no second holder, so the capability is sealed at
    /// construction: no further derivation can widen it.
    sealed: bool,
    /// A nonescape subject's capability never leaves its region, so the
    /// global bit is clear and it may not be retained beyond it.
    global: bool,
};

/// Derive the capability an authority bundle constructs to, or refuse: a
/// capability whose bounds are not statically known is not constructible
/// here, and a mechanism that cannot be constructed is not a realization.
pub fn capabilityOf(auth: world.Authority) ?Capability {
    const extent = switch (auth.extent) {
        .exact => |n| n,
        .bounded => |n| n,
        .unknown => return null,
    };
    var permissions: std.EnumSet(Permission) = .{};
    permissions.insert(.load);
    if (auth.readonly != .yes) permissions.insert(.store);
    return .{
        .extent = extent,
        .permissions = permissions,
        .sealed = auth.unique == .yes,
        .global = auth.nonescape != .yes,
    };
}

// ===========================================================================
// Selection
// ===========================================================================

/// Why no plan exists. Named outcomes, never a bare false.
pub const Refusal = enum {
    /// No admitted mechanism enforces every demanded property.
    no_admissible_mechanism,

    pub fn name(self: Refusal) []const u8 {
        return switch (self) {
            .no_admissible_mechanism => "no_admissible_mechanism",
        };
    }
};

/// A selected dynamic enforcement, with the demand it answers and the cost
/// under which it won — `law.cost.explain`: the plan explains itself.
pub const Dynamic = struct {
    mechanism: Mechanism,
    demanded: PropertySet,
    cost: Cost,
    /// The unit `cost` is stated in — `cycle_order` for the stated relation,
    /// the measured unit when a uniform measurement decided.
    unit: CostUnit = .cycle_order,
    /// The derived construction when the mechanism is `.cheri`.
    capability: ?Capability,
};

/// The realization plan. The case IS the witness: `static` carries the
/// authority facts that discharge every demanded property; `dynamic` carries
/// the mechanism and its cost.
pub const Plan = union(enum) {
    /// Zero dynamic enforcement — statically witnessed authority.
    static: world.Authority,
    dynamic: Dynamic,
};

pub const Selection = union(enum) {
    plan: Plan,
    refused: Refusal,
};

/// Select the cheapest enforcement of `auth` that preserves every property
/// the attack model demands, on the mechanisms the target world admits,
/// under the given demand profile.
///
/// Ties resolve to the EARLIER candidate in the `Mechanism` index — the
/// weakest sufficient enforcement — which is deterministic and is the least
/// authority consistent with the demand. A NULL profile is not a small one:
/// it is the absence of workload facts, so every admissible candidate ties on
/// cost and the weakest sufficient mechanism is the whole answer, with no
/// cost claim attached.
///
/// This is the stated-order face: costs come from `costOf`. `selectMeasured`
/// is the same selection under measured cost facts.
pub fn select(
    auth: world.Authority,
    attack: observation.World,
    target: world.TargetWorld,
    profile: ?Profile,
) Selection {
    return selectMeasured(auth, attack, target, profile, &.{});
}

/// Selection under measured cost facts. `measured` facts decide ONLY a
/// uniform comparison — every admissible candidate measured on this target
/// in one unit (`uniformMeasurement`); anything less leaves the stated
/// orders to decide, and a measured fact never mixes with a stated estimate
/// in one comparison.
pub fn selectMeasured(
    auth: world.Authority,
    attack: observation.World,
    target: world.TargetWorld,
    profile: ?Profile,
    measured: []const MeasuredCost,
) Selection {
    const demanded = world.demandOf(attack, auth);
    // The static rung's proof quantifies over the program's own accesses; a
    // `foreign_boundary` world carries in-image code that can forge pointers,
    // so zero enforcement is not admissible there (`world.enforces`' ruling).
    if (!attack.has(.foreign_boundary) and auth.fixedAgainst(demanded)) return .{ .plan = .{ .static = auth } };
    var candidates: [Mechanism.count]Dynamic = undefined;
    var n: usize = 0;
    for (std.meta.tags(Mechanism)) |m| {
        if (!target.admits(m)) continue;
        if (!world.enforces(m, attack).supersetOf(demanded)) continue;
        // A capability that cannot be constructed statically is not a
        // realization: derivability is an admissibility condition.
        const capability: ?Capability = if (m == .cheri) capabilityOf(auth) else null;
        if (m == .cheri and capability == null) continue;
        candidates[n] = .{
            .mechanism = m,
            .demanded = demanded,
            .cost = costOf(m),
            .capability = capability,
        };
        n += 1;
    }
    if (n == 0) return .{ .refused = .no_admissible_mechanism };
    // The tie rule, applied: with no workload facts every admissible
    // candidate ties, so the first one in index order is the answer.
    if (profile == null) return .{ .plan = .{ .dynamic = candidates[0] } };
    // A uniform measurement replaces the stated orders for every candidate
    // at once, so the comparison below never mixes units.
    if (uniformMeasurement(target.triple, candidates[0..n], measured)) |unit| {
        for (candidates[0..n]) |*c| {
            c.cost = measurementOf(c.mechanism, target.triple, measured).?.cost;
            c.unit = unit;
        }
    }
    var best = candidates[0];
    for (candidates[1..n]) |candidate| {
        if (candidate.cost.total(profile.?) < best.cost.total(profile.?)) best = candidate;
    }
    return .{ .plan = .{ .dynamic = best } };
}

// ===========================================================================
// The graph wiring — one census place IS one authority subject
// ===========================================================================

/// THE graph-facing consumer: a row of the place census the graph carries
/// (`SemanticGraph.places` IS a `place.Census`) is one authority subject, and
/// this is where those facts reach selection — through the census the graph
/// already produces, never through a second AST walk or a host projection
/// (`law.fact.producer.one`). The authority projection itself stays in
/// `world.Authority.of`; nothing here re-inverts `alias` or `escape`.
///
/// The workload profile is derived, not assumed: enforced ACCESSES are the
/// census's own read/write counts weighted by their recorded multiplicities.
/// CROSSINGS are a composition fact — which authority domains the realized
/// program crosses — and one place's census does not carry them, so the
/// caller supplies them. An UNKNOWN multiplicity is an unknown workload,
/// never a small one (`place.Mult.upperOrNull`): selection then carries no
/// cost claim and `select`'s tie rule decides.
pub fn selectPlace(
    p: *const place.Place,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
) Selection {
    return selectPlaceMeasured(p, attack, target, crossings, &.{});
}

/// `selectPlace` under measured cost facts — the same census-row selection,
/// with `measured` threaded into `selectMeasured` so a uniform measurement of
/// every admissible candidate on this target decides the row's cost instead of
/// `costOf`'s stated orders. The workload profile is derived exactly as in
/// `selectPlace`: enforced accesses are the census's own read/write counts.
pub fn selectPlaceMeasured(
    p: *const place.Place,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
    measured: []const MeasuredCost,
) Selection {
    const reads = p.readCount().upperOrNull();
    const writes = p.writeCount().upperOrNull();
    const profile: ?Profile = if (reads != null and writes != null)
        Profile{ .accesses = reads.? +| writes.?, .crossings = crossings }
    else
        null;
    return selectMeasured(world.Authority.of(p.facts), attack, target, profile, measured);
}

/// THE backend realization walk's answer over one module census: every census
/// place selected, counted by rung — or the first place with no admissible
/// enforcement, named, so realization fails closed on the place rather than
/// weakening its demand.
pub const CensusSelection = union(enum) {
    /// Every census place selected, counted by rung.
    realized: Realized,
    /// The first census place with no admissible enforcement.
    refused: PlaceRefusal,

    pub const Realized = struct {
        /// Census places the walk selected over — the census size, exactly,
        /// so the walk's completeness is a measured fact rather than a loop
        /// invariant asserted but never observed.
        places: usize,
        /// Places whose authority is statically witnessed: the zero-cost rung.
        static_plans: usize,
        /// Places committed to a dynamic mechanism.
        dynamic_plans: usize,
    };

    pub const PlaceRefusal = struct {
        /// The census place's own name — the subject identity, borrowed from
        /// the census and sharing its lifetime.
        place: []const u8,
        refusal: Refusal,
    };
};

/// THE backend consumer (GAP-185): ONE call per realization walks the census
/// the graph carries and selects per place — `selectPlace` applied to every
/// census row, never a second census and never a host projection
/// (`law.fact.producer.one`). The graph-backed C99 realization arm in
/// `main.zig` calls this between the graph lift and graph-to-DNIR lowering;
/// other backends consume the same walk when their boundary comes.
pub fn selectModule(
    census: *const place.Census,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
) CensusSelection {
    return selectModuleMeasured(census, attack, target, crossings, &.{});
}

/// `selectModule` under measured cost facts — the same realization walk over
/// every census row, with `measured` threaded into each place's selection so a
/// uniform measurement of the target decides the walk's per-place costs. The
/// existing `selectModule` remains the empty-measurement face.
pub fn selectModuleMeasured(
    census: *const place.Census,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
    measured: []const MeasuredCost,
) CensusSelection {
    var realized: CensusSelection.Realized = .{ .places = 0, .static_plans = 0, .dynamic_plans = 0 };
    for (census.places.items) |*p| {
        switch (selectPlaceMeasured(p, attack, target, crossings, measured)) {
            .plan => |plan| {
                realized.places += 1;
                switch (plan) {
                    .static => realized.static_plans += 1,
                    .dynamic => realized.dynamic_plans += 1,
                }
            },
            .refused => |r| return .{ .refused = .{ .place = p.name, .refusal = r } },
        }
    }
    return .{ .realized = realized };
}

/// The per-place plans as a name-keyed set: every census place whose
/// authority is statically fixed — the zero-cost rung — is a member.
/// `dnir_lower` consumes this to elide the enforcement it would otherwise
/// emit per place: when the plan is static, the compiler's own proof
/// covers spatial safety and no runtime check is needed.
///
/// Returned as a `StringHashMapUnmanaged(void)` so the caller (the graph)
/// owns the set and `dnir_lower` reads it through `graph.static_places`.
/// Null when any place refused (the caller checks `selectModule` first).
pub fn collectStaticPlaces(
    alloc: std.mem.Allocator,
    census: *const place.Census,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
) ?std.StringHashMapUnmanaged(void) {
    return collectStaticPlacesMeasured(alloc, census, attack, target, crossings, &.{});
}

/// `collectStaticPlaces` under measured cost facts — the same name-keyed set
/// of statically witnessed places, with `measured` threaded into each place's
/// selection. Measured facts never manufacture a static witness: the static
/// rung is decided by the authority proof alone, so a measurement can only
/// change which DYNAMIC mechanism a non-static place selects.
pub fn collectStaticPlacesMeasured(
    alloc: std.mem.Allocator,
    census: *const place.Census,
    attack: observation.World,
    target: world.TargetWorld,
    crossings: u64,
    measured: []const MeasuredCost,
) ?std.StringHashMapUnmanaged(void) {
    var set: std.StringHashMapUnmanaged(void) = .empty;
    for (census.places.items) |*p| {
        switch (selectPlaceMeasured(p, attack, target, crossings, measured)) {
            .plan => |plan| switch (plan) {
                .static => set.put(alloc, p.name, {}) catch {
                    set.deinit(alloc);
                    return null;
                },
                .dynamic => {},
            },
            .refused => {
                set.deinit(alloc);
                return null;
            },
        }
    }
    return set;
}

/// The selection record as structured evidence — names, never ordinals
/// (`law.magic.code.zero`). Revision and subject identity belong to the
/// caller's evidence envelope (`law.evidence.subject.one`); this is the
/// decision content only.
pub fn writeJson(w: *std.Io.Writer, selection: Selection) !void {
    try w.writeAll("{\"schema\":\"idol.world.enforcement.v1\"");
    switch (selection) {
        .refused => |r| try w.print(",\"outcome\":\"refused\",\"refusal\":\"{s}\"", .{r.name()}),
        .plan => |plan| switch (plan) {
            .static => try w.writeAll(",\"outcome\":\"plan\",\"mechanism\":\"none\",\"cost\":{\"access\":0,\"crossing\":0}"),
            .dynamic => |d| {
                try w.print(",\"outcome\":\"plan\",\"mechanism\":\"{s}\"", .{d.mechanism.name()});
                try w.writeAll(",\"demanded\":[");
                var first = true;
                for (std.meta.tags(world.Property)) |p| {
                    if (!d.demanded.contains(p)) continue;
                    if (!first) try w.writeAll(",");
                    try w.print("\"{s}\"", .{p.name()});
                    first = false;
                }
                try w.writeAll("]");
                try w.print(",\"cost\":{{\"access\":{},\"crossing\":{},\"unit\":\"{s}\"}}", .{ d.cost.access, d.cost.crossing, d.unit.name() });
                if (d.capability) |cap| {
                    try w.print(",\"capability\":{{\"extent\":{},\"sealed\":{},\"global\":{},\"permissions\":[", .{ cap.extent, cap.sealed, cap.global });
                    var pfirst = true;
                    for (std.meta.tags(Permission)) |permission| {
                        if (!cap.permissions.contains(permission)) continue;
                        if (!pfirst) try w.writeAll(",");
                        try w.print("\"{s}\"", .{@tagName(permission)});
                        pfirst = false;
                    }
                    try w.writeAll("]}");
                }
            },
        },
    }
    try w.writeAll("}");
}

// ===========================================================================
// Tests
// ===========================================================================

fn fixedAuthority() world.Authority {
    return world.Authority.of(.{
        .alias = .no,
        .escape = .no,
        .immutability = .yes,
        .determinacy = .exact,
        .extent = .{ .exact = 64 },
    });
}

fn exposedAuthority() world.Authority {
    // Escapes and aliases: no static discharge, extent exact.
    return world.Authority.of(.{
        .alias = .yes,
        .escape = .yes,
        .immutability = .yes,
        .determinacy = .unknown,
        .extent = .{ .exact = 64 },
    });
}

test "lower: statically fixed authority realizes at zero cost" {
    const target = world.TargetWorld.of(.{ .arch = .aarch64, .os = .macos, .abi = .gnu });
    const selection = select(fixedAuthority(), observation.ordinary_executable, target, .{ .accesses = 1000, .crossings = 100 });
    const plan = selection.plan;
    const witness = plan.static;
    try std.testing.expectEqual(world.Tri.yes, witness.unique);
    try std.testing.expectEqual(world.Tri.yes, witness.nonescape);
    // Zero overhead, by construction: there is no dynamic enforcement.
}

test "lower: an adversary defeats the static rung" {
    const target = world.TargetWorld.of(.{ .arch = .aarch64, .os = .macos, .abi = .gnu });
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const selection = select(fixedAuthority(), hostile, target, .{ .accesses = 10, .crossings = 1 });
    // Statically fixed facts cannot discharge confidentiality or timing, so
    // a mechanism is selected even though every local fact is proven.
    try std.testing.expectEqual(Mechanism.process, selection.plan.dynamic.mechanism);
}

test "lower: one authority, different enforcement on different targets" {
    // GAP-185's evidence shape: the SAME authority bundle selects different
    // enforcement per target world, with the model cost recorded on each.
    const auth = exposedAuthority();
    const attack = observation.ordinary_executable.with(.security_adversary);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };

    const linux = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const on_linux = select(auth, attack, linux, profile).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, on_linux.mechanism);
    try std.testing.expectEqual(@as(u64, 320), on_linux.cost.total(profile));

    const macos = world.TargetWorld.of(.{ .arch = .aarch64, .os = .macos, .abi = .gnu });
    const on_macos = select(auth, attack, macos, profile).plan.dynamic;
    try std.testing.expectEqual(Mechanism.process, on_macos.mechanism);
    try std.testing.expectEqual(@as(u64, 20480), on_macos.cost.total(profile));

    // The authority did not change; the target world did.
    try std.testing.expect(on_linux.cost.total(profile) != on_macos.cost.total(profile));
}

test "lower: the cost model is a relation, not a priority list" {
    // MPK wins when crossings are rare relative to accesses; a software
    // check wins when crossings dominate. The mechanism choice flips on the
    // PROFILE, which is what makes this a cost model.
    const auth = exposedAuthority();
    const attack = observation.ordinary_executable; // spatial + immutability only
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });

    const hot_access = select(auth, attack, target, .{ .accesses = 1000, .crossings = 1 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, hot_access.mechanism);
    // software_check: 2*1000 = 2000; mpk: 32. mpk is cheaper.
    try std.testing.expectEqual(@as(u64, 32), hot_access.cost.total(.{ .accesses = 1000, .crossings = 1 }));

    const hot_crossing = select(auth, attack, target, .{ .accesses = 4, .crossings = 1000 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.software_check, hot_crossing.mechanism);
    // software_check: 8; mpk: 32000. The branch is cheaper.
    try std.testing.expectEqual(@as(u64, 8), hot_crossing.cost.total(.{ .accesses = 4, .crossings = 1000 }));
}

// ===========================================================================
// The measured-cost face — measured facts decide only a uniform comparison
// ===========================================================================

/// The measured-cost fixture's target and subject: one triple, one revision,
/// four facts covering every mechanism the target admits for the fixture's
/// demand (software_check, mpk, process, network_isolation).
const measured_triple: target_model.TargetTriple = .{ .arch = .x86_64, .os = .linux, .abi = .gnu };
const measured_revision = "9f62a9dcf0000000000000000000000000000001";

fn measuredSet(unit: CostUnit) [4]MeasuredCost {
    return .{
        .{ .mechanism = .software_check, .triple = measured_triple, .unit = unit, .cost = .{ .access = 1, .crossing = 0 }, .subject_revision = measured_revision },
        .{ .mechanism = .mpk, .triple = measured_triple, .unit = unit, .cost = .{ .access = 0, .crossing = 900 }, .subject_revision = measured_revision },
        .{ .mechanism = .process, .triple = measured_triple, .unit = unit, .cost = .{ .access = 0, .crossing = 3000 }, .subject_revision = measured_revision },
        .{ .mechanism = .network_isolation, .triple = measured_triple, .unit = unit, .cost = .{ .access = 0, .crossing = 100000 }, .subject_revision = measured_revision },
    };
}

test "lower: a uniform measurement replaces the stated orders and can flip the winner" {
    // The stated relation's answer on this target is MPK (320 under the
    // profile). The measured facts say the software check's enforced access
    // is one nanosecond and every boundary crossing costs hundreds more, so
    // under measurement the same authority, demand and profile select the
    // software check — the measurement, not the estimate, decides.
    const auth = exposedAuthority();
    const attack = observation.ordinary_executable;
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };

    const stated = select(auth, attack, target, profile).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, stated.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, stated.unit);

    const measured = measuredSet(.nanoseconds);
    const plan = selectMeasured(auth, attack, target, profile, &measured).plan.dynamic;
    try std.testing.expectEqual(Mechanism.software_check, plan.mechanism);
    try std.testing.expectEqual(CostUnit.nanoseconds, plan.unit);
    // 1ns * 1000 accesses: the measured total, not the stated 2*1000.
    try std.testing.expectEqual(@as(u64, 1000), plan.cost.total(profile));
}

test "lower: a partial measurement leaves the stated orders to decide" {
    // Only the software check was measured; MPK, process and network carry
    // stated estimates. A measured nanosecond never settles a comparison
    // against a stated cycle estimate, so the stated relation decides and
    // MPK wins exactly as without the measurement.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    const partial = [_]MeasuredCost{measuredSet(.nanoseconds)[0]};
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &partial).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: a measurement on another target constructs no fact here" {
    // All four facts are present but name aarch64-macos; the selection's
    // target is x86_64-linux. A measurement is a fact about the target it
    // was measured ON, so nothing is measured here and the stated orders
    // decide.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    var foreign = measuredSet(.nanoseconds);
    const macos: target_model.TargetTriple = .{ .arch = .aarch64, .os = .macos, .abi = .gnu };
    for (&foreign) |*fact| fact.triple = macos;
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &foreign).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: mixed units are not a comparison" {
    // Three facts in nanoseconds and one in cycle-scale orders is not a
    // uniform measurement; the stated relation decides for all four.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    var mixed = measuredSet(.nanoseconds);
    mixed[2].unit = .cycle_order;
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &mixed).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: mixed subject revisions are not a comparison" {
    // Rows measured against different program revisions are facts about
    // different subjects. Combining them would construct a synthetic cost
    // comparison that no producer measured, so stated orders decide for all
    // candidates instead.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    var mixed = measuredSet(.nanoseconds);
    mixed[2].subject_revision = "7a310e7f00000000000000000000000000000002";
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &mixed).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: a measurement without a subject revision constructs no fact" {
    // `law.evidence.subject.one`: a measurement that cannot name what was
    // measured is not a fact. All four facts present, all revisions empty —
    // the stated orders decide.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    var unowned = measuredSet(.nanoseconds);
    for (&unowned) |*fact| fact.subject_revision = "";
    try std.testing.expectEqual(@as(?MeasuredCost, null), measurementOf(.software_check, measured_triple, &unowned));
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &unowned).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: duplicate measurements construct no cost fact" {
    // A mechanism and target have one cost-fact producer. Even identical
    // duplicate rows are ambiguous provenance; slice order must never choose
    // which producer owns the fact, so the whole comparison stays stated.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    const measured = measuredSet(.nanoseconds);
    const duplicate = measured ++ [1]MeasuredCost{measured[0]};

    try std.testing.expectEqual(@as(?MeasuredCost, null), measurementOf(.software_check, measured_triple, &duplicate));
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &duplicate).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, plan.unit);
}

test "lower: a cost row parses into the measured fact it names" {
    // The exact shape `gate/lower/cost.sh` emits for the software check on
    // this host: schema, mechanism, triple, unit, cost and subject revision.
    // The parser reconstructs the typed fact — the one producer of a measured
    // fact from the measured world — with no field guessed and no host reread.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":3,"crossing":0},"subject_revision":"c0adff39aabbccddeeff00112233445566778899","checked_access_ns":5.0,"plain_access_ns":2.0,"accesses_per_rep":4194304,"reps":9}
    ;
    var rev: [64]u8 = undefined;
    const fact = parseMeasured(text, &rev).?;
    try std.testing.expectEqual(Mechanism.software_check, fact.mechanism);
    try std.testing.expectEqual(target_model.Arch.x86_64, fact.triple.arch);
    try std.testing.expectEqual(target_model.Os.linux, fact.triple.os);
    try std.testing.expectEqual(target_model.Abi.gnu, fact.triple.abi);
    try std.testing.expectEqual(CostUnit.nanoseconds, fact.unit);
    try std.testing.expectEqual(@as(u64, 3), fact.cost.access);
    try std.testing.expectEqual(@as(u64, 0), fact.cost.crossing);
    try std.testing.expectEqualStrings("c0adff39aabbccddeeff00112233445566778899", fact.subject_revision);
}

test "lower: a boundary crossing row parses its crossing cost" {
    // The process row carries its measurement in `cost.crossing`, `access`
    // zero — the same schema, a different mechanism and cost face.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"process","triple":"aarch64-macos-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":1800},"subject_revision":"deadbeef00000000000000000000000000000001"}
    ;
    var rev: [64]u8 = undefined;
    const fact = parseMeasured(text, &rev).?;
    try std.testing.expectEqual(Mechanism.process, fact.mechanism);
    try std.testing.expectEqual(@as(u64, 0), fact.cost.access);
    try std.testing.expectEqual(@as(u64, 1800), fact.cost.crossing);
}

test "lower: a row with no subject revision constructs no fact" {
    // `law.evidence.subject.one` at the seam: a measurement that names no
    // subject is not a fact, so the parser refuses it exactly as an empty
    // `subject_revision` field on a struct fact does.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":3,"crossing":0},"subject_revision":""}
    ;
    var rev: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured(text, &rev));
}

test "lower: a foreign schema is not a cost fact" {
    // The seam admits exactly `idol.world.cost.v1`. A row carrying every
    // cost field under a different schema is a fact about something else and
    // constructs no measured cost here (`law.fact.producer.one`).
    const text =
        \\{"schema":"idol.world.enforcement.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":3,"crossing":0},"subject_revision":"c0adff3900000000000000000000000000000001"}
    ;
    var rev: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured(text, &rev));
}

test "lower: an unknown mechanism name is not a cost fact" {
    // The mechanism crosses the seam as its stable identity spelling, read
    // back by name (`law.magic.code.zero`). A name no mechanism owns is not a
    // fact, never a defaulted or ordinal-reconstructed one.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"quantum_moat","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":1,"crossing":0},"subject_revision":"c0adff3900000000000000000000000000000001"}
    ;
    var rev: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured(text, &rev));
}

test "lower: a malformed row is not a cost fact" {
    // Truncated JSON, a missing cost field, and a non-object body all fail
    // closed — a row that is not a complete, well-formed cost fact leaves the
    // stated orders to decide, exactly as an absent measurement does.
    var rev: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured("{not json", &rev));
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured("\"a string\"", &rev));
    const no_cost =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","subject_revision":"c0adff3900000000000000000000000000000001"}
    ;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured(no_cost, &rev));
}

test "lower: a producer float cost parses by truncation" {
    // The producer emits computed costs as `%.4f` floats — whole measured
    // nanoseconds arrive as floats, never as the integers the earlier parse
    // tests use. Truncation toward zero is the reconstruction.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"aarch64-linux-gnu","unit":"nanoseconds","cost":{"access":2.8437,"crossing":0},"subject_revision":"5acc89730000000000000000000000000000000001","checked_access_ns":12.5,"plain_access_ns":9.6562,"accesses_per_rep":4194304,"reps":9}
    ;
    var rev: [64]u8 = undefined;
    const fact = parseMeasured(text, &rev).?;
    try std.testing.expectEqual(@as(u64, 2), fact.cost.access);
    try std.testing.expectEqual(@as(u64, 0), fact.cost.crossing);
}

test "lower: a negative noise delta reconstructs as zero cost, not refusal" {
    // `gate/lower/cost.sh` reports the enforcement delta even when timer
    // noise makes it negative. A cost is a physical quantity: the noise floor
    // reconstructs as zero, so a genuine producer row always constructs its
    // fact instead of refusing the stream.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"aarch64-linux-gnu","unit":"nanoseconds","cost":{"access":-0.0312,"crossing":0},"subject_revision":"5acc89730000000000000000000000000000000001","checked_access_ns":9.625,"plain_access_ns":9.6562,"accesses_per_rep":1024,"reps":2}
    ;
    var rev: [64]u8 = undefined;
    const fact = parseMeasured(text, &rev).?;
    try std.testing.expectEqual(@as(u64, 0), fact.cost.access);
}

test "lower: an unrepresentable float cost is not a cost fact" {
    // Fail closed, never a trapping conversion: a magnitude no u64 holds
    // constructs no fact.
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"process","triple":"aarch64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":1e30},"subject_revision":"5acc89730000000000000000000000000000000001"}
    ;
    var rev: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?MeasuredCost, null), parseMeasured(text, &rev));
}

test "lower: parseMeasurements keeps a noise-floor producer stream" {
    // The regression pin: a complete producer stream whose software row went
    // negative under noise is complete evidence, not a partial stream.
    const alloc = std.testing.allocator;
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"aarch64-linux-gnu","unit":"nanoseconds","cost":{"access":-0.0312,"crossing":0},"subject_revision":"5acc89730000000000000000000000000000000001","checked_access_ns":9.625,"plain_access_ns":9.6562,"accesses_per_rep":1024,"reps":2}
        \\{"schema":"idol.world.cost.v1","mechanism":"process","triple":"aarch64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":1800.25},"subject_revision":"5acc89730000000000000000000000000000000001","roundtrips_per_rep":16,"reps":2}
    ;
    var parsed = (try parseMeasurements(alloc, text)).?;
    defer parsed.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), parsed.facts.items.len);
    try std.testing.expectEqual(@as(u64, 0), parsed.facts.items[0].cost.access);
    try std.testing.expectEqual(@as(u64, 1800), parsed.facts.items[1].cost.crossing);
}

test "lower: a parsed row feeds the same selection the struct fact does" {
    // The seam is transparent to the decision: rows parsed from the producer
    // select exactly what the equivalent struct facts select. Four rows in
    // one unit at one revision on the target are a uniform measurement, and
    // the software check wins under this profile just as `measuredSet` does.
    const rows = [_][]const u8{
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":1,"crossing":0},"subject_revision":"9f62a9dcf0000000000000000000000000000001"}
        ,
        \\{"schema":"idol.world.cost.v1","mechanism":"mpk","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":900},"subject_revision":"9f62a9dcf0000000000000000000000000000001"}
        ,
        \\{"schema":"idol.world.cost.v1","mechanism":"process","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":3000},"subject_revision":"9f62a9dcf0000000000000000000000000000001"}
        ,
        \\{"schema":"idol.world.cost.v1","mechanism":"network_isolation","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":100000},"subject_revision":"9f62a9dcf0000000000000000000000000000001"}
        ,
    };
    var revs: [4][64]u8 = undefined;
    var facts: [4]MeasuredCost = undefined;
    for (rows, 0..) |text, i| facts[i] = parseMeasured(text, &revs[i]).?;

    const auth = exposedAuthority();
    const target = world.TargetWorld.of(measured_triple);
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    const plan = selectMeasured(auth, observation.ordinary_executable, target, profile, &facts).plan.dynamic;
    try std.testing.expectEqual(Mechanism.software_check, plan.mechanism);
    try std.testing.expectEqual(CostUnit.nanoseconds, plan.unit);
    try std.testing.expectEqual(@as(u64, 1000), plan.cost.total(profile));
}

test "lower: parseMeasurements owns every complete producer row" {
    const alloc = std.testing.allocator;
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":3,"crossing":0},"subject_revision":"c0adff39aabbccddeeff00112233445566778899"}
        \\{"schema":"idol.world.cost.v1","mechanism":"process","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":1800},"subject_revision":"c0adff39aabbccddeeff00112233445566778899"}
    ;
    var parsed = (try parseMeasurements(alloc, text)).?;
    defer parsed.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), parsed.facts.items.len);
    try std.testing.expectEqual(Mechanism.software_check, parsed.facts.items[0].mechanism);
    try std.testing.expectEqual(Mechanism.process, parsed.facts.items[1].mechanism);
    try std.testing.expectEqualStrings(parsed.facts.items[0].subject_revision, parsed.facts.items[1].subject_revision);
}

test "lower: parseMeasurements refuses a partial evidence stream" {
    const alloc = std.testing.allocator;
    const text =
        \\{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":3,"crossing":0},"subject_revision":"c0adff39aabbccddeeff00112233445566778899"}
        \\{"schema":"idol.world.cost.v1","mechanism":"unknown","triple":"x86_64-linux-gnu","unit":"nanoseconds","cost":{"access":0,"crossing":1},"subject_revision":"c0adff39aabbccddeeff00112233445566778899"}
    ;
    try std.testing.expect((try parseMeasurements(alloc, text)) == null);
}

test "lower: cheri is selected on a capability world, with derived construction" {
    const auth = world.Authority.of(.{
        .alias = .no,
        .escape = .yes,
        .immutability = .yes,
        .determinacy = .unknown,
        .extent = .{ .exact = 128 },
    });
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const target = world.TargetWorld.of(.{ .arch = .aarch64, .os = .linux, .abi = .gnu }).with(.cheri);
    const plan = select(auth, hostile, target, .{ .accesses = 500, .crossings = 5 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.cheri, plan.mechanism);
    const cap = plan.capability.?;
    try std.testing.expectEqual(@as(u32, 128), cap.extent);
    // readonly authority: no store permission.
    try std.testing.expect(cap.permissions.contains(.load));
    try std.testing.expect(!cap.permissions.contains(.store));
    // unique subject: sealed; escaping subject: global.
    try std.testing.expect(cap.sealed);
    try std.testing.expect(cap.global);
}

test "lower: capability derivation refuses an unknown extent, and selection falls through" {
    const auth = world.Authority.of(.{
        .alias = .no,
        .escape = .yes,
        .immutability = .yes,
        .determinacy = .unknown,
        .extent = .unknown,
    });
    try std.testing.expect(capabilityOf(auth) == null);
    // On a cheri-admitting x86_64 world the unknown extent removes cheri
    // from admissibility; the next cheapest admitted mechanism wins instead.
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu }).with(.cheri);
    const plan = select(auth, hostile, target, .{ .accesses = 500, .crossings = 5 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plan.mechanism);
}

test "lower: nonescape clears the global bit" {
    const auth = world.Authority.of(.{
        .alias = .no,
        .escape = .no,
        .immutability = .no,
        .extent = .{ .bounded = 32 },
    });
    const cap = capabilityOf(auth).?;
    try std.testing.expectEqual(@as(u32, 32), cap.extent);
    try std.testing.expect(cap.permissions.contains(.store));
    try std.testing.expect(!cap.global);
}

test "lower: no admissible mechanism refuses closed" {
    // A freestanding target admits only the software check, which cannot
    // confine; an adversarial demand is therefore refused, not weakened.
    const bare = world.TargetWorld.of(.{ .arch = .aarch64, .os = .none, .abi = .none });
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const selection = select(exposedAuthority(), hostile, bare, .{ .accesses = 1, .crossings = 1 });
    try std.testing.expectEqual(Refusal.no_admissible_mechanism, selection.refused);
}

test "lower: foreign_boundary moves selection to a boundary the forger cannot cross" {
    // The SAME authority, profile and target — only the world fact changes.
    // Without it MPK wins; under it the permission-register write is one the
    // foreign code can issue for itself, so the answer is the page-table
    // boundary.
    const auth = exposedAuthority();
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const profile: Profile = .{ .accesses = 1000, .crossings = 10 };
    const plain = select(auth, observation.ordinary_executable, target, profile).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, plain.mechanism);
    const forged = select(auth, observation.ordinary_executable.with(.foreign_boundary), target, profile).plan.dynamic;
    try std.testing.expectEqual(Mechanism.process, forged.mechanism);
}

test "lower: foreign_boundary keeps cheri admissible — the ruling discriminates" {
    // The fact narrows admissibility; it does not carpet-ban. A capability is
    // unforgeable, so on a capability world the same adversarial demand is
    // answered by CHERI — with the construction still derived from the
    // authority facts — rather than by a costlier boundary.
    const auth = exposedAuthority();
    const hostile = observation.ordinary_executable.with(.security_adversary).with(.foreign_boundary);
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu }).with(.cheri);
    const plan = select(auth, hostile, target, .{ .accesses = 500, .crossings = 5 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.cheri, plan.mechanism);
    try std.testing.expectEqual(@as(u32, 64), plan.capability.?.extent);
}

test "lower: foreign_boundary denies the static rung" {
    // The same facts that realize at zero cost in an ordinary world cannot
    // witness spatial or immutability against in-image code that forges
    // pointers: the proof covers the program's own accesses and no foreign
    // ones, so zero enforcement is not admissible and the cheapest surviving
    // boundary answers instead.
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const profile: Profile = .{ .accesses = 1000, .crossings = 100 };
    const plain = select(fixedAuthority(), observation.ordinary_executable, target, profile);
    try std.testing.expect(std.meta.activeTag(plain.plan) == .static);
    const forged = select(fixedAuthority(), observation.ordinary_executable.with(.foreign_boundary), target, profile);
    try std.testing.expectEqual(Mechanism.process, forged.plan.dynamic.mechanism);
}

test "lower: foreign_boundary on a bare target refuses closed" {
    // The freestanding target admitted the software check and nothing else;
    // with that arm void there is no admissible enforcement at all, and the
    // answer is a refusal, never a weakening.
    const bare = world.TargetWorld.of(.{ .arch = .aarch64, .os = .none, .abi = .none });
    const forged = observation.ordinary_executable.with(.foreign_boundary);
    const selection = select(exposedAuthority(), forged, bare, .{ .accesses = 1, .crossings = 1 });
    try std.testing.expectEqual(Refusal.no_admissible_mechanism, selection.refused);
}

test "lower: the evidence record is structured and names its decision" {
    const target = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const attack = observation.ordinary_executable.with(.security_adversary);
    const selection = select(exposedAuthority(), attack, target, .{ .accesses = 10, .crossings = 2 });
    var storage: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&storage);
    try writeJson(&writer, selection);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("idol.world.enforcement.v1", parsed.value.object.get("schema").?.string);
    try std.testing.expectEqualStrings("mpk", parsed.value.object.get("mechanism").?.string);
    const demanded = parsed.value.object.get("demanded").?.array;
    try std.testing.expectEqual(@as(usize, 4), demanded.items.len);
    // The cost record names the unit its numbers are in — the stated
    // relation's scale here.
    const cost = parsed.value.object.get("cost").?.object;
    try std.testing.expectEqualStrings("cycle_order", cost.get("unit").?.string);
}

// ===========================================================================
// The graph wiring, measured over real censuses — authority facts reaching
// `select` through `place.analyzeModule` output, never a hand-built bundle.
// ===========================================================================

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn censusOf(arena: *std.heap.ArenaAllocator, src: []const u8) !place.Census {
    const alloc = arena.allocator();
    const owned = try alloc.dupe(u8, src);
    var lexer = Lexer.init(owned, "lower_test.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    return try place.analyzeModule(alloc, &mod);
}

test "lower: a census place with statically fixed authority realizes at zero cost" {
    // GAP-185 required order 5, THROUGH THE GRAPH'S CENSUS: a module word that
    // nothing names, writes or aliases has every demanded property statically
    // witnessed, so the plan carries the authority facts and no dynamic
    // enforcement — the zero-overhead rung is reached from census facts alone.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\hidden: i64 = 2
        \\
    );
    defer census.deinit();
    const p = census.find("hidden").?;
    const linux = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const selection = selectPlace(p, observation.ordinary_executable, linux, 1);
    const witness = selection.plan.static;
    try std.testing.expectEqual(world.Tri.yes, witness.unique);
    try std.testing.expectEqual(world.Tri.yes, witness.nonescape);
    try std.testing.expectEqual(world.Tri.yes, witness.readonly);

    // The same census facts under an adversary cannot discharge
    // confidentiality or timing: a mechanism is selected, not assumed away.
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const dynamic = selectPlace(p, hostile, linux, 1).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, dynamic.mechanism);
}

test "lower: one census place selects different enforcement per target world" {
    // GAP-185's evidence shape through the graph wiring: the SAME census row,
    // the SAME derived authority — only the target world changes the answer.
    // `peek` names `seen`, so the census records the escape and the static
    // rung is unavailable; the adversary demands confinement and timing.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\seen: i64 = 1
        \\peek: i64 = ()
        \\    seen
        \\
    );
    defer census.deinit();
    const p = census.find("seen").?;
    try std.testing.expectEqual(place.Tri.yes, p.facts.escape);
    const hostile = observation.ordinary_executable.with(.security_adversary);

    // One read of `seen`, recorded exactly: accesses = 1, crossings = 1.
    const linux = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const on_linux = selectPlace(p, hostile, linux, 1).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, on_linux.mechanism);
    try std.testing.expectEqual(@as(u64, 32), on_linux.cost.total(.{ .accesses = 1, .crossings = 1 }));

    const macos = world.TargetWorld.of(.{ .arch = .aarch64, .os = .macos, .abi = .gnu });
    const on_macos = selectPlace(p, hostile, macos, 1).plan.dynamic;
    try std.testing.expectEqual(Mechanism.process, on_macos.mechanism);
    try std.testing.expectEqual(@as(u64, 2048), on_macos.cost.total(.{ .accesses = 1, .crossings = 1 }));
}

test "lower: an unknown census multiplicity is an unknown workload, never a small one" {
    // A read inside a loop whose trip count the census cannot bound leaves the
    // multiplicity UNKNOWN. Selection must not manufacture a workload: with no
    // cost claim the weakest sufficient admitted mechanism wins.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\total: i64 = 0
        \\walk: i64 = (n: i64)
        \\    i = 0
        \\    while i < n
        \\        total += 1
        \\        i += 1
        \\    total
        \\
    );
    defer census.deinit();
    const p = census.find("total").?;
    try std.testing.expectEqual(@as(?u64, null), p.writeCount().upperOrNull());
    const linux = world.TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const unknown_workload = selectPlace(p, observation.ordinary_executable, linux, 1).plan.dynamic;
    try std.testing.expectEqual(Mechanism.software_check, unknown_workload.mechanism);

    // A KNOWN profile over the same authority answers the cost question
    // instead: crossings dominate at 1, so MPK's free in-domain access wins.
    const auth = world.Authority.of(p.facts);
    const known = select(auth, observation.ordinary_executable, linux, .{ .accesses = 10000, .crossings = 1 }).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, known.mechanism);
}

test "lower: a census place with no admissible enforcement refuses closed" {
    // WASI admits the software check and the Wasm sandbox; an adversary's
    // timing demand fits neither. The refusal is an outcome, not a weakening.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var census = try censusOf(&arena,
        \\seen: i64 = 1
        \\peek: i64 = ()
        \\    seen
        \\
    );
    defer census.deinit();
    const p = census.find("seen").?;
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const wasi = world.TargetWorld.of(.{ .arch = .wasm32, .os = .wasi, .abi = .none });
    const selection = selectPlace(p, hostile, wasi, 1);
    try std.testing.expectEqual(Refusal.no_admissible_mechanism, selection.refused);
}

// ===========================================================================
// THE backend consumer, measured — the realization walk over census rows
// with KNOWN facts. These rows are built directly, not through `censusOf`:
// the walk's subject is `selectModule` — completeness, rung counts,
// fail-closed naming — and the GAP-145 table-primary parser regression
// blocks producing a census from source at HEAD. Census PRODUCTION is the
// graph-wiring tests' subject above; selection consumes only `facts` and the
// recorded access counts, so a direct row is the walk's honest input.
// ===========================================================================

/// One census row with known facts. `binding` is never read on the selection
/// path — `selectPlace` consumes `facts` and access counts — so it stays
/// unwritten rather than pointing at a fabricated statement.
fn row(id: u32, name: []const u8, facts: place.Facts) place.Place {
    return .{
        .id = id,
        .name = name,
        .binding = undefined,
        .shape = .scalar,
        .region = .module,
        .bind_origin = .declaration,
        .init = null,
        .facts = facts,
    };
}

/// The facts a census records for a word nothing names, writes or aliases:
/// every demanded property statically witnessed — the zero-cost rung.
fn fixedFacts() place.Facts {
    return .{
        .alias = .no,
        .escape = .no,
        .mutation = .no,
        .immutability = .yes,
        .determinacy = .exact,
    };
}

/// The facts a census records for a word another region names: the escape is
/// observed, so the static rung is unavailable.
fn escapedFacts() place.Facts {
    return .{
        .alias = .no,
        .escape = .yes,
        .mutation = .no,
        .immutability = .yes,
        .determinacy = .exact,
    };
}

test "lower: the backend realization walk selects every census place" {
    // GAP-185's backend consumer, measured: the walk selects ONE plan per
    // census row — the count is the census size exactly — and the rung split
    // is the per-place `selectPlace` answer under the world the graph-backed
    // C realization arm selects in: portable C99 source admits the software
    // check and nothing else.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "hidden", fixedFacts()));
    try census.places.append(alloc, row(1, "seen", escapedFacts()));
    const portable = world.TargetWorld.of(.{ .arch = .unknown, .os = .unknown, .abi = .unknown });
    const selection = selectModule(&census, observation.ordinary_executable, portable, 0);
    const realized = selection.realized;
    try std.testing.expectEqual(census.count(), realized.places);
    try std.testing.expectEqual(realized.places, realized.static_plans + realized.dynamic_plans);
    try std.testing.expectEqual(@as(usize, 1), realized.static_plans);
    try std.testing.expectEqual(@as(usize, 1), realized.dynamic_plans);

    // The anchors, row by row: the authority nothing names is statically
    // witnessed (the zero-cost rung); the escaped authority, with only the
    // software check admitted, is that check.
    const hidden = census.find("hidden").?;
    try std.testing.expect(std.meta.activeTag(selectPlace(hidden, observation.ordinary_executable, portable, 0).plan) == .static);
    const seen = census.find("seen").?;
    try std.testing.expectEqual(Mechanism.software_check, selectPlace(seen, observation.ordinary_executable, portable, 0).plan.dynamic.mechanism);

    // The aggregate IS the per-place walk: recounting by hand agrees.
    var static_count: usize = 0;
    var dynamic_count: usize = 0;
    for (census.places.items) |*p| {
        switch (selectPlace(p, observation.ordinary_executable, portable, 0)) {
            .plan => |plan| switch (plan) {
                .static => static_count += 1,
                .dynamic => dynamic_count += 1,
            },
            .refused => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expectEqual(static_count, realized.static_plans);
    try std.testing.expectEqual(dynamic_count, realized.dynamic_plans);
}

test "lower: the backend realization walk fails closed on the refusing place" {
    // WASI admits the software check and the Wasm sandbox; the adversary's
    // confidentiality and timing demands fit neither, so BOTH rows have no
    // admissible enforcement — and the walk names the FIRST refusing row, a
    // real census place `selectPlace` itself refuses on, rather than
    // weakening the demand.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "hidden", fixedFacts()));
    try census.places.append(alloc, row(1, "seen", escapedFacts()));
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const wasi = world.TargetWorld.of(.{ .arch = .wasm32, .os = .wasi, .abi = .none });
    const selection = selectModule(&census, hostile, wasi, 0);
    try std.testing.expectEqual(Refusal.no_admissible_mechanism, selection.refused.refusal);
    try std.testing.expectEqualStrings("hidden", selection.refused.place);
    const p = census.find(selection.refused.place).?;
    try std.testing.expectEqual(Refusal.no_admissible_mechanism, selectPlace(p, hostile, wasi, 0).refused);
}

// ===========================================================================
// collectStaticPlaces — the per-place plans as a name-keyed set
// ===========================================================================

test "lower: collectStaticPlaces marks statically fixed places" {
    // The same census as the backend walk test: `hidden` is statically fixed,
    // `seen` escapes. On a portable world the static rung is available for
    // `hidden` (ordinary_executable, no foreign_boundary, no adversary).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "hidden", fixedFacts()));
    try census.places.append(alloc, row(1, "seen", escapedFacts()));
    const portable = world.TargetWorld.of(.{ .arch = .unknown, .os = .unknown, .abi = .unknown });
    var set = collectStaticPlaces(alloc, &census, observation.ordinary_executable, portable, 0).?;
    defer set.deinit(alloc);
    // `hidden` is statically fixed; `seen` is not.
    try std.testing.expect(set.contains("hidden"));
    try std.testing.expect(!set.contains("seen"));
}

test "lower: collectStaticPlaces returns null on refusal" {
    // WASI + adversary: no admissible mechanism for `hidden`, so the
    // function returns null rather than a partial set.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "hidden", fixedFacts()));
    try census.places.append(alloc, row(1, "seen", escapedFacts()));
    const hostile = observation.ordinary_executable.with(.security_adversary);
    const wasi = world.TargetWorld.of(.{ .arch = .wasm32, .os = .wasi, .abi = .none });
    try std.testing.expectEqual(@as(?std.StringHashMapUnmanaged(void), null), collectStaticPlaces(alloc, &census, hostile, wasi, 0));
}

test "lower: collectStaticPlaces is empty when no place is statically fixed" {
    // Both places escape; no static rung is available.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "a", escapedFacts()));
    try census.places.append(alloc, row(1, "b", escapedFacts()));
    const portable = world.TargetWorld.of(.{ .arch = .unknown, .os = .unknown, .abi = .unknown });
    var set = collectStaticPlaces(alloc, &census, observation.ordinary_executable, portable, 0).?;
    defer set.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 0), set.count());
}

// ===========================================================================
// Measured facts reaching the realization walk — selectPlace/selectModule/
// collectStaticPlaces under a measured slice, threaded into selectMeasured
// ===========================================================================

/// One census row with a KNOWN read multiplicity, so the walk derives a live
/// workload profile and the cost comparison is not the tie rule.
fn escapedRowWithAccess(alloc: std.mem.Allocator) !place.Place {
    var p = row(0, "seen", escapedFacts());
    try p.accesses.append(alloc, .{ .kind = .read, .point = 0, .depth = 0, .mult = .{ .exact = 1000 }, .const_index = true });
    return p;
}

test "lower: measured facts reach the realization walk and flip a place's selection" {
    // The same census row, the same authority and target: stated orders pick
    // MPK (320 vs the software check's 2000), and a uniform measurement of all
    // four admitted candidates on the target in nanoseconds flips the row to
    // the software check (1000 vs MPK's 9000). The measured facts REACH the
    // walk — `selectPlaceMeasured` and `selectModuleMeasured` consume the same
    // slice `selectMeasured` does.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, try escapedRowWithAccess(alloc));

    const attack = observation.ordinary_executable;
    const linux = world.TargetWorld.of(measured_triple);
    const crossings: u64 = 10;

    const stated = selectPlace(census.find("seen").?, attack, linux, crossings).plan.dynamic;
    try std.testing.expectEqual(Mechanism.mpk, stated.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, stated.unit);

    const measured = measuredSet(.nanoseconds);
    const flipped = selectPlaceMeasured(census.find("seen").?, attack, linux, crossings, &measured).plan.dynamic;
    try std.testing.expectEqual(Mechanism.software_check, flipped.mechanism);
    try std.testing.expectEqual(CostUnit.nanoseconds, flipped.unit);
    try std.testing.expectEqual(@as(u64, 1000), flipped.cost.total(.{ .accesses = 1000, .crossings = 10 }));

    const walk = selectModuleMeasured(&census, attack, linux, crossings, &measured).realized;
    try std.testing.expectEqual(census.count(), walk.places);
    try std.testing.expectEqual(@as(usize, 0), walk.static_plans);
    try std.testing.expectEqual(@as(usize, 1), walk.dynamic_plans);
}

test "lower: a non-uniform measurement leaves the walk on stated orders" {
    // A partial measurement (the software check alone) is not a uniform
    // comparison, so the measured walk's per-place answer equals the empty
    // face's: MPK, stated orders. The `*Measured` variants are the same walk
    // under the same rule, not a second, weaker one.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, try escapedRowWithAccess(alloc));

    const attack = observation.ordinary_executable;
    const linux = world.TargetWorld.of(measured_triple);
    const crossings: u64 = 10;

    const partial = [_]MeasuredCost{measuredSet(.nanoseconds)[0]};
    const empty = selectPlace(census.find("seen").?, attack, linux, crossings).plan.dynamic;
    const measured = selectPlaceMeasured(census.find("seen").?, attack, linux, crossings, &partial).plan.dynamic;
    try std.testing.expectEqual(empty.mechanism, measured.mechanism);
    try std.testing.expectEqual(Mechanism.mpk, measured.mechanism);
    try std.testing.expectEqual(CostUnit.cycle_order, measured.unit);
}

test "lower: measured facts never manufacture a static witness" {
    // A measurement of every mechanism does not turn an escaping place static:
    // the static rung is the authority proof alone. `collectStaticPlacesMeasured`
    // threads measured facts for the DYNAMIC selection only, so the name-keyed
    // static set is exactly what the empty face returns.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var census = place.Census.init(alloc);
    defer census.deinit();
    try census.places.append(alloc, row(0, "hidden", fixedFacts()));
    try census.places.append(alloc, row(1, "seen", escapedFacts()));
    const linux = world.TargetWorld.of(measured_triple);
    const measured = measuredSet(.nanoseconds);
    var set = collectStaticPlacesMeasured(alloc, &census, observation.ordinary_executable, linux, 0, &measured).?;
    defer set.deinit(alloc);
    try std.testing.expect(set.contains("hidden"));
    try std.testing.expect(!set.contains("seen"));
}
