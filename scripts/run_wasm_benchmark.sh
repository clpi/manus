#!/usr/bin/env bash
# WASM Runtime Benchmark: compares Duo-compiled WASM across multiple runtimes.
#
# Supported runtimes (auto-detected):
#   wasmtime  https://wasmtime.dev
#   wazero    https://wazero.io
#   wasm3     https://github.com/wasm3/wasm3
#   iwasm     https://github.com/bytecodealliance/wasm-micro-runtime
#   wasmer    https://wasmer.io
#   spin      https://developer.fermyon.com/spin
#
# "Better than last time" gate: each detected runtime must not regress
# by more than REGRESS_PCT (10%) versus the stored baseline.
# On the first run (or when --reset-baseline is passed), the baseline is
# written fresh and the gate always passes.
#
# Usage:
#   bash scripts/run_wasm_benchmark.sh [--reset-baseline] [--runs N]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
WASM_SRC="$ROOT/examples/benchmark_wasm.lua"
WASM_BIN="/tmp/duo_wasm_bench.wasm"
BASELINE_FILE="$ROOT/benchmarks/wasm_baseline.txt"
RUNS="${WASM_BENCH_RUNS:-3}"
REGRESS_PCT=10   # % slowdown allowed before gate fails
RESET_BASELINE=0
BENCHES=40

# ── Argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --reset-baseline) RESET_BASELINE=1 ;;
        --runs) shift ;;          # handled below via =N form
        --runs=*) RUNS="${arg#*=}" ;;
        *) ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
pass() { printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; }
info() { printf "  \033[34mINFO\033[0m %s\n" "$1"; }

# Returns wall-clock seconds for a command using /usr/bin/time (or bash time).
wall_time() {
    local cmd="$1"
    local elapsed
    elapsed=$( { /usr/bin/time -f "%e" sh -c "$cmd" > /dev/null 2>&1; } 2>&1 | tail -1 || true )
    # Fallback: TIMEFORMAT + bash time if /usr/bin/time failed
    if ! [[ "$elapsed" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        elapsed=$( { TIMEFORMAT='%R'; time sh -c "$cmd" > /dev/null 2>&1; } 2>&1 | tail -1 )
    fi
    printf '%s' "$elapsed"
}

# Collect minimum wall time across $RUNS runs.
collect_min() {
    local cmd="$1"
    local min=""
    local i
    for (( i = 0; i < RUNS; i++ )); do
        local t
        t=$(wall_time "$cmd")
        if [[ -z "$min" ]] || awk "BEGIN{exit !($t < $min)}" 2>/dev/null; then
            min="$t"
        fi
    done
    printf '%s' "${min:-0}"
}

# ── Runtime auto-detection ────────────────────────────────────────────────────
FOUND_RUNTIMES=()
declare -A RT_CMD

check_runtime() {
    local name="$1" cmd_test="$2" run_tmpl="$3"
    if command -v "$cmd_test" &>/dev/null; then
        FOUND_RUNTIMES+=("$name")
        RT_CMD["$name"]="$run_tmpl"
        info "Found runtime: $name ($(command -v "$cmd_test"))"
    fi
}

check_runtime "wasmtime" "wasmtime"  "wasmtime run $WASM_BIN"
check_runtime "wazero"   "wazero"    "wazero run $WASM_BIN"
check_runtime "wasm3"    "wasm3"     "wasm3 $WASM_BIN"
check_runtime "iwasm"    "iwasm"     "iwasm $WASM_BIN"
check_runtime "wasmer"   "wasmer"    "wasmer $WASM_BIN"
check_runtime "spin"     "spin"      "spin up --file $WASM_BIN"

if [[ ${#FOUND_RUNTIMES[@]} -eq 0 ]]; then
    echo "ERROR: No WASM runtimes found. Install at least one of:"
    echo "  wasmtime  https://wasmtime.dev"
    echo "  wazero    go install github.com/tetratelabs/wazero/cmd/wazero@latest"
    echo "  wasm3     https://github.com/wasm3/wasm3/releases"
    echo "  iwasm     https://github.com/bytecodealliance/wasm-micro-runtime/releases"
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "=== Building Duo compiler ==="
cd "$ROOT"
if ! command -v zig &>/dev/null; then
    echo "ERROR: zig not found in PATH. Install zig >= 0.13 to cross-compile to WASM."
    exit 1
fi
zig build 2>&1 | grep -v "^$" || true

echo ""
echo "=== Compiling benchmark to WASM ==="
"$DUO" compile "$WASM_SRC" --target wasm32-wasi -o "$WASM_BIN" 2>&1 | grep -v "warning" || true
if [[ ! -f "$WASM_BIN" ]]; then
    echo "ERROR: WASM compilation failed — $WASM_BIN not produced."
    exit 1
fi
info "Produced: $WASM_BIN ($(du -sh "$WASM_BIN" | cut -f1))"

# ── Correctness check ─────────────────────────────────────────────────────────
echo ""
echo "=== Correctness (RESULT lines, first runtime: ${FOUND_RUNTIMES[0]}) ==="
FIRST_RT="${FOUND_RUNTIMES[0]}"
FIRST_CMD="${RT_CMD[$FIRST_RT]}"

WASM_OUT=$( sh -c "$FIRST_CMD" 2>/dev/null || true )
WASM_RESULTS=$(echo "$WASM_OUT" | awk '/^RESULT / {print $2, $3}')
RESULT_COUNT=$(echo "$WASM_RESULTS" | grep -c "^" 2>/dev/null || echo 0)

if [[ "$RESULT_COUNT" -ne "$BENCHES" ]]; then
    echo "ERROR: Expected $BENCHES RESULT lines, got $RESULT_COUNT."
    echo "Output (first 20 lines):"
    echo "$WASM_OUT" | head -20
    exit 1
fi
pass "All $BENCHES RESULT lines present"

# Cross-check: run on the second runtime if available and compare results.
if [[ ${#FOUND_RUNTIMES[@]} -ge 2 ]]; then
    SECOND_RT="${FOUND_RUNTIMES[1]}"
    SECOND_CMD="${RT_CMD[$SECOND_RT]}"
    SECOND_RESULTS=$( sh -c "$SECOND_CMD" 2>/dev/null | awk '/^RESULT / {print $2, $3}' || true )
    if [[ "$WASM_RESULTS" == "$SECOND_RESULTS" ]]; then
        pass "Results match between $FIRST_RT and $SECOND_RT"
    else
        fail "Result mismatch between $FIRST_RT and $SECOND_RT"
        diff <(echo "$WASM_RESULTS") <(echo "$SECOND_RESULTS") | head -20
    fi
fi

# ── Timing ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Timing (min of $RUNS runs, wall-clock seconds) ==="
declare -A CURRENT_TIMES

for rt in "${FOUND_RUNTIMES[@]}"; do
    info "Timing $rt..."
    CURRENT_TIMES["$rt"]=$(collect_min "${RT_CMD[$rt]}")
    printf "  %-12s  %.3fs\n" "$rt" "${CURRENT_TIMES[$rt]}"
done

# ── Baseline comparison ───────────────────────────────────────────────────────
echo ""
GATE_FAIL=0

load_baseline() {
    declare -gA BASELINE_TIMES
    [[ -f "$BASELINE_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        rt=$(echo "$line" | awk '{print $1}')
        t=$(echo  "$line" | awk '{print $2}')
        BASELINE_TIMES["$rt"]="$t"
    done < "$BASELINE_FILE"
}

save_baseline() {
    mkdir -p "$(dirname "$BASELINE_FILE")"
    {
        echo "# Duo WASM Runtime Benchmark Baseline"
        echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "# Commit: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        echo "# Runs per runtime: $RUNS"
        echo "#"
        echo "# runtime  total_wall_seconds"
        for rt in "${FOUND_RUNTIMES[@]}"; do
            printf "%-12s  %s\n" "$rt" "${CURRENT_TIMES[$rt]}"
        done
    } > "$BASELINE_FILE"
    info "Baseline saved → $BASELINE_FILE"
}

declare -A BASELINE_TIMES
load_baseline

if [[ "$RESET_BASELINE" -eq 1 ]] || [[ ! -f "$BASELINE_FILE" ]]; then
    if [[ "$RESET_BASELINE" -eq 1 ]]; then
        echo "=== Resetting baseline ==="
    else
        echo "=== No baseline found — writing initial baseline ==="
    fi
    save_baseline
    echo ""
    printf "%-12s  %10s  %10s  %8s\n" "Runtime" "Current(s)" "Baseline(s)" "Delta"
    printf "%-12s  %10s  %10s  %8s\n" "------------" "----------" "-----------" "--------"
    for rt in "${FOUND_RUNTIMES[@]}"; do
        printf "%-12s  %10.3f  %10s  %8s\n" "$rt" "${CURRENT_TIMES[$rt]}" "(new)" "baseline"
    done
else
    echo "=== Regression check (>${REGRESS_PCT}% slowdown = FAIL) ==="
    echo ""
    printf "%-12s  %10s  %10s  %8s  %s\n" "Runtime" "Current(s)" "Baseline(s)" "Delta%" "Status"
    printf "%-12s  %10s  %10s  %8s  %s\n" "------------" "----------" "-----------" "--------" "------"

    for rt in "${FOUND_RUNTIMES[@]}"; do
        cur="${CURRENT_TIMES[$rt]}"
        base="${BASELINE_TIMES[$rt]:-}"

        if [[ -z "$base" ]]; then
            printf "%-12s  %10.3f  %10s  %8s  %s\n" "$rt" "$cur" "(new)" "-" "NEW"
            continue
        fi

        # Compute delta%: positive = faster, negative = slower
        delta_pct=$(awk -v c="$cur" -v b="$base" 'BEGIN{
            if (b+0 < 1e-9) { print "0"; exit }
            printf "%.1f", (b - c) / b * 100
        }')

        status="OK"
        regression=$(awk -v c="$cur" -v b="$base" -v pct="$REGRESS_PCT" 'BEGIN{
            if (b+0 < 1e-9) { print 0; exit }
            print (c - b) / b * 100 > pct ? 1 : 0
        }')

        if [[ "$regression" -eq 1 ]]; then
            status="REGRESSED"
            GATE_FAIL=1
        elif awk -v c="$cur" -v b="$base" 'BEGIN{exit !(c < b * 0.98)}' 2>/dev/null; then
            status="IMPROVED"
        fi

        printf "%-12s  %10.3f  %10.3f  %7.1f%%  %s\n" "$rt" "$cur" "$base" "$delta_pct" "$status"
    done

    # Save updated baseline if no regression.
    if [[ "$GATE_FAIL" -eq 0 ]]; then
        echo ""
        save_baseline
    fi
fi

# ── Summary table ─────────────────────────────────────────────────────────────
if [[ ${#FOUND_RUNTIMES[@]} -ge 2 ]]; then
    echo ""
    echo "=== Relative speed (wasmtime=1.0x reference, lower is faster) ==="
    ref_time="${CURRENT_TIMES[${FOUND_RUNTIMES[0]}]}"
    for rt in "${FOUND_RUNTIMES[@]}"; do
        ratio=$(awk -v t="${CURRENT_TIMES[$rt]}" -v r="$ref_time" \
            'BEGIN{ if(r+0<1e-9){print "N/A"}else{printf "%.2fx", t/r} }')
        printf "  %-12s  %s\n" "$rt" "$ratio"
    done
fi

# ── Final gate ────────────────────────────────────────────────────────────────
echo ""
if [[ "$GATE_FAIL" -ne 0 ]]; then
    echo "WASM benchmark FAILED: one or more runtimes regressed by >${REGRESS_PCT}%."
    echo "Run with --reset-baseline to accept the new times as the new baseline."
    exit 1
fi

echo "WASM benchmark PASSED: all runtimes at or better than baseline."
