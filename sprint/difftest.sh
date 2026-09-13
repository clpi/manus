#!/usr/bin/env bash
# difftest.sh <corpus-dir> [src.id]
# Differential test B vs C:
#   1. For each <corpus-dir>/*.s.id (S program): compile+link with B, compile+link
#      with C, run both, compare stdout and exit code. PASS/FAIL per file + summary.
#   2. Self-host check: B(B_src) vs C(B_src) assembly must be byte-identical
#      (deterministic codegen). FAILs loudly otherwise.
# Exit 0 iff every check passes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORPUS="${1:?usage: sprint/difftest.sh <corpus-dir> [src.id]}"
SRC="${2:-$ROOT/sprint/b_src.id}"
# SPRINT_B / SPRINT_C env overrides allow testing with stand-in compilers.
# (With the real B, build_c.sh output *is* C; the harness stub's canned program
# cannot act as a compiler, so the stub test points SPRINT_C at the stub script.)
B="${SPRINT_B:-$ROOT/sprint/b}"
C="${SPRINT_C:-$ROOT/sprint/c}"
WORK="$ROOT/sprint/work"

log() { echo "[difftest] $*" >&2; }
die() { echo "[difftest] FATAL: $*" >&2; exit 1; }

if command -v xcrun >/dev/null 2>&1; then CC=(xcrun clang); else CC=(clang); fi
command -v "${CC[0]}" >/dev/null 2>&1 || die "no toolchain: need xcrun or clang on PATH"
[ -d "$CORPUS" ] || die "corpus dir not found: $CORPUS"
[ -x "$B" ] || die "B missing/not executable: $B"
[ -x "$C" ] || die "C missing/not executable: $C"
[ -f "$SRC" ] || die "B_src not found: $SRC"

mkdir -p "$WORK"
PASS=0; FAIL=0; FAILED_FILES=""

shopt -s nullglob
files=("$CORPUS"/*.s.id)
[ "${#files[@]}" -gt 0 ] || die "no .s.id files in $CORPUS"

for t in "${files[@]}"; do
  base="$(basename "$t" .s.id)"
  ok=1
  # compile with B
  if ! "$B" < "$t" > "$WORK/${base}_b.s" 2>"$WORK/${base}_b.err"; then ok=0; log "B failed to compile $t"; fi
  if [ "$ok" = 1 ] && ! "${CC[@]}" "$WORK/${base}_b.s" -o "$WORK/${base}_b" 2>"$WORK/${base}_b.linkerr"; then ok=0; log "B output failed to link: $t"; fi
  # compile with C
  if ! "$C" < "$t" > "$WORK/${base}_c.s" 2>"$WORK/${base}_c.err"; then ok=0; log "C failed to compile $t"; fi
  if [ "$ok" = 1 ] && ! "${CC[@]}" "$WORK/${base}_c.s" -o "$WORK/${base}_c" 2>"$WORK/${base}_c.linkerr"; then ok=0; log "C output failed to link: $t"; fi
  # run both, compare stdout + exit code
  if [ "$ok" = 1 ]; then
    set +e
    "$WORK/${base}_b" > "$WORK/${base}_b.out" 2>&1; rc_b=$?
    "$WORK/${base}_c" > "$WORK/${base}_c.out" 2>&1; rc_c=$?
    set -e
    if [ "$rc_b" -eq "$rc_c" ] && cmp -s "$WORK/${base}_b.out" "$WORK/${base}_c.out"; then
      PASS=$((PASS+1)); echo "PASS $t (rc=$rc_b)"
    else
      ok=0
      log "behavioral mismatch on $t: rc_b=$rc_b rc_c=$rc_c"
    fi
  fi
  if [ "$ok" = 0 ]; then
    FAIL=$((FAIL+1)); FAILED_FILES="$FAILED_FILES $t"; echo "FAIL $t"
  fi
done

# Self-host determinism: B(B_src) and C(B_src) assembly must be byte-identical.
log "self-host check: B(B_src) vs C(B_src)..."
"$B" < "$SRC" > "$WORK/selfhost_b.s" || die "B failed on B_src"
"$C" < "$SRC" > "$WORK/selfhost_c.s" || die "C failed on B_src"
SELFHOST="PASS"
if cmp -s "$WORK/selfhost_b.s" "$WORK/selfhost_c.s"; then
  echo "SELFHOST-DETERMINISTIC PASS (B(B_src) == C(B_src), $(wc -c < "$WORK/selfhost_b.s") bytes)"
else
  SELFHOST="FAIL"
  echo "SELFHOST-DETERMINISTIC FAIL (assembly differs)"
  diff "$WORK/selfhost_b.s" "$WORK/selfhost_c.s" | head -20 >&2 || true
fi

echo "---"
echo "SUMMARY: pass=$PASS fail=$FAIL selfhost=$SELFHOST"
[ -n "$FAILED_FILES" ] && echo "failed files:$FAILED_FILES"

[ "$FAIL" -eq 0 ] && [ "$SELFHOST" = "PASS" ]
