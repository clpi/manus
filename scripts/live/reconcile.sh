#!/bin/sh
# scripts/live/reconcile.sh — keep one worktree continuously reconciled to
# origin/main (clpi/idol). Runs from launchd on the mm host every few minutes
# and from any agent before it claims work.
#
# Contract (Live-0, coord/README.md): one main, rebase before push, no branch
# lives past a day. This script is the mechanical form of that rule:
#
#   1. fetch --prune
#   2. if the worktree is clean and on main: fast-forward to origin/main
#   3. if the worktree has local commits on main: rebase onto origin/main,
#      rebuild, run the aggregate gate, push only if green
#   4. write evidence/live/reconcile.json (host, sha, gate result, timestamp)
#   5. never touch a dirty tree; report it instead
#
# Exit codes: 0 reconciled, 10 dirty (left alone), 20 gate failed (not pushed),
# 30 fetch failed.
set -u

REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
ZIG=${ZIG:-zig}
HOST=$(hostname -s)
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_DIR=${LOG_DIR:-$HOME/.local/state/idol-live}
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/reconcile.log"
STATE="$LOG_DIR/reconcile.json"

log() { printf '%s %s %s\n' "$STAMP" "$HOST" "$*" | tee -a "$LOG" >&2; }
state() {
  # state <verdict> <sha> <detail>
  printf '{"host":"%s","at":"%s","verdict":"%s","sha":"%s","detail":"%s"}\n' \
    "$HOST" "$STAMP" "$1" "$2" "$3" > "$STATE"
}

cd "$REPO" || { log "no repo at $REPO"; exit 30; }

# One writer per host.
exec 9>"$LOG_DIR/reconcile.lock"
if ! flock -n 9 2>/dev/null; then
  # macOS has no flock(1); fall back to mkdir lock.
  if ! mkdir "$LOG_DIR/reconcile.lock.d" 2>/dev/null; then
    log "another reconcile is running"; exit 0
  fi
  trap 'rmdir "$LOG_DIR/reconcile.lock.d" 2>/dev/null' EXIT HUP INT TERM
fi

if ! git fetch --prune -q origin 2>>"$LOG"; then
  log "fetch failed"; state fetch-failed "$(git rev-parse --short HEAD)" "origin unreachable"; exit 30
fi

BRANCH=$(git branch --show-current)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
HEAD_SHA=$(git rev-parse --short HEAD)
MAIN_SHA=$(git rev-parse --short origin/main)

if [ "$DIRTY" != "0" ]; then
  log "dirty worktree ($DIRTY paths) on $BRANCH@$HEAD_SHA; not touching"
  state dirty "$HEAD_SHA" "$DIRTY dirty paths on $BRANCH; origin/main=$MAIN_SHA"
  exit 10
fi

if [ "$BRANCH" != "main" ]; then
  # A worker lane. Rebase it onto main so it never diverges more than one tick,
  # and publish it so other hosts see it (hermes/<lane> namespace).
  if git rebase -q origin/main 2>>"$LOG"; then
    git push -q --force-with-lease origin "HEAD:refs/heads/$BRANCH" 2>>"$LOG" || true
    log "lane $BRANCH rebased onto origin/main $MAIN_SHA and published"
    state lane-rebased "$(git rev-parse --short HEAD)" "$BRANCH on origin/main=$MAIN_SHA"
  else
    git rebase --abort 2>/dev/null
    log "lane $BRANCH conflicts with origin/main $MAIN_SHA; needs a human or a merge card"
    state lane-conflict "$HEAD_SHA" "$BRANCH vs origin/main=$MAIN_SHA"
  fi
  exit 0
fi

AHEAD=$(git rev-list --count origin/main..HEAD)
BEHIND=$(git rev-list --count HEAD..origin/main)

if [ "$AHEAD" = "0" ]; then
  if [ "$BEHIND" != "0" ]; then
    git merge -q --ff-only origin/main 2>>"$LOG"
    log "fast-forwarded main $HEAD_SHA -> $MAIN_SHA"
  fi
  state in-sync "$MAIN_SHA" "ahead=0 behind=0"
  exit 0
fi

# Local commits on main: rebase, verify, push.
if ! git rebase -q origin/main 2>>"$LOG"; then
  git rebase --abort 2>/dev/null
  log "local main commits conflict with origin/main; parking on rescue branch"
  RESCUE="rescue/$HOST-$(date -u +%Y%m%dT%H%M)Z"
  git branch "$RESCUE" && git push -q origin "$RESCUE" && git reset -q --hard origin/main
  state rescued "$MAIN_SHA" "$AHEAD commits parked on $RESCUE"
  exit 0
fi

GATE_LOG="$LOG_DIR/gate.$(date -u +%Y%m%dT%H%M%S).log"
if "$ZIG" build >"$GATE_LOG" 2>&1 && \
   ./zig-out/bin/idol check gate/architecture.id >>"$GATE_LOG" 2>&1 && \
   "$ZIG" build test >>"$GATE_LOG" 2>&1; then
  if git push -q origin HEAD:main 2>>"$LOG"; then
    log "pushed $AHEAD commit(s) to origin/main -> $(git rev-parse --short HEAD)"
    state pushed "$(git rev-parse --short HEAD)" "$AHEAD commits; gate green ($GATE_LOG)"
  else
    log "push rejected (raced); will retry next tick"
    state push-raced "$(git rev-parse --short HEAD)" "retry"
  fi
  exit 0
fi

log "gate FAILED; $AHEAD local commit(s) NOT pushed; see $GATE_LOG"
state gate-failed "$(git rev-parse --short HEAD)" "$GATE_LOG"
exit 20
