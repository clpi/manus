# Pass 10 — Public Repository Readiness, Information Density, Structural Coherence

**Status:** active (2026-08-04)  
**Mission:** The Duo repository must be suitable for **immediate public inspection** without private agent context, pass history, or undocumented conventions.

Public readiness is a **release requirement**, not post-release cleanup.

## Machine-readable tracking

```bash
duo catalog | jq '.pass10'
duo catalog | jq '.pass10.repo_audit_findings'
duo catalog | jq '.pass10.pollution_findings'
duo catalog | jq '.pass10.release_invariants[] | select(.status!="met")'
duo catalog | jq '.pass10.mandatory_audits'
duo catalog | jq '.pass10.acceptance_criteria'
```

| Module | Role |
| --- | --- |
| `src/pass10_repo_audit.zig` | Invariants 3.14–3.21, audits A15–A19, blockers, acceptance criteria, pollution findings |
| `src/pass10_catalog.zig` | Milestones, workstreams, presentation standard, catalog export |

## Release invariants (Section 3)

| ID | Title | Status |
| --- | --- | --- |
| 3.14 | Repository ready for public inspection | open |
| 3.15 | No repository pollution | open |
| 3.16 | Every file has a permanent role | open |
| 3.17 | Information density repository-wide | partial |
| 3.18 | Markdown concise and canonical | open |
| 3.19 | Comments explain what code cannot | partial |
| 3.20 | Code concise without cleverness | partial |
| 3.21 | Public names intentional | partial |

## Mandatory audits

| ID | Title | Exit gate |
| --- | --- | --- |
| A15 | Public repository quality audit | New reader can build Duo without private guidance |
| A16 | File necessity audit | Every tracked file has explicit durable purpose |
| A17 | Markdown compression audit | Canonical doc set; duplicates merged or archived |
| A18 | Source density and comment audit | Compact readable codebase without pass/agent noise |
| A19 | Public safety and licensing audit | No secrets; licenses complete |

## Public Repository Presentation Standard

1. **Root experience** — sparse root; README answers what/build/test/limitations in ~10 questions.
2. **Documentation hierarchy** — one entry point; target `docs/language.md`, `docs/compiler.md`, etc.
3. **Current vs future** — label Supported / Experimental / Planned / Historical.
4. **Examples** — compile, run, one capability each; automated validation.
5. **Tests** — organized by semantic responsibility, not pass/issue/agent names.
6. **Generated files** — deterministic, documented command, necessary only.
7. **Scripts** — durable role or delete after migration.
8. **Configuration** — minimal, no private paths, no dead flags.
9. **Public history hygiene** — no secrets, personal paths, copied conversations.

## Milestones

| ID | Title | Status |
| --- | --- | --- |
| P10-M0 | Machine-readable repo audit + catalog | partial |
| P10-M1 | File necessity audit (A16) | open |
| P10-M2 | Markdown compression (A17) | open |
| P10-M3 | Source density + comments (A18) | open |
| P10-M4 | Public safety + licensing (A19) | open |
| P10-M5 | Root README + bootstrap public entry | open |

## Seed pollution findings (P10-P001+)

Initial inventory in `pass10_repo_audit.zig` — expand via A16:

- Duplicate agent docs (`docs/AGENT_COORDINATION.md` vs `.agents/`)
- `AGENTS.md` at root (relocate for public tree)
- Pass-shaped plan docs (`docs/plans/pass2_convergence.md`, etc.) → archive
- Missing canonical `docs/compiler.md`, `docs/language.md`
- Untracked working-tree pollution (`.out`, `debug.log`, `wait*.sh`)

## Release blockers (summary)

**Critical:** secrets, unlicensed code, broken release instructions, misrepresenting docs, confidential tracked files.

**High:** pass-shaped hierarchy, duplicate docs, unclear build, stale examples, scratch files, agent coordination as public architecture.

## Pass 10 acceptance (20 criteria)

Complete when: public-ready tree, sparse root, permanent hierarchy, no pass/agent naming in production, every file justified, consolidated Markdown, validated examples, separated future plans, intentional public names, licensing complete, and an external contributor can locate parser/sema/backend/tests/docs/bootstrap without private guidance.

## Required agent output (Pass 10)

Every agent reports **Repository-quality impact (L):** files added/removed/renamed/merged, docs/comments delta, hierarchy impact, public-readiness impact, justification for every new file.

## Governing questions

For every file: essential? correct directory? permanent name? duplicate? requires history? concise? exposes private material?

For every Markdown doc: audience? canonical? current behavior? merge or delete?

For the repository: intentional? navigable? demonstrates Duo’s semantic density?

**Final rule:** A file is justified only if it has a necessary, permanent role in the clearest possible version of the repository.
