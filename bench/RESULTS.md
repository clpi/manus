| field | value |
|---|---|
| title | Benchmark results |
| oracle_versions | clang: Apple clang version 21.0.0 (clang-2100.1.1.101) ; gcc: Apple clang version 21.0.0 (clang-2100.1.1.101) |
| correctness_oracle | clang (exit code + byte-identical stdout) |
| route | production |
| load_threshold | 8 (1-min avg; re-sampled before each program) |
| qualification | QUALIFIED: load at start 6.15 vs threshold 8. Load re-sampled before each program's timing. |
| qualification | QUALIFIED: load at start 5.09 vs threshold 8. Load re-sampled before each program's timing. |

| # | directive |
|---|---|
| 1 | Generated 2026-09-16T01:19:52 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). | |
| 2 | Generated 2026-09-16T01:08:09 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). | |
| 3 | Generated 2026-09-16T01:47:09 by `bench/run.sh` (route production, 21 interleaved rounds, 3 warmup, median is primary). | |

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
| ceildiv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012137 | 0.012245 | 0.000539 | 0.011935 | 0.014562 | 0.012315 | 1 |
| clang | 0.012131 | 0.012306 | 0.000514 | 0.011952 | 0.014121 | 0.013279 | 2 |
| gcc | 0.012171 | 0.012176 | 0.000162 | 0.011896 | 0.012473 | 0.012438 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): equivalent, median margin -0.05% [95% CI -1.16%, +1.12%]; equivalent=true (90% CI [-0.70%, +0.96%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.7101. |
| ilp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.022117 | 0.022332 | 0.000423 | 0.021777 | 0.023289 | 0.023240 | 0 |
| clang | 0.022184 | 0.022426 | 0.000683 | 0.021806 | 0.024484 | 0.024179 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): equivalent, median margin +0.30% [95% CI -1.25%, +1.83%]; equivalent=true (90% CI [-1.15%, +1.70%] vs band [-2%,+2%]); mean/median conflict=false; Welch p (mean diagnostic)=0.5949. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /tmp/wt-ceildiv/zig-out/bin/idol sha256=914138468591aff1... (route production, rev e91b00c82a72a5e90b2f84021aee8694af96e79e). Load before timing: 4.78. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.040s (5/5 ok); gcc 0.045s (5/5 ok). Idol compiler sha256=914138468591aff1... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16848, clang 16848, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 744, gcc 744. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |


| section |
|---|---|
| absd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012768 | 0.012763 | 0.000114 | 0.012569 | 0.012983 | 0.012930 | 0 |
| clang | 0.012548 | 0.012672 | 0.000406 | 0.012367 | 0.014075 | 0.013478 | 2 |
| gcc | 0.012599 | 0.012641 | 0.000201 | 0.012385 | 0.013143 | 0.012994 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, median margin -1.75% [95% CI +0.39%, +2.61%]; equivalent=false (90% CI [+0.67%, +2.55%] vs band [-2%,+2%]); mean/median conflict=true; Welch p (mean diagnostic)=0.3343. |
| 2 | Decision rule: declared estimand: median(idol)-median(rival) as % of rival median (positive margin = idol faster). win/loss iff 95% bootstrap percentile CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never 'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic only; mean_median_conflict flags disagreement. Undefined percentage estimand (rival median zero in every bootstrap resample) is insufficient evidence: verdict 'inconclusive', never an affirmative [0,0] interval. |

| # | directive |
|---|---|
| 1 | Producer: /tmp/wt-absd/zig-out/bin/idol sha256=79d3db9e77b219b3... (route production, rev a0d35b964a704368455c38f29ef806218b86ab6f). Load before timing: 6.15. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.031s (5/5 ok); clang 0.039s (5/5 ok); gcc 0.042s (5/5 ok). Idol compiler sha256=79d3db9e77b219b3... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840, gcc 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 600, gcc 600. |
| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): idol __TEXT 16384 __DATA 0; clang __TEXT 16384 __DATA 0; gcc __TEXT 16384 __DATA 0. |
| 1 | Producer: /tmp/wt-madd/zig-out/bin/idol sha256=0576ad89523bea43... (route production, rev f4f76a1adf5e3ce9a7ac69a5f331c1ca44f64dd2). Load before timing: 5.09. |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of successful attempts; FAILED attempts are failed work, never in the median): idol 0.032s (5/5 ok); clang 0.037s (5/5 ok). Idol compiler sha256=0576ad89523bea43... |

| # | directive |
|---|---|
| 1 | Executable size, bytes (linked executables, like-for-like): idol 16840, clang 16840. |
| 2 | Object size, bytes (relocatable objects, like-for-like; idol object kind: none): clang 752. |
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
| absd | 7 | 2026-09-15T05:56:29 | loss | -1.75% | -57.52% | -1.75% |
| arith | 4 | 2026-09-15T05:56:29 | win | +95.71% | +95.18% | +95.71% |
| bigconst | 4 | 2026-09-15T05:56:29 | inconclusive | -3.11% | -4.30% | -1.78% |
| bitr | 11 | 2026-09-13T07:47:26 | win | +39.57% | -35.56% | +40.45% |
| brm1 | 5 | 2026-09-13T07:47:26 | inconclusive | -1.97% | -3.46% | +0.59% |
| brm2 | 9 | 2026-09-13T07:47:26 | loss | -2.33% | -217.03% | -1.81% |
| brm3 | 6 | 2026-09-13T07:47:26 | inconclusive | +1.20% | -130.65% | +2.22% |
| ceildiv | 6 | 2026-09-15T05:56:29 | equivalent | -0.05% | -72.29% | -0.05% |
| cltz | 8 | 2026-09-13T08:16:29 | win | +63.75% | -65.18% | +64.43% |
| dgcd | 5 | 2026-09-15T05:56:29 | win | +2.35% | -0.06% | +2.35% |
| div | 4 | 2026-09-15T05:56:29 | win | +94.94% | +94.39% | +95.10% |
| divd | 10 | 2026-09-15T05:56:29 | win | +75.42% | -308.65% | +78.39% |
| divm | 6 | 2026-09-15T05:56:29 | loss | -19.40% | -60.46% | -19.40% |
| divpow2 | 10 | 2026-09-13T07:47:26 | win | +91.94% | -140.18% | +91.94% |
| divv | 4 | 2026-09-15T05:56:29 | loss | -72.35% | -104.82% | -72.35% |
| fib | 4 | 2026-09-15T05:56:29 | inconclusive | +0.02% | -5.65% | +0.02% |
| ilp | 8 | 2026-09-15T05:56:29 | equivalent | +0.30% | -6.90% | +14.14% |
| loopinv | 4 | 2026-09-15T05:56:29 | inconclusive | -2.34% | -2.34% | +0.04% |
| madd | 9 | 2026-09-15T05:56:29 | loss | -27.14% | -29.23% | -0.15% |
| mixop | 12 | 2026-09-13T07:47:26 | win | +67.06% | -67.83% | +67.06% |
| mul13 | 4 | 2026-09-15T05:56:29 | win | +96.68% | +96.26% | +96.92% |
| mulc | 4 | 2026-09-15T05:56:29 | win | +96.70% | +96.50% | +96.70% |
| mulh | 5 | 2026-09-15T05:56:29 | inconclusive | -2.22% | -4.36% | -0.78% |
| nest | 4 | 2026-09-15T05:56:29 | inconclusive | -1.34% | -2.60% | -0.23% |
| nest3d | 4 | 2026-09-15T05:56:29 | inconclusive | -1.33% | -8.66% | -0.26% |
| popc | 7 | 2026-09-13T07:47:26 | win | +32.57% | -212.08% | +34.05% |
| powmod | 6 | 2026-09-15T05:56:29 | loss | -20.37% | -96.35% | -19.81% |
| regp | 7 | 2026-09-15T05:56:29 | loss | -25.44% | -27.47% | -20.64% |
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
