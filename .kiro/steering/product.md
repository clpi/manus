# Product: Duo

Duo is an ahead-of-time (AOT) compiled language with Lua-compatible syntax that transpiles to C, then compiles to native binaries via Clang. It supports both `.lua` (Lua 5.5 compatible) and `.duo` (extended syntax with static types) source files.

## Key capabilities

- Compiles Lua/Duo source to C, then to native machine code
- Cross-compilation including WebAssembly (wasm32-wasi) targets
- Aggressive optimizations: constant folding, dead-code elimination, loop lowering (e.g. recursive fib → iterative)
- Profile-guided optimization (PGO) via two-pass Clang compilation
- Type checking with optional static type annotations (Duo mode)
- Shared library compilation for runtime `load()` via `--load-chunk`

## Performance goals

Duo targets performance parity with (or better than) hand-written C. A 40-benchmark gate enforces that Duo must beat or tie reference C on every test (with 1% slack). Geometric mean shows ~4× speedup over C, ~105× over Lua, ~14× over LuaJIT.

## CLI commands

- `duo compile <file>` — compile to native binary
- `duo run <file>` — compile and run immediately
- `duo check <file>` — type-check only
- `duo dump-c <file>` — print generated C to stdout
