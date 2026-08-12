# MCP servers — canonical implementation in sibling `duo-mcp` repo

All Duo MCP servers are implemented in **pure Duo** and live in the **duo-mcp**
companion repository (sibling to this repo under the same parent directory).

| Server | Entry point |
| --- | --- |
| duo-bench | `duo-mcp/duo_bench.id` |
| duo-lsp | `duo-mcp/duo_lsp.id` |
| zls | `duo-mcp/zls.id` |
| shared tool impl | `duo-mcp/duo_shared.id` |

Run them from the Duo repo root (set `DUO_ROOT` to this checkout):

```sh
export DUO_ROOT="$(pwd)"
duo run "$DUO_ROOT/../duo-mcp/duo_bench.id"
duo run "$DUO_ROOT/../duo-mcp/duo_lsp.id"
duo run "$DUO_ROOT/../duo-mcp/zls.id"
```

See `duo-mcp/README.md` (in the companion repo) and `.agents/AGENT_INTEGRATION.md`.
