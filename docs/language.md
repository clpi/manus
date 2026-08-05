# Duo language reference

**Status:** current entry point. Detailed chapters live under `docs/src/`.

## Quick start

Duo extends Lua 5.5 with optional static types, descriptors, pipelines, and `@comp.*` metaprogramming.

```duo
add(a: i64, b: i64): i64 = a + b

Point: @{ x: f64, y: f64 }

main(): i64
    p = Point { x = 3.0, y = 4.0 }
    add(1, 2)
end
```

Build and run:

```bash
zig build
duo run hello.duo
duo check myfile.duo    # type-check only
```

## Core topics

| Topic | Document |
| --- | --- |
| Introduction | [docs/src/introduction.md](src/introduction.md) |
| Types | [docs/src/types.md](src/types.md) |
| Functions | [docs/src/functions.md](src/functions.md) |
| Typed functions | [docs/src/functions_typed.md](src/functions_typed.md) |
| Descriptors / concepts | [docs/src/concepts.md](src/concepts.md) |
| Pattern matching | [docs/src/pattern_matching.md](src/pattern_matching.md) |
| Error handling | [docs/src/error_handling.md](src/error_handling.md) |
| Idiomatic Duo | [docs/src/idiomatic_duo.md](src/idiomatic_duo.md) |
| Stdlib | [docs/src/stdlib.md](src/stdlib.md) |
| WASM | [docs/src/wasm.md](src/wasm.md) |

## Metaprogramming

Use `@comp.*` for compile-time transforms. See [metaprogramming](metaprogramming.md) and `duo catalog`.

Bare compile-time eval: `@(expr)`.

## Grammar

Authoritative rules: [GRAMMAR_SPEC.md](GRAMMAR_SPEC.md). `@const` and `@comptime` are **not** valid user directives.

## Experimental vs supported

- **Supported:** Lua-compatible syntax, typed native lowering, `@comp.*` registry entries with tests, benchmark suite
- **Experimental:** semantic graph tooling, Ward Wasm runtime integration, some `@comp.*` combinators
- **Planned:** see [roadmap](src/roadmap.md) and pass plans under `docs/plans/` (historical milestones)

## Compiler

See [compiler.md](compiler.md).
