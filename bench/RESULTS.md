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
|---|
| corrections |

| # | directive |
|---|---|
| 1 | CORRECTIONS APPLIED 2026-09-12 (honest-scoreboard audit, second external audit ~19:08 PDT). |
| 2 | Route labeling: the "idol" binaries in every section below were compiled by the RESTRICTED route (`idol compile lib/compiler/native.id --backend native -o nativebench`, then `nativebench < P.id` + hex-decode + `ld`), not by the production compiler (zig-out/bin/idol) compiling the programs. The production route (src/native.zig) does not consume the .id optimizer passes (opt/licm.id, opt/poly.id, opt/zerotrip.id); restricted-route wins are not production progress until the production route consumes the technique with its own equivalence + cost evidence. |
| 3 | Compile-time rows ("Compile time, source to executable"): same restricted route + `ld` vs `clang -O3` / `gcc -O3`. Comparator identity VERIFIED 2026-09-12: `gcc --version` and `clang --version` both report Apple clang 21.0.0 (clang-2100.1.1.101), Target: arm64-apple-darwin25.5.0 -- no GNU GCC was measured. Load context on the 2026-09-12 compile-time baseline: 1-min load 9.94 -> 9.62 (publish gate < 10; at threshold, indicative). |
| 4 | The faster-compile-time figures stand alongside real output-runtime losses in the same runs (e.g. upbranch -19.86% vs clang, significant, p=0.0000; zerotrip -4.32%; nest -3.31%): compile-time speed does not offset slower output. No faster-compile-time claim may be presented as compensating for slower output, extra allocation, larger code, or wrong answers. |
| 5 | Claim "narrowed spill 2.11x faster" (commit e35a6c36: "mixop 0.0442s -> 0.0209s, 2.11x faster", marked provisional, load ~12) was REVERTED by 59a7b26b ("native.deepexpr: revert narrowed spill, restore full spill"). Not a retained gain; it survives only in the immutable commit message. |
| 6 | Claim "mask hoisting 70->50 instructions" (commit 471a40c9): independently re-measured 2026-09-12 -- nativebench built before/after the commit (--no-cache), popc.id compiled, otool disassembly: loop 88 -> 73 instructions (4 big masks hoisted to prologue; exit code identical, 196); runtime median -1.9% (noise) at 1-min load ~7.4. The claimed 70->50 figures are NOT reproduced. Restricted-route technique (lib/compiler/opt/licm.id); the production route has no nestedband big-mask equivalent. |
| 7 | Going-forward rule: compile-time claims must use the PRODUCTION compiler route on real programs with verified-independent comparators; the record must carry both `--version` identities and the load window. Loaded-machine figures are indicative only, never conclusive. |


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
