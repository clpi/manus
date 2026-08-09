//! The conversion trie — gap[082], Pass 100 §9 ("Relations, the trie, protocols,
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
//! authority**: `Class`, `Edge`, `Path` and `Relation` are host structs that
//! project onto `relation` / `fact` / `witness`, which are three of the six
//! irreducible primitives in `docs/spec/constitution.duo`. The final shape has
//! no `ConversionRelation`, `ConversionEdge`, `ConversionClass` or
//! `ConversionPath` in it.
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
//!
//! THE ALGEBRA. `derive` is the one composition law: an undeclared `a -> b` is
//! answered by `a -> mid -> b` when a mid exists. This is the whole claim under
//! test — N descriptors sharing a canonical hub need N authored edges rather
//! than N(N-1) pairwise ones, and every edge the trie answers with that was
//! never written is the numerator of SER.
//!
//! CLASSES ARE FACTS ON THE EDGE, not a second conversion system. `exact`,
//! `lossless`, `checked`, `narrowing`, `view`, `consuming` ride on the edge and
//! compose by MEET: a path is only as strong as its weakest hop. The rule that
//! matters is `Class.derivable` — **silent** derivation stops at `lossless`.
//! A path through a narrowing or checked hop is found, reported, and REFUSED,
//! because an algebra that silently composes into a lossy conversion is worse
//! than no algebra at all. `refuse` is what makes this design safe to scale;
//! without it, adding a descriptor could quietly change an existing program's
//! answer.
const std = @import("std");
const ast = @import("ast.zig");

/// Conversion classes. Ordered by STRENGTH, strongest first — the enum order IS
/// the lattice, so `meet` is a max over the tag index and needs no table.
pub const Class = enum {
    /// The two descriptors denote the same value; the edge is an identity of
    /// representation. Composes freely.
    exact,
    /// Every source value has a distinct destination value. No information is
    /// lost, so composing two of these loses nothing either.
    lossless,
    /// A view onto the same storage — no copy, and the source must outlive it.
    /// Not `exact`: the lifetime fact is real and does not survive composition.
    view,
    /// May fail; the edge answers `dest | error`. Silent composition is refused
    /// because the failure position would have nowhere to land (B-14).
    checked,
    /// Some source values do not survive. Silent composition is refused.
    narrowing,
    /// Consumes its source. Silent composition is refused — a derived path
    /// would consume an intermediate the caller never named.
    consuming,

    pub fn parse(name: []const u8) ?Class {
        return std.meta.stringToEnum(Class, name);
    }

    pub fn text(self: Class) []const u8 {
        return @tagName(self);
    }

    /// The class of a path is its WEAKEST hop. Enum order is strength order, so
    /// the weaker of two classes is the one with the larger tag.
    pub fn meet(a: Class, b: Class) Class {
        return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
    }

    /// May an edge of this class be composed into a DERIVED edge that no one
    /// wrote? Only when nothing is lost and nothing can fail. Everything below
    /// `lossless` must be authored deliberately or routed by the caller.
    pub fn derivable(self: Class) bool {
        return self == .exact or self == .lossless;
    }
};

pub const Edge = struct {
    dest: []const u8,
    src: []const u8,
    /// The name of the callable that realizes this edge.
    conv: []const u8,
    class: Class,
    loc: ast.Loc,
};

/// A conversion the trie ANSWERED but nobody wrote. `class` is the meet of the
/// hops; `admitted` is false when a hop's class forbids silent composition, in
/// which case this value is a DIAGNOSTIC rather than a lowering.
pub const Path = struct {
    src: []const u8,
    dest: []const u8,
    mid: []const u8,
    first: Edge,
    second: Edge,
    class: Class,
    admitted: bool,

    /// The A5 witness, rendered. Every derived conversion carries one; a
    /// derivation without a witness is unshipped.
    pub fn witness(self: Path, buf: []u8) []const u8 {
        return std.fmt.bufPrint(
            buf,
            "derived {s} -> {s} via {s}: {s}({s}) then {s}({s}); class {s} meet {s} = {s}; {s}",
            .{
                self.src,          self.dest,                                                                          self.mid,
                self.first.conv,   self.first.src,                                                                     self.second.conv,
                self.second.src,   self.first.class.text(),                                                            self.second.class.text(),
                self.class.text(), if (self.admitted) "admitted" else "REFUSED: silent composition stops at lossless",
            },
        ) catch "derived edge (witness truncated)";
    }
};

/// One relation's edge set. Flat storage: this is a trie by ACCESS, not by
/// layout, and at the sizes a single compilation unit reaches a scan beats a
/// map — the enumeration order also stays declaration order, which is what
/// makes `for src, conv in to[str]` reproducible.
pub const Relation = struct {
    /// The relation's own name — `to`. Held so a diagnostic can spell the
    /// relation it is talking about rather than assuming.
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
    /// Returns the path even when its class REFUSES it, because the refusal is
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
                const class = Class.meet(first.class, second.class);
                const path = Path{
                    .src = src,
                    .dest = dest,
                    .mid = first.dest,
                    .first = first,
                    .second = second,
                    .class = class,
                    .admitted = first.class.derivable() and second.class.derivable(),
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
    /// `refused` counts pairs a route exists for whose class forbids silent
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

/// The declaration face, recognised off an ORDINARY ASSIGNMENT.
///
/// `to(dest)(src) = conv` and `to(dest)(src) = conv@class`. No new statement
/// kind, no new token, no new keyword: the shape already parsed, it simply had
/// no meaning and lowered to `tostring("u32") = digits`, which clang rejected
/// as "expression is not assignable". A2 NNS-FIRST is not a style preference
/// here — it is why this whole mechanism is a recogniser rather than a grammar
/// change.
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
pub fn declFromAssign(as: anytype, isRelation: *const fn ([]const u8) bool) ?Decl {
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
    if (!isRelation(rel)) return null;

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
