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
    diag="$(printf '%s' "$e" | grep -m1 -E 'missing:|DNB[0-9]+')"
    if [ -n "$diag" ]; then
      printf '%s\t%s\n' "$f" "$diag" >> "$tmp.rec"
    elif [ "$rc" -eq 0 ]; then
      printf '%s\t\n' "$f" >> "$tmp.rec"
    else
      # NONZERO EXIT WITH NO DIAGNOSTIC IS NOT A CLEAN COMPILE. A parser
      # error, a crash, or a killed compiler emits no `missing:` and no DNB
      # code; scoring it by the empty field would count it as compile+run,
      # SHRINKING the refusal budget and leaving this gate green on a
      # regression. Same failure shape as TRAP 4 in gate/differential.sh —
      # the silent error is OPTIMISTIC. Classified separately and excluded
      # from both the clean count and the budget.
      printf '%s\tUNCLASSIFIED rc=%s\n' "$f" "$rc" >> "$tmp.rec"
    fi
  fi
done < "$tmp.files"
total=$(wc -l < "$tmp.rec" | tr -d ' ')
clean=$(awk -F'\t' '$2==""' "$tmp.rec" | wc -l | tr -d ' ')
tmo=$(awk -F'\t' '$2=="TIMEOUT"' "$tmp.rec" | wc -l | tr -d ' ')
unc=$(grep -c '\tUNCLASSIFIED' "$tmp.rec" || true)
refuse=$((total - clean - tmo - unc))
{
  echo "== FIRST BLOCKING SEMANTIC EDGE =="
  echo "corpus $total   compile+run $clean   refuse $refuse   timeout $tmo (>${TMO}s)   unclassified $unc (nonzero exit, no diagnostic)"
  if [ "$unc" -gt 0 ]; then
    echo "  UNCLASSIFIED runs invalidate the budget — a crash or parse error is not a refusal:"
    grep '\tUNCLASSIFIED' "$tmp.rec" | head -10 | sed 's/^/    /'
  fi
  echo
  # NOT AN INDEPENDENT OBSERVATION. src/native_backend.zig:242 reads
  #   const producer = if (err == error.SemanticFactsInvalid) "graph"
  #                    else "dnir lower";
  # so this column RESTATES the error code and adds nothing to it. Measured:
  # DNB001 333 / DNB011 92 against dnir-lower 333 / graph 91 — the same split
  # twice. Report it as the code split it is; do not cite it as corroboration
  # of a reason histogram, and do not call it attribution.
  #
  # WORSE THAN UNINFORMATIVE — IT MISATTRIBUTES THE MAJORITY. Measured by an
  # instrumented build: 302 of 444 first blocking edges (68%) are emitted by
  # src/codegen.zig's PRE-GRAPH native_scalar_precheck, which runs at
  # main.zig:4781, strictly before every graph lift (main.zig:4991/5214/5249)
  # and so cannot consult the graph at all. main.zig:5102-5108 funnels that
  # precheck tag into this same `missing:` slot, and formatDirectCause labels
  # every error.UnsupportedProgram "dnir lower". There is no
  # `producer: codegen precheck` value, so this census CANNOT NAME the phase
  # that owns most of the budget. Treat the column as absent, not as data.
  #
  # AND THERE IS NO GRAPH FACT TO ROUTE TO for the descriptor family: an
  # instrumented lift measured params_with_descriptor = 0 in 808 of 808
  # relation nodes, and 46 of 46 ret-type-refused relations answer `any`
  # identically in AST and graph — semantic_graph.zig:2536 and :4082 set
  # `.result_descriptor = try types.resolve(fd.func.ret_type, ...)`, copying
  # the same AST field the precheck reads. The graph MIRRORS the AST here.
  # The fact is unproduced, not producer-hollow.
  echo "-- error code restated as producer (NOT independent of the code) --"
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
  [ "$unc" -eq 0 ] || { echo "gate/attribution.sh: $unc UNCLASSIFIED run(s) — budget NOT judged" >&2; exit 1; }
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
