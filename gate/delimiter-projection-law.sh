#!/bin/sh
# Architecture gate: () is application; [] is computed projection.
# Parentheses must not be reinterpreted as aggregate indexing after resolution.
#
#   sh gate/delimiter-projection-law.sh

set -eu

root=${DELIMITER_LAW_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-delimiter-law.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

fail() {
    printf 'delimiter-projection-law gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"

canonical=$root/examples/projection_index_assign.id
call_form=$work/call_not_index.id
log=$work/check.log

[ -f "$canonical" ] || fail "missing probe: $canonical"

cat >"$call_form" <<'PROBE'
# arr(2) must not silently index a local table; () is application, not [].
main: i64 = ()
  arr = {0, 0, 0, 0}
  arr(2)
PROBE

set +e
(CDPATH='' cd -- "$root" && "$idol" run "$canonical") >"$log" 2>&1
ec=$?
set -e
if [ "$ec" -ne 42 ]; then
    cat "$log" >&2
    fail "projection_index_assign.id expected exit 42, got $ec"
fi

set +e
(CDPATH='' cd -- "$root" && "$idol" run "$call_form") >"$log" 2>&1
ec=$?
set -e
if [ "$ec" -eq 42 ]; then
    cat "$log" >&2
    fail "arr(2) was lowered as indexing; () must not alias []"
fi

printf 'delimiter-projection-law gate: PASS\n'
