# Idol — supreme language, semantic-graph, compiler, and performance law

This is the **sole supreme compact law** of Idol. It governs the active tree.
`docs/spec/constitution.md` is its structured long-form expansion and the home of
stable `law.*` identities. When any projection, gate, comment, fixture, branch,
or long-form sentence diverges from this file, this file wins and the divergent
artifact must be corrected or classified as historical research.

The pre-convergence compact law is preserved by Git blob
`99525703b37b2bab4f8fa42bbfdffda8f45d654c` and repository ancestry. Replacing
an authority projection never deletes its research provenance.

## 0. Identity and objective

The project and language are **Idol**. The compiler executable is `idol` and
canonical source uses `.id`.

Idol is Lua progressively specialized into native execution:

```text
ordinary Lua meaning
→ inferred semantic facts
→ guarded specialization
→ sealed specialization
→ native representation
→ target-specific realization
```

The compiler gains knowledge. The programmer should rarely rewrite code to
become fast.

FTCFTW means verified Pareto dominance over the strongest known semantically
equivalent implementation, or equality with a proven physical lower bound where
strict improvement is impossible. It is not “roughly C speed,” not a single
benchmark score, and not an algorithmic win used to conceal code-generation
loss.

Every relevant dimension remains visible: runtime, throughput, latency, startup,
warmup, compile and incremental work, memory, allocations, traffic, artifact and
loaded bytes, relocations, syscalls, instructions, branches, misses, spills,
energy, and target-specific constraints. A result is WIN, OPTIMAL, or an exact
LOSS with causal decomposition. No win compensates for an open loss on another
unacknowledged dimension.

SHC means every production semantic decision is eventually executed by Idol
itself. Source-file percentage and translated LOC are not SHC evidence.

## 1. Observation, identity, facts

A program specifies required observable relationships among inputs, worlds,
effects, outcomes, and outputs—not a mandatory sequence of implementation
steps. Everything not semantically observed is realization freedom.

```text
SEMANTIC IDENTITY PERSISTS
REPRESENTATION CHANGES
```

One semantic thing has one exact id. Facts qualify ids; facts do not mint shadow
identities. Names, paths, spans, hashes, pointers, AST nodes, opcodes, slots,
host types, local enums, source spellings, and representations are provenance,
indexes, or physical encodings only.

Unknown, absent, false, zero, empty, and not-asked are distinct.

Every authoritative fact has exactly one producer. Once known, a fact is carried
forward; downstream phases never reconstruct it from syntax or representation.

## 2. The only semantic architecture

The compiler converges on one semantic graph containing exact identities and
facts for:

- source provenance and selected source law;
- homes, bindings, reach, worlds, authority, witnesses;
- values, places, descriptors, packs, relations, applications, results;
- effects, control dependencies, determinacy, ranges, laws, stages, targets;
- demand, observation, transformations, realizations, machine lineage;
- foreign semantic identities and exact equivalence witnesses.

No parallel AST semantics, namespace model, type kingdom, protocol registry,
builtin registry, optimizer ontology, DNIR semantics, backend semantics, LSP
semantics, or MCP semantics may compete with the graph. Bounded physical indexes
and encodings are allowed only with a named graph producer, consumer, provenance,
and deletion condition.

## 3. Source minimum, graph maximum, physical minimum

Canonical direction:

```text
MINIMUM SOURCE SPELLING
MAXIMUM SEMANTIC FACTS
MINIMUM PHYSICAL WORK
```

Source spells only distinctions not uniquely recoverable from graph-visible
subject, operands, result demand, descriptors, reachable facts, relation laws,
world/effect requirements, stage, target, provenance, and control refinement.
If one lawful interpretation remains, infer it. If several remain, spell the
smallest missing distinction. An inference implementation gap never makes
redundant syntax canonical.

One-use intermediates disappear when the chain preserves identity. Names remain
when they add semantic meaning, serve multiple consumers, identify observable
places, or preserve required provenance.

## 4. Source, grammar, world, graph, realization

Keep the layers exact:

```text
source       bytes, span, source law, provenance
grammar      generated recognition projection
world        bindings/facts/authority/stage/target/observers in reach
graph        resolved meaning and witnesses
demand       required observations/results/effects
realization  physical representation and execution
```

```text
recognize(source, source law)
→ resolve(syntax provenance, world)
→ publish graph facts
→ project demand
→ choose lawful realization
→ machine + evidence
```

Exactly one source law owns each source position. Never union grammars, try
parsers until one accepts, infer grammar from command-looking text, or grant
world authority from syntax. A suffix/path may select law at ingress and remains
provenance afterward; it never becomes downstream semantic authority.

Parser, formatter, Tree-sitter, LSP, MCP, documentation, and canonicalization
consume projections from one grammar owner. They do not maintain spelling or
role tables that must merely “agree.”

## 5. Delimiter and face closure

Delimiter meanings are permanent and non-overloaded:

```text
()  ordinary relation application, grouping, operand/result boundaries
[]  computed or indexed projection
{}  structured pack, table, descriptor structure
.   one statically known projection
:   subject-oriented relation or constraint face
@   current-world access, injection, or world qualification
```

`()` is ordinary application. It never means table indexing.

`[]` is computed/indexed projection. Reads and writes are the demand-selected
faces of the same projected place/value relation:

```id
value = table[key]
table[key] = replacement
```

`{}` carries structured pack/table/descriptor structure. Layout may be offside
when the introducer already fixes the region’s role, but the semantic structure
is the same.

`.` is exactly one static projection, never dynamic method search, namespace
fallback, recursive lookup, world fallback, or computed access.

`:` orients an existing relation around its genuine semantic subject. It does
not turn organizational homes/packages into receivers.

Compatibility syntax may be recognized with exact provenance and normalized
before semantic consumption. Compatibility never changes canonical delimiter
meaning and never creates a second application/projection implementation.

## 6. World, home, reach, subject, place

A world is the closed semantic table under which meaning is resolved. It may
carry bindings, descriptors, relations, facts, stage/target facts, authority,
requirements, witnesses, and observer demand. Authority is a fact in a world;
world is not synonymous with authority.

Never conflate:

```text
home     where meaning lives / provenance context
reach    whether meaning resolves here
subject  value/place an application is about
world    facts and authority under which it is interpreted
place    observable storage/location identity
```

Absolute:

```text
home != world
home != subject
path != identity
package provenance != authority
value != place
binding != place
world witness != relation/protocol witness
```

A place exists only when mutation, alias, address, lifetime, persistence,
volatile/device behavior, or an ABI boundary makes location observable. Scalars,
parameters, homes, and immutable determined values are not places merely because
a compiler implementation stores them.

`@` is the current world. `@member` accesses an exact current-world member;
`@{ k = v }` derives a closed world with an exact fact delta; `thing@world`
evaluates/qualifies `thing` under that world. Injection does not mutate its
source world and cannot manufacture authority from a boolean/string label.

Stage is a fact a world carries, so evaluation at a stage is evaluation under a
world. `@(expr)` is the current world applied to an expression — `expr`
resolved under the world resolving it, whose stage fact is the compile stage —
and is therefore exactly `expr@{ stage = compile }`. It is not a compiler
directive and not a fourth use of the sigil; prefix `@` keeps its one meaning.
It follows that an operation whose whole content is "do this at compile time"
is an ordinary relation applied under a stage-delta world, that a value absent
at that stage is absent from that world rather than specially diagnosed, and
that stage participates in world identity wherever it changes lawful
realizations.

A local binding wins over an ambient projection. Ambiguity fails closed—never
first/last/load/path/hash order.

## 7. Files, homes, distribution

A `.id` file is a source partition, not a module. A directory may establish
initial discovery/home provenance, not a namespace object or authority grant.
After resolution, ids and witnesses preserve continuity; downstream phases do
not walk paths again to recover meaning.

Native Idol has no semantic module, namespace, import, require, `req`, package
loader, module table, standard namespace, admission operation, provider,
service-locator, or dependency-injection system. Existing instances are exact
foreign-law provenance or bounded migration bridges with deletion gates.

A resolved reference contributes its dependency. Build/distribution
configuration establishes acquisition, version, provenance, trust, and roots in
reach. Source does not restate the same dependency with import ceremony.

Canonical vocabulary is compiler-owned initial reachability of admitted semantic
identities. It is not a runtime `std` object or duplicated registry.

## 8. Descriptors, relations, protocols

One descriptor system expresses types, shapes, schemas, cases, concepts,
protocol demands, stages, targets, hardware facts, worlds, and agent/tool facts
where they are genuinely descriptors of existing identities. Do not create a
separate class/struct/trait/concept/enum/module object model for each surface.

A relation is the protocol. A constraint demands an existing relation/fact;
witnesses prove satisfaction. No trait/impl/interface/vtable ontology is native
Idol law.

Tables, closures, metatables, multiple results, and ordinary bindings remain the
Lua semantic foundation and become progressively more specialized rather than
being replaced by host-language abstractions.

## 9. Application and projection

There is one application algebra. Function-like, subject-oriented, generic,
builtin, foreign, and transformed calls are applications of exact relation/value
identities with exact operand packs, world, result demand, and witnesses.

Source orientation disappears after resolution. Operation-first and subject-first
faces that denote the same application share one occurrence identity and one
relation identity; provenance records the face used.

Computed aggregate access is projection, not application. Static named access is
static projection. Application and projection may share downstream value/place
machinery only after their semantic identities are already resolved; syntax
shape never decides which one occurred in lowering.

Call shape, table shape, descriptor identity, compile-time values, result packs,
closure captures, world, stage, target, and observer demand drive progressive
specialization.

Declaration heads specialize by the same algebra as invocation faces. A relation
head may carry its projection pack before `=` (`weight(kg) = (body, factor)`),
a subject specialization (`body:weight = (factor)`), or both
(`body:weight(kg) = (factor)`). These are one relation identity plus semantic
facts — subject constraint and projection facts — with an implementation
witness; they are not nested functions, bound methods, partial applications, or
closures. A subject home compresses the same declaration
(`body: { weight(kg) = ... }`) by supplying the recoverable subject.

Head levels admit only stable semantic axes: descriptor, unit, encoding, law,
stage, target, world, witness. Runtime payload stays in the operand pack after
`=`; specializing on payload (`body:move(10) = ...`) is refused. Compile-time
knowledge at a call site may specialize an application without minting a
declared axis. There is no anonymous self slot `(:)` and no pipeline operator
`|>`; chaining is subject/relation chaining through demanded results.

## 10. Demand and observation

Demand is a graph fact, not a parallel type lattice. It identifies which results,
members, effects, states, diagnostics, provenance, or temporal observations must
survive.

Unobserved values, fields, iterations, control flow, storage, calls, modules,
world setup, and even whole algorithms may be physically absent when an exact
witness proves observation equivalence.

Observer/debugger/profiler/MCP demands are per exact semantic entity/place, not a
compile-wide all-or-nothing roster. Observer/world demand participates in cache
identity whenever it changes lawful realizations.

Demand over user-defined and recursive relations is solved through graph
relation/application identities and finite fixpoints with explicit refusal for
unsupported effects, traps, captures, rebinding, budgets, or disagreement.

## 11. Transformations and laws

A transformation is a graph entity with:

- exact input occurrence/value ids;
- relation laws and preconditions;
- world, effect, stage, target, and observer obligations;
- replacement/result ids;
- provenance and verification witness;
- realization/machine/evidence lineage.

Never destructively rewrite syntax and reconstruct application accounting later.
Constant folding, specialization, quotienting, loop contraction, early
termination, vectorization, layout change, devirtualization, fusion, and foreign
projection all use the same transformation architecture.

A relation law is a graph fact. Local op enums or bounded search encodings may be
physical indexes, never semantic owners. Unsupported or unproved cases refuse or
fall back without changing meaning.

## 12. Representation and DNIR

Semantic values are independent of physical representation. The realization
engine may select absence, immediate, register, stack, aggregate, memory, shared
region, SIMD, GPU, Wasm, foreign ABI, or another target form under exact demand
and law.

DNIR/native IR is permitted only as a physical realization encoding over graph
ids/facts. It must not own semantic application classes, builtin meaning,
result/descriptors, effect law, place identity, world selection, or optimization
eligibility. AST pointers, names, paths, strings, and opcode tags are temporary
bridges only and must monotonically reach zero after graph fact closure.

Direct, C, Wasm, JIT, interpreter, and tool backends consume the same graph
meaning and may differ only in lawful physical realization. Generated C is a
bootstrap/foreign realization, not proof of direct-native performance or SHC.

## 13. Cache, artifacts, concurrency

Artifact identity derives from the exact semantic dependency closure:
source graph, worlds, observers, target/subtarget/ABI, profile, foreign/link
inputs, realization policy/budget, compiler configuration, and compiler revision.
Path may discriminate physical temporary files but is never semantic identity.

Concurrent builds must use race-safe physical artifact namespaces. Same-basename
sources may never share temporary objects or poison content-addressed caches.
Unknown cache dependencies conservatively invalidate or fail closed.

## 14. Performance admission and evidence

A performance change must bind:

- exact clean commit and compiler artifact;
- machine, OS/world, target, ABI, and thermal/power context;
- source/graph subject and observer demand;
- cache/warmup/startup state;
- raw outcomes and distributions;
- semantic result/equivalence controls;
- negative and ablation controls;
- runtime, compile work, memory, artifact size, and relevant counters;
- strongest known competitor and physical lower bound;
- same-algorithm code-generation comparison separate from algorithmic wins.

Research measurements remain historical until rerun on the exact integrated
subject. “UNMEASURED” is a valid state; invented green evidence is not.

A non-performance change activates no performance claim and must preserve the
strongest executable baseline. An algorithmic win never closes machine/codegen
debt.

## 15. Agent, LSP, MCP, tooling

Every feature is evaluated with formatting, completion, hover, highlighting,
diagnostics, refactoring, navigation, and stable semantic ids.

LSP and MCP are projections/API consumers of the same graph. They do not infer
meaning from text once ids/facts exist. Agent workflows use stable ids,
provenance, transformations, gaps, and evidence rather than branch-local prose or
session-state files.

Kira’s ordinary ad hoc questions and other personal conversation are unrelated
to Idol authority unless the user explicitly connects them to the project.

## 16. Research, gaps, and zero-history active tree

Git stores history. The active tree stores current law, current implementation,
current foreign interoperability, bounded executed bridges, exact open gaps, and
current evidence—not museums, session snapshots, or superseded identities.

Research is never lost when removed from the active tree. Preserve exact source,
commit ancestry, controls, measurements, non-results, and disposition. A research
mechanism becomes active only after current-law reconciliation, named consumers,
lineage, controls, and exact-head evidence.

Every bridge records semantic owner, physical owner, facts crossing/lost,
consumer, evidence, and deletion witness. Consumer-zero production modules move
to research or gain a real consumer.

## 17. Absolute direction

Idol is not a conventional compiler rewritten in `.id`, a permanent AST→IR→IR
pipeline, a module system, a type/object hierarchy, a conventional Wasm VM, or a
collection of optimizer passes that rediscover facts.

Idol is:

```text
semantic identity
+ exact facts
+ demand and observation
+ lawful transformation
+ late physical realization
+ exact evidence
```

The compiler should know more while physically doing less. Dynamic code should
progressively become native without changing programming style. Every merge must
move toward fewer authorities, fewer reconstructed facts, fewer representations
forced early, fewer runtime obligations, and greater semantic/physical freedom—or
record the exact gap preventing that movement.
