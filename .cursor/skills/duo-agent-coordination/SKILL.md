---
name: duo-agent-coordination
description: Coordinate multi-agent work on the Duo compiler repo. Use at session start for every Duo task — reads canonical buffers, claims files, delegates gaps, runs build gates under duo_lock.sh. Works with Cursor, Claude, Codex, Devin, Kiro, Hermes, and other MCP-capable agents.
---

# Duo multi-agent coordination

## When to use

- Starting any session on the Duo repo (`/Users/clp/x/duo`)
- Before editing `src/codegen.zig`, `src/sema.zig`, `lib/std/*`, benchmarks, or docs buffers
- Before `zig build bench` or other heavy builds

## Canonical index

Read **`docs/AGENT_CANONICAL.md`** — single router. Do not create duplicate coordination files.

## Session start checklist

1. MCP: **`duo_agent_session_start(agent_id="cursor")`** (duo-bench server)
2. Read open **P0** rows in gaps buffer; claim matching work
3. **`duo_coordination_update(action="claim", agent_id=..., detail=..., files=...)`**
4. Verify: `scripts/duo_lock.sh -- zig build && zig build agent-smoke`

## MCP servers (stdio)

| Server | Script | Key tools |
| --- | --- | --- |
| duo-bench | `scripts/mcp/duo_bench_mcp.py` | `duo_agent_session_start`, `duo_coordination_*`, `duo_agent_gaps_*`, `duo_bench_run` |
| duo-lsp | `scripts/mcp/duo_lsp_mcp.py` | `duo_meta_catalog`, `duo_compile_check`, `duo_coordination_buffer` |

## Language priorities (after buffer read)

1. **No `lua_Value`** on typed/comptime paths — native C scalars/structs
2. **Exponential `@comp.*`** — prefer `@comp.derive.all` / `@comp.burst` over linear copies
3. **Zero benchmark regressions** — `zig build bench` only when holding perf claim

## Do not

- Duplicate `AGENT_COORDINATION.md` or `AGENT_GAPS.md` content in chat-only memory
- Run tier-3 bench in parallel with other agents
- Use public `@foo_bar` — use `@comp.foo.bar` dotted hierarchy only
