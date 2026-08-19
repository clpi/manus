#!/bin/sh
# gate/canonicality.sh — authority-repair program gate.
#
#   sh gate/canonicality.sh
#
# Exit 0 = the new supreme-law sections and C0 law identities are present,
# AGENTS.md has been reconciled, and the program document is complete.

set -u
cd "$(dirname "$0")/.." || exit 2

LAW=docs/spec/law.md
C0=docs/spec/constitution.md
AGENTS=AGENTS.md
PROG=docs/authority-repair-program.md

WANT_LAW=5
FINDINGS=0

bad() { FINDINGS=$((FINDINGS + 1)); printf '  FAIL %s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }

check_law_section() {
    heading="$1"
    if grep -qF "$heading" "$LAW"; then
        ok "law section: $heading"
    else
        bad "law section missing: $heading"
    fi
}

check_law_section '## 111. SUBJECT-ZERO'
check_law_section '## 112. ANY-DESCRIPTOR-ZERO'
check_law_section '## 113. RESULT-ZERO'
check_law_section '## 114. TEXT/BYTE-SEQUENCE'
check_law_section '## 115. CANONICALITY'

# C0 law identities
for lid in 'law.subject.zero' 'law.any.descriptor.zero' 'law.result.zero' 'law.text.byte' 'law.canonicality'; do
    if grep -qF "id    = \"$lid\"" "$C0"; then
        ok "C0 identity: $lid"
    else
        bad "C0 identity missing: $lid"
    fi
done

# AGENTS.md must no longer endorse @comp.* as canonical
if grep -qF 'Where a directive is unavoidable the canonical spelling is' "$AGENTS"; then
    bad 'AGENTS.md still contains the stale @comp.* directive paragraph'
else
    ok 'AGENTS.md @comp.* paragraph removed'
fi

# Program document must carry both tables
if [ -f "$PROG" ]; then
    if grep -qF '## Final rulings' "$PROG" && \
       grep -qF '## Canonicality status relation' "$PROG"; then
        ok 'authority-repair program has rulings and status relation'
    else
        bad 'authority-repair program missing rulings or status relation'
    fi
else
    bad 'authority-repair program document is missing'
fi

total=$((WANT_LAW + WANT_LAW + WANT_LAW + 1 + 1))

if [ "$FINDINGS" -eq 0 ]; then
    printf 'canonicality gate: PASS (%s check(s)) %s law sections, %s C0 identities, AGENTS + program verified\n' \
        "$total" "$WANT_LAW" "$WANT_LAW"
    exit 0
fi

printf 'canonicality gate: (%s check(s)) %s finding(s)\n' "$total" "$FINDINGS"
exit "$FINDINGS"
