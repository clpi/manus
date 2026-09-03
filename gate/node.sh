#!/bin/sh
# gate/node.sh — file-boundary face agreement hold for the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (`publishConceptIdentities`, schema 16) and `writeJson` exports it
# twice: once as the `concepts[]` row the sibling gates hold, and once as a
# `concept` face on the file's own module node, so compiler, MCP and tooling
# readers answer the same fact without parsing the row table. No sibling
# gate reads the node face — a damaged, missing, or duplicated node face
# passes every one of them while the two compiler faces disagree. This gate
# holds the agreement no sibling gate holds: the module-node `concept` face
# must name exactly the home the `concepts[]` row produces for the same
# subject. It owns the agreement ONLY and no derivation, no identity, and
# no refusal: verdict-correctness (REFUSED exactly when the export carries
# the refusal, HELD otherwise) is owned by `gate/concept.sh` over the
# export; the single-record shape is owned by `gate/docs.sh`; the upstream
# explain/graph agreement is owned by `gate/explain.sh`.
#
# THE THREE SHAPES ARE THE ROSTER, so a one-sided gate cannot call itself
# an agreement (verdict-correctness of those shapes stays owned by
# `gate/concept.sh`; here they are the positive controls that one produced
# home reaches both export faces as one finding):
#   bucket refused: the export must carry one `concepts[]` row with
#     `shared_demand=0` beside its `no_shared_demand` refusal AND exactly
#     one module node faced with that same home. THE NEGATIVE DIRECTION:
#     a node face missing, duplicated, moved off the module node, or
#     naming another home is convicted. The subject file carries a SPACE
#     in its name: a face that interpolates the path through a host shell
#     splits it and fails, so the spaced path is the positive control for
#     argv passing (host-transport norm).
#   cohort held: one `concepts[]` row with `shared_demand=1`, empty
#     refusals, AND the same single module-node face agreement. THE
#     POSITIVE DIRECTION: a face that disagrees on a lawful cohort is
#     convicted.
#   unwitnessed held: one `concepts[]` row with the exact produced
#     identity `relations=2 shapes=0 applications=1 shared_demand=0`,
#     empty refusals, AND the same single module-node face agreement.
#     THE THIRD DIRECTION: a face that disagrees on a lawful single is
#     convicted. Its evidence differs from the cohort's, so the two HELD
#     rows are distinguished by their evidence, never merged.
# Fail-closed controls: an unparseable subject, an absent subject, or no
# subject refuses with a nonzero exit and never a verdict-shaped export. A
# row whose measured answer differs from its demanded answer FAILS. Zero
# rows examined FAILS (GAP-201). A missing compiler or jq refuses NOT
# MEASURED (exit 3) — a clean refusal the vacuity scaffold counts as
# noticing the missing subject, never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
# gate-role: gate
cd "$root" || { printf 'node: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}

if [ ! -x "$IDOL" ]; then
    printf 'node: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'node: NOT MEASURED — jq is required to read the produced graph JSON\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.node.XXXXXX") || exit 3
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the subjects ─────────────────────────────────────────────────────────
# Same three shapes `gate/concept.sh` materializes. Verdict-correctness
# stays owned there; here they are the positive controls that one produced
# home reaches both export faces as one finding.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

examined=0
failed=0

# agree <label> <file> <demand> [<demand> ...]: the node face answers the
# row's home. Each demand is a jq filter run against the graph export.
agree() {
    label=$1
    file=$2
    shift 2
    "$IDOL" graph "$file" >"$work/face.got.json" 2>"$work/face.got.diag" || {
        printf 'node: FAIL — %s graph face refused a subject that demands an export\n' "$label" >&2
        cat "$work/face.got.diag" >&2
        failed=$((failed + 1))
        return 1
    }
    # The export answered, so the agreement is examined even when a demand
    # below fails — the same examined semantics the sibling gates hold.
    examined=$((examined + 1))
    for demand in "$@"; do
        jq -e "$demand" <"$work/face.got.json" >/dev/null 2>&1 || {
            printf 'node: FAIL — %s agreement misses %s\n' "$label" "$demand" >&2
            failed=$((failed + 1))
            return 1
        }
    done
}

# face_demands: the agreement itself, owned here and nowhere else. Exactly
# one node carries the file-boundary face, it sits on the module node, and
# it names the home the concepts[] row produces — never a second face,
# never a face on another node, never another home. Filters carry no
# spaces, so the call-site command substitution never splits one demand
# into two words.
face_demands() {
    printf '%s\n' '.concepts|length==1'
    printf '%s\n' '[.nodes[]|select(has("concept"))]|length==1'
    printf '%s\n' '[.nodes[]|select(has("concept"))][0].kind=="module"'
    printf '%s\n' '(.concepts[0].home)as$h|[.nodes[]|select(has("concept"))][0].concept==$h'
}

# refuse <label> <args...>: a subject that cannot be graphed must never
# yield a verdict-shaped export.
refuse() {
    label=$1
    shift
    if "$IDOL" graph "$@" >"$work/face.ref.got.json" 2>"$work/face.ref.got.diag"; then
        printf 'node: FAIL — %s graph face rendered where a refusal was demanded\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    fi
    examined=$((examined + 1))
    jq -e '.concepts | type == "array"' <"$work/face.ref.got.json" >/dev/null 2>&1 && {
        printf 'node: FAIL — %s graph refusal still carries a verdict-shaped export\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
# shellcheck disable=SC2046
agree refused-bucket "$work/my bucket.id" \
    $(face_demands) \
    '.concepts[0].shared_demand == 0' \
    '.refusals | length == 1'
# shellcheck disable=SC2046
agree held-cohort "$work/cohort.id" \
    $(face_demands) \
    '.concepts[0].shared_demand == 1' \
    '.refusals == []'
# shellcheck disable=SC2046
agree held-unwitnessed "$work/unwitnessed.id" \
    $(face_demands) \
    '.concepts[0].relations == 2 and .concepts[0].shapes == 0 and .concepts[0].applications == 1 and .concepts[0].shared_demand == 0' \
    '.refusals == []'

# ── fail-closed ──────────────────────────────────────────────────────────
printf 'plus(: i64): i64\n  a + \n' >"$work/broken.id" || exit 3
refuse unparseable "$work/broken.id"
refuse absent "$work/absent.id"
refuse no-subject

[ "$examined" -gt 0 ] || {
    printf 'node: FAIL — 0 file-boundary agreements examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'node: FAIL — %s of %s examined agreement(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'node: %s examined agreement(s), 0 failed\n' "$examined"
