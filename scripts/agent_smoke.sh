#!/usr/bin/env bash
# Bootstrap wrapper: build duo, then delegate to Duo-native scripts/agent_smoke.duo.
# Runs under scripts/duo_lock.sh so concurrent agents never corrupt .zig-cache.
# Run: scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo
# Or:  ./scripts/agent_smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# DUO_ALREADY_BUILT tells the Duo script to skip its redundant inner `zig build`,
# which would otherwise spawn a second zig process that can collide with this one.
export DUO_ALREADY_BUILT=1

exec scripts/duo_lock.sh --timeout 1800 -- sh -c '
  zig build && exec ./zig-out/bin/duo run scripts/agent_smoke.duo
'
