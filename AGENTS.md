# Agent Instructions

## Core Design Targets (ALL agents MUST acknowledge and follow)

### 1. The Aha Moment Target
Every feature must create "discoverability moments" — the feeling when Zig's comptime made generics click, when Rust's traits made metaprogramming extensible. Duo features should compose intuitively so developers have revelations about what's possible. Features should be discoverable through common-sense semantics and produce outsized results from minimal input.

### 2. Metaprogramming Framework (More Capable Than Jai/Rust/Zig)
- `@` is the SINGLE prefix for ALL compile-time operations in .duo files
- All directives use dotted paths under a compiler meta module; NO underscore patterns in public surface
- **Primary:** `@comp.*` — shortest, canonical compiler module
- **Aliases:** `@compiler.*`, `@meta.*` — both map to same internal targets
- NO underscores in @-directive names: write `@comp.foo.bar`, NEVER `@comp.foo_bar`

**Hierarchy:**
- `@comp.compile.*` — compile-time control (`when`, `loop`, `fold`, `log`, `warn`, `error`, `assert`, `cached`, `thread`, `device`, `autodiff`, `unroll`, `modify`, `profile`, `native`)
- `@comp.embed.*` — file embedding (`str`, `file`, `json`, `wasm`)
- `@comp.bit.*` — bit intrinsics (`popcount`, `ctz`, `clz`, `bswap`, `rotl`, `rotr`, `bitcast`)
- `@comp.hint.*` — optimization hints (`likely`, `unlikely`, `prefetch`, `assume`, `unreachable`, `trap`, `fence`)
- `@comp.type.*` — type introspection (`name`, `id`, `info`, `is`, `as`)
- `@comp.c.*` — C interface (`emit`, `include`, `import`, `export`, `call`, `type`)
- `@comp.agent.*` — agent discoverability hooks (`catalog`, `ladder`, `hooks`, `dedupe`, `gaps`)
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
- `@comp.tabulate` — O(n) compile-time lookup table generator
- `@comp.interpolate` — O(n) compile-time string interpolation (code template injection with {name} placeholders)
- `@comp.zip` — O(n*m) compile-time cartesian zip
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

**Bare-name aliases** (ergonomic, for extremely common intrinsics):
- `@(expr)` = compile-time evaluation
- `@popcount`, `@clz`, `@ctz` — bit intrinsics
- `@likely`, `@unlikely` — branch hints
- `@hot`, `@inline`, `@cold`, `@noinline` — optimization directives
- `@raw`, `@packed`, `@align` — layout control
- `@export`, `@c.export`, `@ffi` — linkage
- `@modify(fn)` — type parameter validation
- `@native` — native C ABI (no lua_Value intermediaries)
- `@cached` — memoize comptime evaluation
- `@deprecated`, `@pure`, `@flatten`, `@noreturn`, `@restrict` — function attributes

**In .lua files**, `--- @directive` in triple-dash comments provides the same without breaking Lua syntax.

**Goal:** produce the MOST expansive dynamic and capable output with MINIMAL syntax additions over Lua. The framework must be MORE logical and capable than Jai's #run, Rust's proc macros, and Zig's comptime.

### 3. AI/ML-Native (Better Than Mojo)
- `Tensor[dims, dtype]` compile-time shape checking
- `@comp.device(.auto)` — one function targets CPU/CUDA/Metal/WebGPU/WASM
- `@comp.autodiff` — differentiation as compile-time transform
- Kernel fusion via user-definable rewrite rules
- Sub-millisecond startup, <1MB binary (vs PyTorch's 2GB)
- See `docs/ai_ml_native.md` for full design

### 4. Semantic Graph Architecture (THE Meta-Priority)
**This overrides all other priorities.** As of 2026-08-04, Duo's ultimate goal is:

> "A compact language for defining computations, transformations, constraints, and objectives over a persistent semantic universe—where humans, compilers, libraries, and agents all manipulate the same program model at different levels of authority."

**Key pillars (in order of importance):**
1. **Persistent semantic graph with durable identities** — Everything is a graph node
2. **Unified transformation engine** — All `@comp.*` directives are transforms with contracts/provenance
3. **First-class staging + budgeted partial evaluation** — Agents can reason about computation exposure
4. **Effects and capabilities** — Basis for builds, plugins, agents
5. **Transactional semantic editing** — Safe agent collaboration

**All agents:** See `.agents/AGENT_COORDINATION.md` for the detailed implementation plan. Coordinate via `duo_agent_gaps_update()` rather than duplicating work.

### 4. C Interface: `@c.*` Prefix
- `@c.include("header.h")` — include C header (replaces @cinclude)
- `@c.import("header.h")` — parse and import C declarations
- `@c.export("name")` — export function with C ABI
- `@c.type("struct_name")` — reference C type
- `@c.call("func_name", args)` — call C function directly
- `@c.emit("raw C code")` — inject raw C (replaces __emit)
- Full form: `@comp.c.*` — both `@c.*` and `@comp.c.*` are valid

### 5. Performance Guarantee
- Duo MUST beat or tie hand-written C on ALL 40 benchmarks
- Every change MUST be verified against `zig build bench`
- NO performance regressions are acceptable
- Benchmarks must cover: dispatch loops, memory access patterns, SIMD, string ops, table ops, recursion, iteration
- **ALL agents MUST read and update `docs/performance.md`** before and after any performance-affecting change (see *Agent Performance Protocol* in that file)

### 6. NO LUA BOXED VALUES (Critical Rule)

**ALL typed and comptime paths MUST lower to native C scalars and structs. lua_Value intermediaries are NEVER acceptable on any typed/comptime path.**

- Typed function parameters and return values become C types directly (e.g. `i64` → `int64_t`, `float` → `double`, `str` → `const char*`).
- Comptime-evaluated expressions must fold to C literals or typed struct initializers.
- Introducing a `lua_Value` (tagged union / boxed value) on a typed path is a correctness AND performance bug. Reject any codegen change that does this.
- Literal metaprogramming helper calls (`std.pipeline.fuse_*`) MUST fold in codegen when inputs are compile-time strings; do not route proven generator calls through `req` tables, `lua_Value`, or `lua_invoke`.
- Untyped/dynamic paths may still use lua_Value — this is expected for fully dynamic Lua-compatible code.
- When adding features: prefer `native_scalar_mode` eligibility, typed params, and `@comp.c.emit`/`@comp.asm` over dynamic table/string APIs.
- Backfill legacy paths that still box as appropriate to maximize performance.

## Ultimate Lowering Goal

Duo lowers to WHATEVER native format achieves maximum performance — C, assembly, machine code, GPU kernels (CUDA/Metal/WebGPU), SIMD intrinsics, or WASM. The output is NOT limited to C. C emission is the default fallback; specialized backends target asm, SIMD, and GPU kernels where they outperform C.

Duo MUST achieve compile, runtime, and startup speeds that are better than ANY programming language maxed out at the absolute limit by any means necessary.

## Semantic Universe (architectural north star — all agents)

**Read first:** [`docs/AGENT_ALIGNMENT.md`](docs/AGENT_ALIGNMENT.md) (2-min compass).

**Full plan:** [`docs/archive/semantic_graph_architecture.md`](docs/archive/semantic_graph_architecture.md).

**Architecture passes (read in order):**
- Pass 2: [`docs/archive/pass2_foundational_convergence.md`](docs/archive/pass2_foundational_convergence.md) — 8 algebras
- Pass 3: [`docs/archive/pass3_directive_grammar_convergence.md`](docs/archive/pass3_directive_grammar_convergence.md) — grammar/directives
- Pass 4: [`docs/archive/pass4_native_end_to_end.md`](docs/archive/pass4_native_end_to_end.md) — native backend
- Pass 5: [`docs/archive/pass5_semantic_interchange.md`](docs/archive/pass5_semantic_interchange.md) — cross-language
- Pass 6: [`docs/archive/pass6_architectural_reconciliation.md`](docs/archive/pass6_architectural_reconciliation.md) — architectural reconciliation
- Pass 7: [`docs/archive/pass7_ai_native_compilation.md`](docs/archive/pass7_ai_native_compilation.md) — AI-native compilation
- Pass 8: [`docs/archive/pass8_persistent_semantic_computing.md`](docs/archive/pass8_persistent_semantic_computing.md) — persistent semantic computing
- Pass 9: [`docs/archive/pass9_ward_readiness.md`](docs/archive/pass9_ward_readiness.md) — Ward readiness & runtime supremacy

**Catalogs:** [`docs/catalogs/keywords.md`](docs/catalogs/keywords.md) | [`docs/catalogs/directives.md`](docs/catalogs/directives.md) | [`docs/catalogs/grammar_compactness.md`](docs/catalogs/grammar_compactness.md) | [`docs/catalogs/native_barriers.md`](docs/catalogs/native_barriers.md)

Duo’s long-term shape is not “Lua with every advanced feature.” It is a **compact
language for computations, transformations, constraints, and objectives over a
persistent semantic program model** — humans, compilers, libraries, and agents
manipulate the **same graph** at different capability levels.

**Foundational priorities (Tier A):** (1) persistent semantic graph + durable IDs,
(2) unified transformation engine + contracts + provenance, (3) first-class staging
+ budgeted partial eval, (4) effects/capabilities for builds/plugins/agents,
(5) transactional semantic editing for agent workflows.

**Do not** add new `@comp.*` combinators without registry entry, contract, and
parity tests (top-level, nested callback, block body). Exponential metaprogramming
remains the advantage; **predictable composition** is how we keep it.

This plan **preserves** performance gate, Lua superset, native lowering, and
minimum-syntax ergonomics — see §11 of the semantic graph architecture doc.

## Duo Grammar Rules (Canonical)

These rules are authoritative. Compiler, stdlib, docs, and all agents must stay aligned.

### @-Directive Syntax
- NO `@const` or `@comptime` — these are NOT valid Duo directives.
- Use `@(expr)` for compile-time evaluation of an expression.
- Use `@comp.*` for module-scope compile-time transforms (e.g. `@comp.derive`, `@comp.specialize`).
- `@comp.*` is the PRIMARY metaprogramming module. `@meta.*` and `@compiler.*` are aliases and map to the same functionality.
- NO underscores in @-directive names: write `@comp.foo.bar`, NEVER `@comp.foo_bar`.

### Function Declaration
- Bare function declarations are preferred in new .duo code — the `fun` or `function` keyword is optional when the context is unambiguous at file/module scope.
- Example: `add(a: i64, b: i64): i64 = a + b`
- `fun` remains valid and may be used for clarity inside blocks.

### If-Expressions
- Duo supports if as an expression: `x = if a < b value else value * 2 end`
- The `end` closes the if-expression. Omitting `then` is Duo-canonical; `if ready then run() end` remains valid Lua (`LUA_AND_DUO_CANONICAL`).
- Chained: `x = if a expr1 else if b expr2 else expr3 end`

### Table Keys
- Identifier keys NEVER need `[]`: write `{ x = 1, y = 2 }` not `{ [x] = 1 }`.
- Computed/dynamic keys use `[]`: `{ [key_expr] = value }`.

### Lua superset maximization (Pass 24)

- Duo is a **Lua superset**, not a Lua-inspired subset. Valid Lua 5.5 should remain valid with equivalent semantics unless a documented superset exception applies.
- **`[[ ... ]]` is Lua long-string syntax** — never deprecate, repurpose as shell conditionals, or replace with alternate block syntax. Full long-bracket family and long comments must match Lua delimiter rules.
- **Canonical ≠ exclusive.** Prefer denser Duo forms in new code; permanently accept Lua-canonical equivalents (`then`, `do`, `local function`, parenthesized calls).
- **Call model:** bare `a` = value reference; `a()` / `a x` = invoke; shell zero-arg commands only in explicit command regions (Pass 15) — never global bare-name invocation.
- **Deprecation threshold:** genuine conflict + no reliable disambiguation + blocks higher-value capability + exact migration + documented exception. Token reduction alone is insufficient.
- Full constitution: `docs/archive/pass24_execution_concurrency_lua_supremacy.md`. Matrix: `docs/catalogs/lua_superset_compatibility.md`. Gate: `zig build lua-superset-gate`.

## Duo Language Conventions

When writing `.duo` files, follow these conventions:

### File-as-M Pattern
- Every module file IS its own `M`. Treat the file scope as `M` — no need for `local M = {}` / `return M` boilerplate. Functions and values declared at file scope are module exports. Use an explicit `M = {}` table only when you need to rename exports or selectively expose a subset.

### Syntax
- **Bare declarations preferred** — `name(params): ret body end` without `fun`/`function` keyword.
- **`fun` when needed** — use inside blocks or for clarity. Always prefer `fun` over `function`.
- **`req` over `require`** — use `req` for all module imports. `req("std.string")` for stdlib, `req("module.path")` for user modules.
- **If-expressions as values** — `x = if cond expr else expr2 end`.
- **Omit `do`** where the parser allows it — `while cond ... end`, `for ... end`.
- **Prefer omitting `then`** — `if ready run() end` is Duo-canonical; `if ready then run() end` remains permanently accepted Lua syntax.
- **Omit `local`** — in .duo files, all bindings default to local scope.
- **`end` closes all blocks** — `fun`, `if`, `while`, `for`, `match`, `enum`, etc.

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
- `@comp.*` dotted paths use periods, never underscores: `@comp.compile.thread` not `@compile_thread`.

### Module Structure
- Register every stdlib module in `lib/std.duo` with a `std.<name> = req "std.<name>"` line.
- Group related modules hierarchically: `std.net.retry` (network retry), `std.collections.cache` (data structures), `std.time.timer` (timing), etc.
- Export via `M = {}` / `M` at file end when renaming exports or exposing a subset.

## Syntax Semantics (canonical — keep compiler, stdlib, and docs aligned)

| Rule | `.duo` behavior | Implementation status |
| --- | --- | --- |
| **Implicit `local`** | Omit `local` everywhere; bindings are file/module locals unless `global` is explicit | **Fixed** in `src/sema.zig` (2026-07-12): duo module scope no longer uses `require_global`; reads of undeclared names auto-define locals; pre-register assign targets |
| **`@` prefix** | ALL compile-time ops use `@comp.*` dotted paths; `@meta.*` and `@compiler.*` are aliases | Parser desugars dotted paths to `__*` internals |
| **`_` private prefix** | Top-level `fun _helper()` / `_state = …` are file-private, not module exports | **Codegen**: `add_module_export` skips `name[0]=='_'`; **LSP** (`duo-lsp`): should mirror — open gap if completion lists `_` symbols |
| **`global`** | Only way to create a true module global in `.duo` | Implemented via `global_decl` |
| **String-literal calls** | `print 'hi'`, `req 'std.io'` — call sugar without parens | Parser `parse_suffixed_expr` |
| **Bare functions + if-expressions** | `name(params) body end`, `name = (params) body end`, and `if cond expr else if ... end` | Parser hardened 2026-07-30 |
| **Indentation** | Not semantic; blocks close with `end` | Lua-style |
| **`@comp.*` hierarchy** | Primary module for ALL metaprogramming; NO underscore public names | `src/meta_module.zig` |
| **Table keys** | Identifier keys: `{ x = 1 }`; computed: `{ [expr] = val }` | Standard Lua table semantics |

### Agent documentation protocol

1. **Before any work:** read `.agents/AGENT_COORDINATION.md` and `AGENTS.md`; for perf/codegen also `docs/performance.md`.
2. **Claim** your area in the untracked `.agents/session/` before editing shared surfaces, and name it in the commit message either way.
3. **After** performance or codegen work: append a dated section to `docs/performance.md` with commands run, files touched, measured ratios, and rejected experiments.
4. **After** syntax/semantic fixes: update the semantics table if status changes.
5. **Hardware / low-level**: prefer `.duo` + `@comp.c.emit` / `@comp.asm` / `@comp.device` in `lib/std/hardware.duo` and `lib/std/ml/device.duo` when Lua grammar blocks optimization; do not add Lua-only benchmark gaming.

### Open gaps (2026-08-03)

- **Sieve**: 8-byte hardware popcount via `__builtin_popcountll` now implemented, and marking loop uses pointer-based stride arithmetic to avoid repeated index multiplication. Further improvements would likely require chunk-based 16-byte SIMD marking.
- **Mandelbrot**: `duo_mandel_benchmark_sum` is now `static inline __attribute__((always_inline))` while keeping `no-fast-math`; `.duo` now beats `.lua` while `RESULT` matches. 4-wide SIMD without RESULT drift is still open.
- **Lua boxed values**: `codegen.zig` still emits `lua_to_num`, `lua_to_bool`, `lua_to_str` on several paths that could use native lowering. Audit in progress.
- **`@comp.*` canonical names**: internal `normalizeDirective` still maps dotted paths to underscore canonical names. These should be fully dotted.
- **LSP `_` privacy**: export filtering in `duo-lsp` (codegen already filters)
- **Exponential combinator boxing** (2026-08-04): ~~`@comp.tensor`, `@comp.transcend`, `@comp.infinity`, `@comp.hyper` fold correctly but emit `lua_to_str("<literal>")` instead of bare `const char*` C literals.~~ **FIXED** (kiro-cli 2026-08-04): Added tensor/transcend/infinity/hyper to `fold_meta_string_expr` and `comptimeMetaHook`. All four now emit bare `const char*` literals.
- **@comp.nfold unwired**: ~~Registered + hook exists in meta_module.zig but NO codegen dispatch.~~ **FIXED** (kiro-cli 2026-08-04): Added `__comptimenfold` to `maybe_emit_meta_string_call`. Fully wired.
- **func_is_compile_only missing**: ~~`@comp.compile.only` is registered as a directive but has NO enforcement in codegen.~~ **FIXED** (kiro-cli 2026-08-04): `func_is_compile_only()` added; gates `emit_lua_thunk_decls` and `emit_lua_thunk`.
- **Alias metatable guards**: ~~`emit_alias_metatable_init`, `emit_alias_metatable_decls`, `emit_alias_derive_functions` in codegen.zig lack `native_scalar_mode` guards.~~ **FIXED** (prior agent): All three already have guards.

## Performance Work

**Canonical reference:** `docs/performance.md` — the performance ledger, gap analysis, benchmark inventory, and modification roadmap. Read it at the start of any performance task; append a dated entry after every benchmark-affecting change (including rejected experiments).

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.

## Known Parallel Agents

Duo is actively developed by 5+ concurrent agents working in parallel. Known agents include:

- devin
- oh-my-pi
- codex
- claude-code
- agy
- ollama
- hermes
- kiro-cli
- cursor/agent
- opencode
- pool
- kilo (npm @kilocode/cli)
- kimi-code (`kimi` binary — `sudo npm install -g kimi-code --allow-scripts=keytar`)
- junie
- trae
- qodercli (@qoder-ai/qodercli)

NOTE on Serena: if Serena appears in a Cursor session it is a project-plugin cache artefact from the wax workspace — not a Duo MCP tool. Dismiss it.

All agents must follow the rules in this file. Before starting work, read the full AGENTS.md and the relevant docs. Coordinate via git commits and docs/performance.md entries to avoid conflicts.

**NEVER `git stash` work away.** Do not stash to reach a "clean tree", dodge a
conflict, or clear the tree for a parallel agent — the stash hides work from
`git status`, all other agents keep building against stale copies, and it caused
one full 23-file rescue (2026-08-01). Commit early on a branch, coordinate via
claims in `.agents/session/`, or export a visible `.patch` file.
`git stash list` must stay EMPTY.

## Companion Repositories

- **duo-mcp**: ~/x/duo-mcp/ — canonical MCP (Model Context Protocol) server for Duo. Provides tool definitions and AI integration for Duo language services.
- **duo-lsp**: ~/x/duo-lsp/ — canonical LSP (Language Server Protocol) implementation for Duo. Provides editor integration, completion, and diagnostics.
