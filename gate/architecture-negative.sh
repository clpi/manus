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

require_absent() {
    SEEN=$((SEEN + 1))
    n=$(count_in "$2" "$3")
    if [ "$n" -gt 0 ]; then
        bad "$1: found $n forbidden match(es) in $2"
    else
        ok "$1"
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

require_present \
    DEBT-GRAPH-ARG-FILTER-LABELED \
    src/dnir_lower.zig \
    '@debt GRAPH-ARG-EXACT'

require_present \
    DEBT-AMBIGUITY-LABELED \
    src/sema.zig \
    '@debt AMBIGUITY-FAILS'

require_absent \
    NO-FIRST-WINS-SEMANTICS \
    src/sema.zig \
    'first home that declares it wins'

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
    'fn subjectFirstForeignHomeCandidates' \
    1

require_max \
    CONFORMANCE-ENUM-SCOPE \
    src/subject_home.zig \
    'pub const Conformance = enum' \
    1


require_present     CONTROLS-MANIFEST     docs/architecture-negative-controls.md     'GRAPH-FACT-TRUST'

require_present     COMPILER-SOURCE-DEBT     docs/history/compiler-source-debt-projection.md     'bootstrap-debt'

require_present     CENTRAL-AUTHORITY-RULE     docs/architecture-negative-controls.md     'what authority you added'

require_present     ENUMERATION-ORDER-LAW     docs/AGENT_ALIGNMENT.md     'Order may affect cost, never meaning'

require_present     IDOL-NATIVE-MEASURE-ONLY     docs/AGENT_ALIGNMENT.md     'idol-native may measure and falsify. idol owns meaning'

require_present     PIPELINE-REDUCTION-GOAL     docs/AGENT_ALIGNMENT.md     'remove the need for large parts of today'

require_max     NO-DNIR-SECOND-TYPECHECK     src/dnir_lower.zig     'fn exprIsStr|exprIsStr\('     40

require_max \
    NO-SOURCE-IO-BELOW-GRAPH \
    src/dnir_lower.zig \
    'loadSiblingModuleConsts|parseSiblingModule|mergeForeignModuleConstsForFields|mergeForeignModuleRecordsForFields|mergeForeignModuleRecordReturns|mergeAliasModuleConsts|exprCollectModuleFieldAliases|blockCollectModuleFieldAliases|siblingModulePath|siblingRecordReturnExportName' \
    0

require_max \
    CALL-AS-INDEX-FORBIDDEN \
    src/dnir_lower.zig \
    'shouldLowerAsArrayIndex|arrayIndexSite' \
    0

require_max \
    CALL-AS-INDEX-FORBIDDEN-GRAPH \
    src/semantic_graph.zig \
    'aggregateIndexSite|shouldLowerAsArrayIndex' \
    0

require_present \
    GRAPH-RECORD-RETURN-BARRIER \
    src/dnir_lower.zig \
    'if (ctx.require_graph_facts) return false;'

require_absent \
    CALL-INDEX-GATE-REMOVED \
    gate/call-index-assign.sh \
    'call-index-assign'

if [ -x gate/architecture-roadmap.sh ]; then
    SEEN=$((SEEN + 1))
    if sh gate/architecture-roadmap.sh >/dev/null 2>&1; then
        ok 'ARCHITECTURE-ROADMAP'
    else
        bad 'ARCHITECTURE-ROADMAP: gate/architecture-roadmap.sh failed'
    fi
fi

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

if [ -x gate/architecture-companion.sh ]; then
    SEEN=$((SEEN + 1))
    if sh gate/architecture-companion.sh >/tmp/arch-companion.log 2>&1; then
        ok 'ARCHITECTURE-COMPANION'
    else
        bad 'ARCHITECTURE-COMPANION: see /tmp/arch-companion.log'
        sed 's/^/    /' /tmp/arch-companion.log >&2
    fi
fi

printf '\narchitecture-negative gate: %d control(s), %d failure(s)\n' "$SEEN" "$FAILED"
exit "$FAILED"
