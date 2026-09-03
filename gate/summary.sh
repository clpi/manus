#!/bin/sh
# gate/summary.sh — batch-summary hold for the produced concept verdict (GAP-120).
#
# `tools/concept/summary.sh` is the batch verdict reduction of the produced
# concept finding: subject `.id` files as argv elements, one `summary: `
# line on stdout counting how many subjects the batch index render held
# and refused. This gate holds that face. It owns the reduction and
# nothing else — no derivation, no mapping, no enforcement, no joining:
# verdict-correctness (REFUSED exactly when the export carries the
# refusal, HELD otherwise) is owned by `gate/concept.sh` over the export;
# the single-record shape is owned by `gate/docs.sh`; the one-line mapping
# is owned by `gate/index.sh`; the section joining is owned by
# `gate/page.sh`; the index-plus-section joining is owned by
# `gate/site.sh`; refusing a build over refusals is owned by
# `gate/refuse.sh`. What is measured HERE, and nowhere else, is the
# count — every subject counted exactly once beside the verdict its own
# index line produced, no lost subject, no invented row, no swapped
# count. A summary renders REFUSED subjects; it never refuses over them.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself a summary:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the summary as `summary: 0 held 1 refused of 1`. THE
#     NEGATIVE DIRECTION: a summary that loses a refusal is convicted.
#     The subject file carries a SPACE in its name: a summary that
#     interpolates the path through a host shell splits it and fails, so
#     the spaced path is the positive control for argv passing
#     (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the summary must answer `summary: 1 held 0 refused
#     of 1`. THE POSITIVE DIRECTION: a summary that refuses a lawful
#     cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the summary must answer `summary: 1
#     held 0 refused of 1`. THE THIRD DIRECTION: a summary that refuses
#     a lawful single is convicted. Its evidence differs from the
#     cohort's, so the two HELD rows are distinguished by the demand
#     evidence the index line carries beside the verdict, never merged.
# Fail-closed controls: an unreadable subject, an unparseable subject, or
# no subject refuses with a nonzero exit and never a `summary: ` line. A
# row whose measured answer differs from its demanded answer FAILS. Zero
# rows examined FAILS (GAP-201). A missing compiler refuses NOT MEASURED
# (exit 3) — a clean refusal the vacuity scaffold counts as noticing the
# missing subject, never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'summary: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
summary=$here/../tools/concept/summary.sh
index=$here/../tools/concept/index.sh

if [ ! -x "$IDOL" ]; then
    printf 'summary: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$summary" ]; then
    printf 'summary: NOT MEASURED — %s is not executable (the batch summary was required)\n' "$summary" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'summary: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.summary.XXXXXX") || exit 3
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
# positive controls that every produced direction crossed the reduction
# boundary with its own count.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# demand_summary <label> <want> <file> [...]: the subjects in, exit 0, the
# one demanded `summary: ` line and nothing else shaped like it.
demand_summary() {
    label=$1
    want=$2
    shift 2
    resp=$work/respSummary.txt
    if ! sh "$summary" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'summary: FAIL — %s refused where a summary was demanded\n' "$label" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    n=$(grep -c '^summary: ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'summary: FAIL — %s summarized %s time(s), not once; a batch is never lost or doubled\n' "$label" "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fxq "$want" <"$resp" || {
        printf 'summary: FAIL — %s summarized yet carried nothing with [%s]\n' "$label" "$want" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_closed <label> [--] [args ...]: the summary must refuse with a
# nonzero exit and never a `summary: ` line.
demand_closed() {
    label=$1
    shift
    resp=$work/respClosed.txt
    if sh "$summary" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'summary: FAIL — %s summarized where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "summary: " <"$resp" && {
        printf 'summary: FAIL — %s refused yet carried a summary; a refusal is never summary-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_summary refused-bucket "summary: 0 held 1 refused of 1" "$work/my bucket.id"
demand_summary held-cohort "summary: 1 held 0 refused of 1" "$work/cohort.id"
demand_summary held-unwitnessed "summary: 1 held 0 refused of 1" "$work/unwitnessed.id"

# ── the batch: three subjects in, one reduction out — two held beside
# one refused, with the held rows distinguished by the demand evidence
# their own index lines carry.
resp=$work/respBatch.txt
if ! sh "$summary" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$resp" 2>"$resp.diag"; then
    printf 'summary: FAIL — batch refused where a summary was demanded\n' >&2
    cat "$resp" >&2
    cat "$resp.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    n=$(grep -c '^summary: ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'summary: FAIL — batch summarized %s time(s), not once\n' "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fxq "summary: 2 held 1 refused of 3" <"$resp" || {
        printf 'summary: FAIL — batch summarized yet carried nothing with [summary: 2 held 1 refused of 3]\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
fi

# ── faithfulness: the batch reduction counts exactly what the standalone
# index render produced — the reduction invents nothing. The expected
# counts are derived from the index lines themselves, never hand-written.
if ! sh "$index" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$work/idxBatch.txt" 2>"$work/idxBatch.diag"; then
    printf 'summary: FAIL — standalone index refused the batch; faithfulness unmeasurable\n' >&2
    cat "$work/idxBatch.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
elif ! sh "$summary" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$work/sumBatch.txt" 2>"$work/sumBatch.diag"; then
    printf 'summary: FAIL — summary refused the batch; faithfulness unmeasurable\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    want_h=$(grep -c '^index: .* verdict: HELD' <"$work/idxBatch.txt") || want_h=0
    want_r=$(grep -c '^index: .* verdict: REFUSED' <"$work/idxBatch.txt") || want_r=0
    want_n=$(grep -c '^index: ' <"$work/idxBatch.txt") || want_n=0
    printf 'summary: %s held %s refused of %s\n' "$want_h" "$want_r" "$want_n" >"$work/wantSummary.txt"
    grep '^summary: ' "$work/sumBatch.txt" >"$work/gotSummary.txt" || : >"$work/gotSummary.txt"
    cmp -s "$work/wantSummary.txt" "$work/gotSummary.txt" || {
        printf 'summary: FAIL — batch reduction differs from the standalone index render; the reduction invents\n' >&2
        cat "$work/sumBatch.txt" >&2
        failed=$((failed + 1))
    }
    # The two HELD rows are distinguished by their produced demand
    # evidence, never merged: exactly one HELD line holds over
    # shared_demand=1 (the cohort), and the other over the exact
    # unwitnessed produced identity.
    n=$(grep -c '^index: .* verdict: HELD one concept identity: .* shared_demand=1$' <"$work/idxBatch.txt") || n=0
    [ "$n" -eq 1 ] || {
        printf 'summary: FAIL — batch index carries %s cohort HELD line(s) with shared_demand=1, not one; the held rows merge\n' "$n" >&2
        cat "$work/idxBatch.txt" >&2
        failed=$((failed + 1))
    }
    grep -Fq "verdict: HELD one concept identity: relations=2 shapes=0 applications=1 shared_demand=0" <"$work/idxBatch.txt" || {
        printf 'summary: FAIL — batch index carries no unwitnessed HELD with its exact produced identity; the held rows merge\n' >&2
        cat "$work/idxBatch.txt" >&2
        failed=$((failed + 1))
    }
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unreadable-subject "$work/absent.id"
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

# ── not measured: a missing compiler refuses exit 3, never a summary.
resp=$work/respUnmeasured.txt
if IDOL=/nonexistent sh "$summary" "$work/cohort.id" >"$resp" 2>"$resp.diag"; then
    printf 'summary: FAIL — missing compiler summarized where NOT MEASURED was demanded\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    rc=$?
    examined=$((examined + 1))
    [ "$rc" -eq 3 ] || {
        printf 'summary: FAIL — missing compiler refused with %s, not NOT MEASURED (3)\n' "$rc" >&2
        failed=$((failed + 1))
    }
fi

[ "$examined" -gt 0 ] || {
    printf 'summary: FAIL — 0 summary examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'summary: FAIL — %s of %s examined summar(ies) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'summary: PASS — %s examined summar(ies), 0 failed\n' "$examined"
exit 0
