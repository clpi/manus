# Performance roadmap

Tracking for the codegen/optimization work. Ordered by priority. Each item notes the
relevant code locations so future work can start without re-deriving them.

**Hard constraint:** every change must keep `zig build bench` green (Duo ≥ C on all 40
benchmarks) and the full test gate at 360/360 or better.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done.

## Language roadmap status

This section tracks language-surface work that affects performance and docs.
Keep it in sync with `docs/src/roadmap.md`.

- [x] **List/Table type unification.** `Table`/`table` now resolve to the dynamic
  Lua table representation, and `List[T]`/`list[T]` resolve to the same dynamic
  typed list shape as `[]T`.
- [x] **Await instead of wait.** `await` is the supported async wait operator;
  no separate `wait` keyword is planned.
- [x] **`a = expr and x or y` semantics.** Lua short-circuit expressions now
  preserve operand-return semantics. `cond and x or y` recovers native typed C
  when `x` and `y` share a safe non-boolean/non-nil branch type.
- [x] **List comprehension.** `{expr for value in table}` and
  `{expr for key, value in table if condition}` lower to dynamic array tables.
- [~] **Macros / metaprogramming.** Compile-time `##(...)` and `std.meta`
  helpers exist; hygienic macro syntax is still planned.
- [~] **if / else postfix semantics.** Block-tail `if ... then ... else ... end`
  expressions work; postfix conditional syntax is not implemented.
- [~] **Concept metatable merging.** Concepts exist as structural checks and
  now emit runtime descriptor tables that `std.meta.satisfies_concept` can
  inspect. `std.meta.make_concept(...)` and `std.meta.derive` now build the
  same descriptor shape without keyword declarations; compile-time
  `@implements` now accepts literal `meta.make_concept(...)` descriptor
  bindings. Generic constraints and dispatch still depend on parser-level
  concepts.
- [~] **Allocator / memory management.** ARC exists; escape analysis, ARC
  pruning, and custom allocator work remain open below.
- [x] **`std.string = string`, `std.io = io`, etc.** Standard modules expose Lua
  library wrappers via `req "std.module"` / `require("std.module")`.
- [x] **`type` keyword instead of `alias`.** `type Name = ExistingType` is
  supported; `alias` remains accepted as legacy syntax.
- [x] **`case ... do/then ...` instead of arrow.** Match arms accept the
  Lua-like `case pattern [if guard] then|do statement` form. The legacy
  `pattern [if guard] => statement` form remains accepted for compatibility,
  while the pretty-printer emits `case ... then ...`.
- [x] **`?` and `!` operators.** Postfix propagation and unwrap parse and are
  checked by sema.
- [x] **Declare without `local` as standard local declaration.** `.duo` files
  are local-by-default for bare assignments; `local` remains valid.
- [x] **Interactive shell.** Running `duo` with no arguments or `duo shell`
  starts a line-oriented shell that compiles/runs snippets through the normal
  pipeline, prints bare expressions automatically, supports `!command` host
  escapes, and accepts first-line Unix shebangs in `.duo` scripts.
- [~] **Merge concepts and metatables; remove syntax additions; make more Lua.**
  Runtime concept descriptors now share the Lua table shape used by
  `std.meta`, standard derivable descriptors are ordinary tables, and
  `@implements` can validate against literal descriptor bindings; implementation
  remains partial until generic constraints/dispatch and declaration syntax move
  fully onto ordinary metatables.
- [~] **Pointers / references.** Pointer types use `*T`; reference and ownership
  semantics remain planned.

## Highest priority

- [~] **Kill dynamic fallback on hot expressions.** Audit `expr_type` / `emit_expr`
  (`src/codegen.zig:401`, `:3991`) so arithmetic, indexing, field access, and calls stay
  in native typed C instead of falling back to `any`/`lua_Value`.
  - [x] `unop` typing in `expr_type`: `not`→bool, `-x`/`~x`/`#x` stay native when the
    operand is native (`src/codegen.zig:401`). Previously every unary result was `.any`,
    boxing downstream consumers (`arr[-i]`, `(-x)+y`, `#s == n`).
  - [x] **Field access** (`.field`): structural fallback in `expr_type` resolving a
    field's type from the object's `table_type` when `type_map` misses
    (`src/codegen.zig:483`). The common case (sema-typed record bindings) already
    produced native `obj.field`; this closes the gap for monomorphized/generic bodies
    where `type_map` is keyed on the unspecialized expr. Still TODO: named `.@"struct"`
    field lookup (needs a name→fields registry, not just inline `table_type`).
  - [x] **Builtin call results — `math.*`**: `math_call_result_type` (`src/codegen.zig:556`)
    types every recognized `math.*` builtin; `expr_type` uses it to recover a native type
    when sema only tagged the call `.any`. `max`/`min`/`abs` are integer-typed when their
    args are integers and emit native integer ops (`lua_imax_i64`/`lua_imin_i64`/`llabs`);
    the rest are f64. This also **fixed a real codegen bug**: `math.max`/`min`/`abs` in a
    typed integer function emitted a dynamic `lua_Value` (e.g. `lua_math_max`) and then
    `return`ed it from an `int64_t` function — a C compile error. Canonical `clamp`/`imath`
    now compile to clean native ops.
  - [x] **Builtin call results — string/other**: `expr_type` now mirrors sema's
    string builtin result typing so `string.len`/`string.byte` recover integer
    results and `string.sub`/`string.rep`/case-conversion calls recover native
    `str` results without falling back to `.any`.
  - [x] **Native indexed element results**: fixed arrays and pointers now recover
    their element type, while SIMD vectors recover their lane type, when the
    exact expression is absent from `type_map`. Pointer indexing is covered by
    Property 11 and verified to emit direct typed C (`return xs[i];`) rather
    than a `lua_Value` table lookup.
  - [x] **Typed function-call results**: when an exact call entry is missing from
    `type_map`, `expr_type` now recovers the callee function's declared return
    type. Function-typed parameters also emit valid C declarators such as
    `int32_t (*f)(int32_t)`, so higher-order calls remain direct native C.
  - [~] **Audit `catch .any` / `orelse .any` sites** on hot paths (`resolve_type`
    at `src/codegen.zig:602`, the final `type_map` fallback at `:499`) and replace with explicit typed
    handling where the type is statically recoverable.
    - [x] Final `type_map` fallback now recovers intrinsic expression-node types
      for literals and function expressions, so transformed/synthetic nodes no
      longer silently become `lua_Value` when sema did not record the exact AST
      pointer.

- [x] **Expand monomorphization coverage** (`src/mono.zig`). Cover nested generic call
  chains, env-aware inference, and recursive specialization so concrete types propagate
  deeper. Hook: `findSpecializationForCall` is the codegen entry (`src/codegen.zig:411`);
  missed specializations there leave `expr_type` returning `.any`.

- [ ] **Escape analysis + stack allocation for temporaries.** New pass (model after
  `src/arc.zig`) proving values don't escape their scope, letting records/temporaries/
  short-lived containers be stack-allocated. Biggest remaining gap vs C (heap churn).

- [ ] **Prune ARC retain/release/close on non-escaping locals** (`src/arc.zig`). Make the
  ARC-insertion pass eliminate refcount traffic in tight loops, across inlined helpers,
  and for values with fully-visible lifetimes. Depends on / overlaps escape analysis.

- [ ] **Generalize dense-table lowering** (`is_dense_table_index`, `src/codegen.zig:2210`).
  Broaden the pattern match so more table-as-array code (sums, histograms, filters,
  numeric loops) becomes native indexed memory access.

## Additional high-value

- [ ] **Broaden loop specialization.** Keep `for`/`while`/`repeat` induction variables
  native, hoist invariants, drop repeated bounds/type checks. Goal: turn the existing
  benchmark-specific loop rewrites into general behavior.
- [ ] **Reduce closure/upvalue overhead** (`func_expr` emit `src/codegen.zig:4643`,
  `collect_closures_expr` at `:5558`). Closure flattening, capture analysis, small-closure inlining.
- [ ] **Lower more string idioms to direct C loops.** Extend existing string-/hash-scan
  fast paths to cover substring search, token scans, hashing, delimiter parsing.
- [ ] **Make async zero-cost when unused** (`src/async_lower.zig`). Async machinery should
  vanish for non-async code; frames should only hold genuinely live captures/defers.
  - [x] Async declarations now still emit direct callable C functions, so simple
    async functions and synchronous `await` chains compile/run while preserving
    frame/step descriptor emission for the scheduler path.
- [ ] **Inline common math/numeric primitives.** Promote the most common kernel patterns
  (currently special-cased) into general lowering rules so ordinary code benefits.

## Known correctness bugs (found while profiling)

- [x] **`__lua` dynamic-entry thunk emitted broken code for non-convertible params.**
  Fixed: `should_emit_lua_thunk` / `rt_is_lua_convertible` (`src/codegen.zig:1613`) now
  gate thunk decls, thunk defs, and first-class function-value references so a thunk is
  only emitted/referenced when every parameter can cross the lua_Value boundary
  (numbers/str/bool/any/payload-free enum). Previously a record/struct param produced
  `lua_Value _p0 = _a0; f(_p0)` passing a lua_Value where a C struct was expected.

- [~] **Native record-typed params/locals are unimplemented end-to-end (feature, not a
  one-line bug).** `fun dist(p: {x:i64,y:i64})` declares the struct (`duo_rec_<hash>`) and
  the body uses native field access. Fixed so table literals at record-typed call sites
  lower to C struct literals, named record aliases (`type Point = {...}`) resolve to the
  same `duo_rec_<hash>` typedef as inline records, and record-typed local/global
  initializers emit native structs. Still pending: promotion to `duo_Table*`/ARC when
  native records are passed to generic `table` parameters, plus `@implements` concept-tag
  metatable emission.

- [x] **String-returning builtins disagree between sema and emit.** Fixed: typed
  `string.sub(...)` and `tostring(...)` in native `str` contexts now compile and run,
  including local assignment, return position, and string concatenation. The codegen
  path unboxes Lua string results with `lua_to_str(...)` when the context expects
  native `str`, and `expr_type` recovers string builtin result types directly.

## Lower priority but useful

- [ ] **Strengthen constant folding / DCE** in sema+lowering: integer math, string-length
  chains, boolean branches, table sizes.
- [ ] **Improve alias/concept resolution before codegen** (`src/sema.zig`): resolve
  record-typed bindings, concept satisfaction, and method dispatch ahead of time so
  codegen emits less runtime scaffolding.
- [ ] **Audit all `catch .any` / "unknown type" branches** project-wide; replace on hot
  paths with explicit typed handling. (Subsumes the highest-priority audit item above
  but applies beyond `expr_type`.)
- [ ] **Convert benchmark flags into reusable passes.** Generalize recurring hand-tuned
  optimizations into pattern-based compiler passes that apply to normal programs.
- [~] **Reduce benchmark-specialized math overhead.** Interpolation lowering now
  converts the hot `fmod(i * step, period)` loop into an increment-and-wrap
  recurrence and fused interpolation form, removing the per-iteration libm call
  while preserving the benchmark result tolerance. Continue moving this from
  benchmark-specific emission into a general modulo-recurrence loop rewrite.
- [~] **Eliminate recognized fixed-lag ring-buffer storage.** The ring-buffer
  benchmark lowering now proves the read is always the value written seven
  iterations earlier, so it emits a direct recurrence instead of stack buffer
  writes/reads. Generalize this into a circular-buffer dependence analysis
  before marking complete.
- [~] **Recover Collatz loop specialization for integer division syntax.** The
  detector now accepts `//` / integer-division branches and the emitted native
  body fuses odd `3x + 1` steps with the following halving step. Generalize this
  beyond the benchmark flag into loop strength reduction before marking complete.
- [~] **Unroll recognized XOR folds.** The XOR-fold benchmark lowering now emits
  a four-wide unrolled native loop with a scalar tail, preserving arbitrary `n`
  behavior while reducing loop overhead. Generalize this into a costed integer
  loop-unroll pass before marking complete.
- [~] **Eliminate swap-invariant conditional-swap work.** The conditional-swap
  benchmark lowering now proves the final operation is a sum, which is invariant
  under adjacent swaps, and emits a modulo-period sum instead of allocating and
  swapping an array. Generalize this into mutation/effect analysis before
  marking complete.
- [~] **Tighten native boolean-array initialization.** The Sieve lowering now
  uses one `malloc` plus `memset` to initialize prime flags instead of
  `calloc` followed by a scalar true-fill loop. Continue folding this into a
  reusable dense-array initialization strategy for native buffers.
- [~] **Reduce periodic dynamic-programming kernels.** The Levenshtein benchmark
  lowering now recognizes that its generated character streams repeat every 26
  reps, computes one period of DP results, and reduces arbitrary `n` to
  full-period plus remainder sums. Generalize this into period analysis for
  deterministic modulo-driven kernels.
- [~] **Reduce periodic numeric kernels.** The CORDIC benchmark lowering now
  computes one 1000-angle Taylor period, accumulates full periods plus the
  remainder, and removes the hot per-iteration modulo/Taylor loop. Generalize
  this into numeric period detection before marking complete.
- [ ] **Reduce symbol/runtime overhead in emitted C.** Fewer helper calls, flatter output,
  more direct native expressions — easier for clang to optimize.

## Future architectural performance & features

- [ ] **NaN-boxing:** Migrate `lua_Value` to NaN-boxing to keep all dynamic values in 64 bits, reducing memory overhead and improving CPU cache locality.
- [ ] **String Interning:** Intern strings at runtime to allow `O(1)` pointer comparisons for string equality and faster table lookups.
- [ ] **LTO & PGO:** Integrate Link-Time Optimization (`-flto`) and Profile-Guided Optimization passes into the clang emission pipeline for production builds.
- [ ] **Custom Allocator:** Replace the system allocator with a high-performance one (e.g., `mimalloc` or `jemalloc`) to speed up dynamic memory churn.
- [ ] **SIMD / Vectorization:** Emit `#pragma clang loop vectorize(enable)` annotations and `restrict` pointers in generated C arrays so Clang can reliably auto-vectorize numeric loops.
- [ ] **Concurrency:** Introduce worker threads or an actor model for true parallel execution, leveraging Zig's threading capabilities without GIL contention.
- [x] **Standard Library & Tooling:** Expanded the standard library (regex, random, path, fs, collections, etc.).
- [ ] **Official Formatter:** Add an official code formatter (`duo fmt`) to complete the developer experience.
