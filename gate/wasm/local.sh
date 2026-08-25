#!/bin/sh
# GAP-238 pin: a Lua `local function` is the same graph-owned callable its
# `.id` spelling is, all the way through the wasm32-wasi realization. The
# defect this pins was invisible to the graph — both ingests published the
# identical callable linkage — so the observation compared here is the
# executed program's stdout, byte-for-byte, between the two ingests through
# the SAME realization. Exit status alone cannot see it either: the broken
# tree refused at compile, and a future half-fix could compile a wrong body.
#
# Negative control: a genuinely unknown call target still refuses BY NAME.
# The positive arm above is this zero's positive control.
set -u

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
idol=${IDOL_BIN:-$root/zig-out/bin/idol}
wasmtime=${WASMTIME_BIN:-$(command -v wasmtime 2>/dev/null || true)}
subject=$root/examples/hello.lua
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-wasm-local.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$idol" in
    /*) ;;
    *) idol=$root/${idol#./} ;;
esac

[ -x "$idol" ] || {
    printf 'wasm/local: compiler absent: %s\n' "$idol" >&2
    exit 2
}
[ -n "$wasmtime" ] && [ -x "$wasmtime" ] || {
    printf 'wasm/local: wasmtime absent\n' >&2
    exit 2
}
[ -f "$subject" ] || {
    printf 'wasm/local: subject absent: %s\n' "$subject" >&2
    exit 2
}

# The `.id` spelling of examples/hello.lua: the same two print applications
# and the same module-level callable, with no `local` face to mis-read.
cat >"$work/hello.id" <<'EOF'
print("Hello from duo!")

greet = (name)
    "Hello, " .. name .. "!"

print(greet("world"))
EOF

# A genuinely unknown call target, for the refuse-by-name arm.
printf 'print(mystery("world"))\n' >"$work/unknown.lua"

(
    cd "$work" || exit 125
    "$idol" compile "$subject" --target wasm32-wasi -o "$work/lua.wasm"
) >"$work/lua.compile.out" 2>"$work/lua.compile.err"
lua_compile=$?

(
    cd "$work" || exit 125
    "$idol" compile "$work/hello.id" --target wasm32-wasi -o "$work/id.wasm"
) >"$work/id.compile.out" 2>"$work/id.compile.err"
id_compile=$?

lua_run=255
id_run=255
: >"$work/lua.out"
: >"$work/id.out"
if [ "$lua_compile" -eq 0 ]; then
    "$wasmtime" run "$work/lua.wasm" >"$work/lua.out" 2>"$work/lua.err"
    lua_run=$?
fi
if [ "$id_compile" -eq 0 ]; then
    "$wasmtime" run "$work/id.wasm" >"$work/id.out" 2>"$work/id.err"
    id_run=$?
fi

(
    cd "$work" || exit 125
    "$idol" compile "$work/unknown.lua" --target wasm32-wasi -o "$work/unknown.wasm"
) >"$work/unknown.out" 2>"$work/unknown.err"
unknown_compile=$?

printf 'Hello from duo!\nHello, world!\n' >"$work/expected"
ok=1
[ "$lua_compile" -eq 0 ] || ok=0
[ "$id_compile" -eq 0 ] || ok=0
[ "$lua_run" -eq 0 ] || ok=0
[ "$id_run" -eq 0 ] || ok=0
cmp -s "$work/expected" "$work/lua.out" || ok=0
cmp -s "$work/lua.out" "$work/id.out" || ok=0
# Refusal, and refusal BY NAME: the unknown callee's own spelling is in the
# diagnostic, not a generic failure some other defect could also produce.
[ "$unknown_compile" -ne 0 ] || ok=0
grep -q 'mystery' "$work/unknown.out" "$work/unknown.err" 2>/dev/null || ok=0

if [ "$ok" -ne 1 ]; then
    printf 'wasm/local: FAIL lua_compile=%s id_compile=%s lua_run=%s id_run=%s unknown_compile=%s\n' \
        "$lua_compile" "$id_compile" "$lua_run" "$id_run" "$unknown_compile" >&2
    printf '%s\n' '--- lua compile stderr' >&2
    sed -n '1,40p' "$work/lua.compile.err" >&2
    printf '%s\n' '--- id compile stderr' >&2
    sed -n '1,40p' "$work/id.compile.err" >&2
    printf '%s\n' '--- lua stdout' >&2
    sed -n '1,20p' "$work/lua.out" >&2
    printf '%s\n' '--- id stdout' >&2
    sed -n '1,20p' "$work/id.out" >&2
    printf '%s\n' '--- unknown compile output' >&2
    sed -n '1,20p' "$work/unknown.out" >&2
    sed -n '1,40p' "$work/unknown.err" >&2
    exit 1
fi

printf 'wasm/local: pass lua=id stdout under wasmtime; unknown callee refused by name\n'
