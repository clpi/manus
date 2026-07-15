# Introduction

Duo is a Lua-like language that compiles to native C (ahead-of-time compilation). It combines the simplicity and expressiveness of Lua with optional static typing for performance-critical code.

## Key Features

- **Lua-compatible syntax**: Duo accepts both `.duo` files (typed mode, local-by-default) and `.lua` files (traditional Lua mode, global-by-default)
- **Static types, zero-cost**: When you annotate types, Duo generates pure C code with no runtime overhead or boxing
- **Native performance**: Fully-typed Duo code compiles to native C that beats C in many benchmarks due to aggressive optimizations
- **WASM target**: Cross-compile to WebAssembly with WASI support
- **Pattern matching**: Lua-like match expressions with destructuring and `then`/`do` arms
- **Async/await**: Cooperative concurrency built on stackless coroutines
- **Generics**: Monomorphized generics (compile-time specialization)
- **Result and Option types**: Rust-inspired error handling without runtime cost

## Architecture

The Duo compiler has four main passes:

1. **Lexer** → Tokenizes source code
2. **Parser** → Builds an AST from tokens
3. **Semantic Analysis** → Type-checks and annotates the AST
4. **Code Generation** → Emits C code that clang compiles to native

Optional passes between semantic analysis and codegen:

- **Monomorphizer** → Expands generic functions into concrete specializations
- **ARC Pass** → Analyzes reference counting for managed values
- **Async Lowering** → Transforms async functions into state machines

## Status

Duo is actively developed with 393+ unit tests, compile-fail tests, and a 40-benchmark performance gate (`zig build bench` requires Duo to beat or tie C). The compiler produces native binaries, shared libraries, and WebAssembly outputs. See [Roadmap](./roadmap.md) for the current feature set and planned work.

## Quick Start

```bash
# Install (requires Zig 0.17.0-dev)
zig build

# Run a Duo file
./zig-out/bin/duo run examples/hello.lua

# Compile a .duo file to native binary
./zig-out/bin/duo compile script.duo -o program

# Compile to WASM
./zig-out/bin/duo compile script.duo --target wasm32-wasi -o program.wasm
```

## Hello World

```duo
-- hello.duo
fun main(): void
    print("Hello, Duo!")
end
```

```bash
$ duo run hello.duo
Hello, Duo!
```

## Typed Example

```duo
-- fib.duo
fun fib(n: i64): i64
    if n <= 1 then return n end
    fib(n - 1) + fib(n - 2)
end

print(fib(40))
```

This compiles to pure C, running at native speed.
