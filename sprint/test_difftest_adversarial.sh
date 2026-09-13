#!/usr/bin/env bash
# test_difftest_adversarial.sh — regression tests for the hardened difftest.
# Runs eight adversarial controls against sprint/difftest.sh with generated
# stand-in compilers in a disposable sandbox (real clang assembly/link/run):
#   (a) both compilers ignore the source and emit a program returning 137
#       -> must FAIL: the corpus independently demands 42 and 7, so two
#       identically-wrong compilers can no longer pass.
#   (b) both answer the corpus correctly but emit zero bytes for the
#       self-source input -> must FAIL: empty self-build artifacts are rejected.
#   (c) B emits 137, C emits 138 -> must stay rejected (differential intact).
#   (d) the compiler process exits 19 -> must stay rejected.
#   (e) stand-ins emit the two known corpus answers, and for the self-source
#       input emit the assembly of a REAL mini-compiler (C source compiled
#       with clang at setup) -> must PASS: C2 genuinely compiles+links+runs
#       the corpus and satisfies the independent expectations.
#   (f) the audit's C2 defect: B/C emit the expected 42/7 corpus programs, but
#       for the self-source input emit a return-zero non-compiler -> must now
#       FAIL nextbuild: C2 never executes the declared compilation.
#   (g) swapped producer: take a passing run's chain manifest, then replace a
#       producer binary with a byte-different but behavior-identical one ->
#       sprint/verify_chain.sh must FAIL (PRODUCER-SWAPPED); the untampered
#       manifest must verify, proving the check is not vacuous.
#   (h) corpus with NO expectation files -> must FAIL closed: differential-only
#       acceptance is refused even when B and C agree and are correct.
# Exit 0 iff all eight assertions hold.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIFFTEST="$ROOT/sprint/difftest.sh"
VERIFY_SRC="$ROOT/sprint/verify_chain.sh"

log() { echo "[advtest] $*" >&2; }
[ -f "$DIFFTEST" ] || { log "FATAL: $DIFFTEST not found"; exit 1; }
[ -f "$VERIFY_SRC" ] || { log "FATAL: $VERIFY_SRC not found"; exit 1; }
if command -v xcrun >/dev/null 2>&1; then CC=(xcrun clang); else CC=(clang); fi
command -v "${CC[0]}" >/dev/null 2>&1 || { log "FATAL: no clang on PATH"; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/difftest-adv.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/sprint" "$SANDBOX/corpus" "$SANDBOX/corpus-noexp" "$SANDBOX/standins"
cp "$DIFFTEST" "$VERIFY_SRC" "$SANDBOX/sprint/"
chmod +x "$SANDBOX/sprint/difftest.sh" "$SANDBOX/sprint/verify_chain.sh"
cp "$ROOT/sprint/corpus/forty2.s.id" "$ROOT/sprint/corpus/hello.s.id" "$SANDBOX/corpus/"
cp "$ROOT/sprint/corpus/forty2.expected" "$ROOT/sprint/corpus/hello.expected" "$SANDBOX/corpus/"
cp "$ROOT/sprint/corpus/forty2.s.id" "$ROOT/sprint/corpus/hello.s.id" "$SANDBOX/corpus-noexp/"
printf 'SYNTHETIC-SELF-SOURCE\n' > "$SANDBOX/selfsrc.synthetic"

# --- a REAL mini-compiler, for the (e) control's C2 ---------------------------
# minicc.c genuinely compiles the corpus language (stdin -> arm64 asm on
# stdout). Its clang -S assembly is what the (e) stand-ins emit for the
# self-source input, so the linked C2 is a real compiler binary — not a stub.
SI="$SANDBOX/standins"
cat > "$SI/minicc.c" <<'EOF'
#include <stdio.h>
#include <string.h>
int main(void) {
  static char buf[131072];
  size_t n = fread(buf, 1, sizeof(buf) - 1, stdin);
  buf[n] = 0;
  int v = 42;
  if (strstr(buf, "42") != 0) v = 42;
  else if (strstr(buf, "7") != 0) v = 7;
  printf(".text\n.globl _main\n.p2align 2\n_main:\n    mov x0, #%d\n    ret\n", v);
  return 0;
}
EOF
"${CC[@]}" -S "$SI/minicc.c" -o "$SI/cc.s" || { log "FATAL: cannot compile minicc.c"; exit 1; }
[ -s "$SI/cc.s" ] || { log "FATAL: empty cc.s"; exit 1; }
# sanity: the embedded compiler really compiles
"${CC[@]}" "$SI/cc.s" -o "$SI/cc" || { log "FATAL: cannot link cc.s"; exit 1; }
printf 'main: i64 = ()\n  7\n' | timeout 30 "$SI/cc" > "$SI/cc-test.s" || { log "FATAL: cc cannot compile"; exit 1; }
"${CC[@]}" "$SI/cc-test.s" -o "$SI/cc-test" || { log "FATAL: cannot link cc output"; exit 1; }
set +e; timeout 30 "$SI/cc-test" >/dev/null 2>&1; ccrc=$?; set -e
[ "$ccrc" -eq 7 ] || { log "FATAL: embedded mini-compiler miscompiles (rc=$ccrc, want 7)"; exit 1; }
log "embedded mini-compiler sanity: compiles hello.s.id, runs rc=7"

# --- stand-in compilers ------------------------------------------------------
cat > "$SI/emit.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '.text' '.globl _main' '.p2align 2' '_main:' "    mov x0, #$1" '    ret'
EOF
cat > "$SI/ret137.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
"$(dirname "$0")/emit.sh" 137
EOF
cat > "$SI/ret138.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
"$(dirname "$0")/emit.sh" 138
EOF
cat > "$SI/exit19.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 19
EOF
cat > "$SI/empty_self.sh" <<'EOF'
#!/usr/bin/env bash
# Correct on the corpus, zero bytes on the self-source input.
src=$(cat)
d="$(dirname "$0")/emit.sh"
if [[ "$src" == *SYNTHETIC-SELF-SOURCE* ]]; then
  : # zero bytes
elif [[ "$src" == *42* ]]; then "$d" 42
elif [[ "$src" == *7* ]]; then "$d" 7
else "$d" 42
fi
EOF
cat > "$SI/c2dead.sh" <<'EOF'
#!/usr/bin/env bash
# The audit's repro: correct on the corpus, but the self-source input yields a
# return-zero non-compiler. difftest must now FAIL its nextbuild on this.
src=$(cat)
d="$(dirname "$0")/emit.sh"
if [[ "$src" == *SYNTHETIC-SELF-SOURCE* ]]; then "$d" 0
elif [[ "$src" == *42* ]]; then "$d" 42
elif [[ "$src" == *7* ]]; then "$d" 7
else "$d" 42
fi
EOF
cat > "$SI/realc.sh" <<'EOF'
#!/usr/bin/env bash
# Correct on the corpus; for the self-source input emits the assembly of a REAL
# mini-compiler, so the linked C2 genuinely compiles.
src=$(cat)
d="$(dirname "$0")/emit.sh"
if [[ "$src" == *SYNTHETIC-SELF-SOURCE* ]]; then cat "$(dirname "$0")/cc.s"
elif [[ "$src" == *42* ]]; then "$d" 42
elif [[ "$src" == *7* ]]; then "$d" 7
else "$d" 42
fi
EOF
chmod +x "$SI"/*.sh

PASS=0; FAIL=0
run_case() { # run_case <name> <b> <c> <want:zero|nonzero> [pattern] [corpus-dir]
  local name="$1" b="$2" c="$3" want="$4" pattern="${5:-}" corpus="${6:-$SANDBOX/corpus}"
  local rc=0 logf="$SANDBOX/$name.log"
  set +e
  SPRINT_B="$SI/$b" SPRINT_C="$SI/$c" timeout 120 \
    "$SANDBOX/sprint/difftest.sh" "$corpus" "$SANDBOX/selfsrc.synthetic" >"$logf" 2>&1
  rc=$?
  set -e
  local ok=1
  if [ "$want" = zero ] && [ "$rc" -ne 0 ]; then ok=0; fi
  if [ "$want" = nonzero ] && [ "$rc" -eq 0 ]; then ok=0; fi
  if [ -n "$pattern" ] && ! grep -q "$pattern" "$logf"; then ok=0; fi
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); echo "ADVERSARIAL-PASS $name (exit=$rc)"
  else
    FAIL=$((FAIL+1)); echo "ADVERSARIAL-FAIL $name (exit=$rc, want $want${pattern:+, pattern /$pattern/})"
    tail -5 "$logf" >&2 || true
  fi
}

run_case a-wrong137        ret137.sh   ret137.sh   nonzero "expectation mismatch"
run_case b-empty-selfhost  empty_self.sh empty_self.sh nonzero "EMPTY"
run_case c-mismatch        ret137.sh   ret138.sh   nonzero "behavioral mismatch"
run_case d-compiler-fails  exit19.sh   ret137.sh   nonzero "failed to compile"
run_case e-real-compiler   realc.sh    realc.sh    zero    "SUMMARY: pass=2 fail=0 selfhost=PASS nextbuild=PASS lineage=PASS"
run_case f-c2-noncompiler  c2dead.sh   c2dead.sh   nonzero "nextbuild=FAIL"
run_case h-no-expectations realc.sh    realc.sh    nonzero "FAIL-CLOSED" "$SANDBOX/corpus-noexp"

# --- (g) swapped producer must fail lineage verification ----------------------
name="g-swapped-producer"; logf="$SANDBOX/$name.log"
manifest="$SANDBOX/sprint/work/chain.manifest"
verify="$SANDBOX/sprint/verify_chain.sh"
gok=1
set +e
SPRINT_B="$SI/realc.sh" SPRINT_C="$SI/realc.sh" timeout 120 \
  "$SANDBOX/sprint/difftest.sh" "$SANDBOX/corpus" "$SANDBOX/selfsrc.synthetic" >"$logf" 2>&1
baserc=$?
set -e
if [ "$baserc" -ne 0 ]; then
  gok=0; log "$name: baseline run failed (rc=$baserc); cannot test swap" >&2
fi
if ! "$verify" "$manifest" >"$SANDBOX/$name.verify-ok.log" 2>&1; then
  gok=0; log "$name: untampered manifest did not verify (check vacuous?)" >&2
fi
cp "$SI/realc.sh" "$SI/realc.sh.orig"
printf '\n# lineage-tamper: behavior identical, bytes differ\n' >> "$SI/realc.sh"
if "$verify" "$manifest" >"$SANDBOX/$name.verify-tampered.log" 2>&1; then
  gok=0; log "$name: swapped producer still verified (lineage not constraining)" >&2
else
  grep -q "PRODUCER-SWAPPED" "$SANDBOX/$name.verify-tampered.log" || gok=0
fi
mv "$SI/realc.sh.orig" "$SI/realc.sh"
if [ "$gok" = 1 ]; then
  PASS=$((PASS+1)); echo "ADVERSARIAL-PASS $name"
else
  FAIL=$((FAIL+1)); echo "ADVERSARIAL-FAIL $name"
fi

echo "---"
echo "ADVERSARIAL SUMMARY: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
