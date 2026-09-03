#!/bin/sh
# gate/explain.sh — upstream agreement hold for the produced concept verdict (GAP-120).
#
# The produced concept finding leaves the compiler through two faces that each
# already has a downstream hold: the `idol explain` document's `.concept`
# object (read by `tools/concept/doc.sh`) and the `idol graph` export's
# `concepts[]`/`refusals[]` (held by `gate/concept.sh`). `doc.sh` checks their
# agreement internally before rendering — but no gate holds the agreement
# itself. A `doc.sh` that skipped its check still passes `gate/docs.sh` while
# the faces diverge, and `gate/converge.sh` holds the three downstream renders
# against each other without ever touching either upstream face. This gate
# closes that hole: for one subject it renders both upstream faces and demands
# they answer the same produced finding.
#
# It owns no derivation: verdict-correctness (REFUSED exactly when the export
# carries the refusal, HELD otherwise) is owned by `gate/concept.sh` over the
# export; the record shape is owned by `gate/docs.sh`; the downstream
# agreement is owned by `gate/converge.sh`. What is measured HERE, and nowhere
# else, is the upstream agreement — one produced verdict reaching two compiler
# faces as one finding.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided agreement cannot
# call itself an enforcement:
#   bucket refused: the no-shared-demand cohort must reach both faces with
#     one `no_shared_demand` refusal and `shared_demand=0`. The subject file
#     carries a SPACE in its name: a face that interpolates the path through
#     a host shell splits it and breaks the agreement — so the spaced path is
#     the positive control for argv passing on both faces at once.
#   cohort held: one subject drives both relations, so both faces must read
#     empty refusals with `shared_demand=1`.
#   unwitnessed held: nothing applies the module's one relation, so both faces
#     must read empty refusals over the exact identity
#     `relations=2 shapes=0 applications=1 shared_demand=0` — different
#     produced evidence from the cohort's, so the two HELD agreements are
#     never merged.
# Identities compare whole (the explain face additionally names the home, and
# the home must match too); refusals compare the produced triple
# (module, reason, split). A row whose faces disagree FAILS. Fail-closed rows:
# an unparseable subject, an absent subject, and no subject must each refuse
# with a nonzero exit and never a verdict-shaped document. Zero rows examined
# FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'explain: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}

if [ ! -x "$IDOL" ]; then
    printf 'explain: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'explain: NOT MEASURED — jq is required to read the produced verdict\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.explain.XXXXXX") || exit 3
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
# positive controls that one produced verdict reaches two compiler faces as
# one finding.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

examined=0
failed=0

# agree <label> <file> <demand> [<demand> ...]: both faces answer one finding.
# Each demand is a jq filter run against the explain document; it sees the
# explain face as `.exp` and the graph face as `.got`.
agree() {
    label=$1
    file=$2
    shift 2
    "$IDOL" explain "$file" >"$work/face.exp.json" 2>"$work/face.exp.diag" || {
        printf 'explain: FAIL — %s explain face refused a subject that demands a document\n' "$label" >&2
        cat "$work/face.exp.diag" >&2
        failed=$((failed + 1))
        return 1
    }
    "$IDOL" graph "$file" >"$work/face.got.json" 2>"$work/face.got.diag" || {
        printf 'explain: FAIL — %s graph face refused a subject that demands a document\n' "$label" >&2
        cat "$work/face.got.diag" >&2
        failed=$((failed + 1))
        return 1
    }
    # Both faces answered, so the agreement is examined even when a demand
    # below fails — the same examined semantics the sibling gates hold.
    examined=$((examined + 1))
    jq -e '.concept | type == "object"' <"$work/face.exp.json" >/dev/null 2>&1 || {
        printf 'explain: FAIL — %s explain face carries no produced concept verdict\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    # The upstream agreement itself: identities whole, refusals on the
    # produced triple. A face carrying the verdict plus one invented row
    # fails here.
    exp_concepts=$(jq -c '.concept.concepts' <"$work/face.exp.json" 2>/dev/null) || exp_concepts=""
    got_concepts=$(jq -c '.concepts' <"$work/face.got.json" 2>/dev/null) || got_concepts=""
    [ -n "$exp_concepts" ] && [ "$exp_concepts" = "$got_concepts" ] || {
        printf 'explain: FAIL — %s explain identity disagrees with the graph export\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    exp_ref=$(jq -c '[.concept.refusals[] | {module, reason, split}]' <"$work/face.exp.json" 2>/dev/null) || exp_ref=""
    got_ref=$(jq -c '[.refusals[] | {module, reason, split}]' <"$work/face.got.json" 2>/dev/null) || got_ref=""
    [ -n "$exp_ref" ] && [ "$exp_ref" = "$got_ref" ] || {
        printf 'explain: FAIL — %s explain refusal disagrees with the graph export\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    joined=$(jq -n --slurpfile exp "$work/face.exp.json" --slurpfile got "$work/face.got.json" \
        '{exp: $exp[0], got: $got[0]}') || exit 3
    for demand in "$@"; do
        printf '%s\n' "$joined" | jq -e "$demand" >/dev/null 2>&1 || {
            printf 'explain: FAIL — %s agreement misses %s\n' "$label" "$demand" >&2
            failed=$((failed + 1))
            return 1
        }
    done
}

# refuse <label> <args...>: a subject that cannot be explained must never
# yield a verdict-shaped document from either face.
refuse() {
    label=$1
    shift
    if "$IDOL" explain "$@" >"$work/face.ref.exp.json" 2>"$work/face.ref.exp.diag"; then
        printf 'explain: FAIL — %s explain face rendered where a refusal was demanded\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    jq -e '.concept | type == "object"' <"$work/face.ref.exp.json" >/dev/null 2>&1 && {
        printf 'explain: FAIL — %s explain refusal still carries a verdict-shaped document\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    if "$IDOL" graph "$@" >"$work/face.ref.got.json" 2>"$work/face.ref.got.diag"; then
        printf 'explain: FAIL — %s graph face rendered where a refusal was demanded\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
}

# ── every produced direction ─────────────────────────────────────────────
agree refused-bucket "$work/my bucket.id" \
    '.exp.concept.refusals | length == 1' \
    '.exp.concept.refusals[0].reason == "no_shared_demand"' \
    '.exp.concept.concepts[0].shared_demand == 0' \
    '.got.refusals | length == 1'
agree held-cohort "$work/cohort.id" \
    '.exp.concept.refusals == []' \
    '.exp.concept.concepts[0].shared_demand == 1' \
    '.got.refusals == []'
agree held-unwitnessed "$work/unwitnessed.id" \
    '.exp.concept.refusals == []' \
    '.exp.concept.concepts[0].relations == 2 and .exp.concept.concepts[0].shapes == 0 and .exp.concept.concepts[0].applications == 1 and .exp.concept.concepts[0].shared_demand == 0' \
    '.got.refusals == []'

# ── fail-closed ──────────────────────────────────────────────────────────
printf 'plus(: i64): i64\n  a + \n' >"$work/broken.id" || exit 3
refuse unparseable "$work/broken.id"
refuse absent "$work/absent.id"
refuse no-subject

[ "$examined" -gt 0 ] || {
    printf 'explain: FAIL — 0 upstream agreements examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'explain: FAIL — %s of %s examined agreement(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'explain: PASS — %s examined agreement(s), 0 failed\n' "$examined"
exit 0
