| field | value |
|---|---|
| title | Optimization verification results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T20:41:37 by `bench/verify/verify.py` (platform arm64-macos, seeds=8, full=False). |

| # | directive |
|---|---|
| 1 | Policy: every mismatch is a compiler bug report. |
| 2 | Cases tagged EXPECTED-ADVERSARIAL were designed to defeat a specific optimization; their mismatch confirms the suspected unsoundness. |

| opt | cases | pass | mismatch | build_fail | hang |
|---|---|---|---|---|---|
| fold | 57 | 56 | 1 | 0 | 0 |
| simp | 35 | 32 | 3 | 0 | 0 |
| imm | 55 | 51 | 4 | 0 | 0 |
| mulred | 69 | 63 | 6 | 0 | 0 |
| countdown | 22 | 21 | 1 | 0 | 0 |
| copy | 19 | 19 | 0 | 0 | 0 |
| div | 51 | 51 | 0 | 0 | 0 |
| nest | 20 | 20 | 0 | 0 | 0 |

| section |
|---|---|
| Mismatches |

| # | directive |
|---|---|
| 1 | [mismatch] fold/mulwrap2: byte 1: idol exit 1 != clang exit 0 — known-32bit-limitation: compile-time arithmetic wraps at 32 bits (see bench/README.md Known limitations) |

| # | directive |
|---|---|
| 1 | [mismatch] simp/r0001: byte 1: idol exit 85 != clang exit 84 |

| # | directive |
|---|---|
| 1 | [mismatch] simp/r0002: byte 1: idol exit 119 != clang exit 118 |

| # | directive |
|---|---|
| 1 | [mismatch] simp/r0005: byte 1: idol exit 107 != clang exit 106 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/sub_wrap: byte 1: idol exit 0 != clang exit 255 — 64-bit wrap on immediate sub |

| # | directive |
|---|---|
| 1 | [mismatch] imm/wrap2: byte 1: idol exit 0 != clang exit 255 — no wrap on sub from max. known-32bit-limitation: integer literals above 4294967295 are truncated at compile time (bench/README.md); this 64-bit wrap probe mismatches until literals go 64-bit |

| # | directive |
|---|---|
| 1 | [mismatch] imm/chain21: byte 1: idol exit 240 != clang exit 239 — wrap: max-4096 across the boundary. known-32bit-limitation: integer literals above 4294967295 are truncated at compile time (bench/README.md); this 64-bit wrap probe mismatches until literals go 64-bit |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0006: byte 1: idol exit 190 != clang exit 189 |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/wrap3: byte 1: idol exit 0 != clang exit 255 — x*3 near 2^64-1 |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/wrap7: byte 1: idol exit 0 != clang exit 255 — x*7 near 2^64-1 |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/w35: byte 1: idol exit 0 != clang exit 255 — mul chain wrapping 2^64. known-32bit-limitation: integer literals above 4294967295 are truncated at compile time (bench/README.md); this 64-bit wrap probe mismatches until literals go 64-bit |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/w22: byte 1: idol exit 0 != clang exit 255 — mul chain wrapping 2^64. known-32bit-limitation: integer literals above 4294967295 are truncated at compile time (bench/README.md); this 64-bit wrap probe mismatches until literals go 64-bit |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/w79: byte 1: idol exit 0 != clang exit 255 — mul chain wrapping 2^64. known-32bit-limitation: integer literals above 4294967295 are truncated at compile time (bench/README.md); this 64-bit wrap probe mismatches until literals go 64-bit |

| # | directive |
|---|---|
| 1 | [mismatch] mulred/r0006: byte 1: idol exit 66 != clang exit 65 |

| # | directive |
|---|---|
| 1 | [mismatch] countdown/double_inc: byte 0: idol exit 100 != clang exit 50 (expected adversarial) — ADVERSARIAL: two increments per iteration |

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
| div | 2 | 2026-09-12T00:11:52 | win | +0.15% | -35.72% | +0.15% |
| fib | 1 | 2026-09-12T00:11:52 | win | +2.31% | +2.31% | +2.31% |
| mul13 | 2 | 2026-09-12T00:11:52 | win | +1.26% | -7.52% | +1.26% |
| nest | 2 | 2026-09-12T00:11:52 | loss | -3.31% | -44.04% | -3.31% |
| startup | 1 | 2026-09-12T00:11:52 | loss | -4.38% | -4.38% | -4.38% |
| sum | 1 | 2026-09-12T00:11:52 | loss | -2.95% | -2.95% | -2.95% |
| upbranch | 2 | 2026-09-12T00:11:52 | loss | -19.86% | -24.09% | -19.86% |
| zerotrip | 2 | 2026-09-12T00:11:52 | loss | -4.32% | -120.32% | -4.32% |
