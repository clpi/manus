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
#      whose body does nothing but assign module-scope `global`s publish
#      `effect: none`. `publishApplicationEffects` blocks on a foreign body, a
#      `.capture` edge, a `.member` read and an unresolved call -- and a write
#      to a module-scope binding is none of those, because the lift mints a
#      FRESH scope-local entity for it instead of an edge to the module
#      binding. So `effect: none` answers "does this observe the outside
#      world", and does not answer "can this mutate".
#
#      With the lineage rule gone and a termination fact published, the two
#      surviving `no-termination-fact` arms in `lib/compiler/comptime.id` --
#      `left = left + _term()` against `left = left - _term()` -- would be
#      admitted, and BOTH arms would run a recursive-descent parser step that
#      advances a module-scope cursor. The missing fact at those sites is not
#      termination. It is MUTATION.
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
modules=0
while IFS= read -r src; do
    [ -n "$src" ] || continue
    line=$(IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm -o /dev/null 2>&1 |
        grep '^ifconv2 ' | head -1)
    [ -n "$line" ] || continue
    modules=$((modules + 1))
    printf '%s\t%s\n' "$src" "$line" >>"$work/rows"
done <"$work/files"

[ "$modules" -gt 0 ] || die "ZERO modules reached the arm64 census over [$corpus]. Examining nothing is not a pass."

sum() { LC_ALL=C awk -F'\t' -v k="$1" '{
    n = split($2, a, /[ ()]+/)
    for (i = 1; i <= n; i++) { split(a[i], kv, "="); if (kv[1] == k) t += kv[2] }
} END { print t + 0 }' "$work/rows"; }

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

[ "$modules" -ge "$MIN_MODULES" ] || die "only $modules module(s) reached arm64, floor $MIN_MODULES. The corpus stopped lowering; a census over nothing says nothing."
[ "$candidates" -ge "$MIN_CANDIDATES" ] || die "only $candidates two-sided if candidate(s), floor $MIN_CANDIDATES. The population this measurement is about has collapsed, and every conclusion below is about a different tree."
[ "$term_masked" -le "$term_n" ] || die "no_termination_fact_masked ($term_masked) exceeds no_termination_fact ($term_n). The counter counts a subset by construction; this is a compiler defect, not a census result."

if [ "$mode" = census ]; then
    note "speculation: --census-only -- the counterfactual and the hazard were SKIPPED, not passed."
    exit 0
fi

# ================================================= COUNTERFACTUAL: ASSUME IT
# Only the modules the refusal actually fired in can change, because
# `terminationAssumed()` guards exactly that one branch. Compiling the other
# two hundred twice would measure the compiler's determinism, not this fact.
LC_ALL=C awk -F'\t' '$2 !~ /no_termination_fact=0 / { print $1 }' "$work/rows" >"$work/subjects"
subjects=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/subjects")

if [ "$term_n" -eq 0 ]; then
    note "speculation: no arm in [$corpus] is refused for want of a termination fact. There is nothing to control."
    changed=0
else
    [ "$subjects" -gt 0 ] || die "the census counted $term_n no-termination-fact refusal(s) but named no module carrying one. The row filter and the counter disagree."
    changed=0
    reached=0
    while IFS= read -r src; do
        [ -n "$src" ] || continue
        "$idol" compile "$src" --emit asm -o "$work/base.s" >/dev/null 2>&1 ||
            die "$src did not compile in the baseline arm."
        IDOL_TERMINATION_ASSUME=1 IDOL_IFCONV_REPORT=1 "$idol" compile "$src" --emit asm \
            -o "$work/assumed.s" 2>"$work/assumed.report" >/dev/null ||
            die "$src did not compile with termination ASSUMED. The control must change a DECISION, not break the compiler."
        # THE INSTRUMENT MUST BE SHOWN TO REACH. `changed=0` is the answer this
        # gate expects, and it is also exactly what a control wired to nothing
        # reports. So the assumed arm has to demonstrate that it moved the
        # refusal it names; a byte-identical artifact only means something once
        # the census under the assumption is different from the census without.
        LC_ALL=C grep -q 'no_termination_fact=0 ' "$work/assumed.report" ||
            die "IDOL_TERMINATION_ASSUME=1 did not clear the no-termination-fact refusal in $src. The control reaches no decision, so its byte-identical artifact proves nothing about the fact. Check native_backend.terminationAssumed."
        reached=$((reached + 1))
        cmp -s "$work/base.s" "$work/assumed.s" || {
            note "  differs under the assumption: $src"
            changed=$((changed + 1))
        }
    done <"$work/subjects"
    printf '%-28s %8s\n' "counterfactual subjects" "$subjects"
    printf '%-28s %8s\n' "  control reached" "$reached"
    printf '%-28s %8s\n' "artifacts changed" "$changed"
fi

# =========================================================== HAZARD: MUTATION
# Relations that DIRECTLY assign a module-scope `global`, intersected with the
# effect card their applications carry. A row here is a relation the graph
# positively asserts is unobservable and whose body writes module state.
: >"$work/mutators"
: >"$work/allmut"
while IFS= read -r src; do
    [ -n "$src" ] || continue
    grep -q '^global[ 	]' "$src" 2>/dev/null || continue
    LC_ALL=C awk -f "$extract" "$src" | cut -f1 | LC_ALL=C sort -u >"$work/mutrel"
    [ -s "$work/mutrel" ] || continue
    cat "$work/mutrel" >>"$work/allmut"
    "$idol" graph "$src" >"$work/g.json" 2>/dev/null || continue
    jq -r '(reduce .nodes[] as $n ({}; .[$n.id|tostring] = $n.name)) as $nm
           | .applications[]
           | select(.effect.card == "none")
           | ($nm[.relation|tostring] // "?")' "$work/g.json" 2>/dev/null |
        LC_ALL=C sort -u >"$work/free" || continue
    LC_ALL=C comm -12 "$work/mutrel" "$work/free" |
        LC_ALL=C awk -v f="$src" 'NF { print f "\t" $0 }' >>"$work/mutators"
done <"$work/files"

mutators=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/mutators")
allmut=$(LC_ALL=C awk 'END { print NR + 0 }' "$work/allmut")
printf '%-28s %8s\n' "global-mutating relations" "$allmut"
printf '%-28s %8s\n' "  ...publishing effect none" "$mutators"
LC_ALL=C awk -F'\t' '{ printf "    %-34s %s\n", $2, $1 }' "$work/mutators" >&2

[ "$mutators" -ge "$MIN_MUTATORS" ] ||
    die "only $mutators relation(s) both assign a module-scope global and publish effect none, floor $MIN_MUTATORS. Either the corpus lost the witness or the effect fact learned to see mutation -- and in the second case this gate's whole argument has to be re-derived rather than kept passing."

# ==================================================================== THE RULE
if [ "$term_n" -gt 0 ] && [ "$term_masked" -eq "$term_n" ] && [ "$changed" -eq 0 ]; then
    note "speculation: every one of the $term_n no-termination-fact refusal(s) is ALSO refused by the independent lineage ground, and assuming the fact changes $changed artifact byte(s) across $subjects subject(s)."
    note "speculation: DO NOT BUILD THE TERMINATION PRODUCER. It would govern nothing."
    note "speculation: SPECULATION OK."
    exit 0
fi

if [ "$term_n" -eq 0 ] && [ "$changed" -eq 0 ]; then
    note "speculation: no arm is refused on termination at all. SPECULATION OK."
    exit 0
fi

die "an if-conversion arm is now refused ONLY for want of a termination fact: $term_n refusal(s), $term_masked of them masked, $changed artifact(s) changed under the assumption. That is a real consumer, and it arrived while $mutators relation(s) in this corpus still publish effect none about a body that writes module-scope state. Publishing termination here admits speculation that runs a mutation twice. The mutation fact comes first -- see gaps/GAP-225.md."
