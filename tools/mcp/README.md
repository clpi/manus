# Idsem MCP Bootstrap

These servers are physical compatibility transports for current repository
coordination, evidence, and semantic projections. The `duo-*` server names and
`.duo` implementation files are historical bootstrap identities; they do not
name the language or authorize new historical source.

Start at [`AGENTS.md`](../../AGENTS.md). Configure the servers through
[`.agents/AGENT_INTEGRATION.md`](../../.agents/AGENT_INTEGRATION.md), discover
their current schemas with MCP `tools/list`, and read executed compiler
ownership from [`docs/bootstrap.md`](../../docs/bootstrap.md).

`std` is migration distribution, not a semantic namespace. Existing direct
`std.*` calls in these transports are deletion-gated physical debt. Do not copy,
expand, document, or generate them as canonical Idsem. New capability begins
with the relation, subject, world, facts, outcome, evidence, and realization;
missing vocabulary blocks instead of creating a helper root.

Run the exact serialized MCP gate after changes:

```bash
./zig-out/bin/duo run scripts/duo_lock.duo -- zig build mcp-gate
```

The gate must prove handshake, schema/value agreement, truthful session state,
claim exclusion, inner failure propagation, and current routing. A server
starting or listing tools is not sufficient evidence.
