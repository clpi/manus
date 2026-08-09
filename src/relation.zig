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
//! are three of the six irreducible primitives in `docs/spec/constitution.duo`.
//! The final shape has no `ConversionRelation`, `ConversionEdge`,
//! `ConversionClass` or `ConversionPath` in it.
//!
//! Recorded now, at the moment the file is USEFUL, because that is when the
//! pressure to fossilize starts. GAP-084 was this repository's registry problem;
//! a registry that returns under a cleaner name is the same defect. Two rows of
//! `law.architecture.owner`'s deny list — `*Registry`, `*Kernel` — were written
//! against exactly this trajectory.
//!
//! KNOWN BOOTSTRAP DEBT, so it is measured rather than discovered later:
//!   - descriptor and callable identities are `[]const u8`. Textual names doing
//!     semantic-identity work is the root of a whole family of live bugs
//!     (`law.identity.three`), and it breaks packages, renames, MCP,
//!     refactoring, version coexistence and private descriptors. Stable
//!     semantic ids retire it.
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
    /// The relation's own name — `to`, `eq`, `from` is NOT one: it is the SAME
    /// edge read backwards (spec 2.6) and must never get a family of its own.
    /// Held so a diagnostic can spell the relation it is talking about rather
    /// than assuming.
    name: []const u8,
    edges: std.ArrayListUnmanaged(Edge) = .empty,

    pub fn deinit(self: *Relation, alloc: std.mem.Allocator) void {
        self.edges.deinit(alloc);
    }

    /// Land an edge. A redeclaration of the same (src, dest) REPLACES, so the
    /// last declaration wins and a package may override an edge it inherits.
    pub fn declare(self: *Relation, alloc: std.mem.Allocator, e: Edge) !void {
        for (self.edges.items) |*existing| {
            if (std.mem.eql(u8, existing.src, e.src) and std.mem.eql(u8, existing.dest, e.dest)) {
                existing.* = e;
                return;
            }
        }
        try self.edges.append(alloc, e);
    }

    /// The authored edge, if one was written.
    pub fn direct(self: *const Relation, src: []const u8, dest: []const u8) ?Edge {
        for (self.edges.items) |e| {
            if (std.mem.eql(u8, e.src, src) and std.mem.eql(u8, e.dest, dest)) return e;
        }
        return null;
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
    pub fn derive(self: *const Relation, src: []const u8, dest: []const u8) ?Path {
        if (std.mem.eql(u8, src, dest)) return null;
        var found: ?Path = null;
        for (self.edges.items) |first| {
            if (!std.mem.eql(u8, first.src, src)) continue;
            // `first.dest` is the candidate hub.
            for (self.edges.items) |second| {
                if (!std.mem.eql(u8, second.dest, dest)) continue;
                if (!std.mem.eql(u8, second.src, first.dest)) continue;
                const path = Path{
                    .src = src,
                    .dest = dest,
                    .mid = first.dest,
                    .first = first,
                    .second = second,
                    .props = Properties.meet(first.props, second.props),
                    .admitted = first.props.derivable() and second.props.derivable(),
                };
                // Prefer an admitted path; keep a refused one only to explain.
                if (path.admitted) return path;
                if (found == null) found = path;
            }
        }
        return found;
    }

    /// Enumeration is destination-keyed and demand-ordered: `to[str]` is every
    /// source that reaches `str`. Declaration order, so the loop is stable.
    pub fn intoDest(self: *const Relation, dest: []const u8, out: *std.ArrayListUnmanaged(Edge), alloc: std.mem.Allocator) !void {
        for (self.edges.items) |e| {
            if (std.mem.eql(u8, e.dest, dest)) try out.append(alloc, e);
        }
    }

    pub fn authored(self: *const Relation) usize {
        return self.edges.items.len;
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
        var descs: std.ArrayListUnmanaged([]const u8) = .empty;
        defer descs.deinit(alloc);
        for (self.edges.items) |e| {
            try addUnique(&descs, alloc, e.src);
            try addUnique(&descs, alloc, e.dest);
        }
        var derived: usize = 0;
        refused.* = 0;
        for (descs.items) |a| {
            for (descs.items) |b| {
                if (std.mem.eql(u8, a, b)) continue;
                if (self.direct(a, b) != null) continue;
                const p = self.derive(a, b) orelse continue;
                if (p.admitted) derived += 1 else refused.* += 1;
            }
        }
        return derived;
    }

    /// Distinct descriptors mentioned by any edge — the N that every published
    /// SER must carry. A ratio without its universe is not a measurement.
    pub fn universe(self: *const Relation, alloc: std.mem.Allocator) !usize {
        var descs: std.ArrayListUnmanaged([]const u8) = .empty;
        defer descs.deinit(alloc);
        for (self.edges.items) |e| {
            try addUnique(&descs, alloc, e.src);
            try addUnique(&descs, alloc, e.dest);
        }
        return descs.items.len;
    }

    fn addUnique(list: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, name: []const u8) !void {
        for (list.items) |x| {
            if (std.mem.eql(u8, x, name)) return;
        }
        try list.append(alloc, name);
    }
};

/// Every relation family a compilation unit carries. Families are created by
/// their first declaration and looked up by the call/enumeration faces by
/// name; there is no separate registry a family must be entered into, which is
/// what keeps "add a family" a data fact rather than a code change.
pub const Store = struct {
    families: std.ArrayListUnmanaged(Relation) = .empty,

    pub fn deinit(self: *Store, alloc: std.mem.Allocator) void {
        for (self.families.items) |*f| f.deinit(alloc);
        self.families.deinit(alloc);
    }

    /// The family by name, or null when nothing has declared one. `from` is
    /// deliberately NOT a family: it is the same edge read backwards.
    pub fn family(self: *const Store, name: []const u8) ?*const Relation {
        for (self.families.items) |*f| {
            if (std.mem.eql(u8, f.name, name)) return f;
        }
        return null;
    }

    /// The family by name, creating it on first sight. The returned pointer is
    /// stable only until the NEXT `getOrCreate` reallocates the family list, so
    /// callers must not hold it across one.
    pub fn getOrCreate(self: *Store, alloc: std.mem.Allocator, name: []const u8) !*Relation {
        if (self.family(name)) |f| return @constCast(f);
        try self.families.append(alloc, .{ .name = name });
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

fn fmtBuf(p: Properties) [64]u8 {
    var buf: [64]u8 = undefined;
    _ = p.fmt(&buf);
    return buf;
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

test "an eq family composes independently of to" {
    var store = Store{};
    defer store.deinit(testing.allocator);
    const eq = try store.getOrCreate(testing.allocator, "eq");
    try eq.declare(testing.allocator, testEdge("f64", "i64", "eqfi", .lossless));
    try eq.declare(testing.allocator, testEdge("i64", "f64", "eqif", .lossless));

    // i64 == f64 comparability derives; the to family does not see it.
    const p = eq.derive("f64", "i64") orelse return error.NoDerivation;
    try testing.expect(p.admitted);
    var refused: usize = 0;
    try testing.expectEqual(@as(usize, 0), try eq.derivedCount(testing.allocator, &refused));
    try testing.expectEqual(@as(usize, 2), eq.authored());
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
    try testing.expectEqualStrings("narrowing", &fmtBuf(p.props));

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
    try testing.expectEqualStrings("failure view", &fmtBuf(p.props));
}

test "declFromAssign refuses an ordinary assignment" {
    // No AST needed here: the shape test is a recogniser, and the recogniser
    // itself is exercised end-to-end by the spec100 relation fixtures through
    // the compiler. What a unit test CAN pin cheaply is the null answer for a
    // plain two-name assignment, which must stay the overwhelming case.
    const target = ast.Expr{ .name = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .ident = "x" } };
    const value = ast.Expr{ .name = .{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .ident = "y" } };
    const as = ast.Assign{ .loc = .{ .file = "t", .line = 1, .col = 1 }, .targets = &[_]*ast.Expr{@constCast(&target)}, .values = &[_]*ast.Expr{@constCast(&value)} };
    try testing.expect(declFromAssign(&as) == null);
}
