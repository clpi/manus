# Integrated status at ce03c7eb — measured, not asserted

Revision: `ce03c7ebb6dc7469662096dd0f91cf09d903d77f`
Worktree: `/Volumes/d 1/lanes/integrated` (branch `lane/integrated-20260823`)
Host: Darwin-arm64, zig 0.17.0-dev.1770+5d7cf3f34
Compiler under test: `zig-out/bin/idol`, ReleaseFast (derived by `tools/node/dev/build-mode`),
sha256 `11c1898ce90cab161b7c36d225c0ff10bfe2acd3d6be7ec9e862d037ef1d8b8a`
Date measured: 2026-08-23

## 1. Builds

| command | exit | result |
|---|---|---|
| `zig build --summary all` (default, Debug) | 0 | `Build Summary: 5/5 steps succeeded` |
| `zig build -Doptimize=ReleaseFast --summary all` | 0 | `Build Summary: 5/5 steps succeeded` |
| `zig build unit-test --summary all` | 0 | `Build Summary: 3/3 steps succeeded; 1710/1710 tests passed` |

Build wiring is GREEN. Nothing below is a build-wiring failure.

## 2. The integrated aggregate — `zig build test`

`build.zig` has no step named aggregate/integration. `test` IS the aggregate:
13 `test_step.dependOn(...)` edges, one of which is the whole `agent-smoke` tier-0 step.

    ./tools/node/dev/idol-lock --timeout 3600 -- zig build test -Doptimize=ReleaseFast --summary all
    Build Summary: 22/31 steps succeeded (7 failed); 1710/1710 tests passed
    EXIT=1

**22/31** at ce03c7eb. (The previously circulated figure was 23/31.)

Seven failing commands, verbatim:

| # | failed command | first error line |
|---|---|---|
| 1 | `./zig-out/bin/idol run examples/demand/swap.id` | `error: direct backend: DNB001 application: unknown missing: ret-type:any consumer: native realization producer: dnir lower` |
| 2 | `./zig-out/bin/idol run examples/hash/agreement.id` | `error: direct backend: DNB001 application: unknown missing: ret-type:any consumer: native realization producer: dnir lower` |
| 3 | `./zig-out/bin/idol run --backend=direct gate/architecture.id` | `error: direct backend: DNB001 application: 259 relation: tally missing: concat consumer: native realization producer: dnir lower` (bail site `lowerConcatChain() at dnir_lower.zig:11278`) |
| 4 | `./zig-out/bin/idol run scripts/run_compile_fail_tests.id` | `error: direct backend: DNB001 application: unknown missing: runtime-global-call:tostring consumer: native realization producer: dnir lower` |
| 5 | `./zig-out/bin/idol run scripts/assert_no_ansi_reports.id` | `error: direct backend: DNB001 application: unknown missing: runtime-global-call:tostring consumer: native realization producer: dnir lower` |
| 6 | `./tools/node/dev/idol-lock -- ./zig-out/bin/idol run scripts/agent_smoke.id` | `agent-smoke: luahost FAIL` (root: `scripts/luahost.id` → `error: direct backend: DNB011 application: 18 relation: chomp missing: unresolved-application-facts consumer: native realization producer: graph`) |
| 7 | `./tools/node/dev/mcp-gate` | `probe-mcp: idol-native entry is unreadable: /Volumes/d 1/lanes/idol-native/tools/mcp/server.id` |

Rows 1–6 are genuine capability failures (direct-native subset holes).
Row 7 is environment: `tools/node/dev/mcp.manifest.json` declares a `"sibling": "idol-native"`
server; a lane worktree has no `../idol-native`.

## 3. Shell gates — `gate/*.sh`, each run individually

32 of 34 pass (excluding `gate/all.sh`, which is the runner).

Failing:

| gate | exit | first line |
|---|---|---|
| `gate/differential.sh` | 2 | `differential: shared outcome limiter absent at /Volumes/d 1/lanes/integrated/../idol-native/gate/run_limited.pl` |
| `gate/researchgap.sh` | 5 | `GAP-218.md: no **Kind:** declared — the research census cannot select its subject` (also 219, 220, 221, 222) — `gapc0: 49 GAPs in range, 21 research GAPs C0-checked, 5 violations` |

With `IDOL_NATIVE=/Volumes/d 1/x/idol-native` the differential gate exits 0, and prints:

    differential: selftest PASS — sibling-mirror null row, per-arm cwd, real row survives normalisation, one observation, comparator damage, zero-subject, signal and timeout controls
    differential: compiler comparison UNMEASURED — supply base and candidate

i.e. it passes without comparing two compilers.

## 4. Gates that cannot fail as invoked

| gate | evidence |
|---|---|
| `gate/architecture-roadmap.sh` | its own header: "Always exits 0"; prints 7 planned gates, asserts nothing |
| `gate/coverage.sh` | last line `gate/coverage.sh: reporting only (set COVERAGE_BUDGET to ratchet)`; `COVERAGE_BUDGET` is unset in `gate/all.sh` |
| `gate/attribution.sh` | `exit 0` unconditionally unless `ATTRIBUTION_BUDGET` is set; `gate/all.sh` does not set it |
| `gate/differential.sh` | passes with the comparison UNMEASURED (above) |

`gate/attribution.sh` is the important one, because the census it prints while exiting 0 is:

    corpus 949   compile+run 117   refuse 441   timeout 0 (>60s)   unclassified 391 (nonzero exit, no diagnostic)

117 of 949 corpus `.id` files compile AND run.

## 5. Slow gates (wall clock, measured)

    attribution           182s
    layering-controls      57s
    vocabulary-controls    39s
    admission-controls     35s
    coverage               14s
    everything else       <=7s

`sh gate/all.sh` runs all 34 serially; attribution alone is ~3 minutes of it.

## 6. Crashes

No compiler panic, segfault, abort or `unreachable` was observed in any gate,
in `zig build test`, or in a sweep of every `.id` under
`examples native_differential lib scripts gate`. Every failure above is a clean
diagnostic refusal (`DNB001` / `DNB011`) with exit 1. Nonzero exits in the corpus
sweep are program answers (`examples/boring/fib.id` exits 109), not faults.

## 7. Where CI is

GitHub Actions is unavailable for this account — jobs are refused with
"The job was not started because recent account payments have failed".
That is a billing failure, not a code failure. Local measurement is the only signal.
