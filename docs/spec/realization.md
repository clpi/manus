# Realization workstreams (projection)

Projection of C0 (`docs/spec/constitution.md` §67): `law.representation.one`,
`law.guard.one`, `law.specialize.budget`, `law.abi.internal`, `law.error.cold`,
`law.crash.first`, `law.cost.explain`, `law.representation.demand`,
`law.profile.evidence`. Not a second semantic law. Conflict → repair this file.

Measurable checkboxes: `WORKSTREAM_DEBT_REGISTER.md` (BA–BH). Lane owners:
`.agents/AGENT_COORDINATION.md`. Compass: `.agents/TECH_DEBT_WORKSTREAM.md`.

Executed frontier remains S0. No compiler B. Complete FTCFTW is **not** proven.
P1 items do not authorize host lowering patches that re-decide representation
(`src/dnir_lower.zig`, `src/native.zig`) before the single realization
owner exists.

Evidence subject `29f62035` · evidence revision `59093d7b`. Live Git HEAD is
not recorded here (`law.control.derived`). Do not report costs “at HEAD”
unless the measured subject equals the live tree. `59093d7b` is the
measurement commit, not current Git HEAD.

---

## Why this list is explicit

Catalog deletion and Idol-first lexing closed the obvious anti-pattern phase.
Remaining FTCFTW risk is **conservative realization**: a clean graph that still
boxes, allocates, indirects, and guards everything because no one owned the
physical decision. These 35 items are workstreams, not optimizer kingdoms.

---

## 1. REPRESENTATION-ONE (`law.representation.one`) · lane 4

One producer. Inputs: descriptor, lifetime, alias, mutation, escape, demand,
ABI, target. Output: one realization.

Owns: width, layout, location, boxing, addressability, aggregation, calling
convention.

A semantic value has **no** physical representation until demand requires one.
No downstream pass separately decides boxed / stack / register / heap / struct
/ SIMD. FTCFTW is not a sequence of representation repairs.

## 2. Guard / deopt (`law.guard.one`) · lane 5

Guard = unresolved semantic alternative whose fast realization depends on a
fact. Not a pass artifact, type-check object, generic runtime check, or a
reason to box everything.

- fact known → guard 0
- fact speculated from evidence → exact guard + exact slow alternative
- fact unknown → lawful general realization

Every guard retains: assumed fact, witness/evidence, recovery realization,
provenance. Profile is evidence, never truth (`law.profile.evidence`).

## 3. Specialize budget (`law.specialize.budget`) · lane 4

Specialize when expected runtime gain > compile cost + code size + I-cache +
startup. Same semantic id; clones are not new identities. Record: applications
benefiting, branches/allocs/indirects removed, bytes added, compile time added.

## 4. ABI specialization (`law.abi.internal`) · lane 4

Semantic pack → demanded physical slots → target ABI. Internal calls: register
args/returns, aggregate elision, no tuple/sret/temp pack, tail-call layout.
Foreign ABI only at an actual foreign boundary.

## 5. Tail call / tail expression · lane 4

`walk = (x) next(x)` → frame reuse where lawful; tail recursion → loop;
stack-depth proof where demanded. Concise source must not become conventional
recursive call overhead.

## 6. Numeric FTCFTW · lane 4–5

Width, sign, range, overflow law, NaN/Inf, alignment, vectorizability,
constantness survive to machine. `i64` in source is descriptor demand, not
instruction width. Range `0..255` → narrower lane, vector candidate, no
overflow guard if proven.

## 7. Range / refinement · lane 5

`if x < 256 use(x)` carries `x < 256` through arithmetic, indexing, bounds,
SIMD, narrowing, switch prune, allocation size. Refinement is a graph fact
that must reach realization.

## 8. Bounds-check metric · lane 5

For `x(i)`: remove when loop range, shape/cardinality, or caller demand
proves it. Track emitted / proven-unnecessary+reason / remaining+reason.

## 9. String realization + fusion · lane 5

Tiers: borrowed view; static literal; inline small text; slice+length; owned
buffer; rope/segmented only if justified; interned identity when semantics
require. `stdout:write("hello {name}")` streams or sizes once — no
allocate-copy-copy-write when legal.

## 10. Table realization tiers · lane 5

One semantic table. Physical ladder: unknown dynamic → hash; stable keyed
shape → specialized storage; sealed record → native struct/scalars; dense
ordinal → flat contiguous; compile-time → disappear.

## 11. Metatable / metamethod · lane 5

Unknown → dynamic; stable → exact relation; sealed → inline; unused → zero
machinery. Same application/relation facts. No second metamethod compiler.

## 12. Coroutine tiers · lane 5

Never suspends → ordinary function; nonescaping suspend → compact state;
general → runtime; cross-thread → scheduler only if demanded. Unused → zero
link.

## 13. Concurrency realization · lane 5

Facts: ownership/isolation, mutation, shared reachability, effect
independence, blocking, cancellation, ordering, world interactions.
Realization: inline / worker / thread / event / async syscall / SIMD-parallel
/ GPU. No mandatory scheduler for ordinary programs.

## 14. Region / arena · lane 5

Whole-app lifetime, not only per-object escape: arena, region, bump, stack,
static, reuse. Temporaries that die together → one region, one release.

## 15. Lifetime / alias provenance · lane 5

Graph-native: alias?, escape?, last use?, reusable? Conservative fallback
blocks SIMD, stack promotion, mutation reorder, copy elimination. Provenance
survives transforms.

## 16. SoA / AoS layout · lane 5

Homogeneous collections: AoS / SoA / AoSoA / vectorized blocks from demand.
Semantic table does not fix physical layout.

## 17. Code / branch layout · lane 5

Branch probability, cold error isolation, hot target proximity, function/block
order. Profile is evidence, never truth. Correct without it.

## 18. Error paths cold (`law.error.cold`) · lane 5

Rare failure must not force boxed result, tagged union, heap, or a branch on
every operation. Cold continuation; hot layout stays the success realization.

## 19. Stage cache + purity · lane 6

Exact dependencies, effect/world facts, deterministic witness, stage
provenance. Cache key from semantic dependencies, not source-text hash.
Invalidate only when dependencies change.

## 20. Generated-code lineage · lane 6

Every generated fact points to generator application, source facts, stage,
world, demand, resulting identities. Never an opaque blob that must be
reparsed to recover meaning.

## 21. Transformation convergence · lane 6

One transformation algebra. Inliner, rewrite, macro, vector, staging may use
distinct physical algorithms but record the same: input ids, required facts,
output ids, eliminated alternatives, provenance.

## 22. Determinism · lane 6

Same source + world + target + compiler revision → deterministic graph and
realization unless evidence explicitly permits nondeterminism. Required for
cache, B/C, benchmarks, agent debug. Explicit tests.

## 23. Whole-program reachability DCE · lane 6

Sealed programs: exact reachable applications, then delete unused relations,
descriptors, worlds, runtime features, foreign bridges, diagnostics, metadata.

## 24. Link-time semantic reachability · lane 6

Carry reachability into section inclusion, dedup, runtime-support selection,
visibility. The system linker receives already-minimal input.

## 25. FFI boundary · lane 6

Idol value → demanded ABI projection → foreign call → result projection. Cost
isolated to the boundary. No global CValue / FFIValue / boxed foreign kingdom.

## 26. Wasm import/export · lane 7

Fixed import → no generic trampoline; specialize memory; omit unused tables;
direct-call known functions; minimize metadata; precompute init. Startup and
size vs Wasmtime, not only execution.

## 27. Direct object writer · lane 6

Single-pass section sizing, compact relocs, arena symbols/fixups, deterministic
order, no intermediate assembly text.

## 28. Semantic incremental invalidation · lane 8

Changed binding/application fact → invalidate exact dependent closure. Not
changed file → recompile module. Files cease to be compilation units after
ingestion.

## 29. LSP same-graph · lane 8

Hover, completion, rename, navigation, diagnostics, coloring query exact
semantic ids. No parallel LSP semantic model.

## 30. MCP same-graph · lane 8

Agents query id / relation / subject / application / provenance / demand /
realization. Replaces shell census as the semantic interface.

## 31. Census / shell → graph query · lane 8

Regex gates stay at lexical ingress. Long-term semantic auditors are graph/MCP
violation identities, not grep/awk/wc/filename patterns.

## 32. Dual debt gates · lane 8

New debt = 0 always. Total debt monotonically decreases per category until 0.
Changed-line rejection alone preserves historical islands.

## 33. Crashes first (`law.crash.first`) · lane 6

Crash > wrong diagnostic > reject valid > optimization miss. Every crash is
an immediate P0. Performance work on an unstable backend is not evidence.

## 34. Causal backend refusal (`law.cost.explain`) · lane 6

DNB-style bail names: application id, missing fact/capability, consumer,
expected producer — never “unsupported.”

## 35. Optimization-miss diagnostics (`law.cost.explain`) · lane 8

Why boxed / allocated / indirect / not SIMD / copied / hashed → unresolved
fact. MCP `explain application N realization` answers from the graph.

## Cross-cutting compile-time · FACT-LOCALITY (`law.fact.locality`)

As graph consumption grows, do not pay per-instruction global hash lookups or
edge scans. After resolution, expose compact application-local ranges or
dense-id derived views. Authority stays in the graph; the hot compile path
uses a derived physical view (`law.fact.locality`).

---

## Graph sovereignty G1–G12 (P0 — before parser SHC closure)

The surface can look Idollic while the spine remains a host-shaped nullable
record with tag-based validity, AST backedges, and duplicated indexes.
These are correctness and compile-time FTCFTW prerequisites — not polish.

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

**G1:** `.func` / `.module` / `.table_shape` tags must not gate validity —
query descriptor, binding, and application facts instead.

**G3 manifest:** relation→`applicationRelation`; subject→`applicationSubject`;
operands/results→packed ranges; descriptor/demand/caller/stage→graph accessors;
effect/authority/witness/target/realization→`ApplicationFact` with explicit
unknown vs known-absent cardinality (**G4**).

**G12 milestone:** graph schema = semantic ids + facts + physical derived
indexes only; AST/sema/types/transform project in/out — never define ontology.

Audit: `scripts/ledger/graph.id`. Gate ratchet: `gate/graph.id` on added lines.

---

## Critical path (do not reorder)

**P0 — correctness / authority**

1. source-family off path/suffix (`law.family.one`) — admitted source → family fact
2. GAP-145: zero downstream observers of collapsed `KIND_STRING_LIT` / `.string_lit`
3. producer token ABI/schema (GAP-107); `bindKindSchema` deletion-gated → token-role-id
4. GAP-134 GRAMMAR-ONE — one executable grammar owner; `grammar_roles.zig` transitional
5. Tree-sitter / LSP / MCP / formatter from that same owner
6. Idol parser (not before GAP-145 remaining observers are gone)
7. exact resolver/graph; APPLICATION-CONSUMER-ZERO (every lowering field from graph)
8. decompose any remaining synthetic application identity; graph ontology reduction
9. world/effect/witness
10. demand producer; executed REPRESENTATION-ONE
11. direct backend crashes → 0 (`law.crash.first`); remeasure integrated evidence
12. compiler B

**P1 — FTCFTW cost collapse** (after demand + one representation owner)

10–26: representation-one, boxing, call/shape/closure specialization, region,
copy, tag/refine, pack/ABI, bounds/range, string fusion, table layout,
metamethod, fusion/SIMD, concurrency, runtime DCE, link reachability.

**P2 — compile / startup / tooling**

27–35: zero-copy tokens, dense graph, **fact-locality derived views**,
exact invalidation, parallel compiler, stage cache, object writer, LSP/MCP
same-graph, census death.

**P3 — proof**

36–44: crash 0, correctness matrix, C-equivalent suite, pinned Wasmtime,
positive damage controls, separate startup/memory/size/compile/runtime, B, C,
semantic fixed-point.

Without these workstreams the implementation can stay semantically clean and
still fail FTCFTW by realizing everything conservatively.
