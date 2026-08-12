#!/bin/sh
# List OPEN P0 gaps and their filed-by owner. Until GAP-131 closes, the
# session-start P0 summary is incomplete; this scan plus the exact gap files
# are the routing evidence. Pattern matches tools/devnode/orient.
set -eu
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$repo"
printf '# open P0 gaps\n\n'
n=0
for gap in gaps/GAP-*.md; do
  [ -e "$gap" ] || continue
  header="$(sed -n '1,8p' "$gap")"
  if printf '%s\n' "$header" | grep -Eiq '^\*\*Status:\*\*[[:space:]]*(OPEN|REOPENED)([[:space:].(:!---]|$)' &&
     printf '%s\n' "$header" | grep -Eiq '^\*\*(Status|Priority):\*\*.*P0'; then
    filed=$(printf '%s\n' "$header" | grep -m1 -iE 'Filed by:' | tr -d '*' | sed -E 's/.*[Ff]iled by:[[:space:]]*//; s/[[:space:]]*$//')
    kind=$(printf '%s\n' "$header" | grep -m1 -iE 'Kind:' | tr -d '*' | sed -E 's/.*[Kk]ind:[[:space:]]*//; s/[[:space:]]*$//')
    printf '  %-16s %-26s %s\n' "$gap" "${filed:-?}" "${kind:-}"
    n=$((n + 1))
  fi
done
printf '\ncount: %s\n' "$n"
