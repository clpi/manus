# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Duo is a Lua-like language with an **ahead-of-time compiler written in Zig**. It does
not interpret or JIT: it lowers source to **C**, then shells out to `clang` (or `zig cc`
for WASM) to produce a native binary. There is no runtime VM — `src/runtime/` is an empty
placeholder. Accepts two source dialects:

- `.lua` — Lua 5.5 compatible, untyped.
- `.duo` — extended syntax with optional static type annotations. The compiler infers and
  checks types; annotated functions generate monomorphic C with no dynamic dispatch.

The standard library (`lib/std/*.duo`) is itself written in Duo.

## Build & run

Requires **Zig 0.17.0-dev** (nightly; exact build pinned in CI). `clang` must be on `$PATH`
at runtime — it is invoked to compile the generated C.

```bash
zig build                      # build compiler → zig-out/bin/duo
zig build run -- <cmd> <file>  # run compiler without installing
```

CLI (`duo <cmd>`): `compile`, `run`, `check` (type-check only), `dump-c` (print generated C),
`build`, `init`, `fmt` (format), `completion`. WASM: `duo compile f.lua --target wasm32-wasi -o f.wasm`
(uses `zig cc`, emits a WASI module exporting `main`).

## Tests

```bash
zig build test         # unit tests + compile-fail tests (the full gate)
zig build unit-test    # Zig in-module test blocks only
zig test src/tests.zig --test-filter "<name>"   # a single unit test
```

- **Unit tests** are co-located `test {}` blocks, aggregated by importing every module in
  `src/tests.zig`. Add new modules there or their tests won't run.
- **Compile-fail tests** live in `examples/compile_fail/*.lua`; each must produce a specific
  error. Run via `scripts/run_compile_fail_tests.sh`.
- **Benchmark gate** (`zig build bench`): compiles `examples/benchmark.lua` and reference
  `examples/benchmark_c.c`, verifies all 40 `RESULT <id> <value>` lines match, then requires
  **Duo to beat or tie C wall-time on every benchmark** (1% slack). This is a hard CI gate —
  a change that regresses codegen performance will fail it. `examples/benchmark.duo` mirrors
  the `.lua` driver and must be kept in sync.
- `zig build cross-bench` additionally needs `lua` (≥5.4) and `luajit` on `$PATH`.

## Compiler pipeline

`Source → lexer → parser → AST → sema → (mono / arc / async_lower) → codegen → C → clang`

| File | Role |
|------|------|
| `src/main.zig` | CLI entry, arg parsing, orchestration; invokes clang/zig cc |
| `src/lexer.zig` | Tokenizer for both Lua and Duo keywords/operators |
| `src/parser.zig` | Recursive-descent parser → AST (`src/ast.zig`) |
| `src/types.zig` | Type system definitions |
| `src/sema.zig` | Semantic analysis, type inference & checking |
| `src/mono.zig` | Monomorphizes generic functions (one specialization per type-arg tuple) |
| `src/arc.zig` | Static pass deciding `duo_retain`/`release`/`close` + cycle-collector registration for heap types (strings, tables, closures) |
| `src/async_lower.zig` | Lowers `async`/`await` into stackless state machines for codegen |
| `src/codegen.zig` | Emits C from the typed AST — by far the largest module (~10k lines); most codegen work happens here |
| `src/pretty.zig` | AST pretty-printer |

`src/property_tests.zig` holds property-based tests. `src/types.zig.orig` is a stale merge
leftover — ignore it.

Codegen relies on constant folding + dead-code elimination: some benchmarks report `0.000000s`
because the compiler proves the result is unused in the timed path and eliminates it. Keep
this in mind when a benchmark's output looks suspiciously fast — verify correctness via the
`RESULT` lines, not timing alone.

## Editor tooling

`ext/` contains a tree-sitter grammar, LSP, and VS Code / Zed / Helix / Vim plugins for Duo.

## Conventions

- `snake_case` for both functions and types, following Zig stdlib style (`parse_module`,
  `emit_module`, `TokenKind`).
- Single-file modules; public API via `pub`.
- Errors use Zig error unions; the CLI exits via `std.process.exit(1)` on failure.

## Roadmap & Future Work

To achieve the best performance and feature set, future milestones include:
- **NaN-boxing** for `lua_Value` to keep dynamic types lightweight (64-bit).
- **String interning** for fast pointer-based equality and hashing.
- Integrating high-performance custom allocators (e.g. `mimalloc`).
- Implementing **LTO & PGO** for final binary emission via clang.
- Guaranteeing **SIMD auto-vectorization** for generated numeric array loops.
- Adding true multithreading/concurrency support (e.g. worker threads).
- Expanding the standard library and providing built-in tooling like `duo fmt`.
