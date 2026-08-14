# WORKSTREAM DEBT REGISTER

PROJECTION — not authority. Authority chain:
- Semantic law: `docs/spec/constitution.md`
- Executed frontier: `docs/bootstrap.md`
- Metric interpretation: `docs/METRICS.md`
- Realization architecture: `docs/spec/realization.md`
- Measurements: `evidence/EVIDENCE_BUNDLE.md`

EVIDENCE-SUBJECT-ONE (`law.control.derived`): this register does **not**
record live HEAD, dirty tree, or lane holders. Obtain those from `git`,
`.agents/session/claims/`, `scripts/ledger/claim.id`, and
`tools/node/dev/orient`. Bind every evidence claim to the revision that
was actually measured.

Compass: `.agents/TECH_DEBT_WORKSTREAM.md`
1–35 index: `docs/spec/realization.md` (projection, not C0)

**Live HEAD / lane holders / dirty:** `evidence/HEAD.txt` via orient,
`scripts/ledger/claim.id` — never hand-pasted here (`law.control.derived`).

## Audit verdict (2026-08-13)

**Closed / materially improved at live tree**

- Production `tokenize()` route; host `tokenizeHost()` differential-only
- `lib/semantic/*` catalog deleted (CATALOG-ZERO)
- Host `RECORD_SLOTS` / magic ordinals / rejection-code mapping deleted;
  producer queries + `bindKindSchema` bind-once (bridge with deletion gate)
- `ApplicationFact.relation` consumed via `graph.applicationRelation` in lowering
- `lib/compiler/application.id` decomposed to role docs (APPLICATION-CONSUMER-ZERO)
- Storage class demoted; causal DNB / backend refusal pattern improved

**P0 remaining (authority before FTCFTW performance claims)**

1. source-family off host suffix/path (`law.family.one`)
2. GAP-145 close — literal zero on dead `KIND_STRING_LIT` / `.string_lit`, not merely unused
3. host `TokenKind` + `bindKindSchema` bridge death (token-role-id endpoint)
4. GAP-134 single grammar authority — `grammar_roles.zig` transitional only
5. Tree-sitter from same grammar owner (never parallel authority)
6. parser SHC after 2–5
7. binding/resolver graph authority
8. graph ontology reduction (tags → facts; do not rename-only)
9. world/effect/witness facts
10. demand producer (REPRESENTATION-ONE blocked until demand executes)
11. direct backend crashes → 0 (`law.crash.first`)
12. integrated build/test remeasure at current revision — not assumed green
13. compiler B

**Phase shift:** from “remove wrong ontology” to “one ontology produces every
fact end-to-end.” Next gates measure **application fact provenance completeness**
(`scripts/ledger/application.id`) and **graph sovereignty**
(`scripts/ledger/graph.id`) — tag authority, fact cardinality, AST backedges,
not merely absence of forbidden names.

**GRAPH-SOVEREIGNTY** is the highest-impact milestone after GAP-145/GAP-134:
the graph must become the semantic spine, not a host-shaped god-record with
tags that still decide meaning (`law.tag.authority`, `law.graph.sovereignty`).

Each workstream item maps to measurable criteria. No claim is accepted
without binding to exact HEAD, dirty state, input, expected/actual result,
and environment.

## Scoped envelope A–AZ → eight lanes

| Letters | Lane | Focus |
|---|---|---|
| A, B, C, D, AE, AW + P0.1–3 | 1 Ingress + lexical SHC | source-family (`law.family.one`), GAP-145, producer token schema, magic-code/ordinal zero, bridge copies, oracle bounds |
| E, F + P0.4–5 | 2 Grammar + parser SHC | GAP-134 roles, immutable token view, Idol parser facts (no AST kingdom) |
| G–M + P0.6–8 | 3 Resolver + graph | exact binding/application/descriptor/capture/world/witness; demand facts for lane 4 |
| N + P1.10–12, 18 | 4 Demand + specialization | return/field demand; REPRESENTATION-ONE; specialize-budget; internal ABI; packs |
| O–Z + P1.11–24 | 5 Memory + effects | boxing, guards/deopt, range/bounds, string/table/metatable/coroutine ladders, region/alias, SoA, fusion/SIMD, concurrency |
| AA–AO + P1.25–26 P2.32 | 6 Direct native + runtime | I/O via facts, DCE/link reachability, object writer, C-bridge death, lineage, startup/size |
| AJ–AL + P1.26 | 7 Wasm | same graph; import/export specialization; pinned Wasmtime matrix |
| AP–AZ + P2.33–35 P3 | 8 Evidence + anti-drift | gates, MCP/LSP same-graph, census→query, crashes-as-P0, evidence-subject, B/C |

FTCFTW performance claims remain **invalid** until subject-native correctness and
revision-bound measurement close. No compiler B.

## Live claims

Not recorded here (`law.control.derived`). Read `.agents/session/claims/`
or run `scripts/ledger/claim.id`. Acquire via `idol_dev_claim_acquire`
before lane-owned edits.

## A — SOURCE/LEXER SHC

Current exact state:

- `src/lexer_dispatch.zig` `route()` calls `tokenize()` for **every** source.
  `tokenizeHost(allocator, src, file)` exists only inside `differential()`.
  The origin-audit "canonical `.id` still tokenizeHost" claim is **stale**.
- `src/lexer_bridge.zig` / sourceFacts — suffix/path still produces source law
- Generated `src/lexer_tokenize.c` is from current `lib/compiler/lexer.id`
  via `idol dump-c --lib` (no `@`, no `std`/`token.KIND_*` table walk; kinds
  are ordinal immediates matching `compiler/token.id`; `lookup` is spelling →
  ordinal; `Lexer.family` set once in `new()`). Proved: `idol check` on `.id`
  including `#` comments and `'A'` bytes; `scripts/ledger/shc.id` PASS.
- `is_canonical_source` deleted from the Idol producer. Suffix bytes remain
  only inside `Lexer.new()`; host `sourceFacts` is still a second producer
  (ingress debt)
- Host `RECORD_SLOTS`, `lexErrorFromCode`, and `tokenKindFromOrdinal` are
  **deleted**; consumer queries `recordslots()` / `field*()` /
  `rejectionname()` / `kindname()` / `kindcount()`; `bindKindSchema` binds
  ordinals once (`law.schema.one`, `law.magic.zero`). Remaining: host
  `TokenKind` enum, `duo_lexer_*` / `useDuoTokens` names
- GAP-145 — `KIND_STRING_LIT=3` remains; identities appended, not closed.
  Do not close with plural `bytes`. Parser long-bracket reconstruction deleted.

Measurable acceptance criteria:

- [x] `route()` production path is `tokenize()`, not `tokenizeHost`
- [x] `tokenizeHost` remains only as differential oracle
- [x] `scripts/ledger/shc.id` convicts production `tokenizeHost(alloc, zsrc, zfile)`
      and keeps differential `tokenizeHost(allocator, src, file)`
- [x] producer schema queries replace host `RECORD_SLOTS` / magic ordinals /
      rejection codes (`recordslots`, `field*`, `rejectionname`, `kindname`)
- [ ] rejection-id and token-role-id; no parallel host `TokenKind` enum
- [ ] `duo_lexer_*` / `useDuoTokens` deleted (`law.bridge.death`)
- [ ] source-family fact produced by Idol, not suffix/path
- [ ] GAP-145 closed: distinct canonical identities for all token classes
- [ ] Zero host semantic fallback after resolution
- [ ] `tokenizeHost` oracle scoped to legacy-equivalent subset and deletable

Current debt count: 5 exact blockers (parallel TokenKind, bridge names, ingress fact, identity close, oracle bound)

## B — GRAMMAR/PARSER SHC

Current exact state:

- `src/parser.zig` — host-owned production recognition
- GAP-134 — grammar-role authority incomplete (blocked on GAP-145)

Measurable acceptance criteria:

- [ ] One machine-readable grammar-role authority
- [ ] Idol parser consumes immutable token/role projection
- [ ] No duplicated handwritten parser vocabulary

Current debt count: 2 exact blockers

## C — RESOLVER/GRAPH

**Owner: Codex (designated). Status: blocked until acquire.** No other lane
mints relation catalogs, boolean-mirror rows, string worlds, or numeric
semantic codes as substitutes. Devin is A/B SHC transfer, not a second graph
ontology.

Current exact state:

- Binding/scope, graph construction, query remain host-owned
- Descriptor recursion walks `.descriptor_ref` exact-id edges (progress)
- `lib/semantic/*` relation registry **deleted** (`law.catalog.zero`);
  boolean-mirror rows (`callable`/`possessed`/`operation`/string `world`)
  are added-line illegal (`law.boolean.mirror.zero`)
- NodeKind / EdgeKind still carry stale ontology (see compass). Target:
  `module`→provenance facts; `func`/`call`→application facts; `param`/`local`→
  binding roles; `type_node`→descriptor id; `contains`/`home`→`member`;
  `use`→exact binding ref; `transform_output`→operand/result/provenance on
  transformation identity. Tags remain as indexes until facts subsume them.
- Origin-audit "19 semantic_graph build errors" is **stale** — do not cite;
  re-measure on this HEAD before using as a blocker count

Measurable acceptance criteria:

- [ ] Idol produces exact binding/relation/subject/descriptor/capture/world edges
- [ ] Zero semantic rediscovery after resolution
- [ ] `graph.get(exact-id)` only; no string-keyed semantic lookup
- [ ] Zero parent-scope lookup after resolution
- [ ] No operational edge kinds; application owns relation id

Current debt count: 3 exact blockers + ontology audit (not a rename pass)

## D — CANONICAL SOURCE

Current exact state:

- `docs/spec/canonical.md` training-surface regressions from the origin audit
  are **closed** at live HEAD (chained `validate():normalize()`, no `value:to()`
  rung, SOURCE-INFER-ONE / INTERMEDIATE-ZERO in §18a)
- Corpus still contains bracket indexing, inferable `:to`, plurals, one-use
  temporaries, residual `end`, stale conversion comments
- Added-line gates ≠ whole-corpus closure

Measurable acceptance criteria:

- [x] `canonical.md` / `agent.md` / HARNESS match current ruling (keep aligned)
- [ ] SOURCE-INFER-ONE applied globally in corpus (not just docs)
- [ ] `x(key)` replaces `:get(` / `[key]` for ordinary access
- [ ] Intermediate-zero: no avoidable `tmp`/`result`/`checked`/`current`/`next`
- [ ] Whole-corpus gate exists and fails closed (reject; do not rewrite as SHC)

Current debt count: corpus categories remain open; doc teaching closed

## E — WORLD/EFFECT

Current exact state:

- Filesystem ingress still conflatable with runtime file authority
- Runtime world abstraction still present when witness can be known
- Re-measure `gate/host.id` on this HEAD before citing PASS/FAIL

Measurable acceptance criteria:

- [ ] `gate/host.id` passes on current HEAD
- [ ] Known witness → zero runtime world abstraction
- [ ] Filesystem ingress separated from runtime file authority
- [ ] No capability objects, world classes, protocol objects

## F — DEMAND

Current exact state: demand host-owned; no Idol producer.

Measurable acceptance criteria:

- [ ] Idol produces exact demand facts
- [ ] Undemanded work deleted before realization

Current debt count: 1 exact blocker

## G — SHAPE/CALL/CLOSURE SPECIALIZATION

Re-measure emission counts on this HEAD. Origin-audit boxing/indirect/heap
closure numbers are directional, not current evidence.

Measurable acceptance criteria:

- [ ] Known shape → generic hash 0
- [ ] Exact sealed target → indirect call 0
- [ ] Known captures → capture discovery 0
- [ ] Nonescaping closure → heap environment 0

## H — VALUE/PLACE/MEMORY

Re-measure allocation/copy emissions on this HEAD.

Measurable acceptance criteria:

- [ ] Stack/heap/static/region chosen from lifetime/escape/alias facts
- [ ] No GC because "table" exists
- [ ] No allocation without proved observability

## I — EFFECT/FUSION/SIMD

Current exact state: not implemented as graph-fact-driven optimization.

Measurable acceptance criteria:

- [ ] Effects drive CSE/hoisting/fusion/parallelization/SIMD legality
- [ ] map/filter/reduce fuse to one loop when facts permit
- [ ] No target-qualified semantic relation ids

## J — NATIVE MACHINE

Current exact state: generated C remains bounded bridge; direct native is not
yet the production destination for the full corpus. Integrated unit/DNB counts
are **not** recorded here (`law.control.derived`, `law.evidence.subject`).
Re-measure at the live revision before citing pass/fail/crash; crash count is
P0 above pass-count improvement (`law.crash.first`). Last bound subject:
`29f62035` / evidence `59093d7b` in `evidence/EVIDENCE_BUNDLE.md`.

Measurable acceptance criteria:

- [ ] Direct backend executes all semantically valid programs
- [ ] Semantic graph → demand → realization → instruction → object bytes
- [ ] C bridge reduced to bootstrap only, with deletion witness

## K — WASM

Current exact state: no correctness-locked pinned Wasmtime matrix on this HEAD.

Measurable acceptance criteria:

- [ ] Pinned Wasmtime comparison with exact revision
- [ ] Separate measurements: compile/load, instantiate/startup, execution, RSS, bytes
- [ ] No combined vanity score

## L — COMPILE-TIME

Current exact state: dense-id / packed-fact / exact-invalidation / parallel
analysis not closed. Lexer bridge still copies source + filename +
`len × 7 × i64` records + host `Token` array.

Measurable acceptance criteria:

- [ ] Dense ids with arena allocation
- [ ] Parallel semantic analysis by exact dependencies
- [ ] Exact invalidation on source change
- [ ] No string-keyed semantic maps
- [ ] Lexer: source → immutable token view → parser (no pessimistic record buffer, no second token materialization)

## M — EVIDENCE

Current exact state: FTCFTW complete proof near zero. `scripts/ledger/ftcftw.id`
is a contract-presence index (exit 0 on this tree; pass ≠ proof). Parent
`scripts/ledger/perf.id` rows `ledger/ftcftw`. Curry `audit(path)(pattern)` is
IMPLEMENTATION-BLOCKED (direct native SIGSEGV). Stale bundles do not certify
this HEAD.

Measurable acceptance criteria:

- [ ] Every claim binds subject revision and evidence revision separately
      (`law.evidence.subject`); do not report metrics "at HEAD" unless the
      measured subject equals HEAD
- [ ] Every claim binds dirty state, input, expected/actual result,
      CPU/features, target, compiler mode, competitor version, compile,
      startup, runtime, memory, binary size, sample count, variance
- [ ] Positive damage controls: forced allocation, indirect, hash, copy, delay, pad
- [ ] No damage sensitivity → evidence invalid
- [ ] No semantic equivalence → benchmark invalid

## N — COMPILER B/C

Current exact state: no compiler B; no compiler C; repository remains S0.

Measurable acceptance criteria:

- [ ] Compiler B built from canonical Idol
- [ ] Compiler B builds C
- [ ] Exact graph correspondence between B and current compiler
- [ ] No host semantic fallback

## GLOBAL ZERO TARGET (non-negotiable)

```text
semantic string lookup after resolution        0
semantic path lookup after ingress             0
parent-scope lookup after resolution           0
module/import semantic machinery               0
operational graph edge kinds                   0
plural-cardinality identities                  0
*able/*ible identities                         0
role-noun protocol identities                  0
collision mediator systems                     0
generic encode/codec ontology                  0
avoidable source intermediates                 0
inferable explicit `to`                        0
inferable explicit projection                  0
inferable world/protocol plumbing              0
known-shape generic hash                       0
sealed-target indirect dispatch                0
nonescaping heap closures                      0
singleton-union tags                           0
unused-result materialization                  0
known-witness runtime world abstraction        0
unexplained allocations/copies/boxes           0
silent host semantic fallback                  0  (retracted at 2e5d516 — tokenize() route)
unbound performance claims                     0
```

## Scoped checklist A–AZ (subject `29f62035`)

Authority / SHC: [ ] A source-family fact not suffix [ ] B producer token schema [ ] C magic-code zero [ ] D token-role-id not ordinal [ ] E GAP-134 grammar roles [ ] F parser facts not AST [ ] G exact binding id [ ] H ontology decomposition [ ] I edge minimization [ ] J application fact completion [ ] K world/effect/witness [ ] L protocol satisfaction [ ] M infer composition [ ] N demand stage

Physical FTCFTW: [ ] O boxing [ ] P direct calls [ ] Q table hash zero [ ] R closure spec [ ] S alloc [ ] T copy [ ] U tags [ ] V packs [ ] W effects [ ] X fusion [ ] Y SIMD [ ] Z parallel

Native: [ ] AA direct I/O [ ] AB direct coverage [ ] AC C-bridge death [ ] AD machine lineage

Compile-time: [ ] AE lexer bridge copies [ ] AF dense storage [ ] AG exact invalidation [ ] AH parallel analysis [ ] AI string-free hot paths

Wasm: [ ] AJ same graph [ ] AK runtime arch [ ] AL Wasmtime matrix

Runtime/size: [ ] AM feature elimination [ ] AN startup [ ] AO binary size

Corpus/enforcement: [ ] AP no cls:has identity [ ] AQ shell bridge bounded [ ] AR no generic main in tooling [ ] AS generic-action zero [ ] AT foundation-word zero

Evidence: [ ] AU evidence-subject machine-readable [ ] AV status-doc discipline [ ] AW oracle bounded [ ] AX gate adversaries [ ] AY compiler B [ ] AZ compiler C

## Optimization architecture 1–35 → workstreams

Explicit FTCFTW closure items (post catalog-deletion phase). Full item text and
acceptance: `docs/spec/realization.md`. C0:
`law.representation.one`, `law.guard.one`, `law.specialize.budget`, `law.abi.internal`,
`law.crash.first`, `law.cost.explain`, `law.representation.demand`.

| # | Workstream | Law / register | Lane |
|---|---|---|---|
| 1 | REPRESENTATION-ONE | `law.representation.one` · BA | 4 |
| 2 | Guard / deopt architecture | `law.guard.one` · BA | 5 |
| 3 | Specialization code-growth law | `law.specialize.budget` · BA | 4 |
| 4 | ABI specialization | `law.abi.internal` · BB | 4 |
| 5 | Tail call / tail expression | BB | 4 |
| 6 | Numeric FTCFTW pass | BC | 4–5 |
| 7 | Range / refinement propagation | BC | 5 |
| 8 | Bounds-check elimination metric | BC | 5 |
| 9 | String representation + fusion | BD | 5 |
| 10 | Table representation tiers | BD | 5 |
| 11 | Metatable / metamethod specialization | BD | 5 |
| 12 | Coroutine representation tiers | BE | 5 |
| 13 | Concurrency realization | BE | 5 |
| 14 | Region / arena allocation strategy | BE | 5 |
| 15 | Lifetime / alias provenance | BE | 5 |
| 16 | SoA / AoS layout freedom | BF | 5 |
| 17 | Code / branch layout | BF | 5 |
| 18 | Error paths cold / hot separation | BF | 5 |
| 19 | Stage cache + purity facts | BF | 6 |
| 20 | Generated-code lineage | BF | 6 |
| 21 | Transformation convergence | BF | 6 |
| 22 | Determinism / reproducibility | BG | 6 |
| 23 | Whole-program reachability DCE | BG | 6 |
| 24 | Link-time semantic reachability | BG | 6 |
| 25 | FFI boundary conversion | BG | 6 |
| 26 | Wasm import/export specialization | BG | 7 |
| 27 | Direct-native object writer | BG | 6 |
| 28 | Semantic incremental invalidation | BH | 8 |
| 29 | LSP same-graph | BH | 8 |
| 30 | MCP same-graph | BH | 8 |
| 31 | Census / shell → graph query | BH | 8 |
| 32 | Dual debt gates (new=0, total↓) | BH | 8 |
| 33 | Crashes above ordinary failure | `law.crash.first` · BH | 6 |
| 34 | DNB causal bail codes | `law.cost.explain` · BH | 6 |
| 35 | Optimization-miss diagnostics | `law.cost.explain` · BH | 8 |

## Updated critical path (P0–P3)

**P0 — correctness / authority**

1. source-family authority off path/suffix (`law.family.one`)
2. finish GAP-145 lexical identities
3. producer-owned token ABI/schema; eliminate magic slots/codes/ordinal duplication (GAP-107)
4. grammar-role authority / GAP-134
5. Idol parser
6. exact resolver/graph
7. world/effect/witness
8. demand
9. direct backend crashes/failures to zero (`law.crash.first`)

**P1 — FTCFTW cost collapse**

10. representation-one · 11. boxing elimination · 12. call specialization ·
13. shape specialization · 14. closure escape specialization ·
15. allocation/region selection · 16. copy elimination ·
17. tag/refinement elimination · 18. pack/ABI specialization ·
19. bounds/range elimination · 20. string/interpolation fusion ·
21. table layout polymorphism · 22. metamethod specialization ·
23. effect/fusion/SIMD · 24. concurrency realization ·
25. runtime feature DCE · 26. link-time reachability

**P2 — compile/startup/tooling superiority**

27. lexer/token bridge zero-copy · 28. dense graph storage ·
29. exact incremental invalidation · 30. parallel compiler ·
31. stage-result caching · 32. direct object writer optimization ·
33. LSP same-graph · 34. MCP same-graph · 35. replace semantic grep/census

**P3 — proof**

36. all crashes zero · 37. complete correctness matrix ·
38. C-equivalent benchmark suite · 39. pinned Wasmtime suite ·
40. positive damage controls · 41. startup/memory/size/compile/runtime separately ·
42. B compiler · 43. C compiler · 44. semantic fixed-point evidence

Phase conclusion: architecture leaves obvious anti-pattern cleanup; remaining
risk is optimization architecture — representation ownership, guard/deopt,
ABI, range/bounds, layout polymorphism, effect fusion, semantic incremental
compilation, causal optimization diagnostics. Without explicit workstreams
above, implementation can stay semantically clean yet realize everything
conservatively and fail FTCFTW.

## BA — REPRESENTATION / GUARD / SPECIALIZE (items 1–3, P1)

Current exact state: host lowering (`src/dnir_lower.zig`, `src/native_backend.zig`)
still makes ad hoc boxing/register/heap decisions. Measured subject still shows
~1,271 `lua_Value`, ~120 `malloc`, ~174 tag/union sites.

Measurable acceptance criteria:

- [ ] One realization owner produces width/layout/location/boxing/addressability/aggregation/calling-convention facts
- [ ] No downstream pass separately chooses boxed/stack/register/heap/struct/SIMD
- [ ] Guard = unresolved semantic alternative with witness + recovery + provenance
- [ ] Specialization obeys code-growth law (runtime gain vs compile+size+I-cache+startup)
- [ ] Same semantic id for specialized clones; metrics per specialization site

## BB — ABI / TAIL / PACK (items 4–5)

- [ ] Semantic pack → demanded physical slots → target ABI assignment
- [ ] Optimized internal ABI; foreign ABI only at boundary
- [ ] Tail expressions → frame reuse where lawful
- [ ] No tuple materialization / unnecessary sret / temp pack for undemanded results

## BC — NUMERIC / REFINE / BOUNDS (items 6–8)

- [ ] Width/range/sign/overflow facts survive to realization
- [ ] Branch facts (`x < 256`) propagate through arithmetic, index, SIMD, narrowing
- [ ] Bounds metric: emitted / proven-unnecessary / remaining + reason

## BD — STRING / TABLE / META (items 9–11)

- [ ] String realization tiers + concat/interpolation fusion
- [ ] Table layout ladder (dynamic → shape → sealed → dense → compile-time)
- [ ] Metamethod dispatch through application facts; zero machinery when unused

## BE — CORO / CONCUR / REGION / ALIAS (items 12–15)

- [ ] Coroutine tiers from suspend/escape facts; zero link when unused
- [ ] Concurrency realization from isolation/effect facts; no mandatory scheduler
- [ ] Whole-app region/arena selection; graph-native alias/escape/last-use

## BF — LAYOUT / ERROR / STAGE / TRANSFORM (items 16–21)

- [ ] AoS/SoA/AoSoA from demand; code layout from profile evidence only
- [ ] Rare errors on cold paths; hot path unp poisoned
- [ ] Stage cache keyed on semantic dependencies
- [ ] One transformation algebra with shared provenance records

## BG — REACH / LINK / FFI / WASM / OBJ (items 22–27)

- [ ] Sealed reachability DCE; link-time semantic reachability
- [ ] FFI cost isolated to boundary; Wasm import/export specialization
- [ ] Direct object writer: no intermediate assembly text

## BH — TOOLING / GATES / DIAGNOSTICS (items 28–35)

- [ ] Incremental invalidation on semantic application dependency (28)
- [ ] LSP + MCP query same graph — no parallel models (29–30)
- [ ] Shell grep census → MCP/graph violations — CENSUS-DEATH (31)
- [ ] Dual debt gates: new=0, total monotonic decrease per category (32)
- [ ] Crashes = P0 above wrong diagnostic / reject / opt miss (33, `law.crash.first`)
- [ ] DNB bail codes name application + missing fact + producer (34)
- [ ] OPT-EXPLAIN: why boxed/allocated/indirect answerable from facts (35)

## BI — GRAPH SOVEREIGNTY (items G1–G12, P0 lane 3)

Full definitions: `docs/spec/realization.md` § Graph sovereignty. Laws in C0 §67.
File audit: `scripts/ledger/graph.id`.

| # | Workstream | Law | Open debt (live tree) |
|---|---|---|---|
| G1 | TAG-AUTHORITY-ZERO | `law.tag.authority` | `graph_query` `kind != .func`; descriptor kind gates |
| G2 | MODULE-ZERO | `law.module.zero` | `NodeKind.module`, `atModuleScope`, `functionsInModule` |
| G3 | APPLICATION-FACT-CLOSURE | `law.application.closure` | relation/caller/demand/stage via accessors; manifest required |
| G4 | FACT-CARDINALITY-ONE | `law.fact.cardinality` | `?id` null = unknown; known-absent not representable yet |
| G5 | DERIVED-INDEX-ONE | `law.derived.index` | `scope` + `.contains`; application_rows/presence/candidates |
| G6 | FACT-COLUMN-ONE | `law.fact.column` | sparse god-`Node` with nullable role fields on every entity |
| G7 | storage class upstream | `law.representation.one` | `storage_class` → `inferDescriptorState` on Node |
| G8 | bundled State/Recursion/Completion | identity closure | orthogonal facts not mashed enums |
| G9 | AST-BACKEDGE-ZERO | `law.ast.backedge` | `ast_ref` on Node; semantic reads must → 0 |
| G10 | ZERO-COPY + locality | `law.view.zerocopy` · `law.fact.locality` | `alloc.dupe` queries; O(all apps) scans |
| G11 | target + prose contamination | `law.target.contamination` · `law.prose.fact` | `hardware_lowerings`, `why` string on Node |
| G12 | GRAPH-SOVEREIGNTY | `law.graph.sovereignty` | imports ast/sema/types/transform; host enums on Node |

Measurable acceptance:

- [ ] No query/lowering uses NodeKind/EdgeKind to establish semantic validity
- [ ] Fact-location manifest: one authoritative owner per application dimension
- [ ] Unknown / known-absent / exact-id distinguishable on optional facts
- [ ] Semantic `ast_ref` reads = 0; diagnostic-only reads inventoried
- [ ] Node record decomposed to columnar/sparse fact storage
- [ ] Operand/result/capture queries borrow packed ranges (no dupe on hot path)
- [ ] Caller→application and home→member adjacency indexed (not full scans)
- [ ] `module_path` and module tag eliminated; home/member/provenance only
- [ ] Graph core does not import AST/sema/transform to define ontology

---

## Impact-ordered next fixes

Last bound evidence subject `29f62035` (catalog
deletion slice). Live HEAD, dirty tree, lane holders, and integrated counts
are obtained from `git`, `tools/node/dev/orient`, and a fresh measurement run
— not this register (`law.control.derived`, `law.evidence.subject`).

1. **Keep `lib/semantic/*` dead** — gates + `resident-proof`; no catalog resurrection.
2. **P0 authority chain** — source-family → GAP-145 → token ABI → GAP-134 →
   parser → graph → demand → crash/fail zero (see P0 list above).
3. **NodeKind / EdgeKind fact decomposition** — tags are physical indexes only.
4. **P1 optimization architecture** — items 1–26 before revision-bound FTCFTW
   performance claims; each physical cost names missing facts or deletes.
5. **P2 tooling** — semantic incremental invalidation, LSP/MCP same-graph,
   census death; P3 proof matrix and B/C only after correctness green.
