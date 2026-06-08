#!/usr/bin/env bash
# WAST (WebAssembly Script Test) harness for Duo.
#
# Covers two complementary test layers:
#   1. Pure WAT WAST files — verify WASM spec semantics via `wasmtime wast`
#   2. Duo binary WAST files — compile Duo @export libs, embed the binary in a
#      WAST file with WASI preview1 stubs, then test exported functions with
#      (assert_return ...) / (assert_trap ...) directives
#
# Requirements:
#   wasmtime  – https://wasmtime.dev
#   zig       – https://ziglang.org  (used to build duo if zig-out/bin/duo absent)
#   python3   – for WASM-to-hex conversion
#
# Run from the repo root after `zig build`.
set -euo pipefail

DUO="${DUO:-./zig-out/bin/duo}"
WASMTIME="${WASMTIME:-wasmtime}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1 ($2)"; SKIP=$((SKIP+1)); }

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── WASI preview1 stub provider ────────────────────────────────────────────────
# Injected at the top of every binary WAST file so that Duo's WASI-linked
# modules can be instantiated without a full WASI runtime.
WASI_STUBS='(module
  (func (export "args_get")            (param i32 i32) (result i32) (i32.const 0))
  (func (export "args_sizes_get")      (param i32 i32) (result i32) (i32.const 0))
  (func (export "environ_get")         (param i32 i32) (result i32) (i32.const 0))
  (func (export "environ_sizes_get")   (param i32 i32) (result i32) (i32.const 0))
  (func (export "clock_time_get")      (param i32 i64 i32) (result i32) (i32.const 0))
  (func (export "fd_close")            (param i32) (result i32) (i32.const 0))
  (func (export "fd_fdstat_get")       (param i32 i32) (result i32) (i32.const 0))
  (func (export "fd_prestat_get")      (param i32 i32) (result i32) (i32.const 8))
  (func (export "fd_prestat_dir_name") (param i32 i32 i32) (result i32) (i32.const 0))
  (func (export "fd_read")             (param i32 i32 i32 i32) (result i32) (i32.const 0))
  (func (export "fd_seek")             (param i32 i64 i32 i32) (result i32) (i32.const 0))
  (func (export "fd_write")            (param i32 i32 i32 i32) (result i32) (i32.const 0))
  (func (export "path_open")           (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32) (i32.const 0))
  (func (export "proc_exit")           (param i32) (unreachable))
  (func (export "sched_yield")         (result i32) (i32.const 0))
)
(register "wasi_snapshot_preview1")'

# ── Helpers ────────────────────────────────────────────────────────────────────

# Compile src to wasm in --lib mode. Prints .wasm path on success, empty on failure.
compile_lib() {
    local src="$1"
    local base
    base=$(basename "$src")
    local wasm="$TMPDIR_TEST/${base%.*}_lib.wasm"
    if "$DUO" compile "$src" --target wasm32-wasi --lib -o "$wasm" 2>/tmp/duo_wast_err; then
        echo "$wasm"
    else
        echo ""
    fi
}

# Convert a .wasm binary to a WAST hex string using python3.
wasm_to_wast_hex() {
    local wasm="$1"
    python3 -c "
import sys
with open('$wasm', 'rb') as f:
    data = f.read()
hex_str = ''.join('\\\\%02x' % b for b in data)
print(f'(module binary \"{hex_str}\")')
"
}

# Run a .wast file with wasmtime wast.
run_wast() {
    "$WASMTIME" wast "$1" 2>/dev/null
}

# Assert that a WAST file passes all directives.
assert_wast_file() {
    local label="$1" wast="$2"
    if ! command -v "$WASMTIME" &>/dev/null; then
        skip "$label" "wasmtime not found"
        return
    fi
    if run_wast "$wast"; then
        pass "$label"
    else
        fail "$label"
        # Show the directive that failed
        "$WASMTIME" wast "$wast" 2>&1 | head -6 | sed 's/^/    /' || true
    fi
}

# Build and run a binary WAST test from a Duo lib source + inline assertions.
assert_binary_wast() {
    local label="$1" src="$2"
    shift 2
    local assertions=("$@")   # remaining args are (assert_return ...) lines

    if ! command -v "$WASMTIME" &>/dev/null || ! command -v python3 &>/dev/null; then
        skip "$label" "wasmtime or python3 not found"
        return
    fi

    local wasm
    wasm=$(compile_lib "$src")
    if [[ -z "$wasm" ]]; then
        fail "$label — compile failed: $(cat /tmp/duo_wast_err 2>/dev/null | head -3)"
        return
    fi

    # Generate the WAST file: stubs + binary module + assertions
    local wast="$TMPDIR_TEST/$(basename "${src%.*}").wast"
    {
        echo "$WASI_STUBS"
        wasm_to_wast_hex "$wasm"
        for a in "${assertions[@]}"; do
            echo "$a"
        done
    } > "$wast"

    assert_wast_file "$label" "$wast"
}

# ── Section 1: Pure WAT WAST spec tests ───────────────────────────────────────
echo "=== WAST Spec Tests ==="
echo ""
echo "--- 1. Pure WAT: i64 arithmetic ---"

assert_wast_file "i64 add/sub/mul" tests/wast/arithmetic_i64.wast
assert_wast_file "i64 div/mod"     tests/wast/divmod_i64.wast
assert_wast_file "i64 bitwise"     tests/wast/bitwise_i64.wast
assert_wast_file "i64 comparison"  tests/wast/compare_i64.wast

echo ""
echo "--- 2. Pure WAT: f64 arithmetic ---"

assert_wast_file "f64 arithmetic"  tests/wast/arithmetic_f64.wast

echo ""
echo "--- 3. Pure WAT: control flow ---"

assert_wast_file "if/else"         tests/wast/control_if.wast
assert_wast_file "loops"           tests/wast/control_loop.wast
assert_wast_file "calls"           tests/wast/control_call.wast

echo ""
echo "--- 4. Pure WAT: memory ---"

assert_wast_file "memory load/store" tests/wast/memory_ops.wast

# ── Section 2: Duo binary WAST tests ─────────────────────────────────────────
echo ""
echo "--- 5. Duo binary: arithmetic exports ---"

assert_binary_wast "duo arithmetic: add" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "add" (i64.const 3) (i64.const 4)) (i64.const 7))' \
    '(assert_return (invoke "add" (i64.const 0) (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "add" (i64.const -1) (i64.const 1)) (i64.const 0))' \
    '(assert_return (invoke "add" (i64.const 100) (i64.const -200)) (i64.const -100))'

assert_binary_wast "duo arithmetic: sub" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "sub" (i64.const 10) (i64.const 3)) (i64.const 7))' \
    '(assert_return (invoke "sub" (i64.const 0) (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "sub" (i64.const 5) (i64.const 10)) (i64.const -5))'

assert_binary_wast "duo arithmetic: mul" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "mul" (i64.const 6) (i64.const 7)) (i64.const 42))' \
    '(assert_return (invoke "mul" (i64.const 0) (i64.const 100)) (i64.const 0))' \
    '(assert_return (invoke "mul" (i64.const -3) (i64.const 4)) (i64.const -12))'

assert_binary_wast "duo arithmetic: idiv/imod" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "idiv" (i64.const 10) (i64.const 3)) (i64.const 3))' \
    '(assert_return (invoke "idiv" (i64.const -7) (i64.const 2)) (i64.const -4))' \
    '(assert_return (invoke "imod" (i64.const 10) (i64.const 3)) (i64.const 1))' \
    '(assert_return (invoke "imod" (i64.const -7) (i64.const 3)) (i64.const 2))'

assert_binary_wast "duo arithmetic: bitwise" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "band" (i64.const 0xFF) (i64.const 0x0F)) (i64.const 15))' \
    '(assert_return (invoke "bor"  (i64.const 0xF0) (i64.const 0x0F)) (i64.const 255))' \
    '(assert_return (invoke "bxor" (i64.const 0xFF) (i64.const 0xFF)) (i64.const 0))' \
    '(assert_return (invoke "lshift" (i64.const 1) (i64.const 8)) (i64.const 256))' \
    '(assert_return (invoke "rshift" (i64.const 256) (i64.const 4)) (i64.const 16))'

assert_binary_wast "duo arithmetic: abs/max/min" \
    examples/wasm/lib/arithmetic.duo \
    '(assert_return (invoke "abs_val" (i64.const -5)) (i64.const 5))' \
    '(assert_return (invoke "abs_val" (i64.const 5)) (i64.const 5))' \
    '(assert_return (invoke "abs_val" (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "max_val" (i64.const 3) (i64.const 7)) (i64.const 7))' \
    '(assert_return (invoke "min_val" (i64.const 3) (i64.const 7)) (i64.const 3))'

echo ""
echo "--- 6. Duo binary: fibonacci ---"

assert_binary_wast "duo fibonacci: fib recursive" \
    examples/wasm/lib/fibonacci.duo \
    '(assert_return (invoke "fib" (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "fib" (i64.const 1)) (i64.const 1))' \
    '(assert_return (invoke "fib" (i64.const 2)) (i64.const 1))' \
    '(assert_return (invoke "fib" (i64.const 5)) (i64.const 5))' \
    '(assert_return (invoke "fib" (i64.const 10)) (i64.const 55))' \
    '(assert_return (invoke "fib" (i64.const 15)) (i64.const 610))'

assert_binary_wast "duo fibonacci: fib iterative" \
    examples/wasm/lib/fibonacci.duo \
    '(assert_return (invoke "fib_iter" (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "fib_iter" (i64.const 1)) (i64.const 1))' \
    '(assert_return (invoke "fib_iter" (i64.const 10)) (i64.const 55))' \
    '(assert_return (invoke "fib_iter" (i64.const 20)) (i64.const 6765))'

assert_binary_wast "duo fibonacci: factorial" \
    examples/wasm/lib/fibonacci.duo \
    '(assert_return (invoke "factorial" (i64.const 0)) (i64.const 1))' \
    '(assert_return (invoke "factorial" (i64.const 1)) (i64.const 1))' \
    '(assert_return (invoke "factorial" (i64.const 5)) (i64.const 120))' \
    '(assert_return (invoke "factorial" (i64.const 10)) (i64.const 3628800))'

assert_binary_wast "duo fibonacci: gcd/lcm" \
    examples/wasm/lib/fibonacci.duo \
    '(assert_return (invoke "gcd" (i64.const 12) (i64.const 8)) (i64.const 4))' \
    '(assert_return (invoke "gcd" (i64.const 100) (i64.const 75)) (i64.const 25))' \
    '(assert_return (invoke "gcd" (i64.const 7) (i64.const 13)) (i64.const 1))' \
    '(assert_return (invoke "lcm" (i64.const 4) (i64.const 6)) (i64.const 12))' \
    '(assert_return (invoke "lcm" (i64.const 3) (i64.const 5)) (i64.const 15))'

assert_binary_wast "duo fibonacci: pow_int" \
    examples/wasm/lib/fibonacci.duo \
    '(assert_return (invoke "pow_int" (i64.const 2) (i64.const 0)) (i64.const 1))' \
    '(assert_return (invoke "pow_int" (i64.const 2) (i64.const 10)) (i64.const 1024))' \
    '(assert_return (invoke "pow_int" (i64.const 3) (i64.const 4)) (i64.const 81))' \
    '(assert_return (invoke "pow_int" (i64.const 10) (i64.const 5)) (i64.const 100000))'

echo ""
echo "--- 7. Duo binary: predicates ---"

assert_binary_wast "duo predicates: even/odd" \
    examples/wasm/lib/predicates.duo \
    '(assert_return (invoke "is_even" (i64.const 0)) (i64.const 1))' \
    '(assert_return (invoke "is_even" (i64.const 2)) (i64.const 1))' \
    '(assert_return (invoke "is_even" (i64.const 3)) (i64.const 0))' \
    '(assert_return (invoke "is_odd" (i64.const 1)) (i64.const 1))' \
    '(assert_return (invoke "is_odd" (i64.const 4)) (i64.const 0))'

assert_binary_wast "duo predicates: sign" \
    examples/wasm/lib/predicates.duo \
    '(assert_return (invoke "sign" (i64.const 5)) (i64.const 1))' \
    '(assert_return (invoke "sign" (i64.const -5)) (i64.const -1))' \
    '(assert_return (invoke "sign" (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "is_positive" (i64.const 1)) (i64.const 1))' \
    '(assert_return (invoke "is_positive" (i64.const 0)) (i64.const 0))' \
    '(assert_return (invoke "is_negative" (i64.const -1)) (i64.const 1))'

assert_binary_wast "duo predicates: clamp/in_range" \
    examples/wasm/lib/predicates.duo \
    '(assert_return (invoke "clamp" (i64.const 5) (i64.const 0) (i64.const 10)) (i64.const 5))' \
    '(assert_return (invoke "clamp" (i64.const -1) (i64.const 0) (i64.const 10)) (i64.const 0))' \
    '(assert_return (invoke "clamp" (i64.const 15) (i64.const 0) (i64.const 10)) (i64.const 10))' \
    '(assert_return (invoke "in_range" (i64.const 5) (i64.const 0) (i64.const 10)) (i64.const 1))' \
    '(assert_return (invoke "in_range" (i64.const -1) (i64.const 0) (i64.const 10)) (i64.const 0))'

# ── Section 3: Full WAST test files ───────────────────────────────────────────
echo ""
echo "--- 8. Full WAST file tests ---"

for wast_file in tests/wast/*.wast; do
    [[ -f "$wast_file" ]] || continue
    label="wast: $(basename "$wast_file")"
    assert_wast_file "$label" "$wast_file"
done

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[ "$FAIL" -eq 0 ] || exit 1
