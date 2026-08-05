#!/usr/bin/env sh
# Pass 14 constructive evolution gate — cross-platform native. Prefer: zig build pass14-gate
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build pass14-gate
