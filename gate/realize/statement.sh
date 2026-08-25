#!/bin/sh
# gate/realize/statement.sh — a statement-position `if` arm answers BY POSITION,
# never by type alone. Pins gaps/GAP-070.md by VALUE, on both C faces.
#
# THE LAW THIS RUNS. An `if` arm may exit the enclosing relation in exactly two
# positions: when the `if` is the block's tail slot, or when the enclosing block
# answers the relation and the arm's tail is a value-carrying expression — the
# value-guard rule `src/dnir_lower.zig` documents at `branchIsValueGuard` and
# `examples/boring/fib.id` depends on (`if n < 2` / bare `n` before the
# recursive tail). Everywhere else — a trailing assignment, a void effect, and
# ANY arm inside a loop body — the block executes and control continues past it.
#
# WHY BY VALUE AND WHY BOTH FACES. GAP-070 recorded the C backend compiling a
# statement-position arm's final expression into a `return` while the direct
# backend fell through — a silent wrong answer selected by which backend a bail
# happened to pick. At close, the same class was live again in ONE face only:
# `idol dump-c` answered 5 from a value-typed arm inside a `while` body where
# the DNIR/C99 face answered 3, because `control_block_should_return` in
# `src/codegen.zig` was a TYPE test with no position fact. Each subject below
# is compiled through BOTH faces and must produce the SAME pinned exit, so a
# face that drifts fails here rather than in whichever gate bails into it next.
#
# The expected exits live HERE, in the runner that checks them, per AGENTS.md.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in
    /*) ;;
    *) idol=$repo/${idol#./} ;;
esac
[ -x "$idol" ] || {
    printf 'statement gate: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2
    exit 2
}

cc=${CC:-cc}
command -v "$cc" >/dev/null 2>&1 || {
    printf 'statement gate: CANNOT MEASURE — no C compiler (%s)\n' "$cc" >&2
    exit 2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gate-statement.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail=0

# Run one subject through one face and compare its exit BY VALUE. An optional
# fourth operand pins the subject's exact stdout too, so an effect arm can be
# proven to have RUN and not only to have fallen through.
#   face(realizer|dump) name expected [stdout]
face() {
    _face=$1
    _name=$2
    _want=$3
    _src=$work/$_name.id
    _c=$work/$_name.$_face.c
    case $_face in
        realizer)
            if ! "$idol" compile --backend=c --emit=c "$_src" -o "$_c" \
                >/dev/null 2>&1; then
                printf '  FAIL %s [%s]: the C realizer refused the subject\n' \
                    "$_name" "$_face" >&2
                fail=1
                return 0
            fi ;;
        dump)
            if ! "$idol" dump-c "$_src" >"$_c" 2>/dev/null; then
                printf '  FAIL %s [%s]: dump-c refused the subject\n' \
                    "$_name" "$_face" >&2
                fail=1
                return 0
            fi ;;
    esac
    if ! "$cc" -o "$work/$_name.$_face" "$_c" >/dev/null 2>&1; then
        printf '  FAIL %s [%s]: emitted C did not compile\n' "$_name" "$_face" >&2
        fail=1
        return 0
    fi
    _out=$("$work/$_name.$_face" 2>/dev/null)
    _got=$?
    if [ "$_got" -ne "$_want" ]; then
        printf '  FAIL %s [%s]: exit %s, pinned %s\n' \
            "$_name" "$_face" "$_got" "$_want" >&2
        fail=1
        return 0
    fi
    if [ $# -ge 4 ] && [ "$_out" != "$4" ]; then
        printf '  FAIL %s [%s]: stdout [%s], pinned [%s]\n' \
            "$_name" "$_face" "$_out" "$4" >&2
        fail=1
        return 0
    fi
    printf '  ok   %s [%s] exit %s\n' "$_name" "$_face" "$_want"
}

both() {
    face realizer "$1" "$2"
    face dump "$1" "$2"
}

# ============================ §1 CONTROL ====================================
# The comparator must be able to FAIL, or every pin below is vacuous. One
# subject is compared against a deliberately wrong exit; the comparator must
# report the mismatch and must not report the pass line.
printf 'statement gate: §1 control\n'
printf 'main: i64 = ()\n    41\n' >"$work/control.id"
ctl_out=$( { face realizer control 42; } 2>&1 )
case $ctl_out in
    *FAIL*) printf '  PASS — a wrong pin is reported as FAIL\n' ;;
    *) printf '  control FAIL: a wrong pin went unreported (%s)\n' "$ctl_out" >&2
       printf 'statement gate: BROKEN — the comparator cannot fail\n' >&2
       exit 2 ;;
esac
fail=0

# ============================= §2 SUBJECTS ==================================
printf 'statement gate: §2 subjects, both faces\n'

# A statement-position arm holding an ASSIGNMENT executes and control
# continues past it: 99 + 1 = 100, then the block tail answers.
cat >"$work/through.id" <<'EOF'
poke: i64 = (n: i64)
    out: i64 = 99
    if n == 1
        out = out + 1
    out

main: i64 = ()
    poke(1)
EOF
both through 100

# A statement-position arm whose tail CARRIES A VALUE is a guard exit of the
# answering block — the ruling that superseded GAP-070's expected 99, and the
# shape `examples/boring/fib.id` canonicalizes. Both faces must agree on 5.
cat >"$work/guard.id" <<'EOF'
adds: i64 = (a: i64, b: i64)
    a + b

pick: i64 = (n: i64)
    out: i64 = 99
    if n == 1
        adds(2, 3)
    out

main: i64 = ()
    pick(1)
EOF
both guard 5

# A LOOP BODY NEVER ANSWERS THE RELATION, so the same value-carrying arm
# inside `while` falls through on every iteration: three iterations, 3. This
# row is the divergence this gate was born measuring — dump-c answered 5.
cat >"$work/loop.id" <<'EOF'
adds: i64 = (a: i64, b: i64)
    a + b

count: i64 = (n: i64)
    i = 0
    total = 0
    while i < n
        if i == 0
            adds(2, 3)
        total = total + 1
        i = i + 1
    total

main: i64 = ()
    count(3)
EOF
both loop 3

# POSITIVE CONTROL — a genuine tail-position `if` still returns its arm.
cat >"$work/tail.id" <<'EOF'
grade: i64 = (n: i64)
    if n == 1
        7
    else
        3

main: i64 = ()
    grade(1)
EOF
both tail 7

# The filing's original damage class: a void EFFECT arm before the answer must
# not become the exit status — the effect runs and `code` still answers.
# dump-c face only: `print` is outside the C realizer's current slice
# (`value-not-i64`), and that frontier belongs to gate/realize/census.sh.
cat >"$work/effect.id" <<'EOF'
main: i64 = ()
    code: i64 = 1
    work = "x"
    if work != ""
        print("cleanup")
    code
EOF
face dump effect 1 cleanup

if [ "$fail" -ne 0 ]; then
    printf 'statement gate: FAIL — a statement-position arm answered out of position\n' >&2
    exit 1
fi
printf 'statement gate: OK — arms answer by position on both C faces\n'
exit 0
