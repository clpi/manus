# Idol MCP Tool Discovery

This file intentionally contains no static tool census or copied schemas.
Discover the exact current surface through MCP `tools/list`; validate it with
the locked `mcp-gate`.

The current project server exposes exactly the manifest-gated orientation
operations `status`, `head`, `orient`, plus the GAP-120 `concept` tool whose
production contract is held by `tools/concept/tool.sh` and `gate/mcp.sh`. The
sibling `idol-native` server owns its separately gated compiler and LSP
queries. There are no `duo_*` aliases and no hidden benchmark, claim, build,
gap, or zls tools.

`concept` is not a separate command: it is the served arm of the produced
concept finding. `idol` makes `idol explain` available as a CLI; the MCP
`concept` tool is the same projection exposed as a tool. Its input schema is
`{"file": "<subject .id>"}`; its output is the rendered verdict (REFUSED
with the produced reason or HELD one concept) carried as `result.content
[0].text` exactly as `gate/mcp.sh` holds for `tools/concept/tool.sh`.

Claims, gap reservations, and locked execution are explicit repository
commands. Do not reintroduce them through raw JSON substring dispatch or model
their outcomes as successful text payloads.

MCP does not own semantics. It projects graph identity, facts, demand,
realization, provenance, evidence, and current repository state. It must fail
closed when a projection cannot be produced.

No tool or example may teach universal namespace dispatch as native meaning.
Package location is provenance, relations are identity, subjects orient
application, worlds grant authority, and realization selects physical
implementation with zero runtime catalog obligation for sealed programs.
