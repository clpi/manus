| field | value |
|---|---|
| title | Benchmark results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T20:45:37 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary). |

| # | directive |
|---|---|
| 1 | Honesty policy: every program x every compiler is listed. |
| 2 | Losses are reported, not hidden. |
| 3 | A loss is a bug report against the compiler. |

| section |
|---|---|
| zerotrip |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001597 | 0.001617 | 0.000111 | 0.001459 | 0.001854 | 0.001840 | 0 |
| clang | 0.001573 | 0.001606 | 0.000115 | 0.001478 | 0.001970 | 0.001821 | 1 |
| gcc | 0.001617 | 0.001660 | 0.000204 | 0.001441 | 0.002426 | 0.001989 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -1.53%, p=0.7497 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.035s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 267, clang 512, gcc 512. |

| section |
|---|---|
| nest |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001980 | 0.001933 | 0.000146 | 0.001638 | 0.002186 | 0.002094 | 0 |
| clang | 0.001917 | 0.001897 | 0.000128 | 0.001655 | 0.002072 | 0.002052 | 0 |
| gcc | 0.001954 | 0.001964 | 0.000149 | 0.001730 | 0.002351 | 0.002165 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -3.33%, p=0.3943 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.040s, gcc 0.044s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 512, gcc 512. |

| section |
|---|---|
| div |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.032974 | 0.033105 | 0.000494 | 0.032458 | 0.034120 | 0.033986 | 0 |
| clang | 0.033124 | 0.033286 | 0.000964 | 0.032450 | 0.037161 | 0.034323 | 1 |
| gcc | 0.032985 | 0.033092 | 0.000481 | 0.032229 | 0.033862 | 0.033788 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): win, margin +0.03%, p=0.9317 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.022s, clang 0.035s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 327, clang 560, gcc 560. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.008948 | 0.009081 | 0.000428 | 0.008471 | 0.010473 | 0.009615 | 1 |
| clang | 0.008281 | 0.008438 | 0.000505 | 0.007915 | 0.009893 | 0.009592 | 2 |
| gcc | 0.008317 | 0.008414 | 0.000399 | 0.007848 | 0.009518 | 0.009225 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -8.05%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.038s, gcc 0.042s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 347, clang 608, gcc 608. |

| section |
|---|---|
| mul13 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.053306 | 0.053476 | 0.000611 | 0.052812 | 0.055396 | 0.054457 | 1 |
| clang | 0.053491 | 0.053756 | 0.000864 | 0.052839 | 0.055736 | 0.055697 | 0 |
| gcc | 0.053301 | 0.053534 | 0.000520 | 0.052968 | 0.054921 | 0.054440 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -0.01%, p=0.7461 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.027s, clang 0.039s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| history |

| # | directive |
|---|---|
| 1 | Per-case verdict history across runs. Any commit that regresses a case is visible here. |
| 2 | margin% = (rival_median - idol_median) / rival_median; negative = idol slower. |
| 3 | Source: bench/results/history.jsonl, one entry appended per run. |

| case | runs | first seen | last verdict | last margin% | worst margin% | best margin% |
|---|---|---|---|---|---|---|
| arith | 1 | 2026-09-12T00:11:52 | loss | -0.85% | -0.85% | -0.85% |
| bigconst | 1 | 2026-09-12T00:11:52 | loss | -0.35% | -0.35% | -0.35% |
| div | 3 | 2026-09-12T00:11:52 | win | +0.03% | -35.72% | +0.15% |
| fib | 1 | 2026-09-12T00:11:52 | win | +2.31% | +2.31% | +2.31% |
| mul13 | 3 | 2026-09-12T00:11:52 | loss | -0.01% | -7.52% | +1.26% |
| nest | 3 | 2026-09-12T00:11:52 | loss | -3.33% | -44.04% | -3.31% |
| startup | 1 | 2026-09-12T00:11:52 | loss | -4.38% | -4.38% | -4.38% |
| sum | 1 | 2026-09-12T00:11:52 | loss | -2.95% | -2.95% | -2.95% |
| upbranch | 3 | 2026-09-12T00:11:52 | loss | -8.05% | -24.09% | -8.05% |
| zerotrip | 3 | 2026-09-12T00:11:52 | loss | -1.53% | -120.32% | -1.53% |
