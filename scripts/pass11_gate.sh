#!/usr/bin/env sh
# Pass 11 closure gate — cross-platform native core. Prefer: zig build pass11-gate
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build pass11-gate
