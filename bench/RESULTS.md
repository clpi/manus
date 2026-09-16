| field | value |
|---|---|
| title | Benchmark results |
| oracle_versions | clang: Apple clang version 21.0.0 (clang-2100.1.1.101) ; gcc: Apple clang version 21.0.0 (clang-2100.1.1.101) |
| correctness_oracle | clang (exit code + byte-identical stdout) |
| route | production |
| load_threshold | 8 (1-min avg; re-sampled before each program) |
| qualification | QUALIFIED: load at start 4.26 vs threshold 8. Load re-sampled before each program's timing. |

| # | directive |
|---|---|
| 1 | Generated 2026-09-16T00:20:27 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). |

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
| sum |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001276 | 0.001403 | 0.000272 | 0.001151 | 0.002144 | 0.001902 | 0 |
| clang | 0.001263 | 0.001378 | 0.000226 | 0.001171 | 0.001899 | 0.001820 | 0 |
| gcc | 0.001277 | 0.001389 | 0.000229 | 0.001174 | 0.001921 | 0.001806 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin -1.01% [95% CI -13.51%, +14.31%]; equivalent=false (90% CI [-10.24%, +9.93%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.7470. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.26. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.037s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| arith |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001707 | 0.001706 | 0.000105 | 0.001534 | 0.001859 | 0.001857 | 0 |
| clang | 0.039764 | 0.039762 | 0.000194 | 0.039215 | 0.040035 | 0.040018 | 0 |
| gcc | 0.040014 | 0.040290 | 0.000992 | 0.039719 | 0.044229 | 0.041684 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +95.71% [95% CI -95.86%, -95.55%]; equivalent=false (90% CI [-95.85%, -95.60%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.26. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 544, gcc 544. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| fib |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001264 | 0.001301 | 0.000122 | 0.001166 | 0.001651 | 0.001589 | 0 |
| clang | 0.001264 | 0.001285 | 0.000101 | 0.001159 | 0.001552 | 0.001465 | 0 |
| gcc | 0.001270 | 0.001286 | 0.000093 | 0.001184 | 0.001518 | 0.001452 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin +0.02% [95% CI -2.96%, +4.34%]; equivalent=false (90% CI [-2.46%, +3.18%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.6631. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.16. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| nest |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001260 | 0.001315 | 0.000124 | 0.001120 | 0.001636 | 0.001547 | 0 |
| clang | 0.001278 | 0.001300 | 0.000103 | 0.001187 | 0.001551 | 0.001545 | 0 |
| gcc | 0.001244 | 0.001296 | 0.000126 | 0.001167 | 0.001671 | 0.001475 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -1.34% [95% CI -7.16%, +10.24%]; equivalent=false (90% CI [-4.13%, +7.74%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.6236. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.16. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| div |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001570 | 0.001595 | 0.000228 | 0.001303 | 0.002222 | 0.001982 | 1 |
| clang | 0.031000 | 0.030944 | 0.001308 | 0.029110 | 0.032926 | 0.032775 | 0 |
| gcc | 0.031787 | 0.031454 | 0.001486 | 0.029589 | 0.035863 | 0.032671 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +94.94% [95% CI -95.27%, -94.64%]; equivalent=false (90% CI [-95.24%, -94.69%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.22. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 560, gcc 560. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| mul13 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001768 | 0.001753 | 0.000127 | 0.001533 | 0.002040 | 0.001915 | 0 |
| clang | 0.053290 | 0.053848 | 0.001648 | 0.051403 | 0.057063 | 0.056973 | 0 |
| gcc | 0.053996 | 0.054089 | 0.001739 | 0.051161 | 0.057124 | 0.056979 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +96.68% [95% CI -96.88%, -96.59%]; equivalent=false (90% CI [-96.80%, -96.61%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.22. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 544, gcc 544. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| bigconst |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001390 | 0.001378 | 0.000067 | 0.001238 | 0.001478 | 0.001470 | 0 |
| clang | 0.001354 | 0.001365 | 0.000068 | 0.001271 | 0.001586 | 0.001470 | 1 |
| gcc | 0.001349 | 0.001350 | 0.000073 | 0.001257 | 0.001535 | 0.001455 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -3.11% [95% CI -2.59%, +7.94%]; equivalent=false (90% CI [-1.52%, +6.89%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.2046. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.13. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| zerotrip |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001329 | 0.001366 | 0.000091 | 0.001274 | 0.001606 | 0.001570 | 0 |
| clang | 0.001370 | 0.001468 | 0.000362 | 0.001270 | 0.002975 | 0.001725 | 2 |
| gcc | 0.001339 | 0.001354 | 0.000078 | 0.001255 | 0.001554 | 0.001452 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin +0.79% [95% CI -5.45%, +5.62%]; equivalent=false (90% CI [-4.52%, +5.05%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.6305. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.13. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001599 | 0.001624 | 0.000078 | 0.001495 | 0.001881 | 0.001695 | 1 |
| clang | 0.007477 | 0.007552 | 0.000323 | 0.007133 | 0.008578 | 0.008084 | 1 |
| gcc | 0.007637 | 0.007629 | 0.000167 | 0.007237 | 0.007941 | 0.007900 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +78.61% [95% CI -79.02%, -77.88%]; equivalent=false (90% CI [-78.97%, -78.05%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.20. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.047s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16848. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 608, gcc 608. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| startup |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001447 | 0.001514 | 0.000376 | 0.001303 | 0.003125 | 0.001557 | 1 |
| clang | 0.001412 | 0.001513 | 0.000309 | 0.001299 | 0.002639 | 0.002065 | 2 |
| gcc | 0.001402 | 0.001498 | 0.000366 | 0.001267 | 0.003030 | 0.001685 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -3.17% [95% CI -2.88%, +6.93%]; equivalent=false (90% CI [-2.00%, +6.08%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.8873. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.20. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| brm1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001949 | 0.002021 | 0.000229 | 0.001799 | 0.002594 | 0.002498 | 3 |
| clang | 0.001911 | 0.002012 | 0.000270 | 0.001781 | 0.002797 | 0.002656 | 2 |
| gcc | 0.001914 | 0.001943 | 0.000121 | 0.001808 | 0.002217 | 0.002118 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin -1.97% [95% CI -3.67%, +7.14%]; equivalent=false (90% CI [-3.17%, +6.06%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.9053. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.20. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 568, gcc 568. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| brm2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.004470 | 0.004686 | 0.000393 | 0.004334 | 0.005522 | 0.005513 | 0 |
| clang | 0.004389 | 0.004621 | 0.000544 | 0.004188 | 0.005877 | 0.005833 | 0 |
| gcc | 0.004369 | 0.004459 | 0.000286 | 0.004210 | 0.005157 | 0.005114 | 3 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -2.33% [95% CI +0.89%, +11.44%]; equivalent=false (90% CI [+1.52%, +10.99%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0390. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.02. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 576, gcc 576. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| brm3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001469 | 0.001522 | 0.000144 | 0.001401 | 0.001978 | 0.001772 | 1 |
| clang | 0.001487 | 0.001543 | 0.000152 | 0.001420 | 0.001976 | 0.001911 | 1 |
| gcc | 0.001501 | 0.001533 | 0.000127 | 0.001397 | 0.001948 | 0.001779 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin +1.20% [95% CI -5.54%, +2.79%]; equivalent=false (90% CI [-4.69%, +1.27%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.6449. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.02. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.032s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 592, gcc 592. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| divv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.073167 | 0.073180 | 0.001481 | 0.070808 | 0.077511 | 0.075079 | 1 |
| clang | 0.042609 | 0.042069 | 0.001095 | 0.039614 | 0.043174 | 0.043125 | 0 |
| gcc | 0.042453 | 0.042185 | 0.001139 | 0.039819 | 0.044768 | 0.043534 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -72.35% [95% CI +71.21%, +74.81%]; equivalent=false (90% CI [+71.52%, +74.05%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 4.10. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.034s (5/5 ok); gcc 0.038s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 560, gcc 560. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| divm |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.008823 | 0.008821 | 0.000068 | 0.008722 | 0.008984 | 0.008940 | 0 |
| clang | 0.006386 | 0.006390 | 0.000108 | 0.006277 | 0.006780 | 0.006486 | 1 |
| gcc | 0.006336 | 0.006365 | 0.000089 | 0.006255 | 0.006550 | 0.006524 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -39.25% [95% CI +37.68%, +39.99%]; equivalent=false (90% CI [+37.97%, +39.95%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.85. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 664, gcc 664. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| divd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001552 | 0.001559 | 0.000134 | 0.001354 | 0.001778 | 0.001773 | 0 |
| clang | 0.006315 | 0.006322 | 0.000084 | 0.006186 | 0.006513 | 0.006469 | 1 |
| gcc | 0.006384 | 0.006418 | 0.000134 | 0.006192 | 0.006706 | 0.006589 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +75.42% [95% CI -76.97%, -74.42%]; equivalent=false (90% CI [-76.94%, -74.79%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.85. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.039s (5/5 ok); gcc 0.044s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 1088, gcc 1088. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| dgcd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.003981 | 0.004111 | 0.000574 | 0.003777 | 0.006558 | 0.004331 | 1 |
| clang | 0.004077 | 0.004086 | 0.000169 | 0.003901 | 0.004738 | 0.004243 | 1 |
| gcc | 0.004080 | 0.004138 | 0.000418 | 0.003860 | 0.005880 | 0.004323 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +2.35% [95% CI -3.81%, -0.14%]; equivalent=false (90% CI [-3.62%, -0.54%] vs band [-2%,+2%]); mean/median conflict=true; Welch p (mean diagnostic)=0.8508. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.85. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.042s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 632, gcc 632. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| divpow2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001304 | 0.001332 | 0.000091 | 0.001207 | 0.001565 | 0.001545 | 0 |
| clang | 0.016174 | 0.016175 | 0.000083 | 0.016018 | 0.016295 | 0.016292 | 0 |
| gcc | 0.016182 | 0.016201 | 0.000101 | 0.016056 | 0.016441 | 0.016373 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +91.94% [95% CI -92.09%, -91.75%]; equivalent=false (90% CI [-92.07%, -91.80%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.70. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.028s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 544, gcc 544. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| ceildiv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.016912 | 0.017108 | 0.000570 | 0.016772 | 0.019420 | 0.017576 | 1 |
| clang | 0.011499 | 0.011699 | 0.000487 | 0.011331 | 0.013258 | 0.012851 | 1 |
| gcc | 0.011496 | 0.011561 | 0.000225 | 0.011350 | 0.012351 | 0.011891 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -47.11% [95% CI +46.36%, +48.02%]; equivalent=false (90% CI [+46.43%, +47.89%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.70. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.043s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 744, gcc 744. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| mulc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001736 | 0.001811 | 0.000384 | 0.001475 | 0.003395 | 0.002093 | 1 |
| clang | 0.052667 | 0.053420 | 0.001883 | 0.051938 | 0.059864 | 0.055868 | 1 |
| gcc | 0.052883 | 0.053792 | 0.002727 | 0.052078 | 0.064858 | 0.055746 | 3 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +96.70% [95% CI -96.84%, -96.61%]; equivalent=false (90% CI [-96.83%, -96.62%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.56. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 552, gcc 552. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| mulh |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001355 | 0.001458 | 0.000264 | 0.001218 | 0.002058 | 0.002042 | 0 |
| clang | 0.001351 | 0.001504 | 0.000372 | 0.001262 | 0.002661 | 0.002371 | 2 |
| gcc | 0.001326 | 0.001434 | 0.000286 | 0.001257 | 0.002338 | 0.002164 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -2.22% [95% CI -5.49%, +11.97%]; equivalent=false (90% CI [-4.28%, +5.95%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.7798. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.60. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| madd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.031996 | 0.032039 | 0.000318 | 0.031164 | 0.032785 | 0.032443 | 1 |
| clang | 0.025044 | 0.025230 | 0.000723 | 0.024630 | 0.028241 | 0.025635 | 1 |
| gcc | 0.025139 | 0.025189 | 0.000515 | 0.024369 | 0.027088 | 0.025858 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -27.76% [95% CI +26.91%, +28.36%]; equivalent=false (90% CI [+27.09%, +28.29%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.60. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.042s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 560, gcc 560. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| sred1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001601 | 0.001611 | 0.000097 | 0.001414 | 0.001768 | 0.001755 | 0 |
| clang | 0.040138 | 0.041163 | 0.004839 | 0.039786 | 0.062255 | 0.040656 | 1 |
| gcc | 0.040246 | 0.040497 | 0.001201 | 0.039741 | 0.045524 | 0.041439 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +96.01% [95% CI -96.10%, -95.86%]; equivalent=false (90% CI [-96.09%, -95.87%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.71. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 544, gcc 544. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| powmod |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.011135 | 0.011186 | 0.000223 | 0.010917 | 0.011764 | 0.011575 | 0 |
| clang | 0.006947 | 0.006924 | 0.000274 | 0.006509 | 0.007444 | 0.007435 | 0 |
| gcc | 0.006846 | 0.006881 | 0.000218 | 0.006634 | 0.007325 | 0.007315 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -62.65% [95% CI +60.39%, +65.08%]; equivalent=false (90% CI [+60.62%, +64.84%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.73. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.042s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 912, gcc 912. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| popc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.003022 | 0.003058 | 0.000136 | 0.002875 | 0.003347 | 0.003329 | 0 |
| clang | 0.004481 | 0.004521 | 0.000102 | 0.004358 | 0.004710 | 0.004680 | 0 |
| gcc | 0.004530 | 0.004553 | 0.000113 | 0.004360 | 0.004794 | 0.004740 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +32.57% [95% CI -34.13%, -31.46%]; equivalent=false (90% CI [-33.95%, -31.81%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.73. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.039s (5/5 ok); gcc 0.044s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 1136, gcc 1136. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| bitr |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001460 | 0.001494 | 0.000148 | 0.001270 | 0.001783 | 0.001767 | 0 |
| clang | 0.002416 | 0.002432 | 0.000187 | 0.002212 | 0.002979 | 0.002679 | 0 |
| gcc | 0.002428 | 0.002448 | 0.000157 | 0.002233 | 0.002835 | 0.002705 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +39.57% [95% CI -42.59%, -35.11%]; equivalent=false (90% CI [-41.78%, -35.79%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.73. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.040s (5/5 ok); gcc 0.044s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 1296, gcc 1296. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| xsft |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.021546 | 0.021688 | 0.000428 | 0.021317 | 0.022790 | 0.022277 | 0 |
| clang | 0.032664 | 0.032872 | 0.000517 | 0.032417 | 0.033933 | 0.033843 | 0 |
| gcc | 0.032689 | 0.032854 | 0.000523 | 0.032393 | 0.034201 | 0.033932 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +34.04% [95% CI -34.89%, -33.37%]; equivalent=false (90% CI [-34.73%, -33.60%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.84. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.040s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 608, gcc 608. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| absd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.017252 | 0.017306 | 0.000221 | 0.017005 | 0.017756 | 0.017743 | 0 |
| clang | 0.011882 | 0.011925 | 0.000137 | 0.011743 | 0.012289 | 0.012172 | 0 |
| gcc | 0.011861 | 0.011918 | 0.000318 | 0.011756 | 0.013275 | 0.011980 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -45.45% [95% CI +44.62%, +46.73%]; equivalent=false (90% CI [+44.72%, +46.47%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.84. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 600, gcc 600. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| cltz |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.010560 | 0.010651 | 0.000329 | 0.010368 | 0.011912 | 0.010871 | 1 |
| clang | 0.029142 | 0.029436 | 0.001787 | 0.028179 | 0.036950 | 0.030673 | 2 |
| gcc | 0.029133 | 0.029752 | 0.001620 | 0.028195 | 0.034012 | 0.033338 | 4 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): win, median margin +63.75% [95% CI -64.08%, -63.19%]; equivalent=false (90% CI [-64.03%, -63.33%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.69. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 608, gcc 608. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| nest3d |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001480 | 0.001470 | 0.000103 | 0.001304 | 0.001649 | 0.001609 | 0 |
| clang | 0.001466 | 0.001453 | 0.000112 | 0.001254 | 0.001627 | 0.001626 | 0 |
| gcc | 0.001461 | 0.001480 | 0.000126 | 0.001269 | 0.001686 | 0.001664 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -1.33% [95% CI -8.05%, +9.48%]; equivalent=false (90% CI [-7.43%, +7.85%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.7729. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.55. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 960, gcc 960. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| unroll |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001275 | 0.001322 | 0.000114 | 0.001217 | 0.001577 | 0.001569 | 1 |
| clang | 0.001304 | 0.001342 | 0.000144 | 0.001164 | 0.001795 | 0.001617 | 1 |
| gcc | 0.001269 | 0.001306 | 0.000103 | 0.001197 | 0.001536 | 0.001483 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): inconclusive, median margin -0.44% [95% CI -5.41%, +5.78%]; equivalent=false (90% CI [-3.99%, +4.47%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.6297. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.55. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.029s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| mixop |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001413 | 0.001457 | 0.000136 | 0.001299 | 0.001752 | 0.001693 | 0 |
| clang | 0.004289 | 0.004341 | 0.000197 | 0.004065 | 0.005073 | 0.004516 | 1 |
| gcc | 0.004343 | 0.004350 | 0.000109 | 0.004183 | 0.004635 | 0.004506 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +67.06% [95% CI -68.66%, -64.03%]; equivalent=false (90% CI [-68.60%, -64.82%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.55. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.040s (5/5 ok); gcc 0.043s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 688, gcc 688. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| loopinv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001385 | 0.001408 | 0.000116 | 0.001296 | 0.001772 | 0.001630 | 0 |
| clang | 0.001354 | 0.001513 | 0.000581 | 0.001240 | 0.003993 | 0.001785 | 1 |
| gcc | 0.001388 | 0.001407 | 0.000127 | 0.001259 | 0.001735 | 0.001641 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin -2.34% [95% CI -6.51%, +6.18%]; equivalent=false (90% CI [-5.78%, +4.62%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.4273. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.51. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.039s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| satadd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001533 | 0.001783 | 0.000541 | 0.001367 | 0.003327 | 0.002815 | 3 |
| clang | 0.004481 | 0.004842 | 0.001063 | 0.004256 | 0.008727 | 0.006965 | 3 |
| gcc | 0.004627 | 0.005394 | 0.001613 | 0.004417 | 0.009992 | 0.009375 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, median margin +65.78% [95% CI -67.02%, -62.72%]; equivalent=false (90% CI [-66.69%, -63.33%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.51. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.038s (5/5 ok); gcc 0.043s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 760, gcc 760. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| regp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001655 | 0.001695 | 0.000092 | 0.001587 | 0.001877 | 0.001867 | 0 |
| clang | 0.001327 | 0.001354 | 0.000109 | 0.001219 | 0.001661 | 0.001523 | 1 |
| gcc | 0.001305 | 0.001339 | 0.000103 | 0.001206 | 0.001626 | 0.001471 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, median margin -26.83% [95% CI +20.08%, +35.12%]; equivalent=false (90% CI [+22.72%, +33.29%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.0000. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.51. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.036s (5/5 ok); clang 0.036s (5/5 ok); gcc 0.041s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| ilp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.021868 | 0.021847 | 0.000210 | 0.021400 | 0.022203 | 0.022185 | 0 |
| clang | 0.021881 | 0.021978 | 0.000774 | 0.020722 | 0.025091 | 0.022192 | 1 |
| gcc | 0.021787 | 0.021705 | 0.000487 | 0.019862 | 0.022092 | 0.022083 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): equivalent, median margin -0.37% [95% CI -0.28%, +0.81%]; equivalent=true (90% CI [-0.22%, +0.75%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.2305. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.63. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.037s (5/5 ok); gcc 0.042s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 752, gcc 752. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

| section |
|---|---|
| stride3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001384 | 0.001547 | 0.000763 | 0.001282 | 0.004864 | 0.001535 | 1 |
| clang | 0.001346 | 0.001386 | 0.000190 | 0.001237 | 0.002182 | 0.001459 | 1 |
| gcc | 0.001369 | 0.001425 | 0.000262 | 0.001247 | 0.002520 | 0.001569 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): inconclusive, median margin -2.82% [95% CI -0.95%, +6.36%]; equivalent=false (90% CI [-0.38%, +6.12%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.3598. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /Users/clp/work/idol-main/zig-out/bin/idol sha256=37e121a8f4769c61... (route production, rev 64765db2dbf9b639fe5692439c0103c8d33a48cd). Load before timing: 3.63. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.030s (5/5 ok); clang 0.035s (5/5 ok); gcc 0.040s (5/5 ok). Idol compiler sha256=37e121a8f4769c61... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 512, gcc 512. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |

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
| absd | 4 | 2026-09-15T05:56:29 | loss | -45.45% | -57.52% | -44.72% |
| arith | 4 | 2026-09-15T05:56:29 | win | +95.71% | +95.18% | +95.71% |
| bigconst | 4 | 2026-09-15T05:56:29 | inconclusive | -3.11% | -4.30% | -1.78% |
| bitr | 11 | 2026-09-13T07:47:26 | win | +39.57% | -35.56% | +40.45% |
| brm1 | 5 | 2026-09-13T07:47:26 | inconclusive | -1.97% | -3.46% | +0.59% |
| brm2 | 9 | 2026-09-13T07:47:26 | loss | -2.33% | -217.03% | -1.81% |
| brm3 | 6 | 2026-09-13T07:47:26 | inconclusive | +1.20% | -130.65% | +2.22% |
| ceildiv | 4 | 2026-09-15T05:56:29 | loss | -47.11% | -72.29% | -47.11% |
| cltz | 8 | 2026-09-13T08:16:29 | win | +63.75% | -65.18% | +64.43% |
| dgcd | 5 | 2026-09-15T05:56:29 | win | +2.35% | -0.06% | +2.35% |
| div | 4 | 2026-09-15T05:56:29 | win | +94.94% | +94.39% | +95.10% |
| divd | 10 | 2026-09-15T05:56:29 | win | +75.42% | -308.65% | +78.39% |
| divm | 4 | 2026-09-15T05:56:29 | loss | -39.25% | -60.46% | -37.20% |
| divpow2 | 10 | 2026-09-13T07:47:26 | win | +91.94% | -140.18% | +91.94% |
| divv | 4 | 2026-09-15T05:56:29 | loss | -72.35% | -104.82% | -72.35% |
| fib | 4 | 2026-09-15T05:56:29 | inconclusive | +0.02% | -5.65% | +0.02% |
| ilp | 4 | 2026-09-15T05:56:29 | equivalent | -0.37% | -6.90% | -0.37% |
| loopinv | 4 | 2026-09-15T05:56:29 | inconclusive | -2.34% | -2.34% | +0.04% |
| madd | 4 | 2026-09-15T05:56:29 | loss | -27.76% | -28.20% | -26.04% |
| mixop | 12 | 2026-09-13T07:47:26 | win | +67.06% | -67.83% | +67.06% |
| mul13 | 4 | 2026-09-15T05:56:29 | win | +96.68% | +96.26% | +96.92% |
| mulc | 4 | 2026-09-15T05:56:29 | win | +96.70% | +96.50% | +96.70% |
| mulh | 5 | 2026-09-15T05:56:29 | inconclusive | -2.22% | -4.36% | -0.78% |
| nest | 4 | 2026-09-15T05:56:29 | inconclusive | -1.34% | -2.60% | -0.23% |
| nest3d | 4 | 2026-09-15T05:56:29 | inconclusive | -1.33% | -8.66% | -0.26% |
| popc | 7 | 2026-09-13T07:47:26 | win | +32.57% | -212.08% | +34.05% |
| powmod | 4 | 2026-09-15T05:56:29 | loss | -62.65% | -96.35% | -57.57% |
| regp | 4 | 2026-09-15T05:56:29 | loss | -26.83% | -27.47% | -20.64% |
| satadd | 7 | 2026-09-15T05:56:29 | win | +65.78% | -62.22% | +67.88% |
| sred1 | 4 | 2026-09-15T05:56:29 | win | +96.01% | +95.42% | +96.27% |
| startup | 4 | 2026-09-15T05:56:29 | inconclusive | -3.17% | -3.34% | -0.09% |
| stride3 | 4 | 2026-09-15T05:56:29 | inconclusive | -2.82% | -2.82% | +2.27% |
| sum | 4 | 2026-09-15T05:56:29 | inconclusive | -1.01% | -1.01% | +1.95% |
| unroll | 8 | 2026-09-15T05:56:29 | inconclusive | -0.44% | -994.87% | +0.41% |
| upbranch | 7 | 2026-09-15T05:56:29 | win | +78.61% | -26.00% | +80.74% |
| xsft | 5 | 2026-09-15T05:56:29 | win | +34.04% | +34.01% | +34.40% |
| zerotrip | 7 | 2026-09-15T05:56:29 | inconclusive | +0.79% | -418.55% | +3.71% |
| zerotrip2 | 1 | 2026-09-15T23:50:05 | inconclusive | -0.38% | -0.38% | -0.38% |
