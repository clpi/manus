# Agent Alignment Compass

> **Read this first every session** (2 min), then drill into linked docs as needed.
> All agents — Cursor, Claude, Codex, Devin, Kiro, Hermes, OpenCode, Pi, etc.

## One direction

Duo is **not** “Lua with every advanced feature.” It is a compact language for
**computations, transformations, constraints, and objectives** over a persistent
semantic program model — where humans, compilers, libraries, and agents manipulate
the **same graph** at different **capability** levels.

**Existential risk:** powerful `@comp.*` mechanisms whose interactions cannot be
predicted, cached, validated, secured, or explained. We add power **through**
shared semantics, not around them.

**Design principle (Pass 2):** Don't ask "what features are missing?" Ask: "what
independent mechanisms can become manifestations of the same underlying semantic
system?" Fewer mechanisms that compose into more behaviors.

**Pass 3 (2026-08-04):** Operationalize convergence across directive surface, keyword
retirement, compact grammar, and toolchain catalogs. Read
[`plans/pass3_directive_grammar_convergence.md`](plans/pass3_directive_grammar_convergence.md)
and `docs/catalogs/`. Export: `duo catalog` (Pass 3 JSON), `duo algebra` (Pass 2 JSON).

**Pass 4 (2026-08-04):** Native end-to-end compilation — eliminate boxed architecture as
center, establish Duo-owned pipeline layers, modular runtime, direct backend, self-hosting
roadmap. Read [`plans/pass4_native_end_to_end.md`](plans/pass4_native_end_to_end.md),
`docs/catalogs/bootstrap_dependencies.md`, and `docs/catalogs/performance_barriers.md` (PB-011+).
Export: `duo catalog` includes `pass4` JSON.

**Pass 5 (2026-08-04):** Semantic Interchange Model (SIM) for cross-language import,
transformation, and ecosystem tooling — must not outrun Pass 4. Read
[`plans/pass5_semantic_interchange.md`](plans/pass5_semantic_interchange.md).
Export: `duo sim <file>` (SIM v0 JSON), `duo catalog` includes `pass5` JSON.

Full plan: [`plans/semantic_graph_architecture.md`](plans/semantic_graph_architecture.md)
Convergence audit: [`plans/pass2_foundational_convergence.md`](plans/pass2_foundational_convergence.md)

---

## What we never sacrifice

| Commitment | Gate / proof |
| --- | --- |
| **Performance** | `zig build bench` — Duo ≥ C on all 40 benchmarks; zero regressions |
| **Native typed paths** | No `lua_Value` on typed/comptime paths — native C scalars/structs |
| **Lua superset** | `.lua` untyped compatible; `.duo` adds types + `@comp.*` without breaking dynamic code |
| **Ergonomics** | Minimum syntax; `@comp.*` / `@()` unchanged for authors; better errors, not more ceremony |
| **Exponential metaprogramming** | O(1) author input → O(n^k) native output — via **registered** transforms |

Architecture serves these goals; it does **not** trade them for purity.

---

## Priority stack (foundational first)

**Tier A — build the spine**

1. Persistent semantic graph + durable identities → `src/semantic_graph.zig`
2. Unified transformation engine + contracts + provenance → `src/transform_engine.zig`
3. First-class staging + budgeted partial evaluation
4. Effects & capabilities (builds, emit, FS, agents)
5. Transactional semantic editing (agent graph patches)

**Tier B — after spine**

6. Equality saturation · 7. Foreign adapters · 8. Multi-objective portfolios ·
9. Proof-carrying transforms · 10. Relational compiler queries

Details: [`semantic_universe.md` §2–§9](semantic_universe.md)

---

## Current phase (Pass 5 — Semantic interchange + cross-language)

**Pass 4** native boundaries and P4-M1 milestone are in place.
**Pass 5** extends Duo semantics across language boundaries via SIM — without reversing Pass 4.

| Track | Doc / command | Status |
| --- | --- | --- |
| Pass 5 plan | `docs/plans/pass5_semantic_interchange.md` | ✅ |
| SIM v0 | `src/sim.zig` | 🔄 partial |
| Native export | `duo sim <file.duo>` | ✅ |
| C import (Layer B) | `@c.import` include-only today | ⬜ Phase 2 |
| First milestone P5-M1 | C `CPoint`/`distance2` → direct call | ⬜ |
| Agent JSON | `duo catalog` → `pass5` section | ✅ |

**Constraint:** Pass 5 must not outrun Pass 4. Foreign work reuses SIM + transforms, not text templates.

---

## Previous phase (Pass 4 — Native end-to-end + self-hosting)

**Pass 3** (directive surface, grammar catalogs) is largely complete.
**Pass 4** establishes implementation boundaries: no universal boxing, Duo-owned pipeline,
modular runtime, direct native backend, incremental self-hosting.

| Track | Doc / command | Status |
| --- | --- | --- |
| Pass 4 plan | `docs/plans/pass4_native_end_to_end.md` | ✅ |
| Barrier catalog | `docs/catalogs/performance_barriers.md` (PB-011+) | 🔄 |
| Bootstrap catalog | `docs/catalogs/bootstrap_dependencies.md` | ✅ |
| First milestone | `examples/pass4_native_milestone.duo` | ✅ C + direct arm64 |
| Direct backend | `src/native_backend.zig` (arm64 Mach-O) | 🔄 partial |
| Agent JSON | `duo catalog` → `pass4` section | ✅ |

**Pass 4 invariants:** Preserve observable Lua semantics; replace boxed VM architecture
where specialization permits. See P4-01–P4-09 in the Pass 4 plan.

---

## Previous phase (Pass 3 — Directive surface + grammar minimalism)

**Pass 2 spine** (algebras, transform registry, G-061 parity) is largely in place.
**Pass 3** operationalizes convergence across directives, keywords, compact grammar, and tooling.

| Track | Doc / command | Status |
| --- | --- | --- |
| Pass 3 plan | `docs/plans/pass3_directive_grammar_convergence.md` | ✅ |
| Keyword catalog | `docs/catalogs/keywords.md` (53 → target 30) | ✅ |
| Directive catalog | `docs/catalogs/directives.md` | ✅ |
| Grammar catalog | `docs/catalogs/grammar_compactness.md` | ✅ |
| Convergence map | `docs/catalogs/convergence.md` | ✅ |
| Performance barriers | `docs/catalogs/performance_barriers.md` | ✅ |
| Agent JSON | `duo catalog` / `duo algebra` | ✅ |

**Symbolic operators (deprioritized):** Do not teach or expand `|>` pipeline infix or
infix `@` matmul in new `.duo` code — prefer `f(x)`, `map(data, .field)`, and explicit
tensor APIs. Parser warns in `.duo` mode; see `docs/catalogs/grammar_compactness.md` GR-DP01–04.

Pass 2 audit: [`plans/pass2_foundational_convergence.md`](plans/pass2_foundational_convergence.md)

---

## Previous phase (Pass 2 — Foundational Convergence)

**Core principle:** Collapse independent mechanisms into shared algebras over one Knowledge Lattice.

| Algebra | Role | Status |
| --- | --- | --- |
| **Knowledge Lattice** | "how much does the compiler know?" | ✅ `KnowledgeLevel`; codegen `module_knowledge` 🔄 |
| **Descriptor Algebra** | types + concepts + derive + enums + modules = one mechanism | ✅ `DescriptorExpr` spine; sema wiring ⬜ |
| **Shape Algebra** | universal structural operations | ✅ `ShapeOp` + graph nodes |
| **Call Algebra** | calls as semantic objects driving all specialization | 🔄 `CallSite` + `call.*` transforms on graph lift |
| **Transformation Registry** | every rewrite is graph→graph + contract | ✅ `transform_engine.zig` |
| **Stage Polymorphism** | arbitrary execution stages replace comptime/runtime | ✅ `Stage` enum; routing ⬜ |
| **Pipeline Graph IR** | pipelines as optimization graphs | ⬜ `PipelineNode` planned |
| **Effect Algebra** | effects as composable descriptor values | ⬜ `EffectSet` planned |

Full audit: [`plans/pass2_convergence.md`](plans/pass2_convergence.md)

| Infrastructure | Status | Owner tag |
| --- | --- | --- |
| Plan doc | ✅ `docs/semantic_universe.md` | — |
| **Pass 2 convergence audit** | ✅ `docs/plans/pass2_foundational_convergence.md` | `convergence-audit` |
| **Algebra spine** | ✅ `src/semantic_algebra.zig` + `duo algebra` | `convergence-audit` |
| **Knowledge ↔ sema bridge** | 🔄 `knowledgeOfType`, `module_knowledge` in codegen | `convergence-audit` |
| **Shape transforms registry** | ✅ `shape.seal` … `shape.lower` in `transform_engine` | `transform-registry` |
| **Call transforms registry** | ✅ `call.inline` … `call.simd_lower` + graph lift | `transform-registry` |
| **CallSite graph metadata** | 🔄 `attachCallTransforms` on specializable calls | `graph-spine` |
| Transform registry stub | ✅ `src/transform_engine.zig` | `transform-registry` |
| Graph spine | 🔄 `src/semantic_graph.zig` (`DUO_GRAPH=1`, `duo graph` JSON export) | `graph-spine` |
| Graph shape facts | ✅ `shape_id` + `why` in `duo graph` JSON | `graph-spine` |
| 3-site parity harness (tier-1 `@comp.*`) | ⬜ open | `parity-harness` |
| `DUO_PROVENANCE=1` in driver | ✅ env + stderr summary | `transform-registry` |
| `@comp.shape` alias | ✅ → `__type_shape` | `graph-spine` |
| `@comp.why.shape` / `@comp.why` | ✅ factual storage-class explanations | `graph-spine` |
| MCP `duo_table_shapes` | ✅ `duo-mcp/duo_lsp.duo` → `duo graph` | `graph-spine` |
| Parser/`isMetaAttribute` audit | 🔄 ongoing | `transform-registry` |

Track gap **G-061** in [`.agents/AGENT_COORDINATION.md`](../.agents/AGENT_COORDINATION.md).

---

## Moratorium (effective now)

Before merging **any** new or changed `@comp.*` combinator / fold / meta hook:

1. **Register** in `src/transform_engine.zig` (descriptor + budget + contract)
2. **Parity test** — same behavior at **top-level**, **nested callback**, **block body**
3. **One dispatch path** — route through transform engine (no fourth ad-hoc fold)
4. **Native contract** — output must not introduce `lua_Value` on typed paths
5. **Bench** if codegen touched + append [`docs/performance.md`](performance.md)

---

## Session start (every agent)

1. Read this file + skim [`semantic_universe.md`](semantic_universe.md) phase section
2. Read [`AGENTS.md`](../AGENTS.md) non-negotiables
3. MCP **`duo_agent_session_start(agent_id="…")`** or read [`.agents/AGENT_COORDINATION.md`](../.agents/AGENT_COORDINATION.md)
4. **Claim** work before editing shared files (`duo_coordination_update` / Active claims)
5. Build under **`scripts/duo_lock.sh`** — default: `zig build && zig build agent-smoke`

**Never:** `git stash` · duplicate coordination files · tier-3 bench in parallel · new `@comp.*` without registry

---

## Canonical doc map

| Read | Path |
| --- | --- |
| **This compass** | `docs/AGENT_ALIGNMENT.md` |
| **Pass 5 cross-language** | `docs/plans/pass5_semantic_interchange.md` |
| **Pass 4 native** | `docs/plans/pass4_native_compilation.md` |
| **Pass 3 directive/grammar** | `docs/plans/pass3_directive_grammar_convergence.md` |
| **Pass 3 catalogs** | `docs/catalogs/README.md` + `duo catalog` |
| **Pass 2 convergence** | `docs/plans/pass2_convergence.md` |
| Architecture plan | `docs/semantic_universe.md` |
| Agent rules | `AGENTS.md` |
| Claims, gaps, log | `.agents/AGENT_COORDINATION.md` |
| Router index | `.agents/AGENT_CANONICAL.md` |
| `@comp.*` catalog | `docs/metaprogramming.md` |
| **Keyword catalog** | `docs/catalogs/keywords.md` |
| **Directive catalog** | `docs/catalogs/directives.md` |
| **Grammar catalog** | `docs/catalogs/grammar_compactness.md` |
| Performance ledger | `docs/performance.md` |
| MCP setup | `.agents/AGENT_INTEGRATION.md` |

---

## Three concerns (do not conflate)

1. **Agent coordination** — buffers, MCP, claims (this doc + `.agents/*`)
2. **End-user agent hooks** — `@comp.agent.*`, `std.agent`, `docs/agent_hooks.md`
3. **Language implementation** — compiler, codegen, native lowering

---

## Directional alignment check

Before you ship, ask:

- Does this **preserve** bench / native / Lua / ergonomics / exponential MP?
- Does it **reduce entropy** (registry, contract, parity) or **add entropy** (another special case)?
- Could this mechanism be a **consequence** of an existing algebra instead of a new one?
- Is work **claimed** and **logged** for other agents?
- If touching meta: would **G-060** happen again (expression vs directive split)?

If any answer is wrong, stop and align in the coordination buffer first.

---

*Last updated: 2026-08-04 — Pass 2 convergence audit.*
