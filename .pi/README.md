# pi projection for Idol

This directory is a **tooling projection** for the [pi](https://pi.dev) coding
agent. It is the pi analogue of `.cursor/rules/`, `.codex/`, `.claude/`, and
`.kiro/` already present in this tree. It is **not** Idol language authority,
not a compiler subsystem, and not semantic source.

Authority and workflow law live where C0 says they live:

```
AGENTS.md -> docs/spec/constitution.md -> CLAUDE.md -> docs/spec/source.md
         -> docs/spec/AUTHORITY.md -> docs/bootstrap.md
         -> .agents/AGENT_CANONICAL.md / AGENT_COORDINATION.md
```

Nothing in `.pi/` may contradict those files. If it ever does, the authority
file is right and this projection must be repaired.

## Contents

| Path | Purpose |
| --- | --- |
| `settings.json` | Project-local pi settings (compaction retention, npm via mise). |
| `skills/idol-dev/` | Pi-local mirror of the canonical Idol development-loop skill in `.devin/skills/idol-dev/`. Install into Codex and Devin with `./tools/node/dev/install-skills`. |
| `extensions/idol-mcp.ts` | Bridges the three project MCP servers (`idol-bench`, `idol-lsp`, `zls`) into pi tools, since pi has no native MCP and the Idol coordination workflow (claims, gaps, serialized builds) is MCP-based. |

## What this projection does NOT do

- It does not add a foreign compiler subsystem (Zig/C/Lua/shell/Python) inside
  the Idol compiler. The extension only shells out to the existing
  repository-native `idol` binary to speak JSON-RPC to the project's own MCP
  servers.
- It does not bypass the gates. `skills/idol-dev` wraps `gate/idiom.id`
  and `gate/architecture.id`; it never suppresses a finding.
- It does not replace claim coordination. Claim acquire/release is forwarded to
  the `idol-bench` MCP server (`idol_dev_claim_acquire` / `duo_dev_claim_acquire` aliases), the same authority
  Cursor and Codex use.

## Trust

pi will prompt before trusting this folder on first run because it contains
project-local settings and skills. Use `/trust` to persist the decision. The
extension executes the `idol` binary with your permissions; review
`extensions/idol-mcp.ts` before trusting.

## Committing this directory

Whether to commit `.pi/` is a project decision. It is a new tree addition and,
under this repository's claim discipline, should be claimed before a shared
commit. Machine-local pi state (caches, compiled MCP binaries) should stay
ignored — add `.pi/.cache/` to a local ignore if you compile MCP servers here.
