| field | value |
|---|---|
| title | Benchmark results |
| oracle_versions | clang: Apple clang version 21.0.0 (clang-2100.1.1.101) ; gcc: Apple clang version 21.0.0 (clang-2100.1.1.101) |
| correctness_oracle | clang (exit code + byte-identical stdout) |
| route | production |

| # | directive |
|---|---|
| 1 | Generated 2026-09-14T17:54:19 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). |

| section |
|---|---|
| corrections |

| # | directive |
|---|---|
| 1 | [route] Route labeling: the `idol` binaries in every section below were compiled by the route named in the `route` field row above. RESTRICTED route = `idol compile lib/compiler/native.id --backend native --no-cache -o nativebench`, then `nativebench < P.id` piped through `xxd -r -p`, then `ld -arch arm64 -e _idolmain`. PRODUCTION route = the production compiler (`zig-out/bin/idol compile P.id --backend native --no-cache -o P.idol`), which emits a linked Mach-O executable directly. The production route (src/native.zig) does not consume the .id optimizer passes (opt/licm.id, opt/poly.id, opt/zerotrip.id); restricted-route wins are not production progress until the production route consumes the technique with its own equivalence + cost evidence. |
| 2 | [oracle-identity] Comparator identity is established at run time via `clang --version` and `gcc --version`, and the discovered version strings are recorded per run in this report; identity is never assumed from command names. On the Mac mini both report Apple clang 21.0.0 (clang-2100.1.1.101), Target: arm64-apple-darwin25.5.0 -- no GNU GCC is measured here, so the "gcc" column is an Apple-clang alias of the "clang" column, not an independent oracle. |
| 3 | [compile-time-scope] Compile-time rows (`Compile time, source to executable`) use the run's labeled route vs the run-time-discovered comparators: restricted = the `nativebench` produce/decode/`ld` pipeline; production = `zig-out/bin/idol compile P.id --backend native --no-cache -o P.idol`. A duration counts as a successful compilation only after every required stage succeeded and the artifact was validated (exists, nonzero size). Failed attempts are recorded as FAILED work and are never mixed into success medians. Faster compile time does not offset slower output, extra allocation, larger code, or wrong answers; no faster-compile-time claim may be presented as compensating for those. |
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
| mixop |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006869 | 0.007022 | 0.000497 | 0.006491 | 0.008581 | 0.007723 | 0 |
| clang | 0.004738 | 0.004773 | 0.000201 | 0.004323 | 0.005224 | 0.005027 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -44.99%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.043s (5/5 ok); clang 0.055s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Artifact size (bytes; idol = linked executable, production route emits no separate object): idol 16840, clang 688, gcc 688. |

| section |
|---|---|
| bitr |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006439 | 0.006892 | 0.002569 | 0.004265 | 0.017015 | 0.008352 | 1 |
| clang | 0.005577 | 0.006030 | 0.002085 | 0.003317 | 0.013471 | 0.007934 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, margin -15.47%, p=0.2329 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.053s (5/5 ok); clang 0.066s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Artifact size (bytes; idol = linked executable, production route emits no separate object): idol 16840, clang 1296, gcc 1296. |

| section |
|---|---|
| cltz |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.068068 | 0.074189 | 0.016575 | 0.053571 | 0.106393 | 0.104452 | 0 |
| clang | 0.044484 | 0.049523 | 0.019834 | 0.031851 | 0.122780 | 0.072427 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -53.02%, p=0.0000 (significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.042s (5/5 ok); clang 0.051s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Artifact size (bytes; idol = linked executable, production route emits no separate object): idol 16840, clang 608, gcc 608. |

| section |
|---|---|
| brm2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.005178 | 0.005250 | 0.000270 | 0.004777 | 0.006018 | 0.005568 | 0 |
| clang | 0.005086 | 0.005179 | 0.000529 | 0.004584 | 0.006928 | 0.005972 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, margin -1.81%, p=0.5817 (not significant; win/loss requires p<0.05). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.038s (5/5 ok); clang 0.048s (5/5 ok). |

| # | directive |
|---|---|
| 1 | Artifact size (bytes; idol = linked executable, production route emits no separate object): idol 16840, clang 576, gcc 576. |

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
| bitr | 4 | 2026-09-13T07:47:26 | inconclusive | -15.47% | -35.56% | -15.47% |
| brm1 | 1 | 2026-09-13T07:47:26 | tie | -3.22% | -3.22% | -3.22% |
| brm2 | 4 | 2026-09-13T07:47:26 | inconclusive | -1.81% | -217.03% | -1.81% |
| brm3 | 2 | 2026-09-13T07:47:26 | inconclusive | -5.20% | -130.65% | -5.20% |
| cltz | 3 | 2026-09-13T08:16:29 | loss | -53.02% | -65.18% | -53.02% |
| divpow2 | 6 | 2026-09-13T07:47:26 | inconclusive | +0.17% | -140.18% | +0.46% |
| mixop | 4 | 2026-09-13T07:47:26 | loss | -44.99% | -67.83% | -44.99% |
| popc | 3 | 2026-09-13T07:47:26 | inconclusive | +9.58% | -212.08% | +9.58% |
