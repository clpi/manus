| field | value |
|---|---|
| title | MCP transport law (tools/mcp projection) |

| # | directive |
|---|---|
| 1 | **No universal namespace anywhere** in MCP servers, gates, or shared helpers. |

| # | directive |
|---|---|
| 1 | Use layout-projected homes and worlds: |

```id
root = os.env["IDOL_ROOT"]
content = path:read()
encoded = value:encode(json)
mcp:register_tool(...)
result = command:run()
instant = clock:now()
civil = instant:utc()
```

| # | directive |
|---|---|
| 1 | Host/world law: `docs/spec/world.md`, `docs/spec/host.md`, GAP-157. |

| # | directive |
|---|---|
| 1 | Do not copy historical namespace dispatch from comments or deleted code. |
| 2 | Do not use `@c.*`, `tostring`, `os.time`, `os.date`, or `..` in MCP source. |
