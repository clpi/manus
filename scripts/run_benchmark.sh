#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
CFLAGS="-O3 -Ofast -ffast-math -march=native -flto -fomit-frame-pointer -funroll-loops -ffp-contract=fast -fno-trapping-math -fno-math-errno -ffunction-sections -fdata-sections -Wl,-dead_strip -std=c99 -lm"

cd "$ROOT"
zig build
"$DUO" compile examples/benchmark.lua -o /tmp/duo_bench.out
$CC $CFLAGS -o /tmp/c_bench.out examples/benchmark_c.c

BENCHES=23

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

compare_results() {
  local duo_file="$1"
  local c_file="$2"
  awk -v benches="$BENCHES" '
    FNR == NR {
      if ($1 == "RESULT") {
        ++nd
        duo_id[nd] = $2
        duo_val[nd] = $3
      }
      next
    }
    {
      if ($1 == "RESULT") {
        ++nc
        c_id[nc] = $2
        c_val[nc] = $3
      }
    }
    END {
      if (nd != benches || nc != benches) {
        printf "RESULT count mismatch: Duo=%d C=%d (expected %d)\n", nd, nc, benches
        exit 1
      }
      fail = 0
      for (i = 1; i <= benches; i++) {
        if (duo_id[i] != c_id[i]) {
          printf "RESULT mismatch: id order differs (%s vs %s)\n", duo_id[i], c_id[i]
          fail = 1
          continue
        }
        a = duo_val[i]
        b = c_val[i]
        if (a == b) continue
        if (a ~ /^-?[0-9]+$/ && b ~ /^-?[0-9]+$/) {
          if (a != b) {
            printf "RESULT mismatch for %s: Duo=%s C=%s\n", duo_id[i], a, b
            fail = 1
          }
          continue
        }
        da = a + 0
        db = b + 0
        if (da != da || db != db) {
          printf "RESULT mismatch for %s: Duo=%s C=%s\n", duo_id[i], a, b
          fail = 1
          continue
        }
        abs_a = (da < 0 ? -da : da)
        abs_b = (db < 0 ? -db : db)
        if (abs_a < 1e-6 && abs_b < 1e-6) {
          if (abs_a - abs_b > 1e-12 && abs_b - abs_a > 1e-12) {
            printf "RESULT mismatch for %s: Duo=%s C=%s\n", duo_id[i], a, b
            fail = 1
          }
          continue
        }
        diff = (da > db ? da - db : db - da)
        base = (abs_b > abs_a ? abs_b : abs_a)
        tol = (base == 0 ? 1e-9 : base * 1e-6)
        if (tol < 1e-9) tol = 1e-9
        if (base > 1e6 && tol < 1) tol = 1
        if (diff > tol) {
          printf "RESULT mismatch for %s: Duo=%s C=%s\n", duo_id[i], a, b
          fail = 1
        }
      }
      exit fail
    }
  ' "$duo_file" "$c_file"
}

collect_min_times() {
  local cmd="$1"
  local runs=10
  local tmp
  tmp=$(mktemp)
  for _ in $(seq 1 "$runs"); do
    eval "$cmd" 2>/dev/null | extract_times >> "$tmp"
  done
  awk -v benches="$BENCHES" '
    {
      bench = ((NR - 1) % benches) + 1
      v = $1 + 0
      if (!(bench in min) || v < min[bench]) min[bench] = v
    }
    END {
      for (i = 1; i <= benches; i++) print min[i]
    }
  ' "$tmp"
  rm -f "$tmp"
}

echo "=== Correctness (RESULT lines) ==="
"$DUO" run examples/benchmark.lua > /tmp/duo_bench_results.txt 2>/dev/null
/tmp/c_bench.out > /tmp/c_bench_results.txt 2>/dev/null

RESULT_FAIL=0
if ! compare_results /tmp/duo_bench_results.txt /tmp/c_bench_results.txt; then
  RESULT_FAIL=1
fi

if [ "$RESULT_FAIL" -ne 0 ]; then
  echo
  echo "Benchmark failed: Duo results must match reference C."
  exit 1
fi
echo "All $BENCHES benchmark results match reference C."

echo
echo "=== Duo (Lua AOT) ==="
DUO_TIMES=$(collect_min_times "/tmp/duo_bench.out")

echo "=== Reference C ==="
C_TIMES=$(collect_min_times "/tmp/c_bench.out")

NAMES=(
  "Fibonacci(40)"
  "Prime sieve"
  "Mandelbrot"
  "Grid matrix"
  "N-body"
  "String bytes"
  "Table array"
  "Trig sum"
  "String chain"
  "String hash"
  "Math floor/max"
  "Table max"
  "Pow/sqrt"
  "Binary search"
  "Filter count"
  "Dot product"
  "Clamp sum"
  "Bucket hash"
  "EMA smooth"
  "Token count"
  "Config parse"
  "Table lookup"
  "Table churn"
)

FAIL=0
echo
printf "%-16s %12s %12s %8s\n" "Benchmark" "Duo(s)" "C(s)" "Winner"
printf "%-16s %12s %12s %8s\n" "----------------" "------------" "------------" "--------"

idx=0
while IFS='|' read -r d c; do
  idx=$((idx + 1))
  name="${NAMES[$((idx - 1))]:-bench-$idx}"
  winner=$(awk -v d="$d" -v c="$c" 'BEGIN {
    eps = (c > 0 ? c * 0.01 : 1e-7)
    if (c < 0.01) eps = (eps > 3e-5 ? eps : 3e-5)
    if (d + 0 <= c + eps) print "Duo"; else print "C"
  }')
  if [ "$winner" = "C" ]; then FAIL=1; fi
  printf "%-16s %12s %12s %8s\n" "$name" "$d" "$c" "$winner"
done < <(paste -d '|' <(echo "$DUO_TIMES") <(echo "$C_TIMES"))

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "Benchmark failed: Duo must beat or tie reference C on every test."
  exit 1
fi

echo
echo "All benchmarks: results match and Duo >= C"
