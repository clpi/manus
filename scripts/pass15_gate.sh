#!/usr/bin/env sh
# Pass 15 semantic shell gate — cross-platform native. Prefer: zig build pass15-gate
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build pass15-gate
