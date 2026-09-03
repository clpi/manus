#!/bin/sh
# gate/index.sh — batch-docs hold for the produced concept verdict (GAP-120).
#
# `tools/concept/index.sh` is the batch generated-docs face of the produced
# concept finding: subject `.id` files as argv elements, one markdown concept
# index on stdout with one line per subject naming the file beside its
# rendered verdict and identity evidence, each line faithful to the
# single-file `tools/concept/doc.sh` render. This gate holds that face. It
# owns no derivation and no enforcement: verdict-correctness (REFUSED exactly
# when the export carries the refusal, HELD otherwise) is owned by
# `gate/concept.sh` over the export; the single-record shape is owned by
# `gate/docs.sh`; refusing a build over refusals is owned by
# `gate/refuse.sh`. What is measured HERE, and nowhere else, is the batch
# boundary — the per-file mapping, argv file passing, and fail-closed
# refusals. An index renders REFUSED subjects; it never refuses over them.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the index as `verdict: REFUSED no_shared_demand` with the
#     produced demand evidence `shared_demand=0`. THE NEGATIVE DIRECTION: a
#     projection that drops a refusal is convicted. The subject file carries
#     a SPACE in its name: a projection that interpolates the path through
#     a host shell splits it and fails, so the spaced path is the positive
#     control for argv passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the line must read `verdict: HELD one concept` with
#     `shared_demand=1`. THE POSITIVE DIRECTION: a projection that refuses
#     a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the line must read
#     `verdict: HELD one concept` with the exact produced identity
#     `relations=2 shapes=0 applications=1 shared_demand=0`. THE THIRD
#     DIRECTION: a projection that refuses a lawful single is convicted.
#     Its evidence differs from the cohort's, so the two HELD rows are
#     distinguished by their evidence, never merged.
# Fail-closed controls: an unreadable subject, an unparseable subject, or no
# subject refuses with a nonzero exit and never an `index: ` line. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201). A missing compiler refuses NOT MEASURED
# (exit 3) — a clean refusal the vacuity scaffold counts as noticing the
# missing subject, never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'index: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
index=$here/../tools/concept/index.sh
doc=$here/../tools/concept/doc.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'index: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$index" ]; then
    printf 'index: NOT MEASURED — %s is not executable (the batch projection was required)\n' "$index" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'index: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.index.XXXXXX") || exit 3
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
# positive controls that every produced direction crossed the batch boundary.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# demand_line <label> <file> <needle> [...]: one subject in, exit 0, exactly
# one `index: ` line naming the file, every needle on it.
demand_line() {
    label=$1
    file=$2
    shift 2
    resp=$work/respLine.txt
    if ! sh "$index" "$file" >"$resp" 2>"$resp.diag"; then
        printf 'index: FAIL — %s refused where a render was demanded\n' "$label" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    n=$(grep -c '^index: ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'index: FAIL — %s rendered %s index line(s), not one; a subject is never lost or doubled\n' "$label" "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    for needle in "$@"; do
        grep -Fq "$needle" <"$resp" || {
            printf 'index: FAIL — %s rendered yet carried nothing with %s\n' "$label" "$needle" >&2
            cat "$resp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
}

# demand_closed <label> [--] [args ...]: the batch must refuse with a
# nonzero exit and never an `index: ` line.
demand_closed() {
    label=$1
    shift
    resp=$work/respClosed.txt
    if sh "$index" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'index: FAIL — %s rendered where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "index: " <"$resp" && {
        printf 'index: FAIL — %s refused yet carried an index line; a refusal is never render-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_line refused-bucket "$work/my bucket.id" "index: $work/my bucket.id" "verdict: REFUSED no_shared_demand" "shared_demand=0"
demand_line held-cohort "$work/cohort.id" "index: $work/cohort.id" "verdict: HELD one concept" "shared_demand=1"
demand_line held-unwitnessed "$work/unwitnessed.id" "index: $work/unwitnessed.id" "verdict: HELD one concept" "relations=2 shapes=0 applications=1 shared_demand=0"

# ── the batch: three subjects in, three lines out, each file beside its own
# verdict — no lost subject, no invented row, no swapped verdict.
resp=$work/respBatch.txt
if ! sh "$index" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$resp" 2>"$resp.diag"; then
    printf 'index: FAIL — batch refused where a render was demanded\n' >&2
    cat "$resp" >&2
    cat "$resp.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    n=$(grep -c '^index: ' <"$resp") || n=0
    [ "$n" -eq 3 ] || {
        printf 'index: FAIL — batch rendered %s index line(s), not three\n' "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "index: $work/my bucket.id" <"$resp" && grep -Fq "verdict: REFUSED no_shared_demand" <"$resp" || {
        printf 'index: FAIL — batch lost the refused bucket verdict\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "index: $work/cohort.id" <"$resp" || {
        printf 'index: FAIL — batch lost the cohort line\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "index: $work/unwitnessed.id" <"$resp" || {
        printf 'index: FAIL — batch lost the unwitnessed line\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
fi

# ── faithfulness: the bucket index line carries exactly what the
# single-file render produced — the mapping invents nothing.
if ! sh "$doc" "$work/my bucket.id" >"$work/docBucket.txt" 2>"$work/docBucket.diag"; then
    printf 'index: FAIL — single-file render refused the bucket; faithfulness unmeasurable\n' >&2
    cat "$work/docBucket.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    verdict=$(grep '^verdict: ' "$work/docBucket.txt" | head -n 1) || verdict=""
    identity=$(grep '^identity: ' "$work/docBucket.txt" | head -n 1) || identity=""
    # shellcheck disable=SC2181
    [ -n "$verdict" ] && [ -n "$identity" ] || {
        printf 'index: FAIL — single-file render unreadable; faithfulness unmeasurable\n' >&2
        failed=$((failed + 1))
    }
    if ! sh "$index" "$work/my bucket.id" >"$work/idxBucket.txt" 2>"$work/idxBucket.diag"; then
        printf 'index: FAIL — batch refused the bucket; faithfulness unmeasurable\n' >&2
        failed=$((failed + 1))
    else
        grep -Fq "$verdict" <"$work/idxBucket.txt" || {
            printf 'index: FAIL — index line dropped the rendered verdict\n' >&2
            cat "$work/idxBucket.txt" >&2
            failed=$((failed + 1))
        }
        grep -Fq "$identity" <"$work/idxBucket.txt" || {
            printf 'index: FAIL — index line dropped the rendered identity\n' >&2
            cat "$work/idxBucket.txt" >&2
            failed=$((failed + 1))
        }
    fi
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unreadable-subject "$work/absent.id"
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

# ── not measured: a missing compiler refuses exit 3, never a render.
resp=$work/respUnmeasured.txt
if IDOL=/nonexistent sh "$index" "$work/cohort.id" >"$resp" 2>"$resp.diag"; then
    printf 'index: FAIL — missing compiler rendered where NOT MEASURED was demanded\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    rc=$?
    examined=$((examined + 1))
    [ "$rc" -eq 3 ] || {
        printf 'index: FAIL — missing compiler refused with %s, not NOT MEASURED (3)\n' "$rc" >&2
        failed=$((failed + 1))
    }
fi

[ "$examined" -gt 0 ] || {
    printf 'index: FAIL — 0 index examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'index: FAIL — %s of %s examined index(es) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'index: PASS — %s examined index(es), 0 failed\n' "$examined"
exit 0
