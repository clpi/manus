# Benchmark results

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T00:11:52 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary). |

| # | directive |
|---|---|
| 1 | Honesty policy: every program x every compiler is listed. |
| 2 | Losses are reported, not hidden. |
| 3 | A loss is a bug report against the compiler. |

## sum

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001866 | 0.001984 | 0.000329 | 0.001591 | 0.002836 | 0.002666 | 0 |
| clang | 0.001865 | 0.002012 | 0.000421 | 0.001591 | 0.003293 | 0.002856 | 1 |
| gcc | 0.001812 | 0.001925 | 0.000352 | 0.001574 | 0.003116 | 0.002394 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -2.95%, p=0.5835 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.042s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 512, gcc 512. |

## arith

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.042078 | 0.042730 | 0.001752 | 0.040644 | 0.046997 | 0.046456 | 0 |
| clang | 0.041724 | 0.042654 | 0.001647 | 0.040747 | 0.046143 | 0.045977 | 0 |
| gcc | 0.042121 | 0.042606 | 0.002002 | 0.040735 | 0.048150 | 0.047533 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -0.85%, p=0.8875 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.030s, clang 0.046s, gcc 0.053s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 544, gcc 544. |

## fib

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.002469 | 0.002477 | 0.000485 | 0.001791 | 0.003937 | 0.003055 | 0 |
| clang | 0.002527 | 0.002592 | 0.000495 | 0.001798 | 0.004143 | 0.003183 | 0 |
| gcc | 0.002585 | 0.002606 | 0.000669 | 0.001829 | 0.004591 | 0.003458 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +2.31%, p=0.4562 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.031s, clang 0.047s, gcc 0.048s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 303, clang 512, gcc 512. |

## nest

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.003887 | 0.004083 | 0.000693 | 0.002895 | 0.005679 | 0.005644 | 0 |
| clang | 0.002698 | 0.002665 | 0.000344 | 0.002065 | 0.003214 | 0.003177 | 0 |
| gcc | 0.002757 | 0.002903 | 0.000671 | 0.001868 | 0.004655 | 0.004072 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -44.04%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.032s, clang 0.045s, gcc 0.055s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 283, clang 512, gcc 512. |

## div

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.047600 | 0.048961 | 0.006711 | 0.043187 | 0.074589 | 0.054711 | 1 |
| clang | 0.035909 | 0.036420 | 0.002933 | 0.032954 | 0.044472 | 0.041149 | 0 |
| gcc | 0.035072 | 0.036863 | 0.003806 | 0.033049 | 0.048602 | 0.042352 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -35.72%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.033s, clang 0.047s, gcc 0.054s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 283, clang 560, gcc 560. |

## mul13

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.061525 | 0.061967 | 0.003330 | 0.055297 | 0.067747 | 0.066741 | 0 |
| clang | 0.057448 | 0.057872 | 0.001891 | 0.054963 | 0.062854 | 0.060892 | 0 |
| gcc | 0.057224 | 0.058457 | 0.002546 | 0.055397 | 0.064452 | 0.062561 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -7.52%, p=0.0002 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.027s, clang 0.042s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 279, clang 544, gcc 544. |

## bigconst

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001979 | 0.002064 | 0.000401 | 0.001520 | 0.002932 | 0.002888 | 0 |
| clang | 0.001973 | 0.002233 | 0.000674 | 0.001513 | 0.003894 | 0.003643 | 2 |
| gcc | 0.002096 | 0.002375 | 0.000817 | 0.001588 | 0.004825 | 0.003911 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -0.35%, p=0.3353 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.028s, clang 0.040s, gcc 0.053s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 271, clang 512, gcc 512. |

## zerotrip

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.004734 | 0.005079 | 0.001057 | 0.004286 | 0.009114 | 0.006584 | 1 |
| clang | 0.002247 | 0.002358 | 0.000453 | 0.001756 | 0.003382 | 0.003109 | 0 |
| gcc | 0.002149 | 0.002212 | 0.000476 | 0.001693 | 0.003452 | 0.003060 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -120.32%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.040s, gcc 0.049s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 512, gcc 512. |

## upbranch

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.011236 | 0.011473 | 0.001573 | 0.009570 | 0.015871 | 0.013952 | 0 |
| clang | 0.009055 | 0.009612 | 0.001073 | 0.008476 | 0.011905 | 0.011584 | 0 |
| gcc | 0.009360 | 0.009412 | 0.000730 | 0.008330 | 0.011295 | 0.010989 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -24.09%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.031s, clang 0.045s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 355, clang 608, gcc 608. |

## startup

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001815 | 0.001912 | 0.000383 | 0.001473 | 0.003151 | 0.002397 | 1 |
| clang | 0.001739 | 0.001829 | 0.000233 | 0.001544 | 0.002361 | 0.002283 | 0 |
| gcc | 0.001809 | 0.001971 | 0.000361 | 0.001569 | 0.003103 | 0.002656 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -4.38%, p=0.4095 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.038s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 247, clang 512, gcc 512. |
