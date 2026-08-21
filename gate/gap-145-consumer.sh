#!/bin/sh
# gate/gap-145-consumer.sh — quoted literals must not collapse to `.str` blindly.
#
# GAP-145 acceptance requires consumers to observe producer quote identity.
# This gate ratchets the shared helper and forbids reintroducing bare
# `.quoted => .str` in sema/codegen typing paths.
set -u

ROOT=${GAP145_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TYPES="$ROOT/src/types.zig"
SEMA="$ROOT/src/sema.zig"
CODEGEN="$ROOT/src/codegen.zig"
AST="$ROOT/src/ast.zig"
DNIR="$ROOT/src/dnir_lower.zig"

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'gap-145 consumer gate: FAIL %s\n' "$*"
}

has() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if ! grep -Fq "$pattern" "$file"; then
        bad "$msg"
    fi
}

forbid() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if grep -Fq "$pattern" "$file"; then
        bad "$msg"
    fi
}

has "$AST" 'pub fn quotedLiteralIsByteSequence' \
    'ast.zig lost quotedLiteralIsByteSequence helper'
has "$TYPES" 'pub fn quotedLiteralType' \
    'types.zig lost quotedLiteralType helper'
has "$SEMA" 'types.quotedLiteralType(lit.quote)' \
    'sema.zig must type quoted literals via quotedLiteralType'
has "$CODEGEN" 'types.quotedLiteralType(lit.quote)' \
    'codegen.zig must recover quoted literal types via quotedLiteralType'
has "$DNIR" 'types.quotedLiteralType(lit.quote)' \
    'dnir_lower.zig must type quoted globals via quotedLiteralType'

forbid "$SEMA" '.quoted => .str,' \
    'sema.zig reintroduced bare `.quoted => .str` collapse'
forbid "$CODEGEN" '.quoted => .str,' \
    'codegen.zig reintroduced bare `.quoted => .str` collapse'
forbid "$DNIR" '.quoted => .str,' \
    'dnir_lower.zig reintroduced bare `.quoted => .str` collapse'

if [ "$violations" -eq 0 ]; then
    printf 'gap-145 consumer gate: PASS (%d check(s))\n' "$examined"
    exit 0
fi

printf 'gap-145 consumer gate: FAIL (%d violation(s), %d check(s))\n' "$violations" "$examined"
exit 1
