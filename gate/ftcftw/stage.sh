#!/bin/sh
# gate/ftcftw/stage.sh — the nonexecution row: work C must do at runtime,
# Idol's stage world does at build, and the program carries the answer.
#
# THE MECHANISM. REALIZATION-CONTRACT (§108, `law.realization.contract`) names
# lawful nonexecution — "a cached exact answer, a theorem, materialized state"
# — the ultimate realization. `@(expr)` / `expr@{ stage = compile }` is that
# contract's spelling: evaluation under a stage-delta world
# (`law.stage.world`), value in, no residual operation out. C11 has no such
# spelling — a C program cannot ask its compiler to execute an arbitrary
# function at build time, and gcc's own folding gives up long before a
# multiplicative 64-bit recurrence over millions of iterations.
#
# WHAT THE ARMS ARE:
#
#   idol    main returns `@(mix(N))` -> the emitted C contains a CONSTANT
#   hand    the same mix(N), idiomatic C, computed by main at runtime
#
# WHAT KEEPS IT HONEST, in order:
#
#   §1  structure — the idol main carries NO loop (nonexecution is a fact of
#       the artifact, not a stopwatch reading), and the hand main STILL
#       carries one at -O2, which is the control proving the C compiler could
#       not do this fold. If gcc ever folds it, this gate reports the tie.
#   §2  the folded constant is re-derived by an independent C program at
#       runtime and compared over the FULL 64 bits — not an 8-bit exit code.
#       A wrong fold is a wrong program with a good stopwatch.
#   §3  only then is anything timed.
#
# BOUNDED CLAIM, stated where the number is printed: the stage world's fuel
# budget caps how much work can move to build time, so this row demonstrates a
# CAPABILITY C lacks, at a magnitude the budget allows — it is not a throughput
# comparison. And a C programmer could paste the precomputed constant by hand;
# then the constant is a human claim carried in a comment, where here it is
# derived by the compiler and re-verified by this gate. That provenance
# asymmetry IS the semantic knowledge `law.ftcftw.dominance` prices.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in /*) ;; *) idol=$repo/${idol#./} ;; esac
[ -x "$idol" ] || { printf 'ftcftw/stage: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2; exit 2; }
command -v cc >/dev/null 2>&1 || { printf 'ftcftw/stage: CANNOT MEASURE — no cc\n' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-ftcftw-stage.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

N=4000000

cat >"$work/bench.id" <<EOF
mix: i64 = (rounds: i64)
  h = 99
  i = 0
  while i < rounds
    h = h * 6364136223846793005 + 1442695040888963407
    h = h + (h * 1024)
    i = i + 1
  h

main: i64 = ()
  x = @(mix($N))
  x
EOF

cat >"$work/hand.c" <<EOF
#include <stdint.h>
static int64_t mix(int64_t rounds) {
    uint64_t h = 99;
    for (int64_t i = 0; i < rounds; i++) {
        h = h * UINT64_C(6364136223846793005) + UINT64_C(1442695040888963407);
        h = h + (h * 1024);
    }
    int64_t out; __builtin_memcpy(&out, &h, sizeof out); return out;
}
int main(void) { return (int)mix($N); }
EOF

# ========================== §0 CONTROLS =====================================
# The face must fold a known value and refuse a known non-value, or everything
# below is a classifier that cannot fail.
printf 'ftcftw/stage: §0 control\n'
printf 'tri: i64 = (n: i64)\n  t = 0\n  i = 0\n  while i < n\n    i = i + 1\n    t = t + i\n  t\n\nmain: i64 = ()\n  x = @(tri(100))\n  x\n' >"$work/ctl_fold.id"
"$idol" compile "$work/ctl_fold.id" --backend=c --emit=c -o "$work/ctl_fold.c" >/dev/null 2>&1 || {
    printf 'ftcftw/stage: CANNOT MEASURE — the stage world cannot fold a sibling relation here\n' >&2
    exit 2
}
grep -q 'UINT64_C(0x13ba)' "$work/ctl_fold.c" || {
    printf 'ftcftw/stage: BROKEN — tri(100) folded to something other than 5050\n' >&2
    exit 2
}
printf 'main: i64 = ()\n  x = @(nosuchrelation(3))\n  x\n' >"$work/ctl_refuse.id"
if "$idol" compile "$work/ctl_refuse.id" --backend=c --emit=c -o /dev/null >/dev/null 2>&1; then
    printf 'ftcftw/stage: BROKEN — an unknown relation folded\n' >&2
    exit 2
fi
# The MEASURED integer-division divergence from the evaluator's own doc block:
# without `native_fold`, `7 / 2` routes to the float path and `3.5 == 3` folds
# false. The staged fold must answer with the backend's integer laws, so this
# control pins the exact case that was a silent wrong answer.
printf 'sel: i64 = (a: i64, b: i64)\n  q = a / b\n  out = 0\n  if q == 3\n    out = 1\n  out\n\nmain: i64 = ()\n  x = @(sel(7, 2))\n  x\n' >"$work/ctl_div.id"
"$idol" compile "$work/ctl_div.id" --backend=c --emit=c -o "$work/ctl_div.c" >/dev/null 2>&1 || {
    printf 'ftcftw/stage: BROKEN — the staged fold refused integer division\n' >&2
    exit 2
}
grep -q 'UINT64_C(0x1)' "$work/ctl_div.c" || {
    printf 'ftcftw/stage: BROKEN — 7 / 2 == 3 staged FALSE: the fold is running compatibility float division, the measured silent-wrong-answer\n' >&2
    exit 2
}
# Two module relations under one spelling: the stage world must REFUSE, never
# pick one by collection order.
printf 'pick: i64 = (n: i64)\n  n + 1\n\npick: i64 = (n: i64, m: i64)\n  n + m\n\nmain: i64 = ()\n  x = @(pick(1))\n  x\n' >"$work/ctl_dup.id"
if "$idol" compile "$work/ctl_dup.id" --backend=c --emit=c -o /dev/null >/dev/null 2>&1; then
    printf 'ftcftw/stage: BROKEN — a duplicated spelling folded; last-wins is a coin flip, not resolution\n' >&2
    exit 2
fi
printf '  PASS — sibling folds right, unknown refuses, integer / is the backend law, duplicate spelling refuses\n'

# ============================ §1 STRUCTURE ==================================
printf 'ftcftw/stage: §1 the artifact shapes\n'
"$idol" compile "$work/bench.id" --backend=c --emit=c -o "$work/idol.c" >"$work/emit.log" 2>&1 || {
    printf 'ftcftw/stage: CANNOT MEASURE — the stage world refused the workload:\n' >&2
    sed 's/^/    /' "$work/emit.log" >&2
    exit 2
}
cc -std=c11 -O2 -o "$work/idol.bin" "$work/idol.c" || exit 2
cc -std=c11 -O2 -o "$work/hand.bin" "$work/hand.c" || exit 2
cc -std=c11 -O2 -S -o "$work/idol.s" "$work/idol.c"
cc -std=c11 -O2 -S -o "$work/hand.s" "$work/hand.c"
ij=$(awk '/^main:/,/^[[:space:]]*ret/' "$work/idol.s" | grep -cE 'j[a-z]+[[:space:]]+\.L' || :)
hj=$(grep -cE 'j[a-z]+[[:space:]]+\.L' "$work/hand.s" || :)
printf '  idol main backward jumps: %s   (nonexecution: the answer is in the binary)\n' "${ij:-0}"
printf '  hand loop jumps anywhere: %s   (gcc retained the loop: it could not fold this)\n' "${hj:-0}"
[ "${ij:-0}" -eq 0 ] || {
    printf 'ftcftw/stage: BROKEN — the idol arm still carries a loop; the fold did not happen\n' >&2
    exit 2
}
tie=0
[ "${hj:-0}" -gt 0 ] || tie=1

# ========================== §2 FULL-WIDTH TRUTH =============================
printf 'ftcftw/stage: §2 the folded constant, re-derived at 64 bits\n'
konst=$(grep -oE 'UINT64_C\(0x[0-9a-f]+\)' "$work/idol.c" | sort | uniq -c | sort -n | tail -1 | grep -oE '0x[0-9a-f]+')
[ -n "$konst" ] || { printf 'ftcftw/stage: BROKEN — no folded constant in the emitted C\n' >&2; exit 2; }
cat >"$work/check.c" <<EOF
#include <stdint.h>
int main(void) {
    uint64_t h = 99;
    for (int64_t i = 0; i < $N; i++) {
        h = h * UINT64_C(6364136223846793005) + UINT64_C(1442695040888963407);
        h = h + (h * 1024);
    }
    return h == UINT64_C($konst) ? 0 : 1;
}
EOF
cc -std=c11 -O2 -o "$work/check.bin" "$work/check.c" || exit 2
if "$work/check.bin"; then
    printf '  PASS — %s over all 64 bits, derived by the compiler, re-derived at runtime\n' "$konst"
else
    printf 'ftcftw/stage: BROKEN — the folded constant is WRONG (%s); a wrong fold with a fast binary is the worst outcome\n' "$konst" >&2
    exit 2
fi

# =============================== §3 TIME ====================================
printf 'ftcftw/stage: §3 min of 9, alternating (microseconds)\n'
bi=99999999; bh=99999999
i=0
while [ $i -lt 9 ]; do
    s=$(date +%s%N); "$work/idol.bin" >/dev/null 2>&1 || :; e=$(date +%s%N)
    t=$(( (e - s) / 1000 )); [ "$t" -lt "$bi" ] && bi=$t
    s=$(date +%s%N); "$work/hand.bin" >/dev/null 2>&1 || :; e=$(date +%s%N)
    t=$(( (e - s) / 1000 )); [ "$t" -lt "$bh" ] && bh=$t
    i=$((i + 1))
done
printf '  idol (constant)   %8s us\n' "$bi"
printf '  hand (computes)   %8s us\n' "$bh"

# ============================== §4 OUTCOME ==================================
printf 'ftcftw/stage: §4 outcome\n'
if [ "$tie" -eq 1 ]; then
    printf '  TIE — gcc folded the workload too; raise N or change the recurrence\n'
elif [ "$bi" -lt "$bh" ]; then
    printf '  WIN — the answer was realized at build; runtime carries none of the work.\n'
    printf '        Capability row, fuel-bounded: the stage budget caps how much work\n'
    printf '        can move to build, and a hand-pasted C constant would be a human\n'
    printf '        claim where this one is compiler-derived and re-verified above.\n'
else
    printf '  LOSS — process overhead swallowed the fold; raise N\n'
fi
printf 'ftcftw/stage: OK — folded, verified at full width, and timed\n'
exit 0
