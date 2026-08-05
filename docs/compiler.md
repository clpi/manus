# Duo compiler architecture

**Status:** current (internal). Canonical plan: [semantic graph architecture](plans/semantic_graph_architecture.md).

## What Duo is

Duo is an ahead-of-time compiler (Zig) that lowers `.duo` / `.lua` source to C (default), then invokes `clang` or `zig cc` for native binaries. There is no runtime VM.

## Pipeline

```
Source → lexer → parser → AST → sema → (mono / arc / async_lower) → codegen → C → clang
```

| Module | Responsibility |
| --- | --- |
| `src/lexer.zig` | Tokenization (Lua + Duo) |
| `src/parser.zig` | Recursive-descent parse → `src/ast.zig` |
| `src/types.zig` | Type definitions |
| `src/sema.zig` | Type inference and checking |
| `src/mono.zig` | Generic monomorphization |
| `src/arc.zig` | Retain/release for heap types |
| `src/async_lower.zig` | Async/await state machines |
| `src/codegen.zig` | C emission (largest module) |
| `src/comptime.zig` | Compile-time evaluation |
| `src/meta_module.zig` | `@comp.*` directive registry |
| `src/transform_engine.zig` | Unified transform registry (Phase 0–1) |
| `src/semantic_graph.zig` | Semantic graph spine |

## Metaprogramming

All compile-time operations use `@comp.*` (aliases: `@compiler.*`, `@meta.*`). Registry: `duo catalog`.

## Self-hosting / bootstrap

1. Build compiler: `zig build` → `zig-out/bin/duo`
2. Stdlib is Duo source under `lib/std/*.duo`, embedded at compile time
3. Compiler is Zig; Duo does not yet compile itself — bootstrap is Zig → duo binary → user programs

## Validation

```bash
zig build test          # full gate
zig build unit-test     # Zig tests only
zig build bench         # 40-benchmark perf gate vs hand-written C
duo catalog             # machine-readable pass/milestone JSON
```

## Experimental

- Semantic graph / realization (`duo graph`, `duo realize`, `duo explain`)
- Pass 9 Wasm descriptor pipeline (`src/wasm_semantic.zig`, `duo wasm-tables emit`)
- Native backend / direct object emission (`src/native_backend.zig`) — partial

## Further reading

- [Compiler usage (CLI)](src/compiler_usage.md)
- [Performance ledger](performance.md)
- [Semantic universe](semantic_universe.md)
- [Agent alignment compass](AGENT_ALIGNMENT.md) — contributor/internal
