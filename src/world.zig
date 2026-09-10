//! WORLD → AUTHORITY → ENFORCEMENT facts (GAP-185).
//!
//! A world grants authority (`law.world.grant`); authority over a subject is a
//! bundle of SEMANTIC facts — unique, nonescape, readonly, extent — projected
//! here from the place fact bundle (`place.Facts` is the sole producer,
//! `law.fact.producer.one`). Enforcement of that authority is a REALIZATION
//! candidate, never a semantic kind: `Mechanism` is a compact physical index
//! (`kinds.role = .index`, authority false) and no `SafePointer`,
//! `CapabilityObject`, or `SandboxType` semantic kind is minted here or anywhere
//! else. The selection over this index lives in `lower.zig`.
//!
//! The observation/attack model is `observation.World`; `demandOf` maps it to
//! the enforcement PROPERTIES a realization must preserve. Unknown blocks:
//! every authority fact is three-valued (`place.Tri`) and an unproven fact
//! demands enforcement rather than assuming it away.
//!
//! DELETION WITNESS (`law.bridge.death`): host owner before — this module and
//! `lower.zig`; Idol owner after — graph-carried world/authority facts with
//! realization selection as a witnessed transform; the BACKEND lowering
//! consumer LANDED — the graph-backed C99 realization arm in `main.zig` calls
//! `lower.selectModule` per census place during realization (`lower.selectPlace`
//! is the graph-facing selection over one census row: authority facts reach
//! selection through the census the graph carries). The per-place PLANS
//! constraining lowering LANDED — `lower.collectStaticPlaces` populates
//! `graph.static_places` so `dnir_lower` elides enforcement for statically
//! fixed places. The measured-cost face LANDED in `lower.zig`: a
//! `MeasuredCost` fact (mechanism, target triple, unit, measured subject
//! revision) decides a selection only as a uniform comparison;
//! `gate/lower/cost.sh` measures the software check on the host. Measured
//! facts now REACH the realization walk — `lower.selectPlace`/`selectModule`/
//! `collectStaticPlaces` delegate to `*Measured` variants that thread a
//! measured slice through `selectMeasured`. Next host boundary — measured
//! costs for the boundary mechanisms.
//!
//! `foreign_boundary` IS modeled, as an admissibility ruling over the
//! observation world (`observation.WorldFact.foreign_boundary`): foreign code
//! in-image can forge pointers, so an enforcement that is a CONVENTION in-image
//! code participates in preserves nothing against it — the foreign code was
//! never compiled to follow it. What survives is what the forger cannot cross
//! from inside the image: unforgeable hardware capabilities (`.cheri`), the
//! page-table boundary (`.process`), a transport boundary
//! (`.network_isolation`), and the Wasm engine's mandatory per-access
//! linear-memory check (`.wasm_sandbox`) — engine semantics on every access,
//! not a convention the checked code follows. The same premise denies
//! `lower.select`'s static rung: a proof over the program's own accesses
//! quantifies over no foreign ones.

const std = @import("std");
const place = @import("place.zig");
const observation = @import("observation.zig");
const target_model = @import("target/model.zig");

/// Three-valued, and the third value is the point: shared with `place.zig`
/// rather than redeclared. An `unknown` authority fact is never read as `no`.
pub const Tri = place.Tri;

// ===========================================================================
// The enforcement mechanisms — a compact physical index, never meaning
// ===========================================================================

/// The candidates GAP-185's physical-mechanism row names, in one bounded
/// index. Enum order is the declared strength/cost ladder used only as a
/// deterministic tiebreak in `lower.select`; admissibility is `enforces`,
/// availability is `TargetWorld.admitted`, and cost is `lower.costOf` — three
/// relations, never three readings of this order.
pub const Mechanism = enum {
    /// No dynamic enforcement at all: the authority is statically witnessed,
    /// so there is nothing to enforce against. Zero overhead by construction.
    none,
    /// A compiler-emitted test+trap inside the image. Enforces the access,
    /// not the observation of the access: the branch is data-dependent, and
    /// in-image code shares the domain.
    software_check,
    /// Hardware base+limit bounds on the access path (a bounds register or
    /// equivalent). Spatial only; the compare is not data-dependent.
    bounds,
    /// Memory protection keys: page-granularity domains inside one address
    /// space, switched by a data-independent permission-register write.
    mpk,
    /// A hardware capability carrying base, extent and permissions —
    /// unforgeable, so it confines; checked in hardware, so enforcement adds
    /// no data-dependent timing.
    cheri,
    /// An address-space boundary with an IPC crossing.
    process,
    /// A Wasm linear-memory domain: spatial isolation of the region, with no
    /// sub-region immutability the current Wasm law admits.
    wasm_sandbox,
    /// A separate trust domain reached over a transport. The strongest
    /// isolation and the most expensive crossing.
    network_isolation,

    pub const count = @typeInfo(Mechanism).@"enum".field_names.len;

    pub fn name(self: Mechanism) []const u8 {
        return switch (self) {
            .none => "none",
            .software_check => "software_check",
            .bounds => "bounds",
            .mpk => "mpk",
            .cheri => "cheri",
            .process => "process",
            .wasm_sandbox => "wasm_sandbox",
            .network_isolation => "network_isolation",
        };
    }
};

pub const MechanismSet = std.EnumSet(Mechanism);

// ===========================================================================
// The properties an enforcement can be asked to preserve
// ===========================================================================

/// What the observation/attack model can DEMAND of an enforcement. These are
/// properties of the authority relation, not of a mechanism; `enforces` maps
/// mechanism → properties, `demandOf` maps world+authority → properties.
pub const Property = enum {
    /// An access outside the subject's extent faults rather than corrupts.
    spatial,
    /// A write through a readonly authority faults.
    immutability,
    /// The subject's bytes do not leave the authority domain.
    confidentiality,
    /// Enforcement introduces no subject-data-dependent timing.
    timing,

    pub const count = @typeInfo(Property).@"enum".field_names.len;

    pub fn name(self: Property) []const u8 {
        return switch (self) {
            .spatial => "spatial",
            .immutability => "immutability",
            .confidentiality => "confidentiality",
            .timing => "timing",
        };
    }
};

pub const PropertySet = std.EnumSet(Property);

/// What a mechanism preserves AGAINST an observation/attack model — the
/// admissibility relation. Each arm is a physical fact about the mechanism,
/// stated where it is declared, so a selection question never re-derives
/// hardware truth at a call site.
///
/// The `foreign_boundary` ruling: foreign code in-image can forge pointers,
/// so a mechanism whose enforcement is a CONVENTION in-image code participates
/// in preserves nothing against it. `.software_check` is a test+trap emitted
/// around this compiler's own accesses; the foreign code carries no such
/// branch. `.bounds` is a base+limit register the access path is built to
/// consult; the forger's access path is not. `.mpk`'s domain switch is an
/// unprivileged permission-register write any in-image instruction stream can
/// issue for itself. All three read as the empty set under the fact. `.cheri`
/// (a capability cannot be minted), `.process` (the page table is not an
/// in-image convention), `.network_isolation` (a transport) and
/// `.wasm_sandbox` (the engine checks every linear-memory access, whoever
/// authored the code) are what a forger cannot cross from inside the image.
pub fn enforces(m: Mechanism, attack: observation.World) PropertySet {
    if (attack.has(.foreign_boundary)) {
        switch (m) {
            .software_check, .bounds, .mpk => return .{},
            else => {},
        }
    }
    var p: PropertySet = .{};
    switch (m) {
        // Statically witnessed authority has no dynamic enforcement; the
        // witness, not a mechanism, is what preserves the properties.
        .none => {},
        // A test+trap stops the violating access; it does not isolate the
        // domain and its branch is data-dependent.
        .software_check => {
            p.insert(.spatial);
            p.insert(.immutability);
        },
        // Hardware bounds stop the out-of-extent access without a
        // data-dependent branch; they carry no permission axis.
        .bounds => {
            p.insert(.spatial);
            p.insert(.timing);
        },
        // Page-granularity domains: confinement at page granularity, a
        // permission axis, and a data-independent domain switch.
        .mpk => {
            p.insert(.spatial);
            p.insert(.immutability);
            p.insert(.confidentiality);
            p.insert(.timing);
        },
        // Unforgeable base+extent+permissions at byte granularity, checked
        // in hardware on every access.
        .cheri => {
            p.insert(.spatial);
            p.insert(.immutability);
            p.insert(.confidentiality);
            p.insert(.timing);
        },
        // Address spaces confine, page permissions carry immutability, and
        // the crossing is a syscall whose cost does not depend on the
        // subject's bytes.
        .process => {
            p.insert(.spatial);
            p.insert(.immutability);
            p.insert(.confidentiality);
            p.insert(.timing);
        },
        // Linear memory confines the region; current Wasm law admits no
        // sub-region readonly, and an explicit-bounds realization is
        // data-dependent, so timing is not claimed.
        .wasm_sandbox => {
            p.insert(.spatial);
            p.insert(.confidentiality);
        },
        // A separate trust domain across a transport enforces every
        // property at the highest crossing cost.
        .network_isolation => {
            p.insert(.spatial);
            p.insert(.immutability);
            p.insert(.confidentiality);
            p.insert(.timing);
        },
    }
    return p;
}

// ===========================================================================
// Authority — the semantic facts about one subject, projected from place facts
// ===========================================================================

/// The authority facts GAP-185 names, over one subject. Every field is
/// three-valued or determinacy-tagged because an unproven fact must DEMAND
/// enforcement; there is no default grant.
pub const Authority = struct {
    /// No second name reaches the subject (`place.Facts.alias` inverted).
    unique: Tri = .unknown,
    /// No reference leaves the subject's region (`place.Facts.escape`
    /// inverted).
    nonescape: Tri = .unknown,
    /// A write through this authority is a semantic fault.
    readonly: Tri = .unknown,
    /// The subject's extent fact, carried for capability construction.
    extent: place.Extent = .unknown,
    /// Whether every access is statically determined.
    determinacy: place.Determinacy = .unknown,

    /// THE projection from the place fact bundle — the one place polarity
    /// is stated, so no consumer inverts `alias` or `escape` by hand.
    pub fn of(facts: place.Facts) Authority {
        return .{
            .unique = switch (facts.alias) {
                .no => .yes,
                .yes => .no,
                .unknown => .unknown,
            },
            .nonescape = switch (facts.escape) {
                .no => .yes,
                .yes => .no,
                .unknown => .unknown,
            },
            .readonly = readonlyOf(facts),
            .extent = facts.extent,
            .determinacy = facts.determinacy,
        };
    }

    /// `readonly` is proven only by an immutability proof, and disproven by
    /// an observed mutation or a proven-mutable fact. Anything else is
    /// unknown — "no mutation seen yet" is not immutability.
    fn readonlyOf(facts: place.Facts) Tri {
        if (facts.immutability == .yes) return .yes;
        if (facts.mutation == .yes or facts.immutability == .no) return .no;
        return .unknown;
    }

    /// Is every demanded property statically witnessed, so that no dynamic
    /// enforcement can ever observe a violation? This is GAP-185's
    /// zero-overhead rung as a relation over facts: the answer is yes only
    /// when every access is statically determined and no second name can
    /// reach the subject.
    ///
    /// `confidentiality` and `timing` are NEVER discharged here: an
    /// adversary's observations are not bounded by local access determinacy,
    /// so a world that demands them always requires a mechanism.
    pub fn fixedAgainst(self: Authority, demanded: PropertySet) bool {
        if (self.determinacy != .exact) return false;
        if (self.unique != .yes or self.nonescape != .yes) return false;
        if (demanded.contains(.immutability) and self.readonly != .yes) return false;
        if (demanded.contains(.confidentiality) or demanded.contains(.timing)) return false;
        return true;
    }
};

/// The enforcement properties a world and an authority bundle demand — the
/// observation/attack model as a constraint on admissible enforcement
/// (GAP-185's demand implication).
///
/// `spatial` is ALWAYS demanded: the failure_recovery observer is always
/// demanded (`observation.World.observers`), and an out-of-authority access
/// that corrupts instead of faulting is exactly what it observes. A readonly
/// authority demands `immutability` — and an authority of UNKNOWN polarity
/// demands it too, because an unproven non-observation is not a
/// non-observation. A `security_adversary` world fact demands
/// `confidentiality` and `timing`: the adversary observes addresses, cache
/// and duration (`observation.WorldFact.security_adversary`).
pub fn demandOf(attack: observation.World, auth: Authority) PropertySet {
    var p: PropertySet = .{};
    p.insert(.spatial);
    if (auth.readonly != .no) p.insert(.immutability);
    if (attack.has(.security_adversary)) {
        p.insert(.confidentiality);
        p.insert(.timing);
    }
    return p;
}

// ===========================================================================
// The target world — which mechanisms a world admits
// ===========================================================================

/// The mechanisms a TARGET WORLD admits. The default facts are derived from
/// the target triple; a world may carry additional mechanism facts (a
/// capability-architecture world admits `.cheri`) through `with` — injection
/// changes fact availability and never manufactures authority
/// (`law.injection.authority`).
pub const TargetWorld = struct {
    triple: target_model.TargetTriple,
    admitted: MechanismSet,

    /// The default availability facts for a triple. Honest by construction:
    /// a mechanism this compiler's targets do not expose is simply not
    /// admitted — `.bounds` and `.cheri` name real hardware this target
    /// index does not yet carry, and selection over an honest empty set
    /// beats an attractive speculative one (`law` §14).
    pub fn of(triple: target_model.TargetTriple) TargetWorld {
        var admitted: MechanismSet = .{};
        // The compiler can always emit a test+trap on any target.
        admitted.insert(.software_check);
        switch (triple.os) {
            .macos, .linux, .freebsd, .windows => {
                admitted.insert(.process);
                admitted.insert(.network_isolation);
            },
            // WASI is the sandbox world itself.
            .wasi => admitted.insert(.wasm_sandbox),
            .none, .unknown => {},
        }
        // PKU is exposed to userspace as pkeys on Linux/x86_64 only.
        if (triple.arch == .x86_64 and triple.os == .linux) admitted.insert(.mpk);
        if (triple.arch == .wasm32) admitted.insert(.wasm_sandbox);
        return .{ .triple = triple, .admitted = admitted };
    }

    /// A target world carrying an additional admitted mechanism fact.
    pub fn with(self: TargetWorld, m: Mechanism) TargetWorld {
        var t = self;
        t.admitted.insert(m);
        return t;
    }

    pub fn admits(self: TargetWorld, m: Mechanism) bool {
        return self.admitted.contains(m);
    }
};

// ===========================================================================
// Tests
// ===========================================================================

test "world: authority projection inverts alias and escape exactly once" {
    const auth = Authority.of(.{
        .alias = .no,
        .escape = .no,
        .immutability = .yes,
        .mutation = .no,
        .determinacy = .exact,
        .extent = .{ .exact = 16 },
    });
    try std.testing.expectEqual(Tri.yes, auth.unique);
    try std.testing.expectEqual(Tri.yes, auth.nonescape);
    try std.testing.expectEqual(Tri.yes, auth.readonly);

    const aliased = Authority.of(.{ .alias = .yes, .escape = .unknown, .mutation = .yes });
    try std.testing.expectEqual(Tri.no, aliased.unique);
    try std.testing.expectEqual(Tri.unknown, aliased.nonescape);
    try std.testing.expectEqual(Tri.no, aliased.readonly);

    // "No mutation observed" is not immutability.
    const unproven = Authority.of(.{ .mutation = .no });
    try std.testing.expectEqual(Tri.unknown, unproven.readonly);
}

test "world: demand follows the observation/attack model" {
    // The ordinary world always demands spatial integrity, and a readonly
    // authority adds immutability.
    const fixed = Authority.of(.{
        .alias = .no,
        .escape = .no,
        .immutability = .yes,
        .determinacy = .exact,
        .extent = .{ .exact = 8 },
    });
    const ordinary = demandOf(observation.ordinary_executable, fixed);
    try std.testing.expect(ordinary.contains(.spatial));
    try std.testing.expect(ordinary.contains(.immutability));
    try std.testing.expect(!ordinary.contains(.confidentiality));
    try std.testing.expect(!ordinary.contains(.timing));

    // A writable authority drops the immutability demand; unknown keeps it.
    const writable = Authority.of(.{ .mutation = .yes });
    try std.testing.expect(!demandOf(observation.ordinary_executable, writable).contains(.immutability));
    const unproven = Authority.of(.{});
    try std.testing.expect(demandOf(observation.ordinary_executable, unproven).contains(.immutability));

    // An adversary observes addresses and duration.
    const hostile = demandOf(observation.ordinary_executable.with(.security_adversary), fixed);
    try std.testing.expect(hostile.contains(.confidentiality));
    try std.testing.expect(hostile.contains(.timing));
}

test "world: statically fixed authority discharges only non-adversarial demand" {
    const fixed = Authority.of(.{
        .alias = .no,
        .escape = .no,
        .immutability = .yes,
        .determinacy = .exact,
        .extent = .{ .exact = 8 },
    });
    const ordinary = demandOf(observation.ordinary_executable, fixed);
    try std.testing.expect(fixed.fixedAgainst(ordinary));

    // The same facts under an adversary are NOT fixed: confidentiality and
    // timing are never discharged statically.
    const hostile = demandOf(observation.ordinary_executable.with(.security_adversary), fixed);
    try std.testing.expect(!fixed.fixedAgainst(hostile));

    // Any unknown link in the static chain blocks the zero-overhead rung.
    const escaped = Authority.of(.{ .alias = .no, .escape = .unknown, .immutability = .yes, .determinacy = .exact });
    try std.testing.expect(!escaped.fixedAgainst(ordinary));
    const dynamic_access = Authority.of(.{ .alias = .no, .escape = .no, .immutability = .yes, .determinacy = .unknown });
    try std.testing.expect(!dynamic_access.fixedAgainst(ordinary));
}

test "world: enforces is the admissibility relation, ordered by strength" {
    const ordinary = observation.ordinary_executable;
    try std.testing.expectEqual(@as(usize, 0), enforces(.none, ordinary).count());
    const software = enforces(.software_check, ordinary);
    try std.testing.expect(software.contains(.spatial));
    try std.testing.expect(!software.contains(.confidentiality));
    try std.testing.expect(!software.contains(.timing));
    // CHERI, MPK and process confine; a Wasm sandbox admits no sub-region
    // immutability under current Wasm law.
    try std.testing.expect(enforces(.cheri, ordinary).contains(.confidentiality));
    try std.testing.expect(enforces(.cheri, ordinary).contains(.timing));
    try std.testing.expect(!enforces(.wasm_sandbox, ordinary).contains(.immutability));
    try std.testing.expect(enforces(.network_isolation, ordinary).supersetOf(enforces(.cheri, ordinary)));
}

test "world: foreign_boundary voids the in-image-cooperative mechanisms" {
    // The ruling's premise: foreign code in-image can forge pointers, so an
    // enforcement that is a convention in-image code participates in —
    // an emitted test+trap, a bounds register the access path is built to
    // consult, an unprivileged permission-register write — preserves nothing
    // against it. The foreign code was never compiled to follow any of them.
    const forged = observation.ordinary_executable.with(.foreign_boundary);
    try std.testing.expectEqual(@as(usize, 0), enforces(.software_check, forged).count());
    try std.testing.expectEqual(@as(usize, 0), enforces(.bounds, forged).count());
    try std.testing.expectEqual(@as(usize, 0), enforces(.mpk, forged).count());

    // What the forger cannot cross from inside the image is untouched: the
    // fact narrows admissibility, it does not carpet-ban.
    const ordinary = observation.ordinary_executable;
    try std.testing.expectEqual(enforces(.cheri, ordinary), enforces(.cheri, forged));
    try std.testing.expectEqual(enforces(.process, ordinary), enforces(.process, forged));
    try std.testing.expectEqual(enforces(.wasm_sandbox, ordinary), enforces(.wasm_sandbox, forged));
    try std.testing.expectEqual(enforces(.network_isolation, ordinary), enforces(.network_isolation, forged));

    // ...and the mechanisms it voids are exactly the cooperative ones:
    // without the fact they carry the properties the relation has always stated.
    try std.testing.expect(enforces(.software_check, ordinary).contains(.spatial));
    try std.testing.expect(enforces(.bounds, ordinary).contains(.spatial));
    try std.testing.expect(enforces(.mpk, ordinary).contains(.confidentiality));
}

test "world: target availability is derived from triple facts, honestly" {
    const linux = TargetWorld.of(.{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    try std.testing.expect(linux.admits(.software_check));
    try std.testing.expect(linux.admits(.mpk));
    try std.testing.expect(linux.admits(.process));
    try std.testing.expect(!linux.admits(.cheri));
    try std.testing.expect(!linux.admits(.wasm_sandbox));

    // macOS exposes no PKU; the same demand falls to another mechanism.
    const macos = TargetWorld.of(.{ .arch = .aarch64, .os = .macos, .abi = .gnu });
    try std.testing.expect(!macos.admits(.mpk));
    try std.testing.expect(macos.admits(.process));

    // WASI is the sandbox world; there is no process boundary inside it.
    const wasi = TargetWorld.of(.{ .arch = .wasm32, .os = .wasi, .abi = .none });
    try std.testing.expect(wasi.admits(.wasm_sandbox));
    try std.testing.expect(!wasi.admits(.process));

    // A freestanding target admits the software check and nothing else.
    const bare = TargetWorld.of(.{ .arch = .aarch64, .os = .none, .abi = .none });
    try std.testing.expect(bare.admits(.software_check));
    try std.testing.expect(!bare.admits(.process));
    try std.testing.expect(!bare.admits(.network_isolation));

    // Injection adds a fact; it does not mutate the source world.
    const capability_world = macos.with(.cheri);
    try std.testing.expect(capability_world.admits(.cheri));
    try std.testing.expect(!macos.admits(.cheri));
}
