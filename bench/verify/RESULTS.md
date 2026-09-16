| field | value |
|---|---|
| title | Optimization verification results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-15T22:12:14 by `bench/verify/verify.py` (platform arm64-macos, seeds=30, full=False). |

| # | directive |
|---|---|
| 1 | Policy: every mismatch is a compiler bug report. |
| 2 | Cases tagged EXPECTED-ADVERSARIAL were designed to defeat a specific optimization; their mismatch confirms the suspected unsoundness. |

| opt | cases | pass | mismatch | build_fail | hang |
|---|---|---|---|---|---|
| fold | 79 | 78 | 1 | 0 | 0 |
| simp | 57 | 52 | 5 | 0 | 0 |
| imm | 77 | 67 | 10 | 0 | 0 |
| mulred | 91 | 84 | 7 | 0 | 0 |
| countdown | 44 | 43 | 1 | 0 | 0 |
| copy | 41 | 41 | 0 | 0 | 0 |
| div | 73 | 73 | 0 | 0 | 0 |
| nest | 42 | 42 | 0 | 0 | 0 |

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
| 1 | [mismatch] simp/r0014: byte 1: idol exit 40 != clang exit 39 |

| # | directive |
|---|---|
| 1 | [mismatch] simp/r0020: byte 1: idol exit 179 != clang exit 178 |

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
| 1 | [mismatch] imm/r0011: byte 1: idol exit 0 != clang exit 255 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0012: byte 1: idol exit 240 != clang exit 239 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0016: byte 1: idol exit 10 != clang exit 9 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0019: byte 1: idol exit 0 != clang exit 255 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0022: byte 1: idol exit 241 != clang exit 240 |

| # | directive |
|---|---|
| 1 | [mismatch] imm/r0027: byte 1: idol exit 1 != clang exit 0 |

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
| 1 | [mismatch] mulred/r0012: byte 1: idol exit 59 != clang exit 58 |

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
