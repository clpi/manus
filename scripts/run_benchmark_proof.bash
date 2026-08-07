#!/usr/bin/env bash
# P0 — Pass 27 benchmark proof matrix (bash fallback until Duo script codegen matures).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
CC="${CC:-clang}"
export DUO_EMIT_PROOF=1

cd "$ROOT"
if [ ! -x "$DUO" ]; then "${ZIG:-zig}" build; fi

WORK_DIR="${BENCH_PROOF_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/duo-bench-proof.XXXXXX")}"
CLEAN_WORK_DIR=0
[ -z "${BENCH_PROOF_DIR:-}" ] && CLEAN_WORK_DIR=1
trap 'if [ "$CLEAN_WORK_DIR" -eq 1 ]; then rm -rf "$WORK_DIR"; fi' EXIT

SOURCE="${BENCH_PROOF_SOURCE:-examples/pass27_proof_matrix.duo}"
DIRECT_SOURCE="${BENCH_PROOF_DIRECT_SOURCE:-examples/pass27_proof_matrix_direct.duo}"
C_SOURCE="${BENCH_PROOF_C_SOURCE:-examples/pass27_proof_matrix_c.c}"
PROFILES=(c-dynamic c-specialized direct)
STEM="$(basename "$SOURCE" .duo)"
DIRECT_STEM="$(basename "$DIRECT_SOURCE" .duo)"
EXPECTED_RESULTS=10

echo "=== Pass 27 benchmark proof matrix (P0 evidence) ==="
echo "source: $SOURCE"
echo "direct: $DIRECT_SOURCE"
echo "work:   $WORK_DIR"

compile_profile() {
  local profile="$1" out="$WORK_DIR/bench_${profile}.out" source="$SOURCE"
  [ "$profile" = "direct" ] && source="$DIRECT_SOURCE"
  export BENCH_BACKEND="$profile"
  export DUO_BENCH_MANIFEST="backend=${profile} representation=profile-selected runtime=dynamic"
  "$DUO" compile --bench-backend "$profile" -O3 "$source" -o "$out" >/dev/null
  echo "$out"
}

run_results() {
  local bin="$1" out="$2"
  "$bin" > "${out}.stdout" 2>"${out}.stderr" || { echo "run failed: $bin" >&2; exit 1; }
  cat "${out}.stdout" "${out}.stderr" > "$out"
}

result_hash() { awk '/^RESULT / { print $2, $3 }' "$1" | sort | sha256sum | awk '{print $1}'; }
count_results() { awk '/^RESULT / { c++ } END { print c+0 }' "$1"; }

collect_proof() {
  local profile="$1" stem="$STEM"
  [ "$profile" = "direct" ] && stem="$DIRECT_STEM"
  local proof="/tmp/duo_${stem}.c.proof.json"
  [ "$profile" = "direct" ] && [ -f "/tmp/duo_${stem}_native.o.proof.json" ] && proof="/tmp/duo_${stem}_native.o.proof.json"
  [ -f "$proof" ] || { echo "missing proof artifact: $proof" >&2; exit 1; }
  cp "$proof" "$WORK_DIR/bench_${profile}.proof.json"
  echo "$WORK_DIR/bench_${profile}.proof.json"
}

SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
[ -n "$SDKROOT" ] && CFLAGS="$CFLAGS -isysroot $SDKROOT"
$CC $CFLAGS -o "$WORK_DIR/c_ref.out" "$C_SOURCE"
run_results "$WORK_DIR/c_ref.out" "$WORK_DIR/c_ref.results.txt"
C_HASH=$(result_hash "$WORK_DIR/c_ref.results.txt")
echo "correctness_hash(c_ref)=${C_HASH}"

CANONICAL_HASH="" CANONICAL_PROFILE="" OVERALL=0
for profile in "${PROFILES[@]}"; do
  echo "--- Profile: ${profile} ---"
  BIN=$(compile_profile "$profile")
  PROOF=$(collect_proof "$profile")
  if [ "$profile" = "direct" ]; then
    "$BIN" >/dev/null 2>&1 || { echo "FAIL: direct exit non-zero" >&2; OVERALL=1; }
    P_HASH=$(shasum -a 256 "$PROOF" | awk '{print $1}')
    RC=0
  else
    run_results "$BIN" "$WORK_DIR/bench_${profile}.results.txt"
    RC=$(count_results "$WORK_DIR/bench_${profile}.results.txt")
    [ "$RC" -eq "$EXPECTED_RESULTS" ] || { echo "FAIL: $RC results" >&2; OVERALL=1; }
    P_HASH=$(result_hash "$WORK_DIR/bench_${profile}.results.txt")
    [ -z "$CANONICAL_HASH" ] && CANONICAL_HASH="$P_HASH" && CANONICAL_PROFILE="$profile"
    [ "$P_HASH" = "$CANONICAL_HASH" ] || { echo "FAIL cross-profile" >&2; OVERALL=1; }
  fi
  read -r BOXES UNBOXES TABLE_OPS EVIDENCE_CLASS <<< "$(awk '
    /"boxes":/ { gsub(/[^0-9]/,"",$2); boxes=$2 }
    /"unboxes":/ { gsub(/[^0-9]/,"",$2); unboxes=$2 }
    /"generic_table_ops":/ { gsub(/[^0-9]/,"",$2); table_ops=$2 }
    /"evidence_class":/ { match($0, /"evidence_class":"([^"]+)"/, a); class=a[1] }
    END { print boxes+0, unboxes+0, table_ops+0, class }
  ' "$PROOF")"
  [ "$profile" = "direct" ] && { [ "$EVIDENCE_CLASS" = "direct-native-subset" ] && [ "$BOXES" = "0" ] || OVERALL=1; }
  echo "emission boxes=${BOXES} class=${EVIDENCE_CLASS} hash=${P_HASH}"
done

[ "$OVERALL" -eq 0 ] || exit 1
echo "PASS: canonical ${CANONICAL_HASH}"
