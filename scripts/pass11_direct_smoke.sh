#!/usr/bin/env bash
# Pass 11 WP-04/15: direct-backend smoke (macOS AArch64 host only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DUO="$ROOT/zig-out/bin/duo"
PROOF="$ROOT/examples/pass11_record_proof.duo"
OUT="/tmp/duo_pass11_direct_smoke.out"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pass11_direct_smoke: SKIP (requires macOS host)"
  exit 0
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "pass11_direct_smoke: SKIP (requires AArch64 host)"
  exit 0
fi

if [[ ! -x "$DUO" ]]; then
  "${ZIG:-zig}" build
fi

if [[ ! -f "$PROOF" ]]; then
  echo "pass11_direct_smoke: FAIL — missing $PROOF" >&2
  exit 1
fi

"$DUO" compile "$PROOF" --backend=direct --target aarch64-macos --emit exe -o "$OUT"
"$OUT"
code=$?
if [[ "$code" -ne 0 ]]; then
  echo "pass11_direct_smoke: FAIL — expected exit 0, got exit=$code" >&2
  exit 1
fi

echo "pass11_direct_smoke: PASS — direct compile + execute (exit=$code)"
