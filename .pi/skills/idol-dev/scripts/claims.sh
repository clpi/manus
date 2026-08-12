#!/bin/sh
# Durable view of live agent claims (.agents/session/claims/*.md).
#
# This is a FALLBACK view. The authority for claim atomicity is the duo-bench
# MCP server (duo_dev_claim_acquire / duo_dev_claim_files), exposed from pi as
# the idol__* tools. When MCP is healthy, prefer it. This script only reads
# markdown; it cannot prevent a race with a concurrent session.
set -u
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$repo"
dir=".agents/session/claims"
if [ ! -d "$dir" ]; then
  echo "no claim directory at $dir"
  exit 0
fi
echo "# live claims ($dir)"
echo
for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  agent=$(grep -m1 -iE '^- Agent:' "$f" | tr -d '*' | sed -E 's/^[[:space:]]*-[[:space:]]*[Aa]gent:[[:space:]]*//; s/[[:space:]]*$//')
  scope=$(grep -m1 -iE '^- (Scope|Files locked|Files):' "$f" | tr -d '*' | sed -E 's/^[[:space:]]*-[[:space:]]*(Scope|Files locked|Files):[[:space:]]*//; s/[[:space:]]*$//')
  rel=$(grep -m1 -iE 'Released:' "$f")
  status="active"; [ -n "$rel" ] && status="released"
  printf '%s  %-26s  %s\n' "$status" "${agent:-?}" "$(basename "$f")"
  [ -n "$scope" ] && printf '    %s\n' "$scope"
done | sort
