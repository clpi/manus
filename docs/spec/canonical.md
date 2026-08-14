# IDOL — blind one-pager / total canonical + repository law

**AUTHORITY:** This document is authoritative over repository accidents.

**SUPREME one-page law:** `docs/spec/law.md` is authoritative over every document,
including this one; wherever this file diverges from `docs/spec/law.md`, that page
wins and this file must be corrected. `docs/spec/constitution.md` (C0) is the
structured long-form expansion of `docs/spec/law.md` and the home of the `law.*`
identities. Readable bootstrap: `docs/spec/agent.md`. **Read this file before
repository code.**

Existing Git state may contain:

- stale syntax
- stale names
- migration machinery
- old ontology
- host-language patterns
- historical tests/docs

**Do not infer language law from frequency in Git.**

```text
SOURCE MINIMUM.
GRAPH MAXIMUM.
REALIZATION MINIMUM.
ONE THING → ONE ID.
FACTS QUALIFY THINGS.
RELATIONS ARE IDS.
EDGES EXPRESS STRUCTURAL ROLES.
EDGES NEVER NAME OPERATIONS.
```

**Enforcement nuance:** regex owns **lexical impossibility**; semantic gates own
**conceptual impossibility**. Do not “solve” naming with one giant regexp —
`broker` is as wrong as `router`, `bundle` can encode plurality without ending
in `s`, and `tokenview` satisfies `^[a-z][a-z0-9]*$` while encoding two meanings.

**Gate pipeline (mechanical → semantic):**

```text
lexical regex
→ filename/path regex
→ syntax AST checks
→ identifier semantic-role classification
→ graph-structure checks
→ adversarial negative controls
```

Current migration implementation: `gate/idiom.id`, `gate/path.id`, `gate/host.id`,
`gate/admission.id`, `gate/graph.id` — partial coverage until GAP-124 graph gate.

---

## 1. Canonical source

**Bindings:**

```id
x = value
x: descriptor = value
```

**Functions:**

```id
add = (a, b) a + b
normalize = (value) value:validate():normalize()
```

**Static projection:** `x.y`

**Subject relation:** `x:y(...)`

**Application / ordinary access:** `x(...)`

**Canonical lookup:**

```id
table(key)
env("HOME")
args(1)
```

**Meaningful relation verbs remain:**

```id
source:read()
path:open()
command:run()
stdout:write(text)
text:find(pattern)
text:parse(json)
```

Root body executes. Tail expression returns. Blocks are offside. Comments use `#`.
Text uses `"..."`. Interpolation uses `"{value}"`.

---

## 2. Canonical source zero list

Canonical Idol **must not introduce:**

- `function`, `fun`, `fn`
- `local`, `let`, `var`, `const`
- `then`, `do`, `end`
- `main`, `entry`, `init`
- `import`, `require`, `req`, `include`
- `module`, `namespace`
- `trait`, `interface`, `impl`
- `class`, `struct` as independent object-model kingdom
- `concept` as independent protocol kingdom
- `std.*`, `lib.*`, `core.*`
- `@comp.*`, `@host.*`, `@runtime.*`, `@c.*` — `@` IS THE CURRENT-WORLD ACCESSOR
  (`docs/spec/law.md` §4): bare `@` current-world value, `@member` world access
  (`@target`, `@env`), `@member = v` mutation, postfix `thing@world` / `thing@`,
  `@{ k=v }` world injection (`thing@{ k=v }` interjection), `@(eval)`; never a
  compiler/host/runtime/emit directive namespace, and never `@.member` or
  `@:member` — `@` already accesses, so `@.` and `@:` are INVALID

**Ordinary access must not be:**

- `x:get(k)`, `x:set(k,v)`, `x[k]`

**Ordinary application must not be:**

- `f:call(x)`, `f.call(x)`

**Presence must not be reboxed as:** `has`, `contains`, `exists`, `present`

**Use instead:**

```id
value = x(key)
position = text:find(pattern)
# then nil/value refinement
```

---

## 3. Application / table dispatch

One application algebra owns:

- relation, subject, operand, result
- descriptor, demand, effect
- world requirement, witness
- stage, provenance, realization

There are **not** separate semantic kingdoms for: function call, method call,
table call, accessor call, protocol call, builtin call, generic call.

A table may admit application. `table(key)` does **not** secretly mean
`table:get(key)`. Resolver determines application semantics.

If application yields a place: `table(key) = value` — no separate setter ontology.

---

## 4. Edge law

Edges encode **structural semantic roles**.

Permissible conceptual edge roles include only irreducible structural facts such
as: `relation`, `subject`, `operand`, `result`, `member`, `binding`, `descriptor`,
`projection`, `capture`, `provenance`, `origin`, `witness`, `demand`, `target`.

Each still must prove irreducibility.

**Never define operational edge kinds:**

`run`, `call`, `invoke`, `execute`, `read`, `write`, `get`, `set`, `open`,
`close`, `parse`, `encode`, `decode`, `convert`, `compile`, `lower`, `emit`,
`generate`, `transform`, `dispatch`, `resolve`, `load`, `store`

**Correct:**

```text
application --relation--> read-id
application --subject--> file-id
application --result--> value-id
```

**Wrong:**

```text
file --read--> value
application --call--> function
command --run--> process
```

Relation identity owns operation semantics.

---

## 5. Reverse edge zero

Do not create semantic inverse duplicates:

- `calls` / `calledby`
- `contains` / `containedby`
- `uses` / `usedby`
- `reads` / `readby`
- `parent` / `child`

Store one authoritative relation. Reverse traversal is query, index, or derived
view — not second semantic truth.

---

## 6. Resolve once

Source spelling may participate in **initial resolution** only.

After exact id exists, **never** recover meaning from spelling again.

After resolution there is no:

- `findFunc(name)`, `findByName(name)`
- semantic `.get(name)`, semantic `["name"]`
- callee string matching
- descriptor name identity matching
- path-based lookup, module lookup
- namespace / global / parent-scope / parent-world fallback

Use exact ids + graph edges. If consumer lacks id: **fix producer.** Never patch
consumer with a search.

---

## 7. String matching classification

Every compiler string comparison must be classified:

| Class | Role |
|---|---|
| SOURCE | resolution-time token/spelling |
| FOREIGN | foreign lawset provenance |
| DATA | user/runtime data keys |
| DISPLAY | diagnostics/rendering |
| CACHE | candidate narrowing; exact facts must verify |
| SEMANTIC | **forbidden after resolution** |

**Legitimate:** JSON field key, env variable key, user text, source token spelling
during resolution, diagnostic rendering.

**Forbidden:** relation selected by `"add"`, descriptor identified by `"point"`,
world selected by `"io"`, handler selected by `"read"`, target selected by
path/name.

---

## 8. `.get` / `[]` host rule

Do **not** blindly ban host-language indexing.

**Allowed:**

- `graph.get(exact_id)`
- `rows[application_id]`
- `json.object.get("field")`
- runtime user-data map lookup

**Forbidden:**

- `functions.get(name)`
- `descriptors.get(name)`
- `handlers.get(kind_name)`
- `worlds.get("io")`
- `semantic["read"]`

**Question:** accessing already-resolved storage/data? → allowed. Recovering
semantic meaning from label/path? → forbidden.

---

## 9. Naming — one word / one thing

Project-owned semantic identities are: lowercase, singular, one irreducible word.

**No:** underscores, hyphens, camelCase, PascalCase, mashed compounds,
numeric/historical taxonomy.

**Still invalid (examples):** `tokenview`, `scanfiles`, `canonicalid`,
`arm64check`, `perfledger`, `hostcensus`, `semanticgraph`, `nativevalue`

Do not remove separator and call migration complete. **Decompose before rename.**

---

## 10. Plural zero

Semantic identity denotes **one thing**. Plurality belongs to table membership,
pack membership, shape, cardinality.

**Presumptively forbidden semantic identities:**

`bytes`, `strings`, `chars`, `fields`, `variants`, `tokens`, `nodes`, `edges`,
`values`, `arguments`, `results`, `captures`, `tests`, `gates`, `examples`,
`fixtures`, `files`, `rules`, `worlds`, `protocols`, `descriptors`, `collections`,
`contracts`, `encodings`, `formats`

Do not evade using `collection`, `bundle`, `suite`, `set`, `catalog`, `group`,
`pool`, `container`, `family` when meaning is merely “many X.”

A sequence of byte-like values is: value + element descriptor + shape +
cardinality + stride/layout facts — not `bytes`. Even `byte` must prove
irreducibility.

---

## 11. Able zero

Project-owned identities encoding capability are forbidden:

`callable`, `readable`, `writable`, `iterable`, `indexable`, `hashable`,
`comparable`, `serializable`, `encodable`, `decodable`, `parseable`, `printable`,
`executable`, `runnable`, `awaitable`, `seekable`

**General rule:** `*able` / `*ible` forbidden when meaning is “admits relation/application X.”
Use actual relation/application fact.

**Exception — the boundary keyword `able(...)`:** the bare relation `able(r)` is
NOT an adjective identity; it is the one explicit protocol/requirement boundary
(`docs/spec/law.md` §9), e.g. `able(eq)`, `able(read)`, `able(to(str))`. It is
normally inferred and spelled only at a real boundary; it mints no trait,
dictionary, or vtable. A name ending in `able`/`ible` (`readable`, `iterable`)
remains forbidden.

---

## 11a. Boolean-mirror zero (BOOLEAN-MIRROR-ZERO)

Do not store a boolean flag that merely restates a structural graph fact
(`law.boolean.mirror.zero`).

| Graph fact | Forbidden mirror |
|---|---|
| subject edge exists | `possessed = true` / `has_subject` |
| witness edge exists | `authorized = true` |
| capture edge exists | `captured = true` |
| descriptor edge exists | `typed = true` |
| application is applied | `callable = true` |
| identity participates | `operation = true` / `operation = false` |
| projection / binding / stage / target | `projected` `resolved` `imported` `native` `static` |

Absence of the fact is the answer. Never `world = ""`, `world = nil`,
`world = "none"`, or `world = false`.

---

## 11b. Catalog zero (CATALOG-ZERO)

Do not create a table whose primary purpose is to enumerate relations,
descriptors, worlds, formats, handlers, operations, or capabilities
(`law.catalog.zero`).

If the items already have identities and facts in the graph, the catalog is a
second authority and must be deleted. Do not rename a catalog to preserve it
(`seq` → `sequence` keeps the architecture).

Deleted second authorities include: `lib/semantic/*` relation rows, `seq`
catalog, `semantic/io`, `semantic/fs`, encoding/builtin/directive catalogs,
producer relation ledger.

Relation facts come from resolution. Authority comes from world or witness
facts on the application. JSON is a format or descriptor, not a world.

---

## 11c. Magic-code zero (MAGIC-CODE-ZERO)

Do not reconstruct semantic identity from a numeric code, ordinal, or sentinel
(`law.magic.zero`). The producer already knows the rejection, kind, or
outcome. The consumer must not switch on `-103` or `@enumFromInt`.

Forbidden reconstructions:

- negative status → diagnostic (`lexErrorFromCode`)
- enum ordinal → host enum (`tokenKindFromOrdinal`)
- opcode → semantic relation
- foreign `$?` → run outcome

Carry the rejection-id, token-role-id, or outcome fact across the seam.

---

## 11d. Schema-one (SCHEMA-ONE)

One producer per record law (`law.schema.one`, `law.fact.producer.one`).
Host `RECORD_SLOTS` and positional field decoding are a second schema.
The producer projects the record; the consumer reads that projection.
`duo_lexer_tokenize_full` / `duo_lexer_error_line` / `useDuoTokens` are
bridge-death names (`law.bridge.death`).

---

## 11e. Main zero / generic-action zero / collision zero

- **MAIN-ZERO** (`law.main.zero`): file-scope result or the named step. Never
  `main: i64 = ()` wrapping another routine.
- **GENERIC-ACTION-ZERO** (`law.action.zero`): `run`, `execute`, `process`,
  `apply`, `perform`, `handle` as root/helper names require an actual semantic
  subject. `command:run()` is legitimate; `run: i64 = ()` is not.
- **FOUNDATIONAL-WORD-COLLISION-ZERO** (`law.foundation.zero`): do not use
  `apply`, `project`, `realize`, `resolve`, `bind`, `demand`, `witness`,
  `relation`, `subject`, `world`, `shape`, `descriptor` as generic helpers.

---

## 11f. Evidence-subject one (EVIDENCE-SUBJECT-ONE)

Evidence identity and measured-program identity are separate facts.
A measurement commit must name `subject revision` and `evidence revision`.
Do not report metrics “at HEAD” unless the measured subject equals HEAD.

Status authorities:

- executed frontier → `docs/bootstrap.md`
- metrics interpretation → `docs/METRICS.md`
- revision-bound evidence → generated evidence artifact

Other reports are snapshots or projections. They are not a second frontier.

---

## 11g. Oracle bound

A differential oracle covers the legacy-equivalent subset only. Idol law is
the constitution and the canonical lexer. When Idol intentionally diverges,
the host scanner must not veto the new behavior. `tokenizeHost()` remains
deletable (`law.bridge.death`).

---

## 11h. Source-family one

Path suffix is provenance only (`law.family.one`). One ingress authority
produces the source-family fact. Later components must not call
`is_canonical_source(path)` or re-parse `.id` bytes to decide law.
Every lexer export takes family as an operand. `new()` does not read suffix
bytes. Production compile, fmt, and embed classify once via `sourceFacts` then
`Lexer.initFacts`; they must not call `Lexer.init` or `is_canonical_source`.
`route()`, parse, sema, and token-view consume `lex.family` / the family
operand. Family is produced by `admit(law, path)` — law is the operand,
path is provenance. Corpus homes admit in-tree family; `discover` is only
the unlisted-path fallback (`law.bridge.death`). `Lexer.init` remains a
test convenience.

---

## 11i. Representation one

A semantic value has no physical representation until realization demand
requires one (`law.representation.one`). One producer decides width, layout,
location, boxing, addressability, aggregation, and calling convention from
descriptor × lifetime × alias × mutation × escape × demand × ABI × target.

Downstream must not separately decide boxed / stack / register / heap /
struct / SIMD. Those are that one realization decision, not later repairs.
Every remaining physical structure must name its observation
(`law.representation.demand`).

---

## 11j. Guard one

A guard is an unresolved semantic alternative whose fast realization depends
on a fact (`law.guard.one`). Not an optimization artifact, type-check object,
or a reason to box everything.

- fact known → guard 0
- fact speculated from evidence → exact guard + exact slow alternative
- fact unknown → lawful general realization

Every guard retains the assumed fact, witness/evidence, recovery realization,
and provenance. Rare failure must not poison hot representation
(`law.error.cold`).

---

## 11k. Specialize budget

Specialize only when expected runtime gain exceeds compile cost + code size +
I-cache + startup (`law.specialize.budget`, `perf.worth`). Same semantic id;
multiple realizations only when profitable. Do not mint new semantic identities
for clones. Each specialization records applications, branches/allocs/indirects
removed, bytes added, compile time added.

---

## 11l. Internal ABI

Semantic pack → demanded physical slots → target ABI (`law.abi.internal`,
`law.abi.demand`). Known internal calls use an optimized internal ABI.
Foreign ABI only at an actual foreign boundary. Objectives: register
args/returns, aggregate elision, no tuple/sret/temp pack, tail-call
compatibility.

---

## 11m. Crash first / cost explain

Crash > wrong diagnostic > reject valid > optimization miss
(`law.crash.first`). Backend refusal names application id, missing fact,
consumer, expected producer. Every remaining box/alloc/indirect/copy/hash/tag
names the unresolved fact (`law.cost.explain`). Every compiler refusal —
parser, resolver, world, descriptor, realization, specialization,
vectorization — names the same four: entity/application, missing fact,
expected producer, consumer.

---

## 11n. Application consumer zero

Lowering and later stages consume application facts from the graph
(`law.application.consumer`). Forbidden independent derivation: subject,
operand identity, result identity, descriptor, effect, world requirement,
witness, demand, target. Consuming `ApplicationFact.relation` from the graph
while reconstructing adjacent fields from AST, host types, or callee text is
partial transfer, not closure. Downstream reconstructed application facts
target zero. The graph entity is identity — no three-coordinate record.

---

## 11o. Fact locality one

The graph remains authority. After an application is resolved, frequently
consumed facts live in compact application-local ranges or dense-id tables
(`law.fact.locality`). Do not re-query through global hash maps or repeated
edge scans on every lowering instruction. Semantic correctness must not
create compile-time query overhead.

---

## 11p. Grammar one

Exactly one executable grammar-fact owner (`law.grammar.one`). Canonical Idol
grammar facts are the authority. Generated Zig/C tables are a bridge
projection. `grammar.md` and Tree-sitter are human/editor projections from
that owner. A host `grammar_roles.zig` table is transitional and has a
deletion condition. Parser-local BinOp maps, spelling lists, and category
switches are reconstruction debt. Tree-sitter, LSP, MCP, and formatter
consume the same facts or generated projections.

---

## 11q. Control plane derived zero

Durable human status docs do not manually encode live HEAD, lane holder,
lock state, or dirty tree (`law.control.derived`). Those facts come from
git, claims, session state, and orient. Workstream definitions may live in
projections; live control-plane values may not.

---

## 12. Role noun zero

Do not evade ability rules with noun roles:

`reader`, `writer`, `runner`, `caller`, `encoder`, `decoder`, `serializer`,
`parser`, `formatter`, `checker`, `validator`, `builder`, `emitter`, `generator`,
`scanner`, `resolver`, `evaluator`, `interpreter`, `provider`, `producer`,
`consumer`, `receiver`, `sender`

when identity merely means “thing performing relation X.” Use actual subject +
relation.

---

## 13. Collision zero

Presumptively forbidden compiler semantic roles:

`router`, `gateway`, `dispatcher`, `registry`, `manager`, `factory`, `adapter`,
`broker`, `mediator`, `controller`, `coordinator`, `orchestrator`, `handler`,
`executor`, `engine`, `pipeline`, `scheduler`, `loader`, `bridge`, `shim`,
`proxy`, `wrapper`, `frontend`, `backend`, `context`, `session`, `service`,
`provider`, `driver`, `framework`, `container`

**Role is forbidden, not spelling.**

| Wrong role | Right decomposition |
|---|---|
| Routing | application resolution |
| Registration | graph facts |
| Context | closed fact set |
| Execution selection | demand + realization |
| Adaptation | foreign projection / realization |

---

## 14. Qualifier zero

Do not mint identities from qualifying facts:

`native`, `static`, `dynamic`, `sealed`, `guarded`, `foreign`, `local`, `global`,
`mutable`, `immutable`, `resolved`, `unresolved`, `generated`, `inferred`,
`boxed`, `unboxed`, `cached`, `active`, `ready`, `valid`, `invalid`, `readonly`,
`optimized`

Thus reject: `nativevalue`, `staticcall`, `dynamicvalue`, `generatednode`,
`validtype`, `resolvedrelation` — represent underlying id + fact.

---

## 15. Meta / organizational zero

Do not create semantic homes from generic organizational/meta vocabulary:

`core`, `base`, `common`, `shared`, `helper`, `util`, `utility`, `support`,
`misc`, `internal`, `foundation`, `platform`, `system`, `default`, `generic`,
`framework`, `algebra`, `model`, `layer`, `mechanism`, `schema`, `meta`

unless independently irreducible. If name means “stuff goes here,” semantic
ownership is unresolved.

---

## 16. Abbreviation zero

Do not invent abbreviations to evade naming law:

`ctx`, `mgr`, `cfg`, `req`, `res`, `msg`, `cmd`, `proc`, `buf`, `fmt`, `gen`,
`impl`, `util`, `tmp`, `aux`, `svc`

Allowed only if abbreviation itself is established irreducible domain term
(`abi`, `ffi`, `rpc`, `wasm`, `json` — still subject to semantic review).

---

## 17. Nil / presence

Ordinary absence: `nil`

**No** `absent`, `present`, `maybe`, `option`, `none`, `some`, `missing` for
ordinary absence. **No `has`.** Use value/search result + refinement.

---

## 18. Conversion / format

One conversion relation: `to`

**Conversion ladder** (shortest uniquely resolving form wins):

```text
level 0   enabled: bool = value          # graph records to(bool) when unique
level 1   value:to(target)               # ONLY when target is not inferable
migrate   to(target)(value) → value:to(target) → value
```

`to` is written **only** when the target conversion cannot be inferred from
graph-visible demand/context. There is no canonical `value:to()` rung — if the
relation is explicit and the target is uniquely inferable, spelling `to` adds
no information.

If demand uniquely determines target: `consume(value)`, not
`consume(value:to(target))`.

Do not create `cast`, `coerce`, `convert`, `into`, `stringify`, `encode` when
ordinary conversion suffices.

Parsing may remain distinct: `text:parse(json)`

Generic systems forbidden unless independently irreducible: `encoding`, `codec`,
`encoder`, `decoder`, `serialize`, `deserialize`, `marshal`, `unmarshal`,
`transcode`

Formats (`json`, `cbor`, `protobuf`, `pem`) may survive as descriptors if
irreducible.

---

## 18a. Source inference (SOURCE-INFER-ONE)

No source spelling should survive merely to restate a semantic fact the compiler
can already recover uniquely. This applies to `to`, relation/method names,
projections, explicit subjects, world/protocol witnesses, capture declarations,
and projection/injection composition — not conversion alone.

**SOURCE-INFER-ONE:** Every source token must contribute semantic information
that is **not** already uniquely recoverable from:

```text
subject
operands
result demand
descriptor demand
reachable exact facts
relation constraints
world/effect requirements
stage
provenance
control-flow refinement
```

If a spelling contributes no new semantic information: **omit it.**

If omission would leave more than one lawful semantic solution: spell **only**
the minimum fact needed to disambiguate.

If omission is compiler-unique but human-ambiguous: retain the meaningful
irreducible relation name.

Source syntax is a **disambiguation surface**, not a transcript of graph facts.

**Relation/method inference:** hierarchy is `no relation spelling` → `explicit
relation only when necessary`. `source:read()` stays explicit because
`source()` is human-ambiguous — `read` carries useful intent. `env("HOME")` is
better than `env:get("HOME")`. `f(x)` not `f:call(x)`.

**Projection inference:** do not write a projection merely because the compiler
internally has a projection edge. Keep `os.env("HOME")` only when it
disambiguates two different env values; when exactly one env is admitted and
obvious, `env("HOME")` is canonical. Progression: fully inferred → smallest
static projection required for uniqueness. Never fully-qualified-everything by
default.

**Conversion:** `to` is written **only** when the target conversion cannot be
inferred. There is no canonical `value:to()` rung. If demand uniquely determines
target: `consume(value)`, not `consume(value:to(target))`.

**INTERMEDIATE-ZERO:** do not name intermediate values used once when the chain
preserves semantic identity — chain relations directly. Retain a named
intermediate only when the name contributes semantic information the chain does
not (multiple consumers, or human-clarity place identity).

Do not spell relation wrappers that add no semantic choice: `f(x)`, not
`f:call(x)`; `table(key)`, not `table:get(key)`.

**Human clarity guard:** if compiler inference is unique but omission would make
the operation genuinely unclear to a human, retain the irreducible meaningful
relation (`source:read()` may remain).

Never preserve explicit syntax merely because compiler inference is not
implemented yet. Mark `IMPLEMENTATION-BLOCKED`, then implement inference. Do not
canonize the workaround.

**Graph fact deletion is NOT implied by source spelling deletion.** Inferred
relation, projection, conversion, witness, capture remain exact graph
ids/edges/facts.

**Canonical density objective:**

```text
MINIMUM SOURCE SPELLING
MAXIMUM GRAPH SEMANTICS
ZERO REDUNDANT REALIZATION
```

Gate every explicit source: `.to(`, explicit projection chain, helper binding
used once, `.get(`, `:call(`, world/injection declaration. Ask: WHAT INFORMATION
HERE COULD NOT HAVE BEEN INFERRED? No answer: delete spelling.

---

## 18b. Fact composition inference (FACT-COMPOSITION-INFER-ONE)

Projection, injection, capture, protocol satisfaction, world satisfaction,
descriptor refinement, and target selection are **graph facts**. Do not require
source syntax for them when they can be derived uniquely.

Explicit source projection exists only to disambiguate actual semantic choice.
Explicit source conversion exists only to disambiguate actual semantic choice.
Explicit world/protocol/injection declarations normally do **not** exist. The
graph is explicit; the source is not redundant.

Do not write:

```id
@{
    os.env
    io.stdout
}
```

merely because the graph needs those facts. Usage derives dependencies:

```id
stdout:write(env("HOME"))
```

The graph can contain projection, world requirement, witness, application,
relation, subject, and result demand without the programmer spelling that
bookkeeping.

**Source-density order** (complete collapse sequence):

```text
1. omit redundant binding
2. omit redundant relation
3. omit redundant projection
4. omit redundant conversion
5. omit redundant world/protocol composition
6. retain only minimum spelling for uniqueness + human meaning
```

Example collapse: `stdout:write(value:to(json))` → `stdout:write(value)` when
`write` uniquely demands the representation. The graph still records inferred
`to`; source deletion does not erase graph facts.

**Final:**

```text
IF THE GRAPH CAN KNOW IT, THE PROGRAMMER SHOULD NOT HAVE TO SAY IT.
IF DEMAND CAN SELECT IT, DO NOT SPELL IT.
IF ONE USE FOLLOWS ANOTHER LINEARLY, DO NOT NAME THE INTERMEDIATE.
IF QUALIFICATION DOES NOT DISAMBIGUATE, REMOVE IT.
IF PROJECTION DOES NOT DISAMBIGUATE, REMOVE IT.
IF INJECTION CAN BE DERIVED FROM USE, DO NOT EXPOSE IT.
SOURCE MINIMUM. GRAPH MAXIMUM. REALIZATION MINIMUM.
```

---

## 19. File / directory law

Directory implies table/home:

```text
gate/
    idiom.id    → gate, gate.idiom
```

File is member body. **Do not** redeclare filename/member inside.

Callable child whose parent is subject: `gate:idiom(diff)` — not `gate.idiom(diff)`

Source filesystem: ingestion + provenance only. After resolution, path has no
semantic lookup authority. Runtime filesystem authority is separate world/effect
matter. Source path never grants runtime filesystem authority.

---

## 20. World / universe / projection

- **World:** authority-bearing facts/witnesses
- **Universe:** closed compiler-internal fact set for body/application
- **Projection:** select exact facts preserving id/origin
- **Injection/composition:** make exact selected facts available to exact context/application

Do not create separate source systems for import, dependency injection, protocol
injection, world injection, mock injection, descriptor injection, stage injection,
capture injection — all reduce to exact fact edges + coherent composition.

Users normally do **not** write explicit world declarations. `@{ k=v }` is
world derivation by injection (`thing@{ k=v }` interjection), not an import,
dependency list, or universe-construction ceremony. Graph injection normally
has **zero** source syntax — usage derives exact world/protocol dependencies
(`stdout:write(env("HOME"))`, not an explicit `@{ os.env io.stdout }` block).
Explicit `@{ k=v }` injection exists only when fact composition is not uniquely
inferable from use.

Known authority witness → runtime abstraction cost 0. Missing → fail. Multiple
incomparable → ambiguity. No parent/default/global/nearest world.

---

## 21. Protocol

Protocol is demanded relation/application facts.

**Never ask:** is callable? is readable?

**Ask:** does subject admit relation/application satisfying demanded shape?

Static satisfaction is graph fact with runtime cost 0. No mandatory protocol
object, dictionary, vtable, or interface instance. Protocol satisfaction does
**not** grant world authority.

---

## 22. FTCFTW

Every physical cost must identify unresolved semantic possibility requiring it:
allocation, box, copy, tag, hash, indirect call, guard, runtime descriptor,
closure environment, world object, lock, atomic, materialized pack.

**Required zeros:**

| When | Cost must be zero |
|---|---|
| known shape | generic hash |
| exact target | indirect call |
| resolved binding | parent lookup |
| known capture set | capture discovery |
| nonescaping closure | heap env |
| singleton union | tag |
| unused result | materialization |
| known world witness | world dispatch/object |

---

## 23. SHC

Self-hosting means semantic authority transfer. Track earliest host-owned fact:
lexical identity, grammar, binding, relation, subject, descriptor, application,
graph, world/effect, demand, realization, machine.

Move producer into Idol. Disable old host producer.

Do **not** self-host stale architecture: module loader, scope chain, registry,
dispatcher, context object, string lookup.

---

## 24. Hard file / path rules

**Canonical project-owned source extension:** `.id`

New canonical `.id` is admitted.

**Retired / forbidden active project source extensions:** `.duo`, `.duon`, `.idsem`

No active generated/cache/source path may contain retired project identity.

**Forbidden active semantic directory concepts include:**

`std`, `lib` (as semantic namespace), `modules`, `namespaces`, `imports`,
`registry`, `registries`, `adapters`, `bridges`, `contexts`, `engines`, `pipelines`

Physical repository grouping may temporarily survive only if explicitly
**nonsemantic** and scheduled for removal/rehome.

Current canonical repository paths **should not** encode: pass numbers, gap numbers,
migration chronology, historical project identity, implementation strategy,
plural-cardinality homes.

---

## 25. Hard lexical regex gates

These are mechanical **pre-filters**. Semantic gates still apply afterward.

**Project-owned identifier base shape:** `^[a-z][a-z0-9]*$`

Lexical shape alone does **not** prove semantic validity.

| Pattern | Rejects |
|---|---|
| `[_A-Z-]` or `(?=.*[_A-Z-])` | separators / case |
| `(?i)(?:^|[_-])(pass\|phase\|gap)[-_]?[0-9]+(?:$|[_-])` | numeric/history taxonomy |
| `(?i)(duo\|duon\|idsem)` | retired project identity in active tree |
| `(?i)\.(duo\|duon\|idsem)$` | retired source extensions |
| `\b(function\|fun\|fn\|local\|let\|var\|const\|then\|do\|end\|import\|require\|req\|include\|module\|namespace)\b` | legacy keywords |
| `\.(get\|set\|call)\s*\(` | legacy ordinary access faces |
| `\b[a-z][a-z0-9.]*\s*\[[^\]]+\]` | bracket indexing **review trigger** |
| `(?i)(?:^|[^a-z0-9])(has\|contains\|exists\|present)\s*\(` | presence wrappers |
| `^[a-z0-9]*(able\|ible)$` | capability adjectives |
| `(?i)(?:EdgeKind\.\|\.)(run\|call\|invoke\|execute\|read\|write\|get\|set\|open\|close\|parse\|encode\|decode\|convert\|compile\|lower\|emit\|generate\|transform\|dispatch\|resolve\|load\|store)\b` | operational edge spellings |
| `(?i)(findFunc\|findByName\|lookupByName\|lookup_by_name\|name_index)` | semantic string dispatch **review** |
| `\b(std\|lib\|core)\.` | retired semantic namespace faces |
| `@(comp\|host\|runtime)\.` | compiler-host namespace in Idol |
| `(?i)\b(pass\s*[0-9]+\|gap[-_ ]?[0-9]+\|formerly\|legacy migration\|migrat(?:e\|ed\|ion) from)\b` | migration/history prose |

---

## 26. File-name regex gates

**Canonical project-owned `.id` filename:** `^[a-z][a-z0-9]*\.id$` (lexical only)

Reject filename separators/case: `[_A-Z-]`

Mashed compounds require **semantic segmentation review** — regex alone cannot
prove compounds.

**High-risk filename suffix/prefix review patterns:**

- `(?i)(reader|writer|runner|caller|encoder|decoder|parser|formatter|checker|validator|builder|emitter|generator|scanner|resolver|provider|producer|consumer)\.id$`
- `(?i)(router|gateway|dispatcher|registry|manager|factory|adapter|broker|mediator|controller|coordinator|orchestrator|handler|executor|engine|pipeline|scheduler|loader|bridge|shim|proxy|wrapper|frontend|backend|context|session|service|provider|framework|container)\.id$`
- `(?i)(callable|readable|writable|iterable|indexable|hashable|comparable|serializable|encodable|decodable|parseable|printable|executable|runnable|awaitable|seekable)\.id$`
- `(?i)(bytes|strings|fields|values|arguments|results|nodes|edges|captures|tests|gates|examples|fixtures|files|rules|worlds|protocols|descriptors|collections|contracts|encodings|formats)\.id$`
- `(?i)(pass|phase|gap)[-_]?[0-9]+`
- `(?i)(showcase|smoke|legacy|migration|deprecated|old|compat)`

These are **review/isolation triggers**, not always-semantic bans.

---

## 27. Directory-name regex gates

**Canonical semantic directory lexical shape:** `^[a-z][a-z0-9]*$`

**Obvious plurality roots (review — do not mechanically singularize):**

`(?i)^(tests|examples|fixtures|scripts|gates|gaps|agents|worlds|protocols|descriptors|encodings|collections)$`

**Organizational semantic namespace candidates:**

`(?i)^(std|lib|core|common|shared|utils?|helpers?|support|internal|framework|platform|system|modules?|namespaces?)$`

**Mediator/collision homes:**

`(?i)^(router|gateway|dispatcher|registry|manager|factory|adapter|broker|context|engine|pipeline|service|provider|bridge|wrapper)s?$`

Lexical detection is first pass only. **Semantic role determines final rejection.**

---

## 28. Plural regex is not sufficient

Do **not** globally reject every word ending in `s`. Some irreducible domain
words naturally end in `s`.

Plural law is semantic: **does the identity mean “many singular X”?**

Regex may flag `[a-z]+s` for review but **must not** be sole authority.

Likewise `*able`/`*ible` is stronger (project-owned capability adjectives are
categorically closed), but external domain nouns still require contextual review.

---

## 29. Semantic role gates — regex cannot replace these

For every new/changed project-owned identity ask:

1. What independently observable thing exists?
2. Is this name merely: capability, role, cardinality, transformation, direction,
   representation, stage, target, provenance, state, implementation technique,
   collection, or mediator responsibility?
3. Would changing one of those facts force renaming the entity?
4. Does existing Idol machinery already own the implied behavior?

If yes → reject/decompose. **No regex proves semantic irreducibility.**

---

## 30. Format / file content gate

Every changed `.id` file must be classified:

| Class | Requirement |
|---|---|
| CANONICAL | obey all source rules |
| FOREIGN | isolated; must not teach native syntax |
| NEGATIVE | preferably generated transiently; if stored, excluded from canonical corpus |
| GENERATED | derive from authority; must not become second law |
| TRANSITIONAL | explicit deletion prerequisite; may not be copied into new code |

No unclassified `.id` source.

---

## 31. Source-file content hard stops

A **new canonical** `.id` file may not introduce:

- `main` wrapper, import/module syntax
- `std`/`lib`/`core` namespace
- ordinary `[]` lookup, `.get`/`.set`/`.call` access
- `has`/`contains` presence wrapper
- `*able`/`*ible` protocol name
- encode/decode subsystem
- role-noun protocol object
- collision mediator object
- Pass/history prose, old project identity

A **new compiler graph change** may not introduce:

- operational edge kind
- semantic string dispatch, semantic path dispatch
- name-based descriptor identity
- reverse-edge duplicate authority
- parent-scope downstream lookup

---

## 32. Final agent stop rule

**STOP** if:

- only semantic key available is string
- only semantic locator is path
- relation id, subject id, or descriptor id is missing
- witness is missing
- easiest fix is registry/router/context
- easiest fix is operation edge, `.get(name)`, bracket-string dispatch, parent lookup, or compatibility fallback

**Fix producer. Do not patch consumer.**

---

## 33. Final compression

```text
NO CALL EDGE.  NO RUN EDGE.  NO READ EDGE.  NO WRITE EDGE.  NO EXECUTE EDGE.
RELATIONS ARE IDS.
APPLICATIONS POINT TO RELATIONS.
EDGES RECORD STRUCTURAL ROLES.
NO SEMANTIC STRING MATCH AFTER RESOLUTION.
NO SEMANTIC PATH MATCH AFTER RESOLUTION.
NO `.get` FOR IDOL ORDINARY ACCESS.
NO `[]` FOR IDOL ORDINARY ACCESS.
NO HAS.
NO *ABLE/*IBLE.
NO PLURAL-CARDINALITY IDENTITY.
NO ROLE-NOUN PROTOCOL OBJECTS.
NO MODULE.  NO IMPORT.
NO STD/LIB/CORE SEMANTIC HOP.
NO ROUTER/REGISTRY/CONTEXT/ENGINE SHADOW MACHINERY.
NO GENERIC ENCODING/CODEC KINGDOM.
FILESYSTEM = INGESTION + PROVENANCE.
RUNTIME FILE ACCESS = WORLD AUTHORITY.
WORLD = CLOSED SEMANTIC TABLE (AUTHORITY IS ONE FACT CLASS, NOT THE WORLD).
@ = CURRENT WORLD.
UNIVERSE = CLOSED FACT CLOSURE.
ACCESS = @member FACT SELECTION (@ IS THE ACCESSOR; NEVER @.member / @:member).
INJECTION = @{ k = v } DERIVES A CLOSED WORLD.
INTERJECTION = thing@{ k = v } EVALUATES A SUBTREE UNDER IT.
SOURCE MINIMUM.  GRAPH MAXIMUM.  REALIZATION MINIMUM.
IF YOU HAVE AN ID: DO NOT MATCH A NAME.
IF YOU HAVE AN EDGE: DO NOT SEARCH.
IF YOU HAVE A RELATION ID: DO NOT INVENT AN OPERATION EDGE.
IF A FACT IS MISSING: FIX ITS PRODUCER.
FTCFTW: LEARN EARLY. PRESERVE EXACTLY. DELETE COST.
SHC: MAKE IDOL PRODUCE THE FACTS ITSELF.
```

---

## Corpus

Git is history. Canonical current source/docs do not contain old project names,
`.duo`, Pass N, migration narrative, or historical syntax — unless describing a
currently executed bounded foreign/bootstrap boundary. Negative fixtures must not
train agents. See `docs/spec/corpus.md`.

---

## Live gate mapping (migration)

Until graph-owned admission (GAP-124), mechanical layers approximate sections
25–31:

| Layer | Owner |
|---|---|
| Lexical regex (§25) | `gate/idiom.id` added-line firewall |
| Path/filename regex (§26–27) | `gate/path.id` |
| Host namespace (§2, §25) | `gate/host.id` |
| Graph structural roles (§4) | `gate/graph.id` |
| Staged architecture census | `gate/architecture.id` |
| Semantic admission shape | `gate/admission.id` |

Negative controls in `gate/idiom.id` convict synonym evasions (`callable`,
`router`, `jsonencoder`, `tokenview`, operation-first faces, mashed gate
compounds) via semantic-role rows — not regex alone.

**Edge law reminder:** graph edges are structural roles — never operational edge
kinds (`.call`, `.run`, `.read`, …). Relation identity lives on the application;
edges connect application → relation/subject/operand/result.
