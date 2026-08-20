#!/bin/sh
# gate/architecture-negative.sh — architectural anti-regression controls.
#
#   sh gate/architecture-negative.sh
#
# Exit 0 = no forbidden patterns detected. Non-zero = violation count.
# These checks intentionally fail while known debt remains — do not silence
# them with downstream workarounds.
set -u

ROOT=${ARCHITECTURE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
DNIR="$ROOT/src/dnir_lower.zig"
SEMA="$ROOT/src/sema.zig"
MONOLITH="$ROOT/lib/compiler/monolith.id"
INJECTION="$ROOT/.agents/ARCHITECTURE_INJECTION.md"
CONTROLS="$ROOT/docs/architecture-negative-controls.md"

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'architecture-negative: FAIL %s\n' "$*"
}

ok() {
    printf 'architecture-negative: ok   %s\n' "$*"
}

warn() {
    printf 'architecture-negative: WARN %s\n' "$*"
}

require_file() {
    path=$1
    label=$2
    if [ ! -r "$path" ]; then
        bad "$label missing: $path"
        return 1
    fi
    examined=$((examined + 1))
    return 0
}

grep_file() {
    path=$1
    pattern=$2
    label=$3
    examined=$((examined + 1))
    if grep -Eq "$pattern" "$path"; then
        bad "$label"
        return 1
    fi
    ok "$label"
    return 0
}

require_file "$INJECTION" architecture-injection
require_file "$CONTROLS" architecture-negative-controls
require_file "$DNIR" dnir_lower
require_file "$SEMA" sema


# NO-SOURCE-IO-BELOW-GRAPH — lowering must not re-parse sibling modules
grep_file "$DNIR" 'fn loadSiblingModuleConsts' 'NO-SOURCE-IO-BELOW-GRAPH: loadSiblingModuleConsts forbidden in dnir_lower'
grep_file "$DNIR" 'fn parseSiblingModule' 'NO-SOURCE-IO-BELOW-GRAPH: parseSiblingModule forbidden in dnir_lower'
grep_file "$DNIR" 'mergeForeignModuleConstsForFields' 'NO-SOURCE-IO-BELOW-GRAPH: mergeForeignModuleConstsForFields forbidden in dnir_lower'
grep_file "$DNIR" 'mergeForeignModuleRecordsForFields' 'NO-SOURCE-IO-BELOW-GRAPH: mergeForeignModuleRecordsForFields forbidden in dnir_lower'
grep_file "$DNIR" 'mergeForeignModuleRecordReturns' 'NO-SOURCE-IO-BELOW-GRAPH: mergeForeignModuleRecordReturns forbidden in dnir_lower'
grep_file "$DNIR" 'readFileAlloc' 'NO-SOURCE-IO-BELOW-GRAPH: readFileAlloc forbidden in dnir_lower'
grep_file "$DNIR" 'readFile\(' 'NO-SOURCE-IO-BELOW-GRAPH: readFile forbidden in dnir_lower'
grep_file "$DNIR" 'parseFile\(' 'NO-SOURCE-IO-BELOW-GRAPH: parseFile forbidden in dnir_lower'

# DELIMITER-CLOSURE — graph must not treat () as [] projection
grep_file "$ROOT/src/semantic_graph.zig" 'break :blk .{ .obj = c.func, .key = c.args[0] };' 'DELIMITER-CLOSURE: aggregateIndexSite must not accept .call'

# GRAPH-RECORD-RETURN-ONE — export map cannot bypass graph-required paths
examined=$((examined + 1))
if grep -Fq 'if (ctx.require_graph_facts) return false;' "$DNIR" && grep -Fq 'fn tryAssignRecordCallFromExportMap' "$DNIR"; then
    ok 'GRAPH-RECORD-RETURN-ONE export-map guard present'
else
    bad 'GRAPH-RECORD-RETURN-ONE: tryAssignRecordCallFromExportMap must refuse when require_graph_facts'
fi

# GRAPH-FACT-TRUST / NO-DNIR-AST-FILTER
grep_file "$DNIR" 'fn filterCheckedCallOperands\(' 'GRAPH-FACT-TRUST: filterCheckedCallOperands must be removed'
grep_file "$DNIR" 'fn callValueForApplication\(' 'GRAPH-FACT-TRUST: callValueForApplication must be removed'
grep_file "$DNIR" 'fn filterCallArgumentOperands\(' 'GRAPH-FACT-TRUST: filterCallArgumentOperands must be removed'
grep_file "$DNIR" 'fn filterRecordAssignOperands\(' 'GRAPH-FACT-TRUST: filterRecordAssignOperands must be removed'

# NO-NAME-RECORD-INFERENCE
grep_file "$DNIR" 'expandableRecordForName' 'NO-NAME-RECORD-INFERENCE: expandableRecordForName must not infer records from local names'

# NO-RECORD-HISTORY-INFERENCE — warn-only until graph publishes field-place facts
examined=$((examined + 1))
if grep -Fq 'fn recordFieldsPresent(' "$DNIR"; then
    warn 'NO-RECORD-HISTORY-INFERENCE: recordFieldsPresent still infers from lowering history (debt)'
else
    ok 'NO-RECORD-HISTORY-INFERENCE: recordFieldsPresent removed'
fi

# RESOLUTION-ORDER-INDEPENDENT / NO-HOME-SEMANTIC-PRIORITY
grep_file "$SEMA" 'first home that declares it wins' 'NO-HOME-SEMANTIC-PRIORITY: first-wins home ordering forbidden'
grep_file "$SEMA" 'subjectFirstForeignHomesForConformance' 'NO-HOME-SEMANTIC-PRIORITY: conformance→home registry forbidden'
grep_file "$SEMA" 'subjectFirstForeignHomeCandidates' 'NO-HOME-SEMANTIC-PRIORITY: ordered home candidate registry forbidden'
# RESOLUTION-PERMUTATION — home enumeration order must not be semantic law
examined=$((examined + 1))
if grep -Fq 'Sorted alphabetically so collection order is never semantic' "$SEMA"; then
    ok 'RESOLUTION-PERMUTATION: foreign_module_homes documents order independence'
else
    bad 'RESOLUTION-PERMUTATION: foreign_module_homes must document order independence'
fi
examined=$((examined + 1))
if grep -Fq 'RESOLUTION-PERMUTATION resolveUniqueForeignRelations does not first-win' "$SEMA"; then
    ok 'RESOLUTION-PERMUTATION: unit test must guard non-first-wins resolution'
else
    bad 'RESOLUTION-PERMUTATION: unit test must guard non-first-wins resolution'
fi

# GRAPH-ARG-EXACT producer hook must exist
examined=$((examined + 1))
if grep -Fq 'verifyCheckedApplicationOperandPacks' "$ROOT/src/semantic_graph.zig"; then
    ok 'GRAPH-ARG-EXACT: verifyCheckedApplicationOperandPacks present in graph lift'
else
    bad 'GRAPH-ARG-EXACT: verifyCheckedApplicationOperandPacks missing from graph lift'
fi

# NO-BACKEND-TYPE-GUESS — warn-only debt marker until descriptors replace it
examined=$((examined + 1))
if grep -Fq 'fn exprIsStr(' "$DNIR"; then
    warn 'NO-BACKEND-TYPE-GUESS: exprIsStr still re-derives string shape in lowering (debt)'
else
    ok 'NO-BACKEND-TYPE-GUESS: exprIsStr removed from lowering'
fi

# RETIRED-TYPE-ALIAS-PROJECTION — lib/compiler parser must not emit typedecl/(type …)
PARSER="$ROOT/lib/compiler/parser.id"
require_file "$PARSER" parser.id
grep_file "$PARSER" 'return "\(typedecl' 'RETIRED-TYPE-ALIAS-PROJECTION: typedecl emission forbidden in lib/compiler/parser.id'
grep_file "$PARSER" '" \(type " .. proj_type' 'RETIRED-TYPE-ALIAS-PROJECTION: (type …) wrapper forbidden in lib/compiler/parser.id'
grep_file "$ROOT/lib/compiler/lexer.id" 'word(start, n, "alias") return 51' 'RETIRED-TYPE-ALIAS-PROJECTION: alias keyword forbidden in lib/compiler/lexer.id'

# MONOLITH-PROBE-ONLY
if [ -r "$MONOLITH" ]; then
    examined=$((examined + 1))
    if grep -Fq 'capability probe' "$MONOLITH"; then
        ok 'MONOLITH-PROBE-ONLY: monolith.id marked as probe'
    else
        bad 'MONOLITH-PROBE-ONLY: monolith.id must declare capability-probe status in header'
    fi
fi

if [ "$violations" -eq 0 ]; then
    printf 'architecture-negative gate: PASS (%d check(s))\n' "$examined"
    exit 0
fi

printf 'architecture-negative gate: FAIL %d violation(s) in %d check(s)\n' "$violations" "$examined"
exit "$violations"
