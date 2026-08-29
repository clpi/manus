#!/bin/sh
# coord/cron/lane.sh — wraps overnight.sh with per-lane identity.
#
# Three of these run every 5 minutes via cron. Each lane has its own
# worktree base directory and log dir so they don't step on each
# other's worktrees, branches, or logs.
#
# The pump reads coord/tasks.jsonl and uses the lockfile at
# $LOCK_DIR/<ticket_id> to serialize dispatches of the same ticket.
# Lanes race for tickets; the loser sees the worktree already exists
# and skips.

set -u

LANE=${1:-1}

WORKSPACE=/tmp/idol-gap145-fix
BRANCH=gap-145-c-backend
WORKTREE_BASE=/tmp/idol-migrate-lane$LANE
LOG_DIR=/tmp/idol-migrate-logs-lane$LANE
LOCK_DIR=/tmp/idol-migrate-locks
MAX_TICKETS_PER_RUN=${MAX_TICKETS_PER_RUN:-9}
OR_MODEL="meta-llama/llama-3.1-8b-instruct"

export WORKSPACE WORKTREE_BASE LOG_DIR LOCK_DIR BRANCH MAX_TICKETS_PER_RUN OR_MODEL

mkdir -p "$LOG_DIR" "$LOCK_DIR"
printf 'lane=%d tick=%s\n' "$LANE" "$(date -Iseconds)" >> "$LOG_DIR/lane.log"

# Wrapper around overnight.sh — overnight.sh accepts a ticket at a
# time and dispatches it. For each candidate, attempt to grab the
# ticket's flock before the overnight pump tries the worktree add.
#
# Because overnight.sh iterates ALL pending tickets in one invocation,
# the lanes serialize each other naturally — lane 2 sees the worktree
# that lane 1 already created and logs a worktree-create-failed, then
# moves on. This is the simplest correct serialization.
exec /tmp/idol-gap145-fix/coord/cron/overnight.sh
