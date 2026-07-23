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
#   WASM_BENCH_RUNTIMES="wasmtime wazero" bash scripts/run_wasm_benchmark.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
WASM_SRC="$ROOT/examples/benchmark_wasm.lua"
WORK_DIR="${WASM_BENCH_WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/duo_wasm_bench.XXXXXX")}"
KEEP_WORK_DIR=0
if [[ -n "${WASM_BENCH_WORK_DIR:-}" ]]; then
    mkdir -p "$WORK_DIR"
    KEEP_WORK_DIR=1
fi
WASM_BIN="$WORK_DIR/duo_wasm_bench.wasm"
BASELINE_FILE="${WASM_BENCH_BASELINE:-$ROOT/benchmarks/wasm_baseline.txt}"
RUNS="${WASM_BENCH_RUNS:-3}"
RUNTIME_FILTER="${WASM_BENCH_RUNTIMES:-}"
REGRESS_PCT=10   # % slowdown allowed before gate fails
RESET_BASELINE=0
BENCHES=40

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset-baseline)
            RESET_BASELINE=1
            shift
            ;;
        --runs)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --runs requires a value"
                exit 1
            fi
            RUNS="$2"
            shift 2
            ;;
        --runs=*)
            RUNS="${1#*=}"
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1"
            exit 1
            ;;
    esac
done

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: runs must be a positive integer, got '$RUNS'"
    exit 1
fi

cleanup() {
    if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────
pass() { printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; }
info() { printf "  \033[34mINFO\033[0m %s\n" "$1"; }

# Returns wall-clock seconds for a command using /usr/bin/time (or bash time).
wall_time() {
    local label="$1"
    local cmd="$2"
    local out_file="$WORK_DIR/${label}.time.out"
    local err_file="$WORK_DIR/${label}.time.err"
    local elapsed
    local status=0

    elapsed=$( { /usr/bin/time -f "%e" sh -c "$cmd" >"$out_file" 2>"$err_file"; } 2>&1 ) || status=$?
    # Fallback: TIMEFORMAT + bash time if /usr/bin/time failed
    if ! [[ "$elapsed" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        status=0
        elapsed=$( { TIMEFORMAT='%R'; time sh -c "$cmd" >"$out_file" 2>"$err_file"; } 2>&1 ) || status=$?
    fi

    if [[ "$status" -ne 0 ]] || ! [[ "$elapsed" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "ERROR: timing run '$label' failed" >&2
        echo "  command: $cmd" >&2
        echo "  stdout: $out_file" >&2
        echo "  stderr: $err_file" >&2
        sed -n '1,40p' "$err_file" >&2
        return 1
    fi

    printf '%s' "$elapsed"
}

capture_runtime_output() {
    local label="$1"
    local cmd="$2"
    local out_file="$WORK_DIR/${label}.out"
    local err_file="$WORK_DIR/${label}.err"

    if ! sh -c "$cmd" >"$out_file" 2>"$err_file"; then
        echo "ERROR: runtime '$label' failed" >&2
        echo "  command: $cmd" >&2
        echo "  stdout: $out_file" >&2
        echo "  stderr: $err_file" >&2
        sed -n '1,40p' "$err_file" >&2
        return 1
    fi

    cat "$out_file"
}

# Collect minimum wall time across $RUNS runs.
collect_min() {
    local label="$1"
    local cmd="$2"
    local min=""
    local i
    for (( i = 0; i < RUNS; i++ )); do
        local t
        if ! t=$(wall_time "${label}.${i}" "$cmd"); then
            return 1
        fi
        if [[ -z "$min" ]] || awk "BEGIN{exit !($t < $min)}" 2>/dev/null; then
            min="$t"
        fi
    done
    printf '%s' "${min:-0}"
}

# ── Runtime auto-detection ────────────────────────────────────────────────────
FOUND_RUNTIMES=()
declare -a RT_KEYS
declare -a RT_CMDS

check_runtime() {
    local name="$1" cmd_test="$2" run_tmpl="$3"
    if [[ -n "$RUNTIME_FILTER" ]]; then
        case " ${RUNTIME_FILTER//,/ } " in
            *" $name "*) ;;
            *) return 0 ;;
        esac
    fi
    if command -v "$cmd_test" &>/dev/null; then
        FOUND_RUNTIMES+=("$name")
        RT_KEYS+=("$name")
        RT_CMDS+=("$run_tmpl")
        info "Found runtime: $name ($(command -v "$cmd_test"))"
    fi
}

check_runtime "wasmtime" "wasmtime"  "wasmtime run $WASM_BIN"
check_runtime "wazero"   "wazero"    "wazero run $WASM_BIN"
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
zig build

echo ""
echo "=== Compiling benchmark to WASM ==="
"$DUO" compile "$WASM_SRC" --target wasm32-wasi -o "$WASM_BIN"
if [[ ! -f "$WASM_BIN" ]]; then
    echo "ERROR: WASM compilation failed — $WASM_BIN not produced."
    exit 1
fi
info "Produced: $WASM_BIN ($(du -sh "$WASM_BIN" | cut -f1))"

# ── Correctness check ─────────────────────────────────────────────────────────
echo ""
echo "=== Correctness (RESULT lines, first runtime: ${FOUND_RUNTIMES[0]}) ==="
FIRST_RT="${FOUND_RUNTIMES[0]}"
FIRST_CMD="${RT_CMDS[0]}"

WASM_OUT=$(capture_runtime_output "$FIRST_RT.correctness" "$FIRST_CMD")
WASM_RESULTS=$(echo "$WASM_OUT" | awk '/^RESULT / {print $2, $3}')
RESULT_COUNT=$(printf "%s\n" "$WASM_RESULTS" | sed '/^$/d' | wc -l | tr -d ' ')

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
    SECOND_CMD="${RT_CMDS[1]}"
    SECOND_OUT=$(capture_runtime_output "$SECOND_RT.correctness" "$SECOND_CMD")
    SECOND_RESULTS=$(echo "$SECOND_OUT" | awk '/^RESULT / {print $2, $3}')
    if [[ "$WASM_RESULTS" == "$SECOND_RESULTS" ]]; then
        pass "Results match between $FIRST_RT and $SECOND_RT"
    else
        fail "Result mismatch between $FIRST_RT and $SECOND_RT"
        diff <(echo "$WASM_RESULTS") <(echo "$SECOND_RESULTS") | head -20
        exit 1
    fi
fi

# ── Timing ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Timing (min of $RUNS runs, wall-clock seconds) ==="
declare -a CURRENT_TIMES

for rt in "${FOUND_RUNTIMES[@]}"; do
    info "Timing $rt..."
    rt_idx=""
    for i in "${!FOUND_RUNTIMES[@]}"; do
        if [[ "${FOUND_RUNTIMES[$i]}" == "$rt" ]]; then
            CURRENT_TIMES[$i]=$(collect_min "$rt" "${RT_CMDS[$i]}")
            rt_idx="$i"
            break
        fi
    done
    printf "  %-12s  %.3fs\n" "$rt" "${CURRENT_TIMES[$rt_idx]}"
done

# ── Baseline comparison ───────────────────────────────────────────────────────
echo ""
GATE_FAIL=0

baseline_for() {
    local wanted="$1"
    [[ -f "$BASELINE_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        rt=$(echo "$line" | awk '{print $1}')
        t=$(echo "$line" | awk '{print $2}')
        if [[ "$rt" == "$wanted" ]]; then
            printf "%s" "$t"
            return 0
        fi
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
        for i in "${!FOUND_RUNTIMES[@]}"; do
            printf "%-12s  %s\n" "${FOUND_RUNTIMES[$i]}" "${CURRENT_TIMES[$i]}"
        done
    } > "$BASELINE_FILE"
    info "Baseline saved → $BASELINE_FILE"
}

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
    for i in "${!FOUND_RUNTIMES[@]}"; do
        printf "%-12s  %10.3f  %10s  %8s\n" "${FOUND_RUNTIMES[$i]}" "${CURRENT_TIMES[$i]}" "(new)" "baseline"
    done
else
    echo "=== Regression check (>${REGRESS_PCT}% slowdown = FAIL) ==="
    echo ""
    printf "%-12s  %10s  %10s  %8s  %s\n" "Runtime" "Current(s)" "Baseline(s)" "Delta%" "Status"
    printf "%-12s  %10s  %10s  %8s  %s\n" "------------" "----------" "-----------" "--------" "------"

    for i in "${!FOUND_RUNTIMES[@]}"; do
        rt="${FOUND_RUNTIMES[$i]}"
        cur="${CURRENT_TIMES[$i]}"
        base="$(baseline_for "$rt")"

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
    ref_time="${CURRENT_TIMES[0]}"
    for i in "${!FOUND_RUNTIMES[@]}"; do
        rt="${FOUND_RUNTIMES[$i]}"
        ratio=$(awk -v t="${CURRENT_TIMES[$i]}" -v r="$ref_time" \
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
