# Duo Semantic Universe — Architecture Plan

> **Status:** Canonical plan (2026-08-04). All agents read at session start alongside
> **`docs/AGENT_ALIGNMENT.md`** (2-min compass), `AGENTS.md`, and `.agents/AGENT_COORDINATION.md`.
>
> **North star:** A compact language for defining computations, transformations,
> constraints, and objectives over a **persistent semantic universe** — where humans,
> compilers, libraries, and agents manipulate the **same program model** at different
> levels of authority.
>
> **Existential risk:** Duo becoming a collection of powerful `@comp.*` mechanisms
> whose interactions cannot be predicted, cached, validated, secured, or explained.
> Power without shared semantics is entropy.

This plan **does not replace** existing goals in `AGENTS.md`. It **organizes** them:

| Existing non-negotiable | How this plan serves it |
| --- | --- |
| Beat/tie C on all benchmarks | Graph + staging enable **incremental** and **cached** codegen; fewer full recompiles |
| No `lua_Value` on typed/comptime paths | Transform contracts enforce native lowering; violations are compile errors |
| Lua 5.5 superset + `.duo` typed extensions | Graph stores both dialects; transforms preserve dynamic paths |
| `@comp.*` exponential metaprogramming | Combinators become **registered transforms**, not ad-hoc fold paths |
| Minimum syntax → maximum output | One transform registry + one staging model vs N special cases |
| Agent/MCP/LSP integration | Transactional graph edits + capability bounds for agents |

---

## 1. What we are building (one sentence)

**Duo is a capability-bounded producer of proposed graph transactions** over a durable
semantic program model, with a unified transformation engine that lowers to optimal
native code (C/asm/GPU/WASM) under explicit performance contracts.

---

## 2. Priority ranking (foundational → advanced)

### Tier A — Foundational (do these first)

| # | Pillar | Outcome | Preserves |
| --- | --- | --- | --- |
| **A1** | **Persistent semantic graph + durable identities** | Every concept, type, func, derive, combinator application, and emitted artifact has a stable ID across parses/sessions | Incremental compile; agent diff/merge; LSP precision |
| **A2** | **Unified transformation engine + contracts + provenance** | All `@comp.*` / folds / derives / codegen hooks register as `(name, input_kind, output_kind, contract, apply)` | Predictable composition; one place to fix G-060-class bugs |
| **A3** | **First-class staging + budgeted partial evaluation** | User-visible phases (`parse → sema → transform → lower → link`); step/time/output-size budgets; resumable partial results | Ergonomics (`@comp.match` in callbacks works everywhere); no silent empty strings |
| **A4** | **Effects & capabilities** | Builds, `@c.emit`, FS, subprocess, MCP tools declare capabilities; violations fail at compile/agent boundary | Security for plugins and parallel agents |
| **A5** | **Transactional semantic editing** | Agents propose `GraphPatch[]`; policy/human commits; rollback; merge semantics | Safe multi-agent development |

### Tier B — Advanced (after Tier A spines exist)

| # | Pillar | Notes |
| --- | --- | --- |
| **B6** | Equality saturation | E-graph rewrites on graph nodes; shares engine with A2 |
| **B7** | Foreign-language semantic adapters | Import Python/Rust/C headers as graph fragments, not string paste |
| **B8** | Multi-objective optimization + implementation portfolios | Choose among lowering strategies under perf/size/compile-time objectives |
| **B9** | Lightweight proof-carrying transformations | Attach optional proof objects to high-risk transforms |
| **B10** | Relational compiler queries + architectural rules | `query(types satisfying HasXY)`; lint rules over graph |

### Explicit anti-goal

**Do not** add a long list of individually impressive `@comp.*` directives before
establishing **common semantics** (A2 + A3). New combinators require:

1. Registration in the transform registry (even if backed by legacy code initially).
2. A **contract** (input/output kinds, native-only path, budget class).
3. **Parity tests** (top-level, nested callback, block body — see G-060).
4. **Provenance** stub (transform id, input hash, output hash, source site).

---

## 3. Current state (honest inventory)

What exists today maps to **pre-graph** fragments:

| Component | Location | Role today | Target |
| --- | --- | --- | --- |
| AST | `src/ast.zig` | Ephemeral per compile | Graph node storage |
| Sema | `src/sema.zig` | Types, concepts | Graph edges + checks |
| Comptime eval | `src/comptime.zig` | Partial evaluation | Staging phase 3 (budgeted) |
| Meta hooks | `src/codegen.zig` `comptimeMetaHook` | Ad-hoc combinator dispatch | Transform registry plugin |
| Meta codegen | `src/meta_codegen.zig` | Combinator implementations | Transform backends |
| Fold paths | `fold_meta_string_expr`, `maybe_emit_meta_string_call` | Duplicate semantics | Single `applyTransform` |
| Derive registry | `src/meta_directives.zig`, `derive_registry.zig` | Macro store | Graph-attached derive nodes |
| Agent coordination | `.agents/AGENT_COORDINATION.md` | Social locking | + semantic transactions |
| MCP / LSP | `duo-mcp`, `duo-lsp` | Tooling | Graph patch protocol |

**Recent lesson (G-060):** `@comp.derive.power` parsed as expression at module level but
as `.directive` stmt inside `fun(c)` because `isMetaAttribute` lists were inconsistent.
That class of bug is **semantic fragmentation**, not a one-off fix.

---

## 4. Semantic graph (A1) — sketch

### Node kinds (initial set)

- `Module`, `SourceFile`, `Span`
- `Concept`, `TypeAlias`, `Record`, `Enum`, `Func`, `Macro`, `DeriveMacro`
- `TransformApp` (application of a combinator/derive at a site)
- `ComptimeValue` (folded string/int/table — typed, not `lua_Value`)
- `EmitArtifact` (C fragment, symbol ref, link unit)
- `AgentPatch` (proposed edit, status: draft | validated | committed)

### Identity

```
id = hash(module_path, kind, stable_path, generation)
```

- **stable_path:** e.g. `Vec2`, `main`, `@comp.match:42:10`
- **generation:** bumped on committed transactional edit
- IDs survive formatter runs and benign reparses when span+path match

### Storage (phased)

| Phase | Implementation | Agent impact |
| --- | --- | --- |
| **0** | In-memory graph during compile; debug dump JSON | None |
| **1** | `.duo/graph/<module>.json` sidecar; invalidated on source hash change | Optional read via MCP |
| **2** | Incremental graph merge on edit | LSP + agents use IDs |
| **3** | Workspace graph index | Cross-module queries (B10) |

**Performance rule:** Graph build must not regress `zig build bench`. Phase 0 is
debug-only behind a flag (`DUO_GRAPH_DUMP=1`).

---

## 5. Unified transformation engine (A2) — sketch

### Transform descriptor

```zig
pub const Transform = struct {
    name: []const u8,           // public: "comp.derive.power"
    internal: []const u8,      // "__derivepower"
    input_kind: InputKind,     // .concept + .derive_name | .func_callback + ...
    output_kind: OutputKind,   // .native_string | .c_fragment | .type_set
    budget_class: BudgetClass, // .linear | .polynomial | .exponential | .factorial
    contract: Contract,        // native-only, max_input_size, requires_concepts
    apply: *const fn (ctx: *TransformCtx, args: []Value) TransformError!Value,
};
```

### Single entry points (migration target)

1. **Parse:** `@comp.foo` → always one AST shape (call to internal name), never `.directive` in expression positions.
2. **Apply:** `transform_engine.apply("comp.derive.power", args, site)` — used by fold, comptime eval, and codegen.
3. **Prove:** `provenance_log.append(site, transform, inputs_hash, outputs_hash)`.

### Contract examples

| Transform | Contract |
| --- | --- |
| `@comp.derive.power` | Output: native C string; inputs: concept spec + derive name; budget: exponential in matching types; no `lua_Value` |
| `@comp.match` | Callback must be `.func`; each arm evaluated under same staging; errors surface, not swallowed |
| `@c.emit` | Capability: `emit_c`; scope: current module; audited in provenance |

### Migration rule for agents

When touching any of: `comptimeMetaHook`, `fold_meta_string_expr`, `maybe_emit_meta_string_call`, `meta_codegen.*Hook`:

- **Prefer** routing through `transform_engine` (add stub if not implemented).
- **Do not** add a fourth independent dispatch path.
- **Add** parity test in `src/meta_transform_tests.zig` (to be created).

---

## 6. Staging + budgets (A3) — sketch

### Stages (user-visible eventually; internal first)

```
S0 parse     → AST/graph skeleton
S1 sema      → types, concepts, satisfaction
S2 transform → @comp.*, derive, fold (budgeted)
S3 lower     → C/asm/GPU
S4 link      → binary / wasm
```

### Budgets

| Class | Default limit | User override |
| --- | --- | --- |
| Linear sweep | 10_000 steps | `@comp.budget(steps=N)` |
| Exponential (power set) | `MAX_POWERSET_SIZE` (24) | compile error with hint |
| Factorial (permute) | hard cap | use `@comp.choose` instead |

**Partial results:** Failed budget → structured error with `{ stage, transform, consumed, limit, resumable }`, not `""`.

**Ergonomics preserved:** Authors keep writing `@comp.match("A|B", fun(m) ... end)` — staging is implementation, not new syntax (optional `@stage` later).

---

## 7. Capabilities (A4) — sketch

### Capability tokens (initial)

| Token | Grants |
| --- | --- |
| `comptime:eval` | `@()`, arithmetic, table literal fold |
| `meta:transform` | `@comp.*` combinators |
| `emit:c` | `@c.emit`, `@comp.c.emit` |
| `emit:foreign` | `@comp.foreign`, `@c.import` |
| `fs:read` | `@comp.embed.file`, build inputs |
| `fs:write` | `@comp.c.emit.file`, build outputs |
| `proc:spawn` | `@comp.run`, build scripts |
| `agent:propose` | MCP graph patch propose |
| `agent:commit` | MCP graph patch commit |

### Default bundles

| Context | Capabilities |
| --- | --- |
| User `.duo` module | `comptime:eval`, `meta:transform`, `emit:c` |
| `duo build` driver | + `fs:*`, `proc:spawn` |
| Agent (default) | `agent:propose` only |
| Agent (trusted) | + `agent:commit` with policy |

Plugins and stdlib modules declare required capabilities in module metadata (future `@comp.capabilities(...)`).

---

## 8. Transactional editing (A5) — sketch

### Graph patch (agent protocol)

```json
{
  "patch_id": "uuid",
  "agent_id": "cursor/agent",
  "ops": [
    { "op": "replace_node", "id": "...", "new": { ... } },
    { "op": "apply_transform", "site": "...", "transform": "comp.derive.power", "args": [...] }
  ],
  "capabilities_used": ["agent:propose", "meta:transform"],
  "parent_generation": 42
}
```

### Workflow

1. Agent **proposes** patch (never silent file stomp for semantic edits).
2. Compiler **validates** patch against contracts + capabilities.
3. Human or policy **commits** → generation++, graph updated, codegen incremental.
4. **Rollback** to generation N.

MCP tools (`duo-mcp`): `graph_propose_patch`, `graph_validate_patch`, `graph_commit_patch`, `graph_diff`.

**Coexistence:** Text edits remain valid; reparse merges into graph. Agents migrate to patches over time.

---

## 9. Phased roadmap (all agents align here)

### Phase 0 — Alignment (now → 2 weeks)

**Goal:** Same page; stop entropy growth.

- [x] This document (`docs/semantic_universe.md`)
- [x] `src/transform_engine.zig` — registry stub + dispatch to existing hooks
- [x] `src/meta_transform_tests.zig` — G-061 tier-1 parity harness
- [x] `src/pass1_catalog.zig` — Pass 1 audit catalog (`duo catalog` → `pass1`)
- [ ] `isMetaAttribute` / parser parity audit — all expression combinators excluded (G-060 pattern)
- [x] Parity test harness: `{top_level, nested_callback, block_body}` × core combinators
- [x] Provenance debug log behind `DUO_PROVENANCE=1` (driver reads env in `main.zig`)
- [ ] Agent rule: no new combinator without registry entry + parity test (documented; G-061)

**Gates:** `zig build test`, `zig build bench`, `zig build agent-smoke` — no regressions.

### Phase 1 — Graph spine (2–6 weeks)

- [ ] In-memory semantic graph built from AST+sema (`src/semantic_graph.zig`) — **skeleton + `table_shape` lift (partial)**
- [x] `StorageClass` ladder wired (`dynamic`→`native`) for typed records; `@comp.type.shape` introspection
- [ ] Stable IDs for concepts, types, funcs, transform applications
- [x] JSON dump for debugging (`duo graph <file.duo>`); optional sidecar open
- [ ] LSP: map cursor → graph node id (read-only)

**Claim tag:** `graph-spine` (one agent; coordinate in Active claims)

| Tag | Phase | Primary files |
| --- | --- | --- |
| `graph-spine` | 1 | `src/semantic_graph.zig`, `src/sema.zig` |
| `transform-registry` | 2 | `src/transform_engine.zig`, `src/sema.zig`, `src/codegen.zig` |
| `staging-budget` | 3 | `src/comptime.zig`, `src/meta_module.zig` |
| `capabilities` | 3–4 | `src/main.zig`, `duo-mcp` |
| `semantic-tx` | 4 | `duo-mcp`, future `src/semantic_tx.zig` |

### Phase 2 — Engine unification (4–8 weeks)

- [ ] All combinators register in `transform_engine`
- [ ] Delete duplicate dispatch from `fold_meta_string_expr` where possible
- [ ] Contracts enforced; budget errors structured
- [ ] `@comp.compile.cached` backed by graph hash

### Phase 3 — Staging + capabilities (6–10 weeks)

- [ ] Explicit stage boundaries in compiler driver
- [ ] Capability checks for emit/fs/proc
- [ ] `@comp.budget` or compile flags for limits

### Phase 4 — Agent transactions (8–14 weeks)

- [ ] MCP patch propose/validate/commit
- [ ] Generation counter + rollback
- [ ] Coordination buffer links patches to gap IDs

### Phase 5 — Tier B features (ongoing)

- [ ] B6 saturation, B7 foreign adapters, … as graph + engine mature

---

## 10. Agent protocol (mandatory)

### Session start

1. Read `AGENTS.md`, `.agents/AGENT_COORDINATION.md`, **this file**.
2. Claim work via coordination buffer.
3. If adding/changing `@comp.*` or comptime hooks → check Phase 0 checklist below.

### Before merging metaprogramming changes

- [ ] Registered in transform engine (or issue filed with gap ID)
- [ ] Parity tests: top-level + nested callback + block body
- [ ] No new `lua_Value` on typed/comptime path (`duo_audit_native_boxing` if available)
- [ ] `zig build bench` if codegen touched; entry in `docs/performance.md`
- [ ] Capability implications documented if emit/fs/proc

### What NOT to do

- Add a new combinator with its own fold path only
- Swallow transform errors (`catch { continue }` → empty output) without structured diagnostic
- Split parser semantics (expression vs directive) for the same `@comp.*` name
- Sacrifice benchmark gate for architectural purity — **bridge incrementally**

---

## 11. Preserving performance, ergonomics, Lua superset

| Concern | Strategy |
| --- | --- |
| **Performance** | Graph/incremental is opt-in phases; hot path stays native scalar; transforms prove native lowering in contract |
| **Ergonomics** | No new ceremony for authors; `@comp.*` syntax unchanged; better errors |
| **Lua superset** | Dynamic paths untouched; graph nodes marked `dynamic` vs `native`; sema preserves Lua semantics |
| **Exponential MP** | Combinators stay; engine makes them composable and testable |
| **Aha moments** | Discoverability via `@comp.catalog` / ladder — fed from registry, not hand-maintained lists |

---

## 12. Success metrics

| Metric | Target |
| --- | --- |
| Combinator parity tests | 100% of Tier-1 combinators pass 3-site harness |
| G-class meta bugs | Downward trend; root-caused to engine/parse split |
| Bench gate | Continuous PASS |
| Agent-smoke | Continuous PASS |
| Silent empty fold | Zero (structured errors only) |
| Graph dump | Available for any module by Phase 1 |
| MCP patch workflow | Propose/validate for ≥1 transform by Phase 4 |

---

## 13. Cross-references

- **`docs/AGENT_ALIGNMENT.md`** — 2-min agent compass (read first)
- `AGENTS.md` — non-negotiables and syntax conventions
- `docs/metaprogramming.md` — user-facing `@comp.*` catalog
- `docs/DIRECTIVE_HIERARCHY.md` — dotted path naming
- `docs/performance.md` — benchmark ledger
- `docs/agent_hooks.md` — end-user agent API
- `.agents/AGENT_COORDINATION.md` — claims, gaps, session log
- `docs/ai_ml_native.md` — ML/device/autodiff (Tier B integration)

---

## 14. Open decisions (resolve in Phase 0–1)

1. Sidecar format: JSON vs binary vs SQLite for graph persistence
2. Whether `@stage(2)` is ever user-visible or compiler-internal only
3. Default agent capability bundle for duo-mcp tools
4. Merge strategy when text edit and graph patch disagree

Record decisions in this file (dated subsection) when resolved.

---

## Decision log

### 2026-08-04 — Plan adopted; Phase 0 started

- **Canonical doc:** `docs/semantic_universe.md` (Tier A/B priorities, phased roadmap, agent protocol).
- **Coordination:** `AGENTS.md`, `.agents/AGENT_COORDINATION.md`, `.agents/AGENT_CANONICAL.md` updated.
- **Code stub:** `src/transform_engine.zig` — descriptor catalog, parity tier-1 list, provenance log stub.
- **Gap:** G-061 tracks remaining Phase 0 deliverables.
- **Preserved:** Performance gate, Lua superset, native lowering, `@comp.*` syntax — semantics unified behind engine over time.
