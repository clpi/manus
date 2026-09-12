| field | value |
|---|---|
| title | Duo Agent Coordination Buffer (redirect) |
| canonical location | [](.agents/AGENT_COORDINATION.md) |
| alignment compass (read first) | [](AGENT_ALIGNMENT.md) |

| # | directive |
|---|---|
| 1 | This file redirects to the canonical location in `.agents/`. |

| section |
|---|---|
| For agents: |

| # | directive |
|---|---|
| 1 | Read via MCP `duo_coordination_read()` / `duo_coordination_buffer()` |
| 2 | Update via MCP `duo_coordination_update(action="claim", agent_id, detail, files)` |
| 3 | Claims, build tiers, session log, gap findings, delegation, and hooks |

| section |
|---|---|
| For gaps specifically: |

| # | directive |
|---|---|
| 1 | Canonical section: [`.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer`](.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer) |
| 2 | Read via MCP `duo_agent_gaps_read()` / `duo_agent_gaps_buffer` |
| 3 | Update via MCP `duo_agent_gaps_update(action="open\|close", ...)` |
