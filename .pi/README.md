# pi projection for Idol

This directory is a **tooling projection** for the [pi](https://pi.dev) coding
agent. It is the pi analogue of `.cursor/rules/`, `.codex/`, `.claude/`, and
`.kiro/` already present in this tree. It is **not** Idol language authority,
not a compiler subsystem, and not semantic source.

Authority and workflow law live where C0 says they live:

```
docs/spec/law.md -> AGENTS.md -> docs/spec/canonical.md -> docs/spec/agent.md
         -> docs/spec/constitution.md -> CLAUDE.md -> docs/spec/source.md
         -> docs/spec/host.md -> docs/spec/AUTHORITY.md -> docs/bootstrap.md
         -> .agents/AGENT_CANONICAL.md / AGENT_COORDINATION.md
```

Nothing in `.pi/` may contradict those files. If it ever does, the authority
file is right and this projection must be repaired.

## Contents

| Path | Purpose |
| --- | --- |
| `settings.json` | Project-local pi settings (compaction retention, npm via mise). |
| `skills/idol-dev/` | Canonical Idol development-loop skill source. Install it into agent homes with `./tools/node/dev/install-skills`. |
| `skills/idol/` | Canonical Idol authority-projection skill source. Install it into agent homes with `./tools/node/dev/install-skills`. |
| `extensions/idol-mcp.ts` | Projects the manifest-owned `idol` and `idol-native` servers into pi tools. Compiler/LSP facts come from `idol-native`; claims and locked builds stay explicit repository commands. |

## What this projection does NOT do

- It does not add a foreign compiler subsystem (Zig/C/Lua/shell/Python) inside
  the Idol compiler. The extension only shells out to the existing
  repository-native `idol` binary to speak JSON-RPC to the project's own MCP
  servers.
- It does not bypass the gates. `skills/idol-dev` wraps `gate/idiom.id`
  and `gate/architecture.id`; it never suppresses a finding.
- It does not replace claim coordination. Claim acquire/release remains the
  explicit `tools/node/dev/claim` command; MCP does not mint a second transport
  meaning for it.

## Trust

pi will prompt before trusting this folder on first run because it contains
project-local settings and skills. Use `/trust` to persist the decision. The
extension executes the `idol` binary with your permissions; review
`extensions/idol-mcp.ts` before trusting.

## Committing this directory

The skill sources, settings, and MCP bridge are tracked tooling projections.
Machine-local pi state (caches and compiled MCP binaries) stays ignored.
