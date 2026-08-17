# MCP servers — in-tree implementation

Project MCP servers live under **`tools/mcp/`** and are declared in
**`tools/node/dev/mcp.manifest.json`**. The pre-rename project identity is
fully retired; every server, tool, and environment key is `idol`-named only.

| Server | Entry | State | Purpose |
|---|---|---|---|
| `idol` | `tools/mcp/native.id` | enabled, required | repository status, head, orient (native backend, `idol run`) |
| `idol-native` | sibling `idol-native` repo, `tools/mcp/server.id` | enabled | semantic graph: `check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`, `explain`, `fmt`, `asm` |

Run the enabled servers from the repository root:

```sh
export IDOL_ROOT="$(git rev-parse --show-toplevel)"
export IDOL_BIN="$IDOL_ROOT/zig-out/bin/idol"
"$IDOL_BIN" run "$IDOL_ROOT/tools/mcp/native.id"
```

The `idol-native` server runs from its own checkout with its own binary:

```sh
cd ../idol-native
./bin/idol run tools/mcp/server.id
```

Editor language intelligence for `.id` files is the idol-native LSP
(`tools/lsp/launch.sh` in that tree), proven by its framed-traffic test.

Generate client configs (Codex, Cursor, OpenCode, skills):

```sh
./tools/node/dev/generate-configs
```

Integration gate (production JSON-RPC plus damage controls):

```sh
./tools/node/dev/mcp-gate
```

See `.agents/AGENT_INTEGRATION.md` and `tools/node/dev/README.md`.
