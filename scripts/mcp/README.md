# MCP servers — canonical implementation in `~/x/duo-mcp/`

All Duo MCP servers are implemented in **pure Duo** and live canonically in
`/Users/clp/x/duo-mcp/`:

| Server | Entry point |
| --- | --- |
| duo-bench | `/Users/clp/x/duo-mcp/duo_bench.duo` |
| duo-lsp | `/Users/clp/x/duo-mcp/duo_lsp.duo` |
| zls | `/Users/clp/x/duo-mcp/zls.duo` |
| shared tool impl | `/Users/clp/x/duo-mcp/duo_shared.duo` |

Run them from the Duo repo root (`cd /Users/clp/x/duo`):

```sh
duo run /Users/clp/x/duo-mcp/duo_bench.duo
duo run /Users/clp/x/duo-mcp/duo_lsp.duo
duo run /Users/clp/x/duo-mcp/zls.duo
```

See `/Users/clp/x/duo-mcp/README.md` and `.agents/AGENT_INTEGRATION.md`.
