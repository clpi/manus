# Agent Instructions

## Core Design Targets (ALL agents MUST acknowledge and follow)

### 1. The Aha Moment Target
Every feature must create "discoverability moments" — the feeling when Zig's comptime made generics click, when Rust's traits made metaprogramming extensible. Duo features should compose intuitively so developers have revelations about what's possible. Features should be discoverable through common-sense semantics and produce outsized results from minimal input.

### 2. Metaprogramming Framework (More Capable Than Jai/Rust/Zig)
- `@` is the SINGLE prefix for ALL compile-time operations in .duo files
- `@(expr)` = compile-time evaluation
- `@inline`, `@hot`, `@raw`, `@packed` = compiler directives
- `@derive(...)`, `@ffi(...)` = type attributes
- `@fields(T)`, `@sizeof(T)` = compile-time introspection
- `@autodiff`, `@device(...)` = compile-time transforms
- In .lua files, `--- @directive` in triple-dash comments provides the same without breaking Lua syntax
- Goal: produce the MOST expansive dynamic and capable output with MINIMAL syntax additions over Lua
- The framework must be MORE logical and capable than Jai's #run, Rust's proc macros, and Zig's comptime

### 3. AI/ML-Native (Better Than Mojo)
- `Tensor[dims, dtype]` compile-time shape checking
- `@device(.auto)` — one function targets CPU/CUDA/Metal/WebGPU/WASM
- `@autodiff` — differentiation as compile-time transform
- Kernel fusion via user-definable rewrite rules
- Sub-millisecond startup, <1MB binary (vs PyTorch's 2GB)
- See `docs/ai_ml_native.md` for full design

### 4. C Interface: `@c.*` Prefix
- `@c.include("header.h")` — include C header (replaces @cinclude)
- `@c.import("header.h")` — parse and import C declarations
- `@c.export("name")` — export function with C ABI
- `@c.type("struct_name")` — reference C type
- `@c.call("func_name", args)` — call C function directly
- `@c.emit("raw C code")` — inject raw C (replaces __emit)

### 5. Performance Guarantee
- Duo MUST beat or tie hand-written C on ALL 40 benchmarks
- Every change MUST be verified against `zig build bench`
- NO performance regressions are acceptable
- Benchmarks must cover: dispatch loops, memory access patterns, SIMD, string ops, table ops, recursion, iteration
- **ALL agents MUST read and update `docs/performance.md`** before and after any performance-affecting change (see *Agent Performance Protocol* in that file)

## Duo Language Conventions

When writing `.duo` files, follow these conventions:

### File-as-M Pattern
- Every module file IS its own `M`. Treat the file scope as `M` — no need for `local M = {}` / `return M` boilerplate. Functions and values declared at file scope are module exports. Use an explicit `M = {}` table only when you need to rename exports or selectively expose a subset.

### Syntax
- **`fun` over `function`** — always use `fun` for function declarations.
- **`req` over `require`** — use `req` for all module imports. When importing from stdlib, use the `std` global: `local s = req("std.string")`. When importing user modules, use `req("module.path")`.
- **Omit `do`** where the parser allows it — e.g. `while cond ... end`, `if cond ... end`, `for ... end` without trailing `do`.
- **Omit `then`** — `then` is deprecated in .duo files.
- **Omit `local`** — in .duo files, all bindings default to local scope.
- **`end` closes all blocks** — use `end` for `fun`, `if`, `while`, `for`, `match`, `enum`, etc.

### Style
- Prefer implicit returns (tail expressions) over explicit `return`.
- Minimize new syntax over Lua — Duo adds `fun`, `req`, typed params, enums, match, concepts. Do not invent new keywords or syntax unless there is a clear ergonomic or performance win.
- Favor fewer characters where possible without sacrificing clarity.
- Prioritize ergonomics, no performance regressions, highest metaprogramming power, and low-level control.
- Use `@` prefix for ALL compile-time and compiler directive operations.
- Use `const` for module-level constants that should fold into typed code.

### Compiler Hints (Lua files only)
- Compiler hints like `--- @inline`, `--- @cold`, `--- @unroll` are supported only in `.lua` files as an extra feature. Do not use them in `.duo` files — in .duo files, `@` is direct syntax, not embedded in comments.

### Type Annotations
- Add `i64`, `str`, `float`, `bool` type annotations on parameters and return types when performance matters. The codegen inserts native C casts for these, generating faster code.

### The @c.* Interface
- `@c.include("header.h")` for C headers
- `@c.emit("code")` for raw C injection
- `@ffi("name")` on functions for external C linkage
- `@c.export("name")` for exported symbols

### Naming
- Module files: `lib/std/<name>.duo` — short, lowercase, no underscores.
- Functions: `snake_case` — e.g. `do_retry`, `circuit_new`, `config_get`.
- Internal helpers: prefix with the module name — e.g. `std_retry_sleep`, `dt_pad2`, `dt_is_leap_year`.
- Avoid C reserved words as parameter names (e.g. `default`).

### Module Structure
- Register every stdlib module in `lib/std.duo` with a `std.<name> = req "std.<name>"` line.
- Group related modules hierarchically: `std.net.retry` (network retry), `std.collections.cache` (data structures), `std.time.timer` (timing), etc.
- Export via `M = {}` / `M` at file end when renaming exports or exposing a subset.

## Syntax Semantics (canonical — keep compiler, stdlib, and docs aligned)

| Rule | `.duo` behavior | Implementation status |
| --- | --- | --- |
| **Implicit `local`** | Omit `local` everywhere; bindings are file/module locals unless `global` is explicit | **Fixed** in `src/sema.zig` (2026-07-12): duo module scope no longer uses `require_global`; reads of undeclared names auto-define locals; pre-register assign targets |
| **`@` prefix** | User-facing metaprogramming: `@c.emit`, `@asm`, `@emit`, `@hot`, `@device`, `@(expr)` | Parser desugars `@c.emit`/`@emit`→`__emit`, `@asm`→`__asm`, `@hot_path`→`__hot_path`; `__*` names are **internal** desugar targets only |
| **`_` private prefix** | Top-level `fun _helper()` / `_state = …` are file-private, not module exports | **Codegen**: `add_module_export` skips `name[0]=='_'`; **LSP** (`duo-lsp`): should mirror — open gap if completion lists `_` symbols |
| **`global`** | Only way to create a true module global in `.duo` | Implemented via `global_decl` |
| **String-literal calls** | `print 'hi'`, `req 'std.io'` — call sugar without parens | Parser `parse_suffixed_expr` |
| **Indentation** | Not semantic; blocks close with `end` | Lua-style |

### Agent documentation protocol

1. **Before** performance or codegen work: read `docs/performance.md` (ledger + open gaps).
2. **After** any benchmark-affecting or semantics change: append a dated section to `docs/performance.md` with commands run, files touched, measured ratios, and rejected experiments.
3. **After** syntax/semantic fixes: update this table if status changes.
4. **Hardware / low-level**: prefer `.duo` + `@c.emit` / `@asm` / `@device` in `lib/std/hardware.duo` and `lib/std/ml/device.duo` when Lua grammar blocks optimization; do not add Lua-only benchmark gaming.

### Open gaps (2026-07-12)

- **Sieve**: file-scope NEON popcount (portable SWAR done; ~2.7× vs C, room to improve)
- **Mandelbrot**: correct 4-wide SIMD without RESULT drift (prior unroll reverted)
- **LSP `_` privacy**: export filtering in `duo-lsp` (codegen already filters)
- **Full `@` surface**: `@sizeof` / `@alignof` desugar from `@` (still `__sizeof` internally)
- **GPU CI**: `examples/bench_gpu_metal.duo` + `scripts/run_gpu_benchmark.sh` not in `zig build test`

## Performance Work

**Canonical reference:** `docs/performance.md` — the performance ledger, gap analysis, benchmark inventory, and modification roadmap. Read it at the start of any performance task; append a dated entry after every benchmark-affecting change (including rejected experiments).

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.

