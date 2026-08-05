# Duo Compiler Architecture

**Status:** Supported overview. **Audience:** compiler engineers and contributors.

Duo is an ahead-of-time compiler written in **Zig**. It does not interpret or JIT: source lowers to **C** (default), then `clang` or `zig cc` produces the binary. There is no runtime VM.

## Pipeline

```
Source → lexer → parser → AST → sema → (mono / arc / async_lower) → codegen → C → clang
```

| Stage | Module | Responsibility |
| --- | --- | --- |
| Lex / parse | `src/lexer.zig`, `src/parser.zig`, `src/ast.zig` | Lua + Duo syntax → AST |
| Types / sema | `src/types.zig`, `src/sema.zig` | Inference, checking, `@comp.*` hooks |
| Monomorphization | `src/mono.zig` | Generic specialization |
| Memory / async | `src/arc.zig`, `src/async_lower.zig` | Retain/release; async state machines |
| Codegen | `src/codegen.zig` | Typed AST → C (largest module) |
| Metaprogramming | `src/comptime.zig`, `src/meta_module.zig`, `src/meta_codegen.zig` | `@comp.*` transforms |
| Semantic graph | `src/semantic_graph.zig`, `src/transform_engine.zig` | Unified transform + graph lift (in progress) |
| Realization | `src/realization.zig`, `src/persistent_semantic_state.zig` | Representation selection + cache (Pass 8) |
| Native backend | `src/native_backend.zig` | Direct machine code (subset) |
| CLI | `src/main.zig` | `compile`, `run`, `check`, `catalog`, `explain`, `realize` |

## Build and test

```bash
zig build                          # compiler → zig-out/bin/duo
zig build test                     # unit + compile-fail + bench gate
zig build unit-test                # Zig test blocks only
zig test src/tests.zig --test-filter "<name>"
```

Performance gate: `zig build bench` — Duo must beat or tie C on all 40 benchmarks. Ledger: [docs/performance.md](performance.md).

## Tooling exports

```bash
duo catalog    # JSON: passes, transforms, Ward/readiness matrices
duo explain    # Knowledge snapshots + optimization outcomes
duo graph      # Semantic graph lift (partial)
duo realize    # Realization + persistent evidence (partial)
```

## Dialects

- **`.lua`** — Lua 5.5 compatible, untyped; hints via `--- @directive` comments.
- **`.duo`** — Types, `@comp.*`, bare functions, if-expressions, `req` imports.

## Self-hosting / bootstrap

The compiler is **Zig**, not self-hosted yet. The standard library (`lib/std/*.duo`) is Duo source compiled by `duo`. See [docs/bootstrap.md](bootstrap.md).

## Further reading

- CLI details: [docs/src/compiler_usage.md](src/compiler_usage.md)
- Contributor entry: [CLAUDE.md](../CLAUDE.md)
- Long-range architecture: [docs/plans/semantic_graph_architecture.md](plans/semantic_graph_architecture.md) (**Planned / internal** — not all items implemented)
- Historical pass plans: [docs/plans/archive/](plans/archive/) — **Historical** only
