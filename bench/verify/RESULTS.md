| field | value |
|---|---|
| title | Optimization verification results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T22:27:59 by `bench/verify/verify.py` (platform arm64-macos, seeds=8, full=False). |

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
| absd | 1 | 2026-09-12T21:48:24 | loss | -12.27% | -12.27% | -12.27% |
| arith | 2 | 2026-09-12T00:11:52 | loss | -1.07% | -1.07% | -0.85% |
| bigconst | 2 | 2026-09-12T00:11:52 | win | +0.23% | -0.35% | +0.23% |
| bitr | 1 | 2026-09-12T21:48:24 | loss | -708.83% | -708.83% | -708.83% |
| brm1 | 1 | 2026-09-12T21:48:24 | loss | -881.07% | -881.07% | -881.07% |
| brm2 | 1 | 2026-09-12T21:48:24 | loss | -173.30% | -173.30% | -173.30% |
| brm3 | 1 | 2026-09-12T21:48:24 | loss | -487.56% | -487.56% | -487.56% |
| ceildiv | 1 | 2026-09-12T21:48:24 | loss | -3.60% | -3.60% | -3.60% |
| cltz | 1 | 2026-09-12T21:48:24 | loss | -150.97% | -150.97% | -150.97% |
| dgcd | 1 | 2026-09-12T21:48:24 | loss | -69.90% | -69.90% | -69.90% |
| div | 4 | 2026-09-12T00:11:52 | loss | -0.13% | -35.72% | +0.15% |
| divd | 1 | 2026-09-12T21:48:24 | loss | -130.69% | -130.69% | -130.69% |
| divm | 1 | 2026-09-12T21:48:24 | loss | -1.11% | -1.11% | -1.11% |
| divpow2 | 1 | 2026-09-12T21:48:24 | loss | -159.16% | -159.16% | -159.16% |
| divv | 1 | 2026-09-12T21:48:24 | win | +0.40% | +0.40% | +0.40% |
| fib | 2 | 2026-09-12T00:11:52 | loss | -0.54% | -0.54% | +2.31% |
| ilp | 1 | 2026-09-12T21:48:24 | win | +16.01% | +16.01% | +16.01% |
| loopinv | 1 | 2026-09-12T21:48:24 | loss | -566.38% | -566.38% | -566.38% |
| madd | 1 | 2026-09-12T21:48:24 | win | +0.81% | +0.81% | +0.81% |
| mixop | 1 | 2026-09-12T21:48:24 | loss | -574.55% | -574.55% | -574.55% |
| mul13 | 4 | 2026-09-12T00:11:52 | win | +0.32% | -7.52% | +1.26% |
| mulc | 1 | 2026-09-12T21:48:24 | win | +0.09% | +0.09% | +0.09% |
| mulh | 1 | 2026-09-12T21:48:24 | loss | -265.11% | -265.11% | -265.11% |
| nest | 4 | 2026-09-12T00:11:52 | loss | -1.38% | -44.04% | -1.38% |
| nest3d | 1 | 2026-09-12T21:48:24 | win | +0.06% | +0.06% | +0.06% |
| popc | 1 | 2026-09-12T21:48:24 | loss | -174.48% | -174.48% | -174.48% |
| powmod | 1 | 2026-09-12T21:48:24 | loss | -22.13% | -22.13% | -22.13% |
| regp | 1 | 2026-09-12T21:48:24 | loss | -0.32% | -0.32% | -0.32% |
| satadd | 1 | 2026-09-12T21:48:24 | loss | -177.47% | -177.47% | -177.47% |
| sred1 | 1 | 2026-09-12T21:48:24 | loss | -31.27% | -31.27% | -31.27% |
| startup | 2 | 2026-09-12T00:11:52 | loss | -4.26% | -4.38% | -4.26% |
| stride3 | 1 | 2026-09-12T21:48:24 | loss | -2.07% | -2.07% | -2.07% |
| sum | 2 | 2026-09-12T00:11:52 | loss | -2.45% | -2.95% | -2.45% |
| unroll | 1 | 2026-09-12T21:48:24 | loss | -747.68% | -747.68% | -747.68% |
| upbranch | 4 | 2026-09-12T00:11:52 | loss | -6.62% | -24.09% | -6.62% |
| xsft | 1 | 2026-09-12T21:48:24 | loss | -86.99% | -86.99% | -86.99% |
| zerotrip | 4 | 2026-09-12T00:11:52 | win | +0.15% | -120.32% | +0.15% |
