#!/usr/bin/env bash
# Pass 11 WP-13: build the compiler twice and compare ReleaseFast binary hashes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ZIG="${ZIG:-zig}"
OPT="${REPRO_OPT:-ReleaseFast}"

build_once() {
  local out="$1"
  rm -rf "$ROOT/zig-out"
  "$ZIG" build "-Doptimize=$OPT"
  shasum -a 256 "$ROOT/zig-out/bin/duo" | awk '{print $1}'
}

echo "reproducibility_smoke: zig=$("$ZIG" version) optimize=$OPT"
hash1="$(build_once a)"
hash2="$(build_once b)"

echo "reproducibility_smoke: hash1=$hash1"
echo "reproducibility_smoke: hash2=$hash2"

if [[ "$hash1" != "$hash2" ]]; then
  echo "reproducibility_smoke: FAIL — ReleaseFast duo binary differs between clean rebuilds" >&2
  exit 1
fi

echo "reproducibility_smoke: PASS — identical ReleaseFast compiler binaries"
