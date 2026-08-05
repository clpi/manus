#!/usr/bin/env sh
# Pass 11–14 native smoke — cross-platform wrapper (no jq). Prefer: zig build passes-11-14-smoke
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build passes-11-14-smoke
