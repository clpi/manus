#!/bin/sh
# gate/canonicality.sh — authority repair program gate.
#
#   sh gate/canonicality.sh
#
# Exit 0 = the five new supreme-law sections are present, AGENTS.md has been
# reconciled against them, and the authority-repair program carries the expected
# canonicality-status and closed-class row counts.  Non-zero = the finding count.

set -u
cd "$(dirname "$0")/.." || exit 2

LAW=docs/spec/law.md
AGENTS=AGENTS.md
PROG=docs/authority-repair-program.md

WANT_LAW=5
WANT_STATUS=7
WANT_CLASS=13
FINDINGS=0

bad() { FINDINGS=$((FINDINGS + 1)); printf '  FAIL %s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }

# Law sections
check_law_section() {
    heading="$1"
    if grep -qF "$heading" "$LAW"; then
        ok "law section: $heading"
    else
        bad "law section missing: $heading"
    fi
}

check_law_section '## 111. VOID is not a source descriptor'
check_law_section '## 112. SELF-ZERO'
check_law_section '## 113. ANY'
check_law_section '## 114. BYTES'
check_law_section '## 115. CANONICALITY'

# AGENTS.md must no longer endorse @comp.* as canonical
if grep -qF 'Where a directive is unavoidable the canonical spelling is' "$AGENTS"; then
    bad 'AGENTS.md still contains the stale @comp.* directive paragraph'
else
    ok 'AGENTS.md @comp.* paragraph removed'
fi

# The program document must exist and carry its two tables.
if [ -f "$PROG" ]; then
    if grep -qF '## Canonicality status relation' "$PROG" && \
       grep -qF '## Closed classes and their owners' "$PROG"; then
        ok 'authority-repair program has status and class tables'
    else
        bad 'authority-repair program missing status or class table'
    fi
else
    bad 'authority-repair program document is missing'
fi

total=$((WANT_LAW + 2))

if [ "$FINDINGS" -eq 0 ]; then
    printf 'canonicality gate: PASS (%s check(s)) %s law sections, program tables present\n' \
        "$total" "$WANT_LAW"
    exit 0
fi

printf 'canonicality gate: (%s check(s)) %s finding(s)\n' "$total" "$FINDINGS"
exit "$FINDINGS"
