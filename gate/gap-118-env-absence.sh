#!/bin/sh
# GAP-118: environment lookup must not erase absence into empty string.
#
# docs/spec/law.md §2: "Unknown, absent, false, zero, empty, and not-asked are
# distinct." The admitted environment face — os.env[key] computed projection
# under the os world (docs/spec/host.md) — must answer three DISTINGUISHABLE
# outcomes for an absent variable, a variable present and empty, and a variable
# present and nonempty. The probe's exit status IS the outcome: 10 absent,
# 20 present-empty, 30 present-nonempty. Any two outcomes agreeing is the
# GAP-118 erasure, measured, not asserted.
#
# The exercised path is the emitted-C realization (dump-c + cc), the one this
# host executes; DNB004 refuses the direct backend here. The lib/os.id ratchet
# at the bottom pins the named specimen: the erasing wrapper (absent -> "")
# stays deleted.

set -eu

root=${GAP118_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap118.XXXXXX")

# Private scratch root, same reasoning as gate/world-launch.sh: never diff or
# delete inside a /tmp cache every lane on the machine writes.
TMPDIR="$work/scratch"
export TMPDIR
mkdir -p "$TMPDIR"

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'gap-118 env absence gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
command -v "$cc" >/dev/null 2>&1 || fail "C compiler is unavailable: $cc"

cat >"$work/probe.id" <<'EOF'
main: i64 = ()
    v = os.env["G118PROBE"]
    if v == nil
        return 10
    if v == ""
        return 20
    30
EOF

"$idol" dump-c "$work/probe.id" >"$work/probe.c" 2>"$work/dump.log" \
    || fail "dump-c refused the probe (see $work/dump.log)"
"$cc" -o "$work/probe" "$work/probe.c" 2>"$work/cc.log" \
    || fail "emitted C did not compile (see $work/cc.log)"

outcome() {
    label=$1
    shift
    if "$@" >"$work/$label.log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    printf '%s' "$rc"
}

absent=$(outcome absent env -u G118PROBE "$work/probe")
empty=$(outcome empty env G118PROBE= "$work/probe")
nonempty=$(outcome nonempty env G118PROBE=hello "$work/probe")

[ "$absent" -eq 10 ] || fail "absent variable answered $absent, not 10"
[ "$empty" -eq 20 ] || fail "present-empty variable answered $empty, not 20"
[ "$nonempty" -eq 30 ] || fail "present-nonempty variable answered $nonempty, not 30"

# The named specimen stays deleted: lib/os.id must not reintroduce an
# environment reader that answers "" for absence. Text ratchet only — the
# executed probe above is the authoritative evidence.
if grep -q '^getenv' "$root/lib/os.id"; then
    fail 'lib/os.id defines getenv again; the admitted face is os.env[key]'
fi

printf 'gap-118 env absence gate: PASS absent=10 empty=20 nonempty=30\n'
