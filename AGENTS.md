# Agent Instructions

## Duo Language Conventions

When writing `.duo` files, follow these conventions:

### File-as-M Pattern
- Every module file IS its own `M`. Treat the file scope as `M` — no need for `local M = {}` / `return M` boilerplate. Functions and values declared at file scope are module exports. Use an explicit `M = {}` table only when you need to rename exports or selectively expose a subset.

### Syntax
- **`fun` over `function`** — always use `fun` for function declarations.
- **`req` over `require`** — use `req` for all module imports. When importing from stdlib, use the `std` global: `local s = req("std.string")`. When importing user modules, use `req("module.path")`.
- **Omit `do`** where the parser allows it — e.g. `while cond ... end`, `if cond ... end`, `for ... end` without trailing `do`.
- **`end` closes all blocks** — use `end` for `fun`, `if`, `while`, `for`, `match`, `enum`, etc.

### Style
- Prefer implicit returns (tail expressions) over explicit `return`.
- Use `local` for all non-global bindings.
- Minimize new syntax over Lua — Duo adds `fun`, `req`, typed params, enums, match, concepts. Do not invent new keywords or syntax unless there is a clear ergonomic or performance win.
- Favor fewer characters where possible without sacrificing clarity.
- Prioritize ergonomics, no performance regressions, highest metaprogramming power, and low-level control.

### Compiler Hints (Lua files only)
- Compiler hints like `--- @inline`, `--- @cold`, `--- @unroll` are supported only in `.lua` files as an extra feature. Do not use them in `.duo` files.

### Type Annotations
- Add `i64`, `str`, `float`, `bool` type annotations on parameters and return types when performance matters. The codegen inserts native C casts for these, generating faster code.
- **Codegen limitation**: typed params only work reliably for external API calls (through `__lua` wrappers) and same-module calls where the sema has tracked the argument's type. Same-module calls with untyped table field access or local variables may not get casts inserted — use `any` for params that receive such values.

### Naming
- Module files: `lib/std/<name>.duo` — short, lowercase, no underscores.
- Functions: `snake_case` — e.g. `do_retry`, `circuit_new`, `config_get`.
- Internal helpers: prefix with the module name — e.g. `std_retry_sleep`, `dt_pad2`, `dt_is_leap_year`.
- Avoid C reserved words as parameter names (e.g. `default`).

### Module Structure
- Register every stdlib module in `lib/std.duo` with a `std.<name> = req "std.<name>"` line.
- Group related modules hierarchically: `std.net.retry` (network retry), `std.collections.cache` (data structures), `std.time.timer` (timing), etc.
- Export via `M = {}` / `M` at file end when renaming exports or exposing a subset.

## Performance Work

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.
