#!/usr/bin/env bash
# WASI execution test harness.
#
# For every program in examples/wasm/ this script:
#   1. Compiles it to a .wasm binary via `duo compile --target wasm32-wasi`
#   2. Runs it with wasmtime and captures stdout
#   3. Asserts stdout equals the hard-coded expected string
#   4. (where wabt is available) validates module structure with wasm-objdump:
#      - memory export present
#      - _start export present
#      - wasi_snapshot_preview1 imports present
#
# Requirements:
#   wasmtime  – https://wasmtime.dev/install.sh
#   wabt      – `apt install wabt` or https://github.com/WebAssembly/wabt/releases
#
# Run after `zig build` so zig-out/bin/duo is up to date.
set -euo pipefail

DUO="${DUO:-./zig-out/bin/duo}"
WASMTIME="${WASMTIME:-wasmtime}"
WASM_OBJDUMP="${WASM_OBJDUMP:-wasm-objdump}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1 ($2)"; SKIP=$((SKIP+1)); }

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────

# Compile src to wasm. Prints the .wasm path on success, empty on failure.
compile_wasm() {
    local src="$1"
    local base
    base=$(basename "$src")
    local wasm="$TMPDIR_TEST/${base%.*}.wasm"
    if "$DUO" compile "$src" --target wasm32-wasi -o "$wasm" 2>/tmp/duo_compile_err; then
        echo "$wasm"
    else
        echo ""
    fi
}

# Run a .wasm file with wasmtime; print stdout.  Returns non-zero on crash.
run_wasm() {
    "$WASMTIME" run "$1" 2>/dev/null
}

# Assert that compiling src and running it produces exactly `expected` on stdout.
assert_output() {
    local label="$1" src="$2" expected="$3"

    if ! command -v "$WASMTIME" &>/dev/null; then
        skip "$label" "wasmtime not found"
        return
    fi

    local wasm
    wasm=$(compile_wasm "$src")
    if [[ -z "$wasm" ]]; then
        fail "$label — compile failed: $(cat /tmp/duo_compile_err 2>/dev/null | head -3)"
        return
    fi

    local actual
    if ! actual=$(run_wasm "$wasm"); then
        fail "$label — wasmtime exited non-zero"
        return
    fi

    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label — output mismatch
      expected: $(printf '%q' "$expected")
      got:      $(printf '%q' "$actual")"
    fi
}

# Assert that a compiled .wasm passes structural checks (WAST-style module assertions).
assert_module_structure() {
    local label="$1" src="$2"

    if ! command -v "$WASMTIME" &>/dev/null; then
        skip "$label (structure: compile)" "wasmtime not found"
        return
    fi

    local wasm
    wasm=$(compile_wasm "$src")
    if [[ -z "$wasm" ]]; then
        fail "$label (structure) — compile failed"
        return
    fi

    # wasm-validate: binary is a well-formed WebAssembly module
    if command -v wasm-validate &>/dev/null; then
        if wasm-validate "$wasm" 2>/dev/null; then
            pass "$label — wasm-validate: well-formed module"
        else
            fail "$label — wasm-validate: malformed module"
        fi
    fi

    if ! command -v "$WASM_OBJDUMP" &>/dev/null; then
        skip "$label (structure checks)" "wasm-objdump not found"
        return
    fi

    local details
    details=$("$WASM_OBJDUMP" -x "$wasm" 2>/dev/null)

    # Must export `memory` (WASI requires it)
    if echo "$details" | grep -q "memory"; then
        pass "$label — exports memory"
    else
        fail "$label — missing memory export"
    fi

    # Must export `_start` (WASI entry point)
    if echo "$details" | grep -q "_start"; then
        pass "$label — exports _start"
    else
        fail "$label — missing _start export"
    fi

    # Must import from wasi_snapshot_preview1
    if echo "$details" | grep -q "wasi_snapshot_preview1"; then
        pass "$label — imports wasi_snapshot_preview1"
    else
        fail "$label — missing wasi_snapshot_preview1 imports"
    fi

    # Must NOT import anything from __wasi_unstable (old ABI — we target preview1 only)
    if echo "$details" | grep -q "__wasi_unstable"; then
        fail "$label — unexpected __wasi_unstable import"
    else
        pass "$label — no deprecated __wasi_unstable ABI"
    fi
}

# ── Section 1: hello world ────────────────────────────────────────────────────
echo "=== WASI Execution Tests ==="
echo ""
echo "--- 1. hello world ---"

assert_output "hello.lua: print two lines" \
    examples/wasm/hello.lua \
    "$(printf 'hello wasm\nfrom duo!')"

assert_module_structure "hello.lua" examples/wasm/hello.lua

# ── Section 2: arithmetic ──────────────────────────────────────────────────────
echo ""
echo "--- 2. arithmetic ---"

assert_output "arithmetic.lua: basic ops" \
    examples/wasm/arithmetic.lua \
    "$(printf '3\n12\n3\n5\n256.0\n2')"

# ── Section 3: string library ─────────────────────────────────────────────────
echo ""
echo "--- 3. string library ---"

assert_output "strings.lua: string ops" \
    examples/wasm/strings.lua \
    "$(printf 'hello\n5\nhello world\nHELLO\nhel\nababab')"

# ── Section 4: tables and for loops ───────────────────────────────────────────
echo ""
echo "--- 4. tables and for loops ---"

assert_output "tables.lua: ipairs + numeric for" \
    examples/wasm/tables.lua \
    "$(printf '10\n20\n30\n15')"

assert_module_structure "tables.lua" examples/wasm/tables.lua

# ── Section 5: fibonacci (untyped) ────────────────────────────────────────────
echo ""
echo "--- 5. fibonacci ---"

assert_output "fib.lua: fib(10)=55 then fib(0..5)" \
    examples/wasm/fib.lua \
    "$(printf '55\n0\n1\n1\n2\n3\n5')"

assert_module_structure "fib.lua" examples/wasm/fib.lua

# ── Section 6: typed fibonacci (duo) ──────────────────────────────────────────
echo ""
echo "--- 6. typed fibonacci (.duo) ---"

assert_output "typed_fib.duo: fib(10)=55 fib(15)=610" \
    examples/wasm/typed_fib.duo \
    "$(printf '55\n610')"

assert_module_structure "typed_fib.duo" examples/wasm/typed_fib.duo

# ── Section 7: math library ───────────────────────────────────────────────────
echo ""
echo "--- 7. math library ---"

assert_output "math_funcs.lua: math stdlib" \
    examples/wasm/math_funcs.lua \
    "$(printf '42\n5\n2\n3\n4\n4.0\ninteger\nfloat')"

# ── Section 8: existing examples compile and run ──────────────────────────────
echo ""
echo "--- 8. canonical examples ---"

assert_output "examples/hello.lua: greet output" \
    examples/hello.lua \
    "$(printf 'Hello from duo!\nHello, world!')"

assert_module_structure "examples/hello.lua" examples/hello.lua

# ── Section 9: binary size check ─────────────────────────────────────────────
echo ""
echo "--- 9. WASM binary size ---"

if command -v "$WASMTIME" &>/dev/null; then
    HELLO_WASM="$TMPDIR_TEST/hello_size.wasm"
    if "$DUO" compile examples/hello.lua --target wasm32-wasi -o "$HELLO_WASM" 2>/dev/null; then
        SIZE=$(wc -c < "$HELLO_WASM")
        # Sanity bounds: >1 KB (has runtime) and <10 MB (not bloated)
        if (( SIZE > 1024 && SIZE < 10485760 )); then
            pass "hello.wasm size ${SIZE} bytes is reasonable (1KB–10MB)"
        else
            fail "hello.wasm size ${SIZE} bytes is out of expected range"
        fi
    else
        fail "hello.lua compile failed for size check"
    fi
else
    skip "binary size check" "wasmtime not found"
fi

# ── Section 10: WASI module validation (wasm-validate) ────────────────────────
echo ""
echo "--- 10. wasm-validate on all compiled modules ---"

if command -v wasm-validate &>/dev/null && command -v "$WASMTIME" &>/dev/null; then
    for src in examples/wasm/*.lua examples/wasm/*.duo; do
        [[ -f "$src" ]] || continue
        base=$(basename "$src")
        wasm=$(compile_wasm "$src")
        if [[ -n "$wasm" ]]; then
            if wasm-validate "$wasm" 2>/dev/null; then
                pass "wasm-validate: $base"
            else
                fail "wasm-validate: $base — invalid module"
            fi
        else
            fail "compile: $base"
        fi
    done
else
    skip "wasm-validate sweep" "wasm-validate or wasmtime not available"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[ "$FAIL" -eq 0 ] || exit 1
