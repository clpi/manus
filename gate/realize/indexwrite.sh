#!/bin/sh
# gate/realize/indexwrite.sh — indexed WRITE answers by VALUE on the C99 path.
#
# WHY THIS EXISTS. `gaps/GAP-101.md` spent five corrections learning that
# "indexed write does not lower" was measured against one pipeline and blamed
# on another. On this host the C99 realizer is the only route from source to a
# running program (the direct backend refuses non-aarch64-darwin hosts by
# name, DNB004), and until the indexed-store family landed in
# `src/c_backend.zig` every `xs[i] = v` with a computed index refused at
# `operation-not-in-c99-slice`. This gate pins the repaired behavior BY VALUE:
# the program's own exit status is the byte compared, so the pin cannot decay
# into prose the way the gap's headline did.
#
# WHAT IT REFUSES TO CLAIM. The C99 path only. Direct-native evidence is not C
# evidence and is not obtainable on a refused host; the growable `{}` table
# still bails upstream in `dnir_lower` and is OUT of this gate's subject.
#
# Exit 0: every pin holds. Exit 1: a pin broke. Exit 2: cannot measure.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in
    /*) ;;
    *) idol=$repo/${idol#./} ;;
esac
[ -x "$idol" ] || {
    printf 'indexwrite: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2
    exit 2
}

cc=${CC:-cc}
command -v -- "$cc" >/dev/null 2>&1 || {
    printf 'indexwrite: CANNOT MEASURE — no C compiler (%s)\n' "$cc" >&2
    exit 2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-indexwrite.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail=0

# Compile one subject through --backend=c --emit=c, build it, run it, and
# compare the process exit to the expected value. The expected number lives
# HERE, in the runner that checks it, per AGENTS.md.
pin() {
    _name=$1
    _expect=$2
    if ! "$idol" compile "$work/$_name.id" --no-cache --backend=c --emit=c \
        -o "$work/$_name.c" >"$work/$_name.log" 2>&1
    then
        printf 'indexwrite: %s did not realize\n' "$_name" >&2
        sed -n 's/.*refused at: /  refused at: /p' "$work/$_name.log" >&2
        fail=1
        return 0
    fi
    if ! "$cc" -std=c99 -O2 -o "$work/$_name" "$work/$_name.c" \
        >"$work/$_name.cc.log" 2>&1
    then
        printf 'indexwrite: %s emitted C that does not build\n' "$_name" >&2
        fail=1
        return 0
    fi
    if "$work/$_name" >/dev/null 2>&1; then _got=0; else _got=$?; fi
    if [ "$_got" -ne "$_expect" ]; then
        printf 'indexwrite: %s answered %s, expected %s\n' "$_name" "$_got" "$_expect" >&2
        fail=1
    fi
}

# ---- §1 positive control: the compile+build+run circuit reports a value ----
printf 'main: i64 = ()\n  7\nmain()\n' >"$work/circuit.id"
pin circuit 7
[ "$fail" -eq 0 ] || {
    printf 'indexwrite: CANNOT MEASURE — the value circuit itself is broken\n' >&2
    exit 2
}
printf 'indexwrite: §1 control PASS — a value survives compile, cc, and run\n'

# ---- §2 loop-variable indexed WRITE, read back by value ----
# The register-exploded (select-chain / reduce) representation: write through
# a loop variable, then sum the elements. 2+4+6+8.
cat >"$work/smallrw.id" <<'EOF'
main: i64 = ()
  xs = { 0, 0, 0, 0 }
  i = 1
  while i <= 4
    xs[i] = i * 2
    i = i + 1
  s = 0
  j = 1
  while j <= 4
    s = s + xs[j]
    j = j + 1
  s
main()
EOF
pin smallrw 20

# The memory-backed representation (len > 32 forces alloc_slots +
# store_index/load_index): write through a loop variable, read one back.
{
    printf 'main: i64 = ()\n  xs = {'
    n=0
    while [ "$n" -lt 40 ]; do
        [ "$n" -gt 0 ] && printf ','
        printf ' 0'
        n=$((n + 1))
    done
    printf ' }\n'
    cat <<'EOF'
  i = 1
  while i <= 40
    xs[i] = i * 3
    i = i + 1
  v: i64 = xs[40]
  v
main()
EOF
} >"$work/membacked.id"
pin membacked 120

# ---- §3 the bounds guard still traps out of range ----
# An index one past the extent must abort, not store somewhere and answer 0 —
# gap[063]'s defect. Death by SIGABRT reports > 128 in every POSIX shell.
cat >"$work/trap.id" <<'EOF'
main: i64 = ()
  xs = { 0, 0, 0, 0 }
  i = 1
  while i <= 4
    i = i + 1
  xs[i] = 9
  0
main()
EOF
if ! "$idol" compile "$work/trap.id" --no-cache --backend=c --emit=c \
    -o "$work/trap.c" >"$work/trap.log" 2>&1
then
    printf 'indexwrite: trap subject did not realize\n' >&2
    fail=1
elif ! "$cc" -std=c99 -O2 -o "$work/trap" "$work/trap.c" >/dev/null 2>&1; then
    printf 'indexwrite: trap subject emitted C that does not build\n' >&2
    fail=1
else
    if "$work/trap" >/dev/null 2>&1; then trap_got=0; else trap_got=$?; fi
    if [ "$trap_got" -le 128 ]; then
        printf 'indexwrite: out-of-range write exited %s, expected a signal death (> 128)\n' "$trap_got" >&2
        fail=1
    fi
fi

[ "$fail" -eq 0 ] || {
    printf 'indexwrite: FAIL\n' >&2
    exit 1
}
printf 'indexwrite: OK — loop-variable indexed write answers by value on the C99 path, in both representations, and out of range still traps\n'
exit 0
