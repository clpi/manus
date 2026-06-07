# Requirements Document

## Introduction

Duo is a programming language that is a superset of Lua 5.5, designed for high-performance systems programming with shell-script ergonomics. It compiles ahead-of-time to C (and optionally to WASM via wasi-sdk), providing zero-cost abstractions while maintaining Lua's familiar syntax. Duo reduces verbosity, adds a static type system (dynamic when needed), introduces structured error handling, generics, concurrency primitives, an expanded standard library, and rich metaprogramming capabilities. Every valid Lua 5.5 program is expressible in Duo.

Duo deliberately omits the `struct` and `class` keywords; all composite data is a Lua table, and a typed shape is given via an inline record-type annotation on a binding (e.g. `local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }`). OO-style objects are just table literals with method fields. Concept satisfaction is declared via the `@implements(...)` attribute on a binding, not on a type declaration. Error handling uses an untyped `try/catch` form — there is no `catch ErrorType e` syntax; error discrimination is done by reading `__tag` inside the catch body.

**Lua compatibility note:** This specification tracks Lua 5.5 (work branch). The normative reference is the Lua 5.5 work-tree as of commit `lua/lua@v5.5-work.2` (or the first release candidate, whichever is published first). Any feature gated behind a subsequent work-tree commit that is later removed before final release SHALL be re-evaluated for inclusion. The "all Lua 5.5 standard metamethods" list in Requirement 14.1 is pinned to the metamethod set present at that reference point.

**No `struct` keyword, no `class` keyword.** Duo deliberately omits the `struct` and `class` keywords. All composite data is a Lua table. To attach a static shape to a value, the user annotates the binding with an inline record type (`{ field: T, ... }`); to attach behavior, the user attaches methods as table fields. This is the only way to declare a typed record in Duo. There is no `record`, `type`, or `data` keyword either — type names are not first-class declarations.

## Glossary

- **Compiler**: The Duo ahead-of-time compiler that translates Duo source code to C (which can then be compiled to native or WASM via wasi-sdk)
- **Parser**: The component that reads Duo source text and produces an abstract syntax tree (AST)
- **Pretty_Printer**: The component that formats a Duo AST back into valid Duo source text
- **Type_Checker**: The component that performs static type analysis on the AST
- **Resolver**: The component that resolves variable scoping, overloads, and generics
- **Codegen**: The component that generates C code from the typed AST
- **Runtime**: The minimal runtime support library linked into compiled Duo programs
- **Scheduler**: The component within the Runtime that manages concurrent task execution
- **Module**: A Duo source file, which is implicitly a closure returning its exports
- **Table**: The fundamental composite data structure in Duo, also usable as a class. There is no `class` keyword; OO-style objects are just table literals with method fields, optionally annotated with a record type and `@implements(...)`.
- **Metatable**: A table attached to another table that defines operator and protocol behavior
- **Metamethod**: A function stored in a metatable under a reserved key (e.g., `__index`) that customizes operator or protocol behavior
- **Concept**: A named set of constraints (required methods and fields) that a type must satisfy
- **ADT**: Algebraic Data Type, a type composed of variant cases (sum type)
- **Channel**: A typed, bounded conduit for communication between concurrent tasks
- **FFI**: Foreign Function Interface for calling C functions and being called from C
- **Attribute**: A compile-time annotation (e.g., `@inline`) attached to a function, type, or field
- **ARC**: Automatic Reference Counting, the primary memory management strategy for heap-allocated values
- **Cycle_Collector**: A supplementary component that detects and reclaims reference cycles
- **wasi-sdk**: The toolchain used to compile generated C code to WASM/WASI targets

## Requirements

---

### Requirement 1: Keyword Aliases and Reduced Verbosity

**User Story:** As a developer, I want shorter keyword aliases for common constructs, so that I can write concise code without sacrificing readability.

#### Acceptance Criteria

1. WHEN the Parser encounters the keyword `fun`, THE Parser SHALL treat it as semantically identical to `function`
2. WHEN the Parser encounters the keyword `req`, THE Parser SHALL treat it as semantically identical to `require`
3. WHEN the Parser encounters a variable declaration without the `global` keyword, THE Resolver SHALL treat the binding as local-scoped; no `let`, `local`, or other binding keyword is required — bare assignment at declaration position creates a local binding
4. WHEN the Parser encounters the `global` keyword before a declaration, THE Resolver SHALL treat the binding as module-global-scoped
5. WHEN the Parser encounters a conditional without the `then` keyword, THE Parser SHALL accept the conditional as valid syntax
6. WHEN the Parser encounters a conditional with the `then` keyword, THE Parser SHALL accept the conditional as valid syntax
7. THE Parser SHALL NOT recognize `let` as a keyword; `let` is NOT a reserved word in Duo
8. THE Parser SHALL continue to recognize `local` as a valid keyword for Lua compatibility; `local x = 1` and bare `x = 1` (at declaration position) are both valid and produce local-scoped bindings

---

### Requirement 2: Statement-Style Function Calls (Nim-style)

**User Story:** As a developer, I want to call functions using space-separated arguments without parentheses, so that I get shell-like ergonomics for command-style invocations.

#### Acceptance Criteria

1. WHEN the Parser encounters a function identifier at statement position followed by expressions separated by commas without parentheses (e.g., `f a, b, c`), THE Parser SHALL parse it as equivalent to `f(a, b, c)`
2. WHEN the Parser encounters a function call written with parentheses (e.g., `f(a, b, c)`), THE Parser SHALL parse it as a standard parenthesized call
3. WHEN a statement-style call is nested as an argument (e.g., `f g x`), THE Parser SHALL parse it as `f(g(x))` following left-to-right application
4. WHEN ambiguity arises between a statement-style call and an expression, THE Parser SHALL prefer the parenthesized interpretation
5. WHEN a statement-style argument list is followed by a newline or semicolon, THE Parser SHALL terminate the argument list at that boundary
6. WHEN a statement-style argument contains a postfix operator (`?` or `!`), THE Parser SHALL bind the operator to the immediately preceding expression, not to the entire call
7. WHEN a statement-style argument contains a binary operator (e.g., `f a & b`), THE Parser SHALL require parentheses around the binary expression; bare binary operators SHALL terminate the argument list, so `f a & b` is parsed as `(f(a)) & b`

---

### Requirement 3: Type System — Static and Dynamic Typing

**User Story:** As a developer, I want a type system that is static when possible and dynamic when needed, so that I get compile-time safety without losing Lua's flexibility.

#### Acceptance Criteria

1. WHEN a variable declaration includes a type annotation, THE Type_Checker SHALL enforce that annotation at compile time
2. WHEN a variable declaration omits a type annotation and the initializer has a statically known type, THE Type_Checker SHALL infer the type
3. WHEN a variable is annotated as `any`, THE Type_Checker SHALL defer all type checks on that variable to runtime
4. WHEN a function signature includes parameter types, THE Type_Checker SHALL verify argument types at each call site
5. WHEN the Type_Checker cannot infer a type and no annotation is provided, THE Type_Checker SHALL assign the `any` type and emit a diagnostic warning
6. THE Type_Checker SHALL support primitive types: `nil`, `bool`, `int`, `float`, `string`, `table`, `function`, and `any`
7. THE Type_Checker SHALL support **anonymous record types** as type annotations: `{ name: str, age: i64, items: []str }`. Record types are structural: two records with identical field sets are interchangeable, regardless of source position
8. THE Type_Checker SHALL recognize the `option` and `result` types declared in the standard library (`Option[T]`, `Result[T, E]`) and any type with the `__try` metamethod as result-compatible for the `?` operator

---

### Requirement 4: Generics

**User Story:** As a developer, I want generic types and functions, so that I can write reusable, type-safe abstractions without runtime overhead.

#### Acceptance Criteria

1. WHEN a function or type is declared with type parameters, THE Compiler SHALL monomorphize each unique instantiation into a separate specialization
2. WHEN a generic type parameter has a constraint (via `__implements` or `__satisfies`), THE Type_Checker SHALL verify the constraint at instantiation
3. WHEN a generic type is instantiated, THE Compiler SHALL use `__generic_id` or `__typekey` for stable specialization caching
4. WHEN `__specialize(T, args...)` is defined on a generic type, THE Compiler SHALL invoke it to control instantiation behavior
5. WHEN a generic type defines `__static_index`, THE Runtime SHALL use it to resolve static member reads on the generic type itself
6. WHEN a generic type defines `__static_newindex`, THE Runtime SHALL use it to resolve static member writes on the generic type itself

---

### Requirement 5: Enums and Algebraic Data Types

**User Story:** As a developer, I want enums and sum types with associated data, so that I can model domain concepts precisely and safely.

#### Acceptance Criteria

1. WHEN an enum is declared with variant cases, THE Parser SHALL parse each case and optional associated payload
2. WHEN `__enum_cases()` or `__variants()` is called on an enum type, THE Runtime SHALL return the list of variant cases
3. WHEN `__payload()` or `__destructure()` is called on an enum value, THE Runtime SHALL return the associated data for that variant
4. WHEN `__derive(trait)` is specified on an enum, THE Compiler SHALL generate the trait implementation based on the type's structure (as defined in Requirement 22)
5. THE Type_Checker SHALL verify that match expressions on enum types are exhaustive (as defined in Requirement 6)

---

### Requirement 6: Match Semantics

**User Story:** As a developer, I want pattern matching with exhaustiveness checking, so that I can write clear, safe control flow over structured data.

#### Acceptance Criteria

1. WHEN a `match` expression is encountered, THE Parser SHALL parse the scrutinee and each arm's pattern and body
2. WHEN all variant cases of an enum are not covered by match arms, THE Type_Checker SHALL emit a compile-time error listing the missing cases
3. WHEN a match arm includes a guard condition, THE Codegen SHALL evaluate the guard after pattern binding succeeds
4. WHEN a type defines `__tag` (as defined in Requirement 14), THE Runtime SHALL use it to determine which match arm to select
5. WHEN a type defines `__match` (as defined in Requirement 14), THE Runtime SHALL invoke it to perform user-defined pattern matching logic
6. WHEN a match arm uses destructuring, THE Resolver SHALL bind the destructured variables in the arm's scope

---

### Requirement 7: Destructuring

**User Story:** As a developer, I want destructuring assignments and bindings, so that I can extract values from tables and tuples concisely.

#### Acceptance Criteria

1. WHEN a binding uses table destructuring syntax (e.g., `{a, b} = t`), THE Parser SHALL parse it as individual local bindings from the table's fields
2. WHEN a binding uses array destructuring syntax (e.g., `[x, y] = arr`), THE Parser SHALL parse it as positional local bindings from indices 1..N
3. WHEN a destructuring pattern includes a rest element (e.g., `{a, ...rest} = t`), THE Parser SHALL capture remaining fields or elements into the rest variable
4. WHEN a destructured field is not present in the source value, THE Runtime SHALL assign `nil` to that binding
5. WHEN destructuring is used in function parameters, THE Parser SHALL treat it as equivalent to a local destructuring of the parameter

---

### Requirement 8: Error Handling — try/catch/defer

**User Story:** As a developer, I want structured error handling with resource cleanup, so that I can write robust code without manual error propagation.

#### Acceptance Criteria

1. WHEN a `try` block is entered, THE Runtime SHALL capture any error raised within it
2. WHEN an error is raised inside a `try` block and a matching `catch` clause exists, THE Runtime SHALL transfer control to that `catch` clause
3. WHEN a `catch` clause names a binding, THE Runtime SHALL bind the caught error value to that name for the duration of the catch body; the error value is a table (any user-constructed shape)
4. WHEN no `catch` clause is present and an error is raised, THE Runtime SHALL run pending `defer` blocks in LIFO order and propagate the error up the call stack
5. WHEN a `defer` statement is encountered, THE Runtime SHALL execute the deferred expression when the enclosing scope exits, regardless of whether an error occurred
6. WHEN multiple `defer` statements exist in a scope, THE Runtime SHALL execute them in reverse order of declaration (LIFO)
7. WHEN a value with `__close` defined in its metatable goes out of scope, THE Runtime SHALL invoke `__close` as part of deferred cleanup (as defined in Requirement 14)
8. **There is no typed `catch ErrorType e` syntax.** All errors are tables; user code that needs to discriminate error kinds does so by reading `e.__tag` (a string) and switching with `match` / `if`. The `try/catch` mechanism is structural, not nominal.

---

### Requirement 9: Result-Type Semantics and the `?` / `!` Operators

**User Story:** As a developer, I want concise optional/result propagation, so that I can handle errors without verbose boilerplate.

#### Acceptance Criteria

1. THE Type_Checker SHALL recognize any type implementing the `__try` metamethod as a result-compatible type; additionally, the standard library SHALL provide built-in `Result[T, E]` and `Option[T]` generic types that implement `__try` and `__unwrap`
2. WHEN the `?` operator is applied to a result-compatible value where `__try` returns an error indicator, THE Runtime SHALL propagate the error to the calling function's result
3. WHEN the `?` operator is applied to a result-compatible value where `__try` returns a success value, THE Runtime SHALL unwrap and return that value
4. WHEN the `!` operator is applied to a result-compatible value containing a success, THE Runtime SHALL unwrap and return the value
5. WHEN the `!` operator is applied to a result-compatible value containing an error, THE Runtime SHALL panic with the error
6. WHEN `__unwrap` is defined on a value's metatable (as defined in Requirement 14), THE Runtime SHALL invoke it when the `!` operator is applied
7. IF the `?` operator is used inside a function whose return type does not implement `__try` (i.e., is not result-compatible), THEN THE Type_Checker SHALL emit a compile-time error indicating that error propagation requires a result-compatible return type
8. IF the `!` operator is used inside a function annotated `@nopanic`, THEN THE Type_Checker SHALL emit a compile-time error

---

### Requirement 10: Closures and Scoping

**User Story:** As a developer, I want first-class closures with proper lexical scoping, so that I can capture and use variables from enclosing scopes.

#### Acceptance Criteria

1. THE Compiler SHALL treat every Duo source file as a closure that returns its exports
2. WHEN a function references a variable from an enclosing scope, THE Compiler SHALL capture that variable in the function's closure environment
3. WHEN a captured variable is mutated in the enclosing scope after closure creation, THE Runtime SHALL ensure the closure observes the mutation (shared capture semantics)
4. WHEN a closure is returned from its enclosing function, THE Runtime SHALL keep captured variables alive for the lifetime of the closure via ARC (as defined in Requirement 26)

---

### Requirement 11: Inheritance and Table-as-Class

**User Story:** As a developer, I want every table to be usable as a class with inheritance, so that I can use object-oriented patterns naturally.

#### Acceptance Criteria

1. WHEN a table is assigned a metatable with an `__index` pointing to another table, THE Runtime SHALL resolve field lookups through the prototype chain
2. WHEN a method is called on a table that does not define it, THE Runtime SHALL traverse the metatable chain to find the method
3. WHEN a child table overrides a method from its parent metatable, THE Runtime SHALL invoke the child's version
4. A "table definition" in the OO sense is just a binding whose initializer is a table literal whose annotation is a `{ field: T, ... }` record type. There is no `class` or `struct` keyword; declaring an OO-style object is done with:
   ```duo
   local Counter: { count: i64, inc: () -> void } = {
       count = 0,
       inc = function() self.count = self.count + 1 end,
   }
   ```
5. WHEN `private` is specified on a field of a record type annotation (e.g. `{ name: str, @private id: i64 }`), THE Type_Checker SHALL enforce at compile time that only methods defined in the same initializer may access that field
6. IF a `private` member is accessed from outside its declaring initializer, THEN THE Type_Checker SHALL emit a compile-time error naming the inaccessible member

---

### Requirement 12: Function Overloading

**User Story:** As a developer, I want to define multiple functions with the same name but different signatures, so that I can provide clean APIs with type-specific behavior.

#### Acceptance Criteria

1. WHEN multiple functions share the same name with different parameter types, THE Resolver SHALL select the correct overload based on argument types at the call site
2. WHEN `__overload(signature, fn)` is defined, THE Resolver SHALL register the function as an overload candidate
3. WHEN `__resolve_overload(callsiteInfo)` is defined, THE Resolver SHALL invoke it to perform user-defined overload resolution
4. WHEN no overload matches the argument types, THE Type_Checker SHALL emit a compile-time error listing the available overloads and the provided argument types
5. WHEN multiple overloads match equally well, THE Type_Checker SHALL emit an ambiguity error listing the conflicting candidates

---

### Requirement 13: Bitwise Operations

**User Story:** As a developer, I want bitwise operators with metatable overridability, so that I can perform low-level bit manipulation and define custom bitwise behavior.

#### Acceptance Criteria

1. THE Parser SHALL recognize bitwise operators: `&` (band), `|` (bor), `~` (binary xor when infix), `~` (unary bitwise-not when prefix), `<<` (shl), `>>` (shr)
2. WHEN a bitwise operator is applied to integer operands, THE Codegen SHALL emit the corresponding C bitwise operation
3. WHEN a bitwise operator is applied to a value whose metatable defines the corresponding metamethod (`__band`, `__bor`, `__bxor`, `__bnot`, `__shl`, `__shr`), THE Runtime SHALL invoke that metamethod (as defined in Requirement 14)

---

### Requirement 14: Metatables — Normative Metamethod Definitions

**User Story:** As a developer, I want a comprehensive and extensible metamethod system, so that I can customize all aspects of type behavior in a single, consistent mechanism.

#### Acceptance Criteria

**Standard Lua 5.5 metamethods (all preserved):**

1. THE Runtime SHALL support all Lua 5.5 standard metamethods: `__index`, `__newindex`, `__call`, `__len`, `__tostring`, `__concat`, `__eq`, `__lt`, `__le`, `__add`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`, `__unm`, `__idiv`, `__gc`
2. WHEN any standard metamethod is defined on a value's metatable, THE Runtime SHALL invoke it according to Lua 5.5 semantics
3. WHEN `__gc` is defined on a value's metatable, THE Runtime SHALL invoke it during garbage collection / cycle collection as per Lua 5.5 semantics; `__close` (see below) is the PREFERRED deterministic cleanup mechanism, but `__gc` remains supported for Lua compatibility

**Duo-extended metamethods (operator/protocol hooks — compile-time and reflection hooks are defined in Reqs 4, 15–17, 22):**

4. WHEN `__iter` is defined on a metatable, THE Runtime SHALL use it to provide custom iteration in `for` loops, returning an iterator function
5. WHEN `__hash` is defined on a metatable, THE Runtime SHALL use it to compute hash values when the value is used as a table key
6. WHEN `__close` is defined on a metatable, THE Runtime SHALL invoke it when the value goes out of scope, during `defer` cleanup, or on early return from a result-type expression
7. WHEN `__tag` is defined on a metatable, THE Runtime SHALL return its value for match discrimination, error-type identification, and `__typeof` tag queries
8. WHEN `__try` is defined on a metatable, THE Runtime SHALL invoke it when the `?` operator is applied to the value
9. WHEN `__unwrap` is defined on a metatable, THE Runtime SHALL invoke it when the `!` operator is applied to the value
10. WHEN `__contains` is defined on a metatable, THE Runtime SHALL invoke it to evaluate `x in y` expressions, returning a boolean
11. WHEN `__match` is defined on a metatable, THE Runtime SHALL invoke it during pattern matching to perform user-defined match logic, receiving the pattern and returning matched bindings or nil
12. WHEN `__cast(toType, value)` is defined on a metatable, THE Runtime SHALL invoke it for explicit cast operations on values of that type

**Bitwise metamethods:**

13. WHEN `__band`, `__bor`, `__bxor`, `__bnot`, `__shl`, or `__shr` is defined on a metatable, THE Runtime SHALL invoke the corresponding metamethod for bitwise operations on values of that type

**Static member metamethods:**

14. WHEN `__static_index` is defined on a metatable, THE Runtime SHALL use it to resolve reads on the type object itself (not instances)
15. WHEN `__static_newindex` is defined on a metatable, THE Runtime SHALL use it to resolve writes on the type object itself

---

### Requirement 15: Constraints and Concepts

**User Story:** As a developer, I want to define named constraints on types, so that generic code can require specific capabilities and produce clear error messages.

#### Acceptance Criteria

1. WHEN a concept is defined, THE Type_Checker SHALL record the set of required methods and fields with their expected signatures
2. WHEN a binding is annotated with `@implements(concept)` (or `@implements(C1, C2, ...)`), THE Type_Checker SHALL verify that the binding's record-type annotation provides all required members of each named concept, and the binding's initializer is checked for the corresponding field/method definitions
3. Generic type parameters continue to use `__implements` / `__satisfies` for constraint syntax (e.g., `function f<T: __implements(Hashable)>(x: T)`) — these are still recognised by the Type_Checker
4. WHEN `__concepts()` is called on a table value, THE Runtime SHALL return the set of concept tags the value was declared with via `@implements(...)`
5. WHEN a generic constraint is not met at instantiation, THE Type_Checker SHALL emit an error naming the unsatisfied concept, the type that failed, and each missing or incompatible member
6. **There is no `struct X implements Y` form** — concepts attach to values through `@implements` attribute annotations, not to type declarations. Type declarations do not exist; only record-type annotations on bindings do.

---

### Requirement 16: Reflection and Introspection

**User Story:** As a developer, I want runtime and compile-time reflection, so that I can inspect types, fields, methods, and layout information programmatically.

#### Acceptance Criteria

1. WHEN `__typeof(x)` is called, THE Runtime SHALL return a type object describing the value's type
2. WHEN `__fields()` is called on a type object, THE Runtime SHALL return the list of fields with their names and types
3. WHEN `__methods()` is called on a type object, THE Runtime SHALL return the list of methods with their names and signatures
4. WHEN `__layout()` is called on a type object, THE Runtime SHALL return size in bytes, alignment in bytes, and ABI classification
5. WHEN `__doc()` is called on a type object, THE Runtime SHALL return attached docstrings and attribute annotations
6. WHEN `__repr_type()` is called on a type, THE Runtime SHALL return a human-readable string representation of the type suitable for error messages
7. WHEN `__coerce(targetType, value)` is defined on a type, THE Runtime SHALL use it for implicit type conversions (see Requirement 17)

---

### Requirement 17: Conversions and Casting

**User Story:** As a developer, I want explicit and implicit conversion mechanisms, so that types can interoperate smoothly where safe and explicitly where not.

#### Acceptance Criteria

1. WHEN `__coerce(toType, value)` is defined on a source type, THE Type_Checker SHALL permit implicit conversion to `toType` at assignment and argument-passing sites
2. WHEN `__cast(toType, value)` is invoked explicitly via cast syntax, THE Runtime SHALL invoke the `__cast` metamethod (as defined in Requirement 14) and return the result or raise a typed error
3. WHEN an implicit coercion could lose information (e.g., float to int), THE Type_Checker SHALL emit a warning suggesting an explicit cast

**Note:** `__coerce` (implicit) is defined here; `__cast` (explicit) is defined as a metamethod in Requirement 14.12. Both are conversion hooks — `__coerce` is Type_Checker-gated (safe, implicit), while `__cast` is developer-invoked (potentially unsafe, explicit).

---

### Requirement 18: Attributes and Annotations

**User Story:** As a developer, I want compile-time attributes on functions, types, and fields, so that I can control optimization, ABI, and documentation metadata.

#### Acceptance Criteria

The attribute system is extensible; this list is non-exhaustive. Additional attributes are defined normatively in their respective requirements. The following are the core compiler-recognized attributes:

1. WHEN `@inline` is applied to a function, THE Codegen SHALL emit the function body inline at call sites (e.g., `static inline` or `__attribute__((always_inline))` in generated C)
2. WHEN `@noinline` is applied to a function, THE Codegen SHALL emit `__attribute__((noinline))` on the generated C function
3. WHEN `@cold` is applied to a function, THE Codegen SHALL emit `__attribute__((cold))` on the generated C function
4. WHEN `@hot` is applied to a function, THE Codegen SHALL emit `__attribute__((hot))` on the generated C function
5. WHEN `@packed` is applied to a type, THE Codegen SHALL emit `__attribute__((packed))` on the generated C struct, removing inter-field padding
6. WHEN `@align(N)` is applied to a type or field, THE Codegen SHALL emit `__attribute__((aligned(N)))` in the generated C code
7. WHEN `@deprecated("message")` is applied to a symbol, THE Type_Checker SHALL emit a warning at every use site including the deprecation message
8. WHEN `@ffi("C_name")` is applied to a function or type, THE Codegen SHALL use the specified C identifier in the generated code
9. WHEN `@nopanic` is applied to a function, THE Type_Checker SHALL reject any `!` operator or panic-capable call within its body (see Requirement 9.8)
10. WHEN `@arc(false)` is applied to a type, THE Compiler SHALL bypass ARC for instances of that type (see Requirement 26.8)
11. WHEN `@concurrent("threaded")` is applied to a module, THE Scheduler SHALL enable multi-threaded mode for that module (see Requirement 19.8)
12. WHEN `@derive(trait)` is applied to a type, THE Compiler SHALL invoke `__derive(trait)` to generate the trait implementation (see Requirement 22.3)
13. WHEN `__attrs()` is called on a function, type, or field, THE Runtime SHALL return the list of attached attributes as a table

---

### Requirement 19: Concurrency — async/await and Channels

**User Story:** As a developer, I want async/await and typed channels with a defined execution model, so that I can write concurrent code that is safe and predictable.

#### Acceptance Criteria

1. WHEN a function is declared with `async`, THE Compiler SHALL transform it into a stackless state machine that yields at `await` points
2. WHEN `await` is applied to an async function call, THE Scheduler SHALL suspend the current task until the result is available
3. WHEN `concurrent.channel(capacity)` is called with a type parameter, THE Runtime SHALL create a typed channel with the specified bounded capacity
4. WHEN a value is sent to a full channel, THE Scheduler SHALL suspend the sending task until space is available
5. WHEN a receive is attempted on an empty channel, THE Scheduler SHALL suspend the receiving task until a value is available
6. WHEN an async task raises an uncaught error, THE Scheduler SHALL propagate the error to the next `await` on that task's result
7. THE Scheduler SHALL use a cooperative, single-threaded event loop by default for task multiplexing
8. WHERE multi-threaded mode is enabled via `--threads` CLI flag or `@concurrent("threaded")` module attribute, THE Scheduler SHALL use a work-stealing thread pool and channels SHALL be safe to use across OS threads
9. WHEN an async task is awaited and the task has already been cancelled, THE Scheduler SHALL return a cancellation error to the awaiting task
10. WHEN a task is suspended at an `await` point and the task is cancelled, THE Scheduler SHALL execute all pending `defer` statements in the task before completing cancellation

---

### Requirement 20: Standard Library — Core Modules

**User Story:** As a developer, I want a comprehensive standard library for file system, networking, process management, and data formats, so that I can build systems programs without third-party dependencies.

#### Acceptance Criteria

1. THE Runtime SHALL provide a `path` module for file path manipulation (join, resolve, basename, dirname, extension)
2. THE Runtime SHALL provide an `fs` module for file system operations (read, write, mkdir, remove, stat, walk)
3. THE Runtime SHALL provide a `process` module for spawning and managing child processes (spawn, wait, kill, pipe stdin/stdout/stderr)
4. THE Runtime SHALL provide an `env` module for reading and writing environment variables
5. THE Runtime SHALL provide a `net` module for TCP and UDP socket operations (listen, connect, send, receive, close)
6. THE Runtime SHALL provide a `json` module for JSON serialization and deserialization
7. THE Runtime SHALL provide a `time` module for time measurement, formatting, parsing, and sleeping
8. THE Runtime SHALL provide a `log` module for structured logging with severity levels (debug, info, warn, error)
9. THE Runtime SHALL provide a `concurrent` module containing channel and async primitives (as defined in Requirement 19)

---

### Requirement 21: FFI — Foreign Function Interface

**User Story:** As a developer, I want to call C functions from Duo and expose Duo functions to C, so that I can interoperate with existing system libraries.

#### Acceptance Criteria

1. WHEN a function is annotated with `@ffi("C_name")`, THE Codegen SHALL generate a C-compatible function with that name and the C calling convention
2. WHEN an external C function is declared in Duo with type annotations, THE Compiler SHALL generate the correct calling convention and type marshalling code
3. WHEN a Duo function is exported for C consumption, THE Codegen SHALL produce a C header file declaring the function's signature
4. THE Type_Checker SHALL verify that FFI-annotated types map to valid C types (integers, floats, pointers, fixed-size arrays, anonymous record types which lower to C structs)
5. WHEN `@align(N)` or `@packed` is used on an FFI record (i.e. on a binding whose annotation is an anonymous record type), THE Codegen SHALL match the specified C memory layout exactly
6. Anonymous record types used in FFI bindings get a deterministic C struct name derived from a content hash, so that C headers can be re-generated and matched by the linker

---

### Requirement 22: Metaprogramming — Compile-Time Evaluation and Macros

**User Story:** As a developer, I want compile-time code generation, evaluation, and AST-level macros, so that I can reduce boilerplate and implement domain-specific optimizations.

#### Acceptance Criteria

1. WHEN `__constexpr()` wraps an expression, THE Compiler SHALL evaluate it during compilation and emit the result as a literal in the generated code
2. WHEN `__consteval(ctx)` defines a compile-time function, THE Compiler SHALL execute it at compile time with access to AST context information
3. WHEN `__derive(trait)` is specified on a type, THE Compiler SHALL generate the trait implementation based on the type's field and method structure
4. WHEN `__macroexpand(node, ctx)` is defined, THE Compiler SHALL invoke it during macro expansion, passing the AST node and a context object
5. WHEN `__quote` is used inside a macro, THE Compiler SHALL capture the enclosed code as an AST fragment
6. WHEN `__unquote` is used inside a `__quote` block, THE Compiler SHALL splice the evaluated expression into the quoted AST
7. THE Compiler SHALL enforce macro hygiene: generated identifiers SHALL NOT capture names from the expansion site unless explicitly escaped via `ctx.freshName`
8. WHEN a macro expansion produces invalid syntax, THE Compiler SHALL emit an error with source spans pointing to both the macro definition and the expansion site

---

### Requirement 23: Parser — Duo Source Language Grammar

**User Story:** As a developer working on the compiler, I want a complete parser for the Duo grammar, so that all language constructs are correctly recognized and represented in the AST.

#### Acceptance Criteria

1. THE Parser SHALL parse all valid Lua 5.5 syntax as a subset of Duo
2. THE Parser SHALL parse type annotations on variable declarations, function parameters, and return types
3. THE Parser SHALL parse generic type parameters with optional constraints
4. THE Parser SHALL parse `match` expressions with pattern arms, guards, and destructuring
5. THE Parser SHALL parse `try`/`catch`/`defer` blocks
6. THE Parser SHALL parse `async`/`await` keywords
7. THE Parser SHALL parse attribute annotations (e.g., `@inline`, `@ffi("name")`, `@derive(...)`) preceding declarations
8. THE Parser SHALL parse enum declarations with variant names and optional payloads
9. THE Parser SHALL parse statement-style function calls with argument list terminated by newline, semicolon, or end-of-block
10. THE Parser SHALL parse `in` as a binary operator in expression context (e.g., `x in y`); disambiguation from the `for-in` loop SHALL use the rule that `in` following a `for` header's variable list is always the loop keyword
11. THE Pretty_Printer SHALL format any valid Duo AST back into valid Duo source text
12. FOR ALL valid Duo ASTs, parsing then pretty-printing then parsing SHALL produce an equivalent AST (round-trip property)

---

### Requirement 24: Ahead-of-Time Compilation to C

**User Story:** As a developer, I want Duo to compile to C, so that I get native performance and can target any platform with a C compiler.

#### Acceptance Criteria

1. THE Codegen SHALL produce valid C11 source code from a typed Duo AST
2. WHEN generics are used, THE Codegen SHALL emit one C function/struct per monomorphized specialization
3. WHEN closures capture variables, THE Codegen SHALL represent captured environments as ARC-managed heap-allocated structs
4. WHEN `defer` is used, THE Codegen SHALL emit cleanup code at every exit point of the enclosing scope (normal return, error, early return)
5. WHEN an async function is compiled, THE Codegen SHALL emit a state machine struct and step function in C
6. THE Codegen SHALL produce C code that compiles without warnings under `-Wall -Wextra -pedantic` with GCC and Clang

---

### Requirement 25: WASM/WASI Backend

**User Story:** As a developer, I want to compile Duo to WebAssembly, so that I can run Duo programs in browsers and WASI-compatible runtimes.

#### Acceptance Criteria

1. WHEN the `--target wasm32-wasi` flag is passed to the Compiler, THE Codegen SHALL produce C code and invoke wasi-sdk (clang) to compile it into a valid WASM module
2. WHEN the WASM target is selected, THE Codegen SHALL emit WASI-compatible system calls for `fs`, `env`, `process`, and `net` module operations
3. WHEN the WASM target is selected and an `async` function is compiled, THE Codegen SHALL emit the same state-machine C representation, compiled to WASM single-threaded execution
4. WHEN the WASM target is selected and `--threads` or `@concurrent("threaded")` is specified, THE Compiler SHALL emit a compile-time error stating that multi-threaded mode is not supported on the `wasm32-wasi` target
5. THE Compiler SHALL produce WASM output that passes validation by a conformant WASM runtime (e.g., wasmtime, wasm3)

---

### Requirement 26: Memory Management

**User Story:** As a developer, I want deterministic resource cleanup with minimal runtime overhead, so that I can write systems code without GC pauses or manual memory management.

#### Acceptance Criteria

1. THE Runtime SHALL use automatic reference counting (ARC) as the primary memory management strategy for heap-allocated values (tables, closures, strings)
2. WHEN a reference count reaches zero, THE Runtime SHALL immediately deallocate the value
3. WHEN a reference cycle is detected by the Cycle_Collector, THE Runtime SHALL reclaim all values in the cycle
4. THE Cycle_Collector SHALL run incrementally, limiting per-invocation pause time to a configurable threshold (default: 1ms)
5. WHEN `__close` is defined on a value's metatable, THE Runtime SHALL invoke it at scope exit before the reference count is decremented (deterministic cleanup regardless of whether other references exist)
6. WHEN `__gc` is defined on a value's metatable, THE Runtime SHALL invoke it when the cycle collector reclaims the value; this provides Lua-compatible finalization for legacy code
7. WHEN a value is passed across an FFI boundary, THE Runtime SHALL not reference-count it; the caller is responsible for lifetime management of FFI-owned values
8. WHEN `@arc(false)` is applied to a type, THE Compiler SHALL allocate instances on the stack or in a caller-managed region, bypassing ARC

---

### Requirement 27: Module Resolution and Imports

**User Story:** As a developer, I want clear module resolution rules, so that imports are predictable and the build system can resolve dependencies deterministically.

#### Acceptance Criteria

1. WHEN `req "name"` is used, THE Resolver SHALL search for the module in this order: local project source tree, then declared dependencies, then standard library
2. WHEN a relative path is used (e.g., `req "./util"`), THE Resolver SHALL resolve it relative to the importing file's directory
3. WHEN a module exports symbols, THE Resolver SHALL make only explicitly returned values available to importers
4. WHEN a circular import is detected, THE Compiler SHALL emit a compile-time error naming the cycle

---

### Requirement 28: Compiler Diagnostics and CLI

**User Story:** As a developer, I want clear, actionable compiler diagnostics and a usable CLI, so that I can quickly identify and fix issues.

#### Acceptance Criteria

1. WHEN the Compiler encounters an error, THE Compiler SHALL emit a diagnostic with file path, line number, column number, and a descriptive message
2. WHEN a type constraint fails, THE Compiler SHALL include the concept name, the failing type, and each unsatisfied member in the diagnostic
3. WHEN a deprecation warning is triggered, THE Compiler SHALL include the deprecation message and the location of the deprecated symbol's definition
4. THE Compiler SHALL accept `duo build <file>` to compile a Duo source file to the default target (native via C)
5. THE Compiler SHALL accept `duo run <file>` to compile and immediately execute the resulting binary
6. THE Compiler SHALL accept `--target` flag with values `native`, `wasm32-wasi` to select the compilation backend

---

## Non-Functional Requirements

---

### Requirement 29: Performance — Compiled Output

**User Story:** As a developer, I want Duo's compiled output to perform comparably to hand-written C, so that the language abstraction does not impose meaningful runtime cost.

#### Acceptance Criteria

1. THE Codegen SHALL produce code that executes within 10% of equivalent hand-written C on a standard benchmark suite (recursive fibonacci, matrix multiply, binary trees, spectral norm)
2. THE Codegen SHALL produce code where monomorphized generic functions perform identically to manually specialized C functions (zero overhead)
3. WHEN no closures, dynamic dispatch, string operations, or table operations are used, THE Codegen SHALL produce code with zero heap allocations for that code path (string literals and table literals are ARC-managed and excluded from this guarantee)

---

### Requirement 30: Performance — Compilation Speed and Binary Size

**User Story:** As a developer, I want fast compilation and reasonable binary sizes, so that my development cycle stays tight.

#### Acceptance Criteria

1. THE Compiler SHALL compile a 10,000-line Duo source file to C in under 2 seconds on a modern workstation (4+ cores, 16GB RAM); this budget covers Duo→C translation only and excludes the downstream C compiler (gcc/clang) invocation
2. THE Compiler SHALL produce binaries where a minimal "hello world" program is under 100KB statically linked (excluding debug symbols)

---

### Requirement 31: Error Message Quality

**User Story:** As a developer, I want error messages that help me fix problems quickly, so that I spend less time debugging compiler output.

#### Acceptance Criteria

1. WHEN a type error occurs, THE Compiler SHALL display the expected type, the actual type, and the source location with context
2. WHEN a concept constraint fails, THE Compiler SHALL list each missing or incompatible member with its expected signature
3. WHEN an overload resolution fails, THE Compiler SHALL list all candidate overloads and explain why each was rejected
4. THE Compiler SHALL colorize diagnostic output when the terminal supports it

