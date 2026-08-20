#!/bin/sh
# gate/architecture-negative.sh — architecture-negative controls (2026-08-20 mandate).
#
#   sh gate/architecture-negative.sh
#
# Exit 0 = every control is at or below its pinned debt ceiling.
# Non-zero = the number of controls that regressed or broke.

set -u
cd "$(dirname "$0")/.." || exit 2

FAILED=0
SEEN=0

bad() {
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' "$1"
}

ok() {
    printf '  ok    %s\n' "$1"
}

count_in() {
    grep -E "$2" "$1" 2>/dev/null | wc -l | tr -d ' '
}

require_max() {
    SEEN=$((SEEN + 1))
    n=$(count_in "$2" "$3")
    if [ "$n" -gt "$4" ]; then
        bad "$1: found $n (max $4) in $2"
    else
        ok "$1 ($n/$4)"
    fi
}

require_present() {
    SEEN=$((SEEN + 1))
    if grep -Fq "$3" "$2"; then
        ok "$1"
    else
        bad "$1: missing from $2"
    fi
}

printf 'architecture-negative gate: mandate + debt ratchets\n\n'

require_present \
    MANDATE-PRESENT \
    docs/AGENT_ALIGNMENT.md \
    'A passing fixture is not the objective'

require_present \
    REVIEW-QUESTION \
    docs/AGENT_ALIGNMENT.md \
    'Review question (required before every commit)'

require_max \
    NO-DNIR-AST-FILTER \
    src/dnir_lower.zig \
    'filterCheckedCallOperands|callValueForApplication' \
    6

require_max \
    NO-NAME-RECORD-INFERENCE \
    src/dnir_lower.zig \
    'expandableRecordForName|recordFieldsPresent' \
    10

require_max \
    NO-HOME-PRIORITY-DISPATCH \
    src/sema.zig \
    'subjectFirstForeignHomeCandidates|first home that declares it wins' \
    3

require_max \
    CONFORMANCE-ENUM-SCOPE \
    src/subject_home.zig \
    'pub const Conformance = enum' \
    1

require_present \
    MONOLITH-PROBE-LABELED \
    lib/compiler/monolith.id \
    'capability probe'

if [ -f ../idol-native/docs/self-hosting-scoreboard.md ]; then
    SEEN=$((SEEN + 1))
    if grep -Fq 'HISTORICAL EVIDENCE' ../idol-native/docs/self-hosting-scoreboard.md; then
        ok 'SCOREBOARD-HISTORICAL-LABEL'
    else
        bad 'SCOREBOARD-HISTORICAL-LABEL: idol-native scoreboard missing classification banner'
    fi
fi

printf '\narchitecture-negative gate: %d control(s), %d failure(s)\n' "$SEEN" "$FAILED"
exit "$FAILED"
