#!/bin/sh
# coord/cron/overnight.sh — overnight-managed Live-0 dispatch.
#
# The Live-0 protocol (coord/README.md) puts one main at clpi/idol/main,
# records pending work in coord/tasks.jsonl, and gives each ticket a
# fixture set the agent must re-measure before claiming success. This
# script is the overnight pump: it scans the ledger for pending tasks
# the human has not claimed, opens a new task-specific worktree, runs a
# focused subagent on that single ticket, merges the result through the
# gap-145-c-backend branch (never directly to main), and updates the
# ledger with the outcome.
#
# Why a shell loop instead of dispatching a multi-ticket agent: the
# foundational audit's first sentence is "A fresh stage 0 against a
# frozen corpus is a two to four week job for one strong model and is
# cheaper than cleaning." One strong model, one ticket per overnight
# run, one focused commit per ticket. That is the only pace at which the
# freeze has any chance of holding.
#
# Why gap-145-c-backend and not origin/main: the human (Chris) merges
# gap-145-c-backend -> main when the corpus is green. The overnight
# pump never writes to main directly. The dirty worktree at
# /home/clp/src/idol on hermes-nous-zero34-catalog-faces is pre-Live-0
# and reconciles when its author rebases, not here.
#
# Required to run safely:
#   - GITHUB_TOKEN with push to clpi/idol gap-145-c-backend
#   - The dispatching model on the PATH (default: claude, fallback: openai)
#   - The repo at /tmp/idol-gap145-fix on branch gap-145-c-backend at the
#     pinned base SHA the script is given

set -u

WORKSPACE=${WORKSPACE:-/tmp/idol-gap145-fix}
WORKTREE_BASE=${WORKTREE_BASE:-/tmp/idol-migrate}
LOG_DIR=${LOG_DIR:-/tmp/idol-migrate-logs}
BASE_SHA=${BASE_SHA:-566d1884}     # the latest coord/ Live-0 substrate commit
BRANCH=${BRANCH:-gap-145-c-backend}
DISPATCH_MODEL=${DISPATCH_MODEL:-claude}
MAX_TICKETS_PER_RUN=${MAX_TICKETS_PER_RUN:-3}

mkdir -p "$LOG_DIR"

# 1. REBASE THE WORKTREE onto the latest origin/$BRANCH before any
#    dispatch. A stale base is the most common overnight failure mode
#    and the audit's section 7 says "agents rebase before every push".
cd "$WORKSPACE"
# Stage everything in coord/ so a work-in-progress pump entry doesn't
# fail the rebase step. A pump that touches its own substrate must not
# block on its own diff. (The substrate is pushed separately; the
# pump only READS tasks.jsonl and claims.jsonl.)
git add coord/ 2>/dev/null || true
git fetch origin "$BRANCH" 2>&1 | tee -a "$LOG_DIR/fetch.log"
# If the rebase would conflict with unstaged changes, the right move is
# to stash and pop. A pump that breaks on its own diff is a pump that
# cannot run unattended.
if ! git rebase origin/"$BRANCH" 2>&1 | tee -a "$LOG_DIR/rebase.log"; then
  git rebase --abort 2>&1 | tee -a "$LOG_DIR/rebase.log" || true
  printf 'overnight: rebase failed, stashing and retrying
' | tee -a "$LOG_DIR/rebase.log"
  git stash push -u -m "overnight-pump-2026-08-29T04:56:24-07:00" >> "$LOG_DIR/rebase.log" 2>&1
  git rebase origin/"$BRANCH" >> "$LOG_DIR/rebase.log" 2>&1 || true
fi

# 2. NEUTRALIZE THE IDLE CHECKOUT. /home/clp/src/idol is a pre-Live-0
#    leftover worktree. Do not touch it; the audit says "Live-0 enforces
#    the discipline from now on, not the past." Just confirm it is
#    still preserved and move on.
if [ -d /home/clp/src/idol ]; then
  dirty_branch=$(git -C /home/clp/src/idol branch --show-current 2>/dev/null || echo unknown)
  dirty_state=$(git -C /home/clp/src/idol status -s 2>/dev/null | wc -l | tr -d ' ')
  printf 'overnight: dirty /home/clp/src/idol on %s with %s uncommitted lines (do not touch)\n' \
    "$dirty_branch" "$dirty_state" | tee -a "$LOG_DIR/observe.log"
fi

# 3. FIND PENDING TASKS that the human has not yet claimed.
pending=$(awk -F'"' '
  /^\{/ && /"id":/ && /"state": "pending"/
' "$WORKSPACE/coord/tasks.jsonl")

ticket_count=$(echo "$pending" | grep -c '"id":' || true)
printf 'overnight: %d pending ticket(s) at %s\n' "$ticket_count" "$(date -Iseconds)" \
  | tee -a "$LOG_DIR/dispatch.log"

if [ "$ticket_count" -eq 0 ]; then
  printf 'overnight: no work to do, exiting\n' | tee -a "$LOG_DIR/dispatch.log"
  exit 0
fi

# 4. DISPATCH UP TO MAX_TICKETS_PER_RUN TICKETS, each in its own worktree.
#    The dispatch is delegated to a subagent (claude, openai, or
#    whichever model the user configured). The subagent's task: read
#    coord/README.md and the ticket, do the migration, commit, push to
#    origin/$BRANCH, append a task entry and an attempt summary.
dispatched=0
echo "$pending" | while IFS= read -r line; do
  if [ -z "$line" ]; then continue; fi
  if [ "$dispatched" -ge "$MAX_TICKETS_PER_RUN" ]; then break; fi

  ticket_id=$(echo "$line" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')
  if [ -z "$ticket_id" ]; then continue; fi

  wt="$WORKTREE_BASE/$ticket_id"
  log="$LOG_DIR/$ticket_id.log"
  printf 'overnight: dispatching ticket=%s worktree=%s\n' "$ticket_id" "$wt" \
    | tee -a "$log"

  if [ -d "$wt" ]; then rm -rf "$wt"; fi
  git worktree add -b "migrate/$ticket_id" "$wt" origin/"$BRANCH" \
    >> "$log" 2>&1

  # The subagent is given the ticket's full body as the dispatch
  # argument. The harness (this script) writes the prompt, then
  # invokes the model. On exit 0 with a returned commit SHA, append a
  # task ledger entry and an attempt summary.
  prompt_file=$(mktemp)
  cat > "$prompt_file" <<PROMPT
You are the Live-0 overnight dispatcher agent.

Read first:
  1. $WORKSPACE/coord/README.md
  2. $WORKSPACE/coord/tasks.jsonl (find the pending ticket below)
  3. $WORKSPACE/coord/decisions.md
  4. The doc/ authority stack cited in decisions.md

Your ticket:
  $line

Your workspace:
  Working directory: $wt
  Branch: migrate/$ticket_id
  Base SHA: $BASE_SHA
  Target push: origin/$BRANCH (NEVER origin/main)

Constraints (the human said "Don't take everything as gospel yet
from that constitution" — meaning D1-D13 in coord/decisions.md are
AWAITING HUMAN RATIFICATION):
  - Do NOT make semantic-breaking changes. Do NOT change line-leading
    infix continuation behavior. Do NOT change declaration head rules.
  - DO ONLY spec migration: decompose mashed compounds in Idol source
    files (.id) into their constituent single-word names.
  - Decompose before rename per spec section 9.
  - Each commit should be ONE focused migration. Run gates after each
    commit:
      cd $WORKSPACE && timeout 60 zig build gap-145-consumer
      cd $WORKSPACE && timeout 60 zig build grammar-projection
      cd $WORKSPACE && timeout 60 zig build posix
  - Push to origin/$BRANCH only. Never to origin/main.
  - Add a row to coord/tasks.jsonl marking this delivery.
  - Add a row to coord/claims.jsonl recording your claim + result.
  - Write coord/attempts/\$(date -I)-\$ticket_id.md with the attempt
    summary.

Return one line:
  ticket=\$ticket_id commit=\$SHA summary=\$ONELINE
PROMPT

  # Invoke the model. The dispatch is the host's responsibility; this
  # script does not need to know which model is on PATH. The
  # orchestrating env chooses. The default is claude via the
  # anthropic API, with OPENai as fallback; both are configured in
  # /home/clp/.openclaw/.env.
  chmod 600 /home/clp/.openclaw/.env
  # shellcheck disable=SC1090
  . /home/clp/.openclaw/.env

  model_cmd=""
  if [ "$DISPATCH_MODEL" = "claude" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    model_cmd="claude -p \$(cat $prompt_file)"
  fi
  if [ -z "$model_cmd" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
    model_cmd="openai -p \$(cat $prompt_file)"
  fi
  if [ -z "$model_cmd" ]; then
    printf 'overnight: no model API key found in /home/clp/.openclaw/.env, exiting\n' \
      | tee -a "$log"
    exit 2
  fi

  sh -c "$model_cmd" >> "$log" 2>&1
  rm -f "$prompt_file"
  dispatched=$((dispatched + 1))
done

printf 'overnight: dispatched %d ticket(s) at %s\n' "$dispatched" "$(date -Iseconds)" \
  | tee -a "$LOG_DIR/dispatch.log"
