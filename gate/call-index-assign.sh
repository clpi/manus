#!/bin/sh
# Ratchet: demagix call-form fixed-array index assign/read (arr(2) == arr[2]).
# One aggregate-access semantic edge; () is not ordinary application here.

set -eu

root=${CALL_INDEX_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
probe=$root/examples/call_index_assign.id
log=$(mktemp "${TMPDIR:-/tmp}/idol-call-index.XXXXXX")

cleanup() {
    rm -f "$log"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'call-index-assign gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
[ -f "$probe" ] || fail "missing probe: $probe"

set +e
(CDPATH='' cd -- "$root" && "$idol" run "$probe") >"$log" 2>&1
ec=$?
set -e

if [ "$ec" -ne 42 ]; then
    cat "$log" >&2
    fail "call_index_assign.id expected exit 42, got $ec"
fi

printf 'call-index-assign gate: PASS\n'
