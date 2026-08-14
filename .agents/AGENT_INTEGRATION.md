# Idol agent integration

This is a durable client setup guide. It contains no language law, live claims,
tool census, or current gate status.

## Repository servers

The version-locked MCP implementations live in this repository:

| Physical server name | Entry point | Purpose |
|---|---|---|
| `idol-bench` | `tools/mcp/bench.id` | claims, gaps, serialized gates, performance evidence |
| `idol-lsp` | `tools/mcp/lsp.id` | diagnostics and language intelligence |
| `zls` | `tools/mcp/zls.id` | Zig bootstrap navigation |

The physical `duo` executable, `duo-*` server names, and `duo_*` MCP tool names
are legacy aliases registered beside `idol_*` on the same servers. Prefer
`idol-bench`, `idol-lsp`, and `idol_*` tools in new client configuration.
The current `.id` server entrypoints are executed bootstrap/compatibility
transport; their suffix alone proves neither canonicality nor self-hosting
authority transfer. Historical `.id` paths are migration provenance. None of
those transport or historical spellings names the language, authorizes new
`.id`, or establishes a second current project brand. Historical
`~/x/duo-mcp` and `~/x/duo-lsp` checkouts are not canonical implementations.

## Client shape

Clients run the in-tree bootstrap executable with the repository as cwd. The
one client-neutral physical manifest is `tools/node/dev/mcp.manifest.json`; run
`tools/node/dev/generate-configs` to derive absolute client projections from the
actual clone path. Generated client configurations are projections, not
additional manifest authorities.

The generated Codex shape is:

```toml
[mcp_servers.idol-bench]
command = "<repo>/zig-out/bin/idol"
args = ["run", "<repo>/tools/mcp/bench.id"]
cwd = "<repo>"
env = { IDOL_ROOT = "<repo>", IDOL_BIN = "<repo>/zig-out/bin/idol", DUO_ROOT = "<repo>", DUO_BIN = "<repo>/zig-out/bin/idol" }
startup_timeout_sec = 60
tool_timeout_sec = 1800
required = true
```

`idol-lsp` and `zls` use the same command, cwd, and environment pattern with
their own entry points. Keep the pinned Zig and ZLS directories in `PATH` for
desktop and IDE launches.

Do not copy tool counts into documentation. `zig build mcp-gate` obtains and
checks the current tool lists through real JSON-RPC requests.

## Session protocol

1. Start at `AGENTS.md` and `.agents/AGENT_CANONICAL.md`.
2. Use skill **`idol-dev`** (`.pi/skills/idol-dev`).
3. Call session start on the bench MCP server.
4. Inspect current HEAD, dirty state, recent commits, live claim files,
   every current `gaps/GAP-*.md`, the verified `docs/bootstrap.md` frontier,
   and stash state.
5. Treat the session-start gap summary as incomplete until `GAP-131` closes.
6. Claim exact paths before editing.
7. Delegate only bounded independent work with disjoint write ownership.
8. Serialize heavy gates through the repository lock script.
9. Commit explicit pathspecs and release only claims owned by the session.

## Validation

Run setup evidence from the repository root:

```text
repo="$(git rev-parse --show-toplevel)"
codex --strict-config doctor
codex mcp list
"$repo/zig-out/bin/idol" run "$repo/scripts/idol_lock.id" -- zig build mcp-gate
```

The absolute bootstrap paths avoid the current relative-executable discovery
failure. The first two commands validate client configuration. The locked MCP
gate validates the actual repository handlers. A client listing tools without
exercising the handlers is not MCP health evidence.
