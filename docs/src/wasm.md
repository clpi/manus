# WASM Compilation

Duo supports cross-compilation to WebAssembly with WASI (WebAssembly System Interface) for sandboxed execution.

## Requirements

- Zig (for WASI toolchain via `zig cc`)
- WASI-compatible runtime (wasmtime, wasmer, Node.js with WASI support)

## Basic Compilation

```bash
# Compile to WASM
duo compile script.duo --target wasm32-wasi -o program.wasm

# Run with wasmtime
wasmtime program.wasm

# Run with wasmer
wasmer program.wasm

# Run with Node.js (experimental WASI)
node --experimental-wasi-unstable-preview1 program.wasm
```

## Output Naming

When `--target wasm32-wasi` is specified, the output defaults to `<stem>.wasm`:

```bash
duo compile hello.lua              # Produces hello.wasm automatically
duo compile script.duo -o app.wasm  # Explicit name
```

## WASI Exports

The generated module exports a `main` function:

```duo
-- This becomes the WASM entry point
fun main(): i64
    print("Hello from WASM!")
    return 0
end
```

## Standard Library Support

Most standard library modules work in WASM, including:

- `print` — Writes to WASI stdout
- `fs` — Limited file system access
- `json` — JSON parsing/stringification
- `math` — Mathematical functions

Network modules may require additional WASI capabilities.

## Shared Library Mode

Compile as a shared library for dynamic loading:

```bash
duo compile module.duo --target wasm32-wasi --load-chunk -o module.wasm

# Use with wasmtime component model
wasmtime module.wasm --invoke main
```

## Shared Memory (Experimental)

Enable shared memory for threading support:

```bash
duo compile script.duo --target wasm32-wasi --shared-memory -o program.wasm
```

Requires WASI runtime with `wasi:threading` support.

## Limitations

- Multi-threaded mode (`--threads`) is a compile error with WASM target
- Some system calls may not be available
- File system access depends on runtime capabilities

## Example

```duo
-- hello.duo
fun main(): i64
    print("Hello, WASM!")
    return 0
end
```

```bash
$ duo compile hello.duo --target wasm32-wasi
$ wasmtime hello.wasm
Hello, WASM!
```

## Debugging WASM

Generate and inspect the C code:

```bash
# See what will be compiled to WASM
duo dump-c script.duo

# Compile manually for debugging
clang --target=wasm32-wasi -O3 script.c -o debug.wasm
wasmtime debug.wasm --invoke main
```