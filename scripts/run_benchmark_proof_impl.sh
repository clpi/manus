#!/usr/bin/env bash
# P0 — Pass 27 benchmark proof matrix (3 profiles + emission audit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO:-$ROOT/zig-out/bin/duo}"
CC="${CC:-clang}"
export DUO_EMIT_PROOF=1
# L6 (pass34 PH1): capture @comp.why transform provenance so emitted manifests
# carry the transform-provenance section. Provenance summary goes to stderr only.
export DUO_PROVENANCE=1

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

SOURCE="${BENCH_PROOF_SOURCE:-examples/pass27_proof_matrix.duo}"
DIRECT_SOURCE="${BENCH_PROOF_DIRECT_SOURCE:-examples/pass27_proof_matrix_direct.duo}"
C_SRC="${BENCH_PROOF_C_SOURCE:-examples/pass27_proof_matrix_c.c}"
STEM="$(basename "$SOURCE" .duo)"
DSTEM="$(basename "$DIRECT_SOURCE" .duo)"
PROFILES=(c-dynamic c-specialized direct)
EXPECTED_RESULTS=10

echo "=== Pass 27 benchmark proof matrix (P0 evidence) ==="
echo "source: $SOURCE"
echo "direct: $DIRECT_SOURCE"
echo "work:   $WORK_DIR"
echo

compile_profile() {
  local profile="$1"
  local src="$SOURCE"
  if [ "$profile" = "direct" ]; then
    src="$DIRECT_SOURCE"
  fi
  local out="$WORK_DIR/bench_${profile}.out"
  export BENCH_BACKEND="$profile"
  export DUO_BENCH_MANIFEST="backend=${profile} representation=profile-selected runtime=dynamic"
  if ! "$DUO" compile --bench-backend "$profile" -O3 "$src" -o "$out" >/dev/null; then
    echo "compile failed: profile=${profile} source=${src}" >&2
    exit 1
  fi
  echo "$out"
}

proof_stem_for_profile() {
  local profile="$1"
  if [ "$profile" = "direct" ]; then
    echo "$DSTEM"
  else
    echo "$STEM"
  fi
}

collect_proof() {
  local profile="$1"
  local stem
  stem="$(proof_stem_for_profile "$profile")"
  local proof=""
  if [ "$profile" = "direct" ] && [ -f "/tmp/duo_${stem}_native.o.proof.json" ]; then
    proof="/tmp/duo_${stem}_native.o.proof.json"
  else
    proof="/tmp/duo_${stem}.c.proof.json"
  fi
  if [ ! -f "$proof" ]; then
    echo "missing proof artifact for ${profile}: $proof" >&2
    exit 1
  fi
  cp "$proof" "$WORK_DIR/bench_${profile}.proof.json"
  echo "$WORK_DIR/bench_${profile}.proof.json"
}

result_hash() {
  awk '/^RESULT / { print $2, $3 }' | sort | shasum -a 256 | awk '{print $1}'
}

count_results() {
  awk '/^RESULT / { c++ } END { print c+0 }'
}

proof_field() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
key = sys.argv[2]
if key == "boxes":
    print(d.get("emission", {}).get("boxes", 0))
elif key == "evidence_class":
    print(d.get("evidence_class", ""))
else:
    print("")
PY
}

SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
CFLAGS="-O3 -ffast-math -march=native -flto -lm"
if [ -n "$SDKROOT" ]; then CFLAGS="$CFLAGS -isysroot $SDKROOT"; fi

echo "--- Reference C ---"
$CC $CFLAGS -o "$WORK_DIR/c_ref.out" "$C_SRC"
C_OUT="$("$WORK_DIR/c_ref.out")"
C_HASH="$(printf '%s\n' "$C_OUT" | result_hash)"
echo "correctness_hash(c_ref)=${C_HASH}"
echo

OVERALL=0
CANONICAL_HASH=""
CANONICAL_PROFILE=""
DYNAMIC_BOXES=""
SPECIALIZED_BOXES=""

for profile in "${PROFILES[@]}"; do
  echo "--- Profile: ${profile} ---"
  BIN="$(compile_profile "$profile")"
  PROOF="$(collect_proof "$profile")"
  BOXES="$(proof_field "$PROOF" boxes)"
  EVIDENCE="$(proof_field "$PROOF" evidence_class)"

  if [ "$profile" = "direct" ]; then
    if ! "$BIN" >/dev/null 2>&1; then
      echo "FAIL: direct native exit non-zero" >&2
      OVERALL=1
    else
      echo "OK direct native binary exit 0"
    fi
    HASH="$(shasum -a 256 "$PROOF" | awk '{print $1}')"
    if [ "$EVIDENCE" != "direct-native-subset" ]; then
      echo "FAIL: direct profile must emit direct-native-subset" >&2
      OVERALL=1
    fi
    if [ "$BOXES" != "0" ]; then
      echo "FAIL: direct profile must have zero boxes" >&2
      OVERALL=1
    fi
    if ! grep -q '"manifest_schema":"pass34-l6-manifest-v0"' "$PROOF"; then
      echo "FAIL: direct profile proof must be an L6 manifest (missing manifest_schema)" >&2
      OVERALL=1
    fi
    if ! grep -q '"transform_provenance"' "$PROOF"; then
      echo "FAIL: direct profile proof must carry @comp.why transform_provenance" >&2
      OVERALL=1
    fi
  else
    OUT="$("$BIN")"
    RC="$(printf '%s\n' "$OUT" | count_results)"
    if [ "$RC" -ne "$EXPECTED_RESULTS" ]; then
      echo "FAIL: profile ${profile} emitted ${RC} RESULT lines (expected ${EXPECTED_RESULTS})" >&2
      OVERALL=1
    fi
    HASH="$(printf '%s\n' "$OUT" | result_hash)"
    if [ -z "$CANONICAL_HASH" ]; then
      CANONICAL_HASH="$HASH"
      CANONICAL_PROFILE="$profile"
    elif [ "$HASH" != "$CANONICAL_HASH" ]; then
      echo "FAIL cross-profile: ${profile} != ${CANONICAL_PROFILE}" >&2
      OVERALL=1
    else
      echo "OK cross-profile semantics match ${CANONICAL_PROFILE}"
    fi
    if [ "$profile" = "c-dynamic" ] && [ "$EVIDENCE" != "provisional-boxed-path" ]; then
      echo "FAIL: c-dynamic must emit provisional-boxed-path (got ${EVIDENCE})" >&2
      OVERALL=1
    fi
    if [ "$profile" = "c-specialized" ] && [ "$EVIDENCE" != "specialized-provisional-boxed" ] && [ "$EVIDENCE" != "specialized-generated-c" ]; then
      echo "FAIL: c-specialized must emit specialized evidence class (got ${EVIDENCE})" >&2
      OVERALL=1
    fi
  fi

  echo "emission boxes=${BOXES} class=${EVIDENCE}"
  echo "correctness_hash=${HASH}"
  if [ "$profile" = "c-dynamic" ]; then
    DYNAMIC_BOXES="$BOXES"
  elif [ "$profile" = "c-specialized" ]; then
    SPECIALIZED_BOXES="$BOXES"
  fi
  echo
done

if [ -n "$DYNAMIC_BOXES" ] && [ -n "$SPECIALIZED_BOXES" ]; then
  if [ "$SPECIALIZED_BOXES" -ge "$DYNAMIC_BOXES" ]; then
    echo "FAIL: c-specialized boxes (${SPECIALIZED_BOXES}) must be < c-dynamic (${DYNAMIC_BOXES})" >&2
    OVERALL=1
  else
    echo "OK c-specialized boxing (${SPECIALIZED_BOXES}) < c-dynamic (${DYNAMIC_BOXES})"
  fi
fi

SUMMARY="$WORK_DIR/proof_matrix_summary.json"
python3 - "$SUMMARY" "$SOURCE" "$DIRECT_SOURCE" "$CANONICAL_PROFILE" "$CANONICAL_HASH" "$C_HASH" <<'PY'
import json, sys
doc = {
    "schema": "pass27-proof-matrix-v0",
    "source": sys.argv[2],
    "direct_source": sys.argv[3],
    "canonical_profile": sys.argv[4],
    "canonical_hash": sys.argv[5],
    "c_reference_hash": sys.argv[6],
}
json.dump(doc, open(out := sys.argv[1], "w"))
PY

if [ "$OVERALL" -ne 0 ]; then
  exit 1
fi
echo "PASS: C-path hash ${CANONICAL_HASH}; summary ${SUMMARY}"
