# MCP servers — in-tree implementation

Project MCP servers live under **`tools/mcp/`** and are declared in
**`tools/node/dev/mcp.manifest.json`**.

| Server | Entry | Purpose |
|---|---|---|
| `idol-bench` | `tools/mcp/bench.id` | claims, gaps, serialized gates, performance evidence |
| `idol-lsp` | `tools/mcp/lsp.id` | diagnostics and language intelligence |
| `zls` | `tools/mcp/zls.id` | Zig bootstrap navigation through zls |

Legacy **`duo-bench`** / **`duo-lsp`** / **`duo_*`** tool names are deleted; clients use **`idol_*`** only.

Run from the repository root:

```sh
export IDOL_ROOT="$(git rev-parse --show-toplevel)"
export IDOL_BIN="$IDOL_ROOT/zig-out/bin/idol"
"$IDOL_BIN" run "$IDOL_ROOT/tools/mcp/bench.id"
"$IDOL_BIN" run "$IDOL_ROOT/tools/mcp/lsp.id"
"$IDOL_BIN" run "$IDOL_ROOT/tools/mcp/zls.id"
```

Generate client configs:

```sh
./tools/node/dev/generate-configs
```

Integration gate (C emit compiles; full JSON-RPC round trip blocked until S0 runtime entry resolves):

```sh
zig build mcp-gate
```

See `.agents/AGENT_INTEGRATION.md` and `tools/node/dev/README.md`.
