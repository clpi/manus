#!/bin/sh
# Idol focused build + unit-test. For serialized/benchmark builds use the
# locked path (duo_lock.id via duo-bench MCP), not this script.
#
# Usage: build.sh [target]      e.g. build.sh unit-test
set -eu
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$repo"
if [ "$#" -gt 0 ]; then
  zig build --summary all "$@"
else
  echo '== zig build --summary all =='
  zig build --summary all
  echo
  echo '== zig build unit-test =='
  zig build unit-test
fi
