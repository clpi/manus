#!/usr/bin/env bash
# Native lowering differential — the direct ARM64 backend must agree with the C
# backend on every corpus program.
#
# Why this exists: the direct backend's own unit tests assert that instructions
# are *present* ("at least 3 cmp, at least 3 b."). A backend can satisfy every
# one of those while computing the wrong answer, which is exactly what happened —
# `if n < 0` compiled as `if n == 0`, loop bodies returned after one iteration,
# and loop counters were folded to constants. Only a behavioural differential
# against a known-good backend catches that class.
#
# Exit 0 iff every program in examples/native_differential/ produces the same
# exit status under --backend=direct and --backend=c, with no hangs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO:-$ROOT/zig-out/bin/duo}"
CORPUS="${NATIVE_DIFF_CORPUS:-$ROOT/examples/native_differential}"
# A miscompiled loop does not fail, it spins. Bound every run.
RUN_TIMEOUT="${NATIVE_DIFF_TIMEOUT:-10}"

cd "$ROOT"
if [ ! -x "$DUO" ]; then
  "${ZIG:-zig}" build
fi

TIMEOUT_BIN=""
for cand in timeout gtimeout; do
  if command -v "$cand" >/dev/null 2>&1; then TIMEOUT_BIN="$cand"; break; fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/duo-native-diff.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

run_binary() {
  # Echoes the exit status; 124 marks a timeout (a spinning miscompiled loop).
  local bin="$1"
  local rc=0
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$RUN_TIMEOUT" "$bin" >/dev/null 2>&1 || rc=$?
  else
    "$bin" >/dev/null 2>&1 || rc=$?
  fi
  echo "$rc"
}

agree=0
diverge=0
failures=()

shopt -s nullglob
for src in "$CORPUS"/*.duo; do
  name="$(basename "$src" .duo)"
  direct_bin="$WORK_DIR/$name.direct"
  c_bin="$WORK_DIR/$name.c"

  if ! "$DUO" compile "$src" --backend=direct --emit exe -o "$direct_bin" >/dev/null 2>&1; then
    failures+=("$name: direct backend failed to compile")
    diverge=$((diverge + 1))
    continue
  fi
  if ! "$DUO" compile "$src" --backend=c --emit exe -o "$c_bin" >/dev/null 2>&1; then
    failures+=("$name: c backend failed to compile")
    diverge=$((diverge + 1))
    continue
  fi

  direct_rc="$(run_binary "$direct_bin")"
  c_rc="$(run_binary "$c_bin")"

  if [ "$direct_rc" = "124" ]; then
    failures+=("$name: direct backend HUNG (>${RUN_TIMEOUT}s) — c=$c_rc")
    diverge=$((diverge + 1))
  elif [ "$direct_rc" != "$c_rc" ]; then
    failures+=("$name: c=$c_rc direct=$direct_rc")
    diverge=$((diverge + 1))
  else
    agree=$((agree + 1))
  fi
done

# `native_only/` gates capabilities where the C backend is not a valid oracle
# (it cannot compile them at all), so the expected exit status is declared in the
# file itself as `-- expect: N`. These block like the main corpus: they pin
# self-hosting capabilities that have no differential counterpart.
for src in "$CORPUS"/native_only/*.duo; do
  name="$(basename "$src" .duo)"
  expected="$(sed -n 's/^-- expect: *\([0-9][0-9]*\).*/\1/p' "$src" | head -1)"
  if [ -z "$expected" ]; then
    failures+=("$name: native_only file has no '-- expect: N' header")
    diverge=$((diverge + 1))
    continue
  fi
  bin="$WORK_DIR/no_$name"
  if ! "$DUO" compile "$src" --backend=direct --emit exe -o "$bin" >/dev/null 2>&1; then
    failures+=("$name: direct backend failed to compile (native_only)")
    diverge=$((diverge + 1))
    continue
  fi
  actual="$(run_binary "$bin")"
  if [ "$actual" != "$expected" ]; then
    failures+=("$name: expected $expected, got $actual (native_only)")
    diverge=$((diverge + 1))
  else
    agree=$((agree + 1))
  fi
done

# Frontier reporting. `unsupported/` holds programs the direct backend refuses
# to compile (a capability gap — honest, not a miscompilation). `known_divergent/`
# holds programs it compiles and gets WRONG; those are open bugs, listed every
# run so they stay visible instead of decaying into folklore. Neither blocks:
# the gate exists to stop regressions in what already works.
unsupported_count=0
for src in "$CORPUS"/unsupported/*.duo; do
  unsupported_count=$((unsupported_count + 1))
  echo "native_differential: unsupported (direct backend cannot compile) — $(basename "$src" .duo)"
done
for src in "$CORPUS"/known_divergent/*.duo; do
  name="$(basename "$src" .duo)"
  direct_bin="$WORK_DIR/kd_$name.direct"
  c_bin="$WORK_DIR/kd_$name.c"
  if "$DUO" compile "$src" --backend=direct --emit exe -o "$direct_bin" >/dev/null 2>&1 &&
     "$DUO" compile "$src" --backend=c --emit exe -o "$c_bin" >/dev/null 2>&1; then
    d="$(run_binary "$direct_bin")"
    c="$(run_binary "$c_bin")"
    if [ "$d" = "$c" ]; then
      echo "native_differential: known_divergent now AGREES — $name (promote it into the corpus)"
    else
      echo "native_differential: known divergence — $name (c=$c direct=$d)"
    fi
  fi
done

echo "native_differential: $agree agree, $diverge diverge, $unsupported_count unsupported (corpus: $CORPUS)"
if [ "$diverge" -ne 0 ]; then
  printf 'native_differential: FAIL\n'
  for f in "${failures[@]}"; do printf '  %s\n' "$f"; done
  exit 1
fi
if [ "$agree" -eq 0 ]; then
  echo "native_differential: FAIL (empty corpus)"
  exit 1
fi
echo "native_differential: PASS"
