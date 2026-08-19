#!/bin/sh
# Regression gate for semantic decisions already moved toward the one graph.
#
# Exit 0 means the landed slices have not regressed. OPEN lines are deliberate:
# they name remaining GAP-201 bridges and are not converted into false failures
# until their graph-owned replacements exist.
set -u

ROOT=${SEMANTIC_GRAPH_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TABLE="$ROOT/src/table_apply.zig"
PLACE="$ROOT/src/place.zig"
CURSOR="$ROOT/src/source_cursor.zig"
LOWER="$ROOT/src/dnir_lower.zig"
GRAPH="$ROOT/src/semantic_graph.zig"
BOOTSTRAP="$ROOT/src/native_bootstrap.zig"
AST="$ROOT/src/ast.zig"
GAP="$ROOT/gaps/GAP-201.md"

violations=0
examined=0
open=0

bad() {
    violations=$((violations + 1))
    printf 'semantic graph gate: FAIL %s\n' "$*"
}

need() {
    path=$1
    if [ ! -r "$path" ]; then
        bad "missing or unreadable $path"
        return 1
    fi
    examined=$((examined + 1))
    return 0
}

has() {
    path=$1
    text=$2
    label=$3
    grep -Fq "$text" "$path" || bad "$label"
}

lacks() {
    path=$1
    text=$2
    label=$3
    if grep -Fq "$text" "$path"; then bad "$label"; fi
}

finding() {
    path=$1
    text=$2
    label=$3
    if grep -Fq "$text" "$path"; then
        open=$((open + 1))
        printf 'semantic graph gate: OPEN %s\n' "$label"
    fi
}

for path in "$TABLE" "$PLACE" "$CURSOR" "$LOWER" "$GRAPH" "$BOOTSTRAP" "$AST" "$GAP"; do
    need "$path"
done

if [ -r "$TABLE" ]; then
    has "$TABLE" '`()` is ordinary application and `[]` is computed/indexed projection.' \
        'table ingress no longer states the call/index split'
    lacks "$TABLE" 'active_names' 'process-global name census returned to table ingress'
    lacks "$TABLE" 'calleeIsArray' 'type-directed call-to-index classifier returned'
    lacks "$TABLE" 'positionalResultDepth' 'return-type call-to-index classifier returned'
    lacks "$TABLE" 'array_types' 'parallel array-call registry returned'
    has "$TABLE" 'ordinary parenthesized call remains application' \
        'ordinary-call identity control disappeared'
    has "$TABLE" 'bracket projection remains projection' \
        'bracket-projection identity control disappeared'
    has "$TABLE" 'user-bound env remains application' \
        'ambient-world shadowing control disappeared'
    finding "$TABLE" 'type_map: *const sema.TypeMap' \
        'table ingress still exposes an inert sema.TypeMap compatibility parameter'
fi

if [ -r "$PLACE" ]; then
    has "$PLACE" 'Only `collection` and `record` are produced.' \
        'aggregate-only producer contract disappeared'
    lacks "$PLACE" 'break :blk .scalar' 'scalar bindings are being produced as places again'
    lacks "$PLACE" 'break :blk .parameter' 'parameters are being produced as places again'
    lacks "$PLACE" 'break :blk .home' 'homes are being produced as places again'
    lacks "$PLACE" 'shape = .parameter' 'parameter place production returned'
    lacks "$PLACE" 'shape = .home' 'home place production returned'
    has "$PLACE" 'brackets are the only computed projection face' \
        'place delimiter control disappeared'
    has "$PLACE" 'an ordinary call is not an indexed read' \
        'place call/index negative control disappeared'
    has "$PLACE" 'scalar values, parameters and homes are not places' \
        'rejected place-ontology control disappeared'
fi

if [ -r "$CURSOR" ]; then
    has "$CURSOR" 'self.bytes.len' 'source cursor lost O(1) exact byte length'
    lacks "$CURSOR" 'strlen' 'source cursor performs repeated C-string length work'
fi

# Remaining exact P0 seams. They stay visible on every run, but the gate does
# not demand deletion before their graph-owned producer/consumer replacement is
# present; doing so would convert fail-closed compilation into silent guessing.
if [ -r "$LOWER" ]; then
    finding "$LOWER" 'const OccurrenceBridge' \
        'AST pointer to application-id occurrence bridge remains'
    finding "$LOWER" 'applicationFace(' \
        'lowering still reconstructs relation faces from AST provenance'
fi
if [ -r "$GRAPH" ]; then
    finding "$GRAPH" 'ast_ref' \
        'semantic graph still carries Phase-1 AST provenance as a live bridge'
fi
if [ -r "$BOOTSTRAP" ]; then
    finding "$BOOTSTRAP" 'recognizeName' \
        'bootstrap application meaning is still classified from source names'
fi
if [ -r "$AST" ]; then
    finding "$AST" 'use_simple_loop_fold' \
        'optimizer eligibility/result payloads still live on AST FuncBody'
fi

if [ -r "$GAP" ]; then
    has "$GAP" 'OccurrenceBridge' 'GAP-201 lost the occurrence-bridge deletion witness'
    has "$GAP" 'Physical-only DNIR' 'GAP-201 lost the physical-only DNIR objective'
fi

if [ "$examined" -eq 0 ]; then bad 'examined zero files'; fi

if [ "$violations" -eq 0 ]; then
    printf 'semantic graph gate: PASS (%s file(s), %s OPEN bridge class(es))\n' "$examined" "$open"
else
    printf 'semantic graph gate: FAIL (%s violation(s), %s file(s), %s OPEN bridge class(es))\n' \
        "$violations" "$examined" "$open"
fi
exit "$violations"
