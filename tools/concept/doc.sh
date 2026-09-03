#!/bin/sh
# tools/concept/doc.sh — generated-docs projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and `idol explain`
# projects it as `.concept` so a reader consumes it without parsing the full
# graph JSON. This file is the generated-docs reader: it renders the produced
# verdict as a markdown concept record and holds it against the graph export's
# own `concepts[]`/`refusals[]`. It owns no derivation: every row it reads was
# produced on the graph and re-verified on export before this file saw it; the
# render refuses rather than invents when the two faces disagree.
#
# WHAT IS MEASURED. One subject file, compiled twice through the checked lift:
# `idol explain` (the docs face) and `idol graph` (the export face). The doc
# renders REFUSED exactly when the export carries a refusal for the same
# module with the same reason and split, and HELD otherwise. A produced row
# whose faces disagree is damage, not a verdict.
#
# Usage:
#   tools/concept/doc.sh <file.id>        render the concept record on stdout
#
# Exit: 0 rendered; 1 the verdict could not be rendered (damage or mismatch);
# 3 not measured (no compiler or no jq).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
IDOL=${IDOL:-"$root/zig-out/bin/idol"}

[ $# -eq 1 ] || { printf 'doc: FAIL — one subject file is required\n' >&2; exit 1; }
src=$1
[ -r "$src" ] || { printf 'doc: FAIL — subject unreadable: %s\n' "$src" >&2; exit 1; }

if [ ! -x "$IDOL" ]; then
  printf 'doc: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
  exit 3
fi

command -v jq >/dev/null 2>&1 || {
  printf 'doc: NOT MEASURED — jq is required to read the produced verdict\n' >&2
  exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptdoc.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

if ! "$IDOL" explain "$src" >"$work/explain.json" 2>"$work/explain.log"; then
  printf 'doc: FAIL — explain did not render: %s\n' "$src" >&2
  tail -3 "$work/explain.log" | sed 's/^/doc:   /' >&2
  exit 1
fi
if ! "$IDOL" graph "$src" >"$work/graph.json" 2>"$work/graph.log"; then
  printf 'doc: FAIL — graph did not render: %s\n' "$src" >&2
  tail -3 "$work/graph.log" | sed 's/^/doc:   /' >&2
  exit 1
fi

# The docs face must carry the produced verdict, or there is nothing to render.
jq -e '.concept | type == "object"' <"$work/explain.json" >/dev/null 2>&1 || {
  printf 'doc: FAIL — explain carries no produced concept verdict: %s\n' "$src" >&2
  exit 1
}

# Agreement: the docs face and the export face answer the same finding.
# Identities compare whole; refusals compare the produced triple
# (module, reason, split) — the docs face additionally names the home.
exp_concepts=$(jq -c '.concept.concepts' <"$work/explain.json" 2>/dev/null) || exp_concepts=""
got_concepts=$(jq -c '.concepts' <"$work/graph.json" 2>/dev/null) || got_concepts=""
[ -n "$exp_concepts" ] && [ "$exp_concepts" = "$got_concepts" ] || {
  printf 'doc: FAIL — docs identity disagrees with the graph export: %s\n' "$src" >&2
  exit 1
}
exp_ref=$(jq -c '[.concept.refusals[] | {module, reason, split}]' <"$work/explain.json" 2>/dev/null) || exp_ref=""
got_ref=$(jq -c '[.refusals[] | {module, reason, split}]' <"$work/graph.json" 2>/dev/null) || got_ref=""
[ -n "$exp_ref" ] && [ "$exp_ref" = "$got_ref" ] || {
  printf 'doc: FAIL — docs refusal disagrees with the graph export: %s\n' "$src" >&2
  exit 1
}

# The produced identity must read as an identity: a named home with counts.
jq -e '.concept.concepts | length >= 1' <"$work/explain.json" >/dev/null 2>&1 || {
  printf 'doc: FAIL — produced identity unreadable: %s\n' "$src" >&2
  exit 1
}
jq -e '.concept.concepts[0] | .home | type == "string"' <"$work/explain.json" >/dev/null 2>&1 || {
  printf 'doc: FAIL — produced home unreadable: %s\n' "$src" >&2
  exit 1
}
jq -e '.concept.concepts[0] | .relations | type == "number"' <"$work/explain.json" >/dev/null 2>&1 || {
  printf 'doc: FAIL — produced composition unreadable: %s\n' "$src" >&2
  exit 1
}
jq -e '.concept.refusals | type == "array"' <"$work/explain.json" >/dev/null 2>&1 || {
  printf 'doc: FAIL — produced refusals unreadable: %s\n' "$src" >&2
  exit 1
}

home=$(jq -r '.concept.concepts[0].home' <"$work/explain.json")
relations=$(jq -r '.concept.concepts[0].relations' <"$work/explain.json")
shapes=$(jq -r '.concept.concepts[0].shapes' <"$work/explain.json")
applications=$(jq -r '.concept.concepts[0].applications' <"$work/explain.json")
demand=$(jq -r '.concept.concepts[0].shared_demand' <"$work/explain.json")

printf '# Concept record — %s\n' "$home"
printf 'source: %s\n' "$src"
printf 'identity: relations=%s shapes=%s applications=%s shared_demand=%s\n' \
  "$relations" "$shapes" "$applications" "$demand"
nref=$(jq -r '.concept.refusals | length' <"$work/explain.json")
if [ "$nref" = "0" ]; then
  printf 'verdict: HELD one concept\n'
else
  jq -r '.concept.refusals[] | "verdict: REFUSED \(.reason) split=\(.split | map(tostring) | join(","))"' \
    <"$work/explain.json"
fi
