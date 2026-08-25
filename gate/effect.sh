#!/bin/sh
# gate/effect.sh — the CENSUS and the COUNTERFACTUAL for
# `ApplicationFact.effect`.
#
# WHY THIS EXISTS. The effect fact shipped with exactly one published value:
# `one` was UNREACHABLE, and `--census-only` on the commit before this gate
# prints the zero. A fact whose positive case cannot occur is not an effect
# fact — it can prove innocence and it can shrug, and it can never say WHICH
# observation stands in the way of a transformation. Two numbers have to hold
# for that not to come back, and they are opposite in direction:
#
#   `one` MUST NOT COLLAPSE TO ZERO. That is the defect this gate was written
#   against, and it is the state the tree was in.
#
#   `none` MUST NOT MOVE. Publishing more `one` by publishing less `none`
#   would be a census that improved by getting worse. `none` is the card every
#   consumer in the tree actually reads, and the positive work must be paid
#   for out of `unknown`.
#
# THAT SECOND RULE WAS CORRECTED ONCE, ON PURPOSE, AND THE CORRECTION IS THE
# WHOLE OF gaps/GAP-225.md. It is right about a REORDERING — moving the effect
# pass after the worlds pass must not cost a proof — and wrong as a general
# law, because it assumes every `none` in the census was a proof. Some were
# not. `publishApplicationEffects` blocked on a C linkage, a `.capture`, a
# static `.member`, an unresolved candidate and a blocked callee, and a write
# to a module-scope binding is none of the five; the lift hid it further by
# minting a fresh same-spelled local per relation instead of naming the
# binding. So a relation whose body advanced a parser cursor published `none`,
# and `comptime.foldRelationBody` — which reads that card — replaced its
# caller with a constant and deleted the write. Measured, `--backend=direct`:
# a program answering 2 answered 0.
#
# `none` FELL WHEN THAT WAS REPAIRED, and it fell in two steps because two
# lanes reached the same defect. On `examples`:
#
#     edc726bf   none 1043   one 123   unknown 165   before either
#     539e7902   none 1024   one 142   unknown 165   the lift names the binding
#     this file  none 1019   one 154   unknown 163   + closure and cardinality
#
# The middle row is the state `MIN_NONE` was left ROTTEN at: the floor still
# said 1043 and the tree measured 1024, so this gate was RED on `main` and the
# census it exists to police was not being read. It is pinned at the measured
# value now, ONCE, with this paragraph as the argument. Moving it again needs
# its own argument; a lane that lowers it to make a census pass is doing the
# thing the rule above exists to stop.
#
# AND IT FELL A THIRD TIME, BY ONE, FOR THE READ HALF (gaps/GAP-229.md). The
# write column said which relations ADVANCE a module binding and nothing said
# which relations READ one, so a relation whose answer depends on when it is
# called — `_at` in `lib/compiler/comptime.id`, reading the cursor `_skip_ws`
# advances — published `none`. That `none` was not a proof either: the lift
# now records bare-name reads against the exact module binding they resolve
# to, and the effect derivation blocks AND grounds a read of a binding SOME
# relation writes, so `one` names the binding READ as well as the binding
# written. On `examples`, corpus of this tree:
#
#     before     none 1058   one 169   unknown 151
#     after      none 1057   one 170   unknown 151
#
# paid out of a non-proof `none`, with `unknown` untouched. The controls are
# both directions at once: `_hex_val` and `_is_digit` (closed functions of
# their operands) keep `none`, and a read of a binding NOTHING writes stays
# `none` — the write column is the discriminant, and the graph unit test
# "reading a mutated module binding is an observation; a constant read is
# not" pins both.
#
# The floor still catches a LOSS, and the anti-regression ratchet for the
# repair itself is not here at all — it is `gate/speculation.sh`, whose
# "...publishing effect none" row must stay at zero while its severed twin
# stays nonzero. That pair is immune to ordinary corpus growth in a way a
# ceiling here is not.
#
# AND THE CENSUS IS NOT ENOUGH. A card can be published, counted, projected to
# JSON and read by nobody. The COUNTERFACTUAL removes the fact and NOTHING
# else — `IDOL_EFFECT_SEVER=1` suppresses the `effect` writes in
# `publishApplicationEffects` — and requires the artifact to change. If the two
# arms are byte identical the fact is decoration, whatever the census says.
#
# IT SEVERS ONE FACT, WHICH IT DID NOT ALWAYS DO. The sever was an early return
# from the publication loop, so it also suppressed the `authority = .none`
# write; `effectFreeApplications` reads BOTH cards, so the control was removing
# two facts and attributing the difference to one. Measured: that inflated the
# changed-module count by one. A control that severs more than it names proves
# nothing about the thing it names.
#
# THE SUBJECT IS CORPUS CODE, NOT A FIXTURE WRITTEN FOR THE GATE.
# `examples/demand/tail.id` was already in the tree and already checks every
# one of its answers by value. A fixture authored here would also have had to
# declare module-scope vocabulary the declaration freeze refuses, and would
# have measured a program that exists to be measured.
#
# ITS SCOPE IS ONE MODULE, AND THE POPULATION IS MEASURED RATHER THAN QUOTED.
# The subject below is one of the modules the fact reaches; the size of that
# set is not written down here, because a number in a comment rots on its own
# while the runner keeps passing. Measure it:
#
#   for f in $(find examples lib -name '*.id'); do
#     idol compile "$f" --emit asm -o a.s
#     IDOL_EFFECT_SEVER=1 idol compile "$f" --emit asm -o b.s
#     cmp -s a.s b.s || echo "$f"
#   done
#
# The gate checks ONE of them rather than all because two compiles of the whole
# corpus is a two-minute gate, and the runner comparison below fails just as
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

# THE FLOORS. These are the ONLY census numbers this file states, and they are
# inequalities rather than equalities so ordinary corpus growth does not rot
# them. `gate/effect.sh --census-only` prints what the tree actually measures;
# nothing above repeats it.
#
# `MIN_NONE` is the reversal control for moving `publishApplicationEffects`
# after `publishApplicationWorlds`: that reordering must not have taken a
# single proof of unobservability away. It is pinned at the value the base
# measured, so a positive card bought by giving up a `none` fails here — with
# the one documented exception above.
#
# `MIN_ONE` rose with it, and that is the half that makes the exception
# checkable: the mutation repair does not merely stop saying `none`, it names
# the binding written. A change that took those `none`s and left them in
# `unknown` would pass a lowered `MIN_NONE` and fail here. It caught exactly
# that during the repair — grounding the effect card only from the call-graph
# CLOSURE dropped the exact binding for every relation that both writes one and
# applies something unresolved, and 18 `one` cards over `examples lib` became
# `unknown`. The direct rows ground first now, and this floor is why that was
# noticed rather than shipped.
#
# `MIN_ONE` rose again with the read half (GAP-229): the positive card now
# also names the binding a relation READS when some relation writes it, and
# the floor is pinned at the value the tree measured so a change that dropped
# the read grounding back into `none` or `unknown` fails here.
MIN_APPS=${EFFECT_MIN_APPS:-1200}
MIN_NONE=${EFFECT_MIN_NONE:-1019}
MIN_ONE=${EFFECT_MIN_ONE:-170}

command -v jq >/dev/null 2>&1 || { echo "effect: jq not on PATH" >&2; exit 64; }
[ -x "$idol" ] || { echo "effect: no compiler at $idol (set IDOL=)" >&2; exit 64; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idoleffect.XXXXXX") || exit 64
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

# THE CENSUS ABOVE IS MEASURABLE ANYWHERE; THIS HALF IS NOT. The counterfactual
# compares emitted assembly, so it needs a native realization, and on a host
# without one this gate printed its four census counts and then
# "EFFECT BLOCKED -- the subject did not compile with the effect fact
# published" — which reads as the publisher having broken. The census keeps its
# floors (that is real law signal this host can carry) and the counterfactual
# says which half went unmeasured. Still non-zero: half a gate is not a pass.
. "$repo/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the counterfactual half (the census above DID run and its floors held)'
    exit 1
fi

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
