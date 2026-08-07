#!/usr/bin/env bash
# ward benchmark + coverage harness.
#
# Every perf/coverage claim about ward must come from this script. It exists
# because two earlier "baselines" were wrong for the same reason: ward reads
# WARD_WASM, NOT argv (src/ward.duo entry), and silently falls back to a
# hardcoded /tmp/hash.wasm. Passing a module as $1 measures nothing.
#
#   ./bench/run.sh          # full sweep
#   ./bench/run.sh cover    # coverage only, no timing
set -uo pipefail
cd "$(dirname "$0")/.."

DUO=${DUO:-$HOME/x/duo/zig-out/bin/duo}
WART=${WART:-$HOME/x/wart/zig-out/bin/wart}
WASMTIME=${WASMTIME:-wasmtime}
WARD_BIN=${WARD_BIN:-/tmp/ward}
MODE=${1:-full}

build() {
  echo "== building ward =="
  "$DUO" compile src/ward.duo --backend=c --emit exe -o "$WARD_BIN" 2>&1 \
    | grep -vE 'warning|detail:|help:' | tail -3
  [[ -x "$WARD_BIN" ]] || { echo "BUILD FAILED"; exit 1; }
}

# Run one engine on one module. Echoes "<result>|<seconds>|<exit>".
# ward is invoked via WARD_WASM; anything else is a lie (see header).
ward_run() {
  local mod=$1 engine=$2 out rc res sec eng
  # Corpora disagree on the entry export: hash.wasm uses `run`, wart's uses
  # `_start`. Try both rather than silently reporting "unsupported".
  for want in "${WANT:-run}" _start; do
    out=$(WARD_WASM="$PWD/$mod" WARD_INVOKE="$want" WARD_ENGINE="$engine" \
          timeout 120 "$WARD_BIN" 2>&1)
    rc=$?
    res=$(sed -n 's/^result=//p' <<<"$out")
    [[ -n $res ]] && break
  done
  sec=$(sed -n 's/^seconds=//p' <<<"$out")
  eng=$(sed -n 's/^engine=//p' <<<"$out")
  # Report the engine that actually ran: the JIT falls back to the interpreter
  # on any opcode it cannot emit, so "jit" requested != "jit" used.
  printf '%s|%.4s|%s\n' "${res:-none}" "${sec:-none}" "${eng:-none}"
}

# wart takes the module on argv and runs _start.
wart_run() {
  local mod=$1 t0 t1 rc
  t0=$(python3 -c 'import time;print(time.time())')
  timeout 120 "$WART" run "$mod" >/dev/null 2>&1; rc=$?
  t1=$(python3 -c 'import time;print(time.time())')
  # 132 == 128+SIGILL: wart's ARM64 JIT emits `ldp xzr,xzr,[sp],#16`
  # (Rt==Rt2==31, UNPREDICTABLE, trapped on Apple silicon).
  [[ $rc -eq 132 ]] && { echo "SIGILL|-|$rc"; return; }
  python3 -c "print('ok|%.3f|$rc' % ($t1-$t0))"
}

wasmtime_run() {
  local mod=$1 t0 t1 out rc
  t0=$(python3 -c 'import time;print(time.time())')
  out=$(timeout 120 "$WASMTIME" --invoke run "$mod" 2>/dev/null); rc=$?
  t1=$(python3 -c 'import time;print(time.time())')
  python3 -c "print('${out:-none}|%.3f|$rc' % ($t1-$t0))"
}

build
printf '\n%-32s %-26s %-26s %-18s %s\n' MODULE 'ward-jit (res|s|rc)' 'ward-interp' 'wasmtime' 'wart'
printf '%.0s-' {1..126}; echo

pass=0; total=0
for m in bench/*.wasm; do
  total=$((total+1))
  jit=$(ward_run "$m" jit)
  itp=$(ward_run "$m" interp)
  if [[ $MODE == cover ]]; then wt="-|-|-"; wr="-|-|-"
  else wt=$(wasmtime_run "$m"); wr=$(wart_run "$m"); fi
  printf '%-32s %-26s %-26s %-18s %s\n' "$(basename "$m" .wasm)" "$jit" "$itp" "$wt" "$wr"
  # ward "covers" a module when it produced a result at all and both engines
  # agree. result=0 is legitimate here: the wart corpus exports a void `_start`.
  jr=${jit%%|*}; ir=${itp%%|*}
  if [[ $jr == "$ir" && $jr != none && $jr != -1 ]]; then pass=$((pass+1)); fi
done

printf '%.0s-' {1..126}; echo
echo "ward covers $pass/$total modules (both engines agree, non-sentinel result)"
