#!/usr/bin/env sh
# Pass 11 module smoke — cross-platform native. Prefer: zig build pass11-module-smoke
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build pass11-module-smoke
