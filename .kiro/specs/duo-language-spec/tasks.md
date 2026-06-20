# Implementation Plan: Duo Language Spec

## Overview

This plan implements the full Duo language specification in a bottom-up order: lexer extensions → AST additions → parser enhancements → type system expansion → semantic analysis upgrades → new compiler passes (monomorphization, ARC insertion, async lowering) → codegen extensions → runtime library → standard library modules → CLI updates. Each task builds incrementally on previous work, with property-based tests validating correctness properties from the design document.

### Key design decision: implicit records (no `struct`/`class` keyword)

Duo deliberately omits the `struct` and `class` keywords. All composite data is a Lua table; a static shape is given by an inline record-type annotation on a binding (`local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }`). Concept satisfaction is declared via the `@implements(...)` attribute on a binding, not on a type declaration. Error handling is untyped — `try/catch` has no `catch ErrorType e` form; error discrimination is done inside the body by reading `e.__tag`. These rules are normative; tasks below reflect them.

## Tasks

- [x] 1. Extend the Lexer with Duo tokens
  - [x] 1.1 Add new token kinds to `src/lexer.zig`
    - Add `at` (`@`), `question` (`?`), `bang` (`!`), `fat_arrow` (`=>`) token kinds to `TokenKind` enum
    - Add contextual keyword tokens: `kw_match`, `kw_try`, `kw_catch`, `kw_defer`, `kw_async`, `kw_await`, `kw_concept`
    - Update `spelling()` method for all new tokens
    - Update `lookup_kw()` to recognize `match`, `try`, `catch`, `defer`, `async`, `await`, `concept` as keywords
    - Update `next_tok()` to lex `@`, `?`, `!`, and `=>` characters
    - _Requirements: 23.1, 23.4, 23.5, 23.6, 23.7, 23.8_

  - [x] 1.2 Write property test for lexer round-trip (Property 15: `in` disambiguation)
    - **Property 15: `in` Operator Disambiguation**
    - Generate token sequences with `in` in for-loop headers vs expression contexts; verify the lexer emits `kw_in` in both cases (disambiguation is a parser concern, not lexer)
    - **Validates: Requirements 23.10**

  - [x] 1.3 Write unit tests for new lexer tokens
    - Test each new token kind is lexed correctly from source text
    - Test contextual keywords are recognized
    - Test `@`, `?`, `!`, `=>` operators are emitted
    - _Requirements: 23.1_

- [x] 2. Extend the AST with Duo node types
  - [x] 2.1 Add new statement nodes to `src/ast.zig`
    - Add `match_stmt: MatchExpr` variant to `Stmt` union
    - Add `try_stmt: TryStmt` variant
    - Add `defer_stmt: DeferStmt` variant
    - Add `enum_def: EnumDef` variant (extend existing `kw_enum` handling)
    - Add `concept_def: ConceptDef` variant
    - Define `MatchExpr`, `MatchArm`, `Pattern`, `TryStmt`, `CatchClause`, `DeferStmt`, `EnumDef`, `EnumVariant`, `Attribute`, `ConceptDef` structs as specified in the design
    - **CatchClause**: remove the `error_type` field — catch clauses are untyped, only carry a binding
    - **There is no `struct_def` variant and no `StructDefPayload` struct.** Records are anonymous; their shape is captured by the type-literal annotation on a binding and stored on the binding's `LocalName`/parameter annotation, not on a statement node
    - _Requirements: 5.1, 6.1, 8.1, 15.1, 23.4, 23.5, 23.8_

  - [x] 2.2 Add new expression nodes to `src/ast.zig`
    - Add `try_expr` (postfix `?`), `unwrap_expr` (postfix `!`), `match_expr`, `await_expr`, `contains_expr` (`x in y`) variants to `Expr` union
    - Update `Expr.loc()` to handle new variants
    - _Requirements: 9.1, 9.4, 14.10, 19.2, 23.6, 23.10_

  - [x] 2.3 Add `BinOp.contains` variant for `in` operator
    - Extend `BinOp` enum with a `contains` variant
    - _Requirements: 14.10, 23.10_

- [x] 3. Extend the Parser for Duo grammar
  - [x] 3.1 Implement `match` statement/expression parsing in `src/parser.zig`
    - Parse `match expr` followed by Lua-like `case pattern [if guard] then|do body` arms
    - Continue accepting legacy `pattern [if guard] => body` arms for source compatibility
    - Parse patterns: literal, binding, variant, table/array destructuring, rest (`...name`), wildcard (`_`)
    - Parse optional guard expressions (`if cond`)
    - _Requirements: 6.1, 6.3, 6.6, 7.1, 7.2, 7.3, 23.4_

  - [x] 3.2 Implement `try`/`catch`/`defer` parsing in `src/parser.zig`
    - Parse `try` block followed by zero or more `catch` clauses
    - **Catch clauses are untyped**: `catch e` only. There is no `catch MyError e` form. If a name follows `catch` it's always the binding; if the body uses a structured error, dispatch is done with `match e.__tag` inside the catch body
    - Parse standalone `defer` statements
    - _Requirements: 8.1, 8.2, 8.3, 23.5_

  - [x] 3.3 Implement `async`/`await` parsing in `src/parser.zig`
    - Parse `async` function declarations (modifier before `fun`/`function`)
    - Parse `await` as a prefix unary operator on expressions
    - _Requirements: 19.1, 19.2, 23.6_

  - [x] 3.4 Implement attribute parsing in `src/parser.zig`
    - Parse `@name` and `@name(args)` annotations before declarations
    - Store attributes on `FuncDecl`, `EnumDef`, `ConceptDef`
    - `@implements(Concept1, Concept2)` is a binding-level attribute; it attaches to a `local`/`global` declaration and is stored alongside the binding's type-literal annotation
    - _Requirements: 18.1–18.13, 23.7_

  - [x] 3.5 Implement enum declaration parsing in `src/parser.zig`
    - Parse `enum Name ... end` with variant cases and optional payloads
    - Parse generic type parameters on enums
    - _Requirements: 5.1, 23.8_

  - [x] 3.6 Implement concept declaration parsing in `src/parser.zig`
    - Parse `concept Name ... end` with required methods and fields
    - _Requirements: 15.1, 23.3_

  - [x] 3.7 Implement `in` operator disambiguation in `src/parser.zig`
    - In `parse_for()`, `in` after variable list is always the loop keyword (already correct)
    - In `parse_prec()`, add `kw_in` as an infix operator with precedence between comparison and bitwise (left=5, right=5), producing `contains_expr` or `BinOp.contains`
    - _Requirements: 23.10_

  - [x] 3.8 Implement postfix `?` and `!` operator parsing
    - In `parse_suffixed_expr()`, after primary expression, check for `?` or `!` tokens
    - Produce `try_expr` for `?` and `unwrap_expr` for `!`
    - _Requirements: 9.1, 9.4, 2.6_

  - [x] 3.9 Implement optional `then` in conditionals
    - In `parse_if()`, make `then` keyword optional (accept both `if cond then` and `if cond` followed by block)
    - _Requirements: 1.5, 1.6_

  - [x] 3.10 Write property test for statement-style call equivalence (Property 2)
    - **Property 2: Statement-Style Call Equivalence**
    - Generate random function names and argument lists; verify `f a1, a2, ..., aN` parses identically to `f(a1, a2, ..., aN)`
    - **Validates: Requirements 2.1, 2.2**

  - [x] 3.11 Write property test for `in` disambiguation (Property 15)
    - **Property 15: `in` Operator Disambiguation**
    - Generate for-loop headers with `in` and expression contexts with `in`; verify correct parsing in each context
    - **Validates: Requirements 23.10**

  - [x] 3.12 Add record-type annotation to type expressions in `src/parser.zig` and `src/ast.zig`
    - Extend `TypeExpr` with a `record` variant carrying a slice of `RecordField { name: []const u8, typ: TypeExpr }`
    - Parse `{ name: T, name2: T2, ... }` as a type literal wherever a `TypeExpr` is expected
    - This is the only mechanism for declaring typed records in Duo
    - _Requirements: 3.7_

- [x] 4. Checkpoint - Lexer, AST, and Parser
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Extend the Type System
  - [x] 5.1 Add new type variants to `src/types.zig`
    - Add `result: struct { ok: *ResolvedType, err: *ResolvedType }` variant
    - Add `option: *ResolvedType` variant
    - Add `enum_type: struct { name: []const u8, variants: []EnumVariantType }` variant
    - Add `channel: struct { elem: *ResolvedType, capacity: ?usize }` variant
    - Add `generic_param: struct { name: []const u8, constraint: ?[]const u8 }` variant
    - Add `table_type: struct { fields: []FieldType }` variant
    - Add `instantiated: struct { base: *ResolvedType, args: []ResolvedType, specialization_key: u64 }` variant
    - Update `eql()`, `is_native()`, `c_type()`, and `format()` for all new variants
    - _Requirements: 3.6, 4.1, 5.1, 9.1, 19.3_

  - [x] 5.2 Add concept registry data structures
    - Define `ConceptInfo` struct with required methods and fields
    - Add concept storage to `Sema` (or a separate registry)
    - _Requirements: 15.1, 15.2_

  - [x] 5.3 Write property test for type annotation enforcement (Property 4)
    - **Property 4: Type Annotation Enforcement**
    - Generate (type annotation, expression type) pairs; verify type checker accepts matching pairs and rejects mismatches
    - **Validates: Requirements 3.1, 3.4**

  - [x] 5.4 Write property test for type inference soundness (Property 5)
    - **Property 5: Type Inference Soundness**
    - Generate typed expressions without annotations; verify inferred types match expected (int_lit→i64, float_lit→f64, string_lit→str, bool_lit→bool)
    - **Validates: Requirements 3.2, 3.5**

- [ ] 6. Extend Semantic Analysis
  - [x] 6.1 Implement Duo scoping rules in `src/sema.zig`
    - In `.duo` mode, bare assignment at new-binding position creates a local (already partially implemented — verify and complete)
    - Ensure `local` keyword is still accepted as valid (Lua compatibility) — both `local x = 1` and bare `x = 1` create local bindings
    - Implement `global` keyword for module-scope bindings
    - Ensure `let` is NOT recognized as a keyword
    - _Requirements: 1.3, 1.4, 1.7, 1.8_

  - [x] 6.2 Implement type checking for `match` and exhaustiveness
    - Type-check match scrutinee and arms
    - Implement exhaustiveness checker: verify all enum variants are covered or a wildcard is present
    - Emit compile-time error listing uncovered variants
    - _Requirements: 5.5, 6.2, 6.4, 6.5_

  - [x] 6.3 Implement type checking for `try`/`catch`/`defer`
    - Validate `?` operator is only used in functions with result-compatible return type
    - Validate `!` operator is rejected in `@nopanic` functions
    - **Catch clauses are untyped** — no error-type lookup is performed. The binding (if any) is defined in the catch scope with type `any` (errors are tables, statically unknown). User code uses `match`/`if` on `e.__tag` inside the body
    - _Requirements: 8.2, 8.3, 9.2, 9.7, 9.8_

  - [x] 6.4 Implement concept satisfaction checking on `@implements` bindings
    - When a binding is annotated with `@implements(Concept1, ...)`, the Type_Checker resolves the binding's record-type annotation against each concept's required members
    - The binding's initializer is checked for the corresponding field/method definitions
    - Emit clear error on unsatisfied concepts listing each missing member, with the binding's location
    - _Requirements: 15.2, 15.4_

  - [x] 6.5 Implement generic constraint validation
    - At instantiation sites, verify type arguments satisfy declared constraints
    - Track instantiation sites for the monomorphizer
    - _Requirements: 4.2, 4.3_

  - [x] 6.6 Implement overload resolution
    - When multiple functions share a name, select based on argument types
    - Emit ambiguity error when multiple overloads match equally
    - _Requirements: 12.1, 12.4, 12.5_

  - [x] 6.7 Implement attribute validation
    - Validate `@nopanic` functions don't use `!` operator
    - Validate `@arc(false)` types (only valid on table-typed bindings and record-type annotations)
    - Validate `@deprecated` emits warnings at use sites
    - Validate `@implements` is only attached to bindings whose annotation is a record type
    - _Requirements: 18.1–18.10_

  - [x] 6.8 Write property test for scoping invariant (Property 3)
    - **Property 3: Scoping Invariant**
    - Generate identifiers in `.duo` mode; verify bare assignment creates local, `global` creates module-global
    - **Validates: Requirements 1.3, 1.4**

  - [x] 6.9 Write property test for match exhaustiveness (Property 7)
    - **Property 7: Match Exhaustiveness**
    - Generate enums with N variants and partial matches; verify compiler emits error for missing cases
    - **Validates: Requirements 5.5, 6.2**

  - [x] 6.10 Write property test for concept constraint checking (Property 14)
    - **Property 14: Concept Constraint Checking**
    - Generate bindings with `@implements(Concept)` and varying field sets; verify acceptance iff all members provided
    - **Validates: Requirements 15.1, 15.2, 15.4**

- [x] 7. Checkpoint - Type System and Semantic Analysis
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement Monomorphizer (`src/mono.zig`)
  - [x] 8.1 Create `src/mono.zig` with Monomorphizer struct
    - Define `SpecKey` (generic_id + type_args_hash) and `SpecRequest` types
    - Implement specialization cache (`std.HashMap(SpecKey, *ast.FuncBody)`)
    - Implement work queue for iterative fixed-point expansion
    - _Requirements: 4.1, 4.3_

  - [x] 8.2 Implement generic specialization logic
    - Walk typed AST collecting instantiation sites
    - For each unique (generic_def, type_args) pair, record a specialization with a deterministic mangled name
    - Store a total type-parameter substitution map for the template body; codegen resolves type parameters through that map instead of requiring an eager deep AST clone
    - Scan specialized bodies for new instantiation sites (fixed-point iteration)
    - _Requirements: 4.1, 4.4_

  - [x] 8.3 Integrate monomorphizer into the pipeline (`src/main.zig`)
    - Call monomorphizer after sema, before codegen
    - Pass specialization metadata to codegen
    - _Requirements: 4.1, 24.2_

  - [x] 8.4 Write property test for monomorphization uniqueness (Property 6)
    - **Property 6: Monomorphization Uniqueness**
    - Generate generic functions with various type arg combinations; verify distinct args → distinct specializations, identical args → reuse
    - **Validates: Requirements 4.1, 4.3**

- [x] 9. Implement ARC Insertion Pass (`src/arc.zig`)
  - [x] 9.1 Create `src/arc.zig` with ARC annotation pass
    - Define ARC annotation types (retain, release, close)
    - Walk typed AST identifying heap-allocated values (tables, closures, strings, enum payloads)
    - Skip primitive types (int, float, bool) and `@arc(false)` types
    - _Requirements: 26.1, 26.8_

  - [x] 9.2 Implement retain/release insertion logic
    - Insert `duo_retain` at assignment and capture sites
    - Insert `duo_release` at scope exit, reassignment, and drop points
    - Insert `duo_close` before `duo_release` when `__close` is defined
    - _Requirements: 26.1, 26.2, 26.5_

  - [x] 9.3 Implement cycle collector registration
    - Identify objects that could form cycles (tables with table-valued fields)
    - Mark them for cycle collector registration in generated code
    - _Requirements: 26.3, 26.4_

  - [x] 9.4 Integrate ARC pass into the pipeline
    - Call ARC insertion after monomorphization, before codegen
    - _Requirements: 26.1_

  - [x] 9.5 Write property test for ARC refcount correctness (Property 13)
    - **Property 13: ARC Refcount Correctness**
    - Generate sequences of assignments and scope exits; verify refcount reaches zero iff no live reference exists
    - **Validates: Requirements 26.1, 26.2**

- [x] 10. Implement Async Lowering Pass (`src/async_lower.zig`)
  - [x] 10.1 Create `src/async_lower.zig` with async state machine transformation
    - Define frame struct generation (state field, result, captured locals)
    - Identify `await` points as state boundaries
    - Generate step function with switch on state
    - _Requirements: 19.1, 24.5_

  - [x] 10.2 Implement task cancellation and defer cleanup
    - When a task is cancelled at an await point, execute pending defers in LIFO order
    - _Requirements: 19.9, 19.10_

  - [x] 10.3 Integrate async lowering into the pipeline
    - Call async lowering after ARC insertion, before codegen
    - Validate WASM + threads → compile error
    - _Requirements: 19.1, 25.4_

- [x] 11. Checkpoint - New Compiler Passes
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 12. Extend Code Generator
  - [-] 12.1 Implement monomorphized generic emission in `src/codegen.zig`
    - Emit one C function per specialization with mangled name (e.g., `duo_Vec_i32_push`)
    - Emit one C struct per specialized generic type
    - **Status**: generic function specializations are emitted and call sites dispatch to their mangled concrete functions. Structural substitution/unification now covers generic applications, functions, and records; nested and recursive calls inherit concrete parameter/local types without stray `any` specializations. Generic enum annotations emit one canonical, deduplicated concrete payload struct per type-argument tuple. Constructor/match coverage for every generic enum shape and constraint-driven specialization hooks remain pending.
    - _Requirements: 24.2, 4.1_

  - [x] 12.2 Implement `defer` lowering in codegen
    - At every scope exit (return, error, break), emit deferred blocks in LIFO order
    - Handle multiple defers per scope
    - **Status**: `defer ... end` bodies are registered per-scope (a `defer_scopes`
      stack parallel to `local_scopes`) and flushed in LIFO order at normal block
      exit (`emit_top_defers`) and before early `return` (`emit_all_pending_defers`,
      innermost scope first). Defer-free code emits byte-identical C (guarded by
      `has_pending_defers`), so benchmarks are unaffected. Loop `break` flushes
      defers for the exited loop-body scopes without flushing outer function
      defers. Verified by `examples/duo/defer.duo` and a break/defer smoke run.
    - _Requirements: 8.4, 8.5, 24.4_

  - [-] 12.3 Implement ARC code emission
    - Emit `duo_retain(ptr)` / `duo_release(ptr)` / `duo_close(ptr)` calls based on ARC annotations
    - Emit `duo_ObjHeader` for heap-allocated objects
    - **Status**: generated C now includes `duo_ObjHeader` plus `duo_retain`,
      `duo_release`, and `duo_close` runtime hooks. Codegen emits retain on
      pointer-shaped heap locals/globals, release/close at scope exit, and
      release-before/retain-after for simple name reassignment. Full runtime
      refcount semantics and embedding headers into every heap object remain
      pending under the runtime ARC task.
    - _Requirements: 26.1, 26.2, 26.5, 24.3_

  - [-] 12.4 Implement async state machine emission
    - Emit frame struct typedefs per async function
    - Emit step functions with `switch (frame->state)` pattern
    - Emit `DUO_POLL_PENDING` / `DUO_POLL_READY` returns
    - **Status**: codegen now emits `duo_Poll`, one frame typedef per lowered
      async function, and a step-function skeleton with `switch
      (frame->state)`, await-state cases, `DUO_POLL_PENDING`, and
      `DUO_POLL_READY`. Normal function-body emission is skipped for async
      declarations so `await` placeholders do not leak into C. Generated async
      support now also has a type-erased task lifecycle ABI, cancellation/error
      and owned-child frame state, idempotent cancellation propagation, and
      child polling with pending/error/ready propagation. Creating child tasks,
      executing body segments, result transfer, and scheduler integration remain
      pending.
    - _Requirements: 19.1, 24.5_

  - [-] 12.5 Implement match compilation in codegen
    - Compile match expressions to nested if/switch in C
    - Generate tag comparisons for enum matches
    - Bind destructured variables
    - **Status**: match lowers to a chained `if/else if` over the scrutinee
      (GNU statement-expression so it works in both statement and expression
      position). The scrutinee is bound with its concrete C type (no GNU `auto`).
      Wildcard (`_`), literal, binding, and enum-variant patterns generate the
      right conditions; variant patterns emit `==` (payload-free enums) or
      `.tag ==` (payloaded). Binding patterns, including payload bindings such
      as `Maybe.Some(x)`, are emitted as arm-local C declarations before guards
      and body statements. Non-exhaustive fall-through calls `lua_error`.
      Pending: table/array destructuring. Verified by
      `examples/duo/enum_match.duo` and a payload enum smoke.
    - _Requirements: 6.1, 6.3, 6.6_

  - [-] 12.6 Implement enum representation in codegen
    - Emit tagged union structs for enum types
    - Emit tag constants and payload access
    - **Status**: `emit_enum_decls` emits, per enum, either a plain C `enum`
      (`typedef enum { duo_<E>_<V> = i, ... } duo_<E>;`) when no variant carries a
      payload, or a tagged struct (`int tag` + a `union` of payload structs, with
      `#define duo_<E>_tag_<V>` constants) otherwise. `enum_has_payload` records
      the representation; `enum_name_of`/`enum_is_payload_free` let the rest of
      codegen recognize enums (named types resolve to `.@"struct"` at codegen
      time). Variant value expressions (`Color.Green`), match conditions, and the
      `lua_Value`↔enum thunk conversions all handle the payload-free case.
      Payloaded variant constructors such as `Maybe.Some(42)` now emit tagged
      struct literals with union payload initializers, and payload fields can be
      accessed through match payload bindings. Pending: direct/general payload
      field access helpers outside match binding.
    - _Requirements: 5.1, 5.2, 5.3_

  - [x] 12.6a Implement anonymous record (table-type literal) codegen
    - When a binding is annotated with a `{ field: T, ... }` record type, mint a fresh C `struct` (deterministic name from a content hash) and use it as the binding's storage
    - Deduplicate by content hash so two structurally-equivalent records share one C struct declaration
    - Field access compiles to plain `struct.field` reads/writes (no `__index` chain) for typed bindings
    - When a record-typed value is assigned to a generic `table` parameter, promote to `duo_Table*` and switch to ARC
    - Generate concept tags onto the table's metatable for `@implements`-annotated bindings
    - **Status**: content-hash dedup + struct typedef (`ensure_record_decl`) are in
      place, and record-typed bindings initialized from a table literal now emit a
      designated-initializer C struct literal (`emit_record_initializer`, wired at
      local/global declarations and record-typed call arguments) with field access
      lowering to plain `s.field`. Named record aliases such as
      `type Point = { x: i64, y: i64 }` lower to the same content-hashed record
      typedef as inline record annotations. Verified by
      `examples/native_record_params.duo` and `examples/layout_attrs_test.duo`.
      Pending (separate follow-ups): promotion to `duo_Table*`/ARC when passed to a
      generic `table` parameter, and `@implements` concept-tag metatable emission.
    - _Requirements: 3.7, 11.4, 15.4_

  - [x] 12.7 Implement closure representation in codegen
    - Emit `duo_closure_N` structs with captured variable pointers
    - Emit `duo_retain`/`duo_release` for closure objects
    - _Requirements: 10.2, 10.3, 10.4, 24.3_

  - [-] 12.8 Implement attribute-driven C output
    - `@inline` → `static inline __attribute__((always_inline))`
    - `@noinline` → `__attribute__((noinline))`
    - `@cold` → `__attribute__((cold))`
    - `@hot` → `__attribute__((hot))`
    - `@packed` → `__attribute__((packed))`
    - `@align(N)` → `__attribute__((aligned(N)))`
    - `@ffi("C_name")` → use specified C identifier
    - **Status**: function declarations/definitions now emit `@inline`,
      `@noinline`, `@cold`, and `@hot` as GCC attributes, with `@noinline`
      suppressing the default typed-function `static inline`. `@ffi("C_name")`
      now changes the generated C symbol and call sites consistently.
      `@packed`/`@align(N)` now lower onto record and enum typedefs, including
      record-typed local/global bindings initialized from table literals.
      Pending: type-level `@ffi`.
    - _Requirements: 18.1–18.8, 21.1_

  - [x] 12.9 Write property test for valid C output (Property 11)
    - **Property 11: Codegen Produces Valid C**
    - Generate fully-typed Duo modules; verify generated C compiles under `clang -Wall -Wextra -pedantic -std=c11`
    - **Status**: `scripts/test_property_11.sh` now generates multiple
      fully-typed modules covering arithmetic, branches, loops, native strings,
      record globals/locals, and bitwise expressions, then syntax-checks the
      generated C with clang.
    - **Validates: Requirements 24.1, 24.6**

  - [x] 12.10 Write property test for bitwise operation correctness (Property 12)
    - **Property 12: Bitwise Operation Correctness**
    - Generate random i64 pairs; compile and run Duo bitwise ops; compare results with expected C semantics
    - **Status**: `scripts/test_property_12.sh` generates deterministic random
      signed `i64` pairs for `&`, `|`, binary `~`, unary `~`, and defined
      shift cases, then diffs `duo run` output against a generated C oracle.
    - **Validates: Requirements 13.1, 13.2, 13.3**

- [ ] 13. Checkpoint - Code Generator Extensions
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. Implement Runtime Library
  - [ ] 14.1 Create `src/runtime/value.h` — Dynamic value representation
    - Define `lua_Value` tagged union (nil, bool, number, string, table, closure, userdata)
    - Implement value creation macros and type checking
    - _Requirements: 3.6, 16.1_

  - [ ] 14.2 Create `src/runtime/arc.h` — Reference counting and cycle collector
    - Define `duo_ObjHeader` struct (refcount, flags, type_tag)
    - Implement `duo_retain()`, `duo_release()`, `duo_close()` macros/functions
    - Implement incremental cycle collector with configurable pause threshold
    - Implement `__gc` finalizer invocation during cycle collection (Lua 5.5 compatibility)
    - _Requirements: 26.1, 26.2, 26.3, 26.4, 26.5, 26.6_

  - [ ] 14.3 Create `src/runtime/table.h` — Table and metatable operations
    - Implement table creation, get/set, hash map internals
    - Implement metatable attachment and metamethod lookup
    - Implement `__index` chain resolution for prototype-based inheritance
    - _Requirements: 11.1, 11.2, 11.3, 14.1, 14.2_

  - [ ] 14.4 Create `src/runtime/string.h` — Immutable string with interning
    - Implement ARC-managed strings with `duo_ObjHeader`
    - Implement string interning for deduplication
    - Implement hash caching for table key usage
    - _Requirements: 26.1_

  - [ ] 14.5 Create `src/runtime/error.h` — Error types and panic support
    - Implement `duo_panic(msg)` with stack trace and exit(1)
    - Implement result type support (`duo_Result_T_E`, `duo_Option_T`)
    - Implement `__try` and `__unwrap` runtime hooks
    - _Requirements: 8.1, 9.1, 9.4, 9.5_

  - [ ] 14.6 Create `src/runtime/scheduler.h` — Task scheduler
    - Implement single-threaded cooperative event loop (default mode)
    - Implement ready/suspended task queues
    - Implement task polling and state transitions
    - Implement work-stealing thread pool for `@concurrent("threaded")` mode
    - _Requirements: 19.1, 19.2, 19.7, 19.8_

  - [ ] 14.7 Create `src/runtime/channel.h` — Typed bounded channels
    - Implement bounded channel with send/receive
    - Suspend sender when full, receiver when empty
    - Thread-safe when in threaded mode
    - _Requirements: 19.3, 19.4, 19.5_

  - [ ] 14.8 Write property test for defer LIFO ordering (Property 8)
    - **Property 8: Defer LIFO Ordering**
    - Generate scopes with 1–10 defer statements; verify execution order is reverse of declaration
    - **Validates: Requirements 8.4, 8.5**

  - [ ] 14.9 Write property test for result operator semantics (Property 9)
    - **Property 9: Result Operator Semantics**
    - Generate result-compatible values (success/error); verify `?` unwraps success and propagates error
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.7**

  - [ ] 14.10 Write property test for closure shared capture (Property 10)
    - **Property 10: Closure Shared Capture**
    - Generate nested functions that capture and mutate variables; verify mutations are visible through closures
    - **Validates: Requirements 10.2, 10.3, 10.4**

- [ ] 15. Checkpoint - Runtime Library
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 16. Implement Standard Library Modules
  - [ ] 16.1 Create `src/runtime/modules/path.zig` (or C header) — Path manipulation
    - Implement join, resolve, basename, dirname, extension
    - _Requirements: 20.1_

  - [ ] 16.2 Create `src/runtime/modules/fs.zig` — File system operations
    - Implement read, write, mkdir, remove, stat, walk
    - _Requirements: 20.2_

  - [ ] 16.3 Create `src/runtime/modules/process.zig` — Process management
    - Implement spawn, wait, kill, pipe stdin/stdout/stderr
    - _Requirements: 20.3_

  - [ ] 16.4 Create `src/runtime/modules/env.zig` — Environment variables
    - Implement get/set environment variables
    - _Requirements: 20.4_

  - [ ] 16.5 Create `src/runtime/modules/net.zig` — TCP/UDP sockets
    - Implement listen, connect, send, receive, close
    - _Requirements: 20.5_

  - [ ] 16.6 Create `src/runtime/modules/json.zig` — JSON serialization
    - Implement encode/decode between Duo tables and JSON
    - _Requirements: 20.6_

  - [ ] 16.7 Create `src/runtime/modules/time.zig` — Time operations
    - Implement measurement, formatting, parsing, sleeping
    - _Requirements: 20.7_

  - [ ] 16.8 Create `src/runtime/modules/log.zig` — Structured logging
    - Implement debug, info, warn, error severity levels
    - _Requirements: 20.8_

  - [ ] 16.9 Create `src/runtime/modules/concurrent.zig` — Concurrency primitives
    - Export channel and async primitives for user code
    - _Requirements: 20.9_

- [ ] 17. Update CLI and Module Resolution
  - [ ] 17.1 Update `src/main.zig` CLI commands
    - Add `duo build` as alias for `compile`
    - Ensure `duo run` and `duo check` work with new pipeline phases
    - Add `--threads` flag for multi-threaded scheduler mode
    - Validate WASM + `--threads` → compile error
    - _Requirements: 25.4, 28.4, 28.5, 28.6_

  - [ ] 17.2 Implement module resolution in sema/resolver
    - Implement `req "name"` search order: local project → dependencies → stdlib
    - Implement relative path resolution (`req "./util"`)
    - Detect and report circular imports
    - _Requirements: 27.1, 27.2, 27.3, 27.4_

  - [ ] 17.3 Update `build.zig` for new modules
    - Add `src/mono.zig`, `src/arc.zig`, `src/async_lower.zig` to compilation
    - Add runtime library C headers to include path for generated code
    - Update test targets to include new property test file
    - _Requirements: 24.1_

- [ ] 18. Implement Pretty Printer and Parser Round-Trip
  - [ ] 18.1 Create `src/pretty.zig` — AST pretty printer
    - Implement formatting for all AST node types back to valid Duo source
    - Handle indentation, operator precedence parenthesization, and keyword output
    - Support both Duo syntax (bare locals, `fun`, optional `then`) and Lua syntax
    - _Requirements: 23.11_

  - [ ] 18.2 Write property test for parser round-trip (Property 1)
    - **Property 1: Parser Round-Trip**
    - Generate random valid ASTs; pretty-print → parse → compare for equivalence
    - **Validates: Requirements 23.11, 23.12**

- [ ] 19. Checkpoint - Full Pipeline Integration
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 20. Integration Tests and Final Validation
  - [ ] 20.1 Create compile-and-run integration tests
    - Write example `.duo` programs exercising generics, match, try/catch, defer, async/await
    - Compile each to C and verify successful compilation + expected output
    - _Requirements: 24.1, 24.6, 29.1_

  - [ ] 20.2 Create WASM target validation tests
    - Compile example programs with `--target wasm32-wasi`
    - Validate output with wasmtime
    - Verify `--threads` + WASM → compile error
    - _Requirements: 25.1, 25.4, 25.5_

  - [ ] 20.3 Create compile-fail tests for error diagnostics
    - Test type mismatch errors include expected/actual types
    - Test exhaustiveness errors list missing variants
    - Test concept constraint errors list missing members
    - Test `?` in non-result function → error
    - Test `!` in `@nopanic` function → error
    - _Requirements: 28.1, 28.2, 31.1, 31.2, 31.3_

  - [ ] 20.4 Create performance validation tests
    - Benchmark fibonacci, matrix multiply against hand-written C (within 10%)
    - Verify monomorphized generics have zero overhead vs manual specialization
    - _Requirements: 29.1, 29.2, 29.3_

- [ ] 21. Final checkpoint - All tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The implementation language is Zig, matching the existing codebase
- Property tests should be added to `src/property_tests.zig` using Zig's `std.Random` for generation with minimum 100 iterations per property
- Runtime library files are C headers (`.h`) that get `#include`d by generated C code

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "2.2", "2.3"] },
    { "id": 1, "tasks": ["1.2", "1.3", "3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8", "3.9", "3.12"] },
    { "id": 2, "tasks": ["3.10", "3.11", "5.1", "5.2"] },
    { "id": 3, "tasks": ["5.3", "5.4", "6.1", "6.2", "6.3", "6.4", "6.5", "6.6", "6.7"] },
    { "id": 4, "tasks": ["6.8", "6.9", "6.10", "8.1"] },
    { "id": 5, "tasks": ["8.2", "9.1", "10.1"] },
    { "id": 6, "tasks": ["8.3", "8.4", "9.2", "9.3", "10.2"] },
    { "id": 7, "tasks": ["9.4", "9.5", "10.3"] },
    { "id": 8, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5", "12.6", "12.6a", "12.7", "12.8"] },
    { "id": 9, "tasks": ["12.9", "12.10", "14.1", "14.2", "14.4"] },
    { "id": 10, "tasks": ["14.3", "14.5", "14.6", "14.7"] },
    { "id": 11, "tasks": ["14.8", "14.9", "14.10", "16.1", "16.2", "16.3", "16.4", "16.5", "16.6", "16.7", "16.8", "16.9"] },
    { "id": 12, "tasks": ["17.1", "17.2", "17.3", "18.1"] },
    { "id": 13, "tasks": ["18.2", "20.1", "20.2", "20.3", "20.4"] }
  ]
}
```
