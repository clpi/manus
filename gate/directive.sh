#!/usr/bin/env sh
# @comp.* DIRECTIVE RATCHET.
#
# Current metaprogramming law admits NO compiler-directive syntax: metaprogramming
# operates on graph identities, facts, dependencies, demand, worlds, provenance and
# transformations. src/legacy_directives.zig nevertheless calls the dotted `@comp.*`
# forms "canonical" and maps the older underscore spellings onto them, so the tree
# carries a second semantic control plane of 109 forms across 133 files.
#
# This gate does not delete that plane — migration is per-form semantic work recorded
# in docs/spec/directive-ledger.json. It stops the plane GROWING, which is the part a
# reviewer cannot be expected to catch by reading a diff.
#
# TWO RULES, both monotonic:
#   NEW FORM     a `@comp.*` spelling absent from the ledger fails. The namespace is
#                closed; a new directive is a new authority.
#   MORE USES    a ledger form whose code-position count RISES fails. Usage may only
#                shrink. Lowering a count in the ledger is the intended way to record
#                migration progress.
#
# COUNTS ARE CODE POSITIONS ONLY. `#` comments are stripped before matching, because
# prose describing a directive is not a use of one: counting comment text reported
# 1063 occurrences where the code figure is 824. Forms may not end in a dot — an
# earlier census captured sentence punctuation and invented phantom forms such as
# `@comp.define...` and `@comp.agent.`.
#
# ZERO SUBJECTS IS A FAILURE, NOT A PASS. A census that enumerates nothing proves
# nothing; if the find below returns no files the gate exits nonzero rather than
# reporting a clean tree.
set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
led="docs/spec/directive-ledger.json"
[ -f "$led" ] || { echo "directive.sh: missing $led" >&2; exit 2; }
tmp="$(mktemp -t idoldir)"; trap 'rm -f "$tmp" "$tmp.led" "$tmp.now" "$tmp.files"' EXIT

# Counted OUTSIDE the pipeline on purpose. The loop below feeds `sort`, so it runs
# in a subshell and any counter incremented inside it is discarded when the subshell
# exits — the first version of this gate counted 0 subjects for exactly that reason
# and its own zero-subject guard caught it.
find . -name '*.id' -not -path './.git/*' | sort > "$tmp.files"
subjects=$(wc -l < "$tmp.files" | tr -d ' ')
: > "$tmp.now"
while IFS= read -r f; do
  sed 's/#.*//' "$f" | grep -oE '@comp\.[a-z0-9]+(\.[a-z0-9]+)*' || true
done < "$tmp.files" | sort | uniq -c | awk '{print $2"\t"$1}' > "$tmp.now"
[ "$subjects" -gt 0 ] || { echo "directive.sh: ZERO subjects enumerated — census proves nothing" >&2; exit 2; }

# The ledger is generated with one key per line, so this extraction is exact for the
# shape we emit. It is deliberately strict: a form line must be followed by its
# code_occurrences line, or the gate fails rather than guessing.
awk '
  /^    "@comp\./ { f=$1; gsub(/[",:]/,"",f); next }
  f != "" && /"code_occurrences"/ { c=$2; gsub(/[,]/,"",c); print f"\t"c; f=""; next }
' "$led" | sort > "$tmp.led"
[ -s "$tmp.led" ] || { echo "directive.sh: ledger parsed to ZERO forms — extraction is broken" >&2; exit 2; }

fail=0
newf=$(awk -F'\t' 'NR==FNR{k[$1]=1;next} !($1 in k){print $1" ("$2" uses)"}' "$tmp.led" "$tmp.now")
if [ -n "$newf" ]; then
  echo "directive.sh: NEW @comp.* form(s) — the directive namespace is closed:" >&2
  echo "$newf" | sed 's/^/  /' >&2
  fail=1
fi
grew=$(awk -F'\t' 'NR==FNR{b[$1]=$2;next} ($1 in b) && $2+0 > b[$1]+0 {print $1": "b[$1]" -> "$2}' "$tmp.led" "$tmp.now")
if [ -n "$grew" ]; then
  echo "directive.sh: @comp.* usage GREW — it may only shrink:" >&2
  echo "$grew" | sed 's/^/  /' >&2
  fail=1
fi

now_total=$(awk -F'\t' '{s+=$2} END{print s+0}' "$tmp.now")
led_total=$(awk -F'\t' '{s+=$2} END{print s+0}' "$tmp.led")
now_forms=$(wc -l < "$tmp.now" | tr -d ' ')
led_forms=$(wc -l < "$tmp.led" | tr -d ' ')
echo "directive.sh: $subjects .id subjects, $now_forms form(s)/$now_total code use(s); ledger pins $led_forms/$led_total."
shrunk=$(awk -F'\t' 'NR==FNR{b[$1]=$2;next} ($1 in b) && $2+0 < b[$1]+0 {n++} END{print n+0}' "$tmp.led" "$tmp.now")
gone=$(awk -F'\t' 'NR==FNR{k[$1]=1;next} {d[$1]=1} END{for(f in k) if(!(f in d)) n++; print n+0}' "$tmp.led" "$tmp.now")
[ "$shrunk" -eq 0 ] && [ "$gone" -eq 0 ] || \
  echo "directive.sh: migration progress — $shrunk form(s) less used, $gone form(s) fully removed; lower the ledger to lock it in."
[ "$fail" -eq 0 ] || { echo "directive.sh: DIRECTIVE RATCHET BROKEN." >&2; exit 1; }
echo "directive.sh: DIRECTIVE OK."
exit 0
