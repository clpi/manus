#!/bin/sh
# gate/page.sh — batch-page hold for the produced concept verdict (GAP-120).
#
# `tools/concept/page.sh` is the batch generated-docs page of the produced
# concept finding: subject `.id` files as argv elements, one markdown concept
# page on stdout carrying every subject's full `tools/concept/doc.sh` record
# as its own section, in argv order. This gate holds that face. It owns the
# joining only and no derivation, no mapping, and no enforcement:
# verdict-correctness (REFUSED exactly when the export carries the refusal,
# HELD otherwise) is owned by `gate/concept.sh` over the export; the
# single-record shape is owned by `gate/docs.sh`; the one-line mapping is
# owned by `gate/index.sh`; refusing a build over refusals is owned by
# `gate/refuse.sh`. What is measured HERE, and nowhere else, is the batch
# joining — every subject sectioned exactly once, in order, every section
# faithful to its single-file render — plus argv file passing and fail-closed
# refusals. A page sections REFUSED subjects; it never refuses over them.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself a page:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the page as a section carrying
#     `verdict: REFUSED no_shared_demand` with the produced demand evidence
#     `shared_demand=0`. THE NEGATIVE DIRECTION: a page that drops a refusal
#     is convicted. The subject file carries a SPACE in its name: a page
#     that interpolates the path through a host shell splits it and fails,
#     so the spaced path is the positive control for argv passing
#     (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the section must carry `verdict: HELD one concept` with
#     `shared_demand=1`. THE POSITIVE DIRECTION: a page that refuses a
#     lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the section must carry
#     `verdict: HELD one concept` with the exact produced identity
#     `relations=2 shapes=0 applications=1 shared_demand=0`. THE THIRD
#     DIRECTION: a page that refuses a lawful single is convicted. Its
#     evidence differs from the cohort's, so the two HELD sections are
#     distinguished by their evidence, never merged.
# Fail-closed controls: an unreadable subject, an unparseable subject, or no
# subject refuses with a nonzero exit and never a section (`## `) or verdict
# (`verdict: `) line. A row whose measured answer differs from its demanded
# answer FAILS. Zero rows examined FAILS (GAP-201). A missing compiler
# refuses NOT MEASURED (exit 3) — a clean refusal the vacuity scaffold counts
# as noticing the missing subject, never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'page: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
page=$here/../tools/concept/page.sh
doc=$here/../tools/concept/doc.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'page: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$page" ]; then
    printf 'page: NOT MEASURED — %s is not executable (the batch page was required)\n' "$page" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'page: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.page.XXXXXX") || exit 3
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
# positive controls that every produced direction crossed the page boundary.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# demand_section <label> <file> <needle> [...]: one subject in, exit 0,
# exactly one `## ` section naming the file, every needle in the page.
demand_section() {
    label=$1
    file=$2
    shift 2
    resp=$work/respSection.txt
    if ! sh "$page" "$file" >"$resp" 2>"$resp.diag"; then
        printf 'page: FAIL — %s refused where a page was demanded\n' "$label" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    n=$(grep -c '^## ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'page: FAIL — %s sectioned %s time(s), not once; a subject is never lost or doubled\n' "$label" "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "## $file" <"$resp" || {
        printf 'page: FAIL — %s section names nothing with %s\n' "$label" "$file" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    for needle in "$@"; do
        grep -Fq "$needle" <"$resp" || {
            printf 'page: FAIL — %s sectioned yet carried nothing with %s\n' "$label" "$needle" >&2
            cat "$resp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
}

# demand_closed <label> [--] [args ...]: the page must refuse with a
# nonzero exit and never a section or verdict line.
demand_closed() {
    label=$1
    shift
    resp=$work/respClosed.txt
    if sh "$page" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'page: FAIL — %s paged where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "## " <"$resp" && {
        printf 'page: FAIL — %s refused yet carried a section; a refusal is never page-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "verdict: " <"$resp" && {
        printf 'page: FAIL — %s refused yet carried a verdict; a refusal is never page-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_section refused-bucket "$work/my bucket.id" "# Concept record — " "source: $work/my bucket.id" "verdict: REFUSED no_shared_demand" "shared_demand=0"
demand_section held-cohort "$work/cohort.id" "# Concept record — " "source: $work/cohort.id" "verdict: HELD one concept" "shared_demand=1"
demand_section held-unwitnessed "$work/unwitnessed.id" "# Concept record — " "source: $work/unwitnessed.id" "verdict: HELD one concept" "relations=2 shapes=0 applications=1 shared_demand=0"

# ── the batch: three subjects in, three sections out in argv order, each
# file beside its own verdict — no lost subject, no invented section, no
# swapped verdict.
resp=$work/respBatch.txt
if ! sh "$page" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$resp" 2>"$resp.diag"; then
    printf 'page: FAIL — batch refused where a page was demanded\n' >&2
    cat "$resp" >&2
    cat "$resp.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    n=$(grep -c '^## ' <"$resp") || n=0
    [ "$n" -eq 3 ] || {
        printf 'page: FAIL — batch sectioned %s time(s), not three\n' "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    {
        printf '## %s\n' "$work/my bucket.id"
        printf '## %s\n' "$work/cohort.id"
        printf '## %s\n' "$work/unwitnessed.id"
    } >"$work/wantHeaders.txt"
    grep '^## ' <"$resp" >"$work/gotHeaders.txt" || : >"$work/gotHeaders.txt"
    cmp -s "$work/wantHeaders.txt" "$work/gotHeaders.txt" || {
        printf 'page: FAIL — batch sections are not the subjects in argv order; the joining invents or reorders\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "verdict: REFUSED no_shared_demand" <"$resp" || {
        printf 'page: FAIL — batch lost the refused bucket verdict\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    grep -Fq "verdict: HELD one concept" <"$resp" || {
        printf 'page: FAIL — batch lost a held verdict\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
fi

# ── faithfulness: the bucket page section carries exactly what the
# single-file render produced — the joining invents nothing.
if ! sh "$doc" "$work/my bucket.id" >"$work/docBucket.txt" 2>"$work/docBucket.diag"; then
    printf 'page: FAIL — single-file render refused the bucket; faithfulness unmeasurable\n' >&2
    cat "$work/docBucket.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    verdict=$(grep '^verdict: ' "$work/docBucket.txt" | head -n 1) || verdict=""
    identity=$(grep '^identity: ' "$work/docBucket.txt" | head -n 1) || identity=""
    record=$(grep -F '# Concept record — ' "$work/docBucket.txt" | head -n 1) || record=""
    # shellcheck disable=SC2181
    { [ -n "$verdict" ] && [ -n "$identity" ] && [ -n "$record" ]; } || {
        printf 'page: FAIL — single-file render unreadable; faithfulness unmeasurable\n' >&2
        failed=$((failed + 1))
    }
    if ! sh "$page" "$work/my bucket.id" >"$work/pgBucket.txt" 2>"$work/pgBucket.diag"; then
        printf 'page: FAIL — batch page refused the bucket; faithfulness unmeasurable\n' >&2
        failed=$((failed + 1))
    else
        grep -Fq "$verdict" <"$work/pgBucket.txt" || {
            printf 'page: FAIL — page section dropped the rendered verdict\n' >&2
            cat "$work/pgBucket.txt" >&2
            failed=$((failed + 1))
        }
        grep -Fq "$identity" <"$work/pgBucket.txt" || {
            printf 'page: FAIL — page section dropped the rendered identity\n' >&2
            cat "$work/pgBucket.txt" >&2
            failed=$((failed + 1))
        }
        grep -Fq "$record" <"$work/pgBucket.txt" || {
            printf 'page: FAIL — page section dropped the record header\n' >&2
            cat "$work/pgBucket.txt" >&2
            failed=$((failed + 1))
        }
    fi
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unreadable-subject "$work/absent.id"
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

# ── not measured: a missing compiler refuses exit 3, never a page.
resp=$work/respUnmeasured.txt
if IDOL=/nonexistent sh "$page" "$work/cohort.id" >"$resp" 2>"$resp.diag"; then
    printf 'page: FAIL — missing compiler paged where NOT MEASURED was demanded\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    rc=$?
    examined=$((examined + 1))
    [ "$rc" -eq 3 ] || {
        printf 'page: FAIL — missing compiler refused with %s, not NOT MEASURED (3)\n' "$rc" >&2
        failed=$((failed + 1))
    }
fi

[ "$examined" -gt 0 ] || {
    printf 'page: FAIL — 0 page examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'page: FAIL — %s of %s examined page(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'page: PASS — %s examined page(s), 0 failed\n' "$examined"
exit 0
