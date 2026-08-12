# MCP transport law (tools/mcp projection)

**No universal namespace anywhere** in MCP servers, gates, or shared helpers.

Use layout-projected homes and worlds:

```id
os.env["DUO_ROOT"]
fs:read_file(path)
json:encode(value)
mcp:register_tool(...)
capture(cmd)   # bootstrap @c.emit in shared.id only
```

Host/world law: `docs/spec/world.md`, `docs/spec/host.md`, GAP-157.

Do not copy historical namespace dispatch from comments or deleted code.
