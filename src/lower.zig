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
//!    fixed" rung).
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
//! over world facts; next host boundary — the demand/lowering consumer that
//! calls `select` once authority facts flow through the graph.

const std = @import("std");
const observation = @import("observation.zig");
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
/// authority consistent with the demand.
pub fn select(
    auth: world.Authority,
    attack: observation.World,
    target: world.TargetWorld,
    profile: Profile,
) Selection {
    const demanded = world.demandOf(attack, auth);
    if (auth.fixedAgainst(demanded)) return .{ .plan = .{ .static = auth } };
    var best: ?Dynamic = null;
    for (std.meta.tags(Mechanism)) |m| {
        if (!target.admits(m)) continue;
        if (!world.enforces(m).supersetOf(demanded)) continue;
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
        if (best) |incumbent| {
            if (candidate.cost.total(profile) < incumbent.cost.total(profile)) best = candidate;
        } else {
            best = candidate;
        }
    }
    if (best) |d| return .{ .plan = .{ .dynamic = d } };
    return .{ .refused = .no_admissible_mechanism };
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
