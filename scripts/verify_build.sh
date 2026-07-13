#!/bin/sh
set -e
cd "$(dirname "$0")/.."
zig build 2>&1 | tee /tmp/duo_zig_build.log
echo "zig build OK"
zig build test 2>&1 | tee /tmp/duo_zig_test.log
echo "zig build test OK"
