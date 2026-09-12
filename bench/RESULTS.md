# Benchmark results

Generated 2026-09-11T22:18:37 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary).

Honesty policy: every program x every compiler is listed. Losses are
reported, not hidden. A loss is a bug report against the compiler.

## sum

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.027992 | 0.028050 | 0.000226 | 0.027671 | 0.028540 | 0.028430 | 0 |
| clang | 0.002259 | 0.002264 | 0.000114 | 0.002053 | 0.002490 | 0.002418 | 0 |

Idol vs best rival (clang): loss, margin -1138.88%, p=0.0000 (significant).

Compile time, source to executable (median of 5): idol 0.025s, clang 0.038s, gcc 0.045s.

Object size (bytes): idol 279, clang 512, gcc 512.

## arith

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.054334 | 0.057088 | 0.011373 | 0.053107 | 0.107461 | 0.060676 | 1 |
| clang | 0.041590 | 0.044011 | 0.011296 | 0.040456 | 0.094424 | 0.043042 | 1 |

Idol vs best rival (clang): loss, margin -30.64%, p=0.0003 (significant).

Compile time, source to executable (median of 5): idol 0.023s, clang 0.039s, gcc 0.043s.

Object size (bytes): idol 279, clang 544, gcc 544.

## fib

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001918 | 0.001895 | 0.000177 | 0.001595 | 0.002175 | 0.002163 | 0 |
| clang | 0.001900 | 0.001988 | 0.000342 | 0.001671 | 0.003257 | 0.002514 | 1 |

Idol vs best rival (clang): loss, margin -0.93%, p=0.2802 (not significant).

Compile time, source to executable (median of 5): idol 0.024s, clang 0.038s, gcc 0.045s.

Object size (bytes): idol 303, clang 512, gcc 512.

## nest

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.003583 | 0.003786 | 0.000597 | 0.002998 | 0.005099 | 0.004818 | 0 |
| clang | 0.002476 | 0.002843 | 0.000904 | 0.002006 | 0.005777 | 0.004257 | 1 |

Idol vs best rival (clang): loss, margin -44.71%, p=0.0001 (significant).

Compile time, source to executable (median of 5): idol 0.027s, clang 0.043s, gcc 0.054s.

Object size (bytes): idol 283, clang 512, gcc 512.

## div

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.043223 | 0.043369 | 0.000611 | 0.042852 | 0.045091 | 0.045020 | 2 |
| clang | 0.032951 | 0.032954 | 0.000251 | 0.032628 | 0.033726 | 0.033344 | 0 |

Idol vs best rival (clang): loss, margin -31.17%, p=0.0000 (significant).

Compile time, source to executable (median of 5): idol 0.024s, clang 0.039s, gcc 0.046s.

Object size (bytes): idol 283, clang 560, gcc 560.

## mul13

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.054247 | 0.054692 | 0.001247 | 0.053128 | 0.058170 | 0.056156 | 0 |
| clang | 0.054490 | 0.054375 | 0.000780 | 0.053256 | 0.055857 | 0.055853 | 0 |

Idol vs best rival (clang): win, margin +0.45%, p=0.3346 (not significant).

Compile time, source to executable (median of 5): idol 0.027s, clang 0.040s, gcc 0.047s.

Object size (bytes): idol 279, clang 544, gcc 544.

## bigconst

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.028132 | 0.028216 | 0.000248 | 0.027872 | 0.028863 | 0.028494 | 0 |
| clang | 0.002465 | 0.002452 | 0.000165 | 0.002149 | 0.002724 | 0.002714 | 0 |

Idol vs best rival (clang): loss, margin -1041.19%, p=0.0000 (significant).

Compile time, source to executable (median of 5): idol 0.026s, clang 0.040s, gcc 0.046s.

Object size (bytes): idol 279, clang 512, gcc 512.

## zerotrip

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.004844 | 0.004912 | 0.000231 | 0.004622 | 0.005475 | 0.005365 | 0 |
| clang | 0.002291 | 0.002293 | 0.000232 | 0.002028 | 0.003005 | 0.002619 | 0 |

Idol vs best rival (clang): loss, margin -111.42%, p=0.0000 (significant).

Compile time, source to executable (median of 5): idol 0.029s, clang 0.053s, gcc 0.049s.

Object size (bytes): idol 295, clang 512, gcc 512.

## upbranch

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.010407 | 0.010517 | 0.000570 | 0.009792 | 0.012102 | 0.011803 | 0 |
| clang | 0.008753 | 0.008887 | 0.000466 | 0.008425 | 0.010674 | 0.009531 | 1 |

Idol vs best rival (clang): loss, margin -18.89%, p=0.0000 (significant).

Compile time, source to executable (median of 5): idol 0.031s, clang 0.044s, gcc 0.046s.

Object size (bytes): idol 355, clang 608, gcc 608.

## startup

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.002213 | 0.002276 | 0.000313 | 0.001987 | 0.003460 | 0.002562 | 1 |
| clang | 0.002285 | 0.002308 | 0.000186 | 0.002003 | 0.002782 | 0.002611 | 0 |

Idol vs best rival (clang): win, margin +3.16%, p=0.6995 (not significant).

Compile time, source to executable (median of 5): idol 0.027s, clang 0.038s, gcc 0.044s.

Object size (bytes): idol 243, clang 512, gcc 512.

