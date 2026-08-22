#!/bin/sh
# gate/corpus-status.sh — .id teaching-status census, derived and verified.
#
#   sh gate/corpus-status.sh
#
# law.md §115 + docs/source-corpus-classification.md: every tracked .id file
# has a teaching status. The DEFAULT is DERIVED from the executed corpus
# manifest in docs/spec/corpus.md (one classification authority — SOURCE-
# INFER-ONE: a per-file header restating the derived status is debt). A
# `## TEACHING-STATUS:` header in the first four lines is an OVERRIDE for
# files whose finer fact disagrees with the directory rule, and its status
# word must be one of the six.
#
# Derivation map: canonical->canonical, compatibility->compat,
# foreign->foreign, generated->scenery, negative->fixture.
#
# Exit code = unclassified files (no header, no manifest rule) + invalid
# header status words. A zero means every tracked .id file carries a lawful
# teaching status. Totals print with the distribution.
# Tier 1: per-file header override. Tier 2: the ingress manifest
# (docs/spec/corpus.md — source-law authority). Tier 3: the teaching-status
# prefix defaults in docs/source-corpus-classification.md (no ingress
# semantics). Exit = unclassified + invalid.
# THE REPO IS THE SUBJECT, so resolve it from this file rather than from the
# ambient working directory. Every relative path below -- and `git ls-files` --
# used to read whatever tree the caller happened to be standing in; from
# anywhere else this gate exited 2 with "missing docs/spec/corpus.md", which is
# indistinguishable from a repo that has lost its manifest. Same class as the
# git_preservation test, which shells out with no .cwd set.
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2

MANIFEST=docs/spec/corpus.md
DEFAULTS=docs/source-corpus-classification.md
[ -f "$MANIFEST" ] || { printf 'corpus-status gate: FAIL — missing %s\n' "$MANIFEST"; exit 2; }
[ -f "$DEFAULTS" ] || { printf 'corpus-status gate: FAIL — missing %s\n' "$DEFAULTS"; exit 2; }

RULES=$(mktemp -t idol-corpus-rules)
DEFS=$(mktemp -t idol-corpus-defs)
FILES=$(mktemp -t idol-corpus-files)
trap 'rm -f "$RULES" "$DEFS" "$FILES"' EXIT
# The manifest's fenced projection block: `class<spaces>prefix`, first match wins.
awk '/^```text$/ { inb = !inb; next } inb && /[[:space:]]/ {
  cls = $1; sub(/^[[:space:]]*/, "", $0); prefix = $2
  if (prefix != "") print cls " " prefix
}' "$MANIFEST" >"$RULES"
[ -s "$RULES" ] || { printf 'corpus-status gate: FAIL — manifest yielded 0 rules\n'; exit 2; }

# The derived-defaults block under "## Derived defaults" only: `status<spaces>prefix`.
awk '/^## Derived defaults/ { ind = 1; next } /^## / { ind = 0 }
     ind && /^```text$/ { inb = !inb; next }
     inb && /^[a-z]/ { print $1 " " $2 }' "$DEFAULTS" >"$DEFS"
[ -s "$DEFS" ] || { printf 'corpus-status gate: FAIL — derived defaults yielded 0 rules\n'; exit 2; }

git ls-files -- '*.id' | sort >"$FILES"
total=$(wc -l <"$FILES" | tr -d ' ')
[ "$total" -gt 0 ] || { printf 'corpus-status gate: FAIL — no tracked .id files\n'; exit 2; }

derive() {
  # $1 = table file, $2 = path; prints the matched first field or nothing
  while read -r cls prefix; do
    case $2 in
      "$prefix"|"$prefix"*) printf '%s' "$cls"; return ;;
    esac
  done <"$1"
}

map() {
  case $1 in
    canonical) printf canonical ;;
    compatibility) printf compat ;;
    foreign) printf foreign ;;
    generated) printf scenery ;;
    negative) printf fixture ;;
    *) printf '' ;;
  esac
}

valid_status() {
  case $1 in
    canonical|compat|fixture|foreign|migration|scenery) return 0 ;;
    *) return 1 ;;
  esac
}

unclassified=0
invalid=0
overrides=0
derived_counts=""

while IFS= read -r f; do
  header=$(head -n 4 "$f" | sed -n 's/^## TEACHING-STATUS:[[:space:]]*\([a-z]*\).*/\1/p' | head -n 1)
  if [ -n "$header" ]; then
    if valid_status "$header"; then
      overrides=$((overrides + 1))
      derived_counts="$derived_counts$header\n"
    else
      printf '  FAIL %s: invalid TEACHING-STATUS [%s]\n' "$f" "$header"
      invalid=$((invalid + 1))
    fi
    continue
  fi
  cls=$(derive "$RULES" "$f")
  if [ -n "$cls" ]; then
    st=$(map "$cls")
    if [ -z "$st" ]; then
      printf '  FAIL %s: manifest class [%s] has no status mapping\n' "$f" "$cls"
      unclassified=$((unclassified + 1))
      continue
    fi
    derived_counts="$derived_counts$st\n"
    continue
  fi
  st=$(derive "$DEFS" "$f")
  if [ -n "$st" ]; then
    if valid_status "$st"; then
      derived_counts="$derived_counts$st\n"
    else
      printf '  FAIL %s: derived default [%s] is not a status\n' "$f" "$st"
      invalid=$((invalid + 1))
    fi
    continue
  fi
  printf '  FAIL %s: no header, no manifest rule, no derived default\n' "$f"
  unclassified=$((unclassified + 1))
done <"$FILES"

printf 'corpus-status gate: %s tracked .id files, %s override headers, %s unclassified, %s invalid\n' \
  "$total" "$overrides" "$unclassified" "$invalid"
printf '%b' "$derived_counts" | sort | uniq -c | sed 's/^/  /'

exit $((unclassified + invalid))
