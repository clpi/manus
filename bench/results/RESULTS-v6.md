# Benchmark results — v6 (current main)

| # | directive |
|---|---|
| 1 | Re-run of the skeptical benchmark suite (`bench/run.sh`) on current main at `ae5532b2`, 21 interleaved rounds, 3 warmup, median primary. |
| 2 | Generated 2026-09-12. |
| 3 | Raw tables: `bench/RESULTS.md` (rewritten by the run). |

| # | directive |
|---|---|
| 1 | Baseline: v5 at `85886ee3` (2026-09-11). |
| 2 | Since v5, fix1 (`edd80d38`, compile-time loop evaluation) and fix2 (`ae5532b2`, same-variable constant-chain accumulator) landed, plus egraph/canon/hooks (`dfc9534c`), size hooks (`04a2655f`), identical code folding (`cc0c9260`), and the machine outliner (`5a4e64c8`). |

| # | directive |
|---|---|
| 1 | Methodology (unchanged from v5): Idol native compiler rebuilt from `lib/compiler/native.id` at run start; each program built with Idol, clang -O3, gcc -O3; correctness gate (identical exit codes) passed on all 10 programs |
| 2 | 21 interleaved timed rounds |
| 3 | Welch t-test; compile time is median-of-5 source-to-executable; object size is `.o` bytes. `bench/programs/*.id` sources withheld per the vocabulary gate (same as v5). |

## Runtime: v5 → v6 deltas (Idol median vs clang median)

| program | v5 idol | v5 clang | v5 margin | v6 idol | v6 clang | v6 margin | delta |
|---|---|---|---|---|---|---|---|
| sum | 0.027992 | 0.002259 | -1138.88% loss* | 0.001866 | 0.001865 | -0.05% tie | **+1138.8pp FIXED** |
| arith | 0.054334 | 0.041590 | -30.64% loss* | 0.042078 | 0.041724 | -0.85% tie | **+29.8pp FIXED** |
| bigconst | 0.028132 | 0.002465 | -1041.19% loss* | 0.001979 | 0.001973 | -0.30% tie | **+1040.9pp FIXED** |
| fib | 0.001918 | 0.001900 | -0.93% tie | 0.002469 | 0.002527 | +2.31% tie | tie → tie |
| startup | 0.002213 | 0.002285 | +3.16% tie | 0.001815 | 0.001739 | -4.38% tie | tie → tie |
| nest | 0.003583 | 0.002476 | -44.71% loss* | 0.003887 | 0.002698 | -44.04% loss* | flat, loss persists |
| div | 0.043223 | 0.032951 | -31.17% loss* | 0.047600 | 0.035909 | -32.57% loss* | flat, loss persists |
| zerotrip | 0.004844 | 0.002291 | -111.42% loss* | 0.004734 | 0.002247 | -110.68% loss* | flat, loss persists |
| upbranch | 0.010407 | 0.008753 | -18.89% loss* | 0.011236 | 0.009055 | -24.09% loss* | -5.2pp, loss persists |
| mul13 | 0.054247 | 0.054490 | +0.45% tie | 0.061525 | 0.057448 | -7.10% loss* | **REGRESSION: tie → loss** |

| # | directive |
|---|---|
| 1 | `*` = statistically significant (Welch p < 0.05) |
| 2 | "tie" = not significant. |
| 3 | Margin = (clang − idol) / clang; positive favors Idol. |

| # | directive |
|---|---|
| 1 | Scoreboard: v5 was 0 wins / 3 ties / 7 losses. v6 is 0 wins / 5 ties / 5 losses. |
| 2 | Compile time 10/10 wins and object size 10/10 wins are retained (see below). |

## Fixed since v5

- **sum** (−1138.88% → −0.05%, p=0.5835 ns): fix1 repaired compile-time
  loop evaluation; the 100M-iteration loop now folds to a constant.
  Idol median 0.027992s → 0.001866s.
- **bigconst** (−1041.19% → −0.30%, p=0.3353 ns): same fix; `x+5000−4000`
  per-iteration chain now folds. Idol median 0.028132s → 0.001979s.
- **arith** (−30.64% → −0.85%, p=0.8875 ns): fix2's same-variable
  constant-chain accumulator handles the `x*3+7−2` chain.
  Idol median 0.054334s → 0.042078s.

## REGRESSION: mul13

- **mul13** (+0.45% tie, p=0.3346 → −7.10% loss, p=0.0002): Idol's own
  median rose 0.054247s → 0.061525s (+13.4%) while clang held ~0.055s.
  Confirmed by an independent second run (idol 0.061031 vs clang
  0.055090, −10.78%, p=0.0000). Verdict flipped from tie to significant
  loss. Per the honesty policy this is a compiler bug report: something
  between `85886ee3` and `ae5532b2` slowed the `x*13+1` loop — suspect
  fix2's chain accumulator or the egraph/canon pass interacting with the
  multiply chain. Needs a bisection.

## Persistent losses (unchanged verdict, still bug reports)

- **nest** −44.04%: nested-loop bound handling still far behind.
- **div** −32.57%: `sdiv` loop; no strength reduction on divide-by-3.
- **zerotrip** −110.68%: 10M-iteration outer loop with dead inner loop;
  clang deletes it, Idol does not.
- **upbranch** −24.09% (was −18.89%): margin widened 5.2pp; verdict
  unchanged (significant loss). Watch item, not a verdict flip.

## Compile time, source → executable (median of 5, seconds)

| # | directive |
|---|---|
| 1 | Idol wins all 10 comparisons (v5: 10/10, v6: 10/10). |

| program | v5 idol | v5 clang | v6 idol | v6 clang |
|---|---|---|---|---|
| sum | 0.025 | 0.038 | 0.025 | 0.042 |
| arith | 0.023 | 0.039 | 0.030 | 0.046 |
| fib | 0.024 | 0.038 | 0.031 | 0.047 |
| nest | 0.027 | 0.043 | 0.032 | 0.045 |
| div | 0.024 | 0.039 | 0.033 | 0.047 |
| mul13 | 0.027 | 0.040 | 0.027 | 0.042 |
| bigconst | 0.026 | 0.040 | 0.028 | 0.040 |
| zerotrip | 0.029 | 0.053 | 0.024 | 0.040 |
| upbranch | 0.031 | 0.044 | 0.031 | 0.045 |
| startup | 0.027 | 0.038 | 0.023 | 0.038 |

| # | directive |
|---|---|
| 1 | Absolute compile times rose run-to-run for all three compilers on most programs (machine state), so the cross-run idol delta is environmental; the within-run idol-vs-clang win is the controlled comparison. |

## Object size (`.o` bytes)

| # | directive |
|---|---|
| 1 | Idol wins all 10 comparisons (v5: 10/10, v6: 10/10). |

| program | v5 idol | v6 idol | v6 clang |
|---|---|---|---|
| sum | 279 | 275 | 512 |
| arith | 279 | 275 | 544 |
| fib | 303 | 303 | 512 |
| nest | 283 | 283 | 512 |
| div | 283 | 283 | 560 |
| mul13 | 279 | 279 | 544 |
| bigconst | 279 | 271 | 512 |
| zerotrip | 295 | 295 | 512 |
| upbranch | 355 | 355 | 608 |
| startup | 243 | 247 | 512 |

## Notes

- Host: arm64-Darwin (Apple M4 Mac mini), same machine as v5.
- gcc -O3 also ran (harness default); all margins above are vs clang,
  matching the v5 report. Full three-compiler tables are in
  `bench/RESULTS.md`.
- The 504-case differential verify suite (`bench/verify`) was not re-run
  here; the run.sh correctness gate (exit-code agreement Idol/clang/gcc
  on all 10 programs) passed.
