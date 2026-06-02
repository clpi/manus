#!/usr/bin/env bash
# Cross-language benchmark: Duo (Lua AOT) vs C vs Lua vs LuaJIT
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
LUA="${LUA:-lua}"
LUAJIT="${LUAJIT:-luajit}"
CFLAGS="-O3 -ffast-math -march=native -flto -fomit-frame-pointer -funroll-loops -ffp-contract=fast -fno-trapping-math -fno-math-errno -ffunction-sections -fdata-sections -Wl,-dead_strip -std=c99 -lm"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)}"

cd "$ROOT"
if [ ! -x "$DUO" ]; then
    echo "Building Duo compiler..."
    /tmp/zig-0.17.0-dir/zig-aarch64-macos-0.17.0-dev.644+3de725074/zig build
fi

echo "Compiling Duo binary..."
"$DUO" compile examples/benchmark.lua -o /tmp/duo_bench.out 2>/dev/null

echo "Compiling reference C binary..."
$CC $CFLAGS -o /tmp/c_bench.out examples/benchmark_c.c

PURE_LUA="$ROOT/examples/benchmark_pure.lua"

BENCHES=23
OUTDIR=$(mktemp -d)
trap 'rm -rf "$OUTDIR"' EXIT

run_once() {
    local label="$1" cmd="$2"
    local out="$OUTDIR/$label"
    mkdir -p "$out"
    eval "$cmd" 2>/dev/null > "$out/results.txt" || true
}

extract_times() {
    awk '/Time/ {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+(\.[0-9]+)?(e-?[0-9]+)?$/) { print $i; break }
        }
    }' | head -"$BENCHES"
}

extract_results() {
    awk '/^RESULT / { print $2, $3 }'
}

collect_min_times() {
    local cmd="$1"
    local runs=3
    local tmp; tmp=$(mktemp)
    for _ in $(seq 1 "$runs"); do
        eval "$cmd" 2>/dev/null | extract_times >> "$tmp"
    done
    awk -v benches="$BENCHES" '
    {
        bench = ((NR - 1) % benches) + 1
        v = $1 + 0
        if (!(bench in min) || v < min[bench]) min[bench] = v
    }
    END { for (i = 1; i <= benches; i++) print min[i] }
    ' "$tmp"
    rm -f "$tmp"
}

BENCH_IDS=(
    fib primes mandel grid nbody
    str_bytes table_sum trig str_chain str_hash
    floor_max table_max pow_sqrt bsearch filter
    dot clamp bucket ema token
    parse lookup churn
)

BENCH_NAMES=(
    "Fibonacci(40)" "Prime sieve" "Mandelbrot" "Grid matrix" "N-body"
    "String bytes" "Table array" "Trig sum" "String chain" "String hash"
    "Math floor/max" "Table max" "Pow/sqrt" "Binary search" "Filter count"
    "Dot product" "Clamp sum" "Bucket hash" "EMA smooth" "Token count"
    "Config parse" "Table lookup" "Table churn"
)

echo "=============================================="
echo "     Cross-Language Performance Benchmark     "
echo "=============================================="
echo ""

# ---- Correctness ----
echo "=== Correctness (RESULT lines vs reference C) ==="
run_once duo    "/tmp/duo_bench.out"
run_once refc   "/tmp/c_bench.out"

# Fix Lua benchmark for Lua 5.5 (math.pow removed)
FIXED_LUA=$(mktemp)
sed 's/math\.pow(\(.*\), \(.*\))/\1 ^ \2/g' "$PURE_LUA" > "$FIXED_LUA"

run_once lua    "$LUA $FIXED_LUA"
run_once luajit "$LUAJIT $FIXED_LUA"

FAIL=0

# Check that Duo's results match reference C (strict: required for CI gate)
echo "  C vs Duo:"
if ! awk \
    'FNR==NR{r_vals[$1]=$2;next}{t_vals[$1]=$2}
    END{f=0;for(k in r_vals){
        a=r_vals[k]+0;b=t_vals[k]+0
        diff=(a>b?a-b:b-a)
        if(a!=""&&b!=""&&(a+0)==int(a)&&(b+0)==int(b)){if(a!=b){print "    MISMATCH",k":"a" vs"b;f=1}}
        else if(diff>1e-4){print "    FLOAT DIFF",k":"a" vs"b;f=1}
    }exit f}' \
    <(extract_results < "$OUTDIR/refc/results.txt") \
    <(extract_results < "$OUTDIR/duo/results.txt"); then
    FAIL=1
else
    echo "    PASS"
fi

# For Lua/LuaJIT: compare only integer results exactly, report but don't fail on float diffs
compare_loose() {
    local label="$1" file="$2"
    echo "  C vs $label:"
    awk \
        'FNR==NR{r_vals[$1]=$2;next}{t_vals[$1]=$2}
        END{f=0;for(k in r_vals){
            a=r_vals[k];b=t_vals[k]
            if(a!=""&&b!=""&&(a+0)==int(a)&&(b+0)==int(b)&&a!=b){
                print "    MISMATCH",k":"a" vs"b;f=1
            }
        }exit f}' \
        <(extract_results < "$OUTDIR/refc/results.txt") \
        <(extract_results < "$file") && echo "    PASS" || true
}

compare_loose "Lua"    "$OUTDIR/lua/results.txt"
compare_loose "LuaJIT" "$OUTDIR/luajit/results.txt"

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "Cross-language benchmark FAILED: Duo must match reference C."
    exit 1
fi

echo ""

# ---- Timing ----
echo "=== Timing (minimum of 3 runs, seconds) ==="

echo "  Timing Duo..."
DUO_TIMES=$(collect_min_times "/tmp/duo_bench.out")
echo "  Timing C..."
C_TIMES=$(collect_min_times "/tmp/c_bench.out")
echo "  Timing Lua..."
LUA_TIMES=$(collect_min_times "$LUA $FIXED_LUA")
echo "  Timing LuaJIT..."
LUAJIT_TIMES=$(collect_min_times "$LUAJIT $FIXED_LUA")

printf "\n%-16s %10s %10s %10s %10s\n" "Benchmark" "Duo(s)" "C(s)" "Lua(s)" "LuaJIT"
printf "%-16s %10s %10s %10s %10s\n" "----------------" "----------" "----------" "----------" "----------"

idx=0
while IFS='|' read -r d c l lj; do
    idx=$((idx + 1))
    name="${BENCH_NAMES[$((idx - 1))]:-bench-$idx}"
    printf "%-16s %10.6f %10.6f %10.6f %10.6f\n" "$name" "$d" "$c" "$l" "$lj"
done < <(paste -d '|' <(echo "$DUO_TIMES") <(echo "$C_TIMES") <(echo "$LUA_TIMES") <(echo "$LUAJIT_TIMES"))

echo ""
echo "=== Summary (geometric mean speedup) ==="
paste -d '|' <(echo "$DUO_TIMES") <(echo "$C_TIMES") <(echo "$LUA_TIMES") <(echo "$LUAJIT_TIMES") | awk -F'|' '
{
    d=$1+0; c=$2+0; l=$3+0; j=$4+0
    if(d>0&&c>0){dc+=log(c/d);dl+=log(l/d);dj+=log(j/d);cnt++}
}
END{
    printf "Duo vs C:       %.0fx faster\n", exp(dc/cnt)
    printf "Duo vs Lua:     %.0fx faster\n", exp(dl/cnt)
    printf "Duo vs LuaJIT:  %.0fx faster\n", exp(dj/cnt)
}'
