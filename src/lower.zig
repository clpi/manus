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
//! emit per place when the authority is statically fixed. Next host
//! boundary — measured per-mechanism costs replacing `costOf`'s stated
//! orders.

const std = @import("std");
const observation = @import("observation.zig");
const place = @import("place.zig");
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
pub fn select(
    auth: world.Authority,
    attack: observation.World,
    target: world.TargetWorld,
    profile: ?Profile,
) Selection {
    const demanded = world.demandOf(attack, auth);
    // The static rung's proof quantifies over the program's own accesses; a
    // `foreign_boundary` world carries in-image code that can forge pointers,
    // so zero enforcement is not admissible there (`world.enforces`' ruling).
    if (!attack.has(.foreign_boundary) and auth.fixedAgainst(demanded)) return .{ .plan = .{ .static = auth } };
    var best: ?Dynamic = null;
    for (std.meta.tags(Mechanism)) |m| {
        if (!target.admits(m)) continue;
        if (!world.enforces(m, attack).supersetOf(demanded)) continue;
        // A capability that cannot be constructed statically is not a
        // realization: derivability is an admissibility condition.
        const capability: ?Capability = if (m == .cheri) capabilityOf(auth) else null;
        if (m == .cheri and capability == null) continue;
        const candidate: Dynamic = .{
            .mechanism = m,
            .demanded = demanded,
            .cost = costOf(m),
            .capability = capability,
        };
        // The tie rule, applied: with no workload facts every admissible
        // candidate ties, so the first one in index order is the answer.
        if (profile == null) return .{ .plan = .{ .dynamic = candidate } };
        if (best) |incumbent| {
            if (candidate.cost.total(profile.?) < incumbent.cost.total(profile.?)) best = candidate;
        } else {
            best = candidate;
        }
    }
    if (best) |d| return .{ .plan = .{ .dynamic = d } };
    return .{ .refused = .no_admissible_mechanism };
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
    const reads = p.readCount().upperOrNull();
    const writes = p.writeCount().upperOrNull();
    const profile: ?Profile = if (reads != null and writes != null)
        Profile{ .accesses = reads.? +| writes.?, .crossings = crossings }
    else
        null;
    return select(world.Authority.of(p.facts), attack, target, profile);
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
    var realized: CensusSelection.Realized = .{ .places = 0, .static_plans = 0, .dynamic_plans = 0 };
    for (census.places.items) |*p| {
        switch (selectPlace(p, attack, target, crossings)) {
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
    var set: std.StringHashMapUnmanaged(void) = .empty;
    for (census.places.items) |*p| {
        switch (selectPlace(p, attack, target, crossings)) {
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
                try w.print(",\"cost\":{{\"access\":{},\"crossing\":{}}}", .{ d.cost.access, d.cost.crossing });
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
