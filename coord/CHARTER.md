| field | value |
|---|---|
| title | Live worker charter — Idol self-host campaign |

| # | directive |
|---|---|
| 1 | Read this before touching the tree. |
| 2 | It is the contract every Kanban worker, subagent, cron tick, and human lane on any device operates under. |

| section |
|---|---|
| The one truth |

| # | directive |
|---|---|
| 1 | `clpi/idol` `main` on GitHub is the only integration surface. |
| 2 | Every device holds a worktree that `scripts/live/reconcile.sh` keeps within one tick of `origin/main`. |
| 3 | There is no second integration branch. |
| 4 | There is no long-lived lane. |
| 5 | Work you do not land is work that did not happen. |

| section |
|---|---|
| Before you write a byte |

| # | directive |
|---|---|
| 1 | `sh scripts/live/reconcile.sh` — you must start from `origin/main` HEAD. |
| 2 | Read the card. It names ONE gate or ONE GAP and the exact acceptance command. If the card names more than one, split it and take the first. |
| 3 | `zig build && zig build test 2>&1 \| grep 'failed command' \| sort -u` — record the failing set BEFORE you change anything. That is your baseline. |

| section |
|---|---|
| While you work |

| # | directive |
|---|---|
| 1 | One concern per commit. Subject line names the gate/GAP and the fact that changed, e.g. `GAP-145: .quoted tag-test ceiling 89 -> 88`. |
| 2 | Never lower a ceiling, weaken a gate, delete a test, or edit a `gate/*.sh` threshold to make red go green. A gate that rejects the tree is the tree's fault. If the gate itself is wrong, that is a separate card with a written argument in `gaps/`. |
| 3 | Never invent grammar. `..` is retired, `\|>` and `(:)` do not exist, `pass*`/`duo_*` are retired. Read `AGENTS.md` and `docs/spec/law.md`. |
| 4 | Never write to `dnir_lower.zig` or `native_backend.zig` to fake a realization. Never claim FTCFTW / Compiler B without pinned evidence. |
| 5 | Do not touch another card's files. If you must, comment on both cards first. |

| section |
|---|---|
| Before you finish |

| # | directive |
|---|---|
| 1 | `zig build && zig build test` — the failing set must be a strict subset of your baseline. Paste both sets in the card comment. |
| 2 | The card's named acceptance command must exit 0. Paste its last lines. |
| 3 | `sh scripts/live/reconcile.sh` — it rebases, re-gates, and pushes to `origin/main`. If it parks you on `rescue/<host>-<stamp>`, resolve and rerun; do not leave work on a rescue branch. |
| 4 | Complete the card. Its child promotes automatically. |

| section |
|---|---|
| If you are blocked |

| # | directive |
|---|---|
| 1 | A missing fact, a broken tool, an unreachable host — these are work, not status. |
| 2 | Fix in place, or create the exact repair card as this card's parent, comment why, and complete or block this one. |
| 3 | Never end with a paragraph that begins "The next step would be". |

| # | directive |
|---|---|
| 1 | Fail closed only on: a spec decision the human owns (`coord/decisions.md`), credentials, or destructive external action. |

| section |
|---|---|
| Providers |

| # | directive |
|---|---|
| 1 | No PAYG. |
| 2 | Use the profile/provider pinned on the card. |
| 3 | If it is exhausted (402/429 quota), `hermes kanban --board idol-selfhost reassign <id>` to the next approved profile and comment the failure; do not switch to a metered key. |

| section |
|---|---|
| Evidence |

| # | directive |
|---|---|
| 1 | Every performance or cross-platform claim binds to a revision and a host: `evidence/` entries carry `sha`, `host`, `toolchain`, and the raw command output. |
| 2 | Unbound numbers are deleted on sight. |
