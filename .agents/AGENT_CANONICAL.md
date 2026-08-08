# Duo Agent Canonical Index

> **Single entry point for ALL agents** (Cursor, Claude, Codex, Devin, Kiro, Hermes,
> OpenCode, Windsurf, Pi, etc.). Do not duplicate buffers elsewhere — route here.

## Canonical files (only these)

| Purpose | Path | MCP read | MCP write |
| --- | --- | --- | --- |
| **Alignment compass** (read first, 2 min) | `docs/AGENT_ALIGNMENT.md` | — | update at phase boundaries |
| **Coordination** (subsystems, owners, protocol) | `.agents/AGENT_COORDINATION.md` | read it | hand-edit only — MCP writes go to the untracked `.agents/session/` |
| **Gaps / findings** | `gaps/GAP-0NN.md`, one file per gap | — | new file; check the directory first, numbers collide |
| **Performance ledger** | `docs/performance.md` | `duo_perf_ledger` | append manually after bench work |
| **Agent rules** | `AGENTS.md` | — | update only for protocol changes |
| **Architecture plan** (semantic universe) | `docs/semantic_universe.md` | — | update at phase boundaries |
| **Grammar spec** (surface syntax evolution) | `docs/GRAMMAR_SPEC.md` | `duo_grammar_spec_read` | `duo_grammar_spec_update` |
| **Directive hierarchy** (`@comp.*` dotted paths) | `docs/DIRECTIVE_HIERARCHY.md` | `duo_directive_hierarchy_read` | — |
| **MCP / multi-agent setup** | `.agents/AGENT_INTEGRATION.md` | — | update when MCP config changes |
| **MCP servers (canonical code)** | `tools/mcp/` | all `duo_*` tools | merged in-tree 2026-08-08; version-locked to the compiler |
| **End-user agent hooks** (writing IN Duo) | `docs/agent_hooks.md` | `duo_meta_catalog`, `duo_meta_ladder` | — |

**Law:** `CLAUDE.md` is operative; `docs/spec/pass100.md` and `docs/spec/AUTHORITY.md` back it. The archived pass documents are historical evidence and may not be cited as authority.

**Redirects (not canonical):** `docs/AGENT_COORDINATION.md` and `docs/AGENT_GAPS.md` → the files above.

**PROTOCOL — `git stash` is BANNED (2026-08-01).** Never stash work to reach a
"clean tree" or dodge a conflict; it silently hides work from `git status` and
broke all parallel agents once. Commit early on a branch, coordinate via claims,
or export a visible `.patch` file. `git stash list` must stay EMPTY.

## Session start (every agent, every session)

1. Read **`docs/AGENT_ALIGNMENT.md`** — 2-min compass (direction + moratorium + phase status).
2. Skim **`docs/semantic_universe.md`** — architecture depth when touching meta/graph/transforms.
3. Read **`AGENTS.md`** — non-negotiables (perf, native, Lua, `@comp.*`).
4. Call **`duo_agent_session_start(agent_id="your-id")`** (duo-bench MCP) — loads buffers + open P0 count.
5. **Claim** work: **`duo_coordination_update(action="claim", ...)`** before editing shared files.
6. Builds: **`duo_agent_smoke()`** or **`duo run scripts/duo_lock.duo -- ./zig-out/bin/duo run scripts/agent_smoke.duo`** (tier-0 default; `duo_lock.sh` was retired by RL-13).
7. Native audit: **`duo_audit_metaprogramming_smokes()`** after generative/meta work; **`duo_audit_native_boxing(path)`** for targeted checks.
8. New gap: a new `gaps/GAP-0NN.md`.
9. Delegate P0/P1: **`duo_agent_delegate(gap_id, agent_id, status)`**.

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
