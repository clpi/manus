#!/usr/bin/env bash
# agent_dedup_check.sh — Check claim status before editing shared files.
# Run BEFORE editing any shared file to detect potential duplication.
# Usage: scripts/agent_dedup_check.sh [file1 file2 ...]
set -euo pipefail

COORD=".agents/AGENT_COORDINATION.md"
CANONICAL=".agents/AGENT_CANONICAL.md"
GAPS="docs/AGENT_GAPS.md"

echo "=== Duo Agent Dedup Check ==="

# 1. Check if canonical files exist
for f in "$COORD" "$CANONICAL" "$GAPS"; do
    if [ ! -f "$f" ]; then
        echo "WARNING: $f not found"
    fi
done

# 2. Check coordination buffer read
if [ -f "$COORD" ]; then
    echo "--- Active Claims ---"
    awk '/^## Active claims/,/^## /' "$COORD" | grep -E '^\|.*\|.*\|.*\|.*\|' | grep -v 'Area.*Agent' | head -20
fi

# 3. Check for open P0 gaps
if [ -f "$GAPS" ]; then
    P0_COUNT=$(grep -c '| P0 |' "$GAPS" 2>/dev/null || echo 0)
    echo "--- Open P0 gaps: $P0_COUNT ---"
fi

# 4. Check specified files for claims
if [ $# -gt 0 ]; then
    echo "--- File claim check ---"
    for f in "$@"; do
        if [ -f "$f" ]; then
            CLAIMED=$(grep -l "$f" "$COORD" 2>/dev/null || true)
            if [ -n "$CLAIMED" ]; then
                echo "WARNING: $f may be claimed by another agent (found in $COORD)"
            fi
        fi
    done
fi

# 5. Check lock status
LOCKFILE="/tmp/duo-build.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "unknown")
    echo "--- Build lock held by PID: $LOCK_PID ---"
else
    echo "--- Build lock: FREE ---"
fi

echo "=== Done ==="
