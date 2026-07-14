#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
RUNS="${RUNS:-5}"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)}"

cd "$ROOT"

if [ ! -x "$DUO" ]; then
    "${ZIG:-zig}" build
fi

DUO_SRC="/tmp/duo_compile_size.duo"
C_SRC="/tmp/duo_compile_size.c"
DUO_OUT="/tmp/duo_compile_size_duo"
C_OUT="/tmp/duo_compile_size_c"

cat > "$DUO_SRC" <<'DUO'
fun fib_iter(n: i64): i64
    a: i64 = 0
    b: i64 = 1
    i: i64 = 0
    while i < n
        t: i64 = a + b
        a = b
        b = t
        i += 1
    end
    a
end

fun checksum(n: i64): i64
    acc: i64 = 0
    i: i64 = 1
    while i <= n
        acc += (fib_iter(i % 40) * i) % 1000003
        i += 1
    end
    acc
end

print(checksum(200000))
DUO

cat > "$C_SRC" <<'C'
#include <stdint.h>
#include <stdio.h>

static inline int64_t fib_iter(int64_t n) {
    int64_t a = 0;
    int64_t b = 1;
    for (int64_t i = 0; i < n; ++i) {
        int64_t t = a + b;
        a = b;
        b = t;
    }
    return a;
}

static inline int64_t checksum(int64_t n) {
    int64_t acc = 0;
    for (int64_t i = 1; i <= n; ++i) {
        acc += (fib_iter(i % 40) * i) % 1000003;
    }
    return acc;
}

int main(void) {
    printf("%lld\n", (long long)checksum(200000));
    return 0;
}
C

time_command() {
    local label="$1"
    shift
    python3 - "$label" "$RUNS" "$@" <<'PY'
import subprocess
import sys
import time

label = sys.argv[1]
runs = int(sys.argv[2])
cmd = sys.argv[3:]
best = None
for _ in range(runs):
    start = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    elapsed = time.perf_counter() - start
    best = elapsed if best is None or elapsed < best else best
print(f"{label} {best:.6f}")
PY
}

echo "=== Compile Time + Binary Size Benchmark ==="
echo "Workload: typed Fibonacci checksum, runtime output only"
echo "Runs: $RUNS (minimum wall time)"
echo

duo_compile=$(time_command "duo_compile" "$DUO" compile "$DUO_SRC" -o "$DUO_OUT")
c_compile=$(time_command "c_compile" "$CC" -O3 -ffast-math -march=native -flto -fomit-frame-pointer -Wl,-dead_strip "$C_SRC" -o "$C_OUT")

duo_time=$(echo "$duo_compile" | awk '{print $2}')
c_time=$(echo "$c_compile" | awk '{print $2}')

duo_size=$(stat -f%z "$DUO_OUT" 2>/dev/null || stat -c%s "$DUO_OUT")
c_size=$(stat -f%z "$C_OUT" 2>/dev/null || stat -c%s "$C_OUT")

duo_result=$("$DUO_OUT")
c_result=$("$C_OUT")
if [ "$duo_result" != "$c_result" ]; then
    echo "RESULT mismatch: Duo=$duo_result C=$c_result"
    exit 1
fi

compile_ratio=$(awk "BEGIN { if ($c_time > 0) printf \"%.3f\", $duo_time / $c_time; else print \"N/A\" }")
size_ratio=$(awk "BEGIN { if ($c_size > 0) printf \"%.3f\", $duo_size / $c_size; else print \"N/A\" }")

printf "%-16s %12s %12s %10s\n" "Metric" "Duo" "C" "Ratio"
printf "%-16s %12s %12s %10s\n" "----------------" "------------" "------------" "----------"
printf "%-16s %12.6f %12.6f %10sx\n" "compile_s" "$duo_time" "$c_time" "$compile_ratio"
printf "%-16s %12d %12d %10sx\n" "binary_bytes" "$duo_size" "$c_size" "$size_ratio"
echo
echo "RESULT checksum $duo_result"
echo
echo "Note: this is a tracking benchmark. It reports the typed-program runtime"
echo "prelude cost and does not fail when Duo is slower or larger than C."
