# Bootstrap and Build

**Status:** Supported. **Audience:** contributors.

## What bootstraps what

| Component | Built with | Output |
| --- | --- | --- |
| Duo compiler | **Zig 0.17.0-dev** | `zig-out/bin/duo` |
| User programs | `duo compile` / `duo run` | Generated C → `clang` → native binary or WASM |
| Standard library | Compiled as part of user/embedded modules | Native C via same pipeline |
| Editor LSP | Duo (`ext/duo-lsp/`) | Separate build in companion repo |

There is **no** self-hosted Duo compiler yet. Zig is the canonical bootstrap chain.

## Minimum build

Requires **Zig 0.17.0-dev** and **`clang`** on `$PATH` (invoked at compile time).

```bash
git clone <repo>
cd duo
zig build
./zig-out/bin/duo run examples/benchmark.duo   # smoke
zig build test                                  # full gate (includes bench)
```

## Validation tiers

| Tier | Command | When |
| --- | --- | --- |
| Compiler build | `zig build` | Every change |
| Unit tests | `zig build unit-test` | Compiler modules |
| Full gate | `zig build test` | Before merge |
| Performance | `zig build bench` | Codegen / perf changes |
| Agent smokes | `duo run scripts/agent_smoke.duo` | Stdlib / example changes |

## Self-hosting direction

Goal: compiler subsets expressible in Duo, compiled by the current Zig-built `duo`. Tracked under Pass 4 native end-to-end — see [docs/plans/pass4_native_end_to_end.md](plans/pass4_native_end_to_end.md) (**partial**).
