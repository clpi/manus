| field | value |
|---|---|
| title | Optimization verification results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T01:40:52 by `bench/verify/verify.py` (platform arm64-macos, seeds=40, full=True). |


| # | directive |
|---|---|
| 1 | Policy: every mismatch is a compiler bug report. |
| 2 | Cases tagged EXPECTED-ADVERSARIAL were designed to defeat a specific optimization; their mismatch confirms the suspected unsoundness. |


| opt | cases | pass | mismatch | build_fail | hang |
|---|---|---|---|---|---|
| div | 83 | 62 | 4 | 17 | 0 |

| section |
|---|---|
| Mismatches |

| # | directive |
|---|---|
| 1 | [mismatch] div/neg: byte 0: idol exit 73 != clang exit 244 — known-32bit-limitation: negative folded dividend is zero-extended, not sign-extended |
| 2 | [mismatch] div/neg2: byte 0: idol exit 22 != clang exit 242 — known-32bit-limitation |
| 3 | [mismatch] div/negchain0: byte 0: idol exit 7 != clang exit 252 — known-32bit-limitation: negative folded dividend is zero-extended, then chained through division |
| 4 | [mismatch] div/negchain1: byte 0: idol exit 149 != clang exit 253 — known-32bit-limitation |
| 5 | [build_fail] div/d0023: idol build failed (byte 5): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0023_b5.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0024: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0024_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0025: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0025_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0026: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0026_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0027: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0027_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0028: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0028_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0029: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0029_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0030: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0030_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0031: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0031_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0032: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0032_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0033: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0033_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0034: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0034_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0035: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0035_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0036: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0036_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0037: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0037_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/r0038: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_r0038_b0.o'

| # | directive |
|---|---|
| 1 | [build_fail] div/d0039: idol build failed (byte 0): plat_link failed: |
ld: file is empty in '$HOME/work/idol-main/bench/verify/.work/v_div_d0039_b0.o'

| section |
|---|---|
| performance history |

| # | directive |
|---|---|
| 1 | Per-case benchmark verdict history across runs. Any commit that regresses a case is visible here. |
| 2 | margin% = (rival_median - idol_median) / rival_median; negative = idol slower. |
| 3 | Source: bench/results/history.jsonl, one entry appended per bench/run.sh run. |

| case | runs | first seen | last verdict | last margin% | worst margin% | best margin% |
|---|---|---|---|---|---|---|
| arith | 1 | 2026-09-12T00:11:52 | loss | -0.85% | -0.85% | -0.85% |
| bigconst | 1 | 2026-09-12T00:11:52 | loss | -0.35% | -0.35% | -0.35% |
| div | 1 | 2026-09-12T00:11:52 | loss | -35.72% | -35.72% | -35.72% |
| fib | 1 | 2026-09-12T00:11:52 | win | +2.31% | +2.31% | +2.31% |
| mul13 | 1 | 2026-09-12T00:11:52 | loss | -7.52% | -7.52% | -7.52% |
| nest | 1 | 2026-09-12T00:11:52 | loss | -44.04% | -44.04% | -44.04% |
| startup | 1 | 2026-09-12T00:11:52 | loss | -4.38% | -4.38% | -4.38% |
| sum | 1 | 2026-09-12T00:11:52 | loss | -2.95% | -2.95% | -2.95% |
| upbranch | 1 | 2026-09-12T00:11:52 | loss | -24.09% | -24.09% | -24.09% |
| zerotrip | 1 | 2026-09-12T00:11:52 | loss | -120.32% | -120.32% | -120.32% |
