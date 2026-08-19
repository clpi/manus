#!/bin/sh
# gate/corpus-status.sh — census of .id teaching-status headers.
#
#   sh gate/corpus-status.sh
#
# Reports the count of .id files and the number missing a
# `## TEACHING-STATUS:` header in the first four lines. Prints the first
# missing paths for visibility. A non-zero exit means the census could not run.

set -u
cd "$(dirname "$0")/.." || exit 2

WORK=$(mktemp -t idol-corpus-status)
trap 'rm -f "$WORK"' EXIT

find examples gate lib scripts tools -name '*.id' -type f 2>/dev/null | sort >"$WORK"

total=$(wc -l <"$WORK" | tr -d ' ')
[ "$total" -gt 0 ] || { printf 'corpus-status gate: FAIL — no .id files examined\n' ; exit 2; }

missing=0
missing_list=""
while IFS= read -r f; do
    if ! head -n 4 "$f" | grep -q '^## TEACHING-STATUS:'; then
        missing=$((missing + 1))
        if [ "$missing" -le 12 ]; then
            missing_list="$missing_list    $f\n"
        fi
    fi
done <"$WORK"

printf 'corpus-status gate: %s total, %s missing TEACHING-STATUS header\n' "$total" "$missing"
if [ "$missing" -gt 0 ]; then
    printf '  first missing:\n'
    printf '%b' "$missing_list"
fi

exit 0
