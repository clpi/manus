# DNB011 Direct Backend Failure Characterization

**Date:** 2026-08-12T19:00:19-07:00  
**HEAD:** dc07e5d7  
**Author:** measurement/acceptance lane

## Measured Signature

The native direct backend rejects programs with `DNB011` at
`native_backend.zig:3864` when the semantic graph contains unresolved
application candidates after excluding bootstrap nodes.

## Passes (pure computation, no builtin I/O)

```idol
main: i64 = ()
    0
```

```idol
main: i64 = ()
    x = 0
    x
```

```idol
main: i64 = ()
    1 + 2
```

```idol
add = (a: i64, b: i64) a + b

main: i64 = ()
    add(1, 2)
```

```idol
fib = (n: i64)
    if n <= 1
        n
    else
        fib(n - 1) + fib(n - 2)

main: i64 = ()
    fib(10)
```

```idol
main: i64 = ()
    if 1 == 1
        1
    else
        2
```

## Fails DNB011 (unresolved-application-facts)

- Builtin print: `main: i64 = () print("test")`
- Builtin len on string: `main: i64 = () s = "hello"; len(s)`
- String method find: `main: i64 = () s:find("x")`
- Stdout method write: `main: i64 = () stdout:write("x")`
- Curried closure: `hit(io) = (code) code:find("io.")`

## C Backend Emission

**Passes:**
- `print(42)`
- `len(s)`

**Fails (missing runtime declarations):**
- Curried closures: `hit(io) = (code) code:find("io.")`
  → generated C calls `lua_to_bool`, `lua_to_str` without declarations

## Root Cause Assessment

The semantic graph resolver does not fully resolve application facts
for builtin/I/O relations (`print`, `len`, `string:find`,
`stdout:write`). These remain as `application_candidates` without
`application` facts.

The direct backend requires zero unresolved application candidates
(excluding bootstrap), so it rejects.

The C backend emits code for some builtins but fails on closures due
to missing runtime helper declarations in generated C.

## Impact on Workstream

| Component | Status | Reason |
|-----------|--------|--------|
| gate/idiom.id | FAIL | uses `print`, `string:find`, closures |
| gate/host.id | FAIL | uses `print`, `string:find` |
| gate/path.id | FAIL | same |
| gate/architecture.id | FAIL | same |
| gate/admission.id | FAIL | same + missing linker entry |
| gate/census.id | FAIL | same |
| ALL 8 ledger scripts | FAIL | same + missing linker entry |
| Pre-commit hook | BLOCKED | all admission gates fail |

## Evidence Confidence

**HIGH** for this characterization. Minimal reproductions confirm the
exact failure boundary. This is measurement, not implementation.

## Next Dependency (Compiler Implementation Lane)

The semantic graph resolver must fully resolve application facts for
builtin/I/O relations, **OR** the direct backend must accept a defined
subset of unresolved bootstrap/builtin applications.

Until then:
- No gate or ledger can execute
- No canonical change can be admitted
- FTCFTW evidence is invalid
- SHC claim cannot be verified
