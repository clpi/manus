#!/bin/sh
# gate/speculation.sh -- THE MEASUREMENT THAT SAYS WHETHER TO BUILD A
# TERMINATION FACT, AND THE CONTROL THAT SAYS IT IS NOT TIME YET.
#
# WHY THIS EXISTS. `gate/effect.sh` took `ApplicationFact.effect` from a fact
# whose positive case was unreachable to one that names the observation. That
# answers exactly one of the questions speculation asks. The rest --
#
#     does it terminate?   can it trap?      can it diverge?
#     can it mutate?       can it allocate?  does order matter?
#     is identity observable?
#
# -- are still unanswered, and the obvious next move is to publish termination
# because a refusal in `native_backend.ifConvArmChainAdmissible` names it by
# spelling ("no-termination-fact"). This file is the reason not to, and it is
# a runner rather than a paragraph so the reason expires on its own the day it
# stops holding.
#
# THREE THINGS ARE MEASURED HERE, AND THE THIRD IS THE ONE THAT MATTERS.
#
#   1. THE CENSUS. How many two-sided `if` windows the corpus offers, how many
#      are converted, and which ground refuses the rest. Printed, never quoted.
#
#   2. THE COUNTERFACTUAL, RUN BACKWARDS. A published fact is controlled by
#      SEVERING it and watching the artifact change (`gate/effect.sh`).
#      Termination has no producer to sever, so the control ASSUMES the
#      strongest answer the fact could ever give -- `IDOL_TERMINATION_ASSUME=1`
#      makes every applied relation terminate -- and requires the artifact to
#      be BYTE-IDENTICAL. Identical means the producer would change nothing.
#      That is a refutation of the feature, and it is the only kind of evidence
#      that can refute one before it is written.
#
#      The compiler counts the same thing statically: `no_termination_fact` is
#      how many arms the refusal fired on, and `no_termination_fact_masked` is
#      how many of those the INDEPENDENT lineage ground would have refused
#      anyway. Equal counts and identical artifacts are the same finding
#      arrived at from two directions.
#
#   3. THE HAZARD, which is why the sequencing "delete the lineage rule, then
#      publish termination" is not merely premature but unsound. The FIRST
#      admission test on an if-conversion arm is `armInstrEffectAdmissible`:
#      `effect == .none and authority == .none`. Measured below: relations
#      whose body assigns module-scope `global`s used to publish `effect:
#      none`. The graph now publishes exact relation -> binding mutation rows,
#      and this gate requires those rows to agree with an independent source
#      census before accepting the effect cards derived from them.
#
#      With the lineage rule gone and a termination fact published, the two
#      surviving `no-termination-fact` arms in `lib/compiler/comptime.id` --
#      `left = left + _term()` against `left = left - _term()` -- would be
#      admitted, and BOTH arms would run a recursive-descent parser step that
#      advances a module-scope cursor. The missing fact at those sites is not
#      termination. It is MUTATION.
#
#   4. THE SECOND READING, because the mutation fact took the population away
#      from the ground it was measuring. Those two arms no longer reach the
#      termination refusal at all -- `effect-not-none` refuses them first --
#      so a counterfactual over "the modules that carry a termination refusal"
#      now has no subjects, and skipping it is the vacuous pass
#      `gate/vacuity.sh` exists to convict. Every reading below is therefore
#      taken TWICE: once on the compiler, and once with `IDOL_MUTATION_SEVER=1`,
#      which removes the mutation column and NOTHING else. Severed, the
#      population comes back, and that is where the termination counterfactual
#      is run -- both of its arms severed, so the only variable is still the
#      termination assumption. The same second reading is what tells a zero in
#      the hazard census from a census that examined nothing.
#
# USAGE:
#   gate/speculation.sh                census + counterfactual + hazard
#   gate/speculation.sh --census-only  census only (stated, not silent)
#   SPECULATION_CORPUS="examples lib"  default is `examples lib`
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64

idol=${IDOL:-$repo/zig-out/bin/idol}
corpus=${SPECULATION_CORPUS:-examples lib}
extract="$repo/gate/speculation.awk"

# THE FLOORS. Inequalities, not equalities, so ordinary corpus growth does not
# rot them; `gate/speculation.sh --census-only` prints what the tree measures
# and nothing above repeats it.
MIN_MODULES=${SPECULATION_MIN_MODULES:-200}
MIN_CANDIDATES=${SPECULATION_MIN_CANDIDATES:-25}
MIN_MUTATORS=${SPECULATION_MIN_MUTATORS:-5}

# THE NAMED WITNESS, and it is a PIN rather than a discovery.
#
# Everything below turns on there being an arm the mutation effect actually
# refuses. Discovering that set by scanning the corpus means a module that
# stops compiling, or stops reaching arm64, or stops emitting its census line,
# SILENTLY empties it -- and the module and candidate floors above are far too
# broad to notice one module leaving. The gate would then report a clean
# refutation having measured nothing, which is the exact shape `gate/vacuity.sh`
# exists to convict.
#
# So the module that carries the refusal is named here and its disappearance is
# FATAL. If the tree legitimately stops refusing on termination, this pin is
# the thing an author has to change on purpose, and changing it is where the
# argument gets re-derived.
WITNESS=${SPECULATION_WITNESS:-lib/compiler/comptime.id}

command -v jq >/dev/null 2>&1 || { echo "speculation: jq not on PATH" >&2; exit 64; }
[ -x "$idol" ] || { echo "speculation: no compiler at $idol (set IDOL=)" >&2; exit 64; }
[ -f "$extract" ] || { echo "speculation: gate/speculation.awk is missing" >&2; exit 64; }

work=$(mktemp -d -t idolspeculation) || exit 64
trap 'rm -rf "$work"' EXIT INT TERM

die() { printf 'SPECULATION BLOCKED -- %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

mode=full
while [ $# -gt 0 ]; do
    case "$1" in
        --census-only) mode=census ;;
        -h|--help) sed -n '1,60p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

for dir in $corpus; do
    find "$dir" -name '*.id' -type f 2>/dev/null
done | LC_ALL=C sort >"$work/files"

# ======================================================================= CENSUS
: >"$work/rows"
: >"$work/severed"
modules=0
while IFS= read -r src; do
    [ -n "$src" ] || continue
    line=$(IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm -o /dev/null 2>&1 |
        grep '^ifconv2 ' | head -1)
    [ -n "$line" ] || continue
    modules=$((modules + 1))
    printf '%s\t%s\n' "$src" "$line" >>"$work/rows"
    cut=$(IDOL_MUTATION_SEVER=1 IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm -o /dev/null 2>&1 |
        grep '^ifconv2 ' | head -1)
    [ -n "$cut" ] || continue
    printf '%s\t%s\n' "$src" "$cut" >>"$work/severed"
done <"$work/files"

[ "$modules" -gt 0 ] || die "ZERO modules reached the arm64 census over [$corpus]. Examining nothing is not a pass."

sum() { LC_ALL=C awk -F'\t' -v k="$1" '{
    n = split($2, a, /[ ()]+/)
    for (i = 1; i <= n; i++) { split(a[i], kv, "="); if (kv[1] == k) t += kv[2] }
} END { print t + 0 }' "${2:-$work/rows}"; }

candidates=$(sum two_sided_ifs)
admitted=$(sum admitted)
refused=$(sum refused)
cap=$(sum arm_op_cap)
latency=$(sum latency)
trap_n=$(sum trap)
effect_n=$(sum effect_not_none)
term_n=$(sum no_termination_fact)
term_masked=$(sum no_termination_fact_masked)
lineage=$(sum lineage)
cut_effect=$(sum effect_not_none "$work/severed")
cut_term=$(sum no_termination_fact "$work/severed")
cut_masked=$(sum no_termination_fact_masked "$work/severed")

note "speculation census over [$corpus] -- $modules module(s) reached arm64"
printf '%-28s %8s\n' "two-sided if candidates" "$candidates"
printf '%-28s %8s\n' "converted" "$admitted"
printf '%-28s %8s\n' "refused" "$refused"
printf '%-28s %8s\n' "  arm-op-cap" "$cap"
printf '%-28s %8s\n' "  arm-op-latency" "$latency"
printf '%-28s %8s\n' "  arm-op-trapping" "$trap_n"
printf '%-28s %8s\n' "  effect-not-none" "$effect_n"
printf '%-28s %8s\n' "  no-termination-fact" "$term_n"
printf '%-28s %8s\n' "    of which masked" "$term_masked"
printf '%-28s %8s\n' "  arm-op-lineage" "$lineage"
printf '%-28s %8s\n' "mutation SEVERED:" ""
printf '%-28s %8s\n' "  effect-not-none" "$cut_effect"
printf '%-28s %8s\n' "  no-termination-fact" "$cut_term"
printf '%-28s %8s\n' "    of which masked" "$cut_masked"

[ "$modules" -ge "$MIN_MODULES" ] || die "only $modules module(s) reached arm64, floor $MIN_MODULES. The corpus stopped lowering; a census over nothing says nothing."
[ "$candidates" -ge "$MIN_CANDIDATES" ] || die "only $candidates two-sided if candidate(s), floor $MIN_CANDIDATES. The population this measurement is about has collapsed, and every conclusion below is about a different tree."
[ "$term_masked" -le "$term_n" ] || die "no_termination_fact_masked ($term_masked) exceeds no_termination_fact ($term_n). The counter counts a subset by construction; this is a compiler defect, not a census result."

# THE WITNESS MUST STILL BE THERE. Three separate ways it can vanish, and all
# three read as "0 refusals" to a census that only sums.
LC_ALL=C grep -qx -- "$WITNESS" "$work/files" ||
    die "the named witness $WITNESS is not in the corpus [$corpus]. Set SPECULATION_WITNESS deliberately; do not let the subject leave by accident."
witness_row=$(LC_ALL=C awk -F'\t' -v w="$WITNESS" '$1 == w { print $2 }' "$work/rows")
[ -n "$witness_row" ] ||
    die "the named witness $WITNESS emitted no ifconv2 census line. It stopped compiling, stopped reaching arm64, or stopped reporting -- and a census that skipped it would have reported a clean refutation having measured nothing."
witness_of() { printf '%s\n' "$1" |
    LC_ALL=C awk -v k="$2" '{ n = split($0, a, /[ ()]+/)
        for (i = 1; i <= n; i++) { split(a[i], kv, "="); if (kv[1] == k) print kv[2] + 0 } }'; }
witness_cut_row=$(LC_ALL=C awk -F'\t' -v w="$WITNESS" '$1 == w { print $2 }' "$work/severed")
[ -n "$witness_cut_row" ] ||
    die "the named witness $WITNESS emitted no ifconv2 census line with the mutation column severed. The control did not reach it, so nothing below can be attributed to the fact."
witness_effect=$(witness_of "$witness_row" effect_not_none)
witness_term=$(witness_of "$witness_row" no_termination_fact)
witness_cut_term=$(witness_of "$witness_cut_row" no_termination_fact)
printf '%-28s %8s\n' "witness mutation refusals" "${witness_effect:-0}"
printf '%-28s %8s\n' "witness term refusals" "${witness_term:-0}"
printf '%-28s %8s\n' "  ...with mutation severed" "${witness_cut_term:-0}"

# THE ARM IS STILL THERE, SOMETHING ELSE REFUSES IT, AND THE SOMETHING ELSE IS
# THIS FACT. Three checks, because any one alone is indistinguishable from the
# subject having left the corpus:
#
#   the witness carries an EFFECT refusal            the population is present
#   severing mutation brings the TERM refusal back   the effect card is why
#   the witness reaches NO termination ground        the order is the safe one
#
# `left = left + _term()` against `left = left - _term()` is the arm.
# `armInstrEffectAdmissible` refuses it now that `_term` publishes
# `effect: one(_bad)` instead of `effect: none`, which is the ground that
# should have been standing in front of it from the beginning (GAP-225).
[ "${witness_effect:-0}" -ge 1 ] ||
    die "the named witness $WITNESS carries no effect-not-none refusal (${witness_effect:-0}). The mutation fact stopped governing speculation."
[ "${witness_cut_term:-0}" -ge 1 ] ||
    die "severing the mutation column did not bring a no-termination-fact refusal back to $WITNESS (${witness_cut_term:-0}). The control reaches no decision, so the published arm's readings cannot be attributed to the fact. Check semantic_graph.mutationSevered."
[ "${witness_term:-0}" -eq 0 ] ||
    die "the named witness $WITNESS still reaches the termination ground (${witness_term:-0} refusal(s)). The effect card is supposed to refuse a call-carrying arm first; one that gets past it is an arm whose mutation the graph did not see."

if [ "$mode" = census ]; then
    note "speculation: --census-only -- the counterfactual and the hazard were SKIPPED, not passed."
    exit 0
fi

# ================================================= COUNTERFACTUAL: ASSUME IT
#
# RUN IN THE SEVERED ARM, AND SKIPPED NOWHERE. Only the modules the refusal
# actually fired in can move, because `terminationAssumed()` guards exactly
# that one branch -- and on the compiler as it stands, none do: the mutation
# effect refuses first and `no_termination_fact` is 0 corpus-wide. This used to
# print "skipped, not passed", which is honest and is still a gate that stopped
# measuring the thing it exists to measure.
#
# The refutation is a real question whatever refuses first, because "publish
# termination" is still a thing a lane can propose. So the subjects are taken
# from the SEVERED census -- the exact condition under which the ground has a
# population -- and BOTH arms carry `IDOL_MUTATION_SEVER=1`, so the only
# variable is the termination assumption. What it measures is unchanged: assume
# the strongest answer the fact could ever give, and require the artifact to be
# identical.
LC_ALL=C awk -F'\t' '$2 !~ /no_termination_fact=0 / { print $1 }' "$work/severed" >"$work/subjects"
subjects=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/subjects")

changed=0
reached=0
would=0
[ "$term_n" -eq 0 ] ||
    die "$term_n arm(s) reach the termination ground on the UNSEVERED compiler. The effect card is supposed to refuse a call-carrying arm first; anything that gets past it is an arm whose mutation the graph did not see, and this gate's argument has to be re-derived rather than kept passing."
if [ "$cut_term" -eq 0 ]; then
    die "no arm in [$corpus] is refused for want of a termination fact even with the mutation column severed, yet the named witness was required to carry one above. The two readings disagree, and one of them is a bug."
else
    [ "$subjects" -gt 0 ] || die "the severed census counted $cut_term no-termination-fact refusal(s) but named no module carrying one. The row filter and the counter disagree."
    while IFS= read -r src; do
    [ -n "$src" ] || continue
    IDOL_MUTATION_SEVER=1 IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm \
        -o "$work/base.s" 2>"$work/base.report" >/dev/null ||
        die "$src did not compile in the baseline arm."
    IDOL_MUTATION_SEVER=1 IDOL_TERMINATION_ASSUME=1 IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm \
        -o "$work/assumed.s" 2>"$work/assumed.report" >/dev/null ||
        die "$src did not compile with termination ASSUMED. The control must change a DECISION, not break the compiler."

    base_line=$(LC_ALL=C grep '^ifconv2 ' "$work/base.report" | head -1)
    assumed_line=$(LC_ALL=C grep '^ifconv2 ' "$work/assumed.report" | head -1)
    [ -n "$assumed_line" ] ||
        die "the assumed arm of $src printed no ifconv2 census line at all. A control that produced no reading is not a reading of zero."

    # THE INSTRUMENT MUST BE SHOWN TO REACH. The expected artifact answer is
    # "identical", which is also exactly what a control wired to nothing
    # reports, so the assumed arm has to demonstrate it moved the census it
    # names before its byte-identical artifact counts for anything. Under the
    # assumption the chain CONTINUES past the termination ground, so the
    # refusal lands on a different ground and the two lines cannot match.
    [ "$base_line" != "$assumed_line" ] ||
        die "IDOL_TERMINATION_ASSUME=1 left the census of $src unchanged. The control reaches no decision, so its byte-identical artifact proves nothing about the fact. Check native_backend.terminationAssumed."
    reached=$((reached + 1))

    n=$(printf '%s\n' "$assumed_line" |
        LC_ALL=C awk '{ k = split($0, a, /[ ()]+/)
            for (i = 1; i <= k; i++) { split(a[i], kv, "="); if (kv[1] == "termination_would_admit") print kv[2] + 0 } }')
    would=$((would + ${n:-0}))

    # AND IT MUST NOT REACH THE ARTIFACT. `terminationAssumed` can only turn
    # one refusal into a different refusal -- it is never allowed to admit,
    # because a measuring instrument on the production path is a way for an
    # inherited environment to silently delete a safety refusal. That is a
    # claim about the code, so it is CHECKED rather than argued.
        cmp -s "$work/base.s" "$work/assumed.s" || {
            note "  ARTIFACT MOVED under the assumption: $src"
            changed=$((changed + 1))
        }
    done <"$work/subjects"
fi
printf '%-28s %8s\n' "counterfactual subjects" "$subjects"
printf '%-28s %8s\n' "  control reached" "$reached"
printf '%-28s %8s\n' "  would admit" "$would"
printf '%-28s %8s\n' "artifacts changed" "$changed"

[ "$changed" -eq 0 ] ||
    die "IDOL_TERMINATION_ASSUME=1 changed $changed artifact(s). The control is only allowed to turn one refusal into another; an artifact that moves means the assumption reached an ADMISSION, and an inherited environment variable can now delete a safety refusal from an ordinary compile. See native_backend.terminationAssumed."

# =========================================================== HAZARD: MUTATION
# Relations that DIRECTLY assign a module-scope `global`, intersected with the
# effect card their applications carry. A row here is a relation the graph
# positively asserts is unobservable and whose body writes module state.
: >"$work/mutators"
: >"$work/cutmutators"
: >"$work/allsource"
: >"$work/allmut"
: >"$work/allgraphmut"
: >"$work/missingmut"
: >"$work/extramut"
while IFS= read -r src; do
    [ -n "$src" ] || continue
    grep -q '^global[ 	]' "$src" 2>/dev/null || continue
    LC_ALL=C awk -f "$extract" "$src" | LC_ALL=C sort -u >"$work/mutpair"
    cut -f1 "$work/mutpair" | LC_ALL=C sort -u >"$work/mutrel"
    [ -s "$work/mutrel" ] || continue
    cat "$work/mutpair" >>"$work/allsource"
    "$idol" graph "$src" >"$work/g.json" 2>/dev/null || continue
    cat "$work/mutpair" >>"$work/allmut"
    jq -e 'has("mutations") and (.mutations | type == "array")' "$work/g.json" >/dev/null 2>&1 ||
        die "$src graph export has no mutations array; absence is not proof of no mutation."
    jq -r '(reduce .nodes[] as $n ({}; .[$n.id|tostring] = $n.name)) as $nm
           | .mutations[]
           | [($nm[.relation|tostring] // "?"), ($nm[.binding|tostring] // "?")]
           | @tsv' "$work/g.json" 2>/dev/null | LC_ALL=C sort -u >"$work/graphmut" ||
        die "$src mutation projection could not be read."
    cat "$work/graphmut" >>"$work/allgraphmut"
    LC_ALL=C comm -23 "$work/mutpair" "$work/graphmut" |
        LC_ALL=C awk -v f="$src" 'NF { print f "\t" $0 }' >>"$work/missingmut"
    LC_ALL=C comm -13 "$work/mutpair" "$work/graphmut" |
        LC_ALL=C awk -v f="$src" 'NF { print f "\t" $0 }' >>"$work/extramut"
    jq -r '(reduce .nodes[] as $n ({}; .[$n.id|tostring] = $n.name)) as $nm
           | .applications[]
           | select(.effect.card == "none")
           | ($nm[.relation|tostring] // "?")' "$work/g.json" 2>/dev/null |
        LC_ALL=C sort -u >"$work/free" || continue
    LC_ALL=C comm -12 "$work/mutrel" "$work/free" 2>/dev/null |
        LC_ALL=C awk -v f="$src" 'NF { print f "\t" $0 }' >>"$work/mutators"
    # AND THE SAME INTERSECTION WITH THE COLUMN SEVERED. `mutators` must be
    # zero, and a zero from a scan that examined nothing looks the same. This
    # is the row that has to be NONZERO for the zero above to mean anything.
    IDOL_MUTATION_SEVER=1 "$idol" graph "$src" >"$work/cut.json" 2>/dev/null || continue
    jq -r '(reduce .nodes[] as $n ({}; .[$n.id|tostring] = $n.name)) as $nm
           | .applications[]
           | select(.effect.card == "none")
           | ($nm[.relation|tostring] // "?")' "$work/cut.json" 2>/dev/null |
        LC_ALL=C sort -u >"$work/cutfree" || continue
    LC_ALL=C comm -12 "$work/mutrel" "$work/cutfree" 2>/dev/null |
        LC_ALL=C awk -v f="$src" 'NF { print f "\t" $0 }' >>"$work/cutmutators"
done <"$work/files"

mutators=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/mutators")
allsource=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/allsource")
allmut=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/allmut")
graphmut=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/allgraphmut")
missingmut=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/missingmut")
extramut=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/extramut")
cutmutators=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/cutmutators")
printf '%-28s %8s\n' "source mutation pairs" "$allsource"
printf '%-28s %8s\n' "  graph-measured pairs" "$allmut"
printf '%-28s %8s\n' "graph mutation facts" "$graphmut"
printf '%-28s %8s\n' "  source facts missing" "$missingmut"
printf '%-28s %8s\n' "  extra graph facts" "$extramut"
printf '%-28s %8s\n' "  ...publishing effect none" "$mutators"
printf '%-28s %8s\n' "  ...severed, effect none" "$cutmutators"
LC_ALL=C awk -F'\t' '{ printf "    %-34s %s\n", $2, $1 }' "$work/mutators" >&2

[ "$allmut" -ge "$MIN_MUTATORS" ] ||
    die "only $allmut source relation/binding mutation pair(s), floor $MIN_MUTATORS. The corpus lost the positive population; a zero graph result would be vacuous."
[ "$missingmut" -eq 0 ] ||
    die "$missingmut source mutation fact(s) are absent from the graph. The producer lost a module-binding write."
[ "$extramut" -eq 0 ] ||
    die "$extramut graph mutation fact(s) have no source witness. The producer invented a write or crossed a shadow."
[ "$cutmutators" -ge "$MIN_MUTATORS" ] ||
    die "with the mutation column severed only $cutmutators relation(s) publish effect none about a body that writes module state, floor $MIN_MUTATORS. The control reaches no decision, so the published arm's zero proves nothing. Check semantic_graph.mutationSevered."
[ "$mutators" -eq 0 ] ||
    die "$mutators relation(s) write module bindings yet publish effect none. Mutation is observable; see gaps/GAP-225.md."

# ==================================================================== THE RULE
if [ "$would" -eq 0 ]; then
    note "speculation: $term_n arm(s) reach the termination ground on the compiler; $cut_term reach it with the mutation column severed, $cut_masked of those ALSO refused by the independent lineage ground, and $would would be admitted by a real producer."
    note "speculation: MODULE-BINDING MUTATION IS NOW THE EARLIER REFUSAL. $allsource source mutation pair(s), $graphmut in the graph, $cutmutators publishing effect none with the column severed and $mutators with it published."
    note "speculation: DO NOT BUILD THE TERMINATION PRODUCER. It would govern nothing."
    note "speculation: SPECULATION OK."
    exit 0
fi

die "a real producer would now unblock $would if-conversion arm(s) ($cut_term refused on termination in the severed arm, $cut_masked of them masked). That is a consumer. Re-derive this gate's argument against the current effect and mutation columns before building it -- gaps/GAP-225.md is the ordering the last derivation turned on."
