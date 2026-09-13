#!/bin/sh
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "numeric-matrix: compiler unavailable" >&2; exit 2; }
limit=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then limit="$candidate"; break; fi
done
[ -n "$limit" ] || { echo "numeric-matrix: timeout command unavailable" >&2; exit 2; }
wasmrun=""
for candidate in wasmtime wasmer; do
  if command -v "$candidate" >/dev/null 2>&1; then wasmrun="$candidate"; break; fi
done
[ -n "$wasmrun" ] || { echo "numeric-matrix: Wasm execution unavailable" >&2; exit 2; }
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
fail=0
measured=0
note() { printf 'numeric-matrix: %s\n' "$1"; }
bad() { printf 'numeric-matrix: FAIL: %s\n' "$1" >&2; fail=1; }

want="1 1 1 0 0 0"
src="$root/gate/numeric-matrix.id"
[ -f "$src" ] || { bad "matrix source unavailable"; }

check() {
  name=$1
  got=$2
  if [ "$got" = "$want" ]; then
    note "$name answered '$want' and completed successfully"
    measured=$((measured + 1))
  else
    bad "$name answered '$got', expected '$want'"
  fi
}

if [ -f "$src" ]; then
  "$limit" 60 "$idol" run --backend=direct "$src" >"$work/direct.out" 2>"$work/direct.err"
  status=$?
  if [ "$status" -ne 0 ]; then
    bad "direct backend did not complete: status $status"
    head -3 "$work/direct.err" >&2
  else
    check direct "$(tr '\n' ' ' < "$work/direct.out" | sed 's/ *$//')"
  fi

  "$limit" 60 "$idol" compile --backend=native --no-cache -o "$work/matrix" "$src" >"$work/native.log" 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    bad "native backend did not compile: status $status"
    head -3 "$work/native.log" >&2
  elif [ ! -s "$work/matrix" ]; then
    bad "native compilation produced no nonempty artifact"
  else
    "$limit" 30 "$work/matrix" >"$work/native.out" 2>"$work/native.err"
    status=$?
    if [ "$status" -ne 0 ]; then
      bad "native execution did not succeed: status $status"
      head -3 "$work/native.err" >&2
    else
      check native "$(tr '\n' ' ' < "$work/native.out" | sed 's/ *$//')"
    fi
  fi

  "$limit" 60 "$idol" compile --backend=wasm --no-cache -o "$work/matrix.wasm" "$src" >"$work/wasm.log" 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    bad "wasm backend did not compile: status $status"
    head -3 "$work/wasm.log" >&2
  elif [ ! -s "$work/matrix.wasm" ]; then
    bad "wasm compilation produced no nonempty artifact"
  else
    "$limit" 30 "$wasmrun" "$work/matrix.wasm" >"$work/wasm.out" 2>"$work/wasm.err"
    status=$?
    if [ "$status" -ne 0 ]; then
      bad "wasm execution did not succeed: status $status"
      head -3 "$work/wasm.err" >&2
    else
      check wasm "$(tr '\n' ' ' < "$work/wasm.out" | sed 's/ *$//')"
    fi
  fi
fi

note "observed $measured completed executions"
if [ "$fail" -ne 0 ]; then exit 1; fi
note "PASS"
