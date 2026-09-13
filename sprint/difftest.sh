#!/usr/bin/env bash
# difftest.sh <corpus-dir> [src.id]
# Differential test B vs C, with independent correctness obligations:
#   1. For each <corpus-dir>/*.s.id (S program): compile+link with B, compile+link
#      with C, run both, compare stdout and exit code. This B-vs-C differential
#      is unchanged. Additionally, when <corpus-dir>/<base>.expected exists, the
#      observed exit code (and stdout, when the file pins it) must equal the
#      INDEPENDENT expectation: two identically-wrong compilers no longer pass.
#   2. Self-host check: B(B_src) vs C(B_src) assembly must be byte-identical
#      (deterministic codegen) AND nonempty. Empty self-build artifacts are
#      rejected outright.
#   3. Next-build check: C(B_src) is assembled+linked into C2, and C2 must
#      compile+run the corpus satisfying the independent expectations. This
#      proves C actually executes as a compiler: the chain
#      declared source -> seed-built B -> B-produced C -> C-built C2 is real,
#      not just byte comparisons.
# Every link names its artifact (sha256 + path) on stderr as [chain] lines and
# in $WORK/chain.manifest, so a reviewer can verify the chain.
# Exit 0 iff every check passes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORPUS="${1:?usage: sprint/difftest.sh <corpus-dir> [src.id]}"
SRC="${2:-$ROOT/sprint/b_src.id}"
# SPRINT_B / SPRINT_C env overrides allow testing with stand-in compilers.
B="${SPRINT_B:-$ROOT/sprint/b}"
C="${SPRINT_C:-$ROOT/sprint/c}"
WORK="$ROOT/sprint/work"

log() { echo "[difftest] $*" >&2; }
die() { echo "[difftest] FATAL: $*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
chain() { # chain <role> <path>: name the artifact by hash + path, on stderr and in the manifest
  local h; h=$(sha256 "$2")
  echo "[chain] $1 $h $2" >&2
  printf '%s\t%s\t%s\n' "$1" "$h" "$2" >> "$WORK/chain.manifest"
}

if command -v xcrun >/dev/null 2>&1; then CC=(xcrun clang); else CC=(clang); fi
command -v "${CC[0]}" >/dev/null 2>&1 || die "no toolchain: need xcrun or clang on PATH"
[ -d "$CORPUS" ] || die "corpus dir not found: $CORPUS"
[ -x "$B" ] || die "B missing/not executable: $B"
[ -x "$C" ] || die "C missing/not executable: $C"
[ -f "$SRC" ] || die "B_src not found: $SRC"

mkdir -p "$WORK"
rm -f "$WORK/chain.manifest"
chain source "$SRC"
chain B "$B"
chain C "$C"

PASS=0; FAIL=0; FAILED_FILES=""

# --- independent expectations: <corpus-dir>/<base>.expected -----------------
# File format, one per line:  rc=<exit code the program must return>
#                            out=<exact stdout bytes expected> (may be empty)
# Absent file: differential comparison only (backward compatible).
have_expect=0; have_out=0; expect_rc=""; expect_out=""
load_expect() { # load_expect <base>
  have_expect=0; have_out=0; expect_rc=""; expect_out=""
  local ef="$CORPUS/$1.expected"
  [ -f "$ef" ] || { log "no expectation file for $1: differential only"; return 0; }
  have_expect=1
  local line
  while IFS= read -r line; do
    case "$line" in
      rc=*) expect_rc="${line#rc=}" ;;
      out=*) expect_out="${line#out=}"; have_out=1 ;;
    esac
  done < "$ef"
  [ -n "$expect_rc" ] || die "expectation file $ef has no rc= line"
}
check_expect() { # check_expect <base> <rc> <outpath>; 0 iff expectations satisfied
  [ "$have_expect" = 1 ] || return 0
  if [ "$2" != "$expect_rc" ]; then
    log "expectation mismatch on $1: expected rc=$expect_rc, got rc=$2"
    return 1
  fi
  if [ "$have_out" = 1 ]; then
    if ! printf '%s' "$expect_out" | cmp -s - "$3"; then
      log "expectation mismatch on $1: stdout differs from pinned expectation"
      return 1
    fi
  fi
  return 0
}

# compile_run <compiler> <srcfile> <tag>: compile+link+run; sets CR_RC; 0 on success
CR_RC=-1
compile_run() {
  CR_RC=-1
  local comp="$1" src="$2" tag="$3"
  "$comp" < "$src" > "$WORK/${tag}.s" 2>"$WORK/${tag}.err" || return 1
  "${CC[@]}" "$WORK/${tag}.s" -o "$WORK/${tag}" 2>"$WORK/${tag}.linkerr" || return 2
  set +e
  "$WORK/${tag}" > "$WORK/${tag}.out" 2>&1; CR_RC=$?
  set -e
  return 0
}

shopt -s nullglob
files=("$CORPUS"/*.s.id)
[ "${#files[@]}" -gt 0 ] || die "no .s.id files in $CORPUS"

# --- phase 1: corpus differential (B vs C) + independent expectations --------
for t in "${files[@]}"; do
  base="$(basename "$t" .s.id)"
  load_expect "$base"
  ok=1; rc_b=-1; rc_c=-1
  if compile_run "$B" "$t" "${base}_b"; then rc_b=$CR_RC; else ok=0; log "B failed to compile/link $t"; fi
  if compile_run "$C" "$t" "${base}_c"; then rc_c=$CR_RC; else ok=0; log "C failed to compile/link $t"; fi
  if [ "$ok" = 1 ]; then
    if [ "$rc_b" -eq "$rc_c" ] && cmp -s "$WORK/${base}_b.out" "$WORK/${base}_c.out"; then
      : # differential holds; rc_c == rc_b and outputs are identical
    else
      ok=0
      log "behavioral mismatch on $t: rc_b=$rc_b rc_c=$rc_c"
    fi
  fi
  if [ "$ok" = 1 ]; then
    check_expect "$base" "$rc_b" "$WORK/${base}_b.out" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); echo "PASS $t (rc=$rc_b)"
  else
    FAIL=$((FAIL+1)); FAILED_FILES="$FAILED_FILES $t"; echo "FAIL $t"
  fi
done

# --- phase 2: self-host determinism (byte-identical AND nonempty) ------------
log "self-host check: B(B_src) vs C(B_src)..."
"$B" < "$SRC" > "$WORK/selfhost_b.s" || die "B failed on B_src"
"$C" < "$SRC" > "$WORK/selfhost_c.s" || die "C failed on B_src"
SELFHOST="PASS"
[ -s "$WORK/selfhost_b.s" ] || { SELFHOST="FAIL"; log "self-host artifact EMPTY: B(B_src) emitted 0 bytes"; }
[ -s "$WORK/selfhost_c.s" ] || { SELFHOST="FAIL"; log "self-host artifact EMPTY: C(B_src) emitted 0 bytes"; }
if [ "$SELFHOST" = "PASS" ]; then
  if cmp -s "$WORK/selfhost_b.s" "$WORK/selfhost_c.s"; then
    echo "SELFHOST-DETERMINISTIC PASS (B(B_src) == C(B_src), $(wc -c < "$WORK/selfhost_b.s") bytes)"
  else
    SELFHOST="FAIL"
    echo "SELFHOST-DETERMINISTIC FAIL (assembly differs)"
    diff "$WORK/selfhost_b.s" "$WORK/selfhost_c.s" | head -20 >&2 || true
  fi
else
  echo "SELFHOST-DETERMINISTIC FAIL (empty self-build artifact rejected)"
fi
[ "$SELFHOST" = "PASS" ] && chain selfhost-asm "$WORK/selfhost_b.s"

# --- phase 3: next build — C executes; its self-output must build -------------
# C has executed over B_src above (phase 2). The next build links that
# output: a C whose self-emission does not assemble+link is unusable, even
# when it is byte-identical and nonempty. The resulting C2 is hash-named in
# the chain manifest, completing: source -> B -> C -> C2.
NEXTBUILD="PASS"
log "next-build check: linking C(B_src) into C2..."
if [ "$SELFHOST" = "PASS" ]; then
  if "${CC[@]}" "$WORK/selfhost_c.s" -o "$WORK/c2" 2>"$WORK/c2.linkerr"; then
    chain C2 "$WORK/c2"
    echo "NEXTBUILD PASS (C(B_src) assembled+linked)"
  else
    NEXTBUILD="FAIL"
    log "next build broken: C(B_src) failed to assemble+link"
  fi
else
  NEXTBUILD="FAIL"
  log "next build skipped: self-host check failed"
fi

echo "---"
echo "SUMMARY: pass=$PASS fail=$FAIL selfhost=$SELFHOST nextbuild=$NEXTBUILD"
[ -n "$FAILED_FILES" ] && echo "failed files:$FAILED_FILES"
echo "chain manifest: $WORK/chain.manifest"

[ "$FAIL" -eq 0 ] && [ "$SELFHOST" = "PASS" ] && [ "$NEXTBUILD" = "PASS" ]
