#!/usr/bin/env bash
# difftest.sh <corpus-dir> [src.id]
# Differential test B vs C, with independent correctness obligations:
#   1. For each <corpus-dir>/*.s.id (S program): compile+link with B, compile+link
#      with C, run both, compare stdout and exit code. When
#      <corpus-dir>/<base>.expected exists, the observed exit code (and stdout,
#      when the file pins it) must equal the INDEPENDENT expectation: two
#      identically-wrong compilers cannot pass on differential agreement alone.
#      Expectation files are MANDATORY: a corpus file without one fails closed.
#      Differential-only acceptance is not permitted.
#   2. Self-host check: B(B_src) vs C(B_src) assembly must be byte-identical
#      (deterministic codegen) AND nonempty. Empty self-build artifacts are
#      rejected outright.
#   3. Next-build check: C(B_src) is assembled+linked into C2, and then C2 must
#      EXECUTE the declared compilation: C2 compiles+links+runs every corpus
#      program, and each result must satisfy the independent expectations.
#      A C2 that merely links (e.g. a return-zero non-compiler) fails here.
#      Chain: declared source -> seed-built B -> B-produced C -> C-built C2 ->
#      C2 performs the required compilation correctly.
#   4. Lineage check: sprint/verify_chain.sh re-hashes every manifest entry and
#      every named producer binary (fail closed). A producer binary swapped at
#      any point — mid-run or after — fails the run.
# Every build names its artifact (sha256 + path + producer) on stderr as
# [chain] lines and in $WORK/chain.manifest, so a reviewer can verify the chain.
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
VERIFY="$SCRIPT_DIR/verify_chain.sh"

log() { echo "[difftest] $*" >&2; }
die() { echo "[difftest] FATAL: $*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
chain() { # chain <role> <path> [producer-path]: bind artifact to the exact producer binary
  local role="$1" path="$2" ppath="${3:-}"
  local h; h=$(sha256 "$path")
  local ph=""
  [ -n "$ppath" ] && ph=$(sha256 "$ppath")
  printf '%s\t%s\t%s\t%s\t%s\n' "$role" "$h" "$path" "$ppath" "$ph" >> "$WORK/chain.manifest"
  if [ -n "$ppath" ]; then
    echo "[chain] $role $h $path <- producer $ph $ppath" >&2
  else
    echo "[chain] $role $h $path" >&2
  fi
}

if command -v xcrun >/dev/null 2>&1; then CC=(xcrun clang); else CC=(clang); fi
command -v "${CC[0]}" >/dev/null 2>&1 || die "no toolchain: need xcrun or clang on PATH"
[ -d "$CORPUS" ] || die "corpus dir not found: $CORPUS"
[ -x "$B" ] || die "B missing/not executable: $B"
[ -x "$C" ] || die "C missing/not executable: $C"
[ -f "$SRC" ] || die "B_src not found: $SRC"
[ -f "$VERIFY" ] || die "chain verifier not found: $VERIFY"

mkdir -p "$WORK"
rm -f "$WORK/chain.manifest"
chain source "$SRC"
chain B "$B"
chain C "$C"

PASS=0; FAIL=0; FAILED_FILES=""

# --- independent expectations: <corpus-dir>/<base>.expected -----------------
# File format, one per line:  rc=<exit code the program must return>
#                            out=<exact stdout bytes expected> (may be empty)
# Expectation files are MANDATORY. A corpus file without one fails closed:
# differential-only acceptance is not permitted.
have_expect=0; have_out=0; expect_missing=0; expect_rc=""; expect_out=""
load_expect() { # load_expect <base>
  have_expect=0; have_out=0; expect_missing=0; expect_rc=""; expect_out=""
  local ef="$CORPUS/$1.expected"
  if [ ! -f "$ef" ]; then
    expect_missing=1
    log "FAIL-CLOSED: no expectation file for $1 ($ef): differential-only acceptance refused"
    return 0
  fi
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

# --- phase 1: corpus differential (B vs C) + mandatory independent expectations
for t in "${files[@]}"; do
  base="$(basename "$t" .s.id)"
  load_expect "$base"
  ok=1; rc_b=-1; rc_c=-1
  if [ "$expect_missing" = 1 ]; then
    ok=0
  else
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
if [ "$SELFHOST" = "PASS" ]; then
  chain selfhost-b-asm "$WORK/selfhost_b.s" "$B"
  chain selfhost-c-asm "$WORK/selfhost_c.s" "$C"
fi

# --- phase 3: next build — C2 must EXECUTE the declared compilation -----------
# C(B_src) is assembled+linked into C2. Linking alone proves nothing: C2 must
# then compile+link+run every corpus program, and each result must satisfy the
# independent expectations. A C2 that merely links — e.g. a return-zero
# non-compiler — cannot perform the required compilation and fails here.
NEXTBUILD="PASS"
log "next-build check: linking C(B_src) into C2, then C2 must compile+run the corpus..."
if [ "$SELFHOST" = "PASS" ]; then
  if "${CC[@]}" "$WORK/selfhost_c.s" -o "$WORK/c2" 2>"$WORK/c2.linkerr"; then
    chain C2 "$WORK/c2" "$C"
    echo "NEXTBUILD-LINK PASS (C(B_src) assembled+linked into C2)"
    for t in "${files[@]}"; do
      base="$(basename "$t" .s.id)"
      load_expect "$base"
      if [ "$expect_missing" = 1 ]; then
        NEXTBUILD="FAIL"
      elif compile_run "$WORK/c2" "$t" "${base}_c2"; then
        if check_expect "$base" "$CR_RC" "$WORK/${base}_c2.out"; then
          chain "c2qual-$base" "$WORK/${base}_c2" "$WORK/c2"
          echo "C2-QUALIFY PASS $t (rc=$CR_RC)"
        else
          NEXTBUILD="FAIL"
          log "C2 qualification failed on $t: result did not satisfy independent expectations"
        fi
      else
        NEXTBUILD="FAIL"
        log "C2 failed to compile/link $t: C2 cannot perform the required compilation"
      fi
    done
  else
    NEXTBUILD="FAIL"
    log "next build broken: C(B_src) failed to assemble+link"
  fi
else
  NEXTBUILD="FAIL"
  log "next build skipped: self-host check failed"
fi
if [ "$NEXTBUILD" = "PASS" ]; then
  echo "NEXTBUILD PASS (C2 executed the declared compilation correctly)"
else
  echo "NEXTBUILD FAIL"
fi

# --- phase 4: chain lineage verification (fail closed) ------------------------
# Re-hash every manifest entry and every named producer binary. A producer
# swapped at any point — mid-run or after the run — fails here.
LINEAGE="FAIL"
if "$VERIFY" "$WORK/chain.manifest" >"$WORK/verify.log" 2>&1; then
  LINEAGE="PASS"
else
  log "chain lineage verification failed:"
  sed 's/^/[difftest]   /' "$WORK/verify.log" >&2 || true
fi

echo "---"
echo "SUMMARY: pass=$PASS fail=$FAIL selfhost=$SELFHOST nextbuild=$NEXTBUILD lineage=$LINEAGE"
[ -n "$FAILED_FILES" ] && echo "failed files:$FAILED_FILES"
echo "chain manifest: $WORK/chain.manifest"

[ "$FAIL" -eq 0 ] && [ "$SELFHOST" = "PASS" ] && [ "$NEXTBUILD" = "PASS" ] && [ "$LINEAGE" = "PASS" ]
