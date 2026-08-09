/// Pass 2 — Foundational Convergence Algebra (spine types, not surface syntax).
///
/// Canonical audit: `docs/plans/pass2_foundational_convergence.md`
///
/// Goal: collapse independent compiler mechanisms into a small set of orthogonal
/// algebras. This module defines the shared vocabulary; `transform_engine.zig` and
/// `semantic_graph.zig` attach metadata. No user-facing syntax changes in Pass 2.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const directives = @import("directives.zig");

// ── 13. Knowledge Lattice ───────────────────────────────────────────────────

/// How much the compiler knows about a value. Information only increases upward.
/// Every optimization asks: "where is this value on the lattice?"
pub const KnowledgeLevel = enum(u8) {
    unknown = 0,
    observed = 1,
    guarded = 2,
    stable = 3,
    frozen = 4,
    at_comptime = 5,
    native = 6,

    pub fn name(self: KnowledgeLevel) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .observed => "observed",
            .guarded => "guarded",
            .stable => "stable",
            .frozen => "frozen",
            .at_comptime => "comptime",
            .native => "native",
        };
    }

    /// Join (⊔): best knowledge from two sources.
    pub fn join(a: KnowledgeLevel, b: KnowledgeLevel) KnowledgeLevel {
        return @enumFromInt(@max(@intFromEnum(a), @intFromEnum(b)));
    }

    /// Meet (⊓): conservative knowledge safe for both.
    pub fn meet(a: KnowledgeLevel, b: KnowledgeLevel) KnowledgeLevel {
        return @enumFromInt(@min(@intFromEnum(a), @intFromEnum(b)));
    }

    pub fn dominates(self: KnowledgeLevel, other: KnowledgeLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }

    /// Bridge Pass 1 storage classes into the knowledge lattice.
    pub fn fromStorageClass(sc: types.StorageClass) KnowledgeLevel {
        return switch (sc) {
            .dynamic => .observed,
            .guarded => .guarded,
            .sealed => .stable,
            .native => .native,
        };
    }
};

// ── 2. Stage Polymorphism ─────────────────────────────────────────────────────

/// Every function/expression can exist at arbitrary evaluation stages.
pub const Stage = enum(u8) {
    parse = 0,
    sema = 1,
    transform = 2,
    compile = 3,
    link = 4,
    runtime = 5,
    deploy = 6,
    gpu = 7,

    pub fn name(self: Stage) []const u8 {
        return switch (self) {
            .parse => "parse",
            .sema => "sema",
            .transform => "transform",
            .compile => "compile",
            .link => "link",
            .runtime => "runtime",
            .deploy => "deploy",
            .gpu => "gpu",
        };
    }

    pub fn isCompileTime(self: Stage) bool {
        return @intFromEnum(self) <= @intFromEnum(Stage.compile);
    }
};

// ── 1. Descriptor Algebra ─────────────────────────────────────────────────────

/// Operations on descriptor *values* (types, concepts, protocols, effects, …).
pub const DescriptorOp = enum {
    add,
    sub,
    intersect,
    restrict,
    transform,

    pub fn name(self: DescriptorOp) []const u8 {
        return switch (self) {
            .add => "add",
            .sub => "sub",
            .intersect => "intersect",
            .restrict => "restrict",
            .transform => "transform",
        };
    }
};

pub const DescriptorKind = enum {
    type,
    concept,
    protocol,
    enum_shape,
    module,
    schema,
    capability,
    directive,
    effect,
    hardware,

    pub fn name(self: DescriptorKind) []const u8 {
        return @tagName(self);
    }
};

/// Named descriptor reference in the convergence spine (graph node id later).
pub const DescriptorRef = struct {
    kind: DescriptorKind,
    name: []const u8,
    knowledge: KnowledgeLevel = .unknown,
};

pub const DescriptorExpr = struct {
    op: DescriptorOp,
    lhs: ?*const DescriptorExpr = null,
    rhs: ?*const DescriptorExpr = null,
    atom: ?DescriptorRef = null,

    /// Structural hash for cache keys (Phase 2+).
    pub fn hash(self: *const DescriptorExpr, hasher: *std.hash.Wyhash) void {
        hasher.update(@tagName(self.op));
        if (self.atom) |a| {
            hasher.update(a.name);
            hasher.update(@tagName(a.kind));
            hasher.update(&.{@intFromEnum(a.knowledge)});
        }
        if (self.lhs) |l| l.hash(hasher);
        if (self.rhs) |r| r.hash(hasher);
    }
};

/// Arena-backed builder for descriptor expression trees (Pass 2.1 — internal only).
pub const DescriptorExprBuilder = struct {
    nodes: std.ArrayListUnmanaged(DescriptorExpr) = .empty,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) DescriptorExprBuilder {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *DescriptorExprBuilder) void {
        self.nodes.deinit(self.alloc);
    }

    pub fn leaf(
        self: *DescriptorExprBuilder,
        kind: DescriptorKind,
        name: []const u8,
        knowledge: KnowledgeLevel,
    ) !*const DescriptorExpr {
        try self.nodes.append(self.alloc, .{
            .op = .add,
            .atom = .{ .kind = kind, .name = name, .knowledge = knowledge },
        });
        return &self.nodes.items[self.nodes.items.len - 1];
    }

    pub fn compose(
        self: *DescriptorExprBuilder,
        op: DescriptorOp,
        lhs: *const DescriptorExpr,
        rhs: *const DescriptorExpr,
    ) !*const DescriptorExpr {
        try self.nodes.append(self.alloc, .{
            .op = op,
            .lhs = lhs,
            .rhs = rhs,
        });
        return &self.nodes.items[self.nodes.items.len - 1];
    }
};

pub fn descriptorIsAtom(expr: *const DescriptorExpr) bool {
    return expr.atom != null and expr.lhs == null and expr.rhs == null;
}

pub fn descriptorStructuralHash(expr: *const DescriptorExpr) u64 {
    var hasher = std.hash.Wyhash.init(0);
    expr.hash(&hasher);
    return hasher.final();
}

/// Build descriptor for a module alias: `Point = {…}`, `Sprite = Point`, `Colored = Named + …`.
pub fn buildAliasDescriptorExpr(
    builder: *DescriptorExprBuilder,
    alias_name: []const u8,
    parent: ?[]const u8,
    target_name: ?[]const u8,
    knowledge: KnowledgeLevel,
) !*const DescriptorExpr {
    const self_atom = try builder.leaf(.type, alias_name, knowledge);
    if (parent) |p| {
        const parent_atom = try builder.leaf(.type, p, .stable);
        return try builder.compose(.add, parent_atom, self_atom);
    }
    if (target_name) |t| {
        if (!std.mem.eql(u8, t, alias_name)) {
            const target_atom = try builder.leaf(.type, t, .stable);
            return try builder.compose(.add, target_atom, self_atom);
        }
    }
    return self_atom;
}

/// Parse `@derive(Display, Eq, …)` trait names from alias attributes.
pub fn collectDeriveTraitNames(
    attributes: []const ast.Attribute,
    alloc: std.mem.Allocator,
) ![]const []const u8 {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (names.items) |n| alloc.free(n);
        names.deinit(alloc);
    }
    for (attributes) |attr| {
        const key = effectAttrKey(attr.name);
        if (!std.mem.eql(u8, key, "derive")) continue;
        // `@derive(Display, Eq)` and `@derive("Display", "Eq")` are one shape:
        // a positional list. The shared tokenizer splits it, so a comma inside
        // a quoted trait argument no longer severs the name.
        var it = directives.attrArgs(attr.args);
        while (it.next()) |arg| {
            if (arg.text.len == 0) continue;
            try names.append(alloc, try alloc.dupe(u8, arg.text));
        }
    }
    return names.toOwnedSlice(alloc);
}

/// Alias descriptor + `@derive` traits as `DescriptorOp.transform` chain (`Type~Display~Eq`).
pub fn buildAliasDescriptorExprWithDerives(
    builder: *DescriptorExprBuilder,
    alias_name: []const u8,
    parent: ?[]const u8,
    target_name: ?[]const u8,
    knowledge: KnowledgeLevel,
    attributes: []const ast.Attribute,
    alloc: std.mem.Allocator,
) !*const DescriptorExpr {
    _ = try buildAliasDescriptorExpr(builder, alias_name, parent, target_name, knowledge);
    var expr_idx = builder.nodes.items.len - 1;
    const traits = try collectDeriveTraitNames(attributes, alloc);
    defer alloc.free(traits);
    // Reserve before storing pointers into the node list (ArrayList reallocation safety).
    try builder.nodes.ensureTotalCapacity(builder.alloc, builder.nodes.items.len + traits.len * 2);
    for (traits) |trait| {
        _ = try builder.leaf(.protocol, trait, .stable);
        const trait_idx = builder.nodes.items.len - 1;
        try builder.nodes.append(builder.alloc, .{
            .op = .transform,
            .lhs = &builder.nodes.items[expr_idx],
            .rhs = &builder.nodes.items[trait_idx],
        });
        expr_idx = builder.nodes.items.len - 1;
    }
    return &builder.nodes.items[expr_idx];
}

/// Map pipeline IR ops to transform registry ids (`pipeline.map`, …).
pub fn pipelineTransformId(op: PipelineOp) []const u8 {
    return switch (op) {
        .source => "pipeline.source",
        .map => "pipeline.map",
        .filter => "pipeline.filter",
        .scan => "pipeline.scan",
        .fold => "pipeline.fold",
        .fuse => "pipeline.fuse",
        .branch => "pipeline.branch",
        .collect => "pipeline.collect",
    };
}

/// Compact label for graph JSON (`Point`, `Point+Named`, `A+B`).
pub fn formatDescriptorExprShort(expr: *const DescriptorExpr, buf: []u8) []const u8 {
    if (descriptorIsAtom(expr)) {
        return std.fmt.bufPrint(buf, "{s}", .{expr.atom.?.name}) catch "?";
    }
    const lhs = expr.lhs orelse return "?";
    const rhs = expr.rhs orelse return "?";
    var lb: [96]u8 = undefined;
    var rb: [96]u8 = undefined;
    const ls = formatDescriptorExprShort(lhs, &lb);
    const rs = formatDescriptorExprShort(rhs, &rb);
    const sep = switch (expr.op) {
        .add => "+",
        .sub => "-",
        .intersect => "&",
        .restrict => "<:",
        .transform => "~",
    };
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ ls, sep, rs }) catch "?";
}

// ── 3. Shape Algebra ──────────────────────────────────────────────────────────

pub const ShapeOp = enum {
    seal,
    open,
    merge,
    subtract,
    project,
    rename,
    freeze,
    specialize,
    lift,
    lower,

    pub fn name(self: ShapeOp) []const u8 {
        return @tagName(self);
    }

    /// Map shape ops to knowledge transitions (Pass 1 storage → Pass 2 structure).
    pub fn resultingKnowledge(op: ShapeOp, input: KnowledgeLevel) KnowledgeLevel {
        return switch (op) {
            .seal, .freeze => KnowledgeLevel.join(input, .stable),
            .specialize, .lower => KnowledgeLevel.join(input, .native),
            .lift => KnowledgeLevel.join(input, .at_comptime),
            .open => KnowledgeLevel.meet(input, .observed),
            .merge, .subtract, .project, .rename => input,
        };
    }
};

// ── 4. Call Algebra ───────────────────────────────────────────────────────────

pub const CallSite = struct {
    callee: ?[]const u8 = null,
    receiver: ?[]const u8 = null,
    stage: Stage = .runtime,
    knowledge: KnowledgeLevel = .unknown,
    effects: EffectSet = .{},
    hardware: HardwareSet = .{},
    /// Expected return arity (0 = void, null = variadic/unknown).
    return_arity: ?u8 = null,
    is_tail: bool = false,
    is_pure: bool = false,
};

// ── 6. Effect Algebra ─────────────────────────────────────────────────────────

pub const EffectAtom = enum(u8) {
    pure = 0,
    io = 1,
    network = 2,
    filesystem = 3,
    gpu = 4,
    unsafe_op = 5,
    async_suspend = 6,
    build = 7,
    noalloc = 8,
    constant_time = 9,

    pub fn name(self: EffectAtom) []const u8 {
        return switch (self) {
            .pure => "pure",
            .io => "io",
            .network => "network",
            .filesystem => "filesystem",
            .gpu => "gpu",
            .unsafe_op => "unsafe",
            .async_suspend => "suspend",
            .build => "build",
            .noalloc => "noalloc",
            .constant_time => "constant_time",
        };
    }

    pub fn bit(self: EffectAtom) u32 {
        return @as(u32, 1) << @intCast(@intFromEnum(self));
    }
};

pub const EffectSet = struct {
    bits: u32 = 0,

    pub fn empty() EffectSet {
        return .{};
    }

    pub fn singleton(atom: EffectAtom) EffectSet {
        return .{ .bits = atom.bit() };
    }

    pub fn add(self: EffectSet, atom: EffectAtom) EffectSet {
        return .{ .bits = self.bits | atom.bit() };
    }

    pub fn merge(a: EffectSet, b: EffectSet) EffectSet {
        return .{ .bits = a.bits | b.bits };
    }

    pub fn intersect(a: EffectSet, b: EffectSet) EffectSet {
        return .{ .bits = a.bits & b.bits };
    }

    /// Set difference: effects in `a` not in `b`.
    pub fn subtract(a: EffectSet, b: EffectSet) EffectSet {
        return .{ .bits = a.bits & ~b.bits };
    }

    pub fn contains(self: EffectSet, atom: EffectAtom) bool {
        return self.bits & atom.bit() != 0;
    }

    pub fn isEmpty(self: EffectSet) bool {
        return self.bits == 0;
    }
};

/// Strip `@comp.*` / `@meta.*` prefixes to a bare attribute key for effect lookup.
fn effectAttrKey(name: []const u8) []const u8 {
    var s = name;
    if (std.mem.startsWith(u8, s, "comp.")) {
        s = s["comp.".len..];
    } else if (std.mem.startsWith(u8, s, "meta.")) {
        s = s["meta.".len..];
    } else if (std.mem.startsWith(u8, s, "compiler.")) {
        s = s["compiler.".len..];
    }
    if (std.mem.startsWith(u8, s, "compile.")) s = s["compile.".len..];
    return s;
}

/// Does `@device(...)` name a GPU?
///
/// Two consumers used to answer this and they disagreed. `effectSetFromAttributes`
/// compared the whole trimmed token against `"metal"`, which the corpus never
/// writes — every real site spells it `@device(.metal)`, so the effect was a
/// FALSE NEGATIVE at all 6 GPU call sites. `hardwareLoweringsFromAttributes`
/// substring-searched for `"cuda"`, so `@device(cuda_helper)` was a FALSE
/// POSITIVE. Both now read the one spelling table in `directives`.
fn attrIsGpuDevice(args: ?[]const u8) bool {
    const tag = directives.attrTag(args) orelse return false;
    const target = directives.deviceFromTag(tag) orelse return false;
    return directives.deviceIsGpu(target);
}

/// Infer callee effects from function/type attributes (`@pure`, `@noalloc`, device hints).
pub fn effectSetFromAttributes(attrs: []const ast.Attribute) EffectSet {
    var set = EffectSet.empty();
    var has_pure = false;
    for (attrs) |attr| {
        const key = effectAttrKey(attr.name);
        if (std.mem.eql(u8, key, "pure")) has_pure = true;
        if (std.mem.eql(u8, key, "noalloc")) set = set.add(.noalloc);
        if (std.mem.eql(u8, key, "device")) {
            if (attrIsGpuDevice(attr.args)) set = set.add(.gpu);
        }
        if (std.mem.eql(u8, key, "compile.thread")) set = set.add(.async_suspend);
        if (std.mem.eql(u8, key, "compile.only")) set = set.add(.build);
    }
    if (has_pure) {
        const noalloc = set.contains(.noalloc);
        set = EffectSet.singleton(.pure);
        if (noalloc) set = set.add(.noalloc);
    }
    return set;
}

// ── 7. Hardware Algebra ───────────────────────────────────────────────────────

pub const HardwareFacet = enum(u8) {
    cpu = 0,
    gpu = 1,
    cache = 2,
    tensor = 3,
    warp = 4,
    registers = 5,
    memory = 6,
    simd = 7,

    pub fn name(self: HardwareFacet) []const u8 {
        return @tagName(self);
    }

    pub fn bit(self: HardwareFacet) u32 {
        return @as(u32, 1) << @intCast(@intFromEnum(self));
    }
};

pub const HardwareSet = struct {
    bits: u32 = 0,

    pub fn singleton(facet: HardwareFacet) HardwareSet {
        return .{ .bits = facet.bit() };
    }

    pub fn merge(a: HardwareSet, b: HardwareSet) HardwareSet {
        return .{ .bits = a.bits | b.bits };
    }

    pub fn add(self: HardwareSet, facet: HardwareFacet) HardwareSet {
        return .{ .bits = self.bits | facet.bit() };
    }

    /// Well-known query paths (e.g. `cpu.simd.width`) — resolved at specialize time.
    pub fn queryPath(path: []const u8) ?HardwareFacet {
        if (std.mem.indexOf(u8, path, ".simd.") != null or std.mem.startsWith(u8, path, "simd"))
            return .simd;
        if (std.mem.startsWith(u8, path, "gpu")) return .gpu;
        if (std.mem.startsWith(u8, path, "cache")) return .cache;
        if (std.mem.startsWith(u8, path, "tensor")) return .tensor;
        if (std.mem.startsWith(u8, path, "warp")) return .warp;
        if (std.mem.startsWith(u8, path, "registers")) return .registers;
        if (std.mem.startsWith(u8, path, "memory")) return .memory;
        if (std.mem.startsWith(u8, path, "cpu")) return .cpu;
        return null;
    }
};

/// Infer pipeline lowering targets from callee attributes (`@simd`, `@comp.device`, …).
pub fn hardwareLoweringsFromAttributes(attrs: []const ast.Attribute) HardwareSet {
    var set = HardwareSet.singleton(.cpu);
    for (attrs) |attr| {
        const key = effectAttrKey(attr.name);
        if (std.mem.eql(u8, key, "simd") or std.mem.eql(u8, key, "hot")) {
            set = set.add(.simd);
        }
        if (std.mem.eql(u8, key, "device")) {
            if (attrIsGpuDevice(attr.args)) set = set.add(.gpu);
        }
    }
    return set;
}

// ── 8. Pipeline Graph IR ──────────────────────────────────────────────────────

pub const PipelineOp = enum {
    source,
    map,
    filter,
    scan,
    fold,
    fuse,
    branch,
    collect,

    pub fn name(self: PipelineOp) []const u8 {
        return @tagName(self);
    }
};

pub const PipelineNode = struct {
    id: u32,
    op: PipelineOp,
    /// Lowered targets this node may become (loop, simd, gpu, coroutine, comptime).
    lowerings: HardwareSet = .{},
    knowledge: KnowledgeLevel = .unknown,
};

// ── 5. Return Packs (IR sketch) ───────────────────────────────────────────────

pub const ReturnPack = struct {
    arity: u8,
    /// Field names when destructured (`a, b = f()` or `f().x`).
    fields: ?[]const []const u8 = null,
    knowledge: KnowledgeLevel = .unknown,
    /// Consumption mode drives DCE / tail-call / pack fusion.
    consumption: enum { unused, bound, projected, spread, piped } = .unused,
};

// ── 14. Semantic Cost Model ───────────────────────────────────────────────────
//
// constitution §47: "PERFORMANCE IS NOT ONE NUMBER. A realization DOMINATES
// another when it is no worse on every relevant dimension and strictly better
// on one — a Pareto frontier, never a magical scalar."
//
// THE DIMENSION SET. §47 names twelve; this enum carried eleven, written before
// §47 and overlapping it by seven. The twelve are added rather than the eleven
// replaced (NNS FIRST: reach for the existing form), so `§47.dimensions` is a
// named SUBSET of this enum and the four extras (`bandwidth`, `determinism`,
// `agent_complexity`, `source_complexity`) stay available to transform_engine,
// which already sets them.
//
// THE HONESTY RULE, and it is the whole reason this type was rewritten: the old
// vector was `[N]f32` with `neutral()` = all zeros, so a candidate about which
// NOTHING was known compared as free on every axis and dominated everything.
// That is the fabricated-win shape §3 MEASUREMENT HONESTY was written from. A
// dimension is now UNKNOWN until a fact sets it, an unknown dimension does not
// participate in dominance, and a comparison with no participating dimension
// answers `.insufficient` — never "wins".

pub const CostDimension = enum(u8) {
    latency = 0,
    throughput = 1,
    compile_time = 2,
    binary_size = 3,
    memory = 4,
    bandwidth = 5,
    power = 6,
    determinism = 7,
    code_size = 8,
    agent_complexity = 9,
    source_complexity = 10,
    // ── the five §47 names the enum did not already carry ──
    allocations = 11,
    cache_footprint = 12,
    branch_misses = 13,
    startup = 14,
    tail_latency = 15,

    pub const count: usize = 16;

    /// §47's twelve, by this enum's spelling. `memory` is §47's "peak memory"
    /// and `power` is its "energy" — same fact, the name this file already had.
    pub const constitutional: []const CostDimension = &.{
        .latency, .throughput,  .code_size,       .compile_time,
        .memory,  .allocations, .cache_footprint, .branch_misses,
        .power,   .startup,     .binary_size,     .tail_latency,
    };

    pub fn name(self: CostDimension) []const u8 {
        return switch (self) {
            .latency => "latency",
            .throughput => "throughput",
            .compile_time => "compile_time",
            .binary_size => "binary_size",
            .memory => "memory",
            .bandwidth => "bandwidth",
            .power => "power",
            .determinism => "determinism",
            .code_size => "code_size",
            .agent_complexity => "agent_complexity",
            .source_complexity => "source_complexity",
            .allocations => "allocations",
            .cache_footprint => "cache_footprint",
            .branch_misses => "branch_misses",
            .startup => "startup",
            .tail_latency => "tail_latency",
        };
    }
};

/// How a single cost number was obtained. Ordered weakest to strongest, because
/// `law.perf.floor` turns on the ORDER: the conservative baseline is retained
/// "until another candidate is PROVEN OR MEASURED superior".
///
/// Deliberately a separate enum from `optimization_outcome.Evidence` (which
/// grades an optimization CLAIM, has `guarded`/`assumed`/`profiled`, and lives
/// in a file that imports this one). Merging them would be a mutual import to
/// save five lines.
pub const CostEvidence = enum(u8) {
    /// No fact. Never participates in a comparison.
    unknown = 0,
    /// A number the compiler made up from structure. Orders candidates; may not
    /// unseat a baseline on its own (law.perf.floor).
    estimated = 1,
    /// Derived from a fact that cannot be false for this program.
    proven = 2,
    /// Observed by running the thing, and the observation is attached.
    measured = 3,

    pub fn name(self: CostEvidence) []const u8 {
        return @tagName(self);
    }

    /// law.perf.floor's bar for replacing a retained baseline.
    pub fn unseatsBaseline(self: CostEvidence) bool {
        return self == .proven or self == .measured;
    }

    pub fn weakest(a: CostEvidence, b: CostEvidence) CostEvidence {
        return if (@intFromEnum(a) <= @intFromEnum(b)) a else b;
    }
};

/// One cost number and where it came from. `unknown` evidence means the slot
/// holds nothing at all — `value` is not to be read.
pub const CostFact = struct {
    value: f32 = 0,
    evidence: CostEvidence = .unknown,

    pub fn known(self: CostFact) bool {
        return self.evidence != .unknown;
    }
};

/// constitution §49: "The objective is an ordinary target/world fact. NO new
/// surface, no compiler modes: `target = latency` and `target = size` select
/// different frontiers of the same cost.dimensions in §47."
///
/// The objective is therefore the RELEVANCE SET of a dominance claim, and that
/// is the whole of its job here. `balanced` is every constitutional dimension,
/// which is why nothing dominates under `balanced` until everything is known —
/// the correct and deliberately expensive default.
pub const Objective = enum {
    latency,
    throughput,
    size,
    energy,
    startup,
    balanced,

    pub fn name(self: Objective) []const u8 {
        return @tagName(self);
    }

    pub fn dimensions(self: Objective) []const CostDimension {
        return switch (self) {
            .latency => &.{ .latency, .tail_latency },
            .throughput => &.{.throughput},
            .size => &.{ .binary_size, .code_size },
            .energy => &.{.power},
            .startup => &.{.startup},
            .balanced => CostDimension.constitutional,
        };
    }

    pub fn fromName(s: []const u8) ?Objective {
        return std.meta.stringToEnum(Objective, s);
    }
};

/// The result of one Pareto comparison, with everything `why(realize)` and
/// `why(skip)` need to answer without re-deriving anything.
pub const DominanceVerdict = struct {
    pub const Relation = enum {
        /// `a` is no worse everywhere it can be compared, and better somewhere.
        dominates,
        /// `b` is, symmetrically.
        dominated,
        /// each is better on some dimension — the frontier holds both.
        incomparable,
        /// every comparable dimension is equal.
        equal,
        /// no dimension is known on both sides. NOT a tie, NOT a win.
        insufficient,
    };

    relation: Relation,
    /// Dimensions known on BOTH sides and relevant. The denominator of the claim.
    compared: u8,
    /// RELEVANT dimensions with no fact on one side or the other. The honest
    /// counterweight to `compared`: a claim of "no worse on every relevant
    /// dimension" is not established while this is nonzero, however good the
    /// dimensions that ARE known look.
    missing: u8,
    /// Of those compared, how many `a` was strictly better on.
    better: u8,
    /// Of those compared, how many `a` was strictly worse on.
    worse: u8,
    /// The first dimension `a` was strictly better on, if any.
    decided_by: ?CostDimension,
    /// Weakest evidence over the compared dimensions. law.perf.floor reads this.
    evidence: CostEvidence,

    pub fn relationName(self: DominanceVerdict) []const u8 {
        return @tagName(self.relation);
    }

    /// `law.perf.floor`'s exact bar for replacing a RETAINED baseline. Three
    /// conditions, each of which has to hold on its own:
    ///   1. dominance on the frontier (§47);
    ///   2. the objective's relevance set fully covered — no unknown may be
    ///      read as "no worse";
    ///   3. evidence `proven` or `measured` — §47's own words.
    pub fn unseats(self: DominanceVerdict) bool {
        return self.relation == .dominates and self.missing == 0 and self.evidence.unseatsBaseline();
    }
};

/// Multidimensional cost. Lower is better on every dimension in this enum.
pub const CostVector = struct {
    facts: [CostDimension.count]CostFact = @splat(.{}),

    /// All dimensions UNKNOWN. Named `neutral` because callers already say that;
    /// what changed is that neutral now means "no facts", not "free".
    pub fn neutral() CostVector {
        return .{};
    }

    pub fn get(self: CostVector, dim: CostDimension) CostFact {
        return self.facts[@intFromEnum(dim)];
    }

    pub fn knownCount(self: CostVector) u8 {
        var n: u8 = 0;
        for (self.facts) |f| {
            if (f.known()) n += 1;
        }
        return n;
    }

    /// Back-compatible setter. An unqualified number is an ESTIMATE — the
    /// callers that used this (transform_engine's cost hints) never measured
    /// anything, and labelling their numbers `proven` would be the lie.
    pub fn set(self: *CostVector, dim: CostDimension, v: f32) void {
        self.facts[@intFromEnum(dim)] = .{ .value = v, .evidence = .estimated };
    }

    pub fn setFact(self: *CostVector, dim: CostDimension, v: f32, ev: CostEvidence) void {
        self.facts[@intFromEnum(dim)] = .{ .value = v, .evidence = ev };
    }

    /// Sum of two vectors. A dimension unknown on either side stays UNKNOWN —
    /// adding a fact to a non-fact does not produce a fact. Evidence of a sum is
    /// the weaker of its parts.
    pub fn add(a: CostVector, b: CostVector) CostVector {
        var out: CostVector = .{};
        for (0..CostDimension.count) |i| {
            if (!a.facts[i].known() or !b.facts[i].known()) continue;
            out.facts[i] = .{
                .value = a.facts[i].value + b.facts[i].value,
                .evidence = CostEvidence.weakest(a.facts[i].evidence, b.facts[i].evidence),
            };
        }
        return out;
    }

    /// Pareto comparison over `relevant` (null = every dimension). §47: no worse
    /// on every relevant dimension, strictly better on one.
    pub fn compare(a: CostVector, b: CostVector, relevant: ?[]const CostDimension) DominanceVerdict {
        var compared: u8 = 0;
        var missing: u8 = 0;
        var better: u8 = 0;
        var worse: u8 = 0;
        var decided_by: ?CostDimension = null;
        var ev: CostEvidence = .measured;

        const dims = relevant orelse CostDimension.constitutional;
        for (dims) |dim| {
            const i = @intFromEnum(dim);
            const fa = a.facts[i];
            const fb = b.facts[i];
            if (!fa.known() or !fb.known()) {
                missing += 1;
                continue;
            }
            compared += 1;
            ev = CostEvidence.weakest(ev, CostEvidence.weakest(fa.evidence, fb.evidence));
            if (fa.value < fb.value) {
                better += 1;
                if (decided_by == null) decided_by = dim;
            } else if (fa.value > fb.value) {
                worse += 1;
            }
        }

        const relation: DominanceVerdict.Relation = blk: {
            if (compared == 0) break :blk .insufficient;
            if (better > 0 and worse == 0) break :blk .dominates;
            if (worse > 0 and better == 0) break :blk .dominated;
            if (better > 0 and worse > 0) break :blk .incomparable;
            break :blk .equal;
        };
        return .{
            .relation = relation,
            .compared = compared,
            .missing = missing,
            .better = better,
            .worse = worse,
            .decided_by = decided_by,
            .evidence = if (compared == 0) .unknown else ev,
        };
    }

    /// `a` strictly dominates `b` under §47. Kept as the one-word question the
    /// old API asked, now answered from `compare` so the two cannot drift.
    pub fn dominates(a: CostVector, b: CostVector) bool {
        return a.compare(b, null).relation == .dominates;
    }
};

test "cost: an unknown dimension never participates" {
    var a = CostVector.neutral();
    var b = CostVector.neutral();
    // `a` knows one thing and is better at it; `b` knows nothing at all.
    a.setFact(.latency, 1.0, .measured);
    b.setFact(.compile_time, 9.0, .measured);
    const v = a.compare(b, null);
    // Zero dimensions known on BOTH sides -> no verdict. The old all-zero vector
    // answered "a dominates b" here, which is the bug this test exists for.
    try std.testing.expectEqual(DominanceVerdict.Relation.insufficient, v.relation);
    try std.testing.expectEqual(@as(u8, 0), v.compared);
    try std.testing.expect(!a.dominates(b));
}

test "cost: dominance needs no-worse everywhere and better somewhere" {
    var a = CostVector.neutral();
    var b = CostVector.neutral();
    a.setFact(.latency, 1.0, .measured);
    a.setFact(.binary_size, 5.0, .measured);
    b.setFact(.latency, 2.0, .measured);
    b.setFact(.binary_size, 5.0, .measured);
    const v = a.compare(b, null);
    try std.testing.expectEqual(DominanceVerdict.Relation.dominates, v.relation);
    try std.testing.expectEqual(@as(u8, 2), v.compared);
    try std.testing.expectEqual(@as(u8, 1), v.better);
    try std.testing.expectEqual(CostDimension.latency, v.decided_by.?);

    // Better on latency, worse on size: the frontier holds BOTH. This is the
    // case a scalar cost model destroys by summing.
    b.setFact(.binary_size, 4.0, .measured);
    try std.testing.expectEqual(DominanceVerdict.Relation.incomparable, a.compare(b, null).relation);
    try std.testing.expectEqual(DominanceVerdict.Relation.incomparable, b.compare(a, null).relation);
}

test "cost: verdict evidence is the weakest fact compared" {
    var a = CostVector.neutral();
    var b = CostVector.neutral();
    a.setFact(.latency, 1.0, .measured);
    b.setFact(.latency, 2.0, .estimated);
    const v = a.compare(b, null);
    try std.testing.expectEqual(DominanceVerdict.Relation.dominates, v.relation);
    try std.testing.expectEqual(CostEvidence.estimated, v.evidence);
    // law.perf.floor: an estimate may not unseat a retained baseline.
    try std.testing.expect(!v.evidence.unseatsBaseline());
    a.setFact(.latency, 1.0, .proven);
    b.setFact(.latency, 2.0, .proven);
    try std.testing.expect(a.compare(b, null).evidence.unseatsBaseline());
}

test "cost: an unknown relevant dimension blocks unseating, however good the rest look" {
    var a = CostVector.neutral();
    var b = CostVector.neutral();
    // Native is PROVEN better on compile time and nothing else is known.
    a.setFact(.compile_time, 1.0, .proven);
    b.setFact(.compile_time, 2.0, .proven);

    // Under `balanced` — every constitutional dimension is relevant — this is
    // dominance on the one axis anybody looked at, and it must NOT unseat a
    // retained baseline. Eleven unknowns are eleven unasked questions.
    const wide = a.compare(b, Objective.balanced.dimensions());
    try std.testing.expectEqual(DominanceVerdict.Relation.dominates, wide.relation);
    try std.testing.expectEqual(@as(u8, 1), wide.compared);
    try std.testing.expectEqual(@as(u8, 11), wide.missing);
    try std.testing.expect(wide.evidence.unseatsBaseline());
    try std.testing.expect(!wide.unseats());

    // Declare an objective the facts actually cover and the same numbers decide.
    var lat_a = CostVector.neutral();
    var lat_b = CostVector.neutral();
    lat_a.setFact(.latency, 1.0, .measured);
    lat_a.setFact(.tail_latency, 1.0, .measured);
    lat_b.setFact(.latency, 2.0, .measured);
    lat_b.setFact(.tail_latency, 2.0, .measured);
    const narrow = lat_a.compare(lat_b, Objective.latency.dimensions());
    try std.testing.expectEqual(@as(u8, 0), narrow.missing);
    try std.testing.expect(narrow.unseats());
}

test "cost: §49 objectives select different frontiers of the same facts" {
    var fast_big = CostVector.neutral();
    var slow_small = CostVector.neutral();
    fast_big.setFact(.latency, 1.0, .measured);
    fast_big.setFact(.tail_latency, 1.0, .measured);
    fast_big.setFact(.binary_size, 9.0, .measured);
    fast_big.setFact(.code_size, 9.0, .measured);
    slow_small.setFact(.latency, 4.0, .measured);
    slow_small.setFact(.tail_latency, 4.0, .measured);
    slow_small.setFact(.binary_size, 2.0, .measured);
    slow_small.setFact(.code_size, 2.0, .measured);

    try std.testing.expect(fast_big.compare(slow_small, Objective.latency.dimensions()).unseats());
    try std.testing.expect(!fast_big.compare(slow_small, Objective.size.dimensions()).unseats());
    try std.testing.expect(slow_small.compare(fast_big, Objective.size.dimensions()).unseats());
    // Under `balanced` neither wins: this is the Pareto frontier holding two
    // realizations, which is the §47 behaviour a scalar cost would destroy.
    try std.testing.expectEqual(
        DominanceVerdict.Relation.incomparable,
        fast_big.compare(slow_small, Objective.balanced.dimensions()).relation,
    );
    try std.testing.expectEqual(Objective.size, Objective.fromName("size").?);
    try std.testing.expect(Objective.fromName("fastest") == null);
}

test "cost: §47 names twelve dimensions and all twelve exist" {
    try std.testing.expectEqual(@as(usize, 12), CostDimension.constitutional.len);
    var seen: [CostDimension.count]bool = @splat(false);
    for (CostDimension.constitutional) |d| {
        const i = @intFromEnum(d);
        try std.testing.expect(!seen[i]); // no duplicate row
        seen[i] = true;
    }
}

// ── 10. Convergence catalog (audit spine) ─────────────────────────────────────

pub const ConvergenceStatus = enum {
    converged,
    partial,
    planned,
};

pub const ConvergenceEntry = struct {
    id: []const u8,
    legacy_mechanisms: []const []const u8,
    unified_algebra: []const u8,
    status: ConvergenceStatus,
    priority: u8,
    notes: []const u8,
};

pub const convergence_catalog: []const ConvergenceEntry = &.{
    .{
        .id = "knowledge_lattice",
        .legacy_mechanisms = &.{
            "known type",    "known value",        "known shape", "StorageClass",
            "comptime fold", "native_scalar_mode",
        },
        .unified_algebra = "KnowledgeLevel lattice (unknown→native)",
        .status = .partial,
        .priority = 1,
        .notes = "knowledgeOfType/lowersToNativeC; module_knowledge + moduleUsesFullNativeLowering in codegen.",
    },
    .{
        .id = "descriptor_algebra",
        .legacy_mechanisms = &.{
            "types", "concepts", "derive", "protocols", "enum", "module", "schema", "@comp.*",
        },
        .unified_algebra = "DescriptorExpr + DescriptorOp (+, −, ∩, restrict, transform)",
        .status = .partial,
        .priority = 2,
        .notes = "Alias lift builds DescriptorExpr atoms/composition; graph exports descriptor_hash+label.",
    },
    .{
        .id = "shape_algebra",
        .legacy_mechanisms = &.{
            "StorageClass", "@sealed", "table_shape nodes", "@comp.type.shape", "record dedup",
        },
        .unified_algebra = "ShapeOp (seal/open/merge/project/freeze/specialize/lift/lower)",
        .status = .partial,
        .priority = 3,
        .notes = "Graph lift attaches shape.lift/seal/specialize via transform_engine; JSON exports transform_app.",
    },
    .{
        .id = "call_algebra",
        .legacy_mechanisms = &.{
            "call codegen", "mono", "inline hints", "native_scalar_funcs", "lua_invoke",
        },
        .unified_algebra = "CallSite semantic object + transform pipeline",
        .status = .partial,
        .priority = 4,
        .notes = "CallSite on graph lift; call.memo/inline/specialize/simd dispatch in codegen; provenance harness.",
    },
    .{
        .id = "transformation_registry",
        .legacy_mechanisms = &.{
            "comptimeMetaHook", "fold_meta_string_expr", "meta_codegen", "optimizer passes",
        },
        .unified_algebra = "transform_engine: graph→graph + contract + budget + provenance",
        .status = .partial,
        .priority = 5,
        .notes = "Registry stub live; shape.* + comp.* descriptors; dispatch still fragmented in codegen.",
    },
    .{
        .id = "stage_polymorphism",
        .legacy_mechanisms = &.{
            "comptime", "constexpr", "@()", "build_framework stages", "link-time",
        },
        .unified_algebra = "Stage enum + per-site stage metadata",
        .status = .planned,
        .priority = 6,
        .notes = "Replaces compile-time/runtime dichotomy.",
    },
    .{
        .id = "pipeline_graph_ir",
        .legacy_mechanisms = &.{
            "|> pipeline", "std.pipeline", "pipeline_gen.zig",
        },
        .unified_algebra = "PipelineNode graph with multi-target lowering",
        .status = .partial,
        .priority = 7,
        .notes = "Graph lift pipeline nodes; pipeline.* registered in transform_engine; fused backend via pipeline_gen pending.",
    },
    .{
        .id = "effect_algebra",
        .legacy_mechanisms = &.{
            "@pure", "@noalloc", "capabilities (planned)", "arc pass",
        },
        .unified_algebra = "EffectSet composable descriptors",
        .status = .partial,
        .priority = 8,
        .notes = "effectSetFromAttributes + callSiteFromShapeWithEffects; codegen func_decls lookup.",
    },
    .{
        .id = "hardware_algebra",
        .legacy_mechanisms = &.{
            "@simd", "@gpu", "@comp.device", "ml_kernels", "native_backend",
        },
        .unified_algebra = "HardwareSet + queryPath specialization",
        .status = .planned,
        .priority = 9,
        .notes = "cpu.simd.width style queries become ordinary specialize facts.",
    },
    .{
        .id = "return_packs",
        .legacy_mechanisms = &.{
            "multi-return", "vararg", "tail expr", "destructure assign",
        },
        .unified_algebra = "ReturnPack IR + consumption modes",
        .status = .planned,
        .priority = 10,
        .notes = "parse().x / spread / :map on returns without allocation.",
    },
    .{
        .id = "pattern_recognition",
        .legacy_mechanisms = &.{
            "match", "handlers[color]", "jump tables in codegen",
        },
        .unified_algebra = "Descriptor dispatch → perfect hash / switch / direct call",
        .status = .planned,
        .priority = 11,
        .notes = "No new keywords; compiler recognizes handler-table shape.",
    },
    .{
        .id = "reflection_as_query",
        .legacy_mechanisms = &.{
            "reflection APIs", "@comp.type.*", "LSP hover (partial)",
        },
        .unified_algebra = "Point.fields / .shape / .stage / .effects as descriptor queries",
        .status = .partial,
        .priority = 12,
        .notes = "@comp.type.shape/why/origin are early reflection-via-descriptor.",
    },
};

pub fn statusName(s: ConvergenceStatus) []const u8 {
    return switch (s) {
        .converged => "converged",
        .partial => "partial",
        .planned => "planned",
    };
}

/// JSON catalog for `duo algebra` and agent introspection.
pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("{{\"algebras\":{{", .{});
    try w.print("\"knowledge\":[\"unknown\",\"observed\",\"guarded\",\"stable\",\"frozen\",\"comptime\",\"native\"],", .{});
    try w.print("\"stages\":[\"parse\",\"sema\",\"transform\",\"compile\",\"link\",\"runtime\",\"deploy\",\"gpu\"],", .{});
    try w.print("\"descriptor_ops\":[\"add\",\"sub\",\"intersect\",\"restrict\",\"transform\"],", .{});
    try w.print("\"shape_ops\":[\"seal\",\"open\",\"merge\",\"subtract\",\"project\",\"rename\",\"freeze\",\"specialize\",\"lift\",\"lower\"],", .{});
    try w.print("\"call_transforms\":[\"inline\",\"specialize\",\"memo\",\"devirtualize\",\"gpu_lower\",\"simd_lower\"],", .{});
    try w.print("\"pipeline_ops\":[\"source\",\"map\",\"filter\",\"scan\",\"fold\",\"fuse\",\"branch\",\"collect\"],", .{});
    try w.print("\"cost_dimensions\":[\"latency\",\"throughput\",\"compile_time\",\"binary_size\",\"memory\",\"bandwidth\",\"power\",\"determinism\",\"code_size\",\"agent_complexity\",\"source_complexity\"]", .{});
    try w.print("}},\"convergence\":[\n", .{});

    for (convergence_catalog, 0..) |e, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"{s}\",\"unified\":\"{s}\",\"status\":\"{s}\",\"priority\":{d},\"legacy\":[", .{
            e.id, e.unified_algebra, statusName(e.status), e.priority,
        });
        for (e.legacy_mechanisms, 0..) |m, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("\"{s}\"", .{m});
        }
        try w.print("],\"notes\":\"", .{});
        for (e.notes) |c| {
            switch (c) {
                '\\', '"' => try w.print("\\{c}", .{c}),
                else => try w.writeAll(&.{c}),
            }
        }
        try w.print("\"}}", .{});
    }
    try w.print("\n]}}\n", .{});
}

// ── Pass 2.1: Knowledge lattice ↔ ResolvedType bridge ────────────────────────

/// Map a sema-resolved type to its position on the knowledge lattice.
pub fn knowledgeOfType(rt: types.ResolvedType) KnowledgeLevel {
    return switch (rt) {
        .any, .nil => .observed,
        .never => .frozen,
        .void,
        .i8,
        .i16,
        .i32,
        .i64,
        .u8,
        .u16,
        .u32,
        .u64,
        .f32,
        .f64,
        .bool,
        .str,
        .v4f64,
        .v4i64,
        .v8f32,
        .v8i32,
        => .native,
        .table_type => |t| KnowledgeLevel.fromStorageClass(t.storage_class),
        .func => |f| blk: {
            if (f.is_compile_only) break :blk .at_comptime;
            if (f.is_native) break :blk .native;
            break :blk .observed;
        },
        .enum_type, .@"struct" => .stable,
        .array => |a| KnowledgeLevel.meet(knowledgeOfType(a.elem.*), .guarded),
        .pointer => |p| knowledgeOfType(p.*),
        .result => |r| KnowledgeLevel.meet(knowledgeOfType(r.ok.*), knowledgeOfType(r.err.*)),
        .option => |o| knowledgeOfType(o.*),
        .channel => .guarded,
        .generic_param => .unknown,
        .instantiated => |i| knowledgeOfType(i.base.*),
        .tensor => .at_comptime,
    };
}

pub fn knowledgeAtLeastType(rt: types.ResolvedType, min: KnowledgeLevel) bool {
    return knowledgeOfType(rt).dominates(min);
}

/// Pass 2 lattice form of `ResolvedType.is_native()` — no lua_Value lowering.
pub fn lowersToNativeC(rt: types.ResolvedType) bool {
    return knowledgeAtLeastType(rt, .native);
}

// ── Pass 2.1: Call Algebra ↔ CallShape bridge ─────────────────────────────────

/// Evaluation stage for a call site inferred from AST CallShape.
pub fn stageOfCallShape(shape: types.CallShape) Stage {
    return switch (shape.callee_kind) {
        .comptime_known => .compile,
        else => .runtime,
    };
}

/// Knowledge lattice position for a call site from conservative CallShape facts.
pub fn knowledgeOfCallShape(shape: types.CallShape) KnowledgeLevel {
    return switch (shape.callee_kind) {
        .comptime_known => .at_comptime,
        .direct => if (shape.callee_name != null) .stable else .observed,
        .method => if (shape.receiver_shape_known) .stable else .observed,
        .indirect => .observed,
    };
}

/// Build a CallSite semantic object from an inferred CallShape (graph lift / sema).
pub fn callSiteFromShape(shape: types.CallShape) CallSite {
    return callSiteFromShapeWithEffects(shape, .{});
}

/// CallSite with callee effect facts merged (Pass 2.2 effect algebra bridge).
pub fn callSiteFromShapeWithEffects(shape: types.CallShape, callee_effects: EffectSet) CallSite {
    return callSiteFromShapeWithCalleeFacts(shape, callee_effects, .{});
}

/// CallSite with callee effect + hardware facts (Pass 2.5 call transform bridge).
pub fn callSiteFromShapeWithCalleeFacts(
    shape: types.CallShape,
    callee_effects: EffectSet,
    hardware: HardwareSet,
) CallSite {
    var site: CallSite = .{
        .callee = shape.callee_name,
        .receiver = shape.method_name,
        .stage = stageOfCallShape(shape),
        .knowledge = knowledgeOfCallShape(shape),
        .effects = callee_effects,
        .hardware = hardware,
        .is_pure = shape.callee_kind == .comptime_known or callee_effects.contains(.pure),
    };
    site.return_arity = switch (shape.return_consumption) {
        .discard => 0,
        .single => 1,
        .multi => null,
        .unknown => null,
    };
    return site;
}

/// Map a ShapeOp to its transform registry id (`shape.seal`, `shape.lift`, …).
pub fn shapeTransformId(op: ShapeOp) []const u8 {
    return switch (op) {
        .seal => "shape.seal",
        .open => "shape.open",
        .merge => "shape.merge",
        .subtract => "shape.subtract",
        .project => "shape.project",
        .rename => "shape.rename",
        .freeze => "shape.freeze",
        .specialize => "shape.specialize",
        .lift => "shape.lift",
        .lower => "shape.lower",
    };
}

/// Resolve `shape.*` transform id back to ShapeOp (null if unknown).
pub fn shapeOpFromTransformId(id: []const u8) ?ShapeOp {
    inline for (@typeInfo(ShapeOp).@"enum".field_names, @typeInfo(ShapeOp).@"enum".field_values) |_, value| {
        const op: ShapeOp = @enumFromInt(value);
        if (std.mem.eql(u8, id, shapeTransformId(op))) return op;
    }
    return null;
}

// ── Pass 2.2: Call transforms (CallSite → graph rewrite) ─────────────────────

/// Optimizations that rewrite CallSite semantic objects (not surface syntax).
pub const CallTransform = enum {
    @"inline",
    specialize,
    memo,
    devirtualize,
    gpu_lower,
    simd_lower,

    pub fn name(self: CallTransform) []const u8 {
        return switch (self) {
            .@"inline" => "inline",
            else => @tagName(self),
        };
    }
};

pub fn callTransformId(op: CallTransform) []const u8 {
    return switch (op) {
        .@"inline" => "call.inline",
        .specialize => "call.specialize",
        .memo => "call.memo",
        .devirtualize => "call.devirtualize",
        .gpu_lower => "call.gpu_lower",
        .simd_lower => "call.simd_lower",
    };
}

pub fn callTransformFromId(id: []const u8) ?CallTransform {
    inline for (@typeInfo(CallTransform).@"enum".field_names, @typeInfo(CallTransform).@"enum".field_values) |_, value| {
        const op: CallTransform = @enumFromInt(value);
        if (std.mem.eql(u8, id, callTransformId(op))) return op;
    }
    return null;
}

/// Conservative transform eligibility from a CallSite + CallShape.
pub fn callTransformEligible(op: CallTransform, site: CallSite, shape: types.CallShape) bool {
    return switch (op) {
        .@"inline" => site.callee != null and site.knowledge.dominates(.stable),
        .specialize => blk: {
            if (shape.isSpecializable()) break :blk true;
            if (shape.callee_kind == .direct and shape.callee_name != null) break :blk true;
            if (shape.callee_kind == .comptime_known) break :blk true;
            break :blk site.knowledge.dominates(.stable);
        },
        .memo => site.is_pure and site.knowledge.dominates(.at_comptime),
        .devirtualize => site.receiver != null and site.knowledge.dominates(.stable),
        .gpu_lower => site.hardware.bits & HardwareFacet.gpu.bit() != 0,
        .simd_lower => site.hardware.bits & HardwareFacet.simd.bit() != 0,
    };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "knowledge lattice: join and meet" {
    try std.testing.expectEqual(KnowledgeLevel.native, KnowledgeLevel.join(.observed, .native));
    try std.testing.expectEqual(KnowledgeLevel.guarded, KnowledgeLevel.meet(.native, .guarded));
    try std.testing.expect(KnowledgeLevel.native.dominates(.at_comptime));
}

test "knowledge lattice: storage class bridge" {
    try std.testing.expectEqual(KnowledgeLevel.native, KnowledgeLevel.fromStorageClass(.native));
    try std.testing.expectEqual(KnowledgeLevel.guarded, KnowledgeLevel.fromStorageClass(.guarded));
    try std.testing.expectEqual(KnowledgeLevel.stable, KnowledgeLevel.fromStorageClass(.sealed));
}

test "effect algebra: union subtract intersect" {
    const net = EffectSet.singleton(.network);
    const fs = EffectSet.singleton(.filesystem);
    const both = EffectSet.merge(net, fs);
    try std.testing.expect(both.contains(.network));
    try std.testing.expect(both.contains(.filesystem));
    const net_only = EffectSet.subtract(both, fs);
    try std.testing.expect(net_only.contains(.network));
    try std.testing.expect(!net_only.contains(.filesystem));
    try std.testing.expectEqual(@as(u32, net.bits), EffectSet.intersect(both, net).bits);
}

test "shape algebra: seal raises knowledge" {
    try std.testing.expectEqual(
        KnowledgeLevel.stable,
        ShapeOp.resultingKnowledge(.seal, .observed),
    );
    try std.testing.expectEqual(
        KnowledgeLevel.native,
        ShapeOp.resultingKnowledge(.lower, .at_comptime),
    );
}

test "cost vector: pareto dominance" {
    var a = CostVector.neutral();
    var b = CostVector.neutral();
    a.set(.latency, 1.0);
    b.set(.latency, 2.0);
    try std.testing.expect(a.dominates(b));
    try std.testing.expect(!b.dominates(a));
}

test "convergence catalog: ranked priorities" {
    try std.testing.expect(convergence_catalog.len >= 8);
    try std.testing.expectEqualStrings("knowledge_lattice", convergence_catalog[0].id);
    try std.testing.expect(convergence_catalog[0].priority <= convergence_catalog[1].priority);
}

test "hardware queryPath" {
    try std.testing.expectEqual(HardwareFacet.simd, HardwareSet.queryPath("cpu.simd.width").?);
    try std.testing.expectEqual(HardwareFacet.gpu, HardwareSet.queryPath("gpu.shared").?);
}

test "knowledgeOfType: aligns with is_native for scalars and tables" {
    try std.testing.expectEqual(KnowledgeLevel.native, knowledgeOfType(.i64));
    try std.testing.expectEqual(KnowledgeLevel.observed, knowledgeOfType(.any));
    try std.testing.expect(lowersToNativeC(.i64));
    try std.testing.expect(!lowersToNativeC(.any));
    try std.testing.expectEqual(
        lowersToNativeC(.i64),
        (@as(types.ResolvedType, .i64)).is_native(),
    );
    var native_fields = [_]types.FieldType{
        .{ .name = "x", .typ = .i64 },
        .{ .name = "y", .typ = .i64 },
    };
    const native_table = types.ResolvedType{
        .table_type = .{
            .fields = native_fields[0..],
            .storage_class = .native,
        },
    };
    try std.testing.expect(lowersToNativeC(native_table));
    try std.testing.expectEqual(
        native_table.is_native(),
        lowersToNativeC(native_table),
    );
    var dynamic_fields = [_]types.FieldType{.{ .name = "x", .typ = .any }};
    const dynamic_table = types.ResolvedType{
        .table_type = .{
            .fields = dynamic_fields[0..],
            .storage_class = .dynamic,
        },
    };
    try std.testing.expect(!lowersToNativeC(dynamic_table));
    try std.testing.expectEqual(KnowledgeLevel.observed, knowledgeOfType(dynamic_table));
}

test "callSiteFromShape: comptime vs runtime" {
    const comptime_shape = types.CallShape{
        .callee_kind = .comptime_known,
        .callee_name = "comp.map",
        .arg_count = 2,
        .return_consumption = .single,
    };
    const site = callSiteFromShape(comptime_shape);
    try std.testing.expectEqual(Stage.compile, site.stage);
    try std.testing.expectEqual(KnowledgeLevel.at_comptime, site.knowledge);
    try std.testing.expect(site.is_pure);

    const direct = types.CallShape{
        .callee_kind = .direct,
        .callee_name = "add",
        .arg_count = 2,
    };
    const rt_site = callSiteFromShape(direct);
    try std.testing.expectEqual(Stage.runtime, rt_site.stage);
    try std.testing.expectEqual(KnowledgeLevel.stable, rt_site.knowledge);
}

test "shapeTransformId roundtrip" {
    try std.testing.expectEqualStrings("shape.seal", shapeTransformId(.seal));
    try std.testing.expectEqual(ShapeOp.lift, shapeOpFromTransformId("shape.lift").?);
}

test "effectSetFromAttributes: pure and noalloc" {
    const attrs = [_]ast.Attribute{
        .{ .name = "pure", .args = null },
        .{ .name = "comp.compile.noalloc", .args = null },
    };
    const effects = effectSetFromAttributes(&attrs);
    try std.testing.expect(effects.contains(.pure));
}

test "device attribute: the corpus spelling reaches both consumers" {
    // `@device(.metal)` is how every real site writes it. The effect set used
    // to compare the whole token against "metal" and therefore never fired;
    // the hardware set substring-matched and did. They must now agree.
    const attrs = [_]ast.Attribute{.{ .name = "device", .args = ".metal" }};
    try std.testing.expect(effectSetFromAttributes(&attrs).contains(.gpu));
    try std.testing.expect(hardwareLoweringsFromAttributes(&attrs).bits & HardwareFacet.gpu.bit() != 0);
}

test "device attribute: a name that merely contains a device is not one" {
    // `indexOf(args, "cuda")` made this a GPU function.
    const attrs = [_]ast.Attribute{.{ .name = "device", .args = "cuda_helper" }};
    try std.testing.expect(!effectSetFromAttributes(&attrs).contains(.gpu));
    try std.testing.expect(hardwareLoweringsFromAttributes(&attrs).bits & HardwareFacet.gpu.bit() == 0);
}

test "device attribute: undotted and quoted spellings agree with dotted" {
    inline for (.{ ".cuda", "cuda", "\"cuda\"" }) |spelling| {
        const attrs = [_]ast.Attribute{.{ .name = "device", .args = spelling }};
        try std.testing.expect(effectSetFromAttributes(&attrs).contains(.gpu));
    }
    // Positive control: a CPU device must not read as GPU through any of them.
    const cpu = [_]ast.Attribute{.{ .name = "device", .args = ".cpu" }};
    try std.testing.expect(!effectSetFromAttributes(&cpu).contains(.gpu));
}

test "collectDeriveTraitNames: quoted and bare lists give the same names" {
    const alloc = std.testing.allocator;
    inline for (.{ "Display, Eq", "\"Display\", \"Eq\"" }) |spelling| {
        const attrs = [_]ast.Attribute{.{ .name = "derive", .args = spelling }};
        const names = try collectDeriveTraitNames(&attrs, alloc);
        defer {
            for (names) |n| alloc.free(n);
            alloc.free(names);
        }
        try std.testing.expectEqual(@as(usize, 2), names.len);
        try std.testing.expectEqualStrings("Display", names[0]);
        try std.testing.expectEqualStrings("Eq", names[1]);
    }
}

test "callSiteFromShapeWithEffects: callee pure propagates" {
    const shape = types.CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 0 };
    const site = callSiteFromShapeWithEffects(shape, EffectSet.singleton(.pure));
    try std.testing.expect(site.is_pure);
    try std.testing.expect(site.effects.contains(.pure));
}

test "callSiteFromShapeWithCalleeFacts: hardware enables simd_lower" {
    const attrs = [_]ast.Attribute{.{ .name = "hot", .args = null }};
    const hw = hardwareLoweringsFromAttributes(&attrs);
    const shape = types.CallShape{ .callee_kind = .direct, .callee_name = "scale", .arg_count = 1 };
    const site = callSiteFromShapeWithCalleeFacts(shape, .{}, hw);
    try std.testing.expect(callTransformEligible(.simd_lower, site, shape));
    try std.testing.expect(!callTransformEligible(.gpu_lower, site, shape));
}

test "callTransformId roundtrip and eligibility" {
    try std.testing.expectEqualStrings("call.inline", callTransformId(.@"inline"));
    try std.testing.expectEqual(CallTransform.specialize, callTransformFromId("call.specialize").?);
    const direct = types.CallShape{
        .callee_kind = .direct,
        .callee_name = "add",
        .arg_count = 2,
    };
    const site = callSiteFromShape(direct);
    try std.testing.expect(callTransformEligible(.@"inline", site, direct));
    try std.testing.expect(callTransformEligible(.specialize, site, direct));
    const indirect = types.CallShape{ .callee_kind = .indirect, .arg_count = 1 };
    const indirect_site = callSiteFromShape(indirect);
    try std.testing.expect(!callTransformEligible(.@"inline", indirect_site, indirect));
    try std.testing.expect(!callTransformEligible(.specialize, indirect_site, indirect));
}

test "descriptor algebra: alias atom and composition" {
    var builder = DescriptorExprBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const point = try buildAliasDescriptorExpr(&builder, "Point", null, null, .native);
    try std.testing.expect(descriptorIsAtom(point));
    try std.testing.expectEqualStrings("Point", point.atom.?.name);

    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Point", formatDescriptorExprShort(point, &buf));

    const sprite = try buildAliasDescriptorExpr(&builder, "Sprite", "Point", null, .native);
    try std.testing.expectEqualStrings("Point+Sprite", formatDescriptorExprShort(sprite, &buf));

    const h1 = descriptorStructuralHash(point);
    const h2 = descriptorStructuralHash(sprite);
    try std.testing.expect(h1 != h2);

    const colored = try buildAliasDescriptorExpr(&builder, "Colored", null, "Named", .stable);
    try std.testing.expectEqualStrings("Named+Colored", formatDescriptorExprShort(colored, &buf));
}

test "descriptor algebra: derive traits as transform chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var builder = DescriptorExprBuilder.init(alloc);
    defer builder.deinit();
    const attrs = [_]ast.Attribute{
        .{ .name = "derive", .args = "Display, Eq, Add" },
    };
    const vec = try buildAliasDescriptorExprWithDerives(
        &builder,
        "Vec2",
        null,
        null,
        .native,
        &attrs,
        alloc,
    );
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Vec2~Display~Eq~Add", formatDescriptorExprShort(vec, &buf));
}
