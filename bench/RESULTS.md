| field | value |
|---|---|
| title | Benchmark results |
| oracle_versions | clang: Apple clang version 21.0.0 (clang-2100.1.1.101) ; gcc: Apple clang version 21.0.0 (clang-2100.1.1.101) |
| correctness_oracle | clang (exit code + byte-identical stdout) |
| route | production |
| load_threshold | 8 (1-min avg; re-sampled before each program) |
| qualification | QUALIFIED: load at start 3.33 vs threshold 8. Load re-sampled before each program's timing. |

| # | directive |
|---|---|
| 1 | Generated 2026-09-15T19:48:13 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). |

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
| 10 | [equivalence-procedure] RETIRED 2026-09-15: the former parity criterion ('abs(median runtime delta) <= 2% AND Welch p >= 0.05 => parity') is withdrawn. A small point estimate plus failure to reject a difference does not establish equivalence. The replacement, predeclared: a verdict of 'equivalent' on a program requires the 90% confidence interval for the median runtime difference (idol - rival, as % of rival median; bootstrap percentile, B=2000, fixed seed 20260915) to lie WHOLLY inside the band [-2%, +2%]. Win/loss requires the 95% CI to exclude zero. Any other outcome is 'inconclusive' — never 'tie', 'parity', or equivalence-by-default. Welch's t (Welch-Satterthwaite df) is reported as a mean-based diagnostic only; a mean/median disagreement is flagged, never silently resolved. A verdict of win/loss/equivalent without the band, the interval, and the uncertainty behind it is inadmissible. Loaded-machine figures remain indicative only, never conclusive. |

| # | directive |
|---|---|
| 1 | Honesty policy: every program x every compiler is listed. |
| 2 | Losses are reported, not hidden. |
| 3 | A loss is a bug report against the compiler. |
| 4 | No win/loss without a median-difference 95% bootstrap CI excluding zero; no 'equivalent' without a 90% CI wholly inside the predeclared +/-2% band; otherwise the verdict is inconclusive — never 'tie'. The retired rule 'abs(median diff) <= 2% and Welch p >= 0.05 => parity' must not appear in any verdict. |
| 5 | Raw per-round samples are retained in bench results.json per row; every verdict is re-derivable. |
| 6 | Producer binding: the timer's compiler attribution is cross-checked against the exact hashed binary every program; a mismatch aborts. |
| 7 | Sizes are like-for-like only: executables vs executables, objects vs objects. No single ratio across unequal artifact boundaries. |
| 8 | An UNQUALIFIED run yields exploratory verdicts only; no qualified comparison claim may be drawn from it. |

| section |
|---|---|
| unroll |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001542 | 0.001596 | 0.000339 | 0.001224 | 0.002297 | 0.002222 | 0 |
| clang | 0.001510 | 0.001559 | 0.000290 | 0.001228 | 0.002277 | 0.001995 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin -2.15% [95% CI -17.45%, +20.98%]; equivalent=false (90% CI [-14.73%, +20.18%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.7054. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.33. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.034s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| zerotrip |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.003630 | 0.003691 | 0.000235 | 0.003452 | 0.004441 | 0.004195 | 2 |
| clang | 0.001283 | 0.001304 | 0.000086 | 0.001192 | 0.001517 | 0.001466 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -182.94% [95% CI +170.10%, +191.98%]; equivalent=false (90% CI [+172.06%, +190.66%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.33. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.033s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| divd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.024865 | 0.024893 | 0.000231 | 0.024457 | 0.025455 | 0.025170 | 0 |
| clang | 0.006378 | 0.006418 | 0.000194 | 0.006150 | 0.006870 | 0.006752 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -289.83% [95% CI +284.89%, +295.26%]; equivalent=false (90% CI [+285.97%, +294.83%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.47. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.042s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 1088. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.008723 | 0.008774 | 0.000210 | 0.008514 | 0.009238 | 0.009167 | 0 |
| clang | 0.007569 | 0.007608 | 0.000233 | 0.007314 | 0.008125 | 0.008085 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -15.24% [95% CI +13.35%, +17.46%]; equivalent=false (90% CI [+13.55%, +17.05%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.47. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.037s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 608. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| satadd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006828 | 0.006927 | 0.000423 | 0.006622 | 0.008679 | 0.007116 | 1 |
| clang | 0.004367 | 0.004646 | 0.001077 | 0.004231 | 0.009292 | 0.004927 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -56.35% [95% CI +53.04%, +58.84%]; equivalent=false (90% CI [+53.93%, +58.54%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.47. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.039s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 760. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| mixop |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006517 | 0.006523 | 0.000101 | 0.006344 | 0.006711 | 0.006703 | 0 |
| clang | 0.004285 | 0.004291 | 0.000174 | 0.004065 | 0.004884 | 0.004438 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -52.08% [95% CI +49.13%, +54.60%]; equivalent=false (90% CI [+49.39%, +54.12%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.51. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.038s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 688. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

| section |
|---|---|
| bitr |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.002922 | 0.002934 | 0.000096 | 0.002826 | 0.003253 | 0.003071 | 1 |
| clang | 0.002330 | 0.002348 | 0.000093 | 0.002240 | 0.002605 | 0.002561 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -25.41% [95% CI +23.35%, +27.27%]; equivalent=false (90% CI [+23.61%, +26.93%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=61357c15077b604b... (route production, rev 9a8a3239b71e81ed7eab3f6f51a4277805b9cb1e). Load before timing: 3.51. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.040s (5/5 ok). Idol compiler sha256=61357c15077b604b... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 1296. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0. |

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
| absd | 1 | 2026-09-15T05:56:29 | loss | -57.52% | -57.52% | -57.52% |
| arith | 1 | 2026-09-15T05:56:29 | win | +95.18% | +95.18% | +95.18% |
| bigconst | 1 | 2026-09-15T05:56:29 | loss | -3.61% | -3.61% | -3.61% |
| bitr | 7 | 2026-09-13T07:47:26 | loss | -25.41% | -35.56% | -15.47% |
| brm1 | 2 | 2026-09-13T07:47:26 | inconclusive | -3.46% | -3.46% | -3.22% |
| brm2 | 6 | 2026-09-13T07:47:26 | inconclusive | -3.30% | -217.03% | -1.81% |
| brm3 | 3 | 2026-09-13T07:47:26 | inconclusive | +1.81% | -130.65% | +1.81% |
| ceildiv | 1 | 2026-09-15T05:56:29 | loss | -70.17% | -70.17% | -70.17% |
| cltz | 5 | 2026-09-13T08:16:29 | win | +63.45% | -65.18% | +64.43% |
| dgcd | 2 | 2026-09-15T05:56:29 | inconclusive | -0.03% | -0.03% | +0.20% |
| div | 1 | 2026-09-15T05:56:29 | win | +94.39% | +94.39% | +94.39% |
| divd | 4 | 2026-09-15T05:56:29 | loss | -289.83% | -308.65% | -264.63% |
| divm | 1 | 2026-09-15T05:56:29 | loss | -54.92% | -54.92% | -54.92% |
| divpow2 | 7 | 2026-09-13T07:47:26 | win | +89.51% | -140.18% | +89.51% |
| divv | 1 | 2026-09-15T05:56:29 | loss | -93.17% | -93.17% | -93.17% |
| fib | 1 | 2026-09-15T05:56:29 | inconclusive | -5.65% | -5.65% | -5.65% |
| ilp | 1 | 2026-09-15T05:56:29 | inconclusive | -0.43% | -0.43% | -0.43% |
| loopinv | 1 | 2026-09-15T05:56:29 | inconclusive | +0.04% | +0.04% | +0.04% |
| madd | 1 | 2026-09-15T05:56:29 | loss | -28.20% | -28.20% | -28.20% |
| mixop | 8 | 2026-09-13T07:47:26 | loss | -52.08% | -67.83% | -40.67% |
| mul13 | 1 | 2026-09-15T05:56:29 | win | +96.57% | +96.57% | +96.57% |
| mulc | 1 | 2026-09-15T05:56:29 | win | +96.60% | +96.60% | +96.60% |
| mulh | 2 | 2026-09-15T05:56:29 | inconclusive | -3.95% | -3.95% | -2.54% |
| nest | 1 | 2026-09-15T05:56:29 | inconclusive | -2.60% | -2.60% | -2.60% |
| nest3d | 1 | 2026-09-15T05:56:29 | inconclusive | -8.66% | -8.66% | -8.66% |
| popc | 4 | 2026-09-13T07:47:26 | win | +25.88% | -212.08% | +25.88% |
| powmod | 1 | 2026-09-15T05:56:29 | loss | -81.95% | -81.95% | -81.95% |
| regp | 1 | 2026-09-15T05:56:29 | loss | -25.77% | -25.77% | -25.77% |
| satadd | 3 | 2026-09-15T05:56:29 | loss | -56.35% | -62.22% | -56.35% |
| sred1 | 1 | 2026-09-15T05:56:29 | win | +95.74% | +95.74% | +95.74% |
| startup | 1 | 2026-09-15T05:56:29 | inconclusive | -3.34% | -3.34% | -3.34% |
| stride3 | 1 | 2026-09-15T05:56:29 | inconclusive | -1.63% | -1.63% | -1.63% |
| sum | 1 | 2026-09-15T05:56:29 | inconclusive | -0.54% | -0.54% | -0.54% |
| unroll | 4 | 2026-09-15T05:56:29 | inconclusive | -2.15% | -994.87% | -0.97% |
| upbranch | 3 | 2026-09-15T05:56:29 | loss | -15.24% | -26.00% | -15.24% |
| xsft | 2 | 2026-09-15T05:56:29 | win | +34.01% | +34.01% | +34.26% |
| zerotrip | 3 | 2026-09-15T05:56:29 | loss | -182.94% | -418.55% | -182.94% |
