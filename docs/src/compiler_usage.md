# Compiler Usage

The Duo compiler compiles `.duo` and `.lua` files to native executables or WebAssembly modules.

## Installation

Requires Zig 0.17.0-dev or later:

```bash
# Build from source
zig build

# Binary installed to zig-out/bin/duo
```

## Commands

```
duo compile <file>              compile to native binary
duo run     <file>              compile and run immediately
duo check   <file>              type-check only
duo dump-c  <file>              print generated C to stdout
duo completion <shell>           generate shell completions (bash, zsh, fish, nu)
duo help                         show help message
```

## Options

| Option | Description |
|--------|-------------|
| `-o <name>` | Output binary name (default: `<stem>.out` or `<stem>.wasm`) |
| `-O<n>` | Optimization level (default: `-O3`) |
| `--cc <path>` | C compiler path (default: clang) |
| `--target <triple>` | Cross-compilation target |
| `--load-chunk` | Compile as shared library for runtime `load()` |
| `--pgo` | Enable profile-guided optimization |
| `--shared-memory` | Enable WASM shared memory (wasm32-wasi only) |
| `-v, --verbose` | Show C compiler warnings |

## Target Triples

| Target | Platform |
|--------|----------|
| `native` | Native machine code (default) |
| `wasm32-wasi` | WebAssembly with WASI |

## Basic Usage

```bash
# Compile and run
duo run script.duo

# Compile only
duo compile script.duo -o my_program
./my_program

# Check types without generating code
duo check script.duo

# View generated C code
duo dump-c script.duo
```

## Optimization Levels

| Level | Description |
|-------|-------------|
| `-O0` | No optimization |
| `-O1` | Basic optimizations |
| `-O2` | Standard optimizations |
| `-O3` | Aggressive optimizations (default) |

## Profile-Guided Optimization

PGO enables the compiler to optimize based on actual execution profiles:

```bash
# Two-pass compile with profiling
duo run script.duo --pgo

# The compiler runs the program, collects profile data,
# then recompiles with optimized paths
```

## C Compiler Flags

Duo passes these flags to the C compiler automatically:

- `-ffast-math` — Aggressive floating-point optimizations
- `-flto` — Link-time optimization
- `-march=native` — CPU-specific instructions (native target)
- `-fomit-frame-pointer` — Smaller, faster code
- `-funroll-loops` — Loop unrolling

## Output Inspection

```bash
# See generated C code
duo dump-c script.duo > output.c

# Compile generated C manually
clang -O3 -flto output.c -o output
```

## Error Messages

The compiler provides detailed error locations:

```
error: type mismatch
  in function 'add' at line 3
  expected: i64
  got: f64
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Compile error or runtime error |
| 2 | Invalid command-line arguments |
| 128 | Program terminated by signal |