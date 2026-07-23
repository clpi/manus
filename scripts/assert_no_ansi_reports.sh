#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="$ROOT/zig-out/bin/duo"

cd "$ROOT"

if [ ! -x "$DUO" ]; then
    "${ZIG:-zig}" build
fi

assert_escape_free() {
    local label="$1"
    local out="$2"
    if printf "%s" "$out" | LC_ALL=C grep "$(printf '\033')" >/dev/null; then
        echo "ANSI escape sequence leaked in $label"
        printf "%s\n" "$out"
        return 1
    fi
    printf "ok no-ansi %s\n" "$label"
}

assert_has_escape() {
    local label="$1"
    local out="$2"
    if ! printf "%s" "$out" | LC_ALL=C grep "$(printf '\033')" >/dev/null; then
        echo "ANSI styling missing in $label"
        printf "%s\n" "$out"
        return 1
    fi
    printf "ok ansi %s\n" "$label"
}

check_flag_report() {
    local style="$1"
    local out
    out="$("$DUO" test examples/directives_test.duo --no-color --test-report "$style" 2>&1)"
    assert_escape_free "--no-color $style" "$out"
}

check_env_report() {
    local style="$1"
    local out
    out="$(NO_COLOR=1 "$DUO" test examples/directives_test.duo --test-report "$style" 2>&1)"
    assert_escape_free "NO_COLOR=1 $style" "$out"
}

check_forced_color_report() {
    local style="$1"
    local out
    out="$(DUO_COLOR=1 "$DUO" test examples/directives_test.duo --test-report "$style" 2>&1)"
    assert_has_escape "DUO_COLOR=1 $style" "$out"
}

check_json_report() {
    local out
    out="$(DUO_COLOR=1 "$DUO" test examples/directives_test.duo --test-report json 2>&1)"
    assert_escape_free "DUO_COLOR=1 json" "$out"
    printf "%s\n" "$out" | python3 -c 'import json, sys
lines = [line for line in sys.stdin.read().splitlines() if line.strip()]
if not lines:
    raise SystemExit("json report produced no events")
for line in lines:
    json.loads(line)
if not any(json.loads(line).get("event") == "summary" for line in lines):
    raise SystemExit("json report missing summary event")
print("ok json DUO_COLOR=1 json")'
}

for style in pretty compact verbose; do
    check_flag_report "$style"
    check_env_report "$style"
    check_forced_color_report "$style"
done

check_json_report
