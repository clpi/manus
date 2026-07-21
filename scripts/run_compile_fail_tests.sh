#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
# Keep compile progress off stdout so `duo run` output assertions stay stable.
export DUO_BUILD_REPORT=plain
cd "$ROOT"

any_failed=0

# Avoid bash $(...) command substitution when capturing duo output: nested subshells
# can deadlock under Cursor's agent shell (unix socket stdio). Use temp files instead.
run_fail() {
    local file="$1" pattern="$2"
    local tmp
    tmp=$(mktemp)
    if "$DUO" check "$file" >"$tmp" 2>&1; then
        echo "FAIL: $file should not compile"
        cat "$tmp"
        any_failed=1
    elif grep -qF "$pattern" "$tmp"; then
        echo "OK:   $file  (expected error found)"
    else
        echo "FAIL: $file  expected pattern: $pattern"
        cat "$tmp"
        any_failed=1
    fi
    rm -f "$tmp"
}

run_ok() {
    local file="$1"
    local tmp
    tmp=$(mktemp)
    if "$DUO" check "$file" >"$tmp" 2>&1; then
        echo "OK:   $file  (check passes)"
    else
        echo "FAIL: $file  should compile but got:"
        cat "$tmp"
        any_failed=1
    fi
    rm -f "$tmp"
}

run_output() {
    local file="$1" expected="$2"
    local tmp want
    tmp=$(mktemp)
    if "$DUO" run "$file" >"$tmp" 2>&1; then
        want=$(printf '%b' "$expected")
        if [[ "$(<"$tmp")" == "$want" ]]; then
            echo "OK:   $file  (run output matches)"
        else
            echo "FAIL: $file  output mismatch"
            echo "--- want ---"
            echo "$want"
            echo "--- got ---"
            cat "$tmp"
            any_failed=1
        fi
    else
        echo "FAIL: $file  should compile+run but got:"
        cat "$tmp"
        any_failed=1
    fi
    rm -f "$tmp"
}

run_shell_ok() {
    local label="$1" script="$2"
    local tmp
    tmp=$(mktemp)
    if bash "$script" >"$tmp" 2>&1; then
        echo "OK:   $label"
    else
        echo "FAIL: $label failed:"
        cat "$tmp"
        any_failed=1
    fi
    rm -f "$tmp"
}

run_fail examples/compile_fail/global_star_read.lua    "use of undeclared global"
run_fail examples/compile_fail/implicit_global_read.lua "use of undeclared global"
run_fail examples/compile_fail/global_star_assign.lua  "attempt to assign to undeclared global"
run_fail examples/compile_fail/for_assign_num.lua      "cannot assign to for loop control variable"
run_fail examples/compile_fail/for_assign_gen.lua      "cannot assign to for loop control variable"
run_fail examples/compile_fail/const_local_assign.lua  "attempt to assign to const variable"
run_fail examples/compile_fail/const_no_init.lua       "must have an initializer"
run_fail examples/compile_fail/close_no_init.lua       "must have an initializer"
run_fail examples/compile_fail/vararg_rest_assign.lua  "read-only vararg table"
run_fail examples/compile_fail/global_const_assign.lua "attempt to assign to const variable"
run_fail examples/compile_fail/tensor_matmul_k_mismatch.duo "tensor matmul inner dimension mismatch"
run_fail examples/compile_fail/tensor_matmul_symbolic_k_mismatch.duo "tensor matmul inner dimension mismatch"
run_fail examples/compile_fail/tensor_broadcast_incompatible.duo "tensor broadcast incompatible shapes"
run_fail examples/compile_fail/tensor_return_mismatch.duo "return type mismatch"
run_ok   tests/test.lua
run_ok   examples/hello.lua
run_ok   examples/fib.lua
run_ok   examples/fib.duo
run_ok   examples/ml_showcase.duo
run_ok   examples/direct_table_iteration.duo
run_output examples/control_defaults_mem.duo "14\n16\n10\n"
run_output examples/metatable_class_semantics.duo "Vector(3, 4)\nVector(6, 8)\ntrue\n2\ntrue\n42\nmissing:anything\nVector\n"
run_output examples/compound_metamethods.duo "sub\nmul\ndiv\nmod\npow\n"
run_output examples/metamethod_operator_compat.duo "concat\ntrue\ntrue\nunm\nidiv\nband\nbor\nbxor\nbnot\nshl\nshr\n"
run_output examples/metamethod_gc.duo "1\n"
run_output examples/metamethod_iter.duo "60\n"
run_output examples/metamethod_pairs_ipairs.lua "15\n15\n"
run_output examples/typed_string_builtins.duo "abc\n42\nabc42\n7\n3\n"
run_output examples/layout_attrs_test.duo "6\n"
run_output examples/native_record_params.duo "4\n12\n"

run_shell_ok "Property 11 test passes" scripts/test_property_11.sh
run_shell_ok "Property 12 test passes" scripts/test_property_12.sh

echo ""
if [[ $any_failed -eq 0 ]]; then
    echo "All compile-fail tests passed"
else
    echo "Some tests FAILED"
    exit 1
fi
