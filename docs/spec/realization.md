| field | value |
|---|---|
| title | Realization workstreams (projection) |

| # | directive |
|---|---|
| 1 | Projection of C0 (`docs/spec/constitution.md` §67): `law.representation.one`, `law.guard.one`, `law.specialize.budget`, `law.abi.internal`, `law.error.cold`, `law.crash.first`, `law.cost.explain`, `law.representation.demand`, `law.profile.evidence`. |
| 2 | Not a second semantic law. |
| 3 | Conflict → repair this file. |

| # | directive |
|---|---|
| 1 | Measurable checkboxes: `WORKSTREAM_DEBT_REGISTER.md` (BA–BH). |
| 2 | Lane owners: `.agents/AGENT_COORDINATION.md`. |
| 3 | Compass: `.agents/TECH_DEBT_WORKSTREAM.md`. |

| # | directive |
|---|---|
| 1 | Executed frontier remains S0. |
| 2 | No compiler B. |
| 3 | Complete FTCFTW is **not** proven. |
| 4 | P1 items do not authorize host lowering patches that re-decide representation (`src/dnir_lower.zig`, `src/native.zig`) before the single realization owner exists. |

| # | directive |
|---|---|
| 1 | Evidence subject `29f62035` · evidence revision `59093d7b`. |
| 2 | Live Git HEAD is not recorded here (`law.control.derived`). |
| 3 | Do not report costs “at HEAD” unless the measured subject equals the live tree. `59093d7b` is the measurement commit, not current Git HEAD. |

| section |
|---|---|
| Why this list is explicit |

| # | directive |
|---|---|
| 1 | Catalog deletion and Idol-first lexing closed the obvious anti-pattern phase. |
| 2 | Remaining FTCFTW risk is **conservative realization**: a clean graph that still boxes, allocates, indirects, and guards everything because no one owned the physical decision. |
| 3 | These 35 items are workstreams, not optimizer kingdoms. |

| # | directive |
|---|---|

| section |
|---|---|
| 1. REPRESENTATION-ONE (`law.representation.one`) · lane 4 |

| # | directive |
|---|---|
| 1 | One producer. |
| 2 | Inputs: descriptor, lifetime, alias, mutation, escape, demand, ABI, target. |
| 3 | Output: one realization. |

| # | directive |
|---|---|
| 1 | Owns: width, layout, location, boxing, addressability, aggregation, calling convention. |

| # | directive |
|---|---|
| 1 | A semantic value has **no** physical representation until demand requires one. |
| 2 | No downstream pass separately decides boxed / stack / register / heap / struct / SIMD. |
| 3 | FTCFTW is not a sequence of representation repairs. |

| section |
|---|---|
| 2. Guard / deopt (`law.guard.one`) · lane 5 |

| # | directive |
|---|---|
| 1 | Guard = unresolved semantic alternative whose fast realization depends on a fact. |
| 2 | Not a pass artifact, type-check object, generic runtime check, or a reason to box everything. |

| # | directive |
|---|---|
| 1 | fact known → guard 0 |
| 2 | fact speculated from evidence → exact guard + exact slow alternative |
| 3 | fact unknown → lawful general realization |

| # | directive |
|---|---|
| 1 | Every guard retains: assumed fact, witness/evidence, recovery realization, provenance. |
| 2 | Profile is evidence, never truth (`law.profile.evidence`). |

| section |
|---|---|
| 3. Specialize budget (`law.specialize.budget`) · lane 4 |

| # | directive |
|---|---|
| 1 | Specialize when expected runtime gain > compile cost + code size + I-cache + startup. |
| 2 | Same semantic id; clones are not new identities. |
| 3 | Record: applications benefiting, branches/allocs/indirects removed, bytes added, compile time added. |

| section |
|---|---|
| 4. ABI specialization (`law.abi.internal`) · lane 4 |

| # | directive |
|---|---|
| 1 | Semantic pack → demanded physical slots → target ABI. |
| 2 | Internal calls: register args/returns, aggregate elision, no tuple/sret/temp pack, tail-call layout. |
| 3 | Foreign ABI only at an actual foreign boundary. |

| section |
|---|---|
| 5. Tail call / tail expression · lane 4 |

| # | directive |
|---|---|
| 1 | `walk = (x) next(x)` → frame reuse where lawful; tail recursion → loop; stack-depth proof where demanded. |
| 2 | Concise source must not become conventional recursive call overhead. |

| section |
|---|---|
| 6. Numeric FTCFTW · lane 4–5 |

| # | directive |
|---|---|
| 1 | Width, sign, range, overflow law, NaN/Inf, alignment, vectorizability, constantness survive to machine. `i64` in source is descriptor demand, not instruction width. |
| 2 | Range `0..255` → narrower lane, vector candidate, no overflow guard if proven. |

| section |
|---|---|
| 7. Range / refinement · lane 5 |

| # | directive |
|---|---|
| 1 | `if x < 256 use(x)` carries `x < 256` through arithmetic, indexing, bounds, SIMD, narrowing, switch prune, allocation size. |
| 2 | Refinement is a graph fact that must reach realization. |

| section |
|---|---|
| 8. Bounds-check metric · lane 5 |

| # | directive |
|---|---|
| 1 | For `x(i)`: remove when loop range, shape/cardinality, or caller demand proves it. |
| 2 | Track emitted / proven-unnecessary+reason / remaining+reason. |

| section |
|---|---|
| 9. String realization + fusion · lane 5 |

| # | directive |
|---|---|
| 1 | Tiers: borrowed view; static literal; inline small text; slice+length; owned buffer; rope/segmented only if justified; interned identity when semantics require. `stdout:write("hello {name}")` streams or sizes once — no allocate-copy-copy-write when legal. |

| section |
|---|---|
| 10. Table realization tiers · lane 5 |

| # | directive |
|---|---|
| 1 | One semantic table. |
| 2 | Physical ladder: unknown dynamic → hash; stable keyed shape → specialized storage; sealed record → native struct/scalars; dense ordinal → flat contiguous; compile-time → disappear. |

| section |
|---|---|
| 11. Metatable / metamethod · lane 5 |

| # | directive |
|---|---|
| 1 | Unknown → dynamic; stable → exact relation; sealed → inline; unused → zero machinery. |
| 2 | Same application/relation facts. |
| 3 | No second metamethod compiler. |

| section |
|---|---|
| 12. Coroutine tiers · lane 5 |

| # | directive |
|---|---|
| 1 | Never suspends → ordinary function; nonescaping suspend → compact state; general → runtime; cross-thread → scheduler only if demanded. |
| 2 | Unused → zero link. |

| section |
|---|---|
| 13. Concurrency realization · lane 5 |

| # | directive |
|---|---|
| 1 | Facts: ownership/isolation, mutation, shared reachability, effect independence, blocking, cancellation, ordering, world interactions. |
| 2 | Realization: inline / worker / thread / event / async syscall / SIMD-parallel / GPU. |
| 3 | No mandatory scheduler for ordinary programs. |

| section |
|---|---|
| 14. Region / arena · lane 5 |

| # | directive |
|---|---|
| 1 | Whole-app lifetime, not only per-object escape: arena, region, bump, stack, static, reuse. |
| 2 | Temporaries that die together → one region, one release. |

| section |
|---|---|
| 15. Lifetime / alias provenance · lane 5 |

| # | directive |
|---|---|
| 1 | Graph-native: alias?, escape?, last use?, reusable? |
| 2 | Conservative fallback blocks SIMD, stack promotion, mutation reorder, copy elimination. |
| 3 | Provenance survives transforms. |

| section |
|---|---|
| 16. SoA / AoS layout · lane 5 |

| # | directive |
|---|---|
| 1 | Homogeneous collections: AoS / SoA / AoSoA / vectorized blocks from demand. |
| 2 | Semantic table does not fix physical layout. |

| section |
|---|---|
| 17. Code / branch layout · lane 5 |

| # | directive |
|---|---|
| 1 | Branch probability, cold error isolation, hot target proximity, function/block order. |
| 2 | Profile is evidence, never truth. |
| 3 | Correct without it. |

| section |
|---|---|
| 18. Error paths cold (`law.error.cold`) · lane 5 |

| # | directive |
|---|---|
| 1 | Rare failure must not force boxed result, tagged union, heap, or a branch on every operation. |
| 2 | Cold continuation; hot layout stays the success realization. |

| section |
|---|---|
| 19. Stage cache + purity · lane 6 |

| # | directive |
|---|---|
| 1 | Exact dependencies, effect/world facts, deterministic witness, stage provenance. |
| 2 | Cache key from semantic dependencies, not source-text hash. |
| 3 | Invalidate only when dependencies change. |

| section |
|---|---|
| 20. Generated-code lineage · lane 6 |

| # | directive |
|---|---|
| 1 | Every generated fact points to generator application, source facts, stage, world, demand, resulting identities. |
| 2 | Never an opaque blob that must be reparsed to recover meaning. |

| section |
|---|---|
| 21. Transformation convergence · lane 6 |

| # | directive |
|---|---|
| 1 | One transformation algebra. |
| 2 | Inliner, rewrite, macro, vector, staging may use distinct physical algorithms but record the same: input ids, required facts, output ids, eliminated alternatives, provenance. |

| section |
|---|---|
| 22. Determinism · lane 6 |

| # | directive |
|---|---|
| 1 | Same source + world + target + compiler revision → deterministic graph and realization unless evidence explicitly permits nondeterminism. |
| 2 | Required for cache, B/C, benchmarks, agent debug. |
| 3 | Explicit tests. |

| section |
|---|---|
| 23. Whole-program reachability DCE · lane 6 |

| # | directive |
|---|---|
| 1 | Sealed programs: exact reachable applications, then delete unused relations, descriptors, worlds, runtime features, foreign bridges, diagnostics, metadata. |

| section |
|---|---|
| 24. Link-time semantic reachability · lane 6 |

| # | directive |
|---|---|
| 1 | Carry reachability into section inclusion, dedup, runtime-support selection, visibility. |
| 2 | The system linker receives already-minimal input. |

| section |
|---|---|
| 25. FFI boundary · lane 6 |

| # | directive |
|---|---|
| 1 | Idol value → demanded ABI projection → foreign call → result projection. |
| 2 | Cost isolated to the boundary. |
| 3 | No global CValue / FFIValue / boxed foreign kingdom. |

| section |
|---|---|
| 26. Wasm import/export · lane 7 |

| # | directive |
|---|---|
| 1 | Fixed import → no generic trampoline; specialize memory; omit unused tables; direct-call known functions; minimize metadata; precompute init. |
| 2 | Startup and size vs Wasmtime, not only execution. |

| section |
|---|---|
| 27. Direct object writer · lane 6 |

| # | directive |
|---|---|
| 1 | Single-pass section sizing, compact relocs, arena symbols/fixups, deterministic order, no intermediate assembly text. |

| section |
|---|---|
| 28. Semantic incremental invalidation · lane 8 |

| # | directive |
|---|---|
| 1 | Changed binding/application fact → invalidate exact dependent closure. |
| 2 | Not changed file → recompile module. |
| 3 | Files cease to be compilation units after ingestion. |

| section |
|---|---|
| 29. LSP same-graph · lane 8 |

| # | directive |
|---|---|
| 1 | Hover, completion, rename, navigation, diagnostics, coloring query exact semantic ids. |
| 2 | No parallel LSP semantic model. |

| section |
|---|---|
| 30. MCP same-graph · lane 8 |

| # | directive |
|---|---|
| 1 | Agents query id / relation / subject / application / provenance / demand / realization. |
| 2 | Replaces shell census as the semantic interface. |

| section |
|---|---|
| 31. Census / shell → graph query · lane 8 |

| # | directive |
|---|---|
| 1 | Regex gates stay at lexical ingress. |
| 2 | Long-term semantic auditors are graph/MCP violation identities, not grep/awk/wc/filename patterns. |

| section |
|---|---|
| 32. Dual debt gates · lane 8 |

| # | directive |
|---|---|
| 1 | New debt = 0 always. |
| 2 | Total debt monotonically decreases per category until 0. |
| 3 | Changed-line rejection alone preserves historical islands. |

| section |
|---|---|
| 33. Crashes first (`law.crash.first`) · lane 6 |

| # | directive |
|---|---|
| 1 | Crash > wrong diagnostic > reject valid > optimization miss. |
| 2 | Every crash is an immediate P0. |
| 3 | Performance work on an unstable backend is not evidence. |

| section |
|---|---|
| 34. Causal backend refusal (`law.cost.explain`) · lane 6 |

| # | directive |
|---|---|
| 1 | DNB-style bail names: application id, missing fact/capability, consumer, expected producer — never “unsupported.” |

| section |
|---|---|
| 35. Optimization-miss diagnostics (`law.cost.explain`) · lane 8 |

| # | directive |
|---|---|
| 1 | Why boxed / allocated / indirect / not SIMD / copied / hashed → unresolved fact. |
| 2 | MCP `explain application N realization` answers from the graph. |

| section |
|---|---|
| Cross-cutting compile-time · FACT-LOCALITY (`law.fact.locality`) |

| # | directive |
|---|---|
| 1 | As graph consumption grows, do not pay per-instruction global hash lookups or edge scans. |
| 2 | After resolution, expose compact application-local ranges or dense-id derived views. |
| 3 | Authority stays in the graph; the hot compile path uses a derived physical view (`law.fact.locality`). |

| # | directive |
|---|---|

| section |
|---|---|
| Graph sovereignty G1–G12 (P0 — before parser SHC closure) |

| # | directive |
|---|---|
| 1 | The surface can look Idollic while the spine remains a host-shaped nullable record with tag-based validity, AST backedges, and duplicated indexes. |
| 2 | These are correctness and compile-time FTCFTW prerequisites — not polish. |

| # | Workstream | Law |
|---|---|---|
| G1 | TAG-AUTHORITY-ZERO | `law.tag.authority` |
| G2 | MODULE-ZERO | `law.module.zero` |
| G3 | APPLICATION-FACT-CLOSURE | `law.application.closure` |
| G4 | FACT-CARDINALITY-ONE | `law.fact.cardinality` |
| G5 | DERIVED-INDEX-ONE | `law.derived.index` |
| G6 | FACT-COLUMN-ONE | `law.fact.column` |
| G7 | storage class / descriptor state audit | `law.representation.one` |
| G8 | State/Recursion/Completion decomposition | C0 identity closure |
| G9 | AST-BACKEDGE-ZERO | `law.ast.backedge` |
| G10 | ZERO-COPY-GRAPH-VIEWS + FACT-LOCALITY indexes | `law.view.zerocopy` · `law.fact.locality` |
| G11 | TARGET-CONTAMINATION + PROSE-FACT-ZERO | `law.target.contamination` · `law.prose.fact` |
| G12 | GRAPH-SOVEREIGNTY | `law.graph.sovereignty` |

| # | directive |
|---|---|
| 1 | **G1:** `.func` / `.module` / `.table_shape` tags must not gate validity — query descriptor, binding, and application facts instead. |

| # | directive |
|---|---|
| 1 | **G3 manifest:** relation→`applicationRelation`; subject→`applicationSubject`; operands/results→packed ranges; descriptor/demand/caller/stage→graph accessors; effect/authority/witness/target/realization→`ApplicationFact` with explicit unknown vs known-absent cardinality (**G4**). |

| # | directive |
|---|---|
| 1 | **G12 milestone:** graph schema = semantic ids + facts + physical derived indexes only |
| 2 | AST/sema/types/transform project in/out — never define ontology. |

| # | directive |
|---|---|
| 1 | Audit: `scripts/ledger/graph.id`. |
| 2 | Gate ratchet: `gate/graph.id` on added lines. |

| # | directive |
|---|---|

| section |
|---|---|
| Critical path (do not reorder) |

| # | directive |
|---|---|
| 1 | **P0 — correctness / authority** |

| # | directive |
|---|---|
| 1 | source-family off path/suffix (`law.family.one`) — admitted source → family fact |
| 2 | GAP-145: zero downstream observers of collapsed `KIND_STRING_LIT` / `.string_lit` |
| 3 | producer token ABI/schema (GAP-107); `bindKindSchema` deletion-gated → token-role-id |
| 4 | GAP-134 GRAMMAR-ONE — one executable grammar owner; `grammar_roles.zig` transitional |
| 5 | Tree-sitter / LSP / MCP / formatter from that same owner |
| 6 | Idol parser (not before GAP-145 remaining observers are gone) |
| 7 | exact resolver/graph; APPLICATION-CONSUMER-ZERO (every lowering field from graph) |
| 8 | decompose any remaining synthetic application identity; graph ontology reduction |
| 9 | world/effect/witness |
| 10 | demand producer; executed REPRESENTATION-ONE |
| 11 | direct backend crashes → 0 (`law.crash.first`); remeasure integrated evidence |
| 12 | compiler B |

| # | directive |
|---|---|
| 1 | **P1 — FTCFTW cost collapse** (after demand + one representation owner) |

| # | directive |
|---|---|
| 1 | 10–26: representation-one, boxing, call/shape/closure specialization, region, copy, tag/refine, pack/ABI, bounds/range, string fusion, table layout, metamethod, fusion/SIMD, concurrency, runtime DCE, link reachability. |

| # | directive |
|---|---|
| 1 | **P2 — compile / startup / tooling** |

| # | directive |
|---|---|
| 1 | 27–35: zero-copy tokens, dense graph, **fact-locality derived views**, exact invalidation, parallel compiler, stage cache, object writer, LSP/MCP same-graph, census death. |

| # | directive |
|---|---|
| 1 | **P3 — proof** |

| # | directive |
|---|---|
| 1 | 36–44: crash 0, correctness matrix, C-equivalent suite, pinned Wasmtime, positive damage controls, separate startup/memory/size/compile/runtime, B, C, semantic fixed-point. |

| # | directive |
|---|---|
| 1 | Without these workstreams the implementation can stay semantically clean and still fail FTCFTW by realizing everything conservatively. |
