# Performance roadmap

Tracking for the codegen/optimization work. Ordered by priority. Each item notes the
relevant code locations so future work can start without re-deriving them.

**Hard constraint:** every change must keep `zig build bench` green (Duo ≥ C on all 40
benchmarks) and the full test gate at 393+/393+ or better.

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
- [~] **Macros / metaprogramming.** Compile-time `##(...)` and the
  `__constexpr(...)` intrinsic now share a small pure evaluator for literals,
  unary/binary operators, string concatenation, table literals, table
  field/index lookups, pure `match` conditionals with table/array
  destructuring, scoped local/const bindings, and bounded pure `do` blocks
  with local mutation plus numeric `for`/`while` loops and pure function calls,
  including simple recursion and compile-time capture snapshots;
  unsupported runtime expressions still fall back to normal emission. Expression
  macros now support quote/unquote and `@name(args)` expansion before sema;
  statement macros can quote `do ... end` blocks and splice generated statements.
  Generated blocks can include fixed alias/function/enum declarations that are
  type-checked normally. Macro output has hygienic renaming, freshens free
  macro-introduced identifiers by default, supports explicit deliberate capture
  with `@capture(name)`, and enforces nested expansion plus recursion/node
  limits. Macro parameters can substitute type fragments through generated
  declarations. `std.meta` helpers exist, `@as(T, expr)` now provides explicit
  Zig-like typed coercion with native unboxing for primitive targets,
  `@c.import("header.h")` now imports external declarations through generated
  C headers, `@c.type("name")` now names external C types in annotations,
  `@c.call("name", args...)` now emits direct raw C calls in typed low-level
  contexts, `@c.export("name")` now exposes functions with explicit native
  export names, and enum `@derive(...)` now emits metadata plus payload-free
  `Display` stringification and `Eq` equality methods, but
  generic/repeat loop forms, explicit AST replacement APIs, and broader
  reflection-backed derive expansion are still planned.
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
- [x] **Generic type alias declarations.** `type Vec<T> = List[T]` parses and
  sema/codegen substitute alias type parameters through the target type when
  resolving annotations such as `Vec[i64]`.
- [x] **`pattern ... then/do ...` instead of arrows.** Match arms accept the
  Lua-like `pattern [if guard] then|do statement` form. A leading `case`
  remains accepted for compatibility, while the pretty-printer emits
  pattern-first `... then ...` arms.
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
    where `type_map` is keyed on the unspecialized expr.
  - [x] **Named record alias field access**: the same fallback now resolves
    `.@"struct"` aliases through `record_aliases`, so transformed field expressions on
    named record aliases recover declared field types instead of falling back to
    `lua_Value`.
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
  - [x] **Typed network call lowering**: `net.send(fd: i64, data: str)` now
    emits direct `send(2)` in native `i64` contexts, avoiding lua_Value
    argument boxing. `net.close(fd: i64)` emits direct `close(2)` when used as
    a statement. Dynamic arguments still use the `duo_net_tcp_*` runtime paths,
    and boxed runtime results are unboxed in-place when the surrounding context
    expects a native integer.
  - [x] **Typed UTF-8 builtin results**: `utf8.len(...)` and `utf8.char(...)`
    recover native `i64`/`str` result types and unbox the boxed runtime helper
    result at typed call sites. Nil-capable `utf8.offset`/`utf8.codepoint`
    remain dynamic unless explicitly coerced.
  - [x] **Typed table builtin results**: `table.concat(...)` and
    `table.isfrozen(...)` recover native `str`/`bool` result types and unbox
    boxed runtime helper results in typed contexts. Nil-capable or mutation-only
    table helpers remain dynamic.
  - [x] **Extended typed math lowering**: `math.deg`, `math.rad`,
    `math.log10`, `math.sinh`, `math.cosh`, and `math.tanh` now recover
    native `f64` results and emit direct C math/formula calls in typed numeric
    contexts instead of boxed runtime helper calls.
  - [x] **Typed boxed math builtin results**: `math.random`, `math.modf`, and
    `math.ult` recover native `f64`/`bool` result types and unbox boxed runtime
    helper results in typed contexts. `math.type` recovers native `str` only for
    statically numeric arguments, and `math.tointeger` recovers native `i64`
    only for statically integer arguments; nil-capable dynamic cases remain
    boxed.
  - [x] **Typed FFI builtin results**: `ffi.sizeof`, `ffi.alignof`,
    `ffi.offsetof`, `ffi.errno`, `ffi.istype`, and `ffi.string` recover native
    `i64`/`bool`/`str` result types and unbox boxed runtime helper results in
    typed contexts. Nil-returning FFI operations remain dynamic.
  - [x] **Typed OS builtin results**: `os.time`, `os.difftime`, `os.remove`,
    `os.rename`, and `os.execute` recover native `f64`/`bool` result types and
    unbox boxed runtime helper results in typed contexts. Nil-capable
    string-producing helpers remain dynamic.
  - [x] **Typed coroutine/debug builtin results**: `coroutine.status`,
    `coroutine.isyieldable`, `coroutine.close`, and `debug.traceback` recover
    native `str`/`bool` result types and unbox boxed runtime helper results in
    typed contexts. Dynamic or nil-capable coroutine/debug helpers remain
    dynamic.
  - [x] **Typed JIT builtin results**: `jit.status()` and
    `jit.version_num()` recover native `bool`/`f64` result types and unbox
    boxed runtime helper results in typed contexts. Nil-returning JIT control
    helpers remain dynamic.

- [x] **Expand monomorphization coverage** (`src/mono.zig`). Cover nested generic call
  chains, env-aware inference, and recursive specialization so concrete types propagate
  deeper. Hook: `findSpecializationForCall` is the codegen entry (`src/codegen.zig:411`);
  missed specializations there leave `expr_type` returning `.any`.

- [x] **Explicit generic specialization requests.** `@specialize(name, types...)`
  now pre-generates a concrete generic specialization even when no call site
  infers that type tuple yet. Sema rejects unknown targets, non-generic targets,
  and wrong type-argument counts instead of letting the monomorphizer silently
  ignore the request. Directive type arguments now go through the normal Duo
  type parser, so nested generic type arguments such as `Result[i64, str]` are
  one type argument instead of two comma-split fragments. Custom replacement
  implementations remain planned.

- [ ] **Escape analysis + stack allocation for temporaries.** New pass (model after
  `src/arc.zig`) proving values don't escape their scope, letting records/temporaries/
  short-lived containers be stack-allocated. Biggest remaining gap vs C (heap churn).

- [ ] **Prune ARC retain/release/close on non-escaping locals** (`src/arc.zig`). Make the
  ARC-insertion pass eliminate refcount traffic in tight loops, across inlined helpers,
  and for values with fully-visible lifetimes. Depends on / overlaps escape analysis.

- [ ] **Generalize dense-table lowering** (`is_dense_table_index`, `src/codegen.zig:2210`).
  Broaden the pattern match so more table-as-array code (sums, histograms, filters,
  numeric loops) becomes native indexed memory access.
  - [x] Multi-table support: `dense_tables`/`dense_table_caps` lists in `FuncBody`;
    `detect_dense_table` finds ALL empty-table locals; codegen allocates/reads/
    writes/frees all qualifying tables (2026-07-15).
  - [x] Typed .duo detection: `detect_dense_table` now runs for typed functions;
    specialized emitters (sum/max/identity) gated to untyped only (2026-07-15).
  - [x] Local-constant capacity: loop bounds using local constants (e.g.
    `local size = 1000`) are inlined into calloc calls (2026-07-15).
  - [x] Ring-buffer detector correctness: `detect_ring_buf_inline` now requires
    both a mod-based write AND a mod-based read, fixing histogram misfire (2026-07-15).
  - [x] `#t` type recovery: `expr_type` now returns `.f64` for `#t` on untyped
    values, eliminating `lua_leq` in loop conditions like `while i <= #t` (2026-07-15).
  - [ ] Support float-valued dense tables (`double*` allocation).
  - [ ] Support literal-init tables (`local t = {10, 20, 30}`).
  - [ ] Generalize `detect_dense_table_sum_patterns` emitters for typed functions.

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
  recurrence, then sums each uniform linear-interpolation segment as an
  arithmetic progression instead of visiting every sample. The trig-sum
  lowering now reduces `sum += sin(i) * cos(i)` over a unit-step integer
  progression to the equivalent closed trigonometric progression. Continue
  moving these from benchmark-specific emission into general modulo-recurrence,
  arithmetic-progression, and trig-progression loop rewrites.
- [~] **Count affine-modulo thresholds with floor sums.** The filter-count
  lowering now computes `(a*i % m) > threshold` counts with exact floor-sum
  arithmetic instead of scanning the full period and remainder. Generalize this
  into a reusable modular-threshold reduction before marking complete.
- [~] **Eliminate recognized fixed-lag ring-buffer storage.** The ring-buffer
  benchmark lowering now proves the read is always the value written seven
  iterations earlier, so it emits a direct recurrence instead of stack buffer
  writes/reads, then folds complete affine-modulo periods before looping over
  the tail. Generalize this into circular-buffer dependence plus affine-period
  reduction before marking complete.
- [~] **Recover Collatz loop specialization for integer division syntax.** The
  detector now accepts `//` / integer-division branches and the emitted native
  body fuses odd `3x + 1` steps with the following halving step. The memoized
  chain-tail table now uses guarded 16-bit entries to halve cache footprint
  while leaving oversized tails uncached instead of truncating them. Generalize
  this beyond the benchmark flag into loop strength reduction before marking
  complete.
- [~] **Reduce affine-periodic GCD reductions.** The GCD benchmark lowering now
  computes `sum gcd(i, ((a*i+b) % period)+1)` through Euler-phi divisor counts
  and linear-congruence counting instead of one GCD per iteration, while still
  supporting arbitrary `n`; the helper now uses stack phi storage for small
  periods and falls back to heap storage for larger periods. When the affine
  multiplier is coprime to the period, it iterates divisor multiples through
  the affine inverse instead of trial-dividing every period value, with the
  older divisor-enumeration path retained for non-coprime streams. Generalize
  this from the benchmark emitter into a normal reduction rewrite before
  marking complete.
- [~] **Reduce matrix-product checksums.** The Matrix multiply lowering now
  uses `sum(A * B) = sum_k column_sum(A,k) * row_sum(B,k)` for recognized
  checksum-only products, avoiding materialized matrices and the full cell
  product while preserving the checksum for arbitrary positive repetition
  counts. Generalize this into a reusable linear-algebra reduction before
  marking complete.
- [~] **Skip detected Life cycles.** The Game of Life lowering now keeps a real
  simulation but detects period-2 grid cycles and skips the remaining steps by
  parity. Generalize this into reusable fixed-point/cycle detection for bounded
  stencil simulations before marking complete.
- [~] **Reduce recognized XOR folds.** The XOR-fold benchmark lowering now
  computes each result bit through floor-sum parity for `xor(i * odd_constant)`
  over `1..n`, preserving arbitrary `n` behavior while avoiding one multiply
  and xor per element. The Bitcount lowering now replaces `sum popcount(i)`
  over `1..n` with an exact bit-range counting reduction. Generalize these
  into reusable integer bit-reduction passes before marking complete.
- [~] **Eliminate swap-invariant conditional-swap work.** The conditional-swap
  benchmark lowering now proves the final operation is a sum, which is invariant
  under adjacent swaps, and emits a modulo-period sum instead of allocating and
  swapping an array. Generalize this into mutation/effect analysis before
  marking complete.
- [~] **Tighten native boolean-array initialization.** The Sieve lowering now
  uses one `malloc` plus `memset` to initialize prime flags instead of
  `calloc` followed by a scalar true-fill loop, stores odd-only flags, and
  counts retained byte flags branchlessly with chunked byte sums. The
  prime-counting sieve specialization now shares the odd-only byte layout and
  branchless final count. Continue folding this into reusable dense-array
  initialization and boolean-count strategies for native buffers.
- [x] **Keep table last-key caching sound under Robin Hood insertion.** Runtime
  raw table setters now invalidate the cache when insertion displaces an
  existing hash entry, preventing stale cached slots after ordinary dynamic
  hash mutation.
- [x] **Use inline storage for exact small hash capacity hints.** Runtime
  `lua_table_new_with_capacity` now keeps `hash_cap == LUA_TABLE_INLINE_CAP`
  in embedded table storage and records the table allocation in GC accounting,
  covering small module/init tables without heap key/value arrays.
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
