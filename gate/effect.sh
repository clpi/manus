#!/bin/sh
# gate/effect.sh — the CENSUS and the COUNTERFACTUAL for
# `ApplicationFact.effect`.
#
# WHY THIS EXISTS. The effect fact shipped with exactly one published value.
# Measured at debad1df over `examples`: 1331 applications, 1043 `none`, 288
# `unknown`, and `one` ZERO. A fact whose positive case is unreachable is not
# an effect fact — it can prove innocence and it can shrug, and it can never
# say WHICH observation stands in the way of a transformation. Two numbers
# have to hold for that not to come back, and they are opposite in direction:
#
#   `one` MUST NOT COLLAPSE TO ZERO. That is the defect this gate was written
#   against, and it is the state the tree was in.
#
#   `none` MUST NOT MOVE. Publishing more `one` by publishing less `none`
#   would be a census that improved by getting worse. `none` is the card every
#   consumer in the tree actually reads, and the positive work must be paid
#   for out of `unknown`.
#
# AND THE CENSUS IS NOT ENOUGH. A card can be published, counted, projected to
# JSON and read by nobody. The COUNTERFACTUAL removes the fact and NOTHING
# else — `IDOL_EFFECT_SEVER=1` severs `publishApplicationEffects` at the
# producer — and requires the artifact to change. If the two arms are byte
# identical the fact is decoration, whatever the census says.
#
# THE SUBJECT IS CORPUS CODE, NOT A FIXTURE WRITTEN FOR THE GATE.
# `examples/demand/tail.id` was already in the tree and already checks every
# one of its answers by value. A fixture authored here would also have had to
# declare module-scope vocabulary the declaration freeze refuses, and would
# have measured a program that exists to be measured.
#
# ITS SCOPE IS ONE MODULE AND THE POPULATION IS MEASURED. Over `examples lib`,
# 244 modules reach the direct backend and severing the effect fact changes
# the emitted assembly of 54 of them; 190 are unchanged. Reproduce with:
#
#   for f in $(find examples lib -name '*.id'); do
#     idol compile "$f" --emit asm -o a.s
#     IDOL_EFFECT_SEVER=1 idol compile "$f" --emit asm -o b.s
#     cmp -s a.s b.s || echo "$f"
#   done
#
# The gate checks one of the 54 rather than all of them because two compiles
# of the whole corpus is a two-minute gate, and the floor below fails just as
# loudly when the last consumer is deleted.
#
# IT COUNTS RATHER THAN ASSERTS wherever it can, like `gate/coverage.sh`: the
# floors below are floors, not equalities, so ordinary corpus growth does not
# rot them.
#
# USAGE:
#   gate/effect.sh                 census over $EFFECT_CORPUS + counterfactual
#   gate/effect.sh --census-only   census only (stated, not silent)
#   EFFECT_CORPUS="examples lib"   default is `examples`
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64

idol=${IDOL:-$repo/zig-out/bin/idol}
corpus=${EFFECT_CORPUS:-examples}
subject=examples/demand/tail.id

# THE FLOORS, measured on this tree and stated as inequalities.
#   `examples`:      1331 applications, none 1043, one 123, unknown 165
#   `examples lib`:  5071 applications, none 3707, one 166, unknown 1198
# The base debad1df measures the same corpus at 1331 / 1043 / ZERO / 288 —
# same applications, same `none`, and every positive card paid for out of
# `unknown`.
# `MIN_NONE` is the reversal control for moving `publishApplicationEffects`
# after `publishApplicationWorlds`: that reordering must not have taken a
# single proof of unobservability away.
MIN_APPS=${EFFECT_MIN_APPS:-1200}
MIN_NONE=${EFFECT_MIN_NONE:-1043}
MIN_ONE=${EFFECT_MIN_ONE:-100}

command -v jq >/dev/null 2>&1 || { echo "effect: jq not on PATH" >&2; exit 64; }
[ -x "$idol" ] || { echo "effect: no compiler at $idol (set IDOL=)" >&2; exit 64; }

work=$(mktemp -d -t idoleffect) || exit 64
trap 'rm -rf "$work"' EXIT INT TERM

die() { printf 'EFFECT BLOCKED -- %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

mode=full
while [ $# -gt 0 ]; do
    case "$1" in
        --census-only) mode=census ;;
        -h|--help) sed -n '1,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

# ======================================================================= CENSUS
: >"$work/rows"
files=0; lifted=0
for dir in $corpus; do
    find "$dir" -name '*.id' -type f 2>/dev/null
done | LC_ALL=C sort >"$work/files"
while IFS= read -r src; do
    [ -n "$src" ] || continue
    files=$((files + 1))
    "$idol" graph "$src" >"$work/g.json" 2>/dev/null || continue
    jq -r '[ (.applications|length)
           , ([.applications[]|select((.effect.card? // "absent") == "none")]|length)
           , ([.applications[]|select((.effect.card? // "absent") == "one")]|length)
           , ([.applications[]|select((.effect.card? // "absent") == "unknown")]|length)
           , ([.applications[]|select(has("effect")|not)]|length)
           ] | @tsv' "$work/g.json" >>"$work/rows" 2>/dev/null || continue
    lifted=$((lifted + 1))
done <"$work/files"

[ "$lifted" -gt 0 ] || die "ZERO modules lifted from [$corpus]. Examining nothing is not a pass."

set -- $(LC_ALL=C awk -F'\t' '{ a+=$1; n+=$2; o+=$3; u+=$4; b+=$5 }
    END { print a+0, n+0, o+0, u+0, b+0 }' "$work/rows")
apps=$1; none=$2; one=$3; unknown=$4; absent=$5

note "effect census over [$corpus] -- $files file(s), $lifted lifted"
printf '%-18s %8s\n' "applications" "$apps"
printf '%-18s %8s\n' "effect none" "$none"
printf '%-18s %8s\n' "effect one" "$one"
printf '%-18s %8s\n' "effect unknown" "$unknown"
printf '%-18s %8s\n' "effect absent" "$absent"

[ "$absent" -eq 0 ] || die "$absent application(s) carry NO effect key. A missing key is not a card, and a reader that treats it as one reports coverage it does not have."
[ "$apps" -ge "$MIN_APPS" ] || die "only $apps published application(s), floor $MIN_APPS. The corpus stopped lifting; a census over nothing says nothing."
[ "$none" -ge "$MIN_NONE" ] || die "effect none fell to $none, floor $MIN_NONE. Proofs of unobservability were LOST. Publishing more 'one' by publishing less 'none' is a census that improved by getting worse."
[ "$one" -ge "$MIN_ONE" ] || die "effect one is $one, floor $MIN_ONE. This is the original defect: the card can refuse and it can license, and it can never name the observation. Positive evidence is the draw rows and the capture edges; see publishApplicationEffects."

if [ "$mode" = census ]; then
    note "effect: --census-only -- the counterfactual was SKIPPED, not passed."
    exit 0
fi

# =============================================================== COUNTERFACTUAL
[ -f "$subject" ] || die "the counterfactual subject $subject is missing. Without it the census stands alone, and a census cannot tell a published fact from a consumed one."

"$idol" compile "$subject" --emit asm -o "$work/with.s" >/dev/null 2>&1 ||
    die "the subject did not compile with the effect fact published."
IDOL_EFFECT_SEVER=1 "$idol" compile "$subject" --emit asm -o "$work/severed.s" >/dev/null 2>&1 ||
    die "the subject did not compile with the effect fact severed. The sever must remove a FACT, not break the compiler."

# `throughbinding` is `p = 5 · square(p)`: it applies a relation, so the
# whole-relation fold in `comptime.foldRelationBody` is admitted only when the
# graph can prove `square` observes nothing — it asks through
# `graph_query.effectFreeCalleeClosure`, which reads `effect == .none`. With
# the fact the body is two instructions; without it, a frame and a `bl`.
symbol=_idol_examples_demand_tail__throughbinding
body() { LC_ALL=C awk -v s="$symbol:" '$0 == s { f = 1; next } f && /^$/ { exit } f' "$1" | grep -c .; }
with=$(body "$work/with.s")
severed=$(body "$work/severed.s")

printf '%-18s %8s\n' "folded (fact)" "$with"
printf '%-18s %8s\n' "folded (severed)" "$severed"

[ "$with" -gt 0 ] || die "found no body for $symbol in the published arm; the extractor is looking at the wrong symbol and would report agreement between two empty strings."
[ "$severed" -gt "$with" ] ||
    die "severing the effect fact changed nothing ($with vs $severed instructions). The fact is DECORATIVE: it is published, projected and read by no decision. Either a consumer was deleted or the sever no longer reaches the producer."

# AND THE MEANING MUST NOT MOVE. A fact selects a realization; if the two arms
# disagree about the ANSWER then the fold is a miscompile and the instruction
# count was the least interesting thing about it. The subject checks every one
# of its values by value and prints its own OK line only when they all hold.
"$idol" run "$subject" >"$work/with.out" 2>&1 ||
    die "the subject failed at runtime with the effect fact published."
IDOL_EFFECT_SEVER=1 "$idol" run "$subject" >"$work/severed.out" 2>&1 ||
    die "the subject failed at runtime with the effect fact severed."
grep -q 'tail demand: OK' "$work/with.out" ||
    die "the published arm did not reach its own OK line."
grep -q 'tail demand: OK' "$work/severed.out" ||
    die "the severed arm did not reach its own OK line."

note "effect: counterfactual OK -- $symbol is $with instruction(s) with the fact and $severed without, and both arms answer 25/16/42."
note "effect: EFFECT OK."
exit 0
