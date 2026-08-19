#!/bin/sh
# gate/researchgap.sh — research GAP admission: map every frontier idea to C0.
#
#   sh gate/researchgap.sh
#
# Exit 0 = docs/research-gap-admission.md carries the expected schema, mapping,
# rewrites, and horizons.  Non-zero = the number of findings.

set -u
cd "$(dirname "$0")/.." || exit 2

PROG=docs/research-gap-admission.md
WANT_SCHEMA=14
WANT_MAP=23
WANT_REWRITES=10
WANT_HORIZONS=4
FINDINGS=0

bad() { FINDINGS=$((FINDINGS + 1)); printf '  FAIL %s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }

if [ ! -f "$PROG" ]; then
    bad "$PROG is missing"
    printf 'researchgap gate: (%s check(s)) %s finding(s)\n' "$((WANT_SCHEMA + WANT_MAP + WANT_REWRITES + WANT_HORIZONS))" "$FINDINGS"
    exit 1
fi

block() {
    heading="$1"
    file="$2"
    awk -v h="$heading" 'BEGIN{inb=0} /^## / { if (inb) { exit } if ($0 == "## " h) { inb=1; next } } inb { print }' "$file"
}

count_rows() {
    header="$1"
    awk -F'|' -v h="$header" '
        NF >= 3 {
            cell = $2
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            if (cell != "" && cell != h && cell !~ /^-+$/) {
                count++
            }
        }
        END { print count + 0 }
    '
}

schema=$(block "Admission schema" "$PROG")
map=$(block "Structural mapping" "$PROG")
rewrites=$(block "Concrete rewrites" "$PROG")
horizons=$(block "Execution horizons" "$PROG")

schema_n=$(printf '%s\n' "$schema" | count_rows "Field")
map_n=$(printf '%s\n' "$map" | count_rows "Research capability")
rewrites_n=$(printf '%s\n' "$rewrites" | count_rows "Current GAP language")
horizons_n=$(printf '%s\n' "$horizons" | count_rows "Horizon")

[ "$schema_n" -eq "$WANT_SCHEMA" ] && \
    ok "admission schema: $schema_n fields" || \
    bad "admission schema: $schema_n fields, want $WANT_SCHEMA"

[ "$map_n" -eq "$WANT_MAP" ] && \
    ok "structural mapping: $map_n rows" || \
    bad "structural mapping: $map_n rows, want $WANT_MAP"

[ "$rewrites_n" -eq "$WANT_REWRITES" ] && \
    ok "concrete rewrites: $rewrites_n rows" || \
    bad "concrete rewrites: $rewrites_n rows, want $WANT_REWRITES"

[ "$horizons_n" -eq "$WANT_HORIZONS" ] && \
    ok "execution horizons: $horizons_n rows" || \
    bad "execution horizons: $horizons_n rows, want $WANT_HORIZONS"

total=$((WANT_SCHEMA + WANT_MAP + WANT_REWRITES + WANT_HORIZONS))

if [ "$FINDINGS" -eq 0 ]; then
    printf 'researchgap gate: PASS (%s check(s)) %s schema, %s map, %s rewrites, %s horizons\n' \
        "$total" "$schema_n" "$map_n" "$rewrites_n" "$horizons_n"
    exit 0
fi

printf 'researchgap gate: (%s check(s)) %s finding(s)\n' "$total" "$FINDINGS"
exit "$FINDINGS"
