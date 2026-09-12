# Duo Agent Coordination Buffer (redirect)

| # | directive |
|---|---|
| 1 | **Canonical location:** [`.agents/AGENT_COORDINATION.md`](.agents/AGENT_COORDINATION.md) |

| # | directive |
|---|---|
| 1 | **Alignment compass (read first):** [`docs/AGENT_ALIGNMENT.md`](AGENT_ALIGNMENT.md) |

| # | directive |
|---|---|
| 1 | This file redirects to the canonical location in `.agents/`. |

## For agents:
- Read via MCP `duo_coordination_read()` / `duo_coordination_buffer()`
- Update via MCP `duo_coordination_update(action="claim", agent_id, detail, files)`
- Claims, build tiers, session log, gap findings, delegation, and hooks

## For gaps specifically:
- Canonical section: [`.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer`](.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer)
- Read via MCP `duo_agent_gaps_read()` / `duo_agent_gaps_buffer`
- Update via MCP `duo_agent_gaps_update(action="open|close", ...)`