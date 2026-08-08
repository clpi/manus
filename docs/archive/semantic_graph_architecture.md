> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Semantic Graph Architecture

> **Status:** Active plan. All agents read before architectural work.
> **Date:** 2026-08-04
> **Constraint:** MUST preserve Lua superset status, `@comp.*` surface ergonomics, and performance guarantees (beat/tie C on all 40 benchmarks). This is an internal substrate change, not a user-facing rewrite.

## Thesis

Duo's existential risk is not insufficient power. It is becoming a collection of powerful mechanisms whose interactions cannot be predicted, cached, validated, secured, or explained.

The winning version of Duo is:

> A compact language for defining computations, transformations, constraints, and objectives over a persistent semantic universe—where humans, compilers, libraries, and agents all manipulate the same program model at different levels of authority.

The current `@comp.*` combinators, derive system, concept system, and native lowering all work. But they are four separate mechanisms connected by string templates and special-case codegen hooks. This plan establishes their **common semantics** so that:

- Compositions are predictable (not emergent from implementation details)
- Results are cacheable (identity-stable across edits)
- Transformations are auditable (provenance, not string splicing)
- Access is controlled (capabilities, not "all code can do anything")
- Concurrent agents operate on the same model (transactions, not file locks)

## Non-Negotiable Constraints

1. **Lua superset** — Every valid Lua 5.4+ program remains valid Duo. The graph is an internal representation; surface syntax is unchanged.
2. **Performance** — The graph IR must lower to code that beats/ties C. The graph is a compiler intermediate, not a runtime interpreter. Final output is still native machine code (via C or direct emission).
3. **`@comp.*` surface** — All existing `@comp.*` directives remain valid and ergonomic. They become *sugar for graph transactions* rather than direct codegen hooks, but user code doesn't change.
4. **Incremental adoption** — The graph substrate is introduced alongside the current pipeline, not as a big-bang replacement. Subsystems migrate one at a time.
5. **Zero-cost abstraction** — The graph and its transaction machinery are compile-time only. No runtime overhead. No graph nodes exist at runtime.

---

## Priority 1: Persistent Semantic Graph with Durable Identities

### What

Replace the ephemeral AST (rebuilt every compilation) with a **persistent semantic graph** where every meaningful entity (type, function, concept, field, derive implementation, module) has a **stable identity** that survives across:

- Source edits (rename a function → same identity, new name attribute)
- Recompilations (incremental: only changed subgraphs are re-lowered)
- Agent sessions (an agent can reference "the Vec2 type" by ID, not path)
- Refactors (move a function between modules → same identity, new location edge)

### Node kinds (initial)

| Kind | Examples | Key edges |
|------|----------|-----------|
| `Module` | file, package | contains → Decl |
| `Type` | Vec2, i64, Tensor[3,f32] | fields →, satisfies →, derives → |
| `Function` | add, compute | params →, returns →, body → |
| `Concept` | HasXY, Numeric | requires → (fields, methods) |
| `Derive` | Display for Vec2 | implements →, source → |
| `Directive` | @comp.derive.all("HasXY", Eq) | targets →, produces → |
| `Value` | 42, "hello" | type → |
| `Expr` | a + b, if x then y | operands →, type → |
| `Constraint` | "must satisfy HasXY" | subject →, predicate |
| `Capability` | "may add methods to Vec2" | holder →, scope → |

### Identity semantics

- IDs are content-addressed for structural types, name-addressed for nominal entities.
- A `Type` node for `{ x: f64, y: f64 }` has the same ID regardless of which module defines it (structural equality).
- A named `type Vec2 = { x: f64, y: f64 }` has a name-based ID that is stable across edits to its fields (the name is the identity; fields are mutable attributes).
- Functions are identified by (module, name, overload-signature).

### Relationship to current implementation

The current `ast.zig` AST becomes a **parsing front-end** that produces graph nodes. The current `codegen.zig` becomes a **lowering back-end** that consumes graph nodes. The graph sits between them as the canonical program representation.

### Migration path

1. Introduce `src/graph.zig` with node/edge types alongside existing AST.
2. After parsing, build graph from AST (lossless round-trip initially).
3. Sema operates on graph instead of raw AST.
4. Codegen reads from graph instead of AST.
5. Eventually, incremental: only rebuild changed subgraph portions.

---

## Priority 2: Unified Transformation Engine with Contracts and Provenance

### What

Every `@comp.*` combinator, every derive, every optimization pass becomes a **transformation** — a function from graph → graph that:

- Has a **contract**: preconditions (what must be true for it to apply) and postconditions (what it guarantees after application).
- Produces **provenance**: every new node tracks which transformation created it and from what inputs.
- Is **composable**: transformations can be sequenced, parallelized, or nested with well-defined semantics.

### Current state vs. target

| Current | Target |
|---------|--------|
| `@comp.derive.all("HasXY", Eq)` iterates types, emits C string | Same directive proposes graph transactions: "for each Type node satisfying HasXY, add an Eq Derive node" |
| `@comp.tensor("A", "B", "C", cb)` builds a string via meta_codegen.zig | Same directive creates a ProductSweep transformation node whose output is a set of generated nodes |
| Optimization passes in sema.zig mutate AST in-place | Optimization passes propose graph rewrites subject to contracts |

### Transformation contract structure

```
transform DeriveBatch {
  precondition: ∀ type ∈ targets: type.satisfies(concept)
  postcondition: ∀ type ∈ targets: type.has_derive(trait)
  monotonic: true  -- only adds nodes, never removes
  idempotent: true -- applying twice = applying once
  provenance: "derive.all directive at {loc}"
}
```

### Provenance enables

- **Debugging**: "why does Vec2 have an `eq` method?" → "because @comp.derive.all on line 15 generated it"
- **Caching**: if neither the concept nor the type changed, the derive output is cache-valid
- **Rollback**: remove a directive → remove all nodes it produced (transitively)
- **Conflict detection**: two transforms proposing contradictory changes are flagged at compile time

### Migration path

1. Define `Transform` trait in `src/transform.zig` (precondition, apply, postcondition, provenance).
2. Wrap existing `@comp.*` hooks as transforms (same output, new interface).
3. Add provenance tracking to generated nodes.
4. Implement transform sequencing with contract validation.
5. Expose contracts in `@comp.agent.explain(node)` for debugging.

---

## Priority 3: First-Class Staging Plus Budgeted Partial Evaluation

### What

Replace the current ad-hoc comptime evaluation (fold string expressions, special-case `comptimeMetaHook`) with a **unified partial evaluator** that:

- Has a **stage**: compile-time (stage 0), link-time (stage 1), runtime (stage 2).
- Has a **budget**: maximum reduction steps before residualizing (prevents infinite loops, enables timeout-based tradeoffs).
- Produces either a **value** (fully reduced) or a **residual** (partially-reduced code for the next stage).
- Subsumes constant folding, dead-code elimination, comptime string building, AND the exponential combinators.

### Staging semantics

```
@(expr)             -- force to stage 0 (must fully reduce at compile time)
@comp.run { ... }   -- stage 0 block (may produce residuals if budget exceeded)
-- default --       -- stage inferred: reduce what's provably static, residualize the rest
```

### Budget model

- Default budget: 10^6 reduction steps per `@(expr)`.
- `@comp.compile.budget(N)` overrides per-expression.
- Exceeding budget in `@(expr)` is a compile error (explicit annotation = must succeed).
- Exceeding budget in default inference = residualize (emit as runtime code).

### Relationship to current comptime

The current `comptime_eval.zig` evaluator becomes the **stage-0 reducer**. The current `fold_meta_string_expr` in codegen.zig becomes unnecessary — the partial evaluator handles all folding uniformly. The exponential combinators (`@comp.tensor`, etc.) become stage-0 graph transformations whose output is a set of value nodes.

### Migration path

1. Add `Stage` enum to graph nodes (compile, link, runtime).
2. Implement budget-limited evaluator in `src/partial_eval.zig`.
3. Route `@(expr)` through partial evaluator instead of `comptime_eval`.
4. Gradually move `fold_meta_string_expr` cases to the partial evaluator.
5. Exponential combinators become graph transforms that the evaluator reduces.

---

## Priority 4: Effects and Capabilities as the Basis of Builds, Plugins, and Agents

### What

Every action that modifies the semantic graph requires a **capability**. Capabilities are:

- **Granular**: "may add methods to types satisfying HasXY" is different from "may modify any type."
- **Hierarchical**: a module capability implies function capabilities within it.
- **Auditable**: every graph mutation records which capability authorized it.
- **Revocable**: remove a plugin/agent → revoke its capabilities → identify all nodes it created.

### Capability lattice (initial)

```
root
├── module.create        -- create new modules
├── module.*.modify      -- modify any module
│   ├── type.*.modify    -- modify any type in the module
│   │   ├── type.*.derive.add    -- add derives to types
│   │   ├── type.*.field.add     -- add fields
│   │   └── type.*.method.add    -- add methods
│   ├── function.*.modify
│   └── ...
├── codegen.emit         -- emit raw C (escape hatch)
├── build.execute        -- run build commands
└── agent.coordinate     -- read/write coordination buffer
```

### Agent integration

Agents (Devin, kiro-cli, Claude, etc.) are **capability-bounded producers of proposed graph transactions**. They cannot directly mutate the graph. They propose transactions that are:

1. Validated against their capability token.
2. Checked for contract satisfaction.
3. Merged or rejected based on semantic conflicts with other proposals.

This replaces file-level coordination (`.agents/AGENT_COORDINATION.md`) with semantic-level coordination. Two agents can both propose "add Eq derive to Vec2" — the system deduplicates. Two agents proposing contradictory changes get a semantic conflict, not a git merge conflict.

### Migration path

1. Define capability types in `src/capability.zig`.
2. Tag existing `@comp.*` directives with required capabilities.
3. MCP tools (`duo_coordination_update`) operate on graph transactions instead of text appends.
4. Agent sessions receive a capability token on start (from `duo_agent_session_start`).
5. Conflict resolution replaces file-lock coordination.

---

## Priority 5: Transactional Semantic Editing for Agent Workflows

### What

Instead of agents editing source files and hoping they don't conflict, agents **propose semantic transactions** against the graph:

```
transaction "add-eq-to-vectors" {
  requires: capability(type.HasXY.derive.add)
  precondition: ¬ exists(Derive(Eq, Vec2))
  operations:
    - add_node(Derive, { trait: Eq, type: Vec2 })
    - add_node(Derive, { trait: Eq, type: Point3 })
  postcondition: ∀ t satisfying HasXY: has_derive(t, Eq)
}
```

### Transaction semantics

- **Serializable**: concurrent transactions produce the same result regardless of execution order (or abort with conflict).
- **Atomic**: all operations in a transaction succeed or none do.
- **Reversible**: every applied transaction has an inverse.
- **Mergeable**: non-conflicting transactions compose without coordination.

### Conflict model

Two transactions conflict iff:
- They modify the same node attribute to different values.
- One's postcondition contradicts the other's precondition.
- They create duplicate nodes (deduplicated, not conflicted).

Non-conflicting transactions merge automatically. This eliminates:
- The 5+ agent coordination problem (no more file locks).
- Duplicate work (same transaction proposed twice = applied once).
- Regression from parallel edits (contracts catch violations).

### Migration path

1. Define `Transaction` type in `src/transaction.zig`.
2. MCP tools produce transactions instead of file edits.
3. `zig build` applies pending transactions before compilation.
4. Agent dedup check becomes "is this transaction already applied?"
5. Rollback = unapply transaction (remove nodes it created).

---

## Priority 6: Equality Saturation

### What

Instead of applying rewrite rules in a fixed order (which can miss optimal sequences), maintain an **e-graph** (equivalence graph) where multiple equivalent representations coexist. Extract the best one according to a cost model.

### Application to Duo

- **Optimization**: `a * 2` ≡ `a << 1` ≡ `a + a` — all three exist in the e-graph; cost model picks cheapest for target.
- **Metaprogramming**: different combinator expansions produce equivalent outputs; the system picks the most efficient.
- **Native lowering**: `C emission` ≡ `SIMD intrinsic` ≡ `GPU kernel` — same computation, different lowering; cost model selects.

### Relationship to current rewrite_rules.zig

The existing `src/rewrite_rules.zig` and `src/rewrite_apply.zig` become the **rule database** for the equality saturation engine. Instead of applying rules greedily, they populate equivalence classes.

### Migration path

1. Implement e-graph data structure in `src/egraph.zig`.
2. Register existing rewrite rules as e-graph axioms.
3. Add cost model (latency, code size, energy — selectable).
4. Extraction phase replaces greedy rewrite application.
5. `@comp.rewrite.describe` reports equivalence classes, not just rule counts.

---

## Priority 7: Foreign-Language Semantic Adapters

### What

Allow other languages' programs to be represented as subgraphs, enabling Duo's transformations to operate across language boundaries.

### Adapters

| Language | Adapter | What it provides |
|----------|---------|------------------|
| C | `@comp.c.import` | C declarations as graph nodes (types, functions) |
| Rust | `@comp.foreign("rust", ...)` | Rust trait impls as concept satisfactions |
| Python | `@comp.foreign("python", ...)` | Python type stubs as graph types |
| WASM | `@comp.wasm(...)` | WASM module exports as function nodes |

### Key principle

Foreign nodes are **opaque** at the computation level (Duo doesn't rewrite Rust code) but **transparent** at the type/interface level (Duo knows what interfaces they satisfy and can generate glue code).

### Migration path

1. Current `@comp.c.import` already partially does this (parses C headers into types).
2. Generalize to an adapter trait: `ForeignAdapter { parse, type_map, glue_emit }`.
3. Rust/Python/WASM adapters follow the same trait.
4. `@comp.foreign` becomes sugar for "load adapter, import subgraph."

---

## Priority 8: Multi-Objective Optimization and Implementation Portfolios

### What

Instead of a single optimization goal (minimize latency), support **multiple objectives** with **Pareto-optimal** selections:

- Latency vs. code size vs. energy vs. compile time
- `@comp.compile.objective("latency")` — single objective
- `@comp.compile.objectives("latency", "code_size")` — Pareto frontier

### Implementation portfolios

For hot functions, generate **multiple implementations** and select at:
- Compile time (based on target analysis)
- Link time (based on PGO data)
- Runtime (based on input characteristics — e.g., small array → scalar, large → SIMD)

### Relationship to current lowering

The current "lower to whatever is fastest" philosophy becomes formalized. Instead of a single codegen path, the system maintains a **portfolio** of equivalent lowerings (via equality saturation) and selects based on the active objective function.

### Migration path

1. Add objective annotations to function nodes.
2. Cost model in e-graph extraction becomes parameterized by objective.
3. Portfolio generation = extract top-k from e-graph instead of top-1.
4. Runtime dispatch between portfolio members (for input-dependent selection).

---

## Priority 9: Lightweight Proof-Carrying Transformations

### What

Transformations carry **lightweight proofs** that their output satisfies their postcondition. Not full formal verification — lightweight witnesses that can be checked cheaply.

### Proof kinds

| Kind | Example | Checking cost |
|------|---------|---------------|
| Type preservation | "output has same type as input" | O(1) — compare type IDs |
| Monotonicity | "only added nodes, never removed" | O(n) — diff transaction |
| Idempotency | "applying twice = applying once" | O(1) — check if already applied |
| Semantic preservation | "output computes same values" | O(test_suite) — run tests |
| Termination | "transform completes in budget" | O(1) — budget counter |

### Why lightweight

Full verification (Coq/Lean style) is too expensive for a compile-time system. Lightweight proofs are:
- Cheap to generate (the transform itself records the evidence).
- Cheap to check (no SMT solver — structural checks + bounded testing).
- Informative on failure (points to the specific violated invariant).

### Migration path

1. Add proof obligations to Transform contracts.
2. Existing transforms get trivial proofs (monotonicity for derives, type preservation for rewrites).
3. `@comp.agent.explain(node)` shows proof chain for any generated node.
4. CI gate: all transforms must carry valid proofs.

---

## Priority 10: Relational Compiler Queries and Architectural Rules

### What

The semantic graph is queryable via a **relational query language** (Datalog-like). Architectural rules are queries that must hold:

```duo
-- Rule: no circular module dependencies
@comp.rule("no-cycles")
  not exists(m1: Module, m2: Module |
    m1.depends_on(m2) and m2.depends_on(m1))

-- Rule: all public types must have Display
@comp.rule("public-display")
  forall(t: Type | t.is_public =>
    exists(d: Derive | d.type == t and d.trait == Display))

-- Query: what concepts does Vec2 satisfy?
@comp.query("Vec2.concepts")
  { c.name | c: Concept, t: Type |
    t.name == "Vec2" and t.satisfies(c) }
```

### Relationship to current `@comp.agent.catalog` / `@comp.agent.gaps`

These become queries over the graph rather than hand-maintained text files. The catalog is `{ d.name | d: Directive }`. The gaps list is `{ t | t: Type, not exists(d: Derive(Display, t)) }`.

### Migration path

1. Implement simple pattern matching over graph nodes in `src/query.zig`.
2. `@comp.rule` directives register compile-time assertions.
3. `@comp.query` returns results as compile-time tables/strings.
4. LSP integration: queries power go-to-definition, find-references, etc.
5. Architectural rules run as part of `zig build test`.

---

## Implementation Phases

### Phase 0: Design stabilization (current)
- This document.
- All agents acknowledge the direction.
- **No new `@comp.*` directives** added without checking they fit the graph model.
- Existing directives continue working unchanged.

### Phase 1: Graph IR alongside AST (weeks 1-4)
- `src/graph.zig` — node/edge types, identity scheme.
- Parser → AST → Graph builder (lossless).
- Graph → existing codegen (passthrough initially).
- Prove: graph round-trips without changing output.

### Phase 2: Sema on graph (weeks 5-8)
- Type checking operates on graph nodes.
- Concept satisfaction is a graph query.
- Derive generation becomes a graph transformation.
- Prove: all 702 tests pass with graph-based sema.

### Phase 3: Transform engine (weeks 9-12)
- `src/transform.zig` — contracts, provenance, composition.
- Existing `@comp.*` combinators reimplemented as transforms.
- Partial evaluator replaces `comptime_eval` + `fold_meta_string_expr`.
- Prove: all 40 benchmarks still beat/tie C.

### Phase 4: Capabilities and transactions (weeks 13-16)
- `src/capability.zig`, `src/transaction.zig`.
- MCP tools produce transactions.
- Agent coordination via semantic merge (replaces file locks).
- Prove: concurrent agent test passes.

### Phase 5: Advanced (ongoing)
- Equality saturation.
- Foreign adapters.
- Multi-objective optimization.
- Proof-carrying transforms.
- Relational queries.

---

## What This Does NOT Change

- **User syntax**: `@comp.derive.all("HasXY", Eq)` still works exactly the same way.
- **CLI**: `duo compile`, `duo run`, `duo check` — unchanged.
- **Performance**: all 40 benchmarks must still beat/tie C after each phase.
- **Lua compatibility**: every valid Lua program remains valid.
- **Existing test suite**: 700+ tests must pass continuously.
- **@comp.* surface**: all existing directives are preserved as sugar.

## What This DOES Change (internally)

- The compiler's canonical representation moves from AST to graph.
- Codegen reads from graph nodes instead of AST nodes.
- Metaprogramming output is graph transactions instead of string templates.
- Agent coordination is semantic (graph transactions) instead of textual (file locks).
- Caching becomes identity-based (if the node didn't change, its lowering is valid).
- Debugging becomes provenance-based (every generated node traces to its origin).

---

## Relationship to Current Goals

| Current goal | How the graph serves it |
|---|---|
| Beat C performance | Graph enables equality saturation → optimal lowering selection |
| No lua_Value boxing | Graph type annotations are authoritative → lowering always uses native types when available |
| Exponential metaprogramming | Combinators are graph transforms → compose predictably, cache results |
| Agent coordination | Transactions replace file locks → semantic merge, dedup, conflict detection |
| Duo as scripting language | Graph queries power tooling (find, refactor, analyze) without external scripts |
| Minimum syntax, maximum power | Fewer mechanisms (graph + transforms) derive more capability than many ad-hoc hooks |

---

## Open Questions

1. **Graph persistence format** — Do we persist to disk (SQLite? custom binary?) or rebuild from source each time? Disk persistence enables incremental compilation but adds complexity.
2. **E-graph vs. simple graph** — Do we start with equality saturation from day one, or add it later? Starting simple is lower risk but may require later refactoring.
3. **Transaction conflict resolution** — Last-writer-wins? Abort-on-conflict? User-mediated? The right default matters for agent ergonomics.
4. **Capability assignment** — Who grants capabilities to agents? The user? A config file? Per-project policy?
5. **Budget defaults** — What's the right default reduction budget? Too low = useful comptime fails. Too high = slow compilation.

---

## For All Agents: Immediate Protocol

1. **Read this document** at session start (alongside AGENTS.md and .agents/AGENT_COORDINATION.md).
2. **Before adding new `@comp.*` directives**: ask "does this fit as a graph transformation with a contract?" If not, reconsider.
3. **Existing directives**: continue working on correctness, performance, native lowering. These are not frozen — but their internal implementation will eventually migrate to graph transforms.
4. **New infrastructure work**: should align with the graph direction. Prefer changes that move toward "nodes with identity" over "strings with templates."
5. **Performance work**: unchanged. Beat C. No regressions. The graph is an internal concern.
