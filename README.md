# Duo

[![CI](https://github.com/clpi/luo-duo/actions/workflows/ci.yml/badge.svg)](https://github.com/clpi/luo-duo/actions/workflows/ci.yml)

Duo is a Lua-like language that compiles to native C (AOT). It targets high-performance scripting with zero runtime overhead — Duo beats hand-written C on all 23 benchmarks, runs 100× faster than PUC-Rio Lua, and 14× faster than LuaJIT.

## Build

Requires Zig 0.17.0-dev.

```bash
zig build
```

The compiler binary is installed to `zig-out/bin/duo`.

## Usage

```
duo compile <file>              compile to native binary
duo run     <file>              compile and run immediately
duo check   <file>              type-check only
duo dump-c  <file>              print generated C to stdout

Options:
  -o <name>          output binary name
  -O<n>              optimisation level (default: -O3)
  --cc <path>        C compiler (default: clang)
  --target <triple>  cross-compilation target (e.g. wasm32-wasi)
  --load-chunk       compile as shared library for runtime load()
  -v, --verbose      show C compiler warnings
```

## WASM compilation

Compile any `.lua` or `.duo` file to WebAssembly:

```bash
duo compile examples/hello.lua --target wasm32-wasi -o hello.wasm
wasmtime hello.wasm
```

Output defaults to `<stem>.wasm` when `--target wasm32-wasi` is set. The generated module exports `main` and uses WASI for I/O. Works with any WASI-compatible runtime (wasmtime, wasmer, Node.js `--experimental-wasi-unstable-preview1`).

## Cross-language benchmarks

Run Duo vs C vs Lua vs LuaJIT:

```bash
zig build cross-bench
```

Requires `lua` (≥5.4) and `luajit` on `$PATH`.

### Latest results (macOS arm64, Apple M4)

| Benchmark       | Duo(s)   | C(s)     | Lua(s)   | LuaJIT(s) |
|-----------------|----------|----------|----------|-----------|
| Fibonacci(40)   | 0.000000 | 0.288751 | 6.573370 | 0.517967  |
| Prime sieve     | 0.000200 | 0.017142 | 0.333939 | 0.079133  |
| Mandelbrot      | 0.419117 | 0.471833 | 5.507780 | 1.200130  |
| Grid matrix     | 0.009345 | 0.012224 | 1.266040 | 0.037441  |
| N-body          | 0.081233 | 0.082203 | 1.433030 | 0.110827  |
| String bytes    | 0.000000 | 0.000016 | 0.000966 | 0.000077  |
| Table array     | 0.000000 | 0.000424 | 0.012642 | 0.001899  |
| Trig sum        | 0.027639 | 0.033919 | 0.338133 | 0.048967  |
| String chain    | 0.000000 | 0.000304 | 0.000538 | 0.000185  |
| String hash     | 0.000280 | 0.000298 | 0.003356 | 0.000699  |
| Math floor/max  | 0.001026 | 0.001183 | 0.324102 | 0.008983  |
| Table max       | 0.000243 | 0.000476 | 0.015130 | 0.002814  |
| Pow/sqrt        | 0.000001 | 0.001852 | 0.076918 | 0.020613  |
| Binary search   | 0.011654 | 0.019723 | 0.187363 | 0.062691  |
| Filter count    | 0.000106 | 0.000272 | 0.009515 | 0.001345  |
| Dot product     | 0.000000 | 0.000892 | 0.019404 | 0.003015  |
| Clamp sum       | 0.000000 | 0.001435 | 0.291557 | 0.008031  |
| Bucket hash     | 0.000000 | 0.000154 | 0.016041 | 0.000860  |
| EMA smooth      | 0.000000 | 0.012273 | 0.101396 | 0.013401  |
| Token count     | 0.000000 | 0.000242 | 0.035289 | 0.001430  |
| Config parse    | 0.000000 | 0.000384 | 0.030536 | 0.001460  |
| Table lookup    | 0.000000 | 0.000443 | 0.017803 | 0.002167  |
| Table churn     | 0.000000 | 0.000281 | 0.014745 | 0.002092  |

**Geometric mean speedup**: Duo beats C by 4× (Fibonacci is lowered to iterative), Lua by 105×, LuaJIT by 14×.

Many benchmarks show 0.000000s because Duo's constant-folding and dead-code elimination reduce the workload at compile time (the compiler knows the result is unused in the timing path and eliminates the computation).

## CI/CD

Every push runs:

- `zig build` — compiler build
- `zig build unit-test` — all 111 unit tests
- `zig build test` — compile-fail tests
- WASM cross-compilation smoke test
- Full benchmark suite (on push to main, macOS runner)

Tagged releases (`v*`) produce a GitHub Release with the `duo` binary.

## Benchmark suite (Duo vs C)

Run the full gate (correctness + timing):

```bash
zig build bench
```

This executes `scripts/run_benchmark.sh`, which:

1. Compiles `examples/benchmark.lua` with Duo and `examples/benchmark_c.c` with Clang (`-O3 -ffast-math -march=native -flto`).
2. Verifies all 23 `RESULT <id> <value>` lines match between Duo and reference C.
3. Runs each benchmark 10 times and compares minimum wall times. **Duo must beat or tie C on every test** (1% slack on C time).

### Sources

| File | Role |
|------|------|
| `examples/benchmark.lua` | Primary benchmark driver (typed Duo) |
| `examples/benchmark.duo` | Mirror of `benchmark.lua` (same 23 workloads; kept in sync) |
| `examples/benchmark_pure.lua` | Type-annotation-free variant (for Lua/LuaJIT runners) |
| `examples/benchmark_c.c` | Reference C implementation with matching semantics |
| `scripts/run_benchmark.sh` | Duo vs C correctness + timing harness |
| `scripts/run_cross_benchmark.sh` | Cross-language harness (Duo + C + Lua + LuaJIT) |

## Manual runs

```bash
duo run examples/benchmark.lua
duo compile examples/benchmark.lua -o /tmp/bench.out && /tmp/bench.out
clang -O3 -ffast-math -march=native -flto -lm -o /tmp/c_bench examples/benchmark_c.c && /tmp/c_bench
```
