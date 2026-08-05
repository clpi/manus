# Duo

[![CI](https://github.com/clpi/luo-duo/actions/workflows/ci.yml/badge.svg)](https://github.com/clpi/luo-duo/actions/workflows/ci.yml)

Duo is an experimental Lua-derived ahead-of-time language and compiler **written in Zig** (not self-hosted). Its **default backend emits C** and invokes Clang or `zig cc` to produce native binaries and Wasm. Duo includes aggressive typed specialization for `.duo` programs and an **experimental direct ARM64 Mach-O backend** for a restricted scalar subset (`--backend=direct`).

**Honest status:** Pass 11 Profile A (C-backend default) is **closed** — run `zig build pass11-gate`. Self-hosting, universal direct native compilation, and globally zero-boxing semantics remain **out of scope**. See `duo catalog | jq '.pass11'` and [docs/plans/pass11_release_proof.md](docs/plans/pass11_release_proof.md).

## Documentation

| Document | Purpose |
| --- | --- |
| [docs/language.md](docs/language.md) | Language reference entry |
| [docs/compiler.md](docs/compiler.md) | Compiler architecture and modules |
| [docs/bootstrap.md](docs/bootstrap.md) | Build chain and validation tiers |
| [docs/tooling.md](docs/tooling.md) | CLI, editors, MCP, validation scripts |
| [docs/contributing.md](docs/contributing.md) | Contributor workflow |
| [docs/release.md](docs/release.md) | Release checklist |
| [docs/src/SUMMARY.md](docs/src/SUMMARY.md) | Detailed topic index |
| [docs/performance.md](docs/performance.md) | Benchmark ledger |

Machine-readable program status: `./zig-out/bin/duo catalog`.

## Syntax at a Glance

```lua
-- Compact functions (no keywords needed)
add(a: i64, b: i64): i64 a + b end
distance(p: Point): f64 p.x * p.x + p.y * p.y end

-- Descriptors replace struct/enum/concept keywords
Point: @{ x: f64, y: f64 }
Color: @{ Red, Green, Blue }
Sprite: @{ ..Named, ..Positioned, color: str }  -- composition

-- Pipelines with field projections
users:filter(.active):map(.name):each(print)

-- Table spread and newline separators
config = {
    ..defaults
    workers = 8
    debug = true
}

-- Compile-time evaluation
size = @(64 * 1024)
Vec4f = @(Vector(f32, 4))

-- Backends (Pass 11 — explicit, no silent fallback)
-- duo compile file.duo                         # C backend (default)
-- duo compile file.duo --backend=direct        # experimental ARM64 Mach-O
-- duo compile file.duo --target native-exe --backend=direct
```

## Editor support

Official editor plugins for Duo live under `ext/`:

- **VS Code** — `ext/vscode-duo/` — Includes LSP integration with `duo-lsp`
- **Vim / Neovim** — `ext/vim-duo/`
- **Helix** — `ext/helix/` (linked from `ext/`)
- **Zed** — `ext/zed-duo/` — Tree-sitter + LSP config

The editor plugins provide file-type detection, syntax highlighting for all Duo syntax, and LSP integration. The LSP server (`ext/duo-lsp/src/server.duo`) is written in Duo and provides diagnostics, document symbols, hover, go-to-definition, and completions.

## Build

Requires Zig 0.17.0-dev.

```bash
zig build
```

The compiler binary is installed to `zig-out/bin/duo`.

## Usage

```
duo compile <file>              compile to native binary
duo init    [name]              create build.duo and src/main.duo
duo build   [target]            build the default or named build.duo target
duo run     [file|target]       compile and run a file, or run a build target
duo check   <file>              type-check only
duo dump-c  <file>              print generated C to stdout
duo fmt     <file>              format a .duo/.lua file
duo completion <shell>          generate shell completions (bash, zsh, fish, nu)

Options:
  -o <name>          output binary name
  -O<n>              optimisation level (default: -O3)
  --cc <path>        C compiler (default: clang)
  --target <triple>  cross-compilation target (e.g. wasm32-wasi)
  --load-chunk       compile as shared library for runtime load()
  --pgo              profile-guided optimisation (two-pass compile)
  --shared-memory    enable WASM shared memory (wasm32-wasi only)
  --lib              library mode: export @export functions, skip _start
  -v, --verbose      show C compiler warnings
```

## WASM compilation

Compile any `.duo` or `.lua` file to WebAssembly:

```bash
duo compile examples/wasm/typed_fib.duo --target wasm32-wasi -o typed_fib.wasm
wasmtime typed_fib.wasm
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
- `zig build unit-test` — all 393 unit tests
- `zig build test` — unit tests, compile-fail tests, and report-styling guard
- WASM compilation smoke test
- WASM codegen compatibility tests
- WASI execution tests (wasmtime + wabt)
- Full benchmark suite (on push to main, macOS runner)

Tagged releases (`v*`) produce GitHub Releases with `duo` binaries for Linux and macOS.

## Benchmark suite (Duo vs C)

Run the full gate (correctness + timing):

```bash
zig build bench
```

This executes `scripts/run_benchmark.sh`, which:

1. Compiles `examples/benchmark.lua` with Duo and `examples/benchmark_c.c` with Clang (`-O3 -ffast-math -march=native -flto`).
2. Verifies all 40 `RESULT <id> <value>` lines match between Duo and reference C.
3. Runs each benchmark 10 times and compares minimum wall times. **Duo must beat or tie C on every test** (1% slack on C time).

### Sources

| File | Role |
|------|------|
| `examples/benchmark.lua` | Primary benchmark driver (untyped Lua) |
| `examples/benchmark.duo` | Mirror of `benchmark.lua` (same 40 workloads; kept in sync) |
| `examples/benchmark_pure.lua` | Type-annotation-free variant (for Lua/LuaJIT runners) |
| `examples/benchmark_c.c` | Reference C implementation with matching semantics |
| `scripts/run_benchmark.sh` | Correctness + timing harness |
| `scripts/run_cross_benchmark.sh` | Cross-language harness (Duo + C + Lua + LuaJIT) |

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
| 24 | `matmul` | Small matrix multiply (nested loop + indexed access) |
| 25 | `prefix` | Prefix sum scan (serial accumulation) |
| 26 | `gcd` | GCD reduction (Euclidean algorithm, branch-heavy) |
| 27 | `collatz` | Collatz chain length (unpredictable branching) |
| 28 | `xorfold` | XOR fold / bit manipulation reduction |
| 29 | `ringbuf` | Ring buffer write/read (modulo indexing) |
| 30 | `cond_swap` | Conditional swap reduce (sorting-kernel pattern) |
| 31 | `ack` | Ackermann function (deep recursion stress) |
| 32 | `leven` | Levenshtein distance (2D DP table) |
| 33 | `sieve` | Sieve of Eratosthenes (boolean array scan) |
| 34 | `fenwick` | Fenwick tree point-update + prefix-query |
| 35 | `interp` | Linear interpolation table (float index) |
| 36 | `run_len` | Run-length encoding count (byte comparison) |
| 37 | `bitcount` | Population count / Hamming weight |
| 38 | `cordic` | Taylor-series sin approximation (shift+add) |
| 39 | `sparse` | Sparse vector dot product (stride access) |
| 40 | `life` | Game of Life step (2D neighbor count) |

Each section prints `RESULT <id> <value>` for automated verification.

## Manual runs

```bash
duo run examples/benchmark.lua
duo compile examples/benchmark.lua -o /tmp/bench.out && /tmp/bench.out
clang -O3 -ffast-math -march=native -flto -lm -o /tmp/c_bench examples/benchmark_c.c && /tmp/c_bench
```
