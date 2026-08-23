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
subject="$repo/gate/subject.sh"
[ -x "$bin" ] || { echo "attribution: no compiler at $bin" >&2; exit 2; }
[ -x "$subject" ] || { echo "attribution: no subject enumerator at $subject" >&2; exit 2; }
out="${1:-/dev/stdout}"
TMO="${ATTRIBUTION_TIMEOUT:-60}"
tmp="$(mktemp -t idolattr)"; trap 'rm -f "$tmp" "$tmp.all" "$tmp.files" "$tmp.rec"' EXIT
# examples/compile_fail/ IS EXCLUDED ON PURPOSE. Those files exist to be
# rejected — a refusal there is the fixture passing, not a blocked program.
# Counting them inflated this budget by 29 and would have made the census
# improve every time someone ADDED a negative test.
if ! sh "$subject" 'examples/*.id' 'native_differential/*.id' 'lib/*.id' \
    'scripts/*.id' >"$tmp.all"; then
  echo "attribution: source enumeration failed (GAP-201/GAP-220)" >&2
  exit 2
fi
LC_ALL=C awk '!/\/compile_fail\//' "$tmp.all" | LC_ALL=C sort >"$tmp.files"
[ -s "$tmp.files" ] || { echo "attribution: ZERO non-fixture subjects" >&2; exit 2; }
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
    # THE COMPILER STATES ITS OWN OUTCOME; DO NOT INFER IT FROM rc.
    # An Idol program's exit status IS its tail value — examples/anchor/bare.id
    # prints `5 9 5` and exits 5 because 5 is its answer. An earlier rule here
    # scored `rc == 0` as "compiled and ran", which actually scored "the program
    # answered zero" — an arbitrary property of the source, not a success
    # signal — and moved 391 correct programs into a bogus failure bucket.
    # Nor is empty stderr the signal: progress lines (`> compile ...`, the `✓`)
    # are written to STDERR, so `$e` is essentially never empty and a rule
    # keyed on that classified the entire corpus as failing.
    # The two authoritative markers are the compiler's own: `✓` = it produced
    # and ran an artifact, `error:` = it refused.
    # BOTH SUCCESS SPELLINGS, because the compiler has two and they are not
    # interchangeable: a COLD compile prints `  ok compile (35 ms — ./x.out)`
    # and only a CACHE HIT prints `✓ ./x.out (cached)`. Keying on `✓` alone
    # made this census measure CACHE STATE rather than the compiler: the same
    # tree scored 230 compile+run warm and 4 cold, and every `zig build`
    # relink flipped it, because the compiler's size and mtime are in the
    # build cache key so a rebuild invalidates every entry at once. That
    # produced a 227-program phantom regression twice.
    ok="$(printf '%s' "$e" | grep -cE '^✓|ok compile')"
    err="$(printf '%s' "$e" | grep -c -E '^error:|: error: ')"
    diag="$(printf '%s' "$e" | grep -m1 -E 'missing:|DNB[0-9]+')"
    if [ -n "$diag" ]; then
      printf '%s\t%s\n' "$f" "$diag" >> "$tmp.rec"
    elif printf '%s' "$e" | grep -q '^error: no process:'; then
      # NOT A PROGRAM, THEREFORE NOT A BLOCKED PROGRAM. 171 corpus files —
      # 64 in lib/, 21 in lib/ml/, 15 in lib/compiler/ — define values and
      # relations and declare no entry point, so `idol run` correctly reports
      # `no process`. Scoring that as a first blocking semantic edge charged
      # 171 refusals (25% of the budget) to the compiler for a question the
      # file never asked. Excluded from clean AND from refuse.
      # Keyed on the DIAGNOSTIC, not on the path: a lib/ file that grows an
      # entry point re-enters the census by itself, and an examples/ program
      # that loses one leaves it. A path rule would freeze today's layout.
      printf '%s\tNOTAPROGRAM\n' "$f" >> "$tmp.rec"
    elif [ "$err" -gt 0 ]; then
      # A REFUSAL THE REASON PATTERN CANNOT NAME — e.g. `error: no process: a
      # file-scope tail is the program`. It is a real refusal with different
      # wording, so it belongs in the budget; it is reported separately only
      # because the reason histogram below cannot bucket it.
      # `^error: N error(s)` is the SUMMARY line, not the reason — it only
      # restates that something failed. The reason is the located diagnostic
      # `file:line:col: error: <text>`, so that is what gets recorded.
      # Prefer the LOCATED diagnostic `file:line:col: error: <text>`; fall back
      # to the bare `error: <text>` form (e.g. `macro expansion error:
      # UnknownMacro`, 5 files) which carries a reason but no source position.
      # Without the fallback those refusals bucket as the empty string and
      # sort to the top of the histogram as a phantom leading cause — which
      # is exactly how 176 files once presented as one nameless #1 reason.
      r="$(printf '%s' "$e" | grep -m1 ': error: ' | sed 's/.*: error: //')"
      [ -n "$r" ] || r="$(printf '%s' "$e" | grep -m1 '^error:' | sed 's/^error: //')"
      printf '%s\tUNNAMED %s\n' "$f" "$(printf '%s' "$r" | cut -c1-80)" >> "$tmp.rec"
    elif [ "$ok" -gt 0 ]; then
      printf '%s\t\n' "$f" >> "$tmp.rec"
    else
      # NEITHER MARKER. The compiler did not claim success and did not claim
      # refusal: a crash, a signal, or a message shape this gate does not know.
      # Scoring it either way is a lie in a different direction, so it is
      # counted apart and it makes the budget refuse to judge.
      printf '%s\tUNCLASSIFIED rc=%s\n' "$f" "$rc" >> "$tmp.rec"
    fi
  fi
done < "$tmp.files"
total=$(wc -l < "$tmp.rec" | tr -d ' ')
clean=$(awk -F'\t' '$2==""' "$tmp.rec" | wc -l | tr -d ' ')
tmo=$(awk -F'\t' '$2=="TIMEOUT"' "$tmp.rec" | wc -l | tr -d ' ')
unn=$(grep -c '\tUNNAMED' "$tmp.rec" || true)
nap=$(grep -c '\tNOTAPROGRAM' "$tmp.rec" || true)
unc=$(grep -c '\tUNCLASSIFIED' "$tmp.rec" || true)
refuse=$((total - clean - tmo - unc - nap))   # UNNAMED stays inside refuse; UNCLASSIFIED does not
{
  echo "== FIRST BLOCKING SEMANTIC EDGE =="
  echo "corpus $total   programs $((total - nap))   not-a-program $nap (no entry point)"
  echo "compile+run $clean   refuse $refuse   timeout $tmo (>${TMO}s)   unnamed $unn (refused, reason unbucketed)   unclassified $unc (no ✓, no error:)"
  if [ "$unn" -gt 0 ]; then
    echo "  UNNAMED — inside the refuse count; the reason histogram cannot bucket these:"
    grep '\tUNNAMED' "$tmp.rec" | head -10 | sed 's/^/    /'
  fi
  if [ "$unc" -gt 0 ]; then
    echo "  UNCLASSIFIED — compiler claimed neither success nor refusal:"
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
  # 250 of 690 refusals (36%) carry a located prose diagnostic rather than a
  # `missing:` tag. The tagged histogram below therefore ranks barely half the
  # budget; read BOTH or the top of the list is an artifact of which refusals
  # happen to be machine-tagged. This section is the untagged remainder.
  echo "-- first blocking reason (untagged prose, $unn of $refuse refusals) --"
  awk -F'\t' '$2 ~ /^UNNAMED /{sub(/^UNNAMED /,"",$2); print $2}' "$tmp.rec" \
    | sort | uniq -c | sort -rn | head -20
  echo
  echo "-- first blocking reason (tagged, $((refuse - unn)) of $refuse refusals) --"
  grep -oE 'missing: [a-z0-9:_-]+' "$tmp.rec" | sed 's/missing: //' \
    | sort | uniq -c | sort -rn
} > "$out"
budget="${ATTRIBUTION_BUDGET:-}"
if [ -n "$budget" ]; then
  echo "gate/attribution.sh: budget $budget, measured $refuse"
  [ "$unc" -eq 0 ] || { echo "gate/attribution.sh: $unc UNCLASSIFIED — budget NOT judged" >&2; exit 1; }
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
