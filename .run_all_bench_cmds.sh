#!/bin/bash
set -o pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
OUT="$ROOT/.all_bench_output.log"
: > "$OUT"

run_cmd() {
  local n="$1"
  shift
  {
    echo "========== COMMAND $n: $* =========="
    echo "START: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "$@"
    local ec=$?
    echo "EXIT_CODE=$ec"
    echo "END: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    return $ec
  } 2>&1 | tee -a "$OUT"
}

run_cmd 1 zig build test
run_cmd 2 zig test src/ml_kernels.zig
run_cmd 3 zig build ml-bench
run_cmd 4 zig build bench
run_cmd 5 zig build honest-bench
echo "ALL_DONE" >> "$OUT"
