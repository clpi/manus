# Historical RFC: The Semantic Graph as Multi-Language Substrate

**Author:** opencode (big-pickle) · **Date:** 2026-08-08
**Status:** dated design record — not law, current status, or implementation guidance
**Current law:** `docs/spec/constitution.md`
**Owner files:** `src/semantic_graph.zig` · `src/duo_native_ir.zig` · `src/dnir_lower.zig`

This file preserves the evidence and reasoning available on its date. Git and
the current production tree decide what remains implemented. It must not train
new architecture or compete with the constitution.

## 1. Thesis

Duo's long-term shape — a compact language over a persistent semantic program
model where humans, compilers, libraries, and agents manipulate the same graph —
requires one architectural decision that the current tree does not yet make:

> **The semantic graph is the substrate. DNIR is its linearization, emitted only
> at the backend boundary.**

Today the opposite relationship is implied: `semantic_graph.zig` is a read-only,
advisory sidecar lifted from the AST, and DNIR is the IR that codegen actually
consumes. That is fine as a *phase* — and this RFC does not ask to rework the
native backend — but every new capability (multi-language interop, exponential
transform auditability, graph visualization, agent transactions) becomes easier
in the graph and impossible in a flat instruction arena. This RFC fixes the
direction of the dependency without disturbing the performance gate.

## 2. Current state (grounded in the tree, 2026-08-08)

### 2.1 The graph is advisory

`src/semantic_graph.zig` (2173 lines) builds a node/edge graph from `ast.Module`:

- `NodeId = { index: u32 }` — arena index, session-scoped (`:17`)
- `StableId = { hash: u64 }` — content-addressed via **wyhash** of
  `(module_path, kind, stable_path, generation)` (`:28`). Note: the design doc
  promises SHA-256; the code uses wyhash. See §8 Open Questions.
- `NodeKind`: `module, source_file, func, param, local, type_node, call,
  directive, concept, transform_app, comptime_value, emit_artifact, table_shape,
  enum_shape, pipeline` (`:48`)
- `EdgeKind`: `contains, def, use, type_of, transform_input, transform_output,
  provenance` (`:69`)
- Lifters: `liftModule`, `liftAliasShapes`, `liftEnumShapes`, `liftFunctionBindings`,
  `liftCalls`, `liftModuleWithCalls`, `liftModuleFull` (`:483–990`)
- Query side: `id_index` keyed on `StableId.hash`, `findById`, `stablePath` (scope
  chain walk, `:228`)
- Export: `writeJson` (`:1292`), `duo graph <file>` → JSON sidecar

Properties that matter:

1. **Scope as a fact.** `Node.scope` records the binding chain, and `stablePath`
   hashes it, so `scale.n` and module `n` are distinct identities. `nameAddressable`
   (`:213`) separates named bindings from occurrences (`call`, `local`, etc.),
   which disambiguates by `@line:col`. This is real identity work — it must be
   preserved, not re-done.
2. **Codegen reads the graph for emit order, not structure.** Header says "no
   behavior change to codegen until Phase 2 wiring." The one consumer is
   `moduleFunctionEmitOrder` (in `semantic_graph.zig`) for callee-before-caller
   ordering, plus Pass 22's `region_graph` projection for transform/validation —
   both metadata/structure reads, not a graph-driven emit path.
3. **Effect edges exist only per-function, transiently.** Pass 22's
   `orders_before` chains cover one function at emit time; the graph has no
   durable, cross-language effect model.

### 2.2 DNIR is a flat per-function instruction arena

`src/duo_native_ir.zig`:

- `Block = { instrs: []const Instr }` — flat array (`:157`)
- `Value` union: `void, i64, f64, str, local:u32, temp:u32, record:u32` (`:119`)
- `Function.graph_stable_id` — the ONLY graph link on DNIR itself, metadata only (`:185`)
- `moduleIsNativeDirectReady` (`:235`) proves no `lua_Value` on the native path

`src/dnir_lower.zig` (183KB) is the main Duo→DNIR lowerer. The real consumer is
`src/native_backend.zig` (ARM64 Mach-O/asm), which imports `dnir` + `dnir_lower`.

### 2.3 A graph over DNIR ALREADY exists: Pass 22 region graph

**`src/region_graph.zig` projects DNIR + semantic-graph identity into a bounded
region graph with a real edge vocabulary — this is most of "graph-backed DNIR"
already built and wired.** The RFC's Phase A must therefore *extend* it, not
reinvent it.

- Edge vocabulary (`CanonicalEdge`): `defines, uses, calls, orders_before,
  realizes_as` (`region_graph.zig:12`) — matches the proposed `.def`/`.use`
  edges plus an effect-ordering edge (`orders_before`).
- **Effect ordering already exists**: `buildModuleRegions` chains `orders_before`
  edges across effect ops (`branch, ret, call, binop, …` via `prev_effect`,
  `region_graph.zig:108–170`). This is the seed of the `.effect` edge model in §4.
- Wired into the native backend: `native_backend.zig:4446–4461` builds regions,
  validates them (strict via `DUO_REGION_GATE`, `region_schedule.zig:30`), attaches
  a `realization` plan, and applies `region_transform.applyModuleRegionTransforms`.
- Support tree: `region_schedule.zig`, `region_layout.zig`, `region_transform.zig`,
  `graph_query.zig` (bounded, memoizable queries for compiler/LSP/MCP — the seed of
  the §7.3 graph REPL), `realization.zig` (Pass 8 freedom/candidate/selection
  machinery). Gate: `pass22_gate.zig`.

**Gap this RFC targets that Pass 22 does not cover:** the region graph is
*per-function, transient, and consumed only by the native backend*. It is not a
persistent, multi-language, content-deduped substrate. The region graph answers
"how does one function's DNIR flow?"; the substrate must answer "what is the
semantic relationship of every value, type, and transform across C/Lua/WASM/Duo,
and why does each node exist?"

### 2.4 C, Lua, WASM integration today

| Path | Files | State |
| --- | --- | --- |
| C import | `c_frontend.zig`, `c_header_parse.zig` → foreign descriptor → `foreign_adapter` | Closest to done; produces typed `ForeignFunc` with `boundary_id` |
| Lua dynamic | `lua_Value`, `native_scalar_mode` split in `codegen.zig` | Native scalar vs Lua thunks chosen per-function; `lua_Value` only on dynamic path |
| WASM | `wasm_dispatch.zig`, `wasm_semantic.zig`, `wasm_semantic_gen.zig`, plus `@comp.embed.wasm` and `tools/wasm/` (WASM runtime consumer) | Three disjoint roles, no Duo→WASM direct backend, no WASM frontend into the graph |
| Transform registry | `src/transform_engine.zig` + `DUO_PROVENANCE=1` | `@comp.match` wired to provenance; other combinators next |

## 3. The core architectural decision

**Keep DNIR linear. Make the graph the substrate. Add a lift/lower boundary.**

Do **not** turn DNIR into a graph. The flat instruction arena is correct for the
native backend: it is what the ARM64 emitter already walks, it matches the
performance gate, and rewriting it risks the single most guarded property of this
repo. Instead:

```
 frontends ──lift──▶ semantic graph (substrate) ──linearize──▶ DNIR ──emit──▶ ARM64 / C / wasm
 (duo, C, lua, wasm)        ▲ transform_engine rewrites                     (backends)
                             └── provenance / budget / contracts
```

The graph is the contract between frontends and backends. Each frontend produces
graph fragments; each backend walks the graph and linearizes only the subgraph it
can express. Interop is **node unification by content ID**, not adapter plumbing.

This preserves the design doc's promise — "no codegen behavior change required
for graph reads" — because reads stay reads until a backend deliberately consumes
a transformed subgraph.

## 4. The substrate node model

### 4.1 Principles

1. **Language origin is metadata, not type.** Every node carries
   `origin: lua | c | wasm | duo` + toolchain version + semantic fingerprint.
   Unification to a substrate type happens when fingerprints are identical; the
   origin stays for provenance/audit.
2. **Lua is one adaptive layer, not the core representation.** The `lua_Value`
   becomes a foreign leaf node (`opaque(origin=lua)`) with guard/conversion edges.
   This is exactly the existing table-shape ladder (dynamic → guarded → sealed →
   native) expressed as graph levels.
3. **Few mechanisms that compose into more behaviors** (Pass 2 principle).
   Everything below is an *edge or a field*, not a new subsystem.

### 4.2 Required upgrades to `Node`/`Edge`

Add to `EdgeKind` (conservative, additive — where possible *adopt* the Pass 22
`region_graph.CanonicalEdge` vocabulary instead of parallel edges):

- `.effect` — memory/state ordering: `read`, `write`, `alloc`, `call`, `io`,
  `atomic`. The missing prerequisite for cross-language fusion and safe
  transactional edits. Without it, C memory + Lua table + WASM linear memory
  cannot be reasoned about in one graph. Pass 22's `orders_before` chains are the
  per-function seed; promote them to durable cross-language edges.
- `.origin` — language/toolchain provenance edge to an origin node.
- `.dedup` — witness edge: this node is structurally shared with another content
  ID (the dedup trace, for debugging exponential expansion).

Add to `Node`:

- `origin: Language` (`duo | c | lua | wasm`) — where the node came from.
- `cost: BudgetClass` already exists in `transform_engine`; carry it onto nodes
  so budget is queryable, not just enforced.

Keep: scope-chain identity, `stablePath`, `nameAddressable` disambiguation. These
are hard-won correctness facts.

### 4.3 Content-dedup = the exponential-enabling mechanism

When `@comp.tower(16)` or `@comp.nfold(4)` stamps out bodies, the graph collapses
common subexpressions by content ID. O(n^k) textual code becomes a DAG of shared
nodes; `BudgetClass` then bounds *unique* nodes, not emitted text. This is what
makes exponential metaprogramming *auditable*: the graph shows the shared skeleton
plus the N delta leaves, instead of N full copies.

Concretely: `addNode` (the single writer, per the comment at `:166`) hashes the
normalized node payload (kind + stable path + origin + shape fingerprint) and
returns the existing node when the ID already exists — a memoid keyed on the
content hash the code already computes.

## 5. C, Lua, WASM as peer boundaries

Unify each integration into a **boundary adapter pair** (import + export) instead
of bespoke paths.

### 5.1 C (closest to done)

Generalize `foreign_adapter.zig` into: C header → **graph fragment** (type nodes
+ param/ret/ABI edges). `@c.export` becomes "mark this node as exportable through
the C boundary" — one mechanism both directions. `@c.import` produces the same
fragment kind as `@c.export` consumes, so round-tripping C↔Duo is identity.

### 5.2 Lua

The `native_scalar_mode` vs `mixed` vs Lua-thunk decision becomes *derived from
the graph*: a function lowers to native C iff every node in its subgraph is
substrate-native; otherwise it is a "dynamic backend" selection. `lua_Value` is a
foreign leaf, not the substrate. The existing per-function decision in
`compute_native_scalar_funcs` stays; it just gets a graph-shaped justification
that agents and `duo explain` can read.

### 5.3 WASM (biggest opportunity)

Today three disjoint features. Converge:

1. **WASM frontend** — `wasm_semantic`/`wasm_decode_*` decodes `.wasm` into graph
   fragments: imports → foreign nodes, functions → subgraphs.
2. **WASM backend** — lower the substrate graph to i32/i64/f32/f64 + linear
   memory + imports/exports. This is also the path to the Pass 9/ward goal.
3. `@comp.embed.wasm` stays a convenience for embedding artifacts.

That completes the C↔Lua↔WASM triangle in one graph: a C function and a WASM
function become interoperable by node unification, and cross-WASM-module linking
is a graph edge.

## 6. Transforms as graph rewrites

`transform_engine.zig` already has the right spine (Contract, parity, BudgetClass,
provenance). Two changes:

1. **Provenance edges live on graph nodes**, not only in the stderr summary.
   Then the graph answers "why does this node exist?" by walking
   `.provenance` edges backward to the directive + input subgraph.
2. **Every transform is a pure graph→graph function** with declared input/output
   subgraph + cost. `@comp.product` emits subgraph G′ = product(G) with edge
   `product#42: G → G′`. Exponential blowup becomes budgetable and auditable
   instead of a codegen event.

This stays inside the existing moratorium (registry + contract + parity + one
dispatch path + native contract). It adds provenance *placement*, not a new
transform path.

## 7. Debugging, exploration, visualization

Exponential workflows produce code no one can read in a text editor. The tooling
is where the "aha" moments live.

1. **Diffs as the primary debug surface.** Nodes are content-addressed and
   `duo graph` JSON export exists. Add `duo graph diff a.json b.json` → which
   nodes a transform added/removed/rewired. This is the metaprogramming
   debugger: you *see* what `@comp.derive` / `@comp.tower` did.
2. **Interactive explorer, not static dumps.** A local graph server (fits the
   WASM/web ambitions) with a canvas UI: search by stable ID, filter by
   `origin`/`kind`, expand/collapse shared subgraphs, follow provenance chains,
   overlay cost/budget. Two views: *semantic* (types/values/transforms) and
   *SSA* (per-function dataflow).
3. **Graph queries through `@comp.*`.** Extend the planned `@comp.type.info`
   graph queries to `graph.query(kind=Type, origin=c)`,
   `graph.walk(provenance=product, depth=2)`. This is the Pass 15 semantic shell.
4. **Replay + commit log.** Persistence as an append-only transaction/commit log
   (not SQLite first): every compile/transform writes a record. Enables
   incremental builds, agent undo, provenance audit, deterministic replay (ties
   into existing `build_determinism`).

## 8. Open questions

1. **wyhash vs SHA-256.** The design doc promises SHA-256; code uses wyhash for
   speed. Recommend: keep wyhash for session identity (it only needs
   collision-resistance within a build), promote to SHA-256 only for *persistent*
   cross-session IDs where adversarial collision matters. Decide explicitly.
2. **Effect edge granularity.** Full memory SSA (every store is a node) is heavy.
   Recommend starting with per-function effect orderings (a happens-before list)
   rather than per-access edges — enough for fusion legality and transactional
   edits, cheap to maintain.
3. **Persistence format.** Log file vs embedded DB. The commit-log approach is
   recommended (§7.4); WAL-backed DB only if query performance demands it.
4. **Provenance depth.** Full transform DAG vs immediate input→output. Recommend
   immediate edges on nodes + a compact per-transform summary record; full DAG
   can be replayed from the commit log.

## 9. Phased roadmap

Each phase preserves the perf gate (no codegen behavior change unless the phase
says so), keeps `git stash` banned, and claims `.agents/session/` before touching
shared files.

### Phase A — Promote the region graph to a durable substrate
- Adopt `region_graph.zig`'s edge vocabulary (`defines/uses/calls/orders_before`)
  as the canonical `.def`/`.use`/`.effect` model rather than inventing a new one.
- Extend it from per-function/transient to durable and cross-language: persist
  regions in the semantic graph with stable IDs, attach `origin`, content-dedup
  shared subgraphs.
- Files: `src/region_graph.zig` (extend), `src/semantic_graph.zig` (durable
  storage of region facts).
- Proof: `zig build bench` unchanged; `zig build unit-test` green; existing
  `pass22_gate` still passes.

### Phase B — Persistence + commit log
- Append-only transaction log; `duo graph` writes a session record.
- Enables incremental builds, agent undo, replay. Prerequisite for Phase E.
- Files: new `src/semantic_graph/log.zig`, `duo graph --log`.

### Phase C — C frontend → graph fragments; WASM backend + frontend
- Generalize `foreign_adapter` into boundary adapters; C imports become graph
  fragments; WASM gets both a decode-frontend and a lower-backend.
- Files: `src/foreign_adapter.zig`, `src/wasm_*.zig`, new
  `src/wasm_backend.zig`.
- Proof: `examples/pass5/c_point_smoke.duo` and a WASM round-trip smoke.

### Phase D — Diff tooling + graph explorer + graph REPL
- `duo graph diff`, local graph server, `@comp.*` graph queries.
- Files: new `tools/graph_viewer/`, `src/semantic_graph/query.zig`.

### Phase E — Transactions + capabilities
- ACID graph transactions; `@comp.capability.consume` enforcement. Depends on
  A+B. Aligns with Tier A priorities 4–5 in `AGENT_ALIGNMENT.md`.

## 10. Anti-patterns (do not)

1. **Native backend reads the graph directly.** Keeps the two-layer split so the
   performance gate never blocks substrate work.
2. **DNIR becomes a graph.** The flat arena is correct for emission.
3. **A fourth transform dispatch path.** Everything routes through
   `transform_engine` per the moratorium.
4. **Another name-keyed index.** The scope-chain identity (`stablePath`) is the
   correctness answer; `id_index` on StableId is the query answer. Do not
   reintroduce name-only lookups (the removed `name_index` collided on scopes).
5. **Persisting wyhash IDs across sessions without the SHA-256 decision.** See §8.

## 11. Relationship to current law and dated implementation evidence

- `docs/spec/constitution.md` — the current graph, demand, realization, identity,
  and provenance law supersedes every architectural authority this RFC once
  claimed.
- `src/region_graph.zig` + `pass22_gate.zig` (Pass 22, §17.2–17.4) — the existing
  bounded graph over DNIR. This RFC's Phase A is an extension of it, not a fresh
  build; `graph_query.zig` is the seed of the §7.3 graph REPL.
- `src/realization.zig` (Pass 8) — freedom/candidate/selection machinery that
  Phase E (transactions + capabilities) should build on.
- `docs/AGENT_ALIGNMENT.md` — Tier A (spine) and Tier B (equality saturation,
  foreign adapters). Phase C maps to Tier B.7.
- `(archived, deleted — git history)` — C/Lua/WASM boundaries. Phase C
  is the graph-flavored continuation.
- `(archived, deleted — git history)` — Phase B (commit log)
  and Phase E (transactions) are its graph mechanism.
- `(archived, deleted — git history)` — Phase D (graph REPL).
- the region graph passes this RFC extends (archived, deleted — git history).
