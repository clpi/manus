| field | value |
|---|---|
| title | Benchmark results |
| oracle_versions | clang: Apple clang version 21.0.0 (clang-2100.1.1.101) ; gcc: Apple clang version 21.0.0 (clang-2100.1.1.101) |
| correctness_oracle | clang (exit code + byte-identical stdout) |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T23:50:32 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary). |

| section |
|---|---|
| corrections |

| # | directive |
|---|---|
| 1 | [route] Route labeling: the "idol" binaries in every section below were compiled by the RESTRICTED route (`idol compile lib/compiler/native.id --backend native --no-cache -o nativebench`, then `nativebench < P.id` piped through `xxd -r -p`, then `ld -arch arm64 -e _idolmain`), not by the production compiler (zig-out/bin/idol) compiling the programs. The production route (src/native.zig) does not consume the .id optimizer passes (opt/licm.id, opt/poly.id, opt/zerotrip.id); restricted-route wins are not production progress until the production route consumes the technique with its own equivalence + cost evidence. |
| 2 | [oracle-identity] Comparator identity is established at run time via `clang --version` and `gcc --version`, and the discovered version strings are recorded per run in this report; identity is never assumed from command names. On the Mac mini both report Apple clang 21.0.0 (clang-2100.1.1.101), Target: arm64-apple-darwin25.5.0 -- no GNU GCC is measured here, so the "gcc" column is an Apple-clang alias of the "clang" column, not an independent oracle. |
| 3 | [compile-time-scope] Compile-time rows ("Compile time, source to executable") use the same restricted route + `ld` vs the run-time-discovered comparators. A duration counts as a successful compilation only after every required stage succeeded and the artifact was validated (exists, nonzero size). Failed attempts are recorded as FAILED work and are never mixed into success medians. Faster compile time does not offset slower output, extra allocation, larger code, or wrong answers; no faster-compile-time claim may be presented as compensating for those. |
| 4 | [reverted-narrowed-spill] RETRACTED: claim "narrowed spill 2.11x faster" (commit e35a6c36: "mixop 0.0442s -> 0.0209s, 2.11x faster", marked provisional, load ~12) was REVERTED by 59a7b26b ("native.deepexpr: revert narrowed spill, restore full spill"). Not a retained gain; it survives only in the immutable commit message. |
| 5 | [mask-hoisting] NOT REPRODUCED: claim "mask hoisting 70->50 instructions" (commit 471a40c9). Independent re-measurement 2026-09-12 (nativebench built before/after the commit, --no-cache; popc.id compiled; otool disassembly): loop 88 -> 73 instructions (4 big masks hoisted to prologue; exit code identical, 196); runtime median -1.9% (noise) at 1-min load ~7.4. Restricted-route technique (lib/compiler/opt/licm.id) only; the production route has no nestedband big-mask equivalent. |
| 6 | [unproved-way-fastest] UNPROVED: the standing "way fastest" target. No clean idle-machine benchmark window has yet been achieved; every speed figure to date is loaded-machine (indicative only, never conclusive). |
| 7 | [unreplicated-upbranch-audit] Upbranch: two observations exist with an UNRESOLVED relationship. (1) The retained report shows an upbranch RUNTIME slowdown vs the oracle. This observation is INCOMPLETELY ATTRIBUTABLE: the old measurement path did not record compiler-executable identity, generated-binary hash, compiler route, comparator versions, or load window, so it cannot be retroactively assigned to any revision. (2) A separate post-mul-chain-fix (commit 99ab0a0f) measurement reported a statistical tie vs clang. CORRECTION 2026-09-13: the reproduced compile-timer defect concerned the COMPILATION-TIME section of bench/run.sh, not the production of the runtime percentage. The timer defect is established but has NOT been shown to explain the runtime difference; it does not by itself invalidate observation (1). Neither observation establishes the current result; the case awaits re-measurement with the fixed methodology. |
| 8 | [methodology-rule] Going-forward rule: compile-time claims must use the production compiler route on real programs with run-time-verified comparators; the record must carry both --version identities and the load window. Loaded-machine figures are indicative only, never conclusive. |
| 9 | [durability] These corrections are emitted by the report generator from bench/corrections.json on every run. A report regeneration cannot delete them; amend them only by committing a change to the producer data. |
| 10 | [parity-criterion] Parity acceptance criterion, predeclared: 'parity' between idol and an oracle on a program requires abs(median runtime delta) <= 2 percent AND Welch p >= 0.05 on uncertainty-quantified samples (per-round raw samples, stated N, load window, run-time oracle --version identities). Failure to detect a difference is not parity; a verdict of parity, win, or loss without the tolerance band and the uncertainty behind it is inadmissible. Loaded-machine figures remain indicative only, never conclusive. |

| # | directive |
|---|---|
| 1 | Honesty policy: every program x every compiler is listed. |
| 2 | Losses are reported, not hidden. |
| 3 | A loss is a bug report against the compiler. |
| 4 | No win/loss without significance: a verdict of win/loss requires Welch p < 0.05; otherwise the verdict is tie. |
| 5 | Raw per-round samples are retained in bench results.json per row; every verdict is re-derivable. |

| section |
|---|---|
| sum |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001603 | 0.001643 | 0.000121 | 0.001483 | 0.001936 | 0.001870 | 0 |
| clang | 0.001641 | 0.001620 | 0.000086 | 0.001480 | 0.001771 | 0.001751 | 0 |
| gcc | 0.001614 | 0.001620 | 0.000082 | 0.001489 | 0.001775 | 0.001765 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin +0.65%, p=0.4863 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 512, gcc 512. |

| section |
|---|---|
| arith |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.040234 | 0.040632 | 0.001095 | 0.039611 | 0.045037 | 0.041280 | 1 |
| clang | 0.040254 | 0.040416 | 0.000490 | 0.039727 | 0.041431 | 0.041356 | 0 |
| gcc | 0.040253 | 0.040420 | 0.000509 | 0.039611 | 0.041621 | 0.041311 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin +0.05%, p=0.4328 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| fib |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001547 | 0.001633 | 0.000279 | 0.001441 | 0.002799 | 0.001784 | 1 |
| clang | 0.001578 | 0.001594 | 0.000109 | 0.001423 | 0.001873 | 0.001789 | 0 |
| gcc | 0.001522 | 0.001556 | 0.000120 | 0.001390 | 0.001895 | 0.001745 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -1.62%, p=0.2574 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 512, gcc 512. |

| section |
|---|---|
| nest |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001548 | 0.001569 | 0.000077 | 0.001434 | 0.001718 | 0.001698 | 0 |
| clang | 0.001566 | 0.001587 | 0.000130 | 0.001456 | 0.002029 | 0.001738 | 1 |
| gcc | 0.001582 | 0.001573 | 0.000072 | 0.001449 | 0.001741 | 0.001694 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): tie, margin +1.09%, p=0.5893 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.024s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.043s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 512, gcc 512. |

| section |
|---|---|
| div |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.032597 | 0.032835 | 0.000736 | 0.032188 | 0.035747 | 0.033461 | 1 |
| clang | 0.032577 | 0.032838 | 0.000934 | 0.032194 | 0.036766 | 0.033418 | 1 |
| gcc | 0.032526 | 0.032788 | 0.000657 | 0.032223 | 0.035325 | 0.033456 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -0.22%, p=0.8331 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 327, clang 560, gcc 560. |

| section |
|---|---|
| mul13 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.052799 | 0.052813 | 0.000761 | 0.051346 | 0.054182 | 0.054163 | 0 |
| clang | 0.052649 | 0.052947 | 0.000711 | 0.051583 | 0.054047 | 0.053970 | 0 |
| gcc | 0.052615 | 0.052905 | 0.000799 | 0.051944 | 0.054352 | 0.054240 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -0.35%, p=0.7072 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| bigconst |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001448 | 0.001438 | 0.000047 | 0.001357 | 0.001517 | 0.001511 | 0 |
| clang | 0.001444 | 0.001445 | 0.000049 | 0.001370 | 0.001572 | 0.001499 | 0 |
| gcc | 0.001454 | 0.001462 | 0.000062 | 0.001381 | 0.001629 | 0.001532 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): tie, margin -0.23%, p=0.6628 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.021s (5/5 ok); clang 0.033s (5/5 ok); gcc 0.037s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 283, clang 512, gcc 512. |

| section |
|---|---|
| zerotrip |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001907 | 0.001916 | 0.000201 | 0.001474 | 0.002581 | 0.002112 | 1 |
| clang | 0.001741 | 0.001790 | 0.000174 | 0.001576 | 0.002174 | 0.002159 | 0 |
| gcc | 0.001742 | 0.001752 | 0.000110 | 0.001552 | 0.001948 | 0.001938 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -9.54%, p=0.0329 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 267, clang 512, gcc 512. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.007756 | 0.007755 | 0.000100 | 0.007580 | 0.008087 | 0.007832 | 1 |
| clang | 0.007553 | 0.007606 | 0.000187 | 0.007413 | 0.008301 | 0.007901 | 1 |
| gcc | 0.007562 | 0.007564 | 0.000058 | 0.007471 | 0.007675 | 0.007668 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -2.69%, p=0.0017 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 351, clang 608, gcc 608. |

| section |
|---|---|
| startup |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001600 | 0.001602 | 0.000065 | 0.001416 | 0.001705 | 0.001687 | 0 |
| clang | 0.001665 | 0.001681 | 0.000102 | 0.001543 | 0.001968 | 0.001839 | 0 |
| gcc | 0.001585 | 0.001608 | 0.000078 | 0.001465 | 0.001791 | 0.001732 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -0.95%, p=0.8146 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.021s (5/5 ok); clang 0.033s (5/5 ok); gcc 0.037s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 255, clang 512, gcc 512. |

| section |
|---|---|
| brm1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.022178 | 0.022276 | 0.000398 | 0.022078 | 0.024023 | 0.022394 | 1 |
| clang | 0.002313 | 0.002436 | 0.000458 | 0.002192 | 0.004408 | 0.002680 | 1 |
| gcc | 0.002216 | 0.002261 | 0.000210 | 0.002083 | 0.003082 | 0.002557 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -900.58%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.026s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.042s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 391, clang 568, gcc 568. |

| section |
|---|---|
| brm2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012493 | 0.012809 | 0.000971 | 0.012337 | 0.017014 | 0.013173 | 1 |
| clang | 0.004602 | 0.004610 | 0.000114 | 0.004456 | 0.004908 | 0.004852 | 0 |
| gcc | 0.004562 | 0.004579 | 0.000105 | 0.004423 | 0.004800 | 0.004758 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -173.86%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.024s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 435, clang 576, gcc 576. |

| section |
|---|---|
| brm3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012051 | 0.012118 | 0.000403 | 0.011617 | 0.013326 | 0.013185 | 2 |
| clang | 0.002220 | 0.002238 | 0.000259 | 0.001876 | 0.003274 | 0.002377 | 1 |
| gcc | 0.001954 | 0.001993 | 0.000237 | 0.001739 | 0.002932 | 0.002205 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -516.78%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.024s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 455, clang 592, gcc 592. |

| section |
|---|---|
| divv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.042443 | 0.042553 | 0.000460 | 0.041919 | 0.043579 | 0.043264 | 0 |
| clang | 0.042441 | 0.042485 | 0.000405 | 0.041772 | 0.043364 | 0.043202 | 0 |
| gcc | 0.042377 | 0.042443 | 0.000365 | 0.041707 | 0.043213 | 0.042985 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -0.16%, p=0.4019 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 560, gcc 560. |

| section |
|---|---|
| divm |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006709 | 0.006706 | 0.000123 | 0.006492 | 0.006892 | 0.006881 | 0 |
| clang | 0.006679 | 0.006695 | 0.000106 | 0.006557 | 0.006940 | 0.006900 | 0 |
| gcc | 0.006699 | 0.006704 | 0.000080 | 0.006546 | 0.006830 | 0.006828 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): tie, margin -0.44%, p=0.7547 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 335, clang 664, gcc 664. |

| section |
|---|---|
| divd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.015457 | 0.015536 | 0.000459 | 0.015048 | 0.017364 | 0.015763 | 1 |
| clang | 0.006838 | 0.006794 | 0.000230 | 0.006305 | 0.007161 | 0.007103 | 0 |
| gcc | 0.006705 | 0.006743 | 0.000217 | 0.006298 | 0.007140 | 0.007138 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -130.54%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.027s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.043s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 415, clang 1088, gcc 1088. |

| section |
|---|---|
| dgcd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.007092 | 0.007104 | 0.000100 | 0.006905 | 0.007315 | 0.007277 | 0 |
| clang | 0.004077 | 0.004068 | 0.000094 | 0.003897 | 0.004250 | 0.004247 | 0 |
| gcc | 0.004054 | 0.004098 | 0.000305 | 0.003880 | 0.005418 | 0.004168 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -74.95%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 487, clang 632, gcc 632. |

| section |
|---|---|
| divpow2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.044030 | 0.044670 | 0.002878 | 0.043238 | 0.057405 | 0.045221 | 1 |
| clang | 0.016951 | 0.016925 | 0.000219 | 0.016444 | 0.017424 | 0.017225 | 0 |
| gcc | 0.016887 | 0.017404 | 0.002553 | 0.016450 | 0.028783 | 0.017255 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -160.73%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 315, clang 544, gcc 544. |

| section |
|---|---|
| ceildiv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012148 | 0.012222 | 0.000379 | 0.011927 | 0.013848 | 0.012349 | 1 |
| clang | 0.011955 | 0.011971 | 0.000115 | 0.011795 | 0.012304 | 0.012150 | 0 |
| gcc | 0.012006 | 0.011976 | 0.000107 | 0.011744 | 0.012116 | 0.012090 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -1.62%, p=0.0047 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 351, clang 744, gcc 744. |

| section |
|---|---|
| mulc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.052774 | 0.052829 | 0.000278 | 0.052340 | 0.053338 | 0.053299 | 0 |
| clang | 0.052873 | 0.052892 | 0.000488 | 0.052060 | 0.054156 | 0.053806 | 0 |
| gcc | 0.052755 | 0.052792 | 0.000312 | 0.052265 | 0.053363 | 0.053281 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -0.04%, p=0.6936 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.024s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 552, gcc 552. |

| section |
|---|---|
| mulh |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006811 | 0.006982 | 0.000724 | 0.006529 | 0.010000 | 0.007830 | 2 |
| clang | 0.001926 | 0.001993 | 0.000379 | 0.001731 | 0.003624 | 0.002108 | 1 |
| gcc | 0.001786 | 0.001825 | 0.000207 | 0.001598 | 0.002640 | 0.001978 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -281.31%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 512, gcc 512. |

| section |
|---|---|
| madd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.025222 | 0.025291 | 0.000336 | 0.024849 | 0.026464 | 0.025698 | 0 |
| clang | 0.025556 | 0.025662 | 0.000559 | 0.025200 | 0.027971 | 0.025936 | 1 |
| gcc | 0.025583 | 0.025594 | 0.000345 | 0.025173 | 0.026707 | 0.026135 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +1.31%, p=0.0111 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.025s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 560, gcc 560. |

| section |
|---|---|
| sred1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.052560 | 0.052733 | 0.000358 | 0.052407 | 0.053718 | 0.053260 | 0 |
| clang | 0.039840 | 0.039921 | 0.000237 | 0.039623 | 0.040442 | 0.040326 | 0 |
| gcc | 0.039831 | 0.039960 | 0.000308 | 0.039678 | 0.040798 | 0.040692 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -31.96%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| powmod |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.008788 | 0.009025 | 0.000996 | 0.007947 | 0.010361 | 0.010356 | 0 |
| clang | 0.007255 | 0.007246 | 0.000086 | 0.007091 | 0.007389 | 0.007387 | 0 |
| gcc | 0.007207 | 0.007228 | 0.000088 | 0.007105 | 0.007398 | 0.007395 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -21.94%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 912, gcc 912. |

| section |
|---|---|
| popc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.013556 | 0.013596 | 0.000194 | 0.013366 | 0.014101 | 0.013975 | 3 |
| clang | 0.004642 | 0.004705 | 0.000235 | 0.004472 | 0.005514 | 0.005024 | 0 |
| gcc | 0.004593 | 0.004619 | 0.000177 | 0.004378 | 0.005086 | 0.004947 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -195.13%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.024s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 611, clang 1136, gcc 1136. |

| section |
|---|---|
| bitr |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.026844 | 0.026849 | 0.000418 | 0.026191 | 0.028009 | 0.027502 | 1 |
| clang | 0.003025 | 0.003060 | 0.000354 | 0.002657 | 0.004515 | 0.003217 | 1 |
| gcc | 0.002739 | 0.002804 | 0.000327 | 0.002441 | 0.004153 | 0.002945 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -880.10%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.026s (5/5 ok); clang 0.039s (5/5 ok); gcc 0.043s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 399, clang 1296, gcc 1296. |

| section |
|---|---|
| xsft |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.062964 | 0.063084 | 0.000643 | 0.062157 | 0.064540 | 0.064159 | 0 |
| clang | 0.033709 | 0.033717 | 0.000313 | 0.033151 | 0.034397 | 0.034204 | 0 |
| gcc | 0.033693 | 0.033744 | 0.000300 | 0.033227 | 0.034397 | 0.034218 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -86.88%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 431, clang 608, gcc 608. |

| section |
|---|---|
| absd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.013900 | 0.013926 | 0.000116 | 0.013690 | 0.014208 | 0.014084 | 0 |
| clang | 0.012430 | 0.012435 | 0.000093 | 0.012275 | 0.012611 | 0.012592 | 0 |
| gcc | 0.012415 | 0.012401 | 0.000081 | 0.012245 | 0.012564 | 0.012501 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -11.95%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 443, clang 600, gcc 600. |

| section |
|---|---|
| cltz |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.073785 | 0.075472 | 0.007140 | 0.072287 | 0.107172 | 0.076640 | 1 |
| clang | 0.029146 | 0.029284 | 0.000757 | 0.028574 | 0.032210 | 0.030160 | 1 |
| gcc | 0.028974 | 0.029088 | 0.000371 | 0.028374 | 0.029803 | 0.029793 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -154.66%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.039s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 543, clang 608, gcc 608. |

| section |
|---|---|
| nest3d |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001567 | 0.001597 | 0.000115 | 0.001456 | 0.001855 | 0.001804 | 0 |
| clang | 0.001535 | 0.001581 | 0.000155 | 0.001405 | 0.002124 | 0.001782 | 1 |
| gcc | 0.001622 | 0.001616 | 0.000089 | 0.001496 | 0.001825 | 0.001797 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): tie, margin -2.13%, p=0.7120 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 335, clang 960, gcc 960. |

| section |
|---|---|
| unroll |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.013199 | 0.013794 | 0.001064 | 0.012916 | 0.016845 | 0.015920 | 0 |
| clang | 0.001711 | 0.001729 | 0.000127 | 0.001524 | 0.001977 | 0.001905 | 0 |
| gcc | 0.001642 | 0.001707 | 0.000295 | 0.001465 | 0.002960 | 0.001859 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -703.80%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 343, clang 512, gcc 512. |

| section |
|---|---|
| mixop |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.021942 | 0.021779 | 0.000518 | 0.020276 | 0.022479 | 0.022378 | 0 |
| clang | 0.004816 | 0.004796 | 0.000125 | 0.004593 | 0.005019 | 0.004997 | 0 |
| gcc | 0.004742 | 0.004722 | 0.000113 | 0.004418 | 0.004877 | 0.004845 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -362.71%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.026s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.044s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 423, clang 688, gcc 688. |

| section |
|---|---|
| loopinv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006991 | 0.007008 | 0.000103 | 0.006863 | 0.007278 | 0.007209 | 0 |
| clang | 0.001673 | 0.001673 | 0.000112 | 0.001508 | 0.001929 | 0.001855 | 0 |
| gcc | 0.001585 | 0.001599 | 0.000080 | 0.001484 | 0.001809 | 0.001805 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -341.00%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 315, clang 512, gcc 512. |

| section |
|---|---|
| satadd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012406 | 0.012399 | 0.000186 | 0.012055 | 0.012702 | 0.012652 | 0 |
| clang | 0.004532 | 0.004511 | 0.000136 | 0.004189 | 0.004719 | 0.004708 | 0 |
| gcc | 0.004423 | 0.004438 | 0.000142 | 0.004116 | 0.004776 | 0.004624 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -180.49%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 423, clang 760, gcc 760. |

| section |
|---|---|
| regp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001446 | 0.001463 | 0.000078 | 0.001368 | 0.001689 | 0.001632 | 0 |
| clang | 0.001428 | 0.001437 | 0.000066 | 0.001315 | 0.001571 | 0.001533 | 0 |
| gcc | 0.001440 | 0.001446 | 0.000057 | 0.001368 | 0.001568 | 0.001562 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): tie, margin -1.24%, p=0.2549 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.023s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 512, gcc 512. |

| section |
|---|---|
| ilp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.018187 | 0.018250 | 0.000271 | 0.017844 | 0.019250 | 0.018477 | 1 |
| clang | 0.021753 | 0.021889 | 0.000509 | 0.021300 | 0.023895 | 0.022562 | 2 |
| gcc | 0.021818 | 0.021805 | 0.000211 | 0.021276 | 0.022159 | 0.022060 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +16.39%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 371, clang 752, gcc 752. |

| section |
|---|---|
| stride3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001476 | 0.001514 | 0.000231 | 0.001335 | 0.002487 | 0.001701 | 1 |
| clang | 0.001468 | 0.001492 | 0.000154 | 0.001362 | 0.002135 | 0.001601 | 1 |
| gcc | 0.001460 | 0.001477 | 0.000073 | 0.001346 | 0.001634 | 0.001591 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): tie, margin -1.11%, p=0.5000 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.022s (5/5 ok); clang 0.033s (5/5 ok); gcc 0.039s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 287, clang 512, gcc 512. |

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
| absd | 2 | 2026-09-12T21:48:24 | loss | -11.95% | -12.27% | -11.95% |
| arith | 3 | 2026-09-12T00:11:52 | tie | +0.05% | -1.07% | +0.05% |
| bigconst | 3 | 2026-09-12T00:11:52 | tie | -0.23% | -0.35% | +0.23% |
| bitr | 2 | 2026-09-12T21:48:24 | loss | -880.10% | -880.10% | -708.83% |
| brm1 | 2 | 2026-09-12T21:48:24 | loss | -900.58% | -900.58% | -881.07% |
| brm2 | 2 | 2026-09-12T21:48:24 | loss | -173.86% | -173.86% | -173.30% |
| brm3 | 2 | 2026-09-12T21:48:24 | loss | -516.78% | -516.78% | -487.56% |
| ceildiv | 2 | 2026-09-12T21:48:24 | loss | -1.62% | -3.60% | -1.62% |
| cltz | 2 | 2026-09-12T21:48:24 | loss | -154.66% | -154.66% | -150.97% |
| dgcd | 2 | 2026-09-12T21:48:24 | loss | -74.95% | -74.95% | -69.90% |
| div | 5 | 2026-09-12T00:11:52 | tie | -0.22% | -35.72% | +0.15% |
| divd | 2 | 2026-09-12T21:48:24 | loss | -130.54% | -130.69% | -130.54% |
| divm | 2 | 2026-09-12T21:48:24 | tie | -0.44% | -1.11% | -0.44% |
| divpow2 | 2 | 2026-09-12T21:48:24 | loss | -160.73% | -160.73% | -159.16% |
| divv | 2 | 2026-09-12T21:48:24 | tie | -0.16% | -0.16% | +0.40% |
| fib | 3 | 2026-09-12T00:11:52 | tie | -1.62% | -1.62% | +2.31% |
| ilp | 2 | 2026-09-12T21:48:24 | win | +16.39% | +16.01% | +16.39% |
| loopinv | 2 | 2026-09-12T21:48:24 | loss | -341.00% | -566.38% | -341.00% |
| madd | 2 | 2026-09-12T21:48:24 | win | +1.31% | +0.81% | +1.31% |
| mixop | 2 | 2026-09-12T21:48:24 | loss | -362.71% | -574.55% | -362.71% |
| mul13 | 5 | 2026-09-12T00:11:52 | tie | -0.35% | -7.52% | +1.26% |
| mulc | 2 | 2026-09-12T21:48:24 | tie | -0.04% | -0.04% | +0.09% |
| mulh | 2 | 2026-09-12T21:48:24 | loss | -281.31% | -281.31% | -265.11% |
| nest | 5 | 2026-09-12T00:11:52 | tie | +1.09% | -44.04% | +1.09% |
| nest3d | 2 | 2026-09-12T21:48:24 | tie | -2.13% | -2.13% | +0.06% |
| popc | 2 | 2026-09-12T21:48:24 | loss | -195.13% | -195.13% | -174.48% |
| powmod | 2 | 2026-09-12T21:48:24 | loss | -21.94% | -22.13% | -21.94% |
| regp | 2 | 2026-09-12T21:48:24 | tie | -1.24% | -1.24% | -0.32% |
| satadd | 2 | 2026-09-12T21:48:24 | loss | -180.49% | -180.49% | -177.47% |
| sred1 | 2 | 2026-09-12T21:48:24 | loss | -31.96% | -31.96% | -31.27% |
| startup | 3 | 2026-09-12T00:11:52 | tie | -0.95% | -4.38% | -0.95% |
| stride3 | 2 | 2026-09-12T21:48:24 | tie | -1.11% | -2.07% | -1.11% |
| sum | 3 | 2026-09-12T00:11:52 | tie | +0.65% | -2.95% | +0.65% |
| unroll | 2 | 2026-09-12T21:48:24 | loss | -703.80% | -747.68% | -703.80% |
| upbranch | 5 | 2026-09-12T00:11:52 | loss | -2.69% | -24.09% | -2.69% |
| xsft | 2 | 2026-09-12T21:48:24 | loss | -86.88% | -86.99% | -86.88% |
| zerotrip | 5 | 2026-09-12T00:11:52 | loss | -9.54% | -120.32% | +0.15% |
