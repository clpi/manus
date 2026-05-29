# Duo

Duo is a Lua-like language that compiles to native C (AOT). This repository includes a 23-benchmark suite comparing Duo against hand-written reference C.

## Build

```bash
zig build
```

The compiler binary is installed to `zig-out/bin/duo`.

## Benchmark suite

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
| `examples/benchmark.lua` | Primary benchmark driver (untyped Lua) |
| `examples/benchmark.duo` | Mirror of `benchmark.lua` (same 23 workloads; kept in sync) |
| `examples/benchmark_c.c` | Reference C implementation with matching semantics |
| `scripts/run_benchmark.sh` | Correctness + timing harness |

### Benchmarks (high → practical stdlib)

| # | ID | Models |
|---|-----|--------|
| 1 | `fib` | Recursive numeric hot loop (lowered to iterative) |
| 2 | `primes` | Trial-division / sieve-style integer scan |
| 3 | `mandel` | Float escape-time (Mandelbrot core) |
| 4 | `grid` | Nested double loop (spectral-norm style) |
| 5 | `nbody` | Multi-body physics integration |
| 6 | `str_bytes` | `string.rep`, `len`, `byte` checksum |
| 7 | `table_sum` | Dense indexed table fill + sum |
| 8 | `trig` | `math.sin` / `math.cos` accumulation |
| 9 | `str_chain` | String length + repeat chain |
| 10 | `str_hash` | Rolling hash over repeated literal |
| 11 | `floor_max` | `math.floor` + `math.max` |
| 12 | `table_max` | Dense table max scan |
| 13 | `pow_sqrt` | `math.pow` + `math.sqrt` |
| 14 | `bsearch` | Sorted table binary search |
| 15 | `filter` | Predicate count / analytics filter |
| 16 | `dot` | Dot product of two vectors |
| 17 | `clamp` | `math.min` / `math.max` saturate |
| 18 | `bucket` | Histogram bucket hash |
| 19 | `ema` | Exponential moving average |
| 20 | `token` | Token / whitespace counting |
| 21 | `parse` | JSON-ish delimiter byte sum |
| 22 | `lookup` | Indexed table lookup accumulation |
| 23 | `churn` | Table insert + aggregate |

Each section prints `RESULT <id> <value>` for automated verification.

## Manual runs

```bash
duo run examples/benchmark.lua
duo compile examples/benchmark.lua -o /tmp/bench.out && /tmp/bench.out
clang -O3 -ffast-math -march=native -flto -lm -o /tmp/c_bench examples/benchmark_c.c && /tmp/c_bench
```
