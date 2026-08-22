#!/usr/bin/env bash
# First blocking semantic edge, per corpus program.
#
# Coverage answers "which facts exist". This answers "which missing edge
# stops a program first, and which producer owns it" — the question that
# ranks work. They disagree: exact_i64 went 15.5% -> 98.4% while the
# blocking budget did not move, because the newly published facts sat
# behind a connective edge nobody had attributed.
#
# LIMIT (read before quoting a number): this is FIRST blocking edge, not
# the only one. A program refusing on `ret-type:any` may hide five deeper
# gaps behind it. Fixing the top family does NOT unblock its whole count.
# To get the next layer, fix a family and re-run — the census is designed
# to be iterated, not read once.
set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
bin="${IDOL_BIN:-$repo/zig-out/bin/idol}"
[ -x "$bin" ] || { echo "attribution: no compiler at $bin" >&2; exit 2; }
out="${1:-/dev/stdout}"
TMO="${ATTRIBUTION_TIMEOUT:-60}"
tmp="$(mktemp -t idolattr)"; trap 'rm -f "$tmp"' EXIT
find examples native_differential lib scripts -name '*.id' 2>/dev/null | sort > "$tmp.files"
: > "$tmp.rec"
while IFS= read -r f; do
  # stdin MUST be closed: `idol run` otherwise consumes this very list.
  # stdout to /dev/null, stderr captured; rc read from the DIRECT command,
  # never through a pipe (`$?` after a pipe reports the pipe, not the run).
  e="$(timeout "$TMO" "$bin" run "$f" 2>&1 >/dev/null </dev/null)"; rc=$?
  if [ "$rc" -eq 124 ]; then
    # A timeout is NOT a refusal. Under machine load a slow compile will
    # trip the clock; counting it as a refusal inflated this census by 96
    # files once already. Recorded separately and excluded from the budget.
    printf '%s\tTIMEOUT\n' "$f" >> "$tmp.rec"
  else
    printf '%s\t%s\n' "$f" "$(printf '%s' "$e" | grep -m1 -E 'missing:|DNB[0-9]+')" >> "$tmp.rec"
  fi
done < "$tmp.files"
total=$(wc -l < "$tmp.rec" | tr -d ' ')
clean=$(awk -F'\t' '$2==""' "$tmp.rec" | wc -l | tr -d ' ')
tmo=$(awk -F'\t' '$2=="TIMEOUT"' "$tmp.rec" | wc -l | tr -d ' ')
refuse=$((total - clean - tmo))
{
  echo "== FIRST BLOCKING SEMANTIC EDGE =="
  echo "corpus $total   compile+run $clean   refuse $refuse   timeout $tmo (>${TMO}s, NOT counted as refusal)"
  echo
  echo "-- producer owning the first blocking edge --"
  grep -oE 'producer: [a-z ]+' "$tmp.rec" | sed 's/producer: //' \
    | sort | uniq -c | sort -rn
  echo
  echo "-- first blocking reason --"
  grep -oE 'missing: [a-z0-9:_-]+' "$tmp.rec" | sed 's/missing: //' \
    | sort | uniq -c | sort -rn
} > "$out"
budget="${ATTRIBUTION_BUDGET:-}"
if [ -n "$budget" ]; then
  echo "gate/attribution.sh: budget $budget, measured $refuse"
  [ "$refuse" -le "$budget" ] || { echo "gate/attribution.sh: RATCHET BROKEN" >&2; exit 1; }
fi
exit 0

# LIB-ROOT TRAP, recorded because it is invisible and it bites hard:
# `detectCompilerLibRoot(..., args[0])` in src/main.zig:483 resolves the
# compiler's `lib/` from WHERE THE BINARY LIVES, not from the cwd. Passing
# IDOL_BIN from a mirror therefore measures the LIVE corpus against the
# MIRROR's lib/. Two binaries from different mirrors likewise compare two
# different lib/ trees, not one. Measured bound at the time of writing: only
# 4 of 943 corpus files reference `req(` at all, and 3 of 441 refusing ones,
# so the effect on this census is negligible — but a sweep over `req`-heavy
# source must build in place or the number is silently wrong.
