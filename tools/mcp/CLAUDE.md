# MCP transport law (tools/mcp projection)

**No universal namespace anywhere** in MCP servers, gates, or shared helpers.

Use layout-projected homes and worlds:

```id
root = os.env("IDOL_ROOT")
content = path:read()
encoded = value:encode(json)
mcp:register_tool(...)
result = command:run()
instant = clock:now()
civil = instant:utc()
```

Host/world law: `docs/spec/world.md`, `docs/spec/host.md`, GAP-157.

Do not copy historical namespace dispatch from comments or deleted code.
Do not use `@c.*`, `tostring`, `os.time`, `os.date`, or `..` in MCP source.
