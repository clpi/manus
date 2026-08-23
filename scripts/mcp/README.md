# MCP servers — in-tree implementation

Project MCP servers live under **`tools/mcp/`** and are declared in
**`tools/node/dev/mcp.manifest.json`**. The pre-rename project identity is
fully retired; every server, tool, and environment key is `idol`-named only.

| Server | Entry | State | Purpose |
|---|---|---|---|
| `idol` | `tools/mcp/native.id` | enabled, required | repository status, head, orient (native backend, `idol run`) |
| `idol-native` | exact `IDOL_NATIVE_ROOT`, `tools/mcp/server.id` | enabled | semantic graph: `check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`, `explain`, `fmt`, `asm` |

Run the enabled servers from the repository root:

```sh
export IDOL_ROOT="$(git rev-parse --show-toplevel)"
export IDOL_BIN="$IDOL_ROOT/zig-out/bin/idol"
"$IDOL_BIN" run "$IDOL_ROOT/tools/mcp/native.id"
```

The `idol-native` server is admitted only from the exact clean revision, tree,
entry, artifact, and authority projection recorded in the manifest:

```sh
export IDOL_NATIVE_ROOT=/absolute/path/to/idol-native
export IDOL_PAIR_COMPILER="$PWD/zig-out/bin/idol"
./tools/node/dev/mcp-pair launch tools/node/dev/mcp.manifest.json idol-native
```

There is no inferred sibling path. The launcher validates the explicit root,
forms a private exact checkout, cold-compiles its entry with current Idol, and
publishes the protected native artifact to the server as `IDOL_BIN`.

Editor language intelligence for `.id` files is the idol-native LSP
(`tools/lsp/launch.sh` in that tree), proven by its framed-traffic test.

Generate client configs (Codex, Cursor, OpenCode, skills):

```sh
IDOL_NATIVE_ROOT=/absolute/path/to/idol-native ./tools/node/dev/generate-configs
```

Integration gate (production JSON-RPC plus damage controls):

```sh
IDOL_NATIVE_ROOT=/absolute/path/to/idol-native ./tools/node/dev/mcp-gate
```

See `.agents/AGENT_INTEGRATION.md` and `tools/node/dev/README.md`.
