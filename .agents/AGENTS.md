# Agent Instructions

## Core Design Targets (ALL agents MUST acknowledge and follow)

### 1. The Aha Moment Target
Every feature must create "discoverability moments" — the feeling when Zig's comptime made generics click, when Rust's traits made metaprogramming extensible. Duo features should compose intuitively so developers have revelations about what's possible. Features should be discoverable through common-sense semantics and produce outsized results from minimal input.

### 2. Metaprogramming Framework (More Capable Than Jai/Rust/Zig)
- `@` is the SINGLE prefix for ALL compile-time operations in .duo files
- All directives use dotted paths under a compiler meta module; NO underscore patterns in public surface
- **Primary:** `@comp.*` — shortest, canonical compiler module
- **Aliases:** `@compiler.*`, `@meta.*` — both map to same internal targets

**Hierarchy:**
- `@comp.compile.*` — compile-time control (`when`, `loop`, `fold`, `log`, `warn`, `error`, `assert`, `cached`, `thread`, `device`, `autodiff`, `unroll`, `modify`, `profile`, `native`)
- `@comp.embed.*` — file embedding (`str`, `file`, `json`, `wasm`)
- `@comp.bit.*` — bit intrinsics (`popcount`, `ctz`, `clz`, `bswap`, `rotl`, `rotr`, `bitcast`)
- `@comp.hint.*` — optimization hints (`likely`, `unlikely`, `prefetch`, `assume`, `unreachable`, `trap`, `fence`)
- `@comp.type.*` — type introspection (`name`, `id`, `info`, `is`, `as`)
- `@comp.c.*` — C interface (`emit`, `include`, `import`, `export`, `call`, `type`)
- `@comp.agent.*` — agent discoverability hooks (`catalog`, `ladder`, `hooks`)
- `@comp.pipeline` — pipeline family generation
- `@comp.derive` / `@comp.define.derive` — derive macros
- `@comp.foreign` — cross-language transpilation
- `@comp.sql` — SQL DDL to C struct generation
- `@comp.wasm` — embed WASM modules
- `@comp.lua` — compile-time Lua execution
- `@comp.schema` — schema generation
- `@comp.ffi` — FFI generation
- `@comp.codegen` — raw codegen injection
- `@comp.as` — explicit type cast
- `@comp.make.type` — type construction
- `@comp.bitfield` — bitfield type
- `@comp.union` — union type
- `@comp.select` — compile-time select
- `@comp.run` — compile-time execution
- `@comp.constexpr` — constexpr evaluation
- `@comp.catalog` / `@comp.ladder` — self-documentation

**Exponential combinators (O(1) → O(n^k)):**
- `@comp.map` / `@comp.sweep` — O(n) type sweep
- `@comp.match` — O(n) pattern-match codegen (pipe-separated alternatives → N specialized branches)
- `@comp.tabulate` — O(n) compile-time lookup table generator (unrolled loop of codegen; 0..count-1)
- `@comp.interpolate` — O(n) compile-time string interpolation (code template injection with {name} placeholders)
- `@comp.zip` — O(n*m) compile-time cartesian zip (two pipe-separated specs → all pairs)
- `@comp.product` — O(n²) cartesian product
- `@comp.tensor` — O(n³) tensor sweep
- `@comp.nfold` — O(n^k) N-concept sweep
- `@comp.ceiling` — derive sweep + product
- `@comp.omni` / `@comp.stack` — ceiling + optional sweep
- `@comp.burst` — derive.all + product
- `@comp.transcend` — 3-concept derive + map
- `@comp.infinity` — transcend + nfold(4)
- `@comp.hyper` — transcend + nfold(5)
- `@comp.tower` — nfold with dynamic k (up to 16)
- `@comp.power` / `@comp.powerset` — O(2^n)
- `@comp.choose` — O(n choose k), fixed-size subset generation
- `@comp.permute` — O(n!)
- `@comp.derive.product` / `@comp.derive.tensor` / `@comp.derive.nfold` — derive variants
- `@comp.derive.power` / `@comp.derive.choose` / `@comp.derive.permute` — derive on powerset/combinations/permutations

**Bare-name aliases** (ergonomic, for extremely common intrinsics that predate hierarchy):
- `@(expr)` = compile-time evaluation
- `@popcount`, `@clz`, `@ctz` — bit intrinsics
- `@likely`, `@unlikely` — branch hints
- `@hot`, `@inline`, `@cold`, `@noinline` — optimization directives
- `@raw`, `@packed`, `@align` — layout control
- `@export`, `@c.export`, `@ffi` — linkage
- `@modify(fn)` — type parameter validation
- `@native` — native C ABI (no lua_Value intermediaries); also `@comp.compile.native`
- `@cached` — memoize comptime evaluation
- `@deprecated`, `@pure`, `@flatten`, `@noreturn`, `@restrict` — function attributes

**In .lua files**, `--- @directive` in triple-dash comments provides the same without breaking Lua syntax.

**Goal:** produce the MOST expansive dynamic and capable output with MINIMAL syntax additions over Lua.
The framework must be MORE logical and capable than Jai's #run, Rust's proc macros, and Zig's comptime.

### 3. AI/ML-Native (Better Than Mojo)
- `Tensor[dims, dtype]` compile-time shape checking
- `@comp.device(.auto)` — one function targets CPU/CUDA/Metal/WebGPU/WASM
- `@comp.autodiff` — differentiation as compile-time transform
- Kernel fusion via user-definable rewrite rules
- Sub-millisecond startup, <1MB binary (vs PyTorch's 2GB)
- See `docs/ai_ml_native.md` for full design

### 4. C Interface: `@comp.c.*` Prefix
- `@comp.c.include("header.h")` — include C header
- `@comp.c.import("header.h")` — parse and import C declarations
- `@comp.c.export("name")` — export function with C ABI
- `@comp.c.type("struct_name")` — reference C type
- `@comp.c.call("func_name", args)` — call C function directly
- `@comp.c.emit("raw C code")` — inject raw C
- `@c.include`, `@c.emit`, `@c.export` also work as shorter aliases

### 5. Performance Guarantee (The Absolute Limit)
- **Ultimate Goal**: The goal is NOT just to compile down to C, but to lower to *whatever degree necessary* (machine code, object formats, asm, native formats, GPU kernels, etc.) to ensure the MOST OPTIMAL HIGHEST PERFORMANCE.
- Duo MUST achieve compile, runtime, and startup speeds that are better than ANY programming language maxed out at the absolute limit by any means necessary.
- Duo MUST beat or tie hand-written C on ALL 40 benchmarks
- Every change MUST be verified against `zig build bench`
- NO performance regressions are acceptable EVER.
- Benchmarks must cover: dispatch loops, memory access patterns, SIMD, string ops, table ops, recursion, iteration
- **ALL agents MUST read and update `docs/performance.md`** before and after any performance-affecting change (see *Agent Performance Protocol* in that file)

### 6. No Lua-Boxed Values (NON-NEGOTIABLE)
- **NO LUA INTERMEDIARIES EVER.** ALWAYS lower to the most performant representations possible.
- **Never use `lua_Value` intermediaries** when sema can prove native types (`i64`, `f64`, `bool`, `str`, typed records).
- Typed `.duo` hot paths MUST lower to direct C scalars/structs/machine representations — not Lua dynamic dispatch, not boxing/unboxing.
- Comptime-only helpers (`@comp.map` callbacks, derive generators) MUST NOT emit runtime lua thunks; use `@comp.compile.only` or rely on auto-detection.
- `@comp.*` metaprogramming folds at compile time; runtime output is native C/assembly (`const char*`, `int64_t`, `double`, struct literals).
- Literal metaprogramming helper calls such as `std.pipeline.fuse_*` MUST fold in codegen when inputs are compile-time strings; do not route proven generator calls through `req` tables, `lua_Value`, or `lua_invoke`.
- When adding features: prefer `native_scalar_mode` eligibility, typed params, and `@comp.c.emit`/`@comp.asm` over dynamic table/string APIs.
- **ALL AGENTS MUST REMEMBER THIS:** Backfill legacy paths that still box as appropriate to maximize performance. **Zero performance regressions.** Better than C performance across the board in ANY domain for ANY use case.

### 7. Multi-Agent Coordination & Context Buffer
- **Canonical index (`.agents/AGENT_CANONICAL.md`):** single router for ALL agents/CLIs — do not duplicate buffers.
- **Known agents (2026-08):** Devin, oh-my-pi, Codex, Claude Code, Agy, Ollama, Hermes, kiro-cli, Cursor/agent, OpenCode, Pool, Kilo (`kilo`), Kimi Code (`kimi` — `sudo npm install -g kimi-code --allow-scripts=keytar`), Junie, Trae, Qoder/qodercli.
- **Serena note:** appears in Cursor when wax project is open (project-plugin cache artefact). Not a Duo tool — dismiss it.
- **Context Buffer (`.agents/AGENT_COORDINATION.md`):** ALL agents MUST read/update at session start — file claims, resource tiers, sprint goals, build status, gap findings, delegation, and hooks.
- **Gaps Buffer (`.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer`):** canonical section for expressiveness, native-lowering, perf, scripting, backend gaps; `@comp.agent.gaps()` / `std.agent.gaps_index()`; MCP `duo_agent_gaps_read` / `duo_agent_gaps_update`.
  - Read via MCP tool `duo_coordination_buffer` (duo-lsp MCP) or `duo_coordination_read` (duo-bench MCP).
  - Update via MCP tool `duo_coordination_update` with action (claim/release/complete/status/note/block), agent_id, detail, files.
  - BEFORE editing any file: claim it. Do NOT edit files another agent has locked.
  - AFTER finishing: release the file and mark the task complete.
  - BEFORE running `zig build`/`zig build bench`/`zig build test`: check the buffer for active builds. Serialize builds to prevent machine freeze.
- **Default gate:** `scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo` (serialized; no bench).
- **Agent hooks:** `@comp.agent.catalog()`, `@comp.agent.ladder()`, `@comp.agent.hooks()`, `@comp.agent.dedupe()`, `@comp.agent.gaps()`; stdlib `std.agent`.

### 8. MCP Server Infrastructure (Agent Tooling)

Three MCP servers are configured for Duo development. All use stdio transport (no HTTP, no browser tabs, no OAuth). They are spawned as lightweight subprocesses by Hermes Agent.

**duo-lsp MCP** (`~/x/duo-mcp/duo_lsp.duo`)
Exposes Duo language intelligence to agents as callable tools:
- `duo_diagnostics(file_path)` — compiler diagnostics for a .duo file
- `duo_completions(file_path, line, char)` — code completions at cursor
- `duo_hover(file_path, line, char)` — hover/type info for a symbol
- `duo_definition(file_path, line, char)` — go-to-definition
- `duo_document_symbols(file_path)` — list all symbols in a document
- `duo_compile_check(file_path)` — run `duo check` and return parsed errors
- `duo_meta_catalog(grouped?)` — full @comp.* construct registry (reflects src/meta_module.zig)
- `duo_meta_ladder()` — @comp.* scaling ladder (O(types) → O(n!))
- `duo_language_features()` — all implemented language features, directives, C interface, AI/ML
- `duo_coordination_buffer()` — read the shared agent coordination buffer

**duo-bench MCP** (`~/x/duo-mcp/duo_bench.duo`)
Exposes benchmark + build/test gates + performance auditing:
- `duo_bench_run(bench_type, timeout)` — run `zig build bench` (or ml-bench, honest-bench, etc.), return structured JSON
- `duo_bench_regressions()` — compare current bench results vs docs/performance.md baseline
- `duo_perf_ledger()` — read the performance ledger summary
- `duo_perf_gaps()` — list open performance gaps
- `duo_build_run(gate, timeout)` — run build/test/unit-test/fmt-check gates with structured output
- `duo_coordination_read()` — read the coordination buffer
- `duo_coordination_update(action, agent_id, detail, files)` — update the coordination buffer

**zls MCP** (`~/x/duo-mcp/zls.duo`)
Exposes Zig language intelligence for editing the compiler's own Zig source (src/*.zig):
- `zig_diagnostics(file_path)` — LSP diagnostics for a .zig file
- `zig_hover(file_path, line, char)` — hover/type info
- `zig_definition(file_path, line, char)` — go-to-definition
- `zig_references(file_path, line, char)` — find all references
- `zig_completions(file_path, line, char)` — code completions
- `zig_document_symbols(file_path)` — list symbols in a .zig file
- `zig_format(file_path)` — format via `zig fmt`
- `zig_ast_check(file_path)` — quick `zig ast-check` error scan

### 9. Agent Hooks Architecture

**For Duo compiler development (agents working ON Duo):**
Agents get instant access to Duo's metaprogramming framework via MCP tools:
- `duo_meta_catalog()` — discover all 140+ @comp.* constructs
- `duo_meta_ladder()` — understand output scaling (O(n) → O(n!))
- `duo_language_features()` — know what syntax/types/directives are implemented
- `duo_compile_check()` — verify code correctness instantly
- `duo_bench_run()` / `duo_bench_regressions()` — audit performance impact
- `duo_coordination_buffer()` — coordinate with other active agents

**For Duo end-user development (agents writing IN Duo):**
When Duo is used as a build tool, agents leverage the same metaprogramming multipliers:
- `@comp.catalog()` in Duo code itself — self-documenting language features
- `@comp.ladder()` — choose the right output scaling construct
- `@comp.derive.bundle("Numeric")` — one annotation → 8 trait implementations
- `@comp.map(types, callback)` — O(types) code generation from one call
- `@comp.product(types_a, types_b, callback)` — O(types²) from one call
- `@comp.nfold({concepts}, k, callback)` — O(types^k) from one call
- `@comp.ceiling(...)` / `@comp.omni(...)` — stacked combinators
- `@comp.compile.cached` — memoize expensive comptime computations
- `@comp.embed.file` — write generated code to disk for reuse
- `@comp.pipeline({ variants = "..." })` — one descriptor → N fused typed kernels

**Exponential dividend design:** The agent hooks are designed so that a single agent
action (one MCP tool call, one @comp.* construct) produces multiplicative output.
This mirrors the @comp.* framework's core design: O(1) author input → O(n^k) output.
Agents should ALWAYS prefer metaprogramming constructs over manual code generation.

## Duo Language Conventions

When writing `.duo` files, follow these conventions:

### File-as-M Pattern
- Every module file IS its own `M`. Treat the file scope as `M` — no need for `local M = {}` / `return M` boilerplate. Functions and values declared at file scope are module exports. Use an explicit `M = {}` table only when you need to rename exports or selectively expose a subset.

### Syntax
- **`fun` / `function` deprecated in `.duo`** — prefer bare `name(params) body end` or `name = (params) body end` (see `docs/GRAMMAR_SPEC.md` GR-001).
- **If-expressions** — `x = if cond expr else if cond2 expr2 else expr3 end` (GR-002).
- **`fun` over `function`** — when a keyword is required (Lua), prefer `fun`.
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
- Prefer `@comp.*` for new features; use bare-name aliases only for extremely common pre-existing intrinsics.
- Use `const` for module-level constants that should fold into typed code.

### Compiler Hints (Lua files only)
- Compiler hints like `--- @inline`, `--- @cold`, `--- @unroll` are supported only in `.lua` files as an extra feature. Do not use them in `.duo` files — in .duo files, `@` is direct syntax, not embedded in comments.

### Type Annotations
- Add `i64`, `str`, `float`, `bool` type annotations on parameters and return types when performance matters. The codegen inserts native C casts for these, generating faster code.

### The @comp.c.* Interface
- `@comp.c.include("header.h")` for C headers
- `@comp.c.emit("code")` for raw C injection
- `@c.include`, `@c.emit`, `@c.export` also work as shorter aliases
- `@ffi("name")` on functions for external C linkage
- `@comp.c.export("name")` for exported symbols

### Naming
- Module files: `lib/std/<name>.duo` — short, lowercase, no underscores.
- Functions: `snake_case` — e.g. `do_retry`, `circuit_new`, `config_get`.
- Internal helpers: prefix with the module name — e.g. `std_retry_sleep`, `dt_pad2`, `dt_is_leap_year`.
- Avoid C reserved words as parameter names (e.g. `default`).
- `@comp.*` dotted paths use periods, never underscores: `@comp.compile.thread` not `@compile_thread`.

### Module Structure
- Register every stdlib module in `lib/std.duo` with a `std.<name> = req "std.<name>"` line.
- Group related modules hierarchically: `std.net.retry` (network retry), `std.collections.cache` (data structures), `std.time.timer` (timing), etc.
- Export via `M = {}` / `M` at file end when renaming exports or exposing a subset.

## Syntax Semantics (canonical — keep compiler, stdlib, and docs aligned)

| Rule | `.duo` behavior | Implementation status |
| --- | --- | --- |
| **Implicit `local`** | Omit `local` everywhere; bindings are file/module locals unless `global` is explicit | **Fixed** in `src/sema.zig` (2026-07-12) |
| **`@` prefix** | ALL compile-time ops use `@comp.*` dotted paths; `@meta.*` and `@compiler.*` are aliases | Parser desugars dotted paths to `__*` internals |
| **`_` private prefix** | Top-level `fun _helper()` / `_state = …` are file-private, not module exports | **Codegen**: `add_module_export` skips `name[0]=='_'` |
| **`global`** | Only way to create a true module global in `.duo` | Implemented via `global_decl` |
| **String-literal calls** | `print 'hi'`, `req 'std.io'` — call sugar without parens | Parser `parse_suffixed_expr` |
| **Bare functions + if-expressions** | `name(params) body end`, `name = (params) body end`, and `if cond expr else if ... end` | Parser hardened 2026-07-30: `else if` normalized; speculative function parsing avoids call-expression diagnostics |
| **Indentation** | Not semantic; blocks close with `end` | Lua-style |
| **`@comp.*` hierarchy** | Primary module for ALL metaprogramming; NO underscore public names | `src/meta_module.zig` |
| **Canonical names** | Internal dispatch uses `__*` prefixed names, not underscore-separated public surface | `src/meta_module.zig` |

### Agent documentation protocol

1. **Before any work:** read `.agents/AGENT_COORDINATION.md` via MCP (`duo_coordination_buffer` / `duo_agent_gaps_read`), plus `AGENTS.md`; for perf/codegen also `docs/performance.md`.
2. **Claim** your area in `.agents/AGENT_COORDINATION.md` via `duo_coordination_update(action="claim", agent_id=..., detail=..., files=...)` before editing shared surfaces.
3. **After** performance or codegen work: append a dated section to `docs/performance.md` with commands run, files touched, measured ratios, and rejected experiments.
4. **After** syntax/semantic fixes: update the semantics table if status changes.
5. **Default verify:** `scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo` (not full bench unless you hold the benchmarks claim).
6. **Hardware / low-level**: prefer `.duo` + `@comp.c.emit` / `@comp.asm` / `@comp.device` in `lib/std/hardware.duo` and `lib/std/ml/device.duo` when Lua grammar blocks optimization; do not add Lua-only benchmark gaming.

### Open gaps (2026-07-29)

- **Sieve**: 8-byte hardware popcount via `__builtin_popcountll` now implemented, and marking loop uses pointer-based stride arithmetic to avoid repeated index multiplication. Further improvements would likely require chunk-based 16-byte SIMD marking.
- **Mandelbrot**: `duo_mandel_benchmark_sum` is now `static inline __attribute__((always_inline))` while keeping `no-fast-math`; `.duo` now beats `.lua` while `RESULT` matches. 4-wide SIMD without RESULT drift is still open.
- **Lua boxed values**: `codegen.zig` still emits `lua_to_num`, `lua_to_bool`, `lua_to_str` on several paths that could use native lowering. Audit in progress.
- **`@comp.*` canonical names**: internal `normalizeDirective` still maps dotted paths to underscore canonical names. These should be fully dotted.
- **Duo as scripting**: need stdlib modules for argparse, filesystem, subprocess, env vars to match Python/bash ergonomics.

### Exponential Metaprogramming Patterns (2026-07-29)

The `@comp.*` compiler module turns O(1) author input into multiplicative output. Discover paths via `@comp.catalog()` or `@comp.catalog("grouped")`; scaling reference via `@comp.ladder()`.

| Construct | Output scaling |
|---|---|
| `@comp.map` / `@comp.sweep` | O(types) |
| `@comp.derive` | O(types × fields) |
| `@comp.product` | O(types²) |
| `@comp.derive.product` | O(types² × fields) |
| `@comp.tensor` | O(types³) |
| `@comp.derive.tensor` | O(types³ × fields) |
| `@comp.nfold` | O(types^k) — generalizes product/tensor |
| `@comp.derive.nfold` | O(types^k × fields) |
| `@comp.ceiling` | derive sweep + cartesian derive product |
| `@comp.omni` / `@comp.stack` | ceiling + optional sweep |
| `@comp.burst` (module) | derive.all + quadratic emit |
| `@comp.transcend` (module) | burst + cubic emit |
| `@comp.infinity` (module) | transcend + quartic emit |
| `@comp.hyper` (module) | transcend + quintic emit |
| `@comp.tower` | nfold with dynamic k (k up to 16) |
| `@comp.power` / `@comp.powerset` | O(2^n) — truly exponential |
| `@comp.choose` / `@comp.derive.choose` | O(n choose k) — controlled fixed-size subset expansion |
| `@meta.power` / `@meta.permute` | O(2^n) / O(n!) — truly exponential |
| `@meta.agent.*` | agent discoverability hooks |
| `@meta.grammar` | O(b^d) — EBNF grammar-driven code generation (generative) |
| `@meta.weave` | O(N×M) — cross-module type-driven code injection (generative) |
| `@meta.template` | O(instances) — parametric code templates (generative) |
| `@meta.generate` | O(constraints) — constraint-based code synthesis (generative) |
| `@meta.scheme` | O(declarations) — declarative scheme → implementation (generative) |

Patterns:

1. **Derive Bundles** (`@comp.derive.bundle("Numeric")`): One annotation → 8 trait implementations.

2. **Type-Pattern Rewrite Rules**: One rule `($1 - $1) → 0` matches ANY expression that subtracts itself.

3. **User-Defined Derives** (`@comp.define.derive`): One macro definition → generates code for every matching type.

4. **Cross-Invocation Caching** (`@comp.compile.cached`): First invocation computes, subsequent calls cached.

5. **Compile-Time File Emission** (`@comp.embed.file`): One construct → writes generated code to disk.

6. **Higher-Order Derives** (`@comp.derive`): One macro applied to N types → N implementations.

7. **Stacked Combinators** (`@comp.burst`, `@comp.transcend`, `@comp.infinity`): compose linear + quadratic + cubic + quartic sweeps.

8. **Arbitrary-Degree Sweeps** (`@comp.nfold`, `@comp.derive.nfold`): O(types^k) output for any k.

9. **Pipeline Families** (`@comp.pipeline({ variants = "sum_i64:int64_t:0 | sum_f64:double:0.0" })`): One descriptor → N fused typed kernels.

10. **Pipeline Products** (`@comp.pipeline({ types = "...", takes = "..." })`): One descriptor → cartesian product fused kernels.

Example exponential pattern:
```duo
-- One derive macro generates N operator implementations
@comp.define.derive("Fieldwise", fun generate(meta) -> str
    code = ""
    for i = 1, #meta.fields
        f = meta.fields[i]
        code = code .. f.name .. " = lhs." .. f.name .. " + rhs." .. f.name .. "; "
    end
    code
end)

-- Apply to multiple types with one bundle
@comp.derive.bundle("Numeric")
type Vec3 = { x: f64, y: f64, z: f64 }
type Mat4 = { ... }  -- Gets all Numeric traits too!
```

## Duo as Universal Scripting Language

Duo MUST be the preferred choice for ALL scripting operations, replacing Python, bash, and Lua.
This means:
- Duo stdlib must have first-class modules for: argparse, filesystem ops, subprocess, env vars, JSON/YAML/TOML, HTTP client/server, regex, templating, testing, benchmarking
- `@comp.run("cmd")` for shell execution at compile time
- `std.fs`, `std.io`, `std.proc`, `std.env` for runtime OS interaction
- Shebang support (`#!/usr/bin/env duo`) for standalone scripts
- Sub-millisecond startup for script use cases
- All the above already exist in lib/std/ — ensure they stay ergonomic and performant

## Performance Work

**Canonical reference:** `docs/performance.md` — the performance ledger, gap analysis, benchmark inventory, and modification roadmap. Read it at the start of any performance task; append a dated entry after every benchmark-affecting change (including rejected experiments).

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.
