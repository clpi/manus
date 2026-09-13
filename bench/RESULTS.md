| field | value |
|---|---|
| title | Benchmark results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T19:48:05 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary). |

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
| idol | 0.001710 | 0.001845 | 0.000317 | 0.001504 | 0.002664 | 0.002359 | 0 |
| clang | 0.001873 | 0.001957 | 0.000445 | 0.001482 | 0.003134 | 0.002792 | 0 |
| gcc | 0.001639 | 0.001820 | 0.000418 | 0.001486 | 0.003333 | 0.002295 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -4.32%, p=0.8286 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.041s, gcc 0.043s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 267, clang 512, gcc 512. |

| section |
|---|---|
| nest |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.002399 | 0.002348 | 0.000384 | 0.001568 | 0.003341 | 0.002852 | 0 |
| clang | 0.002322 | 0.002348 | 0.000315 | 0.001728 | 0.002952 | 0.002859 | 0 |
| gcc | 0.002437 | 0.002354 | 0.000373 | 0.001632 | 0.003028 | 0.002858 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -3.31%, p=0.9975 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.027s, clang 0.040s, gcc 0.050s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 512, gcc 512. |

| section |
|---|---|
| div |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.035962 | 0.037324 | 0.003626 | 0.032755 | 0.044864 | 0.043917 | 0 |
| clang | 0.036353 | 0.039525 | 0.010587 | 0.032468 | 0.082865 | 0.046627 | 1 |
| gcc | 0.036018 | 0.037131 | 0.004142 | 0.033025 | 0.048798 | 0.043843 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): win, margin +0.15%, p=0.8755 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.035s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 327, clang 560, gcc 560. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.009688 | 0.009790 | 0.000607 | 0.008908 | 0.010940 | 0.010641 | 0 |
| clang | 0.008083 | 0.008225 | 0.000668 | 0.007454 | 0.010228 | 0.009181 | 0 |
| gcc | 0.008343 | 0.008212 | 0.000539 | 0.007509 | 0.009480 | 0.009136 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -19.86%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.038s, gcc 0.042s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 379, clang 608, gcc 608. |

| section |
|---|---|
| mul13 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.053679 | 0.055289 | 0.002859 | 0.052806 | 0.062798 | 0.059873 | 0 |
| clang | 0.054405 | 0.055351 | 0.002449 | 0.052703 | 0.060942 | 0.060393 | 0 |
| gcc | 0.054362 | 0.054765 | 0.001655 | 0.052738 | 0.059076 | 0.058389 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): win, margin +1.26%, p=0.4780 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.037s, gcc 0.044s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 303, clang 544, gcc 544. |

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
| div | 2 | 2026-09-12T00:11:52 | win | +0.15% | -35.72% | +0.15% |
| fib | 1 | 2026-09-12T00:11:52 | win | +2.31% | +2.31% | +2.31% |
| mul13 | 2 | 2026-09-12T00:11:52 | win | +1.26% | -7.52% | +1.26% |
| nest | 2 | 2026-09-12T00:11:52 | loss | -3.31% | -44.04% | -3.31% |
| startup | 1 | 2026-09-12T00:11:52 | loss | -4.38% | -4.38% | -4.38% |
| sum | 1 | 2026-09-12T00:11:52 | loss | -2.95% | -2.95% | -2.95% |
| upbranch | 2 | 2026-09-12T00:11:52 | loss | -19.86% | -24.09% | -19.86% |
| zerotrip | 2 | 2026-09-12T00:11:52 | loss | -4.32% | -120.32% | -4.32% |
