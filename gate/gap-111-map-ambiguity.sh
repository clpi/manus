#!/bin/sh
# Architecture companion: xs:map must be ambiguous while iter and table both
# declare `map` without descriptor/world discrimination — never first-wins.
#
#   sh gate/gap-111-map-ambiguity.sh

set -eu

root=${GAP111_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap111-amb.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

fail() {
    printf 'gap-111-map-ambiguity gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"

ambiguous=$work/ambiguous.id
log=$work/check.log

cat >"$ambiguous" <<'PROBE'
twice = (x) x * 2
xs = {1, 2, 3}
main: i64 = ()
    r = xs:map(twice)
    0
PROBE

if (CDPATH='' cd -- "$root" && "$idol" check "$ambiguous") >"$log" 2>&1; then
    cat "$log" >&2
    fail "xs:map(twice) was admitted despite duplicate map in iter and table"
fi

grep -Fq 'ambiguous subject-first relation' "$log" \
    || fail "expected explicit ambiguity refusal for xs:map, not silent first-wins"

printf 'gap-111-map-ambiguity gate: PASS\n'
