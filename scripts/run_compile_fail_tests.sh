#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
STATUS_DIR="$(mktemp -d)"
trap 'rm -rf "$STATUS_DIR"' EXIT
cd "$ROOT"

# Each test gets a unique index; we write results to $STATUS_DIR/<idx>.{status,msg}.
# Jobs run in parallel but results are printed in declaration order.

N=0
run_fail() {
    local idx=$N; N=$((N + 1))
    local file="$1" pattern="$2"
    (
        if out=$("$DUO" check "$file" 2>&1); then
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf 'FAIL: %s should not compile\n%s\n' "$file" "$out" > "$STATUS_DIR/$idx.msg"
        elif echo "$out" | grep -qF "$pattern"; then
            echo OK > "$STATUS_DIR/$idx.status"
            printf 'OK:   %s  (expected error found)\n' "$file" > "$STATUS_DIR/$idx.msg"
        else
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf 'FAIL: %s  expected pattern: %s\n%s\n' "$file" "$pattern" "$out" > "$STATUS_DIR/$idx.msg"
        fi
    ) &
}

run_ok() {
    local idx=$N; N=$((N + 1))
    local file="$1"
    (
        if out=$("$DUO" check "$file" 2>&1); then
            echo OK > "$STATUS_DIR/$idx.status"
            printf 'OK:   %s  (check passes)\n' "$file" > "$STATUS_DIR/$idx.msg"
        else
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf 'FAIL: %s  should compile but got:\n%s\n' "$file" "$out" > "$STATUS_DIR/$idx.msg"
        fi
    ) &
}

# Compile + run a .duo/.lua file and assert its stdout equals an expected
# string (newlines written as literal \n in the second argument).
run_output() {
    local idx=$N; N=$((N + 1))
    local file="$1" expected="$2"
    (
        if out=$("$DUO" run "$file" 2>&1); then
            local want
            want=$(printf '%b' "$expected")
            if [[ "$out" == "$want" ]]; then
                echo OK > "$STATUS_DIR/$idx.status"
                printf 'OK:   %s  (run output matches)\n' "$file" > "$STATUS_DIR/$idx.msg"
            else
                echo FAIL > "$STATUS_DIR/$idx.status"
                printf 'FAIL: %s  output mismatch\n--- want ---\n%s\n--- got ---\n%s\n' "$file" "$want" "$out" > "$STATUS_DIR/$idx.msg"
            fi
        else
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf 'FAIL: %s  should compile+run but got:\n%s\n' "$file" "$out" > "$STATUS_DIR/$idx.msg"
        fi
    ) &
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
run_ok   tests/test.lua
run_ok   examples/hello.lua
run_ok   examples/fib.lua
run_ok   examples/fib.duo
run_output examples/typed_string_builtins.duo "abc\n42\nabc42\n"
run_output examples/layout_attrs_test.duo "6\n"
run_output examples/native_record_params.duo "4\n12\n"
run_property_11() {
    local idx=$N; N=$((N + 1))
    (
        if out=$(bash scripts/test_property_11.sh 2>&1); then
            echo OK > "$STATUS_DIR/$idx.status"
            printf "OK:   Property 11 test passes\n" > "$STATUS_DIR/$idx.msg"
        else
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf "FAIL: Property 11 test failed:\n%s\n" "$out" > "$STATUS_DIR/$idx.msg"
        fi
    ) &
}
run_property_11

run_property_12() {
    local idx=$N; N=$((N + 1))
    (
        if out=$(bash scripts/test_property_12.sh 2>&1); then
            echo OK > "$STATUS_DIR/$idx.status"
            printf "OK:   Property 12 test passes\n" > "$STATUS_DIR/$idx.msg"
        else
            echo FAIL > "$STATUS_DIR/$idx.status"
            printf "FAIL: Property 12 test failed:\n%s\n" "$out" > "$STATUS_DIR/$idx.msg"
        fi
    ) &
}
run_property_12

TOTAL=$N

# Collect results in order
any_failed=0
for i in $(seq 0 $((TOTAL - 1))); do
    wait
    if [[ ! -f "$STATUS_DIR/$i.msg" ]] || [[ ! -f "$STATUS_DIR/$i.status" ]]; then
        echo "ERROR: Test $i did not complete (missing output files)"
        any_failed=1
        continue
    fi
    cat "$STATUS_DIR/$i.msg"
    [[ "$(< "$STATUS_DIR/$i.status")" == OK ]] || any_failed=1
done

echo ""
if [[ $any_failed -eq 0 ]]; then
    echo "All compile-fail tests passed"
else
    echo "Some tests FAILED"
    exit 1
fi
