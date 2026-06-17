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
  - [ ] **Builtin call results**: `expr_type` only types mono-specialized name calls
    (`:375`). Type known stdlib/math builtins (`math.floor`/`math.sqrt`/`math.abs` → f64
    or i64, `string.len` → i64, etc.) so chained math stays native.
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

- [ ] **Record-typed function params break the `__lua` wrapper.** A `fun f(p: {x:i64,...})`
  generates `dist__lua(lua_Value _a0)` with `lua_Value _p0 = _a0; int64_t _r = dist(_p0);`
  — passing a `lua_Value` where the C struct param is expected, which fails to compile.
  Repro: `fun dist(p: {x:i64,y:i64}): i64 ... end`. The dynamic-entry wrapper needs to
  unbox the record (or skip generating `__lua` for non-native param types).

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
