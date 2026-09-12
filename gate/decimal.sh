#!/bin/sh
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "decimal: compiler unavailable" >&2; exit 2; }
"$idol" run --backend=direct "$root/gate/outcome.id" -- "$root/gate/decimal.sh" || exit 1
limit=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then limit="$candidate"; break; fi
done
[ -n "$limit" ] || { echo "decimal: timeout command unavailable" >&2; exit 2; }
wasmrun=""
for candidate in wasmtime wasmer; do
  if command -v "$candidate" >/dev/null 2>&1; then wasmrun="$candidate"; break; fi
done
[ -n "$wasmrun" ] || { echo "decimal: Wasm execution unavailable" >&2; exit 2; }
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
fail=0
measured=0
note() { printf 'decimal: %s\n' "$1"; }
bad() { printf 'decimal: FAIL: %s\n' "$1" >&2; fail=1; }

carrier() {
  name=$1
  want=$2
  body=$3
  source=${4:-$work/$name.id}
  if [ "$#" -lt 4 ]; then printf '%s\n' "$body" > "$source"; fi
  if [ ! -f "$source" ]; then bad "$name source unavailable"; return; fi
  "$limit" 30 "$idol" compile --backend=wasm -o "$work/$name.wasm" "$source" >"$work/$name.log" 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    bad "$name required program did not compile: status $status"
    head -3 "$work/$name.log" >&2
    return
  fi
  if [ ! -f "$work/$name.wasm" ] || [ ! -s "$work/$name.wasm" ]; then
    bad "$name compilation produced no nonempty artifact"
    return
  fi
  "$limit" 30 "$wasmrun" "$work/$name.wasm" >"$work/$name.out" 2>"$work/$name.err"
  status=$?
  if [ "$status" -ne 0 ]; then
    bad "$name required execution did not succeed: status $status"
    head -3 "$work/$name.err" >&2
    return
  fi
  if [ "$(wc -c < "$work/$name.out")" -gt 65536 ]; then
    bad "$name output exceeded the observation bound"
    return
  fi
  measured=$((measured + 1))
  got=$(tr '\n' ' ' < "$work/$name.out" | sed 's/ *$//')
  if [ "$got" = "$want" ]; then
    note "$name answered '$want' and completed successfully"
  else
    bad "$name answered '$got', expected '$want'"
  fi
}

carrier exact '1 1 0' '' "$root/examples/decimal/exact.id"
carrier smallexp '1 0 0' '
holds: i64 = ()
  tiny = 1e-19
  if tiny == 1e-19
    1
  else
    0

vanished: i64 = ()
  tiny = 1e-19
  if tiny == 0.0
    1
  else
    0

swallowed: i64 = ()
  if 0.1 + 1e-19 == 0.1
    1
  else
    0

print(holds())
print(vanished())
print(swallowed())
'
carrier intfloor '1 0 0' '
floorv: i64 = ()
  -9223372036854775808

holds: i64 = ()
  if floorv() == -9223372036854775808
    1
  else
    0

vanished: i64 = ()
  if floorv() == 0
    1
  else
    0

crowded: i64 = ()
  if 9223372036854775808.0 == 9223372036854775807.0
    1
  else
    0

print(holds())
print(vanished())
print(crowded())
'
carrier zerounder '1' '
holds: i64 = ()
  z = 0.0e-2147483648
  if z == 0.0
    1
  else
    0

print(holds())
'
carrier zeroover '1' '
holds: i64 = ()
  z = 0e+2147483647
  if z == 0.0
    1
  else
    0

print(holds())
'
carrier ordered '1 1 0' '
tight: i64 = ()
  if 0.1 < 0.1 + 1e-19
    1
  else
    0

crowded: i64 = ()
  if 9223372036854775807.0 < 9223372036854775808.0
    1
  else
    0

merged: i64 = ()
  if 0.1 >= 0.1 + 1e-19
    1
  else
    0

print(tight())
print(crowded())
print(merged())
'
[ "$measured" -gt 0 ] || { echo "decimal: no successful execution observed" >&2; exit 1; }
note "observed $measured completed executions"
[ "$fail" -eq 0 ] || exit 1
note "PASS"
