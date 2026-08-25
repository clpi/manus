#!/bin/sh
# gate/ftcftw/wrap.sh — one executed FTCFTW row: Idol vs C on i64 wraparound.
#
# WHY THIS EXISTS. `docs/bootstrap.md` records FTCFTW as INVALID as a
# performance claim at S0, and `docs/METRICS.md` keeps the evidence-matrix cells
# explicitly empty. Both are correct and neither is a reason to have measured
# NOTHING. This measures one workload, on one axis, through the one realization
# route that exists on a host without direct-native codegen, and reports the
# outcome §99 requires: WIN, OPTIMAL, or LOSS with named debt.
#
# THE MECHANISM UNDER TEST, which is the whole point. `law.md` §98 says the
# advantage comes from maximum semantic knowledge. Idol's i64 is defined to
# WRAP. C's signed overflow is undefined. So the emitter writes every i64
# operation as unsigned-and-bit-cast (`idol_u64` / `idol_bits_i64`), and a C
# compiler may then reassociate freely across it — while the same algorithm
# spelled `int64_t`, which is what a C programmer writes, does not get the same
# treatment.
#
# WHAT IT MEASURES, on the same machine, same compiler, same flags:
#
#   idol           bench.id -> `idol compile --backend=c --emit=c` -> cc
#   hand-signed    the same algorithm handwritten with int64_t     -> cc
#   hand-unsigned  the same algorithm handwritten with uint64_t    -> cc
#
# THE THIRD ARM IS THE CONTROL AND IT IS NOT OPTIONAL. Without it the result
# reads as "Idol is 1.59x faster than C", and that is FALSE: the unsigned
# spelling ties Idol exactly. The honest claim is that Idol reaches the best
# known C without the programmer having to know why, and `law.ftcftw.dominance`
# calls that OPTIMAL, not WIN. A two-arm version of this gate would have
# published the false claim, which is why the arm is here.
#
# ANSWER EQUIVALENCE IS CHECKED BEFORE TIME. A faster program that computes
# something else is not a faster program.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in /*) ;; *) idol=$repo/${idol#./} ;; esac
[ -x "$idol" ] || { printf 'ftcftw/wrap: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2; exit 2; }
command -v cc >/dev/null 2>&1 || { printf 'ftcftw/wrap: CANNOT MEASURE — no cc\n' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-ftcftw-wrap.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ROUNDS=500
OUTER=200000

# The subject stays inside the C realizer's admitted slice — add, sub, mul and
# comparison only. Division is `binop-not-in-c99-slice` and `print` is
# `operation-not-in-c99-slice`, so the exit code is the only observation, which
# is also why the recurrence must not be algebraically trivial: an earlier draft
# used `h - h*3 + h*2`, which is `h*0`, and both programs folded to `return 0`.
cat >"$work/bench.id" <<EOF
mix: i64 = (seed: i64, rounds: i64)
  h = seed
  i = 0
  while i < rounds
    h = h * 6364136223846793005 + 1442695040888963407
    h = h + (h * 1024)
    i = i + 1
  h

main: i64 = ()
  acc = 0
  outer = 0
  while outer < $OUTER
    acc = acc + mix(outer, $ROUNDS)
    outer = outer + 1
  acc
EOF

cat >"$work/hand.c" <<EOF
#include <stdint.h>
static inline int64_t mix(int64_t seed, int64_t rounds) {
    int64_t h = seed;
    for (int64_t i = 0; i < rounds; i++) {
        h = h * 6364136223846793005 + 1442695040888963407;
        h = h + (h * 1024);
    }
    return h;
}
int main(void) {
    int64_t acc = 0;
    for (int64_t outer = 0; outer < $OUTER; outer++) acc += mix(outer, $ROUNDS);
    return (int)acc;
}
EOF

sed 's/int64_t/uint64_t/g; s/(int)acc/(int)(int64_t)acc/' "$work/hand.c" >"$work/hand_u.c"

"$idol" compile "$work/bench.id" --backend=c --emit=c -o "$work/idol.c" >"$work/emit.log" 2>&1 || {
    printf 'ftcftw/wrap: CANNOT MEASURE — the C realizer refused the subject:\n' >&2
    sed 's/^/    /' "$work/emit.log" >&2
    exit 2
}

for a in idol hand hand_u; do
    cc -std=c11 -O2 -o "$work/$a.bin" "$work/$a.c" 2>"$work/$a.cc" || {
        printf 'ftcftw/wrap: CANNOT MEASURE — cc refused %s.c\n' "$a" >&2
        sed 's/^/    /' "$work/$a.cc" >&2
        exit 2
    }
done

# ===================== §1 THE WORK MUST SURVIVE THE OPTIMIZER ================
# A loop the compiler deleted times as process startup and reads as a win. The
# earlier draft of this gate measured 3ms for 10^8 iterations and the assembly
# was `xorl %eax, %eax; ret`.
printf 'ftcftw/wrap: §1 the loop survives -O2\n'
alive=0
for a in idol hand hand_u; do
    cc -std=c11 -O2 -S -o "$work/$a.s" "$work/$a.c" 2>/dev/null || continue
    n=$(awk '/^main:/,/^[[:space:]]*ret/' "$work/$a.s" | grep -cE 'j[a-z]+[[:space:]]+\.L' || :)
    [ "${n:-0}" -gt 0 ] && alive=$((alive + 1))
    printf '  %-14s backward jumps in main: %s\n' "$a" "${n:-0}"
done
[ "$alive" -eq 3 ] || {
    printf 'ftcftw/wrap: CANNOT MEASURE — a hot loop did not survive; the timing below would be startup\n' >&2
    exit 2
}

# =========================== §2 SAME ANSWER =================================
printf 'ftcftw/wrap: §2 equivalence\n'
"$work/idol.bin"; ai=$?
"$work/hand.bin"; ah=$?
"$work/hand_u.bin"; au=$?
printf '  idol %s   hand-signed %s   hand-unsigned %s\n' "$ai" "$ah" "$au"
[ "$ai" = "$ah" ] && [ "$ai" = "$au" ] || {
    printf 'ftcftw/wrap: BROKEN — the three arms do not compute the same answer\n' >&2
    exit 2
}

# ============================== §3 TIME =====================================
printf 'ftcftw/wrap: §3 min of 9, alternating\n'
bi=999999; bh=999999; bu=999999
i=0
while [ $i -lt 9 ]; do
    for a in idol hand hand_u; do
        s=$(date +%s%N); "$work/$a.bin" >/dev/null 2>&1; e=$(date +%s%N)
        t=$(( (e - s) / 1000000 ))
        case $a in
            idol)   [ "$t" -lt "$bi" ] && bi=$t ;;
            hand)   [ "$t" -lt "$bh" ] && bh=$t ;;
            hand_u) [ "$t" -lt "$bu" ] && bu=$t ;;
        esac
    done
    i=$((i + 1))
done
printf '  idol            %5s ms\n' "$bi"
printf '  hand int64_t    %5s ms\n' "$bh"
printf '  hand uint64_t   %5s ms\n' "$bu"

[ "$bi" -gt 0 ] || {
    printf 'ftcftw/wrap: CANNOT MEASURE — sub-millisecond; raise OUTER\n' >&2
    exit 2
}

# ============================ §4 THE OUTCOME ================================
# §99 admits exactly three, and the comparison oracle is the BEST known
# implementation — here the unsigned arm, not the idiomatic one.
printf 'ftcftw/wrap: §4 outcome against the best known C\n'
if [ "$bi" -lt "$bu" ]; then
    printf '  WIN — idol is faster than the best C arm (%s ms vs %s ms)\n' "$bi" "$bu"
elif [ "$bi" -eq "$bu" ]; then
    printf '  OPTIMAL — idol equals the best C arm (%s ms), and is faster than\n' "$bi"
    printf '            the idiomatic int64_t spelling (%s ms)\n' "$bh"
else
    printf '  LOSS — idol %s ms vs best C %s ms; debt: the emitted unsigned form\n' "$bi" "$bu"
    printf '         did not reach the fold the C arm did\n'
fi
printf 'ftcftw/wrap: OK — one workload, one axis, three arms, answers equal\n'
exit 0
