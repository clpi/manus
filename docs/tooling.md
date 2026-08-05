# Duo Tooling

**Status:** Supported overview. **Audience:** users and contributors setting up editors, MCP, and CLI workflows.

## CLI (`duo`)

Built from this repo (`zig build` → `zig-out/bin/duo`).

| Command | Purpose |
| --- | --- |
| `compile`, `run`, `check` | Compile and execute Duo/Lua source |
| `dump-c` | Inspect generated C |
| `fmt` | Format `.duo` / `.lua` |
| `catalog` | Machine-readable JSON (passes, transforms, readiness matrices) |
| `explain` | Knowledge snapshots + optimization outcomes |
| `realize` | Realization planning + persistent evidence (partial) |
| `graph` | Semantic graph lift (partial) |
| `wasm-tables emit` | Regenerate `lib/std/wasm/opcode_lookup.duo` from `wasm_semantic.zig` |
| `algebra` | Pass 2 semantic algebra export |

See [docs/src/compiler_usage.md](src/compiler_usage.md) for full option list.

## Editor plugins (`ext/`)

| Editor | Path |
| --- | --- |
| VS Code | `ext/vscode-duo/` |
| Vim / Neovim | `ext/vim-duo/` |
| Helix | `ext/helix/` |
| Zed | `ext/zed-duo/` |

Tree-sitter grammar: `ext/tree-sitter-duo/`. LSP server: companion repo **duo-lsp** (Duo source).

## MCP (Model Context Protocol)

Companion repo **duo-mcp** exposes compiler/catalog/agent coordination tools for AI integrations. Not required for local development.

## Agent coordination (internal)

Parallel agent rules: [AGENTS.md](../AGENTS.md), [.agents/AGENT_COORDINATION.md](../.agents/AGENT_COORDINATION.md). **Not** part of the public architecture — contributors only.

## Validation scripts

| Script | Role |
| --- | --- |
| `scripts/agent_smoke.duo` | Tier-0 example smoke via `std.agent.smoke_targets()` + `public_safety_scan.sh` |
| `scripts/public_safety_scan.sh` | Pre-release secret/path scan (Pass 10 A19) |
| `scripts/run_compile_fail_tests.sh` | Compile-fail regression corpus |
| `scripts/duo_lock.sh` | Serialize parallel agent builds |

```bash
./zig-out/bin/duo run scripts/agent_smoke.duo
./scripts/public_safety_scan.sh
```
