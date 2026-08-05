#!/usr/bin/env bash
# Head-to-head WASM runtime benchmark: ward vs every other runtime on PATH.
#
# Unlike scripts/run_wasm_benchmark.sh (which measures duo-compiled-to-WASM
# running *under* other runtimes), this measures the runtimes themselves
# executing the same module.
#
# Every runtime must produce byte-identical stdout or its time is discarded --
# a fast wrong answer is not a result.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WARD="${WARD_BIN:?set WARD_BIN to the ward binary}"
DIR="${BENCH_DIR:-$HERE/scaled}"
RUNS="${RUNS:-3}"
BENCHES="${BENCHES:-loop_i32 loop_f64 memory calls fib brtable}"

have() { command -v "$1" >/dev/null 2>&1; }

# name|command template ($1 = wasm file)
RUNTIMES=()
have wasmtime && RUNTIMES+=("wasmtime|wasmtime")
have wasmer   && RUNTIMES+=("wasmer|wasmer run")
have wasm3    && RUNTIMES+=("wasm3|wasm3")
have iwasm    && RUNTIMES+=("iwasm|iwasm")
have wazero   && RUNTIMES+=("wazero|wazero run")

now() { python3 -c 'import time;print(time.perf_counter())'; }

time_cmd() { # $@ = command; echoes "seconds|output"
    local t0 t1 out
    t0=$(now); out=$(timeout 900 "$@" 2>/dev/null | tail -1); t1=$(now)
    echo "$(python3 -c "print(f'{$t1-$t0:.4f}')")|$out"
}

best_of() { # $@ = command; echoes "best_seconds|output"
    local best="" out="" r
    for _ in $(seq "$RUNS"); do
        r=$(time_cmd "$@")
        local t="${r%%|*}" o="${r##*|}"
        out="$o"
        if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
    done
    echo "$best|$out"
}

printf '%-9s' "bench"
printf '%-14s' "ward"
for e in "${RUNTIMES[@]}"; do printf '%-14s' "${e%%|*}"; done
echo

for b in $BENCHES; do
    f="$DIR/$b.wasm"
    [[ -f "$f" ]] || { echo "$b: MISSING $f"; continue; }

    ref=$(timeout 900 wasmtime "$f" 2>/dev/null | tail -1)   # reference answer
    printf '%-9s' "$b"

    r=$(best_of "$WARD" run "$f"); wt="${r%%|*}"; wo="${r##*|}"
    [[ "$wo" == "$ref" ]] && printf '%-14s' "${wt}s" || printf '%-14s' "WRONG"

    for e in "${RUNTIMES[@]}"; do
        # shellcheck disable=SC2086
        r=$(best_of ${e##*|} "$f"); t="${r%%|*}"; o="${r##*|}"
        [[ "$o" == "$ref" ]] && printf '%-14s' "${t}s" || printf '%-14s' "WRONG"
    done
    echo
done
