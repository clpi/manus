/// Resident semantic graph.
///
/// An `id` names one exact entity in this resident graph. Names,
/// paths, spans, and fingerprints are provenance or query projections; none of
/// them can create or recover semantic identity.
const std = @import("std");
const ast = @import("ast.zig");
const native_bootstrap = @import("native_bootstrap.zig");
const home_resolve_mod = @import("home_resolve.zig");
const Expr = ast.Expr;
const sema = @import("sema.zig");
const types = @import("types.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const place = @import("place.zig");
const region = @import("region.zig");
const subject_home = @import("subject_home.zig");
const semantic_identity = @import("semantic_identity.zig");
const authority_projection = @import("authority_projection.zig");
pub const id = semantic_identity.id;
pub const Card = semantic_identity.Card;

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
// whole qualified descriptor closure of every table shape on every compile, and
// its two answers went into `Node.recursion`/`Node.completion`, which were read
// by one `writeJson` arm each and by nothing else in either tree. The public
// `descriptorRecursion` had callers only in this file's own tests. Deleted
// because they had no consumer. Exact descriptor edges and their private
// qualification index remain because descriptor queries consume them.

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
/// cost graph memory forever. Containment is `Node.scope`; descriptor
/// qualification is a private index over the canonical descriptor edge.
pub const EdgeKind = enum {
    /// Reference to an exact binding id (not a name recovery edge).
    binding,
    /// Static member/field of a descriptor home entity.
    member,
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

test "semantic_graph: EdgeKind exposes only irreducible lowercase words" {
    const forbidden = [_][]const u8{
        "run",  "call",            "invoke",  "execute",  "read",     "write",          "get",
        "set",  "parse",           "encode",  "decode",   "convert",  "compile",        "lower",
        "emit", "transform",       "subject", "argument", "result",   "relation",       "type_of",
        "def",  "transform_input", "use",     "home",     "contains", "descriptor_ref",
    };
    inline for (@typeInfo(EdgeKind).@"enum".field_names) |field_name| {
        const kind: EdgeKind = @field(EdgeKind, field_name);
        const label = @tagName(kind);
        for (label) |byte| try std.testing.expect(byte >= 'a' and byte <= 'z');
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
    // A JSON key with no reader is not tooling; it is scenery with an audience
    // of nobody, and it cost seven fields on every graph node plus a whole
    // qualified descriptor closure walk (`recursion`) per shape.
    // `shape_id` stayed, because it has a reader that makes a decision.
    // ─────────────────────────────────────────────────────────────────────
    /// Opaque link to AST for Phase 1 — graph mirrors, does not replace, AST yet.
    ast_ref: ?*anyopaque = null,
    /// THE HOME A CALLABLE IS DECLARED IN, when that home is not this module.
    ///
    /// Null on every node lifted from the module being compiled — its home is
    /// the module node and the scope chain already says so. Non-null only
    /// on a FOREIGN relation: a declaration this module refers to and does not
    /// contain. It is the one fact that separates "the graph knows this call"
    /// from "the graph knows this call AND can name the symbol it lands on",
    /// and realization reads it through `foreignHome` rather than by
    /// re-deriving a home from a file path in a second place.
    foreign_home: ?[]const u8 = null,
    /// The graph entity this one is nested inside. `nested` is the sole derived
    /// reverse index of this authoritative fact.
    scope: ?id = null,
    /// When true, `name` was allocated on the graph allocator and must be freed in deinit.
    owns_name: bool = false,
};

pub const Edge = struct {
    from: id,
    to: id,
    kind: EdgeKind,
    position: u16 = 0,
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

/// Producer quote identity for a lifted literal value (GAP-145). The AST
/// `.quoted` arm carries provenance; this fact makes it observable on the graph
/// without collapsing text and bytes to one `.str` descriptor kingdom.
pub const SourceQuoteFact = struct {
    value: id,
    quote: ast.Quote,
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
    world: Card = .unknown,
    target: Card = .unknown,
    dependencies: Dependencies = .unknown,
};

pub const IncarnationFact = struct {
    coordinate: incarnation,
    entity_count: u32,
    revision: Revision,
    producer: RefCard,
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
    embedded: bool,
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
        embedded: bool,
    ) !void {
        const slot = try self.map.getOrPut(alloc, from);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        errdefer {
            if (slot.value_ptr.items.len == 0) {
                slot.value_ptr.deinit(alloc);
                _ = self.map.remove(from);
            }
        }
        try slot.value_ptr.append(alloc, .{ .to = to, .embedded = embedded });
    }

    fn of(self: *const RefAdjacency, from: id) []const DescriptorHit {
        const list = self.map.get(from) orelse return &.{};
        return list.items;
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

/// HOW MANY MODULE-SCOPE BINDINGS ONE APPLICATION CAN REACH A WRITE TO.
///
/// `Card` cannot carry this: it stops at `one`, and `_reset` writes three. The
/// four states are distinct and none is a sentinel for another — `unknown` is
/// "this pass could not follow the body", `none` is the POSITIVE claim "no
/// module binding is written", `one` names the exact binding, and `many` packs
/// the exact set. A boolean `mutates` would collapse the first two, which is
/// the collapse that produced GAP-225 in the effect column.
pub const MutationCard = union(enum) {
    unknown,
    none,
    one: id,
    /// Packed into `SemanticGraph.mutation_places`, ascending.
    many: FactRange,

    pub fn name(self: MutationCard) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
            .many => "many",
        };
    }
};

/// THE CLOSURE OF `BindingMutation` OVER THE CALL GRAPH, keyed by the exact
/// application occurrence — the same key `Draw` uses, for the same reason: an
/// occurrence that reaches a write frequently has no `ApplicationFact` at all,
/// so a field on that struct could not reach it.
///
/// IT IS A SECOND COLUMN AND NOT A REPLACEMENT. `BindingMutation` is what the
/// LIFT saw: this relation's body assigns this exact binding. It is a positive
/// row, so the absence of one means `none` and `unknown` at once — "writes
/// nothing" and "this pass could not follow the callees" are the same silence,
/// and they license opposite decisions. This column says which.
///
/// IT IS NOT A WORLD AND MUST NOT BECOME ONE. `Draw` answers "which world does
/// this occurrence reach"; a module binding is not an injected world and
/// confers no ambient authority, so the answer here is a BINDING. Folding the
/// two columns together would read every relation that bumps a counter as
/// exercising world authority. The columns stay distinct and admissibility is
/// DERIVED from the set — see `publishApplicationEffects`, which is the
/// derivation.
pub const MutationClosure = struct {
    application: id,
    place: MutationCard,
};

/// A PROVED BOUND on every value one exact entity holds.
///
/// `subject` is the local or parameter binding entity, not a name and not a
/// place: §6 refuses to mint a scalar as a place, so `b: i64 = 2` has no place
/// and its bound would have had nowhere to live. It has a binding entity, and
/// that is the subject a range is about.
///
/// PRODUCER: `publishBindingRanges`, once per lift, over `range.widthsOf`.
/// There is no second one; the lattice that used to run inside `dnir_lower`
/// and die with its lowering context is gone.
///
/// INVALIDATION: the relation body's statement list, and the set of names
/// bound at module scope. The analysis is flow-insensitive, so no lowering
/// order, instruction schedule or register decision can move it — which is the
/// dependency statement the lowering-local version could not make.
///
/// CONSUMERS: `dnir_lower` asks for the sign of a divisor and carries the
/// ANSWER'S SUBJECT — this entity id — into DNIR, so `native_backend` reverses
/// it here instead of trusting a boolean. Every other projection reads the
/// same column off the same graph.
pub const RangeFact = struct {
    subject: id,
    /// Every value of `subject` lies in `[0, 2^nonneg_width)`.
    nonneg_width: u8,
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
    /// The relation the binding was resolved in. Kept because it is the scope
    /// the resolution started from, NOT because `binding` is only meaningful
    /// against it -- a graph entity id is meaningful graph-wide, which is the
    /// whole point of gap[206]'s deletion condition.
    relation: id,
    /// THE BOUND NAME THIS VALUE CAME FROM, as a graph entity.
    ///
    /// This was a `place.Census` id until gap[206]. `noteOrigin` resolved it
    /// through `body.places.find`, and `bindPlace` declines every scalar, so
    /// the field answered for a record operand and for nothing else -- measured
    /// `origins=0` on four scalar fixtures against `origins=1` on a record.
    /// Two id spaces claimed the same question and the census could not answer
    /// it for the shape that asks most often.
    binding: id,
};

/// One relation writes one exact module-scope binding.
///
/// This is a sparse graph fact rather than a boolean on the relation or on an
/// application.  A binding id preserves the identity of the place being
/// changed; absence of a row is only consumed after the body lift that owns
/// this column has completed.  Several rows may share either coordinate when a
/// relation writes several bindings or several relations write one binding.
pub const BindingMutation = struct {
    relation: id,
    binding: id,
};

/// The value one module binding was initialized from, joined once at semantic
/// ingress to the exact module place that decides whether that value remains
/// current.
///
/// This is deliberately not `EdgeKind.binding`.  That edge answers the other
/// direction and the other question: a use-occurrence value names the binding
/// it reads.  Here the binding names the value its defining occurrence
/// produced.  Keeping the two relations distinct is what prevents a later use
/// from being mistaken for the definition merely because both values have the
/// same descriptor and spelling.
pub const BindingInitialization = struct {
    binding: id,
    value: id,
    place: u32,
};

/// Three producer-coverage states for `BindingInitialization`.
///
/// `unvisited` is outside this bounded producer's current domain. `invalid`
/// means the producer claimed the binding but its row was removed or damaged;
/// consumers must refuse rather than reconstruct from a name. `known` carries
/// the exact ids.
pub const BindingInitializationState = union(enum) {
    unvisited,
    invalid,
    known: BindingInitialization,
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

pub const CallableOrigin = enum { idol, c };
pub const CallableExposure = enum { internal, compat_export, c_export, c_import };

/// One graph-owned linkage decision keyed by the exact callable identity.
/// `symbol` is a physical projection selected once from checked source
/// boundary facts plus the callable's home; backends may validate or consume
/// it, but may not reconstruct it from attributes or names.
pub const CallableLinkage = struct {
    callable: id,
    origin: CallableOrigin,
    exposure: CallableExposure,
    symbol: []const u8,
};

pub const SemanticGraph = struct {
    alloc: std.mem.Allocator,
    /// Coordinate assigned only by an owning `History`. The semantic entity
    /// identity remains `id`; this qualifies it across graph incarnations.
    incarnation_coordinate: ?incarnation = null,
    /// Source path for the lifted module; used for gate-transport bootstrap faces.
    module_path: ?[]const u8 = null,
    /// Exact source-law epoch inherited from checked ingress. Source suffix,
    /// path, parser mode, and graph schema are not substitutes for this fact.
    root_source_law_edition: authority_projection.SourceLawEdition = .unknown,
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
    /// Derived here, once, from the module path by `home_resolve_mod.homeOfPath` —
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
    /// Exact identity of `module_ast` in this graph incarnation. Entry
    /// selection and realization consume this producer-owned id instead of
    /// accepting any node whose tag happens to be `.module`.
    module_root: ?id = null,
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
    source_quote_facts: std.ArrayListUnmanaged(SourceQuoteFact) = .empty,
    source_quote_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    binding_initializations: std.ArrayListUnmanaged(BindingInitialization) = .empty,
    binding_initialization_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    /// Producer-domain certificate. A set bit with no valid row is damage, not
    /// permission for a consumer to fall back to a name-keyed constant table.
    binding_initialization_candidates: std.DynamicBitSetUnmanaged = .{},
    owned_descriptors: std.ArrayListUnmanaged(*types.ResolvedType) = .empty,
    aggregate_access_relation: ?id = null,
    application_rows: std.ArrayListUnmanaged(u32) = .empty,
    application_presence: std.DynamicBitSetUnmanaged = .{},
    application_candidates: std.DynamicBitSetUnmanaged = .{},
    /// Reverse of `Node.scope` — rebuilt only from `addChild` (`law.derived.index`).
    nested: Adjacency = .{},
    /// Caller home → published application ids (`law.fact.locality`).
    home_apps: Adjacency = .{},
    /// Descriptor → qualified descriptor hits (`law.fact.locality`).
    qualified: RefAdjacency = .{},
    /// Func id assigned at addNode from the declaration pointer. Lookup is this
    /// index, not a later walk of `ast_ref` slots.
    origin: std.AutoHashMapUnmanaged(usize, id) = .empty,
    /// REVERSE OF `Node.ast_ref` FOR VALUE NODES — a derived physical index
    /// (`law.derived.index`), the same shape as `origin` above and as
    /// `out_edges`, and nothing more.
    ///
    /// It replaced `exact_i64_by_ast`, which was a SECOND STORE of the same
    /// correspondence: that map was written by `publishExactI64` in PUBLISH
    /// order while `Node.ast_ref` already recorded the same occurrence in
    /// CREATION order, and it was consulted as the authority for
    /// one-row-per-literal-occurrence — so it established meaning rather than
    /// accelerating a query, which `law.derived.index` forbids and
    /// `law.fact.producer.one` forbids twice over. MEASURED before deleting it:
    /// over the 809-module corpus, across every `exact_i64` publish carrying an
    /// occurrence in the 453 modules that reach the producer, the two stores
    /// never once disagreed. They were the same relation kept twice.
    ///
    /// Written ONLY by `addNode`, from the node's own `ast_ref`, so it is a
    /// pure function of the node set and can be rebuilt by scanning `nodes`.
    /// FIRST NODE WINS, which is exactly what the linear scan it replaced
    /// (`findValueByAstRef`) already answered. Every read re-checks
    /// `Node.kind` and `Node.ast_ref` against the node itself, so a stale
    /// bucket is harmless and no answer originates here.
    ///
    /// It does NOT retire AST identity: `exactI64OfExpr` still takes an
    /// `*const Expr` because `constIntValue` in `dnir_lower.zig` is reached
    /// from an AST-driven lowering walk. That is the remaining defect, and its
    /// deletion condition is unchanged — realization work items carrying the
    /// value id, at which point `exactI64(id)` is the only face needed and
    /// this index goes with the rest of the AST bridge.
    value_by_ast: std.AutoHashMapUnmanaged(usize, id) = .empty,
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
    /// `mutation[application]`, ascending by application id — the closure of
    /// `binding_mutations` over the call graph, with its cardinality.
    mutation_closure: std.ArrayListUnmanaged(MutationClosure) = .empty,
    /// The packed bindings a `MutationCard.many` names.
    mutation_places: std.ArrayListUnmanaged(id) = .empty,
    /// PROVED BOUNDS, keyed by the exact binding entity. §2 lists ranges among
    /// the facts this graph carries; this is the column.
    ranges: std.ArrayListUnmanaged(RangeFact) = .empty,
    /// `place[value]` for application values, ascending by value id.
    origins: std.ArrayListUnmanaged(Origin) = .empty,
    /// Exact module-binding writes, in source lift order.
    binding_mutations: std.ArrayListUnmanaged(BindingMutation) = .empty,
    callable_linkages: std.ArrayListUnmanaged(CallableLinkage) = .empty,
    callable_linkage_rows: std.AutoHashMapUnmanaged(id, u32) = .empty,
    /// Set only by checked lift. A manually assembled/bootstrap graph may have
    /// no linkage column; a checked graph may never reinterpret missing rows as
    /// permission to reconstruct them.
    callable_linkage_required: bool = false,
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
        self.source_quote_facts.deinit(self.alloc);
        self.source_quote_rows.deinit(self.alloc);
        self.binding_initializations.deinit(self.alloc);
        self.binding_initialization_rows.deinit(self.alloc);
        self.binding_initialization_candidates.deinit(self.alloc);
        for (self.owned_descriptors.items) |descriptor| self.alloc.destroy(descriptor);
        self.owned_descriptors.deinit(self.alloc);
        self.application_rows.deinit(self.alloc);
        self.application_presence.deinit(self.alloc);
        self.application_candidates.deinit(self.alloc);
        self.nested.deinit(self.alloc);
        self.home_apps.deinit(self.alloc);
        self.qualified.deinit(self.alloc);
        self.origin.deinit(self.alloc);
        self.value_by_ast.deinit(self.alloc);
        if (self.places) |*census| census.deinit();
        for (self.bodies.items) |*body| {
            body.places.deinit();
            body.regions.deinit();
        }
        self.bodies.deinit(self.alloc);
        self.worlds.deinit(self.alloc);
        self.world_members.deinit(self.alloc);
        self.draws.deinit(self.alloc);
        self.mutation_closure.deinit(self.alloc);
        self.mutation_places.deinit(self.alloc);
        self.ranges.deinit(self.alloc);
        self.origins.deinit(self.alloc);
        self.binding_mutations.deinit(self.alloc);
        for (self.callable_linkages.items) |fact| self.alloc.free(fact.symbol);
        self.callable_linkages.deinit(self.alloc);
        self.callable_linkage_rows.deinit(self.alloc);
        if (self.home) |h| self.alloc.free(h);
    }

    /// The module's own home, or null when it was lifted without a path.
    /// Realization asks this for the DEFINER half of `(home, name)`; nothing
    /// else may re-derive it, for the same reason `foreignHome` is the sole
    /// authority for the caller's half.
    pub fn selfHome(self: *const SemanticGraph) ?[]const u8 {
        return self.home;
    }

    /// Exact semantic root for this lifted source module. The pointer check
    /// establishes graph/source association; the returned id remains the
    /// semantic identity consumed downstream.
    pub fn rootForModule(self: *const SemanticGraph, mod: *const ast.Module) ?id {
        if (self.module_ast != mod) return null;
        const root = self.module_root orelse return null;
        const node = self.get(root) orelse return null;
        if (node.kind != .module) return null;
        return root;
    }

    /// True only for this graph incarnation's exact root. Node kind validates
    /// the fact; it cannot establish root identity by itself.
    pub fn isModuleRoot(self: *const SemanticGraph, entity: id) bool {
        if (self.module_root != entity) return false;
        const node = self.get(entity) orelse return false;
        return node.kind == .module;
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
        // THE ONE WRITER of `value_by_ast`, and it writes nothing the node does
        // not already carry: the key is the node's own `ast_ref`, the value is
        // the node's own id. FIRST NODE WINS, matching the linear scan this
        // index replaced. A caller that unwinds may leave a bucket pointing at
        // an id that no longer exists; `valueByAst` re-checks the node, so such
        // a bucket answers null rather than lying.
        if (node.kind == .value) {
            if (node.ast_ref) |raw| {
                const slot = try self.value_by_ast.getOrPut(self.alloc, @intFromPtr(raw));
                if (!slot.found_existing) slot.value_ptr.* = entity;
            }
        }
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

    /// Add `node` inside `parent`: records the authoritative scope fact and its
    /// private reverse index in one transaction.
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
            if (edge.kind == .member or edge.kind == .descriptor)
                return true;
        }
        return false;
    }

    /// Table/record descriptor home: sealed state or qualified descriptor edges.
    pub fn hasTableDescriptorFacts(self: *const SemanticGraph, entity: id) bool {
        const node = self.get(entity) orelse return false;
        if (node.descriptor_state != null) return true;
        return self.qualified.of(entity).len != 0;
    }

    /// Enum descriptor home: member facts without table qualification/state.
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
        return &census.places.items[site];
    }

    fn aggregateExactI64WordsMatchAt(
        self: *const SemanticGraph,
        aggregate_id: id,
        words: []const i64,
        cursor: *usize,
        depth: usize,
    ) bool {
        if (depth >= self.aggregateCount()) return false;
        const fact = self.aggregate(aggregate_id) orelse return false;
        if (fact.contents_known != .yes) return false;
        const members = self.aggregateMembers(aggregate_id) orelse return false;
        for (members) |member| {
            const node = self.get(member) orelse return false;
            const descriptor = node.descriptor orelse return false;
            switch (descriptor) {
                .i64 => {
                    if (cursor.* >= words.len or self.exactI64(member) != words[cursor.*]) return false;
                    cursor.* += 1;
                },
                .array => if (!self.aggregateExactI64WordsMatchAt(
                    member,
                    words,
                    cursor,
                    depth + 1,
                )) return false,
                else => return false,
            }
        }
        return true;
    }

    /// Whether these physical words are exactly the graph-owned, descriptor-
    /// ordered contents of one aggregate. Native and Wasm use the same query as
    /// a damage boundary before admitting a dense realization; neither backend
    /// reconstructs contents from source literals or its own layout census.
    pub fn aggregateExactI64WordsMatch(
        self: *const SemanticGraph,
        aggregate_id: id,
        words: []const i64,
    ) bool {
        var cursor: usize = 0;
        return self.aggregateExactI64WordsMatchAt(aggregate_id, words, &cursor, 0) and
            cursor == words.len;
    }

    /// The unique aggregate value bound to one exact graph place.
    ///
    /// This is a derived index over `AggregateFact.owner/place`, not another
    /// binding authority. More than one aggregate at the same place is not a
    /// unique answer (normally a rebinding) and therefore returns null. A
    /// realization can use the returned semantic id without consulting the
    /// aggregate's source expression.
    pub fn boundAggregateAtPlace(self: *const SemanticGraph, owner: id, site: u32) ?id {
        _ = self.get(owner) orelse return null;
        var found: ?id = null;
        for (self.aggregate_facts.items) |fact| {
            if (fact.owner != owner) continue;
            const fact_site = switch (fact.place) {
                .one => |value| value,
                .unknown, .none => continue,
            };
            if (fact_site != site or self.aggregate(fact.aggregate) == null) continue;
            // Nested member aggregates inherit the root place because their
            // contents project from it. Only the aggregate directly contained
            // by `owner` is the value bound there.
            if ((self.get(fact.aggregate) orelse continue).scope != owner) continue;
            // A projected aggregate can share its subject's place while being
            // produced by an application. This query selects the binding's
            // stored value, not an occurrence result at that place.
            if (self.aggregateProducer(fact.aggregate) != null) continue;
            if (found != null and found.? != fact.aggregate) return null;
            found = fact.aggregate;
        }
        return found;
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

    /// The graph producer classified this occurrence as computed aggregate
    /// projection, independently of whether every fact needed by the strict
    /// `aggregateAccess` query is still valid. Consumers use this only to fail
    /// closed on damaged rows; it never supplies a missing result or place.
    ///
    /// The target card and relation edge are independent projections of the
    /// same producer decision. Either surviving one identifies a damaged row;
    /// requiring both would let damage to one erase the producer domain and
    /// fall through to the older source/place reconstruction.
    pub fn isAggregateAccessApplication(self: *const SemanticGraph, occurrence: id) bool {
        const relation = self.aggregate_access_relation orelse return false;
        for (self.application_facts.items) |fact| {
            if (fact.application != occurrence) continue;
            const target_is_projection = switch (fact.target) {
                .one => |target| target == relation,
                .unknown, .none => false,
            };
            return target_is_projection or self.bindingRelation(occurrence) == relation;
        }
        return false;
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

    /// Exact module place by its census identity. The array position is only a
    /// physical acceleration: every read rechecks `Place.id` before answering.
    pub fn modulePlace(self: *const SemanticGraph, site: u32) ?*const place.Place {
        const census = if (self.places) |*known| known else return null;
        if (site >= census.places.items.len) return null;
        const found = &census.places.items[site];
        if (found.id != site) return null;
        return found;
    }

    /// The initializer value and place produced for one exact module binding.
    /// A claimed-but-damaged row is distinct from an occurrence outside the
    /// current producer domain, so a realization cannot turn missing graph
    /// knowledge into permission to consult `ModuleConsts` by spelling.
    pub fn bindingInitialization(self: *const SemanticGraph, binding: id) BindingInitializationState {
        if (binding >= self.binding_initialization_candidates.bit_length or
            !self.binding_initialization_candidates.isSet(binding))
        {
            return .unvisited;
        }
        const row = self.binding_initialization_rows.get(binding) orelse return .invalid;
        if (row >= self.binding_initializations.items.len) return .invalid;
        const fact = self.binding_initializations.items[row];
        if (fact.binding != binding) return .invalid;
        const binding_node = self.get(binding) orelse return .invalid;
        if (binding_node.kind != .local or binding_node.scope != self.module_root) return .invalid;
        const value_node = self.get(fact.value) orelse return .invalid;
        if (value_node.kind != .value or value_node.scope != self.module_root) return .invalid;
        if (binding_node.descriptor) |binding_descriptor| {
            const value_descriptor = value_node.descriptor orelse return .invalid;
            if (!binding_descriptor.eql(value_descriptor)) return .invalid;
        }
        if (self.modulePlace(fact.place) == null) return .invalid;
        return .{ .known = fact };
    }

    fn publishBindingInitialization(
        self: *SemanticGraph,
        binding: id,
        value: id,
        site: u32,
    ) !void {
        try self.requireOpen();
        const binding_node = self.get(binding) orelse return error.InvalidBindingInitialization;
        if (binding_node.kind != .local or binding_node.scope != self.module_root)
            return error.InvalidBindingInitialization;
        const value_node = self.get(value) orelse return error.InvalidBindingInitialization;
        if (value_node.kind != .value or value_node.scope != self.module_root)
            return error.InvalidBindingInitialization;
        if (binding_node.descriptor) |binding_descriptor| {
            const value_descriptor = value_node.descriptor orelse
                return error.InvalidBindingInitialization;
            if (!binding_descriptor.eql(value_descriptor))
                return error.InvalidBindingInitialization;
        }
        if (self.modulePlace(site) == null) return error.InvalidBindingInitialization;
        if (self.binding_initialization_candidates.bit_length < self.nodes.items.len) {
            try self.binding_initialization_candidates.resize(self.alloc, self.nodes.items.len, false);
        }
        if (self.binding_initialization_candidates.isSet(binding))
            return error.DuplicateBindingInitialization;
        self.binding_initialization_candidates.set(binding);
        const row = try coordinateForLength(self.binding_initializations.items.len);
        try self.binding_initializations.append(self.alloc, .{
            .binding = binding,
            .value = value,
            .place = site,
        });
        errdefer _ = self.binding_initializations.pop();
        try self.binding_initialization_rows.putNoClobber(self.alloc, binding, row);
    }

    /// THE VALUE AN OCCURRENCE IS, asked with the occurrence.
    ///
    /// The single route from an `*const Expr` to the graph entity minted for
    /// it. `value_by_ast` only accelerates it: the answer is CONFIRMED against
    /// the node's own `kind` and `ast_ref` before it is returned, so the index
    /// can be dropped or rebuilt at will and no fact originates in it.
    pub fn valueByAst(self: *const SemanticGraph, expr: *const Expr) ?id {
        const raw: *const anyopaque = @ptrCast(@constCast(expr));
        const candidate = self.value_by_ast.get(@intFromPtr(raw)) orelse return null;
        const node = self.get(candidate) orelse return null;
        if (node.kind != .value) return null;
        if (node.ast_ref != raw) return null;
        return candidate;
    }

    /// THE EXACT CONTENT OF A LITERAL, ASKED WITH THE LITERAL.
    ///
    /// The face a realization phase can actually use, because it holds an
    /// `*const Expr` and not a value id. Its absence is why `intLiteralStep`
    /// exists as an AST re-parse in `dnir_lower.zig`.
    ///
    /// It is now a COMPOSITION, not a lookup in a store of its own: the
    /// occurrence names the value (`valueByAst`), and the value names the
    /// content (`exactI64`). There is exactly one store of each, so the two
    /// cannot drift apart the way `exact_i64_by_ast` and `exact_i64_rows`
    /// could.
    pub fn exactI64OfExpr(self: *const SemanticGraph, expr: *const Expr) ?i64 {
        const value = self.valueByAst(expr) orelse return null;
        return self.exactI64(value);
    }

    fn publishExactI64(self: *SemanticGraph, value: id, content: i64) !void {
        const node = self.get(value) orelse return error.InvalidExactValueFact;
        if (node.descriptor == null or node.descriptor.? != .i64) return error.InvalidExactValueFact;
        if (self.exact_i64_rows.contains(value)) return error.DuplicateExactValueFact;
        // ONE ROW PER LITERAL OCCURRENCE. An application-operand lift and the
        // literal sweep can both reach the same `.int_lit` node; the first to
        // arrive owns it and the second is a no-op rather than a shadow, which
        // is `publishSourceQuote`'s rule and for the same reason -- the family
        // is measured against source TOKENS.
        //
        // A value whose `ast_ref` is not itself an integer literal is a DERIVED
        // content -- the result of `xs[1]` against a constant aggregate, a
        // foreign module's `.field` constant. It takes no TOKEN slot, so the
        // one-row-per-occurrence refusal does not apply to it, but it is
        // indexed all the same: a derived content is precisely the answer the
        // AST re-parse could never give, and `exactI64OfExpr` is where a
        // consumer collects it.
        const occurrence: ?*const Expr = blk: {
            const raw = node.ast_ref orelse break :blk null;
            break :blk @ptrCast(@alignCast(raw));
        };
        if (occurrence) |expr| {
            // ONE ROW PER TOKEN, decided against the GRAPH rather than against
            // a private map: the occurrence's value is `valueByAst(expr)`, and
            // if that value is not this one and already owns content, this
            // token is taken. Identical to the map's first-writer-wins rule
            // wherever the two were ever both consulted, which was everywhere:
            // measured over the corpus, they never disagreed.
            if (expr.* == .int_lit) {
                if (self.valueByAst(expr)) |owner| {
                    if (owner != value and self.exact_i64_rows.contains(owner)) return;
                }
            }
        }
        const row = try coordinateForLength(self.exact_i64_facts.items.len);
        try self.exact_i64_facts.append(self.alloc, .{ .value = value, .content = content });
        errdefer _ = self.exact_i64_facts.pop();
        try self.exact_i64_rows.putNoClobber(self.alloc, value, row);
    }

    pub fn sourceQuote(self: *const SemanticGraph, value: id) ?ast.Quote {
        const row = self.source_quote_rows.get(value) orelse return null;
        if (row >= self.source_quote_facts.items.len) return null;
        const fact = self.source_quote_facts.items[row];
        if (fact.value != value or self.get(value) == null) return null;
        return fact.quote;
    }

    /// THE PRODUCER QUOTE IDENTITY OF A LITERAL, ASKED WITH THE LITERAL.
    ///
    /// The face a realization phase can actually use: it holds an
    /// `*const Expr`, not a value id, so without this it re-read
    /// `expr.quoted.quote` and became a second authority on text-vs-bytes.
    pub fn sourceQuoteOfExpr(self: *const SemanticGraph, expr: *const Expr) ?ast.Quote {
        const value = self.sourceQuoteValue(expr) orelse return null;
        return self.sourceQuote(value);
    }

    /// The graph VALUE a literal occurrence is, so a consumer can read the
    /// descriptor the producer already resolved instead of re-deciding
    /// text-vs-bytes from the quote face for itself.
    ///
    /// Composed, like `exactI64OfExpr`: the occurrence names the value and the
    /// value names the quote. `source_quote_by_ast` used to answer the first
    /// half from a store of its own, in publish order, duplicating what
    /// `Node.ast_ref` already recorded in creation order. MEASURED over the
    /// 809-module corpus before deleting it: on every `publishSourceQuote`
    /// call the two named the same entity, and neither ever failed to find one.
    pub fn sourceQuoteValue(self: *const SemanticGraph, expr: *const Expr) ?id {
        const value = self.valueByAst(expr) orelse return null;
        if (self.sourceQuote(value) == null) return null;
        return value;
    }

    /// THE OCCURRENCE IS NOT A PARAMETER. It is `node.ast_ref`, which the value
    /// already carries; passing it separately made the caller a second source
    /// of the same correspondence and let the two be handed different exprs.
    fn publishSourceQuote(self: *SemanticGraph, value: id, quote: ast.Quote) !void {
        const node = self.get(value) orelse return error.InvalidSourceQuoteFact;
        if (node.kind != .value) return error.InvalidSourceQuoteFact;
        if (self.source_quote_rows.contains(value)) return error.DuplicateSourceQuoteFact;
        // ONE ENTITY PER LITERAL OCCURRENCE. An operand lift and the binding
        // sweep can both reach the same `.quoted` node; the first one to
        // arrive owns it, and the second is a no-op rather than a shadow --
        // decided against the graph now, not against a private map.
        if (node.ast_ref) |raw| {
            const expr: *const Expr = @ptrCast(@alignCast(raw));
            if (self.valueByAst(expr)) |owner| {
                if (owner != value and self.source_quote_rows.contains(owner)) return;
            }
        }
        const row = try coordinateForLength(self.source_quote_facts.items.len);
        try self.source_quote_facts.append(self.alloc, .{ .value = value, .quote = quote });
        errdefer _ = self.source_quote_facts.pop();
        try self.source_quote_rows.putNoClobber(self.alloc, value, row);
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
        // A PUBLISHED APPLICATION IS NOT BOOTSTRAP — by this type's own
        // three-column definition, bootstrap means "the graph identified
        // NOTHING". When `publishApplication` ran for this node the graph
        // identified the relation, and the spelling classifier below must not
        // answer over it: a module that declares its own `tail` and calls it
        // subject-first is PUBLISHED (lowering realizes it with lineage,
        // validateDnirApplications counts it in `seen`) while the classifier
        // still called it bootstrap by name and excluded it from `expected` —
        // seen=1, expected=0, a refusal manufactured by the classifier alone.
        // Same rule as `lowerCollectionRelation`'s `any`: the declaration owns
        // the name.
        if (self.application(entity) != null) return false;
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

    /// Home-local shape lookup with a published cross-home fallback. Application
    /// result-shape edges must not be lost when the callee's return type lives in
    /// another module home (e.g. `peek2: token` calling into `compiler.token`).
    fn resolveTableShape(self: *const SemanticGraph, scope: id, name: []const u8) ?id {
        if (self.resolveInHome(scope, name, .table_shape)) |found| return found;
        return self.findUniqueByNameOfKind(name, .table_shape);
    }

    fn publishDescriptorRefEdge(self: *SemanticGraph, from: id, to: id, embedded: bool) !void {
        try self.addEdge(.{ .from = from, .to = to, .kind = .descriptor });
        errdefer self.popEdge();
        try self.qualified.push(self.alloc, from, to, embedded);
    }

    fn publishDescriptorRefType(self: *SemanticGraph, descriptor: id, rt: types.ResolvedType, embedded: bool) !void {
        switch (rt) {
            .pointer => |p| {
                try self.publishDescriptorRefType(descriptor, p.*, false);
            },
            .@"struct" => |s| {
                const start = self.homeOf(descriptor) orelse descriptor;
                if (self.resolveInHome(start, s.name, .table_shape)) |ref| {
                    try self.publishDescriptorRefEdge(descriptor, ref, embedded);
                }
            },
            .table_type => |t| {
                for (t.fields) |field| {
                    try self.publishDescriptorRefType(descriptor, field.typ, embedded);
                }
            },
            .enum_type => |e| {
                const start = self.homeOf(descriptor) orelse descriptor;
                if (self.resolveInHome(start, e.name, .enum_shape)) |ref| {
                    try self.publishDescriptorRefEdge(descriptor, ref, embedded);
                }
                for (e.variants) |variant| {
                    if (variant.payload) |payload| {
                        for (payload) |member| {
                            try self.publishDescriptorRefType(descriptor, member, embedded);
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
        embedded: bool,
    };

    /// Exact descriptor entities referenced by canonical descriptor edges.
    pub fn descriptorRefsOf(self: *const SemanticGraph, descriptor: id, alloc: std.mem.Allocator) ![]const DescriptorRefTarget {
        if (!self.hasDescriptorFacts(descriptor)) return error.InvalidDescriptorEntity;
        const hits = self.qualified.of(descriptor);
        var out: std.ArrayListUnmanaged(DescriptorRefTarget) = .empty;
        errdefer out.deinit(alloc);
        try out.ensureTotalCapacity(alloc, hits.len);
        for (hits) |hit| {
            out.appendAssumeCapacity(.{ .target = hit.to, .embedded = hit.embedded });
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
        type_name: ?[]const u8,
    ) !void {
        const shape = blk: {
            switch (descriptor) {
                .@"struct" => |s| break :blk self.resolveTableShape(scope, s.name),
                .table_type => {
                    if (type_name) |name| break :blk self.resolveTableShape(scope, name);
                    break :blk null;
                },
                else => break :blk null,
            }
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
                try self.addDescriptorShapeEdge(member, 0, home, descriptor, null);
            }
        }
    }

    fn attachCallableResultShapes(self: *SemanticGraph, home: id) !void {
        for (self.nested.of(home)) |relation| {
            const node = self.get(relation) orelse continue;
            if (node.kind != .func) continue;
            const descriptor = node.result_descriptor orelse continue;
            var type_name: ?[]const u8 = null;
            if (node.ast_ref) |raw| {
                const fd: *const ast.FuncDecl = @ptrCast(@alignCast(raw));
                type_name = switch (fd.func.ret_type) {
                    .named => |n| n,
                    else => null,
                };
            }
            try self.addDescriptorShapeEdge(relation, 0, home, descriptor, type_name);
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

    /// Exact relation identity already published for this declaration.
    /// Entry selection is one semantic consumer: a requested source spelling
    /// is resolved while the declaration is still available, then only this id
    /// crosses into realization. Names remain diagnostics and physical input;
    /// they never become the selected relation identity.
    pub fn relationForDeclaration(self: *const SemanticGraph, declaration: *const ast.FuncDecl) ?id {
        const relation = self.findFuncDecl(declaration) orelse return null;
        if (!self.callable(relation)) return null;
        return relation;
    }

    pub fn callableLinkage(self: *const SemanticGraph, entity: id) ?*const CallableLinkage {
        const row = self.callable_linkage_rows.get(entity) orelse return null;
        if (row >= self.callable_linkages.items.len) return null;
        const fact = &self.callable_linkages.items[row];
        if (fact.callable != entity or !self.callable(entity)) return null;
        return fact;
    }

    pub fn requiresCallableLinkage(self: *const SemanticGraph) bool {
        return self.callable_linkage_required;
    }

    fn publishCallableLinkage(
        self: *SemanticGraph,
        entity: id,
        checked: sema.CallableLinkage,
    ) !void {
        try self.requireOpen();
        const node = self.get(entity) orelse return error.InvalidCallableLinkageFact;
        if (!self.callable(entity)) return error.InvalidCallableLinkageFact;
        const name = node.name orelse return error.InvalidCallableLinkageFact;
        if (self.callable_linkage_rows.contains(entity)) return error.DuplicateCallableLinkageFact;

        const symbol = switch (checked.exposure) {
            .internal => blk: {
                const owner_home = node.foreign_home orelse self.home;
                if (owner_home) |home| break :blk try home_resolve_mod.homeSymbol(self.alloc, home, name);
                break :blk try self.alloc.dupe(u8, name);
            },
            .compat_export, .c_export => try self.alloc.dupe(u8, checked.symbol_override orelse name),
            .c_import => try self.alloc.dupe(u8, checked.symbol_override orelse
                return error.InvalidCallableLinkageFact),
        };
        errdefer self.alloc.free(symbol);
        const row = try coordinateForLength(self.callable_linkages.items.len);
        try self.callable_linkages.append(self.alloc, .{
            .callable = entity,
            .origin = switch (checked.origin) {
                .idol => .idol,
                .c => .c,
            },
            .exposure = switch (checked.exposure) {
                .internal => .internal,
                .compat_export => .compat_export,
                .c_export => .c_export,
                .c_import => .c_import,
            },
            .symbol = symbol,
        });
        errdefer _ = self.callable_linkages.pop();
        try self.callable_linkage_rows.putNoClobber(self.alloc, entity, row);
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
        self.module_root = mod_id;
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

    /// EVERY NAME A RELATION BODY BINDS, AS A GRAPH ENTITY.
    ///
    /// Deduplicated against this relation's own children, so a rebind of a name
    /// already bound is the same binding — the rule `place.zig` states for a
    /// place, applied to the entity the graph owns. A `.param` of the same
    /// spelling already IS that binding and is not shadowed by a second row.
    fn noteLocalBinding(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        name: []const u8,
        loc: ast.Loc,
        descriptor: ?types.ResolvedType,
        ast_ref: ?*anyopaque,
    ) !void {
        for (self.nested.of(scope)) |child| {
            const node = self.get(child) orelse continue;
            if (node.kind != .local and node.kind != .param) continue;
            if (node.name) |n| {
                if (!std.mem.eql(u8, n, name)) continue;
                if (descriptor != null and self.nodes.items[child].descriptor == null) {
                    self.nodes.items[child].descriptor = descriptor;
                }
                return;
            }
        }
        _ = try self.addChild(scope, .{
            .kind = .local,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .name = name,
            .descriptor = descriptor,
            .ast_ref = ast_ref,
        });
    }

    /// Publish one exact write to a binding owned by this module.
    ///
    /// The binding and relation have already been resolved by the lexical lift;
    /// this function validates those ids and never repeats resolution from a
    /// spelling.  Repeated writes by one relation to one binding are one sparse
    /// fact, not one row per source statement.
    fn publishBindingMutation(self: *SemanticGraph, relation: id, binding: id) !void {
        if (!self.callable(relation)) return error.InvalidBindingMutation;
        const module = self.module_root orelse return error.InvalidBindingMutation;
        const node = self.get(binding) orelse return error.InvalidBindingMutation;
        if (node.kind != .local or node.scope != module) return error.InvalidBindingMutation;
        for (self.binding_mutations.items) |fact| {
            if (fact.relation == relation and fact.binding == binding) return;
        }
        try self.binding_mutations.append(self.alloc, .{
            .relation = relation,
            .binding = binding,
        });
    }

    /// Sparse module-binding mutation facts in source lift order.
    pub fn bindingMutations(self: *const SemanticGraph) []const BindingMutation {
        return self.binding_mutations.items;
    }

    fn bindingDescriptor(self: *SemanticGraph, typ: ast.TypeExpr) ?types.ResolvedType {
        const descriptor = types.resolve(typ, null, self.alloc) catch return null;
        if (descriptor == .any) return null;
        return descriptor;
    }

    fn addQuoteValue(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        expr: *const Expr,
        quote: ast.Quote,
    ) !void {
        // The occurrence already IS a value. Publish on that exact identity;
        // minting a second value would leave `valueByAst` pointing at the
        // first, quote-less node and make the fact unreachable to consumers.
        if (self.valueByAst(expr)) |owner| {
            if (self.source_quote_rows.contains(owner)) return;
            try self.publishSourceQuote(owner, quote);
            return;
        }
        const loc = expr.loc();
        const descriptor = types.quotedLiteralType(quote);
        const value = try self.addChild(scope, .{
            .kind = .value,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .descriptor = descriptor,
            .knowledge = semantic_algebra.knowledgeOfType(descriptor),
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.publishSourceQuote(value, quote);
    }

    /// EVERY NAME A SCOPE BINDS, IN TWO SWEEPS, AND THE ORDER IS THE POINT.
    ///
    /// The single-sweep version walked into a `.func_decl` the moment it
    /// reached one, so a relation body was lifted against however much of the
    /// module happened to be declared ABOVE it. `place.zig`'s `ForeignReach`
    /// records the same finding on the other axis: "module-scope order does not
    /// decide whether a relation reaches a word, so the question is answered
    /// before the walk begins". Deciding whether `_pos = _pos + 1` writes the
    /// module's `_pos` or mints a relation-local needs the module's bindings to
    /// ALREADY EXIST, and with one sweep that answer depended on which side of
    /// the relation the `global` was written on.
    ///
    /// So: sweep one binds everything at this scope; sweep two descends into
    /// the callables. The rule holds at every level, so a relation nested in a
    /// relation sees its enclosing body's bindings for the same reason.
    fn liftBindingsInStmts(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        stmts: []ast.Stmt,
    ) !void {
        // THE SHADOW ROSTER, GROWN IN SOURCE ORDER AND TRUNCATED AT EVERY BLOCK
        // BOUNDARY. A bare-name assignment is a write to the module binding it
        // names UNLESS the name is declared where the assignment can see the
        // declaration — which is a LEXICAL question, not a whole-body one.
        //
        // A whole-body roster gets it wrong in the unsafe direction. Measured,
        // before this was scoped:
        //
        //     global ring: i64 = 0
        //     bump(): i64
        //       ring = 1          <- a write to the module binding
        //       if ring > 100
        //         ring: i64 = 5   <- a declaration in an inner block
        //       7
        //
        // exported an EMPTY `mutations` array. The inner declaration is scoped
        // to the `if`; the assignment above it names the module's word, and
        // dropping that row is exactly the licence GAP-225 is about.
        //
        // The graph has no block entities — every local of a relation is a
        // child of the one callable — so the roster is where block extent
        // lives, and it lives only for as long as this walk needs it.
        var declared: std.ArrayListUnmanaged([]const u8) = .empty;
        defer declared.deinit(self.alloc);
        try self.liftBindingsAtScope(file, scope, stmts, &declared);
        try self.liftBindingsInCallables(file, scope, stmts);
    }

    /// Enter a nested lexical block: everything it declares is visible inside
    /// it and gone after, so the roster is restored to the length it had.
    fn liftBindingsInBlock(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        stmts: []ast.Stmt,
        declared: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!void {
        const mark = declared.items.len;
        defer declared.shrinkRetainingCapacity(mark);
        try self.liftBindingsAtScope(file, scope, stmts, declared);
    }

    fn noteName(
        alloc: std.mem.Allocator,
        out: *std.ArrayListUnmanaged([]const u8),
        name: []const u8,
    ) !void {
        for (out.items) |existing| if (std.mem.eql(u8, existing, name)) return;
        try out.append(alloc, name);
    }

    /// TRUE WHEN THIS BARE-NAME ASSIGNMENT IS A WRITE TO A MODULE BINDING, and
    /// the write has been recorded when it returns true.
    ///
    /// Fails toward MINTING A LOCAL only where the module has no such binding
    /// at all, so no assignment loses an entity it used to have. Where the
    /// module DOES bind the name and this body does not, the module binding is
    /// what the program means and the shadow entity was the wrong answer.
    fn noteModuleWrite(
        self: *SemanticGraph,
        scope: id,
        declared: []const []const u8,
        name: []const u8,
    ) !bool {
        const root = self.module_root orelse return false;
        // The module's own body binds; it does not write somebody else's word.
        if (scope == root) return false;
        // A GENUINE SHADOW STAYS DISTINCT. This is the control acceptance §3
        // asks for: a body that declares `_pos` where this assignment can see
        // the declaration owns its own `_pos`, and the module's is a different
        // entity that this assignment does not touch.
        for (declared) |existing| if (std.mem.eql(u8, existing, name)) return false;
        // A parameter of the same spelling IS that binding. Only `.param`,
        // because a `.local` child of this scope may have been minted by a
        // declaration in a SIBLING block that this assignment cannot see —
        // block extent is the roster's, and the graph has no block entities.
        for (self.nested.of(scope)) |child| {
            const node = self.get(child) orelse continue;
            if (node.kind != .param) continue;
            const child_name = node.name orelse continue;
            if (std.mem.eql(u8, child_name, name)) return false;
        }
        // RESOLVE THROUGH THE ENCLOSING CHAIN, NOT STRAIGHT TO THE MODULE. For
        // a relation nested inside another, a same-named local or parameter of
        // the ENCLOSING relation is the binding the assignment names, and the
        // graph records reaching it as a `.capture` edge. Jumping to the root
        // would publish a module write about a word the program never touches.
        // Sweep one finishes the enclosing scope before sweep two descends, so
        // by here every binding above this relation exists.
        const outer = (self.get(scope) orelse return false).scope orelse return false;
        const binding = self.resolveBindingInScope(outer, name) orelse return false;
        const binding_node = self.get(binding) orelse return false;
        if (binding_node.scope != root) return false;
        const relation = self.enclosingCallable(scope) orelse return false;
        try self.publishBindingMutation(relation, binding);
        return true;
    }

    /// Sweep two: the callables declared under `stmts`, whatever block they sit
    /// in. Separate from sweep one so no relation body is lifted before the
    /// scope enclosing it has finished binding its own names.
    fn liftBindingsInCallables(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        stmts: []ast.Stmt,
    ) anyerror!void {
        for (stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    if (self.findFuncDecl(fd)) |nested_id| {
                        try self.liftBindingsInStmts(file, nested_id, fd.func.body.stmts);
                    }
                },
                .do_block => |*d| try self.liftBindingsInCallables(file, scope, d.body.stmts),
                .while_loop => |*w| try self.liftBindingsInCallables(file, scope, w.body.stmts),
                .repeat_loop => |*r| try self.liftBindingsInCallables(file, scope, r.body.stmts),
                .num_for => |*nf| try self.liftBindingsInCallables(file, scope, nf.body.stmts),
                .gen_for => |*g| try self.liftBindingsInCallables(file, scope, g.body.stmts),
                .if_stmt => |*i| {
                    try self.liftBindingsInCallables(file, scope, i.then.stmts);
                    for (i.elseifs) |*ei| try self.liftBindingsInCallables(file, scope, ei.body.stmts);
                    if (i.else_body) |*eb| try self.liftBindingsInCallables(file, scope, eb.stmts);
                },
                .try_stmt => |*t| {
                    try self.liftBindingsInCallables(file, scope, t.body.stmts);
                    for (t.catches) |*cc| try self.liftBindingsInCallables(file, scope, cc.body.stmts);
                },
                .defer_stmt => |*d| try self.liftBindingsInCallables(file, scope, d.body.stmts),
                else => {},
            }
        }
    }

    fn liftBindingsAtScope(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        stmts: []ast.Stmt,
        declared: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!void {
        for (stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.names) |*lname| {
                        try self.liftTableShapeFromTypeExpr(
                            file,
                            scope,
                            lname.ident,
                            lname.typ,
                            lname.loc,
                            lname.attributes,
                            lname,
                        );
                        try noteName(self.alloc, declared, lname.ident);
                        try self.noteLocalBinding(
                            file,
                            scope,
                            lname.ident,
                            lname.loc,
                            self.bindingDescriptor(lname.typ),
                            @ptrCast(@constCast(lname)),
                        );
                    }
                },
                .const_decl => |*cd| {
                    try noteName(self.alloc, declared, cd.ident);
                    try self.noteLocalBinding(
                        file,
                        scope,
                        cd.ident,
                        cd.loc,
                        self.bindingDescriptor(cd.typ),
                        null,
                    );
                },
                .global_decl => |*gd| {
                    for (gd.names) |*lname| {
                        // `global x = …` INSIDE a relation writes the module's
                        // word — `place.zig` records the same reading in
                        // `reachStmt`. It is a write, not a second binding.
                        if (try self.noteModuleWrite(scope, declared.items, lname.ident)) continue;
                        try noteName(self.alloc, declared, lname.ident);
                        try self.noteLocalBinding(
                            file,
                            scope,
                            lname.ident,
                            lname.loc,
                            self.bindingDescriptor(lname.typ),
                            @ptrCast(@constCast(lname)),
                        );
                    }
                },
                .assign => |*asg| {
                    for (asg.targets) |target| {
                        if (target.* != .name) continue;
                        // THE SHADOW ENTITY DIES HERE. A bare-name assignment
                        // whose name the module binds and this body does not is
                        // a WRITE to that binding; minting a same-spelled local
                        // in this relation is what made the two indistinguishable
                        // (gaps/GAP-225.md).
                        if (try self.noteModuleWrite(scope, declared.items, target.name.ident)) continue;
                        try self.noteLocalBinding(file, scope, target.name.ident, target.loc(), null, null);
                    }
                },
                .do_block => |*d| try self.liftBindingsInBlock(file, scope, d.body.stmts, declared),
                .while_loop => |*w| try self.liftBindingsInBlock(file, scope, w.body.stmts, declared),
                .repeat_loop => |*r| try self.liftBindingsInBlock(file, scope, r.body.stmts, declared),
                .if_stmt => |*i| {
                    try self.liftBindingsInBlock(file, scope, i.then.stmts, declared);
                    for (i.elseifs) |*ei| try self.liftBindingsInBlock(file, scope, ei.body.stmts, declared);
                    if (i.else_body) |*eb| try self.liftBindingsInBlock(file, scope, eb.stmts, declared);
                },
                .num_for => |*nf| {
                    const mark = declared.items.len;
                    defer declared.shrinkRetainingCapacity(mark);
                    try noteName(self.alloc, declared, nf.var_name);
                    try self.noteLocalBinding(file, scope, nf.var_name, nf.loc, null, null);
                    try self.liftBindingsAtScope(file, scope, nf.body.stmts, declared);
                },
                .gen_for => |*g| {
                    const mark = declared.items.len;
                    defer declared.shrinkRetainingCapacity(mark);
                    for (g.vars) |v| try noteName(self.alloc, declared, v);
                    for (g.vars) |v| try self.noteLocalBinding(file, scope, v, g.loc, null, null);
                    try self.liftBindingsAtScope(file, scope, g.body.stmts, declared);
                },
                // `.func_decl` IS SWEEP TWO'S. Descending here is exactly the
                // order dependence `liftBindingsInStmts` split the walk to end.
                .try_stmt => |*t| {
                    try self.liftBindingsInBlock(file, scope, t.body.stmts, declared);
                    for (t.catches) |*cc| try self.liftBindingsInBlock(file, scope, cc.body.stmts, declared);
                },
                .defer_stmt => |*d| try self.liftBindingsInBlock(file, scope, d.body.stmts, declared),
                else => {},
            }
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
    /// THE ONE WRITE SITE for `SemanticGraph.ranges`.
    ///
    /// One relation body at a time: settle `range.widthsOf` over it, then key
    /// each proved name to EVERY local or parameter entity of that name inside
    /// the relation. Several entities can share a name — sibling blocks bind
    /// distinct identities — and the lattice is flow-insensitive, so its claim
    /// is about the name across the whole body and therefore about each of
    /// them. Publishing on one and not the others would make the fact depend
    /// on which binding a consumer happened to reach.
    fn publishBindingRanges(self: *SemanticGraph, mod: *const ast.Module) !void {
        // Imported HERE rather than at module scope: `range` is also a local
        // binding name in this file (packed member ranges, refinement ranges),
        // and a module-scope alias would shadow six of them.
        const value_range = @import("range.zig");
        if (self.ranges.items.len > 0) return;
        const outer = try value_range.outerNames(self.alloc, mod);
        defer self.alloc.free(outer);
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1) continue;
            const relation = self.findFuncDecl(fd) orelse continue;
            var widths = try value_range.widthsOf(self.alloc, &fd.func, outer);
            defer widths.deinit(self.alloc);
            if (widths.count() == 0) continue;
            for (self.nodes.items, 0..) |node, i| {
                if (node.kind != .local and node.kind != .param) continue;
                const name = node.name orelse continue;
                const entity = std.math.cast(id, i) orelse break;
                if (self.enclosingCallable(node.scope orelse continue) != relation) continue;
                const width = widths.get(name) orelse continue;
                try self.ranges.append(self.alloc, .{ .subject = entity, .nonneg_width = width });
            }
        }
    }

    /// The proved bound on one entity, or null for UNKNOWN — which is not
    /// "negative", not "zero" and not "unbounded".
    pub fn nonNegativeWidth(self: *const SemanticGraph, subject: id) ?u8 {
        for (self.ranges.items) |fact| {
            if (fact.subject == subject) return fact.nonneg_width;
        }
        return null;
    }

    /// The proved bound on a divisor-shaped EXPRESSION inside one relation.
    ///
    /// THE DERIVATION STAYS IN SEMA, and the layering gate is what said so:
    /// `dnir_lower` asking `range.widthOfExpr` itself was a BACKEND importing
    /// SEMA to re-derive meaning at emission time, which is how two places come
    /// to decide the same thing and disagree. The backend asks here; the answer
    /// is derived once, over this graph's own `ranges` column, by the same
    /// `range.zig` derivation the producer settled the lattice with.
    pub fn nonNegativeWidthOfExpr(
        self: *const SemanticGraph,
        relation: id,
        expr: *const Expr,
    ) ?u8 {
        const value_range = @import("range.zig");
        var reach = RangeReach{ .graph = self, .relation = relation };
        return value_range.widthOfExpr(reach.lookup(), expr);
    }

    /// One relation's view of `ranges`, as the name lookup `range.widthOfExpr`
    /// takes. It reads the published column and holds nothing.
    const RangeReach = struct {
        graph: *const SemanticGraph,
        relation: id,

        fn lookup(self: *const RangeReach) @import("range.zig").Lookup {
            return .{ .ctx = self, .of = widthOfName };
        }

        fn widthOfName(ctx: *const anyopaque, name: []const u8) ?u8 {
            const self: *const RangeReach = @ptrCast(@alignCast(ctx));
            const subject = self.graph.bindingNamedIn(self.relation, name) orelse return null;
            return self.graph.nonNegativeWidth(subject);
        }
    };

    /// The local or parameter entity a name denotes inside one relation, for a
    /// consumer that has a source name and needs the exact subject a range is
    /// keyed to. Several entities can share the name; they carry the same
    /// width by construction, so the first is an exact answer to "which
    /// subject" and not a choice between different facts.
    pub fn bindingNamedIn(self: *const SemanticGraph, relation: id, name: []const u8) ?id {
        for (self.nodes.items, 0..) |node, i| {
            if (node.kind != .local and node.kind != .param) continue;
            const held = node.name orelse continue;
            if (!std.mem.eql(u8, held, name)) continue;
            const entity = std.math.cast(id, i) orelse return null;
            if (self.enclosingCallable(node.scope orelse continue) != relation) continue;
            return entity;
        }
        return null;
    }

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
            var regions = try region.analyzeFunction(self.alloc, &fd.func, self, relation);
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

    /// THE EFFECT OF ONE APPLICATION OCCURRENCE, including the POSITIVE card
    /// that `ApplicationFact.effect` structurally cannot carry.
    ///
    /// `publishApplicationEffects` computes "provably unobservable" and stops,
    /// so the stored field only ever holds `.none` or `.unknown`. Measured over
    /// the corpus: 842 files, 7709 applications, none 4518, unknown 3191, ONE
    /// ZERO. That zero was read as an unimplemented arm. It is not — the fact
    /// is stored on the wrong entity:
    ///
    ///     draws naming a world                       381
    ///     ...that also have an ApplicationFact         0
    ///
    /// PERFECTLY DISJOINT. Every world observation in the corpus happens at an
    /// occurrence with NO `ApplicationFact`, exactly as `Draw`'s own note says
    /// ("the applications that actually DRAW a world are overwhelmingly the
    /// ones with no `ApplicationFact` at all") — measured, it is not
    /// overwhelmingly but entirely. So a positive card written into that field
    /// can never reach a single world-drawing occurrence, and an earlier
    /// attempt to write one there fired zero times.
    ///
    /// Because the two domains are disjoint there is no second producer here
    /// and no new column: this DERIVES the answer from `draws`, which already
    /// records which world an occurrence drew. `stdin:read()` draws `io`, so it
    /// observes the world and `Card.one` names WHICH world it observed.
    ///
    /// THE `c` WORLD IS EXCLUDED. Drawing `c` means the call is FOREIGN, not
    /// that it acts — an earlier seed taken from foreign declarations produced
    /// `llabs` as its first identity, and `llabs` is pure. Crossing the foreign
    /// boundary establishes that the compiler cannot SEE the callee, never that
    /// the callee ACTS; `publishApplicationWorlds` already routes `c` to
    /// AUTHORITY for that reason, and effect stays `.unknown` there.
    pub fn applicationEffect(self: *const SemanticGraph, occurrence: id) Card {
        if (self.application(occurrence)) |fact| return fact.effect;
        const drawn = switch (self.applicationWorld(occurrence)) {
            .one => |w| w,
            else => return .unknown,
        };
        for (self.worlds.items) |fact| {
            if (fact.world != drawn) continue;
            // A PROTOCOL WORLD OBSERVES NOTHING. `subject_home` already carries
            // the discriminator as `Provision`: `string`, `math` and `table`
            // are `.realized` — the file calls them "the protocol worlds" and
            // states that `string.len(s)` is "the operation-first face of
            // `s:len()`". Such a relation acts on the value it was handed and
            // reaches no state outside it, so drawing that world is not an
            // effect. `os` supplies a ROSTER of environment members (`env`,
            // `cwd`, `clock`, `arg`) and `io` SUPPLIES the standing streams;
            // those observe state the program does not own.
            //
            // Read from `Provision` and NOT from a list of world names. An
            // earlier cut of this accessor published `.one` for every drawn
            // world and produced `math` 41 times and `string` 5 — 46 of 381
            // identities asserting an effect for `math.floor`. A name list
            // would have fixed the count while committing exactly the
            // names-carry-semantics error this tree denies; `Provision` is the
            // fact that was already there.
            //
            // `c` is excluded separately and for a different reason: drawing it
            // means the call is FOREIGN, not that it acts. The seed tried
            // before this one came from foreign declarations and named `llabs`,
            // which is pure. `publishApplicationWorlds` routes `c` to
            // AUTHORITY, and effect stays `.unknown` there.
            if (fact.home == .c) return .unknown;
            const declaration = subject_home.declarationOf(fact.home);
            if (declaration.provides == .realized) return .unknown;
            return .{ .one = drawn };
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
    /// The bound name a value came from, as the graph's OWN three-valued
    /// reference. `place.Site` before gap[206]: a value that is a place id
    /// answered through a type spelled for the place census, which is how the
    /// two spaces stayed conflated with nothing forcing them apart.
    pub fn valueOrigin(self: *const SemanticGraph, value: id) semantic_identity.Card {
        const node = self.get(value) orelse return .unknown;
        const raw = node.ast_ref orelse return .unknown;
        const expr: *const Expr = @ptrCast(@alignCast(raw));
        if (expr.* != .name) return .none;
        var match: ?id = null;
        for (self.outEdges(value)) |edge_index| {
            if (edge_index >= self.edges.items.len) continue;
            const edge = self.edges.items[edge_index];
            if (edge.from != value or edge.kind != .binding) continue;
            const binding = self.get(edge.to) orelse continue;
            if (binding.kind != .local and binding.kind != .param) continue;
            // Two bindings for one value is contradictory producer output. The
            // three-state query cannot represent contradiction yet, so it must
            // refuse exactness rather than select one by insertion order.
            if (match != null) return .unknown;
            match = edge.to;
        }
        return if (match) |binding| .{ .one = binding } else .unknown;
    }

    /// Lift module-level symbols, alias table shapes, and enum shapes.
    pub fn liftModuleFull(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModule(mod, file);
        try self.liftAliasShapes(mod, file, mod_id);
        try self.liftEnumShapes(mod, file, mod_id);
        try self.attachMemberDescriptorShapes(mod_id);
        try self.attachCallableResultShapes(mod_id);
        // One binding producer walks the module and every callable beneath it.
        // Module bindings used to be absent while function locals were present,
        // so an application value could carry an exact descriptor yet lose the
        // binding it read solely because that binding lived one scope higher.
        try self.liftBindingsInStmts(file, mod_id, mod.body.stmts);
        try self.liftPlaces(mod);
        try self.liftBodies(mod);
        // AFTER the bindings, because a range is keyed by binding entity and
        // there is nothing to key it to before `liftBindingsInStmts` has run.
        try self.publishBindingRanges(mod);
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
        // A module tail is the process result. Call syntax does not make that
        // result unobserved: `_answer()` at root must carry `_answer`'s value
        // into the physical ABI `main`. Statement/call_stmt positions above
        // remain the producer-owned discard cases.
        if (mod.body.tail_expr) |tail| {
            try self.liftExprsFromExpr(tail, file, parent, .single);
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
                _ = try self.liftAggregateAccess(expr, file, parent, consumption);
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
        if (try self.liftAggregateAccess(expr, file, parent, consumption)) return;
        if (aggregateIndexSite(expr)) |site| {
            if (!self.isBootstrapApplicationExpr(expr) and self.aggregateForExpr(site.obj, parent) != null)
                return;
        }
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

    const AggregateIndexSite = struct {
        obj: *const ast.Expr,
        key: *const ast.Expr,
    };

    fn aggregateIndexSite(expr: *const ast.Expr) ?AggregateIndexSite {
        return switch (expr.*) {
            .index => |ix| .{ .obj = ix.obj, .key = ix.key },
            // `()` is application; `[]` is computed projection. Legacy call-form
            // indexing belongs in ingress compatibility migration, not here.
            else => null,
        };
    }

    /// ONE BINDING, NEVER WRITTEN, NEVER ALIASED, NEVER ESCAPED, CONTENTS KNOWN.
    ///
    /// The licence to answer a projection from the aggregate's contents instead
    /// of from its storage. It lives HERE because the aggregate fact and the
    /// place fact both do, and because two readers need the SAME answer: the
    /// lift decides whether to publish the projection at all, and realization
    /// decides whether to fold it. When those two disagreed — the lift checking
    /// only `contents_known` while realization also checked the place — five
    /// corpus modules published a projection realization then refused with
    /// `aggregate-access-depth`, which is `law.fact.producer.one` collecting on
    /// a predicate that had been written down twice.
    pub fn aggregateIsSoleImmutableBinding(self: *const SemanticGraph, aggregate_id: id) bool {
        const fact = self.aggregate(aggregate_id) orelse return false;
        if (fact.contents_known != .yes) return false;
        const p = self.aggregatePlace(aggregate_id) orelse return false;
        // ONE PRODUCER FOR CONTENTS-KNOWN. `fact.contents_known` is checked
        // above and is authoritative: `publishAggregate` sets it when this
        // graph has just lifted the members it names. `p.facts.contents_known`
        // is a SECOND, AST-derived answer to the same question —
        // `place.zig` recomputes it through `allFieldsConst`, which walks the
        // initializer and rejects any field that is not an int literal or a
        // nested table of them, including every NAMED field (it takes
        // `positionalValue(field) orelse return false`). MEASURED over the
        // corpus: of 77 admission attempts, 0 were rejected by the aggregate
        // fact and 48 were rejected by the place's copy — the two stores
        // disagreeing about one property, which is the defect, not the guard.
        // Static realization is still gated exactly where it belongs: every
        // demanded member must carry an `exact_i64`, and realization consults
        // this same predicate before selecting the dense table, so the two
        // cannot drift.
        if (p.shape != .collection) return false;
        // THE REMAINING REFUSALS ARE FACTS, NOT MISSING FACTS. RE-MEASURED AT
        // 09b20611: 1010 tracked `.id`, 22 of which contain any attempt at
        // all, 99 attempts, 19 admit, and EVERY ONE OF THE 80 REJECTS IS A
        // TRUE NEGATIVE. (The `5 -> 23` and `5 -> 53` deltas in the widening
        // paragraph below were taken BEFORE 7c304127 deleted the place's
        // duplicate `contents_known` clause; their baseline of 5 admits is now
        // 19. The refusals they record are unaffected — both widenings still
        // publish answers the programs' own assertions refute.)
        //
        //   all 56   the mutation/immutability line below — the module really
        //            does execute `t[k] = v` on this place (`symtab_native` 22,
        //            `simultaneous_assign_proof` 12, `swap` 6,
        //            `table_mutable_store` 5, `projection_index_assign` 3,
        //            `codegen_native` 3, `nested_while_reduction` 3,
        //            `typed_array_bracket_assign` 1, `untyped_assign` 1).
        //            ALL-CLAUSE ATTRIBUTION, and it matters: both halves of
        //            that `or` reject all 56, so deleting either half alone
        //            admits nothing. `markAllUnknown`, the whole-census
        //            sledgehammer, tagged ZERO of them: no reject here comes
        //            from an unmodelled statement.
        //   all 24   `escape = .unknown`, and escape is their SOLE blocker.
        //            18 from `for x in xs`, whose body assigns the loop
        //            variable and thereby writes the table — the place walk
        //            records NO mutation for that write, so escape is the only
        //            fact standing between this predicate and a wrong answer.
        //            6 from `sort(xs, 1, 10)`, an in-place quicksort that
        //            mutates through the parameter.
        //
        // BOTH WIDENINGS WERE BUILT AND MEASURED, and both are refusals. Making
        // iteration non-escaping moved admits 5 -> 23 and published
        // applications 4997 -> 5015; the 18 new rows assert `xs[1] == 1` on the
        // exact source lines that read `assert(xs[1] == 11)`. Deleting the
        // mutation clause moved admits 5 -> 53 and published applications
        // 4997 -> 5045; of the five machine-compilable modules it reaches, two
        // (`projection_index_assign`, `symtab_native`) then refuse with DNB011
        // `application-realization-count` and three (`table_mutable_store`
        // 100 -> 0, `nested_while_reduction` 15 -> 0, `codegen_native` 2 -> 0)
        // return the wrong answer.
        //
        // A PLACE INCARNATION WOULD BE CORRECT AND WOULD HAVE ONE CONSUMER.
        //
        // Every clause here is whole-binding because `AggregateFact.place` is
        // `.one(site)` and `boundAggregateAtPlace` returns null when two
        // aggregates share a place. The graph can name the collection at a site
        // but not its CONTENTS BETWEEN TWO WRITES. That reading is right, and
        // the paragraph that used to stand here concluded from it that an
        // ordered-incarnation model was the missing piece. IT WAS SIZED BEFORE
        // BEING BUILT, and the size is the refutation.
        //
        // RE-MEASURED AT 09b20611 WITH ALL-CLAUSE ATTRIBUTION — every clause
        // evaluated for every attempt, not just the first one that returns,
        // because deleting a clause moves its rejects to the next one:
        //
        //   1010 tracked `.id`; 22 of them contain ANY admission attempt.
        //   99 attempts. 19 admit.
        //   56 blocked by the mutation/immutability line — and BY BOTH HALVES
        //      of it. Not one of the 56 is blocked by `mutation` alone, so
        //      deleting that half admits ZERO rows. The earlier "48 stop on
        //      the mutation clause" was a first-clause tally of one `or`.
        //   24 blocked by `escape`, and by escape ALONE.
        //
        // THE INCARNATION CEILING, DERIVED FROM FACTS THIS GRAPH ALREADY
        // PUBLISHES. A store-forwarding incarnation can carry contents through
        // a write only when the write is straight-line, constant-indexed and
        // singular — `Access.depth == 0`, `const_index`, `mult = exact 1`, all
        // three already on every access row of the v9+ export. Reads behind
        // only such writes, over the whole written population (24 writes, 60
        // reads): ELEVEN, in THREE files. `examples/demand/swap.id` (5) and
        // `examples/simultaneous_assign_proof.id` (5) both REFUSE at the direct
        // backend with DNB001 `ret-type:any`, so folding them changes no
        // machine text at all. The remainder is `examples/projection_index_
        // assign.id`: ONE read, two of its three attempts, in a five-line
        // program that already answers 42 correctly.
        //
        // The 24 escape rejects are not reachable either: all four of their
        // files (`boring/quicksort`, `boring/sort/quick`,
        // `direct_table_iteration`, `table/iterate`) also refuse DNB001, and
        // their blocker is loop-carried or interprocedural rather than a
        // missing incarnation.
        //
        // So the whole model — ordered incarnations, dominating-read
        // resolution, per-incarnation member contents, store forwarding — buys
        // ONE READ IN ONE FILE and no correctness change anywhere. A correct
        // architecture with one consumer is the producer-hollow pattern this
        // tree keeps measuring, and the measurement is the deliverable.
        //
        // WHAT WOULD MOVE THE NUMBER, so the next lane does not re-derive it:
        // the ceiling is set by the WRITES, not by this predicate. 13 of the
        // 24 writes carry a non-constant index or sit at loop depth, and every
        // read after one of them is unanswerable by any content model. Widening
        // the yield means either exact keys for loop-variable writes (a
        // recurrence fact, not a place fact) or more corpus programs of this
        // shape at all — 988 of the 1010 files reach this predicate ZERO times.
        //
        // AND ONE COST THE MODEL DOES NOT YET HAVE A FACT FOR: resolving a read
        // to its dominating incarnation needs the read's POSITION, and
        // `ApplicationFact` carries none. The census points live on
        // `place.Access`; nothing corresponds an access to the application that
        // performs it. That correspondence would have to be built first.
        if (p.facts.mutation != .no or p.facts.immutability != .yes) return false;
        if (p.facts.alias != .no or p.facts.escape != .no) return false;
        return switch (p.bindCount()) {
            .exact => |count| count == 1,
            .bounded, .unknown => false,
        };
    }

    fn liftAggregateAccess(
        self: *SemanticGraph,
        expr: *const ast.Expr,
        file: []const u8,
        parent: id,
        consumption: types.ReturnConsumption,
    ) !bool {
        const site = aggregateIndexSite(expr) orelse return false;
        if (self.isBootstrapApplicationExpr(expr)) return false;
        const subject = self.aggregateForExpr(site.obj, parent) orelse return false;
        const subject_node = self.get(subject) orelse return error.InvalidAggregateFact;
        const descriptor = subject_node.descriptor orelse return error.InvalidAggregateFact;
        if (descriptor != .array) return error.InvalidAggregateFact;
        const result_descriptor = descriptor.array.elem.*;
        // This bounded producer owns hierarchical projection and immutable
        // one-level scalar projection. Mutable flat aggregates remain on the
        // existing place realization until their writes carry the same exact
        // access/result identities; they are outside this producer domain,
        // not examined-and-unknown.
        if (result_descriptor != .array and self.aggregateProducer(subject) == null and
            (result_descriptor != .i64 or !self.aggregateIsSoleImmutableBinding(subject))) return false;
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

        const key = try self.addApplicationValue(occurrence, site.key, file, .i64);
        try self.noteOrigin(key, site.key, parent);
        var selected: ?id = null;
        if (self.exactI64(key)) |constant_key| {
            const members = self.aggregateMembers(subject) orelse return error.InvalidAggregateFact;
            if (constant_key >= 1 and constant_key <= @as(i64, @intCast(members.len))) {
                selected = members[@intCast(constant_key - 1)];
            }
        } else if (site.key.* == .int_lit) {
            try self.publishExactI64(key, site.key.int_lit.val);
            const members = self.aggregateMembers(subject) orelse return error.InvalidAggregateFact;
            const constant_key = site.key.int_lit.val;
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
        return true;
    }

    /// Lift module fully including call sites (Phase 1 complete lift).
    pub fn liftModuleWithCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModuleCalls(mod, file);
        try self.liftLiteralFacts(file, mod_id, &mod.body, true);
        return mod_id;
    }

    /// Everything `liftModuleWithCalls` does EXCEPT the literal sweeps, so the
    /// checked lift can run its own application operands FIRST and the sweep
    /// LAST. Order is the whole reason this split exists: the sweep claims a
    /// literal occurrence, and an occurrence an application names is better
    /// owned by the application's operand entity, which carries the resolved
    /// descriptor, the operand pack membership and the origin.
    fn liftModuleCalls(self: *SemanticGraph, mod: *const ast.Module, file: []const u8) !id {
        const mod_id = try self.liftModuleFull(mod, file);
        try self.liftCalls(mod, file, mod_id);
        return mod_id;
    }

    /// THE CONTENT OR QUOTE IDENTITY OF EVERY LITERAL VALUE THE SOURCE WRITES.
    ///
    /// MEASURED BEFORE THIS EXISTED: `add(8, 34)` — two integer literal
    /// operands — published ZERO `exact_i64` facts, and `gate/coverage.sh`
    /// scored the family PRODUCER-HOLLOW at 3148/20354 = 15.5% over the
    /// 716-module corpus. Every one of those 3148 came from an aggregate
    /// member or a constant index key, the only two positions
    /// `publishExactI64` was called from, so the graph did not hold the
    /// content of an ordinary integer operand or an ordinary binding.
    ///
    /// That is the root of gap[213]: a constant condition needed a fold in the
    /// backend because there was no fact to look up. It is also why
    /// `intLiteralStep` exists as an AST re-parse at 19 sites in
    /// `dnir_lower.zig` — `gate/coverage.sh`'s `exact.i64` rival row.
    ///
    /// ONE ROW PER TOKEN. `publishExactI64` claims the literal's AST node, so
    /// an occurrence an application operand already owns is skipped here and
    /// the family stays comparable with the lexical denominator it is measured
    /// against.
    ///
    /// `source_quote` used to have a second, narrower binding-initializer walk.
    /// On the exact 817-file coverage corpus that published 1,693 facts for
    /// 8,086 lexical quote tokens (20.9%) while `exact_i64` reached 98.5%.
    /// Keeping two walks made their domains drift. One walk now publishes both
    /// existing families; no second literal census or producer is introduced.
    ///
    /// A `.func_expr` body is NOT swept: `findFuncDecl` keys on
    /// `*const ast.FuncDecl` and a lambda has no such entity, so its literals
    /// have no scope to be parented to that is not a lie.
    fn liftBindingInitialization(
        self: *SemanticGraph,
        scope: id,
        statement: *const ast.Stmt,
        name: []const u8,
        initializer: *const Expr,
    ) !void {
        // The correspondence is value-generic. This first producer domain is
        // deliberately the exact-integer subset because it has an existing
        // machine consumer; quote content can reuse the same fact later.
        if (self.module_root != scope) return;
        const value = self.valueByAst(initializer) orelse return;
        if (self.exactI64(value) == null) return;

        // Name lookup is lawful only here at the source-resolution boundary.
        // The stored answer is three exact identities, and no consumer repeats
        // either lookup.
        const binding = self.resolveBindingInScope(scope, name) orelse return;
        const binding_node = self.get(binding) orelse return;
        if (binding_node.kind != .local or binding_node.scope != self.module_root) return;

        // This producer certifies only values whose exact-i64 occurrence
        // descriptor already agrees with the binding. A checked literal such
        // as `n: u64 = 3` is lawful, but its descriptor satisfaction is not an
        // exact-i64 binding-initialization fact; leave it unvisited until that
        // producer exists. Once a row is claimed, publish/query validation
        // below still refuses every descriptor mismatch as graph damage.
        if (binding_node.descriptor) |binding_descriptor| {
            const value_node = self.get(value) orelse return;
            const value_descriptor = value_node.descriptor orelse return;
            if (!binding_descriptor.eql(value_descriptor)) return;
        }

        // Prove the transitional name projection found this exact definition,
        // not another binding with the same spelling, before storing its place
        // identity. A later rebind therefore cannot publish a rival row.
        const bound_place = self.placeNamed(name) orelse return;
        if (bound_place.binding != statement or bound_place.init != initializer) return;
        if (bound_place.shape != .scalar or bound_place.region != .module) return;
        try self.publishBindingInitialization(binding, value, bound_place.id);
    }

    fn liftLiteralFacts(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        block: *const ast.Block,
        direct_module: bool,
    ) anyerror!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.inits) |seed| try self.liftLiteralFactsInExpr(file, scope, seed);
                    if (direct_module) for (ld.names, 0..) |*name, i| {
                        if (i >= ld.inits.len) break;
                        try self.liftBindingInitialization(scope, stmt, name.ident, ld.inits[i]);
                    };
                },
                .const_decl => |*cd| {
                    try self.liftLiteralFactsInExpr(file, scope, cd.val);
                    if (direct_module) try self.liftBindingInitialization(scope, stmt, cd.ident, cd.val);
                },
                .global_decl => |*gd| for (gd.inits) |seed| try self.liftLiteralFactsInExpr(file, scope, seed),
                .assign => |*asg| {
                    for (asg.targets) |target| try self.liftLiteralFactsInExpr(file, scope, target);
                    for (asg.values) |value| try self.liftLiteralFactsInExpr(file, scope, value);
                },
                .call_stmt => |*cs| try self.liftLiteralFactsInExpr(file, scope, cs.expr),
                .expr_stmt => |*es| try self.liftLiteralFactsInExpr(file, scope, es.expr),
                .ret => |*r| for (r.vals) |value| try self.liftLiteralFactsInExpr(file, scope, value),
                .do_block => |*d| try self.liftLiteralFacts(file, scope, &d.body, false),
                .while_loop => |*w| {
                    try self.liftLiteralFactsInExpr(file, scope, w.cond);
                    try self.liftLiteralFacts(file, scope, &w.body, false);
                },
                .repeat_loop => |*r| {
                    try self.liftLiteralFacts(file, scope, &r.body, false);
                    try self.liftLiteralFactsInExpr(file, scope, r.cond);
                },
                .if_stmt => |*i| {
                    if (i.binding) |b| try self.liftLiteralFactsInExpr(file, scope, b.expr);
                    try self.liftLiteralFactsInExpr(file, scope, i.cond);
                    try self.liftLiteralFacts(file, scope, &i.then, false);
                    for (i.elseifs) |*ei| {
                        try self.liftLiteralFactsInExpr(file, scope, ei.cond);
                        try self.liftLiteralFacts(file, scope, &ei.body, false);
                    }
                    if (i.else_body) |*eb| try self.liftLiteralFacts(file, scope, eb, false);
                },
                .num_for => |*nf| {
                    try self.liftLiteralFactsInExpr(file, scope, nf.start);
                    try self.liftLiteralFactsInExpr(file, scope, nf.stop);
                    if (nf.step) |step| try self.liftLiteralFactsInExpr(file, scope, step);
                    try self.liftLiteralFacts(file, scope, &nf.body, false);
                },
                .gen_for => |*g| {
                    for (g.iters) |iter| try self.liftLiteralFactsInExpr(file, scope, iter);
                    try self.liftLiteralFacts(file, scope, &g.body, false);
                },
                .try_stmt => |*t| {
                    try self.liftLiteralFacts(file, scope, &t.body, false);
                    for (t.catches) |*cc| try self.liftLiteralFacts(file, scope, &cc.body, false);
                    for (t.defers) |*d| try self.liftLiteralFacts(file, scope, &d.body, false);
                },
                .defer_stmt => |*d| try self.liftLiteralFacts(file, scope, &d.body, false),
                .match_stmt => |*m| {
                    try self.liftLiteralFactsInExpr(file, scope, m.scrutinee);
                    for (m.arms) |*arm| {
                        if (arm.pattern == .literal) try self.liftLiteralFactsInExpr(file, scope, arm.pattern.literal);
                        if (arm.guard) |guard| try self.liftLiteralFactsInExpr(file, scope, guard);
                        try self.liftLiteralFacts(file, scope, &arm.body, false);
                    }
                },
                .func_decl => |*fd| {
                    const nested = self.findFuncDecl(fd) orelse continue;
                    try self.liftLiteralFacts(file, nested, &fd.func.body, false);
                },
                else => {},
            }
        }
        // A single-line Idol body stores its answer in `tail_expr`, not in
        // `stmts`. Omitting it here left every one-line relation's literals
        // unreached, which is most of them.
        if (block.tail_expr) |tail| try self.liftLiteralFactsInExpr(file, scope, tail);
    }

    fn liftLiteralFactsInExpr(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        expr: *const Expr,
    ) anyerror!void {
        switch (expr.*) {
            .int_lit => |literal| try self.addExactI64Value(file, scope, expr, literal.val),
            .quoted => |literal| try self.addQuoteValue(file, scope, expr, literal.quote),
            .index => |ix| {
                try self.liftLiteralFactsInExpr(file, scope, ix.obj);
                try self.liftLiteralFactsInExpr(file, scope, ix.key);
            },
            .field => |f| try self.liftLiteralFactsInExpr(file, scope, f.obj),
            .call => |c| {
                try self.liftLiteralFactsInExpr(file, scope, c.func);
                for (c.args) |argument| try self.liftLiteralFactsInExpr(file, scope, argument);
            },
            .method_call => |mc| {
                try self.liftLiteralFactsInExpr(file, scope, mc.obj);
                for (mc.args) |argument| try self.liftLiteralFactsInExpr(file, scope, argument);
            },
            .binop => |b| {
                try self.liftLiteralFactsInExpr(file, scope, b.lhs);
                try self.liftLiteralFactsInExpr(file, scope, b.rhs);
            },
            .unop => |u| try self.liftLiteralFactsInExpr(file, scope, u.operand),
            .table => |t| for (t.fields) |field| switch (field) {
                .indexed => |entry| {
                    try self.liftLiteralFactsInExpr(file, scope, entry.key);
                    try self.liftLiteralFactsInExpr(file, scope, entry.val);
                },
                .named => |entry| try self.liftLiteralFactsInExpr(file, scope, entry.val),
                .positional => |element| try self.liftLiteralFactsInExpr(file, scope, element),
                .spread => |source| try self.liftLiteralFactsInExpr(file, scope, source),
                .semantic => |entry| try self.liftLiteralFactsInExpr(file, scope, entry.val),
            },
            .try_expr => |t| try self.liftLiteralFactsInExpr(file, scope, t.operand),
            .unwrap_expr => |u| try self.liftLiteralFactsInExpr(file, scope, u.operand),
            .await_expr => |a| try self.liftLiteralFactsInExpr(file, scope, a.operand),
            .contains_expr => |c| {
                try self.liftLiteralFactsInExpr(file, scope, c.lhs);
                try self.liftLiteralFactsInExpr(file, scope, c.rhs);
            },
            .sequence => |s| for (s.exprs) |element| try self.liftLiteralFactsInExpr(file, scope, element),
            .range => |r| {
                try self.liftLiteralFactsInExpr(file, scope, r.start);
                try self.liftLiteralFactsInExpr(file, scope, r.end);
                if (r.step) |step| try self.liftLiteralFactsInExpr(file, scope, step);
            },
            .if_expr => |ie| {
                try self.liftLiteralFactsInExpr(file, scope, ie.cond);
                try self.liftLiteralFactsInExpr(file, scope, ie.then_expr);
                try self.liftLiteralFactsInExpr(file, scope, ie.else_expr);
            },
            .match_expr => |me| {
                try self.liftLiteralFactsInExpr(file, scope, me.scrutinee);
                for (me.arms) |*arm| {
                    if (arm.pattern == .literal) try self.liftLiteralFactsInExpr(file, scope, arm.pattern.literal);
                    if (arm.guard) |guard| try self.liftLiteralFactsInExpr(file, scope, guard);
                    try self.liftLiteralFacts(file, scope, &arm.body, false);
                }
            },
            .list_comp => |lc| {
                try self.liftLiteralFactsInExpr(file, scope, lc.value);
                try self.liftLiteralFactsInExpr(file, scope, lc.iter);
                if (lc.filter) |filter| try self.liftLiteralFactsInExpr(file, scope, filter);
            },
            else => {},
        }
    }

    fn addExactI64Value(
        self: *SemanticGraph,
        file: []const u8,
        scope: id,
        expr: *const Expr,
        content: i64,
    ) !void {
        // The occurrence already IS a value that owns its content — do not
        // mint a second entity for one token.
        if (self.valueByAst(expr)) |owner| {
            if (self.exact_i64_rows.contains(owner)) return;
        }
        const loc = expr.loc();
        const value = try self.addChild(scope, .{
            .kind = .value,
            .span = .{ .file = file, .start = loc.line, .end = loc.col },
            .descriptor = .i64,
            .knowledge = .at_comptime,
            .stage = .sema,
            .ast_ref = @ptrCast(@constCast(expr)),
        });
        try self.publishExactI64(value, content);
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
        switch (expr.*) {
            .quoted => |lit| try self.publishSourceQuote(value, lit.quote),
            // THE OPERAND HALF OF `exact_i64`. `add(8, 34)` published ZERO
            // exact content facts: the family fired only on aggregate members
            // and on a constant index key, so nothing in the graph held the
            // content of an ordinary integer operand and every consumer that
            // needed one re-parsed it from the AST. The value entity was
            // already here and already carried the resolved `.i64` descriptor;
            // what was missing was the one line that published its content.
            .int_lit => |literal| if (descriptor == .i64) {
                try self.publishExactI64(value, literal.val);
            },
            else => {},
        }
        return value;
    }

    /// Publish checked name occurrences nested inside one application operand.
    ///
    /// Immediate operands of a checked application already get their value id
    /// from `addApplicationValue`.  Their CHILDREN did not: `sink("{t}")`
    /// published the concat value but not the `t` value inside it, and a
    /// bootstrap application such as `stdout:write("{t}")` published neither
    /// because it intentionally has no `ApplicationFact` yet.  In both cases
    /// realization fell back to a module-name/type census even though Sema had
    /// checked the exact occurrence and the graph already owned its binding.
    ///
    /// This bounded producer visits application operand expression trees only.
    /// It deliberately does not enter nested function or block bodies: those
    /// have their own scope and value producers and remain `unvisited` here.
    /// A checked
    /// application's root stays with `addApplicationValue`; an unresolved or
    /// bootstrap application's root is included because no later pack producer
    /// will claim it. Every admitted name must already have both Sema's exact
    /// descriptor and an exact graph binding; an unresolved name remains
    /// unvisited. The graph does not yet carry a producer-domain completeness
    /// certificate, so publishing an edge-less placeholder would make
    /// "visited but refused" indistinguishable from damaged producer output.
    fn liftCheckedNamesInOperand(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        occurrence: id,
        expr: *const Expr,
        include_root: bool,
    ) anyerror!void {
        if (include_root and expr.* == .name and self.valueByAst(expr) == null) root: {
            const descriptor = checked.exprDescriptor(expr) orelse break :root;
            if (descriptor == .any) break :root;
            const ident = expr.name.ident;
            const start = self.get(occurrence).?.scope orelse break :root;
            const binding = self.resolveBindingInScope(start, ident) orelse break :root;
            const loc = expr.loc();
            const value = try self.addChild(occurrence, .{
                .kind = .value,
                .span = .{ .file = file, .start = loc.line, .end = loc.col },
                .descriptor = descriptor,
                .knowledge = semantic_algebra.knowledgeOfType(descriptor),
                .stage = .sema,
                .ast_ref = @ptrCast(@constCast(expr)),
            });
            try self.addEdge(.{ .from = value, .to = binding, .kind = .binding });
        }

        switch (expr.*) {
            .index => |index| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, index.obj, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, index.key, true);
            },
            .field => |field| try self.liftCheckedNamesInOperand(checked, file, occurrence, field.obj, true),
            .call => |call| for (call.args) |argument| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, true);
            },
            .method_call => |call| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, call.obj, true);
                for (call.args) |argument| {
                    try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, true);
                }
            },
            .binop => |binary| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, binary.lhs, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, binary.rhs, true);
            },
            .unop => |unary| try self.liftCheckedNamesInOperand(checked, file, occurrence, unary.operand, true),
            .table => |table| for (table.fields) |field| switch (field) {
                .indexed => |entry| {
                    try self.liftCheckedNamesInOperand(checked, file, occurrence, entry.key, true);
                    try self.liftCheckedNamesInOperand(checked, file, occurrence, entry.val, true);
                },
                .named => |entry| try self.liftCheckedNamesInOperand(checked, file, occurrence, entry.val, true),
                .positional => |value| try self.liftCheckedNamesInOperand(checked, file, occurrence, value, true),
                .spread => |value| try self.liftCheckedNamesInOperand(checked, file, occurrence, value, true),
                .semantic => |value| try self.liftCheckedNamesInOperand(checked, file, occurrence, value.val, true),
            },
            .list_comp => |list| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, list.value, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, list.iter, true);
                if (list.filter) |filter| {
                    try self.liftCheckedNamesInOperand(checked, file, occurrence, filter, true);
                }
            },
            .try_expr => |attempt| try self.liftCheckedNamesInOperand(checked, file, occurrence, attempt.operand, true),
            .unwrap_expr => |unwrap| try self.liftCheckedNamesInOperand(checked, file, occurrence, unwrap.operand, true),
            .if_expr => |conditional| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, conditional.cond, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, conditional.then_expr, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, conditional.else_expr, true);
            },
            .match_expr => |match| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, match.scrutinee, true);
                for (match.arms) |*arm| {
                    if (arm.pattern == .literal) {
                        try self.liftCheckedNamesInOperand(checked, file, occurrence, arm.pattern.literal, true);
                    }
                    if (arm.guard) |guard| {
                        try self.liftCheckedNamesInOperand(checked, file, occurrence, guard, true);
                    }
                }
            },
            .await_expr => |awaited| try self.liftCheckedNamesInOperand(checked, file, occurrence, awaited.operand, true),
            .contains_expr => |contains| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, contains.lhs, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, contains.rhs, true);
            },
            .quote => |quoted| try self.liftCheckedNamesInOperand(checked, file, occurrence, quoted.expr, true),
            .unquote => |quoted| try self.liftCheckedNamesInOperand(checked, file, occurrence, quoted.expr, true),
            .macro_call => |macro| for (macro.args) |argument| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, true);
            },
            .sequence => |sequence| for (sequence.exprs) |item| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, item, true);
            },
            .range => |range| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, range.start, true);
                try self.liftCheckedNamesInOperand(checked, file, occurrence, range.end, true);
                if (range.step) |step| {
                    try self.liftCheckedNamesInOperand(checked, file, occurrence, step, true);
                }
            },
            // Nested bodies are outside this producer's declared domain.  A
            // later scope-owned producer must publish their occurrences; this
            // walk must not attach them to the enclosing application.
            .func_expr => {},
            else => {},
        }
    }

    fn liftCheckedApplicationOperandNames(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        file: []const u8,
        occurrence: id,
        expr: *const Expr,
        fact: ?sema.ApplicationFact,
    ) anyerror!void {
        if (fact) |application_fact| {
            if (application_fact.subject) |subject| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, subject, false);
            }
            for (application_fact.arguments) |argument| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, false);
            }
            return;
        }
        // No semantic application pack exists yet.  Its syntactic argument
        // expressions are nevertheless sema-visited values, and this producer
        // records that bounded domain without pretending the callee resolved.
        switch (expr.*) {
            .call => |call| for (call.args) |argument| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, true);
            },
            .method_call => |call| for (call.args) |argument| {
                try self.liftCheckedNamesInOperand(checked, file, occurrence, argument, true);
            },
            else => {},
        }
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
    pub fn resolveBindingInScope(self: *const SemanticGraph, start_scope: id, name: []const u8) ?id {
        var scope: ?id = start_scope;
        while (scope) |s| {
            for (self.nested.of(s)) |child| {
                const node = self.get(child) orelse continue;
                if (node.kind != .local and node.kind != .param) continue;
                if (node.name) |n| {
                    if (std.mem.eql(u8, n, name)) return child;
                }
            }
            scope = self.get(s).?.scope;
        }
        return null;
    }

    const CaptureLiftError = error{
        OutOfMemory,
        DuplicateSemanticDeclaration,
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
        try self.liftForeignModuleConstants(foreign, resolved.module, resolved.path);
        return foreign;
    }

    fn liftForeignModuleConstants(
        self: *SemanticGraph,
        foreign_module: id,
        mod: *const ast.Module,
        file: []const u8,
    ) !void {
        for (mod.body.stmts) |*stmt| {
            var ident: ?[]const u8 = null;
            var val: ?*const Expr = null;
            switch (stmt.*) {
                .assign => |as| {
                    if (as.targets.len == 1 and as.values.len == 1 and as.targets[0].* == .name) {
                        ident = as.targets[0].name.ident;
                        val = as.values[0];
                    }
                },
                .local_decl => |ld| {
                    if (ld.names.len == 1 and ld.inits.len == 1) {
                        ident = ld.names[0].ident;
                        val = ld.inits[0];
                    }
                },
                .const_decl => |cd| {
                    ident = cd.ident;
                    val = cd.val;
                },
                .global_decl => |gd| {
                    if (gd.names.len == 1 and gd.inits.len == 1) {
                        ident = gd.names[0].ident;
                        val = gd.inits[0];
                    }
                },
                else => {},
            }
            if (ident) |name| {
                if (val) |expr| {
                    if (ast.intLiteralValue(expr)) |content| {
                        const value = try self.addChild(foreign_module, .{
                            .kind = .value,
                            .span = .{ .file = file, .start = expr.loc().line, .end = expr.loc().col },
                            .name = name,
                            .descriptor = .i64,
                            .knowledge = .at_comptime,
                            .stage = .sema,
                            .ast_ref = @ptrCast(@constCast(expr)),
                        });
                        try self.publishExactI64(value, content);
                    }
                }
            }
        }
    }

    fn liftForeignConstantFieldSites(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        block: *const ast.Block,
        file: []const u8,
        parent: id,
    ) anyerror!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    const func_id = self.findFuncDecl(fd) orelse continue;
                    try self.liftForeignConstantFieldSites(checked, &fd.func.body, file, func_id);
                },
                .if_stmt => |*i| {
                    try self.liftForeignConstantFieldSitesInExpr(checked, i.cond, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &i.then, file, parent);
                    for (i.elseifs) |*ei| {
                        try self.liftForeignConstantFieldSitesInExpr(checked, ei.cond, file, parent);
                        try self.liftForeignConstantFieldSites(checked, &ei.body, file, parent);
                    }
                    if (i.else_body) |*eb| try self.liftForeignConstantFieldSites(checked, eb, file, parent);
                },
                .while_loop => |*w| {
                    try self.liftForeignConstantFieldSitesInExpr(checked, w.cond, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &w.body, file, parent);
                },
                .repeat_loop => |*r| {
                    try self.liftForeignConstantFieldSitesInExpr(checked, r.cond, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &r.body, file, parent);
                },
                .num_for => |*f| {
                    try self.liftForeignConstantFieldSitesInExpr(checked, f.start, file, parent);
                    try self.liftForeignConstantFieldSitesInExpr(checked, f.stop, file, parent);
                    if (f.step) |step| try self.liftForeignConstantFieldSitesInExpr(checked, step, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &f.body, file, parent);
                },
                .gen_for => |*f| {
                    for (f.iters) |iter| try self.liftForeignConstantFieldSitesInExpr(checked, iter, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &f.body, file, parent);
                },
                .local_decl => |ld| for (ld.inits) |init_expr| try self.liftForeignConstantFieldSitesInExpr(checked, init_expr, file, parent),
                .global_decl => |gd| for (gd.inits) |init_expr| try self.liftForeignConstantFieldSitesInExpr(checked, init_expr, file, parent),
                .assign => |as| for (as.values) |val| try self.liftForeignConstantFieldSitesInExpr(checked, val, file, parent),
                .ret => |rs| for (rs.vals) |val| try self.liftForeignConstantFieldSitesInExpr(checked, val, file, parent),
                .expr_stmt => |es| try self.liftForeignConstantFieldSitesInExpr(checked, es.expr, file, parent),
                .call_stmt => |cs| try self.liftForeignConstantFieldSitesInExpr(checked, cs.expr, file, parent),
                else => {},
            }
        }
        // Single-line Idol bodies store the implicit return in tail_expr, not stmts.
        if (block.tail_expr) |tail| {
            try self.liftForeignConstantFieldSitesInExpr(checked, tail, file, parent);
        }
    }

    fn liftForeignConstantFieldSitesInExpr(
        self: *SemanticGraph,
        checked: *const sema.Sema,
        expr: *const Expr,
        file: []const u8,
        parent: id,
    ) anyerror!void {
        if (expr.* == .field) {
            if (checked.foreignModuleIntConstant(expr)) |content| {
                if (self.valueByAst(expr)) |existing| {
                    if (self.exactI64(existing) == null) {
                        const node = self.get(existing) orelse return;
                        if (node.descriptor == null or node.descriptor.? != .i64) {
                            self.nodes.items[existing].descriptor = .i64;
                        }
                        try self.publishExactI64(existing, content);
                    }
                } else {
                    const loc = expr.loc();
                    const value = try self.addChild(parent, .{
                        .kind = .value,
                        .span = .{ .file = file, .start = loc.line, .end = loc.col },
                        .descriptor = .i64,
                        .knowledge = .at_comptime,
                        .stage = .sema,
                        .ast_ref = @ptrCast(@constCast(expr)),
                    });
                    try self.publishExactI64(value, content);
                }
            }
        }
        switch (expr.*) {
            .binop => |b| {
                try self.liftForeignConstantFieldSitesInExpr(checked, b.lhs, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, b.rhs, file, parent);
            },
            .call => |c| {
                try self.liftForeignConstantFieldSitesInExpr(checked, c.func, file, parent);
                for (c.args) |arg| try self.liftForeignConstantFieldSitesInExpr(checked, arg, file, parent);
            },
            .method_call => |mc| {
                try self.liftForeignConstantFieldSitesInExpr(checked, mc.obj, file, parent);
                for (mc.args) |arg| try self.liftForeignConstantFieldSitesInExpr(checked, arg, file, parent);
            },
            .unop => |u| try self.liftForeignConstantFieldSitesInExpr(checked, u.operand, file, parent),
            .index => |ix| {
                try self.liftForeignConstantFieldSitesInExpr(checked, ix.obj, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, ix.key, file, parent);
            },
            .field => |f| try self.liftForeignConstantFieldSitesInExpr(checked, f.obj, file, parent),
            .table => |t| {
                for (t.fields) |field| switch (field) {
                    .indexed => |idx| {
                        try self.liftForeignConstantFieldSitesInExpr(checked, idx.key, file, parent);
                        try self.liftForeignConstantFieldSitesInExpr(checked, idx.val, file, parent);
                    },
                    .named => |nmd| try self.liftForeignConstantFieldSitesInExpr(checked, nmd.val, file, parent),
                    .positional => |val| try self.liftForeignConstantFieldSitesInExpr(checked, val, file, parent),
                    .spread => |src| try self.liftForeignConstantFieldSitesInExpr(checked, src, file, parent),
                    .semantic => |sem| try self.liftForeignConstantFieldSitesInExpr(checked, sem.val, file, parent),
                };
            },
            .if_expr => |ie| {
                try self.liftForeignConstantFieldSitesInExpr(checked, ie.cond, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, ie.then_expr, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, ie.else_expr, file, parent);
            },
            .try_expr => |t| try self.liftForeignConstantFieldSitesInExpr(checked, t.operand, file, parent),
            .unwrap_expr => |u| try self.liftForeignConstantFieldSitesInExpr(checked, u.operand, file, parent),
            .await_expr => |a| try self.liftForeignConstantFieldSitesInExpr(checked, a.operand, file, parent),
            .contains_expr => |c| {
                try self.liftForeignConstantFieldSitesInExpr(checked, c.lhs, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, c.rhs, file, parent);
            },
            .quote => |q| try self.liftForeignConstantFieldSitesInExpr(checked, q.expr, file, parent),
            .unquote => |q| try self.liftForeignConstantFieldSitesInExpr(checked, q.expr, file, parent),
            .sequence => |s| for (s.exprs) |item| try self.liftForeignConstantFieldSitesInExpr(checked, item, file, parent),
            .range => |r| {
                try self.liftForeignConstantFieldSitesInExpr(checked, r.start, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, r.end, file, parent);
                if (r.step) |step| try self.liftForeignConstantFieldSitesInExpr(checked, step, file, parent);
            },
            .list_comp => |lc| {
                try self.liftForeignConstantFieldSitesInExpr(checked, lc.value, file, parent);
                try self.liftForeignConstantFieldSitesInExpr(checked, lc.iter, file, parent);
                if (lc.filter) |filter| try self.liftForeignConstantFieldSitesInExpr(checked, filter, file, parent);
            },
            .macro_call => |m| for (m.args) |arg| try self.liftForeignConstantFieldSitesInExpr(checked, arg, file, parent),
            .match_expr => |m| {
                try self.liftForeignConstantFieldSitesInExpr(checked, m.scrutinee, file, parent);
                for (m.arms) |*arm| {
                    if (arm.guard) |guard| try self.liftForeignConstantFieldSitesInExpr(checked, guard, file, parent);
                    try self.liftForeignConstantFieldSites(checked, &arm.body, file, parent);
                }
            },
            else => {},
        }
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
        if (fd.path.len == 0) return error.MissingSemanticDeclaration;
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
        const checked_linkage = checked.callableLinkage(fd) orelse
            return error.MissingCallableLinkageFact;
        try self.publishCallableLinkage(func_id, checked_linkage);
        const foreign_type_name = switch (fd.func.ret_type) {
            .named => |n| n,
            else => null,
        };
        try self.addDescriptorShapeEdge(func_id, 0, foreign, self.nodes.items[func_id].result_descriptor.?, foreign_type_name);
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

    fn verifyCheckedApplicationOperandPacks(
        self: *const SemanticGraph,
        checked: *const sema.Sema,
    ) !void {
        for (self.application_facts.items) |fact| {
            const application_node = self.get(fact.application) orelse return error.InvalidApplicationFact;
            const raw = application_node.ast_ref orelse continue;
            const expr: *const Expr = @ptrCast(@alignCast(raw));
            const sema_fact = checked.applicationFact(expr) orelse continue;
            const graph_args = self.applicationArguments(fact.application) orelse
                return error.ApplicationArgumentPackInexact;
            if (graph_args.len != sema_fact.arguments.len)
                return error.ApplicationArgumentPackInexact;
            for (graph_args, sema_fact.arguments) |value_id, argument_expr| {
                const projected = self.valueExpression(value_id) orelse
                    return error.ApplicationArgumentPackInexact;
                if (projected != argument_expr) return error.ApplicationArgumentPackInexact;
            }
            if (sema_fact.subject) |subject_expr| {
                const graph_subject = self.applicationSubject(fact.application) orelse
                    return error.ApplicationArgumentPackInexact;
                const projected_subject = self.valueExpression(graph_subject) orelse
                    return error.ApplicationArgumentPackInexact;
                if (projected_subject != subject_expr) return error.ApplicationArgumentPackInexact;
            } else if (self.applicationSubject(fact.application) != null) {
                return error.ApplicationArgumentPackInexact;
            }
        }
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
        try checked.source_law_edition.validate();
        try self.root_source_law_edition.validate();
        if (!checked.source_law_edition.eql(.unknown)) {
            if (!self.root_source_law_edition.eql(.unknown) and
                !self.root_source_law_edition.eql(checked.source_law_edition))
            {
                return error.SourceLawEditionMismatch;
            }
            self.root_source_law_edition = checked.source_law_edition;
        }
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
            if (home_resolve_mod.homeOfPath(self.alloc, threaded.io(), file)) |h| {
                if (self.home) |old| self.alloc.free(old);
                self.home = h;
            } else |_| {}
        }
        const module = try self.liftModuleCalls(mod, file);
        self.callable_linkage_required = true;

        // Resolution owns boundary classification. Lift it onto the exact
        // callable ids before any application or effect consumer can run.
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const declaration = &stmt.func_decl;
            if (declaration.path.len != 1) continue;
            const relation = self.relationForDeclaration(declaration) orelse
                return error.MissingCallableLinkageFact;
            const linkage = checked.callableLinkage(declaration) orelse
                return error.MissingCallableLinkageFact;
            try self.publishCallableLinkage(relation, linkage);
        }

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
            const checked_fact = checked.applicationFact(expr);
            try self.liftCheckedApplicationOperandNames(checked, file, call_id, expr, checked_fact);
            const fact = checked_fact orelse continue;
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
                const result_type_name = switch (fact.target.func.ret_type) {
                    .named => |n| n,
                    else => null,
                };
                try self.addDescriptorShapeEdge(results[i], 0, relation_home, descriptor, result_type_name);
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
        try self.liftForeignConstantFieldSites(checked, &mod.body, file, module);
        try self.liftCaptureEdges(mod);
        // WORLDS FIRST, WHICH REVERSES THE PREVIOUS ORDER AND IS MEASURED.
        //
        // The effect fixpoint used to run first, and the reason recorded here
        // was that it "blocks a relation on any `.member` edge inside it, and a
        // world's member edges are the graph's record of exactly the reach it
        // means" — so publishing worlds first would move `effect` for a reason
        // unrelated to what the relation does.
        //
        // THAT FEAR IS FALSE AND THE GRAPH SAYS SO. A world member is added by
        // `addChild(world, …)` and the world is `addChild(module, …)`, so the
        // member edge's `from` is scoped to the MODULE. `enclosingCallable` of a
        // module-scoped entity is null, and the member scan drops it with
        // `orelse continue`. Not one world member edge can block a relation.
        //
        // What the old order DID cost is the whole subject of this lane: the
        // draw rows are the only POSITIVE evidence in the graph that an
        // application reaches a world, and running the effect pass before they
        // existed is exactly why `effect` could never say `one`. The census
        // control for the reversal is `effect none`, which must not move:
        // 1027/1317 on `examples`, 3646/5005 on `examples lib`.
        try self.publishApplicationWorlds(file);
        // MUTATION BEFORE EFFECT, because effect DERIVES from it. The mutation
        // column is the evidence; the effect card is the consequence. Reversing
        // them would have the consequence published before its evidence exists,
        // which is exactly how `effect: none` came to be a claim about world
        // observation masquerading as a claim about observability.
        try self.publishApplicationMutations();
        try self.publishApplicationEffects();
        try self.verifyCheckedApplicationOperandPacks(checked);
        // LAST, so every application operand has already claimed the literal
        // occurrence it names and this sweep reaches only what nothing else
        // does. Running it inside `liftModuleCalls` would have made the sweep
        // the owner of every checked operand literal instead.
        try self.liftLiteralFacts(file, module, &mod.body, true);
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

        // AUTHORITY for foreign-world applications. A call through the `c`
        // world is a foreign call — it is AUTHORIZED by the world, not
        // effect-free. This closes the gap that kept `c.abs(0-7)` blocked
        // without the graph-facts waiver: the world node exists now, so
        // `authority = .one(c_world)` can be written.
        //
        // THIS PASS NOW RUNS FIRST and `publishApplicationEffects` runs after,
        // so the effect pass no longer overwrites this row: it writes
        // `authority = .none` only where the card is still `.unknown`. One
        // exact authority identity, written once, by whichever pass has the
        // evidence.
        for (self.worlds.items) |world_fact| {
            if (world_fact.home != .c) continue;
            for (drawn.items) |row| {
                if (row.home != .c) continue;
                for (self.application_facts.items) |*fact| {
                    if (fact.application != row.application) continue;
                    fact.authority = .{ .one = world_fact.world };
                }
            }
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
                    // A DECLARED RELATION OF THE SAME SPELLING DOES NOT ANSWER
                    // FOR `@x`. The bare face yields to the declaration — that
                    // is the `findFunc` line — but the sigil names the world
                    // outright, and a graph that let the declaration win here
                    // published `world: none` over an occurrence the machine
                    // realizes as `getenv`. Measured on `env = (k) 99` followed
                    // by `@env("HOME")`: the program printed the environment
                    // variable and the graph said no world was drawn.
                    if (!n.world and self.findFunc(n.ident) != null) return .{ .home = null, .member = "" };
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
        // `publishNameBinding` is the one producer. `origins` remains a JSON
        // evidence projection for now, so derive it from that exact edge rather
        // than resolving the source spelling a second time.
        const binding = switch (self.valueOrigin(value)) {
            .one => |exact| exact,
            .unknown, .none => return,
        };
        const relation = self.enclosingCallable(caller) orelse caller;
        try self.origins.append(self.alloc, .{
            .value = value,
            .relation = relation,
            .binding = binding,
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
        /// THE EVIDENCE THAT AN OBSERVATION EXISTS, which `blocked` cannot
        /// carry and never could. `blocked` is one boolean over six conditions
        /// of two OPPOSITE kinds: four of them are absences of evidence (a
        /// foreign body, an unresolved call), and the graph learns nothing from
        /// them; the draw rows and the capture edges are evidence that the
        /// relation REACHES AN EXACT PLACE, which is a fact and not a hole.
        /// Collapsing both into `blocked` is why `ApplicationFact.effect` could
        /// publish `none` and `unknown` and never `one`.
        ///
        /// Exact entity of the first place the relation is proved to reach, in
        /// entity order — which is lift order, which is source order, so this
        /// is "the first observation in the body" and not an arbitrary pick.
        /// The relation may reach more; `one` is a cardinality statement about
        /// the EFFECT ("exactly one exact identity is known for it"), and a
        /// second reached place does not unknow the first.
        site: ?id = null,
        callees_start: u32 = 0,
        callees_len: u32 = 0,
    };

    /// DOES REACHING THIS WORLD OBSERVE ANYTHING OUTSIDE THE PROGRAM — asked of
    /// the world's OWN DECLARATION, not of a list kept here.
    ///
    /// `math.floor(x)` draws the `math` world and observes nothing. A
    /// `.realized` world provides exactly the relations the compiler realizes
    /// (`realizedBy(roster, m) == home`), so reaching one is reaching a pure
    /// projection of this program and grounding an effect on it is an
    /// over-claim. The first census of this pass caught precisely that: of 192
    /// positive sites, 24 were `math` and 2 were `string`, and not one of them
    /// is an observation.
    ///
    /// `.roster` and `.supplies` are the boundary. `os` members are the process
    /// environment; `io` supplies the standing streams. Reaching either
    /// observes state this program does not own.
    ///
    /// `c` IS EXCLUDED THOUGH ITS PROVISION IS A ROSTER. A foreign body is
    /// invisible, and invisible is `unknown` — the fact there is evidence for
    /// is `authority = .one(c_world)`, and `publishApplicationWorlds` already
    /// publishes exactly that.
    fn worldObservesOutside(self: *const SemanticGraph, world: id) bool {
        for (self.worlds.items) |fact| {
            if (fact.world != world) continue;
            if (fact.home == .c) return false;
            return switch (subject_home.declarationOf(fact.home).provides) {
                .realized => false,
                .roster, .supplies => true,
            };
        }
        return false;
    }

    /// Record an exact reached place on a relation's effect row, keeping the
    /// FIRST in entity order. Entity ids are assigned in lift order, so the
    /// kept witness is the first observation the body performs; a later one is
    /// not more exact, and swapping between them on a graph edit would move a
    /// published identity for no semantic reason.
    fn groundRow(row: *EffectRow, site: id) void {
        const existing = row.site orelse {
            row.site = site;
            return;
        };
        if (site < existing) row.site = site;
    }

    /// MUTATION, FOR EVERY APPLICATION OCCURRENCE — the closure over the call
    /// graph of the DIRECT writes the lift recorded in
    /// `SemanticGraph.binding_mutations`.
    ///
    /// WHY THIS IS A COLUMN AND NOT A FIELD ON `ApplicationFact`. The same
    /// reason `Draw` is: the occurrences that reach a write are frequently ones
    /// with no `ApplicationFact` at all, so a field there could not reach them.
    /// `law.md` §20-21.
    ///
    /// WHY IT IS NOT A `Draw`, WHICH IS THE ARCHITECTURAL LINE. A world SUPPLIES
    /// facts and confers reach; a module binding does neither. `_pos` is one
    /// `__DATA` word this file's own relations agree to share, and reading a
    /// write to it as an ambient-world draw would say every relation that bumps
    /// a counter exercises world authority. World draw, binding mutation and
    /// the effect consequence are THREE columns, and admissibility is derived
    /// from them rather than read off any one of them.
    ///
    /// THE LATTICE IS LEAST AND `unknown` IS TOP. A relation whose body this
    /// pass cannot follow — an unresolved callee, a foreign body — reaches
    /// `.unknown`, which is not `.none` and not `.many`: it is the absence of
    /// an answer, and every consumer must refuse on it. `.none` is the POSITIVE
    /// claim that no module binding is written, and the whole of GAP-225 is
    /// what happens when a pass publishes a positive claim it did not prove.
    fn publishApplicationMutations(self: *SemanticGraph) !void {
        const node_count = self.nodes.items.len;
        if (node_count == 0) return;
        if (mutationSevered()) return;

        const reach = try self.alloc.alloc(std.ArrayListUnmanaged(id), node_count);
        defer {
            for (reach) |*list| list.deinit(self.alloc);
            self.alloc.free(reach);
        }
        for (reach) |*list| list.* = .empty;

        var opaque_body = try std.DynamicBitSetUnmanaged.initEmpty(self.alloc, node_count);
        defer opaque_body.deinit(self.alloc);

        // SEED ONE: the lift's direct writes.
        for (self.binding_mutations.items) |write| {
            if (write.relation >= node_count) continue;
            try noteBinding(self.alloc, &reach[write.relation], write.binding);
        }

        // SEED TWO: a body whose callees this graph cannot name. A foreign
        // body is the same case — its writes are somebody else's source.
        for (self.callable_linkages.items) |fact| {
            if (fact.origin != .c) continue;
            if (fact.callable < node_count) opaque_body.set(fact.callable);
        }

        var edges: std.ArrayListUnmanaged(struct { caller: id, callee: id }) = .empty;
        defer edges.deinit(self.alloc);
        var candidate: usize = 0;
        while (candidate < self.application_candidates.bit_length) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const site = std.math.cast(id, candidate) orelse break;
            const node = self.get(site) orelse continue;
            const caller = self.enclosingCallable(node.scope orelse continue) orelse continue;
            if (caller >= node_count) continue;
            const callee = self.applicationRelation(site) orelse {
                // AN UNRESOLVED CALL IS NOT A PROOF OF PURITY. The string faces
                // `publishApplicationEffects` exempts are exempt here for the
                // same measured reason: they lower through bootstrap rules
                // rather than a published relation id, and a string is
                // immutable, so no module binding is reachable through one.
                if (!self.unobservableStringFace(site)) opaque_body.set(caller);
                continue;
            };
            if (callee >= node_count) {
                opaque_body.set(caller);
                continue;
            }
            try edges.append(self.alloc, .{ .caller = caller, .callee = callee });
        }

        var spread = true;
        while (spread) {
            spread = false;
            for (edges.items) |edge| {
                if (opaque_body.isSet(edge.callee) and !opaque_body.isSet(edge.caller)) {
                    opaque_body.set(edge.caller);
                    spread = true;
                }
                for (reach[edge.callee].items) |binding| {
                    if (hasBinding(reach[edge.caller].items, binding)) continue;
                    try noteBinding(self.alloc, &reach[edge.caller], binding);
                    spread = true;
                }
            }
        }

        candidate = 0;
        while (candidate < self.application_candidates.bit_length) : (candidate += 1) {
            if (!self.application_candidates.isSet(candidate)) continue;
            const site = std.math.cast(id, candidate) orelse break;
            const card: MutationCard = card: {
                const callee = self.applicationRelation(site) orelse {
                    if (self.unobservableStringFace(site)) break :card .none;
                    break :card .unknown;
                };
                if (callee >= node_count) break :card .unknown;
                if (opaque_body.isSet(callee)) break :card .unknown;
                const bindings = reach[callee].items;
                if (bindings.len == 0) break :card .none;
                if (bindings.len == 1) break :card .{ .one = bindings[0] };
                const start = self.mutation_places.items.len;
                try self.mutation_places.appendSlice(self.alloc, bindings);
                break :card .{ .many = try factRange(start, bindings.len) };
            };
            try self.mutation_closure.append(self.alloc, .{ .application = site, .place = card });
        }
    }

    fn hasBinding(list: []const id, binding: id) bool {
        for (list) |existing| if (existing == binding) return true;
        return false;
    }

    fn noteBinding(
        alloc: std.mem.Allocator,
        list: *std.ArrayListUnmanaged(id),
        binding: id,
    ) !void {
        if (hasBinding(list.items, binding)) return;
        try list.append(alloc, binding);
    }

    /// The module-scope bindings one application can reach a write to.
    /// `.unknown` when nothing decided — never a claim that it writes nothing.
    pub fn mutation(self: *const SemanticGraph, occurrence: id) MutationCard {
        for (self.mutation_closure.items) |row| {
            if (row.application == occurrence) return row.place;
        }
        return .unknown;
    }

    /// TRUE WHEN SOME RELATION IN THIS MODULE WRITES THE MODULE-SCOPE BINDING
    /// SPELLED `name`.
    ///
    /// The question a consumer asks before treating a module binding's
    /// initializer as the binding's VALUE. `comptime.foldRelationBody` bound
    /// every module-scope initializer it could evaluate into the fold's scope
    /// and read the answer back as a constant — sound for a binding nothing
    /// writes, and a WRONG ANSWER for one a relation advances. Measured before
    /// this query existed: `ring = 0` with a `bump` that increments it, and a
    /// zero-operand relation whose whole body is `peek()`, folded to 0 where
    /// the program answers 1.
    ///
    /// NAME-KEYED because that is the face a fold's scope is built in, and the
    /// lookup is at the source-resolution boundary where a name is lawful. The
    /// answer is derived from exact binding entities, never from spellings.
    pub fn moduleBindingWritten(self: *const SemanticGraph, name: []const u8) bool {
        const root = self.module_root orelse return false;
        for (self.binding_mutations.items) |write| {
            const binding = self.get(write.binding) orelse continue;
            if (binding.scope != root) continue;
            const binding_name = binding.name orelse continue;
            if (std.mem.eql(u8, binding_name, name)) return true;
        }
        return false;
    }

    /// TRUE WHEN A MODULE BINDING'S INITIALIZER IS ITS VALUE EVERYWHERE —
    /// nothing in the module writes it, so a reader may be answered from the
    /// declaration. The question `comptime.foldRelationBody` asks before
    /// binding an initializer into the fold's scope as a constant.
    ///
    /// SEVERED BY THE COUNTERFACTUAL, AND `moduleBindingWritten` IS NOT.
    /// `dnir_lower.collectModuleGlobals` asks the raw fact to decide whether a
    /// binding needs a `__DATA` word, and that is a physical requirement of the
    /// program rather than a licence anything reads: a control able to delete
    /// it BREAKS THE COMPILER instead of moving a decision, which is the one
    /// thing `gate/effect.sh` says a sever may never do. Measured — with the
    /// storage query severed too, a program whose module binding a relation
    /// writes stopped lowering at `lowerExprCons`. So the sever reaches exactly
    /// the licences: this one, and the two loops in `publishApplicationEffects`.
    pub fn moduleBindingConstant(self: *const SemanticGraph, name: []const u8) bool {
        if (mutationSevered()) return true;
        return !self.moduleBindingWritten(name);
    }

    /// The exact bindings a card names, whatever its arity. Empty for `.none`
    /// and for `.unknown` — the two are distinguished by the CARD, and a
    /// consumer that reads only this slice is reading the wrong question.
    pub fn mutationPlaces(self: *const SemanticGraph, card: MutationCard, one: *[1]id) []const id {
        return switch (card) {
            .unknown, .none => &.{},
            .one => |binding| blk: {
                one[0] = binding;
                break :blk one[0..1];
            },
            .many => |range| self.mutation_places.items[range.start .. range.start + range.len],
        };
    }

    /// Publication of the mutation column severed at the producer, for the
    /// counterfactual control. Every application reads `mutation: unknown` and
    /// nothing else moves — `binding_mutations` is still lifted, `effect` is still
    /// published by its own pass off whatever the severed column says.
    /// `IDOL_MUTATION_SEVER` is classed `.affects` in `main.behaviourEnvClass`
    /// because it changes the artifact, which is the point of the control.
    fn mutationSevered() bool {
        return std.c.getenv("IDOL_MUTATION_SEVER") != null;
    }

    /// Publication of `ApplicationFact.effect` severed at the producer, for the
    /// counterfactual control. Every application reads `effect: unknown` and
    /// NOTHING ELSE MOVES — `authority` is still published, which is what makes
    /// the control isolate one fact instead of two. `IDOL_EFFECT_SEVER` is
    /// classed `.affects` in `main.behaviourEnvClass` because it does change
    /// the artifact — that is the entire point of a severing control.
    fn effectSevered() bool {
        return std.c.getenv("IDOL_EFFECT_SEVER") != null;
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
    /// had to assume the worst. This is the write site.
    ///
    /// IT USED TO PUBLISH EXACTLY ONE VALUE, AND THAT WAS THE DEFECT. Measured
    /// at ce03c7eb over `examples`: 1317 published applications, 1027 `none`,
    /// 290 `unknown`, and `one` ZERO — the same shape over `examples lib`
    /// (5005 / 3646 / 1359 / 0). A fact whose positive case is unreachable is
    /// not an effect fact; it is a purity fact wearing the name. It can refuse
    /// a transformation and it can license one, but it can never say WHICH
    /// observation stands in the way, so every consumer that needs to
    /// distinguish "this reads the `os` world" from "nobody looked" has to
    /// treat both as the worst case. CSE, hoisting, fusion and speculation all
    /// need exactly that distinction.
    ///
    /// THE POSITIVE CASE HAS EVIDENCE, and it was already in the graph:
    ///
    ///   - a DRAW row with `world == .one(W)` says this application occurrence
    ///     reaches world `W` — `env("HOME")`, `print(v)`, `clock()`. 261 such
    ///     rows over `examples lib`, and not one of them was reaching `effect`;
    ///   - a `.capture` edge says the relation reads an exact binding from an
    ///     enclosing frame, which is a place it does not own.
    ///
    /// Both name an EXACT ENTITY, so both publish `effect = .one(entity)`. The
    /// remaining three blocking conditions — a foreign body, an unresolved
    /// call, a `.member` edge the pass cannot see through — are absences of
    /// evidence and keep publishing `.unknown`, which is the honest answer and
    /// not a sentinel. `unknown != none != one` all the way down.
    ///
    /// WHAT `one` CLAIMS, EXACTLY. "This application can reach an observation
    /// of entity E." It is a MAY-fact with a witness, which is what an effect
    /// fact is everywhere: `.none` proves no observation is reachable, `.one`
    /// exhibits one that is, `.unknown` has looked and found neither proof. A
    /// relation that is both positively grounded and partly hidden publishes
    /// `.one`: a proved observation is not unproved by an unexamined body.
    ///
    /// A relation is EFFECT-FREE when all of these hold:
    ///   1. its callable linkage origin is not C;
    ///   2. every application candidate whose caller is this relation RESOLVED
    ///      to a published fact — an unresolved candidate is a call the graph
    ///      could not identify, and `print("hi")` is measured to be exactly
    ///      that shape (a `.call` node in `unresolved_applications`);
    ///   3. every callee it does resolve is itself effect-free;
    ///   4. it captures nothing — a `.capture` edge is the graph's own record
    ///      of reaching outside the frame;
    ///   5. it writes no module binding — `binding_mutations` names the exact
    ///      binding rather than treating an assignment as a fresh local;
    ///   6. nothing inside it reads a static `.member` — the injected world
    ///      arrives as member edges, so this is where `env`/`arg`/`clock` land.
    ///
    /// The fixpoint is LEAST: nothing starts effect-free and a relation is only
    /// promoted once all of its callees already are, so a recursive relation is
    /// never promoted at all. That is a missed fact. The opposite error — a
    /// greatest fixpoint that starts optimistic — publishes "pure" about
    /// something impure the moment any of the six conditions is incomplete,
    /// and this tree has shipped two silent miscompiles already.
    ///
    /// AUTHORITY rides on the same evidence deliberately: a relation that
    /// applies nothing foreign, resolves every call it makes, captures nothing
    /// and reads no world member cannot be exercising authority either. When
    /// authority acquires evidence of its own — a capability fact rather than
    /// the absence of one — it separates from this and gets its own predicate.
    fn publishApplicationEffects(self: *SemanticGraph) !void {
        const node_count = self.nodes.items.len;
        if (node_count == 0) return;

        var foreign = try std.DynamicBitSetUnmanaged.initEmpty(self.alloc, node_count);
        defer foreign.deinit(self.alloc);
        for (self.callable_linkages.items) |fact| {
            if (fact.origin != .c) continue;
            if (fact.callable < foreign.bit_length) foreign.set(fact.callable);
        }

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

        // Condition 6, then 4: a member read or a capture blocks the relation
        // it sits inside, whichever relation that is.
        //
        // A CAPTURE ALSO GROUNDS THE EFFECT, and a member does not. The two
        // were one line because both only ever had to answer "blocked". They
        // are not the same fact: `edge.to` on a capture is the exact outer
        // binding the relation reads, which is a place; `edge.to` on a member
        // is a field of a descriptor home declared inside the body, which is
        // a shape and observes nothing. Blocking on the second stays (it is
        // the conservative reading of a body this pass does not model), but it
        // publishes no positive claim.
        for (self.edges.items) |edge| {
            if (edge.kind != .member and edge.kind != .capture) continue;
            const holder = self.enclosingCallable(edge.from) orelse continue;
            const row = row_of.get(holder) orelse continue;
            rows.items[row].blocked = true;
            if (edge.kind == .capture) groundRow(&rows.items[row], edge.to);
        }

        // THE DRAW ROWS, which is where the positive evidence actually lives.
        //
        // `publishApplicationWorlds` runs before this pass now and keys one
        // row per application CANDIDATE — published or not — with the exact
        // world entity it reaches. An occurrence that draws `os` reads the `os`
        // world; the relation the occurrence sits in performs that read. This
        // is the only place in the compiler where "an effect exists" is
        // established rather than failed to be refuted.
        for (self.draws.items) |draw| {
            const world = switch (draw.world) {
                .one => |w| w,
                .unknown, .none => continue,
            };
            const node = self.get(draw.application) orelse continue;
            const holder = self.enclosingCallable(node.scope orelse continue) orelse continue;
            const row = row_of.get(holder) orelse continue;
            rows.items[row].blocked = true;
            if (self.worldObservesOutside(world)) groundRow(&rows.items[row], world);
        }

        // THE MUTATION COLUMN, WHICH IS THE SIXTH GROUND AND WAS MISSING.
        //
        // The five grounds above answer ONE question — "does this body observe
        // the outside world" — and `effect: none` was published as though the
        // answer were "does this body perform an observable action". A write to
        // a module-scope binding is observable to every later relation that
        // reads that binding, and it is none of the five: not a C linkage, not
        // a capture (the binding is not captured, it is named), not a static
        // member, not an unresolved call, and not a blocked callee. The lift
        // hid it further by minting a same-spelled local, so the graph could
        // not see the write at all. gaps/GAP-225.md.
        //
        // THE DERIVATION, and it is a derivation rather than a fold: mutation
        // BLOCKS (a mutating relation is not provably unobservable) and it
        // GROUNDS at the exact binding written (which observation stands in the
        // way). Blocking alone would publish `unknown` and lose the name of the
        // place; grounding alone would license the transform. World draw and
        // binding mutation stay separate columns and both feed this one card.
        // THE DIRECT ROWS GROUND FIRST, and they have to. A relation that
        // writes `_pos` AND also applies something the graph could not resolve
        // has closure card `.unknown` — honest about the CARDINALITY, since
        // there may be writes behind the unresolved call — but the binding it
        // demonstrably writes is still known, and dropping it would trade an
        // exact place for a shrug. Measured: 18 `one` cards became `unknown`
        // corpus-wide when the closure was the only grounding source.
        //
        // BOTH LOOPS ARE UNDER ONE SEVER. `mutationSevered()` already empties
        // the closure column at its producer; if the direct rows kept feeding
        // this pass, `IDOL_MUTATION_SEVER=1` would remove half a fact and the
        // control would measure the half. Measured: with only the closure
        // severed, `lib/compiler/comptime.id` still refused its arms on
        // `effect-not-none` and `gate/speculation.sh` could not show that the
        // mutation fact is what refuses them.
        const mutation_severed = mutationSevered();
        if (!mutation_severed) for (self.binding_mutations.items) |write| {
            const target = row_of.get(write.relation) orelse continue;
            rows.items[target].blocked = true;
            groundRow(&rows.items[target], write.binding);
        };

        // THEN THE CLOSURE, which adds what a direct row cannot say: a relation
        // that writes nothing itself but APPLIES one that does is grounded at
        // the binding it reaches, and one whose callees this pass could not
        // follow is blocked with no place named. `.none` is the only card that
        // licenses anything, and it is a positive claim.
        for (self.mutation_closure.items) |row| {
            const callee = self.applicationRelation(row.application) orelse continue;
            const target = row_of.get(callee) orelse continue;
            switch (row.place) {
                .none => {},
                .unknown => rows.items[target].blocked = true,
                .one => |binding| {
                    rows.items[target].blocked = true;
                    groundRow(&rows.items[target], binding);
                },
                .many => |range| {
                    rows.items[target].blocked = true;
                    // The LOWEST binding id the set names — `groundRow`'s own
                    // tie-break, applied here so the choice is the same one it
                    // would make. `Card` holds one site and the exact set is
                    // already published in the closure column, so naming one
                    // here loses nothing a consumer cannot recover.
                    for (self.mutation_places.items[range.start .. range.start + range.len]) |binding| {
                        groundRow(&rows.items[target], binding);
                    }
                },
            }
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

        // THE POSITIVE FIXPOINT, and it is the same shape as BAD for the same
        // reason. GROUNDED is the least set that contains every relation with
        // an exact reached place and is closed under "applies a relation in
        // GROUNDED" — a caller of something that reads the `os` world can
        // itself reach that read. It is least, so a cycle none of whose members
        // is grounded stays ungrounded, and the witness carried along the edge
        // is the callee's, which is the place actually reached.
        //
        // BAD and GROUNDED are not complements and must not be collapsed into
        // one three-valued pass. A relation can be in BAD and not in GROUNDED
        // (an unresolved call: blocked, nothing known) and it can be in both (a
        // world read: blocked, and exactly what it reads is known). Only the
        // pair distinguishes "no fact" from "this fact".
        const grounded_site = try self.alloc.alloc(?id, node_count);
        defer self.alloc.free(grounded_site);
        @memset(grounded_site, null);
        for (rows.items) |row| {
            if (row.site) |site| grounded_site[row.relation] = site;
        }
        spread = true;
        while (spread) {
            spread = false;
            for (rows.items) |row| {
                if (grounded_site[row.relation] != null) continue;
                const start: usize = row.callees_start;
                for (callees.items[start .. start + row.callees_len]) |callee| {
                    if (callee >= node_count) continue;
                    const site = grounded_site[callee] orelse continue;
                    grounded_site[row.relation] = site;
                    spread = true;
                    break;
                }
            }
        }

        // THE SEVER GUARDS THE EFFECT WRITES AND NOTHING ELSE.
        //
        // It was an early `return` from this whole loop, which also suppressed
        // the `authority = .none` write below — and `effectFreeApplications`
        // reads BOTH cards, so the counterfactual was removing two facts and
        // attributing the difference to one. A control that severs more than
        // it names proves nothing about the thing it names.
        const severed = effectSevered();

        for (self.application_facts.items) |*fact| {
            const callee = self.applicationRelation(fact.application) orelse continue;
            if (callee < effect_free.bit_length and effect_free.isSet(callee)) {
                if (!severed) fact.effect = .none;
                // NOT AN UNCONDITIONAL WRITE, because this pass now runs AFTER
                // `publishApplicationWorlds` and that pass owns
                // `authority = .one(c_world)` for a foreign-world application.
                // Under the old order the worlds pass wrote last and won; the
                // reversal would otherwise have this one erase an exact
                // authority identity with `none`, which is a wrong fact and not
                // a lost one.
                //
                // AND IT IS OUTSIDE THE SEVER, deliberately: authority is a
                // different fact with different evidence, and the control is
                // for the effect card.
                if (fact.authority == .unknown) fact.authority = .none;
                continue;
            }
            if (callee >= node_count) continue;
            if (severed) continue;
            // AUTHORITY IS NOT WRITTEN HERE. `publishApplicationWorlds` owns
            // `authority = .one(c_world)` and `law.fact.producer.one` means one
            // of us writes it, not both. Effect and authority rode the same
            // evidence only while that evidence was a single boolean.
            if (grounded_site[callee]) |site| fact.effect = .{ .one = site };
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
            .binding => "binding",
            .member => "member",
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
            // DECLARATION OR ASSIGNMENT. Two relation bodies that write `M.x`
            // export identical rows under v9 — same shape, same region, same
            // accesses — while one of them declares its own `M` and the other
            // writes the module's. A reader adjudicating which storage a field
            // write reaches cannot get there from any other published key.
            try buf.appendSlice(alloc, "\",\"bind_origin\":\"");
            try buf.appendSlice(alloc, @tagName(p.bind_origin));
            try buf.appendSlice(alloc, "\",\"determinacy\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.determinacy));
            try buf.appendSlice(alloc, "\",\"mutation\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.mutation));
            // THE THREE FACTS THE FOLD ACTUALLY TURNS ON, and until v9 the only
            // ones it consults that this projection did not publish.
            // `aggregateIsSoleImmutableBinding` reads six place inputs — shape,
            // mutation, immutability, alias, escape, bind count — and v8
            // published three of them. A reader holding a v8 export could see
            // `mutation:"no"` on a place the predicate had just refused and had
            // no way to learn why, so REPRODUCING AN ADMISSION DECISION FROM THE
            // EXPORT WAS IMPOSSIBLE. Measured while auditing that predicate over
            // the corpus: the 77 admission attempts had to be attributed with an
            // instrumented compiler because these keys were absent, and an
            // instrumented build is a second store that rots the moment it is
            // deleted. Absence of a key is not the same answer as `"unknown"`
            // (see the version note above), so these are published, never
            // inferred.
            try buf.appendSlice(alloc, "\",\"immutability\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.immutability));
            try buf.appendSlice(alloc, "\",\"alias\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.alias));
            try buf.appendSlice(alloc, "\",\"contents_known\":\"");
            try buf.appendSlice(alloc, @tagName(p.facts.contents_known));
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
                try buf.appendSlice(alloc, ",\"binding\":");
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
                    try buf.appendSlice(alloc, ",\"binding\":");
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
            // The DERIVED effect for this occurrence. Projected here and not
            // stored, because `ApplicationFact.effect` cannot reach a
            // world-drawing occurrence at all: measured, 381 draws name a world
            // and 0 of them have an `ApplicationFact`. See `applicationEffect`.
            try appendCardJson(buf, alloc, "effect", self.applicationEffect(draw.application));
            try buf.append(alloc, '}');
        }
        // THE CLOSURE, PROJECTED BESIDE ITS EVIDENCE. `mutations` below is what
        // the LIFT saw — this relation's body assigns this exact module
        // binding — and it is POSITIVE ONLY, so the absence of a row means
        // `none` and `unknown` at the same time. This column is the closure
        // over the call graph, keyed by the occurrence, and it says which. A
        // reader given only the rows has to walk the call graph itself, which
        // is the reconstruction this column exists to end; a reader given only
        // the closure cannot tell a direct write from a reached one.
        try buf.appendSlice(alloc, "],\"mutation_closure\":[");
        for (self.mutation_closure.items, 0..) |row, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"application\":");
            try appendJsonInt(buf, alloc, row.application);
            try buf.appendSlice(alloc, ",\"mutation\":{\"card\":\"");
            try buf.appendSlice(alloc, row.place.name());
            try buf.append(alloc, '"');
            var one: [1]id = undefined;
            const bindings = self.mutationPlaces(row.place, &one);
            if (bindings.len > 0) {
                try buf.appendSlice(alloc, ",\"bindings\":");
                try appendIdsJson(buf, alloc, bindings);
            }
            try buf.appendSlice(alloc, "}}");
        }
        // RANGES ARE PROJECTED, which is the point of moving them here. The
        // proof used to be a boolean on one backend's instruction and no other
        // realization could see it; every projection reads this column.
        try buf.appendSlice(alloc, "],\"ranges\":[");
        for (self.ranges.items, 0..) |fact, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"subject\":");
            try appendJsonInt(buf, alloc, fact.subject);
            try buf.appendSlice(alloc, ",\"nonneg_width\":");
            try appendJsonInt(buf, alloc, fact.nonneg_width);
            try buf.append(alloc, '}');
        }
        try buf.appendSlice(alloc, "],\"origins\":[");
        for (self.origins.items, 0..) |origin, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"value\":");
            try appendJsonInt(buf, alloc, origin.value);
            try buf.appendSlice(alloc, ",\"relation\":");
            try appendJsonInt(buf, alloc, origin.relation);
            try buf.appendSlice(alloc, ",\"binding\":");
            try appendJsonInt(buf, alloc, origin.binding);
            try buf.append(alloc, '}');
        }
        try buf.appendSlice(alloc, "],\"mutations\":[");
        for (self.binding_mutations.items, 0..) |write, i| {
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"relation\":");
            try appendJsonInt(buf, alloc, write.relation);
            try buf.appendSlice(alloc, ",\"binding\":");
            try appendJsonInt(buf, alloc, write.binding);
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
        try buf.appendSlice(alloc, ",\"source_quote\":[");
        for (self.source_quote_facts.items, 0..) |fact, i| {
            if (self.sourceQuote(fact.value) == null) return error.InvalidSourceQuoteFact;
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"value\":");
            try appendJsonInt(buf, alloc, fact.value);
            try buf.appendSlice(alloc, ",\"quote\":\"");
            try buf.appendSlice(alloc, @tagName(fact.quote));
            try buf.appendSlice(alloc, "\"}");
        }
        try buf.append(alloc, ']');
    }

    fn appendCallableLinkagesJson(
        self: *const SemanticGraph,
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
    ) !void {
        try buf.appendSlice(alloc, ",\"callable_linkages\":[");
        for (self.callable_linkages.items, 0..) |fact, i| {
            const published = self.callableLinkage(fact.callable) orelse
                return error.InvalidCallableLinkageFact;
            if (published.callable != fact.callable or
                published.origin != fact.origin or
                published.exposure != fact.exposure or
                !std.mem.eql(u8, published.symbol, fact.symbol))
            {
                return error.InvalidCallableLinkageFact;
            }
            if (i > 0) try buf.append(alloc, ',');
            try buf.appendSlice(alloc, "{\"callable\":");
            try appendJsonInt(buf, alloc, fact.callable);
            try buf.appendSlice(alloc, ",\"origin\":\"");
            try buf.appendSlice(alloc, @tagName(fact.origin));
            try buf.appendSlice(alloc, "\",\"exposure\":\"");
            try buf.appendSlice(alloc, @tagName(fact.exposure));
            try buf.appendSlice(alloc, "\",\"symbol\":\"");
            try jsonEscapeAppend(buf, alloc, fact.symbol);
            try buf.appendSlice(alloc, "\"}");
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
        try self.root_source_law_edition.validate();
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
        // version 7: `source_quote`. Version 6 collapsed every lifted `.quoted`
        // value to a bare `.str` descriptor with no producer quote identity.
        // version 8: node `scope` replaces duplicate containment edges;
        // qualified descriptor links use the canonical `descriptor` relation.
        //
        // version 9: `places[]` rows gain `immutability`, `alias` and
        // `contents_known`. Version 8 published `mutation` and `escape` but not
        // the three siblings `aggregateIsSoleImmutableBinding` reads alongside
        // them, so no v8 reader could reproduce that predicate's answer — the
        // one predicate that decides whether an aggregate projection is
        // published at all AND whether realization may fold it. The bump is what
        // lets a v8 reader know it was not being told, rather than read a
        // missing key as agreement.
        //
        // version 10: `places[]` rows gain `bind_origin`. Version 9 published
        // every place fact a realization reads EXCEPT whether the binding
        // statement declared the name or assigned to one the enclosing scope
        // already owns, and those two answers select different STORAGE for the
        // same spelling. Measured at 09b20611: a module table owning field
        // storage and shadowed by a relation-local declaration answered the
        // shadow's write from the module's word, and no v9 export distinguished
        // the shadow from a plain module write.
        // version 11: exact `root_source_law` edition. Imported source positions
        // need their own source/home facts before mixed-law closure can be claimed.
        // version 12: `callable_linkages`. Version 11 forced every graph/tool
        // consumer to rederive physical origin/exposure/symbol from declaration
        // spellings even though checked realization consumed the graph fact.
        // version 13: `mutations`. Version 12 could publish a module place as
        // mutated but could not identify which relation wrote its binding, so
        // the effect producer treated those relations as unobservable.
        //
        // version 14: `mutation_closure`. Version 13's `mutations` rows are
        // POSITIVE only — a row says a relation writes a binding, and the
        // absence of one is `none` and `unknown` at the same time. A reader
        // cannot tell "this relation writes nothing" from "this pass could not
        // follow its callees", and those license opposite decisions. The
        // closure column carries the cardinality explicitly, keyed by the
        // application, so `unknown != absent != none`. gaps/GAP-225.md.
        try out.appendSlice(alloc, "{\"schema\":\"sim-v0\",\"version\":14,\"file\":\"");
        try jsonEscapeAppend(out, alloc, file);
        try out.append(alloc, '"');
        switch (self.root_source_law_edition) {
            .exact => |edition| {
                try out.appendSlice(alloc, ",\"root_source_law\":{\"card\":\"one\",\"family\":\"");
                try jsonEscapeAppend(out, alloc, edition.family);
                try out.appendSlice(alloc, "\",\"schema\":\"");
                try jsonEscapeAppend(out, alloc, edition.schema);
                try out.appendSlice(alloc, "\",\"sha256\":\"");
                try jsonEscapeAppend(out, alloc, edition.sha256);
                try out.appendSlice(alloc, "\"}");
            },
            .foreign_unversioned => try out.appendSlice(alloc, ",\"root_source_law\":{\"card\":\"unknown\",\"family\":\"foreign\"}"),
            .unknown => try out.appendSlice(alloc, ",\"root_source_law\":{\"card\":\"unknown\"}"),
        }
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
            if (node.scope) |scope| {
                try out.appendSlice(alloc, ",\"scope\":");
                try appendJsonInt(out, alloc, scope);
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
            if (edge.kind == .descriptor) {
                for (self.qualified.of(edge.from)) |hit| {
                    if (hit.to != edge.to or !hit.embedded) continue;
                    try out.appendSlice(alloc, ",\"inline\":true");
                    break;
                }
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
        try out.append(alloc, ']');
        try self.appendCallableLinkagesJson(out, alloc);
        try out.appendSlice(alloc, ",\"unresolved_applications\":[");
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
    try std.testing.expectEqual(@as(usize, 0), graph.edges.items.len);
    try std.testing.expectEqual(parent, graph.homeOf(child).?);
    try std.testing.expectEqualSlices(id, &.{child}, graph.nested.of(parent));
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
    checked.source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
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

test "semantic_graph: source-law edition preserves knowledge and refuses conflict" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\edition_probe = 1
    ;
    var lex = Lexer.init(src, "edition.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    checked.source_law_edition = lex.source_law_edition;
    try checked.check_module(&module);

    var retained = SemanticGraph.init(alloc);
    defer retained.deinit();
    _ = try retained.liftModuleWithCheckedCalls(&module, &checked, "edition.id");
    try std.testing.expect(retained.root_source_law_edition.eql(authority_projection.SourceLawEdition.idolCurrent()));

    var current_json: std.ArrayListUnmanaged(u8) = .empty;
    defer current_json.deinit(alloc);
    try retained.writeJson(alloc, "edition.id", &current_json, null);
    var current_parsed = try std.json.parseFromSlice(std.json.Value, alloc, current_json.items, .{});
    defer current_parsed.deinit();
    const current_law = current_parsed.value.object.get("root_source_law").?.object;
    try std.testing.expectEqualStrings("one", current_law.get("card").?.string);
    try std.testing.expectEqualStrings("idol", current_law.get("family").?.string);
    try std.testing.expectEqualStrings(authority_projection.source_law_schema, current_law.get("schema").?.string);
    try std.testing.expectEqualStrings(authority_projection.source_law_sha256, current_law.get("sha256").?.string);

    const historical: authority_projection.SourceLawEdition = .{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.historical-test",
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    } };
    checked.source_law_edition = historical;
    var historical_graph = SemanticGraph.init(alloc);
    defer historical_graph.deinit();
    _ = try historical_graph.liftModuleWithCheckedCalls(&module, &checked, "edition.id");
    try std.testing.expect(historical_graph.root_source_law_edition.eql(historical));
    var historical_json: std.ArrayListUnmanaged(u8) = .empty;
    defer historical_json.deinit(alloc);
    try historical_graph.writeJson(alloc, "edition.id", &historical_json, null);
    var historical_parsed = try std.json.parseFromSlice(std.json.Value, alloc, historical_json.items, .{});
    defer historical_parsed.deinit();
    const historical_law = historical_parsed.value.object.get("root_source_law").?.object;
    try std.testing.expectEqualStrings("one", historical_law.get("card").?.string);
    try std.testing.expectEqualStrings("idol.source.law.historical-test", historical_law.get("schema").?.string);
    try std.testing.expectEqualStrings(historical.sha256().?, historical_law.get("sha256").?.string);

    checked.source_law_edition = .foreign_unversioned;
    var foreign_graph = SemanticGraph.init(alloc);
    defer foreign_graph.deinit();
    _ = try foreign_graph.liftModuleWithCheckedCalls(&module, &checked, "edition.lua");
    var foreign_json: std.ArrayListUnmanaged(u8) = .empty;
    defer foreign_json.deinit(alloc);
    try foreign_graph.writeJson(alloc, "edition.lua", &foreign_json, null);
    var foreign_parsed = try std.json.parseFromSlice(std.json.Value, alloc, foreign_json.items, .{});
    defer foreign_parsed.deinit();
    const foreign_law = foreign_parsed.value.object.get("root_source_law").?.object;
    try std.testing.expectEqualStrings("unknown", foreign_law.get("card").?.string);
    try std.testing.expectEqualStrings("foreign", foreign_law.get("family").?.string);
    try std.testing.expect(foreign_law.get("schema") == null);
    try std.testing.expect(foreign_law.get("sha256") == null);

    var malformed_graph = SemanticGraph.init(alloc);
    defer malformed_graph.deinit();
    malformed_graph.root_source_law_edition = .{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.v1",
        .sha256 = "not-a-sha256",
    } };
    var malformed_json: std.ArrayListUnmanaged(u8) = .empty;
    defer malformed_json.deinit(alloc);
    try std.testing.expectError(
        error.InvalidSourceLawEdition,
        malformed_graph.writeJson(alloc, "edition.id", &malformed_json, null),
    );

    var conflicting = SemanticGraph.init(alloc);
    defer conflicting.deinit();
    conflicting.root_source_law_edition = .foreign_unversioned;
    checked.source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
    try std.testing.expectError(
        error.SourceLawEditionMismatch,
        conflicting.liftModuleWithCheckedCalls(&module, &checked, "edition.id"),
    );
}

test "semantic_graph: module tail application result is process-observed" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\produce: i64 = (value: i64)
        \\    value + 1
        \\answer: i64 = (seed: i64)
        \\    produce(seed)
        \\    produce(seed)
        \\answer(40)
    ;
    var lexer = Lexer.init(source, "root-demand.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();

    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    checked.source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
    try checked.check_module(&module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const root = try graph.liftModuleWithCheckedCalls(&module, &checked, "root-demand.id");

    var root_single: usize = 0;
    var nested_single: usize = 0;
    var nested_discard: usize = 0;
    for (graph.applications()) |application| {
        const demand = graph.applicationDemand(application.application) orelse
            return error.TestExpectedEqual;
        if (graph.applicationCaller(application.application).? == root) {
            try std.testing.expectEqual(types.ReturnConsumption.single, demand);
            root_single += 1;
        } else switch (demand) {
            .single => nested_single += 1,
            .discard => nested_discard += 1,
            else => return error.TestExpectedEqual,
        }
    }
    try std.testing.expectEqual(@as(usize, 1), root_single);
    try std.testing.expectEqual(@as(usize, 1), nested_single);
    try std.testing.expectEqual(@as(usize, 1), nested_discard);
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
    checked.source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
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
    const source_law = parsed.value.object.get("root_source_law").?.object;
    try std.testing.expectEqualStrings("one", source_law.get("card").?.string);
    try std.testing.expectEqualStrings("idol", source_law.get("family").?.string);
    try std.testing.expectEqualStrings(authority_projection.source_law_sha256, source_law.get("sha256").?.string);
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

test "semantic_graph: checked callable linkage is one id keyed fact" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\ordinary: i64 = ()
        \\    1
        \\@export
        \\compat: i64 = ()
        \\    2
        \\@c.export("idol_api")
        \\public: i64 = ()
        \\    3
        \\@ffi("llabs")
        \\external: i64 = (n: i64)
        \\    0
    ;
    var lexer = Lexer.init(source, "linkage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    checked.source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
    try checked.check_module(&module);
    try std.testing.expectEqual(@as(u32, 0), checked.errors);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "linkage.id");
    try std.testing.expect(graph.requiresCallableLinkage());

    const ordinary = graph.relationForDeclaration(&module.body.stmts[0].func_decl).?;
    const compat = graph.relationForDeclaration(&module.body.stmts[1].func_decl).?;
    const public = graph.relationForDeclaration(&module.body.stmts[2].func_decl).?;
    const external = graph.relationForDeclaration(&module.body.stmts[3].func_decl).?;
    const ordinary_fact = graph.callableLinkage(ordinary).?;
    const expected_ordinary = if (graph.selfHome()) |owner|
        try home_resolve_mod.homeSymbol(alloc, owner, "ordinary")
    else
        try alloc.dupe(u8, "ordinary");
    defer alloc.free(expected_ordinary);
    try std.testing.expectEqualStrings(expected_ordinary, ordinary_fact.symbol);
    try std.testing.expectEqual(CallableOrigin.idol, ordinary_fact.origin);
    try std.testing.expectEqual(CallableExposure.internal, ordinary_fact.exposure);
    try std.testing.expectEqualStrings("compat", graph.callableLinkage(compat).?.symbol);
    try std.testing.expectEqual(CallableExposure.compat_export, graph.callableLinkage(compat).?.exposure);
    try std.testing.expectEqualStrings("idol_api", graph.callableLinkage(public).?.symbol);
    try std.testing.expectEqual(CallableExposure.c_export, graph.callableLinkage(public).?.exposure);
    try std.testing.expectEqualStrings("llabs", graph.callableLinkage(external).?.symbol);
    try std.testing.expectEqual(CallableOrigin.c, graph.callableLinkage(external).?.origin);
    try std.testing.expectEqual(CallableExposure.c_import, graph.callableLinkage(external).?.exposure);

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "linkage.id", &json, null);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 14), parsed.value.object.get("version").?.integer);
    const exported = parsed.value.object.get("callable_linkages").?.array.items;
    try std.testing.expectEqual(@as(usize, 4), exported.len);
    try std.testing.expectEqual(@as(i64, external), exported[3].object.get("callable").?.integer);
    try std.testing.expectEqualStrings("c", exported[3].object.get("origin").?.string);
    try std.testing.expectEqualStrings("c_import", exported[3].object.get("exposure").?.string);
    try std.testing.expectEqualStrings("llabs", exported[3].object.get("symbol").?.string);

    // Damaging the id->row index cannot recover a symbol from the declaration.
    _ = graph.callable_linkage_rows.remove(ordinary);
    try std.testing.expect(graph.callableLinkage(ordinary) == null);
    try std.testing.expect(graph.requiresCallableLinkage());
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
        \\    pairs[i][2]
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
    try std.testing.expectEqual(@as(i64, 14), parsed.value.object.get("version").?.integer);
    try std.testing.expectEqual(graph.aggregateCount(), parsed.value.object.get("aggregates").?.array.items.len);
    try std.testing.expectEqual(graph.exact_i64_facts.items.len, parsed.value.object.get("exact_i64").?.array.items.len);
    try std.testing.expectEqual(graph.source_quote_facts.items.len, parsed.value.object.get("source_quote").?.array.items.len);

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
        \\    pairs[i][2]
        ,
        \\pick: i64 = (i: i64)
        \\    pairs = {{10, 11}, {20, 21}, {30, 31}}
        \\    pairs[i][2]
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

test "semantic_graph: immutable flat projection publishes exact application result" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    values = {10, 20, 30}
        \\    values[2]
    ;
    var lexer = Lexer.init(source, "flat-projection.id");
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
    const home = try graph.liftModuleWithCheckedCalls(&module, &checked, "flat-projection.id");
    const main_relation = graph.resolveInHome(home, "main", .func) orelse return error.TestExpectedEqual;
    const aggregate = graph.aggregateNamedInScope(main_relation, "values") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(graph.aggregateIsSoleImmutableBinding(aggregate));
    try std.testing.expect(graph.aggregateExactI64WordsMatch(aggregate, &.{ 10, 20, 30 }));
    try std.testing.expect(!graph.aggregateExactI64WordsMatch(aggregate, &.{ 10, 99, 30 }));

    var access: ?*const ApplicationFact = null;
    for (graph.applications()) |application| {
        if (graph.aggregateAccess(application.application)) |fact| access = fact;
    }
    const fact = access orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(aggregate, graph.applicationSubject(fact.application).?);
    const results = graph.applicationResults(fact.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(@as(?i64, 20), graph.exactI64(results[0]));
    try std.testing.expectEqual(types.ResolvedType.i64, graph.get(results[0]).?.descriptor.?);
}

test "semantic_graph: flat projection producer declines unsupported scalar descriptors" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const sources = [_][]const u8{
        \\main: f64 = ()
        \\    values = {1.0, 2.0}
        \\    values[1]
        ,
        \\main: str = ()
        \\    values = {"a", "b"}
        \\    values[1]
        ,
    };

    for (sources, 0..) |source, i| {
        var lexer = Lexer.init(source, if (i == 0) "flat-f64.id" else "flat-text.id");
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
        var flat_accesses: usize = 0;
        for (graph.applications()) |application| {
            if (graph.aggregateAccess(application.application) != null) flat_accesses += 1;
        }
        try std.testing.expectEqual(@as(usize, 0), flat_accesses);
    }
}

test "semantic_graph: flat projection producer declines mixed aggregate consumers" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const sources = [_][]const u8{
        \\main: i64 = ()
        \\    values = {10, 20, 30}
        \\    copy = values
        \\    values[2]
        ,
        \\main: i64 = ()
        \\    values = {10, 20, 30}
        \\    selected = values[2]
        \\    copy = values
        \\    selected
        ,
    };

    for (sources, 0..) |source, i| {
        var lexer = Lexer.init(source, if (i == 0) "alias-before.id" else "alias-after.id");
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
        const home = try graph.liftModuleWithCheckedCalls(&module, &checked, module.file);
        const main_relation = graph.resolveInHome(home, "main", .func) orelse
            return error.TestExpectedEqual;
        const aggregate = graph.aggregateNamedInScope(main_relation, "values") orelse
            return error.TestExpectedEqual;
        try std.testing.expect(!graph.aggregateIsSoleImmutableBinding(aggregate));
        var accesses: usize = 0;
        for (graph.applications()) |application| {
            if (graph.aggregateAccess(application.application) != null) accesses += 1;
        }
        try std.testing.expectEqual(@as(usize, 0), accesses);
    }
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
    // SLOT-ROLE-ONE: `w("x")` promotes its first argument to the subject slot
    // (the relation's first parameter), so the argument pack is empty and the
    // subject is present.
    try std.testing.expect(graph.applicationSubject(fact.application) != null);
    try std.testing.expectEqual(@as(usize, 0), graph.applicationArguments(fact.application).?.len);
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
    try std.testing.expect(std.mem.indexOf(u8, s, "\"version\":14") != null);
    try std.testing.expectEqualStrings(
        "unknown",
        parsed.value.object.get("root_source_law").?.object.get("card").?.string,
    );
    try std.testing.expect(std.mem.indexOf(u8, s, "\"home\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"scope\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"scope\":\"module\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"scope\":\"inline\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"relation\":\"contains\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"relation\":\"descriptor_ref\"") == null);
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
        // SLOT-ROLE-ONE: `sum(1, 2)` promotes `1` to the subject slot, leaving
        // one ordinary operand (`2`).
        try std.testing.expectEqual(@as(usize, 1), graph.applicationArguments(fact.application).?.len);
        try std.testing.expect(graph.applicationSubject(fact.application) != null);
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
        // SLOT-ROLE-ONE: `sum(1, 2)` promotes `1` to the subject slot, so the
        // JSON projection carries a subject, not null.
        try std.testing.expect(object.get("subject") != null);
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
    try std.testing.expect(!refs[0].embedded);

    // The descriptor edge is keyed on the exact graph id, not on the name —
    // renaming the shape must not move it. (The
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
    const child = try g.addChild(a, .{ .kind = .value, .span = .{ .file = "t", .start = 4, .end = 5 } });
    try std.testing.expectEqual(a, g.homeOf(child).?);
    try std.testing.expectEqualSlices(id, &.{child}, g.nested.of(a));
    for (g.edges.items) |edge| try std.testing.expect(edge.from != a or edge.to != child);
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
    // SLOT-ROLE-ONE: `inner(n)` promotes `n` to the subject slot, so the
    // argument pack is empty and the subject carries the value bound to the
    // parameter.
    try std.testing.expectEqual(@as(usize, 0), arguments.len);
    const subject = g.applicationSubject(occurrence) orelse return error.TestExpectedEqual;
    var param: ?id = null;
    for (g.nested.of(outer)) |child| {
        const node = g.get(child) orelse continue;
        if (node.kind == .param) param = child;
    }
    const param_id = param orelse return error.TestExpectedEqual;
    var param_users: std.ArrayListUnmanaged(id) = .empty;
    defer param_users.deinit(alloc);
    try g.usersOf(param_id, &param_users);
    try std.testing.expectEqual(@as(usize, 1), param_users.items.len);
    try std.testing.expectEqual(subject, param_users.items[0]);
    try std.testing.expectEqual(Card{ .one = param_id }, g.valueOrigin(subject));
}

test "semantic_graph: module mutation keeps binding identity and local shadow" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\global counter: i64 = 0
        \\write: i64 = ()
        \\    counter = counter + 1
        \\    counter
        \\shadow: i64 = ()
        \\    counter: i64 = 7
        \\    counter = counter + 1
        \\    counter
        \\entry: i64 = ()
        \\    write()
        \\shadowentry: i64 = ()
        \\    shadow()
    ;
    var lexer = Lexer.init(source, "module-mutation.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const home = try graph.liftModuleWithCheckedCalls(&module, &checked, "module-mutation.id");

    const module_binding = graph.resolveInHome(home, "counter", .local) orelse
        return error.TestExpectedEqual;
    const write = graph.resolveInHome(home, "write", .func) orelse
        return error.TestExpectedEqual;
    const shadow = graph.resolveInHome(home, "shadow", .func) orelse
        return error.TestExpectedEqual;
    const entry = graph.resolveInHome(home, "entry", .func) orelse
        return error.TestExpectedEqual;
    const shadow_entry = graph.resolveInHome(home, "shadowentry", .func) orelse
        return error.TestExpectedEqual;

    var same_named: usize = 0;
    var shadow_binding: ?id = null;
    for (graph.nodes.items, 0..) |node, coordinate| {
        if (node.kind != .local or node.name == null) continue;
        if (!std.mem.eql(u8, node.name.?, "counter")) continue;
        same_named += 1;
        if (node.scope == shadow) shadow_binding = @intCast(coordinate);
    }
    // The module binding and the explicit shadow are distinct.  The assignment
    // in `write` must not manufacture a third binding.
    try std.testing.expectEqual(@as(usize, 2), same_named);
    try std.testing.expect(shadow_binding != null);
    try std.testing.expect(shadow_binding.? != module_binding);

    const mutations = graph.bindingMutations();
    try std.testing.expectEqual(@as(usize, 1), mutations.len);
    try std.testing.expectEqual(write, mutations[0].relation);
    try std.testing.expectEqual(module_binding, mutations[0].binding);

    const calls = graph.applicationsIn(entry);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    const effect = graph.applicationEffect(calls[0]);
    try std.testing.expectEqual(Card{ .one = module_binding }, effect);
    const shadow_calls = graph.applicationsIn(shadow_entry);
    try std.testing.expectEqual(@as(usize, 1), shadow_calls.len);
    try std.testing.expectEqual(Card.none, graph.applicationEffect(shadow_calls[0]));

    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, "module-mutation.id", &json, null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"version\":14") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"mutations\":[{") != null);

    // THE CARDINALITY, AND THE THREE STATES THAT MUST NOT COLLAPSE. The
    // `mutations` rows above are positive only, so absence means `none` and
    // `unknown` at once. `entry` applies a relation that writes exactly one
    // binding; `shadowentry` applies one that writes nothing and must read
    // `none` rather than share the silence.
    try std.testing.expectEqual(MutationCard{ .one = module_binding }, graph.mutation(calls[0]));
    try std.testing.expectEqual(MutationCard.none, graph.mutation(shadow_calls[0]));
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"mutation_closure\":[{") != null);
}

test "semantic_graph: one module binding owns checked value origin and survives shadowing" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\total: i64 = 3
        \\total = total + 4
        \\take: i64 = (value: i64)
        \\    value
        \\frommodule: i64 = ()
        \\    take(total)
        \\shadow: i64 = (total: i64)
        \\    take(total)
    ;
    var lex = Lexer.init(src, "module-binding.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var g = SemanticGraph.init(alloc);
    defer g.deinit();
    const module_id = try g.liftModuleWithCheckedCalls(&module, &checked, "module-binding.id");

    var module_binding: ?id = null;
    var module_binding_count: usize = 0;
    for (g.nested.of(module_id)) |child| {
        const node = g.get(child) orelse continue;
        if (node.kind != .local or node.name == null) continue;
        if (!std.mem.eql(u8, node.name.?, "total")) continue;
        module_binding = child;
        module_binding_count += 1;
        try std.testing.expectEqual(types.ResolvedType.i64, node.descriptor.?);
    }
    try std.testing.expectEqual(@as(usize, 1), module_binding_count);
    const exact_module_binding = module_binding orelse return error.TestExpectedEqual;

    var module_origin_seen = false;
    var shadow_origin_seen = false;
    for (g.applications()) |application| {
        const caller = g.applicationCaller(application.application) orelse continue;
        const caller_node = g.get(caller) orelse continue;
        const caller_name = caller_node.name orelse continue;
        const subject = g.applicationSubject(application.application) orelse continue;
        if (std.mem.eql(u8, caller_name, "frommodule")) {
            try std.testing.expectEqual(Card{ .one = exact_module_binding }, g.valueOrigin(subject));
            module_origin_seen = true;
        } else if (std.mem.eql(u8, caller_name, "shadow")) {
            const shadow_binding = switch (g.valueOrigin(subject)) {
                .one => |binding| binding,
                .unknown, .none => return error.TestExpectedEqual,
            };
            try std.testing.expect(shadow_binding != exact_module_binding);
            try std.testing.expectEqual(NodeKind.param, g.get(shadow_binding).?.kind);
            shadow_origin_seen = true;
        }
    }
    try std.testing.expect(module_origin_seen);
    try std.testing.expect(shadow_origin_seen);
}

test "semantic_graph: module binding names its initializer value and exact place" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\const fixed: i64 = 41
        \\moving: i64 = 1
        \\moving = 2
        \\wide: u64 = 3
        \\take: i64 = (value: i64)
        \\    value
        \\readfixed: i64 = ()
        \\    take(fixed)
        \\readmoving: i64 = ()
        \\    take(moving)
        \\readliteral: i64 = ()
        \\    take(7)
    ;
    var lexer = Lexer.init(source, "binding-initializer.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const module_id = try graph.liftModuleWithCheckedCalls(
        &module,
        &checked,
        "binding-initializer.id",
    );

    for ([_][]const u8{ "fixed", "moving" }) |name| {
        const binding = graph.resolveInHome(module_id, name, .local) orelse
            return error.TestExpectedEqual;
        const initialization = switch (graph.bindingInitialization(binding)) {
            .known => |fact| fact,
            .unvisited, .invalid => return error.TestExpectedEqual,
        };
        try std.testing.expectEqual(binding, initialization.binding);
        try std.testing.expect(graph.exactI64(initialization.value) != null);
        const value = graph.get(initialization.value) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(module_id, value.scope.?);
        const p = graph.modulePlace(initialization.place) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(place.Shape.scalar, p.shape);
        if (std.mem.eql(u8, name, "fixed")) {
            try std.testing.expectEqual(@as(i64, 41), graph.exactI64(initialization.value).?);
            try std.testing.expectEqual(place.Tri.no, p.facts.mutation);
            try std.testing.expectEqual(place.Tri.yes, p.facts.immutability);
            try std.testing.expectEqual(place.Tri.yes, p.facts.contents_known);
        } else {
            try std.testing.expectEqual(@as(i64, 1), graph.exactI64(initialization.value).?);
            try std.testing.expectEqual(place.Tri.yes, p.facts.mutation);
            try std.testing.expectEqual(place.Tri.no, p.facts.immutability);
            try std.testing.expectEqual(place.Tri.no, p.facts.contents_known);
        }
    }

    const wide = graph.resolveInHome(module_id, "wide", .local) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(graph.bindingInitialization(wide) == .unvisited);

    const fixed = graph.resolveInHome(module_id, "fixed", .local).?;
    const saved_row = graph.binding_initialization_rows.fetchRemove(fixed) orelse
        return error.TestExpectedEqual;
    try std.testing.expect(graph.bindingInitialization(fixed) == .invalid);
    try graph.binding_initialization_rows.putNoClobber(alloc, saved_row.key, saved_row.value);
    switch (graph.bindingInitialization(fixed)) {
        .known => {},
        .unvisited, .invalid => return error.TestExpectedEqual,
    }
}

test "semantic_graph: nested application name publishes checked module descriptor" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\t: i64 = 0
        \\t = t + 5
        \\stdout:write("{t}\\n")
    ;
    var lexer = Lexer.init(source, "module-interpolation.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    const module_id = try graph.liftModuleWithCheckedCalls(&module, &checked, "module-interpolation.id");

    const binding = graph.resolveInHome(module_id, "t", .local) orelse
        return error.TestExpectedEqual;
    var nested_value: ?id = null;
    for (graph.nodes.items, 0..) |node, coordinate| {
        if (node.kind != .value or node.ast_ref == null) continue;
        const expression: *const Expr = @ptrCast(@alignCast(node.ast_ref.?));
        if (expression.* != .name or !std.mem.eql(u8, expression.name.ident, "t")) continue;
        // Only the interpolation occurrence is inside an application operand;
        // the assignment's read is outside this producer's declared domain.
        try std.testing.expect(nested_value == null);
        nested_value = @intCast(coordinate);
    }
    const value = nested_value orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(types.ResolvedType.i64, graph.get(value).?.descriptor.?);
    try std.testing.expectEqual(Card{ .one = binding }, graph.valueOrigin(value));
    const application = graph.get(value).?.scope orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(NodeKind.call, graph.get(application).?.kind);
    try std.testing.expect(graph.application(application) == null);
    try std.testing.expect(graph.isBootstrapApplicationNode(application));
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
    //
    // THIS PINNED `unknown` AND THAT WAS THE WHOLE DEFECT IN ONE ASSERTION.
    // `stdout:write(s)` is an OBSERVATION — the clearest one a program makes —
    // and the strongest thing the graph could say about it was "nobody looked".
    // It now says `one`, and the id is the exact `io` world entity the draw row
    // named. `unknown` here would be a fact that is available and not published.
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
        try std.testing.expect(observed == .one);
        const world = g.get(observed.one) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("io", world.name.?);
    }

    // AND THE OTHER HALF OF THE SAME FACT, which is what keeps `one` from
    // becoming a second spelling of "not none": a body that reaches a
    // `.realized` world observes nothing, and grounding an effect on it would
    // be an over-claim. `math.floor` draws the `math` world and the honest
    // answer stays `unknown` — the relation is blocked for a reason this pass
    // does not model, not because an observation was proved.
    {
        var g = SemanticGraph.init(alloc);
        defer g.deinit();
        const observed = liftedEffectOf(alloc, &g,
            \\down: f64 = (x: f64)
            \\    math.floor(x)
            \\entry: f64 = ()
            \\    down(1.5)
        , "entry") catch |err| switch (err) {
            error.TestExpectedEqual => Card.unknown,
            else => return err,
        };
        try std.testing.expect(observed != .one);
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

test "semantic_graph: same-named descriptors resolve in the home scope chain" {
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
    for (g.nested.of(first)) |child| {
        const node = g.get(child) orelse continue;
        const name = node.name orelse continue;
        if (node.kind == .table_shape and std.mem.eql(u8, name, "Point")) point_a = child;
        if (node.kind == .func and std.mem.eql(u8, name, "use")) use_a = child;
    }
    for (g.nested.of(second)) |child| {
        const node = g.get(child) orelse continue;
        const name = node.name orelse continue;
        if (node.kind == .table_shape and std.mem.eql(u8, name, "Point")) point_b = child;
        if (node.kind == .func and std.mem.eql(u8, name, "use")) use_b = child;
    }
    try std.testing.expect(point_a.? != point_b.?);

    var local_a: ?id = null;
    var local_b: ?id = null;
    for (g.nested.of(use_a.?)) |child| {
        const node = g.get(child) orelse continue;
        const name = node.name orelse continue;
        if (node.kind == .local and std.mem.eql(u8, name, "p")) local_a = child;
    }
    for (g.nested.of(use_b.?)) |child| {
        const node = g.get(child) orelse continue;
        const name = node.name orelse continue;
        if (node.kind == .local and std.mem.eql(u8, name, "p")) local_b = child;
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
    before.root_source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
    const old = try before.addNode(.{
        .kind = .func,
        .span = .{ .file = "old/place.id", .start = 1, .end = 1 },
        .name = "parse",
    });

    var after = SemanticGraph.init(std.testing.allocator);
    defer after.deinit();
    after.root_source_law_edition = authority_projection.SourceLawEdition.idolCurrent();
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

    // Equal source-law edition and spelling cannot establish continuity, even
    // across a file move. Only the witnessed correspondence below may do so.
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

test "semantic_graph: lifted quoted literals publish source quote facts" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\t: str = "hi"
        \\b = 'b'
        \\entry: str = ()
        \\    t
    ;
    var lex = Lexer.init(source, "quotes.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    table_apply.normalizeModule(alloc, &mod, &checked.type_map);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "quotes.id");
    try std.testing.expectEqual(@as(usize, 2), graph.source_quote_facts.items.len);
    var saw_text = false;
    var saw_bytes = false;
    for (graph.source_quote_facts.items) |fact| {
        switch (fact.quote) {
            .text => saw_text = true,
            .bytes => saw_bytes = true,
            else => {},
        }
    }
    try std.testing.expect(saw_text);
    try std.testing.expect(saw_bytes);
}

test "semantic_graph: one literal sweep reaches nested, operand, and tail quotes" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\entry: str = ()
        \\    raw = 'raw'
        \\    pair = "left" .. "right"
        \\    print("operand")
        \\    "tail"
    ;
    var lex = Lexer.init(source, "quote-reach.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "quote-reach.id");

    // Five lexical value occurrences, including the unresolved `print`
    // operand. The retired binding-only sweep reached just `raw` here.
    try std.testing.expectEqual(@as(usize, 5), graph.source_quote_facts.items.len);
    var text: usize = 0;
    var bytes: usize = 0;
    for (graph.source_quote_facts.items) |fact| switch (fact.quote) {
        .bytes => bytes += 1,
        else => text += 1,
    };
    try std.testing.expectEqual(@as(usize, 4), text);
    try std.testing.expectEqual(@as(usize, 1), bytes);
}

test "semantic_graph: cross-home tail constant publishes exactI64" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io_iface = threaded.io();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const from = "examples/cross_home_constant.id";
    const src =
        \\main: i64 = ()
        \\    token.kindeof
    ;
    var lex = Lexer.init(src, from);
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    checked.source_path = try alloc.dupe(u8, from);
    const TestLoader = struct {
        alloc: std.mem.Allocator,
        io: std.Io,
        from: []const u8,
        fn load(raw: *anyopaque, alias: []const u8) ?sema.ForeignHome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const source = home_resolve_mod.resolve(
                self.alloc,
                self.io,
                .{ .from = self.from, .stdlib_root = "lib/compiler" },
                alias,
            ) orelse return null;
            if (std.mem.eql(u8, source.path, self.from)) return null;
            const file_src = std.Io.Dir.cwd().readFileAlloc(self.io, source.path, self.alloc, .unlimited) catch return null;
            var file_lex = Lexer.init(file_src, source.path);
            var file_parser = Parser.init(&file_lex, self.alloc);
            file_parser.idol_mode = true;
            const file_mod = self.alloc.create(ast.Module) catch return null;
            file_mod.* = file_parser.parse_module() catch return null;
            const home = home_resolve_mod.homeOfPath(self.alloc, self.io, source.path) catch return null;
            return .{ .home = home, .path = source.path, .module = file_mod };
        }
    };
    var loader_ctx: TestLoader = .{ .alloc = alloc, .io = io_iface, .from = from };
    checked.home_loader = .{ .ctx = &loader_ctx, .load = TestLoader.load };
    try checked.check_module(&mod);
    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, from);
    const tail = mod.body.stmts[0].func_decl.func.body.tail_expr orelse return error.TestExpectedEqual;
    try std.testing.expect(tail.* == .field);
    try std.testing.expectEqual(@as(i64, 109), checked.foreignModuleIntConstant(tail).?);
    const raw: *const anyopaque = @ptrCast(@constCast(tail));
    var saw = false;
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .value or node.ast_ref != raw) continue;
        try std.testing.expectEqual(@as(i64, 109), graph.exactI64(@intCast(i)).?);
        saw = true;
    }
    try std.testing.expect(saw);
}

test "semantic_graph: cross-home application exposes the exact missing body boundary" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var foreign_lex = Lexer.init(
        \\read: i64 = (subject: { value: i64 })
        \\    subject.value
    , "lib/compiler/reader.id");
    var foreign_parser = Parser.init(&foreign_lex, alloc);
    foreign_parser.idol_mode = true;
    const foreign_module = try alloc.create(ast.Module);
    foreign_module.* = try foreign_parser.parse_module();

    var root_lex = Lexer.init(
        \\grab: i64 = (d: { value: i64 })
        \\    compiler.reader.read(d)
    , "cross-home.id");
    var root_parser = Parser.init(&root_lex, alloc);
    root_parser.idol_mode = true;
    var root_module = try root_parser.parse_module();

    const TestLoader = struct {
        module: *const ast.Module,

        fn load(raw: *anyopaque, spelling: []const u8) ?sema.ForeignHome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (!std.mem.eql(u8, spelling, "compiler.reader")) return null;
            return .{
                .home = "compiler.reader",
                .path = "lib/compiler/reader.id",
                .module = self.module,
            };
        }
    };
    var loader: TestLoader = .{ .module = foreign_module };
    var checked = sema.Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    checked.home_loader = .{ .ctx = &loader, .load = TestLoader.load };
    try checked.check_module(&root_module);

    var graph = SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&root_module, &checked, "cross-home.id");

    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const occurrence = graph.applications()[0].application;
    const target = graph.applicationTarget(occurrence) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("compiler.reader", graph.foreignHome(target) orelse return error.TestExpectedEqual);
    const linkage = graph.callableLinkage(target) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("idol_compiler_reader__read", linkage.symbol);

    // This is the exact remaining transfer boundary. The checked caller knows
    // the target and its one physical symbol, but no executable body is owned
    // by this graph incarnation. A real cross-home realization must replace
    // this null with the target's graph-owned body/schedule before C emission
    // may stop refusing; spelling-based embedding is not an alternative.
    try std.testing.expect(graph.bodyOf(target) == null);
}
