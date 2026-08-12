# Idol MCP Bootstrap

These servers are physical compatibility transports for current repository
coordination, evidence, and semantic projections. The `duo-*` server names and
historical `.id` source are bootstrap identities. Current `.id` entrypoints
still carry compatibility transport; their suffix alone is not canonicality or
self-host evidence.

Start at [`AGENTS.md`](../../AGENTS.md). Configure the servers through
[`.agents/AGENT_INTEGRATION.md`](../../.agents/AGENT_INTEGRATION.md), discover
their current schemas with MCP `tools/list`, and read executed compiler
ownership from [`docs/bootstrap.md`](../../docs/bootstrap.md).

No universal namespace in these transports. Existing namespace dispatch is
deletion-gated physical debt. Do not copy, expand, document, or generate it
as canonical Idol. New capability begins with relation, subject, world, facts,
outcome, evidence, and realization; missing vocabulary blocks instead of
creating a helper root.

Run the exact serialized MCP gate after changes:

```bash
repo="$(git rev-parse --show-toplevel)"
"$repo/zig-out/bin/idol" run --backend=c "$repo/scripts/duo_lock.id" -- zig build mcp-gate
```

The gate must prove handshake, schema/value agreement, truthful session state,
claim exclusion, and current routing. `GAP-146` keeps inner child-build outcome
propagation incomplete, so inspect inner output as well as wrapper status. A
server starting or listing tools is not sufficient evidence.
