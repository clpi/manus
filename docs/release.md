# Release Process

**Status:** Supported outline. **Audience:** maintainers.

## Pre-release checklist

1. **Closure gate:** `zig build pass11-gate` — Pass 11 Profile A release proof
2. **Hygiene:** `zig build repo-hygiene` — no forbidden root artifacts
3. **Build gate:** `zig build test` — unit, compile-fail, agent-smoke
4. **Toolchain pin:** `bash scripts/ci_zig_version.sh` matches `.github/workflows/ci.yml` `ZIG_VERSION` and `build.zig.zon` `minimum_zig_version`
5. **Reproducibility (Pass 11):** `zig build reproducibility-smoke` — identical ReleaseFast compiler across clean rebuilds
6. **Direct backend (macOS AArch64):** `zig build pass11-direct-smoke` — `examples/pass11_record_proof.duo` via `--backend=direct`
7. **Pass 11 modules:** `zig build pass11-module-smoke` — barrier checks + target model + catalog tests (no duo binary)
8. **Byte blob object (macOS AArch64):** `zig build pass11-blob-object-smoke` — WP-05 Mach-O object from blob constants
9. **Performance:** `BENCH_BACKEND=c-specialized zig build bench` — honest benchmark profile (not forced boxing)
10. **Public safety (Pass 10 A19):** `./scripts/public_safety_scan.sh`
11. **Documentation:** [README.md](../README.md), [docs/compiler.md](compiler.md) claims match `duo catalog | jq '.pass11'`
12. **Examples:** `./zig-out/bin/duo run scripts/agent_smoke.duo`
13. **Catalog truth:** `duo catalog | jq '.pass11.readiness_summary'` and `.pass11.closure_status`

## Versioning

Follow git tags on `main`. Changelog: [CHANGELOG.md](../CHANGELOG.md) when present.

## Artifacts

| Artifact | Command |
| --- | --- |
| Compiler binary | `zig build` → `zig-out/bin/duo` |
| WASM module | `duo compile file.duo --target wasm32-wasi -o out.wasm` |
| Generated Wasm tables | `duo wasm-tables emit` → `lib/std/wasm/opcode_lookup.duo` |

Commit generated Wasm lookup tables when `wasm_semantic.zig` changes.

## Public readiness (Pass 10)

Release is blocked on critical items in `duo catalog → pass10.release_blockers` (secrets, licensing, broken instructions, misrepresented docs).

Historical pass plans under `docs/plans/` are **not** release-contract documentation — see [docs/plans/archive/](plans/archive/).

## CI

GitHub Actions: `.github/workflows/ci.yml`

| Job | Purpose |
| --- | --- |
| `hygiene` | repo hygiene + public safety + Zig pin verification |
| `build` | pinned Zig build, unit tests, Pass 11 module smoke, Wasm smokes |
| `reproducibility` | Pass 11 WP-13 — dual ReleaseFast build hash compare (main only) |
| `pass11-direct` | direct ARM64 record proof + byte blob object smoke (macOS main only) |
| `bench` | `BENCH_BACKEND=c-specialized` performance gate (main only) |
| `release` | tagged release binaries |

Pin source of truth: `build.zig.zon` → `minimum_zig_version`, mirrored in CI `ZIG_VERSION` env and verified by `scripts/ci_zig_version.sh`.
