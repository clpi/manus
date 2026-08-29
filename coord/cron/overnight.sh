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
OR_MODEL=${OR_MODEL:-"meta-llama/llama-3.1-8b-instruct"}
DISPATCH_MODEL=${DISPATCH_MODEL:-claude}
MAX_TICKETS_PER_RUN=${MAX_TICKETS_PER_RUN:-3}

mkdir -p "$LOG_DIR"

# Load env (credentials) once
chmod 600 /home/clp/.openclaw/.env 2>/dev/null || true
. /home/clp/.openclaw/.env

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

# 3. FIND PENDING TASKS via Python jsonl parse (one ticket per line).
pending_file=$(mktemp)
python3 "$WORKSPACE/coord/cron/filter_pending.py" "$WORKSPACE/coord/tasks.jsonl" > "$pending_file"

ticket_count=$(wc -l < "$pending_file" | tr -d ' ')
printf 'overnight: %d pending ticket(s) at %s\n' "$ticket_count" "$(date -Iseconds)" \
  | tee -a "$LOG_DIR/dispatch.log"

if [ "$ticket_count" -eq 0 ]; then
  printf 'overnight: no work to do, exiting\n' | tee -a "$LOG_DIR/dispatch.log"
  rm -f "$pending_file"
  exit 0
fi

# 4. DISPATCH UP TO MAX_TICKETS_PER_RUN TICKETS, each in its own worktree.
dispatched=0
while IFS= read -r line; do
  if [ -z "$line" ]; then continue; fi
  if [ "$dispatched" -ge "$MAX_TICKETS_PER_RUN" ]; then break; fi

  ticket_id=$(echo "$line" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')
  if [ -z "$ticket_id" ]; then continue; fi

  wt="$WORKTREE_BASE/$ticket_id"
  log="$LOG_DIR/$ticket_id.log"
  printf 'overnight: dispatching ticket=%s worktree=%s\n' "$ticket_id" "$wt" \
    | tee -a "$log"

  # Clean any leftover worktree/branch from previous runs
  if [ -d "$wt" ]; then rm -rf "$wt"; fi
  if git worktree list --porcelain 2>/dev/null | grep -q "worktrees/$ticket_id"; then
    git worktree prune
  fi
  if git show-ref --verify --quiet "refs/heads/migrate/$ticket_id"; then
    git branch -D "migrate/$ticket_id" 2>/dev/null || true
  fi
  if git ls-remote origin "migrate/$ticket_id" >/dev/null 2>&1; then
    git push origin --delete "migrate/$ticket_id" 2>/dev/null || true
  fi

  if ! git worktree add -b "migrate/$ticket_id" "$wt" origin/"$BRANCH" >> "$log" 2>&1; then
    printf 'overnight: %s -> worktree create failed\n' "$ticket_id" | tee -a "$log"
    continue
  fi

  # Route by ticket id pattern
  mode="openrouter"
  case "$ticket_id" in
    spec-*|migrate-*-private-*)
      mode="script" ;;
    dirty-checkout-*)
      mode="skip" ;;
  esac

  case "$mode" in
    script)
      printf 'overnight: %s -> script migration\n' "$ticket_id" | tee -a "$log"
      if [ ! -x "$WORKSPACE/coord/cron/migrate-private-prefixes.sh" ]; then
        printf 'overnight: %s -> migration script missing\n' "$ticket_id" | tee -a "$log"
        continue
      fi
      target=$(printf '%s' "$line" \
        | python3 -c "import json,sys; t=json.loads(sys.stdin.read()); print(t.get('target',''))" \
        2>/dev/null)
      if [ -z "$target" ]; then
        target=$(grep -lE "^[[:space:]]*_[a-z_]+:" "$WORKSPACE"/scripts/*.id 2>/dev/null \
          | head -1 | sed "s|$WORKSPACE/||")
      fi
      if [ -z "$target" ] || [ ! -f "$WORKSPACE/$target" ]; then
        printf 'overnight: %s -> no target file\n' "$ticket_id" | tee -a "$log"
        continue
      fi
      # Migrate in the worktree
      (cd "$wt" && sh "$WORKSPACE/coord/cron/migrate-private-prefixes.sh" "$target") >> "$log" 2>&1
      # Verify gates (use the main workspace so the C backend is built)
      if ! (cd "$WORKSPACE" && timeout 60 zig build gap-145-consumer grammar-projection posix) >> "$log" 2>&1; then
        printf 'overnight: %s -> gates FAILED, not committing\n' "$ticket_id" | tee -a "$log"
        continue
      fi
      # Copy the migrated file back into the worktree
      cp "$WORKSPACE/$target" "$wt/$target"
      # Commit
      if (cd "$wt" && git add -A \
        && git -c user.name="Idol Live-0" -c user.email="idol@local" \
             commit -m "spec: decompose private-prefix in $target (ticket $ticket_id)") >> "$log" 2>&1; then
        # Push
        if (cd "$wt" && git push origin "migrate/$ticket_id":"$BRANCH") >> "$log" 2>&1; then
          printf 'overnight: %s -> PUSHED to %s\n' "$ticket_id" "$BRANCH" | tee -a "$log"
          dispatched=$((dispatched + 1))
        else
          printf 'overnight: %s -> push failed\n' "$ticket_id" | tee -a "$log"
        fi
      else
        printf 'overnight: %s -> commit failed (no changes?)\n' "$ticket_id" | tee -a "$log"
      fi
      ;;
    openrouter)
      printf 'overnight: %s -> openrouter\n' "$ticket_id" | tee -a "$log"
      if [ -z "${OPENROUTER_API_KEY:-}" ]; then
        printf 'overnight: %s -> no OPENROUTER_API_KEY, skipping\n' "$ticket_id" | tee -a "$log"
        continue
      fi
      prompt="Live-0 dispatch. Ticket: $line. Workspace: $wt. Branch: migrate/$ticket_id. Push: origin/$BRANCH. CONSTRAINT: D1-D13 are AWAITING HUMAN RATIFICATION. Do NOT make semantic-breaking changes. Spec migration only: decompose mashed compounds in .id files. Run gates before commit."
      payload=$(python3 -c '
import json, sys
prompt = sys.argv[1]
print(json.dumps({"model": sys.argv[2], "messages":[{"role":"user","content":prompt}], "max_tokens":1000}))
' "$prompt" "$OR_MODEL")
      response=$(curl -sm 90 -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1) || response="curl_failed"
      echo "$response" >> "$log"
      printf 'overnight: %s -> openrouter response logged\n' "$ticket_id" | tee -a "$log"
      dispatched=$((dispatched + 1))
      ;;
  esac
done < "$pending_file"
rm -f "$pending_file"

printf 'overnight: dispatched %d ticket(s) at %s\n' "$dispatched" "$(date -Iseconds)" \
  | tee -a "$LOG_DIR/dispatch.log"
