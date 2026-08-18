# Idol — final one-page language + semantic + compiler law

This is the **supreme one-page law** of Idol. It is authoritative and supersedes
any stale projection wherever they diverge. `docs/spec/constitution.md` (C0)
remains the structured long-form expansion of this law and the home of the
`law.*` identities that gates and code reference; where C0, `docs/spec/agent.md`,
`docs/spec/canonical.md`, `CLAUDE.md`, `AGENTS.md`, or any gate diverges from
this page, this page wins and the divergent text must be corrected to match it.

A projection is never authority above this page. A re-pasted partial prompt is
never authority above this page.

## Purpose

Idol is Lua progressively specialized into native execution.

    ordinary Lua meaning
    → inferred facts
    → guarded specialization
    → sealed specialization
    → native representation
    → target realization

The compiler gains knowledge. The programmer should not have to rewrite code to
become fast.

### Primary objective

FTCFTW is not parity with C, LLVM, Fortran, Wasmtime, or any named compiler. It
is verified Pareto **dominance** over the best known semantically equivalent
implementation, reaching the physical lower bound wherever dominance is
impossible, with optimization space permanently open. The comparison oracle is
always two things at once: the strongest known implementation AND the semantic/
physical lower bound. C, LLVM, Fortran, Wasmtime, hand assembly, and specialized
libraries are each only one oracle among many.

For every cost dimension — a non-exhaustive vector whose full physical extent is
defined by §100 and §102, not this list — exactly three outcomes are valid.
Dimensions include: runtime, throughput, tail, startup, warmup, compile,
incremental, compiler/runtime/peak memory, allocations, memory traffic, binary
bytes, loaded bytes, relocations, syscalls/kernel transitions, branches,
mispredicts, instructions, loads, stores, cache misses, TLB misses, page faults,
startup page working set, uop-cache residency, spills, code-cache pressure,
sustained/thermal throughput, and energy:

- WIN: strictly better than the best competitor with equivalence + confidence.
- OPTIMAL: equal the proven lower bound where no improvement is physically
  possible (fewer operations than the semantic minimum is impossible — this
  counts as FTCFTW closure).
- LOSS: expose the exact optimization debt — application id, extra physical
  cost, semantic cause, unresolved fact, lower bound, and workstream. A loss
  without causal decomposition is itself a compiler defect.

Conflicting dimensions are evaluated as a Pareto frontier under an explicit
build-world policy/budget (§98), never collapsed into a vanity scalar. No win
elsewhere compensates for an open loss (§100).

- smaller artifacts · faster startup · lower memory · faster compilation are
  dimensions of that frontier, not afterthoughts.
- faster Wasm than Wasmtime across target workloads on every measured phase.

SHC: every production semantic decision eventually produced by Idol itself.

## 1. Fundamental law

OBSERVATION-ONE is the deepest law: a program is a set of required observable
relationships between inputs, worlds, effects, outcomes, and outputs — not a
sequence of execution steps. Semantic observations are the only invariants;
identity and facts define which observations are required; everything else —
control flow, algorithms, data structures, memory, code, OS interaction,
hardware placement, and compiler strategy — is realization space that may
disappear, transform, migrate, or be synthesized whenever verified equivalence
permits a cheaper physical outcome (§104, §105).

Its consequence:

SEMANTIC IDENTITY PERSISTS. REPRESENTATION CHANGES.

One semantic thing → one id. Facts qualify identities. Facts do not mint
identities.

Names, paths, spans, hashes, fingerprints, opcodes, slots, pointers,
representations and source spelling are never semantic identity.

Unknown ≠ absent ≠ false ≠ zero ≠ empty.

Every authoritative fact has exactly one producer.

After a fact is known: preserve it; never reconstruct it downstream.

## 2. Source minimum / graph maximum / realization minimum

Canonical optimization target:

    MINIMUM SOURCE SPELLING
    MAXIMUM SEMANTIC FACTS
    MINIMUM PHYSICAL WORK

If the compiler can recover a fact uniquely, source should normally omit it.

Inference may use: subject, operands, result demand, descriptor demand, exact
reachable facts, relation constraints, world, authority, effects, stage,
provenance, control-flow refinement.

If one lawful interpretation remains: infer it. If several remain: spell only
the smallest missing distinction. If compiler inference is unique but human
meaning becomes genuinely unclear: retain the irreducible meaningful relation
word.

Never canonize redundant source syntax merely because inference is not yet
implemented. Mark `IMPLEMENTATION-BLOCKED`, then implement the inference.

## 3. World

A WORLD is the closed semantic table under which meaning is resolved.

A world may contain: bindings, descriptors, relations, semantic facts, other
worlds, stage facts, target facts, execution/environment facts, authority
requirements and witnesses.

Authority is a fact within a world. World is not synonymous with authority.

A world is an ordinary semantic table. No separate World object hierarchy.

## 3a. Source, law, grammar, world

Source supplies bytes, spans, origin, and provenance. Law supplies how those
bytes and the values they denote behave. Grammar is the one compiler authority's
projection of a source law into token identities, roles, precedence, and
structural recognition. World supplies bindings, descriptors, relations,
values, laws in reach, stage and target facts, authority requirements, and
witnesses. The graph owns resolved meaning. Demand decides which observations
must survive. Realization chooses physical execution.

The ordering is exact:

    recognize(source, source law) -> syntax provenance
    resolve(syntax, world, source law) -> semantic facts
    project(semantic facts, demand) -> specialization
    realize(semantic facts, demand, target) -> physical execution

Exactly one source law owns every source position. Never union grammars, try
several parsers and choose one that accepts, infer a grammar from command-like
text, or activate syntax because a world or authority is reachable. Canonical
`.id` ingress selects Idol source law; other admitted source partitions may
select Lua, C, Bash, Wasm, or another exact law. A suffix or path may participate
at ingress and remains provenance afterward; it is never reconstructed as
semantic authority.

Do not mint a semantic dialect, source-world, grammar-world, foreign-mode, or
language-mode identity. `origin`, `law`, span, and provenance qualify ordinary
identities in the one graph. Foreign grammar remains source recognition state,
not permanent `BashPipelineNode`, `LuaMethodCall`, `CForStatement`, or
`IdolSubjectCall` semantic kinds. Foreign meaning that has no witnessed native
equivalent remains an exact foreign semantic identity in the same id universe.

Source law never grants authority or selects realization. A tool may recognize
Bash with zero process authority. Process authority may be present while Idol
grammar remains unchanged. Shell is command interpretation law; Bash is one
foreign source and semantic lawset; process is a world capability. They are
independent facts even when a launcher supplies them together.

Whole-source partitions are the first ingestion boundary. Inline polyglot
source, if admitted later, requires one neutral face that captures an unparsed
source span before a law is selected. It does not execute, import, change world,
or grant authority. Its punctuation is not frozen. Ordinary `thing@world`
remains semantic interjection after recognition and never becomes a parser-mode
switch.

## 4. @

`@` means exactly THE CURRENT WORLD.

No second meaning. No generic compiler namespace. No `@comp`. No `@host`. No
`@runtime`. No directive zoo.

Bare `@` is the current world value.

`@` is itself the accessor. `@` immediately followed by a static name accesses
that world member — `@target`, `@env` — only when explicit spelling is actually
necessary. There is no `@.` projection step and no `@:` subject dispatch:
`@.member` and `@:member` are INVALID. `@member.child` is one world access then
one ordinary static projection.

World qualification `thing@world` means: interpret/project `thing` in `world`.

Explicit current-world qualification `thing@` is legal if useful, but normally
redundant because current-world resolution is already implicit.

World qualification does not automatically mint a new identity. Same meaning in
different worlds: same semantic id, different witness/target/realization facts
where appropriate.

Every `@` form must be explainable through world semantics.

## 5. Filesystem + dot

Filesystem establishes INITIAL static table/home topology. One filesystem
level: one static projection.

After ingestion: path = provenance; ids/facts = authority. Never walk
filesystem paths again to recover semantic meaning.

`.` ALWAYS means exactly one STATIC projection: one statically known table
member OR one filesystem-originated child level.

    world.target.arm
    config.database.host

Never use `.` for: dynamic dispatch, method search, extension lookup, namespace
fallback, recursive lookup, world fallback.

`a.b.c` is exactly `a → b → c`, one static projection per dot.

No native module/namespace/import system. Directory/file structure creates
ordinary tables/homes. A root source such as physical `main/lib.id` may
establish the root world table, but `lib` must never become a semantic
namespace prefix.

## 5a. Dot is one static step

`.` is the strongest grammar invariant: every dot is exactly one statically
known structural projection — one filesystem child level, or one static member
of a value/table. Nothing else.

    sale.quote          # sale → static member quote
    target.arm.feature  # three known values, two projections

`.` never means method lookup, extension lookup, dynamic dispatch, namespace
search, recursive lookup, world fallback, or parent lookup.

A projected member that is itself callable applies normally: `math.sin(x)` is
static projection then application. If `math` is instead the subject of relation
`sin`, that is `math:sin(x)`. The two are not interchangeable.

`.` is never computed. A runtime key uses application: `table(key)`, never
`table.key`.

## 5b. Filesystem is the root world table

The filesystem establishes the initial static world topology, then its semantic
job is finished. Physical `main/` is the source-root convention — not a language
main, entry, namespace, or identity. `main/lib.id` is the root table body; `lib`
is not a namespace prefix and user code never writes `lib.sale.quote`.

The resulting root table is `@`. Sibling files and directories are its members:
`main/tax.id` → `tax`; `main/sale/quote.id` → `sale.quote`. Each `/` after the
source root is exactly one static `.` projection.

After ingestion: path = provenance; id/facts = authority. No component walks
directories again to recover meaning.

A directory is a static table, not a category bucket. Prefer paths whose every
segment is a real projected entity (`sale/quote.id`, `target/arm.id`); reject
organizational buckets (a utility, helper, service, model, handler, provider,
common, shared, core, internal, or module directory that names no entity).

## 5c. Projection · injection · interjection · mutation

Projection, injection, and interjection are three uses of ordinary world/table
semantics — not three subsystems. No inject, scope, context, provider, registry,
or dependency framework is introduced.

    @x               access     select one exact static fact/member
    @{ k = v }       inject     derive a closed world with exact fact deltas
    thing@world      qualify    evaluate thing under world
    thing@{ k = v }  interject  evaluate thing under an injected world
    @k = v           mutate     obtain a world member as a place and mutate it

`@` is the accessor itself: write `@x`, never `@.x`; `@.x` and `@:x` are invalid
because `@` already performs the access. Access selects an exact member. A bare
name may infer as a static access of `@` when no lexical binding supplies the
meaning: `tax(sum)` resolves as `@tax(sum)` when unique; the shorter form is
canonical. Spell `@tax` only when the distinction matters — for example a lexical
`tax` shadows the ambient member. Missing access (`@missing`) fails; there is no
parent, global, library, or default fallback. A world cannot hold two incomparable static definitions for one
member and silently choose.

Injection derives a new closed world from the current one, replacing or adding
only the stated facts. `@{ … }` is not mutation; the source world is unchanged.
It may be realized by structural sharing, persistent tables, exact deltas, or
full elimination after specialization — but semantically it is closed:
resolution does not search the derived world and then fall back to the source.

Interjection needs no new syntax: `thing@{ k = v }` means `thing@(@{ k = v })` —
evaluate `thing` under a derived world whose stated facts were explicitly
replaced. The caller's world is unchanged afterward.

Mutation `@k = v` obtains a world member as a place and mutates it; it is legal
only when that application yields a place. Mutation is persistent and observed by
every alias of that world identity. Prefer interjection for scoped replacement;
mutate the ambient world only when the persistent state change is itself the
meaning. A derived world is a distinct world: mutating a member of an injected
world mutates that world, never the source.

## 5d. Injection algebra

For a world `w` and explicit `k = v`:

    project(inject(w, k=v), k) = v
    project(inject(w, k=v), q) = project(w, q)   # every untouched q

These equalities are established when the derived world is formed — not by a
runtime parent-world fallback. Empty injection is identity (`@{}` ≡ `@`, and
should disappear). Injecting the exact existing fact is idempotent, and the
derived world may be erased. A duplicate member in one injection literal is an
error — no declaration-order magic. Nested injection explicitly shadows the outer
world: the inner fact wins because it was formed last, not because of search.

## 5e. World qualification, propagation, scope

`thing@world` evaluates the whole expression world-relative:
`(sale.quote@trial)(100)` resolves `sale.quote` under `trial`, then applies.
Inside, bare `@` is `trial`, and inferred ambient projections come from `trial`.
Qualification scopes to the evaluated subtree; it does not mutate the caller.

Dot binds after qualification: `thing@world.member` is `(thing@world).member`.
Use `thing@(world.member)` when the world expression is itself nested. Postfix
`thing@` is `thing` under the current world (normally redundant, so
SOURCE-INFER-ONE removes it) — useful only to take the current-world definition
as a value at that point.

A world-qualified application threads its current world through unresolved
ambient dependencies in that subtree; a child application without its own
qualifier receives the same world facts. This is semantic threading, not a
runtime World argument. When everything is statically known: world object 0,
lookup 0, dispatch 0 — the graph records only the exact facts selected.

Lexical binding wins for a bare lexical name; `@x` explicitly accesses the world
member. The resolver sees one closed lexical + world fact set and records exact
ids: no lexical search, no world search, no parent search afterward.

## 5f. able, worlds, authority

`able(read)` proves the subject can participate in a relation; it never proves
execution authority. `source:read()` may additionally demand a world witness.
Relation applicability and world authority are separate facts.

Injection changes fact availability; it never bypasses satisfaction. A boolean,
label, or string cannot manufacture authority — `@{ authority = true }` grants
nothing. An injected authority fact must itself be a valid semantic witness:
`job@{ witness = permit }()` runs only if `permit` actually satisfies the
demanded authority relation.

A closure captures the smallest exact necessary world fact, not the whole world.
`(sum) sum + fee` depends on the exact `fee` fact and specializes it away when
static. The ambient world is not an automatic giant closure environment.

Name a world for its genuine scenario, never for the fact it injects: prefer a
domain world `trial` that injects `tax` inside it over a world named for
tax-freeness, and inject `clock` rather than naming a member after a stand-in
clock. The world already carries the qualifying fact.

## 6. Application (APPLICATION-ONE)

There is ONE application algebra. Not separate semantic kingdoms for: function
call, method call, table lookup, accessor call, indexing, generic call, protocol
call, or builtin call. Every `value(args...)` is one semantic question:

    given applied value V, operand pack A, current world W, and result demand D,
    what exact lawful application exists?

Syntax never encodes the answer. `f(x)`, `table(key)`, `descriptor(value)`,
`world(key)`, `closure(x)`, and `foreign(x)` all begin as the same question.

Resolution MAY use only: applied value identity; operand identities/facts;
operand pack shape; result demand; descriptor facts; table shape; relation
facts; current world; authority/witness facts; stage; control-flow refinements;
known metatable facts; target-independent semantic facts.

Resolution MUST NOT use: callee spelling; file path; source category; AST node
kind; "looks like a function"; "looks like a table"; declaration order; fallback
priority; nearest namespace; registry order.

Resolution output is exactly one application fact: application id, applied
identity, relation id (only if semantically meaningful), subject id (only if
semantically oriented), operand pack, result pack, descriptor constraints,
effect, authority requirement, witness, stage, demand, provenance. Realization
chooses physical behavior only afterward. There is exactly one authoritative
owner per application dimension (§21).

Resolution ladder:

    1. collect exact applied/subject/operand/world/demand facts
    2. enumerate lawful semantic applications
    3. eliminate impossible candidates from exact constraints
    4. project implied relation / descriptor / conversion / able / witness /
       world fact / result pack / stage
    5. exactly one candidate remains  → publish the exact application
    6. zero candidates                → invalid application
    7. more than one incomparable     → AMBIGUITY (fail-closed)
    8. only after semantic closure    → choose realization

Ambiguity is fail-closed. Never resolve by first/nearest declaration, most
recently injected, function-before-table, table-before-relation, or "more
specific" unless specificity is mathematically defined.

Currying is not automatic. `add(1)(2)` is ordinary chained application whose
first application yields a callable. Do not invent a closure merely because
fewer operands were supplied; partial application specializes only where the
relation/application descriptor explicitly admits it or a known callable value
returns another applicable value.

Metatable / `__call` resolves ONCE. The resolver reads table/metatable facts and
publishes the exact lawful application; the backend never runs "try function,
else table, else __call" priority code. Sealed metatable → dynamic dispatch 0;
a still-dynamic metatable keeps runtime dispatch because semantic alternatives
remain.

Operators and conversion are application sugar. `a + b` resolves to the same
arithmetic relation application as the explicit form; `value:to(str)` is
explicit relation application only when the target is not inferable. No
operator-specific backend semantics, no CoercionKind, no conversion search from
host types. Grammar owns punctuation precedence; the resolver owns meaning.
Lowering consumes the complete resolved application and never reconstructs an
adjacent fact from spelling, AST, host types, or table/function category.

## 7. Table access

Ordinary access is application: `table(key)`. Not `table[key]`, not
`table:get(key)`, not `get(table, key)`.

Read versus write does not select a different table operation — demand does:
`x = table(key)` demands a value; `table(key) = value` demands a place. No
setter ontology, and no `get` / `set` / `call` relation invented merely for
uniformity — the application itself is enough.

Static `.` and application `()` assert different author knowledge and stay
distinct source faces: `user.name` asserts one statically known structural
projection; `user("name")` is ordinary application with key operand `"name"`.
If the compiler proves both denote the same member they may converge to one
semantic identity, but `.` is never computed — a runtime key always uses
`table(key)`. Ordinal access `row(1)` is likewise ordinary application; no `[]`,
`at`, or `get` unless `at` is an independently meaningful domain relation.

Cost falls monotonically with knowledge (§26): dynamic table + dynamic key →
generic lookup; known shape + known-domain key → specialized dispatch/offset;
known shape + exact key → direct field offset; sealed table + exact demanded
field → scalar replacement; constant → no table at runtime. The source form is
identical throughout.

## 8. Colon

`:` means meaningful relation orientation on a semantic subject.

    source:read()
    path:open()
    stdout:write(text)
    text:find(pattern)
    text:parse(json)

Prefer subject-first relations. Not `read(source)` / `io.read(source)` unless
there is genuinely no semantic subject.

Do not spell a relation merely because the graph contains one. Canonical `f(x)`
not `f:call(x)`. Canonical `table(key)` not `table:get(key)`. Retain an explicit
relation only when it contributes semantic/human meaning.

Colon is source subject orientation only. After resolution it is still just an
application (§6) — there is no `method_call` or `member_call` graph kind, and
`text:find(pattern)` records subject `text`, relation `find`, operands
`{pattern}`, never a distinct method-call node.

The operator partition is absolute; no operator steals another's job:

    @     world access / world qualification
    .     exactly one static structural projection
    :     subject orientation onto a semantic relation
    ()    universal application

Projection finds a statically known value. Relation orientation supplies a
semantic subject. World qualification selects the closed fact environment.
Application does everything that remains.

## 9. able

`able(...)` is the ONE explicit protocol/requirement boundary.

It does NOT create: traits, interfaces, protocol objects, dictionaries,
vtables, adjective types.

    able(eq)
    able(read)
    able(to(str))

Meaning: the unknown subject at this boundary must admit the demanded
relation/application shape. `able(eq)`: subject must admit equality application.
`able(to(str))`: subject must admit conversion to str.

ABLE IS NORMALLY INFERRED. If implementation/use already establishes the
requirement, do not spell `able`.

    show = (value)
        stdout:write(value)

should not require `value: able(to(str))` if write demand uniquely establishes
the needed facts.

Explicit `able(...)` is justified only at a real boundary: public/open generic
contract, implementation unavailable, higher-order boundary, several possible
requirements remain ambiguous, or descriptor explicitly exposes its admitted
relation shape.

INFER ABLE FIRST. SPELL ABLE ONLY AT A REAL BOUNDARY.

Static satisfaction: runtime protocol object = 0, dictionary = 0, vtable = 0.
Protocol satisfaction never grants authority.

## 10. Conversion

One semantic conversion relation: `to`. No cast/coerce/convert/into/stringify/
generic encode-decode kingdom. But source normally omits `to`.

If target is uniquely demanded: `payload: json = value` not
`payload = value:to(json)`. If consumer uniquely demands text:
`stdout:write(count)` not `stdout:write(count:to(str))`.

Explicit `value:to(target)` ONLY when target cannot otherwise be uniquely
inferred. There is NO canonical `value:to()`.

Parsing may remain distinct when grammar/failure law is distinct:
`text:parse(json)`. No `from` relation.

## 11. Bindings + intermediate zero

Canonical `x = value` / `x: descriptor = value`. No local/let/var/const.

Binding ≠ value ≠ place. Binding does not imply storage. Bindings name meaning;
they do not manually encode compiler SSA steps.

Wrong:

    checked = value:validate()
    checked:normalize()

Canonical: `value:validate():normalize()`.

Wrong:

    stream = path:open()
    text = stream:read()
    text:parse(json)

Canonical when semantics permit: `path:open():read():parse(json)`.

Keep an intermediate only if: it has independent semantic meaning, multiple
consumers, control-flow refinement requires identity, mutation/place identity is
observable, lifetime/effect ordering requires it, or the name materially
improves otherwise ambiguous human meaning. No tmp/result/current/next merely
for stepwise flow.

## 12. Functions + control

    add = (a, b) a + b

    normalize = (value)
        value:validate():normalize()

Tail expression returns. Root body executes.

No canonical function/fun/fn/main/entry/init/end/then/do/result. Offside blocks.
No canonical main wrapper merely to run a file.

## 13. Descriptors

Descriptor = semantic facts/constraints. One descriptor mechanism eventually
covers types, concepts, enums, schemas, protocols, target facts, stage facts,
formats.

Do not recreate class/struct kingdom/trait/interface/impl/concept object/
protocol object. Descriptor identity is exact id based; never identify
descriptors by name. Semantic value is independent from physical representation.

## 14. Shapes

One shape system covers table structure. The same semantic table may realize as
generic hash table, specialized keyed table, contiguous sequence, native struct,
scalarized fields, registers, SIMD layout, SoA, AoS, AoSoA, or a
compile-time-only value that disappears.

Shape facts drive representation. Source table semantics never force hash-table
realization.

## 15. nil / presence

`nil` is ordinary absence. Do not create absent/present/maybe/option/none/some/
missing. Do not rebox presence with has/contains/exists/present.

Use ordinary lookup/search and refine:

    value = table(key)
    position = text:find(pattern)

Unknown is not nil. Known absence is not unknown. Every optional graph fact must
distinguish unknown / known absent / exact fact.

## 16. Identifier law

Project-owned semantic names: lowercase, singular, one irreducible word. No
underscore/camelCase/PascalCase/kebab-case/mashed compounds/invented
abbreviations/numeric historical taxonomy.

DELETE / DECOMPOSE BEFORE RENAME. A name is admissible only if deleting it would
lose a genuinely independent semantic entity. Facts must not become identities.

## 17. Cardinality zero

Semantic identity denotes one thing. Plurality belongs to table membership, pack
membership, cardinality, shape.

Do not create semantic identities meaning merely "many X" (bytes, strings,
fields, values, arguments, results, nodes, edges, captures, tests, worlds,
protocols, descriptors). Do not evade with collection/bundle/set/catalog/pool/
container/suite if the meaning remains "many X."

## 18. Role / capability / mediator zero

No adjective protocol identities (readable, writable, callable, iterable,
serializable). `able(...)` replaces the legitimate explicit requirement
boundary.

No generic performer-role identities (reader, writer, runner, caller, encoder,
decoder, resolver, provider, builder, generator).

No mediator systems duplicating language semantics (router, dispatcher,
registry, manager, factory, adapter, broker, controller, coordinator,
orchestrator, handler, executor, engine, pipeline, context, session, service,
framework).

Routing = application resolution. Registration = graph facts. Context = closed
world/fact set. Dispatch = application + realization. Adaptation = foreign
projection/realization.

## 19. Graph

One semantic graph is the source of truth. AST is transitional source
structure/provenance; it is not downstream semantic authority.

After graph publication: AST semantic backedges → 0, source-name reconstruction
→ 0, path reconstruction → 0, opcode reconstruction → 0, host-type
reconstruction → 0.

Graph contains dense semantic ids, exact facts, exact structural relations.
Physical indexes may accelerate queries but may never establish meaning.

TAG-AUTHORITY-ZERO: NodeKind / EdgeKind tags may narrow candidates but exact
facts determine semantic validity. No module/function/call/type kingdom encoded
merely through tags.

## 20. Graph fact storage

Do not build one giant nullable Node object carrying every possible fact.

Target: dense entity ids, packed sparse fact columns/ranges — `provenance[id]`,
`descriptor[id]`, `home[id]`, `stage[id]`, `demand[application]`,
`realization[application]`.

Only facts that exist consume storage. Names/prose/target realization metadata
stay out of semantic hot structures.

Common graph reads use borrowed immutable views, dense adjacency, O(out-degree)
traversal. No query → alloc → memcpy → free for ids already stored contiguously.

## 21. Application fact closure

Every application dimension has EXACTLY ONE authoritative location. Required
manifest: relation, subject, operands, results, descriptor, demand, effect,
authority, witness, stage, caller/home, provenance, target, realization.

Derived indexes are rebuildable projections only. Never store the same semantic
fact independently in Node, edge, ApplicationFact, scope, auxiliary map unless
exactly one is authoritative and all others are mechanically derived.

## 22. Edges

Edges express structural semantic roles. Never operational action names.

Forbidden edge kinds: run, call, invoke, execute, read, write, get, set, open,
parse, encode, decode, convert, compile, lower, emit, transform, dispatch,
resolve, load, store.

Correct: `application --relation--> read-id`. Not `file --read--> result`.

Relation identity owns operation meaning. No authoritative reverse duplicates.
Reverse traversal is derived index/query.

## 23. Home

Home = declaration/reachability anchor. Not namespace/module/authority/protocol/
world grant.

Home/member/provenance replace module semantics. Moving an identity between
equivalent homes must not change the identity of the relation/value itself. No
module kingdom.

## 24. Demand

Demand belongs primarily to the exact application/use occurrence. The same value
can have different demand at different uses.

Demand includes: which result slots matter, which fields matter, addressability,
effect requirement, precision, representation constraints, target constraints.

Demand deletes work BEFORE materialization. Unused result: allocation 0, pack
materialization 0, boxing 0, when semantics permit.

## 25. Representation one

There is exactly one physical representation decision. The semantic graph does
NOT decide boxed/stack/heap/register/struct/SIMD/ABI layout. Realization does.

Input facts: descriptor, shape, demand, lifetime, escape, alias, mutation,
stage, target, ABI boundary. Output: one selected physical realization. Later
passes do not re-decide representation independently.

`none` — physical nonexistence — is a first-class representation (§104): an
unused result, compile-time-known value, inlined closure, known world, or
descriptor metadata may materialize as nothing at all.

## 26. FTCFTW cost law

Every physical cost must name the unresolved semantic possibility requiring it.

For every allocation, copy, box, tag, hash, indirect call, guard, runtime
descriptor, closure environment, world object, ABI shuffle, spill, lock, atomic,
materialized pack, the compiler must answer WHY. No causal semantic reason: bug.

Required zeros: known shape → generic hash 0; exact target → indirect call 0;
nonescaping closure → heap environment 0; singleton alternative → runtime tag 0;
unused result → materialization 0; known witness → runtime world lookup 0;
static able proof → protocol runtime object 0; direct descriptor satisfaction →
conversion 0.

## 27. Guards

Guard = unresolved semantic alternative under speculative specialization. A
guard carries: assumed fact, evidence/witness, fast realization, exact recovery
realization, provenance.

Known fact: guard 0. Unknown fact: general realization. Do not use guard
existence as reason to box unrelated values.

## 28. Specialization

Specialization accumulates facts. It does not automatically mean code cloning.
Clone only when runtime gain beats compile cost, binary growth, I-cache
pressure, startup cost.

The same semantic relation/application identity may have multiple realizations.
No specialized semantic identity merely because machine code differs.

## 29. Value / place / memory

Value ≠ binding ≠ place. Place exists only when semantics demand observable
storage: mutation, alias, address, lifetime, ABI. Otherwise prefer
scalar/register/value representation.

Memory realization hierarchy may include register, stack, static, region, arena,
isolated heap, GC heap. GC is realization, never table semantics. Whole-lifetime
facts may choose regions/arenas.

## 30. Closures

Exact capture facts. No capture: environment 0. Constant capture:
specialize/fold. Nonescaping: register/stack. Escaping: heap only if required.
No parent-scope runtime lookup.

## 31. Packs + ABI

One semantic pack model. Physical packs materialize only if demanded. Multiple
returns may become registers, independent scalars, or an ABI aggregate only at a
necessary boundary.

Internal Idol ABI may specialize beyond the generic external C ABI. Foreign ABI
only at an actual foreign boundary. No tuple object by default.

## 32. Range / bounds / numeric facts

Preserve range, width, sign, overflow law, refinement, NaN/Inf possibility,
alignment through the graph.

Use them to eliminate bounds checks, overflow guards, widening, tags; and to
enable narrowing, SIMD, constant folding, branch pruning. Physical integer width
is not necessarily a semantic primitive identity.

## 33. Effects

Effects are structured facts, not merely pure/impure. Effects determine legality
of elimination, duplication, reordering, CSE, hoisting, fusion, vectorization,
parallelization, staging.

World/authority effects remain explicit graph facts even if source omits them.

## 34. Iteration / fusion

One iteration relation. No mandatory iterator object. Semantic chains
(map, filter, each, reduction) may fuse into one physical loop when facts permit.
No intermediate table merely because source is high-level.

FTCFTW requires high-level Idol to meet or beat handwritten loop realizations.

## 35. Hardware

CPU/SIMD/GPU are realizations, never semantic relation kingdoms. The semantic
graph remains target-independent where meaning is target-independent.

Realization uses shape, stride, alignment, alias, reduction law, effects, target
capabilities to choose hardware. No target-specific relation identity unless
semantics genuinely differ.

## 36. Coroutines / concurrency

Lua coroutine semantics remain. Realization may collapse: never suspends →
ordinary function; nonescaping suspension → compact stack/state; general
coroutine → runtime state. No coroutine runtime linked if unused.

Concurrency realization derives from isolation, ownership, mutation, alias,
blocking, effect independence, ordering. No mandatory scheduler for ordinary
programs.

## 37. Strings

One semantic text model may realize as static literal, borrowed view, slice +
length, inline small value, owned buffer, or other representation if demanded.

Interpolation publishes an ordered formatted-text segment pack: literal
segment, expression value, literal segment. It does not semantically publish a
concatenation chain or demand materialization. Concatenation, exact-size
materialization, direct sink formatting, scatter/gather output, constant
folding, and erasure are realization candidates. Retired `..` input is not the
semantic concat relation. Do not turn text convenience into automatic heap
allocation.

## 38. Metatables

Preserve Lua metatable semantics. Metamethods resolve through ordinary
relation/application facts.

Unknown metatable: dynamic. Known stable metatable: exact target. Sealed:
direct/inlined. Provably unused: machinery 0. No separate metamethod compiler
kingdom.

## 39. Transformations

One transformation model covers fold, specialize, inline, fuse, vectorize,
stage, eliminate, lower.

Every transformation records input ids, prerequisite facts, produced facts,
eliminated alternatives, lineage/provenance. No independent rewrite-language
kingdoms.

## 40. Compile time

Compile-time execution uses ordinary Idol semantics under world/stage facts. No
separate compile-time language.

Staged results retain exact dependencies. Cache by semantic dependencies, not
source spelling. Change one dependency: invalidate the exact dependent closure.
No file-wide recompilation merely because a file changed.

## 41. Native backend

Destination: graph → demand → realization → instruction → object.

Direct native is the canonical default, self-host, release, correctness, and
performance path. It never emits C, invokes a C compiler, depends on a C
artifact, or falls back to C.

Generated C is also a lawful, explicit, orthogonal physical realization when it
consumes the same graph facts. It is never semantic authority, never selected by
`auto`, and never supplies missing facts or evidence for direct native. No
semantic feature may require it exclusively. The `c` foreign world is a separate
interop capability and does not select the C backend.

Every backend refusal names application id, missing fact, expected producer,
consumer/cause. Crashes: P0, target 0.

Idol never lowers away semantic information merely because a conventional
compiler phase no longer knows how to represent it. Semantic identity persists
to the final machine decision; representation is chosen once, as late as
profitable, from exact demand, effects, alias, shape, world, and target. There
is no irreversible semantic cliff between the application graph and machine
code, and one authoritative graph carries sparse realization overlays rather
than a chain of separately materialized IRs (`law.realization.late`).

The opportunity is to arrive at machine code with more exact knowledge than a
conventional lowered IR retains, then use it to avoid creating the allocations,
memory objects, aliases, generic ABIs, temporaries, dynamic calls, and runtime
abstractions a conventional backend must later struggle to remove. Twelve
central claims each bind a named law:

1. Semantic-late lowering — meaning survives to machine realization (`law.realization.late`).
2. Representation-one — width, layout, register/stack/heap, and ABI chosen together from demand (`law.representation.one`).
3. Application-specific ABI — closed-world internal calls need not obey a generic ABI (`law.abi.internal`).
4. Place-on-demand — a place exists only when observable storage is demanded (§29; `law.alias.provenance`).
5. Semantic alias provenance — preserve place disjointness instead of reconstructing pointer aliasing (`law.alias.provenance`).
6. Bufferization-on-demand — table, array, and text chains stay virtual until materialization is necessary (`law.buffer.demand`).
7. One vectorization algebra — loop, structurally-similar-application, reduction, fusion, and parallelism from one graph (`law.vector.one`).
8. World specialization — sealed world and witness facts specialize away runtime context and authority checks (`law.world.closed`, `law.world.capability`).
9. Application-level linking and incrementality — no module or file grain after ingestion (`law.link.semantic`).
10. Verified realization search — aggressive local machine rewrites carry a translation-validation witness (`law.realization.valid`).
11. Causal cost accounting — every physical cost names the unresolved semantic fact requiring it (§26; `law.cost.explain`).
12. Semantic lower-bound evidence — measure against the semantic minimum, the best C/Fortran/LLVM result, and the current Idol result (`law.lower.bound`).

No machine or lowering stage may ask whether a value was a function, a table, a
callee spelling, or an AST node — it consumes the resolved application facts
(`law.application.consumer`). The detailed opportunity catalogue and the four
vertical FTCFTW kernels that prove the architecture are the realization
obligation, not more source syntax (`docs/performance.md`; `gaps/GAP-169.md`).

## 42. Register / stack realization

Semantic ids are not physical stack offsets. Spill layout belongs to
realization. Only values that are live across a call AND stored in clobbered
registers need spilling. No "spill every local on every call" endpoint. Internal
calls may use specialized clobber/ABI knowledge.

## 43. Wasm

Same semantic graph as native. No separate Wasm language/semantic pipeline.
Target realization specializes imports, exports, memory, calls, initialization,
metadata, runtime support.

Benchmark separately against pinned Wasmtime: load/parse, validation/compile,
instantiate, startup/first run, steady runtime, memory, artifact bytes. No
vanity combined score.

## 44. Runtime / link / startup

Whole-program demand/reachability eliminates unused GC, scheduler, coroutine
runtime, dynamic table machinery, reflection, descriptors, world machinery,
generic conversion, unused foreign bridges.

Sealed CLI ideal: OS loader → entry code. The compiler carries semantic
reachability through object/link selection.

## 45. FFI

Foreign representation exists only at the boundary:

    Idol semantic value
    → required ABI projection
    → foreign application
    → result projection

No global C-value/FFI-value semantic kingdom. Foreign physical machinery gains
zero semantic authority.

## 46. LSP + MCP

LSP and MCP consume the same semantic graph. No independent semantic model.
Hover/completion/navigation/refactor/diagnostics query exact ids.

MCP becomes the agent semantic API: entity, relation, application, demand,
provenance, realization, cause. Agents should increasingly query graph facts
instead of grep source.

## 47. Gates

Gate stack: lexical regex, path/filename lexical checks, syntax checks,
semantic-role classification, graph invariants, adversarial controls.

Two permanent metrics: new debt = 0; total existing debt monotonically → 0.

Regex enforces lexical impossibility. Graph/semantic gates enforce semantic
impossibility. Do not use regex as final semantic authority.

## 48. Graph sovereignty

The final semantic graph must contain Idol ids/facts; not mirror host AST
ontology; not depend on host tags for semantic validity; not recover meaning
through AST pointers; not store target realization candidates in the semantic
core; not store freeform prose as facts; not conflate unknown and absent; not
carry generic sparse god-record fields; not use paths/names to recover meaning.

AST/sema/host types project INTO the graph during bootstrap.
Demand/optimization/realization consume FROM it. Eventually the graph core does
not import host AST/sema/transform machinery to define its ontology.

## 49. Evidence

Every performance claim binds: measured revision, evidence revision, dirty
state, input, expected semantic result, actual result, target, CPU/features,
competitor version, compiler mode, sample count, variance, compile time,
startup, runtime, memory, artifact size.

Measured program revision ≠ evidence commit revision. No current-subject
measurement: no current performance claim.

Positive damage controls: force allocation, force indirect call, force hash,
force copy, force startup delay, pad artifact. The metric must worsen. If not:
evidence invalid.

## 50. SHC

Self-hosting is EXECUTED SEMANTIC AUTHORITY TRANSFER. Not `.id` percentage.

Target chain: source family → lexical identity → grammar roles → parser facts →
binding/resolution → graph → demand → realization → machine → object/link.

Each transferred producer: new Idol authority executes; old host semantic
producer disabled/sabotaged; no fallback.

Compiler B: seed builds canonical Idol compiler source. Compiler C: B builds the
same source. Acceptance requires semantic/diagnostic/behavioral correspondence.

Reaching the earliest executed SHC frontier is the priority. A bounded foreign
bridge — including new Zig — that advances the executed authority frontier is
admitted and preferred over stalling when it is the fastest path to the next
transfer, provided it carries a deletion witness (`law.bridge.death`,
`law.bootstrap.velocity`). Foreign is forbidden only as permanent architecture,
as semantic authority, or as a new foreign semantic kingdom beside the graph —
never as bootstrap scaffolding toward the next native owner. Do not block on the
monoglot ideal where the native compiler cannot yet express a stage: mark
`IMPLEMENTATION-BLOCKED` and add the smallest unblocking bridge rather than idle.
Generated bridge artifacts are regenerated from their Idol owner, never
hand-forked.

## 51. Final source surface

Core forms:

    x = value

    add = (a, b) a + b

    table(key)

    subject:relation(args)

    x.y

    @

    @x                         # explicit world access, rarely needed (never @.x / @:x)

    thing@world

    @{ k = v }                 # derive world (injection)

    thing@{ k = v }            # interject a fact for a subtree

    @k = v                     # ambient world mutation, rare

    able(relation-shape)       # rarely explicit

    value:to(target)           # rarely explicit

The whole world algebra is four surfaces over one table mechanism —
`@x` access, `@{ k = v }` inject, `thing@world` qualify, `thing@{ k = v }`
interject — plus `@k = v` mutate. `@` is the accessor itself, so `@.x` and `@:x`
are invalid. Ordinary source stays `sale.quote(100)`; the
graph still records the exact quote id under the exact current world with exact
ambient projections, demand, target, and witness facts. Realization may then
collapse the entire world algebra: no runtime world allocation, table merge,
hash, lookup, closure environment, or protocol dictionary unless an independent
unresolved semantic reason requires it.

Everything else should be inferred where unique. The ideal Idol program
increasingly reads like the problem, while the graph contains everything the
machine needs.

## World + projection algebra (authoritative add-on)

This add-on is authoritative and part of the one-page law. Projection, injection,
and interjection are **not** three new subsystems — they are three uses of
ordinary world/table semantics:

- **projection** = select an exact fact/member
- **injection** = derive a world with explicit fact additions/replacements
- **interjection** = evaluate one subtree under such a derived world

No `inject`, `scope`, `context`, `provider`, `registry`, or dependency framework
is introduced.

### World and @

A world is an ordinary closed semantic table. `@` is the current world.

`@` is itself the accessor: `@name` accesses world member `name`. There is no
`@.` step and no `@:` dispatch — `@.member` and `@:member` are invalid. Bare
names may be inferred as static accesses of `@` when no lexical binding already
supplies the meaning: `tax(sum)` may resolve exactly as if written `@tax(sum)`.
The shorter form is canonical when unique. Explicit `@tax` is useful only when
the distinction matters — e.g. a lexical binding named `tax` shadows the ambient
world member.

A world can contain values, relations, descriptors, other worlds, stage/target
facts, and authority facts. A world is not itself an authority object; authority
is one class of fact inside it.

### `.` — one static step, always (strongest grammar invariant)

Every dot means exactly one statically known structural projection: one
filesystem child level, or one static member of a value/table. Nothing else.

    sale.quote            # sale → static member quote
    target.arm.feature    # three known values, two projections

`.` never means method lookup, extension lookup, dynamic dispatch, namespace
search, recursive lookup, world fallback, or parent lookup.

If the selected member is a callable value, `math.sin(x)` is static projection
then application. If `math` is instead the semantic subject of relation `sin`,
the relation form is `math:sin(x)`. These are not interchangeable.

`.` is never computed. When the key is runtime data use application `table(key)`,
never `table.key`.

### Filesystem algebra

The filesystem establishes the initial static world topology.

    market/
        main/
            lib.id        # root table body
            tax.id        # → @tax
            sale/
                quote.id  # → @sale.quote

`main/` is the physical source-root convention — not a language main, entry
function, namespace, or semantic identity. `lib` is not a semantic namespace;
user code never writes `lib.sale.quote`. The resulting root table is simply `@`.
Each `/` after the source root corresponds to exactly one static `.` projection.

After ingestion the filesystem has finished its semantic job: `path = provenance`,
`id/facts = authority`. No downstream component walks directories to rediscover
meaning.

### World qualification — `thing@world`

`thing@world` evaluates/resolves `thing` with `world` as the current world. The
entire expression is world-relative, not merely a name lookup:

    (sale.quote@trial)(100)   # evaluate sale.quote under trial, then apply

Inside `sale.quote`, bare `@` is now `trial`. Qualification is scoped to that
evaluated subtree; it does not mutate the caller's world.

**Dot after qualification:** `thing@world.member` means `(thing@world).member`.
For a nested world qualifier, write `thing@(world.member)`.

**Bare postfix `thing@`** means `thing` under the current world. Usually `thing`
already means the same and SOURCE-INFER-ONE removes the postfix `@`; it remains
useful to say "take the current-world definition of this thing as a value here."

### Injection — `@{ member = value }`

`@{ member = value }` derives a new closed world from the current world,
injecting/replacing exactly the stated static facts. This is not mutation.

    trial = @{
        tax = (sum) 0
    }

`trial` receives all current-world facts except its `tax` projection. `W` is
unchanged. The compiler may implement `W'` via structural sharing, persistent
tables, exact deltas, or by eliminating the derived world after specialization —
but semantically it is a **closed** world; resolution does not search `W'` then
fall back to `W`.

Injection algebra: `project(inject(w, k=v), k) = v`; for every untouched fact
`q`, `project(inject(w, k=v), q) = project(w, q)`. That equality is established
when the derived world is formed — not a runtime parent-world fallback. Empty
injection `@{}` is identity with `@` (and normally disappears). Injecting the
exact same fact is idempotent. Duplicate definitions in one injection literal are
an error (no declaration-order magic). Nested explicit injection replaces an
outer injection — explicit lexical/world shadowing, not "last-world-wins" search.

### Interjection — `thing@{ k = v }`

Interjection needs no new syntax; it is the scoped composition
`thing@(@{ k = v })`, with the dense canonical shorthand `thing@{ k = v }`:

    sale.quote@{
        tax = (sum) 0
    }(100)

executes `sale.quote(100)` under a derived version of the current world whose
`tax` fact is replaced. After the expression finishes the caller's world is
unchanged.

Compact surfaces, one mechanism:

    @x                access
    @{ x = v }        inject
    thing@world       qualify
    thing@{ x = v }   interject

### Ambient mutation — `@fee = 0`

`@fee = 0` accesses the static `fee` member of the current world as a place
and mutates it (legal only if that member/application can produce a place).
Ordinary table/place semantics — no special world-mutation API. Mutation is
persistent and every alias of the same world identity observes it. Prefer
interjection for scoped replacement; mutate the ambient world only when the
mutation itself is meaningful.

A derived (injected) world is a distinct world: mutating `trial.fee` mutates
`trial`, not the root. Structural sharing may exist physically but must preserve
this distinction — `derived world ≠ alias of source world` unless alias identity
was explicitly established.

### Lexical scope vs world scope

Lexical binding wins for a bare lexical name; `@tax` explicitly accesses the
current-world member. There is no ambiguous search/fallback chain — the resolver
sees the closed lexical + world fact set once and records exact ids. After that:
no lexical search, no world search, no parent search.

### World propagation (semantic threading, zero runtime object)

A world-qualified application propagates its current world through unresolved
ambient dependencies in that evaluation subtree. This is semantic world
threading — it does not imply a runtime World object argument. When everything is
statically known: world object = 0, lookup = 0, dispatch = 0. The graph merely
records the exact facts selected from that world.

### able(...) and worlds

`able(read)` proves semantic applicability; it does not prove execution
authority. A concrete `source:read()` may additionally demand a witness from the
current world. Injecting a world cannot fabricate authority by naming it —
`@{ authority = true }` is void because a boolean is not a valid witness. An
injected authority fact must itself be an exact valid semantic witness, and the
compiler checks satisfaction:

    job@{ witness = permit }()   # runs only if permit satisfies the demanded authority

World injection modifies fact availability; it never bypasses satisfaction.

A reusable descriptor may legitimately expose an explicit contract:

    key = {
        able(eq)
        able(hash)
    }

because the descriptor is itself the boundary contract. Even then the compiler
may represent it as demanded relation facts, not an `able` object. If a use
establishes the requirement in its body, infer it — do not spell `able` unless
the boundary itself must communicate the requirement.

### Closures capture the smallest exact world fact

A closure does not automatically heap-capture an entire world. The semantic
dependency of `(sum) sum + fee` is the exact `fee` fact, not the whole `@`. If
`fee` is statically known the closure specializes it away; if dynamic, capture
the smallest exact necessary world fact. Only if world identity itself is
observably required is the whole world value captured. Ambient world ≠ automatic
giant closure environment.

### Use cases are worlds, not bespoke machinery

Deterministic clocks, tests, build targets, native/Wasm differences, locale
policy, feature experiments, filesystem authority, transactions, staged
compilation, hardware specialization, agent execution, simulation, and
reproducible builds are all **derived worlds** — not `Mock`, `Environment`,
`DependencyContainer`, `CapabilitySet`, `BuildContext`, or `TargetContext`. Stage
is a world fact, not a second language; target facts influence realization
without changing relation identity.

### Naming add-on for worlds and filesystem

Do not create names that merely encode the fact being injected: `testworld`,
`mockclock`, `fakeclock`, `prodworld`, `runtimecontext`, `buildcontext`,
`targetcontext`, `worldprovider`, `worldmanager`, `dependencycontainer`,
`capabilityset`, `taxfree`, `zerotax`. The world already carries the qualifying
fact — prefer a genuine domain scenario world like `trial`, and inside it
`@{ tax = ... }` / `@{ clock = ... }`, never a new identity `notax` / `mockclock`.
A name survives only if it is an independently meaningful thing; world
differences belong to world facts.

Avoid organizational directories (`utils/`, `helpers/`, `services/`, `models/`,
`handlers/`, `providers/`, `common/`, `shared/`, `core/`, `internal/`,
`modules/`). Prefer paths where each segment is an actual projected table/entity
(`sale/quote.id`, `target/arm.id`). A directory is not a category bucket; it is a
static table.

### Projection/injection optimization law

The graph remains maximally explicit even when source is tiny. For
`sale.quote@{ tax = (sum) 0 }(100)` the compiler may know the application, the
derived world `W1` from `W0`, exact `tax`/`fee` projections, numeric result
demand, absent effect/authority, and native target — then realization collapses
the entire world algebra. A source-level derived world does NOT imply runtime
world allocation, table merge, hash, world lookup, closure allocation, or
protocol dictionary. Any of those requires an independent unresolved semantic
reason (§26 FTCFTW cost law).

### Final algebra

    @                 current world
    @x                access world member x (@ is the accessor; never @.x / @:x)
    x.y               one static projection
    x(args)           application
    x:y(args)         subject-oriented relation
    x@w               evaluate x under world w
    @{ k = v }        derive current world with exact injected fact
    x@{ k = v }       interject fact for x's evaluation subtree
    @k = v            mutate a world member place
    able(r)           explicit requirement boundary, normally inferred

SOURCE-INFER-ONE compresses further. Ordinary Idol mostly reads `sale.quote(100)`
while the graph understands the exact quote id, current world, ambient tax/fee
projections, inferred constraints, demand, and target/witness facts. The
programmer reaches for `@`, `@member`, `@{}`, `thing@world`, and `able(...)` only when
the world or boundary distinction itself is meaningful.

## 52. Refinement selection (no match kingdom)

There is no `match`, `case`, `switch`, or pattern-object subsystem. `if`
generalizes into refinement selection over the already-evaluated subject:

    label = (value)
        if value
            nil          "missing"
            0            "zero"
            n: i64       "integer {n}"
            p: point     "{p.x}, {p.y}"
            red          "red"
            else         "other"

Branch heads are constraints on the subject, not patterns: exact-value
refinement (`nil`, `0`), descriptor satisfaction + ordinary binding (`n: i64`),
exact semantic identity (`red`), remaining possibility set (`else`). The subject
evaluates exactly once; a branch binding re-binds the refined value, never copies
it.

Multi-arm refinement is semantically unordered. If two arms can both lawfully
satisfy the same remaining value and are not proven disjoint, that is an
ambiguity error — no first-match, most-specific, declaration-order, or trait
precedence. Ordered testing uses ordinary nested `if`. Guards use nested `if`,
not pattern guards. No destructuring-pattern syntax — `p: point` already makes
`p.x`/`p.y` exact static projections.

Exhaustiveness: if the result is demanded, either the compiler proves the arms
exhaust the possibility set or `else` is required; if undemanded, a nonmatching
remainder runs no body (ordinary conditional behavior). Realization turns the
refinement set into zero branches, compare chains, jump tables, bit/range tests,
or tag-free specialization.

## 53. Possibility algebra

A value is not fundamentally "dynamic" or "static": the compiler holds a set of
remaining semantic possibilities, and facts monotonically remove them.

    unknown → observed facts → descriptor constraints → world constraints
    → control-flow refinement → application resolution → sealed possibility
    → realization

Descriptor checking, `if` refinement, `able(...)`, union alternatives, nil
refinement, guard insertion, call specialization, conversion inference, shape
specialization, and target selection are one mechanism. A union is not a
kingdom — it is more than one remaining admissible alternative. A guard exists
only when a profitable realization assumes one of several remaining
possibilities.

## 54. @{} is world injection only; descriptors are plain tables

`@{ … }` belongs exclusively to world derivation/injection (§5c). A descriptor
is an ordinary table whose values are descriptor constraints — no descriptor
sigil:

    point = {
        x: f64
        y: f64
    }

`point = @{ x: f64, y: f64 }` for descriptor construction is retired. Strengthen
tables; do not add a type kingdom. Separately, `@{ … }` is never an import or
dependency list — usage derives dependencies, so `@{ os.env io.stdout }` bare-name
manifests remain forbidden; injection carries explicit `k = v` fact deltas.

## 55. Evaluation order

Observable evaluation is left-to-right. `f(a(), b(), c())` observes `a`, then
`b`, then `c`, then `f`. Static projection evaluates its subject first. World
qualification evaluates the world expression before the qualified subtree.
Injection evaluates injected values in lexical source order; duplicate keys are
invalid. The compiler may reorder only when graph effect facts prove
observational equivalence. Strong source semantics plus proven reordering beats
vague source semantics.

## 56. Truth

`false` and `nil` are false; everything else is true. `and`/`or` preserve Lua's
operand-returning semantics. The graph records the truth refinement; it does not
insert conversion-to-bool operations.

## 57. Packs and multiple returns

Multiple returns are semantic packs, not tuples. One pack algebra owns adjustment
for `f(g())`, `a, b = f()`, `h(x, f())`, `return f()`: whether a pack expands,
how many slots are demanded, first-result-only consumption, how parentheses
truncate demand, how varargs combine, how tail returns forward packs. Parser,
graph, and backend share this one algebra. Unused pack slots become literally
nonexistent. No tuple object by default.

## 58. Varargs are packs

No separate varargs object. An open operand pack is a pack whose cardinality is
not yet sealed; `f = (…) …` is the same mechanism as multiple returns. Known
cardinality → registers/scalars; unknown → general realization; no mandatory
array allocation.

## 59. Failure is an outcome alternative

No exceptions, `Result` kingdom, error protocol, `throws` declaration, or
try/catch hierarchy. An application produces a normal result pack or a failure
outcome — both graph facts — refined by ordinary control flow. Cold failure
paths separate physically; hot success paths stay unboxed; static impossibility
removes error machinery. Compact propagation syntax is postponed; the semantic
model matters more than whether it later gets `?`. Do not self-host a Result or
exception architecture to get the compiler working.

## 60. Identity and equality

Ordinary Lua table equality preserves identity semantics by default. An `eq`
relation may supply semantic equality for descriptors that define it; `hash` must
be compatible with the selected `eq`; structural equality is not implied by
shape. Specialization eliminates identity machinery only when identity is
provably unobservable. Semantic, identity, structural equality, ordering, and
hash compatibility are distinct facts.

## 61. Iteration order

A table has an iteration relation whose ordering fact may be unordered, ordinal,
insertion, or sorted-by-relation. Never promise hash-layout order by accident. If
order is unobservable, realization has maximum freedom; if program semantics
demand order, that becomes an application fact — not a permanent representation
choice.

## 62. Numeric law

Fully defined before any FTCFTW claim: signed/unsigned overflow, division by
zero, modulo sign, shifts ≥ width, narrowing, float→integer conversion, NaN
equality, signed zero, infinities, float contraction/FMA, reassociation,
denormals. Bias toward semantics that map efficiently to hardware while remaining
deterministic. Ordinary integer arithmetic has no C-style undefined behavior.
Stronger arithmetic behavior uses distinct relations/facts, never a global
compiler mode.

## 63. No undefined behavior

Idol requires no semantic undefined behavior to optimize aggressively.
Optimization comes from exact alias, world, shape, demand, range, descriptor,
application, effect, and lifetime facts. Unknown behavior remains unknown; proven
facts enable optimization. (Agent-generated software depends on this.)

## 64. Concurrency memory law

Isolated mutable state by default. Crossing an isolation boundary is explicit
semantic transfer. A shared mutable place requires an exact sharing/
synchronization fact. Data races are rejected or given defined semantics, never
C-like UB. Atomic ordering is an application/effect fact. The compiler reorders
only when effect/alias/order facts permit. No async/await kingdom — suspension/
blocking is an effect/realization fact; a call may realize synchronously, as
evented I/O, on another thread, or as a direct syscall without changing source
when semantics permit.

## 65. Unsafe is a world capability

Raw memory, privileged instructions, syscalls, and unchecked foreign access
require exact authority witnesses in the current world. No `unsafe { … }`
kingdom — evaluate under a world that contains the required witness. Statically
known authority costs zero runtime checks; the compiler still knows exactly which
applications require it.

## 66. World attenuation

World derivation must express removal, not only add/replace. Because
nil-as-value and absent-member are distinct (§15, FACT-CARDINALITY-ONE),
attenuation states a projection is **known absent**, not `net = nil`. A derived
worker world can be "everything except filesystem/network authority" without any
capability API — attenuation is an explicit absence fact in the world algebra.

## 67. World mutation and alias law

Injection creates a distinct world identity. Unchanged immutable values may
structurally share. Mutable places do not implicitly alias unless exact place
identity is injected. `@k = v` mutation is persistent and observable; world
identity survives mutation. Scoped replacement uses interjection, not mutation or
rollback tricks. Whether `@` may be rebound, and concurrency visibility, follow
§64.

## 68. Compile-time generation and hygiene by id

Compile-time execution uses ordinary Idol semantics under world/stage facts (§40)
— no separate compile-time language and no macro hygiene subsystem. Generated
facts reference exact semantic ids, so hygiene follows from identity + provenance
+ world, never token renaming. Generation should produce descriptors, tables,
relations, applications, and graph facts — not source strings; emitted source
text re-enters lexical/grammar ingestion with explicit generated provenance.

## 69. Reflection is ordinary semantic access

Descriptors, relations, worlds, and semantic graph values are ordinary values at
stages where they are available — projected/applied/iterated like any value. No
`@reflect`, `reflect.*`, or embedded compiler-object API. Reflection access can
disappear completely after staging/demand.

## 70. Cross-build correspondence, not StableId

Incremental builds, hot reload, debugging, and B/C bootstrap model correspondence
as a witnessed relation between two ids across graph incarnations — id A in G1
corresponds-to id B in G2 because exact provenance/facts satisfy witness W — not
an intrinsic eternal identifier. No second identity system.

## 71. Packages are world construction

No import/package namespace kingdom. A package is an independently built/admitted
source world/table; the build resolves dependencies into the project root world.
Version, source hash, and signature are provenance facts; the program sees
ordinary projections. A lockfile defines dependency source, revision, integrity,
and world projection name — none becomes semantic module identity.

## 72. Reproducible builds from sealed worlds

A sealed build world contains exact facts for source graph, dependency revisions,
target, environment inputs, generated inputs, feature facts, and compiler
revision. Time, random, environment, and filesystem influences are explicit world
effects. Same source facts + same sealed build world → same semantic graph.
Physical output determinism is a separately measurable realization property.

## 73. Clock / random / environment are world facts

`clock`, random source, environment, and process context are world facts/
relations — never ambient globals. Tests interject deterministic versions
(`job@{ clock = fixed }()`); static deterministic execution eliminates the runtime
abstraction. Testing, simulation, and reproducibility are one mechanism.

## 74. Resource budgets are world facts

Memory budget, CPU/time budget, stack limit, allocation policy, cancellation, and
network policy inhabit a world; code needs no different API. Known-irrelevant
budgets → checks disappear; enforced budgets → realization inserts the machinery.

## 75. Cancellation is an effect/world fact

Cancellation is an effect/world obligation, not async syntax. An application that
can suspend may consume a cancellation fact from its world. No demand → no token,
no polling, no branch. Demanded → realization inserts checks at legal suspension/
interruption points.

## 76. Finalizers / weak tables / GC

Freeze Lua semantics before aggressive escape analysis ships: when finalizers may
execute, whether ordering is observable, resurrection, weak-key/value
reachability, interaction with region/stack allocation, and whether finalizable
identity forbids scalar replacement. Observable lifetime/finalization facts
constrain realization; otherwise GC machinery is unnecessary.

## 77. Metamethod precedence is one relation law

All operators and metatable hooks normalize to relation resolution — arithmetic,
comparison, length, indexing, assignment, iteration, call. No backend-specific
"try lhs metatable then rhs metatable" logic; the graph resolver owns the exact
application target. Operator punctuation is provenance.

## 78. Operators are relation resolution

`a + b` and the corresponding relation application resolve to the same relation
identity. Precedence is grammar; meaning is relation resolution. Generated code,
operator syntax, and explicit relation calls converge before optimization. No
second generic system.

## 79. Tail calls

Tail position is a semantic/demand fact. Idol preserves proper tail-call
semantics (Lua heritage); direct native honors them where required. Recursive
state machines depend on it.

## 80. Debugging without forced materialization

A debugger can ask "what is value id X here?" even when X was scalarized, folded,
register-only, or fused away — reconstructed via provenance + realization
lineage. Do not keep values boxed for debugging. A debug build may demand extra
materialization as a realization policy; debugging never infects semantic
architecture.

## 81. Profiling is evidence, never truth

Profile facts (hot edge, likely target, common shape) may influence realization
but never change meaning. A profile-guided guard retains a correct recovery path.
No PGO result becomes semantic authority (`law.profile.evidence`).

## 82. Capability-secure worlds

Unforgeable authority witnesses are ordinary world facts: code receives exactly
the authority its current world contains; derived worlds attenuate it (§66);
static proof removes runtime capability lookup; agents run under restricted
worlds; tests replace implementations without acquiring production authority.
Ordinary source must not construct an authority witness merely from knowing its
descriptor/name — witness forgery is impossible.

## 83. FFI provenance / ownership / callback law

Beyond ABI layout (§45), FFI specifies as facts: who owns returned memory,
whether foreign pointers may escape, callback lifetime, thread affinity, foreign
mutation, aliasing, exception/longjmp interaction, errno/thread-local state, and
signal safety. FFI is not "convert args and call C."

## 84. Signals / processes / files are world effects

Process creation, signals, files, sockets, environment, terminal, and clocks are
world effects — subject + relation + witness. No `os`/`io` library kingdom. This
is where the `std.os.read_line`-style disaster disappears.

## 85. Incremental identity is application-level

Do not invalidate modules or whole functions by default. Facts form exact
dependency edges; changing one descriptor field invalidates only the applications
whose resolution/demand/realization depended on that fact.

## 86. Compiler queries are pure projections

MCP/LSP/debugger/compiler-internal queries never mutate semantic state; any cache
is a physical derived index. Query order never affects compilation.

## 87. Deterministic graph construction

Equivalent input under equivalent world facts yields semantically corresponding
graph facts regardless of hash iteration order, thread scheduling, allocation
addresses, or filesystem enumeration order. Physical ids may differ if an exact
correspondence witness exists; prefer deterministic dense allocation where easy
to simplify B/C proof and caching. Test this adversarially.

## 88. Optimization is translation-validated

Each transformation emits/checks a local witness: input facts, transformation,
output facts, preserved observations. Difficult optimizations validate the result
against the pre-transform semantic slice. A mechanically self-checking optimizer
is a differentiator — especially for agent-written optimizations.

## 89. Semantic cost accounting

Extend cost-explain: each application accumulates a cost vector — alloc, copy,
hash, branch, indirect, box, load, store, spill, sync, runtime support, code
bytes — and every nonzero component links to an unresolved fact. The compiler
answers "why isn't this the theoretical minimum?" This is an MCP primitive.

## 90. Theoretical lower-bound comparator

FTCFTW compares against three, not one: semantic lower bound (minimum memory
traffic, allocations, dynamic dispatch, passes, required branches/sync), C
baseline, and Idol actual. The lower bound proves when further optimization is
physically impossible and prevents benchmark gaming.

## 91. Compile-time FTCFTW

Compile speed has equal status to runtime. Track bytes scanned, graph
entities/facts per source token, allocations per entity, hash lookups, full-edge
scans, incremental invalidation count, peak compiler RSS, object-writer
throughput. A brilliant binary that costs 30× clang to compile fails the
ambition. (Current host-shaped nullable graph record and AST coupling are the
open blockers.)

## 92. Binary-size FTCFTW causality

Every retained runtime symbol/section names the demanded application that reaches
it; none reaching → dead section. Covers generic table runtime, GC, formatting,
reflection, world machinery, unwinding, coroutine runtime. Whole-program semantic
reachability beats symbol reachability.

## 93. Startup zero-initialization

Static world/descriptor facts become immediates, readonly data, relocations, and
compile-time constants — not runtime registration. No descriptor registry init,
module init graph, world service startup, or dynamic builtin registration. Sealed
program model: loader → demanded computation.

## 94. Source topology dangers

Plural/organizational identities (`bytes`, `strings`, `collections`) are
classified, never mechanically renamed: if canonical they violate cardinality/
organizational law; if foreign/transitional they carry a deletion schedule.
`lib/` is bootstrap filesystem provenance, not permanent semantic architecture —
do not let `lib/everything` become the new `std/`. Long-term topology is actual
semantic tables/homes.

## 95. Inferred facts stay inspectable

Invisible source syntax never means invisible semantics. LSP hover / MCP expose
every inferred requirement, conversion, world, witness, capture, effect, and
descriptor — an agent can always ask "what did the compiler infer?"

## 96. World inference stays closed

Ambient world resolution is closed: at an application site only the exact current
world + lexical environment are consulted. The compiler never searches parent
packages, a global registry, all reachable worlds, or installed dependencies. If
several world projections satisfy a bare name/relation, that is ambiguity — no
"nearest" magic beyond the defined lexical binding rules.

## 97. Frozen vocabulary and the closure test

The semantic vocabulary is frozen:

    id · fact · binding · table · descriptor · world · projection · application
    · relation · pack · place · refinement · demand · effect · witness · stage
    · provenance · transformation · realization

plus `able(...)` as explicit constraint spelling. Every proposed feature must
prove it cannot already reduce to one of those (or to identity, static
projection, world qualification, injection/interjection, or an `able`
constraint). If it can reduce, it is not introduced. Most future work makes the
compiler know more, not the syntax know more.

## 98. FTCFTW-DOMINANCE

For every program, target, world, workload, policy, and observable semantics
under comparison, Idol searches for the least-cost lawful realization. Against
the strongest semantically equivalent external implementation it must strictly
improve every cost dimension where improvement is physically possible, equal the
proven lower bound where improvement is impossible, and never lose without naming
the exact tradeoff or unresolved fact responsible.

The opponent is `BEST KNOWN IMPLEMENTATION + SEMANTIC/PHYSICAL LOWER BOUND`, not
one compiler. Objectives genuinely conflict (throughput ↔ size, specialization ↔
compile time, prefetch ↔ memory traffic/energy), so FTCFTW is a Pareto-dominance
requirement, never a scalar score: Idol's achievable frontier must dominate the
comparison frontier everywhere the semantics permit.

Target policy is an explicit build-world fact (§74) — same semantic program, no
source change — expressed as an objective under budgets: minimize latency under
100 KiB; minimize size under latency ≤ X; minimize compile time under runtime ≤
X; minimize energy under throughput ≥ X. Idol finds the best lawful realization
for that policy.

The canonical acceptance inequality, for each comparable workload P, target T,
world W, policy Q, competitor set C:

    IdolCost(P,T,W,Q) Pareto-dominates BestKnownCost(C,P,T,W,Q)

unless the competing point is already on a proven semantic/physical lower bound,
in which case Idol must reach the same bound. Failure sets FTCFTW status OPEN;
no rhetorical exception.

FTCFTW spans the whole lifecycle, not only inner loops: edit, incremental
analysis, compile, link, load, relocation, startup, warmup, first result, steady
state, tail latency, footprint, shutdown, distribution — and for Wasm also
download bytes, decode, validate, compile, instantiate, initialize, first call,
steady state, RSS. A binary 2% faster that compiles 30× slower and is 5× larger
is not dominance. The Idol compiler obeys this same contract on itself
(self-hosting makes it recursively testable).

## 99. OPTIMIZATION-OPEN

There is NO closed optimization taxonomy. Named passes — inlining, SROA, GVN,
LICM, SLP, loop vectorization, DSE, tail-call — are merely known instances of one
general problem: over a semantic region, derive proven-equivalent realizations
reachable within budget and choose `argmin cost(r, target, world, policy)`. The
compiler reasons in semantic equivalence, remaining possibility, demand,
observation, target, and cost — never "which pass recognizes this pattern."

Any present or future semantics-preserving transformation, representation,
algorithm, schedule, layout, ABI, staging choice, hardware mapping, or machine
sequence is admissible. Candidates may originate from deterministic rewrite,
equality saturation / equivalence graphs, constraint/DP solving, enumerative
superoptimization, autotuning, profiles, hardware-in-the-loop measurement,
learned search models, agents, humans, competitor-binary mining, or methods not
yet invented. These are physical search strategies, not semantic kingdoms;
learned models and profiles are evidence, never authority (§81).

VERIFIED-OPTIMIZATION-ONE: search may be experimental; the accepted result may
never be semantically speculative. A candidate becomes canonical only when its
required observations are verified (translation validation for machine regions,
algebraic law where it applies — §88) AND it improves the selected cost frontier.
Correctness never relies on trusting a transformation.

Every improvement ultimately eliminates one of four things: WORK (instruction,
branch, call, check, hash, conversion, calculation), MOVEMENT (load, store, copy,
spill, allocation, serialization, syscall, traversal), REPRESENTATION (box, tag,
object, descriptor, world object, closure environment, iterator, pack, pointer),
or UNCERTAINTY (guard, indirect target, runtime lookup, alias/bounds check,
dynamic dispatch). Any future unnamed optimization must reduce to one of these.

Completeness is a moving frontier: closure is provable only for a bounded region
and search domain (e.g. 7 pure integer ops, arm64, candidate length ≤ 5 →
exhaustive search → SEARCH-CLOSED under the stated bound). For larger programs,
report proved lower bound, best realization found, remaining gap, and search
coverage — a stronger position than pretending global completeness.

The architecture follows: NOT `parser → IR → fixed list of optimization passes
→ backend`, but `source → semantic graph (identities, worlds, applications,
possibility sets, effects, demand, lifetime, alias, provenance) → equivalence/
realization space (transformations, algorithms, layouts, ABIs, instruction
forms, schedules, placements) → verification (observations preserved) →
multiobjective cost search (hardware + profile + build policy) → Pareto frontier
→ selected realization → machine/object`. Passes are not the ontology; the
searched, verified, cost-ranked realization space is.

## 100. COST-CLOSURE

Every remaining physical cost is a graph fact carrying: exact semantic cause,
theoretical lower bound, actual measured cost, and optimization-debt delta
(§26, §89, §90). Derive each hot application's theoretical zero vector (its cost
under complete knowledge); `actual − lower_bound = optimization debt`. This
yields a mechanical FTCFTW backlog agents query ("show greatest weighted
optimization debt") instead of recalling a curated pass list. Unexplained cost
is a compiler defect.

Competitors and hardware are continuous discovery systems: compile equivalent
source under the strongest competitor configuration, measure, inspect machine
behavior, map any competitor advantage back to an Idol semantic opportunity, and
add a regression oracle; and directly explore verified realizations on the actual
target to discover wins no compared compiler generates (idioms, unrolling,
prefetch, vector width, alignment, addressing, branchless forms, cache blocking).

A benchmark is CLOSED only when Idol either dominates every compared
implementation or reaches a proven lower bound. No benchmark win elsewhere and no
geometric mean compensates for an open loss: if 99 benchmarks win and one loses
where improvement is possible, FTCFTW remains OPEN for that case. This makes the
goal genuinely adversarial and verifiable.

## 101. ALGORITHM-REALIZATION-ONE

Algorithm and data-structure choice are realization, not source commitment, when
semantics do not mandate them. Preserving the specified observations, the
compiler may choose a fundamentally better algorithm (linear lookup → binary
search → perfect hash; comparison sort → counting/radix from range facts; generic
matrix multiply → tiled/vector/GPU; repeated parse → compiled parser; generic
regex → DFA; generic table → direct switch) and may change asymptotic complexity
(O(n)→O(1), O(n log n)→O(n), repeated O(n) → one indexed preprocessing step).
This is optimization space C usually lacks, because C commits algorithm in
source.

The same `table` semantics may realize as hash table, sorted vector, B-tree,
direct array, perfect hash, trie, bitmap, bitset, struct, SoA, scalarized
registers, or nothing (§14 shapes, §25 representation). Idol compiles semantic
data structures, not programmer-selected physical containers.

Realization is demand-directed (§24): `text:parse(json)` feeding only
`document.user.name` need not build a full object tree — scan just enough to find
`user.name`, allocate nothing else. This applies to parsers, encoders, queries,
transforms, files, protocols, reflection, and math.

Optimization boundaries are only semantic — observable effects, authority
boundary, foreign ABI, unknown dynamic world, resource policy, or search budget —
never function, file, module, package, or library. An abstraction that is only
organizational costs zero; if 15 functions collapse into one loop or 20 tables
disappear, good. Dynamic programs specialize progressively along
unknown → observed → guarded → sealed with correct deopt (§27, §53, §81);
multi-version only when expected benefit × frequency exceeds compile + code-byte
+ I-cache + dispatch cost, so specialization is itself FTCFTW.

## 102. PHYSICAL-SPACE-OPEN

REALIZATION means any physically observable strategy that preserves the
program's semantic observations — not merely machine representation and code
generation. The FTCFTW optimizer is a semantic-to-physical realization optimizer,
not a code optimizer. No compiler phase, backend convention, runtime abstraction,
ABI, operating-system interface, data structure, algorithm, device, or currently
known optimization defines the boundary of Idol's realization space.

A physical strategy is admissible when: semantic observations are preserved;
authority/effect constraints are satisfied; target/world constraints admit it;
AND the selected cost frontier improves (§98–§100, C0 `law.physical.open`). The
realization search includes, and is not limited to: computation, representation,
algorithm, data structure, encoding, layout, precision, memory placement and
tier, allocation, instruction selection, scheduling, ABI, linking, OS interface,
syscall strategy, concurrency, hardware placement, specialization, persistence,
and distribution. Unknown future physical strategies are admitted by the same
rule.

Concretely this admits, when lawful and cost-justified: entropy-driven
representation and compression; bit-level logic synthesis (SWAR, bitmanip,
vector masks, table synthesis); precision-proportional-to-demand and
range-specialized transcendentals; polyhedral/affine schedule search and sparse
iteration; distribution-sensitive and adaptively-switched algorithms; cross-run
persistent specialization and AOT/JIT-hybrid realization; snapshot/preinitialized
executable state; page-fault, huge-page, TLB, cache-set, uop-cache,
macro/micro-fusion, branch-predictor/BTB, and speculation-window realization;
thermal/DVFS/heterogeneous-core/SMT/NUMA/bandwidth-aware placement;
recompute-vs-store and automatic memoization; prefetch and
non-temporal/write-combining synthesis; kernel-crossing elimination and
interface selection (mmap, sendfile/splice, io_uring, vectored I/O); kernel and
network zero-copy and protocol fusion; accelerator instructions beyond SIMD
(AMX/SVE/SME/crypto/CRC/dot-product) and GPU/NPU/DSP realization with complete
transfer/launch/sync cost; semantic index/query-plan/materialized-view
synthesis; storage-tier and persistent-memory realization;
transaction/optimistic-concurrency/lock-shape/contention-layout/per-core
specialization; and energy, carbon, or dollar cost as first-class Pareto
dimensions under world policy. Security-mandated speculation hardening is a
realization cost that is zero exactly when a proof shows the mitigation is
unnecessary for an exact application. None of these is a new semantic kingdom;
each is a physical search strategy under §99 OPTIMIZATION-OPEN, verified under
§100, and accepted only on the §98 cost frontier.

## 103. OBSERVATION-MINIMUM

A realization must preserve only what the program's semantics actually make
observable. Everything else is free to change. If the program cannot observe
allocation identity, table layout, iteration order, exact scheduling,
intermediate strings, physical representation, device, or storage tier, then
each is a realization choice, not a constraint (C0 `law.observation.minimum`).

FTCFTW power is proportional to how carefully Idol defines what is and is not
observable: every accidental observable is a permanent optimization barrier.
Defining the exact observation model — the behavior realizations must preserve —
is the highest-leverage remaining language-design work. An observable that is
conservative by default and later proves unobservable is narrowed, never widened
silently.

## 104. OBSERVATION-ONE

A program is a set of required observable relationships between inputs, worlds,
effects, outcomes, and outputs — not a sequence of source operations. Given

    a = f(x)
    b = g(a)
    stdout:write(b)

the required observation may be only "given `x` and the current world, `stdout`
eventually observes the correct bytes with the required effects, order, and
failure semantics." If `f`, `g`, `a`, and `b` disappear entirely, that is ideal.
Only explicitly semantic observations constrain realization; incidental physical
behavior does not. Every accidental observable constrains FTCFTW forever, so the
exact observation boundary (which of result values, effect ordering, I/O bytes,
failure, timing, allocation/pointer/table identity, addresses, iteration order,
GC/finalizer timing, scheduling, stack depth, FP rounding, NaN payloads, signed
zero, syscall count, temp files, randomness, clock and environment reads is
observable) is the deepest language-design decision (C0 `law.observation.one`;
model in `gaps/GAP-170.md`).

Semantic time is not physical time. A relation may require `A` happens-before
`B` without requiring any wall-clock duration; execution duration is not program
semantics unless the program explicitly observes a clock or deadline world fact,
and reading the clock is itself an effect. A program may admit an allowed
**outcome set** (concurrency, unordered iteration, randomized algorithms); the
optimizer may realize any allowed outcome unless a stronger world/demand fact
constrains it. Determinism and reproducibility are world demands, not global
constraints. Observation sets are partly world-dependent: for a security world,
timing/cache/address may be observations; for an ordinary world they are not
(side-channel observability, §111-class). This is the deepest form of §1.

## 105. BOUNDARY-ONE

Representation freedom ends only at irreversible semantic boundaries: foreign
ABI, external file format, network protocol, shared-memory boundary, observable
pointer, volatile/device place, authority boundary, debugger-demanded address.
Before a boundary, representation is free; at the boundary, a specific
representation is demanded; after crossing back, representation is free again
where possible.

Foreign representation has finite extent. A C struct, Wasm ABI, network packet,
disk format, or GPU buffer is a temporary physical view whose lifetime is exactly
the foreign application; it must never infect the whole program because one
function touches it. Serialization is projection of semantic facts into an
externally constrained representation, and parsing is the inverse projection
under a descriptor; external schemas (protocol, file, ABI, database) are ordinary
descriptors, and endian/alignment are boundary representation facts, not language
primitives. Volatile/device places carry stronger effect semantics and must not
infect the ordinary memory model (C0 `law.observation.one`, which folds
BOUNDARY-ONE).

## 106. Foundational algebras (square-zero basis)

FTCFTW is not an ever-growing optimization checklist; it follows from a small
set of foundational algebras (C0 `law.observation.one`, `law.equivalence.observation`,
`law.demand.derivative`, `law.relation.property`, `law.change.delta`,
`law.uncertainty.algebra`, `law.optimizer.economy`). Define the smallest
observable semantics; everything not observable is realization space;
continuously search that space for the least-cost verified realization.

1. **Observation** — what must stay the same (§104, `law.observation.one`).
2. **Equivalence** — prove two semantic/physical programs produce the same
   permitted observations over results, failure, effects, authority, ordering,
   observable identity, and resource obligations; identity equality, semantic
   equivalence, and representation sharing stay distinct (§100,
   `law.equivalence.observation`, `law.realization.valid`, `law.optimization.validated`).
3. **Demand** — the exact portion, quality, cardinality, and order a consumer
   requires, including partial consumption, existential/`any`/`all`, top-k /
   order-statistic, and aggregate demand; and the demand derivative
   `demand(output) → demand(inputs)` that drives field pruning, lazy parsing,
   dead-result elimination, and query optimization; inverse demand cancels work a
   producer already satisfies (§24, `law.demand.derivative`).
4. **Law** — relation properties (associativity, commutativity, identity,
   idempotence, invertibility, monotonicity, distributivity, subsumption, fusion
   compatibility) drive transformation, not hardcoded arithmetic recognition; a
   law-implication graph lets known laws imply others (`law.relation.property`).
5. **Change** — semantic derivative/delta enabling incrementalization instead of
   recomputation (UI, compilers, databases, analytics, build systems); generalizes
   differentiation and reversibility (`law.change.delta`).
6. **Resource** — latency, throughput, tail, deadline, memory, energy, and
   reliability define the desired physical frontier (§98, `law.cost.closure`).
7. **Uncertainty** — separate unknown, known-absent, possibility set, evidence,
   assumption, fact, and proof; known absence (no effect/escape/failure/alias/
   allocation) is among the strongest facts (§7, `law.uncertainty.algebra`,
   `law.unknown.one`, `law.fact.cardinality`).
8. **Physical realization** — code is one physical strategy; algorithm, layout,
   data structure, OS mechanism, hardware, storage, and distribution belong here,
   and physical nonexistence (`none`) is a first-class representation (§102,
   `law.physical.open`, `law.observation.one`).
9. **Verification** — a small trusted checker admits candidates from any source
   (`law.optimization.validated`, `law.optimizer.economy`); minimize the trusted core.
10. **Search** — search the equivalence space, not a finite pass list (§99,
    `law.optimization.open`); discovery is separated from trusted admission.
11. **Optimization-of-optimization** — allocate compile, search, and proof effort
    by ROI (expected gain × executions − compile/search/code-size cost); anytime,
    background, and distributed search, and a proof-carrying realization cache, are
    admissible (`law.optimizer.economy`).
12. **Self-improvement** — verified discovered transformations become reusable
    laws and improve the self-hosted compiler, bounded by verification (§45,
    `law.optimizer.economy`).

Refinement is monotonic: knowledge only becomes more precise except under
explicitly guarded speculation, and no phase forgets an exact fact to reconstruct
a weaker one later. Contradiction (no valid meaning), ambiguity (several valid
meanings), and unknown (meaning not yet known) are distinct first-class states
with provenance. Proof identity and provenance are irrelevant to meaning and
realization unless observable or authority-sensitive. "Compiler pass" is a
physical scheduling unit only — facts exist, consumers demand them, producers
derive them, to a fixed point (§46-class, bidirectional demand↔facts↔realization).

## 107. OPTIMIZATION-SPACE-COMPLETE

FTCFTW is not compiler optimization. It is optimal realization of a semantic
observation contract under semantics, information, physics, economics, and
uncertainty. The square-zero problem is not "how to execute a program" but: what
transformations are possible between an intention and an observation, under
physical law, information constraints, uncertainty, resource constraints,
adversaries, and changing worlds? Execution, algorithm, architecture, storage,
distribution, and **even whether any computation occurs at all** are merely
candidate strategies. Given

    S = semantic identities and laws     O = demanded observation set
    W = world/environment/authority      D = downstream demand
    K = known facts                      E = uncertain evidence
    H = available physical resources     P = optimization policy
    F = fault/security/precision model   B = compilation/search budget

    R(S, O, W, D, K, E, H, P, F, B)

is the set of **every** physically lawful realization whose observations lie in
`allowed(O, S, W, F)` (§104). FTCFTW is: search `R` → verified Pareto frontier →
dominate every known competitor point → equal the proven lower bound where
further improvement is impossible (§98). Lower bounds are not instruction counts:
they include information-theoretic (bits that must be learned/moved/distinguished/
emitted), communication (bytes across any boundary), I/O and memory-hierarchy
(cache/external-memory transfers, rounds), circuit (depth/size/critical path),
parallel work/span, and ultimately physical law (speed of light, memory latency,
thermodynamic energy). `R` is never restricted to "compiler optimizations we
currently know," and the target is the best physically achievable lawful
implementation, not "best compiler output."

**Admission rule (the only rule).** A candidate realization — current or future,
named or unnamed, from any source (algebraic law, superoptimization, equality
saturation, learned search, autotuning, competitor mining, agent proposal) —
belongs in `R` iff it (1) preserves the demanded observations under the current
world (§104, §103); (2) satisfies authority, effect, and resource constraints
(§33, §74, §82); (3) has verifiable correctness (§100, `law.optimization.validated`);
and (4) improves the chosen Pareto frontier (§98). No compiler phase, source
abstraction, runtime architecture, target family, IR, or fixed pass order may
permanently narrow `R` without an explicit semantic observation requiring it.
Recent practice confirms the direction: persistent equivalence (equality
saturation) kept across abstraction levels so discovered alternatives are never
discarded; MLIR-style tunable transform composition with **no privileged pass
order**; and near-data/PIM results showing layout and computation must sometimes
be optimized *jointly* — hardware placement is not a backend afterthought.

**The frontier factors into 24 foundational axes.** Every degree of freedom —
from constant folding to GPU offload to automatic indexing to thermal scheduling
to distributed-architecture synthesis to lawful nonexecution — is a point in a
combination of these axes:

1.  **IDENTITY** — which semantic things exist and persist. (§1)
2.  **OBSERVATION** — what must remain invariant? (§104, §103)
3.  **LAW** — relation properties enabling equivalence transforms. (`law.relation.property`)
4.  **KNOWLEDGE** — known/absent/possible/exact facts. (§7)
5.  **UNCERTAINTY** — possibility, evidence, assumption, proof. (`law.uncertainty.algebra`)
6.  **DEMAND** — portion/quality/cardinality/order/timing required. (`law.demand.derivative`, §24)
7.  **CHANGE** — adaptation under changing inputs/worlds/hardware/workload/evidence. (`law.change.delta`)
8.  **EQUIVALENCE** — same permitted observations. (`law.equivalence.observation`, §100)
9.  **INFORMATION** — bits that must be learned/moved/distinguished/emitted (info-theoretic lower bound).
10. **WORK** — total operations and dependency span (work/span, circuit depth/size).
11. **COMMUNICATION** — information crossing any boundary (rounds, bytes, latency-hiding).
12. **REPRESENTATION** — structure/layout/encoding/precision/materialization, including `none`. (§25, §104)
13. **ARCHITECTURE** — software/system architecture as realization (erase/introduce boundaries, synthesize topology).
14. **PLACEMENT** — where code/data execute and live. (§102, §35)
15. **SCHEDULE** — when/in what order/parallelism physical work happens. (§34, §55)
16. **BOUNDARY** — ABI/OS/network/device/storage/trust interactions and their movement. (§105, §45)
17. **FAILURE** — fault domains, recovery, checkpoint, resilience strategy.
18. **RESOURCE** — memory/energy/bandwidth/thermal/hardware/economic budgets. (`law.cost.closure`)
19. **SEARCH** — which equivalent realization is found, with which search strategy. (§99)
20. **VERIFICATION** — how a candidate is established lawful. (§100, `law.optimization.validated`)
21. **EVIDENCE** — profile/measurement/value-of-information driving specialization. (`law.profile.evidence`)
22. **COST** — which Pareto point is optimal under world/policy. (§98, §89)
23. **ADAPTATION** — online/competitive strategy, migration, persistence, self-improvement. (`law.optimizer.economy`, §28, §85)
24. **META-COST** — compile/search/proof/profiling cost and lifecycle-global amortization. (`law.optimizer.economy`)

Lower bounds and Pareto accounting follow from these axes, not from instruction
counts: FTCFTW closure states *which* bound was reached (proven semantic minimum,
architectural minimum, measured machine minimum, best known external) drawn from
the INFORMATION/WORK/COMMUNICATION axes and physical law. Cost is a distribution,
not a constant: dominance requires non-overlapping confidence and robustness to
workload variation, and META-COST makes FTCFTW lifecycle-global — a 1 ns runtime
win that costs 10 hours to discover for a once-run program is a global loss;
every optimization carries an explicit break-even execution count.

**Meta-rule.** Individual optimization ideas — and every one of the ~200 discussed
frontier classes — are instances discovered *inside* `R`, not additions to the
constitution. Idol chooses the cheapest verified physical way to satisfy a
semantic observation contract; execution, algorithm, architecture, storage,
distribution, and even whether computation occurs at all are candidate strategies,
admissible whenever the four-part admission rule holds. This is how Idol claims
every identified *and unidentified future* optimization by construction rather
than by an ever-growing checklist (C0 `law.optimization.space`).

## 108. REALIZATION-CONTRACT

§107 still understated the frontier: "search every way to realize a computation"
already assumes computation must occur and that a compiler is choosing how to
*execute a program*. The square-zero premise is larger. FTCFTW is not compiler
optimization; it is **optimal verified realization under semantics, information,
physics, economics, and uncertainty**. Idol chooses the cheapest verified
physical way to satisfy a semantic observation contract — and execution,
algorithm, architecture, storage, distribution, and *whether any computation
occurs at all* are merely candidate strategies (§189-class lawful nonexecution).

**The complete shape.** The problem is not `semantic program → cheapest machine
code`. Given

    S = semantic identities and laws        O = demanded observation set
    W = world / environment / authority       D = downstream demand
    K = known facts                           E = uncertain evidence
    H = available physical resources          P = optimization policy
    F = fault / security / precision model     B = compile / search budget

find a realization `R` ranging over computation, **noncomputation**, algorithm,
data structure, encoding, precision, architecture, partition, placement,
schedule, memory, persistence, OS mechanism, hardware, distribution, and
adaptation, such that `observations(R) ∈ allowed(O, S, W, F)`, `R` is
Pareto-optimal under `P`, correctness is verified, and the remaining gap to the
known lower bounds is explicit (§100, §61-class).

**Lower bounds are physical, not instruction counts.** COST closure (§100,
`law.lower.bound`) tracks, where relevant, information required vs processed
(entropy / distinguishing bits), communication complexity across every boundary
(core, NUMA, device, kernel, machine), I/O and cache-block complexity, circuit
depth/size, parallel **work vs span** (available parallelism = work/span),
synchronization and round complexity, and ultimately speed-of-light, memory
latency, and thermodynamic energy bounds. An implementation reading 1 GiB to
answer a 1-bit question is far from optimal even with perfect instruction
selection. FTCFTW closure states *which* bound was reached: provable semantic
minimum, architectural minimum, measured machine minimum, or best known external.

**Lawful nonexecution is the ultimate realization.** If a demanded observation
is already satisfiable from cached exact answers, a theorem, materialized state,
or world facts, `R` runs nothing. Demand itself is analyzable: a demand proven
irrelevant to any observer disappears, and an effect/output proven unobservable
in the current world takes its producer with it. Cross-program pure results and
proofs may be reused (content-addressed) when communication beats recomputation.

**Architecture is realization.** A conventional software boundary — API layer,
serialization, process split, task, object, module, RPC, scheduler — that is not
externally observable may be **erased** (co-deployed RPC → direct call, network →
none), and a beneficial boundary may be **introduced** (isolate, parallelize,
distribute, offload). Cross-layer optimization spans language, compiler, runtime,
allocator, OS, database, network, hardware, and deployment wherever the boundary
is not semantically observable. The source need not fix the physical software
architecture; semantic relationships compile into whatever topology best
satisfies `W` under `P`.

**Meta-cost is lifecycle-global.** Compilation, search, proof, autotuning,
profiling, and variant storage are costs; a 1 ns runtime win that costs 10 hours
to discover for a once-run program is a global loss. Every optimization carries a
break-even execution count; amortization spans deployment scale; cost dimensions
are distributions, and no dominance is claimed when confidence intervals overlap
(§81-class), nor when a candidate wins nominally but loses under slight workload
or adversarial variation (robust/regret frontier).

**The foundational axes are ~24, not 12+1.** Every point discussed — constant
folding, GPU offload, automatic indexing, thermal scheduling, distributed
architecture synthesis, lawful nonexecution — is a combination of:

    1 IDENTITY   2 OBSERVATION  3 LAW         4 KNOWLEDGE
    5 UNCERTAINTY 6 DEMAND       7 CHANGE      8 EQUIVALENCE
    9 INFORMATION 10 WORK        11 COMMUNICATION 12 REPRESENTATION
    13 ARCHITECTURE 14 PLACEMENT  15 SCHEDULE   16 BOUNDARY
    17 FAILURE    18 RESOURCE    19 SEARCH     20 VERIFICATION
    21 EVIDENCE   22 COST        23 ADAPTATION 24 META-COST

These extend, not replace, the twelve of §106/§107 (IDENTITY, INFORMATION, WORK,
COMMUNICATION, ARCHITECTURE, FAILURE, EVIDENCE, ADAPTATION, and META-COST are the
axes §107 folded implicitly). Observation sets, cost dimensions, semantic facts,
and hardware targets all remain **extensible**: a future architecture, memory
technology, OS interface, algorithm, optimization theorem, cost dimension, or
observation must enrich existing identities without minting a parallel compiler
world, and no named ontology may permanently narrow `R` (§102, §99). The premise
in one line: *Idol satisfies a semantic observation contract at the cheapest
verified physical point — computation is one candidate strategy among many, and
sometimes the answer is to compute nothing* (C0 `law.realization.contract`).

## 109. OBLIGATION-ONE

Observation is only one side of semantics; **obligation** is the other. A program
does not merely produce observations — it owes obligations, and "same output" is
therefore not semantic equivalence. Semantics is `allowed observations +
required obligations`; FTCFTW may optimize everything else.

**Positive obligations** — must eventually respond, must commit durable state,
must respond within a deadline, must preserve an ordering, must release a
resource, must remain available under a fault model, must obey an authority
boundary. **Negative obligations** — must *not* touch the network, allocate,
leak secret-dependent timing, write after cancellation, duplicate an external
effect, retain persistent state, or let data leave a region. Negative
obligations are among the strongest optimization enablers: proving something
*cannot* happen eliminates whole runtime mechanisms.

Obligations are **temporal**, not merely ordered: `eventually A`, `A until B`,
`never C after D`, `A within deadline`, `B at most once`. **Safety** (a bad thing
never happens) and **liveness** (a required thing eventually happens) are
distinct and both must be preserved — an optimization may keep safety yet break
progress. A world fixes the **progress model** (wait-free, lock-free,
obstruction-free, eventual, best-effort) and whether **fairness** is observable;
never globally promise fairness a world did not demand. **Causality** (`B because
of A`) is stronger than order (`A before B`) and is a distinct graph fact.
Some optimizations reason **counterfactually** over several admissible worlds
(speculation, rollback, deoptimization, noninterference), not only the realized
one. **Noninterference** — changing a secret must not change a public
observation — is a relation *between* executions, and FTCFTW optimizes within it
(constant-time, privacy, information-flow).

**HYPERPROPERTIES: equivalence is over sets of executions, not one trace.** Some
requirements — determinism, noninterference, serializability, linearizability,
observational consistency — constrain the *set* of a program's executions, not
any single run. A single-trace observation-equivalence model is therefore
insufficient; §100/§104 equivalence must preserve the demanded **hyperproperties**
as well as per-trace observations. Trust and provenance quality (axiom, static
proof, trusted witness, runtime observation, profile estimate, external claim,
heuristic) grade how aggressively a fact may be exploited; information-flow,
declassification, and privacy-budget worlds bound which derived facts may cross a
boundary (C0 `law.obligation.one`; obligations are effect/world facts, never new
source syntax — `docs/spec/host.md`, §104).

## 110. NINE-UNIVERSE (structural closure)

A complete FTCFTW design cannot be a list of optimizations; it must be a closure
system in which every present and future optimization is a point in a formally
open problem space. The whole architecture reduces to **nine universes**:

1. **Meaning** — identity, relation, fact, world, law. *What does it mean?*
2. **Observation** — value, effect, ordering, time, identity, security,
   liveness, failure, quality, and **obligation** (§104, §109). *What is
   externally constrained?*
3. **Knowledge** — unknown, absent, possible, fact, evidence, assumption, proof,
   provenance. *What do we know, and how strongly?* (§7)
4. **Demand** — which result, portion, quality, when, how often, under what
   obligation. *What is actually required?* (§24)
5. **Equivalence** — which alternate semantic/physical behaviors preserve the
   required observations *and hyperproperties* (§100, §109). *This defines legal
   optimization.*
6. **Realization** — an intentionally unbounded set: computation, noncomputation,
   algorithm, architecture, representation, placement, schedule, hardware, OS,
   distribution, and future physical strategy (§102, §108).
7. **Resource** — an extensible vector: time, memory, energy, bandwidth, space,
   money, reliability, human effort, future resource (§98).
8. **Search + proof** — discover, verify, measure, rank, learn, generalize,
   reuse; no fixed algorithm set (§99, §100).
9. **Change** — inputs, program, world, hardware, evidence, policy, and physical
   state all change; realization adapts while semantic identity persists (§28).

**The supreme FTCFTW equation.** Given meaning `M`, observation+obligation
contract `O`, knowledge `K`, demand `D`, world `W`, resource/policy `P`, and
current physical state `X`, find any realization `R` such that `R` satisfies
`O(M, W, D)`, no known lawful realization dominates `R`, and the remaining gap to
the available lower bounds is explicit — *while continuously admitting new
knowledge, laws, hardware, search methods, proofs, cost dimensions, and physical
strategies.* Completeness is therefore **structural, not enumerative**: no
enumeration can close the realization set, so the constitution closes it by the
admission rule (§107) plus these nine universes, never by a checklist.

Corollaries the closure makes first-class: **value-of-information** — acquiring a
fact (profile, probe, prescan, external query, or a stronger human/agent
contract) is itself an optimization action weighed as `cost-to-learn` vs
`expected savings`; **contract-weakening / semantic-debt** — a declared guarantee
(exact order, precision, stable address, identity) with *no observer* should be
removed to expand `R`, and its presence is measurable debt; **real-options /
irreversibility** — keeping several physical options open, or paying slightly
more now to make future migration cheap, has option value, and irreversible
choices (published ABI, persistent format, distributed partitioning) are priced;
**monotonic frontier** — a newer compiler may not knowingly regress a previously
closed Pareto point unless a selected constraint changed, so the best-ever
realization and best-known competitor point are archived and regression is
first-class debt; **optimality gap** — `best-known − proven-lower-bound` is the
exact quantitative definition of remaining FTCFTW debt, and "no faster found" is
kept distinct from "proven none faster exists" (§51/§52-class, C0
`law.realization.universe`).

**The fundamental statement.** *Idol specifies meaning and demanded observation,
not execution. Every property not required by that contract remains an open
optimization variable. FTCFTW is the continuous search for the verified
nondominated physical realization over an intentionally unbounded realization
space, with every remaining cost causally attributable and every optimality gap
measurable.*

## Master test

Before adding ANY source spelling, identity, graph field, edge, runtime object,
compiler subsystem or physical cost, ask:

1. WHAT independent semantic thing exists?
2. Is this actually a fact about something else?
3. Can the compiler infer it?
4. Does the graph already know it?
5. Is this duplicating an existing authority?
6. Is this merely representation?
7. Is this merely cardinality?
8. Is this merely a role?
9. Is this merely organization?
10. Can this be a static projection from a world/table?
11. Can this be ordinary application?
12. Can this be an inferred able constraint?
13. Can this be deleted before being named?
14. What unresolved semantic possibility requires its runtime cost?

If there is no good answer: DELETE IT.

## Final architectural sentence

Semantic observations are the only invariants. Identity and facts define those
observations; everything else — control flow, algorithms, data structures,
memory, code, operating-system interaction, hardware placement, and compiler
strategy — is realization space and may disappear, transform, migrate, or be
synthesized whenever verified equivalence permits a cheaper physical outcome.
Idol is a world-relative Lua semantic graph where ordinary table projection,
subject-oriented relations, one universal application algebra, mostly inferred
`able(...)` constraints, exact demand, and representation-polymorphic realization
allow minimal source to specialize all the way into minimal native machine work.
