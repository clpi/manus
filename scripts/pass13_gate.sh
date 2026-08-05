#!/usr/bin/env sh
# Pass 13 control plane gate — cross-platform native. Prefer: zig build pass13-gate
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build pass13-gate
