# Release Process

**Status:** Supported outline. **Audience:** maintainers.

## Pre-release checklist

1. **Build gate:** `zig build test` — all unit, compile-fail, and benchmark tests pass
2. **Performance:** `zig build bench` — Duo ≥ C on all 40 benchmarks (1% slack)
3. **Public safety (Pass 10 A19):** `./scripts/public_safety_scan.sh` — no secrets, suspicious paths, or missing LICENSE
4. **Documentation:** [README.md](../README.md), [docs/language.md](language.md), [docs/compiler.md](compiler.md) commands verified
5. **Examples:** `./zig-out/bin/duo run scripts/agent_smoke.duo`
6. **Catalog truth:** `duo catalog | jq '.pass10.readiness_summary'` — review open blockers

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

GitHub Actions: `.github/workflows/ci.yml` — build, test, benchmark on pinned Zig.
