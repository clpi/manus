//! The relation store — gap[082], Pass 100 §9 ("Relations, the trie, protocols,
//! the algebra").
//!
//! WHAT THIS REPLACES. `to` was not a relation. Four sites in `codegen.zig`
//! compared the literal string `"to"` and lowered the call directly, so the
//! conversion universe was exactly the set of primitive descriptors the code
//! generator had been taught by hand. Authored edges: 0. Derived edges: 0.
//! Semantic expansion ratio: 1.
//!
//! WHAT IT IS. A relation is a two-level trie keyed DESTINATION-first, because
//! that is the order §9 enumerates it in (`for src, conv in to[str]`). An edge
//! is one graph fact (A3 ONE EDGE); the declaration face `to(dest)(src) = conv`
//! is the ONLY way one enters, and it is an ordinary assignment statement — NNS
//! FIRST (A2), the grammar is closed and no new surface was added to get here.
//!
//! A STORE, NOT ONE RELATION. `to` proved the shape; the store holds every
//! relation family in the same machinery, so `eq`, `ord`, `iter`, `from` etc.
//! are rows of one store rather than second mechanisms (spec 2.6, "Do not build
//! all of them independently"). Declaration, enumeration, composition and SER
//! are family-generic; the only thing a family owns is its name.
//!
//! ── DELETION CONTRACT (law.host.projection) ─────────────────────────────────
//!
//!     authority   = false
//!     projects    = relation
//!     bootstrap   = true
//!     deletion    = when descriptors, edges and witnesses are ordinary graph
//!                   facts and this file has no object taxonomy left to hold
//!
//! THIS FILE IS NOT THE RELATION SUBSYSTEM. It is the bootstrap REALIZATION of
//! ordinary graph relation facts, and **none of its object taxonomy is semantic
//! authority**: `Properties`, `Class`, `Edge`, `Path`, `Relation` and `Store`
//! are host structs that project onto `relation` / `fact` / `witness`, which
//! are three of the six irreducible primitives in `docs/spec/constitution.md`.
//! The final shape has no `ConversionRelation`, `ConversionEdge`,
//! `ConversionClass` or `ConversionPath` in it.
//!
//! Recorded now, at the moment the file is USEFUL, because that is when the
//! pressure to fossilize starts. GAP-084 was this repository's registry problem;
//! a registry that returns under a cleaner name is the same defect. Two rows of
//! `law.architecture.owner`'s deny list — `*Registry`, `*Kernel` — were written
//! against exactly this trajectory.
//!
//! RETIRED DEBT — descriptor and callable identities are no longer `[]const u8`.
//! The store keys every edge on a stable semantic `Id` minted by `Names` from a
//! key carrying KIND, spelling, ORIGIN (package + version), SCOPE (exported +
//! owner) and LAWSET. The string survives ONLY as a rendering and lookup
//! convenience: `Edge`, `Path` and `Relation.name` are the rendered face of
//! `Fact`, `Route` and `Relation.id`, and no comparison in the algebra reads
//! text. See "STABLE SEMANTIC IDENTITY" below for what each of the four
//! text-key failure modes was and which of them this actually closes.
//!
//! KNOWN BOOTSTRAP DEBT, so it is measured rather than discovered later:
//!   - the FRONT END still hands the store one origin, one lawset and one
//!     scope, because Idol has no package surface yet and `rename` has no
//!     source form. Every discrimination below is proven at the store layer and
//!     unreachable from a `.id` file; that is the remaining half and it is
//!     gap[103], not a claim this file makes.
//!   - class legality is refused at CODEGEN, so `duo check` can approve what
//!     compilation later rejects. Resolution, coherence and class legality
//!     belong in SEMA, above realization. This is a direction violation and it
//!     is temporary.
//!   - `derive` is deliberately ONE HOP. Longer paths need a real
//!     path-selection law — multiple valid paths, cost, information loss,
//!     effects, ownership, failure, trust, ambiguity. **Adding BFS/DFS instead
//!     of that law would be architecturally wrong**, so the limit stays until
//!     the law exists.
//!   - the `to` CALL face is still reached by name in `codegen.zig`
//!     (`emit_relation_convert` looks up family `"to"`), and the two literal
//!     `"to"` comparisons near `expr_type` remain host projections of that
//!     family with their own deletion gates. Families other than `to` are
//!     declared and ENUMERATED today; a call projection is the next face.
//!
//! THE ALGEBRA. `derive` is the one composition law: an undeclared `a -> b` is
//! answered by `a -> mid -> b` when a mid exists. This is the whole claim under
//! test — N descriptors sharing a canonical hub need N authored edges rather
//! than N(N-1) pairwise ones, and every edge the trie answers with that was
//! never written is the numerator of SER.
//!
//! CLASSES ARE FACTS ON THE EDGE, not a second conversion system. The six
//! authored spellings — `exact`, `lossless`, `checked`, `narrowing`, `view`,
//! `consuming` — parse to a `Properties` fact set: `loss`, `failure`,
//! `storage`, `consumes` (plus `same_repr`, the identity fact that tells
//! `exact` from `lossless`). The facts compose by MEET: a path is only as
//! strong as its weakest hop. `Class` survives ONLY as the spelling bijection
//! for the `@anchor`; it has no algebra of its own. The rule that matters is
//! `Properties.derivable` — **silent** derivation stops when any fact is
//! withheld: a path that loses, may fail, views, or consumes is found,
//! reported, and REFUSED, because an algebra that silently composes into a
//! lossy conversion is worse than no algebra at all. `refuse` is what makes
//! this design safe to scale; without it, adding a descriptor could quietly
//! change an existing program's answer.
const std = @import("std");
const ast = @import("ast.zig");

/// How much of the source value survives the edge. The strength order of the
/// tags IS the lattice: `none` is strongest, `total` weakest, so a meet is a
/// max over the tag index and needs no table.
pub const Loss = enum(u2) {
    /// Every source value has a distinct destination value.
    none,
    /// Some source values do not survive.
    some,
    /// The source value does not survive at all.
    total,
};

/// Where the destination value lives relative to the source's storage.
pub const Storage = enum(u2) {
    copy,
    view,
    consume,
};

/// Ordinary graph facts carried by EVERY edge of EVERY relation family. This
/// is the fact set the six authored classes parse into and render from; there
/// is no conversion-only class algebra left for `meet` and `derivable` to be
/// a second system. `loss` / `failure` / `storage` / `consumes` are general —
/// an `add` edge can fail, an `iter` edge can consume.
pub const Properties = struct {
    loss: Loss = .none,
    failure: bool = false,
    storage: Storage = .copy,
    consumes: bool = false,
    /// The two descriptors denote the SAME value — the edge is an identity of
    /// representation. The one fact the authored spellings disagree on that
    /// `loss`/`storage` cannot see (`exact` vs `lossless`). Survives a meet
    /// only when every hop is itself an identity.
    same_repr: bool = false,

    /// The class of a path is its WEAKEST hop, fact by fact: the worst loss,
    /// a failure if either hop may fail, the worst storage, and consumption if
    /// either hop consumes. An identity survives a meet only if every hop is
    /// one.
    pub fn meet(a: Properties, b: Properties) Properties {
        return .{
            .loss = if (@intFromEnum(a.loss) >= @intFromEnum(b.loss)) a.loss else b.loss,
            .failure = a.failure or b.failure,
            .storage = if (@intFromEnum(a.storage) >= @intFromEnum(b.storage)) a.storage else b.storage,
            .consumes = a.consumes or b.consumes,
            .same_repr = a.same_repr and b.same_repr,
        };
    }

    /// May an edge of these facts be composed into a DERIVED edge that no one
    /// wrote? Only when nothing is lost, nothing can fail, nothing is viewed or
    /// consumed. Everything else must be authored deliberately or routed by the
    /// caller.
    pub fn derivable(self: Properties) bool {
        return self.loss == .none and !self.failure and self.storage == .copy and !self.consumes;
    }

    /// The authored class this fact set IS, when one of the six spells it
    /// exactly. A MEET can land outside the six — a checked view, a narrowing
    /// view, a consuming narrowing — and that is honest: the weaker-class tag
    /// the old lattice printed for those pairs (checked∘view rendered as
    /// `checked`) was the ONE class that did not contain the both facts. Those
    /// combos render as facts below and are refused by `derivable`.
    pub fn class_opt(self: Properties) ?Class {
        // Zig cannot switch on a struct, so this is the same bijection written
        // as an ordered scan of the six spellings. The TABLE is the point — it
        // stays one row per authored class, and `null` still means the facts
        // landed outside the six, which `fmt` renders as facts.
        const rows = [_]struct { p: Properties, c: Class }{
            .{ .p = .{ .loss = .none, .failure = false, .storage = .copy, .consumes = false, .same_repr = true }, .c = .exact },
            .{ .p = .{ .loss = .none, .failure = false, .storage = .copy, .consumes = false, .same_repr = false }, .c = .lossless },
            .{ .p = .{ .loss = .none, .failure = false, .storage = .view, .consumes = false, .same_repr = false }, .c = .view },
            .{ .p = .{ .loss = .none, .failure = true, .storage = .copy, .consumes = false, .same_repr = false }, .c = .checked },
            .{ .p = .{ .loss = .some, .failure = false, .storage = .copy, .consumes = false, .same_repr = false }, .c = .narrowing },
            .{ .p = .{ .loss = .none, .failure = false, .storage = .copy, .consumes = true, .same_repr = false }, .c = .consuming },
        };
        for (rows) |r| {
            if (std.meta.eql(self, r.p)) return r.c;
        }
        return null;
    }

    /// Render the facts: the class name when the six spell them, otherwise the
    /// facts themselves, space-joined. `buf` holds the fallback rendering.
    pub fn fmt(self: Properties, buf: []u8) []const u8 {
        if (self.class_opt()) |c| return c.text();
        const parts = [_]struct { present: bool, s: []const u8 }{
            .{ .present = self.loss != .none, .s = @tagName(self.loss) },
            .{ .present = self.failure, .s = "failure" },
            .{ .present = self.storage != .copy, .s = @tagName(self.storage) },
            .{ .present = self.consumes, .s = "consumes" },
        };
        // Written into `buf` directly. `std.io.fixedBufferStream` is gone in Zig
        // master, and a writer is more machinery than joining four short words
        // needs — the bound is the caller's buffer either way.
        var n: usize = 0;
        for (parts) |p| {
            if (!p.present) continue;
            if (n > 0) {
                if (n + 1 > buf.len) return "facts";
                buf[n] = ' ';
                n += 1;
            }
            if (n + p.s.len > buf.len) return "facts";
            @memcpy(buf[n..][0..p.s.len], p.s);
            n += p.s.len;
        }
        return if (n > 0) buf[0..n] else "facts";
    }
};

/// The authored SPELLING vocabulary for an edge's facts, in the strength order
/// the constitution names them. This is a parse/render bijection onto
/// `Properties` and nothing else — no `meet`, no `derivable`, no lattice: the
/// algebra lives on the facts so any family can use it.
pub const Class = enum {
    exact,
    lossless,
    view,
    checked,
    narrowing,
    consuming,

    pub fn parse(name: []const u8) ?Class {
        return std.meta.stringToEnum(Class, name);
    }

    pub fn text(self: Class) []const u8 {
        return @tagName(self);
    }

    /// The facts the `@anchor` spelling names. `exact` and `lossless` agree on
    /// loss/failure/storage and differ only on `same_repr` — the identity fact.
    pub fn to_properties(self: Class) Properties {
        return switch (self) {
            .exact => .{ .loss = .none, .failure = false, .storage = .copy, .consumes = false, .same_repr = true },
            .lossless => .{ .loss = .none, .failure = false, .storage = .copy, .consumes = false, .same_repr = false },
            .view => .{ .loss = .none, .failure = false, .storage = .view, .consumes = false, .same_repr = false },
            .checked => .{ .loss = .none, .failure = true, .storage = .copy, .consumes = false, .same_repr = false },
            .narrowing => .{ .loss = .some, .failure = false, .storage = .copy, .consumes = false, .same_repr = false },
            .consuming => .{ .loss = .none, .failure = false, .storage = .copy, .consumes = true, .same_repr = false },
        };
    }
};

// ── STABLE SEMANTIC IDENTITY (law.identity.three, constitution §21) ─────────
//
// THE LAW requires THREE identities and forbids collapsing them:
//
//     semantic     "what thing is this?"       stable across harmless edits
//     content      "what payload right now?"   changes when the content changes
//     incarnation  "which occurrence/build?"   never stable, that is the point
//
// WHAT WAS WRONG. The store keyed every edge on a descriptor's TEXT. Two
// strings that were equal were one descriptor and two that differed were two,
// which is wrong in BOTH directions the moment anything real exists:
//
//   packages   `micron` from a@1 and `micron` from b@1 are two descriptors, and
//              a text key silently merges them into one.
//   renames    spelling `micron` as `micrometre` is a harmless edit, and a text
//              key destroys every edge that mentioned it.
//   versions   a@1's `micron` and a@2's `micron` may carry different edges, and
//              a text key cannot hold both at once.
//   private    two modules' private `scratch` are two descriptors, and a text
//              key lets one module's edge answer the other module's query.
//
// WHAT AN ID IS. A number minted by `Names` from a key carrying all four
// discriminators plus the Lua firewall's — a Lua `number` and an Idol `f64` may
// share a spelling and are never the same thing, so LAWSET is an identity fact
// before it is an optimizer fact. An `Id` holds no text on purpose: a copy
// cannot go stale across a rename and cannot be byte-compared by accident.
//
// THE STRING SURVIVES ONLY AS RENDERING AND LOOKUP. `Edge` and `Path` are the
// rendered face of `Fact` and `Route`; `Names.find` is the single quarantined
// site where comparing bytes is correct, because resolving a SPELLING to an
// identity is what a lookup IS. Everything from `Relation` down compares `Id`,
// and `zig build relation-id` convicts the file if a byte comparison reappears
// there — with the in-region count as the positive control, because a scanner
// reporting zero findings is usually a broken scanner.

/// Which LAWSET an identity belongs to (constitution §22). THE LUA FIREWALL:
/// the substrate is shared and the lawset is not, so identity may not be.
pub const Lawset = enum { idol, lua, c, wasm };

/// What kind of thing an identity names. A descriptor `to` and a relation `to`
/// share a spelling and nothing else.
pub const Kind = enum { descriptor, callable, relation };

/// WHERE the identity came from. Two packages, or two versions of one package,
/// may each define a `micron`, and those are different descriptors.
pub const Origin = struct {
    /// "" is the compilation unit itself — the prelude graph, which is not a
    /// package (§0h: std has no module tree and no import).
    package: []const u8 = "",
    version: []const u8 = "",

    pub fn eq(a: Origin, b: Origin) bool {
        return std.mem.eql(u8, a.package, b.package) and std.mem.eql(u8, a.version, b.version);
    }
};

/// WHO can see it. A private descriptor is only ever the same thing as itself,
/// so its owner participates in its identity — privacy is topology, never
/// spelling (§0.1).
pub const Scope = struct {
    exported: bool = true,
    owner: []const u8 = "",

    pub fn eq(a: Scope, b: Scope) bool {
        return a.exported == b.exported and std.mem.eql(u8, a.owner, b.owner);
    }
};

/// The interning KEY — everything that makes two names DIFFERENT THINGS.
pub const Name = struct {
    kind: Kind,
    text: []const u8,
    origin: Origin = .{},
    scope: Scope = .{},
    lawset: Lawset = .idol,
};

/// A STABLE SEMANTIC IDENTITY. The number is the identity and there is no text
/// in here, deliberately.
pub const Id = struct {
    n: u32,

    pub const none: Id = .{ .n = std.math.maxInt(u32) };

    pub fn eq(a: Id, b: Id) bool {
        return a.n == b.n;
    }

    pub fn valid(self: Id) bool {
        return self.n != none.n;
    }
};

/// What the interner remembers about one identity.
pub const Record = struct {
    kind: Kind,
    /// The CURRENT spelling. A rename edits THIS and nothing else, which is the
    /// whole reason a rename is a harmless edit again.
    text: []const u8,
    /// The spelling the identity was MINTED under. Forensics and diagnostics
    /// only — never a key, or a rename would mint a second identity.
    minted: []const u8,
    origin: Origin,
    scope: Scope,
    lawset: Lawset,
    /// INCARNATION — which minting occurrence this is. Never stable across
    /// builds; law.identity.three says that is the point, not a defect.
    incarnation: u32,
};

/// The interner. Flat and scanned: a compilation unit's descriptor set is tens
/// of names, and a scan keeps MINT ORDER = enumeration order, which is what
/// makes `for src, conv in to[str]` reproducible.
pub const Names = struct {
    records: std.ArrayListUnmanaged(Record) = .empty,
    /// Total mintings ever, including ones later renamed. Mints incarnations.
    mintings: u32 = 0,

    pub fn deinit(self: *Names, alloc: std.mem.Allocator) void {
        self.records.deinit(alloc);
    }

    /// ── THE ONE QUARANTINED BYTE COMPARISON ─────────────────────────────────
    /// Resolving a SPELLING to an identity is what a lookup IS, so this is the
    /// only place in the store where text may be compared. `Origin.eq` and
    /// `Scope.eq` above are part of the same key comparison and part of the
    /// same quarantine. A `std.mem.eql` from `Relation` down is a finding.
    pub fn find(self: *const Names, name: Name) ?Id {
        for (self.records.items, 0..) |r, i| {
            if (r.kind != name.kind) continue;
            if (r.lawset != name.lawset) continue;
            if (!r.origin.eq(name.origin)) continue;
            if (!r.scope.eq(name.scope)) continue;
            if (!std.mem.eql(u8, r.text, name.text)) continue;
            return .{ .n = @intCast(i) };
        }
        return null;
    }

    /// The identity for a key, minting one on first sight. Idempotent: the same
    /// key always answers with the same number, which is the half of the law
    /// that stops the discriminators from being merely "always different".
    pub fn intern(self: *Names, alloc: std.mem.Allocator, name: Name) !Id {
        if (self.find(name)) |id| return id;
        self.mintings += 1;
        try self.records.append(alloc, .{
            .kind = name.kind,
            .text = name.text,
            .minted = name.text,
            .origin = name.origin,
            .scope = name.scope,
            .lawset = name.lawset,
            .incarnation = self.mintings,
        });
        return .{ .n = @intCast(self.records.items.len - 1) };
    }

    /// THE LOOKUP CONVENIENCE the compiler front end uses today: one
    /// compilation unit, one lawset, everything exported. This is the only
    /// place the old text-keyed behaviour survives, and it survives as a
    /// LOOKUP — it answers with an identity and never with a comparison.
    pub fn lookup(self: *const Names, kind: Kind, spelling: []const u8) ?Id {
        return self.find(.{ .kind = kind, .text = spelling });
    }

    pub fn at(self: *const Names, id: Id) ?Record {
        if (!id.valid() or id.n >= self.records.items.len) return null;
        return self.records.items[id.n];
    }

    /// The identity's CURRENT spelling, for rendering. Reading through the
    /// interner rather than through a stored copy is what makes a rename
    /// visible from every edge without any edge being touched.
    pub fn text(self: *const Names, id: Id) []const u8 {
        const r = self.at(id) orelse return "";
        return r.text;
    }

    /// RENAME — the harmless edit. The identity does not move; only its
    /// spelling does.
    ///
    /// A rename onto a spelling already taken under the same key is REFUSED.
    /// Allowing it would collapse two semantic identities into one lookup,
    /// which is the exact failure law.dedup names.
    pub fn rename(self: *Names, id: Id, to: []const u8) !void {
        const r = self.at(id) orelse return error.NoSuchIdentity;
        if (self.find(.{ .kind = r.kind, .text = to, .origin = r.origin, .scope = r.scope, .lawset = r.lawset })) |taken| {
            if (!taken.eq(id)) return error.NameTaken;
            return;
        }
        self.records.items[id.n].text = to;
    }

    pub fn count(self: *const Names) usize {
        return self.records.items.len;
    }
};

/// The SEMANTIC identity of one relationship (A3, ONE EDGE): the family it
/// belongs to and its two endpoints, all three as identities and none as text.
/// Stable across a rename of any of the three, and across a redeclaration that
/// swaps the realization — which is what "stable across harmless edits" means.
pub const EdgeId = struct {
    relation: Id,
    src: Id,
    dest: Id,

    pub fn eq(a: EdgeId, b: EdgeId) bool {
        return a.relation.eq(b.relation) and a.src.eq(b.src) and a.dest.eq(b.dest);
    }
};

/// WHAT THE STORE HOLDS. `Edge` is this rendered for a reader.
pub const Fact = struct {
    id: EdgeId,
    conv: Id,
    props: Properties,
    /// CONTENT identity — "what payload right now". Computed from the
    /// endpoints, the realization and the facts, and NOT from the family, so
    /// two families carrying the same conversion SHARE content while keeping
    /// separate `id`s. That is law.dedup exactly: share content nodes, never
    /// collapse semantic identity.
    content: u64,
    /// INCARNATION — which declaration in this family produced the fact now in
    /// the store. Every redeclaration bumps it, including one that changes
    /// nothing; an incarnation that were stable would not be one.
    incarnation: u32,
    loc: ast.Loc,
};

/// The content hash. Wyhash, matching `semantic_graph.zig`'s `StableId` — this
/// is a host hash for a bootstrap store, not the language's keyed hashing rule.
fn contentOf(src: Id, dest: Id, conv: Id, props: Properties) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(std.mem.asBytes(&src.n));
    h.update(std.mem.asBytes(&dest.n));
    h.update(std.mem.asBytes(&conv.n));
    h.update(&[_]u8{
        @intFromEnum(props.loss),
        @intFromEnum(props.storage),
        @intFromBool(props.failure),
        @intFromBool(props.consumes),
        @intFromBool(props.same_repr),
    });
    return h.final();
}

/// A derivation in identities. `Path` is this rendered.
pub const Route = struct {
    src: Id,
    dest: Id,
    mid: Id,
    first: Fact,
    second: Fact,
    props: Properties,
    admitted: bool,
};

/// The DECLARATION and RENDERING face of an edge — the spellings a declaration
/// site carried, or the spellings the store currently renders a `Fact` with.
/// Nothing in the algebra compares these fields; `declare` resolves them to
/// identities once, on the way in, and every answer comes back out through
/// `Relation.render`, which reads the interner's CURRENT text.
pub const Edge = struct {
    dest: []const u8,
    src: []const u8,
    /// The name of the callable that realizes this edge.
    conv: []const u8,
    props: Properties,
    loc: ast.Loc,
};

/// A conversion the trie ANSWERED but nobody wrote. `props` is the meet of the
/// hops; `admitted` is false when a hop's facts forbid silent composition, in
/// which case this value is a DIAGNOSTIC rather than a lowering.
pub const Path = struct {
    src: []const u8,
    dest: []const u8,
    mid: []const u8,
    first: Edge,
    second: Edge,
    props: Properties,
    admitted: bool,

    /// The A5 witness, rendered. Every derived conversion carries one; a
    /// derivation without a witness is unshipped.
    pub fn witness(self: Path, buf: []u8) []const u8 {
        var c1: [64]u8 = undefined;
        var c2: [64]u8 = undefined;
        var c3: [64]u8 = undefined;
        return std.fmt.bufPrint(
            buf,
            "derived {s} -> {s} via {s}: {s}({s}) then {s}({s}); class {s} meet {s} = {s}; {s}",
            .{
                self.src,              self.dest,               self.mid,
                self.first.conv,       self.first.src,          self.second.conv,
                self.second.src,       self.first.props.fmt(&c1), self.second.props.fmt(&c2),
                self.props.fmt(&c3),   if (self.admitted) "admitted" else "REFUSED: silent composition stops at lossless",
            },
        ) catch "derived edge (witness truncated)";
    }
};

/// One relation family's edge set. Flat storage: this is a trie by ACCESS, not
/// by layout, and at the sizes a single compilation unit reaches a scan beats a
/// map — the enumeration order also stays declaration order, which is what
/// makes `for src, conv in to[str]` reproducible.
pub const Relation = struct {
    /// The relation's own STABLE IDENTITY. `to` and `eq` are two identities,
    /// and a package shipping its own `to` gets a third rather than colliding
    /// with the prelude's.
    id: Id = Id.none,
    /// The relation's CURRENT spelling — rendering only, mirrored from the
    /// interner and refreshed by `Store.rename`, so a diagnostic can spell the
    /// relation it is talking about rather than assuming. `from` is NOT a
    /// family: it is the SAME edge read backwards (spec 2.6).
    name: []const u8,
    /// The store's interner. HEAP-OWNED by `Store`, so a `Relation` moved by
    /// an ArrayList growth keeps a valid pointer to it.
    ///
    /// NOT OPTIONAL AND WITHOUT A DEFAULT, deliberately: a relation with no
    /// identity space is a nonsense value, and making it a COMPILE error to
    /// construct one is stronger than a runtime branch and costs the callers
    /// nothing — `Store.getOrCreate` is the only constructor either way. It
    /// also keeps `declare`'s error set exactly what it was.
    names: *Names,
    facts: std.ArrayListUnmanaged(Fact) = .empty,
    /// How many declarations this family has ever taken. Mints incarnations.
    declarations: u32 = 0,

    pub fn deinit(self: *Relation, alloc: std.mem.Allocator) void {
        self.facts.deinit(alloc);
    }

    /// Land an edge FROM ITS DECLARED SPELLINGS. The spellings are resolved to
    /// identities here, once, and nothing below this line compares text.
    pub fn declare(self: *Relation, alloc: std.mem.Allocator, e: Edge) !void {
        const nm = self.names;
        try self.declareBy(
            alloc,
            try nm.intern(alloc, .{ .kind = .descriptor, .text = e.src }),
            try nm.intern(alloc, .{ .kind = .descriptor, .text = e.dest }),
            try nm.intern(alloc, .{ .kind = .callable, .text = e.conv }),
            e.props,
            e.loc,
        );
    }

    /// THE IDENTITY-NATIVE DECLARATION FACE. A redeclaration of the same
    /// SEMANTIC edge replaces the fact — last declaration wins, so a package
    /// may override an edge it inherits — and the semantic id SURVIVES while
    /// content and incarnation both move. Three identities, none collapsed.
    pub fn declareBy(
        self: *Relation,
        alloc: std.mem.Allocator,
        src: Id,
        dest: Id,
        conv: Id,
        props: Properties,
        loc: ast.Loc,
    ) !void {
        self.declarations += 1;
        const f = Fact{
            .id = .{ .relation = self.id, .src = src, .dest = dest },
            .conv = conv,
            .props = props,
            .content = contentOf(src, dest, conv, props),
            .incarnation = self.declarations,
            .loc = loc,
        };
        for (self.facts.items) |*existing| {
            if (existing.id.eq(f.id)) {
                existing.* = f;
                return;
            }
        }
        try self.facts.append(alloc, f);
    }

    /// Render a held fact for a reader. The text comes from the interner, so a
    /// rename shows up through every edge that mentions the renamed thing
    /// without a single edge being rewritten.
    pub fn render(self: *const Relation, f: Fact) Edge {
        const nm = self.names;
        return .{
            .dest = nm.text(f.id.dest),
            .src = nm.text(f.id.src),
            .conv = nm.text(f.conv),
            .props = f.props,
            .loc = f.loc,
        };
    }

    /// A descriptor spelling resolved to its identity in this store's default
    /// origin, scope and lawset — the front end's single lookup face.
    pub fn resolve(self: *const Relation, spelling: []const u8) ?Id {
        return self.names.lookup(.descriptor, spelling);
    }

    /// The authored fact, if one was declared. Identity-native.
    pub fn directBy(self: *const Relation, src: Id, dest: Id) ?Fact {
        for (self.facts.items) |f| {
            if (f.id.src.eq(src) and f.id.dest.eq(dest)) return f;
        }
        return null;
    }

    /// The authored edge, if one was written. Spellings in, rendering out; the
    /// comparison in the middle is on identities.
    pub fn direct(self: *const Relation, src: []const u8, dest: []const u8) ?Edge {
        const s = self.resolve(src) orelse return null;
        const d = self.resolve(dest) orelse return null;
        const f = self.directBy(s, d) orelse return null;
        return self.render(f);
    }

    /// THE COMPOSITION LAW. `a -> mid` composed with `mid -> b` derives `a -> b`.
    ///
    /// One hop, deliberately. A transitive closure over the whole trie would
    /// find longer paths, but it would also make the answer depend on search
    /// order the moment two paths exist, and A3 says a relationship is ONE
    /// fact — an ambiguous derivation is a mixed-space diagnostic, not a guess
    /// (G-TOTAL's ambiguity number is 0). One hop through a canonical hub is
    /// the shape the compression thesis actually claims, so it is the shape
    /// under test.
    ///
    /// Returns the path even when its facts REFUSE it, because the refusal is
    /// the more useful answer: the caller reports "there is a route and here is
    /// why you may not have it silently" instead of "no such conversion".
    pub fn routeBy(self: *const Relation, src: Id, dest: Id) ?Route {
        if (src.eq(dest)) return null;
        var admitted: ?Route = null;
        var refused: ?Route = null;
        for (self.facts.items) |first| {
            if (!first.id.src.eq(src)) continue;
            // `first.id.dest` is the candidate hub.
            for (self.facts.items) |second| {
                if (!second.id.dest.eq(dest)) continue;
                if (!second.id.src.eq(first.id.dest)) continue;
                const route = Route{
                    .src = src,
                    .dest = dest,
                    .mid = first.id.dest,
                    .first = first,
                    .second = second,
                    .props = Properties.meet(first.props, second.props),
                    .admitted = first.props.derivable() and second.props.derivable(),
                };
                if (route.admitted) {
                    // Two lawful paths require an upstream selection law. The
                    // store cannot let declaration order choose semantics.
                    if (admitted != null) return null;
                    admitted = route;
                } else if (refused == null) {
                    refused = route;
                }
            }
        }
        return admitted orelse refused;
    }

    /// The composition law's rendered face — spellings in, a readable `Path`
    /// with its witness out.
    pub fn derive(self: *const Relation, src: []const u8, dest: []const u8) ?Path {
        const s = self.resolve(src) orelse return null;
        const d = self.resolve(dest) orelse return null;
        const r = self.routeBy(s, d) orelse return null;
        const nm = self.names;
        return .{
            .src = nm.text(r.src),
            .dest = nm.text(r.dest),
            .mid = nm.text(r.mid),
            .first = self.render(r.first),
            .second = self.render(r.second),
            .props = r.props,
            .admitted = r.admitted,
        };
    }

    /// Enumeration is destination-keyed and demand-ordered: `to[str]` is every
    /// source that reaches `str`. Declaration order, so the loop is stable.
    pub fn intoDest(self: *const Relation, dest: []const u8, out: *std.ArrayListUnmanaged(Edge), alloc: std.mem.Allocator) !void {
        const d = self.resolve(dest) orelse return;
        for (self.facts.items) |f| {
            if (f.id.dest.eq(d)) try out.append(alloc, self.render(f));
        }
    }

    pub fn authored(self: *const Relation) usize {
        return self.facts.items.len;
    }

    /// Every ordered pair the trie can answer that NOBODY WROTE. This is the
    /// numerator of SER and it is computed, never declared.
    ///
    /// `refused` counts pairs a route exists for whose facts forbid silent
    /// composition. They are reported separately and NOT counted as derived:
    /// a conversion the compiler will not perform is not a capability, and
    /// folding it into the headline is the exact dishonesty this gap was filed
    /// against.
    pub fn derivedCount(self: *const Relation, alloc: std.mem.Allocator, refused: *usize) !usize {
        var descs: std.ArrayListUnmanaged(Id) = .empty;
        defer descs.deinit(alloc);
        try self.endpoints(&descs, alloc);
        var derived: usize = 0;
        refused.* = 0;
        for (descs.items) |a| {
            for (descs.items) |b| {
                if (a.eq(b)) continue;
                if (self.directBy(a, b) != null) continue;
                const r = self.routeBy(a, b) orelse continue;
                if (r.admitted) derived += 1 else refused.* += 1;
            }
        }
        return derived;
    }

    /// Distinct descriptors mentioned by any edge — the N that every published
    /// SER must carry. A ratio without its universe is not a measurement.
    ///
    /// Distinct BY IDENTITY, which is a correctness change and not only a
    /// refactor: under the text key, two packages' `micron` counted once and
    /// the ratio was computed over a universe that did not exist.
    pub fn universe(self: *const Relation, alloc: std.mem.Allocator) !usize {
        var descs: std.ArrayListUnmanaged(Id) = .empty;
        defer descs.deinit(alloc);
        try self.endpoints(&descs, alloc);
        return descs.items.len;
    }

    fn endpoints(self: *const Relation, out: *std.ArrayListUnmanaged(Id), alloc: std.mem.Allocator) !void {
        for (self.facts.items) |f| {
            try addUnique(out, alloc, f.id.src);
            try addUnique(out, alloc, f.id.dest);
        }
    }

    fn addUnique(list: *std.ArrayListUnmanaged(Id), alloc: std.mem.Allocator, id: Id) !void {
        for (list.items) |x| {
            if (x.eq(id)) return;
        }
        try list.append(alloc, id);
    }
};

/// Every relation family a compilation unit carries. Families are created by
/// their first declaration and looked up by the call/enumeration faces by
/// name; there is no separate registry a family must be entered into, which is
/// what keeps "add a family" a data fact rather than a code change.
pub const Store = struct {
    families: std.ArrayListUnmanaged(Relation) = .empty,
    /// The compilation unit's identity space, HEAP-OWNED so that a `Relation`
    /// relocated by an ArrayList growth keeps a valid pointer to it. Identities
    /// belong to the unit, not to a struct, so a `Store` copied by value shares
    /// one identity space with its copy — which is the correct reading.
    names: ?*Names = null,

    pub fn deinit(self: *Store, alloc: std.mem.Allocator) void {
        for (self.families.items) |*f| f.deinit(alloc);
        self.families.deinit(alloc);
        if (self.names) |nm| {
            nm.deinit(alloc);
            alloc.destroy(nm);
            self.names = null;
        }
    }

    /// The identity space, created on first sight.
    pub fn interner(self: *Store, alloc: std.mem.Allocator) !*Names {
        if (self.names) |nm| return nm;
        const nm = try alloc.create(Names);
        nm.* = .{};
        self.names = nm;
        return nm;
    }

    pub fn intern(self: *Store, alloc: std.mem.Allocator, name: Name) !Id {
        const nm = try self.interner(alloc);
        return nm.intern(alloc, name);
    }

    /// A descriptor in the default origin, scope and lawset — what the front
    /// end has to offer today.
    pub fn descriptor(self: *Store, alloc: std.mem.Allocator, spelling: []const u8) !Id {
        return self.intern(alloc, .{ .kind = .descriptor, .text = spelling });
    }

    pub fn callable(self: *Store, alloc: std.mem.Allocator, spelling: []const u8) !Id {
        return self.intern(alloc, .{ .kind = .callable, .text = spelling });
    }

    /// An identity's CURRENT spelling, for rendering.
    pub fn text(self: *const Store, id: Id) []const u8 {
        const nm = self.names orelse return "";
        return nm.text(id);
    }

    pub fn at(self: *const Store, id: Id) ?Record {
        const nm = self.names orelse return null;
        return nm.at(id);
    }

    /// RENAME. Edges are untouched — that is the whole point — and a family's
    /// mirrored spelling is refreshed so diagnostics do not lie.
    pub fn rename(self: *Store, id: Id, to: []const u8) !void {
        const nm = self.names orelse return error.NoSuchIdentity;
        try nm.rename(id, to);
        for (self.families.items) |*f| {
            if (f.id.eq(id)) f.name = nm.text(id);
        }
    }

    /// The family by name, or null when nothing has declared one. `from` is
    /// deliberately NOT a family: it is the same edge read backwards.
    pub fn family(self: *const Store, name: []const u8) ?*const Relation {
        const nm = self.names orelse return null;
        const id = nm.lookup(.relation, name) orelse return null;
        return self.familyBy(id);
    }

    pub fn familyBy(self: *const Store, id: Id) ?*const Relation {
        for (self.families.items) |*f| {
            if (f.id.eq(id)) return f;
        }
        return null;
    }

    /// The family by name, creating it on first sight. The returned pointer is
    /// stable only until the NEXT `getOrCreate` reallocates the family list, so
    /// callers must not hold it across one.
    pub fn getOrCreate(self: *Store, alloc: std.mem.Allocator, name: []const u8) !*Relation {
        const nm = try self.interner(alloc);
        const id = try nm.intern(alloc, .{ .kind = .relation, .text = name });
        for (self.families.items) |*f| {
            if (f.id.eq(id)) return f;
        }
        try self.families.append(alloc, .{ .id = id, .name = nm.text(id), .names = nm });
        return &self.families.items[self.families.items.len - 1];
    }

    /// How many families exist. Every line of the `[ser]` census belongs to one
    /// of these.
    pub fn declared(self: *const Store) usize {
        return self.families.items.len;
    }
};

/// The declaration face, recognised off an ORDINARY ASSIGNMENT.
///
/// `to(dest)(src) = conv` and `to(dest)(src) = conv@class`. No new statement
/// kind, no new token, no new keyword: the shape already parsed, it simply had
/// no meaning and lowered to `tostring("u32") = digits`, which clang rejected
/// as "expression is not assignable". A2 NNS-FIRST is not a style preference
/// here — it is why this whole mechanism is a recogniser rather than a grammar
/// change.
///
/// Any relation family answers the same shape; there is no per-name gate. The
/// shape test is strict on all four levels, and nothing else in the corpus uses
/// it (the value must be a bare name or `name@class`), so claiming it for the
/// store cannot hijack an ordinary assignment.
pub const Decl = struct {
    relation: []const u8,
    dest: []const u8,
    src: []const u8,
    conv: []const u8,
    class: Class,
    loc: ast.Loc,
};

/// Is this assignment a relation-edge declaration? Returns the decoded edge, or
/// null for every ordinary assignment — which must stay the overwhelming case,
/// so the shape test is strict on all four levels before it claims anything.
pub fn declFromAssign(as: anytype) ?Decl {
    if (as.targets.len != 1 or as.values.len != 1) return null;
    const target = as.targets[0];
    if (target.* != .call) return null;
    const outer = target.call;
    // `to(dest)(src)`: the group NEAREST the relation is the DESTINATION, which
    // is what makes the declaration face read the same way as the call face
    // (`v:to(dest)`) and the enumeration face (`to[dest]`). So the INNER call's
    // argument is the destination and the OUTER call's is the source — the two
    // are easy to transpose and the trie answers a confidently wrong question
    // if you do, which is why they are named rather than positional below.
    if (outer.args.len != 1 or outer.args[0].* != .name) return null;
    if (outer.func.* != .call) return null;
    const inner = outer.func.call;
    if (inner.args.len != 1 or inner.args[0].* != .name) return null;
    if (inner.func.* != .name) return null;
    const rel = inner.func.name.ident;

    // The value side names the callable, optionally anchored with its class.
    // `x@class` already parses to a field walk (parser.zig, the glued-anchor
    // arm), so the class fact rides an existing form too.
    const value = as.values[0];
    var conv: []const u8 = undefined;
    var class: Class = .exact;
    switch (value.*) {
        .name => |n| conv = n.ident,
        .field => |f| {
            if (f.obj.* != .name) return null;
            conv = f.obj.name.ident;
            class = Class.parse(f.field) orelse return null;
        },
        else => return null,
    }
    return .{
        .relation = rel,
        .dest = inner.args[0].name.ident,
        .src = outer.args[0].name.ident,
        .conv = conv,
        .class = class,
        .loc = inner.func.name.loc,
    };
}

const testing = std.testing;

fn testEdge(dest: []const u8, src: []const u8, conv: []const u8, c: Class) Edge {
    return .{
        .dest = dest,
        .src = src,
        .conv = conv,
        .props = c.to_properties(),
        .loc = .{ .file = "relation_test", .line = 1, .col = 1 },
    };
}

// Returns the SLICE `fmt` wrote, not the whole buffer. Returning `[64]u8`
// meant every comparison also saw 52 bytes of `undefined` tail — the test
// read as a `fmt` bug when the helper was the bug.
fn fmtBuf(p: Properties, buf: []u8) []const u8 {
    return p.fmt(buf);
}

test "a store holds many relation families" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    _ = try store.getOrCreate(testing.allocator, "to");
    _ = try store.getOrCreate(testing.allocator, "eq");
    _ = try store.getOrCreate(testing.allocator, "ord");
    try testing.expectEqual(@as(usize, 3), store.declared());
    try testing.expect(store.family("to") != null);
    try testing.expect(store.family("eq") != null);
    try testing.expect(store.family("ord") != null);
    try testing.expect(store.family("iter") == null);
}

test "the to family derives through a hub; other families are untouched" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    try to.declare(testing.allocator, testEdge("micron", "inch", "stretch", .lossless));
    try to.declare(testing.allocator, testEdge("inch", "micron", "shrink", .lossless));
    try to.declare(testing.allocator, testEdge("micron", "milli", "swell", .lossless));
    try to.declare(testing.allocator, testEdge("milli", "micron", "shrivel", .lossless));

    // inch -> milli was never written; composition answers it.
    const path = to.derive("inch", "milli") orelse return error.NoDerivation;
    try testing.expect(path.admitted);
    try testing.expectEqualStrings("micron", path.mid);

    // The inverse is the same edge read backwards, not a second family.
    const back = to.derive("milli", "inch") orelse return error.NoDerivation;
    try testing.expect(back.admitted);

    // SER: 2 derived, nothing refused, N = 3.
    var refused: usize = 0;
    const derived = try to.derivedCount(testing.allocator, &refused);
    try testing.expectEqual(@as(usize, 2), derived);
    try testing.expectEqual(@as(usize, 0), refused);
    try testing.expectEqual(@as(usize, 3), try to.universe(testing.allocator));
    try testing.expectEqual(@as(usize, 4), to.authored());

    // `eq` was never declared in this store — no bleed between families.
    try testing.expect(store.family("eq") == null);
    try testing.expectEqual(@as(usize, 1), store.declared());
}

test "two lawful hubs are ambiguous and never select by declaration order" {
    var first = Store{};
    defer first.deinit(testing.allocator);
    const first_to = try first.getOrCreate(testing.allocator, "to");
    try first_to.declare(testing.allocator, testEdge("left", "a", "aleft", .lossless));
    try first_to.declare(testing.allocator, testEdge("b", "left", "leftb", .lossless));
    try first_to.declare(testing.allocator, testEdge("right", "a", "aright", .lossless));
    try first_to.declare(testing.allocator, testEdge("b", "right", "rightb", .lossless));
    try testing.expect(first_to.direct("a", "left") != null);
    try testing.expect(first_to.direct("left", "b") != null);
    try testing.expect(first_to.direct("a", "right") != null);
    try testing.expect(first_to.direct("right", "b") != null);
    try testing.expect(first_to.derive("a", "b") == null);

    var second = Store{};
    defer second.deinit(testing.allocator);
    const second_to = try second.getOrCreate(testing.allocator, "to");
    try second_to.declare(testing.allocator, testEdge("right", "a", "aright", .lossless));
    try second_to.declare(testing.allocator, testEdge("b", "right", "rightb", .lossless));
    try second_to.declare(testing.allocator, testEdge("left", "a", "aleft", .lossless));
    try second_to.declare(testing.allocator, testEdge("b", "left", "leftb", .lossless));
    try testing.expect(second_to.direct("a", "right") != null);
    try testing.expect(second_to.direct("right", "b") != null);
    try testing.expect(second_to.direct("a", "left") != null);
    try testing.expect(second_to.direct("left", "b") != null);
    try testing.expect(second_to.derive("a", "b") == null);
}

test "overlapping relation families retain independent facts" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    const adapt = try store.getOrCreate(testing.allocator, "adapt");
    try to.declare(testing.allocator, testEdge("micron", "inch", "shrink", .exact));
    try to.declare(testing.allocator, testEdge("milli", "micron", "swell", .exact));
    try adapt.declare(testing.allocator, testEdge("milli", "inch", "bridge", .lossless));

    const path = to.derive("inch", "milli") orelse return error.NoDerivation;
    try testing.expect(path.admitted);
    try testing.expectEqualStrings("micron", path.mid);
    const direct = adapt.direct("inch", "milli") orelse return error.NoDerivation;
    try testing.expectEqualStrings("bridge", direct.conv);
    try testing.expect(to.direct("inch", "milli") == null);
    try testing.expect(adapt.derive("inch", "milli") == null);

    try to.declare(testing.allocator, testEdge("milli", "micron", "narrow", .narrowing));
    const refused = to.derive("inch", "milli") orelse return error.NoDerivation;
    try testing.expect(!refused.admitted);
    try testing.expectEqualStrings("bridge", adapt.direct("inch", "milli").?.conv);
    try testing.expectEqual(@as(usize, 2), store.declared());
}

test "a lossy or failing hop is found and REFUSED, never silently composed" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    try to.declare(testing.allocator, testEdge("micron", "inch", "stretch", .exact));
    try to.declare(testing.allocator, testEdge("inch", "micron", "shrink", .narrowing));
    try to.declare(testing.allocator, testEdge("micron", "milli", "swell", .exact));
    try to.declare(testing.allocator, testEdge("milli", "micron", "shrivel", .narrowing));

    const p = to.derive("inch", "milli") orelse return error.NoDerivation;
    try testing.expect(!p.admitted);

    // narrowing meets exact = narrowing: the one-weak-hop rule is fact-wise.
    try testing.expectEqual(Loss.some, p.props.loss);
    var nbuf: [64]u8 = undefined;
    try testing.expectEqualStrings("narrowing", fmtBuf(p.props, &nbuf));

    var refused: usize = 0;
    const derived = try to.derivedCount(testing.allocator, &refused);
    try testing.expectEqual(@as(usize, 0), derived);
    try testing.expectEqual(@as(usize, 2), refused);
}

test "a meet outside the six classes renders as facts, not a wrong class" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    try to.declare(testing.allocator, testEdge("mid", "a", "one", .checked));
    try to.declare(testing.allocator, testEdge("b", "mid", "two", .view));

    const p = to.derive("a", "b") orelse return error.NoDerivation;
    try testing.expect(!p.admitted);
    // checked ∘ view was never one of the six classes; the old lattice lied by
    // printing `checked`. The facts print `failure view`.
    var fbuf: [64]u8 = undefined;
    try testing.expectEqualStrings("failure view", fmtBuf(p.props, &fbuf));
}

// ── law.identity.three ──────────────────────────────────────────────────────
//
// Every test below has a NEGATIVE TWIN in the same body: the discriminator is
// shown to SEPARATE two things AND to KEEP one thing one thing. A test that
// only proves separation cannot tell a working discriminator from an interner
// that mints a fresh number every call.

const testloc = ast.Loc{ .file = "relation_test", .line = 1, .col = 1 };

fn declareIds(rel: *Relation, src: Id, dest: Id, conv: Id, c: Class) !void {
    try rel.declareBy(testing.allocator, src, dest, conv, c.to_properties(), testloc);
}

test "an identity is minted once per key and reused — the control for every split below" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const a = try store.descriptor(testing.allocator, "micron");
    const b = try store.descriptor(testing.allocator, "micron");
    try testing.expect(a.eq(b));
    try testing.expectEqual(@as(usize, 1), store.names.?.count());

    // NEGATIVE TWIN: a different spelling is a different identity, so the
    // interner is not simply answering with a constant.
    const c = try store.descriptor(testing.allocator, "inch");
    try testing.expect(!a.eq(c));
    try testing.expectEqual(@as(usize, 2), store.names.?.count());
}

test "packages: one spelling in two packages is two descriptors" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const mine = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "1" } });
    const theirs = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "b", .version = "1" } });
    try testing.expect(!mine.eq(theirs));

    // NEGATIVE TWIN: the same package is the same descriptor.
    const again = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "1" } });
    try testing.expect(mine.eq(again));
}

test "packages: two same-spelled hubs do NOT compose — the text key derived an edge that does not exist" {
    // The sharpest form of the bug, as BEHAVIOUR rather than as an inequality.
    // `inch -> micron(a)` and `micron(b) -> foot` share no descriptor, so there
    // is no route from `inch` to `foot`. Keyed on text, both hops read
    // "micron", the trie composed them, and the compiler emitted a conversion
    // through two unrelated descriptors.
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");

    const inch = try store.descriptor(testing.allocator, "inch");
    const foot = try store.descriptor(testing.allocator, "foot");
    const conv = try store.callable(testing.allocator, "scale");
    const hub_a = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "1" } });
    const hub_b = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "b", .version = "1" } });

    try declareIds(to, inch, hub_a, conv, .lossless);
    try declareIds(to, hub_b, foot, conv, .lossless);
    try testing.expect(to.routeBy(inch, foot) == null);

    // Two hubs, so the universe is FOUR descriptors and nothing derives.
    var refused: usize = 0;
    try testing.expectEqual(@as(usize, 0), try to.derivedCount(testing.allocator, &refused));
    try testing.expectEqual(@as(usize, 0), refused);
    try testing.expectEqual(@as(usize, 4), try to.universe(testing.allocator));

    // NEGATIVE TWIN: one hub, and the same two hops compose immediately. The
    // refusal above is the identity split talking, not a broken `routeBy`.
    const one = try store.getOrCreate(testing.allocator, "eq");
    try declareIds(one, inch, hub_a, conv, .lossless);
    try declareIds(one, hub_a, foot, conv, .lossless);
    const r = one.routeBy(inch, foot) orelse return error.NoDerivation;
    try testing.expect(r.admitted);
    try testing.expect(r.mid.eq(hub_a));
}

test "versions: a@1's micron and a@2's micron coexist" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const v1 = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "1" } });
    const v2 = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "2" } });
    try testing.expect(!v1.eq(v2));

    // NEGATIVE TWIN: one version is one descriptor.
    const v1again = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "micron", .origin = .{ .package = "a", .version = "1" } });
    try testing.expect(v1.eq(v1again));
}

test "private: two modules' private scratch never answer each other" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const mine = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "scratch", .scope = .{ .exported = false, .owner = "lexer" } });
    const theirs = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "scratch", .scope = .{ .exported = false, .owner = "parser" } });
    try testing.expect(!mine.eq(theirs));

    // A private `scratch` is also not the EXPORTED `scratch`.
    const public = try store.descriptor(testing.allocator, "scratch");
    try testing.expect(!mine.eq(public));
    try testing.expect(!theirs.eq(public));

    // NEGATIVE TWIN: one owner is one descriptor.
    const again = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "scratch", .scope = .{ .exported = false, .owner = "lexer" } });
    try testing.expect(mine.eq(again));
}

test "lawset: a lua number and an Idol number are two identities" {
    // THE LUA FIREWALL as an identity fact. Idol laws may never prove a Lua
    // optimization, and the first place that has to hold is the identity that
    // an edge is keyed on.
    var store = Store{};
    defer store.deinit(testing.allocator);
    const native = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "number", .lawset = .idol });
    const lua = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "number", .lawset = .lua });
    try testing.expect(!native.eq(lua));

    // NEGATIVE TWIN: one lawset is one descriptor.
    const again = try store.intern(testing.allocator, .{ .kind = .descriptor, .text = "number", .lawset = .lua });
    try testing.expect(lua.eq(again));
}

test "kind: a descriptor `to` and a relation `to` share a spelling and nothing else" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const desc = try store.descriptor(testing.allocator, "to");
    const call = try store.callable(testing.allocator, "to");
    const fam = try store.intern(testing.allocator, .{ .kind = .relation, .text = "to" });
    try testing.expect(!desc.eq(call));
    try testing.expect(!desc.eq(fam));
    try testing.expect(!call.eq(fam));

    // NEGATIVE TWIN: one kind is one identity.
    try testing.expect(desc.eq(try store.descriptor(testing.allocator, "to")));
}

test "renames: the spelling moves and the identity does not — every edge survives" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    try to.declare(testing.allocator, testEdge("micron", "inch", "stretch", .lossless));
    try to.declare(testing.allocator, testEdge("inch", "micron", "shrink", .lossless));
    try to.declare(testing.allocator, testEdge("micron", "milli", "swell", .lossless));
    try to.declare(testing.allocator, testEdge("milli", "micron", "shrivel", .lossless));

    const hub = to.resolve("micron") orelse return error.NoIdentity;
    var refused: usize = 0;
    const before = try to.derivedCount(testing.allocator, &refused);

    try store.rename(hub, "micrometre");

    // THE IDENTITY DID NOT MOVE, so the algebra did not notice.
    try testing.expect(to.resolve("micrometre").?.eq(hub));
    try testing.expectEqual(@as(usize, 4), to.authored());
    try testing.expectEqual(before, try to.derivedCount(testing.allocator, &refused));
    try testing.expectEqual(@as(usize, 0), refused);
    try testing.expectEqual(@as(usize, 3), try to.universe(testing.allocator));
    const path = to.derive("inch", "milli") orelse return error.NoDerivation;
    try testing.expect(path.admitted);

    // The RENDERING moved, everywhere, without an edge being rewritten.
    try testing.expectEqualStrings("micrometre", path.mid);
    try testing.expectEqualStrings("micrometre", to.direct("inch", "micrometre").?.dest);

    // NEGATIVE TWIN: the OLD spelling stops answering. Without this the test
    // would pass on an interner that simply added a second name for one id.
    try testing.expect(to.resolve("micron") == null);
    try testing.expect(to.direct("inch", "micron") == null);

    // The minting spelling is kept for forensics and is never a key.
    try testing.expectEqualStrings("micron", store.at(hub).?.minted);
}

test "renames: a rename onto an occupied spelling is REFUSED, never a merge" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const inch = try store.descriptor(testing.allocator, "inch");
    _ = try store.descriptor(testing.allocator, "foot");
    try testing.expectError(error.NameTaken, store.rename(inch, "foot"));
    try testing.expectEqualStrings("inch", store.text(inch));

    // NEGATIVE TWIN: renaming onto a FREE spelling succeeds, and renaming an
    // identity to the spelling it already has is a no-op rather than a clash
    // with itself.
    try store.rename(inch, "thumb");
    try testing.expectEqualStrings("thumb", store.text(inch));
    try store.rename(inch, "thumb");
    try testing.expectEqualStrings("thumb", store.text(inch));
}

test "law.dedup: two families SHARE content and never share semantic identity" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    const eq = try store.getOrCreate(testing.allocator, "eq");
    const i = try store.descriptor(testing.allocator, "i64");
    const f = try store.descriptor(testing.allocator, "f64");
    const conv = try store.callable(testing.allocator, "widen");

    try declareIds(to, i, f, conv, .lossless);
    try declareIds(eq, i, f, conv, .lossless);
    const a = to.directBy(i, f).?;
    const b = eq.directBy(i, f).?;

    // CONTENT may be shared — the normalized subgraph is the same one.
    try testing.expectEqual(a.content, b.content);
    // SEMANTIC IDENTITY may NOT. `to` and `eq` are two relationships.
    try testing.expect(!a.id.eq(b.id));

    // NEGATIVE TWIN: change the payload and the content identity moves, so the
    // equality above is a measurement and not a constant.
    const other = try store.callable(testing.allocator, "promote");
    try declareIds(eq, i, f, other, .lossless);
    try testing.expect(eq.directBy(i, f).?.content != a.content);
    // …and changing only the FACTS moves it too.
    try declareIds(eq, i, f, conv, .checked);
    try testing.expect(eq.directBy(i, f).?.content != a.content);
}

test "law.identity.three: a redeclaration keeps the edge, moves content, bumps incarnation" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    const i = try store.descriptor(testing.allocator, "i64");
    const s = try store.descriptor(testing.allocator, "str");
    const digits = try store.callable(testing.allocator, "digits");
    const roman = try store.callable(testing.allocator, "roman");

    try declareIds(to, i, s, digits, .lossless);
    const first = to.directBy(i, s).?;
    try declareIds(to, i, s, roman, .lossless);
    const second = to.directBy(i, s).?;

    try testing.expectEqual(@as(usize, 1), to.authored());
    try testing.expect(first.id.eq(second.id)); // semantic: the same relationship
    try testing.expect(first.content != second.content); // content: a new payload
    try testing.expect(first.incarnation != second.incarnation); // incarnation: a new occurrence
    try testing.expectEqual(@as(u32, 2), second.incarnation);

    // NEGATIVE TWIN: redeclaring the IDENTICAL edge keeps semantic identity AND
    // content, and STILL bumps the incarnation — an incarnation that held still
    // would not be one.
    try declareIds(to, i, s, roman, .lossless);
    const third = to.directBy(i, s).?;
    try testing.expect(second.id.eq(third.id));
    try testing.expectEqual(second.content, third.content);
    try testing.expectEqual(@as(u32, 3), third.incarnation);
}

test "the hub shape derives six edges nobody wrote — SER 2.00 at N = 4" {
    // The unit twin of `examples/spec100/relation.id`, which is what actually
    // runs the compiler. This pins the STORE's numbers so a regression names
    // the store rather than the fixture.
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    for ([_][3][]const u8{
        .{ "micron", "inch", "stretch" },
        .{ "inch", "micron", "shrink" },
        .{ "micron", "milli", "swell" },
        .{ "milli", "micron", "shrivel" },
        .{ "micron", "foot", "expand" },
        .{ "foot", "micron", "compress" },
    }) |row| try to.declare(testing.allocator, testEdge(row[0], row[1], row[2], .lossless));

    var refused: usize = 0;
    try testing.expectEqual(@as(usize, 6), to.authored());
    try testing.expectEqual(@as(usize, 6), try to.derivedCount(testing.allocator, &refused));
    try testing.expectEqual(@as(usize, 0), refused);
    try testing.expectEqual(@as(usize, 4), try to.universe(testing.allocator));
}

test "the SAME six edges narrowing derive NOTHING — the control for the six above" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const to = try store.getOrCreate(testing.allocator, "to");
    for ([_][3][]const u8{
        .{ "micron", "inch", "stretch" },
        .{ "inch", "micron", "shrink" },
        .{ "micron", "milli", "swell" },
        .{ "milli", "micron", "shrivel" },
        .{ "micron", "foot", "expand" },
        .{ "foot", "micron", "compress" },
    }) |row| try to.declare(testing.allocator, testEdge(row[0], row[1], row[2], .narrowing));

    var refused: usize = 0;
    try testing.expectEqual(@as(usize, 0), try to.derivedCount(testing.allocator, &refused));
    try testing.expectEqual(@as(usize, 6), refused);
    try testing.expectEqual(@as(usize, 4), try to.universe(testing.allocator));
}

test "declFromAssign refuses an ordinary assignment" {
    // No AST needed here: the shape test is a recogniser, and the recogniser
    // itself is exercised end-to-end by the spec100 relation fixtures through
    // the compiler. What a unit test CAN pin cheaply is the null answer for a
    // plain two-name assignment, which must stay the overwhelming case.
    const target = ast.Expr{ .name = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .ident = "x" } };
    const value = ast.Expr{ .name = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .ident = "y" } };
    // `ast.Assign` does not exist — `assign` is an ANONYMOUS struct inside the
    // `Stmt` union, so there is no named type to construct. `declFromAssign`
    // takes `anytype` and reads three fields, so the recogniser's real contract
    // is structural: this literal IS what it receives at every call site.
    const as = .{ .loc = ast.Loc{ .file = "t", .line = 1, .col = 1 }, .targets = &[_]*ast.Expr{@constCast(&target)}, .values = &[_]*ast.Expr{@constCast(&value)} };
    try testing.expect(declFromAssign(&as) == null);
}
