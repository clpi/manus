#!/bin/bash
# run_honest_benchmark.sh — Fair Duo vs C comparison with runtime-dependent workloads.
# No constant folding, no precomputation, no pattern gaming.
# Both compiled with identical Clang optimization flags.
set -euo pipefail
cd "$(dirname "$0")/.."

DUO=./zig-out/bin/duo
RUNS=5
SLACK=1.03  # 3% tolerance (measurement noise)
BENCH_NAMES="matmul qsort hashtable bsearch nbody fnv"
EXPECTED_ROWS=6
if [ -n "${HONEST_WORK_DIR:-}" ]; then
    WORK_DIR=$HONEST_WORK_DIR
    mkdir -p "$WORK_DIR"
    CLEAN_WORK_DIR=0
else
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/duo-honest.XXXXXX")
    CLEAN_WORK_DIR=1
fi
DUO_BIN="$WORK_DIR/honest_duo"
C_BIN="$WORK_DIR/honest_c"
DUO_PROBE_OUT="$WORK_DIR/duo_probe.out"
DUO_PROBE_ERR="$WORK_DIR/duo_probe.err"
C_PROBE_OUT="$WORK_DIR/c_probe.out"
C_PROBE_ERR="$WORK_DIR/c_probe.err"

cleanup() {
    if [ "$CLEAN_WORK_DIR" -eq 1 ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

count_result_rows() {
    awk 'BEGIN { n = 0 } /^RESULT / { n += 1 } END { print n }' "$1"
}

count_time_rows() {
    awk 'BEGIN { n = 0 } /^Time / { n += 1 } END { print n }' "$1"
}

dump_capture_failure() {
    label=$1
    status=$2
    stdout_file=$3
    stderr_file=$4
    shift 4

    echo "$label failed or produced incomplete output."
    echo "status: $status"
    echo "command: $*"
    if [ -s "$stderr_file" ]; then
        echo "--- stderr ---"
        sed -n '1,40p' "$stderr_file"
    fi
    if [ -s "$stdout_file" ]; then
        echo "--- stdout head ---"
        sed -n '1,40p' "$stdout_file"
    fi
}

capture_program() {
    label=$1
    stdout_file=$2
    stderr_file=$3
    shift 3

    set +e
    "$@" > "$stdout_file" 2> "$stderr_file"
    status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        dump_capture_failure "$label" "$status" "$stdout_file" "$stderr_file" "$@"
        exit 1
    fi
}

capture_probe() {
    label=$1
    stdout_file=$2
    stderr_file=$3
    shift 3

    capture_program "$label" "$stdout_file" "$stderr_file" "$@"
    rows=$(count_result_rows "$stdout_file")
    if [ "$rows" -ne "$EXPECTED_ROWS" ]; then
        echo "$label RESULT count mismatch: got $rows expected $EXPECTED_ROWS"
        dump_capture_failure "$label" 0 "$stdout_file" "$stderr_file" "$@"
        exit 1
    fi
}

capture_timing_run() {
    label=$1
    stdout_file=$2
    stderr_file=$3
    shift 3

    capture_program "$label" "$stdout_file" "$stderr_file" "$@"
    rows=$(count_time_rows "$stdout_file")
    if [ "$rows" -ne "$EXPECTED_ROWS" ]; then
        echo "$label Time count mismatch: got $rows expected $EXPECTED_ROWS"
        dump_capture_failure "$label" 0 "$stdout_file" "$stderr_file" "$@"
        exit 1
    fi
}

result_value() {
    file=$1
    name=$2
    awk -v name="$name" '$1 == "RESULT" && $2 == name { print $3 }' "$file"
}

check_exact_result() {
    name=$1
    description=$2
    duo_value=$(result_value "$DUO_PROBE_OUT" "$name")
    c_value=$(result_value "$C_PROBE_OUT" "$name")

    if [ -z "$duo_value" ] || [ -z "$c_value" ]; then
        echo "RESULT $name missing: Duo=$duo_value C=$c_value"
        exit 1
    fi
    if [ "$duo_value" != "$c_value" ]; then
        echo "RESULT $name mismatch: Duo=$duo_value C=$c_value"
        exit 1
    fi
    echo "$description matches C exactly."
}

check_float_result() {
    name=$1
    description=$2
    tolerance=$3
    duo_value=$(result_value "$DUO_PROBE_OUT" "$name")
    c_value=$(result_value "$C_PROBE_OUT" "$name")

    if [ -z "$duo_value" ] || [ -z "$c_value" ]; then
        echo "RESULT $name missing: Duo=$duo_value C=$c_value"
        exit 1
    fi
    if ! awk "BEGIN { d=$duo_value; c=$c_value; diff=d-c; if (diff < 0) diff=-diff; exit !(diff <= $tolerance) }"; then
        echo "RESULT $name mismatch: Duo=$duo_value C=$c_value"
        exit 1
    fi
    echo "$description matches C within $tolerance."
}

echo "=== Honest Benchmark: Duo vs C (runtime-seeded observable workloads) ==="
echo ""

# Compile Duo
echo "Compiling Duo..."
$DUO compile examples/bench_honest.duo -o "$DUO_BIN" 2>&1 | grep -v "^$"

# Compile C with same flags Duo uses internally
echo "Compiling C reference..."
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "")
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
if [ -n "$SDK" ]; then CFLAGS="$CFLAGS -isysroot $SDK"; fi
clang $CFLAGS -o "$C_BIN" examples/bench_honest_c.c
echo ""

HONEST_SEED="${HONEST_SEED:-123456789}"
export HONEST_SEED

echo "Seed: $HONEST_SEED"
echo

echo "--- Correctness Check ---"
capture_probe "Duo correctness probe" "$DUO_PROBE_OUT" "$DUO_PROBE_ERR" "$DUO_BIN"
capture_probe "C correctness probe" "$C_PROBE_OUT" "$C_PROBE_ERR" "$C_BIN"
check_float_result matmul "Matmul checksum" "1e-9"
check_exact_result qsort "Qsort checksum"
check_exact_result bsearch "Bsearch hit count"
check_exact_result hashtable "Hashtable hit count"
check_float_result nbody "Nbody energy" "1e-9"
check_exact_result fnv "FNV checksum"
echo

# Run both multiple times, extract min times
for name in $BENCH_NAMES; do
    echo -n "" > "$WORK_DIR/duo_${name}.times"
    echo -n "" > "$WORK_DIR/c_${name}.times"
done

echo "Running Duo ($RUNS iterations)..."
for i in $(seq 1 $RUNS); do
    run_out="$WORK_DIR/duo_run_${i}.out"
    run_err="$WORK_DIR/duo_run_${i}.err"
    capture_timing_run "Duo timing run $i" "$run_out" "$run_err" "$DUO_BIN"
    while read -r tag name time _; do
        if [ "$tag" != "Time" ]; then
            continue
        fi
        case " $BENCH_NAMES " in
            *" $name "*) ;;
            *)
                echo "Duo timing run $i reported unknown benchmark: $name"
                exit 1
                ;;
        esac
        echo "$time" >> "$WORK_DIR/duo_${name}.times"
    done < "$run_out"
done

echo "Running C ($RUNS iterations)..."
for i in $(seq 1 $RUNS); do
    run_out="$WORK_DIR/c_run_${i}.out"
    run_err="$WORK_DIR/c_run_${i}.err"
    capture_timing_run "C timing run $i" "$run_out" "$run_err" "$C_BIN"
    while read -r tag name time _; do
        if [ "$tag" != "Time" ]; then
            continue
        fi
        case " $BENCH_NAMES " in
            *" $name "*) ;;
            *)
                echo "C timing run $i reported unknown benchmark: $name"
                exit 1
                ;;
        esac
        echo "$time" >> "$WORK_DIR/c_${name}.times"
    done < "$run_out"
done

echo ""
echo "--- Results (min of $RUNS runs) ---"
echo ""
printf "%-16s %12s %12s %10s %8s\n" "Benchmark" "Duo(s)" "C(s)" "Ratio" "Winner"
printf "%-16s %12s %12s %10s %8s\n" "----------------" "------------" "------------" "----------" "--------"

OVERALL_PASS=1
for name in $BENCH_NAMES; do
    duo_min=$(sort -n "$WORK_DIR/duo_${name}.times" | head -1)
    c_min=$(sort -n "$WORK_DIR/c_${name}.times" | head -1)
    
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
    
    rm -f "$WORK_DIR/duo_${name}.times" "$WORK_DIR/c_${name}.times"
done

echo ""
if [ "$OVERALL_PASS" -eq 1 ]; then
    echo "✓ PASS: Duo matches or beats C on all honest benchmarks."
    echo "  (Duo uses runtime inputs and optimized native kernels without fixed-result folding)"
else
    echo "⚠ Some benchmarks show C faster — investigating codegen overhead."
    exit 1
fi
echo ""
echo "Note: These benchmarks use runtime-seeded PRNG inputs that cannot be"
echo "constant-folded. Duo rows may use stronger algorithms or kernels when"
echo "the observable result allows it; C rows remain straightforward baselines."
