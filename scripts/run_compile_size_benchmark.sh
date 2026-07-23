#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
STRIP="${STRIP:-strip}"
RUNS="${RUNS:-5}"
CHAIN_FUNCS_1K="${CHAIN_FUNCS_1K:-${CHAIN_FUNCS:-180}}"
CHAIN_FUNCS_10K="${CHAIN_FUNCS_10K:-1500}"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)}"

cd "$ROOT"

if [ ! -x "$DUO" ]; then
    "${ZIG:-zig}" build
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/duo_compile_size.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ "$(uname -s)" = "Darwin" ]; then
    C_LINK_TRIM=(-Wl,-dead_strip)
else
    C_LINK_TRIM=(-Wl,--gc-sections)
fi
C_FLAGS=(-O3 -ffast-math -march=native -flto -fomit-frame-pointer "${C_LINK_TRIM[@]}")

stat_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

stripped_size() {
    local input="$1"
    local out="$2"
    cp "$input" "$out"
    if [ "$(uname -s)" = "Darwin" ]; then
        "$STRIP" -x "$out" 2>/dev/null || true
    else
        "$STRIP" --strip-all "$out" 2>/dev/null || true
    fi
    stat_size "$out"
}

count_result_rows() {
    awk '/^RESULT / { n++ } END { print n + 0 }' "$1"
}

capture_result_rows() {
    local label="$1"
    local expected="$2"
    local out="$3"
    shift 3
    local err="${out}.err"
    local status=0
    "$@" > "$out.raw" 2>"$err" || status=$?
    awk '/^RESULT /' "$out.raw" | sort > "$out"
    local count
    count=$(count_result_rows "$out")
    if [ "$status" -eq 0 ] && [ "$count" -eq "$expected" ]; then
        rm -f "$err" "$out.raw"
        return 0
    fi

    echo "RESULT capture failed for $label: got $count/$expected row(s), status $status" >&2
    echo "command: $*" >&2
    if [ -s "$err" ]; then
        echo "stderr:" >&2
        sed -n '1,40p' "$err" >&2
    fi
    if [ -s "$out.raw" ]; then
        echo "stdout head:" >&2
        sed -n '1,40p' "$out.raw" >&2
    fi
    return 1
}

write_typed_checksum_duo() {
    local out="$1"
    cat > "$out" <<'DUO'
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
}

write_typed_checksum_c() {
    local out="$1"
    cat > "$out" <<'C'
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
}

write_chain_duo() {
    local out="$1"
    local funcs="$2"
    {
        printf -- "-- Generated typed function-chain workload.\n\n"
        local i
        for ((i = 0; i < funcs; i++)); do
            local add=$((i * 17 + 31))
            local salt=$((i + 3))
            printf "fun step_%d(x: i64): i64\n" "$i"
            printf "    y: i64 = x + %d\n" "$add"
            printf "    y = (y * 1103515245 + 12345 + %d) %% 2147483647\n" "$salt"
            printf "    y\n"
            printf "end\n\n"
        done
        printf "fun checksum(n: i64): i64\n"
        printf "    acc: i64 = 0\n"
        printf "    i: i64 = 1\n"
        printf "    while i <= n\n"
        printf "        x: i64 = i + acc %% 97\n"
        for ((i = 0; i < funcs; i++)); do
            printf "        x = step_%d(x)\n" "$i"
        done
        printf "        acc = (acc + x) %% 1000000007\n"
        printf "        i += 1\n"
        printf "    end\n"
        printf "    acc\n"
        printf "end\n\n"
        printf "print(checksum(2000))\n"
    } > "$out"
}

write_chain_c() {
    local out="$1"
    local funcs="$2"
    {
        printf "#include <stdint.h>\n#include <stdio.h>\n\n"
        local i
        for ((i = 0; i < funcs; i++)); do
            local add=$((i * 17 + 31))
            local salt=$((i + 3))
            printf "static inline int64_t step_%d(int64_t x) {\n" "$i"
            printf "    int64_t y = x + %d;\n" "$add"
            printf "    y = (y * 1103515245 + 12345 + %d) %% 2147483647;\n" "$salt"
            printf "    return y;\n"
            printf "}\n\n"
        done
        printf "static inline int64_t checksum(int64_t n) {\n"
        printf "    int64_t acc = 0;\n"
        printf "    for (int64_t i = 1; i <= n; ++i) {\n"
        printf "        int64_t x = i + acc %% 97;\n"
        for ((i = 0; i < funcs; i++)); do
            printf "        x = step_%d(x);\n" "$i"
        done
        printf "        acc = (acc + x) %% 1000000007;\n"
        printf "    }\n"
        printf "    return acc;\n"
        printf "}\n\n"
        printf "int main(void) {\n"
        printf "    printf(\"%%lld\\\\n\", (long long)checksum(2000));\n"
        printf "    return 0;\n"
        printf "}\n"
    } > "$out"
}

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
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=True)
    except subprocess.CalledProcessError as err:
        if err.stderr:
            sys.stderr.write(err.stderr)
        raise
    elapsed = time.perf_counter() - start
    best = elapsed if best is None or elapsed < best else best
print(f"{label} {best:.6f}")
PY
}

echo "=== Compile Time + Binary Size Benchmark ==="
echo "Runs: $RUNS (minimum wall time)"
echo "Generated chain functions: 1k=$CHAIN_FUNCS_1K 10k=$CHAIN_FUNCS_10K"
echo

printf "%-22s %-16s %12s %12s %10s\n" "Workload" "Metric" "Duo" "C" "Ratio"
printf "%-22s %-16s %12s %12s %10s\n" "----------------------" "----------------" "------------" "------------" "----------"

measure_workload() {
    local name="$1"
    local duo_src="$2"
    local c_src="$3"
    local duo_out="$4"
    local c_out="$5"

    local duo_compile
    local c_compile
    duo_compile=$(time_command "duo_compile" "$DUO" compile "$duo_src" -o "$duo_out")
    c_compile=$(time_command "c_compile" "$CC" "${C_FLAGS[@]}" "$c_src" -o "$c_out")

    local duo_time
    local c_time
    duo_time=$(echo "$duo_compile" | awk '{print $2}')
    c_time=$(echo "$c_compile" | awk '{print $2}')

    local duo_size
    local c_size
    duo_size=$(stat_size "$duo_out")
    c_size=$(stat_size "$c_out")

    local duo_src_lines
    local c_src_lines
    local duo_src_bytes
    local c_src_bytes
    duo_src_lines=$(wc -l < "$duo_src" | awk '{print $1}')
    c_src_lines=$(wc -l < "$c_src" | awk '{print $1}')
    duo_src_bytes=$(stat_size "$duo_src")
    c_src_bytes=$(stat_size "$c_src")

    local duo_result
    local c_result
    duo_result=$("$duo_out")
    c_result=$("$c_out")
    if [ "$duo_result" != "$c_result" ]; then
        echo "RESULT mismatch for $name: Duo=$duo_result C=$c_result"
        exit 1
    fi

    local compile_ratio
    local size_ratio
    local lines_ratio
    local bytes_ratio
    compile_ratio=$(awk "BEGIN { if ($c_time > 0) printf \"%.3f\", $duo_time / $c_time; else print \"N/A\" }")
    size_ratio=$(awk "BEGIN { if ($c_size > 0) printf \"%.3f\", $duo_size / $c_size; else print \"N/A\" }")
    lines_ratio=$(awk "BEGIN { if ($c_src_lines > 0) printf \"%.3f\", $duo_src_lines / $c_src_lines; else print \"N/A\" }")
    bytes_ratio=$(awk "BEGIN { if ($c_src_bytes > 0) printf \"%.3f\", $duo_src_bytes / $c_src_bytes; else print \"N/A\" }")

    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "source_lines" "$duo_src_lines" "$c_src_lines" "$lines_ratio"
    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "source_bytes" "$duo_src_bytes" "$c_src_bytes" "$bytes_ratio"
    printf "%-22s %-16s %12.6f %12.6f %10sx\n" "$name" "compile_s" "$duo_time" "$c_time" "$compile_ratio"
    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "binary_bytes" "$duo_size" "$c_size" "$size_ratio"
    printf "RESULT %-15s %s\n" "$name" "$duo_result"
}

measure_ml_binary_workload() {
    local name="ml_binary"
    local duo_src="examples/bench_ml.duo"
    local c_src="examples/bench_ml_c.c"
    local duo_out="$WORK_DIR/ml_bench_duo"
    local c_out="$WORK_DIR/ml_bench_c"
    local duo_stripped="$WORK_DIR/ml_bench_duo_stripped"
    local c_stripped="$WORK_DIR/ml_bench_c_stripped"

    local duo_compile
    local c_compile
    duo_compile=$(time_command "duo_compile" "$DUO" compile "$duo_src" -o "$duo_out")
    c_compile=$(time_command "c_compile" "$CC" "${C_FLAGS[@]}" "$c_src" -o "$c_out" -lm)

    local duo_time
    local c_time
    duo_time=$(echo "$duo_compile" | awk '{print $2}')
    c_time=$(echo "$c_compile" | awk '{print $2}')

    capture_result_rows "$name Duo" 5 "$WORK_DIR/ml_duo.results" "$duo_out"
    capture_result_rows "$name C" 5 "$WORK_DIR/ml_c.results" "$c_out"
    python3 - "$WORK_DIR/ml_duo.results" "$WORK_DIR/ml_c.results" <<'PY'
import math
import sys

duo_path, c_path = sys.argv[1], sys.argv[2]
duo = [line.split() for line in open(duo_path, encoding="utf-8")]
c = [line.split() for line in open(c_path, encoding="utf-8")]
if len(duo) != len(c):
    raise SystemExit(f"RESULT count mismatch: Duo={len(duo)} C={len(c)}")
for left, right in zip(duo, c):
    if len(left) < 3 or len(right) < 3 or left[1] != right[1]:
        raise SystemExit(f"RESULT id mismatch: Duo={' '.join(left)} C={' '.join(right)}")
    d = float(left[2])
    r = float(right[2])
    denom = max(abs(r), 1.0)
    if math.fabs(d - r) / denom >= 0.0001:
        raise SystemExit(f"RESULT mismatch for {left[1]}: Duo={d} C={r}")
PY

    local duo_size
    local c_size
    local duo_strip_size
    local c_strip_size
    local duo_src_lines
    local c_src_lines
    local duo_src_bytes
    local c_src_bytes
    duo_size=$(stat_size "$duo_out")
    c_size=$(stat_size "$c_out")
    duo_strip_size=$(stripped_size "$duo_out" "$duo_stripped")
    c_strip_size=$(stripped_size "$c_out" "$c_stripped")
    duo_src_lines=$(wc -l < "$duo_src" | awk '{print $1}')
    c_src_lines=$(wc -l < "$c_src" | awk '{print $1}')
    duo_src_bytes=$(stat_size "$duo_src")
    c_src_bytes=$(stat_size "$c_src")

    local compile_ratio
    local size_ratio
    local stripped_ratio
    local lines_ratio
    local bytes_ratio
    compile_ratio=$(awk "BEGIN { if ($c_time > 0) printf \"%.3f\", $duo_time / $c_time; else print \"N/A\" }")
    size_ratio=$(awk "BEGIN { if ($c_size > 0) printf \"%.3f\", $duo_size / $c_size; else print \"N/A\" }")
    stripped_ratio=$(awk "BEGIN { if ($c_strip_size > 0) printf \"%.3f\", $duo_strip_size / $c_strip_size; else print \"N/A\" }")
    lines_ratio=$(awk "BEGIN { if ($c_src_lines > 0) printf \"%.3f\", $duo_src_lines / $c_src_lines; else print \"N/A\" }")
    bytes_ratio=$(awk "BEGIN { if ($c_src_bytes > 0) printf \"%.3f\", $duo_src_bytes / $c_src_bytes; else print \"N/A\" }")

    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "source_lines" "$duo_src_lines" "$c_src_lines" "$lines_ratio"
    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "source_bytes" "$duo_src_bytes" "$c_src_bytes" "$bytes_ratio"
    printf "%-22s %-16s %12.6f %12.6f %10sx\n" "$name" "compile_s" "$duo_time" "$c_time" "$compile_ratio"
    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "binary_bytes" "$duo_size" "$c_size" "$size_ratio"
    printf "%-22s %-16s %12d %12d %10sx\n" "$name" "stripped_bytes" "$duo_strip_size" "$c_strip_size" "$stripped_ratio"
    printf "RESULT %-15s %s\n" "$name" "5_rows_match"
}

measure_duo_app_workload() {
    local name="$1"
    local duo_src="$2"
    local sentinel="$3"
    local duo_out="$WORK_DIR/${name}_duo"
    local duo_stripped="$WORK_DIR/${name}_duo_stripped"

    local duo_compile
    duo_compile=$(time_command "duo_compile" "$DUO" compile "$duo_src" -o "$duo_out")

    local duo_time
    duo_time=$(echo "$duo_compile" | awk '{print $2}')

    local run_output
    run_output=$("$duo_out")
    if ! printf "%s\n" "$run_output" | grep -F "$sentinel" >/dev/null; then
        echo "RESULT mismatch for $name: missing sentinel '$sentinel'"
        exit 1
    fi

    local duo_size
    local duo_strip_size
    local duo_src_lines
    local duo_src_bytes
    duo_size=$(stat_size "$duo_out")
    duo_strip_size=$(stripped_size "$duo_out" "$duo_stripped")
    duo_src_lines=$(wc -l < "$duo_src" | awk '{print $1}')
    duo_src_bytes=$(stat_size "$duo_src")

    printf "%-22s %-16s %12d %12s %10s\n" "$name" "source_lines" "$duo_src_lines" "-" "-"
    printf "%-22s %-16s %12d %12s %10s\n" "$name" "source_bytes" "$duo_src_bytes" "-" "-"
    printf "%-22s %-16s %12.6f %12s %10s\n" "$name" "compile_s" "$duo_time" "-" "-"
    printf "%-22s %-16s %12d %12s %10s\n" "$name" "binary_bytes" "$duo_size" "-" "-"
    printf "%-22s %-16s %12d %12s %10s\n" "$name" "stripped_bytes" "$duo_strip_size" "-" "-"
    printf "RESULT %-15s %s\n" "$name" "sentinel_match"
}

DUO_TYPED_SRC="$WORK_DIR/typed_checksum.duo"
C_TYPED_SRC="$WORK_DIR/typed_checksum.c"
DUO_TYPED_OUT="$WORK_DIR/typed_checksum_duo"
C_TYPED_OUT="$WORK_DIR/typed_checksum_c"
write_typed_checksum_duo "$DUO_TYPED_SRC"
write_typed_checksum_c "$C_TYPED_SRC"
measure_workload "typed_checksum" "$DUO_TYPED_SRC" "$C_TYPED_SRC" "$DUO_TYPED_OUT" "$C_TYPED_OUT"

DUO_CHAIN_1K_SRC="$WORK_DIR/function_chain_1k.duo"
C_CHAIN_1K_SRC="$WORK_DIR/function_chain_1k.c"
DUO_CHAIN_1K_OUT="$WORK_DIR/function_chain_1k_duo"
C_CHAIN_1K_OUT="$WORK_DIR/function_chain_1k_c"
write_chain_duo "$DUO_CHAIN_1K_SRC" "$CHAIN_FUNCS_1K"
write_chain_c "$C_CHAIN_1K_SRC" "$CHAIN_FUNCS_1K"
measure_workload "function_chain_1k" "$DUO_CHAIN_1K_SRC" "$C_CHAIN_1K_SRC" "$DUO_CHAIN_1K_OUT" "$C_CHAIN_1K_OUT"

DUO_CHAIN_10K_SRC="$WORK_DIR/function_chain_10k.duo"
C_CHAIN_10K_SRC="$WORK_DIR/function_chain_10k.c"
DUO_CHAIN_10K_OUT="$WORK_DIR/function_chain_10k_duo"
C_CHAIN_10K_OUT="$WORK_DIR/function_chain_10k_c"
write_chain_duo "$DUO_CHAIN_10K_SRC" "$CHAIN_FUNCS_10K"
write_chain_c "$C_CHAIN_10K_SRC" "$CHAIN_FUNCS_10K"
measure_workload "function_chain_10k" "$DUO_CHAIN_10K_SRC" "$C_CHAIN_10K_SRC" "$DUO_CHAIN_10K_OUT" "$C_CHAIN_10K_OUT"

measure_ml_binary_workload
measure_duo_app_workload "metaprogramming_app" "examples/metaprogramming_test.duo" "ALL METAPROGRAMMING TESTS PASSED"

echo
echo "Note: this is a tracking benchmark. It reports typed-program runtime"
echo "prelude cost, generated 1k/10k-line project scaling, ML binary size,"
echo "and a fixed metaprogramming app binary-size sample;"
echo "it does not fail when Duo is slower or larger than C."
