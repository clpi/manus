# Benchmarks

> **Canonical performance reference:** [`docs/performance.md`](../performance.md) — agent protocol, gap analysis, modification roadmap, and full historical ledger. Update that file after any benchmark-affecting change.

Duo includes a comprehensive benchmark suite comparing Duo against C, Lua, and LuaJIT.

## Running Benchmarks

```bash
zig build bench          # Duo vs C (40 workloads, hard gate)
zig build ml-bench       # ML kernels vs C (soft gate)
zig build honest-bench   # Runtime-seeded, no precomputation
zig build cross-bench    # Duo + C + Lua + LuaJIT (needs lua, luajit)
zig build wasm-bench     # WASM runtime comparison
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
| Prime sieve | 0.000200s | 0.017142s | 0.333939s | 0.079133s |
| Mandelbrot | 0.419117s | 0.471833s | 5.507780s | 1.200130s |
| Grid matrix | 0.009345s | 0.012224s | 1.266040s | 0.037441s |
| N-body | 0.081233s | 0.082203s | 1.433030s | 0.110827s |

Three rows this table used to carry — **Fibonacci(40), Table array, Bitcount** —
were REMOVED from the speed comparison by gap[096] and are no longer timed in
any of the four programs. Their kernels still run and their answers are still
compared against reference C; only the duration is gone, because Duo's codegen
substitutes a different ALGORITHM for each of them (an O(n) iteration for the
O(φⁿ) recursion, n(n+1)/2 for the O(n) fill-and-sum, an O(log n) identity for
the O(n log n) bit loop). A duration that compares two algorithms is not a
codegen measurement. The `Fibonacci(40) | 0.000000s | 0.288751s` row this
paragraph replaces was that mistake in print.

## Performance Characteristics

Rows are reported individually; there is no aggregate speedup claim here, and
the "Duo beats C by 4× (Fibonacci is lowered to iterative)" line that used to
sit here was the removed row's fake win restated as a geometric mean.
`law.c.floor` (§47) makes any dominance claim conditional on the C-equivalent
realization being a candidate the compiler costs and can choose, which this tree
does not implement. `scripts/run_benchmark.duo` publishes its LOSSES in the same
table as its wins, and every runtime must produce the SAME ANSWER before any
speed number is compared.

A 0.000000s duration is a FINDING, not a result. The harness classifies such a
row as `folded` and refuses to credit it as a win; the explanation this
paragraph replaces — "constant-folding and dead-code elimination … the result is
unused" — was wrong on the facts, since every benchmark result is printed and
compared, so nothing is dead.

## Benchmark Sources

| File | Description |
|------|-------------|
| `examples/benchmark.lua` | Primary benchmark driver (untyped Lua) |
| `examples/benchmark.duo` | Mirror of benchmark.lua (typed version) |
| `examples/benchmark_pure.lua` | Type-annotation-free variant |
| `examples/benchmark_c.c` | Reference C implementation |
| `scripts/run_benchmark.duo` | Correctness (40 rows) + timing (37 rows) harness |
| `scripts/run_cross_benchmark.duo` | Cross-language harness (21 rows) |

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