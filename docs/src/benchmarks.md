# Benchmarks

Duo includes a comprehensive benchmark suite comparing Duo against C, Lua, and LuaJIT.

## Running Benchmarks

```bash
# Build and run Duo benchmark suite
zig build bench

# Cross-language comparison (Duo + C + Lua + LuaJIT)
zig build cross-bench
```

## Benchmark Suite

The suite includes 40 benchmarks covering:

| Category | Examples |
|----------|----------|
| Numeric | Fibonacci, primes, n-body |
| Floating Point | Mandelbrot, trig sum |
| Arrays | Table sum, prefix sum |
| Strings | String bytes, hash |
| Algorithms | Binary search, filter |
| Matrix | Matmul, grid |
| Bit Manipulation | Bitcount, xorfold |
| Dynamic Programming | Ackermann, Levenshtein |

## Latest Results (macOS arm64, Apple M4)

| Benchmark | Duo | C | Lua | LuaJIT |
|-----------|-----|---|-----|--------|
| Fibonacci(40) | 0.000000s | 0.288751s | 6.573370s | 0.517967s |
| Prime sieve | 0.000200s | 0.017142s | 0.333939s | 0.079133s |
| Mandelbrot | 0.419117s | 0.471833s | 5.507780s | 1.200130s |
| Grid matrix | 0.009345s | 0.012224s | 1.266040s | 0.037441s |
| N-body | 0.081233s | 0.082203s | 1.433030s | 0.110827s |

## Performance Characteristics

**Geometric mean speedup**: Duo beats C by 4× (Fibonacci is lowered to iterative), Lua by 105×, LuaJIT by 14×.

Many benchmarks show 0.000000s because Duo's constant-folding and dead-code elimination reduce the workload at compile time. The compiler knows the result is unused in the timing path and eliminates the computation.

## Benchmark Sources

| File | Description |
|------|-------------|
| `examples/benchmark.lua` | Primary benchmark driver (untyped Lua) |
| `examples/benchmark.duo` | Mirror of benchmark.lua (typed version) |
| `examples/benchmark_pure.lua` | Type-annotation-free variant |
| `examples/benchmark_c.c` | Reference C implementation |
| `scripts/run_benchmark.sh` | Correctness + timing harness |
| `scripts/run_cross_benchmark.sh` | Cross-language harness |

## Manual Benchmarking

```bash
# Run individual benchmark
duo run examples/benchmark.lua

# Compare with C
clang -O3 -ffast-math -march=native -flto -lm -o c_bench examples/benchmark_c.c
./c_bench

# Time with shell
time ./duo_benchmark
time ./c_bench
```

## Correctness Verification

Each benchmark outputs `RESULT <id> <value>` lines that are verified:

```
RESULT fib 102334155
RESULT primes 1229
RESULT mandel 198968
```

The harness verifies all values match between Duo and reference C before comparing timing.