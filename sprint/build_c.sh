#!/usr/bin/env bash
# build_c.sh — build C = assembler+linker(B(B_src)).
#   sprint/b < sprint/b_src.id > sprint/c.s
#   <xcrun|plain> clang sprint/c.s -o sprint/c
# Then CONNECT the build: execute C over B_src (C performs the next build),
# require nonempty assembly, and assemble+link it into sprint/c.next.
# A C that cannot execute, or emits nothing usable, fails here — not later.
# Usage: sprint/build_c.sh [src.id]        (default: sprint/b_src.id)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${1:-$ROOT/sprint/b_src.id}"
B="$ROOT/sprint/b"
ASM="$ROOT/sprint/c.s"
OUT="$ROOT/sprint/c"
SMOKE_ASM="$ROOT/sprint/c.smoke.s"
NEXT="$ROOT/sprint/c.next"

log() { echo "[build_c] $*" >&2; }
die() { echo "[build_c] FATAL: $*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
chain() { echo "[build_c] chain: $1 $(sha256 "$2") $2" >&2; }

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

chain source "$SRC"
chain B "$B"
chain c-asm "$ASM"
chain C "$OUT"
log "OK: C built -> $OUT"

# Connected smoke: C must execute as a compiler and perform the next build.
rm -f "$SMOKE_ASM" "$NEXT"
log "smoke: executing C over B_src (C performs the next build)..."
"$OUT" < "$SRC" > "$SMOKE_ASM" || die "C failed to execute on $SRC"
[ -s "$SMOKE_ASM" ] || die "C executed but emitted empty assembly on $SRC"
log "C emitted $(wc -c < "$SMOKE_ASM") bytes of assembly"
log "assembling+linking C output with ${CC[*]}..."
"${CC[@]}" "$SMOKE_ASM" -o "$NEXT" || die "next build: assembler/linker failed on C output"
[ -x "$NEXT" ] || die "next build: link reported success but no executable at $NEXT"
chain c-next "$NEXT"
log "OK: C executes; next build -> $NEXT"
