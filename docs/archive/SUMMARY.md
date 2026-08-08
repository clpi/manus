# Duo Architecture — 6-Pass Summary

> One-page reference. See individual pass docs for details.

## The Ladder

```
Lua semantics → observed → inferred → guarded → stable → sealed → native → target-specific
```

Every feature strengthens this specialization ladder. Nothing bypasses it.

## Pass 1 — Identity

Duo is Lua with progressively stronger compiler knowledge.

- Plan: `docs/plans/pass1_identity.md`
- Catalog: `duo catalog` → `pass1`
- Owners: `src/pass1_catalog.zig`, `src/semantic_graph.zig`, `src/transform_engine.zig`

## Pass 2 — Convergence (8 Algebras)

Collapse ~15 mechanisms into 8 orthogonal algebras over one Knowledge Lattice:

1. **Knowledge Lattice** — unknown → observed → guarded → stable → frozen → comptime → native
2. **Descriptor Algebra** — types + concepts + derive + enums + modules via `+`/`-`/`∩`
3. **Shape Algebra** — seal, open, merge, project, freeze, specialize, lift, lower
4. **Call Algebra** — calls as semantic objects; inline/specialize/memo as transforms
5. **Transformation Registry** — all rewrites are graph→graph + contract + provenance
6. **Stage Polymorphism** — parse → compile → link → runtime → gpu
7. **Pipeline Graph IR** — `:map(:filter(:fold))` as optimization graph
8. **Effect Algebra** — composable effect descriptors

## Pass 3 — Grammar & Directives

- 53 keywords → target 30 (23 retirement candidates)
- `@{}` descriptor syntax retires `enum`/`concept`/`alias`/`extends`
- `.name` projections, `:method` references, `..spread`, optional separators
- 3-tier directive model: top-level / short alias / `@comp.*` namespaced
- `duo fmt --canonical` strips deprecated keywords

## Pass 4 — Native Compilation

- Native backend: arm64 macOS, int/float/branch/loop/call/string
- **Milestone proven:** `distance2(p: Point): f64` → 5 arm64 instructions, zero boxing
- Knowledge Lattice gates emission: module-level + per-function + per-call
- 10 native barriers cataloged (9 remaining)
- `duo sim` exports SIM v0 JSON

## Pass 5 — Semantic Interchange

- SIM v0 schema (versioned semantic boundary)
- `duo sim` command works (entities with IDs, origins, contracts)
- C import foundation: `@c.import` registered, `c_frontend.zig` + `sim.zig` building
- `abi.specialize` shared transformation in progress
- 27 MCP tools available

## Pass 6 — Reconciliation

- **#1 risk:** codegen.zig is 28K lines with 3 parallel meta-dispatch paths
- **#1 refactor:** unify dispatch → `meta_dispatch.zig` (table created, 32 combinators)
- SIM should derive from semantic_graph (not parallel queries)
- Knowledge lattice + transform engine + semantic algebra are the strongest parts
- True dependency order: codegen split → meta unification → SIM projection → expansion

## Pass 7 — AI-Native Compilation

- `duo explain`, knowledge snapshots, optimization outcomes, assumption guards
- Export: `duo catalog` → `pass7` JSON

## Pass 8 — Persistent Semantic Computing

- Realization variables, persistent evidence cache, invalidation, `duo realize`
- Export: `duo catalog` → `pass8` JSON

## Pass 9 — Ward Readiness (vertical proof)

- **Mission:** Duo-native Wasm runtime (Ward) faster/smaller than Wart via semantic density
- Matrix owner: `src/ward_readiness.zig`; catalog: `duo catalog` → `pass9`
- **P9-M1 (open):** descriptor-generated LEB128 + instruction decoder
- **Blocker:** Ward hot path still `@c.emit` + `lua_Value` in `module.duo`

## Pass 10 — Public Repository Readiness

- **Mission:** Repository suitable for immediate public inspection without private agent history
- Matrix owner: `src/pass10_repo_audit.zig`; catalog: `duo catalog` → `pass10`
- **Release invariants:** 3.14–3.21 (public readiness, no pollution, permanent roles, density)
- **Audits A15–A19:** quality, file necessity, markdown compression, source/comments, safety
- **P10-M0 partial:** initial pollution audit (15+ findings, 6 canonical docs missing)
- **High blockers:** duplicate pass plans, untracked pass9 smokes, flat `src/` hierarchy

## Pass 11 — Canonical Compiler Closure

- **Mission:** Honest release architecture — explicit backends, no silent fallback, trustworthy benchmarks
- Plan: `docs/plans/pass11_release_proof.md`; catalog: `duo catalog` → `pass11`
- **Profile A (default):** `--backend=c` (generated C → Clang)
- **Profile B (experimental):** `--backend=direct` (ARM64 Mach-O subset)
- **WP-01 partial:** `bench_mode` no longer forces boxing; `--bench-backend` + manifest
- **WP-02 partial:** `backend_identity.zig`, DNB codes, `--backend` flag
- **WP-10 partial:** `semantic_ownership.zig` module classifications

## Pass 12 — Semantic Autonomy & Proof-Carrying Development

- **Mission:** AI proposes; Duo proves — one semantic source drives many validated artifacts
- Plan: `docs/plans/pass12_semantic_autonomy.md`; catalog: `duo catalog | jq '.pass12'`
- **P12-WS2 partial:** intent/obligation schema in `src/proof_carrying.zig`
- **P12-WS3 partial:** `transform_engine.buildTransformProofRecord` + proof log on `logProvenance`
- **P12-WS4 partial:** `realization.compareCandidates` for bounded selection
- **P12-WS10 partial:** `seed_capabilities` + `effectiveClaimStatus` claim dependency graph
- **P12-WS11 partial:** `src/semantic_compression.zig` M1 baseline metrics
- **P12-M1 partial:** `src/token_semantic.zig` → `lexer.zig` keyword lookup integrated
- **P12-M2 partial:** Ward dispatch via `wasm_semantic_gen.zig`

## Pass 13 — Development Control Plane

- **Mission:** One deterministic, inspectable development control plane so humans and concurrent agents operate on canonical truth
- Plan: `docs/plans/pass13_development_control_plane.md`; catalog: `duo catalog` → `pass13`
- `duo dev snapshot|audit|context|summary|claim|session|validate|coordination`
- Canonical owners: `src/dev_control_plane.zig`, `src/pass13_dev_audit.zig`, `src/presentation_record.zig`
- **Open:** claim-lease MCP wire, `.duo/dev/` persistence, coordination migration (P13-WS18)

## Pass 14 — Constructive Evolution, Sovereignty, Universal Performance, Living Compiler

- **Mission:** The permanent development philosophy — reconcile before replacing, preserve before deleting, own essential capabilities, perform across all architectures, stay current, shrink over time
- Plan: `docs/plans/pass14_constructive_evolution.md`; catalog: `duo catalog` → `pass14`
- `duo dev preserve` inventories stash / dirty work / valuable untracked / unique branches / prunable worktrees (Milestone 1)
- Canonical owners: `src/git_preservation.zig` (Audit 1), `src/salvage_registry.zig` (Audit 2, seeded with real findings), `src/pass14_constructive_audit.zig` (14 audits), `src/pass14_catalog.zig`
- **Delivered:** M1 (preservation report) + M2 (salvage registry with real drift findings: stale pass-name stubs still referenced by AGENTS.md, prunable worktrees, unmerged branch, untracked agent state)
- **Process pass** over Pass 13's control plane — governs how work is preserved, reconciled, and removed, not coordination state itself

## Pass 24 — Unified Calls, Lua Superset, Execution-Graph Concurrency

- **Mission:** One design constitution reconciling call semantics (value vs invoke), permanent Lua 5.5 superset contract, shell boundaries, structured concurrency, automatic parallelism, streams, scheduling, hardware realization, and tooling
- **Authority:** `docs/plans/pass24_execution_concurrency_lua_supremacy.md`; index: `docs/plans/lua_superset_concurrency_supremacy.md`
- **Catalog:** `duo catalog` → `pass24`; owners: `src/pass24_catalog.zig`, `src/lua_superset_catalog.zig`, `src/pass24_gate.zig`
- **Non-negotiable:** `a` is a value; `a()` / `a x` invoke; `[[` is Lua long-string; bare auto-call rejected
- **P0 partial:** long-bracket gates, keyword compatibility (`then`/`do`/`local`), syntax classification
- **P2 partial:** call-model parse proofs (`src/pass24_call_model.zig`); `InvocationForm` on AST + `CallShape`; semantic graph lift proofs
- **P3 partial:** execution graph schema stub (`src/pass24_execution_model.zig`)
- **P2–P9 open:** execution graph, `@spawn`/`@all`/`@race`/`@parallel`, channel elimination, determinism, Ward/Go benchmarks
- **Validate:** `zig build pass24-gate` (alias `lua-superset-gate`)

## Pass 25 — Native Semantic Unification, Lifetimes, Bidirectional Meta, Descriptor Reconciliation

- **Mission:** One coherent model for descriptor construction (ordinary calls, no type parameters), inferred lifetimes/provenance, views/ownership/pointers, consumption-driven return realization, and bidirectional metaprogramming via semantic transactions — without fragmenting the language
- **Authority:** `docs/plans/pass25_native_semantic_unification.md`; index: `docs/plans/pass25_semantic_unification_index.md`
- **Catalog:** `duo catalog` → `pass25`; owners: `src/pass25_catalog.zig`, `src/pass25_gate.zig`, schema stubs in `pass25_semantic_category.zig`, `pass25_lifetime_model.zig`, `pass25_projection_model.zig`
- **Builds on:** Pass 23 (metaprotocols, return consumption), Pass 24 (views + `@all` disjointness), Pass 22 (semantic graph), Pass 20 (provenance harness)
- **Non-negotiable:** descriptors are ordinary values; no canonical bracket/angle generics; lifetimes are provenance not syntax; views not borrow syntax; reverse meta returns transactions
- **M0 partial:** constitution, rejected-syntax registry, five semantic categories schema, bidirectional levels 0–3, Pass 23 `@return` alignment, **tail-demand model** (`pass25_tail_result_model.zig`; **P23-D01 superseded**)
- **M1–M3 open:** tail-demand in sema/graph (loop/branch phi, ambiguity diagnostics), specialization by call knowledge, lifetime diagnostics, projection relationships, LSP/MCP transaction preview
- **Validate:** `zig build pass25-gate` (alias `semantic-unification-gate`)

## Pass 26 — Foundational Closure (52 Seams + Two Unifiers)

- **Mission:** Close foundational seams before adding capabilities — one canonical semantic rule per boundary
- **Authority:** `docs/plans/pass26_foundational_semantic_closure.md`; index: `docs/plans/pass26_closure_index.md`
- **Unifiers:** (1) semantic boundaries as first-class values; (2) semantic domains (nine kinds)
- **Original five foundations (F1–F5):** operation IDs, protocol attachment, descriptor identity, boundaries, decision registry
- **Extended Part II:** 30 additional seams (init, recursion, mutability, dynamic/GC, hashing, evidence, ABI, resources, …)
- **Top-ten closure priorities:** descriptor identity+recursion → dynamic → init/mutability → GC → ops/protocols → domains/boundaries → stage/meta → evidence → ABI → resource/unwind
- **M0 partial:** constitution + 13 schema modules + 52 workstreams + 28 gates
- **M1 open:** wire top-ten into sema/graph; flagship C→Duo→Rust vertical proof (P26-G20)
- **Validate:** `zig build pass26-gate` (alias `foundational-closure-gate`)

## Pass 27 — Proof Bundle & Honest Performance Evidence

- **Mission:** Charter-grade proof bundles for every performance/metaprogramming claim
- **Authority:** `docs/plans/pass27_proof_bundle.md`; index: `docs/plans/pass27_proof_index.md`
- **P0 partial:** emission counters, backend×representation×runtime manifest, `.proof.json` on compile/bench, 10×3 matrix schema
- **North star:** P27-PROOF-01 descriptor-generated Ward decoder (performance + metaprogramming)
- **Validate:** `zig build pass27-gate` (alias `proof-bundle-gate`); P0 matrix: `zig build bench-proof-gate`

## Self-Hosting Foundation (Umbrella)

- **Mission:** Language monoculture + graph-native compiler architecture (not a Zig port)
- **Authority:** `docs/plans/self_hosting_foundation.md`
- **Catalog:** `src/foundation_catalog.zig` — bootstrap S0→S3, IR layers IR-01..IR-09, gates F-G01..F-G10
- **M0 partial:** schema gate + ledger anchors; completion requires all F-G01..F-G10 (most open/partial)
- **Validate:** `zig build foundation-gate` (alias `self-hosting-foundation-gate`)

## Current Proven Capabilities

```
duo run file.duo                          # Compile + run via C backend
duo compile file.duo --target native-asm  # Pure arm64 (no C, no runtime)
duo compile file.duo --target native-exe  # Linked executable (no C)
duo graph file.duo                        # Semantic graph JSON
duo sim file.duo                          # SIM v0 export
duo fmt --canonical file.duo              # Strip deprecated keywords
duo catalog                               # Pass 3–12 tracking JSON
duo explain file.duo                      # Knowledge + outcomes + realizations
duo realize file.duo                      # Realization plan + persistent cache
```

## File Map

| Lines | File | Role |
| --- | --- | --- |
| 27,975 | codegen.zig | C code generation (needs split) |
| 9,116 | sema.zig | Type checking + semantic analysis |
| 6,144 | parser.zig | Grammar + AST construction |
| 3,657 | meta_codegen.zig | Combinator hook implementations |
| 2,779 | main.zig | CLI orchestration |
| 2,140 | native_backend.zig | arm64 Mach-O emission |
| 1,855 | types.zig | Type system |
| 1,760 | meta_module.zig | Directive registry |
| 1,634 | comptime.zig | Compile-time evaluator |
| 1,492 | semantic_graph.zig | Persistent semantic entities |
| 1,224 | semantic_algebra.zig | Knowledge lattice + convergence types |
| 668 | transform_engine.zig | Transform contracts + provenance |
| 454 | sim.zig | SIM v0 export |
| 136 | meta_dispatch.zig | Unified combinator table |
