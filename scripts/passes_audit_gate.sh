#!/usr/bin/env sh
# Comprehensive passes audit gate — cross-platform. Prefer: zig build passes-audit-gate
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
"$ZIG" build passes-audit-gate
