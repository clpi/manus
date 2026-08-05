#!/usr/bin/env bash
# Pass 11 WP-05: byte blob constants → direct Mach-O object (macOS AArch64 host only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DUO="$ROOT/zig-out/bin/duo"
PROOF="$ROOT/examples/pass11_blob_object_smoke.duo"
OUT="/tmp/duo_pass11_blob_object_smoke.o"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pass11_blob_object_smoke: SKIP (requires macOS host)"
  exit 0
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "pass11_blob_object_smoke: SKIP (requires AArch64 host)"
  exit 0
fi

if [[ ! -x "$DUO" ]]; then
  "${ZIG:-zig}" build
fi

if [[ ! -f "$PROOF" ]]; then
  echo "pass11_blob_object_smoke: FAIL — missing $PROOF" >&2
  exit 1
fi

"$DUO" compile "$PROOF" --backend=direct --target aarch64-macos --emit obj -o "$OUT"

magic="$(xxd -p -l 4 "$OUT")"
if [[ "$magic" != "cffaedfe" ]]; then
  echo "pass11_blob_object_smoke: FAIL — expected Mach-O magic cffaedfe, got $magic" >&2
  exit 1
fi

echo "pass11_blob_object_smoke: PASS — Mach-O object from byte blob module"
