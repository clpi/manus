# Duo Architecture — 6-Pass Summary

> One-page reference. See individual pass docs for details.

## The Ladder

```
Lua semantics → observed → inferred → guarded → stable → sealed → native → target-specific
```

Every feature strengthens this specialization ladder. Nothing bypasses it.

## Pass 1 — Identity

Duo is Lua with progressively stronger compiler knowledge.

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

## Current Proven Capabilities

```
duo run file.duo                          # Compile + run via C backend
duo compile file.duo --target native-asm  # Pure arm64 (no C, no runtime)
duo compile file.duo --target native-exe  # Linked executable (no C)
duo graph file.duo                        # Semantic graph JSON
duo sim file.duo                          # SIM v0 export
duo fmt --canonical file.duo              # Strip deprecated keywords
duo algebra                               # Convergence catalog JSON
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
