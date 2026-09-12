| field | value |
|---|---|
| title | WORKSTREAM DEBT REGISTER |
| live head / lane holders / dirty | via orient,  — never hand-pasted here (). |

| # | directive |
|---|---|
| 1 | PROJECTION — not authority. |
| 2 | Authority chain: |

| # | directive |
|---|---|
| 1 | Supreme compact law: `docs/spec/law.md` |
| 2 | Structured expansion: `docs/spec/constitution.md` |
| 3 | Executed frontier: `docs/bootstrap.md` |
| 4 | Metric interpretation: `docs/METRICS.md` |
| 5 | Realization architecture: `docs/spec/realization.md` |
| 6 | Measurements: `evidence/EVIDENCE_BUNDLE.md` |

| # | directive |
|---|---|
| 1 | EVIDENCE-SUBJECT-ONE (`law.control.derived`): this register does **not** record live HEAD, dirty tree, or lane holders. |
| 2 | Obtain those from `git`, `.agents/session/claims/`, `scripts/ledger/claim.id`, and `tools/node/dev/orient`. |
| 3 | Bind every evidence claim to the revision that was actually measured. |

| # | directive |
|---|---|
| 1 | Compass: `.agents/TECH_DEBT_WORKSTREAM.md` 1–35 index: `docs/spec/realization.md` (projection, not C0) |

| section |
|---|---|
| Audit verdict (2026-08-13) |

| # | directive |
|---|---|
| 1 | **Closed / materially improved at live tree** |

| # | directive |
|---|---|
| 1 | Production `tokenize()` route; host `tokenizeHost()` differential-only |
| 2 | `lib/semantic/*` catalog deleted (CATALOG-ZERO) |
| 3 | Host `RECORD_SLOTS` / magic ordinals / rejection-code mapping deleted; producer queries + `bindKindSchema` bind-once (bridge with deletion gate) |
| 4 | `ApplicationFact.relation` consumed via `graph.applicationRelation` in lowering |
| 5 | `lib/compiler/application.id` decomposed to role docs (APPLICATION-CONSUMER-ZERO) |
| 6 | Storage class demoted; causal DNB / backend refusal pattern improved |

| # | directive |
|---|---|
| 1 | **P0 remaining (authority before FTCFTW performance claims)** |

| # | directive |
|---|---|
| 1 | source-family off host suffix/path (`law.family.one`) |
| 2 | GAP-145 close — literal zero on dead `KIND_STRING_LIT` / `.string_lit`, not merely unused |
| 3 | host `TokenKind` + `bindKindSchema` bridge death (token-role-id endpoint) |
| 4 | GAP-134 single grammar authority — `grammar_roles.zig` transitional only |
| 5 | Tree-sitter from same grammar owner (never parallel authority) |
| 6 | parser SHC after 2–5 |
| 7 | binding/resolver graph authority |
| 8 | graph ontology reduction (tags → facts; do not rename-only) |
| 9 | world/effect/witness facts |
| 10 | demand producer (REPRESENTATION-ONE blocked until demand executes) |
| 11 | direct backend crashes → 0 (`law.crash.first`) |
| 12 | integrated build/test remeasure at current revision — not assumed green |
| 13 | compiler B |

| # | directive |
|---|---|
| 1 | **Phase shift:** from “remove wrong ontology” to “one ontology produces every fact end-to-end.” Next gates measure **application fact provenance completeness** (`scripts/ledger/application.id`) and **graph sovereignty** (`scripts/ledger/graph.id`) — tag authority, fact cardinality, AST backedges, not merely absence of forbidden names. |

| # | directive |
|---|---|
| 1 | **GRAPH-SOVEREIGNTY** is the highest-impact milestone after GAP-145/GAP-134: the graph must become the semantic spine, not a host-shaped god-record with tags that still decide meaning (`law.tag.authority`, `law.graph.sovereignty`). |

| # | directive |
|---|---|
| 1 | Each workstream item maps to measurable criteria. |
| 2 | No claim is accepted without binding to exact HEAD, dirty state, input, expected/actual result, and environment. |

| section |
|---|---|
| Scoped envelope A–AZ → eight lanes |

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

| # | directive |
|---|---|
| 1 | FTCFTW performance claims remain **invalid** until subject-native correctness and revision-bound measurement close. |
| 2 | No compiler B. |

| section |
|---|---|
| Live claims |

| # | directive |
|---|---|
| 1 | Not recorded here (`law.control.derived`). |
| 2 | Read `.agents/session/claims/` or run `scripts/ledger/claim.id`. |
| 3 | Acquire via `idol_dev_claim_acquire` before lane-owned edits. |

| section |
|---|---|
| A — SOURCE/LEXER SHC |

| # | directive |
|---|---|
| 1 | Current exact state: |

| # | directive |
|---|---|
| 1 | `src/lexer_dispatch.zig` `route()` calls `tokenize()` for **every** source. `tokenizeHost(allocator, src, file)` exists only inside `differential()`. The origin-audit "canonical `.id` still tokenizeHost" claim is **stale**. |
| 2 | `src/lexer_bridge.zig` / sourceFacts — suffix/path still produces source law |
| 3 | Generated `src/lexer_tokenize.c` is from current `lib/compiler/lexer.id` via `idol dump-c --lib` (no `@`, no `std`/`token.KIND_*` table walk; kinds are ordinal immediates matching `compiler/token.id`; `lookup` is spelling → ordinal; `Lexer.family` set once in `new()`). Proved: `idol check` on `.id` including `#` comments and `'A'` bytes; `scripts/ledger/shc.id` PASS. |
| 4 | `is_canonical_source` deleted from the Idol producer. Suffix bytes remain only inside `Lexer.new()`; host `sourceFacts` is still a second producer (ingress debt) |
| 5 | Host `RECORD_SLOTS`, `lexErrorFromCode`, and `tokenKindFromOrdinal` are **deleted**; consumer queries `recordslots()` / `field*()` / `rejectionname()` / `kindname()` / `kindcount()`; `bindKindSchema` binds ordinals once (`law.schema.one`, `law.magic.zero`). Remaining: host `TokenKind` enum, `duo_lexer_*` / `useDuoTokens` names |
| 6 | GAP-145 — `KIND_STRING_LIT=3` remains; identities appended, not closed. Do not close with plural `bytes`. Parser long-bracket reconstruction deleted. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [x] `route()` production path is `tokenize()`, not `tokenizeHost` |
| 2 | [x] `tokenizeHost` remains only as differential oracle |
| 3 | [x] `scripts/ledger/shc.id` convicts production `tokenizeHost(alloc, zsrc, zfile)` and keeps differential `tokenizeHost(allocator, src, file)` |
| 4 | [x] producer schema queries replace host `RECORD_SLOTS` / magic ordinals / rejection codes (`recordslots`, `field*`, `rejectionname`, `kindname`) |
| 5 | [x] host-authored `TokenKind` enum deleted; `lexer.zig` aliases the owner-generated projection |
| 6 | [ ] parser consumes token-role-id directly; generated `TokenKind` bridge deleted |
| 7 | [ ] `duo_lexer_*` / `useDuoTokens` deleted (`law.bridge.death`) |
| 8 | [ ] source-family fact produced by Idol, not suffix/path |
| 9 | [ ] GAP-145 closed: distinct canonical identities for all token classes |
| 10 | [ ] Zero host semantic fallback after resolution |
| 11 | [ ] `tokenizeHost` oracle scoped to legacy-equivalent subset and deletable |

| # | directive |
|---|---|
| 1 | Current debt count: 5 exact blockers (generated TokenKind bridge, bridge names, ingress fact, identity close, oracle bound) |

| section |
|---|---|
| B — GRAMMAR/PARSER SHC |

| # | directive |
|---|---|
| 1 | Current exact state: |

| # | directive |
|---|---|
| 1 | `src/parser.zig` — host-owned production recognition |
| 2 | GAP-134 — grammar-role authority incomplete (blocked on GAP-145) |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] One machine-readable grammar-role authority |
| 2 | [ ] Idol parser consumes immutable token/role projection |
| 3 | [ ] No duplicated handwritten parser vocabulary |

| # | directive |
|---|---|
| 1 | Current debt count: 2 exact blockers |

| section |
|---|---|
| C — RESOLVER/GRAPH |

| # | directive |
|---|---|
| 1 | **Owner: Codex (designated). |
| 2 | Status: blocked until acquire.** No other lane mints relation catalogs, boolean-mirror rows, string worlds, or numeric semantic codes as substitutes. |
| 3 | Devin is A/B SHC transfer, not a second graph ontology. |

| # | directive |
|---|---|
| 1 | Current exact state: |

| # | directive |
|---|---|
| 1 | Binding/scope, graph construction, query remain host-owned |
| 2 | Descriptor recursion walks `.descriptor_ref` exact-id edges (progress) |
| 3 | `lib/semantic/*` relation registry **deleted** (`law.catalog.zero`); boolean-mirror rows (`callable`/`possessed`/`operation`/string `world`) are added-line illegal (`law.boolean.mirror.zero`) |
| 4 | NodeKind / EdgeKind still carry stale ontology (see compass). Target: `module`→provenance facts; `func`/`call`→application facts; `param`/`local`→ binding roles; `type_node`→descriptor id; `contains`/`home`→`member`; `use`→exact binding ref; `transform_output`→operand/result/provenance on transformation identity. Tags remain as indexes until facts subsume them. |
| 5 | Origin-audit "19 semantic_graph build errors" is **stale** — do not cite; re-measure on this HEAD before using as a blocker count |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Idol produces exact binding/relation/subject/descriptor/capture/world edges |
| 2 | [ ] Zero semantic rediscovery after resolution |
| 3 | [ ] `graph.get(exact-id)` only; no string-keyed semantic lookup |
| 4 | [ ] Zero parent-scope lookup after resolution |
| 5 | [ ] No operational edge kinds; application owns relation id |

| # | directive |
|---|---|
| 1 | Current debt count: 3 exact blockers + ontology audit (not a rename pass) |

| section |
|---|---|
| D — CANONICAL SOURCE |

| # | directive |
|---|---|
| 1 | Current exact state: |

| # | directive |
|---|---|
| 1 | `docs/spec/canonical.md` training-surface regressions from the origin audit are **closed** at live HEAD (chained `validate():normalize()`, no `value:to()` rung, SOURCE-INFER-ONE / INTERMEDIATE-ZERO in §18a) |
| 2 | Corpus still contains bracket indexing, inferable `:to`, plurals, one-use temporaries, residual `end`, stale conversion comments |
| 3 | Added-line gates ≠ whole-corpus closure |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [x] `canonical.md` / `agent.md` / HARNESS match current ruling (keep aligned) |
| 2 | [ ] SOURCE-INFER-ONE applied globally in corpus (not just docs) |
| 3 | [ ] `x[key]` replaces call-shaped / `:get(` indexing for computed projection |
| 4 | [ ] Intermediate-zero: no avoidable `tmp`/`result`/`checked`/`current`/`next` |
| 5 | [ ] Whole-corpus gate exists and fails closed (reject; do not rewrite as SHC) |

| # | directive |
|---|---|
| 1 | Current debt count: corpus categories remain open; doc teaching closed |

| section |
|---|---|
| E — WORLD/EFFECT |

| # | directive |
|---|---|
| 1 | Current exact state: |

| # | directive |
|---|---|
| 1 | Filesystem ingress still conflatable with runtime file authority |
| 2 | Runtime world abstraction still present when witness can be known |
| 3 | Re-measure `gate/host.id` on this HEAD before citing PASS/FAIL |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] `gate/host.id` passes on current HEAD |
| 2 | [ ] Known witness → zero runtime world abstraction |
| 3 | [ ] Filesystem ingress separated from runtime file authority |
| 4 | [ ] No capability objects, world classes, protocol objects |

| section |
|---|---|
| F — DEMAND |

| # | directive |
|---|---|
| 1 | Current exact state: demand host-owned; no Idol producer. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Idol produces exact demand facts |
| 2 | [ ] Undemanded work deleted before realization |

| # | directive |
|---|---|
| 1 | Current debt count: 1 exact blocker |

| section |
|---|---|
| G — SHAPE/CALL/CLOSURE SPECIALIZATION |

| # | directive |
|---|---|
| 1 | Re-measure emission counts on this HEAD. |
| 2 | Origin-audit boxing/indirect/heap closure numbers are directional, not current evidence. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Known shape → generic hash 0 |
| 2 | [ ] Exact sealed target → indirect call 0 |
| 3 | [ ] Known captures → capture discovery 0 |
| 4 | [ ] Nonescaping closure → heap environment 0 |

| section |
|---|---|
| H — VALUE/PLACE/MEMORY |

| # | directive |
|---|---|
| 1 | Re-measure allocation/copy emissions on this HEAD. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Stack/heap/static/region chosen from lifetime/escape/alias facts |
| 2 | [ ] No GC because "table" exists |
| 3 | [ ] No allocation without proved observability |

| section |
|---|---|
| I — EFFECT/FUSION/SIMD |

| # | directive |
|---|---|
| 1 | Current exact state: not implemented as graph-fact-driven optimization. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Effects drive CSE/hoisting/fusion/parallelization/SIMD legality |
| 2 | [ ] map/filter/reduce fuse to one loop when facts permit |
| 3 | [ ] No target-qualified semantic relation ids |

| section |
|---|---|
| J — NATIVE MACHINE |

| # | directive |
|---|---|
| 1 | Current exact state: generated C remains bounded bridge; direct native is not yet the production destination for the full corpus. |
| 2 | Integrated unit/DNB counts are **not** recorded here (`law.control.derived`, `law.evidence.subject`). |
| 3 | Re-measure at the live revision before citing pass/fail/crash; crash count is P0 above pass-count improvement (`law.crash.first`). |
| 4 | Last bound subject: `29f62035` / evidence `59093d7b` in `evidence/EVIDENCE_BUNDLE.md`. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Direct backend executes all semantically valid programs |
| 2 | [ ] Semantic graph → demand → realization → instruction → object bytes |
| 3 | [ ] C bridge reduced to bootstrap only, with deletion witness |

| section |
|---|---|
| K — WASM |

| # | directive |
|---|---|
| 1 | Current exact state: no correctness-locked pinned Wasmtime matrix on this HEAD. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Pinned Wasmtime comparison with exact revision |
| 2 | [ ] Separate measurements: compile/load, instantiate/startup, execution, RSS, bytes |
| 3 | [ ] No combined vanity score |

| section |
|---|---|
| L — COMPILE-TIME |

| # | directive |
|---|---|
| 1 | Current exact state: dense-id / packed-fact / exact-invalidation / parallel analysis not closed. |
| 2 | Lexer bridge still copies source + filename + `len × 7 × i64` records + host `Token` array. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Dense ids with arena allocation |
| 2 | [ ] Parallel semantic analysis by exact dependencies |
| 3 | [ ] Exact invalidation on source change |
| 4 | [ ] No string-keyed semantic maps |
| 5 | [ ] Lexer: source → immutable token view → parser (no pessimistic record buffer, no second token materialization) |

| section |
|---|---|
| M — EVIDENCE |

| # | directive |
|---|---|
| 1 | Current exact state: FTCFTW complete proof near zero. `scripts/ledger/ftcftw.id` is a contract-presence index (exit 0 on this tree; pass ≠ proof). |
| 2 | Parent `scripts/ledger/perf.id` rows `ledger/ftcftw`. |
| 3 | Curry `audit(path)(pattern)` is IMPLEMENTATION-BLOCKED (direct native SIGSEGV). |
| 4 | Stale bundles do not certify this HEAD. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Every claim binds subject revision and evidence revision separately (`law.evidence.subject`); do not report metrics "at HEAD" unless the measured subject equals HEAD |
| 2 | [ ] Every claim binds dirty state, input, expected/actual result, CPU/features, target, compiler mode, competitor version, compile, startup, runtime, memory, binary size, sample count, variance |
| 3 | [ ] Positive damage controls: forced allocation, indirect, hash, copy, delay, pad |
| 4 | [ ] No damage sensitivity → evidence invalid |
| 5 | [ ] No semantic equivalence → benchmark invalid |

| section |
|---|---|
| N — COMPILER B/C |

| # | directive |
|---|---|
| 1 | Current exact state: no compiler B; no compiler C; repository remains S0. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] Compiler B built from canonical Idol |
| 2 | [ ] Compiler B builds C |
| 3 | [ ] Exact graph correspondence between B and current compiler |
| 4 | [ ] No host semantic fallback |

| section |
|---|---|
| GLOBAL ZERO TARGET (non-negotiable) |

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

| section |
|---|---|
| Scoped checklist A–AZ (subject `29f62035`) |

| # | directive |
|---|---|
| 1 | Authority / SHC: [ ] A source-family fact not suffix [ ] B producer token schema [ ] C magic-code zero [ ] D token-role-id not ordinal [ ] E GAP-134 grammar roles [ ] F parser facts not AST [ ] G exact binding id [ ] H ontology decomposition [ ] I edge minimization [ ] J application fact completion [ ] K world/effect/witness [ ] L protocol satisfaction [ ] M infer composition [ ] N demand stage |

| # | directive |
|---|---|
| 1 | Physical FTCFTW: [ ] O boxing [ ] P direct calls [ ] Q table hash zero [ ] R closure spec [ ] S alloc [ ] T copy [ ] U tags [ ] V packs [ ] W effects [ ] X fusion [ ] Y SIMD [ ] Z parallel |

| # | directive |
|---|---|
| 1 | Native: [ ] AA direct I/O [ ] AB direct coverage [ ] AC C-bridge death [ ] AD machine lineage |

| # | directive |
|---|---|
| 1 | Compile-time: [ ] AE lexer bridge copies [ ] AF dense storage [ ] AG exact invalidation [ ] AH parallel analysis [ ] AI string-free hot paths |

| # | directive |
|---|---|
| 1 | Wasm: [ ] AJ same graph [ ] AK runtime arch [ ] AL Wasmtime matrix |

| # | directive |
|---|---|
| 1 | Runtime/size: [ ] AM feature elimination [ ] AN startup [ ] AO binary size |

| # | directive |
|---|---|
| 1 | Corpus/enforcement: [ ] AP no cls:has identity [ ] AQ shell bridge bounded [ ] AR no generic main in tooling [ ] AS generic-action zero [ ] AT foundation-word zero |

| # | directive |
|---|---|
| 1 | Evidence: [ ] AU evidence-subject machine-readable [ ] AV status-doc discipline [ ] AW oracle bounded [ ] AX gate adversaries [ ] AY compiler B [ ] AZ compiler C |

| section |
|---|---|
| Optimization architecture 1–35 → workstreams |

| # | directive |
|---|---|
| 1 | Explicit FTCFTW closure items (post catalog-deletion phase). |
| 2 | Full item text and acceptance: `docs/spec/realization.md`. |
| 3 | C0: `law.representation.one`, `law.guard.one`, `law.specialize.budget`, `law.abi.internal`, `law.crash.first`, `law.cost.explain`, `law.representation.demand`. |

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

| section |
|---|---|
| Updated critical path (P0–P3) |

| # | directive |
|---|---|
| 1 | **P0 — correctness / authority** |

| # | directive |
|---|---|
| 1 | source-family authority off path/suffix (`law.family.one`) |
| 2 | finish GAP-145 lexical identities |
| 3 | producer-owned token ABI/schema; eliminate magic slots/codes/ordinal duplication (GAP-107) |
| 4 | grammar-role authority / GAP-134 |
| 5 | Idol parser |
| 6 | exact resolver/graph |
| 7 | world/effect/witness |
| 8 | demand |
| 9 | direct backend crashes/failures to zero (`law.crash.first`) |

| # | directive |
|---|---|
| 1 | **P1 — FTCFTW cost collapse** |

| # | directive |
|---|---|
| 1 | representation-one · 11. boxing elimination · 12. call specialization · |
| 2 | shape specialization · 14. closure escape specialization · |
| 3 | allocation/region selection · 16. copy elimination · |
| 4 | tag/refinement elimination · 18. pack/ABI specialization · |
| 5 | bounds/range elimination · 20. string/interpolation fusion · |
| 6 | table layout polymorphism · 22. metamethod specialization · |
| 7 | effect/fusion/SIMD · 24. concurrency realization · |
| 8 | runtime feature DCE · 26. link-time reachability |

| # | directive |
|---|---|
| 1 | **P2 — compile/startup/tooling superiority** |

| # | directive |
|---|---|
| 1 | lexer/token bridge zero-copy · 28. dense graph storage · |
| 2 | exact incremental invalidation · 30. parallel compiler · |
| 3 | stage-result caching · 32. direct object writer optimization · |
| 4 | LSP same-graph · 34. MCP same-graph · 35. replace semantic grep/census |

| # | directive |
|---|---|
| 1 | **P3 — proof** |

| # | directive |
|---|---|
| 1 | all crashes zero · 37. complete correctness matrix · |
| 2 | C-equivalent benchmark suite · 39. pinned Wasmtime suite · |
| 3 | positive damage controls · 41. startup/memory/size/compile/runtime separately · |
| 4 | B compiler · 43. C compiler · 44. semantic fixed-point evidence |

| # | directive |
|---|---|
| 1 | Phase conclusion: architecture leaves obvious anti-pattern cleanup; remaining risk is optimization architecture — representation ownership, guard/deopt, ABI, range/bounds, layout polymorphism, effect fusion, semantic incremental compilation, causal optimization diagnostics. |
| 2 | Without explicit workstreams above, implementation can stay semantically clean yet realize everything conservatively and fail FTCFTW. |

| section |
|---|---|
| BA — REPRESENTATION / GUARD / SPECIALIZE (items 1–3, P1) |

| # | directive |
|---|---|
| 1 | Current exact state: host lowering (`src/dnir_lower.zig`, `src/native_backend.zig`) still makes ad hoc boxing/register/heap decisions. |
| 2 | Measured subject still shows ~1,271 `lua_Value`, ~120 `malloc`, ~174 tag/union sites. |

| # | directive |
|---|---|
| 1 | Measurable acceptance criteria: |

| # | directive |
|---|---|
| 1 | [ ] One realization owner produces width/layout/location/boxing/addressability/aggregation/calling-convention facts |
| 2 | [ ] No downstream pass separately chooses boxed/stack/register/heap/struct/SIMD |
| 3 | [ ] Guard = unresolved semantic alternative with witness + recovery + provenance |
| 4 | [ ] Specialization obeys code-growth law (runtime gain vs compile+size+I-cache+startup) |
| 5 | [ ] Same semantic id for specialized clones; metrics per specialization site |

| section |
|---|---|
| BB — ABI / TAIL / PACK (items 4–5) |

| # | directive |
|---|---|
| 1 | [ ] Semantic pack → demanded physical slots → target ABI assignment |
| 2 | [ ] Optimized internal ABI; foreign ABI only at boundary |
| 3 | [ ] Tail expressions → frame reuse where lawful |
| 4 | [ ] No tuple materialization / unnecessary sret / temp pack for undemanded results |

| section |
|---|---|
| BC — NUMERIC / REFINE / BOUNDS (items 6–8) |

| # | directive |
|---|---|
| 1 | [ ] Width/range/sign/overflow facts survive to realization |
| 2 | [ ] Branch facts (`x < 256`) propagate through arithmetic, index, SIMD, narrowing |
| 3 | [ ] Bounds metric: emitted / proven-unnecessary / remaining + reason |

| section |
|---|---|
| BD — STRING / TABLE / META (items 9–11) |

| # | directive |
|---|---|
| 1 | [ ] String realization tiers + concat/interpolation fusion |
| 2 | [ ] Table layout ladder (dynamic → shape → sealed → dense → compile-time) |
| 3 | [ ] Metamethod dispatch through application facts; zero machinery when unused |

| section |
|---|---|
| BE — CORO / CONCUR / REGION / ALIAS (items 12–15) |

| # | directive |
|---|---|
| 1 | [ ] Coroutine tiers from suspend/escape facts; zero link when unused |
| 2 | [ ] Concurrency realization from isolation/effect facts; no mandatory scheduler |
| 3 | [ ] Whole-app region/arena selection; graph-native alias/escape/last-use |

| section |
|---|---|
| BF — LAYOUT / ERROR / STAGE / TRANSFORM (items 16–21) |

| # | directive |
|---|---|
| 1 | [ ] AoS/SoA/AoSoA from demand; code layout from profile evidence only |
| 2 | [ ] Rare errors on cold paths; hot path unp poisoned |
| 3 | [ ] Stage cache keyed on semantic dependencies |
| 4 | [ ] One transformation algebra with shared provenance records |

| section |
|---|---|
| BG — REACH / LINK / FFI / WASM / OBJ (items 22–27) |

| # | directive |
|---|---|
| 1 | [ ] Sealed reachability DCE; link-time semantic reachability |
| 2 | [ ] FFI cost isolated to boundary; Wasm import/export specialization |
| 3 | [ ] Direct object writer: no intermediate assembly text |

| section |
|---|---|
| BH — TOOLING / GATES / DIAGNOSTICS (items 28–35) |

| # | directive |
|---|---|
| 1 | [ ] Incremental invalidation on semantic application dependency (28) |
| 2 | [ ] LSP + MCP query same graph — no parallel models (29–30) |
| 3 | [ ] Shell grep census → MCP/graph violations — CENSUS-DEATH (31) |
| 4 | [ ] Dual debt gates: new=0, total monotonic decrease per category (32) |
| 5 | [ ] Crashes = P0 above wrong diagnostic / reject / opt miss (33, `law.crash.first`) |
| 6 | [ ] DNB bail codes name application + missing fact + producer (34) |
| 7 | [ ] OPT-EXPLAIN: why boxed/allocated/indirect answerable from facts (35) |

| section |
|---|---|
| BI — GRAPH SOVEREIGNTY (items G1–G12, P0 lane 3) |

| # | directive |
|---|---|
| 1 | Full definitions: `docs/spec/realization.md` § Graph sovereignty. |
| 2 | Laws in C0 §67. |
| 3 | File audit: `scripts/ledger/graph.id`. |

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

| # | directive |
|---|---|
| 1 | Measurable acceptance: |

| # | directive |
|---|---|
| 1 | [ ] No query/lowering uses NodeKind/EdgeKind to establish semantic validity |
| 2 | [ ] Fact-location manifest: one authoritative owner per application dimension |
| 3 | [ ] Unknown / known-absent / exact-id distinguishable on optional facts |
| 4 | [ ] Semantic `ast_ref` reads = 0; diagnostic-only reads inventoried |
| 5 | [ ] Node record decomposed to columnar/sparse fact storage |
| 6 | [ ] Operand/result/capture queries borrow packed ranges (no dupe on hot path) |
| 7 | [ ] Caller→application and home→member adjacency indexed (not full scans) |
| 8 | [ ] `module_path` and module tag eliminated; home/member/provenance only |
| 9 | [ ] Graph core does not import AST/sema/transform to define ontology |

---

| section |
|---|---|
| Impact-ordered next fixes |

| # | directive |
|---|---|
| 1 | Last bound evidence subject `29f62035` (catalog deletion slice). |
| 2 | Live HEAD, dirty tree, lane holders, and integrated counts are obtained from `git`, `tools/node/dev/orient`, and a fresh measurement run — not this register (`law.control.derived`, `law.evidence.subject`). |

| # | directive |
|---|---|
| 1 | **Keep `lib/semantic/*` dead** — gates + `resident-proof`; no catalog resurrection. |
| 2 | **P0 authority chain** — source-family → GAP-145 → token ABI → GAP-134 → parser → graph → demand → crash/fail zero (see P0 list above). |
| 3 | **NodeKind / EdgeKind fact decomposition** — tags are physical indexes only. |
| 4 | **P1 optimization architecture** — items 1–26 before revision-bound FTCFTW performance claims; each physical cost names missing facts or deletes. |
| 5 | **P2 tooling** — semantic incremental invalidation, LSP/MCP same-graph, census death; P3 proof matrix and B/C only after correctness green. |
