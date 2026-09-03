#!/bin/sh
# gate/lower/cost.sh — GAP-185's measured-cost face: the software check's
# per-access enforcement cost, MEASURED on this host, never estimated.
#
# WHY THIS EXISTS. `lower.costOf` states cycle-scale ORDERS — `law` §14:
# unmeasured is stated, never dressed up. The one mechanism this compiler
# both admits on every target and actually realizes today is
# `software_check`, the test+trap the graph-backed C99 arm emits around an
# enforced access. This runner measures exactly that mechanism: two loops
# identical but for the check, compiled by the host C compiler the C99 arm
# emits for, timed interleaved min-of-N. The answer is an
# `idol.world.cost.v1` row on stdout — one mechanism, one target triple, one
# unit, and the exact measured subject revision (`law.evidence.subject.one`).
# `lower.selectMeasured` is the consumer: measured facts decide ONLY a
# uniform comparison, so this row joins a selection only when every
# candidate on the target was measured in the same unit.
#
# THE CONTROL. The measurement is meaningless if the host compiler folded
# the check away — then nothing is being measured. `probe selftest` runs the
# checked loop with the extent fact set BELOW the index range: a live check
# kills the process by signal, and this gate requires that death before it
# trusts a timing. A selftest that returns proves the check is gone and the
# verdict is CANNOT MEASURE.
#
# REFUSALS. No C compiler, a failed compile, or a folded check are all
# CANNOT MEASURE (exit 2) with the reason named — never a fabricated row.
#
# K (accesses per repetition, default 2^22) and N (repetitions, default 9)
# are environment-tunable. The row reports checked and plain ns/access
# separately; the enforcement cost is the difference, reported even when
# noise makes it negative — the number is the host's answer, not a target.

set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd -- "$repo" || exit 2

cc=${CC:-cc}
K=${K:-4194304}
N=${N:-9}

command -v "$cc" >/dev/null 2>&1 || {
    printf 'lower/cost: CANNOT MEASURE — no C compiler (%s)\n' "$cc" >&2
    exit 2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-lower-cost.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cat >"$work/probe.c" <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define EXTENT 64

static unsigned long table_data[EXTENT];
/* The extent is a runtime fact: a copy of a volatile read, so the compiler
   cannot prove the check away and cannot fold the comparison. */
static volatile size_t extent_fact = EXTENT;
static volatile unsigned long sink;

static uint64_t walk_state = 0x9e3779b97f4a7c15ULL;

static uint64_t walk_next(void) {
    walk_state ^= walk_state << 13;
    walk_state ^= walk_state >> 7;
    walk_state ^= walk_state << 17;
    return walk_state;
}

/* The mechanism under measurement: a compiler-emitted test+trap per
   enforced access — software_check itself. The index walk is uniform in
   [0, EXTENT), so the branch predicts; what remains is the compare, the
   branch slot and the extent read. */
static unsigned long accesses_checked(size_t len, unsigned long n) {
    unsigned long acc = 0;
    for (unsigned long i = 0; i < n; i++) {
        size_t idx = (size_t)(walk_next() & (EXTENT - 1));
        if (idx >= len) __builtin_trap();
        acc += table_data[idx];
    }
    return acc;
}

/* The same walk with no enforcement: the baseline the check is measured
   against. Identical in every other instruction. */
static unsigned long accesses_plain(size_t len, unsigned long n) {
    (void)len;
    unsigned long acc = 0;
    for (unsigned long i = 0; i < n; i++) {
        size_t idx = (size_t)(walk_next() & (EXTENT - 1));
        acc += table_data[idx];
    }
    return acc;
}

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "selftest") == 0) {
        /* Extent below the index range: a live check must kill the
           process. Completing the loop proves the check was folded. */
        extent_fact = EXTENT / 2;
        sink = accesses_checked(extent_fact, 1UL << 24);
        return 0;
    }
    unsigned long k = argc > 2 ? strtoul(argv[2], NULL, 10) : (1UL << 22);
    int reps = argc > 3 ? atoi(argv[3]) : 9;
    size_t len = extent_fact;
    double best_checked = 1e30;
    double best_plain = 1e30;
    for (int rep = 0; rep < reps; rep++) {
        double a = now_ns();
        sink = accesses_checked(len, k);
        double b = now_ns();
        sink = accesses_plain(len, k);
        double c = now_ns();
        if (b - a < best_checked) best_checked = b - a;
        if (c - b < best_plain) best_plain = c - b;
    }
    printf("%.4f %.4f\n", best_checked / (double)k, best_plain / (double)k);
    return 0;
}
EOF

if ! "$cc" -O2 -std=c11 -D_POSIX_C_SOURCE=199309L -o "$work/probe" "$work/probe.c" 2>"$work/cc.err"; then
    printf 'lower/cost: CANNOT MEASURE — probe does not compile:\n' >&2
    cat "$work/cc.err" >&2
    exit 2
fi

# §0 The control: the check must be live, or nothing is being measured.
"$work/probe" selftest >/dev/null 2>&1
st=$?
if [ "$st" -eq 0 ]; then
    printf 'lower/cost: CANNOT MEASURE — the selftest completed, so the host compiler folded the check away\n' >&2
    exit 2
fi
if [ "$st" -le 128 ]; then
    printf 'lower/cost: CANNOT MEASURE — selftest exit %d is not a trap\n' "$st" >&2
    exit 2
fi
printf 'lower/cost: control — the check is live (selftest killed by signal, status %d)\n' "$st" >&2

# §1 The measurement: interleaved min-of-N, checked and plain per rep.
out=$("$work/probe" run "$K" "$N") || {
    printf 'lower/cost: CANNOT MEASURE — probe run failed\n' >&2
    exit 2
}
checked_ns=${out%% *}
plain_ns=${out##* }
delta_ns=$(awk -v c="$checked_ns" -v p="$plain_ns" 'BEGIN { printf "%.4f", c - p }')

machine=$(uname -m 2>/dev/null || echo unknown)
case "$machine" in
    aarch64|arm64) arch=aarch64 ;;
    x86_64|amd64)  arch=x86_64 ;;
    *)             arch=unknown ;;
esac
system=$(uname -s 2>/dev/null || echo unknown)
case "$system" in
    Linux)  os=linux ;;
    Darwin) os=macos ;;
    *)      os=unknown ;;
esac
dump=$("$cc" -dumpmachine 2>/dev/null || echo unknown)
case "$dump" in
    *musl*) abi=musl ;;
    *)      abi=gnu ;;
esac
triple="$arch-$os-$abi"

revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)

printf '{"schema":"idol.world.cost.v1","mechanism":"software_check","triple":"%s","unit":"nanoseconds","cost":{"access":%s,"crossing":0},"subject_revision":"%s","checked_access_ns":%s,"plain_access_ns":%s,"accesses_per_rep":%s,"reps":%s}\n' \
    "$triple" "$delta_ns" "$revision" "$checked_ns" "$plain_ns" "$K" "$N"
printf 'lower/cost: software_check on %s at %s — checked %s ns/access, plain %s ns/access, enforcement %s ns/access (min-of-%s)\n' \
    "$triple" "$revision" "$checked_ns" "$plain_ns" "$delta_ns" "$N" >&2
