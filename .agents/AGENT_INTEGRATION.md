# Idol agent integration

| # | directive |
|---|---|
| 1 | This is a durable client setup guide. |
| 2 | It contains no language law, live claims, tool census, or current gate status. |

## Canonical locations

- Development repository: the current `clpi/idol` checkout (worktrees may live
  on another volume; derive the root with `git rev-parse --show-toplevel`).
- Native benchmark repository: the sibling `idol-native` checkout (remote
  `clpi/idol-native`, branch `main`) — owns the end-user `.id` language server
  and its compiler-backed graph queries.
- The pre-rename project identity is **fully retired**. Server names, tool
  names, environment keys, and skill names are `idol`-named only; no client
  configuration may reintroduce retired spellings.

## Operating model and work orders

| # | directive |
|---|---|
| 1 | Multi-agent allocation is defined by `.agents/AGENT_OPERATING_MODEL.md` (roles, waves, and the never-assign list). |
| 2 | Every assignment to a non-architectural agent is materialized through `.agents/WORK_ORDER.md`; per-agent injectables live under `.agents/briefs/`. |
| 3 | OpenCode's assigned role is projected natively as the `pickle` agent (`.opencode/agent/pickle.md`). |

## Repository servers

| # | directive |
|---|---|
| 1 | The version-locked MCP implementations are declared once by the client-neutral `tools/node/dev/mcp.manifest.json`: |

| Physical server name | Entry point | State | Purpose |
|---|---|---|---|
| `idol` | `tools/mcp/native.id` | enabled, required | bootstrap status, head, orient transport |
| `idol-native` | sibling `idol-native` checkout, `tools/mcp/server.id` | enabled | `check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`, `explain`, `fmt`, `asm` |

| # | directive |
|---|---|
| 1 | A manifest entry with a `sibling` field resolves its root, entry, and launcher binary against the sibling checkout of this clone. |
| 2 | The retired pre-rename transports (claims/bench, diagnostics, zls bridges) were removed, not disabled: claims use `tools/node/dev/claim`, diagnostics and language intelligence come from the `idol-native` server and its language server, and Zig navigation uses the editor's own zls directly. `tools/mcp/native.id` is a raw-text bootstrap compatibility transport, not a graph-owned semantic projection. |
| 3 | Generated client configurations are projections of the manifest, not additional authorities. |

## Client shape

| # | directive |
|---|---|
| 1 | Clients run each server's own `idol` binary with the server's root as cwd. |
| 2 | Run `tools/node/dev/generate-configs` to derive absolute client projections from the actual clone path (the generator emits the stable `~/x` spelling when applicable). |
| 3 | Projections: |

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

| # | directive |
|---|---|
| 1 | The generated Codex shape is: |

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

| # | directive |
|---|---|
| 1 | `idol-native` uses the same shape with its own root and `bin/idol` launcher. |
| 2 | Keep the pinned Zig and ZLS directories in `PATH` for desktop and IDE launches. |

## Skills and law routing

- Every agent starts at `AGENTS.md`; OpenCode additionally loads it through
  `instructions` in its global config.
- Skills `idol` and `idol-dev` live canonically in `.pi/skills`.
  `tools/node/dev/install-skills` installs them for Codex and Devin;
  `tools/node/dev/generate-configs` projects them for OpenCode (paths above).

## Editor language intelligence

| # | directive |
|---|---|
| 1 | The `.id` language server is the idol-native tree's `tools/lsp/launch.sh` (Content-Length framing; diagnostics and symbols come from that tree's own compiler and semantic graph — the transport adds no second authority). |
| 2 | Wire editors with `IDOL_BIN` pointing at the sibling checkout's `bin/idol`. |
| 3 | The duplicate in-repository `tools/lsp` scanner, taxonomy, fixtures, and gates were deleted. |
| 4 | Semantic tokens wait for graph-owned source spans and generated grammar-role projections in the durable sibling server; do not restore the old raw scanner or corpus. |

## Session protocol

1. Start at `AGENTS.md` and `.agents/AGENT_CANONICAL.md`.
2. Use skill **`idol-dev`** (`.pi/skills/idol-dev`).
3. Orient: `tools/node/dev/orient`, or the `orient` tool on the `idol` server.
4. Inspect current HEAD, dirty state, recent commits, `tools/node/dev/claim list`,
   every current `gaps/GAP-*.md`, and the verified `docs/bootstrap.md` frontier.
5. Treat `orient`'s `activep0` as a derived census; the exact gap files own
   obligation status (`GAP-131` is closed).
6. Claim exact paths with `tools/node/dev/claim acquire` before editing.
7. Delegate only bounded independent work with disjoint write ownership.
8. Serialize heavy gates through `tools/node/dev/idol-lock`.
9. Commit explicit pathspecs and release only claims owned by the session.

## Validation

| # | directive |
|---|---|
| 1 | Run setup evidence from the repository root: |

```text
repo="$(git rev-parse --show-toplevel)"
codex --strict-config doctor
codex mcp list
"$repo/tools/node/dev/probe-mcp"
"$repo/tools/node/dev/mcp-gate"
opencode mcp list
opencode debug skill
```

| # | directive |
|---|---|
| 1 | The first two commands validate Codex client configuration. `probe-mcp` exercises a real JSON-RPC initialize against every enabled server; `mcp-gate` drives the production server plus damage controls. |
| 2 | The OpenCode commands validate the OpenCode projection and skill discovery. |
| 3 | A client listing tools without exercising the handlers is not MCP health evidence. |
