# Performance roadmap

Tracking for the codegen/optimization work. Ordered by priority. Each item notes the
relevant code locations so future work can start without re-deriving them.

**Hard constraint:** every change must keep `zig build bench` green (Duo ≥ C on all 40
benchmarks) and `zig build unit-test` at 345/345.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done.

## Highest priority

- [~] **Kill dynamic fallback on hot expressions.** Audit `expr_type` / `emit_expr`
  (`src/codegen.zig:367`, `:3466`) so arithmetic, indexing, field access, and calls stay
  in native typed C instead of falling back to `any`/`lua_Value`.
  - [x] `unop` typing in `expr_type`: `not`→bool, `-x`/`~x`/`#x` stay native when the
    operand is native (`src/codegen.zig:367`). Previously every unary result was `.any`,
    boxing downstream consumers (`arr[-i]`, `(-x)+y`, `#s == n`).
  - [x] **Field access** (`.field`): structural fallback in `expr_type` resolving a
    field's type from the object's `table_type` when `type_map` misses
    (`src/codegen.zig:428`). The common case (sema-typed record bindings) already
    produced native `obj.field`; this closes the gap for monomorphized/generic bodies
    where `type_map` is keyed on the unspecialized expr. Still TODO: named `.@"struct"`
    field lookup (needs a name→fields registry, not just inline `table_type`).
  - [x] **Builtin call results — `math.*`**: `math_call_result_type` (`src/codegen.zig:456`)
    types every recognized `math.*` builtin; `expr_type` uses it to recover a native type
    when sema only tagged the call `.any`. `max`/`min`/`abs` are integer-typed when their
    args are integers and emit native integer ops (`lua_imax_i64`/`lua_imin_i64`/`llabs`);
    the rest are f64. This also **fixed a real codegen bug**: `math.max`/`min`/`abs` in a
    typed integer function emitted a dynamic `lua_Value` (e.g. `lua_math_max`) and then
    `return`ed it from an `int64_t` function — a C compile error. Canonical `clamp`/`imath`
    now compile to clean native ops.
  - [~] **Builtin call results — string/other**: `string.len`/`string.byte` already work
    (sema types them i64 → native `strlen`/byte). But string-*returning* builtins have a
    sema-vs-emit disagreement (see bug below); fix that first, then this item is moot for
    them. Remaining clean adds: nothing pressing once the bug is fixed.
  - [ ] **Audit `catch .any` / `orelse .any` sites** on hot paths (`resolve_type`
    `:411`, the final `type_map.get(e) orelse .any`) and replace with explicit typed
    handling where the type is statically recoverable.

- [ ] **Expand monomorphization coverage** (`src/mono.zig`). Cover nested generic call
  chains, env-aware inference, and recursive specialization so concrete types propagate
  deeper. Hook: `findSpecializationForCall` is the codegen entry (`src/codegen.zig:379`);
  missed specializations there leave `expr_type` returning `.any`.

- [ ] **Escape analysis + stack allocation for temporaries.** New pass (model after
  `src/arc.zig`) proving values don't escape their scope, letting records/temporaries/
  short-lived containers be stack-allocated. Biggest remaining gap vs C (heap churn).

- [ ] **Prune ARC retain/release/close on non-escaping locals** (`src/arc.zig`). Make the
  ARC-insertion pass eliminate refcount traffic in tight loops, across inlined helpers,
  and for values with fully-visible lifetimes. Depends on / overlaps escape analysis.

- [ ] **Generalize dense-table lowering** (`is_dense_table_index`, `src/codegen.zig:373`).
  Broaden the pattern match so more table-as-array code (sums, histograms, filters,
  numeric loops) becomes native indexed memory access.

## Additional high-value

- [ ] **Broaden loop specialization.** Keep `for`/`while`/`repeat` induction variables
  native, hoist invariants, drop repeated bounds/type checks. Goal: turn the existing
  benchmark-specific loop rewrites into general behavior.
- [ ] **Reduce closure/upvalue overhead** (`func_expr` emit `src/codegen.zig:4036`,
  `collect_closures_expr`). Closure flattening, capture analysis, small-closure inlining.
- [ ] **Lower more string idioms to direct C loops.** Extend existing string-/hash-scan
  fast paths to cover substring search, token scans, hashing, delimiter parsing.
- [ ] **Make async zero-cost when unused** (`src/async_lower.zig`). Async machinery should
  vanish for non-async code; frames should only hold genuinely live captures/defers.
- [ ] **Inline common math/numeric primitives.** Promote the most common kernel patterns
  (currently special-cased) into general lowering rules so ordinary code benefits.

## Known correctness bugs (found while profiling)

- [x] **`__lua` dynamic-entry thunk emitted broken code for non-convertible params.**
  Fixed: `should_emit_lua_thunk` / `rt_is_lua_convertible` (`src/codegen.zig:1323`) now
  gate thunk decls, thunk defs, and first-class function-value references so a thunk is
  only emitted/referenced when every parameter can cross the lua_Value boundary
  (numbers/str/bool/any/payload-free enum). Previously a record/struct param produced
  `lua_Value _p0 = _a0; f(_p0)` passing a lua_Value where a C struct was expected.

- [ ] **Native record-typed params/locals are unimplemented end-to-end (feature, not a
  one-line bug).** `fun dist(p: {x:i64,y:i64})` declares the struct (`duo_rec_<hash>`) and
  the body uses native field access, but:
  - call sites pass a `lua_Value` table literal where the C struct is expected
    (`src/codegen.zig:3698` arg loop — needs table-literal→struct-literal coercion);
  - named aliases (`alias Point = {...}`) resolve to an undeclared `duo_Point` C type
    instead of the `duo_rec_<hash>` typedef;
  - record-typed `local`s with table-literal initializers don't emit the struct.
  Idiomatic duo uses `self: any` (dynamic) instead, so this is latent. Completing it is a
  real perf win (native struct passing vs boxed tables) but spans type resolution, struct
  emission, let-binding init, and call-site coercion.

- [ ] **String-returning builtins disagree between sema and emit.** In a typed context
  (`local a = string.sub(s,1,3)` where `a`/return is `str`), sema types the result `str`
  (C `const char*`) but emission lowers `string.sub` to `lua_str_sub(...)` which returns a
  `lua_Value` → `const char* a = <lua_Value>` compile error. Also `tostring(x)` in the
  typed path emits a bare `tostring(...)` (undefined C symbol) instead of the runtime call.
  Repro: `fun f(s: str): str local a = string.sub(s,1,3); local b = tostring(42); return a .. b end`.
  Fix options: make the string builtins emit `const char*` natively, or have sema type
  them as the dynamic `lua_Value` type to match the emit. Affects heavily-used string code,
  so needs care + the benchmark gate. (`string.len`/`string.byte`/`#` are unaffected.)

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
- [ ] **Reduce symbol/runtime overhead in emitted C.** Fewer helper calls, flatter output,
  more direct native expressions — easier for clang to optimize.

## Future architectural performance & features

- [ ] **NaN-boxing:** Migrate `lua_Value` to NaN-boxing to keep all dynamic values in 64 bits, reducing memory overhead and improving CPU cache locality.
- [ ] **String Interning:** Intern strings at runtime to allow `O(1)` pointer comparisons for string equality and faster table lookups.
- [ ] **LTO & PGO:** Integrate Link-Time Optimization (`-flto`) and Profile-Guided Optimization passes into the clang emission pipeline for production builds.
- [ ] **Custom Allocator:** Replace the system allocator with a high-performance one (e.g., `mimalloc` or `jemalloc`) to speed up dynamic memory churn.
- [ ] **SIMD / Vectorization:** Emit `#pragma clang loop vectorize(enable)` annotations and `restrict` pointers in generated C arrays so Clang can reliably auto-vectorize numeric loops.
- [ ] **Concurrency:** Introduce worker threads or an actor model for true parallel execution, leveraging Zig's threading capabilities without GIL contention.
- [ ] **Standard Library & Tooling:** Expand the standard library (networking, regex, etc.) and add an official code formatter (`duo fmt`) to complete the developer experience.
