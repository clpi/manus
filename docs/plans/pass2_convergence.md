# Pass 2 — Foundational Convergence Audit

> **Date:** 2026-08-04
> **Follows:** Pass 1 (unified philosophy + table-shape / graph / transform spine)
> **Principle:** Reduce conceptual entropy — collapse independent mechanisms into shared algebras.
> **Non-goal:** Add features. This pass finds where 2–3 future features collapse into one mechanism.

**Spine implementation:** `src/semantic_algebra.zig`
**CLI introspection:** `duo algebra` (JSON catalog)
**Pass 1 reference:** `docs/semantic_universe.md`, `docs/plans/semantic_graph_architecture.md`
**Prior sketch:** `docs/plans/pass2_foundational_convergence.md` (initial targets + spine types)

---

## The Core Insight

The best language designs reduce conceptual entropy.

Instead of asking "what features are missing?" ask:

> **What independent mechanisms can become manifestations of the same underlying semantic system?**

Five separate features give you five things. One algebra with five operations gives you 5^n things.

Pass 1 converged the philosophy. Pass 2 converges the mechanisms.

---

## Dependency Graph

These algebras are not independent. They form a DAG:

```
                    ┌─────────────────┐
                    │ Knowledge Lattice│  ← Tier 0 (everything queries this)
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌──────────────┐
     │ Descriptor │  │   Shape    │  │Transformation│  ← Tier 1 (structural)
     │  Algebra   │  │  Algebra   │  │   Registry   │
     └─────┬──────┘  └─────┬──────┘  └──────┬───────┘
           │                │                │
           ├────────────────┼────────────────┤
           ▼                ▼                ▼
     ┌──────────┐    ┌──────────┐    ┌──────────────┐
     │  Stage   │    │   Call   │    │   Pipeline   │  ← Tier 2 (execution)
     │Polymorph │    │  Algebra │    │   Graph IR   │
     └────┬─────┘    └────┬─────┘    └──────┬───────┘
          │                │                 │
          ├────────────────┼─────────────────┤
          ▼                ▼                 ▼
     ┌──────────┐    ┌──────────┐    ┌──────────────┐
     │  Effect  │    │ Hardware │    │  Cost Model  │  ← Tier 3 (domains)
     │  Algebra │    │  Algebra │    │  (semantic)  │
     └──────────┘    └──────────┘    └──────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │ Emergent (fall out for free): │  ← Tier 4
              │ Return Packs, Pattern Recog, │
              │ Reflection disappears,       │
              │ Grammar Compression          │
              └──────────────────────────────┘
```

Items in Tier 4 are NOT separate features. They are **consequences** of getting Tiers 0–3 right. That's how you know the architecture is converging.

---

## Tier 0 — Knowledge Lattice

**The single highest-leverage abstraction.** A unified model for "how much the compiler knows" about any value.

### The Problem

Today we have scattered, disconnected checks:

- `native_scalar_mode` — "do we know the type?"
- comptime fold — "do we know the value?"
- `@sealed` — "do we know the shape won't change?"
- type annotations — "did the user tell us something?"
- `StorageClass` — "dynamic vs guarded vs sealed vs native"

These are all asking the same question at different granularities.

### The Solution

One monotonic lattice. Information only increases:

```
Unknown → Observed → Guarded → Stable → Frozen → Comptime → Native
```

Every optimization asks ONE question: **"Where is this value in the knowledge lattice?"**

| Level | What the compiler knows | Enables |
| --- | --- | --- |
| `Unknown` | Nothing | Dynamic dispatch only |
| `Observed` | Has been used; type inferred | Basic type checking |
| `Guarded` | Narrowed by a runtime check | Branch elimination |
| `Stable` | Won't change within scope | Hoisting, CSE |
| `Frozen` | Immutable after construction | Cache, share, dedup |
| `Comptime` | Value fully known at compile time | Constant folding, specialization |
| `Native` | Lowered to bare C scalar/struct | Zero-overhead emission |

### Unification

| Legacy check | Lattice equivalent |
| --- | --- |
| `native_scalar_mode` | knowledge ≥ `native` at call boundary |
| comptime fold | knowledge ≥ `comptime` |
| `@sealed` | knowledge ≥ `stable` |
| type annotation | knowledge ≥ `observed` |
| `StorageClass.dynamic` | knowledge = `unknown` |
| branch narrowing | `unknown` → `guarded` |

### Implementation anchor

`KnowledgeLevel` enum + `fromStorageClass()` in `src/semantic_algebra.zig`.

---

## Tier 1a — Descriptor Algebra

**The biggest remaining opportunity.** Descriptors can become *everything*.

### The Problem (fragmented)

Today we have 8 separate mechanisms:

| Mechanism | Keywords/syntax | Location |
| --- | --- | --- |
| Types / records | `type`, struct literals | `src/types.zig` |
| Concepts | `concept HasXY` | `src/sema.zig` |
| Derive | `@comp.derive.*` | `derive_eval.zig` |
| Enums | `enum Color` | `ast.EnumDef` |
| Modules | file-as-M, `req()` | codegen |
| Schemas | `@comp.schema` | meta hooks |
| Capabilities | planned | — |
| Directives | `@comp.*` | meta_module |

Each has its own composition rules (or none). Users must learn 8 mental models.

### The Solution

All of these are **descriptor values**. There is one mechanism: **descriptor algebra**.

```duo
Named = @{
    name: str
}

Positioned = @{
    x: f64
    y: f64
}

Colored = @{
    color: Color
}

-- Composition via algebra, not keywords
Sprite = Named + Positioned + Colored
```

### Operations

| Op | Symbol | Meaning | Replaces |
| --- | --- | --- | --- |
| Addition | `+` | Merge fields/constraints | `extends`, `implements`, mixins |
| Subtraction | `-` | Remove fields/capabilities | capability restriction |
| Intersection | `∩` / `&` | Shared constraints only | — |
| Restriction | `\|` | Narrow to subset | sealed subset |
| Transformation | `>>` | Compile-time rewrite | `derive`, macros |

### What it subsumes

Instead of inventing five keywords:

```
-- NOT THIS (five mechanisms):
extends Base
implements Protocol
derive(Eq, Hash)
mixin Serializable
use Module

-- THIS (one mechanism):
Entity = Base + Protocol + Eq + Hash + Serializable + Module.exports
```

### Convergence path

1. Lift concept/alias/enum/module nodes to `DescriptorKind` in semantic graph
2. Represent `@comp.derive` as `DescriptorOp.transform` on graph
3. Surface `@{}` literals as descriptor values
4. Deprecate parallel inheritance paths once algebra covers 3-site parity

---

## Tier 1b — Shape Algebra

**Make shapes the universal structural representation, not just a storage optimization.**

### The Problem

Today shapes mostly represent storage (`StorageClass`). But modules, tables, configs, schemas, records, AST nodes, and compile-time values ALL have structural shape.

### The Solution

One set of operations that applies everywhere:

| Op | Meaning | Example |
| --- | --- | --- |
| `seal()` | Fix layout permanently | `@sealed` on a record |
| `open()` | Allow extension | dynamic table |
| `merge()` | Combine two shapes | record + inline fields |
| `subtract()` | Remove fields | `User - { password }` |
| `project()` | Select field subset | `{ .x, .y }` from Point3D |
| `rename()` | Rename fields | `{ x → lat, y → lon }` |
| `freeze()` | No further mutation | const binding |
| `specialize()` | Monomorphize | `Vec[f32]` from `Vec[T]` |
| `lift()` | AST → graph node | `semantic_graph.lift*` |
| `lower()` | Graph → C/GPU code | `codegen.zig` emit |

### Unified domain

These operations apply uniformly to:

- Descriptors
- Modules
- Tables
- Configs
- Schemas
- Records
- AST nodes
- Compile-time values

One set of operations, not N specialized APIs.

### Implementation anchor

`ShapeOp` enum in `src/semantic_algebra.zig`; graph `table_shape` nodes from Pass 1.


---

## Tier 1c — Transformation Registry

**Every optimization, lowering, rewrite, and specialization uses one framework.**

### The Problem

Today we have:

- `fold_meta_string_expr` — ad-hoc string folding
- `maybe_emit_meta_string_call` — duplicate ad-hoc folding
- `comptimeMetaHook` — third fold path
- Derive system — separate mechanism
- Sema passes — in-place mutation
- Optimizer hints — scattered annotations

Six different systems for "take some input, produce some output."

### The Solution

Everything is:

```
Input graph → Transform → Output graph
                 │
           ┌─────┼─────┐
           ▼     ▼     ▼
      Contract Budget Provenance
           │     │     │
           └─────┼─────┘
                 ▼
            Validation
```

### What it enables

| Legacy pass | Transform identity |
| --- | --- |
| Constant folder | `fold.constant` |
| Inliner | `call.inline` |
| `comptimeMetaHook` | `comp.*` registry entries |
| GPU lowering | `lower.gpu` |
| Shape seal | `shape.seal` |
| SIMD vectorize | `lower.simd` |

This is exactly what allows **equality saturation** later (Tier B6) — multiple equivalent rewrites coexist, cost model picks the best.

### Implementation anchor

`src/transform_engine.zig` (partial); contracts, budgets, provenance stubs.

---

## Tier 2a — Stage Polymorphism

**Replace the compile-time/runtime dichotomy with arbitrary execution stages.**

### The Problem

Currently we have a binary:

- Compile-time (`@()`, `comptime.zig`)
- Runtime (everything else)

With ad-hoc carve-outs for link-time (`-flto`), deploy-time (build scripts), and GPU.

### The Solution

Everything evaluates in a **stage**. A function can exist at arbitrary stages:

```duo
@(stage.compile)   -- fold at compile time
@(stage.link)      -- resolve at link time (PGO, LTO decisions)
@(stage.runtime)   -- normal execution
@(stage.deploy)    -- build/package/deploy scripts
@(stage.gpu)       -- GPU kernel launch
```

Every function can exist at multiple stages. The compiler specializes to whichever stage the inputs are known at (determined by the Knowledge Lattice).

### Why this is more powerful than comptime

`comptime` is one point on the lattice. Stages give you a **continuum**:

- A function whose inputs are known at compile time → runs at `stage.compile`
- Same function whose inputs are known at link time → runs at `stage.link`
- Same function whose inputs are runtime-only → runs at `stage.runtime`
- Same function targeting GPU memory → runs at `stage.gpu`

No separate keywords. No special `#run` or `comptime` annotations. The **same function** participates in whatever stage its inputs allow.

### Implementation anchor

`Stage` enum in `src/semantic_algebra.zig`; connects to Knowledge Lattice (stage = highest stage where inputs are ≥ that level).

---

## Tier 2b — Call Algebra

**Elevate calls to first-class semantic objects that drive ALL specialization.**

### The Problem

Call specialization currently focuses on signatures. But a call carries far more semantic information.

### The Solution

Every call becomes a semantic object:

```
CallSite {
    callee       -- what's being called
    receiver     -- self/this if method
    arguments    -- with shapes + knowledge levels
    shape        -- structural return shape
    effects      -- what side effects occur
    stage        -- which stage executes
    hardware     -- what target (cpu/gpu/simd)
    returns      -- expected return arity + types
    consumption  -- how results are used downstream
    context      -- enclosing scope knowledge
}
```

Then **every optimization** becomes a transformation on CallSite objects:

| Optimization | CallSite transform |
| --- | --- |
| Inlining | replace callee with body subgraph |
| Specialization | attach monomorphic shape |
| Memoization | cache key = callsite hash + knowledge |
| Partial evaluation | stage=compile + knowledge≥comptime → fold |
| GPU lowering | hardware=gpu + shape analysis → kernel |
| SIMD lowering | hardware=cpu.simd + width→vectorize |

No separate inliner, specializer, memoizer, GPU compiler. One framework.

### Implementation anchor

`CallSite` struct (planned) in `src/semantic_algebra.zig`.

---

## Tier 2c — Pipeline Graph IR

**Treat fluent pipelines as an optimization graph, not syntax sugar.**

### The Problem

Current `|>` desugars to nested function calls. `std.pipeline` emits code templates. The compiler sees individual calls, not the pipeline as a whole.

### The Solution

Formalize pipelines as an **IR graph**:

```duo
users
    :filter(active)
    :map(name)
    :sort()
    :take(10)
```

This is NOT syntax sugar for `take(sort(map(filter(users, active), name)), 10)`.

It is a **pipeline graph node** that the compiler can lower into:

- Fused scalar loops (default)
- SIMD vectorized passes
- GPU kernel (data-parallel map/filter)
- Coroutine/streaming (lazy evaluation)
- Compile-time unrolled (if input is comptime)
- Distributed execution (future: split across workers)

**Without changing syntax.** The same source lowers differently based on stage, hardware, shape, and cost model.

### Implementation anchor

`PipelineNode` (planned) in `src/semantic_algebra.zig`.


---

## Tier 3a — Effect Algebra

**Represent capabilities and side effects as composable descriptor values.**

### The Problem

Current proposal has scattered annotations:

```duo
@pure
@noalloc
@constant.time
```

These are booleans. You can't compose them, intersect them, or subtract them.

### The Solution

Effects become **descriptors** with the same algebra:

```duo
-- Effects are values
Network = @effect{ net.connect, net.send, net.recv }
Filesystem = @effect{ fs.read, fs.write, fs.delete }
GPU = @effect{ gpu.alloc, gpu.launch, gpu.sync }
Unsafe = @effect{ ptr.deref, ptr.cast, mem.raw }

-- Algebra applies
WebServer = Network + Filesystem
ReadOnly = Filesystem - fs.write - fs.delete
SafeGPU = GPU - ptr.deref
```

Effect bounds on functions:

```duo
serve(req: Request): Response [Network + Filesystem] = ...
query(db: DB): Rows [Network - net.send] = ...  -- read-only network
```

Violations are **lattice meets below the required effect bound** — same mechanism as Knowledge Lattice, applied to capabilities.

### Implementation anchor

`EffectSet` (planned) in `src/semantic_algebra.zig`; connects to capability system (Priority A4).

---

## Tier 3b — Hardware Algebra

**Hardware targets become semantic values, not special annotations.**

### The Problem

Today:

```duo
@gpu
@simd
@comp.device(.auto)
```

Ad-hoc annotations that trigger special codegen paths.

### The Solution

Hardware is a semantic value with queryable properties:

```duo
cpu.simd.width     -- 128, 256, 512 depending on target
gpu.shared         -- shared memory size
cache.line         -- cache line bytes
target.vector      -- max vector register width
```

Optimization becomes ordinary specialization:

```duo
-- Same function, different hardware facets
dot(a: Vec, b: Vec): f64 =
    if target.vector >= 256
        dot_avx(a, b)       -- stage.compile selects
    else if hardware.has(.gpu)
        dot_gpu(a, b)
    else
        dot_scalar(a, b)
```

The hardware algebra composes with Call Algebra — a CallSite's `hardware` facet determines which lowering transform applies.

---

## Tier 3c — Semantic Cost Model

**Replace ad-hoc optimization heuristics with a single multidimensional cost framework.**

### The Problem

Optimization decisions today are qualitative ("prefer native", "fold if possible"). There's no framework for tradeoffs.

### The Solution

Every transformation optimizes against a **cost vector**:

```
CostVector {
    latency           -- execution time
    throughput        -- ops/second
    compile_time      -- build speed impact
    binary_size       -- output bytes
    memory            -- runtime allocation
    bandwidth         -- memory bus pressure
    power             -- energy consumption
    determinism       -- timing predictability
    code_size         -- source complexity
    agent_complexity  -- tool comprehension cost
    source_complexity -- human comprehension cost
}
```

Transforms declare cost deltas. The optimizer picks Pareto-optimal rewrites under the active budget:

```duo
@comp.compile.objective("latency")                    -- single objective
@comp.compile.objectives("latency", "binary_size")    -- Pareto frontier
```

### Implementation anchor

`CostVector` struct in `src/semantic_algebra.zig`; ties to `transform_engine.BudgetClass`.

---

## Tier 4 — Emergent Consequences

These are NOT features to implement. They **fall out for free** from Tiers 0–3.

### Return Packs

Lua multi-return + Call Algebra + Shape Algebra = return packs are just "calls whose shape has arity > 1":

```duo
a, b = parse()        -- CallSite.returns.arity = 2
parse().x             -- CallSite.returns projected by ShapeOp.project
parse()...            -- CallSite.returns spread (consumption = spread)
parse():map(...)      -- Pipeline on CallSite.returns
```

No new runtime allocation. Pure compiler representation via existing algebras.

### Pattern Recognition

Descriptor dispatch + Call Algebra + Shape Algebra = pattern recognition is a **transform**:

```duo
handlers[color]  -- table indexed by descriptor
```

The compiler recognizes the shape (enum-keyed table of functions) and applies `call.dispatch_optimize`:

- Jump table (if enum is dense)
- Perfect hash (if sparse)
- Direct call (if color is comptime-known)
- Switch (general fallback)

No `match`/`switch` keyword needed. The transform fires on recognized shapes.

### Reflection Disappears

Descriptor algebra + Shape algebra = reflection is just **querying descriptors**:

```duo
Point.fields        -- descriptor query: field list
Point.methods       -- descriptor query: method list
Point.shape         -- shape algebra: current storage class
Point.stage         -- stage: where is it evaluated?
Point.effects       -- effect set: what does it do?
```

No separate reflection API. No `std.reflect`. Just semantic objects responding to dot access.

### Grammar Compression

Knowledge Lattice enables context-dependent parsing:

- `{}` becomes a descriptor literal when the context requires a descriptor (Knowledge Lattice says "expecting descriptor here")
- `.foo.bar` becomes a projection chain when context is a shape operation
- Newline-separated fields work when parser knows it's inside a descriptor

Not Pass 2 scope — but the *mechanism that enables it* (Knowledge Lattice context) is Pass 2.

---

## Mechanism Collapse Map (quick reference)

```
types ────────────────┐
concepts ─────────────┤
derive ───────────────┼──► Descriptor Algebra (one mechanism)
protocols ────────────┤
enums / modules ──────┘

StorageClass ─────────┐
@sealed ──────────────┼──► Shape Algebra + Knowledge Lattice
graph table_shape ────┘

inline / mono / GPU ──┐
dispatch ─────────────┼──► Call Algebra (transforms on CallSite)
lua_invoke ───────────┘

comptime / runtime ───┼──► Stage Polymorphism

@pure / capabilities ─┼──► Effect Algebra (descriptors for effects)

optimizer / folds ────┼──► Transformation Registry (graph → graph)

reflection / LSP ─────┼──► Descriptor queries (no separate API)

@gpu / @simd / target ┼──► Hardware Algebra (semantic values)

heuristic decisions ──┼──► Semantic Cost Model (CostVector)
```

**Before Pass 2:** ~15 independent mechanisms with ad-hoc interactions.
**After Pass 2:** 8 orthogonal algebras sharing one lattice.
**Combinatorial result:** 8 algebras × 5 operations each = 40 operations that compose into thousands of behaviors.

---

## Implementation Priority (do not skip order)

### Phase 2.0 (immediate — wire what exists)

1. Attach `KnowledgeLevel` to typed bindings in sema — one helper replaces scattered native checks
2. Register `shape.seal`, `shape.lift` in `transform_engine`
3. Add `CallSite` as a graph node kind on lift

### Phase 2.1 (descriptor foundation)

4. `DescriptorExpr` for aliases — `Point = { x, y }` as descriptor atom
5. `+` for descriptor composition (internal representation; syntax later)
6. Concepts as descriptor constraints (same representation)

### Phase 2.2 (stage + effects)

7. `Stage` routing through partial evaluator
8. `EffectSet` on function signatures (annotation → lattice check)
9. Hardware queries as comptime descriptors

### Phase 2.3 (call + pipeline)

10. `CallSite` semantic object with effect/stage/hardware facets
11. `PipelineNode` IR with multiple lowering backends
12. Pattern recognition as a registered transform

### Phase 2.4 (cost model + integration)

13. `CostVector` on transforms; Pareto selection in optimizer
14. 3-site parity for all tier-1 `@comp.*` through transform engine
15. Equality saturation prototype (Tier B6 gate)

---

## Moratorium (unchanged from Pass 1)

Before merging any new `@comp.*` combinator:

1. **Register** in `src/transform_engine.zig` (descriptor + budget + contract)
2. **Parity test** — same behavior at top-level, nested callback, block body
3. **One dispatch path** — route through transform engine
4. **Native contract** — no `lua_Value` on typed paths
5. **Bench** if codegen touched

---

## Agent Commands

```bash
duo algebra                                # convergence catalog JSON
duo graph examples/table_shape_smoke.duo   # shape facts
DUO_PROVENANCE=1 duo compile ...           # transform provenance
zig test src/semantic_algebra.zig           # algebra unit tests
```

---

## The Twenty-Year Test

A language feels "inevitable" twenty years later when every feature is a logical consequence of a small number of orthogonal mechanisms.

Pass 2 reduces Duo from ~15 mechanisms to 8 algebras over one lattice. The features that would have taken years of keyword-by-keyword addition instead emerge as compositions of these algebras.

That's the architectural win. Not more features — fewer mechanisms that compose into more behaviors.
