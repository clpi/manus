#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"

# ── Parallel helpers ───────────────────────────────────────────────────────────
# Each _job call spawns a background subshell that writes two files:
#   $TMP/<idx>.status  — "OK" or "FAIL"
#   $TMP/<idx>.msg     — human-readable result line(s)
# After all jobs are launched, wait collects them, then results are printed in
# declaration order so output is deterministic regardless of completion order.

_fail_job() {
    local idx="$1" file="$2" pattern="$3"
    (
        set +e; out=$("$DUO" check "$file" 2>&1); rc=$?; set -e
        if [[ $rc -eq 0 ]]; then
            echo FAIL > "$TMP/$idx.status"
            printf 'FAIL: %s should not compile\n%s\n' "$file" "$out" > "$TMP/$idx.msg"
        elif echo "$out" | grep -qF "$pattern"; then
            echo OK > "$TMP/$idx.status"
            printf 'OK:   %s  (expected error found)\n' "$file" > "$TMP/$idx.msg"
        else
            echo FAIL > "$TMP/$idx.status"
            printf 'FAIL: %s  expected pattern: %s\n%s\n' "$file" "$pattern" "$out" > "$TMP/$idx.msg"
        fi
    ) &
}

_ok_job() {
    local idx="$1" file="$2"
    (
        if out=$("$DUO" check "$file" 2>&1); then
            echo OK > "$TMP/$idx.status"
            printf 'OK:   %s  (check passes)\n' "$file" > "$TMP/$idx.msg"
        else
            echo FAIL > "$TMP/$idx.status"
            printf 'FAIL: %s  should compile but got:\n%s\n' "$file" "$out" > "$TMP/$idx.msg"
        fi
    ) &
}

# ── Launch all tests in parallel ──────────────────────────────────────────────

pids=()
N=0
_fail_job $((N++)) examples/compile_fail/global_star_read.lua    "use of undeclared global" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/implicit_global_read.lua "use of undeclared global" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/global_star_assign.lua  "attempt to assign to undeclared global" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/for_assign_num.lua      "cannot assign to for loop control variable" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/for_assign_gen.lua      "cannot assign to for loop control variable" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/const_local_assign.lua  "attempt to assign to const variable" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/const_no_init.lua       "must have an initializer" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/close_no_init.lua       "must have an initializer" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/vararg_rest_assign.lua  "read-only vararg table" &
pids+=($!)
_fail_job $((N++)) examples/compile_fail/global_const_assign.lua "attempt to assign to const variable" &
pids+=($!)
_ok_job   $((N++)) tests/test.lua &
pids+=($!)
_ok_job   $((N++)) examples/hello.lua &
pids+=($!)
_ok_job   $((N++)) examples/fib.lua &
pids+=($!)
_ok_job   $((N++)) examples/fib.duo &
pids+=($!)
TOTAL=$N

# ── Collect results (in declaration order) ────────────────────────────────────

for pid in "${pids[@]}"; do
    wait "$pid"
done

any_failed=0
for i in $(seq 0 $((TOTAL - 1))); do
    if [[ ! -f "$TMP/$i.msg" ]] || [[ ! -f "$TMP/$i.status" ]]; then
        echo "ERROR: Test $i did not complete (missing output files)"
        any_failed=1
        continue
    fi
    cat "$TMP/$i.msg"
    [[ "$(cat "$TMP/$i.status")" == OK ]] || any_failed=1
done

echo ""
if [[ $any_failed -eq 0 ]]; then
    echo "All compile-fail tests passed"
else
    echo "Some tests FAILED"
    exit 1
fi
