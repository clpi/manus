#!/usr/bin/env bash
# Pass 16 self-hosted compiler gate — cross-platform native. Prefer: zig build pass16-gate
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG="${ZIG:-$(command -v zig)}"
cd "$ROOT"
"$ZIG" build pass16-gate
