# Duo

[![CI](https://github.com/clpi/luo-duo/actions/workflows/ci.yml/badge.svg)](https://github.com/clpi/luo-duo/actions/workflows/ci.yml)

Duo is an experimental Lua-derived ahead-of-time language and compiler **written in Zig** (not self-hosted). Its **default backend emits C** and invokes Clang or `zig cc` to produce native binaries and Wasm. Duo includes aggressive typed specialization for `.duo` programs and an **experimental direct ARM64 Mach-O backend** for a restricted scalar subset (`--backend=direct`).

**Honest status:** Pass 11 Profile A (C-backend default) is **closed** — run `zig build pass11-gate`. Self-hosting, universal direct native compilation, and globally zero-boxing semantics remain **out of scope**. See `duo catalog | jq '.pass11'` and [docs/archive/pass11_release_proof.md](docs/archive/pass11_release_proof.md).

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
duo init    [name]              scaffold src/main.duo            [see note]
duo build   [target]            build the default or named target [see note]
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

> **Note — `duo init` / `duo build` do not work today (measured 2026-08-08).**
> `duo init` writes one file, `src/main.duo`, and no `build.duo` (this section
> used to claim both). The file it writes opens with `@build.project({…})`,
> `@build.run({…})` and `@build.test({…})`, and the front end rejects every one
> of them with `error: macro expansion error: UnknownMacro`. So a freshly
> initialised project fails `duo check`, `duo build` and `duo run` — exit 1 on
> all three — even though `duo init` itself exits 0 and prints
> `next: duo build`. The inline project model in `src/build_framework.zig` has
> unit-test coverage that drives the parser and sema directly, which is why the
> break does not show up there. Compiling a file straight through
> (`duo compile`, `duo run <file>`, `duo check <file>`) is unaffected.

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

### Latest results

**Withdrawn, 2026-08-08.** A results table used to sit here reporting a
geometric-mean "Duo beats C by 4×", with eleven rows at `0.000000` explained as
constant-folding and dead-code elimination.

That explanation was not true. Ten kernel substitutions were removed from the
suite in one day: three returned **frozen literal answers** when the argument
matched the benchmark (`if (steps == 5000000) return 9.378…e-08;` — no
integration ran), and seven **computed the benchmark's constants** for programs
that had stopped asking for them. Three harness defects hid it: a float
comparator that compared magnitudes (so a sign flip differed by zero), a
`RESULT_FAIL` flag that could not hold a value, and a timing collector that
never seeded its minimum. `CLAUDE.md` §3 records the whole thing.

The withdrawn numbers were produced by that suite, so they are not evidence
and they are not reprinted here. Run `zig build bench` and
`zig build cross-bench` yourself; the rules any future table must satisfy —
no recognizer keyed on a function name, a literal or a loop bound; verify by
value, never by "it compiled"; positive-control every zero — are in `CLAUDE.md`
§3 and are not negotiable.

## CI/CD

Every push runs:

- `zig build` — compiler build
- `zig build unit-test` — Zig unit tests. **Currently red**: measured
  2026-08-08 on `canonical-to-relation`, 1244/1302 pass, 54 fail, 4 crash, 14
  leaks. The failures cluster in `mono`, `sema`, `pass*_gate` and codegen
  string lowering. This line previously read "all 393 unit tests", which was
  wrong about both the count and the colour.
- `zig build test` — unit tests, compile-fail tests, and report-styling guard
- `zig build agent-smoke` — tier-0 gate. **Green** as of the same measurement,
  and it is the gate to trust before pushing.
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

This executes `scripts/run_benchmark.duo`, which:

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
| `scripts/run_benchmark.duo` | Correctness + timing harness |
| `scripts/run_cross_benchmark.duo` | Cross-language harness (Duo + C + Lua + LuaJIT) |

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
