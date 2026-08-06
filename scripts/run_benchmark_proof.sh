#!/usr/bin/env bash
# P0 — benchmark proof matrix: backend × representation × emission audit.
#
# Compiles a subset of benchmarks under three bench-backend profiles, runs
# differential correctness against C, and writes proof artifacts (.proof.json).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
export DUO_EMIT_PROOF=1

cd "$ROOT"
if [ ! -x "$DUO" ]; then
  "${ZIG:-zig}" build
fi

WORK_DIR="${BENCH_PROOF_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/duo-bench-proof.XXXXXX")}"
CLEAN_WORK_DIR=0
if [ -z "${BENCH_PROOF_DIR:-}" ]; then
  CLEAN_WORK_DIR=1
fi
trap 'if [ "$CLEAN_WORK_DIR" -eq 1 ]; then rm -rf "$WORK_DIR"; fi' EXIT

# Ten high-signal benchmarks from the 40-program suite (names match benchmark.lua ids).
BENCH_IDS=(
  fib40 sieve mandelbrot matrix nbody string_bytes table_array trig_sum
  string_chain string_hash
)

PROFILES=(c-dynamic c-specialized direct)
SOURCE="${BENCH_PROOF_SOURCE:-examples/benchmark.duo}"

echo "=== Duo benchmark proof matrix (P0 evidence) ==="
echo "source: $SOURCE"
echo "work:   $WORK_DIR"
echo

compile_profile() {
  local profile="$1"
  local out="$WORK_DIR/bench_${profile}.out"
  export BENCH_BACKEND="$profile"
  export DUO_BENCH_MANIFEST="backend=${profile} representation=profile-selected runtime=dynamic"
  "$DUO" compile --bench-backend "$profile" -O3 "$SOURCE" -o "$out" >/dev/null
  echo "$out"
}

run_results() {
  local bin="$1"
  local out="$2"
  "$bin" > "$out" 2>"${out}.err" || {
    echo "run failed: $bin" >&2
    sed -n '1,20p' "${out}.err" >&2 || true
    exit 1
  }
}

result_hash() {
  awk '/^RESULT / { print $2, $3 }' "$1" | sort | sha256sum | awk '{print $1}'
}

echo "--- Reference C ---"
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
if [ -n "$SDKROOT" ]; then CFLAGS="$CFLAGS -isysroot $SDKROOT"; fi
$CC $CFLAGS -o "$WORK_DIR/c_ref.out" examples/benchmark_c.c
run_results "$WORK_DIR/c_ref.out" "$WORK_DIR/c_ref.results.txt"
C_HASH=$(result_hash "$WORK_DIR/c_ref.results.txt")
echo "correctness_hash(c_ref)=${C_HASH}"
echo

OVERALL=0
for profile in "${PROFILES[@]}"; do
  echo "--- Profile: ${profile} ---"
  BIN=$(compile_profile "$profile")
  C_GEN="/tmp/duo_$(basename "$SOURCE" .duo).c"
  PROOF="${C_GEN}.proof.json"
  if [ ! -f "$PROOF" ]; then
    echo "missing proof artifact: $PROOF" >&2
    exit 1
  fi
  cp "$PROOF" "$WORK_DIR/bench_${profile}.proof.json"
  run_results "$BIN" "$WORK_DIR/bench_${profile}.results.txt"
  P_HASH=$(result_hash "$WORK_DIR/bench_${profile}.results.txt")
  if [ "$P_HASH" != "$C_HASH" ]; then
    echo "FAIL correctness: profile ${profile} hash ${P_HASH} != C ${C_HASH}" >&2
    OVERALL=1
  else
    echo "OK correctness matches C"
  fi
  BOXES=$(python3 - <<PY
import json
with open("$WORK_DIR/bench_${profile}.proof.json") as f:
    d=json.load(f)
print(d["emission"]["boxes"], d["emission"]["unboxes"], d["emission"]["generic_table_ops"], d.get("evidence_class",""))
PY
)
  echo "emission boxes,unboxes,table_ops,class: $BOXES"
  echo "proof: $WORK_DIR/bench_${profile}.proof.json"
  echo
done

if [ "$OVERALL" -ne 0 ]; then
  echo "benchmark proof matrix FAILED (correctness mismatch)" >&2
  exit 1
fi

echo "PASS: all profiles match C correctness hash; proof artifacts in $WORK_DIR"
echo "Next: compare emission counters across c-dynamic vs c-specialized vs direct."
