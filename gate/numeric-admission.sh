#!/bin/sh
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "numeric-admission: compiler unavailable" >&2; exit 2; }
limit=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then limit="$candidate"; break; fi
done
[ -n "$limit" ] || { echo "numeric-admission: timeout command unavailable" >&2; exit 2; }
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
fail=0
note() { printf 'numeric-admission: %s\n' "$1"; }
bad() { printf 'numeric-admission: FAIL: %s\n' "$1" >&2; fail=1; }

src="$root/gate/numeric-admission.id"
[ -f "$src" ] || { bad "admission source unavailable"; }

refused() {
  name=$1
  log=$2
  if grep -q "specialized-parameter-domain\|any-parameter-fp-operand" "$log" 2>/dev/null; then
    note "$name refused the surviving float call before artifact emission"
  else
    bad "$name did not refuse the surviving float call"
    head -3 "$log" >&2
  fi
}

if [ -f "$src" ]; then
  "$limit" 60 "$idol" run --backend=direct "$src" >"$work/direct.out" 2>"$work/direct.log"
  if [ $? -eq 0 ]; then
    bad "direct backend executed the surviving float call instead of refusing it"
  else
    refused direct "$work/direct.log"
  fi

  "$limit" 60 "$idol" compile --backend=native --no-cache -o "$work/adm" "$src" >"$work/native.log" 2>&1
  if [ $? -eq 0 ]; then
    bad "native backend emitted an artifact for the surviving float call instead of refusing it"
  else
    refused native "$work/native.log"
  fi

  "$limit" 60 "$idol" compile --backend=wasm --no-cache -o "$work/adm.wasm" "$src" >"$work/wasm.log" 2>&1
  if [ $? -eq 0 ]; then
    bad "wasm backend emitted an artifact for the surviving float call instead of refusing it"
  else
    refused wasm "$work/wasm.log"
  fi
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
note "PASS"
