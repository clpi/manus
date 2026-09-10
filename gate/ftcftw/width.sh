#!/bin/sh
# gate/ftcftw/width.sh — one executed FTCFTW row: declared-u32 width narrowing
# in the C realizer vs hand C, on a matmul-shaped kernel.
#
# WHY THIS EXISTS. `Instr.ty` has carried a declared narrow width from the graph
# to every backend since the direct backend learned `emitNarrowFit`, and the
# wasm backend refits at the same store — but the C realizer never read the
# field, so a declared `u32` accumulator ran in the full 64-bit ring. The
# measured wrong answer (this row's negative control): the kernel below with
# input byte 'A' answered 4968005058000065 under the C realizer where the
# Z/2^32 law answers 3501814977 — silently, exit 0, `ok compile` both times.
# Both sibling realizers already truncate; this row proves the C one does too,
# then measures what the truncation costs or earns on the same machine.
#
# THE MECHANISM UNDER TEST. A declared `r: u32` makes every write to `r` a
# Z/2^32 operation. The C realizer emits `r = (int64_t)((uint32_t)(expr))` at
# each write — the same fact the direct backend realizes as `ubfx` and wasm as
# `i64.and 0xffffffff`. The comparison arm is the same algorithm handwritten
# with `uint32_t`, which is the strongest equivalent C spelling: it is what a C
# programmer writes when the domain is 32 bits, and clang compiles it to the
# same wrap. A `uint64_t` arm is the WIDTH-WIDENED control: identical source
# shape, no narrowing, and it answers a DIFFERENT value — proving the kernel
# genuinely depends on the declared width, not just on loop trip count.
#
# WHAT IT MEASURES, on the same machine, same compiler, same flags:
#
#   idol-u32     mm.id -> `idol compile --backend=c --emit=c` -> cc
#   hand-u32     the same algorithm handwritten with uint32_t -> cc
#   hand-u64     width-widened control (different answer, same work)
#
# ANSWER EQUIVALENCE IS CHECKED BEFORE TIME, against a Python oracle computed
# independently of every backend in this tree, and the comparator is proved
# able to fail before it is trusted to pass. The u64 control's DIFFERENT
# answer is asserted, not tolerated: a width row whose widened twin agreed
# would prove the kernel does not exercise the seam.
#
# Timing is min-of-9 end-to-end process wall clock, alternating arms.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

idol=${IDOL_BIN:-$repo/zig-out/bin/idol}
case "$idol" in /*) ;; *) idol=$repo/${idol#./} ;; esac
[ -x "$idol" ] || { printf 'ftcftw/width: CANNOT MEASURE — no compiler at %s\n' "$idol" >&2; exit 2; }
command -v cc >/dev/null 2>&1 || { printf 'ftcftw/width: CANNOT MEASURE — no cc\n' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'ftcftw/width: CANNOT MEASURE — no python3 oracle\n' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-ftcftw-width.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

OUTER=4000000

# The subject stays inside the C realizer's admitted slice — add, sub, mul and
# comparison only, one stdin byte as the only runtime input. The triple loop
# is a matmul-shaped dependency (row x col x k) without leaving the slice; the
# multipliers vary with both loop indices so the product cannot fold.
cat >"$work/mm.id" <<EOF
mm: i64 = (n: i64, seed: i64)
  r: u32 = seed
  i: i64 = 0
  while i < n
    j: i64 = 0
    while j < 3
      k: i64 = 0
      while k < 3
        x = (i + k + 1) * 3 + 1
        y = (k + j + 1) * 7 + 2
        r = r + x * y
        k = k + 1
      j = j + 1
    i = i + 1
  r

main: i64 = ()
  s = stdin:read():sub(1, 1):byte()
  v = mm($OUTER, s)
  print("mm {v}")
  v
EOF

cat >"$work/hand32.c" <<EOF
#include <stdint.h>
#include <stdio.h>
static int64_t mm(int64_t n, int64_t seed) {
    uint32_t r = (uint32_t)seed;
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < 3; j++)
            for (int64_t k = 0; k < 3; k++) {
                int64_t x = (i + k + 1) * 3 + 1;
                int64_t y = (k + j + 1) * 7 + 2;
                r = (uint32_t)(r + x * y);
            }
    return (int64_t)r;
}
int main(void) {
    int c = getchar();
    int64_t s = c == EOF ? 0 : (unsigned char)c;
    int64_t v = mm($OUTER, s);
    printf("mm %lld\n", (long long)v);
    return (int)(v & 0xff);
}
EOF

# Width-widened control: identical shape, u64 accumulator.
sed 's/uint32_t r = (uint32_t)seed;/uint64_t r = (uint64_t)seed;/; s/r = (uint32_t)(r + x \* y);/r = (uint64_t)(r + x * y);/; s/return (int64_t)r;/return (int64_t)r;/' \
    "$work/hand32.c" >"$work/hand64.c"

"$idol" compile --no-cache --backend=c --emit=c --target=c-source "$work/mm.id" -o "$work/idol.c" >"$work/emit.log" 2>&1 || {
    printf 'ftcftw/width: CANNOT MEASURE — the C realizer refused the subject:\n' >&2
    sed 's/^/    /' "$work/emit.log" >&2
    exit 2
}

printf 'A' >"$work/seed"
for a in idol hand32 hand64; do
    if [ "$a" = idol ]; then
        cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -o "$work/$a.bin" "$work/$a.c" \
            "$repo/tools/node/dev/grammar/idol_c_runtime_shim.c" 2>"$work/$a.cc"
    else
        cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -o "$work/$a.bin" "$work/$a.c" 2>"$work/$a.cc"
    fi
    [ $? -eq 0 ] || {
        printf 'ftcftw/width: CANNOT MEASURE — cc refused %s.c\n' "$a" >&2
        sed 's/^/    /' "$work/$a.cc" >&2
        exit 2
    }
done

# ===================== §1 THE WORK SURVIVES THE OPTIMIZER ====================
printf 'ftcftw/width: §1 the loop survives -O2\n'
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
alive=0
for a in idol hand32 hand64; do
    cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -S -o "$work/$a.s" "$work/$a.c" 2>/dev/null || continue
    case $a in idol) symbol=idol_entry ;; *) symbol=main ;; esac
    n=$(backward_jumps "$work/$a.s" "$symbol")
    [ "${n:-0}" -gt 0 ] && alive=$((alive + 1))
    printf '  %-12s backward jumps in %s: %s\n' "$a" "$symbol" "${n:-0}"
done
[ "$alive" -eq 3 ] || {
    printf 'ftcftw/width: CANNOT MEASURE — a hot loop did not survive; the timing below would be startup\n' >&2
    exit 2
}

# =========================== §2 SAME ANSWER =================================
printf 'ftcftw/width: §2 equivalence against the independent oracle\n'
oracle=$(python3 - "$work/seed" <<'PYEOF'
import sys
M = 1 << 32
s = open(sys.argv[1], 'rb').read(1)[0]
r = s % M
for i in range(4000000):
    for j in range(3):
        for k in range(3):
            x = (i + k + 1) * 3 + 1
            y = (k + j + 1) * 7 + 2
            r = (r + x * y) % M
print(r)
PYEOF
) || { printf 'ftcftw/width: CANNOT MEASURE — oracle failed\n' >&2; exit 2; }
oracle64=$(python3 - "$work/seed" <<'PYEOF'
import sys
s = open(sys.argv[1], 'rb').read(1)[0]
r = s
for i in range(4000000):
    for j in range(3):
        for k in range(3):
            x = (i + k + 1) * 3 + 1
            y = (k + j + 1) * 7 + 2
            r = r + x * y
print(r)
PYEOF
) || { printf 'ftcftw/width: CANNOT MEASURE — widened oracle failed\n' >&2; exit 2; }

want="mm $oracle"
ai=$("$work/idol.bin" <"$work/seed")
ah=$("$work/hand32.bin" <"$work/seed")
au=$("$work/hand64.bin" <"$work/seed")
printf '  oracle(u32)  %s\n  idol        %s\n  hand-u32    %s\n  hand-u64    %s (width control; oracle %s)\n' \
    "$want" "$ai" "$ah" "$au" "$oracle64"
[ "$ai" = "$want" ] || {
    printf 'ftcftw/width: BROKEN — idol answered %s where the u32 law answers %s\n' "$ai" "$want" >&2
    printf '             this is the pre-seam silent wrong answer; the C realizer ignored Instr.ty\n' >&2
    exit 2
}
[ "$ah" = "$want" ] || {
    printf 'ftcftw/width: BROKEN — hand-u32 arm answered %s where the u32 law answers %s\n' "$ah" "$want" >&2
    exit 2
}
[ "$au" = "mm $oracle64" ] || {
    printf 'ftcftw/width: BROKEN — hand-u64 control answered %s where the widened law answers mm %s\n' "$au" "$oracle64" >&2
    exit 2
}
[ "$au" != "$want" ] || {
    printf 'ftcftw/width: BROKEN — the widened control AGREED with the u32 law; the kernel does not exercise the width seam\n' >&2
    exit 2
}

# ============================== §3 TIME =====================================
printf 'ftcftw/width: §3 observed range of 9, alternating (end-to-end wall clock)\n'
bi=999999; bh=999999; bu=999999
bix=0; bhx=0; bux=0
i=0
while [ $i -lt 9 ]; do
    for a in idol hand32 hand64; do
        s=$(date +%s%N); "$work/$a.bin" <"$work/seed" >/dev/null 2>&1; e=$(date +%s%N)
        t=$(( (e - s) / 1000000 ))
        case $a in
            idol)   [ "$t" -lt "$bi" ] && bi=$t; [ "$t" -gt "$bix" ] && bix=$t ;;
            hand32) [ "$t" -lt "$bh" ] && bh=$t; [ "$t" -gt "$bhx" ] && bhx=$t ;;
            hand64) [ "$t" -lt "$bu" ] && bu=$t; [ "$t" -gt "$bux" ] && bux=$t ;;
        esac
    done
    i=$((i + 1))
done
printf '  idol-u32        %5s..%-5s ms\n' "$bi" "$bix"
printf '  hand uint32_t   %5s..%-5s ms (strongest equivalent C arm)\n' "$bh" "$bhx"
printf '  hand uint64_t   %5s..%-5s ms (width-widened control; different answer)\n' "$bu" "$bux"

[ "$bi" -gt 0 ] && [ "$bh" -gt 0 ] && [ "$bu" -gt 0 ] || {
    printf 'ftcftw/width: CANNOT MEASURE — sub-millisecond; raise OUTER\n' >&2
    exit 2
}

# ============================ §4 THE OUTCOME ================================
printf 'ftcftw/width: §4 scoped outcome against the strongest equivalent C arm\n'
if [ "$bix" -lt "$bh" ]; then
    printf '  WIN — Idol range %s..%s ms is strictly below equivalent-C %s..%s ms\n' "$bi" "$bix" "$bh" "$bhx"
    printf '        confidence: nine-run observed ranges are disjoint\n'
elif [ "$bi" -gt "$bhx" ]; then
    printf '  UNKNOWNBOUND — Idol range %s..%s ms is above equivalent-C %s..%s ms\n' "$bi" "$bix" "$bh" "$bhx"
    printf '                 the exact causal debt is not isolated, so no OPEN finding is admitted\n'
else
    printf '  UNKNOWNBOUND — Idol %s..%s ms and equivalent-C %s..%s ms overlap\n' "$bi" "$bix" "$bh" "$bhx"
    printf '                 no physical lower bound is proved; tie/win/loss is unresolved\n'
fi
printf 'ftcftw/width: OK — one workload, one end-to-end axis; the declared width is carried and answered\n'
exit 0
