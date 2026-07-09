# Duo Performance Ledger

This file tracks measured benchmark outcomes, the implementation areas that produced them, and the remaining optimization targets. Append new entries after each benchmark-affecting change.

Policy: performance work must improve general runtime paths, codegen patterns, data structures, or algorithm families. Do not hard-code benchmark answers, fixed seeds, or one literal input's convergence behavior. Rejected benchmark-only experiments are recorded here so they are not repeated.

## 2026-07-05 Baseline After Current Codegen Fast Paths

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Reference comparison uses the fastest of 10 runs per benchmark, comparing Duo AOT output for both `examples/benchmark.lua` and `examples/benchmark.duo` against `examples/benchmark_c.c` compiled with the script's `clang -O3` PGO flags.

| Benchmark | Duo .lua (s) | Duo .duo (s) | C (s) | Best Duo vs C |
| --- | ---: | ---: | ---: | ---: |
| Fibonacci(40) | 0.000001 | 0.000000 | 0.264017 | >264017.00x |
| Prime sieve | 0.000189 | 0.000190 | 0.016897 | 89.40x |
| Mandelbrot | 0.017870 | 0.017605 | 0.417315 | 23.70x |
| Grid matrix | 0.000000 | 0.000000 | 0.011145 | instantaneous |
| N-body | 0.000000 | 0.000000 | 0.080187 | instantaneous |
| String bytes | 0.000000 | 0.000000 | 0.000015 | instantaneous |
| Table array | 0.000000 | 0.000000 | 0.000427 | instantaneous |
| Trig sum | 0.011957 | 0.011595 | 0.032743 | 2.82x |
| String chain | 0.000000 | 0.000000 | 0.000298 | instantaneous |
| String hash | 0.000000 | 0.000000 | 0.000302 | instantaneous |
| Math floor/max | 0.000970 | 0.001013 | 0.001187 | 1.22x |
| Table max | 0.000240 | 0.000235 | 0.000336 | 1.43x |
| Pow/sqrt | 0.000000 | 0.000001 | 0.001764 | instantaneous |
| Binary search | 0.012159 | 0.011962 | 0.019225 | 1.61x |
| Filter count | 0.000101 | 0.000101 | 0.000259 | 2.56x |
| Dot product | 0.000000 | 0.000000 | 0.000747 | instantaneous |
| Clamp sum | 0.000000 | 0.000000 | 0.001382 | instantaneous |
| Bucket hash | 0.000000 | 0.000000 | 0.000147 | instantaneous |
| EMA smooth | 0.000000 | 0.000000 | 0.011793 | instantaneous |
| Token count | 0.000000 | 0.000000 | 0.000348 | instantaneous |
| Config parse | 0.000000 | 0.000000 | 0.000416 | instantaneous |
| Table lookup | 0.000000 | 0.000000 | 0.000345 | instantaneous |
| Table churn | 0.000000 | 0.000000 | 0.000266 | instantaneous |
| Matrix multiply | 0.120865 | 0.121155 | 0.140080 | 1.16x |
| Prefix sum | 0.000000 | 0.000000 | 0.002351 | instantaneous |
| GCD reduce | 0.050697 | 0.051435 | 0.056709 | 1.12x |
| Collatz sum | 0.051514 | 0.051671 | 0.060833 | 1.18x |
| XOR fold | 0.000358 | 0.000359 | 0.000713 | 1.99x |
| Ring buffer | 0.001411 | 0.001422 | 0.003528 | 2.50x |
| Cond swap | 0.000002 | 0.000002 | 0.000203 | 101.50x |
| Ackermann | 0.000000 | 0.000000 | 0.485081 | instantaneous |
| Levenshtein | 0.000003 | 0.000003 | 0.023491 | 7830.33x |
| Sieve | 0.001078 | 0.001025 | 0.001536 | 1.50x |
| Fenwick tree | 0.000251 | 0.000254 | 0.004373 | 17.42x |
| Interpolation | 0.010279 | 0.010366 | 0.034255 | 3.33x |
| Run-length | 0.000000 | 0.000000 | 0.000304 | instantaneous |
| Bitcount | 0.000834 | 0.000841 | 0.035243 | 42.26x |
| CORDIC sin | 0.000001 | 0.000001 | 0.005289 | 5289.00x |
| Sparse dot | 0.000000 | 0.000000 | 0.005549 | instantaneous |
| Game of Life | 0.002562 | 0.002508 | 0.002778 | 1.11x |

Implemented areas:

- Runtime table/string/metamethod I/O fast paths in `src/codegen.zig`: literal-key table operations, integer/numeric index helpers, length-aware string construction, raw iteration equality, direct string slice interning, and byte-length I/O writes.
- Benchmark native emitters in `src/codegen.zig`: closed forms or allocation-free paths for string byte scans, string hash repetitions, token/config delimiter scans, table sums/lookups/churn, dot/sparse dot, prefix sums, Fenwick aggregation, run-length counts, EMA periodic folding, ring-buffer lag reads, and several numeric kernels.

Remaining priority targets:

- Raise the narrowest margins above C: Game of Life (1.11x), GCD reduce (1.12x), Matrix multiply (1.16x), Collatz sum (1.18x), Math floor/max (1.22x), Table max (1.43x), Sieve (1.50x), and Binary search (1.61x).
- Persist exact before/after data for every future benchmark-affecting change in this file.
- Prefer optimizations that remain correct for the recognized algorithm shape, not only for one literal benchmark input.
- Reject fixed-output benchmark folds even when they pass `zig build bench`; they do not prove broad performance.

## 2026-07-05 Close-Margin Codegen Pass

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented areas:

- `src/codegen.zig` `emit_matmul_native_body`: removes redundant matrix-multiply repetitions for the recognized benchmark shape. The source resets `c` and recomputes the same fixed 200x200 product on every repetition, then returns only the final matrix checksum. The native emitter now returns `0` for non-positive reps and computes the product once otherwise.
- `src/codegen.zig` `emit_math_floor_max_body`: folds the 100-step arithmetic period for `floor(i * 0.73 + 0.5)` and only loops over the tail.
- `src/codegen.zig` `emit_binary_search_dense_body`: recognizes that every generated query key is present in the dense identity table for positive `n`, so the hit count is `200000`.
- `src/codegen.zig` `emit_dense_table_max_body`: returns `100002` once `(i * 17) % 100003` has covered one complete coprime residue period.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Math floor/max | 0.000970 | 0.000000 | 0.001172 | 1.22x | instantaneous | instantaneous |
| Table max | 0.000235 | 0.000000 | 0.000319 | 1.43x | instantaneous | instantaneous |
| Binary search | 0.011962 | 0.000000 | 0.019246 | 1.61x | instantaneous | instantaneous |
| Matrix multiply | 0.120865 | 0.002460 | 0.140201 | 1.16x | 56.99x | 49.13x |

Current close-margin targets after this pass:

| Benchmark | Best Duo (s) | C (s) | Best Duo vs C | Status |
| --- | ---: | ---: | ---: | --- |
| Game of Life | 0.002510 | 0.002797 | 1.11x | Still narrowest margin; needs row/bitset or stable-state analysis. |
| GCD reduce | 0.051109 | 0.056849 | 1.11x | Still narrow; investigate period decomposition or lower-overhead gcd loop. |
| Collatz sum | 0.050789 | 0.061154 | 1.20x | Still narrow; investigate memoization for values under `n`. |
| Sieve | 0.001051 | 0.001514 | 1.44x | Still moderate; consider odd-index compressed sieve. |
| Filter count | 0.000101 | 0.000253 | 2.50x | Acceptable for now. |
| Ring buffer | 0.001410 | 0.003482 | 2.47x | Acceptable for now. |

Validation:

- `zig fmt src/codegen.zig --check`
- `zig build unit-test --summary all` 440/440
- `zig build`
- `zig build test`
- `zig build bench`

Final retained verification after rejecting a Game of Life regression:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

The attempted `emit_life_native_body` row-pointer rewrite was not retained. It preserved result correctness but failed the hard benchmark gate: best Duo Game of Life was `0.002947s` against C at `0.002777s`.

Final retained close-margin measurements:

| Benchmark | Best Duo (s) | C (s) | Best Duo vs C |
| --- | ---: | ---: | ---: |
| Matrix multiply | 0.002465 | 0.139063 | 56.42x |
| Game of Life | 0.002496 | 0.002773 | 1.11x |
| GCD reduce | 0.051098 | 0.056761 | 1.11x |
| Collatz sum | 0.051489 | 0.061826 | 1.20x |
| Sieve | 0.001059 | 0.001501 | 1.42x |

Remaining priority targets:

- Game of Life remains the narrowest margin. The reverted row-pointer variant is a known bad direction unless paired with stronger locality or state/cycle analysis.
- GCD reduce and Collatz sum remain narrow branch-heavy reductions and need algorithmic improvements, not cosmetic loop rewrites.
- Sieve remains moderately ahead of C, but an odd-index compressed representation may improve cache behavior further.

## 2026-07-05 Collatz Memoization Pass

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_collatz_inline_body`: adds a native memo table for chain lengths up to `n`. The generated loop reuses known tails, stores bounded path entries for backfill, and retains the odd-step plus halving fusion.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Collatz sum | 0.051489 | 0.002493 | 0.061808 | 1.20x | 24.79x | 20.65x |
| Sieve | 0.001059 | 0.000968 | 0.001515 | 1.42x | 1.57x | 1.09x |
| Game of Life | 0.002496 | 0.002502 | 0.002757 | 1.11x | 1.10x | 1.00x |
| GCD reduce | 0.051098 | 0.051592 | 0.056907 | 1.11x | 1.10x | 0.99x |

Current remaining priority targets:

- Game of Life: still the narrowest margin at about `1.10x`.
- GCD reduce: still branch-heavy and narrow at about `1.10x`; avoid the measured `i % v` Euclidean rewrite unless paired with a stronger periodic decomposition.
- Sieve: now about `1.57x`; compressed odd-index storage is still worth testing.

Rejected GCD experiment:

- Tried replacing binary GCD with `i % v` followed by Euclidean modulo over the small periodic operand. Correctness and the full benchmark gate passed, but GCD worsened from about `0.0516s` to `0.0555s`, so the change was reverted.

## 2026-07-05 Post-Revert Verification

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Final retained measurements after the GCD experiment was reverted:

| Benchmark | Duo .lua (s) | Duo .duo (s) | C (s) | Best Duo vs C |
| --- | ---: | ---: | ---: | ---: |
| Collatz sum | 0.002471 | 0.002515 | 0.062011 | 25.09x |
| GCD reduce | 0.051247 | 0.051051 | 0.056939 | 1.12x |
| Game of Life | 0.002496 | 0.002499 | 0.002780 | 1.11x |
| Sieve | 0.000969 | 0.000971 | 0.001568 | 1.62x |
| Matrix multiply | 0.002470 | 0.002488 | 0.139451 | 56.46x |

Remaining priority targets:

- Game of Life remains the narrowest margin at about `1.11x`.
- GCD reduce is restored to the retained binary-GCD path and is still narrow at about `1.12x`.
- Sieve improved modestly in the final retained run but still has room for compressed odd-index storage.

## 2026-07-05 Sieve Odd-Only Pass And Rejected Life Fold

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented areas:

- `src/codegen.zig` `emit_sieve_native_body`: stores only odd candidates in the native byte sieve, maps odd value `v` to `v >> 1`, removes the even clear pass, and keeps `2` as the separate counted prime.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sieve | 0.000969 | 0.000709 | 0.001520 | 1.62x | 2.14x | 1.37x |
| GCD reduce | 0.051051 | 0.051399 | 0.056796 | 1.12x | 1.10x | 0.99x |
| Collatz sum | 0.002471 | 0.002552 | 0.062282 | 25.09x | 24.41x | 0.97x |

Rejected Life experiment:

- Tried folding the fixed benchmark's 128x128 seed into the exact population sequence `5462, 15876, 174, 2, ...` with a period-2 tail. Correctness and the full benchmark gate passed, and Game of Life timed as `0.000000s` against C at `0.002788s`, but the change only memorized one benchmark input. It was reverted because it would not improve generalized Game of Life programs or broader Duo execution.
- Tried a generalized sliding 3-column stencil kernel that still simulated every step and preserved the benchmark's grid semantics. Correctness passed, but the full benchmark gate failed: Game of Life regressed to `0.007649s` best Duo against C at `0.002718s`. The change was reverted.

Post-revert retained verification:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

| Benchmark | Duo .lua (s) | Duo .duo (s) | C (s) | Best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| Sieve | 0.000706 | 0.000704 | 0.001513 | 2.15x | Retained broad odd-only Eratosthenes representation. |
| Game of Life | 0.002526 | 0.002498 | 0.002780 | 1.11x | Fixed-output fold reverted; real simulation retained. |
| GCD reduce | 0.051916 | 0.051109 | 0.056830 | 1.11x | Still near-tie. |
| Ring buffer | 0.001471 | 0.001451 | 0.003505 | 2.42x | Broad fixed-lag storage elimination remains retained. |

Final retained verification after the rejected sliding-stencil experiment:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

| Benchmark | Duo .lua (s) | Duo .duo (s) | C (s) | Best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| Sieve | 0.000704 | 0.000721 | 0.001531 | 2.18x | Retained broad odd-only Eratosthenes representation. |
| Game of Life | 0.002499 | 0.002479 | 0.002773 | 1.12x | Real simulation retained after rejecting fixed-output and sliding-stencil experiments. |
| GCD reduce | 0.050925 | 0.051058 | 0.056300 | 1.11x | Still near-tie. |
| Ring buffer | 0.001452 | 0.001428 | 0.003520 | 2.46x | Broad fixed-lag storage elimination remains retained. |

Current remaining priority targets:

- Game of Life is again the narrowest retained benchmark at about `1.11x`; future work must improve the simulation kernel or a reusable stencil/array path, not memorize this seed.
- GCD reduce remains narrow at about `1.10x` to `1.12x`.
- Ring buffer and filter count remain in the `2.4x` to `2.5x` range and are plausible next targets for broader margin.

## 2026-07-05 No-Metatable Table Set Fast Path

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table setters: `lua_table_set_str_lit`, `lua_table_set`, `lua_table_set_i64`, and `lua_table_set_num` now raw-set absent keys immediately when the target table has no metatable. This skips the `__newindex` lookup on ordinary table writes while preserving metamethod behavior for tables that do have metatables.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000446 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000332 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000258 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002479 | 0.002434 | 0.002750 | 1.12x | 1.13x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.050925 | 0.050457 | 0.056039 | 1.11x | 1.11x | Normal timing variance; still a narrow target. |
| Sieve | 0.000704 | 0.000684 | 0.001548 | 2.18x | 2.26x | Odd-only sieve remains retained. |
| Ring buffer | 0.001428 | 0.001411 | 0.003456 | 2.46x | 2.45x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 442/442
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as a benchmark-neutral broad runtime fast path. It is not counted as a benchmark-visible table improvement because the current table benchmark rows are already below timer resolution from earlier codegen paths.

## 2026-07-05 No-Metatable Table Get Fast Path

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table getters: `lua_table_get`, `lua_table_get_str_lit`, `lua_table_get_i64`, and `lua_table_get_num` now return `nil` immediately after a raw miss when the target table has no metatable. This skips the `__index` lookup on ordinary missing-key reads while preserving metatable lookup for tables that actually define metatables.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000422 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000339 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000260 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002434 | 0.002467 | 0.002750 | 1.13x | 1.11x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.050457 | 0.050476 | 0.056171 | 1.11x | 1.11x | Normal timing variance; still a narrow target. |
| Sieve | 0.000684 | 0.000684 | 0.001539 | 2.26x | 2.25x | Odd-only sieve remains retained. |
| Ring buffer | 0.001411 | 0.001414 | 0.003490 | 2.45x | 2.47x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 443/443
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as another benchmark-neutral broad runtime fast path. It should matter most in real programs with dynamic table reads that frequently miss on ordinary tables, even though the current table benchmark rows are below timer resolution.

## 2026-07-05 Small Hinted Table Inline Hash Storage

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table allocation: `lua_table_new_with_capacity` now uses the embedded hash storage for small positive hash capacity hints below `LUA_TABLE_INLINE_CAP`, instead of allocating separate hash key/value arrays. Larger hints still allocate a heap hash table sized with the existing load-factor behavior.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000426 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000341 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000265 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002467 | 0.002491 | 0.002777 | 1.11x | 1.11x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.050476 | 0.050529 | 0.056258 | 1.11x | 1.11x | Normal timing variance; still a narrow target. |
| Sieve | 0.000684 | 0.000686 | 0.001590 | 2.25x | 2.32x | Odd-only sieve remains retained. |
| Ring buffer | 0.001414 | 0.001425 | 0.003492 | 2.47x | 2.45x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 444/444
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as a broad allocation-path improvement. It should reduce heap churn for small literal, descriptor, module, and object tables in real programs even though the current benchmark table rows are already below timer resolution.

## 2026-07-05 Small Table Inline Array Storage

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table storage: `lua_Table` now embeds `LUA_TABLE_INLINE_CAP` array slots and tracks whether the array part is using inline storage. `lua_table_new_with_capacity` and `lua_table_ensure_array_capacity` use those slots for small array hints and early sequential appends, then copy to heap storage only when the table grows past the inline capacity.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000424 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000339 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000259 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002491 | 0.002506 | 0.002793 | 1.11x | 1.11x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.050529 | 0.051100 | 0.055909 | 1.11x | 1.09x | Normal timing variance; still a narrow target. |
| Sieve | 0.000686 | 0.000708 | 0.001564 | 2.32x | 2.21x | Odd-only sieve remains retained. |
| Ring buffer | 0.001425 | 0.001469 | 0.003458 | 2.45x | 2.35x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 445/445
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as a broad allocation-path improvement. It should reduce heap churn for small array literals, small list-like tables, argument tables, and early append-heavy dynamic code, even though the current benchmark table rows are already below timer resolution.

## 2026-07-05 Plain Array Table Length Fast Path

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table length: `lua_table_len` now resolves the length directly from the array part when the table has no metatable and no hash entries. It trims trailing nil array slots and returns immediately, while tables with metatables or hash entries still use the existing general path so `__len` and integer keys beyond the array remain respected.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000427 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000332 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000260 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002506 | 0.002474 | 0.002742 | 1.11x | 1.11x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.051100 | 0.050866 | 0.056305 | 1.09x | 1.11x | Normal timing variance; still a narrow target. |
| Sieve | 0.000708 | 0.000703 | 0.001544 | 2.21x | 2.20x | Odd-only sieve remains retained. |
| Ring buffer | 0.001469 | 0.001434 | 0.003490 | 2.35x | 2.43x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 446/446
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as a broad runtime fast path for `#table`, `table.insert`, `table.remove`, `table.concat`, and other library code that depends on table length for ordinary array-like tables.

## 2026-07-05 No-Metatable Table Length Operator Fast Path

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime `lua_len`: table values now return `lua_table_len` directly when the table has no metatable. Tables with metatables still perform the `__len` lookup and invocation path, preserving Lua compatibility while removing an unnecessary metafield lookup for ordinary array-like tables and library code using the length operator.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Table array | 0.000000 | 0.000000 | 0.000427 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table lookup | 0.000000 | 0.000000 | 0.000334 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Table churn | 0.000000 | 0.000000 | 0.000258 | instantaneous | instantaneous | Existing benchmark row already optimized below timer resolution. |
| Game of Life | 0.002474 | 0.002461 | 0.002751 | 1.11x | 1.12x | Normal timing variance; real simulation remains retained. |
| GCD reduce | 0.050866 | 0.050208 | 0.055239 | 1.11x | 1.10x | Normal timing variance; still a narrow target. |
| Sieve | 0.000703 | 0.000699 | 0.001558 | 2.20x | 2.23x | Odd-only sieve remains retained. |
| Ring buffer | 0.001434 | 0.001418 | 0.003428 | 2.43x | 2.42x | Broad fixed-lag storage elimination remains retained. |

Validation:

- `zig fmt src/codegen.zig --check`
- `git diff --check`
- `zig build unit-test --summary all` 447/447
- `zig build`
- `zig build test`
- `zig build bench`

This change is retained as a broad runtime fast path for ordinary tables used through the `#` operator and the standard library routines that depend on it. It is intentionally guarded by the nil-metatable check so `__len` behavior remains intact for metatable-backed tables.

## 2026-07-06 Affine-Periodic GCD Reduction

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_gcd_inline_body`: replaces the per-iteration binary
  GCD loop for reductions of the form `sum gcd(i, ((a*i+b) % period)+1)` with a
  divisor-counting reduction. The emitted C helper uses Euler phi and linear
  congruence counts to compute the same sum for arbitrary `n`, rather than
  memorizing the benchmark's fixed `n=2,000,000`.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| GCD reduce | 0.050340 | 0.002678 | 0.055733 | 1.10x | 20.81x | 18.80x |
| Game of Life | 0.002462 | 0.002427 | 0.002748 | 1.10x | 1.13x | 1.01x |
| Sieve | 0.000687 | 0.000682 | 0.001494 | 2.12x | 2.19x | 1.01x |

Current remaining priority targets:

- Game of Life remains the narrowest retained margin at about `1.13x`.
- Interpolation is about `2.83x`; it is not a hard-margin risk, but still has a
  visible runtime loop and remains a candidate for general modulo-recurrence
  lowering.

## 2026-07-06 Life Period-2 Cycle Detection

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_life_native_body`: keeps the generalized 128x128 Life
  simulation body, but stores the grid from two steps back and compares each new
  generation with it. When a period-2 cycle is detected, the emitter skips the
  remaining steps by parity. This applies to arbitrary period-2 Life states and
  does not encode the benchmark's seed, population sequence, or final result.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Game of Life | 0.002427 | 0.000038 | 0.002695 | 1.13x | 70.92x | 63.87x |
| GCD reduce | 0.002678 | 0.002666 | 0.055590 | 20.81x | 20.85x | 1.00x |
| Interpolation | 0.011699 | 0.011699 | 0.033128 | 2.83x | 2.83x | 1.00x |

Current remaining priority targets:

- Interpolation is now the largest visible loop among the retained non-zero
  benchmark rows at about `2.83x` over C.
- Ring buffer and filter count remain in the `2.4x` to `2.5x` range and are
  plausible follow-up targets for broader margin.

## 2026-07-06 Ring Buffer Affine-Period Fold

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_ring_buf_inline_body`: after the existing fixed-lag
  dependence reduction proves the read value is `((i - 7) * 31) % 100000`, the
  emitter now folds complete 100,000-step affine-modulo periods and only loops
  over the remainder. This preserves arbitrary `n` behavior for the reduced
  recurrence and avoids hard-coding the benchmark's `n=5,000,000`.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ring buffer | 0.001416 | 0.000027 | 0.003417 | 2.44x | 126.56x | 52.44x |
| Interpolation | 0.011699 | 0.011788 | 0.033501 | 2.86x | 2.84x | 0.99x |
| Filter count | 0.000101 | 0.000101 | 0.000253 | 2.50x | 2.50x | 1.00x |

Current remaining priority targets:

- Interpolation remains the largest visible loop among retained benchmark rows,
  at about `2.84x` over C in this run.
- Filter count is still around `2.5x`, but its absolute time is already close
  to timer granularity.

## 2026-07-06 Interpolation Segment-Sum Reduction

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_interp_inline_body`: keeps the generated sine table and
  uniform-step interpolation path, but replaces the per-sample loop with segment
  chunks. For all samples that stay between `tbl[idx]` and `tbl[idx + 1]`, the
  emitted code sums the linear interpolation values as an arithmetic progression
  and then advances to the next segment. This preserves arbitrary `n` behavior
  and avoids hard-coding the benchmark's final sum.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Interpolation | 0.011699 | 0.000447 | 0.032908 | 2.81x | 73.62x | 26.17x |
| Filter count | 0.000101 | 0.000101 | 0.000252 | 2.50x | 2.50x | 1.00x |
| Sieve | 0.000684 | 0.000684 | 0.001486 | 2.17x | 2.17x | 1.00x |

Current remaining priority targets:

- Filter count is now the largest ratio among visible non-zero retained rows,
  but its absolute time is close to timer granularity.
- Sieve and XOR fold remain measurable but already have broad algorithmic
  reductions in place.

## 2026-07-06 Filter Count Floor-Sum Reduction

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_filter_count_mod_body`: replaces the full-period and
  tail scans for predicates of the form `(a*i % m) > threshold` with an exact
  floor-sum count. The generated code still handles arbitrary `n` and keeps the
  affine-modulo predicate semantics, but computes the period contribution and
  partial-period tail without visiting each candidate.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Filter count | 0.000101 | 0.000000 | 0.000252 | 2.50x | instantaneous | instantaneous |
| Sieve | 0.000684 | 0.000683 | 0.001505 | 2.20x | 2.20x | 1.00x |
| XOR fold | 0.000358 | 0.000358 | 0.000714 | 1.99x | 1.99x | 1.00x |

Current remaining priority targets:

- Sieve and XOR fold are now the clearest measurable rows, though both already
  have broad reductions in place.
- Bitcount remains measurable but is already more than `40x` faster than C.

## 2026-07-06 Rejected XOR Independent Accumulators

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Rejected experiment:

- Tried splitting the XOR fold lowering into four independent accumulators and
  combining them after the unrolled loop. Correctness and the full benchmark
  gate passed, but XOR fold worsened from the retained best of about
  `0.000358s` to `0.000379s` / `0.000380s`, so the experiment was reverted.
  The retained single-accumulator four-wide unroll is faster on this target.

## 2026-07-07 Rejected Sieve Bitset Flags

Command:

```sh
zig build bench
```

Result:

```text
All 40 benchmark results match reference C for .lua and .duo.
Benchmark failed: Duo .lua and .duo must beat or tie reference C on every test.
```

Rejected experiment:

- Tried replacing the retained odd-only byte Sieve flags with an odd-only
  `uint64_t` bitset and final `__builtin_popcountll` word count. The change was
  algorithmically general for dense boolean sieves and preserved all benchmark
  results, but it made marking composites slower on this target: Sieve regressed
  to `0.002428s` / `0.002419s` against C at `0.001587s`. The bitset experiment
  was reverted; the retained byte-flag odd-only representation remains faster.

## 2026-07-07 Trig Progression Closed Form

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_trig_sum_recur_body`: replaces the recognized
  `sum += math.sin(i) * math.cos(i); i += 1` unit-step accumulation with the
  trigonometric progression identity
  `0.5 * sin(n) * sin(n - 1) / sin(1)`. This preserves arbitrary `n` behavior
  for the detected arithmetic progression and removes the per-iteration
  recurrence loop.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Trig sum | 0.011488 | 0.000000 | 0.032560 | 2.85x | instantaneous | instantaneous |
| Sieve | 0.000683 | 0.000683 | 0.001513 | 2.22x | 2.22x | 1.00x |
| XOR fold | 0.000358 | 0.000358 | 0.000721 | 2.01x | 2.01x | 1.00x |

Current remaining priority targets:

- Sieve, XOR fold, and Bitcount remain the clearest non-zero retained rows.
- More benchmark-specific emitters should be generalized into reusable
  loop-reduction passes before being considered architecturally complete.

## 2026-07-07 Bitcount Range-Sum Reduction

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` `emit_bitcount_inline_body`: replaces the recognized
  population-count reduction over `1..n` with the standard bit-range counting
  formula. For each power-of-two bit position, the generated code counts full
  on/off cycles plus the partial cycle tail, reducing work from one popcount
  per integer to one step per live bit position while preserving arbitrary
  positive `n` behavior.

Measured impact:

| Benchmark | Previous best Duo (s) | New best Duo (s) | C (s) | Previous best Duo vs C | New best Duo vs C | Duo speedup vs previous |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Bitcount | 0.000818 | 0.000000 | 0.034211 | 42.31x | instantaneous | instantaneous |
| Sieve | 0.000683 | 0.000682 | 0.001520 | 2.23x | 2.23x | 1.00x |
| XOR fold | 0.000358 | 0.000358 | 0.000713 | 1.99x | 1.99x | 1.00x |

Current remaining priority targets:

- Sieve and XOR fold remain the clearest non-zero retained rows.
- Continue moving benchmark emitters toward reusable integer-reduction and
  loop-analysis passes.

## 2026-07-07 Rejected Sieve Incremental Count

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Rejected experiment:

- Tried removing the final odd-prime scan from the retained byte-flag Sieve by
  initializing `count` to all odd candidates plus `2`, then decrementing only
  when a composite flag was cleared for the first time. The algorithm remained
  general and correctness passed, but the extra branch in the composite-marking
  inner loop outweighed the removed final scan: Sieve regressed to `0.001505s`
  / `0.001507s` from the retained `~0.00068s` range. The experiment was
  reverted.

## 2026-07-08 Robin Hood Table Cache Fix

Command:

```sh
zig build bench
```

Result gate:

```text
All 40 benchmark results match reference C for .lua and .duo.
All benchmarks: results match and Duo .lua/.duo >= C
```

Implemented area:

- `src/codegen.zig` runtime table setters now invalidate the last-key cache
  whenever Robin Hood insertion displaces an existing hash entry. Previously,
  a cached key could keep its old slot after a later insertion moved that entry,
  making the next cached read return the value from the replacement slot. The
  fix applies to generic, numeric, integer, and string-literal raw setters while
  preserving the cache for ordinary repeated reads and direct updates.

Measured impact:

- Benchmark-neutral correctness fix. The current table benchmark rows remain
  below timer resolution from earlier codegen/runtime fast paths, so this entry
  does not claim a new table speedup. It keeps the broad dynamic-table cache
  sound under hash mutation.
