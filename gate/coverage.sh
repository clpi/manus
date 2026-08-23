#!/bin/sh
# gate/coverage.sh — the PRODUCER / CONSUMER / COVERAGE matrix for semantic
# fact families.
#
# WHY THIS EXISTS. A fact having a type, a store, a public reader and a JSON
# column says NOTHING about whether it reaches real programs. Measured this
# session: `SourceQuoteFact` published 0 facts on `s = 'abc'`, on
# `global names = {…}`, and on its own test's source, while the accessor and
# the JSON column both existed. `ApplicationFact.realization` is serialized on
# every application with no writer at all. `valueOrigin` had zero callers.
#
# THREE FAILURE MODES LOOK IDENTICAL DOWNSTREAM AND NEED OPPOSITE FIXES:
#   producer-hollow  the fact exists and its producer reaches ~nothing
#   consumer-zero    the fact is produced, correct, and read by nobody
#   unproduced       the answer is derivable and nobody computes it
# They are three separate columns below, never one score.
#
# IT COUNTS RATHER THAN ASSERTS, exactly like `gate/all.sh`, so the number
# cannot rot the way an asserted one does. There is NO CACHE AND NO INDEX: the
# corpus is lifted fresh into a mktemp that is deleted on exit. The tree is the
# store. A persisted matrix would be a second store needing a deletion witness.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64

idol=${IDOL:-$repo/zig-out/bin/idol}
corpus=${COVERAGE_CORPUS:-examples lib}
budget=${COVERAGE_BUDGET:-}

command -v jq >/dev/null 2>&1 || { echo "coverage: jq not on PATH" >&2; exit 64; }
[ -x "$idol" ] || { echo "coverage: no compiler at $idol (set IDOL=)" >&2; exit 64; }

work=$(mktemp -d -t idolcoverage) || exit 64
trap 'rm -rf "$work"' EXIT INT TERM

# ---------------------------------------------------------------------------
# 1. COVERAGE BY CONSTRUCTION.
#
# Lift every corpus module and count, per fact family, the LAWFUL SOURCE
# OCCURRENCES ELIGIBLE for the fact against the facts actually published. The
# denominator never comes from the family being measured: application cards are
# measured against the applications that exist, `origins` against the operand
# and subject VALUE SLOTS applications declare, `exact_i64` and `source_quote`
# against literal tokens counted from the SOURCE TEXT by a scanner that has
# never heard of the graph. A denominator taken from the producer would agree
# with itself at 100% while reaching nothing, which is the exact failure this
# gate is built to catch.
# ---------------------------------------------------------------------------

cat > "$work/row.jq" <<'JQ'
# NULL-SAFE BY CONSTRUCTION. The export is versioned and a reader pointed at an
# older one sees a MISSING key, not a card. `.[$n].card` on an absent key is
# `null`, and `null != "unknown"` is TRUE — so a naive census counts every
# application as carrying a card the export never wrote. MEASURED: that scored
# `foreign` at 4946/4946 = 100% against a v8 export that has no `foreign` key at
# all. Absence is its own answer and gets its own column.
def card($n): [.applications[] | (.[$n].card? // "absent")]
  | map(select(. != "unknown" and . != "absent")) | length;
def absent($n): [.applications[] | select(has($n) | not)] | length;
[ (.applications|length)
, (.fact_coverage.candidates)
, (.fact_coverage.published)
, (.fact_coverage.blocking)
, (.fact_coverage.bootstrap)
, card("applied"), card("effect"), card("authority")
, card("witness"), card("target"), card("realization"), card("foreign")
, ([.applications[] | (.arguments|length) + (if has("subject") then 1 else 0 end)] | add // 0)
, (.origins|length)
, (.draws|length)
, ([.draws[] | select(.world.card != "unknown")] | length)
, (.worlds|length)
, (.bodies|length)
, ([.bodies[] | (.places|length)] | add // 0)
, ([.bodies[] | (.regions|length)] | add // 0)
, (.places|length)
, (.aggregates|length)
, (.exact_i64|length)
, (.source_quote|length)
, ([.nodes[]|select(.kind=="func")]|length)
, ([.nodes[]|select(.kind=="value")]|length)
, ([.nodes[]|select(.kind=="local")]|length)
, (.table_shapes|length)
, (.nodes|length)
, (.edges|length)
, ([.bodies[] | select((.regions|length) > 0)] | length)
, ([.applications[] | select(.demand == "discard")] | length)
, ([.applications[] | select(.demand == "unknown")] | length)
, ([.applications[] | (.result_demands? // []) | length] | add // 0)
, ([.applications[] | (.result_demands? // [])[] | select(. == "discard")] | length)
, absent("applied"), absent("effect"), absent("authority"), absent("witness")
, absent("target"), absent("realization"), absent("foreign")
, ([.bodies[] | .regions[] | select(.shape == "refinement" or .shape == "alternative")] | length)
, ([.bodies[] | .regions[] | select(.shape == "refinement" or .shape == "alternative")
    | select(.refinement.subject.site? != "unknown")] | length)
, ([.bodies[] | .regions[] | select(.shape == "recurrence" or .shape == "iteration")] | length)
, ([.bodies[] | .regions[] | select(.shape == "recurrence" or .shape == "iteration")
    | select((.carried | length) > 0)] | length)
, ([.bodies[] | .regions[] | select(.shape == "exit")] | length)
] | @tsv
JQ

# The independent denominators. This scanner reads SOURCE TEXT, strips `#`
# comments, and counts the two literal families by delimiter. It is crude on
# purpose: it shares no code, no lift and no assumption with the producer, so
# when it disagrees with the graph the disagreement is information.
cat > "$work/lex.awk" <<'AWK'
# ONE PASS, STRING STATE FIRST. The previous version ran
# `sub(/#.*$/, "", line)` BEFORE recognising strings, so a `#` inside a
# string literal truncated the line. MEASURED: `s = "tag#1"` counted 0
# quoted strings instead of 1, and `y = f("a#b", 42)` counted 0 integers
# instead of 1 — the denominator silently lost the string AND every token
# after it on that line. `#` opens a comment only OUTSIDE a string, so
# string state must be tracked before the comment is cut, not after.
# WHAT THIS RATIO IS, AND IS NOT. Two limits survive the scanner repair
# below and neither is fixable here, so do not quote `exact_i64` reach as
# corpus coverage:
#
#   THE DENOMINATOR ONLY COUNTS FILES THAT LIFT. This scanner runs inside
#   the `if "$idol" graph "$src" && jq ...` block, so a refused file
#   contributes to NEITHER side. The ratio is "of literals in files that
#   already lift", not "of literals in the corpus". At the time of writing
#   4655 application candidates are BLOCKING, and none of their files are
#   in this denominator.
#
#   THE TWO SIDES COUNT DIFFERENT POPULATIONS. The numerator is
#   `.exact_i64|length` from the graph export, which may include DERIVED
#   exact values; the denominator counts literal TOKENS in source. A
#   producer that publishes an exact value for a computed result raises the
#   numerator against a denominator that never had a token for it.
#
# The honest decomposition is four separate measurements — literal
# occurrence coverage, derived exact-value coverage, consumer reach, and
# transformation enablement — and this row is only the first, bounded to
# lifted files.
BEGIN { sq = sprintf("%c", 39) }   # a single quote, without shell-quoting hazards
{
  n = split($0, ch, "")
  i = 1; instr = 0; inby = 0; q = 0; b = 0; t = ""
  while (i <= n) {
    c = ch[i]
    if (c == "\\" && (instr || inby)) { i += 2; continue }
    if (!instr && !inby && c == "#") break
    if (!inby && c == "\"") { instr = !instr; if (!instr) q++; i++; continue }
    if (!instr && c == sq) { inby = !inby; if (!inby) b++; i++; continue }
    if (!instr && !inby) t = t c
    i++
  }
  quoted += q + b
  m = split(t, tok, /[^0-9A-Za-z_.]+/)
  for (j = 1; j <= m; j++) if (tok[j] ~ /^[0-9]+$/) ints++
}
END { printf "%d\t%d\n", quoted + 0, ints + 0 }
AWK

files=0
lifted=0
refused=0
: > "$work/rows"
: > "$work/lex"
for root in $corpus; do
  [ -d "$root" ] || continue
  find "$root" -name '*.id' -type f 2>/dev/null
done | sort > "$work/corpus"

while IFS= read -r src; do
  files=$((files + 1))
  if "$idol" graph "$src" > "$work/g.json" 2>/dev/null && [ -s "$work/g.json" ]; then
    if jq -r -f "$work/row.jq" "$work/g.json" >> "$work/rows" 2>/dev/null; then
      lifted=$((lifted + 1))
      awk -f "$work/lex.awk" "$src" >> "$work/lex"
    else
      refused=$((refused + 1))
    fi
  else
    refused=$((refused + 1))
  fi
done < "$work/corpus"

sum() { awk -v c="$1" -F'\t' '{t += $c} END {print t + 0}' "$2"; }

apps=$(sum 1 "$work/rows");        cand=$(sum 2 "$work/rows")
appub=$(sum 3 "$work/rows");       ablock=$(sum 4 "$work/rows")
aboot=$(sum 5 "$work/rows")
c_applied=$(sum 6 "$work/rows");   c_effect=$(sum 7 "$work/rows")
c_auth=$(sum 8 "$work/rows");      c_witness=$(sum 9 "$work/rows")
c_target=$(sum 10 "$work/rows");   c_real=$(sum 11 "$work/rows")
c_foreign=$(sum 12 "$work/rows")
slots=$(sum 13 "$work/rows");      origins=$(sum 14 "$work/rows")
draws=$(sum 15 "$work/rows");      draws_known=$(sum 16 "$work/rows")
worlds=$(sum 17 "$work/rows");     bodies=$(sum 18 "$work/rows")
bplaces=$(sum 19 "$work/rows");    bregions=$(sum 20 "$work/rows")
places=$(sum 21 "$work/rows");     aggs=$(sum 22 "$work/rows")
exact=$(sum 23 "$work/rows");      quote=$(sum 24 "$work/rows")
funcs=$(sum 25 "$work/rows");      values=$(sum 26 "$work/rows")
locals=$(sum 27 "$work/rows");     tables=$(sum 28 "$work/rows")
nodes=$(sum 29 "$work/rows");      edges=$(sum 30 "$work/rows")
bwithreg=$(sum 31 "$work/rows");   discard=$(sum 32 "$work/rows")
unkdemand=$(sum 33 "$work/rows");  rdemands=$(sum 34 "$work/rows")
rdiscard=$(sum 35 "$work/rows")
a_applied=$(sum 36 "$work/rows");  a_effect=$(sum 37 "$work/rows")
a_auth=$(sum 38 "$work/rows");     a_witness=$(sum 39 "$work/rows")
a_target=$(sum 40 "$work/rows");   a_real=$(sum 41 "$work/rows")
a_foreign=$(sum 42 "$work/rows")
refine=$(sum 43 "$work/rows");     refinesub=$(sum 44 "$work/rows")
recur=$(sum 45 "$work/rows");      recurcar=$(sum 46 "$work/rows")
exits=$(sum 47 "$work/rows")
lexquote=$(sum 1 "$work/lex");     lexint=$(sum 2 "$work/lex")

pct() {
  awk -v n="$1" -v d="$2" 'BEGIN { if (d + 0 == 0) printf "n/a"; else printf "%.1f%%", 100 * n / d }'
}

echo "gate/coverage.sh: corpus $files file(s) under [$corpus]; $lifted lifted, $refused refused"
echo
echo "== COVERAGE BY CONSTRUCTION (published / eligible) =="
printf '%-22s %10s %10s %8s %8s  %s\n' family published eligible reach absent denominator
printf '%-22s %10s %10s %8s %8s  %s\n' application "$appub" "$cand" "$(pct "$appub" "$cand")" "-" "application candidates in graph"
printf '%-22s %10s %10s %8s %8s  %s\n' " .applied" "$c_applied" "$apps" "$(pct "$c_applied" "$apps")" "$a_applied" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .effect" "$c_effect" "$apps" "$(pct "$c_effect" "$apps")" "$a_effect" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .authority" "$c_auth" "$apps" "$(pct "$c_auth" "$apps")" "$a_auth" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .witness" "$c_witness" "$apps" "$(pct "$c_witness" "$apps")" "$a_witness" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .target" "$c_target" "$apps" "$(pct "$c_target" "$apps")" "$a_target" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .realization" "$c_real" "$apps" "$(pct "$c_real" "$apps")" "$a_real" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' " .foreign" "$c_foreign" "$apps" "$(pct "$c_foreign" "$apps")" "$a_foreign" "published applications"
printf '%-22s %10s %10s %8s %8s  %s\n' draw "$draws_known" "$draws" "$(pct "$draws_known" "$draws")" "-" "draw rows published"
printf '%-22s %10s %10s %8s  %s\n' origin "$origins" "$slots" "$(pct "$origins" "$slots")" "operand+subject value slots"
printf '%-22s %10s %10s %8s  %s\n' exacti64 "$exact" "$lexint" "$(pct "$exact" "$lexint")" "integer literal tokens in source"
printf '%-22s %10s %10s %8s  %s\n' sourcequote "$quote" "$lexquote" "$(pct "$quote" "$lexquote")" "quoted literal tokens in source"
printf '%-22s %10s %10s %8s  %s\n' body "$bodies" "$funcs" "$(pct "$bodies" "$funcs")" "func entities"
printf '%-22s %10s %10s %8s  %s\n' " place(relation)" "$bplaces" "$locals" "$(pct "$bplaces" "$locals")" "local entities"
printf '%-22s %10s %10s %8s  %s\n' " region" "$bwithreg" "$bodies" "$(pct "$bwithreg" "$bodies")" "relation bodies with any region"
printf '%-22s %10s %10s %8s  %s\n' " refinement.subject" "$refinesub" "$refine" "$(pct "$refinesub" "$refine")" "refinement+alternative regions"
printf '%-22s %10s %10s %8s  %s\n' " recurrence.carried" "$recurcar" "$recur" "$(pct "$recurcar" "$recur")" "recurrence+iteration regions"
printf '%-22s %10s %10s %8s  %s\n' place "$places" "$funcs" "$(pct "$places" "$funcs")" "func entities (module census)"
printf '%-22s %10s %10s %8s  %s\n' world "$worlds" "$lifted" "$(pct "$worlds" "$lifted")" "modules lifted (rows per module, not a fraction)"
printf '%-22s %10s %10s %8s  %s\n' aggregate "$aggs" "$tables" "$(pct "$aggs" "$tables")" "table shape entities"
echo
printf 'gate/coverage.sh: refusal census: %s candidate(s), %s published, %s bootstrap, %s BLOCKING\n' \
  "$cand" "$appub" "$aboot" "$ablock"
printf 'gate/coverage.sh: graph size: %s node(s), %s edge(s), %s value entit(ies)\n' \
  "$nodes" "$edges" "$values"
printf 'gate/coverage.sh: application demand: %s discard, %s unknown, of %s published\n' \
  "$discard" "$unkdemand" "$apps"
printf 'gate/coverage.sh: result-pack member demand: %s discard of %s member(s)\n' \
  "$rdiscard" "$rdemands"
printf 'gate/coverage.sh: region shapes: %s refinement/alternative, %s recurrence/iteration, %s exit\n' \
  "$refine" "$recur" "$exits"

# ---------------------------------------------------------------------------
# 2. CONSUMER CENSUS.
#
# A family's public reader, counted at every call site OUTSIDE the file that
# owns the producer. `consumer-zero` is a DIFFERENT finding from `zero
# coverage` and takes the OPPOSITE repair: a fact at full coverage read by
# nobody is not a producer bug, and connecting one to a transformation that
# already exists was the 186x win.
#
# The third column is the trap this gate was built after. `SourceQuoteFact` had
# a public accessor AND a JSON column, and the JSON column is what made it look
# consumed: `writeJson` reads every family by construction, so a family whose
# ONLY reader is its own serializer reads as "has a consumer" to every census
# that greps for the accessor name. JSON-ONLY is therefore counted separately
# and never counted as a consumer.
# ---------------------------------------------------------------------------
echo
echo "== CONSUMERS (call sites outside src/semantic_graph.zig) =="

# Lines of `semantic_graph.zig` that belong to a `*Json` projection function,
# by brace depth from the `fn ...Json(` header. Everything here is SERIALIZATION,
# never a consumer.
awk '
  /fn [A-Za-z]*Json\(/ { injson = 1; depth = 0 }
  injson {
    print
    n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
    depth += n - m
    if (depth <= 0 && /\}/) injson = 0
  }
' src/semantic_graph.zig > "$work/jsonregion"

printf '%-22s %7s %7s %8s  %s\n' family external 'in-file' json readers

consumers() {
  fam=$1; shift
  pat=$(printf '%s\\(' "$1"); shift
  for r in "$@"; do pat="$pat|$(printf '%s\\(' "$r")"; done
  hits=$(grep -rnE "\.($pat)" src --include='*.zig' 2>/dev/null | grep -v '^src/semantic_graph.zig:' || true)
  n=$(printf '%s' "$hits" | grep -c . || true)
  own=$(grep -cE "\.($pat)" src/semantic_graph.zig 2>/dev/null || true)
  js=$(grep -cE "\.($pat)" "$work/jsonregion" 2>/dev/null || true)
  who=$(printf '%s' "$hits" | cut -d: -f1 | sed 's|^src/||;s|\.zig$||' | sort -u | tr '\n' ' ')
  if [ -z "$who" ]; then
    if [ "$js" -gt 0 ]; then who='-- CONSUMER-ZERO (JSON-ONLY) --'; else who='-- CONSUMER-ZERO --'; fi
  fi
  printf '%-22s %7s %7s %8s  %s\n' "$fam" "$n" "$own" "$js" "$who"
}

consumers application application applications applicationRelation applicationSubject
consumers applicationstage applicationStage
consumers applicationdemand applicationDemand
consumers applicationdescriptor applicationDescriptor
consumers applicationapplied applicationApplied
consumers pack pack packMembers packEffect packWorld
consumers packmemberdemand packMemberDemands
consumers packadjustment packAdjustment
consumers aggregate aggregate aggregateMembers aggregateAt aggregatePlace aggregateAccess aggregateProducer boundAggregateAtPlace
consumers aggregateorigin aggregateOrigin
consumers exacti64 exactI64
# The accessors actually in use are `sourceQuoteValue(` and
# `sourceQuoteOfExpr(`. Naming only `sourceQuote` built the pattern
# `\.sourceQuote\(`, whose trailing paren excludes both by construction -- so
# this gate reported CONSUMER-ZERO for a family `dnir_lower.zig:637` reads at
# HEAD. An instrument that names its subject by a prefix and anchors on `(`
# finds only the accessor whose name is exactly the prefix.
consumers sourcequote sourceQuote sourceQuoteOfExpr sourceQuoteValue
consumers origin valueOrigin
consumers draw applicationWorld
consumers world worldMembers
consumers body bodyOf
consumers place placeNamed placeCount
consumers descriptorhome descriptorHomes tableDescriptorHomes enumDescriptorHomes
consumers entityof entityOf
consumers factcoverage factCoverage

# The region census is a whole FAMILY with no accessor of its own: `bodyOf`
# hands back a `Body` and the reader reaches `.regions` directly. Counted by
# the field, for the same reason.
regionhits=$(grep -rnE 'region\.Census|region\.Refinement|region\.analyzeFunction|body\.regions|\)\.regions\b' src --include='*.zig' 2>/dev/null \
  | grep -vE '^src/(region|region_graph|semantic_graph)\.zig:' || true)
regionwho=$(printf '%s' "$regionhits" | cut -d: -f1 | sed 's|^src/||;s|\.zig$||' | sort -u | tr '\n' ' ')
[ -n "$regionwho" ] || regionwho='-- CONSUMER-ZERO --'
printf '%-22s %7s %7s %8s  %s\n' region \
  "$(printf '%s' "$regionhits" | grep -c . || true)" \
  "$(grep -cE '\.regions\b|region\.Census' src/semantic_graph.zig || true)" \
  "$(grep -cE '\.regions\b|region\.Census' "$work/jsonregion" || true)" \
  "$regionwho"

# ---------------------------------------------------------------------------
# 2b. WRITERS — the UNPRODUCED column.
#
# The third failure mode. A fact family can have a type, a store, a public
# reader, a JSON column, a test AND full serialization while NO PRODUCTION SITE
# EVER WRITES IT. Downstream that is indistinguishable from producer-hollow and
# from consumer-zero, and the repair is different again: there is nothing to
# connect and nothing to widen, something has to compute it for the first time.
#
# `writers` counts assignment sites. `production` excludes every site at or
# after the first `test "` header in the owning file, because a fact written
# only by its own test is unproduced in every program the compiler compiles.
# ---------------------------------------------------------------------------
echo
echo "== WRITERS (0 production writers == UNPRODUCED, not hollow, not unread) =="
printf '%-30s %8s %11s  %s\n' field writers production state

# `semantic_graph.zig` INTERLEAVES tests with code from line 104 onward, so
# "everything after the first `test` header" excludes the whole file. Test
# bodies are excised by BRACE DEPTH from each `test "` header instead, and what
# remains is production. Measured: the naive first-header rule reported
# `ApplicationFact.effect` unproduced while the coverage pass measured it at
# 70.9%, and the coverage pass was right.
awk '
  /^test "/ { intest = 1; depth = 0 }
  intest {
    n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
    depth += n - m
    if (depth <= 0 && /\}/) intest = 0
    next
  }
  { print FILENAME ":" FNR ":" $0 }
' src/semantic_graph.zig > "$work/production"

writers() {
  field=$1; pat=$2
  # A `pub fn` HEADER is not a writer. Counting the setter's own declaration
  # scored `PackFact.realization` as produced when every call to it is a test.
  all=$(grep -rnE "$pat" src --include='*.zig' 2>/dev/null | grep -v 'pub fn ' || true)
  n=$(printf '%s' "$all" | grep -c . || true)
  outside=$(printf '%s' "$all" | grep -v '^src/semantic_graph.zig:' \
    | grep -vE 'std\.testing|expectEqual' | grep -c . || true)
  inside=$(grep -E "$pat" "$work/production" 2>/dev/null | grep -vc 'pub fn ' || true)
  prod=$((outside + inside))
  state=unproduced
  [ "$prod" -gt 0 ] && state=produced
  printf '%-30s %8s %11s  %s\n' "$field" "$n" "$prod" "$state"
}

writers 'ApplicationFact.applied'      '\.applied = '
writers 'ApplicationFact.effect'       'fact\.effect = |\.effect = \.'
writers 'ApplicationFact.authority'    'application_facts\.items\[[a-z_]*\]\.authority = |fact\.authority = '
writers 'ApplicationFact.witness'      'application_facts\.items\[[a-z_]*\]\.witness = |fact\.witness = '
writers 'ApplicationFact.target'       'application_facts\.items\[[a-z_]*\]\.target = |fact\.target = '
writers 'ApplicationFact.realization'  'application_facts\.items\[[a-z_]*\]\.realization = '
writers 'ApplicationFact.foreign'      'application_facts\.items\[[a-z_]*\]\.foreign = |\.foreign = foreign'
writers 'PackFact.realization'         'pack_facts\.items\[[a-z_]*\]\.realization = |selectPackRealization\('
writers 'PackMember.demand=.discard'   '\.demand = \.discard|=> \.discard'
writers 'AggregateFact.contents=.yes'  'contents_known = \.yes|\.contents_known = \.'

# ---------------------------------------------------------------------------
# 3. RIVAL AUTHORITIES.
#
# Every site that reconstructs an answer the graph already owns, from AST
# shape, from a name, or from spelling. This is the column that ranks by
# DAMAGE: GAP-204, GAP-207, GAP-208 and GAP-209 are all one shape — a
# reconstruction that models a narrower program than the language admits,
# consulted by a caller with no way to know the walk did not cover its case.
# ---------------------------------------------------------------------------
echo
echo "== RIVAL AUTHORITIES (a second producer for a fact the graph owns) =="
printf '%-26s %6s  %-34s %s\n' fact sites owner rival

rival() {
  printf '%-26s %6s  %-34s %s\n' "$1" \
    "$(grep -rnE "$3" src --include='*.zig' 2>/dev/null | grep -vE '^src/(semantic_graph|place|region|demand)\.zig:' | grep -c . || true)" \
    "$2" "$4"
}

rival exact.i64            'graph.exactI64'      'intLiteralStep|literalIntValue|intLiteralOf'   'AST integer re-parse'
rival source.quote         'graph.sourceQuote'   'exprIsStr\(|quotedLiteralIsByteSequence'       'AST quote re-classification'
rival module.binding.value 'graph binding entity' 'collectModuleConsts|ModuleConsts|moduleConstValue' 'top-level AST walk (GAP-209)'
rival module.binding.store 'graph binding entity' 'collectModuleGlobals|ModuleGlobals'           'top-level AST walk (GAP-209)'
rival aggregate.contents   'graph.aggregate'     'const_table\.|constTableOf|table_facts\.'      'name-keyed side table'
rival application.descr    'graph.applicationDescriptor' 'exprIsIntegral|exprIsFloat|exprIsRecord' 'AST descriptor guess (GAP-207)'
rival relation.identity    'graph binding edge'  'std\.mem\.eql\(u8, *name'                      'spelling comparison'
rival home.identity        'graph.foreignHome'   'std\.mem\.eql\(u8, *home'                      'spelling comparison'
rival result.demand        'graph.applicationDemand'  'consumption == \.discard|consumption: types\.ReturnConsumption'  'AST statement position'
rival loop.carried         'region carried census'    'readMachine\(|polyOfExpr\('                                     'AST loop-slot rediscovery'
rival refinement.domain    'region refinement census' 'lowerIf\(|lowerCond|\.if_stmt =>|\.while_loop =>'               'AST branch walk'

# ---------------------------------------------------------------------------
# 4. POSITIVE CONTROLS.
#
# EVERY ZERO THIS GATE REPORTS MUST BE A ZERO THE INSTRUMENT COULD HAVE MOVED.
# Three controls, each written to force a family the corpus reads at ~0:
#
#   ordinary.id   the shape real source is written in — named bindings, a
#                 record literal, a refinement, text and byte literals.
#   operand.id    the same literals moved into APPLICATION OPERAND position,
#                 which is the only position `addApplicationValue` visits.
#   aggregate.id  a positional table and a constant index key, the only two
#                 positions `publishExactI64` is called from.
#
# A family reading 0 on ALL THREE is an instrument fault and this gate says so.
# A family that reads 0 on `ordinary.id` and nonzero on one of the other two is
# a PRODUCER-HOLLOW finding: the fact is real, the producer's reach is not.
# ---------------------------------------------------------------------------
echo
echo "== POSITIVE CONTROLS (proving each zero is a finding, not a dead instrument) =="

cat > "$work/ordinary.id" <<'CONTROL'
pt: { x: i64, y: i64 }

ring: i64 = 2147483647

add: i64 = (a: i64, b: i64)
    a + b

pick: i64 = (p: pt)
    if p.x > 3
        return p.x
    p.y

main: i64 = ()
    tag = "alpha"
    raw = 'abc'
    n = 8
    q: pt = { x = 1, y = 2 }
    stdout:write(tag)
    print(add(n, ring))
    print(pick(q))
    print(raw:len())
    0
CONTROL

cat > "$work/operand.id" <<'CONTROL'
emit: i64 = (t: str)
    t:len()

add: i64 = (a: i64, b: i64)
    a + b

main: i64 = ()
    print(add(8, 34))
    print(emit("alpha"))
    print(emit('abc'))
    0
CONTROL

cat > "$work/aggregate.id" <<'CONTROL'
sum: i64 = (a: i64)
    a

main: i64 = ()
    xs = { 3, 5, 8 }
    n = xs[1]
    print(sum(n))
    0
CONTROL

: > "$work/controls"
for c in ordinary operand aggregate; do
  if "$idol" graph "$work/$c.id" > "$work/$c.json" 2>"$work/$c.err"; then
    jq -r -f "$work/row.jq" "$work/$c.json" >> "$work/controls"
  else
    echo "control $c: the compiler REFUSED it — the instrument is unproven for this row" >&2
    printf '%s\n' "$(sed -n 1p "$work/$c.err")" >&2
    printf '0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n' >> "$work/controls"
  fi
done

ctl() { sed -n "$2p" "$work/controls" | cut -f"$1"; }
# The corpus total is the fourth witness. A family at 0 on all three controls
# but nonzero over 716 real modules is an under-specified CONTROL, not a dead
# instrument, and the gate must not report the two the same way.
verdict() {
  awk -v a="$1" -v b="$2" -v c="$3" -v k="$4" 'BEGIN {
    if (a + 0 > 0) { print "reached on ordinary source"; exit }
    if (b + 0 > 0 || c + 0 > 0) { print "PRODUCER-HOLLOW (needs a special position)"; exit }
    if (k + 0 > 0) { print "control under-specified; corpus " k; exit }
    print "UNPRODUCED (nothing anywhere writes it)"
  }'
}
printf '%-20s %9s %9s %11s  %s\n' family ordinary operand aggregate verdict
row() {
  a=$(ctl "$2" 1); b=$(ctl "$2" 2); c=$(ctl "$2" 3)
  printf '%-20s %9s %9s %11s  %s\n' "$1" "$a" "$b" "$c" "$(verdict "$a" "$b" "$c" "$3")"
}
row applications 1 "$apps"
row 'applied card' 6 "$c_applied"
row 'effect card' 7 "$c_effect"
row 'authority card' 8 "$c_auth"
row 'witness card' 9 "$c_witness"
row 'target card' 10 "$c_target"
row 'realization card' 11 "$c_real"
row 'foreign card' 12 "$c_foreign"
row origins 14 "$origins"
row draws 16 "$draws_known"
row worlds 17 "$worlds"
row bodies 18 "$bodies"
row 'relation places' 19 "$bplaces"
row regions 20 "$bregions"
row 'module places' 21 "$places"
row aggregates 22 "$aggs"
row exact_i64 23 "$exact"
row source_quote 24 "$quote"

# ---------------------------------------------------------------------------
# 5. BUDGET.
#
# A gate shipped red is skipped on day one — `build.zig` records `audit100` and
# `capability-scan` as exactly that. So this ratchets a MEASURED budget, not a
# zero. `COVERAGE_BUDGET` is the maximum number of application candidates the
# corpus may leave BLOCKING; unset, the gate reports and exits 0.
# ---------------------------------------------------------------------------
echo
if [ -n "$budget" ]; then
  printf 'gate/coverage.sh: blocking budget %s, measured %s\n' "$budget" "$ablock"
  if [ "$ablock" -gt "$budget" ]; then
    printf 'gate/coverage.sh: OVER BUDGET\n'
    exit 1
  fi
fi
printf 'gate/coverage.sh: reporting only (set COVERAGE_BUDGET to ratchet)\n'
exit 0
