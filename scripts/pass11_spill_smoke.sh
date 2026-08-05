#!/usr/bin/env bash
# Pass 11 WP-03: register spill proof (macOS AArch64 host only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DUO="$ROOT/zig-out/bin/duo"
PROOF="$ROOT/examples/pass11_spill_proof.duo"
OUT="/tmp/duo_pass11_spill_smoke.out"
ASM="/tmp/duo_pass11_spill_smoke.asm"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pass11_spill_smoke: SKIP (requires macOS host)"
  exit 0
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "pass11_spill_smoke: SKIP (requires AArch64 host)"
  exit 0
fi

if [[ ! -x "$DUO" ]]; then
  "${ZIG:-zig}" build
fi

if [[ ! -f "$PROOF" ]]; then
  echo "pass11_spill_smoke: FAIL — missing $PROOF" >&2
  exit 1
fi

"$DUO" compile "$PROOF" --backend=direct --target aarch64-macos --emit exe -o "$OUT"
"$DUO" compile "$PROOF" --backend=direct --target native-asm -o "$ASM"

if ! grep -q $'\tstr x' "$ASM"; then
  echo "pass11_spill_smoke: FAIL — expected spill stores in assembly" >&2
  exit 1
fi
if ! grep -q $'\tldr x' "$ASM"; then
  echo "pass11_spill_smoke: FAIL — expected spill reloads in assembly" >&2
  exit 1
fi

set +e
"$OUT"
code=$?
set -e
if [[ "$code" -ne 2 ]]; then
  echo "pass11_spill_smoke: FAIL — expected exit 2 (v0+v21 with >20 live locals), got exit=$code" >&2
  exit 1
fi

echo "pass11_spill_smoke: PASS — spill lowering + runtime (exit=$code)"
