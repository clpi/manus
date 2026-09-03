#!/bin/sh
# gate/site.sh — batch-site hold for the produced concept verdict (GAP-120).
#
# `tools/concept/site.sh` is the batch generated-docs site of the produced
# concept finding: subject `.id` files as argv elements, one markdown
# concept site on stdout carrying the batch `tools/concept/index.sh` block
# followed by the batch `tools/concept/page.sh` sections, in argv order.
# This gate holds that face. It owns the joining and the cross-face
# agreement only and no derivation, no mapping, and no enforcement:
# verdict-correctness (REFUSED exactly when the export carries the refusal,
# HELD otherwise) is owned by `gate/concept.sh` over the export; the
# single-record shape is owned by `gate/docs.sh`; the one-line mapping is
# owned by `gate/index.sh`; the section joining is owned by `gate/page.sh`;
# refusing a build over refusals is owned by `gate/refuse.sh`. What is
# measured HERE, and nowhere else, is the site joining — every subject
# indexed and sectioned exactly once, in order, every line and section
# faithful to its standalone render — plus the agreement no sibling gate
# holds: the verdict the site's index block names for a subject must be the
# verdict the site's own section carries for it. An index naming REFUSED
# beside a section holding HELD for the same subject passes both sibling
# gates while agreeing with nothing; here it FAILS naming the diverged
# face. A site renders REFUSED subjects; it never refuses over them.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself a site:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the site as an index line and a section each carrying
#     `verdict: REFUSED no_shared_demand` with the produced demand evidence
#     `shared_demand=0`. THE NEGATIVE DIRECTION: a site that drops a refusal
#     is convicted. The subject file carries a SPACE in its name: a site
#     that interpolates the path through a host shell splits it and fails,
#     so the spaced path is the positive control for argv passing
#     (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the line and the section must each carry
#     `verdict: HELD one concept` with `shared_demand=1`. THE POSITIVE
#     DIRECTION: a site that refuses a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the line and the section must each carry
#     `verdict: HELD one concept` with the exact produced identity
#     `relations=2 shapes=0 applications=1 shared_demand=0`. THE THIRD
#     DIRECTION: a site that refuses a lawful single is convicted. Its
#     evidence differs from the cohort's, so the two HELD rows are
#     distinguished by their evidence, never merged.
# Fail-closed controls: an unreadable subject, an unparseable subject, or no
# subject refuses with a nonzero exit and never an index line (`index: `),
# a section (`## `), or a verdict (`verdict: `) line. A row whose measured
# answer differs from its demanded answer FAILS. Zero rows examined FAILS
# (GAP-201). A missing compiler refuses NOT MEASURED (exit 3) — a clean
# refusal the vacuity scaffold counts as noticing the missing subject,
# never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'site: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
site=$here/../tools/concept/site.sh
index=$here/../tools/concept/index.sh
page=$here/../tools/concept/page.sh

if [ ! -x "$IDOL" ]; then
    printf 'site: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$site" ]; then
    printf 'site: NOT MEASURED — %s is not executable (the batch site was required)\n' "$site" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'site: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.site.XXXXXX") || exit 3
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
# positive controls that every produced direction crossed the site boundary
# on BOTH faces at once.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# section_of <file> <site>: print the site's `## <file>` section (header
# through the line before the next section) on stdout.
section_of() {
    awk -v h="## $1" '$0==h{f=1; print; next} f && /^## /{exit} f{print}' "$2"
}

# demand_agree <label> <resp> <file>: the verdict the index block names for
# the file must be the verdict the section carries for it.
demand_agree() {
    label=$1
    resp=$2
    file=$3
    iv=$(awk -v p="index: $file " 'index($0,p)==1{v=substr($0,length(p)+1); sub(/ identity: .*$/, "", v); print v; exit}' "$resp") || iv=""
    sv=$(awk -v h="## $file" '$0==h{f=1; next} /^## /{f=0} f && /^verdict: /{print; exit}' "$resp") || sv=""
    { [ -n "$iv" ] && [ "$iv" = "$sv" ]; } || {
        printf 'site: FAIL — %s index and section disagree (index carries [%s], section carries [%s]); the faces agree or the site fails\n' "$label" "$iv" "$sv" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_site <label> <file> <needle> [...]: one subject in, exit 0,
# exactly one `index: ` line and one `## ` section naming the file, every
# needle in the site, and both faces agreeing on the verdict.
demand_site() {
    label=$1
    file=$2
    shift 2
    resp=$work/respSite.txt
    if ! sh "$site" "$file" >"$resp" 2>"$resp.diag"; then
        printf 'site: FAIL — %s refused where a site was demanded\n' "$label" >&2
        cat "$resp" >&2
        cat "$resp.diag" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    n=$(grep -c '^index: ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'site: FAIL — %s indexed %s time(s), not once; a subject is never lost or doubled\n' "$label" "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    n=$(grep -c '^## ' <"$resp") || n=0
    [ "$n" -eq 1 ] || {
        printf 'site: FAIL — %s sectioned %s time(s), not once; a subject is never lost or doubled\n' "$label" "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "index: $file " <"$resp" || {
        printf 'site: FAIL — %s index names nothing with %s\n' "$label" "$file" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "## $file" <"$resp" || {
        printf 'site: FAIL — %s section names nothing with %s\n' "$label" "$file" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    for needle in "$@"; do
        grep -Fq "$needle" <"$resp" || {
            printf 'site: FAIL — %s sited yet carried nothing with %s\n' "$label" "$needle" >&2
            cat "$resp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
    demand_agree "$label" "$resp" "$file"
}

# demand_closed <label> [--] [args ...]: the site must refuse with a
# nonzero exit and never an index line, a section, or a verdict line.
demand_closed() {
    label=$1
    shift
    resp=$work/respClosed.txt
    if sh "$site" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'site: FAIL — %s sited where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        examined=$((examined + 1))
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "index: " <"$resp" && {
        printf 'site: FAIL — %s refused yet carried an index line; a refusal is never site-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "## " <"$resp" && {
        printf 'site: FAIL — %s refused yet carried a section; a refusal is never site-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    grep -Fq "verdict: " <"$resp" && {
        printf 'site: FAIL — %s refused yet carried a verdict; a refusal is never site-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_site refused-bucket "$work/my bucket.id" "# Concept site — " "# Concept record — " "verdict: REFUSED no_shared_demand" "shared_demand=0"
demand_site held-cohort "$work/cohort.id" "# Concept site — " "# Concept record — " "verdict: HELD one concept" "shared_demand=1"
demand_site held-unwitnessed "$work/unwitnessed.id" "# Concept site — " "# Concept record — " "verdict: HELD one concept" "relations=2 shapes=0 applications=1 shared_demand=0"

# ── the batch: three subjects in, three index lines plus three sections in
# argv order, each file beside its own verdict on both faces — no lost
# subject, no invented row, no swapped verdict, no diverged face.
resp=$work/respBatch.txt
if ! sh "$site" "$work/my bucket.id" "$work/cohort.id" "$work/unwitnessed.id" >"$resp" 2>"$resp.diag"; then
    printf 'site: FAIL — batch refused where a site was demanded\n' >&2
    cat "$resp" >&2
    cat "$resp.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    n=$(grep -c '^index: ' <"$resp") || n=0
    [ "$n" -eq 3 ] || {
        printf 'site: FAIL — batch indexed %s time(s), not three\n' "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    n=$(grep -c '^## ' <"$resp") || n=0
    [ "$n" -eq 3 ] || {
        printf 'site: FAIL — batch sectioned %s time(s), not three\n' "$n" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    {
        printf 'index: %s verdict: REFUSED no_shared_demand\n' "$work/my bucket.id"
        printf 'index: %s verdict: HELD one concept\n' "$work/cohort.id"
        printf 'index: %s verdict: HELD one concept\n' "$work/unwitnessed.id"
    } >"$work/wantLines.txt"
    awk '/^index: /{v=$0; sub(/ split=[^ ]*/, "", v); sub(/ identity: .*$/, "", v); print v}' "$resp" >"$work/gotLines.txt" || : >"$work/gotLines.txt"
    cmp -s "$work/wantLines.txt" "$work/gotLines.txt" || {
        printf 'site: FAIL — batch index lines are not the subjects in argv order beside their own verdicts; the joining invents or reorders\n' >&2
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
        printf 'site: FAIL — batch sections are not the subjects in argv order; the joining invents or reorders\n' >&2
        cat "$resp" >&2
        failed=$((failed + 1))
    }
    demand_agree batch-bucket "$resp" "$work/my bucket.id"
    demand_agree batch-cohort "$resp" "$work/cohort.id"
    demand_agree batch-unwitnessed "$resp" "$work/unwitnessed.id"
fi

# ── faithfulness: the site's bucket line and bucket section carry exactly
# what the standalone renders produced — the joining invents nothing.
if ! sh "$index" "$work/my bucket.id" >"$work/idxBucket.txt" 2>"$work/idxBucket.diag"; then
    printf 'site: FAIL — standalone index refused the bucket; faithfulness unmeasurable\n' >&2
    cat "$work/idxBucket.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
elif ! sh "$page" "$work/my bucket.id" >"$work/pgBucket.txt" 2>"$work/pgBucket.diag"; then
    printf 'site: FAIL — standalone page refused the bucket; faithfulness unmeasurable\n' >&2
    cat "$work/pgBucket.diag" >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
elif ! sh "$site" "$work/my bucket.id" >"$work/stBucket.txt" 2>"$work/stBucket.diag"; then
    printf 'site: FAIL — site refused the bucket; faithfulness unmeasurable\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    examined=$((examined + 1))
    grep '^index: ' "$work/idxBucket.txt" >"$work/wantLine.txt" || : >"$work/wantLine.txt"
    grep '^index: ' "$work/stBucket.txt" >"$work/gotLine.txt" || : >"$work/gotLine.txt"
    cmp -s "$work/wantLine.txt" "$work/gotLine.txt" || {
        printf 'site: FAIL — site index line differs from the standalone index render; the joining invents\n' >&2
        cat "$work/stBucket.txt" >&2
        failed=$((failed + 1))
    }
    section_of "$work/my bucket.id" "$work/pgBucket.txt" >"$work/wantSection.txt"
    section_of "$work/my bucket.id" "$work/stBucket.txt" >"$work/gotSection.txt"
    cmp -s "$work/wantSection.txt" "$work/gotSection.txt" || {
        printf 'site: FAIL — site section differs from the standalone page section; the joining invents\n' >&2
        cat "$work/stBucket.txt" >&2
        failed=$((failed + 1))
    }
fi

# ── fail-closed ──────────────────────────────────────────────────────────
demand_closed unreadable-subject "$work/absent.id"
demand_closed unparseable-subject "$work/broken.id"
demand_closed no-subject

# ── not measured: a missing compiler refuses exit 3, never a site.
resp=$work/respUnmeasured.txt
if IDOL=/nonexistent sh "$site" "$work/cohort.id" >"$resp" 2>"$resp.diag"; then
    printf 'site: FAIL — missing compiler sited where NOT MEASURED was demanded\n' >&2
    examined=$((examined + 1))
    failed=$((failed + 1))
else
    rc=$?
    examined=$((examined + 1))
    [ "$rc" -eq 3 ] || {
        printf 'site: FAIL — missing compiler refused with %s, not NOT MEASURED (3)\n' "$rc" >&2
        failed=$((failed + 1))
    }
fi

[ "$examined" -gt 0 ] || {
    printf 'site: FAIL — 0 site examinations\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'site: FAIL — %s of %s examined site(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'site: PASS — %s examined site(s), 0 failed\n' "$examined"
exit 0
