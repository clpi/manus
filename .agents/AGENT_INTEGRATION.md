# Idsem agent integration

This is a durable client setup guide. It contains no language law, live claims,
tool census, or current gate status.

## Repository servers

The version-locked MCP implementations live in this repository:

| Physical server name | Entry point | Purpose |
|---|---|---|
| `duo-bench` | `tools/mcp/duo_bench.duo` | claims, gaps, serialized gates, performance evidence |
| `duo-lsp` | `tools/mcp/duo_lsp.duo` | diagnostics and language intelligence |
| `zls` | `tools/mcp/zls.duo` | Zig bootstrap navigation |

The `duo-*` names and `.duo` entry paths are current bootstrap compatibility
identities. They do not name the language, authorize new `.duo`, or establish a
second current project brand. Historical `~/x/duo-mcp` and `~/x/duo-lsp`
checkouts are not canonical implementations.

## Client shape

Clients run the in-tree bootstrap executable with the repository as cwd. The
physical configuration remains:

```toml
[mcp_servers.duo-bench]
command = "/Users/clp/x/duo/zig-out/bin/duo"
args = ["run", "/Users/clp/x/duo/tools/mcp/duo_bench.duo"]
cwd = "/Users/clp/x/duo"
env = { DUO_ROOT = "/Users/clp/x/duo", DUO_BIN = "/Users/clp/x/duo/zig-out/bin/duo" }
startup_timeout_sec = 60
tool_timeout_sec = 1800
required = true
```

`duo-lsp` and `zls` use the same command, cwd, and environment pattern with
their own entry points. Keep the pinned Zig and ZLS directories in `PATH` for
desktop and IDE launches.

Do not copy tool counts into documentation. `zig build mcp-gate` obtains and
checks the current tool lists through real JSON-RPC requests.

## Session protocol

1. Start at `AGENTS.md` and `.agents/AGENT_CANONICAL.md`.
2. Call `duo_agent_session_start`.
3. Inspect current HEAD, dirty state, recent commits, live claims, gap files,
   and stash state.
4. Treat the session-start P0 count as incomplete until `GAP-131` closes.
5. Claim exact paths through `duo_dev_claim_acquire`.
6. Delegate only bounded independent work with disjoint write ownership.
7. Serialize heavy gates through `scripts/duo_lock.duo`.
8. Commit explicit pathspecs and release only claims owned by the session.

## Validation

Run setup evidence from the repository root:

```text
codex --strict-config doctor
codex mcp list
./zig-out/bin/duo run scripts/duo_lock.duo -- zig build mcp-gate
```

The first two commands validate client configuration. The locked gate validates
the actual repository handlers. A client listing tools without exercising the
handlers is not MCP health evidence.
