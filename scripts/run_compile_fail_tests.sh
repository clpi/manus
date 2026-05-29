#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"

cd "$ROOT"

expect_fail() {
    local file="$1"
    local pattern="$2"
    local out
    if out=$("$DUO" check "$file" 2>&1); then
        echo "FAIL: $file should not compile"
        echo "$out"
        exit 1
    fi
    if echo "$out" | grep -qF "$pattern"; then
        echo "OK: $file"
    else
        echo "FAIL: $file expected pattern: $pattern"
        echo "$out"
        exit 1
    fi
}

expect_fail examples/compile_fail/global_star_read.lua "use of undeclared global"
expect_fail examples/compile_fail/implicit_global_read.lua "use of undeclared global"
expect_fail examples/compile_fail/global_star_assign.lua "attempt to assign to undeclared global"
expect_fail examples/compile_fail/for_assign_num.lua "cannot assign to for loop control variable"
expect_fail examples/compile_fail/for_assign_gen.lua "cannot assign to for loop control variable"

expect_fail examples/compile_fail/const_local_assign.lua "attempt to assign to const variable"
expect_fail examples/compile_fail/const_no_init.lua "must have an initializer"
expect_fail examples/compile_fail/close_no_init.lua "must have an initializer"
expect_fail examples/compile_fail/vararg_rest_assign.lua "read-only vararg table"
expect_fail examples/compile_fail/global_const_assign.lua "attempt to assign to const variable"

echo "All compile-fail tests passed"
