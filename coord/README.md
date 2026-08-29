# Live-0 — coordination protocol for the Idol bootstrap

Date: 2026-08-29
Authority: derived from `docs/spec/law.md`, the foundational audit
of 2026-08-29, and the self-host execution plan.

## Files in this directory

| File | Purpose | Owner |
|---|---|---|
| `tasks.jsonl` | one task per line: goal, task, depends, owner, state | agent creating the task |
| `claims.jsonl` | one claim per line: actor, target files or dump boundary, intent, expiry | agent starting work |
| `attempts/` | one file per attempt: observed fixture set, what changed, result, and if rejected, why | agent closing the attempt |
| `decisions.md` | kernel decisions with dates and reasons, versioned corpus changes | the human (Chris) |

## Trunk discipline

One `main`. Agents work in worktrees on tickets sized to finish in one
session. Rebase before every push. The only merge gate is the corpus
plus the dump goldens. No branch lives past a day; if it does, the
ticket was too big.

## Ticket contract

Every ticket states:
- the goal
- the fixtures that must pass
- the files the agent may touch
- the files the agent may not touch

No renames outside the ticket. No new abstraction without a fixture
that fails without it. Deletion is its own ticket. A ticket that
requires a spec decision is blocked and routed to the human, not
resolved by the agent's best guess.

## Reconcile before claim

`git pull --rebase` before opening a claim. The dirty worktrees that
existed before Live-0 are an exception, not the rule. They reconcile
into main when their authors rebase and push; Live-0 enforces the
discipline from now on, not the past.
