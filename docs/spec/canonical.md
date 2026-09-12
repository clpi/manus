# IDOL — blind one-pager / total canonical + repository law

| # | directive |
|---|---|
| 1 | **AUTHORITY:** This document is authoritative over repository accidents. |

| # | directive |
|---|---|
| 1 | **SUPREME one-page law:** `docs/spec/law.md` is authoritative over every document, including this one; wherever this file diverges from `docs/spec/law.md`, that page wins and this file must be corrected. `docs/spec/constitution.md` (C0) is the structured long-form expansion of `docs/spec/law.md` and the home of the `law.*` identities. |
| 2 | Readable bootstrap: `docs/spec/agent.md`. **Read this file before repository code.** |

| # | directive |
|---|---|
| 1 | Existing Git state may contain: |

- stale syntax
- stale names
- migration machinery
- old ontology
- host-language patterns
- historical tests/docs

| # | directive |
|---|---|
| 1 | **Do not infer language law from frequency in Git.** |

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

| # | directive |
|---|---|
| 1 | **Enforcement nuance:** regex owns **lexical impossibility**; semantic gates own **conceptual impossibility**. |
| 2 | Do not “solve” naming with one giant regexp — `broker` is as wrong as `router`, `bundle` can encode plurality without ending in `s`, and `tokenview` satisfies `^[a-z][a-z0-9]*$` while encoding two meanings. |

| # | directive |
|---|---|
| 1 | **Gate pipeline (mechanical → semantic):** |

```text
lexical regex
→ filename/path regex
→ syntax AST checks
→ identifier semantic-role classification
→ graph-structure checks
→ adversarial negative controls
```

| # | directive |
|---|---|
| 1 | Current migration implementation: `gate/idiom.id`, `gate/path.id`, `gate/host.id`, `gate/admission.id`, `gate/graph.id` — partial coverage until GAP-124 graph gate. |

| # | directive |
|---|---|

## 1. Canonical source

| # | directive |
|---|---|
| 1 | **Bindings:** |

```id
x = value
x: descriptor = value
```

| # | directive |
|---|---|
| 1 | **Functions:** |

```id
add = (a, b) a + b
normalize = (value) value:validate():normalize()
```

| # | directive |
|---|---|
| 1 | **Static projection:** `x.y` |

| # | directive |
|---|---|
| 1 | **Subject relation:** `x:y(...)` |

| # | directive |
|---|---|
| 1 | **Application:** `x(...)` — ordinary relation application and grouping |

| # | directive |
|---|---|
| 1 | **Computed projection:** `x[key]` |

| # | directive |
|---|---|
| 1 | **Canonical aggregate lookup:** |

```id
table[key]
env["HOME"]
args[1]
```

| # | directive |
|---|---|
| 1 | **Meaningful relation verbs remain:** |

```id
source:read()
path:open()
command:run()
stdout:write(text)
text:find(pattern)
text:parse(json)
```

| # | directive |
|---|---|
| 1 | Root body executes. |
| 2 | Tail expression returns. |
| 3 | Blocks are offside. |
| 4 | Comments use `#`. |
| 5 | Text uses `"..."`. |
| 6 | Interpolation uses `"{value}"`. |

| # | directive |
|---|---|

## 2. Canonical source zero list

| # | directive |
|---|---|
| 1 | Canonical Idol **must not introduce:** |

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

| # | directive |
|---|---|
| 1 | **Aggregate access must not be:** |

- `x:get(k)`, `x:set(k,v)`, `get(x, k)`, `set(x, k, v)` — computed projection is
  `x[k]`, and its place face is `x[k] = v`

| # | directive |
|---|---|
| 1 | **Ordinary application must not be:** |

- `f:call(x)`, `f.call(x)`, `table(key)` standing in for aggregate indexing

| # | directive |
|---|---|
| 1 | **Presence must not be reboxed as:** `has`, `contains`, `exists`, `present` |

| # | directive |
|---|---|
| 1 | **Use instead:** |

```id
value = x[key]
position = text:find(pattern)
# then nil/value refinement
```

| # | directive |
|---|---|

## 3. Application / table dispatch

| # | directive |
|---|---|
| 1 | One application algebra owns: |

- relation, subject, operand, result
- descriptor, demand, effect
- world requirement, witness
- stage, provenance, realization

| # | directive |
|---|---|
| 1 | There are **not** separate semantic kingdoms for: function call, method call, table call, accessor call, protocol call, builtin call, generic call. |

| # | directive |
|---|---|
| 1 | A table may admit application when the applied value is genuinely callable. `table(key)` does **not** mean aggregate indexing and does **not** secretly mean `table:get(key)`. |
| 2 | Aggregate access is computed projection `table[key]`; its read/write face is selected by demand: `table[key] = value` — no separate setter ontology. |
| 3 | The resolver determines application semantics from facts, never from call shape. |

| # | directive |
|---|---|

## 4. Edge law

| # | directive |
|---|---|
| 1 | Edges encode **structural semantic roles**. |

| # | directive |
|---|---|
| 1 | Permissible conceptual edge roles include only irreducible structural facts such as: `relation`, `subject`, `operand`, `result`, `member`, `binding`, `descriptor`, `projection`, `capture`, `provenance`, `origin`, `witness`, `demand`, `target`. |

| # | directive |
|---|---|
| 1 | Each still must prove irreducibility. |

| # | directive |
|---|---|
| 1 | **Never define operational edge kinds:** |

| # | directive |
|---|---|
| 1 | `run`, `call`, `invoke`, `execute`, `read`, `write`, `get`, `set`, `open`, `close`, `parse`, `encode`, `decode`, `convert`, `compile`, `lower`, `emit`, `generate`, `transform`, `dispatch`, `resolve`, `load`, `store` |

| # | directive |
|---|---|
| 1 | **Correct:** |

```text
application --relation--> read-id
application --subject--> file-id
application --result--> value-id
```

| # | directive |
|---|---|
| 1 | **Wrong:** |

```text
file --read--> value
application --call--> function
command --run--> process
```

| # | directive |
|---|---|
| 1 | Relation identity owns operation semantics. |

| # | directive |
|---|---|

## 5. Reverse edge zero

| # | directive |
|---|---|
| 1 | Do not create semantic inverse duplicates: |

- `calls` / `calledby`
- `contains` / `containedby`
- `uses` / `usedby`
- `reads` / `readby`
- `parent` / `child`

| # | directive |
|---|---|
| 1 | Store one authoritative relation. |
| 2 | Reverse traversal is query, index, or derived view — not second semantic truth. |

| # | directive |
|---|---|

## 6. Resolve once

| # | directive |
|---|---|
| 1 | Source spelling may participate in **initial resolution** only. |

| # | directive |
|---|---|
| 1 | After exact id exists, **never** recover meaning from spelling again. |

| # | directive |
|---|---|
| 1 | After resolution there is no: |

- `findFunc(name)`, `findByName(name)`
- semantic `.get(name)`, semantic `["name"]`
- callee string matching
- descriptor name identity matching
- path-based lookup, module lookup
- namespace / global / parent-scope / parent-world fallback

| # | directive |
|---|---|
| 1 | Use exact ids + graph edges. |
| 2 | If consumer lacks id: **fix producer.** Never patch consumer with a search. |

| # | directive |
|---|---|

## 7. String matching classification

| # | directive |
|---|---|
| 1 | Every compiler string comparison must be classified: |

| Class | Role |
|---|---|
| SOURCE | resolution-time token/spelling |
| FOREIGN | foreign lawset provenance |
| DATA | user/runtime data keys |
| DISPLAY | diagnostics/rendering |
| CACHE | candidate narrowing; exact facts must verify |
| SEMANTIC | **forbidden after resolution** |

| # | directive |
|---|---|
| 1 | **Legitimate:** JSON field key, env variable key, user text, source token spelling during resolution, diagnostic rendering. |

| # | directive |
|---|---|
| 1 | **Forbidden:** relation selected by `"add"`, descriptor identified by `"point"`, world selected by `"io"`, handler selected by `"read"`, target selected by path/name. |

| # | directive |
|---|---|

## 8. `.get` / `[]` host rule

| # | directive |
|---|---|
| 1 | Do **not** blindly ban host-language indexing. |

| # | directive |
|---|---|
| 1 | **Allowed:** |

- `graph.get(exact_id)`
- `rows[application_id]`
- `json.object.get("field")`
- runtime user-data map lookup

| # | directive |
|---|---|
| 1 | **Forbidden:** |

- `functions.get(name)`
- `descriptors.get(name)`
- `handlers.get(kind_name)`
- `worlds.get("io")`
- `semantic["read"]`

| # | directive |
|---|---|
| 1 | **Question:** accessing already-resolved storage/data? → allowed. |
| 2 | Recovering semantic meaning from label/path? → forbidden. |

| # | directive |
|---|---|

## 9. Naming — one word / one thing

| # | directive |
|---|---|
| 1 | Project-owned semantic identities are: lowercase, singular, one irreducible word. |

| # | directive |
|---|---|
| 1 | **No:** underscores, hyphens, camelCase, PascalCase, mashed compounds, numeric/historical taxonomy. |

| # | directive |
|---|---|
| 1 | **Still invalid (examples):** `tokenview`, `scanfiles`, `canonicalid`, `arm64check`, `perfledger`, `hostcensus`, `semanticgraph`, `nativevalue` |

| # | directive |
|---|---|
| 1 | Do not remove separator and call migration complete. **Decompose before rename.** |

| # | directive |
|---|---|

## 10. Plural zero

| # | directive |
|---|---|
| 1 | Semantic identity denotes **one thing**. |
| 2 | Plurality belongs to table membership, pack membership, shape, cardinality. |

| # | directive |
|---|---|
| 1 | **Presumptively forbidden semantic identities:** |

| # | directive |
|---|---|
| 1 | `bytes`, `strings`, `chars`, `fields`, `variants`, `tokens`, `nodes`, `edges`, `values`, `arguments`, `results`, `captures`, `tests`, `gates`, `examples`, `fixtures`, `files`, `rules`, `worlds`, `protocols`, `descriptors`, `collections`, `contracts`, `encodings`, `formats` |

| # | directive |
|---|---|
| 1 | Do not evade using `collection`, `bundle`, `suite`, `set`, `catalog`, `group`, `pool`, `container`, `family` when meaning is merely “many X.” |

| # | directive |
|---|---|
| 1 | A sequence of byte-like values is: value + element descriptor + shape + cardinality + stride/layout facts — not `bytes`. |
| 2 | Even `byte` must prove irreducibility. |

| # | directive |
|---|---|

## 11. Able zero

| # | directive |
|---|---|
| 1 | Project-owned identities encoding capability are forbidden: |

| # | directive |
|---|---|
| 1 | `callable`, `readable`, `writable`, `iterable`, `indexable`, `hashable`, `comparable`, `serializable`, `encodable`, `decodable`, `parseable`, `printable`, `executable`, `runnable`, `awaitable`, `seekable` |

| # | directive |
|---|---|
| 1 | **General rule:** `*able` / `*ible` forbidden when meaning is “admits relation/application X.” Use actual relation/application fact. |

| # | directive |
|---|---|
| 1 | **Exception — the boundary keyword `able(...)`:** the bare relation `able(r)` is NOT an adjective identity; it is the one explicit protocol/requirement boundary (`docs/spec/law.md` §9), e.g. `able(eq)`, `able(read)`, `able(to(str))`. |
| 2 | It is normally inferred and spelled only at a real boundary; it mints no trait, dictionary, or vtable. |
| 3 | A name ending in `able`/`ible` (`readable`, `iterable`) remains forbidden. |

| # | directive |
|---|---|

## 11a. Boolean-mirror zero (BOOLEAN-MIRROR-ZERO)

| # | directive |
|---|---|
| 1 | Do not store a boolean flag that merely restates a structural graph fact (`law.boolean.mirror.zero`). |

| Graph fact | Forbidden mirror |
|---|---|
| subject edge exists | `possessed = true` / `has_subject` |
| witness edge exists | `authorized = true` |
| capture edge exists | `captured = true` |
| descriptor edge exists | `typed = true` |
| application is applied | `callable = true` |
| identity participates | `operation = true` / `operation = false` |
| projection / binding / stage / target | `projected` `resolved` `imported` `native` `static` |

| # | directive |
|---|---|
| 1 | Absence of the fact is the answer. |
| 2 | Never `world = ""`, `world = nil`, `world = "none"`, or `world = false`. |

| # | directive |
|---|---|

## 11b. Catalog zero (CATALOG-ZERO)

| # | directive |
|---|---|
| 1 | Do not create a table whose primary purpose is to enumerate relations, descriptors, worlds, formats, handlers, operations, or capabilities (`law.catalog.zero`). |

| # | directive |
|---|---|
| 1 | If the items already have identities and facts in the graph, the catalog is a second authority and must be deleted. |
| 2 | Do not rename a catalog to preserve it (`seq` → `sequence` keeps the architecture). |

| # | directive |
|---|---|
| 1 | Deleted second authorities include: `lib/semantic/*` relation rows, `seq` catalog, `semantic/io`, `semantic/fs`, encoding/builtin/directive catalogs, producer relation ledger. |

| # | directive |
|---|---|
| 1 | Relation facts come from resolution. |
| 2 | Authority comes from world or witness facts on the application. |
| 3 | JSON is a format or descriptor, not a world. |

| # | directive |
|---|---|

## 11c. Magic-code zero (MAGIC-CODE-ZERO)

| # | directive |
|---|---|
| 1 | Do not reconstruct semantic identity from a numeric code, ordinal, or sentinel (`law.magic.zero`). |
| 2 | The producer already knows the rejection, kind, or outcome. |
| 3 | The consumer must not switch on `-103` or `@enumFromInt`. |

| # | directive |
|---|---|
| 1 | Forbidden reconstructions: |

- negative status → diagnostic (`lexErrorFromCode`)
- enum ordinal → host enum (`tokenKindFromOrdinal`)
- opcode → semantic relation
- foreign `$?` → run outcome

| # | directive |
|---|---|
| 1 | Carry the rejection-id, token-role-id, or outcome fact across the seam. |

| # | directive |
|---|---|

## 11d. Schema-one (SCHEMA-ONE)

| # | directive |
|---|---|
| 1 | One producer per record law (`law.schema.one`, `law.fact.producer.one`). |
| 2 | Host `RECORD_SLOTS` and positional field decoding are a second schema. |
| 3 | The producer projects the record; the consumer reads that projection. `duo_lexer_tokenize_full` / `duo_lexer_error_line` / `useDuoTokens` are bridge-death names (`law.bridge.death`). |

| # | directive |
|---|---|

## 11e. Main zero / generic-action zero / collision zero

- **MAIN-ZERO** (`law.main.zero`): file-scope result or the named step. Never
  `main: i64 = ()` wrapping another routine.
- **GENERIC-ACTION-ZERO** (`law.action.zero`): `run`, `execute`, `process`,
  `apply`, `perform`, `handle` as root/helper names require an actual semantic
  subject. `command:run()` is legitimate; `run: i64 = ()` is not.
- **FOUNDATIONAL-WORD-COLLISION-ZERO** (`law.foundation.zero`): do not use
  `apply`, `project`, `realize`, `resolve`, `bind`, `demand`, `witness`,
  `relation`, `subject`, `world`, `shape`, `descriptor` as generic helpers.

| # | directive |
|---|---|

## 11f. Evidence-subject one (EVIDENCE-SUBJECT-ONE)

| # | directive |
|---|---|
| 1 | Evidence identity and measured-program identity are separate facts. |
| 2 | A measurement commit must name `subject revision` and `evidence revision`. |
| 3 | Do not report metrics “at HEAD” unless the measured subject equals HEAD. |

| # | directive |
|---|---|
| 1 | Status authorities: |

- executed frontier → `docs/bootstrap.md`
- metrics interpretation → `docs/METRICS.md`
- revision-bound evidence → generated evidence artifact

| # | directive |
|---|---|
| 1 | Other reports are snapshots or projections. |
| 2 | They are not a second frontier. |

| # | directive |
|---|---|

## 11g. Oracle bound

| # | directive |
|---|---|
| 1 | A differential oracle covers the legacy-equivalent subset only. |
| 2 | Idol law is the constitution and the canonical lexer. |
| 3 | When Idol intentionally diverges, the host scanner must not veto the new behavior. `tokenizeHost()` remains deletable (`law.bridge.death`). |

| # | directive |
|---|---|

## 11h. Source-family one

| # | directive |
|---|---|
| 1 | Path suffix is provenance only (`law.family.one`). |
| 2 | One ingress authority produces the source-family fact. |
| 3 | Later components must not call `is_canonical_source(path)` or re-parse `.id` bytes to decide law. |
| 4 | Every lexer export takes family as an operand. `new()` does not read suffix bytes. |
| 5 | Production compile, fmt, and embed classify once via `sourceFacts` then `Lexer.initFacts`; they must not call `Lexer.init` or `is_canonical_source`. `route()`, parse, sema, and token-view consume `lex.family` / the family operand. |
| 6 | The executed Idol producer owns physical source forms, corpus-role admission, unlisted fallback, law, and provenance. |
| 7 | The host may normalize a filesystem path into provenance and bind producer-returned names to its bootstrap ABI; it may not own a roster or role→law mapping. `Lexer.init` remains a test convenience. |

| # | directive |
|---|---|

## 11i. Representation one

| # | directive |
|---|---|
| 1 | A semantic value has no physical representation until realization demand requires one (`law.representation.one`). |
| 2 | One producer decides width, layout, location, boxing, addressability, aggregation, and calling convention from descriptor × lifetime × alias × mutation × escape × demand × ABI × target. |

| # | directive |
|---|---|
| 1 | Downstream must not separately decide boxed / stack / register / heap / struct / SIMD. |
| 2 | Those are that one realization decision, not later repairs. |
| 3 | Every remaining physical structure must name its observation (`law.representation.demand`). |

| # | directive |
|---|---|

## 11j. Guard one

| # | directive |
|---|---|
| 1 | A guard is an unresolved semantic alternative whose fast realization depends on a fact (`law.guard.one`). |
| 2 | Not an optimization artifact, type-check object, or a reason to box everything. |

- fact known → guard 0
- fact speculated from evidence → exact guard + exact slow alternative
- fact unknown → lawful general realization

| # | directive |
|---|---|
| 1 | Every guard retains the assumed fact, witness/evidence, recovery realization, and provenance. |
| 2 | Rare failure must not poison hot representation (`law.error.cold`). |

| # | directive |
|---|---|

## 11k. Specialize budget

| # | directive |
|---|---|
| 1 | Specialize only when expected runtime gain exceeds compile cost + code size + I-cache + startup (`law.specialize.budget`, `perf.worth`). |
| 2 | Same semantic id; multiple realizations only when profitable. |
| 3 | Do not mint new semantic identities for clones. |
| 4 | Each specialization records applications, branches/allocs/indirects removed, bytes added, compile time added. |

| # | directive |
|---|---|

## 11l. Internal ABI

| # | directive |
|---|---|
| 1 | Semantic pack → demanded physical slots → target ABI (`law.abi.internal`, `law.abi.demand`). |
| 2 | Known internal calls use an optimized internal ABI. |
| 3 | Foreign ABI only at an actual foreign boundary. |
| 4 | Objectives: register args/returns, aggregate elision, no tuple/sret/temp pack, tail-call compatibility. |

| # | directive |
|---|---|

## 11m. Crash first / cost explain

| # | directive |
|---|---|
| 1 | Crash > wrong diagnostic > reject valid > optimization miss (`law.crash.first`). |
| 2 | Backend refusal names application id, missing fact, consumer, expected producer. |
| 3 | Every remaining box/alloc/indirect/copy/hash/tag names the unresolved fact (`law.cost.explain`). |
| 4 | Every compiler refusal — parser, resolver, world, descriptor, realization, specialization, vectorization — names the same four: entity/application, missing fact, expected producer, consumer. |

| # | directive |
|---|---|

## 11n. Application consumer zero

| # | directive |
|---|---|
| 1 | Lowering and later stages consume application facts from the graph (`law.application.consumer`). |
| 2 | Forbidden independent derivation: subject, operand identity, result identity, descriptor, effect, world requirement, witness, demand, target. |
| 3 | Consuming `ApplicationFact.relation` from the graph while reconstructing adjacent fields from AST, host types, or callee text is partial transfer, not closure. |
| 4 | Downstream reconstructed application facts target zero. |
| 5 | The graph entity is identity — no three-coordinate record. |

| # | directive |
|---|---|

## 11o. Fact locality one

| # | directive |
|---|---|
| 1 | The graph remains authority. |
| 2 | After an application is resolved, frequently consumed facts live in compact application-local ranges or dense-id tables (`law.fact.locality`). |
| 3 | Do not re-query through global hash maps or repeated edge scans on every lowering instruction. |
| 4 | Semantic correctness must not create compile-time query overhead. |

| # | directive |
|---|---|

## 11p. Grammar one

| # | directive |
|---|---|
| 1 | Exactly one executable grammar-fact owner (`law.grammar.one`). |
| 2 | Each source position has exactly one explicit or ingress-derived source law before lexing. |
| 3 | The owner projects that law into token identities, roles, precedence, and structural recognition. |
| 4 | Canonical Idol is the default projection for canonical `.id` source; it is not the authority for every admitted source law. |
| 5 | Generated Zig/C tables are bridge projections. `grammar.md`, Tree-sitter, and other editor/tooling artifacts are projections from that same owner. |
| 6 | A host `grammar_roles.zig` table is transitional and has a deletion condition. |
| 7 | Parser-local BinOp maps, spelling lists, category switches, grammar unions, try-parser selection, and world-selected grammar are reconstruction debt. |
| 8 | Worlds supply semantic context and authority only after recognition. |
| 9 | They never select grammar. |
| 10 | Parser, formatter, and any admitted editor/tooling consumer use the same law-qualified facts or generated projections. |

| # | directive |
|---|---|

## 11q. Control plane derived zero

| # | directive |
|---|---|
| 1 | Durable human status docs do not manually encode live HEAD, lane holder, lock state, or dirty tree (`law.control.derived`). |
| 2 | Those facts come from git, claims, session state, and orient. |
| 3 | Workstream definitions may live in projections; live control-plane values may not. |

| # | directive |
|---|---|

## 12. Role noun zero

| # | directive |
|---|---|
| 1 | Do not evade ability rules with noun roles: |

| # | directive |
|---|---|
| 1 | `reader`, `writer`, `runner`, `caller`, `encoder`, `decoder`, `serializer`, `parser`, `formatter`, `checker`, `validator`, `builder`, `emitter`, `generator`, `scanner`, `resolver`, `evaluator`, `interpreter`, `provider`, `producer`, `consumer`, `receiver`, `sender` |

| # | directive |
|---|---|
| 1 | when identity merely means “thing performing relation X.” Use actual subject + relation. |

| # | directive |
|---|---|

## 13. Collision zero

| # | directive |
|---|---|
| 1 | Presumptively forbidden compiler semantic roles: |

| # | directive |
|---|---|
| 1 | `router`, `gateway`, `dispatcher`, `registry`, `manager`, `factory`, `adapter`, `broker`, `mediator`, `controller`, `coordinator`, `orchestrator`, `handler`, `executor`, `engine`, `pipeline`, `scheduler`, `loader`, `bridge`, `shim`, `proxy`, `wrapper`, `frontend`, `backend`, `context`, `session`, `service`, `provider`, `driver`, `framework`, `container` |

| # | directive |
|---|---|
| 1 | **Role is forbidden, not spelling.** |

| Wrong role | Right decomposition |
|---|---|
| Routing | application resolution |
| Registration | graph facts |
| Context | closed fact set |
| Execution selection | demand + realization |
| Adaptation | foreign projection / realization |

| # | directive |
|---|---|

## 14. Qualifier zero

| # | directive |
|---|---|
| 1 | Do not mint identities from qualifying facts: |

| # | directive |
|---|---|
| 1 | `native`, `static`, `dynamic`, `sealed`, `guarded`, `foreign`, `local`, `global`, `mutable`, `immutable`, `resolved`, `unresolved`, `generated`, `inferred`, `boxed`, `unboxed`, `cached`, `active`, `ready`, `valid`, `invalid`, `readonly`, `optimized` |

| # | directive |
|---|---|
| 1 | Thus reject: `nativevalue`, `staticcall`, `dynamicvalue`, `generatednode`, `validtype`, `resolvedrelation` — represent underlying id + fact. |

| # | directive |
|---|---|

## 15. Meta / organizational zero

| # | directive |
|---|---|
| 1 | Do not create semantic homes from generic organizational/meta vocabulary: |

| # | directive |
|---|---|
| 1 | `core`, `base`, `common`, `shared`, `helper`, `util`, `utility`, `support`, `misc`, `internal`, `foundation`, `platform`, `system`, `default`, `generic`, `framework`, `algebra`, `model`, `layer`, `mechanism`, `schema`, `meta` |

| # | directive |
|---|---|
| 1 | unless independently irreducible. |
| 2 | If name means “stuff goes here,” semantic ownership is unresolved. |

| # | directive |
|---|---|

## 16. Abbreviation zero

| # | directive |
|---|---|
| 1 | Do not invent abbreviations to evade naming law: |

| # | directive |
|---|---|
| 1 | `ctx`, `mgr`, `cfg`, `req`, `res`, `msg`, `cmd`, `proc`, `buf`, `fmt`, `gen`, `impl`, `util`, `tmp`, `aux`, `svc` |

| # | directive |
|---|---|
| 1 | Allowed only if abbreviation itself is established irreducible domain term (`abi`, `ffi`, `rpc`, `wasm`, `json` — still subject to semantic review). |

| # | directive |
|---|---|

## 17. Nil / presence

| # | directive |
|---|---|
| 1 | Ordinary absence: `nil` |

| # | directive |
|---|---|
| 1 | **No** `absent`, `present`, `maybe`, `option`, `none`, `some`, `missing` for ordinary absence. **No `has`.** Use value/search result + refinement. |

| # | directive |
|---|---|

## 18. Conversion / format

| # | directive |
|---|---|
| 1 | One conversion relation: `to` |

| # | directive |
|---|---|
| 1 | **Conversion ladder** (shortest uniquely resolving form wins): |

```text
level 0   enabled: bool = value          # graph records to(bool) when unique
level 1   value:to(target)               # ONLY when target is not inferable
migrate   to(target)(value) → value:to(target) → value
```

| # | directive |
|---|---|
| 1 | `to` is written **only** when the target conversion cannot be inferred from graph-visible demand/context. |
| 2 | There is no canonical `value:to()` rung — if the relation is explicit and the target is uniquely inferable, spelling `to` adds no information. |

| # | directive |
|---|---|
| 1 | If demand uniquely determines target: `consume(value)`, not `consume(value:to(target))`. |

| # | directive |
|---|---|
| 1 | Do not create `cast`, `coerce`, `convert`, `into`, `stringify`, `encode` when ordinary conversion suffices. |

| # | directive |
|---|---|
| 1 | Parsing may remain distinct: `text:parse(json)` |

| # | directive |
|---|---|
| 1 | Generic systems forbidden unless independently irreducible: `encoding`, `codec`, `encoder`, `decoder`, `serialize`, `deserialize`, `marshal`, `unmarshal`, `transcode` |

| # | directive |
|---|---|
| 1 | Formats (`json`, `cbor`, `protobuf`, `pem`) may survive as descriptors if irreducible. |

| # | directive |
|---|---|

## 18a. Source inference (SOURCE-INFER-ONE)

| # | directive |
|---|---|
| 1 | No source spelling should survive merely to restate a semantic fact the compiler can already recover uniquely. |
| 2 | This applies to `to`, relation/method names, projections, explicit subjects, world/protocol witnesses, capture declarations, and projection/injection composition — not conversion alone. |

| # | directive |
|---|---|
| 1 | **SOURCE-INFER-ONE:** Every source token must contribute semantic information that is **not** already uniquely recoverable from: |

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

| # | directive |
|---|---|
| 1 | If a spelling contributes no new semantic information: **omit it.** |

| # | directive |
|---|---|
| 1 | If omission would leave more than one lawful semantic solution: spell **only** the minimum fact needed to disambiguate. |

| # | directive |
|---|---|
| 1 | If omission is compiler-unique but human-ambiguous: retain the meaningful irreducible relation name. |

| # | directive |
|---|---|
| 1 | Source syntax is a **disambiguation surface**, not a transcript of graph facts. |

| # | directive |
|---|---|
| 1 | **Relation/method inference:** hierarchy is `no relation spelling` → `explicit relation only when necessary`. `source:read()` stays explicit because `source()` is human-ambiguous — `read` carries useful intent. `env["HOME"]` is better than `env:get("HOME")`. `f(x)` not `f:call(x)`. |

| # | directive |
|---|---|
| 1 | **Projection inference:** do not write a projection merely because the compiler internally has a projection edge. |
| 2 | Keep `os.env["HOME"]` only when it disambiguates two different env values; when exactly one env is admitted and obvious, `env["HOME"]` is canonical. |
| 3 | Progression: fully inferred → smallest static projection required for uniqueness. |
| 4 | Never fully-qualified-everything by default. |

| # | directive |
|---|---|
| 1 | **Conversion:** `to` is written **only** when the target conversion cannot be inferred. |
| 2 | There is no canonical `value:to()` rung. |
| 3 | If demand uniquely determines target: `consume(value)`, not `consume(value:to(target))`. |

| # | directive |
|---|---|
| 1 | **INTERMEDIATE-ZERO:** do not name intermediate values used once when the chain preserves semantic identity — chain relations directly. |
| 2 | Retain a named intermediate only when the name contributes semantic information the chain does not (multiple consumers, or human-clarity place identity). |

| # | directive |
|---|---|
| 1 | Do not spell relation wrappers that add no semantic choice: `f(x)`, not `f:call(x)`; `table[key]`, not `table:get(key)`. |

| # | directive |
|---|---|
| 1 | **Human clarity guard:** if compiler inference is unique but omission would make the operation genuinely unclear to a human, retain the irreducible meaningful relation (`source:read()` may remain). |

| # | directive |
|---|---|
| 1 | Never preserve explicit syntax merely because compiler inference is not implemented yet. |
| 2 | Mark `IMPLEMENTATION-BLOCKED`, then implement inference. |
| 3 | Do not canonize the workaround. |

| # | directive |
|---|---|
| 1 | **Graph fact deletion is NOT implied by source spelling deletion.** Inferred relation, projection, conversion, witness, capture remain exact graph ids/edges/facts. |

| # | directive |
|---|---|
| 1 | **Canonical density objective:** |

```text
MINIMUM SOURCE SPELLING
MAXIMUM GRAPH SEMANTICS
ZERO REDUNDANT REALIZATION
```

| # | directive |
|---|---|
| 1 | Gate every explicit source: `.to(`, explicit projection chain, helper binding used once, `.get(`, `:call(`, world/injection declaration. |
| 2 | Ask: WHAT INFORMATION HERE COULD NOT HAVE BEEN INFERRED? |
| 3 | No answer: delete spelling. |

| # | directive |
|---|---|

## 18b. Fact composition inference (FACT-COMPOSITION-INFER-ONE)

| # | directive |
|---|---|
| 1 | Projection, injection, capture, protocol satisfaction, world satisfaction, descriptor refinement, and target selection are **graph facts**. |
| 2 | Do not require source syntax for them when they can be derived uniquely. |

| # | directive |
|---|---|
| 1 | Explicit source projection exists only to disambiguate actual semantic choice. |
| 2 | Explicit source conversion exists only to disambiguate actual semantic choice. |
| 3 | Explicit world/protocol/injection declarations normally do **not** exist. |
| 4 | The graph is explicit; the source is not redundant. |

| # | directive |
|---|---|
| 1 | Do not write: |

```id
@{
    os.env
    io.stdout
}
```

| # | directive |
|---|---|
| 1 | merely because the graph needs those facts. |
| 2 | Usage derives dependencies: |

```id
stdout:write(env["HOME"])
```

| # | directive |
|---|---|
| 1 | The graph can contain projection, world requirement, witness, application, relation, subject, and result demand without the programmer spelling that bookkeeping. |

| # | directive |
|---|---|
| 1 | **Source-density order** (complete collapse sequence): |

```text
1. omit redundant binding
2. omit redundant relation
3. omit redundant projection
4. omit redundant conversion
5. omit redundant world/protocol composition
6. retain only minimum spelling for uniqueness + human meaning
```

| # | directive |
|---|---|
| 1 | Example collapse: `stdout:write(value:to(json))` → `stdout:write(value)` when `write` uniquely demands the representation. |
| 2 | The graph still records inferred `to`; source deletion does not erase graph facts. |

| # | directive |
|---|---|
| 1 | **Final:** |

```text
IF THE GRAPH CAN KNOW IT, THE PROGRAMMER SHOULD NOT HAVE TO SAY IT.
IF DEMAND CAN SELECT IT, DO NOT SPELL IT.
IF ONE USE FOLLOWS ANOTHER LINEARLY, DO NOT NAME THE INTERMEDIATE.
IF QUALIFICATION DOES NOT DISAMBIGUATE, REMOVE IT.
IF PROJECTION DOES NOT DISAMBIGUATE, REMOVE IT.
IF INJECTION CAN BE DERIVED FROM USE, DO NOT EXPOSE IT.
SOURCE MINIMUM. GRAPH MAXIMUM. REALIZATION MINIMUM.
```

| # | directive |
|---|---|

## 19. File / directory law

| # | directive |
|---|---|
| 1 | Directory implies table/home: |

```text
gate/
    idiom.id    → gate, gate.idiom
```

| # | directive |
|---|---|
| 1 | File is member body. **Do not** redeclare filename/member inside. |

| # | directive |
|---|---|
| 1 | Callable child whose parent is subject: `gate:idiom(diff)` — not `gate.idiom(diff)` |

| # | directive |
|---|---|
| 1 | Source filesystem: ingestion + provenance only. |
| 2 | After resolution, path has no semantic lookup authority. |
| 3 | Runtime filesystem authority is separate world/effect matter. |
| 4 | Source path never grants runtime filesystem authority. |

| # | directive |
|---|---|

## 20. World / universe / projection

- **World:** authority-bearing facts/witnesses
- **Universe:** closed compiler-internal fact set for body/application
- **Projection:** select exact facts preserving id/origin
- **Injection/composition:** make exact selected facts available to exact context/application

| # | directive |
|---|---|
| 1 | Do not create separate source systems for import, dependency injection, protocol injection, world injection, mock injection, descriptor injection, stage injection, capture injection — all reduce to exact fact edges + coherent composition. |

| # | directive |
|---|---|
| 1 | Users normally do **not** write explicit world declarations. `@{ k=v }` is world derivation by injection (`thing@{ k=v }` interjection), not an import, dependency list, or universe-construction ceremony. |
| 2 | Graph injection normally has **zero** source syntax — usage derives exact world/protocol dependencies (`stdout:write(env["HOME"])`, not an explicit `@{ os.env io.stdout }` block). |
| 3 | Explicit `@{ k=v }` injection exists only when fact composition is not uniquely inferable from use. |

| # | directive |
|---|---|
| 1 | Known authority witness → runtime abstraction cost 0. |
| 2 | Missing → fail. |
| 3 | Multiple incomparable → ambiguity. |
| 4 | No parent/default/global/nearest world. |

| # | directive |
|---|---|

## 21. Protocol

| # | directive |
|---|---|
| 1 | Protocol is demanded relation/application facts. |

| # | directive |
|---|---|
| 1 | **Never ask:** is callable? is readable? |

| # | directive |
|---|---|
| 1 | **Ask:** does subject admit relation/application satisfying demanded shape? |

| # | directive |
|---|---|
| 1 | Static satisfaction is graph fact with runtime cost 0. |
| 2 | No mandatory protocol object, dictionary, vtable, or interface instance. |
| 3 | Protocol satisfaction does **not** grant world authority. |

| # | directive |
|---|---|

## 22. FTCFTW

| # | directive |
|---|---|
| 1 | Every physical cost must identify unresolved semantic possibility requiring it: allocation, box, copy, tag, hash, indirect call, guard, runtime descriptor, closure environment, world object, lock, atomic, materialized pack. |

| # | directive |
|---|---|
| 1 | **Required zeros:** |

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

| # | directive |
|---|---|

## 23. SHC

| # | directive |
|---|---|
| 1 | Self-hosting means semantic authority transfer. |
| 2 | Track earliest host-owned fact: lexical identity, grammar, binding, relation, subject, descriptor, application, graph, world/effect, demand, realization, machine. |

| # | directive |
|---|---|
| 1 | Move producer into Idol. |
| 2 | Disable old host producer. |

| # | directive |
|---|---|
| 1 | Do **not** self-host stale architecture: module loader, scope chain, registry, dispatcher, context object, string lookup. |

| # | directive |
|---|---|

## 24. Hard file / path rules

| # | directive |
|---|---|
| 1 | **Canonical project-owned source extension:** `.id` |

| # | directive |
|---|---|
| 1 | New canonical `.id` is admitted. |

| # | directive |
|---|---|
| 1 | **Retired / forbidden active project source extensions:** `.duo`, `.duon`, `.idsem` |

| # | directive |
|---|---|
| 1 | No active generated/cache/source path may contain retired project identity. |

| # | directive |
|---|---|
| 1 | **Forbidden active semantic directory concepts include:** |

| # | directive |
|---|---|
| 1 | `std`, `lib` (as semantic namespace), `modules`, `namespaces`, `imports`, `registry`, `registries`, `adapters`, `bridges`, `contexts`, `engines`, `pipelines` |

| # | directive |
|---|---|
| 1 | Physical repository grouping may temporarily survive only if explicitly **nonsemantic** and scheduled for removal/rehome. |

| # | directive |
|---|---|
| 1 | Current canonical repository paths **should not** encode: pass numbers, gap numbers, migration chronology, historical project identity, implementation strategy, plural-cardinality homes. |

| # | directive |
|---|---|

## 25. Hard lexical regex gates

| # | directive |
|---|---|
| 1 | These are mechanical **pre-filters**. |
| 2 | Semantic gates still apply afterward. |

| # | directive |
|---|---|
| 1 | **Project-owned identifier base shape:** `^[a-z][a-z0-9]*$` |

| # | directive |
|---|---|
| 1 | Lexical shape alone does **not** prove semantic validity. |

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

| # | directive |
|---|---|

## 26. File-name regex gates

| # | directive |
|---|---|
| 1 | **Canonical project-owned `.id` filename:** `^[a-z][a-z0-9]*\.id$` (lexical only) |

| # | directive |
|---|---|
| 1 | Reject filename separators/case: `[_A-Z-]` |

| # | directive |
|---|---|
| 1 | Mashed compounds require **semantic segmentation review** — regex alone cannot prove compounds. |

| # | directive |
|---|---|
| 1 | **High-risk filename suffix/prefix review patterns:** |

- `(?i)(reader|writer|runner|caller|encoder|decoder|parser|formatter|checker|validator|builder|emitter|generator|scanner|resolver|provider|producer|consumer)\.id$`
- `(?i)(router|gateway|dispatcher|registry|manager|factory|adapter|broker|mediator|controller|coordinator|orchestrator|handler|executor|engine|pipeline|scheduler|loader|bridge|shim|proxy|wrapper|frontend|backend|context|session|service|provider|framework|container)\.id$`
- `(?i)(callable|readable|writable|iterable|indexable|hashable|comparable|serializable|encodable|decodable|parseable|printable|executable|runnable|awaitable|seekable)\.id$`
- `(?i)(bytes|strings|fields|values|arguments|results|nodes|edges|captures|tests|gates|examples|fixtures|files|rules|worlds|protocols|descriptors|collections|contracts|encodings|formats)\.id$`
- `(?i)(pass|phase|gap)[-_]?[0-9]+`
- `(?i)(showcase|smoke|legacy|migration|deprecated|old|compat)`

| # | directive |
|---|---|
| 1 | These are **review/isolation triggers**, not always-semantic bans. |

| # | directive |
|---|---|

## 27. Directory-name regex gates

| # | directive |
|---|---|
| 1 | **Canonical semantic directory lexical shape:** `^[a-z][a-z0-9]*$` |

| # | directive |
|---|---|
| 1 | **Obvious plurality roots (review — do not mechanically singularize):** |

| # | directive |
|---|---|
| 1 | `(?i)^(tests\|examples\|fixtures\|scripts\|gates\|gaps\|agents\|worlds\|protocols\|descriptors\|encodings\|collections)$` |

| # | directive |
|---|---|
| 1 | **Organizational semantic namespace candidates:** |

| # | directive |
|---|---|
| 1 | `(?i)^(std\|lib\|core\|common\|shared\|utils?\|helpers?\|support\|internal\|framework\|platform\|system\|modules?\|namespaces?)$` |

| # | directive |
|---|---|
| 1 | **Mediator/collision homes:** |

| # | directive |
|---|---|
| 1 | `(?i)^(router\|gateway\|dispatcher\|registry\|manager\|factory\|adapter\|broker\|context\|engine\|pipeline\|service\|provider\|bridge\|wrapper)s?$` |

| # | directive |
|---|---|
| 1 | Lexical detection is first pass only. **Semantic role determines final rejection.** |

| # | directive |
|---|---|

## 28. Plural regex is not sufficient

| # | directive |
|---|---|
| 1 | Do **not** globally reject every word ending in `s`. |
| 2 | Some irreducible domain words naturally end in `s`. |

| # | directive |
|---|---|
| 1 | Plural law is semantic: **does the identity mean “many singular X”?** |

| # | directive |
|---|---|
| 1 | Regex may flag `[a-z]+s` for review but **must not** be sole authority. |

| # | directive |
|---|---|
| 1 | Likewise `*able`/`*ible` is stronger (project-owned capability adjectives are categorically closed), but external domain nouns still require contextual review. |

| # | directive |
|---|---|

## 29. Semantic role gates — regex cannot replace these

| # | directive |
|---|---|
| 1 | For every new/changed project-owned identity ask: |

1. What independently observable thing exists?
2. Is this name merely: capability, role, cardinality, transformation, direction,
   representation, stage, target, provenance, state, implementation technique,
   collection, or mediator responsibility?
3. Would changing one of those facts force renaming the entity?
4. Does existing Idol machinery already own the implied behavior?

| # | directive |
|---|---|
| 1 | If yes → reject/decompose. **No regex proves semantic irreducibility.** |

| # | directive |
|---|---|

## 30. Format / file content gate

| # | directive |
|---|---|
| 1 | Every changed `.id` file must be classified: |

| Class | Requirement |
|---|---|
| CANONICAL | obey all source rules |
| FOREIGN | isolated; must not teach native syntax |
| NEGATIVE | preferably generated transiently; if stored, excluded from canonical corpus |
| GENERATED | derive from authority; must not become second law |
| TRANSITIONAL | explicit deletion prerequisite; may not be copied into new code |

| # | directive |
|---|---|
| 1 | No unclassified `.id` source. |

| # | directive |
|---|---|

## 31. Source-file content hard stops

| # | directive |
|---|---|
| 1 | A **new canonical** `.id` file may not introduce: |

- `main` wrapper, import/module syntax
- `std`/`lib`/`core` namespace
- `table(key)` or other `()` standing in for aggregate indexing; `.get`/`.set`/`.call` access
- `has`/`contains` presence wrapper
- `*able`/`*ible` protocol name
- encode/decode subsystem
- role-noun protocol object
- collision mediator object
- Pass/history prose, old project identity

| # | directive |
|---|---|
| 1 | A **new compiler graph change** may not introduce: |

- operational edge kind
- semantic string dispatch, semantic path dispatch
- name-based descriptor identity
- reverse-edge duplicate authority
- parent-scope downstream lookup

| # | directive |
|---|---|

## 32. Final agent stop rule

| # | directive |
|---|---|
| 1 | **STOP** if: |

- only semantic key available is string
- only semantic locator is path
- relation id, subject id, or descriptor id is missing
- witness is missing
- easiest fix is registry/router/context
- easiest fix is operation edge, `.get(name)`, bracket-string dispatch, parent lookup, or compatibility fallback

| # | directive |
|---|---|
| 1 | **Fix producer. |
| 2 | Do not patch consumer.** |

| # | directive |
|---|---|

## 33. Final compression

```text
NO CALL EDGE.  NO RUN EDGE.  NO READ EDGE.  NO WRITE EDGE.  NO EXECUTE EDGE.
RELATIONS ARE IDS.
APPLICATIONS POINT TO RELATIONS.
EDGES RECORD STRUCTURAL ROLES.
NO SEMANTIC STRING MATCH AFTER RESOLUTION.
NO SEMANTIC PATH MATCH AFTER RESOLUTION.
NO `.get` FOR IDOL ORDINARY ACCESS.
NO `()` FOR AGGREGATE INDEXING — computed projection is `[]` only.
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

| # | directive |
|---|---|

## Corpus

| # | directive |
|---|---|
| 1 | Git is history. |
| 2 | Canonical current source/docs do not contain old project names, `.duo`, Pass N, migration narrative, or historical syntax — unless describing a currently executed bounded foreign/bootstrap boundary. |
| 3 | Negative fixtures must not train agents. |
| 4 | See `docs/spec/corpus.md`. |

| # | directive |
|---|---|

## Live gate mapping (migration)

| # | directive |
|---|---|
| 1 | Until graph-owned admission (GAP-124), mechanical layers approximate sections 25–31: |

| Layer | Owner |
|---|---|
| Lexical regex (§25) | `gate/idiom.id` added-line firewall |
| Path/filename regex (§26–27) | `gate/path.id` |
| Host namespace (§2, §25) | `gate/host.id` |
| Graph structural roles (§4) | `gate/graph.id` |
| Staged architecture census | `gate/architecture.id` |
| Semantic admission shape | `gate/admission.id` |

| # | directive |
|---|---|
| 1 | Negative controls in `gate/idiom.id` convict synonym evasions (`callable`, `router`, `jsonencoder`, `tokenview`, operation-first faces, mashed gate compounds) via semantic-role rows — not regex alone. |

| # | directive |
|---|---|
| 1 | **Edge law reminder:** graph edges are structural roles — never operational edge kinds (`.call`, `.run`, `.read`, …). |
| 2 | Relation identity lives on the application; edges connect application → relation/subject/operand/result. |
