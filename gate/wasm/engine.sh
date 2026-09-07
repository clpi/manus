#!/bin/sh
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
idol=${IDOL_BIN:-${IDOL:-$root/zig-out/bin/idol}}
engine=$root/tools/wasm/src/engine.id
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-wasm-engine.XXXXXX") || exit 3
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -x "$idol" ] || { printf 'wasm/engine: NOT MEASURED compiler absent\n' >&2; exit 3; }
[ -f "$engine" ] || { printf 'wasm/engine: NOT MEASURED subject absent\n' >&2; exit 3; }
"$idol" compile "$engine" --backend=c --emit=c -o "$work/engine.c" >"$work/engine.log" 2>&1
engine_status=$?
if [ "$engine_status" -eq 0 ]; then
  printf 'wasm/engine: FAIL engine built without a gate update\n' >&2
  exit 1
fi
grep -q 'missing-application-id' "$work/engine.log" || { printf 'wasm/engine: FAIL engine refusal names no missing-application-id\n' >&2; exit 1; }
grep -q 'in relation: req' "$work/engine.log" || { printf 'wasm/engine: FAIL engine refusal names no req relation\n' >&2; exit 1; }
printf 'jitm = req "jit"\nmain: i64 = ()\n  0\n' > "$work/face.id"
"$idol" compile "$work/face.id" --backend=c --emit=c -o "$work/face.c" >"$work/face.log" 2>&1
face_status=$?
if [ "$face_status" -eq 0 ]; then
  printf 'wasm/engine: FAIL isolated req face built\n' >&2
  exit 1
fi
grep -q 'missing-application-id' "$work/face.log" || { printf 'wasm/engine: FAIL isolated req face refuses elsewhere\n' >&2; exit 1; }
grep -q 'in relation: req' "$work/face.log" || { printf 'wasm/engine: FAIL isolated req face names no req relation\n' >&2; exit 1; }
printf 'main: i64 = ()\n  0\n' > "$work/control.id"
"$idol" compile "$work/control.id" --backend=c --emit=c -o "$work/control.c" >"$work/control.log" 2>&1
control_status=$?
if [ "$control_status" -ne 0 ]; then
  printf 'wasm/engine: FAIL control program refused\n' >&2
  sed -n '1,10p' "$work/control.log" >&2
  exit 1
fi
[ -s "$work/control.c" ] || { printf 'wasm/engine: FAIL control program left no artifact\n' >&2; exit 1; }
printf 'wasm/engine: pass engine refused at missing-application-id in relation req; face matches; control builds\n'
