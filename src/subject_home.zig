//! SUBJECT-ONE, resolved by CONFORMANCE: `subject:relation(x)` and
//! `home.relation(subject, x)` are one edge, and WHICH home answers is decided
//! by what the subject IS, never by which list the relation's name appears in.
//!
//! WHY THIS EXISTS. The canon makes subject-first the PREFERRED face whenever
//! the subject is possessed — `r(subject, a)` and `subject:r(a)` are one edge
//! written from two ends. The operation-first face resolved through per-module
//! name lists; the subject-first face resolved through a hardcoded allow-list of
//! about a dozen method names in `methodCallResolved`. So `math.floor(x)`
//! compiled and `x:floor()` did not, and `string.split(s, ",")` compiled and
//! `s:split(",")` did not — the canonical spelling was the one that failed.
//!
//! ── WHAT CHANGED, AND WHY THE NAME LIST WAS THE WRONG MECHANISM ─────────────
//!
//! The first repair kept the shape of the thing it replaced: one flat table of
//! member names per home, consulted by NAME ALONE. `homeOf("floor")` answered
//! `.math` for every receiver in the language, so `"hi":floor()`, `42:split(",")`
//! and `"hi":push(1)` all type-checked clean — measured, not supposed. Dispatch
//! by name cannot refuse a subject that has no such relation, because it never
//! looks at the subject.
//!
//! It also could not resolve a name two homes claimed. `concat` was declared
//! CONTESTED and settled by a `receiver_is_str` boolean tiebreak — the name-list
//! mechanism reaching for exactly the type information that should have decided
//! it in the first place. The contest was fiction: there is no `string.concat`
//! relation anywhere in this compiler or its runtime (`string.concat("ab","cd")`
//! answers nil), only `lua_tbl_concat` behind `table.concat`. A name list
//! invented a conflict, then guessed its way out of it.
//!
//! Both faces are now decided by `conformanceOf(descriptor)`: the subject's
//! resolved descriptor answers which protocol it satisfies, and only that
//! protocol's relations are in reach. `concat` needs no tiebreak because a
//! `str` subject conforms to `text`, `text` provides no `concat`, and the
//! question never becomes a contest. Nothing was added to say so — `is_numeric`
//! already looks through a nominal descriptor to its representation, so a
//! `feet: f64` reaches `:floor()` without this file learning the word "feet".
//!
//! ONE ORIGIN, consulted by both the resolver and the lowerer, so the two faces
//! cannot drift apart again — which is the whole point of the law.

const std = @import("std");
const types = @import("types.zig");
const RT = types.ResolvedType;

/// What a subject's descriptor SATISFIES. Derived from the descriptor itself —
/// this function reads the type and nothing else, which is the whole difference
/// between this mechanism and the name list it replaces.
///
/// `unknown` is not a fourth protocol. It is the honest answer for a subject
/// whose descriptor sema never narrowed, and every caller has to decide for
/// itself what to do with an absent fact rather than being handed a guess.
pub const Conformance = enum {
    /// A string of bytes.
    text,
    /// A number. Includes a nominal descriptor over a numeric representation,
    /// because `is_numeric` looks through — that is a new conformant type
    /// reaching subject-first dispatch with no edit to this file.
    numeric,
    /// An ordered collection.
    sequence,
    /// A byte channel with a direction. THE PROTOCOL A SUPPLIED INSTANCE
    /// CARRIES — see `Supply`. `conformanceOf` NEVER answers this: `ResolvedType`
    /// has no stream descriptor, so no value's type can say it. It is derived
    /// instead from the world that SUPPLIED the instance, which is the one fact
    /// available when the descriptor is not.
    stream,
    /// No descriptor to ask.
    unknown,
};

/// The builtin homes. `os` and `testing` are WORLDS rather than protocols: no
/// value conforms to them, they are reached because the subject IS the world.
pub const Home = enum { string, math, table, io, testing, os, c };

/// A relation whose semantic contract is supplied by a protocol/world rather
/// than by an authored declaration in the current module. This is an identity,
/// not a spelling: sema resolves source text to this value once and every
/// downstream consumer receives only the graph entity created for it.
pub const Relation = enum { write };

/// The complete semantic contract for one protocol-supplied relation.
///
/// This is deliberately the sole row for path writing. The text roster,
/// semantic result, world/effect requirement, and graph relation identity all
/// project from it; none is reconstructed from `"write"` after resolution.
pub const Edge = struct {
    relation: Relation,
    name: []const u8,
    subject: Conformance,
    operand: RT,
    home: Home,
    result: RT,
    world: Home,
};

pub const edges = [_]Edge{
    .{
        .relation = .write,
        .name = "write",
        .subject = .text,
        .operand = .str,
        .home = .io,
        .result = .bool,
        .world = .io,
    },
};

/// Exact protocol relation selected at semantic ingress. `unknown` never
/// guesses: compatibility reach may still admit an untyped stream below, but
/// it cannot publish a path-write fact without the text descriptor witness.
pub fn edgeFor(protocol: Conformance, name: []const u8) ?*const Edge {
    if (protocol == .unknown) return null;
    for (&edges) |*candidate| {
        if (candidate.subject == protocol and std.mem.eql(u8, candidate.name, name)) return candidate;
    }
    return null;
}

pub fn edge(relation: Relation) *const Edge {
    for (&edges) |*candidate| {
        if (candidate.relation == relation) return candidate;
    }
    unreachable;
}

/// THE `c` WORLD'S ROSTER — the one place it is written down.
///
/// NAMED `c` BY RULING. `docs/foreign-world.md` §8.1 argued the world's identity
/// IS the library, which would make this `libc`; the ruling is `c`, and it is
/// the better answer for the reason §8.1 was reaching for. `libc` names an
/// artifact of one platform's packaging — the C standard library is `libc.so` on
/// Linux, `libSystem` on Darwin, and neither is the entity a program means. `c`
/// IS the independently meaningful entity `docs/spec/world.md` asks for: the C
/// ABI and its standard surface, which is what a caller is actually reaching
/// for. A world per shared object (`sqlite3`, `openssl`) still follows §8.1 —
/// those genuinely ARE libraries.
///
/// Deliberately SMALL and deliberately a ROSTER rather than "any symbol". A world
/// that forwards every name it is given is not a capability, it is a hole: the
/// point of `authority = .one(<world>)` is that a module which was not granted
/// the world cannot reach out, and that is worth nothing if the granted world
/// reaches everything. Growing this list is how the world grows, and each entry
/// is a decision.
///
/// Signature-checked NOWHERE YET, which is the honest limit of this first cut:
/// these are the i64-in/i64-out members, and a member whose C signature is not
/// that shape does not belong here until the roster carries signatures.
pub const c_members = [_][]const u8{ "abs", "labs" };

/// Is `name` a member of the `c` world? Asked by BOTH sema and lowering, so
/// there is one roster and not two lists that have to agree — which is the shape
/// that has already produced a wrong answer in this compiler (the formatter's
/// precedence table, idol `68d33bbe`).
pub fn isCMember(name: []const u8) bool {
    for (c_members) |m| {
        if (std.mem.eql(u8, m, name)) return true;
    }
    return false;
}

/// The conformance a descriptor carries.
///
/// NOT A TABLE. Every arm reads a structural fact already present in
/// `ResolvedType`; there is no name anywhere in this function, so a descriptor
/// this file has never heard of still gets the right answer.
pub fn conformanceOf(t: RT) Conformance {
    return switch (t) {
        .str => .text,
        .array, .table_type => .sequence,
        // A specialization conforms to whatever it specializes.
        .instantiated => |i| conformanceOf(i.base.*),
        // `is_numeric` sees through a nominal descriptor to its representation
        // (law.nominal: a PHYSICAL question about `feet` is a question about the
        // double behind it), so `feet:floor()` resolves without an entry here.
        else => if (t.is_numeric()) .numeric else .unknown,
    };
}

// ── THE CONFORMANCE A BINDING CARRIES ───────────────────────────────────────
//
// THE HOLE THIS CLOSES, measured with `idol check` against the shipped binary:
//
//     s: str = "text" ; s:write("x")   REFUSED     — the annotated case is right
//     s      = "text" ; s:write("x")   CLEAN       — and it is the same program
//     s      = "text" ; s:floor()      CLEAN
//     n      = 5      ; n:write("x")   CLEAN
//     "text":write("x")                REFUSED     — the literal is right too
//
// ANNOTATE IT AND IT IS REFUSED; WRITE IT DOWN BARE AND IT IS ADMITTED. Nothing
// about the subject changed between those two lines — only whether sema still
// had the descriptor when the subject was asked. An IMPLICIT LOCAL (assignment
// to an undeclared name) is bound `any` and the initializer's descriptor is
// discarded, so `conformanceOf` answers `unknown` and the `unknown` arm — the
// bridge that lets an unnarrowed subject reach every roster — admitted `write`
// on a string and `floor` on a string alike.
//
// c0 §41 already rules this the other way: AN IMPLICIT LOCAL TAKES THE CASE-SET
// OF THE VALUE THAT CREATED IT. The general form of that rule (the binding takes
// the value's DESCRIPTOR) is recorded as owed at the assignment site in
// `sema.zig` and is a representation change — a `str` local stops being a
// `lua_Value` in the emitted C — so it is not this ruling's to make.
//
// WHAT IS THIS RULING'S: the CONFORMANCE, which is not a representation and
// costs nothing to carry. sema already carries exactly this fact for exactly
// this reason, for exactly one protocol — `sequence_bindings`, "a name bound to
// a table CONSTRUCTOR is a sequence", recorded because a table constructor also
// types `any`. The mechanism was right and its scope was one protocol wide. The
// two functions below are that mechanism generalized to the whole lattice, kept
// HERE so the derivation has one origin and sema spells out no protocol rule.

/// The conformance a BINDING carries, derived from the value that created it.
///
/// `init_is_constructor` is the one fact a descriptor cannot supply today: a
/// table constructor types `any`, so `t = { … }` has no descriptor to read and
/// the AST shape is the only witness. It is passed as a BOOLEAN rather than
/// read here because this file does not import the AST and must not start.
///
/// DELETION CONDITION: delete `init_is_constructor` once a table constructor's
/// descriptor is `table_type`; delete the whole function once an implicit local
/// carries its initializer's descriptor (c0 §41's general rule), at which point
/// `conformanceOf(ot)` answers at the subject and nothing needs to be recorded.
pub fn conformanceOfBinding(init_type: RT, init_is_constructor: bool) Conformance {
    const from_descriptor = conformanceOf(init_type);
    if (from_descriptor != .unknown) return from_descriptor;
    if (init_is_constructor) return .sequence;
    return .unknown;
}

/// What a name carries after being bound AGAIN — and it only ever WIDENS.
///
/// `null` means the name carries no conformance fact, which is the honest
/// answer and NOT a third protocol: the subject falls back to `unknown` and
/// reaches every roster, exactly as it does today.
///
/// WIDENING IS THE WHOLE SAFETY ARGUMENT. A witness on a name is keyed by the
/// name, so it cannot see a branch merge, a loop back-edge or a shadowing inner
/// scope. Every one of those can make a recorded conformance STALE, and a stale
/// conformance that NARROWS would refuse a valid program — `f = "name"` early,
/// `f = io.open(path)` later, `f:close()` refused because the first binding is
/// what the name remembers. So two bindings that disagree retract to no fact at
/// all, and the only way this mechanism can be wrong is by admitting something
/// it could have refused. That direction is already today's behaviour.
///
/// `track_table_field` takes the same decision for the same reason ("on type
/// mismatch, widens to .any (conservative)").
pub fn mergedBindingConformance(prev: ?Conformance, next: Conformance) ?Conformance {
    if (next == .unknown) return null;
    const p = prev orelse return next;
    if (p == next) return p;
    return null;
}

// ── A WORLD DECLARES ITSELF ─────────────────────────────────────────────────
//
// WHAT WAS HERE BEFORE. `injectedWorlds()` returned the literal `&.{.os}`;
// `worldNamed` was a six-arm `if` chain of string comparisons; `homeProvides`
// was a six-arm switch, one hand-written expression per world; `homeName` was a
// third six-arm switch; the `os` roster and the `test` roster were two loose
// `const` arrays; the standing stream names were a fourth if-chain; and WHICH
// test-world admission lived in `sema.inTestWorld`, inferred from a source path
// in a file that did not own either launch role or world declarations. Seven
// places had to agree about six worlds, and nothing made them.
//
// A WORLD NOW CARRIES ITS OWN FACTS: its name, what it provides, whether it
// needs a launcher witness, and what reach confers. Every question below is
// ANSWERED FROM THAT DECLARATION, so a world added to the table is a world the
// resolver, the bare-reach rule, the injection rule and the diagnostics all
// already know about, with no edit anywhere else.
//
// WHAT THIS IS NOT. The table is still Zig. A user cannot write a world down in
// `.id` source, because there is no source form for declaring one — that is a
// RULING and it is routed, not invented here (§0 SOURCE-LAW FIREWALL). What
// changed is that a world's membership is now a property OF THE WORLD instead of
// a literal in whichever function happened to need it, which is the shape a
// declaration has to arrive into. The remaining hardcoded fact is named
// precisely: `Provision.roster` — and only two worlds still use it.

/// HOW A WORLD ENTERS THE ACTIVE LAUNCH CONTEXT.
pub const Injection = enum {
    /// The standard environment supplies this world without another witness.
    always,
    /// The launcher must supply an exact grant for this world. Source paths do
    /// not grant it; they may only help the launcher select a role.
    witnessed,
};

/// WHAT INHABITING a world confers. The two are separate questions and were
/// being answered by one list.
pub const Reach = enum {
    /// Member edges are reachable BARE — `env("HOME")`, `cwd()`, `arg(i)` — and
    /// the anchored `os.env("HOME")` is the DISAMBIGUATOR, reserved for a world
    /// where the same name is injected from elsewhere and resolution is
    /// genuinely contested. `os.env["HOME"]` is the retired `[` accessor;
    /// `os.getenv(...)` is not a lawful name at all — two words glued, a C
    /// legacy spelling, where LAW-16 wants one irreducible lowercase word.
    bare,
    /// The world's NAME resolves, and nothing else does: its relations are
    /// reached through the world subject (`string.len(s)`, `test:assert(c, m)`).
    ///
    /// ROUTED, NOT DECIDED: `test` is `anchored_only` here and the reason
    /// previously given for it — "a bare `equal(a, b)` would capture an ordinary
    /// user relation of that name in every test file" — is REFUTED by this
    /// file's own ruling (injection adds reach, it never takes a name) and by
    /// `gate/shadow.id`, which runs. The ruling that actually settles it is open:
    /// `docs/foreign-world.md` §7 proposes RETIRING the test world and making
    /// `assert` a language trap, which would delete the question rather than
    /// answer it. Flipping this one field is the whole change either way; it is
    /// not made unilaterally.
    anchored_only,
};

/// THE INSTANCES A WORLD SUPPLIES, and the protocol they carry.
///
/// CROSS-PROJECTION, stated as a declaration instead of as a roster. `io`
/// provides NO relation to itself: it supplies stream instances under standing
/// names, and `write`/`read`/`close` are relations on THE INSTANCE. The world
/// provides the instance; a different subject carries the relation. C0
/// `law.world.grant` states it for the sibling relation — "io:open(path) cannot
/// become canonical merely because io is reachable", failing on "world authority
/// arriving through ... namespace receiver" — so `stdout:write(x)` is canon and
/// `io:write(x)` is the denied shape with the relation's name changed.
///
/// THREE FACTS FALL OUT OF THIS ONE DECLARATION, all of which used to be written
/// down separately: that `io` provides nothing to itself (`homeProvides`), that
/// `stdout`/`stderr`/`stdin` are standing names (`suppliedInstance`), and that a
/// refusal can NAME the projection the author omitted (`exemplarStream`).
pub const Supply = struct {
    instances: []const Instance,
    /// What the instances conform to. The relations belong to THIS, not to the
    /// world — which is the whole of cross-projection.
    protocol: Conformance,
};

/// One standing instance, and the direction its data flows.
///
/// Direction is carried because a refusal that only says no teaches nothing:
/// `write(x)` has to come back as `stdout:write(x)` and `read()` as
/// `stdin:read()`, or the author is left guessing which of three standing
/// streams the compiler wanted. It used to be a two-arm `if` on the relation's
/// name in `exemplarStream`; it is a property of the instance.
pub const Instance = struct { name: []const u8, inbound: bool };

/// WHAT A WORLD PROVIDES — and it is not always a list. The three arms are the
/// three answers, and which arm a world uses is the honest measure of how much
/// of it is still hardcoded.
pub const Provision = union(enum) {
    /// WRITTEN DOWN, because nothing in the tree declares it. THE NAMED GAP, and
    /// it is now exactly two worlds wide (`os`, `test`). See the note on
    /// `os_members` for what would delete it.
    roster: []const []const u8,
    /// DERIVED. The world provides exactly the relations it REALIZES for some
    /// protocol — `realizedBy(roster, m) == home`. No list: adding a relation to
    /// a protocol's roster adds it to its realizing world's membership, and the
    /// two cannot disagree because there is only one of them.
    realized,
    /// SUPPLIED. The world provides NOTHING to itself; see `Supply`.
    supplies: Supply,
};

/// ONE WORLD, declaring itself.
pub const Declaration = struct {
    home: Home,
    /// The word that NAMES this world as a subject.
    name: []const u8,
    provides: Provision,
    injection: Injection,
    reach: Reach,
};

/// The standing streams `io` supplies. `stdout` precedes `stderr` so an
/// outbound refusal names `stdout`, which is the one an author almost always
/// meant.
const standing_streams = [_]Instance{
    .{ .name = "stdout", .inbound = false },
    .{ .name = "stderr", .inbound = false },
    .{ .name = "stdin", .inbound = true },
};

/// THE WORLDS. Every world question in this compiler is answered from here.
pub const declarations = [_]Declaration{
    // The standard environment. Injected everywhere, and its member edges are
    // the canonical bare faces: `env("HOME")`, `cwd()`, `clock()`, `arg(i)`.
    .{
        .home = .os,
        .name = "os",
        .provides = .{ .roster = &os_members },
        .injection = .always,
        .reach = .bare,
    },
    // Injected everywhere, and what its injection confers is the standing
    // stream INSTANCES — not one relation name. That is why bare `write("x")`
    // has nothing to resolve to while `stdout:write("x")` does, and it is a
    // consequence of the declaration rather than a rule written against `io`.
    .{
        .home = .io,
        .name = "io",
        .provides = .{ .supplies = .{ .instances = &standing_streams, .protocol = .stream } },
        .injection = .always,
        .reach = .bare,
    },
    // The protocol worlds. Their names resolve everywhere — `string.len(s)` is
    // the operation-first face of `s:len()` — and they confer no bare reach at
    // all: a bare `len(x)` is an ordinary name.
    .{ .home = .string, .name = "string", .provides = .realized, .injection = .always, .reach = .anchored_only },
    .{ .home = .math, .name = "math", .provides = .realized, .injection = .always, .reach = .anchored_only },
    .{ .home = .table, .name = "table", .provides = .realized, .injection = .always, .reach = .anchored_only },
    // THE FOREIGN WORLD. `c.abs(0 - 7)` is anchored access on a world value —
    // no directive, and `@cinclude`/`@comp.c.call`/`@c.export` are the retired
    // spellings it replaces.
    //
    // `anchored_only` IS THE CAPABILITY-RELEVANT HALF: the world's NAME
    // resolves and nothing else does, so a bare `abs(x)` stays whatever the
    // module itself declares and no C name is ever taken from a program that
    // did not ask. Injection adds reach; it never takes a name.
    //
    // `always` IS AN INTERIM AND IS NOT THE GRANTING STORY. Granting is the open
    // ruling in `docs/foreign-world.md` §8.4, and the answer taken is that the
    // BUILD ROOT grants authority (what a program may reach at all, enforceable
    // at link because the root decides what is linked) while INJECTION scopes
    // reach (where the granted world is nameable). `Injection` has no variant
    // for either yet, so this is `always` and capability is NOT enforced: today
    // any module can write `c.abs`. That is a smaller hole than it sounds —
    // `anchored_only` means nothing is reachable without writing `c.`
    // explicitly — but it is a hole, and it closes when granting lands rather
    // than by tightening this line.
    .{
        .home = .c,
        .name = "c",
        .provides = .{ .roster = &c_members },
        .injection = .always,
        .reach = .anchored_only,
    },
    // A TEST LAUNCH may grant this world. The source path never does: launch
    // structure is interpreted at the launcher boundary and arrives here as an
    // exact world grant.
    .{
        .home = .testing,
        .name = "test",
        .provides = .{ .roster = &testing_members },
        .injection = .witnessed,
        .reach = .anchored_only,
    },
};

/// The declaration for a home. Total by construction — the table is required to
/// hold every `Home`, and `the declaration table covers every world` proves it.
pub fn declarationOf(home: Home) *const Declaration {
    for (&declarations) |*d| {
        if (d.home == home) return d;
    }
    unreachable;
}

/// The worlds reached under exact launcher `grants`, taken from `decls`.
/// `always` worlds need no explicit grant; `witnessed` worlds do. The input is
/// semantic identity, never a file path or spelling detector.
pub fn inhabitedIn(decls: []const Declaration, grants: []const Home) WorldSet {
    var set: WorldSet = .{};
    for (decls) |d| {
        const in = switch (d.injection) {
            .always => true,
            .witnessed => for (grants) |grant| {
                if (grant == d.home) break true;
            } else false,
        };
        if (in) set.add(d.home);
    }
    return set;
}

/// A bounded set of worlds, returned by value. Sized to the declaration table,
/// so it cannot overflow and needs no allocator.
pub const WorldSet = struct {
    items: [declarations.len]Home = undefined,
    len: usize = 0,

    pub fn add(self: *WorldSet, h: Home) void {
        for (self.items[0..self.len]) |existing| {
            if (existing == h) return;
        }
        self.items[self.len] = h;
        self.len += 1;
    }

    pub fn slice(self: *const WorldSet) []const Home {
        return self.items[0..self.len];
    }

    pub fn holds(self: *const WorldSet, h: Home) bool {
        for (self.items[0..self.len]) |existing| {
            if (existing == h) return true;
        }
        return false;
    }
};

/// Whether `world` reaches the supplied launch context.
pub fn worldReached(worlds: []const Home, world: Home) bool {
    for (worlds) |reached| if (reached == world) return true;
    return false;
}

/// The worlds reached after applying exact launcher grants.
pub fn injectedWorldsFor(grants: []const Home) WorldSet {
    return inhabitedIn(&declarations, grants);
}

/// The worlds supplied without explicit launcher grants — every `always` world.
///
/// MEMBERSHIP, NOT A SECOND LIST. `arg` was admitted by hand in
/// `is_builtin_global` when the argument ruling landed, and the other five
/// members of the same world were not, so `arg(i)` resolved bare and `env(k)`
/// reported "'env' is neither a descriptor nor a callable". Adding the missing
/// five by hand would have been the name-list mechanism in a second location.
/// Bare reach falls out of world membership instead: a world that is not
/// injected confers nothing, and a member edge added to an injected world is
/// bare-reachable with no edit anywhere.
pub fn injectedWorlds() WorldSet {
    return injectedWorldsFor(&.{});
}

/// Which injected worlds provide `name` as a member edge. THE BARE-REACH
/// QUESTION, and it is answered by COUNT rather than by first match.
///
/// `law.inject.algebra`: "ambiguous injection fails rather than picking by
/// declaration import or path priority", and `law.ambient.one`: an ambient fact
/// requires EXACTLY ONE valid contextual value. A loop that returns the first
/// provider is an ordering accident wearing a resolution's clothes — it would
/// answer, silently, and the answer would change if the list were reordered. So
/// the ambiguity is a REPRESENTED OUTCOME here, not an absent case.
pub const BareReach = union(enum) {
    /// No injected world provides it — the name is an ordinary one.
    none,
    /// Exactly one does. The only case that confers reach.
    one: Home,
    /// Two or more do. §42: diagnose, never pick.
    ambiguous: struct { first: Home, second: Home },
};

/// The bare reach `name` has in `worlds`. Parameterized on the world list so
/// the ambiguity arm is reachable from a test — the shipped list is a single
/// world today, which makes the arm unreachable in production and is exactly
/// why it would otherwise never be exercised.
/// The bare reach `name` has in `worlds`, resolved against `decls`.
///
/// Parameterized on the DECLARATIONS as well as the world list, because the two
/// are one fact: a `Home` is only a tag, and everything that decides reach —
/// membership, injection, whether reach is bare at all — lives in the row. A
/// version that took the tags and read the shipped rows would answer from the
/// shipped table no matter what it was handed, which is a test that proves the
/// shipped table twice and the mechanism not at all.
pub fn bareReachAmong(
    decls: []const Declaration,
    worlds: []const Home,
    name: []const u8,
) BareReach {
    var found: ?Home = null;
    for (worlds) |w| {
        for (decls) |d| {
            if (d.home != w) continue;
            // INJECTION AND REACH ARE TWO QUESTIONS. `string`, `math`, `table`
            // and `test` are injected — their names resolve — and confer no bare
            // reach at all, so `len(x)` and `assert(c, m)` are ordinary names. A
            // world that only anchors is skipped here rather than being kept out
            // of the injected set, because it IS injected; what it confers is
            // the fact being asked about.
            if (d.reach != .bare) continue;
            if (!provisionHolds(d, name)) continue;
            if (found) |first| return .{ .ambiguous = .{ .first = first, .second = w } };
            found = w;
        }
    }
    if (found) |w| return .{ .one = w };
    return .none;
}

pub fn bareReachIn(worlds: []const Home, name: []const u8) BareReach {
    return bareReachAmong(&declarations, worlds, name);
}

/// The bare reach `name` has in an exact launch-world set.
pub fn bareReachFor(worlds: []const Home, name: []const u8) BareReach {
    return bareReachIn(worlds, name);
}

/// The bare reach `name` has in the STANDARD environment.
pub fn bareReach(name: []const u8) BareReach {
    const worlds = injectedWorlds();
    return bareReachFor(worlds.slice(), name);
}

/// The injected world that UNIQUELY provides `name`, or null. Ambiguity answers
/// null here too — a caller that only wants "may this name be reached bare"
/// must not be handed one of two answers — and the caller that reports the
/// ambiguity asks `bareReach` for the pair.
pub fn injectedWorldProviding(name: []const u8) ?Home {
    const worlds = injectedWorlds();
    return injectedWorldProvidingFor(worlds.slice(), name);
}

/// The reached world that uniquely provides `name` in this launch context.
pub fn injectedWorldProvidingFor(worlds: []const Home, name: []const u8) ?Home {
    return switch (bareReachFor(worlds, name)) {
        .one => |w| w,
        .none, .ambiguous => null,
    };
}

pub fn injectedWorldProvidingIn(worlds: []const Home, name: []const u8) ?Home {
    return injectedWorldProvidingAmong(&declarations, worlds, name);
}

pub fn injectedWorldProvidingAmong(
    decls: []const Declaration,
    worlds: []const Home,
    name: []const u8,
) ?Home {
    return switch (bareReachAmong(decls, worlds, name)) {
        .one => |w| w,
        .none, .ambiguous => null,
    };
}

/// The world a builtin subject NAMES, when the subject is a world value rather
/// than an instance. `os:arg(i)` reaches the `os` world because the subject is
/// `os`, not because "arg" appears in a table keyed by home.
///
/// The caller still owns admission: naming a world does not grant it.
pub fn worldNamed(ident: []const u8) ?Home {
    for (&declarations) |*d| {
        if (std.mem.eql(u8, d.name, ident)) return d.home;
    }
    return null;
}

/// The world a builtin subject names AND that reaches this launch context.
pub fn worldNamedFor(worlds: []const Home, ident: []const u8) ?Home {
    const world = worldNamed(ident) orelse return null;
    return if (worldReached(worlds, world)) world else null;
}

// ── THE REMAINDER: what conformance still cannot derive ─────────────────────
//
// Everything below this line is a ROSTER — which relations a protocol provides
// — and every one of them is here for the same reason, stated once:
//
//   THE MISSING FACT: no builtin protocol declares its relations anywhere sema
//   can read. The string roster's ground truth is the `lua_str_*` if-else chain
//   in `codegen.zig` (`try_emit_guarded_string_face`, and the `.field` chains
//   near lines 16863 and 22149); the math roster's is libm plus the
//   `lua_math_*` chain near 22331; the table roster's is the `lua_tbl_*` chain
//   near 22168. Those are C EMISSION sites: `codegen.zig` imports sema, so sema
//   cannot import them back, and none of them is a declaration a `.id` file
//   could add to. Until a protocol states its own relations as ordinary graph
//   facts, WHICH relations a conformance provides has to be written down.
//
// What is NO LONGER here is the part conformance did answer: which roster is
// consulted at all. That is now the subject's, and a roster is unreachable from
// a subject that does not conform.

/// One relation a protocol provides, and the home that REALIZES it.
///
/// Two axes, and they are not the same axis. `home` is where the
/// operation-first face lives, so `subject:r(a)` and `home.r(subject, a)` land
/// on one application; the protocol it is listed under is what the SUBJECT must
/// conform to. The flat name list collapsed the two and got `char` wrong for
/// it: `string.char(65)` lives in the `string` module but its subject is a
/// NUMBER, so `0:char()` and `255:char()` — 111 call sites across 15 files in
/// `lib/` — are numeric subjects reaching a string-realized relation. Keyed by
/// name alone that is invisible; keyed by the subject it is the first thing you
/// see.
const Provided = struct {
    name: []const u8,
    home: Home,
    /// WHICH WAY THE DATA GOES, for a protocol whose instances a world SUPPLIES.
    /// Read only through `exemplarStream`, so a refusal can name the standing
    /// instance the author omitted instead of listing all three. Meaningless —
    /// and left at its default — for a protocol a value CONFORMS to, because
    /// there the subject was written down and nothing has to be guessed.
    inbound: bool = false,
};

fn str_(name: []const u8) Provided {
    return .{ .name = name, .home = .string };
}

/// What a `text` subject provides.
///
/// `concat` is deliberately absent: `string.concat` does not exist in this
/// compiler or its runtime (`string.concat("ab","cd")` answers nil), and
/// listing it here is what made `concat` look contested.
///
/// `char` is absent for the opposite reason — it is real, but its subject is
/// numeric, so it is listed under `numeric_relations`.
///
/// `read` is here and is realized by the `io` home, because A STRING IS A PATH:
/// `law.world.grant`'s own canon is `file = path:open()` and `path:read` "retains
/// the required world fact even when elided in source". `"data.txt":read()`
/// lowers today (`dnir_lower.lowerSubjectRead`, guarded by `exprIsStr`), so it
/// is a real edge and not an aspiration. Path `write` is supplied by the
/// semantic `edges` authority above rather than duplicated in this legacy
/// roster; `close` remains stream-only because a path is not an open handle.
const text_relations = [_]Provided{
    str_("sub"),    str_("match"), str_("byte"),                     str_("len"),
    str_("rep"),    str_("lower"), str_("upper"),                    str_("reverse"),
    str_("format"), str_("gsub"),  str_("gmatch"),                   str_("split"),
    str_("trim"),   str_("has"),   str_("tail"),                     str_("starts"),
    str_("ends"),   str_("find"),  .{ .name = "read", .home = .io },
};

fn math_(name: []const u8) Provided {
    return .{ .name = name, .home = .math };
}

/// What a `numeric` subject provides.
const numeric_relations = [_]Provided{
    math_("sqrt"), math_("sin"),  math_("cos"),   math_("tan"),
    math_("exp"),  math_("log"),  math_("ceil"),  math_("max"),
    math_("min"),  math_("abs"),  math_("floor"), math_("fmod"),
    math_("pow"),  math_("sign"), math_("round"), math_("random"),
    math_("sinh"), math_("cosh"), math_("tanh"),  math_("asin"),
    math_("acos"), math_("atan"), math_("atan2"),
    // A CODEPOINT is the subject; the relation is realized by the string home.
    // `65:char()` is the canonical face and `string.char(65)` the other end of
    // the same edge.
    str_("char"),
};

fn tbl_(name: []const u8) Provided {
    return .{ .name = name, .home = .table };
}

/// What a `sequence` subject provides. `concat` is here and only here, so a
/// `str` subject cannot reach it and a sequence subject reaches it with no
/// tiebreak.
const sequence_relations = [_]Provided{
    tbl_("insert"), tbl_("remove"), tbl_("sort"),   tbl_("unpack"),
    tbl_("push"),   tbl_("pop"),    tbl_("concat"),
};

/// A STREAM's relations.
///
/// THE ADDITIONAL MISSING FACT, specific to this roster: `ResolvedType` has no
/// stream descriptor. `io.open(...)` answers `any`, a file handle carries no
/// descriptor, and `conformanceOf` therefore answers `unknown` for every
/// stream in the language. So these cannot be gated on what the subject IS —
/// they are reachable from an unnarrowed subject and nowhere else.
///
/// THE SUBJECT IS THE STREAM, NEVER THE WORLD. `io:write(x)` is not a
/// world-specific call: `io` PROJECTS to a writable-conformant instance, and
/// `:write` dispatches on THAT instance. C0 `law.world.grant` states the shape
/// directly for the sibling relation —
///
///     canon = { "file = path:open()", "open subject path world io result file" }
///     deny  = { "io:open(path)" }
///     "io:open(path) cannot become canonical merely because io is reachable"
///     fails = "world authority arriving through ... namespace receiver"
///
/// — so `stdout:write(x)` is canon and `io:write(x)` is the denied shape with
/// the relation's name changed. `homeProvides(.io, …)` therefore answers NO for
/// every name here: the `io` world supplies stream INSTANCES, and the relations
/// below belong to the instances, not to the world. Sema refuses the world-as-
/// receiver spelling by name (`checkStreamRelationFace`) so the refusal carries
/// the canonical form instead of falling out as a missing fact at emit.
///
/// `write`, `read` and `close` were missing from a roster titled "a STREAM's
/// relations" and were reached instead through an `ot == .str or .any` arity
/// list in sema — which is why `"text":write(x)` type-checked and why a local
/// named `stdout` could be written to. They are stream relations; they are
/// listed as stream relations.
///
/// `open` is deliberately ABSENT even though `law.world.grant` denies
/// `io:open(path)` by name: its canon is `path:open()`, and `path:open` has no
/// lowering anywhere in this tree, so listing it here would refuse the only
/// spelling that works. Recorded as owed, not enforced.
///
/// DELETION CONDITION: delete this roster once a stream carries a descriptor,
/// at which point `conformanceOf` grows a `stream` arm and these become the
/// `stream` protocol's relations like any other.
///
/// WHY THAT CONDITION IS THE ONLY ONE, and why the obvious shortcut is wrong.
/// The tempting move is to stop `unknown` reaching this roster and be done: it
/// would refuse `s = "text" ; s:write(x)` in one line. It would also refuse the
/// corpus. MEASURED across every `.id` in this tree — 212 sites reach a stream
/// relation on a subject that is NOT one of the three standing names, and the
/// subject is unnarrowable at 51 of them in `lib/` alone plus 37 field
/// subjects:
///
///     lib/io.id        `write: any = (file: any, arg: any)` / `file:write(arg)`
///                      — seven relations, every one on an `any` PARAMETER
///     lib/bufio.id:140 `w.fh:write(w.buf)`      — a table FIELD
///     lib/fs.id:33     `f = io.open(path,"w")`  — a binding, `io.open` is `any`
///
/// A parameter and a table field have no binding to carry a witness and no
/// descriptor to read, so the only way to narrow them is to WRITE THE
/// DESCRIPTOR DOWN — `write: any = (file: stream, arg: any)`. That is the same
/// condition stated above, seen from the corpus instead of from the compiler:
/// the roster leaves `unknown`'s reach when `stream` is a descriptor an author
/// can spell, not before. Refusing first and migrating after would refuse
/// working programs in the interval, and this gate exists to stop exactly that.
/// `line` was MISSING and it lowers: `dnir_lower` binds `stdin.line` to
/// `idol_io_read_line`, `sema.methodCallResolved` admitted `stdin:line()` by a
/// hardcoded receiver-name comparison, and `tools/mcp/native.id` calls it twice.
/// A roster that omits a relation the backend realizes is the same defect as one
/// that invents a relation the backend does not — the roster and the realization
/// disagree, and only one of them runs.
const stream_relations = [_]Provided{
    .{ .name = "write", .home = .io },
    .{ .name = "read", .home = .io, .inbound = true },
    .{ .name = "line", .home = .io, .inbound = true },
    .{ .name = "lines", .home = .io, .inbound = true },
    .{ .name = "close", .home = .io },
    .{ .name = "flush", .home = .io },
    .{ .name = "seek", .home = .io },
    .{ .name = "setvbuf", .home = .io },
};

/// Whether `name` is a relation ON A STREAM INSTANCE rather than a member edge
/// of the `io` WORLD. THE SUBJECT QUESTION, asked by sema at both application
/// faces so the world-as-receiver spelling is refused in one place.
pub fn streamRelation(name: []const u8) bool {
    return protocolProvides(.stream, name) != null;
}

/// The roster a protocol's relations live in. ONE PLACE that maps a protocol to
/// its relations, so `homeForConformance`, `streamRelation` and the world's own
/// `realized` membership all read the same answer.
fn protocolRoster(c: Conformance) []const Provided {
    return switch (c) {
        .text => &text_relations,
        .numeric => &numeric_relations,
        .sequence => &sequence_relations,
        .stream => &stream_relations,
        .unknown => &.{},
    };
}

/// The home that realizes `method` for `protocol`, or null.
fn protocolProvides(protocol: Conformance, method: []const u8) ?Home {
    if (edgeFor(protocol, method)) |provided| return provided.home;
    return realizedBy(protocolRoster(protocol), method);
}

/// The world that SUPPLIES an instance under the standing name `ident`, and the
/// protocol that instance carries.
///
/// CROSS-PROJECTION, ANSWERED FROM THE DECLARATION. `stdout` is a name no file
/// declares and no protocol provides: it is reachable because the injected `io`
/// world supplies it. That fact used to be four string comparisons in
/// `streamNamed` — WHICH HAD ZERO CONSUMERS, measured — while sema, dnir_lower,
/// native_bootstrap, codegen and semantic_graph each compared the three names
/// themselves, twelve sites across five files.
///
/// Membership is the only fact this file owns; ADMISSION is sema's, exactly as
/// for `worldNamed` — a lexical binding spelled `stdout` is an ordinary value and
/// this file has no way to know that. AN INJECTED WORLD ADDS REACH, IT NEVER
/// TAKES A NAME.
pub const Supplied = struct { world: Home, protocol: Conformance, inbound: bool };

pub fn suppliedInstanceIn(
    decls: []const Declaration,
    worlds: []const Home,
    ident: []const u8,
) ?Supplied {
    for (worlds) |w| {
        for (decls) |d| {
            if (d.home != w or d.reach != .bare) continue;
            switch (d.provides) {
                .supplies => |s| for (s.instances) |inst| {
                    if (std.mem.eql(u8, inst.name, ident))
                        return .{ .world = w, .protocol = s.protocol, .inbound = inst.inbound };
                },
                .roster, .realized => {},
            }
        }
    }
    return null;
}

pub fn suppliedInstanceFor(worlds: []const Home, ident: []const u8) ?Supplied {
    return suppliedInstanceIn(&declarations, worlds, ident);
}

pub fn suppliedInstance(ident: []const u8) ?Supplied {
    const worlds = injectedWorlds();
    return suppliedInstanceFor(worlds.slice(), ident);
}

/// Whether `ident` is a standing stream the `io` world supplies.
pub fn streamNamed(ident: []const u8) bool {
    const s = suppliedInstance(ident) orelse return false;
    return s.protocol == .stream;
}

/// The standing stream a refusal NAMES when the author gave it none.
///
/// A refusal that only says no teaches nothing; `io:write(x)` has to come back
/// as `stdout:write(x)` or the author is left guessing which of three standing
/// streams the compiler wanted. Direction is the only fact needed to choose, and
/// BOTH ENDS OF IT ARE NOW DECLARED: the relation says which way its data goes
/// (`Provided.inbound`), the instance says which way it faces (`Instance.inbound`),
/// and this matches them. It used to be a two-arm `if` naming `read` and `lines`
/// literally, which is why `line` — a relation that lowers — would have been
/// answered `stdout`.
pub fn exemplarStream(relation: []const u8) []const u8 {
    const want_inbound = for (&stream_relations) |p| {
        if (std.mem.eql(u8, p.name, relation)) break p.inbound;
    } else false;
    const d = declarationOf(.io);
    switch (d.provides) {
        .supplies => |s| for (s.instances) |inst| {
            if (inst.inbound == want_inbound) return inst.name;
        },
        .roster, .realized => {},
    }
    return "stdout";
}

/// The `os` WORLD's projections, reached subject-first as `os:arg(i)` and bare
/// as `arg(i)` because `os` is injected with `Reach.bare`.
///
/// ── THE LAST HARDCODED ROSTER, AND WHAT WOULD DELETE IT ────────────────────
///
/// This is one of exactly TWO `Provision.roster` arms left; `string`, `math`
/// and `table` derive their membership from the protocol rosters and `io`
/// derives its (empty) membership from supplying instead. So the honest
/// statement of what a world can still NOT declare about itself is this array
/// and `testing_members`.
///
/// WHAT IS MISSING is not a mechanism — the declaration reads a slice, and a
/// slice built from graph facts would drop in unchanged. It is a SOURCE FORM:
/// there is no spelling in `.id` for "this is a world and these are its member
/// edges", and inventing one is a ruling, not an implementation detail (§0
/// SOURCE-LAW FIREWALL). The shape the graph would need is stated in
/// `docs/foreign-world.md` §8.2 — a `module` node for the world, `EdgeKind
/// .member` to each relation — and it adds no node kind and no edge kind.
///
/// TWO SECOND-ORDER GAPS, measured, that the roster form is hiding:
///
///   1. THE OPERATION-FIRST FACE DOES NOT CONSULT IT. `os.bogus(1)` type-checks
///      clean while `os:bogus(1)` is refused, so this roster governs one of the
///      two faces of one edge. Closing it needs the roster to be COMPLETE, and
///      it measurably is not: the sibling corpus calls 14 distinct `os.*`
///      relations against these 7 — `getenv` 61 times, `execute` 22, `remove`
///      19, `date` 9, `tmpname` 5 — plus `io.open` 54 and `io.popen` 47 against
///      an `io` world that provides nothing by construction. Refusing the
///      unlisted ones would refuse the corpus, so the completeness question has
///      to be settled before the face can be.
///   2. `getenv` IS ABSENT ON PURPOSE — two words glued is not a lawful name,
///      LAW-16 admits one irreducible lowercase word — and `os.getenv(...)`
///      still compiles clean at 61 sites in 16 files, including four `gate/`
///      files and the LSP and MCP tools. `examples/compile_fail/host_getenv.id`
///      exists and does not enforce. That is a corpus migration, not a compiler
///      change, and it blocks (1).
///
/// `args` is the legacy plural — an identity is singular — kept only so existing
/// source keeps working.
///
/// ── DERIVED, NOT WRITTEN ────────────────────────────────────────────────────
///
/// This used to be a hand-written array of seven names beside `os_dot_members`'
/// fifteen rows, and the two had to agree about which of the fifteen were also
/// member edges of the world. They were TWO AUTHORITIES on one fact, which is
/// the shape that has already produced a wrong answer in this compiler twice
/// (the formatter's precedence table, idol `68d33bbe`; the definer/caller symbol
/// split, `patches/definer-side-symbol-law`). `Provision.roster` wants names and
/// the roster carries rows, so the names are TAKEN FROM THE ROWS: a member edge
/// is bare-reachable exactly when its row says `.bare`, and the two cannot
/// disagree because there is only one of them.
fn osBareCount() usize {
    var n: usize = 0;
    for (os_dot_members) |m| {
        if (m.bare) n += 1;
    }
    return n;
}

const os_members: [osBareCount()][]const u8 = blk: {
    var out: [osBareCount()][]const u8 = undefined;
    var n: usize = 0;
    for (os_dot_members) |m| {
        if (!m.bare) continue;
        out[n] = m.name;
        n += 1;
    }
    break :blk out;
};

/// ── THE DOT FACE, AND WHAT DECIDED ITS ROSTER ──────────────────────────────
///
/// `os_members` is the SUBJECT-FIRST roster: what `os:relation(x)` reaches. The
/// operation-first face `os.relation(x)` consulted no roster at all —
/// `os.bogus(1)` type-checked clean and, on the retired C bridge, compiled clean
/// and aborted at RUNTIME with `unlowered native call`. One face of one edge
/// governed; the other wide open.
///
/// Closing it needs a roster, and the roster question is the one this file
/// already states for `stream_relations`:
///
///     "A roster that omits a relation the backend realizes is the same defect
///      as one that invents a relation the backend does not — the roster and
///      the realization disagree, and only one of them runs."
///
/// Direct is canonical. The explicit graph-observed DNIR to C99 realizer is an
/// orthogonal physical output and does not define this world roster. The
/// measurement that decides the current direct realization is therefore one
/// column. Measured per name, `--backend=direct`, every face, from the
/// repo root (idol 48cfd928):
///
///     env(k)  env(k)=v  env:remove(k)  os.env(k)     LOWERS
///     exit(n)  os.exit(n)                            LOWERS
///     arg(i)  os.arg(i)  os.args[i]                  LOWERS
///     os.cwd                                         LOWERS
///     ─────────────────────────────────────────────────────────
///     clock()  os.clock()                            DNB011
///     time()   os.time()                             DNB011
///     cwd()                    (bare face only)      DNB011
///     ─────────────────────────────────────────────────────────
///     getenv execute remove rename difftime          DNB011
///     date tmpname setenv read_file write_file       DNB011
///     pcall(os.getenv, k)                            DNB001
///     bogus  — and every other name                  DNB011
///
/// THE ANSWER THE MEASUREMENT GAVE, and it is not the one the question assumed.
/// NOT ONE off-roster `os.*` name lowers on the canonical backend. Not one. The
/// roster therefore does not need COMPLETING — there is nothing realized outside
/// it to complete it with — and the corpus does not need MIGRATING onto names
/// that would be admitted, because there are none. Every off-roster site in the
/// tree is a site the only backend cannot build.
///
/// Under the retired C bridge four of them (`execute`, `remove`, `rename`,
/// `difftime`) lowered to real libc and answered correctly, and that is what
/// made this look like a trade. It is not one any more. They are recorded here
/// as refused with the rest.
///
/// AND THE ROSTER IS WRONG IN THE OTHER DIRECTION TOO, which is the finding
/// worth more than the closure. `clock` and `time` are ON the roster, are
/// reachable through both faces, and lower NOWHERE — 210 live corpus sites
/// (`os.clock` 182, `os.time` 28) that the only backend cannot build. That is a
/// LOWERING gap, not a naming gap: there is nothing wrong with the words and no
/// repair to point an author at, so refusing them would be a wall. They are
/// admitted, marked `.unrealized`, and COUNTED, so the debt is visible and
/// cannot grow quietly.
pub const Realization = enum {
    /// Lowers on the direct backend — the only backend. Measured, end to end.
    direct,
    /// ON THE ROSTER AND UNREALIZED. Reachable through both faces, lowered by
    /// nothing: `os.clock()` and `os.time()` answer DNB011 on the direct
    /// backend, and so do their bare faces.
    ///
    /// NOT REFUSED, and the reason is the same standard this file applies to
    /// `open` in `stream_relations` — "Recorded as owed, not enforced." A
    /// refusal has to name a repair; there is no other spelling of "what time is
    /// it", so a refusal here could only say "stop". The word is fine. The
    /// lowering is missing.
    ///
    /// DELETION CONDITION: delete the tier when the direct backend lowers them.
    /// It is a `dnir_lower`/`native_backend` change and this lane does not own
    /// those files, so it is reported rather than attempted.
    unrealized,
    /// RETIRED BY NAME. Two words glued is not a lawful name (LAW-16 admits one
    /// irreducible lowercase word), AND the lawful spelling lowers on the only
    /// backend — measured, `env(k)` answers nil for an unset name, `""` for one
    /// set and empty, `env(k) = v` writes and `env:remove(k)` unsets, all four
    /// on `--backend=direct`.
    ///
    /// REFUSED IN EVERY FACE, including as a value. Under the C bridge
    /// `pcall(os.getenv, k)` compiled and answered correctly, which was the one
    /// argument for admitting the value face as debt; on the direct backend it
    /// is DNB001, so there is nothing left to preserve and the retirement is
    /// total.
    retired,
};

/// WHAT APPLYING A MEMBER EDGE *IS*. The three faces are three different
/// applications, and collapsing them is how `exit(1)` would become an index.
///
/// This was a THIRD roster, in `table_apply.zig`, with its own `Member` struct
/// and its own seven rows — a private copy of the world's membership living in
/// the pass that rewrites it. It is a property OF THE EDGE, so the edge carries
/// it, and the pass asks.
pub const Face = enum {
    /// Applying it is ACCESS on the world's table — `arg(i)`, `env(k)`.
    projection,
    /// Applying it is a CALL — `exit(n)`, `clock()`.
    relation,
    /// It is not applied at all: the edge IS the value, and `cwd()` is that
    /// value applied to nothing. `os.cwd` is the node that realizes it.
    value,
};

pub const OsMember = struct {
    name: []const u8,
    how: Realization,
    /// What to write instead. Non-empty only for `.retired`, because that is
    /// the only tier where a repair exists to name.
    repair: []const u8 = "",
    /// WHAT APPLYING IT IS — see `Face`.
    face: Face = .relation,
    /// THE DECLARED RESULT TYPE, AND THE WHOLE POINT OF THIS ROSTER CARRYING
    /// TYPES AT ALL.
    ///
    /// `dnir_lower` has always known `arg(i)` produces text — it emits
    /// `idol_os_arg` with `.ty = .str` — and the TYPE side knew nothing, so
    /// `codegen.expr_type` answered `any` for the same node. MEASURED before
    /// this field existed, and the two forms are the same edge:
    ///
    ///     p = arg(1) ; p:len()     ANSWERS 5
    ///     arg(1):len()             REFUSED  DNB001 method-unresolved:len
    ///
    /// The first works only because `string_method_result_type` admits a
    /// receiver that is a bare `.name` whatever its type — an accident, not a
    /// fact. The second is the same relation on the same subject and it had no
    /// descriptor to dispatch on. So the result type is declared HERE, once,
    /// and BOTH sides read it: `codegen.expr_type` for the receiver's
    /// descriptor and `dnir_lower.exprIsStr`/`.ty` for the realization.
    ///
    /// `.any` means NOT DECLARED, which is the honest answer for a member whose
    /// result nothing in this compiler knows — and every consumer treats it as
    /// an absent fact rather than as the `any` descriptor, exactly as
    /// `Conformance.unknown` is treated above.
    result: RT = .any,
    /// The node every face of this edge converges on, when it is not the
    /// member's own name.
    ///
    /// `arg` converges on the PLURAL `os.args`, and that is DEBT, not the
    /// target: `args` is a plural name and LAW-16 admits one irreducible
    /// lowercase word, so `arg` is the lawful edge. It is written down here
    /// rather than in the pass because this is the one place the debt can be
    /// seen beside the thing it is debt against.
    ///
    /// DELETION CONDITION: delete the field when `os.arg` is the node that
    /// resolves end to end and `args` is a retired spelling like `getenv`.
    target: []const u8 = "",
    /// Whether the edge is BARE-REACHABLE — a member of the world in the sense
    /// `Provision.roster` means. `os_members` is derived from this flag.
    bare: bool = false,
};

/// The node a member edge's faces converge on. `target` when it has one, the
/// member's own name otherwise.
pub fn osTarget(m: OsMember) []const u8 {
    return if (m.target.len == 0) m.name else m.target;
}

/// THE OPERATION-FIRST ROSTER. Every `os.NAME` in the language is one of these
/// or it is refused.
///
/// `gate/roster.sh` pins this table in BOTH directions: a name leaving is red,
/// and a NEW name being silently admitted is red.
pub const os_dot_members = [_]OsMember{
    // LOWERS ON THE DIRECT BACKEND. Measured end to end, statement position,
    // from the repo root: each compiles, runs, and answers correctly.
    .{ .name = "arg", .how = .direct, .face = .projection, .result = .str, .target = "args", .bare = true },
    .{ .name = "args", .how = .direct, .face = .projection, .result = .str, .target = "args", .bare = true },
    .{ .name = "env", .how = .direct, .face = .projection, .result = .str, .bare = true },
    // A VALUE, NOT A RELATION. `os.cwd` is the working directory; `cwd()` is
    // that value applied to nothing, and both converge on the one node
    // `dnir_lower.lowerField` realizes. Written as `.relation` it was a call
    // with no lowering — DNB011 through both faces, measured.
    .{ .name = "cwd", .how = .direct, .face = .value, .result = .str, .bare = true },
    .{ .name = "exit", .how = .direct, .face = .relation, .result = .void, .bare = true },
    // `os.execute("printf EXEC")` emits `EXEC` on `--backend=direct`. It was
    // DNB011 earlier in this session and a lowering landed under this lane;
    // the roster is derived from the measurement, so it moved with it.
    .{ .name = "execute", .how = .direct, .result = .bool },
    // CLAIMED BY THE WORLD, LOWERED BY NOTHING. Counted debt; see `.unrealized`.
    // Refusing these would refuse the corpus while naming no repair, which is a
    // wall rather than a ruling — and it took down the compile-fail harness once
    // already, which is how this tier came to be written down.
    //
    // THE RESULT TYPE IS DECLARED ANYWAY, and it is not decoration: it is the
    // fact a lowering would have to produce, stated before the lowering exists
    // so the lowering cannot land disagreeing with it. Nothing observes it
    // today because nothing gets past the refusal.
    .{ .name = "clock", .how = .unrealized, .result = .f64, .bare = true },
    .{ .name = "time", .how = .unrealized, .result = .f64, .bare = true },
    .{ .name = "remove", .how = .unrealized, .result = .bool },
    .{ .name = "rename", .how = .unrealized, .result = .bool },
    // `date` and the two retired names are `.any` — NOT DECLARED. Nothing in
    // this compiler knows what they answer, and inventing a type here would be
    // scenery with a consumer, which is worse than scenery.
    .{ .name = "date", .how = .unrealized },
    .{ .name = "tmpname", .how = .unrealized, .result = .str },
    .{ .name = "difftime", .how = .unrealized, .result = .f64 },
    // Retired, with the repair the refusal quotes back.
    .{ .name = "getenv", .how = .retired, .repair = "env(k)" },
    .{ .name = "setenv", .how = .retired, .repair = "env(k) = v" },
};

/// The `os` world's member edge for the OPERATION-FIRST face, or null when the
/// world has no such member at all — the `os.bogus(1)` answer.
pub fn osDotMember(name: []const u8) ?OsMember {
    for (&os_dot_members) |m| {
        if (std.mem.eql(u8, m.name, name)) return m;
    }
    return null;
}

/// The admitted member edges, comma-separated, for a refusal to quote back.
///
/// BUILT FROM THE TABLE at comptime rather than written out beside it: a
/// diagnostic that lists a roster it is not generated from is the same rot as a
/// gate quoting a number it did not measure, and this file has one of those in
/// its history already.
pub const os_dot_member_list: []const u8 = blk: {
    var out: []const u8 = "";
    for (&os_dot_members) |m| {
        if (m.how == .retired) continue;
        out = out ++ (if (out.len == 0) "" else ", ") ++ m.name;
    }
    break :blk out;
};

pub fn osDotMemberList() []const u8 {
    return os_dot_member_list;
}

/// How many members sit in a tier. Read by the tests below and quoted by
/// `gate/roster.sh`, so a tier cannot grow unnoticed.
pub fn osDotTierCount(how: Realization) usize {
    var n: usize = 0;
    for (&os_dot_members) |m| {
        if (m.how == how) n += 1;
    }
    return n;
}

/// The TEST world's relations. Reached as `test:assert(...)` only when the
/// launcher supplied the testing-world witness. Source paths do not grant it.
///
/// This is what `@comp.assert` should have been. A directive namespace is a
/// namespace; a world is a subject, and an assertion is a relation on it.
///
/// Same missing fact as `os_members`, and the same deletion condition: a source
/// form for declaring a world. Two of these six (`raises`, `near`) have no
/// lowering anywhere, which is the other thing a roster cannot say and a
/// declaration derived from realized edges could not have got wrong.
const testing_members = [_][]const u8{
    "assert", "refute", "equal", "differs", "raises", "near",
};

fn has(list: []const []const u8, name: []const u8) bool {
    for (list) |m| if (std.mem.eql(u8, m, name)) return true;
    return false;
}

/// The home that realizes `method` for a subject conforming to this protocol,
/// or null when the protocol does not provide it.
fn realizedBy(list: []const Provided, method: []const u8) ?Home {
    for (list) |p| if (std.mem.eql(u8, p.name, method)) return p.home;
    return null;
}

/// Whether `home` provides `method` TO ITS OWN WORLD — the `os:arg(i)` /
/// `test:assert(x)` question, asked only when the subject names the world.
pub fn homeProvides(home: Home, method: []const u8) bool {
    return provisionHolds(declarationOf(home).*, method);
}

/// Whether ONE DECLARATION provides `method`. Takes the row rather than the tag,
/// so a declaration table that is not the shipped one answers from itself.
fn provisionHolds(d: Declaration, method: []const u8) bool {
    return switch (d.provides) {
        // WRITTEN DOWN, because nothing declares it. Two worlds.
        .roster => |names| has(names, method),
        // DERIVED. Exactly the relations this world REALIZES for some protocol.
        //
        // REALIZES, not MENTIONS: the text roster carries one relation the
        // STRING home does not realize (`read`, realized by `io` — a string is a
        // path), and a mention test would have made `string:read(s)` a legal
        // world spelling of an edge the string world has nothing to do with.
        .realized => realizesAnywhere(d.home, method),
        // THE `io` WORLD PROVIDES NOTHING TO ITSELF, and that is now a
        // CONSEQUENCE of its declaration rather than a rule written against it.
        // It supplies stream INSTANCES; `write`/`read`/`flush`/… are relations
        // on those instances, so `io:write(x)` has no subject and
        // `stdout:write(x)` is the canon (C0 `law.world.grant`, whose `deny`
        // names `io:open(path)` for the same reason). This used to answer from
        // `stream_relations`, which made the world a legitimate receiver for
        // every one of them; then it was a hardcoded `false`; now no world that
        // supplies can provide, whichever world that turns out to be.
        .supplies => false,
    };
}

/// Whether `home` REALIZES `method` for any protocol.
fn realizesAnywhere(home: Home, method: []const u8) bool {
    for ([_]Conformance{ .text, .numeric, .sequence, .stream }) |c| {
        if (protocolProvides(c, method)) |h| {
            if (h == home) return true;
        }
    }
    return false;
}

/// THE DISPATCH. The home that provides `method` TO A SUBJECT WITH THIS
/// CONFORMANCE — the whole resolution, in one function, keyed on the subject.
///
/// A conforming subject reaches its protocol and NOTHING else: `"hi":floor()`
/// and `42:split(",")` have no answer here, where the name list answered both.
///
/// `unknown` is the bridge and is marked as such. A subject sema never narrowed
/// carries no fact to dispatch on, so every roster is still in reach for it —
/// which is exactly today's behaviour, held only for the case where the
/// descriptor is genuinely absent. `os` and `testing` are NOT in that fallback:
/// a world is reached by naming it, and an unnarrowed subject is not a world.
///
/// THE BRIDGE IS NOW ONLY AS WIDE AS THE ABSENCE. It used to be much wider than
/// that: an implicit local discarded its initializer's descriptor, so `s =
/// "text"` arrived here as `unknown` and reached `write`, `close` and `floor` —
/// while the SAME PROGRAM written `s: str = "text"` was correctly refused.
/// `conformanceOfBinding` closes that, and what is left under `unknown` is the
/// genuine article: a parameter, a table field, a call into an untyped relation.
/// The stream roster is still in reach from here BY MEASUREMENT — see
/// `stream_relations`, where 212 corpus sites say why — and that is the one
/// remaining place where `unknown` stands in for a fact rather than reporting
/// its absence.
pub fn homeForConformance(c: Conformance, method: []const u8) ?Home {
    if (c != .unknown) return protocolProvides(c, method);
    // THE BRIDGE. Every roster, in reach from a subject with no descriptor.
    for ([_]Conformance{ .text, .numeric, .sequence, .stream }) |p| {
        if (protocolProvides(p, method)) |h| return h;
    }
    return null;
}

/// BRIDGE, for `dnir_lower.zig` only.
///
/// The lowerer still asks the old question — a boolean "is the receiver a
/// string" derived from its own `strs` slot set, because at lowering time it
/// has slots rather than descriptors. That boolean is the last name-list reach
/// into this file and it belongs to `dnir_lower.zig`, not here; it is expressed
/// as the conformance it was always standing in for, so there is one dispatch
/// and not two.
///
/// DELETION CONDITION: delete when the lowerer carries the subject's descriptor
/// to its call site and can ask `homeForConformance` directly.
pub fn homeOfWithReceiver(method: []const u8, receiver_is_str: bool) ?Home {
    return homeForConformance(if (receiver_is_str) .text else .unknown, method);
}

pub fn homeName(h: Home) []const u8 {
    return declarationOf(h).name;
}

// ── Proofs ──────────────────────────────────────────────────────────────────
//
// Every one of these asserts on the RESOLVED TARGET — which home answered —
// not on the absence of an error. `idol check` accepting a file has twice been
// mistaken for the relation being reachable in this tree, and it is not
// evidence of anything.

test "conformance is read off the descriptor, not off a name" {
    try std.testing.expectEqual(Conformance.text, conformanceOf(.str));
    try std.testing.expectEqual(Conformance.numeric, conformanceOf(.f64));
    try std.testing.expectEqual(Conformance.numeric, conformanceOf(.i64));
    try std.testing.expectEqual(Conformance.numeric, conformanceOf(.u8));
    var elem: RT = .i64;
    try std.testing.expectEqual(
        Conformance.sequence,
        conformanceOf(.{ .array = .{ .elem = &elem, .size = 3 } }),
    );
    try std.testing.expectEqual(
        Conformance.sequence,
        conformanceOf(.{ .table_type = .{ .fields = &.{} } }),
    );
    try std.testing.expectEqual(Conformance.unknown, conformanceOf(.any));
    try std.testing.expectEqual(Conformance.unknown, conformanceOf(.bool));
}

test "a nominal descriptor over a number conforms without this file naming it" {
    // law.nominal: `feet` is a descriptor over f64. Nothing below mentions
    // "feet"; the conformance is derived from the representation, which is the
    // property the name list could not have.
    // The nominal store is process-global and outlives the test, so it is not
    // the testing allocator's to account for.
    try types.declareNominal(std.heap.page_allocator, "feet", .f64);
    const feet = types.nominalNamed("feet").?;
    try std.testing.expectEqual(Conformance.numeric, conformanceOf(feet));
    try std.testing.expectEqual(Home.math, homeForConformance(conformanceOf(feet), "floor").?);
    // ...and it reaches ONLY the math protocol.
    try std.testing.expect(homeForConformance(conformanceOf(feet), "split") == null);
}

test "the subject settles a relation two homes could claim — no tiebreak" {
    // `concat` on a sequence is `table.concat`, the relation that exists.
    try std.testing.expectEqual(Home.table, homeForConformance(.sequence, "concat").?);
    // `concat` on text has NO answer: `string.concat` is not a relation in this
    // compiler or its runtime, and the previous mechanism guessed it into one.
    try std.testing.expect(homeForConformance(.text, "concat") == null);
    // There is no contested list left to consult, and nothing asks the receiver
    // a boolean question. Both answers came from `conformanceOf` alone.
}

test "the subject picks the protocol; the home picks the realization" {
    // `string.char(65)` is realized by the string home, but its SUBJECT is a
    // number — `0:char()` and `255:char()` are how lib/ actually writes it.
    // Dispatching on the name alone filed it under "string" and refused every
    // one of those 111 call sites the moment the subject started mattering.
    try std.testing.expectEqual(Home.string, homeForConformance(.numeric, "char").?);
    try std.testing.expect(homeForConformance(.text, "char") == null);
    // The two axes stay separate: a numeric subject's OTHER relations are
    // realized by math, in the same roster.
    try std.testing.expectEqual(Home.math, homeForConformance(.numeric, "floor").?);
}

test "a conforming subject reaches its protocol and nothing else" {
    try std.testing.expectEqual(Home.string, homeForConformance(.text, "split").?);
    try std.testing.expectEqual(Home.math, homeForConformance(.numeric, "floor").?);
    try std.testing.expectEqual(Home.table, homeForConformance(.sequence, "push").?);

    // The three the name list admitted, measured against `idol check` before
    // this change: all three type-checked clean.
    try std.testing.expect(homeForConformance(.text, "floor") == null); // "hi":floor()
    try std.testing.expect(homeForConformance(.numeric, "split") == null); // 42:split(",")
    try std.testing.expect(homeForConformance(.text, "push") == null); // "hi":push(1)
    try std.testing.expect(homeForConformance(.sequence, "len") == null); // t:len()
}

test "a world is reached by naming it, not by the relation's name" {
    try std.testing.expectEqual(Home.os, worldNamed("os").?);
    try std.testing.expectEqual(Home.testing, worldNamed("test").?);
    try std.testing.expect(worldNamed("wat") == null);
    try std.testing.expect(homeProvides(.os, "arg"));
    try std.testing.expect(homeProvides(.testing, "assert"));
    // An unnarrowed subject is not a world: `x:arg(1)` and `x:assert(y)` have
    // no answer, where the name list answered both for every receiver alive.
    try std.testing.expect(homeForConformance(.unknown, "arg") == null);
    try std.testing.expect(homeForConformance(.unknown, "assert") == null);
}

test "a binding carries the conformance of the value that created it" {
    // The four rows measured on the shipped binary, decided here instead of at
    // the `unknown` fallthrough. `s = "text"` is `str` to everyone except the
    // binding, and this is where the binding gets told.
    try std.testing.expectEqual(Conformance.text, conformanceOfBinding(.str, false));
    try std.testing.expectEqual(Conformance.numeric, conformanceOfBinding(.i64, false));
    try std.testing.expectEqual(Conformance.numeric, conformanceOfBinding(.f64, false));

    // ...and the roster that conformance reaches is the one the ANNOTATED
    // spelling already reached, which is the whole point: two spellings of one
    // program stop disagreeing.
    const s = conformanceOfBinding(.str, false);
    try std.testing.expectEqual(Home.io, homeForConformance(s, "write").?); // path:write(body)
    try std.testing.expect(homeForConformance(s, "close") == null); // s = "text" ; s:close()
    try std.testing.expect(homeForConformance(s, "floor") == null); // s = "text" ; s:floor()
    try std.testing.expectEqual(Home.string, homeForConformance(s, "len").?); // still resolves
    try std.testing.expectEqual(Home.io, homeForConformance(s, "read").?); // a string is a PATH

    const n = conformanceOfBinding(.i64, false);
    try std.testing.expect(homeForConformance(n, "write") == null); // n = 5 ; n:write(x)
    try std.testing.expectEqual(Home.math, homeForConformance(n, "floor").?);

    // A table CONSTRUCTOR types `any`, so the descriptor cannot answer and the
    // AST shape is the witness — the one fact `sequence_bindings` was carrying
    // before this generalized it.
    try std.testing.expectEqual(Conformance.sequence, conformanceOfBinding(.any, true));
    try std.testing.expectEqual(Conformance.unknown, conformanceOfBinding(.any, false));
    // `io.open(…)` answers `any` and is not a constructor: NO witness, so a
    // stream-valued binding keeps the bridge and `f:write(x)` keeps working.
    // This is the row that makes the deletion condition on `stream_relations`
    // load-bearing rather than decorative.
    try std.testing.expectEqual(
        Home.io,
        homeForConformance(conformanceOfBinding(.any, false), "write").?,
    );
}

test "a name bound twice WIDENS, so a stale witness can never refuse" {
    // First binding: the fact is taken.
    try std.testing.expectEqual(Conformance.text, mergedBindingConformance(null, .text).?);
    // Bound again to the same thing: unchanged.
    try std.testing.expectEqual(Conformance.text, mergedBindingConformance(.text, .text).?);
    // DISAGREEMENT RETRACTS. `f = "name"` then `f = io.open(path)` must not
    // leave `f` remembering `text`, or `f:close()` is refused for a program
    // that is correct — the failure mode this rule exists to make impossible.
    try std.testing.expect(mergedBindingConformance(.text, .unknown) == null);
    try std.testing.expect(mergedBindingConformance(.text, .numeric) == null);
    try std.testing.expect(mergedBindingConformance(.sequence, .text) == null);
    // A first binding with nothing to say records nothing, rather than
    // recording "unknown" as though it were a fact.
    try std.testing.expect(mergedBindingConformance(null, .unknown) == null);
}

test "an unnarrowed subject still reaches every protocol — the bridge, marked" {
    try std.testing.expectEqual(Home.string, homeForConformance(.unknown, "split").?);
    try std.testing.expectEqual(Home.math, homeForConformance(.unknown, "floor").?);
    try std.testing.expectEqual(Home.table, homeForConformance(.unknown, "push").?);
    // The stream roster is reachable ONLY from an unnarrowed subject, because
    // `ResolvedType` has no stream descriptor to conform.
    try std.testing.expectEqual(Home.io, homeForConformance(.unknown, "flush").?);
    try std.testing.expect(homeForConformance(.text, "flush") == null);
}

test "an ordinary relation belongs to no builtin home" {
    try std.testing.expect(homeForConformance(.unknown, "recognize") == null);
    try std.testing.expect(homeForConformance(.text, "recognize") == null);
    try std.testing.expect(homeForConformance(.sequence, "recognize") == null);
}

test "a string is a PATH, not a stream" {
    // Path I/O is oriented on the possessed path; the world supplies authority
    // and never becomes the receiver.
    try std.testing.expectEqual(Home.io, homeForConformance(.text, "read").?);
    try std.testing.expectEqual(Home.io, homeForConformance(.text, "write").?);
    const write = edgeFor(.text, "write") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Relation.write, write.relation);
    try std.testing.expectEqual(RT.bool, write.result);
    try std.testing.expectEqual(Home.io, write.world);
    // `close` remains a stream edge: a path has no open handle to close.
    try std.testing.expect(homeForConformance(.text, "close") == null);
    // The `string` WORLD does not gain the path edge: `read` is realized by
    // `io`, and `homeProvides` asks which home realizes it rather than whether
    // the roster mentions it.
    try std.testing.expect(!homeProvides(.string, "read"));
    try std.testing.expect(homeProvides(.string, "split"));
}

test "the io world provides nothing to itself — the stream is the subject" {
    // C0 `law.subject.resolve` deny: `io:open(path)`, `file:read(stream)`.
    // `law.world.grant` fails: "world authority arriving through ... namespace
    // receiver". Every stream relation is denied to the WORLD as receiver.
    for ([_][]const u8{ "write", "read", "close", "flush", "seek", "lines", "setvbuf" }) |r| {
        try std.testing.expect(streamRelation(r));
        try std.testing.expect(!homeProvides(.io, r));
    }
    // ...and the refusal can name the projection, which is what makes it a
    // ruling rather than a wall.
    try std.testing.expectEqualStrings("stdout", exemplarStream("write"));
    try std.testing.expectEqualStrings("stdin", exemplarStream("read"));
}

test "bare reach is decided by COUNT, so two providers diagnose rather than race" {
    // One provider — the standard environment, where `os` alone is injected.
    try std.testing.expectEqual(Home.os, bareReach("env").one);
    try std.testing.expectEqual(Home.os, bareReach("cwd").one);
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("recognize")));
    // A stream relation is NOT a member edge of any injected world, which is
    // why bare `write(x)` has no reach to confer.
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("write")));
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("read")));

    // TWO providers fail closed. `law.inject.algebra`: "ambiguous injection
    // fails rather than picking by declaration import or path priority".
    // The shipped world list holds one world, so the only way to reach this arm
    // is to hand the function a list that has two providers — which is the
    // point: the arm must be exercised BEFORE a second world exists, or the
    // first program to create a conflict is the one that discovers the loop
    // returned whichever provider happened to be listed first.
    const twice = [_]Home{ .os, .os };
    const clash = bareReachIn(&twice, "env");
    try std.testing.expectEqual(BareReach.ambiguous, std.meta.activeTag(clash));
    try std.testing.expectEqual(Home.os, clash.ambiguous.first);
    try std.testing.expectEqual(Home.os, clash.ambiguous.second);
    // ...and the ambiguity does NOT confer reach: the caller that only wants a
    // yes/no is handed no, never one of two answers.
    try std.testing.expect(injectedWorldProvidingIn(&twice, "env") == null);
    // Order is not consulted: a name NO world in the list provides is still
    // `none`, and one provider is still `one`.
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReachIn(&twice, "recognize")));
    const pair = [_]Home{ .os, .testing };
    try std.testing.expectEqual(BareReach.one, std.meta.activeTag(bareReachIn(&pair, "env")));
}

test "the world rosters are DISJOINT, so injection has nothing to resolve" {
    // The property that makes single-answer bare reach sound today. It is
    // asserted rather than assumed: the ambiguity arm above is the behaviour
    // when it breaks, and this is the tripwire that says it broke.
    const worlds = [_]Home{ .string, .math, .table, .io, .testing, .os };
    const names = [_][]const u8{
        "arg",    "args",   "env",    "cwd",     "exit",   "clock",  "time",
        "assert", "refute", "equal",  "differs", "raises", "near",   "sub",
        "match",  "byte",   "len",    "rep",     "lower",  "upper",  "reverse",
        "format", "gsub",   "gmatch", "split",   "trim",   "has",    "tail",
        "starts", "ends",   "find",   "char",    "sqrt",   "sin",    "cos",
        "tan",    "exp",    "log",    "ceil",    "max",    "min",    "abs",
        "floor",  "fmod",   "pow",    "sign",    "round",  "random", "sinh",
        "cosh",   "tanh",   "asin",   "acos",    "atan",   "atan2",  "insert",
        "remove", "sort",   "unpack", "push",    "pop",    "concat", "write",
        "read",   "close",  "flush",  "seek",    "line",   "lines",  "setvbuf",
    };
    for (names) |n| {
        var providers: usize = 0;
        for (worlds) |w| {
            if (homeProvides(w, n)) providers += 1;
        }
        if (providers > 1) {
            std.debug.print("'{s}' is provided by {d} worlds\n", .{ n, providers });
            return error.WorldRostersOverlap;
        }
    }
}

// ── The `os` world's edges: one roster, four askers ─────────────────────────

test "a member edge declares its RESULT, and both faces of the edge read it" {
    // THE MISSING FACT, closed. `dnir_lower` emitted `idol_os_arg` with
    // `.ty = .str` while `codegen.expr_type` answered `any` for the same node,
    // so ONE EDGE had TWO ANSWERS and which one you got depended on how you
    // spelled the receiver — measured on the shipped binary:
    //
    //     p = arg(1) ; p:len()     ANSWERS 5
    //     arg(1):len()             REFUSED  DNB001 method-unresolved:len
    //
    // The first only worked because the string dispatch admits a receiver that
    // is a bare `.name` whatever its type. The result is declared here now, and
    // the type side and the lowering both read this row.
    try std.testing.expect(osDotMember("arg").?.result == .str);
    try std.testing.expect(osDotMember("args").?.result == .str);
    try std.testing.expect(osDotMember("env").?.result == .str);
    try std.testing.expect(osDotMember("cwd").?.result == .str);
    try std.testing.expect(osDotMember("exit").?.result == .void);
    try std.testing.expect(osDotMember("clock").?.result == .f64);
    try std.testing.expect(osDotMember("time").?.result == .f64);
    // `.any` is NOT DECLARED — the honest answer for a member whose result
    // nothing in this compiler knows, never a claim that it answers `any`.
    try std.testing.expect(osDotMember("date").?.result == .any);
    // ...and a word the world has no edge for has no row to read at all.
    try std.testing.expect(osDotMember("bogus") == null);
}

test "a member edge's FACE decides what APPLYING it is" {
    // Three faces, and collapsing them is how `exit(1)` would become an index.
    //
    // This was a THIRD roster, in `table_apply.zig`, with its own struct and
    // its own seven rows — and it had already drifted from this one: `cwd` was
    // written `.value` there with an arm that did NOTHING, so the canonical
    // bare `cwd()` answered DNB011 while `os_dot_members` recorded `cwd` as
    // `.direct` — LOWERS. Two authorities, one fact, and the roster was the one
    // telling the truth.
    try std.testing.expectEqual(Face.projection, osDotMember("arg").?.face);
    try std.testing.expectEqual(Face.projection, osDotMember("env").?.face);
    try std.testing.expectEqual(Face.value, osDotMember("cwd").?.face);
    try std.testing.expectEqual(Face.relation, osDotMember("exit").?.face);
    try std.testing.expectEqual(Face.relation, osDotMember("clock").?.face);
    // The convergence target is the member's own name unless the row says
    // otherwise, and the one row that says otherwise is the PLURAL debt.
    try std.testing.expectEqualStrings("args", osTarget(osDotMember("arg").?));
    try std.testing.expectEqualStrings("env", osTarget(osDotMember("env").?));
    try std.testing.expectEqualStrings("cwd", osTarget(osDotMember("cwd").?));
}

test "the bare roster is DERIVED from the rows, and it does not WIDEN" {
    // `os_members` was a hand-written array of seven names beside these fifteen
    // rows, and the two had to agree about which rows were also member edges.
    // It is taken from `.bare` now. The count is asserted so a row gaining bare
    // reach cannot pass unnoticed — widening is not a small mistake here:
    // `remove` bare would collide with `table.remove` and break the disjointness
    // this file's own tripwire asserts, and `execute` bare would take a name no
    // program asked it to take.
    try std.testing.expectEqual(@as(usize, 7), os_members.len);
    for ([_][]const u8{ "arg", "args", "env", "cwd", "exit", "clock", "time" }) |n| {
        try std.testing.expectEqual(Home.os, bareReach(n).one);
        try std.testing.expect(osDotMember(n).?.bare);
    }
    // ON THE DOT ROSTER AND NOT BARE. `os.execute(cmd)` resolves through the
    // anchor; a bare `execute(cmd)` is an ordinary name and must stay one.
    for ([_][]const u8{
        "execute", "remove",   "rename", "date",
        "tmpname", "difftime", "getenv", "setenv",
    }) |n| {
        try std.testing.expect(osDotMember(n) != null);
        try std.testing.expect(!osDotMember(n).?.bare);
        try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach(n)));
    }
}

test "the ANCHOR may never reach less than the bare face" {
    // `Reach.bare` makes the member edge the canonical face and `os.env(k)` the
    // DISAMBIGUATOR — "reserved for a world where the same name is injected
    // from elsewhere and resolution is genuinely contested". A disambiguator
    // that reaches a SMALLER set than the name it disambiguates is not one; it
    // is a second, narrower surface, and an author who writes the anchor to be
    // explicit gets less than one who does not.
    //
    // MEASURED BEFORE THIS: `cwd()` and `os.cwd()` were both DNB011 while
    // `os.cwd` — the same edge, third spelling — compiled and ran. The property
    // is asserted here rather than assumed, because the shipped table is small
    // enough that a reader would never notice a row missing from one side.
    for (os_members) |n| {
        const m = osDotMember(n) orelse return error.BareMemberHasNoAnchoredFace;
        try std.testing.expect(m.bare);
        // A retired name has a repair to quote; a bare-reachable one cannot be
        // retired, or the canonical face would name a spelling nothing admits.
        try std.testing.expect(m.how != .retired);
    }
}

// ── The declaration, and what it makes decidable ────────────────────────────

test "the declaration table covers every world, exactly once" {
    // `declarationOf` is total by assertion — it ends in `unreachable`, which is
    // a promise this test is the proof of. It also has to be total the OTHER
    // way: two rows for one home would make `homeProvides` answer from whichever
    // came first, which is the ordering accident this whole file exists to
    // remove.
    for (std.enums.values(Home)) |home| {
        var rows: usize = 0;
        for (&declarations) |*d| {
            if (d.home == home) rows += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), rows);
        try std.testing.expectEqual(home, declarationOf(home).home);
    }
    // ...and no two worlds answer to one word.
    for (&declarations, 0..) |*a, i| {
        for (declarations[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.name, b.name));
        }
    }
}

test "a world's name, membership and injection all come from its declaration" {
    // The four questions that used to be four hand-written switches.
    try std.testing.expectEqualStrings("test", homeName(.testing));
    try std.testing.expectEqual(Home.testing, worldNamed("test").?);
    try std.testing.expect(worldNamed("wat") == null);
    try std.testing.expect(homeProvides(.testing, "assert"));
    try std.testing.expect(!homeProvides(.testing, "assert_eq"));

    // A `realized` world's membership is DERIVED, so it cannot disagree with the
    // protocol roster it is derived from. `char` is realized by `string` under
    // the NUMERIC protocol — the case a flat name list got wrong across 111
    // sites — and `string:char(65)` is a lawful world spelling of it because the
    // string home realizes it, whichever protocol listed it.
    try std.testing.expect(homeProvides(.string, "char"));
    try std.testing.expect(homeProvides(.string, "split"));
    // `read` is MENTIONED by the text roster and realized by `io`, so the string
    // world does not gain it.
    try std.testing.expect(!homeProvides(.string, "read"));
}

test "witnessed worlds require exact launcher grants" {
    const ordinary = injectedWorlds();
    try std.testing.expect(ordinary.holds(.os));
    try std.testing.expect(ordinary.holds(.io));
    try std.testing.expect(!ordinary.holds(.testing));

    const testing = injectedWorldsFor(&.{.testing});
    try std.testing.expect(testing.holds(.testing));
    try std.testing.expect(testing.holds(.os));

    try std.testing.expect(worldReached(testing.slice(), .testing));
    try std.testing.expect(!worldReached(ordinary.slice(), .testing));
    try std.testing.expect(worldReached(ordinary.slice(), .os));

    try std.testing.expectEqual(Home.testing, worldNamedFor(testing.slice(), "test").?);
    try std.testing.expect(worldNamedFor(ordinary.slice(), "test") == null);
    try std.testing.expectEqual(Home.os, worldNamedFor(ordinary.slice(), "os").?);
}

test "explicit world grants are general and their conflicts fail closed" {
    const alpha = [_][]const u8{ "alpha", "shared" };
    const beta = [_][]const u8{ "beta", "shared" };
    const two = [_]Declaration{
        .{
            .home = .os,
            .name = "os",
            .provides = .{ .roster = &alpha },
            .injection = .witnessed,
            .reach = .bare,
        },
        .{
            .home = .testing,
            .name = "test",
            .provides = .{ .roster = &beta },
            .injection = .witnessed,
            .reach = .bare,
        },
    };

    try std.testing.expectEqual(@as(usize, 0), inhabitedIn(&two, &.{}).len);

    const in_alpha = inhabitedIn(&two, &.{.os});
    try std.testing.expect(in_alpha.holds(.os) and !in_alpha.holds(.testing));
    const in_beta = inhabitedIn(&two, &.{.testing});
    try std.testing.expect(in_beta.holds(.testing) and !in_beta.holds(.os));

    const both = inhabitedIn(&two, &.{ .os, .testing });
    try std.testing.expectEqual(@as(usize, 2), both.len);

    try std.testing.expectEqual(Home.os, bareReachAmong(&two, in_alpha.slice(), "alpha").one);
    try std.testing.expectEqual(
        BareReach.none,
        std.meta.activeTag(bareReachAmong(&two, in_beta.slice(), "alpha")),
    );

    // Two exact grants still cannot create an ordering rule. `shared` is
    // ambiguous and therefore confers no reach.
    const clash = bareReachAmong(&two, both.slice(), "shared");
    try std.testing.expectEqual(BareReach.ambiguous, std.meta.activeTag(clash));
    try std.testing.expectEqual(Home.os, clash.ambiguous.first);
    try std.testing.expectEqual(Home.testing, clash.ambiguous.second);
    // The ambiguity confers NO reach: the caller that wants a yes/no gets no.
    try std.testing.expect(injectedWorldProvidingAmong(&two, both.slice(), "shared") == null);
    // ...and in a file that inhabits only one of them, `shared` is unambiguous.
    try std.testing.expectEqual(
        Home.os,
        injectedWorldProvidingAmong(&two, in_alpha.slice(), "shared").?,
    );
}

test "injection and REACH are two questions, and only one confers a bare name" {
    // `string` is supplied by every launch — `string.len(s)` resolves anywhere —
    // and confers no bare reach at all, so `len(x)` is an ordinary name and
    // `gate/shadow.id` can declare a relation called `len`.
    const set = injectedWorlds();
    try std.testing.expect(set.holds(.string));
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("len")));
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("floor")));
    try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach("push")));
    // `os` is injected AND confers bare reach, which is the whole difference.
    try std.testing.expectEqual(Home.os, bareReach("env").one);
    try std.testing.expectEqual(Home.os, bareReach("cwd").one);
    // An explicit test-world grant still confers nothing bare; its own name is
    // the anchor and `assert` remains an ordinary bare name.
    const testing = injectedWorldsFor(&.{.testing});
    try std.testing.expectEqual(
        BareReach.none,
        std.meta.activeTag(bareReachFor(testing.slice(), "assert")),
    );
    try std.testing.expectEqual(
        BareReach.none,
        std.meta.activeTag(bareReachFor(testing.slice(), "equal")),
    );
}

test "CROSS-PROJECTION: the world supplies the instance, the protocol carries the relation" {
    // The `io` world provides NOTHING to itself, and that is now derived from
    // its declaration rather than written against it.
    for ([_][]const u8{ "write", "read", "line", "lines", "close", "flush", "seek", "setvbuf" }) |r| {
        try std.testing.expect(streamRelation(r));
        try std.testing.expect(!homeProvides(.io, r));
        // ...and none of them is bare-reachable, though `io` IS injected: what
        // its injection confers is the instances, not the relations.
        try std.testing.expectEqual(BareReach.none, std.meta.activeTag(bareReach(r)));
    }

    // The three standing instances, answered from the supply declaration. This
    // used to be four string comparisons in a function with ZERO consumers,
    // while five other files compared the same three names themselves.
    for ([_][]const u8{ "stdout", "stderr", "stdin" }) |i| {
        const supplied = suppliedInstance(i).?;
        try std.testing.expectEqual(Home.io, supplied.world);
        try std.testing.expectEqual(Conformance.stream, supplied.protocol);
        try std.testing.expect(streamNamed(i));
    }
    try std.testing.expect(suppliedInstance("stdlog") == null);
    try std.testing.expect(suppliedInstance("os") == null);

    // AND THE RELATION IS THE INSTANCE'S. Given the instance's protocol, the
    // relation resolves — one derivation, from the world's own declaration to
    // the home that realizes the edge.
    const out = suppliedInstance("stdout").?;
    try std.testing.expectEqual(Home.io, homeForConformance(out.protocol, "write").?);
    // ...and a relation that is not the protocol's does NOT resolve on it.
    try std.testing.expect(homeForConformance(out.protocol, "floor") == null);
    try std.testing.expect(homeForConformance(out.protocol, "split") == null);

    // A refusal can NAME the omitted projection, and both ends of the direction
    // are declared: the relation says which way its data goes, the instance says
    // which way it faces.
    try std.testing.expectEqualStrings("stdout", exemplarStream("write"));
    try std.testing.expectEqualStrings("stdout", exemplarStream("flush"));
    try std.testing.expectEqualStrings("stdin", exemplarStream("read"));
    try std.testing.expectEqualStrings("stdin", exemplarStream("lines"));
    // `line` is the row a two-arm `if` on `read`/`lines` would have sent to
    // `stdout`, which is the wrong stream and the wrong direction.
    try std.testing.expectEqualStrings("stdin", exemplarStream("line"));
}

test "a supplied instance is a name the world reaches, not a name it takes" {
    // Membership is this file's; ADMISSION is sema's, and sema asks
    // `userBinding` first. What THIS file has to guarantee is that the fact is
    // keyed on the world reaching the launch at all: a world that does not
    // reach supplies nothing.
    const two = [_]Declaration{.{
        .home = .io,
        .name = "io",
        .provides = .{ .supplies = .{ .instances = &standing_streams, .protocol = .stream } },
        .injection = .witnessed,
        .reach = .bare,
    }};
    const reached = inhabitedIn(&two, &.{.io});
    const absent = inhabitedIn(&two, &.{});
    try std.testing.expect(reached.holds(.io));
    try std.testing.expect(!absent.holds(.io));
    // ...and the instance follows the world. `stdout` is a standing name where
    // the world that supplies it reaches, and an ordinary word where it does
    // not — which is what makes "not granted, not reachable" a mechanism rather
    // than a rule someone has to remember to write.
    try std.testing.expectEqual(
        Conformance.stream,
        suppliedInstanceIn(&two, reached.slice(), "stdout").?.protocol,
    );
    try std.testing.expect(suppliedInstanceIn(&two, absent.slice(), "stdout") == null);
}

test "the lowerer's bridge is the same dispatch, not a second one" {
    try std.testing.expectEqual(Home.string, homeOfWithReceiver("split", true).?);
    try std.testing.expectEqual(Home.table, homeOfWithReceiver("concat", false).?);
    try std.testing.expect(homeOfWithReceiver("concat", true) == null);
    try std.testing.expect(homeOfWithReceiver("floor", true) == null);
}
