# Duo Agent Canonical Index

> **Single entry point for ALL agents** (Cursor, Claude, Codex, Devin, Kiro, Hermes,
> OpenCode, Windsurf, Pi, etc.). Do not duplicate buffers elsewhere — route here.

## Canonical files (only these)

| Purpose | Path | MCP read | MCP write |
| --- | --- | --- | --- |
| **Coordination** (claims, build tiers, session log) | `.agents/AGENT_COORDINATION.md` | `duo_coordination_read` / `duo_coordination_buffer` | `duo_coordination_update` |
| **Gaps / findings** (P0–P2, delegation) | `.agents/AGENT_COORDINATION.md#cross-agent-gap-buffer` | `duo_agent_gaps_read` / `duo_agent_gaps_buffer` | `duo_agent_gaps_update` |
| **Performance ledger** | `docs/performance.md` | `duo_perf_ledger` | append manually after bench work |
| **Agent rules** | `AGENTS.md` | — | update only for protocol changes |
| **Grammar spec** (surface syntax evolution) | `docs/GRAMMAR_SPEC.md` | `duo_grammar_spec_read` | `duo_grammar_spec_update` |
| **Directive hierarchy** (`@comp.*` dotted paths) | `docs/DIRECTIVE_HIERARCHY.md` | `duo_directive_hierarchy_read` | — |
| **MCP / multi-agent setup** | `.agents/AGENT_INTEGRATION.md` | — | update when MCP config changes |
| **MCP servers (canonical code)** | `/Users/clp/x/duo-mcp/` | all `duo_*` tools | edit only in duo-mcp repo |
| **End-user agent hooks** (writing IN Duo) | `docs/agent_hooks.md` | `duo_meta_catalog`, `duo_meta_ladder` | — |

**Redirects (not canonical):** `DUO_AGENT_COORDINATION.md` (repo root) and `.agents/AGENT_GAPS.md` → coordination doc only.

**PROTOCOL — `git stash` is BANNED (2026-08-01).** Never stash work to reach a
"clean tree" or dodge a conflict; it silently hides work from `git status` and
broke all parallel agents once. Commit early on a branch, coordinate via claims,
or export a visible `.patch` file. `git stash list` must stay EMPTY.

## Session start (every agent, every session)

1. Call **`duo_agent_session_start(agent_id="your-id")`** (duo-bench MCP) — loads all buffers + open P0 count.
2. Claim work: **`duo_coordination_update(action="claim", ...)`** before editing shared files.
3. Builds: **`duo_agent_smoke()`** or **`scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo`** (tier-0 default).
4. Native audit: **`duo_audit_metaprogramming_smokes()`** after generative/meta work; single-file **`duo_audit_native_boxing(path)`** for targeted checks.
5. New gap: **`duo_agent_gaps_update(action="open", ...)`** or append the Cross-Agent Gap Buffer in `.agents/AGENT_COORDINATION.md`.
6. Delegate P0/P1: **`duo_agent_delegate(gap_id, agent_id, status)`**.

## Comptime hooks (in Duo source)

| Audience | API |
| --- | --- |
| Agents working **on** Duo | `@comp.agent.catalog()`, `.ladder()`, `.hooks()`, `.dedupe()`, `.gaps()`; `req("std.agent")` |
| Agents / apps **in** Duo | `@comp.derive.*`, `@comp.burst`, `@comp.pipeline`, `@comp.catalog("grouped")` |

## Three concerns (do not conflate)

1. **Agent direction** — coordination + gaps buffers + MCP (this index).
2. **End-user agent hooks** — `docs/agent_hooks.md`, `@comp.agent.*`, `std.agent`.
3. **Language implementation** — compiler, codegen, `@comp.*` combinators, native lowering.

Language work takes priority once buffers are read/claimed; do not fork parallel coordination files.
