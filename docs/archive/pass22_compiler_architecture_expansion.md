# Pass 22 — Compiler Architecture Expansion

Graph-native IR, universal metaprogramming, and hardware realization.

**Status:** M1 — Gate L (deferred realization) + M0 substrate (2026-08-05).  
**North star:** One canonical semantic graph; meaning stable while representation, stage, algorithm, device, and schedule remain transformable.

## Pipeline (canonical)

```
source → semantic graph → region graph → DNIR → LIR/SSA → machine IR → artifact
```

C emission remains bootstrap-only. Foreign IR is never canonical truth.

---

## §16 — Defining compiler innovation

Duo's compiler must exploit: persistent semantic identity, Lua-shaped dynamic semantics, descriptors, shapes, calls, return packs, arbitrary staging, transformations, representation freedom, foreign semantic import, direct machine ownership, hardware descriptors, provenance, persistent evidence, and self-hosting.

**Goal:** program meaning stays stable; code structure, representation, stage, algorithm, memory layout, execution device, scheduling, ABI, and machine realization remain transformable.

Conventional compilers discard semantic relationships while lowering. Duo preserves semantic identity and enriches each entity with proven knowledge, transformation history, legal implementation freedoms, selected realization, hardware constraints, measured evidence, source/foreign provenance, fallback paths, and validation state.

The compiler optimizes the full mapping:

```
meaning → algorithm → data structure → representation → stage
       → execution graph → memory topology → hardware topology → machine artifact
```

---

## §17 — One canonical semantic graph, multiple materialized views

### §17.1 Graph entity model

Every important entity is a graph node with stable semantic identity. Candidate classes: source, syntax, declaration, binding, descriptor, shape, field, function, closure, capture, call, parameter, return-pack position, value, constant, variant, effect, capability, stage, assumption, guard, law, contract, transformation, representation variable, realization candidate, memory region, execution region, hardware resource, foreign entity, generated entity, validation obligation, evidence, machine artifact.

Stable semantic graph identity and compact phase-local IR storage coexist — not every instruction is a heavyweight generic object.

**Current:** `src/semantic_graph.zig` — `NodeKind` partial coverage; `StableId` content-addressed.

### §17.2 Canonical edge algebra

One edge vocabulary; specialized views project from it. Required relationships: defines, binds, references, contains, calls, captures, receives, returns, consumes, refines, specializes, transforms, guards, assumes, invalidates, depends on, orders before, may alias, mutates, conflicts with, realizes as, represented by, executes on, stored in, imported from, generated from, validates, proves, falls back to.

**Current:** `contains`, `def`, `use`, `type_of`, `transform_*`, `provenance`. **Next:** `calls`, `realizes as`, `invalidates`.

### §17.3 Graph views

| View | Contents |
| --- | --- |
| Source | files, syntax, declarations, references, generated-source |
| Semantic | descriptors, shapes, calls, effects, laws, stages, contracts |
| Dataflow | defs, uses, return-pack flow, memory state, aliases |
| Transformation | candidates, preconditions, outcomes, rejected alternatives |
| Realization | algorithms, representations, layouts, schedules, costs |
| Hardware | processors, caches, accelerators, communication paths |
| Foreign | source-language identity, imported semantics, ABI facts |
| Evidence | assertions, proofs, tests, profiles, validation status |

### §17.4 Graph query engine

Deterministic, memoizable, dependency-tracked, incrementally invalidatable queries callable by compiler, LSP, and MCP.

Examples: `representation(value, target)`, `calls(function)`, `effects(call)`, `legal_realizations(region, target)`, `why_boxed(value)`, `dependents(descriptor)`, `invalidated_by(change)`.

**Current:** `src/graph_query.zig` — `calleesOf`, `callsIn`, `functionEmitOrder`, `stableIdOf`.

---

## §18 — Graph IR as optimization substrate

### §18.1 Region graphs

Bounded regions (function, loop, pipeline, kernel, parser, foreign module) as graphs with control, value, memory/effect deps, call nodes, stage boundaries, representation variables, hardware-placement variables, fallback edges.

**Current:** `src/region_graph.zig` from DNIR.

### §18.2 Graph-to-SSA relationship

```
semantic graph → executable region graph → selected/scheduled graph → SSA/LIR → machine IR
```

Graph IR: semantic structure, fusion, layout, foreign adaptation, hardware placement. SSA: local value flow, scalar opts, lowering.

### §18.3 Graph transformations

inline, outline, fuse, split, tile, vectorize, parallelize, pipeline, stage, residualize, specialize, clone, multiversion, reorder, buffer, layout-convert, transfer-device, eliminate, replace-algorithm, introduce-guard, insert-adapter, …

Each transformation declares: input domain, semantic preservation, required laws/knowledge, effect constraints, target requirements, cost, fallback, validation, provenance.

**Current:** callee-first emit order (Gate K). **Next:** transformation metamodel (WS27).

### §18.4 Equality infrastructure

Identity, structural, descriptor, observational, ABI, transformation-proven equivalence. Bounded equality saturation with region/node/time limits — not whole-program prerequisite.

---

## §19 — Semantic superposition and deferred commitment

### §19.1–§19.3 Superposition

Representation, algorithm, and execution superposition — multiple legal implementations until evidence requires commitment.

### §19.4 Realization variables

Unified mechanism for representation, algorithm, layout, device, scheduling, ABI, cache, specialization, vector width, precision.

**Owner:** `src/realization.zig` — `Variable`, `Candidate`, `selectDeterministic`, `selectForTarget`, `buildDeferredFromGraph`, `commitModuleForTarget`.

### §19.5 Bounded realization planning

Deterministic finite candidate comparison first; DP/partitioning/IP/profile/autotuning later. Correctness path never depends on learned models.

---

## §20 — Arbitrary staging and multi-stage IR

Stage graph: parse, bind, semantic, compile, specialize, optimize, link, load, runtime, profile, device, remote, deploy, tool, agent.

Quote-free semantic metaprogramming over descriptors, shapes, functions, graph regions, transformations, targets. Residualization at graph/LIR level — not print/reparse.

**Current:** `@comp.*` registry (`transform_engine.zig`, `meta_module.zig`), G-061 combinator dispatch.

---

## §21 — Metaprogramming over the compiler itself

Declarative compiler facts drive tokens, parser, diagnostics, targets, ABI, intrinsics, LSP, MCP, tests. Transformations as versioned semantic entities.

**Current:** Pass 16 partial; `@comp.concepts.*`, `@comp.expand`, `@comp.zip`, etc.

---

## §22 — Cross-language graph harness

Import strength levels 0–5 (textual → binary semantic). Foreign semantic capsules with language, dialect, effects, ABI, opaque regions, provenance.

**Current:** `foreign_adapter.zig` partial (Level 1–2). Layers D/E deferred.

---

## §23 — Multi-interface compiler architecture

| Interface | Status |
| --- | --- |
| Library service | partial — compile paths in `main.zig` |
| Incremental daemon | open |
| LSP | `duo-lsp` separate repo |
| MCP | duo-mcp tools partial |
| Embedded | open |
| External protocol | SIM projection |
| Native plugins | open |

---

## §24–§26 — Hardware graph and LIR

Hardware descriptor graph: ISA, extensions, cores, vector units, caches, memory spaces, GPU warps, atomics, ABI.

Capability queries: `target.cpu.vector.width`, `target.cache.line`, … via `@comp.target.*`.

Extensible LIR operation families: scalar, vector, mask, memory, atomic, control, call, trap, tensor, device, target intrinsic.

**Current:** `dnir_hardware.zig` open (WS23). `native_backend.zig` ARM64 partial.

---

## §27 — Schedule IR

Operation order, tiling, fusion, vectorization, unrolling, parallelism, device placement, prefetch, synchronization — separated from semantics.

**Status:** open (WS25).

---

## §28–§29 — Memory SSA and continuations

Memory state, effect tokens/edges, field-sensitive optimization, foreign memory provenance. Continuation IR unifying closures, coroutines, async, shell tasks, foreign callbacks.

**Status:** open.

---

## §30 — Compile-time and runtime unification

Shared graph operations; distinct realizations (interpreter, native JIT, partial eval). Compile-time native acceleration for parser tables, perfect hashes, schema derivation.

**Current:** partial — comptime fold + C bootstrap.

---

## §31–§35 — Extensibility, cost model, direct lowering, examples

Versioned semantic capabilities, extension admission rubric, opaque nodes with progressive disclosure, research sandbox.

Multidimensional cost model: latency, throughput, compile time, code size, memory, bandwidth, device transfer, energy, …

Direct graph-to-hardware for tensor graphs, FSMs, parsers, pipelines.

Conceptual capabilities (syntax provisional):

```duo
graph = @comp.graph(fn)
layout = @comp.realizations(value).layout
why = @comp.why(value)
optimized = @comp.transform(foreign.region, fuse + vectorize)
```

---

## §36 — Workstreams

Tracked in `src/pass22_catalog.zig` — **P22-WS19 … P22-WS35**.

| WS | Title | Owner | Status |
| --- | --- | --- | --- |
| P22-WS19 | Canonical graph schema | `semantic_graph.zig` | partial |
| P22-WS20 | Executable region graph | `region_graph.zig` | partial |
| P22-WS21 | Graph-to-LIR lowering | `dnir_lower.zig` + `native_backend.zig` | partial |
| P22-WS22 | Realization-variable core | `realization.zig` | **partial+** — target-aware deferred selection |
| P22-WS23 | Hardware descriptor graph | `dnir_hardware.zig` | open |
| P22-WS24 | Memory and layout planner | future | open |
| P22-WS25 | Schedule representation | future | open |
| P22-WS26 | Multi-stage residualization | `comptime.zig` | open |
| P22-WS27 | Transformation metamodel | `transform_engine.zig` | partial |
| P22-WS28 | Foreign semantic capsule | `foreign_adapter.zig` | partial |
| P22-WS29 | Boundary minimization | future | open |
| P22-WS30 | Cross-language native specialization | future | open |
| P22-WS31 | Compiler service interface | `main.zig` + duo-lsp | partial |
| P22-WS32 | Hardware-aware proof workload | `pass16_hardware_direct.duo` | partial |
| P22-WS33 | Bounded equality exploration | future | open |
| P22-WS34 | Semantic profile mapping | future | open |
| P22-WS35 | Future-extension protocol | future | open |

---

## §37 — Completion gates

| Gate | Title | Status | Proof |
| --- | --- | --- | --- |
| **J** | Graph identity through artifacts | partial | `pass22_gate.proveGateIdentity` |
| **K** | Graph-region optimization | partial | `pass22_gate.proveGateGraphTransform` |
| **L** | Deferred realization | **partial** | `pass22_gate.proveGateDeferredRealization` — ≥2 legal repr candidates until `selectForTarget` |
| **M** | Hardware graph consumption | open | — |
| **N** | Schedule selection | open | — |
| **O** | Multi-stage residualization | open | — |
| **P** | Foreign executable semantics | partial | foreign_adapter |
| **Q** | Cross-boundary optimization | open | — |
| **R** | Shared transformation | partial | transform_engine |
| **S** | Hardware multiversioning | open | — |
| **T** | Extensibility protocol | open | — |

Validate: `zig build pass22-gate`

---

## §38 — Prohibited outcomes

- Graph IR as untyped node heap; one slow universal structure
- Unrelated graphs without stable correspondence
- Semantic identity loss during SSA lowering
- Backend types as semantic truth; foreign IR as canonical IR
- Flattening foreign-language differences incorrectly
- One optimizer per hardware target; separate GPU/scheduling/metaprogramming languages
- Source generation as primary staging; interpreter-only comptime
- Premature representation commitment before call/target/escape knowledge
- Optimizing arithmetic while ignoring transfer/sync costs
- ML on correctness path; whole-program solver requirement for normal compiles
- Opaque ops without effects/validators/fallback
- Unrestricted compiler mutation; hardware directives bypassing semantic validation

---

## §39 — Governing questions

For every compiler/IR feature:

1. Preserves semantic identity?
2. Participates in the graph (not a side database)?
3. Fact, constraint, preference, candidate, or selected realization?
4. Preserves implementation freedom until evidence exists?
5. Works across native Duo and foreign semantics?
6. Stageable? Residualizable without printing source?
7. Targets CPU/SIMD/GPU/Wasm without semantic change?
8. Models memory and communication costs?
9. Exposes several legal realizations with explainable selection?
10. Usable by self-hosted compiler, Ward, LSP, MCP?
11. Incrementally invalidatable? Serializable/projectable?
12. Independently validatable with provenance to machine code?
13. Extensible for future hardware without semantic redesign?
14. Fundamentally more capable than AST → SSA → machine?

---

## Commands

```bash
zig build pass22-gate
duo catalog audit gate pass22
duo realize <file>          # realization plan + evidence
duo explain realizations <file>
```

## Related plans

- [`semantic_universe.md`](../semantic_universe.md)
- [`semantic_graph_architecture.md`](semantic_graph_architecture.md)
- [`pass16_self_hosted_compiler.md`](pass16_self_hosted_compiler.md)
- [`pass8_persistent_semantic_computing.md`](pass8_persistent_semantic_computing.md)
- [`realization.zig`](../../src/realization.zig)
