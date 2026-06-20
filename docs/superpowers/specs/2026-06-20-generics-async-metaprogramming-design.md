# Generics, Async, and Metaprogramming Design

Date: 2026-06-20

## Scope

This design closes the remaining compiler gaps for Requirement 4 (generics),
Requirement 19 (async/await), and Requirement 22 (metaprogramming). It preserves
Duo's existing syntax: generic functions and enums are the named generic
declarations; inline record annotations remain structural and anonymous.

The implementation is staged, but every stage must be executable and tested.
Descriptor-only async output, runtime-only "compile-time" helpers, and generic
fallbacks to `any` are not considered complete implementations.

## Shared pipeline

The compiler pipeline becomes:

1. parse source into the normal AST;
2. expand hygienic macros and evaluate required compile-time expressions;
3. type-check the expanded AST and record generic instantiation sites;
4. discover generic specializations to a fixed point;
5. run ARC and async lowering;
6. emit concrete C declarations, state machines, and ordinary code.

Compile-time expansion precedes semantic analysis because generated syntax must
be checked exactly like source syntax. Monomorphization precedes async lowering
so an async generic function gets a concrete frame layout per specialization.

## Generics

### Structural substitution

`Specialization` owns an immutable substitution map. Resolution and unification
must recurse through every `TypeExpr` carrier: named, pointer, optional, array,
generic application, function, tuple, and record. A nested call is inferred from
the specialized environment rather than the unspecialized semantic type map.
Unbound parameters are a diagnostic at a concrete call site; they must not
silently generate an `any` specialization.

### Fixed point and recursion

Specialization identity is `(declaration identity, canonical concrete type
arguments)`. Requests enter the cache before scanning the body, which terminates
direct recursion. Scanning a specialized body may enqueue further requests and
continues until the queue is empty. Mangling is deterministic and structural.

### Generic named types

Generic enum applications such as `Option[i64]` receive a canonical concrete
name and one emitted C definition per unique instantiation. Variant payload
fields are substituted recursively. Inline record types already use stable
content-hashed names and therefore need structural substitution, not a new
declaration syntax. Generic constraints are checked at each instantiation.

## Async/await

### Runtime contract

Generated code uses a type-erased task header containing state, status,
cancellation, error, frame, step, and destroy hooks. Typed async wrappers allocate
the concrete frame and return a task handle immediately. The cooperative
scheduler repeatedly polls runnable tasks. A completed task retains its result
until consumed or destroyed.

### State-machine lowering

Lowering partitions a function body at each `await`. The frame contains the
program counter, result/error slots, child-task slot, parameters, and locals
live across suspension. Each step case executes its segment once. At an await it
creates the child task once, polls it, returns pending when necessary, propagates
error/cancellation, stores the ready value, advances state, and continues.

Control-flow constructs are lowered recursively. The initial executable subset
must reject an unsupported suspension shape with a source diagnostic instead of
emitting a misleading skeleton. The supported subset expands until all normal
statements and expressions can cross suspension.

### Cancellation and cleanup

Cancellation is idempotent. On the next poll, active defers run once in reverse
registration order, owned children are cancelled/released, ARC-owned frame
values are released, and the task becomes cancelled. Awaiting a cancelled task
produces the cancellation error through the same error path as task failure.

## Metaprogramming

### Deterministic constant evaluation

`##expr` and `__constexpr(expr)` use a compiler-owned evaluator, not host Lua or
generated C execution. The initial value domain is nil, booleans, integers,
floats, strings, arrays, and records. Pure unary/binary operations, conditionals,
local bindings, bounded loops, and calls to declared `__consteval` functions are
allowed. I/O, mutable globals, FFI, nondeterminism, async, and runtime-only calls
are rejected. Evaluation has step/depth/allocation limits and reports the
original source span.

### AST values and hygienic expansion

Quoted code is represented by compiler-owned AST values retaining definition
spans. `__quote` constructs an AST fragment and `__unquote` splices an AST value
or literal. Calling a value with `__macroexpand(node, ctx)` during expansion
returns an AST fragment. Identifiers introduced by a macro receive a fresh
syntax context; source identifiers retain theirs. Deliberate capture requires a
context API operation and is visible in the expansion implementation.

Expansion runs to a fixed point with recursion and node-count limits. Invalid
output reports both the macro definition span and invocation span.

### Reflection and derive

The compile-time context exposes read-only type/declaration metadata: kind,
name, fields, variants, methods, attributes, size, and alignment. `@derive(X)`
is implemented as a compiler-driven macro invocation over this metadata and its
generated implementation is then type-checked normally.

## Testing and compatibility

Each feature starts with unit tests for its pure transformation, followed by
compile/dump-C tests and compile-and-run fixtures. Required cross-feature cases
include recursive generic calls, generic async functions, compile-time generated
generic calls, await error propagation, cancellation/defer order, hygiene, and
deterministic repeated output. Existing non-generic, non-async programs must
retain byte-equivalent generated C except for shared runtime declarations that
are only emitted when used.

Roadmap/task status changes only after executable tests cover the claimed
behavior. Full-suite verification is `zig build test --summary all`; performance
claims additionally require `zig build bench`.
