# Generics, Async, and Metaprogramming Implementation Plan

> **For Codex:** Execute this plan task-by-task, keeping tests and roadmap status synchronized.

**Goal:** Complete Duo's remaining generics, executable async/await, and deterministic hygienic metaprogramming implementation.

**Architecture:** Add total structural generic substitution and concrete named-type specializations; replace async descriptor skeletons with pollable frames and runtime tasks; introduce a compiler-owned compile-time evaluator and macro expansion pass before semantic analysis.

**Tech Stack:** Zig compiler passes and tests, generated C11 runtime/codegen, Duo integration fixtures, mdBook documentation.

---

### Task 1: Total generic structural inference

**Files:** `src/mono.zig`, `src/types.zig`

- Add failing unit tests for nested generic applications, function types,
  records, nested generic call chains, and recursive specialization reuse.
- Extend substitution, unification, canonical hashing, and environment-aware
  argument inference across every `TypeExpr`/`ResolvedType` carrier.
- Diagnose unresolved concrete type arguments rather than specializing as
  `any`.
- Run focused monomorphizer tests.

### Task 2: Concrete generic enum/type emission

**Files:** `src/sema.zig`, `src/mono.zig`, `src/codegen.zig`

- Add failing tests for two concrete instantiations of a payloaded generic enum
  and deduplication of repeated instantiations.
- Record named generic type applications and canonical concrete identities.
- Emit substituted enum payload layouts and route constructors/matches through
  concrete names.
- Validate constraints at instantiation and test diagnostics.

### Task 3: Async runtime contract

**Files:** `src/async_lower.zig`, `src/codegen.zig`, runtime support in `src/codegen.zig`

- Add generated-C tests for task header, typed frame, wrapper, step, poll,
  cancellation, and destruction hooks.
- Define task status/error/cancellation ownership and emit helpers only when an
  async function is present.
- Replace descriptor-only frame fields with child/result/error/cleanup state.

### Task 4: Executable straight-line await/resume

**Files:** `src/async_lower.zig`, `src/codegen.zig`, integration fixtures

- Add compile-and-run tests for immediate completion, one suspension, multiple
  awaits, and generic async functions.
- Partition straight-line bodies into executable state segments.
- Emit wrappers that initialize frames and step functions that create/poll child
  tasks without repeating pre-await work.
- Reject unsupported suspension shapes with precise diagnostics until Task 5
  handles them.

### Task 5: Async control flow, errors, and cancellation

**Files:** `src/async_lower.zig`, `src/codegen.zig`, concurrent stdlib/runtime tests

- Add failing tests for awaits in conditionals/loops/matches, failure
  propagation, already-cancelled await, and LIFO defer cleanup.
- Lower structured control flow into explicit states.
- Propagate task errors/cancellation and run active cleanup exactly once.
- Integrate cooperative scheduling and channel wakeups; retain explicit
  diagnostics for threaded/WASM-invalid combinations.

### Task 6: Deterministic compile-time evaluator

**Files:** new `src/comptime.zig`, `src/main.zig`, `src/sema.zig`, `src/codegen.zig`

- Add evaluator unit tests for literals, pure operations, bindings,
  conditionals, bounded loops/functions, limits, and forbidden effects.
- Implement compile-time values, environment, evaluator, diagnostics, and AST
  literal replacement.
- Route `##expr` and `__constexpr(expr)` through the evaluator and remove
  codegen's literal-only special case.

### Task 7: Quote, unquote, macros, and hygiene

**Files:** `src/ast.zig`, `src/lexer.zig`, `src/parser.zig`, new `src/macro_expand.zig`, `src/main.zig`

- Add parser/expander tests for quote/unquote, fixed-point expansion, deliberate
  capture, accidental-capture prevention, recursion limits, and dual-span
  diagnostics.
- Add AST syntax contexts and compiler-owned quoted AST values.
- Invoke `__macroexpand(node, ctx)` before sema and validate expanded AST.

### Task 8: Reflection and derive

**Files:** compile-time context modules, `src/sema.zig`, `lib/std/meta.duo`, `lib/std/meta/*`

- Add tests for declaration/type metadata and derived enum/record behavior.
- Expose read-only type metadata and implement `@derive` through normal macro
  expansion and semantic checking.
- Replace misleading runtime-only meta helpers with compiler-backed APIs and
  document unsupported reflection explicitly if any remains.

### Task 9: Cross-feature verification and status synchronization

**Files:** `.kiro/specs/duo-language-spec/tasks.md`, `docs/perf-todo.md`, `docs/src/roadmap.md`, async/generic/meta docs and examples

- Run focused Zig tests after each task, then `zig build test --summary all`.
- Compile/run cross-feature fixtures and inspect generated C under strict C11
  warnings.
- Run `zig build bench` for compiler/runtime-sensitive changes; report measured
  results only.
- Update status ledgers and user docs to match precisely what tests establish.
