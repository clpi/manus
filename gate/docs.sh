#!/bin/sh
# gate/docs.sh — generated-docs hold for the produced concept verdict (GAP-120).
#
# `tools/concept/doc.sh` is the generated-docs face of the produced concept
# finding: one subject `.id` file as a single argv element, one markdown
# concept record on stdout, rendered from the produced graph through `idol
# explain` and held against the graph export's own `concepts[]`/`refusals[]`
# before a line is printed. This gate holds that face. It owns no
# derivation: verdict-correctness (REFUSED exactly when the export carries
# the refusal, HELD otherwise) is owned by `gate/concept.sh` over the export;
# what is measured HERE, and nowhere else, is the docs boundary — the record
# shape, the evidence the render carries, argv file passing, and fail-closed
# refusals.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the reader as `verdict: REFUSED no_shared_demand` with the
#     produced demand evidence `shared_demand=0`. THE NEGATIVE DIRECTION: a
#     projection that stops refusing is convicted. The subject file carries
#     a SPACE in its name: a projection that interpolates the path through
#     a host shell splits it and fails, so the spaced path is the positive
#     control for argv passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the record must read `verdict: HELD one concept` with
#     `shared_demand=1`. THE POSITIVE DIRECTION: a projection that refuses
#     a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the record must read
#     `verdict: HELD one concept` with `shared_demand=0` over two
#     relations. THE THIRD DIRECTION: a projection that refuses a lawful
#     single is convicted. Its produced evidence differs from the cohort's
#     (shared_demand 0, zero refusals, one applied relation), so this row
#     holds the HELD render across the boundary from different facts — the
#     two HELD rows are distinguished by their evidence, never merged.
# Fail-closed controls: an unreadable subject, an unparseable subject, no
# subject, or two subjects refuse with a nonzero exit and never a
# verdict-shaped record. A row whose measured answer differs from its
# demanded answer FAILS. Zero rows examined FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'docs: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
doc=$here/../tools/concept/doc.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'docs: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$doc" ]; then
    printf 'docs: NOT MEASURED — %s is not executable (the docs projection was required)\n' "$doc" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'docs: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.docs.XXXXXX") || exit 3
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
# positive controls that the verdict crossed the docs boundary intact.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3
printf 'this is not idol @@\n' >"$work/broken.id" || exit 3

examined=0
failed=0

# render <label> <file> <response-file>: one subject in, one record out.
render() {
    sh "$doc" "$2" >"$3" 2>"$3.diag" || {
        printf 'docs: FAIL — %s refused a subject that demands a record\n' "$1" >&2
        cat "$3.diag" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
}

# demand_render <label> <file> <needle> [<needle> ...]: the record must carry
# every needle. Needles name the verdict plus the produced evidence that
# distinguishes the three directions; the shape needles hold the record face.
demand_render() {
    label=$1
    file=$2
    shift 2
    resp=$work/respRender.txt
    render "$label" "$file" "$resp" || return 1
    for needle in "$@"; do
        grep -Fq "$needle" <"$resp" || {
            printf 'docs: FAIL — %s record misses %s\n' "$label" "$needle" >&2
            cat "$resp" >&2
            failed=$((failed + 1))
            return 1
        }
    done
}

# demand_absent <label> <file> <needle>: the record must never carry the
# opposite verdict — a render that both refuses and holds is damage.
demand_absent() {
    resp=$work/respAbsent.txt
    render "$1" "$2" "$resp" || return 1
    grep -Fq "$3" <"$resp" && {
        printf 'docs: FAIL — %s record carries the forbidden %s\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_refuse <label> [--] [args ...]: the render must refuse with a
# nonzero exit and never a verdict-shaped record.
demand_refuse() {
    label=$1
    shift
    resp=$work/respRefuse.txt
    if sh "$doc" "$@" >"$resp" 2>"$resp.diag"; then
        printf 'docs: FAIL — %s rendered where a refusal was demanded\n' "$label" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    grep -Fq "verdict: " <"$resp" && {
        printf 'docs: FAIL — %s refused yet carried a verdict line; a refusal is never verdict-shaped\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_render refused-bucket "$work/my bucket.id" \
    "# Concept record — " \
    "source: $work/my bucket.id" \
    "identity: relations=" \
    "shared_demand=0" \
    "verdict: REFUSED no_shared_demand split="
demand_render held-cohort "$work/cohort.id" \
    "# Concept record — " \
    "source: $work/cohort.id" \
    "identity: relations=" \
    "shared_demand=1" \
    "verdict: HELD one concept"
demand_render held-unwitnessed "$work/unwitnessed.id" \
    "# Concept record — " \
    "source: $work/unwitnessed.id" \
    "identity: relations=2 shapes=0 applications=1 shared_demand=0" \
    "verdict: HELD one concept"

# The two HELD renders share a branch but not their evidence: the cohort
# holds over shared demand, the unwitnessed over a lone applied relation.
demand_absent refused-bucket "$work/my bucket.id" "verdict: HELD"
demand_absent held-cohort "$work/cohort.id" "verdict: REFUSED"
demand_absent held-unwitnessed "$work/unwitnessed.id" "verdict: REFUSED"

# ── fail-closed ──────────────────────────────────────────────────────────
demand_refuse unreadable-subject "$work/absent.id"
demand_refuse unparseable-subject "$work/broken.id"
demand_refuse no-subject
demand_refuse two-subjects "$work/cohort.id" "$work/unwitnessed.id"

[ "$examined" -gt 0 ] || {
    printf 'docs: FAIL — 0 concept records examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'docs: FAIL — %s of %s examined record(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'docs: PASS — %s examined record(s), 0 failed\n' "$examined"
exit 0
