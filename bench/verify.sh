#!/usr/bin/env bash
# Differential correctness oracle: ward vs wasmtime.
#
# This exists because "ward produced a result" is NOT coverage. A first pass at
# this harness counted any non-sentinel result as a pass and reported 8/18; a
# differential check against wasmtime showed 2 of those were plain wrong and one
# was an f64 the reporting path truncates. Only wasmtime agreement counts.
#
#   ./bench/verify.sh
set -uo pipefail
cd "$(dirname "$0")/.."
WARD_BIN=${WARD_BIN:-/tmp/ward}
WASMTIME=${WASMTIME:-wasmtime}

# wasmtime prints i32 signed, ward prints it unsigned. Same 32-bit value.
norm() { python3 -c "
import sys
v=sys.argv[1].strip()
try:
    f=float(v)
except ValueError:
    print(v); sys.exit()
if f!=f:
    print('nan'); sys.exit()
if f==int(f) and abs(f)<2**63:
    print(int(f)%(2**32))          # fold to unsigned 32-bit
else:
    # Non-integral: an f64. Compare as a DOUBLE, not as text — wasmtime and
    # ward print different digit counts for the same value (4.436463668243931
    # vs 4.4364636682439311), which read as a DIFF and hid real passes.
    print(repr(float(v)))
" "$1" 2>/dev/null || echo "$1"; }

pass=0; fail=0; skip=0; void=0; jitn=0
printf '%-30s %-20s %-20s %-10s %s\n' MODULE WASMTIME WARD ENGINE VERDICT
printf '%.0s-' {1..96}; echo
for m in bench/*.wasm; do
  name=$(basename "$m" .wasm)
  # Pick the export wasmtime can actually invoke, judged by EXIT STATUS rather
  # than by output: a void `(func)` export runs fine and prints nothing, and
  # keying off output alone both skipped those and misnamed the export in the
  # error text (it reported the last candidate tried, not the real one).
  want=""; ref=""
  for cand in run _start benchmark; do
    if out=$("$WASMTIME" --invoke "$cand" "$m" 2>/dev/null); then
      want=$cand; ref=$(tail -1 <<<"$out"); break
    fi
  done
  [[ -z $want ]] && want=_start
  # WARD_ENGINE selects the engine under test. It defaults to `interp` because
  # that is the path every module takes; run with WARD_ENGINE=jit to difference
  # the JIT against the same oracle. The JIT silently FALLS BACK to the
  # interpreter when it cannot compile a body, so agreement alone does not prove
  # the JIT ran — the ENGINE column reports what actually executed.
  raw=$(WARD_WASM="$PWD/$m" WARD_INVOKE="$want" WARD_ENGINE="${WARD_ENGINE:-interp}" \
        timeout 120 "$WARD_BIN" 2>/dev/null)
  eng=$(sed -n 's/^engine=//p' <<<"$raw")
  [[ $eng == jit-arm64 ]] && jitn=$((jitn+1))
  got=$(sed -n 's/^result=//p' <<<"$raw")
  # A module whose real answer is what it PRINTS (via fd_write) is compared on
  # its emitted bytes, not on the numeric result of a void _start. Strip ward's
  # own protocol lines to recover just the module's output.
  emitted=$(sed 's/engine=.*//; s/^result=.*//; s/^seconds=.*//' <<<"$raw" | tr -d '\n')
  if [[ -n ${emitted// } && ! $ref =~ ^-?[0-9.]+$ ]]; then got=$emitted; fi
  if [[ -z $ref ]]; then
    # wasmtime invoked it successfully but it yields no observable value — a
    # void `(func)` export that neither returns nor prints. There is nothing to
    # difference, so the only honest check is that ward also runs it to
    # completion instead of bailing (-1). Counted separately from a real PASS,
    # because "didn't trap" is much weaker evidence than "matched the oracle".
    if [[ -n $want && -n $got && $got != -1 ]]; then
      printf '%-30s %-20s %-20s %-10s %s\n' "$name" "<void>" "$got" "${eng:-?}" "OK(void)"; void=$((void+1))
    else
      printf '%-30s %-20s %-20s %-10s %s\n' "$name" "<void>" "${got:-none}" "${eng:-?}" "SKIP"; skip=$((skip+1))
    fi
    continue
  fi
  if [[ -z $got || $got == -1 ]]; then
    printf '%-30s %-20s %-20s %-10s %s\n' "$name" "$ref" "${got:-none}" "${eng:-?}" "UNSUPPORTED"; fail=$((fail+1)); continue
  fi
  if [[ $(norm "$ref") == $(norm "$got") ]]; then
    printf '%-30s %-20s %-20s %-10s %s\n' "$name" "$ref" "$got" "${eng:-?}" "PASS"; pass=$((pass+1))
  else
    printf '%-30s %-20s %-20s %-10s %s\n' "$name" "$ref" "$got" "${eng:-?}" "*** DIFF ***"; fail=$((fail+1))
  fi
done
printf '%.0s-' {1..96}; echo
echo "ward agrees with wasmtime on $pass module(s); $fail unsupported-or-wrong; $void void-export completed; $skip skipped"

# JIT COVERAGE FLOOR. A JIT that stops compiling falls back to the interpreter
# and still produces correct answers, so a purely correctness-based gate stays
# fully green while the JIT is dead. That happened during this work: an
# operand-stack accounting bug disabled JIT compilation for every float module
# and the corpus still read 42/42. Only under WARD_ENGINE=jit is the floor
# meaningful; the default interp run legitimately compiles nothing.
if [[ ${WARD_ENGINE:-interp} == jit ]]; then
  floor=${JIT_FLOOR:-34}
  echo "jit-compiled: $jitn module(s) (floor $floor)"
  if (( jitn < floor )); then
    echo "*** JIT COVERAGE REGRESSION: $jitn < $floor — the JIT is silently falling back ***"
    exit 1
  fi
fi
(( fail == 0 )) || exit 1
