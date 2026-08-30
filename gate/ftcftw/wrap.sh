#!/bin/sh
# gate/ftcftw/wrap.sh — one executed FTCFTW row: Idol vs C on i64 wraparound.
#
# WHY THIS EXISTS. `docs/bootstrap.md` records FTCFTW as INVALID as a
# performance claim at S0, and `docs/METRICS.md` keeps the evidence-matrix cells
# explicitly empty. Both are correct and neither is a reason to have measured
# NOTHING. This measures one workload, on one axis, through the one realization
# route that exists on a host without direct-native codegen, and reports the
# current law's scoped `win` or `unknownbound`. Equality with C is NOT a physical
# lower bound and therefore can never establish `bound` by itself.
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
# spelling can tie Idol. The honest claim is that Idol can reach the strongest
# equivalent C spelling without the programmer having to know why. A sampled
# tie or overlap is `unknownbound`, never OPTIMAL: this gate proves no physical
# lower bound. A two-arm version would publish a false win over a strawman.
#
# ANSWER EQUIVALENCE IS CHECKED BEFORE TIME. A faster program that computes
# something else is not a faster program.
# One identical byte is read at runtime by every arm. It is a semantic input,
# not entropy: the fixed seed file makes answers reproducible while preventing
# the C optimizer from replacing the complete workload with a constant.
# The measured axis is END-TO-END process wall clock: startup and the one-byte
# input are included for every arm. They occur once before 100,000,000 inner
# iterations and remain visible rather than being silently subtracted.

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
  seed = stdin:read():sub(1, 1):byte()
  acc = 0
  outer = 0
  while outer < $OUTER
    acc = acc + mix(seed + outer, $ROUNDS)
    outer = outer + 1
  acc
EOF

cat >"$work/hand.c" <<EOF
#include <stdint.h>
#include <stdio.h>
static inline int64_t mix(int64_t seed, int64_t rounds) {
    int64_t h = seed;
    for (int64_t i = 0; i < rounds; i++) {
        h = h * 6364136223846793005 + 1442695040888963407;
        h = h + (h * 1024);
    }
    return h;
}
int main(void) {
    int input = getchar();
    int64_t seed = input == EOF ? 0 : (unsigned char)input;
    int64_t acc = 0;
    for (int64_t outer = 0; outer < $OUTER; outer++) acc += mix(seed + outer, $ROUNDS);
    return (int)acc;
}
EOF

sed 's/int64_t/uint64_t/g; s/(int)acc/(int)(int64_t)acc/' "$work/hand.c" >"$work/hand_u.c"

"$idol" compile "$work/bench.id" --backend=c --emit=c -o "$work/idol.c" >"$work/emit.log" 2>&1 || {
    printf 'ftcftw/wrap: CANNOT MEASURE — the C realizer refused the subject:\n' >&2
    sed 's/^/    /' "$work/emit.log" >&2
    exit 2
}

printf 'A' >"$work/seed"
for a in idol hand hand_u; do
    if [ "$a" = idol ]; then
        cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -o "$work/$a.bin" "$work/$a.c" \
            "$repo/tools/node/dev/grammar/idol_c_runtime_shim.c" 2>"$work/$a.cc"
    else
        cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -o "$work/$a.bin" "$work/$a.c" 2>"$work/$a.cc"
    fi
    if [ $? -ne 0 ]; then
        printf 'ftcftw/wrap: CANNOT MEASURE — cc refused %s.c\n' "$a" >&2
        sed 's/^/    /' "$work/$a.cc" >&2
        exit 2
    fi
done

# ===================== §1 THE WORK MUST SURVIVE THE OPTIMIZER ================
# A loop the compiler deleted times as process startup and reads as a win. The
# earlier draft of this gate measured 3ms for 10^8 iterations and the assembly
# was `xorl %eax, %eax; ret`.
printf 'ftcftw/wrap: §1 the loop survives -O2\n'
backward_jumps() {
    asm=$1
    symbol=$2
    awk -v symbol="$symbol" '
        FNR == NR {
            if ($1 ~ /^\.L[A-Za-z0-9_.$]*:$/) {
                label=$1
                sub(/:$/, "", label)
                at[label]=FNR
            }
            next
        }
        $1 == symbol ":" { inside=1; next }
        inside && $1 == "ret" { inside=0; next }
        inside && $1 ~ /^(j|b|cb|tb)/ {
            for (i=2; i<=NF; i++) {
                target=$i
                gsub(/[,;]/, "", target)
                if (target in at && at[target] < FNR) n++
            }
        }
        END { print n + 0 }
    ' "$asm" "$asm"
}
cat >"$work/branch-forward.s" <<'ASM'
main:
    bne .Llater
    ret
.Llater:
    ret
ASM
cat >"$work/branch-backward.s" <<'ASM'
main:
.Lloop:
    bne .Lloop
    ret
ASM
cat >"$work/branch-multioperand.s" <<'ASM'
idol_entry:
.Lloop:
    cbnz x0, .Lloop
    ret
ASM
[ "$(backward_jumps "$work/branch-forward.s" main)" -eq 0 ] || {
    printf 'ftcftw/wrap: BROKEN — branch scanner counted a forward edge as work\n' >&2
    exit 2
}
[ "$(backward_jumps "$work/branch-backward.s" main)" -eq 1 ] || {
    printf 'ftcftw/wrap: BROKEN — branch scanner missed a planted backward edge\n' >&2
    exit 2
}
[ "$(backward_jumps "$work/branch-multioperand.s" idol_entry)" -eq 1 ] || {
    printf 'ftcftw/wrap: BROKEN — branch scanner missed a multi-operand backward edge\n' >&2
    exit 2
}
printf '  branch scanner control: forward 0, backward 1, multi-operand 1\n'
alive=0
for a in idol hand hand_u; do
    cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -S -o "$work/$a.s" "$work/$a.c" 2>/dev/null || continue
    case $a in idol) symbol=idol_entry ;; *) symbol=main ;; esac
    n=$(backward_jumps "$work/$a.s" "$symbol")
    [ "${n:-0}" -gt 0 ] && alive=$((alive + 1))
    printf '  %-14s backward jumps in %s: %s\n' "$a" "$symbol" "${n:-0}"
done
[ "$alive" -eq 3 ] || {
    printf 'ftcftw/wrap: CANNOT MEASURE — a hot loop did not survive; the timing below would be startup\n' >&2
    exit 2
}

# =========================== §2 SAME ANSWER =================================
printf 'ftcftw/wrap: §2 equivalence\n'
"$work/idol.bin" <"$work/seed"; ai=$?
"$work/hand.bin" <"$work/seed"; ah=$?
"$work/hand_u.bin" <"$work/seed"; au=$?
printf '  idol %s   hand-signed %s   hand-unsigned %s\n' "$ai" "$ah" "$au"
[ "$ai" = "$au" ] || {
    printf 'ftcftw/wrap: BROKEN — Idol and the semantically equivalent unsigned-C arm disagree\n' >&2
    exit 2
}
# The high-bit control proves both equivalent arms interpret the input byte as
# 0..255 rather than host `char` signedness. This is deliberately separate from
# the timed ASCII seed so the portability fact cannot pass by using 0x41.
printf '\200' >"$work/seed-high"
[ "$(wc -c <"$work/seed-high" | tr -d ' ')" -eq 1 ] || {
    printf 'ftcftw/wrap: BROKEN — could not construct the one-byte high-bit control\n' >&2
    exit 2
}
"$work/idol.bin" <"$work/seed-high"; aih=$?
"$work/hand_u.bin" <"$work/seed-high"; auh=$?
printf '  high-bit byte control: idol %s   hand-unsigned %s\n' "$aih" "$auh"
[ "$aih" = "$auh" ] || {
    printf 'ftcftw/wrap: BROKEN — high-bit input is not zero-extended equally\n' >&2
    exit 2
}
# `int64_t` overflow is undefined in C, so this arm is an idiomatic control,
# not a semantic oracle. Its observed answer is published above but never used
# to establish equivalence or a frontier result.

# ============================== §3 TIME =====================================
printf 'ftcftw/wrap: §3 observed range of 9, alternating (end-to-end wall clock)\n'
bi=999999; bh=999999; bu=999999
bix=0; bhx=0; bux=0
i=0
while [ $i -lt 9 ]; do
    for a in idol hand hand_u; do
        s=$(date +%s%N); "$work/$a.bin" <"$work/seed" >/dev/null 2>&1; e=$(date +%s%N)
        t=$(( (e - s) / 1000000 ))
        case $a in
            idol)   [ "$t" -lt "$bi" ] && bi=$t; [ "$t" -gt "$bix" ] && bix=$t ;;
            hand)   [ "$t" -lt "$bh" ] && bh=$t; [ "$t" -gt "$bhx" ] && bhx=$t ;;
            hand_u) [ "$t" -lt "$bu" ] && bu=$t; [ "$t" -gt "$bux" ] && bux=$t ;;
        esac
    done
    i=$((i + 1))
done
printf '  idol            %5s..%-5s ms\n' "$bi" "$bix"
printf '  hand int64_t    %5s..%-5s ms (idiomatic UB control; not an oracle)\n' "$bh" "$bhx"
printf '  hand uint64_t   %5s..%-5s ms (strongest equivalent C arm)\n' "$bu" "$bux"

[ "$bi" -gt 0 ] && [ "$bh" -gt 0 ] && [ "$bu" -gt 0 ] || {
    printf 'ftcftw/wrap: CANNOT MEASURE — sub-millisecond; raise OUTER\n' >&2
    exit 2
}

# ============================ §4 THE OUTCOME ================================
# The comparison oracle is the BEST semantically equivalent known arm — here
# unsigned C, not the idiomatic signed-overflow control. The nine-run observed
# ranges are the stated confidence boundary. Overlap cannot establish a win,
# and equality with an implementation cannot establish a physical bound.
printf 'ftcftw/wrap: §4 scoped outcome against the strongest equivalent C arm\n'
if [ "$bix" -lt "$bu" ]; then
    printf '  WIN — Idol range %s..%s ms is strictly below equivalent-C %s..%s ms\n' "$bi" "$bix" "$bu" "$bux"
    printf '        confidence: nine-run observed ranges are disjoint\n'
elif [ "$bi" -gt "$bux" ]; then
    printf '  UNKNOWNBOUND — Idol range %s..%s ms is above equivalent-C %s..%s ms\n' "$bi" "$bix" "$bu" "$bux"
    printf '                 the exact causal debt is not isolated, so no OPEN finding is admitted\n'
else
    printf '  UNKNOWNBOUND — Idol %s..%s ms and equivalent-C %s..%s ms overlap\n' "$bi" "$bix" "$bu" "$bux"
    printf '                 no physical lower bound is proved; tie/win/loss is unresolved\n'
fi
printf 'ftcftw/wrap: OK — one workload, one end-to-end axis; equivalent arms answer equally\n'
exit 0
