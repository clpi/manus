# Pass 2 — Foundational Convergence Audit

> **Date:** 2026-08-04  
> **Follows:** Pass 1 (unified philosophy + table-shape / graph / transform spine)  
> **Goal:** Reduce conceptual entropy — collapse independent mechanisms into one semantic system.  
> **Non-goal:** Ship many new user-facing features. This pass defines *what converges into what* and wires spine types.

**Spine implementation:** `src/semantic_algebra.zig`  
**CLI introspection:** `duo algebra` (JSON catalog)  
**Pass 1 reference:** architecture convergence started in `docs/semantic_universe.md`, `docs/plans/semantic_graph_architecture.md`

---

## The question Pass 2 asks

Instead of *“what features are missing?”* ask:

> **What independent mechanisms can become manifestations of the same underlying semantic system?**

Pass 1 mostly converged the *philosophy*. Pass 2 converges the *mechanisms*.

The best language designs reduce **conceptual entropy**: instead of asking "what features are
missing?", ask "what independent mechanisms can become manifestations of the same underlying
semantic system?" Those collapses are what make a language feel *inevitable* twenty years later.

### Design principle

| Pass 1 | Pass 2 |
| --- | --- |
| Unified philosophy (graph, transforms, staging vision) | Unified mechanisms (algebras, not feature lists) |
| `@comp.*` registry + provenance stub | Every pass becomes a graph transform |
| Storage classes + shape facts | Knowledge lattice + shape/call/descriptor algebra |
| "What can we add?" | "What can we collapse?" |

---

## Architectural wins (ranked leverage)

If you had to rank the highest-leverage convergences beyond Pass 1:

1. **Knowledge Lattice** — one abstraction for "how much the compiler knows" about any value
2. **Descriptor Algebra** — composition/intersection/subtraction instead of extends/implements/derive/mixins
3. **Shape Algebra** — universal structural representation (not just storage optimization)
4. **Call Algebra** — calls as first-class semantic objects driving specialization
5. **Transformation Registry** — one framework for every optimization, lowering, rewrite
6. **Stage Polymorphism** — arbitrary execution stages replace compile-time/runtime dichotomy
7. **Pipeline Graph IR** — fluent pipelines as optimization graphs, not chained calls
8. **Effect Algebra** — capabilities as composable descriptor values, not scattered annotations

Secondary (same spine): Hardware Algebra, Return Packs, Pattern Recognition, Reflection-as-query,
Grammar Compression, Semantic Cost Model.

---

## Ranked convergence targets (authoritative priority)

| Rank | Algebra | Replaces (eventually) | Spine status |
| --- | --- | --- | --- |
| 1 | **Knowledge Lattice** | scattered “known type/value/shape/target/stage” | `KnowledgeLevel` + `fromStorageClass()` |
| 2 | **Descriptor Algebra** | types, concepts, derive, protocols, extends, mixins | `DescriptorExpr` + `DescriptorOp` (planned) |
| 3 | **Shape Algebra** | storage classes, sealed records, schemas, AST shapes | `ShapeOp` + graph `table_shape` nodes |
| 4 | **Call Algebra** | inlining, mono, dispatch, memo, GPU/SIMD entry | `CallSite` (planned) |
| 5 | **Transformation Registry** | optimizer passes, folds, meta hooks, specializers | `transform_engine.zig` (partial) |
| 6 | **Stage Polymorphism** | comptime vs runtime vs link vs deploy | `Stage` enum (planned) |
| 7 | **Pipeline Graph IR** | `\|>` chains, std.pipeline | `PipelineNode` (planned) |
| 8 | **Effect Algebra** | `@pure`, capabilities, side-effect passes | `EffectSet` (planned) |

Secondary (same spine, lower urgency): Hardware Algebra, Return Packs, Pattern Recognition, Reflection-as-query, Grammar Compression, Semantic Cost Model.

---

## 1. Descriptor Algebra

### Today (fragmented)

| Mechanism | Location |
| --- | --- |
| Types / records | `src/types.zig`, sema |
| Concepts | `src/sema.zig` concepts map |
| Derive | `derive_eval.zig`, `@comp.derive.*` |
| Enums | `ast.EnumDef`, codegen tagged struct |
| Modules | file-as-`M`, `req()` |
| Schemas | `@comp.schema` (partial) |
| Capabilities | planned A4 |
| Directives | `@comp.*` → meta_module |

### Target (one mechanism)

Descriptors are **values**, not separate language features.

```
Named      = @{ name: str }
Positioned = @{ x: f64, y: f64 }
Sprite     = Named + Positioned + Colored   -- DescriptorOp.add
```

No separate `extends` / `implements` / `derive` / mixin keywords — only **descriptor algebra**:

- `add` — merge fields/constraints
- `sub` — remove capabilities or fields
- `intersect` — shared constraints
- `restrict` — narrow (e.g. sealed subset)
- `transform` — compile-time rewrite of descriptor graph

### Convergence path

1. Lift concept/alias/enum/module nodes to `DescriptorKind` in semantic graph  
2. Represent `@comp.derive` as `DescriptorOp.transform` on graph  
3. Surface `@{}` literals as descriptor values (syntax unchanged from Pass 1 plan)  
4. Deprecate parallel inheritance paths once algebra covers 3-site parity tests

---

## 2. Stage Polymorphism

### Today

- `comptime.zig`, `@()`, `@comp.compile.*` — compile-time  
- `build_framework.zig` — link/deploy stages  
- Codegen — runtime  
- `ml_kernels` / `@comp.device` — GPU (ad hoc)

### Target

Everything evaluates in a **stage**. Functions may exist at multiple stages; specialization picks the stage + knowledge lattice point.

```
@(stage.compile)  @(stage.link)  @(stage.runtime)  @(stage.deploy)  @(stage.gpu)
```

`Stage` in `semantic_algebra.zig` is the shared enum. Pass 2 adds metadata hooks; Pass 3 routes `@()` through stage + budget.

---

## 3. Shape Algebra

### Today (Pass 1 partial)

- `StorageClass`: dynamic → guarded → sealed → native  
- `@comp.type.shape`, `@comp.why`, `@comp.origin`  
- `semantic_graph` `table_shape` / `enum_shape` nodes with `shape_id`

### Target

Shapes describe **semantic structure**, not just storage:

| Op | Meaning | Pass 1 anchor |
| --- | --- | --- |
| `seal` | fixed layout | `@sealed`, `.sealed` |
| `open` | allow extension | dynamic tables |
| `merge` | combine records | alias + inline record |
| `project` | field subset | future `{ .x }` projections |
| `freeze` | no further mutation | knowledge → `.frozen` |
| `specialize` | mono instance | `mono.zig` |
| `lift` | AST → graph node | `semantic_graph.lift*` |
| `lower` | graph → C/GPU | `codegen.zig` |

**Unified domain:** descriptors, modules, tables, configs, schemas, records, AST nodes, comptime values.

---

## 4. Call Algebra

### Today

Calls are codegen events: `emit_call`, `lua_invoke`, mono specialization, inline hints.

### Target

Every call is a **semantic object**:

```
callee, receiver, arguments, shape, effects, stage, hardware,
expected returns, consumption, context
```

`CallSite` in spine. Optimizations become graph transforms:

| Legacy pass | Call transform |
| --- | --- |
| Inlining | rewrite CallSite.callee → body |
| Specialization | attach mono shape to CallSite |
| Memoization | cache key = CallSite hash + knowledge |
| Partial eval | stage=compile + knowledge≥comptime |
| GPU/SIMD | hardware facet + lower transform |

---

## 5. Return Packs

Lua multi-return is underused. Target: **ReturnPack** IR with consumption modes:

- `bound` — `a, b = f()`
- `projected` — `f().x`
- `spread` — `f()...`
- `piped` — `f() :map(...)`

Compiler representation only — no runtime allocation. Connects to Call Algebra via `CallSite.return_arity` and `ReturnPack.consumption`.

---

## 6. Effect Algebra

### Today

`@pure`, `@noalloc`, ARC pass, planned capabilities.

### Target

Effects are **descriptor values** (`EffectSet`):

```
Network + Filesystem
Filesystem - Write
Unsafe + SIMD
```

Compose with same ops as descriptors. Violations = lattice meet below required effect bound.

---

## 7. Hardware Algebra

### Today

`@simd`, `@gpu`, `@comp.device`, `ml_kernels`, `native_backend`.

### Target

Hardware facets as semantic values; queries like `cpu.simd.width`, `gpu.shared`, `cache.line` resolve during **specialization** (Call + Shape transforms), not as separate intrinsics.

---

## 8. Pipeline Graph IR

### Today

`|>` desugars to nested calls; `pipeline_gen.zig` emits stages.

### Target

Pipeline = **IR graph** (`PipelineNode`). Same syntax lowers to:

- scalar loop  
- SIMD  
- GPU kernel  
- coroutine  
- comptime unrolled  
- distributed (future)

One graph, many lowerings — chosen by cost vector + hardware + stage.

---

## 9. Pattern Recognition

Avoid proliferating `match` / `switch` keywords where **descriptor dispatch** suffices:

```lua
handlers[color]   -- table indexed by enum/discriminant
```

Compiler recognizes shape → perfect hash / jump table / direct call. No new syntax; Pattern Recognition is a **transform** on CallSite + descriptor layout.

---

## 10. Everything becomes a Transformation

Pass 1 started this with `transform_engine.zig`. Pass 2 completes the model:

```
Input graph → Transform → Output graph
              ↓
         Contract, Budget, Provenance, Validation
```

Legacy surfaces map as:

| Legacy | Transform id |
| --- | --- |
| Constant folder | `fold.constant` |
| Inliner | `call.inline` |
| `comptimeMetaHook` | `comp.*` registry entries |
| GPU lowering | `lower.gpu` |
| Shape seal | `shape.seal` |

Enables equality saturation (Tier B6) without new concepts.

---

## 11. Reflection disappears

No separate reflection API. **Query descriptors:**

```
Point.fields   Point.methods   Point.shape   Point.stage   Point.effects
```

Pass 1 precursors: `@comp.type.shape`, `@comp.why`, `@comp.origin`, `duo graph`.

---

## 12. Grammar Compression (future, optional)

Documented opportunities — **not Pass 2 scope**:

| Idea | Risk |
| --- | --- |
| `{}` as descriptor when context requires | ambiguity with tables |
| `.foo.bar` projection chains | parser complexity |
| Newline field construction `Point{ x\n y }` | whitespace semantics |
| Indentation-only expression bodies | high ambiguity cost |

Audit only; implement only when knowledge lattice can disambiguate.

---

## 13. Knowledge Lattice (highest leverage)

Single axis for compiler reasoning:

```
Unknown → Observed → Guarded → Stable → Frozen → Comptime → Native
```

**Pass 1 bridge:** `KnowledgeLevel.fromStorageClass()`.

Every pass asks one question: *can I move this value up the lattice?*

| Legacy check | Lattice form |
| --- | --- |
| `native_scalar_mode` | knowledge ≥ native at call boundary |
| comptime fold | knowledge ≥ comptime |
| `@sealed` | knowledge ≥ stable |
| type annotation | knowledge ≥ observed |

---

## 14. Semantic Cost Model

`CostVector` — multidimensional tradeoffs:

latency, throughput, compile_time, binary_size, memory, bandwidth, power, determinism, code_size, agent_complexity, source_complexity.

Transforms declare cost deltas; optimizer picks Pareto-optimal rewrites under budget (ties to `transform_engine.BudgetClass`).

---

## Mechanism collapse map (quick reference)

```
types ────────────────┐
concepts ─────────────┤
derive ───────────────┼──► DescriptorExpr
protocols ────────────┤
enums/modules ────────┘

StorageClass ─────────┐
@sealed ──────────────┼──► ShapeOp + KnowledgeLevel
graph table_shape ──┘

inline/mono/GPU ──────┐
dispatch ─────────────┼──► CallSite transforms
lua_invoke ───────────┘

comptime/runtime ─────┼──► Stage

@pure/capabilities ───┼──► EffectSet

optimizer/folds ──────┼──► transform_engine (graph→graph)

reflection/LSP ───────┼──► descriptor queries (no API)
```

---

## What Pass 2 shipped (code)

| Deliverable | File |
| --- | --- |
| Algebra spine types | `src/semantic_algebra.zig` |
| Knowledge ↔ type bridge | `knowledgeOfType`, `lowersToNativeC`, `Symbol.knowledge` |
| Call ↔ shape bridge | `callSiteFromShape`, graph call `knowledge`/`stage` |
| Call transform ids | `call.inline` … `call.simd_lower` in `transform_engine.zig` |
| Codegen lattice helpers | `moduleUsesFullNativeLowering`, `moduleNeedsLuaRuntime`, `funcUsesNativeLowering` |
| Descriptor lift edges | `shape.lift` `transform_app` on alias shapes |
| Convergence catalog JSON | `duo algebra` |
| Unit tests (lattice, effects, shapes, cost, calls) | `semantic_algebra.zig` / `transform_engine.zig` tests |
| Transform metadata hooks | `transform_engine.zig` (`KnowledgeLevel`, `CostVector` on descriptors) |
| Graph metadata hooks | `semantic_graph.zig` (`knowledge`, `stage` on nodes) |
| This audit | `docs/plans/pass2_foundational_convergence.md` |

---

## Pass 2.1 progress (2026-08-04)

| Slice | Status | Notes |
| --- | --- | --- |
| Wire knowledge into sema | ✅ partial | `knowledgeOfType`, `Symbol.knowledge`, `module_bindings` snapshot |
| ShapeOp as transforms | ✅ partial | All 10 `shape.*` ids registered; `shape.lift` on alias graph lift |
| CallSite on graph lift | ✅ partial | `callSiteFromShape`; `call.*` registry; `attachCallTransforms` on lift |
| EffectSet on CallSite | ✅ partial | `effectSetFromAttributes`; codegen `func_decls` + `callSiteForShape` |
| Codegen call transforms | ✅ partial | `tryEmitCallTransformDispatch` (specialize); provenance for remaining |
| Pipeline codegen | ✅ partial | `try_emit_native_pipeline` — typed `|>` → direct C call |
| DescriptorExpr for aliases | ✅ partial | Alias + `@derive` → `DescriptorOp.transform` (`Type~Display~Eq`) |
| PipelineNode lift | ✅ partial | `|>` → `.pipeline` nodes + `pipeline.map` transform_app |
| Codegen lattice migration | ✅ partial | `moduleUsesFullNativeLowering` / `moduleNeedsLuaRuntime` replace `native_scalar_mode` checks |
| G-061 parity | ✅ done | `src/meta_transform_tests.zig` — registry + 8/8 tier-1 3-site compile parity |

---

## Pass 2.4 progress (2026-08-04)

| Slice | Status | Notes |
| --- | --- | --- |
| Call rewrite dispatch | ✅ partial | specialize + inline + simd/gpu + memo via `tryEmitCallTransformDispatch` |
| Call provenance skip | ✅ done | `noteCallTransformProvenance(..., skip)` avoids duplicate logs on dispatch |
| Native pipeline lowering | ✅ done | `try_emit_native_pipeline` — typed `\|>` → direct C call + `pipeline.map` provenance |
| Hardware algebra on graph | ✅ partial | `HardwareSet` + `hardwareLoweringsFromAttributes`; pipeline nodes carry lowering bits |
| Provenance introspection | ✅ done | `provenanceSitesObserved`, `tier1ParityObserved`, `paritySitesFor` |
| End-to-end provenance harness | ✅ done | `meta_transform_tests` compile + `tier1ParityObserved` for all tier-1 cases |
| Provenance allocator fix | ✅ done | Log uses `page_allocator` — survives compile arena teardown |
| G-061 compile parity | ✅ 8/8 | `comp.fixpoint` TOP literal extraction now passes 3-site parity |

**Still open:** fused pipeline graph→C backend; full lattice migration off `native_scalar_mode`; `call.gpu_lower` GPU kernel backend; runtime memo cache.

---

## Pass 2.5 progress (2026-08-04)

| Slice | Status | Notes |
| --- | --- | --- |
| CallSite hardware facts | ✅ done | `callSiteFromShapeWithCalleeFacts`; codegen + graph from callee `@hot`/`@simd`/`@device` |
| `call.inline` dispatch | ✅ done | `tryEmitDirectNamedCall` / `emitDirectNamedFuncCall` before `lua_invoke` |
| `call.simd_lower` dispatch | ✅ done | `@hot`/`@simd` callees → native direct call + provenance |
| `call.gpu_lower` dispatch | ✅ partial | Same native path + provenance (`@comp.device` sets GPU bit; kernel backend open) |
| `call.memo` dispatch | ✅ partial | Comptime fold when knowledge ≥ at_comptime + pure |
| Call transform tests | ✅ done | `meta_transform_tests` — inline, simd_lower, provenance |

---

## Next implementation slices (Pass 2.6+)

Do **not** skip order:

1. **Pipeline fused lowering** — graph `PipelineNode` → fused C backend (beyond single-step native `\|>`).  
2. **Call devirtualize dispatch** — method/table dispatch through transform engine.  
3. **Codegen lattice migration** — finish routing `native_scalar_mode` through `lowersToNativeC` / `knowledgeAtLeastType`.  
4. **DescriptorExpr composition** — internal `+` for alias merging; full `@comp.derive` as `DescriptorOp.transform`.  
5. **EffectSet completeness** — capability annotations beyond `@pure` / `@noalloc`.  
6. **Stage polymorphism wiring** — expose `Stage` on graph nodes in sema/codegen paths.  

**Completed in Pass 2.1–2.5:** CallSite transforms registered + dispatched; G-061 8/8 compile parity; pipeline native codegen; provenance harness; hardware on CallSite.

---

## Agent commands

```bash
duo algebra                              # convergence catalog JSON
duo graph examples/table_shape_smoke.duo # shape facts (Pass 1)
DUO_PROVENANCE=1 duo compile …             # transform provenance
zig test src/semantic_algebra.zig          # algebra unit tests
```

**Moratorium unchanged:** new `@comp.*` requires transform registration + 3-site parity + native contract.
