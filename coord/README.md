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

## Overnight pump

`coord/cron/overnight.sh` is the overnight pump. The audit says
"agents work in tickets sized to finish in one session. Rebase before
every push. No branch lives past a day." The pump applies that rule:

  1. `git fetch` the workspace onto the latest origin/gap-145-c-backend.
  2. `git rebase` the workspace before any dispatch.
  3. Observe the dirty `/home/clp/src/idol` worktree but do NOT touch it
     (the audit says "Live-0 enforces the discipline from now on, not
     the past"). Log the branch and the uncommitted line count.
  4. Find every pending ticket in `coord/tasks.jsonl`.
  5. For up to `MAX_TICKETS_PER_RUN` (default 3) tickets, spawn a
     per-ticket worktree at `/tmp/idol-migrate/$ticket_id` and dispatch
     a single-ticket subagent there. The subagent's contract: read
     `coord/README.md`, do the migration, run the three gates, push to
     `origin/gap-145-c-backend` (NEVER origin/main), append a task row
     and an attempt summary.
  6. Exit 0. The next cron tick re-reads the ledger.

The human merges `gap-145-c-backend` -> `main` when the corpus is green.
No subagent writes to main directly.

### Installing the cron entry

The pump itself is `coord/cron/overnight.sh`. Install it via crontab:

```
0 2 * * *  /tmp/idol-gap145-fix/coord/cron/overnight.sh >> /tmp/idol-migrate-logs/cron.log 2>&1
```

That is "2 AM nightly, one ticket each." Adjust the schedule to match
how much the human can review in the morning.

### Why the pump never writes main

The audit's section 7 says "Trunk discipline. One main. Rebase before
every push." A subagent that lands on main directly sidesteps the
human's review and makes the freeze unratifiable. The pump is the
instrument that keeps subagent work in a single integration branch
(`gap-145-c-backend`) where the human sees every commit before it
becomes law.
