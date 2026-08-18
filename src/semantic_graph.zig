/// Resident semantic graph.
///
/// An `id` names one exact entity in this resident graph. Names,
/// paths, spans, and fingerprints are provenance or query projections; none of
/// them can create or recover semantic identity.
const std = @import("std");
const ast = @import("ast.zig");
const native_bootstrap = @import("native_bootstrap.zig");
const home_resolve = @import("home_resolve.zig");
const Expr = ast.Expr;
const sema = @import("sema.zig");
const types = @import("types.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const place = @import("place.zig");
const region = @import("region.zig");
const subject_home = @import("subject_home.zig");
pub const id = u32;

pub const State = enum {
    frozen_snapshot,
    open_semantic,
    sealed,
    derived,
    mutable_builder,

    pub fn name(self: State) []const u8 {
        return @tagName(self);
    }
};

// `Recursion`, `Completion`, `DescriptorRefWalk`,
// `classifyDescriptorRecursionFromEdges`, `resolveDescriptorCompletion` and
// `SemanticGraph.descriptorRecursion` lived here. The classifier walked the
// whole `.descriptor_ref` closure of every table shape on every compile, and
// its two answers went into `Node.recursion`/`Node.completion`, which were read
// by one `writeJson` arm each and by nothing else in either tree. The public
// `descriptorRecursion` had callers only in this file's own tests. Deleted
// under HPLS §7-8; the `.descriptor_ref` EDGES stay, because
// `hasDescriptorFacts`/`hasTableDescriptorFacts` do read them.

fn inferDescriptorState(is_sealed: bool) State {
    if (is_sealed) return .sealed;
    return .open_semantic;
}

fn shapeKnowledge(is_sealed: bool) semantic_algebra.KnowledgeLevel {
    if (is_sealed) return .stable;
    return .observed;
}

/// Physical tags only. None own semantic meaning. Meaning lives in graph ids
/// and facts (home/member/provenance, binding, application, descriptor, stage,
/// realization). Tags remain while facts are incomplete; they must not be
/// consulted as a second ontology. Deleted unused tags: source_file, concept,
/// comptime_value, emit_artifact, type_node (members are values with descriptor
/// facts — not a type ontology).
pub const NodeKind = enum {
    module,
    func,
    param,
    local,
    value,
    call,
    relation,
    transform_app,
    /// Typed table/record shape node (storage class + field count).
    table_shape,
    /// Enum descriptor shape (variants are `.member` edges; names via `ast_ref`).
    enum_shape,
};

/// Physical tags only. Application roles (relation/subject/operand/result)
/// live on `ApplicationFact`. Remaining tags below are migration indexes and
/// must not own meaning. Deleted unused tags: def, type_of, transform_input,
/// home (`homeOf` is `Node.scope`), and `transform_output` — that last one was
/// WRITE-ONLY, added on every compile from two sites and read by nothing but
/// its own `=> "output"` arm in the JSON dump. Every scan over `edges.items`
/// filters on a kind and none of them named it, so it changed no answer and
/// cost graph memory forever (`HPLS` §7-8). Remaining reduction:
/// descriptor_ref when the descriptor role is already represented.
pub const EdgeKind = enum {
    /// Nesting/home containment (scope projection — not module lookup).
    contains,
    /// Reference to an exact binding id (not a name recovery edge).
    binding,
    /// Static member/field of a descriptor home entity.
    member,
    /// Descriptor entity references another descriptor entity by exact id.
    descriptor_ref,
    /// Callable entity captures an exact outer binding id.
    capture,
    /// Named projection specialization (not operation spelling).
    projection,
    /// Descriptor constraint on a value entity (not a type ontology).
    descriptor,
    /// Source span linkage for diagnostics/display.
    provenance,
};

// Operational relation spellings must never become edge kinds. The selected
// callable is the unique `.binding` edge to func/relation; subject-first
// subject is the unique `.projection` at `application_subject_projection`.
pub const application_subject_projection: u16 = 1;

test "semantic_graph: EdgeKind excludes operational spellings" {
    const forbidden = [_][]const u8{
        "run",  "call",            "invoke",  "execute",  "read",    "write",    "get",
        "set",  "parse",           "encode",  "decode",   "convert", "compile",  "lower",
        "emit", "transform",       "subject", "argument", "result",  "relation", "type_of",
        "def",  "transform_input", "use",     "home",
    };
    inline for (@typeInfo(EdgeKind).@"enum".field_names) |field_name| {
        const kind: EdgeKind = @field(EdgeKind, field_name);
        const label = @tagName(kind);
        for (forbidden) |word| {
            try std.testing.expect(!std.mem.eql(u8, label, word));
        }
    }
}

// WORLD IS NOT A FIELD HERE, AND THAT IS NOW A DECISION RATHER THAN A GAP.
// `protocol-projection-one.md` §10.1 measured the absence and read it as
// "injection algebra is NOT yet graph-bound at the application". It is bound —
// as `SemanticGraph.draws`, `world[application]`, keyed by the exact occurrence.
// It is not a field on this struct for one measured reason: the applications
// that actually draw a world (`env("HOME")`, `s:len()`, `print(v)`) have no
// `ApplicationFact` at all, so a field here would have been a world fact that
// could not reach a single world face. `demand`, `descriptor`, `provenance`,
// `stage` and `caller` are already not fields of this struct for the same kind
// of reason, and `law.md` §20 asks for packed sparse columns keyed by
// application rather than one fat nullable row.
//
// A STRING WORLD REMAINS FORBIDDEN, which is what this test was written for and
// still checks: `draws` carries a `Card` over an exact world ENTITY, never a
// spelling.
test "semantic_graph: ApplicationFact has no string world" {
    try std.testing.expect(!@hasField(ApplicationFact, "world"));
    try std.testing.expect(!@hasField(ApplicationFact, "descriptor"));
    try std.testing.expect(!@hasField(ApplicationFact, "demand"));
    try std.testing.expect(!@hasField(ApplicationFact, "provenance"));
    try std.testing.expect(!@hasField(ApplicationFact, "stage"));
    try std.testing.expect(!@hasField(ApplicationFact, "caller"));
    try std.testing.expect(!@hasField(ApplicationFact, "relation"));
    try std.testing.expect(!@hasField(ApplicationFact, "subject"));
    const dummy = ApplicationFact{
        .application = 0,
        .operand_pack = 1,
        .result_pack = 2,
    };
    try std.testing.expect(dummy.effect == .unknown);
    try std.testing.expect(dummy.authority == .unknown);
    try std.testing.expect(dummy.witness == .unknown);
    try std.testing.expect(dummy.target == .unknown);
    try std.testing.expect(dummy.realization == .unknown);
    try std.testing.expect(dummy.applied == .unknown);
    try std.testing.expect(dummy.effect != .none);
}

test "semantic_graph: NodeKind excludes unused shadow kinds" {
    const forbidden = [_][]const u8{
        "source_file", "concept", "comptime_value", "emit_artifact", "type_node",
    };
    inline for (@typeInfo(NodeKind).@"enum".field_names) |field_name| {
        const kind: NodeKind = @field(NodeKind, field_name);
        const label = @tagName(kind);
        for (forbidden) |word| {
            try std.testing.expect(!std.mem.eql(u8, label, word));
        }
    }
}

pub const SpanRef = struct {
    file: []const u8,
    start: u32,
    end: u32,
};

pub const Node = struct {
    kind: NodeKind,
    span: SpanRef,
    name: ?[]const u8 = null,
    /// Residual physical class copied onto a shape. Lift does not populate it
    /// (`law.representation.one`); realization owns width/layout/location.
    storage_class: ?types.StorageClass = null,
    /// Shape-content fingerprint used by current realization candidates.
    /// It never selects or identifies a graph entity. THE ONE FIELD IN THIS
    /// GROUP THAT SURVIVED THE SCENERY AUDIT:
    /// `realization.fingerprintForRecordId` reads it to key candidate reuse,
    /// which is a decision, not a print. Exact graph facts still verify a hit.
    shape_id: ?u64 = null,
    /// For `.call` nodes: the inferred CallShape (Phase 1 — conservative from AST).
    call_shape: ?types.CallShape = null,
    /// Resolved result descriptor attached to a function's semantic identity.
    result_descriptor: ?types.ResolvedType = null,
    /// Checked descriptor of a semantic value or application result.
    descriptor: ?types.ResolvedType = null,
    /// Demand attached to an application before realization selects control.
    demand: ?types.ReturnConsumption = null,
    /// Residual prose. New lifts do not populate this.
    why: ?[]const u8 = null,
    /// knowledge lattice position when known.
    knowledge: ?semantic_algebra.KnowledgeLevel = null,
    /// evaluation stage when known.
    stage: ?semantic_algebra.Stage = null,
    /// M1: descriptor lifecycle state at lift.
    descriptor_state: ?State = null,
    // ─────────────────────────────────────────────────────────────────────
    // DELETED HERE, and the deletion is the entry that keeps them deleted:
    // `field_count`, `descriptor_hash`, `call_shape_fingerprint`,
    // `recursion`, `completion`, `iteration_relation`, `hardware_lowerings`.
    //
    // MEASURED: every one of them was produced on every compile and read by
    // NOTHING but `writeJson`/`dumpSummary`, and no gate, script or tool in
    // EITHER tree parses those keys — `grep` over `gate/`, `scripts/`,
    // `tools/` and `benchmarks/` in both repos returns one hit, and it is
    // `scripts/ledger/graph.id` reporting `hardware_lowerings` as OPEN DEBT.
    // A JSON key with no reader is not "tooling" under HPLS §7; it is scenery
    // with an audience of nobody, and it cost seven fields on every graph node
    // plus a whole `.descriptor_ref` closure walk (`recursion`) per shape.
    // `shape_id` stayed, because it has a reader that makes a decision.
    // ─────────────────────────────────────────────────────────────────────
    /// Opaque link to AST for Phase 1 — graph mirrors, does not replace, AST yet.
    ast_ref: ?*anyopaque = null,
    /// THE HOME A CALLABLE IS DECLARED IN, when that home is not this module.
    ///
    /// Null on every node lifted from the module being compiled — its home is
    /// the module node and the `.contains` chain already says so. Non-null only
    /// on a FOREIGN relation: a declaration this module refers to and does not
    /// contain. It is the one fact that separates "the graph knows this call"
    /// from "the graph knows this call AND can name the symbol it lands on",
    /// and realization reads it through `foreignHome` rather than by
    /// re-deriving a home from a file path in a second place.
    foreign_home: ?[]const u8 = null,
    /// The graph entity this one is nested inside. The `.contains` edge is a
    /// projection of this field; `addChild` writes both from one call.
    scope: ?id = null,
    /// When true, `name` was allocated on the graph allocator and must be freed in deinit.
    owns_name: bool = false,
};

pub const Edge = struct {
    from: id,
    to: id,
    kind: EdgeKind,
    position: u16 = 0,
    /// For `.descriptor_ref`: true when inline/embedded, false when indirect (e.g. pointer).
    inline_ref: bool = false,
};

pub const FactRange = struct {
    start: u32,
    len: u32,
};

/// Cardinality is a fact about a semantic pack, not its current physical
/// container. `open` carries the number of leading members whose identity is
/// already known; the tail remains a pack and may later become fixed.
pub const PackArity = union(enum) {
    unknown,
    fixed: u32,
    open: u32,

    pub fn fixedPrefix(self: PackArity) ?u32 {
        return switch (self) {
            .unknown => null,
            .fixed => |n| n,
            .open => |n| n,
        };
    }
};

/// Demand for one ordered pack member. Known-discarded is distinct from
/// unknown: the former authorizes physical nonexistence, the latter does not.
pub const PackMemberDemand = enum {
    unknown,
    discard,
    value,
};

pub const PackMember = struct {
    value: id,
    demand: PackMemberDemand = .unknown,
};

/// Physical answers available to realization. Semantic producers publish
/// `.unknown`; only a realization decision may select another member.
pub const PackRealization = enum {
    unknown,
    none,
    scalar,
    registers,
    split_registers,
    stack,
    foreign_sret,
    lazy,
};

/// One exact semantic pack. `pack` is an ordinary graph value identity; no
/// `NodeKind.pack` exists. Ordered members carry their own descriptors and
/// provenance on their value nodes. `producer` links effects/worlds back to
/// their single owners instead of copying either fact onto the pack.
pub const PackFact = struct {
    pack: id,
    members: FactRange,
    arity: PackArity,
    producer: Card = .unknown,
    realization: PackRealization = .unknown,
};

/// One aggregate semantic value and the ordered pack of values it contains.
/// The pack owns member identity and descriptors; this row adds only the two
/// facts a pack cannot answer: which value is the aggregate and which place,
/// if any, those members project from. `contents_known` is deliberately
/// three-valued: a dynamic projection can have an exact member descriptor pack
/// without claiming the member values are compile-time constants.
pub const AggregateFact = struct {
    aggregate: id,
    members_pack: id,
    /// Module or relation whose place census qualifies `place`.
    owner: id,
    place: place.Site = .unknown,
    contents_known: place.Tri = .unknown,
};

/// Exact scalar content retained by the graph. Literal AST is provenance; a
/// realization consumes this fact and never re-parses literal syntax.
pub const ExactI64 = struct {
    value: id,
    content: i64,
};

pub const PackFill = enum { nil };

/// One binding adjustment from a produced source pack to an ordered target
/// pack. Arity differences are facts on the two packs; no separate case enum
/// duplicates one-to-many, many-to-fewer, or exact adjustment.
pub const PackAdjustment = struct {
    application: id,
    source_pack: id,
    target_pack: id,
    fill: PackFill = .nil,
    forwards_tail: bool = false,
};

/// Dense coordinate of one graph incarnation inside its owning `History`.
/// It qualifies an `id`; it is not a second semantic entity identity.
pub const incarnation = u32;

/// One exact semantic entity in one exact graph incarnation.
pub const EntityRef = struct {
    incarnation: incarnation,
    entity: id,

    pub fn eql(a: EntityRef, b: EntityRef) bool {
        return a.incarnation == b.incarnation and a.entity == b.entity;
    }
};

/// Cross-incarnation cardinality. `unknown`, known absence, and one exact
/// entity remain distinct just as they do inside one graph (`Card`).
pub const RefCard = union(enum) {
    unknown,
    none,
    one: EntityRef,

    pub fn name(self: RefCard) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
    }
};

pub const RefRange = struct {
    start: u32,
    len: u32,
};

/// Dependency knowledge for an incarnation. A known empty set is stronger
/// than `unknown` and therefore has its own representation.
pub const Dependencies = union(enum) {
    unknown,
    known: []const EntityRef,
};

pub const DependencyFacts = union(enum) {
    unknown,
    known: RefRange,
};

/// Revision bytes are provenance, never identity. They can bind evidence to a
/// checkout, but cannot establish semantic correspondence.
pub const Revision = union(enum) {
    unknown,
    known: []const u8,
};

pub const IncarnationInput = struct {
    revision: Revision = .unknown,
    /// The compiler application that produced this graph, when witnessed in a
    /// previously registered incarnation.
    producer: RefCard = .unknown,
    /// These are graph-local semantic entities, not enum/string substitutes.
    source_family: Card = .unknown,
    world: Card = .unknown,
    target: Card = .unknown,
    dependencies: Dependencies = .unknown,
};

pub const IncarnationFact = struct {
    coordinate: incarnation,
    entity_count: u32,
    revision: Revision,
    producer: RefCard,
    source_family: RefCard,
    world: RefCard,
    target: RefCard,
    dependencies: DependencyFacts,
};

/// The cardinality of each relationship is checked at admission:
/// preserved/replaced 1→1, split 1→many, merged many→1, generated 0→many,
/// retired many→0.
pub const Continuity = enum {
    preserved,
    replaced,
    split,
    merged,
    generated,
    retired,
};

pub const Preservation = enum {
    exact,
    lawful_refinement,
};

pub const StageCard = union(enum) {
    unknown,
    none,
    one: semantic_algebra.Stage,
};

/// A witnessed correspondence between exact entities in distinct graph
/// incarnations. Fingerprints may locate candidates for this fact; only this
/// fact establishes continuity.
pub const Correspondence = struct {
    predecessors: RefRange,
    successors: RefRange,
    relationship: Continuity,
    preservation: Preservation,
    witness: EntityRef,
    transformation: RefCard = .unknown,
    provenance: RefCard = .unknown,
    world: RefCard = .unknown,
    stage: StageCard = .unknown,
};

pub const CorrespondenceInput = struct {
    predecessors: []const EntityRef,
    successors: []const EntityRef,
    relationship: Continuity,
    preservation: Preservation,
    witness: EntityRef,
    transformation: RefCard = .unknown,
    provenance: RefCard = .unknown,
    world: RefCard = .unknown,
    stage: StageCard = .unknown,
};

/// Owner of graph incarnations and their explicit correspondence facts.
/// Semantic entities remain `semantic_graph.id`; this object only qualifies
/// those coordinates over time and validates every cross-incarnation edge.
pub const History = struct {
    alloc: std.mem.Allocator,
    incarnations: std.ArrayListUnmanaged(IncarnationFact) = .empty,
    refs: std.ArrayListUnmanaged(EntityRef) = .empty,
    correspondences: std.ArrayListUnmanaged(Correspondence) = .empty,

    pub fn init(alloc: std.mem.Allocator) History {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *History) void {
        for (self.incarnations.items) |fact| switch (fact.revision) {
            .known => |revision| self.alloc.free(revision),
            .unknown => {},
        };
        self.incarnations.deinit(self.alloc);
        self.refs.deinit(self.alloc);
        self.correspondences.deinit(self.alloc);
    }

    fn u32Coordinate(value: usize) !u32 {
        if (comptime @bitSizeOf(usize) > @bitSizeOf(u32)) {
            if (value > std.math.maxInt(u32)) return error.GraphCoordinateExhausted;
        }
        return @intCast(value);
    }

    pub fn incarnationFact(self: *const History, coordinate: incarnation) ?*const IncarnationFact {
        return if (coordinate < self.incarnations.items.len)
            &self.incarnations.items[coordinate]
        else
            null;
    }

    pub fn correspondenceAt(self: *const History, coordinate: u32) ?*const Correspondence {
        return if (coordinate < self.correspondences.items.len)
            &self.correspondences.items[coordinate]
        else
            null;
    }

    pub fn correspondenceCount(self: *const History) usize {
        return self.correspondences.items.len;
    }

    pub fn refsIn(self: *const History, range: RefRange) ?[]const EntityRef {
        const start: usize = range.start;
        const len: usize = range.len;
        if (start > self.refs.items.len or len > self.refs.items.len - start) return null;
        return self.refs.items[start .. start + len];
    }

    fn validRef(self: *const History, ref: EntityRef) bool {
        const fact = self.incarnationFact(ref.incarnation) orelse return false;
        return ref.entity < fact.entity_count;
    }

    fn validateRefCard(self: *const History, card: RefCard) !void {
        switch (card) {
            .unknown, .none => {},
            .one => |ref| if (!self.validRef(ref)) return error.InvalidGraphEntityRef,
        }
    }

    fn localCard(graph: *const SemanticGraph, coordinate: incarnation, card: Card) !RefCard {
        return switch (card) {
            .unknown => .unknown,
            .none => .none,
            .one => |entity| blk: {
                if (graph.get(entity) == null) return error.InvalidGraphEntityRef;
                break :blk .{ .one = .{ .incarnation = coordinate, .entity = entity } };
            },
        };
    }

    pub fn register(
        self: *History,
        graph: *SemanticGraph,
        input: IncarnationInput,
    ) !incarnation {
        if (graph.incarnation_coordinate != null) return error.GraphAlreadyRegistered;
        try self.validateRefCard(input.producer);
        switch (input.dependencies) {
            .unknown => {},
            .known => |dependencies| for (dependencies) |dependency| {
                if (!self.validRef(dependency)) return error.InvalidGraphEntityRef;
            },
        }

        const coordinate = try u32Coordinate(self.incarnations.items.len);
        const entity_count = try u32Coordinate(graph.nodes.items.len);
        const source_family = try localCard(graph, coordinate, input.source_family);
        const world = try localCard(graph, coordinate, input.world);
        const target = try localCard(graph, coordinate, input.target);

        const revision: Revision = switch (input.revision) {
            .unknown => .unknown,
            .known => |value| .{ .known = try self.alloc.dupe(u8, value) },
        };
        errdefer switch (revision) {
            .known => |value| self.alloc.free(value),
            .unknown => {},
        };

        const refs_before = self.refs.items.len;
        errdefer self.refs.shrinkRetainingCapacity(refs_before);
        const dependencies: DependencyFacts = switch (input.dependencies) {
            .unknown => .unknown,
            .known => |values| blk: {
                const start = try u32Coordinate(self.refs.items.len);
                const len = try u32Coordinate(values.len);
                try self.refs.appendSlice(self.alloc, values);
                break :blk .{ .known = .{ .start = start, .len = len } };
            },
        };

        try self.incarnations.append(self.alloc, .{
            .coordinate = coordinate,
            .entity_count = entity_count,
            .revision = revision,
            .producer = input.producer,
            .source_family = source_family,
            .world = world,
            .target = target,
            .dependencies = dependencies,
        });
        graph.incarnation_coordinate = coordinate;
        return coordinate;
    }

    fn validateRelationship(input: CorrespondenceInput) !void {
        const before = input.predecessors.len;
        const after = input.successors.len;
        const valid = switch (input.relationship) {
            .preserved, .replaced => before == 1 and after == 1,
            .split => before == 1 and after > 1,
            .merged => before > 1 and after == 1,
            .generated => before == 0 and after > 0,
            .retired => before > 0 and after == 0,
        };
        if (!valid) return error.InvalidCorrespondenceCardinality;
        if (input.relationship == .preserved and input.preservation != .exact)
            return error.InvalidCorrespondencePreservation;
        if (input.relationship != .preserved and input.preservation == .exact)
            return error.InvalidCorrespondencePreservation;
    }

    pub fn addCorrespondence(self: *History, input: CorrespondenceInput) !u32 {
        try validateRelationship(input);
        if (!self.validRef(input.witness)) return error.InvalidGraphEntityRef;
        try self.validateRefCard(input.transformation);
        try self.validateRefCard(input.provenance);
        try self.validateRefCard(input.world);
        for (input.predecessors) |predecessor| {
            if (!self.validRef(predecessor)) return error.InvalidGraphEntityRef;
            for (input.successors) |successor| {
                if (predecessor.incarnation == successor.incarnation)
                    return error.CorrespondenceRequiresDistinctIncarnations;
            }
        }
        for (input.successors) |successor| {
            if (!self.validRef(successor)) return error.InvalidGraphEntityRef;
        }

        const refs_before = self.refs.items.len;
        errdefer self.refs.shrinkRetainingCapacity(refs_before);
        const predecessors = RefRange{
            .start = try u32Coordinate(self.refs.items.len),
            .len = try u32Coordinate(input.predecessors.len),
        };
        try self.refs.appendSlice(self.alloc, input.predecessors);
        const successors = RefRange{
            .start = try u32Coordinate(self.refs.items.len),
            .len = try u32Coordinate(input.successors.len),
        };
        try self.refs.appendSlice(self.alloc, input.successors);

        const coordinate = try u32Coordinate(self.correspondences.items.len);
        try self.correspondences.append(self.alloc, .{
            .predecessors = predecessors,
            .successors = successors,
            .relationship = input.relationship,
            .preservation = input.preservation,
            .witness = input.witness,
            .transformation = input.transformation,
            .provenance = input.provenance,
            .world = input.world,
            .stage = input.stage,
        });
        return coordinate;
    }

    /// Exact 1→1 continuity only. No name, path, or fingerprint fallback.
    pub fn exactSuccessor(self: *const History, predecessor: EntityRef) ?EntityRef {
        for (self.correspondences.items) |fact| {
            if (fact.relationship != .preserved or fact.preservation != .exact) continue;
            const before = self.refsIn(fact.predecessors) orelse continue;
            const after = self.refsIn(fact.successors) orelse continue;
            if (before.len != 1 or after.len != 1) continue;
            if (EntityRef.eql(before[0], predecessor)) return after[0];
        }
        return null;
    }
};

/// Derived reverse index: one producer writes it; consumers borrow the range
/// (`law.fact.locality`, `law.derived.index`).
const Adjacency = struct {
    map: std.AutoHashMapUnmanaged(id, std.ArrayListUnmanaged(id)) = .empty,

    fn deinit(self: *Adjacency, alloc: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(alloc);
        }
        self.map.deinit(alloc);
    }

    fn push(self: *Adjacency, alloc: std.mem.Allocator, from: id, to: id) !void {
        const slot = try self.map.getOrPut(alloc, from);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        errdefer {
            if (slot.value_ptr.items.len == 0) {
                slot.value_ptr.deinit(alloc);
                _ = self.map.remove(from);
            }
        }
        try slot.value_ptr.append(alloc, to);
    }

    fn of(self: *const Adjacency, from: id) []const id {
        const list = self.map.get(from) orelse return &.{};
        return list.items;
    }
};

const DescriptorHit = struct {
    to: id,
    inline_ref: bool,
};

const RefAdjacency = struct {
    map: std.AutoHashMapUnmanaged(id, std.ArrayListUnmanaged(DescriptorHit)) = .empty,

    fn deinit(self: *RefAdjacency, alloc: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(alloc);
        }
        self.map.deinit(alloc);
    }

    fn push(
        self: *RefAdjacency,
        alloc: std.mem.Allocator,
        from: id,
        to: id,
        inline_ref: bool,
    ) !void {
        const slot = try self.map.getOrPut(alloc, from);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        errdefer {
            if (slot.value_ptr.items.len == 0) {
                slot.value_ptr.deinit(alloc);
                _ = self.map.remove(from);
            }
        }
        try slot.value_ptr.append(alloc, .{ .to = to, .inline_ref = inline_ref });
    }

    fn of(self: *const RefAdjacency, from: id) []const DescriptorHit {
        const list = self.map.get(from) orelse return &.{};
        return list.items;
    }
};

/// FACT-CARDINALITY-ONE: unknown, known-absent, or one exact id.
/// `null` is forbidden as a stand-in for any of these (`law.unknown.one`).
pub const Card = union(enum) {
    unknown,
    none,
    one: id,

    /// The union tag, spelled once. Every projection of a `Card` — JSON,
    /// diagnostics, any future face — uses THIS, so a consumer that learns the
    /// three words learns them for the whole tree. Deliberately not `@tagName`
    /// at each site: `law.unknown.one` forbids `null` standing in for any of
    /// these, and a hand-written spelling at each site is how one of them
    /// quietly becomes `null` again.
    pub fn name(self: Card) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
    }
};

/// Graph-owned facts for one checked relation application. The application
/// id is the key; packed ranges are physical projections over the graph's
/// shared value storage.
///
/// APPLICATION-FACT-CLOSURE owners:
/// relation → unique `.binding` edge · subject → unique subject projection
/// operands/results → packed ranges · descriptor/demand/stage/provenance → node
/// caller → node.scope · effect/authority/witness/target/realization → Card here
pub const ApplicationFact = struct {
    application: id,
    operand_pack: id,
    result_pack: id,
    effect: Card = .unknown,
    authority: Card = .unknown,
    witness: Card = .unknown,
    target: Card = .unknown,
    realization: Card = .unknown,
    /// THE APPLIED VALUE — the applicator, and a THIRD fact beside relation and
    /// subject (`face-role-launch-one.md` §2). Relation is the operation the
    /// application denotes; subject is the value it is oriented around; APPLIED
    /// is the value that is applied. `tokenizer = rule` then `tokenizer(source)`
    /// normalises to `applied = rule-value, relation = token, subject = source`,
    /// and `tokenizer-id != token-id` is exactly the distinction this field
    /// exists to keep.
    ///
    /// `.one` is the exact semantic applicator identity. A sealed stateless
    /// applicator may still realize to provider object 0, lookup 0, and dynamic
    /// dispatch 0; physical absence never erases this semantic role.
    ///
    /// The default is `.unknown`, not `.none`: absence of an applied fact is
    /// not an exact empty role.
    applied: Card = .unknown,
};

/// One injected world, keyed by the exact id of its graph entity.
///
/// A WORLD IS A VALUE, so it needs no new `NodeKind` — `ast.Expr.semantic_scope`
/// already spells bare `@` as "the current effective semantic world, AS A
/// VALUE". The meaning lives HERE, in the fact, not in the tag (`law.md` §19,
/// TAG-AUTHORITY-ZERO).
///
/// `home` and `reach` are copied from `subject_home.declarations`, which is the
/// SOLE authority for what a world is and what inhabiting it confers. This
/// family does not decide either; it records which of them this module drew on.
pub const WorldFact = struct {
    world: id,
    home: subject_home.Home,
    reach: subject_home.Reach,
    /// The member entities THIS MODULE reaches, packed. A world's full roster
    /// is a property of the world, not of the module, and publishing the whole
    /// roster on every module would be a fact about somebody else.
    members: FactRange,
};

/// WORLD, keyed by the exact application occurrence.
///
/// KEYED BY THE OCCURRENCE AND NOT STORED ON `ApplicationFact`, deliberately.
/// `demand`, `descriptor`, `provenance`, `stage` and `caller` are already not
/// fields of that struct — this tree's convention is that an application
/// dimension lives wherever exactly ONE producer owns it (`law.md` §21), and
/// `law.md` §20 asks for packed sparse columns keyed by application rather than
/// one fat nullable row. The deciding fact is coverage: the applications that
/// actually DRAW a world are overwhelmingly the ones with no `ApplicationFact`
/// at all — `env("HOME")`, `s:len()`, `print(v)` — so a field on the struct
/// would have been a world fact that could not reach a single world face.
pub const Draw = struct {
    application: id,
    world: Card,
};

/// The place one application VALUE reads, keyed by the exact value entity.
///
/// `p:add(q)` and `q:add(p)` published BYTE-IDENTICAL normalised graphs: both
/// carry `subject = <value>`, `arguments = [<value>]`, and a value entity is
/// anonymous. The missing fact is which PLACE the value came from — §29's
/// "value != binding != place", with the third term finally named. The name is
/// used to LOCATE the place during ingress (`face-role-launch-one.md` §1
/// permits exactly that) and what is stored is an exact census id.
///
/// SHADOWING IS THE KNOWN LIMIT. `place.Census.find` scans backward, so a body
/// binding two places of one spelling in sibling scopes attributes to the
/// later one. A wrong answer here names the wrong PLACE and never changes a
/// program; it becomes exact when places carry lexical extent, with no change
/// to any consumer of this family.
pub const Origin = struct {
    value: id,
    /// The relation whose census `place` indexes. A place id is only meaningful
    /// against the census it came from.
    relation: id,
    place: u32,
};

/// The two censuses of one relation body, produced as a PAIR.
///
/// `place.Census` is keyed to one body and `region.Census`'s refinements index
/// into it, so they are only meaningful together and are stored together. The
/// module-scope census on `SemanticGraph.places` is a different census with a
/// different id space and is NOT one of these.
pub const Body = struct {
    relation: id,
    places: place.Census,
    regions: region.Census,
};

pub const SemanticGraph = struct {
    alloc: std.mem.Allocator,
    /// Coordinate assigned only by an owning `History`. The semantic entity
    /// identity remains `id`; this qualifies it across graph incarnations.
    incarnation_coordinate: ?incarnation = null,
    /// Source path for the lifted module; used for gate-transport bootstrap faces.
    module_path: ?[]const u8 = null,
    /// Exact launcher-supplied worlds for this graph incarnation. This is copied
    /// from checked sema facts; `module_path` is provenance only.
    launch_worlds: subject_home.WorldSet,
    /// THE MODULE'S OWN HOME — the DEFINER half of `(home, name)`.
    ///
    /// `foreign_home` on a node answers the caller's half: "the relation I am
    /// calling lives over there". Nothing answered "and where do I live", so
    /// realization named every definition by its bare spelling and two homes
    /// that both declare `field` both emitted `_field`. MEASURED: `ld -r` over
    /// that pair answers `duplicate symbol '_field'`, which is why linking the
    /// eighteen `lib/compiler` modules into one image was impossible
    /// independent of every sema question in front of it.
    ///
    /// Derived here, once, from the module path by `home_resolve.homeOfPath` —
    /// the SAME derivation `sema` runs for a foreign home — so a definer and a
    /// caller cannot land on two spellings of one home.
    home: ?[]const u8 = null,
    /// The declaration the module entity was lifted from. Provenance for
    /// consumers that need file-scope statements the graph does not lift as
    /// entities — module-level constants such as `ring = 2147483647`, which are
    /// free names inside every relation that reads them. Kept as its own field
    /// rather than on `Node.ast_ref` because two diagnostic projections
    /// (`dnir_lower.applicationFace`, `native_backend.occurrenceFace`) cast any
    /// `ast_ref` they are handed straight to `*const Expr`.
    module_ast: ?*const ast.Module = null,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    edges: std.ArrayListUnmanaged(Edge) = .empty,
    /// from-id -> indices into `edges`. A PHYSICAL ACCELERATION INDEX ONLY
    /// (law.md §19: indexes may accelerate queries but never establish meaning),
    /// so every consumer re-checks `edge.from` and a stale bucket is harmless.
    /// Without it the hot graph queries scanned ALL edges per lookup, making
    /// lowering O(applications x edges).
    out_edges: std.AutoHashMapUnmanaged(id, std.ArrayListUnmanaged(u32)) = .empty,
    application_facts: std.ArrayListUnmanaged(ApplicationFact) = .empty,
    pack_facts: std.ArrayListUnmanaged(PackFact) = .empty,
    pack_values: std.ArrayListUnmanaged(id) = .empty,
    pack_demands: std.ArrayListUnmanaged(PackMemberDemand) = .empty,
    pack_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    pack_adjustments: std.ArrayListUnmanaged(PackAdjustment) = .empty,
    adjustment_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    aggregate_facts: std.ArrayListUnmanaged(AggregateFact) = .empty,
    aggregate_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    aggregate_origins: std.AutoHashMapUnmanaged(usize, id) = .empty,
    exact_i64_facts: std.ArrayListUnmanaged(ExactI64) = .empty,
    exact_i64_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    owned_descriptors: std.ArrayListUnmanaged(*types.ResolvedType) = .empty,
    aggregate_access_relation: ?id = null,
    application_rows: std.ArrayListUnmanaged(u32) = .empty,
    application_presence: std.DynamicBitSetUnmanaged = .{},
    application_candidates: std.DynamicBitSetUnmanaged = .{},
    /// Reverse of `Node.scope` — rebuilt only from `addChild` (`law.derived.index`).
    nested: Adjacency = .{},
    /// Caller home → published application ids (`law.fact.locality`).
    home_apps: Adjacency = .{},
    /// Descriptor → descriptor_ref hits (`law.fact.locality`).
    descriptor_refs: RefAdjacency = .{},
    /// Func id assigned at addNode from the declaration pointer. Lookup is this
    /// index, not a later walk of `ast_ref` slots.
    origin: std.AutoHashMapUnmanaged(usize, id) = .empty,
    /// §18 — PLACE, IN THE GRAPH.
    ///
    /// The graph MUST represent place: identity, determinacy, extent, mutation,
    /// immutability, alias, escape, lifetime, alignment, residency, origin,
    /// SHARED by sema, demand, optimization, realization, LSP and MCP, and
    /// NEVER recomputed or discarded per backend. It is one census over the
    /// module, produced once at lift time, and every consumer reads the same
    /// array — which is the difference between this and the four name-keyed
    /// side tables (`ModuleConsts`, `ModuleGlobals`, `const_tables`,
    /// `table_facts.Decisions`) that each answer one question for one caller.
    ///
    /// Optional rather than empty because `null` and "no places" are different
    /// answers: a graph lifted by `liftModule` alone has NOT been asked, and a
    /// consumer must not read absence as proof.
    places: ?place.Census = null,
    /// §18's census and SOURCE-CONTROL-ONE's regions, PER RELATION.
    ///
    /// `places` above is the MODULE-scope census and `place.zig` states why it
    /// stops there: "a relation body binds nothing into the MODULE census. Its
    /// own places are `analyzeFunction`'s to produce, over its own body, with
    /// its own ids." Nothing produced them, so every fact that separates two
    /// relation bodies — how many places, at what depth, updated where, under
    /// which refinement — was unproduced, and TEN different programs published
    /// ONE graph digest. This is the production.
    ///
    /// A SEPARATE FIELD rather than a widened `places`, because
    /// `dnir_lower.zig:5219` resolves MODULE-scope names through
    /// `placeNamed`/`find`, and `find` scans backwards: folding relation-local
    /// places into the same census would silently answer a module lookup with a
    /// relation-local place of the same spelling.
    bodies: std.ArrayListUnmanaged(Body) = .empty,
    /// Injected worlds this module draws on, and the members it reaches.
    worlds: std.ArrayListUnmanaged(WorldFact) = .empty,
    world_members: std.ArrayListUnmanaged(id) = .empty,
    /// `world[application]`, ascending by application id.
    draws: std.ArrayListUnmanaged(Draw) = .empty,
    /// `place[value]` for application values, ascending by value id.
    origins: std.ArrayListUnmanaged(Origin) = .empty,
    pub fn init(alloc: std.mem.Allocator) SemanticGraph {
        return .{ .alloc = alloc, .launch_worlds = subject_home.injectedWorlds() };
    }

    pub fn deinit(self: *SemanticGraph) void {
        for (self.nodes.items) |node| {
            self.deinitNode(node);
        }
        self.nodes.deinit(self.alloc);
        self.edges.deinit(self.alloc);
        {
            var it = self.out_edges.valueIterator();
            while (it.next()) |bucket| bucket.deinit(self.alloc);
            self.out_edges.deinit(self.alloc);
        }
        self.application_facts.deinit(self.alloc);
        self.pack_facts.deinit(self.alloc);
        self.pack_values.deinit(self.alloc);
        self.pack_demands.deinit(self.alloc);
        self.pack_rows.deinit(self.alloc);
        self.pack_adjustments.deinit(self.alloc);
        self.adjustment_rows.deinit(self.alloc);
        self.aggregate_facts.deinit(self.alloc);
        self.aggregate_rows.deinit(self.alloc);
        self.aggregate_origins.deinit(self.alloc);
        self.exact_i64_facts.deinit(self.alloc);
        self.exact_i64_rows.deinit(self.alloc);
        for (self.owned_descriptors.items) |descriptor| self.alloc.destroy(descriptor);
        self.owned_descriptors.deinit(self.alloc);
        self.application_rows.deinit(self.alloc);
        self.application_presence.deinit(self.alloc);
        self.application_candidates.deinit(self.alloc);
        self.nested.deinit(self.alloc);
        self.home_apps.deinit(self.alloc);
        self.descriptor_refs.deinit(self.alloc);
        self.origin.deinit(self.alloc);
        if (self.places) |*census| census.deinit();
        for (self.bodies.items) |*body| {
            body.places.deinit();
            body.regions.deinit();
        }
        self.bodies.deinit(self.alloc);
        self.worlds.deinit(self.alloc);
        self.world_members.deinit(self.alloc);
        self.draws.deinit(self.alloc);
        self.origins.deinit(self.alloc);
        if (self.home) |h| self.alloc.free(h);
    }

    /// The module's own home, or null when it was lifted without a path.
    /// Realization asks this for the DEFINER half of `(home, name)`; nothing
    /// else may re-derive it, for the same reason `foreignHome` is the sole
    /// authority for the caller's half.
    pub fn selfHome(self: *const SemanticGraph) ?[]const u8 {
        return self.home;
    }

    pub fn entityRef(self: *const SemanticGraph, entity: id) !EntityRef {
        if (self.get(entity) == null) return error.InvalidGraphEntityRef;
        return .{
            .incarnation = self.incarnation_coordinate orelse return error.GraphNotRegistered,
            .entity = entity,
        };
    }

    fn deinitNode(self: *SemanticGraph, node: Node) void {
        if (node.why) |why| self.alloc.free(why);
        if (node.owns_name) {
            if (node.name) |name| self.alloc.free(name);
        }
    }

    fn coordinateForLength(len: usize) !id {
        if (comptime @bitSizeOf(usize) > @bitSizeOf(id)) {
            if (len > std.math.maxInt(id)) return error.GraphCoordinateExhausted;
        }
        return @intCast(len);
    }

    fn requireOpen(self: *const SemanticGraph) !void {
        if (self.incarnation_coordinate != null) return error.GraphIncarnationFrozen;
    }

    pub fn addNode(self: *SemanticGraph, node: Node) !id {
        try self.requireOpen();
        const entity = try coordinateForLength(self.nodes.items.len);
        try self.rememberFunc(node, entity);
        errdefer self.forgetFunc(node);
        try self.nodes.append(self.alloc, node);
        return entity;
    }

    fn rememberFunc(self: *SemanticGraph, node: Node, entity: id) !void {
        if (node.result_descriptor == null) return;
        const raw = node.ast_ref orelse return;
        const slot = try self.origin.getOrPut(self.alloc, @intFromPtr(raw));
        if (slot.found_existing) return error.DuplicateSemanticDeclaration;
        slot.value_ptr.* = entity;
    }

    fn forgetFunc(self: *SemanticGraph, node: Node) void {
        if (node.result_descriptor == null) return;
        const raw = node.ast_ref orelse return;
        _ = self.origin.remove(@intFromPtr(raw));
    }

    /// Add `node` inside `parent`: records the scope fact and emits the
    /// `.contains` edge that projects it. Both used to be written by hand at
    /// every lift site, and the scope half was simply never written — which is
    /// how a parameter and a module function came to share one identity.
    pub fn addChild(self: *SemanticGraph, parent: id, node: Node) !id {
        var n = node;
        n.scope = parent;
        errdefer self.deinitNode(n);
        const entity = try self.addNode(n);
        errdefer {
            const removed = self.nodes.pop() orelse unreachable;
            std.debug.assert(removed.scope == parent);
            self.forgetFunc(removed);
        }
        try self.appendEdge(.{ .from = parent, .to = entity, .kind = .contains });
        errdefer self.popEdge();
        try self.nested.push(self.alloc, parent, entity);
        return entity;
    }

    fn appendEdge(self: *SemanticGraph, edge: Edge) !void {
        try self.requireOpen();
        const idx: u32 = @intCast(self.edges.items.len);
        try self.edges.append(self.alloc, edge);
        // The index is required for query COMPLETENESS, so a failure to grow it
        // must not leave the edge published — appendEdge stays transactional.
        errdefer _ = self.edges.pop();
        const gop = try self.out_edges.getOrPut(self.alloc, edge.from);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(self.alloc, idx);
    }

    /// Roll back the last appended edge AND its index entry together. Popping
    /// only the edge would leave a stale bucket entry; if a later edge reused
    /// that slot with the same `from` it would be visited twice, and a
    /// uniqueness query would report false ambiguity.
    fn popEdge(self: *SemanticGraph) void {
        const edge = self.edges.pop() orelse return;
        if (self.out_edges.getPtr(edge.from)) |bucket| {
            if (bucket.items.len > 0) _ = bucket.pop();
        }
    }

    /// Edge indices whose `from` is `n`, for O(out-degree) traversal (law.md §20).
    fn outEdges(self: *const SemanticGraph, n: id) []const u32 {
        const bucket = self.out_edges.getPtr(n) orelse return &[_]u32{};
        return bucket.items;
    }

    pub fn addEdge(self: *SemanticGraph, edge: Edge) !void {
        if (edge.kind == .contains) return error.DerivedContainsIndex;
        try self.appendEdge(edge);
    }

    pub fn get(self: *const SemanticGraph, entity: id) ?*const Node {
        if (entity >= self.nodes.items.len) return null;
        return &self.nodes.items[entity];
    }

    pub fn atModuleScope(self: *const SemanticGraph, node: *const Node) bool {
        const home = node.scope orelse return false;
        const parent = self.get(home) orelse return false;
        return parent.scope == null;
    }

    /// Applicable relation/callable from published facts, not NodeKind
    /// (`law.tag.authority`).
    pub fn callable(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        return node.result_descriptor != null;
    }

    /// Descriptor-home facts (members, descriptor edges, or sealed descriptor
    /// state) — not table_shape/enum_shape tags (`law.tag.authority`).
    pub fn hasDescriptorFacts(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        if (node.descriptor_state != null) return true;
        for (self.edges.items) |edge| {
            if (edge.from != entity) continue;
            if (edge.kind == .member or edge.kind == .descriptor_ref or edge.kind == .descriptor)
                return true;
        }
        return false;
    }

    /// Table/record descriptor home: sealed state or `.descriptor_ref` edges.
    pub fn hasTableDescriptorFacts(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        if (node.descriptor_state != null) return true;
        for (self.edges.items) |edge| {
            if (edge.from == entity and edge.kind == .descriptor_ref) return true;
        }
        return false;
    }

    /// Enum descriptor home: member facts without table descriptor_ref/state.
    pub fn hasEnumDescriptorFacts(self: *const SemanticGraph, entity: id) bool {
        if (!self.hasDescriptorFacts(entity)) return false;
        if (self.hasTableDescriptorFacts(entity)) return false;
        return true;
    }

    /// All descriptor-home entities in resident id order (`law.tag.authority`).
    pub fn descriptorHomes(self: *const SemanticGraph, alloc: std.mem.Allocator) ![]const id {
        var out: std.ArrayListUnmanaged(id) = .empty;
        errdefer out.deinit(alloc);
        for (self.nodes.items, 0..) |_, i| {
            const entity: id = @intCast(i);
            if (!self.hasDescriptorFacts(entity)) continue;
            try out.append(alloc, entity);
        }
        return try out.toOwnedSlice(alloc);
    }

    /// Table/record descriptor homes only.
    pub fn tableDescriptorHomes(self: *const SemanticGraph, alloc: std.mem.Allocator) ![]const id {
        var out: std.ArrayListUnmanaged(id) = .empty;
        errdefer out.deinit(alloc);
        for (self.nodes.items, 0..) |_, i| {
            const entity: id = @intCast(i);
            if (!self.hasTableDescriptorFacts(entity)) continue;
            try out.append(alloc, entity);
        }
        return try out.toOwnedSlice(alloc);
    }

    /// The exact descriptor shape attached to one semantic entity and pack
    /// position. Absence and ambiguity both refuse: a consumer may not choose
    /// whichever same-named shape happened to be visited first.
    pub fn descriptorShape(self: *const SemanticGraph, entity: id, position: u16) ?id {
        var found: ?id = null;
        for (self.edges.items) |edge| {
            if (edge.from != entity or edge.kind != .descriptor or edge.position != position) continue;
            if (found != null and found.? != edge.to) return null;
            found = edge.to;
        }
        const shape = found orelse return null;
        if (!self.hasTableDescriptorFacts(shape)) return null;
        return shape;
    }

    /// Exact shape of one application result-pack member. The result value is
    /// the owner of the edge, so source call orientation and relation spelling
    /// are already gone by the time realization asks this question.
    pub fn applicationResultShape(self: *const SemanticGraph, occurrence: id, position: u16) ?id {
        const results = self.applicationResults(occurrence) orelse return null;
        if (position >= results.len) return null;
        return self.descriptorShape(results[position], 0);
    }

    /// Enum descriptor homes only.
    pub fn enumDescriptorHomes(self: *const SemanticGraph, alloc: std.mem.Allocator) ![]const id {
        var out: std.ArrayListUnmanaged(id) = .empty;
        errdefer out.deinit(alloc);
        for (self.nodes.items, 0..) |_, i| {
            const entity: id = @intCast(i);
            if (!self.hasEnumDescriptorFacts(entity)) continue;
            try out.append(alloc, entity);
        }
        return try out.toOwnedSlice(alloc);
    }

    fn ensureApplicationRows(self: *SemanticGraph) !void {
        if (self.application_rows.items.len < self.nodes.items.len) {
            try self.application_rows.appendNTimes(
                self.alloc,
                0,
                self.nodes.items.len - self.application_rows.items.len,
            );
        }
        if (self.application_presence.bit_length < self.nodes.items.len) {
            try self.application_presence.resize(self.alloc, self.nodes.items.len, false);
        }
        if (self.application_candidates.bit_length < self.nodes.items.len) {
            try self.application_candidates.resize(self.alloc, self.nodes.items.len, false);
        }
    }

    fn factRange(start: usize, len: usize) !FactRange {
        if (start > std.math.maxInt(u32) or len > std.math.maxInt(u32)) {
            return error.ApplicationFactCapacityExceeded;
        }
        const end = std.math.add(usize, start, len) catch
            return error.ApplicationFactCapacityExceeded;
        if (end > std.math.maxInt(u32)) return error.ApplicationFactCapacityExceeded;
        return .{ .start = @intCast(start), .len = @intCast(len) };
    }

    fn membersForRange(self: *const SemanticGraph, range: FactRange) ?[]const id {
        const start: usize = range.start;
        const end = std.math.add(usize, start, range.len) catch return null;
        if (end > self.pack_values.items.len or end > self.pack_demands.items.len) return null;
        return self.pack_values.items[start..end];
    }

    fn demandsForRange(self: *const SemanticGraph, range: FactRange) ?[]const PackMemberDemand {
        const start: usize = range.start;
        const end = std.math.add(usize, start, range.len) catch return null;
        if (end > self.pack_values.items.len or end > self.pack_demands.items.len) return null;
        return self.pack_demands.items[start..end];
    }

    fn demandsForRangeMut(self: *SemanticGraph, range: FactRange) ?[]PackMemberDemand {
        const start: usize = range.start;
        const end = std.math.add(usize, start, range.len) catch return null;
        if (end > self.pack_values.items.len or end > self.pack_demands.items.len) return null;
        return self.pack_demands.items[start..end];
    }

    fn validPackArity(arity: PackArity, member_count: usize) bool {
        const count = std.math.cast(u32, member_count) orelse return false;
        return switch (arity) {
            .unknown => member_count == 0,
            .fixed => |n| n == count,
            .open => |prefix| prefix == count,
        };
    }

    /// Publish one exact ordered pack. Members must already be graph values;
    /// this operation establishes pack membership, never value identity.
    pub fn publishPack(
        self: *SemanticGraph,
        pack_id: id,
        members: []const PackMember,
        arity: PackArity,
        producer: Card,
    ) !void {
        const pack_node = self.get(pack_id) orelse return error.InvalidPackFact;
        if (pack_node.kind != .value or !validPackArity(arity, members.len)) {
            return error.InvalidPackFact;
        }
        if (self.pack_rows.contains(pack_id)) return error.DuplicatePackFact;
        for (members) |member| {
            const node = self.get(member.value) orelse return error.InvalidPackMember;
            if (node.descriptor == null) return error.InvalidPackMember;
        }
        switch (producer) {
            .one => |entity| if (self.get(entity) == null) return error.InvalidPackProducer,
            else => {},
        }

        const start = self.pack_values.items.len;
        errdefer self.pack_values.shrinkRetainingCapacity(start);
        errdefer self.pack_demands.shrinkRetainingCapacity(start);
        const range = try factRange(start, members.len);
        for (members) |member| {
            try self.pack_values.append(self.alloc, member.value);
            try self.pack_demands.append(self.alloc, member.demand);
        }
        const row = try coordinateForLength(self.pack_facts.items.len);
        try self.pack_facts.append(self.alloc, .{
            .pack = pack_id,
            .members = range,
            .arity = arity,
            .producer = producer,
        });
        errdefer _ = self.pack_facts.pop();
        try self.pack_rows.putNoClobber(self.alloc, pack_id, row);
    }

    pub fn pack(self: *const SemanticGraph, pack_id: id) ?*const PackFact {
        const row = self.pack_rows.get(pack_id) orelse return null;
        if (row >= self.pack_facts.items.len) return null;
        const fact = &self.pack_facts.items[row];
        if (fact.pack != pack_id or self.get(pack_id) == null) return null;
        const members = self.membersForRange(fact.members) orelse return null;
        if (!validPackArity(fact.arity, members.len)) return null;
        _ = self.demandsForRange(fact.members) orelse return null;
        for (members) |member| {
            const node = self.get(member) orelse return null;
            if (node.descriptor == null) return null;
        }
        switch (fact.producer) {
            .one => |entity| if (self.get(entity) == null) return null,
            else => {},
        }
        return fact;
    }

    pub fn packMembers(self: *const SemanticGraph, pack_id: id) ?[]const id {
        const fact = self.pack(pack_id) orelse return null;
        return self.membersForRange(fact.members);
    }

    pub fn packMemberDemands(self: *const SemanticGraph, pack_id: id) ?[]const PackMemberDemand {
        const fact = self.pack(pack_id) orelse return null;
        return self.demandsForRange(fact.members);
    }

    fn publishAggregate(self: *SemanticGraph, fact: AggregateFact) !void {
        const node = self.get(fact.aggregate) orelse return error.InvalidAggregateFact;
        _ = self.get(fact.owner) orelse return error.InvalidAggregateFact;
        if (node.descriptor == null or self.pack(fact.members_pack) == null) {
            return error.InvalidAggregateFact;
        }
        if (self.aggregate_rows.contains(fact.aggregate)) return error.DuplicateAggregateFact;
        switch (fact.place) {
            .one => |site| {
                const owner = self.get(fact.owner) orelse return error.InvalidAggregateFact;
                if (owner.scope == null) {
                    const census = if (self.places) |*places| places else return error.InvalidAggregateFact;
                    if (site >= census.count()) return error.InvalidAggregateFact;
                } else {
                    const body = self.bodyOf(fact.owner) orelse return error.InvalidAggregateFact;
                    if (site >= body.places.count()) return error.InvalidAggregateFact;
                }
            },
            .unknown, .none => {},
        }
        const row = try coordinateForLength(self.aggregate_facts.items.len);
        try self.aggregate_facts.append(self.alloc, fact);
        errdefer _ = self.aggregate_facts.pop();
        try self.aggregate_rows.putNoClobber(self.alloc, fact.aggregate, row);
    }

    pub fn aggregate(self: *const SemanticGraph, aggregate_id: id) ?*const AggregateFact {
        const row = self.aggregate_rows.get(aggregate_id) orelse return null;
        if (row >= self.aggregate_facts.items.len) return null;
        const fact = &self.aggregate_facts.items[row];
        if (fact.aggregate != aggregate_id) return null;
        const node = self.get(aggregate_id) orelse return null;
        _ = node.descriptor orelse return null;
        const members_fact = self.pack(fact.members_pack) orelse return null;
        switch (members_fact.producer) {
            .one => |producer| if (producer != aggregate_id) return null,
            else => return null,
        }
        const members = self.packMembers(fact.members_pack) orelse return null;
        for (members) |member| {
            const member_node = self.get(member) orelse return null;
            _ = member_node.descriptor orelse return null;
            if (fact.contents_known != .yes or self.exactI64(member) != null) continue;
            const nested_row = self.aggregate_rows.get(member) orelse return null;
            if (nested_row >= self.aggregate_facts.items.len) return null;
            const nested = self.aggregate_facts.items[nested_row];
            if (nested.aggregate != member or nested.contents_known != .yes) return null;
        }
        return fact;
    }

    /// The current physical slice is uniform positional arrays. Keep that
    /// restriction on its consumer, not on `AggregateFact`: record-valued
    /// results extend the same aggregate/member-pack fact without acquiring a
    /// second semantic identity or being rejected by serialization.
    fn positionalAggregate(self: *const SemanticGraph, aggregate_id: id) ?*const AggregateFact {
        const fact = self.aggregate(aggregate_id) orelse return null;
        const descriptor = (self.get(aggregate_id) orelse return null).descriptor orelse return null;
        if (descriptor != .array) return null;
        const extent = descriptor.array.size orelse return null;
        const members = self.packMembers(fact.members_pack) orelse return null;
        if (members.len != extent) return null;
        for (members) |member| {
            const member_descriptor = (self.get(member) orelse return null).descriptor orelse return null;
            if (!member_descriptor.eql(descriptor.array.elem.*)) return null;
        }
        return fact;
    }

    pub fn aggregateMembers(self: *const SemanticGraph, aggregate_id: id) ?[]const id {
        const fact = self.aggregate(aggregate_id) orelse return null;
        return self.packMembers(fact.members_pack);
    }

    pub fn aggregateCount(self: *const SemanticGraph) usize {
        return self.aggregate_facts.items.len;
    }

    pub fn aggregateAt(self: *const SemanticGraph, row: usize) ?*const AggregateFact {
        if (row >= self.aggregate_facts.items.len) return null;
        const fact = &self.aggregate_facts.items[row];
        return if (self.aggregate(fact.aggregate) != null) fact else null;
    }

    pub fn aggregateOrigin(self: *const SemanticGraph, expr: *const ast.Expr) ?id {
        return self.aggregate_origins.get(@intFromPtr(expr));
    }

    pub fn aggregatePlace(self: *const SemanticGraph, aggregate_id: id) ?*const place.Place {
        const fact = self.aggregate(aggregate_id) orelse return null;
        const site = switch (fact.place) {
            .one => |site| site,
            .unknown, .none => return null,
        };
        const owner = self.get(fact.owner) orelse return null;
        const census = if (owner.scope == null)
            if (self.places) |*places| places else return null
        else if (self.bodyOf(fact.owner)) |body|
            &body.places
        else
            return null;
        return census.at(site);
    }

    pub fn aggregateAccess(self: *const SemanticGraph, occurrence: id) ?*const ApplicationFact {
        const relation = self.aggregate_access_relation orelse return null;
        const fact = self.application(occurrence) orelse return null;
        if (self.applicationRelation(occurrence) != relation) return null;
        const subject = self.applicationSubject(occurrence) orelse return null;
        switch (fact.applied) {
            .one => |applied| if (applied != subject) return null,
            else => return null,
        }
        switch (fact.target) {
            .one => |target| if (target != relation) return null,
            else => return null,
        }
        const operands = self.packMembers(fact.operand_pack) orelse return null;
        const results = self.packMembers(fact.result_pack) orelse return null;
        if (operands.len != 1 or results.len != 1) return null;
        const aggregate_fact = self.positionalAggregate(subject) orelse return null;
        const subject_node = self.get(aggregate_fact.aggregate) orelse return null;
        const subject_descriptor = subject_node.descriptor orelse return null;
        if (subject_descriptor != .array) return null;
        const key = self.get(operands[0]) orelse return null;
        if (key.descriptor == null or key.descriptor.? != .i64) return null;
        const result = self.get(results[0]) orelse return null;
        const result_descriptor = result.descriptor orelse return null;
        if (!result_descriptor.eql(subject_descriptor.array.elem.*)) return null;
        if (result_descriptor == .array and self.positionalAggregate(results[0]) == null) return null;
        return fact;
    }

    pub fn aggregateProducer(self: *const SemanticGraph, aggregate_id: id) ?id {
        var producer: ?id = null;
        for (self.application_facts.items) |fact| {
            if (self.aggregateAccess(fact.application) == null) continue;
            const results = self.packMembers(fact.result_pack) orelse continue;
            if (results.len != 1 or results[0] != aggregate_id) continue;
            if (producer != null and producer.? != fact.application) return null;
            producer = fact.application;
        }
        return producer;
    }

    pub fn valueExpression(self: *const SemanticGraph, value: id) ?*const ast.Expr {
        const node = self.get(value) orelse return null;
        if (node.kind != .value) return null;
        const raw = node.ast_ref orelse return null;
        return @ptrCast(@alignCast(raw));
    }

    pub fn exactI64(self: *const SemanticGraph, value: id) ?i64 {
        const row = self.exact_i64_rows.get(value) orelse return null;
        if (row >= self.exact_i64_facts.items.len) return null;
        const fact = self.exact_i64_facts.items[row];
        if (fact.value != value or self.get(value) == null) return null;
        return fact.content;
    }

    fn publishExactI64(self: *SemanticGraph, value: id, content: i64) !void {
        const node = self.get(value) orelse return error.InvalidExactValueFact;
        if (node.descriptor == null or node.descriptor.? != .i64) return error.InvalidExactValueFact;
        if (self.exact_i64_rows.contains(value)) return error.DuplicateExactValueFact;
        const row = try coordinateForLength(self.exact_i64_facts.items.len);
        try self.exact_i64_facts.append(self.alloc, .{ .value = value, .content = content });
        errdefer _ = self.exact_i64_facts.pop();
        try self.exact_i64_rows.putNoClobber(self.alloc, value, row);
    }

    pub fn packEffect(self: *const SemanticGraph, pack_id: id) Card {
        const fact = self.pack(pack_id) orelse return .unknown;
        const producer = switch (fact.producer) {
            .one => |entity| entity,
            else => return .unknown,
        };
        const application_fact = self.application(producer) orelse return .unknown;
        return application_fact.effect;
    }

    pub fn packWorld(self: *const SemanticGraph, pack_id: id) Card {
        const fact = self.pack(pack_id) orelse return .unknown;
        const producer = switch (fact.producer) {
            .one => |entity| entity,
            else => return .unknown,
        };
        return self.applicationWorld(producer);
    }

    pub fn selectPackRealization(self: *SemanticGraph, pack_id: id, realization: PackRealization) !void {
        if (self.incarnation_coordinate != null) return error.GraphIncarnationFrozen;
        const row = self.pack_rows.get(pack_id) orelse return error.InvalidPackFact;
        const fact = self.pack(pack_id) orelse return error.InvalidPackFact;
        const demands = self.demandsForRange(fact.members) orelse return error.InvalidPackFact;
        switch (realization) {
            .none => for (demands) |demand| {
                if (demand != .discard) return error.DemandedPackCannotDisappear;
            },
            .scalar => switch (fact.arity) {
                .fixed => |n| if (n != 1 or demands[0] == .discard) return error.InvalidPackRealization,
                else => return error.InvalidPackRealization,
            },
            else => {},
        }
        self.pack_facts.items[row].realization = realization;
    }

    fn publishPackAdjustment(self: *SemanticGraph, adjustment: PackAdjustment) !void {
        if (self.application(adjustment.application) == null) return error.InvalidPackAdjustment;
        if (self.pack(adjustment.source_pack) == null or self.pack(adjustment.target_pack) == null) {
            return error.InvalidPackAdjustment;
        }
        if (self.adjustment_rows.contains(adjustment.application)) return error.DuplicatePackAdjustment;
        const row = try coordinateForLength(self.pack_adjustments.items.len);
        try self.pack_adjustments.append(self.alloc, adjustment);
        errdefer _ = self.pack_adjustments.pop();
        try self.adjustment_rows.putNoClobber(self.alloc, adjustment.application, row);
    }

    pub fn packAdjustment(self: *const SemanticGraph, application_id: id) ?*const PackAdjustment {
        const row = self.adjustment_rows.get(application_id) orelse return null;
        if (row >= self.pack_adjustments.items.len) return null;
        const adjustment = &self.pack_adjustments.items[row];
        if (adjustment.application != application_id) return null;
        const application_fact = self.application(application_id) orelse return null;
        if (application_fact.result_pack != adjustment.source_pack) return null;
        if (self.pack(adjustment.target_pack) == null) return null;
        return adjustment;
    }

    pub fn isApplicationCandidate(self: *const SemanticGraph, entity: id) bool {
        return entity < self.application_candidates.bit_length and
            self.application_candidates.isSet(entity);
    }

    fn markApplicationCandidate(self: *SemanticGraph, entity: id) !void {
        if (self.get(entity) == null) return error.InvalidApplicationFact;
        try self.ensureApplicationRows();
        self.application_candidates.set(entity);
    }

    fn publishApplication(
        self: *SemanticGraph,
        occurrence: id,
        applied: id,
        relation: id,
        target: id,
        subject: ?id,
        arguments: []const id,
        results: []const id,
    ) !void {
        const application_node = self.get(occurrence) orelse return error.InvalidApplicationFact;
        const want = application_node.descriptor orelse return error.InvalidApplicationFact;
        const caller = application_node.scope orelse return error.InvalidApplicationCaller;
        const application_span = application_node.span;
        const result_consumption = application_node.demand orelse return error.InvalidApplicationFact;
        if (!self.isApplicationCandidate(occurrence) or
            application_node.demand == null) return error.InvalidApplicationFact;
        _ = self.get(relation) orelse return error.InvalidApplicationRelation;
        if (!self.callable(relation)) return error.InvalidApplicationRelation;
        _ = self.get(applied) orelse return error.InvalidApplicationApplied;
        _ = self.get(target) orelse return error.InvalidApplicationTarget;
        if (!self.callable(target)) return error.InvalidApplicationTarget;
        const caller_node = self.get(caller) orelse return error.InvalidApplicationCaller;
        if (!self.callable(caller) and caller_node.scope != null) return error.InvalidApplicationCaller;
        if (subject) |entity| {
            const node = self.get(entity) orelse return error.InvalidApplicationSubject;
            if (node.descriptor == null) return error.InvalidApplicationSubject;
        }
        for (arguments) |entity| {
            const node = self.get(entity) orelse return error.InvalidApplicationArgument;
            if (node.descriptor == null) return error.InvalidApplicationArgument;
        }
        for (results, 0..) |entity, i| {
            const node = self.get(entity) orelse return error.InvalidApplicationResult;
            if (node.descriptor == null or (i == 0 and !node.descriptor.?.eql(want))) {
                return error.InvalidApplicationResult;
            }
        }

        try self.ensureApplicationRows();
        if (self.application_presence.isSet(occurrence)) return error.DuplicateApplicationFact;

        const operand_members = try self.alloc.alloc(PackMember, arguments.len);
        defer self.alloc.free(operand_members);
        for (arguments, 0..) |value, i| operand_members[i] = .{ .value = value, .demand = .value };
        const result_members = try self.alloc.alloc(PackMember, results.len);
        defer self.alloc.free(result_members);
        for (results, 0..) |value, i| {
            result_members[i] = .{
                .value = value,
                .demand = switch (result_consumption) {
                    .unknown => .unknown,
                    .discard => .discard,
                    .single => if (i == 0) .value else .discard,
                    .multi => .value,
                },
            };
        }

        const operand_pack = try self.addChild(occurrence, .{
            .kind = .value,
            .span = application_span,
            .knowledge = .stable,
            .stage = .sema,
        });
        const result_pack = try self.addChild(occurrence, .{
            .kind = .value,
            .span = application_span,
            .knowledge = .stable,
            .stage = .sema,
        });
        try self.publishPack(operand_pack, operand_members, .{ .fixed = @intCast(arguments.len) }, .{ .one = occurrence });
        try self.publishPack(result_pack, result_members, .{ .fixed = @intCast(results.len) }, .{ .one = occurrence });

        const row = try coordinateForLength(self.application_facts.items.len);
        try self.application_facts.append(self.alloc, .{
            .application = occurrence,
            .operand_pack = operand_pack,
            .result_pack = result_pack,
            .applied = .{ .one = applied },
            .target = .{ .one = target },
        });
        self.application_rows.items[occurrence] = row;
        self.application_presence.set(occurrence);
        try self.addEdge(.{ .from = occurrence, .to = relation, .kind = .binding });
        if (subject) |entity| {
            try self.addEdge(.{
                .from = occurrence,
                .to = entity,
                .kind = .projection,
                .position = application_subject_projection,
            });
        }
        try self.home_apps.push(self.alloc, caller, occurrence);
    }

    pub fn applications(self: *const SemanticGraph) []const ApplicationFact {
        return self.application_facts.items;
    }

    pub fn application(self: *const SemanticGraph, occurrence: id) ?*const ApplicationFact {
        if (occurrence >= self.application_rows.items.len or
            occurrence >= self.application_presence.bit_length or
            !self.application_presence.isSet(occurrence)) return null;
        const row = self.application_rows.items[occurrence];
        if (row >= self.application_facts.items.len) return null;
        const fact = &self.application_facts.items[row];
        if (fact.application != occurrence) return null;
        const application_node = self.get(fact.application) orelse return null;
        const want = application_node.descriptor orelse return null;
        const caller = application_node.scope orelse return null;
        if (!self.isApplicationCandidate(fact.application) or
            application_node.demand == null) return null;
        const applied = switch (fact.applied) {
            .one => |entity| entity,
            .unknown, .none => return null,
        };
        _ = self.get(applied) orelse return null;
        const target = switch (fact.target) {
            .one => |entity| entity,
            .unknown, .none => return null,
        };
        if (self.get(target) == null or !self.callable(target)) return null;
        _ = self.bindingRelation(fact.application) orelse return null;
        const caller_node = self.get(caller) orelse return null;
        if (!self.callable(caller) and caller_node.scope != null) return null;
        if (self.uniqueSubjectProjection(fact.application)) |entity| {
            const node = self.get(entity) orelse return null;
            if (node.descriptor == null) return null;
        }
        const arguments = self.packMembers(fact.operand_pack) orelse return null;
        const results = self.packMembers(fact.result_pack) orelse return null;
        for (arguments) |member| {
            const node = self.get(member) orelse return null;
            if (node.descriptor == null) return null;
        }
        for (results, 0..) |member, i| {
            const node = self.get(member) orelse return null;
            if (node.descriptor == null or (i == 0 and !node.descriptor.?.eql(want))) return null;
        }
        return fact;
    }

    pub fn applicationArguments(self: *const SemanticGraph, occurrence: id) ?[]const id {
        const fact = self.application(occurrence) orelse return null;
        return self.packMembers(fact.operand_pack);
    }

    pub fn applicationResults(self: *const SemanticGraph, occurrence: id) ?[]const id {
        const fact = self.application(occurrence) orelse return null;
        return self.packMembers(fact.result_pack);
    }

    pub fn unresolvedApplicationCount(self: *const SemanticGraph, caller: ?id) usize {
        var count: usize = 0;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse {
                count += 1;
                continue;
            };
            const node = self.get(entity) orelse {
                count += 1;
                continue;
            };
            if (caller) |caller_id| {
                if (node.scope != caller_id) continue;
            }
            if (self.application(entity) == null) count += 1;
        }
        return count;
    }

    /// Bootstrap world and string descriptor faces lower through dedicated
    /// direct rules until graph vocabulary owns them (GAP-155). They remain
    /// application candidates but must not block gate transport on direct.
    pub fn unresolvedApplicationCountExcludingBootstrap(self: *const SemanticGraph, caller: ?id) usize {
        var count: usize = 0;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse {
                count += 1;
                continue;
            };
            const node = self.get(entity) orelse {
                count += 1;
                continue;
            };
            if (caller) |caller_id| {
                if (node.scope != caller_id) continue;
            }
            if (self.application(entity) != null) continue;
            if (isBootstrapApplicationNode(self, entity)) continue;
            count += 1;
        }
        return count;
    }

    /// First unresolved non-bootstrap application occurrence, if any.
    /// Diagnostic routing only — not identity selection among alternatives.
    pub fn firstUnresolvedApplicationExcludingBootstrap(self: *const SemanticGraph, caller: ?id) ?id {
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse continue;
            const node = self.get(entity) orelse continue;
            if (caller) |caller_id| {
                if (node.scope != caller_id) continue;
            }
            if (self.application(entity) != null) continue;
            if (isBootstrapApplicationNode(self, entity)) continue;
            return entity;
        }
        return null;
    }

    pub fn isBootstrapApplicationNode(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        const raw = node.ast_ref orelse return false;
        const expr: *const ast.Expr = @ptrCast(@alignCast(raw));
        return self.bootstrapApplicationExpr(expr);
    }

    /// HOW MUCH OF THIS MODULE'S APPLICATION SURFACE THE GRAPH ACTUALLY OWNS.
    ///
    /// Three answers, not two, and the middle one is the whole point:
    ///
    ///   published  the graph identified the relation. Lowering consumes an
    ///              exact id and every downstream fact (effect, emit order,
    ///              fold licence) is available.
    ///   bootstrap  the graph identified NOTHING and lowering proceeds anyway,
    ///              by recognizing the callee's SPELLING in
    ///              `native_bootstrap.applicationExprInModule`. `s:len()`,
    ///              `print(v)`, `mem.read_i64(p,o)`. The code emitted is real;
    ///              the fact behind it is not in the graph, so nothing
    ///              downstream can reason about it.
    ///   blocking   the graph identified nothing and no bootstrap face claims
    ///              it. This is the set `native_backend` refuses the module on
    ///              (`unresolved-application-facts`) and `dnir_lower` refuses
    ///              it on second (`missing-application-id`).
    ///
    /// Before this, an outside consumer could see `applications` and
    /// `unresolved_applications` and had no way to tell the middle column from
    /// the right one — so "the graph does not know what this call is" and "the
    /// graph does not know what this call is AND that stops the compiler" read
    /// as the same number. They are 4:1 apart corpus-wide, and only one of them
    /// is a refusal. A census that cannot separate them cannot rank any work.
    pub const FactCoverage = struct {
        /// Every `.call`/`.method_call` the lift marked as an application site.
        candidates: usize = 0,
        /// Candidates carrying a published `ApplicationFact`.
        published: usize = 0,
        /// Unpublished, but recognized by a bootstrap face — lowered by spelling.
        bootstrap: usize = 0,
        /// Unpublished and unrecognized — the refusal set.
        blocking: usize = 0,

        pub fn unresolved(self: FactCoverage) usize {
            return self.bootstrap + self.blocking;
        }
    };

    pub fn factCoverage(self: *const SemanticGraph) FactCoverage {
        var out: FactCoverage = .{};
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse continue;
            if (self.get(entity) == null) continue;
            out.candidates += 1;
            if (self.application(entity) != null) {
                out.published += 1;
            } else if (self.isBootstrapApplicationNode(entity)) {
                out.bootstrap += 1;
            } else {
                out.blocking += 1;
            }
        }
        return out;
    }

    pub fn gateTransportModule(self: *const SemanticGraph) bool {
        if (self.module_path) |path| return native_bootstrap.gateTransport(path);
        return false;
    }

    pub fn bootstrapApplicationExpr(self: *const SemanticGraph, expr: *const ast.Expr) bool {
        return isBootstrapApplicationExpr(self, expr);
    }

    fn isBootstrapApplicationExpr(self: *const SemanticGraph, expr: *const ast.Expr) bool {
        return native_bootstrap.applicationExprInModule(expr, self.module_path);
    }

    /// The dotted home of a callable declared OUTSIDE this module, or null when
    /// the callable is this module's own. Realization asks this to decide
    /// whether a call is a local branch or a relocation against another home's
    /// symbol; nothing else may re-derive the answer.
    pub fn foreignHome(self: *const SemanticGraph, entity: id) ?[]const u8 {
        const node = self.get(entity) orelse return null;
        return node.foreign_home;
    }

    fn findFuncDecl(self: *const SemanticGraph, target: *const ast.FuncDecl) ?id {
        const raw: *const anyopaque = @ptrCast(target);
        return self.origin.get(@intFromPtr(raw));
    }

    /// A name-facing projection is diagnostic/tooling input, never identity.
    /// Ambiguity refuses instead of selecting the first matching graph entity.
    fn findUniqueByNameOfKind(self: *const SemanticGraph, name: []const u8, kind: NodeKind) ?id {
        var match: ?id = null;
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != kind) continue;
            const node_name = node.name orelse continue;
            if (!std.mem.eql(u8, node_name, name)) continue;
            if (match != null) return null;
            match = @intCast(i);
        }
        return match;
    }

    /// Named entity of `kind` in the contains chain of `start`.
    /// Downstream uses published edges; this walk is lift and home-local resolve only.
    pub fn resolveInHome(
        self: *const SemanticGraph,
        start: id,
        name: []const u8,
        kind: NodeKind,
    ) ?id {
        var scope: ?id = start;
        while (scope) |s| {
            for (self.nested.of(s)) |child| {
                const node = self.get(child) orelse continue;
                if (node.kind != kind) continue;
                const node_name = node.name orelse continue;
                if (std.mem.eql(u8, node_name, name)) return child;
            }
            scope = self.get(s).?.scope;
        }
        return null;
    }

    fn publishDescriptorRefEdge(self: *SemanticGraph, from: id, to: id, inline_ref: bool) !void {
        try self.addEdge(.{ .from = from, .to = to, .kind = .descriptor_ref, .inline_ref = inline_ref });
        try self.descriptor_refs.push(self.alloc, from, to, inline_ref);
    }

    fn publishDescriptorRefType(self: *SemanticGraph, descriptor: id, rt: types.ResolvedType, inline_ref: bool) !void {
        switch (rt) {
            .pointer => |p| {
                try self.publishDescriptorRefType(descriptor, p.*, false);
            },
            .@"struct" => |s| {
                const start = self.homeOf(descriptor) orelse descriptor;
                if (self.resolveInHome(start, s.name, .table_shape)) |ref| {
                    try self.publishDescriptorRefEdge(descriptor, ref, inline_ref);
                }
            },
            .table_type => |t| {
                for (t.fields) |field| {
                    try self.publishDescriptorRefType(descriptor, field.typ, inline_ref);
                }
            },
            .enum_type => |e| {
                const start = self.homeOf(descriptor) orelse descriptor;
                if (self.resolveInHome(start, e.name, .enum_shape)) |ref| {
                    try self.publishDescriptorRefEdge(descriptor, ref, inline_ref);
                }
                for (e.variants) |variant| {
                    if (variant.payload) |payload| {
                        for (payload) |member| {
                            try self.publishDescriptorRefType(descriptor, member, inline_ref);
                        }
                    }
                }
            },
            else => {},
        }
    }

    /// Source-resolution boundary: publish descriptor-id edges once at lift.
    pub fn publishDescriptorRefEdges(self: *SemanticGraph, descriptor: id, rt: types.ResolvedType) !void {
        try self.publishDescriptorRefType(descriptor, rt, true);
    }

    pub const DescriptorRefTarget = struct {
        target: id,
        inline_ref: bool,
    };

    /// Exact descriptor entities referenced by published `.descriptor_ref` edges.
    pub fn descriptorRefsOf(self: *const SemanticGraph, descriptor: id, alloc: std.mem.Allocator) ![]const DescriptorRefTarget {
        if (!self.hasDescriptorFacts(descriptor)) return error.InvalidDescriptorEntity;
        const hits = self.descriptor_refs.of(descriptor);
        var out: std.ArrayListUnmanaged(DescriptorRefTarget) = .empty;
        errdefer out.deinit(alloc);
        try out.ensureTotalCapacity(alloc, hits.len);
        for (hits) |hit| {
            out.appendAssumeCapacity(.{ .target = hit.to, .inline_ref = hit.inline_ref });
        }
        return try out.toOwnedSlice(alloc);
    }

    pub fn entityOf(self: *const SemanticGraph, e: id) ?*const Node {
        return self.get(e);
    }

    pub fn membersOf(self: *const SemanticGraph, home: id, alloc: std.mem.Allocator) ![]const id {
        const Entry = struct { pos: u16, entity: id };
        var out: std.ArrayListUnmanaged(Entry) = .empty;
        errdefer out.deinit(alloc);
        for (self.edges.items) |edge| {
            if (edge.from != home or edge.kind != .member) continue;
            try out.append(alloc, .{ .pos = edge.position, .entity = edge.to });
        }
        std.mem.sort(Entry, out.items, {}, struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return a.pos < b.pos;
            }
        }.lessThan);
        var ids: std.ArrayListUnmanaged(id) = .empty;
        errdefer ids.deinit(alloc);
        for (out.items) |entry| try ids.append(alloc, entry.entity);
        return try ids.toOwnedSlice(alloc);
    }

    fn publishMember(
        self: *SemanticGraph,
        home: id,
        span: SpanRef,
        name: []const u8,
        position: u16,
        descriptor: ?types.ResolvedType,
    ) !id {
        const member_id = try self.addChild(home, .{
            .kind = .value,
            .span = span,
            .name = name,
            .descriptor = descriptor,
            .knowledge = if (descriptor) |d| semantic_algebra.knowledgeOfType(d) else .stable,
            .stage = .sema,
        });
        try self.addEdge(.{ .from = home, .to = member_id, .kind = .member, .position = position });
        return member_id;
    }

    fn publishTableShapeMembers(self: *SemanticGraph, home: id, span: SpanRef, rt: types.ResolvedType) !void {
        if (rt != .table_type) return;
        for (rt.table_type.fields, 0..) |field, i| {
            _ = try self.publishMember(home, span, field.name, @intCast(i), field.typ);
        }
    }

    fn publishEnumShapeMembers(self: *SemanticGraph, home: id, span: SpanRef, ed: *const ast.EnumDef) !void {
        for (ed.variants, 0..) |variant, i| {
            _ = try self.publishMember(home, span, variant.name, @intCast(i), null);
        }
    }

    fn addDescriptorShapeEdge(
        self: *SemanticGraph,
        entity: id,
        position: u16,
        scope: id,
        descriptor: types.ResolvedType,
    ) !void {
        const shape = switch (descriptor) {
            .@"struct" => |s| self.resolveInHome(scope, s.name, .table_shape),
            else => null,
        } orelse return;
        for (self.edges.items) |edge| {
            if (edge.from == entity and edge.kind == .descriptor and edge.position == position) {
                if (edge.to != shape) return error.InvalidDescriptorFact;
                return;
            }
        }
        try self.addEdge(.{ .from = entity, .to = shape, .kind = .descriptor, .position = position });
    }

    /// Bind each field to the exact nested descriptor shape after every alias
    /// in the home exists. Doing this in the alias-construction loop made a
    /// forward declaration silently lose its edge and forced consumers to
    /// recover the nested shape by name.
    fn attachMemberDescriptorShapes(self: *SemanticGraph, home: id) !void {
        for (self.nested.of(home)) |shape| {
            const node = self.get(shape) orelse continue;
            if (node.kind != .table_shape) continue;
            const members = try self.membersOf(shape, self.alloc);
            defer self.alloc.free(members);
            for (members) |member| {
                const descriptor = (self.get(member) orelse continue).descriptor orelse continue;
                try self.addDescriptorShapeEdge(member, 0, home, descriptor);
            }
        }
    }

    fn attachCallableResultShapes(self: *SemanticGraph, home: id) !void {
        for (self.nested.of(home)) |relation| {
            const node = self.get(relation) orelse continue;
            if (node.kind != .func) continue;
            const descriptor = node.result_descriptor orelse continue;
            try self.addDescriptorShapeEdge(relation, 0, home, descriptor);
        }
    }

    // `capturesOf` lived here. Its only caller was `graph_query.capture`, which
    // had no caller at all; with that deleted it kept one test and no consumer.
    // The `.capture` EDGE stays and is operative — `publishApplicationEffects`
    // blocks any relation holding one — so the test below reads the edge.

    pub fn homeOf(self: *const SemanticGraph, entity: id) ?id {
        const node = self.get(entity) orelse return null;
        return node.scope;
    }

    /// Applicable relations/callables directly under one home id (source order).
    pub fn callablesInHome(self: *const SemanticGraph, home: id, alloc: std.mem.Allocator) ![]const id {
        var out: std.ArrayListUnmanaged(id) = .empty;
        errdefer out.deinit(alloc);
        for (self.nested.of(home)) |child| {
            if (!self.callable(child)) continue;
            try out.append(alloc, child);
        }
        return try out.toOwnedSlice(alloc);
    }

    /// Published application occurrences owned by one home (`law.fact.locality`).
    pub fn applicationsIn(self: *const SemanticGraph, home: id) []const id {
        return self.home_apps.of(home);
    }

    /// Alias for query-layer locality (`applicationsIn`).
    pub fn applicationsInCaller(self: *const SemanticGraph, caller: id) []const id {
        return self.applicationsIn(caller);
    }

    /// Migration alias — prefer `callablesInHome` (`law.module.zero`).
    pub fn functionsInModule(self: *const SemanticGraph, module: id, alloc: std.mem.Allocator) ![]const id {
        return self.callablesInHome(module, alloc);
    }

    /// Exact entities of one node kind in resident graph order.
    pub fn entitiesOfKind(self: *const SemanticGraph, kind: NodeKind, alloc: std.mem.Allocator) ![]const id {
        var out: std.ArrayListUnmanaged(id) = .empty;
        errdefer out.deinit(alloc);
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != kind) continue;
            try out.append(alloc, @intCast(i));
        }
        return try out.toOwnedSlice(alloc);
    }

    /// Projection specialization value ids for one application occurrence.
    pub fn projectionsOf(self: *const SemanticGraph, occurrence: id, alloc: std.mem.Allocator) ![]const id {
        const Entry = struct { pos: u16, entity: id };
        var out: std.ArrayListUnmanaged(Entry) = .empty;
        errdefer out.deinit(alloc);
        for (self.edges.items) |edge| {
            if (edge.from != occurrence or edge.kind != .projection) continue;
            if (edge.position == application_subject_projection) continue;
            try out.append(alloc, .{ .pos = edge.position, .entity = edge.to });
        }
        std.mem.sort(Entry, out.items, {}, struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return a.pos < b.pos;
            }
        }.lessThan);
        var ids: std.ArrayListUnmanaged(id) = .empty;
        errdefer ids.deinit(alloc);
        for (out.items) |entry| try ids.append(alloc, entry.entity);
        return try ids.toOwnedSlice(alloc);
    }

    fn publishApplicationProjections(self: *SemanticGraph, occurrence: id) !void {
        const node = self.get(occurrence) orelse return;
        const shape = node.call_shape orelse return;
        if (shape.method_name) |method| {
            const projection_id = try self.addChild(occurrence, .{
                .kind = .value,
                .span = node.span,
                .name = method,
                .knowledge = .observed,
                .stage = .sema,
            });
            try self.addEdge(.{ .from = occurrence, .to = projection_id, .kind = .projection, .position = 0 });
        }
    }

    pub fn provenanceOf(self: *const SemanticGraph, entity: id) ?SpanRef {
        const node = self.get(entity) orelse return null;
        return node.span;
    }

    /// Migration projection for callers that still possess only function text.
    /// Semantic consumers must retain a declaration or id instead.
    pub fn findFunc(self: *const SemanticGraph, name: []const u8) ?id {
        return self.findUniqueByNameOfKind(name, .func);
    }

    /// Relation selected for a checked application. Producer is the unique
    /// `.binding` edge from the occurrence to a func/relation entity.
    pub fn applicationRelation(self: *const SemanticGraph, occurrence: id) ?id {
        _ = self.application(occurrence) orelse return null;
        return self.bindingRelation(occurrence);
    }

    /// Exact semantic value occupying the applied role.
    pub fn applicationApplied(self: *const SemanticGraph, occurrence: id) ?id {
        const fact = self.application(occurrence) orelse return null;
        return switch (fact.applied) {
            .one => |entity| entity,
            .unknown, .none => null,
        };
    }

    /// Exact callable implementation selected by semantic analysis.
    pub fn applicationTarget(self: *const SemanticGraph, occurrence: id) ?id {
        const fact = self.application(occurrence) orelse return null;
        return switch (fact.target) {
            .one => |entity| entity,
            .unknown, .none => null,
        };
    }

    fn bindingRelation(self: *const SemanticGraph, occurrence: id) ?id {
        var match: ?id = null;
        for (self.outEdges(occurrence)) |ei| {
            if (ei >= self.edges.items.len) continue;
            const edge = self.edges.items[ei];
            if (edge.from != occurrence or edge.kind != .binding) continue;
            if (self.get(edge.to) == null) continue;
            if (!self.callable(edge.to)) continue;
            if (match != null) return null;
            match = edge.to;
        }
        return match;
    }

    fn uniqueSubjectProjection(self: *const SemanticGraph, occurrence: id) ?id {
        var match: ?id = null;
        for (self.outEdges(occurrence)) |ei| {
            if (ei >= self.edges.items.len) continue;
            const edge = self.edges.items[ei];
            if (edge.from != occurrence or edge.kind != .projection) continue;
            if (edge.position != application_subject_projection) continue;
            if (self.get(edge.to) == null) continue;
            if (match != null) return null;
            match = edge.to;
        }
        return match;
    }

    /// Result value produced by a checked application.
    pub fn applicationResult(self: *const SemanticGraph, occurrence: id) ?id {
        const results = self.applicationResults(occurrence) orelse return null;
        if (results.len != 1) return null;
        return results[0];
    }

    /// Result descriptor lives on the application node — not a copied fact field.
    pub fn applicationDescriptor(self: *const SemanticGraph, occurrence: id) ?types.ResolvedType {
        const node = self.get(occurrence) orelse return null;
        return node.descriptor;
    }

    /// Demand lives on the application node — not a copied fact field.
    pub fn applicationDemand(self: *const SemanticGraph, occurrence: id) ?types.ReturnConsumption {
        const node = self.get(occurrence) orelse return null;
        return node.demand;
    }

    /// Provenance lives on the application node — not a copied fact field.
    pub fn applicationProvenance(self: *const SemanticGraph, occurrence: id) ?SpanRef {
        return self.provenanceOf(occurrence);
    }

    /// Evaluation stage lives on the application node — not a copied fact field.
    pub fn applicationStage(self: *const SemanticGraph, occurrence: id) ?semantic_algebra.Stage {
        const node = self.get(occurrence) orelse return null;
        return node.stage;
    }

    /// Caller lives on the application node as scope — not a copied fact field.
    pub fn applicationCaller(self: *const SemanticGraph, occurrence: id) ?id {
        const node = self.get(occurrence) orelse return null;
        return node.scope;
    }

    /// Subject of a subject-first application. Null is absence, not argument
    /// zero. Producer is the unique `.projection` at
    /// `application_subject_projection` (`law.application.consumer`).
    /// Checked subject: unique projection at `application_subject_projection`.
    pub fn applicationSubject(self: *const SemanticGraph, occurrence: id) ?id {
        const entity = self.uniqueSubjectProjection(occurrence) orelse return null;
        const node = self.get(entity) orelse return null;
        if (node.descriptor == null) return null;
        return entity;
    }

    /// Result descriptor retained on one exact function entity.
    pub fn functionResultDescriptor(self: *const SemanticGraph, function: id) ?types.ResolvedType {
        const node = self.get(function) orelse return null;
        return node.result_descriptor;
    }

    /// Textual projection across all kinds. Ambiguity remains unresolved.
    pub fn findByName(self: *const SemanticGraph, name: []const u8) ?id {
        var match: ?id = null;
        for (self.nodes.items, 0..) |node, i| {
            if (node.name) |n| {
                if (!std.mem.eql(u8, n, name)) continue;
                if (match != null) return null;
                match = @intCast(i);
            }
        }
        return match;
    }

    /// Textual projection for diagnostics. Ambiguity remains unresolved.
    pub fn findByNameOfKind(self: *const SemanticGraph, name: []const u8, kind: NodeKind) ?id {
        return self.findUniqueByNameOfKind(name, kind);
    }

    pub fn usersOf(self: *const SemanticGraph, target: id, buf: *std.ArrayListUnmanaged(id)) !void {
        for (self.edges.items) |e| {
            if (e.to == target and e.kind == .binding) {
                try buf.append(self.alloc, e.from);
            }
        }
    }

    /// Register a shape algebra transform (`shape.lift`, `shape.seal`, …) on the graph.
    fn addShapeTransformApp(
        self: *SemanticGraph,
        parent: id,
        op: semantic_algebra.ShapeOp,
        input_knowledge: semantic_algebra.KnowledgeLevel,
        span: SpanRef,
        input_hash: u64,
        output_hash: u64,
    ) !id {
        const transform_name = semantic_algebra.shapeTransformId(op);
        std.debug.assert(transform_engine.isShapeTransform(transform_name));
        const node_id = try self.addChild(parent, .{
            .kind = .transform_app,
            .span = span,
            .name = transform_name,
            .knowledge = semantic_algebra.ShapeOp.resultingKnowledge(op, input_knowledge),
            .stage = .transform,
        });
        transform_engine.logProvenance(
            self.alloc,
            transform_name,
            .top_level_assign,
            input_hash,
            output_hash,
        );
        return node_id;
    }

    fn followupShapeOps(is_sealed: bool) []const semantic_algebra.ShapeOp {
        if (is_sealed) return &.{.seal};
        return &.{};
    }

    fn attachTableShapeTransforms(
        self: *SemanticGraph,
        parent: id,
        span: SpanRef,
        rt: types.ResolvedType,
        shape_id: ?u64,
    ) !void {
        const sid = shape_id orelse 0;
        const is_sealed = rt == .table_type and rt.table_type.is_sealed;
        const shape_knowledge = shapeKnowledge(is_sealed);
        _ = try self.addShapeTransformApp(
            parent,
            .lift,
            .observed,
            span,
            0,
            sid,
        );
        for (followupShapeOps(is_sealed)) |op| {
            _ = try self.addShapeTransformApp(
                parent,
                op,
                shape_knowledge,
                span,
                sid,
                sid,
            );
        }
    }

    /// Lift module-level function names from AST (Phase 1 minimal — no sema yet).
    pub fn liftModule(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        self.module_ast = mod;
        const mod_id = try self.addNode(.{
            .kind = .module,
            .span = .{ .file = file, .start = 0, .end = 0 },
            .name = file,
        });
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const func_id = try self.addChild(mod_id, .{
                .kind = .func,
                .span = .{
                    .file = file,
                    .start = fd.loc.line,
                    .end = fd.loc.col,
                },
                .name = fd.path[0],
                .result_descriptor = try types.resolve(fd.func.ret_type, null, self.alloc),
                .ast_ref = @ptrCast(fd),
            });
            for (fd.func.params) |param| {
                _ = try self.addChild(func_id, .{
                    .kind = .param,
                    .span = .{ .file = file, .start = 0, .end = 0 },
                    .name = param.name,
                });
            }
        }
        return mod_id;
    }

    /// Lift alias record shapes from AST (Phase 1 — storage class inferred from fields).
    pub fn liftAliasShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .alias_def) continue;
            const ad = &stmt.alias_def;
            if (ad.type_params != null) continue;
            var rt: types.ResolvedType = .any;
            if (ad.target) |tgt| {
                rt = try types.resolve(tgt, null, self.alloc);
            } else if (ad.fields.len > 0) {
                var fields = try self.alloc.alloc(types.FieldType, ad.fields.len);
                for (ad.fields, 0..) |field, i| {
                    fields[i] = .{
                        .name = field.name,
                        .typ = try types.resolve(field.typ, null, self.alloc),
                    };
                }
                rt = .{ .table_type = .{ .fields = fields } };
                rt.table_type.storage_class = types.inferStorageClass(fields, false, .dynamic);
            }
            types.applyTableShapeAttrs(&rt, ad.attributes);
            const is_sealed = rt == .table_type and rt.table_type.is_sealed;
            const knowledge = shapeKnowledge(is_sealed);
            const shape_id = types.tableShapeIdentityHash(rt);
            const alias_span = SpanRef{
                .file = file,
                .start = ad.loc.line,
                .end = ad.loc.col,
            };
            // The `DescriptorExprBuilder` tree that used to be built here fed
            // exactly one consumer — `descriptorStructuralHash` into the
            // deleted `Node.descriptor_hash` — so every alias in every module
            // built and freed a descriptor-expression tree to produce a number
            // nothing read. `semantic_algebra`'s builder is now reachable only
            // from its own tests; that is a separate P0 row, not this one.
            const state = inferDescriptorState(is_sealed);
            const shape_id_node = try self.addChild(parent, .{
                .kind = .table_shape,
                .span = alias_span,
                .name = ad.name,
                .shape_id = shape_id,
                .knowledge = knowledge,
                .stage = .sema,
                .descriptor_state = state,
                .ast_ref = @ptrCast(ad),
            });
            try self.publishDescriptorRefEdges(shape_id_node, rt);
            try self.publishTableShapeMembers(shape_id_node, alias_span, rt);
            try self.attachTableShapeTransforms(parent, alias_span, rt, shape_id orelse 0);
        }
    }

    /// Lift enum descriptor shapes from AST (Phase 2 — unified descriptor spine).
    pub fn liftEnumShapes(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .enum_def) continue;
            const ed = &stmt.enum_def;
            if (ed.type_params != null) continue;
            const rt = types.enumShapeFromAst(ed, self.alloc) catch continue;
            const shape_id = types.enumShapeIdentityHash(rt);
            const enum_span = SpanRef{
                .file = file,
                .start = ed.loc.line,
                .end = ed.loc.col,
            };
            const enum_id = try self.addChild(parent, .{
                .kind = .enum_shape,
                .span = enum_span,
                .name = ed.name,
                .shape_id = shape_id,
                .knowledge = .stable,
                .stage = .sema,
                .ast_ref = @ptrCast(ed),
            });
            try self.publishEnumShapeMembers(enum_id, enum_span, ed);
        }
    }

    fn liftTableShapeFromTypeExpr(
        self: *SemanticGraph,
        file: []const u8,
        func_id: id,
        binding_name: []const u8,
        te: ast.TypeExpr,
        loc: ast.Loc,
        attributes: []const ast.Attribute,
        lname: *const ast.LocalName,
    ) !void {
        var rt: types.ResolvedType = .any;
        var inline_record = false;
        switch (te) {
            .record => {
                inline_record = true;
                rt = types.resolve(te, null, self.alloc) catch return;
            },
            .named => |alias| {
                const local_id = try self.addChild(func_id, .{
                    .kind = .local,
                    .span = .{ .file = file, .start = loc.line, .end = loc.col },
                    .name = binding_name,
                    .ast_ref = @ptrCast(@constCast(lname)),
                });
                if (self.resolveInHome(func_id, alias, .table_shape)) |shape_id| {
                    try self.addEdge(.{ .from = local_id, .to = shape_id, .kind = .descriptor });
                }
                return;
            },
            else => return,
        }
        if (rt != .table_type) return;
        types.applyTableShapeAttrs(&rt, attributes);
        const is_sealed = rt.table_type.is_sealed;
        const sid = types.tableShapeIdentityHash(rt);
        const shape_node_id = try self.addChild(func_id, .{
            .kind = .table_shape,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .shape_id = sid,
            .knowledge = shapeKnowledge(is_sealed),
            .stage = .sema,
            .ast_ref = if (inline_record) @ptrCast(@constCast(lname)) else null,
        });
        try self.publishDescriptorRefEdges(shape_node_id, rt);
        try self.publishTableShapeMembers(shape_node_id, .{
            .file = file,
            .start = loc.line,
            .end = loc.col,
        }, rt);
        try self.attachTableShapeTransforms(func_id, .{
            .file = file,
            .start = loc.line,
            .end = loc.col,
        }, rt, sid);
        const local_id = try self.addChild(func_id, .{
            .kind = .local,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .name = binding_name,
            .ast_ref = @ptrCast(@constCast(lname)),
        });
        try self.addEdge(.{ .from = local_id, .to = shape_node_id, .kind = .descriptor });
    }

    fn liftBindingsInStmts(
        self: *SemanticGraph,
        file: []const u8,
        func_id: id,
        func_name: []const u8,
        stmts: []ast.Stmt,
    ) !void {
        for (stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.names) |*lname| {
                        try self.liftTableShapeFromTypeExpr(
                            file,
                            func_id,
                            lname.ident,
                            lname.typ,
                            lname.loc,
                            lname.attributes,
                            lname,
                        );
                    }
                },
                .do_block => |*d| try self.liftBindingsInStmts(file, func_id, func_name, d.body.stmts),
                .while_loop => |*w| try self.liftBindingsInStmts(file, func_id, func_name, w.body.stmts),
                .repeat_loop => |*r| try self.liftBindingsInStmts(file, func_id, func_name, r.body.stmts),
                .if_stmt => |*i| {
                    try self.liftBindingsInStmts(file, func_id, func_name, i.then.stmts);
                    for (i.elseifs) |*ei| try self.liftBindingsInStmts(file, func_id, func_name, ei.body.stmts);
                    if (i.else_body) |*eb| try self.liftBindingsInStmts(file, func_id, func_name, eb.stmts);
                },
                .num_for => |*nf| try self.liftBindingsInStmts(file, func_id, func_name, nf.body.stmts),
                .gen_for => |*g| try self.liftBindingsInStmts(file, func_id, func_name, g.body.stmts),
                .func_decl => |*fd| {
                    if (self.findFuncDecl(fd)) |nested_id| {
                        try self.liftBindingsInStmts(file, nested_id, fd.path[0], fd.func.body.stmts);
                    }
                },
                .try_stmt => |*t| {
                    try self.liftBindingsInStmts(file, func_id, func_name, t.body.stmts);
                    for (t.catches) |*cc| try self.liftBindingsInStmts(file, func_id, func_name, cc.body.stmts);
                },
                .defer_stmt => |*d| try self.liftBindingsInStmts(file, func_id, func_name, d.body.stmts),
                else => {},
            }
        }
    }

    /// Lift typed bindings inside functions (inline records + alias descriptor edges).
    pub fn liftFunctionBindings(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const func_id = self.findFuncDecl(fd) orelse return error.MissingSemanticDeclaration;
            try self.liftBindingsInStmts(file, func_id, fd.path[0], fd.func.body.stmts);
        }
    }

    /// §18's census, lifted ONCE. Idempotent: a second call is a no-op, so a
    /// caller that lifts a graph twice does not get two censuses and two sets
    /// of place identities.
    pub fn liftPlaces(self: *SemanticGraph, mod: *const ast.Module) !void {
        try self.requireOpen();
        if (self.places != null) return;
        self.places = try place.analyzeModule(self.alloc, mod);
    }

    /// The place a module-scope name denotes, or null when this graph was never
    /// asked for places. Consumers must treat null as "unknown", never as "no
    /// place" — `place.Tri`'s rule, applied to the lookup itself.
    pub fn placeNamed(self: *const SemanticGraph, name: []const u8) ?*const place.Place {
        const census = if (self.places) |*c| c else return null;
        return census.find(name);
    }

    /// How many places this graph carries. O(1), so a hot consumer can decline
    /// before paying for a lookup.
    pub fn placeCount(self: *const SemanticGraph) usize {
        const census = if (self.places) |*c| c else return 0;
        return census.count();
    }

    /// The place and region censuses of one relation body. Idempotent: a second
    /// lift is a no-op, so a graph lifted twice does not get two censuses.
    pub fn liftBodies(self: *SemanticGraph, mod: *const ast.Module) !void {
        try self.requireOpen();
        if (self.bodies.items.len > 0) return;
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const relation = self.findFuncDecl(fd) orelse continue;
            var places = try place.analyzeFunction(self.alloc, &fd.func);
            errdefer places.deinit();
            var regions = try region.analyzeFunction(self.alloc, &fd.func, &places);
            errdefer regions.deinit();
            try self.bodies.append(self.alloc, .{
                .relation = relation,
                .places = places,
                .regions = regions,
            });
        }
    }

    fn ownedDescriptor(self: *SemanticGraph, descriptor: types.ResolvedType) !*types.ResolvedType {
        const stored = try self.alloc.create(types.ResolvedType);
        errdefer self.alloc.destroy(stored);
        stored.* = descriptor;
        try self.owned_descriptors.append(self.alloc, stored);
        return stored;
    }

    /// Exact uniform positional descriptor admitted by this slice. A mixed or
    /// keyed table is declined; it remains a table, but this bounded producer
    /// cannot truthfully publish one element descriptor for it.
    fn aggregateDescriptor(self: *SemanticGraph, expr: *const ast.Expr) !?types.ResolvedType {
        if (expr.* != .table or expr.table.fields.len == 0) return null;
        var element: ?types.ResolvedType = null;
        for (expr.table.fields) |field| {
            if (field != .positional) return null;
            const descriptor: types.ResolvedType = switch (field.positional.*) {
                .int_lit => .i64,
                .table => (try self.aggregateDescriptor(field.positional)) orelse return null,
                else => return null,
            };
            if (element) |known| {
                if (!known.eql(descriptor)) return null;
            } else {
                element = descriptor;
            }
        }
        const elem = try self.ownedDescriptor(element orelse return null);
        return .{ .array = .{ .elem = elem, .size = expr.table.fields.len } };
    }

    fn placeForAggregate(self: *const SemanticGraph, owner: id, name: []const u8) place.Site {
        const owner_node = self.get(owner) orelse return .unknown;
        const found = if (owner_node.scope == null)
            self.placeNamed(name)
        else if (self.bodyOf(owner)) |body|
            body.places.find(name)
        else
            null;
        return if (found) |p| .{ .one = p.id } else .unknown;
    }

    fn rememberAggregateOrigin(self: *SemanticGraph, expr: *const ast.Expr, aggregate_id: id) !void {
        const raw: *const anyopaque = @ptrCast(expr);
        const slot = try self.aggregate_origins.getOrPut(self.alloc, @intFromPtr(raw));
        if (slot.found_existing and slot.value_ptr.* != aggregate_id) return error.DuplicateAggregateOrigin;
        slot.value_ptr.* = aggregate_id;
    }

    fn liftAggregateLiteral(
        self: *SemanticGraph,
        parent: id,
        owner: id,
        name: ?[]const u8,
        expr: *const ast.Expr,
        site: place.Site,
    ) !?id {
        const descriptor = (try self.aggregateDescriptor(expr)) orelse return null;
        const loc = expr.loc();
        const aggregate_id = try self.addChild(parent, .{
            .kind = .value,
            .span = .{ .file = self.module_path orelse "", .start = loc.line, .end = loc.col },
            .name = name,
            .descriptor = descriptor,
            .knowledge = .at_comptime,
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.rememberAggregateOrigin(expr, aggregate_id);

        const members = try self.alloc.alloc(PackMember, expr.table.fields.len);
        defer self.alloc.free(members);
        for (expr.table.fields, 0..) |field, i| {
            const value = field.positional;
            const child: id = switch (value.*) {
                .int_lit => |literal| blk: {
                    const child_id = try self.addChild(aggregate_id, .{
                        .kind = .value,
                        .span = .{ .file = self.module_path orelse "", .start = value.loc().line, .end = value.loc().col },
                        .descriptor = .i64,
                        .knowledge = .at_comptime,
                        .stage = .sema,
                        .ast_ref = @ptrCast(@constCast(value)),
                    });
                    try self.publishExactI64(child_id, literal.val);
                    break :blk child_id;
                },
                .table => (try self.liftAggregateLiteral(aggregate_id, owner, null, value, site)) orelse
                    return error.InvalidAggregateFact,
                else => return error.InvalidAggregateFact,
            };
            members[i] = .{ .value = child, .demand = .unknown };
        }
        const members_pack = try self.addChild(aggregate_id, .{
            .kind = .value,
            .span = self.get(aggregate_id).?.span,
            .knowledge = .stable,
            .stage = .sema,
        });
        try self.publishPack(
            members_pack,
            members,
            .{ .fixed = @intCast(members.len) },
            .{ .one = aggregate_id },
        );
        try self.publishAggregate(.{
            .aggregate = aggregate_id,
            .members_pack = members_pack,
            .owner = owner,
            .place = site,
            .contents_known = .yes,
        });
        return aggregate_id;
    }

    fn liftAggregateBinding(
        self: *SemanticGraph,
        owner: id,
        name: []const u8,
        value: *const ast.Expr,
    ) !void {
        if (value.* != .table) return;
        _ = try self.liftAggregateLiteral(owner, owner, name, value, self.placeForAggregate(owner, name));
    }

    fn liftAggregateBindingsInBlock(self: *SemanticGraph, owner: id, block: *const ast.Block) anyerror!void {
        for (block.stmts) |*stmt| switch (stmt.*) {
            .local_decl => |declaration| for (declaration.names, 0..) |name, i| {
                if (i < declaration.inits.len) try self.liftAggregateBinding(owner, name.ident, declaration.inits[i]);
            },
            .global_decl => |declaration| for (declaration.names, 0..) |name, i| {
                if (i < declaration.inits.len) try self.liftAggregateBinding(owner, name.ident, declaration.inits[i]);
            },
            .assign => |assignment| for (assignment.targets, 0..) |target, i| {
                if (target.* == .name and i < assignment.values.len)
                    try self.liftAggregateBinding(owner, target.name.ident, assignment.values[i]);
            },
            .do_block => |nested| try self.liftAggregateBindingsInBlock(owner, &nested.body),
            .while_loop => |loop| try self.liftAggregateBindingsInBlock(owner, &loop.body),
            .repeat_loop => |loop| try self.liftAggregateBindingsInBlock(owner, &loop.body),
            .num_for => |loop| try self.liftAggregateBindingsInBlock(owner, &loop.body),
            .gen_for => |loop| try self.liftAggregateBindingsInBlock(owner, &loop.body),
            .if_stmt => |conditional| {
                try self.liftAggregateBindingsInBlock(owner, &conditional.then);
                for (conditional.elseifs) |*branch| try self.liftAggregateBindingsInBlock(owner, &branch.body);
                if (conditional.else_body) |*branch| try self.liftAggregateBindingsInBlock(owner, branch);
            },
            .try_stmt => |attempt| {
                try self.liftAggregateBindingsInBlock(owner, &attempt.body);
                for (attempt.catches) |*clause| try self.liftAggregateBindingsInBlock(owner, &clause.body);
            },
            .defer_stmt => |deferred| try self.liftAggregateBindingsInBlock(owner, &deferred.body),
            else => {},
        };
    }

    fn liftAggregates(self: *SemanticGraph, mod: *const ast.Module, module: id) !void {
        for (mod.body.stmts) |*stmt| switch (stmt.*) {
            .func_decl => |*function| {
                const owner = self.findFuncDecl(function) orelse continue;
                try self.liftAggregateBindingsInBlock(owner, &function.func.body);
            },
            .local_decl => |declaration| for (declaration.names, 0..) |name, i| {
                if (i < declaration.inits.len) try self.liftAggregateBinding(module, name.ident, declaration.inits[i]);
            },
            .global_decl => |declaration| for (declaration.names, 0..) |name, i| {
                if (i < declaration.inits.len) try self.liftAggregateBinding(module, name.ident, declaration.inits[i]);
            },
            .assign => |assignment| for (assignment.targets, 0..) |target, i| {
                if (target.* == .name and i < assignment.values.len)
                    try self.liftAggregateBinding(module, target.name.ident, assignment.values[i]);
            },
            else => {},
        };
    }

    /// The censuses of one relation, or null when this graph was never asked.
    /// Null must be read as "not asked", never as "no places and no regions" —
    /// `place.Tri`'s rule applied to the lookup itself.
    pub fn bodyOf(self: *const SemanticGraph, relation: id) ?*const Body {
        for (self.bodies.items) |*body| {
            if (body.relation == relation) return body;
        }
        return null;
    }

    /// The world an application draws. `.unknown` when nothing decided — which
    /// is the answer for every occurrence this graph never examined, and is not
    /// a claim that the application draws nothing.
    pub fn applicationWorld(self: *const SemanticGraph, occurrence: id) Card {
        for (self.draws.items) |draw| {
            if (draw.application == occurrence) return draw.world;
        }
        return .unknown;
    }

    /// The members of one world this module reaches.
    pub fn worldMembers(self: *const SemanticGraph, fact: WorldFact) []const id {
        const end = std.math.add(u32, fact.members.start, fact.members.len) catch return &.{};
        if (end > self.world_members.items.len) return &.{};
        return self.world_members.items[fact.members.start..end];
    }

    /// The place an application value reads, three-valued.
    pub fn valueOrigin(self: *const SemanticGraph, value: id) place.Site {
        for (self.origins.items) |origin| {
            if (origin.value == value) return .{ .one = origin.place };
        }
        return .unknown;
    }

    /// Lift module-level symbols, alias table shapes, and enum shapes.
    pub fn liftModuleFull(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModule(mod, file);
        try self.liftAliasShapes(mod, file, mod_id);
        try self.liftEnumShapes(mod, file, mod_id);
        try self.attachMemberDescriptorShapes(mod_id);
        try self.attachCallableResultShapes(mod_id);
        try self.liftFunctionBindings(mod, file);
        try self.liftPlaces(mod);
        try self.liftBodies(mod);
        try self.liftAggregates(mod, mod_id);
        return mod_id;
    }

    /// Lift call sites from function bodies (Phase 1 — call-shape specialization).
    /// Walks all function statements and extracts call/method_call expressions,
    /// recording their CallShape for specialization analysis.
    pub fn liftCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8, parent: id) !void {
        for (mod.body.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    const func_id = self.findFuncDecl(fd) orelse continue;
                    try self.liftCallsFromBlock(&fd.func.body, file, func_id);
                },
                .expr_stmt => |es| {
                    const rc: types.ReturnConsumption = if (es.expr.* == .call or es.expr.* == .method_call)
                        .discard
                    else
                        .discard;
                    try self.liftExprsFromExpr(es.expr, file, parent, rc);
                },
                .call_stmt => |cs| {
                    try self.liftExprsFromExpr(cs.expr, file, parent, .discard);
                },
                .local_decl => |ld| {
                    const rc = types.returnConsumptionForTargets(ld.names.len);
                    for (ld.inits) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                .global_decl => |gd| {
                    const rc = types.returnConsumptionForTargets(gd.names.len);
                    for (gd.inits) |v| try self.liftExprsFromExpr(v, file, parent, rc);
                },
                .assign => |asgn| {
                    for (asgn.targets) |target| {
                        try self.liftExprsFromExpr(target, file, parent, .single);
                    }
                    const rc = types.returnConsumptionForTargets(asgn.targets.len);
                    for (asgn.values) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                else => {},
            }
        }
        if (mod.body.tail_expr) |tail| {
            const rc: types.ReturnConsumption = switch (tail.*) {
                .call, .method_call => .discard,
                else => .single,
            };
            try self.liftExprsFromExpr(tail, file, parent, rc);
        }
    }

    fn liftCallsFromBlock(self: *SemanticGraph, block: *const ast.Block, file: []const u8, parent: id) anyerror!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .expr_stmt => |es| {
                    const rc: types.ReturnConsumption = if (es.expr.* == .call or es.expr.* == .method_call)
                        .discard
                    else
                        .discard;
                    try self.liftExprsFromExpr(es.expr, file, parent, rc);
                },
                .call_stmt => |cs| {
                    try self.liftExprsFromExpr(cs.expr, file, parent, .discard);
                },
                .local_decl => |ld| {
                    const rc = types.returnConsumptionForTargets(ld.names.len);
                    for (ld.inits) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                .assign => |asgn| {
                    for (asgn.targets) |target| {
                        try self.liftExprsFromExpr(target, file, parent, .single);
                    }
                    const rc = types.returnConsumptionForTargets(asgn.targets.len);
                    for (asgn.values) |v| {
                        try self.liftExprsFromExpr(v, file, parent, rc);
                    }
                },
                .ret => |r| {
                    const rc: types.ReturnConsumption = if (r.vals.len <= 1) .single else .multi;
                    for (r.vals) |v| try self.liftExprsFromExpr(v, file, parent, rc);
                },
                .if_stmt => |is| {
                    if (is.binding) |bound| {
                        try self.liftExprsFromExpr(bound.expr, file, parent, .single);
                    }
                    try self.liftExprsFromExpr(is.cond, file, parent, .single);
                    try self.liftCallsFromBlock(&is.then, file, parent);
                    for (is.elseifs) |*elif| {
                        try self.liftExprsFromExpr(elif.cond, file, parent, .single);
                        try self.liftCallsFromBlock(&elif.body, file, parent);
                    }
                    if (is.else_body) |*eb| {
                        try self.liftCallsFromBlock(eb, file, parent);
                    }
                },
                .while_loop => |wl| {
                    try self.liftExprsFromExpr(wl.cond, file, parent, .single);
                    try self.liftCallsFromBlock(&wl.body, file, parent);
                },
                .repeat_loop => |rl| {
                    try self.liftCallsFromBlock(&rl.body, file, parent);
                    try self.liftExprsFromExpr(rl.cond, file, parent, .single);
                },
                .num_for => |nf| {
                    try self.liftExprsFromExpr(nf.start, file, parent, .single);
                    try self.liftExprsFromExpr(nf.stop, file, parent, .single);
                    if (nf.step) |step| try self.liftExprsFromExpr(step, file, parent, .single);
                    try self.liftCallsFromBlock(&nf.body, file, parent);
                },
                .gen_for => |gf| {
                    for (gf.iters) |iter| try self.liftExprsFromExpr(iter, file, parent, .single);
                    try self.liftCallsFromBlock(&gf.body, file, parent);
                },
                .do_block => |db| {
                    try self.liftCallsFromBlock(&db.body, file, parent);
                },
                .func_decl => |*fd| {
                    try self.liftCallsFromBlock(&fd.func.body, file, parent);
                },
                .const_decl => |cd| {
                    try self.liftExprsFromExpr(cd.val, file, parent, .single);
                },
                .global_decl => |gd| {
                    const rc = types.returnConsumptionForTargets(gd.names.len);
                    for (gd.inits) |v| try self.liftExprsFromExpr(v, file, parent, rc);
                },
                .match_stmt => |ms| {
                    try self.liftExprsFromExpr(ms.scrutinee, file, parent, .single);
                    for (ms.arms) |*arm| {
                        if (arm.guard) |guard| {
                            try self.liftExprsFromExpr(guard, file, parent, .single);
                        }
                        try self.liftCallsFromBlock(&arm.body, file, parent);
                    }
                },
                .try_stmt => |ts| {
                    try self.liftCallsFromBlock(&ts.body, file, parent);
                    for (ts.catches) |*cc| try self.liftCallsFromBlock(&cc.body, file, parent);
                    for (ts.defers) |*d| try self.liftCallsFromBlock(&d.body, file, parent);
                },
                .defer_stmt => |d| {
                    try self.liftCallsFromBlock(&d.body, file, parent);
                },
                else => {},
            }
        }
        // Also check tail expression (implicit return in Duo)
        if (block.tail_expr) |tail| {
            try self.liftExprsFromExpr(tail, file, parent, .single);
        }
    }

    fn liftExprsFromExpr(
        self: *SemanticGraph,
        expr: *const Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) anyerror!void {
        switch (expr.*) {
            .binop => |b| {
                if (b.op == .pipeline) {
                    const loc = expr.loc();
                    const relation = semantic_algebra.IterationRelation.map;
                    _ = try self.addChild(parent, .{
                        .kind = .relation,
                        .span = .{
                            .file = file,
                            .start = loc.line,
                            .end = loc.col,
                        },
                        .knowledge = .observed,
                        .stage = .sema,
                        .ast_ref = @ptrCast(@constCast(expr)),
                    });
                    const transform_name = semantic_algebra.iterationTransformId(relation);
                    if (transform_engine.isRegisteredTransform(transform_name)) {
                        _ = try self.addChild(parent, .{
                            .kind = .transform_app,
                            .span = .{ .file = file, .start = loc.line, .end = loc.col },
                            .name = transform_name,
                            .knowledge = .observed,
                            .stage = .transform,
                        });
                    }
                }
                try self.liftExprsFromExpr(b.lhs, file, parent, .single);
                try self.liftExprsFromExpr(b.rhs, file, parent, .single);
            },
            .call => |c| {
                try self.liftCallFromExpr(expr, file, parent, consumption);
                try self.liftExprsFromExpr(c.func, file, parent, .single);
                for (c.args) |arg| try self.liftExprsFromExpr(arg, file, parent, .single);
            },
            .method_call => |mc| {
                try self.liftCallFromExpr(expr, file, parent, consumption);
                try self.liftExprsFromExpr(mc.obj, file, parent, .single);
                for (mc.args) |arg| try self.liftExprsFromExpr(arg, file, parent, .single);
            },
            .unop => |u| try self.liftExprsFromExpr(u.operand, file, parent, .single),
            .index => |ix| {
                try self.liftExprsFromExpr(ix.obj, file, parent, .single);
                try self.liftExprsFromExpr(ix.key, file, parent, .single);
                try self.liftAggregateAccess(expr, file, parent, consumption);
            },
            .field => |f| try self.liftExprsFromExpr(f.obj, file, parent, .single),
            .table => |t| {
                for (t.fields) |field| switch (field) {
                    .indexed => |idx| {
                        try self.liftExprsFromExpr(idx.key, file, parent, .single);
                        try self.liftExprsFromExpr(idx.val, file, parent, .single);
                    },
                    .named => |nmd| try self.liftExprsFromExpr(nmd.val, file, parent, .single),
                    .positional => |val| try self.liftExprsFromExpr(val, file, parent, .single),
                    .spread => |src| try self.liftExprsFromExpr(src, file, parent, .single),
                    .semantic => |sem| try self.liftExprsFromExpr(sem.val, file, parent, .single),
                };
            },
            .if_expr => |ie| {
                try self.liftExprsFromExpr(ie.cond, file, parent, .single);
                try self.liftExprsFromExpr(ie.then_expr, file, parent, consumption);
                try self.liftExprsFromExpr(ie.else_expr, file, parent, consumption);
            },
            .try_expr => |t| try self.liftExprsFromExpr(t.operand, file, parent, .single),
            .unwrap_expr => |u| try self.liftExprsFromExpr(u.operand, file, parent, .single),
            .await_expr => |a| try self.liftExprsFromExpr(a.operand, file, parent, .single),
            .contains_expr => |c| {
                try self.liftExprsFromExpr(c.lhs, file, parent, .single);
                try self.liftExprsFromExpr(c.rhs, file, parent, .single);
            },
            .quote => |q| try self.liftExprsFromExpr(q.expr, file, parent, .single),
            .unquote => |q| try self.liftExprsFromExpr(q.expr, file, parent, .single),
            .sequence => |s| {
                for (s.exprs) |item| try self.liftExprsFromExpr(item, file, parent, .single);
            },
            .range => |r| {
                try self.liftExprsFromExpr(r.start, file, parent, .single);
                try self.liftExprsFromExpr(r.end, file, parent, .single);
                if (r.step) |step| try self.liftExprsFromExpr(step, file, parent, .single);
            },
            .list_comp => |lc| {
                try self.liftExprsFromExpr(lc.value, file, parent, .single);
                try self.liftExprsFromExpr(lc.iter, file, parent, .single);
                if (lc.filter) |filter| try self.liftExprsFromExpr(filter, file, parent, .single);
            },
            .macro_call => |m| {
                for (m.args) |arg| try self.liftExprsFromExpr(arg, file, parent, .single);
            },
            .match_expr => |m| {
                try self.liftExprsFromExpr(m.scrutinee, file, parent, .single);
                for (m.arms) |*arm| {
                    if (arm.guard) |guard| {
                        try self.liftExprsFromExpr(guard, file, parent, .single);
                    }
                    try self.liftCallsFromBlock(&arm.body, file, parent);
                }
            },
            else => {},
        }
    }

    fn liftCallFromExpr(
        self: *SemanticGraph,
        expr: *const Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) !void {
        const base = types.inferCallShape(expr) orelse return;
        const shape = types.callShapeWithConsumption(base, consumption);
        const call_loc = expr.loc();
        const occurrence = try self.addChild(parent, .{
            .kind = .call,
            .span = .{
                .file = file,
                .start = call_loc.line,
                .end = call_loc.col,
            },
            .call_shape = shape,
            .demand = consumption,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.markApplicationCandidate(occurrence);
    }

    fn aggregateNamedInScope(self: *const SemanticGraph, start: id, name: []const u8) ?id {
        var scope: ?id = start;
        while (scope) |current| {
            var found: ?id = null;
            for (self.aggregate_facts.items) |fact| {
                if (fact.owner != current) continue;
                const node = self.get(fact.aggregate) orelse continue;
                if (node.scope != current) continue;
                const candidate = node.name orelse continue;
                if (!std.mem.eql(u8, candidate, name)) continue;
                if (found != null and found.? != fact.aggregate) return null;
                found = fact.aggregate;
            }
            if (found != null) return found;
            scope = (self.get(current) orelse return null).scope;
        }
        return null;
    }

    fn aggregateForExpr(self: *const SemanticGraph, expr: *const ast.Expr, scope: id) ?id {
        return switch (expr.*) {
            .name => |name| self.aggregateNamedInScope(scope, name.ident),
            .table, .index => self.aggregate_origins.get(@intFromPtr(expr)),
            else => null,
        };
    }

    fn aggregateAccessRelation(self: *SemanticGraph, start: id) !id {
        if (self.aggregate_access_relation) |relation| return relation;
        var module = start;
        while (self.get(module).?.scope) |parent| module = parent;
        const relation = try self.addChild(module, .{
            .kind = .relation,
            .span = self.get(module).?.span,
            .result_descriptor = .any,
            .knowledge = .stable,
            .stage = .sema,
        });
        self.aggregate_access_relation = relation;
        return relation;
    }

    fn publishAggregateSkeleton(
        self: *SemanticGraph,
        aggregate_id: id,
        owner: id,
        descriptor: types.ResolvedType,
        site: place.Site,
    ) !void {
        if (descriptor != .array) return error.InvalidAggregateFact;
        const count = descriptor.array.size orelse return error.InvalidAggregateFact;
        const members = try self.alloc.alloc(PackMember, count);
        defer self.alloc.free(members);
        for (members, 0..) |*member, i| {
            _ = i;
            const child = try self.addChild(aggregate_id, .{
                .kind = .value,
                .span = self.get(aggregate_id).?.span,
                .descriptor = descriptor.array.elem.*,
                .knowledge = .stable,
                .stage = .sema,
            });
            if (descriptor.array.elem.* == .array) {
                try self.publishAggregateSkeleton(child, owner, descriptor.array.elem.*, site);
            }
            member.* = .{ .value = child, .demand = .unknown };
        }
        const pack_id = try self.addChild(aggregate_id, .{
            .kind = .value,
            .span = self.get(aggregate_id).?.span,
            .knowledge = .stable,
            .stage = .sema,
        });
        try self.publishPack(pack_id, members, .{ .fixed = @intCast(count) }, .{ .one = aggregate_id });
        try self.publishAggregate(.{
            .aggregate = aggregate_id,
            .members_pack = pack_id,
            .owner = owner,
            .place = site,
            .contents_known = .unknown,
        });
    }

    fn publishAggregateProjection(
        self: *SemanticGraph,
        projected: id,
        selected: id,
        owner: id,
        site: place.Site,
    ) !void {
        const selected_fact = self.aggregate(selected) orelse return error.InvalidAggregateFact;
        const selected_members = self.aggregateMembers(selected) orelse return error.InvalidAggregateFact;
        const members = try self.alloc.alloc(PackMember, selected_members.len);
        defer self.alloc.free(members);
        for (selected_members, 0..) |member, i| {
            members[i] = .{ .value = member, .demand = .unknown };
        }
        const pack_id = try self.addChild(projected, .{
            .kind = .value,
            .span = self.get(projected).?.span,
            .knowledge = .stable,
            .stage = .sema,
        });
        try self.publishPack(pack_id, members, .{ .fixed = @intCast(members.len) }, .{ .one = projected });
        try self.publishAggregate(.{
            .aggregate = projected,
            .members_pack = pack_id,
            .owner = owner,
            .place = site,
            .contents_known = selected_fact.contents_known,
        });
    }

    fn liftAggregateAccess(
        self: *SemanticGraph,
        expr: *const ast.Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) !void {
        if (expr.* != .index) return;
        const subject = self.aggregateForExpr(expr.index.obj, parent) orelse return;
        const subject_node = self.get(subject) orelse return error.InvalidAggregateFact;
        const descriptor = subject_node.descriptor orelse return error.InvalidAggregateFact;
        if (descriptor != .array) return error.InvalidAggregateFact;
        const result_descriptor = descriptor.array.elem.*;
        // This bounded producer owns hierarchical aggregate projection. A flat
        // scalar table read remains on the existing place realization until
        // that family is migrated with its mutable cases; publishing an
        // application that no graph consumer can yet realize would turn new
        // semantic knowledge into a capability regression.
        if (result_descriptor != .array and self.aggregateProducer(subject) == null) return;
        const aggregate_fact = self.aggregate(subject) orelse return error.InvalidAggregateFact;
        const loc = expr.loc();
        const occurrence = try self.addChild(parent, .{
            .kind = .call,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .demand = consumption,
            .descriptor = result_descriptor,
            .knowledge = .stable,
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.markApplicationCandidate(occurrence);

        const key = try self.addApplicationValue(occurrence, expr.index.key, file, .i64);
        try self.noteOrigin(key, expr.index.key, parent);
        var selected: ?id = null;
        if (self.exactI64(key)) |constant_key| {
            const members = self.aggregateMembers(subject) orelse return error.InvalidAggregateFact;
            if (constant_key >= 1 and constant_key <= @as(i64, @intCast(members.len))) {
                selected = members[@intCast(constant_key - 1)];
            }
        } else if (expr.index.key.* == .int_lit) {
            try self.publishExactI64(key, expr.index.key.int_lit.val);
            const members = self.aggregateMembers(subject) orelse return error.InvalidAggregateFact;
            const constant_key = expr.index.key.int_lit.val;
            if (constant_key >= 1 and constant_key <= @as(i64, @intCast(members.len))) {
                selected = members[@intCast(constant_key - 1)];
            }
        }
        const result = try self.addApplicationValue(occurrence, expr, file, result_descriptor);
        if (selected) |exact| {
            if (result_descriptor == .array) {
                try self.publishAggregateProjection(
                    result,
                    exact,
                    aggregate_fact.owner,
                    aggregate_fact.place,
                );
            } else if (self.exactI64(exact)) |content| {
                try self.publishExactI64(result, content);
            }
        } else if (result_descriptor == .array) {
            try self.publishAggregateSkeleton(
                result,
                aggregate_fact.owner,
                result_descriptor,
                aggregate_fact.place,
            );
        }
        if (result_descriptor == .array) try self.rememberAggregateOrigin(expr, result);
        const relation = try self.aggregateAccessRelation(parent);
        try self.publishApplication(
            occurrence,
            subject,
            relation,
            relation,
            subject,
            &.{key},
            &.{result},
        );
    }

    /// Lift module fully including call sites (Phase 1 complete lift).
    pub fn liftModuleWithCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModuleFull(mod, file);
        try self.liftCalls(mod, file, mod_id);
        return mod_id;
    }

    fn addApplicationValue(
        self: *SemanticGraph,
        occurrence: id,
        expr: *const Expr,
        file: []const u8,
        descriptor: types.ResolvedType,
    ) !id {
        const loc = expr.loc();
        const value = try self.addChild(occurrence, .{
            .kind = .value,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .descriptor = descriptor,
            .knowledge = semantic_algebra.knowledgeOfType(descriptor),
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.publishNameBinding(value, expr, occurrence);
        return value;
    }

    /// Lift-time only: a name operand projects onto an exact local/param id.
    fn publishNameBinding(
        self: *SemanticGraph,
        from: id,
        expr: *const Expr,
        occurrence: id,
    ) !void {
        const ident = switch (expr.*) {
            .name => |n| n.ident,
            else => return,
        };
        const start = self.get(occurrence).?.scope orelse return;
        const binding = self.resolveBindingInScope(start, ident) orelse return;
        try self.addEdge(.{ .from = from, .to = binding, .kind = .binding });
    }

    /// Source-resolution boundary: resolve a binding name to an exact id by
    /// walking the lexical scope chain recorded on the graph. Downstream
    /// consumers must use published capture and binding edges — never repeat this walk.
    fn resolveBindingInScope(self: *const SemanticGraph, start_scope: id, name: []const u8) ?id {
        var scope: ?id = start_scope;
        while (scope) |s| {
            for (self.edges.items) |edge| {
                if (edge.from != s or edge.kind != .contains) continue;
                const node = self.get(edge.to) orelse continue;
                if (node.kind != .local and node.kind != .param) continue;
                if (node.name) |n| {
                    if (std.mem.eql(u8, n, name)) return edge.to;
                }
            }
            scope = self.get(s).?.scope;
        }
        return null;
    }

    const CaptureLiftError = error{
        OutOfMemory,
        DuplicateSemanticDeclaration,
        DerivedContainsIndex,
        GraphIncarnationFrozen,
    };

    fn liftCaptureEdgesFromBlock(self: *SemanticGraph, block: *const ast.Block) CaptureLiftError!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| try self.liftCaptureEdgesFromFunc(fd),
                .if_stmt => |*i| {
                    try self.liftCaptureEdgesFromBlock(&i.then);
                    for (i.elseifs) |*ei| try self.liftCaptureEdgesFromBlock(&ei.body);
                    if (i.else_body) |*eb| try self.liftCaptureEdgesFromBlock(eb);
                },
                .while_loop => |*w| try self.liftCaptureEdgesFromBlock(&w.body),
                .repeat_loop => |*r| try self.liftCaptureEdgesFromBlock(&r.body),
                .do_block => |*d| try self.liftCaptureEdgesFromBlock(&d.body),
                .num_for => |*nf| try self.liftCaptureEdgesFromBlock(&nf.body),
                .gen_for => |*g| try self.liftCaptureEdgesFromBlock(&g.body),
                .try_stmt => |*t| {
                    try self.liftCaptureEdgesFromBlock(&t.body);
                    for (t.catches) |*cc| try self.liftCaptureEdgesFromBlock(&cc.body);
                },
                .defer_stmt => |*d| try self.liftCaptureEdgesFromBlock(&d.body),
                else => {},
            }
        }
    }

    fn liftCaptureEdgesFromFunc(self: *SemanticGraph, fd: *const ast.FuncDecl) CaptureLiftError!void {
        const callable_id = self.findFuncDecl(fd) orelse return;
        const outer_scope = self.get(callable_id).?.scope orelse return;
        for (fd.func.upvalues) |uv| {
            const capture_id = self.resolveBindingInScope(outer_scope, uv.name) orelse continue;
            try self.addEdge(.{ .from = callable_id, .to = capture_id, .kind = .capture });
        }
        try self.liftCaptureEdgesFromBlock(&fd.func.body);
    }

    fn liftCaptureEdges(self: *SemanticGraph, mod: *const ast.Module) !void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            try self.liftCaptureEdgesFromFunc(&stmt.func_decl);
        }
    }

    /// The graph entity for a relation declared in ANOTHER HOME.
    ///
    /// `findFuncDecl` answers over `origin`, which is keyed on the AST pointers
    /// this module's lift walked — so a cross-home target was never in it and
    /// the site could only be `MissingSemanticDeclaration`. The declaration is
    /// real and checked; what was missing was a graph entity to BE it.
    ///
    /// It is lifted as an ordinary `.func` child of this module's node, with
    /// one fact the local ones do not carry: `foreign_home`. Every downstream
    /// consumer therefore treats it as a callable identity in the ordinary way
    /// and only realization — which must choose a branch or a relocation —
    /// consults the home. That is the §35 split: one semantic identity, two
    /// physical realizations, and the boundary named exactly once.
    ///
    /// `rememberFunc` keys `origin` on the AST pointer, so the SECOND call to
    /// the same foreign relation finds this node through `findFuncDecl` and no
    /// duplicate identity is created.
    fn liftForeignHome(
        self: *SemanticGraph,
        module: id,
        checked: *const sema.Sema,
        home: []const u8,
    ) !id {
        for (self.nested.of(module)) |child| {
            const node = self.get(child) orelse continue;
            if (node.kind != .module) continue;
            const candidate = node.foreign_home orelse continue;
            if (std.mem.eql(u8, candidate, home)) return child;
        }
        const resolved = checked.resolvedHome(home) orelse return error.MissingSemanticDeclaration;
        const foreign = try self.addChild(module, .{
            .kind = .module,
            .span = .{ .file = resolved.path, .start = 0, .end = 0 },
            .name = resolved.home,
            .foreign_home = resolved.home,
        });
        const first = self.nodes.items.len;
        try self.liftAliasShapes(resolved.module, resolved.path, foreign);
        try self.liftEnumShapes(resolved.module, resolved.path, foreign);
        for (self.nodes.items[first..]) |*node| {
            if (node.kind == .table_shape or node.kind == .enum_shape) node.foreign_home = resolved.home;
        }
        try self.attachMemberDescriptorShapes(foreign);
        return foreign;
    }

    fn liftForeignRelation(
        self: *SemanticGraph,
        module: id,
        checked: *const sema.Sema,
        fact: sema.ApplicationFact,
        file: []const u8,
    ) !id {
        const home = fact.home orelse return error.MissingSemanticDeclaration;
        const fd = fact.target;
        if (fd.path.len != 1) return error.MissingSemanticDeclaration;
        const foreign = try self.liftForeignHome(module, checked, home);
        const func_id = try self.addChild(foreign, .{
            .kind = .func,
            .span = .{ .file = file, .start = fd.loc.line, .end = fd.loc.col },
            .name = fd.path[0],
            .result_descriptor = try types.resolve(fd.func.ret_type, null, self.alloc),
            .ast_ref = @ptrCast(@constCast(fd)),
            .foreign_home = home,
        });
        for (fd.func.params) |param| {
            _ = try self.addChild(func_id, .{
                .kind = .param,
                .span = .{ .file = file, .start = 0, .end = 0 },
                .name = param.name,
            });
        }
        try self.addDescriptorShapeEdge(func_id, 0, foreign, self.nodes.items[func_id].result_descriptor.?);
        return func_id;
    }

    /// Copy the checked callable's principal result pack into graph-owned
    /// descriptors. A tuple annotation is syntax provenance for a semantic
    /// pack, never a tuple value or mandatory aggregate representation.
    fn checkedResultPack(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        fact: sema.ApplicationFact,
    ) ![]types.ResolvedType {
        switch (fact.target.func.ret_type) {
            .tuple => |items| {
                const results = try self.alloc.alloc(types.ResolvedType, items.len);
                errdefer self.alloc.free(results);
                for (items, 0..) |item, i| {
                    results[i] = try types.resolve(item, @ptrCast(@constCast(checked)), self.alloc);
                }
                return results;
            },
            else => {
                const results = try self.alloc.alloc(types.ResolvedType, 1);
                results[0] = fact.result;
                return results;
            },
        }
    }

    fn applicationForExpression(self: *const SemanticGraph, expr: *const Expr) ?*const ApplicationFact {
        for (self.application_facts.items) |*fact| {
            const node = self.get(fact.application) orelse continue;
            const raw = node.ast_ref orelse continue;
            const candidate: *const Expr = @ptrCast(@alignCast(raw));
            if (candidate == expr) return self.application(fact.application);
        }
        return null;
    }

    const BindingAdjustmentSource = struct {
        application: id,
        source_pack: id,
        members: []const id,
    };

    fn bindingAdjustmentSource(
        self: *SemanticGraph,
        source: *const Expr,
        target_count: usize,
    ) !?BindingAdjustmentSource {
        if (target_count <= 1) return null;
        const application_fact = self.applicationForExpression(source) orelse return null;
        const source_fact = self.pack(application_fact.result_pack) orelse return error.InvalidPackAdjustment;
        const source_members = self.packMembers(source_fact.pack) orelse return error.InvalidPackAdjustment;
        const source_demands = self.demandsForRangeMut(source_fact.members) orelse return error.InvalidPackAdjustment;
        for (source_demands, 0..) |*demand, i| {
            demand.* = if (i < target_count) .value else .discard;
        }
        return .{
            .application = application_fact.application,
            .source_pack = application_fact.result_pack,
            .members = source_members,
        };
    }

    fn publishBindingTargetPack(
        self: *SemanticGraph,
        source: BindingAdjustmentSource,
        target_pack: id,
        members: []const PackMember,
    ) !void {
        try self.publishPack(
            target_pack,
            members,
            .{ .fixed = @intCast(members.len) },
            .{ .one = source.application },
        );
        try self.publishPackAdjustment(.{
            .application = source.application,
            .source_pack = source.source_pack,
            .target_pack = target_pack,
        });
    }

    fn publishBindingAdjustment(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        targets: []const *Expr,
        source: *const Expr,
    ) !void {
        const adjustment_source = try self.bindingAdjustmentSource(source, targets.len) orelse return;

        const target_pack = try self.addChild(adjustment_source.application, .{
            .kind = .value,
            .span = self.get(adjustment_source.application).?.span,
            .knowledge = .stable,
            .stage = .sema,
        });
        const target_members = try self.alloc.alloc(PackMember, targets.len);
        defer self.alloc.free(target_members);
        for (targets, 0..) |target, i| {
            const descriptor = checked.exprDescriptor(target) orelse if (i < adjustment_source.members.len)
                self.get(adjustment_source.members[i]).?.descriptor.?
            else
                types.ResolvedType.nil;
            const value = try self.addApplicationValue(adjustment_source.application, target, file, descriptor);
            target_members[i] = .{ .value = value, .demand = .value };
        }
        try self.publishBindingTargetPack(adjustment_source, target_pack, target_members);
    }

    fn localBindingForAdjustment(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        source: BindingAdjustmentSource,
        name: *const ast.LocalName,
        fallback: types.ResolvedType,
    ) !id {
        const descriptor = switch (name.typ) {
            .inferred => fallback,
            else => try types.resolve(name.typ, @ptrCast(@constCast(checked)), self.alloc),
        };
        const caller = self.get(source.application).?.scope orelse return error.InvalidPackAdjustment;
        const raw: *const anyopaque = @ptrCast(name);
        for (self.nested.of(caller)) |child| {
            const node = self.get(child) orelse continue;
            if (node.kind != .local or node.ast_ref != raw) continue;
            if (node.descriptor) |existing| {
                if (!std.meta.eql(existing, descriptor)) return error.InvalidPackAdjustment;
            } else {
                self.nodes.items[child].descriptor = descriptor;
                self.nodes.items[child].knowledge = semantic_algebra.knowledgeOfType(descriptor);
                self.nodes.items[child].stage = .sema;
            }
            return child;
        }
        return self.addChild(caller, .{
            .kind = .local,
            .span = .{ .file = file, .start = name.loc.line, .end = name.loc.col },
            .name = name.ident,
            .descriptor = descriptor,
            .knowledge = semantic_algebra.knowledgeOfType(descriptor),
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(name)),
        });
    }

    fn publishDeclarationBindingAdjustment(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        names: []const ast.LocalName,
        source_expr: *const Expr,
    ) !void {
        const adjustment_source = try self.bindingAdjustmentSource(source_expr, names.len) orelse return;
        const target_pack = try self.addChild(adjustment_source.application, .{
            .kind = .value,
            .span = self.get(adjustment_source.application).?.span,
            .knowledge = .stable,
            .stage = .sema,
        });
        const target_members = try self.alloc.alloc(PackMember, names.len);
        defer self.alloc.free(target_members);
        for (names, 0..) |*name, i| {
            const fallback = if (i < adjustment_source.members.len)
                self.get(adjustment_source.members[i]).?.descriptor.?
            else
                types.ResolvedType.nil;
            const binding = try self.localBindingForAdjustment(checked, file, adjustment_source, name, fallback);
            target_members[i] = .{ .value = binding, .demand = .value };
        }
        try self.publishBindingTargetPack(adjustment_source, target_pack, target_members);
    }

    fn publishBindingAdjustmentsInBlock(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        block: *const ast.Block,
    ) !void {
        for (block.stmts) |*stmt| switch (stmt.*) {
            .local_decl => |declaration| if (declaration.inits.len == 1)
                try self.publishDeclarationBindingAdjustment(checked, file, declaration.names, declaration.inits[0]),
            .global_decl => |declaration| if (!declaration.star and declaration.inits.len == 1)
                try self.publishDeclarationBindingAdjustment(checked, file, declaration.names, declaration.inits[0]),
            .assign => |assignment| if (assignment.values.len == 1)
                try self.publishBindingAdjustment(checked, file, assignment.targets, assignment.values[0]),
            .do_block => |nested| try self.publishBindingAdjustmentsInBlock(checked, file, &nested.body),
            .while_loop => |loop| try self.publishBindingAdjustmentsInBlock(checked, file, &loop.body),
            .repeat_loop => |loop| try self.publishBindingAdjustmentsInBlock(checked, file, &loop.body),
            .num_for => |loop| try self.publishBindingAdjustmentsInBlock(checked, file, &loop.body),
            .gen_for => |loop| try self.publishBindingAdjustmentsInBlock(checked, file, &loop.body),
            .if_stmt => |conditional| {
                try self.publishBindingAdjustmentsInBlock(checked, file, &conditional.then);
                for (conditional.elseifs) |*branch| {
                    try self.publishBindingAdjustmentsInBlock(checked, file, &branch.body);
                }
                if (conditional.else_body) |*branch| {
                    try self.publishBindingAdjustmentsInBlock(checked, file, branch);
                }
            },
            .try_stmt => |attempt| {
                try self.publishBindingAdjustmentsInBlock(checked, file, &attempt.body);
                for (attempt.catches) |*clause| {
                    try self.publishBindingAdjustmentsInBlock(checked, file, &clause.body);
                }
            },
            .defer_stmt => |deferred| try self.publishBindingAdjustmentsInBlock(checked, file, &deferred.body),
            .func_decl => |function| try self.publishBindingAdjustmentsInBlock(checked, file, &function.func.body),
            else => {},
        };
    }

    /// Publish identities and descriptors that survived semantic checking.
    /// Absence of a checked fact stays unresolved rather than falling back to
    /// name matching.
    pub fn liftModuleWithCheckedCalls(
        self: *SemanticGraph,
        mod: *const ast.Module,
        checked: *const sema.Sema,
        file: []const u8,
    ) !id {
        self.module_path = file;
        self.launch_worlds = checked.worlds;
        // THE DEFINER'S HALF OF `(home, name)`, established at the same moment
        // as the path it is derived from, so no consumer can observe a graph
        // that knows where the module came from and not which home it is.
        //
        // A local `Io` rather than a threaded parameter: `homeOfPath` probes for
        // the project root and nothing else, this runs once per lift, and the
        // alternative is an `Io` argument on the lift signature and on every one
        // of its fourteen call sites — most of them unit tests that have no `Io`
        // to give. `sema.importForeignHeader` reaches for a local one for the
        // same reason.
        {
            var threaded = std.Io.Threaded.init(self.alloc, .{});
            defer threaded.deinit();
            if (home_resolve.homeOfPath(self.alloc, threaded.io(), file)) |h| {
                if (self.home) |old| self.alloc.free(old);
                self.home = h;
            } else |_| {}
        }
        const module = try self.liftModuleWithCalls(mod, file);

        const candidate_limit = self.application_candidates.bit_length;
        var candidate: usize = 0;
        while (candidate < candidate_limit) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const call_id = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            if (call_id >= self.nodes.items.len) return error.InvalidApplicationFact;
            if (self.application(call_id) != null) continue;
            const raw = self.nodes.items[call_id].ast_ref orelse continue;
            const expr: *const Expr = @ptrCast(@alignCast(raw));
            const fact = checked.applicationFact(expr) orelse continue;
            const relation = self.findFuncDecl(fact.target) orelse
                try self.liftForeignRelation(module, checked, fact, file);
            const applied = self.findFuncDecl(fact.applied) orelse
                return error.MissingApplicationApplied;
            const target = self.findFuncDecl(fact.target) orelse
                return error.MissingApplicationTarget;
            const caller = self.nodes.items[call_id].scope orelse return error.MissingApplicationCaller;
            const caller_node = self.get(caller) orelse return error.MissingApplicationCaller;
            if (!self.callable(caller) and caller_node.scope != null) return error.MissingApplicationCaller;
            if (self.nodes.items[call_id].demand == null) return error.MissingApplicationDemand;

            const result_descriptors = try self.checkedResultPack(checked, fact);
            defer self.alloc.free(result_descriptors);
            self.nodes.items[call_id].descriptor = if (result_descriptors.len > 0)
                result_descriptors[0]
            else
                .void;

            var subject_value: ?id = null;
            if (fact.subject) |subject| {
                const descriptor = checked.exprDescriptor(subject) orelse
                    return error.MissingApplicationDescriptor;
                subject_value = try self.addApplicationValue(call_id, subject, file, descriptor);
                try self.noteOrigin(subject_value.?, subject, caller);
            }
            const arguments = try self.alloc.alloc(id, fact.arguments.len);
            defer self.alloc.free(arguments);
            for (fact.arguments, 0..) |argument, i| {
                const descriptor = checked.exprDescriptor(argument) orelse
                    return error.MissingApplicationDescriptor;
                arguments[i] = try self.addApplicationValue(call_id, argument, file, descriptor);
                try self.noteOrigin(arguments[i], argument, caller);
            }
            const results = try self.alloc.alloc(id, result_descriptors.len);
            defer self.alloc.free(results);
            for (result_descriptors, 0..) |descriptor, i| {
                results[i] = try self.addApplicationValue(call_id, expr, file, descriptor);
                const relation_home = self.homeOf(relation) orelse return error.MissingSemanticDeclaration;
                try self.addDescriptorShapeEdge(results[i], 0, relation_home, descriptor);
            }
            try self.publishApplication(
                call_id,
                applied,
                relation,
                target,
                subject_value,
                arguments,
                results,
            );
            try self.publishApplicationProjections(call_id);
        }
        try self.publishBindingAdjustmentsInBlock(checked, file, &mod.body);
        try self.liftCaptureEdges(mod);
        try self.publishApplicationEffects(mod);
        // AFTER the effect fixpoint, deliberately. That pass blocks a relation
        // on any `.member` edge inside it, and a world's member edges are the
        // graph's record of exactly the reach it means. Publishing worlds first
        // would have moved `effect`/`authority` on relations for a reason that
        // has nothing to do with what they do — a measurement changing because
        // it was measured.
        try self.publishApplicationWorlds(file);
        return module;
    }

    /// WORLD, for every application occurrence — published or not.
    ///
    /// THE FACT THE GRAPH DID NOT HAVE. `protocol-projection-one.md` §10.1:
    /// "THERE IS NO WORLD FIELD. `grep -c world` over `ApplicationFact` returns
    /// 0. World ownership is still distributed and transitional, so injection
    /// algebra is NOT yet graph-bound at the application." This binds it, for
    /// the worlds that exist.
    ///
    /// IT DOES NOT COLLAPSE INTO AUTHORITY OR WITNESS, and the split is the
    /// ruling's: world SUPPLIES facts, authority REQUIRES them, witness PROVES
    /// satisfaction. `env("HOME")` draws the `os` world whether or not any
    /// authority is demanded of it, and a relation may demand authority with no
    /// world in sight. Three Cards, three questions.
    ///
    /// EVERY ANSWER COMES FROM `subject_home.declarations`, which is the sole
    /// authority for what a world is, what it provides, how it is granted, and
    /// what that reach confers. This pass adds NO name list: it asks
    /// the world table the same questions the resolver asks.
    ///
    /// THE MODULE WINS. `docs/rulings.md`: "injection ADDS reach, it never TAKES
    /// A NAME." A module that declares its own `env` draws no world at an
    /// application of it, and this pass checks that FIRST.
    fn publishApplicationWorlds(self: *SemanticGraph, file: []const u8) !void {
        const Drawn = struct { application: id, home: ?subject_home.Home, member: []const u8 };
        var drawn: std.ArrayListUnmanaged(Drawn) = .empty;
        defer drawn.deinit(self.alloc);

        var candidate: usize = 0;
        while (candidate < self.application_candidates.bit_length) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const site = std.math.cast(id, candidate) orelse break;
            const node = self.get(site) orelse continue;
            const raw = node.ast_ref orelse continue;
            const expr: *const Expr = @ptrCast(@alignCast(raw));
            const reached = self.worldOfApplication(site, expr) orelse continue;
            try drawn.append(self.alloc, .{
                .application = site,
                .home = reached.home,
                .member = reached.member,
            });
        }

        // ONE PASS PER WORLD so a world's member range is contiguous. Interleaved
        // appends would have produced ranges that overlap two worlds, which is
        // the kind of packed-storage defect that reads as a wrong fact rather
        // than as a crash.
        for (&subject_home.declarations) |*declaration| {
            var uses = false;
            for (drawn.items) |row| {
                if (row.home) |h| {
                    if (h == declaration.home) uses = true;
                }
            }
            if (!uses) continue;
            const module = self.moduleEntity() orelse continue;
            const world = try self.addChild(module, .{
                .kind = .value,
                .span = .{ .file = file, .start = 0, .end = 0 },
                .name = subject_home.homeName(declaration.home),
                .knowledge = .stable,
                .stage = .sema,
            });
            const start = self.world_members.items.len;
            for (drawn.items) |row| {
                const h = row.home orelse continue;
                if (h != declaration.home) continue;
                if (row.member.len == 0) continue;
                if (self.worldMemberNamed(start, row.member)) continue;
                const member = try self.addChild(world, .{
                    .kind = .value,
                    .span = .{ .file = file, .start = 0, .end = 0 },
                    .name = row.member,
                    .knowledge = .stable,
                    .stage = .sema,
                });
                try self.addEdge(.{ .from = world, .to = member, .kind = .member });
                try self.world_members.append(self.alloc, member);
            }
            try self.worlds.append(self.alloc, .{
                .world = world,
                .home = declaration.home,
                .reach = declaration.reach,
                .members = try factRange(start, self.world_members.items.len - start),
            });
        }

        for (drawn.items) |row| {
            const card: Card = if (row.home) |h| blk: {
                for (self.worlds.items) |fact| {
                    if (fact.home == h) break :blk .{ .one = fact.world };
                }
                break :blk .unknown;
            } else .none;
            try self.draws.append(self.alloc, .{ .application = row.application, .world = card });
        }
    }

    fn worldMemberNamed(self: *const SemanticGraph, start: usize, name: []const u8) bool {
        for (self.world_members.items[start..]) |member| {
            const node = self.get(member) orelse continue;
            const existing = node.name orelse continue;
            if (std.mem.eql(u8, existing, name)) return true;
        }
        return false;
    }

    fn moduleEntity(self: *const SemanticGraph) ?id {
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind == .module) return @intCast(i);
        }
        return null;
    }

    const Reached = struct { home: ?subject_home.Home, member: []const u8 };

    /// Which world supplies one application, or null for "not determined".
    ///
    /// FAILS CLOSED at every step. A method call whose receiver the graph does
    /// not carry a descriptor for is `null`, not a guess: the receiver decides
    /// the home and reading it from the relation's SPELLING is the exact
    /// inference `face-role-launch-one.md` §1 forbids.
    fn worldOfApplication(
        self: *const SemanticGraph,
        site: id,
        expr: *const Expr,
    ) ?Reached {
        // A RESOLVED RELATION IS SUPPLIED BY A DECLARATION, NOT BY A WORLD.
        // Published means sema bound an exact declaration; a declaration lives
        // in a HOME; and `law.md` §23 is explicit that a home is not a world
        // grant. So the answer is `.none` — known-absent — and it does not
        // depend on WHICH home.
        //
        // MEASURED, AND THE FIRST DRAFT WAS WRONG HERE. This used to answer
        // `.none` only when `foreign_home == null`, so `step(3)` declared at
        // module scope drew `.none` and the same relation moved to a sibling
        // home drew nothing at all. `gate/protocol.sh` §7.6 caught it: "move a
        // relation to another home, semantics unchanged" is a control, and a
        // world fact that changes when a declaration moves house is a home
        // leaking into a world.
        if (self.application(site)) |fact| {
            if (self.applicationRelation(fact.application) != null) {
                return .{ .home = null, .member = "" };
            }
        }
        switch (expr.*) {
            .call => |c| switch (c.func.*) {
                .name => |n| {
                    if (self.findFunc(n.ident) != null) return .{ .home = null, .member = "" };
                    const home = subject_home.injectedWorldProvidingFor(self.launch_worlds.slice(), n.ident) orelse return null;
                    return .{ .home = home, .member = n.ident };
                },
                // `math.sqrt(x)`, `c.abs(v)`, `os.env(k)` — the ANCHORED face,
                // where the world is named outright and nothing is inferred.
                .field => |f| {
                    if (f.obj.* != .name) return null;
                    const home = subject_home.worldNamedFor(self.launch_worlds.slice(), f.obj.name.ident) orelse return null;
                    if (!subject_home.homeProvides(home, f.field)) return null;
                    return .{ .home = home, .member = f.field };
                },
                else => return null,
            },
            .method_call => |mc| {
                if (mc.obj.* != .name) return null;
                const receiver = mc.obj.name.ident;
                // `test:assert(c, m)` — the world reached on its own subject.
                if (subject_home.worldNamedFor(self.launch_worlds.slice(), receiver)) |home| {
                    if (!subject_home.homeProvides(home, mc.method)) return null;
                    return .{ .home = home, .member = mc.method };
                }
                // `stdout:write(x)` — the world supplies the INSTANCE and a
                // different subject carries the relation, which is the whole of
                // cross-projection. The world drawn is the one that supplied
                // the standing name.
                if (subject_home.suppliedInstanceFor(self.launch_worlds.slice(), receiver) != null) {
                    if (!subject_home.worldReached(self.launch_worlds.slice(), .io)) return null;
                    return .{ .home = .io, .member = receiver };
                }
                return null;
            },
            else => return null,
        }
    }

    /// The place an application value reads, when it reads one exactly.
    ///
    /// Only a bare name resolves. `p:add(q)` names two places and `f(x + 1)`
    /// names none — a derived value has no single place and inventing one would
    /// make `alias` unanswerable, the same judgment `place.zig` takes about
    /// record fields.
    fn noteOrigin(self: *SemanticGraph, value: id, expr: *const Expr, caller: id) !void {
        if (expr.* != .name) return;
        const relation = self.enclosingCallable(caller) orelse return;
        const body = self.bodyOf(relation) orelse return;
        const found = body.places.find(expr.name.ident) orelse return;
        try self.origins.append(self.alloc, .{
            .value = value,
            .relation = relation,
            .place = found.id,
        });
    }

    /// One relation's inputs to the effect fixpoint, gathered in a single pass
    /// so the fixpoint iterates over edges of the call graph rather than
    /// re-walking the node table once per round.
    const EffectRow = struct {
        relation: id,
        /// Something about this relation's body the graph cannot see through.
        /// A blocked relation is never effect-free and never becomes so.
        blocked: bool = false,
        callees_start: u32 = 0,
        callees_len: u32 = 0,
    };

    /// Declarations whose body is a placeholder for a symbol outside this
    /// module. `@ffi("llabs")` lifts as an ordinary `func` node with an
    /// ordinary body — MEASURED: the graph for `@ffi("llabs") absval: i64 =
    /// (n) 0` publishes a normal application bound to a normal callable, and
    /// nothing in the graph records that applying it runs `llabs`. So this one
    /// fact has to come from the declaration, which is why the effect pass
    /// takes the AST module it was lifted from.
    fn declarationIsForeign(fd: *const ast.FuncDecl) bool {
        for (fd.attributes) |attribute| {
            for ([_][]const u8{ "ffi", "extern", "foreign", "import" }) |name| {
                if (std.mem.eql(u8, attribute.name, name)) return true;
            }
        }
        return false;
    }

    fn markForeignDeclarations(
        self: *SemanticGraph,
        block: *const ast.Block,
        foreign: *std.DynamicBitSetUnmanaged,
    ) void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    if (declarationIsForeign(fd)) {
                        if (self.findFuncDecl(fd)) |entity| {
                            if (entity < foreign.bit_length) foreign.set(entity);
                        }
                    }
                    self.markForeignDeclarations(&fd.func.body, foreign);
                },
                .if_stmt => |*i| {
                    self.markForeignDeclarations(&i.then, foreign);
                    for (i.elseifs) |*ei| self.markForeignDeclarations(&ei.body, foreign);
                    if (i.else_body) |*eb| self.markForeignDeclarations(eb, foreign);
                },
                .while_loop => |*w| self.markForeignDeclarations(&w.body, foreign),
                .repeat_loop => |*r| self.markForeignDeclarations(&r.body, foreign),
                .do_block => |*d| self.markForeignDeclarations(&d.body, foreign),
                .num_for => |*nf| self.markForeignDeclarations(&nf.body, foreign),
                .gen_for => |*g| self.markForeignDeclarations(&g.body, foreign),
                .try_stmt => |*t| {
                    self.markForeignDeclarations(&t.body, foreign);
                    for (t.catches) |*cc| self.markForeignDeclarations(&cc.body, foreign);
                },
                .defer_stmt => |*d| self.markForeignDeclarations(&d.body, foreign),
                else => {},
            }
        }
    }

    /// THE ONE EXCEPTION TO "AN UNRESOLVED CANDIDATE IS NEVER EFFECT-FREE".
    ///
    /// `s:len()` and `s:byte(i)` lower through dedicated bootstrap rules rather
    /// than through a published relation id (GAP-155), so they sit in the
    /// unresolved column forever and, until this, blocked every relation that
    /// touched a string. MEASURED on `native.id`: 34 relations blocked directly
    /// by exactly these two faces, and transitively 60 of 92 — including `run`
    /// and therefore `main`. Not one of those blocks was a real effect.
    ///
    /// STATED AS A CLOSED LIST, NOT AS A PROPERTY, AND THE REASON IS THAT
    /// `native_bootstrap`'s bootstrap set IS NOT A PURITY PREDICATE. It also
    /// contains `stdin:read`, `stdin:line`, `stdout:write`, `print` and
    /// `gatecap` — every one of which reaches the world. Admitting the
    /// bootstrap set wholesale would publish "pure" about host egress, which is
    /// precisely the greatest-fixpoint error this pass exists to avoid.
    ///
    /// `sub` IS DELIBERATELY ABSENT even though it is in the same bootstrap set
    /// and the compile-time evaluator implements it. `gate/collapse.sh` pins
    /// `len` and `byte` against the emitted code and nothing pins `sub`'s
    /// negative-index and clamping behaviour across the two implementations, so
    /// it stays unproven rather than assumed.
    fn unobservableStringFace(self: *const SemanticGraph, occurrence: id) bool {
        const node = self.get(occurrence) orelse return false;
        const raw = node.ast_ref orelse return false;
        const expr: *const ast.Expr = @ptrCast(@alignCast(raw));
        if (expr.* != .method_call) return false;
        const mc = expr.method_call;

        const arity_ok = if (std.mem.eql(u8, mc.method, "len"))
            mc.args.len == 0
        else if (std.mem.eql(u8, mc.method, "byte"))
            mc.args.len == 1
        else
            false;
        if (!arity_ok) return false;

        // A WORLD HANDLE IS NEVER A STRING, whatever the spelling after the
        // colon — and WHICH names are world handles is a question the world
        // declaration table answers exactly.
        //
        // THIS USED TO BE A LIST OF FIVE SPELLINGS (`stdin stdout stderr io
        // os`) written down here, in a file that has no other business knowing
        // what a world is. `subject_home.declarations` is the sole authority
        // for both halves of the question — `worldNamedFor` for a world reached
        // on its own subject, `suppliedInstanceFor` for a standing instance the
        // world supplies — and asking it covers every world including the ones
        // the list forgot. A world added to that table is a handle this rule
        // already knows about, with no edit here.
        if (mc.obj.* == .name) {
            const receiver = mc.obj.name.ident;
            if (subject_home.worldNamedFor(self.launch_worlds.slice(), receiver) != null) return false;
            if (subject_home.suppliedInstanceFor(self.launch_worlds.slice(), receiver) != null) return false;
        }

        // A module that declares its own relation of this name OWNS the
        // spelling. If an application of it is unresolved, it is unresolved for
        // a real reason and must block. Scanned rather than routed through
        // `findFunc`, which answers null for an AMBIGUOUS name and would turn
        // two declarations of `len` into an admission.
        for (self.nodes.items) |declaration| {
            if (declaration.kind != .func) continue;
            const name = declaration.name orelse continue;
            if (std.mem.eql(u8, name, mc.method)) return false;
        }
        return true;
    }

    /// Query face of `unobservableStringFace` for the effect consumer, which
    /// must admit exactly the same sites the fixpoint declined to block.
    pub fn applicationIsUnobservableStringFace(self: *const SemanticGraph, occurrence: id) bool {
        if (!self.isApplicationCandidate(occurrence)) return false;
        if (self.application(occurrence) != null) return false;
        return self.unobservableStringFace(occurrence);
    }

    /// Nearest enclosing callable of an entity, by `scope`. Null when the
    /// entity hangs off the module rather than off a relation.
    fn enclosingCallable(self: *const SemanticGraph, entity: id) ?id {
        var cursor: ?id = entity;
        while (cursor) |current| {
            if (self.callable(current)) return current;
            cursor = (self.get(current) orelse return null).scope;
        }
        return null;
    }

    /// EFFECT AND AUTHORITY for every published application.
    ///
    /// `ApplicationFact.effect` and `.authority` shipped with no write site at
    /// all: `Card` distinguishes "known-absent" from "not yet known", and every
    /// application said "not yet known" forever, so every consumer downstream
    /// had to assume the worst. This is the write site. It publishes exactly
    /// one value — `.none` — and only where the whole transitive body is
    /// provably unobservable; everything else keeps `.unknown`, which is the
    /// honest answer and not a sentinel.
    ///
    /// A relation is EFFECT-FREE when all of these hold:
    ///   1. it is not a foreign declaration (`declarationIsForeign`);
    ///   2. every application candidate whose caller is this relation RESOLVED
    ///      to a published fact — an unresolved candidate is a call the graph
    ///      could not identify, and `print("hi")` is measured to be exactly
    ///      that shape (a `.call` node in `unresolved_applications`);
    ///   3. every callee it does resolve is itself effect-free;
    ///   4. it captures nothing — a `.capture` edge is the graph's own record
    ///      of reaching outside the frame, which is where a write to somebody
    ///      else's binding would show up;
    ///   5. nothing inside it reads a static `.member` — the injected world
    ///      arrives as member edges, so this is where `env`/`arg`/`clock` land.
    ///
    /// The fixpoint is LEAST: nothing starts effect-free and a relation is only
    /// promoted once all of its callees already are, so a recursive relation is
    /// never promoted at all. That is a missed fact. The opposite error — a
    /// greatest fixpoint that starts optimistic — publishes "pure" about
    /// something impure the moment any of the five conditions is incomplete,
    /// and this tree has shipped two silent miscompiles already.
    ///
    /// AUTHORITY rides on the same evidence deliberately: a relation that
    /// applies nothing foreign, resolves every call it makes, captures nothing
    /// and reads no world member cannot be exercising authority either. When
    /// authority acquires evidence of its own — a capability fact rather than
    /// the absence of one — it separates from this and gets its own predicate.
    fn publishApplicationEffects(self: *SemanticGraph, mod: *const ast.Module) !void {
        const node_count = self.nodes.items.len;
        if (node_count == 0) return;

        var foreign = try std.DynamicBitSetUnmanaged.initEmpty(self.alloc, node_count);
        defer foreign.deinit(self.alloc);
        self.markForeignDeclarations(&mod.body, &foreign);

        var rows: std.ArrayListUnmanaged(EffectRow) = .empty;
        defer rows.deinit(self.alloc);
        var callees: std.ArrayListUnmanaged(id) = .empty;
        defer callees.deinit(self.alloc);
        var row_of: std.AutoHashMapUnmanaged(id, u32) = .empty;
        defer row_of.deinit(self.alloc);

        var entity: usize = 0;
        while (entity < node_count) : (entity += 1) {
            const relation = std.math.cast(id, entity) orelse break;
            if (!self.callable(relation)) continue;
            try row_of.put(self.alloc, relation, @intCast(rows.items.len));
            try rows.append(self.alloc, .{
                .relation = relation,
                .blocked = relation < foreign.bit_length and foreign.isSet(relation),
            });
        }
        if (rows.items.len == 0) return;

        // Condition 5, then 4: a member read or a capture blocks the relation
        // it sits inside, whichever relation that is.
        for (self.edges.items) |edge| {
            if (edge.kind != .member and edge.kind != .capture) continue;
            const holder = self.enclosingCallable(edge.from) orelse continue;
            const row = row_of.get(holder) orelse continue;
            rows.items[row].blocked = true;
        }

        // Condition 2: an unresolved candidate is a call the graph could not
        // identify, so its caller can never be proven unobservable.
        var candidate: usize = 0;
        while (candidate < self.application_candidates.bit_length) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const site = std.math.cast(id, candidate) orelse break;
            if (self.applicationRelation(site) != null) continue;
            if (self.unobservableStringFace(site)) continue;
            const node = self.get(site) orelse continue;
            const caller = self.enclosingCallable(node.scope orelse continue) orelse continue;
            const row = row_of.get(caller) orelse continue;
            rows.items[row].blocked = true;
        }

        // Condition 3, grouped by caller so the fixpoint below walks call-graph
        // edges instead of re-scanning the candidate column every round.
        for (rows.items) |*row| {
            row.callees_start = @intCast(callees.items.len);
            candidate = 0;
            while (candidate < self.application_candidates.bit_length) : (candidate += 1) {
                if (!self.application_candidates.isSet(candidate)) continue;
                const site = std.math.cast(id, candidate) orelse break;
                const callee = self.applicationRelation(site) orelse continue;
                const node = self.get(site) orelse continue;
                const caller = self.enclosingCallable(node.scope orelse continue) orelse continue;
                if (caller != row.relation) continue;
                try callees.append(self.alloc, callee);
            }
            row.callees_len = @as(u32, @intCast(callees.items.len)) - row.callees_start;
        }

        // THE FIXPOINT RUNS ON BADNESS, AND IS STILL LEAST.
        //
        // It used to run forward on GOODNESS — a relation became effect-free
        // once every callee already was. That is a least fixpoint which can
        // never close a CYCLE, so no recursive relation was ever promoted and
        // neither was anything that reaches one. MEASURED on `native.id` with
        // every blocking condition satisfied and NOTHING blocked at all: 47 of
        // 92 relations still read `.unknown`, every one of them because the
        // recursive-descent core (`expr` / `term` / `factor`) is mutually
        // recursive. `run` and therefore `main` were among them.
        //
        // The dual is grounded in exactly the same evidence and is still least:
        // BAD is the LEAST set that contains every BLOCKED relation and is
        // closed under "applies a relation in BAD". A relation is effect-free
        // exactly when it is not in BAD — when no finite call chain out of it
        // reaches a relation the graph could not clear. A cycle none of whose
        // members is blocked performs no observable action however long it
        // runs, and that is the fact the forward form threw away.
        //
        // THIS IS NOT THE GREATEST FIXPOINT THIS PASS WARNS ABOUT. That one
        // starts every relation effect-free and removes the ones it can
        // disprove, so an incomplete blocking condition silently publishes
        // "pure". Here the seed set is the blocking evidence itself, exactly as
        // before: an incomplete blocking condition is wrong in precisely the
        // same way, and in no new way. What changed is the direction of
        // propagation, not what is trusted.
        var bad = try std.DynamicBitSetUnmanaged.initEmpty(self.alloc, node_count);
        defer bad.deinit(self.alloc);
        for (rows.items) |row| {
            if (row.blocked) bad.set(row.relation);
        }
        var spread = true;
        while (spread) {
            spread = false;
            for (rows.items) |row| {
                if (bad.isSet(row.relation)) continue;
                const start: usize = row.callees_start;
                for (callees.items[start .. start + row.callees_len]) |callee| {
                    if (callee >= bad.bit_length or bad.isSet(callee)) {
                        bad.set(row.relation);
                        spread = true;
                        break;
                    }
                }
            }
        }

        var effect_free = try std.DynamicBitSetUnmanaged.initEmpty(self.alloc, node_count);
        defer effect_free.deinit(self.alloc);
        for (rows.items) |row| {
            if (!bad.isSet(row.relation)) effect_free.set(row.relation);
        }

        for (self.application_facts.items) |*fact| {
            const callee = self.applicationRelation(fact.application) orelse continue;
            if (callee >= effect_free.bit_length or !effect_free.isSet(callee)) continue;
            fact.effect = .none;
            fact.authority = .none;
        }
    }

    const DependencyFrame = struct {
        row: usize,
        next: usize,
    };

    fn orderFunctionComponents(
        alloc: std.mem.Allocator,
        functions: []const id,
        unlocks: []const std.ArrayListUnmanaged(usize),
    ) ![]const id {
        const reverse = try alloc.alloc(std.ArrayListUnmanaged(usize), functions.len);
        defer {
            for (reverse) |*list| list.deinit(alloc);
            alloc.free(reverse);
        }
        for (reverse) |*list| list.* = .empty;
        for (unlocks, 0..) |list, row| {
            for (list.items) |dependent| try reverse[dependent].append(alloc, row);
        }

        const visited = try alloc.alloc(bool, functions.len);
        defer alloc.free(visited);
        @memset(visited, false);
        var finish: std.ArrayListUnmanaged(usize) = .empty;
        defer finish.deinit(alloc);
        var frames: std.ArrayListUnmanaged(DependencyFrame) = .empty;
        defer frames.deinit(alloc);

        for (functions, 0..) |_, root| {
            if (visited[root]) continue;
            visited[root] = true;
            try frames.append(alloc, .{ .row = root, .next = 0 });
            while (frames.items.len > 0) {
                const top = frames.items.len - 1;
                const row = frames.items[top].row;
                if (frames.items[top].next < unlocks[row].items.len) {
                    const dependent = unlocks[row].items[frames.items[top].next];
                    frames.items[top].next += 1;
                    if (!visited[dependent]) {
                        visited[dependent] = true;
                        try frames.append(alloc, .{ .row = dependent, .next = 0 });
                    }
                    continue;
                }
                _ = frames.pop().?;
                try finish.append(alloc, row);
            }
        }

        const components = try alloc.alloc(usize, functions.len);
        defer alloc.free(components);
        @memset(components, std.math.maxInt(usize));
        var component_count: usize = 0;
        var stack: std.ArrayListUnmanaged(usize) = .empty;
        defer stack.deinit(alloc);
        var finish_index = finish.items.len;
        while (finish_index > 0) {
            finish_index -= 1;
            const root = finish.items[finish_index];
            if (components[root] != std.math.maxInt(usize)) continue;
            components[root] = component_count;
            try stack.append(alloc, root);
            while (stack.items.len > 0) {
                const row = stack.pop().?;
                for (reverse[row].items) |predecessor| {
                    if (components[predecessor] != std.math.maxInt(usize)) continue;
                    components[predecessor] = component_count;
                    try stack.append(alloc, predecessor);
                }
            }
            component_count += 1;
        }

        const component_counts = try alloc.alloc(usize, component_count);
        defer alloc.free(component_counts);
        @memset(component_counts, 0);
        for (components) |component| component_counts[component] += 1;
        const component_offsets = try alloc.alloc(usize, component_count + 1);
        defer alloc.free(component_offsets);
        component_offsets[0] = 0;
        for (component_counts, 0..) |count, component| {
            component_offsets[component + 1] = component_offsets[component] + count;
        }
        const component_cursors = try alloc.dupe(usize, component_offsets[0..component_count]);
        defer alloc.free(component_cursors);
        const component_rows = try alloc.alloc(usize, functions.len);
        defer alloc.free(component_rows);
        for (components, 0..) |component, row| {
            component_rows[component_cursors[component]] = row;
            component_cursors[component] += 1;
        }

        const component_unlocks = try alloc.alloc(std.ArrayListUnmanaged(usize), component_count);
        defer {
            for (component_unlocks) |*list| list.deinit(alloc);
            alloc.free(component_unlocks);
        }
        for (component_unlocks) |*list| list.* = .empty;
        const component_degree = try alloc.alloc(usize, component_count);
        defer alloc.free(component_degree);
        @memset(component_degree, 0);
        var component_edges: std.AutoHashMapUnmanaged(u128, void) = .empty;
        defer component_edges.deinit(alloc);
        for (unlocks, 0..) |list, row| {
            const from = components[row];
            for (list.items) |dependent| {
                const to = components[dependent];
                if (from == to) continue;
                const edge = (@as(u128, from) << 64) | @as(u128, to);
                const slot = try component_edges.getOrPut(alloc, edge);
                if (slot.found_existing) continue;
                try component_unlocks[from].append(alloc, to);
                component_degree[to] += 1;
            }
        }

        var ready: std.ArrayListUnmanaged(usize) = .empty;
        defer ready.deinit(alloc);
        for (component_degree, 0..) |degree, component| {
            if (degree == 0) try ready.append(alloc, component);
        }
        var component_order: std.ArrayListUnmanaged(usize) = .empty;
        defer component_order.deinit(alloc);
        while (ready.items.len > 0) {
            const component = ready.pop().?;
            try component_order.append(alloc, component);
            for (component_unlocks[component].items) |dependent| {
                component_degree[dependent] -= 1;
                if (component_degree[dependent] == 0) try ready.append(alloc, dependent);
            }
        }
        if (component_order.items.len != component_count) return error.UnresolvedApplication;

        const ordered = try alloc.alloc(id, functions.len);
        errdefer alloc.free(ordered);
        var ordered_len: usize = 0;
        for (component_order.items) |component| {
            for (component_rows[component_offsets[component]..component_offsets[component + 1]]) |row| {
                ordered[ordered_len] = functions[row];
                ordered_len += 1;
            }
        }
        if (ordered_len != functions.len) return error.UnresolvedApplication;
        return ordered;
    }

    /// Emit order for exact module function entities: callees before callers.
    /// An unresolved application inside the requested function set refuses the
    /// projection rather than becoming an absent dependency.
    pub fn moduleFunctionEmitOrder(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        functions: []const id,
    ) ![]const id {
        if (functions.len == 0) return try alloc.dupe(id, functions);

        var rows: std.AutoHashMapUnmanaged(id, usize) = .empty;
        defer rows.deinit(alloc);
        for (functions, 0..) |function, row| {
            const node = self.get(function) orelse return error.InvalidFunctionEntity;
            if (!self.callable(function) and node.scope != null) return error.InvalidFunctionEntity;
            const slot = try rows.getOrPut(alloc, function);
            if (slot.found_existing) return error.DuplicateFunctionEntity;
            slot.value_ptr.* = row;
        }

        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            const application_id = std.math.cast(id, candidate) orelse
                return error.UnresolvedApplication;
            const application_node = self.get(application_id) orelse
                return error.UnresolvedApplication;
            const caller = application_node.scope orelse return error.UnresolvedApplication;
            if (!rows.contains(caller)) continue;
            if (self.application(application_id) == null) {
                if (self.isBootstrapApplicationNode(application_id)) continue;
                return error.UnresolvedApplication;
            }
        }

        const in_degree = try alloc.alloc(usize, functions.len);
        defer alloc.free(in_degree);
        @memset(in_degree, 0);
        const unlocks = try alloc.alloc(std.ArrayListUnmanaged(usize), functions.len);
        defer {
            for (unlocks) |*list| list.deinit(alloc);
            alloc.free(unlocks);
        }
        for (unlocks) |*list| list.* = .empty;
        var dependencies: std.AutoHashMapUnmanaged(u128, void) = .empty;
        defer dependencies.deinit(alloc);

        for (functions) |function| {
            for (self.applicationsIn(function)) |occurrence| {
                const fact = self.application(occurrence) orelse return error.UnresolvedApplication;
                const caller_id = self.applicationCaller(fact.application) orelse continue;
                const caller = rows.get(caller_id) orelse continue;
                const relation_id = self.applicationRelation(fact.application) orelse return error.UnresolvedApplication;
                if (self.get(relation_id) == null) return error.UnresolvedApplication;
                if (!self.callable(relation_id)) continue;
                const relation = rows.get(relation_id) orelse continue;
                const dependency = (@as(u128, relation) << 64) | @as(u128, caller);
                const slot = try dependencies.getOrPut(alloc, dependency);
                if (slot.found_existing) continue;
                try unlocks[relation].append(alloc, caller);
                in_degree[caller] += 1;
            }
        }
        if (dependencies.count() == 0) return try alloc.dupe(id, functions);

        var ready: std.ArrayListUnmanaged(usize) = .empty;
        defer ready.deinit(alloc);
        for (in_degree, 0..) |degree, row| {
            if (degree == 0) try ready.append(alloc, row);
        }

        var ordered: std.ArrayListUnmanaged(id) = .empty;
        errdefer ordered.deinit(alloc);

        while (ready.items.len > 0) {
            const row = ready.pop().?;
            try ordered.append(alloc, functions[row]);
            for (unlocks[row].items) |dependent| {
                in_degree[dependent] -= 1;
                if (in_degree[dependent] == 0) try ready.append(alloc, dependent);
            }
        }

        if (ordered.items.len != functions.len) {
            ordered.clearAndFree(alloc);
            return try orderFunctionComponents(alloc, functions, unlocks);
        }

        return try ordered.toOwnedSlice(alloc);
    }

    /// Get the CallShape for a specific call node.
    pub fn callShapeOf(self: *const SemanticGraph, entity: id) ?types.CallShape {
        if (!self.isApplicationCandidate(entity)) return null;
        const node = self.get(entity) orelse return null;
        return node.call_shape;
    }

    /// Count nodes of a given kind (diagnostics / MCP queries).
    pub fn countKind(self: *const SemanticGraph, kind: NodeKind) usize {
        var n: usize = 0;
        for (self.nodes.items) |node| {
            if (node.kind == kind) n += 1;
        }
        return n;
    }

    fn countCallableHomes(self: *const SemanticGraph) usize {
        var n: usize = 0;
        for (self.nodes.items, 0..) |_, i| {
            if (self.callable(@intCast(i))) n += 1;
        }
        return n;
    }

    fn countTableDescriptorHomes(self: *const SemanticGraph) usize {
        var n: usize = 0;
        for (self.nodes.items, 0..) |_, i| {
            if (self.hasTableDescriptorFacts(@intCast(i))) n += 1;
        }
        return n;
    }

    fn countEnumDescriptorHomes(self: *const SemanticGraph) usize {
        var n: usize = 0;
        for (self.nodes.items, 0..) |_, i| {
            if (self.hasEnumDescriptorFacts(@intCast(i))) n += 1;
        }
        return n;
    }

    pub fn findTableShape(self: *const SemanticGraph, name: []const u8) ?*const Node {
        const entity = self.findUniqueByNameOfKind(name, .table_shape) orelse return null;
        return self.get(entity);
    }

    /// Exact table-shape entity by id — descriptor facts, not NodeKind tag.
    pub fn tableShapeEntity(self: *const SemanticGraph, record: id) ?*const Node {
        if (!self.hasTableDescriptorFacts(record)) return null;
        return self.get(record);
    }

    /// Exact enum-shape entity by id — descriptor facts, not NodeKind tag.
    pub fn enumShapeEntity(self: *const SemanticGraph, descriptor: id) ?*const Node {
        if (!self.hasEnumDescriptorFacts(descriptor)) return null;
        return self.get(descriptor);
    }

    pub fn nodeKindLabel(kind: NodeKind) []const u8 {
        return switch (kind) {
            .module => "module",
            .func => "func",
            .param => "param",
            .local => "local",
            .value => "value",
            .call => "call",
            .relation => "relation",
            .transform_app => "transform_app",
            .table_shape => "table_shape",
            .enum_shape => "enum_shape",
        };
    }

    pub fn edgeKindLabel(kind: EdgeKind) []const u8 {
        return switch (kind) {
            .contains => "contains",
            .binding => "binding",
            .member => "member",
            .descriptor_ref => "descriptor_ref",
            .capture => "capture",
            .projection => "projection",
            .descriptor => "descriptor",
            .provenance => "provenance",
        };
    }

    fn jsonEscapeAppend(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, s: []const u8) !void {
        for (s) |c| switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\x08' => try buf.appendSlice(alloc, "\\b"),
            '\x0c' => try buf.appendSlice(alloc, "\\f"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            else => {
                if (c < 0x20) {
                    const hex = "0123456789abcdef";
                    try buf.appendSlice(alloc, "\\u00");
                    try buf.append(alloc, hex[c >> 4]);
                    try buf.append(alloc, hex[c & 0x0f]);
                } else {
                    try buf.append(alloc, c);
                }
            },
        };
    }

    fn appendJsonInt(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: anytype) !void {
        var tmp: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
        try buf.appendSlice(alloc, s);
    }

    fn appendIdsJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        values: []const id,
    ) !void {
        try buf.append(alloc, '[');
        for (values, 0..) |value, i| {
            if (i > 0) try buf.append(alloc, ',');
            try appendJsonInt(buf, alloc, value);
        }
        try buf.append(alloc, ']');
    }

    fn appendDemandJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        demand: types.ReturnConsumption,
    ) !void {
        try buf.append(alloc, '"');
        try buf.appendSlice(alloc, switch (demand) {
            .unknown => "unknown",
            .discard => "discard",
            .single => "single",
            .multi => "multi",
        });
        try buf.append(alloc, '"');
    }

    /// PROJECT A `Card` SO A CONSUMER OUTSIDE THE COMPILER CAN READ IT.
    ///
    /// This replaced a writer that mapped BOTH `.none` and `.unknown` to Zig
    /// `null` and then OMITTED the key, which made the two answers the graph
    /// exists to distinguish — "this application has no effect" and "nobody has
    /// looked" — byte-identical in the export, and identical to a third thing
    /// besides: a schema that never had the field. Measured on the tree it was
    /// replaced from: 178 of 210 `examples/*.id` exported, 525 applications
    /// published, and the strings `effect`, `authority` and `witness` occurred
    /// ZERO times across all of them. The fact was written into a struct that
    /// no consumer could see, which is the same as not having been written.
    ///
    /// The encoding is one key per card, ALWAYS PRESENT, holding a tagged
    /// object. A consumer reads `.card`:
    ///
    ///     {"card":"unknown"}      nobody has looked — assume the worst
    ///     {"card":"none"}         KNOWN-ABSENT — the graph proved it
    ///     {"card":"one","id":N}   exactly this graph entity
    ///
    /// Always-present is the load-bearing half. An omitted key is indistinguish-
    /// able from an older compiler, a truncated write, or a consumer reading the
    /// wrong array — so a gate that treats "no key" as "no effect" is agreeing
    /// with an absence, and this tree already paid for that lesson once in
    /// `gate/negative.sh`, where a missing artifact read as a refusal. With the
    /// key always present, a missing key is a MALFORMED EXPORT and nothing else,
    /// and a gate can say so.
    ///
    /// `.one` carries its id in a named slot rather than overloading the key's
    /// JSON type. A consumer that wants the id checks `card == "one"` first, so
    /// it can never read a tag as a coordinate.
    fn appendCardJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        key: []const u8,
        card: Card,
    ) !void {
        try buf.appendSlice(alloc, ",\"");
        try buf.appendSlice(alloc, key);
        try buf.appendSlice(alloc, "\":{\"card\":\"");
        try buf.appendSlice(alloc, card.name());
        try buf.append(alloc, '"');
        switch (card) {
            .one => |n| {
                try buf.appendSlice(alloc, ",\"id\":");
                try appendJsonInt(buf, alloc, n);
            },
            .unknown, .none => {},
        }
        try buf.append(alloc, '}');
    }

    fn requireHome(self: *const SemanticGraph, entity: id) !id {
        return self.homeOf(entity) orelse error.InvalidTableShapeScope;
    }

    fn appendMultJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        mult: place.Mult,
    ) !void {
        switch (mult) {
            .unknown => try buf.appendSlice(alloc, "\"unknown\""),
            .exact => |n| {
                try buf.appendSlice(alloc, "{\"exact\":");
                try appendJsonInt(buf, alloc, n);
                try buf.append(alloc, '}');
            },
            .bounded => |n| {
                try buf.appendSlice(alloc, "{\"bounded\":");
                try appendJsonInt(buf, alloc, n);
                try buf.append(alloc, '}');
            },
        }
    }

    /// §18's census, PROJECTED — not a new fact.
    ///
    /// `place.Census` is produced on every lift and consumed by
    /// `dnir_lower.zig:5216`; until now no projection published it, so a graph
    /// reader could not see the one entity that carries a program point. That
    /// is why TEN structurally different programs normalised to ONE digest:
    /// every fact separating them lives on a place, and the dump printed none.
    ///
    /// NAMES ARE NOT PUBLISHED. A place's identity is its binding site
    /// (`place.zig` header) and its name is provenance, so a renamed binding
    /// must not move this digest — the same rule §8 states for spelling.
    fn appendPlacesJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        maybe: ?*const place.Census,
    ) !void {
        try buf.append(alloc, '[');
        const census = maybe orelse {
            try buf.appendSlice(alloc, "]");
            return;
        };
        for (census.places.items, 0..) |*p, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"place\":");
            try appendJsonInt(buf, alloc, p.id);
            try buf.appendSlice(alloc, ",\"shape\":\"");
            try buf.appendSlice(alloc, @tagName(p.shape));
            try buf.appendSlice(alloc, "\",\"region\":\"");
            try buf.appendSlice(alloc, @tagName(p.region));
            try buf.appendSlice(alloc, "\",\"determinacy\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.determinacy));
            try buf.appendSlice(alloc, "\",\"mutation\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.mutation));
            try buf.appendSlice(alloc, "\",\"escape\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.escape));
            try buf.appendSlice(alloc, "\",\"lifetime\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.lifetime));
            try buf.appendSlice(alloc, "\",\"residency\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.residency));
            try buf.appendSlice(alloc, "\",\"origin\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.origin));
            try buf.appendSlice(alloc, "\",\"extent\":");
            switch (p.facts.extent) {
                .unknown => try buf.appendSlice(alloc, "\"unknown\""),
                .exact => |n| {
                    try buf.appendSlice(alloc, "{\"exact\":");
                    try appendJsonInt(buf, alloc, n);
                    try buf.append(alloc, '}');
                },
                .bounded => |n| {
                    try buf.appendSlice(alloc, "{\"bounded\":");
                    try appendJsonInt(buf, alloc, n);
                    try buf.append(alloc, '}');
                },
            }
            try buf.appendSlice(alloc, ",\"accesses\":[");
            for (p.accesses.items, 0..) |a, ai| {
                if (ai > 0) try buf.append(alloc, ',');
                try buf.appendSlice(alloc, "{\"kind\":\"");
                try buf.appendSlice(alloc, @tagName(a.kind));
                try buf.appendSlice(alloc, "\",\"point\":");
                try appendJsonInt(buf, alloc, a.point);
                try buf.appendSlice(alloc, ",\"depth\":");
                try appendJsonInt(buf, alloc, a.depth);
                try buf.appendSlice(alloc, ",\"mult\":");
                try appendMultJson(buf, alloc, a.mult);
                try buf.appendSlice(alloc, ",\"const_index\":");
                try buf.appendSlice(alloc, if (a.const_index) "true" else "false");
                try buf.append(alloc, '}');
            }
            try buf.appendSlice(alloc, "]}");
        }
        try buf.appendSlice(alloc, "]");
    }

    fn appendBoundJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        key: []const u8,
        bound: region.Bound,
    ) !void {
        try buf.appendSlice(alloc, ",\"");
        try buf.appendSlice(alloc, key);
        try buf.appendSlice(alloc, "\":{\"end\":\"");
        try buf.appendSlice(alloc, bound.name());
        try buf.append(alloc, '"');
        switch (bound) {
            .unknown => {},
            .at => |v| {
                try buf.appendSlice(alloc, ",\"value\":");
                try appendJsonInt(buf, alloc, v);
            },
            .place, .under => |p| {
                try buf.appendSlice(alloc, ",\"place\":");
                try appendJsonInt(buf, alloc, p);
            },
        }
        try buf.append(alloc, '}');
    }

    fn appendSiteJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        key: []const u8,
        name: []const u8,
        one: ?u32,
    ) !void {
        try buf.appendSlice(alloc, ",\"");
        try buf.appendSlice(alloc, key);
        try buf.appendSlice(alloc, "\":{\"site\":\"");
        try buf.appendSlice(alloc, name);
        try buf.append(alloc, '"');
        if (one) |v| {
            try buf.appendSlice(alloc, ",\"id\":");
            try appendJsonInt(buf, alloc, v);
        }
        try buf.append(alloc, '}');
    }

    fn appendRegionsJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        census: *const region.Census,
    ) !void {
        try buf.append(alloc, '[');
        for (census.regions.items, 0..) |r, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"region\":");
            try appendJsonInt(buf, alloc, r.id);
            try buf.appendSlice(alloc, ",\"shape\":\"");
            try buf.appendSlice(alloc, @tagName(r.shape));
            try buf.appendSlice(alloc, "\",\"position\":");
            try appendJsonInt(buf, alloc, r.position);
            try appendSiteJson(buf, alloc, "parent", r.parent.name(), switch (r.parent) {
                .one => |v| v,
                else => null,
            });
            try appendSiteJson(buf, alloc, "target", r.target.name(), switch (r.target) {
                .one => |v| v,
                else => null,
            });
            try buf.appendSlice(alloc, ",\"departure\":\"");
            try buf.appendSlice(alloc, @tagName(r.departure));
            try buf.appendSlice(alloc, "\",\"results\":");
            try appendJsonInt(buf, alloc, r.results);
            try buf.appendSlice(alloc, ",\"refinement\":{");
            try buf.appendSlice(alloc, "\"subject\":{\"site\":\"");
            try buf.appendSlice(alloc, r.refinement.subject.name());
            try buf.append(alloc, '"');
            switch (r.refinement.subject) {
                .one => |v| {
                    try buf.appendSlice(alloc, ",\"place\":");
                    try appendJsonInt(buf, alloc, v);
                },
                else => {},
            }
            try buf.append(alloc, '}');
            try appendBoundJson(buf, alloc, "lower", r.refinement.lower);
            try appendBoundJson(buf, alloc, "upper", r.refinement.upper);
            try appendBoundJson(buf, alloc, "hole", r.refinement.hole);
            try buf.appendSlice(alloc, "},\"carried\":[");
            for (census.carriedOf(r), 0..) |p, ci| {
                if (ci > 0) try buf.append(alloc, ',');
                try appendJsonInt(buf, alloc, p);
            }
            try buf.appendSlice(alloc, "]}");
        }
        try buf.append(alloc, ']');
    }

    /// The two censuses of each relation, keyed by the exact relation entity.
    ///
    /// THIS IS THE SECTION THAT SEPARATES THE TEN PROGRAMS. Everything above it
    /// in this dump is module-level and identical across all ten.
    fn appendBodiesJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
    ) !void {
        try buf.appendSlice(alloc, ",\"bodies\":[");
        for (self.bodies.items, 0..) |*body, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"relation\":");
            try appendJsonInt(buf, alloc, body.relation);
            try buf.appendSlice(alloc, ",\"places\":");
            try appendPlacesJson(buf, alloc, &body.places);
            try buf.appendSlice(alloc, ",\"regions\":");
            try appendRegionsJson(buf, alloc, &body.regions);
            try buf.appendSlice(alloc, ",\"points\":");
            try appendJsonInt(buf, alloc, body.regions.points);
            try buf.append(alloc, '}');
        }
        try buf.append(alloc, ']');
    }

    fn appendWorldsJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
    ) !void {
        try buf.appendSlice(alloc, ",\"worlds\":[");
        for (self.worlds.items, 0..) |fact, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"world\":");
            try appendJsonInt(buf, alloc, fact.world);
            try buf.appendSlice(alloc, ",\"home\":\"");
            try buf.appendSlice(alloc, subject_home.homeName(fact.home));
            try buf.appendSlice(alloc, "\",\"reach\":\"");
            try buf.appendSlice(alloc, @tagName(fact.reach));
            try buf.appendSlice(alloc, "\",\"members\":");
            try appendIdsJson(buf, alloc, self.worldMembers(fact));
            try buf.append(alloc, '}');
        }
        try buf.appendSlice(alloc, "],\"draws\":[");
        for (self.draws.items, 0..) |draw, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"application\":");
            try appendJsonInt(buf, alloc, draw.application);
            try appendCardJson(buf, alloc, "world", draw.world);
            try buf.append(alloc, '}');
        }
        try buf.appendSlice(alloc, "],\"origins\":[");
        for (self.origins.items, 0..) |origin, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"value\":");
            try appendJsonInt(buf, alloc, origin.value);
            try buf.appendSlice(alloc, ",\"relation\":");
            try appendJsonInt(buf, alloc, origin.relation);
            try buf.appendSlice(alloc, ",\"place\":");
            try appendJsonInt(buf, alloc, origin.place);
            try buf.append(alloc, '}');
        }
        try buf.append(alloc, ']');
    }

    fn appendAggregateDescriptorJson(
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        descriptor: types.ResolvedType,
    ) !void {
        try buf.appendSlice(alloc, "{\"kind\":\"");
        try jsonEscapeAppend(buf, alloc, @tagName(descriptor));
        try buf.append(alloc, '"');
        switch (descriptor) {
            .array => |array| {
                try buf.appendSlice(alloc, ",\"extent\":");
                if (array.size) |extent|
                    try appendJsonInt(buf, alloc, extent)
                else
                    try buf.appendSlice(alloc, "null");
                try buf.appendSlice(alloc, ",\"element\":");
                try appendAggregateDescriptorJson(buf, alloc, array.elem.*);
            },
            .@"struct" => |record| {
                try buf.appendSlice(alloc, ",\"name\":\"");
                try jsonEscapeAppend(buf, alloc, record.name);
                try buf.append(alloc, '"');
            },
            .table_type => |record| {
                try buf.appendSlice(alloc, ",\"storage\":\"");
                try buf.appendSlice(alloc, @tagName(record.storage_class));
                try buf.appendSlice(alloc, "\",\"sealed\":");
                try buf.appendSlice(alloc, if (record.is_sealed) "true" else "false");
                try buf.appendSlice(alloc, ",\"fields\":[");
                for (record.fields, 0..) |field, i| {
                    if (i > 0) try buf.append(alloc, ',');
                    try buf.appendSlice(alloc, "{\"name\":\"");
                    try jsonEscapeAppend(buf, alloc, field.name);
                    try buf.appendSlice(alloc, "\",\"descriptor\":");
                    try appendAggregateDescriptorJson(buf, alloc, field.typ);
                    try buf.append(alloc, '}');
                }
                try buf.append(alloc, ']');
            },
            else => {},
        }
        try buf.append(alloc, '}');
    }

    fn appendAggregatesJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
    ) !void {
        try buf.appendSlice(alloc, ",\"aggregates\":[");
        for (self.aggregate_facts.items, 0..) |stored, i| {
            const fact = self.aggregate(stored.aggregate) orelse return error.InvalidAggregateFact;
            const descriptor = (self.get(fact.aggregate) orelse return error.InvalidAggregateFact).descriptor orelse
                return error.InvalidAggregateFact;
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"aggregate\":");
            try appendJsonInt(buf, alloc, fact.aggregate);
            try buf.appendSlice(alloc, ",\"members_pack\":");
            try appendJsonInt(buf, alloc, fact.members_pack);
            try buf.appendSlice(alloc, ",\"owner\":");
            try appendJsonInt(buf, alloc, fact.owner);
            try appendSiteJson(buf, alloc, "place", fact.place.name(), switch (fact.place) {
                .one => |site| site,
                else => null,
            });
            try buf.appendSlice(alloc, ",\"contents\":\"");
            try buf.appendSlice(alloc, @tagName(fact.contents_known));
            try buf.appendSlice(alloc, "\",\"descriptor\":");
            try appendAggregateDescriptorJson(buf, alloc, descriptor);
            try buf.appendSlice(alloc, ",\"members\":");
            try appendIdsJson(buf, alloc, self.aggregateMembers(fact.aggregate) orelse return error.InvalidAggregateFact);
            try buf.append(alloc, '}');
        }
        try buf.appendSlice(alloc, "],\"exact_i64\":[");
        for (self.exact_i64_facts.items, 0..) |fact, i| {
            if (self.exactI64(fact.value) == null) return error.InvalidExactValueFact;
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"value\":");
            try appendJsonInt(buf, alloc, fact.value);
            try buf.appendSlice(alloc, ",\"content\":");
            try appendJsonInt(buf, alloc, fact.content);
            try buf.append(alloc, '}');
        }
        try buf.append(alloc, ']');
    }

    fn appendMembersJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        home: id,
    ) !void {
        const members = try self.membersOf(home, alloc);
        defer alloc.free(members);
        try appendIdsJson(buf, alloc, members);
    }

    /// Write agent-facing JSON snapshot (table_shapes + enum_shapes + full node list).
    pub fn writeJson(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        file: []const u8,
        out: *std.ArrayListUnmanaged(u8),
        source_hash: ?u64,
    ) !void {
        // version 3: every `applications[]` row now carries all five Cards as
        // always-present tagged objects (`appendCardJson`). Version 2 omitted a
        // card whose answer was `.none` or `.unknown`, so a v2 reader pointed at
        // a v3 export sees keys it did not expect, and a v3 reader pointed at a
        // v2 export sees a MISSING card rather than silently reading absence as
        // agreement. The bump is what lets it tell those apart.
        //
        // version 4: `blocking_applications` and `fact_coverage`. Same argument
        // one level up — v3 published `unresolved_applications` and nothing that
        // said which of those entries the backend would actually refuse on, so a
        // reader had to guess, and the guess is wrong by 4:1 corpus-wide.
        //
        // version 5: `places`, `bodies`, `worlds`, `draws`, `origins`, and an
        // `applied` card on every application row. Same argument a third time,
        // and this one is the largest: v4 published NO fact that separated two
        // relation BODIES, so ten structurally different programs exported one
        // digest (`ebede795efad`) while the backend emitted ten objects. A
        // reader that cannot tell a recurrence from an early return cannot
        // adjudicate SOURCE-CONTROL-ONE §8 on any row, and a v4 reader pointed
        // at a v5 export must know that it is now being told.
        //
        // version 6: `aggregates` and `exact_i64`. Version 5 serialized neither
        // aggregate member identity nor exact scalar content, so a self-hosted
        // consumer could not reproduce the fact closure used by realization.
        try out.appendSlice(alloc, "{\"schema\":\"sim-v0\",\"version\":6,\"file\":\"");
        try jsonEscapeAppend(out, alloc, file);
        try out.append(alloc, '"');
        if (source_hash) |h| {
            try out.appendSlice(alloc, ",\"source_hash\":");
            try appendJsonInt(out, alloc, h);
        }
        try out.appendSlice(alloc, ",\"nodes\":[");
        for (self.nodes.items, 0..) |node, i| {
            const entity = std.math.cast(id, i) orelse
                return error.ApplicationFactCapacityExceeded;
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, i);
            try out.appendSlice(alloc, ",\"kind\":\"");
            try out.appendSlice(alloc, nodeKindLabel(node.kind));
            try out.appendSlice(alloc, "\"");
            if (node.name) |n| {
                try out.appendSlice(alloc, ",\"name\":\"");
                try jsonEscapeAppend(out, alloc, n);
                try out.append(alloc, '"');
            }
            if (self.hasTableDescriptorFacts(entity)) {
                try out.appendSlice(alloc, ",\"home\":");
                try appendJsonInt(out, alloc, try self.requireHome(entity));
                if (node.storage_class) |s| {
                    try out.appendSlice(alloc, ",\"storage_class\":\"");
                    try out.appendSlice(alloc, types.storageClassName(s));
                    try out.append(alloc, '"');
                }
                if (node.shape_id) |sid| {
                    try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                    try appendJsonInt(out, alloc, sid);
                }
                if (node.descriptor_state) |ds| {
                    try out.appendSlice(alloc, ",\"descriptor_state\":\"");
                    try out.appendSlice(alloc, State.name(ds));
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, ",\"fields\":");
                try self.appendMembersJson(out, alloc, entity);
            }
            if (self.isApplicationCandidate(entity)) {
                if (node.call_shape) |cs| {
                    try out.appendSlice(alloc, ",\"callee_kind\":\"");
                    try out.appendSlice(alloc, switch (cs.callee_kind) {
                        .direct => "direct",
                        .method => "method",
                        .indirect => "indirect",
                        .comptime_known => "comptime",
                    });
                    try out.appendSlice(alloc, "\",\"arg_count\":");
                    try appendJsonInt(out, alloc, cs.arg_count);
                    try out.appendSlice(alloc, ",\"specializable\":");
                    try out.appendSlice(alloc, if (cs.isSpecializable()) "true" else "false");
                }
                if (node.knowledge) |k| {
                    try out.appendSlice(alloc, ",\"knowledge\":\"");
                    try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                    try out.append(alloc, '"');
                }
                if (node.stage) |s| {
                    try out.appendSlice(alloc, ",\"stage\":\"");
                    try out.appendSlice(alloc, semantic_algebra.Stage.name(s));
                    try out.append(alloc, '"');
                }
            }
            if (node.kind == .transform_app) {
                if (node.name) |n| {
                    try out.appendSlice(alloc, ",\"transform\":\"");
                    try jsonEscapeAppend(out, alloc, n);
                    try out.append(alloc, '"');
                }
                if (node.knowledge) |k| {
                    try out.appendSlice(alloc, ",\"knowledge\":\"");
                    try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                    try out.append(alloc, '"');
                }
                if (node.stage) |s| {
                    try out.appendSlice(alloc, ",\"stage\":\"");
                    try out.appendSlice(alloc, semantic_algebra.Stage.name(s));
                    try out.append(alloc, '"');
                }
            }
            if (self.hasEnumDescriptorFacts(entity)) {
                if (node.shape_id) |sid| {
                    try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                    try appendJsonInt(out, alloc, sid);
                }
                try out.appendSlice(alloc, ",\"variants\":");
                try self.appendMembersJson(out, alloc, entity);
            }
            if (node.demand) |demand| {
                try out.appendSlice(alloc, ",\"demand\":\"");
                try out.appendSlice(alloc, switch (demand) {
                    .unknown => "unknown",
                    .discard => "discard",
                    .single => "single",
                    .multi => "multi",
                });
                try out.append(alloc, '"');
            }
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"edges\":[");
        for (self.edges.items, 0..) |edge, i| {
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"from\":");
            try appendJsonInt(out, alloc, edge.from);
            try out.appendSlice(alloc, ",\"to\":");
            try appendJsonInt(out, alloc, edge.to);
            try out.appendSlice(alloc, ",\"relation\":\"");
            try out.appendSlice(alloc, edgeKindLabel(edge.kind));
            try out.append(alloc, '"');
            if (edge.kind == .member or edge.kind == .projection) {
                try out.appendSlice(alloc, ",\"position\":");
                try appendJsonInt(out, alloc, edge.position);
            }
            if (edge.kind == .descriptor_ref and edge.inline_ref) {
                try out.appendSlice(alloc, ",\"inline_ref\":true");
            }
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"applications\":[");
        for (self.applications(), 0..) |stored, i| {
            const fact = self.application(stored.application) orelse return error.InvalidApplicationFact;
            const arguments = self.applicationArguments(fact.application) orelse
                return error.InvalidApplicationFact;
            const results = self.applicationResults(fact.application) orelse
                return error.InvalidApplicationFact;
            if (i > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"application\":");
            try appendJsonInt(out, alloc, fact.application);
            try out.appendSlice(alloc, ",\"relation\":");
            try appendJsonInt(out, alloc, self.applicationRelation(fact.application).?);
            try out.appendSlice(alloc, ",\"caller\":");
            try appendJsonInt(out, alloc, self.applicationCaller(fact.application).?);
            if (self.applicationSubject(fact.application)) |subject| {
                try out.appendSlice(alloc, ",\"subject\":");
                try appendJsonInt(out, alloc, subject);
            }
            try out.appendSlice(alloc, ",\"arguments\":");
            try appendIdsJson(out, alloc, arguments);
            try out.appendSlice(alloc, ",\"results\":");
            try appendIdsJson(out, alloc, results);
            try out.appendSlice(alloc, ",\"demand\":");
            try appendDemandJson(out, alloc, self.applicationDemand(fact.application).?);
            const span = self.applicationProvenance(fact.application).?;
            try out.appendSlice(alloc, ",\"provenance\":{\"file\":\"");
            try jsonEscapeAppend(out, alloc, span.file);
            try out.appendSlice(alloc, "\",\"start\":");
            try appendJsonInt(out, alloc, span.start);
            try out.appendSlice(alloc, ",\"end\":");
            try appendJsonInt(out, alloc, span.end);
            try out.append(alloc, '}');
            try appendCardJson(out, alloc, "applied", fact.applied);
            try appendCardJson(out, alloc, "effect", fact.effect);
            try appendCardJson(out, alloc, "authority", fact.authority);
            try appendCardJson(out, alloc, "witness", fact.witness);
            try appendCardJson(out, alloc, "target", fact.target);
            try appendCardJson(out, alloc, "realization", fact.realization);
            if (self.applicationStage(fact.application)) |st| {
                try out.appendSlice(alloc, ",\"stage\":\"");
                try out.appendSlice(alloc, semantic_algebra.Stage.name(st));
                try out.append(alloc, '"');
            }
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"unresolved_applications\":[");
        var first_unresolved = true;
        var candidates = self.application_candidates.iterator(.{});
        while (candidates.next()) |candidate| {
            if (candidate < self.application_presence.bit_length and
                self.application_presence.isSet(candidate)) continue;
            if (self.get(@intCast(candidate)) == null) return error.InvalidApplicationFact;
            if (!first_unresolved) try out.append(alloc, ',');
            first_unresolved = false;
            try appendJsonInt(out, alloc, candidate);
        }
        // THE ONE UNRESOLVED CANDIDATE THAT REFUSES THE MODULE, listed by id, and
        // the three-way census behind it. `unresolved_applications` above lumps
        // together a call the compiler lowers happily by spelling and a call that
        // stops it dead; those are different facts and a consumer that cannot
        // separate them cannot rank the gap. See `factCoverage`.
        try out.appendSlice(alloc, "],\"blocking_applications\":[");
        var first_blocking = true;
        var blocking_candidates = self.application_candidates.iterator(.{});
        while (blocking_candidates.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse return error.InvalidApplicationFact;
            if (self.get(entity) == null) return error.InvalidApplicationFact;
            if (self.application(entity) != null) continue;
            if (self.isBootstrapApplicationNode(entity)) continue;
            if (!first_blocking) try out.append(alloc, ',');
            first_blocking = false;
            try appendJsonInt(out, alloc, entity);
        }
        const coverage = self.factCoverage();
        try out.appendSlice(alloc, "],\"fact_coverage\":{\"candidates\":");
        try appendJsonInt(out, alloc, coverage.candidates);
        try out.appendSlice(alloc, ",\"published\":");
        try appendJsonInt(out, alloc, coverage.published);
        try out.appendSlice(alloc, ",\"bootstrap\":");
        try appendJsonInt(out, alloc, coverage.bootstrap);
        try out.appendSlice(alloc, ",\"blocking\":");
        try appendJsonInt(out, alloc, coverage.blocking);
        try out.append(alloc, '}');
        try out.appendSlice(alloc, ",\"places\":");
        try appendPlacesJson(out, alloc, if (self.places) |*c| c else null);
        try self.appendBodiesJson(out, alloc);
        try self.appendWorldsJson(out, alloc);
        try self.appendAggregatesJson(out, alloc);
        try out.appendSlice(alloc, ",\"table_shapes\":[");
        var first_table = true;
        for (self.nodes.items, 0..) |node, node_index| {
            const shape: id = @intCast(node_index);
            if (!self.hasTableDescriptorFacts(shape)) continue;
            if (!first_table) try out.append(alloc, ',');
            first_table = false;
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, node_index);
            try out.appendSlice(alloc, ",\"home\":");
            try appendJsonInt(out, alloc, try self.requireHome(shape));
            if (node.name) |n| {
                try out.appendSlice(alloc, ",\"name\":\"");
                try jsonEscapeAppend(out, alloc, n);
                try out.append(alloc, '"');
            }
            if (node.storage_class) |s| {
                try out.appendSlice(alloc, ",\"storage_class\":\"");
                try out.appendSlice(alloc, types.storageClassName(s));
                try out.append(alloc, '"');
            }
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                try appendJsonInt(out, alloc, sid);
            }
            if (node.knowledge) |k| {
                try out.appendSlice(alloc, ",\"knowledge\":\"");
                try out.appendSlice(alloc, semantic_algebra.KnowledgeLevel.name(k));
                try out.append(alloc, '"');
            }
            try out.appendSlice(alloc, ",\"fields\":");
            try self.appendMembersJson(out, alloc, shape);
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"enum_shapes\":[");
        var first_enum = true;
        for (self.nodes.items, 0..) |node, node_index| {
            const shape: id = @intCast(node_index);
            if (!self.hasEnumDescriptorFacts(shape)) continue;
            if (!first_enum) try out.append(alloc, ',');
            first_enum = false;
            try out.appendSlice(alloc, "{\"id\":");
            try appendJsonInt(out, alloc, node_index);
            try out.appendSlice(alloc, ",\"home\":");
            try appendJsonInt(out, alloc, try self.requireHome(shape));
            if (node.name) |n| {
                try out.appendSlice(alloc, ",\"name\":\"");
                try jsonEscapeAppend(out, alloc, n);
                try out.append(alloc, '"');
            }
            if (node.shape_id) |sid| {
                try out.appendSlice(alloc, ",\"shape_fingerprint\":");
                try appendJsonInt(out, alloc, sid);
            }
            try out.appendSlice(alloc, ",\"variants\":");
            try self.appendMembersJson(out, alloc, shape);
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "],\"call_shapes\":[");
        var first_call = true;
        var shapes = self.application_candidates.iterator(.{});
        while (shapes.next()) |candidate| {
            const entity = std.math.cast(id, candidate) orelse
                return error.ApplicationFactCapacityExceeded;
            const node = self.get(entity) orelse return error.InvalidApplicationFact;
            if (!first_call) try out.append(alloc, ',');
            first_call = false;
            try out.appendSlice(alloc, "{\"node\":");
            try appendJsonInt(out, alloc, entity);
            if (self.application(entity)) |fact| {
                try out.appendSlice(alloc, ",\"relation\":");
                try appendJsonInt(out, alloc, self.applicationRelation(fact.application).?);
            }
            if (node.call_shape) |cs| {
                try out.appendSlice(alloc, ",\"callee_kind\":\"");
                try out.appendSlice(alloc, switch (cs.callee_kind) {
                    .direct => "direct",
                    .method => "method",
                    .indirect => "indirect",
                    .comptime_known => "comptime",
                });
                try out.appendSlice(alloc, "\",\"arg_count\":");
                try appendJsonInt(out, alloc, cs.arg_count);
                try out.appendSlice(alloc, ",\"specializable\":");
                try out.appendSlice(alloc, if (cs.isSpecializable()) "true" else "false");
            }
            try out.appendSlice(alloc, ",\"line\":");
            try appendJsonInt(out, alloc, node.span.start);
            try out.appendSlice(alloc, ",\"col\":");
            try appendJsonInt(out, alloc, node.span.end);
            try out.append(alloc, '}');
        }
        try out.appendSlice(alloc, "]}");
    }

    /// Relative sidecar path: `.idol/graph/<stem>.json`.
    pub fn sidecarRelPath(src_path: []const u8, buf: []u8) []const u8 {
        const base = std.fs.path.basename(src_path);
        const ext = std.fs.path.extension(base);
        const stem = if (ext.len > 0 and ext.len <= base.len) base[0 .. base.len - ext.len] else base;
        return std.fmt.bufPrint(buf, ".idol/graph/{s}.json", .{stem}) catch ".idol/graph/module.json";
    }

    /// Persist graph JSON sidecar invalidated by source hash (Phase 1 A1).
    pub fn writeSidecar(
        self: *const SemanticGraph,
        alloc: std.mem.Allocator,
        io: std.Io,
        src_path: []const u8,
        source_hash: u64,
    ) !void {
        var json: std.ArrayListUnmanaged(u8) = .empty;
        defer json.deinit(alloc);
        try self.writeJson(alloc, src_path, &json, source_hash);
        var path_buf: [512]u8 = undefined;
        const rel = sidecarRelPath(src_path, &path_buf);
        if (std.fs.path.dirname(rel)) |dir| {
            if (!std.mem.eql(u8, dir, ".")) {
                const cwd = std.Io.Dir.cwd();
                try cwd.createDirPath(io, dir);
            }
        }
        const cwd = std.Io.Dir.cwd();
        try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = rel, .data = json.items });
    }

    /// Print a one-line graph summary to stderr when `DUO_GRAPH=1`.
    pub fn dumpSummary(self: *const SemanticGraph, io: std.Io, stderr: std.Io.File, file: []const u8) void {
        var buf: [512]u8 = undefined;
        var fw: std.Io.File.Writer = .init(stderr, io, &buf);
        fw.interface.print(
            "[duo graph] {s}: {d} nodes ({d} callable, {d} table, {d} enum, {d} call)\n",
            .{
                file,
                self.nodes.items.len,
                self.countCallableHomes(),
                self.countTableDescriptorHomes(),
                self.countEnumDescriptorHomes(),
                self.application_candidates.count(),
            },
        ) catch return;
        for (self.nodes.items, 0..) |node, i| {
            if (!self.hasTableDescriptorFacts(@intCast(i))) continue;
            fw.interface.print("  shape {d}", .{i}) catch return;
            if (node.storage_class) |s| {
                fw.interface.print(" {s}", .{types.storageClassName(s)}) catch return;
            }
            fw.interface.print("\n", .{}) catch return;
        }
        fw.interface.flush() catch {};
    }
};

fn addChildAllocationProbe(alloc: std.mem.Allocator) !void {
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const parent = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "allocation.id", .start = 0, .end = 0 },
    });
    const name = try alloc.dupe(u8, "child");
    const child = graph.addChild(parent, .{
        .kind = .value,
        .span = .{ .file = "allocation.id", .start = 1, .end = 1 },
        .name = name,
        .owns_name = true,
    }) catch |err| {
        try std.testing.expectEqual(@as(usize, 1), graph.nodes.items.len);
        try std.testing.expectEqual(@as(usize, 0), graph.edges.items.len);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 2), graph.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 1), graph.edges.items.len);
    try std.testing.expectEqual(parent, graph.edges.items[0].from);
    try std.testing.expectEqual(child, graph.edges.items[0].to);
}

fn orderFunctionComponentsAllocationProbe(alloc: std.mem.Allocator) !void {
    var unlocks = [_]std.ArrayListUnmanaged(usize){ .empty, .empty, .empty };
    defer for (&unlocks) |*list| list.deinit(alloc);
    try unlocks[0].append(alloc, 1);
    try unlocks[0].append(alloc, 2);
    try unlocks[1].append(alloc, 0);
    const functions = [_]id{ 10, 11, 12 };
    const ordered = try SemanticGraph.orderFunctionComponents(alloc, &functions, &unlocks);
    defer alloc.free(ordered);
    try std.testing.expectEqualSlices(id, &functions, ordered);
}

fn moduleFunctionEmitOrderAllocationProbe(
    alloc: std.mem.Allocator,
    graph: *const SemanticGraph,
    functions: []const id,
    expected: []const id,
) !void {
    const ordered = try graph.moduleFunctionEmitOrder(alloc, functions);
    defer alloc.free(ordered);
    try std.testing.expectEqualSlices(id, expected, ordered);
}

test "semantic_graph: child and scope relation publish transactionally" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        addChildAllocationProbe,
        .{},
    );
}

test "semantic_graph: liftModule creates func and param nodes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\function add(a, b)
        \\  return a + b
        \\end
    , "test.lua");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.liftModule(&module, "test.lua");
    try std.testing.expect(g.get(mod_id) != null);
    try std.testing.expectEqual(@as(usize, 4), g.nodes.items.len); // module + func + 2 params
    const add_id = g.resolveInHome(mod_id, "add", .func) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(.func, g.get(add_id).?.kind);
}

test "semantic_graph: function identities carry resolved result descriptors" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\measure(): f64
        \\    1.5
        \\label(): str
        \\    "ok"
        \\ready(): bool
        \\    true
    ;
    var lex = Lexer.init(src, "results.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModule(&module, "results.id");
    const measure = g.resolveInHome(home, "measure", .func) orelse return error.TestExpectedEqual;
    const label = g.resolveInHome(home, "label", .func) orelse return error.TestExpectedEqual;
    const ready = g.resolveInHome(home, "ready", .func) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(types.ResolvedType.f64, g.functionResultDescriptor(measure).?);
    try std.testing.expectEqual(types.ResolvedType.str, g.functionResultDescriptor(label).?);
    try std.testing.expectEqual(types.ResolvedType.bool, g.functionResultDescriptor(ready).?);
    try std.testing.expect(g.resolveInHome(home, "missing", .func) == null);
}

test "semantic_graph: tuple return descriptor publishes one semantic result pack" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\pair(n: i64, s: str): (i64, str)
        \\    return n, s
        \\main(): i64
        \\    a, b = pair(7, "ok")
        \\    a
    ;
    var lex = Lexer.init(src, "result-pack.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "result-pack.id");
    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const application_fact = graph.applications()[0];
    const results = graph.applicationResults(application_fact.application).?;
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqual(types.ResolvedType.i64, graph.get(results[0]).?.descriptor.?);
    try std.testing.expectEqual(types.ResolvedType.str, graph.get(results[1]).?.descriptor.?);
    try std.testing.expect(graph.applicationResult(application_fact.application) == null);
    try std.testing.expectEqualSlices(PackMemberDemand, &.{ .value, .value }, graph.packMemberDemands(application_fact.result_pack).?);
    const adjustment = graph.packAdjustment(application_fact.application).?;
    try std.testing.expectEqual(application_fact.result_pack, adjustment.source_pack);
    try std.testing.expectEqual(@as(?u32, 2), graph.pack(adjustment.target_pack).?.arity.fixedPrefix());
    try std.testing.expectEqual(@as(usize, 2), graph.packMembers(adjustment.target_pack).?.len);
}

test "semantic_graph: checked subject application retains relation and value identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\document: {
        \\    value: i64
        \\}
        \\read: i64 = (subject: document)
        \\    subject.value
        \\main: i64 = ()
        \\    document{ value = 42 }:read()
    ;
    var lex = Lexer.init(src, "application.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "application.id");

    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const fact = graph.applications()[0];
    const stored = graph.application(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("read", graph.get(graph.applicationRelation(stored.application).?).?.name.?);
    try std.testing.expectEqual(types.ResolvedType.i64, graph.applicationDescriptor(stored.application).?);
    try std.testing.expectEqual(types.ReturnConsumption.single, graph.applicationDemand(stored.application).?);
    try std.testing.expectEqual(@as(usize, 0), graph.applicationArguments(fact.application).?.len);
    const results = graph.applicationResults(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(results[0], graph.applicationResult(fact.application).?);
    const subject_id = graph.applicationSubject(stored.application) orelse return error.TestExpectedEqual;
    const subject = graph.get(subject_id) orelse return error.TestExpectedEqual;
    try std.testing.expect(subject.kind == .value);
    try std.testing.expect(subject.descriptor.? == .@"struct");
    try std.testing.expectEqualStrings("document", subject.descriptor.?.@"struct".name);
    try std.testing.expectEqual(types.ResolvedType.i64, graph.get(results[0]).?.descriptor.?);
    try std.testing.expectEqual(@as(u32, 7), graph.applicationProvenance(stored.application).?.start);
    // `read` is sealed and stateless, so its semantic applicator identity is
    // exact even though no provider object or dynamic dispatch survives.
    try std.testing.expect(stored.effect == .none);
    try std.testing.expect(stored.authority == .none);
    try std.testing.expect(stored.witness == .unknown);
    const relation = graph.applicationRelation(stored.application).?;
    try std.testing.expectEqual(Card{ .one = relation }, stored.applied);
    try std.testing.expectEqual(Card{ .one = relation }, stored.target);
    try std.testing.expect(stored.realization == .unknown);
    // The remaining unknowns are graph state. Do not reconstruct world from
    // "io" or a catalog.

    const unresolved_before = graph.unresolvedApplicationCount(null);
    const row = graph.application_rows.items[fact.application];
    graph.application_rows.items[fact.application] = std.math.maxInt(u32);
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.application_rows.items[fact.application] = row;

    graph.nodes.items[fact.application].demand = null;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[fact.application].demand = .single;

    graph.nodes.items[subject_id].kind = .local;
    graph.nodes.items[subject_id].scope = null;
    graph.nodes.items[results[0]].kind = .local;
    graph.nodes.items[results[0]].scope = null;
    try std.testing.expect(graph.application(fact.application) != null);
    try std.testing.expectEqual(unresolved_before, graph.unresolvedApplicationCount(null));

    const subject_descriptor = graph.nodes.items[subject_id].descriptor.?;
    graph.nodes.items[subject_id].descriptor = null;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[subject_id].descriptor = subject_descriptor;

    const result_descriptor = graph.nodes.items[results[0]].descriptor.?;
    graph.nodes.items[results[0]].descriptor = .i32;
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.nodes.items[results[0]].descriptor = result_descriptor;

    const result_pack_row = graph.pack_rows.get(fact.result_pack).?;
    const result_range = graph.pack_facts.items[result_pack_row].members;
    graph.pack_facts.items[result_pack_row].members.start = std.math.maxInt(u32);
    try std.testing.expect(graph.application(fact.application) == null);
    try std.testing.expectEqual(unresolved_before + 1, graph.unresolvedApplicationCount(null));
    graph.pack_facts.items[result_pack_row].members = result_range;

    // Transitional kinds and containment do not own application meaning. The
    // candidate column and packed roles retain the exact semantic identities.
    graph.nodes.items[fact.application].kind = .value;
    try std.testing.expect(graph.application(fact.application) != null);
    try std.testing.expect(graph.callShapeOf(fact.application) != null);
    var relation_users: std.ArrayListUnmanaged(id) = .empty;
    defer relation_users.deinit(alloc);
    try graph.usersOf(graph.applicationRelation(fact.application).?, &relation_users);
    try std.testing.expectEqualSlices(id, &.{fact.application}, relation_users.items);

    try std.testing.expect(graph.applicationRelation(fact.application) != null);
    try std.testing.expect(graph.applicationSubject(stored.application) != null);

    const projections = try graph.projectionsOf(fact.application, alloc);
    defer alloc.free(projections);
    try std.testing.expectEqual(@as(usize, 1), projections.len);
    try std.testing.expectEqualStrings("read", graph.get(projections[0]).?.name.?);

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "application.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    const projected = parsed.value.object.get("applications").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), projected.len);
    try std.testing.expectEqual(
        @as(i64, @intCast(subject_id)),
        projected[0].object.get("subject").?.integer,
    );
    try std.testing.expectEqualStrings("single", projected[0].object.get("demand").?.string);
    // THE CARDS ARE OBSERVABLE, AND `.none` IS NOT `.unknown`.
    //
    // This block used to assert `get("effect") == null` — it PINNED the defect.
    // Both known-absent and not-yet-known were written as an omitted key, so the
    // export could not answer the one question it is asked: whether the graph
    // proved this application does nothing, or never looked. `read` projects a
    // field of the subject it was handed, so effect and authority are
    // KNOWN-ABSENT. Applied and target are exact semantic identities even
    // though their physical provider and dispatch remain absent.
    try std.testing.expectEqualStrings(
        "none",
        projected[0].object.get("effect").?.object.get("card").?.string,
    );
    try std.testing.expectEqualStrings(
        "none",
        projected[0].object.get("authority").?.object.get("card").?.string,
    );
    try std.testing.expectEqualStrings(
        "unknown",
        projected[0].object.get("witness").?.object.get("card").?.string,
    );
    try std.testing.expectEqualStrings(
        "one",
        projected[0].object.get("applied").?.object.get("card").?.string,
    );
    try std.testing.expectEqual(
        @as(i64, @intCast(relation)),
        projected[0].object.get("applied").?.object.get("id").?.integer,
    );
    try std.testing.expectEqualStrings(
        "one",
        projected[0].object.get("target").?.object.get("card").?.string,
    );
    try std.testing.expectEqual(
        @as(i64, @intCast(relation)),
        projected[0].object.get("target").?.object.get("id").?.integer,
    );
    try std.testing.expectEqualStrings(
        "unknown",
        projected[0].object.get("realization").?.object.get("card").?.string,
    );
    // NEGATIVE CONTROL for the encoding itself: neither absent-ish card may
    // carry an id, or a consumer could read a tag as a coordinate.
    try std.testing.expect(projected[0].object.get("effect").?.object.get("id") == null);
    try std.testing.expect(projected[0].object.get("witness").?.object.get("id") == null);
    const witness_id = results[0];
    graph.application_facts.items[row].witness = .{ .one = witness_id };
    json.clearRetainingCapacity();
    try graph.writeJson(alloc, "application.id", &json, null);
    parsed.deinit();
    parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    const witnessed = parsed.value.object.get("applications").?.array.items;
    const witness_card = witnessed[0].object.get("witness").?.object;
    try std.testing.expectEqualStrings("one", witness_card.get("card").?.string);
    try std.testing.expectEqual(@as(i64, @intCast(witness_id)), witness_card.get("id").?.integer);
    // `.one` must not disturb its neighbours: effect stays known-absent.
    try std.testing.expectEqualStrings(
        "none",
        witnessed[0].object.get("effect").?.object.get("card").?.string,
    );
    try std.testing.expectEqual(witness_id, graph.application(fact.application).?.witness.one);
    graph.application_facts.items[row].witness = .unknown;
    const projected_shapes = parsed.value.object.get("call_shapes").?.array.items;
    try std.testing.expectEqual(graph.application_candidates.count(), projected_shapes.len);
    var matching_shapes: usize = 0;
    for (projected_shapes) |shape| {
        if (shape.object.get("node").?.integer != @as(i64, @intCast(fact.application))) continue;
        matching_shapes += 1;
        try std.testing.expectEqual(
            @as(i64, @intCast(graph.applicationRelation(fact.application).?)),
            shape.object.get("relation").?.integer,
        );
        try std.testing.expect(shape.object.get("method") == null);
    }
    try std.testing.expectEqual(@as(usize, 1), matching_shapes);
}

test "semantic_graph: nested positional access owns aggregate member and result packs" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pairs = {{10, 11}, {20, 21}, {30, 31}}
        \\pick: i64 = (i: i64)
        \\    pairs(i)(2)
        \\main: i64 = ()
        \\    pick(2)
    ;
    var lexer = Lexer.init(source, "aggregate-module.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    table_apply.normalizeModule(alloc, &module, &checked.type_map);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const home = try graph.liftModuleWithCheckedCalls(&module, &checked, "aggregate-module.id");
    const root = graph.aggregateNamedInScope(home, "pairs") orelse return error.TestExpectedEqual;
    const root_fact = graph.aggregate(root) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(place.Tri.yes, root_fact.contents_known);
    try std.testing.expect(root_fact.place == .one);
    const root_descriptor = graph.get(root).?.descriptor.?;
    try std.testing.expect(root_descriptor == .array);
    try std.testing.expectEqual(@as(?usize, 3), root_descriptor.array.size);
    try std.testing.expect(root_descriptor.array.elem.* == .array);
    try std.testing.expectEqual(@as(?usize, 2), root_descriptor.array.elem.array.size);
    try std.testing.expect(root_descriptor.array.elem.array.elem.* == .i64);
    const rows = graph.aggregateMembers(root) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    for (rows, 0..) |row, row_index| {
        const row_fact = graph.aggregate(row) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(root_fact.place, row_fact.place);
        const members = graph.aggregateMembers(row) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(@as(usize, 2), members.len);
        try std.testing.expectEqual(@as(i64, @intCast(row_index * 10 + 10)), graph.exactI64(members[0]).?);
        try std.testing.expectEqual(@as(i64, @intCast(row_index * 10 + 11)), graph.exactI64(members[1]).?);
    }

    var accesses: [2]id = undefined;
    var access_count: usize = 0;
    for (graph.applications()) |application| {
        if (graph.aggregateAccess(application.application) == null) continue;
        accesses[access_count] = application.application;
        access_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), access_count);
    const inner = graph.aggregateAccess(accesses[0]) orelse return error.TestExpectedEqual;
    const outer = graph.aggregateAccess(accesses[1]) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(root, graph.applicationSubject(inner.application).?);
    const projected = graph.applicationResults(inner.application).?[0];
    try std.testing.expectEqual(projected, graph.applicationSubject(outer.application).?);
    try std.testing.expectEqual(inner.application, graph.aggregateProducer(projected).?);
    try std.testing.expectEqual(place.Tri.unknown, graph.aggregate(projected).?.contents_known);
    try std.testing.expectEqual(@as(usize, 1), graph.applicationArguments(inner.application).?.len);
    try std.testing.expectEqual(@as(usize, 1), graph.applicationResults(inner.application).?.len);
    try std.testing.expectEqual(@as(usize, 1), graph.applicationArguments(outer.application).?.len);
    try std.testing.expectEqual(@as(usize, 1), graph.applicationResults(outer.application).?.len);
    try std.testing.expect(graph.get(graph.applicationResults(outer.application).?[0]).?.descriptor.? == .i64);

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "aggregate-module.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 6), parsed.value.object.get("version").?.integer);
    try std.testing.expectEqual(graph.aggregateCount(), parsed.value.object.get("aggregates").?.array.items.len);
    try std.testing.expectEqual(graph.exact_i64_facts.items.len, parsed.value.object.get("exact_i64").?.array.items.len);

    // The producer in this slice is positional arrays, but AggregateFact and
    // its interchange are not an array ontology. A record-valued application
    // result extends the same aggregate/member-pack row; only its access
    // realization remains for that later slice.
    const saved_root_descriptor = graph.nodes.items[root].descriptor;
    graph.nodes.items[root].descriptor = .{ .@"struct" = .{ .name = "rowset" } };
    try std.testing.expect(graph.aggregate(root) != null);
    var generic_json: std.ArrayListUnmanaged(u8) = .empty;
    defer generic_json.deinit(alloc);
    try graph.writeJson(alloc, "aggregate-module.id", &generic_json, null);
    var generic_parsed = try std.json.parseFromSlice(std.json.Value, alloc, generic_json.items, .{});
    defer generic_parsed.deinit();
    var serialized_record = false;
    for (generic_parsed.value.object.get("aggregates").?.array.items) |row| {
        if (row.object.get("aggregate").?.integer != @as(i64, root)) continue;
        const serialized = row.object.get("descriptor").?.object;
        try std.testing.expectEqualStrings("struct", serialized.get("kind").?.string);
        try std.testing.expectEqualStrings("rowset", serialized.get("name").?.string);
        serialized_record = true;
    }
    try std.testing.expect(serialized_record);
    graph.nodes.items[root].descriptor = saved_root_descriptor;

    // Damage controls: lowering-facing access validation consumes the exact
    // target, result pack range, and aggregate member descriptor. None may be
    // recovered from the nested source expression.
    const outer_row = graph.application_rows.items[outer.application];
    const saved_outer = graph.application_facts.items[outer_row];
    graph.application_facts.items[outer_row].target = .unknown;
    try std.testing.expect(graph.aggregateAccess(outer.application) == null);
    graph.application_facts.items[outer_row] = saved_outer;
    const pack_row = graph.pack_rows.get(outer.result_pack).?;
    const saved_range = graph.pack_facts.items[pack_row].members;
    graph.pack_facts.items[pack_row].members.start = std.math.maxInt(u32);
    try std.testing.expect(graph.aggregateAccess(outer.application) == null);
    graph.pack_facts.items[pack_row].members = saved_range;
    const saved_member_descriptor = graph.nodes.items[rows[0]].descriptor;
    graph.nodes.items[rows[0]].descriptor = .i64;
    try std.testing.expect(graph.aggregate(root) != null);
    try std.testing.expect(graph.aggregateAccess(inner.application) == null);
    graph.nodes.items[rows[0]].descriptor = saved_member_descriptor;
    try std.testing.expect(graph.aggregate(root) != null);
    try std.testing.expect(graph.aggregateAccess(inner.application) != null);
}

test "semantic_graph: local nested and module nested access share one fact family" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const sources = [_][]const u8{
        \\pairs = {{10, 11}, {20, 21}, {30, 31}}
        \\pick: i64 = (i: i64)
        \\    pairs(i)(2)
        ,
        \\pick: i64 = (i: i64)
        \\    pairs = {{10, 11}, {20, 21}, {30, 31}}
        \\    pairs(i)(2)
        ,
    };
    for (sources, 0..) |source, source_index| {
        var lexer = Lexer.init(source, if (source_index == 0) "module.id" else "local.id");
        var parser = Parser.init(&lexer, alloc);
        parser.idol_mode = true;
        var module = try parser.parse_module();
        var checked = sema.Sema.init(alloc);
        defer checked.deinit();
        checked.idol_mode = true;
        try checked.check_module(&module);
        table_apply.normalizeModule(alloc, &module, &checked.type_map);
        var graph = SemanticGraph.init(alloc);
        defer graph.deinit();
        _ = try graph.liftModuleWithCheckedCalls(&module, &checked, module.file);
        var accesses: usize = 0;
        for (graph.applications()) |application| {
            if (graph.aggregateAccess(application.application) != null) accesses += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), accesses);
    }

    // Independent flat control: the old flat mutable-capable physical family
    // remains separate until it has equivalent graph facts for writes.
    var lexer = Lexer.init(
        \\pick: i64 = (i: i64)
        \\    values = {10, 20, 30}
        \\    values(i)
    , "flat.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    table_apply.normalizeModule(alloc, &module, &checked.type_map);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "flat.id");
    var accesses: usize = 0;
    for (graph.applications()) |application| {
        if (graph.aggregateAccess(application.application) != null) accesses += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), accesses);
}

test "semantic_graph: if-condition application is published" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\w: bool = (code: str)
        \\    true
        \\go: i64 = ()
        \\    if w("x")
        \\        return 0
        \\    1
    ;
    var lex = Lexer.init(src, "examples/shc/char.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "examples/shc/char.id");

    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const fact = graph.applications()[0];
    const stored = graph.application(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("w", graph.get(graph.applicationRelation(stored.application).?).?.name.?);
    try std.testing.expectEqual(@as(usize, 1), graph.applicationArguments(fact.application).?.len);
}

test "semantic_graph: moduleFunctionEmitOrder callees before callers" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\helper: i64 = ()
        \\    1
        \\main: i64 = ()
        \\    helper()
    ;
    var lex = Lexer.init(src, "order.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleWithCheckedCalls(&module, &checked, "order.id");

    const main = g.resolveInHome(home, "main", .func) orelse return error.TestExpectedEqual;
    const helper = g.resolveInHome(home, "helper", .func) orelse return error.TestExpectedEqual;
    const functions = [_]id{ main, helper };
    const order = try g.moduleFunctionEmitOrder(alloc, &functions);
    defer alloc.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqual(helper, order[0]);
    try std.testing.expectEqual(main, order[1]);

    const idle = try g.addNode(.{
        .kind = .func,
        .span = .{ .file = "order.id", .start = 0, .end = 0 },
    });
    const independent = [_]id{ helper, idle };
    const unchanged = try g.moduleFunctionEmitOrder(alloc, &independent);
    defer alloc.free(unchanged);
    try std.testing.expectEqualSlices(id, &independent, unchanged);

    const duplicate = [_]id{ main, main };
    try std.testing.expectError(error.DuplicateFunctionEntity, g.moduleFunctionEmitOrder(alloc, &duplicate));
    const invalid = [_]id{std.math.maxInt(id)};
    try std.testing.expectError(error.InvalidFunctionEntity, g.moduleFunctionEmitOrder(alloc, &invalid));

    const unresolved = g.application_facts.items[0].application;
    g.nodes.items[unresolved].kind = .value;
    g.application_presence.unset(unresolved);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
    g.application_presence.set(unresolved);

    const application_row = g.application_rows.items[unresolved];
    g.application_rows.items[unresolved] = std.math.maxInt(u32);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
    g.application_rows.items[unresolved] = application_row;

    const result_pack_row = g.pack_rows.get(g.application_facts.items[0].result_pack).?;
    g.pack_facts.items[result_pack_row].members.len = std.math.maxInt(u32);
    try std.testing.expectError(error.UnresolvedApplication, g.moduleFunctionEmitOrder(alloc, &functions));
}

test "semantic_graph: moduleFunctionEmitOrder condenses recursive dependencies" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\a: i64 = ()
        \\    b()
        \\b: i64 = ()
        \\    a()
        \\c: i64 = ()
        \\    a()
    ;
    var lex = Lexer.init(src, "recursive.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleWithCheckedCalls(&module, &checked, "recursive.id");

    const a = g.resolveInHome(home, "a", .func) orelse return error.TestExpectedEqual;
    const b = g.resolveInHome(home, "b", .func) orelse return error.TestExpectedEqual;
    const c = g.resolveInHome(home, "c", .func) orelse return error.TestExpectedEqual;
    const functions = [_]id{ c, a, b };
    const order = try g.moduleFunctionEmitOrder(alloc, &functions);
    defer alloc.free(order);
    try std.testing.expectEqualSlices(id, &.{ a, b, c }, order);

    const recursive = [_]id{ b, a };
    const stable = try g.moduleFunctionEmitOrder(alloc, &recursive);
    defer alloc.free(stable);
    try std.testing.expectEqualSlices(id, &recursive, stable);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        moduleFunctionEmitOrderAllocationProbe,
        .{ &g, functions[0..], @as([]const id, &.{ a, b, c }) },
    );
}

test "semantic_graph: recursive function ordering releases temporary state" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        orderFunctionComponentsAllocationProbe,
        .{},
    );
}

test "semantic_graph: liftAliasShapes records shape without physical class" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Point = { x: f64, y: f64 }
        \\function main()
        \\end
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "test.id");
    const point_id = g.resolveInHome(home, "Point", .table_shape) orelse return error.TestExpectedEqual;
    const node = g.get(point_id).?;
    try std.testing.expectEqual(.table_shape, node.kind);
    try std.testing.expect(node.storage_class == null);
    // The field COUNT is now read off the published `.member` edges rather
    // than off a `field_count` scalar nothing consumed.
    const point_members = try g.membersOf(point_id, alloc);
    defer alloc.free(point_members);
    try std.testing.expectEqual(@as(usize, 2), point_members.len);
    try std.testing.expectEqual(semantic_algebra.KnowledgeLevel.observed, node.knowledge.?);
    try std.testing.expectEqual(@as(?State, .open_semantic), node.descriptor_state);
}

test "semantic_graph: findTableShape returns shape node" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const home = try g.addNode(.{ .kind = .module, .span = .{ .file = "t", .start = 0, .end = 0 } });
    const shape = try g.addChild(home, .{
        .kind = .table_shape,
        .span = .{ .file = "t", .start = 0, .end = 1 },
        .name = "Point",
        .storage_class = .native,
    });
    const node = g.get(shape).?;
    try std.testing.expectEqual(.native, node.storage_class.?);
    try std.testing.expectEqual(shape, g.resolveInHome(home, "Point", .table_shape).?);
    try std.testing.expect(g.findTableShape("Missing") == null);
}

test "semantic_graph: liftEnumShapes records enum variants" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\function main()
        \\end
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "test.id");
    const color = g.resolveInHome(home, "Color", .enum_shape) orelse return error.TestExpectedEqual;
    const node = g.get(color).?;
    try std.testing.expectEqual(.enum_shape, node.kind);
    const variants = try g.membersOf(color, alloc);
    defer alloc.free(variants);
    try std.testing.expectEqual(@as(usize, 3), variants.len);
}

test "semantic_graph: writeJson includes table_shapes and enum_shapes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Point = { x: f64, y: f64 }
        \\enum Color
        \\  Red
        \\  Green
        \\end
        \\function main()
        \\end
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "test.id");
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try g.writeJson(alloc, "test.id", &json, null);
    const s = json.items;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, s, .{});
    defer parsed.deinit();
    try std.testing.expect(std.mem.indexOf(u8, s, "\"table_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"enum_shapes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Color\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"Red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"storage_class\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"home\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"scope\":\"module\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"scope\":\"inline\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"shape_fingerprint\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"id_scope\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"table_shapes\":[{\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"enum_shapes\":[{\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"fields\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"generation\"") == null);
    const tables = parsed.value.object.get("table_shapes").?.array.items;
    try std.testing.expect(tables.len == 1);
    const fields = tables[0].object.get("fields").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expect(fields[0] == .integer);
    try std.testing.expect(fields[1] == .integer);
    const enums = parsed.value.object.get("enum_shapes").?.array.items;
    try std.testing.expect(enums.len == 1);
    const variants = enums[0].object.get("variants").?.array.items;
    try std.testing.expect(variants.len >= 2);
    try std.testing.expect(variants[0] == .integer);
}

test "semantic_graph: writeJson escapes every JSON control byte" {
    const alloc = std.testing.allocator;
    const file = "control\x00\x01\x08\x0c\x1f.id";
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);

    try graph.writeJson(alloc, file, &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(file, parsed.value.object.get("file").?.string);
}

test "semantic_graph: malformed table-shape scope refuses projection" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    _ = try graph.addNode(.{
        .kind = .table_shape,
        .descriptor_state = .sealed,
        .span = .{ .file = "malformed.id", .start = 1, .end = 1 },
        .name = "shape",
    });
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.InvalidTableShapeScope,
        graph.writeJson(std.testing.allocator, "malformed.id", &json, null),
    );
}

test "semantic_graph: equal projection metadata does not merge graph entities" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const node = Node{
        .kind = .value,
        .span = .{ .file = "same.id", .start = 1, .end = 1 },
        .name = "same",
    };
    const first = try graph.addNode(node);
    const second = try graph.addNode(node);
    try std.testing.expect(first != second);
    try std.testing.expectEqualStrings(graph.get(first).?.name.?, graph.get(second).?.name.?);
    try std.testing.expectEqual(graph.get(first).?.span.start, graph.get(second).?.span.start);
}

test "semantic_graph: textual projections refuse same-kind ambiguity" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "ambiguous.id", .start = 0, .end = 0 },
    });
    const first = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "ambiguous.id", .start = 1, .end = 1 },
        .name = "same",
    });
    const second = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "ambiguous.id", .start = 2, .end = 1 },
        .name = "same",
    });
    try std.testing.expect(first != second);
    try std.testing.expect(graph.findFunc("same") == null);
}

test "semantic_graph: packs preserve exact identity arity order and demand" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "packs.id", .start = 0, .end = 0 },
    });
    const first = try graph.addChild(module, .{
        .kind = .value,
        .span = .{ .file = "packs.id", .start = 1, .end = 1 },
        .descriptor = .i64,
    });
    const second = try graph.addChild(module, .{
        .kind = .value,
        .span = .{ .file = "packs.id", .start = 1, .end = 2 },
        .descriptor = .str,
    });
    const open_pack = try graph.addChild(module, .{
        .kind = .value,
        .span = .{ .file = "packs.id", .start = 1, .end = 3 },
    });
    const members = [_]PackMember{
        .{ .value = first, .demand = .value },
        .{ .value = second, .demand = .discard },
    };
    try graph.publishPack(open_pack, &members, .{ .open = 2 }, .none);
    try std.testing.expectEqualSlices(id, &.{ first, second }, graph.packMembers(open_pack).?);
    try std.testing.expectEqualSlices(PackMemberDemand, &.{ .value, .discard }, graph.packMemberDemands(open_pack).?);
    try std.testing.expectEqual(@as(?u32, 2), graph.pack(open_pack).?.arity.fixedPrefix());
    try std.testing.expectError(error.DemandedPackCannotDisappear, graph.selectPackRealization(open_pack, .none));

    const bad_pack = try graph.addChild(module, .{
        .kind = .value,
        .span = .{ .file = "packs.id", .start = 2, .end = 1 },
    });
    try std.testing.expectError(
        error.InvalidPackFact,
        graph.publishPack(bad_pack, &members, .{ .fixed = 1 }, .none),
    );
    try std.testing.expect(graph.pack(bad_pack) == null);

    const absent_pack = try graph.addChild(module, .{
        .kind = .value,
        .span = .{ .file = "packs.id", .start = 3, .end = 1 },
    });
    const discarded = [_]PackMember{
        .{ .value = first, .demand = .discard },
        .{ .value = second, .demand = .discard },
    };
    try graph.publishPack(absent_pack, &discarded, .{ .fixed = 2 }, .none);
    try graph.selectPackRealization(absent_pack, .none);
    try std.testing.expectEqual(PackRealization.none, graph.pack(absent_pack).?.realization);
}

test "semantic_graph: packed application facts reject duplicate and wrong roles" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "axes.id", .start = 0, .end = 0 },
    });
    const relation = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "axes.id", .start = 1, .end = 1 },
        .name = "apply",
        .result_descriptor = .i64,
    });
    const application = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(application);
    const subject = try graph.addChild(module, .{
        .kind = .param,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const argument = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const result = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 2, .end = 1 },
        .descriptor = .i64,
    });
    const arguments = [_]id{argument};
    const results = [_]id{result};
    try graph.publishApplication(
        application,
        relation,
        relation,
        relation,
        subject,
        &arguments,
        &results,
    );
    try std.testing.expectEqual(relation, graph.applicationRelation(application).?);
    try std.testing.expectEqual(relation, graph.applicationApplied(application).?);
    try std.testing.expectEqual(relation, graph.applicationTarget(application).?);
    try std.testing.expectEqual(subject, graph.applicationSubject(application).?);
    try std.testing.expectEqualSlices(id, &arguments, graph.applicationArguments(application).?);
    try std.testing.expectEqual(result, graph.applicationResult(application).?);
    const application_fact = graph.application(application).?;
    try std.testing.expect(application_fact.operand_pack != application_fact.result_pack);
    try std.testing.expectEqualSlices(PackMemberDemand, &.{.value}, graph.packMemberDemands(application_fact.operand_pack).?);
    try std.testing.expectEqualSlices(PackMemberDemand, &.{.unknown}, graph.packMemberDemands(application_fact.result_pack).?);
    try std.testing.expectEqual(Card.unknown, graph.packEffect(application_fact.result_pack));
    try std.testing.expectEqual(Card.unknown, graph.packWorld(application_fact.result_pack));
    try std.testing.expect(graph.application(@intCast(graph.nodes.items.len)) == null);

    graph.nodes.items[application].demand = null;
    try std.testing.expectError(
        error.InvalidApplicationFact,
        graph.publishApplication(
            application,
            relation,
            relation,
            relation,
            subject,
            &arguments,
            &results,
        ),
    );
    graph.nodes.items[application].demand = .unknown;

    try std.testing.expectError(
        error.DuplicateApplicationFact,
        graph.publishApplication(
            application,
            relation,
            relation,
            relation,
            subject,
            &arguments,
            &results,
        ),
    );

    const wrong = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 3, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(wrong);
    const wrong_result = try graph.addChild(wrong, .{
        .kind = .value,
        .span = .{ .file = "axes.id", .start = 3, .end = 1 },
        .descriptor = .i64,
    });
    const wrong_results = [_]id{wrong_result};
    try std.testing.expectError(
        error.InvalidApplicationRelation,
        graph.publishApplication(
            wrong,
            relation,
            result,
            relation,
            null,
            &.{},
            &wrong_results,
        ),
    );

    const incomplete = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i64,
        .demand = .unknown,
    });
    try graph.markApplicationCandidate(incomplete);
    const without_descriptor = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
    });
    const wrong_descriptor = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i32,
    });
    const complete_result = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "axes.id", .start = 4, .end = 1 },
        .descriptor = .i64,
    });
    const incomplete_arguments = [_]id{without_descriptor};
    const incomplete_results = [_]id{complete_result};
    try std.testing.expectError(
        error.InvalidApplicationSubject,
        graph.publishApplication(
            incomplete,
            relation,
            relation,
            relation,
            without_descriptor,
            &.{},
            &incomplete_results,
        ),
    );
    try std.testing.expectError(
        error.InvalidApplicationArgument,
        graph.publishApplication(
            incomplete,
            relation,
            relation,
            relation,
            null,
            &incomplete_arguments,
            &incomplete_results,
        ),
    );
    const mismatched_results = [_]id{wrong_descriptor};
    try std.testing.expectError(
        error.InvalidApplicationResult,
        graph.publishApplication(
            incomplete,
            relation,
            relation,
            relation,
            null,
            &.{},
            &mismatched_results,
        ),
    );
}

test "semantic_graph: applied relation and selected target remain distinct" {
    var graph = SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    const module = try graph.addNode(.{
        .kind = .module,
        .span = .{ .file = "roles.id", .start = 0, .end = 0 },
    });
    const relation = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "roles.id", .start = 1, .end = 1 },
        .result_descriptor = .i64,
    });
    const target = try graph.addChild(module, .{
        .kind = .func,
        .span = .{ .file = "roles.id", .start = 2, .end = 2 },
        .result_descriptor = .i64,
    });
    const applied = try graph.addChild(module, .{
        .kind = .local,
        .span = .{ .file = "roles.id", .start = 2, .end = 2 },
        .descriptor = .i64,
    });
    const application = try graph.addChild(relation, .{
        .kind = .call,
        .span = .{ .file = "roles.id", .start = 3, .end = 3 },
        .descriptor = .i64,
        .demand = .single,
    });
    try graph.markApplicationCandidate(application);
    const result = try graph.addChild(application, .{
        .kind = .value,
        .span = .{ .file = "roles.id", .start = 3, .end = 3 },
        .descriptor = .i64,
    });
    try graph.publishApplication(
        application,
        applied,
        relation,
        target,
        null,
        &.{},
        &.{result},
    );

    try std.testing.expectEqual(applied, graph.applicationApplied(application).?);
    try std.testing.expectEqual(relation, graph.applicationRelation(application).?);
    try std.testing.expectEqual(target, graph.applicationTarget(application).?);
    try std.testing.expect(applied != relation);
    try std.testing.expect(applied != target);
    try std.testing.expect(target != relation);

    const row = graph.application_rows.items[application];
    graph.application_facts.items[row].applied = .none;
    try std.testing.expect(graph.application(application) == null);
    graph.application_facts.items[row].applied = .{ .one = applied };
    graph.application_facts.items[row].target = .unknown;
    try std.testing.expect(graph.application(application) == null);
}

test "semantic_graph: checked occurrences keep distinct packed ranges" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\sum: i64 = (a: i64, b: i64)
        \\    a + b
        \\main: i64 = ()
        \\    sum(1, 2) + sum(3, 4)
    ;
    var lexer = Lexer.init(source, "ranges.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var probe = SemanticGraph.init(alloc);
    _ = try probe.liftModuleWithCalls(&module, "ranges.id");
    try std.testing.expect(probe.nodes.items.len < 64);
    const prefix = 64 - probe.nodes.items.len;
    probe.deinit();

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    for (0..prefix) |_| {
        _ = try graph.addNode(.{
            .kind = .value,
            .span = .{ .file = "ranges.id", .start = 0, .end = 0 },
        });
    }
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "ranges.id");

    const facts = graph.applications();
    try std.testing.expect(graph.nodes.items.len > 64);
    try std.testing.expectEqual(@as(usize, 2), facts.len);
    try std.testing.expect(facts[0].application != facts[1].application);
    try std.testing.expectEqual(
        graph.applicationRelation(facts[0].application).?,
        graph.applicationRelation(facts[1].application).?,
    );
    try std.testing.expect(facts[0].operand_pack != facts[1].operand_pack);
    try std.testing.expect(facts[0].result_pack != facts[1].result_pack);
    for (facts) |fact| {
        try std.testing.expectEqual(@as(usize, 2), graph.applicationArguments(fact.application).?.len);
        try std.testing.expectEqual(@as(usize, 1), graph.applicationResults(fact.application).?.len);
        try std.testing.expect(graph.application(fact.application) != null);
    }

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "ranges.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    const projected = parsed.value.object.get("applications").?.array.items;
    try std.testing.expectEqual(facts.len, projected.len);
    for (projected, facts) |value, fact| {
        const object = value.object;
        try std.testing.expectEqual(@as(i64, @intCast(fact.application)), object.get("application").?.integer);
        try std.testing.expectEqual(@as(i64, @intCast(graph.applicationRelation(fact.application).?)), object.get("relation").?.integer);
        try std.testing.expectEqual(@as(i64, @intCast(graph.applicationCaller(fact.application).?)), object.get("caller").?.integer);
        try std.testing.expect(object.get("subject") == null);
        try std.testing.expectEqual(types.ReturnConsumption.single, graph.applicationDemand(fact.application).?);
        try std.testing.expectEqualStrings("single", object.get("demand").?.string);
        try std.testing.expect(object.get("descriptor") == null);
        const provenance = object.get("provenance").?.object;
        try std.testing.expectEqualStrings("ranges.id", provenance.get("file").?.string);
        const span = graph.applicationProvenance(fact.application).?;
        try std.testing.expectEqual(@as(i64, span.start), provenance.get("start").?.integer);
        try std.testing.expectEqual(@as(i64, span.end), provenance.get("end").?.integer);

        const expected_arguments = graph.applicationArguments(fact.application).?;
        const projected_arguments = object.get("arguments").?.array.items;
        try std.testing.expectEqual(expected_arguments.len, projected_arguments.len);
        for (projected_arguments, expected_arguments) |argument, expected| {
            try std.testing.expectEqual(@as(i64, @intCast(expected)), argument.integer);
        }
        const expected_results = graph.applicationResults(fact.application).?;
        const projected_results = object.get("results").?.array.items;
        try std.testing.expectEqual(expected_results.len, projected_results.len);
        for (projected_results, expected_results) |result, expected| {
            try std.testing.expectEqual(@as(i64, @intCast(expected)), result.integer);
        }
    }

    const first_application = facts[0].application;
    const first_result = graph.applicationResults(first_application).?[0];
    var binding: ?usize = null;
    for (graph.edges.items, 0..) |edge, i| {
        if (edge.from == first_application and edge.kind == .binding) {
            binding = i;
            break;
        }
    }
    graph.edges.items[binding.?].to = first_result;
    try std.testing.expect(graph.application(first_application) == null);
}

test "semantic_graph: resident ids exhaust without a sentinel" {
    try std.testing.expectEqual(@as(id, 0), try SemanticGraph.coordinateForLength(0));
    try std.testing.expectEqual(
        std.math.maxInt(id),
        try SemanticGraph.coordinateForLength(std.math.maxInt(id)),
    );
    if (comptime @bitSizeOf(usize) > @bitSizeOf(id)) {
        try std.testing.expectError(
            error.GraphCoordinateExhausted,
            SemanticGraph.coordinateForLength(@as(usize, std.math.maxInt(id)) + 1),
        );
    }
}

test "semantic_graph: duplicate declaration provenance refuses" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\target: i64 = ()
        \\    0
    , "duplicate-declaration.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const parent = try graph.liftModule(&module, "duplicate-declaration.id");
    const declaration = &module.body.stmts[0].func_decl;
    try std.testing.expectEqual(
        @as(?id, 1),
        graph.findFuncDecl(declaration),
    );
    try std.testing.expectError(
        error.DuplicateSemanticDeclaration,
        graph.addChild(parent, .{
            .kind = .func,
            .span = .{ .file = "duplicate-declaration.id", .start = 1, .end = 1 },
            .name = "duplicate",
            .result_descriptor = .i64,
            .ast_ref = @ptrCast(@constCast(declaration)),
        }),
    );
}

test "semantic_graph: liftFunctionBindings creates inline table_shape" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\point: {
        \\    x: f64
        \\    y: f64
        \\}
        \\main: i64 = ()
        \\    p: point = { x = 1.0, y = 2.0 }
        \\    other: { x: f64, y: f64 } = { x = 3.0, y = 4.0 }
        \\    0
    , "binding.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleFull(&module, "binding.id");

    const shapes = try g.entitiesOfKind(.table_shape, alloc);
    defer alloc.free(shapes);
    var inline_shape: ?id = null;
    for (shapes) |shape| {
        const node = g.get(shape) orelse continue;
        const parent = g.get(node.scope orelse continue) orelse continue;
        if (parent.kind == .func) {
            inline_shape = shape;
            break;
        }
    }
    const found_id = inline_shape orelse return error.TestExpectedEqual;
    const found = g.get(found_id).?;
    try std.testing.expect(found.storage_class == null);
    const found_members = try g.membersOf(found_id, alloc);
    defer alloc.free(found_members);
    try std.testing.expectEqual(@as(usize, 2), found_members.len);
    try std.testing.expect(countTransformApps(&g, "shape.lift") >= 1);
}

fn countTransformApps(g: *const SemanticGraph, transform_name: []const u8) usize {
    var n: usize = 0;
    for (g.nodes.items) |node| {
        if (node.kind != .transform_app) continue;
        if (node.name) |nm| {
            if (std.mem.eql(u8, nm, transform_name)) n += 1;
        }
    }
    return n;
}

test "semantic_graph: native alias lift attaches shape transforms" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init("alias Point = { x: f64, y: f64 }", "test.id");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.addNode(.{ .kind = .module, .span = .{ .file = "t", .start = 0, .end = 0 }, .name = "t" });
    try g.liftAliasShapes(&module, "test.id", mod_id);
    try std.testing.expect(countTransformApps(&g, "shape.lift") >= 1);
    try std.testing.expectEqual(@as(usize, 0), countTransformApps(&g, "shape.specialize"));
    const point_id = g.resolveInHome(mod_id, "Point", .table_shape) orelse return error.TestExpectedEqual;
    const point = g.get(point_id).?;
    try std.testing.expectEqualStrings("Point", point.name.?);
}

test "semantic_graph: alias extension builds descriptor composition" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\alias Named = { name: str }
        \\alias Colored = Named
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "test.id");
    const named_id = g.resolveInHome(home, "Named", .table_shape) orelse return error.TestExpectedEqual;
    const colored_id = g.resolveInHome(home, "Colored", .table_shape) orelse return error.TestExpectedEqual;
    const refs = try g.descriptorRefsOf(colored_id, alloc);
    defer alloc.free(refs);
    try std.testing.expectEqual(@as(usize, 1), refs.len);
    try std.testing.expectEqual(named_id, refs[0].target);
}

test "semantic_graph: table shape_id stable across identical field sets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields_a = try alloc.alloc(types.FieldType, 2);
    fields_a[0] = .{ .name = "x", .typ = .f64 };
    fields_a[1] = .{ .name = "y", .typ = .f64 };
    const fields_b = try alloc.alloc(types.FieldType, 2);
    fields_b[0] = .{ .name = "x", .typ = .f64 };
    fields_b[1] = .{ .name = "y", .typ = .f64 };
    const rt_a: types.ResolvedType = .{ .table_type = .{ .fields = fields_a, .storage_class = .native } };
    const rt_b: types.ResolvedType = .{ .table_type = .{ .fields = fields_b, .storage_class = .native } };
    try std.testing.expectEqual(types.tableShapeIdentityHash(rt_a), types.tableShapeIdentityHash(rt_b));
}

test "semantic_graph: descriptor lifecycle facts need no parallel identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\PairA: { first: i32, second: str }
        \\PairB: { first: i32, second: str }
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "test.id");
    const pair_a = g.get(g.resolveInHome(home, "PairA", .table_shape) orelse return error.TestExpectedEqual).?;
    const pair_b = g.get(g.resolveInHome(home, "PairB", .table_shape) orelse return error.TestExpectedEqual).?;
    try std.testing.expect(pair_a.descriptor_state == .open_semantic);
    try std.testing.expect(pair_b.descriptor_state == .open_semantic);
}

test "semantic_graph: recursive descriptor facts remain graph-derived" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const module = try g.addNode(.{ .kind = .module, .span = .{ .file = "rec.id", .start = 0, .end = 0 } });
    const node_shape = try g.addChild(module, .{
        .kind = .table_shape,
        .span = .{ .file = "rec.id", .start = 1, .end = 1 },
        .name = "Node",
        .storage_class = .native,
    });

    const node: types.ResolvedType = .{ .@"struct" = .{ .name = "Node" } };
    const next = try alloc.create(types.ResolvedType);
    next.* = node;
    const fields = try alloc.alloc(types.FieldType, 2);
    fields[0] = .{ .name = "value", .typ = .i64 };
    fields[1] = .{ .name = "next", .typ = .{ .pointer = next } };
    const descriptor: types.ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .native,
        .is_sealed = true,
    } };

    try g.publishDescriptorRefEdges(node_shape, descriptor);
    const refs = try g.descriptorRefsOf(node_shape, alloc);
    defer alloc.free(refs);
    try std.testing.expectEqual(@as(usize, 1), refs.len);
    try std.testing.expectEqual(node_shape, refs[0].target);
    try std.testing.expect(!refs[0].inline_ref);

    // The `.descriptor_ref` EDGE is the fact, and it is keyed on the exact
    // graph id, not on the name — renaming the shape must not move it. (The
    // `Recursion`/`Completion` classification that used to be asserted here
    // was deleted: nothing outside this test ever read either answer.)
    g.nodes.items[node_shape].name = "Renamed";
    const after = try g.descriptorRefsOf(node_shape, alloc);
    defer alloc.free(after);
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expectEqual(node_shape, after[0].target);
}

test "semantic_graph: alias with derive keeps the shape identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\@derive(Display, Eq)
        \\type Vec2 = { x: f64, y: f64 }
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "test.id");
    const vec = g.get(g.resolveInHome(home, "Vec2", .table_shape) orelse return error.TestExpectedEqual).?;
    try std.testing.expectEqualStrings("Vec2", vec.name.?);
    try std.testing.expect(countTransformApps(&g, "shape.lift") >= 1);
}

test "semantic_graph: pipeline face normalizes to an iteration relation" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\fun double(x: i64): i64
        \\  x * 2
        \\end
        \\fun main()
        \\  x = 21 |> double
        \\end
    , "test.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const mod_id = try g.liftModuleWithCalls(&module, "test.id");
    _ = mod_id;
    try std.testing.expectEqual(@as(usize, 1), g.countKind(.relation));
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try g.writeJson(alloc, "test.id", &json, null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"kind\":\"relation\"") != null);
    // THE RELATION IDENTITY IS STATED ONCE, NOT TWICE. It used to be carried
    // BOTH as `Node.iteration_relation` on the relation node (exported as
    // `"relation":"map"`, read by nothing) and as the neighbouring
    // `transform_app`'s name from `semantic_algebra.iterationTransformId`. Two
    // carriers for one fact is the redundancy rule, so the scalar went and the
    // named transform stayed — which is also the carrier a consumer would
    // actually reach for, since it is the one the transform engine registers.
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"transform\":\"pipeline.map\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"kind\":\"pipeline\"") == null);
}

test "semantic_graph: usersOf finds binding edges" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const a = try g.addNode(.{ .kind = .local, .span = .{ .file = "t", .start = 0, .end = 1 }, .name = "a" });
    const b = try g.addNode(.{ .kind = .call, .span = .{ .file = "t", .start = 2, .end = 3 } });
    try g.addEdge(.{ .from = b, .to = a, .kind = .binding });
    try std.testing.expectError(error.DerivedContainsIndex, g.addEdge(.{
        .from = a,
        .to = b,
        .kind = .contains,
    }));
    var users: std.ArrayListUnmanaged(id) = .empty;
    defer users.deinit(g.alloc);
    try g.usersOf(a, &users);
    try std.testing.expectEqual(@as(usize, 1), users.items.len);
    try std.testing.expectEqual(b, users.items[0]);
}

test "semantic_graph: checked application publishes binding to relation and param" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\inner: i64 = (n: i64)
        \\    n
        \\outer: i64 = (n: i64)
        \\    inner(n)
    ;
    var lex = Lexer.init(src, "binding.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const module_id = try g.liftModuleWithCheckedCalls(&module, &checked, "binding.id");
    const functions = try g.functionsInModule(module_id, alloc);
    defer alloc.free(functions);
    try std.testing.expectEqual(@as(usize, 2), functions.len);
    const inner = functions[0];
    const outer = functions[1];
    var call_users: std.ArrayListUnmanaged(id) = .empty;
    defer call_users.deinit(alloc);
    try g.usersOf(inner, &call_users);
    try std.testing.expectEqual(@as(usize, 1), call_users.items.len);
    const occurrence = call_users.items[0];
    try std.testing.expectEqual(inner, g.applicationRelation(occurrence).?);
    try std.testing.expectEqual(outer, g.applicationCaller(occurrence).?);
    const arguments = g.applicationArguments(occurrence) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), arguments.len);
    var param: ?id = null;
    for (g.edges.items) |edge| {
        if (edge.from != outer or edge.kind != .contains) continue;
        const node = g.get(edge.to) orelse continue;
        if (node.kind == .param) param = edge.to;
    }
    const param_id = param orelse return error.TestExpectedEqual;
    var param_users: std.ArrayListUnmanaged(id) = .empty;
    defer param_users.deinit(alloc);
    try g.usersOf(param_id, &param_users);
    try std.testing.expectEqual(@as(usize, 1), param_users.items.len);
    try std.testing.expectEqual(arguments[0], param_users.items[0]);
}

test "semantic_graph: identity lookup survives a param that shadows a function name" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\scale: i64 = (n: i64)
        \\    n * 2
        \\n: i64 = ()
        \\    7
    ;
    var lex = Lexer.init(src, "shadow.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModule(&module, "shadow.id");

    try std.testing.expect(g.findByName("n") == null);

    const exact = g.resolveInHome(home, "n", .func) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(NodeKind.func, g.get(exact).?.kind);
}

test "semantic_graph: same-named params in different functions get distinct ids" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\first: i64 = (v: i64)
        \\    v + 1
        \\second: i64 = (v: i64)
        \\    v + 2
    ;
    var lex = Lexer.init(src, "params.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModule(&module, "params.id");

    var identities: [2]id = undefined;
    var count: usize = 0;
    for (g.nodes.items, 0..) |node, i| {
        if (node.kind != .param) continue;
        const name = node.name orelse continue;
        if (!std.mem.eql(u8, name, "v")) continue;
        identities[count] = @intCast(i);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expect(identities[0] != identities[1]);
    try std.testing.expect(g.get(identities[0]).?.scope.? != g.get(identities[1]).?.scope.?);
}

test "semantic_graph: four calls to one callee in one body are four identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\double: i64 = (x: i64)
        \\    x * 2
        \\run: i64 = (a: i64)
        \\    double(a) + double(a) + double(a) + double(a)
    ;
    var lex = Lexer.init(src, "calls.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&module, "calls.id");

    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(alloc);
    var calls: usize = 0;
    var candidates = g.application_candidates.iterator(.{});
    while (candidates.next()) |candidate| {
        const entity = std.math.cast(id, candidate) orelse
            return error.ApplicationFactCapacityExceeded;
        calls += 1;
        try seen.put(alloc, entity, {});
    }
    // Positive control on the count: a zero here would make the identity
    // assertion below vacuously true.
    try std.testing.expectEqual(@as(usize, 4), calls);
    try std.testing.expectEqual(@as(usize, 4), seen.count());
}

test "semantic_graph: fact coverage separates a bootstrap face from a blocking one" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THREE CANDIDATES, ONE OF EACH KIND, IN ONE BODY — because a census that
    // cannot tell them apart is the defect this projection exists to fix, and
    // three separate one-column fixtures would each pass against a reader that
    // collapses two of the columns into one.
    //
    //   helper()   PUBLISHED  — a module relation sema identified.
    //   s:len()    BOOTSTRAP  — no fact, but `native_bootstrap` lowers it by
    //                           spelling, so the module still compiles.
    //   f()        BLOCKING   — `f` is a LOCAL binding, so `callable_defs` (a
    //                           module-level map) never sees it and no fact is
    //                           recorded. Nothing lowers it either. This is the
    //                           shape that refuses the module.
    const src =
        \\helper: i64 = ()
        \\    1
        \\entry: i64 = (s: str)
        \\    f = () 2
        \\    helper() + s:len() + f()
    ;
    var lex = Lexer.init(src, "coverage.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "coverage.id");

    const coverage = g.factCoverage();
    // POSITIVE CONTROL FIRST. Every assertion below is vacuous at zero, and a
    // lift that stopped marking candidates would satisfy the partition.
    try std.testing.expectEqual(@as(usize, 3), coverage.candidates);
    try std.testing.expectEqual(@as(usize, 1), coverage.published);
    try std.testing.expectEqual(@as(usize, 1), coverage.bootstrap);
    try std.testing.expectEqual(@as(usize, 1), coverage.blocking);

    // THE PARTITION. `candidates` is exactly the three columns and nothing
    // falls outside them.
    try std.testing.expectEqual(
        coverage.candidates,
        coverage.published + coverage.bootstrap + coverage.blocking,
    );
    try std.testing.expectEqual(coverage.bootstrap + coverage.blocking, coverage.unresolved());

    // AND THE MIDDLE COLUMN IS NOT THE RIGHT ONE. The backend refuses on
    // `firstUnresolvedApplicationExcludingBootstrap`, so `blocking` must agree
    // with it exactly — one number, two readers, and this is the seam where
    // they could drift.
    try std.testing.expect(g.firstUnresolvedApplicationExcludingBootstrap(null) != null);
    try std.testing.expectEqual(
        coverage.blocking,
        g.unresolvedApplicationCountExcludingBootstrap(null),
    );
    // The count that does NOT exclude bootstrap is strictly larger here, which
    // is the whole point: reading it as the refusal set overstates by one.
    try std.testing.expectEqual(coverage.unresolved(), g.unresolvedApplicationCount(null));
    try std.testing.expect(g.unresolvedApplicationCount(null) > coverage.blocking);
}

/// Lift `src` the way the native path lifts it — sema first, then checked
/// calls — and report the effect the pass published for the single application
/// named by `caller`.
fn liftedEffectOf(
    alloc: std.mem.Allocator,
    g: *SemanticGraph,
    src: []const u8,
    caller: []const u8,
) !Card {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var lex = Lexer.init(src, "effect.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    const module = try g.liftModuleWithCheckedCalls(&mod, &checked, "effect.id");
    const home = g.resolveInHome(module, caller, .func) orelse return error.TestExpectedEqual;
    const published = g.applicationsIn(home);
    if (published.len == 0) return error.TestExpectedEqual;
    const fact = g.application(published[0]) orelse return error.TestExpectedEqual;
    return fact.effect;
}

test "semantic_graph: effect and authority are published, not left empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A leaf that applies nothing. The purest case, and the seed the whole
    // fixpoint grows from.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        try std.testing.expect(.none == try liftedEffectOf(alloc, &g,
            \\helper: i64 = ()
            \\    1
            \\entry: i64 = ()
            \\    helper()
        , "entry"));
    }

    // Transitive: `entry` applies `middle` applies `leaf`. Every link has to be
    // established before `entry`'s application is known-absent, which is what
    // makes this a fixpoint rather than a one-level check.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        try std.testing.expect(.none == try liftedEffectOf(alloc, &g,
            \\leaf: i64 = (n: i64)
            \\    n + 1
            \\middle: i64 = (n: i64)
            \\    leaf(n) * 2
            \\entry: i64 = ()
            \\    middle(3)
        , "entry"));
    }

    // An unresolved candidate in the callee's body. MEASURED: `print("hi")`
    // lifts as a `.call` node that never publishes an application, so a rule
    // that only consulted published applications would call this body empty and
    // therefore pure. It is not.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        const observed = liftedEffectOf(alloc, &g,
            \\noisy: i64 = ()
            \\    print("hi")
            \\    1
            \\entry: i64 = ()
            \\    noisy()
        , "entry") catch |err| switch (err) {
            error.TestExpectedEqual => Card.unknown,
            else => return err,
        };
        try std.testing.expect(observed == .unknown);
    }

    // A foreign declaration. Its body is a placeholder and the graph records
    // nothing about the symbol it binds, so the declaration is the only place
    // this can be known.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        try std.testing.expect(.unknown == try liftedEffectOf(alloc, &g,
            \\@ffi("llabs")
            \\absval: i64 = (n: i64)
            \\    0
            \\entry: i64 = ()
            \\    absval(5)
        , "entry"));
    }

    // RECURSION IS NO LONGER A MISS. This block asserted `.unknown` and
    // recorded the forward-on-goodness fixpoint's inability to close a cycle.
    // MEASURED cost of that miss on `native.id`: with every blocking condition
    // satisfied and NOTHING blocked, 47 of 92 relations still read `.unknown`
    // because the recursive-descent core is mutually recursive — `run` and
    // `main` among them. The fixpoint now runs on BADNESS, which is still least
    // and still seeded by the same blocking evidence.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        try std.testing.expect(.none == try liftedEffectOf(alloc, &g,
            \\down: i64 = (n: i64)
            \\    if n <= 0
            \\        0
            \\    else
            \\        down(n - 1)
            \\entry: i64 = ()
            \\    down(3)
        , "entry"));
    }

    // …AND THE HALF THAT MAKES THE PROMOTION ABOVE A FACT RATHER THAN OPTIMISM:
    // one observable member and the whole cycle stays unknown. If this ever
    // reads `.none`, the fixpoint has become the greatest one.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        const observed = liftedEffectOf(alloc, &g,
            \\down: i64 = (n: i64)
            \\    if n <= 0
            \\        0
            \\    else
            \\        up(n - 1)
            \\up: i64 = (n: i64)
            \\    print("x")
            \\    down(n - 1)
            \\entry: i64 = ()
            \\    down(3)
        , "entry") catch |err| switch (err) {
            error.TestExpectedEqual => Card.unknown,
            else => return err,
        };
        try std.testing.expect(observed == .unknown);
    }

    // THE STRING READER FACES. `s:len()` and `s:byte(i)` are unresolved
    // candidates forever (they lower through bootstrap rules), and blocking on
    // them cost `native.id` 60 of its 92 relations. Admitted by name and arity,
    // as a closed list.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        try std.testing.expect(.none == try liftedEffectOf(alloc, &g,
            \\size: i64 = (s: str)
            \\    s:len() + s:byte(1)
            \\entry: i64 = ()
            \\    size("abc")
        , "entry"));
    }

    // …and a face in the SAME bootstrap set that reaches the world is not
    // admitted. The bootstrap set is not a purity predicate.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        const observed = liftedEffectOf(alloc, &g,
            \\emit: i64 = (s: str)
            \\    stdout:write(s)
            \\    1
            \\entry: i64 = ()
            \\    emit("abc")
        , "entry") catch |err| switch (err) {
            error.TestExpectedEqual => Card.unknown,
            else => return err,
        };
        try std.testing.expect(observed == .unknown);
    }
}

test "semantic_graph: same-named locals in sibling blocks are distinct identities" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const module = try g.addNode(.{ .kind = .module, .span = .{ .file = "locals.id", .start = 0, .end = 0 } });
    const function = try g.addChild(module, .{ .kind = .func, .span = .{ .file = "locals.id", .start = 1, .end = 1 }, .name = "pick" });
    const first = try g.addChild(function, .{ .kind = .local, .span = .{ .file = "locals.id", .start = 2, .end = 2 }, .name = "value" });
    const second = try g.addChild(function, .{ .kind = .local, .span = .{ .file = "locals.id", .start = 2, .end = 2 }, .name = "value" });
    try std.testing.expect(first != second);
    try std.testing.expectEqual(g.get(first).?.scope, g.get(second).?.scope);
}

test "semantic_graph: same-named descriptors resolve in the home contains chain" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: { x: f64, y: f64 }
        \\use: i64 = ()
        \\    p: Point = { x = 1.0, y = 2.0 }
        \\    0
    ;
    var lex_a = Lexer.init(src, "a.id");
    var parser_a = Parser.init(&lex_a, alloc);
    parser_a.idol_mode = true;
    const module_a = try parser_a.parse_module();
    var lex_b = Lexer.init(src, "b.id");
    var parser_b = Parser.init(&lex_b, alloc);
    parser_b.idol_mode = true;
    const module_b = try parser_b.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const first = try g.liftModuleFull(&module_a, "a.id");
    const second = try g.liftModuleFull(&module_b, "b.id");
    try std.testing.expect(g.findTableShape("Point") == null);

    var point_a: ?id = null;
    var point_b: ?id = null;
    var use_a: ?id = null;
    var use_b: ?id = null;
    for (g.edges.items) |edge| {
        if (edge.kind != .contains) continue;
        const node = g.get(edge.to) orelse continue;
        const name = node.name orelse continue;
        if (edge.from == first and node.kind == .table_shape and std.mem.eql(u8, name, "Point")) point_a = edge.to;
        if (edge.from == second and node.kind == .table_shape and std.mem.eql(u8, name, "Point")) point_b = edge.to;
        if (edge.from == first and node.kind == .func and std.mem.eql(u8, name, "use")) use_a = edge.to;
        if (edge.from == second and node.kind == .func and std.mem.eql(u8, name, "use")) use_b = edge.to;
    }
    try std.testing.expect(point_a.? != point_b.?);

    var local_a: ?id = null;
    var local_b: ?id = null;
    for (g.edges.items) |edge| {
        if (edge.kind != .contains) continue;
        const node = g.get(edge.to) orelse continue;
        const name = node.name orelse continue;
        if (edge.from == use_a.? and node.kind == .local and std.mem.eql(u8, name, "p")) local_a = edge.to;
        if (edge.from == use_b.? and node.kind == .local and std.mem.eql(u8, name, "p")) local_b = edge.to;
    }

    var desc_a: ?id = null;
    var desc_b: ?id = null;
    for (g.edges.items) |edge| {
        if (edge.kind != .descriptor) continue;
        if (edge.from == local_a.?) desc_a = edge.to;
        if (edge.from == local_b.?) desc_b = edge.to;
    }
    try std.testing.expectEqual(point_a.?, desc_a.?);
    try std.testing.expectEqual(point_b.?, desc_b.?);
}

test "semantic_graph: capture edges publish exact binding ids; home is scope" {
    var g = SemanticGraph.init(std.testing.allocator);
    defer g.deinit();
    const module = try g.addNode(.{ .kind = .module, .span = .{ .file = "cap.id", .start = 0, .end = 0 } });
    const outer = try g.addChild(module, .{ .kind = .func, .span = .{ .file = "cap.id", .start = 1, .end = 1 }, .name = "outer" });
    const inner = try g.addChild(outer, .{ .kind = .func, .span = .{ .file = "cap.id", .start = 2, .end = 2 }, .name = "inner" });
    const binding = try g.addChild(outer, .{ .kind = .local, .span = .{ .file = "cap.id", .start = 3, .end = 3 }, .name = "x" });
    try g.addEdge(.{ .from = inner, .to = binding, .kind = .capture });

    try std.testing.expectEqual(module, g.homeOf(outer).?);
    try std.testing.expectEqual(outer, g.homeOf(inner).?);
    try std.testing.expectEqual(g.get(outer).?.scope, g.homeOf(outer));
    try std.testing.expectEqual(g.get(inner).?.scope, g.homeOf(inner));

    var captures: usize = 0;
    var captured: ?id = null;
    for (g.edges.items) |edge| {
        if (edge.from != inner or edge.kind != .capture) continue;
        captures += 1;
        captured = edge.to;
    }
    try std.testing.expectEqual(@as(usize, 1), captures);
    try std.testing.expectEqual(binding, captured.?);
    try std.testing.expect(g.get(@intCast(g.nodes.items.len)) == null);
}

test "semantic_graph: same-named functions resolve in the home contains chain" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src_a =
        \\measure(): f64
        \\    1.5
    ;
    const src_b =
        \\measure(): str
        \\    "ok"
    ;
    var lex_a = Lexer.init(src_a, "a.id");
    var parser_a = Parser.init(&lex_a, alloc);
    parser_a.idol_mode = true;
    const module_a = try parser_a.parse_module();
    var lex_b = Lexer.init(src_b, "b.id");
    var parser_b = Parser.init(&lex_b, alloc);
    parser_b.idol_mode = true;
    const module_b = try parser_b.parse_module();

    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const first = try g.liftModule(&module_a, "a.id");
    const second = try g.liftModule(&module_b, "b.id");
    try std.testing.expect(g.findFunc("measure") == null);

    const measure_a = g.resolveInHome(first, "measure", .func) orelse return error.TestExpectedEqual;
    const measure_b = g.resolveInHome(second, "measure", .func) orelse return error.TestExpectedEqual;
    try std.testing.expect(measure_a != measure_b);
    try std.testing.expectEqual(types.ResolvedType.f64, g.functionResultDescriptor(measure_a).?);
    try std.testing.expectEqual(types.ResolvedType.str, g.functionResultDescriptor(measure_b).?);
    try std.testing.expectEqual(measure_a, g.resolveInHome(measure_a, "measure", .func).?);
}

test "semantic_graph: table shape members are exact field identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\Point: { x: f64, y: f64 }
    , "members.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const home = try g.liftModuleFull(&module, "members.id");
    const point_id = g.resolveInHome(home, "Point", .table_shape) orelse return error.TestExpectedEqual;
    const members = try g.membersOf(point_id, alloc);
    defer alloc.free(members);
    try std.testing.expectEqual(@as(usize, 2), members.len);
    try std.testing.expectEqual(.value, g.get(members[0]).?.kind);
    try std.testing.expectEqual(.value, g.get(members[1]).?.kind);
    try std.testing.expectEqualStrings("x", g.get(members[0]).?.name.?);
    try std.testing.expectEqualStrings("y", g.get(members[1]).?.name.?);
}

test "semantic_graph: gate transport census clears bootstrap-only unresolved applications" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\cap: str = (cmd: str)
        \\    gatecap(cmd)
        \\envor: str = (name: str, fallback: str)
        \\    v = os.env(name)
        \\    if !v or v:len() == 0
        \\        fallback
        \\    else
        \\        v
        \\main: i64 = ()
        \\    out = cap("echo 1")
        \\    n = out:sub(1, out:len()):to(i64)
        \\    print("census/language: PASS {n}")
        \\    envor("CENSUS_FLOOR", "0"):to(i64)
    ;
    var lex = Lexer.init(src, "scripts/census/language.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "scripts/census/language.id");
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
}

test "semantic_graph: continuity requires a witnessed cross-incarnation fact" {
    var before = SemanticGraph.init(std.testing.allocator);
    defer before.deinit();
    const old = try before.addNode(.{
        .kind = .func,
        .span = .{ .file = "old/place.id", .start = 1, .end = 1 },
        .name = "parse",
    });

    var after = SemanticGraph.init(std.testing.allocator);
    defer after.deinit();
    const current = try after.addNode(.{
        .kind = .func,
        .span = .{ .file = "moved/place.id", .start = 9, .end = 9 },
        .name = "parse",
    });
    const witness = try after.addNode(.{
        .kind = .transform_app,
        .span = .{ .file = "moved/place.id", .start = 9, .end = 9 },
    });

    var history = History.init(std.testing.allocator);
    defer history.deinit();
    _ = try history.register(&before, .{ .revision = .{ .known = "before" } });
    try std.testing.expectError(error.GraphIncarnationFrozen, before.addNode(.{
        .kind = .value,
        .span = .{ .file = "old/place.id", .start = 2, .end = 2 },
    }));
    const old_ref = try before.entityRef(old);
    _ = try history.register(&after, .{
        .revision = .{ .known = "after" },
        .producer = .{ .one = old_ref },
    });
    const current_ref = try after.entityRef(current);
    const witness_ref = try after.entityRef(witness);

    // Equal spelling cannot establish continuity, even across a file move.
    try std.testing.expect(history.exactSuccessor(old_ref) == null);
    _ = try history.addCorrespondence(.{
        .predecessors = &.{old_ref},
        .successors = &.{current_ref},
        .relationship = .preserved,
        .preservation = .exact,
        .witness = witness_ref,
        .transformation = .{ .one = witness_ref },
        .provenance = .{ .one = witness_ref },
        .stage = .{ .one = .transform },
    });
    try std.testing.expectEqual(current_ref, history.exactSuccessor(old_ref).?);
}

test "semantic_graph: correspondence cardinality and entity bounds fail closed" {
    var before = SemanticGraph.init(std.testing.allocator);
    defer before.deinit();
    const old = try before.addNode(.{
        .kind = .value,
        .span = .{ .file = "before.id", .start = 1, .end = 1 },
    });
    var after = SemanticGraph.init(std.testing.allocator);
    defer after.deinit();
    const current = try after.addNode(.{
        .kind = .value,
        .span = .{ .file = "after.id", .start = 1, .end = 1 },
    });
    const witness = try after.addNode(.{
        .kind = .transform_app,
        .span = .{ .file = "after.id", .start = 1, .end = 1 },
    });

    var history = History.init(std.testing.allocator);
    defer history.deinit();
    _ = try history.register(&before, .{});
    _ = try history.register(&after, .{});
    const old_ref = try before.entityRef(old);
    const current_ref = try after.entityRef(current);
    const witness_ref = try after.entityRef(witness);

    try std.testing.expectError(error.InvalidCorrespondenceCardinality, history.addCorrespondence(.{
        .predecessors = &.{old_ref},
        .successors = &.{current_ref},
        .relationship = .split,
        .preservation = .lawful_refinement,
        .witness = witness_ref,
    }));
    try std.testing.expectError(error.InvalidGraphEntityRef, history.addCorrespondence(.{
        .predecessors = &.{old_ref},
        .successors = &.{.{ .incarnation = current_ref.incarnation, .entity = 99 }},
        .relationship = .replaced,
        .preservation = .lawful_refinement,
        .witness = witness_ref,
    }));
    try std.testing.expectEqual(@as(usize, 0), history.correspondenceCount());
}
