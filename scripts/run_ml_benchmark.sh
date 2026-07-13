#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
RUNS=5
SLACK=1.05  # 5% tolerance (ML workloads have higher variance)

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
"$DUO" compile examples/bench_ml.duo -o /tmp/duo_ml_bench

# Compile reference C ML benchmark
echo "Compiling bench_ml_c.c..."
$CC $CFLAGS -o /tmp/c_ml_bench examples/bench_ml_c.c

echo ""
echo "--- Correctness Check ---"

# Run both and capture RESULT lines
DUO_RESULTS=$(/tmp/duo_ml_bench | grep '^RESULT ' | sort)
C_RESULTS=$(/tmp/c_ml_bench | grep '^RESULT ' | sort)

# Compare RESULT lines (allow floating point tolerance)
BENCHES=5
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

BENCH_NAMES="matmul_256 conv2d softmax_1k attention mlp_forward"

# Initialize min arrays using file-based approach
for name in $BENCH_NAMES; do
    echo "999999.0" > "/tmp/ml_bench_duo_min_$name"
    echo "999999.0" > "/tmp/ml_bench_c_min_$name"
done

# Run Duo multiple times
echo "Running Duo ($RUNS times)..."
for run in $(seq 1 $RUNS); do
    output=$(/tmp/duo_ml_bench)
    for name in $BENCH_NAMES; do
        t=$(extract_time "$output" "$name")
        cur=$(cat "/tmp/ml_bench_duo_min_$name")
        new=$(awk "BEGIN { if ($t < $cur) print $t; else print $cur }")
        echo "$new" > "/tmp/ml_bench_duo_min_$name"
    done
done

# Run C multiple times
echo "Running C ($RUNS times)..."
for run in $(seq 1 $RUNS); do
    output=$(/tmp/c_ml_bench)
    for name in $BENCH_NAMES; do
        t=$(extract_time "$output" "$name")
        cur=$(cat "/tmp/ml_bench_c_min_$name")
        new=$(awk "BEGIN { if ($t < $cur) print $t; else print $cur }")
        echo "$new" > "/tmp/ml_bench_c_min_$name"
    done
done

echo ""
echo "--- Results (min of $RUNS runs) ---"
echo ""
printf "%-16s %12s %12s %10s\n" "Benchmark" "Duo(s)" "C(s)" "Ratio"
printf "%-16s %12s %12s %10s\n" "----------------" "------------" "------------" "----------"

TIMING_FAIL=0
for name in $BENCH_NAMES; do
    d=$(cat "/tmp/ml_bench_duo_min_$name")
    c=$(cat "/tmp/ml_bench_c_min_$name")
    ratio=$(awk "BEGIN { if ($c > 0) printf \"%.3f\", $d / $c; else print \"N/A\" }")
    printf "%-16s %12.6f %12.6f %10s\n" "$name" "$d" "$c" "${ratio}x"

    # Check: Duo must beat or tie C (with 5% slack)
    pass=$(awk "BEGIN { if ($d <= $c * $SLACK) print 1; else print 0 }")
    if [ "$pass" = "0" ]; then
        echo "  *** WARN: Duo ($d) slower than C ($c) — optimization target"
        TIMING_FAIL=$((TIMING_FAIL + 1))
    fi
done

# Clean up temp files
for name in $BENCH_NAMES; do
    rm -f "/tmp/ml_bench_duo_min_$name" "/tmp/ml_bench_c_min_$name"
done

echo ""
if [ "$TIMING_FAIL" -gt 0 ]; then
    echo "ML BENCHMARK: $TIMING_FAIL workload(s) slower than C (optimization targets)."
    echo "  (Core 40-benchmark gate: zig build bench)"
    exit 0
fi

echo "ALL ML BENCHMARKS PASSED: Duo beats or ties C on all ML workloads."
exit 0
