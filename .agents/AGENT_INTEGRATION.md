# Duo Agent Integration Guide

This file documents how ALL AI agent CLIs are configured to work on the Duo project
simultaneously without conflicting, duplicating, or colliding.

## Configured Agents

The following agents are installed and configured with Duo-native MCP servers:

| Agent | Binary | MCP Config | Status |
|-------|--------|------------|--------|
| Hermes | `hermes` | `~/.hermes/config.yaml` | ✅ duo-lsp, duo-bench, zls |
| Claude Code | `claude` | `~/.claude.json` | ✅ duo-lsp, duo-bench, zls |
| Codex | `codex` | `~/.codex/config.toml` | ✅ duo-lsp, duo-bench, zls |
| Cursor | `cursor` | `~/.cursor/mcp.json` | ✅ (cleaned + Duo MCPs) |
| Kiro | `kiro` | `~/.kiro/settings/mcp.json` | ✅ (cleaned + Duo MCPs) |
| Trae | `trae` | `~/Library/.../mcp.json` | ✅ (cleaned) |
| Windsurf | `windsurf` | `~/.codeium/windsurf/mcp_config.json` | ✅ (cleaned) |
| Agy/Gemini | `agy` | `~/.gemini/config/mcp_config.json` | ✅ (cleaned + Duo MCPs) |
| OpenCode | `opencode` | `~/.config/opencode/opencode.jsonc` | ✅ (no MCP needed) |
| Devin | `devin` / `devin-cli` | `~/.local/share/devin/` | ✅ (no MCP, uses own tools) |
| Junie | `junie` | `~/.junie/` | ✅ (no MCP configured) |
| Pool | `pool` | `~/.config/poolside/pool.json` | ✅ (ACP, no MCP) |
| Kimi Code | `kimi` | `~/.kimi/config.toml` | ✅ installed via `sudo npm install -g kimi-code --allow-scripts=keytar`; binary at `/Users/clp/.local/share/mise/installs/node/26.4.0/bin/kimi`; invoke as `kimi` |
| Oh-My-Pi | `oh-my-pi` | npm global | ✅ (installed) |
| Kilo Code | `kilo` | `~/.config/kilo/` | ✅ (installed, no MCP needed) |

## MCP Servers (Duo-Native)

All agents share the same 3 MCP servers via stdio (no HTTP, no browser tabs, no OAuth):

1. **duo-lsp** (`/Users/clp/x/duo-mcp/duo_lsp.duo`)
   - `duo_diagnostics` — compiler diagnostics
   - `duo_compile_check` — run `duo check`
   - `duo_meta_catalog` — all 100+ @meta.* constructs
   - `duo_meta_ladder` — scaling ladder O(types) → O(n!)
   - `duo_language_features` — syntax, types, directives, AI/ML
   - `duo_coordination_buffer` — read coordination buffer
   - `duo_agent_gaps_buffer` — read canonical coordination buffer gap section
   - `duo_agent_canonical_index` — single router (`.agents/AGENT_CANONICAL.md`)

2. **duo-bench** (`/Users/clp/x/duo-mcp/duo_bench.duo`)
   - `duo_agent_session_start` — **call at every session start**
   - `duo_agent_canonical_index` — canonical file router
   - `duo_agent_delegate` — update gaps delegation queue
   - `duo_agent_smoke` — tier-0 agent gate (parallel-safe)
   - `duo_audit_native_boxing` — scan codegen for lua boxing (G-001)
   - `duo_bench_run` — run benchmarks with structured JSON output
   - `duo_bench_regressions` — detect performance regressions
   - `duo_perf_ledger` — read performance ledger
   - `duo_perf_gaps` — list open performance gaps
   - `duo_build_run` — build/test/unit-test/fmt-check gates
   - `duo_coordination_read` / `duo_coordination_update` — coordination buffer
   - `duo_agent_gaps_read` / `duo_agent_gaps_update` — canonical coordination buffer gap section
   - `duo_embed_symbols` — symbol-level keyword/vector search over compiler + stdlib (builds `docs/symbol_index.json`)
   - `duo_cross_lang_meta` — guide for injecting Duo @comp.* exponential metaprogramming from any host language
   - `duo_file_finding` — file a bug/exponential_opportunity/ergonomic_gap/regression to the coordination buffer
   - `duo_exponential_eval` — input Duo code, output metaprogramming-enhanced + optimized Duo

3. **zls** (`/Users/clp/x/duo-mcp/zls.duo`)
   - `zig_hover`, `zig_definition`, `zig_references`, `zig_completions`
   - `zig_diagnostics`, `zig_document_symbols`
   - `zig_format`, `zig_ast_check`

## Coordination Protocol (ALL Agents Must Follow)

1. **At session start:** Call `duo_agent_session_start` (duo-bench MCP); read `.agents/AGENT_CANONICAL.md`
2. **Before editing files:** Claim files via `duo_coordination_update(action="claim")`
3. **Before building:** Check `duo run scripts/duo_lock.duo status` — serialize builds
4. **After benchmark changes:** Append to `docs/performance.md`
5. **When discovering gaps:** write a new `gaps/GAP-0NN.md` — check the directory first, numbers collide across sessions
6. **After finishing:** Release claims via `duo_coordination_update(action="release")`

## Build Safety (Prevents Machine Freeze)

ALL builds must run under `scripts/duo_lock.duo`:
```
duo run scripts/duo_lock.duo -- ./zig-out/bin/duo run scripts/agent_smoke.duo   # tier-0
duo run scripts/duo_lock.duo -- zig build unit-test --summary all     # tier-1
duo run scripts/duo_lock.duo -- zig build bench                       # tier-3 (claim perf row first!)
```

## Duo as Scripting Language

Use `std.script` for repo tooling instead of bash/python:
```duo
s = req("std.script")
s.echo("Building...")
s.locked_must("zig build")
s.must("./zig-out/bin/duo run examples/hello.duo")
output = s.capture("zig build bench 2>&1 | head -20")
```

Path manipulation (ergonomic vs Python):
```duo
s = req("std.script")
full = s.path_join("lib/std", "string.duo")     -- "lib/std/string.duo"
base = s.path_basename(full)                      -- "string.duo"
dir = s.path_dirname(full)                        -- "lib/std"
ext = s.path_ext(full)                            -- ".duo"
stem = s.path_stem(full)                           -- "string"
```

File operations:
```duo
s = req("std.script")
if s.fs_exists("build.zig") then s.echo("found") end
content = s.fs_read("src/main.zig")
s.fs_write("/tmp/test.txt", "hello")
tmp = s.fs_tmp()
```

## Removed MCP Servers (Do NOT Re-Add)

These were removed from ALL agent configs to prevent browser tabs, OAuth flows,
and machine freezes:

- **OAuth (opened browser tabs):** canva, google-calendar, linear, neon, notion, supabase, vercel
- **mcp-remote bridges (opened browser for OAuth):** all cloudflare-*, tinybird, gen-pdf, wpcom-mcp
- **Browser-opening:** playwright, chrome-devtools-mcp
- **Redundant with Hermes/native tools:** fetch, filesystem, fs, memory, sequential-thinking, time, github
- **Irrelevant SaaS:** stripe, postman, railway-mcp-server, task_master, mcp-docs, GitKraken, etc.
