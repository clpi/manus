# Contributing to Duo

**Status:** Supported. **Audience:** contributors.

## Prerequisites

- **Zig 0.17.0-dev** (nightly; see CI pin)
- **`clang`** on `$PATH` (runtime C compilation)
- Optional: `lua` ≥5.4, `luajit` for `zig build cross-bench`

## Build and test

```bash
zig build
zig build unit-test          # fast Zig tests
zig build test               # full gate (includes compile-fail + bench)
./zig-out/bin/duo run scripts/agent_smoke.duo
```

Performance-sensitive changes: read and update [docs/performance.md](performance.md); run `zig build bench`.

## Code conventions

- Zig: `snake_case`, single-file modules, `pub` API surface — see [CLAUDE.md](../CLAUDE.md)
- Duo stdlib: [docs/src/idiomatic_duo.md](src/idiomatic_duo.md), [AGENTS.md](../AGENTS.md) grammar table
- Typed paths must not introduce `lua_Value` on hot paths

## Agent / parallel development

Multiple agents may work concurrently. Before editing shared surfaces:

1. Read [.agents/AGENT_COORDINATION.md](../.agents/AGENT_COORDINATION.md) and claim your area
2. Use `scripts/duo_lock.sh` for builds when other agents are active
3. Never `git stash` — commit early on a branch or coordinate via visible patches

## Pull requests

- `zig build test` must pass
- No benchmark regressions (`zig build bench`)
- Pass 10: every new file needs a durable role; prefer extending canonical modules over new parallel docs

## Companion repositories

| Repo | Role |
| --- | --- |
| duo-lsp | Language Server Protocol |
| duo-mcp | MCP tools for agents and IDE integration |

These live outside this tree; paths in agent docs use `~/x/duo-lsp` and `~/x/duo-mcp` as conventions for maintainers.
