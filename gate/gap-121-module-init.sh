#!/bin/sh
# GAP-121: a module's initialization must reach the consumer that reads it.
#
# The gap's filed counterexample was a static consumer with no dependency edge
# to its module's initializer. The current tree carries the same defect one
# layer quieter: the module-global STORAGE is emitted and its INITIALIZER is
# not, so the consumer reads a `__bss` zero and the program exits with a value
# its source never computes. That is a silent wrong answer, which is why this
# gate executes the programs and reads their exit status rather than grepping
# the emitted C for a declaration.
#
# THE MEASUREMENT IS AN AGREEMENT, NOT A CONSTANT. The same module fact is
# spelled three ways — the canonical declaration `global base = 40`, the
# file-scope `local base = 40`, and the compatibility assign `base = 40` — and
# each is consumed from a SEPARATE program through `<home>.pick(2)`. All three must
# answer 42. Only the assign spelling did before this gate existed; the two
# declaration faces answered 2, so a source spelling was selecting the
# realization after resolution had already agreed on the value.
#
# The same-file arm is the positive control: it proves 42 is reachable at all on
# this host, so a green cross-module arm cannot be green by accident.
#
# The negative control is the class this gap still owns. A module global whose
# initializer is NOT a load-time constant has no realized initializer here, and
# `law.fallback.zero` forbids answering with the zero word. That arm requires a
# REFUSAL — never a silent value, and never a wrong one.
#
# The exercised path is the emitted-C bootstrap bridge (dump-c + cc), the one
# this host executes; DNB004 refuses the direct backend on non-macOS hosts.

set -eu

root=${GAP121_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap121.XXXXXX")

# Private scratch root, same reasoning as gate/gap-118-env-absence.sh: never
# diff or delete inside a /tmp cache every lane on the machine writes.
TMPDIR="$work/scratch"
export TMPDIR
mkdir -p "$TMPDIR"

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'gap-121 module init gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"
command -v "$cc" >/dev/null 2>&1 || fail "C compiler is unavailable: $cc"

# One module fact, three source faces, each in its own home so the consumer
# programs cannot share storage by accident.
cat >"$work/declared.id" <<'EOF'
global base = 40

pick: i64 = (n: i64)
  base + n
EOF

cat >"$work/scoped.id" <<'EOF'
local base = 40

pick: i64 = (n: i64)
  base + n
EOF

cat >"$work/assigned.id" <<'EOF'
base = 40

pick: i64 = (n: i64)
  base + n
EOF

# The class this gap still owns: the value is computed, not placed.
cat >"$work/computed.id" <<'EOF'
seed: i64 = ()
  40

global base: i64 = seed()

pick: i64 = (n: i64)
  base + n
EOF

for home in declared scoped assigned computed; do
    cat >"$work/use_$home.id" <<EOF
main: i64 = ()
  $home.pick(2)
EOF
done

# The positive control: the identical relation with no module boundary at all.
cat >"$work/same.id" <<'EOF'
global base = 40

pick: i64 = (n: i64)
  base + n

main: i64 = ()
  pick(2)
EOF

answer() {
    label=$1
    src=$2
    ( cd "$work" && "$idol" dump-c "$src" ) >"$work/$label.c" 2>"$work/$label.dump.log" \
        || { printf 'refused'; return 0; }
    "$cc" -o "$work/$label" "$work/$label.c" 2>"$work/$label.cc.log" \
        || { printf 'uncompilable'; return 0; }
    if "$work/$label" >"$work/$label.run.log" 2>&1; then
        printf '%s' 0
    else
        printf '%s' "$?"
    fi
}

same=$(answer same same.id)
[ "$same" = 42 ] || fail "positive control: same-file module global answered $same, not 42"

declared=$(answer declared use_declared.id)
scoped=$(answer scoped use_scoped.id)
assigned=$(answer assigned use_assigned.id)

[ "$assigned" = 42 ] || fail "compatibility assign face answered $assigned, not 42"
[ "$declared" = 42 ] || fail "canonical 'global base = 40' answered $declared, not 42"
[ "$scoped" = 42 ] || fail "file-scope 'local base = 40' answered $scoped, not 42"

# NEGATIVE CONTROL. A computed module initializer has no realization on this
# path, so the only lawful outcomes are a refusal or the right answer. A number
# that is neither is the GAP-121 erasure: the consumer ran before its module was
# initialized and could not tell.
computed=$(answer computed use_computed.id)
case "$computed" in
    refused|42) ;;
    *) fail "computed module initializer answered $computed; a static consumer ran before its module initialization" ;;
esac

printf 'gap-121 module init gate: PASS same=%s declared=%s scoped=%s assigned=%s computed=%s\n' \
    "$same" "$declared" "$scoped" "$assigned" "$computed"
