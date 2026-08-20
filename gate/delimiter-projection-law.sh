#!/bin/sh
# Delimiter closure: [] is computed projection; () is application.
set -eu
root=${DELIMITER_PROJECTION_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
bracket_probe=$root/examples/typed_array_bracket_assign.id
call_probe=$root/examples/call_index_assign.id
log=$(mktemp "${TMPDIR:-/tmp}/idol-delimiter-projection.XXXXXX")
cleanup() { rm -f "$log"; }
trap cleanup EXIT INT TERM
fail() { printf 'delimiter-projection-law gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"
[ -f "$bracket_probe" ] || fail "missing probe: $bracket_probe"
[ -f "$call_probe" ] || fail "missing probe: $call_probe"
set +e
(CDPATH='' cd -- "$root" && "$idol" run "$bracket_probe") >"$log" 2>&1
ec=$?
set -e
if [ "$ec" -ne 42 ]; then cat "$log" >&2; fail "typed_array_bracket_assign.id expected exit 42, got $ec"; fi
set +e
(CDPATH='' cd -- "$root" && "$idol" run "$call_probe") >"$log" 2>&1
ec=$?
set -e
if [ "$ec" -eq 42 ]; then cat "$log" >&2; fail "call_index_assign.id must not treat arr(i) as indexing"; fi
printf 'delimiter-projection-law gate: PASS\n'
