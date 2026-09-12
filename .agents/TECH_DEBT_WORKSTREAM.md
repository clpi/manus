# Idol — current tech debt + FTCFTW workstream one-pager

| # | directive |
|---|---|
| 1 | This is the **current workstream / debt compass**. |
| 2 | It is not semantic law. |
| 3 | Supreme compact law is `docs/spec/law.md`; structured expansion is `docs/spec/constitution.md` (C0, including §67). |
| 4 | Executed frontier: `docs/bootstrap.md`. |
| 5 | Metrics: `docs/METRICS.md`. |
| 6 | Measurable checkboxes: `WORKSTREAM_DEBT_REGISTER.md`. |

| # | directive |
|---|---|
| 1 | **Live HEAD / dirty / holders:** not recorded here (`law.control.derived`). |
| 2 | Use `git rev-parse HEAD`, `git status`, `tools/node/dev/claim list`, and `tools/node/dev/orient`. **Evidence subject vs revision:** bind every metric to the measured subject and the evidence revision separately (`law.evidence.subject`). |
| 3 | Catalog deletion + `tokenize()` route subject is `29f62035`; later evidence revisions must name their own subject. |
| 4 | Do not report FTCFTW “at HEAD” unless subject equals the live tree. |

## Status

| Dimension | State |
|---|---|
| Architecture | direction strong |
| Canonical source | incomplete |
| Graph authority | incomplete |
| End-to-end id continuity | incomplete |
| SHC | **S0**; no compiler B; ~10% executed semantic authority |
| FTCFTW | architecture promising; complete current evidence **NOT PROVEN** (~0%) |
| Release | not ready |

| # | directive |
|---|---|
| 1 | Doctor default at live HEAD: **PASS** (MCP serve, architecture gate, unit gate deferred). |
| 2 | Default doctor green is **not** combined CI / full-gate proof. |

| # | directive |
|---|---|

## Live-HEAD delta vs origin audit `dc07e5d7`

| # | directive |
|---|---|
| 1 | Still true (do not reopen as "maybe fixed by alignment commits"): |

- Source-family: family is a tokenize operand; `suffix(file)` is deleted.
  Production compile/fmt/embed classify once via `sourceFacts` then
  `initFacts`. `isIdolSourcePath` is deleted. Executed `sourceform*`,
  `sourceentry*`, and `sourcefact*` now own source admission; the host residual
  is filesystem normalization plus ABI name binding.
- GAP-145 not closed: distinct producer identities and source admission now
  cross production, but remaining semantic quote/source-law consumers and the
  Tree-sitter lexical projection have not converged.
- GAP-134 grammar roles still blocked. Parser onward remain host-owned.
- No compiler B. FTCFTW complete proof still near zero.
- Path/corpus cleanup ≠ source closure.

| # | directive |
|---|---|
| 1 | Closed at subject `29f62035` (catalog deletion + `tokenize()` route): |

- **`lib/semantic/*` deleted** — 28 hand-authored relation-catalog files
  (`io`, `fs`, `seq`, `json`, `jit`, `coroutine`, `net`, `mem`, `ffi`, `mcp`,
  `debug`, `keyword`, `application`, `bit`, `census`, `clock`, `gate`, `graph`,
  `ingest`, `os`, `process`, `producer`, `simd`, `verdict`, `vocabulary`,
  `zerostd`, …). Do not restore, rename (`seq` → `sequence`), or relocate rows.
- **`law.boolean.mirror.zero`** and **`law.catalog.zero`** in C0 §67; added-line
  gates convict `callable`/`possessed`/`operation`/string `world` rows and
  `lib/semantic/` paths. `scripts/proof/resident.id` + `zig build resident-proof`
  ratchet absence.
- Bootstrap subset rewritten as **required capabilities/facts**, not container
  kingdoms (`docs/bootstrap.md` § Bootstrap subset).

## Convergence principle (catalog death)

| # | directive |
|---|---|
| 1 | There must eventually be **no manually maintained semantic catalog** anywhere. |
| 2 | Source produces semantics; the resolver publishes exact graph ids and structural facts (subject, operand, result, witness, demand, effect); every downstream stage consumes those facts directly — never metadata rows like: |

```id
read = { world = "io", possessed = true, callable = true, operation = false }
```

| # | directive |
|---|---|
| 1 | That pattern violated six independent laws (lib namespace, semantic qualifier, string world, *able mirror, possessed mirror, operation taxonomy). |
| 2 | Correct shape is application/relation exact-ids with edges — no registry row. |

| # | directive |
|---|---|
| 1 | Closed this session (SHC A dispatch + CATALOG-ZERO enforcement): |

- Production route is `tokenize()` for every source. `tokenizeHost()` is
  differential-only.
- `src/lexer_tokenize.c` regenerated from `lib/compiler/lexer.id`
  via `idol dump-c --lib` (`KIND_EOF = 109`, `family` on Lexer; no `is_canonical_source`).
- Unit tests at subject `29f62035`: 1216 pass / 22 fail / 4 crash (was 1205 / 33 / 4).
  **Historical subject only** — re-measure live tree before citing (`law.evidence.subject`).

| # | directive |
|---|---|
| 1 | Superseded / do not re-litigate from the origin audit text: |

- **`d09fd376` and earlier** still contained `lib/semantic/*` catalog rows.
  Live tree at `2e5d516` does not. Do not cite pre-`29f62035` manifests as current.
- `docs/spec/canonical.md` now teaches `value:validate():normalize()` and
  **no** `value:to()` rung; SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE /
  INTERMEDIATE-ZERO are in §18 / §18a. Constitution retains `checked` /
  `value:to()` only as **negative** exhibits.
- Origin-audit "19 semantic_graph build errors" and "doctor FAIL" are **stale**.
  Re-measure before citing. Default `./tools/node/dev/doctor` is PASS with
  deferred full gates; that is **not** combined CI / integrated unit proof.

| # | directive |
|---|---|
| 1 | **Forbidden next move:** another filename / "canonical: finalize … alignment" round. `dd3371e5` and later “finalize alignment” commits are not closure. `dd3371e5` reintroduced `good`/`raw`/`:has`/`bytes`/`echo $?` in `gate/build.id` because (1) pre-commit only `idol check`’d gates and (2) `cited` exempted all of `gate/`. `gate/build.id` is no longer a detector home. |
| 2 | Detectors exist for those forms. |

| # | directive |
|---|---|
| 1 | `idol run gate/idiom.id` over a non-empty diff currently refuses at DNB001 `concat` (IMPLEMENTATION-BLOCKED). |
| 2 | Its law remains migration guidance; a static added-line scan is only nonsemantic pressure. |
| 3 | Do not restore hook execution until the executable scan is stable. |
| 4 | Check-pass is not a scan. |
| 5 | Do not land another alignment commit that reintroduces the blocked forms. |

| # | directive |
|---|---|
| 1 | **Critical path (not naming, not reports):** |

```text
source-family → lexical identity → grammar role → parser
→ exact graph → demand → specialization → direct realization
→ object → evidence → B → C
```

| # | directive |
|---|---|
| 1 | Eight production lanes: `.agents/AGENT_COORDINATION.md`. |
| 2 | This compass is not the frontier (`docs/bootstrap.md`). |

| # | directive |
|---|---|
| 1 | **Highest-impact order** |

1. Source-family fact + remaining lexical authority (GAP-145). Path is provenance.
2. Lexer ABI/schema/magic-code deletion — producer token view, not a Zig slot map.
3. Resolver/graph is unowned (Codex stale). Do not invent catalogs.
4. Grammar/parser into Idol (GAP-134) only after GAP-145.
5. Demand.
6. Kill `lua_Value` / `lua_invoke` / malloc / memcpy from known facts.
7. Direct native correctness.
8. C + Wasmtime FTCFTW evidence.

| # | directive |
|---|---|
| 1 | FTCFTW remains **invalid** as a performance claim. |
| 2 | No compiler B. |

## Physical-cost baseline (subject `29f62035` evidence)

| # | directive |
|---|---|
| 1 | Directional counts from revision-bound measurement — re-measure on live tree before citing as current: |

| Category | Approximate sites |
|---|---|
| `lua_Value` boxing | ~1,271 |
| `lua_table_new` | ~82 |
| `malloc` | ~120 |
| `lua_invoke` | ~97 |
| tag/union | ~174 |
| Lua hash | ~84 |
| `memcpy` | ~134 |
| materialized packs | dozens |
| unit fail / crash | 22 / 4 at subject `29f62035` only — remeasure live tree |

| # | directive |
|---|---|
| 1 | Each remaining site must name unresolved semantic alternatives or be deleted. |

| # | directive |
|---|---|

## Optimization architecture closure (items 1–35)

| # | directive |
|---|---|
| 1 | Post catalog-deletion phase: remaining FTCFTW risk is optimization architecture, not obvious semantic anti-patterns. |
| 2 | Explicit 1–35 workstreams: `docs/spec/realization.md`. |
| 3 | Register maps clusters in `WORKSTREAM_DEBT_REGISTER.md` (sections BA–BH + 1–35 table). |
| 4 | C0 laws: `law.representation.one`, `law.guard.one`, `law.specialize.budget`, `law.abi.internal`, `law.representation.demand`, `law.crash.first`, `law.cost.explain`. |

| Cluster | Items | Closure test |
|---|---|---|
| Representation / guard / specialize | 1–3 | one realization owner; guards carry recovery; specialize obeys budget |
| ABI / tail / pack | 4–5 | internal ABI; foreign only at boundary; tail → frame reuse |
| Numeric / refine / bounds | 6–8 | width/range survive; branch facts propagate; bounds metric tracked |
| String / table / meta | 9–11 | realization tiers; fusion; metamethod via application facts |
| Coro / concur / region / alias | 12–15 | tiered realization; zero link when unused; graph-native alias |
| Layout / error / stage / transform | 16–21 | AoS/SoA from demand; cold errors; stage cache; one transform algebra |
| Reach / link / FFI / Wasm / obj | 22–27 | sealed DCE; link reachability; FFI isolated; direct object writer |
| Tooling / gates / diagnostics | 28–35 | semantic invalidation; LSP/MCP graph; dual debt gates; OPT-EXPLAIN |

| # | directive |
|---|---|
| 1 | Updated ranking: P0 authority (1–9) → P1 cost collapse (10–26) → P2 tooling (27–35) → P3 proof (36–44). |
| 2 | Full numbered list in register. |

| # | directive |
|---|---|

## P0 — authority / SHC debt

| # | directive |
|---|---|
| 1 | Closed: production `tokenize()`; `tokenizeHost()` differential-only (`law.oracle.bound`); `lib/semantic/*` gone (`29f62035`). |

| # | directive |
|---|---|
| 1 | Open, in path order: GAP-145 remaining lexical consumers; parallel host `TokenKind` / `duo_*` bridge names (schema queries landed `9b475670`) |
| 2 | GAP-134; parser; graph (unowned — Codex stale); demand; realization |

| # | directive |
|---|---|

## P0 — canonical authority doc debt

| # | directive |
|---|---|
| 1 | **Training-surface regressions named in the origin audit are closed at live HEAD** (`canonical.md` §1 / §18 / §18a; regenerated harness / agent / CLAUDE / AGENTS projections). |

| # | directive |
|---|---|
| 1 | Ongoing: keep every provider projection, example, and skill aligned when authority changes. |
| 2 | Do not teach: |

```id
checked = value:validate()
checked:normalize()
```

| # | directive |
|---|---|
| 1 | or a canonical `value:to()` rung. |

```text
infer everything possible
explicit to(target) only when target cannot be inferred
```

| # | directive |
|---|---|
| 1 | SOURCE-INFER-ONE applies globally to: bindings; relation names; projections; conversion; world witnesses; protocol witnesses; captures; qualification; injection/projection composition. |

| # | directive |
|---|---|

## P0 — corpus debt

| # | directive |
|---|---|
| 1 | Latest migrations still contain canonical-corpus violations including: |

- call-shaped aggregate access — computed projection must converge on
  `count[x + 1]`, `cells[1]`, `src[i]`, and `flag[i]`, while `value(args)`
  remains ordinary application
- explicit inferable `i:to(str)`
- one-use temporaries
- plural bindings: `rows`, `lines`, `words`, `chars`
- stale `end` in portions of migrated corpus
- comments teaching outdated conversion necessity

| # | directive |
|---|---|
| 1 | **Path cleanup ≠ source closure.** Required: entire-corpus audit / gate, not added-line-only. |
| 2 | Cursor/corpus lane **prevents re-entry**; it does not become the SHC frontier. |

| # | directive |
|---|---|

## P0 — INTERMEDIATE-ZERO

| # | directive |
|---|---|
| 1 | Source bindings name meaning, not compiler steps. |
| 2 | Eliminate avoidable: `tmp`, `result`, `checked`, `converted`, `output`, `current`, `next`, `intermediate`. |

| # | directive |
|---|---|
| 1 | Prefer `value:a():b():c()` over single-use bridge chains. |

| # | directive |
|---|---|
| 1 | Exception only when the binding is semantically meaningful, reused, refinement-bound, effect/order/lifetime relevant, or genuinely improves human understanding. |
| 2 | Bindings must never force storage. |

| # | directive |
|---|---|

## P0 — inference / source density

```text
IF GRAPH CAN KNOW IT UNIQUELY, SOURCE SHOULD NOT SPELL IT.
```

| # | directive |
|---|---|
| 1 | Applies to: `to`; relation selection; static projection; subject; descriptor target; capture; world witness; protocol witness; projection/injection algebra. |

| # | directive |
|---|---|
| 1 | Examples: `env["HOME"]` not `os.env["HOME"]` when uniquely admitted; `f(x)` not `f:call(x)`; `x[key]` not `x(key)` or `x:get(key)` for computed projection; `consume(value)` not `consume(value:to(target))` when target is demanded uniquely. |

| # | directive |
|---|---|
| 1 | Human-meaning exception: `source:read()` may remain because `source()` obscures semantic intent. |

| # | directive |
|---|---|

## P0 — graph edge / id debt

| # | directive |
|---|---|
| 1 | Good progress: descriptor recursion now traverses `.descriptor_ref` exact-id edges. |

| # | directive |
|---|---|
| 1 | Remaining graph ontology must prove irreducibility. |
| 2 | Deleted unused tags (never constructed): NodeKind `source_file` `concept` `comptime_value` `emit_artifact` |
| 3 | EdgeKind `def` `type_of` `transform_input`. `type_of` became `descriptor`. |

| # | directive |
|---|---|
| 1 | Still present (physical tags, must not own meaning): `module`, `func`, `param`, `local`, `type_node`, `call`, `relation`, `transform_app`, `table_shape`, `enum_shape`. |

| # | directive |
|---|---|
| 1 | Likely reductions: |

- `module` → home/member/provenance facts
- `call` → application
- `transform_app` → transformation facts
- `local` / `param` → binding/value roles
- `type_node` → descriptor id
- `table_shape` / `enum_shape` → shape/descriptor facts

| # | directive |
|---|---|
| 1 | Remaining suspicious EdgeKind: `contains`, `use`, `descriptor_ref`, `transform_output`. |
| 2 | Audit each against structural-role law. |
| 3 | Do not mint `subject`/`relation`/`result` as EdgeKind — those roles already live on `ApplicationFact`. |

| # | directive |
|---|---|
| 1 | No operational edge kinds: `run`, `call`, `invoke`, `execute`, `read`, `write`, `parse`, `convert`, `lower`, `emit`, etc. Application owns relation id. |

| # | directive |
|---|---|

## P0 — name / string / path reconstruction debt

| # | directive |
|---|---|
| 1 | Target: **ZERO semantic rediscovery after resolution.** |

| # | directive |
|---|---|
| 1 | Audit/delete production authority from: `findFunc(name)`, `findByName(name)`, name indexes, callee text matching, descriptor name matching, path suffix semantic selection, source filename relation selection, opcode → semantic relation recovery, host type → semantic fact recovery. |

| # | directive |
|---|---|
| 1 | Allowed: `graph.get(exact-id)`; id-indexed physical row; actual JSON/env/user string key. |
| 2 | If consumer lacks id: **fix producer**. |

| # | directive |
|---|---|

## P0 — filesystem / module debt

| # | directive |
|---|---|
| 1 | Filesystem has exactly two unrelated roles: |

- **SOURCE:** ingress / home / member / provenance
- **RUNTIME:** file/path authority through world/effect semantics

| # | directive |
|---|---|
| 1 | Never conflate them. |

| # | directive |
|---|---|
| 1 | Target zero: module semantics; namespace semantics; import/`req`; path-based resolution after ingress; parent-directory semantic lookup; sibling lookup; source location granting runtime authority. |

| # | directive |
|---|---|
| 1 | Directory may imply table/home. |
| 2 | File is member body. |
| 3 | After resolution, path is provenance only. |

| # | directive |
|---|---|

## P0 — world / protocol / projection debt

| # | directive |
|---|---|
| 1 | One fact-composition algebra only. |

- Protocol: demanded application/relation facts
- World: authority-bearing facts/witnesses
- Projection: select exact existing facts
- Injection/composition: add exact selected facts to exact context/application

| # | directive |
|---|---|
| 1 | `lib/semantic/*` relation catalogs are **deleted** (`law.catalog.zero`). |
| 2 | Do not restore `world = "io"`, `callable = true`, `possessed`, `operation`, `seq` dumps, or `json` as a world. |
| 3 | Relation ids come from resolution; authority from application witness facts. |

| # | directive |
|---|---|
| 1 | No separate: capability objects; world classes; protocol objects; injection framework; provider; registry; context; module import; mock framework. |

| # | directive |
|---|---|
| 1 | Known witness → zero runtime abstraction. |
| 2 | No parent world, default world, nearest world, last-wins. |

| # | directive |
|---|---|
| 1 | Source should normally **not** spell projection/injection/world plumbing when use uniquely determines it. |

| # | directive |
|---|---|

## P0 — naming debt

| # | directive |
|---|---|
| 1 | Enforce semantic, not cosmetic naming. |

- NO plural cardinality identities (`bytes`, `strings`, `fields`, `values`,
  `arguments`, `results`, `nodes`, `edges`, `captures`, `tests`, `examples`,
  `collections`, …)
- NO `*able`/`*ible` (`callable`, `readable`, `writable`, `iterable`,
  `encodable`, …)
- NO role-noun evasions (`reader`, `writer`, `encoder`, `runner`, `resolver`,
  `provider`, …)
- NO collision roles (`router`, `gateway`, `registry`, `manager`, `adapter`,
  `engine`, `pipeline`, `context`, `service`, `bridge`, `wrapper`, …)
- NO mashed compounds (`tokenview`, `canonicalid`, `perfledger`, `arm64check`, …)
- NO qualifier identity (`nativevalue`, `staticcall`, `resolvedtype`, …)
- NO boolean mirrors of graph structure (`callable`, `possessed`, `operation`,
  `typed`, `authorized`, `captured`, `projected`, `resolved`, `imported`,
  `native`, `static`) — BOOLEAN-MIRROR-ZERO
- NO relation/world/format/handler catalogs — CATALOG-ZERO

| # | directive |
|---|---|
| 1 | Delete/decompose before rename. |

| # | directive |
|---|---|

## P1 — optimization architecture (FTCFTW closure)

| # | directive |
|---|---|
| 1 | After semantic anti-pattern cleanup, FTCFTW failure mode is **conservative realization** — semantically clean graphs that still box, allocate, indirect, and guard everything. |
| 2 | These lanes are explicit; none may remain implicit. |

| Lane | Owner fact | Decision point |
|---|---|---|
| **REPRESENTATION-ONE** | demand + lifetime + alias + mutation + escape + ABI + target | one realization pass owns width, layout, location, boxing, addressability, aggregation, calling convention — no downstream pass chooses stack/register/heap/struct/SIMD separately |
| **GUARD-ONE** | unresolved semantic alternative | guard = fast path depends on a fact; known → 0; speculated → exact guard + slow alt + witness; unknown → general realization; every guard retains assumed fact, evidence, recovery realization, provenance |
| **SPECIALIZE-LAW** | same semantic id, multiple realizations | specialize when expected runtime gain > compile cost + bytes + I-cache + startup; track apps benefiting, branches/alloc/indirects removed, bytes/compile added; no clone semantic identities |
| **ABI-ONE** | semantic pack → physical slots → target ABI | register args/returns, aggregate elision, no tuple/sret/temp pack; optimized internal ABI; foreign ABI only at boundary |
| **TAIL-ONE** | tail expression / recursive relation | tail call → frame reuse; loop conversion; stack-depth proof where lawful |
| **NUMERIC-ONE** | width/sign/range/overflow/NaN/alignment/const | facts survive to narrower lanes, vectors, overflow-guard removal; physical width ≠ semantic identity |
| **REFINE-ONE** | branch/loop/shape facts | `x < 256` inside branch propagates through arithmetic, indexing, bounds, SIMD, narrowing, switch prune, allocation size |
| **BOUNDS-ONE** | sequence/table/string access | emit metric: checks emitted / proven unnecessary / remaining + reason |
| **STRING-ONE** | text realization tier | borrowed/static/inline/slice/owned/rope/intern; concat/interpolation fuse to stream or size-once |
| **TABLE-ONE** | one semantic table, many physical tiers | dynamic hash → shape-specialized → sealed struct → dense ordinal → compile-time disappear |
| **META-ONE** | metatable/metamethod | unknown → dynamic; stable → direct relation; sealed → inline; unused → zero machinery via same application facts |
| **CORO-ONE** | suspend/escape/thread facts | never suspends → ordinary fn; nonescaping suspend → compact state; general → runtime; cross-thread only if demanded; zero link when unused |
| **CONCUR-ONE** | isolation/mutation/shared/effect/block/cancel/order/world | inline/worker/thread/event/async-SIMD/GPU realization; no mandatory scheduler |
| **REGION-ONE** | whole-app lifetime facts | arena/region/bump/stack/static/reuse when profitable — not per-object escape alone |
| **ALIAS-ONE** | place/value lifetime graph-native | alias, escape, last-use, reuse without conservative fallback; provenance survives transforms |
| **LAYOUT-ONE** | homogeneous collection demand | AoS/SoA/AoSoA/vector blocks chosen from demand — semantic table does not fix layout |
| **LAYOUT-CODE** | profile evidence (not truth) | branch/block/function ordering; cold error/diagnostic separation |
| **ERROR-COLD** | rare failure | must not poison hot path with boxed/tagged/heap/branch-on-every-op; cold continuation where lawful |
| **STAGE-CACHE** | `@(...)` compile-time execution | dependency/effect/purity witness; cache key from semantic deps; invalidation on dep change only |
| **GEN-LINEAGE** | generated facts | generator application, source facts, stage, world, demand, resulting ids — never opaque reparsed text |
| **XFORM-ONE** | one transformation algebra | inline/vector/stage/macro algorithms record same input ids, required facts, output ids, eliminated alts, provenance |
| **DETERMIN-ONE** | same source+world+target+revision | graph + realization deterministic unless evidence explicitly permits nondeterminism |
| **REACH-ONE** | sealed program | exact reachable applications → DCE unused relations/descriptors/worlds/runtime/bridges/metadata |
| **LINK-REACH** | post-emission | semantic reachability → section/COMDAT/runtime-support/visibility minimization |
| **FFI-ONE** | boundary only | Idol value → ABI projection → foreign call → result projection; no global CValue kingdom |
| **WASM-ONE** | import/export fixed | direct import, layout specialize, omit unused tables, minimize metadata, precompute init |
| **OBJ-ONE** | direct object writer | single-pass sizing, compact relocs, arena symbols/fixups, deterministic order, no asm text |
| **INCR-ONE** | semantic dependency | changed application fact → invalidate dependent closure — not changed file → recompile module |
| **LSP-GRAPH** | tooling | hover/completion/rename/nav/diagnostics/color query exact semantic ids — no parallel LSP model |
| **MCP-GRAPH** | agents | id/relation/subject/application/provenance/demand/realization queries replace grep census |
| **CENSUS-DEATH** | shell/string auditors | regex gates at lexical ingress only; long-term violations = graph/MCP query identities |
| **DEBT-GATE** | whole-repo baselines | new debt = 0 always; total debt monotonic decrease per category until 0 |
| **CRASH-ZERO** | compiler infrastructure | crash > wrong diagnostic > reject valid > opt miss — each crash is immediate P0 |
| **DNB-CAUSAL** | backend bail | application id, missing fact/capability, consumer, expected producer — not opaque category |
| **OPT-EXPLAIN** | cost diagnostics | why boxed/allocated/indirect/not-SIMD/copied answerable from unresolved facts via MCP |

| # | directive |
|---|---|
| 1 | Blocked on graph + demand for most lanes. |
| 2 | Representation/guard/ABI decisions must not land in host lowering ad hoc (`src/dnir_lower.zig`, `src/native_backend.zig`) without routing through the single realization owner. |

| # | directive |
|---|---|

## P1 — specialization, memory, effects, machine

- **Shape specialization** — known table shape eliminates generic hash, dynamic
  field dispatch, boxed records, runtime shape checks, redundant descriptor
  lookup. Known fixed field → direct offset/register/scalarized value.
- **Application specialization** — exact application facts drive direct target,
  inlining, constant propagation, pack/subject/descriptor/world specialization.
  Exact sealed target: indirect dispatch = 0. Clone code only when runtime gain
  beats compile cost, size, I-cache, startup.
- **Closure specialization** — exact capture edges. No captures → no
  environment; constant → fold; nonescaping → register/stack; escaping → only
  then durable allocation. No generic heap closure by default. No parent-frame
  semantic links.
- **Value / place / allocation zero** — binding ≠ value ≠ place. Every stack
  slot, heap object, temporary aggregate, load/store, copy must prove mutation,
  alias, address, ABI, lifetime, observability — otherwise scalarize/eliminate.
- **Pack / return zero** — operand/result packs are semantic. Do not
  materialize tuples because a backend likes them. Unused results: zero
  materialization. Demand deletes undemanded result work before realization.
- **Union / tag zero** — union = remaining alternatives. After refinement to
  one alternative: tag = 0; branch = 0 where possible.
- **World cost zero** — known authority witness: runtime world object = 0;
  capability dictionary = 0; service lookup = 0; world dispatch = 0.
- **Effect-driven optimization** — no binary pure/impure collapse. Effects
  drive reorder, eliminate, duplicate, speculate, fuse, parallelize, vectorize,
  stage, CSE, hoisting, loop fusion, SIMD legality.
- **Loop / iteration / fusion** — one iteration semantic relation. No mandatory
  iterator object. map/filter/reduce-like chains fuse to one loop, zero
  intermediate table when facts permit.
- **SIMD / hardware** — realizations, not source semantic kingdoms. No
  target-qualified semantic relation ids.
- **Native backend** — direct native is the production destination. Generated C
  is bounded bridge debt. Do not shape Idol semantics around C emission.
  Delete C-only semantic dependencies as native coverage closes.
- **Machine lineage** — source → semantic id → application → relation → value
  → demand → realization → instruction → object byte range. No optimizer may
  destroy lineage.
- **Compile-time FTCFTW** — dense ids, arenas, packed fact ranges, compact
  bitsets, lazy indexes, exact dependency invalidation. No repeated scope
  walks, name resolution, string-key semantic maps, or heap object per fact.
  Lexer bridge currently copies source, filename, a pessimistic
  `len × 7 × i64` record buffer, then rematerializes host `Token`s. Target:
  source → immutable token/fact view → parser. No filename copy; no source
  copy where ABI permits; no second token array if the parser can consume
  the producer view.
- **Startup / binary size** — sealed program links only required machinery.
  OS loader → entry. No mandatory GC, scheduler, reflection, dynamic table
  runtime, world framework, coroutine machinery unless demanded.
- **GC / memory** — GC is realization only, chosen from lifetime/escape/alias/
  mutation/world/effect facts. No GC because "table" exists.
- **Wasm FTCFTW** — same semantic graph as native. No Wasm semantic universe.
  Pinned Wasmtime comparison: correctness, compile/load, instantiate/startup,
  runtime, peak memory, artifact bytes — separately measured.

| # | directive |
|---|---|

## P0/P1 — evidence debt

| # | directive |
|---|---|
| 1 | Complete FTCFTW proof currently near zero. `scripts/ledger/ftcftw.id` is a contract-presence index — pass means contracts exist, not that the bound is proven. `audit(path)(pattern)` is IMPLEMENTATION-BLOCKED on direct native (compiles, then SIGSEGV); index uses flat `look`/`need` until that second apply survives. |
| 2 | Every claim must bind subject revision and evidence revision separately (`law.evidence.subject`); do not report metrics "at HEAD" unless the measured subject equals HEAD. |
| 3 | Then: dirty state; input; expected semantic result; actual result |
| 4 | CPU/features; target; compiler mode; competitor version; compile; startup; runtime; memory; binary/artifact size; sample count; variance. |

| # | directive |
|---|---|
| 1 | Positive damage controls required: force allocation, force indirect, force hash, force copy, force startup delay, pad artifact. |
| 2 | Measurement must worsen. |
| 3 | No damage sensitivity → evidence invalid. |
| 4 | No semantic equivalence → benchmark invalid. |
| 5 | No current revision → stale evidence. |

| # | directive |
|---|---|

## P0 — build / CI debt

| # | directive |
|---|---|
| 1 | Origin audit reported broken ledgers and no revision-bound proof. |
| 2 | Live default doctor is PASS with deferred full gates; that is **not** combined CI status. |

| # | directive |
|---|---|
| 1 | Before performance claims: clean integrated build; full semantic gates; full correctness corpus; all ledgers executable; revision-bound proof bundle. |

| # | directive |
|---|---|

## Workstream order

```text
A  SOURCE/LEXER SHC        close GAP-145 identities; delete parallel
                           TokenKind / `duo_*` bridge names; replace suffix
                           ingress; host scanner stays differential-only
B  GRAMMAR/PARSER SHC      one grammar-role authority; immutable token view;
                           Idol parser recognition
C  RESOLVER/GRAPH          exact binding/relation/subject/descriptor/capture/
                           world edges; zero rediscovery
D  CANONICAL SOURCE        keep docs honest; INTERMEDIATE-ZERO; global
                           inference; x(key); naming cleanup; whole-corpus
                           gate (reject, do not rewrite as the frontier)
E  WORLD/EFFECT            exact requirement/witness graph; fs authority
                           separation; zero runtime world abstraction when sealed
F  DEMAND                  delete undemanded work before realization
G  REPRESENTATION/GUARD    REPRESENTATION-ONE + GUARD-ONE + SPECIALIZE-LAW
H  ABI/TAIL/PACK           ABI-ONE + TAIL-ONE + pack/return zero
I  NUMERIC/REFINE/BOUNDS   NUMERIC-ONE + REFINE-ONE + BOUNDS-ONE
J  STRING/TABLE/META       STRING-ONE + TABLE-ONE + META-ONE
K  CORO/CONCUR/REGION      CORO-ONE + CONCUR-ONE + REGION-ONE + ALIAS-ONE
L  LAYOUT/ERROR/STAGE      LAYOUT-ONE + LAYOUT-CODE + ERROR-COLD + STAGE-CACHE
M  TRANSFORM/PROOF           XFORM-ONE + GEN-LINEAGE + DETERMIN-ONE + REACH-ONE
N  LINK/FFI/WASM/OBJ       LINK-REACH + FFI-ONE + WASM-ONE + OBJ-ONE
O  TOOLING/INCR            INCR-ONE + LSP-GRAPH + MCP-GRAPH + CENSUS-DEATH
P  GATES/DIAGNOSTICS       DEBT-GATE + CRASH-ZERO + DNB-CAUSAL + OPT-EXPLAIN
Q  EVIDENCE                correctness-locked C/Wasm/native matrix; damage controls
R  COMPILER B/C            B from canonical Idol; B builds C; no host fallback
```

| # | directive |
|---|---|
| 1 | Lane reminder: A/B lexical+grammar is **Devin** (`shc-ingress-lexer`). |
| 2 | Lane 3 is Cursor `graph-interim` until Codex acquires — no catalogs. |
| 3 | Poolside is stale |
| 4 | Cursor holds 4–6 as `realization-interim` until Poolside acquires. |
| 5 | Cursor also holds census MAIN-ZERO. |

| # | directive |
|---|---|

## Live claims

| # | directive |
|---|---|
| 1 | **Not recorded here** (`law.control.derived`, CONTROL-PLANE-DERIVED-ZERO). |
| 2 | Obtain live lane holders, locks, HEAD, and dirty state from: |

- `tools/node/dev/claim list`
- `evidence/HEAD.txt` via `tools/node/dev/orient`

| # | directive |
|---|---|
| 1 | Lane labels elsewhere in this file name durable *roles*, not active locks. |
| 2 | Acquire before editing owned paths. |

| # | directive |
|---|---|

## Global zero target

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
inferable explicit to                          0
inferable explicit projection                  0
inferable world/protocol plumbing              0
known-shape generic hash                       0
sealed-target indirect dispatch                0
nonescaping heap closures                      0
singleton-union tags                           0
unused-result materialization                  0
known-witness runtime world abstraction        0
unexplained allocations/copies/boxes           0
silent host semantic fallback                  0
unbound performance claims                     0
```

## Final priority

```text
FIRST MOVE AUTHORITY.
THEN PRESERVE EXACT FACTS.
THEN DELETE PHYSICAL COST.
THEN PROVE THE WIN.
```

| # | directive |
|---|---|
| 1 | 100% SHC: every production semantic decision owned by Idol. |

| # | directive |
|---|---|
| 1 | FTCFTW: every avoidable physical cost removed, with correctness-bound evidence proving native + Wasm performance. |
