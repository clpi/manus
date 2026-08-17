# Idol agent integration

This is a durable client setup guide. It contains no language law, live claims,
tool census, or current gate status.

## Canonical locations

- Development repository: `/Users/clp/x/idol` (worktree on the data volume,
  reached through the `~/x` symlink; dev remote `clpi/idol`).
- Native benchmark repository: `/Users/clp/x/idol-native` (remote
  `clpi/idol-native`, branch `main`) — owns the semantic-graph MCP server and
  the end-user `.id` language server.
- The pre-rename project identity is **fully retired**. Server names, tool
  names, environment keys, and skill names are `idol`-named only; no client
  configuration may reintroduce retired spellings.

## Repository servers

The version-locked MCP implementations are declared once by the
client-neutral `tools/node/dev/mcp.manifest.json`:

| Physical server name | Entry point | State | Purpose |
|---|---|---|---|
| `idol` | `tools/mcp/native.id` | enabled, required | status, head, orient |
| `idol-native` | sibling `idol-native` checkout, `tools/mcp/server.id` | enabled | `check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`, `explain`, `fmt`, `asm` |

A manifest entry with a `sibling` field resolves its root, entry, and launcher
binary against the sibling checkout of this clone. The retired pre-rename
transports (claims/bench, diagnostics, zls bridges) were removed, not
disabled: claims live in `.agents/session/claims/`, diagnostics and language
intelligence come from the `idol-native` server and its language server, and
Zig navigation uses the editor's own zls directly. Generated client
configurations are projections of the manifest, not additional authorities.

## Client shape

Clients run each server's own `idol` binary with the server's root as cwd.
Run `tools/node/dev/generate-configs` to derive absolute client projections
from the actual clone path (the generator emits the stable `~/x` spelling
when applicable). Projections:

- Codex: `.codex/mcp.generated.toml` plus a marked block in `~/.codex/config.toml`.
- Cursor: `.cursor/mcp.json`.
- OpenCode: `.opencode/opencode.json` (project) plus the managed `mcp` entries
  of `~/.config/opencode/opencode.jsonc`; user-owned keys are preserved.
- OpenCode skills: `.opencode/skills/{idol,idol-dev}` symlinks into
  `.pi/skills`, and the same skills synced to `~/.config/opencode/skills`.
- Claude Code: user-scope `mcpServers` in `~/.claude.json` (same servers;
  `sh -c` cd-wrappers because Claude has no cwd field).
- pi: `.pi/extensions/idol-mcp.ts` reads the same manifest and spawns the same
  entrypoints; `idol_mcp_status` reports health, `idol__<server>__<tool>`
  forwards calls.

The generated Codex shape is:

```toml
[mcp_servers.idol]
command = "<repo>/zig-out/bin/idol"
args = ["run", "--backend=native", "<repo>/tools/mcp/native.id"]
cwd = "<repo>"
startup_timeout_sec = 60
tool_timeout_sec = 1800
required = true

[mcp_servers.idol.env]
IDOL_ROOT = "<repo>"
IDOL_BIN = "<repo>/zig-out/bin/idol"
```

`idol-native` uses the same shape with its own root and `bin/idol` launcher.
Keep the pinned Zig and ZLS directories in `PATH` for desktop and IDE
launches.

## Skills and law routing

- Every agent starts at `AGENTS.md`; OpenCode additionally loads it through
  `instructions` in its global config.
- Skills `idol` and `idol-dev` live canonically in `.pi/skills`.
  `tools/node/dev/install-skills` installs them for Codex and Devin;
  `tools/node/dev/generate-configs` projects them for OpenCode (paths above).

## Editor language intelligence

The `.id` language server is the idol-native tree's `tools/lsp/launch.sh`
(Content-Length framing; diagnostics and symbols come from that tree's own
compiler and semantic graph — the transport adds no second authority). Wire
editors with `IDOL_BIN` pointing at `/Users/clp/x/idol-native/bin/idol`.
The in-repository `tools/lsp` projection remains bootstrap debt until its
source fits the direct-native subset.

## Session protocol

1. Start at `AGENTS.md` and `.agents/AGENT_CANONICAL.md`.
2. Use skill **`idol-dev`** (`.pi/skills/idol-dev`).
3. Orient: `tools/node/dev/orient`, or the `orient` tool on the `idol` server.
4. Inspect current HEAD, dirty state, recent commits, live claim files,
   every current `gaps/GAP-*.md`, and the verified `docs/bootstrap.md` frontier.
5. Treat the session-start gap summary as incomplete until `GAP-131` closes.
6. Claim exact paths before editing (`.agents/session/claims/`; claims minting
   is owned by the bench server while it is live, else durable claim files).
7. Delegate only bounded independent work with disjoint write ownership.
8. Serialize heavy gates through the repository lock script.
9. Commit explicit pathspecs and release only claims owned by the session.

## Validation

Run setup evidence from the repository root:

```text
repo="$(git rev-parse --show-toplevel)"
codex --strict-config doctor
codex mcp list
"$repo/tools/node/dev/probe-mcp"
"$repo/tools/node/dev/mcp-gate"
opencode mcp list
opencode debug skill
```

The first two commands validate Codex client configuration. `probe-mcp`
exercises a real JSON-RPC initialize against every enabled server;
`mcp-gate` drives the production server plus damage controls. The OpenCode
commands validate the OpenCode projection and skill discovery. A client
listing tools without exercising the handlers is not MCP health evidence.
