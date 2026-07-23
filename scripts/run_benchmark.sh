#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
CFLAGS="-O3 -ffast-math -march=native -flto -fomit-frame-pointer -funroll-loops -ffp-contract=fast -fno-trapping-math -fno-math-errno -ffunction-sections -fdata-sections -Wl,-dead_strip -std=c99 -lm"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)}"

cd "$ROOT"
if [ ! -x "$DUO" ]; then
  "${ZIG:-zig}" build
fi

# Compile Lua-flavoured Duo benchmark with PGO (two-pass: instrument, profile, optimise).
"$DUO" compile --pgo -O3 examples/benchmark.lua -o /tmp/duo_bench.out &
DUO_COMP_PID=$!

# Compile reference C benchmark with PGO.
# Pass 1: instrument.
$CC $CFLAGS -fprofile-instr-generate -o /tmp/c_bench_instr.out examples/benchmark_c.c
# Collect profile.
env LLVM_PROFILE_FILE=/tmp/c_bench.profraw /tmp/c_bench_instr.out > /dev/null 2>&1 || true
# Merge.
xcrun llvm-profdata merge -output=/tmp/c_bench.profdata /tmp/c_bench.profraw
# Pass 2: optimise.
$CC $CFLAGS -fprofile-instr-use=/tmp/c_bench.profdata -o /tmp/c_bench.out examples/benchmark_c.c &
CC_COMP_PID=$!

wait $DUO_COMP_PID
wait $CC_COMP_PID

# The PGO implementation uses a fixed temporary profile path, so compile the
# .duo mirror after the .lua driver has finished profiling.
"$DUO" compile --pgo -O3 examples/benchmark.duo -o /tmp/duo_bench_duo.out

BENCHES=40

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

count_results() {
  awk '/^RESULT / { n++ } END { print n + 0 }' "$1"
}

capture_results() {
  local label="$1"
  local out="$2"
  shift 2
  local err="${out}.err"
  local attempt
  local status=0
  local count=0

  for attempt in 1 2; do
    status=0
    "$@" > "$out" 2>"$err" || status=$?
    count=$(count_results "$out")
    if [ "$status" -eq 0 ] && [ "$count" -eq "$BENCHES" ]; then
      rm -f "$err"
      return 0
    fi
    if [ "$attempt" -eq 1 ]; then
      echo "warning: $label produced $count/$BENCHES RESULT rows (status $status), retrying..." >&2
    fi
  done

  echo "error: $label produced $count/$BENCHES RESULT rows after retry (status $status)" >&2
  echo "error: command: $*" >&2
  if [ -s "$err" ]; then
    echo "error: stderr from $label:" >&2
    sed -n '1,40p' "$err" >&2
  fi
  return 1
}

echo "=== Correctness (RESULT lines) ==="
capture_results "Duo benchmark.lua" /tmp/duo_bench_results.txt "$DUO" run examples/benchmark.lua
capture_results "Duo benchmark.duo" /tmp/duo_bench_duo_results.txt "$DUO" run examples/benchmark.duo
capture_results "reference C benchmark" /tmp/c_bench_results.txt /tmp/c_bench.out

RESULT_FAIL=0
if ! compare_results /tmp/duo_bench_results.txt /tmp/c_bench_results.txt; then
  RESULT_FAIL=1
fi
if ! compare_results /tmp/duo_bench_duo_results.txt /tmp/c_bench_results.txt; then
  RESULT_FAIL=1
fi

if [ "$RESULT_FAIL" -ne 0 ]; then
  echo
  echo "Benchmark failed: Duo .lua and .duo results must match reference C."
  exit 1
fi
echo "All $BENCHES benchmark results match reference C for .lua and .duo."

# Compile timer.so for high resolution timing in Lua 5.5 and LuaJIT
cat << 'EOF' > /tmp/timer.c
#include <sys/time.h>
#include <lua.h>
#include <lauxlib.h>
static int l_now(lua_State *L) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    lua_pushnumber(L, (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0);
    return 1;
}
int luaopen_timer(lua_State *L) {
    lua_pushcfunction(L, l_now);
    return 1;
}
EOF
clang -shared -undefined dynamic_lookup -o /tmp/timer.so /tmp/timer.c 2>/dev/null || true

# Prepare untyped benchmark script for standard Lua
sed -E 's/:[ ]*[a-zA-Z0-9_]+//g' examples/benchmark.lua > /tmp/lua_bench.lua
# Inject high-res timer override safely
sed -i '' '1i\
local ok, t = pcall(require, "timer"); if ok and type(t) == "function" then os.clock = t end\
' /tmp/lua_bench.lua

echo
echo "=== Duo (Lua AOT) ==="
DUO_TIMES=$(collect_min_times "/tmp/duo_bench.out")

echo "=== Duo (.duo AOT) ==="
DUO_FILE_TIMES=$(collect_min_times "/tmp/duo_bench_duo.out")

echo "=== Reference C ==="
C_TIMES=$(collect_min_times "/tmp/c_bench.out")

echo "=== LuaJIT ==="
LUAJIT_TIMES=$(LUA_CPATH="/tmp/?.so;;" collect_min_times "luajit /tmp/lua_bench.lua")

echo "=== Lua 5.5 ==="
LUA55_TIMES=$(LUA_CPATH="/tmp/?.so;;" collect_min_times "lua /tmp/lua_bench.lua")

echo "=== Nelua ==="
# Note: Nelua may fail to compile the untyped bench if it uses generic tables, but we run it anyway
NELUA_TIMES=$(collect_min_times "nelua /tmp/lua_bench.lua 2>/dev/null || true")

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
  "Matrix multiply"
  "Prefix sum"
  "GCD reduce"
  "Collatz sum"
  "XOR fold"
  "Ring buffer"
  "Cond swap"
  "Ackermann"
  "Levenshtein"
  "Sieve"
  "Fenwick tree"
  "Interpolation"
  "Run-length"
  "Bitcount"
  "CORDIC sin"
  "Sparse dot"
  "Game of Life"
)

FAIL=0
echo
printf "%-16s %12s %12s %12s %12s %12s %12s %8s\n" "Benchmark" "DuoLua(s)" "DuoDuo(s)" "C(s)" "LuaJIT(s)" "Lua5.5(s)" "Nelua(s)" "Winner"
printf "%-16s %12s %12s %12s %12s %12s %12s %8s\n" "----------------" "------------" "------------" "------------" "------------" "------------" "------------" "--------"

idx=0
while IFS='|' read -r d duo_file c lj l5 n; do
  idx=$((idx + 1))
  name="${NAMES[$((idx - 1))]:-bench-$idx}"
  winner=$(awk -v d="$d" -v duo_file="$duo_file" -v c="$c" 'BEGIN {
    eps = (c > 0 ? c * 0.05 : 1e-7)
    if (c < 0.01) eps = (eps > 5e-5 ? eps : 5e-5)
    if (d + 0 <= c + eps && duo_file + 0 <= c + eps) print "Duo"; else print "C"
  }')
  if [ "$winner" = "C" ]; then FAIL=1; fi
  # If a compiler fails, its time might be empty. Format gracefully.
  d_fmt=$(printf "%g" "$d" 2>/dev/null || echo "N/A")
  duo_file_fmt=$(printf "%g" "$duo_file" 2>/dev/null || echo "N/A")
  c_fmt=$(printf "%g" "$c" 2>/dev/null || echo "N/A")
  lj_fmt=$(printf "%g" "$lj" 2>/dev/null || echo "N/A")
  l5_fmt=$(printf "%g" "$l5" 2>/dev/null || echo "N/A")
  n_fmt=$(printf "%g" "$n" 2>/dev/null || echo "N/A")
  if [ -z "$duo_file" ]; then duo_file_fmt="N/A"; fi
  if [ -z "$lj" ]; then lj_fmt="N/A"; fi
  if [ -z "$l5" ]; then l5_fmt="N/A"; fi
  if [ -z "$n" ]; then n_fmt="N/A"; fi

  printf "%-16s %12s %12s %12s %12s %12s %12s %8s\n" "$name" "$d_fmt" "$duo_file_fmt" "$c_fmt" "$lj_fmt" "$l5_fmt" "$n_fmt" "$winner"
done < <(paste -d '|' <(echo "$DUO_TIMES") <(echo "$DUO_FILE_TIMES") <(echo "$C_TIMES") <(echo "$LUAJIT_TIMES") <(echo "$LUA55_TIMES") <(echo "$NELUA_TIMES"))

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "Benchmark failed: Duo .lua and .duo must beat or tie reference C on every test."
  exit 1
fi

echo
echo "All benchmarks: results match and Duo .lua/.duo >= C"
