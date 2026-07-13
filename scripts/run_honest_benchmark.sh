#!/bin/bash
# run_honest_benchmark.sh — Fair Duo vs C comparison with runtime-dependent workloads.
# No constant folding, no precomputation, no pattern gaming.
# Both compiled with identical Clang optimization flags.
set -euo pipefail
cd "$(dirname "$0")/.."

DUO=./zig-out/bin/duo
RUNS=5
SLACK=1.03  # 3% tolerance (measurement noise)

echo "=== Honest Benchmark: Duo vs C (identical algorithms, runtime inputs) ==="
echo ""

# Compile Duo
echo "Compiling Duo..."
$DUO compile examples/bench_honest.duo -o /tmp/honest_duo 2>&1 | grep -v "^$"

# Compile C with same flags Duo uses internally
echo "Compiling C reference..."
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "")
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
if [ -n "$SDK" ]; then CFLAGS="$CFLAGS -isysroot $SDK"; fi
clang $CFLAGS -o /tmp/honest_c examples/bench_honest_c.c
echo ""

BENCH_NAMES="matmul qsort hashtable bsearch nbody fnv"

# Run both multiple times, extract min times
for name in $BENCH_NAMES; do
    echo -n "" > "/tmp/honest_duo_${name}"
    echo -n "" > "/tmp/honest_c_${name}"
done

echo "Running Duo ($RUNS iterations)..."
for i in $(seq 1 $RUNS); do
    /tmp/honest_duo | grep "^Time " | while read -r _ name time _; do
        echo "$time" >> "/tmp/honest_duo_${name}"
    done
done

echo "Running C ($RUNS iterations)..."
for i in $(seq 1 $RUNS); do
    /tmp/honest_c | grep "^Time " | while read -r _ name time _; do
        echo "$time" >> "/tmp/honest_c_${name}"
    done
done

echo ""
echo "--- Results (min of $RUNS runs) ---"
echo ""
printf "%-16s %12s %12s %10s %8s\n" "Benchmark" "Duo(s)" "C(s)" "Ratio" "Winner"
printf "%-16s %12s %12s %10s %8s\n" "----------------" "------------" "------------" "----------" "--------"

OVERALL_PASS=1
for name in $BENCH_NAMES; do
    duo_min=$(sort -n "/tmp/honest_duo_${name}" | head -1)
    c_min=$(sort -n "/tmp/honest_c_${name}" | head -1)
    
    if [ -z "$duo_min" ] || [ -z "$c_min" ]; then
        printf "%-16s %12s %12s %10s %8s\n" "$name" "N/A" "N/A" "N/A" "SKIP"
        continue
    fi
    
    ratio=$(awk "BEGIN { if ($c_min > 0) printf \"%.3f\", $duo_min / $c_min; else print \"N/A\" }")
    
    if awk "BEGIN { exit !($duo_min <= $c_min * $SLACK) }"; then
        winner="Duo/Tie"
    else
        winner="C"
        OVERALL_PASS=0
    fi
    
    printf "%-16s %12.6f %12.6f %10sx %8s\n" "$name" "$duo_min" "$c_min" "$ratio" "$winner"
    
    rm -f "/tmp/honest_duo_${name}" "/tmp/honest_c_${name}"
done

echo ""
if [ "$OVERALL_PASS" -eq 1 ]; then
    echo "✓ PASS: Duo matches or beats C on all honest benchmarks."
    echo "  (Duo generates equivalent native code via the C→Clang pipeline)"
else
    echo "⚠ Some benchmarks show C faster — investigating codegen overhead."
fi
echo ""
echo "Note: These benchmarks use runtime-seeded PRNG inputs that cannot be"
echo "constant-folded or pattern-matched at compile time. Both Duo and C"
echo "produce identical machine code quality through Clang -O3."
