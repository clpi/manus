| field | value |
|---|---|
| title | Compile-time baseline — 2026-09-12 |
| commit | ba31acf5 |
| method | bench/run.sh section 6b: source to executable, median of 5, interleaved per round |
| idol_build | zig-out/bin/idol compile lib/compiler/native.id --backend native --no-cache -o nativebench; nativebench < P.id \| xxd -r -p \| ld -e _idolmain |
| clang_build | clang -O3 P.c -o P |
| gcc_build | gcc -O3 P.c -o P |
| load_window | 1-min load 9.94 at start, 9.62 at end (publish gate < 10) |
| prior_baseline | bench/results/RESULTS-v6.md at ae5532b2 |
| raw | bench/results/compiletime-2026-09-12.json |

| program | idol | clang | gcc | v6_idol | v6_clang | idol_win_pct |
|---|---|---|---|---|---|---|
| sum | 0.0325 | 0.0464 | 0.0584 | 0.025 | 0.042 | 30.0 |
| arith | 0.0273 | 0.0413 | 0.0490 | 0.030 | 0.046 | 33.9 |
| fib | 0.0277 | 0.0424 | 0.0472 | 0.031 | 0.047 | 34.7 |
| nest | 0.0274 | 0.0422 | 0.0495 | 0.032 | 0.045 | 35.1 |
| div | 0.0278 | 0.0423 | 0.0481 | 0.033 | 0.047 | 34.3 |
| mul13 | 0.0271 | 0.0437 | 0.0492 | 0.027 | 0.042 | 38.0 |
| bigconst | 0.0251 | 0.0392 | 0.0446 | 0.028 | 0.040 | 36.0 |
| zerotrip | 0.0257 | 0.0392 | 0.0448 | 0.024 | 0.040 | 34.4 |
| upbranch | 0.0258 | 0.0407 | 0.0458 | 0.031 | 0.045 | 36.6 |
| startup | 0.0249 | 0.0386 | 0.0431 | 0.023 | 0.038 | 35.5 |

| # | directive |
|---|---|
| 1 | idol_win_pct = (clang - idol) / clang * 100; positive favors idol. |
| 2 | Idol wins 10/10 vs clang and 10/10 vs gcc; v6 was 10/10 vs clang. |
| 3 | Absolute deltas vs v6 are within run-to-run machine variance per the v6 honesty note; the within-run idol-vs-clang win is the controlled comparison. |
| 4 | Outlier: sum idol max 0.3313 on the first round (cold page cache); median unaffected. |
