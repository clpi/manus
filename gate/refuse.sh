#!/bin/sh
# gate/refuse.sh — build-refusal hold for the produced concept verdict (GAP-120).
#
# `tools/concept/refuse.sh` is the build-refusal face of the produced concept
# finding: subject `.id` files as argv elements, one verdict line per file,
# and a nonzero exit naming the refused module when any subject's export
# carries a produced refusal. This gate holds that face. It owns no
# derivation: verdict-correctness (REFUSED exactly when the export carries
# the refusal, HELD otherwise) is owned by `gate/concept.sh` over the export;
# what is measured HERE, and nowhere else, is the refusal boundary — the
# exit-code enforcement, the refused module named on stdout, argv file
# passing, and fail-closed refusals.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must refuse the build — exit 1 with `refuse: REFUSED` naming the
#     reason. THE NEGATIVE DIRECTION: an enforcement that holds a bucket
#     is convicted. The subject file carries a SPACE in its name: an
#     enforcement that interpolates the path through a host shell splits
#     it and fails, so the spaced path is the positive control for argv
#     passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the build must hold — exit 0 with `refuse: HELD`.
#     THE POSITIVE DIRECTION: an enforcement that refuses a lawful cohort
#     is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the build must hold — exit 0 with
#     `refuse: HELD`. THE THIRD DIRECTION: an enforcement that refuses a
#     lawful single is convicted.
# Fail-closed controls: an unreadable subject, an unparseable subject, or no
# subject refuses with a nonzero exit and never a HELD-shaped line. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'refuse: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
refuse=$here/../tools/concept/refuse.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'refuse: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$refuse" ]; then
    printf 'refuse: NOT MEASURED — %s is not executable (the refusal projection was required)\n' "$refuse" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'refuse: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.refuse.XXXXXX") || exit 3
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the subjects ─────────────────────────────────────────────────────────
# Same three shapes `gate/concept.sh` materializes (bucket: no subject drives
# both relations — refused; cohort: one subject drives both — held;
# unwitnessed: nothing applies the one relation — held). The
# verdict-correctness of those shapes is owned there; here they are the
# positive controls that the refusal crossed the enforcement boundary intact.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# demand_refuse <label> <file> <needle>: the build must refuse — nonzero exit
# with the needle on stdout naming what was refused.
demand_refuse() {
    label=$1
    file=$2
    needle=$3
    resp=$work/respRefuse.txt
    if sh "$refuse" "$file" >"$resp" 2>"$resp.diag"; then
        printf 'refuse: FAIL — %s held where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "$needle" <"$resp" || {
        printf 'refuse: FAIL — %s refused yet named nothing with %s\n' "$label" "$needle" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_hold <label> <file>: the build must hold — exit 0 with a HELD line
# and never a REFUSED line.
demand_hold() {
    resp=$work/respHold.txt
    if ! sh "$refuse" "$2" >"$resp" 2>"$resp.diag"; then
        printf 'refuse: FAIL — %s refused where a hold was demanded\n' "$1" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "refuse: HELD" <"$resp" || {
        printf 'refuse: FAIL — %s held yet carried no HELD line\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "refuse: REFUSED" <"$resp" && {
        printf 'refuse: FAIL — %s held yet carried a REFUSED line; a hold is never refusal-shaped\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_closed <label> [--] [args ...]: the enforcement must refuse with a
# nonzero exit and never a HELD-shaped line.
demand_closed() {
    label=$1
    shift
    resp=$work/respClosed.txt
    if sh "$refuse" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'refuse: FAIL — %s held where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "refuse: HELD" <"$resp" && {
        printf 'refuse: FAIL — %s refused yet carried a HELD line; a refusal is never hold-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_refuse refused-bucket "$work/my bucket.id" "refuse: REFUSED"
demand_refuse refused-bucket-reason "$work/my bucket.id" "no_shared_demand"
demand_hold held-cohort "$work/cohort.id"
demand_hold held-unwitnessed "$work/unwitnessed.id"

# A multi-subject build refuses when ANY subject is refused: the bucket
# among held company still fails the build.
resp=$work/respMixed.txt
if sh "$refuse" "$work/cohort.id" "$work/my bucket.id" "$work/unwitnessed.id" >"$resp" 2>"$resp.diag"; then
    printf 'refuse: FAIL — mixed build held where a refusal was demanded\n' >&2
    cat "$resp" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    grep -Fq "refuse: REFUSED" <"$resp" || {
        printf 'refuse: FAIL — mixed build refused yet named no refused module\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "refuse: HELD $work/cohort.id" <"$resp" || {
        printf 'refuse: FAIL — mixed build refused yet lost the held cohort line\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unreadable-subject "$work/absent.id"
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

[ "$examined" -gt 0 ] || {
    printf 'refuse: FAIL — 0 refusal examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'refuse: FAIL — %s of %s examined refusal(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'refuse: PASS — %s examined refusal(s), 0 failed\n' "$examined"
exit 0
