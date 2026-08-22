#!/bin/sh
# gate/grammar-projection.sh — the grammar-role counterfactual.
#
# GAP-134 / law.grammar.one: lib/compiler/token.id is the ONE executable
# grammar-fact owner. src/grammar_role_table.zig (host bridge, read by the
# production parser) and lib/token/grammarrole.id (Idol projection) are its
# generated outputs.
#
# A tracked generated artifact that may drift from its owner is not generated:
# damaging the owner then changes NOTHING until somebody hand-regenerates, and
# "the grammar is Idol owned" becomes a claim with no counterfactual. That is
# exactly what src/lexer_tokenize.c did in this tree (build.zig, lexer-artifact).
#
# This step regenerates and fails unless both artifacts are byte-identical.
# It restores the tracked bytes either way, so a failing gate never leaves a
# half-regenerated tree behind.
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2

IDOL=${IDOL-./zig-out/bin/idol}
OWNER=lib/compiler/token.id
ZIGOUT=src/grammar_role_table.zig
IDOUT=lib/token/grammarrole.id

[ -x "$IDOL" ] || { printf 'grammar projection: FAIL — compiler is not executable: %s\n' "$IDOL"; exit 2; }
[ -f "$OWNER" ] || { printf 'grammar projection: FAIL — missing owner %s\n' "$OWNER"; exit 2; }

keep=$(mktemp -d -t idol-grammar-projection) || exit 2
cp "$ZIGOUT" "$keep/zig" || exit 2
cp "$IDOUT" "$keep/id" || exit 2

"$IDOL" run "$OWNER" >"$keep/log" 2>&1
run_status=$?

status=0
if [ "$run_status" -ne 0 ]; then
    printf 'grammar projection: FAIL — the Idol owner did not run (exit %s)\n' "$run_status"
    sed -n '1,20p' "$keep/log"
    status=1
else
    if cmp -s "$ZIGOUT" "$keep/zig"; then
        printf 'grammar projection: %s regenerates byte-identically\n' "$ZIGOUT"
    else
        printf 'grammar projection: FAIL — %s drifted from %s\n' "$ZIGOUT" "$OWNER"
        status=1
    fi
    if cmp -s "$IDOUT" "$keep/id"; then
        printf 'grammar projection: %s regenerates byte-identically\n' "$IDOUT"
    else
        printf 'grammar projection: FAIL — %s drifted from %s\n' "$IDOUT" "$OWNER"
        status=1
    fi
fi

cp "$keep/zig" "$ZIGOUT"
cp "$keep/id" "$IDOUT"
rm -rf "$keep"
exit "$status"
