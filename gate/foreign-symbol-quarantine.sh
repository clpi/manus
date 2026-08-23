#!/bin/sh
# Migration-boundary symbol quarantine. This gate does not claim `@ffi`,
# `@export`, or `@c.export` are canonical `@` faces; it proves malformed
# compatibility spellings stop before direct, C, or Wasm artifact creation.
# Graph-owned linkage identity, bootstrap collision safety, ABI, ownership, and
# lifetime remain OPEN under GAP-211/GAP-107.
set -u

root=${FOREIGN_SYMBOL_ROOT:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)}
idol=${IDOL:-$root/zig-out/bin/idol}

if [ ! -x "$idol" ]; then
    printf 'foreign-symbol-quarantine: INFRA compiler unavailable: %s\n' "$idol" >&2
    exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-foreign-symbol.XXXXXX") || exit 2
cleanup() {
    chmod -R u+w "$work" 2>/dev/null || true
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

invalid=$work/invalid.id
valid_c=$work/valid-c.id
valid_wasm=$work/valid-wasm.id
collision=$work/collision.id

printf '%s\n' \
    '@ffi("bad-name")' \
    'bad: i64 = ()' \
    '    0' >"$invalid"
printf '%s\n' \
    '@c.export("idol_gate_ok")' \
    'ok: i64 = ()' \
    '    7' >"$valid_c"
printf '%s\n' \
    '@export' \
    '_api: i64 = ()' \
    '    7' \
    '_api()' >"$valid_wasm"
printf '%s\n' \
    '@c.export("shared")' \
    'first: i64 = ()' \
    '    1' \
    '@c.export("shared")' \
    'second: i64 = ()' \
    '    2' >"$collision"

pass=0
fail=0

ok() {
    pass=$((pass + 1))
    printf 'foreign-symbol-quarantine: PASS %s\n' "$*"
}

bad() {
    fail=$((fail + 1))
    printf 'foreign-symbol-quarantine: FAIL %s\n' "$*" >&2
}

refuses_without_artifact() {
    label=$1
    artifact=$2
    shift 2
    log=$work/$label.log
    if "$idol" compile "$@" "$invalid" -o "$artifact" >"$log" 2>&1; then
        bad "$label accepted malformed @ffi symbol"
        return
    fi
    if ! grep -Fq "invalid migration boundary attribute '@ffi'" "$log"; then
        bad "$label refused without the boundary diagnostic"
        return
    fi
    if [ -e "$artifact" ]; then
        bad "$label wrote an artifact after refusal"
        return
    fi
    ok "$label refuses and writes no artifact"
}

refuses_without_artifact direct "$work/invalid.o" --backend=direct --lib
refuses_without_artifact c "$work/invalid.c" --backend=c --emit=c
refuses_without_artifact wasm "$work/invalid.wasm" --backend=wasm --target=wasm32-wasi

if "$idol" compile --backend=direct --lib "$valid_c" -o "$work/valid.o" >"$work/valid-direct.log" 2>&1 &&
   [ -s "$work/valid.o" ]; then
    ok 'direct positive control reaches an artifact'
else
    bad 'direct positive control did not reach an artifact'
    sed 's/^/foreign-symbol-quarantine: direct: /' "$work/valid-direct.log" >&2
fi

if "$idol" compile --backend=c --emit=c "$valid_c" -o "$work/valid.c" >"$work/valid-c.log" 2>&1 &&
   [ -s "$work/valid.c" ]; then
    ok 'C positive control reaches an artifact'
else
    bad 'C positive control did not reach an artifact'
    sed 's/^/foreign-symbol-quarantine: c: /' "$work/valid-c.log" >&2
fi

# This is the load-bearing target split: plain @export may retain an underscored
# Wasm-facing declaration even though public C export policy rejects that name.
if "$idol" compile --backend=wasm --target=wasm32-wasi "$valid_wasm" -o "$work/valid.wasm" >"$work/valid-wasm.log" 2>&1 &&
   [ -s "$work/valid.wasm" ]; then
    ok 'plain @export Wasm positive control reaches an artifact'
else
    bad 'plain @export Wasm positive control did not reach an artifact'
    sed 's/^/foreign-symbol-quarantine: wasm: /' "$work/valid-wasm.log" >&2
fi

# Per-declaration syntax quarantine is not graph-owned symbol identity. Keep the
# still-admitted two-declaration collision explicitly paired with the OPEN gap
# so this gate cannot be cited as GAP-211 closure.
if "$idol" check "$collision" >"$work/collision.log" 2>&1 &&
   grep -Fq '**Status:** OPEN' "$root/gaps/GAP-211.md"; then
    ok 'GAP-211 OPEN: cross-declaration physical-symbol collision remains unowned'
else
    bad 'GAP-211 nonclosure control moved without an explicit gap transition'
fi

printf 'foreign-symbol-quarantine: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
