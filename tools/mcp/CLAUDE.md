# duo-mcp — MCP servers for Duo

MCP servers implemented in **pure Duo** (not Zig). Depends on the `duo` compiler binary from `~/x/duo`.

## Dependency

Build duo first if the binary doesn't exist:
```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast
# Binary lands at ~/x/duo/zig-out/bin/duo
```

`duo` must be on PATH or set `DUO_ROOT=~/x/duo`.

## Running the MCP servers

```bash
duo run duo_bench.duo   # bench/perf/build-gate MCP server
duo run duo_lsp.duo     # LSP intelligence + @comp.* catalog MCP server
duo run zls.duo         # Zig compiler source navigation (wraps zls subprocess)
```

## MCP config snippet (for Claude Desktop / claude_desktop_config.json)

```json
{
  "mcpServers": {
    "duo-bench": {
      "command": "duo",
      "args": ["run", "/Users/clp/x/duo-mcp/duo_bench.duo"],
      "env": { "DUO_ROOT": "/Users/clp/x/duo" }
    },
    "duo-lsp": {
      "command": "duo",
      "args": ["run", "/Users/clp/x/duo-mcp/duo_lsp.duo"],
      "env": { "DUO_ROOT": "/Users/clp/x/duo" }
    }
  }
}
```

## Files

```
duo_bench.duo   Benchmark, build gate, perf audit, agent coordination server
duo_lsp.duo     Language intelligence, @comp.* catalog, diagnostics server
zls.duo         Zig source navigation server (bridges zls subprocess)
lib/            Shared Duo library code
vendor → ~/x/duo/lib   Symlink to duo stdlib
```
