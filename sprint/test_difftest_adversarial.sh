#!/usr/bin/env bash
# test_difftest_adversarial.sh — regression tests for the hardened difftest.
# Runs the five adversarial controls against sprint/difftest.sh with generated
# stand-in compilers in a disposable sandbox (real clang assembly/link/run):
#   (a) both compilers ignore the source and emit a program returning 137
#       -> must now FAIL: the corpus independently demands 42 and 7, so two
#       identically-wrong compilers can no longer pass.
#   (b) both answer the corpus correctly but emit zero bytes for the
#       self-source input -> must now FAIL: empty self-build artifacts are
#       rejected. (Sharpens the audit's (b): the corpus answers are right, so
#       the only defect under test is the empty self-host output.)
#   (c) B emits 137, C emits 138 -> must stay rejected (differential intact).
#   (d) the compiler process exits 19 -> must stay rejected.
#   (e) stand-ins emit the two known corpus answers -> must pass.
# Exit 0 iff all five assertions hold.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIFFTEST="$ROOT/sprint/difftest.sh"

log() { echo "[advtest] $*" >&2; }
[ -f "$DIFFTEST" ] || { log "FATAL: $DIFFTEST not found"; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/difftest-adv.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/sprint" "$SANDBOX/corpus" "$SANDBOX/standins"
cp "$DIFFTEST" "$SANDBOX/sprint/difftest.sh"
cp "$ROOT/sprint/corpus/forty2.s.id" "$ROOT/sprint/corpus/hello.s.id" "$SANDBOX/corpus/"
cp "$ROOT/sprint/corpus/forty2.expected" "$ROOT/sprint/corpus/hello.expected" "$SANDBOX/corpus/"
printf 'SYNTHETIC-SELF-SOURCE\n' > "$SANDBOX/selfsrc.synthetic"

# --- stand-in compilers (generated; arm64 _main returning a constant) --------
SI="$SANDBOX/standins"
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
cat > "$SI/correct.sh" <<'EOF'
#!/usr/bin/env bash
src=$(cat)
d="$(dirname "$0")/emit.sh"
if [[ "$src" == *42* ]]; then "$d" 42
elif [[ "$src" == *7* ]]; then "$d" 7
else "$d" 42
fi
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
chmod +x "$SI"/*.sh

PASS=0; FAIL=0
run_case() { # run_case <name> <b> <c> <want:zero|nonzero> [pattern that must appear in output]
  local name="$1" b="$2" c="$3" want="$4" pattern="${5:-}"
  local rc=0 logf="$SANDBOX/$name.log"
  set +e
  SPRINT_B="$SI/$b" SPRINT_C="$SI/$c" timeout 120 \
    "$SANDBOX/sprint/difftest.sh" "$SANDBOX/corpus" "$SANDBOX/selfsrc.synthetic" >"$logf" 2>&1
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
run_case e-correct         correct.sh  correct.sh  zero    "SUMMARY: pass=2 fail=0 selfhost=PASS nextbuild=PASS"

echo "---"
echo "ADVERSARIAL SUMMARY: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
