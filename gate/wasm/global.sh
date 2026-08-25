#!/bin/sh
# One graph-owned module-global initializer, observed through both surviving
# realizations. Status alone cannot see the defect: both programs exit 40, so
# stdout is compared byte-for-byte as the demanded observation.
set -u

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
idol=${IDOL_BIN:-$root/zig-out/bin/idol}
wasmtime=${WASMTIME_BIN:-$(command -v wasmtime 2>/dev/null || true)}
subject=$root/examples/local_test.id
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-wasm-global.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$idol" in
    /*) ;;
    *) idol=$root/${idol#./} ;;
esac

[ -x "$idol" ] || {
    printf 'wasm/global: compiler absent: %s\n' "$idol" >&2
    exit 2
}
[ -n "$wasmtime" ] && [ -x "$wasmtime" ] || {
    printf 'wasm/global: wasmtime absent\n' >&2
    exit 2
}
[ -f "$subject" ] || {
    printf 'wasm/global: subject absent: %s\n' "$subject" >&2
    exit 2
}

# THIS IS A DIFFERENTIAL, so it needs BOTH realizations, and the wasmtime check
# above was hiding the other half. On a host with no wasmtime it said "wasmtime
# absent" and stopped; install wasmtime and the direct arm then fails DNB004 and
# the gate reports `FAIL direct=1 compile=0 wasm=40` — a differential naming a
# disagreement where one side never ran. Two host facts, and the gate could only
# see one of them.
#
# `gate/all.sh` would classify this correctly today only because the compiler's
# own DNB004 text leaks into the log it greps, which is the fragile log-matching
# the header of gate/realization/direct.sh exists to end. Asked directly instead.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the direct-vs-wasm stdout differential (the direct arm is one of the two observations)'
    exit 1
fi

mkdir "$work/direct" "$work/wasm" || exit 2
(
    cd "$work/direct" || exit 125
    "$idol" run --backend=direct "$subject"
) >"$work/direct.out" 2>"$work/direct.err"
direct_status=$?

"$idol" compile --backend=wasm --target=wasm32-wasi "$subject" \
    -o "$work/wasm/program.wasm" >"$work/wasm/compile.out" 2>"$work/wasm/compile.err"
compile_status=$?
if [ "$compile_status" -eq 0 ]; then
    "$wasmtime" run "$work/wasm/program.wasm" \
        >"$work/wasm.out" 2>"$work/wasm.err"
    wasm_status=$?
else
    wasm_status=255
    : >"$work/wasm.out"
fi

printf '10\n20\n30\n40\n' >"$work/expected"
ok=1
[ "$direct_status" -eq 40 ] || ok=0
[ "$compile_status" -eq 0 ] || ok=0
[ "$wasm_status" -eq 40 ] || ok=0
cmp -s "$work/expected" "$work/direct.out" || ok=0
cmp -s "$work/expected" "$work/wasm.out" || ok=0
cmp -s "$work/direct.out" "$work/wasm.out" || ok=0

if [ "$ok" -ne 1 ]; then
    printf 'wasm/global: FAIL direct=%s compile=%s wasm=%s\n' \
        "$direct_status" "$compile_status" "$wasm_status" >&2
    printf '%s\n' '--- direct stdout' >&2
    sed -n '1,20p' "$work/direct.out" >&2
    printf '%s\n' '--- direct stderr' >&2
    sed -n '1,40p' "$work/direct.err" >&2
    printf '%s\n' '--- wasm compile stderr' >&2
    sed -n '1,40p' "$work/wasm/compile.err" >&2
    printf '%s\n' '--- wasm stdout' >&2
    sed -n '1,20p' "$work/wasm.out" >&2
    printf '%s\n' '--- wasm stderr' >&2
    sed -n '1,40p' "$work/wasm.err" >&2
    exit 1
fi

printf 'wasm/global: pass direct=40 wasm=40 stdout=10,20,30,40\n'
