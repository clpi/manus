#!/usr/bin/env bash
# build_c.sh — build C = assembler+linker(B(B_src)).
#   sprint/b < sprint/b_src.id > sprint/c.s
#   <xcrun|plain> clang sprint/c.s -o sprint/c
# Usage: sprint/build_c.sh [src.id]        (default: sprint/b_src.id)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${1:-$ROOT/sprint/b_src.id}"
B="$ROOT/sprint/b"
ASM="$ROOT/sprint/c.s"
OUT="$ROOT/sprint/c"

log() { echo "[build_c] $*" >&2; }
die() { echo "[build_c] FATAL: $*" >&2; exit 1; }

if command -v xcrun >/dev/null 2>&1; then CC=(xcrun clang); else CC=(clang); fi
command -v "${CC[0]}" >/dev/null 2>&1 || die "no toolchain: need xcrun or clang on PATH"

[ -x "$B" ]   || die "B missing/not executable: $B (run sprint/build_b.sh first)"
[ -f "$SRC" ] || die "source not found: $SRC"

log "B    : $B"
log "src  : $SRC"
log "asm  : $ASM"
log "out  : $OUT"
log "cc   : ${CC[*]}"

rm -f "$ASM" "$OUT"
log "running B over B_src..."
"$B" < "$SRC" > "$ASM" || die "B failed on $SRC"
[ -s "$ASM" ] || die "B emitted empty assembly: $ASM"
log "B emitted $(wc -c < "$ASM") bytes of assembly"

log "assembling+linking with ${CC[*]}..."
"${CC[@]}" "$ASM" -o "$OUT" || die "assembler/linker failed on $ASM"
[ -x "$OUT" ] || die "link reported success but no executable at $OUT"

log "OK: C built -> $OUT"
