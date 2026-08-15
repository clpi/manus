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
    /// No descriptor to ask.
    unknown,
};

/// The builtin homes. `os` and `testing` are WORLDS rather than protocols: no
/// value conforms to them, they are reached because the subject IS the world.
pub const Home = enum { string, math, table, io, testing, os };

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

/// The worlds INJECTED into root scope.
///
/// A member edge of an injected world is reachable BARE, because the world is
/// there — `env("HOME")`, `cwd()`, `clock()`, `arg(i)`. That is the CANONICAL
/// face. `os.env("HOME")` is the anchored DISAMBIGUATOR, lawful and reserved
/// for a world where `env` is also injected from somewhere else and resolution
/// is genuinely contested; `os.env["HOME"]` is the retired `[` accessor; and
/// `os.getenv(...)` is not a lawful name at all — two words glued, a C legacy
/// spelling, where LAW-16 wants one irreducible lowercase word.
///
/// MEMBERSHIP, NOT A SECOND LIST. `arg` was admitted by hand in
/// `is_builtin_global` when the argument ruling landed, and the other five
/// members of the same world were not, so `arg(i)` resolved bare and `env(k)`
/// reported "'env' is neither a descriptor nor a callable". Adding the missing
/// five by hand would have been the name-list mechanism in a second location.
/// Bare reach falls out of world membership instead: a world that is not
/// injected confers nothing, and a member edge added to an injected world is
/// bare-reachable with no edit anywhere.
pub fn injectedWorlds() []const Home {
    // `os` only. `test` is injected BY STRUCTURE into the files that inhabit
    // it, and its relations are reached through the world subject
    // (`test:assert(x)`) rather than bare — a bare `equal(a, b)` would capture
    // an ordinary user relation of that name in every test file in the tree.
    return &.{.os};
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
pub fn bareReachIn(worlds: []const Home, name: []const u8) BareReach {
    var found: ?Home = null;
    for (worlds) |w| {
        if (!homeProvides(w, name)) continue;
        if (found) |first| return .{ .ambiguous = .{ .first = first, .second = w } };
        found = w;
    }
    if (found) |w| return .{ .one = w };
    return .none;
}

/// The bare reach `name` has in the STANDARD environment.
pub fn bareReach(name: []const u8) BareReach {
    return bareReachIn(injectedWorlds(), name);
}

/// The injected world that UNIQUELY provides `name`, or null. Ambiguity answers
/// null here too — a caller that only wants "may this name be reached bare"
/// must not be handed one of two answers — and the caller that reports the
/// ambiguity asks `bareReach` for the pair.
pub fn injectedWorldProviding(name: []const u8) ?Home {
    return injectedWorldProvidingIn(injectedWorlds(), name);
}

pub fn injectedWorldProvidingIn(worlds: []const Home, name: []const u8) ?Home {
    return switch (bareReachIn(worlds, name)) {
        .one => |w| w,
        .none, .ambiguous => null,
    };
}

/// The world a builtin subject NAMES, when the subject is a world value rather
/// than an instance. `os:arg(i)` reaches the `os` world because the subject is
/// `os`, not because "arg" appears in a table keyed by home.
///
/// The caller still owns admission: `test` is injected by STRUCTURE and is only
/// a world in a file that inhabits it, which is sema's question, not this
/// file's.
pub fn worldNamed(ident: []const u8) ?Home {
    if (std.mem.eql(u8, ident, "string")) return .string;
    if (std.mem.eql(u8, ident, "math")) return .math;
    if (std.mem.eql(u8, ident, "table")) return .table;
    if (std.mem.eql(u8, ident, "io")) return .io;
    if (std.mem.eql(u8, ident, "os")) return .os;
    if (std.mem.eql(u8, ident, "test")) return .testing;
    return null;
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
const Provided = struct { name: []const u8, home: Home };

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
/// is a real edge and not an aspiration. It sat in an `ot == .str or .any`
/// arity list in sema beside `write` and `close`, which is how `"hi":write(x)`
/// and `"hi":close()` came to type-check clean and die at emit with
/// `DNB001 method-unresolved` — a string is a PATH, and a path is not a stream.
const text_relations = [_]Provided{
    str_("sub"),   str_("match"), str_("byte"),    str_("len"),
    str_("rep"),   str_("lower"), str_("upper"),   str_("reverse"),
    str_("format"), str_("gsub"), str_("gmatch"),  str_("split"),
    str_("trim"),  str_("has"),   str_("tail"),    str_("starts"),
    str_("ends"),  str_("find"),
    .{ .name = "read", .home = .io },
};

fn math_(name: []const u8) Provided {
    return .{ .name = name, .home = .math };
}

/// What a `numeric` subject provides.
const numeric_relations = [_]Provided{
    math_("sqrt"),  math_("sin"),   math_("cos"),   math_("tan"),
    math_("exp"),   math_("log"),   math_("ceil"),  math_("max"),
    math_("min"),   math_("abs"),   math_("floor"), math_("fmod"),
    math_("pow"),   math_("sign"),  math_("round"), math_("random"),
    math_("sinh"),  math_("cosh"),  math_("tanh"),  math_("asin"),
    math_("acos"),  math_("atan"),  math_("atan2"),
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
    tbl_("insert"), tbl_("remove"), tbl_("sort"), tbl_("unpack"),
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
const stream_relations = [_]Provided{
    .{ .name = "write", .home = .io },
    .{ .name = "read", .home = .io },
    .{ .name = "close", .home = .io },
    .{ .name = "flush", .home = .io },
    .{ .name = "seek", .home = .io },
    .{ .name = "lines", .home = .io },
    .{ .name = "setvbuf", .home = .io },
};

/// Whether `name` is a relation ON A STREAM INSTANCE rather than a member edge
/// of the `io` WORLD. THE SUBJECT QUESTION, asked by sema at both application
/// faces so the world-as-receiver spelling is refused in one place.
pub fn streamRelation(name: []const u8) bool {
    return realizedBy(&stream_relations, name) != null;
}

/// The stream INSTANCES the `io` world supplies under a standing name.
///
/// These are the subjects `io.write(stream, x)` may name. Membership is the
/// only fact this file owns; ADMISSION is sema's, exactly as for `worldNamed` —
/// a lexical binding spelled `stdout` is an ordinary value and this file has no
/// way to know that. AN INJECTED WORLD ADDS REACH, IT NEVER TAKES A NAME.
pub fn streamNamed(ident: []const u8) bool {
    return std.mem.eql(u8, ident, "stdout") or
        std.mem.eql(u8, ident, "stderr") or
        std.mem.eql(u8, ident, "stdin");
}

/// The standing stream a refusal NAMES when the author gave it none.
///
/// A refusal that only says no teaches nothing; `io:write(x)` has to come back
/// as `stdout:write(x)` or the author is left guessing which of three standing
/// streams the compiler wanted. Direction is the only fact needed to choose,
/// and the relation states it.
pub fn exemplarStream(relation: []const u8) []const u8 {
    if (std.mem.eql(u8, relation, "read") or std.mem.eql(u8, relation, "lines"))
        return "stdin";
    return "stdout";
}

/// The `os` WORLD's projections, reached subject-first as `os:arg(i)`.
///
/// THE ADDITIONAL MISSING FACT, specific to this roster: the operation-first
/// face does not check module members at all — `os.bogus(1)` type-checks clean
/// today — so there is nothing for the subject-first face to agree with. This
/// roster is the only place that says what the `os` world projects, and it
/// exists because no world declares its own projections.
///
/// Canonically these need no anchor: `os` is injected in the standard world, so
/// `env("HOME")` and `arg(i)` at root scope are the canonical faces — see
/// `injectedWorlds`, which reads THIS roster to answer bare reach, so the two
/// spellings of an os edge cannot come apart. `args` is the legacy plural — an
/// identity is singular — kept only so existing source keeps working, and
/// `getenv` is deliberately absent: two words glued is not a lawful name.
const os_members = [_][]const u8{
    "arg", "args", "env", "cwd", "exit", "clock", "time",
};

/// The TEST world's relations. Reached as `test:assert(...)`, and only in a
/// file the test world is injected into — which sema derives from where the
/// file LIVES (`test/`, `*_test.id`), not from an import or an attribute.
///
/// This is what `@comp.assert` should have been. A directive namespace is a
/// namespace; a world is a subject, and an assertion is a relation on it.
///
/// Same missing fact as `os_members`: the world does not declare its own
/// relations.
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
    return switch (home) {
        .os => has(&os_members, method),
        .testing => has(&testing_members, method),
        // The three protocols answer through their conformance roster; a world
        // spelling like `string:len(s)` reaches the same relations.
        //
        // `== Home.string`, not `!= null`: the text roster carries one relation
        // the STRING home does not realize (`read`, realized by `io` — a string
        // is a path), and `!= null` would have made `string:read(s)` a legal
        // world spelling of an edge the string world has nothing to do with.
        .string => realizedBy(&text_relations, method) == Home.string or
            realizedBy(&numeric_relations, method) == Home.string,
        .math => realizedBy(&numeric_relations, method) == Home.math,
        .table => realizedBy(&sequence_relations, method) != null,
        // THE `io` WORLD PROVIDES NOTHING TO ITSELF. It supplies stream
        // INSTANCES; `write`/`read`/`flush`/… are relations on those instances,
        // so `io:write(x)` has no subject and `stdout:write(x)` is the canon
        // (C0 `law.world.grant`, whose `deny` names `io:open(path)` for the
        // same reason). This used to answer from `stream_relations`, which made
        // the world a legitimate receiver for every one of them.
        .io => false,
    };
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
    return switch (c) {
        .text => realizedBy(&text_relations, method),
        .numeric => realizedBy(&numeric_relations, method),
        .sequence => realizedBy(&sequence_relations, method),
        .unknown => realizedBy(&text_relations, method) orelse
            realizedBy(&numeric_relations, method) orelse
            realizedBy(&sequence_relations, method) orelse
            realizedBy(&stream_relations, method),
    };
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
    return switch (h) {
        .string => "string",
        .math => "math",
        .table => "table",
        .io => "io",
        .testing => "test",
        .os => "os",
    };
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
    try std.testing.expect(homeForConformance(s, "write") == null); // s = "text" ; s:write(x)
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
    // `path:read()` is `law.world.grant`'s own canon and it lowers today.
    try std.testing.expectEqual(Home.io, homeForConformance(.text, "read").?);
    // `write` and `close` on a string do NOT resolve. Both used to, through an
    // `ot == .str or .any` arity list in sema, and both then died at emit with
    // `DNB001 method-unresolved` — `idol check` said the program was fine and
    // it could not be built.
    try std.testing.expect(homeForConformance(.text, "write") == null);
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
        "arg",    "args",  "env",     "cwd",    "exit",   "clock",  "time",
        "assert", "refute", "equal",  "differs", "raises", "near",
        "sub",    "match", "byte",    "len",    "rep",    "lower",  "upper",
        "reverse", "format", "gsub",  "gmatch", "split",  "trim",   "has",
        "tail",   "starts", "ends",   "find",   "char",
        "sqrt",   "sin",   "cos",     "tan",    "exp",    "log",    "ceil",
        "max",    "min",   "abs",     "floor",  "fmod",   "pow",    "sign",
        "round",  "random", "sinh",   "cosh",   "tanh",   "asin",   "acos",
        "atan",   "atan2",
        "insert", "remove", "sort",   "unpack", "push",   "pop",    "concat",
        "write",  "read",  "close",   "flush",  "seek",   "lines",  "setvbuf",
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

test "the lowerer's bridge is the same dispatch, not a second one" {
    try std.testing.expectEqual(Home.string, homeOfWithReceiver("split", true).?);
    try std.testing.expectEqual(Home.table, homeOfWithReceiver("concat", false).?);
    try std.testing.expect(homeOfWithReceiver("concat", true) == null);
    try std.testing.expect(homeOfWithReceiver("floor", true) == null);
}
