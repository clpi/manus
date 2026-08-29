#!/bin/sh
# coord/cron/migrate-private-prefixes.sh — one-pass script migration
# for *.id files: drop the leading underscore from `_xxx` private-
# prefix identifiers per docs/spec/canonical.md §9 ("native
# underscore identifiers are zero").
#
# USAGE:
#   migrate-private-prefixes.sh <file.id> [<file.id> ...]
#
# Mechanical, deterministic, no LLM needed. Designed to be called from
# the overnight pump for spec-* tickets.

set -u

migrate_one() {
  local f="$1"
  local log="${2:-/dev/stdout}"

  # Find all _xxx identifiers in this file
  local ids
  ids=$(grep -oE "_[a-z][a-z0-9_]+" "$f" 2>/dev/null | sort -u)
  [ -z "$ids" ] && { printf 'migrate: %s: no _xxx, skipping\n' "$f" >>"$log"; return 0; }

  local renamed=0
  local skipped=0
  for id in $ids; do
    local newname=${id#_}
    # Check if newname already exists in file (other than as part of $id)
    if grep -qE "[^a-zA-Z_0-9]$newname[^a-zA-Z_0-9]" "$f" 2>/dev/null; then
      printf 'migrate: %s: COLLISION on %s -> %s, skipping\n' "$f" "$id" "$newname" >>"$log"
      skipped=$((skipped + 1))
      continue
    fi
    # Apply rename: word-boundary replacement
    sed -i "s/\\b$id\\b/$newname/g" "$f"
    renamed=$((renamed + 1))
  done
  printf 'migrate: %s: %d renamed, %d skipped\n' "$f" "$renamed" "$skipped" >>"$log"
  return 0
}

ok=0
fail=0
for f in "$@"; do
  if migrate_one "$f"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done

printf 'migrate: total: %d ok, %d fail\n' "$ok" "$fail"
exit $fail
