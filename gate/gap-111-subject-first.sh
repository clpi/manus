#!/bin/sh
# GAP-111 ratchet: explicit `iter.map(xs, f)` must check; unknown subject-first
# relations still fail closed. Ambiguous `xs:map(f)` is architecture-companion.

set -eu

root=${GAP111_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap111.XXXXXX")

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'gap-111-subject-first gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"

canonical=$work/canonical.id
unknown=$work/unknown.id
log=$work/check.log

cat >"$canonical" <<'PROBE'
twice = (x) x * 2
xs = {1, 2, 3}
main: i64 = ()
    r = iter.map(xs, twice)
    0
PROBE

cat >"$unknown" <<'PROBE'
main: i64 = ()
    s = "abcd"
    r = s:zzznotarelation()
    0
PROBE

if ! (CDPATH='' cd -- "$root" && "$idol" check "$canonical") >"$log" 2>&1; then
    cat "$log" >&2
    fail "canonical iter.map(xs, twice) was not admitted"
fi

if (CDPATH='' cd -- "$root" && "$idol" check "$unknown") >"$log" 2>&1; then
    cat "$log" >&2
    fail "unknown subject-first relation was admitted"
fi

grep -Fq "zzznotarelation" "$log" \
    || fail "unknown relation refusal did not name zzznotarelation"

printf 'gap-111-subject-first gate: PASS\n'
