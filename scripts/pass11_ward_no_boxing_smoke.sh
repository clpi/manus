#!/usr/bin/env bash
# Pass 11 WP-15 — native-barrier proofs for M1 classifier + honest Ward decode gap.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"

echo "pass11_ward_no_boxing_smoke: build duo (dump-c dependency)"
"$ZIG" build

echo "pass11_ward_no_boxing_smoke: barrier profile tests"
"$ZIG" test src/pass11_ward_barrier_tests.zig --test-filter "Pass 11 WP-15" --test-filter "WP-15"

echo "pass11_ward_no_boxing_smoke: PASS"
