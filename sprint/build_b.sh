#!/usr/bin/env bash
# build_b.sh — build B (seed-compiled compiler) from B_src.
# Usage: sprint/build_b.sh [src.id]        (default: sprint/b_src.id)
# Exact seed command under test:
#   ./zig-out/bin/idol compile --backend=direct --emit=exe -o sprint/b sprint/b_src.id
# Run from anywhere; the script resolves the repo root itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${1:-$ROOT/sprint/b_src.id}"
SEED="$ROOT/zig-out/bin/idol"
OUT="$ROOT/sprint/b"

log() { echo "[build_b] $*" >&2; }
die() { echo "[build_b] FATAL: $*" >&2; exit 1; }

[ -f "$SRC" ]  || die "source not found: $SRC (pass a path explicitly: sprint/build_b.sh <src.id>)"
[ -x "$SEED" ] || die "seed compiler missing/not executable: $SEED"

log "seed : $SEED"
log "src  : $SRC"
log "out  : $OUT"

rm -f "$OUT"
"$SEED" compile --backend=direct --emit=exe -o "$OUT" "$SRC" \
  || die "seed compile failed"

[ -x "$OUT" ] || die "compile reported success but no executable at $OUT"
size=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null || echo 0)
[ "$size" -gt 0 ] || die "built binary is empty: $OUT"

log "OK: B built ($size bytes) -> $OUT"
