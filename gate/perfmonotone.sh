#!/bin/sh
# gate/perfmonotone.sh — PERF-MONOTONE: prior-art matrix and monotonicity contract.
#
#   sh gate/perfmonotone.sh
#
# Exit 0 = the matrix and contract in docs/perf-monotone-program.md carry the
# expected number of rows.  Non-zero = the number of findings.
#
# This is a DOCUMENT gate.  It does not open the compiler; it checks the durable
# program that governs historical compiler exploitation and monotone performance
# admission.

set -u
cd "$(dirname "$0")/.." || exit 2

PROG=docs/perf-monotone-program.md
WANT_MATRIX=15
WANT_CONTRACT=16
FINDINGS=0

bad() { FINDINGS=$((FINDINGS + 1)); printf '  FAIL %s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }

if [ ! -f "$PROG" ]; then
    bad "$PROG is missing"
    printf 'perfmonotone gate: (%s check(s)) %s finding(s)\n' "$((WANT_MATRIX + WANT_CONTRACT))" "$FINDINGS"
    exit 1
fi

# print the block under a `## <heading>` until the next `## ` or EOF.
block() {
    heading="$1"
    file="$2"
    awk -v h="$heading" 'BEGIN{inb=0} /^## / { if (inb) { exit } if ($0 == "## " h) { inb=1; next } } inb { print }' "$file"
}

# count table data rows in a markdown table, skipping the named header and any
# `---` separator.  A 7-column table has 9 `|`-separated fields; this is loose
# enough to tolerate trailing or missing final pipes.
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

matrix=$(block "Compiler Prior Art Matrix" "$PROG")
contract=$(block "Mandatory Performance Monotonicity Contract" "$PROG")

matrix_n=$(printf '%s\n' "$matrix" | count_rows "technique")
contract_n=$(printf '%s\n' "$contract" | count_rows "invariant")

[ "$matrix_n" -eq "$WANT_MATRIX" ] && \
    ok "prior-art matrix: $matrix_n rows" || \
    bad "prior-art matrix: $matrix_n rows, want $WANT_MATRIX"

[ "$contract_n" -eq "$WANT_CONTRACT" ] && \
    ok "monotonicity contract: $contract_n invariants" || \
    bad "monotonicity contract: $contract_n invariants, want $WANT_CONTRACT"

total=$((WANT_MATRIX + WANT_CONTRACT))

if [ "$FINDINGS" -eq 0 ]; then
    printf 'perfmonotone gate: PASS (%s check(s)) %s matrix rows, %s contract invariants\n' \
        "$total" "$matrix_n" "$contract_n"
    exit 0
fi

printf 'perfmonotone gate: (%s check(s)) %s finding(s)\n' "$total" "$FINDINGS"
exit "$FINDINGS"
