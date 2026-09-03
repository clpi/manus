#!/bin/sh
# gate/concept.sh — CONSUMER ENFORCEMENT over `refusals[]` (GAP-120).
#
# A module whose relations are applied from elsewhere but whose callers
# share no demand is a utility bucket. The graph PRODUCED that finding
# (`publishConceptRefusals`, schema 17) and `writeJson` exported it as
# `refusals[]`; this gate is the consumer: it compiles each subject and
# compares the verdict the produced export carries against the verdict the
# roster demands. It owns no derivation: every refusal it reads was produced
# on the graph and re-verified on export before this file saw it; the gate
# never re-decides, it reads what was produced.
#
# WHY THE CENSUS IS READ ALONGSIDE THE ROW: the export publishes the refusal
# and the join evidence beside it, and a producer that contradicts its own
# evidence — a produced refusal where the join says demand exists — is
# damage this gate reports rather than a verdict it trusts. Judging BOTH
# against the SAME export keeps the verdict on one producer: the produced
# export, never a second derivation.
#
# WHAT IS MEASURED, AND WHY IT IS EXECUTION. Every subject is COMPILED
# through `idol graph` — the checked lift produces the identity, the demand
# join, and the refusal from RESOLVED on-graph applications, so a source grep
# over the same files answers a question the producer never asked. The gate
# reads the produced export or it reads nothing.
#
# THE ROSTER CARRIES BOTH DIRECTIONS, so a one-sided gate cannot call itself
# an enforcement:
#   `bucket  bucket  refused`  demands the produced row for the bucket
#     shape whose composition shares no demand. THE NEGATIVE DIRECTION: a
#     producer that stops refusing is convicted.
#   `unwitnessed  unwitnessed  pass`  demands no row for a module whose one
#     relation is applied by nothing else. THE THIRD DIRECTION: the
#     adjudicator refuses a cohort sharing no demand, and one applied
#     relation is not a cohort. This stops the gate reading every
#     non-bucket as a bucket.
#   `cohort  cohort  pass`     demands no row for the shape whose caller
#     drives both relations. THE POSITIVE DIRECTION: a join that
#     over-refuses is convicted.
# A row whose measured verdict differs from its demanded verdict FAILS.
# Zero rows examined FAILS (GAP-201). A row naming a shape this file cannot
# materialize, or a shape arm no row names, FAILS — `materialize`'s arms ARE
# the enumeration.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
# gate-role: gate
cd "$root" || { printf 'concept: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
roster=$here/concept.subjects
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'concept: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi

if [ ! -r "$roster" ]; then
    printf 'concept: FAIL — subject roster is unreadable: %s (0 subjects examined)\n' "$roster" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || {
    printf 'concept: NOT MEASURED — jq is required to read the produced graph JSON\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.concept.XXXXXX") || exit 3
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the shapes ─────────────────────────────────────────────────────────────
# Each arm is TWO SOURCE FILES: $name.id, the module the graph JSON judges,
# and part.id, the partition it reaches. The arms ARE the enumeration of
# which shapes exist and which of them are subjects; there is no list beside
# them to drift.
materialize() {
    shape=$1
    dir=$2
    name=$3
    mkdir -p "$dir" || return 1
    case $shape in
        bucket) #shape:subject
            # THE UTILITY BUCKET: two relations in ONE FILE, each applied by
            # its own subject in that same file — plus by `main`, minus by
            # `entry`, and NO subject drives both. The graph refuses.
            printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$dir/$name.id" || return 1
            ;;
        cohort) #shape:subject
            # THE PASSING COHORT: one subject drives both relations — the
            # shared demand the bucket lacks. No refusal is produced.
            printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$dir/$name.id" || return 1
            ;;
        unwitnessed) #shape:subject
            # AN UNWITNESSED MODULE: nothing applies its one relation. One
            # applied relation is not a cohort; no refusal is produced.
            printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$dir/$name.id" || return 1
            ;;
        *)
            return 2
            ;;
    esac
    return 0
}

shape_roll() {
    awk -v want="$1" '
        /^materialize\(\) \{$/  { inside = 1; next }
        inside && /^\}$/        { inside = 0 }
        inside && $0 ~ ("^ *[a-z][a-z]*\\) *#shape:" want "$") { sub(/\).*/, ""); sub(/^ */, ""); print }
    ' "$self"
}

# ── one subject, judged on the produced export ─────────────────────────────
# Prints the measured verdict word on stdout: `refused`, `pass`, `damaged`.
# DAMAGED means the export never existed (the graph command failed), or its
# shape the verdict reads (`refusals` length, `shared_demand`) is unreadable.
judge() {
    name=$1
    src=$2
    json=$work/$name.json
    if ! "$IDOL" graph "$src" >"$json" 2>"$work/$name.log"; then
        printf 'damaged'
        tail -3 "$work/$name.log" | sed 's/^/concept:   /' >&2
        return
    fi
    # The produced export carries the refusal and the demand face of the same
    # finding. Reading both from one export keeps the verdict on the produced
    # fact rather than a grep over the source that produced it.
    refused_rows=$(jq -r '.refusals | length' <"$json" 2>/dev/null)
    shared=$(jq -r '.concepts[0].shared_demand' <"$json" 2>/dev/null)
    case $refused_rows in
        ''|*[!0-9]*)
            printf 'damaged'
            printf 'concept:   %s: refusals length unreadable\n' "$name" >&2
            return
            ;;
    esac
    case $shared in
        ''|*[!0-9]*)
            printf 'damaged'
            printf 'concept:   %s: shared_demand unreadable\n' "$name" >&2
            return
            ;;
    esac
    if [ "$shared" -gt 0 ] && [ "$refused_rows" -gt 0 ]; then
        printf 'damaged'
        printf 'concept:   %s: shared_demand %s and refusals[%s] — the export contradicts the evidence of demand\n' "$name" "$shared" "$refused_rows" >&2
        return
    fi
    if [ "$refused_rows" -gt 0 ]; then
        reason=$(jq -r '.refusals[0].reason' <"$json" 2>/dev/null || printf 'unknown')
        printf 'refused'
        printf 'concept:   %s: refusals[%s] reason %s shared_demand %s\n' "$name" "$refused_rows" "$reason" "$shared" >&2
    else
        printf 'pass'
        printf 'concept:   %s: no refusals; shared_demand %s\n' "$name" "$shared" >&2
    fi
}

# ── roster ratchet: the roll read from this file IS the roster ────────────
roll=$(shape_roll subject)
for shape in $roll; do
    if ! awk -v want="$shape" '$2 == want { found=1 } END { exit !found }' "$roster"; then
        printf 'concept: FAIL — subject arm %s has no roster row (the roll is the roster)\n' "$shape" >&2
        exit 1
    fi
done

rows_examined=0
failed=0
while read -r name shape want extra; do
    [ -n "$name" ] || continue
    case $name in \#*) continue ;; esac
    rows_examined=$((rows_examined + 1))
    if [ -z "$want" ] || [ -n "$extra" ]; then
        printf 'concept: FAIL — roster row %s must carry exactly name, shape, verdict\n' "$name" >&2
        failed=$((failed + 1))
        continue
    fi
    if ! materialize "$shape" "$work/$name" "$name" 2>/dev/null; then
        printf 'concept: FAIL — roster row %s names shape %s, which this gate cannot materialize\n' "$name" "$shape" >&2
        exit 1
    fi
    got=$(judge "$name" "$work/$name/$name.id")
    if [ "$got" != "$want" ]; then
        printf 'concept: FAIL — %s: demanded %s, measured %s\n' "$name" "$want" "$got" >&2
        failed=$((failed + 1))
    fi
done < "$roster"

[ "$rows_examined" -gt 0 ] || {
    printf 'concept: FAIL — zero roster rows examined (GAP-201)\n' >&2
    exit 1
}

printf 'concept: %s subject(s) examined, %s failed\n' "$rows_examined" "$failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
