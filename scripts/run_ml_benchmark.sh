#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
RUNS="${RUNS:-5}"
SLACK=1.05  # 5% tolerance (ML workloads have higher variance)
BENCHES=5
BENCH_NAMES="matmul_256 conv2d softmax_1k attention mlp_forward"
WORK_DIR="${ML_BENCH_WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/duo_ml_bench.XXXXXX")}"
KEEP_WORK_DIR=0

if [ -n "${ML_BENCH_WORK_DIR:-}" ]; then
    mkdir -p "$WORK_DIR"
    KEEP_WORK_DIR=1
fi

cleanup() {
    if [ "$KEEP_WORK_DIR" -eq 0 ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)}"

cd "$ROOT"

echo "========================================"
echo "     ML BENCHMARK: Duo vs C             "
echo "========================================"

# Build Duo compiler if needed
if [ ! -x "$DUO" ]; then
    echo "Building Duo compiler..."
    "${ZIG:-zig}" build
fi

# Compile Duo ML benchmark
echo "Compiling bench_ml.duo..."
DUO_BIN="$WORK_DIR/duo_ml_bench"
C_BIN="$WORK_DIR/c_ml_bench"
"$DUO" compile examples/bench_ml.duo -o "$DUO_BIN"

# Compile reference C ML benchmark
echo "Compiling bench_ml_c.c..."
$CC $CFLAGS -o "$C_BIN" examples/bench_ml_c.c

echo ""
echo "--- Correctness Check ---"

capture_result_lines() {
    local label="$1"
    local bin="$2"
    local out_file="$WORK_DIR/${label}.correctness.out"
    local err_file="$WORK_DIR/${label}.correctness.err"
    local result_file="$WORK_DIR/${label}.results"

    if ! "$bin" >"$out_file" 2>"$err_file"; then
        echo "$label correctness run failed" >&2
        echo "  command: $bin" >&2
        echo "  stdout: $out_file" >&2
        echo "  stderr: $err_file" >&2
        sed -n '1,40p' "$err_file" >&2
        return 1
    fi

    grep '^RESULT ' "$out_file" | sort >"$result_file" || true
    local rows
    rows=$(wc -l <"$result_file" | tr -d ' ')
    if [ "$rows" -ne "$BENCHES" ]; then
        echo "$label correctness run emitted $rows RESULT row(s), expected $BENCHES" >&2
        echo "  stdout: $out_file" >&2
        echo "  stderr: $err_file" >&2
        sed -n '1,60p' "$out_file" >&2
        sed -n '1,40p' "$err_file" >&2
        return 1
    fi

    cat "$result_file"
}

# Run both and capture RESULT lines
DUO_RESULTS="$(capture_result_lines duo "$DUO_BIN")"
C_RESULTS="$(capture_result_lines c "$C_BIN")"

# Compare RESULT lines (allow floating point tolerance)
FAIL=0

paste <(echo "$DUO_RESULTS") <(echo "$C_RESULTS") | while IFS=$'\t' read -r duo_line c_line; do
    duo_id=$(echo "$duo_line" | awk '{print $2}')
    duo_val=$(echo "$duo_line" | awk '{print $3}')
    c_id=$(echo "$c_line" | awk '{print $2}')
    c_val=$(echo "$c_line" | awk '{print $3}')

    if [ "$duo_id" != "$c_id" ]; then
        echo "MISMATCH: benchmark ID differs: Duo='$duo_id' vs C='$c_id'"
        exit 1
    fi
    match=$(awk "BEGIN { d=$duo_val; c=$c_val; diff=(d-c); if(diff<0) diff=-diff; denom=c; if(denom<0) denom=-denom; if(denom<1e-10) denom=1; rel=diff/denom; if(rel<0.0001) print 1; else print 0 }")
    if [ "$match" = "0" ]; then
        echo "MISMATCH: $duo_id: Duo=$duo_val vs C=$c_val"
        exit 1
    else
        echo "  OK: $duo_id = $duo_val"
    fi
done

echo ""
echo "All $BENCHES results match."
echo ""

# Timing runs
echo "--- Timing ($RUNS runs each) ---"
echo ""

# Extract time for a specific benchmark from output
extract_time() {
    local output="$1"
    local bench="$2"
    echo "$output" | awk -v b="$bench" '
        /^Running / { gsub(/\.\.\./, "", $2); cur = $2 }
        /^Time:/ && cur == b { print $2 }
    '
}

# Initialize min arrays using file-based approach
for name in $BENCH_NAMES; do
    echo "999999.0" > "$WORK_DIR/ml_bench_duo_min_$name"
    echo "999999.0" > "$WORK_DIR/ml_bench_c_min_$name"
done

capture_timing_run() {
    local label="$1"
    local bin="$2"
    local run="$3"
    local out_file="$WORK_DIR/${label}.timing.${run}.out"
    local err_file="$WORK_DIR/${label}.timing.${run}.err"

    if ! "$bin" >"$out_file" 2>"$err_file"; then
        echo "$label timing run $run failed" >&2
        echo "  command: $bin" >&2
        echo "  stdout: $out_file" >&2
        echo "  stderr: $err_file" >&2
        sed -n '1,40p' "$err_file" >&2
        return 1
    fi

    for name in $BENCH_NAMES; do
        local t
        t=$(extract_time "$(cat "$out_file")" "$name")
        if [ -z "$t" ]; then
            echo "$label timing run $run did not report Time for $name" >&2
            echo "  stdout: $out_file" >&2
            echo "  stderr: $err_file" >&2
            sed -n '1,80p' "$out_file" >&2
            return 1
        fi
        local cur_file="$WORK_DIR/ml_bench_${label}_min_$name"
        local cur
        cur=$(cat "$cur_file")
        local new
        new=$(awk "BEGIN { if ($t < $cur) print $t; else print $cur }")
        echo "$new" > "$cur_file"
    done
}

# Run Duo multiple times
echo "Running Duo ($RUNS times)..."
for run in $(seq 1 $RUNS); do
    capture_timing_run duo "$DUO_BIN" "$run"
done

# Run C multiple times
echo "Running C ($RUNS times)..."
for run in $(seq 1 $RUNS); do
    capture_timing_run c "$C_BIN" "$run"
done

echo ""
echo "--- Results (min of $RUNS runs) ---"
echo ""
printf "%-16s %12s %12s %10s\n" "Benchmark" "Duo(s)" "C(s)" "Ratio"
printf "%-16s %12s %12s %10s\n" "----------------" "------------" "------------" "----------"

TIMING_FAIL=0
for name in $BENCH_NAMES; do
    d=$(cat "$WORK_DIR/ml_bench_duo_min_$name")
    c=$(cat "$WORK_DIR/ml_bench_c_min_$name")
    ratio=$(awk "BEGIN { if ($c > 0) printf \"%.3f\", $d / $c; else print \"N/A\" }")
    printf "%-16s %12.6f %12.6f %10s\n" "$name" "$d" "$c" "${ratio}x"

    # Check: Duo must beat or tie C (with 5% slack)
    pass=$(awk "BEGIN { if ($d <= $c * $SLACK) print 1; else print 0 }")
    if [ "$pass" = "0" ]; then
        echo "  *** WARN: Duo ($d) slower than C ($c) — optimization target"
        TIMING_FAIL=$((TIMING_FAIL + 1))
    fi
done

echo ""
if [ "$TIMING_FAIL" -gt 0 ]; then
    echo "ML BENCHMARK: $TIMING_FAIL workload(s) slower than C (optimization targets)."
    echo "  (Core 40-benchmark gate: zig build bench)"
    exit 0
fi

echo "ALL ML BENCHMARKS PASSED: Duo beats or ties C on all ML workloads."
exit 0
