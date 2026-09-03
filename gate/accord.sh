#!/bin/sh
# gate/accord.sh — render/enforcement agreement hold for the produced concept verdict (GAP-120).
#
# `tools/concept/site.sh` is the batch generated-docs site of the produced
# concept finding: it RENDERS refusals as index lines plus record sections
# and never refuses over them. `tools/concept/refuse.sh` is the
# build-refusal face of the same finding: it REFUSES the build over the
# export's `refusals[]` and never renders a record. This gate holds the
# agreement no sibling gate holds: the verdict the site renders for a
# subject must be the verdict the enforcement answers for it. A site
# rendering HELD beside an enforcement refusing the same bucket passes
# both sibling gates while agreeing with nothing; here it FAILS naming
# the diverged face. It owns the agreement ONLY and no derivation, no
# joining, no mapping, and no enforcement: verdict-correctness (REFUSED
# exactly when the export carries the refusal, HELD otherwise) is owned
# by `gate/concept.sh` over the export; the single-record shape is owned
# by `gate/docs.sh`; the one-line mapping is owned by `gate/index.sh`;
# the section joining is owned by `gate/page.sh`; the index-plus-section
# joining is owned by `gate/site.sh`; the exit-code enforcement is owned
# by `gate/refuse.sh`.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an agreement:
#   bucket refused: the site must carry `verdict: REFUSED no_shared_demand`
#     with `shared_demand=0` AND the enforcement must refuse the build —
#     nonzero exit with `refuse: REFUSED` naming the reason. THE NEGATIVE
#     DIRECTION: an enforcement that holds a rendered bucket is convicted,
#     and a site that holds a refused bucket is convicted. The subject
#     file carries a SPACE in its name: a face that interpolates the path
#     through a host shell splits it and fails, so the spaced path is the
#     positive control for argv passing on both faces at once
#     (host-transport norm).
#   cohort held: the site must carry `verdict: HELD one concept` with
#     `shared_demand=1` AND the enforcement must hold — exit 0 with
#     `refuse: HELD` and never a REFUSED line. THE POSITIVE DIRECTION: a
#     face that refuses a lawful cohort is convicted.
#   unwitnessed held: the site must carry `verdict: HELD one concept`
#     with the exact produced identity
#     `relations=2 shapes=0 applications=1 shared_demand=0` AND the
#     enforcement must hold — exit 0 with `refuse: HELD` and never a
#     REFUSED line. THE THIRD DIRECTION: a face that refuses a lawful
#     single is convicted. Its evidence differs from the cohort's, so the
#     two HELD rows are distinguished by their evidence, never merged.
# Fail-closed controls: an unparseable subject or no subject refuses on
# both faces with a nonzero exit and never a verdict-shaped answer. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201). A missing compiler refuses NOT MEASURED
# (exit 3) on both faces — a clean refusal the vacuity scaffold counts
# as noticing the missing subject, never a pass.
#
# ACCORD_SITE / ACCORD_REFUSE point the gate at the faces it holds
# (default: the `tools/concept` projections). When a served arm lands it
# must satisfy this gate with the seam pointed at it; the projections
# then become its conformance oracle, not a second enforcement.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'accord: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
site=${ACCORD_SITE:-"$here/../tools/concept/site.sh"}
refuse=${ACCORD_REFUSE:-"$here/../tools/concept/refuse.sh"}

if [ ! -x "$IDOL" ]; then
    printf 'accord: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$site" ]; then
    printf 'accord: NOT MEASURED — %s is not executable (the batch site was required)\n' "$site" >&2
    exit 3
fi
if [ ! -x "$refuse" ]; then
    printf 'accord: NOT MEASURED — %s is not executable (the refusal projection was required)\n' "$refuse" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'accord: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.accord.XXXXXX") || exit 3
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
# positive controls that the render and the enforcement answer every
# produced direction together.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# demand_refused <label> <file> <needle> [...]: the site must render the
# refusal AND the enforcement must refuse the build over it, or the faces
# disagree and the row FAILS naming the diverged face.
demand_refused() {
    label=$1
    file=$2
    shift 2
    sresp=$work/respAccordSite.txt
    rresp=$work/respAccordRefuse.txt
    if ! sh "$site" "$file" >"$sresp" 2>"$sresp.diag"; then
        printf 'accord: FAIL — %s site refused where a render was demanded\n' "$label" >&2
        cat "$sresp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    if sh "$refuse" "$file" >"$rresp" 2>"$rresp.diag"; then
        printf 'accord: FAIL — %s enforcement held where a refusal was demanded; the render and the enforcement disagree\n' "$label" >&2
        cat "$sresp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    for needle in "$@"; do
        grep -Fq "$needle" <"$sresp" || {
            printf 'accord: FAIL — %s rendered yet carried nothing with %s; the site face diverged\n' "$label" "$needle" >&2
            cat "$sresp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
    grep -Fq "refuse: REFUSED" <"$rresp" || {
        printf 'accord: FAIL — %s refused yet named no refused module; the enforcement face diverged\n' "$label" >&2
        cat "$rresp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "no_shared_demand" <"$rresp" || {
        printf 'accord: FAIL — %s refused yet named nothing with no_shared_demand; the enforcement face diverged\n' "$label" >&2
        cat "$rresp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_held <label> <file> <needle> [...]: the site must render HELD AND
# the enforcement must hold the build, or the faces disagree and the row
# FAILS naming the diverged face.
demand_held() {
    label=$1
    file=$2
    shift 2
    sresp=$work/respAccordSite.txt
    rresp=$work/respAccordRefuse.txt
    if ! sh "$site" "$file" >"$sresp" 2>"$sresp.diag"; then
        printf 'accord: FAIL — %s site refused where a render was demanded\n' "$label" >&2
        cat "$sresp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    if ! sh "$refuse" "$file" >"$rresp" 2>"$rresp.diag"; then
        printf 'accord: FAIL — %s enforcement refused where a hold was demanded; the render and the enforcement disagree\n' "$label" >&2
        cat "$rresp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    for needle in "$@"; do
        grep -Fq "$needle" <"$sresp" || {
            printf 'accord: FAIL — %s rendered yet carried nothing with %s; the site face diverged\n' "$label" "$needle" >&2
            cat "$sresp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
    grep -Fq "refuse: HELD" <"$rresp" || {
        printf 'accord: FAIL — %s held yet carried no HELD line; the enforcement face diverged\n' "$label" >&2
        cat "$rresp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "refuse: REFUSED" <"$rresp" && {
        printf 'accord: FAIL — %s held yet carried a REFUSED line; a hold is never refusal-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_closed <label> [--] [args ...]: both faces must refuse with a
# nonzero exit and never a verdict-shaped answer.
demand_closed() {
    label=$1
    shift
    sresp=$work/respAccordClosedSite.txt
    rresp=$work/respAccordClosedRefuse.txt
    if sh "$site" "$@" >"$sresp" 2>"$sresp.diag"; then
        printf 'accord: FAIL — %s site rendered where a refusal was demanded\n' "$label" >&2
        cat "$sresp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    if sh "$refuse" "$@" >"$rresp" 2>"$rresp.diag"; then
        printf 'accord: FAIL — %s enforcement held where a refusal was demanded\n' "$label" >&2
        cat "$rresp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "verdict: " <"$sresp" && {
        printf 'accord: FAIL — %s site refused yet carried a verdict; a refusal is never site-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "refuse: HELD" <"$rresp" && {
        printf 'accord: FAIL — %s enforcement refused yet carried a HELD line; a refusal is never hold-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_refused refused-bucket "$work/my bucket.id" "verdict: REFUSED no_shared_demand" "shared_demand=0"
demand_held held-cohort "$work/cohort.id" "verdict: HELD one concept" "shared_demand=1"
demand_held held-unwitnessed "$work/unwitnessed.id" "verdict: HELD one concept" "relations=2 shapes=0 applications=1 shared_demand=0"

# ── the batch: three subjects in, the site renders all three while the
# enforcement refuses the batch — every subject rendered beside the
# verdict the enforcement answers for it, in argv order.
sresp=$work/respAccordBatchSite.txt
rresp=$work/respAccordBatchRefuse.txt
if ! sh "$site" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$sresp" 2>"$sresp.diag"; then
    printf 'accord: FAIL — batch site refused where a render was demanded\n' >&2
    cat "$sresp.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
elif sh "$refuse" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$rresp" 2>"$rresp.diag"; then
    printf 'accord: FAIL — batch enforcement held where a refusal was demanded; the render and the enforcement disagree\n' >&2
    cat "$sresp" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    grep -Fq "index: $work/my bucket.id verdict: REFUSED no_shared_demand" <"$sresp" || {
        printf 'accord: FAIL — batch site names nothing refused for the bucket; the site face diverged\n' >&2
        cat "$sresp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "index: $work/cohort.id verdict: HELD one concept" <"$sresp" || {
        printf 'accord: FAIL — batch site names nothing held for the cohort; the site face diverged\n' >&2
        cat "$sresp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "index: $work/unwitnessed.id verdict: HELD one concept" <"$sresp" || {
        printf 'accord: FAIL — batch site names nothing held for the unwitnessed; the site face diverged\n' >&2
        cat "$sresp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "refuse: REFUSED" <"$rresp" || {
        printf 'accord: FAIL — batch enforcement refused yet named no refused module; the enforcement face diverged\n' >&2
        cat "$rresp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "refuse: HELD $work/cohort.id" <"$rresp" || {
        printf 'accord: FAIL — batch enforcement refused yet lost the held cohort line; the enforcement face diverged\n' >&2
        cat "$rresp" >&2
        failed=$((failed + 1))
    }
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

# ── not measured: a missing compiler refuses exit 3 on both faces, never
# an agreement.
sresp=$work/respAccordUnmeasuredSite.txt
rresp=$work/respAccordUnmeasuredRefuse.txt
IDOL=/nonexistent sh "$site" "$work/cohort.id" >"$sresp" 2>"$sresp.diag"
src=$?
IDOL=/nonexistent sh "$refuse" "$work/cohort.id" >"$rresp" 2>"$rresp.diag"
rrc=$?
examined=$((examined + 1))
[ "$src" -eq 3 ] || {
    printf 'accord: FAIL — missing compiler sited with %s, not NOT MEASURED (3)\n' "$src" >&2
    failed=$((failed + 1))
}
[ "$rrc" -eq 3 ] || {
    printf 'accord: FAIL — missing compiler enforced with %s, not NOT MEASURED (3)\n' "$rrc" >&2
    failed=$((failed + 1))
}

[ "$examined" -gt 0 ] || {
    printf 'accord: FAIL — 0 accord examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'accord: FAIL — %s of %s examined accord(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'accord: PASS — %s examined accord(s), 0 failed\n' "$examined"
exit 0
